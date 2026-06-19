/**
 * Scheduled Apex job that expires unpaid remittance forms.
 * Runs daily. Finds all Remittance Forms with Status = 'Open'
 * where Expiry_Date__c <= TODAY and marks them as 'Expired'.
 * 
 * Schedule: System.schedule('Remittance Expiry Daily', '0 0 1 * * ?', new RemittanceExpiryScheduler());
 */
public class RemittanceExpiryScheduler implements Schedulable {
    
    public void execute(SchedulableContext ctx) {
        expireRemittanceForms();
    }
    
    public static void expireRemittanceForms() {
        List<Remittance_Form__c> formsToExpire = [
            SELECT Id, Status__c, Expiry_Date__c
            FROM Remittance_Form__c
            WHERE Status__c = 'Open'
              AND Expiry_Date__c != null
              AND Expiry_Date__c <= TODAY
            LIMIT 10000
        ];
        
        if (!formsToExpire.isEmpty()) {
            for (Remittance_Form__c form : formsToExpire) {
                form.Status__c = 'Expired';
            }
            update formsToExpire;
        }
    }
}