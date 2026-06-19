@isTest
public class RemittanceExpirySchedulerTest {
    
    @isTest
    static void testExpireOpenForms() {
        // Create a remittance form with Open status and past expiry date
        Remittance_Form__c form = new Remittance_Form__c(
            Status__c = 'Open',
            Expiry_Date__c = Date.today().addDays(-1)
        );
        insert form;
        
        Test.startTest();
        RemittanceExpiryScheduler.expireRemittanceForms();
        Test.stopTest();
        
        form = [SELECT Status__c FROM Remittance_Form__c WHERE Id = :form.Id];
        System.assertEquals('Expired', form.Status__c, 'Form should be expired');
    }
    
    @isTest
    static void testDoNotExpireFutureForms() {
        // Create a remittance form with Open status and future expiry date
        Remittance_Form__c form = new Remittance_Form__c(
            Status__c = 'Open',
            Expiry_Date__c = Date.today().addDays(10)
        );
        insert form;
        
        Test.startTest();
        RemittanceExpiryScheduler.expireRemittanceForms();
        Test.stopTest();
        
        form = [SELECT Status__c FROM Remittance_Form__c WHERE Id = :form.Id];
        System.assertEquals('Open', form.Status__c, 'Form should remain Open');
    }
    
    @isTest
    static void testDoNotExpireCompletedForms() {
        // Create a completed remittance form with past expiry date
        Remittance_Form__c form = new Remittance_Form__c(
            Status__c = 'Completed',
            Expiry_Date__c = Date.today().addDays(-5)
        );
        insert form;
        
        Test.startTest();
        RemittanceExpiryScheduler.expireRemittanceForms();
        Test.stopTest();
        
        form = [SELECT Status__c FROM Remittance_Form__c WHERE Id = :form.Id];
        System.assertEquals('Completed', form.Status__c, 'Completed form should not be expired');
    }
    
    @isTest
    static void testSchedulableExecution() {
        Test.startTest();
        String jobId = System.schedule('Test Remittance Expiry', '0 0 1 * * ?', new RemittanceExpiryScheduler());
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'Job should be scheduled');
    }
}