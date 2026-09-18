/**
 * PackageOptionMaintenanceServiceTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Covers PackageOptionMaintenanceService (P5 fold-in of the
 * Create_Package_Options admin capability):
 *   • createPackageOptions — typed rows → Package_Option__c rows
 *       - Included from a Package__c        → Package__c + Selection_Type Included
 *       - Included from a direct-link term  → package resolved via Term.Package__c
 *       - Included/Optional from tier-route terms → package resolved via Tier
 *       - Both links present                → tier route takes precedence
 *       - Optional from a Package_Term__c   → Package_Term__c link AND the
 *         Package__c resolved from the term (tier route, then direct link)
 *       - Optional from a Package__c        → legacy shape (Category/Min/Max)
 *       - Validation: null recordId, empty rows, missing optionId, negative
 *         price, min > max, term with no resolvable package (no tier AND no
 *         direct link)
 *       - First-error semantics: earliest bad row wins; no partial inserts
 *
 * Test Strategy:
 *   ✔ @isTest(SeeAllData=false)
 *   ✔ All DML via TestDataFactory; Option__c created inline (no factory method)
 *   ✔ Positive + Negative per branch
 *   ✔ System.assert* with descriptive messages
 *   ✔ Test.startTest / Test.stopTest
 *
 * The legacy CreatePackageOptionsControllerTest exercises the same logic
 * through the controller facade (JSON round trip + string contract); this
 * class pins the service's typed surface directly.
 */
@isTest(SeeAllData=false)
private class PackageOptionMaintenanceServiceTest {

    @TestSetup
    static void setup() {
        // Option__c catalog entry — no TestDataFactory method, created inline
        insert new Option__c(Name = 'Windshield Protection');

        Package__c pkg       = TestDataFactory.createPackage('Extended_Limited_Warranty', true);
        Package_Tier__c tier = TestDataFactory.createPackageTier(pkg.Id, true);
        TestDataFactory.createPackageTerm(pkg.Id, tier.Id, true);
    }

    // ── Query helpers ─────────────────────────────────────────────────────────

    private static Package__c getPackage() {
        return [SELECT Id, Name FROM Package__c LIMIT 1];
    }

    private static Package_Term__c getPackageTerm() {
        return [SELECT Id, Name FROM Package_Term__c LIMIT 1];
    }

    private static Option__c getOption() {
        return [SELECT Id, Name FROM Option__c LIMIT 1];
    }

    // ═════════════════════════════════════════════════════════════════════════
    // createPackageOptions — positive paths
    // ═════════════════════════════════════════════════════════════════════════

    @isTest
    static void testCreatePackageOptions_includedFromPackage_createsIncludedRecord() {
        Package__c pkg = getPackage();
        Option__c opt  = getOption();

        PackageOptionMaintenanceService.PackageOptionRowDTO row =
            new PackageOptionMaintenanceService.PackageOptionRowDTO();
        row.optionId      = opt.Id;
        row.inclusionText = 'Covers windshield chips';
        row.exclusionText = 'Excludes full replacement';

        Test.startTest();
        PackageOptionMaintenanceService.CreateResult result =
            PackageOptionMaintenanceService.createPackageOptions(
                pkg.Id, new List<PackageOptionMaintenanceService.PackageOptionRowDTO>{ row }, true);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Included rows from a Package should succeed: ' + result.message);
        System.assertEquals(1, result.createdCount, 'One row should report created');

        List<Package_Option__c> created = [
            SELECT Id, Package__c, Package_Term__c, Option__c, Selection_Type__c,
                   Inclusion_Text__c, Exclusion_Text__c, Price__c
            FROM Package_Option__c
            WHERE Package__c = :pkg.Id AND Selection_Type__c = 'Included'
        ];
        System.assertEquals(1, created.size(),
            'Exactly one Included Package_Option__c should be created for the package');
        System.assertEquals(opt.Id, created[0].Option__c, 'Option lookup should be set');
        System.assertEquals(null, created[0].Package_Term__c, 'Included rows link the Package, not a Term');
        System.assertEquals('Covers windshield chips', created[0].Inclusion_Text__c);
        System.assertEquals('Excludes full replacement', created[0].Exclusion_Text__c);
    }

    @isTest
    static void testCreatePackageOptions_optionalFromPackageTerm_createsOptionalRecordLinkedToTerm() {
        Package__c pkg       = getPackage();
        Package_Term__c term = getPackageTerm();
        Option__c opt        = getOption();

        PackageOptionMaintenanceService.PackageOptionRowDTO row =
            new PackageOptionMaintenanceService.PackageOptionRowDTO();
        row.optionId      = opt.Id;
        row.price         = 99.00;
        row.packageTermId = term.Id;

        Test.startTest();
        PackageOptionMaintenanceService.CreateResult result =
            PackageOptionMaintenanceService.createPackageOptions(
                term.Id, new List<PackageOptionMaintenanceService.PackageOptionRowDTO>{ row }, false);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Optional rows from a Package_Term should succeed: ' + result.message);
        System.assertEquals(1, result.createdCount, 'One row should report created');

        List<Package_Option__c> created = [
            SELECT Id, Package__c, Package_Term__c, Selection_Type__c, Price__c
            FROM Package_Option__c
            WHERE Package_Term__c = :term.Id AND Selection_Type__c = 'Optional'
        ];
        System.assertEquals(1, created.size(),
            'Exactly one Optional Package_Option__c should be created for the term');
        System.assertEquals(99.00, created[0].Price__c, 'Retail price should be stored');
        System.assertEquals(pkg.Id, created[0].Package__c,
            'Term-launched Optional rows must ALSO stamp the Package__c resolved from the term');
    }

