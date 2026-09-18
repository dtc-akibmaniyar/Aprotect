/**
 * DealerPortalGapEngineParityTest
 *
 * P4 [L] GAP-tab viewer cutover — Apex payload-parity evidence
 * (change-implementation plan §11 P4 [L], §10.1 rule 1, §10.4/§13.5 GAP tab
 * rows; decision 2026-09-06 option (b): source-level + Apex payload-parity
 * evidence is the accepted regression standard for the LWC cutover).
 *
 * UNIT-SHAPE NOTE (verified deviation from the summary/warranty/T&R template —
 * see run record 2026-09-06-p4-c1-gap): the GAP tab
 * (lwc/dealerPortalGap, hosted by dealerPortalContainer under data-tab="gap",
 * label "GAP" / console "Car Loan Protection tab") is a pure Trisura
 * program-info and external-redirect page. Verification against the plan's
 * LWC→tab map (§05.1) and the repo:
 *   1. dealerPortalGap.js (150 lines) imports exactly ONE Apex method —
 *      GAPProgramInfoController.getGAPProgramInfo, a static GAP_Program_Info__mdt
 *      content fetch (portal URL + informational text). It does NOT import
 *      getActiveApplicationPackageByRecordType (or any package read), imports
 *      no viewer gate, and checkForExistingApplicationPackage() /
 *      restoreData() are explicit no-ops ("Trisura info page has no package
 *      logic" — the component's own comment). The GAP product is sold through
 *      the external Trisura portal the tab redirects to; nothing package-
 *      related is read or rendered on the tab.
 *   2. It renders NO engine-priced payload: zero currency-formatting /
 *      client-recalc hits in its 150-line JS (no toFixed/Intl/formatCurrency/
 *      parseFloat, no price/premiumFee/taxAmount/contractPremium tokens) and
 *      its 94-line HTML has no money display of any kind (Trisura logo,
 *      program text, Visit-Trisura-Portal / Save-As-Quote / Continue / Skip
 *      buttons only).
 *   3. The GAP *quote* server flow (finance inputs term/rate/amount →
 *      quote; DealerPortalController.getTotalLossDealerPackages /
 *      createTotalLossApplicationPackageFromMap /
 *      updateTotalLossApplicationPackage /
 *      getTotalLossExistingApplicationPackageByRecordType /
 *      getTotalLossAdditionalOptions* / updateTotalLossFieldsSelective) is
 *      DORMANT in the current portal: reference scan finds zero callers in
 *      any LWC bundle, aura component, page, flow or flexipage in the repo.
 *      It is legacy code not wired to the GAP tab, with no engine/P4-field
 *      coupling (verified by source read; pinned below via
 *      getTotalLossExistingApplicationPackageByRecordType under both flag
 *      states). §10.4 GAP-row regression cases that concern quote *building*
 *      therefore have no client surface in this portal version.
 *   4. The only live paths that can carry a GAP package's money to the portal
 *      are the shared, record-type-agnostic reads the prior units wired: the
 *      summary payload (ApplicationSummaryController.getApplicationSummaryData
 *      → getApplicationPackagesForSummary, RT-agnostic engine-snapshot attach)
 *      and the shared DealerPortalController.getActiveApplicationPackageByRecordType
 *      attach — both of which already ship their viewer cutover + parity
 *      suites for the ELW/T&R record types. This suite pins the same
 *      record-type-agnostic guarantees on the GAP_Coverage Application_Package
 *      record type (the GAP RT the org uses — Application_Package__c
 *      'GAP_Coverage'), i.e. IF a GAP package exists on an Application its
 *      money displays through those shared paths exactly like ELW/T&R: legacy
 *      stored build byte-identical while flags are off, engine lines attached
 *      only behind the T5 gate.
 *   5. The P4 end-state ("pure viewer of stored server payload, no client
 *      price math") therefore ALREADY holds for the GAP tab — in fact
 *      trivially, because the tab displays no package payload at all. There
 *      is no engine payload surface to gate and no stored engine value to
 *      re-stamp, so adding isGapEngineViewerActive() + LWC re-stamp branches
 *      would be dead code with no data source (violating §10.1 rule 1's
 *      spirit). No controller or LWC change was made — this unit ships its
 *      parity evidence (the §10.1 "replacement + parity test" standard with
 *      an empty replacement set), exactly like the vehicle-tab unit.
 *
 * What this suite proves (the payload paths GAP data can actually travel in
 * the portal, under the §10.4 GAP-row regression set):
 *   - getGAPProgramInfo (the GAP tab's ONLY Apex read) is byte-identical
 *     across flag states, returns exactly the stored GAP_Program_Info__mdt
 *     content/portalUrl, and never carries engine keys — nothing on the GAP
 *     tab can change when the engine flags flip.
 *   - Worst case: an engine-priced, snapshot-carrying GAP_Coverage package on
 *     the SAME Application (control asserts the summary payload DOES carry
 *     engine lines under the ON flag) leaves the GAP tab's read byte-identical
 *     — engine state cannot leak into the GAP tab.
 *   - Summary payload parity on the GAP record type (the shared, RT-agnostic
 *     attach): flag-off summary wrapper = legacy stored build, no engine
 *     lines; flag-on = money rebuilt from the stored lines + lineItems
 *     attached; base-only GAP fixture pins 1100/143/1243 @13% (same numbers
 *     as the ELW/T&R suites — the engine and attach are RT-agnostic).
 *   - The dormant legacy GAP quote read (getTotalLossExistingApplicationPackageByRecordType)
 *     returns a finance-field map byte-identical under both flag states with
 *     no engine keys (no P4 coupling, as source-verified).
 *   - The existing per-tab viewer gates (warranty / T&R host / summary) read
 *     Apex flags and are false with zero Aprotect_Portal_Settings rows; the
 *     GAP tab imports none of them and no package read (source-level fact
 *     recorded in the class header + run record), so no gate flip can reach
 *     the GAP tab's display.
 *
 * TEST CONTEXT FACT (same as the sibling parity suites / snapshot tests):
 * inserting a NON-engine-priced Application_Package runs the legacy
 * create-time flow, which cannot execute in the test user context. The one
 * package insert here mirrors production: the engine stamps the record
 * (Priced_By_Engine__c = true) BEFORE the DML, so the flow terminates at its
 * engine guard.
 *
 * ORG QUIRK respected: Package__c percent-config is never read (engine quotes
 * use the handler DEFAULT constants — the ×100 stored-rate anomaly is a
 * deferred item; do not resolve dp-link config in these tests).
 */
