/**
 * RemittanceFormStatusTrigger
 * ──────────────────────────────────────────────────────────────────────────────
 * Fires after update on Remittance_Form__c.
 * When Status__c changes to 'Completed', invokes RemittanceDuplicateInvoiceCleanup
 * to remove duplicate invoice associations from other unpaid remittances.
 */
trigger RemittanceFormStatusTrigger on Remittance_Form__c (after update) {
    Set<Id> completedRemittanceIds = new Set<Id>();

    for (Remittance_Form__c newForm : Trigger.new) {
        Remittance_Form__c oldForm = Trigger.oldMap.get(newForm.Id);
        // Only fire when Status changes TO 'Completed'
        if (newForm.Status__c == 'Completed' && oldForm.Status__c != 'Completed') {
            completedRemittanceIds.add(newForm.Id);
        }
    }

    if (!completedRemittanceIds.isEmpty()) {
        RemittanceDuplicateInvoiceCleanup.cleanupDuplicateInvoices(completedRemittanceIds);
    }
}