    @isTest
    static void testCreatePackageOptions_optionalFromPackage_legacyShape_setsCategoryAndMinMax() {
        Package__c pkg = getPackage();
        Option__c opt  = getOption();

        PackageOptionMaintenanceService.PackageOptionRowDTO row =
            new PackageOptionMaintenanceService.PackageOptionRowDTO();
        row.optionId    = opt.Id;
        row.price       = 250.00;
        row.category    = 'Appearance';
        row.minimumValue = 10;
        row.maximumValue = 20;

        Test.startTest();
        PackageOptionMaintenanceService.CreateResult result =
            PackageOptionMaintenanceService.createPackageOptions(
                pkg.Id, new List<PackageOptionMaintenanceService.PackageOptionRowDTO>{ row }, false);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Legacy-shape Optional rows from a Package should succeed: ' + result.message);

        List<Package_Option__c> created = [
            SELECT Id, Package__c, Selection_Type__c, Price__c, Category__c,
                   Minimum_Value__c, Maximum_Value__c
            FROM Package_Option__c
            WHERE Package__c = :pkg.Id AND Selection_Type__c = 'Optional'
        ];
        System.assertEquals(1, created.size(),
            'Exactly one Optional Package_Option__c should be created for the package');
        System.assertEquals(250.00, created[0].Price__c);
        System.assertEquals('Appearance', created[0].Category__c);
        System.assertEquals(10, created[0].Minimum_Value__c);
        System.assertEquals(20, created[0].Maximum_Value__c);
    }

