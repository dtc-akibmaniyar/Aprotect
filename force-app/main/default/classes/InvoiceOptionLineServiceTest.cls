/**
 * InvoiceOptionLineServiceTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Covers InvoiceOptionLineService + InvoiceOptionLineTrigger:
 *   • one gross line per chargeable option (retail × (1 + tax%), 2dp HALF_UP)
 *   • Included / $0 options excluded
 *   • Add_Ons_Price__c already carrying the option money → package excluded
 *   • idempotent re-run (no duplicates)
 *   • invoice with no options unaffected
 *   • null Application / application with no packages → safe no-op
 *   • blank option description → "Option (Optional)"
 *   • non-Option line types ignored
 *   • bulk (several invoices at once)
 *   • helper coverage (optionLabel / normalize / money)
 */
@isTest
private class InvoiceOptionLineServiceTest {

    // ── Fixtures ────────────────────────────────────────────────────────────

    /** Dealer → Application → package hierarchy → Application_Package__c. */
    private static Map<String, SObject> buildChain(Decimal taxPct) {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Package__c pkg = TestDataFactory.createPackage('Extended_Limited_Warranty', true);
        // Keep CommissionCalculationTrigger happy (sandbox package defaults trip it).
        pkg.Commission_Rate_Pct__c    = 20;
        pkg.Reserve_Pct__c            = 50;
        pkg.Discount_Threshold_Pct__c = 15;
        update pkg;

        Package_Term__c        srcTerm    = TestDataFactory.createPackageTerm(pkg.Id, null, true);
        Dealer_Package__c      dealerPkg  = TestDataFactory.createDealerPackage(
                                                dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true);
        Dealer_Package_Term__c dealerTerm = TestDataFactory.createDealerPackageTerm(
                                                dealerPkg.Id, srcTerm.Id, null, true);
        Application_Package__c appPkg     = TestDataFactory.createApplicationPackage(
                                                app.Id, dealerPkg.Id, dealerTerm.Id, dealer.Id,
                                                'Extended_Limited_Warranty', 1500.00, taxPct, true);
        return new Map<String, SObject>{
            'dealer'      => dealer,
            'application' => app,
            'appPackage'  => appPkg
        };
    }

    /** Inserts one priced Option line (SYSTEM_MODE — the field is not portal-writable). */
    private static void addOption(Id pkgId, String name, Decimal retail, Integer sortOrder) {
        addLine(pkgId, 'Option', name, retail, sortOrder);
    }

    private static void addLine(Id pkgId, String lineType, String name, Decimal amount, Integer sortOrder) {
        Application_Package_Line_Item__c line = new Application_Package_Line_Item__c(
            Application_Package__c = pkgId,
            Name                   = name,
            Line_Type__c           = lineType,
            Description__c         = name,
            Amount__c              = amount,
            Taxable__c             = true,
            Quantity__c            = 1,
            Sort_Order__c          = sortOrder
        );
        Database.insert(line, System.AccessLevel.SYSTEM_MODE);
    }

    private static Invoice__c newInvoice(Id applicationId) {
        return new Invoice__c(
            Application__c      = applicationId,
            Status__c           = 'Due',
            Amount__c           = 1.00,
            Invoice_Due_Date__c = Date.today().addDays(30)
        );
    }

    private static List<Invoice_Line_Item__c> standaloneLines(Id invoiceId) {
        return [
            SELECT Id, Name, Description__c, Application_Package__c,
                   Repair_Charge_Amount__c, Amount__c, Status__c
            FROM Invoice_Line_Item__c
            WHERE Invoice__c = :invoiceId
              AND Application_Package__c = null
            ORDER BY Name
        ];
    }

    // ── Chargeable options ──────────────────────────────────────────────────

