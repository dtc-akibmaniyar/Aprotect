@isTest
private class CommissionCalculationHandlerTest {

    // Helper to create the full hierarchy
    private static Application_Package__c createTestRecord(
        Decimal wholesalePrice,
        Decimal discountValue, String discountType,
        Decimal markup, String markupType,
        Decimal salesRepIncentive,
        Decimal discThresholdPct, Decimal reservePct, Decimal reserveFloor, Decimal commRatePct
    ) {
        // Package with config (percent fields stored as e.g. 15.0 for 15%)
        Package__c pkg = new Package__c(
            Name = 'Test Package',
            Discount_Threshold_Pct__c = discThresholdPct,
            Reserve_Pct__c = reservePct,
            Reserve_Floor__c = reserveFloor,
            Commission_Rate_Pct__c = commRatePct
        );
        insert pkg;

        // Package Term with wholesale price
        Package_Term__c pt = new Package_Term__c(
            Name = 'Test Term',
            Package__c = pkg.Id,
            Price__c = wholesalePrice
        );
        insert pt;

        // Account for Dealer
        Account dealer = new Account(Name = 'Test Dealer');
        insert dealer;

        // Dealer Package
        Dealer_Package__c dp = new Dealer_Package__c(
            Name = 'Test DP',
            Dealer__c = dealer.Id,
            Package__c = pkg.Id
        );
        insert dp;

        // Dealer Package Term (master-detail to DP and PT)
        Dealer_Package_Term__c dpt = new Dealer_Package_Term__c(
            Name = 'Test DPT',
            Dealer_Package__c = dp.Id,
            Package_Term__c = pt.Id,
            Discount_Value__c = discountValue,
            Discount_Type__c = discountType,
            Markup__c = markup,
            Markup_Type__c = markupType,
            Sales_Rep_Incentive__c = salesRepIncentive
        );
        insert dpt;

        // Application
        Application__c app = new Application__c();
        insert app;

        // Application Package
        Application_Package__c ap = new Application_Package__c(
            Name = 'Test AP',
            Application__c = app.Id,
            Package__c = pkg.Id,
            Package_Term__c = pt.Id,
            Dealer_Package__c = dp.Id,
            Dealer_Package_Term__c = dpt.Id,
            Dealer__c = dealer.Id,
            Active__c = true
        );
        insert ap;

        return [SELECT Id, Wholesale_Price__c, Dealer_Discount_Amount__c, Sales_Rep_Incentive__c,
                       Total_Discount_Amount__c, Total_Discount_Pct__c, Aprotect_Net__c,
                       Reserve_Amount__c, Commission_Base__c, Commission_Rate_Pct__c,
                       Commission_Amount__c, CRM_Charge__c, Owed_To_Dealer__c
                FROM Application_Package__c WHERE Id = :ap.Id];
    }

    @isTest
    static void testWithinThreshold() {
        // 10% discount, no incentive, no markup. Package: threshold=15%, reserve=50%, commRate=20%
        Application_Package__c ap = createTestRecord(
            1000, 10, '%', 0, '$', 0,
            15, 50, null, 20
        );
        System.assertEquals(1000, ap.Wholesale_Price__c, 'Wholesale Price');
        System.assertEquals(100, ap.Dealer_Discount_Amount__c, 'Dealer Discount');
        System.assertEquals(0, ap.Sales_Rep_Incentive__c, 'Sales Rep Incentive');
        System.assertEquals(100, ap.Total_Discount_Amount__c, 'Total Discount Amt');
        System.assertEquals(10, ap.Total_Discount_Pct__c, 'Total Discount Pct');
        System.assertEquals(900, ap.Aprotect_Net__c, 'Aprotect Net');
        System.assertEquals(450, ap.Reserve_Amount__c, 'Reserve');
        System.assertEquals(450, ap.Commission_Base__c, 'Commission Base');
        System.assertEquals(90, ap.Commission_Amount__c, 'Commission Amount');
    }

    @isTest
    static void testOverThreshold() {
        // 20% discount + $50 incentive + $100 markup. threshold=15%, reserve=50%, commRate=20%
        // reserveFloor = null → auto-calc = 0.50 * (1000 - 1000*0.15) = 0.50 * 850 = 425
        Application_Package__c ap = createTestRecord(
            1000, 20, '%', 100, '$', 50,
            15, 50, null, 20
        );
        System.assertEquals(1000, ap.Wholesale_Price__c, 'Wholesale Price');
        System.assertEquals(200, ap.Dealer_Discount_Amount__c, 'Dealer Discount');
        System.assertEquals(50, ap.Sales_Rep_Incentive__c, 'Sales Rep Incentive');
        System.assertEquals(250, ap.Total_Discount_Amount__c, 'Total Discount Amt');
        System.assertEquals(25, ap.Total_Discount_Pct__c, 'Total Discount Pct');
        System.assertEquals(750, ap.Aprotect_Net__c, 'Aprotect Net');
        System.assertEquals(425, ap.Reserve_Amount__c, 'Reserve (floor)');
        System.assertEquals(325, ap.Commission_Base__c, 'Commission Base');
        System.assertEquals(65, ap.Commission_Amount__c, 'Commission Amount');
        System.assertEquals(900, ap.CRM_Charge__c, 'CRM Charge');
        System.assertEquals(150, ap.Owed_To_Dealer__c, 'Owed To Dealer');
    }

    @isTest
    static void testHeavyDiscount() {
        // 30% discount + $100 incentive + $50 markup
        // totalDiscount = 300+100 = 400, pct = 40% > 15%
        // net = 600, floor = 425, commBase = max(0, 600-425) = 175, comm = 35
        Application_Package__c ap = createTestRecord(
            1000, 30, '%', 50, '$', 100,
            15, 50, null, 20
        );
        System.assertEquals(600, ap.Aprotect_Net__c, 'Aprotect Net');
        System.assertEquals(425, ap.Reserve_Amount__c, 'Reserve (floor)');
        System.assertEquals(175, ap.Commission_Base__c, 'Commission Base');
        System.assertEquals(35, ap.Commission_Amount__c, 'Commission Amount');
    }

    @isTest
    static void testNoDiscount() {
        // All zeros - within threshold
        Application_Package__c ap = createTestRecord(
            1000, 0, '%', 0, '$', 0,
            15, 50, null, 20
        );
        System.assertEquals(1000, ap.Aprotect_Net__c, 'Aprotect Net');
        System.assertEquals(500, ap.Reserve_Amount__c, 'Reserve');
        System.assertEquals(500, ap.Commission_Base__c, 'Commission Base');
        System.assertEquals(100, ap.Commission_Amount__c, 'Commission Amount');
    }

    @isTest
    static void testNetBelowFloor() {
        // 50% discount + $200 incentive = 70% total
        // net = 1000 - 500 - 200 = 300, floor = 425
        // commBase = max(0, 300-425) = 0, comm = 0
        Application_Package__c ap = createTestRecord(
            1000, 50, '%', 0, '$', 200,
            15, 50, null, 20
        );
        System.assertEquals(300, ap.Aprotect_Net__c, 'Aprotect Net');
        System.assertEquals(425, ap.Reserve_Amount__c, 'Reserve (floor)');
        System.assertEquals(0, ap.Commission_Base__c, 'Commission Base');
        System.assertEquals(0, ap.Commission_Amount__c, 'Commission Amount');
    }
}