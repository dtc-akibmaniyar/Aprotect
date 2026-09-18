/**
 * DealerPortalContainerEngineParityTest
 *
 * P4 [L] portal-container (tab shell) payload-parity evidence — the FINAL
 * unit of the per-tab viewer cutover (change-implementation plan §11 P4 [L],
 * §10.1 rule 1, §10.4 Cross-tab row incl. the frozen modal/scroll set, §13.5
 * Cross-tab row; decision 2026-09-06 option (b): source-level + Apex
 * payload-parity evidence is the accepted regression standard for the LWC
 * cutover).
 *
 * UNIT-SHAPE NOTE (verified deviation from the summary/warranty/T&R template
 * — see run record 2026-09-06-p4-c1-container): lwc/dealerPortalContainer
 * (1,053-line JS, 198-line HTML) is the portal SHELL that hosts the tab
 * envelope — it renders NO package payload and NO money of its own, so there
 * is no engine-priced surface to gate or re-stamp at container level. Source
 * verification (repo, this run):
 *   1. The container's full Apex import surface is FIVE methods, none of them
 *      a package/money read: DealerPortalController.getApplicationStatus
 *      (status/lock/payment fields — drives the locked banner, header title,
 *      summary-only lock), DealerPortalController.hasTireRimPackages (Boolean
 *      — drives Tire & Rim tab visibility), DealerPortalController.
 *      convertApplicationToQuote / convertQuoteToApplication (Save-As-Quote /
 *      Convert-to-Application modal actions), QuotePDFGeneratorService.
 *      generateQuotePDF (deferred [T] Conga PDF item — not exercised here).
 *      It does NOT import getActiveApplicationPackageByRecordType (the shared
 *      engine-snapshot-attached read) or the summary payload read, and it
 *      imports no viewer gate.
 *   2. Its JS has ZERO currency-formatting / client-recalc tokens (no
 *      toFixed/Intl/formatCurrency/parseFloat; no price/premiumFee/taxAmount/
 *      contractPremium tokens) and no engine/lineItem/snapshot identifiers;
 *      its HTML (tab strip, six c-dealer-portal-* tab hosts, locked banner,
 *      one Convert-to-Application modal, PDF button) has no money display of
 *      any kind.
 *   3. Tab switching is pure client state: switchToTab() clears any stale body
 *      scroll-lock (the frozen Phase-C failsafe), sets activeTab, scrolls to
 *      top, and notifies the activated child via onTabActivated() — each child
 *      tab re-reads ITS OWN payload on activation (the exact surfaces the
 *      warranty / T&R / vehicle / GAP / more-products / summary units cut
 *      over and parity-pinned). The container itself keeps no package state
 *      and re-reads nothing engine-related on a tab switch.
 *   4. Modal/scroll behaviour lives here (lockBodyScroll/unlockBodyScroll
 *      idempotent lock helpers + the Convert-to-Application modal state) —
 *      the frozen regression list applies to the whole envelope, so this unit
 *      changes nothing: no LWC edit, no controller edit.
 * No controller gate (isContainerEngineViewerActive) or LWC re-stamp branch
 * was added — there is no engine payload at the shell level to gate or
 * re-stamp (violating §10.1 rule 1's spirit would be adding dead code with no
 * data source), exactly like the vehicle / GAP / more-products units. This
 * suite ships the parity evidence over the container's ACTUAL payload paths.
 *
 * What this suite proves (the payloads the shell reads, under the §10.4
 * Cross-tab rows — tab switching retains state, modal/scroll unchanged, no
 * client recalc; plus the container's status read and tab-visibility read):
 *   - getApplicationStatus (the only Application read the shell performs —
 *     status, lock date, payment status — feeding the locked banner + header)
 *     returns a typed Application__c with exactly the stored status fields
 *     and NO engine keys, byte-identical across flag states, including a
 *     locked/paid application (the state that drives the summary-only lock
 *     envelope).
 *   - hasTireRimPackages (the Tire & Rim tab-visibility read) is a pure
 *     Dealer_Package catalogue count for the app's dealer: false without a
 *     Tire_Rim_Protection_Plan dealer package, true with one, byte-identical
 *     across flag states, and never engine-keyed.
 *   - Cross-tab leak guard (worst case): an engine-priced, snapshot-carrying
 *     Tire_Rim_Protection_Plan package on the SAME Application (control
 *     asserts the shared active-package read DOES carry engine lines under
 *     the ON flag) leaves the shell's reads (getApplicationStatus +
 *     hasTireRimPackages) byte-identical across flag states — engine state
 *     cannot leak into the shell, and a flag-off shell read never surfaces
 *     engine lines.
 *   - Save-As-Quote / Convert-to-Application round trips (the shell's two
 *     modal actions) return byte-identical ApplicationPackageResponse payloads
 *     under both flag states with no engine keys — the actions are
 *     flag-agnostic.
 *   - The per-tab viewer gates read the Apex flag and are false with zero
 *     Aprotect_Portal_Settings rows and with the engine flag alone, true only
 *     at T5 (Line_Item_Snapshot_Enabled__c on) — no viewer code can execute
 *     while the flags are off; the container imports no gate and no package
 *     read (source-level facts in the class header + run record).
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
private class DealerPortalContainerEngineParityTest {

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
     * Full context: T&R catalogue (Package__c RT Tire_Rim_Protection_Plan →
     * dealer mirror RT Tire_Rim_Protection_Plan) + dealer mirror + Application.
     * The engine is record-type agnostic — same fixture shape as the ELW
     * parity suites; the T&R dealer package also makes
     * DealerPortalController.hasTireRimPackages return true for this dealer
     * (the container's Tire & Rim tab-visibility read).
     */
    private static Ctx build(String tag, Decimal rate) {
        return build(tag, rate, null, null, null);
    }

    /**
     * build() with explicit envelope fields set at INSERT time (status /
     * payment / lock date). The locked-state fixtures are created here rather
     * than via a later update because Application__c UPDATEs run the org's
     * active Update Opportunity Statuses flow, which errors in the test
     * context when no Opportunity record variable is populated (verified org
     * quirk — prior parity suites only ever INSERT Application__c).
     */
    private static Ctx build(String tag, Decimal rate, String status, String paymentStatus, Date lockDate) {
        Tax__c tax = taxRegion('CTX' + tag, rate);
        Account d = dealer('CD' + tag, tax);
        Make__c mk = make('CMK' + tag);
        Model__c mo = model(mk, 'CMD' + tag);
        Vehicle__c v = vehicle('CV' + tag, mk, mo);

        Package_Group__c grp = new Package_Group__c(Name = 'CGRP' + tag, Active__c = true);
        insert grp;
        Package__c pkg = new Package__c(Name = 'CPKG' + tag, Package_Group__c = grp.Id,
            RecordTypeId = rt('Package__c', 'Tire_Rim_Protection_Plan'), Is_Active__c = true);
        insert pkg;
        Package_Tier__c tier = new Package_Tier__c(Name = 'CTIR' + tag, Package__c = pkg.Id);
        insert tier;
        Package_Term__c mt = new Package_Term__c(Name = 'CTRM' + tag, Package_Tier__c = tier.Id,
            Price__c = 1000.00);
        insert mt;

        Dealer_Package__c dp = new Dealer_Package__c(Name = 'CDP' + tag, Dealer__c = d.Id,
            Package__c = pkg.Id, RecordTypeId = rt('Dealer_Package__c', 'Tire_Rim_Protection_Plan'));
        insert dp;
        Dealer_Package_Term__c dt = new Dealer_Package_Term__c(Name = 'CDPT' + tag,
            Dealer_Package__c = dp.Id, Package_Term__c = mt.Id,
            Original_Package_Term_Cost__c = 1000.00, Markup__c = 100.00, Markup_Type__c = '$');
        insert dt;

        Ctx c = new Ctx();
        c.dealer = d; c.v = v; c.dealerPackageId = dp.Id; c.dt = dt; c.masterTermId = mt.Id;
        Application__c app = new Application__c(Vehicle__c = v.Id, Dealer_Name__c = d.Id);
        if (String.isNotBlank(status)) {
            app.Application_Status__c = status;
        }
        if (String.isNotBlank(paymentStatus)) {
            app.Payment_Status__c = paymentStatus;
        }
        if (lockDate != null) {
            app.Application_Lock_Date__c = lockDate;
        }
        insert app;
        c.app = app;
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
    private static Application_Package__c insertEnginePricedPackage(Ctx c) {
        Application_Package__c pkg = new Application_Package__c(
            Name = 'CAPK' + c.v.Name,
            Application__c = c.app.Id,
            Dealer__c = c.dealer.Id,
            Dealer_Package__c = c.dealerPackageId,
            Dealer_Package_Term__c = c.dt.Id,
            Package_Term__c = c.masterTermId,
            RecordTypeId = rt('Application_Package__c', 'Tire_Rim_Protection_Plan'),
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
    // The shell's reads: getApplicationStatus + hasTireRimPackages
    // ------------------------------------------------------------------

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

    /**
     * The shell's status read returns a TYPED Application__c with exactly the
     * stored status/lock/payment fields — the envelope state that drives the
     * locked banner, header title and summary-only lock. Assert the returned
     * record is the stored record's fields (nothing engine-derived) and the
     * serialized payload key set is exactly the envelope fields (+ SObject
     * attributes) — never engine keys, never package/money keys.
     *
     * NOTE: JSON.serialize omits null-valued fields, so a fresh Draft
     * application serializes without Application_Status__c when null — the
     * key-set assertion below is null-tolerant (it checks that no UNEXPECTED
     * key is present, not that every optional field is).
     */
    private static void assertStatusReadShape(Application__c stored, Application__c read, String ctx) {
        System.assertNotEquals(null, read, ctx + ': status read must return the application');
        System.assertEquals(stored.Id, read.Id, ctx + ': same application');
        System.assertEquals(stored.Application_Status__c, read.Application_Status__c, ctx + ': status');
        System.assertEquals(stored.Application_Lock_Date__c, read.Application_Lock_Date__c, ctx + ': lock date');
        System.assertEquals(stored.Payment_Status__c, read.Payment_Status__c, ctx + ': payment status');
        String ser = JSON.serialize(read);
        assertNoEngineKeys(ser, ctx);
        Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(ser);
        Set<String> allowed = new Set<String>{
            'attributes', 'Id', 'Application_Status__c',
            'Application_Lock_Date__c', 'Payment_Status__c'
        };
        for (String k : m.keySet()) {
            System.assertEquals(true, allowed.contains(k),
                ctx + ': unexpected payload key "' + k + '" on the typed status read');
        }
    }

    // ------------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------------

    @isTest
    static void testStatusRead_FlagsOff_LegacyShape_NoEngineKeys() {
        // §10.4 Cross-tab baseline: the shell's status read with all flags off
        // returns exactly the stored envelope fields — no engine keys — on an
        // ordinary Draft application.
        delete [SELECT Id FROM Aprotect_Portal_Settings__c];
        Ctx c = build('C1', 13, 'Draft', 'Unpaid', null);
        Application__c stored = [SELECT Id, Application_Status__c, Application_Lock_Date__c,
                                        Payment_Status__c
                                 FROM Application__c WHERE Id = :c.app.Id];
        Application__c read = DealerPortalController.getApplicationStatus(c.app.Id);
        assertStatusReadShape(stored, read, 'flag-off status read');
        System.assertEquals('Draft', read.Application_Status__c, 'stored status returned');
        System.assertEquals('Unpaid', read.Payment_Status__c, 'stored payment status returned');
    }

    @isTest
    static void testStatusRead_FlagsOn_ByteIdenticalToLegacy() {
        // The same read with engine + snapshot flags ON must be byte-identical:
        // the shell's status read has no engine attach (source-verified), so
        // the envelope state the container displays cannot change when the
        // engine state flips.
        delete [SELECT Id FROM Aprotect_Portal_Settings__c];
        Ctx c = build('C2', 13, 'Draft', 'Unpaid', null);
        Application__c stored = [SELECT Id, Application_Status__c, Application_Lock_Date__c,
                                        Payment_Status__c
                                 FROM Application__c WHERE Id = :c.app.Id];

        Application__c off = DealerPortalController.getApplicationStatus(c.app.Id);
        setFlags(true, true);
        Application__c onState = DealerPortalController.getApplicationStatus(c.app.Id);

        System.assertEquals(JSON.serialize(off), JSON.serialize(onState),
            'getApplicationStatus must be byte-identical across flag states');
        assertStatusReadShape(stored, onState, 'flag-on status read');
        assertNoEngineKeys(JSON.serialize(onState), 'flag-on status read');
    }

    @isTest
    static void testLockedApplicationStatusRead_FlagsParity() {
        // Locked-application envelope: Payment_Status 'Paid' + a past lock
        // date is the state that drives the container's isApplicationLocked
        // getter (summary-only lock + locked banner + hidden tab strip). The
        // fields feeding that envelope must be byte-identical across flag
        // states — flipping engine state can never change what the lock
        // envelope reads.
        //
        // ORG QUIRK (verified this run): the locked state is created at
        // INSERT time, not via a later update — Application__c UPDATEs run
        // the org's active "Update Opportunity Statuses" flow, which fails in
        // the test context ("If you use a record variable to update or delete
        // records, the ID value in the variable must be populated") because
        // no Opportunity record variable exists. Prior parity suites likewise
        // only ever insert Application__c.
        delete [SELECT Id FROM Aprotect_Portal_Settings__c];
        Ctx c = build('C3', 13, 'Active', 'Paid', Date.newInstance(2026, 1, 1));

        Application__c off = DealerPortalController.getApplicationStatus(c.app.Id);
        setFlags(true, true);
        Application__c onState = DealerPortalController.getApplicationStatus(c.app.Id);

        System.assertEquals(JSON.serialize(off), JSON.serialize(onState),
            'locked-app status read must be byte-identical across flag states');
        System.assertEquals('Active', onState.Application_Status__c, 'stored status');
        System.assertEquals('Paid', onState.Payment_Status__c, 'stored payment status');
        System.assertEquals(Date.newInstance(2026, 1, 1), onState.Application_Lock_Date__c, 'stored lock date');
        assertNoEngineKeys(JSON.serialize(onState), 'locked-app status read');
    }

    @isTest
    static void testHasTireRimPackages_FlagsParity_TabVisibility() {
        // The container's Tire & Rim tab-visibility read is a pure catalogue
        // count for the app's dealer: false without a T&R dealer package, true
        // with one — byte-identical across flag states, never engine-keyed.
        // (A dealer with ONLY an ELW mirror stays false; the T&R dealer flips
        // true the moment a Tire_Rim_Protection_Plan dealer package exists.)
        setFlags(true, true);
        Ctx c = build('C4', 13); // dealer HAS a T&R Dealer_Package

        setFlags(true, false);
        System.assertEquals(true, DealerPortalController.hasTireRimPackages(c.app.Id),
            'T&R dealer package present -> tab visible (flags off)');
        setFlags(true, true);
        System.assertEquals(true, DealerPortalController.hasTireRimPackages(c.app.Id),
            'T&R dealer package present -> tab visible (flags on)');

        // Dealer WITHOUT any T&R dealer package -> false under both states.
        Account otherDealer = dealer('CNOTR', null);
        Make__c mk2 = make('CNOMK2');
        Model__c mo2 = model(mk2, 'CNOMD2');
        Vehicle__c v2 = vehicle('CNOV2', mk2, mo2);
        Application__c appNoTr = new Application__c(Vehicle__c = v2.Id, Dealer_Name__c = otherDealer.Id);
        insert appNoTr;

        setFlags(true, false);
        System.assertEquals(false, DealerPortalController.hasTireRimPackages(appNoTr.Id),
            'no T&R dealer package -> tab hidden (flags off)');
        setFlags(true, true);
        System.assertEquals(false, DealerPortalController.hasTireRimPackages(appNoTr.Id),
            'no T&R dealer package -> tab hidden (flags on)');

        delete [SELECT Id FROM Aprotect_Portal_Settings__c];
    }

    @isTest
    static void testEnginePricedPackageOnApp_DoesNotLeakIntoShellReads() {
        // Worst case for the shell: the SAME Application carries an
        // engine-priced, snapshot-carrying T&R package (the state in which the
        // shared package payload DOES carry engine lines — asserted live below
        // as a control). The shell's reads (getApplicationStatus +
        // hasTireRimPackages) must stay byte-identical across flag states and
        // never surface engine lines — the cross-tab leak guard at shell
        // level: no tab switch or status reload can surface engine state in
        // the envelope.
        setFlags(true, true);
        Ctx c = build('C5', 13);
        Application_Package__c pkg = insertEnginePricedPackage(c);

        // Control: the shared active-package read (which the T&R host tab
        // performs) DOES carry engine lines under the ON flag...
        DealerPortalController.ApplicationPackageResponse ctl =
            DealerPortalController.getActiveApplicationPackageByRecordType(c.app.Id, 'Tire_Rim_Protection_Plan');
        System.assertEquals(true, ctl.success, 'control read must succeed: ' + ctl.message);
        Map<String, Object> ctlData = (Map<String, Object>) ctl.data;
        System.assertEquals(true, ctlData.get('hasEngineLineItems') == true,
            'control: shared package read must carry engine lines under the ON flag');
        System.assertNotEquals(null, ctlData.get('lineItems'), 'control: line set attached');
        System.assertEquals(pkg.Id, ctlData.get('Id'), 'control: same package');

        // ...while the shell's reads on the same org state are unchanged.
        setFlags(true, false);
        Application__c offStatus = DealerPortalController.getApplicationStatus(c.app.Id);
        Boolean offTr = DealerPortalController.hasTireRimPackages(c.app.Id);
        setFlags(true, true);
        Application__c onStatus = DealerPortalController.getApplicationStatus(c.app.Id);
        Boolean onTr = DealerPortalController.hasTireRimPackages(c.app.Id);

        System.assertEquals(JSON.serialize(offStatus), JSON.serialize(onStatus),
            'status read must be byte-identical across flag states with an engine-priced package present');
        System.assertEquals(offTr, onTr, 'Tire & Rim visibility must be byte-identical across flag states');
        System.assertEquals(true, onTr, 'T&R dealer package still present -> tab visible');
        assertNoEngineKeys(JSON.serialize(onStatus), 'shell status read (engine package present)');

        delete [SELECT Id FROM Aprotect_Portal_Settings__c];
    }

    @isTest
    static void testFlagOffShellReads_NeverEngineLines() {
        // Flag-off shell reads of an app whose package carries a stored line
        // set (gate was on at snapshot time): the shell never surfaces engine
        // lines — its status read and visibility read are engine-free by
        // construction (source-verified: neither read touches the shared
        // engine-snapshot attach).
        setFlags(true, true);
        Ctx c = build('C6', 13);
        insertEnginePricedPackage(c);

        setFlags(true, false);
        Application__c statusRead = DealerPortalController.getApplicationStatus(c.app.Id);
        assertNoEngineKeys(JSON.serialize(statusRead), 'flag-off shell status read');
        System.assertEquals(true, DealerPortalController.hasTireRimPackages(c.app.Id),
            'flag-off visibility read returns its plain Boolean (T&R dealer package present)');

        delete [SELECT Id FROM Aprotect_Portal_Settings__c];
    }

    @isTest
    static void testConvertRoundTrip_FlagsParity_NoEngineKeys() {
        // The shell's two modal actions (Save-As-Quote ->
        // convertApplicationToQuote; Convert-to-Application ->
        // convertQuoteToApplication) return byte-identical
        // ApplicationPackageResponse payloads under both flag states, with no
        // engine keys — the container's cross-tab actions are flag-agnostic.
        setFlags(true, false);
        Ctx c = build('C7', 13);

        // Round trip under flags off.
        DealerPortalController.ApplicationPackageResponse offToQuote =
            DealerPortalController.convertApplicationToQuote(c.app.Id);
        System.assertEquals(true, offToQuote.success, 'convert to quote (off) failed: ' + offToQuote.message);
        DealerPortalController.ApplicationPackageResponse offBack =
            DealerPortalController.convertQuoteToApplication(c.app.Id);
        System.assertEquals(true, offBack.success, 'convert back (off) failed: ' + offBack.message);

        // Round trip under flags on (same application, identical responses).
        setFlags(true, true);
        DealerPortalController.ApplicationPackageResponse onToQuote =
            DealerPortalController.convertApplicationToQuote(c.app.Id);
        System.assertEquals(true, onToQuote.success, 'convert to quote (on) failed: ' + onToQuote.message);
        DealerPortalController.ApplicationPackageResponse onBack =
            DealerPortalController.convertQuoteToApplication(c.app.Id);
        System.assertEquals(true, onBack.success, 'convert back (on) failed: ' + onBack.message);

        String offToQuoteSer = JSON.serialize(offToQuote);
        String onToQuoteSer = JSON.serialize(onToQuote);
        System.assertEquals(offToQuoteSer, onToQuoteSer,
            'convert-to-quote response must be byte-identical across flag states');
        System.assertEquals(JSON.serialize(offBack), JSON.serialize(onBack),
            'convert-to-application response must be byte-identical across flag states');
        assertNoEngineKeys(offToQuoteSer, 'convert-to-quote response');
        assertNoEngineKeys(JSON.serialize(offBack), 'convert-to-application response');

        // The envelope state the container reads after each action is the same.
        Application__c statusAfter = DealerPortalController.getApplicationStatus(c.app.Id);
        System.assertEquals('Draft', statusAfter.Application_Status__c, 'round trip restored Draft status');
        assertNoEngineKeys(JSON.serialize(statusAfter), 'status read after convert round trip');

        delete [SELECT Id FROM Aprotect_Portal_Settings__c];
    }

    @isTest
    static void testViewerGates_ReadApexFlags() {
        // Org default: no setting rows => every per-tab viewer gate is false
        // (all LWC cutover code inert). Engine on alone is not enough; the
        // snapshot flag (T5) is the state in which stored line sets exist.
        // The container imports none of these gates and no package read
        // (source-level facts in the class header + run record) — the gates
        // below are the per-tab viewers the container HOSTS, whose payload
        // surfaces each prior unit parity-pinned.
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

        // Leave the org in the flag-off baseline state (zero rows).
        delete [SELECT Id FROM Aprotect_Portal_Settings__c];
    }
}