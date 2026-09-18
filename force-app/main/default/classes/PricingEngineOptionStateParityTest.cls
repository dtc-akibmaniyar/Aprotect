/**
 * PricingEngineOptionStateParityTest
 *
 * P4 [S] unit (b) parity evidence — option state lives on the package's priced
 * Option LINE ITEMS (change-plan §11 P4 [S]). Decision 2026-09-06 option (b):
 * source-level + Apex payload-parity evidence is the accepted regression
 * standard.
 *
 * WHY THIS SUITE: the engine priced optional selections from Optional
 * Application_Package_Option__c children (APO) and the S5 option flows wrote
 * those children. P4 [S] retires APO: the option-add writers now create
 * priced Option LINE ITEMS (Line_Type__c = 'Option', Amount__c = the dealer-
 * option mirror's priced retail — the value the engine prices and carries
 * forward, R6), and the engine reads ONLY those lines
 * (PricingEngineService.selectOptionPrices precedence 1; the [S TRANSITION]
 * APO fallback was removed in this unit). Application_Package_Option__c is
 * never read or written by the engine or the option flows anymore.
 *
 * What the tests prove (the pinned cases):
 *   - An option at dealer retail 250 (net 200 + $50 markup) @13% adds exactly
 *     250 pre-tax / 32.50 tax / 282.50 with-tax over the base quote
 *     (1100 / 143 / 1243 -> 1350 / 175.50 / 1525.50), priced from the Option
 *     line the writer creates: engine result, stored formula surface and the
 *     portal payload all agree (stored = displayed), and the re-price of an
 *     unchanged quote is byte-identical (R6).
 *   - Writer dedupe: adding the same option twice produces one line; removal
 *     deletes the line and the re-price returns to the base quote.
 *   - The real S5 round trip (DealerPortalController.updateAdditionalOptions
 *     + getExistingAdditionalOptions): creates an Option line, the reader
 *     returns the line-based DTOs with the removal contract intact, and the
 *     engine re-prices the quote through the line-item state
 *     (1350 / 175.50 / 1525.50).
 *   - A pre-tax dealer price override suppresses option state entirely:
 *     999 / 129.87 / 1128.87 on every surface, no Option line (override
 *     full-key parity).
 *
 * TEST CONTEXT FACTS (same as the [L]/[T] parity suites): every
 * Application_Package insert is engine-stamped (Priced_By_Engine__c) BEFORE
 * the DML. Option lines are inserted in SYSTEM_MODE (the P4 line-item fields
 * carry no portal FLS yet — the same mode the engine snapshot writes use).
 * The pre-[S] APO child states the unit-(a)/(b) runs pinned (child-only
 * negative pin, dual line+child dedupe) are dropped with the P4 [S] object
 * delete — the object no longer exists org-side, so those states cannot
 * occur; the line-state contract above is the only option state left.
 */
@isTest
private class PricingEngineOptionStateParityTest {

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

    private static Vehicle__c vehicle(String name, Make__c m, Model__c mo) {
        Vehicle__c v = new Vehicle__c(Name = name, Make_Lookup__c = m.Id, Model_Lookup__c = mo.Id,
            Fuel_Type__c = 'Gas', Usage_Type__c = 'Personal Use');
        insert v;
        return v;
    }

    private class Ctx {
        public Account dealer;
        public Vehicle__c v;
        public Id dealerPackageId;
        public Dealer_Package_Term__c dt;
        public Application__c app;
    }

