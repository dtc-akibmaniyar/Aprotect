/**
 * ApplicationSnapshotServiceTest
 *
 * P4 unit A tests (change-implementation plan §11 P4 [A], §13.2 P4): the
 * engine commit snapshot writes Application_Package_Line_Item__c rows
 * idempotently with provenance filled; the persisted line set sums to the
 * engine's stored totals (Base_Coverage + fee + tax lines summing to stored
 * totals, §07.3 stored = displayed invariant).
 *
 * ORG FACT (verified): Application_Package__c has NO stored field for
 * diesel/commercial/powersports fee amounts — its display totals are formulas
 * over DPP + markup + add-ons + Premium_Model_Fee (base + premium only). Fee
 * mixes therefore reconcile at the LINE-ITEM level: sum(Base + fee lines) =
 * engine no-tax total and sum(all lines incl. Tax) = engine with-tax total.
 * The base/premium-only case also reconciles against the stored formula
 * fields directly.
 *
 * TEST CONTEXT FACT: inserting a NON-engine-priced Application_Package runs
 * the legacy create-time flow, which CANNOT_EXECUTE_FLOW_TRIGGER in the test
 * user context (pre-existing baseline failure). Every insert in this class
 * therefore mirrors production: the engine stamps the record (Priced_By_Engine
 * = true) BEFORE the DML, so the flow terminates at its engine guard.
 *
 * Coverage:
 *   - base-only: Base_Coverage + Tax rows sum to stored formula totals
 *   - mixed-fee (premium + diesel + commercial): fee rows with schedule/member
 *     provenance; line sum == engine payload totals
 *   - tax line carries the single engine tax amount (D5)
 *   - idempotency (re-run converges, no duplicates)
 *   - flag gate (Line_Item_Snapshot_Enabled__c off => no rows)
 *   - legacy marker gate (Priced_By_Engine__c false => no rows)
 *   - commission recursion: engine commit (insert + snapshot) does not
 *     double-fire CommissionCalculationTrigger and does not clobber the
 *     engine-written inputs
 */
@isTest
private class ApplicationSnapshotServiceTest {

    private static Map<String, Id> recordTypes;
    private static Id rt(String sObjectType, String devName) {
        if (recordTypes == null) {
            recordTypes = new Map<String, Id>();
            for (RecordType r : [SELECT Id, SObjectType, DeveloperName FROM RecordType
                                 WHERE SObjectType IN ('Account','Package__c','Dealer_Package__c','Application_Package__c')]) {
                recordTypes.put(r.SObjectType + '.' + r.DeveloperName, r.Id);
            }
        }
        return recordTypes.get(sObjectType + '.' + devName);
    }

    private static Tax__c taxRegion(String name, Decimal rate) {
        Tax__c t = new Tax__c(Name = name, Total_Tax_Rate__c = rate);
        insert t;
        return t;
    }

    private static Account dealer(String name, Tax__c region) {
        Account d = new Account(Name = name,
            RecordTypeId = rt('Account', 'Dealer_Account'),
            Charge_Premium_Vehicle_Fee__c = false,
            Tax_Region__c = region != null ? region.Id : null);
        insert d;
        return d;
    }

    private static Make__c make(String name) { Make__c m = new Make__c(Name = name); insert m; return m; }
    private static Model__c model(Make__c m, String name) { Model__c mo = new Model__c(Name = name, Make__c = m.Id); insert mo; return mo; }

    private static Vehicle__c vehicle(String name, Make__c m, Model__c mo, String fuel, String usage) {
        Vehicle__c v = new Vehicle__c(Name = name, Make_Lookup__c = m.Id, Model_Lookup__c = mo.Id,
            Fuel_Type__c = fuel, Usage_Type__c = usage);
        insert v;
        return v;
    }

    private class Ctx {
        public Account dealer;
        public Vehicle__c v;
        public Id dealerPackageId;
        public Dealer_Package_Term__c dt;
        public Id masterTermId;
        public Application__c app;
    }

