/**
 * DealerPortalScheduleGateTest
 *
 * Covers the dealer-portal vehicle-schedule eligibility gate added to
 * DealerPortalController.getDealerPackages (2026-09-28 change):
 *
 *   A warranty package is kept only when its OWN designation AND the vehicle's
 *   live schedule membership BOTH agree —
 *     - Powersports package: Dealer_Package__c.Class__c = 'POWERSPORTS' or
 *       Package__c.Vehicle_Category_Filter__c = 'Powersports', AND the vehicle
 *       is a Powersports vehicle and an active member of a Powersports_Program
 *       schedule as of today;
 *     - Commercial package: Package__c.Commercial_Business_Use__c = true, AND
 *       the vehicle is commercial/business use and an active member of a
 *       Commercial_Eligibility schedule as of today.
 *   Fail-closed on every uncertainty (no assignment, inactive schedule,
 *   expired effectivity window, no member row, an exclusion row, resolver
 *   error). The whole gate is behind the org hierarchy flag
 *   Aprotect_Portal_Settings__c.Vehicle_Schedule_Gate_Enabled__c (default OFF);
 *   flag-OFF behaviour is byte-identical to the legacy path.
 *
 * Membership is judged through the deployed VehicleScheduleResolver, so the
 * fixtures create real Vehicle_Schedule__c / Member / Assignment rows with the
 * standard key grammar (VehicleScheduleMemberTrigger maintains Member_Key__c).
 *
 * Run with RunSpecifiedTests (RunLocalTests is blocked by pre-existing,
 * unrelated compile failures elsewhere in the org).
 *
 * LIMITATION (test fixture only, no production impact): the controller's
 * Powersports gate accepts a package when Dealer_Package__c.Class__c =
 * 'POWERSPORTS' OR Package__c.Vehicle_Category_Filter__c = 'Powersports'. In
 * THIS org Class__c is a restricted picklist backed by the global value set
 * 'Class', and no record type enables POWERSPORTS, so Class__c = 'POWERSPORTS'
 * cannot be written by a fixture and that branch cannot be exercised here.
 * Powersports designation is therefore covered via the
 * Vehicle_Category_Filter__c = 'Powersports' branch. No assertion is weakened:
 * the gate's OR semantics are unchanged; only the fixture route to them is.
 */
@isTest
private class DealerPortalScheduleGateTest {

    private static final String RT_WARRANTY = 'Extended_Limited_Warranty';

    // ---------------------------------------------------------------
    // Fixture helpers
    // ---------------------------------------------------------------

    private static Map<String, Id> recordTypes;
    private static Id rt(String sobjectType, String devName) {
        if (recordTypes == null) {
            recordTypes = new Map<String, Id>();
            for (RecordType r : [
                SELECT Id, SObjectType, DeveloperName FROM RecordType
                WHERE SObjectType IN ('Account', 'Package__c', 'Dealer_Package__c')
            ]) {
                recordTypes.put(r.SObjectType + '.' + r.DeveloperName, r.Id);
            }
        }
        return recordTypes.get(sobjectType + '.' + devName);
    }

    private static Account dealer(String name) {
        Account a = new Account(Name = name, RecordTypeId = rt('Account', 'Dealer_Account'));
        insert a;
        return a;
    }

    private static Package_Group__c group(String name) {
        Package_Group__c g = new Package_Group__c(Name = name, Active__c = true);
        insert g;
        return g;
    }

    private static Package__c masterPackage(String name, Package_Group__c grp,
                                            String vcFilter, Boolean commercial) {
        Package__c p = new Package__c(
            Name = name,
            Package_Group__c = grp.Id,
            RecordTypeId = rt('Package__c', RT_WARRANTY),
            Is_Active__c = true,
            Vehicle_Category_Filter__c = vcFilter,
            Commercial_Business_Use__c = commercial);
        insert p;
        return p;
    }

    private static Dealer_Package__c dealerPackage(String name, Account dealerRec,
                                                   Package__c master,
                                                   String classValue) {
        Dealer_Package__c dp = new Dealer_Package__c(
            Name = name,
            Dealer__c = dealerRec.Id,
            Package__c = master.Id,
            RecordTypeId = rt('Dealer_Package__c', RT_WARRANTY),
            Class__c = classValue);
        insert dp;
        return dp;
    }

