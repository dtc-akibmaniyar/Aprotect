/**
 * RemittanceDuplicateInvoiceCleanup
 * ──────────────────────────────────────────────────────────────────────────────
 * Scenario 2: When a Remittance Form's Status changes to "Completed",
 * automatically remove the same invoices from all OTHER unpaid remittances.
 *
 * Logic:
 *   1. Get all invoices (via junction) on the completed remittance.
 *   2. For each invoice, find junction records on OTHER remittances.
 *   3. Delete those other junction records (only if the other remittance has
 *      no payments initiated — i.e., Payment_Status__c = 'Planned' or null).
 *   4. If the invoice's Remittance_Form__c lookup points to a different
 *      (now-cleaned) remittance, update it to point to the completed one.
 *
 * Called from RemittanceFormStatusTrigger (after update).
 */
public with sharing class RemittanceDuplicateInvoiceCleanup {

    /**
     * Main entry point — called from trigger context.
     * @param completedRemittanceIds Set of Remittance_Form__c Ids that just changed to 'Completed'
     */
    public static void cleanupDuplicateInvoices(Set<Id> completedRemittanceIds) {
        if (completedRemittanceIds == null || completedRemittanceIds.isEmpty()) {
            return;
        }

        // Step 1: Get all invoice IDs on the completed remittances via junctions
        Map<Id, Set<Id>> remittanceToInvoiceIds = new Map<Id, Set<Id>>();
        Set<Id> allInvoiceIds = new Set<Id>();

        for (Remittance_Line_Item_Junction__c j : [
            SELECT Invoice__c, Remittance_Form__c
            FROM Remittance_Line_Item_Junction__c
            WHERE Remittance_Form__c IN :completedRemittanceIds
            AND Invoice__c != null
        ]) {
            if (!remittanceToInvoiceIds.containsKey(j.Remittance_Form__c)) {
                remittanceToInvoiceIds.put(j.Remittance_Form__c, new Set<Id>());
            }
            remittanceToInvoiceIds.get(j.Remittance_Form__c).add(j.Invoice__c);
            allInvoiceIds.add(j.Invoice__c);
        }

        if (allInvoiceIds.isEmpty()) {
            return;
        }

        // Step 2: Find junction records on OTHER remittances for these invoices
        List<Remittance_Line_Item_Junction__c> otherJunctions = [
            SELECT Id, Invoice__c, Remittance_Form__c, Payment_Status__c
            FROM Remittance_Line_Item_Junction__c
            WHERE Invoice__c IN :allInvoiceIds
            AND Remittance_Form__c NOT IN :completedRemittanceIds
        ];

        if (otherJunctions.isEmpty()) {
            return;
        }

        // Step 3: Determine which other remittances have payments (those are blocked)
        Set<Id> otherRemittanceIds = new Set<Id>();
        for (Remittance_Line_Item_Junction__c j : otherJunctions) {
            otherRemittanceIds.add(j.Remittance_Form__c);
        }

        Set<Id> remittancesWithPayments = new Set<Id>();
        for (Payment__c pmt : [
            SELECT Remittance_Form__c
            FROM Payment__c
            WHERE Remittance_Form__c IN :otherRemittanceIds
        ]) {
            remittancesWithPayments.add(pmt.Remittance_Form__c);
        }

        // Step 4: Collect junctions to delete — only from remittances WITHOUT payments
        List<Remittance_Line_Item_Junction__c> junctionsToDelete = new List<Remittance_Line_Item_Junction__c>();
        for (Remittance_Line_Item_Junction__c j : otherJunctions) {
            if (!remittancesWithPayments.contains(j.Remittance_Form__c)) {
                junctionsToDelete.add(j);
            }
        }

        if (!junctionsToDelete.isEmpty()) {
            delete junctionsToDelete;
        }

        // Step 5: Update Invoice Remittance_Form__c lookup to point to the completed remittance
        // (if the invoice's current lookup is null or points to a non-completed remittance)
        List<Invoice__c> invoicesToUpdate = new List<Invoice__c>();
        Map<Id, Id> invoiceToCompletedRemittance = new Map<Id, Id>();

        for (Id rfId : remittanceToInvoiceIds.keySet()) {
            for (Id invId : remittanceToInvoiceIds.get(rfId)) {
                invoiceToCompletedRemittance.put(invId, rfId);
            }
        }

        for (Invoice__c inv : [
            SELECT Id, Remittance_Form__c
            FROM Invoice__c
            WHERE Id IN :allInvoiceIds
        ]) {
            Id targetRfId = invoiceToCompletedRemittance.get(inv.Id);
            if (inv.Remittance_Form__c != targetRfId) {
                invoicesToUpdate.add(new Invoice__c(
                    Id = inv.Id,
                    Remittance_Form__c = targetRfId
                ));
            }
        }

        if (!invoicesToUpdate.isEmpty()) {
            update invoicesToUpdate;
        }
    }
}