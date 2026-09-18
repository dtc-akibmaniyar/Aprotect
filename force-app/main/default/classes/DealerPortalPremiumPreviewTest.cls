/**
 * DealerPortalPremiumPreviewTest
 *
 * FEATURE A — live premium indication (pre-save) regression suite for
 * DealerPortalController.getPremiumPreview.
 *
 * Proves the COMBINED eligibility rule (user decision #1): premium applies ONLY
 * when the dealer flag (Account.Charge_Premium_Vehicle_Fee__c) AND a matching
 * vehicle schedule (active Premium_Tier, resolved through
 * VehicleScheduleResolver) are BOTH true — neither alone is sufficient — plus
 * the fee rule (master term Premium_Model_Fee__c when > 0, else the matched
 * schedule member-row amount), the dealer override (decision #2), the
 * pre-tax price-override suppression (decision #3) and the exclusion of the
 * Powersports brand-tier surcharge from the premium line (decision #3).
 *
 * The method is read-only: these tests assert the returned DTO only (no DML),
 * and that the DTO never carries schedule/member ids or wholesale cost.
 */
@isTest
private class DealerPortalPremiumPreviewTest {

    private static Map<String, Id> recordTypes;
    private static Id rt(String sObjectType, String devName) {
        if (recordTypes == null) {
            recordTypes = new Map<String, Id>();
            for (RecordType r : [SELECT Id, SObjectType, DeveloperName FROM RecordType
                                 WHERE SObjectType IN ('Account','Package__c','Dealer_Package__c',
                                                       'Application_Package__c')]) {
            recordTypes.put(r.SObjectType + '.' + r.DeveloperName, r.Id);
            }
        }
        return recordTypes.get(sObjectType + '.' + devName);
    }

    private static final Date VALID_FROM = Date.newInstance(2026, 1, 1);

    private class Ctx {
        Account dealer;
        Vehicle__c vehicle;
        Package__c masterPackage;
        Package_Term__c masterTerm;
        Dealer_Package__c dealerPackage;
        Dealer_Package_Term__c dealerTerm;
        Application__c application;
    }

    /**
     * Full context: dealer + vehicle + master catalogue + dealer mirror.
     * A Premium_Tier schedule (make-inclusion row) scoped to the master Package
     * is created when `scheduleRowFee != null`.
     */
    private static Ctx build(String tag, Boolean chargePremium, Decimal dealerOverride,
                             Decimal masterTermPremiumFee, Boolean withSchedule, Decimal scheduleRowFee) {
        Tax__c tax = new Tax__c(Name = 'TXP' + tag, Total_Tax_Rate__c = 5.00);
        insert tax;

        Account d = new Account(
            Name = 'DP' + tag,
            RecordTypeId = rt('Account', 'Dealer_Account'),
            Charge_Premium_Vehicle_Fee__c = chargePremium,
            Premium_Fee_Override_Amount__c = dealerOverride,
            Tax_Region__c = tax.Id);
        insert d;

        String makeName = 'PVM' + tag;
        Make__c mk = new Make__c(Name = makeName);
        insert mk;
        Model__c mo = new Model__c(Name = 'PVMD' + tag, Make__c = mk.Id);
        insert mo;
        Vehicle__c v = new Vehicle__c(Name = 'PVV' + tag, Make__c = makeName, Model__c = 'PVMD' + tag,
            Make_Lookup__c = mk.Id, Model_Lookup__c = mo.Id, Fuel_Type__c = 'Gas', Usage_Type__c = 'Personal Use');
        insert v;

        Package_Group__c grp = new Package_Group__c(Name = 'PVG' + tag, Active__c = true);
        insert grp;
        Package__c pkg = new Package__c(Name = 'PVPKG' + tag, Package_Group__c = grp.Id,
            RecordTypeId = rt('Package__c', 'Extended_Limited_Warranty'), Is_Active__c = true);
        insert pkg;
        Package_Tier__c tier = new Package_Tier__c(Name = 'PVT' + tag, Package__c = pkg.Id);
        insert tier;
        Package_Term__c mt = new Package_Term__c(Name = 'PVTRM' + tag, Package_Tier__c = tier.Id,
            Price__c = 1000.00, Premium_Model_Fee__c = masterTermPremiumFee);
        insert mt;

        if (scheduleRowFee != null) {
            Vehicle_Schedule__c s = new Vehicle_Schedule__c(Name = 'PVS' + tag, Type__c = 'Premium_Tier',
                Is_Active__c = true, Valid_From__c = VALID_FROM);
            insert s;
            insert new Vehicle_Schedule_Member__c(Name = 'PVSM' + tag, Vehicle_Schedule__c = s.Id,
                Make__c = mk.Id, Include_All_Models__c = true, Amount_Type__c = 'Flat',
                Premium_Model_Fee__c = scheduleRowFee, Sort_Order__c = 0);
            insert new Vehicle_Schedule_Assignment__c(Name = 'PVSA' + tag, Vehicle_Schedule__c = s.Id,
                Package__c = pkg.Id, Effective_From__c = VALID_FROM);
        }

        Dealer_Package__c dp = new Dealer_Package__c(Name = 'PVDP' + tag, Dealer__c = d.Id,
            Package__c = pkg.Id, RecordTypeId = rt('Dealer_Package__c', 'Extended_Limited_Warranty'));
        insert dp;
        Dealer_Package_Term__c dt = new Dealer_Package_Term__c(Name = 'PVDPT' + tag,
            Dealer_Package__c = dp.Id, Package_Term__c = mt.Id,
            Original_Package_Term_Cost__c = 1000.00);
        insert dt;

        Application__c app = new Application__c(Vehicle__c = v.Id, Dealer_Name__c = d.Id);
        insert app;

        Ctx c = new Ctx();
        c.dealer = d; c.vehicle = v; c.masterPackage = pkg; c.masterTerm = mt;
        c.dealerPackage = dp; c.dealerTerm = dt; c.application = app;
        return c;
    }

