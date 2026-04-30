/**
 * DealerPackageOptionTriggerHandlerTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Covers DealerPackageOptionTriggerHandler.updateTermsForOptions():
 *
 *   • null / empty packageIds  → early return, no DML
 *   • No options exist         → Included_Options_Price__c set to 0, Additional unchanged
 *   • Included options         → Included_Options_Price__c = sum of Retail_Price__c per package
 *   • Multiple Included        → prices accumulated correctly
 *   • Optional with term       → Additional_Options_Price__c = sum on that term
 *   • Optional with null term  → skipped (branch guard: Dealer_Package_Term__c != null)
 *   • Optional on one of two terms → linked term gets sum; other term gets 0
 *   • Both Included + Optional → both fields updated independently
 *
 * Retail_Price__c formula chain:
 *   Original_Package_Option_Price__c (100) → Net_Cost__c (100, no discount)
 *   → Retail_Price__c (100, no markup) — all driven by factory defaults.
 *
 * Test Strategy:
 *   ✔ @isTest(SeeAllData=false)
 *   ✔ @TestSetup for shared Package / DealerPackage hierarchy
 *   ✔ All data exclusively via TestDataFactory — no inline SObject creation
 *   ✔ One test per logical branch
 *   ✔ System.assert* with descriptive messages on every assertion
 *   ✔ No hardcoded Ids
 */
