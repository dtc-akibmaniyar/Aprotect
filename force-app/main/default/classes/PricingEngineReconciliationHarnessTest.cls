/**
 * PricingEngineReconciliationHarnessTest
 *
 * P3 reconciliation harness (change-implementation plan §13.4 + §11 P3 [T];
 * design success criteria 2 & 3): a parameter sweep over the quote matrix
 * asserting the pricing engine's invariants on ≥ 200 quotes.
 *
 * Structure: one @isTest method per (region x case-group) so each method stays
 * inside the 100-SOQL test governor while the whole class sweeps
 * 8 tax regions × 11 case shapes × up to 4 quote variants ≈ 205 quotes.
 *
 * Sweep dimensions:
 *   regions 8 : 0%, 5%, 11%, 12% (x2), 13%, 14.98%, 15%
 *   vehicles  : premium make, diesel car, diesel commercial, gas commercial,
 *               powersports make, standard (no-fee)
 *   plans     : premium (+diesel+commercial), diesel, commercial, powersports,
 *               entry (no schedules → R4 no fee)
 *   terms     : no markup/discount, $ markup, % markup, $ discount,
 *               % discount + $ markup
 *   overrides : pre-tax custom price; R5 override dealer (one region)
 *   waivers   : premium waived variant of every premium-expected case
 *
 * Assertions per quote: (a) symmetry noTax == withTax − tax, 0 variance (§07.3);
 * (b) noTax == plain sum of lines; (c) fee lines present iff the schedule
 * matrix says so; (d) override prices base only; (e) waiver adds no premium
 * line; (f) determinism (R6) on a subset.
 */
@isTest
private class PricingEngineReconciliationHarnessTest {

    private static Integer totalQuotes = 0;
    private static Integer symmetryFailures = 0;
    private static Integer lineSumFailures = 0;
    private static Integer feePresenceFailures = 0;
    private static Integer determinismFailures = 0;
    private static Integer otherFailures = 0;
    private static final List<String> failures = new List<String>();

    private static Map<String, Id> recordTypes;
    private static Id rt(String sObjectType, String devName) {
        if (recordTypes == null) {
            recordTypes = new Map<String, Id>();
            for (RecordType rt : [SELECT Id, SObjectType, DeveloperName FROM RecordType
                                  WHERE SObjectType IN ('Account','Package__c','Dealer_Package__c')]) {
                recordTypes.put(rt.SObjectType + '.' + rt.DeveloperName, rt.Id);
            }
        }
        return recordTypes.get(sObjectType + '.' + devName);
    }

    private static Make__c make(String name) { Make__c m = new Make__c(Name = name); insert m; return m; }
    private static Model__c model(Make__c makeRec, String name) { Model__c m = new Model__c(Name = name, Make__c = makeRec.Id); insert m; return m; }
    private static Vehicle__c vehicle(String name, Make__c makeRec, Model__c modelRec, String fuel, String usage) {
        Vehicle__c v = new Vehicle__c(Name = name, Make_Lookup__c = makeRec != null ? makeRec.Id : null,
            Model_Lookup__c = modelRec != null ? modelRec.Id : null, Fuel_Type__c = fuel, Usage_Type__c = usage);
        insert v; return v;
    }

    private class HarnessCase {
        public Id dealerId;
        public Vehicle__c vehicleRec;
        public Id dealerTermId;
        public Boolean expectPremium, expectDiesel, expectCommercial, expectPowersports;
        public String label;
    }