    @isTest
    static void testCreatePackageOptions_twoRows_insertsBoth() {
        Package__c pkg = getPackage();
        Option__c opt  = getOption();

        PackageOptionMaintenanceService.PackageOptionRowDTO row1 =
            new PackageOptionMaintenanceService.PackageOptionRowDTO();
        row1.optionId = opt.Id;
        row1.price    = 50.00;

        PackageOptionMaintenanceService.PackageOptionRowDTO row2 =
            new PackageOptionMaintenanceService.PackageOptionRowDTO();
        row2.optionId = opt.Id;
        row2.price    = 75.00;

        Test.startTest();
        PackageOptionMaintenanceService.CreateResult result =
            PackageOptionMaintenanceService.createPackageOptions(
                pkg.Id,
                new List<PackageOptionMaintenanceService.PackageOptionRowDTO>{ row1, row2 },
                false);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Multiple rows should succeed: ' + result.message);
        System.assertEquals(2, result.createdCount, 'Both rows should report created');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // p10 — term-anchored rows carry the package link (dealer-sync requirement)
    // ═════════════════════════════════════════════════════════════════════════

    /**
     * A term-anchored (Additional) create must carry BOTH the Package_Term__c
     * link and the Package__c resolved from that term — the package link the
     * dealer sync keys on to mirror term-anchored options out to dealers.
     * Uses a tier-less term so the resolution takes the direct-link route.
     */
    @isTest
    static void testCreatePackageOptions_termAnchoredRow_carriesResolvedPackage() {
        Package__c pkg = getPackage();
        Package_Term__c tierless = TestDataFactory.createPackageTerm(pkg.Id, null, true);
        Option__c opt = getOption();

        PackageOptionMaintenanceService.PackageOptionRowDTO row =
            new PackageOptionMaintenanceService.PackageOptionRowDTO();
        row.optionId      = opt.Id;
        row.price         = 30.00;
        row.packageTermId = tierless.Id;

        Test.startTest();
        PackageOptionMaintenanceService.CreateResult result =
            PackageOptionMaintenanceService.createPackageOptions(
                tierless.Id, new List<PackageOptionMaintenanceService.PackageOptionRowDTO>{ row }, false);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Term-anchored create should succeed: ' + result.message);

        List<Package_Option__c> created = [
            SELECT Id, Package__c, Package_Term__c, Selection_Type__c
            FROM Package_Option__c
            WHERE Package_Term__c = :tierless.Id AND Selection_Type__c = 'Optional'
        ];
        System.assertEquals(1, created.size(), 'Exactly one Optional row should be created');
        System.assertEquals(tierless.Id, created[0].Package_Term__c, 'Row keeps its term link');
        System.assertEquals(pkg.Id, created[0].Package__c,
            'Row must carry the Package__c resolved from the term (the dealer-sync link)');
    }

    /**
     * When the term has NO direct Package__c but DOES carry a Package_Tier__c,
     * the resolution falls back to the tier's package — the same tier-first
     * resolution the service uses for validation.
     */
    @isTest
    static void testCreatePackageOptions_termAnchoredRow_resolvesPackageViaTierFallback() {
        Package__c pkg = getPackage();
        Package_Tier__c tier = TestDataFactory.createPackageTier(pkg.Id, true);
        // Term with a tier but NO direct package link.
        Package_Term__c tierOnlyTerm = TestDataFactory.createPackageTerm(null, tier.Id, true);
        Option__c opt = getOption();

        PackageOptionMaintenanceService.PackageOptionRowDTO row =
            new PackageOptionMaintenanceService.PackageOptionRowDTO();
        row.optionId      = opt.Id;
        row.price         = 40.00;
        row.packageTermId = tierOnlyTerm.Id;

        Test.startTest();
        PackageOptionMaintenanceService.CreateResult result =
            PackageOptionMaintenanceService.createPackageOptions(
                tierOnlyTerm.Id, new List<PackageOptionMaintenanceService.PackageOptionRowDTO>{ row }, false);
        Test.stopTest();

        System.assertEquals(true, result.success,
            'A tier-only term (no direct package) should resolve via the tier: ' + result.message);

        List<Package_Option__c> created = [
            SELECT Id, Package__c, Package_Term__c, Selection_Type__c
            FROM Package_Option__c
            WHERE Package_Term__c = :tierOnlyTerm.Id AND Selection_Type__c = 'Optional'
        ];
        System.assertEquals(1, created.size(), 'Exactly one Optional row should be created');
        System.assertEquals(pkg.Id, created[0].Package__c,
            'Package__c must fall back to the tier package when the term has no direct link');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // createPackageOptions — validation / negative paths
    // ═════════════════════════════════════════════════════════════════════════

    @isTest
    static void testCreatePackageOptions_nullRecordId_returnsError() {
        Option__c opt = getOption();

        PackageOptionMaintenanceService.PackageOptionRowDTO row =
            new PackageOptionMaintenanceService.PackageOptionRowDTO();
        row.optionId = opt.Id;
        row.price    = 50.00;

        Test.startTest();
        PackageOptionMaintenanceService.CreateResult result =
            PackageOptionMaintenanceService.createPackageOptions(
                null, new List<PackageOptionMaintenanceService.PackageOptionRowDTO>{ row }, false);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Null recordId should fail');
        System.assertEquals('Record ID is required', result.message);
        System.assertEquals(0, result.createdCount);
    }

    @isTest
    static void testCreatePackageOptions_emptyRows_returnsError() {
        Package__c pkg = getPackage();

        Test.startTest();
        PackageOptionMaintenanceService.CreateResult result =
            PackageOptionMaintenanceService.createPackageOptions(
                pkg.Id, new List<PackageOptionMaintenanceService.PackageOptionRowDTO>(), true);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Empty rows should fail');
        System.assertEquals('At least one row is required', result.message);
    }

    @isTest
    static void testCreatePackageOptions_nullRows_returnsError() {
        Package__c pkg = getPackage();

        Test.startTest();
        PackageOptionMaintenanceService.CreateResult result =
            PackageOptionMaintenanceService.createPackageOptions(pkg.Id, null, true);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Null rows should fail');
        System.assertEquals('At least one row is required', result.message);
    }

    @isTest
    static void testCreatePackageOptions_missingOptionId_returnsError() {
        Package__c pkg = getPackage();

        PackageOptionMaintenanceService.PackageOptionRowDTO row =
            new PackageOptionMaintenanceService.PackageOptionRowDTO();
        // optionId intentionally left null
        row.price = 50.00;

        Test.startTest();
        PackageOptionMaintenanceService.CreateResult result =
            PackageOptionMaintenanceService.createPackageOptions(
                pkg.Id, new List<PackageOptionMaintenanceService.PackageOptionRowDTO>{ row }, false);
        Test.stopTest();

        System.assertEquals(false, result.success, 'A row without an Option should fail');
        System.assertEquals('Option is required for all rows', result.message);
    }

    @isTest
    static void testCreatePackageOptions_negativePriceForOptional_returnsError() {
        Package__c pkg = getPackage();
        Option__c opt  = getOption();

        PackageOptionMaintenanceService.PackageOptionRowDTO row =
            new PackageOptionMaintenanceService.PackageOptionRowDTO();
        row.optionId = opt.Id;
        row.price    = -5.00;

        Test.startTest();
        PackageOptionMaintenanceService.CreateResult result =
            PackageOptionMaintenanceService.createPackageOptions(
                pkg.Id, new List<PackageOptionMaintenanceService.PackageOptionRowDTO>{ row }, false);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Negative optional price should fail');
        System.assertEquals('Price must be greater than or equal to 0', result.message);
    }

    @isTest
    static void testCreatePackageOptions_nullPriceForOptional_returnsError() {
        Package__c pkg = getPackage();
        Option__c opt  = getOption();

        PackageOptionMaintenanceService.PackageOptionRowDTO row =
            new PackageOptionMaintenanceService.PackageOptionRowDTO();
        row.optionId = opt.Id;
        // price intentionally left null

        Test.startTest();
        PackageOptionMaintenanceService.CreateResult result =
            PackageOptionMaintenanceService.createPackageOptions(
                pkg.Id, new List<PackageOptionMaintenanceService.PackageOptionRowDTO>{ row }, false);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Missing optional price should fail');
        System.assertEquals('Price must be greater than or equal to 0', result.message);
    }

    @isTest
    static void testCreatePackageOptions_minGreaterThanMax_returnsError() {
        Package__c pkg = getPackage();
        Option__c opt  = getOption();

        PackageOptionMaintenanceService.PackageOptionRowDTO row =
            new PackageOptionMaintenanceService.PackageOptionRowDTO();
        row.optionId    = opt.Id;
        row.price       = 100.00;
        row.minimumValue = 20;
        row.maximumValue = 10;

        Test.startTest();
        PackageOptionMaintenanceService.CreateResult result =
            PackageOptionMaintenanceService.createPackageOptions(
                pkg.Id, new List<PackageOptionMaintenanceService.PackageOptionRowDTO>{ row }, false);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Min > max on the legacy Package shape should fail');
        System.assertEquals('Minimum Value cannot be greater than Maximum Value', result.message);
    }

    @isTest
    static void testCreatePackageOptions_termWithoutResolvablePackage_returnsError() {
        // A Package_Term__c with NEITHER a Package_Tier__c link NOR a direct
        // Package__c lookup cannot resolve its Package (coalesced traversal:
        // Term → Tier → Package, then Term → Package).
        Option__c opt = getOption();

        Package_Term__c orphanTerm = new Package_Term__c(
            Name            = 'Orphan Test Term',
            Package__c      = null,
            Package_Tier__c = null,
            Price__c        = 1500.00,
            Month__c        = '24',
            Mileage__c      = 40000,
            Mileage_Unit__c = 'KM');
        insert orphanTerm;

        PackageOptionMaintenanceService.PackageOptionRowDTO row =
            new PackageOptionMaintenanceService.PackageOptionRowDTO();
        row.optionId = opt.Id;
        row.price    = 10.00;

        Test.startTest();
        PackageOptionMaintenanceService.CreateResult result =
            PackageOptionMaintenanceService.createPackageOptions(
                orphanTerm.Id, new List<PackageOptionMaintenanceService.PackageOptionRowDTO>{ row }, false);
        Test.stopTest();

        System.assertEquals(false, result.success,
            'A term with no resolvable package (no tier and no direct link) should fail');
        System.assertEquals('Could not find Package from Package Term relationship', result.message);
        System.assertEquals(0, result.createdCount, 'No rows should be created');
    }

    @isTest
    static void testCreatePackageOptions_includedFromTierlessTerm_createsIncludedRecordOnTermPackage() {
        // The majority term shape on this org: direct Package__c link, NO
        // Package_Tier__c. Options must resolve the package via the direct link.
        Package__c pkg = getPackage();
        Package_Term__c directTerm = TestDataFactory.createPackageTerm(pkg.Id, null, true);
        Option__c opt = getOption();

        PackageOptionMaintenanceService.PackageOptionRowDTO row =
            new PackageOptionMaintenanceService.PackageOptionRowDTO();
        row.optionId      = opt.Id;
        row.inclusionText = 'Included via direct link';
        row.exclusionText = 'Excluded: rust';

        Test.startTest();
        PackageOptionMaintenanceService.CreateResult result =
            PackageOptionMaintenanceService.createPackageOptions(
                directTerm.Id, new List<PackageOptionMaintenanceService.PackageOptionRowDTO>{ row }, true);
        Test.stopTest();

        System.assertEquals(true, result.success,
            'Included rows from a direct-link (tier-less) term should succeed: ' + result.message);
        System.assertEquals(1, result.createdCount, 'One row should report created');

        List<Package_Option__c> created = [
            SELECT Id, Package__c, Package_Term__c, Selection_Type__c
            FROM Package_Option__c
            WHERE Option__c = :opt.Id AND Selection_Type__c = 'Included'
        ];
        System.assertEquals(1, created.size(), 'Exactly one Included Package_Option__c should be created');
        System.assertEquals(pkg.Id, created[0].Package__c,
            'Included row should land on the term DIRECT-LINKED package, not the tier route');
        System.assertEquals(null, created[0].Package_Term__c,
            'Included rows link the Package, not a Term (legacy contract)');
    }

    @isTest
    static void testCreatePackageOptions_includedFromTierRouteTerm_createsIncludedRecord() {
        // Tier-route terms (Term → Tier → Package) keep working in Included mode.
        Package__c pkg = getPackage();
        Package_Term__c tieredTerm = getPackageTerm(); // created in @TestSetup with a tier
        Option__c opt = getOption();

        PackageOptionMaintenanceService.PackageOptionRowDTO row =
            new PackageOptionMaintenanceService.PackageOptionRowDTO();
        row.optionId      = opt.Id;
        row.inclusionText = 'Included via tier route';

        Test.startTest();
        PackageOptionMaintenanceService.CreateResult result =
            PackageOptionMaintenanceService.createPackageOptions(
                tieredTerm.Id, new List<PackageOptionMaintenanceService.PackageOptionRowDTO>{ row }, true);
        Test.stopTest();

        System.assertEquals(true, result.success,
            'Included rows from a tier-route term should succeed: ' + result.message);
        System.assertEquals(1, result.createdCount);

        List<Package_Option__c> created = [
            SELECT Id, Package__c, Package_Term__c, Selection_Type__c
            FROM Package_Option__c
            WHERE Option__c = :opt.Id AND Selection_Type__c = 'Included'
        ];
        System.assertEquals(1, created.size(), 'Exactly one Included Package_Option__c should be created');
        System.assertEquals(pkg.Id, created[0].Package__c,
            'Included row should land on the package resolved through the tier route');
        System.assertEquals(null, created[0].Package_Term__c,
            'Included rows link the Package, not a Term (legacy contract)');
    }

    @isTest
    static void testCreatePackageOptions_termWithBothLinks_prefersTierRoute() {
        // When a term carries BOTH links, the tier route wins (legacy contract):
        // the row must land on the TIER's package, not the term's direct link.
        Package__c directPkg = getPackage();
        Package__c tierPkg   = TestDataFactory.createPackage('Extended_Limited_Warranty', true);
        Package_Tier__c tier = TestDataFactory.createPackageTier(tierPkg.Id, true);

        Package_Term__c bothLinksTerm = TestDataFactory.createPackageTerm(directPkg.Id, tier.Id, true);
        Option__c opt = getOption();

        PackageOptionMaintenanceService.PackageOptionRowDTO row =
            new PackageOptionMaintenanceService.PackageOptionRowDTO();
        row.optionId = opt.Id;

        Test.startTest();
        PackageOptionMaintenanceService.CreateResult result =
            PackageOptionMaintenanceService.createPackageOptions(
                bothLinksTerm.Id, new List<PackageOptionMaintenanceService.PackageOptionRowDTO>{ row }, true);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Both-link term should succeed: ' + result.message);
        List<Package_Option__c> created = [
            SELECT Id, Package__c FROM Package_Option__c
            WHERE Option__c = :opt.Id AND Selection_Type__c = 'Included'
        ];
        System.assertEquals(1, created.size());
        System.assertEquals(tierPkg.Id, created[0].Package__c,
            'Tier route must take precedence over the term direct link (legacy contract)');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // createPackageOptions — first-error semantics (validation order + atomicity)
    // ═════════════════════════════════════════════════════════════════════════

    @isTest
    static void testCreatePackageOptions_firstErrorWins_missingOptionBeforePrice() {
        // Row order matters: the missing-option check precedes the price check,
        // and the FIRST bad row's error wins even when a later row is also bad.
        Package__c pkg = getPackage();
        Option__c opt  = getOption();

        PackageOptionMaintenanceService.PackageOptionRowDTO badOptionRow =
            new PackageOptionMaintenanceService.PackageOptionRowDTO();
        // optionId intentionally null — triggers the option error
        badOptionRow.price = 10.00;

        PackageOptionMaintenanceService.PackageOptionRowDTO badPriceRow =
            new PackageOptionMaintenanceService.PackageOptionRowDTO();
        badPriceRow.optionId = opt.Id;
        badPriceRow.price    = -1.00; // would trigger the price error if reached

        Test.startTest();
        PackageOptionMaintenanceService.CreateResult result =
            PackageOptionMaintenanceService.createPackageOptions(
                pkg.Id,
                new List<PackageOptionMaintenanceService.PackageOptionRowDTO>{ badOptionRow, badPriceRow },
                false);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals('Option is required for all rows', result.message,
            'First error (missing option) must win over the later price error');
        System.assertEquals(0, result.createdCount);
    }

    @isTest
    static void testCreatePackageOptions_firstErrorWins_noPartialInserts() {
        // Validation runs before the single insert DML: one bad row must leave
        // NO Package_Option__c rows behind (all-or-nothing per save).
        Package__c pkg = getPackage();
        Option__c opt  = getOption();

        PackageOptionMaintenanceService.PackageOptionRowDTO validRow =
            new PackageOptionMaintenanceService.PackageOptionRowDTO();
        validRow.optionId = opt.Id;
        validRow.price    = 20.00;

        PackageOptionMaintenanceService.PackageOptionRowDTO badRow =
            new PackageOptionMaintenanceService.PackageOptionRowDTO();
        badRow.optionId = opt.Id;
        badRow.price    = -3.00;

        Test.startTest();
        PackageOptionMaintenanceService.CreateResult result =
            PackageOptionMaintenanceService.createPackageOptions(
                pkg.Id,
                new List<PackageOptionMaintenanceService.PackageOptionRowDTO>{ validRow, badRow },
                false);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Negative price on the second row should fail the save');
        System.assertEquals('Price must be greater than or equal to 0', result.message);
        System.assertEquals(0,
            [SELECT COUNT() FROM Package_Option__c WHERE Package__c = :pkg.Id],
            'No Package_Option__c rows may be inserted when validation fails');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // p8 — Included and Additional are independent (split-state contract)
    // ═════════════════════════════════════════════════════════════════════════

    @isTest
    static void testCreatePackageOptions_additionalOnly_onTierlessTerm_createsOnlyAdditional() {
        // Additional-only save on a TIER-LESS term: one Package_Option__c with
        // Package_Term__c set and Package__c null, and NO Included row created.
        Package__c pkg = getPackage();
        Package_Term__c tierless = TestDataFactory.createPackageTerm(pkg.Id, null, true);
        Option__c opt = getOption();

        PackageOptionMaintenanceService.PackageOptionRowDTO row =
            new PackageOptionMaintenanceService.PackageOptionRowDTO();
        row.optionId      = opt.Id;
        row.price         = 120.00;
        row.packageTermId = tierless.Id;

        Test.startTest();
        PackageOptionMaintenanceService.CreateResult result =
            PackageOptionMaintenanceService.createPackageOptions(
                tierless.Id, new List<PackageOptionMaintenanceService.PackageOptionRowDTO>{ row }, false);
        Test.stopTest();

        System.assertEquals(true, result.success,
            'Additional-only save on a tier-less term should succeed: ' + result.message);
        System.assertEquals(1, result.createdCount, 'One Additional row should report created');

        List<Package_Option__c> created = [
            SELECT Id, Package__c, Package_Term__c, Selection_Type__c, Price__c
            FROM Package_Option__c
            WHERE Package_Term__c = :tierless.Id
        ];
        System.assertEquals(1, created.size(), 'Exactly one Additional Package_Option__c should be created');
        System.assertEquals(tierless.Id, created[0].Package_Term__c, 'Additional row links the term');
        System.assertEquals(pkg.Id, created[0].Package__c,
            'Additional term rows must ALSO stamp the Package__c resolved from the term');
        System.assertEquals('Optional', created[0].Selection_Type__c);
        System.assertEquals(120.00, created[0].Price__c, 'Additional price stored');

        System.assertEquals(0, [
            SELECT COUNT() FROM Package_Option__c
            WHERE Package__c = :pkg.Id AND Selection_Type__c = 'Included'
        ], 'An Additional-only save must create NO Included row');
    }

    @isTest
    static void testCreatePackageOptions_includedOnly_createsOnlyIncluded() {
        // Included-only save (from the same tier-less term): one row on the
        // package with Selection_Type = 'Included' and no term link.
        Package__c pkg = getPackage();
        Package_Term__c tierless = TestDataFactory.createPackageTerm(pkg.Id, null, true);
        Option__c opt = getOption();

        PackageOptionMaintenanceService.PackageOptionRowDTO row =
            new PackageOptionMaintenanceService.PackageOptionRowDTO();
        row.optionId      = opt.Id;
        row.inclusionText = 'Included only';

        Test.startTest();
        PackageOptionMaintenanceService.CreateResult result =
            PackageOptionMaintenanceService.createPackageOptions(
                tierless.Id, new List<PackageOptionMaintenanceService.PackageOptionRowDTO>{ row }, true);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Included-only save should succeed: ' + result.message);
        System.assertEquals(1, result.createdCount, 'One Included row should report created');

        List<Package_Option__c> created = [
            SELECT Id, Package__c, Package_Term__c, Selection_Type__c
            FROM Package_Option__c
            WHERE Package__c = :pkg.Id AND Selection_Type__c = 'Included'
        ];
        System.assertEquals(1, created.size(), 'Exactly one Included Package_Option__c should be created');
        System.assertEquals(pkg.Id, created[0].Package__c, 'Included row lands on the package');
        System.assertEquals(null, created[0].Package_Term__c,
            'Included rows link the Package, not a Term');

        System.assertEquals(0, [
            SELECT COUNT() FROM Package_Option__c WHERE Package_Term__c = :tierless.Id
        ], 'An Included-only save must create NO Additional (term) row');
    }

    @isTest
    static void testCreatePackageOptions_bothSections_landOnPackageAndTerm() {
        // One row in each section, saved in the same session: Included lands on
        // the Package__c, Additional lands on the Package_Term__c (Package__c null).
        Package__c pkg = getPackage();
        Package_Term__c tierless = TestDataFactory.createPackageTerm(pkg.Id, null, true);
        Option__c opt = getOption();

        PackageOptionMaintenanceService.PackageOptionRowDTO includedRow =
            new PackageOptionMaintenanceService.PackageOptionRowDTO();
        includedRow.optionId      = opt.Id;
        includedRow.inclusionText = 'Both — included';

        PackageOptionMaintenanceService.PackageOptionRowDTO additionalRow =
            new PackageOptionMaintenanceService.PackageOptionRowDTO();
        additionalRow.optionId      = opt.Id;
        additionalRow.price         = 45.00;
        additionalRow.packageTermId = tierless.Id;

        Test.startTest();
        PackageOptionMaintenanceService.CreateResult includedResult =
            PackageOptionMaintenanceService.createPackageOptions(
                tierless.Id, new List<PackageOptionMaintenanceService.PackageOptionRowDTO>{ includedRow }, true);
        PackageOptionMaintenanceService.CreateResult additionalResult =
            PackageOptionMaintenanceService.createPackageOptions(
                tierless.Id, new List<PackageOptionMaintenanceService.PackageOptionRowDTO>{ additionalRow }, false);
        Test.stopTest();

        System.assertEquals(true, includedResult.success, 'Included save should succeed: ' + includedResult.message);
        System.assertEquals(true, additionalResult.success, 'Additional save should succeed: ' + additionalResult.message);

        List<Package_Option__c> included = [
            SELECT Id, Package__c, Package_Term__c, Selection_Type__c
            FROM Package_Option__c
            WHERE Package__c = :pkg.Id AND Selection_Type__c = 'Included'
        ];
        List<Package_Option__c> additional = [
            SELECT Id, Package__c, Package_Term__c, Selection_Type__c, Price__c
            FROM Package_Option__c
            WHERE Package_Term__c = :tierless.Id AND Selection_Type__c = 'Optional'
        ];
        System.assertEquals(1, included.size(), 'One Included row expected');
        System.assertEquals(1, additional.size(), 'One Additional row expected');
        System.assertEquals(pkg.Id, included[0].Package__c, 'Included lands on the Package__c');
        System.assertEquals(null, included[0].Package_Term__c, 'Included carries no term link');
        System.assertEquals(tierless.Id, additional[0].Package_Term__c, 'Additional lands on the Package_Term__c');
        System.assertEquals(pkg.Id, additional[0].Package__c,
            'Additional also carries the Package__c resolved from the term');
        System.assertEquals(45.00, additional[0].Price__c, 'Additional price stored');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // p10fix regression — the inbound JSON row contract
    // ═════════════════════════════════════════════════════════════════════════

    /**
     * The exact row payload the package-option creator sends for an Additional
     * Options row (incident 2026-09-17). Round-tripped through JSON into the DTO
     * this must create the row — pinning the client↔DTO key/type contract (the
     * live failure was this payload being rejected with
     * "Option is required for all rows").
     */
    @isTest
    static void testLiveAdditionalRowPayload_isAccepted() {
        Package_Term__c term = getPackageTerm();
        Option__c opt        = getOption();

        // Verbatim shape of the live request (optionId / price / packageTermId).
        String liveRowJson =
            '[{"optionId":"' + opt.Id + '","price":100,"packageTermId":"' + term.Id + '"}]';

        List<PackageOptionMaintenanceService.PackageOptionRowDTO> rows =
            (List<PackageOptionMaintenanceService.PackageOptionRowDTO>)
                JSON.deserialize(liveRowJson,
                    List<PackageOptionMaintenanceService.PackageOptionRowDTO>.class);

        System.assertEquals(opt.Id, rows[0].optionId, 'optionId must survive the JSON round trip');
        System.assertEquals(100, rows[0].price, 'price must survive the JSON round trip');

        Test.startTest();
        PackageOptionMaintenanceService.CreateResult result =
            PackageOptionMaintenanceService.createPackageOptions(term.Id, rows, false);
        Test.stopTest();

        System.assertEquals(true, result.success,
            'The live Additional-options payload must be accepted: ' + result.message);
        System.assertEquals(1, result.createdCount, 'One row created');
    }

    /**
     * Every member of the row DTO must survive a JSON round trip under its exact
     * camelCase key. Guards the client↔DTO contract: a renamed or omitted member
     * would deserialize to null and reproduce the incident.
     */
    @isTest
    static void testRowDtoJsonRoundTrip_preservesEveryField() {
        String jsonRow = '[{"optionId":"a0AG1000007cLvSMAU","category":"Appearance",' +
            '"minimumValue":10,"maximumValue":20,"price":100,"inclusionText":"inc",' +
            '"exclusionText":"exc","packageTermId":"a06G100000MZa7JIAT"}]';

        List<PackageOptionMaintenanceService.PackageOptionRowDTO> rows =
            (List<PackageOptionMaintenanceService.PackageOptionRowDTO>)
                JSON.deserialize(jsonRow,
                    List<PackageOptionMaintenanceService.PackageOptionRowDTO>.class);
        PackageOptionMaintenanceService.PackageOptionRowDTO r = rows[0];

        System.assertEquals('a0AG1000007cLvSMAU', r.optionId, 'optionId');
        System.assertEquals('Appearance', r.category, 'category');
        System.assertEquals(10, r.minimumValue, 'minimumValue');
        System.assertEquals(20, r.maximumValue, 'maximumValue');
        System.assertEquals(100, r.price, 'price');
        System.assertEquals('inc', r.inclusionText, 'inclusionText');
        System.assertEquals('exc', r.exclusionText, 'exclusionText');
        System.assertEquals('a06G100000MZa7JIAT', r.packageTermId, 'packageTermId');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // p11 — read / delete / price update on EXISTING rows
    // ═════════════════════════════════════════════════════════════════════════

    @isTest
    static void testGetPackageOptions_readsExistingRowsForTerm() {
        Package__c pkg = getPackage();
        Package_Term__c term = getPackageTerm();
        Option__c opt = getOption();

        // Seed one Included (package-level) and one Additional (term-anchored)
        Package_Option__c inc = new Package_Option__c(
            Package__c = pkg.Id, Option__c = opt.Id, Selection_Type__c = 'Included',
            Inclusion_Text__c = 'Inc');
        Package_Option__c addl = new Package_Option__c(
            Package__c = pkg.Id, Package_Term__c = term.Id, Option__c = opt.Id,
            Selection_Type__c = 'Optional', Price__c = 55.00);
        insert new List<Package_Option__c>{ inc, addl };

        Test.startTest();
        List<PackageOptionMaintenanceService.PackageOptionView> included =
            PackageOptionMaintenanceService.getPackageOptions(term.Id, true);
        List<PackageOptionMaintenanceService.PackageOptionView> additional =
            PackageOptionMaintenanceService.getPackageOptions(term.Id, false);
        Test.stopTest();

        System.assertEquals(1, included.size(), 'One Included row for the term package');
        System.assertEquals(1, additional.size(), 'One Additional row for the term');
        System.assertEquals(inc.Id, included[0].id, 'Included row id');
        System.assertEquals(addl.Id, additional[0].id, 'Additional row id');
        System.assertEquals(55.00, additional[0].price, 'Additional price');
    }

    @isTest
    static void testDeletePackageOption_deletesIncludedRow() {
        Package__c pkg = getPackage();
        Option__c opt = getOption();
        Package_Option__c inc = new Package_Option__c(
            Package__c = pkg.Id, Option__c = opt.Id, Selection_Type__c = 'Included');
        insert inc;

        Test.startTest();
        PackageOptionMaintenanceService.OperationResult res =
            PackageOptionMaintenanceService.deletePackageOption(pkg.Id, true, inc.Id);
        Test.stopTest();

        System.assertEquals(true, res.success, res.message);
        System.assertEquals(1, res.affectedCount);
        System.assertEquals(0, [SELECT COUNT() FROM Package_Option__c WHERE Id = :inc.Id],
            'Row should be gone');
    }

    @isTest
    static void testDeletePackageOption_deletesAdditionalRow() {
        Package__c pkg = getPackage();
        Package_Term__c term = getPackageTerm();
        Option__c opt = getOption();
        Package_Option__c addl = new Package_Option__c(
            Package__c = pkg.Id, Package_Term__c = term.Id, Option__c = opt.Id,
            Selection_Type__c = 'Optional', Price__c = 10.00);
        insert addl;

        Test.startTest();
        PackageOptionMaintenanceService.OperationResult res =
            PackageOptionMaintenanceService.deletePackageOption(term.Id, false, addl.Id);
        Test.stopTest();

        System.assertEquals(true, res.success, res.message);
        System.assertEquals(0, [SELECT COUNT() FROM Package_Option__c WHERE Id = :addl.Id]);
    }

    @isTest
    static void testUpdatePackageOptionPrices_updatesPrice() {
        Package__c pkg = getPackage();
        Option__c opt = getOption();
        Package_Option__c addl = new Package_Option__c(
            Package__c = pkg.Id, Option__c = opt.Id, Selection_Type__c = 'Optional',
            Price__c = 20.00);
        insert addl;

        PackageOptionMaintenanceService.PriceUpdateRowDTO dto =
            new PackageOptionMaintenanceService.PriceUpdateRowDTO();
        dto.optionRowId = addl.Id;
        dto.price = 35.00;

        Test.startTest();
        PackageOptionMaintenanceService.OperationResult res =
            PackageOptionMaintenanceService.updatePackageOptionPrices(
                pkg.Id, new List<PackageOptionMaintenanceService.PriceUpdateRowDTO>{ dto });
        Test.stopTest();

        System.assertEquals(true, res.success, res.message);
        System.assertEquals(35.00, [SELECT Price__c FROM Package_Option__c WHERE Id = :addl.Id].Price__c);
    }

    @isTest
    static void testDeletePackageOption_rejectsCrossContextRow() {
        Package__c pkg = getPackage();
        Package_Term__c otherTerm = TestDataFactory.createPackageTerm(pkg.Id, null, true);
        Option__c opt = getOption();
        Package_Option__c addl = new Package_Option__c(
            Package__c = pkg.Id, Package_Term__c = otherTerm.Id, Option__c = opt.Id,
            Selection_Type__c = 'Optional', Price__c = 10.00);
        insert addl;

        Test.startTest();
        PackageOptionMaintenanceService.OperationResult res =
            PackageOptionMaintenanceService.deletePackageOption(pkg.Id, false, addl.Id);
        Test.stopTest();

        System.assertEquals(false, res.success);
        System.assert(res.message.contains('does not belong'));
        System.assertEquals(1, [SELECT COUNT() FROM Package_Option__c WHERE Id = :addl.Id]);
    }

    @isTest
    static void testUpdatePackageOptionPrices_rejectsCrossContextRow() {
        Package__c pkg = getPackage();
        Package_Term__c otherTerm = TestDataFactory.createPackageTerm(pkg.Id, null, true);
        Option__c opt = getOption();
        Package_Option__c addl = new Package_Option__c(
            Package__c = pkg.Id, Package_Term__c = otherTerm.Id, Option__c = opt.Id,
            Selection_Type__c = 'Optional', Price__c = 10.00);
        insert addl;

        PackageOptionMaintenanceService.PriceUpdateRowDTO dto =
            new PackageOptionMaintenanceService.PriceUpdateRowDTO();
        dto.optionRowId = addl.Id;
        dto.price = 99.00;

        Test.startTest();
        PackageOptionMaintenanceService.OperationResult res =
            PackageOptionMaintenanceService.updatePackageOptionPrices(
                pkg.Id, new List<PackageOptionMaintenanceService.PriceUpdateRowDTO>{ dto });
        Test.stopTest();

        System.assertEquals(false, res.success);
        System.assert(res.message.contains('does not belong'));
        System.assertEquals(10.00, [SELECT Price__c FROM Package_Option__c WHERE Id = :addl.Id].Price__c);
    }
}