@isTest(SeeAllData=false)
private class DealerPackageOptionTriggerHandlerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // @TestSetup — shared hierarchy
    // Package__c → Package_Term__c (x1)
    //           → Package_Option__c (Included master)
    //           → Package_Option__c (Optional master)
    // Dealer_Package__c → Dealer_Package_Term__c (x1)
    //
    // Tests that need a second Dealer_Package_Term__c create an extra
    // Package_Term__c + Dealer_Package_Term__c via factory in-test.
    // ─────────────────────────────────────────────────────────────────────────

    @TestSetup
    static void setup() {
        Account dealer           = TestDataFactory.createDealer(true);
        Package__c pkg           = TestDataFactory.createPackage('Extended_Limited_Warranty', true);
        Package_Term__c pkgTerm  = TestDataFactory.createPackageTerm(pkg.Id, null, true);

        // Two Package_Option__c masters — one per Selection_Type.
        // Dealer_Package_Option__c has Package_Option__c as a MasterDetail parent.
        TestDataFactory.createPackageOption(pkg.Id, pkgTerm.Id, 'Included', true);
        TestDataFactory.createPackageOption(pkg.Id, pkgTerm.Id, 'Optional', true);

        Dealer_Package__c dp     = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true
        );
        TestDataFactory.createDealerPackageTerm(dp.Id, pkgTerm.Id, null, true);
    }

    // ── Private query helpers ─────────────────────────────────────────────────

    private static Package__c getPkg() {
        return [SELECT Id FROM Package__c LIMIT 1];
    }

    private static Package_Term__c getPkgTerm() {
        return [SELECT Id FROM Package_Term__c ORDER BY CreatedDate ASC LIMIT 1];
    }

    private static Dealer_Package__c getDealerPackage() {
        return [SELECT Id FROM Dealer_Package__c LIMIT 1];
    }

    private static Dealer_Package_Term__c getDealerPackageTerm() {
        return [SELECT Id, Included_Options_Price__c, Additional_Options_Price__c
                FROM   Dealer_Package_Term__c LIMIT 1];
    }

    private static Package_Option__c getIncludedPkgOption() {
        return [SELECT Id FROM Package_Option__c WHERE Selection_Type__c = 'Included' LIMIT 1];
    }

    private static Package_Option__c getOptionalPkgOption() {
        return [SELECT Id FROM Package_Option__c WHERE Selection_Type__c = 'Optional' LIMIT 1];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // EARLY-RETURN GUARD TESTS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Null packageIds — early return, no DML, term fields unchanged.
     */
    @isTest
    static void testNullPackageIds_earlyReturn_noUpdates() {
        Test.startTest();
        DealerPackageOptionTriggerHandler.updateTermsForOptions(null);
        Test.stopTest();

        Dealer_Package_Term__c dpt = getDealerPackageTerm();
        System.assertEquals(null, dpt.Included_Options_Price__c,
            'Included_Options_Price__c should remain null — handler returned early for null input');
        System.assertEquals(null, dpt.Additional_Options_Price__c,
            'Additional_Options_Price__c should remain null — handler returned early for null input');
    }

    /**
     * Empty packageIds set — early return, no DML, term fields unchanged.
     */
    @isTest
    static void testEmptyPackageIds_earlyReturn_noUpdates() {
        Test.startTest();
        DealerPackageOptionTriggerHandler.updateTermsForOptions(new Set<Id>());
        Test.stopTest();

        Dealer_Package_Term__c dpt = getDealerPackageTerm();
        System.assertEquals(null, dpt.Included_Options_Price__c,
            'Included_Options_Price__c should remain null — handler returned early for empty set');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // NO OPTIONS CASE
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Package has no Dealer_Package_Option__c records at all.
     * Included_Options_Price__c → 0 (always written).
     * Additional_Options_Price__c → unchanged (termIds.size() == 0, so branch not entered).
     */
    @isTest
    static void testNoOptions_includedPriceSetToZero_additionalUnchanged() {
        Dealer_Package__c dp = getDealerPackage();

        Test.startTest();
        DealerPackageOptionTriggerHandler.updateTermsForOptions(new Set<Id>{ dp.Id });
        Test.stopTest();

        Dealer_Package_Term__c dpt = getDealerPackageTerm();
        System.assertEquals(0, dpt.Included_Options_Price__c,
            'Included_Options_Price__c should be 0 when no options exist');
        System.assertEquals(null, dpt.Additional_Options_Price__c,
            'Additional_Options_Price__c should remain null when no Optional options exist at all');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // INCLUDED OPTIONS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * One Included option (Retail_Price__c = 100 via formula chain).
     * Included_Options_Price__c on the term must equal 100.
     * Additional_Options_Price__c must remain null (no Optional options).
     */
    @isTest
    static void testIncludedOption_setsIncludedOptionsPriceOnAllTerms() {
        Dealer_Package__c    dp     = getDealerPackage();
        Dealer_Package_Term__c dpt  = getDealerPackageTerm();
        Package_Option__c    pkgOpt = getIncludedPkgOption();

        // Included option — Dealer_Package_Term__c is null (package-level)
        TestDataFactory.createDealerPackageOption(dp.Id, pkgOpt.Id, null, 'Included', true);

        Test.startTest();
        DealerPackageOptionTriggerHandler.updateTermsForOptions(new Set<Id>{ dp.Id });
        Test.stopTest();

        Dealer_Package_Term__c dptRefreshed = [
            SELECT Included_Options_Price__c, Additional_Options_Price__c
            FROM   Dealer_Package_Term__c
            WHERE  Id = :dpt.Id
        ];
        System.assertEquals(100.00, dptRefreshed.Included_Options_Price__c,
            'Included_Options_Price__c should be 100 (factory Retail_Price__c = 100)');
        System.assertEquals(null, dptRefreshed.Additional_Options_Price__c,
            'Additional_Options_Price__c should remain null when no Optional options exist');
    }

    /**
     * Two Included options — prices are accumulated (sum = 200).
     */
    @isTest
    static void testTwoIncludedOptions_pricesAccumulated() {
        Dealer_Package__c    dp     = getDealerPackage();
        Dealer_Package_Term__c dpt  = getDealerPackageTerm();
        Package_Option__c    pkgOpt = getIncludedPkgOption();

        TestDataFactory.createDealerPackageOption(dp.Id, pkgOpt.Id, null, 'Included', true);
        TestDataFactory.createDealerPackageOption(dp.Id, pkgOpt.Id, null, 'Included', true);

        Test.startTest();
        DealerPackageOptionTriggerHandler.updateTermsForOptions(new Set<Id>{ dp.Id });
        Test.stopTest();

        Dealer_Package_Term__c dptRefreshed = [
            SELECT Included_Options_Price__c
            FROM   Dealer_Package_Term__c
            WHERE  Id = :dpt.Id
        ];
        System.assertEquals(200.00, dptRefreshed.Included_Options_Price__c,
            'Two Included options at 100 each should sum to 200');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // OPTIONAL OPTIONS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * One Optional option linked to the term.
     * Additional_Options_Price__c on that term must equal 100.
     * Included_Options_Price__c must be 0 (no Included options).
     */
    @isTest
    static void testOptionalOption_withTerm_setsAdditionalOptionsPrice() {
        Dealer_Package__c    dp     = getDealerPackage();
        Dealer_Package_Term__c dpt  = getDealerPackageTerm();
        Package_Option__c    pkgOpt = getOptionalPkgOption();

        TestDataFactory.createDealerPackageOption(dp.Id, pkgOpt.Id, dpt.Id, 'Optional', true);

        Test.startTest();
        DealerPackageOptionTriggerHandler.updateTermsForOptions(new Set<Id>{ dp.Id });
        Test.stopTest();

        Dealer_Package_Term__c dptRefreshed = [
            SELECT Included_Options_Price__c, Additional_Options_Price__c
            FROM   Dealer_Package_Term__c
            WHERE  Id = :dpt.Id
        ];
        System.assertEquals(0, dptRefreshed.Included_Options_Price__c,
            'Included_Options_Price__c should be 0 when no Included options exist');
        System.assertEquals(100.00, dptRefreshed.Additional_Options_Price__c,
            'Additional_Options_Price__c should be 100 for the term that has an Optional option');
    }

    /**
     * Optional option with null Dealer_Package_Term__c — skipped by the handler guard.
     * Additional_Options_Price__c must remain null on all terms (termIds is empty).
     */
    @isTest
    static void testOptionalOption_nullTerm_isSkipped() {
        Dealer_Package__c    dp     = getDealerPackage();
        Dealer_Package_Term__c dpt  = getDealerPackageTerm();
        Package_Option__c    pkgOpt = getOptionalPkgOption();

        // Dealer_Package_Term__c = null → handler condition fails, option is skipped
        TestDataFactory.createDealerPackageOption(dp.Id, pkgOpt.Id, null, 'Optional', true);

        Test.startTest();
        DealerPackageOptionTriggerHandler.updateTermsForOptions(new Set<Id>{ dp.Id });
        Test.stopTest();

        Dealer_Package_Term__c dptRefreshed = [
            SELECT Additional_Options_Price__c
            FROM   Dealer_Package_Term__c
            WHERE  Id = :dpt.Id
        ];
        System.assertEquals(null, dptRefreshed.Additional_Options_Price__c,
            'Additional_Options_Price__c should remain null when Optional option has null term (skipped)');
    }

    /**
     * Package has two terms; Optional option is linked only to Term A.
     * Term A → Additional_Options_Price__c = 100.
     * Term B → Additional_Options_Price__c = 0 (termIds.size() > 0 but B not in optionalSumsByTerm).
     */
    @isTest
    static void testOptionalOption_termWithoutOption_getsZeroAdditional() {
        Dealer_Package__c    dp      = getDealerPackage();
        Dealer_Package_Term__c dptA  = getDealerPackageTerm();     // from @TestSetup
        Package_Option__c    pkgOpt  = getOptionalPkgOption();
        Package__c           pkg     = getPkg();

        // Second Package_Term__c and Dealer_Package_Term__c (Term B)
        Package_Term__c pkgTerm2     = TestDataFactory.createPackageTerm(pkg.Id, null, true);
        Dealer_Package_Term__c dptB  = TestDataFactory.createDealerPackageTerm(dp.Id, pkgTerm2.Id, null, true);

        // Optional option linked only to Term A
        TestDataFactory.createDealerPackageOption(dp.Id, pkgOpt.Id, dptA.Id, 'Optional', true);

        Test.startTest();
        DealerPackageOptionTriggerHandler.updateTermsForOptions(new Set<Id>{ dp.Id });
        Test.stopTest();

        Dealer_Package_Term__c dptARefreshed = [
            SELECT Additional_Options_Price__c
            FROM   Dealer_Package_Term__c WHERE Id = :dptA.Id
        ];
        Dealer_Package_Term__c dptBRefreshed = [
            SELECT Additional_Options_Price__c
            FROM   Dealer_Package_Term__c WHERE Id = :dptB.Id
        ];

        System.assertEquals(100.00, dptARefreshed.Additional_Options_Price__c,
            'Term A (linked to Optional option) should have Additional_Options_Price__c = 100');
        System.assertEquals(0, dptBRefreshed.Additional_Options_Price__c,
            'Term B (no Optional option, but other terms have one) should have Additional_Options_Price__c = 0');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // BOTH TYPES TOGETHER
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * One Included option (package-level) + one Optional option (term-level).
     * Included_Options_Price__c = 100, Additional_Options_Price__c = 100.
     */
    @isTest
    static void testBothTypes_bothFieldsUpdatedIndependently() {
        Dealer_Package__c    dp        = getDealerPackage();
        Dealer_Package_Term__c dpt     = getDealerPackageTerm();
        Package_Option__c    includedOpt = getIncludedPkgOption();
        Package_Option__c    optionalOpt = getOptionalPkgOption();

        TestDataFactory.createDealerPackageOption(dp.Id, includedOpt.Id, null,   'Included', true);
        TestDataFactory.createDealerPackageOption(dp.Id, optionalOpt.Id, dpt.Id, 'Optional', true);

        Test.startTest();
        DealerPackageOptionTriggerHandler.updateTermsForOptions(new Set<Id>{ dp.Id });
        Test.stopTest();

        Dealer_Package_Term__c dptRefreshed = [
            SELECT Included_Options_Price__c, Additional_Options_Price__c
            FROM   Dealer_Package_Term__c
            WHERE  Id = :dpt.Id
        ];
        System.assertEquals(100.00, dptRefreshed.Included_Options_Price__c,
            'Included_Options_Price__c should be 100 from the Included option');
        System.assertEquals(100.00, dptRefreshed.Additional_Options_Price__c,
            'Additional_Options_Price__c should be 100 from the Optional option on this term');
    }
}