    /** Full context: catalogue + dealer mirror + schedules + Application. */
    private static Ctx build(String tag, Decimal rate, Boolean premium, Boolean diesel, Boolean commercial) {
        Tax__c tax = taxRegion('ASR' + tag, rate);
        Account d = dealer('D' + tag, tax);
        Make__c mk = make('MK' + tag);
        Model__c mo = model(mk, 'MD' + tag);
        Vehicle__c v = vehicle('V' + tag, mk, mo,
            diesel ? 'Diesel' : 'Gas',
            commercial ? 'Commercial/Business Use' : 'Personal Use');

        Package_Group__c grp = new Package_Group__c(Name = 'GRP' + tag, Active__c = true);
        insert grp;
        Package__c pkg = new Package__c(Name = 'PKG' + tag, Package_Group__c = grp.Id,
            RecordTypeId = rt('Package__c', 'Extended_Limited_Warranty'), Is_Active__c = true);
        insert pkg;
        Package_Tier__c tier = new Package_Tier__c(Name = 'TIR' + tag, Package__c = pkg.Id);
        insert tier;
        Package_Term__c mt = new Package_Term__c(Name = 'TRM' + tag, Package_Tier__c = tier.Id, Price__c = 1000.00);
        insert mt;

        Date vf = Date.newInstance(2026, 1, 1);
        if (premium) {
            Vehicle_Schedule__c s = new Vehicle_Schedule__c(Name = 'SP' + tag, Type__c = 'Premium_Tier', Is_Active__c = true, Valid_From__c = vf);
            insert s;
            insert new Vehicle_Schedule_Member__c(Name = 'SPm', Vehicle_Schedule__c = s.Id, Make__c = mk.Id,
                Include_All_Models__c = true, Tier__c = 'Tier 2', Amount_Type__c = 'Flat',
                Premium_Model_Fee__c = 299.00, Sort_Order__c = 0);
            insert new Vehicle_Schedule_Assignment__c(Name = 'SPa', Vehicle_Schedule__c = s.Id, Package__c = pkg.Id, Effective_From__c = vf);
        }
        if (diesel) {
            Vehicle_Schedule__c s = new Vehicle_Schedule__c(Name = 'SD' + tag, Type__c = 'Diesel_Fee', Is_Active__c = true, Valid_From__c = vf);
            insert s;
            insert new Vehicle_Schedule_Member__c(Name = 'SDm', Vehicle_Schedule__c = s.Id,
                Include_All_Models__c = true, Amount_Type__c = 'Flat',
                Premium_Model_Fee__c = 150.00, Sort_Order__c = 0);
            insert new Vehicle_Schedule_Assignment__c(Name = 'SDa', Vehicle_Schedule__c = s.Id, Package__c = pkg.Id, Effective_From__c = vf);
        }
        if (commercial) {
            Vehicle_Schedule__c s = new Vehicle_Schedule__c(Name = 'SC' + tag, Type__c = 'Commercial_Surcharge', Is_Active__c = true, Valid_From__c = vf);
            insert s;
            insert new Vehicle_Schedule_Member__c(Name = 'SCm', Vehicle_Schedule__c = s.Id,
                Include_All_Models__c = true, Amount_Type__c = 'Flat',
                Premium_Model_Fee__c = 400.00, Sort_Order__c = 0);
            insert new Vehicle_Schedule_Assignment__c(Name = 'SCa', Vehicle_Schedule__c = s.Id, Package__c = pkg.Id, Effective_From__c = vf);
        }

        Dealer_Package__c dp = new Dealer_Package__c(Name = 'DP' + tag, Dealer__c = d.Id,
            Package__c = pkg.Id, RecordTypeId = rt('Dealer_Package__c', 'Extended_Limited_Warranty'));
        insert dp;
        Dealer_Package_Term__c dt = new Dealer_Package_Term__c(Name = 'DPT' + tag,
            Dealer_Package__c = dp.Id, Package_Term__c = mt.Id,
            Original_Package_Term_Cost__c = 1000.00, Markup__c = 100.00, Markup_Type__c = '$');
        insert dt;

        Ctx c = new Ctx();
        c.dealer = d; c.v = v; c.dealerPackageId = dp.Id; c.dt = dt; c.masterTermId = mt.Id;
        c.app = new Application__c(Vehicle__c = v.Id, Dealer_Name__c = d.Id);
        insert c.app;
        return c;
    }

