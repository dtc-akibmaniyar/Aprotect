/**
 * CreatePackageOptionsControllerTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Covers CreatePackageOptionsController:
 *   • getRecordInfo             — resolves object metadata for Package__c / Package_Term__c
 *   • getPackageName            — traverses relationships to return the Package name
 *   • getOptions                — returns all Option__c catalog records
 *   • getCategoryPicklistValues — reads Category__c picklist metadata
 *   • createPackageOptions      — creates Package_Option__c records (included / optional)
 *
 * Test Strategy:
 *   ✔ @isTest(SeeAllData=false)
 *   ✔ All DML via TestDataFactory; Option__c created inline (no factory method)
 *   ✔ Positive + Negative per branch
 *   ✔ System.assert* with descriptive messages
 *   ✔ Test.startTest / Test.stopTest
 */
@isTest(SeeAllData=false)
private class CreatePackageOptionsControllerTest {

    @TestSetup
    static void setup() {
        // Option__c catalog entry — no TestDataFactory method, created inline
        insert new Option__c(Name = 'Roadside Assistance');

        Package__c pkg       = TestDataFactory.createPackage('Extended_Limited_Warranty', true);
        Package_Tier__c tier = TestDataFactory.createPackageTier(pkg.Id, true);
        TestDataFactory.createPackageTerm(pkg.Id, tier.Id, true);
    }

    // ── Query helpers ─────────────────────────────────────────────────────────

    private static Package__c getPackage() {
        return [SELECT Id, Name FROM Package__c LIMIT 1];
    }

    private static Package_Term__c getPackageTerm() {
        return [SELECT Id FROM Package_Term__c LIMIT 1];
    }

    private static Option__c getOption() {
        return [SELECT Id, Name FROM Option__c LIMIT 1];
    }

    // ═════════════════════════════════════════════════════════════════════════
    // getRecordInfo
    // ═════════════════════════════════════════════════════════════════════════

    @isTest
    static void testGetRecordInfo_packageId_returnsPackageInfo() {
        Package__c pkg = getPackage();

        Test.startTest();
        CreatePackageOptionsController.RecordInfoDTO dto =
            CreatePackageOptionsController.getRecordInfo(pkg.Id);
        Test.stopTest();

        System.assertNotEquals(null, dto,
            'RecordInfoDTO should not be null for a valid Package__c ID');
        System.assertEquals('Package__c', dto.objectApiName,
            'objectApiName should be Package__c');
        System.assertEquals(pkg.Id, dto.packageId,
            'packageId should match the input ID');
        System.assertNotEquals(null, dto.packageName,
            'packageName should be populated');
    }

    @isTest
    static void testGetRecordInfo_packageTermId_returnsTermHierarchyInfo() {
        Package_Term__c term = getPackageTerm();

        Test.startTest();
        CreatePackageOptionsController.RecordInfoDTO dto =
            CreatePackageOptionsController.getRecordInfo(term.Id);
        Test.stopTest();

        System.assertNotEquals(null, dto,
            'RecordInfoDTO should not be null for a valid Package_Term__c ID');
        System.assertEquals('Package_Term__c', dto.objectApiName,
            'objectApiName should be Package_Term__c');
        System.assertNotEquals(null, dto.termName,
            'termName should be populated from the Package_Term__c record');
    }

