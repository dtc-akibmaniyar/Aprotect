@isTest
public class ApplicationOilChangeTriggerTest {
    @isTest
    static void testInsertAndDeleteOilChangeUpdatesClaims() {
        // Create an Application
        Application__c app = new Application__c();
        insert app;
        
        Repair_Shop__c repairShop = new Repair_Shop__c();
        repairShop.Name = 'Test';
        repairShop.Contact_Number__c = '43546546';
        repairShop.Email__c = 'test@g.com';
        insert repairShop;

        // Create a Claim related to the Application
        Claim__c claim = new Claim__c(Application__c = app.Id,Repair_Shop__c = repairShop.Id);
        insert claim;

        // Insert Oil Change records: 2 Standard, 1 Synthetic
        List<Application_Oil_Change__c> oilChanges = new List<Application_Oil_Change__c>();
        oilChanges.add(new Application_Oil_Change__c(Application__c = app.Id, Type__c = 'Standard'));
        oilChanges.add(new Application_Oil_Change__c(Application__c = app.Id, Type__c = 'Standard'));
        oilChanges.add(new Application_Oil_Change__c(Application__c = app.Id, Type__c = 'Synthetic'));
        insert oilChanges;

        // After insert, the claim should be updated
        claim = [SELECT Actual_Oil_Change_Duration_Standard__c, Actual_Oil_Change_Duration_Synthetic__c
                 FROM Claim__c WHERE Id = :claim.Id];
        System.assertEquals(2, claim.Actual_Oil_Change_Duration_Standard__c, 'Standard count should be 2 after insert');
        System.assertEquals(1, claim.Actual_Oil_Change_Duration_Synthetic__c, 'Synthetic count should be 1 after insert');

        // Delete one Standard oil change
        delete oilChanges[0];

        // After delete, the claim should be updated
        claim = [SELECT Actual_Oil_Change_Duration_Standard__c, Actual_Oil_Change_Duration_Synthetic__c
                 FROM Claim__c WHERE Id = :claim.Id];
        System.assertEquals(1, claim.Actual_Oil_Change_Duration_Standard__c, 'Standard count should be 1 after delete');
        System.assertEquals(1, claim.Actual_Oil_Change_Duration_Synthetic__c, 'Synthetic count should remain 1 after delete');

        // Delete the remaining oil changes
        delete oilChanges[1];
        delete oilChanges[2];

        // After deleting all, both counts should be 0
        claim = [SELECT Actual_Oil_Change_Duration_Standard__c, Actual_Oil_Change_Duration_Synthetic__c
                 FROM Claim__c WHERE Id = :claim.Id];
        System.assertEquals(0, claim.Actual_Oil_Change_Duration_Standard__c, 'Standard count should be 0 after deleting all');
        System.assertEquals(0, claim.Actual_Oil_Change_Duration_Synthetic__c, 'Synthetic count should be 0 after deleting all');
    }
}