    @isTest
    static void createsOneGrossLinePerChargeableOption() {
        Map<String, SObject>   chain  = buildChain(5.00);
        Application__c         app    = (Application__c)         chain.get('application');
        Application_Package__c appPkg = (Application_Package__c) chain.get('appPackage');

        // Source spelling preserved deliberately ("Air Conditoning").
        addOption(appPkg.Id, 'Air Conditoning', 100.00, 1);
        addOption(appPkg.Id, 'Rust Proofing',   200.00, 2);

        Invoice__c inv = newInvoice(app.Id);

        Test.startTest();
        insert inv;
        Test.stopTest();

        List<Invoice_Line_Item__c> lines = standaloneLines(inv.Id);
        System.assertEquals(2, lines.size(), 'one invoice line per chargeable option');

        Map<String, Invoice_Line_Item__c> byDesc = new Map<String, Invoice_Line_Item__c>();
        for (Invoice_Line_Item__c li : lines) {
            byDesc.put(li.Description__c, li);
        }

        Invoice_Line_Item__c ac = byDesc.get('Air Conditoning (Optional)');
        System.assertNotEquals(null, ac, 'label carries the "(Optional)" suffix');
        System.assertEquals(null, ac.Application_Package__c,
            'Application_Package__c must stay null (no renderer double count)');
        System.assertEquals('Due', ac.Status__c, 'option line starts Due');
        System.assertEquals('Air Conditoning (Optional)', ac.Name, 'Name mirrors the description');
        // 100 × 1.05 = 105.00
        System.assertEquals(105.00, ac.Repair_Charge_Amount__c, 'gross = retail × (1 + tax%)');
        System.assertEquals(105.00, ac.Amount__c,
            'Amount__c falls back to Repair_Charge_Amount__c for a null-package line');

        Invoice_Line_Item__c rp = byDesc.get('Rust Proofing (Optional)');
        System.assertNotEquals(null, rp, 'second option billed');
        System.assertEquals(210.00, rp.Repair_Charge_Amount__c, '200 × 1.05 = 210.00');
    }

    @isTest
    static void includedAndZeroOptionsExcluded() {
        Map<String, SObject>   chain  = buildChain(13.00);
        Application__c         app    = (Application__c)         chain.get('application');
        Application_Package__c appPkg = (Application_Package__c) chain.get('appPackage');

        addOption(appPkg.Id, 'Included Item', 0.00, 1);      // Included / $0
        addOption(appPkg.Id, 'Paid Item',   100.00, 2);

        Invoice__c inv = newInvoice(app.Id);

        Test.startTest();
        insert inv;
        Test.stopTest();

        List<Invoice_Line_Item__c> lines = standaloneLines(inv.Id);
        System.assertEquals(1, lines.size(), 'only the priced option is billed');
        System.assertEquals('Paid Item (Optional)', lines[0].Description__c,
            'the $0 option is excluded');
        System.assertEquals(113.00, lines[0].Repair_Charge_Amount__c, '100 × 1.13 = 113.00');
    }

    @isTest
    static void addOnsAlreadyBilledPackageExcluded() {
        Map<String, SObject>   chain  = buildChain(5.00);
        Application__c         app    = (Application__c)         chain.get('application');
        Application_Package__c appPkg = (Application_Package__c) chain.get('appPackage');

        // Add_Ons_Price__c already carries the full option money → nothing to bill.
        appPkg.Add_Ons_Price__c = 100.00;
        update appPkg;

        addOption(appPkg.Id, 'Air Conditoning', 100.00, 1);

        Invoice__c inv = newInvoice(app.Id);

        Test.startTest();
        insert inv;
        Test.stopTest();

        System.assertEquals(0, standaloneLines(inv.Id).size(),
            'Add_Ons_Price__c covering the option money means it is already billed');
    }

    @isTest
    static void addOnsGreaterThanRetailExcluded_floorZero() {
        Map<String, SObject>   chain  = buildChain(5.00);
        Application__c         app    = (Application__c)         chain.get('application');
        Application_Package__c appPkg = (Application_Package__c) chain.get('appPackage');

        appPkg.Add_Ons_Price__c = 80.00;   // > the 50 retail
        update appPkg;
        addOption(appPkg.Id, 'Small Option', 50.00, 1);

        Invoice__c inv = newInvoice(app.Id);

        Test.startTest();
        insert inv;
        Test.stopTest();

        System.assertEquals(0, standaloneLines(inv.Id).size(),
            'unbilled = Σretail − Add_Ons floors at 0 → nothing billed');
    }

