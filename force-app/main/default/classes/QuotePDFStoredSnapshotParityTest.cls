/**
 * QuotePDFStoredSnapshotParityTest
 *
 * P4 [T] Conga/quote-PDF stored-snapshot check — Apex payload-parity evidence
 * (change-implementation plan §11 P4 [T], §07.3, P4 exit criteria: "contract
 * PDF, portal and invoice agree on a sample of mixed-fee deals"; decision
 * 2026-09-06 option (b): source-level + Apex payload-parity evidence).
 *
 * The quote PDF path (QuotePDFGeneratorService.generateQuotePDF -> /apex/QuotePDF
 * -> QuotePDFExtension) and the two application-PDF pages
 * (CarLoanProtectionApplicationVFP + DealerPortalVehicleApplicationPDFs ->
 * ApplicationPDFExtension) render money from the STORED values on
 * Application_Package__c. Source-level facts (verified in this run):
 *   - QuotePDFExtension sums the org formula fields (Dealer_Package_Retail_Price__c
 *     = Dealer_Package_Price__c + Dealer_Markup__c; Add_Ons_Retail_Price__c =
 *     Add_Ons_Price__c + Add_Ons_Markup__c; Tax_Amount__c / Contract_Premium_*__c
 *     — P3-corrected single-tax formulas, commit b845ca3) into
 *     retailPriceTotal / quoteTotal / taxTotal / grandTotal. No Apex recompute
 *     of the markup math.
 *   - ApplicationPDFExtension pages merge the stored trio
 *     (Contract_Premium_Price_Without_Tax__c / Tax_Amount__c /
 *     Contract_Premium_Price__c) directly.
 *   - P4 [S]: the PDF option display reads the package's priced Option LINE
 *     ITEMS (the engine snapshot contract) for the optional-option retail
 *     parenthetical and the dealer-option mirror for the Included-option name
 *     lists — the SAME sources the engine prices from / the legacy flow
 *     copied from, so the display cannot drift from the priced option.
 *     Application_Package_Option__c children are retired org-side in P4 [S].
 *
 * WHY THE ADDITIVE FIX SHIPPED WITH THIS TEST: fee lines with no stored
 * carrier on Application_Package__c (diesel / commercial / powersports —
 * engine-only concepts) and the premium fee (Premium_Model_Fee__c, engine-
 * written) are NOT part of the legacy formula surface that the PDFs summed.
 * An engine-priced quote with such fees would render LESS money than the
 * engine/line-item/portal totals. The fix (this commit, p4-t): when an
 * engine-priced package carries its persisted line-item snapshot, the PDF
 * money rebuilds from the stored lines (sum(non-Tax lines) = no-tax total,
 * sum(Tax lines) = tax, sum(all) = with-tax total — the exact §07.3 rebuild
 * DealerPortalController / ApplicationSummaryController use for the per-tab
 * payloads). Packages without a line set keep the legacy stored/formula build
 * byte-for-byte, so the flag-off state renders exactly as before.
 *
 * What the tests prove:
 *   - No-line build (the flag-off / legacy shape): QuotePDF totals == the
 *     stored formula fields == the flag-off portal payload keys
 *     (PDF == portal on the legacy path, unchanged).
 *   - Engine fee-matrix build (base + premium + diesel + commercial, lines
 *     snapshotted): QuotePDF totals == the engine QuoteResult totals == the
 *     stored line sums == the engine portal payload keys; the legacy formula
 *     build understates by exactly the fees + their tax (the delta the fix
 *     removes — documented, not papered over).
 *   - Premium-only engine quote: the line build and the formula build
 *     converge to the cent (the fee IS expressible in the formula surface).
 *   - Optional-option engine quote: the option retail is included once in the
 *     line build and the PDF's APO parenthetical read shows the same number
 *     the engine priced.
 *   - ApplicationPDFExtension rendered* keys: legacy (no lines) == stored
 *     trio; fee-matrix (lines) == engine totals == portal payload keys.
 *
 * TEST CONTEXT FACTS (same as the [L] parity suites): inserting a NON-engine-
 * priced Application_Package runs the legacy create-time flow, which cannot
 * execute in the test user context; every insert mirrors production — the
 * engine stamps the record (Priced_By_Engine__c = true) BEFORE the DML so the
 * flow terminates at its engine guard. Application__c fixtures are built at
 * INSERT (the locked/paid state quirk is irrelevant here). Package__c
 * percent-config is never read (engine quotes use handler DEFAULT constants).
 */
@isTest
private class QuotePDFStoredSnapshotParityTest {

    private static Map<String, Id> recordTypes;
    private static Id rt(String sObjectType, String devName) {
        if (recordTypes == null) {
            recordTypes = new Map<String, Id>();
            for (RecordType r : [SELECT Id, SObjectType, DeveloperName FROM RecordType
                                 WHERE SObjectType IN ('Account','Package__c','Dealer_Package__c','Application_Package__c')]) {
                recordTypes.put(r.SObjectType + '.' + r.DeveloperName, r.Id);
            }
        }
        return recordTypes.get(sObjectType + '.' + devName);
    }

    private static Tax__c taxRegion(String name, Decimal rate) {
        Tax__c t = new Tax__c(Name = name, Total_Tax_Rate__c = rate);
        insert t;
        return t;
    }

