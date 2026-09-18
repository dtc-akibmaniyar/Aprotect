/**
 * DealerPortalMoreProductsEngineParityTest
 *
 * P4 [L] more-products selection-surface payload-parity evidence
 * (change-implementation plan §11 P4 [L], §10.1 rule 1, §10.4/§13.5 More
 * Products rows; decision 2026-09-06 option (b): source-level + Apex
 * payload-parity evidence is the accepted regression standard for the LWC
 * cutover).
 *
 * VERIFIED UNIT SHAPE (like the vehicle and GAP units — documented, not
 * papered over): the plan's "more-products" viewer item targets the same
 * LWC bundle as the T&R host unit (lwc/dealerPortalMoreProducts — the
 * portal's data-tab="moreProducts" "Tire & Rim" tab), because that bundle
 * hosts BOTH the T&R plan-selection flow and the "More Products" selection
 * modal + option/add-on surfaces the §10.4 "More Products" row covers.
 * The T&R host unit (C1-TRb, tag p4-c1-tr) already cut over every LIVE
 * engine-money render on that bundle: the Apex gate read
 * (isTireRimEngineViewerActive) on every existing-package load, the
 * summary-card + price-box re-stamp from the stored engine totals
 * (contractPremiumPriceWithoutTax / contractPremiumPrice), and the
 * Engine-Priced Breakdown block (showStoredEngineLines). Source-level
 * verification this run found NO additional live engine-priced money
 * surface left to gate or re-stamp:
 *   1. The "More Products Coverage Details" modal (showMoreProductsModal)
 *      is dead UI — no code path in the bundle ever sets it true; its only
 *      money display ({formattedPrice}) is already engine-fed through the
 *      T&R re-stamp (price / _retailPriceDisplay).
 *   2. Option/add-on money has no live client display in this bundle: the
 *      "Optional Benefits" rows of the Dealer Cost modal are fed from
 *      selectedAdditionalOptions, which the bundle never populates, and the
 *      addOnsPrice/addOnsMarkup/addOnsRetailPrice payload keys are read by
 *      no LWC in the repo. Diesel Components exists only as a catalogue
 *      value (Package_Add_On__c.Add_On_Type__c) — nothing is hard-coded, so
 *      the plan's "shown from catalogue (not hard-coded)" condition already
 *      holds.
 *   3. The Dealer Cost Summary modal (showPriceBreakdownModal — the only
 *      other live modal that shows money on this bundle) performs NO client
 *      recalc: it reads the stored payload keys directly
 *      (dealerPackagePrice / taxPercentage / taxAmount /
 *      contractPremiumPrice). Under the engine gate the latter two ARE the
 *      engine line sums (attach re-wire), the former two stay stored
 *      passthrough — its numbers already "render from payload".
 * A controller gate (isMoreProductsEngineViewerActive) or LWC re-stamp
 * branches would therefore be dead code with no data source (violating
 * §10.1 rule 1's spirit), so — exactly like the vehicle and GAP units — no
 * controller or LWC change was made; this unit ships its parity evidence.
 *
 * What this suite proves (the payload surfaces the More Products selection
 * modal / option-add-on displays read, on the shared active-package read
 * DealerPortalController.getActiveApplicationPackageByRecordType with
 * recordType = 'Tire_Rim_Protection_Plan', the read that feeds the whole
 * bundle):
 *   - An engine-priced T&R package whose stored row ALSO carries legacy
 *     add-on (option) money — the mix this bundle's option/add-on surfaces
 *     would display, which the T&R host suite's fixtures never set — reads
 *     byte-identical on every payload key EXCEPT the three engine-rebuilt
 *     money keys across flag states; the add-on keys
 *     (addOnsPrice/addOnsMarkup/addOnsRetailPrice = 200/50/250) and the
 *     dealer-cost keys (dealerPackagePrice/dealerMarkup/dealerPackageRetailPrice/
 *     taxPercentage/deductible/dealerPriceOverride) never leak or change
 *     when the engine snapshot attaches (base/premium/override/fee mixes).
 *   - The engine line set never contains add-on money (no double count):
 *     line sums = the engine quote exactly, and the stored formula totals
 *     (which DO include Add_Ons_Price + Add_Ons_Markup — verified formula
 *     Contract_Premium_Price_Without_Tax__c = override ?: DPP + markup +
 *     addOns + premium fee) differ from the engine payload by exactly the
 *     add-on retail + its tax @13% (250 + 32.50 = 282.50) — the same class
 *     of pinned stored=displayed delta the fee-line tests pin, here
 *     documenting the deferred-APO boundary: engine quotes from this portal
 *     never carry add-ons, so their persisted line set cannot include
 *     add-on money until the P4 [F] APO retirement folds add-ons into line
 *     items.
 *   - Dealer price override wholesale-replaces the price in BOTH states:
 *     the override branch of the stored formulas excludes add-ons, so with
 *     an override the engine payload and the legacy stored build are equal
 *     on EVERY key including the money keys (999/129.87/1128.87 @13%).
 *   - Flag-off reads never attach engine line items, engine-priced
 *     packages without a line set yet fall back to the legacy build (both
 *     with add-on money present), and the gates the bundle reads through
 *     Apex are false with zero Aprotect_Portal_Settings rows and with the
 *     engine flag alone — true only when Line_Item_Snapshot_Enabled__c is
 *     on — so no viewer code can execute while the flags are off.
 *
 * TEST CONTEXT FACT (same as DealerPortalTireRimEngineParityTest):
 * inserting a NON-engine-priced Application_Package runs the legacy
 * create-time flow, which cannot execute in the test user context. Every
 * insert here mirrors production: the engine stamps the record
 * (Priced_By_Engine__c = true) BEFORE the DML, so the flow terminates at
 * its engine guard. Add_Ons_* stored fields are set between engine pricing
 * and the insert (the engine quote carries no add-ons; the fields mirror a
 * legacy add-on-carrying row).
 *
 * ORG QUIRK respected: Package__c percent-config is never read (engine
 * quotes use the handler DEFAULT constants — the ×100 stored-rate anomaly
 * is a deferred item; do not resolve dp-link config in these tests).
 */