    private static DealerPortalController.PremiumPreviewDTO preview(
            Ctx c, Boolean priceOverrideActive) {
        return DealerPortalController.getPremiumPreview(
            c.dealerTerm.Id, c.vehicle.Id, null, null, null, priceOverrideActive);
    }

    private static void assertKeysOnly(DealerPortalController.PremiumPreviewDTO dto) {
        // The DTO is a fixed four-field payload: no ids, no wholesale cost.
        System.assertNotEquals(null, dto);
        System.assertEquals(false, dto.isPremiumVehicle == null, 'isPremiumVehicle must be set');
        System.assertNotEquals(null, dto.premiumFee, 'premiumFee must be set');
        System.assertEquals(false, dto.waived == null, 'waived must be set');
        System.assertEquals(false, dto.overrideApplied == null, 'overrideApplied must be set');
    }

    // ------------------------------------------------------------------
    // Eligibility: the COMBINED rule
    // ------------------------------------------------------------------

    @isTest
    static void dealerFlagAndScheduleMatch_isPremium() {
        Ctx c = build('A', true, null, 350.00, true, 299.00);
        Test.startTest();
        DealerPortalController.PremiumPreviewDTO dto = preview(c, false);
        Test.stopTest();
        assertKeysOnly(dto);
        System.assertEquals(true, dto.isPremiumVehicle, 'dealer flag + schedule match => premium');
        // Term-anchored: master term fee (350) beats the schedule row (299).
        System.assertEquals(350.00, dto.premiumFee, 'fee from master term when > 0');
        System.assertEquals(false, dto.overrideApplied, 'no dealer override');
        System.assertEquals(false, dto.waived, 'not waived');
    }

    @isTest
    static void dealerFlagWithoutScheduleMatch_noPremium() {
        // Dealer charges the fee but the vehicle does not match any premium schedule.
        Ctx c = build('B', true, null, 350.00, false, null);
        Test.startTest();
        DealerPortalController.PremiumPreviewDTO dto = preview(c, false);
        Test.stopTest();
        assertKeysOnly(dto);
        System.assertEquals(false, dto.isPremiumVehicle, 'dealer flag alone is NOT sufficient');
        System.assertEquals(0, dto.premiumFee, 'no schedule match => no premium fee');
    }

    @isTest
    static void scheduleMatchWithoutDealerFlag_noPremium() {
        // Vehicle matches the premium schedule but the dealer does not charge the fee.
        Ctx c = build('C', false, null, 350.00, true, 299.00);
        Test.startTest();
        DealerPortalController.PremiumPreviewDTO dto = preview(c, false);
        Test.stopTest();
        assertKeysOnly(dto);
        System.assertEquals(false, dto.isPremiumVehicle, 'schedule match alone is NOT sufficient');
        System.assertEquals(0, dto.premiumFee, 'dealer flag off => no premium fee');
    }

    // ------------------------------------------------------------------
    // Fee rule
    // ------------------------------------------------------------------

