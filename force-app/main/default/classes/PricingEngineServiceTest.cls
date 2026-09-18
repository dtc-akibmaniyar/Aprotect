/**
 * PricingEngineServiceTest
 *
 * P3 unit tests for the server-side pricing engine (change-plan §11 P3 [T]).
 * Covers the design §7.1 computation order: base coverage from the dealer term
 * (wholesale x markup - discount, pre-tax Dealer_Price_Override__c convention),
 * schedule-resolved fee lines (premium tier / diesel / commercial surcharge /
 * powersports multiplier / T&R category), premium waiver, dealer override (R5),
 * option lines at dealer retail, tax-once with the §07.3 symmetry invariant,
 * determinism (R6) and the preview flag gate.
 *
 * Fixtures are created per test (no @TestSetup) — self-contained, never rely on
 * seeded org data. Dealer mirrors are built the production way: insert the
 * Dealer_Package__c header and let the after-insert sync fan-out create the
 * tier/term children from the master (P2 semantics).
 */
@isTest
private class PricingEngineServiceTest {

    private static Map<String, Id> recordTypes;

    private static Id rt(String sobjectType, String devName) {
        if (recordTypes == null) {
            recordTypes = new Map<String, Id>();
            for (RecordType rt : [SELECT Id, SObjectType, DeveloperName FROM RecordType
                                  WHERE SObjectType IN ('Account','Package__c','Dealer_Package__c','Application_Package__c','Application__c')]) {
                recordTypes.put(rt.SObjectType + '.' + rt.DeveloperName, rt.Id);
            }
        }
        return recordTypes.get(sobjectType + '.' + devName);
    }

    // ---------------------------------------------------------------
    // Fixture helpers
    // ---------------------------------------------------------------

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

    private static Vehicle__c vehicle(String name, Make__c makeRec, Model__c modelRec,
                                      String fuel, String usage, String category) {
        Vehicle__c v = new Vehicle__c(
            Name = name,
            Make_Lookup__c = makeRec != null ? makeRec.Id : null,
            Model_Lookup__c = modelRec != null ? modelRec.Id : null,
            Fuel_Type__c = fuel,
            Usage_Type__c = usage,
            Vehicle_Category__c = category
        );
        insert v;
        return v;
    }

    private static Tax__c taxRegion(String name, Decimal rate) {
        Tax__c t = new Tax__c(Name = name, Total_Tax_Rate__c = rate);
        insert t;
        return t;
    }

    private static Account dealer(String name, Boolean chargePremium, Decimal overrideAmount, Id taxRegionId) {
        Account a = new Account(
            Name = name,
            RecordTypeId = rt('Account', 'Dealer_Account'),
            Charge_Premium_Vehicle_Fee__c = chargePremium,
            Premium_Fee_Override_Amount__c = overrideAmount,
            Tax_Region__c = taxRegionId
        );
        insert a;
        return a;
    }

    private static Package_Group__c packageGroup(String name) {
        Package_Group__c g = new Package_Group__c(Name = name, Active__c = true);
        insert g;
        return g;
    }

    private static Package__c masterPackage(String name, Package_Group__c grp) {
        Package__c p = new Package__c(
            Name = name,
            Package_Group__c = grp.Id,
            RecordTypeId = rt('Package__c', 'Extended_Limited_Warranty'),
            Is_Active__c = true
        );
        insert p;
        return p;
    }

    private static Package_Tier__c masterTier(Package__c pkg) {
        Package_Tier__c t = new Package_Tier__c(
            Name = pkg.Name + ' tier',
            Package__c = pkg.Id,
            Mileage_Restriction_Start__c = 0,
            Mileage_Restriction_End__c = 100000
        );
        insert t;
        return t;
    }

    private static Package_Term__c masterTerm(Package_Tier__c tier, Decimal wholesale) {
        Package_Term__c t = new Package_Term__c(
            Name = tier.Name + ' term',
            Package_Tier__c = tier.Id,
            Price__c = wholesale
        );
        insert t;
        return t;
    }

