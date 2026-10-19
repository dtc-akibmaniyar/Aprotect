/**
 * InvoiceOptionLineTrigger
 *
 * After a new Invoice__c is inserted, materialise the invoice lines for the
 * priced OPTION selections of the invoice's packages, so options are billed.
 *
 * The work lives in InvoiceOptionLineService (bulkified; SYSTEM_MODE reads/writes;
 * idempotent on (Invoice__c, Description__c)). This trigger only wires it up —
 * one trigger per object, no logic here. It is the ONLY new handler on
 * Invoice__c (the existing dlrs_InvoiceTrigger is unrelated rollup plumbing).
 *
 * Fix-forward only: this never touches pre-existing invoices.
 */
trigger InvoiceOptionLineTrigger on Invoice__c (after insert) {
    InvoiceOptionLineService.handleAfterInsert(Trigger.new);
}