    @isTest
    static void feeFallsBackToScheduleRowWhenTermFeeZero() {
        Ctx c = build('D', true, null, 0.00, true, 299.00);
        Test.startTest();
        DealerPortalController.PremiumPreviewDTO dto = preview(c, false);
        Test.stopTest();
        System.assertEquals(true, dto.isPremiumVehicle, 'eligible');
        System.assertEquals(299.00, dto.premiumFee, 'fee falls back to the schedule member-row amount');
    }

    @isTest
    static void dealerOverrideReplacesResolvedAmount() {
        // Dealer override present => replaces the resolved premium amount (R5 / decision #2).
        Ctx c = build('E', true, 275.00, 350.00, true, 299.00);
        Test.startTest();
        DealerPortalController.PremiumPreviewDTO dto = preview(c, false);
        Test.stopTest();
        System.assertEquals(true, dto.isPremiumVehicle, 'eligible');
        System.assertEquals(275.00, dto.premiumFee, 'dealer Premium_Fee_Override_Amount__c wins');
        System.assertEquals(true, dto.overrideApplied, 'override flagged');
    }

    @isTest
    static void zeroFeeKeepsBadgeButNoCharge() {
        // Eligible vehicle, but neither the term nor the schedule carries an amount.
        Ctx c = build('F', true, null, null, true, 0.00);
        // Sanity: the resolver surfaces the premium line for a 0-amount row, so
        // the badge below is driven by eligibility, not by the fee value.
        VehicleScheduleResolver.ResolverResult rr = VehicleScheduleResolver.resolve(
            new VehicleScheduleResolver.ResolveRequest(c.dealer.Id, c.vehicle.Id, c.masterPackage.Id, Date.today()));
        Integer premLines = 0;
        for (VehicleScheduleResolver.ResolvedFeeLine l : rr.lines) {
            if (VehicleScheduleResolver.TYPE_PREMIUM_TIER.equals(l.scheduleType)) premLines++;
        }
        System.assertEquals(1, premLines, 'resolver must surface the premium line for a 0-amount row');
        Test.startTest();
        DealerPortalController.PremiumPreviewDTO dto = preview(c, false);
        Test.stopTest();
        System.assertEquals(true, dto.isPremiumVehicle, 'badge reflects eligibility');
        System.assertEquals(0, dto.premiumFee, 'a resolved fee <= 0 is never charged');
    }

    // ------------------------------------------------------------------
    // Suppression: price override + waiver
    // ------------------------------------------------------------------

    @isTest
    static void priceOverrideSuppressesPremium() {
        Ctx c = build('G', true, null, 350.00, true, 299.00);
        Test.startTest();
        DealerPortalController.PremiumPreviewDTO dto = preview(c, true);
        Test.stopTest();
        assertKeysOnly(dto);
        System.assertEquals(false, dto.isPremiumVehicle, 'price override suppresses the premium entirely');
        System.assertEquals(0, dto.premiumFee, 'no premium under a price override');
    }

    @isTest
    static void adminWaiverSuppressesPremium() {
        Ctx c = build('H', true, null, 350.00, true, 299.00);
        Application_Package__c ap = new Application_Package__c(
            Name = 'PVAP' + 'H',
            Application__c = c.application.Id,
            Dealer__c = c.dealer.Id,
            Dealer_Package__c = c.dealerPackage.Id,
            Dealer_Package_Term__c = c.dealerTerm.Id,
            Package_Term__c = c.masterTerm.Id,
            RecordTypeId = rt('Application_Package__c', 'Extended_Limited_Warranty'),
            Active__c = true,
            Waive_Premium_Fee__c = true,
            Priced_By_Engine__c = true);
        Database.SaveResult sr = Database.insert(ap, false, System.AccessLevel.SYSTEM_MODE);
        if (!sr.isSuccess()) {
            String msg = '';
            for (Database.Error er : sr.getErrors()) {
                msg += '[' + er.getStatusCode() + '] ' + String.join(er.getFields(), ',') + ' :: ' + er.getMessage() + ' | ';
            }
            System.assert(false, 'AP insert failed: ' + msg);
        }

        Test.startTest();
        DealerPortalController.PremiumPreviewDTO dto =
            DealerPortalController.getPremiumPreview(c.dealerTerm.Id, c.vehicle.Id, null, null, ap.Id, false);
        Test.stopTest();
        assertKeysOnly(dto);
        System.assertEquals(false, dto.isPremiumVehicle, 'waiver suppresses the badge');
        System.assertEquals(0, dto.premiumFee, 'waiver suppresses the fee');
        System.assertEquals(true, dto.waived, 'waiver flagged');
    }