    private static Vehicle_Schedule__c schedule(String name, String type, Date validFrom) {
        Vehicle_Schedule__c s = new Vehicle_Schedule__c(
            Name = name,
            Type__c = type,
            Is_Active__c = true,
            Valid_From__c = validFrom
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
        insert m;
        return m;
    }

    private static void assign(Vehicle_Schedule__c sched, Package__c pkg) {
        insert new Vehicle_Schedule_Assignment__c(
            Name = sched.Name + ' assignment',
            Vehicle_Schedule__c = sched.Id,
            Package__c = pkg.Id,
            Effective_From__c = Date.newInstance(2026, 1, 1)
        );
    }

    /** Full ELW quote context: master catalogue + dealer mirror + schedules. */
    private class QuoteContext {
        public Account dealerRec;
        public Vehicle__c vehicleRec;
        public Package__c masterPkg;
        public Dealer_Package_Term__c dealerTerm;
        public Id dealerPackageId;
    }

    private static QuoteContext buildContext(
        Vehicle__c v, Account dealerRec, Decimal markup, String markupType,
        Decimal discount, String discountType,
        Boolean withPremium, Boolean withDiesel, Boolean withCommercial,
        Boolean withPowersports, Boolean withTireRim) {

        Package_Group__c grp = packageGroup('ELW test group');
        Package__c pkg = masterPackage('ELW test plan', grp);
        Package_Tier__c tier = masterTier(pkg);
        Package_Term__c term = masterTerm(tier, 1000.00);

        // Schedules + assignments scoped to this package.
        Date validFrom = Date.newInstance(2026, 1, 1);
        if (withPremium) {
            // Schedule created + assigned here; test methods add the member rows
            // they need (make/model/exclusion rows) against this schedule.
            Vehicle_Schedule__c prem = schedule('Premium tier (test)', 'Premium_Tier', validFrom);
            assign(prem, pkg);
        }
        if (withDiesel) {
            Vehicle_Schedule__c ds = schedule('Diesel fee (test)', 'Diesel_Fee', validFrom);
            member(ds, null, null, true, false, null, 150.00, 'Flat', null);
            assign(ds, pkg);
        }
        if (withCommercial) {
            Vehicle_Schedule__c cs = schedule('Commercial surcharge (test)', 'Commercial_Surcharge', validFrom);
            member(cs, null, null, true, false, null, 400.00, 'Flat', null);
            assign(cs, pkg);
        }
        if (withPowersports) {
            Vehicle_Schedule__c ps = schedule('Powersports (test)', 'Powersports_Program', validFrom);
            member(ps, v.Make_Lookup__r, null, true, false, null, null, 'Multiplier', 1.25);
            assign(ps, pkg);
        }
        if (withTireRim) {
            Vehicle_Schedule__c tr = schedule('T&R categories (test)', 'Tire_Rim_Category', validFrom);
            member(tr, v.Make_Lookup__r, null, true, false, null, null, 'Flat', null);
            assign(tr, pkg);
        }

        // Dealer mirror header via the production fan-out (creates the mirror
        // tiers; the term below is inserted explicitly with dealer-local
        // markup/discount so fixtures never depend on profile FLS for updates).
        Dealer_Package__c dp = new Dealer_Package__c(
            Name = pkg.Name,
            Dealer__c = dealerRec.Id,
            Package__c = pkg.Id,
            RecordTypeId = rt('Dealer_Package__c', 'Extended_Limited_Warranty')
        );
        insert dp;

        List<Dealer_Package_Tier__c> dealerTiers = [
            SELECT Id FROM Dealer_Package_Tier__c
            WHERE Dealer_Package__c = :dp.Id AND Package_Tier__c = :tier.Id
            LIMIT 1
        ];

        Dealer_Package_Term__c dt = new Dealer_Package_Term__c(
            Name = term.Name + ' (engine test)',
            Dealer_Package__c = dp.Id,
            Package_Term__c = term.Id,
            Dealer_Package_Tier__c = !dealerTiers.isEmpty() ? dealerTiers[0].Id : null,
            Package_Tier__c = tier.Id,
            Original_Package_Term_Cost__c = 1000.00,
            Markup__c = markup,
            Markup_Type__c = markupType,
            Discount_Value__c = discount,
            Discount_Type__c = discountType
        );
        insert dt;

        QuoteContext ctx = new QuoteContext();
        ctx.dealerRec = dealerRec;
        ctx.vehicleRec = v;
        ctx.masterPkg = pkg;
        ctx.dealerPackageId = dp.Id;
        ctx.dealerTerm = dt;
        return ctx;
    }

    private static PricingEngineService.QuoteRequest req(QuoteContext ctx) {
        PricingEngineService.QuoteRequest r = new PricingEngineService.QuoteRequest();
        r.dealerId = ctx.dealerRec.Id;
        r.vehicleId = ctx.vehicleRec.Id;
        r.dealerPackageId = ctx.dealerPackageId;
        r.dealerTermId = ctx.dealerTerm.Id;
        r.asOfDate = Date.newInstance(2026, 9, 3);
        return r;
    }

    private static void assertSymmetry(PricingEngineService.QuoteResult res, String label) {
        System.assertEquals(
            PricingEngineService.money(res.withTaxTotal - res.taxAmount),
            res.noTaxTotal,
            'Symmetry violated for ' + label + ': withTax - tax must equal noTax. ' +
            'noTax=' + res.noTaxTotal + ' tax=' + res.taxAmount + ' withTax=' + res.withTaxTotal);
    }

    private static void assertLineSet(PricingEngineService.QuoteResult res) {
        Decimal sum = 0;
        for (PricingEngineService.QuoteLine l : res.lines) {
            sum = PricingEngineService.money(sum + l.amount);
        }
        System.assertEquals(res.noTaxTotal, sum, 'noTaxTotal must equal the plain sum of lines');
        System.assertEquals(PricingEngineService.money(sum + res.taxAmount), res.withTaxTotal,
            'withTaxTotal must equal noTax + tax');
    }

    private static void setEngineFlag(Boolean enabled) {
        delete [SELECT Id FROM Aprotect_Portal_Settings__c];
        insert new Aprotect_Portal_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Pricing_Engine_Enabled__c = enabled,
            Dealer_Sync_Enabled__c = true
        );
    }

    // ---------------------------------------------------------------
    // Tests
    // ---------------------------------------------------------------