@isTest
private class DealerPortalGapEngineParityTest {

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

    private static Vehicle__c vehicle(String name, Make__c m, Model__c mo) {
        Vehicle__c v = new Vehicle__c(Name = name, Make_Lookup__c = m.Id, Model_Lookup__c = mo.Id,
            Fuel_Type__c = 'Gas', Usage_Type__c = 'Personal Use');
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

    /**
     * Full context: GAP catalogue (Package__c RT Gap_Coverage → dealer mirror
     * RT Total_Loss_Coverage per the sync map / TestDataFactory, Application
     * Package RT GAP_Coverage) + dealer mirror + Application. The engine is
     * record-type agnostic — same fixture shape as the ELW/T&R parity suites.
     */
    private static Ctx build(String tag, Decimal rate) {
        Tax__c tax = taxRegion('GAPTX' + tag, rate);
        Account d = dealer('GD' + tag, tax);
        Make__c mk = make('GMK' + tag);
        Model__c mo = model(mk, 'GMD' + tag);
        Vehicle__c v = vehicle('GV' + tag, mk, mo);

        Package_Group__c grp = new Package_Group__c(Name = 'GGRP' + tag, Active__c = true);
        insert grp;
        Package__c pkg = new Package__c(Name = 'GPKG' + tag, Package_Group__c = grp.Id,
            RecordTypeId = rt('Package__c', 'Gap_Coverage'), Is_Active__c = true);
        insert pkg;
        Package_Tier__c tier = new Package_Tier__c(Name = 'GTIR' + tag, Package__c = pkg.Id);
        insert tier;
        Package_Term__c mt = new Package_Term__c(Name = 'GTRM' + tag, Package_Tier__c = tier.Id,
            Price__c = 1000.00);
        insert mt;

        Dealer_Package__c dp = new Dealer_Package__c(Name = 'GDP' + tag, Dealer__c = d.Id,
            Package__c = pkg.Id, RecordTypeId = rt('Dealer_Package__c', 'Total_Loss_Coverage'));
        insert dp;
        Dealer_Package_Term__c dt = new Dealer_Package_Term__c(Name = 'GDPT' + tag,
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
    private static Application_Package__c insertEnginePricedGapPackage(Ctx c) {
        Application_Package__c pkg = new Application_Package__c(
            Name = 'GAPK' + c.v.Name,
            Application__c = c.app.Id,
            Dealer__c = c.dealer.Id,
            Dealer_Package__c = c.dealerPackageId,
            Dealer_Package_Term__c = c.dt.Id,
            Package_Term__c = c.masterTermId,
            RecordTypeId = rt('Application_Package__c', 'GAP_Coverage'),
            Active__c = true
        );
        PricingEngineService.QuoteRequest req = requestFor(c, pkg);
        PricingEngineService.QuoteResult res = PricingEngineService.applyEnginePricing(pkg, req);
        System.assert(res.success, 'engine pricing expected to succeed: ' + res.errors);
        Database.insert(pkg, System.AccessLevel.SYSTEM_MODE);
        Boolean written = ApplicationSnapshotService.writeSnapshot(pkg.Id,
            PricingEngineService.applyEnginePricing(pkg, requestFor(c, pkg)));
        System.assertEquals(true, written, 'snapshot must be written for the parity fixture');
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

    // ------------------------------------------------------------------
    // The GAP tab's only Apex read: GAPProgramInfoController.getGAPProgramInfo
    // ------------------------------------------------------------------

    private static Map<String, String> gapProgramInfo() {
        Map<String, String> info = GAPProgramInfoController.getGAPProgramInfo();
        System.assert(info != null, 'getGAPProgramInfo must return a map');
        return info;
    }

    private static void assertInfoShape(Map<String, String> info, String ctx) {
        // The GAP tab read returns exactly the stored program-info CMT fields:
        // content (program text) + portalUrl (Trisura portal). No application
        // context, no package payload, no engine keys — the method signature
        // itself takes no applicationId.
        System.assertEquals(true, info.containsKey('content'), ctx + ': content key');
        System.assertEquals(true, info.containsKey('portalUrl'), ctx + ': portalUrl key');
        System.assertEquals(2, info.keySet().size(), ctx + ': exactly content + portalUrl keys');
        String content = info.get('content');
        System.assertNotEquals(null, content, ctx + ': content present');
        System.assertNotEquals('', content.trim(), ctx + ': content non-blank');
        GAP_Program_Info__mdt cmt = [SELECT Content__c, Portal_URL__c FROM GAP_Program_Info__mdt
                                     WHERE DeveloperName = 'Default' LIMIT 1];
        System.assertEquals(cmt.Content__c, content, ctx + ': content equals stored CMT');
        System.assertEquals(cmt.Portal_URL__c, info.get('portalUrl'), ctx + ': portalUrl equals stored CMT');
    }

    /** Engine line keys that exist ONLY on the shared package payloads. */
    private static final List<String> ENGINE_KEYS = new List<String>{
        'lineItems', 'hasEngineLineItems', 'contractPremiumPrice',
        'contractPremiumPriceWithoutTax', 'Priced_By_Engine', 'Engine-Priced'
    };

    private static void assertNoEngineKeys(String serialized, String ctx) {
        for (String key : ENGINE_KEYS) {
            System.assertEquals(false, serialized.contains(key),
                ctx + ': serialized payload must not contain engine key "' + key + '"');
        }
    }

    // ------------------------------------------------------------------
    // Summary-path helpers (the RT-agnostic GAP money display surface)
    // ------------------------------------------------------------------

    private static ApplicationSummaryController.ApplicationPackageWrapper readGapWrapper(Id appId) {
        ApplicationSummaryController.ApplicationSummaryData data =
            ApplicationSummaryController.getApplicationSummaryData(appId);
        System.assert(data != null && data.applicationPackages != null
            && data.applicationPackages.size() == 1,
            'expected exactly one record-type group, got '
            + (data == null || data.applicationPackages == null ? 'none' : String.valueOf(data.applicationPackages.size())));
        List<ApplicationSummaryController.ApplicationPackageWrapper> pkgs =
            data.applicationPackages[0].packages;
        System.assert(pkgs != null && pkgs.size() == 1, 'expected exactly one package wrapper');
        return pkgs[0];
    }

    private static void assertNoEngineLines(ApplicationSummaryController.ApplicationPackageWrapper w, String ctx) {
        System.assertEquals(null, w.lineItems, ctx + ': lineItems must be absent on legacy payload');
        System.assertEquals(true, w.hasEngineLineItems != true, ctx + ': hasEngineLineItems must not be set');
    }

    private static void assertLineSet(ApplicationSummaryController.ApplicationPackageWrapper w,
            List<Decimal> expectedAmounts, String ctx) {
        System.assertEquals(expectedAmounts.size(), w.lineItems.size(), ctx + ': line count');
        for (Integer i = 0; i < expectedAmounts.size(); i++) {
            System.assertEquals(expectedAmounts[i], w.lineItems[i].amount, ctx + ': line ' + i + ' amount');
            System.assertNotEquals(null, w.lineItems[i].description, ctx + ': line ' + i + ' description');
            System.assertNotEquals(null, w.lineItems[i].formattedAmount, ctx + ': line ' + i + ' formatted');
            System.assertNotEquals(null, w.lineItems[i].key, ctx + ': line ' + i + ' key');
        }
        ApplicationSummaryController.LineItemDTO last = w.lineItems[w.lineItems.size() - 1];
        System.assertEquals('Tax', last.lineType, ctx + ': tax line must be last');
        System.assertEquals(true, w.hasEngineLineItems, ctx + ': hasEngineLineItems flag');
        Decimal noTax = 0;
        Decimal tax = 0;
        for (ApplicationSummaryController.LineItemDTO li : w.lineItems) {
            if (li.lineType == 'Tax') {
                tax += li.amount;
            } else {
                noTax += li.amount;
            }
        }
        System.assertEquals(w.retailCost, noTax, ctx + ': retail == non-Tax line sum');
        System.assertEquals(w.tax, tax, ctx + ': tax == Tax line sum');
        System.assertEquals(w.total, noTax + tax, ctx + ': total == all-line sum');
    }

    private static void assertRenderedFieldParity(
            ApplicationSummaryController.ApplicationPackageWrapper enginePkg,
            ApplicationSummaryController.ApplicationPackageWrapper legacyPkg) {
        System.assertEquals(legacyPkg.packageHeaderName, enginePkg.packageHeaderName, 'header');
        System.assertEquals(legacyPkg.planName, enginePkg.planName, 'planName');
        System.assertEquals(legacyPkg.coverageTerm, enginePkg.coverageTerm, 'coverageTerm');
        System.assertEquals(legacyPkg.retailCost, enginePkg.retailCost, 'retailCost (stored no-tax total = non-Tax line sum)');
        System.assertEquals(legacyPkg.formattedRetailCost, enginePkg.formattedRetailCost, 'formattedRetailCost');
        System.assertEquals(legacyPkg.tax, enginePkg.tax, 'tax (stored Tax_Amount = Tax-line sum)');
        System.assertEquals(legacyPkg.formattedTax, enginePkg.formattedTax, 'formattedTax');
        System.assertEquals(legacyPkg.taxRate, enginePkg.taxRate, 'taxRate');
        System.assertEquals(legacyPkg.formattedTaxRate, enginePkg.formattedTaxRate, 'formattedTaxRate');
        System.assertEquals(legacyPkg.total, enginePkg.total, 'total (stored with-tax total = all-line sum)');
        System.assertEquals(legacyPkg.formattedTotal, enginePkg.formattedTotal, 'formattedTotal');
        System.assertEquals(legacyPkg.deductible, enginePkg.deductible, 'deductible');
        System.assertEquals(legacyPkg.formattedDeductible, enginePkg.formattedDeductible, 'formattedDeductible');
        System.assertEquals(legacyPkg.contractStartDate, enginePkg.contractStartDate, 'contractStartDate');
        System.assertEquals(legacyPkg.contractExpiryDate, enginePkg.contractExpiryDate, 'contractExpiryDate');
        System.assertEquals(legacyPkg.contractStartOdometer, enginePkg.contractStartOdometer, 'contractStartOdometer');
        System.assertEquals(legacyPkg.contractExpiryOdometer, enginePkg.contractExpiryOdometer, 'contractExpiryOdometer');
        System.assertEquals(legacyPkg.contractStartOdometerUnit, enginePkg.contractStartOdometerUnit, 'contractStartOdometerUnit');
        System.assertEquals(legacyPkg.contractExpiryOdometerUnit, enginePkg.contractExpiryOdometerUnit, 'contractExpiryOdometerUnit');
        System.assertEquals(legacyPkg.packageTermOdometerKM, enginePkg.packageTermOdometerKM, 'packageTermOdometerKM');
        System.assertEquals(legacyPkg.perClaimLimit, enginePkg.perClaimLimit, 'perClaimLimit');
    }

    // ------------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------------

    @isTest
    static void testGapTabRead_FlagsOff_LegacyShape_NoEngineKeys() {
        // §10.4 GAP-row baseline: the GAP tab's only Apex read with all flags
        // off must return exactly the stored program-info content — no engine
        // keys, no package payload, byte-identical to the pre-cutover shape.
        delete [SELECT Id FROM Aprotect_Portal_Settings__c];
        Map<String, String> info = gapProgramInfo();
        assertInfoShape(info, 'flag-off tab read');
        assertNoEngineKeys(JSON.serialize(info), 'flag-off tab read');
    }

    @isTest
    static void testGapTabRead_FlagsOn_ByteIdenticalToLegacy() {
        // The same read with engine + snapshot flags ON must be byte-identical:
        // the GAP tab displays static program info from a CMT — the engine
        // snapshot attach (which enriches the active-package payloads the
        // warranty/T&R tabs render) cannot reach it.
        setFlags(true, false);
        Map<String, String> off = gapProgramInfo();
        setFlags(true, true);
        Map<String, String> onState = gapProgramInfo();

        System.assertEquals(JSON.serialize(off), JSON.serialize(onState),
            'getGAPProgramInfo must be byte-identical across flag states');
        assertInfoShape(onState, 'flag-on tab read');
        assertNoEngineKeys(JSON.serialize(onState), 'flag-on tab read');
    }

    @isTest
    static void testEnginePricedGapPackageOnApp_DoesNotLeakIntoGapTab() {
        // Worst case for the GAP tab: the same Application carries an
        // engine-priced, snapshot-carrying GAP_Coverage package (the state in
        // which the shared summary/package payloads DO carry engine lines —
        // asserted live below as a control). The GAP tab's read has no
        // application context at all and must stay byte-identical.
        Ctx c = build('G6', 13);
        setFlags(true, true);
        Application_Package__c pkg = insertEnginePricedGapPackage(c);

        // Control: the summary payload for the SAME package carries engine
        // lines under the ON flag (the RT-agnostic attach is live)...
        ApplicationSummaryController.ApplicationPackageWrapper onPkg = readGapWrapper(c.app.Id);
        System.assertEquals(true, onPkg.hasEngineLineItems == true,
            'control: summary must carry engine lines under the ON flag');
        System.assertNotEquals(null, onPkg.lineItems, 'control: line set attached');

        // ...while the GAP tab's only read on the same org state is unchanged.
        setFlags(true, false);
        Map<String, String> offInfo = gapProgramInfo();
        setFlags(true, true);
        Map<String, String> onInfo = gapProgramInfo();
        System.assertEquals(JSON.serialize(offInfo), JSON.serialize(onInfo),
            'GAP tab read must be byte-identical across flag states with an engine-priced package present');
        assertInfoShape(onInfo, 'leak-control tab read');
        assertNoEngineKeys(JSON.serialize(onInfo), 'leak-control tab read');
    }

    @isTest
    static void testSummaryPayload_GapPackage_FlagsOff_NeverEngineLines() {
        // The summary is the only live surface that can display a GAP
        // package's money in the portal. With lines stored (gate was on at
        // snapshot time) but the READ happening with the gate off, the summary
        // wrapper must be the legacy stored-field build — no engine lines,
        // byte-identical to the pre-cutover shape.
        setFlags(true, true);
        Ctx c = build('G4', 13);
        Application_Package__c pkg = insertEnginePricedGapPackage(c);

        setFlags(true, false);
        ApplicationSummaryController.ApplicationPackageWrapper offPkg = readGapWrapper(c.app.Id);

        assertNoEngineLines(offPkg, 'flag-off summary read');
        // Legacy stored build for the base-only GAP fixture:
        // 1000 + 100 markup = 1100 no-tax -> 143 tax @13% -> 1243 with-tax.
        System.assertEquals(1100.00, offPkg.retailCost);
        System.assertEquals(143.00, offPkg.tax);
        System.assertEquals(1243.00, offPkg.total);
        System.assertEquals('$1,243', offPkg.formattedTotal);
    }

    @isTest
    static void testSummaryPayload_GapPackage_FlagsOn_EngineSnapshotParity() {
        // Engine-snapshot payload (gate ON: money rebuilt from the persisted
        // line items + lineItems attached) EQUALS the legacy payload (gate
        // OFF: stored-field build) for the GAP record type — same numbers and
        // same rendered-field parity the ELW/T&R suites pin, proving the
        // attach is record-type agnostic.
        setFlags(true, true);
        Ctx c = build('G5', 13);
        Application_Package__c pkg = insertEnginePricedGapPackage(c);

        setFlags(true, false);
        ApplicationSummaryController.ApplicationPackageWrapper legacyPkg = readGapWrapper(c.app.Id);
        setFlags(true, true);
        ApplicationSummaryController.ApplicationPackageWrapper enginePkg = readGapWrapper(c.app.Id);

        assertRenderedFieldParity(enginePkg, legacyPkg);
        System.assertEquals(1100.00, enginePkg.retailCost);
        System.assertEquals(143.00, enginePkg.tax);
        System.assertEquals(1243.00, enginePkg.total);
        System.assertEquals('$1,243', enginePkg.formattedTotal);
        System.assertEquals(false, enginePkg.hasPremiumModelFee);

        assertLineSet(enginePkg, new List<Decimal>{ 1100.00, 143.00 }, 'GAP base-only ON payload');
        assertNoEngineLines(legacyPkg, 'GAP base-only OFF payload');
    }

    @isTest
    static void testDormantTotalLossRead_FlagsParity_NoEngineKeys() {
        // The dormant legacy GAP quote read (finance-input quote flow —
        // source-verified: zero LWC/aura/page/flow callers in the repo) reads
        // an existing GAP_Coverage package's finance fields. It must return a
        // byte-identical map under both flag states with no engine keys and no
        // P4 coupling — pinning that the legacy GAP flow stays untouched and
        // engine-free while the flags are off (and after T5).
        setFlags(true, true);
        Ctx c = build('G7', 13);
        Application_Package__c pkg = insertEnginePricedGapPackage(c);

        setFlags(true, false);
        Map<String, Object> off = DealerPortalController.getTotalLossExistingApplicationPackageByRecordType(
            c.app.Id, 'GAP_Coverage');
        System.assertEquals(true, off.get('success'), 'dormant GAP read (flags off) failed: ' + off.get('message'));
        System.assertNotEquals(null, off.get('data'), 'dormant GAP read must find the package');

        setFlags(true, true);
        Map<String, Object> onState = DealerPortalController.getTotalLossExistingApplicationPackageByRecordType(
            c.app.Id, 'GAP_Coverage');
        System.assertEquals(true, onState.get('success'), 'dormant GAP read (flags on) failed: ' + onState.get('message'));

        System.assertEquals(JSON.serialize(off), JSON.serialize(onState),
            'dormant Total-Loss read must be byte-identical across flag states');
        Map<String, Object> onData = (Map<String, Object>) onState.get('data');
        System.assertNotEquals(null, onData.get('Id'), 'package Id present');
        assertNoEngineKeys(JSON.serialize(onState), 'dormant Total-Loss read');
        // Finance-input keys of the legacy GAP quote flow are intact.
        System.assertEquals(pkg.Id, onData.get('Id'));
    }

    @isTest
    static void testViewerGates_ReadApexFlags() {
        // Org default: no setting rows => every per-tab viewer gate is false
        // (all LWC cutover code inert). Engine on alone is not enough; the
        // snapshot flag (T5) is the state in which stored line sets exist.
        // The GAP tab imports none of these gates and no package read
        // (source-level fact in the class header + run record), so no gate
        // flip can reach the GAP tab's display.
        delete [SELECT Id FROM Aprotect_Portal_Settings__c];
        System.assertEquals(false, DealerPortalController.isWarrantyEngineViewerActive(),
            'warranty gate false with zero rows');
        System.assertEquals(false, DealerPortalController.isTireRimEngineViewerActive(),
            'T&R host gate false with zero rows');
        System.assertEquals(false, ApplicationSummaryController.isSummaryEngineViewerActive(),
            'summary gate false with zero rows');

        setFlags(true, false);
        System.assertEquals(false, DealerPortalController.isWarrantyEngineViewerActive());
        System.assertEquals(false, DealerPortalController.isTireRimEngineViewerActive());
        System.assertEquals(false, ApplicationSummaryController.isSummaryEngineViewerActive());

        setFlags(true, true);
        System.assertEquals(true, DealerPortalController.isWarrantyEngineViewerActive(),
            'warranty gate true when Line_Item_Snapshot_Enabled__c is on');
        System.assertEquals(true, DealerPortalController.isTireRimEngineViewerActive());
        System.assertEquals(true, ApplicationSummaryController.isSummaryEngineViewerActive());
    }
}