    /**
     * Master plan + schedules + dealer mirror term for one case. The
     * Dealer_Package__c header is created WITHOUT a Package link so the
     * after-insert sync fan-out is skipped (SOQL-budget) — the engine receives
     * the dealerId explicitly and reads the term by id.
     */
    private static HarnessCase buildCase(Id dealerId, Vehicle__c v, String flags,
                                         Decimal markup, String markupType,
                                         Decimal discount, String discountType,
                                         Boolean expPremium, Boolean expDiesel,
                                         Boolean expCommercial, Boolean expPowersports,
                                         Integer seq) {
        Package_Group__c grp = new Package_Group__c(Name = 'HRG' + seq, Active__c = true);
        insert grp;
        Package__c pkg = new Package__c(Name = 'HRP' + seq, Package_Group__c = grp.Id,
            RecordTypeId = rt('Package__c', 'Extended_Limited_Warranty'), Is_Active__c = true);
        insert pkg;
        Package_Tier__c tier = new Package_Tier__c(Name = 'HRT' + seq, Package__c = pkg.Id);
        insert tier;
        Package_Term__c term = new Package_Term__c(Name = 'HRM' + seq, Package_Tier__c = tier.Id, Price__c = 1000.00);
        insert term;

        Date validFrom = Date.newInstance(2026, 1, 1);
        if (flags.contains('premium')) {
            Vehicle_Schedule__c sched = new Vehicle_Schedule__c(Name = 'HR prem ' + seq, Type__c = 'Premium_Tier', Is_Active__c = true, Valid_From__c = validFrom);
            insert sched;
            insert new Vehicle_Schedule_Member__c(Name = 'prem row', Vehicle_Schedule__c = sched.Id,
                Make__c = v.Make_Lookup__c, Include_All_Models__c = true, Amount_Type__c = 'Flat',
                Premium_Model_Fee__c = 299.00, Sort_Order__c = 0);
            insert new Vehicle_Schedule_Assignment__c(Name = 'a' + seq, Vehicle_Schedule__c = sched.Id, Dealer__c = dealerId, Effective_From__c = validFrom);
        }
        if (flags.contains('diesel')) {
            Vehicle_Schedule__c sched = new Vehicle_Schedule__c(Name = 'HR diesel ' + seq, Type__c = 'Diesel_Fee', Is_Active__c = true, Valid_From__c = validFrom);
            insert sched;
            insert new Vehicle_Schedule_Member__c(Name = 'diesel row', Vehicle_Schedule__c = sched.Id,
                Include_All_Models__c = true, Amount_Type__c = 'Flat', Premium_Model_Fee__c = 150.00, Sort_Order__c = 0);
            insert new Vehicle_Schedule_Assignment__c(Name = 'a' + seq, Vehicle_Schedule__c = sched.Id, Dealer__c = dealerId, Effective_From__c = validFrom);
        }
        if (flags.contains('commercial')) {
            Vehicle_Schedule__c sched = new Vehicle_Schedule__c(Name = 'HR comm ' + seq, Type__c = 'Commercial_Surcharge', Is_Active__c = true, Valid_From__c = validFrom);
            insert sched;
            insert new Vehicle_Schedule_Member__c(Name = 'comm row', Vehicle_Schedule__c = sched.Id,
                Include_All_Models__c = true, Amount_Type__c = 'Flat', Premium_Model_Fee__c = 400.00, Sort_Order__c = 0);
            insert new Vehicle_Schedule_Assignment__c(Name = 'a' + seq, Vehicle_Schedule__c = sched.Id, Dealer__c = dealerId, Effective_From__c = validFrom);
        }
        if (flags.contains('powersports')) {
            Vehicle_Schedule__c sched = new Vehicle_Schedule__c(Name = 'HR ps ' + seq, Type__c = 'Powersports_Program', Is_Active__c = true, Valid_From__c = validFrom);
            insert sched;
            insert new Vehicle_Schedule_Member__c(Name = 'ps row', Vehicle_Schedule__c = sched.Id,
                Make__c = v.Make_Lookup__c, Include_All_Models__c = true, Amount_Type__c = 'Multiplier',
                Multiplier__c = 1.25, Sort_Order__c = 0);
            insert new Vehicle_Schedule_Assignment__c(Name = 'a' + seq, Vehicle_Schedule__c = sched.Id, Dealer__c = dealerId, Effective_From__c = validFrom);
        }

        Dealer_Package__c dp = new Dealer_Package__c(Name = 'HR DP ' + seq, Dealer__c = dealerId,
            RecordTypeId = rt('Dealer_Package__c', 'Extended_Limited_Warranty'));
        insert dp; // Package__c = null => trigger fan-out skips (no sync SOQL)
        Dealer_Package_Term__c dpt = new Dealer_Package_Term__c(Name = term.Name + ' d',
            Dealer_Package__c = dp.Id, Package_Term__c = term.Id,
            Original_Package_Term_Cost__c = 1000.00,
            Markup__c = markup, Markup_Type__c = markupType,
            Discount_Value__c = discount, Discount_Type__c = discountType);
        insert dpt;

        HarnessCase c = new HarnessCase();
        c.dealerId = dealerId;
        c.vehicleRec = v;
        c.dealerTermId = dpt.Id;
        c.expectPremium = expPremium;
        c.expectDiesel = expDiesel;
        c.expectCommercial = expCommercial;
        c.expectPowersports = expPowersports;
        c.label = 'case' + seq;
        return c;
    }

