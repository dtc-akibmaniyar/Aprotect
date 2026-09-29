/**
 * VehicleScheduleResolverTypedKeyTest
 *
 * Focused regression tests for the typed member-key symmetry fix (C-C6).
 *
 * The contract is a single key grammar shared by the two sides of the same row
 * lookup:
 *   <ScheduleId>|<Make|*>|<Model|*>|<IncludeAll Y|N>|<IsExclusion Y|N>[|<CommercialVehicleType>]
 *
 *   - ROW side  — VehicleScheduleMemberKeyHandler.buildKey appends the sixth
 *     `|<CommercialVehicleType>` segment whenever the ROW's
 *     Commercial_Vehicle_Type__c is non-blank (type-agnostic).
 *   - VEHICLE side — VehicleScheduleResolver.buildMemberKeys must append the
 *     same segment whenever the VEHICLE's Commercial_Vehicle_Type__c is
 *     non-blank. Before the fix it did so only for a Commercial_Surcharge
 *     schedule, so a typed member row in any other family (proven live on the
 *     Commercial_Eligibility schedule a36G1000000VL4zIAG) could never match.
 *
 * Coverage:
 *   1. C-C6  a typed row in a NON-Commercial_Surcharge family now matches a
 *            vehicle carrying the corresponding commercial type (the regression).
 *   2.       a typed row does NOT match a blank-type vehicle (fail-closed kept).
 *   3. C-C4  the Commercial_Surcharge path emits the same keys and resolves the
 *            same amounts as before the fix.
 *   4.       an untyped / catch-all row still matches exactly as today, and the
 *            extra typed candidate keys emitted for other families match
 *            nothing (checked against the fixture data, not asserted by hand).
 *   5.       the pre-existing VehicleScheduleResolverTest is untouched and still
 *            runs unchanged against the fixed resolver
 *            (RunSpecifiedTests names both classes).
 *
 * All fixtures are created per test — nothing depends on seeded org data.
 */
@isTest
private class VehicleScheduleResolverTypedKeyTest {

    // ---------------------------------------------------------------
    // Fixture helpers
    // ---------------------------------------------------------------

    private static Map<String, Id> recordTypes;

