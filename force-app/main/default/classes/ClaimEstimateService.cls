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
 *
 * FLS/CRUD hardening (Sep 22, Osama's explicit request after asking whether
 * this LWC-facing service enforces profile-based security): "with sharing"
 * only enforces record-level sharing, never field-level security or object
 * CRUD by itself, so every SOQL query here runs WITH USER_MODE and every
 * insert/update/delete goes through Database.<op>(records, AccessLevel.
 * USER_MODE) rather than a bare DML statement - the platform throws
 * (System.NoAccessException, wrapped below as AuraHandledException) instead
 * of silently writing/reading past a missing grant. (First attempt used
 * WITH SECURITY_ENFORCED / Security.stripInaccessible - this org's API
 * version rejects SECURITY_ENFORCED as deprecated in favor of USER_MODE,
 * which - bonus - also works on queries with subqueries, unlike
 * SECURITY_ENFORCED, so nothing here is exempted the way an earlier pass
 * assumed.)
 */
public with sharing class ClaimEstimateService {

    public class WorkOrderResult {
        @AuraEnabled public Id workOrderId          { get; set; }
        @AuraEnabled public Integer claimLineItems  { get; set; }
        @AuraEnabled public Integer workOrderLines  { get; set; }
    }

    // ───────────────────────── Estimate lifecycle ─────────────────────────

    /**
     * Backs the Estimates tab's custom related list (claimEstimatesList LWC).
     * Deliberately NOT cacheable (Sep 22 fix): this list must show the
     * result of a just-completed Manage Estimates save immediately, and an
     * imperative call to a cacheable method can still be served the
     * framework's cached response with no refreshApex equivalent to bust
     * it - claimEstimatesList calls this directly (not via @wire) precisely
     * so every call is guaranteed fresh.
     */
    @AuraEnabled
    public static List<Estimate__c> getEstimatesForClaim(Id claimId) {
        return [
            SELECT Id, Name, Estimate_Name__c, Repair_Shop__c, Repair_Shop__r.Name,
                   Source__c, Retail_Total__c, Is_Selected__c
            FROM Estimate__c
            WHERE Claim__c = :claimId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
        ];
    }

    /**
     * Full editable detail for every estimate on a claim - backs the Repair
     * Price Scenarios grid loading existing estimates for editing (Sep 22),
     * not just the summary columns getEstimatesForClaim returns for the
     * related list. Deliberately NOT cacheable, same reason as
     * getEstimatesForClaim above - reopening this screen after a save must
     * show the just-saved values, not a stale cached response.
     */
    @AuraEnabled
    public static List<Estimate__c> getEstimateDetailsForClaim(Id claimId) {
        return [
            SELECT Id, Estimate_Name__c, Repair_Shop__c, Repair_Shop__r.Tax_Percentage__c, Source__c,
                   Part_Component__c, Job_Type__c,
                   Parts_Supplier__c, Part_Code__c, Stock_Number__c, Condition__c, KMs__c,
                   Insurance_Source__c, Insurance_Amount__c, Parts_Cost__c, Labour_Hours__c, Labour_Rate__c,
                   Shop_Supplies__c, Shop_Supplies_Retail__c, Retail_Price__c, Deductable__c, Is_Selected__c
            FROM Estimate__c
            WHERE Claim__c = :claimId
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ];
    }

    @AuraEnabled
    public static Estimate__c createEstimate(Id claimId, Id repairShopId, String estimateName) {
        Estimate__c e = new Estimate__c(
            Claim__c        = claimId,
            Repair_Shop__c  = repairShopId,
            Estimate_Name__c = estimateName
        );
        if (repairShopId != null) {
            Repair_Shop__c shop = [
                SELECT Labour_Rate_On_File__c FROM Repair_Shop__c
                WHERE Id = :repairShopId
                WITH USER_MODE
            ];
            e.Labour_Rate__c = shop.Labour_Rate_On_File__c;
        }
        insertSecured(new List<Estimate__c>{ e });
        return e;
    }

    /** Saves the edited inputs, then re-stamps the totals so they never drift. */
    @AuraEnabled
    public static ClaimPricingService.PricingResult updateEstimate(Estimate__c estimate, Decimal cap) {
        updateSecured(new List<Estimate__c>{ estimate });
        return ClaimPricingService.recalculateAndStamp(estimate.Id, cap);
    }

    /**
     * Marks one estimate selected and clears the flag on every sibling on the
     * same claim. Called directly from the Repair Price Scenarios grid's USE
     * radio at save time (Sep 22 decision) - a preview of the eventual
     * winner, ahead of Create Work Order. createWorkOrder calls the same
     * shared helper, so whichever estimate actually becomes the work order
     * always wins the flag in the end, regardless of what was marked here.
     */
    @AuraEnabled
    public static void selectEstimate(Id estimateId) {
        Estimate__c est = [
            SELECT Id, Claim__c FROM Estimate__c
            WHERE Id = :estimateId
            WITH USER_MODE
        ];
        markSelected(est.Id, est.Claim__c);
    }

    private static void markSelected(Id estimateId, Id claimId) {
        List<Estimate__c> siblings = [
            SELECT Id, Is_Selected__c FROM Estimate__c
            WHERE Claim__c = :claimId
            WITH USER_MODE
        ];
        for (Estimate__c s : siblings) s.Is_Selected__c = (s.Id == estimateId);
        updateSecured(siblings);
    }

    @AuraEnabled
    public static void deleteEstimate(Id estimateId) {
        Savepoint sp = Database.setSavepoint();
        try {
            deleteSecured([SELECT Id FROM Part__c        WHERE Estimate__c = :estimateId WITH USER_MODE]);
            deleteSecured([SELECT Id FROM Service__c     WHERE Estimate__c = :estimateId WITH USER_MODE]);
            deleteSecured([SELECT Id FROM Shop_Supply__c WHERE Estimate__c = :estimateId WITH USER_MODE]);
            deleteSecured([SELECT Id FROM Estimate__c    WHERE Id = :estimateId          WITH USER_MODE]);
        } catch (Exception ex) {
            Database.rollback(sp);
            throw new AuraHandledException('Could not remove estimate: ' + ex.getMessage());
        }
    }

    /**
     * Bulk equivalent of createEstimate + updateEstimate + deleteEstimate +
     * selectEstimate combined - saves every row of the Repair Price
     * Scenarios grid in ONE Apex call instead of one call per row (Sep 22
     * fix: Save All Estimates was taking 6-7 seconds with several rows,
     * because the LWC previously awaited a separate round trip per row in
     * a for loop - each @AuraEnabled call has real fixed network/platform
     * overhead on top of its own work, so N rows meant N+ sequential round
     * trips. This collapses the whole save into a handful of bulk SOQL/DML
     * statements in one transaction, so total time barely grows with row
     * count.
     *
     * estimates: one entry per row currently in the grid, Id populated for
     * an existing row (update) or blank for a new one (insert); the row
     * with Is_Selected__c = true (at most one) becomes the claim's selected
     * estimate, same meaning as selectEstimate/createWorkOrder's flag.
     * deleteIds: estimates removed from the grid since it was opened -
     * deleted along with their Part__c/Service__c/Shop_Supply__c children,
     * batched across every removed estimate rather than one delete per id.
     */
    @AuraEnabled
    public static void saveEstimates(Id claimId, List<Estimate__c> estimates, List<Id> deleteIds) {
        Savepoint sp = Database.setSavepoint();
        try {
            if (deleteIds != null && !deleteIds.isEmpty()) {
                deleteSecured([SELECT Id FROM Part__c        WHERE Estimate__c IN :deleteIds WITH USER_MODE]);
                deleteSecured([SELECT Id FROM Service__c     WHERE Estimate__c IN :deleteIds WITH USER_MODE]);
                deleteSecured([SELECT Id FROM Shop_Supply__c WHERE Estimate__c IN :deleteIds WITH USER_MODE]);
                deleteSecured([SELECT Id FROM Estimate__c    WHERE Id IN :deleteIds          WITH USER_MODE]);
            }
            if (estimates == null || estimates.isEmpty()) return;

            List<Estimate__c> toInsert = new List<Estimate__c>();
            List<Estimate__c> toUpdate = new List<Estimate__c>();
            Set<Id> shopIds = new Set<Id>();
            for (Estimate__c e : estimates) {
                if (e.Repair_Shop__c != null) shopIds.add(e.Repair_Shop__c);
                if (e.Id == null) { e.Claim__c = claimId; toInsert.add(e); }
                else toUpdate.add(e);
            }

            // One query for every shop referenced across every row, instead
            // of one per row - same bulk principle as the round-trip fix.
            Map<Id, Repair_Shop__c> shopsById = new Map<Id, Repair_Shop__c>([
                SELECT Id, Labour_Rate_On_File__c, Tax_Percentage__c
                FROM Repair_Shop__c WHERE Id IN :shopIds
                WITH USER_MODE
            ]);
            for (Estimate__c e : toInsert) {
                if (e.Labour_Rate__c == null && e.Repair_Shop__c != null) {
                    Repair_Shop__c shop = shopsById.get(e.Repair_Shop__c);
                    if (shop != null) e.Labour_Rate__c = shop.Labour_Rate_On_File__c;
                }
            }

            insertSecured(toInsert);  // populates Id on toInsert's records, same objects referenced in estimates
            updateSecured(toUpdate);

            // Recompute + stamp totals for every row from the already-known
            // shop data and one shared claim-level cap/deductible lookup -
            // no per-row query, matching the same bulk principle throughout.
            Claim__c claim = [
                SELECT Application_Package__r.Per_Claim_Limit__c, Application_Package__r.Deductible__c
                FROM Claim__c WHERE Id = :claimId
                WITH USER_MODE
            ];
            Decimal claimCap = claim.Application_Package__r?.Per_Claim_Limit__c;
            Decimal claimDed = claim.Application_Package__r?.Deductible__c;

            List<Estimate__c> toStamp = new List<Estimate__c>();
            for (Estimate__c e : estimates) {
                Repair_Shop__c shop = e.Repair_Shop__c != null ? shopsById.get(e.Repair_Shop__c) : null;
                ClaimPricingService.PricingInput i = new ClaimPricingService.PricingInput();
                i.parts      = e.Parts_Cost__c;
                i.hrs        = e.Labour_Hours__c;
                i.rate       = e.Labour_Rate__c != null ? e.Labour_Rate__c : shop?.Labour_Rate_On_File__c;
                i.ins        = e.Insurance_Amount__c;
                i.supC       = e.Shop_Supplies__c;
                i.supR       = e.Shop_Supplies_Retail__c;
                i.retail     = e.Retail_Price__c;
                i.ded        = e.Deductable__c != null ? e.Deductable__c : claimDed;
                i.taxPercent = shop?.Tax_Percentage__c;
                i.cap        = claimCap;
                ClaimPricingService.PricingResult r = ClaimPricingService.calculate(i);
                toStamp.add(new Estimate__c(
                    Id                        = e.Id,
                    Labour_Cost__c            = r.labour,
                    Wholesale_Cost__c         = r.wsTotal,
                    Coverage_Applied__c       = r.coverage,
                    Customer_Pays__c          = r.custPre,
                    Customer_Pays_With_Tax__c = r.custTax,
                    Profit_Loss__c            = r.pl,
                    Retail_Total__c           = r.retailTotal,
                    // Sep 22 (Osama): write back the deductible actually
                    // used - the estimate's own override if one was set,
                    // otherwise the claim's - so the record shows the real
                    // number instead of staying blank whenever no override
                    // was ever entered. Never changes the math (i.ded is
                    // already what calculate() used above), purely visibility.
                    Deductable__c             = i.ded
                ));
            }
            updateSecured(toStamp);

            // Selection: whichever row came in with Is_Selected__c = true
            // wins, and every other estimate on the claim (including ones
            // not part of this save) is cleared to match - same guarantee
            // selectEstimate/createWorkOrder already give, just reached
            // without an extra round trip.
            Id selectedId = null;
            for (Estimate__c e : estimates) if (e.Is_Selected__c == true) selectedId = e.Id;
            if (selectedId != null) markSelected(selectedId, claimId);
        } catch (Exception ex) {
            Database.rollback(sp);
            throw new AuraHandledException('Could not save estimates: ' + ex.getMessage());
        }
    }

    // ───────────────────────── Create Work Order ──────────────────────────

    /**
     * Called from the createWorkOrderAction LWC button on the Work Order tab
     * (Sep 22 - Osama caught that the plan originally had this fire
     * automatically on the Claim_Status__c change to "Work Order," which was
     * wrong: the agent needs a deliberate moment to log Ancillary Benefits
     * on that same tab first, and the HTML reference itself has a real
     * button, not automatic behavior). Resolves the claim's currently
     * selected estimate and delegates to createWorkOrder, which already has
     * every guard rail (one active work order per claim, no duplicate per
     * estimate).
     */
    @AuraEnabled
    public static WorkOrderResult createWorkOrderForSelectedEstimate(Id claimId) {
        List<Estimate__c> selected = [
            SELECT Id FROM Estimate__c
            WHERE Claim__c = :claimId AND Is_Selected__c = true
            WITH USER_MODE
            LIMIT 1
        ];
        if (selected.isEmpty()) {
            // AuraHandledException.getMessage() only returns the constructor
            // text after setMessage() is also called - a documented Apex
            // quirk, not a typo.
            AuraHandledException ex = new AuraHandledException('Mark an estimate as USE in Manage Estimates before creating a work order.');
            ex.setMessage('Mark an estimate as USE in Manage Estimates before creating a work order.');
            throw ex;
        }
        return createWorkOrder(selected[0].Id);
    }

    @AuraEnabled
    public static WorkOrderResult createWorkOrder(Id estimateId) {
        Estimate__c est = [
            SELECT Id, Claim__c, Repair_Shop__c,
                   Repair_Shop__r.Tax_Region__c, Repair_Shop__r.Tax_Region__r.Total_Tax_Rate__c,
                   Repair_Shop__r.Tax_Percentage__c,
                   Part_Component__c, Job_Type__c, Part_Code__c, Parts_Supplier__c,
                   Parts_Cost__c, Labour_Hours__c, Labour_Rate__c,
                   Shop_Supplies__c, Shop_Supplies_Retail__c, Retail_Price__c,
                   (SELECT Id FROM Work_Orders__r LIMIT 1)
            FROM Estimate__c WHERE Id = :estimateId
            WITH USER_MODE
        ];
        if (!est.Work_Orders__r.isEmpty()) {
            throw new AuraHandledException('A work order already exists for this estimate.');
        }

        // Only one active work order per claim (any Status__c other than
        // Voided counts as active), even across different estimates on the
        // same claim - the per-estimate check above only catches re-running
        // Create Work Order on the same winning estimate, not a second,
        // different estimate on a claim that already has one.
        List<Work_Order__c> activeOnClaim = [
            SELECT Id FROM Work_Order__c
            WHERE Claim__c = :est.Claim__c AND Status__c != 'Voided'
            WITH USER_MODE
            LIMIT 1
        ];
        if (!activeOnClaim.isEmpty()) {
            throw new AuraHandledException('This claim already has an active work order.');
        }

        Savepoint sp = Database.setSavepoint();
        try {
            // 1. Work order header. Its totals are formulas over the line items
            //    (Total_Line_Items_Cost__c rolls up Price__c, Tax_13__c and
            //    Total_Repair_Cost__c derive from that) and its coverage /
            //    deductible come from Estimate__r.Claim__r.Package__r, so only
            //    the relationships are set here.
            //    Tax mirrors the Application_Package__c pattern: the region is
            //    stamped from the shop, and the percentage is a writeable snapshot
            //    of that region's rate at authorization time (region rate, else the
            //    shop's synced percentage, else 13), so a later rate change never
            //    rewrites an authorized work order.
            Decimal taxRate = est.Repair_Shop__r?.Tax_Region__r?.Total_Tax_Rate__c;
            if (taxRate == null) taxRate = est.Repair_Shop__r?.Tax_Percentage__c;
            if (taxRate == null) taxRate = 13;
            Work_Order__c wo = new Work_Order__c(
                Claim__c         = est.Claim__c,
                Estimate__c      = est.Id,
                Repair_Shop__c   = est.Repair_Shop__c,
                Tax_Region__c    = est.Repair_Shop__r?.Tax_Region__c,
                Tax_Percentage__c = taxRate
            );
            insertSecured(new List<Work_Order__c>{ wo });

            // 2. Selection flag: exactly one per claim.
            markSelected(est.Id, est.Claim__c);

            // 2b. Benefits-inclusive final P&L onto the claim (repair-only
            //     stays on the Estimate/Work Order - see recalculateClaimTotalProfit).
            recalculateClaimTotalProfit(est.Claim__c);

            // 3. Claim line items, one per charge.
            List<Claim_Line_Item__c> lines = buildClaimLineItems(est);
            insertSecured(lines);

            // 4. Work order line items generated from the claim line items.
            //    Price__c carries RETAIL because Work_Order__c.Total_Line_Items_Cost__c
            //    rolls it up and the work order is the customer-facing document; the
            //    vendor cost sits in Wholesale__c. Falls back to wholesale only when a
            //    child had no retail figure at all.
            List<Work_Order_Line_Item__c> woLines = new List<Work_Order_Line_Item__c>();
            for (Claim_Line_Item__c cli : lines) {
                Decimal retail = cli.Retail_Amount__c != null ? cli.Retail_Amount__c : cli.Amount__c;
                Work_Order_Line_Item__c wl = new Work_Order_Line_Item__c(
                    Customer_Work_Order__c        = wo.Id,
                    Claim_Line_Item__c            = cli.Id,
                    Service_Repair_Description__c = cli.Description__c,
                    Description__c                = cli.Description__c,
                    Repair_Shop__c                = cli.Repair_Shop__c,
                    Price__c                      = retail,
                    Retail__c                     = retail,
                    Wholesale__c                  = cli.Amount__c
                );
                if (cli.Line_Type__c == 'Labour') {
                    wl.Wholesale_Labour_Rate_HR__c = cli.Rate__c;
                    if (cli.Hours__c != null) wl.Repair_Time_Adj__c = cli.Hours__c.setScale(0, RoundingMode.HALF_UP);
                }
                woLines.add(wl);
            }
            insertSecured(woLines);

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

    /**
     * Rewritten Sep 22 (Osama): reads the winning Estimate__c's own scalar
     * fields directly, instead of querying Part__c/Service__c/Shop_Supply__c
     * children - the Repair Price Scenarios grid has never created those
     * children (it only ever writes scalar fields onto Estimate__c, the
     * Sep 16 architectural decision), so this used to silently generate an
     * empty work order for every real, UI-created estimate. Still 3 lines
     * (Part/Labour/Supplies), preserving the existing Vendor Payables and
     * Claim Detail - Parts & Labour reports' assumption that Line_Type__c
     * distinguishes Part from Labour.
     *
     * Wrinkle: Estimate__c has only ONE overall Retail_Price__c for the
     * whole repair job (parts + labour combined), not a separate retail
     * figure per part vs labour like the old child-object model did.
     * Resolved by splitting it proportionally between the Part and Labour
     * lines by their wholesale share, so the three lines' retail always
     * sums back to exactly Retail_Total__c (Retail_Price__c +
     * Shop_Supplies_Retail__c, already a real stamped field). Supplies
     * keeps its own honest Shop_Supplies_Retail__c, no allocation needed.
     * A line is only generated when it has a non-zero wholesale amount.
     */
    private static List<Claim_Line_Item__c> buildClaimLineItems(Estimate__c est) {
        List<Claim_Line_Item__c> out = new List<Claim_Line_Item__c>();

        Decimal partsWholesale  = nz(est.Parts_Cost__c);
        Decimal labourWholesale = nz(est.Labour_Hours__c) * nz(est.Labour_Rate__c);
        Decimal repairWholesale = partsWholesale + labourWholesale;
        Decimal jobRetail       = nz(est.Retail_Price__c);
        // setScale(2) before dividing back out - an un-rounded division here
        // (e.g. 1300/1900) can produce a long repeating decimal that throws
        // the retail split off by a fraction of a cent.
        Decimal partsShare   = repairWholesale > 0
            ? (partsWholesale / repairWholesale).setScale(10, RoundingMode.HALF_UP)
            : 0;
        Decimal partsRetail  = (jobRetail * partsShare).setScale(2, RoundingMode.HALF_UP);
        Decimal labourRetail = jobRetail - partsRetail;

        if (partsWholesale != 0) {
            out.add(new Claim_Line_Item__c(
                Claim__c          = est.Claim__c,
                Line_Type__c      = 'Part',
                Role__c           = 'Parts Supplier',
                Description__c    = String.isNotBlank(est.Part_Component__c) ? est.Part_Component__c : 'Part',
                Part_Code__c      = est.Part_Code__c,
                Parts_Supplier__c = est.Parts_Supplier__c,
                Repair_Shop__c    = est.Repair_Shop__c,
                Amount__c         = partsWholesale,
                Retail_Amount__c  = partsRetail
            ));
        }

        if (labourWholesale != 0) {
            out.add(new Claim_Line_Item__c(
                Claim__c         = est.Claim__c,
                Line_Type__c     = 'Labour',
                Role__c          = 'Repair Shop',
                Description__c   = String.isNotBlank(est.Job_Type__c) ? est.Job_Type__c + ' Labour' : 'Labour',
                Hours__c         = est.Labour_Hours__c,
                Rate__c          = est.Labour_Rate__c,
                Repair_Shop__c   = est.Repair_Shop__c,
                Amount__c        = labourWholesale,
                Retail_Amount__c = labourRetail
            ));
        }

        Decimal suppliesWholesale = nz(est.Shop_Supplies__c);
        Decimal suppliesRetail    = nz(est.Shop_Supplies_Retail__c);
        if (suppliesWholesale != 0 || suppliesRetail != 0) {
            out.add(new Claim_Line_Item__c(
                Claim__c         = est.Claim__c,
                Line_Type__c     = 'Supplies',
                Role__c          = 'Repair Shop',
                Description__c   = 'Shop Supplies',
                Repair_Shop__c   = est.Repair_Shop__c,
                Amount__c        = suppliesWholesale,
                Retail_Amount__c = suppliesRetail
            ));
        }

        return out;
    }

    private static Decimal nz(Decimal d) { return d == null ? 0 : d; }

    // ──────────────── Ancillary Benefits (Work Order tab) ────────────────
    // Backs the ancillaryBenefits LWC (Pass 2). Benefits are claim-level,
    // shared across every competing Estimate on the claim, not tied to any
    // one of them - Benefit_Balance__c is keyed off the claim's purchased
    // Application_Package__c, not an Estimate__c.

    public class BenefitBalanceRow {
        @AuraEnabled public Id balanceId;
        @AuraEnabled public String benefitType;
        @AuraEnabled public Decimal capAmount;
        @AuraEnabled public Decimal usedToDate;
        @AuraEnabled public Decimal remaining;     // Benefit_Balance__c.Remaining__c as-is
        @AuraEnabled public Id usageId;            // this claim's own Benefit_Usage__c, if it already has one
        @AuraEnabled public Decimal usageAmount;   // that draw's Amount_Used__c, if any
        // Ceiling for editing THIS claim's own draw: Remaining__c already has
        // this claim's existing usage subtracted out (it's counted in
        // Used_To_Date__c), so saving a changed amount REPLACES that draw
        // rather than adding to it - add it back to get the true room to type into.
        @AuraEnabled public Decimal availableToUse;
    }

    /**
     * Every Benefit_Balance__c under the claim's purchased Application_Package__c,
     * each paired with this claim's own existing Benefit_Usage__c draw (if
     * any) so the LWC edits that draw in place on Save instead of inserting
     * a second, duplicate one every time the screen is saved.
     */
    @AuraEnabled
    public static List<BenefitBalanceRow> getBenefitBalancesForClaim(Id claimId) {
        Claim__c claim = [
            SELECT Id, Application_Package__c
            FROM Claim__c WHERE Id = :claimId
            WITH USER_MODE
        ];
        List<BenefitBalanceRow> rows = new List<BenefitBalanceRow>();
        if (claim.Application_Package__c == null) return rows;

        List<Benefit_Balance__c> balances = [
            SELECT Id, Benefit_Type__c, Cap_Amount__c, Used_To_Date__c, Remaining__c
            FROM Benefit_Balance__c
            WHERE Application_Package__c = :claim.Application_Package__c
            WITH USER_MODE
            ORDER BY Benefit_Type__c
        ];
        if (balances.isEmpty()) return rows;

        Map<Id, Benefit_Usage__c> usageByBalance = new Map<Id, Benefit_Usage__c>();
        for (Benefit_Usage__c u : [
            SELECT Id, Benefit_Balance__c, Amount_Used__c
            FROM Benefit_Usage__c
            WHERE Claim__c = :claimId AND Benefit_Balance__c IN :balances
            WITH USER_MODE
        ]) {
            usageByBalance.put(u.Benefit_Balance__c, u);
        }

        for (Benefit_Balance__c b : balances) {
            Benefit_Usage__c existing = usageByBalance.get(b.Id);
            BenefitBalanceRow row = new BenefitBalanceRow();
            row.balanceId      = b.Id;
            row.benefitType    = b.Benefit_Type__c;
            row.capAmount      = b.Cap_Amount__c;
            row.usedToDate     = b.Used_To_Date__c;
            row.remaining      = b.Remaining__c;
            row.usageId        = existing?.Id;
            row.usageAmount    = existing?.Amount_Used__c;
            row.availableToUse = nz(b.Remaining__c) + nz(existing?.Amount_Used__c);
            rows.add(row);
        }
        return rows;
    }

    /**
     * Bulk save for the Ancillary Benefits editor: one Benefit_Usage__c per
     * included benefit, Id populated to update this claim's already-existing
     * draw (never a second, duplicate draw on re-save) or blank to insert a
     * new one. Amount_Used__c over its balance's availableToUse is refused -
     * the LWC already blocks this live, this is the server-side backstop.
     */
    @AuraEnabled
    public static void saveBenefitUsage(Id claimId, List<Benefit_Usage__c> usages) {
        if (usages == null || usages.isEmpty()) return;

        Set<Id> balanceIds = new Set<Id>();
        Set<Id> usageIds = new Set<Id>();
        for (Benefit_Usage__c u : usages) {
            balanceIds.add(u.Benefit_Balance__c);
            if (u.Id != null) usageIds.add(u.Id);
        }
        Map<Id, Benefit_Balance__c> balancesById = new Map<Id, Benefit_Balance__c>([
            SELECT Id, Remaining__c FROM Benefit_Balance__c WHERE Id IN :balanceIds WITH USER_MODE
        ]);
        Map<Id, Decimal> existingAmountByUsageId = new Map<Id, Decimal>();
        if (!usageIds.isEmpty()) {
            for (Benefit_Usage__c existing : [
                SELECT Id, Amount_Used__c FROM Benefit_Usage__c WHERE Id IN :usageIds WITH USER_MODE
            ]) {
                existingAmountByUsageId.put(existing.Id, existing.Amount_Used__c);
            }
        }

        List<Benefit_Usage__c> toInsert = new List<Benefit_Usage__c>();
        List<Benefit_Usage__c> toUpdate = new List<Benefit_Usage__c>();
        for (Benefit_Usage__c u : usages) {
            Benefit_Balance__c bal = balancesById.get(u.Benefit_Balance__c);
            Decimal available = bal == null ? 0 : nz(bal.Remaining__c) + nz(existingAmountByUsageId.get(u.Id));
            if (nz(u.Amount_Used__c) > available) {
                AuraHandledException ex = new AuraHandledException('Use This Claim amount exceeds the benefit\'s remaining balance.');
                ex.setMessage('Use This Claim amount exceeds the benefit\'s remaining balance.');
                throw ex;
            }
            if (u.Id == null) {
                u.Claim__c = claimId;
                if (u.Date__c == null) u.Date__c = Date.today();
                toInsert.add(u);
            } else {
                // Benefit_Balance__c is a non-reparentable master-detail -
                // never resend it on an update, even unchanged: USER_MODE
                // treats that as an edit to a field that structurally can
                // never be edited and refuses the whole DML.
                toUpdate.add(new Benefit_Usage__c(
                    Id             = u.Id,
                    Amount_Used__c = u.Amount_Used__c,
                    Date__c        = u.Date__c != null ? u.Date__c : Date.today(),
                    Claim__c       = claimId
                ));
            }
        }
        insertSecured(toInsert);
        updateSecured(toUpdate);
        recalculateClaimTotalProfit(claimId);
    }

    /**
     * Stamps the benefits-inclusive final P&L onto Claim__c.Total_Profit__c -
     * the number the Estimate__c/Work_Order__c "A-Protect P&L" fields
     * deliberately do NOT show (those stay repair-only, per the Sep 22
     * decision, so competing estimates stay comparable). Formula: the
     * claim's selected Estimate's own repair-only Profit_Loss__c, minus
     * every ancillary benefit drawn against this claim so far. No-ops if
     * no estimate is selected yet - there's nothing meaningful to compute.
     * Called after every Ancillary Benefits save AND after Create Work
     * Order, so the number never goes stale regardless of which happens
     * first or is edited again later (Osama's choice, Sep 22).
     */
    private static void recalculateClaimTotalProfit(Id claimId) {
        List<Estimate__c> selected = [
            SELECT Id, Profit_Loss__c
            FROM Estimate__c
            WHERE Claim__c = :claimId AND Is_Selected__c = true
            WITH USER_MODE
            LIMIT 1
        ];
        if (selected.isEmpty()) return;

        AggregateResult[] agg = [
            SELECT SUM(Amount_Used__c) total
            FROM Benefit_Usage__c
            WHERE Claim__c = :claimId
            WITH USER_MODE
        ];
        Decimal benefitsUsed = agg.isEmpty() ? 0 : (Decimal) agg[0].get('total');

        updateSecured(new List<Claim__c>{
            new Claim__c(Id = claimId, Total_Profit__c = nz(selected[0].Profit_Loss__c) - nz(benefitsUsed))
        });
    }

    // ───────────────── FLS/CRUD-secured DML helpers ─────────────────
    // AccessLevel.USER_MODE makes the DML itself respect the running user's
    // object and field permissions, the write-side counterpart to WITH
    // USER_MODE on the SOQL above - the platform throws System.NoAccessException
    // rather than silently writing a value the user isn't permitted to set,
    // which is caught here and rethrown as a clear AuraHandledException.

    private static void insertSecured(List<SObject> records) {
        if (records.isEmpty()) return;
        try {
            Database.insert(records, AccessLevel.USER_MODE);
        } catch (System.NoAccessException ex) {
            throw new AuraHandledException('You do not have permission to create this type of record. Contact your administrator.');
        }
    }

    private static void updateSecured(List<SObject> records) {
        if (records.isEmpty()) return;
        try {
            Database.update(records, AccessLevel.USER_MODE);
        } catch (System.NoAccessException ex) {
            throw new AuraHandledException('You do not have permission to update one or more fields on this record. Contact your administrator.');
        }
    }

    private static void deleteSecured(List<SObject> records) {
        if (records.isEmpty()) return;
        try {
            Database.delete(records, AccessLevel.USER_MODE);
        } catch (System.NoAccessException ex) {
            throw new AuraHandledException('You do not have permission to delete this type of record. Contact your administrator.');
        }
    }

    // ──────────────── Invoice And Wrap Up: generate the invoice ───────────────

    /**
     * Called from ClaimWrapUpInvoiceTrigger when a claim's Claim_Status__c
     * changes to "Invoice And Wrap Up". Reuses the Application/Package
     * team's Invoice__c / Invoice_Line_Item__c objects (Osama's Sep 21
     * decision), bridged by the Work_Order__c and Work_Order_Line_Item__c
     * lookups added directly in Setup. Also stamps Invoice__c.Application__c
     * from Claim__r.Application__c (Osama, Sep 21) - Invoice__c's own
     * pre-existing Application_Id__c formula reads Application__r.Name, so
     * setting this one lookup populates both. Mirrors the claim's one
     * active work order (Status__c != 'Voided', matching the "only one
     * active work order per claim" rule) and its lines one-for-one, so the
     * invoice and work order agree by construction rather than needing a
     * manual fix.
     * Idempotent: a claim that re-enters this status (e.g. a status typo
     * corrected and re-saved) does not get a second invoice for the same
     * work order. Silently no-ops for a claim with no active work order
     * yet, or one that already has its invoice - this is a side effect of
     * the status save, not something that should ever block it.
     *
     * Line items ARE itemized, one per Work_Order_Line_Item__c, carrying
     * the same (gross retail) amount as its work order counterpart
     * (Osama, Sep 21). Invoice__c.Amount__c is left alone - a pre-existing,
     * active DLRS real-time rollup sums the line items onto it
     * automatically (so it naturally lands on the gross total, same
     * meaning as Work_Order__c.Total_Line_Items_Cost__c). What the
     * customer actually owes lives on the new Invoice__c.Net_Amount_Due__c,
     * a simple formula reading Work_Order__r.Total_Amount_Due__c directly -
     * mirroring how the work order itself keeps its gross total
     * (Total_Line_Items_Cost__c) and its net amount due
     * (Total_Amount_Due__c) as two separate fields, not one trying to be
     * both. No line-item math, no rollup filter, no negative line needed.
     *
     * Not @AuraEnabled - only reachable via the trigger, not this LWC - but
     * its query and DML are still secured for consistency, running as
     * whichever user saved the claim status change.
     */
    public static void generateInvoicesForWrapUp(List<Id> claimIds) {
        Map<Id, Work_Order__c> activeWorkOrderByClaim = new Map<Id, Work_Order__c>();
        for (Work_Order__c wo : [
            SELECT Id, Name, Claim__c, Claim__r.Application__c, Total_Amount_Due__c,
                   (SELECT Id FROM Invoice__r LIMIT 1),
                   (SELECT Id, Description__c, Price__c FROM Customer_Work_Order_Line_Items__r)
            FROM Work_Order__c
            WHERE Claim__c IN :claimIds AND Status__c != 'Voided'
            WITH USER_MODE
        ]) {
            activeWorkOrderByClaim.put(wo.Claim__c, wo);
        }

        List<Invoice__c> invoicesToInsert = new List<Invoice__c>();
        for (Id claimId : claimIds) {
            Work_Order__c wo = activeWorkOrderByClaim.get(claimId);
            if (wo == null) continue;              // nothing to invoice yet
            if (!wo.Invoice__r.isEmpty()) continue; // already generated

            invoicesToInsert.add(new Invoice__c(
                Name          = 'INV-' + wo.Name,
                Claim__c      = claimId,
                Work_Order__c = wo.Id,
                Application__c = wo.Claim__r.Application__c,
                Status__c     = 'Due'
            ));
        }
        if (invoicesToInsert.isEmpty()) return;
        insertSecured(invoicesToInsert);

        List<Invoice_Line_Item__c> linesToInsert = new List<Invoice_Line_Item__c>();
        for (Invoice__c inv : invoicesToInsert) {
            Work_Order__c wo = activeWorkOrderByClaim.get(inv.Claim__c);
            for (Work_Order_Line_Item__c wl : wo.Customer_Work_Order_Line_Items__r) {
                linesToInsert.add(new Invoice_Line_Item__c(
                    Invoice__c              = inv.Id,
                    Work_Order_Line_Item__c = wl.Id,
                    Description__c          = wl.Description__c,
                    Repair_Charge_Amount__c = wl.Price__c
                ));
            }
        }
        if (!linesToInsert.isEmpty()) insertSecured(linesToInsert);
    }
}