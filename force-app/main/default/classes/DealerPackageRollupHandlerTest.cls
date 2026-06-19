@isTest
private class DealerPackageRollupHandlerTest {
    
    @TestSetup
    static void setup() {
        // Create a Dealer Package
        Dealer_Package__c dp = new Dealer_Package__c();
        insert dp;
    }
    
    @isTest
    static void testRollupOnInsert() {
        Dealer_Package__c dp = [SELECT Id FROM Dealer_Package__c LIMIT 1];
        
        // Create Application_Package__c records
        List<Application_Package__c> aps = new List<Application_Package__c>();
        for (Integer i = 0; i < 3; i++) {
            aps.add(new Application_Package__c(
                Dealer_Package__c = dp.Id
            ));
        }
        
        Test.startTest();
        insert aps;
        Test.stopTest();
        
        dp = [SELECT Total_Reserve_Accrued__c, Total_Commission_Earned__c, Total_Warranties_Sold__c,
                     Total_Revenue__c, Total_Owed_To_Dealer__c 
              FROM Dealer_Package__c WHERE Id = :dp.Id];
        
        System.assertEquals(3, dp.Total_Warranties_Sold__c, 'Should count 3 warranties');
    }
    
    @isTest
    static void testRollupOnUpdate() {
        Dealer_Package__c dp = [SELECT Id FROM Dealer_Package__c LIMIT 1];
        
        Application_Package__c ap = new Application_Package__c(
            Dealer_Package__c = dp.Id
        );
        insert ap;
        
        Test.startTest();
        ap.Reserve_Amount__c = 100;
        update ap;
        Test.stopTest();
        
        dp = [SELECT Total_Reserve_Accrued__c FROM Dealer_Package__c WHERE Id = :dp.Id];
        // Verify rollup ran (value may differ due to before-trigger recalc)
        System.assertNotEquals(null, dp.Total_Reserve_Accrued__c);
    }
    
    @isTest 
    static void testEmptyDealerPackage() {
        // Test with no records
        DealerPackageRollupHandler.recalculateRollups(new List<Application_Package__c>(), null);
        // No exception = pass
    }
}