/**
 * VehicleScheduleResolverTest
 *
 * P1 unit tests for schedule resolution (change-plan §11 P1 [T]): resolver
 * precedence R1-R6, the Porsche Tier-2/Tier-3 worked example (design §6.3)
 * incl. the GT350 exclusion + Subaru WRX addition rows, dealer override (R5),
 * determinism (R6), no-match => no fee (R4), the D2 Tire & Rim commercial
 * block, diesel-fuel gating, Member_Key maintenance and the preview flag gate.
 *
 * All fixtures are created per test (no @TestSetup) so the org-level engine
 * flag row can be toggled per test. Tests are self-contained — they never rely
 * on seeded org data.
 */
@isTest
private class VehicleScheduleResolverTest {

    // ---------------------------------------------------------------
    // Fixture helpers
    // ---------------------------------------------------------------

    private static Map<String, Id> recordTypes;
    private static Id dealerAccountRtId;

    private static Id rt(String sobjectType, String devName) {
        if (recordTypes == null) {
            recordTypes = new Map<String, Id>();
            for (RecordType rt : [SELECT Id, SObjectType, DeveloperName FROM RecordType
                                  WHERE SObjectType IN ('Account','Package__c','Application__c')]) {
                recordTypes.put(rt.SObjectType + '.' + rt.DeveloperName, rt.Id);
            }
        }
        return recordTypes.get(sobjectType + '.' + devName);
    }

    private static Make__c make(String name) {
        Make__c m = new Make__c(Name = name);
        insert m;
        return m;
    }

    private static Model__c model(Make__c makeRec, String name) {
        Model__c m = new Model__c(Name = name, Make__c = makeRec.Id);
        insert m;
        return m;
    }

    private static Package_Group__c packageGroup(String name) {
        Package_Group__c g = new Package_Group__c(Name = name, Active__c = true);
        insert g;
        return g;
    }

    private static Package__c pkg(String name, Package_Group__c grp, String rtDevName) {
        Package__c p = new Package__c(
            Name = name,
            Package_Group__c = grp.Id,
            RecordTypeId = rt('Package__c', rtDevName),
            Is_Active__c = true
        );
        insert p;
        return p;
    }

    private static Vehicle_Schedule__c schedule(String name, String type, Boolean active,
                                                Date validFrom, Date validTo) {
        Vehicle_Schedule__c s = new Vehicle_Schedule__c(
            Name = name,
            Type__c = type,
            Is_Active__c = active,
            Valid_From__c = validFrom,
            Valid_To__c = validTo
        );
        insert s;
        return s;
    }

    private static Vehicle_Schedule_Member__c member(Vehicle_Schedule__c sched,
                                                      Make__c makeRec, Model__c modelRec,
                                                      Boolean includeAll, Boolean exclusion,
                                                      String tier, Decimal amount,
                                                      String amountType, Decimal multiplier) {
        Vehicle_Schedule_Member__c m = new Vehicle_Schedule_Member__c(
            Name = (makeRec != null ? makeRec.Name : 'ALL') + (modelRec != null ? ' ' + modelRec.Name : ''),
            Vehicle_Schedule__c = sched.Id,
            Make__c = makeRec != null ? makeRec.Id : null,
            Model__c = modelRec != null ? modelRec.Id : null,
            Include_All_Models__c = includeAll,
            Is_Exclusion__c = exclusion,
            Tier__c = tier,
            Premium_Model_Fee__c = amount,
            Amount_Type__c = amountType,
            Multiplier__c = multiplier,
            Sort_Order__c = 0
        );
        insert m; // fires VehicleScheduleMemberTrigger -> Member_Key__c maintained
        return m;
    }

    private static Vehicle_Schedule_Assignment__c assignment(Vehicle_Schedule__c sched,
                                                              Account dealer, Package__c pkgRec,
                                                              Package_Group__c grp,
                                                              Date effFrom, Date effTo) {
        Vehicle_Schedule_Assignment__c a = new Vehicle_Schedule_Assignment__c(
            Name = sched.Name + ' assignment',
            Vehicle_Schedule__c = sched.Id,
            Dealer__c = dealer != null ? dealer.Id : null,
            Package__c = pkgRec != null ? pkgRec.Id : null,
            Package_Group__c = grp != null ? grp.Id : null,
            Effective_From__c = effFrom,
            Effective_To__c = effTo
        );
        insert a;
        return a;
    }

    private static Account dealer(String name, Boolean chargePremium, Decimal overrideAmount) {
        Account a = new Account(
            Name = name,
            RecordTypeId = rt('Account', 'Dealer_Account'),
            Charge_Premium_Vehicle_Fee__c = chargePremium,
            Premium_Fee_Override_Amount__c = overrideAmount
        );
        insert a;
        return a;
    }

    private static Vehicle__c vehicle(String name, Make__c makeRec, Model__c modelRec,
                                      String fuel, String usage) {
        Vehicle__c v = new Vehicle__c(
            Name = name,
            Make_Lookup__c = makeRec != null ? makeRec.Id : null,
            Model_Lookup__c = modelRec != null ? modelRec.Id : null,
            Fuel_Type__c = fuel,
            Usage_Type__c = usage
        );
        insert v;
        return v;
    }

    private static VehicleScheduleResolver.ResolverResult resolve(Account dealerRec,
                                                                  Vehicle__c vehicleRec,
                                                                  Package__c pkgRec) {
        VehicleScheduleResolver.ResolveRequest req = new VehicleScheduleResolver.ResolveRequest(
            dealerRec != null ? dealerRec.Id : null,
            vehicleRec.Id,
            pkgRec != null ? pkgRec.Id : null,
            Date.newInstance(2026, 9, 3)
        );
        return VehicleScheduleResolver.resolve(req);
    }

    private static VehicleScheduleResolver.ResolvedFeeLine lineForType(
        VehicleScheduleResolver.ResolverResult r, String type) {
        for (VehicleScheduleResolver.ResolvedFeeLine l : r.lines) {
            if (type.equals(l.scheduleType)) {
                return l;
            }
        }
        return null;
    }

