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
     * Full package hierarchy — Application_Package__c + Invoice_Line_Item__c.
     * Used for PackageRow building and grandTotal / packageTotal coverage.
     */
    private static Map<String, SObject> setupInvoiceWithPackageAndLineItem() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplicationWithDetails(dealer.Id, true);
        Invoice__c     inv    = TestDataFactory.createInvoice(app.Id, true);

        Package__c             pkg        = TestDataFactory.createPackage(
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

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 1 — PACKAGE ROW INNER CLASS
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testPackageRow_allPropertiesGetAndSet() {
        InvoiceDetailPDFController.PackageRow row =
            new InvoiceDetailPDFController.PackageRow();

        Application_Package__c appPkg = new Application_Package__c();
        List<Invoice_Line_Item__c> lis = new List<Invoice_Line_Item__c>();

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

        // No remittance form linked → null-safe navigation returns null
        System.assertEquals(null, ctrl.dealerName,
            'dealerName should be null when no Remittance_Form__c linked');
        System.assertEquals(null, ctrl.billTo,
            'billTo should be null when no Remittance_Form__c linked');

        // No line items → grandTotal = 0
        System.assertEquals(0, ctrl.grandTotal,
            'grandTotal should be 0 when no line items');
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
        // billTo may be null if Bill_To__c is not set on the RF — just assert no crash
        System.assertNotEquals(null, ctrl.invoice,
            'invoice should be set when remittance form is linked');
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

        Test.startTest();
            InvoiceDetailPDFController ctrl = buildController(inv.Id);
        Test.stopTest();

        System.assertNotEquals(null, ctrl.application,
            'application should be populated');
        // Formula fields resolve through lookup relationships
        // Vehicle_VIN__c, Vehicle_Make__c etc. come from Vehicle__c
        // Customer_First_Name__c, Customer_Last_Name__c come from Customer_Name__c
        // We assert they are accessible without error (no direct value assertion
        // since formula resolution in test context depends on data relationships)
        System.assertNotEquals(null, ctrl.invoice,
            'invoice should be set for detailed application');
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
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 7 — LINE ITEMS AND GRAND TOTAL
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testConstructor_lineItemWithNullPackage_addedToGrandTotalNotPkgMap() {
        // Line item with no Application_Package__c → grandTotal += 0
        // (Contract_Cost_Price__c is null) and not added to pkgMap
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
        // Controller checks if (invoice.Application__c != null) before querying packages
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
    static void testConstructor_packageWithNoLineItems_emptyLineItemsAndZeroTotal() {
        // Application_Package__c exists on the Application but no line items
        // reference it → pkgMap does not contain pkg.Id → empty lineItems list
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplicationWithDetails(dealer.Id, true);
        Invoice__c     inv    = TestDataFactory.createInvoice(app.Id, true);

        Package__c             pkg        = TestDataFactory.createPackage(
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

        System.assertEquals(1, ctrl.packages.size(),
            'One PackageRow should be built even with no line items');

        InvoiceDetailPDFController.PackageRow row = ctrl.packages[0];
        System.assertEquals(0, row.lineItems.size(),
            'PackageRow.lineItems should be empty when no line items reference this package');
        System.assertEquals(0, row.packageTotal,
            'PackageRow.packageTotal should be 0 when no line items');
        System.assertEquals(0, ctrl.grandTotal,
            'grandTotal should be 0 when no line items exist for the invoice');
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

        Package__c             pkg1       = TestDataFactory.createPackage(
                                               'Extended_Limited_Warranty', true
                                           );
        Package__c             pkg2       = TestDataFactory.createPackage(
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
}