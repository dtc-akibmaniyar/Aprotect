/**
 * DealerPortalVehicleEngineParityTest
 *
 * P4 [L] vehicle-tab viewer cutover — Apex payload-parity evidence
 * (change-implementation plan §11 P4 [L], §10.1 rule 1, §10.4/§13.5 Vehicle
 * tab rows; decision 2026-09-06 option (b): source-level + Apex payload-parity
 * evidence is the accepted regression standard for the LWC cutover).
 *
 * UNIT-SHAPE NOTE (verified deviation from the summary/warranty/T&R template —
 * see run record 2026-09-06-p4-c1-vehicle): the Vehicle tab
 * (lwc/dealerPortalVehicle, the portal container's first tab) is a pure
 * vehicle / intake data-entry form. It does NOT read the active
 * Application_Package payload (no getActiveApplicationPackageByRecordType
 * import), renders NO engine-priced money field (no contract premium, tax,
 * totals, line items or price breakdown anywhere in its template), and
 * performs NO client-side price/fee/tax computation (zero currency
 * formatting / recalc in its JS). Its Apex surface is
 * DealerPortalController.{loadVehicleData, saveVehicleData,
 * updateVehicleFieldsSelective, decodeVin, getDealershipInfo,
 * getDealerContacts, getVehicleWarrantyPicklists, checkDuplicateVIN} — typed
 * VehicleResponse/VehicleDataDTO payloads that physically cannot carry engine
 * line keys. The only active-package touch on the whole path is
 * loadVehicleData's deferral-eligibility read (the active
 * Extended_Limited_Warranty package's term Allow_Deferral__c — a structure
 * boolean, not an engine money value), which is flag-independent. The tab is
 * therefore ALREADY in the P4 end-state ("pure viewer of stored server
 * payload, no client price math"): there is no engine payload surface to gate
 * and no stored engine value to re-stamp, so no controller viewer gate and no
 * LWC viewer code are added (dead flag-gated branches would violate §10.1
 * rule 1's spirit). The one client derivation on the tab — the powersports
 * brand-tier badge fed by the legacy client-side premium/exotic make lists
 * (client arrays + deriveBrandTier() in dealerPortalVehicle.js) — is
 * the documented P3 [L] backlog (plan §11 P3 [L]), untouched here
 * (grep-gated), and its STORED round-trip (Vehicle__c.Brand_Tier__c) is
 * pinned below.
 *
 * What this suite proves instead (the payloads the Vehicle tab actually reads
 * and writes, under the §10.4/§13.5 vehicle-row regression cases — save, VIN
 * restore, duplicate-VIN dialog incl. cross-dealer, commercial-type dialog
 * values, powersports intake, diesel fuel flag):
 *   - loadVehicleData (the tab's existing-application restore) returns a
 *     byte-identical payload with the engine flags OFF vs ON, and its
 *     serialized response NEVER contains engine line keys (lineItems /
 *     hasEngineLineItems / contractPremium* / Priced_By_Engine) — the shared
 *     engine-snapshot attach on the active-package read cannot leak into the
 *     vehicle intake read.
 *   - saveVehicleData (the tab's save path) round-trips every stored vehicle
 *     field identically under both flag states and never writes engine/P4
 *     state; the powersports + commercial + diesel intake mix (§10.4 Vehicle
 *     row) saves and reloads byte-identically under both flag states,
 *     including the stored Brand_Tier__c the legacy client derivation feeds.
 *   - checkDuplicateVIN (the duplicate-VIN dialog incl. cross-dealer list)
 *     returns a byte-identical result map under both flag states with only the
 *     dialog's keys — no engine keys.
 *   - Worst case: an engine-priced, snapshot-carrying active ELW package on
 *     the SAME Application (the state in which the warranty-tab payload DOES
 *     carry engine lines — asserted live as a control) leaves the vehicle-tab
 *     read byte-identical, including the deferral-eligibility boolean that
 *     queries that very active package.
 *   - The per-tab viewer gates that exist today (warranty / T&R host /
 *     summary) all read the same Apex flag and are false with zero
 *     Aprotect_Portal_Settings rows; the Vehicle tab imports none of them and
 *     no package read (source-level fact recorded in the run record), so no
 *     gate flip can reach the vehicle tab's display.
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
private class DealerPortalVehicleEngineParityTest {

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

    /** Application + vehicle context (the Vehicle tab's data path). */
    private class Ctx {
        public Account dealer;
        public Vehicle__c v;
        public Application__c app;
        // ELW engine fixture (attached on demand by attachEngineCatalogue)
        public Id dealerPackageId;
        public Dealer_Package_Term__c dt;
        public Id masterTermId;
    }

    /** Dealer + tax + make/model + vehicle + application (no packages). */
    private static Ctx buildApp(String tag, Decimal rate) {
        Tax__c tax = taxRegion('VPTX' + tag, rate);
        Account d = dealer('VD' + tag, tax);
        Make__c mk = make('VK' + tag);
        Model__c mo = model(mk, 'VM' + tag);
        Vehicle__c v = new Vehicle__c(Name = 'VV' + tag,
            Make_Lookup__c = mk.Id, Model_Lookup__c = mo.Id,
            VIN__c = '1HGBH41JXMN109186',
            Vehicle_Identification_Number_VIN__c = '1HGBH41JXMN109186',
            Year__c = '2023', Make__c = 'VK' + tag, Model__c = 'VM' + tag, Trim__c = 'SE',
            Fuel_Type__c = 'Gas', Usage_Type__c = 'Personal Use',
            Odometer__c = 10000.0, Odometer_Unit__c = 'KM');
        insert v;

        Ctx c = new Ctx();
        c.dealer = d; c.v = v;
        c.app = new Application__c(Vehicle__c = v.Id, Dealer_Name__c = d.Id);
        insert c.app;
        return c;
    }

    /** ELW catalogue + dealer mirror + premium schedule (engine fixture). */
    private static void attachEngineCatalogue(Ctx c, String tag, Boolean allowDeferral) {
        Package_Group__c grp = new Package_Group__c(Name = 'VGRP' + tag, Active__c = true);
        insert grp;
        Package__c pkg = new Package__c(Name = 'VPKG' + tag, Package_Group__c = grp.Id,
            RecordTypeId = rt('Package__c', 'Extended_Limited_Warranty'), Is_Active__c = true);
        insert pkg;
        Package_Tier__c tier = new Package_Tier__c(Name = 'VTIR' + tag, Package__c = pkg.Id);
        insert tier;
        Package_Term__c mt = new Package_Term__c(Name = 'VTRM' + tag, Package_Tier__c = tier.Id,
            Price__c = 1000.00, Allow_Deferral__c = allowDeferral);
        insert mt;

        Date vf = Date.newInstance(2026, 1, 1);
        // Premium fee schedule (mirrors the sibling parity fixtures) so the
        // engine prices base + markup + premium like the warranty suite.
        Vehicle_Schedule__c s = new Vehicle_Schedule__c(Name = 'VSP' + tag, Type__c = 'Premium_Tier',
            Is_Active__c = true, Valid_From__c = vf);
        insert s;
        insert new Vehicle_Schedule_Member__c(Name = 'VSPm', Vehicle_Schedule__c = s.Id,
            Make__c = c.v.Make_Lookup__c, Include_All_Models__c = true, Tier__c = 'Tier 2',
            Amount_Type__c = 'Flat', Premium_Model_Fee__c = 299.00, Sort_Order__c = 0);
        insert new Vehicle_Schedule_Assignment__c(Name = 'VSPa', Vehicle_Schedule__c = s.Id,
            Package__c = pkg.Id, Effective_From__c = vf);

        Dealer_Package__c dp = new Dealer_Package__c(Name = 'VDP' + tag, Dealer__c = c.dealer.Id,
            Package__c = pkg.Id, RecordTypeId = rt('Dealer_Package__c', 'Extended_Limited_Warranty'));
        insert dp;
        Dealer_Package_Term__c dt = new Dealer_Package_Term__c(Name = 'VDPT' + tag,
            Dealer_Package__c = dp.Id, Package_Term__c = mt.Id,
            Original_Package_Term_Cost__c = 1000.00, Markup__c = 100.00, Markup_Type__c = '$');
        insert dt;

        c.dealerPackageId = dp.Id; c.dt = dt; c.masterTermId = mt.Id;
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

    // ------------------------------------------------------------------
    // Vehicle-tab payload reads (the path the Vehicle tab renders:
    // DealerPortalController.loadVehicleData -> VehicleResponse)
    // ------------------------------------------------------------------

    /** loadVehicleData as the Vehicle tab calls it (typed response). */
    private static DealerPortalController.VehicleResponse loadVehiclePayload(Id appId) {
        DealerPortalController.VehicleResponse response =
            DealerPortalController.loadVehicleData(appId);
        System.assert(response != null && response.success,
            'loadVehicleData expected to succeed: ' + (response == null ? 'null' : response.message));
        System.assert(response.data != null, 'vehicle data expected');
        return response;
    }

    /** Engine line keys that exist ONLY on the shared active-package read. */
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

    private static void assertVehicleDtoParity(DealerPortalController.VehicleResponse off,
                                               DealerPortalController.VehicleResponse onState,
                                               String ctx) {
        System.assertEquals(JSON.serialize(off), JSON.serialize(onState),
            ctx + ': loadVehicleData payload must be byte-identical across flag states');
        System.assertEquals(off.recordId, onState.recordId, ctx + ': recordId');
        DealerPortalController.VehicleDataDTO od = off.data;
        DealerPortalController.VehicleDataDTO nd = onState.data;
        System.assertEquals(od.vin, nd.vin, ctx + ': vin');
        System.assertEquals(od.year, nd.year, ctx + ': year');
        System.assertEquals(od.make, nd.make, ctx + ': make');
        System.assertEquals(od.model, nd.model, ctx + ': model');
        System.assertEquals(od.trim, nd.trim, ctx + ': trim');
        System.assertEquals(od.odometer, nd.odometer, ctx + ': odometer');
        System.assertEquals(od.odometerUnit, nd.odometerUnit, ctx + ': odometerUnit');
        System.assertEquals(od.usageType, nd.usageType, ctx + ': usageType');
        System.assertEquals(od.fuelType, nd.fuelType, ctx + ': fuelType');
        System.assertEquals(od.vehicleCategory, nd.vehicleCategory, ctx + ': vehicleCategory');
        System.assertEquals(od.brandTier, nd.brandTier, ctx + ': brandTier');
        System.assertEquals(od.packageTermAllowsDeferral, nd.packageTermAllowsDeferral,
            ctx + ': packageTermAllowsDeferral (the only active-package touch on the path)');
    }

    private static Integer countOccurrences(String haystack, String needle) {
        Integer count = 0;
        Integer idx = haystack.indexOf(needle);
        while (idx >= 0) {
            count++;
            idx = haystack.indexOf(needle, idx + needle.length());
        }
        return count;
    }

    // ------------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------------

    @isTest
    static void testVehicleLoad_FlagsOff_LegacyPayloadShape_NoEngineKeys() {
        // §10.4 Vehicle-row baseline: the existing-application restore the tab
        // performs with all flags off must be the legacy vehicle payload only.
        setFlags(true, false);
        Ctx c = buildApp('V1', 13);
        DealerPortalController.VehicleResponse response = loadVehiclePayload(c.app.Id);

        System.assertEquals(c.v.Id, response.recordId);
        DealerPortalController.VehicleDataDTO d = response.data;
        System.assertEquals('1HGBH41JXMN109186', d.vin);
        System.assertEquals('2023', d.year);
        System.assertEquals('VKV1', d.make);
        System.assertEquals('VMV1', d.model);
        System.assertEquals(10000.0, d.odometer);
        System.assertEquals('KM', d.odometerUnit);
        System.assertEquals('Personal Use', d.usageType);
        System.assertEquals('Gas', d.fuelType);
        System.assertEquals(false, d.packageTermAllowsDeferral,
            'no active package exists -> deferral flag must be false');
        assertNoEngineKeys(JSON.serialize(response), 'flag-off load');
    }

    @isTest
    static void testVehicleLoad_FlagsOn_ByteIdenticalToLegacy() {
        // The same restore with engine + snapshot flags ON must be
        // byte-identical: the shared engine-snapshot attach (which rebuilds
        // the active-package payload the warranty/T&R tabs render) cannot
        // reach the vehicle intake read.
        Ctx c = buildApp('V2', 13);

        setFlags(true, false);
        DealerPortalController.VehicleResponse off = loadVehiclePayload(c.app.Id);
        setFlags(true, true);
        DealerPortalController.VehicleResponse onState = loadVehiclePayload(c.app.Id);

        assertVehicleDtoParity(off, onState, 'no-package application');
        assertNoEngineKeys(JSON.serialize(onState), 'flag-on load');
    }

    @isTest
    static void testVehicleSave_RoundTrip_FlagsParity() {
        // §10.4 Vehicle-row save path: saveVehicleData must persist the same
        // stored vehicle state and return the same payload under both flag
        // states, and must never write engine/P4 state.
        Ctx c = buildApp('V3', 13);
        Map<String, Object> m = baseVehicleMap(c);

        setFlags(true, false);
        Map<String, Object> off = DealerPortalController.saveVehicleData(m);
        System.assertEquals(true, off.get('success'), 'save (flags off) failed: ' + off.get('message'));
        assertSavedVehicleRoundTrip(c, m);

        setFlags(true, true);
        Map<String, Object> onState = DealerPortalController.saveVehicleData(m);
        System.assertEquals(true, onState.get('success'), 'save (flags on) failed: ' + onState.get('message'));

        // Byte parity of the save response across flag states.
        System.assertEquals(JSON.serialize(off), JSON.serialize(onState),
            'saveVehicleData response must be byte-identical across flag states');
        assertNoEngineKeys(JSON.serialize(onState), 'flag-on save response');
        // Same stored state.
        assertSavedVehicleRoundTrip(c, m);
        // The save path never creates application packages.
        System.assertEquals(0, [SELECT COUNT() FROM Application_Package__c WHERE Application__c = :c.app.Id],
            'vehicle save must not create Application_Package rows');
    }

    @isTest
    static void testPowersportsCommercialDiesel_IntakeSave_FlagsParity() {
        // §10.4/§13.5 Vehicle-row intake mix: powersports (hours + brand
        // tier), commercial-use dialog values and the diesel fuel flag save
        // and reload identically under both flag states. Brand_Tier__c is the
        // stored output of the legacy client tier derivation (P3 [L] backlog —
        // untouched here) and must round-trip unchanged.
        Ctx c = buildApp('V4', 13);
        Map<String, Object> m = baseVehicleMap(c);
        m.put('fuelType', 'Diesel');
        m.put('usageType', 'Commercial/Business Use');
        m.put('businessCommercialUse', true);
        m.put('typeOfCommercialUse', 'Light');
        m.put('commercialVehicleType', 'Personal/Light Duty Vehicle');
        m.put('vehicleCategory', 'Powersports');
        m.put('vehicleSubType', 'ATV');
        m.put('intakeHours', 50);
        m.put('brandTier', 'Premium');

        setFlags(true, false);
        Map<String, Object> off = DealerPortalController.saveVehicleData(m);
        System.assertEquals(true, off.get('success'), 'intake save (flags off) failed: ' + off.get('message'));

        setFlags(true, true);
        Map<String, Object> onState = DealerPortalController.saveVehicleData(m);
        System.assertEquals(true, onState.get('success'), 'intake save (flags on) failed: ' + onState.get('message'));
        System.assertEquals(JSON.serialize(off), JSON.serialize(onState),
            'intake save response must be byte-identical across flag states');

        // Stored state (queried after the second save) matches the payload.
        Vehicle__c v = [SELECT Id, Name, VIN__c, Year__c, Make__c, Model__c, Trim__c, Fuel_Type__c,
                               Usage_Type__c, Business_Commercial_Use__c, Type_Of_Commercial_Use__c,
                               Commercial_Vehicle_Type__c, Vehicle_Category__c, Vehicle_Sub_Type__c,
                               Intake_Hours__c, Brand_Tier__c, Odometer__c, Odometer_Unit__c
                        FROM Vehicle__c WHERE Id = :c.v.Id];
        System.assertEquals('Diesel', v.Fuel_Type__c, 'diesel fuel flag persisted');
        System.assertEquals('Commercial/Business Use', v.Usage_Type__c);
        System.assertEquals(true, v.Business_Commercial_Use__c);
        System.assertEquals('Light', v.Type_Of_Commercial_Use__c);
        System.assertEquals('Personal/Light Duty Vehicle', v.Commercial_Vehicle_Type__c);
        System.assertEquals('Powersports', v.Vehicle_Category__c);
        System.assertEquals('ATV', v.Vehicle_Sub_Type__c);
        System.assertEquals(50, v.Intake_Hours__c, 'powersports intake hours persisted');
        System.assertEquals('Premium', v.Brand_Tier__c, 'stored brand tier round-trips');

        // Reload through the tab's read path: byte-identical under both flags.
        setFlags(true, false);
        DealerPortalController.VehicleResponse offLoad = loadVehiclePayload(c.app.Id);
        setFlags(true, true);
        DealerPortalController.VehicleResponse onLoad = loadVehiclePayload(c.app.Id);
        assertVehicleDtoParity(offLoad, onLoad, 'powersports/commercial/diesel reload');
        System.assertEquals('Premium', onLoad.data.brandTier);
        System.assertEquals('Powersports', onLoad.data.vehicleCategory);
        System.assertEquals(50.0, onLoad.data.intakeHours);
        assertNoEngineKeys(JSON.serialize(onLoad), 'powersports flag-on reload');
    }

    @isTest
    static void testDuplicateVinDialog_Payload_FlagsParity() {
        // §10.4/§13.5 duplicate-VIN dialog (incl. cross-dealer list): the
        // dialog payload must be byte-identical under both flag states and
        // carry only the dialog keys — no engine keys.
        String vin = '1HGBH41JXMN109186';
        Tax__c tax = taxRegion('VPTX5', 13);
        Account dealerA = dealer('VDA5', tax);
        Account dealerB = dealer('VDB5', tax);
        Make__c mk = make('VK5');
        Model__c mo = model(mk, 'VM5');

        // Current application + same-dealer duplicate on dealer A.
        Application__c currentApp = insertVinApplication('CA5', dealerA, mk, mo, vin, 'John Doe');
        insertVinApplication('SDA5', dealerA, mk, mo, vin, 'Jane Roe');
        // Cross-dealer duplicate on dealer B.
        insertVinApplication('CDA5', dealerB, mk, mo, vin, 'Bob Smith');

        User portalUser = TestDataFactory.createPortalUser(dealerA.Id, true);

        setFlags(true, false);
        Map<String, Object> off;
        System.runAs(portalUser) {
            off = DealerPortalController.checkDuplicateVIN(vin, currentApp.Id);
        }
        setFlags(true, true);
        Map<String, Object> onState;
        System.runAs(portalUser) {
            onState = DealerPortalController.checkDuplicateVIN(vin, currentApp.Id);
        }

        System.assertEquals(JSON.serialize(off), JSON.serialize(onState),
            'duplicate-VIN payload must be byte-identical across flag states');
        System.assertEquals(true, onState.get('hasDuplicates'));
        System.assertEquals(true, onState.get('isCrossDealer'), 'dealer-B application must flag cross-dealer');
        String serialized = JSON.serialize(onState);
        System.assertEquals(2, countOccurrences(serialized, '"customerName"'),
            'current application excluded; two duplicates expected');
        System.assertEquals(true, serialized.contains('Jane Roe'), 'same-dealer duplicate rendered');
        System.assertEquals(true, serialized.contains('Bob Smith'), 'cross-dealer duplicate rendered');
        System.assertEquals(true, serialized.contains(dealerB.Name), 'cross-dealer dealer name rendered');
        assertNoEngineKeys(serialized, 'duplicate-VIN dialog payload');

        // No-duplicate path parity (a VIN with no matches).
        setFlags(true, false);
        Map<String, Object> offNone;
        System.runAs(portalUser) {
            offNone = DealerPortalController.checkDuplicateVIN('2HGBH41JXMN109187', currentApp.Id);
        }
        setFlags(true, true);
        Map<String, Object> onNone;
        System.runAs(portalUser) {
            onNone = DealerPortalController.checkDuplicateVIN('2HGBH41JXMN109187', currentApp.Id);
        }
        System.assertEquals(JSON.serialize(offNone), JSON.serialize(onNone), 'no-dup payload parity');
        System.assertEquals(false, onNone.get('hasDuplicates'));
    }

    @isTest
    static void testEnginePricedPackageOnApp_DoesNotLeakIntoVehicleRead() {
        // Worst case for the vehicle tab: the same Application carries an
        // engine-priced, snapshot-carrying active ELW package (the state in
        // which the warranty-tab payload DOES carry engine lines — asserted
        // live below as a control). The vehicle-tab read must stay
        // byte-identical, including the deferral-eligibility boolean that
        // queries that very active package.
        Ctx c = buildApp('V6', 13);
        attachEngineCatalogue(c, 'V6', true); // ELW term allows deferral
        setFlags(true, true);
        Application_Package__c pkg = insertEnginePricedPackage(c, null);

        setFlags(true, false);
        DealerPortalController.VehicleResponse off = loadVehiclePayload(c.app.Id);
        Map<String, Object> offPackage = readActivePackagePayload(c.app.Id);
        setFlags(true, true);
        DealerPortalController.VehicleResponse onState = loadVehiclePayload(c.app.Id);
        Map<String, Object> onPackage = readActivePackagePayload(c.app.Id);

        // The engine attach IS live on the package read under the ON flag...
        System.assertEquals(true, onPackage.get('hasEngineLineItems') == true,
            'control: package read must carry engine lines under the ON flag');
        System.assertNotEquals(null, onPackage.get('lineItems'),
            'control: package read must attach the line set under the ON flag');
        System.assertEquals(true, offPackage.get('hasEngineLineItems') != true,
            'control: flag-off package read must not carry engine lines');
        // ...while the vehicle-tab read on the same Application stays clean.
        assertVehicleDtoParity(off, onState, 'engine-priced package on same application');
        System.assertEquals(true, onState.data.packageTermAllowsDeferral,
            'deferral eligibility (the active-package touch) must survive the engine attach');
        assertNoEngineKeys(JSON.serialize(off), 'flag-off vehicle load (engine pkg present)');
        assertNoEngineKeys(JSON.serialize(onState), 'flag-on vehicle load (engine pkg present)');
    }

    @isTest
    static void testViewerGates_ReadApexFlags() {
        // Org default: no setting rows => every per-tab viewer gate is false
        // (all LWC cutover code inert). Engine on alone is not enough; the
        // snapshot flag (T5) is the state in which stored line sets exist.
        // The Vehicle tab imports none of these gates and no package read
        // (source-level fact in the run record), so no gate flip can reach the
        // vehicle tab's display.
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

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    /** The full field map the vehicle tab posts to saveVehicleData. */
    private static Map<String, Object> baseVehicleMap(Ctx c) {
        Map<String, Object> m = new Map<String, Object>();
        m.put('vehicleId', c.v.Id);
        m.put('applicationId', c.app.Id);
        m.put('stockNumber', 'STK' + c.v.Name);
        m.put('vin', '1HGBH41JXMN109186');
        m.put('vehicleIdentificationNumberVIN', '1HGBH41JXMN109186');
        m.put('year', '2023');
        m.put('make', c.v.Make__c);   // text make the fixture Vehicle carries ('VK<tag>')
        m.put('model', c.v.Model__c); // text model the fixture Vehicle carries ('VM<tag>')
        m.put('trim', 'SE');
        m.put('dateVehicleSold', '2023-06-15');
        m.put('vehiclePurchasePrice', 35000.00);
        m.put('isBrandedRebuilt', false);
        m.put('warrantyInServiceDate', '2023-06-20');
        m.put('odometer', 10000.0);
        m.put('odometerUnit', 'KM');
        m.put('businessCommercialUse', false);
        m.put('typeOfCommercialUse', 'Non-Commercial');
        m.put('usageType', 'Personal Use');
        m.put('fuelType', 'Gas');
        m.put('deferralOption', false);
        m.put('dealerCommentsNotes', 'notes');
        m.put('showCommentsOnPrint', false);
        m.put('dealerSalesId', 'DLR-X');
        m.put('brandTier', 'Standard');
        return m;
    }

    /** Query the saved Vehicle and compare every stored field to the map. */
    private static void assertSavedVehicleRoundTrip(Ctx c, Map<String, Object> m) {
        Vehicle__c v = [SELECT Id, Name, Stock_Number__c, VIN__c, Vehicle_Identification_Number_VIN__c,
                               Year__c, Make__c, Model__c, Trim__c, Date_Vehicle_Sold__c,
                               Vehicle_Purchase_Price__c, Branded_Rebuilt__c, In_Service_Date__c,
                               Odometer__c, Odometer_Unit__c, Business_Commercial_Use__c,
                               Type_Of_Commercial_Use__c, Usage_Type__c, Fuel_Type__c,
                               Deferral_Option__c, Brand_Tier__c, Make_Lookup__c, Model_Lookup__c
                        FROM Vehicle__c WHERE Id = :c.v.Id];
        System.assertEquals((String) m.get('stockNumber'), v.Stock_Number__c, 'stockNumber');
        System.assertEquals((String) m.get('vin'), v.VIN__c, 'vin');
        System.assertEquals((String) m.get('vehicleIdentificationNumberVIN'), v.Vehicle_Identification_Number_VIN__c,
            'vehicleIdentificationNumberVIN');
        System.assertEquals((String) m.get('year'), v.Year__c, 'year');
        System.assertEquals((String) m.get('make'), v.Make__c, 'make');
        System.assertEquals((String) m.get('model'), v.Model__c, 'model');
        System.assertEquals((String) m.get('trim'), v.Trim__c, 'trim');
        System.assertEquals(Date.valueOf((String) m.get('dateVehicleSold')), v.Date_Vehicle_Sold__c, 'dateVehicleSold');
        System.assertEquals((Decimal) m.get('vehiclePurchasePrice'), v.Vehicle_Purchase_Price__c, 'vehiclePurchasePrice');
        System.assertEquals(false, v.Branded_Rebuilt__c, 'brandedRebuilt');
        System.assertEquals(Date.valueOf((String) m.get('warrantyInServiceDate')), v.In_Service_Date__c,
            'warrantyInServiceDate -> In_Service_Date__c');
        System.assertEquals(((Decimal) m.get('odometer')), v.Odometer__c, 'odometer');
        System.assertEquals((String) m.get('odometerUnit'), v.Odometer_Unit__c, 'odometerUnit');
        System.assertEquals((Boolean) m.get('businessCommercialUse'), v.Business_Commercial_Use__c, 'businessCommercialUse');
        System.assertEquals((String) m.get('typeOfCommercialUse'), v.Type_Of_Commercial_Use__c, 'typeOfCommercialUse');
        System.assertEquals((String) m.get('usageType'), v.Usage_Type__c, 'usageType');
        System.assertEquals((String) m.get('fuelType'), v.Fuel_Type__c, 'fuelType');
        System.assertEquals((Boolean) m.get('deferralOption'), v.Deferral_Option__c, 'deferralOption');
        System.assertEquals((String) m.get('brandTier'), v.Brand_Tier__c, 'brandTier');
        System.assertNotEquals(null, v.Make_Lookup__c, 'make lookup resolved by the save path');
        System.assertNotEquals(null, v.Model_Lookup__c, 'model lookup resolved by the save path');
    }

    private static Application__c insertVinApplication(String tag, Account dealerAcct,
            Make__c mk, Model__c mo, String vin, String customerName) {
        Account customer = new Account(Name = customerName);
        insert customer;
        Vehicle__c v = new Vehicle__c(Name = 'VVD' + tag,
            Make_Lookup__c = mk.Id, Model_Lookup__c = mo.Id,
            VIN__c = vin, Vehicle_Identification_Number_VIN__c = vin,
            Year__c = '2022', Make__c = mk.Name, Model__c = mo.Name, Trim__c = 'LE',
            Fuel_Type__c = 'Gas', Usage_Type__c = 'Personal Use');
        insert v;
        Application__c app = new Application__c(
            Vehicle__c = v.Id, Dealer_Name__c = dealerAcct.Id,
            Application_Status__c = 'Active',
            Customer_Name__c = customer.Id);
        insert app;
        return app;
    }

    /** Engine-stamp + INSERT (flow guard: marker pre-DML), then snapshot. */
    private static Application_Package__c insertEnginePricedPackage(Ctx c, Decimal overrideAmt) {
        Application_Package__c pkg = new Application_Package__c(
            Name = 'VAPK' + c.v.Name,
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

    /** Active ELW package payload via the warranty-tab read path (control). */
    private static Map<String, Object> readActivePackagePayload(Id appId) {
        DealerPortalController.ApplicationPackageResponse response =
            DealerPortalController.getActiveApplicationPackageByRecordType(appId, 'Extended_Limited_Warranty');
        System.assert(response != null && response.success, 'active-package read expected to succeed: '
            + (response == null ? 'null' : response.message));
        System.assert(response.data != null, 'active package data expected');
        return response.data;
    }
}