/**
 * DealerPackageSyncServiceTest
 *
 * P2 exit-criteria tests (change-implementation plan §11 P2 / §13.2):
 *   • Sync idempotency: master price change → every dealer copy's derived
 *     Net/Retail updates in one run; markup/discount untouched; re-runs
 *     duplicate nothing.
 *   • Delete-and-recreate a dealer child → reconcile restores it once (no dupes).
 *   • Double-invoke → no duplicate rows.
 *   • Bulk assign (§09.1): dry-run counts vs run counts; re-run safe.
 *
 * Master fixture: Extended_Limited_Warranty Package with one tier, one term
 * (wholesale 1500), one package-level Included option (100) and one term-level
 * Optional option (100) — the copy shapes the pre-P2 fan-out produced.
 */
@isTest(SeeAllData=false)
private class DealerPackageSyncServiceTest {

    @TestSetup
    static void setup() {
        // NOTE: no Account is created here — per-method dealers use distinct
        // identity fields to stay clear of the org's Account duplicate rule.
        Package__c pkg = TestDataFactory.createPackage('Extended_Limited_Warranty', true);
        update new Package__c(
            Id = pkg.Id,
            Coverage_per_claim__c = 500.00,
            Deductible__c = 250.00
        );

        Package_Tier__c tier = TestDataFactory.createPackageTier(pkg.Id, true);
        Package_Term__c term = TestDataFactory.createPackageTerm(pkg.Id, tier.Id, true);

        // Package-level Included option
        TestDataFactory.createPackageOption(pkg.Id, null, 'Included', true);
        // Term-level Optional option
        TestDataFactory.createPackageOption(pkg.Id, term.Id, 'Optional', true);
    }

    /** Dealer with distinct identity fields (org Account duplicate rule is active). */
    private static Account createDistinctDealer(Integer n) {
        Account a = new Account(
            Name = 'P2 Dealer ' + n + ' ' + Datetime.now().getTime(),
            RecordTypeId = TestDataFactory.getRecordTypeId('Account', 'Dealer_Account'),
            Phone = '4165550' + String.valueOf(100 + n),
            BillingStreet = 'Sync Street ' + n,
            BillingCity = 'Toronto', BillingState = 'ON', BillingCountry = 'Canada',
            BillingPostalCode = 'M5V 0A' + String.valueOf(n)
        );
        insert a;
        return a;
    }

    /** Dealer with a distinctive business name (org standard Account dup rule is fuzzy on Name). */
    private static Account createDealerNamed(String name) {
        Account a = new Account(
            Name = name + ' ' + Datetime.now().getTime(),
            RecordTypeId = TestDataFactory.getRecordTypeId('Account', 'Dealer_Account'),
            Phone = '4165550' + String.valueOf(200 + Math.abs(name.length() * 7)),
            BillingStreet = name + ' Street',
            BillingCity = 'Toronto', BillingState = 'ON', BillingCountry = 'Canada',
            BillingPostalCode = 'M5V 0A7'
        );
        insert a;
        return a;
    }

    private static Package__c getMasterPackage() {
        return [
            SELECT Id, Name, RecordType.DeveloperName,
                   (SELECT Id FROM Package_Term_Tiers__r),
                   (SELECT Id FROM Package_Term_Options__r)
            FROM Package__c LIMIT 1
        ];
    }

    // ---------------------------------------------------------------------
    // Insert fan-out builds the mirror exactly once (idempotent)
    // ---------------------------------------------------------------------

    @isTest
    static void test_insertBuildsMirrorAndReRunDuplicatesNothing() {
        Account dealer = createDistinctDealer(1);
        Package__c pkg = getMasterPackage();

        Test.startTest();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true);
        Test.stopTest();

        List<Dealer_Package_Tier__c> tiers = [
            SELECT Id, Dealer_Package__c, Package_Tier__c FROM Dealer_Package_Tier__c
            WHERE Dealer_Package__c = :dp.Id
        ];
        System.assertEquals(1, tiers.size(), 'One dealer tier mirror expected after insert');
        System.assertEquals(1, [SELECT COUNT() FROM Dealer_Package_Term__c WHERE Dealer_Package__c = :dp.Id],
            'One dealer term mirror expected after insert');
        System.assertEquals(2, [SELECT COUNT() FROM Dealer_Package_Option__c WHERE Dealer_Package__c = :dp.Id],
            'Included (package-level) + Optional (term-level) mirrors expected');

