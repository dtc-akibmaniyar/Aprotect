@isTest(SeeAllData=false)
private class DealerPortalMarkupControllerTest {

    @TestSetup
    static void setup() {
        // 1. Create Dealer and Portal User
        Account dealer = TestDataFactory.createDealer(true);
        User portalUser = TestDataFactory.createPortalUser(dealer.Id, true);

        // 2. Setup master Package Hierarchy (Extended Limited Warranty)
        Package__c pkg = TestDataFactory.createPackage('Extended_Limited_Warranty', true);
        Package_Tier__c tier = TestDataFactory.createPackageTier(pkg.Id, true);
        Package_Term__c term = TestDataFactory.createPackageTerm(pkg.Id, tier.Id, true);
        Package_Option__c pOpt = TestDataFactory.createPackageOption(pkg.Id, term.Id, 'Optional', true);

        // 3. Setup Dealer-specific records for Extended Warranty
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true);
        Dealer_Package_Tier__c dpt = TestDataFactory.createDealerPackageTier(dp.Id, tier.Id, true);
        
        // Term with % Markup
        Dealer_Package_Term__c dterm = TestDataFactory.createDealerPackageTerm(dp.Id, term.Id, dpt.Id, false);
        dterm.Markup__c = 10.0;
        dterm.Markup_Type__c = '%';
        //dterm.Net_Cost__c = 1000;
        insert dterm;

        // Option linked to term
        TestDataFactory.createDealerPackageOption(dp.Id, pOpt.Id, dterm.Id, 'Optional', true);

        // 4. Setup Total Loss Coverage (to hit the specific RecordType filters in the Options API)
        Package__c pkgTotal = TestDataFactory.createPackage('Gap_Coverage', true);
        Dealer_Package__c dpTotal = TestDataFactory.createDealerPackage(dealer.Id, pkgTotal.Id, 'Total_Loss_Coverage', true);
        
        // Option linked to package level (No term)
        Package_Option__c pOptTotal = TestDataFactory.createPackageOption(pkgTotal.Id, null, 'Optional', true);
        Dealer_Package_Option__c dpoTotal = TestDataFactory.createDealerPackageOption(dpTotal.Id, pOptTotal.Id, null, 'Optional', false);
        dpoTotal.Category__c = 'Security';
        dpoTotal.Markup_Type__c = '$';
        dpoTotal.Dealer_Markup__c = 50;
        //dpoTotal.Net_Cost__c = 200;
        insert dpoTotal;
    }

    private static User getPortalUser() {
        return [SELECT Id FROM User WHERE Alias = 'ptlu' LIMIT 1];
    }

    // ── Hierarchy & Admin Query Tests ──────────────────────────────────────────

    @isTest
    static void testGetDealerPackagesHierarchy() {
        System.runAs(getPortalUser()) {
            Test.startTest();
            List<DealerPortalMarkupController.DealerPackageDTO> result = DealerPortalMarkupController.getDealerPackagesHierarchy();
            Test.stopTest();
        }
    }

    @isTest
    static void testGetAdminDealerPackages() {
        System.runAs(getPortalUser()) {
            Test.startTest();
            List<DealerPortalMarkupController.AdminDealerPackageDTO> result = DealerPortalMarkupController.getAdminDealerPackages();
            Test.stopTest();

            Assert.isFalse(result.isEmpty());
            Assert.isNotNull(result[0].terms, 'Admin DTO should have flat terms list');
        }
    }

    @isTest
    static void testGetAdminDealerPackageOptions() {
        System.runAs(getPortalUser()) {
            Test.startTest();
            // Total Loss uses categories, Extended Warranty uses terms
            List<DealerPortalMarkupController.PackageWithOptionsDTO> result = 
                DealerPortalMarkupController.getAdminDealerPackageOptions(String.valueOf(System.currentTimeMillis()));
            Test.stopTest();

            Assert.isFalse(result.isEmpty());
            // Verify Total Loss Category Logic
            Boolean foundCategory = false;
            for(DealerPortalMarkupController.PackageWithOptionsDTO dto : result) {
                if(!dto.categories.isEmpty()) foundCategory = true;
            }
            Assert.isTrue(foundCategory, 'Should have populated categories for Total Loss package');
        }
    }

    // ── Term Markup Updates ────────────────────────────────────────────────────

    @isTest
    static void testUpdateTermMarkups_BulkAndSpecific() {
        Dealer_Package_Term__c term = [SELECT Id FROM Dealer_Package_Term__c LIMIT 1];
        
        System.runAs(getPortalUser()) {
            Test.startTest();
            // Test Single Update
            String res1 = DealerPortalMarkupController.updateTermMarkup(term.Id, 25.0, '$');
            
            // Test Bulk All
            String res2 = DealerPortalMarkupController.updateAllTermMarkups(30.0, '%');
            
            // Test Specific
            String res3 = DealerPortalMarkupController.updateSpecificTermMarkups(15.0, '$', new List<String>{term.Id});
            Test.stopTest();
        }
    }

    // ── Option Markup Updates ──────────────────────────────────────────────────

    @isTest
    static void testUpdateOptionMarkups_All() {
        Dealer_Package_Option__c opt = [SELECT Id FROM Dealer_Package_Option__c LIMIT 1];

        System.runAs(getPortalUser()) {
            Test.startTest();
            String res1 = DealerPortalMarkupController.updateOptionMarkup(opt.Id, 10, '$');
            String res2 = DealerPortalMarkupController.updateAllOptionMarkups(5, '%');
            String res3 = DealerPortalMarkupController.updateSpecificOptionMarkups(2, '$', new List<String>{opt.Id});
            Test.stopTest();

            Assert.areEqual('Success', res1);
            Assert.isTrue(res2.contains('Success'));
            Assert.isTrue(res3.contains('Success'));
        }
    }

    // ── Negative Paths & Validation ───────────────────────────────────────────

    @isTest
    static void testValidationErrors() {
        System.runAs(getPortalUser()) {
            Test.startTest();
            // Negative markup
            String err1 = DealerPortalMarkupController.updateAllTermMarkups(-5, '%');
            String err2 = DealerPortalMarkupController.updateAllOptionMarkups(-1, '$');
            
            // Empty ID list
            String err3 = DealerPortalMarkupController.updateSpecificTermMarkups(10, '%', new List<String>());
            String err4 = DealerPortalMarkupController.updateSpecificOptionMarkups(10, '%', null);
            Test.stopTest();

            Assert.isTrue(err1.contains('Error'));
            Assert.isTrue(err2.contains('Error'));
            Assert.isTrue(err3.contains('Error'));
            Assert.isTrue(err4.contains('Error'));
        }
    }

    @isTest
    static void testCatchBlocks() {
        // Run as internal user with no contact to force getCurrentDealerId to return null
        // or trigger empty results in catchable blocks
        Test.startTest();
        List<DealerPortalMarkupController.DealerPackageDTO> res1 = DealerPortalMarkupController.getDealerPackagesHierarchy();
        String res2 = DealerPortalMarkupController.updateTermMarkup('invalidid', 10, '$');
        Test.stopTest();

        Assert.isTrue(res1.isEmpty(), 'Should return empty list for internal user');
        Assert.isTrue(res2.startsWith('Error'), 'Should catch invalid ID exception');
    }
}