    private static Id rt(String sobjectType, String devName) {
        if (recordTypes == null) {
            recordTypes = new Map<String, Id>();
            for (RecordType r : [SELECT Id, SObjectType, DeveloperName FROM RecordType
                                 WHERE SObjectType IN ('Account','Package__c')]) {
                recordTypes.put(r.SObjectType + '.' + r.DeveloperName, r.Id);
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

    private static Package__c pkg(String name, Package_Group__c grp) {
        Package__c p = new Package__c(
            Name = name,
            Package_Group__c = grp.Id,
            RecordTypeId = rt('Package__c', 'Extended_Limited_Warranty'),
            Is_Active__c = true
        );
        insert p;
        return p;
    }

    private static Vehicle_Schedule__c schedule(String name, String type) {
        Vehicle_Schedule__c s = new Vehicle_Schedule__c(
            Name = name,
            Type__c = type,
            Is_Active__c = true,
            Valid_From__c = Date.newInstance(2026, 1, 1)
        );
        insert s;
        return s;
    }

    /** Catch-all member row (no make/model, Include_All_Models = true), optionally type-qualified. */
    private static Vehicle_Schedule_Member__c catchAllRow(Vehicle_Schedule__c sched,
                                                          Decimal amount, String commercialType) {
        Vehicle_Schedule_Member__c m = new Vehicle_Schedule_Member__c(
            Name = 'ALL ' + (commercialType != null ? commercialType : 'any'),
            Vehicle_Schedule__c = sched.Id,
            Include_All_Models__c = true,
            Is_Exclusion__c = false,
            Amount_Type__c = 'Flat',
            Premium_Model_Fee__c = amount,
            Commercial_Vehicle_Type__c = commercialType,
            Sort_Order__c = 0
        );
        insert m; // VehicleScheduleMemberTrigger derives Member_Key__c
        return m;
    }

    private static Vehicle_Schedule_Assignment__c assignment(Vehicle_Schedule__c sched, Package__c pkgRec) {
        Vehicle_Schedule_Assignment__c a = new Vehicle_Schedule_Assignment__c(
            Name = sched.Name + ' assignment',
            Vehicle_Schedule__c = sched.Id,
            Package__c = pkgRec.Id,
            Effective_From__c = Date.newInstance(2026, 1, 1)
        );
        insert a;
        return a;
    }

    private static Account dealer(String name) {
        Account a = new Account(
            Name = name,
            RecordTypeId = rt('Account', 'Dealer_Account'),
            Charge_Premium_Vehicle_Fee__c = false
        );
        insert a;
        return a;
    }

    private static Vehicle__c vehicle(String name, Make__c makeRec, Model__c modelRec,
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

    private static String storedKey(Id memberId) {
        return [SELECT Member_Key__c FROM Vehicle_Schedule_Member__c WHERE Id = :memberId].Member_Key__c;
    }

    // ---------------------------------------------------------------
    // 1/3. Key grammar — the typed segment is emitted for EVERY family,
    //      and only when the vehicle's commercial type is non-blank
    // ---------------------------------------------------------------

    @isTest
    static void testTypedKeySegmentEmittedForEveryFamily() {
        Id schedId = 'a36000000000001AAA'; // id-shaped value only; no DML needed
        String type = 'Commercial (Medium Duty)';
        List<String> families = new List<String>{
            'Premium_Tier', 'Diesel_Fee', 'Commercial_Surcharge',
            'Powersports_Program', 'Tire_Rim_Category', 'Commercial_Eligibility'
        };

        List<String> plain = VehicleScheduleResolver.buildMemberKeys(schedId, 'Ford', 'Transit');
        System.assertEquals(5, plain.size(), 'the base grammar is five segments');

        for (String fam : families) {
            // Blank vehicle type => the five plain keys, unchanged, for every family.
            System.assertEquals(plain,
                VehicleScheduleResolver.buildMemberKeys(schedId, 'Ford', 'Transit', null, fam),
                'blank vehicle type => five plain keys only (' + fam + ')');

            // Non-blank vehicle type => five plain + five typed, for EVERY family.
            List<String> keys = VehicleScheduleResolver.buildMemberKeys(schedId, 'Ford', 'Transit', type, fam);
            System.assertEquals(10, keys.size(), 'ten keys expected for ' + fam);
            for (Integer i = 0; i < plain.size(); i++) {
                System.assertEquals(plain[i], keys[i], 'plain keys stay first and unchanged (' + fam + ')');
            }
            // The five typed keys must equal exactly what the ROW side derives for
            // the same shapes — this is the symmetry the fix restores.
            System.assertEquals(VehicleScheduleMemberKeyHandler.buildKey(schedId, 'Ford', 'Transit', false, true, type),
                keys[5], 'model exclusion typed key (' + fam + ')');
            System.assertEquals(VehicleScheduleMemberKeyHandler.buildKey(schedId, 'Ford', 'Transit', false, false, type),
                keys[6], 'model inclusion typed key (' + fam + ')');
            System.assertEquals(VehicleScheduleMemberKeyHandler.buildKey(schedId, 'Ford', null, true, true, type),
                keys[7], 'make exclusion typed key (' + fam + ')');
            System.assertEquals(VehicleScheduleMemberKeyHandler.buildKey(schedId, 'Ford', null, true, false, type),
                keys[8], 'make inclusion typed key (' + fam + ')');
            System.assertEquals(VehicleScheduleMemberKeyHandler.buildKey(schedId, null, null, true, false, type),
                keys[9], 'catch-all typed key (' + fam + ')');
        }
    }

    // ---------------------------------------------------------------
    // 1. Regression — a typed row in a NON-Commercial_Surcharge family matches
    // ---------------------------------------------------------------

    @isTest
    static void testTypedRowMatchesInNonSurchargeFamily() {
        Make__c ford = make('Ford');
        Model__c transit = model(ford, 'Transit');
        Package_Group__c grp = packageGroup('CE typed keys (test)');
        Package__c pkgRec = pkg('CE pkg (test)', grp);

        Vehicle_Schedule__c ce = schedule('Commercial eligibility typed (test)', 'Commercial_Eligibility');
        Vehicle_Schedule_Member__c heavy = catchAllRow(ce, 1000.00, 'Commercial (Medium Duty)');
        catchAllRow(ce, 250.00, 'Personal/Light Duty Vehicle');
        assignment(ce, pkgRec);

        // The row side already qualifies the key on this family — the contract.
        System.assertEquals(ce.Id + '|*|*|Y|N|Commercial (Medium Duty)', storedKey(heavy.Id),
            'row-side key carries the type segment regardless of family');

        Account dealerRec = dealer('Dealer-A CE (test)');

        Vehicle__c heavyVehicle = vehicle('Transit heavy (test)', ford, transit, 'Gas',
            'Commercial/Business Use', 'Commercial (Medium Duty)');
        VehicleScheduleResolver.ResolverResult r = resolve(dealerRec, heavyVehicle, pkgRec);
        System.assertEquals(0, r.blocks.size(), 'no blocks expected: ' + r.blocks);
        System.assertEquals(1, r.lines.size(), 'one schedule assigned => one line');
        VehicleScheduleResolver.ResolvedFeeLine line = lineForType(r, 'Commercial_Eligibility');
        System.assertNotEquals(null, line,
            'a typed row in a non-Commercial_Surcharge family must now match');
        System.assertEquals(heavy.Id, line.memberId, 'the type-qualified row must be the match');
        System.assertEquals(1000.00, line.amount);

        // The other type resolves its own row, not the first one.
        Vehicle__c lightVehicle = vehicle('Transit light (test)', ford, transit, 'Gas',
            'Commercial/Business Use', 'Personal/Light Duty Vehicle');
        r = resolve(dealerRec, lightVehicle, pkgRec);
        line = lineForType(r, 'Commercial_Eligibility');
        System.assertNotEquals(null, line, 'the second type must resolve its own row');
        System.assertEquals(250.00, line.amount);
        System.assertEquals(1, r.lines.size(), 'still exactly one line');
    }

    // ---------------------------------------------------------------
    // 2. Fail-closed — a typed row does NOT match a blank-type vehicle
    // ---------------------------------------------------------------

    @isTest
    static void testTypedRowDoesNotMatchBlankVehicleType() {
        Make__c ford = make('Ford');
        Model__c transit = model(ford, 'Transit');
        Package_Group__c grp = packageGroup('CE fail-closed (test)');
        Package__c pkgRec = pkg('CE fc pkg (test)', grp);

        Vehicle_Schedule__c ce = schedule('Commercial eligibility fc (test)', 'Commercial_Eligibility');
        catchAllRow(ce, 1000.00, 'Commercial (Medium Duty)'); // ONLY a typed row
        assignment(ce, pkgRec);

        Account dealerRec = dealer('Dealer-A CE fc (test)');

        // Blank vehicle type => no typed candidate keys => the typed row cannot match.
        Vehicle__c blankVehicle = vehicle('Transit blank (test)', ford, transit, 'Gas',
            'Commercial/Business Use', null);
        VehicleScheduleResolver.ResolverResult r = resolve(dealerRec, blankVehicle, pkgRec);
        System.assertEquals(0, r.lines.size(), 'a typed row must not match a blank-type vehicle');
        System.assertEquals(0, r.blocks.size(), 'no blocks expected: ' + r.blocks);

        // A different, non-matching type also matches nothing (exact type equality).
        Vehicle__c otherVehicle = vehicle('Transit other (test)', ford, transit, 'Gas',
            'Commercial/Business Use', 'Personal/Light Duty Vehicle');
        r = resolve(dealerRec, otherVehicle, pkgRec);
        System.assertEquals(0, r.lines.size(), 'type matching is exact');
    }

    // ---------------------------------------------------------------
    // 4. An untyped / catch-all row still matches; the extra typed candidate
    //    keys emitted for other families match nothing today
    // ---------------------------------------------------------------

    @isTest
    static void testUntypedCatchAllRowStillMatchesAndTypedKeysMatchNothing() {
        Make__c ford = make('Ford');
        Model__c f150 = model(ford, 'F-150');
        Package_Group__c grp = packageGroup('Diesel typed keys (test)');
        Package__c pkgRec = pkg('Diesel pkg (test)', grp);

        Vehicle_Schedule__c diesel = schedule('Diesel fee typed (test)', 'Diesel_Fee');
        Vehicle_Schedule_Member__c catchAll = catchAllRow(diesel, 150.00, null); // untyped
        assignment(diesel, pkgRec);

        // Premise of this test, checked against the fixture data rather than asserted:
        // the schedule holds exactly one member row and it is untyped, so the extra
        // typed candidate keys have nothing to match on this family today.
        List<Vehicle_Schedule_Member__c> rows = [
            SELECT Member_Key__c FROM Vehicle_Schedule_Member__c
            WHERE Vehicle_Schedule__c = :diesel.Id
        ];
        System.assertEquals(1, rows.size(), 'exactly one member row on the diesel schedule');
        System.assertEquals(diesel.Id + '|*|*|Y|N', rows[0].Member_Key__c,
            'the untyped row keeps the five-segment key');

        Account dealerRec = dealer('Dealer-A diesel typed (test)');

        // A diesel vehicle that now ALSO carries a commercial type: the extra typed
        // candidate keys must match nothing, and the untyped catch-all must still win.
        Vehicle__c typedDiesel = vehicle('F-150 diesel typed (test)', ford, f150, 'Diesel',
            'Personal Use', 'Commercial (Medium Duty)');
        VehicleScheduleResolver.ResolverResult r = resolve(dealerRec, typedDiesel, pkgRec);
        System.assertEquals(0, r.blocks.size(), 'no blocks expected: ' + r.blocks);
        System.assertEquals(1, r.lines.size(), 'exactly one line expected: ' + r.lines.size());
        VehicleScheduleResolver.ResolvedFeeLine line = lineForType(r, 'Diesel_Fee');
        System.assertNotEquals(null, line);
        System.assertEquals(catchAll.Id, line.memberId, 'the untyped catch-all row still matches');
        System.assertEquals(150.00, line.amount);

        // Control: the identical diesel vehicle with a blank type resolves the same.
        Vehicle__c plainDiesel = vehicle('F-150 diesel plain (test)', ford, f150, 'Diesel',
            'Personal Use', null);
        VehicleScheduleResolver.ResolverResult rc = resolve(dealerRec, plainDiesel, pkgRec);
        System.assertEquals(1, rc.lines.size());
        System.assertEquals(catchAll.Id, lineForType(rc, 'Diesel_Fee').memberId);
        System.assertEquals(150.00, lineForType(rc, 'Diesel_Fee').amount);
    }

    // ---------------------------------------------------------------
    // 3. Commercial_Surcharge — same keys, same amounts as before the fix
    // ---------------------------------------------------------------

    @isTest
    static void testCommercialSurchargeKeysAndAmountsUnchanged() {
        Make__c ford = make('Ford');
        Model__c transit = model(ford, 'Transit');
        Package_Group__c grp = packageGroup('CS guard (test)');
        Package__c pkgRec = pkg('Pro Warranty guard (test)', grp);

        Vehicle_Schedule__c cs = schedule('CS guard sched (test)', 'Commercial_Surcharge');
        catchAllRow(cs, 250.00, 'Personal/Light Duty Vehicle');
        catchAllRow(cs, 500.00, 'Rideshare/Delivery Vehicle');
        Vehicle_Schedule_Member__c heavy = catchAllRow(cs, 1000.00, 'Commercial (Medium Duty)');
        assignment(cs, pkgRec);

        System.assertEquals(cs.Id + '|*|*|Y|N|Commercial (Medium Duty)', storedKey(heavy.Id),
            'surcharge row key unchanged');

        // Key guard — the candidate set for this family is unchanged: the same five
        // plain keys first, then the same five typed keys, in the same order.
        List<String> plain = VehicleScheduleResolver.buildMemberKeys(cs.Id, null, null);
        List<String> keys = VehicleScheduleResolver.buildMemberKeys(
            cs.Id, null, null, 'Commercial (Medium Duty)', 'Commercial_Surcharge');
        System.assertEquals(10, keys.size());
        for (Integer i = 0; i < plain.size(); i++) {
            System.assertEquals(plain[i], keys[i], 'plain keys unchanged for Commercial_Surcharge');
        }
        System.assertEquals(cs.Id + '|*|*|Y|N|Commercial (Medium Duty)', keys[9],
            'typed catch-all key unchanged for Commercial_Surcharge');

        Account dealerRec = dealer('Dealer-A CS guard (test)');

        Map<String, Decimal> expected = new Map<String, Decimal>{
            'Personal/Light Duty Vehicle' => 250.00,
            'Rideshare/Delivery Vehicle' => 500.00,
            'Commercial (Medium Duty)' => 1000.00
        };
        for (String vt : expected.keySet()) {
            Vehicle__c v = vehicle('Transit ' + vt, ford, transit, 'Gas', 'Commercial/Business Use', vt);
            VehicleScheduleResolver.ResolverResult r = resolve(dealerRec, v, pkgRec);
            VehicleScheduleResolver.ResolvedFeeLine line = lineForType(r, 'Commercial_Surcharge');
            System.assertNotEquals(null, line, 'a surcharge line must resolve for ' + vt);
            System.assertEquals(expected.get(vt), line.amount, 'surcharge amount unchanged for ' + vt);
            System.assertEquals(1, r.lines.size(), 'exactly one line for ' + vt);
        }

        // Fail-closed on a blank type is equally preserved on this family.
        Vehicle__c blankType = vehicle('Transit blank guard', ford, transit, 'Gas',
            'Commercial/Business Use', null);
        System.assertEquals(null, lineForType(resolve(dealerRec, blankType, pkgRec), 'Commercial_Surcharge'),
            'blank type => no surcharge (unchanged)');
    }
}