        // Re-run the reconcile — nothing may duplicate.
        DealerPackageSyncService.reconcileDealerPackages(new Set<Id>{ dp.Id });
        System.assertEquals(1, tiers.size(), 'Tier count unchanged after re-run');
        System.assertEquals(1, [SELECT COUNT() FROM Dealer_Package_Term__c WHERE Dealer_Package__c = :dp.Id],
            'Term count unchanged after re-run');
        System.assertEquals(2, [SELECT COUNT() FROM Dealer_Package_Option__c WHERE Dealer_Package__c = :dp.Id],
            'Option count unchanged after re-run');
    }

    // ---------------------------------------------------------------------
    // Master price change → all dealer copies update in ONE run; markup kept
    // ---------------------------------------------------------------------

    @isTest
    static void test_masterPriceChangeFrozenOnceDealerHasLocalPricing() {
        Account dealer = createDistinctDealer(1);
        Package__c pkg = getMasterPackage();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true);

        // Give the dealer term a local markup ($200) and a discount profile —
        // the sync must preserve both.
        Dealer_Package_Term__c dealerTerm = [
            SELECT Id, Markup__c, Markup_Type__c, Discount_Type__c, Discount_Value__c,
                   Sales_Rep_Incentive__c
            FROM Dealer_Package_Term__c WHERE Dealer_Package__c = :dp.Id LIMIT 1
        ];
        update new Dealer_Package_Term__c(
            Id = dealerTerm.Id,
            Markup__c = 200,
            Markup_Type__c = '$',
            Discount_Type__c = '$',
            Discount_Value__c = 50,
            Sales_Rep_Incentive__c = 25
        );

        // Master wholesale 1500 → 1900
        Package_Term__c masterTerm = [
            SELECT Id FROM Package_Term__c WHERE Package_Tier__c IN
                (SELECT Id FROM Package_Tier__c WHERE Package__c = :pkg.Id) LIMIT 1
        ];
        update new Package_Term__c(Id = masterTerm.Id, Price__c = 1900);

        Test.startTest();
        // One run propagates the master change to every dealer copy.
        DealerPackageSyncService.reconcileForMasterTerm(new Set<Id>{ masterTerm.Id });
        Test.stopTest();

        Dealer_Package_Term__c after = [
            SELECT Id, Net_Cost__c, Retail_Price__c, Original_Package_Term_Cost__c,
                   Markup__c, Markup_Type__c, Discount_Type__c, Discount_Value__c,
                   Sales_Rep_Incentive__c
            FROM Dealer_Package_Term__c WHERE Dealer_Package__c = :dp.Id LIMIT 1
        ];
        // PRICE-ANCHOR FREEZE: the dealer already has local pricing, so the
        // stored wholesale anchor is frozen — the master edit must NOT move the
        // dealer's effective price. Org fact: Net_Cost/Retail are FORMULAS
        // anchored on the stored Original_Package_Term_Cost snapshot + dealer
        // discount/markup:
        //   Net = Original(1500) − discount($50) = 1450; Retail = Net + markup($200) = 1650.
        System.assertEquals(1500, after.Original_Package_Term_Cost__c,
            'Frozen anchor: a master price edit must not move the dealer effective price');
        System.assertEquals(1450, after.Net_Cost__c,
            'Net_Cost (formula) = frozen anchor − preserved $50 discount');
        System.assertEquals(1650, after.Retail_Price__c,
            'Retail (formula) = Net + preserved $200 markup');
        System.assertEquals(200, after.Markup__c, 'Markup untouched by sync');
        System.assertEquals('$', after.Markup_Type__c, 'Markup type untouched');
        System.assertEquals(50, after.Discount_Value__c, 'Discount untouched');
        System.assertEquals(25, after.Sales_Rep_Incentive__c, 'Incentive untouched');

        // Re-run: no duplicates, values stable.
        DealerPackageSyncService.reconcileForMasterTerm(new Set<Id>{ masterTerm.Id });
        System.assertEquals(1, [SELECT COUNT() FROM Dealer_Package_Term__c WHERE Dealer_Package__c = :dp.Id]);
        System.assertEquals(1, [SELECT COUNT() FROM Dealer_Package_Tier__c WHERE Dealer_Package__c = :dp.Id]);
    }

    // ---------------------------------------------------------------------
    // Delete-and-recreate a dealer child → reconcile restores exactly one
    // ---------------------------------------------------------------------

    @isTest
    static void test_deletedDealerOptionIsRecreatedOnce() {
        Account dealer = createDistinctDealer(1);
        Package__c pkg = getMasterPackage();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true);

        System.assertEquals(2, [SELECT COUNT() FROM Dealer_Package_Option__c WHERE Dealer_Package__c = :dp.Id]);

        // Delete one dealer option mirror.
        Dealer_Package_Option__c victim = [
            SELECT Id FROM Dealer_Package_Option__c
            WHERE Dealer_Package__c = :dp.Id LIMIT 1
        ];
        delete victim;

        Test.startTest();
        DealerPackageSyncService.reconcileDealerPackages(new Set<Id>{ dp.Id });
        Test.stopTest();

        System.assertEquals(2, [SELECT COUNT() FROM Dealer_Package_Option__c WHERE Dealer_Package__c = :dp.Id],
            'Reconcile restores the missing mirror exactly once');
    }

    // ---------------------------------------------------------------------
    // Master option price change → dealer option derived prices + term
    // included/additional sums refresh in one run
    // ---------------------------------------------------------------------

    @isTest
    static void test_masterOptionPriceChangePropagatesToTermSums() {
        Account dealer = createDistinctDealer(1);
        Package__c pkg = getMasterPackage();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true);

        Package_Option__c masterIncluded = [
            SELECT Id FROM Package_Option__c
            WHERE Package__c = :pkg.Id AND Selection_Type__c = 'Included' LIMIT 1
        ];
        update new Package_Option__c(Id = masterIncluded.Id, Price__c = 130);

        Test.startTest();
        DealerPackageSyncService.reconcileForMasterOption(new Set<Id>{ masterIncluded.Id });
        Test.stopTest();

        Dealer_Package_Option__c dealerOpt = [
            SELECT Net_Cost__c, Retail_Price__c, Original_Package_Option_Price__c
            FROM Dealer_Package_Option__c
            WHERE Dealer_Package__c = :dp.Id AND Package_Option__c = :masterIncluded.Id LIMIT 1
        ];
        System.assertEquals(130, dealerOpt.Net_Cost__c, 'Option Net_Cost tracks master price');
        System.assertEquals(130, dealerOpt.Retail_Price__c, 'Option Retail tracks master price');
        System.assertEquals(130, dealerOpt.Original_Package_Option_Price__c,
            'Original option price snapshot refreshed');

        // Term included-options sum re-derived from the option Retail (option trigger).
        Dealer_Package_Term__c dealerTerm = [
            SELECT Included_Options_Price__c FROM Dealer_Package_Term__c
            WHERE Dealer_Package__c = :dp.Id LIMIT 1
        ];
        System.assertEquals(130, dealerTerm.Included_Options_Price__c,
            'Term Included_Options_Price re-summed from refreshed option retail');
    }

    // ---------------------------------------------------------------------
    // Bulk assign (§09.1): dry-run vs run, idempotent re-run
    // ---------------------------------------------------------------------

    @isTest
    static void test_bulkAssignDryRunThenRunThenReRun() {
        Package__c pkg = getMasterPackage();

        Account d1 = createDealerNamed('Boreal Truck Centre');
        Account d2 = createDealerNamed('Cobalt Leasing Group');

        // Dry run — no DML. Two distinct Dealer Accounts created in this method.
        DealerPackageSyncService.BulkAssignResult preview =
            DealerPackageSyncService.assignPlanToAllDealers(pkg.Id, 'ALL', true);
        System.assertEquals(true, preview.success);
        System.assertEquals(0, [SELECT COUNT() FROM Dealer_Package__c WHERE Package__c = :pkg.Id],
            'Dry run must not create rows');
        System.assertEquals(2, preview.totalDealersConsidered,
            'Two eligible Dealer Accounts expected');

        // Real run.
        Test.startTest();
        DealerPackageSyncService.BulkAssignResult run =
            DealerPackageSyncService.assignPlanToAllDealers(pkg.Id, 'ALL', false);
        Test.stopTest();

        System.assertEquals(true, run.success);
        System.assertEquals(2, run.newlyAssigned, 'Mirror created for every dealer');
        System.assertEquals(2, [SELECT COUNT() FROM Dealer_Package__c WHERE Package__c = :pkg.Id]);
        System.assertEquals(2, [SELECT COUNT() FROM Dealer_Package_Term__c
            WHERE Dealer_Package__c IN (SELECT Id FROM Dealer_Package__c WHERE Package__c = :pkg.Id)],
            'Term mirrors exist for every dealer');
        System.assertEquals(4, [SELECT COUNT() FROM Dealer_Package_Option__c
            WHERE Dealer_Package__c IN (SELECT Id FROM Dealer_Package__c WHERE Package__c = :pkg.Id)],
            'Option mirrors exist for every dealer');

        // Re-run — nothing new.
        DealerPackageSyncService.BulkAssignResult rerun =
            DealerPackageSyncService.assignPlanToAllDealers(pkg.Id, 'ALL', false);
        System.assertEquals(true, rerun.success);
        System.assertEquals(0, rerun.newlyAssigned, 'Re-run assigns nothing new');
        System.assertEquals(2, [SELECT COUNT() FROM Dealer_Package__c WHERE Package__c = :pkg.Id]);
    }

    // ---------------------------------------------------------------------
    // A newly assigned / created dealer package starts ACTIVE (never Inactive),
    // and a deliberate deactivation is a soft state the reconcile never undoes.
    // ---------------------------------------------------------------------

    @isTest
    static void test_newlyAssignedDealerPackageStartsActive() {
        Package__c pkg = getMasterPackage();
        Account dealer = createDealerNamed('Active Default Motors');

        Test.startTest();
        DealerPackageSyncService.BulkAssignResult run =
            DealerPackageSyncService.assignPlanToAllDealers(pkg.Id, 'ALL', false);
        Test.stopTest();

        System.assertEquals(true, run.success, run.message);
        System.assertEquals(1, run.newlyAssigned, 'One dealer assigned');

        Dealer_Package__c dp = [
            SELECT Id, Active__c FROM Dealer_Package__c WHERE Dealer__c = :dealer.Id LIMIT 1
        ];
        System.assertEquals(true, dp.Active__c,
            'A freshly assigned dealer package must start Active');

        // The console toggle still works: deactivate, then re-activate.
        Database.SaveResult deact = Database.update(
            new Dealer_Package__c(Id = dp.Id, Active__c = false), false);
        System.assert(deact.isSuccess());
        System.assertEquals(false,
            [SELECT Active__c FROM Dealer_Package__c WHERE Id = :dp.Id].Active__c,
            'The toggle can deactivate a package');

        Database.update(new Dealer_Package__c(Id = dp.Id, Active__c = true), false);
        System.assertEquals(true,
            [SELECT Active__c FROM Dealer_Package__c WHERE Id = :dp.Id].Active__c,
            'The toggle can re-activate a package');

        // A reconcile must NOT resurrect a deactivated package (soft state).
        Database.update(new Dealer_Package__c(Id = dp.Id, Active__c = false), false);
        DealerPackageSyncService.reconcileDealerPackages(new Set<Id>{ dp.Id });
        System.assertEquals(false,
            [SELECT Active__c FROM Dealer_Package__c WHERE Id = :dp.Id].Active__c,
            'Reconcile must preserve a deliberate deactivation');
    }

    // ---------------------------------------------------------------------
    // P7-e-fix — dealer picklist accepts every master Restriction_Type value
    // (regression: a master term carrying "Unlimited" must mirror cleanly)
    // ---------------------------------------------------------------------

    @isTest
    static void test_masterTermWithUnlimitedRestrictionMirrorsSuccessfully() {
        Account dealer = createDistinctDealer(1);
        Package__c pkg = getMasterPackage();
        Package_Term__c masterTerm = [
            SELECT Id FROM Package_Term__c WHERE Package__c = :pkg.Id LIMIT 1
        ];
        update new Package_Term__c(Id = masterTerm.Id, Restriction_Type__c = 'Unlimited');

        Test.startTest();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true);
        Test.stopTest();

        Dealer_Package_Term__c mirror = [
            SELECT Id, Restriction_Type__c FROM Dealer_Package_Term__c
            WHERE Dealer_Package__c = :dp.Id LIMIT 1
        ];
        System.assertEquals('Unlimited', mirror.Restriction_Type__c,
            'Dealer mirror must accept the master Unlimited restriction value');
        System.assertEquals(0, DealerPackageSyncService.getSkippedMirrorReasons().size(),
            'No mirror row may be skipped for a supported value');
    }

    // ---------------------------------------------------------------------
    // P7-f C1 (tier-opt-in) — a master term with NO tier is its own sellable
    // catalogue row and must be mirrored with a null dealer tier
    // ---------------------------------------------------------------------

    @isTest
    static void test_tierlessMasterTermMirrorsWithNullTier() {
        Account dealer = createDistinctDealer(4);
        Package__c pkg = getMasterPackage();
        Package_Term__c tierless = TestDataFactory.createPackageTerm(pkg.Id, null, true);

        Test.startTest();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true);
        Test.stopTest();

        List<Dealer_Package_Term__c> mirrors = [
            SELECT Id, Dealer_Package_Tier__c, Package_Tier__c, Package_Term__c, Odometer_KM__c
            FROM Dealer_Package_Term__c
            WHERE Dealer_Package__c = :dp.Id AND Package_Term__c = :tierless.Id
        ];
        System.assertEquals(1, mirrors.size(), 'Tier-less master term must be mirrored exactly once');
        System.assertEquals(null, mirrors[0].Dealer_Package_Tier__c,
            'A tier-less master term mirrors with a null dealer tier');
        System.assertEquals(null, mirrors[0].Package_Tier__c,
            'A tier-less master term mirrors with a null master-tier link');
    }

    @isTest
    static void test_tierlessTermReRunDuplicatesNothing() {
        Account dealer = createDistinctDealer(5);
        Package__c pkg = getMasterPackage();
        Package_Term__c tierless = TestDataFactory.createPackageTerm(pkg.Id, null, true);

        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true);
        System.assertEquals(1, [
            SELECT COUNT() FROM Dealer_Package_Term__c
            WHERE Dealer_Package__c = :dp.Id AND Package_Term__c = :tierless.Id
        ], 'One mirror after the fan-out');

        // Re-run the reconcile — the tier-less pass must be idempotent too.
        DealerPackageSyncService.reconcileDealerPackages(new Set<Id>{ dp.Id });
        System.assertEquals(1, [
            SELECT COUNT() FROM Dealer_Package_Term__c
            WHERE Dealer_Package__c = :dp.Id AND Package_Term__c = :tierless.Id
        ], 'Re-run must not duplicate a tier-less mirror');
    }

    @isTest
    static void test_tierlessTermLevelOptionMirrors() {
        Account dealer = createDistinctDealer(6);
        Package__c pkg = getMasterPackage();
        Package_Term__c tierless = TestDataFactory.createPackageTerm(pkg.Id, null, true);
        // Term-level Optional option riding on the tier-less term.
        TestDataFactory.createPackageOption(pkg.Id, tierless.Id, 'Optional', true);

        Test.startTest();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true);
        Test.stopTest();

        Dealer_Package_Term__c dterm = [
            SELECT Id FROM Dealer_Package_Term__c
            WHERE Dealer_Package__c = :dp.Id AND Package_Term__c = :tierless.Id
        ];
        List<Dealer_Package_Option__c> dOpts = [
            SELECT Id, Dealer_Package_Term__c FROM Dealer_Package_Option__c
            WHERE Dealer_Package__c = :dp.Id AND Dealer_Package_Term__c = :dterm.Id
        ];
        System.assertEquals(1, dOpts.size(),
            'The tier-less term-level Optional option mirrors and links via dealerTermIdByKey');
    }

    // ---------------------------------------------------------------------
    // P7-e-fix — defensive writer: one rejected value never fails the run
    // (the good rows commit; the rejected one is skipped and recorded)
    // ---------------------------------------------------------------------

    @isTest
    static void test_defensiveSkipWhenDealerPicklistRejectsValue() {
        Account dealer = createDistinctDealer(1);
        Package__c pkg = getMasterPackage();
        Package_Tier__c tier = [
            SELECT Id FROM Package_Tier__c WHERE Package__c = :pkg.Id LIMIT 1
        ];
        // The setup term (force-rejected) + a second term that must survive.
        Package_Term__c rejected = [
            SELECT Id FROM Package_Term__c WHERE Package_Tier__c = :tier.Id LIMIT 1
        ];
        TestDataFactory.createPackageTerm(pkg.Id, tier.Id, true);

        DealerPackageSyncService.forcedRejectMasterTermIds = new Set<Id>{ rejected.Id };
        try {
            Test.startTest();
            Dealer_Package__c dp = TestDataFactory.createDealerPackage(
                dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true);
            Test.stopTest();

            System.assertNotEquals(null, dp.Id,
                'The header must still be created despite the rejected detail');
            System.assertEquals(1, [
                SELECT COUNT() FROM Dealer_Package_Term__c WHERE Dealer_Package__c = :dp.Id
            ], 'The good term mirror is created; the rejected row is skipped (not fatal)');
            System.assertEquals(1, DealerPackageSyncService.getSkippedMirrorReasons().size(),
                'The rejected package must be recorded so the console can flag it');
            System.assertEquals(true,
                DealerPackageSyncService.getSkippedMirrorReasons().containsKey(pkg.Id),
                'Skip reason keyed by the master package');
        } finally {
            DealerPackageSyncService.forcedRejectMasterTermIds = null;
        }
    }

    // ---------------------------------------------------------------------
    // p8 (option b) — a term-anchored Additional option written the way the
    // admin service writes it (Package_Term__c set, Package__c NULL) must now
    // mirror to the dealer term. This is the production shape: the old
    // package-keyed query never saw it, so term-level Additional options never
    // reached dealers.
    // ---------------------------------------------------------------------

    @isTest
    static void test_termAnchoredOptionWithoutPackageMirrorsToDealerTerm() {
        Account dealer = createDistinctDealer(7);
        Package__c pkg = getMasterPackage();
        // Tier-less term (direct Package__c link) — its own sellable row here.
        Package_Term__c term = TestDataFactory.createPackageTerm(pkg.Id, null, true);
        // Term-anchored Optional option: Package_Term__c set, Package__c NULL.
        Package_Option__c anchored = TestDataFactory.createPackageOption(null, term.Id, 'Optional', false);
        insert anchored;
        System.assertEquals(null, anchored.Package__c, 'Fixture sanity: Package__c must be null');

        Test.startTest();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true);
        Test.stopTest();

        Dealer_Package_Term__c dterm = [
            SELECT Id FROM Dealer_Package_Term__c
            WHERE Dealer_Package__c = :dp.Id AND Package_Term__c = :term.Id
        ];
        List<Dealer_Package_Option__c> mirror = [
            SELECT Id, Dealer_Package__c, Dealer_Package_Term__c, Package_Option__c
            FROM Dealer_Package_Option__c
            WHERE Dealer_Package__c = :dp.Id AND Package_Option__c = :anchored.Id
        ];
        System.assertEquals(1, mirror.size(),
            'A term-anchored Optional master option (Package__c null) must mirror to the dealer');
        System.assertEquals(dterm.Id, mirror[0].Dealer_Package_Term__c,
            'The mirrored option must attach to the dealer term mirror');
        System.assertEquals(0, DealerPackageSyncService.getSkippedMirrorReasons().size(),
            'No mirror row may be skipped for the term-anchored option');

        // Re-run: idempotent, no duplicate row.
        DealerPackageSyncService.reconcileDealerPackages(new Set<Id>{ dp.Id });
        System.assertEquals(1, [
            SELECT COUNT() FROM Dealer_Package_Option__c
            WHERE Dealer_Package__c = :dp.Id AND Package_Option__c = :anchored.Id
        ], 'Re-run must not duplicate the term-anchored mirror');
    }

    // ---------------------------------------------------------------------
    // Premium fee is WRITE-ONCE on the dealer term. A dealer's edited premium
    // survives every later reconcile; a head-office change reaches the dealers
    // only through the explicit on-demand re-push (and that is gated by the
    // Dealer_Sync_Enabled__c kill switch).
    // ---------------------------------------------------------------------

    /** The single dealer term mirroring the fixture package's one master term. */
    private static Dealer_Package_Term__c soleDealerTerm(Id dealerPackageId) {
        return [
            SELECT Id, Dealer_Package__c, Package_Term__c, Premium_Model_Fee__c
            FROM Dealer_Package_Term__c WHERE Dealer_Package__c = :dealerPackageId LIMIT 1
        ];
    }

    /** The single master term of the fixture package. */
    private static Package_Term__c soleMasterTerm(Id packageId) {
        return [
            SELECT Id, Premium_Model_Fee__c FROM Package_Term__c
            WHERE Package__c = :packageId LIMIT 1
        ];
    }

    @isTest
    static void test_dealerTermPremiumSurvivesReconcile_writeOnce() {
        Account dealer = createDistinctDealer(2);
        Package__c pkg = getMasterPackage();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true);

        Dealer_Package_Term__c dealerTerm = soleDealerTerm(dp.Id);
        // Dealer edits the premium locally (the row seeded at creation).
        update new Dealer_Package_Term__c(Id = dealerTerm.Id, Premium_Model_Fee__c = 425.00);

        // Head office later changes the master premium AND its wholesale price.
        Package_Term__c masterTerm = soleMasterTerm(pkg.Id);
        update new Package_Term__c(Id = masterTerm.Id, Premium_Model_Fee__c = 610.00, Price__c = 1900);

        Test.startTest();
        DealerPackageSyncService.reconcileForMasterTerm(new Set<Id>{ masterTerm.Id });
        Test.stopTest();

        Dealer_Package_Term__c after = [
            SELECT Id, Premium_Model_Fee__c, Original_Package_Term_Cost__c
            FROM Dealer_Package_Term__c WHERE Id = :dealerTerm.Id
        ];
        System.assertEquals(425.00, after.Premium_Model_Fee__c,
            'write-once: the dealer term premium is never overwritten by a reconcile');
        System.assertEquals(1900, after.Original_Package_Term_Cost__c,
            'the same reconcile still refreshes the other mirrored fields from the master');
    }

    @isTest
    static void test_repushPremiumPushesMasterValueDown() {
        Account dealer = createDistinctDealer(3);
        Package__c pkg = getMasterPackage();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true);

        // Real writes honour the kill switch, so enable it for this user first.
        insert new Aprotect_Portal_Settings__c(
            SetupOwnerId = UserInfo.getUserId(),
            Dealer_Sync_Enabled__c = true
        );

        Dealer_Package_Term__c dealerTerm = soleDealerTerm(dp.Id);
        update new Dealer_Package_Term__c(Id = dealerTerm.Id, Premium_Model_Fee__c = 425.00);

        Package_Term__c masterTerm = soleMasterTerm(pkg.Id);
        update new Package_Term__c(Id = masterTerm.Id, Premium_Model_Fee__c = 610.00);

        // Dry run: counts only, no DML.
        DealerPackageSyncService.RepushResult dry =
            DealerPackageSyncService.repushPremiumFees(pkg.Id, true);
        System.assertEquals(true, dry.success, 'dry run succeeds: ' + dry.message);
        System.assertEquals(true, dry.dryRun);
        System.assertEquals(1, dry.dealerTermsConsidered, 'one dealer term mirrors the one master term');
        System.assertEquals(1, dry.dealerTermsToUpdate, 'the dealer value differs from the master');
        System.assertEquals(425.00,
            [SELECT Premium_Model_Fee__c FROM Dealer_Package_Term__c WHERE Id = :dealerTerm.Id].Premium_Model_Fee__c,
            'a dry run must not write');

        Test.startTest();
        DealerPackageSyncService.RepushResult run =
            DealerPackageSyncService.repushPremiumFees(pkg.Id, false);
        Test.stopTest();

        System.assertEquals(true, run.success, 're-push succeeds: ' + run.message);
        System.assertEquals(1, run.dealerTermsUpdated, 'one dealer term updated');
        System.assertEquals(610.00,
            [SELECT Premium_Model_Fee__c FROM Dealer_Package_Term__c WHERE Id = :dealerTerm.Id].Premium_Model_Fee__c,
            'the on-demand re-push carries the new master premium down to the dealer term');
    }

    @isTest
    static void test_repushHonoursDealerSyncKillSwitch() {
        Account dealer = createDistinctDealer(4);
        Package__c pkg = getMasterPackage();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true);

        Dealer_Package_Term__c dealerTerm = soleDealerTerm(dp.Id);
        update new Dealer_Package_Term__c(Id = dealerTerm.Id, Premium_Model_Fee__c = 425.00);

        Package_Term__c masterTerm = soleMasterTerm(pkg.Id);
        update new Package_Term__c(Id = masterTerm.Id, Premium_Model_Fee__c = 610.00);

        // Kill switch OFF for this user (a user row wins over the org default).
        insert new Aprotect_Portal_Settings__c(
            SetupOwnerId = UserInfo.getUserId(),
            Dealer_Sync_Enabled__c = false
        );

        Test.startTest();
        DealerPackageSyncService.RepushResult run =
            DealerPackageSyncService.repushPremiumFees(pkg.Id, false);
        Test.stopTest();

        System.assertEquals(false, run.success, 'a real re-push is refused while sync is off');
        System.assertEquals(610.00,
            [SELECT Premium_Model_Fee__c FROM Package_Term__c WHERE Id = :masterTerm.Id].Premium_Model_Fee__c,
            'fixture sanity: the master carries the new fee');
        System.assertEquals(425.00,
            [SELECT Premium_Model_Fee__c FROM Dealer_Package_Term__c WHERE Id = :dealerTerm.Id].Premium_Model_Fee__c,
            'the kill switch blocks the re-push write');
    }

    // ---------------------------------------------------------------------
    // Price-anchor freeze: without local pricing the anchor still tracks the
    // master (initial mirror behaviour is unchanged)
    // ---------------------------------------------------------------------

    @isTest
    static void test_masterPriceChangeTracksWhenNoLocalPricing() {
        Account dealer = createDistinctDealer(4);
        Package__c pkg = getMasterPackage();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true);

        Package_Term__c masterTerm = [
            SELECT Id FROM Package_Term__c WHERE Package_Tier__c IN
                (SELECT Id FROM Package_Tier__c WHERE Package__c = :pkg.Id) LIMIT 1
        ];
        update new Package_Term__c(Id = masterTerm.Id, Price__c = 1900);

        Test.startTest();
        DealerPackageSyncService.reconcileForMasterTerm(new Set<Id>{ masterTerm.Id });
        Test.stopTest();

        Dealer_Package_Term__c after = [
            SELECT Original_Package_Term_Cost__c FROM Dealer_Package_Term__c
            WHERE Dealer_Package__c = :dp.Id LIMIT 1
        ];
        System.assertEquals(1900, after.Original_Package_Term_Cost__c,
            'With no local pricing the anchor keeps tracking the master');
    }

    // ---------------------------------------------------------------------
    // Removed add-on: never re-created, never refreshed
    // ---------------------------------------------------------------------

    @isTest
    static void test_removedOptionNeverRecreatedNorRefreshed() {
        Account dealer = createDistinctDealer(5);
        Package__c pkg = getMasterPackage();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true);

        Dealer_Package_Option__c removed = [
            SELECT Id, Original_Package_Option_Price__c FROM Dealer_Package_Option__c
            WHERE Dealer_Package__c = :dp.Id AND Selection_Type__c = 'Included' LIMIT 1
        ];
        update new Dealer_Package_Option__c(Id = removed.Id, Is_Removed__c = true);

        Integer before = [SELECT COUNT() FROM Dealer_Package_Option__c WHERE Dealer_Package__c = :dp.Id];

        Package_Option__c masterIncluded = [
            SELECT Id FROM Package_Option__c
            WHERE Package__c = :pkg.Id AND Selection_Type__c = 'Included' LIMIT 1
        ];
        update new Package_Option__c(Id = masterIncluded.Id, Price__c = 175);

        Test.startTest();
        DealerPackageSyncService.reconcileForMasterOption(new Set<Id>{ masterIncluded.Id });
        Test.stopTest();

        System.assertEquals(before,
            [SELECT COUNT() FROM Dealer_Package_Option__c WHERE Dealer_Package__c = :dp.Id],
            'A removed add-on is never re-created by a reconcile');

        Dealer_Package_Option__c after = [
            SELECT Is_Removed__c, Original_Package_Option_Price__c
            FROM Dealer_Package_Option__c WHERE Id = :removed.Id
        ];
        System.assertEquals(true, after.Is_Removed__c,
            'The removal flag survives the reconcile');
        System.assertEquals(removed.Original_Package_Option_Price__c,
            after.Original_Package_Option_Price__c,
            'A removed add-on is not refreshed from the master');
    }

    // ---------------------------------------------------------------------
    // Dealer commercial price: seeded at creation, then dealer-owned
    // ---------------------------------------------------------------------

    @isTest
    static void test_dealerCommercialPriceNeverRefreshedFromMaster() {
        Account dealer = createDistinctDealer(6);
        Package__c pkg = getMasterPackage();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true);

        // The dealer owns their commercial figure.
        update new Dealer_Package__c(Id = dp.Id, Commercial_Vehicle_Surcharge_Fee__c = 999.00);

        Test.startTest();
        DealerPackageSyncService.reconcileForMasterPackage(new Set<Id>{ pkg.Id });
        Test.stopTest();

        Dealer_Package__c after = [
            SELECT Commercial_Vehicle_Surcharge_Fee__c FROM Dealer_Package__c WHERE Id = :dp.Id
        ];
        System.assertEquals(999.00, after.Commercial_Vehicle_Surcharge_Fee__c,
            'The dealer commercial price is dealer-owned and never refreshed from the master');
    }
}