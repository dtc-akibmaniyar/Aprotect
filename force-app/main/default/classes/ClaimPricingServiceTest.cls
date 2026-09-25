/**
 * Asserts ClaimPricingService reproduces warranty_claims_dashboard (2).html's
 * own seeded "LKQ used engine" scenario exactly (cap=3000, deductible=100,
 * tax=13%). Sep 22: file (2) superseded the original file as the pricing
 * source of truth and drops Core Charge from the formula entirely, so
 * wsTotal for this same input set is 2370, not the original 2170.
 */
@IsTest
private class ClaimPricingServiceTest {

    private static ClaimPricingService.PricingInput lkqInput() {
        ClaimPricingService.PricingInput i = new ClaimPricingService.PricingInput();
        i.parts = 1500;
        i.hrs = 8; i.rate = 75; i.ins = 120;
        i.supC = 150; i.supR = 300; i.retail = 4000;
        i.cap = 3000; i.ded = 100; i.taxPercent = 13;
        return i;
    }

    @IsTest
    static void lkqUsedEngineMatchesHtmlBaseline() {
        ClaimPricingService.PricingResult r = ClaimPricingService.calculate(lkqInput());
        System.assertEquals(600,   r.labour,      'labour = 8 x 75');
        System.assertEquals(2370,  r.wsTotal,     'wholesale = 1500 + 600 + 150 + 120 (no core charge)');
        System.assertEquals(2900,  r.coverage,    'coverage = min(3000, 4000) - 100');
        System.assertEquals(1400,  r.custPre,     'customer pre-tax = (4000 - 2900) + 300');
        System.assertEquals(1582,  r.custTax,     'customer with tax = 1400 x 1.13');
        System.assertEquals(-970,  r.pl,          'P&L = 1400 - 2370');
        System.assertEquals(4300,  r.retailTotal, 'retail total = 4000 + 300');
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
        e.Parts_Cost__c = 1500;
        e.Labour_Hours__c = 8; e.Labour_Rate__c = 75; e.Insurance_Amount__c = 120;
        e.Shop_Supplies__c = 150; e.Shop_Supplies_Retail__c = 300; e.Retail_Price__c = 4000;
        e.Deductable__c = 100;
        update e;

        Test.startTest();
        ClaimPricingService.PricingResult r = ClaimPricingService.recalculateAndStamp(e.Id, 3000);
        Test.stopTest();

        System.assertEquals(2370, r.wsTotal, 'returned result matches the no-core-charge baseline');

        Estimate__c stamped = [
            SELECT Labour_Cost__c, Wholesale_Cost__c, Coverage_Applied__c,
                   Customer_Pays__c, Customer_Pays_With_Tax__c, Profit_Loss__c, Retail_Total__c
            FROM Estimate__c WHERE Id = :e.Id
        ];
        System.assertEquals(600,  stamped.Labour_Cost__c);
        System.assertEquals(2370, stamped.Wholesale_Cost__c);
        System.assertEquals(2900, stamped.Coverage_Applied__c);
        System.assertEquals(1400, stamped.Customer_Pays__c);
        System.assertEquals(1582, stamped.Customer_Pays_With_Tax__c);
        System.assertEquals(-970, stamped.Profit_Loss__c);
        System.assertEquals(4300, stamped.Retail_Total__c);
    }

    @IsTest
    static void recalculateResolvesCapAndDeductibleFromApplicationPackage() {
        Estimate__c created = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        Claim__c claim = [SELECT Id, Application__c FROM Claim__c WHERE Id = :created.Claim__c];

        // The customer's purchased contract carries the per-claim limit and deductible.
        // Insert bare, then set the contract values by update: the Application team's
        // create-only flow overwrites Per_Claim_Limit__c / Deductible__c on insert.
        Application_Package__c pkg = new Application_Package__c(
            Application__c = claim.Application__c, Payment_Status__c = 'Not Paid');
        insert pkg;
        update new Application_Package__c(Id = pkg.Id, Per_Claim_Limit__c = 3000, Deductible__c = 100);
        claim.Application_Package__c = pkg.Id;
        update claim;

        Repair_Shop__c shop = [SELECT Id FROM Repair_Shop__c WHERE Id = :created.Repair_Shop__c];
        shop.Tax_Percentage__c = 13;
        update shop;

        // No Deductable__c on the estimate and no cap passed: both must come from the package.
        // (TestDataFactory.createEstimate presets Deductable__c = 250, so clear it explicitly.)
        Estimate__c e = [SELECT Id FROM Estimate__c WHERE Id = :created.Id];
        e.Parts_Cost__c = 1500;
        e.Labour_Hours__c = 8; e.Labour_Rate__c = 75; e.Insurance_Amount__c = 120;
        e.Shop_Supplies__c = 150; e.Shop_Supplies_Retail__c = 300; e.Retail_Price__c = 4000;
        e.Deductable__c = null;
        update e;

        ClaimPricingService.PricingResult r = ClaimPricingService.recalculateAndStamp(e.Id, null);

        System.assertEquals(2900, r.coverage, 'min(cap 3000 from package, retail 4000) - deductible 100 from package');
        System.assertEquals(1400, r.custPre);
        System.assertEquals(1582, r.custTax);
        System.assertEquals(100, [SELECT Deductable__c FROM Estimate__c WHERE Id = :e.Id].Deductable__c,
            'the resolved deductible (from the package, since the estimate had none) is written back, not left blank');
    }

    @IsTest
    static void getDefaultsIncludesClaimRefFallingBackToClaimNameAlone() {
        Estimate__c created = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        Claim__c claim = [SELECT Id, Name FROM Claim__c WHERE Id = :created.Claim__c];

        // No Vehicle__c linked in the factory's bare claim, so the formula-derived
        // Vehicle_Year__c/Make__c/Model__c are all blank - claimRef falls back to
        // just the claim's own Name, still a valid header display string.
        ClaimPricingService.PricingDefaults d = ClaimPricingService.getDefaults(claim.Id, null);

        System.assertEquals(claim.Name, d.claimRef, 'falls back to the claim name alone when no vehicle is linked');
    }

    @IsTest
    static void explicitCapOverridesApplicationPackage() {
        Estimate__c created = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        Claim__c claim = [SELECT Id, Application__c FROM Claim__c WHERE Id = :created.Claim__c];
        Application_Package__c pkg = new Application_Package__c(
            Application__c = claim.Application__c, Payment_Status__c = 'Not Paid');
        insert pkg;
        update new Application_Package__c(Id = pkg.Id, Per_Claim_Limit__c = 10000, Deductible__c = 0);
        claim.Application_Package__c = pkg.Id;
        update claim;

        Estimate__c e = [SELECT Id FROM Estimate__c WHERE Id = :created.Id];
        e.Retail_Price__c = 4000; e.Deductable__c = 100;
        update e;

        ClaimPricingService.PricingResult r = ClaimPricingService.recalculateAndStamp(e.Id, 3000);
        System.assertEquals(2900, r.coverage, 'passed cap 3000 and estimate deductible 100 win over the package 10000 / 0');
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
        System.assertEquals(2370, r.wsTotal);
    }
}