    private static Dealer_Package_Term__c dealerTerm(String name, Dealer_Package__c dp) {
        Package_Term__c masterTerm = new Package_Term__c(Name = 'PT ' + name);
        insert masterTerm;
        Dealer_Package_Term__c t = new Dealer_Package_Term__c(
            Name = name,
            Dealer_Package__c = dp.Id,
            Package_Term__c = masterTerm.Id,
            Original_Package_Term_Cost__c = 1000.00,
            Markup__c = 100.00,
            Markup_Type__c = '$');
        insert t;
        return t;
    }

    private static Make__c make(String name) {
        Make__c m = new Make__c(Name = name);
        insert m;
        return m;
    }

    private static Model__c model(Make__c mk, String name) {
        Model__c m = new Model__c(Name = name, Make__c = mk.Id);
        insert m;
        return m;
    }

    private static Vehicle__c vehicle(String name, Make__c mk, Model__c mo,
                                      String category, String usage, String commercialType) {
        Vehicle__c v = new Vehicle__c(
            Name = name,
            Year__c = '2022',
            Odometer__c = 5000,
            Odometer_Unit__c = 'KM',
            Make_Lookup__c = mk != null ? mk.Id : null,
            Model_Lookup__c = mo != null ? mo.Id : null,
            Vehicle_Category__c = category,
            Usage_Type__c = usage,
            Commercial_Vehicle_Type__c = commercialType);
        insert v;
        return v;
    }

    private static Application__c application(Account dealerRec, Vehicle__c v) {
        Application__c app = new Application__c(
            Dealer_Name__c = dealerRec.Id,
            Vehicle__c = v != null ? v.Id : null);
        insert app;
        return app;
    }

    private static Vehicle_Schedule__c schedule(String name, String type, Boolean active,
                                                Date startDate, Date to) {
        Vehicle_Schedule__c s = new Vehicle_Schedule__c(
            Name = name, Type__c = type, Is_Active__c = active,
            Valid_From__c = startDate, Valid_To__c = to);
        insert s;
        return s;
    }

    private static Vehicle_Schedule_Member__c member(Vehicle_Schedule__c sched,
                                                     Make__c mk, Model__c mo,
                                                     Boolean includeAll, Boolean exclusion,
                                                     String commercialType) {
        Vehicle_Schedule_Member__c m = new Vehicle_Schedule_Member__c(
            Name = (mk != null ? mk.Name : 'ALL') + (mo != null ? ' ' + mo.Name : ''),
            Vehicle_Schedule__c = sched.Id,
            Make__c = mk != null ? mk.Id : null,
            Model__c = mo != null ? mo.Id : null,
            Include_All_Models__c = includeAll,
            Is_Exclusion__c = exclusion,
            Amount_Type__c = 'Flat',
            Premium_Model_Fee__c = 0,
            Commercial_Vehicle_Type__c = commercialType,
            Sort_Order__c = 0);
        insert m; // fires VehicleScheduleMemberTrigger -> Member_Key__c maintained
        return m;
    }

    private static Vehicle_Schedule_Assignment__c assignment(Vehicle_Schedule__c sched,
                                                             Account dealerRec,
                                                             Package__c pkg,
                                                             Package_Group__c grp,
                                                             Date startDate, Date to) {
        Vehicle_Schedule_Assignment__c a = new Vehicle_Schedule_Assignment__c(
            Name = sched.Name + ' assignment',
            Vehicle_Schedule__c = sched.Id,
            Dealer__c = dealerRec != null ? dealerRec.Id : null,
            Package__c = pkg != null ? pkg.Id : null,
            Package_Group__c = grp != null ? grp.Id : null,
            Effective_From__c = startDate,
            Effective_To__c = to);
        insert a;
        return a;
    }

