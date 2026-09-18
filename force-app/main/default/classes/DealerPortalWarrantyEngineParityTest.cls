/**
 * DealerPortalWarrantyEngineParityTest
 *
 * P4 [L] warranty-tab viewer cutover — Apex payload-parity evidence
 * (change-implementation plan §11 P4 [L], §10.1 rule 1, §10.4/§13.5 warranty
 * rows; decision 2026-09-06 option (b): source-level + Apex payload-parity
 * evidence is the accepted regression standard for the LWC cutover).
 *
 * What it proves (the payload the warranty tab renders — the active
 * Application_Package read DealerPortalController.getActiveApplicationPackageByRecordType
 * feeds the tab's existing-quote restore, price box, DCS stored view and
 * override restore):
 *   - Engine-snapshot payload (T5 gate ON: contractPremium* money keys rebuilt
 *     from the persisted line items + lineItems attached) EQUALS the legacy
 *     payload (gate OFF: stored-field/formula build) for every fee mix the
 *     stored fields can express — base-only, base+premium fee, dealer price
 *     override — on the full key set the warranty tab reads. Legacy warranty
 *     display therefore cannot change when the viewer cutover flips on.
 *   - Fee lines with no stored carrier on Application_Package__c
 *     (diesel/commercial/powersports — verified org fact) reconcile at LINE
 *     level: the engine payload totals = legacy stored totals + exactly those
 *     fee lines (and their tax). That delta is the intended stored=displayed
 *     fix the line items make visible, not a regression.
 *   - Flag-off reads never attach engine line items (hasEngineLineItems /
 *     lineItems absent), engine-priced packages without a line set yet fall
 *     back to the legacy build, and the LWC gate
 *     (DealerPortalController.isWarrantyEngineViewerActive) is read through
 *     Apex and false with zero Aprotect_Portal_Settings rows — so the LWC
 *     cutover code cannot execute while the flags are off.
 *
 * TEST CONTEXT FACT (same as ApplicationSummaryEngineParityTest / snapshot
 * tests): inserting a NON-engine-priced Application_Package runs the legacy
 * create-time flow, which cannot execute in the test user context. Every
 * insert here mirrors production: the engine stamps the record
 * (Priced_By_Engine__c = true) BEFORE the DML, so the flow terminates at its
 * engine guard.
 *
 * ORG QUIRK respected: Package__c percent-config is never read (engine quotes
 * use the handler DEFAULT constants — the ×100 stored-rate anomaly is a
 * deferred item; do not resolve dp-link config in these tests).
 */
@isTest
private class DealerPortalWarrantyEngineParityTest {

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
        Tax__c tax = taxRegion('WPAR' + tag, rate);
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

    /** Engine-stamp + INSERT (flow guard: marker pre-DML), then snapshot. */
    private static Application_Package__c insertEnginePricedPackage(Ctx c, Decimal overrideAmt) {
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
        PricingEngineService.QuoteRequest req = requestFor(c, pkg, overrideAmt);
        PricingEngineService.QuoteResult res = PricingEngineService.applyEnginePricing(pkg, req);
        System.assert(res.success, 'engine pricing expected to succeed: ' + res.errors);
        Database.insert(pkg, System.AccessLevel.SYSTEM_MODE);
        Boolean written = ApplicationSnapshotService.writeSnapshot(pkg.Id,
            PricingEngineService.applyEnginePricing(pkg, requestFor(c, pkg, overrideAmt)));
        System.assertEquals(true, written, 'snapshot must be written for the parity fixture');
        return pkg;
    }

    private static PricingEngineService.QuoteRequest requestFor(Ctx c, Application_Package__c pkg, Decimal overrideAmt) {
        PricingEngineService.QuoteRequest req = new PricingEngineService.QuoteRequest();
        req.dealerId = c.dealer.Id;
        req.vehicleId = c.v.Id;
        req.dealerPackageId = c.dealerPackageId;
        req.dealerTermId = c.dt.Id;
        req.applicationPackageId = pkg.Id;
        req.asOfDate = Date.newInstance(2026, 9, 3);
        req.dealerPriceOverride = overrideAmt;
        return req;
    }

