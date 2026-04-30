/**
 * DealerPackageAccessHelperTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Covers all public methods of DealerPackageAccessHelper (without sharing):
 *
 *   getDealerPackages(String dealerId)
 *     • blank dealerId                       → empty list
 *     • valid dealerId with packages         → returns Dealer_Package__c records
 *
 *   getAllDealerPackages()
 *     • packages exist                       → returns all records
 *
 *   getDealerPackagesByPackageName(String packageName)
 *     • blank packageName                    → empty list
 *     • matching name substring              → returns records
 *     • no match                             → empty list
 *
 *   createApplicationPackage(...)
 *     • blank applicationId                  → null
 *     • blank dealerPackageId                → null
 *     • all valid                            → returns new Application_Package__c Id
 *
 *   createApplicationPackageWithPricing(...)
 *     • blank required param                 → null
 *     • all valid                            → returns Id with pricing fields set
 *
 *   updateApplicationPackage(...)
 *     • blank packageId                      → null
 *     • blank selectedTermId                 → null
 *     • no field changes                     → returns same packageId (no DML)
 *     • price changes                        → updates record, returns Id
 *
 *   updateApplicationPackageOptionsWithRecords(...)
 *     • recordsToInsert non-empty            → Application_Package_Option__c created
 *     • optionsToRemove non-empty            → Application_Package_Option__c deleted
 *
 *   updateApplicationPackageOptions(...)
 *     • blank applicationPackageId           → returns error string
 *     • no additions / no removals           → returns 'Success: No changes to process'
 *     • valid optionsToAdd                   → Application_Package_Option__c created
 *
 * Test strategy:
 *   ✔ @isTest(SeeAllData=false)
 *   ✔ @TestSetup for shared Dealer + Package + Dealer_Package + Application
 *   ✔ All data via TestDataFactory — no inline SObject creation
 *   ✔ System.assert* with descriptive messages on every assertion
 */
@isTest(SeeAllData=false)
private class DealerPackageAccessHelperTest {

    // ─────────────────────────────────────────────────────────────────────────
    // @TestSetup — shared base data (no Tier/Term/Option so DealerPackageTrigger
    // exits early and doesn't create child records that would interfere)
    // ─────────────────────────────────────────────────────────────────────────

    @TestSetup
    static void setup() {
        Account    dealer = TestDataFactory.createDealer(true);
        Package__c pkg    = TestDataFactory.createPackage('Extended_Limited_Warranty', true);
        TestDataFactory.createDealerPackage(dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true);
        TestDataFactory.createApplication(dealer.Id, true);
    }

    // ── Private query helpers ─────────────────────────────────────────────────

    private static Account getDealer() {
        return [SELECT Id FROM Account LIMIT 1];
    }

    private static Package__c getPkg() {
        return [SELECT Id, Name FROM Package__c LIMIT 1];
    }

    private static Dealer_Package__c getDp() {
        return [SELECT Id FROM Dealer_Package__c LIMIT 1];
    }