    private static Account dealer(String name, Tax__c region) {
        Account d = new Account(Name = name,
            RecordTypeId = rt('Account', 'Dealer_Account'),
            Charge_Premium_Vehicle_Fee__c = false,
            Tax_Region__c = region != null ? region.Id : null);
        insert d;
        return d;
    }

    private static Make__c make(String name) { Make__c m = new Make__c(Name = name); insert m; return m; }
    private static Model__c model(Make__c m, String name) { Model__c mo = new Model__c(Name = name, Make__c = m.Id); insert mo; return mo; }

    private static Vehicle__c vehicle(String name, Make__c m, Model__c mo, String fuel, String usage) {
        Vehicle__c v = new Vehicle__c(Name = name, Make_Lookup__c = m.Id, Model_Lookup__c = mo.Id,
            Fuel_Type__c = fuel, Usage_Type__c = usage);
        insert v;
        return v;
    }

    private class Ctx {
        public Account dealer;
        public Vehicle__c v;
        public Id dealerPackageId;
        public Dealer_Package_Term__c dt;
        public Application__c app;
        public Id masterPkgId;
        public Id masterTermId;
    }

    /** Full context: catalogue + dealer mirror + schedules + Application. */
    private static Ctx build(String tag, Decimal rate, Boolean premium, Boolean diesel, Boolean commercial) {
        Tax__c tax = taxRegion('QPT' + tag, rate);
        Account d = dealer('QD' + tag, tax);
        Make__c mk = make('QMK' + tag);
        Model__c mo = model(mk, 'QMD' + tag);
        Vehicle__c v = vehicle('QV' + tag, mk, mo,
            diesel ? 'Diesel' : 'Gas',
            commercial ? 'Commercial/Business Use' : 'Personal Use');

        Package_Group__c grp = new Package_Group__c(Name = 'QGRP' + tag, Active__c = true);
        insert grp;
        Package__c pkg = new Package__c(Name = 'QPKG' + tag, Package_Group__c = grp.Id,
            RecordTypeId = rt('Package__c', 'Extended_Limited_Warranty'), Is_Active__c = true);
        insert pkg;
        Package_Tier__c tier = new Package_Tier__c(Name = 'QTIR' + tag, Package__c = pkg.Id);
        insert tier;
        Package_Term__c mt = new Package_Term__c(Name = 'QTRM' + tag, Package_Tier__c = tier.Id, Price__c = 1000.00);
        insert mt;

        Date vf = Date.newInstance(2026, 1, 1);
        if (premium) {
            Vehicle_Schedule__c s = new Vehicle_Schedule__c(Name = 'QSP' + tag, Type__c = 'Premium_Tier', Is_Active__c = true, Valid_From__c = vf);
            insert s;
            insert new Vehicle_Schedule_Member__c(Name = 'QSPm' + tag, Vehicle_Schedule__c = s.Id, Make__c = mk.Id,
                Include_All_Models__c = true, Tier__c = 'Tier 2', Amount_Type__c = 'Flat',
                Premium_Model_Fee__c = 299.00, Sort_Order__c = 0);
            insert new Vehicle_Schedule_Assignment__c(Name = 'QSPa' + tag, Vehicle_Schedule__c = s.Id, Package__c = pkg.Id, Effective_From__c = vf);
        }
        if (diesel) {
            Vehicle_Schedule__c s = new Vehicle_Schedule__c(Name = 'QSD' + tag, Type__c = 'Diesel_Fee', Is_Active__c = true, Valid_From__c = vf);
            insert s;
            insert new Vehicle_Schedule_Member__c(Name = 'QSDm' + tag, Vehicle_Schedule__c = s.Id,
                Include_All_Models__c = true, Amount_Type__c = 'Flat',
                Premium_Model_Fee__c = 150.00, Sort_Order__c = 0);
            insert new Vehicle_Schedule_Assignment__c(Name = 'QSDa' + tag, Vehicle_Schedule__c = s.Id, Package__c = pkg.Id, Effective_From__c = vf);
        }
        if (commercial) {
            Vehicle_Schedule__c s = new Vehicle_Schedule__c(Name = 'QSC' + tag, Type__c = 'Commercial_Surcharge', Is_Active__c = true, Valid_From__c = vf);
            insert s;
            insert new Vehicle_Schedule_Member__c(Name = 'QSCm' + tag, Vehicle_Schedule__c = s.Id,
                Include_All_Models__c = true, Amount_Type__c = 'Flat',
                Premium_Model_Fee__c = 400.00, Sort_Order__c = 0);
            insert new Vehicle_Schedule_Assignment__c(Name = 'QSCa' + tag, Vehicle_Schedule__c = s.Id, Package__c = pkg.Id, Effective_From__c = vf);
        }

        Dealer_Package__c dp = new Dealer_Package__c(Name = 'QDP' + tag, Dealer__c = d.Id,
            Package__c = pkg.Id, RecordTypeId = rt('Dealer_Package__c', 'Extended_Limited_Warranty'));
        insert dp;
        Dealer_Package_Term__c dt = new Dealer_Package_Term__c(Name = 'QDPT' + tag,
            Dealer_Package__c = dp.Id, Package_Term__c = mt.Id,
            Original_Package_Term_Cost__c = 1000.00, Markup__c = 100.00, Markup_Type__c = '$');
        insert dt;

        Ctx c = new Ctx();
        c.dealer = d; c.v = v; c.dealerPackageId = dp.Id; c.dt = dt;
        c.masterPkgId = pkg.Id; c.masterTermId = mt.Id;
        c.app = new Application__c(Vehicle__c = v.Id, Dealer_Name__c = d.Id);
        insert c.app;
        return c;
    }