    // ------------------------------------------------------------------
    // Warranty payload reads (the path the warranty tab renders:
    // getActiveApplicationPackageByRecordType -> data map)
    // ------------------------------------------------------------------

    /** Active ELW package payload via the warranty tab's read path. */
    private static Map<String, Object> readActivePackagePayload(Id appId) {
        DealerPortalController.ApplicationPackageResponse response =
            DealerPortalController.getActiveApplicationPackageByRecordType(appId, 'Extended_Limited_Warranty');
        System.assert(response != null && response.success, 'active-package read expected to succeed: '
            + (response == null ? 'null' : response.message));
        System.assert(response.data != null, 'active package data expected');
        return response.data;
    }

    /** Every key the warranty tab reads from the payload — ON vs OFF. */
    private static void assertRenderedKeyParity(Map<String, Object> enginePayload,
                                                 Map<String, Object> legacyPayload) {
        System.assertEquals(legacyPayload.get('Id'), enginePayload.get('Id'), 'Id');
        System.assertEquals(legacyPayload.get('dealerPackageId'), enginePayload.get('dealerPackageId'), 'dealerPackageId');
        System.assertEquals(legacyPayload.get('selectedTermId'), enginePayload.get('selectedTermId'), 'selectedTermId');
        System.assertEquals(legacyPayload.get('selectedTermName'), enginePayload.get('selectedTermName'), 'selectedTermName');
        System.assertEquals(legacyPayload.get('dealerPackagePrice'), enginePayload.get('dealerPackagePrice'), 'dealerPackagePrice');
        System.assertEquals(legacyPayload.get('dealerMarkup'), enginePayload.get('dealerMarkup'), 'dealerMarkup');
        System.assertEquals(legacyPayload.get('deductible'), enginePayload.get('deductible'), 'deductible');
        System.assertEquals(legacyPayload.get('dealerPackageRetailPrice'), enginePayload.get('dealerPackageRetailPrice'),
            'dealerPackageRetailPrice');
        System.assertEquals(legacyPayload.get('addOnsPrice'), enginePayload.get('addOnsPrice'), 'addOnsPrice');
        System.assertEquals(legacyPayload.get('addOnsMarkup'), enginePayload.get('addOnsMarkup'), 'addOnsMarkup');
        System.assertEquals(legacyPayload.get('addOnsRetailPrice'), enginePayload.get('addOnsRetailPrice'), 'addOnsRetailPrice');
        System.assertEquals(legacyPayload.get('contractPremiumPriceWithoutTax'), enginePayload.get('contractPremiumPriceWithoutTax'),
            'contractPremiumPriceWithoutTax (stored no-tax total = non-Tax line sum)');
        System.assertEquals(legacyPayload.get('taxPercentage'), enginePayload.get('taxPercentage'), 'taxPercentage');
        System.assertEquals(legacyPayload.get('taxAmount'), enginePayload.get('taxAmount'),
            'taxAmount (stored Tax_Amount = Tax-line sum)');
        System.assertEquals(legacyPayload.get('contractPremiumPrice'), enginePayload.get('contractPremiumPrice'),
            'contractPremiumPrice (stored with-tax total = all-line sum)');
        System.assertEquals(legacyPayload.get('dealerPriceOverride'), enginePayload.get('dealerPriceOverride'), 'dealerPriceOverride');
        System.assertEquals(legacyPayload.get('expiryTerm'), enginePayload.get('expiryTerm'), 'expiryTerm');
        System.assertEquals(legacyPayload.get('odometerEnd'), enginePayload.get('odometerEnd'), 'odometerEnd');
        System.assertEquals(legacyPayload.get('odometerEndUnit'), enginePayload.get('odometerEndUnit'), 'odometerEndUnit');
        System.assertEquals(legacyPayload.get('packageName'), enginePayload.get('packageName'), 'packageName');
        System.assertEquals(legacyPayload.get('isActive'), enginePayload.get('isActive'), 'isActive');
    }