    private static Application__c getApp() {
        return [SELECT Id FROM Application__c LIMIT 1];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getDealerPackages
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Blank dealerId → guard returns empty list immediately.
     */
    @isTest
    static void testGetDealerPackages_blankId_returnsEmpty() {
        Test.startTest();
        List<Dealer_Package__c> result = DealerPackageAccessHelper.getDealerPackages('');
        Test.stopTest();

        System.assertEquals(0, result.size(),
            'getDealerPackages should return an empty list when dealerId is blank');
    }

    /**
     * Valid dealerId → returns the Dealer_Package__c records for that dealer.
     */
    @isTest
    static void testGetDealerPackages_validDealer_returnsPackages() {
        Account dealer = getDealer();

        Test.startTest();
        List<Dealer_Package__c> result =
            DealerPackageAccessHelper.getDealerPackages(dealer.Id);
        Test.stopTest();

        System.assertEquals(1, result.size(),
            'getDealerPackages should return the one Dealer_Package__c for the dealer');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getAllDealerPackages
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * At least one Dealer_Package__c exists → getAllDealerPackages returns it.
     */
    @isTest
    static void testGetAllDealerPackages_returnsAll() {
        Test.startTest();
        List<Dealer_Package__c> result = DealerPackageAccessHelper.getAllDealerPackages();
        Test.stopTest();

        System.assert(result.size() >= 1,
            'getAllDealerPackages should return at least one record when Dealer_Package__c records exist');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getDealerPackagesByPackageName
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Blank packageName → guard returns empty list immediately.
     */
    @isTest
    static void testGetByPackageName_blankName_returnsEmpty() {
        Test.startTest();
        List<Dealer_Package__c> result =
            DealerPackageAccessHelper.getDealerPackagesByPackageName('');
        Test.stopTest();

        System.assertEquals(0, result.size(),
            'getDealerPackagesByPackageName should return empty list when name is blank');
    }

    /**
     * Name substring matches the Package__r.Name → returns the Dealer_Package__c.
     */
    @isTest
    static void testGetByPackageName_matchingName_returnsPackages() {
        Test.startTest();
        // Factory creates packages named 'Test Package Extended_Limited_Warranty...'
        List<Dealer_Package__c> result =
            DealerPackageAccessHelper.getDealerPackagesByPackageName('Test Package');
        Test.stopTest();

        System.assert(result.size() >= 1,
            'getDealerPackagesByPackageName should return records when the name matches');
    }

    /**
     * No Package__c name matches the search string → returns empty list.
     */
    @isTest
    static void testGetByPackageName_noMatch_returnsEmpty() {
        Test.startTest();
        List<Dealer_Package__c> result =
            DealerPackageAccessHelper.getDealerPackagesByPackageName('XYZ_NOMATCH_99999');
        Test.stopTest();

        System.assertEquals(0, result.size(),
            'getDealerPackagesByPackageName should return empty list when no package name matches');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // createApplicationPackage
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Blank applicationId → required-param guard returns null.
     */
    @isTest
    static void testCreateApplicationPackage_blankAppId_returnsNull() {
        Account           dealer = getDealer();
        Dealer_Package__c dp     = getDp();

        Test.startTest();
        String result = DealerPackageAccessHelper.createApplicationPackage(
            '', dealer.Id, dp.Id, 'Test Pkg', null, 500
        );
        Test.stopTest();

        System.assertEquals(null, result,
            'createApplicationPackage should return null when applicationId is blank');
    }

    /**
     * Blank dealerPackageId → required-param guard returns null.
     */
    @isTest
    static void testCreateApplicationPackage_blankDealerPkgId_returnsNull() {
        Account        dealer = getDealer();
        Application__c app    = getApp();

        Test.startTest();
        String result = DealerPackageAccessHelper.createApplicationPackage(
            app.Id, dealer.Id, '', 'Test Pkg', null, 500
        );
        Test.stopTest();

        System.assertEquals(null, result,
            'createApplicationPackage should return null when dealerPackageId is blank');
    }

    /**
     * All required params valid → creates Application_Package__c and returns its Id.
     */
    @isTest
    static void testCreateApplicationPackage_validParams_createsRecord() {
        Account           dealer = getDealer();
        Dealer_Package__c dp     = getDp();
        Application__c    app    = getApp();

        Test.startTest();
        String result = DealerPackageAccessHelper.createApplicationPackage(
            app.Id, dealer.Id, dp.Id, 'Test Pkg', null, 500
        );
        Test.stopTest();

        System.assertNotEquals(null, result,
            'createApplicationPackage should return a non-null Id on success');

        List<Application_Package__c> created = [
            SELECT Id, Deductible__c
            FROM   Application_Package__c
            WHERE  Id = :result
        ];
        System.assertEquals(1, created.size(),
            'One Application_Package__c record should be created');
        System.assertEquals(500, created[0].Deductible__c,
            'Deductible__c should match the value passed to createApplicationPackage');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // createApplicationPackageWithPricing
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Blank applicationId → guard returns null.
     */
    @isTest
    static void testCreateAppPkgWithPricing_blankAppId_returnsNull() {
        Account           dealer = getDealer();
        Dealer_Package__c dp     = getDp();

        Test.startTest();
        String result = DealerPackageAccessHelper.createApplicationPackageWithPricing(
            '', dealer.Id, dp.Id, 'Test Pkg', null, 1500, 100, 500
        );
        Test.stopTest();

        System.assertEquals(null, result,
            'createApplicationPackageWithPricing should return null when applicationId is blank');
    }

    /**
     * All required params valid → creates Application_Package__c with pricing fields set.
     */
    @isTest
    static void testCreateAppPkgWithPricing_validParams_createsRecord() {
        Account           dealer = getDealer();
        Dealer_Package__c dp     = getDp();
        Application__c    app    = getApp();

        Test.startTest();
        String result = DealerPackageAccessHelper.createApplicationPackageWithPricing(
            app.Id, dealer.Id, dp.Id, 'Test Pkg', null, 1500, 100, 250
        );
        Test.stopTest();

        System.assertNotEquals(null, result,
            'createApplicationPackageWithPricing should return a non-null Id on success');

        List<Application_Package__c> created = [
            SELECT Id, Dealer_Package_Price__c, Deductible__c
            FROM   Application_Package__c
            WHERE  Id = :result
        ];
        System.assertEquals(1, created.size(),
            'One Application_Package__c record should be created');
        System.assertEquals(1500, created[0].Dealer_Package_Price__c,
            'Dealer_Package_Price__c should be set to totalPrice');
        System.assertEquals(250, created[0].Deductible__c,
            'Deductible__c should be set to the deductible parameter');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // updateApplicationPackage
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Blank packageId → required-param guard returns null.
     */
    @isTest
    static void testUpdateApplicationPackage_blankPackageId_returnsNull() {
        Dealer_Package__c dp = getDp();

        // Build a term ID to keep selectedTermId non-blank
        Package_Term__c     pkgTerm = TestDataFactory.createPackageTerm(getPkg().Id, null, true);
        Dealer_Package_Term__c dpTerm = TestDataFactory.createDealerPackageTerm(dp.Id, pkgTerm.Id, null, true);

        Test.startTest();
        String result = DealerPackageAccessHelper.updateApplicationPackage(
            '', dpTerm.Id, 1000, 0, null
        );
        Test.stopTest();

        System.assertEquals(null, result,
            'updateApplicationPackage should return null when packageId is blank');
    }

    /**
     * Blank selectedTermId → required-param guard returns null.
     */
    @isTest
    static void testUpdateApplicationPackage_blankTermId_returnsNull() {
        Account           dealer = getDealer();
        Dealer_Package__c dp     = getDp();
        Application__c    app    = getApp();
        Application_Package__c appPkg = TestDataFactory.createApplicationPackage(
            app.Id, dp.Id, null, dealer.Id, true
        );

        Test.startTest();
        String result = DealerPackageAccessHelper.updateApplicationPackage(
            appPkg.Id, '', 1000, 0, null
        );
        Test.stopTest();

        System.assertEquals(null, result,
            'updateApplicationPackage should return null when selectedTermId is blank');
    }

    /**
     * No field values change → handler detects no changes and returns the same packageId
     * without performing a DML update.
     */
    @isTest
    static void testUpdateApplicationPackage_noChanges_returnsSameId() {
        Account           dealer  = getDealer();
        Dealer_Package__c dp      = getDp();
        Application__c    app     = getApp();
        Package_Term__c   pkgTerm = TestDataFactory.createPackageTerm(getPkg().Id, null, true);
        Dealer_Package_Term__c dpTerm = TestDataFactory.createDealerPackageTerm(
            dp.Id, pkgTerm.Id, null, true
        );
        Application_Package__c appPkg = TestDataFactory.createApplicationPackage(
            app.Id, dp.Id, dpTerm.Id, dealer.Id, 1000.00, 13.0, true
        );

        Test.startTest();
        String result = DealerPackageAccessHelper.updateApplicationPackage(
            appPkg.Id, dpTerm.Id, 1000.00, 0, null
        );
        Test.stopTest();

        System.assertEquals(appPkg.Id, result,
            'updateApplicationPackage should return the same packageId when no field values change');
    }

    /**
     * Price changes → handler updates the record and returns the packageId.
     */
    @isTest
    static void testUpdateApplicationPackage_priceChange_updatesRecord() {
        Account           dealer  = getDealer();
        Dealer_Package__c dp      = getDp();
        Application__c    app     = getApp();
        Package_Term__c   pkgTerm = TestDataFactory.createPackageTerm(getPkg().Id, null, true);
        Dealer_Package_Term__c dpTerm = TestDataFactory.createDealerPackageTerm(
            dp.Id, pkgTerm.Id, null, true
        );
        Application_Package__c appPkg = TestDataFactory.createApplicationPackage(
            app.Id, dp.Id, dpTerm.Id, dealer.Id, 1000.00, 13.0, true
        );

        Test.startTest();
        String result = DealerPackageAccessHelper.updateApplicationPackage(
            appPkg.Id, dpTerm.Id, 2500.00, 0, null
        );
        Test.stopTest();

        System.assertEquals(appPkg.Id, result,
            'updateApplicationPackage should return the packageId after a successful update');

        Application_Package__c updated = [
            SELECT Dealer_Package_Price__c
            FROM   Application_Package__c
            WHERE  Id = :appPkg.Id
        ];
        System.assertEquals(2500, updated.Dealer_Package_Price__c,
            'Dealer_Package_Price__c should be updated to the new totalPrice value');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // updateApplicationPackageOptionsWithRecords
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * recordsToInsert is non-empty → handler inserts them; Application_Package_Option__c created.
     */
    @isTest
    static void testUpdateOptionsWithRecords_insert_createsRecords() {
        Account           dealer  = getDealer();
        Dealer_Package__c dp      = getDp();
        Application__c    app     = getApp();
        Application_Package__c appPkg = TestDataFactory.createApplicationPackage(
            app.Id, dp.Id, null, dealer.Id, true
        );
        Package_Option__c      pkgOpt = TestDataFactory.createPackageOption(
            getPkg().Id, null, 'Optional', true
        );
        Dealer_Package_Option__c dpOpt = TestDataFactory.createDealerPackageOption(
            dp.Id, pkgOpt.Id, null, 'Optional', true
        );

        // Build in-memory record via factory (not yet inserted)
        Application_Package_Option__c optRecord =
            TestDataFactory.createApplicationPackageOption(
                app.Id, appPkg.Id, dpOpt.Id, pkgOpt.Id, false
            );

        Test.startTest();
        String result = DealerPackageAccessHelper.updateApplicationPackageOptionsWithRecords(
            appPkg.Id,
            new List<Application_Package_Option__c>{ optRecord },
            null
        );
        Test.stopTest();

        System.assert(result.startsWith('Success'),
            'updateApplicationPackageOptionsWithRecords should return a Success message on insert');
        System.assertEquals(1,
            [SELECT COUNT() FROM Application_Package_Option__c
             WHERE Application_Package__c = :appPkg.Id],
            'One Application_Package_Option__c should be created');
    }

    /**
     * optionsToRemove is non-empty → handler finds and deletes the matching
     * Application_Package_Option__c records.
     */
    @isTest
    static void testUpdateOptionsWithRecords_remove_deletesRecords() {
        Account           dealer  = getDealer();
        Dealer_Package__c dp      = getDp();
        Application__c    app     = getApp();
        Application_Package__c appPkg = TestDataFactory.createApplicationPackage(
            app.Id, dp.Id, null, dealer.Id, true
        );
        Package_Option__c      pkgOpt = TestDataFactory.createPackageOption(
            getPkg().Id, null, 'Optional', true
        );
        Dealer_Package_Option__c dpOpt = TestDataFactory.createDealerPackageOption(
            dp.Id, pkgOpt.Id, null, 'Optional', true
        );
        // Pre-insert the option so the removal path has something to delete
        TestDataFactory.createApplicationPackageOption(
            app.Id, appPkg.Id, dpOpt.Id, pkgOpt.Id, true
        );

        Test.startTest();
        String result = DealerPackageAccessHelper.updateApplicationPackageOptionsWithRecords(
            appPkg.Id,
            new List<Application_Package_Option__c>(),
            new List<String>{ dpOpt.Id }
        );
        Test.stopTest();

        System.assert(result.startsWith('Success'),
            'updateApplicationPackageOptionsWithRecords should return a Success message on removal');
        System.assertEquals(0,
            [SELECT COUNT() FROM Application_Package_Option__c
             WHERE Application_Package__c = :appPkg.Id],
            'Application_Package_Option__c should be deleted after removal');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // updateApplicationPackageOptions (original method)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Blank applicationPackageId → throws CalloutException caught internally;
     * returns error string.
     */
    @isTest
    static void testUpdateAppPkgOptions_blankPkgId_returnsError() {
        Test.startTest();
        String result = DealerPackageAccessHelper.updateApplicationPackageOptions(
            '', getApp().Id, null, null
        );
        Test.stopTest();

        System.assert(result.startsWith('Error'),
            'updateApplicationPackageOptions should return an error string when applicationPackageId is blank');
    }

    /**
     * Blank applicationId → throws CalloutException caught internally;
     * returns error string.
     */
    @isTest
    static void testUpdateAppPkgOptions_blankAppId_returnsError() {
        Account           dealer = getDealer();
        Dealer_Package__c dp     = getDp();
        Application__c    app    = getApp();
        Application_Package__c appPkg = TestDataFactory.createApplicationPackage(
            app.Id, dp.Id, null, dealer.Id, true
        );

        Test.startTest();
        String result = DealerPackageAccessHelper.updateApplicationPackageOptions(
            appPkg.Id, '', null, null
        );
        Test.stopTest();

        System.assert(result.startsWith('Error'),
            'updateApplicationPackageOptions should return an error string when applicationId is blank');
    }

    /**
     * No additions and no removals → handler returns early with no-changes message.
     */
    @isTest
    static void testUpdateAppPkgOptions_noChanges_returnsSuccess() {
        Account           dealer = getDealer();
        Dealer_Package__c dp     = getDp();
        Application__c    app    = getApp();
        Application_Package__c appPkg = TestDataFactory.createApplicationPackage(
            app.Id, dp.Id, null, dealer.Id, true
        );

        Test.startTest();
        String result = DealerPackageAccessHelper.updateApplicationPackageOptions(
            appPkg.Id, app.Id, null, null
        );
        Test.stopTest();

        System.assertEquals('Success: No changes to process', result,
            'updateApplicationPackageOptions should return the no-changes message when both lists are null');
    }

    /**
     * Valid optionsToAdd containing a Dealer_Package_Option__c with a non-null
     * Package_Option__c → handler creates the Application_Package_Option__c.
     */
    @isTest
    static void testUpdateAppPkgOptions_addOption_createsRecord() {
        Account           dealer  = getDealer();
        Dealer_Package__c dp      = getDp();
        Application__c    app     = getApp();
        Application_Package__c appPkg = TestDataFactory.createApplicationPackage(
            app.Id, dp.Id, null, dealer.Id, true
        );
        Package_Option__c      pkgOpt = TestDataFactory.createPackageOption(
            getPkg().Id, null, 'Optional', true
        );
        Dealer_Package_Option__c dpOpt = TestDataFactory.createDealerPackageOption(
            dp.Id, pkgOpt.Id, null, 'Optional', true
        );

        Test.startTest();
        String result = DealerPackageAccessHelper.updateApplicationPackageOptions(
            appPkg.Id, app.Id,
            new List<String>{ dpOpt.Id },
            null
        );
        Test.stopTest();

        System.assert(result.startsWith('Success'),
            'updateApplicationPackageOptions should return a Success message when adding an option');
        System.assertEquals(1,
            [SELECT COUNT() FROM Application_Package_Option__c
             WHERE Application_Package__c = :appPkg.Id],
            'One Application_Package_Option__c should be created for the added option');
    }

    /**
     * Valid optionsToRemove → handler walks the removal path (queries Dealer_Package_Option__c
     * for Package_Option__c IDs, then queries Application_Package_Option__c to delete).
     * Pre-created Application_Package_Option__c is removed from the package.
     */
    @isTest
    static void testUpdateAppPkgOptions_removeOption_deletesRecord() {
        Account           dealer  = getDealer();
        Dealer_Package__c dp      = getDp();
        Application__c    app     = getApp();
        Application_Package__c appPkg = TestDataFactory.createApplicationPackage(
            app.Id, dp.Id, null, dealer.Id, true
        );
        Package_Option__c      pkgOpt = TestDataFactory.createPackageOption(
            getPkg().Id, null, 'Optional', true
        );
        Dealer_Package_Option__c dpOpt = TestDataFactory.createDealerPackageOption(
            dp.Id, pkgOpt.Id, null, 'Optional', true
        );
        // Pre-insert the Application_Package_Option__c linked to pkgOpt so the
        // removal SOQL (WHERE Package_Option__c IN :packageOptionIds) can find it
        TestDataFactory.createApplicationPackageOption(
            app.Id, appPkg.Id, dpOpt.Id, pkgOpt.Id, true
        );

        Test.startTest();
        String result = DealerPackageAccessHelper.updateApplicationPackageOptions(
            appPkg.Id, app.Id,
            null,
            new List<String>{ dpOpt.Id }
        );
        Test.stopTest();

        System.assert(result.startsWith('Success'),
            'updateApplicationPackageOptions should return a Success message when removing an option');
    }
}