    @isTest
    static void grossRoundsHalfUp() {
        Map<String, SObject>   chain  = buildChain(5.00);
        Application__c         app    = (Application__c)         chain.get('application');
        Application_Package__c appPkg = (Application_Package__c) chain.get('appPackage');

        addOption(appPkg.Id, 'Odd Priced', 33.33, 1);   // 33.33 × 1.05 = 34.9965 → 35.00

        Invoice__c inv = newInvoice(app.Id);

        Test.startTest();
        insert inv;
        Test.stopTest();

        List<Invoice_Line_Item__c> lines = standaloneLines(inv.Id);
        System.assertEquals(1, lines.size(), 'one line');
        System.assertEquals(35.00, lines[0].Repair_Charge_Amount__c,
            '34.9965 rounds HALF_UP to 2dp → 35.00');
    }

    // ── Idempotency ─────────────────────────────────────────────────────────

    @isTest
    static void reRunIsIdempotent() {
        Map<String, SObject>   chain  = buildChain(5.00);
        Application__c         app    = (Application__c)         chain.get('application');
        Application_Package__c appPkg = (Application_Package__c) chain.get('appPackage');

        addOption(appPkg.Id, 'Air Conditoning', 100.00, 1);
        addOption(appPkg.Id, 'Rust Proofing',   200.00, 2);

        Invoice__c inv = newInvoice(app.Id);

        Test.startTest();
        insert inv;
        // The future backfill drives the same public entry point — must not double-add.
        InvoiceOptionLineService.seedForInvoices(new List<Invoice__c>{
            [SELECT Id, Application__c FROM Invoice__c WHERE Id = :inv.Id]
        });
        InvoiceOptionLineService.seedForInvoices(new List<Invoice__c>{
            [SELECT Id, Application__c FROM Invoice__c WHERE Id = :inv.Id]
        });
        Test.stopTest();

        System.assertEquals(2, standaloneLines(inv.Id).size(),
            're-running the service adds no duplicates');
    }

    // ── Non-option / no-op cases ────────────────────────────────────────────

    @isTest
    static void nonOptionLineTypesIgnored() {
        Map<String, SObject>   chain  = buildChain(13.00);
        Application__c         app    = (Application__c)         chain.get('application');
        Application_Package__c appPkg = (Application_Package__c) chain.get('appPackage');

        addLine(appPkg.Id, 'Base_Coverage', 'Base_Coverage', 1500.00, 0);
        addLine(appPkg.Id, 'Diesel_Fee',    'Diesel_Fee',      200.00, 3);
        addLine(appPkg.Id, 'Tax',           'Tax',             280.00, 5);
        addOption(appPkg.Id, 'Air Conditoning', 100.00, 6);

        Invoice__c inv = newInvoice(app.Id);

        Test.startTest();
        insert inv;
        Test.stopTest();

        List<Invoice_Line_Item__c> lines = standaloneLines(inv.Id);
        System.assertEquals(1, lines.size(), 'only the Option line is billed');
        System.assertEquals('Air Conditoning (Optional)', lines[0].Description__c, 'the option');
    }

    @isTest
    static void invoiceWithoutOptionsUnaffected() {
        Map<String, SObject>   chain  = buildChain(5.00);
        Application__c         app    = (Application__c)         chain.get('application');
        Application_Package__c appPkg = (Application_Package__c) chain.get('appPackage');

        addLine(appPkg.Id, 'Base_Coverage', 'Base_Coverage', 1500.00, 0);

        Invoice__c inv = newInvoice(app.Id);

        Test.startTest();
        insert inv;
        Test.stopTest();

        System.assertEquals(0, standaloneLines(inv.Id).size(),
            'a package with no option lines adds nothing');
    }

    @isTest
    static void blankOptionDescriptionFallsBackToOptionLabel() {
        Map<String, SObject>   chain  = buildChain(5.00);
        Application__c         app    = (Application__c)         chain.get('application');
        Application_Package__c appPkg = (Application_Package__c) chain.get('appPackage');

        addOption(appPkg.Id, null, 40.00, 1);   // blank description

        Invoice__c inv = newInvoice(app.Id);

        Test.startTest();
        insert inv;
        Test.stopTest();

        List<Invoice_Line_Item__c> lines = standaloneLines(inv.Id);
        System.assertEquals(1, lines.size(), 'one line');
        System.assertEquals('Option (Optional)', lines[0].Description__c,
            'blank option name falls back to "Option"');
        System.assertEquals(42.00, lines[0].Repair_Charge_Amount__c, '40 × 1.05 = 42.00');
    }