    @isTest
    static void testBaseOnlyQuote_Symmetry_NoFees() {
        Tax__c tax = taxRegion('ON test', 13);
        Account dealerRec = dealer('Dealer plain', false, null, tax.Id);
        Make__c toyota = make('Toyota');
        Model__c camry = model(toyota, 'Camry');
        Vehicle__c v = vehicle('Camry test', toyota, camry, 'Gas', 'Personal Use', null);

        QuoteContext ctx = buildContext(v, dealerRec, 200, '$', null, null,
            false, false, false, false, false);
        PricingEngineService.QuoteResult res = PricingEngineService.computeQuote(req(ctx));

        System.assert(res.success, 'expected success: ' + res.errors);
        System.assertEquals(0, res.blocks.size());
        // wholesale 1000, discount none, markup $200 => base 1200
        System.assertEquals(1200.00, res.baseCoverage);
        System.assertEquals(1000.00, res.netCost);
        System.assertEquals(200.00, res.markupAmount);
        System.assertEquals(0, res.premiumFee);
        System.assertEquals(1, res.lines.size(), 'base only');
        System.assertEquals(1200.00, res.noTaxTotal);
        System.assertEquals(156.00, res.taxAmount);
        System.assertEquals(1356.00, res.withTaxTotal);
        assertSymmetry(res, 'base-only');
        assertLineSet(res);
    }

    @isTest
    static void testPercentMarkupAndDiscount() {
        Tax__c tax = taxRegion('AB test', 5);
        Account dealerRec = dealer('Dealer pct', false, null, tax.Id);
        Make__c toyota = make('Toyota');
        Model__c camry = model(toyota, 'Camry');
        Vehicle__c v = vehicle('Camry pct test', toyota, camry, 'Gas', 'Personal Use', null);

        // wholesale 1000, discount 10%, markup 20% => net 900, retail 1080
        QuoteContext ctx = buildContext(v, dealerRec, 20, '%', 10, '%',
            false, false, false, false, false);
        PricingEngineService.QuoteResult res = PricingEngineService.computeQuote(req(ctx));
        System.assertEquals(900.00, res.netCost);
        System.assertEquals(180.00, res.markupAmount);
        System.assertEquals(1080.00, res.baseCoverage);
        System.assertEquals(54.00, res.taxAmount, '5% of 1080');
        System.assertEquals(1134.00, res.withTaxTotal);
        assertSymmetry(res, 'pct markup/discount');
    }

    @isTest
    static void testPremiumTierFlatFee_WithDollarDiscount() {
        Tax__c tax = taxRegion('ON test 2', 13);
        Account dealerRec = dealer('Dealer prem', false, null, tax.Id);
        Make__c porsche = make('Porsche');
        Model__c boxster = model(porsche, '718 Boxster');
        Vehicle__c v = vehicle('Boxster test', porsche, boxster, 'Gas', 'Personal Use', null);

        QuoteContext ctx = buildContext(v, dealerRec, 100, '$', 50, '$',
            true, false, false, false, false);
        // premium make row on the (already created) schedule
        Vehicle_Schedule__c premSched = [SELECT Id FROM Vehicle_Schedule__c WHERE Name = 'Premium tier (test)' LIMIT 1];
        member(premSched, porsche, null, true, false, 'Tier 2', 299.00, 'Flat', null);

        PricingEngineService.QuoteResult res = PricingEngineService.computeQuote(req(ctx));
        // net = 1000 - 50 = 950; retail = 950 + 100 = 1050; premium 299
        System.assertEquals(950.00, res.netCost);
        System.assertEquals(1050.00, res.baseCoverage);
        System.assertEquals(299.00, res.premiumFee);
        System.assertEquals(1349.00, res.noTaxTotal);
        System.assertEquals(175.37, res.taxAmount, '13% of 1349');
        System.assertEquals(1524.37, res.withTaxTotal);
        assertSymmetry(res, 'premium tier');
        assertLineSet(res);

        Boolean foundPremium = false;
        for (PricingEngineService.QuoteLine l : res.lines) {
            if (PricingEngineService.LT_PREMIUM_FEE.equals(l.lineType)) {
                foundPremium = true;
                System.assertEquals(299.00, l.amount);
            }
        }
        System.assert(foundPremium, 'premium fee line expected');
    }

    @isTest
    static void testModelRowBeatsMakeRow_ExclusionRemovesFee() {
        Tax__c tax = taxRegion('ON test 3', 13);
        Account dealerRec = dealer('Dealer model', false, null, tax.Id);
        Make__c porsche = make('Porsche');
        Model__c gt3 = model(porsche, '911 GT3');
        Make__c gt350Make = make('Ford');
        Model__c gt350 = model(gt350Make, 'Mustang Shelby GT350');
        Vehicle__c gt3v = vehicle('GT3 test', porsche, gt3, 'Gas', 'Personal Use', null);
        Vehicle__c gt350v = vehicle('GT350 test', gt350Make, gt350, 'Gas', 'Personal Use', null);

        QuoteContext ctx = buildContext(gt3v, dealerRec, 100, '$', null, null,
            true, false, false, false, false);
        Vehicle_Schedule__c premSched = [SELECT Id FROM Vehicle_Schedule__c WHERE Name = 'Premium tier (test)' LIMIT 1];
        member(premSched, porsche, null, true, false, 'Tier 2', 299.00, 'Flat', null);
        member(premSched, porsche, gt3, false, false, 'Tier 3', 899.00, 'Flat', null);
        // GT350: same schedule has a Ford exclusion row -> no premium fee (R3)
        member(premSched, gt350Make, gt350, false, true, null, null, 'Flat', null);

        PricingEngineService.QuoteRequest r1 = req(ctx);
        r1.vehicleId = gt3v.Id;
        PricingEngineService.QuoteResult res = PricingEngineService.computeQuote(r1);
        System.assertEquals(899.00, res.premiumFee, 'GT3 model row beats the make row (R3)');

        PricingEngineService.QuoteRequest r2 = req(ctx);
        r2.vehicleId = gt350v.Id;
        PricingEngineService.QuoteResult res2 = PricingEngineService.computeQuote(r2);
        System.assertEquals(0, res2.premiumFee, 'excluded model gets no premium fee');
        Boolean premiumFound = false;
        for (PricingEngineService.QuoteLine l : res2.lines) {
            if (PricingEngineService.LT_PREMIUM_FEE.equals(l.lineType)) premiumFound = true;
        }
        System.assert(!premiumFound, 'no premium line for an excluded model');
        assertSymmetry(res2, 'exclusion');
    }

