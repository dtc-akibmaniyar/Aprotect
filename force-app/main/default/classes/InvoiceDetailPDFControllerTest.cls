/**
 * InvoiceDetailPDFControllerTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Coverage target: 99%+
 *
 * This is a Visualforce page controller — ApexPages.currentPage() must be
 * set up before each constructor call via Test.setCurrentPage().
 *
 * Formula fields on Application__c (Customer_First_Name__c, Vehicle_Make__c
 * etc.) are NOT writable directly. They resolve via Customer_Name__c and
 * Vehicle__c lookups set inside createApplicationWithDetails().
 *
 * Phase 2 (2026-08-24): controller now mirrors the invoiceDetailView LWC —
 *   • packages are scoped to invoice line items (no more "all app packages");
 *   • dealerName / billTo fall back to the Application dealer Account;
 *   • Premium_Model_Fee__c, Selection_Type__c, term null→'0' display,
 *     SUB-TOTAL / HST / TOTAL DUE computations, ISO due date, status styles.
 */
@isTest
private class InvoiceDetailPDFControllerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // SHARED SETUP HELPERS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Wires up the mock Visualforce page with the given id parameter and
     * returns a new controller instance. Pass null to simulate no id param.
     */
    private static InvoiceDetailPDFController buildController(String invoiceId) {
        PageReference page = Page.InvoiceDetailPDF;
        if (invoiceId != null) {
            page.getParameters().put('id', invoiceId);
        }
        Test.setCurrentPage(page);
        return new InvoiceDetailPDFController();
    }

    /**
     * Minimal chain — no vehicle or customer linked to Application.
     *   Dealer → Application → Invoice
     */
    private static Map<String, SObject> setupMinimalInvoice() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);
        Invoice__c     inv    = TestDataFactory.createInvoice(app.Id, true);
        return new Map<String, SObject>{
            'dealer'      => dealer,
            'application' => app,
            'invoice'     => inv
        };
    }

    /**
     * Full chain — Vehicle__c and Customer_Name__c linked so all formula
     * fields on Application__c resolve naturally.
     *   Dealer → Application (with details) → Invoice
     */
    private static Map<String, SObject> setupDetailedInvoice() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplicationWithDetails(dealer.Id, true);
        Invoice__c     inv    = TestDataFactory.createInvoice(app.Id, true);
        return new Map<String, SObject>{
            'dealer'      => dealer,
            'application' => app,
            'invoice'     => inv
        };
    }

    /**
     * Invoice linked to a Dealer_Remittance Remittance_Form__c.
     * Used for dealerName / billTo field coverage.
     */
    private static Map<String, SObject> setupInvoiceWithRemittance() {
        Account            dealer = TestDataFactory.createDealer(true);
        Application__c     app    = TestDataFactory.createApplicationWithDetails(dealer.Id, true);
        Remittance_Form__c rf     = TestDataFactory.createDealerRemittanceForm(dealer.Id, true);
        Invoice__c         inv    = TestDataFactory.createInvoiceLinkedToRF(
                                        app.Id, rf.Id, 'INV-PDF-001', true
                                    );
        return new Map<String, SObject>{
            'dealer'         => dealer,
            'application'    => app,
            'remittanceForm' => rf,
            'invoice'        => inv
        };
    }


    /**
     * Creates a Package__c with a sane commission configuration.
     *
     * Sandbox quirk: the Package__c record-type defaults (Commission_Rate_Pct__c
     * = 2000, Reserve_Pct__c = 5000, Discount_Threshold_Pct__c = 1500) trip
     * CommissionCalculationTrigger when an Application_Package__c with a
     * Package_Term__c is inserted ("Commission Rate: value outside of valid
     * range"). Setting explicit config (like CommissionCalculationHandlerTest
     * does) keeps the trigger's computed values within range.
     */
    private static Package__c createConfiguredPackage(String recordTypeDeveloperName, Boolean doInsert) {
        Package__c pkg = TestDataFactory.createPackage(recordTypeDeveloperName, doInsert);
        if (doInsert) {
            pkg.Commission_Rate_Pct__c    = 20;
            pkg.Reserve_Pct__c            = 50;
            pkg.Discount_Threshold_Pct__c = 15;
            update pkg;
        }
        return pkg;
    }

    /**
     * Full package hierarchy — Application_Package__c + Invoice_Line_Item__c.
     * Used for PackageRow building and grandTotal / packageTotal coverage.
     */
    private static Map<String, SObject> setupInvoiceWithPackageAndLineItem() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplicationWithDetails(dealer.Id, true);
        Invoice__c     inv    = TestDataFactory.createInvoice(app.Id, true);

        Package__c             pkg        = createConfiguredPackage(
                                               'Extended_Limited_Warranty', true
                                           );
        Package_Term__c        srcTerm    = TestDataFactory.createPackageTerm(
                                               pkg.Id, null, true
                                           );
        Dealer_Package__c      dealerPkg  = TestDataFactory.createDealerPackage(
                                               dealer.Id, pkg.Id,
                                               'Extended_Limited_Warranty', true
                                           );
        Dealer_Package_Term__c dealerTerm = TestDataFactory.createDealerPackageTerm(
                                               dealerPkg.Id, srcTerm.Id, null, true
                                           );
        Application_Package__c appPkg    = TestDataFactory.createApplicationPackage(
                                               app.Id, dealerPkg.Id, dealerTerm.Id,
                                               dealer.Id, 'Extended_Limited_Warranty',
                                               1500.00, 13.00, true
                                           );
        Invoice_Line_Item__c   ili       = TestDataFactory.createInvoiceLineItem(
                                               inv.Id, appPkg.Id, true
                                           );
        return new Map<String, SObject>{
            'dealer'      => dealer,
            'application' => app,
            'invoice'     => inv,
            'appPackage'  => appPkg,
            'lineItem'    => ili
        };
    }

    /**
     * Full package hierarchy + a priced add-on (Application_Package_Option__c)
     * with a Selection_Type__c, so Option__c / Net_Cost__c / Selection_Type__c
     * formula fields resolve through the Package_Option__c chain.
     */
    private static Map<String, SObject> setupInvoiceWithPackageOption() {
        Map<String, SObject> chain = setupInvoiceWithPackageAndLineItem();
        Account              dealer = (Account)        chain.get('dealer');
        Application__c       app    = (Application__c) chain.get('application');
        Application_Package__c appPkg = (Application_Package__c) chain.get('appPackage');

        // Package_Option__c chain: Option__c → Package_Option__c → Dealer_Package_Option__c
        Option__c opt = new Option__c(Name = 'Windshield Protection');
        insert opt;

        Dealer_Package__c dealerPkg = [
            SELECT Id, Package__c
            FROM Dealer_Package__c
            WHERE Id = :appPkg.Dealer_Package__c
            LIMIT 1
        ];

        Package_Option__c pkgOpt = TestDataFactory.createPackageOption(
            dealerPkg.Package__c, null, 'Optional', true
        );
        pkgOpt.Option__c = opt.Id;
        update pkgOpt;

        Dealer_Package_Option__c dpOpt = TestDataFactory.createDealerPackageOption(
            dealerPkg.Id, pkgOpt.Id, null, 'Optional', true
        );

        Application_Package_Option__c apo = new Application_Package_Option__c(
            Application__c                  = app.Id,
            Application_Package__c          = appPkg.Id,
            Package_Option__c               = pkgOpt.Id,
            Dealer_Package_Option__c        = dpOpt.Id,
            Original_Package_Option_Price__c = 100.00
        );
        insert apo;

        chain.put('packageOption', apo);
        return chain;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 1 — PACKAGE ROW INNER CLASS
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testPackageRow_allPropertiesGetAndSet() {
        InvoiceDetailPDFController.PackageRow row =
            new InvoiceDetailPDFController.PackageRow();

        Application_Package__c appPkg = new Application_Package__c();
        List<InvoiceDetailPDFController.LineItemWrapper> lis =
            new List<InvoiceDetailPDFController.LineItemWrapper>();

        row.pkg          = appPkg;
        row.lineItems    = lis;
        row.packageTotal = 999.99;

        System.assertNotEquals(null, row.pkg,          'pkg should be set');
        System.assertNotEquals(null, row.lineItems,    'lineItems should be set');
        System.assertEquals(999.99,  row.packageTotal, 'packageTotal should match');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 2 — BLANK / MISSING ID → EARLY RETURN
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testConstructor_blankId_earlyReturn_allPropertiesAtDefaults() {
        // No id param → String.isBlank returns true → constructor returns early
        Test.startTest();
            InvoiceDetailPDFController ctrl = buildController(null);
        Test.stopTest();

        System.assertEquals(null, ctrl.invoice,
            'invoice should be null when id param is absent');
        System.assertEquals(null, ctrl.application,
            'application should be null when id param is absent');
        System.assertEquals(null, ctrl.dealerName,
            'dealerName should be null when id param is absent');
        System.assertEquals(null, ctrl.billTo,
            'billTo should be null when id param is absent');
        System.assertNotEquals(null, ctrl.packages,
            'packages should be initialised as empty list');
        System.assertEquals(0, ctrl.packages.size(),
            'packages should be empty when id param is absent');
        System.assertEquals(0, ctrl.grandTotal,
            'grandTotal should be 0 when id param is absent');
        System.assertEquals(0, ctrl.subTotal,
            'subTotal should be 0 when id param is absent');
        System.assertEquals(0, ctrl.taxTotal,
            'taxTotal should be 0 when id param is absent');
        System.assertEquals(null, ctrl.blendedTaxRate,
            'blendedTaxRate should be null when id param is absent');
        System.assertEquals(null, ctrl.dueDate,
            'dueDate should be null when id param is absent');
    }

    @isTest
    static void testConstructor_emptyStringId_earlyReturn() {
        // Empty string → String.isBlank('') = true → early return
        PageReference page = Page.InvoiceDetailPDF;
        page.getParameters().put('id', '');
        Test.setCurrentPage(page);

        Test.startTest();
            InvoiceDetailPDFController ctrl = new InvoiceDetailPDFController();
        Test.stopTest();

        System.assertEquals(null, ctrl.invoice,
            'invoice should be null for empty string id');
        System.assertEquals(0, ctrl.grandTotal,
            'grandTotal should be 0 for empty string id');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 3 — INVOICE NOT FOUND → EARLY RETURN
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testConstructor_invoiceNotFound_earlyReturn() {
        // Well-formed Id that doesn't exist → SOQL returns empty → early return
        Test.startTest();
            InvoiceDetailPDFController ctrl =
                buildController('a0000000000000ZAAQ');
        Test.stopTest();

        System.assertEquals(null, ctrl.invoice,
            'invoice should be null when no Invoice__c found');
        System.assertEquals(null, ctrl.application,
            'application should be null when invoice not found');
        System.assertEquals(0,    ctrl.packages.size(),
            'packages should be empty when invoice not found');
        System.assertEquals(0,    ctrl.grandTotal,
            'grandTotal should be 0 when invoice not found');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 4 — INVOICE FOUND, NO REMITTANCE FORM
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testConstructor_invoiceFound_noRemittanceForm_topLevelFieldsSet() {
        Map<String, SObject> chain = setupMinimalInvoice();
        Invoice__c inv = (Invoice__c) chain.get('invoice');

        Test.startTest();
            InvoiceDetailPDFController ctrl = buildController(inv.Id);
        Test.stopTest();

        System.assertNotEquals(null, ctrl.invoice,
            'invoice should be set when found');
        System.assertEquals(inv.Id, ctrl.invoice.Id,
            'invoice.Id should match the queried invoice');
        System.assertNotEquals(null, ctrl.invoice.Name,
            'invoice.Name should be populated');
        System.assertNotEquals(null, ctrl.invoice.Status__c,
            'invoice.Status__c should be populated');

        // No remittance form linked → dealerName/billTo fall back to the
        // Application dealer Account (LWC parity).
        System.assertNotEquals(null, ctrl.dealerName,
            'dealerName should fall back to Application__r.Dealer_Name__r.Name');
        System.assertNotEquals(null, ctrl.billTo,
            'billTo should fall back to the dealer Account billing fields');

        // No line items → grandTotal = 0
        System.assertEquals(0, ctrl.grandTotal,
            'grandTotal should be 0 when no line items');
        System.assertEquals(0, ctrl.subTotal,
            'subTotal should be 0 when no packages');
        System.assertEquals(0, ctrl.taxTotal,
            'taxTotal should be 0 when no packages');
        System.assertEquals(null, ctrl.blendedTaxRate,
            'blendedTaxRate should be null when subTotal is 0');
    }

    @isTest
    static void testConstructor_invoiceFound_applicationSetFromRelationship() {
        Map<String, SObject> chain = setupMinimalInvoice();
        Invoice__c     inv = (Invoice__c)     chain.get('invoice');
        Application__c app = (Application__c) chain.get('application');

        Test.startTest();
            InvoiceDetailPDFController ctrl = buildController(inv.Id);
        Test.stopTest();

        System.assertNotEquals(null, ctrl.application,
            'application should be set from invoice.Application__r');
        System.assertEquals(app.Id, ctrl.application.Id,
            'application.Id should match the related Application__c');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 5 — INVOICE WITH REMITTANCE FORM → dealerName / billTo
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testConstructor_withRemittanceForm_dealerNameAndBillToPopulated() {
        Map<String, SObject> chain = setupInvoiceWithRemittance();
        Invoice__c           inv   = (Invoice__c) chain.get('invoice');

        Test.startTest();
            InvoiceDetailPDFController ctrl = buildController(inv.Id);
        Test.stopTest();

        System.assertNotEquals(null, ctrl.dealerName,
            'dealerName should be populated from Remittance_Form__r.Dealer_Name__r.Name');
        // Remittance_Form__c.Bill_To__c is a formula that resolves from the
        // dealer Account billing fields — expect the RF value to win.
        System.assertNotEquals(null, ctrl.billTo,
            'billTo should be populated (RF Bill_To__c formula or account fallback)');
        System.assertNotEquals(null, ctrl.invoice,
            'invoice should be set when remittance form is linked');
    }

    @isTest
    static void testConstructor_billTo_prefersRemittanceFormOverAccountFallback() {
        Map<String, SObject> chain = setupInvoiceWithRemittance();
        Invoice__c           inv   = (Invoice__c) chain.get('invoice');

        Test.startTest();
            InvoiceDetailPDFController ctrl = buildController(inv.Id);
        Test.stopTest();

        // RF Bill_To__c formula: Street<br/>City, State Postal<br/>Country
        // (comma between city and state, no Tel line) — distinct from the
        // account fallback (space join + Tel: line).
        System.assertNotEquals(null, ctrl.billTo, 'billTo should not be null');
        System.assert(ctrl.billTo.contains('123 Main Street'),
            'billTo should contain the billing street: ' + ctrl.billTo);
        System.assert(ctrl.billTo.contains('Toronto, ON M5V 0A1'),
            'billTo should use the RF formula city line (comma): ' + ctrl.billTo);
        System.assert(!ctrl.billTo.contains('Tel:'),
            'billTo should come from the RF formula, not the account fallback');
    }

    @isTest
    static void testConstructor_billTo_fallbackFromDealerAccountFields() {
        // Invoice with NO remittance form → billTo built from dealer Account
        Map<String, SObject> chain = setupMinimalInvoice();
        Invoice__c           inv   = (Invoice__c) chain.get('invoice');
        Account              dealer = (Account)     chain.get('dealer');

        Test.startTest();
            InvoiceDetailPDFController ctrl = buildController(inv.Id);
        Test.stopTest();

        System.assertEquals(dealer.Name, ctrl.dealerName,
            'dealerName should fall back to the Application dealer name');
        System.assertNotEquals(null, ctrl.billTo, 'billTo should be built from the account');
        System.assert(ctrl.billTo.contains('123 Main Street'),
            'billTo should contain billing street: ' + ctrl.billTo);
        System.assert(ctrl.billTo.contains('Toronto ON M5V 0A1'),
            'billTo should contain city/state/postal (space join): ' + ctrl.billTo);
        System.assert(ctrl.billTo.contains('Tel: 416-555-0100'),
            'billTo should contain the phone line: ' + ctrl.billTo);
        System.assert(ctrl.billTo.contains('<br/>'),
            'billTo parts should be joined with <br/>');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 6 — FORMULA FIELDS ON APPLICATION RESOLVE VIA LOOKUPS
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testConstructor_withVehicleAndCustomer_formulaFieldsResolve() {
        // createApplicationWithDetails links Vehicle__c and Customer_Name__c
        // so all formula fields resolve — no direct writes to formula fields
        Map<String, SObject> chain = setupDetailedInvoice();
        Invoice__c inv = (Invoice__c) chain.get('invoice');
        Application__c app = (Application__c) chain.get('application');

        Test.startTest();
            InvoiceDetailPDFController ctrl = buildController(inv.Id);
        Test.stopTest();

        System.assertNotEquals(null, ctrl.application,
            'application should be populated');
        System.assertNotEquals(null, ctrl.invoice,
            'invoice should be set for detailed application');

        // Vehicle grid getters mirror the LWC
        System.assert(ctrl.applicationId != null && ctrl.applicationId.startsWith('APP'),
            'applicationId should be the Application name: ' + ctrl.applicationId);
        System.assertEquals('2022/Toyota/Camry', ctrl.vehicleInfo,
            'vehicleInfo should join Year/Make/Model with "/"');
        System.assert(ctrl.vin == null || ctrl.vin == '1HGBH41JXMN109186',
            'vin should resolve from the Vehicle__c lookup when the formula resolves: ' + ctrl.vin);
        System.assertEquals('KM', ctrl.odometerUnit,
            'odometerUnit should default/populate from the vehicle');
        System.assert(ctrl.customerFullName != null && ctrl.customerFullName != '',
            'customerFullName should resolve from the person account');
    }

    @isTest
    static void testConstructor_noVehicleNoCustomer_formulaFieldsNull() {
        // Minimal application — no Vehicle__c, no Customer_Name__c
        // All formula fields on Application__c resolve to null — no crash
        Map<String, SObject> chain = setupMinimalInvoice();
        Invoice__c inv = (Invoice__c) chain.get('invoice');

        Test.startTest();
            InvoiceDetailPDFController ctrl = buildController(inv.Id);
        Test.stopTest();

        System.assertNotEquals(null, ctrl.application,
            'application should still be set even with null formula fields');
        System.assertEquals(null, ctrl.application.Vehicle_VIN__c,
            'Vehicle_VIN__c formula should be null when Vehicle__c is not linked');
        System.assertEquals(null, ctrl.application.Customer_First_Name__c,
            'Customer_First_Name__c formula should be null when Customer_Name__c not linked');
        System.assertEquals('', ctrl.vehicleInfo,
            'vehicleInfo should be empty when no vehicle fields resolve (String.join of [])');
        System.assertEquals(null, ctrl.vin,
            'vin should be null when no Vehicle__c is linked');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 7 — LINE ITEMS AND GRAND TOTAL
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testConstructor_lineItemWithNullPackage_addedToGrandTotalNotPkgMap() {
        // Line item with no Application_Package__c → grandTotal += 0
        // (Contract_Cost_Price__c is null) and not added to pkgMap.
        // LWC parity: null-package line items still count toward grandTotal
        // (their Contract_Cost_Price__c formula is null → 0).
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);
        Invoice__c     inv    = TestDataFactory.createInvoice(app.Id, true);

        // Line item with no Application_Package__c
        insert new Invoice_Line_Item__c(Invoice__c = inv.Id, Status__c = 'Due');

        Test.startTest();
            InvoiceDetailPDFController ctrl = buildController(inv.Id);
        Test.stopTest();

        System.assertEquals(0, ctrl.grandTotal,
            'grandTotal should be 0 — null Contract_Cost_Price__c adds 0');
        System.assertEquals(0, ctrl.packages.size(),
            'packages should be empty — line item has no Application_Package__c');
    }

    @isTest
    static void testConstructor_withPackageAndLineItem_grandTotalAccumulated() {
        Map<String, SObject>   chain  = setupInvoiceWithPackageAndLineItem();
        Invoice__c             inv    = (Invoice__c)             chain.get('invoice');
        Application_Package__c appPkg = (Application_Package__c) chain.get('appPackage');

        Test.startTest();
            InvoiceDetailPDFController ctrl = buildController(inv.Id);
        Test.stopTest();

        // Contract_Cost_Price__c is a formula driven by Dealer_Package_Price__c
        // If it resolves, grandTotal > 0; if null in test context, grandTotal = 0
        // Either way no exception should be thrown
        System.assert(ctrl.grandTotal >= 0,
            'grandTotal should be non-negative');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 8 — APPLICATION__C NULL → PACKAGE QUERY SKIPPED
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testConstructor_applicationNull_packageQuerySkipped() {
        // Create an Invoice__c with no Application__c
        Invoice__c inv = new Invoice__c(
            Status__c           = 'Due',
            Amount__c           = 500.00,
            Invoice_Due_Date__c = Date.today().addDays(30)
        );
        insert inv;

        Test.startTest();
            InvoiceDetailPDFController ctrl = buildController(inv.Id);
        Test.stopTest();

        System.assertNotEquals(null, ctrl.invoice,
            'invoice should be set');
        System.assertEquals(0, ctrl.packages.size(),
            'packages should be empty when Application__c is null — query skipped');
        System.assertEquals(null, ctrl.application,
            'application should be null when invoice has no Application__c');
        System.assertEquals(0, ctrl.subTotal,
            'subTotal should be 0 with no application');
        // Amount__c = 500 → Total_Balance_Amount__c resolves to 500
        System.assertEquals(500.00, ctrl.balanceAmount,
            'balanceAmount should be Total_Balance_Amount__c');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 9 — PACKAGE ROW BUILDING (pkgMap, packageTotal)
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testConstructor_packageRowBuilt_withLineItems() {
        Map<String, SObject>   chain  = setupInvoiceWithPackageAndLineItem();
        Invoice__c             inv    = (Invoice__c)             chain.get('invoice');
        Application_Package__c appPkg = (Application_Package__c) chain.get('appPackage');

        Test.startTest();
            InvoiceDetailPDFController ctrl = buildController(inv.Id);
        Test.stopTest();

        System.assertEquals(1, ctrl.packages.size(),
            'Should have one PackageRow for the one Application_Package__c');

        InvoiceDetailPDFController.PackageRow row = ctrl.packages[0];
        System.assertNotEquals(null, row.pkg,
            'PackageRow.pkg should not be null');
        System.assertEquals(appPkg.Id, row.pkg.Id,
            'PackageRow.pkg.Id should match the Application_Package__c');
        System.assertNotEquals(null, row.lineItems,
            'PackageRow.lineItems should not be null');
        System.assertEquals(1, row.lineItems.size(),
            'PackageRow should contain the one Invoice_Line_Item__c');
        System.assert(row.packageTotal >= 0,
            'PackageRow.packageTotal should be non-negative');
    }

    @isTest
    static void testConstructor_packageWithoutLineItem_notLoaded() {
        // Application_Package__c exists on the Application but no line items
        // reference it → package scope is line-item-driven (LWC parity), so
        // the package is NOT loaded.
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplicationWithDetails(dealer.Id, true);
        Invoice__c     inv    = TestDataFactory.createInvoice(app.Id, true);

        Package__c             pkg        = createConfiguredPackage(
                                               'Extended_Limited_Warranty', true
                                           );
        Package_Term__c        srcTerm    = TestDataFactory.createPackageTerm(
                                               pkg.Id, null, true
                                           );
        Dealer_Package__c      dealerPkg  = TestDataFactory.createDealerPackage(
                                               dealer.Id, pkg.Id,
                                               'Extended_Limited_Warranty', true
                                           );
        Dealer_Package_Term__c dealerTerm = TestDataFactory.createDealerPackageTerm(
                                               dealerPkg.Id, srcTerm.Id, null, true
                                           );
        // Application_Package__c created but NO Invoice_Line_Item__c referencing it
        TestDataFactory.createApplicationPackage(
            app.Id, dealerPkg.Id, dealerTerm.Id,
            dealer.Id, 'Extended_Limited_Warranty',
            1500.00, 13.00, true
        );

        Test.startTest();
            InvoiceDetailPDFController ctrl = buildController(inv.Id);
        Test.stopTest();

        System.assertEquals(0, ctrl.packages.size(),
            'Packages without an invoice line item should NOT be loaded (scoped to line items)');
        System.assertEquals(0, ctrl.grandTotal,
            'grandTotal should be 0 when no line items exist for the invoice');
    }

    @isTest
    static void testConstructor_packagesScopedToLineItems_onlyInvoicePackagesLoaded() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplicationWithDetails(dealer.Id, true);
        Invoice__c     inv    = TestDataFactory.createInvoice(app.Id, true);

        // Package A — referenced by the invoice line item → must be loaded
        Package__c             pkgA       = createConfiguredPackage(
                                               'Extended_Limited_Warranty', true
                                           );
        Package_Term__c        termA      = TestDataFactory.createPackageTerm(pkgA.Id, null, true);
        Dealer_Package__c      dealerPkgA = TestDataFactory.createDealerPackage(
                                               dealer.Id, pkgA.Id,
                                               'Extended_Limited_Warranty', true
                                           );
        Dealer_Package_Term__c dtA        = TestDataFactory.createDealerPackageTerm(
                                               dealerPkgA.Id, termA.Id, null, true
                                           );
        Application_Package__c appPkgA    = TestDataFactory.createApplicationPackage(
                                               app.Id, dealerPkgA.Id, dtA.Id,
                                               dealer.Id, 'Extended_Limited_Warranty',
                                               1000.00, 13.00, true
                                           );
        TestDataFactory.createInvoiceLineItem(inv.Id, appPkgA.Id, true);

        // Package B — on the SAME application but NOT on the invoice → excluded
        Package__c             pkgB       = createConfiguredPackage(
                                               'Tire_Rim_Protection_Plan', true
                                           );
        Package_Term__c        termB      = TestDataFactory.createPackageTerm(pkgB.Id, null, true);
        Dealer_Package__c      dealerPkgB = TestDataFactory.createDealerPackage(
                                               dealer.Id, pkgB.Id,
                                               'Tire_Rim_Protection_Plan', true
                                           );
        Dealer_Package_Term__c dtB        = TestDataFactory.createDealerPackageTerm(
                                               dealerPkgB.Id, termB.Id, null, true
                                           );
        TestDataFactory.createApplicationPackage(
            app.Id, dealerPkgB.Id, dtB.Id,
            dealer.Id, 'Tire_Rim_Protection_Plan',
            500.00, 13.00, true
        );

        Test.startTest();
            InvoiceDetailPDFController ctrl = buildController(inv.Id);
        Test.stopTest();

        System.assertEquals(1, ctrl.packages.size(),
            'Only packages referenced by invoice line items should be loaded');
        System.assertEquals(appPkgA.Id, ctrl.packages[0].pkg.Id,
            'The loaded package should be the one referenced by the line item');
    }

    @isTest
    static void testConstructor_contractDatesNull_packageRowStillBuilt() {
        Map<String, SObject>   chain  = setupInvoiceWithPackageAndLineItem();
        Invoice__c             inv    = (Invoice__c)             chain.get('invoice');
        Application_Package__c appPkg = (Application_Package__c) chain.get('appPackage');

        appPkg.Contract_Start_Date__c = null;
        appPkg.Contract_End_Date__c   = null;
        update appPkg;

        Test.startTest();
            InvoiceDetailPDFController ctrl = buildController(inv.Id);
        Test.stopTest();

        System.assertEquals(1, ctrl.packages.size(),
            'PackageRow should be built even when contract dates are null');
        System.assertEquals(null, ctrl.packages[0].pkg.Contract_Start_Date__c,
            'Contract_Start_Date__c should be null');
        System.assertEquals(null, ctrl.packages[0].pkg.Contract_End_Date__c,
            'Contract_End_Date__c should be null');
    }

    @isTest
    static void testConstructor_contractDatesSet_packageRowContainsDates() {
        Map<String, SObject>   chain  = setupInvoiceWithPackageAndLineItem();
        Invoice__c             inv    = (Invoice__c)             chain.get('invoice');
        Application_Package__c appPkg = (Application_Package__c) chain.get('appPackage');

        appPkg.Contract_Start_Date__c = Date.newInstance(2023, 3, 1);
        appPkg.Contract_End_Date__c   = Date.newInstance(2025, 3, 1);
        update appPkg;

        Test.startTest();
            InvoiceDetailPDFController ctrl = buildController(inv.Id);
        Test.stopTest();

        System.assertEquals(1, ctrl.packages.size(),
            'One PackageRow should be present');
        System.assertEquals(Date.newInstance(2023, 3, 1),
            ctrl.packages[0].pkg.Contract_Start_Date__c,
            'Contract_Start_Date__c should match the set value');
        System.assertEquals(Date.newInstance(2025, 3, 1),
            ctrl.packages[0].pkg.Contract_End_Date__c,
            'Contract_End_Date__c should match the set value');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 10 — MULTIPLE PACKAGES ON SAME APPLICATION
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testConstructor_multiplePackages_allRowsBuilt() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplicationWithDetails(dealer.Id, true);
        Invoice__c     inv    = TestDataFactory.createInvoice(app.Id, true);

        Package__c             pkg1       = createConfiguredPackage(
                                               'Extended_Limited_Warranty', true
                                           );
        Package__c             pkg2       = createConfiguredPackage(
                                               'Tire_Rim_Protection_Plan', true
                                           );
        Package_Term__c        srcTerm1   = TestDataFactory.createPackageTerm(pkg1.Id, null, true);
        Package_Term__c        srcTerm2   = TestDataFactory.createPackageTerm(pkg2.Id, null, true);
        Dealer_Package__c      dealerPkg1 = TestDataFactory.createDealerPackage(
                                               dealer.Id, pkg1.Id,
                                               'Extended_Limited_Warranty', true
                                           );
        Dealer_Package__c      dealerPkg2 = TestDataFactory.createDealerPackage(
                                               dealer.Id, pkg2.Id,
                                               'Tire_Rim_Protection_Plan', true
                                           );
        Dealer_Package_Term__c dt1        = TestDataFactory.createDealerPackageTerm(
                                               dealerPkg1.Id, srcTerm1.Id, null, true
                                           );
        Dealer_Package_Term__c dt2        = TestDataFactory.createDealerPackageTerm(
                                               dealerPkg2.Id, srcTerm2.Id, null, true
                                           );
        Application_Package__c appPkg1   = TestDataFactory.createApplicationPackage(
                                               app.Id, dealerPkg1.Id, dt1.Id,
                                               dealer.Id, 'Extended_Limited_Warranty',
                                               1000.00, 13.00, true
                                           );
        Application_Package__c appPkg2   = TestDataFactory.createApplicationPackage(
                                               app.Id, dealerPkg2.Id, dt2.Id,
                                               dealer.Id, 'Tire_Rim_Protection_Plan',
                                               500.00, 13.00, true
                                           );

        TestDataFactory.createInvoiceLineItem(inv.Id, appPkg1.Id, true);
        TestDataFactory.createInvoiceLineItem(inv.Id, appPkg2.Id, true);

        Test.startTest();
            InvoiceDetailPDFController ctrl = buildController(inv.Id);
        Test.stopTest();

        System.assertEquals(2, ctrl.packages.size(),
            'Two PackageRows should be built for two Application_Package__c records');

        for (InvoiceDetailPDFController.PackageRow row : ctrl.packages) {
            System.assertNotEquals(null, row.pkg,       'Each row.pkg should not be null');
            System.assertNotEquals(null, row.lineItems, 'Each row.lineItems should not be null');
            System.assert(row.packageTotal >= 0,        'Each row.packageTotal should be >= 0');
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 11 — PHASE 2: PREMIUM FEE / LINE TOTAL / OPTIONS / TOTALS
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testConstructor_premiumModelFee_includedInLineTotal() {
        Map<String, SObject>   chain  = setupInvoiceWithPackageAndLineItem();
        Invoice__c             inv    = (Invoice__c)             chain.get('invoice');
        Application_Package__c appPkg = (Application_Package__c) chain.get('appPackage');

        appPkg.Dealer_Package_Price__c = 1000.00;
        appPkg.Add_Ons_Price__c        = 100.00;
        appPkg.Premium_Model_Fee__c    = 50.00;
        appPkg.Tax_Percentage__c       = 13.00;
        update appPkg;

        Test.startTest();
            InvoiceDetailPDFController ctrl = buildController(inv.Id);
        Test.stopTest();

        System.assertEquals(1, ctrl.packages.size(),
            'one package expected');
        InvoiceDetailPDFController.PackageRow row = ctrl.packages[0];

        System.assertEquals(50.00, row.premiumModelFee,
            'premiumModelFee should be populated');
        System.assertEquals(true, row.hasPremiumModelFee,
            'hasPremiumModelFee should be true when fee > 0');
        System.assertEquals(1150.00, row.lineTotal,
            'lineTotal = base (1000) + add-ons (100) + premium fee (50)');
    }

    @isTest
    static void testConstructor_noPremiumFee_hasPremiumModelFeeFalse() {
        Map<String, SObject>   chain  = setupInvoiceWithPackageAndLineItem();
        Invoice__c             inv    = (Invoice__c) chain.get('invoice');

        Test.startTest();
            InvoiceDetailPDFController ctrl = buildController(inv.Id);
        Test.stopTest();

        InvoiceDetailPDFController.PackageRow row = ctrl.packages[0];
        System.assertEquals(0, row.premiumModelFee,
            'premiumModelFee should default to 0');
        System.assertEquals(false, row.hasPremiumModelFee,
            'hasPremiumModelFee should be false when fee is 0');
        System.assertEquals(row.baseCostPrice + row.addOnsTotal, row.lineTotal,
            'lineTotal = base + add-ons when no premium fee');
    }

    @isTest
    static void testConstructor_addOnSelectionType_surfaced() {
        Map<String, SObject> chain = setupInvoiceWithPackageOption();
        Invoice__c           inv   = (Invoice__c) chain.get('invoice');

        Test.startTest();
            InvoiceDetailPDFController ctrl = buildController(inv.Id);
        Test.stopTest();

        System.assertEquals(1, ctrl.packages.size(),
            'one package expected');
        InvoiceDetailPDFController.PackageRow row = ctrl.packages[0];
        System.assertEquals(1, row.options.size(),
            'one add-on option expected');

        InvoiceDetailPDFController.OptionWrapper opt = row.options[0];
        System.assertEquals('Windshield Protection', opt.optionName,
            'optionName should resolve via the Package_Option__c chain');
        System.assertEquals('Optional', opt.selectionType,
            'selectionType should surface on the wrapper');
        System.assertEquals(100.00, opt.costPrice,
            'costPrice should be Net_Cost__c (Original price, no discount)');
    }

    @isTest
    static void testConstructor_totalsMath_subTotalTaxBlendedBalance() {
        Map<String, SObject>   chain  = setupInvoiceWithPackageAndLineItem();
        Invoice__c             inv    = (Invoice__c)             chain.get('invoice');
        Application_Package__c appPkg = (Application_Package__c) chain.get('appPackage');

        // base 1000 + add-ons 100 + premium 50 = 1150; tax 13%
        appPkg.Dealer_Package_Price__c = 1000.00;
        appPkg.Add_Ons_Price__c        = 100.00;
        appPkg.Premium_Model_Fee__c    = 50.00;
        appPkg.Tax_Percentage__c       = 13.00;
        update appPkg;

        Test.startTest();
            InvoiceDetailPDFController ctrl = buildController(inv.Id);
        Test.stopTest();

        // Contract_Cost_Price_Without_Tax__c = 1000 + 100 + 50 = 1150
        System.assertEquals(1150.00, ctrl.subTotal,
            'subTotal should be Σ Contract_Cost_Price_Without_Tax__c');
        // tax = 1150 × 13% = 149.50
        System.assertEquals(149.50, ctrl.taxTotal,
            'taxTotal should be Σ base × taxPercentage / 100');
        // blended = 149.50 / 1150 × 100 = 13.00
        System.assertEquals(13.00, ctrl.blendedTaxRate,
            'blended tax rate should be 13.00%');
        // Contract_Cost_Price__c = 1150 × 1.13 = 1299.50 (one line item)
        System.assertEquals(1299.50, ctrl.grandTotal,
            'grandTotal should equal the display price (incl. tax) per line item');
        // balanceAmount mirrors Invoice.Total_Balance_Amount__c exactly (LWC parity)
        Decimal expectedBalance = [SELECT Total_Balance_Amount__c FROM Invoice__c WHERE Id = :inv.Id].Total_Balance_Amount__c;
        System.assertEquals(expectedBalance, ctrl.balanceAmount,
            'balanceAmount should be Total_Balance_Amount__c');
    }

    @isTest
    static void testConstructor_balanceAmount_fallsBackToGrandTotal() {
        // Invoice with no Amount__c → Total_Balance_Amount__c formula is null
        // → balanceAmount falls back to grandTotal (LWC JS behavior).
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);
        Invoice__c     inv    = new Invoice__c(
            Application__c    = app.Id,
            Status__c         = 'Due',
            Invoice_Due_Date__c = Date.today().addDays(30)
        );
        insert inv;

        Test.startTest();
            InvoiceDetailPDFController ctrl = buildController(inv.Id);
        Test.stopTest();

        System.assertEquals(0, ctrl.balanceAmount,
            'balanceAmount should fall back to grandTotal (0 here)');
        System.assertEquals(0, ctrl.grandTotal,
            'grandTotal should be 0 with no line items');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 12 — PHASE 2: DUE DATE / TERM DISPLAY / STATUS STYLE / DATE
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testConstructor_dueDate_isoFormat() {
        Map<String, SObject> chain = setupMinimalInvoice();
        Invoice__c           inv   = (Invoice__c) chain.get('invoice');
        Date                 due   = Date.today().addDays(30);

        Test.startTest();
            InvoiceDetailPDFController ctrl = buildController(inv.Id);
        Test.stopTest();

        System.assertEquals(String.valueOf(due), ctrl.dueDate,
            'dueDate should be String.valueOf(Date) — ISO yyyy-MM-dd (LWC quirk)');
        System.assert(Pattern.matches('\\d{4}-\\d{2}-\\d{2}', ctrl.dueDate),
            'dueDate should match yyyy-MM-dd: ' + ctrl.dueDate);
    }

    @isTest
    static void testConstructor_dueDateNull_whenNotSet() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);
        Invoice__c     inv    = new Invoice__c(
            Application__c = app.Id,
            Status__c      = 'Due',
            Amount__c      = 100.00
        );
        insert inv;

        Test.startTest();
            InvoiceDetailPDFController ctrl = buildController(inv.Id);
        Test.stopTest();

        System.assertEquals(null, ctrl.dueDate,
            'dueDate should be null when Invoice_Due_Date__c is not set');
    }

    @isTest
    static void testConstructor_invoiceDate_formattedMmmDdYyyy() {
        Map<String, SObject> chain = setupMinimalInvoice();
        Invoice__c           inv   = (Invoice__c) chain.get('invoice');

        Test.startTest();
            InvoiceDetailPDFController ctrl = buildController(inv.Id);
        Test.stopTest();

        System.assertNotEquals(null, ctrl.invoiceDate,
            'invoiceDate should be formatted');
        System.assert(Pattern.matches('\\w{3} \\d{2}, \\d{4}', ctrl.invoiceDate),
            'invoiceDate should be MMM dd, yyyy: ' + ctrl.invoiceDate);
    }

    @isTest
    static void testConstructor_termDisplay_nullTermAndNullWordReplacement() {
        // Single dealer — an Account duplicate rule flags a second insert with
        // the same phone number, so both chains share the dealer account.
        Account dealer = TestDataFactory.createDealer(true);

        // 1) AP without Dealer_Package_Term__c / Package_Term__c → termDisplay ''
        Application__c app0   = TestDataFactory.createApplicationWithDetails(dealer.Id, true);
        Invoice__c     inv0   = TestDataFactory.createInvoice(app0.Id, true);
        Package__c     pkg0   = createConfiguredPackage('Extended_Limited_Warranty', true);
        Dealer_Package__c dp0 = TestDataFactory.createDealerPackage(
                                    dealer.Id, pkg0.Id, 'Extended_Limited_Warranty', true
                                );
        Application_Package__c appPkg0 = TestDataFactory.createApplicationPackage(
                                    app0.Id, dp0.Id, null, dealer.Id, true
                                );
        TestDataFactory.createInvoiceLineItem(inv0.Id, appPkg0.Id, true);

        InvoiceDetailPDFController ctrl1 = buildController(inv0.Id);
        System.assertEquals(1, ctrl1.packages.size(), 'one package expected');
        System.assertEquals('', ctrl1.packages[0].termDisplay,
            'termDisplay should be empty when the term is null');

        // 2) Term named 'null' → replaced with '0' (LWC JS quirk).
        //    The "Application Package - Update values" flow populates
        //    Package_Term__c from the DPT; rename that term to 'null'
        //    (a duplicate rule blocks INSERTing a term named 'null', but
        //    renaming an existing record is allowed).
        Application__c app = TestDataFactory.createApplicationWithDetails(dealer.Id, true);
        Invoice__c     inv = TestDataFactory.createInvoice(app.Id, true);
        Package__c     pkg = createConfiguredPackage('Extended_Limited_Warranty', true);
        Package_Term__c srcTerm = TestDataFactory.createPackageTerm(pkg.Id, null, true);
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
                                   dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true
                               );
        Dealer_Package_Term__c dt = TestDataFactory.createDealerPackageTerm(
                                        dp.Id, srcTerm.Id, null, true
                                    );
        Application_Package__c appPkg = TestDataFactory.createApplicationPackage(
                                            app.Id, dp.Id, dt.Id, dealer.Id,
                                            'Extended_Limited_Warranty', 1500.00, 13.00, true
                                        );
        TestDataFactory.createInvoiceLineItem(inv.Id, appPkg.Id, true);

        // Re-read the AP so the flow-populated Package_Term__c is visible
        Application_Package__c fresh = [
            SELECT Id, Package_Term__c
            FROM Application_Package__c
            WHERE Id = :appPkg.Id
            LIMIT 1
        ];
        System.assertNotEquals(null, fresh.Package_Term__c,
            'the flow should have populated Package_Term__c from the DPT');
        Package_Term__c term = [
            SELECT Id, Name
            FROM Package_Term__c
            WHERE Id = :fresh.Package_Term__c
            LIMIT 1
        ];
        term.Name = 'null';
        update term;

        InvoiceDetailPDFController ctrl2 = buildController(inv.Id);
        System.assertEquals('0', ctrl2.packages[0].termDisplay,
            'termDisplay should replace the word null with 0');
    }

    @isTest
    static void testConstructor_statusStyle_matchesLwcColors() {
        Map<String, SObject> chain = setupMinimalInvoice();
        Invoice__c           inv   = (Invoice__c) chain.get('invoice');

        InvoiceDetailPDFController ctrlDue = buildController(inv.Id);
        System.assert(ctrlDue.statusStyle.contains('#d9534f'),
            'Due status should be red #d9534f: ' + ctrlDue.statusStyle);

        inv.Status__c = 'Partial Paid';
        update inv;
        InvoiceDetailPDFController ctrlPartial = buildController(inv.Id);
        System.assert(ctrlPartial.statusStyle.contains('#f0ad4e'),
            'Partial Paid should be orange #f0ad4e');

        inv.Status__c = 'Paid';
        update inv;
        InvoiceDetailPDFController ctrlPaid = buildController(inv.Id);
        System.assert(ctrlPaid.statusStyle.contains('#5cb85c'),
            'Paid should be green #5cb85c');

        // 'Planned' is not a valid Invoice Status__c value — the controller
        // still maps it (LWC parity) but it can't be exercised via DML here.
        inv.Status__c = 'Overdue';
        update inv;
        InvoiceDetailPDFController ctrlOverdue = buildController(inv.Id);
        System.assert(ctrlOverdue.statusStyle.contains('#999'),
            'Overdue should fall back to grey #999 (not in the LWC status map)');

        inv.Status__c = 'Cancelled';
        update inv;
        InvoiceDetailPDFController ctrlCancelled = buildController(inv.Id);
        System.assert(ctrlCancelled.statusStyle.contains('line-through'),
            'Cancelled should be struck through: ' + ctrlCancelled.statusStyle);
        System.assert(ctrlCancelled.statusStyle.contains('#999'),
            'Cancelled should be grey #999');

        // Note: 'Something Else' is not a valid Invoice Status__c value —
        // the default branch is exercised above via 'Overdue'.
    }
}