    /** Org-level hierarchy flag row for Aprotect_Portal_Settings__c. */
    private static void setScheduleGate(Boolean enabled) {
        delete [SELECT Id FROM Aprotect_Portal_Settings__c];
        insert new Aprotect_Portal_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Vehicle_Schedule_Gate_Enabled__c = enabled);
    }

    private static DealerPortalController.DealerPackagesResponse readPackages(Id applicationId) {
        return DealerPortalController.getDealerPackages(applicationId, RT_WARRANTY);
    }

    /**
     * One powersports-designated package + a Powersports_Program schedule whose
     * membership / window / exclusion behaviour is parameterised, read through
     * the public portal path.
     *
     * @param vehicleOnSchedule true => the vehicle's make is a member row;
     *                          false => the vehicle's make is not listed.
     */
    private static DealerPortalController.DealerPackagesResponse powersportsScenario(
            String tag, Boolean scheduleActive, Date validFrom, Date validTo,
            Boolean addExclusionRow, Boolean vehicleOnSchedule) {

        Account d = dealer('PS dealer ' + tag);
        Package_Group__c grp = group('PS group ' + tag);
        Dealer_Package__c dp = dealerPackage('PS pkg ' + tag, d,
            masterPackage('PS pkg ' + tag, grp, 'Powersports', false), null);
        dealerTerm('PS pkg ' + tag, dp);

        Make__c listedMake = make('Listed Make ' + tag);
        Model__c listedModel = model(listedMake, 'Listed Model ' + tag);

        Vehicle_Schedule__c s = schedule('PS sched ' + tag, 'Powersports_Program',
            scheduleActive, validFrom, validTo);
        member(s, listedMake, null, true, false, null);            // make inclusion row
        if (addExclusionRow) {
            member(s, listedMake, listedModel, false, true, null); // model exclusion row
        }
        assignment(s, null, null, grp, Date.today(), null);        // plan-type scoped

        Make__c vMake = vehicleOnSchedule ? listedMake : make('Unlisted Make ' + tag);
        Model__c vModel = vehicleOnSchedule ? listedModel : model(vMake, 'Unlisted Model ' + tag);
        Vehicle__c bike = vehicle('PS vehicle ' + tag, vMake, vModel,
            'Powersports', 'Personal Use', null);
        Application__c app = application(d, bike);
        return readPackages(app.Id);
    }

    // ---------------------------------------------------------------
    // Powersports — positive / negative
    // ---------------------------------------------------------------

    @isTest
    static void powersportsMemberBikeSeesFivePackages() {
        setScheduleGate(true);

        Account d = dealer('GO Powertrain (test)');
        Package_Group__c grp = group('Powertrain Warranties (test)');

        List<String> names = new List<String>{
            'Powertrain Bronze (test)', 'Powertrain Silver (test)', 'Powertrain Gold (test)',
            'Powertrain Platinum 2500 (test)', 'Powertrain Platinum 3000 (test)'
        };
        for (String n : names) {
            Dealer_Package__c dp = dealerPackage(n, d, masterPackage(n, grp, 'Powersports', false),
                null);
            dealerTerm(n, dp);
        }

        Make__c harley = make('Harley-Davidson');
        Model__c glide = model(harley, 'Street Glide');

        Vehicle_Schedule__c ps = schedule('Powersports Program (test)', 'Powersports_Program',
            true, Date.today(), null);
        member(ps, harley, null, true, false, null);   // make row: all Harley-Davidson
        assignment(ps, null, null, grp, Date.today(), null);

        Vehicle__c bike = vehicle('Harley (test)', harley, glide,
            'Powersports', 'Personal Use', null);
        Application__c app = application(d, bike);

        Test.startTest();
        DealerPortalController.DealerPackagesResponse res = readPackages(app.Id);
        Test.stopTest();

        System.assertEquals(true, res.success, 'read should succeed: ' + res.message);
        System.assertNotEquals(null, res.data, 'packages expected');
        System.assertEquals(5, res.data.size(),
            'a member bike must see all 5 powersports packages');
    }

    @isTest
    static void powersportsNonMemberVehicleSeesNone() {
        setScheduleGate(true);

        DealerPortalController.DealerPackagesResponse res =
            powersportsScenario('NEG', true, Date.today(), null, false, false);

        System.assertEquals(true, res.success, res.message);
        System.assert(res.data == null || res.data.isEmpty(),
            'a powersports vehicle that is not a schedule member must see no powersports package');
    }

    // ---------------------------------------------------------------
    // Commercial — positive / negative
    // ---------------------------------------------------------------

    @isTest
    static void commercialTypedVehicleMatchesRow() {
        setScheduleGate(true);

        Account d = dealer('Commercial dealer (test)');
        Package_Group__c grp = group('Commercial Warranties (test)');
        Dealer_Package__c dp = dealerPackage('Pro Warranty (test)', d,
            masterPackage('Pro Warranty (test)', grp, 'All', true), null);
        dealerTerm('Pro Warranty (test)', dp);

        Vehicle_Schedule__c ce = schedule('Commercial Eligibility (test)',
            'Commercial_Eligibility', true, Date.today(), null);
        member(ce, null, null, true, false, 'Commercial (Medium Duty)'); // typed catch-all
        assignment(ce, null, null, grp, Date.today(), null);

        Vehicle__c van = vehicle('Box truck (test)', null, null,
            'Used Car', 'Commercial/Business Use', 'Commercial (Medium Duty)');
        Application__c app = application(d, van);

        Test.startTest();
        DealerPortalController.DealerPackagesResponse res = readPackages(app.Id);
        Test.stopTest();

        System.assertEquals(true, res.success, res.message);
        System.assertNotEquals(null, res.data, 'packages expected');
        System.assertEquals(1, res.data.size(),
            'a typed commercial vehicle that matches its row must see the package');
    }

    @isTest
    static void commercialBlankTypeFailsClosed() {
        setScheduleGate(true);

        Account d = dealer('Commercial dealer blank (test)');
        Package_Group__c grp = group('Commercial Warranties blank (test)');
        Dealer_Package__c dp = dealerPackage('Pro Warranty blank (test)', d,
            masterPackage('Pro Warranty blank (test)', grp, 'All', true), null);
        dealerTerm('Pro Warranty blank (test)', dp);

        Vehicle_Schedule__c ce = schedule('Commercial Eligibility blank (test)',
            'Commercial_Eligibility', true, Date.today(), null);
        member(ce, null, null, true, false, 'Commercial (Medium Duty)'); // typed row
        assignment(ce, null, null, grp, Date.today(), null);

        // Commercial vehicle but NO commercial type => cannot match the typed row.
        Vehicle__c van = vehicle('Box truck blank (test)', null, null,
            'Used Car', 'Commercial/Business Use', null);
        Application__c app = application(d, van);

        Test.startTest();
        DealerPortalController.DealerPackagesResponse res = readPackages(app.Id);
        Test.stopTest();

        System.assertEquals(true, res.success, res.message);
        System.assert(res.data == null || res.data.isEmpty(),
            'a commercial vehicle with a blank commercial type must fail closed');
    }

    // ---------------------------------------------------------------
    // Fail-closed schedule states: inactive / expired / exclusion
    // ---------------------------------------------------------------

    @isTest
    static void inactiveScheduleFailsClosed() {
        setScheduleGate(true);
        DealerPortalController.DealerPackagesResponse res =
            powersportsScenario('INACT', false, Date.today(), null, false, true);

        System.assertEquals(true, res.success, res.message);
        System.assert(res.data == null || res.data.isEmpty(),
            'an inactive schedule must not grant powersports membership');
    }

    @isTest
    static void expiredEffectivityWindowFailsClosed() {
        setScheduleGate(true);
        DealerPortalController.DealerPackagesResponse res = powersportsScenario(
            'EXP', true, Date.today().addDays(-90), Date.today().addDays(-1), false, true);

        System.assertEquals(true, res.success, res.message);
        System.assert(res.data == null || res.data.isEmpty(),
            'an expired schedule window must not grant powersports membership');
    }

    @isTest
    static void exclusionRowFailsClosed() {
        setScheduleGate(true);
        DealerPortalController.DealerPackagesResponse res =
            powersportsScenario('EXCL', true, Date.today(), null, true, true);

        System.assertEquals(true, res.success, res.message);
        System.assert(res.data == null || res.data.isEmpty(),
            'an exclusion row must remove the vehicle from the schedule (no membership)');
    }

    // ---------------------------------------------------------------
    // Ordinary-vehicle isolation
    // ---------------------------------------------------------------

    @isTest
    static void ordinaryVehicleIsolation() {
        setScheduleGate(true);

        Account d = dealer('Isolation dealer (test)');
        Package_Group__c grp = group('Isolation group (test)');

        Dealer_Package__c ordinaryPkg = dealerPackage('Ordinary pkg (test)', d,
            masterPackage('Ordinary pkg (test)', grp, 'All', false), null);
        dealerTerm('Ordinary pkg (test)', ordinaryPkg);

        Dealer_Package__c psPkg = dealerPackage('PS pkg iso (test)', d,
            masterPackage('PS pkg iso (test)', grp, 'Powersports', false), null);
        dealerTerm('PS pkg iso (test)', psPkg);

        Make__c toyota = make('Toyota iso');
        Model__c camry = model(toyota, 'Camry iso');
        // The powersports schedule even lists this make, so the ONLY reason the
        // powersports package is dropped is the vehicle's non-Powersports
        // designation (isolation), not the schedule.
        Vehicle_Schedule__c psSched = schedule('PS iso schedule (test)', 'Powersports_Program',
            true, Date.today(), null);
        member(psSched, toyota, null, true, false, null);
        assignment(psSched, null, null, grp, Date.today(), null);

        Vehicle__c car = vehicle('Camry iso (test)', toyota, camry,
            'Used Car', 'Personal Use', null);
        Application__c app = application(d, car);

        Test.startTest();
        DealerPortalController.DealerPackagesResponse res = readPackages(app.Id);
        Test.stopTest();

        System.assertEquals(true, res.success, res.message);
        System.assertNotEquals(null, res.data, 'packages expected');
        System.assertEquals(1, res.data.size(), 'only the ordinary package may be returned');
        System.assertEquals(ordinaryPkg.Id, res.data[0].Id,
            'no powersports line for an ordinary vehicle');
    }

    // ---------------------------------------------------------------
    // Feature flag: OFF = legacy unchanged; ON = fail-closed gate
    // ---------------------------------------------------------------

    @isTest
    static void flagOffLegacyBehaviourUnchanged() {
        setScheduleGate(false);

        Account d = dealer('Legacy dealer (test)');
        Package_Group__c grp = group('Legacy group (test)');
        Dealer_Package__c dp = dealerPackage('Legacy PS pkg (test)', d,
            masterPackage('Legacy PS pkg (test)', grp, 'Powersports', false), null);
        dealerTerm('Legacy PS pkg (test)', dp);

        // A Powersports vehicle with NO schedule at all: the ON gate would drop
        // this package; the OFF flag must return it exactly as today.
        Make__c kawasaki = make('Kawasaki legacy');
        Model__c ninja = model(kawasaki, 'Ninja legacy');
        Vehicle__c bike = vehicle('Ninja legacy (test)', kawasaki, ninja,
            'Powersports', 'Personal Use', null);
        Application__c app = application(d, bike);

        Test.startTest();
        DealerPortalController.DealerPackagesResponse res = readPackages(app.Id);
        Test.stopTest();

        System.assertEquals(true, res.success, res.message);
        System.assertNotEquals(null, res.data, 'flag off: legacy payload expected');
        System.assertEquals(1, res.data.size(),
            'flag off: the powersports package is returned unchanged (legacy behaviour)');
        System.assertEquals(dp.Id, res.data[0].Id, 'the legacy package must be returned');
    }

    @isTest
    static void flagOnNonMemberPowersportsVehicleSeesNothing() {
        setScheduleGate(true);

        Account d = dealer('Gate-on dealer (test)');
        Package_Group__c grp = group('Gate-on group (test)');
        Dealer_Package__c dp = dealerPackage('Gate-on PS pkg (test)', d,
            masterPackage('Gate-on PS pkg (test)', grp, 'Powersports', false), null);
        dealerTerm('Gate-on PS pkg (test)', dp);

        Make__c kawasaki = make('Kawasaki gate-on');
        Model__c ninja = model(kawasaki, 'Ninja gate-on');
        Vehicle__c bike = vehicle('Ninja gate-on (test)', kawasaki, ninja,
            'Powersports', 'Personal Use', null);
        Application__c app = application(d, bike);

        Test.startTest();
        DealerPortalController.DealerPackagesResponse res = readPackages(app.Id);
        Test.stopTest();

        System.assertEquals(true, res.success, res.message);
        System.assert(res.data == null || res.data.isEmpty(),
            'flag on: a powersports vehicle with no schedule membership must fail closed');
    }
}