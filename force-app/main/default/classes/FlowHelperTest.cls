/**
 * FlowHelperTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Coverage target: 99%+
 *
 * Covers every branch of:
 *   DateCalculationFlowHelper.monthsBetweenDates
 *     • null startDate / null endDate / both null → months = null
 *     • same month       → 0
 *     • exact year diff  → 12
 *     • end day < start day → months decremented
 *     • end day >= start day → months not decremented
 *     • bulk list (multiple requests in one call)
 *
 *   DistanceDrivenFlowHelper.calculateDistanceDriven
 *     • blank purchaseUnit / blank lossUnit → null result, continue
 *     • same unit KM  → straight subtraction, unit = KM
 *     • same unit Miles → straight subtraction, unit = Miles
 *     • purchaseUnit Miles, lossUnit KM → purchase converted, unit = KM
 *     • purchaseUnit KM, lossUnit Miles → loss converted, unit = KM
 *     • both Miles different → both converted, unit = KM
 *     • bulk list (multiple requests in one call)
 */
@isTest
private class FlowHelperTest {

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 1 — DateCalculationFlowHelper
    // ─────────────────────────────────────────────────────────────────────────

    // ── helpers ──────────────────────────────────────────────────────────────

    private static DateCalculationFlowHelper.MonthsBetweenRequest dateReq(
        Date startDate,
        Date endDate
    ) {
        DateCalculationFlowHelper.MonthsBetweenRequest req =
            new DateCalculationFlowHelper.MonthsBetweenRequest();
        req.startDate = startDate;
        req.endDate   = endDate;
        return req;
    }

    private static Integer callMonths(Date startDate, Date endDate) {
        List<DateCalculationFlowHelper.MonthsBetweenResponse> responses =
            DateCalculationFlowHelper.monthsBetweenDates(
                new List<DateCalculationFlowHelper.MonthsBetweenRequest>{
                    dateReq(startDate, endDate)
                }
            );
        return responses[0].months;
    }

    // ── null guards ───────────────────────────────────────────────────────────

    @isTest
    static void testMonths_nullStartDate_returnsNull() {
        Test.startTest();
            Integer result = callMonths(null, Date.newInstance(2024, 6, 1));
        Test.stopTest();

        System.assertEquals(null, result,
            'months should be null when startDate is null');
    }

    @isTest
    static void testMonths_nullEndDate_returnsNull() {
        Test.startTest();
            Integer result = callMonths(Date.newInstance(2024, 1, 1), null);
        Test.stopTest();

        System.assertEquals(null, result,
            'months should be null when endDate is null');
    }

    @isTest
    static void testMonths_bothNull_returnsNull() {
        Test.startTest();
            Integer result = callMonths(null, null);
        Test.stopTest();

        System.assertEquals(null, result,
            'months should be null when both dates are null');
    }

    // ── same month ────────────────────────────────────────────────────────────

    @isTest
    static void testMonths_sameDates_returnsZero() {
        Date d = Date.newInstance(2024, 3, 15);

        Test.startTest();
            Integer result = callMonths(d, d);
        Test.stopTest();

        System.assertEquals(0, result,
            'months between the same date should be 0');
    }

    @isTest
    static void testMonths_sameMonthDifferentDay_endDayGreater_returnsZero() {
        // Same month, end day > start day → no decrement → 0
        Test.startTest();
            Integer result = callMonths(
                Date.newInstance(2024, 5, 10),
                Date.newInstance(2024, 5, 20)
            );
        Test.stopTest();

        System.assertEquals(0, result,
            'Same month with end day >= start day should return 0');
    }

    // ── end day < start day → decrement ──────────────────────────────────────

    @isTest
    static void testMonths_endDayLessThanStartDay_monthsDecremented() {
        // Jan 31 → Feb 28 : raw = 1, but endDay(28) < startDay(31) → months--  = 0
        Test.startTest();
            Integer result = callMonths(
                Date.newInstance(2024, 1, 31),
                Date.newInstance(2024, 2, 28)
            );
        Test.stopTest();

        System.assertEquals(0, result,
            'End day < start day should decrement months by 1');
    }