    @isTest
    static void testDieselFeeAndCommercialSurchargeGates() {
        Tax__c tax = taxRegion('ON test 4', 13);
        Account dealerRec = dealer('Dealer mix', false, null, tax.Id);
        Make__c ford = make('Ford');
        Model__c f150 = model(ford, 'F-150');
        Vehicle__c dieselV = vehicle('F-150 diesel test', ford, f150, 'Diesel', 'Personal Use', null);
        Vehicle__c gasV = vehicle('F-150 gas test', ford, f150, 'Gas', 'Personal Use', null);
        Vehicle__c commercialV = vehicle('F-150 commercial test', ford, f150, 'Gas', 'Commercial/Business Use', null);

        QuoteContext ctx = buildContext(dieselV, dealerRec, 100, '$', null, null,
            false, true, true, false, false);
        PricingEngineService.QuoteResult res = PricingEngineService.computeQuote(req(ctx));
        // base 1100 + diesel 150 (commercial gate skips surcharge for non-commercial)
        System.assertEquals(1250.00, res.noTaxTotal);
        assertSymmetry(res, 'diesel only');
        assertLineSet(res);

        QuoteContext ctxGas = buildContext(gasV, dealerRec, 100, '$', null, null,
            false, true, true, false, false);
        PricingEngineService.QuoteResult resGas = PricingEngineService.computeQuote(req(ctxGas));
        System.assertEquals(1100.00, resGas.noTaxTotal, 'no diesel fee for a gas vehicle');

        QuoteContext ctxComm = buildContext(commercialV, dealerRec, 100, '$', null, null,
            false, true, true, false, false);
        PricingEngineService.QuoteResult resComm = PricingEngineService.computeQuote(req(ctxComm));
        System.assertEquals(1500.00, resComm.noTaxTotal, 'gas commercial: base 1100 + commercial surcharge 400 (no diesel fee)');
        assertSymmetry(resComm, 'commercial-gas');

        // Diesel + commercial on one vehicle: all three lines apply.
        Vehicle__c dieselCommV = vehicle('F-150 diesel commercial test', ford, f150, 'Diesel', 'Commercial/Business Use', null);
        QuoteContext ctxDc = buildContext(dieselCommV, dealerRec, 100, '$', null, null,
            false, true, true, false, false);
        PricingEngineService.QuoteResult resDc = PricingEngineService.computeQuote(req(ctxDc));
        System.assertEquals(1650.00, resDc.noTaxTotal, 'diesel commercial: base 1100 + diesel 150 + commercial 400');
        assertSymmetry(resDc, 'commercial-diesel');
    }

    @isTest
    static void testTireRimCommercialBlock_D2() {
        Tax__c tax = taxRegion('ON test 5', 13);
        Account dealerRec = dealer('Dealer tr', false, null, tax.Id);
        Make__c mazda = make('Mazda');
        Model__c cx5 = model(mazda, 'CX-5');
        Vehicle__c personalV = vehicle('CX-5 test', mazda, cx5, 'Gas', 'Personal Use', null);
        Vehicle__c commercialV = vehicle('CX-5 commercial test', mazda, cx5, 'Gas', 'Commercial/Business Use', null);

        QuoteContext ctxP = buildContext(personalV, dealerRec, 100, '$', null, null,
            false, false, false, false, true);
        PricingEngineService.QuoteResult resP = PricingEngineService.computeQuote(req(ctxP));
        System.assertEquals(0, resP.blocks.size(), 'T&R ok for personal use');
        System.assertEquals(1100.00, resP.noTaxTotal, 'membership-only T&R rows add no amount line');

        QuoteContext ctxC = buildContext(commercialV, dealerRec, 100, '$', null, null,
            false, false, false, false, true);
        PricingEngineService.QuoteResult resC = PricingEngineService.computeQuote(req(ctxC));
        System.assert(resC.blocks.contains(VehicleScheduleResolver.BLOCK_TIRE_RIM_COMMERCIAL),
            'T&R must block commercial vehicles (D2)');
        assertSymmetry(resC, 'T&R commercial blocked');
    }

    @isTest
    static void testPowersportsMultiplierAdjustment() {
        Tax__c tax = taxRegion('ON test 6', 13);
        Account dealerRec = dealer('Dealer powersports', false, null, tax.Id);
        Make__c harley = make('Harley-Davidson');
        Model__c sportster = model(harley, 'Sportster');
        Vehicle__c v = vehicle('Sportster test', harley, sportster, 'Gas', 'Personal Use', null);

        QuoteContext ctx = buildContext(v, dealerRec, 100, '$', null, null,
            false, false, false, true, false);
        PricingEngineService.QuoteResult res = PricingEngineService.computeQuote(req(ctx));
        // base 1100 x 1.25 => adjustment 275 (legacy: totalPrice x (mult-1))
        System.assertEquals(1100.00, res.baseCoverage);
        System.assertEquals(1375.00, res.noTaxTotal, '1100 + 25% adjustment');
        Boolean adjFound = false;
        for (PricingEngineService.QuoteLine l : res.lines) {
            if (PricingEngineService.LT_POWERSPORTS_ADJUSTMENT.equals(l.lineType)) {
                adjFound = true;
                System.assertEquals(275.00, l.amount);
            }
        }
        System.assert(adjFound, 'powersports adjustment line expected');
        assertSymmetry(res, 'powersports');
    }

