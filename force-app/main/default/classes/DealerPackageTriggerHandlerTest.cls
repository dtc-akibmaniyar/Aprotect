/**
 * DealerPackageTriggerHandlerTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Covers DealerPackageTriggerHandler via the DealerPackageTrigger (after insert)
 * and via direct static-method calls where guards need isolation.
 *
 * Methods under test:
 *   • populateFieldsFromPackage() — null/empty early return; non-TotalLoss field
 *     mapping (Coverage_per_claim, Deductible, Max_Liability_Limit,
 *     Premium_Model_Fee) from Extended_Limited_Warranty Package.
 *   • createDealerPackageTiers()  — null input guard; Package with no tiers
 *     → returns empty map; creates Dealer_Package_Tier__c with correct links.
 *   • createDealerPackageTerms()  — invoked through trigger; creates term linked
 *     to tier via composite-key map; Original_Package_Term_Cost__c mapped.
 *   • createDealerPackageOptions() — empty-input guard; ELW Included option at
 *     package level (Dealer_Package_Term__c = null); ELW Optional option at
 *     term level (Dealer_Package_Term__c set).
 *
 * Note on RecordType coverage:
 *   Gap_Coverage and Car_Loan_Protection Package__c RecordTypes are not
 *   accessible to the running test-user profile in this org, so those handler
 *   branches are covered via the handler's own unit tests rather than end-to-end
 *   trigger tests here.
 *
 * Test Strategy:
 *   ✔ @isTest(SeeAllData=false)
 *   ✔ @TestSetup builds ELW Package hierarchy; each test inserts its own
 *     Dealer_Package__c so the trigger fires in an isolated transaction
 *   ✔ All data exclusively via TestDataFactory — no inline SObject creation
 *   ✔ update new SObject(Id=...) pattern used only to enrich Package fields
 *     that the factory does not set (writable Currency/Decimal fields)
 *   ✔ One test per logical branch
 *   ✔ System.assert* with descriptive messages on every assertion
 *   ✔ No hardcoded Ids
 */