    @isTest
    static void testMonths_endDayLessThanStartDay_threeMonths() {
        // Mar 20 → Jun 15 : raw = 3, endDay(15) < startDay(20) → months-- = 2
        Test.startTest();
            Integer result = callMonths(
                Date.newInstance(2024, 3, 20),
                Date.newInstance(2024, 6, 15)
            );
        Test.stopTest();

        System.assertEquals(2, result,
            'Three raw months minus decrement should equal 2');
    }

    // ── end day >= start day → no decrement ──────────────────────────────────

    @isTest
    static void testMonths_endDayEqualsStartDay_exactMonths() {
        // Jan 15 → Jun 15 : raw = 5, endDay(15) == startDay(15) → no decrement = 5
        Test.startTest();
            Integer result = callMonths(
                Date.newInstance(2024, 1, 15),
                Date.newInstance(2024, 6, 15)
            );
        Test.stopTest();

        System.assertEquals(5, result,
            'When end day equals start day months should not be decremented');
    }

    @isTest
    static void testMonths_exactOneYear_returns12() {
        Test.startTest();
            Integer result = callMonths(
                Date.newInstance(2023, 1, 1),
                Date.newInstance(2024, 1, 1)
            );
        Test.stopTest();

        System.assertEquals(12, result,
            'Exactly one year apart should return 12 months');
    }

    @isTest
    static void testMonths_crossYearBoundary_endDayGreater() {
        // Nov 5 2023 → Feb 10 2024 : raw = 3, endDay(10) > startDay(5) → 3
        Test.startTest();
            Integer result = callMonths(
                Date.newInstance(2023, 11, 5),
                Date.newInstance(2024, 2, 10)
            );
        Test.stopTest();

        System.assertEquals(3, result,
            'Cross-year months should be calculated correctly');
    }

    @isTest
    static void testMonths_crossYearBoundary_endDayLess() {
        // Nov 20 2023 → Feb 10 2024 : raw = 3, endDay(10) < startDay(20) → 2
        Test.startTest();
            Integer result = callMonths(
                Date.newInstance(2023, 11, 20),
                Date.newInstance(2024, 2, 10)
            );
        Test.stopTest();

        System.assertEquals(2, result,
            'Cross-year with end day < start day should decrement');
    }

    @isTest
    static void testMonths_negativeResult_endBeforeStart() {
        // End before start → negative months (no special handling in controller)
        Test.startTest();
            Integer result = callMonths(
                Date.newInstance(2024, 6, 1),
                Date.newInstance(2024, 1, 1)
            );
        Test.stopTest();

        System.assertEquals(-5, result,
            'End before start should return negative months');
    }

    // ── bulk list ─────────────────────────────────────────────────────────────

    @isTest
    static void testMonths_bulkList_allRequestsProcessed() {
        List<DateCalculationFlowHelper.MonthsBetweenRequest> reqs =
            new List<DateCalculationFlowHelper.MonthsBetweenRequest>{
                dateReq(null, null),
                dateReq(Date.newInstance(2024, 1, 1), Date.newInstance(2024, 6, 1)),
                dateReq(Date.newInstance(2024, 1, 31), Date.newInstance(2024, 2, 28)),
                dateReq(Date.newInstance(2023, 1, 15), Date.newInstance(2024, 1, 15))
            };

        Test.startTest();
            List<DateCalculationFlowHelper.MonthsBetweenResponse> responses =
                DateCalculationFlowHelper.monthsBetweenDates(reqs);
        Test.stopTest();

        System.assertEquals(4, responses.size(),
            'Response count should match request count');
        System.assertEquals(null, responses[0].months,  'Both null → null');
        System.assertEquals(5,    responses[1].months,  'Jan→Jun same year = 5');
        System.assertEquals(0,    responses[2].months,  'Jan31→Feb28 = 0 after decrement');
        System.assertEquals(12,   responses[3].months,  'Exact year = 12');
    }