    private static void assertNoEngineLines(Map<String, Object> payload, String ctx) {
        System.assertEquals(null, payload.get('lineItems'), ctx + ': lineItems must be absent on legacy payload');
        System.assertEquals(true, payload.get('hasEngineLineItems') != true,
            ctx + ': hasEngineLineItems must not be set');
    }

    private static void assertLineSet(Map<String, Object> payload, List<Decimal> expectedAmounts, String ctx) {
        System.assertEquals(true, payload.get('hasEngineLineItems') == true, ctx + ': hasEngineLineItems flag');
        List<DealerPortalController.WarrantyLineItemDTO> lines =
            (List<DealerPortalController.WarrantyLineItemDTO>) payload.get('lineItems');
        System.assertEquals(expectedAmounts.size(), lines.size(), ctx + ': line count');
        for (Integer i = 0; i < expectedAmounts.size(); i++) {
            System.assertEquals(expectedAmounts[i], lines[i].amount, ctx + ': line ' + i + ' amount');
            System.assertNotEquals(null, lines[i].description, ctx + ': line ' + i + ' description');
            System.assertNotEquals(null, lines[i].formattedAmount, ctx + ': line ' + i + ' formatted');
            System.assertNotEquals(null, lines[i].key, ctx + ': line ' + i + ' key');
        }
        DealerPortalController.WarrantyLineItemDTO last = lines[lines.size() - 1];
        System.assertEquals('Tax', last.lineType, ctx + ': tax line must be last');
        // Self-consistency: payload money keys == the attached line sums.
        Decimal noTax = 0;
        Decimal tax = 0;
        for (DealerPortalController.WarrantyLineItemDTO li : lines) {
            if (li.lineType == 'Tax') {
                tax += li.amount;
            } else {
                noTax += li.amount;
            }
        }
        System.assertEquals(payload.get('contractPremiumPriceWithoutTax'), noTax, ctx + ': no-tax key == non-Tax line sum');
        System.assertEquals(payload.get('taxAmount'), tax, ctx + ': taxAmount key == Tax line sum');
        System.assertEquals(payload.get('contractPremiumPrice'), noTax + tax, ctx + ': with-tax key == all-line sum');
    }

    // ------------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------------

    @isTest
    static void testBaseOnly_EngineSnapshotPayload_ParitiesWithLegacy() {
        setFlags(true, true);
        Ctx c = build('WB1', 13, false, false, false);
        Application_Package__c pkg = insertEnginePricedPackage(c, null);

        setFlags(true, false);
        Map<String, Object> legacyPayload = readActivePackagePayload(c.app.Id);
        setFlags(true, true);
        Map<String, Object> enginePayload = readActivePackagePayload(c.app.Id);

        assertRenderedKeyParity(enginePayload, legacyPayload);
        // Base-only quote: 1100 no-tax -> 143 tax -> 1243 with-tax (13%).
        System.assertEquals(1100.00, enginePayload.get('contractPremiumPriceWithoutTax'));
        System.assertEquals(143.00, enginePayload.get('taxAmount'));
        System.assertEquals(1243.00, enginePayload.get('contractPremiumPrice'));

        assertLineSet(enginePayload, new List<Decimal>{ 1100.00, 143.00 }, 'base-only ON payload');
        assertNoEngineLines(legacyPayload, 'base-only OFF payload');
    }