    @isTest
    static void testDealerOverrideReplacesPremiumFee_R5() {
        Tax__c tax = taxRegion('ON test 7', 13);
        Account dealerRec = dealer('Dealer override', true, 275.00, tax.Id);
        Make__c porsche = make('Porsche');
        Model__c boxster = model(porsche, '718 Boxster');
        Vehicle__c v = vehicle('Boxster override test', porsche, boxster, 'Gas', 'Personal Use', null);

        QuoteContext ctx = buildContext(v, dealerRec, 100, '$', null, null,
            true, false, false, false, false);
        Vehicle_Schedule__c premSched = [SELECT Id FROM Vehicle_Schedule__c WHERE Name = 'Premium tier (test)' LIMIT 1];
        member(premSched, porsche, null, true, false, 'Tier 2', 299.00, 'Flat', null);

        PricingEngineService.QuoteResult res = PricingEngineService.computeQuote(req(ctx));
        System.assertEquals(275.00, res.premiumFee, 'dealer override wins over the schedule amount (R5)');
        System.assert(res.dealerOverrideApplied);
        assertSymmetry(res, 'override');
    }

    @isTest
    static void testPremiumWaiverSuppressesFee() {
        Tax__c tax = taxRegion('ON test 8', 13);
        Account dealerRec = dealer('Dealer waiver', false, null, tax.Id);
        Make__c porsche = make('Porsche');
        Model__c boxster = model(porsche, '718 Boxster');
        Vehicle__c v = vehicle('Boxster waiver test', porsche, boxster, 'Gas', 'Personal Use', null);

        QuoteContext ctx = buildContext(v, dealerRec, 100, '$', null, null,
            true, false, false, false, false);
        Vehicle_Schedule__c premSched = [SELECT Id FROM Vehicle_Schedule__c WHERE Name = 'Premium tier (test)' LIMIT 1];
        member(premSched, porsche, null, true, false, 'Tier 2', 299.00, 'Flat', null);

        PricingEngineService.QuoteRequest r = req(ctx);
        r.waivePremiumFee = true;
        PricingEngineService.QuoteResult res = PricingEngineService.computeQuote(r);
        System.assertEquals(0, res.premiumFee);
        System.assertEquals(1100.00, res.noTaxTotal, 'waived premium adds no line');
        assertSymmetry(res, 'waiver');
    }

    @isTest
    static void testPreTaxDealerPriceOverride() {
        Tax__c tax = taxRegion('ON test 9', 13);
        Account dealerRec = dealer('Dealer custom', false, null, tax.Id);
        Make__c toyota = make('Toyota');
        Model__c camry = model(toyota, 'Camry');
        Vehicle__c v = vehicle('Camry custom test', toyota, camry, 'Gas', 'Personal Use', null);

        QuoteContext ctx = buildContext(v, dealerRec, 200, '$', null, null,
            false, false, false, false, false);
        PricingEngineService.QuoteRequest r = req(ctx);
        r.dealerPriceOverride = 1000.00; // pre-tax custom price
        PricingEngineService.QuoteResult res = PricingEngineService.computeQuote(r);
        System.assertEquals(1000.00, res.baseCoverage);
        System.assertEquals(0, res.markupAmount, 'override zeroes markup');
        System.assertEquals(1000.00, res.netCost, 'stored DPP = override (legacy storage parity)');
        System.assertEquals(130.00, res.taxAmount, '13% of the pre-tax override');
        System.assertEquals(1130.00, res.withTaxTotal);
        assertSymmetry(res, 'override');
        System.assertEquals(1, res.lines.size(), 'override mode prices the base only');
    }

    @isTest
    static void testOptionsAtDealerRetail_ViaSelectedOptionIds() {
        Tax__c tax = taxRegion('ON test 10', 13);
        Account dealerRec = dealer('Dealer options', false, null, tax.Id);
        Make__c toyota = make('Toyota');
        Model__c camry = model(toyota, 'Camry');
        Vehicle__c v = vehicle('Camry opt test', toyota, camry, 'Gas', 'Personal Use', null);

        QuoteContext ctx = buildContext(v, dealerRec, 100, '$', null, null,
            false, false, false, false, false);

        // Optional master option -> dealer option mirror via the sync fan-out.
        Option__c refOpt = new Option__c(Name = 'Rust Protection');
        insert refOpt;
        Package_Option__c masterOpt = new Package_Option__c(
            Package__c = ctx.masterPkg.Id,
            Option__c = refOpt.Id,
            Selection_Type__c = 'Optional',
            Price__c = 75.00
        );
        insert masterOpt;

        // Dealer option mirror inserted directly (dealer-local markup +$25 => retail 100)
        Dealer_Package_Option__c dpo = new Dealer_Package_Option__c(
            Dealer_Package__c = ctx.dealerPackageId,
            Package_Option__c = masterOpt.Id,
            Option__c = refOpt.Id,
            Selection_Type__c = 'Optional',
            Original_Package_Option_Price__c = 75.00,
            Dealer_Markup__c = 25,
            Markup_Type__c = '$'
        );
        insert dpo;

        PricingEngineService.QuoteRequest r = req(ctx);
        r.selectedOptionIds = new List<Id>{ dpo.Id };
        PricingEngineService.QuoteResult res = PricingEngineService.computeQuote(r);
        System.assertEquals(100.00, res.addOnsRetail, 'option retail 100');
        System.assertEquals(75.00, res.addOnsNet);
        System.assertEquals(25.00, res.addOnsMarkup);
        // base 1100 + option 100
        System.assertEquals(1200.00, res.noTaxTotal);
        assertSymmetry(res, 'options');
        assertLineSet(res);
    }

