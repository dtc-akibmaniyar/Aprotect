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

    // =====================================================================
    // TASK-047 scenario model (Noelle, Repair Price Scenarios Feedback 1.0)
    // =====================================================================
    //
    // Every expected value below was derived independently of the mockup,
    // with exact decimal arithmetic rather than by reading numbers off the
    // rendered page, then cross-checked against all 15 worked examples in
    // Formulas.dc.html. The two figures Osama named as acceptance criteria
    // are asserted explicitly: Option A total incl. tax 5,308.18 and the LKQ
    // used engine total incl. tax 4,857.87.
    //
    // ONE DELIBERATE ONE-CENT DIVERGENCE FROM THE MOCKUP, see
    // optionAProfitLossInclTaxIsAHalfCentTieRoundedAwayFromZero below.

    private static final Decimal CAP = 3000;
    private static final Decimal DED = 100;
    private static final Decimal TAX = 13;
    private static final Decimal BEN = 100;   // Car Rental, included, 100 approved

    private static ClaimPricingService.ScenarioInput scenarioInput(
            Decimal partsW, Decimal partsR, Decimal warrW, Decimal warrR,
            Decimal labW, Decimal labR, Decimal supW, Decimal supR, Decimal core) {
        ClaimPricingService.ScenarioInput i = new ClaimPricingService.ScenarioInput();
        i.partsWholesale = partsW;    i.partsRetail = partsR;
        i.warrantyWholesale = warrW;  i.warrantyRetail = warrR;
        i.labourWholesale = labW;     i.labourRetail = labR;
        i.suppliesWholesale = supW;   i.suppliesRetail = supR;
        i.coreTotal = core;
        i.cap = CAP; i.deductible = DED; i.taxPercent = TAX; i.benefitsApproved = BEN;
        i.isReimbursement = false;
        return i;
    }

    /** Markup rule shared by parts, extended warranties and shop supplies (Formulas card 1). */
    @IsTest
    static void markupHandlesBothPercentAndFlatAmount() {
        System.assertEquals(2000, ClaimPricingService.applyMarkup(1700, 'Amount', 300),
            'dollar markup: 1,700 + 300');
        System.assertEquals(188.50, ClaimPricingService.applyMarkup(145, 'Percent', 30),
            'percent markup: 145 x 1.30');
        System.assertEquals(1700, ClaimPricingService.applyMarkup(1700, 'Percent', null),
            'a blank markup leaves the wholesale cost untouched');
        System.assertEquals(0, ClaimPricingService.applyMarkup(null, 'Amount', null),
            'a blank base is zero, never a null pointer');
    }

    /**
     * "LKQ used engine": the only sample carrying a core charge, which proves
     * the core stays out of every total and out of P&L while still being
     * reported. One of Osama's two named acceptance figures.
     */
    @IsTest
    static void lkqUsedEngineScenarioMatchesTheDesign() {
        ClaimPricingService.ScenarioResult r = ClaimPricingService.calculateScenario(
            scenarioInput(1500, 2800, 120, 160, 600, 1040, 150, 299, 400));

        System.assertEquals(2370.00, r.subtotalWholesale, 'parts 1500 + warranty 120 + labour 600 + supplies 150, core excluded');
        System.assertEquals(4299.00, r.subtotalRetail,    'parts 2800 + warranty 160 + labour 1040 + supplies 299');
        System.assertEquals(400.00,  r.coreTotal,         'core charge is reported');
        System.assertEquals(4857.87, r.subtotalRetail + r.taxTotal, 'NAMED CHECK: total incl. tax = 4,857.87');
        System.assertEquals(4000.00, r.retailRepair,      'supplies excluded so the cap is tested on the repair only');
        System.assertEquals(4520.00, r.repairInclTax,     '4,000 x 1.13');
        System.assertEquals(2900.00, r.coverageApplied,   'min(4520, 3000) - 100');
        System.assertEquals(1520.00, r.overLimit,         '4,520 - 3,000');
        System.assert(!r.fullyCovered,                'over the cap, so not fully covered');
        System.assertEquals(1857.87, r.customerPays,      '(4520 - 2900) + 337.87 supplies incl. tax - 100 benefit');
        System.assertEquals(1644.13, r.customerPaysPreTax, '1,857.87 / 1.13');
        System.assertEquals(213.74,  r.customerTaxAmount, 'tax sitting inside what the customer pays');
        System.assertEquals(2678.10, r.costInclTax,       '2,370 x 1.13');
        System.assertEquals(-637.37, r.profitLossRepairOnly,   'repair-only P&L, no benefit term');
        System.assertEquals(-725.87, r.profitLossInclBenefits, 'pre-tax P&L with the 100 benefit');
        System.assertEquals(-820.23, r.profitLossInclTax,      '1,857.87 - 2,678.10');
        System.assertEquals(725.87,  r.apLoss,            'loss as a positive number, the BEST ranking key');
    }

    /** "Repair Shop 1 - Option A". Osama's second named acceptance figure. */
    @IsTest
    static void optionAScenarioMatchesTheDesign() {
        ClaimPricingService.ScenarioResult r = ClaimPricingService.calculateScenario(
            scenarioInput(3000, 3500, 145, 188.50, 660, 759, 200, 250, 0));

        System.assertEquals(4005.00, r.subtotalWholesale);
        System.assertEquals(4697.50, r.subtotalRetail);
        System.assertEquals(5308.18, r.subtotalRetail + r.taxTotal, 'NAMED CHECK: total incl. tax = 5,308.18');
        System.assertEquals(2900.00, r.coverageApplied);
        System.assertEquals(2025.68, r.overLimit);
        System.assertEquals(2308.18, r.customerPays);
        System.assertEquals(-1962.37, r.profitLossInclBenefits);
        System.assertEquals(1962.37,  r.apLoss);
    }

    /**
     * "Repair Shop 3 - Option C" is the scenario Formulas.dc.html works all
     * the way through, cards 1 to 13. Asserting it line by line is the single
     * strongest check that the port is faithful.
     */
    @IsTest
    static void optionCReproducesEveryWorkedExampleInTheFormulaReference() {
        ClaimPricingService.ScenarioResult r = ClaimPricingService.calculateScenario(
            scenarioInput(1700, 2000, 0, 0, 700, 800, 160, 200, 0));

        System.assertEquals(2560.00, r.claimCost,       'card 6: 1700 + 0 + 700 + 160');
        System.assertEquals(2892.80, r.costInclTax,     'card 6: 2,560 x 1.13');
        System.assertEquals(2800.00, r.retailRepair,    'card 7: 2000 + 0 + 800, supplies excluded');
        System.assertEquals(3164.00, r.repairInclTax,   'card 7: 2,800 x 1.13');
        System.assertEquals(2900.00, r.coverageApplied, 'card 8: min(3164, 3000) - 100');
        System.assertEquals(164.00,  r.overLimit,       'card 8: 3,164 - 3,000');
        System.assertEquals(226.00,  r.suppliesInclTax, 'card 9: 200 x 1.13');
        System.assertEquals(390.00,  r.customerPays,    'card 9: 264 + 226 - 100');
        System.assertEquals(345.13,  r.customerPaysPreTax, 'card 10: 390 / 1.13');
        System.assertEquals(44.87,   r.customerTaxAmount,  'card 10: tax inside the payment');
        System.assertEquals(-2214.87, r.profitLossInclBenefits, 'card 11: 345.13 - 2,560');
        System.assertEquals(-2502.80, r.profitLossInclTax,      'card 11: 390 - 2,892.80');
    }

    /**
     * The Alternator sample is the only repair scenario inside the 3,000 cap,
     * so it is the one that exercises the Fully covered state, and card 12
     * names it as BEST at a 580.00 loss.
     */
    @IsTest
    static void alternatorIsFullyCoveredAndIsTheBestScenario() {
        ClaimPricingService.ScenarioResult r = ClaimPricingService.calculateScenario(
            scenarioInput(450, 700, 0, 0, 150, 260, 40, 60, 0));

        System.assertEquals(1084.80, r.repairInclTax);
        System.assertEquals(0.00,    r.overLimit,       'inside the cap');
        System.assert(r.fullyCovered,               'card 8: zero over limit shows the Fully covered state');
        System.assertEquals(984.80,  r.coverageApplied, 'coverage absorbs the tax: 1,084.80 - 100');
        System.assertEquals(67.80,   r.customerPays,    'deductible 100 + supplies incl. tax 67.80 - benefit 100');
        System.assertEquals(-580.00, r.profitLossInclBenefits, 'card 12: the BEST scenario loses 580.00');
        System.assertEquals(580.00,  r.apLoss);
    }

    /**
     * The Fully covered box prints deductible + supplies + supply tax - benefits.
     * That must reconcile to the cent with what the customer actually pays, or
     * the green box and the summary table would disagree on the same card.
     */
    @IsTest
    static void fullyCoveredBoxReconcilesToCustomerPays() {
        ClaimPricingService.ScenarioResult r = ClaimPricingService.calculateScenario(
            scenarioInput(450, 700, 0, 0, 150, 260, 40, 60, 0));
        System.assertEquals(r.customerPays, DED + r.suppliesRetail + r.suppliesTax - r.benefitsApproved,
            'deductible 100 + supplies 60 + supply tax 7.80 - benefit 100 = 67.80');
    }

    /** Card 15: no repair, no deductible, no shop supplies, customer pays nothing. */
    @IsTest
    static void reimbursementOnlyPaysTheCustomerAndChargesNothing() {
        ClaimPricingService.ScenarioInput i = scenarioInput(0, 0, 0, 0, 0, 0, 0, 0, 0);
        i.isReimbursement = true;
        i.reimbursementTotal = 205;   // rental 120 + roadside 85
        ClaimPricingService.ScenarioResult r = ClaimPricingService.calculateScenario(i);

        System.assertEquals(0.00,    r.customerPays,          'card 15: the customer pays nothing');
        System.assertEquals(205.00,  r.reimbursedToCustomer,  'card 15: 120 + 85 reimbursed');
        System.assertEquals(0.00,    r.coverageApplied,       'no repair, so no coverage is applied');
        System.assertEquals(-205.00, r.profitLossInclBenefits, 'card 15: P&L is the full reimbursement');
        System.assertEquals(-205.00, r.profitLossInclTax,     'nothing to recover tax on');
        System.assert(!r.fullyCovered,                    'a reimbursement is neither covered nor over limit');
    }

    /**
     * A reimbursement scenario ignores any repair figures that happen to be
     * sitting on the record, rather than quietly pricing them.
     */
    @IsTest
    static void reimbursementIgnoresAnyRepairFiguresStillOnTheRecord() {
        ClaimPricingService.ScenarioInput i = scenarioInput(1500, 2800, 120, 160, 600, 1040, 150, 299, 400);
        i.isReimbursement = true;
        i.reimbursementTotal = 205;
        ClaimPricingService.ScenarioResult r = ClaimPricingService.calculateScenario(i);

        System.assertEquals(0.00, r.claimCost,    'parts, labour and supplies are all dropped');
        System.assertEquals(0.00, r.customerPays, 'and no deductible is charged');
        System.assertEquals(205.00, r.reimbursedToCustomer);
    }

    /**
     * Edge case the mockup itself does not guard: when the deductible exceeds
     * the whole repair, coverage clamps to zero and the customer owes the
     * entire repair, not just the deductible. Asserted so a later change to
     * the Fully covered box cannot quietly understate what is owed.
     */
    @IsTest
    static void deductibleLargerThanTheRepairClampsCoverageToZero() {
        ClaimPricingService.ScenarioInput i = scenarioInput(0, 50, 0, 0, 0, 0, 0, 0, 0);
        i.deductible = 100;
        i.benefitsApproved = 0;
        ClaimPricingService.ScenarioResult r = ClaimPricingService.calculateScenario(i);

        System.assertEquals(0.00, r.coverageApplied, 'min(56.50, 3000) - 100 clamps to 0, never negative');
        System.assertEquals(56.50, r.customerPays,   'the customer owes the whole 50 repair plus its tax');
    }

    /** Benefits larger than the bill are paid back rather than going negative. */
    @IsTest
    static void benefitsBeyondTheBillAreReimbursedNotNetted() {
        ClaimPricingService.ScenarioInput i = scenarioInput(450, 700, 0, 0, 150, 260, 40, 60, 0);
        i.benefitsApproved = 500;    // far more than the 67.80 owed
        ClaimPricingService.ScenarioResult r = ClaimPricingService.calculateScenario(i);

        System.assertEquals(0.00,   r.customerPays,         'card 9: customer pays clamps at zero');
        System.assertEquals(332.20, r.reimbursedToCustomer,
            'card 9: the bill before benefits is 100 deductible + 67.80 supplies incl. tax, so 500 - 167.80 is paid back');
    }

    /**
     * Option A's tax-inclusive P&L lands on an exact half cent (-2,217.475).
     * Apex Decimal is exact and RoundingMode.HALF_UP rounds a tie away from
     * zero, giving -2,217.48. The mockup renders -2,217.47 purely because
     * JavaScript evaluates the same subtraction in binary floating point and
     * lands a hair below the tie. Apex is the correct one; this test exists so
     * the one-cent gap is a recorded decision rather than a future bug report.
     */
    @IsTest
    static void optionAProfitLossInclTaxIsAHalfCentTieRoundedAwayFromZero() {
        ClaimPricingService.ScenarioResult r = ClaimPricingService.calculateScenario(
            scenarioInput(3000, 3500, 145, 188.50, 660, 759, 200, 250, 0));
        System.assertEquals(-2217.48, r.profitLossInclTax,
            'exact value is -2,217.475; HALF_UP rounds away from zero. The mockup shows -2,217.47 (JS float).');
    }

    /** The pre-tax split must always add back up to the gross, with no lost cent. */
    @IsTest
    static void customerPreTaxAndTaxAlwaysAddBackUpToCustomerPays() {
        ClaimPricingService.ScenarioResult r = ClaimPricingService.calculateScenario(
            scenarioInput(1500, 2800, 120, 160, 600, 1040, 150, 299, 400));
        System.assertEquals(r.customerPays, r.customerPaysPreTax + r.customerTaxAmount,
            '1,644.13 + 213.74 = 1,857.87');
    }

    /** An empty scenario must be all zeroes, not a divide-by-zero or a null. */
    @IsTest
    static void emptyScenarioIsAllZeroes() {
        ClaimPricingService.ScenarioInput i = new ClaimPricingService.ScenarioInput();
        ClaimPricingService.ScenarioResult r = ClaimPricingService.calculateScenario(i);
        System.assertEquals(0.00, r.claimCost);
        System.assertEquals(0.00, r.customerPays);
        System.assertEquals(0.00, r.profitLossInclBenefits);
        System.assert(!r.fullyCovered, 'nothing priced is not "fully covered"');
    }

    @IsTest
    static void calculateScenarioLiveDelegatesToCalculateScenario() {
        ClaimPricingService.ScenarioResult r = ClaimPricingService.calculateScenarioLive(
            scenarioInput(1700, 2000, 0, 0, 700, 800, 160, 200, 0));
        System.assertEquals(390.00, r.customerPays);
    }
}