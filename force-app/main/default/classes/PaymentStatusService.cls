/**
 * @description Invocable Apex to mark Remittance_Line_Item_Junction__c records,
 *              Invoice_Line_Item__c, Invoice__c, Application__c, and
 *              Application_Package__c as Paid when a Payment__c record reaches
 *              a confirmed paid status ('Transaction Completed' or 'Deposit Completed').
 *
 * Architecture:
 * ─────────────────────────────────────────────────────────────────────────────
 * Payment__c (confirmed)
 *   └── Remittance_Line_Item_Junction__c  (Payment__c lookup, Payment_Status__c)
 *         ├── Invoice_Line_Item__c         (Status__c → Paid)
 *         └── Invoice__c                  (Status__c → Paid / Partial Paid)
 *               └── Application__c        (Payment_Status__c → Paid)
 *                     └── Application_Package__c (Payment_Status__c → Paid)
 * ─────────────────────────────────────────────────────────────────────────────
 *
 * @requirements
 * - with sharing
 * - Bulkified: no SOQL/DML in loops
 * - Prefer enums over string constants
 * - Return-early pattern
 * - No hardcoded IDs/URLs
 */
public with sharing class PaymentStatusService {

    /**
     * Allowed payment confirmation statuses that qualify a Payment__c as paid.
     */
    public enum PAYMENT_CONFIRMATION_STATUS {
        DEPOSIT_COMPLETED,
        TRANSACTION_COMPLETED
    }

    public static Set<String> valuesAsStrings() {
        Set<String> out = new Set<String>();
        for (PAYMENT_CONFIRMATION_STATUS e : PAYMENT_CONFIRMATION_STATUS.values()) {
            switch on e {
                when DEPOSIT_COMPLETED     { out.add('Deposit Completed'); }
                when TRANSACTION_COMPLETED { out.add('Transaction Completed'); }
            }
        }
        return out;
    }

    /**
     * Target status values written to records during the paid update.
     */
    public enum TARGET_STATUS {
        PAID,
        PARTIAL_PAID
    }

    public static String label(TARGET_STATUS status) {
        switch on status {
            when PAID         { return 'Paid'; }
            when PARTIAL_PAID { return 'Partial Paid'; }
        }
        return null;
    }

    /**
     * Invocable request — accepts a Payment__c Id.
     */
    public class MarkPaidRequest {
        @InvocableVariable(required=true)
        public Id monerisTransactionHistoryId; // Payment__c Id
    }

    /**
     * Invocable response — returns counts for observability/debugging.
     */
    public class MarkPaidResult {
        @InvocableVariable public Integer junctionsUpdated;
        @InvocableVariable public Integer lineItemsUpdated;
        @InvocableVariable public Integer invoicesUpdated;
        @InvocableVariable public Integer applicationsUpdated;
        @InvocableVariable public String  message;
    }

    /**
     * Flow-invocable entry point.
     *
     * For each qualifying Payment__c (status = 'Transaction Completed' or 'Deposit Completed'):
     *  1. Marks linked Remittance_Line_Item_Junction__c records as Paid.
     *  2. Marks related Invoice_Line_Item__c records as Paid.
     *  3. Recomputes Invoice__c.Status__c → 'Paid' (all lines paid) or 'Partial Paid' (some).
     *  4. Marks parent Application__c.Payment_Status__c as Paid (where invoice is fully Paid).
     *  5. Marks related Application_Package__c.Payment_Status__c as Paid.
     */
    @InvocableMethod(
        label='Mark Invoices & Applications Paid by Payment Ids'
        description='Given Payment__c Ids, marks Remittance Line Item Junctions, Invoice Line Items, Invoices, Applications, and Application Packages as Paid when the Payment is in an allowed confirmed status.'
    )
    public static List<MarkPaidResult> markInvoicesPaidByTransactionIds(List<MarkPaidRequest> requests) {
        List<MarkPaidResult> results = new List<MarkPaidResult>();

        // ── Return early on bad input ─────────────────────────────────────────────
        if (requests == null || requests.isEmpty()) {
            results.add(buildResult(0, 0, 0, 0, 'No requests received.'));
            return results;
        }

        // Collect distinct Payment__c Ids
        Set<Id> paymentIds = new Set<Id>();
        for (MarkPaidRequest req : requests) {
            if (req != null && req.monerisTransactionHistoryId != null) {
                paymentIds.add(req.monerisTransactionHistoryId);
            }
        }

        if (paymentIds.isEmpty()) {
            results.add(buildResult(0, 0, 0, 0, 'No Payment__c Ids provided.'));
            return results;
        }

        // ── Step 1: Filter to payments with an allowed confirmed status ───────────
        Set<String> allowedStatuses = PAYMENT_CONFIRMATION_STATUS.valuesAsStrings();

        Map<Id, Payment__c> qualifyingPayments = new Map<Id, Payment__c>([
            SELECT Id, Payment_Confirmation_Status__c
            FROM Payment__c
            WHERE Id IN :paymentIds
            AND Payment_Confirmation_Status__c IN :allowedStatuses
        ]);

        if (qualifyingPayments.isEmpty()) {
            results.add(buildResult(0, 0, 0, 0, 'No Payment__c records in an allowed confirmed status.'));
            return results;
        }

        // ── Step 2: Load all junction records linked to these payments ────────────
        // Remittance_Line_Item_Junction__c.Payment__c is set by DealerPortalMonerisIntegrationServices
        // before the flow fires, so these records are guaranteed to exist at this point.
        List<Remittance_Line_Item_Junction__c> junctions = [
            SELECT Id, Payment__c, Invoice__c, Invoice_Line_Item__c, Payment_Status__c, Paid_Date__c
            FROM Remittance_Line_Item_Junction__c
            WHERE Payment__c IN :qualifyingPayments.keySet()
        ];

        if (junctions.isEmpty()) {
            results.add(buildResult(0, 0, 0, 0, 'No Remittance_Line_Item_Junction__c records found for provided Payment Ids.'));
            return results;
        }

        // Collect Invoice Line Item Ids and Invoice Ids from junctions
        Set<Id> invoiceLineItemIds = new Set<Id>();
        Set<Id> invoiceIds         = new Set<Id>();
        for (Remittance_Line_Item_Junction__c j : junctions) {
            if (j.Invoice_Line_Item__c != null) invoiceLineItemIds.add(j.Invoice_Line_Item__c);
            if (j.Invoice__c           != null) invoiceIds.add(j.Invoice__c);
        }

        // ── Step 3: Mark junction records as Paid ─────────────────────────────────
        Date today = Date.today();
        List<Remittance_Line_Item_Junction__c> junctionsToUpdate = new List<Remittance_Line_Item_Junction__c>();
        for (Remittance_Line_Item_Junction__c j : junctions) {
            if (j.Payment_Status__c != label(TARGET_STATUS.PAID)) {
                junctionsToUpdate.add(new Remittance_Line_Item_Junction__c(
                    Id               = j.Id,
                    Payment_Status__c = label(TARGET_STATUS.PAID),
                    Paid_Date__c     = (j.Paid_Date__c != null ? j.Paid_Date__c : today)
                ));
            } else if (j.Paid_Date__c == null) {
                // Already Paid but missing date — backfill
                junctionsToUpdate.add(new Remittance_Line_Item_Junction__c(
                    Id           = j.Id,
                    Paid_Date__c = today
                ));
            }
        }

        Integer junctionDml = 0;
        if (!junctionsToUpdate.isEmpty()) {
            Database.SaveResult[] srJunc = Database.update(junctionsToUpdate, false);
            for (Database.SaveResult sr : srJunc) { if (sr.isSuccess()) junctionDml++; }
        }

        // ── Step 4: Mark Invoice Line Items as Paid ───────────────────────────────
        Integer lineItemDml = 0;
        if (!invoiceLineItemIds.isEmpty()) {
            List<Invoice_Line_Item__c> lineItemsToUpdate = new List<Invoice_Line_Item__c>();
            for (Invoice_Line_Item__c li : [
                SELECT Id, Status__c
                FROM Invoice_Line_Item__c
                WHERE Id IN :invoiceLineItemIds
            ]) {
                if (li.Status__c != label(TARGET_STATUS.PAID)) {
                    lineItemsToUpdate.add(new Invoice_Line_Item__c(
                        Id       = li.Id,
                        Status__c = label(TARGET_STATUS.PAID)
                    ));
                }
            }
            if (!lineItemsToUpdate.isEmpty()) {
                Database.SaveResult[] srLI = Database.update(lineItemsToUpdate, false);
                for (Database.SaveResult sr : srLI) { if (sr.isSuccess()) lineItemDml++; }
            }
        }

        // ── Step 5: Recompute Invoice status (Paid vs Partial Paid) ──────────────
        // Query ALL line items for the involved invoices (not just the ones in this payment)
        // to correctly determine whether every line item is now Paid.
        Map<Id, Integer> totalByInvoice = new Map<Id, Integer>();
        Map<Id, Integer> paidByInvoice  = new Map<Id, Integer>();

        for (Invoice_Line_Item__c li : [
            SELECT Id, Invoice__c, Status__c
            FROM Invoice_Line_Item__c
            WHERE Invoice__c IN :invoiceIds
        ]) {
            if (li.Invoice__c == null) continue;
            Integer total = totalByInvoice.containsKey(li.Invoice__c) ? totalByInvoice.get(li.Invoice__c) : 0;
            Integer paid  = paidByInvoice.containsKey(li.Invoice__c)  ? paidByInvoice.get(li.Invoice__c)  : 0;
            totalByInvoice.put(li.Invoice__c, total + 1);
            if (li.Status__c == label(TARGET_STATUS.PAID)) {
                paidByInvoice.put(li.Invoice__c, paid + 1);
            }
        }

        // Determine the new status for each invoice
        List<Invoice__c> invoicesToUpdate = new List<Invoice__c>();
        Set<Id> fullyPaidInvoiceIds = new Set<Id>(); // used for Application update below

        for (Id invId : invoiceIds) {
            Integer total = totalByInvoice.containsKey(invId) ? totalByInvoice.get(invId) : 0;
            Integer paid  = paidByInvoice.containsKey(invId)  ? paidByInvoice.get(invId)  : 0;
            if (total == 0) continue; // no line items — skip

            String newStatus = (paid == total)
                ? label(TARGET_STATUS.PAID)
                : label(TARGET_STATUS.PARTIAL_PAID);

            invoicesToUpdate.add(new Invoice__c(
                Id       = invId,
                Status__c = newStatus
            ));

            if (paid == total) {
                fullyPaidInvoiceIds.add(invId);
            }
        }

        Integer invoiceDml = 0;
        if (!invoicesToUpdate.isEmpty()) {
            Database.SaveResult[] srInv = Database.update(invoicesToUpdate, false);
            for (Database.SaveResult sr : srInv) { if (sr.isSuccess()) invoiceDml++; }
        }

        // ── Step 6: Mark parent Applications as Paid (fully paid invoices only) ───
        // Only update Application__c when its invoice is now fully Paid,
        // not when it is still Partial Paid.
        Set<Id> appIds = new Set<Id>();
        if (!fullyPaidInvoiceIds.isEmpty()) {
            for (Invoice__c inv : [
                SELECT Id, Application__c
                FROM Invoice__c
                WHERE Id IN :fullyPaidInvoiceIds
            ]) {
                if (inv.Application__c != null) appIds.add(inv.Application__c);
            }
        }

        Integer appDml = 0;
        if (!appIds.isEmpty()) {
            List<Application__c> appsToUpdate = new List<Application__c>();
            for (Application__c app : [
                SELECT Id, Payment_Status__c
                FROM Application__c
                WHERE Id IN :appIds
            ]) {
                if (app.Payment_Status__c != label(TARGET_STATUS.PAID)) {
                    appsToUpdate.add(new Application__c(
                        Id               = app.Id,
                        Payment_Status__c = label(TARGET_STATUS.PAID)
                    ));
                }
            }
            if (!appsToUpdate.isEmpty()) {
                Database.SaveResult[] srApp = Database.update(appsToUpdate, false);
                for (Database.SaveResult sr : srApp) { if (sr.isSuccess()) appDml++; }
            }

            // ── Step 7: Mark Application_Package__c as Paid ───────────────────────
            // Packages are tied to Applications; mark them Paid when parent app is fully Paid.
            if (!appsToUpdate.isEmpty()) {
                List<Application_Package__c> packagesToUpdate = new List<Application_Package__c>();
                for (Application_Package__c pkg : [
                    SELECT Id, Payment_Status__c
                    FROM Application_Package__c
                    WHERE Application__c IN :appIds
                ]) {
                    if (pkg.Payment_Status__c != label(TARGET_STATUS.PAID)) {
                        packagesToUpdate.add(new Application_Package__c(
                            Id               = pkg.Id,
                            Payment_Status__c = label(TARGET_STATUS.PAID)
                        ));
                    }
                }
                if (!packagesToUpdate.isEmpty()) {
                    Database.update(packagesToUpdate, false);
                }
            }
        }

        results.add(buildResult(
            junctionDml,
            lineItemDml,
            invoiceDml,
            appDml,
            'Processed ' + qualifyingPayments.size() + ' qualifying Payment record(s).'
        ));
        return results;
    }

    // ─── Private Helper ───────────────────────────────────────────────────────────

    private static MarkPaidResult buildResult(
        Integer junctions,
        Integer lineItems,
        Integer invoices,
        Integer applications,
        String  msg
    ) {
        MarkPaidResult r = new MarkPaidResult();
        r.junctionsUpdated    = junctions;
        r.lineItemsUpdated    = lineItems;
        r.invoicesUpdated     = invoices;
        r.applicationsUpdated = applications;
        r.message             = msg;
        return r;
    }
}