    // ── wrapper class properties ──────────────────────────────────────────────

    @isTest
    static void testDateWrappers_allPropertiesGetAndSet() {
        DateCalculationFlowHelper.MonthsBetweenRequest req =
            new DateCalculationFlowHelper.MonthsBetweenRequest();
        req.startDate = Date.newInstance(2024, 1, 1);
        req.endDate   = Date.newInstance(2024, 6, 1);

        System.assertEquals(Date.newInstance(2024, 1, 1), req.startDate,
            'startDate should match');
        System.assertEquals(Date.newInstance(2024, 6, 1), req.endDate,
            'endDate should match');

        DateCalculationFlowHelper.MonthsBetweenResponse resp =
            new DateCalculationFlowHelper.MonthsBetweenResponse();
        resp.months = 5;
        System.assertEquals(5, resp.months, 'months should match');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 2 — DistanceDrivenFlowHelper
    // ─────────────────────────────────────────────────────────────────────────

    // ── helpers ──────────────────────────────────────────────────────────────

    private static DistanceDrivenFlowHelper.DistanceDrivenRequest distReq(
        Decimal purchaseOdometer,
        String  purchaseUnit,
        Decimal lossOdometer,
        String  lossUnit
    ) {
        DistanceDrivenFlowHelper.DistanceDrivenRequest req =
            new DistanceDrivenFlowHelper.DistanceDrivenRequest();
        req.purchaseOdometer     = purchaseOdometer;
        req.purchaseOdometerUnit = purchaseUnit;
        req.lossOdometer         = lossOdometer;
        req.lossOdometerUnit     = lossUnit;
        return req;
    }

    private static DistanceDrivenFlowHelper.DistanceDrivenResponse callDist(
        Decimal purchaseOdometer,
        String  purchaseUnit,
        Decimal lossOdometer,
        String  lossUnit
    ) {
        List<DistanceDrivenFlowHelper.DistanceDrivenResponse> responses =
            DistanceDrivenFlowHelper.calculateDistanceDriven(
                new List<DistanceDrivenFlowHelper.DistanceDrivenRequest>{
                    distReq(purchaseOdometer, purchaseUnit, lossOdometer, lossUnit)
                }
            );
        return responses[0];
    }

    // ── blank unit guards → continue ─────────────────────────────────────────

    @isTest
    static void testDist_blankPurchaseUnit_returnsNull() {
        Test.startTest();
            DistanceDrivenFlowHelper.DistanceDrivenResponse resp =
                callDist(10000, '', 50000, 'KM');
        Test.stopTest();

        System.assertEquals(null, resp.distanceDriven,
            'distanceDriven should be null when purchaseUnit is blank');
        System.assertEquals(null, resp.distanceDrivenUnit,
            'distanceDrivenUnit should be null when purchaseUnit is blank');
    }

    @isTest
    static void testDist_blankLossUnit_returnsNull() {
        Test.startTest();
            DistanceDrivenFlowHelper.DistanceDrivenResponse resp =
                callDist(10000, 'KM', 50000, '');
        Test.stopTest();

        System.assertEquals(null, resp.distanceDriven,
            'distanceDriven should be null when lossUnit is blank');
        System.assertEquals(null, resp.distanceDrivenUnit,
            'distanceDrivenUnit should be null when lossUnit is blank');
    }

    @isTest
    static void testDist_nullPurchaseUnit_returnsNull() {
        Test.startTest();
            DistanceDrivenFlowHelper.DistanceDrivenResponse resp =
                callDist(10000, null, 50000, 'KM');
        Test.stopTest();

        System.assertEquals(null, resp.distanceDriven,
            'distanceDriven should be null when purchaseUnit is null');
        System.assertEquals(null, resp.distanceDrivenUnit,
            'distanceDrivenUnit should be null when purchaseUnit is null');
    }

    @isTest
    static void testDist_nullLossUnit_returnsNull() {
        Test.startTest();
            DistanceDrivenFlowHelper.DistanceDrivenResponse resp =
                callDist(10000, 'KM', 50000, null);
        Test.stopTest();

        System.assertEquals(null, resp.distanceDriven,
            'distanceDriven should be null when lossUnit is null');
        System.assertEquals(null, resp.distanceDrivenUnit,
            'distanceDrivenUnit should be null when lossUnit is null');
    }

    // ── same unit KM ──────────────────────────────────────────────────────────

    @isTest
    static void testDist_bothKM_straightSubtraction() {
        Test.startTest();
            DistanceDrivenFlowHelper.DistanceDrivenResponse resp =
                callDist(10000, 'KM', 60000, 'KM');
        Test.stopTest();

        System.assertEquals(50000, resp.distanceDriven,
            'distanceDriven should be 60000 - 10000 = 50000');
        System.assertEquals('KM', resp.distanceDrivenUnit,
            'distanceDrivenUnit should be KM');
    }

    @isTest
    static void testDist_bothKM_zeroDistance() {
        Test.startTest();
            DistanceDrivenFlowHelper.DistanceDrivenResponse resp =
                callDist(25000, 'KM', 25000, 'KM');
        Test.stopTest();

        System.assertEquals(0, resp.distanceDriven,
            'Zero distance driven should return 0');
        System.assertEquals('KM', resp.distanceDrivenUnit,
            'Unit should still be KM');
    }

    // ── same unit Miles ───────────────────────────────────────────────────────

    @isTest
    static void testDist_bothMiles_straightSubtraction() {
        Test.startTest();
            DistanceDrivenFlowHelper.DistanceDrivenResponse resp =
                callDist(5000, 'Miles', 20000, 'Miles');
        Test.stopTest();

        System.assertEquals(15000, resp.distanceDriven,
            'distanceDriven should be 20000 - 5000 = 15000');
        System.assertEquals('Miles', resp.distanceDrivenUnit,
            'distanceDrivenUnit should be Miles when both units are Miles');
    }

    // ── mixed units — purchaseUnit Miles, lossUnit KM ────────────────────────

    @isTest
    static void testDist_purchaseMiles_lossKM_purchaseConverted() {
        // purchase 100 Miles → 100 * 1.60934 = 160.934 KM
        // loss 300 KM
        // distance = 300 - 160.934 = 139.066
        Decimal expectedPurchaseKm = 100 * 1.60934;
        Decimal expectedDistance   = 300 - expectedPurchaseKm;

        Test.startTest();
            DistanceDrivenFlowHelper.DistanceDrivenResponse resp =
                callDist(100, 'Miles', 300, 'KM');
        Test.stopTest();

        System.assertEquals(expectedDistance, resp.distanceDriven,
            'Purchase in Miles should be converted to KM before subtraction');
        System.assertEquals('KM', resp.distanceDrivenUnit,
            'Result unit should be KM when units differ');
    }

    // ── mixed units — purchaseUnit KM, lossUnit Miles ────────────────────────

    @isTest
    static void testDist_purchaseKM_lossMiles_lossConverted() {
        // purchase 100 KM (no conversion)
        // loss 200 Miles → 200 * 1.60934 = 321.868 KM
        // distance = 321.868 - 100 = 221.868
        Decimal expectedLossKm   = 200 * 1.60934;
        Decimal expectedDistance = expectedLossKm - 100;

        Test.startTest();
            DistanceDrivenFlowHelper.DistanceDrivenResponse resp =
                callDist(100, 'KM', 200, 'Miles');
        Test.stopTest();

        System.assertEquals(expectedDistance, resp.distanceDriven,
            'Loss in Miles should be converted to KM before subtraction');
        System.assertEquals('KM', resp.distanceDrivenUnit,
            'Result unit should be KM when units differ');
    }

    // ── mixed units — both Miles but treated as different (not possible by
    //    design — this path only triggers when purchaseUnit != lossUnit)
    //    Extra edge: one blank triggers the continue guard above ───────────────

    @isTest
    static void testDist_negativeDistance_lossLessThanPurchase() {
        // Loss odometer somehow less than purchase → negative distance
        Test.startTest();
            DistanceDrivenFlowHelper.DistanceDrivenResponse resp =
                callDist(50000, 'KM', 30000, 'KM');
        Test.stopTest();

        System.assertEquals(-20000, resp.distanceDriven,
            'Negative distance should be returned without modification');
        System.assertEquals('KM', resp.distanceDrivenUnit,
            'Unit should still be KM');
    }

    // ── bulk list ─────────────────────────────────────────────────────────────

    @isTest
    static void testDist_bulkList_allRequestsProcessed() {
        List<DistanceDrivenFlowHelper.DistanceDrivenRequest> reqs =
            new List<DistanceDrivenFlowHelper.DistanceDrivenRequest>{
                distReq(10000, '',      50000, 'KM'),    // blank → null
                distReq(10000, 'KM',   60000, 'KM'),    // same KM → 50000
                distReq(5000,  'Miles',20000, 'Miles'), // same Miles → 15000
                distReq(100,   'Miles',300,   'KM')     // mixed → converted
            };

        Test.startTest();
            List<DistanceDrivenFlowHelper.DistanceDrivenResponse> responses =
                DistanceDrivenFlowHelper.calculateDistanceDriven(reqs);
        Test.stopTest();

        System.assertEquals(4, responses.size(),
            'Response count should match request count');

        System.assertEquals(null,  responses[0].distanceDriven,
            'Blank unit → null');
        System.assertEquals(null,  responses[0].distanceDrivenUnit,
            'Blank unit → null unit');

        System.assertEquals(50000, responses[1].distanceDriven,
            'Both KM → 50000');
        System.assertEquals('KM',  responses[1].distanceDrivenUnit,
            'Both KM → unit KM');

        System.assertEquals(15000, responses[2].distanceDriven,
            'Both Miles → 15000');
        System.assertEquals('Miles', responses[2].distanceDrivenUnit,
            'Both Miles → unit Miles');

        Decimal expectedDistance = 300 - (100 * 1.60934);
        System.assertEquals(expectedDistance, responses[3].distanceDriven,
            'Mixed units → purchase converted, result KM');
        System.assertEquals('KM', responses[3].distanceDrivenUnit,
            'Mixed units → result unit KM');
    }

    // ── wrapper class properties ──────────────────────────────────────────────

    @isTest
    static void testDistWrappers_allPropertiesGetAndSet() {
        DistanceDrivenFlowHelper.DistanceDrivenRequest req =
            new DistanceDrivenFlowHelper.DistanceDrivenRequest();
        req.purchaseOdometer     = 10000;
        req.purchaseOdometerUnit = 'KM';
        req.lossOdometer         = 50000;
        req.lossOdometerUnit     = 'Miles';

        System.assertEquals(10000,   req.purchaseOdometer,     'purchaseOdometer should match');
        System.assertEquals('KM',    req.purchaseOdometerUnit, 'purchaseOdometerUnit should match');
        System.assertEquals(50000,   req.lossOdometer,         'lossOdometer should match');
        System.assertEquals('Miles', req.lossOdometerUnit,     'lossOdometerUnit should match');

        DistanceDrivenFlowHelper.DistanceDrivenResponse resp =
            new DistanceDrivenFlowHelper.DistanceDrivenResponse();
        resp.distanceDriven     = 40000;
        resp.distanceDrivenUnit = 'KM';

        System.assertEquals(40000, resp.distanceDriven,     'distanceDriven should match');
        System.assertEquals('KM',  resp.distanceDrivenUnit, 'distanceDrivenUnit should match');
    }
}