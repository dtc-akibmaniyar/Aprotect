/**
 * Sets Expiry_Date__c to 30 days from today on new Remittance Forms
 * when the field is not already populated.
 */
trigger RemittanceFormExpiryTrigger on Remittance_Form__c (before insert) {
    for (Remittance_Form__c form : Trigger.new) {
        if (form.Expiry_Date__c == null) {
            form.Expiry_Date__c = Date.today().addDays(30);
        }
    }
}