    @isTest
    static void testPremiumFee_EngineSnapshotPayload_ParitiesWithLegacy() {
        setFlags(true, true);
        Ctx c = build('WB2', 13, true, false, false); // base + premium 299
        Application_Package__c pkg = insertEnginePricedPackage(c, null);

        setFlags(true, false);
        Map<String, Object> legacyPayload = readActivePackagePayload(c.app.Id);
        setFlags(true, true);
        Map<String, Object> enginePayload = readActivePackagePayload(c.app.Id);

        assertRenderedKeyParity(enginePayload, legacyPayload);
        // Premium fee is fully expressible in the stored formula fields, so the
        // engine payload equals the legacy stored build to the cent:
        // 1399 * 1.13 = 1580.87.
        System.assertEquals(1399.00, enginePayload.get('contractPremiumPriceWithoutTax'));
        System.assertEquals(181.87, enginePayload.get('taxAmount'));
        System.assertEquals(1580.87, enginePayload.get('contractPremiumPrice'));

        assertLineSet(enginePayload, new List<Decimal>{ 1100.00, 299.00, 181.87 }, 'premium ON payload');
        assertNoEngineLines(legacyPayload, 'premium OFF payload');
    }

    @isTest
    static void testDealerOverride_EngineSnapshotPayload_ParitiesWithLegacy() {
        setFlags(true, true);
        Ctx c = build('WB3', 13, true, true, false); // fees exist but override suppresses them
        Application_Package__c pkg = insertEnginePricedPackage(c, 999.00);

        setFlags(true, false);
        Map<String, Object> legacyPayload = readActivePackagePayload(c.app.Id);
        setFlags(true, true);
        Map<String, Object> enginePayload = readActivePackagePayload(c.app.Id);

        assertRenderedKeyParity(enginePayload, legacyPayload);
        // Override replaces the whole price; tax = 999 * 13% = 129.87.
        System.assertEquals(999.00, enginePayload.get('contractPremiumPriceWithoutTax'));
        System.assertEquals(129.87, enginePayload.get('taxAmount'));
        System.assertEquals(1128.87, enginePayload.get('contractPremiumPrice'));
        System.assertEquals(999.00, enginePayload.get('dealerPriceOverride'));

        assertLineSet(enginePayload, new List<Decimal>{ 999.00, 129.87 }, 'override ON payload');
        assertNoEngineLines(legacyPayload, 'override OFF payload');
    }

    @isTest
    static void testMixedFees_EnginePayload_EqualsStoredPlusFeeLines() {
        // Diesel/commercial surcharges have NO stored carrier on
        // Application_Package__c (verified org fact): the stored formula
        // totals express base + premium only. The engine payload therefore
        // equals stored + exactly those fee lines (and their tax) — the
        // intended stored = displayed delta the snapshot render makes
        // visible, asserted here so the delta can never drift silently.
        setFlags(true, true);
        Ctx c = build('WB4', 13, true, true, true); // premium 299 + diesel 150 + commercial 400
        Application_Package__c pkg = insertEnginePricedPackage(c, null);

        setFlags(true, false);
        Map<String, Object> legacyPayload = readActivePackagePayload(c.app.Id);
        setFlags(true, true);
        Map<String, Object> enginePayload = readActivePackagePayload(c.app.Id);

        // Legacy stored build: 1000 + 100 + 0 + 299 = 1399 -> tax 181.87 -> 1580.87.
        System.assertEquals(1399.00, legacyPayload.get('contractPremiumPriceWithoutTax'));
        System.assertEquals(181.87, legacyPayload.get('taxAmount'));
        System.assertEquals(1580.87, legacyPayload.get('contractPremiumPrice'));
        // Engine payload from lines: 1100 + 299 + 150 + 400 = 1949 -> 253.37 -> 2202.37.
        System.assertEquals(1949.00, enginePayload.get('contractPremiumPriceWithoutTax'));
        System.assertEquals(253.37, enginePayload.get('taxAmount'));
        System.assertEquals(2202.37, enginePayload.get('contractPremiumPrice'));
        // The delta is exactly the two fees + their tax (13% of 550 = 71.50).
        System.assertEquals((Decimal) legacyPayload.get('contractPremiumPrice') + 621.50,
            enginePayload.get('contractPremiumPrice'), 'fee-line delta on with-tax total');
        System.assertEquals((Decimal) legacyPayload.get('contractPremiumPriceWithoutTax') + 550.00,
            enginePayload.get('contractPremiumPriceWithoutTax'), 'fee-line delta pre-tax');
        // All other rendered keys stay in parity.
        System.assertEquals(legacyPayload.get('dealerPackagePrice'), enginePayload.get('dealerPackagePrice'));
        System.assertEquals(legacyPayload.get('dealerPackageRetailPrice'), enginePayload.get('dealerPackageRetailPrice'));
        System.assertEquals(legacyPayload.get('taxPercentage'), enginePayload.get('taxPercentage'));
        System.assertEquals(legacyPayload.get('dealerPriceOverride'), enginePayload.get('dealerPriceOverride'));

        assertLineSet(enginePayload, new List<Decimal>{ 1100.00, 299.00, 150.00, 400.00, 253.37 }, 'mixed-fee ON payload');
        assertNoEngineLines(legacyPayload, 'mixed-fee OFF payload');
    }