    private static PricingEngineService.QuoteRequest reqFor(HarnessCase c, Boolean waive, Decimal customPrice) {
        PricingEngineService.QuoteRequest r = new PricingEngineService.QuoteRequest();
        r.dealerId = c.dealerId;
        r.vehicleId = c.vehicleRec.Id;
        r.dealerTermId = c.dealerTermId;
        r.waivePremiumFee = waive;
        r.dealerPriceOverride = customPrice;
        r.asOfDate = Date.newInstance(2026, 9, 3);
        return r;
    }

    private static void checkCase(HarnessCase c, Boolean doWaiver, Boolean doOverride, Boolean doDeterminism) {
        PricingEngineService.QuoteResult res = PricingEngineService.computeQuote(reqFor(c, false, null));
        totalQuotes++;
        validate(res, c.label + ' normal', c);

        if (doWaiver && c.expectPremium) {
            PricingEngineService.QuoteResult waived = PricingEngineService.computeQuote(reqFor(c, true, null));
            totalQuotes++;
            if (waived.premiumFee != 0) { otherFailures++; failures.add(c.label + ': waiver premiumFee != 0'); }
            Boolean premiumLine = false;
            for (PricingEngineService.QuoteLine l : waived.lines) {
                if (PricingEngineService.LT_PREMIUM_FEE.equals(l.lineType)) premiumLine = true;
            }
            if (premiumLine) { otherFailures++; failures.add(c.label + ': waived quote still has a premium line'); }
            validateSymmetryOnly(waived, c.label + ' waived');
        }

        if (doOverride) {
            PricingEngineService.QuoteResult overridden = PricingEngineService.computeQuote(reqFor(c, false, 1200.00));
            totalQuotes++;
            if (overridden.noTaxTotal != 1200.00 || overridden.baseCoverage != 1200.00
                || overridden.markupAmount != 0 || overridden.lines.size() != 1) {
                otherFailures++; failures.add(c.label + ': override != base-only 1200 (noTax=' + overridden.noTaxTotal + ')');
            }
            validateSymmetryOnly(overridden, c.label + ' override');
        }

        if (doDeterminism) {
            PricingEngineService.QuoteResult again = PricingEngineService.computeQuote(reqFor(c, false, null));
            totalQuotes++;
            if (again.noTaxTotal != res.noTaxTotal || again.withTaxTotal != res.withTaxTotal
                || again.lines.size() != res.lines.size()) {
                determinismFailures++; failures.add(c.label + ': non-deterministic');
            }
        }
    }

    private static void validate(PricingEngineService.QuoteResult res, String label, HarnessCase c) {
        validateSymmetryOnly(res, label);
        Boolean premium = false, diesel = false, commercial = false, powersports = false;
        for (PricingEngineService.QuoteLine l : res.lines) {
            if (PricingEngineService.LT_PREMIUM_FEE.equals(l.lineType)) premium = true;
            if (PricingEngineService.LT_DIESEL_FEE.equals(l.lineType)) diesel = true;
            if (PricingEngineService.LT_COMMERCIAL_SURCHARGE.equals(l.lineType)) commercial = true;
            if (PricingEngineService.LT_POWERSPORTS_ADJUSTMENT.equals(l.lineType)) powersports = true;
        }
        if (premium != c.expectPremium) { feePresenceFailures++; failures.add(label + ': premium ' + premium + ' != ' + c.expectPremium); }
        if (diesel != c.expectDiesel) { feePresenceFailures++; failures.add(label + ': diesel ' + diesel + ' != ' + c.expectDiesel); }
        if (commercial != c.expectCommercial) { feePresenceFailures++; failures.add(label + ': commercial ' + commercial + ' != ' + c.expectCommercial); }
        if (powersports != c.expectPowersports) { feePresenceFailures++; failures.add(label + ': powersports ' + powersports + ' != ' + c.expectPowersports); }
    }

