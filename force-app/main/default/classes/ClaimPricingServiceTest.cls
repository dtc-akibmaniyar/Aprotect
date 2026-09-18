/**
 * Asserts ClaimPricingService reproduces the HTML calculator's own seeded
 * "LKQ used engine" scenario exactly (SCN[0] in warranty_claims_dashboard.html
 * with cap=3000, deductible=100, tax=13%). Those numbers are the acceptance
 * baseline recorded in the build plan.
 */
@IsTest
private class ClaimPricingServiceTest {

    private static ClaimPricingService.PricingInput lkqInput() {
        ClaimPricingService.PricingInput i = new ClaimPricingService.PricingInput();
        i.parts = 1500; i.coreOn = true; i.core = 200;
        i.hrs = 8; i.rate = 75; i.ins = 120;
        i.supC = 150; i.supR = 300; i.retail = 4000;
        i.cap = 3000; i.ded = 100; i.taxPercent = 13;
        return i;
    }

    @IsTest
    static void lkqUsedEngineMatchesHtmlBaseline() {
        ClaimPricingService.PricingResult r = ClaimPricingService.calculate(lkqInput());
        System.assertEquals(600,   r.labour,      'labour = 8 x 75');
        System.assertEquals(200,   r.core,        'core applied');
        System.assertEquals(1300,  r.netParts,    'net parts = 1500 - 200');
        System.assertEquals(2170,  r.wsTotal,     'wholesale = 1300 + 600 + 150 + 120');
        System.assertEquals(2900,  r.coverage,    'coverage = min(3000, 4000) - 100');
        System.assertEquals(1400,  r.custPre,     'customer pre-tax = (4000 - 2900) + 300');
        System.assertEquals(1582,  r.custTax,     'customer with tax = 1400 x 1.13');
        System.assertEquals(-770,  r.pl,          'P&L = 1400 - 2170');
        System.assertEquals(4300,  r.retailTotal, 'retail total = 4000 + 300');
    }

    @IsTest
    static void coreIgnoredWhenNotApplied() {
        ClaimPricingService.PricingInput i = lkqInput();
        i.coreOn = false;
        ClaimPricingService.PricingResult r = ClaimPricingService.calculate(i);
        System.assertEquals(0,    r.core);
        System.assertEquals(1500, r.netParts, 'no core deduction when coreOn is false');
    }

    @IsTest
    static void coverageNeverNegativeAndCappedAtRetail() {
        ClaimPricingService.PricingInput i = lkqInput();
        i.retail = 50; i.ded = 100;
        ClaimPricingService.PricingResult r = ClaimPricingService.calculate(i);
        System.assertEquals(0, r.coverage, 'min(cap, 50) - 100 clamps to 0');
        System.assertEquals(350, r.custPre, 'customer pays full 50 retail + 300 supplies');
    }

    @IsTest
    static void nullInputsTreatedAsZero() {
        ClaimPricingService.PricingResult r =
            ClaimPricingService.calculate(new ClaimPricingService.PricingInput());
        System.assertEquals(0, r.wsTotal);
        System.assertEquals(0, r.retailTotal);
        System.assertEquals(0, r.pl);
    }

    @IsTest
    static void recalculateAndStampWritesLkqTotalsOntoEstimate() {
        Estimate__c created = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);

        Repair_Shop__c shop = [SELECT Id FROM Repair_Shop__c WHERE Id = :created.Repair_Shop__c];
        shop.Tax_Percentage__c = 13;
        update shop;

        // Re-query a clean instance: the factory's returned record still carries the
        // non-reparentable master-detail Claim__c in memory, which an update rejects.
        Estimate__c e = [SELECT Id FROM Estimate__c WHERE Id = :created.Id];
        e.Parts_Cost__c = 1500; e.Core_Charge_Applies__c = true; e.Core_Charge__c = 200;
        e.Labour_Hours__c = 8; e.Labour_Rate__c = 75; e.Insurance_Amount__c = 120;
        e.Shop_Supplies__c = 150; e.Shop_Supplies_Retail__c = 300; e.Retail_Price__c = 4000;
        e.Deductable__c = 100;
        update e;

        Test.startTest();
        ClaimPricingService.PricingResult r = ClaimPricingService.recalculateAndStamp(e.Id, 3000);
        Test.stopTest();

        System.assertEquals(2170, r.wsTotal, 'returned result matches baseline');

        Estimate__c stamped = [
            SELECT Labour_Cost__c, Net_Parts__c, Wholesale_Cost__c, Coverage_Applied__c,
                   Customer_Pays__c, Customer_Pays_With_Tax__c, Profit_Loss__c, Retail_Total__c
            FROM Estimate__c WHERE Id = :e.Id
        ];
        System.assertEquals(600,  stamped.Labour_Cost__c);
        System.assertEquals(1300, stamped.Net_Parts__c);
        System.assertEquals(2170, stamped.Wholesale_Cost__c);
        System.assertEquals(2900, stamped.Coverage_Applied__c);
        System.assertEquals(1400, stamped.Customer_Pays__c);
        System.assertEquals(1582, stamped.Customer_Pays_With_Tax__c);
        System.assertEquals(-770, stamped.Profit_Loss__c);
        System.assertEquals(4300, stamped.Retail_Total__c);
    }

    @IsTest
    static void recalculateFallsBackToShopRateWhenEstimateRateBlank() {
        Estimate__c created = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        Repair_Shop__c shop = [SELECT Id FROM Repair_Shop__c WHERE Id = :created.Repair_Shop__c];
        shop.Labour_Rate_On_File__c = 75;
        update shop;
        Estimate__c e = [SELECT Id FROM Estimate__c WHERE Id = :created.Id];
        e.Labour_Hours__c = 8; e.Labour_Rate__c = null;
        update e;

        ClaimPricingService.PricingResult r = ClaimPricingService.recalculateAndStamp(e.Id, 3000);
        System.assertEquals(600, r.labour, 'uses the shop on-file rate when the estimate rate is blank');
    }

    @IsTest
    static void calculateLiveDelegatesToCalculate() {
        ClaimPricingService.PricingResult r = ClaimPricingService.calculateLive(lkqInput());
        System.assertEquals(2170, r.wsTotal);
    }
}