@isTest(SeeAllData=false)
private class DealerPackageTriggerHandlerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // @TestSetup — Extended_Limited_Warranty Package hierarchy
    //
    //   Package__c (ELW)
    //     → Package_Tier__c
    //         → Package_Term__c           (Dealer_Package_Term__c chain)
    //     → Package_Option__c Included    (Package_Term__c = null → pkg-level)
    //     → Package_Option__c Optional    (Package_Term__c = elwTerm.Id → term-level)
    //
    // Each test inserts its own Dealer_Package__c → trigger fires in isolation.
    // ─────────────────────────────────────────────────────────────────────────

    @TestSetup
    static void setup() {
        Account dealer = TestDataFactory.createDealer(true);

        Package__c elwPkg = TestDataFactory.createPackage('Extended_Limited_Warranty', true);
        // Enrich writable Currency/Decimal fields read by populateFieldsFromPackage
        update new Package__c(
            Id                     = elwPkg.Id,
            Coverage_per_claim__c  = 500.00,
            Deductible__c          = 250.00,
            Max_Liability_Limit__c = 10000.00,
            Premium_Model_Fee__c   = 50.00
        );
        Package_Tier__c elwTier = TestDataFactory.createPackageTier(elwPkg.Id, true);
        Package_Term__c elwTerm = TestDataFactory.createPackageTerm(elwPkg.Id, elwTier.Id, true);
        // Included option — package level (no term)
        TestDataFactory.createPackageOption(elwPkg.Id, null,       'Included', true);
        // Optional option — term level
        TestDataFactory.createPackageOption(elwPkg.Id, elwTerm.Id, 'Optional', true);
    }

    // ── Private query helpers ─────────────────────────────────────────────────

    private static Account getDealer() {
        return [SELECT Id FROM Account LIMIT 1];
    }

    private static Package__c getElwPkg() {
        return [SELECT Id FROM Package__c
                WHERE RecordType.DeveloperName = 'Extended_Limited_Warranty' LIMIT 1];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // EARLY-RETURN GUARD TESTS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Null packageIds → handler returns immediately; no child records created.
     */
    @isTest
    static void testNullPackageIds_earlyReturn_noDml() {
        Test.startTest();
        DealerPackageTriggerHandler.populateFieldsFromPackage(
            new List<Dealer_Package__c>(), null
        );
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Dealer_Package_Tier__c],
            'No Dealer_Package_Tier__c should be created when packageIds is null');
        System.assertEquals(0, [SELECT COUNT() FROM Dealer_Package_Term__c],
            'No Dealer_Package_Term__c should be created when packageIds is null');
        System.assertEquals(0, [SELECT COUNT() FROM Dealer_Package_Option__c],
            'No Dealer_Package_Option__c should be created when packageIds is null');
    }

    /**
     * Empty packageIds set → same early-return path as null.
     */
    @isTest
    static void testEmptyPackageIds_earlyReturn_noDml() {
        Test.startTest();
        DealerPackageTriggerHandler.populateFieldsFromPackage(
            new List<Dealer_Package__c>(), new Set<Id>()
        );
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Dealer_Package_Tier__c],
            'No Dealer_Package_Tier__c should be created when packageIds is empty');
        System.assertEquals(0, [SELECT COUNT() FROM Dealer_Package_Term__c],
            'No Dealer_Package_Term__c should be created when packageIds is empty');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FIELD MAPPING — EXTENDED_LIMITED_WARRANTY (non-TotalLoss branch)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * ELW Package → Per_Claim_Limit__c (from Coverage_per_claim__c),
     * Deductable__c (from Deductible__c), Max_Liability_Limit__c,
     * Premium_Model_Fee__c populated on Dealer_Package__c after insert.
     */
    @isTest
    static void testExtendedWarranty_nonTotalLossFieldsMapped() {
        Account    dealer = getDealer();
        Package__c pkg    = getElwPkg();

        Test.startTest();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true
        );
        Test.stopTest();

        Dealer_Package__c dpRefreshed = [
            SELECT Per_Claim_Limit__c, Deductable__c, Max_Liability_Limit__c,
                   Premium_Model_Fee__c
            FROM   Dealer_Package__c
            WHERE  Id = :dp.Id
        ];
        System.assertEquals(500.00, dpRefreshed.Per_Claim_Limit__c,
            'Per_Claim_Limit__c should be 500 (mapped from Package.Coverage_per_claim__c)');
        System.assertEquals(250.00, dpRefreshed.Deductable__c,
            'Deductable__c should be 250 (mapped from Package.Deductible__c)');
        System.assertEquals(10000.00, dpRefreshed.Max_Liability_Limit__c,
            'Max_Liability_Limit__c should be 10000 (mapped from Package)');
        System.assertEquals(50.00, dpRefreshed.Premium_Model_Fee__c,
            'Premium_Model_Fee__c should be 50 (mapped from Package)');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // createDealerPackageTiers — STATIC METHOD GUARDS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Null map input → returns empty map without throwing.
     */
    @isTest
    static void testCreateDealerPackageTiers_nullInput_returnsEmptyMap() {
        Test.startTest();
        Map<String, Id> result = DealerPackageTriggerHandler.createDealerPackageTiers(null);
        Test.stopTest();

        System.assertNotEquals(null, result,
            'createDealerPackageTiers should return a non-null map for null input');
        System.assertEquals(0, result.size(),
            'createDealerPackageTiers should return an empty map for null input');
    }

    /**
     * Package with no Package_Tier__c records → returns empty map;
     * no Dealer_Package_Tier__c created.
     */
    @isTest
    static void testCreateDealerPackageTiers_noTiers_returnsEmptyMap() {
        Account    dealer    = getDealer();
        Package__c freshPkg  = TestDataFactory.createPackage('Extended_Limited_Warranty', true);
        // No Package_Tier__c created for freshPkg — trigger fires on insert but finds none
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, freshPkg.Id, 'Extended_Limited_Warranty', true
        );

        Map<Id, Id> dpToPackageMap = new Map<Id, Id>{ dp.Id => freshPkg.Id };

        Test.startTest();
        Map<String, Id> result =
            DealerPackageTriggerHandler.createDealerPackageTiers(dpToPackageMap);
        Test.stopTest();

        System.assertEquals(0, result.size(),
            'Empty map expected when Package has no Package_Tier__c records');
        System.assertEquals(0,
            [SELECT COUNT() FROM Dealer_Package_Tier__c WHERE Dealer_Package__c = :dp.Id],
            'No Dealer_Package_Tier__c should exist when Package has no tiers');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TIER CREATION — via trigger insert
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * ELW insert → one Dealer_Package_Tier__c created and linked back to the
     * source Package_Tier__c.
     */
    @isTest
    static void testInsert_extendedWarranty_createsDealerPackageTier() {
        Account    dealer = getDealer();
        Package__c pkg    = getElwPkg();

        Test.startTest();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true
        );
        Test.stopTest();

        List<Dealer_Package_Tier__c> tiers = [
            SELECT Id, Dealer_Package__c, Package_Tier__c
            FROM   Dealer_Package_Tier__c
            WHERE  Dealer_Package__c = :dp.Id
        ];
        System.assertEquals(1, tiers.size(),
            'One Dealer_Package_Tier__c should be created for the ELW Package_Tier__c');
        System.assertNotEquals(null, tiers[0].Package_Tier__c,
            'Dealer_Package_Tier__c.Package_Tier__c should reference the source Package_Tier__c');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TERM CREATION — via trigger insert
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * ELW insert → Dealer_Package_Term__c created, linked to both
     * Dealer_Package__c and Dealer_Package_Tier__c (via composite key).
     * Original_Package_Term_Cost__c mapped from Package_Term__c.Price__c
     * (factory default = 1500).
     */
    @isTest
    static void testInsert_extendedWarranty_createsDealerPackageTerm_linkedToTier() {
        Account    dealer = getDealer();
        Package__c pkg    = getElwPkg();

        Test.startTest();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true
        );
        Test.stopTest();

        List<Dealer_Package_Term__c> terms = [
            SELECT Id, Dealer_Package__c, Package_Term__c,
                   Dealer_Package_Tier__c, Original_Package_Term_Cost__c
            FROM   Dealer_Package_Term__c
            WHERE  Dealer_Package__c = :dp.Id
        ];
        System.assertEquals(1, terms.size(),
            'One Dealer_Package_Term__c should be created for the ELW Package_Term__c');
        System.assertNotEquals(null, terms[0].Dealer_Package_Tier__c,
            'Dealer_Package_Term__c should be linked to Dealer_Package_Tier__c (composite key mapping)');
        System.assertEquals(1500.00, terms[0].Original_Package_Term_Cost__c,
            'Original_Package_Term_Cost__c should equal Package_Term__c.Price__c (factory default 1500)');
    }

    /**
     * Package with no tiers → no Dealer_Package_Tier__c, Dealer_Package_Term__c,
     * or Dealer_Package_Option__c (option creation gates on term insertion).
     */
    @isTest
    static void testInsert_packageWithNoTiers_noChildRecordsCreated() {
        Account    dealer   = getDealer();
        Package__c freshPkg = TestDataFactory.createPackage('Extended_Limited_Warranty', true);
        // No Package_Tier__c for freshPkg — handler chain stops at the tier step

        Test.startTest();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, freshPkg.Id, 'Extended_Limited_Warranty', true
        );
        Test.stopTest();

        System.assertEquals(0,
            [SELECT COUNT() FROM Dealer_Package_Tier__c WHERE Dealer_Package__c = :dp.Id],
            'No Dealer_Package_Tier__c when Package has no tiers');
        System.assertEquals(0,
            [SELECT COUNT() FROM Dealer_Package_Term__c WHERE Dealer_Package__c = :dp.Id],
            'No Dealer_Package_Term__c when Package has no tiers');
        System.assertEquals(0,
            [SELECT COUNT() FROM Dealer_Package_Option__c WHERE Dealer_Package__c = :dp.Id],
            'No Dealer_Package_Option__c when no terms are created (options gate on terms)');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // OPTION CREATION — EXTENDED_LIMITED_WARRANTY
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * ELW Included option (Package_Term__c = null in source) →
     * Dealer_Package_Option__c at package level (Dealer_Package_Term__c = null).
     */
    @isTest
    static void testInsert_extendedWarranty_includedOptionAtPackageLevel() {
        Account    dealer = getDealer();
        Package__c pkg    = getElwPkg();

        Test.startTest();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true
        );
        Test.stopTest();

        List<Dealer_Package_Option__c> includedOpts = [
            SELECT Id, Selection_Type__c, Dealer_Package_Term__c
            FROM   Dealer_Package_Option__c
            WHERE  Dealer_Package__c = :dp.Id
            AND    Selection_Type__c = 'Included'
        ];
        System.assertEquals(1, includedOpts.size(),
            'One Included Dealer_Package_Option__c should be created');
        System.assertEquals(null, includedOpts[0].Dealer_Package_Term__c,
            'Included option must have Dealer_Package_Term__c = null (package-level)');
    }

    /**
     * ELW Optional option (Package_Term__c set in source) →
     * Dealer_Package_Option__c linked to the corresponding Dealer_Package_Term__c.
     */
    @isTest
    static void testInsert_extendedWarranty_optionalOptionAtTermLevel() {
        Account    dealer = getDealer();
        Package__c pkg    = getElwPkg();

        Test.startTest();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true
        );
        Test.stopTest();

        List<Dealer_Package_Option__c> optionalOpts = [
            SELECT Id, Selection_Type__c, Dealer_Package_Term__c
            FROM   Dealer_Package_Option__c
            WHERE  Dealer_Package__c = :dp.Id
            AND    Selection_Type__c = 'Optional'
        ];
        System.assertEquals(1, optionalOpts.size(),
            'One Optional Dealer_Package_Option__c should be created for ELW');
        System.assertNotEquals(null, optionalOpts[0].Dealer_Package_Term__c,
            'ELW Optional option must be linked to a Dealer_Package_Term__c (term-level)');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // createDealerPackageOptions — EMPTY INPUT GUARD
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Empty dealerPackageTermToPackageTermMap → method returns early without DML.
     */
    @isTest
    static void testCreateDealerPackageOptions_emptyInput_returnsEarly() {
        Test.startTest();
        DealerPackageTriggerHandler.createDealerPackageOptions(
            new Map<Id, Id>(),
            new Map<Id, Id>(),
            new Map<Id, Package__c>()
        );
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Dealer_Package_Option__c],
            'No Dealer_Package_Option__c should be created for empty input maps');
    }
}