    private static void validateSymmetryOnly(PricingEngineService.QuoteResult res, String label) {
        Decimal check = PricingEngineService.money(res.withTaxTotal - res.taxAmount);
        if (check != res.noTaxTotal) {
            symmetryFailures++;
            failures.add(label + ': symmetry noTax=' + res.noTaxTotal + ' tax=' + res.taxAmount + ' withTax=' + res.withTaxTotal);
        }
        Decimal sum = 0;
        for (PricingEngineService.QuoteLine l : res.lines) {
            sum = PricingEngineService.money(sum + l.amount);
        }
        if (sum != res.noTaxTotal) { lineSumFailures++; failures.add(label + ': sum ' + sum + ' != noTax ' + res.noTaxTotal); }
    }

    private static void assertRegionClean(String regionName) {
        System.assertEquals(0, symmetryFailures, regionName + ' symmetry:\\n' + String.join(failures, '\n'));
        System.assertEquals(0, lineSumFailures, regionName + ' line sum:\\n' + String.join(failures, '\n'));
        System.assertEquals(0, feePresenceFailures, regionName + ' fee presence:\\n' + String.join(failures, '\n'));
        System.assertEquals(0, determinismFailures, regionName + ' determinism:\\n' + String.join(failures, '\n'));
        System.assertEquals(0, otherFailures, regionName + ' other:\\n' + String.join(failures, '\n'));
        System.debug('HARNESS ' + regionName + ': quotes=' + totalQuotes);
    }

    private static Id regionId(String name, Decimal rate) {
        Tax__c t = new Tax__c(Name = name, Total_Tax_Rate__c = rate);
        insert t;
        return t.Id;
    }

    // ------------------------------------------------------------------
    // Group runners — every region runs two methods (premium group + gates)
    // ------------------------------------------------------------------

    private static void premiumGroup(String regionName, Decimal rate, Boolean r5) {
        Id region = regionId(regionName, rate);
        Account d = new Account(Name = 'D' + regionName, RecordTypeId = rt('Account', 'Dealer_Account'),
            Charge_Premium_Vehicle_Fee__c = false, Tax_Region__c = region);
        insert d;
        Account dR5 = null;
        if (r5) {
            dR5 = new Account(Name = 'R5' + regionName, RecordTypeId = rt('Account', 'Dealer_Account'),
                Charge_Premium_Vehicle_Fee__c = true, Premium_Fee_Override_Amount__c = 275.00, Tax_Region__c = region);
            insert dR5;
        }
        Make__c porsche = make('P' + regionName);
        Model__c boxster = model(porsche, 'B');
        Vehicle__c vPrem = vehicle('V1' + regionName, porsche, boxster, 'Gas', 'Personal Use');

        Integer seq = 0;
        List<HarnessCase> cases = new List<HarnessCase>();
        cases.add(buildCase(d.Id, vPrem, 'premium,diesel,commercial', 100, '$', null, null, true, false, false, false, seq++));
        cases.add(buildCase(d.Id, vPrem, 'premium', null, null, null, null, true, false, false, false, seq++));
        cases.add(buildCase(d.Id, vPrem, 'premium', 20, '%', null, null, true, false, false, false, seq++));
        cases.add(buildCase(d.Id, vPrem, 'premium', 100, '$', 50, '$', true, false, false, false, seq++));
        cases.add(buildCase(d.Id, vPrem, 'premium', 25, '%', 10, '%', true, false, false, false, seq++));
        if (r5) {
            cases.add(buildCase(dR5.Id, vPrem, 'premium', 100, '$', null, null, true, false, false, false, seq++));
        }
        Integer i = 0;
        for (HarnessCase c : cases) {
            // R5 override dealer case skips the custom-price variant; the R5
            // region also skips the determinism recompute — both keep the
            // method inside the 100-SOQL governor.
            checkCase(c, i != cases.size() - 1, i != cases.size() - 1, i == 0 && !r5);
            i++;
        }
        assertRegionClean(regionName + '-premium');
    }

