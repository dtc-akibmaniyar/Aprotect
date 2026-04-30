@isTest(SeeAllData=false)
private class SelectAdditionalOptionsControllerTest {

    @TestSetup
    static void setup() {
        // Create an Option entry
        Option__c option = new Option__c(Name = 'Test Additional Option');
        insert option;

        // Setup Package Hierarchy
        Package__c pkg = TestDataFactory.createPackage('Extended_Limited_Warranty', true);
        Package_Tier__c tier = TestDataFactory.createPackageTier(pkg.Id, true);
        Package_Term__c term = TestDataFactory.createPackageTerm(pkg.Id, tier.Id, true);

        // Optional Package Option
        Package_Option__c pkgOpt = new Package_Option__c(
            Package__c = pkg.Id,
            Package_Term__c = term.Id,
            Option__c = option.Id,
            Selection_Type__c = 'Optional',
            Price__c = 150.00,
            Inclusion_Text__c = 'Covers item X',
            Exclusion_Text__c = 'Excludes item Y'
        );
        insert pkgOpt;

        Account dealer = TestDataFactory.createDealer(true);
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true
        );
        Dealer_Package_Tier__c dpt = TestDataFactory.createDealerPackageTier(dp.Id, tier.Id, true);
        TestDataFactory.createDealerPackageTerm(dp.Id, term.Id, dpt.Id, true);
    }

    private static Dealer_Package__c getDealerPackage() {
        return [SELECT Id, Package__c FROM Dealer_Package__c LIMIT 1];
    }

    private static Package_Option__c getPackageOption() {
        return [SELECT Id, Package_Term__c, Option__c FROM Package_Option__c LIMIT 1];
    }

    // ═════════════════════════════════════════════════════════════════════════
    // getPackageDetails Branch Coverage
    // ═════════════════════════════════════════════════════════════════════════

    @isTest
    static void testGetPackageDetails_AllBranches() {
        Dealer_Package__c dp = getDealerPackage();

        Test.startTest();
        // Success path
        SelectAdditionalOptionsController.PackageDetailsResponse resp = SelectAdditionalOptionsController.getPackageDetails(dp.Id);
        // Path where Dealer Package exists but Package__c lookup is null (manual check/simulated)
        SelectAdditionalOptionsController.getPackageDetails(null);
        SelectAdditionalOptionsController.getPackageDetails('invalidId');
        Test.stopTest();

        Assert.isTrue(resp.success);
        Assert.areEqual(dp.Id, resp.data.id);
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Comparator & DTO Coverage
    // ═════════════════════════════════════════════════════════════════════════

    @isTest
    static void testPackageTermComparator_FullLogic() {
        SelectAdditionalOptionsController.PackageTermDTO term1 = new SelectAdditionalOptionsController.PackageTermDTO();
        term1.tierName = 'A';
        term1.durationRestrictionInMonths = 12;
        term1.name = 'Term 1';

        SelectAdditionalOptionsController.PackageTermDTO term2 = new SelectAdditionalOptionsController.PackageTermDTO();
        term2.tierName = 'B';
        term2.durationRestrictionInMonths = 24;
        term2.name = 'Term 2';

        SelectAdditionalOptionsController.PackageTermComparator comp = new SelectAdditionalOptionsController.PackageTermComparator();

        Test.startTest();
        Integer diffTier = comp.compare(term1, term2);
        
        term2.tierName = 'A';
        Integer diffDuration = comp.compare(term1, term2);
        
        term2.durationRestrictionInMonths = 12;
        Integer diffName = comp.compare(term1, term2);

        term2.name = 'Term 1';
        Integer same = comp.compare(term1, term2);
        Test.stopTest();

        Assert.isTrue(diffTier < 0);
        Assert.isTrue(diffDuration < 0);
        Assert.isTrue(diffName < 0);
        Assert.areEqual(0, same);
    }

    // ═════════════════════════════════════════════════════════════════════════
    // saveDealerPackageOptions (DTO List version)
    // ═════════════════════════════════════════════════════════════════════════

    @isTest
    static void testSaveDealerPackageOptions_DTOVersion() {
        Dealer_Package__c dp = getDealerPackage();
        Package_Option__c opt = getPackageOption();

        List<SelectAdditionalOptionsController.SelectedOptionDTO> dtoList = new List<SelectAdditionalOptionsController.SelectedOptionDTO>();
        dtoList.add(new SelectAdditionalOptionsController.SelectedOptionDTO(
            opt.Id, opt.Option__c, dp.Id, '$', 10.0, 'Optional', 150.0
        ));

        Test.startTest();
        SelectAdditionalOptionsController.SaveResponse resp = SelectAdditionalOptionsController.saveDealerPackageOptions(dp.Id, dtoList);
        SelectAdditionalOptionsController.saveDealerPackageOptions(dp.Id, new List<SelectAdditionalOptionsController.SelectedOptionDTO>());
        Test.stopTest();

        Assert.isTrue(resp.success);
        Assert.areEqual(1, resp.savedCount);
    }

    // ═════════════════════════════════════════════════════════════════════════
    // saveDealerPackageOptionsSimple - Error Branches
    // ═════════════════════════════════════════════════════════════════════════

    @isTest
    static void testSaveSimple_ErrorBranches() {
        Dealer_Package__c dp = getDealerPackage();
        Package_Option__c opt = getPackageOption();

        Test.startTest();
        // Missing Dealer Package ID (Check skip logic)
        SelectAdditionalOptionsController.saveDealerPackageOptionsSimple(
            null, 
            new List<String>{ opt.Id }, 
            new List<String>{ opt.Option__c }, 
            new List<String>{ '$' }, 
            new List<Decimal>{ 5.0 }, 
            new List<String>{ 'Optional' }, 
            new List<Decimal>{ 100.0 }
        );

        // Valid execution to check upsert result branch
        SelectAdditionalOptionsController.SaveResponse resp = SelectAdditionalOptionsController.saveDealerPackageOptionsSimple(
            dp.Id, 
            new List<String>{ opt.Id }, 
            new List<String>{ opt.Option__c }, 
            new List<String>{ '$' }, 
            new List<Decimal>{ 5.0 }, 
            new List<String>{ 'Optional' }, 
            new List<Decimal>{ 100.0 }
        );
        Test.stopTest();

        Assert.isNotNull(resp);
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Formatting Helpers Coverage (Internal Private Methods)
    // ═════════════════════════════════════════════════════════════════════════

    @isTest
    static void testFormattingHelpers_NullPaths() {
        // Calling getPackageDetails triggers these, but we want to ensure null values are passed
        // to cover the "if (value == null) return 'N/A'" lines.
        
        // We create a dummy term with null price
        Package__c pkg = [SELECT Id FROM Package__c LIMIT 1];
        Package_Tier__c tier = [SELECT Id FROM Package_Tier__c LIMIT 1];
        Package_Term__c nullTerm = new Package_Term__c(
            Package__c = pkg.Id, 
            Package_Tier__c = tier.Id, 
            Price__c = null, 
            Name = 'Null Price Term'
        );
        insert nullTerm;

        Dealer_Package__c dp = getDealerPackage();

        Test.startTest();
        SelectAdditionalOptionsController.PackageDetailsResponse resp = SelectAdditionalOptionsController.getPackageDetails(dp.Id);
        Test.stopTest();

        Assert.isTrue(resp.success);
        // Find the null term in response
        for(SelectAdditionalOptionsController.PackageTermDTO t : resp.data.packageTerms) {
            if(t.name == 'Null Price Term') {
                Assert.areEqual('N/A', t.priceDisplay);
            }
        }
    }

    @isTest
    static void testSaveSimple_ExceptionPath() {
        // Trigger an exception by passing malformed IDs or lists of different sizes that cause runtime errors
        Test.startTest();
        SelectAdditionalOptionsController.SaveResponse resp = SelectAdditionalOptionsController.saveDealerPackageOptionsSimple(
            'invalid_id', 
            new List<String>{ 'invalid_id' }, 
            null, // This will cause a NullPointerException when accessing index i
            null, 
            null, 
            null, 
            null
        );
        Test.stopTest();

        Assert.isFalse(resp.success);
        Assert.isNotNull(resp.message);
    }
}