    @isTest
    static void nullApplicationInvoiceSafe() {
        Invoice__c inv = new Invoice__c(
            Status__c           = 'Due',
            Amount__c           = 500.00,
            Invoice_Due_Date__c = Date.today().addDays(30)
        );

        Test.startTest();
        insert inv;
        Test.stopTest();

        System.assertEquals(0, standaloneLines(inv.Id).size(),
            'an invoice with no Application__c is a safe no-op');
    }

    @isTest
    static void applicationWithoutPackagesSafe() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);
        Invoice__c     inv    = newInvoice(app.Id);

        Test.startTest();
        insert inv;
        Test.stopTest();

        System.assertEquals(0, standaloneLines(inv.Id).size(),
            'an application with no packages is a safe no-op');
    }

    @isTest
    static void emptyListIsNoOp() {
        Test.startTest();
        InvoiceOptionLineService.handleAfterInsert(new List<Invoice__c>());
        InvoiceOptionLineService.handleAfterInsert(null);
        InvoiceOptionLineService.seedForInvoices(null);
        Test.stopTest();
        System.assert(true, 'no exception for empty / null input');
    }

    // ── Bulk ────────────────────────────────────────────────────────────────

    @isTest
    static void bulkSeveralInvoicesEachBilled() {
        Map<String, SObject>   chain  = buildChain(5.00);
        Application__c         app    = (Application__c)         chain.get('application');
        Application_Package__c appPkg = (Application_Package__c) chain.get('appPackage');

        addOption(appPkg.Id, 'Air Conditoning', 100.00, 1);
        addOption(appPkg.Id, 'Rust Proofing',   200.00, 2);

        List<Invoice__c> invoices = new List<Invoice__c>();
        for (Integer i = 0; i < 25; i++) {
            invoices.add(newInvoice(app.Id));
        }

        Test.startTest();
        insert invoices;
        Test.stopTest();

        // Per-invoice idempotency: each invoice gets its own two option lines.
        Integer total = [SELECT COUNT() FROM Invoice_Line_Item__c
                         WHERE Invoice__c IN :invoices AND Application_Package__c = null];
        System.assertEquals(50, total, '25 invoices × 2 options');
    }

    @isTest
    static void duplicateOptionNamesProduceOneLine() {
        Map<String, SObject>   chain  = buildChain(5.00);
        Application__c         app    = (Application__c)         chain.get('application');
        Application_Package__c appPkg = (Application_Package__c) chain.get('appPackage');

        // Two source lines with the same description → one invoice line.
        addOption(appPkg.Id, 'Air Conditoning', 100.00, 1);
        addOption(appPkg.Id, 'Air Conditoning', 150.00, 2);

        Invoice__c inv = newInvoice(app.Id);

        Test.startTest();
        insert inv;
        Test.stopTest();

        List<Invoice_Line_Item__c> lines = standaloneLines(inv.Id);
        System.assertEquals(1, lines.size(),
            'duplicate option names collapse to a single billed line');
        System.assertEquals(105.00, lines[0].Repair_Charge_Amount__c,
            'the first option line wins');
    }

    // ── Helpers ─────────────────────────────────────────────────────────────

    @isTest
    static void helperCoverage() {
        System.assertEquals('Air Conditoning (Optional)',
            InvoiceOptionLineService.optionLabel('Air Conditoning'), 'suffix appended');
        System.assertEquals('Air Conditoning (Optional)',
            InvoiceOptionLineService.optionLabel('Air Conditoning (Optional)'), 'suffix not doubled');
        System.assertEquals('Option (Optional)',
            InvoiceOptionLineService.optionLabel(''), 'blank falls back');
        System.assertEquals('Option (Optional)',
            InvoiceOptionLineService.optionLabel(null), 'null falls back');
        System.assertEquals('Air (Optional)',
            InvoiceOptionLineService.optionLabel('  Air  '), 'name is trimmed');

        System.assertEquals('abc', InvoiceOptionLineService.normalize('  ABC '), 'normalised key');
        System.assertEquals('',    InvoiceOptionLineService.normalize(null), 'null → empty');

        System.assertEquals(10.01, InvoiceOptionLineService.money(10.005), 'HALF_UP rounds up');
        System.assertEquals(10.00, InvoiceOptionLineService.money(10.004), 'HALF_UP rounds down');
        System.assertEquals(0,     InvoiceOptionLineService.money(null), 'null → 0');
    }
}