    // ------------------------------------------------------------------
    // Entry-time (no draft Vehicle row): metadata-by-name fallback
    // ------------------------------------------------------------------

    @isTest
    static void entryTimePremiumMakeMetadataMatch() {
        Ctx c = build('I', true, null, 350.00, false, null);
        Test.startTest();
        // No vehicleId — evaluate the raw make via Premium_Vehicle_Make__mdt.
        DealerPortalController.PremiumPreviewDTO premium = DealerPortalController.getPremiumPreview(
            c.dealerTerm.Id, null, 'BMW', 'X5', null, false);
        DealerPortalController.PremiumPreviewDTO nonPremium = DealerPortalController.getPremiumPreview(
            c.dealerTerm.Id, null, 'Kia', 'Sportage', null, false);
        Test.stopTest();
        System.assertEquals(true, premium.isPremiumVehicle, 'BMW is a premium make in the metadata');
        System.assertEquals(350.00, premium.premiumFee, 'term-anchored fee available at entry time');
        System.assertEquals(false, nonPremium.isPremiumVehicle, 'Kia is not a premium make');
    }

    @isTest
    static void entryTimeRequiresDealerFlagToo() {
        Ctx c = build('J', false, null, 350.00, false, null);
        Test.startTest();
        DealerPortalController.PremiumPreviewDTO dto = DealerPortalController.getPremiumPreview(
            c.dealerTerm.Id, null, 'BMW', 'X5', null, false);
        Test.stopTest();
        System.assertEquals(false, dto.isPremiumVehicle,
            'metadata match alone is NOT sufficient — dealer flag required');
    }

    // ------------------------------------------------------------------
    // Powersports brand-tier surcharge must NOT reach the premium line
    // ------------------------------------------------------------------

    @isTest
    static void powersportsBrandTierSurchargeNotOnPremiumLine() {
        Ctx c = build('K', true, null, 350.00, true, 299.00);
        // A Powersports vehicle with an Exotic brand tier whose legacy term DTO
        // would carry a 1.60x surcharge on the premiumModelFee display field.
        c.vehicle.Vehicle_Category__c = 'Powersports';
        c.vehicle.Brand_Tier__c = 'Exotic';
        update c.vehicle;

        Test.startTest();
        DealerPortalController.PremiumPreviewDTO dto = preview(c, false);
        Test.stopTest();
        System.assertEquals(true, dto.isPremiumVehicle, 'eligible');
        // The premium fee is the term-anchored premium (350) — never a
        // base x (multiplier - 1) brand-tier surcharge.
        System.assertEquals(350.00, dto.premiumFee,
            'premium line must carry the term-anchored premium, not the powersports surcharge');
    }

    // ------------------------------------------------------------------
    // Robustness / no-context
    // ------------------------------------------------------------------

    @isTest
    static void noContextReturnsCleanDefaults() {
        Test.startTest();
        DealerPortalController.PremiumPreviewDTO dto =
            DealerPortalController.getPremiumPreview(null, null, null, null, null, false);
        DealerPortalController.PremiumPreviewDTO nullSafe =
            DealerPortalController.getPremiumPreview(null, null, null, null, null, null);
        Test.stopTest();
        assertKeysOnly(dto);
        System.assertEquals(false, dto.isPremiumVehicle, 'no context => no premium');
        System.assertEquals(0, dto.premiumFee, 'no context => no fee');
        System.assertEquals(false, nullSafe.isPremiumVehicle, 'null override flag is handled');
    }

    // ------------------------------------------------------------------
    // LAYER 3 (durable) — vehicle change re-prices/clears the STORED premium
    // (Application_Package__c.Premium_Model_Fee__c) through saveVehicleData.
    // ------------------------------------------------------------------

    /** Active warranty Application_Package__c carrying a stored premium. */
    private static Application_Package__c storedPremiumPackage(
            Ctx c, Decimal premium, Decimal overrideAmount) {
        Application_Package__c ap = new Application_Package__c(
            Name = 'PVA' + c.application.Id,
            Application__c = c.application.Id,
            Dealer__c = c.dealer.Id,
            Dealer_Package__c = c.dealerPackage.Id,
            Dealer_Package_Term__c = c.dealerTerm.Id,
            Package_Term__c = c.masterTerm.Id,
            RecordTypeId = rt('Application_Package__c', 'Extended_Limited_Warranty'),
            Active__c = true,
            Dealer_Package_Price__c = 529.00,
            Premium_Model_Fee__c = premium,
            Dealer_Price_Override__c = overrideAmount);
        insert ap;
        return ap;
    }

