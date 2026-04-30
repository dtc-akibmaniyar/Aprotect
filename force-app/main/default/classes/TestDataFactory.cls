/**
 * TestDataFactory
 * ──────────────────────────────────────────────────────────────────────────────
 * Central factory for ALL test SObject creation across the A-Protect Dealer
 * Portal test suite.  No test class should create SObjects inline — everything
 * goes through this factory.
 *
 * Design rules:
 *   • Every method accepts a Boolean doInsert so callers decide whether to DML.
 *   • Record-type IDs are resolved once via Schema Describe and cached.
 *   • Bulk helpers accept a count parameter and always return a List<SObject>.
 *   • Usernames / community nicknames are made unique per-run with a timestamp
 *     suffix so parallel test executions never collide.
 *   • No SeeAllData=true anywhere — all data is self-contained.
 *
 * Usage pattern:
 *   Account dealer  = TestDataFactory.createDealer(true);
 *   Application__c  = TestDataFactory.createApplication(dealer.Id, true);
 */
@isTest
public class TestDataFactory {

    // ─── RECORD TYPE ID CACHE ────────────────────────────────────────────────────
    // Populated lazily; avoids repeated Schema.getGlobalDescribe() calls.
    private static Map<String, Id> rtCache = new Map<String, Id>();

    /**
     * Resolves a RecordType Id by SObject API name + developer name.
     * Result is cached for the lifetime of the test transaction.
     */
    public static Id getRecordTypeId(String sObjectApiName, String developerName) {
        String cacheKey = sObjectApiName + ':' + developerName;
        if (!rtCache.containsKey(cacheKey)) {
            Map<String, Schema.RecordTypeInfo> rtMap =
                Schema.getGlobalDescribe()
                      .get(sObjectApiName)
                      .getDescribe()
                      .getRecordTypeInfosByDeveloperName();

            if (!rtMap.containsKey(developerName)) {
                throw new TestDataFactoryException(
                    'RecordType [' + developerName + '] not found on [' + sObjectApiName + ']'
                );
            }
            rtCache.put(cacheKey, rtMap.get(developerName).getRecordTypeId());
        }
        return rtCache.get(cacheKey);
    }

    // ─── UNIQUE VALUE GENERATOR ──────────────────────────────────────────────────
    // Appends a millisecond timestamp to prevent collisions between test runs.
    private static Long uniqueSeed = System.currentTimeMillis();

    private static String unique(String prefix) {
        uniqueSeed++;
        return prefix + uniqueSeed;
    }