    /** Full context: catalogue + dealer mirror + Application (base quote shape:
     *  wholesale 1000 + $100 markup -> base retail 1100, no fee schedules). */
    private static Ctx build(String tag) {
        Tax__c tax = taxRegion('S3' + tag, 13);
        Account d = dealer('S3D' + tag, tax);
        Make__c mk = make('S3MK' + tag);
        Model__c mo = model(mk, 'S3MD' + tag);
        Vehicle__c v = vehicle('S3V' + tag, mk, mo);

        Package_Group__c grp = new Package_Group__c(Name = 'S3GRP' + tag, Active__c = true);
        insert grp;
        Package__c pkg = new Package__c(Name = 'S3PKG' + tag, Package_Group__c = grp.Id,
            RecordTypeId = rt('Package__c', 'Extended_Limited_Warranty'), Is_Active__c = true);
        insert pkg;
        Package_Tier__c tier = new Package_Tier__c(Name = 'S3TIR' + tag, Package__c = pkg.Id);
        insert tier;
        Package_Term__c mt = new Package_Term__c(Name = 'S3TRM' + tag, Package_Tier__c = tier.Id, Price__c = 1000.00);
        insert mt;

        Dealer_Package__c dp = new Dealer_Package__c(Name = 'S3DP' + tag, Dealer__c = d.Id,
            Package__c = pkg.Id, RecordTypeId = rt('Dealer_Package__c', 'Extended_Limited_Warranty'));
        insert dp;
        Dealer_Package_Term__c dt = new Dealer_Package_Term__c(Name = 'S3DPT' + tag,
            Dealer_Package__c = dp.Id, Package_Term__c = mt.Id,
            Original_Package_Term_Cost__c = 1000.00, Markup__c = 100.00, Markup_Type__c = '$');
        insert dt;

        Ctx c = new Ctx();
        c.dealer = d; c.v = v; c.dealerPackageId = dp.Id; c.dt = dt;
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
            Name = 'S3APK' + c.v.Name,
            Application__c = c.app.Id,
            Dealer__c = c.dealer.Id,
            Dealer_Package__c = c.dealerPackageId,
            Dealer_Package_Term__c = c.dt.Id,
            RecordTypeId = rt('Application_Package__c', 'Extended_Limited_Warranty'),
            Active__c = true
        );
        PricingEngineService.QuoteResult res = PricingEngineService.applyEnginePricing(pkg, requestFor(c, pkg));
        System.assert(res.success, 'engine pricing expected to succeed: ' + res.errors);
        Database.insert(pkg, System.AccessLevel.SYSTEM_MODE);
        Boolean written = ApplicationSnapshotService.writeSnapshot(pkg.Id,
            PricingEngineService.applyEnginePricing(pkg, requestFor(c, pkg)));
        System.assertEquals(true, written, 'snapshot must be written for the parity fixture');
        return pkg;
    }

    private static PricingEngineService.QuoteRequest requestFor(Ctx c, Application_Package__c pkg) {
        return requestFor(c, pkg, null);
    }

    private static PricingEngineService.QuoteRequest requestFor(Ctx c, Application_Package__c pkg, Decimal overrideAmt) {
        PricingEngineService.QuoteRequest req = new PricingEngineService.QuoteRequest();
        req.dealerId = c.dealer.Id;
        req.vehicleId = c.v.Id;
        req.dealerPackageId = c.dealerPackageId;
        req.dealerTermId = c.dt.Id;
        req.applicationPackageId = pkg.Id;
        req.asOfDate = Date.newInstance(2026, 9, 3);
        req.dealerPriceOverride = overrideAmt;
        return req;
    }

    /**
     * Seed the Optional option catalogue row + dealer mirror the S5 option
     * flows select from. Formula results on the mirror: Net_Cost 200
     * (Original 200, no discount), Retail_Price 250 (+ $50 markup).
     * Returns the master Package_Option id.
     */
    private static Id seedOptionalOption(Ctx c, String tag) {
        Option__c catalog = new Option__c(Name = 'S3O' + tag);
        insert catalog;
        Package_Option__c master = new Package_Option__c(
            Option__c = catalog.Id,
            Selection_Type__c = 'Optional');
        insert master;
        Dealer_Package_Option__c dpo = new Dealer_Package_Option__c(
            Dealer_Package__c = c.dealerPackageId,
            Package_Option__c = master.Id,
            Option__c = catalog.Id,
            Selection_Type__c = 'Optional',
            Original_Package_Option_Price__c = 200.00,
            Dealer_Markup__c = 50.00,
            Markup_Type__c = '$'
        );
        insert dpo;
        return master.Id;
    }

    /** Writer-shaped Option line (the unit-(b) option-add state): amount =
     *  the dealer-option mirror's priced retail. SYSTEM_MODE insert (no
     *  portal FLS on line-item fields). */
    private static void addOptionLine(Ctx c, Application_Package__c pkg, Id masterId) {
        Dealer_Package_Option__c dpo = [
            SELECT Id, Retail_Price__c, Option__r.Name FROM Dealer_Package_Option__c
            WHERE Dealer_Package__c = :c.dealerPackageId AND Package_Option__c = :masterId LIMIT 1
        ];
        String optDesc = 'Option';
        if (dpo.Option__r != null && String.isNotBlank(dpo.Option__r.Name)) {
            optDesc = dpo.Option__r.Name;
        }
        String optName = optDesc;
        if (optName.length() > 60) {
            optName = optName.substring(0, 60);
        }
        Database.insert(new Application_Package_Line_Item__c(
            Application_Package__c = pkg.Id,
            Name = optName,
            Line_Type__c = 'Option',
            Description__c = optDesc,
            Amount__c = PricingEngineService.money(dpo.Retail_Price__c),
            Taxable__c = true,
            Quantity__c = 1,
            Package_Option__c = masterId
        ), System.AccessLevel.SYSTEM_MODE);
    }

    /** Engine re-price + DML of the stamped record + snapshot rewrite (the
     *  real re-save order). */
    private static PricingEngineService.QuoteResult restampAndSnapshot(Ctx c, Application_Package__c pkg) {
        return restampAndSnapshot(c, pkg, null);
    }

    private static PricingEngineService.QuoteResult restampAndSnapshot(Ctx c, Application_Package__c pkg, Decimal overrideAmt) {
        PricingEngineService.QuoteResult res = PricingEngineService.applyEnginePricing(pkg, requestFor(c, pkg, overrideAmt));
        System.assert(res.success, 'restamp expected to succeed: ' + res.errors);
        Database.update(pkg, System.AccessLevel.SYSTEM_MODE);
        Boolean written = ApplicationSnapshotService.writeSnapshot(pkg.Id, res);
        System.assertEquals(true, written, 'snapshot rewrite must succeed');
        return res;
    }

    private static Integer optionLineCount(PricingEngineService.QuoteResult res) {
        Integer n = 0;
        for (PricingEngineService.QuoteLine l : res.lines) {
            if (PricingEngineService.LT_OPTION.equals(l.lineType)) {
                n++;
                System.assertEquals(250.00, l.amount, 'option line amount');
                System.assertNotEquals(null, l.provenanceOptionId, 'option provenance master');
            }
        }
        return n;
    }

    private static Integer persistedOptionLineCount(Id pkgId) {
        // SYSTEM_MODE: the P4 line-item fields carry no portal FLS yet (the
        // same mode every line-item reader uses) — a plain query in the test
        // user context cannot see Line_Type__c.
        return (Integer) Database.countQueryWithBinds(
            'SELECT COUNT() FROM Application_Package_Line_Item__c' +
            ' WHERE Application_Package__c = :pkgId AND Line_Type__c = \'Option\'',
            new Map<String, Object>{ 'pkgId' => pkgId },
            System.AccessLevel.SYSTEM_MODE);
    }

    /** The warranty active-package payload money keys (portal read). */
    private static Map<String, Object> readActivePackagePayload(Id appId) {
        DealerPortalController.ApplicationPackageResponse response =
            DealerPortalController.getActiveApplicationPackageByRecordType(appId, 'Extended_Limited_Warranty');
        System.assert(response != null && response.success, 'active-package read expected to succeed: '
            + (response == null ? 'null' : response.message));
        return response.data;
    }

    // ------------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------------

    /**
     * THE pinned case: an option at dealer retail 250 (net 200 + $50 markup)
     * @13% priced from the Option line the writer creates adds exactly
     * 250 pre-tax / 32.50 tax / 282.50 with-tax over the base quote
     * (1100 / 143 / 1243 -> 1350 / 175.50 / 1525.50). The re-price of an
     * unchanged quote is byte-identical (R6); stored formula surface == engine
     * == line sums == portal payload (stored = displayed). Removing the line
     * returns the quote to the base totals.
     */
    @isTest
    static void testOptionOnLine_PricedByteIdentical_DeltaAndPayloadPinned() {
        setFlags(true, true);
        Ctx c = build('B1');
        Application_Package__c pkg = insertEnginePricedPackage(c); // base-only quote
        Id masterId = seedOptionalOption(c, 'B1');

        // Base quote pinned first (1100 / 143 / 1243).
        PricingEngineService.QuoteResult base = PricingEngineService.applyEnginePricing(pkg, requestFor(c, pkg));
        System.assertEquals(1100.00, base.noTaxTotal);
        System.assertEquals(143.00, base.taxAmount);
        System.assertEquals(1243.00, base.withTaxTotal);

        // Writer state: the option-add flow inserts the priced Option line
        // (amount = mirror retail 250). The engine folds it at the next
        // re-save: totals move by exactly the option + its tax.
        addOptionLine(c, pkg, masterId);
        PricingEngineService.QuoteResult priced = restampAndSnapshot(c, pkg);
        System.assertEquals(1350.00, priced.noTaxTotal, 'no-tax');
        System.assertEquals(175.50, priced.taxAmount, 'tax');
        System.assertEquals(1525.50, priced.withTaxTotal, 'with-tax');
        System.assertEquals(1, optionLineCount(priced), 'exactly one option line');
        System.assertEquals(200.00, priced.addOnsNet, 'addOnsNet from the mirror');
        System.assertEquals(50.00, priced.addOnsMarkup, 'addOnsMarkup');
        System.assertEquals(250.00, priced.addOnsRetail, 'addOnsRetail');

        // The add-on delta over the base quote: 250 / 32.50 / 282.50.
        System.assertEquals(250.00, PricingEngineService.money(priced.noTaxTotal - base.noTaxTotal), 'add-on pre-tax delta');
        System.assertEquals(32.50, PricingEngineService.money(priced.taxAmount - base.taxAmount), 'add-on tax delta');
        System.assertEquals(282.50, PricingEngineService.money(priced.withTaxTotal - base.withTaxTotal), 'add-on with-tax delta');

        // Byte-identical re-price (R6) of the unchanged quote.
        PricingEngineService.QuoteResult again = restampAndSnapshot(c, pkg);
        System.assertEquals(priced.noTaxTotal, again.noTaxTotal);
        System.assertEquals(priced.taxAmount, again.taxAmount);
        System.assertEquals(priced.withTaxTotal, again.withTaxTotal);
        System.assertEquals(1, persistedOptionLineCount(pkg.Id), 'snapshot kept one Option line');

        // Stored formula surface == engine == payload (stored = displayed).
        Application_Package__c stored = [SELECT Dealer_Package_Retail_Price__c, Add_Ons_Retail_Price__c,
                                                Contract_Premium_Price_Without_Tax__c, Tax_Amount__c,
                                                Contract_Premium_Price__c
                                         FROM Application_Package__c WHERE Id = :pkg.Id];
        System.assertEquals(1100.00, stored.Dealer_Package_Retail_Price__c, 'stored base retail');
        System.assertEquals(250.00, stored.Add_Ons_Retail_Price__c, 'stored add-ons retail (formula)');
        System.assertEquals(1350.00, stored.Contract_Premium_Price_Without_Tax__c, 'stored no-tax formula');
        System.assertEquals(175.50, stored.Tax_Amount__c, 'stored tax formula');
        System.assertEquals(1525.50, stored.Contract_Premium_Price__c, 'stored with-tax formula');
        Map<String, Object> payload = readActivePackagePayload(c.app.Id);
        System.assertEquals(1350.00, payload.get('contractPremiumPriceWithoutTax'), 'payload no-tax == line sum');
        System.assertEquals(175.50, payload.get('taxAmount'), 'payload tax == line sum');
        System.assertEquals(1525.50, payload.get('contractPremiumPrice'), 'payload with-tax == line sum');
    }

    /**
     * Override full-key parity (999 / 129.87 / 1128.87 @13%): a pre-tax
     * dealer price override suppresses option state entirely — with an Option
     * line on the package, the override quote contains no Option line and no
     * add-on money on ANY surface (engine result, stored formula build,
     * rewritten line set, portal payload).
     */
    @isTest
    static void testOverrideFullKeyParity_OptionStateSuppressed() {
        setFlags(true, true);
        Ctx c = build('B4');
        Application_Package__c pkg = insertEnginePricedPackage(c);
        Id masterId = seedOptionalOption(c, 'B4');
        addOptionLine(c, pkg, masterId);
        PricingEngineService.QuoteResult priced = restampAndSnapshot(c, pkg);
        System.assertEquals(1350.00, priced.noTaxTotal, 'precondition: option priced in');
        System.assertEquals(1, persistedOptionLineCount(pkg.Id), 'precondition: Option line persisted');

        PricingEngineService.QuoteResult over = restampAndSnapshot(c, pkg, 999.00);
        System.assertEquals(999.00, over.noTaxTotal, 'override replaces the whole price');
        System.assertEquals(129.87, over.taxAmount, '13% of 999');
        System.assertEquals(1128.87, over.withTaxTotal);
        System.assertEquals(0, over.addOnsRetail, 'no add-on money under the override');
        System.assertEquals(0, optionLineCount(over), 'no Option line under the override');

        System.assertEquals(0, persistedOptionLineCount(pkg.Id), 'Option line dropped by the override snapshot');
        Application_Package__c stored = [SELECT Contract_Premium_Price_Without_Tax__c, Tax_Amount__c,
                                                Contract_Premium_Price__c
                                         FROM Application_Package__c WHERE Id = :pkg.Id];
        System.assertEquals(999.00, stored.Contract_Premium_Price_Without_Tax__c, 'stored no-tax == override');
        System.assertEquals(129.87, stored.Tax_Amount__c, 'stored tax == override tax');
        System.assertEquals(1128.87, stored.Contract_Premium_Price__c, 'stored with-tax == override total');
        Map<String, Object> payload = readActivePackagePayload(c.app.Id);
        System.assertEquals(999.00, payload.get('contractPremiumPriceWithoutTax'));
        System.assertEquals(129.87, payload.get('taxAmount'));
        System.assertEquals(1128.87, payload.get('contractPremiumPrice'));
    }

    /**
     * The real S5 round trip (warranty-tab option add/remove through
     * DealerPortalController): updateAdditionalOptions creates an Option
     * line; the reader (getExistingAdditionalOptions) returns the line-based
     * DTOs with the removal contract (Id = the dealer option); the engine
     * re-prices the quote through the line-item state
     * (1350 / 175.50 / 1525.50); removal deletes the line and the re-price
     * returns to the base quote.
     */
    @isTest
    static void testWriterRoundTrip_AddRemove_ThroughLineItems_NoApoChildren() {
        setFlags(true, true);
        Ctx c = build('B5');
        Application_Package__c pkg = insertEnginePricedPackage(c);
        Id masterId = seedOptionalOption(c, 'B5');
        Dealer_Package_Option__c dpo = [
            SELECT Id FROM Dealer_Package_Option__c
            WHERE Dealer_Package__c = :c.dealerPackageId AND Package_Option__c = :masterId LIMIT 1
        ];

        // ADD via the real writer (the exact optionsData shape the LWC sends).
        DealerPortalController.AdditionalOptionsResponse addResp =
            DealerPortalController.updateAdditionalOptions(new Map<String, Object>{
                'applicationPackageId' => pkg.Id,
                'applicationId' => c.app.Id,
                'optionsToAdd' => new List<String>{ dpo.Id },
                'optionsToRemove' => new List<String>()
            });
        System.assertEquals(true, addResp.success, 'option add must succeed: ' + addResp.message);
        System.assertEquals(1, persistedOptionLineCount(pkg.Id), 'the writer creates one Option line');

        // Reader: line-based DTOs, removal contract intact (Id = DPO id).
        DealerPortalController.AdditionalOptionsResponse readResp =
            DealerPortalController.getExistingAdditionalOptions(String.valueOf(pkg.Id));
        System.assertEquals(true, readResp.success, 'reader must succeed');
        System.assertEquals(1, readResp.data.size(), 'one existing option');
        System.assertEquals(dpo.Id, readResp.data[0].Id, 'removal id = the dealer option (LWC contract)');
        System.assertEquals(250.00, readResp.data[0].retailPrice, 'priced retail from the line');
        System.assertEquals('S3OB5', readResp.data[0].optionName, 'option name via the master catalogue');

        // Engine re-price through the line-item state: option priced once.
        PricingEngineService.QuoteResult res = restampAndSnapshot(c, pkg);
        System.assertEquals(1350.00, res.noTaxTotal, 'option-add flow prices through the line state');
        System.assertEquals(175.50, res.taxAmount);
        System.assertEquals(1525.50, res.withTaxTotal);
        System.assertEquals(1, optionLineCount(res));

        // REMOVE via the real writer (the option id the LWC collected from
        // the reader DTOs).
        DealerPortalController.AdditionalOptionsResponse rmResp =
            DealerPortalController.updateAdditionalOptions(new Map<String, Object>{
                'applicationPackageId' => pkg.Id,
                'applicationId' => c.app.Id,
                'optionsToAdd' => new List<String>(),
                'optionsToRemove' => new List<String>{ dpo.Id }
            });
        System.assertEquals(true, rmResp.success, 'option removal must succeed: ' + rmResp.message);
        System.assertEquals(0, persistedOptionLineCount(pkg.Id), 'the line is deleted');
        PricingEngineService.QuoteResult back = restampAndSnapshot(c, pkg);
        System.assertEquals(1100.00, back.noTaxTotal, 'quote returns to the base totals');
        System.assertEquals(143.00, back.taxAmount);
        System.assertEquals(1243.00, back.withTaxTotal);
    }

    /**
     * Writer dedupe: adding the same option twice produces exactly one line
     * (the writer skips masters already on the quote), so the engine can
     * never see a duplicate line to double-price.
     */
    @isTest
    static void testWriterDedupe_SameOptionAddedTwice_SingleLine() {
        setFlags(true, true);
        Ctx c = build('B6');
        Application_Package__c pkg = insertEnginePricedPackage(c);
        Id masterId = seedOptionalOption(c, 'B6');
        Dealer_Package_Option__c dpo = [
            SELECT Id FROM Dealer_Package_Option__c
            WHERE Dealer_Package__c = :c.dealerPackageId AND Package_Option__c = :masterId LIMIT 1
        ];

        Map<String, Object> addData = new Map<String, Object>{
            'applicationPackageId' => pkg.Id,
            'applicationId' => c.app.Id,
            'optionsToAdd' => new List<String>{ dpo.Id },
            'optionsToRemove' => new List<String>()
        };
        DealerPortalController.AdditionalOptionsResponse first =
            DealerPortalController.updateAdditionalOptions(addData);
        System.assertEquals(true, first.success, 'first add must succeed');
        DealerPortalController.AdditionalOptionsResponse second =
            DealerPortalController.updateAdditionalOptions(addData);
        System.assertEquals(true, second.success, 'duplicate add must succeed (no-op)');
        System.assertEquals(1, persistedOptionLineCount(pkg.Id), 'one line after two identical adds');

        PricingEngineService.QuoteResult res = restampAndSnapshot(c, pkg);
        System.assertEquals(1350.00, res.noTaxTotal, 'priced once');
        System.assertEquals(1, optionLineCount(res), 'one option line in the result');
        System.assertEquals(250.00, res.addOnsRetail);
    }
}