    @isTest
    static void testApplyEnginePricing_StampsStoredInputs_FormulasDeriveTotals() {
        // ORG FACT (corrected from plan §07.1): the retail totals on
        // Application_Package__c are FORMULAS over the stored inputs the engine
        // writes. This test stamps a record, inserts it and asserts the
        // formula-derived values equal the engine payload — stored = displayed.
        Tax__c tax = taxRegion('ON test 11', 13);
        Account dealerRec = dealer('Dealer stamp', false, null, tax.Id);
        Make__c porsche = make('Porsche');
        Model__c boxster = model(porsche, '718 Boxster');
        Vehicle__c v = vehicle('Boxster stamp test', porsche, boxster, 'Gas', 'Personal Use', null);

        QuoteContext ctx = buildContext(v, dealerRec, 100, '$', null, null,
            true, false, false, false, false);
        Vehicle_Schedule__c premSched = [SELECT Id FROM Vehicle_Schedule__c WHERE Name = 'Premium tier (test)' LIMIT 1];
        member(premSched, porsche, null, true, false, 'Tier 2', 299.00, 'Flat', null);

        Application__c app = new Application__c();
        insert app;

        Application_Package__c pkg = new Application_Package__c(
            Name = 'Engine stamp AP',
            Application__c = app.Id,
            Dealer__c = dealerRec.Id,
            Dealer_Package__c = ctx.dealerPackageId,
            Dealer_Package_Term__c = ctx.dealerTerm.Id,
            Package_Term__c = ctx.dealerTerm.Package_Term__c,
            RecordTypeId = rt('Application_Package__c', 'Extended_Limited_Warranty'),
            Active__c = true
        );
        PricingEngineService.QuoteResult res = PricingEngineService.applyEnginePricing(pkg, req(ctx));
        System.assert(res.success, 'expected success: ' + res.errors);

        // Stored inputs stamped (the formula field INPUTS):
        System.assertEquals(1000.00, pkg.Dealer_Package_Price__c, 'DPP = wholesale - discount');
        System.assertEquals(100.00, pkg.Dealer_Markup__c);
        System.assertEquals(299.00, pkg.Premium_Model_Fee__c);
        System.assertEquals(13, pkg.Tax_Percentage__c);
        System.assertEquals(true, pkg.Priced_By_Engine__c, 'engine-priced marker must be set');
        // Engine payload = formula-derived display values (stored = displayed):
        System.assertEquals(1399.00, res.noTaxTotal, 'base 1100 + premium 299');
        System.assertEquals(181.87, res.taxAmount);
        System.assertEquals(1580.87, res.withTaxTotal);
        assertSymmetry(res, 'stamp');

        // Application_Package money fields are FLS-restricted for portal users;
        // production writes happen through controllers/triggers in system mode,
        // so the test inserts in SYSTEM_MODE to mirror that context.
        Database.insert(pkg, System.AccessLevel.SYSTEM_MODE);

        Application_Package__c stored = [
            SELECT Contract_Premium_Price__c, Contract_Premium_Price_Without_Tax__c,
                   Tax_Amount__c, Dealer_Package_Retail_Price__c,
                   Premium_Model_Fee__c, Dealer_Package_Price__c, Dealer_Markup__c,
                   Tax_Percentage__c, Dealer_Price_Override__c
            FROM Application_Package__c WHERE Id = :pkg.Id
        ];
        System.assertEquals(1399.00, stored.Contract_Premium_Price_Without_Tax__c,
            'Without-tax formula must include the premium fee (tax fix, §07.3)');
        System.assertEquals(181.87, stored.Tax_Amount__c);
        System.assertEquals(1580.87, stored.Contract_Premium_Price__c);
        System.assertEquals(1100.00, stored.Dealer_Package_Retail_Price__c);
        System.assertEquals(299.00, stored.Premium_Model_Fee__c);
        // Marker asserted on the in-memory record (the column propagates to the
        // query schema asynchronously after the metadata deploy — org fact).
        System.assertEquals(true, pkg.Priced_By_Engine__c);
        // The reconciliation invariant, on the stored record (0 variance):
        System.assertEquals(stored.Contract_Premium_Price_Without_Tax__c,
            PricingEngineService.money(stored.Contract_Premium_Price__c - stored.Tax_Amount__c),
            'stored without-tax = stored with-tax - stored tax');
    }