    private static void setFlags(Boolean engine, Boolean snapshot) {
        delete [SELECT Id FROM Aprotect_Portal_Settings__c];
        insert new Aprotect_Portal_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Pricing_Engine_Enabled__c = engine,
            Line_Item_Snapshot_Enabled__c = snapshot,
            Dealer_Sync_Enabled__c = true
        );
    }

    /** Engine-stamp a package, then INSERT it (flow guard: engine marker set
     *  pre-DML so the create-time flow terminates — mirrors production). */
    private static Application_Package__c insertEnginePricedPackage(Ctx c) {
        Application_Package__c pkg = new Application_Package__c(
            Name = 'APK' + c.v.Name,
            Application__c = c.app.Id,
            Dealer__c = c.dealer.Id,
            Dealer_Package__c = c.dealerPackageId,
            Dealer_Package_Term__c = c.dt.Id,
            Package_Term__c = c.masterTermId,
            RecordTypeId = rt('Application_Package__c', 'Extended_Limited_Warranty'),
            Active__c = true
        );
        PricingEngineService.QuoteRequest req = requestFor(c, pkg);
        PricingEngineService.QuoteResult res = PricingEngineService.applyEnginePricing(pkg, req);
        System.assert(res.success, 'engine pricing expected to succeed: ' + res.errors);
        Database.insert(pkg, System.AccessLevel.SYSTEM_MODE);
        return pkg;
    }

    private static PricingEngineService.QuoteRequest requestFor(Ctx c, Application_Package__c pkg) {
        PricingEngineService.QuoteRequest req = new PricingEngineService.QuoteRequest();
        req.dealerId = c.dealer.Id;
        req.vehicleId = c.v.Id;
        req.dealerPackageId = c.dealerPackageId;
        req.dealerTermId = c.dt.Id;
        req.applicationPackageId = pkg.Id;
        req.asOfDate = Date.newInstance(2026, 9, 3);
        return req;
    }

    // ORG FACT (P3): new fields (line items, Priced_By_Engine) carry no FLS for
    // the integration/test user, so plain SOQL on them throws "No such column".
    // Tests query in SYSTEM_MODE (the same mode production writes use).
    private static List<Application_Package_Line_Item__c> lines(Id pkgId) {
        return Database.query(
            'SELECT Line_Type__c, Description__c, Amount__c, Tax_Amount__c, Taxable__c,' +
            ' Quantity__c, Sort_Order__c, Package_Term__c, Package_Option__c,' +
            ' Vehicle_Schedule__c, Vehicle_Schedule_Member__c' +
            ' FROM Application_Package_Line_Item__c' +
            ' WHERE Application_Package__c = \'' + pkgId + '\'' +
            ' ORDER BY Sort_Order__c, Id',
            System.AccessLevel.SYSTEM_MODE);
    }

    private static Application_Package__c storedPkg(Id pkgId) {
        return (Application_Package__c) Database.query(
            'SELECT Id, Priced_By_Engine__c, Dealer_Package_Price__c, Dealer_Markup__c,' +
            ' Wholesale_Price__c, Aprotect_Net__c, Commission_Amount__c,' +
            ' Contract_Premium_Price__c, Tax_Amount__c,' +
            ' Contract_Premium_Price_Without_Tax__c' +
            ' FROM Application_Package__c WHERE Id = \'' + pkgId + '\'',
            System.AccessLevel.SYSTEM_MODE)[0];
    }

    // ------------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------------

    @isTest
    static void testBaseOnly_LinesSumToStoredTotals() {
        setFlags(true, true);
        Ctx c = build('A1', 13, false, false, false);
        Application_Package__c pkg = insertEnginePricedPackage(c);

        Test.startTest();
        PricingEngineService.QuoteResult res = PricingEngineService.applyEnginePricing(pkg, requestFor(c, pkg));
        Boolean written = ApplicationSnapshotService.writeSnapshot(pkg.Id, res);
        Test.stopTest();

        System.assertEquals(true, written, 'snapshot must write when flag on + engine priced');
        System.assertEquals(1100.00, res.noTaxTotal, 'base 1000 + $100 markup, no fees');

        List<Application_Package_Line_Item__c> rows = lines(pkg.Id);
        Map<String, Application_Package_Line_Item__c> byType = new Map<String, Application_Package_Line_Item__c>();
        for (Application_Package_Line_Item__c r : rows) byType.put(r.Line_Type__c, r);
        System.assertEquals(2, rows.size(), 'expected Base_Coverage + Tax, got ' + rows.size());
        System.assertEquals(1100.00, byType.get('Base_Coverage').Amount__c);
        System.assertEquals(143.00, byType.get('Tax').Amount__c, '13% of 1100');
        System.assertEquals(false, byType.get('Tax').Taxable__c);
        System.assertEquals(c.masterTermId, byType.get('Base_Coverage').Package_Term__c,
            'base provenance lookup = master Package_Term');

        // Line sum == stored formula totals (base-only case is expressible).
        Application_Package__c stored = storedPkg(pkg.Id);
        Decimal lineSum = 0;
        for (Application_Package_Line_Item__c r : rows) lineSum = PricingEngineService.money(lineSum + r.Amount__c);
        System.assertEquals(stored.Contract_Premium_Price__c, lineSum,
            'stored with-tax total == sum of all lines');
        System.assertEquals(1100.00, stored.Contract_Premium_Price_Without_Tax__c);
        System.assertEquals(143.00, stored.Tax_Amount__c);
    }

    @isTest
    static void testMixedFees_FeeLinesWithProvenanceAndTax() {
        setFlags(true, true);
        // premium 299 (make Tier 2) + diesel 150 + commercial 400 on one vehicle
        Ctx c = build('A2', 13, true, true, true);
        Application_Package__c pkg = insertEnginePricedPackage(c);

        Test.startTest();
        PricingEngineService.QuoteResult res = PricingEngineService.applyEnginePricing(pkg, requestFor(c, pkg));
        ApplicationSnapshotService.writeSnapshot(pkg.Id, res);
        Test.stopTest();

        // engine payload: base 1100 + premium 299 + diesel 150 + commercial 400 = 1949 no-tax
        System.assertEquals(1949.00, res.noTaxTotal);
        System.assertEquals(253.37, res.taxAmount, '13% of 1949');

        List<Application_Package_Line_Item__c> rows = lines(pkg.Id);
        Map<String, Application_Package_Line_Item__c> byType = new Map<String, Application_Package_Line_Item__c>();
        for (Application_Package_Line_Item__c r : rows) byType.put(r.Line_Type__c, r);
        System.assert(byType.containsKey('Base_Coverage'), 'base line present');
        System.assert(byType.containsKey('Premium_Fee'), 'premium fee line present');
        System.assert(byType.containsKey('Diesel_Fee'), 'diesel fee line present');
        System.assert(byType.containsKey('Commercial_Surcharge'), 'commercial surcharge line present');
        System.assert(byType.containsKey('Tax'), 'tax line present');

        // Fee provenance.
        System.assertNotEquals(null, byType.get('Premium_Fee').Vehicle_Schedule__c);
        System.assertNotEquals(null, byType.get('Premium_Fee').Vehicle_Schedule_Member__c);
        System.assertNotEquals(null, byType.get('Diesel_Fee').Vehicle_Schedule__c);
        System.assertNotEquals(null, byType.get('Commercial_Surcharge').Vehicle_Schedule__c);

        // Line set == engine payload totals (fee mixes reconcile at line level:
        // no stored field exists on Application_Package for these fee amounts).
        Decimal noTaxSum = 0;
        Decimal allSum = 0;
        for (Application_Package_Line_Item__c r : rows) {
            allSum = PricingEngineService.money(allSum + r.Amount__c);
            if (r.Line_Type__c != 'Tax') {
                noTaxSum = PricingEngineService.money(noTaxSum + r.Amount__c);
            }
        }
        System.assertEquals(1949.00, noTaxSum, 'non-tax line sum == engine no-tax total');
        System.assertEquals(2202.37, allSum, 'all lines incl. tax == engine with-tax total');
        System.assertEquals(byType.get('Tax').Amount__c, res.taxAmount);
    }

    @isTest
    static void testSnapshotIdempotent() {
        setFlags(true, true);
        Ctx c = build('A3', 13, true, false, false);
        Application_Package__c pkg = insertEnginePricedPackage(c);

        Test.startTest();
        ApplicationSnapshotService.writeSnapshot(pkg.Id, PricingEngineService.applyEnginePricing(pkg, requestFor(c, pkg)));
        Integer first = lines(pkg.Id).size();
        // Second save of the same quote re-snapshots (delete + insert).
        ApplicationSnapshotService.writeSnapshot(pkg.Id, PricingEngineService.applyEnginePricing(pkg, requestFor(c, pkg)));
        Test.stopTest();

        System.assertEquals(first, lines(pkg.Id).size(),
            're-snapshot must converge to the same rows (no duplicates)');
        System.assertEquals(3, first, 'base + premium + tax');
    }

    @isTest
    static void testFlagOff_WritesNothing() {
        setFlags(true, false); // engine on, snapshot flag off (pre-T5 org state)
        Ctx c = build('A4', 13, false, false, false);
        Application_Package__c pkg = insertEnginePricedPackage(c);

        Test.startTest();
        Boolean written = ApplicationSnapshotService.writeSnapshot(pkg.Id,
            PricingEngineService.applyEnginePricing(pkg, requestFor(c, pkg)));
        Test.stopTest();

        System.assertEquals(false, written,
            'no snapshot write while Line_Item_Snapshot_Enabled__c is off');
        System.assertEquals(0, lines(pkg.Id).size());
    }

    @isTest
    static void testLegacyRecordNeverSnapshots() {
        setFlags(true, true);
        Ctx c = build('A5', 13, false, false, false);
        // Engine-priced insert (flow guard), then simulate a legacy record by
        // clearing the marker in memory before the snapshot call — the guard
        // must refuse (this is the pre-T5 legacy quote population).
        Application_Package__c pkg = insertEnginePricedPackage(c);
        Application_Package__c legacyView = new Application_Package__c(Id = pkg.Id);
        legacyView.Priced_By_Engine__c = false;

        Test.startTest();
        Boolean written = ApplicationSnapshotService.snapshotEnginePriced(legacyView,
            PricingEngineService.applyEnginePricing(pkg, requestFor(c, pkg)));
        Test.stopTest();

        System.assertEquals(false, written, 'non-engine-priced records must never snapshot');
        System.assertEquals(0, lines(pkg.Id).size());
    }

    @isTest
    static void testEngineCommit_CommissionNotDoubleFired() {
        // Commission recursion guard (plan §04.3 / §13.2 P4): an engine-priced
        // insert fires CommissionCalculationTrigger before-insert exactly once,
        // and the snapshot child write must not re-fire it. Engine-written
        // inputs survive the commission pass (no clobber, no loop).
        setFlags(true, true);
        Ctx c = build('A6', 13, false, false, false);
        Application_Package__c pkg = insertEnginePricedPackage(c);

        Test.startTest();
        ApplicationSnapshotService.writeSnapshot(pkg.Id,
            PricingEngineService.applyEnginePricing(pkg, requestFor(c, pkg)));
        Test.stopTest();

        Application_Package__c stored = storedPkg(pkg.Id);
        System.assertEquals(true, stored.Priced_By_Engine__c, 'engine marker');
        System.assertEquals(1000.00, stored.Dealer_Package_Price__c, 'engine DPP preserved after commission');
        System.assertEquals(100.00, stored.Dealer_Markup__c, 'engine markup preserved after commission');
        System.assertEquals(1243.00, stored.Contract_Premium_Price__c, 'stored with-tax intact');
        System.assertEquals(143.00, stored.Tax_Amount__c);
        // Commission outputs present (fired exactly once, no clobber of engine fields).
        System.assertEquals(1000.00, stored.Wholesale_Price__c, 'commission wholesale anchor');
        System.assertNotEquals(null, stored.Commission_Amount__c);
        // Snapshot rows present.
        System.assertEquals(2, lines(pkg.Id).size(), 'base + tax lines after engine commit');
    }

    @isTest
    static void testEngineRePrice_CommissionNoAccumulation_RollupConverges() {
        // Plan §04.3 / §13.3: repeated engine commits (term change re-price,
        // as the updateApplicationPackage seam does) must NOT double-fire or
        // accumulate commission, and the Dealer_Package DLRS-shape rollups
        // must converge (Total_Warranties_Sold stays 1 for one active package).
        setFlags(true, true);
        Ctx c = build('A7', 13, false, false, false);
        Application_Package__c pkg = insertEnginePricedPackage(c);

        Test.startTest();
        // First engine commit (the insert already fired commission once).
        ApplicationSnapshotService.writeSnapshot(pkg.Id,
            PricingEngineService.applyEnginePricing(pkg, requestFor(c, pkg)));

        // Second engine commit on the SAME record — simulates a dealer editing
        // the term and the controller seam re-running applyEnginePricingIfEnabled
        // + update. Commission must recompute to the SAME values (set-based,
        // no accumulation), rollups must count one package.
        pkg.Dealer_Package_Term__c = c.dt.Id; // same term (re-price path)
        PricingEngineService.QuoteRequest req2 = requestFor(c, pkg);
        PricingEngineService.applyEnginePricing(pkg, req2);
        Database.update(pkg, System.AccessLevel.SYSTEM_MODE);
        ApplicationSnapshotService.snapshotEnginePriced(pkg,
            PricingEngineService.applyEnginePricing(pkg, requestFor(c, pkg)));
        Test.stopTest();

        Application_Package__c stored = storedPkg(pkg.Id);
        // Wholesale anchor is the master wholesale (1000) regardless of how many
        // times commission ran — a double-fire would show 2000 here.
        System.assertEquals(1000.00, stored.Wholesale_Price__c,
            'commission must not accumulate across engine commits');
        System.assertEquals(1000.00, stored.Dealer_Package_Price__c, 'engine DPP stable');
        System.assertEquals(1243.00, stored.Contract_Premium_Price__c, 'stored with-tax stable');

        // Rollup convergence on the dealer package (DLRS-shape fields unchanged
        // in shape): one active Application_Package => exactly one warranty.
        Dealer_Package__c dp = (Dealer_Package__c) Database.query(
            'SELECT Id, Total_Warranties_Sold__c, Total_Commission_Earned__c,' +
            ' Total_Revenue__c, Total_Reserve_Accrued__c' +
            ' FROM Dealer_Package__c WHERE Id = \'' + c.dealerPackageId + '\'',
            System.AccessLevel.SYSTEM_MODE);
        System.assertEquals(1, dp.Total_Warranties_Sold__c == null ? 0 : Integer.valueOf(dp.Total_Warranties_Sold__c),
            'rollup counts the single package exactly once (no double-fire)');
        System.assertNotEquals(null, dp.Total_Commission_Earned__c);
        System.assertEquals(2, lines(pkg.Id).size(), 'snapshot refreshed after re-price');
    }

    @isTest
    static void testSubmitBackfill_PreT5QuoteGetsLinesAtInvoiceTime() {
        // P4 [L] server half: quotes created while the snapshot flag was OFF
        // (pre-T5 population) must carry line items by the time the summary
        // submit creates the invoice. backfillIfMissing() recomputes the
        // deterministic engine result from the stored context and writes the
        // line set; a second call is a no-op.
        setFlags(true, false); // engine on, snapshot off (pre-T5 save)
        Ctx c = build('A8', 13, true, false, false); // base + premium
        Application_Package__c pkg = insertEnginePricedPackage(c); // no lines yet

        System.assertEquals(0, lines(pkg.Id).size(), 'pre-T5 quote has no lines');

        setFlags(true, true); // T5 on at submit time
        Test.startTest();
        Boolean backfilled = ApplicationSnapshotService.backfillIfMissing(pkg);
        Boolean second = ApplicationSnapshotService.backfillIfMissing(pkg);
        Test.stopTest();

        System.assertEquals(true, backfilled, 'backfill writes lines for engine-priced pkg');
        System.assertEquals(true, second, 'second call no-ops (returns true, still consistent)');
        List<Application_Package_Line_Item__c> rows = lines(pkg.Id);
        System.assertEquals(3, rows.size(), 'base + premium + tax after backfill');
        Decimal sum = 0;
        for (Application_Package_Line_Item__c r : rows) sum = PricingEngineService.money(sum + r.Amount__c);
        System.assertEquals(1580.87, sum, 'backfilled line set sums to engine with-tax (1100+299 + 13%)');
    }

    @isTest
    static void testSubmitBackfill_LegacyAndFlagOffSkipped() {
        setFlags(true, true);
        Ctx c = build('A9', 13, false, false, false);
        Application_Package__c pkg = insertEnginePricedPackage(c);
        // Legacy record (marker cleared in memory view).
        Application_Package__c legacyView = new Application_Package__c(Id = pkg.Id);

        Test.startTest();
        Boolean legacy = ApplicationSnapshotService.backfillIfMissing(legacyView);
        setFlags(true, false);
        Boolean flagOff = ApplicationSnapshotService.backfillIfMissing(pkg);
        Test.stopTest();

        System.assertEquals(false, legacy, 'legacy (non-engine-priced) never backfills');
        System.assertEquals(false, flagOff, 'flag-off org state never backfills');
    }
}