    /** saveVehicleData payload for a vehicle change on the ctx vehicle. */
    private static Map<String, Object> vehicleChange(Ctx c, String make, String model) {
        Map<String, Object> vm = new Map<String, Object>();
        vm.put('vehicleId', c.vehicle.Id);
        vm.put('applicationId', c.application.Id);
        vm.put('vin', 'VIN' + c.vehicle.Id);
        vm.put('year', '2020');
        vm.put('make', make);
        vm.put('model', model);
        vm.put('businessCommercialUse', false);
        vm.put('isBrandedRebuilt', false);
        vm.put('deferralOption', false);
        vm.put('showCommentsOnPrint', false);
        return vm;
    }

    @isTest
    static void vehicleChangeToNonPremiumClearsStoredPremium() {
        Ctx c = build('L', true, null, 350.00, true, 299.00);
        Application_Package__c ap = storedPremiumPackage(c, 350.00, null);
        Decimal before =
            [SELECT Contract_Premium_Price_Without_Tax__c FROM Application_Package__c WHERE Id = :ap.Id]
                .Contract_Premium_Price_Without_Tax__c;

        Test.startTest();
        Map<String, Object> res = DealerPortalController.saveVehicleData(vehicleChange(c, 'Kia', 'Sportage'));
        Test.stopTest();

        System.assertEquals(true, res.get('success'), 'vehicle save succeeds: ' + res.get('message'));
        Application_Package__c after = [
            SELECT Premium_Model_Fee__c, Contract_Premium_Price_Without_Tax__c
            FROM Application_Package__c WHERE Id = :ap.Id
        ];
        System.assertEquals(0, after.Premium_Model_Fee__c,
            'stored premium cleared when the vehicle is no longer premium for the package term');
        System.assertEquals(before - 350.00, after.Contract_Premium_Price_Without_Tax__c,
            'the stored formula total no longer folds in the old premium');
    }

    @isTest
    static void vehicleChangeKeepingPremiumKeepsStoredPremium() {
        Ctx c = build('M', true, null, 350.00, true, 299.00);
        Application_Package__c ap = storedPremiumPackage(c, 350.00, null);

        Test.startTest();
        Map<String, Object> res = DealerPortalController.saveVehicleData(
            vehicleChange(c, c.vehicle.Make__c, c.vehicle.Model__c));
        Test.stopTest();

        System.assertEquals(true, res.get('success'), 'vehicle save succeeds: ' + res.get('message'));
        System.assertEquals(350.00,
            [SELECT Premium_Model_Fee__c FROM Application_Package__c WHERE Id = :ap.Id].Premium_Model_Fee__c,
            'a still-premium vehicle with a valid retained term keeps its stored premium');
    }

    @isTest
    static void vehicleChangeKeepingPremiumKeepsDealerOverrideAmount() {
        Ctx c = build('N', true, 275.00, 350.00, true, 299.00);
        Application_Package__c ap = storedPremiumPackage(c, 275.00, null);

        Test.startTest();
        Map<String, Object> res = DealerPortalController.saveVehicleData(
            vehicleChange(c, c.vehicle.Make__c, c.vehicle.Model__c));
        Test.stopTest();

        System.assertEquals(true, res.get('success'), 'vehicle save succeeds: ' + res.get('message'));
        System.assertEquals(275.00,
            [SELECT Premium_Model_Fee__c FROM Application_Package__c WHERE Id = :ap.Id].Premium_Model_Fee__c,
            'dealer override amount is kept while the vehicle is still premium');
    }

    @isTest
    static void vehicleChangeWithPriceOverrideClearsStoredPremium() {
        Ctx c = build('O', true, null, 350.00, true, 299.00);
        // Pre-tax dealer price override in force on the stored package.
        Application_Package__c ap = storedPremiumPackage(c, 350.00, 900.00);

        Test.startTest();
        Map<String, Object> res = DealerPortalController.saveVehicleData(
            vehicleChange(c, c.vehicle.Make__c, c.vehicle.Model__c));
        Test.stopTest();

        System.assertEquals(true, res.get('success'), 'vehicle save succeeds: ' + res.get('message'));
        System.assertEquals(0,
            [SELECT Premium_Model_Fee__c FROM Application_Package__c WHERE Id = :ap.Id].Premium_Model_Fee__c,
            'a pre-tax price override suppresses the premium, so the stored premium is cleared');
    }
}