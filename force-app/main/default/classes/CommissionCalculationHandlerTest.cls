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

    // ------------------------------------------------------------------
    // P4 [A/T] re-wire (plan 04.3): engine-priced quotes carry
    // Dealer_Package_Term__c / Dealer_Package__c but NOT the master
    // Package_Term__c / Package__c links, so the handler must read the
    // wholesale anchor from Dealer_Package_Term.Original_Package_Term_Cost__c
    // (the sync-written mirror of master Price__c — the field the pricing
    // engine prices from) and reach the Package__c config via the dealer
    // package. Legacy records keep the historic master-term path; parity is
    // asserted pairwise below.
    // ------------------------------------------------------------------

    private static Package__c configPkg(Decimal thresholdPct, Decimal reservePct,
                                        Decimal reserveFloor, Decimal commRatePct) {
        Package__c pkg = new Package__c(
            Name = 'Engine Config Pkg',
            Discount_Threshold_Pct__c = thresholdPct,
            Reserve_Pct__c = reservePct,
            Reserve_Floor__c = reserveFloor,
            Commission_Rate_Pct__c = commRatePct
        );
        insert pkg;
        return pkg;
    }

    private static Application_Package__c insertAp(Boolean enginePriced, Id dptId,
                                                   Id pkgId, Id ptId, Id dpId, Id dealerId) {
        Application__c app = new Application__c();
        insert app;
        Application_Package__c ap = new Application_Package__c(
            Name = 'Test AP ' + (enginePriced ? 'ENG' : 'LEG'),
            Application__c = app.Id,
            Dealer__c = dealerId,
            Dealer_Package__c = dpId,
            Dealer_Package_Term__c = dptId,
            Active__c = true,
            Priced_By_Engine__c = enginePriced
        );
        if (!enginePriced) {
            // Legacy shape: master links populated (pre-existing fixture style).
            ap.Package__c = pkgId;
            ap.Package_Term__c = ptId;
        }
        insert ap;
        return ap;
    }

    private static Map<String, Decimal> readLedger(Id apId) {
        Application_Package__c ap = [SELECT Wholesale_Price__c, Dealer_Discount_Amount__c,
                Sales_Rep_Incentive__c, Total_Discount_Amount__c, Total_Discount_Pct__c,
                Aprotect_Net__c, Reserve_Amount__c, Commission_Base__c,
                Commission_Rate_Pct__c, Commission_Amount__c, CRM_Charge__c,
                Owed_To_Dealer__c
            FROM Application_Package__c WHERE Id = :apId];
        Map<String, Decimal> m = new Map<String, Decimal>();
        m.put('Wholesale', ap.Wholesale_Price__c);
        m.put('DealerDiscount', ap.Dealer_Discount_Amount__c);
        m.put('SalesRepIncentive', ap.Sales_Rep_Incentive__c);
        m.put('TotalDiscount', ap.Total_Discount_Amount__c);
        m.put('TotalDiscountPct', ap.Total_Discount_Pct__c);
        m.put('AprotectNet', ap.Aprotect_Net__c);
        m.put('Reserve', ap.Reserve_Amount__c);
        m.put('CommissionBase', ap.Commission_Base__c);
        m.put('CommissionRate', ap.Commission_Rate_Pct__c);
        m.put('Commission', ap.Commission_Amount__c);
        m.put('CRMCharge', ap.CRM_Charge__c);
        m.put('OwedToDealer', ap.Owed_To_Dealer__c);
        return m;
    }

    @isTest
    static void testEnginePricedReadsDealerTermAnchor() {
        // Production engine shape: the quote carries Dealer_Package_Term__c /
        // Dealer_Package__c but NOT the master Package_Term__c / Package__c
        // links (the controller seams never set them; the create-time flow
        // that used to populate them is engine-guarded off). Without the P4
        // re-wire the wholesale lookup (master-term based) finds nothing and
        // the whole commission ledger zeroes. With the re-wire the wholesale
        // anchor comes from Dealer_Package_Term.Original_Package_Term_Cost__c
        // (the sync-written mirror of the master price — the field the engine
        // prices from). Package config is absent on this shape, so the handler
        // DEFAULT constants apply (15% threshold / 50% reserve / 20% rate) —
        // the assertions are exact for those constants.
        Package__c pkg = new Package__c(Name = 'Anchor Config Pkg'); // no config
        insert pkg;
        Package_Term__c pt = new Package_Term__c(Name = 'Anchor Term', Package__c = pkg.Id, Price__c = 1000);
        insert pt;
        Account d2 = new Account(Name = 'Anchor Dealer');
        insert d2;
        Dealer_Package__c dp = new Dealer_Package__c(Name = 'Anchor DP', Dealer__c = d2.Id, Package__c = pkg.Id);
        insert dp;
        Dealer_Package_Term__c dpt = new Dealer_Package_Term__c(
            Name = 'Anchor DPT', Dealer_Package__c = dp.Id, Package_Term__c = pt.Id,
            Original_Package_Term_Cost__c = 1000,
            Discount_Value__c = 10, Discount_Type__c = '%',
            Markup__c = 100, Markup_Type__c = '$', Sales_Rep_Incentive__c = 50
        );
        insert dpt;

        Application_Package__c ap = insertAp(true, dpt.Id, pkg.Id, pt.Id, dp.Id, d2.Id);
        Map<String, Decimal> m = readLedger(ap.Id);

        // Ledger fully populated from the dealer-term anchor (no master links):
        // wholesale 1000 (dpt anchor), 10% discount + $50 incentive => total
        // discount 150 = 15% <= 15% threshold => within-threshold branch:
        // reserve = 850 * 0.50 = 425; base = 425; commission = 425 * 0.20 = 85.
        System.assertEquals(1000, m.get('Wholesale'), 'wholesale = dealer-term anchor (no master term link on AP)');
        System.assertEquals(100, m.get('DealerDiscount'), '10% of dealer anchor');
        System.assertEquals(50, m.get('SalesRepIncentive'));
        System.assertEquals(150, m.get('TotalDiscount'));
        System.assertEquals(15, m.get('TotalDiscountPct'));
        System.assertEquals(850, m.get('AprotectNet'));
        System.assertEquals(425, m.get('Reserve'), 'default 50% reserve on net 850');
        System.assertEquals(425, m.get('CommissionBase'));
        System.assertEquals(20, m.get('CommissionRate'), 'default 20% rate');
        System.assertEquals(85, m.get('Commission'));
        System.assertEquals(1000, m.get('CRMCharge'), '(1000-100) + $100 markup');
        System.assertEquals(150, m.get('OwedToDealer'), '$100 markup + $50 incentive');
    }

    @isTest
    static void testEnginePricedParityWithLegacyPath() {
        // Identical inputs through both shapes: engine-priced (no master links,
        // dealer anchor) vs legacy (master links, master price). The full
        // 12-field ledger must match pairwise (numeric parity of the re-wire).
        Package__c pkg = configPkg(15, 50, null, 20);
        Package_Term__c pt = new Package_Term__c(Name = 'Parity Term', Package__c = pkg.Id, Price__c = 1000);
        insert pt;
        Account d = new Account(Name = 'Parity Dealer');
        insert d;
        Dealer_Package__c dp = new Dealer_Package__c(Name = 'Parity DP', Dealer__c = d.Id, Package__c = pkg.Id);
        insert dp;
        Dealer_Package_Term__c dpt = new Dealer_Package_Term__c(
            Name = 'Parity DPT', Dealer_Package__c = dp.Id, Package_Term__c = pt.Id,
            Original_Package_Term_Cost__c = 1000,
            Discount_Value__c = 10, Discount_Type__c = '%',
            Markup__c = 100, Markup_Type__c = '$', Sales_Rep_Incentive__c = 50
        );
        insert dpt;

        Application_Package__c eng = insertAp(true, dpt.Id, pkg.Id, pt.Id, dp.Id, d.Id);
        Application_Package__c leg = insertAp(false, dpt.Id, pkg.Id, pt.Id, dp.Id, d.Id);

        Map<String, Decimal> em = readLedger(eng.Id);
        Map<String, Decimal> lm = readLedger(leg.Id);
        for (String k : em.keySet()) {
            System.assertEquals(lm.get(k), em.get(k), 'engine/legacy parity on ' + k);
        }
        // Spot numbers (within threshold: net 850, reserve 425, base 425, comm 85).
        System.assertEquals(850, em.get('AprotectNet'));
        System.assertEquals(425, em.get('Reserve'));
        System.assertEquals(425, em.get('CommissionBase'));
        System.assertEquals(85, em.get('Commission'));
    }
}