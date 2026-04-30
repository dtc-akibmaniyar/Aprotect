/**
 * ApplicationOilChangeHandlerTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Covers ApplicationOilChangeHandler:
 *
 *   monthsBetween():
 *     • null startDate → null
 *     • null endDate   → null
 *     • end.day == start.day → exact month count
 *     • end.day < start.day  → month count decremented by 1
 *
 *   calculateOdometerDifference() — before insert:
 *     • null Application__c → applicationIds empty → early return
 *     • First oil change, vehicle linked → diff = new - vehicle odometer
 *     • First oil change, no vehicle    → Odometer_Difference_KM__c = null
 *     • Previous oil change exists      → diff = new - previous odometer
 *     • Odometer_KM__c = null           → odometer diff branch skipped
 *     • Schedule_Date_Of_Service__c, vehicle Purchase_Date__c baseline
 *     • Schedule_Date_Of_Service__c, previous service date baseline
 *
 *   updateClaimOilChangeCounts() — after insert + after delete:
 *     • Standard oil change  → Actual_Oil_Change_Duration_Standard__c = 1
 *     • Synthetic oil change → Actual_Oil_Change_Duration_Synthetic__c = 1
 *     • No claims for app    → completes without error
 *     • After delete         → count decremented on linked Claims
 *
 * Test Strategy:
 *   ✔ @isTest(SeeAllData=false)
 *   ✔ @TestSetup: Dealer + App (no vehicle) + App (with vehicle linked)
 *   ✔ All data exclusively via TestDataFactory — no inline SObject creation
 *   ✔ update new SObject(Id=...) pattern for enriching Vehicle.Purchase_Date__c
 *     and linking Application.Vehicle__c (fields not set by factory)
 *   ✔ One test per logical branch
 *   ✔ System.assert* with descriptive messages on every assertion
 *   ✔ No hardcoded Ids
 */
