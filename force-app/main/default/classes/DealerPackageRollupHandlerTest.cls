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
        
        // Only Active__c = true rows may be rolled up.
        List<Application_Package__c> aps = new List<Application_Package__c>();
        for (Integer i = 0; i < 3; i++) {
            aps.add(new Application_Package__c(
                Dealer_Package__c = dp.Id,
                Active__c = true
            ));
        }
        // Inactive rows must be excluded from the rollup.
        aps.add(new Application_Package__c(
            Dealer_Package__c = dp.Id,
            Active__c = false
        ));
        
        Test.startTest();
        insert aps;
        Test.stopTest();
        
        dp = [SELECT Total_Warranties_Sold__c 
              FROM Dealer_Package__c WHERE Id = :dp.Id];
        
        System.assertEquals(3, dp.Total_Warranties_Sold__c, 'Should count only the 3 active warranties');
    }
    
    @isTest
    static void testRollupOnUpdate() {
        Dealer_Package__c dp = [SELECT Id FROM Dealer_Package__c LIMIT 1];
        
        Application_Package__c ap = new Application_Package__c(
            Dealer_Package__c = dp.Id,
            Active__c = true
        );
        insert ap;
        
        Test.startTest();
        ap.Active__c = false;
        update ap;
        Test.stopTest();
        
        dp = [SELECT Total_Warranties_Sold__c FROM Dealer_Package__c WHERE Id = :dp.Id];
        System.assertEquals(0, dp.Total_Warranties_Sold__c, 'Deactivating the only package should zero the count');
    }
    
    @isTest 
    static void testEmptyDealerPackage() {
        // Test with no records
        DealerPackageRollupHandler.recalculateRollups(new List<Application_Package__c>(), null);
        // No exception = pass
    }
}