    @isTest
    static void testGetRecordInfo_nullId_returnsNull() {
        Test.startTest();
        CreatePackageOptionsController.RecordInfoDTO dto =
            CreatePackageOptionsController.getRecordInfo(null);
        Test.stopTest();

        System.assertEquals(null, dto,
            'getRecordInfo should return null when a null ID is passed');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // getPackageName
    // ═════════════════════════════════════════════════════════════════════════

    @isTest
    static void testGetPackageName_packageId_returnsPackageName() {
        Package__c pkg = getPackage();

        Test.startTest();
        String name = CreatePackageOptionsController.getPackageName(pkg.Id);
        Test.stopTest();

        System.assertEquals(pkg.Name, name,
            'getPackageName should return the Package__c.Name');
    }

    @isTest
    static void testGetPackageName_packageTermId_traversesToAncestorPackage() {
        Package_Term__c term = getPackageTerm();
        Package__c pkg       = getPackage();

        Test.startTest();
        String name = CreatePackageOptionsController.getPackageName(term.Id);
        Test.stopTest();

        System.assertEquals(pkg.Name, name,
            'getPackageName on a Package_Term__c should traverse to the ancestor Package__c name');
    }

    @isTest
    static void testGetPackageName_nullId_returnsNull() {
        Test.startTest();
        String name = CreatePackageOptionsController.getPackageName(null);
        Test.stopTest();

        System.assertEquals(null, name,
            'getPackageName should return null for a null ID');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // getOptions
    // ═════════════════════════════════════════════════════════════════════════

    @isTest
    static void testGetOptions_returnsNonNullListWithAtLeastOneEntry() {
        Test.startTest();
        List<CreatePackageOptionsController.OptionDTO> opts =
            CreatePackageOptionsController.getOptions();
        Test.stopTest();

        System.assertNotEquals(null, opts,
            'getOptions should never return null');
        System.assert(opts.size() >= 1,
            'At least the Option__c inserted in @TestSetup should be returned');
    }

    @isTest
    static void testGetOptions_dtosHaveIdAndName() {
        Test.startTest();
        List<CreatePackageOptionsController.OptionDTO> opts =
            CreatePackageOptionsController.getOptions();
        Test.stopTest();

        for (CreatePackageOptionsController.OptionDTO dto : opts) {
            System.assertNotEquals(null, dto.Id,
                'Each OptionDTO should have a non-null Id');
            System.assertNotEquals(null, dto.Name,
                'Each OptionDTO should have a non-null Name');
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // getCategoryPicklistValues
    // ═════════════════════════════════════════════════════════════════════════

    @isTest
    static void testGetCategoryPicklistValues_returnsNonNullList() {
        Test.startTest();
        List<String> values = CreatePackageOptionsController.getCategoryPicklistValues();
        Test.stopTest();

        System.assertNotEquals(null, values,
            'getCategoryPicklistValues should never return null');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // createPackageOptions — included from Package__c
    // ═════════════════════════════════════════════════════════════════════════

    @isTest
    static void testCreatePackageOptions_includedFromPackage_createsIncludedRecord() {
        Package__c pkg = getPackage();
        Option__c opt  = getOption();

        CreatePackageOptionsController.PackageOptionRowDTO row =
            new CreatePackageOptionsController.PackageOptionRowDTO();
        row.optionId       = opt.Id;
        row.inclusionText  = 'Covers breakdown';
        row.exclusionText  = 'Excludes wear';

        Test.startTest();
        String result = CreatePackageOptionsController.createPackageOptions(
            pkg.Id, JSON.serialize(new List<CreatePackageOptionsController.PackageOptionRowDTO>{ row }), true
        );
        Test.stopTest();

        System.assert(result.startsWith('Success'),
            'Should return a Success message for valid included options; got: ' + result);

        List<Package_Option__c> created = [
            SELECT Id, Package__c, Selection_Type__c
            FROM Package_Option__c
            WHERE Package__c = :pkg.Id AND Selection_Type__c = 'Included'
        ];
        System.assertEquals(1, created.size(),
            'Exactly one Included Package_Option__c should be created');
    }

    @isTest
    static void testCreatePackageOptions_optionalFromPackageTerm_createsOptionalRecord() {
        Package_Term__c term = getPackageTerm();
        Option__c opt        = getOption();

        CreatePackageOptionsController.PackageOptionRowDTO row =
            new CreatePackageOptionsController.PackageOptionRowDTO();
        row.optionId      = opt.Id;
        row.price         = 99.00;
        row.packageTermId = term.Id;

        Test.startTest();
        String result = CreatePackageOptionsController.createPackageOptions(
            term.Id, JSON.serialize(new List<CreatePackageOptionsController.PackageOptionRowDTO>{ row }), false
        );
        Test.stopTest();

        System.assert(result.startsWith('Success'),
            'Should return a Success message for valid optional options from a Package_Term__c; got: ' + result);

        List<Package_Option__c> created = [
            SELECT Id FROM Package_Option__c
            WHERE Package_Term__c = :term.Id AND Selection_Type__c = 'Optional'
        ];
        System.assertEquals(1, created.size(),
            'Exactly one Optional Package_Option__c linked to the term should be created');
    }

    @isTest
    static void testCreatePackageOptions_nullRecordId_returnsError() {
        Option__c opt = getOption();

        CreatePackageOptionsController.PackageOptionRowDTO row =
            new CreatePackageOptionsController.PackageOptionRowDTO();
        row.optionId = opt.Id;
        row.price    = 50.00;

        Test.startTest();
        String result = CreatePackageOptionsController.createPackageOptions(
            null, JSON.serialize(new List<CreatePackageOptionsController.PackageOptionRowDTO>{ row }), false
        );
        Test.stopTest();

        System.assert(result.startsWith('Error'),
            'Should return an Error message when recordId is null; got: ' + result);
    }

    @isTest
    static void testCreatePackageOptions_emptyRows_returnsError() {
        Package__c pkg = getPackage();

        Test.startTest();
        String result = CreatePackageOptionsController.createPackageOptions(
            pkg.Id,
            JSON.serialize(new List<CreatePackageOptionsController.PackageOptionRowDTO>()),
            true
        );
        Test.stopTest();

        System.assert(result.startsWith('Error'),
            'Should return an Error message when rows list is empty; got: ' + result);
    }

    @isTest
    static void testCreatePackageOptions_missingOptionId_returnsError() {
        Package__c pkg = getPackage();

        CreatePackageOptionsController.PackageOptionRowDTO row =
            new CreatePackageOptionsController.PackageOptionRowDTO();
        // optionId intentionally left null
        row.price = 50.00;

        Test.startTest();
        String result = CreatePackageOptionsController.createPackageOptions(
            pkg.Id, JSON.serialize(new List<CreatePackageOptionsController.PackageOptionRowDTO>{ row }), false
        );
        Test.stopTest();

        System.assert(result.startsWith('Error'),
            'Should return an Error message when optionId is missing; got: ' + result);
    }

    @isTest
    static void testCreatePackageOptions_negativePriceForOptional_returnsError() {
        Package__c pkg = getPackage();
        Option__c opt  = getOption();

        CreatePackageOptionsController.PackageOptionRowDTO row =
            new CreatePackageOptionsController.PackageOptionRowDTO();
        row.optionId = opt.Id;
        row.price    = -5.00;

        Test.startTest();
        String result = CreatePackageOptionsController.createPackageOptions(
            pkg.Id, JSON.serialize(new List<CreatePackageOptionsController.PackageOptionRowDTO>{ row }), false
        );
        Test.stopTest();

        System.assert(result.startsWith('Error'),
            'Should return an Error message when optional option price is negative; got: ' + result);
    }
}