    @isTest
    static void testEnginePricedNoLinesYet_FallsBackToLegacyBuild() {
        // Pre-T5 quote population: package priced by the engine while the
        // snapshot flag was off (no line set yet). With the gate ON at read
        // time the warranty payload must fall back to the legacy stored-field
        // build — no lines, no engine fields — not crash and not invent a
        // snapshot.
        setFlags(true, false); // engine on, snapshot off => engine insert, no lines
        Ctx c = build('WB5', 13, true, false, false);
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
        PricingEngineService.applyEnginePricing(pkg, requestFor(c, pkg, null));
        Database.insert(pkg, System.AccessLevel.SYSTEM_MODE);

        setFlags(true, true); // gate on at read time
        Map<String, Object> onRead = readActivePackagePayload(c.app.Id);
        setFlags(true, false);
        Map<String, Object> offRead = readActivePackagePayload(c.app.Id);

        assertRenderedKeyParity(onRead, offRead);
        assertNoEngineLines(onRead, 'no-lines-yet ON read');
        System.assertEquals(1399.00, onRead.get('contractPremiumPriceWithoutTax'), 'legacy stored build still authoritative');
        System.assertEquals(1580.87, onRead.get('contractPremiumPrice'));
    }

    @isTest
    static void testFlagOffRead_NeverReturnsEngineLines() {
        // The same package read twice: with lines stored (gate was on at
        // snapshot time) but the READ happens with the gate off — the payload
        // must be the legacy stored-field build with no engine fields,
        // byte-identical to the pre-cutover response shape.
        setFlags(true, true);
        Ctx c = build('WB6', 13, true, true, false); // premium + diesel
        Application_Package__c pkg = insertEnginePricedPackage(c, null);

        setFlags(true, false);
        Map<String, Object> offPayload = readActivePackagePayload(c.app.Id);

        assertNoEngineLines(offPayload, 'flag-off read');
        // Legacy stored build: 1000+100+299 = 1399 -> tax 181.87 -> 1580.87.
        System.assertEquals(1399.00, offPayload.get('contractPremiumPriceWithoutTax'));
        System.assertEquals(1580.87, offPayload.get('contractPremiumPrice'));
    }

    @isTest
    static void testViewerGate_ReadsApexFlags() {
        // Org default: no setting rows => gate false (LWC cutover inert).
        delete [SELECT Id FROM Aprotect_Portal_Settings__c];
        System.assertEquals(false, DealerPortalController.isWarrantyEngineViewerActive(),
            'gate must be false with zero Aprotect_Portal_Settings rows');

        // Engine on alone is NOT enough: the warranty viewer needs the stored
        // line set, which exists only under the T5 snapshot gate.
        setFlags(true, false);
        System.assertEquals(false, DealerPortalController.isWarrantyEngineViewerActive(),
            'gate must be false when only the pricing-engine flag is on');

        setFlags(true, true);
        System.assertEquals(true, DealerPortalController.isWarrantyEngineViewerActive(),
            'gate must be true when Line_Item_Snapshot_Enabled__c is on');
    }
}