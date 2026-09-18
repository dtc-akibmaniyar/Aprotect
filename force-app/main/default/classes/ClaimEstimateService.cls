/**
 * Estimate lifecycle (Add / Edit / Remove Scenario in the HTML calculator)
 * and the Create Work Order transaction.
 *
 * Remove deletes the Part__c / Service__c / Shop_Supply__c children
 * explicitly: their lookups to Estimate__c are SetNull, so deleting the
 * estimate alone would orphan them, not remove them.
 *
 * Create Work Order, in one transaction:
 *   1. Work_Order__c with its existing Estimate__c lookup set (source of
 *      truth for "which estimate won").
 *   2. Estimate__c.Is_Selected__c = true on the chosen estimate, false on
 *      its siblings, kept in step with the lookup above.
 *   3. One Claim_Line_Item__c per charge (Part / Labour / Supplies) from the
 *      estimate's children. Amount__c is what A-Protect owes the vendor.
 *   4. Work_Order_Line_Item__c rows generated FROM those Claim Line Items.
 *      Price__c is populated because Work_Order__c.Total_Line_Items_Cost__c
 *      rolls it up.
 */
public with sharing class ClaimEstimateService {

    public class WorkOrderResult {
        @AuraEnabled public Id workOrderId          { get; set; }
        @AuraEnabled public Integer claimLineItems  { get; set; }
        @AuraEnabled public Integer workOrderLines  { get; set; }
    }

    // ───────────────────────── Estimate lifecycle ─────────────────────────

    @AuraEnabled
    public static Estimate__c createEstimate(Id claimId, Id repairShopId, String estimateName) {
        Estimate__c e = new Estimate__c(
            Claim__c        = claimId,
            Repair_Shop__c  = repairShopId,
            Estimate_Name__c = estimateName
        );
        if (repairShopId != null) {
            Repair_Shop__c shop = [SELECT Labour_Rate_On_File__c FROM Repair_Shop__c WHERE Id = :repairShopId];
            e.Labour_Rate__c = shop.Labour_Rate_On_File__c;
        }
        insert e;
        return e;
    }

    /** Saves the edited inputs, then re-stamps the totals so they never drift. */
    @AuraEnabled
    public static ClaimPricingService.PricingResult updateEstimate(Estimate__c estimate, Decimal cap) {
        update estimate;
        return ClaimPricingService.recalculateAndStamp(estimate.Id, cap);
    }

    @AuraEnabled
    public static void deleteEstimate(Id estimateId) {
        Savepoint sp = Database.setSavepoint();
        try {
            delete [SELECT Id FROM Part__c        WHERE Estimate__c = :estimateId];
            delete [SELECT Id FROM Service__c     WHERE Estimate__c = :estimateId];
            delete [SELECT Id FROM Shop_Supply__c WHERE Estimate__c = :estimateId];
            delete [SELECT Id FROM Estimate__c    WHERE Id = :estimateId];
        } catch (Exception ex) {
            Database.rollback(sp);
            throw new AuraHandledException('Could not remove estimate: ' + ex.getMessage());
        }
    }

    // ───────────────────────── Create Work Order ──────────────────────────

    @AuraEnabled
    public static WorkOrderResult createWorkOrder(Id estimateId) {
        Estimate__c est = [
            SELECT Id, Claim__c, Repair_Shop__c,
                   (SELECT Id FROM Work_Orders__r LIMIT 1)
            FROM Estimate__c WHERE Id = :estimateId
        ];
        if (!est.Work_Orders__r.isEmpty()) {
            throw new AuraHandledException('A work order already exists for this estimate.');
        }

        Savepoint sp = Database.setSavepoint();
        try {
            // 1. Work order header. Its totals are formulas over the line items
            //    (Total_Line_Items_Cost__c rolls up Price__c, Tax_13__c and
            //    Total_Repair_Cost__c derive from that) and its coverage /
            //    deductible come from Estimate__r.Claim__r.Package__r, so only
            //    the relationships are set here.
            Work_Order__c wo = new Work_Order__c(
                Claim__c       = est.Claim__c,
                Estimate__c    = est.Id,
                Repair_Shop__c = est.Repair_Shop__c
            );
            insert wo;

            // 2. Selection flag: exactly one per claim.
            List<Estimate__c> siblings = [SELECT Id, Is_Selected__c FROM Estimate__c WHERE Claim__c = :est.Claim__c];
            for (Estimate__c s : siblings) s.Is_Selected__c = (s.Id == est.Id);
            update siblings;

            // 3. Claim line items, one per charge.
            List<Claim_Line_Item__c> lines = buildClaimLineItems(est);
            insert lines;

            // 4. Work order line items generated from the claim line items.
            List<Work_Order_Line_Item__c> woLines = new List<Work_Order_Line_Item__c>();
            for (Claim_Line_Item__c cli : lines) {
                Work_Order_Line_Item__c wl = new Work_Order_Line_Item__c(
                    Customer_Work_Order__c        = wo.Id,
                    Service_Repair_Description__c = cli.Description__c,
                    Description__c                = cli.Description__c,
                    Repair_Shop__c                = cli.Repair_Shop__c,
                    Price__c                      = cli.Amount__c,
                    Wholesale__c                  = cli.Amount__c
                );
                if (cli.Line_Type__c == 'Labour') {
                    wl.Wholesale_Labour_Rate_HR__c = cli.Rate__c;
                    if (cli.Hours__c != null) wl.Repair_Time_Adj__c = cli.Hours__c.setScale(0, RoundingMode.HALF_UP);
                }
                woLines.add(wl);
            }
            insert woLines;

            WorkOrderResult r = new WorkOrderResult();
            r.workOrderId    = wo.Id;
            r.claimLineItems = lines.size();
            r.workOrderLines = woLines.size();
            return r;
        } catch (Exception ex) {
            Database.rollback(sp);
            throw new AuraHandledException('Could not create work order: ' + ex.getMessage());
        }
    }

    private static List<Claim_Line_Item__c> buildClaimLineItems(Estimate__c est) {
        List<Claim_Line_Item__c> out = new List<Claim_Line_Item__c>();

        for (Part__c p : [
            SELECT Part_Name__c, Description__c, Part_Code__c, Part_Cost_Wholesale__c, Part_Cost__c,
                   Supplier__c, Repair_Shop__c
            FROM Part__c WHERE Estimate__c = :est.Id
        ]) {
            out.add(new Claim_Line_Item__c(
                Claim__c          = est.Claim__c,
                Line_Type__c      = 'Part',
                Role__c           = 'Parts Supplier',
                Description__c    = firstNonBlank(p.Part_Name__c, p.Description__c),
                Part_Code__c      = p.Part_Code__c,
                Parts_Supplier__c = p.Supplier__c,
                Repair_Shop__c    = p.Repair_Shop__c,
                Amount__c         = nz(p.Part_Cost_Wholesale__c != null ? p.Part_Cost_Wholesale__c : p.Part_Cost__c)
            ));
        }

        for (Service__c s : [
            SELECT Service_Repair_Description__c, Item_Desription__c, Repair_Time_Adj__c, Repair_Time_EST__c,
                   Time__c, Wholesale_Labour_Rate_HR__c, Wholesale__c, Cost__c, Repair_Shop__c
            FROM Service__c WHERE Estimate__c = :est.Id
        ]) {
            Decimal hrs = s.Repair_Time_Adj__c != null ? s.Repair_Time_Adj__c : s.Repair_Time_EST__c;
            if (hrs == null && String.isNotBlank(s.Time__c)) {
                try { hrs = Decimal.valueOf(s.Time__c.trim()); } catch (Exception ignored) { hrs = null; }
            }
            out.add(new Claim_Line_Item__c(
                Claim__c       = est.Claim__c,
                Line_Type__c   = 'Labour',
                Role__c        = 'Repair Shop',
                Description__c = firstNonBlank(s.Service_Repair_Description__c, s.Item_Desription__c),
                Hours__c       = hrs,
                Rate__c        = s.Wholesale_Labour_Rate_HR__c,
                Repair_Shop__c = s.Repair_Shop__c,
                Amount__c      = nz(s.Wholesale__c != null ? s.Wholesale__c : s.Cost__c)
            ));
        }

        for (Shop_Supply__c ss : [
            SELECT Item_Name__c, Item_Description__c, Cost__c, Charge__c, Repair_Shop__c
            FROM Shop_Supply__c WHERE Estimate__c = :est.Id
        ]) {
            out.add(new Claim_Line_Item__c(
                Claim__c       = est.Claim__c,
                Line_Type__c   = 'Supplies',
                Role__c        = 'Repair Shop',
                Description__c = firstNonBlank(ss.Item_Name__c, ss.Item_Description__c),
                Repair_Shop__c = ss.Repair_Shop__c,
                Amount__c      = nz(ss.Cost__c != null ? ss.Cost__c : ss.Charge__c)
            ));
        }
        return out;
    }

    private static String firstNonBlank(String a, String b) {
        if (String.isNotBlank(a)) return a.abbreviate(255);
        if (String.isNotBlank(b)) return b.abbreviate(255);
        return null;
    }
    private static Decimal nz(Decimal d) { return d == null ? 0 : d; }
}