    private static String uniqueEmail() {
        uniqueSeed++;
        return 'testuser' + uniqueSeed + '@aprotect.test.invalid';
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // SECTION 1 — ACCOUNT / DEALER
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Creates a Dealer_Account record.
     * This is the root object for almost every test scenario.
     */
    public static Account createDealer(Boolean doInsert) {
        Account dealer = new Account(
            Name                = unique('Test Dealer'),
            RecordTypeId        = getRecordTypeId('Account', 'Dealer_Account'),
            Phone               = '416-555-0100',
            BillingStreet       = '123 Main Street',
            BillingCity         = 'Toronto',
            BillingState        = 'ON',
            BillingCountry      = 'Canada',
            BillingPostalCode   = 'M5V 0A1'
        );
        if (doInsert) insert dealer;
        return dealer;
    }

    /**
     * Creates a Customer Account (Person Account) using the 'Customer Account'
     * RecordType.  Used by DealerPortalCustomerController tests that need a person
     * account for Customer_Name__c / Co_Buyer__c lookups on Application__c.
     *
     * Relies on the org having Person Accounts enabled and a RecordType whose
     * DeveloperName is 'PersonAccount'.
     */
    public static Account createCustomerAccount(Boolean doInsert) {
        Account a = new Account(
            FirstName    = 'Test',
            LastName     = unique('Customer'),
            RecordTypeId = getRecordTypeId('Account', 'PersonAccount')
        );
        if (doInsert) insert a;
        return a;
    }

    /**
     * Creates a Financial_Institution Account record.
     * Used for lender-related test scenarios.
     */
    public static Account createFinancialInstitution(Boolean doInsert) {
        Account fi = new Account(
            Name         = unique('Test Financial Institution'),
            RecordTypeId = getRecordTypeId('Account', 'Financial_Institution')
        );
        if (doInsert) insert fi;
        return fi;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // SECTION 2 — PORTAL USER
    // Used with System.runAs() to test sharing and portal-user access patterns.
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Creates a Contact linked to the given Account and then creates a
     * PowerPartner (dealer portal) User linked to that Contact.
     *
     * Usage:
     *   User portalUser = TestDataFactory.createPortalUser(dealer.Id, true);
     *   System.runAs(portalUser) { ... }
     *
     * The profile query targets UserType = 'PowerPartner'. Adjust the SOQL
     * if your sandbox uses a custom Experience Cloud profile name.
     */
    public static User createPortalUser(Id dealerAccountId, Boolean doInsert) {
        String email = uniqueEmail();

        Contact c = new Contact(
            FirstName   = 'Portal',
            LastName    = 'TestUser',
            Email       = email,
            AccountId   = dealerAccountId
        );
        insert c;

        Profile portalProfile = [
            SELECT Id
            FROM   Profile
            WHERE  UserType = 'PowerPartner'
            LIMIT  1
        ];

        User u = new User(
            FirstName           = 'Portal',
            LastName            = 'TestUser',
            Email               = email,
            Username            = email,
            Alias               = 'ptlu',
            CommunityNickname   = unique('ptlu'),
            TimeZoneSidKey      = 'America/Toronto',
            LocaleSidKey        = 'en_US',
            EmailEncodingKey    = 'UTF-8',
            LanguageLocaleKey   = 'en_US',
            ProfileId           = portalProfile.Id,
            ContactId           = c.Id
        );
        if (doInsert) insert u;
        return u;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // SECTION 3 — PACKAGE HIERARCHY  (master/catalogue objects)
    // Package__c → Package_Tier__c → Package_Term__c → Package_Option__c
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Creates a Package__c with the given record type.
     * Valid developer names: Extended_Limited_Warranty, Gap_Coverage,
     *                         Tire_Rim_Protection_Plan, Car_Loan_Protection
     */
    public static Package__c createPackage(String recordTypeDeveloperName, Boolean doInsert) {
        Package__c pkg = new Package__c(
            Name         = unique('Test Package ' + recordTypeDeveloperName),
            RecordTypeId = getRecordTypeId('Package__c', recordTypeDeveloperName),
            Description__c = 'Auto-generated by TestDataFactory'
        );
        if (doInsert) insert pkg;
        return pkg;
    }

    /**
     * Creates a Package_Tier__c linked to a Package__c.
     * Used for loan-protection and GAP coverage hierarchies.
     */
    public static Package_Tier__c createPackageTier(Id packageId, Boolean doInsert) {
        Package_Tier__c tier = new Package_Tier__c(
            Name      = unique('Test Package Tier'),
            Package__c = packageId
        );
        if (doInsert) insert tier;
        return tier;
    }

    /**
     * Creates a Package_Term__c linked to a Package__c.
     * Optionally links to a Package_Tier__c via tierId (pass null to skip).
     */
    public static Package_Term__c createPackageTerm(Id packageId, Id tierId, Boolean doInsert) {
        Package_Term__c term = new Package_Term__c(
            Name         = unique('Test Package Term'),
            Package__c   = packageId,
            Package_Tier__c = tierId,
            Price__c     = 1500.00,
            Month__c     = '24',
            Mileage__c   = 40000,
            Mileage_Unit__c = 'KM'
        );
        if (doInsert) insert term;
        return term;
    }

    /**
     * Creates a Package_Option__c linked to a Package__c.
     * selectionType: 'Included' or 'Optional'
     */
    public static Package_Option__c createPackageOption(Id packageId, Id packageTermId, String selectionType, Boolean doInsert) {
        Package_Option__c opt = new Package_Option__c(
            Package__c        = packageId,
            Package_Term__c   = packageTermId,
            Selection_Type__c = selectionType,
            Price__c          = 100.00
        );
        if (doInsert) insert opt;
        return opt;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // SECTION 4 — DEALER PACKAGE HIERARCHY  (dealer-specific copies)
    // Dealer_Package__c → Dealer_Package_Tier__c → Dealer_Package_Term__c → Dealer_Package_Option__c
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Creates a Dealer_Package__c.
     * Valid record type developer names mirror Package__c except Gap_Coverage
     * maps to Total_Loss_Coverage on Dealer_Package__c.
     *
     * Valid: Extended_Limited_Warranty, Total_Loss_Coverage,
     *        Tire_Rim_Protection_Plan, Car_Loan_Protection
     */
    public static Dealer_Package__c createDealerPackage(
        Id dealerId,
        Id packageId,
        String recordTypeDeveloperName,
        Boolean doInsert
    ) {
        Dealer_Package__c dp = new Dealer_Package__c(
            Name         = unique('Test Dealer Package'),
            Dealer__c    = dealerId,
            Package__c   = packageId,
            RecordTypeId = getRecordTypeId('Dealer_Package__c', recordTypeDeveloperName)
        );
        if (doInsert) insert dp;
        return dp;
    }

    /**
     * Creates a Dealer_Package_Tier__c linked to a Dealer_Package__c.
     * Optionally links to the source Package_Tier__c.
     */
    public static Dealer_Package_Tier__c createDealerPackageTier(
        Id dealerPackageId,
        Id packageTierId,
        Boolean doInsert
    ) {
        Dealer_Package_Tier__c dpt = new Dealer_Package_Tier__c(
            Name               = unique('Test Dealer Tier'),
            Dealer_Package__c  = dealerPackageId,
            Package_Tier__c    = packageTierId
        );
        if (doInsert) insert dpt;
        return dpt;
    }

    /**
     * Creates a Dealer_Package_Term__c.
     * Package_Term__c is a MasterDetail — required.
     * dealerPackageTierId is optional (pass null to skip).
     */
    public static Dealer_Package_Term__c createDealerPackageTerm(
        Id dealerPackageId,
        Id packageTermId,
        Id dealerPackageTierId,
        Boolean doInsert
    ) {
        Dealer_Package_Term__c term = new Dealer_Package_Term__c(
            Name                          = unique('Test Dealer Term'),
            Dealer_Package__c             = dealerPackageId,
            Package_Term__c               = packageTermId,
            Dealer_Package_Tier__c        = dealerPackageTierId,
            Original_Package_Term_Cost__c = 1500.00,
            Month__c                      = '24',
            Mileage__c                    = 40000,
            Mileage_Unit__c               = 'KM'
        );
        if (doInsert) insert term;
        return term;
    }

    /**
     * Creates a Dealer_Package_Option__c.
     * Package_Option__c is a MasterDetail — required.
     * selectionType: 'Included' or 'Optional'
     * dealerPackageTermId is optional (pass null for package-level options).
     */
    public static Dealer_Package_Option__c createDealerPackageOption(
        Id dealerPackageId,
        Id packageOptionId,
        Id dealerPackageTermId,
        String selectionType,
        Boolean doInsert
    ) {
        Dealer_Package_Option__c opt = new Dealer_Package_Option__c(
            Dealer_Package__c                = dealerPackageId,
            Package_Option__c                = packageOptionId,
            Dealer_Package_Term__c           = dealerPackageTermId,
            Selection_Type__c                = selectionType,
            Original_Package_Option_Price__c = 100.00
        );
        if (doInsert) insert opt;
        return opt;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // SECTION 5 — APPLICATION & APPLICATION PACKAGE
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Creates an Application__c with record type Application.
     * Application_Status__c defaults to Draft; Payment_Status__c defaults to Unpaid.
     */
    public static Application__c createApplication(Id dealerId, Boolean doInsert) {
        Application__c app = new Application__c(
            Dealer_Name__c       = dealerId,
            RecordTypeId         = getRecordTypeId('Application__c', 'Application'),
            Application_Status__c = 'Draft',
            Payment_Status__c    = 'Unpaid'
        );
        if (doInsert) insert app;
        return app;
    }

    /**
     * Creates an Application__c with status 'Submitted' (record type Application).
     * Required by AllocationRemittanceHandler.getApplicationsByDealer which hard-filters
     * on Application_Status__c = 'Submitted'.
     */
    public static Application__c createSubmittedApplication(Id dealerId, Boolean doInsert) {
        Application__c app = new Application__c(
            Dealer_Name__c        = dealerId,
            RecordTypeId          = getRecordTypeId('Application__c', 'Application'),
            Application_Status__c = 'Submitted',
            Payment_Status__c     = 'Unpaid'
        );
        if (doInsert) insert app;
        return app;
    }

    /**
     * Creates an Application__c with record type Quote.
     * Application_Status__c defaults to Quote.
     */
    public static Application__c createQuote(Id dealerId, Boolean doInsert) {
        Application__c quote = new Application__c(
            Dealer_Name__c        = dealerId,
            RecordTypeId          = getRecordTypeId('Application__c', 'Quote'),
            Application_Status__c = 'Quote',
            Payment_Status__c     = 'Unpaid'
        );
        if (doInsert) insert quote;
        return quote;
    }

    /**
     * Creates an Application_Package__c linking an Application to a Dealer Package.
     * dealerId must match the Dealer__c on the Dealer_Package__c (active lookup filter).
     * Optionally links to Dealer_Package_Term__c (pass null to skip).
     */
    public static Application_Package__c createApplicationPackage(
        Id applicationId,
        Id dealerPackageId,
        Id dealerPackageTermId,
        Id dealerId,
        Boolean doInsert
    ) {
        Application_Package__c appPkg = new Application_Package__c(
            Application__c         = applicationId,
            Dealer_Package__c      = dealerPackageId,
            Dealer_Package_Term__c = dealerPackageTermId,
            Dealer__c              = dealerId,
            Payment_Status__c      = 'Not Paid'
        );
        if (doInsert) insert appPkg;
        return appPkg;
    }

    /**
     * Creates an Application_Package__c with explicit pricing fields.
     * Use this overload when formula fields (Contract_Cost_Price__c, Tax_Amount__c, etc.)
     * need to return non-null values in tests.
     *
     * dealerPackagePrice — sets Dealer_Package_Price__c (drives Contract_Cost_Price formula)
     * taxPercentage      — sets Tax_Percentage__c (e.g. 13 for 13 %)
     */
    public static Application_Package__c createApplicationPackage(
        Id applicationId,
        Id dealerPackageId,
        Id dealerPackageTermId,
        Id dealerId,
        Decimal dealerPackagePrice,
        Decimal taxPercentage,
        Boolean doInsert
    ) {
        Application_Package__c appPkg = new Application_Package__c(
            Application__c          = applicationId,
            Dealer_Package__c       = dealerPackageId,
            Dealer_Package_Term__c  = dealerPackageTermId,
            Dealer__c               = dealerId,
            Payment_Status__c       = 'Not Paid',
            Dealer_Package_Price__c = dealerPackagePrice,
            Tax_Percentage__c       = taxPercentage
        );
        if (doInsert) insert appPkg;
        return appPkg;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // SECTION 6 — INVOICE & INVOICE LINE ITEMS
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Creates an Invoice__c in Due status.
     * Due date defaults to 30 days from today.
     */
    public static Invoice__c createInvoice(Id applicationId, Boolean doInsert) {
        Invoice__c inv = new Invoice__c(
            Application__c    = applicationId,
            Status__c         = 'Due',
            Amount__c         = 1500.00,
            Invoice_Due_Date__c = Date.today().addDays(30)
        );
        if (doInsert) insert inv;
        return inv;
    }

    /**
     * Creates an Application_Package__c with RecordType, pricing, and Active__c = true.
     * Use this overload when:
     *   - AllocationRemittanceHandler filters by RecordType.DeveloperName IN serviceTypes
     *   - DealerPortalRemittanceHandler.getBulkConfirmationData filters by Active__c = true
     *   - Formula fields (Contract_Cost_Price__c etc.) need to return non-null values
     *
     * recordTypeDeveloperName — must match a valid Application_Package__c RecordType
     *   (Extended_Limited_Warranty, GAP_Coverage, Loan_Protection, Tire_Rim_Protection_Plan)
     */
    public static Application_Package__c createApplicationPackage(
        Id applicationId,
        Id dealerPackageId,
        Id dealerPackageTermId,
        Id dealerId,
        String recordTypeDeveloperName,
        Decimal dealerPackagePrice,
        Decimal taxPercentage,
        Boolean doInsert
    ) {
        Application_Package__c appPkg = new Application_Package__c(
            Application__c          = applicationId,
            Dealer_Package__c       = dealerPackageId,
            Dealer_Package_Term__c  = dealerPackageTermId,
            Dealer__c               = dealerId,
            RecordTypeId            = getRecordTypeId('Application_Package__c', recordTypeDeveloperName),
            Payment_Status__c       = 'Not Paid',
            Active__c               = true,
            Dealer_Package_Price__c = dealerPackagePrice,
            Tax_Percentage__c       = taxPercentage
        );
        if (doInsert) insert appPkg;
        return appPkg;
    }

    /**
     * Creates an Application_Package_Option__c.
     * Use doInsert=false to build an in-memory record for passing to
     * DealerPackageAccessHelper.updateApplicationPackageOptionsWithRecords().
     *
     * dealerPackageOptionId — links the option back to its Dealer_Package_Option__c
     *                          (used by the removal path in the handler)
     * packageOptionId       — required; maps to Package_Option__c on the record
     * selectionType         — typically 'Optional' (removal query filters on this)
     */
    public static Application_Package_Option__c createApplicationPackageOption(
        Id      applicationId,
        Id      applicationPackageId,
        Id      dealerPackageOptionId,
        Id      packageOptionId,
        Boolean doInsert
    ) {
        Application_Package_Option__c opt = new Application_Package_Option__c(
            Application__c           = applicationId,
            Application_Package__c   = applicationPackageId,
            Dealer_Package_Option__c = dealerPackageOptionId,
            Package_Option__c        = packageOptionId
        );
        if (doInsert) insert opt;
        return opt;
    }

    /**
     * Creates an Invoice__c pre-linked to a Remittance_Form__c with a custom Name.
     * Use this when tests need the Invoice.Remittance_Form__c lookup set at creation
     * time (e.g. Dealer_Remittance breakdown tests, deleteInvoice tests) or when a
     * specific Name value is required for deduplication testing.
     */
    public static Invoice__c createInvoiceLinkedToRF(
        Id applicationId,
        Id remittanceFormId,
        String invoiceName,
        Boolean doInsert
    ) {
        Invoice__c inv = new Invoice__c(
            Application__c      = applicationId,
            Remittance_Form__c  = remittanceFormId,
            Status__c           = 'Due',
            Amount__c           = 1200.00,
            Invoice_Due_Date__c = Date.today().addDays(30),
            Name                = invoiceName
        );
        if (doInsert) insert inv;
        return inv;
    }

    /**
     * Creates an overdue Invoice__c (due date in the past).
     * Used for InvoiceOverdueMarkingBatch tests.
     */
    public static Invoice__c createOverdueInvoice(Id applicationId, Boolean doInsert) {
        Invoice__c inv = new Invoice__c(
            Application__c      = applicationId,
            Status__c           = 'Due',
            Amount__c           = 1500.00,
            Invoice_Due_Date__c = Date.today().addDays(-10)
        );
        if (doInsert) insert inv;
        return inv;
    }

    /**
     * Creates an Invoice_Line_Item__c linking an Invoice to an Application_Package__c.
     * Status__c defaults to 'Planned'.
     */
    public static Invoice_Line_Item__c createInvoiceLineItem(
        Id invoiceId,
        Id applicationPackageId,
        Boolean doInsert
    ) {
        Invoice_Line_Item__c ili = new Invoice_Line_Item__c(
            Invoice__c              = invoiceId,
            Application_Package__c  = applicationPackageId,
            Status__c               = 'Due'
        );
        if (doInsert) insert ili;
        return ili;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // SECTION 7 — REMITTANCE FORM & JUNCTION RECORDS
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Creates an Open Remittance_Form__c for a dealer (no RecordType set).
     * Suitable for payment-flow tests that do not depend on RecordType.
     */
    public static Remittance_Form__c createRemittanceForm(Id dealerId, Boolean doInsert) {
        Remittance_Form__c rf = new Remittance_Form__c(
            Dealer_Name__c = dealerId,
            Status__c      = 'Open',
            Amount__c      = 1500.00,
            Date__c        = Date.today()
        );
        if (doInsert) insert rf;
        return rf;
    }

    /**
     * Creates a Dealer_Remittance Remittance_Form__c.
     * Use for DealerPortalRemittanceHandler and InvoiceBreakdown tests that branch
     * on RecordType.DeveloperName == 'Dealer_Remittance'.
     */
    public static Remittance_Form__c createDealerRemittanceForm(Id dealerId, Boolean doInsert) {
        Remittance_Form__c rf = new Remittance_Form__c(
            Dealer_Name__c = dealerId,
            RecordTypeId   = getRecordTypeId('Remittance_Form__c', 'Dealer_Remittance'),
            Status__c      = 'Open',
            Amount__c      = 1200.00,
            Date__c        = Date.today()
        );
        if (doInsert) insert rf;
        return rf;
    }

    /**
     * Creates an Allocation_Remittance Remittance_Form__c.
     * servicesToPay — semicolon-separated picklist API values, e.g.
     *   'Extended_Limited_Warranty;GAP_Coverage'  (pass null to leave blank)
     * Use for AllocationRemittanceHandler and InvoiceBreakdown allocation-path tests.
     */
    public static Remittance_Form__c createAllocationRemittanceForm(
        Id dealerId,
        String servicesToPay,
        Boolean doInsert
    ) {
        Remittance_Form__c rf = new Remittance_Form__c(
            Dealer_Name__c     = dealerId,
            RecordTypeId       = getRecordTypeId('Remittance_Form__c', 'Allocation_Remittance'),
            Status__c          = 'Open',
            Amount__c          = 1200.00,
            Date__c            = Date.today(),
            Services_To_Pay__c = servicesToPay
        );
        if (doInsert) insert rf;
        return rf;
    }

    /**
     * Creates a Remittance_Line_Item_Junction__c linking a Remittance Form to
     * an Invoice Line Item.  Payment__c is intentionally left null here —
     * it is set by the Flow (Update_Remittance_Line_Item_Junction) when a
     * Payment__c record is created, mirroring real production behaviour.
     */
    public static Remittance_Line_Item_Junction__c createRLJ(
        Id remittanceFormId,
        Id invoiceId,
        Id invoiceLineItemId,
        Boolean doInsert
    ) {
        Remittance_Line_Item_Junction__c rlj = new Remittance_Line_Item_Junction__c(
            Remittance_Form__c    = remittanceFormId,
            Invoice__c            = invoiceId,
            Invoice_Line_Item__c  = invoiceLineItemId,
            Payment_Status__c     = 'Planned',
            Line_Item_Amount__c   = 1500.00
        );
        if (doInsert) insert rlj;
        return rlj;
    }

    /**
     * Creates a fully-linked RLJ that already has a Payment__c attached.
     * Used to test PaymentStatusInvocable and PaymentStatusService directly.
     */
    public static Remittance_Line_Item_Junction__c createRLJWithPayment(
        Id remittanceFormId,
        Id paymentId,
        Id invoiceId,
        Id invoiceLineItemId,
        Boolean doInsert
    ) {
        Remittance_Line_Item_Junction__c rlj = new Remittance_Line_Item_Junction__c(
            Remittance_Form__c    = remittanceFormId,
            Payment__c            = paymentId,
            Invoice__c            = invoiceId,
            Invoice_Line_Item__c  = invoiceLineItemId,
            Payment_Status__c     = 'Planned',
            Line_Item_Amount__c   = 1500.00
        );
        if (doInsert) insert rlj;
        return rlj;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // SECTION 8 — PAYMENT
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Creates a Payment__c in 'Transaction Pending' state.
     * This is the default state before card processing completes.
     */
    public static Payment__c createPayment(Id remittanceFormId, Boolean doInsert) {
        Payment__c pmt = new Payment__c(
            Remittance_Form__c            = remittanceFormId,
            Amount__c                     = 1500.00,
            Payment_Confirmation_Status__c = 'Transaction Pending',
            Date_Time__c                  = DateTime.now()
        );
        if (doInsert) insert pmt;
        return pmt;
    }

    /**
     * Creates a Payment__c that is already marked as Transaction Completed.
     * Triggers the PaymentStatusInvocable Flow when inserted in real org.
     * In tests, call PaymentStatusInvocable.markPaid() directly.
     */
    public static Payment__c createCompletedPayment(Id remittanceFormId, Boolean doInsert) {
        Payment__c pmt = new Payment__c(
            Remittance_Form__c            = remittanceFormId,
            Amount__c                     = 1500.00,
            Payment_Confirmation_Status__c = 'Transaction Completed',
            Transaction_Completed_Date__c  = DateTime.now(),
            Date_Time__c                  = DateTime.now()
        );
        if (doInsert) insert pmt;
        return pmt;
    }

    /**
     * Creates a Payment__c in Deposit Pending state (cheque/eTransfer).
     */
    public static Payment__c createDepositPendingPayment(Id remittanceFormId, Boolean doInsert) {
        Payment__c pmt = new Payment__c(
            Remittance_Form__c            = remittanceFormId,
            Amount__c                     = 1500.00,
            Payment_Confirmation_Status__c = 'Deposit Pending',
            Deposit_Pending_Date__c        = DateTime.now(),
            Date_Time__c                  = DateTime.now()
        );
        if (doInsert) insert pmt;
        return pmt;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // SECTION 9 — CREDIT
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Creates a Credit__c (overpayment credit) for a dealer.
     */
    public static Credit__c createCredit(Id dealerId, Decimal amount, Boolean doInsert) {
        Credit__c credit = new Credit__c(
            Dealer__c  = dealerId,
            Amount__c  = amount
        );
        if (doInsert) insert credit;
        return credit;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // SECTION 10 — VEHICLE
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Creates a Vehicle__c with standard make/model/year defaults.
     */
    public static Vehicle__c createVehicle(Boolean doInsert) {
        Vehicle__c v = new Vehicle__c(
            Name        = unique('Test Vehicle'),
            Make__c     = 'Toyota',
            Model__c    = 'Camry',
            Year__c     = '2022',
            VIN__c      = '1HGBH41JXMN109186',
            Odometer__c = 15000,
            Odometer_Unit__c = 'KM'
        );
        if (doInsert) insert v;
        return v;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // SECTION 11 — CLAIM
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Creates a Claim__c.
     *
     * repairShopId — required due to a validation rule on Claim__c.
     *               Always pass a valid Repair_Shop__c Id.
     *               Use TestDataFactory.createRepairShop(true) to get one.
     *
     * Valid record type developer names: Warranty_Claim, GAP_Claim
     */
    public static Claim__c createClaim(
        Id      applicationId,
        Id      repairShopId,
        String  recordTypeDeveloperName,
        Boolean doInsert
    ) {
        Claim__c claim = new Claim__c(
            Application__c  = applicationId,
            Repair_Shop__c  = repairShopId,
            RecordTypeId    = getRecordTypeId('Claim__c', recordTypeDeveloperName),
            Claim_Status__c = 'New Claim'
        );
        if (doInsert) insert claim;
        return claim;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // SECTION 12 — REPAIR SHOP & WORK ORDER
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Creates a Repair_Shop__c.
     *
     * Field types (confirmed from schema):
     *   Name                       → Text(80)        — required/indexed
     *   Operational_Status__c      → Picklist        — valid value: 'Active'
     *   Dealership_Portal_Access__c→ Picklist        — valid value: 'Access Granted'
     *   Specialization__c          → Picklist        — valid value: 'Engine'
     *   Email__c                   → Email
     *   Phone__c                   → Phone
     *   Unauthorized__c            → Checkbox
     */
    public static Repair_Shop__c createRepairShop(Boolean doInsert) {
        Repair_Shop__c shop = new Repair_Shop__c(
            Name                        = unique('Test Repair Shop'),
            Operational_Status__c       = 'Active',
            Dealership_Portal_Access__c = 'Access Granted',
            Specialization__c           = 'Engine',
            Email__c                    = uniqueEmail(),
            Phone__c                    = '905-555-0199',
            Unauthorized__c             = false
        );
        if (doInsert) insert shop;
        return shop;
    }

    /**
     * Creates a Work_Order__c linked to a Claim and Repair Shop.
     */
    public static Work_Order__c createWorkOrder(
        Id claimId,
        Id repairShopId,
        Boolean doInsert
    ) {
        Work_Order__c wo = new Work_Order__c(
            Claim__c       = claimId,
            Repair_Shop__c = repairShopId
        );
        if (doInsert) insert wo;
        return wo;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // SECTION 13 — NOTICE
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Creates a Notice__c (dealer action board notice).
     */
    public static Notice__c createNotice(Boolean doInsert) {
        Notice__c notice = new Notice__c(
            Name            = unique('Test Notice'),
            Notice_Message__c = 'This is a test notice message.',
            IsActive__c     = true
        );
        if (doInsert) insert notice;
        return notice;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // SECTION 14 — FULL SCENARIO BUILDERS
    // Convenience methods that wire up a complete object graph in one call.
    // Used when tests need a fully-connected data set rather than building
    // objects individually.
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Builds a complete payment scenario graph:
     *   Dealer → Application → AppPackage → Invoice → InvoiceLineItem
     *          → RemittanceForm → Payment → RLJ (linked)
     *
     * Returns a wrapper with all created records for easy access in tests.
     */
    public static PaymentScenario buildPaymentScenario() {
        PaymentScenario ps = new PaymentScenario();

        ps.dealer         = createDealer(true);
        ps.pkg            = createPackage('Extended_Limited_Warranty', true);
        Package_Term__c srcTerm = createPackageTerm(ps.pkg.Id, null, true);
        ps.dealerPkg      = createDealerPackage(ps.dealer.Id, ps.pkg.Id, 'Extended_Limited_Warranty', true);
        ps.dealerPkgTerm  = createDealerPackageTerm(ps.dealerPkg.Id, srcTerm.Id, null, true);
        ps.application    = createApplication(ps.dealer.Id, true);
        ps.appPackage     = createApplicationPackage(ps.application.Id, ps.dealerPkg.Id, ps.dealerPkgTerm.Id, ps.dealer.Id, true);
        ps.invoice        = createInvoice(ps.application.Id, true);
        ps.lineItem       = createInvoiceLineItem(ps.invoice.Id, ps.appPackage.Id, true);
        ps.remittanceForm = createRemittanceForm(ps.dealer.Id, true);
        ps.payment        = createPayment(ps.remittanceForm.Id, true);
        ps.rlj            = createRLJWithPayment(
                                ps.remittanceForm.Id,
                                ps.payment.Id,
                                ps.invoice.Id,
                                ps.lineItem.Id,
                                true
                            );
        return ps;
    }

    /**
     * Wrapper returned by buildPaymentScenario().
     */
    public class PaymentScenario {
        public Account                         dealer;
        public Package__c                      pkg;
        public Dealer_Package__c               dealerPkg;
        public Dealer_Package_Term__c          dealerPkgTerm;
        public Application__c                  application;
        public Application_Package__c          appPackage;
        public Invoice__c                      invoice;
        public Invoice_Line_Item__c            lineItem;
        public Remittance_Form__c              remittanceForm;
        public Payment__c                      payment;
        public Remittance_Line_Item_Junction__c rlj;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // SECTION 15 — BULK HELPERS  (200-record lists for bulk/governor tests)
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Creates and optionally inserts count Invoice__c records, all linked to
     * the same Application.  Used for batch and bulkification tests.
     */
    public static List<Invoice__c> createBulkInvoices(
        Id applicationId,
        Integer count,
        Boolean overdue,
        Boolean doInsert
    ) {
        List<Invoice__c> invList = new List<Invoice__c>();
        Date dueDate = overdue ? Date.today().addDays(-10) : Date.today().addDays(30);
        for (Integer i = 0; i < count; i++) {
            invList.add(new Invoice__c(
                Application__c      = applicationId,
                Status__c           = 'Due',
                Amount__c           = 1500.00,
                Invoice_Due_Date__c = dueDate
            ));
        }
        if (doInsert) insert invList;
        return invList;
    }

    /**
     * Creates and optionally inserts count Payment__c records, all linked to
     * the same Remittance Form.  Used for bulk payment processing tests.
     */
    public static List<Payment__c> createBulkPayments(
        Id remittanceFormId,
        Integer count,
        Boolean doInsert
    ) {
        List<Payment__c> pmtList = new List<Payment__c>();
        for (Integer i = 0; i < count; i++) {
            pmtList.add(new Payment__c(
                Remittance_Form__c             = remittanceFormId,
                Amount__c                      = 100.00,
                Payment_Confirmation_Status__c = 'Transaction Pending',
                Date_Time__c                   = DateTime.now()
            ));
        }
        if (doInsert) insert pmtList;
        return pmtList;
    }

    /**
     * Creates and optionally inserts count Dealer_Package_Option__c records,
     * all linked to the same Dealer_Package_Term__c.
     * Used for DealerPackageOptionTriggerHandler bulk tests.
     */
    public static List<Dealer_Package_Option__c> createBulkDealerPackageOptions(
        Id dealerPackageId,
        Id packageOptionId,
        Id dealerPackageTermId,
        String selectionType,
        Integer count,
        Boolean doInsert
    ) {
        List<Dealer_Package_Option__c> opts = new List<Dealer_Package_Option__c>();
        for (Integer i = 0; i < count; i++) {
            opts.add(new Dealer_Package_Option__c(
                Dealer_Package__c                = dealerPackageId,
                Package_Option__c                = packageOptionId,
                Dealer_Package_Term__c           = dealerPackageTermId,
                Selection_Type__c                = selectionType,
                Original_Package_Option_Price__c = 50.00
            ));
        }
        if (doInsert) insert opts;
        return opts;
    }

    /**
     * Creates and optionally inserts count Application__c records for a dealer.
     * Used for list view and pagination tests.
     */
    public static List<Application__c> createBulkApplications(
        Id dealerId,
        Integer count,
        Boolean doInsert
    ) {
        List<Application__c> apps = new List<Application__c>();
        Id rtId = getRecordTypeId('Application__c', 'Application');
        for (Integer i = 0; i < count; i++) {
            apps.add(new Application__c(
                Dealer_Name__c        = dealerId,
                RecordTypeId          = rtId,
                Application_Status__c = 'Draft',
                Payment_Status__c     = 'Unpaid'
            ));
        }
        if (doInsert) insert apps;
        return apps;
    }

    /**
     * Creates and optionally inserts count Remittance_Line_Item_Junction__c records.
     * Each RLJ is linked to the same Remittance Form and Invoice but to distinct
     * Invoice Line Items passed in as a list.
     */
    public static List<Remittance_Line_Item_Junction__c> createBulkRLJs(
        Id remittanceFormId,
        Id paymentId,
        List<Invoice_Line_Item__c> lineItems,
        Boolean doInsert
    ) {
        List<Remittance_Line_Item_Junction__c> rljList = new List<Remittance_Line_Item_Junction__c>();
        for (Invoice_Line_Item__c ili : lineItems) {
            rljList.add(new Remittance_Line_Item_Junction__c(
                Remittance_Form__c    = remittanceFormId,
                Payment__c            = paymentId,
                Invoice__c            = ili.Invoice__c,
                Invoice_Line_Item__c  = ili.Id,
                Payment_Status__c     = 'Planned',
                Line_Item_Amount__c   = 1500.00
            ));
        }
        if (doInsert) insert rljList;
        return rljList;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // SECTION 16 — APPLICATION OIL CHANGE
    // Used by ApplicationOilChangeHandlerTest.
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Creates an Application_Oil_Change__c.
     * Pass applicationId = null (with doInsert = false) to test early-return guards.
     * type: 'Standard' or 'Synthetic'
     * scheduleDate: maps to Schedule_Date_Of_Service__c (drives Duration_Months__c)
     * odometerKm:  maps to Odometer_KM__c (drives Odometer_Difference_KM__c)
     */
    public static Application_Oil_Change__c createApplicationOilChange(
        Id      applicationId,
        Decimal odometerKm,
        Date    scheduleDate,
        String  type,
        Boolean doInsert
    ) {
        Application_Oil_Change__c oil = new Application_Oil_Change__c(
            Application__c              = applicationId,
            Odometer_KM__c              = odometerKm,
            Schedule_Date_Of_Service__c = scheduleDate,
            Type__c                     = type
        );
        if (doInsert) insert oil;
        return oil;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // SECTION 17 — CONTENT VERSION / PACKAGE FILE
    // Used by DealerPackageFileCopyHandlerTest.
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Creates a ContentVersion linked to an existing SObject record.
     * Salesforce auto-creates the ContentDocument and a ContentDocumentLink
     * from the new document to firstPublishLocationId on insert.
     *
     * Use this to simulate a file being attached to a Dealer Account (logo)
     * or to a Package_File__c (brochure) so the file-copy handler can find it.
     */
    public static ContentVersion createContentVersion(
        Id firstPublishLocationId,
        String title,
        Boolean doInsert
    ) {
        ContentVersion cv = new ContentVersion(
            Title                  = title,
            PathOnClient           = title + '.txt',
            VersionData            = Blob.valueOf('Test file content for ' + title),
            FirstPublishLocationId = firstPublishLocationId
        );
        if (doInsert) insert cv;
        return cv;
    }

    /**
     * Creates a Package_File__c.
     * Pass dealerPackageId = null for package-level source files
     * (handler queries WHERE Dealer_Package__c = null).
     * Pass a valid Id for dealer-package-level copies.
     * fileType maps to File_Type_del__c — e.g. 'Dealer Logo', 'Package Brochure'.
     * Pass null to test the handler's default-type branch.
     */
    public static Package_File__c createPackageFile(
        Id packageId,
        Id dealerPackageId,
        String fileType,
        Boolean doInsert
    ) {
        Package_File__c pf = new Package_File__c(
            Package__c        = packageId,
            Dealer_Package__c = dealerPackageId,
            File_Type_del__c  = fileType
        );
        if (doInsert) insert pf;
        return pf;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // SECTION 18 — ESTIMATE
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Creates an Estimate__c.
     *
     * Field types (confirmed from schema):
     *   Claim__c         → Master-Detail(Claim)  — REQUIRED
     *   Repair_Shop__c   → Lookup(Repair Shop)   — required (validation rule on Claim)
     *   Deductable__c    → Currency(16, 2)
     *   Labour_Cost__c   → Currency(16, 2)
     *   Shop_Supplies__c → Currency(16, 2)
     *
     * Name is an auto-number field and cannot be set manually.
     * Because claimsWorksheetController filters on Estimate__r.Name = 'E-0033',
     * the getter methods will always return empty lists in test context.
     * Recommended fix: refactor controller to accept an estimateId parameter.
     */
    public static Estimate__c createEstimate(
        Id      claimId,
        Id      repairShopId,
        Boolean doInsert
    ) {
        Estimate__c est = new Estimate__c(
            Claim__c         = claimId,
            Repair_Shop__c   = repairShopId,
            Deductable__c    = 250.00,
            Labour_Cost__c   = 150.00,
            Shop_Supplies__c = 25.00
        );
        if (doInsert) insert est;
        return est;
    }

    /**
     * Convenience wrapper — builds the full chain in one call:
     *   Dealer → Application → Repair Shop → Claim → Estimate
     *
     * Returns the inserted Estimate__c.
     * Use when a test only needs an Estimate and does not care about
     * the individual parent records.
     *
     * recordTypeDeveloperName for Claim__c: 'Warranty_Claim' or 'GAP_Claim'
     */
    public static Estimate__c createEstimateWithClaim(
        String  claimRecordTypeDeveloperName,
        Boolean doInsert
    ) {
        Account        dealer     = createDealer(true);
        Application__c app        = createApplication(dealer.Id, true);
        Repair_Shop__c repairShop = createRepairShop(true);
        Claim__c       claim      = createClaim(app.Id, repairShop.Id, claimRecordTypeDeveloperName, true);
        return createEstimate(claim.Id, repairShop.Id, doInsert);
    }
    // ─────────────────────────────────────────────────────────────────────────────
    // SECTION 19 — PART
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Creates a Part__c linked to an Estimate__c.
     *
     * Field types (confirmed from schema):
     *   KMS__c           → Number(18, 0)
     *   Part_Cost__c     → Currency(16, 2)
     *   Quantity__c      → Number(16, 2)
     *   Retail_Markup__c → Picklist  — valid value: '20%'
     *   Supplier_Name__c → Picklist  — valid value: 'MEGACITY'
     *   Part_Type__c     → Picklist  — valid value: 'NEW'
     */
    public static Part__c createPart(Id estimateId, Boolean doInsert) {
        Part__c p = new Part__c(
            Estimate__c        = estimateId,
            Part_Name__c       = unique('Test Part'),
            Supplier_Name__c   = 'MEGACITY',
            Part_Type__c       = 'NEW',
            KMS__c             = 50000,
            Part_Cost__c       = 120.00,
            Retail_Markup__c   = '20%',
            Quantity__c        = 2,
            Additional_Part__c = false
        );
        if (doInsert) insert p;
        return p;
    }

    /**
     * Bulk helper — creates count Part__c records linked to the same Estimate.
     * All records share the same default field values.
     * Used for bulkification and governor-limit tests.
     */
    public static List<Part__c> createBulkParts(
        Id      estimateId,
        Integer count,
        Boolean doInsert
    ) {
        List<Part__c> parts = new List<Part__c>();
        for (Integer i = 0; i < count; i++) {
            parts.add(new Part__c(
                Estimate__c        = estimateId,
                Part_Name__c       = unique('Bulk Part'),
                Supplier_Name__c   = 'MEGACITY',
                Part_Type__c       = 'NEW',
                KMS__c             = 50000,
                Part_Cost__c       = 50.00,
                Retail_Markup__c   = '20%',
                Quantity__c        = 1,
                Additional_Part__c = false
            ));
        }
        if (doInsert) insert parts;
        return parts;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // SECTION 20 — SERVICE
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Creates a Service__c linked to an Estimate__c.
     *
     * Field types (confirmed from schema):
     *   Time__c                      → Text(255)
     *   Wholesale_Labour_Rate_HR__c  → Currency(16, 2)
     *   Retail_Markup__c             → Picklist  — valid value: '20%'
     *   Shop_Supplies__c             → Currency(16, 2)
     *   Shop_Supplies_Markup__c      → Percent(16, 2)
     *   Shop_Supplies_Description__c → Text Area(255)
     */
    public static Service__c createService(Id estimateId, Boolean doInsert) {
        Service__c s = new Service__c(
            Estimate__c                  = estimateId,
            Time__c                      = '1.5',
            Wholesale_Labour_Rate_HR__c  = 75.00,
            Retail_Markup__c             = '20%',
            Shop_Supplies__c             = 25.00,
            Shop_Supplies_Description__c = 'Auto-generated by TestDataFactory',
            Shop_Supplies_Markup__c      = 10.00
        );
        if (doInsert) insert s;
        return s;
    }

    /**
     * Bulk helper — creates count Service__c records linked to the same Estimate.
     * Used for bulkification and governor-limit tests.
     */
    public static List<Service__c> createBulkServices(
        Id      estimateId,
        Integer count,
        Boolean doInsert
    ) {
        List<Service__c> services = new List<Service__c>();
        for (Integer i = 0; i < count; i++) {
            services.add(new Service__c(
                Estimate__c                  = estimateId,
                Time__c                      = '1.0',
                Wholesale_Labour_Rate_HR__c  = 60.00,
                Retail_Markup__c             = '20%',
                Shop_Supplies__c             = 20.00,
                Shop_Supplies_Description__c = 'Bulk service ' + i,
                Shop_Supplies_Markup__c      = 5.00
            ));
        }
        if (doInsert) insert services;
        return services;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // SECTION 21 — SHOP SUPPLY
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Creates a Shop_Supply__c linked to an Estimate__c and Repair_Shop__c.
     *
     * Fields confirmed from controller usage:
     *   Item_Name__c                 → Text
     *   Item_Description__c          → Text
     *   Service_Repair_Description__c→ Text Area
     *   Time__c                      → Text
     *   Quantity__c                  → Number/Decimal
     *   Cost__c                      → Currency
     *   Price__c                     → Currency
     *   Discount__c                  → Currency
     *   Charge__c                    → Currency
     */
    public static Shop_Supply__c createShopSupply(
        Id      estimateId,
        Id      repairShopId,
        Boolean doInsert
    ) {
        Shop_Supply__c supply = new Shop_Supply__c(
            Estimate__c                  = estimateId,
            Repair_Shop__c               = repairShopId,
            Item_Name__c                 = unique('Test Supply'),
            Item_Description__c          = 'Auto-generated by TestDataFactory',
            Service_Repair_Description__c = 'Auto-generated supply description',
            Time__c                      = '0.5',
            Quantity__c                  = 2,
            Cost__c                      = 5.00,
            Price__c                     = 10.00,
            Discount__c                  = 0,
            Charge__c                    = 10.00
        );
        if (doInsert) insert supply;
        return supply;
    }

    /**
     * Bulk helper — creates count Shop_Supply__c records linked to the same
     * Estimate and Repair Shop. Used for bulkification tests.
     */
    public static List<Shop_Supply__c> createBulkShopSupplies(
        Id      estimateId,
        Id      repairShopId,
        Integer count,
        Boolean doInsert
    ) {
        List<Shop_Supply__c> supplies = new List<Shop_Supply__c>();
        for (Integer i = 0; i < count; i++) {
            supplies.add(new Shop_Supply__c(
                Estimate__c                  = estimateId,
                Repair_Shop__c               = repairShopId,
                Item_Name__c                 = unique('Bulk Supply'),
                Item_Description__c          = 'Bulk supply ' + i,
                Service_Repair_Description__c = 'Bulk supply description ' + i,
                Time__c                      = '0.5',
                Quantity__c                  = 1,
                Cost__c                      = 5.00,
                Price__c                     = 10.00,
                Discount__c                  = 0,
                Charge__c                    = 10.00
            ));
        }
        if (doInsert) insert supplies;
        return supplies;
    }

    /**
     * Creates an Application__c pre-populated with vehicle and customer text
     * fields required by InvoiceDetailViewController.getInvoiceDetail.
     *
     * Field type assumptions (adjust if your org differs):
     *   Customer_First_Name__c → Text(255)
     *   Customer_Last_Name__c  → Text(255)
     *   Customer_Address__c    → Text Area / Text(255)
     *   Vehicle_VIN__c         → Text(255)
     *   Vehicle_Year__c        → Text(255) — controller wraps in String.valueOf()
     *   Vehicle_Make__c        → Text(255)
     *   Vehicle_Model__c       → Text(255)
     *   Odometer__c            → Number / Decimal
     *   Odometer_Unit__c       → Picklist — valid value: 'KM'
     *
     * Application_Status__c = 'Draft', Payment_Status__c = 'Unpaid' — same
     * defaults as createApplication() so behaviour is consistent.
     *
     * Usage:
     *   Application__c app =
     *       TestDataFactory.createApplicationWithDetails(dealer.Id, true);
     */
    public static Application__c createApplicationWithDetails(
        Id      dealerId,
        Boolean doInsert
    ) {
        // Person Account drives Customer_First_Name__c, Customer_Last_Name__c,
        // Customer_Address__c and all customer formula fields
        Account customer = createCustomerAccount(true);

        // Vehicle__c drives Vehicle_VIN__c, Vehicle_Make__c, Vehicle_Model__c,
        // Vehicle_Year__c, Odometer__c, Odometer_Unit__c and all vehicle formulas
        Vehicle__c vehicle = createVehicle(true);

        Application__c app = new Application__c(
            Dealer_Name__c        = dealerId,
            Customer_Name__c      = customer.Id,
            Vehicle__c            = vehicle.Id,
            RecordTypeId          = getRecordTypeId('Application__c', 'Application'),
            Application_Status__c = 'Draft',
            Payment_Status__c     = 'Unpaid'
        );
        if (doInsert) insert app;
        return app;
    }

    /**
     * Creates a Cancellation__c record.
     *
     * cancellationType: 'Invoice' or 'Invoice Line Item'
     *
     * For line item-level cancellations, update Invoice_Line_Item__c after
     * creation with doInsert=false, or insert and then update.
     */
    public static Cancellation__c createCancellation(
        Id      invoiceId,
        String  cancellationType,
        Boolean doInsert
    ) {
        Cancellation__c c = new Cancellation__c(
            Invoice__c                   = invoiceId,
            Cancellation_Reason__c       = 'Auto-generated by TestDataFactory',
            Cancellation_Status__c       = 'Pending',
            Cancellation_Type__c         = cancellationType,
            Invoice_Status_At_Request__c = 'Due'
        );
        if (doInsert) insert c;
        return c;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // SECTION 24 — WORK-ORDER-READY PART / SERVICE / SHOP SUPPLY
    // These variants set Export_to_Work_Order__c = true and Repair_Shop__c so the
    // WorkOrderCreatorController SOQL filter picks them up.
    // Existing createPart / createService / createShopSupply are NOT changed.
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Creates a Part__c eligible for Work Order export.
     *
     * Extra writable fields vs createPart():
     *   Export_to_Work_Order__c      → Checkbox       = true
     *   Repair_Shop__c               → Lookup         = repairShopId
     *   Coverage_Category__c         → Picklist       = 'Engine'
     *   Priority__c                  → Picklist       = 'Critical - Required'
     *   Warranty_Coverage_Status__c  → Picklist       = 'Covered'
     *   Service_Repair_Description__c→ Text Area(255)
     *   Comments__c                  → Text Area(255)
     *   Product_Charge__c            → Currency(16,2)
     */
    public static Part__c createPartForWorkOrder(
        Id      estimateId,
        Id      repairShopId,
        Boolean doInsert
    ) {
        Part__c p = new Part__c(
            Estimate__c                   = estimateId,
            Repair_Shop__c                = repairShopId,
            Export_to_Work_Order__c       = true,
            Part_Name__c                  = unique('WO Part'),
            Supplier_Name__c              = 'MEGACITY',
            Part_Type__c                  = 'NEW',
            KMS__c                        = 50000,
            Part_Cost__c                  = 120.00,
            Retail_Markup__c              = '20%',
            Quantity__c                   = 2,
            Product_Charge__c             = 150.00,
            Coverage_Category__c          = 'Engine',
            Priority__c                   = 'Critical - Required',
            Warranty_Coverage_Status__c   = 'Covered',
            Service_Repair_Description__c = 'Test part repair description',
            Comments__c                   = 'Test part comments',
            Additional_Part__c            = false
        );
        if (doInsert) insert p;
        return p;
    }

    /**
     * Creates a Service__c eligible for Work Order export.
     *
     * Extra writable fields vs createService():
     *   Export_to_Work_Order__c       → Checkbox
     *   Repair_Shop__c                → Lookup
     *   Coverage_Category__c          → Picklist = 'Engine'
     *   Priority__c                   → Picklist = 'Critical - Required'
     *   Warranty_Coverage_Status__c   → Picklist = 'Covered'
     *   Service_Repair_Description__c → Text Area(255)
     *   Comments__c                   → Text Area(255)
     *   Charge__c                     → Currency(16,2)
     *   Labour_Guide_Time_All_Data__c → Number(17,1)
     *   Labour_Guide_Time_Mitchell__c → Number(17,1)
     *   Repair_Time_Adj__c            → Number(18,0)
     *   Repair_Time_EST__c            → Number(18,0)
     *   Retail__c                     → Currency(16,2)
     *   Retail_Labour_Rate__c         → Currency(16,2)
     *   Total_Repair__c               → Currency(16,2)
     *   Wholesale__c                  → Currency(16,2)
     *   Wholesale_Labour_Rate_HR__c   → Currency(16,2)
     */
    public static Service__c createServiceForWorkOrder(
        Id      estimateId,
        Id      repairShopId,
        Boolean doInsert
    ) {
        Service__c s = new Service__c(
            Estimate__c                   = estimateId,
            Repair_Shop__c                = repairShopId,
            Export_to_Work_Order__c       = true,
            Time__c                       = '1.5',
            Wholesale_Labour_Rate_HR__c   = 75.00,
            Retail_Markup__c              = '20%',
            Shop_Supplies__c              = 25.00,
            Shop_Supplies_Description__c  = 'WO service supply desc',
            Shop_Supplies_Markup__c       = 10.00,
            Coverage_Category__c          = 'Engine',
            Priority__c                   = 'Critical - Required',
            Warranty_Coverage_Status__c   = 'Covered',
            Service_Repair_Description__c = 'Test service repair description',
            Comments__c                   = 'Test service comments',
            Charge__c                     = 70.00,
            Labour_Guide_Time_All_Data__c = 1.5,
            Labour_Guide_Time_Mitchell__c = 1.0,
            Repair_Time_Adj__c            = 0,
            Repair_Time_EST__c            = 2,
            Retail__c                     = 100.00,
            Retail_Labour_Rate__c         = 80.00,
            Total_Repair__c               = 170.00,
            Wholesale__c                  = 75.00
        );
        if (doInsert) insert s;
        return s;
    }

    /**
     * Creates a Shop_Supply__c eligible for Work Order export.
     *
     * Extra writable fields vs createShopSupply():
     *   Export_to_Work_Order__c       → Checkbox
     *   Coverage_Category__c          → Picklist = 'Engine'
     *   Priority__c                   → Picklist = 'Critical - Required'
     *   Warranty_Coverage_Status__c   → Picklist = 'Covered'
     *   Service_Repair_Description__c → Text Area
     *   Comments__c                   → Text Area
     */
    public static Shop_Supply__c createShopSupplyForWorkOrder(
        Id      estimateId,
        Id      repairShopId,
        Boolean doInsert
    ) {
        Shop_Supply__c supply = new Shop_Supply__c(
            Estimate__c                   = estimateId,
            Repair_Shop__c                = repairShopId,
            Export_to_Work_Order__c       = true,
            Item_Name__c                  = unique('WO Supply'),
            Item_Description__c           = 'WO supply description',
            Service_Repair_Description__c = 'Test supply repair description',
            Time__c                       = '0.5',
            Quantity__c                   = 1,
            Cost__c                       = 5.00,
            Price__c                      = 10.00,
            Discount__c                   = 0,
            Charge__c                     = 10.00,
            Coverage_Category__c          = 'Engine',
            Priority__c                   = 'Critical - Required',
            Warranty_Coverage_Status__c   = 'Covered',
            Comments__c                   = 'Test supply comments'
        );
        if (doInsert) insert supply;
        return supply;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // SECTION 25 — VEHICLE WITH FULL DETAILS
    // Used by VehicleServiceTest to populate all fields queried by loadVehicleData
    // and getVehicleById without going through saveVehicleData.
    //
    // NOTE: Make_Lookup__c and Model_Lookup__c are intentionally omitted —
    // they must be removed from saveVehicleData (hardcoded IDs block all DML
    // in test context). Once removed, all saveVehicleData paths are testable.
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Creates a Vehicle__c with all writable fields populated.
     *
     * Field types confirmed from Vehicle__c schema:
     *   Stock_Number__c                      → Text(255)
     *   VIN__c                               → Text(255)
     *   Vehicle_Identification_Number_VIN__c → Text(255)
     *   Year__c                              → Text / Picklist
     *   Make__c                              → Text(255)
     *   Model__c                             → Text(255)
     *   Trim__c                              → Text(255)
     *   Date_Vehicle_Sold__c                 → Date
     *   Vehicle_Purchase_Price__c            → Currency
     *   Branded_Rebuilt__c                   → Checkbox
     *   In_Service_Date__c                   → Date
     *   Odometer__c                          → Number
     *   Odometer_Unit__c                     → Picklist — valid value: 'KM'
     *   Business_Commercial_Use__c           → Checkbox
     *   Type_of_Commercial_Use__c            → Text / Picklist
     *
     * Usage:
     *   Vehicle__c v = TestDataFactory.createVehicleWithDetails(true);
     */
    public static Vehicle__c createVehicleWithDetails(Boolean doInsert) {
        Vehicle__c v = new Vehicle__c(
            Name                                 = unique('Test Vehicle Full'),
            Stock_Number__c                      = 'STK-001',
            VIN__c                               = '1HGBH41JXMN109186',
            Vehicle_Identification_Number_VIN__c = '1HGBH41JXMN109186',
            Year__c                              = '2022',
            Make__c                              = 'Toyota',
            Model__c                             = 'Camry',
            Trim__c                              = 'SE',
            Date_Vehicle_Sold__c                 = Date.newInstance(2022, 6, 15),
            Vehicle_Purchase_Price__c            = 35000.00,
            Branded_Rebuilt__c                   = false,
            In_Service_Date__c                   = Date.newInstance(2022, 6, 20),
            Odometer__c                          = 15000,
            Odometer_Unit__c                     = 'KM',
            Business_Commercial_Use__c           = false,
            Type_of_Commercial_Use__c            = 'Light'
        );
        if (doInsert) insert v;
        return v;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // SECTION 26 — DOCUSIGN ENVELOPE STATUS
    // Used by EnvelopeStatusServiceTest.
    // dfsle__EnvelopeStatus__c is a DocuSign managed-package object.
    //
    // Field notes:
    //   dfsle__SourceId__c      → Text(18) — stores a Salesforce record Id as a string
    //   dfsle__DocuSignId__c    → Text — the DocuSign envelope GUID
    //   dfsle__Status__c        → Text/Picklist — e.g. 'sent', 'completed', 'declined'
    //   dfsle__SenderEmail__c   → Email
    //   dfsle__SenderName__c    → Text
    //   dfsle__Sent__c          → DateTime
    //   dfsle__Completed__c     → DateTime
    //   dfsle__LastStatusUpdate__c → DateTime
    //   dfsle__Reason__c        → Text
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Creates a dfsle__EnvelopeStatus__c record linked to the given sourceId.
     *
     * sourceId     — the Salesforce record Id to store in dfsle__SourceId__c (as String)
     * status       — e.g. 'sent', 'completed', 'declined'
     * doInsert     — insert immediately if true
     *
     * Usage:
     *   dfsle__EnvelopeStatus__c es =
     *       TestDataFactory.createEnvelopeStatus(app.Id, 'sent', true);
     */
    public static dfsle__EnvelopeStatus__c createEnvelopeStatus(
        Id      sourceId,
        String  status,
        Boolean doInsert
    ) {
        dfsle__EnvelopeStatus__c es = new dfsle__EnvelopeStatus__c(
            dfsle__DocuSignId__c       = 'env-' + unique('test'),
            dfsle__SourceId__c         = String.valueOf(sourceId),
            dfsle__Status__c           = status,
            dfsle__SenderEmail__c      = uniqueEmail(),
            dfsle__SenderName__c       = unique('Test Sender'),
            dfsle__Sent__c             = DateTime.now().addMinutes(-30),
            dfsle__LastStatusUpdate__c = DateTime.now()
        );
        if (doInsert) insert es;
        return es;
    }

    /**
     * Creates a completed dfsle__EnvelopeStatus__c record.
     * Sets dfsle__Completed__c in addition to Sent/Status fields.
     */
    public static dfsle__EnvelopeStatus__c createCompletedEnvelopeStatus(
        Id      sourceId,
        Boolean doInsert
    ) {
        dfsle__EnvelopeStatus__c es = new dfsle__EnvelopeStatus__c(
            dfsle__DocuSignId__c       = 'env-' + unique('completed'),
            dfsle__SourceId__c         = String.valueOf(sourceId),
            dfsle__Status__c           = 'completed',
            dfsle__SenderEmail__c      = uniqueEmail(),
            dfsle__SenderName__c       = unique('Completed Sender'),
            dfsle__Sent__c             = DateTime.now().addMinutes(-60),
            dfsle__Completed__c        = DateTime.now().addMinutes(-5),
            dfsle__LastStatusUpdate__c = DateTime.now()
        );
        if (doInsert) insert es;
        return es;
    }

    /**
     * Bulk helper — creates count dfsle__EnvelopeStatus__c records all linked to
     * the same sourceId with the same status. Used for pagination/limit tests.
     */
    public static List<dfsle__EnvelopeStatus__c> createBulkEnvelopeStatuses(
        Id      sourceId,
        String  status,
        Integer count,
        Boolean doInsert
    ) {
        List<dfsle__EnvelopeStatus__c> records = new List<dfsle__EnvelopeStatus__c>();
        for (Integer i = 0; i < count; i++) {
            records.add(new dfsle__EnvelopeStatus__c(
                dfsle__DocuSignId__c       = 'env-bulk-' + unique(String.valueOf(i)),
                dfsle__SourceId__c         = String.valueOf(sourceId),
                dfsle__Status__c           = status,
                dfsle__SenderEmail__c      = uniqueEmail(),
                dfsle__SenderName__c       = 'Bulk Sender ' + i,
                dfsle__Sent__c             = DateTime.now().addMinutes(-i),
                dfsle__LastStatusUpdate__c = DateTime.now()
            ));
        }
        if (doInsert) insert records;
        return records;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // SECTION 27 — CONTENT MANAGER DOCUMENTS
    // Used by ContentManagerServiceTest.
    // ContentManagerService.getContentDetails filters on three specific titles:
    //   'Total Loss Coverage', 'Extended Limited Warranty', 'Tire & Rim Protection Plan'
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Creates a ContentVersion with the given title linked to the given record.
     * Salesforce auto-creates a ContentDocument and ContentDocumentLink via
     * FirstPublishLocationId on insert.
     *
     * titleName — must be one of the titles ContentManagerService filters on:
     *   'Total Loss Coverage'
     *   'Extended Limited Warranty'
     *   'Tire & Rim Protection Plan'
     *
     * Usage:
     *   ContentVersion cv = TestDataFactory.createLinkedContentVersion(
     *       app.Id, 'Extended Limited Warranty', 'pdf', true
     *   );
     */
    public static ContentVersion createLinkedContentVersion(
        Id      linkedRecordId,
        String  titleName,
        String  fileExtension,
        Boolean doInsert
    ) {
        ContentVersion cv = new ContentVersion(
            Title                  = titleName,
            PathOnClient           = titleName.replaceAll(' ', '_') + '.' + fileExtension,
            VersionData            = Blob.valueOf('Test content for ' + titleName),
            FirstPublishLocationId = linkedRecordId,
            IsMajorVersion         = true
        );
        if (doInsert) insert cv;
        return cv;
    }
    
    // ─────────────────────────────────────────────────────────────────────────────
    // SECTION 28 — CONTENT DISTRIBUTION
    // Used by ContentDistributionHelperTest.
    //
    // ContentDistribution makes a ContentVersion publicly accessible via URL.
    // Key writable fields:
    //   Name                           → Text(255)         — required
    //   ContentVersionId               → Lookup(ContentVersion) — required
    //   PreferencesAllowViewInBrowser  → Checkbox
    //   PreferencesAllowOriginalDownload → Checkbox
    //   PreferencesExpires             → Checkbox
    //
    // DistributionPublicUrl and ContentDownloadUrl are formula/system fields
    // populated by the platform after insert — they are NOT set on creation.
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Creates a ContentDistribution for the given ContentVersion.
     * Used to pre-populate distributions so the "already distributed" skip
     * path in ContentDistributionHelper can be tested.
     *
     * contentVersionId — must be the latest ContentVersion for a document
     *                    (ContentDistribution requires a valid ContentVersionId)
     *
     * Usage:
     *   ContentDistribution dist =
     *       TestDataFactory.createContentDistribution(cv.Id, true);
     */
    public static ContentDistribution createContentDistribution(
        Id      contentVersionId,
        Boolean doInsert
    ) {
        ContentDistribution dist = new ContentDistribution(
            Name                             = 'Test Distribution',
            ContentVersionId                 = contentVersionId,
            PreferencesAllowViewInBrowser    = true,
            PreferencesAllowOriginalDownload = true,
            PreferencesExpires               = false
        );
        if (doInsert) insert dist;
        return dist;
    }

    // ─────────────────────────────────────────────────────────────────────────────
// SECTION 29 — APPLICATION WITH FULL FINANCIAL & LENDER DATA
// Used by ApplicationSummaryControllerTest to cover the financial, lender,
// co-buyer, company, and sales-rep branches in getApplicationSummaryData.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Creates an Application__c fully populated with financial, lender, and
 * company fields that are otherwise null in createApplication().
 *
 * Fields set beyond createApplication() defaults:
 *   Financial_Institution_Lender__c → Text        (lien holder name)
 *   Lender_Phone__c                 → Phone
 *   Lender_Address__c               → Text Area
 *   Finance_Loan_Term_Months__c     → Number
 *   Amount_Financed__c              → Currency
 *   Interest_Rate__c                → Percent
 *   Cash_Down_Payment__c            → Currency
 *   Trade_in_Amount__c              → Currency
 *   Company_Business__c             → Text        (company name on app)
 *   Dealer_Sales_ID_License__c      → Text
 *   Vehicle__c                      → Lookup      (pass null to skip)
 *   Customer_Name__c                → Lookup      (pass null to skip)
 *   Co_Buyer__c                     → Lookup      (pass null to skip)
 *   Sales_Rep__c                    → Lookup      (pass null to skip)
 */
public static Application__c createFullApplication(
    Id      dealerId,
    Id      vehicleId,
    Id      customerId,
    Id      coBuyerId,
    Id      salesRepId,
    Boolean doInsert
) {
    Application__c app = new Application__c(
        Dealer_Name__c                 = dealerId,
        RecordTypeId                   = getRecordTypeId('Application__c', 'Application'),
        Application_Status__c          = 'Draft',
        Payment_Status__c              = 'Unpaid',
        Vehicle__c                     = vehicleId,
        Customer_Name__c               = customerId,
        Co_Buyer__c                    = coBuyerId,
        Sales_Rep__c                   = salesRepId,
        Financial_Institution_Lender__c = 'Test Lender Bank',
        Lender_Phone__c                = '416-555-0200',
        Lender_Address__c              = '999 Finance Blvd, Toronto, ON',
        Finance_Loan_Term_Months__c    = 60,
        Amount_Financed__c             = 25000.00,
        Interest_Rate__c               = 5.99,
        Cash_Down_Payment__c           = 3000.00,
        Trade_in_Amount__c             = 5000.00,
        // Company_Business__c            = 'Test Corp Inc.',
        Dealer_Sales_ID_License__c     = 'SL-12345'
    );
    if (doInsert) insert app;
    return app;
}

/**
 * Creates an internal (non-portal) User with a standard Salesforce profile
 * so it can be linked to Application__c.Sales_Rep__c.
 *
 * Uses the 'Standard User' profile (or 'Read Only' if Standard User is
 * unavailable).  The user is only inserted when doInsert = true.
 */
public static User createInternalUser(Boolean doInsert) {
    String email = uniqueEmail();
    Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    User u = new User(
        FirstName         = 'Sales',
        LastName          = unique('Rep'),
        Email             = email,
        Username          = email,
        Alias             = 'srep',
        CommunityNickname = unique('srep'),
        TimeZoneSidKey    = 'America/Toronto',
        LocaleSidKey      = 'en_US',
        EmailEncodingKey  = 'UTF-8',
        LanguageLocaleKey = 'en_US',
        ProfileId         = p.Id
    );
    if (doInsert) insert u;
    return u;
}

/**
 * Creates a Vehicle__c with all tire/rim and advanced spec fields populated.
 * Used by ApplicationSummaryControllerTest.getTireRimDetails branch.
 *
 * Fields added beyond createVehicleWithDetails():
 *   Engine__c              → Text
 *   Transmission__c        → Text
 *   Fuel_Type__c           → Picklist
 *   Drive_Type__c          → Picklist
 *   Body_Type__c           → Picklist
 *   Color__c               → Text
 *   GVWR__c                → Number
 *   Factory_Warranty__c    → Checkbox
 *   Warranty_Term__c       → Text
 *   In_Service_Date__c     → Date
 *   Delivery_Date__c       → Date
 *   Manufacturer_Warranty_Type__c → Picklist
 *   Purchase_Date__c       → Date
 */
public static Vehicle__c createFullVehicle(Boolean doInsert) {
    Vehicle__c v = new Vehicle__c(
        Name                                 = unique('Full Vehicle'),
        Stock_Number__c                      = 'STK-FULL-001',
        VIN__c                               = '2T1BURHE0JC016394',
        Vehicle_Identification_Number_VIN__c = '2T1BURHE0JC016394',
        Year__c                              = '2021',
        Make__c                              = 'Honda',
        Model__c                             = 'Civic',
        Trim__c                              = 'LX',
        Date_Vehicle_Sold__c                 = Date.newInstance(2021, 3, 10),
        Vehicle_Purchase_Price__c            = 28000.00,
        Branded_Rebuilt__c                   = false,
        In_Service_Date__c                   = Date.newInstance(2021, 3, 15),
        Delivery_Date__c                     = Date.newInstance(2021, 3, 20),
        Purchase_Date__c                     = Date.newInstance(2021, 3, 10),
        Odometer__c                          = 22000,
        Odometer_Unit__c                     = 'KM',
        Business_Commercial_Use__c           = true,
        Type_of_Commercial_Use__c            = 'Light',
        Engine__c                            = '2.0L 4-Cylinder',
        Transmission__c                      = 'Automatic',
        Fuel_Type__c                         = 'Gasoline',
        Drive_Type__c                        = 'FWD',
        Body_Type__c                         = 'Sedan',
        Color__c                             = 'Blue',
        GVWR__c                              = 1800,
        Factory_Warranty__c                  = true,
        Warranty_Term__c                     = '3 Years / 60,000 KM',
        Manufacturer_Warranty_Type__c        = 'Comprehensive'
    );
    if (doInsert) insert v;
    return v;
}

/**
 * Creates an Application_Package__c with RecordType Tire_Rim_Protection_Plan
 * and tire/rim detail fields populated.
 * Used to cover the getTireRimDetails() private method branch.
 *
 * Tire/Rim fields:
 *   Tire_Brand__c       → Text
 *   Tire_Type__c        → Picklist
 *   Tread_Depth__c      → Number
 *   Tread_Depth_Unit__c → Picklist
 *   Rim_Brand__c        → Text
 *   Rim_Type__c         → Picklist
 *   Rim_Size__c         → Number
 *   Rim_Size_Unit__c    → Picklist
 */
public static Application_Package__c createTireRimApplicationPackage(
    Id      applicationId,
    Id      dealerPackageId,
    Id      dealerId,
    Boolean doInsert
) {
    Application_Package__c ap = new Application_Package__c(
        Application__c    = applicationId,
        Dealer_Package__c = dealerPackageId,
        Dealer__c         = dealerId,
        RecordTypeId      = getRecordTypeId('Application_Package__c', 'Tire_Rim_Protection_Plan'),
        Payment_Status__c = 'Not Paid',
        Active__c         = true,
        Tire_Brand__c     = 'Michelin',
        Tire_Type__c      = 'All Season',
        Tread_Depth__c    = 8,
        Tread_Depth_Unit__c = 'MM',
        Rim_Brand__c      = 'OEM',
        Rim_Type__c       = 'Alloy',
        Rim_Size__c       = 17,
        Rim_Size_Unit__c  = 'Inch'
    );
    if (doInsert) insert ap;
    return ap;
}

    // ─────────────────────────────────────────────────────────────────────────────
    // INNER EXCEPTION
    // ─────────────────────────────────────────────────────────────────────────────

    public class TestDataFactoryException extends Exception {}
}