    private static void setEngineFlag(Boolean enabled) {
        // Org-level hierarchy row; only one can exist per transaction.
        delete [SELECT Id FROM Aprotect_Portal_Settings__c];
        insert new Aprotect_Portal_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Pricing_Engine_Enabled__c = enabled
        );
    }

    // ---------------------------------------------------------------
    // R3 — Porsche worked example (design §6.3): Tier 2 vs Tier 3
    // ---------------------------------------------------------------

    @isTest
    static void testPorscheWorkedExample_Tier2VsTier3() {
        Make__c porsche = make('Porsche');
        Model__c gt3 = model(porsche, '911 GT3');
        Model__c gt3rs = model(porsche, '911 GT3 RS');
        Model__c caymanGt4Rs = model(porsche, 'Cayman GT4 RS');
        Model__c boxster = model(porsche, '718 Boxster');

        Package_Group__c elw = packageGroup('ELW (test)');
        Package__c elwPkg = pkg('ELW Plan (test)', elw, 'Extended_Limited_Warranty');

        Vehicle_Schedule__c premium = schedule('V27 Premium Tiers (test)', 'Premium_Tier', true,
            Date.newInstance(2026, 1, 1), null);
        // Make row: every Porsche not otherwise listed => Tier 2 @ $299
        member(premium, porsche, null, true, false, 'Tier 2', 299.00, 'Flat', null);
        // Model rows: the V27 exotic variants => Tier 3 @ $899 (R3 model over make)
        member(premium, porsche, gt3, false, false, 'Tier 3', 899.00, 'Flat', null);
        member(premium, porsche, gt3rs, false, false, 'Tier 3', 899.00, 'Flat', null);
        member(premium, porsche, caymanGt4Rs, false, false, 'Tier 3', 899.00, 'Flat', null);
        assignment(premium, null, elwPkg, null, Date.newInstance(2026, 1, 1), null);

        Account dealerRec = dealer('Dealer-A test', false, null);

        // 911 GT3 => Tier 3 model row
        Vehicle__c gt3Vehicle = vehicle('Porsche 911 GT3 (test)', porsche, gt3, 'Gas', 'Personal Use');
        VehicleScheduleResolver.ResolverResult r = resolve(dealerRec, gt3Vehicle, elwPkg);
        System.assertEquals(0, r.blocks.size(), 'no blocks expected: ' + r.blocks);
        VehicleScheduleResolver.ResolvedFeeLine line = lineForType(r, 'Premium_Tier');
        System.assertNotEquals(null, line, 'GT3 must resolve a premium line');
        System.assertEquals('Tier 3', line.tier);
        System.assertEquals(899.00, line.amount);
        System.assertEquals(VehicleScheduleResolver.SOURCE_SCHEDULE, line.source);

        // 718 Boxster (no model row) => inherits the Porsche make row Tier 2
        Vehicle__c boxsterVehicle = vehicle('Porsche 718 Boxster (test)', porsche, boxster, 'Gas', 'Personal Use');
        r = resolve(dealerRec, boxsterVehicle, elwPkg);
        line = lineForType(r, 'Premium_Tier');
        System.assertEquals('Tier 2', line.tier);
        System.assertEquals(299.00, line.amount);

        // Cayman GT4 RS + GT3 RS resolve Tier 3 like the GT3
        for (Model__c exotic : new List<Model__c>{ caymanGt4Rs, gt3rs }) {
            Vehicle__c exoticVehicle = vehicle('Porsche exotic (test) ' + exotic.Name, porsche, exotic, 'Gas', 'Personal Use');
            r = resolve(dealerRec, exoticVehicle, elwPkg);
            line = lineForType(r, 'Premium_Tier');
            System.assertEquals('Tier 3', line.tier, exotic.Name + ' must be Tier 3');
            System.assertEquals(899.00, line.amount, exotic.Name);
        }
    }

    // ---------------------------------------------------------------
    // R3 — exclusion row removes the model (GT350); R4 — addition row (WRX)
    // ---------------------------------------------------------------

    @isTest
    static void testGT350ExclusionRemovesModel() {
        Make__c ford = make('Ford');
        Model__c gt350 = model(ford, 'Mustang Shelby GT350');
        Model__c mustang = model(ford, 'Mustang GT');

        Package_Group__c elw = packageGroup('ELW (test ex)');
        Package__c elwPkg = pkg('ELW Plan (test ex)', elw, 'Extended_Limited_Warranty');

        Vehicle_Schedule__c premium = schedule('Premium (test ex)', 'Premium_Tier', true,
            Date.newInstance(2026, 1, 1), null);
        member(premium, ford, null, true, false, 'Tier 1', 199.00, 'Flat', null); // Ford make row
        member(premium, ford, gt350, false, true, null, null, 'Flat', null);      // 'except GT350'
        assignment(premium, null, elwPkg, null, Date.newInstance(2026, 1, 1), null);

        Account dealerRec = dealer('Dealer-A test ex', false, null);

        // GT350 removed from the schedule entirely => no premium fee
        Vehicle__c gt350Vehicle = vehicle('GT350 (test ex)', ford, gt350, 'Gas', 'Personal Use');
        VehicleScheduleResolver.ResolverResult r = resolve(dealerRec, gt350Vehicle, elwPkg);
        System.assertEquals(null, lineForType(r, 'Premium_Tier'), 'GT350 must have no premium fee');

        // Non-excluded Ford model still resolves from the make row
        Vehicle__c mustangVehicle = vehicle('Mustang GT (test ex)', ford, mustang, 'Gas', 'Personal Use');
        r = resolve(dealerRec, mustangVehicle, elwPkg);
        VehicleScheduleResolver.ResolvedFeeLine line = lineForType(r, 'Premium_Tier');
        System.assertNotEquals(null, line);
        System.assertEquals('Tier 1', line.tier);
        System.assertEquals(199.00, line.amount);
    }

    @isTest
    static void testSubaruWRXAdditionRow() {
        Make__c subaru = make('Subaru');
        Model__c wrx = model(subaru, 'WRX');
        Model__c outback = model(subaru, 'Outback');

        Package_Group__c elw = packageGroup('ELW (test add)');
        Package__c elwPkg = pkg('ELW Plan (test add)', elw, 'Extended_Limited_Warranty');

        Vehicle_Schedule__c premium = schedule('Premium (test add)', 'Premium_Tier', true,
            Date.newInstance(2026, 1, 1), null);
        // Subaru has NO make row; the model row adds only the WRX to Tier 1
        member(premium, subaru, wrx, false, false, 'Tier 1', 199.00, 'Flat', null);
        assignment(premium, null, elwPkg, null, Date.newInstance(2026, 1, 1), null);

        Account dealerRec = dealer('Dealer-A test add', false, null);

        Vehicle__c wrxVehicle = vehicle('WRX (test add)', subaru, wrx, 'Gas', 'Personal Use');
        VehicleScheduleResolver.ResolverResult r = resolve(dealerRec, wrxVehicle, elwPkg);
        VehicleScheduleResolver.ResolvedFeeLine line = lineForType(r, 'Premium_Tier');
        System.assertNotEquals(null, line, 'WRX addition row must resolve');
        System.assertEquals('Tier 1', line.tier);
        System.assertEquals(199.00, line.amount);

        // R4: any other Subaru model is not listed => no fee
        Vehicle__c outbackVehicle = vehicle('Outback (test add)', subaru, outback, 'Gas', 'Personal Use');
        r = resolve(dealerRec, outbackVehicle, elwPkg);
        System.assertEquals(null, lineForType(r, 'Premium_Tier'), 'Outback must have no fee (R4)');
        System.assertEquals(0, r.lines.size());
        System.assertEquals(0, r.blocks.size());
    }

    @isTest
    static void testNoMatchNoFee_R4() {
        Make__c toyota = make('Toyota');
        Model__c camry = model(toyota, 'Camry');
        Package_Group__c entry = packageGroup('Entry (test nofee)');
        Package__c entryPkg = pkg('Entry NO PREMIUM (test nofee)', entry, 'Extended_Limited_Warranty');

        // No premium schedule assigned to this plan family at all
        Vehicle__c camryVehicle = vehicle('Camry (test nofee)', toyota, camry, 'Gas', 'Personal Use');
        Account dealerRec = dealer('Dealer-A nofee', false, null);

        VehicleScheduleResolver.ResolverResult r = resolve(dealerRec, camryVehicle, entryPkg);
        System.assertEquals(0, r.lines.size(), 'entry plan with no assignment => no fee');
        System.assertEquals(0, r.blocks.size());
    }

    // ---------------------------------------------------------------
    // R2 — scope precedence: dealer > package > plan type; ties newest Valid_From
    // ---------------------------------------------------------------

    @isTest
    static void testScopePrecedence_R2() {
        Make__c porsche = make('Porsche');
        Model__c cayenne = model(porsche, 'Cayenne');
        Package_Group__c grp = packageGroup('ELW scope (test)');

        // Plan-type-scoped schedule @ $100 (older), superseded by newer group one @ $120
        Vehicle_Schedule__c groupOld = schedule('Group old (test)', 'Premium_Tier', true,
            Date.newInstance(2025, 1, 1), Date.newInstance(2025, 12, 31));
        member(groupOld, porsche, null, true, false, 'Tier 2', 100.00, 'Flat', null);
        assignment(groupOld, null, null, grp, Date.newInstance(2025, 1, 1), Date.newInstance(2025, 12, 31));

        Vehicle_Schedule__c groupNew = schedule('Group new (test)', 'Premium_Tier', true,
            Date.newInstance(2026, 1, 1), null);
        member(groupNew, porsche, null, true, false, 'Tier 2', 120.00, 'Flat', null);
        assignment(groupNew, null, null, grp, Date.newInstance(2026, 1, 1), null);

        // Package-scoped schedule @ $200
        Package__c pkgRec = pkg('ELW pkg (test)', grp, 'Extended_Limited_Warranty');
        Vehicle_Schedule__c packageSched = schedule('Package scoped (test)', 'Premium_Tier', true,
            Date.newInstance(2026, 1, 1), null);
        member(packageSched, porsche, null, true, false, 'Tier 2', 200.00, 'Flat', null);
        assignment(packageSched, null, pkgRec, null, Date.newInstance(2026, 1, 1), null);

        // Dealer-scoped schedule @ $300
        Account dealerRec = dealer('Dealer-B scope (test)', false, null);
        Vehicle_Schedule__c dealerSched = schedule('Dealer scoped (test)', 'Premium_Tier', true,
            Date.newInstance(2026, 1, 1), null);
        member(dealerSched, porsche, null, true, false, 'Tier 2', 300.00, 'Flat', null);
        assignment(dealerSched, dealerRec, null, null, Date.newInstance(2026, 1, 1), null);

        Vehicle__c cayenneVehicle = vehicle('Cayenne scope (test)', porsche, cayenne, 'Gas', 'Personal Use');

        // Dealer wins over package over group
        VehicleScheduleResolver.ResolverResult r = resolve(dealerRec, cayenneVehicle, pkgRec);
        VehicleScheduleResolver.ResolvedFeeLine line = lineForType(r, 'Premium_Tier');
        System.assertEquals(300.00, line.amount, 'dealer-scoped must win');

        // No dealer scope: package beats the group schedules
        Account otherDealer = dealer('Dealer-C scope (test)', false, null);
        r = resolve(otherDealer, cayenneVehicle, pkgRec);
        line = lineForType(r, 'Premium_Tier');
        System.assertEquals(200.00, line.amount, 'package-scoped must win over plan type');

        // Only group scope in play (fresh group package): newest Valid_From wins
        Package__c groupOnlyPkg = pkg('ELW group-only (test)', grp, 'Extended_Limited_Warranty');
        r = resolve(otherDealer, cayenneVehicle, groupOnlyPkg);
        line = lineForType(r, 'Premium_Tier');
        System.assertEquals(120.00, line.amount, 'newest Valid_From wins the tie');
    }

    // ---------------------------------------------------------------
    // R1 — effective & active only
    // ---------------------------------------------------------------

    @isTest
    static void testR1OnlyActiveAndEffectiveSchedulesMatch() {
        Make__c porsche = make('Porsche');
        Model__c cayenne = model(porsche, 'Cayenne');
        Package_Group__c grp = packageGroup('ELW r1 (test)');
        Package__c pkgRec = pkg('ELW r1 pkg (test)', grp, 'Extended_Limited_Warranty');

        // Draft (inactive)
        Vehicle_Schedule__c draft = schedule('Draft (test)', 'Premium_Tier', false,
            Date.newInstance(2026, 1, 1), null);
        member(draft, porsche, null, true, false, 'Tier 2', 50.00, 'Flat', null);
        assignment(draft, null, pkgRec, null, Date.newInstance(2026, 1, 1), null);

        // Expired (window in the past)
        Vehicle_Schedule__c expired = schedule('Expired (test)', 'Premium_Tier', true,
            Date.newInstance(2025, 1, 1), Date.newInstance(2025, 6, 30));
        member(expired, porsche, null, true, false, 'Tier 2', 60.00, 'Flat', null);
        assignment(expired, null, pkgRec, null, Date.newInstance(2025, 1, 1), Date.newInstance(2025, 6, 30));

        // Future-dated (Valid_From after as-of)
        Vehicle_Schedule__c future = schedule('Future (test)', 'Premium_Tier', true,
            Date.newInstance(2027, 1, 1), null);
        member(future, porsche, null, true, false, 'Tier 2', 70.00, 'Flat', null);
        assignment(future, null, pkgRec, null, Date.newInstance(2027, 1, 1), null);

        // Assignment with future Effective_From but active schedule
        Vehicle_Schedule__c active = schedule('Active (test)', 'Premium_Tier', true,
            Date.newInstance(2026, 1, 1), null);
        member(active, porsche, null, true, false, 'Tier 2', 80.00, 'Flat', null);
        assignment(active, null, pkgRec, null, Date.newInstance(2027, 1, 1), null); // not yet effective

        Vehicle__c cayenneVehicle = vehicle('Cayenne r1 (test)', porsche, cayenne, 'Gas', 'Personal Use');
        Account dealerRec = dealer('Dealer-A r1', false, null);

        VehicleScheduleResolver.ResolverResult r = resolve(dealerRec, cayenneVehicle, pkgRec);
        // Only 'Active' is effective on the as-of date BUT its assignment is future-dated too.
        // Wait — 'Active' assignment Effective_From 2027 => excluded. No line expected.
        System.assertEquals(0, r.lines.size(), 'draft/expired/future must never match');
    }

    @isTest
    static void testR1ActiveScheduleWithOpenAssignmentResolves() {
        Make__c porsche = make('Porsche');
        Model__c cayenne = model(porsche, 'Cayenne');
        Package_Group__c grp = packageGroup('ELW r1b (test)');
        Package__c pkgRec = pkg('ELW r1b pkg (test)', grp, 'Extended_Limited_Warranty');

        Vehicle_Schedule__c active = schedule('Active open (test)', 'Premium_Tier', true,
            Date.newInstance(2026, 1, 1), null);
        member(active, porsche, null, true, false, 'Tier 2', 80.00, 'Flat', null);
        assignment(active, null, pkgRec, null, Date.newInstance(2026, 1, 1), null);

        Vehicle__c cayenneVehicle = vehicle('Cayenne r1b (test)', porsche, cayenne, 'Gas', 'Personal Use');
        Account dealerRec = dealer('Dealer-A r1b', false, null);
        VehicleScheduleResolver.ResolverResult r = resolve(dealerRec, cayenneVehicle, pkgRec);
        VehicleScheduleResolver.ResolvedFeeLine line = lineForType(r, 'Premium_Tier');
        System.assertNotEquals(null, line);
        System.assertEquals(80.00, line.amount);
    }

    // ---------------------------------------------------------------
    // R5 — dealer override replaces the resolved premium fee
    // ---------------------------------------------------------------

    @isTest
    static void testR5DealerOverrideReplacesPremiumFee() {
        Make__c porsche = make('Porsche');
        Model__c gt3 = model(porsche, '911 GT3');
        Package_Group__c grp = packageGroup('ELW r5 (test)');
        Package__c pkgRec = pkg('ELW r5 pkg (test)', grp, 'Extended_Limited_Warranty');

        Vehicle_Schedule__c premium = schedule('Premium r5 (test)', 'Premium_Tier', true,
            Date.newInstance(2026, 1, 1), null);
        member(premium, porsche, null, true, false, 'Tier 2', 299.00, 'Flat', null);
        member(premium, porsche, gt3, false, false, 'Tier 3', 899.00, 'Flat', null);
        assignment(premium, null, pkgRec, null, Date.newInstance(2026, 1, 1), null);

        Vehicle__c gt3Vehicle = vehicle('GT3 r5 (test)', porsche, gt3, 'Gas', 'Personal Use');

        // Dealer-B charges premium vehicles and has a fixed override amount
        Account overrideDealer = dealer('Dealer-B r5 override', true, 250.00);
        VehicleScheduleResolver.ResolverResult r = resolve(overrideDealer, gt3Vehicle, pkgRec);
        VehicleScheduleResolver.ResolvedFeeLine line = lineForType(r, 'Premium_Tier');
        System.assertNotEquals(null, line);
        System.assertEquals(250.00, line.amount, 'R5 override amount must replace the Tier 3 fee');
        System.assertEquals(VehicleScheduleResolver.SOURCE_DEALER_OVERRIDE, line.source);
        System.assertEquals(true, line.dealerOverrideApplied);
        System.assertEquals(true, r.dealerOverrideApplied);

        // Dealer-A does not charge premium vehicles => schedule amount stands
        Account standardDealer = dealer('Dealer-A r5 standard', false, null);
        r = resolve(standardDealer, gt3Vehicle, pkgRec);
        line = lineForType(r, 'Premium_Tier');
        System.assertEquals(899.00, line.amount, 'no override => resolved schedule amount');
        System.assertEquals(VehicleScheduleResolver.SOURCE_SCHEDULE, line.source);
        System.assertEquals(false, r.dealerOverrideApplied);
    }

    // ---------------------------------------------------------------
    // R6 — determinism
    // ---------------------------------------------------------------

    @isTest
    static void testR6Determinism() {
        Make__c porsche = make('Porsche');
        Model__c gt3 = model(porsche, '911 GT3');
        Package_Group__c grp = packageGroup('ELW r6 (test)');
        Package__c pkgRec = pkg('ELW r6 pkg (test)', grp, 'Extended_Limited_Warranty');

        Vehicle_Schedule__c premium = schedule('Premium r6 (test)', 'Premium_Tier', true,
            Date.newInstance(2026, 1, 1), null);
        member(premium, porsche, null, true, false, 'Tier 2', 299.00, 'Flat', null);
        member(premium, porsche, gt3, false, false, 'Tier 3', 899.00, 'Flat', null);
        assignment(premium, null, pkgRec, null, Date.newInstance(2026, 1, 1), null);

        Account dealerRec = dealer('Dealer-A r6', false, null);
        Vehicle__c gt3Vehicle = vehicle('GT3 r6 (test)', porsche, gt3, 'Gas', 'Personal Use');

        VehicleScheduleResolver.ResolverResult first = resolve(dealerRec, gt3Vehicle, pkgRec);
        VehicleScheduleResolver.ResolverResult second = resolve(dealerRec, gt3Vehicle, pkgRec);

        System.assertEquals(JSON.serialize(first), JSON.serialize(second), 'R6: same context in => same lines out');
    }

    // ---------------------------------------------------------------
    // D2 — Tire & Rim blocked for commercial use (P1 rule)
    // ---------------------------------------------------------------

    @isTest
    static void testD2TireRimCommercialBlocked() {
        Make__c chevrolet = make('Chevrolet');
        Model__c silverado = model(chevrolet, 'Silverado');
        Package_Group__c trGroup = packageGroup('Tire & Rim (test)');
        Package__c trPkg = pkg('T&R Plan (test)', trGroup, 'Tire_Rim_Protection_Plan');

        Vehicle_Schedule__c categorySchedule = schedule('T&R Categories (test)', 'Tire_Rim_Category', true,
            Date.newInstance(2026, 1, 1), null);
        member(categorySchedule, chevrolet, null, true, false, null, null, 'Flat', null);
        assignment(categorySchedule, null, trPkg, null, Date.newInstance(2026, 1, 1), null);

        Account dealerRec = dealer('Dealer-A tr', false, null);

        // Commercial-use vehicle on Tire & Rim => blocked (D2), no category line
        Vehicle__c commercialVan = vehicle('Silverado commercial (test)', chevrolet, silverado, 'Gas', 'Commercial/Business Use');
        VehicleScheduleResolver.ResolverResult r = resolve(dealerRec, commercialVan, trPkg);
        System.assertEquals(true, r.hasBlocks(), 'commercial T&R must be blocked');
        System.assertEquals(true, r.blocks.contains(VehicleScheduleResolver.BLOCK_TIRE_RIM_COMMERCIAL));
        System.assertEquals(null, lineForType(r, 'Tire_Rim_Category'), 'no T&R line for a blocked vehicle');

        // Personal-use vehicle resolves normally
        Vehicle__c personalTruck = vehicle('Silverado personal (test)', chevrolet, silverado, 'Gas', 'Personal Use');
        r = resolve(dealerRec, personalTruck, trPkg);
        System.assertEquals(0, r.blocks.size());
        System.assertNotEquals(null, lineForType(r, 'Tire_Rim_Category'), 'personal T&R vehicle must resolve a category row');
    }

    // ---------------------------------------------------------------
    // Diesel fee gating + commercial surcharge gating
    // ---------------------------------------------------------------

    @isTest
    static void testDieselFeeOnlyForDieselVehicles() {
        Make__c ford = make('Ford');
        Model__c f150 = model(ford, 'F-150');
        Package_Group__c grp = packageGroup('ELW diesel (test)');
        Package__c pkgRec = pkg('ELW diesel pkg (test)', grp, 'Extended_Limited_Warranty');

        Vehicle_Schedule__c diesel = schedule('Diesel fee (test)', 'Diesel_Fee', true,
            Date.newInstance(2026, 1, 1), null);
        // Catch-all row: no make/model, Include_All_Models = true
        member(diesel, null, null, true, false, null, 150.00, 'Flat', null);
        assignment(diesel, null, pkgRec, null, Date.newInstance(2026, 1, 1), null);

        Account dealerRec = dealer('Dealer-A diesel', false, null);

        Vehicle__c dieselTruck = vehicle('F-150 diesel (test)', ford, f150, 'Diesel', 'Personal Use');
        VehicleScheduleResolver.ResolverResult r = resolve(dealerRec, dieselTruck, pkgRec);
        VehicleScheduleResolver.ResolvedFeeLine line = lineForType(r, 'Diesel_Fee');
        System.assertNotEquals(null, line, 'diesel vehicle must resolve the diesel fee');
        System.assertEquals(150.00, line.amount);

        Vehicle__c gasTruck = vehicle('F-150 gas (test)', ford, f150, 'Gas', 'Personal Use');
        r = resolve(dealerRec, gasTruck, pkgRec);
        System.assertEquals(null, lineForType(r, 'Diesel_Fee'), 'gas vehicle => no diesel fee');
    }

    @isTest
    static void testCommercialSurchargeOnlyForCommercialVehicles() {
        Make__c mercedes = make('Mercedes-Benz');
        Model__c sprinter = model(mercedes, 'Sprinter');
        Package_Group__c grp = packageGroup('Commercial (test)');
        Package__c pkgRec = pkg('Commercial pkg (test)', grp, 'Extended_Limited_Warranty');

        Vehicle_Schedule__c surcharge = schedule('Commercial surcharge (test)', 'Commercial_Surcharge', true,
            Date.newInstance(2026, 1, 1), null);
        member(surcharge, null, null, true, false, null, 400.00, 'Flat', null);
        assignment(surcharge, null, pkgRec, null, Date.newInstance(2026, 1, 1), null);

        Account dealerRec = dealer('Dealer-A comm', false, null);

        Vehicle__c commercialVan = vehicle('Sprinter commercial (test)', mercedes, sprinter, 'Diesel', 'Commercial/Business Use');
        VehicleScheduleResolver.ResolverResult r = resolve(dealerRec, commercialVan, pkgRec);
        VehicleScheduleResolver.ResolvedFeeLine line = lineForType(r, 'Commercial_Surcharge');
        System.assertNotEquals(null, line);
        System.assertEquals(400.00, line.amount);

        Vehicle__c personalVan = vehicle('Sprinter personal (test)', mercedes, sprinter, 'Diesel', 'Personal Use');
        r = resolve(dealerRec, personalVan, pkgRec);
        System.assertEquals(null, lineForType(r, 'Commercial_Surcharge'), 'personal use => no surcharge');
    }

    // ---------------------------------------------------------------
    // Powersports multiplier rows (data replaces the hard-coded 1.25/1.60)
    // ---------------------------------------------------------------

    @isTest
    static void testPowersportsMultiplierRows() {
        Make__c harley = make('Harley-Davidson');
        Model__c streetGlide = model(harley, 'Street Glide');
        Make__c ktm = make('KTM');
        Model__c superDuke = model(ktm, 'Super Duke');

        Package_Group__c psGroup = packageGroup('Powersports (test)');
        Package__c psPkg = pkg('Powersports pkg (test)', psGroup, 'Extended_Limited_Warranty');

        Vehicle_Schedule__c program = schedule('Powersports program (test)', 'Powersports_Program', true,
            Date.newInstance(2026, 1, 1), null);
        // Premium tier 1.25 / Exotic tier 1.60 — the old Apex constants as data
        member(program, harley, null, true, false, null, null, 'Multiplier', 1.25);
        member(program, ktm, null, true, false, null, null, 'Multiplier', 1.60);
        assignment(program, null, psPkg, null, Date.newInstance(2026, 1, 1), null);

        Account dealerRec = dealer('Dealer-C powersports (test)', false, null);

        Vehicle__c harleyVehicle = vehicle('Harley (test)', harley, streetGlide, 'Gas', 'Personal Use');
        VehicleScheduleResolver.ResolverResult r = resolve(dealerRec, harleyVehicle, psPkg);
        VehicleScheduleResolver.ResolvedFeeLine line = lineForType(r, 'Powersports_Program');
        System.assertNotEquals(null, line);
        System.assertEquals(VehicleScheduleResolver.AMOUNT_TYPE_MULTIPLIER, line.amountType);
        System.assertEquals(1.25, line.multiplier);
        System.assertEquals(null, line.amount, 'multiplier rows carry no flat amount');

        Vehicle__c ktmVehicle = vehicle('KTM (test)', ktm, superDuke, 'Gas', 'Personal Use');
        r = resolve(dealerRec, ktmVehicle, psPkg);
        line = lineForType(r, 'Powersports_Program');
        System.assertEquals(1.60, line.multiplier);
    }

    // ---------------------------------------------------------------
    // Member_Key maintenance (trigger)
    // ---------------------------------------------------------------

    @isTest
    static void testMemberKeyTriggerMaintainsKey() {
        Make__c porsche = make('Porsche');
        Model__c gt3 = model(porsche, '911 GT3');

        Vehicle_Schedule__c sched = schedule('Key sched (test)', 'Premium_Tier', true,
            Date.newInstance(2026, 1, 1), null);

        Vehicle_Schedule_Member__c m = new Vehicle_Schedule_Member__c(
            Name = 'Porsche GT3 key test',
            Vehicle_Schedule__c = sched.Id,
            Make__c = porsche.Id,
            Model__c = gt3.Id,
            Include_All_Models__c = false,
            Is_Exclusion__c = false
        );
        insert m;

        Vehicle_Schedule_Member__c stored = [SELECT Member_Key__c FROM Vehicle_Schedule_Member__c WHERE Id = :m.Id];
        System.assertEquals(sched.Id + '|Porsche|911 GT3|N|N', stored.Member_Key__c);

        // Exclusion flag flip on update re-derives the key (fetch-then-update:
        // updating a *constructed* sparse MD child in test context trips an FLS
        // guard on the master field; retrieved records update cleanly).
        Vehicle_Schedule_Member__c upd = [SELECT Id, Is_Exclusion__c FROM Vehicle_Schedule_Member__c WHERE Id = :m.Id];
        upd.Is_Exclusion__c = true;
        try {
            update upd;
        } catch (DmlException e) {
            System.assert(false, 'key update failed: fields=' + e.getDmlFields(0)
                + ' msg=' + e.getDmlMessage(0));
        }
        stored = [SELECT Member_Key__c FROM Vehicle_Schedule_Member__c WHERE Id = :m.Id];
        System.assertEquals(sched.Id + '|Porsche|911 GT3|N|Y', stored.Member_Key__c);

        // Make row (include all, no model)
        Vehicle_Schedule_Member__c makeRow = new Vehicle_Schedule_Member__c(
            Name = 'Porsche all key test',
            Vehicle_Schedule__c = sched.Id,
            Make__c = porsche.Id,
            Include_All_Models__c = true
        );
        insert makeRow;
        stored = [SELECT Member_Key__c FROM Vehicle_Schedule_Member__c WHERE Id = :makeRow.Id];
        System.assertEquals(sched.Id + '|Porsche|*|Y|N', stored.Member_Key__c);

        // Catch-all row (no make/model)
        Vehicle_Schedule_Member__c catchAll = new Vehicle_Schedule_Member__c(
            Name = 'Catch all key test',
            Vehicle_Schedule__c = sched.Id,
            Include_All_Models__c = true
        );
        insert catchAll;
        stored = [SELECT Member_Key__c FROM Vehicle_Schedule_Member__c WHERE Id = :catchAll.Id];
        System.assertEquals(sched.Id + '|*|*|Y|N', stored.Member_Key__c);
    }

    // ---------------------------------------------------------------
    // Preview mode flag gate (P1: preview inert while flag off)
    // ---------------------------------------------------------------

    @isTest
    static void testPreviewFlagGate() {
        Make__c porsche = make('Porsche');
        Model__c gt3 = model(porsche, '911 GT3');
        Package_Group__c grp = packageGroup('ELW preview (test)');
        Package__c pkgRec = pkg('ELW preview pkg (test)', grp, 'Extended_Limited_Warranty');
        Vehicle_Schedule__c premium = schedule('Premium preview (test)', 'Premium_Tier', true,
            Date.newInstance(2026, 1, 1), null);
        member(premium, porsche, null, true, false, 'Tier 2', 299.00, 'Flat', null);
        assignment(premium, null, pkgRec, null, Date.newInstance(2026, 1, 1), null);
        Account dealerRec = dealer('Dealer-A preview', false, null);
        Vehicle__c gt3Vehicle = vehicle('GT3 preview (test)', porsche, gt3, 'Gas', 'Personal Use');

        // Flag off (P1 default) => preview unavailable, resolver still callable directly
        setEngineFlag(false);
        VehicleScheduleResolver.ResolverResult preview =
            VehicleSchedulePreviewController.resolveForPreview(dealerRec.Id, gt3Vehicle.Id, pkgRec.Id, Date.today());
        System.assertEquals(null, preview, 'preview must be inert while the engine flag is off');

        // Flag on => preview resolves
        setEngineFlag(true);
        preview = VehicleSchedulePreviewController.resolveForPreview(dealerRec.Id, gt3Vehicle.Id, pkgRec.Id, Date.today());
        System.assertNotEquals(null, preview);
        VehicleScheduleResolver.ResolvedFeeLine line = lineForType(preview, 'Premium_Tier');
        System.assertNotEquals(null, line);
        System.assertEquals(299.00, line.amount);
    }

    @isTest
    static void testResolverHandlesMissingContext() {
        // Null vehicle => block code, no crash
        VehicleScheduleResolver.ResolveRequest req = new VehicleScheduleResolver.ResolveRequest(
            null, null, null, Date.today());
        VehicleScheduleResolver.ResolverResult r = VehicleScheduleResolver.resolve(req);
        System.assertEquals(true, r.blocks.contains(VehicleScheduleResolver.BLOCK_VEHICLE_NOT_FOUND));

        // Unknown vehicle id => block code
        req = new VehicleScheduleResolver.ResolveRequest(null, '001000000000000', null, Date.today());
        r = VehicleScheduleResolver.resolve(req);
        System.assertEquals(true, r.blocks.contains(VehicleScheduleResolver.BLOCK_VEHICLE_NOT_FOUND));
    }

    // ---------------------------------------------------------------
    // Rev 7 — commercial surcharge vehicle-type selection (C-C1…C-C5)
    // ---------------------------------------------------------------

    private static Vehicle__c vehicleTyped(String name, Make__c makeRec, Model__c modelRec,
                                           String fuel, String usage, String commercialType) {
        Vehicle__c v = new Vehicle__c(
            Name = name,
            Make_Lookup__c = makeRec != null ? makeRec.Id : null,
            Model_Lookup__c = modelRec != null ? modelRec.Id : null,
            Fuel_Type__c = fuel,
            Usage_Type__c = usage,
            Commercial_Vehicle_Type__c = commercialType
        );
        insert v;
        return v;
    }

    private static Vehicle_Schedule_Member__c typedCatchAll(Vehicle_Schedule__c sched,
                                                            Decimal amount, String commercialType) {
        Vehicle_Schedule_Member__c m = new Vehicle_Schedule_Member__c(
            Name = 'ALL ' + commercialType,
            Vehicle_Schedule__c = sched.Id,
            Include_All_Models__c = true,
            Is_Exclusion__c = false,
            Amount_Type__c = 'Flat',
            Premium_Model_Fee__c = amount,
            Commercial_Vehicle_Type__c = commercialType,
            Sort_Order__c = 0
        );
        insert m;
        return m;
    }

    @isTest
    static void testCommercialSurchargeSelectsRowByVehicleType() {
        Make__c ford = make('Ford');
        Model__c transit = model(ford, 'Transit');
        Package_Group__c grp = packageGroup('Commercial vt (test)');
        Package__c pkgRec = pkg('Pro Warranty (test)', grp, 'Extended_Limited_Warranty');

        Vehicle_Schedule__c cs = schedule('Commercial vt sched (test)', 'Commercial_Surcharge', true,
            Date.newInstance(2026, 1, 1), null);
        typedCatchAll(cs, 250.00, 'Personal/Light Duty Vehicle');
        typedCatchAll(cs, 500.00, 'Rideshare/Delivery Vehicle');
        typedCatchAll(cs, 1000.00, 'Commercial (Medium Duty)');
        assignment(cs, null, pkgRec, null, Date.newInstance(2026, 1, 1), null);

        Account dealerRec = dealer('Dealer-A vt (test)', false, null);

        Map<String, Decimal> expected = new Map<String, Decimal>{
            'Personal/Light Duty Vehicle' => 250.00,
            'Rideshare/Delivery Vehicle' => 500.00,
            'Commercial (Medium Duty)' => 1000.00
        };
        for (String vt : expected.keySet()) {
            Vehicle__c v = vehicleTyped('Transit ' + vt, ford, transit, 'Gas', 'Commercial/Business Use', vt);
            VehicleScheduleResolver.ResolverResult r = resolve(dealerRec, v, pkgRec);
            VehicleScheduleResolver.ResolvedFeeLine line = lineForType(r, 'Commercial_Surcharge');
            System.assertNotEquals(null, line, 'a commercial line must resolve for ' + vt);
            System.assertEquals(expected.get(vt), line.amount, 'row for ' + vt + ' must win');
            System.assertEquals(1, r.lines.size(), 'exactly one line for ' + vt);
        }

        // Fail-closed: a commercial vehicle with a BLANK type resolves no row.
        Vehicle__c blankType = vehicleTyped('Transit blank', ford, transit, 'Gas', 'Commercial/Business Use', null);
        VehicleScheduleResolver.ResolverResult rb = resolve(dealerRec, blankType, pkgRec);
        System.assertEquals(null, lineForType(rb, 'Commercial_Surcharge'), 'blank type => no surcharge');

        // Personal use => the commercial branch never runs.
        Vehicle__c personal = vehicleTyped('Transit personal', ford, transit, 'Gas', 'Personal Use', 'Commercial (Medium Duty)');
        VehicleScheduleResolver.ResolverResult rp = resolve(dealerRec, personal, pkgRec);
        System.assertEquals(null, lineForType(rp, 'Commercial_Surcharge'), 'personal use => no surcharge');
    }

    // ---------------------------------------------------------------
    // Rev 4/7 — T&R class surfaces on the line (C-1/C-2) + C-3 helper
    // ---------------------------------------------------------------

    private static Vehicle_Schedule_Member__c classRow(Vehicle_Schedule__c sched, Make__c makeRec,
                                                       Model__c modelRec, Boolean includeAll,
                                                       Boolean exclusion, String cls) {
        Vehicle_Schedule_Member__c m = new Vehicle_Schedule_Member__c(
            Name = (makeRec != null ? makeRec.Name : 'ALL') + (modelRec != null ? ' ' + modelRec.Name : ''),
            Vehicle_Schedule__c = sched.Id,
            Make__c = makeRec != null ? makeRec.Id : null,
            Model__c = modelRec != null ? modelRec.Id : null,
            Include_All_Models__c = includeAll,
            Is_Exclusion__c = exclusion,
            Class__c = cls,
            Amount_Type__c = 'Flat',
            Sort_Order__c = 0
        );
        insert m;
        return m;
    }

    @isTest
    static void testTireRimClassSurfacedAndResolved() {
        Make__c dodge = make('Dodge');
        Model__c viper = model(dodge, 'Viper');
        Model__c charger = model(dodge, 'Charger');
        Make__c bmw = make('BMW');
        Model__c m3 = model(bmw, 'M3');

        Package_Group__c trGroup = packageGroup('T&R cls (test)');
        Package__c trPkg = pkg('T&R cls pkg (test)', trGroup, 'Tire_Rim_Protection_Plan');

        Vehicle_Schedule__c cls = schedule('T&R cls sched (test)', 'Tire_Rim_Category', true,
            Date.newInstance(2026, 1, 1), null);
        classRow(cls, dodge, null, true, false, 'Class 1');
        classRow(cls, dodge, viper, false, false, 'Class 3');
        classRow(cls, bmw, null, true, false, 'Class 3');
        assignment(cls, null, trPkg, null, Date.newInstance(2026, 1, 1), null);

        Account dealerRec = dealer('Dealer-A trcls (test)', false, null);

        Vehicle__c viperV = vehicle('Viper (test)', dodge, viper, 'Gas', 'Personal Use');
        VehicleScheduleResolver.ResolverResult r = resolve(dealerRec, viperV, trPkg);
        VehicleScheduleResolver.ResolvedFeeLine line = lineForType(r, 'Tire_Rim_Category');
        System.assertNotEquals(null, line, 'personal T&R vehicle resolves a category row');
        System.assertEquals('Class 3', line.category, 'Viper model row => Class 3 (C-2)');
        System.assertEquals('Class 3', VehicleScheduleResolver.resolveTireRimClass(viperV.Id, Date.newInstance(2026, 9, 3)));

        Vehicle__c chargerV = vehicle('Charger (test)', dodge, charger, 'Gas', 'Personal Use');
        r = resolve(dealerRec, chargerV, trPkg);
        line = lineForType(r, 'Tire_Rim_Category');
        System.assertEquals('Class 1', line.category, 'Dodge make row => Class 1');
        System.assertEquals('Class 1', VehicleScheduleResolver.resolveTireRimClass(chargerV.Id, Date.newInstance(2026, 9, 3)));

        Vehicle__c bmwV = vehicle('M3 (test)', bmw, m3, 'Gas', 'Personal Use');
        System.assertEquals('Class 3', VehicleScheduleResolver.resolveTireRimClass(bmwV.Id, Date.newInstance(2026, 9, 3)));
    }

    // ---------------------------------------------------------------
    // C-C1: the Member_Key grammar gains the type segment ONLY when set
    // ---------------------------------------------------------------

    @isTest
    static void testMemberKeyTypedSegmentOnlyWhenSet() {
        Make__c ford = make('Ford');
        Vehicle_Schedule__c sched = schedule('Key typed (test)', 'Commercial_Surcharge', true,
            Date.newInstance(2026, 1, 1), null);

        Vehicle_Schedule_Member__c plain = new Vehicle_Schedule_Member__c(
            Name = 'Plain catch-all',
            Vehicle_Schedule__c = sched.Id,
            Include_All_Models__c = true
        );
        insert plain;
        Vehicle_Schedule_Member__c stored = [SELECT Member_Key__c FROM Vehicle_Schedule_Member__c WHERE Id = :plain.Id];
        System.assertEquals(sched.Id + '|*|*|Y|N', stored.Member_Key__c, 'blank type => 5-segment key unchanged');

        Vehicle_Schedule_Member__c typed = new Vehicle_Schedule_Member__c(
            Name = 'Typed catch-all',
            Vehicle_Schedule__c = sched.Id,
            Include_All_Models__c = true,
            Commercial_Vehicle_Type__c = 'Commercial (Medium Duty)'
        );
        insert typed;
        stored = [SELECT Member_Key__c FROM Vehicle_Schedule_Member__c WHERE Id = :typed.Id];
        System.assertEquals(sched.Id + '|*|*|Y|N|Commercial (Medium Duty)', stored.Member_Key__c,
            'non-blank type => the type segment is appended');
    }
}