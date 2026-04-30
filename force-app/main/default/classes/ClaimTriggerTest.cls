@isTest
public class ClaimTriggerTest {
    @isTest
    static void testOilChangeCounts() {
        
        Repair_Shop__c repairShop = new Repair_Shop__c();
        repairShop.Name = 'Test';
        repairShop.Contact_Number__c = '43546546';
        repairShop.Email__c = 'test@g.com';
        insert repairShop;
        
        // Create an Application
        Application__c app = new Application__c();
        insert app;

        // Create related Oil Change records
        List<Application_Oil_Change__c> oilChanges = new List<Application_Oil_Change__c>();
        // 3 Standard
        for (Integer i = 0; i < 3; i++) {
            oilChanges.add(new Application_Oil_Change__c(
                Application__c = app.Id,
                Type__c = 'Standard'
            ));
        }
        // 2 Synthetic
        for (Integer i = 0; i < 2; i++) {
            oilChanges.add(new Application_Oil_Change__c(
                Application__c = app.Id,
                Type__c = 'Synthetic'
            ));
        }
        insert oilChanges;

        // Insert Claim
        Claim__c claim = new Claim__c(
            Application__c = app.Id,
            Repair_Shop__c = repairShop.Id
        );
        insert claim;

        // Query the claim to check the fields
        claim = [SELECT Actual_Oil_Change_Duration_Standard__c, Actual_Oil_Change_Duration_Synthetic__c
                 FROM Claim__c WHERE Id = :claim.Id];

        System.assertEquals(3, claim.Actual_Oil_Change_Duration_Standard__c, 'Standard count should be 3');
        System.assertEquals(2, claim.Actual_Oil_Change_Duration_Synthetic__c, 'Synthetic count should be 2');
    }
}