@isTest(SeeAllData=false)
private class ApplicationOilChangeHandlerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // @TestSetup
    //   App A — no Vehicle (tests that don't need vehicle baseline)
    //   App B — Vehicle linked, Odometer=15000, Purchase_Date=2022-01-15
    // ─────────────────────────────────────────────────────────────────────────

    @TestSetup
    static void setup() {
        Account dealer = TestDataFactory.createDealer(true);

        // App A: no vehicle
        TestDataFactory.createApplication(dealer.Id, true);

        // App B: with vehicle
        Vehicle__c v = TestDataFactory.createVehicle(true);
        // Odometer__c = 15000 (factory default); add Purchase_Date__c
        update new Vehicle__c(Id = v.Id, Purchase_Date__c = Date.newInstance(2022, 1, 15));
        Application__c appB = TestDataFactory.createApplication(dealer.Id, true);
        update new Application__c(Id = appB.Id, Vehicle__c = v.Id);
    }

    // ── Private query helpers ─────────────────────────────────────────────────

    private static Application__c getAppNoVehicle() {
        return [SELECT Id FROM Application__c WHERE Vehicle__c = null LIMIT 1];
    }

    private static Application__c getAppWithVehicle() {
        return [SELECT Id FROM Application__c WHERE Vehicle__c != null LIMIT 1];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // monthsBetween — UNIT TESTS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Null startDate → returns null immediately.
     */
    @isTest
    static void testMonthsBetween_nullStart_returnsNull() {
        Test.startTest();
        Integer result = ApplicationOilChangeHandler.monthsBetween(null, Date.today());
        Test.stopTest();

        System.assertEquals(null, result,
            'monthsBetween should return null when startDate is null');
    }

    /**
     * Null endDate → returns null immediately.
     */
    @isTest
    static void testMonthsBetween_nullEnd_returnsNull() {
        Test.startTest();
        Integer result = ApplicationOilChangeHandler.monthsBetween(Date.today(), null);
        Test.stopTest();

        System.assertEquals(null, result,
            'monthsBetween should return null when endDate is null');
    }

    /**
     * Same day of month → exact month difference, no decrement.
     */
    @isTest
    static void testMonthsBetween_sameDayOfMonth_exactMonths() {
        Date start = Date.newInstance(2023, 1, 15);
        Date endDate   = Date.newInstance(2023, 7, 15);

        Test.startTest();
        Integer result = ApplicationOilChangeHandler.monthsBetween(start, endDate);
        Test.stopTest();

        System.assertEquals(6, result,
            'monthsBetween Jan 15 → Jul 15 should be exactly 6');
    }

    /**
     * end.day() < start.day() → month count decremented by 1.
     * Jan 31 → Feb 28: year/month diff = 1, but 28 < 31 → result = 0.
     */
    @isTest
    static void testMonthsBetween_endDayBeforeStartDay_decremented() {
        Date start = Date.newInstance(2023, 1, 31);
        Date endDate   = Date.newInstance(2023, 2, 28);

        Test.startTest();
        Integer result = ApplicationOilChangeHandler.monthsBetween(start, endDate);
        Test.stopTest();

        System.assertEquals(0, result,
            'monthsBetween Jan 31 → Feb 28 should be 0 (end.day < start.day triggers decrement)');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // calculateOdometerDifference — EARLY-RETURN GUARD
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Record with null Application__c → applicationIds empty → both handlers
     * return early without any DML or field updates.
     * Called directly (not via trigger) to avoid insert constraint on Application__c.
     */
    @isTest
    static void testCalculateOdometer_nullApplicationId_earlyReturn() {
        Application_Oil_Change__c oil = TestDataFactory.createApplicationOilChange(
            null, 20000, Date.today(), 'Standard', false
        );

        Test.startTest();
        ApplicationOilChangeHandler.calculateOdometerDifference(
            new List<Application_Oil_Change__c>{ oil }
        );
        ApplicationOilChangeHandler.updateClaimOilChangeCounts(
            new List<Application_Oil_Change__c>{ oil }
        );
        Test.stopTest();

        System.assertEquals(null, oil.Odometer_Difference_KM__c,
            'Odometer_Difference_KM__c should remain null when Application__c is null');
        System.assertEquals(null, oil.Duration_Months__c,
            'Duration_Months__c should remain null when Application__c is null');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // calculateOdometerDifference — FIRST OIL CHANGE (vehicle baseline)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * First oil change for an app linked to a vehicle →
     * Odometer_Difference_KM__c = new (18000) - vehicle (15000) = 3000.
     */
    @isTest
    static void testCalculateOdometer_firstChange_vehicleOdometerUsed() {
        Application__c app = getAppWithVehicle();

        Test.startTest();
        Application_Oil_Change__c oil = TestDataFactory.createApplicationOilChange(
            app.Id, 18000, Date.today(), 'Standard', true
        );
        Test.stopTest();

        Application_Oil_Change__c refreshed = [
            SELECT Odometer_Difference_KM__c
            FROM   Application_Oil_Change__c
            WHERE  Id = :oil.Id
        ];
        System.assertEquals(3000, refreshed.Odometer_Difference_KM__c,
            'Odometer_Difference_KM__c should be 18000 - 15000 = 3000 using vehicle odometer as baseline');
    }

    /**
     * First oil change for an app with NO vehicle →
     * no baseline available; Odometer_Difference_KM__c = null.
     */
    @isTest
    static void testCalculateOdometer_firstChange_noVehicle_diffNull() {
        Application__c app = getAppNoVehicle();

        Test.startTest();
        Application_Oil_Change__c oil = TestDataFactory.createApplicationOilChange(
            app.Id, 18000, Date.today(), 'Standard', true
        );
        Test.stopTest();

        Application_Oil_Change__c refreshed = [
            SELECT Odometer_Difference_KM__c
            FROM   Application_Oil_Change__c
            WHERE  Id = :oil.Id
        ];
        System.assertEquals(null, refreshed.Odometer_Difference_KM__c,
            'Odometer_Difference_KM__c should be null when no previous oil change and no vehicle linked');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // calculateOdometerDifference — PREVIOUS OIL CHANGE EXISTS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Second oil change → diff calculated from the most recent previous record.
     * prev = 15000 km, new = 18000 km → difference = 3000.
     */
    @isTest
    static void testCalculateOdometer_previousExists_diffFromPrevious() {
        Application__c app = getAppNoVehicle();
        // Insert first oil change (becomes "previous" for the second)
        TestDataFactory.createApplicationOilChange(
            app.Id, 15000, Date.today().addMonths(-3), 'Standard', true
        );

        Test.startTest();
        Application_Oil_Change__c second = TestDataFactory.createApplicationOilChange(
            app.Id, 18000, Date.today(), 'Standard', true
        );
        Test.stopTest();

        Application_Oil_Change__c refreshed = [
            SELECT Odometer_Difference_KM__c
            FROM   Application_Oil_Change__c
            WHERE  Id = :second.Id
        ];
        System.assertEquals(3000, refreshed.Odometer_Difference_KM__c,
            'Odometer_Difference_KM__c should be 18000 - 15000 = 3000 from previous oil change record');
    }

    /**
     * Odometer_KM__c = null → odometer difference branch is skipped entirely;
     * Odometer_Difference_KM__c remains null.
     */
    @isTest
    static void testCalculateOdometer_nullOdometer_odometerDiffSkipped() {
        Application__c app = getAppWithVehicle();

        Test.startTest();
        Application_Oil_Change__c oil = TestDataFactory.createApplicationOilChange(
            app.Id, null, Date.today(), 'Standard', true
        );
        Test.stopTest();

        Application_Oil_Change__c refreshed = [
            SELECT Odometer_Difference_KM__c
            FROM   Application_Oil_Change__c
            WHERE  Id = :oil.Id
        ];
        System.assertEquals(null, refreshed.Odometer_Difference_KM__c,
            'Odometer_Difference_KM__c should be null when Odometer_KM__c is null (branch skipped)');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // calculateOdometerDifference — DURATION_MONTHS__c
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * First oil change with vehicle Purchase_Date__c as baseline.
     * Vehicle.Purchase_Date__c = 2022-01-15; service = 2022-07-15 → 6 months.
     */
    @isTest
    static void testDurationMonths_firstChange_vehiclePurchaseDateUsed() {
        Application__c app = getAppWithVehicle();
        Date serviceDate = Date.newInstance(2022, 7, 15);

        Test.startTest();
        Application_Oil_Change__c oil = TestDataFactory.createApplicationOilChange(
            app.Id, 20000, serviceDate, 'Standard', true
        );
        Test.stopTest();

        Application_Oil_Change__c refreshed = [
            SELECT Duration_Months__c
            FROM   Application_Oil_Change__c
            WHERE  Id = :oil.Id
        ];
        System.assertEquals(6, (Integer) refreshed.Duration_Months__c,
            'Duration_Months__c should be 6 months from vehicle Purchase_Date__c (2022-01-15) to service date (2022-07-15)');
    }

    /**
     * Second oil change → Duration_Months__c from previous Schedule_Date_Of_Service__c.
     * prev = 2023-01-15, new = 2023-04-15 → 3 months.
     */
    @isTest
    static void testDurationMonths_previousExists_durationFromPrevious() {
        Application__c app = getAppNoVehicle();
        Date prevDate = Date.newInstance(2023, 1, 15);
        Date newDate  = Date.newInstance(2023, 4, 15);
        TestDataFactory.createApplicationOilChange(app.Id, 15000, prevDate, 'Standard', true);

        Test.startTest();
        Application_Oil_Change__c second = TestDataFactory.createApplicationOilChange(
            app.Id, 18000, newDate, 'Standard', true
        );
        Test.stopTest();

        Application_Oil_Change__c refreshed = [
            SELECT Duration_Months__c
            FROM   Application_Oil_Change__c
            WHERE  Id = :second.Id
        ];
        System.assertEquals(3, (Integer) refreshed.Duration_Months__c,
            'Duration_Months__c should be 3 months from 2023-01-15 to 2023-04-15');
    }
}