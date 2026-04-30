/**
 * InvoiceDetailViewControllerTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Coverage target: 99%+
 *
 * Formula fields on Application__c (Customer_First_Name__c, Customer_Last_Name__c,
 * Customer_Address__c, Vehicle_VIN__c, Vehicle_Year__c, Vehicle_Make__c,
 * Vehicle_Model__c, Odometer__c, Odometer_Unit__c) are NOT writable.
 * They resolve automatically via Customer_Name__c (Person Account) and
 * Vehicle__c lookups. Tests link those lookups instead of setting fields directly.
 *
 * Removed tests that are unreachable through writable fields:
 *   • testGetInvoiceDetail_odometerUnitDefaultsToKM_whenNull
 *   • testGetInvoiceDetail_customerFirstNameOnly_noTrailingSpace
 *   • testGetInvoiceDetail_customerLastNameOnly_noLeadingSpace
 *   • testGetInvoiceDetail_vehicleInfoMakeOnly_noSlashPadding
 */
@isTest
private class InvoiceDetailViewControllerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // SHARED SETUP HELPERS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Minimal chain — no vehicle or customer linked to Application.
     * Formula fields will be null → tests null/empty branches.
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
     * Full chain — links Vehicle__c and Customer_Name__c (Person Account)
     * so all formula fields resolve naturally through the lookups.
     *   Dealer → Application (Vehicle + Customer linked) → Invoice
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
     * Tests hasRemittanceForm=true, dealerName, and billTo fields.
     */
    private static Map<String, SObject> setupInvoiceWithRemittance() {
        Account            dealer = TestDataFactory.createDealer(true);
        Application__c     app    = TestDataFactory.createApplicationWithDetails(dealer.Id, true);
        Remittance_Form__c rf     = TestDataFactory.createDealerRemittanceForm(dealer.Id, true);
        Invoice__c         inv    = TestDataFactory.createInvoiceLinkedToRF(
                                        app.Id, rf.Id, 'INV-TEST-001', true
                                    );
        return new Map<String, SObject>{
            'dealer'         => dealer,
            'application'    => app,
            'remittanceForm' => rf,
            'invoice'        => inv
        };
    }

    /**
     * Full package hierarchy for line item and package coverage.
     *   Dealer → Application (with details) → Invoice
     *          → Package hierarchy → Application_Package__c → Invoice_Line_Item__c
     */
    private static Map<String, SObject> setupInvoiceWithLineItemAndPackage() {
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
    // SECTION 1 — WRAPPER CLASS COVERAGE
    // Every @AuraEnabled property on every inner class touched.
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testInvoiceDetailDataWrapper_allPropertiesGetAndSet() {
        InvoiceDetailViewController.InvoiceDetailData d =
            new InvoiceDetailViewController.InvoiceDetailData();
        d.invoiceId           = 'invId';
        d.invoiceName         = 'INV-001';
        d.invoiceStatus       = 'Due';
        d.invoiceDate         = 'Jan 01, 2025';
        d.hasRemittanceForm   = true;
        d.dealerName          = 'Test Dealer';
        d.billTo              = 'Bill To Name';
        d.applicationId       = 'APP-001';
        d.applicationRecordId = 'recId';
        d.customerFullName    = 'John Smith';
        d.customerAddress     = '123 Main St';
        d.vehicleInfo         = '2022/Toyota/Camry';
        d.vin                 = '1HGBH41JXMN109186';
        d.odometer            = 15000;
        d.odometerUnit        = 'KM';
        d.packages            = new List<InvoiceDetailViewController.PackageData>();
        d.totalAmount         = 1500.00;
        d.packageCount        = 2;

        System.assertEquals('invId',              d.invoiceId,           'invoiceId should match');
        System.assertEquals('INV-001',            d.invoiceName,         'invoiceName should match');
        System.assertEquals('Due',                d.invoiceStatus,       'invoiceStatus should match');
        System.assertEquals('Jan 01, 2025',       d.invoiceDate,         'invoiceDate should match');
        System.assertEquals(true,                 d.hasRemittanceForm,   'hasRemittanceForm should match');
        System.assertEquals('Test Dealer',        d.dealerName,          'dealerName should match');
        System.assertEquals('Bill To Name',       d.billTo,              'billTo should match');
        System.assertEquals('APP-001',            d.applicationId,       'applicationId should match');
        System.assertEquals('recId',              d.applicationRecordId, 'applicationRecordId should match');
        System.assertEquals('John Smith',         d.customerFullName,    'customerFullName should match');
        System.assertEquals('123 Main St',        d.customerAddress,     'customerAddress should match');
        System.assertEquals('2022/Toyota/Camry',  d.vehicleInfo,         'vehicleInfo should match');
        System.assertEquals('1HGBH41JXMN109186',  d.vin,                 'vin should match');
        System.assertEquals(15000,                d.odometer,            'odometer should match');
        System.assertEquals('KM',                 d.odometerUnit,        'odometerUnit should match');
        System.assertEquals(1500.00,              d.totalAmount,         'totalAmount should match');
        System.assertEquals(2,                    d.packageCount,        'packageCount should match');
    }

    @isTest
    static void testPackageDataWrapper_allPropertiesGetAndSet() {
        InvoiceDetailViewController.PackageData pd =
            new InvoiceDetailViewController.PackageData();
        pd.packageId      = 'pkgId';
        pd.recordTypeName = 'Extended Limited Warranty';
        pd.packageName    = 'Test Package';
        pd.packageTerm    = '24 Months';
        pd.startDate      = '01-01-2023';
        pd.expiryDate     = '01-01-2025';
        pd.startOdometer  = 10000;
        pd.expiryOdometer = 50000;
        pd.lineItems      = new List<InvoiceDetailViewController.LineItemData>();

        System.assertEquals('pkgId',                     pd.packageId,      'packageId should match');
        System.assertEquals('Extended Limited Warranty',  pd.recordTypeName, 'recordTypeName should match');
        System.assertEquals('Test Package',              pd.packageName,    'packageName should match');
        System.assertEquals('24 Months',                 pd.packageTerm,    'packageTerm should match');
        System.assertEquals('01-01-2023',                pd.startDate,      'startDate should match');
        System.assertEquals('01-01-2025',                pd.expiryDate,     'expiryDate should match');
        System.assertEquals(10000,                       pd.startOdometer,  'startOdometer should match');
        System.assertEquals(50000,                       pd.expiryOdometer, 'expiryOdometer should match');
        System.assertNotEquals(null,                     pd.lineItems,      'lineItems should be set');
    }

    @isTest
    static void testLineItemDataWrapper_allPropertiesGetAndSet() {
        InvoiceDetailViewController.LineItemData ld =
            new InvoiceDetailViewController.LineItemData();
        ld.lineItemId = 'liId';
        ld.status     = 'Due';
        ld.amount     = 500.00;

        System.assertEquals('liId',  ld.lineItemId, 'lineItemId should match');
        System.assertEquals('Due',   ld.status,     'status should match');
        System.assertEquals(500.00,  ld.amount,     'amount should match');
    }

    @isTest
    static void testOperationResult_twoParamConstructor() {
        InvoiceDetailViewController.OperationResult r =
            new InvoiceDetailViewController.OperationResult(true, 'All good');

        System.assertEquals(true,       r.success,          'success should be true');
        System.assertEquals('All good', r.message,          'message should match');
        System.assertEquals(null,       r.remittanceFormId, 'remittanceFormId should be null');
    }

    @isTest
    static void testOperationResult_threeParamConstructor() {
        InvoiceDetailViewController.OperationResult r =
            new InvoiceDetailViewController.OperationResult(true, 'Created', 'rfId123');

        System.assertEquals(true,      r.success,          'success should be true');
        System.assertEquals('Created', r.message,          'message should match');
        System.assertEquals('rfId123', r.remittanceFormId, 'remittanceFormId should match');
    }

    @isTest
    static void testOperationResult_failureCase() {
        InvoiceDetailViewController.OperationResult r =
            new InvoiceDetailViewController.OperationResult(false, 'Something failed');

        System.assertEquals(false,             r.success, 'success should be false');
        System.assertEquals('Something failed', r.message, 'message should match');
    }

    @isTest
    static void testPDFDownloadResponseWrapper_allPropertiesGetAndSet() {
        InvoiceDetailViewController.PDFDownloadResponse r =
            new InvoiceDetailViewController.PDFDownloadResponse();
        r.success  = true;
        r.message  = 'PDF ready';
        r.pdfData  = 'base64data==';
        r.fileName = 'Invoice_001.pdf';

        System.assertEquals(true,              r.success,  'success should match');
        System.assertEquals('PDF ready',       r.message,  'message should match');
        System.assertEquals('base64data==',    r.pdfData,  'pdfData should match');
        System.assertEquals('Invoice_001.pdf', r.fileName, 'fileName should match');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 2 — getInvoiceDetail ERROR PATHS
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetInvoiceDetail_blankIdThrowsAuraHandledException() {
        Boolean thrown = false;
        Test.startTest();
        try {
            InvoiceDetailViewController.getInvoiceDetail('');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();
        System.assert(thrown, 'Blank invoiceId should throw AuraHandledException');
    }

    @isTest
    static void testGetInvoiceDetail_nullIdThrowsAuraHandledException() {
        Boolean thrown = false;
        Test.startTest();
        try {
            InvoiceDetailViewController.getInvoiceDetail(null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();
        System.assert(thrown, 'Null invoiceId should throw AuraHandledException');
    }

    @isTest
    static void testGetInvoiceDetail_invoiceNotFoundThrowsAuraHandledException() {
        // Well-formed 18-char Id that does not exist → SOQL empty → throw
        Boolean thrown = false;
        Test.startTest();
        try {
            InvoiceDetailViewController.getInvoiceDetail('a0000000000000ZAAQ');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();
        System.assert(thrown, 'Non-existent invoiceId should throw AuraHandledException');
    }

    @isTest
    static void testGetInvoiceDetail_invalidFormatIdHitsExceptionCatch() {
        // Malformed string → SOQL throws QueryException / Exception
        // → caught and re-thrown as AuraHandledException
        Boolean thrown = false;
        Test.startTest();
        try {
            InvoiceDetailViewController.getInvoiceDetail('TOTALLY_INVALID_ID');
        } catch (AuraHandledException e) {
            thrown = true;
            System.assertNotEquals(null, e.getMessage(),
                'Exception message should be populated');
        }
        Test.stopTest();
        System.assert(thrown,
            'Malformed ID should trigger catch block → AuraHandledException');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 3 — getInvoiceDetail SUCCESS PATHS
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetInvoiceDetail_basicSuccess_topLevelFieldsReturned() {
        Map<String, SObject> chain = setupMinimalInvoice();
        Invoice__c inv = (Invoice__c) chain.get('invoice');

        Test.startTest();
            InvoiceDetailViewController.InvoiceDetailData result =
                InvoiceDetailViewController.getInvoiceDetail(inv.Id);
        Test.stopTest();

        System.assertNotEquals(null, result,
            'Result should not be null');
        System.assertEquals(String.valueOf(inv.Id), result.invoiceId,
            'invoiceId should match queried invoice');
        System.assertNotEquals(null, result.invoiceName,
            'invoiceName should be populated');
        System.assertEquals('Due', result.invoiceStatus,
            'invoiceStatus should be Due');
        System.assertNotEquals(null, result.invoiceDate,
            'invoiceDate should be formatted from CreatedDate');
        System.assertEquals(false, result.hasRemittanceForm,
            'hasRemittanceForm should be false when no RF linked');
        System.assertNotEquals(null, result.packages,
            'packages list should not be null');
        System.assertEquals(0, result.packageCount,
            'packageCount should be 0 when no line items');
        System.assertEquals(0, result.totalAmount,
            'totalAmount should be 0 when no line items');
    }

    @isTest
    static void testGetInvoiceDetail_noVehicleNoCustomer_formulaFieldsNull() {
        // Minimal application — no Vehicle__c, no Customer_Name__c
        // All formula fields null → customerFullName = '', vehicleInfo = ''
        Map<String, SObject> chain = setupMinimalInvoice();
        Invoice__c inv = (Invoice__c) chain.get('invoice');

        Test.startTest();
            InvoiceDetailViewController.InvoiceDetailData result =
                InvoiceDetailViewController.getInvoiceDetail(inv.Id);
        Test.stopTest();

        System.assertEquals('', result.customerFullName,
            'customerFullName should be empty string when Customer_Name__c is null');
        System.assertEquals('', result.vehicleInfo,
            'vehicleInfo should be empty string when Vehicle__c is null');
        System.assertEquals(null, result.vin,
            'vin should be null when Vehicle__c is not linked');
    }

    @isTest
    static void testGetInvoiceDetail_withVehicleAndCustomer_formulaFieldsPopulated() {
        // createApplicationWithDetails links Vehicle__c and Customer_Name__c
        // so all formula fields resolve automatically
        Map<String, SObject> chain = setupDetailedInvoice();
        Invoice__c inv = (Invoice__c) chain.get('invoice');

        Test.startTest();
            InvoiceDetailViewController.InvoiceDetailData result =
                InvoiceDetailViewController.getInvoiceDetail(inv.Id);
        Test.stopTest();

        // Customer formula fields resolve from Person Account FirstName/LastName
        System.assertNotEquals(null, result.customerFullName,
            'customerFullName should be populated when Customer_Name__c is linked');
        System.assertNotEquals('', result.customerFullName,
            'customerFullName should not be empty when Person Account is linked');
    }

    @isTest
    static void testGetInvoiceDetail_customerNameJoined_firstAndLastFromPersonAccount() {
        // Link a Person Account — FirstName/LastName drive the formula fields
        Account dealer   = TestDataFactory.createDealer(true);
        Account customer = TestDataFactory.createCustomerAccount(true);

        // Re-query to get exact names set by factory
        customer = [SELECT FirstName, LastName FROM Account WHERE Id = :customer.Id];

        Application__c app = TestDataFactory.createApplication(dealer.Id, true);
        app.Customer_Name__c = customer.Id;
        update app;

        Invoice__c inv = TestDataFactory.createInvoice(app.Id, true);

        Test.startTest();
            InvoiceDetailViewController.InvoiceDetailData result =
                InvoiceDetailViewController.getInvoiceDetail(inv.Id);
        Test.stopTest();

        // Controller: (fn + ' ' + ln).trim()
        String expected = (customer.FirstName + ' ' + customer.LastName).trim();
        System.assertEquals(expected, result.customerFullName,
            'customerFullName should combine Person Account FirstName + LastName');
    }

    @isTest
    static void testGetInvoiceDetail_vehicleLinked_vehicleInfoBuiltFromFormulas() {
        // Link only a Vehicle — no Customer
        Account        dealer  = TestDataFactory.createDealer(true);
        Vehicle__c     vehicle = TestDataFactory.createVehicle(true);
        Application__c app     = TestDataFactory.createApplication(dealer.Id, true);
        app.Vehicle__c = vehicle.Id;
        update app;

        Invoice__c inv = TestDataFactory.createInvoice(app.Id, true);

        Test.startTest();
            InvoiceDetailViewController.InvoiceDetailData result =
                InvoiceDetailViewController.getInvoiceDetail(inv.Id);
        Test.stopTest();

        System.assertNotEquals('', result.vehicleInfo,
            'vehicleInfo should not be empty when Vehicle__c is linked');
        System.assertNotEquals(null, result.vehicleInfo,
            'vehicleInfo should not be null when Vehicle__c is linked');
        System.assert(result.vehicleInfo.contains('Toyota'),
            'vehicleInfo should contain Make (Toyota) from Vehicle__c');
        System.assert(result.vehicleInfo.contains('Camry'),
            'vehicleInfo should contain Model (Camry) from Vehicle__c');
    }

    @isTest
    static void testGetInvoiceDetail_withRemittanceForm_hasRemittanceFormTrue() {
        Map<String, SObject> chain = setupInvoiceWithRemittance();
        Invoice__c           inv   = (Invoice__c) chain.get('invoice');

        Test.startTest();
            InvoiceDetailViewController.InvoiceDetailData result =
                InvoiceDetailViewController.getInvoiceDetail(inv.Id);
        Test.stopTest();

        System.assertEquals(true, result.hasRemittanceForm,
            'hasRemittanceForm should be true when RF is linked to Invoice');
        System.assertNotEquals(null, result.dealerName,
            'dealerName should be populated from Remittance_Form__r.Dealer_Name__r.Name');
    }

    @isTest
    static void testGetInvoiceDetail_withLineItemAndPackage_packageDataBuilt() {
        Map<String, SObject> chain = setupInvoiceWithLineItemAndPackage();
        Invoice__c           inv   = (Invoice__c) chain.get('invoice');

        Test.startTest();
            InvoiceDetailViewController.InvoiceDetailData result =
                InvoiceDetailViewController.getInvoiceDetail(inv.Id);
        Test.stopTest();

        System.assertEquals(1, result.packages.size(),
            'Should have 1 package in result');
        System.assertEquals(1, result.packageCount,
            'packageCount should be 1');

        InvoiceDetailViewController.PackageData pd = result.packages[0];
        System.assertNotEquals(null, pd.packageId,
            'packageId should be populated');
        System.assertNotEquals(null, pd.lineItems,
            'lineItems should not be null');
        System.assertEquals(1, pd.lineItems.size(),
            'Should have 1 line item under the package');

        InvoiceDetailViewController.LineItemData ld = pd.lineItems[0];
        System.assertNotEquals(null, ld.lineItemId,
            'lineItemId should be populated');
        System.assertEquals('Due', ld.status,
            'Line item status should be Due');
    }

    @isTest
    static void testGetInvoiceDetail_lineItemNullPackage_notAddedToPackageMap() {
        // Line item with no Application_Package__c → excluded from pkgToLineItems
        // grandTotal += 0 because Contract_Cost_Price__c is null
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);
        Invoice__c     inv    = TestDataFactory.createInvoice(app.Id, true);

        insert new Invoice_Line_Item__c(Invoice__c = inv.Id, Status__c = 'Due');

        Test.startTest();
            InvoiceDetailViewController.InvoiceDetailData result =
                InvoiceDetailViewController.getInvoiceDetail(inv.Id);
        Test.stopTest();

        System.assertEquals(0, result.totalAmount,
            'totalAmount should be 0 when Contract_Cost_Price__c is null');
        System.assertEquals(0, result.packages.size(),
            'No packages should appear when line item has no Application_Package__c');
    }

    @isTest
    static void testGetInvoiceDetail_packageContractDatesNull_startExpiryDateNull() {
        Map<String, SObject>   chain  = setupInvoiceWithLineItemAndPackage();
        Invoice__c             inv    = (Invoice__c)             chain.get('invoice');
        Application_Package__c appPkg = (Application_Package__c) chain.get('appPackage');

        appPkg.Contract_Start_Date__c = null;
        appPkg.Contract_End_Date__c   = null;
        update appPkg;

        Test.startTest();
            InvoiceDetailViewController.InvoiceDetailData result =
                InvoiceDetailViewController.getInvoiceDetail(inv.Id);
        Test.stopTest();

        System.assertEquals(1, result.packages.size(),
            'Should have 1 package');
        System.assertEquals(null, result.packages[0].startDate,
            'startDate should be null when Contract_Start_Date__c is null');
        System.assertEquals(null, result.packages[0].expiryDate,
            'expiryDate should be null when Contract_End_Date__c is null');
    }

    @isTest
    static void testGetInvoiceDetail_packageContractDatesSet_formattedAsDDMMYYYY() {
        Map<String, SObject>   chain  = setupInvoiceWithLineItemAndPackage();
        Invoice__c             inv    = (Invoice__c)             chain.get('invoice');
        Application_Package__c appPkg = (Application_Package__c) chain.get('appPackage');

        appPkg.Contract_Start_Date__c = Date.newInstance(2023, 1, 15);
        appPkg.Contract_End_Date__c   = Date.newInstance(2025, 6, 30);
        update appPkg;

        Test.startTest();
            InvoiceDetailViewController.InvoiceDetailData result =
                InvoiceDetailViewController.getInvoiceDetail(inv.Id);
        Test.stopTest();

        System.assertEquals(1, result.packages.size(),
            'Should have 1 package');
        System.assertEquals('15-01-2023', result.packages[0].startDate,
            'startDate should be formatted as dd-MM-yyyy');
        System.assertEquals('30-06-2025', result.packages[0].expiryDate,
            'expiryDate should be formatted as dd-MM-yyyy');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 4 — submitCancellationRequest
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testSubmitCancellation_blankInvoiceIdReturnsFailure() {
        Test.startTest();
            InvoiceDetailViewController.OperationResult result =
                InvoiceDetailViewController.submitCancellationRequest(
                    '', null, 'Some reason'
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Blank invoiceId should return failure');
        System.assert(result.message.contains('Invoice ID is required'),
            'Message should indicate Invoice ID required');
    }

    @isTest
    static void testSubmitCancellation_blankReasonReturnsFailure() {
        Test.startTest();
            InvoiceDetailViewController.OperationResult result =
                InvoiceDetailViewController.submitCancellationRequest(
                    'someId', null, ''
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Blank reason should return failure');
        System.assert(result.message.contains('Cancellation reason is required'),
            'Message should indicate reason is required');
    }

    @isTest
    static void testSubmitCancellation_nullReasonReturnsFailure() {
        Test.startTest();
            InvoiceDetailViewController.OperationResult result =
                InvoiceDetailViewController.submitCancellationRequest(
                    'someId', null, null
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Null reason should return failure');
        System.assert(result.message.contains('Cancellation reason is required'),
            'Message should indicate reason is required');
    }

    @isTest
    static void testSubmitCancellation_invoiceNotFoundReturnsFailure() {
        Test.startTest();
            InvoiceDetailViewController.OperationResult result =
                InvoiceDetailViewController.submitCancellationRequest(
                    'a0000000000000ZAAQ', null, 'Test reason'
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Non-existent invoiceId should return failure');
        System.assert(result.message.contains('Invoice not found'),
            'Message should indicate invoice not found');
    }

    @isTest
    static void testSubmitCancellation_invoiceLevelAlreadyCancelledReturnsFailure() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);
        Invoice__c     inv    = TestDataFactory.createInvoice(app.Id, true);
        inv.Status__c = 'Cancelled';
        update inv;

        Test.startTest();
            InvoiceDetailViewController.OperationResult result =
                InvoiceDetailViewController.submitCancellationRequest(
                    inv.Id, null, 'Reason'
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Invoice already cancelled should return failure');
        System.assert(result.message.contains('already cancelled'),
            'Message should indicate invoice is already cancelled');
    }

    @isTest
    static void testSubmitCancellation_invoiceLevelSuccess_noLineItems() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);
        Invoice__c     inv    = TestDataFactory.createInvoice(app.Id, true);

        Test.startTest();
            InvoiceDetailViewController.OperationResult result =
                InvoiceDetailViewController.submitCancellationRequest(
                    inv.Id, null, 'Customer cancellation request'
                );
        Test.stopTest();

        System.assertEquals(true, result.success,
            'Invoice-level cancellation with no line items should succeed');
        System.assert(result.message.contains('successfully'),
            'Success message should confirm submission');

        List<Cancellation__c> created = [
            SELECT Cancellation_Type__c, Cancellation_Status__c,
                   Invoice_Status_At_Request__c
            FROM   Cancellation__c
            WHERE  Invoice__c = :inv.Id
        ];
        System.assertEquals(1, created.size(),
            'Exactly one invoice-level Cancellation__c should be created');
        System.assertEquals('Invoice', created[0].Cancellation_Type__c,
            'Cancellation type should be Invoice');
        System.assertEquals('Pending', created[0].Cancellation_Status__c,
            'Cancellation status should be Pending');
    }

    @isTest
    static void testSubmitCancellation_invoiceLevelSuccess_withLineItems_createsLineItemCancellations() {
        Map<String, SObject> chain    = setupInvoiceWithLineItemAndPackage();
        Invoice__c           inv      = (Invoice__c)           chain.get('invoice');
        Invoice_Line_Item__c lineItem = (Invoice_Line_Item__c) chain.get('lineItem');

        Test.startTest();
            InvoiceDetailViewController.OperationResult result =
                InvoiceDetailViewController.submitCancellationRequest(
                    inv.Id, null, 'Full invoice cancellation'
                );
        Test.stopTest();

        System.assertEquals(true, result.success,
            'Invoice-level cancellation with line items should succeed');

        // 1 invoice cancellation + 1 auto-created line item cancellation = 2
        List<Cancellation__c> all = [
            SELECT Cancellation_Type__c, Invoice_Line_Item__c,
                   Cancellation_Reason__c
            FROM   Cancellation__c
            WHERE  Invoice__c = :inv.Id
        ];
        System.assertEquals(2, all.size(),
            'Should create 1 invoice cancellation + 1 line item cancellation');

        Cancellation__c liCancellation = null;
        for (Cancellation__c c : all) {
            if (c.Cancellation_Type__c == 'Invoice Line Item') liCancellation = c;
        }
        System.assertNotEquals(null, liCancellation,
            'A line item cancellation should be auto-created');
        System.assertEquals(lineItem.Id, liCancellation.Invoice_Line_Item__c,
            'Line item cancellation should reference the correct Invoice_Line_Item__c');
        System.assert(liCancellation.Cancellation_Reason__c.contains('Auto-created'),
            'Auto-created reason should indicate its source');
    }

    @isTest
    static void testSubmitCancellation_lineItemNotFoundReturnsFailure() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);
        Invoice__c     inv    = TestDataFactory.createInvoice(app.Id, true);

        Test.startTest();
            InvoiceDetailViewController.OperationResult result =
                InvoiceDetailViewController.submitCancellationRequest(
                    inv.Id, 'a0000000000000ZAAQ', 'Some reason'
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Non-existent lineItemId should return failure');
        System.assert(result.message.contains('line item not found'),
            'Message should indicate line item not found');
    }

    @isTest
    static void testSubmitCancellation_lineItemAlreadyCancelledReturnsFailure() {
        Map<String, SObject> chain    = setupInvoiceWithLineItemAndPackage();
        Invoice__c           inv      = (Invoice__c)           chain.get('invoice');
        Invoice_Line_Item__c lineItem = (Invoice_Line_Item__c) chain.get('lineItem');

        lineItem.Status__c = 'Cancelled';
        update lineItem;

        Test.startTest();
            InvoiceDetailViewController.OperationResult result =
                InvoiceDetailViewController.submitCancellationRequest(
                    inv.Id, lineItem.Id, 'Test reason'
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Already-cancelled line item should return failure');
        System.assert(result.message.contains('already cancelled'),
            'Message should indicate line item is already cancelled');
    }

    @isTest
    static void testSubmitCancellation_lineItemLevelSuccess_createsLineItemCancellation() {
        Map<String, SObject> chain    = setupInvoiceWithLineItemAndPackage();
        Invoice__c           inv      = (Invoice__c)           chain.get('invoice');
        Invoice_Line_Item__c lineItem = (Invoice_Line_Item__c) chain.get('lineItem');

        Test.startTest();
            InvoiceDetailViewController.OperationResult result =
                InvoiceDetailViewController.submitCancellationRequest(
                    inv.Id, lineItem.Id, 'Individual line item cancellation'
                );
        Test.stopTest();

        System.assertEquals(true, result.success,
            'Line item-level cancellation should succeed');
        System.assert(result.message.contains('successfully'),
            'Success message should confirm submission');

        List<Cancellation__c> created = [
            SELECT Cancellation_Type__c, Invoice_Line_Item__c,
                   Line_Item_Status_At_Request__c, Cancellation_Reason__c
            FROM   Cancellation__c
            WHERE  Invoice__c = :inv.Id
        ];
        System.assertEquals(1, created.size(),
            'Exactly one Cancellation__c should be created for line item request');
        System.assertEquals('Invoice Line Item', created[0].Cancellation_Type__c,
            'Cancellation type should be Invoice Line Item');
        System.assertEquals(lineItem.Id, created[0].Invoice_Line_Item__c,
            'Cancellation should reference the correct line item');
        System.assertNotEquals(null, created[0].Line_Item_Status_At_Request__c,
            'Line item status at time of request should be captured');
        System.assertEquals('Individual line item cancellation',
            created[0].Cancellation_Reason__c,
            'Cancellation reason should match the provided reason');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 5 — createRemittanceForInvoice
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testCreateRemittanceForInvoice_blankIdReturnsFailure() {
        Test.startTest();
            InvoiceDetailViewController.OperationResult result =
                InvoiceDetailViewController.createRemittanceForInvoice('');
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Blank invoiceId should return failure');
        System.assert(result.message.contains('Invoice ID is required'),
            'Message should indicate Invoice ID required');
    }

    @isTest
    static void testCreateRemittanceForInvoice_invoiceNotFoundReturnsFailure() {
        Test.startTest();
            InvoiceDetailViewController.OperationResult result =
                InvoiceDetailViewController.createRemittanceForInvoice('a0000000000000ZAAQ');
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Non-existent invoiceId should return failure');
        System.assert(result.message.contains('Invoice not found'),
            'Message should indicate invoice not found');
    }

    @isTest
    static void testCreateRemittanceForInvoice_alreadyPaidReturnsFailure() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);
        Invoice__c     inv    = TestDataFactory.createInvoice(app.Id, true);
        inv.Status__c = 'Paid';
        update inv;

        Test.startTest();
            InvoiceDetailViewController.OperationResult result =
                InvoiceDetailViewController.createRemittanceForInvoice(inv.Id);
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Paid invoice should return failure');
        System.assert(result.message.contains('already been paid'),
            'Message should indicate invoice is already paid');
    }

    @isTest
    static void testCreateRemittanceForInvoice_alreadyCancelledReturnsFailure() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);
        Invoice__c     inv    = TestDataFactory.createInvoice(app.Id, true);
        inv.Status__c = 'Cancelled';
        update inv;

        Test.startTest();
            InvoiceDetailViewController.OperationResult result =
                InvoiceDetailViewController.createRemittanceForInvoice(inv.Id);
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Cancelled invoice should return failure');
        System.assert(result.message.contains('been cancelled'),
            'Message should indicate invoice has been cancelled');
    }

    @isTest
    static void testCreateRemittanceForInvoice_success_remittanceFormCreatedAndLinked() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);
        Invoice__c     inv    = TestDataFactory.createInvoice(app.Id, true);

        Test.startTest();
            InvoiceDetailViewController.OperationResult result =
                InvoiceDetailViewController.createRemittanceForInvoice(inv.Id);
        Test.stopTest();

        System.assertEquals(true, result.success,
            'createRemittanceForInvoice should succeed for a valid Due invoice');
        System.assertNotEquals(null, result.remittanceFormId,
            'remittanceFormId should be returned on success');
        System.assert(result.message.contains('successfully'),
            'Success message should confirm creation');

        Remittance_Form__c rf = [
            SELECT Status__c, Dealer_Name__c, Receiver_Name__c, Payer_Name__c
            FROM   Remittance_Form__c
            WHERE  Id = :result.remittanceFormId
        ];
        System.assertEquals('Open',      rf.Status__c,        'RF status should be Open');
        System.assertEquals(dealer.Id,   rf.Dealer_Name__c,   'RF should be linked to dealer');
        System.assertEquals('A-Protect', rf.Receiver_Name__c, 'Receiver name should be A-Protect');
    }

    @isTest
    static void testCreateRemittanceForInvoice_success_invoiceLinkedToNewRF() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);
        Invoice__c     inv    = TestDataFactory.createInvoice(app.Id, true);

        Test.startTest();
            InvoiceDetailViewController.OperationResult result =
                InvoiceDetailViewController.createRemittanceForInvoice(inv.Id);
        Test.stopTest();

        Invoice__c updated = [SELECT Remittance_Form__c FROM Invoice__c WHERE Id = :inv.Id];
        System.assertEquals(result.remittanceFormId, updated.Remittance_Form__c,
            'Invoice should be linked to the newly created RF');
    }

    @isTest
    static void testCreateRemittanceForInvoice_success_applicationLinkedToNewRF() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);
        Invoice__c     inv    = TestDataFactory.createInvoice(app.Id, true);

        Test.startTest();
            InvoiceDetailViewController.OperationResult result =
                InvoiceDetailViewController.createRemittanceForInvoice(inv.Id);
        Test.stopTest();

        Application__c updated = [
            SELECT Remittance_Form__c FROM Application__c WHERE Id = :app.Id
        ];
        System.assertEquals(result.remittanceFormId, updated.Remittance_Form__c,
            'Application should be linked to the newly created RF');
    }

    @isTest
    static void testCreateRemittanceForInvoice_withUnpaidLineItems_junctionsCreated() {
        Map<String, SObject> chain = setupInvoiceWithLineItemAndPackage();
        Invoice__c           inv   = (Invoice__c) chain.get('invoice');

        Test.startTest();
            InvoiceDetailViewController.OperationResult result =
                InvoiceDetailViewController.createRemittanceForInvoice(inv.Id);
        Test.stopTest();

        System.assertEquals(true, result.success,
            'Should succeed with unpaid line items');

        List<Remittance_Line_Item_Junction__c> junctions = [
            SELECT Payment_Status__c, Invoice__c, Remittance_Form__c
            FROM   Remittance_Line_Item_Junction__c
            WHERE  Remittance_Form__c = :result.remittanceFormId
        ];
        System.assertEquals(1, junctions.size(),
            'One junction should be created for the one unpaid line item');
        System.assertEquals('Planned', junctions[0].Payment_Status__c,
            'Junction Payment_Status__c should be Planned');
        System.assertEquals(inv.Id, junctions[0].Invoice__c,
            'Junction should reference the invoice');
    }

    @isTest
    static void testCreateRemittanceForInvoice_staleJunctionsDeletedBeforeNew() {
        Map<String, SObject> chain    = setupInvoiceWithLineItemAndPackage();
        Invoice__c           inv      = (Invoice__c)           chain.get('invoice');
        Invoice_Line_Item__c lineItem = (Invoice_Line_Item__c) chain.get('lineItem');
        Account              dealer   = (Account)              chain.get('dealer');

        // Simulate a stale Planned junction from a prior remittance attempt
        Remittance_Form__c              oldRf     = TestDataFactory.createRemittanceForm(
                                                        dealer.Id, true
                                                    );
        Remittance_Line_Item_Junction__c staleRLJ = TestDataFactory.createRLJ(
                                                        oldRf.Id, inv.Id, lineItem.Id, true
                                                    );
        System.assertEquals('Planned', staleRLJ.Payment_Status__c,
            'Pre-condition: stale junction should be Planned');

        Test.startTest();
            InvoiceDetailViewController.OperationResult result =
                InvoiceDetailViewController.createRemittanceForInvoice(inv.Id);
        Test.stopTest();

        System.assertEquals(true, result.success,
            'Should succeed even with a pre-existing stale junction');

        // Stale junction must be deleted
        List<Remittance_Line_Item_Junction__c> remaining = [
            SELECT Id FROM Remittance_Line_Item_Junction__c WHERE Id = :staleRLJ.Id
        ];
        System.assertEquals(0, remaining.size(),
            'Stale Planned junction should be deleted');

        // Fresh junction must exist on the new RF
        List<Remittance_Line_Item_Junction__c> fresh = [
            SELECT Id FROM Remittance_Line_Item_Junction__c
            WHERE  Remittance_Form__c = :result.remittanceFormId
        ];
        System.assertEquals(1, fresh.size(),
            'A new junction should be created on the new Remittance Form');
    }

    @isTest
    static void testCreateRemittanceForInvoice_paidLineItemExcludedFromJunctions() {
        Map<String, SObject> chain    = setupInvoiceWithLineItemAndPackage();
        Invoice__c           inv      = (Invoice__c)           chain.get('invoice');
        Invoice_Line_Item__c lineItem = (Invoice_Line_Item__c) chain.get('lineItem');

        lineItem.Status__c = 'Paid';
        update lineItem;

        Test.startTest();
            InvoiceDetailViewController.OperationResult result =
                InvoiceDetailViewController.createRemittanceForInvoice(inv.Id);
        Test.stopTest();

        System.assertEquals(true, result.success,
            'Should succeed when all line items are Paid');

        List<Remittance_Line_Item_Junction__c> junctions = [
            SELECT Id FROM Remittance_Line_Item_Junction__c
            WHERE  Remittance_Form__c = :result.remittanceFormId
        ];
        System.assertEquals(0, junctions.size(),
            'No junctions should be created when all line items are Paid');
    }

    @isTest
    static void testCreateRemittanceForInvoice_noLineItems_rfStillCreated() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);
        Invoice__c     inv    = TestDataFactory.createInvoice(app.Id, true);

        Test.startTest();
            InvoiceDetailViewController.OperationResult result =
                InvoiceDetailViewController.createRemittanceForInvoice(inv.Id);
        Test.stopTest();

        System.assertEquals(true, result.success,
            'Should succeed even with no line items');
        System.assertNotEquals(null, result.remittanceFormId,
            'Remittance Form should still be created');
        System.assertEquals(0,
            [SELECT COUNT() FROM Remittance_Line_Item_Junction__c
             WHERE Remittance_Form__c = :result.remittanceFormId],
            'No junctions should be created when there are no line items');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 6 — downloadInvoicePDF
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testDownloadInvoicePDF_invoiceNotFoundReturnsFalse() {
        Test.startTest();
            InvoiceDetailViewController.PDFDownloadResponse result =
                InvoiceDetailViewController.downloadInvoicePDF('a0000000000000ZAAQ');
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Non-existent invoiceId should return failure response');
        System.assert(result.message.contains('Invoice not found'),
            'Message should indicate invoice not found');
        System.assertEquals(null, result.pdfData,
            'pdfData should be null when invoice is not found');
        System.assertEquals(null, result.fileName,
            'fileName should be null when invoice is not found');
    }

    @isTest
    static void testDownloadInvoicePDF_validInvoice_catchBlockHitInTestContext() {
        /**
         * getContentAsPDF() always throws in test context:
         * "Getting content from Visualforce pages is not supported in test methods"
         * → catch block runs → success=false, message prefixed 'Error generating PDF:'
         * This covers both the try body (invoice found) and the catch block.
         */
        Map<String, SObject> chain = setupMinimalInvoice();
        Invoice__c           inv   = (Invoice__c) chain.get('invoice');

        Test.startTest();
            InvoiceDetailViewController.PDFDownloadResponse result =
                InvoiceDetailViewController.downloadInvoicePDF(inv.Id);
        Test.stopTest();

        System.assertEquals(false, result.success,
            'getContentAsPDF() throws in test context — catch block returns failure');
        System.assertNotEquals(null, result.message,
            'Error message should be populated from exception');
        System.assert(result.message.contains('Error generating PDF:'),
            'Message should contain the catch block error prefix');
        System.assertEquals(null, result.pdfData,
            'pdfData should be null in error response');
    }
}