    private static void setFlags(Boolean engine, Boolean snapshot) {
        delete [SELECT Id FROM Aprotect_Portal_Settings__c];
        insert new Aprotect_Portal_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Pricing_Engine_Enabled__c = engine,
            Line_Item_Snapshot_Enabled__c = snapshot,
            Dealer_Sync_Enabled__c = true
        );
    }

    /** Engine-stamp + INSERT (flow guard: marker pre-DML), then snapshot. */
    private static Application_Package__c insertEnginePricedPackage(Ctx c) {
        Application_Package__c pkg = new Application_Package__c(
            Name = 'QAPK' + c.v.Name,
            Application__c = c.app.Id,
            Dealer__c = c.dealer.Id,
            Dealer_Package__c = c.dealerPackageId,
            Dealer_Package_Term__c = c.dt.Id,
            RecordTypeId = rt('Application_Package__c', 'Extended_Limited_Warranty'),
            Active__c = true
        );
        PricingEngineService.QuoteRequest req = requestFor(c, pkg);
        PricingEngineService.QuoteResult res = PricingEngineService.applyEnginePricing(pkg, req);
        System.assert(res.success, 'engine pricing expected to succeed: ' + res.errors);
        Database.insert(pkg, System.AccessLevel.SYSTEM_MODE);
        // Snapshot is written only under the T5 gate; the flag-off tests use
        // this same helper for the no-line (legacy) shape, so assert only when
        // the snapshot flag is on.
        if (PortalFeatureFlagService.isLineItemSnapshotEnabled()) {
            Boolean written = ApplicationSnapshotService.writeSnapshot(pkg.Id,
                PricingEngineService.applyEnginePricing(pkg, requestFor(c, pkg)));
            System.assertEquals(true, written, 'snapshot must be written for the parity fixture (flags on)');
        }
        return pkg;
    }

    /** Re-stamp an existing engine-priced package (options added since save). */
    private static PricingEngineService.QuoteResult restampAndSnapshot(Ctx c, Application_Package__c pkg) {
        PricingEngineService.QuoteResult res = PricingEngineService.applyEnginePricing(pkg, requestFor(c, pkg));
        System.assert(res.success, 'restamp expected to succeed: ' + res.errors);
        Boolean written = ApplicationSnapshotService.writeSnapshot(pkg.Id, res);
        System.assertEquals(true, written, 'snapshot rewrite must succeed');
        return res;
    }

    private static PricingEngineService.QuoteRequest requestFor(Ctx c, Application_Package__c pkg) {
        PricingEngineService.QuoteRequest req = new PricingEngineService.QuoteRequest();
        req.dealerId = c.dealer.Id;
        req.vehicleId = c.v.Id;
        req.dealerPackageId = c.dealerPackageId;
        req.dealerTermId = c.dt.Id;
        req.applicationPackageId = pkg.Id;
        req.asOfDate = Date.newInstance(2026, 9, 3);
        return req;
    }

    // ------------------------------------------------------------------
    // PDF reads under test
    // ------------------------------------------------------------------

    /** Construct the QuotePDF extension (the /apex/QuotePDF money path). */
    private static QuotePDFExtension quotePdf(Ctx c) {
        ApexPages.StandardController stdCtrl = new ApexPages.StandardController(c.app);
        return new QuotePDFExtension(stdCtrl);
    }

    /** Construct the ApplicationPDF extension (the two application-PDF pages). */
    private static ApplicationPDFExtension applicationPdf(Ctx c) {
        ApexPages.StandardController stdCtrl = new ApexPages.StandardController(c.app);
        return new ApplicationPDFExtension(stdCtrl);
    }

    /** The engine tab payload money keys (portal read). */
    private static Map<String, Object> readActivePackagePayload(Id appId) {
        DealerPortalController.ApplicationPackageResponse response =
            DealerPortalController.getActiveApplicationPackageByRecordType(appId, 'Extended_Limited_Warranty');
        System.assert(response != null && response.success, 'active-package read expected to succeed: '
            + (response == null ? 'null' : response.message));
        return response.data;
    }

    /** Stored line sums for the package (the §07.3 rebuild source). */
    private static void assertQuotePdfMoney(Ctx c, Decimal expNoTax, Decimal expTax, Decimal expTotal,
                                            Boolean expHasLines, String ctx) {
        QuotePDFExtension ext = quotePdf(c);
        System.assertEquals(1, ext.packageWrappersList.size(), ctx + ': one active package expected');
        QuotePDFExtension.PackageWrapper w = ext.packageWrappersList[0];
        System.assertEquals(expHasLines, w.hasStoredLineMoney == true, ctx + ': hasStoredLineMoney');
        System.assertEquals(expNoTax, w.retailPriceTotal, ctx + ': per-package PRICE (pre-tax)');
        System.assertEquals(expNoTax, ext.quoteTotal, ctx + ': Sub-Total');
        System.assertEquals(expTax, ext.taxTotal, ctx + ': Tax');
        System.assertEquals(expTotal, ext.grandTotal, ctx + ': Total');
    }

    private static void assertApplicationPdfMoney(Ctx c, Decimal expNoTax, Decimal expTax, Decimal expTotal,
                                                  Boolean expHasLines, String ctx) {
        ApplicationPDFExtension ext = applicationPdf(c);
        Boolean found = false;
        for (ApplicationPDFExtension.RecordTypeWrapper rtw : ext.recordTypeWrappersList) {
            for (ApplicationPDFExtension.PackageWrapper w : rtw.packages) {
                found = true;
                System.assertEquals(expHasLines, w.hasStoredLineMoney == true, ctx + ': hasStoredLineMoney');
                System.assertEquals(expNoTax, w.renderedContractPremiumWithoutTax, ctx + ': Warranty Cost');
                System.assertEquals(expTax, w.renderedTaxAmount, ctx + ': Tax');
                System.assertEquals(expTotal, w.renderedContractPremium, ctx + ': Total');
            }
        }
        System.assertEquals(true, found, ctx + ': at least one package wrapper rendered');
    }

    // ------------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------------

    @isTest
    static void testQuotePdf_NoLineBuild_EqualsStoredFormulasAndLegacyPortalPayload() {
        setFlags(true, false); // snapshot OFF -> engine-priced record WITHOUT a line set
        Ctx c = build('Q1', 13, false, false, false);
        insertEnginePricedPackage(c);

        // Legacy build: base 1100, tax 13% -> 143, total 1243. The PDF reads
        // exactly the stored/formula surface (no lines -> no line rebuild).
        assertQuotePdfMoney(c, 1100.00, 143.00, 1243.00, false, 'no-line build');

        // PDF == portal on the legacy path: the flag-off payload keys are the
        // same stored/formula values the PDF totals.
        Map<String, Object> payload = readActivePackagePayload(c.app.Id);
        System.assertEquals(1100.00, payload.get('contractPremiumPriceWithoutTax'));
        System.assertEquals(143.00, payload.get('taxAmount'));
        System.assertEquals(1243.00, payload.get('contractPremiumPrice'));
        System.assertEquals(null, payload.get('lineItems'), 'no-line payload must not attach engine lines');
    }

    @isTest
    static void testQuotePdf_FeeMatrix_LineBuildEqualsEngineTotalsAndPortalPayload() {
        setFlags(true, true); // snapshot ON -> line set written
        Ctx c = build('Q2', 13, true, true, true); // base + premium 299 + diesel 150 + commercial 400
        Application_Package__c pkg = insertEnginePricedPackage(c);

        // The engine's own totals. Deterministic fee matrix (P1 worked example
        // + warranty parity suite): base 1100 (net 1000 + $100 markup),
        // premium 299, diesel 150, commercial 400, 13% tax on all of it.
        PricingEngineService.QuoteResult res = PricingEngineService.applyEnginePricing(pkg, requestFor(c, pkg));
        System.assert(res.success, 'engine pricing expected to succeed');
        System.assertEquals(1949.00, res.noTaxTotal, 'fee-matrix no-tax total');
        System.assertEquals(253.37, res.taxAmount, 'fee-matrix tax');
        System.assertEquals(2202.37, res.withTaxTotal, 'fee-matrix with-tax total');
        Decimal expNoTax = res.noTaxTotal;
        Decimal expTax = res.taxAmount;
        Decimal expTotal = res.withTaxTotal;

        assertQuotePdfMoney(c, expNoTax, expTax, expTotal, true, 'fee-matrix line build');

        // PDF == portal == engine on the mixed-fee sample (P4 exit criterion).
        Map<String, Object> payload = readActivePackagePayload(c.app.Id);
        System.assertEquals(expNoTax, payload.get('contractPremiumPriceWithoutTax'), 'payload no-tax == line sum');
        System.assertEquals(expTax, payload.get('taxAmount'), 'payload tax == Tax-line sum');
        System.assertEquals(expTotal, payload.get('contractPremiumPrice'), 'payload with-tax == all-line sum');

        // The legacy formula build (what the PDF rendered BEFORE this fix)
        // understates the mixed-fee quote: retail formula (base 1100) + stored
        // formula tax ((1100 + premium 299) * 13% = 181.87) = 1281.87. The
        // delta 920.50 = the fees not on the legacy surface (premium display
        // gap 299 + diesel 150 + commercial 400) + their tax ((1949-1399)*13%
        // = 71.50). That gap is exactly what the line rebuild removes.
        Application_Package__c stored = [SELECT Dealer_Package_Retail_Price__c, Add_Ons_Retail_Price__c,
                                                Tax_Amount__c
                                         FROM Application_Package__c WHERE Id = :pkg.Id];
        Decimal legacyPdfTotal = stored.Dealer_Package_Retail_Price__c + stored.Add_Ons_Retail_Price__c
            + stored.Tax_Amount__c;
        System.assertEquals(1281.87, legacyPdfTotal, 'legacy formula PDF total (pre-fix render)');
        System.assertEquals(920.50, expTotal - legacyPdfTotal,
            'delta = fees + their tax, exactly (the gap this fix removes)');
    }

    @isTest
    static void testQuotePdf_PremiumOnly_LineBuildConvergesWithFormulaBuild() {
        setFlags(true, true);
        Ctx c = build('Q3', 13, true, false, false); // base + premium 299 only
        insertEnginePricedPackage(c);

        // Premium fee IS expressible in the stored formula surface, so the
        // line build and the formula build converge to the cent:
        // (1100 + 299) * 1.13 = 1580.87 — same numbers the warranty parity
        // suite pins for the portal payload.
        assertQuotePdfMoney(c, 1399.00, 181.87, 1580.87, true, 'premium-only line build');

        Map<String, Object> payload = readActivePackagePayload(c.app.Id);
        System.assertEquals(1399.00, payload.get('contractPremiumPriceWithoutTax'));
        System.assertEquals(181.87, payload.get('taxAmount'));
        System.assertEquals(1580.87, payload.get('contractPremiumPrice'));
    }

    @isTest
    static void testQuotePdf_OptionalOption_LineBuildIncludesOptionRetail_ApoReadConsistent() {
        setFlags(true, true);
        Ctx c = build('Q4', 13, false, false, false);
        Application_Package__c pkg = insertEnginePricedPackage(c); // base-only snapshot

        // Dealer picks an Optional option: the P4 [S] option-add writer state —
        // a priced Option LINE ITEM (retail 500 = net 400 + $100 markup, the
        // value the engine prices and carries forward). The PDF optional-
        // option parenthetical reads this line; the retired
        // Application_Package_Option__c child state no longer exists.
        Package_Option__c masterOption = new Package_Option__c(Selection_Type__c = 'Optional');
        insert masterOption;
        Database.insert(new Application_Package_Line_Item__c(
            Application_Package__c = pkg.Id,
            Name = 'Optional option',
            Line_Type__c = 'Option',
            Description__c = 'Optional option',
            Amount__c = 500.00,
            Taxable__c = true,
            Quantity__c = 1,
            Package_Option__c = masterOption.Id
        ), System.AccessLevel.SYSTEM_MODE);

        // Re-save: engine re-prices with the option (selectOptionPrices reads
        // the Option line) and rewrites the snapshot.
        restampAndSnapshot(c, pkg);

        // Base 1100 + option retail 500 = 1600 no-tax, 208 tax, 1808 total.
        assertQuotePdfMoney(c, 1600.00, 208.00, 1808.00, true, 'option line build');

        // The PDF's Optional-option parenthetical reads the priced Option LINE
        // the engine priced — retail 500 on both sides of the render.
        QuotePDFExtension ext = quotePdf(c);
        QuotePDFExtension.PackageWrapper w = ext.packageWrappersList[0];
        System.assertEquals(1, w.optionalOptions.size(), 'optional option must render');
        System.assertEquals(500.00, w.optionalOptions[0].retailPrice, 'optional-option parenthetical retail (Option line)');
        System.assertEquals('Optional option', w.optionalOptions[0].optionName, 'optional-option name (line description)');

        Map<String, Object> payload = readActivePackagePayload(c.app.Id);
        System.assertEquals(1600.00, payload.get('contractPremiumPriceWithoutTax'));
        System.assertEquals(208.00, payload.get('taxAmount'));
        System.assertEquals(1808.00, payload.get('contractPremiumPrice'));
    }

    @isTest
    static void testApplicationPdf_NoLines_RenderedKeysEqualStoredTrio() {
        setFlags(true, false);
        Ctx c = build('Q5', 13, false, false, false);
        insertEnginePricedPackage(c);

        // Legacy: the application-PDF pages merge the stored trio directly.
        assertApplicationPdfMoney(c, 1100.00, 143.00, 1243.00, false, 'app-PDF no-line build');
    }

    @isTest
    static void testApplicationPdf_FeeMatrix_RenderedKeysEqualEngineTotals() {
        setFlags(true, true);
        Ctx c = build('Q6', 13, true, true, true);
        Application_Package__c pkg = insertEnginePricedPackage(c);

        PricingEngineService.QuoteResult res = PricingEngineService.applyEnginePricing(pkg, requestFor(c, pkg));
        System.assert(res.success, 'engine pricing expected to succeed');
        assertApplicationPdfMoney(c, res.noTaxTotal, res.taxAmount, res.withTaxTotal, true,
            'app-PDF fee-matrix line build');

        Map<String, Object> payload = readActivePackagePayload(c.app.Id);
        System.assertEquals(res.noTaxTotal, payload.get('contractPremiumPriceWithoutTax'));
        System.assertEquals(res.taxAmount, payload.get('taxAmount'));
        System.assertEquals(res.withTaxTotal, payload.get('contractPremiumPrice'));
    }

    // ------------------------------------------------------------------
    // P4 flip [T]-follow-up: PDF term/plan/T&C/included-option display on
    // engine-quote PDFs (run p4-flip-t45, tag p4-t2).
    //
    // Engine-priced Application_Package records carry NO master Package__c /
    // Package_Term__c links (the create-time flow that wrote them is
    // engine-guarded off) and NO Included APO children. Pre-fix the quote PDF
    // rendered the plan header blank and term 'N/A', and the application PDFs
    // rendered an empty "Additional Options" list and no T&C box for such
    // records. The fix re-points those reads to the dealer copy links the
    // engine path DOES carry (Dealer_Package__c / Dealer_Package_Term__c ->
    // their masters, then the copy names) and, for engine-snapshot packages,
    // to the same Dealer_Package_Option__c Included rows the legacy create-
    // time flow copies into APO children, plus the master-linked T&C the
    // legacy path resolves. Master-first chains keep the legacy path
    // byte-identical (master-linked records resolve exactly as before).
    // ------------------------------------------------------------------

    private static void seedMasterTc(Ctx c, String tag) {
        // Config set EXPLICITLY: fresh Package__c rows read back ×100-scaled
        // percent defaults in this org (p4-run finding 1: 1500/5000/2000) —
        // the CommissionCalculationTrigger reads master-linked package config,
        // so the legacy-shape fixture pins real stored percents (15/50/20).
        update new Package__c(Id = c.masterPkgId,
            Terms_and_Conditions__c = 'QTC' + tag + ': default terms and conditions text.',
            Discount_Threshold_Pct__c = 15,
            Reserve_Pct__c = 50,
            Commission_Rate_Pct__c = 20,
            Reserve_Floor__c = 425);
    }

    /** Master option catalogue row: Option__c name + Package_Option__c master. */
    private static Id seedMasterOption(String tag, String suffix, String selectionType) {
        Option__c catalog = new Option__c(Name = 'QO' + tag + suffix);
        insert catalog;
        Package_Option__c master = new Package_Option__c(
            Option__c = catalog.Id,
            Selection_Type__c = selectionType);
        insert master;
        return master.Id;
    }

    /** Dealer copy of an Included option (the engine-path PDF fallback source). */
    private static void seedDealerIncludedOption(Ctx c, Id masterOptionId, String tag, String suffix,
                                                 String incText, String excText) {
        insert new Dealer_Package_Option__c(
            Dealer_Package__c = c.dealerPackageId,
            Package_Option__c = masterOptionId,
            Selection_Type__c = 'Included',
            Inclusion__c = incText,
            Exclusion__c = excText);
    }

    /** Insert an Application_Package that carries the LEGACY display shape:
     *  master links + Included APO children, no engine line set. The engine
     *  marker is stamped pre-DML only so the create-time flow (which cannot
     *  run in the test user context) terminates at its guard — the display
     *  fields under test are fixture-written exactly as the flow writes them. */
    private static Application_Package__c insertLegacyShapedPackage(Ctx c) {
        // Dealer_Package_Price__c / Dealer_Markup__c / Tax_Percentage__c are
        // the fields the create-time flow's Update_Application_Package element
        // writes on the legacy path (marker is pre-stamped so the flow backs
        // off in tests; the fixture writes the same values the flow would:
        // price = term Net_Cost 1000, markup = $100 -> retail formula 1100,
        // tax 13% -> 143 / 1243).
        Application_Package__c pkg = new Application_Package__c(
            Name = 'LAPK' + c.v.Name,
            Application__c = c.app.Id,
            Dealer__c = c.dealer.Id,
            Dealer_Package__c = c.dealerPackageId,
            Dealer_Package_Term__c = c.dt.Id,
            Package__c = c.masterPkgId,
            Package_Term__c = c.masterTermId,
            Dealer_Package_Price__c = 1000.00,
            Dealer_Markup__c = 100.00,
            Tax_Percentage__c = 13.00,
            RecordTypeId = rt('Application_Package__c', 'Extended_Limited_Warranty'),
            Active__c = true,
            Priced_By_Engine__c = true
        );
        Database.insert(pkg, System.AccessLevel.SYSTEM_MODE);
        return pkg;
    }

    @isTest
    static void testUpdateApplicationPackage_EngineRepriceWithOption_NoSObjectException() {
        // P4-flip engine-contract regression (found by LIVE verification, run
        // p4-flip-t45): with T4 ON, DealerPortalController.updateApplicationPackage
        // reached the engine seam with a package loaded WITHOUT
        // Waive_Premium_Fee__c -> SObjectException on every substantive update
        // (the seam dereferences the field). Fixed additively (field added to
        // the update path's SELECT). This test pins the real UI sequence:
        // engine quote + optional add-on, then the re-save through
        // updateApplicationPackage with a real change (deductible on) ->
        // engine re-price + snapshot rewrite, no exception.
        setFlags(true, true);
        Ctx c = build('QB', 13, false, false, false);
        update new Dealer_Package__c(Id = c.dealerPackageId, Deductable__c = 250.00);
        Application_Package__c pkg = insertEnginePricedPackage(c);

        // Dealer adds an Optional add-on — the P4 [S] writer state: a priced
        // Option LINE (retail 500) — then re-saves via the real update seam
        // with includeDeductible -> deductible 250 != 0 is a real change, so
        // the engine path executes (pre-fix: SObjectException).
        Id optMasterOption = seedMasterOption('QB', 'O', 'Optional');
        Database.insert(new Application_Package_Line_Item__c(
            Application_Package__c = pkg.Id,
            Name = 'Optional option',
            Line_Type__c = 'Option',
            Description__c = 'Optional option',
            Amount__c = 500.00,
            Taxable__c = true,
            Quantity__c = 1,
            Package_Option__c = optMasterOption
        ), System.AccessLevel.SYSTEM_MODE);

        Map<String, Object> upd = new Map<String, Object>();
        upd.put('packageId', pkg.Id);
        upd.put('selectedTermId', c.dt.Id);
        upd.put('includeDeductible', true);
        DealerPortalController.ApplicationPackageResponse updResp =
            DealerPortalController.updateApplicationPackage(upd);
        System.assert(updResp != null && updResp.success,
            'update re-save must succeed: ' + (updResp == null ? 'null' : updResp.message));

        // Engine re-price + snapshot rewrite: base 1100 + option retail 500 =
        // 1600 no-tax, 208 tax, 1808 total; deductible now 250.
        assertQuotePdfMoney(c, 1600.00, 208.00, 1808.00, true, 'update re-save line build');
        Map<String, Object> payload = readActivePackagePayload(c.app.Id);
        System.assertEquals(1600.00, payload.get('contractPremiumPriceWithoutTax'));
        System.assertEquals(208.00, payload.get('taxAmount'));
        System.assertEquals(1808.00, payload.get('contractPremiumPrice'));
        Application_Package__c stored = [SELECT Deductible__c FROM Application_Package__c WHERE Id = :pkg.Id];
        System.assertEquals(250.00, stored.Deductible__c, 'deductible change persisted');
        Boolean marker = false;
        Id pid = pkg.Id;
        for (Application_Package__c p : (List<Application_Package__c>) Database.query(
                'SELECT Priced_By_Engine__c FROM Application_Package__c WHERE Id = :pid',
                System.AccessLevel.SYSTEM_MODE)) {
            marker = p.Priced_By_Engine__c == true;
        }
        System.assertEquals(true, marker, 'still engine-priced');
    }

    @isTest
    static void testQuotePdf_EngineLineBuild_TermAndPlanRenderFromDealerLinks() {
        // Engine shape WITH the line snapshot: the [T]-follow-up display
        // re-point must render the plan/term from the dealer copy links.
        setFlags(true, true);
        Ctx c = build('Q7', 13, false, false, false);
        seedMasterTc(c, 'Q7');
        Id dpoMasterOption = seedMasterOption('Q7', 'A', 'Included');
        seedDealerIncludedOption(c, dpoMasterOption, 'Q7', 'A', 'DPO-INC-A', 'DPO-EXC-A');
        Application_Package__c pkg = insertEnginePricedPackage(c);

        // Money unchanged by the display re-point (line build 1100/143/1243).
        assertQuotePdfMoney(c, 1100.00, 143.00, 1243.00, true, 'engine line build (term re-point)');

        // The QUOTE PDF plan header + term: engine records have no master
        // links, so the re-point resolves through the dealer copy ->
        // master chain; on the synced fixture catalogue that is the SAME text
        // a legacy master-linked record renders (master plan QPKG7 / master
        // term QTRM7). Pre-fix this rendered blank / 'N/A'.
        QuotePDFExtension ext = quotePdf(c);
        QuotePDFExtension.PackageWrapper w = ext.packageWrappersList[0];
        System.assertEquals('QPKGQ7', w.packageName, 'engine quote plan header (via dealer copy master)');
        System.assertEquals('QTRMQ7', w.termName, 'engine quote term (via dealer term master)');

        // The application PDFs: DPV page merges planName/termName (dealer-
        // first, baseline); the CarLoanProtection page merges the rendered*
        // keys (master-first). Both must carry real text on the engine path,
        // and the T&C + Included-option list must render from the dealer/
        // master sources the legacy path uses.
        ApplicationPDFExtension appExt = applicationPdf(c);
        ApplicationPDFExtension.PackageWrapper aw = null;
        for (ApplicationPDFExtension.RecordTypeWrapper rtw : appExt.recordTypeWrappersList) {
            if (!rtw.packages.isEmpty()) { aw = rtw.packages[0]; }
        }
        System.assert(aw != null, 'app-PDF wrapper expected');
        // The dealer copy is sync-renamed to mirror the master name
        // (DealerPackageSyncService reconcile at insert: dp.Name = master.Name),
        // so the DPV plan name == the master plan name; the dealer TERM keeps
        // its fixture name (inserted after the reconcile).
        System.assertEquals('QPKGQ7', aw.planName, 'DPV plan name (dealer-first, sync-mirrored)');
        System.assertEquals('QDPTQ7', aw.termName, 'DPV term name (dealer-first baseline)');
        System.assertEquals('QPKGQ7', aw.renderedPlanName, 'CarLoan plan (master-first via dealer copy)');
        System.assertEquals('QTRMQ7', aw.renderedTermName, 'CarLoan term (master-first via dealer term master)');
        System.assertEquals(true, aw.hasTermsAndConditions,
            'engine contract PDF must render the T&C box');
        System.assert(aw.termsAndConditions != null
            && aw.termsAndConditions.contains('QTCQ7'), 'T&C text = the master default the legacy path resolves');
        System.assertEquals(1, aw.includedOptionNames.size(),
            'engine contract PDF must render the Included options (dealer mirror)');
        System.assertEquals('QOQ7A', aw.includedOptionNames[0],
            'included-option name = the master option the DPO row points at');
    }

    @isTest
    static void testQuotePdf_LegacyMasterLinkedNoLines_ByteIdentical() {
        // Master-linked display shape with NO line set: plan/term/T&C resolve
        // master-first byte-identically, and (P4 [S] — the APO children the
        // legacy flow copied are retired) the Included-option name list now
        // renders from the dealer mirror — the SAME Dealer_Package_Option__c
        // rows the legacy create-time flow copied into the children — on
        // every shape. Optional options stay empty (no Option lines).
        setFlags(true, false); // snapshot OFF -> no line set
        Ctx c = build('Q9', 13, false, false, false);
        seedMasterTc(c, 'Q9');
        Id dpoMasterOption = seedMasterOption('Q9', 'B', 'Included');
        seedDealerIncludedOption(c, dpoMasterOption, 'Q9', 'B', 'DPO-INC-B', 'DPO-EXC-B');
        Application_Package__c pkg = insertLegacyShapedPackage(c);

        // Money: no lines -> legacy formula build, unchanged.
        assertQuotePdfMoney(c, 1100.00, 143.00, 1243.00, false, 'legacy master-linked no-line build');

        QuotePDFExtension ext = quotePdf(c);
        QuotePDFExtension.PackageWrapper w = ext.packageWrappersList[0];
        System.assertEquals('QPKGQ9', w.packageName, 'legacy plan header == master name (byte-identical)');
        System.assertEquals('QTRMQ9', w.termName, 'legacy term == master term name (byte-identical)');
        System.assertEquals(0, w.optionalOptions.size(), 'no Option lines -> no optional options');

        ApplicationPDFExtension appExt = applicationPdf(c);
        ApplicationPDFExtension.PackageWrapper aw = null;
        for (ApplicationPDFExtension.RecordTypeWrapper rtw : appExt.recordTypeWrappersList) {
            if (!rtw.packages.isEmpty()) { aw = rtw.packages[0]; }
        }
        System.assert(aw != null, 'app-PDF wrapper expected');
        System.assertEquals('QPKGQ9', aw.renderedPlanName, 'CarLoan plan == master name (byte-identical)');
        System.assertEquals('QTRMQ9', aw.renderedTermName, 'CarLoan term == master term name (byte-identical)');
        System.assertEquals(true, aw.hasTermsAndConditions, 'T&C box renders on the legacy shape');
        System.assert(aw.termsAndConditions.contains('QTCQ9'), 'T&C via the direct master link');
        System.assertEquals(1, aw.includedOptionNames.size(),
            'Included name list renders from the dealer mirror (the flow copy source)');
        System.assertEquals('QOQ9B', aw.includedOptionNames[0],
            'render source = the dealer mirror Included option');
        System.assertEquals(0, aw.optionalOptions.size(), 'no Option lines -> no optional options');
    }

    @isTest
    static void testQuotePdf_EngineLineBuild_OptionalOption_TermAndIncludedFallbackHold() {
        // Engine shape + optional add-on: after the option is added and the
        // snapshot rewritten (live re-save order), the money includes the
        // option retail once, the term/plan display still resolves from the
        // dealer links, and the Included-option name list (dealer mirror)
        // still renders.
        setFlags(true, true);
        Ctx c = build('QA', 13, false, false, false);
        seedMasterTc(c, 'QA');
        Id dpoMasterOption = seedMasterOption('QA', 'A', 'Included');
        seedDealerIncludedOption(c, dpoMasterOption, 'QA', 'A', 'DPO-INC-A', 'DPO-EXC-A');
        Application_Package__c pkg = insertEnginePricedPackage(c);

        // Dealer adds an Optional add-on — the P4 [S] writer state: the priced
        // Option line the writer now creates — then re-saves -> engine
        // re-price + snapshot rewrite.
        Id optMasterOption = seedMasterOption('QA', 'O', 'Optional');
        Database.insert(new Application_Package_Line_Item__c(
            Application_Package__c = pkg.Id,
            Name = 'Optional option',
            Line_Type__c = 'Option',
            Description__c = 'Optional option',
            Amount__c = 500.00,
            Taxable__c = true,
            Quantity__c = 1,
            Package_Option__c = optMasterOption
        ), System.AccessLevel.SYSTEM_MODE);
        restampAndSnapshot(c, pkg);

        // Money: base 1100 + option retail 500 = 1600 / 208 / 1808 (unchanged
        // by the display re-point).
        assertQuotePdfMoney(c, 1600.00, 208.00, 1808.00, true, 'option line build (term re-point)');

        QuotePDFExtension ext = quotePdf(c);
        QuotePDFExtension.PackageWrapper w = ext.packageWrappersList[0];
        System.assertEquals('QPKGQA', w.packageName, 'engine quote plan header');
        System.assertEquals('QTRMQA', w.termName, 'engine quote term');
        System.assertEquals(1, w.optionalOptions.size(), 'optional option renders with retail');
        System.assertEquals(500.00, w.optionalOptions[0].retailPrice,
            'optional-option parenthetical retail (Option line)');

        ApplicationPDFExtension appExt = applicationPdf(c);
        ApplicationPDFExtension.PackageWrapper aw = null;
        for (ApplicationPDFExtension.RecordTypeWrapper rtw : appExt.recordTypeWrappersList) {
            if (!rtw.packages.isEmpty()) { aw = rtw.packages[0]; }
        }
        System.assert(aw != null, 'app-PDF wrapper expected');
        System.assertEquals(true, aw.hasTermsAndConditions, 'T&C renders after the option add');
        System.assertEquals(1, aw.includedOptionNames.size(), 'Included name list still renders');
        System.assertEquals('QOQAA', aw.includedOptionNames[0], 'included-option name from the dealer mirror');
    }
}