    private static void gatesGroup(String regionName, Decimal rate) {
        Id region = regionId(regionName, rate);
        Account d = new Account(Name = 'D' + regionName, RecordTypeId = rt('Account', 'Dealer_Account'),
            Charge_Premium_Vehicle_Fee__c = false, Tax_Region__c = region);
        insert d;
        Make__c ford = make('F' + regionName);
        Model__c f150 = model(ford, '150');
        Make__c harley = make('H' + regionName);
        Model__c sportster = model(harley, 'S');
        Make__c toyota = make('T' + regionName);
        Model__c camry = model(toyota, 'C');
        Vehicle__c vDiesel = vehicle('V2' + regionName, ford, f150, 'Diesel', 'Personal Use');
        Vehicle__c vDieselComm = vehicle('V3' + regionName, ford, f150, 'Diesel', 'Commercial/Business Use');
        Vehicle__c vComm = vehicle('V4' + regionName, ford, f150, 'Gas', 'Commercial/Business Use');
        Vehicle__c vPs = vehicle('V5' + regionName, harley, sportster, 'Gas', 'Personal Use');
        Vehicle__c vStd = vehicle('V6' + regionName, toyota, camry, 'Gas', 'Personal Use');

        Integer seq = 100;
        List<HarnessCase> cases = new List<HarnessCase>();
        cases.add(buildCase(d.Id, vDiesel, 'diesel', 100, '$', null, null, false, true, false, false, seq++));
        cases.add(buildCase(d.Id, vDieselComm, 'diesel,commercial', 100, '$', null, null, false, true, true, false, seq++));
        cases.add(buildCase(d.Id, vComm, 'commercial', 100, '$', null, null, false, false, true, false, seq++));
        cases.add(buildCase(d.Id, vPs, 'powersports', 100, '$', null, null, false, false, false, true, seq++));
        cases.add(buildCase(d.Id, vStd, 'none', 100, '$', null, null, false, false, false, false, seq++));
        Integer i = 0;
        for (HarnessCase c : cases) {
            checkCase(c, false, true, i == 0);
            i++;
        }
        assertRegionClean(regionName + '-gates');
    }

    // 8 regions x 2 groups + 1 R5 extra method => ~205 quotes
    @isTest static void zeroPrem()  { premiumGroup('ZR', 0, false); }
    @isTest static void zeroGate()  { gatesGroup('ZR', 0); }
    @isTest static void abPrem()    { premiumGroup('AB', 5, false); }
    @isTest static void abGate()    { gatesGroup('AB', 5); }
    @isTest static void skPrem()    { premiumGroup('SK', 11, false); }
    @isTest static void skGate()    { gatesGroup('SK', 11); }
    @isTest static void mbPrem()    { premiumGroup('MB', 12, false); }
    @isTest static void mbGate()    { gatesGroup('MB', 12); }
    @isTest static void bcPrem()    { premiumGroup('BC', 12, false); }
    @isTest static void bcGate()    { gatesGroup('BC', 12); }
    @isTest static void onPrem()    { premiumGroup('ON', 13, true); }
    @isTest static void onGate()    { gatesGroup('ON', 13); }
    @isTest static void qcPrem()    { premiumGroup('QC', 14.98, false); }
    @isTest static void qcGate()    { gatesGroup('QC', 14.98); }
    @isTest static void nbPrem()    { premiumGroup('NB', 15, false); }
    @isTest static void nbGate()    { gatesGroup('NB', 15); }
}