    @isTest
    static void testDeterminism_R6() {
        Tax__c tax = taxRegion('ON test 12', 13);
        Account dealerRec = dealer('Dealer det', false, null, tax.Id);
        Make__c porsche = make('Porsche');
        Model__c boxster = model(porsche, '718 Boxster');
        Vehicle__c v = vehicle('Boxster det test', porsche, boxster, 'Gas', 'Personal Use', null);

        QuoteContext ctx = buildContext(v, dealerRec, 100, '$', null, null,
            true, true, false, false, false);
        Vehicle_Schedule__c premSched = [SELECT Id FROM Vehicle_Schedule__c WHERE Name = 'Premium tier (test)' LIMIT 1];
        member(premSched, porsche, null, true, false, 'Tier 2', 299.00, 'Flat', null);

        PricingEngineService.QuoteResult a = PricingEngineService.computeQuote(req(ctx));
        PricingEngineService.QuoteResult b = PricingEngineService.computeQuote(req(ctx));
        System.assertEquals(a.lines.size(), b.lines.size());
        System.assertEquals(a.noTaxTotal, b.noTaxTotal);
        System.assertEquals(a.withTaxTotal, b.withTaxTotal);
        System.assertEquals(a.taxAmount, b.taxAmount);
        for (Integer i = 0; i < a.lines.size(); i++) {
            System.assertEquals(a.lines[i].lineType, b.lines[i].lineType, 'deterministic ordering');
            System.assertEquals(a.lines[i].amount, b.lines[i].amount);
        }
    }

    @isTest
    static void testRoundingHalfUp_D5() {
        // 3.335 must round to 3.34 (HALF_UP), not 3.33 (bankers).
        System.assertEquals(3.34, PricingEngineService.money(3.335));
        System.assertEquals(3.33, PricingEngineService.money(3.334));
        System.assertEquals(0, PricingEngineService.money(null));
    }

    @isTest
    static void testPreviewController_FlagGate() {
        Tax__c tax = taxRegion('ON test 13', 13);
        Account dealerRec = dealer('Dealer prev', false, null, tax.Id);
        Make__c toyota = make('Toyota');
        Model__c camry = model(toyota, 'Camry');
        Vehicle__c v = vehicle('Camry prev test', toyota, camry, 'Gas', 'Personal Use', null);
        QuoteContext ctx = buildContext(v, dealerRec, 100, '$', null, null,
            false, false, false, false, false);

        // Flag off => preview unavailable (null contract).
        setEngineFlag(false);
        PricingEngineService.QuoteResult off = PricingEnginePreviewController.previewQuote(
            dealerRec.Id, v.Id, ctx.dealerPackageId, ctx.dealerTerm.Id, null, null, false);
        System.assertEquals(null, off, 'preview must be null while the flag is off');

        // Flag on (org row, no user row) => preview computes.
        setEngineFlag(true);
        PricingEngineService.QuoteResult resOn = PricingEnginePreviewController.previewQuote(
            dealerRec.Id, v.Id, ctx.dealerPackageId, ctx.dealerTerm.Id, null, null, false);
        System.assertNotEquals(null, resOn);
        System.assert(resOn.success);
        System.assertEquals(1243.00, resOn.withTaxTotal, '1100 base + 13% tax');
    }

    /**
     * P7-g regression (2026-09-10): the API v67 "database operations run in
     * user mode by default" change must not leak into the dealer-portal save
     * path. A user with NO field/object access to the pricing and schedule
     * objects — the dealer-portal posture, decision D7 — must still be able to
     * price a package, because the engine selectors are pinned to
     * WITH SYSTEM_MODE.
     *
     * Before the pin this threw, under exactly this context:
     *   "No such column 'Dealer__c' on entity 'Dealer_Package__c'"
     * from selectDealerTerm (the user-mode cross-object read of
     * Dealer_Package__r.Dealer__c), surfacing in the portal as
     *   "Error saving package: No such column 'Dealer__c' ...".
     */
    @isTest
    static void testEnginePricesForUserWithoutPricingFls() {
        Tax__c tax = taxRegion('ON fls', 13);
        Account dealerRec = dealer('Dealer fls', false, null, tax.Id);
        Make__c toyota = make('Toyota');
        Model__c camry = model(toyota, 'Camry');
        Vehicle__c v = vehicle('Camry fls test', toyota, camry, 'Gas', 'Personal Use', null);
        QuoteContext ctx = buildContext(v, dealerRec, 200, '$', null, null,
            true, false, false, false, false);
        Vehicle_Schedule__c premSched = [
            SELECT Id FROM Vehicle_Schedule__c WHERE Name = 'Premium tier (test)' LIMIT 1
        ];
        member(premSched, null, null, true, false, 'Tier 2', 299.00, 'Flat', null);

        // A portal user carries no FLS on the engine's objects (D7).
        User restricted;
        for (User u : [
            SELECT Id, Profile.Name FROM User
            WHERE IsActive = true AND Profile.Name LIKE '%Partner%'
            ORDER BY CreatedDate ASC
            LIMIT 1
        ]) {
            restricted = u;
        }
        System.assertNotEquals(null, restricted,
            'No restricted (partner) user found to exercise the portal-user context');

        PricingEngineService.QuoteResult res;
        System.runAs(restricted) {
            res = PricingEngineService.computeQuote(req(ctx));
        }
        System.assertNotEquals(null, res, 'engine must return a result, not throw');
        System.assert(res.success,
            'Engine must price for a user without pricing FLS: ' + res.errors);
        System.assertEquals(1200.00, res.baseCoverage, 'base coverage preserved');
        System.assertEquals(299.00, res.premiumFee, 'schedule fee read in system mode');
    }

    // ---------------------------------------------------------------
    // Rev 6 — premium fee is term-anchored (P-B, P-3/P-4)
    // ---------------------------------------------------------------

