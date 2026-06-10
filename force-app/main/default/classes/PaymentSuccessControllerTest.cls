@isTest
private class PaymentSuccessControllerTest {
    
    @TestSetup
    static void setup() {
        Account dealer = new Account(Name = 'Test Dealer');
        insert dealer;
        
        Remittance_Form__c form = new Remittance_Form__c(
            Dealer_Name__c = dealer.Id,
            Status__c = 'Open'
        );
        insert form;
    }
    
    @isTest
    static void testGetRemittanceFormDetails() {
        Remittance_Form__c form = [SELECT Id FROM Remittance_Form__c LIMIT 1];
        
        Test.startTest();
        PaymentSuccessController.RemittanceFormDetails details = 
            PaymentSuccessController.getRemittanceFormDetails(form.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, details, 'Details should not be null');
        System.assertEquals(form.Id, details.remittanceFormId, 'Form ID should match');
        System.assertEquals('Test Dealer', details.dealerName, 'Dealer name should match');
    }
    
    @isTest
    static void testGetRemittanceFormDetailsBlankId() {
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            PaymentSuccessController.getRemittanceFormDetails('');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'AuraHandledException should have been thrown');
    }
    
    @isTest
    static void testGetRemittanceFormDetailsInvalidId() {
        Test.startTest();
        try {
            PaymentSuccessController.getRemittanceFormDetails('a00000000000000AAA');
            System.assert(false, 'Should have thrown exception');
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage(), 'Should have error message');
        }
        Test.stopTest();
    }
}