@isTest
private class DealerPortalMoreProductsEngineParityTest {

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
        Tax__c tax = taxRegion('MP' + tag, rate);
        Account d = dealer('D' + tag, tax);
        Make__c mk = make('MK' + tag);
        Model__c mo = model(mk, 'MD' + tag);
        Vehicle__c v = vehicle('V' + tag, mk, mo,
            diesel ? 'Diesel' : 'Gas',
            commercial ? 'Commercial/Business Use' : 'Personal Use');

        Package_Group__c grp = new Package_Group__c(Name = 'GRP' + tag, Active__c = true);
        insert grp;
        Package__c pkg = new Package__c(Name = 'PKG' + tag, Package_Group__c = grp.Id,
            RecordTypeId = rt('Package__c', 'Tire_Rim_Protection_Plan'), Is_Active__c = true);
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
            Package__c = pkg.Id, RecordTypeId = rt('Dealer_Package__c', 'Tire_Rim_Protection_Plan'));
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

    /**
     * Engine-stamp + stored legacy add-on money + INSERT (flow guard: marker
     * pre-DML), then snapshot. The add-on fields (Add_Ons_Price__c 200 +
     * Add_Ons_Markup__c 50 -> Add_Ons_Retail_Price__c 250 by formula) mirror
     * a legacy APO-carrying row: they are set between engine pricing and the
     * insert because this portal's engine quotes never carry add-ons (the
     * bundle has no live add-on selector) — exactly the deferred-APO state
     * this suite pins.
     */
    private static Application_Package__c insertEnginePricedPackageWithAddOns(Ctx c, Decimal overrideAmt) {
        Application_Package__c pkg = new Application_Package__c(
            Name = 'APK' + c.v.Name,
            Application__c = c.app.Id,
            Dealer__c = c.dealer.Id,
            Dealer_Package__c = c.dealerPackageId,
            Dealer_Package_Term__c = c.dt.Id,
            Package_Term__c = c.masterTermId,
            RecordTypeId = rt('Application_Package__c', 'Tire_Rim_Protection_Plan'),
            Active__c = true
        );
        PricingEngineService.QuoteRequest req = requestFor(c, pkg, overrideAmt);
        PricingEngineService.QuoteResult res = PricingEngineService.applyEnginePricing(pkg, req);
        System.assert(res.success, 'engine pricing expected to succeed: ' + res.errors);
        pkg.Add_Ons_Price__c = 200.00;
        pkg.Add_Ons_Markup__c = 50.00;
        Database.insert(pkg, System.AccessLevel.SYSTEM_MODE);
        Boolean written = ApplicationSnapshotService.writeSnapshot(pkg.Id,
            PricingEngineService.applyEnginePricing(pkg, requestFor(c, pkg, overrideAmt)));
        System.assertEquals(true, written, 'snapshot must be written for the parity fixture');
        return pkg;
    }

    /** Engine-priced package with NO snapshot (snapshot flag off at write). */
    private static Application_Package__c insertEnginePricedPackageNoSnapshot(Ctx c, Decimal overrideAmt) {
        Application_Package__c pkg = new Application_Package__c(
            Name = 'APK' + c.v.Name,
            Application__c = c.app.Id,
            Dealer__c = c.dealer.Id,
            Dealer_Package__c = c.dealerPackageId,
            Dealer_Package_Term__c = c.dt.Id,
            Package_Term__c = c.masterTermId,
            RecordTypeId = rt('Application_Package__c', 'Tire_Rim_Protection_Plan'),
            Active__c = true
        );
        PricingEngineService.applyEnginePricing(pkg, requestFor(c, pkg, overrideAmt));
        pkg.Add_Ons_Price__c = 200.00;
        pkg.Add_Ons_Markup__c = 50.00;
        Database.insert(pkg, System.AccessLevel.SYSTEM_MODE);
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
    // More Products / selection-modal payload reads (the shared active-package
    // read the whole dealerPortalMoreProducts bundle uses — T&R host restore,
    // More Products selection-modal display, Dealer Cost modal, price box)
    // ------------------------------------------------------------------

    /** Active T&R package payload via the bundle's read path. */
    private static Map<String, Object> readActivePackagePayload(Id appId) {
        DealerPortalController.ApplicationPackageResponse response =
            DealerPortalController.getActiveApplicationPackageByRecordType(appId, 'Tire_Rim_Protection_Plan');
        System.assert(response != null && response.success, 'active-package read expected to succeed: '
            + (response == null ? 'null' : response.message));
        System.assert(response.data != null, 'active package data expected');
        return response.data;
    }

    /**
     * Every payload key the selection-modal / option-add-on / dealer-cost
     * displays read must stay byte-identical ON vs OFF. The ONLY keys that
     * may differ are the three the engine snapshot rebuilds from the stored
     * lines (contractPremiumPriceWithoutTax / taxAmount /
     * contractPremiumPrice) plus the engine line attachments — everything
     * else, including the add-on money keys (addOns*) and the dealer-cost
     * keys (dealerPackagePrice / dealerMarkup / dealerPackageRetailPrice /
     * taxPercentage / deductible / dealerPriceOverride), must not move.
     */
    private static void assertSelectionSurfaceKeyParity(Map<String, Object> enginePayload,
                                                         Map<String, Object> legacyPayload,
                                                         String ctx) {
        Set<String> skip = new Set<String>{
            'contractPremiumPriceWithoutTax', 'taxAmount', 'contractPremiumPrice',
            'lineItems', 'hasEngineLineItems'
        };
        Set<String> keys = new Set<String>();
        keys.addAll(enginePayload.keySet());
        keys.addAll(legacyPayload.keySet());
        for (String k : keys) {
            if (skip.contains(k)) continue;
            System.assertEquals(legacyPayload.get(k), enginePayload.get(k),
                ctx + ': key must stay byte-identical across flag states: ' + k);
        }
    }

    private static void assertStoredAddOnMoneyPassthrough(Map<String, Object> payload, String ctx) {
        System.assertEquals(200.00, payload.get('addOnsPrice'), ctx + ': addOnsPrice stored passthrough');
        System.assertEquals(50.00, payload.get('addOnsMarkup'), ctx + ': addOnsMarkup stored passthrough');
        System.assertEquals(250.00, payload.get('addOnsRetailPrice'), ctx + ': addOnsRetailPrice formula passthrough');
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
    }

    // ------------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------------

    @isTest
    static void testBaseOnly_WithStoredAddOns_SelectionSurfaceParity() {
        // Engine-priced T&R package whose stored row ALSO carries legacy
        // add-on money (Add_Ons_Price 200 + Add_Ons_Markup 50 -> retail 250).
        // The stored formula totals include the add-on money (verified
        // formula: DPP + markup + addOns + premium fee); the engine line set
        // is the engine quote and never contains add-on money. The More
        // Products selection surfaces therefore read: legacy stored build
        // (flags off) = 1350/175.50/1525.50 @13% (add-on money visible in
        // the stored totals), engine payload (gate on) = the engine quote
        // rebuilt from lines 1100/143/1243, every OTHER key byte-identical —
        // add-on/dealer-cost keys are pure stored passthrough in both
        // states.
        setFlags(true, true);
        Ctx c = build('MP1', 13, false, false, false);
        Application_Package__c pkg = insertEnginePricedPackageWithAddOns(c, null);

        setFlags(true, false);
        Map<String, Object> legacyPayload = readActivePackagePayload(c.app.Id);
        setFlags(true, true);
        Map<String, Object> enginePayload = readActivePackagePayload(c.app.Id);

        assertSelectionSurfaceKeyParity(enginePayload, legacyPayload, 'base+add-ons');
        assertStoredAddOnMoneyPassthrough(enginePayload, 'engine payload');
        assertStoredAddOnMoneyPassthrough(legacyPayload, 'legacy payload');
        // Legacy stored build: 1000 + 100 + (200 + 50) = 1350 -> tax 175.50 -> 1525.50.
        System.assertEquals(1350.00, legacyPayload.get('contractPremiumPriceWithoutTax'));
        System.assertEquals(175.50, legacyPayload.get('taxAmount'));
        System.assertEquals(1525.50, legacyPayload.get('contractPremiumPrice'));
        // Engine payload from lines: 1100 -> 143 -> 1243.
        System.assertEquals(1100.00, enginePayload.get('contractPremiumPriceWithoutTax'));
        System.assertEquals(143.00, enginePayload.get('taxAmount'));
        System.assertEquals(1243.00, enginePayload.get('contractPremiumPrice'));
        // The stored=displayed delta is exactly the add-on retail + its tax
        // (250 + 32.50 @13% = 282.50) — pinned so it cannot drift.
        System.assertEquals((Decimal) legacyPayload.get('contractPremiumPrice') - 282.50,
            enginePayload.get('contractPremiumPrice'), 'add-on retail + tax delta on with-tax total');
        System.assertEquals((Decimal) legacyPayload.get('contractPremiumPriceWithoutTax') - 250.00,
            enginePayload.get('contractPremiumPriceWithoutTax'), 'add-on retail delta pre-tax');

        assertLineSet(enginePayload, new List<Decimal>{ 1100.00, 143.00 }, 'base+add-ons ON payload');
        assertNoEngineLines(legacyPayload, 'base+add-ons OFF payload');
    }

    @isTest
    static void testPremiumFee_WithStoredAddOns_SelectionSurfaceParity() {
        // Premium fee is fully expressible in the stored formula fields
        // (Premium_Model_Fee__c carrier). Stored build = 1000+100+250+299 =
        // 1649 -> 214.37 -> 1863.37; engine payload from lines = 1399 ->
        // 181.87 -> 1580.87; delta stays exactly the add-on retail + tax.
        setFlags(true, true);
        Ctx c = build('MP2', 13, true, false, false); // base + premium 299
        Application_Package__c pkg = insertEnginePricedPackageWithAddOns(c, null);

        setFlags(true, false);
        Map<String, Object> legacyPayload = readActivePackagePayload(c.app.Id);
        setFlags(true, true);
        Map<String, Object> enginePayload = readActivePackagePayload(c.app.Id);

        assertSelectionSurfaceKeyParity(enginePayload, legacyPayload, 'premium+add-ons');
        assertStoredAddOnMoneyPassthrough(enginePayload, 'engine payload');
        assertStoredAddOnMoneyPassthrough(legacyPayload, 'legacy payload');
        System.assertEquals(1649.00, legacyPayload.get('contractPremiumPriceWithoutTax'));
        System.assertEquals(214.37, legacyPayload.get('taxAmount'));
        System.assertEquals(1863.37, legacyPayload.get('contractPremiumPrice'));
        System.assertEquals(1399.00, enginePayload.get('contractPremiumPriceWithoutTax'));
        System.assertEquals(181.87, enginePayload.get('taxAmount'));
        System.assertEquals(1580.87, enginePayload.get('contractPremiumPrice'));
        System.assertEquals((Decimal) legacyPayload.get('contractPremiumPrice') - 282.50,
            enginePayload.get('contractPremiumPrice'), 'add-on retail + tax delta on with-tax total');

        assertLineSet(enginePayload, new List<Decimal>{ 1100.00, 299.00, 181.87 }, 'premium+add-ons ON payload');
        assertNoEngineLines(legacyPayload, 'premium+add-ons OFF payload');
    }

    @isTest
    static void testDealerOverride_WithStoredAddOns_FullMoneyKeyParity() {
        // A dealer price override wholesale-replaces the price in BOTH
        // states: the override branch of the stored formulas excludes the
        // add-on money (verified formula: IF(override>0, override, ...)), so
        // engine payload == legacy stored build on EVERY key including the
        // money keys — the override display cannot drift when the snapshot
        // attaches, and the stored add-on money never leaks into it.
        setFlags(true, true);
        Ctx c = build('MP3', 13, true, true, false); // fees exist but override suppresses them
        Application_Package__c pkg = insertEnginePricedPackageWithAddOns(c, 999.00);

        setFlags(true, false);
        Map<String, Object> legacyPayload = readActivePackagePayload(c.app.Id);
        setFlags(true, true);
        Map<String, Object> enginePayload = readActivePackagePayload(c.app.Id);

        assertSelectionSurfaceKeyParity(enginePayload, legacyPayload, 'override+add-ons');
        assertStoredAddOnMoneyPassthrough(enginePayload, 'engine payload');
        assertStoredAddOnMoneyPassthrough(legacyPayload, 'legacy payload');
        // Override replaces the whole price; tax = 999 * 13% = 129.87.
        System.assertEquals(999.00, legacyPayload.get('contractPremiumPriceWithoutTax'));
        System.assertEquals(999.00, enginePayload.get('contractPremiumPriceWithoutTax'));
        System.assertEquals(129.87, legacyPayload.get('taxAmount'));
        System.assertEquals(129.87, enginePayload.get('taxAmount'));
        System.assertEquals(1128.87, legacyPayload.get('contractPremiumPrice'));
        System.assertEquals(1128.87, enginePayload.get('contractPremiumPrice'));
        System.assertEquals(999.00, enginePayload.get('dealerPriceOverride'));

        assertLineSet(enginePayload, new List<Decimal>{ 999.00, 129.87 }, 'override+add-ons ON payload');
        assertNoEngineLines(legacyPayload, 'override+add-ons OFF payload');
    }

    @isTest
    static void testMixedFees_WithStoredAddOns_EnginePayloadEqualsStoredPlusFeesMinusAddOns() {
        // Diesel/commercial surcharges have NO stored carrier on
        // Application_Package__c (verified org fact): the stored formula
        // totals express base + premium + add-ons only. With add-on money
        // stored AND fee lines engine-priced, the legacy build = base +
        // premium + add-ons (1649 -> 214.37 -> 1863.37 @13%) while the
        // engine payload = base + premium + diesel + commercial from lines
        // (1949 -> 253.37 -> 2202.37). The delta = fees (550) minus the
        // add-on retail (250) = 300 pre-tax, +39 tax, +339 total — pinned so
        // the deferred-APO boundary (engine quotes never carry add-ons) and
        // the fee stored=displayed fix cannot drift silently.
        setFlags(true, true);
        Ctx c = build('MP4', 13, true, true, true); // premium 299 + diesel 150 + commercial 400
        Application_Package__c pkg = insertEnginePricedPackageWithAddOns(c, null);

        setFlags(true, false);
        Map<String, Object> legacyPayload = readActivePackagePayload(c.app.Id);
        setFlags(true, true);
        Map<String, Object> enginePayload = readActivePackagePayload(c.app.Id);

        assertSelectionSurfaceKeyParity(enginePayload, legacyPayload, 'mixed fees+add-ons');
        assertStoredAddOnMoneyPassthrough(enginePayload, 'engine payload');
        assertStoredAddOnMoneyPassthrough(legacyPayload, 'legacy payload');
        // Legacy stored build: 1000 + 100 + 250 + 299 = 1649 -> 214.37 -> 1863.37.
        System.assertEquals(1649.00, legacyPayload.get('contractPremiumPriceWithoutTax'));
        System.assertEquals(214.37, legacyPayload.get('taxAmount'));
        System.assertEquals(1863.37, legacyPayload.get('contractPremiumPrice'));
        // Engine payload from lines: 1100 + 299 + 150 + 400 = 1949 -> 253.37 -> 2202.37.
        System.assertEquals(1949.00, enginePayload.get('contractPremiumPriceWithoutTax'));
        System.assertEquals(253.37, enginePayload.get('taxAmount'));
        System.assertEquals(2202.37, enginePayload.get('contractPremiumPrice'));
        // Delta = fee lines (550) minus add-on retail (250) = 300 pre-tax; tax delta 39; total 339.
        System.assertEquals((Decimal) legacyPayload.get('contractPremiumPriceWithoutTax') + 300.00,
            enginePayload.get('contractPremiumPriceWithoutTax'), 'fees-minus-add-ons delta pre-tax');
        System.assertEquals((Decimal) legacyPayload.get('contractPremiumPrice') + 339.00,
            enginePayload.get('contractPremiumPrice'), 'fees-minus-add-ons delta on with-tax total');
        // All other rendered keys (incl. dealer-cost + add-on keys) stay in parity.
        System.assertEquals(legacyPayload.get('dealerPackagePrice'), enginePayload.get('dealerPackagePrice'));
        System.assertEquals(legacyPayload.get('dealerMarkup'), enginePayload.get('dealerMarkup'));
        System.assertEquals(legacyPayload.get('dealerPackageRetailPrice'), enginePayload.get('dealerPackageRetailPrice'));
        System.assertEquals(legacyPayload.get('taxPercentage'), enginePayload.get('taxPercentage'));
        System.assertEquals(legacyPayload.get('dealerPriceOverride'), enginePayload.get('dealerPriceOverride'));

        assertLineSet(enginePayload, new List<Decimal>{ 1100.00, 299.00, 150.00, 400.00, 253.37 }, 'mixed fees+add-ons ON payload');
        assertNoEngineLines(legacyPayload, 'mixed fees+add-ons OFF payload');
    }

    @isTest
    static void testFlagOffRead_WithStoredAddOns_NeverReturnsEngineLines() {
        // The same package read twice: with lines stored (gate was on at
        // snapshot time) but the READ happens with the gate off — the payload
        // must be the legacy stored-field build with no engine fields,
        // byte-identical to the pre-cutover response shape, add-on money
        // intact.
        setFlags(true, true);
        Ctx c = build('MP5', 13, true, true, false); // premium + diesel
        Application_Package__c pkg = insertEnginePricedPackageWithAddOns(c, null);

        setFlags(true, false);
        Map<String, Object> offPayload = readActivePackagePayload(c.app.Id);

        assertNoEngineLines(offPayload, 'flag-off read');
        assertStoredAddOnMoneyPassthrough(offPayload, 'flag-off read');
        // Legacy stored build: 1000+100+250+299 = 1649 -> 214.37 -> 1863.37.
        System.assertEquals(1649.00, offPayload.get('contractPremiumPriceWithoutTax'));
        System.assertEquals(214.37, offPayload.get('taxAmount'));
        System.assertEquals(1863.37, offPayload.get('contractPremiumPrice'));
    }

    @isTest
    static void testEnginePricedNoLinesYet_WithStoredAddOns_FallsBackToLegacyBuild() {
        // Pre-T5 quote population: package priced by the engine while the
        // snapshot flag was off (no line set yet), carrying stored add-on
        // money. With the gate ON at read time the payload must fall back to
        // the legacy stored-field build — no lines, no engine fields — and
        // must be byte-identical to the gate-off read.
        setFlags(true, false); // engine on, snapshot off => engine insert, no lines
        Ctx c = build('MP6', 13, true, false, false);
        Application_Package__c pkg = insertEnginePricedPackageNoSnapshot(c, null);

        setFlags(true, true); // gate on at read time
        Map<String, Object> onRead = readActivePackagePayload(c.app.Id);
        setFlags(true, false);
        Map<String, Object> offRead = readActivePackagePayload(c.app.Id);

        assertSelectionSurfaceKeyParity(onRead, offRead, 'no-lines-yet');
        assertNoEngineLines(onRead, 'no-lines-yet ON read');
        assertStoredAddOnMoneyPassthrough(onRead, 'no-lines-yet ON read');
        assertStoredAddOnMoneyPassthrough(offRead, 'no-lines-yet OFF read');
        // Legacy stored build still authoritative: 1000+100+250+299 = 1649.
        System.assertEquals(1649.00, onRead.get('contractPremiumPriceWithoutTax'));
        System.assertEquals(1863.37, onRead.get('contractPremiumPrice'));
        System.assertEquals(onRead.get('contractPremiumPriceWithoutTax'), offRead.get('contractPremiumPriceWithoutTax'));
        System.assertEquals(onRead.get('contractPremiumPrice'), offRead.get('contractPremiumPrice'));
    }

    @isTest
    static void testModalAndHostGates_ReadApexFlags() {
        // The gates the dealerPortalMoreProducts bundle reads through Apex
        // (isTireRimEngineViewerActive — the T&R host cutover gate this
        // bundle's viewer code runs under) must be false with zero
        // Aprotect_Portal_Settings rows and with the engine flag alone, true
        // only when Line_Item_Snapshot_Enabled__c is on. No selection-modal
        // or option/add-on viewer code can therefore execute while the flags
        // are off.
        delete [SELECT Id FROM Aprotect_Portal_Settings__c];
        System.assertEquals(false, DealerPortalController.isTireRimEngineViewerActive(),
            'gate must be false with zero Aprotect_Portal_Settings rows');
        System.assertEquals(false, DealerPortalController.isWarrantyEngineViewerActive(),
            'warranty gate must also be false with zero Aprotect_Portal_Settings rows');

        setFlags(true, false);
        System.assertEquals(false, DealerPortalController.isTireRimEngineViewerActive(),
            'gate must be false when only the pricing-engine flag is on');

        setFlags(true, true);
        System.assertEquals(true, DealerPortalController.isTireRimEngineViewerActive(),
            'gate must be true when Line_Item_Snapshot_Enabled__c is on');
        System.assertEquals(true, DealerPortalController.isWarrantyEngineViewerActive(),
            'warranty gate must be true when Line_Item_Snapshot_Enabled__c is on');

        // Leave the org in the flag-off baseline state (zero rows).
        delete [SELECT Id FROM Aprotect_Portal_Settings__c];
    }
}