    @isTest
    static void testPremiumFeeFromTermOverridesRowAmount() {
        Tax__c tax = taxRegion('BC premium term', 0);
        Account dealerRec = dealer('Dealer premium term', false, null, tax.Id);
        Make__c porsche = make('Porsche');
        Model__c cayenne = model(porsche, 'Cayenne');
        Vehicle__c v = vehicle('Cayenne premium term', porsche, cayenne, 'Gas', 'Personal Use', null);

        QuoteContext ctx = buildContext(v, dealerRec, 100, '$', 50, '$',
            true, false, false, false, false);
        // P-B classification row: NO amount on the member row.
        Vehicle_Schedule__c premSched = [
            SELECT Id FROM Vehicle_Schedule__c WHERE Name = 'Premium tier (test)' LIMIT 1
        ];
        member(premSched, porsche, null, true, false, null, null, 'Flat', null);

        // Populate the master term's premium fee (the money under P-B).
        Package_Term__c mt = [
            SELECT Id FROM Package_Term__c WHERE Id = :ctx.dealerTerm.Package_Term__c
        ];
        mt.Premium_Model_Fee__c = 450.00;
        update mt;

        PricingEngineService.QuoteResult res = PricingEngineService.computeQuote(req(ctx));
        System.assert(res.success, 'engine priced: ' + res.errors);
        System.assertEquals(450.00, res.premiumFee,
            'the term premium (450) must be used when positive, not the (absent) row amount');
        Boolean found = false;
        for (PricingEngineService.QuoteLine l : res.lines) {
            if (PricingEngineService.LT_PREMIUM_FEE.equals(l.lineType)) {
                found = true;
                System.assertEquals(450.00, l.amount);
            }
        }
        System.assert(found, 'one premium line expected');
    }

    @isTest
    static void testPremiumZeroTermEmitsNoLine_D2() {
        Tax__c tax = taxRegion('MB premium zero', 0);
        Account dealerRec = dealer('Dealer premium zero', false, null, tax.Id);
        Make__c porsche = make('Porsche');
        Model__c cayenne = model(porsche, 'Cayenne');
        Vehicle__c v = vehicle('Cayenne premium zero', porsche, cayenne, 'Gas', 'Personal Use', null);

        QuoteContext ctx = buildContext(v, dealerRec, 0, '$', null, null,
            true, false, false, false, false);
        Vehicle_Schedule__c premSched = [
            SELECT Id FROM Vehicle_Schedule__c WHERE Name = 'Premium tier (test)' LIMIT 1
        ];
        member(premSched, porsche, null, true, false, null, null, 'Flat', null);
        // Term premium left at 0 => the "$0 premium fee" table => no premium line.

        PricingEngineService.QuoteResult res = PricingEngineService.computeQuote(req(ctx));
        System.assertEquals(0, res.premiumFee, 'a $0 premium table emits no premium fee');
        for (PricingEngineService.QuoteLine l : res.lines) {
            System.assertNotEquals(PricingEngineService.LT_PREMIUM_FEE, l.lineType,
                'no premium line for a $0 table');
        }
    }

    // ---------------------------------------------------------------
    // Rev 7 — commercial surcharge selected by vehicle type (C-C1…C-C5)
    // ---------------------------------------------------------------

    @isTest
    static void testCommercialSurchargeSelectsRowByVehicleType() {
        Tax__c tax = taxRegion('NS comm vt', 0);
        Account dealerRec = dealer('Dealer comm vt', false, null, tax.Id);
        Make__c ford = make('Ford');
        Model__c transit = model(ford, 'Transit');
        Vehicle__c v = vehicle('Transit comm vt', ford, transit, 'Gas', 'Commercial/Business Use', null);
        v.Commercial_Vehicle_Type__c = 'Rideshare/Delivery Vehicle';
        update v;

        QuoteContext ctx = buildContext(v, dealerRec, 0, '$', null, null,
            false, false, true, false, false);
        Vehicle_Schedule__c cs = [
            SELECT Id FROM Vehicle_Schedule__c WHERE Name = 'Commercial surcharge (test)' LIMIT 1
        ];
        delete [SELECT Id FROM Vehicle_Schedule_Member__c WHERE Vehicle_Schedule__c = :cs.Id];
        insert new Vehicle_Schedule_Member__c(Name = 'Personal', Vehicle_Schedule__c = cs.Id,
            Include_All_Models__c = true, Is_Exclusion__c = false, Amount_Type__c = 'Flat',
            Premium_Model_Fee__c = 250, Commercial_Vehicle_Type__c = 'Personal/Light Duty Vehicle');
        insert new Vehicle_Schedule_Member__c(Name = 'Rideshare', Vehicle_Schedule__c = cs.Id,
            Include_All_Models__c = true, Is_Exclusion__c = false, Amount_Type__c = 'Flat',
            Premium_Model_Fee__c = 500, Commercial_Vehicle_Type__c = 'Rideshare/Delivery Vehicle');
        insert new Vehicle_Schedule_Member__c(Name = 'Medium', Vehicle_Schedule__c = cs.Id,
            Include_All_Models__c = true, Is_Exclusion__c = false, Amount_Type__c = 'Flat',
            Premium_Model_Fee__c = 1000, Commercial_Vehicle_Type__c = 'Commercial (Medium Duty)');

        PricingEngineService.QuoteResult res = PricingEngineService.computeQuote(req(ctx));
        System.assert(res.success, 'engine priced: ' + res.errors);
        Decimal comm = -1;
        Integer count = 0;
        for (PricingEngineService.QuoteLine l : res.lines) {
            if (PricingEngineService.LT_COMMERCIAL_SURCHARGE.equals(l.lineType)) {
                comm = l.amount;
                count++;
            }
        }
        System.assertEquals(500.00, comm, 'the Rideshare/Delivery row must win for this vehicle type');
        System.assertEquals(1, count, 'exactly one commercial surcharge line');
    }
}