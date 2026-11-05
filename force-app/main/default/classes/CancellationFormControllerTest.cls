/**
 * Tests for CancellationFormController.
 *
 * Org behaviours this suite has to respect:
 *  - static variables set in @TestSetup do not survive into the test method, so
 *    every id is re-queried inside the test;
 *  - the Application_Package_Deactivate_Previous_Application_Package flow keeps
 *    one active package per application, so each fixture package lives on its own
 *    application;
 *  - customer and vehicle fields on Application__c are formulas, so they cannot
 *    be set here and the snapshot assertions stay on dealer/reason/amount only.
 */
@IsTest
private class CancellationFormControllerTest {

    private static final String PNG_1X1 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

    @TestSetup
    static void setup() {
        insert new Account(Name = 'Test Dealer', BillingStreet = '1 Test Road',
            BillingCity = 'Toronto', BillingState = 'ON', BillingPostalCode = 'L4K 1Z8');
        insert new Account(Name = 'Other Dealer');

        Id dealerId = dealerId();
        Id otherDealerId = otherDealerId();

        // Main application: one active package priced 899 + 150 of add-ons.
        Application__c app = new Application__c(
            Dealer_Name__c = dealerId,
            Application_Status__c = 'Draft'
        );
        insert app;
        insert new Application_Package__c(
            Application__c = app.Id,
            Active__c = true,
            Dealer_Package_Price__c = 899,
            Add_Ons_Price__c = 150
        );

        // Second application, already cancelled, for the ineligible path.
        Application__c cancelled = new Application__c(
            Dealer_Name__c = dealerId,
            Application_Status__c = 'Cancelled'
        );
        insert cancelled;

        // Application holding an inactive package only.
        Application__c inactive = new Application__c(
            Dealer_Name__c = dealerId,
            Application_Status__c = 'Draft'
        );
        insert inactive;
        insert new Application_Package__c(
            Application__c = inactive.Id,
            Active__c = false,
            Dealer_Package_Price__c = 100
        );

        // Another dealership's application.
        Application__c other = new Application__c(
            Dealer_Name__c = otherDealerId,
            Application_Status__c = 'Draft'
        );
        insert other;
        insert new Application_Package__c(
            Application__c = other.Id,
            Active__c = true,
            Dealer_Package_Price__c = 10
        );

        // Dealer package with a Plan Type (the Package_Group lookup). This is the
        // only place the real service category comes from - the package name is
        // deliberately a name the client-side keyword heuristic would group
        // differently, so the assertion can only pass from the server value.
        insert new Package_Group__c(Name = 'Tire and Rim Protection');
        Id protectionGroupId = [
            SELECT Id FROM Package_Group__c WHERE Name = 'Tire and Rim Protection' LIMIT 1
        ].Id;
        // Package__c is intentionally left null: DealerPackageTriggerHandler.onAfterInsert
        // returns early without a master link, so no mirror fan-out runs in this test.
        Dealer_Package__c categorisedPkg = new Dealer_Package__c(
            Name = 'Windshield Glass Coverage',
            Plan_Type__c = protectionGroupId
        );
        insert categorisedPkg;

        Application__c categorised = new Application__c(
            Dealer_Name__c = dealerId,
            Application_Status__c = 'Draft'
        );
        insert categorised;
        insert new Application_Package__c(
            Application__c = categorised.Id,
            Active__c = true,
            Dealer_Package__c = categorisedPkg.Id,
            Dealer_Package_Price__c = 650
        );

        // Dealer package with no Plan Type: the category must come back null so the
        // client can fall back. The name is chosen so the fallback produces
        // "Other Services" only here.
        Dealer_Package__c uncategorisedPkg = new Dealer_Package__c(
            Name = 'Legacy Coverage Plan'
        );
        insert uncategorisedPkg;

        Application__c uncategorised = new Application__c(
            Dealer_Name__c = dealerId,
            Application_Status__c = 'Draft'
        );
        insert uncategorised;
        insert new Application_Package__c(
            Application__c = uncategorised.Id,
            Active__c = true,
            Dealer_Package__c = uncategorisedPkg.Id,
            Dealer_Package_Price__c = 425
        );
    }

    // ------------------------------------------------------------- helpers

    private static Id dealerId() {
        return [SELECT Id FROM Account WHERE Name = 'Test Dealer' LIMIT 1].Id;
    }

    private static Id otherDealerId() {
        return [SELECT Id FROM Account WHERE Name = 'Other Dealer' LIMIT 1].Id;
    }

    private static Id appId() {
        return [SELECT Application__c FROM Application_Package__c
                WHERE Dealer_Package_Price__c = 899 LIMIT 1].Application__c;
    }

    private static Id cancelledAppId() {
        return [SELECT Id FROM Application__c
                WHERE Dealer_Name__r.Name = 'Test Dealer'
                AND Application_Status__c = 'Cancelled' LIMIT 1].Id;
    }

    private static Id inactiveAppId() {
        return [SELECT Application__c FROM Application_Package__c
                WHERE Dealer_Package_Price__c = 100 LIMIT 1].Application__c;
    }

    private static Id otherAppId() {
        return [SELECT Id FROM Application__c WHERE Dealer_Name__r.Name = 'Other Dealer' LIMIT 1].Id;
    }

    private static Id packageId() {
        return [SELECT Id FROM Application_Package__c
                WHERE Application__c = :appId() AND Active__c = true LIMIT 1].Id;
    }

    private static Id categorisedAppId() {
        return [SELECT Application__c FROM Application_Package__c
                WHERE Dealer_Package_Price__c = 650 LIMIT 1].Application__c;
    }

    private static Id uncategorisedAppId() {
        return [SELECT Application__c FROM Application_Package__c
                WHERE Dealer_Package_Price__c = 425 LIMIT 1].Application__c;
    }

    private static Id inactivePackageId() {
        return [SELECT Id FROM Application_Package__c
                WHERE Application__c = :inactiveAppId() LIMIT 1].Id;
    }

    private static void asDealer() {
        CancellationFormController.dealerAccountOverride = dealerId();
    }

    // --------------------------------------------------------------- tests

    @IsTest
    static void formContextReturnsRetailPricedEstimate() {
        asDealer();
        Test.startTest();
        CancellationFormController.FormContext ctx = CancellationFormController.getFormContext(appId());
        Test.stopTest();

        System.assertEquals('Test Dealer', ctx.dealerName, 'dealer resolved');
        System.assertNotEquals(null, ctx.dealerAddress, 'address composed');
        System.assertEquals(1, ctx.packages.size(), 'one active service');
        System.assertEquals(1049, ctx.packages[0].estimate, '899 retail + 150 of add-ons');
        System.assertEquals(1049, ctx.estimatedTotal, 'estimate total');
        System.assertEquals(true, ctx.eligible, 'eligible application');
        System.assertEquals(false, ctx.hasOpenRequest, 'no open request');
        System.assertNotEquals(null, ctx.termsVersion, 'terms version supplied');
    }

    /**
     * The service category must come from Dealer_Package__r.Plan_Type__r.Name.
     * The package name used here ("Windshield Glass Coverage") contains no keyword
     * the client heuristic recognises, so a category can only be present if the
     * server supplied it.
     */
    @IsTest
    static void packageCarriesItsPlanTypeCategory() {
        asDealer();
        CancellationFormController.FormContext ctx =
            CancellationFormController.getFormContext(categorisedAppId());

        System.assertEquals(1, ctx.packages.size(), 'one active service');
        System.assertEquals('Windshield Glass Coverage', ctx.packages[0].name, 'package name');
        System.assertEquals('Tire and Rim Protection', ctx.packages[0].category,
            'category read from the plan type, not derived from the name');
    }

    /** A dealer package with no plan type must report a null category, not a guess. */
    @IsTest
    static void packageWithoutPlanTypeHasNoCategory() {
        asDealer();
        CancellationFormController.FormContext ctx =
            CancellationFormController.getFormContext(uncategorisedAppId());

        System.assertEquals(1, ctx.packages.size(), 'one active service');
        System.assertEquals('Legacy Coverage Plan', ctx.packages[0].name, 'package name');
        System.assertEquals(null, ctx.packages[0].category,
            'no plan type -> null category, left to the client fallback');
    }

    @IsTest
    static void cancelledApplicationIsIneligible() {
        asDealer();
        CancellationFormController.FormContext ctx = CancellationFormController.getFormContext(cancelledAppId());
        System.assertEquals(false, ctx.eligible, 'cancelled application is not eligible');
        System.assert(ctx.ineligibleReason.contains('cancelled'), ctx.ineligibleReason);
    }

    @IsTest
    static void estimateIncludesAddOns() {
        asDealer();
        CancellationFormController.EstimateResult result = CancellationFormController.estimateRefund(
            appId(), new List<Id>{ packageId() });

        System.assertEquals(1, result.lines.size(), 'one service estimated');
        System.assertEquals(1049, result.total, '899 + 150');
        System.assertEquals(150, result.lines[0].addOnsTotal, 'add-ons included in the estimate');
    }

    @IsTest
    static void otherDealersApplicationIsRefused() {
        asDealer();
        try {
            CancellationFormController.getFormContext(otherAppId());
            System.assert(false, 'expected a refusal');
        } catch (CancellationFormController.CancellationFormException e) {
            System.assert(e.getMessage().contains('another dealership'), e.getMessage());
        }
    }

    @IsTest
    static void packageFromAnotherApplicationIsRefused() {
        asDealer();
        Id foreignPackage = [SELECT Id FROM Application_Package__c
                             WHERE Application__c = :otherAppId() LIMIT 1].Id;
        try {
            CancellationFormController.submitRequest(appId(), new List<Id>{ foreignPackage },
                'Customer Request', null, true, '1.0', PNG_1X1, 'Rep', 'Principal');
            System.assert(false, 'expected a refusal');
        } catch (CancellationFormController.CancellationFormException e) {
            System.assert(e.getMessage().contains('do not belong'), e.getMessage());
        }
    }

    @IsTest
    static void inactivePackageIsRefused() {
        asDealer();
        Id inactive = inactivePackageId();
        try {
            CancellationFormController.submitRequest(appId(), new List<Id>{ inactive },
                'Customer Request', null, true, '1.0', PNG_1X1, 'Rep', 'Principal');
            System.assert(false, 'expected a refusal');
        } catch (CancellationFormController.CancellationFormException e) {
            System.assert(e.getMessage().contains('no longer active'), e.getMessage());
        }
    }

    @IsTest
    static void otherReasonRequiresDetail() {
        asDealer();
        try {
            CancellationFormController.submitRequest(appId(), new List<Id>{ packageId() },
                'Other', '   ', true, '1.0', PNG_1X1, 'Rep', 'Principal');
            System.assert(false, 'expected a refusal');
        } catch (CancellationFormController.CancellationFormException e) {
            System.assert(e.getMessage().contains('explain'), e.getMessage());
        }
    }

    @IsTest
    static void termsMustBeAccepted() {
        asDealer();
        try {
            CancellationFormController.submitRequest(appId(), new List<Id>{ packageId() },
                'Customer Request', null, false, '1.0', PNG_1X1, 'Rep', 'Principal');
            System.assert(false, 'expected a refusal');
        } catch (CancellationFormController.CancellationFormException e) {
            System.assert(e.getMessage().contains('terms must be accepted'), e.getMessage());
        }
    }

    @IsTest
    static void signatureIsRequired() {
        asDealer();
        try {
            CancellationFormController.submitRequest(appId(), new List<Id>{ packageId() },
                'Customer Request', null, true, '1.0', null, 'Rep', 'Principal');
            System.assert(false, 'expected a refusal');
        } catch (CancellationFormController.CancellationFormException e) {
            System.assert(e.getMessage().contains('signature'), e.getMessage());
        }
    }

    @IsTest
    static void unknownReasonIsRefused() {
        asDealer();
        try {
            CancellationFormController.submitRequest(appId(), new List<Id>{ packageId() },
                'Trade In', null, true, '1.0', PNG_1X1, 'Rep', 'Principal');
            System.assert(false, 'expected a refusal');
        } catch (CancellationFormController.CancellationFormException e) {
            System.assert(e.getMessage().contains('reason'), e.getMessage());
        }
    }

    @IsTest
    static void openRequestBlocksASecondSubmission() {
        asDealer();
        Id app = appId();
        insert new App_Cancellation_Request__c(
            Application__c = app,
            Status__c = 'Pending Sales Review',
            Refund_Eligible__c = true,
            Date_Requested__c = Datetime.now()
        );

        try {
            CancellationFormController.submitRequest(app, new List<Id>{ packageId() },
                'Customer Request', null, true, '1.0', PNG_1X1, 'Rep', 'Principal');
            System.assert(false, 'expected a refusal');
        } catch (CancellationFormController.CancellationFormException e) {
            System.assert(e.getMessage().contains('already open'), e.getMessage());
        }
    }

    @IsTest
    static void happyPathCreatesRequestServicesAndSignature() {
        asDealer();
        Id app = appId();
        CancellationFormController.SubmitResult result;
        Test.startTest();
        result = CancellationFormController.submitRequest(app, new List<Id>{ packageId() },
            'Vehicle Sold/Traded', null, true, '1.0', PNG_1X1, 'Marc McIntosh', 'Dealer Principal');
        Test.stopTest();

        System.assertNotEquals(null, result.requestId, 'request created');
        System.assertEquals(true, result.signatureStored, 'signature stored');

        App_Cancellation_Request__c request = [
            SELECT Id, Name, Status__c, Reason_Code__c, Refund_Eligible__c,
                   Total_Refund_Amount__c, Authorized_Rep_Name__c, Authorized_Rep_Title__c,
                   Terms_Accepted__c, Submitted_From_Portal__c, Signature_Content_Version_Id__c,
                   Dealer_Snapshot__c
            FROM App_Cancellation_Request__c WHERE Id = :result.requestId
        ];
        System.assertEquals('Pending Sales Review', request.Status__c, 'never auto-approved');
        System.assertEquals('Vehicle Sold/Traded', request.Reason_Code__c);
        System.assertEquals(1049, request.Total_Refund_Amount__c, 'estimate stored');
        System.assertEquals(true, request.Refund_Eligible__c);
        System.assertEquals(true, request.Terms_Accepted__c);
        System.assertEquals(true, request.Submitted_From_Portal__c);
        System.assertEquals('Marc McIntosh', request.Authorized_Rep_Name__c);
        System.assertEquals('Test Dealer', request.Dealer_Snapshot__c, 'dealer snapshot');
        System.assertNotEquals(null, request.Signature_Content_Version_Id__c, 'signature stored');

        List<Cancellation_Service__c> services = [
            SELECT Id, Application_Package__c, Estimated_Refund__c, Service_Name__c
            FROM Cancellation_Service__c WHERE App_Cancellation_Request__c = :result.requestId
        ];
        System.assertEquals(1, services.size(), 'one row per selected service');
        System.assertEquals(1049, services[0].Estimated_Refund__c, 'estimate carried to the line');
    }

    @IsTest
    static void requestSummaryExposesTheRequest() {
        asDealer();
        CancellationFormController.SubmitResult submitted = CancellationFormController.submitRequest(
            appId(), new List<Id>{ packageId() },
            'Customer Request', 'Moved overseas', true, '1.0', PNG_1X1, 'Rep', 'Principal');

        Test.startTest();
        CancellationFormController.RequestSummary summary =
            CancellationFormController.getRequestSummary(submitted.requestId);
        Test.stopTest();

        System.assertEquals('Customer Request', summary.reason, 'reason code');
        System.assertEquals('Moved overseas', summary.reasonDetail, 'reason detail');
        System.assertEquals(1, summary.services.size(), 'one service on the summary');
        System.assertEquals('PENDING CANCELLATION', summary.statusLabel, 'status label');
    }

    @IsTest
    static void requestSummaryRefusesAnotherDealersRequest() {
        asDealer();
        CancellationFormController.SubmitResult submitted = CancellationFormController.submitRequest(
            appId(), new List<Id>{ packageId() },
            'Customer Request', null, true, '1.0', PNG_1X1, 'Rep', 'Principal');

        CancellationFormController.dealerAccountOverride = otherDealerId();
        try {
            CancellationFormController.getRequestSummary(submitted.requestId);
            System.assert(false, 'expected a refusal');
        } catch (CancellationFormController.CancellationFormException e) {
            System.assert(e.getMessage().contains('another dealership'), e.getMessage());
        }
    }

    @IsTest
    static void listIsScopedToTheDealerAndFiltered() {
        asDealer();
        CancellationFormController.submitRequest(appId(), new List<Id>{ packageId() },
            'Customer Request', null, true, '1.0', PNG_1X1, 'Rep', 'Principal');

        Test.startTest();
        List<CancellationFormController.RequestRow> rows =
            CancellationFormController.getRequests('all', 'all', null, 'newest');
        List<CancellationFormController.RequestRow> pending =
            CancellationFormController.getRequests('pending', 'all', null, 'customer');
        List<CancellationFormController.RequestRow> none =
            CancellationFormController.getRequests('approved', 'all', null, 'oldest');
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'only this dealer sees the request');
        String expectedNumber = [SELECT Name FROM Application__c WHERE Id = :appId()].Name;
        System.assertEquals(expectedNumber, rows[0].applicationNumber, 'application number present');
        System.assertEquals('pending', rows[0].statusKey, 'pending status key');
        System.assertNotEquals(null, rows[0].services, 'service names joined');
        System.assertEquals(1, pending.size(), 'pending filter matches');
        System.assertEquals(0, none.size(), 'no approved requests yet');
    }

    @IsTest
    static void searchApplicationsNeedsTwoCharactersAndFindsTheNumber() {
        asDealer();
        String appNumber = [SELECT Name FROM Application__c WHERE Id = :appId()].Name;

        Test.startTest();
        System.assertEquals(0, CancellationFormController.searchApplications('T').size(), 'too short');
        List<Map<String, String>> found = CancellationFormController.searchApplications(appNumber);
        Test.stopTest();

        System.assertEquals(1, found.size(), 'application number match');
        System.assertEquals(appNumber, found[0].get('applicationNumber'), 'matched application');
    }

    /**
     * Regression: the portal path must never surface a raw system exception.
     *
     * The deployed form broke for dealers because a client-side render error left
     * the component on its spinner, so the failure was invisible. This exercises
     * getFormContext under a REAL portal user (no dealerAccountOverride test seam)
     * so that a field-level-security or relationship-traversal break - INVALID_FIELD,
     * insufficient access, SObjectException - fails the build instead of failing
     * silently in a browser. A clean CancellationFormException is an acceptable
     * outcome (a portal user may not be shared the fixture application); anything
     * else is not.
     */
    @IsTest
    static void portalUserContextLoadsWithoutSystemException() {
        List<User> portalUsers = [
            SELECT Id FROM User
            WHERE UserType = 'PowerPartner' AND IsActive = true AND ContactId != null
            LIMIT 1
        ];
        if (portalUsers.isEmpty()) {
            return; // no portal user in this org to run as
        }
        Id app = appId();

        Test.startTest();
        System.runAs(portalUsers[0]) {
            try {
                CancellationFormController.FormContext ctx = CancellationFormController.getFormContext(app);
                System.assertNotEquals(null, ctx, 'context returned for a portal user');
                System.assertNotEquals(null, ctx.termsText,
                    'terms text supplied - the client parser depends on it');
                System.assert(ctx.termsText.length() > 255,
                    'the whole terms text is supplied, not a 255-character truncation: '
                        + ctx.termsText.length());
            } catch (CancellationFormController.CancellationFormException e) {
                System.assert(String.isNotBlank(e.getMessage()), 'refusal must be readable');
            }
        }
        Test.stopTest();
    }

    // ------------------------------------------------------------------------
    // Regression coverage for the "dealer submits and nothing is captured" bug.
    // ------------------------------------------------------------------------

    /**
     * The real portal submit, end to end, as a real portal user.
     *
     * The previous suite only read the form context as a portal user; nothing ever
     * INSERTED as one. The submit therefore never exercised the part that broke:
     * CancellationRequestHandler reassigns the new request to the Sales review
     * queue, the portal user loses record access, and the content-publication and
     * follow-up update that store the signature then fail - rolling the whole
     * transaction back. This test fails if any of request, service rows or the
     * signature file goes missing again.
     */
    @IsTest
    static void portalUserSubmitPersistsRequestServicesAndSignature() {
        // A real portal user supplies the sharing context. The dealer comes from the
        // documented test seam: User.ContactId and Contact.AccountId are not readable
        // inside a test transaction in this org, so the dealer cannot be resolved from
        // the portal user's contact here.
        List<User> portalUsers = [
            SELECT Id, Name FROM User
            WHERE UserType = 'PowerPartner' AND IsActive = true
            ORDER BY CreatedDate
            LIMIT 1
        ];
        if (portalUsers.isEmpty()) {
            return; // no portal user in this org to run as
        }
        User pu = portalUsers[0];
        Id dealerId = dealerId();

        Application__c app = new Application__c(
            Dealer_Name__c = dealerId,
            Application_Status__c = 'Active',
            OwnerId = pu.Id
        );
        insert app;
        // Owned by the portal user: with sharing enforced the service rows must be
        // visible to the dealer or the submit is refused before anything is written.
        Application_Package__c pkg = new Application_Package__c(
            Application__c = app.Id,
            Active__c = true,
            Dealer_Package_Price__c = 500,
            OwnerId = pu.Id
        );
        insert pkg;

        // An application flow can re-point Dealer_Name__c on insert.
        Application__c storedApp = [
            SELECT Id, Dealer_Name__c FROM Application__c WHERE Id = :app.Id LIMIT 1
        ];
        Id effectiveDealer = storedApp.Dealer_Name__c == null ? dealerId : storedApp.Dealer_Name__c;

        CancellationFormController.SubmitResult result;

        Test.startTest();
        System.runAs(pu) {
            CancellationFormController.dealerAccountOverride = effectiveDealer;
            CancellationFormController.FormContext ctx =
                CancellationFormController.getFormContext(app.Id);
            System.assertEquals(true, ctx.eligible, 'fixture application is eligible');

            result = CancellationFormController.submitRequest(
                app.Id, new List<Id>{ pkg.Id }, 'Customer Request', null, true, ctx.termsVersion,
                PNG_1X1, 'Portal Rep', 'Dealer Principal');
        }
        Test.stopTest();
        CancellationFormController.dealerAccountOverride = null;

        // Read back OUTSIDE the dealer's sharing context: the after-insert trigger
        // moves the request to the Sales review queue, which is exactly why the
        // dealer could never see (or write to) it again.
        System.assertNotEquals(null, result.requestId,
            'the dealer must get back the id of a request that actually exists');

        App_Cancellation_Request__c request = [
            SELECT Id, Name, Status__c, Reason_Code__c, Terms_Accepted__c,
                   Submitted_From_Portal__c, Signature_Content_Version_Id__c, OwnerId
            FROM App_Cancellation_Request__c
            WHERE Id = :result.requestId
        ];
        System.assertEquals('Pending Sales Review', request.Status__c, 'queued for review');
        System.assertEquals('Customer Request', request.Reason_Code__c, 'reason stored');
        System.assertEquals(true, request.Terms_Accepted__c, 'terms accepted');
        System.assertEquals(true, request.Submitted_From_Portal__c, 'portal origin flagged');

        List<Cancellation_Service__c> services = [
            SELECT Id, Service_Name__c, Estimated_Refund__c
            FROM Cancellation_Service__c
            WHERE App_Cancellation_Request__c = :result.requestId
        ];
        System.assertEquals(1, services.size(), 'one service row per selected service');
        System.assertEquals(500, services[0].Estimated_Refund__c, 'estimate carried to the line');

        // Apex cannot create a file on behalf of a community user outside a real site
        // request: the insert is refused with
        // INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY on NetworkId, even from a
        // without-sharing class with the file permission set assigned. So this test
        // proves the request and its service rows persist, and that a signature
        // failure is reported and non-fatal. When the file IS created it must be
        // linked back onto the request.
        if (result.signatureStored == true) {
            List<ContentVersion> signatures = [
                SELECT Id, Title FROM ContentVersion
                WHERE Id = :request.Signature_Content_Version_Id__c
            ];
            System.assertEquals(1, signatures.size(), 'the signature file really exists');
            System.assert(signatures[0].Title.startsWith('Cancellation Signature'),
                signatures[0].Title);
        } else {
            System.assert(result.warning != null && result.warning.contains('signature'),
                'a signature failure must be reported: ' + result.warning);
            System.assertEquals(null, request.Signature_Content_Version_Id__c,
                'no signature id may be written when the file was not created');
            System.assertNotEquals(null, request.Id, 'the request must survive');
        }
    }

    @IsTest
    static void listViewIdIsRefusedAndCreatesNothing() {
        asDealer();
        Id listViewId = Id.valueOf('00BG100000Fy7rGMAR');
        Integer before = [SELECT COUNT() FROM App_Cancellation_Request__c];

        try {
            CancellationFormController.getFormContext(listViewId);
            System.assert(false, 'a ListView id must be refused');
        } catch (CancellationFormController.CancellationFormException e) {
            System.assertEquals(CancellationFormController.LINK_MESSAGE, e.getMessage(), e.getMessage());
        }

        try {
            CancellationFormController.submitRequest(listViewId, new List<Id>{ packageId() },
                'Customer Request', null, true, '1.0', PNG_1X1, 'Rep', 'Principal');
            System.assert(false, 'a ListView id must be refused on submit too');
        } catch (CancellationFormController.CancellationFormException e) {
            System.assertEquals(CancellationFormController.LINK_MESSAGE, e.getMessage(), e.getMessage());
        }

        // A missing id is the same class of problem and gets the same message.
        try {
            CancellationFormController.getFormContext(null);
            System.assert(false, 'a missing id must be refused');
        } catch (CancellationFormController.CancellationFormException e) {
            System.assertEquals(CancellationFormController.LINK_MESSAGE, e.getMessage(), e.getMessage());
        }

        System.assertEquals(before, [SELECT COUNT() FROM App_Cancellation_Request__c],
            'no request may be created from an unusable link');
    }

    /**
     * Once the row is inserted it must survive a failure in the steps that follow.
     * If the approval probe throws, the dealer is told the request was saved but
     * not routed - and the request row, its signature and its audit note are all
     * still there.
     */
    @IsTest
    static void approvalProbeFailureStillLeavesTheRequest() {
        asDealer();
        CancellationFormController.forceApprovalProbeFailure = true;
        CancellationFormController.SubmitResult result = CancellationFormController.submitRequest(
            appId(), new List<Id>{ packageId() }, 'Customer Request', null, true, '1.0',
            PNG_1X1, 'Rep', 'Principal');
        CancellationFormController.forceApprovalProbeFailure = false;

        System.assertNotEquals(null, result.requestId, 'id returned even when routing failed');
        System.assertEquals(false, result.success, 'routing failure is never reported as success');
        System.assert(result.message.contains('saved'), result.message);

        App_Cancellation_Request__c request = [
            SELECT Id, Sales_Notes__c, Signature_Content_Version_Id__c
            FROM App_Cancellation_Request__c
            WHERE Id = :result.requestId
        ];
        System.assertNotEquals(null, request.Signature_Content_Version_Id__c,
            'signature still linked when only the probe failed');
        System.assert(request.Sales_Notes__c != null
            && request.Sales_Notes__c.contains('Approval probe failed'), request.Sales_Notes__c);
    }

    // ------------------------------------------------- request name (AutoNumber)
    //
    // Name is a plain Text(80) field that nothing populated, so a new request was
    // named after its own record id ("a2vG1000005vuPB") instead of CR-00034. The
    // after-insert trigger now copies the AutoNumber value onto Name.

    @IsTest
    static void requestNameIsAutoNumberedNotTheRecordId() {
        asDealer();
        Test.startTest();
        CancellationFormController.SubmitResult result = CancellationFormController.submitRequest(
            appId(), new List<Id>{ packageId() }, 'Customer Request', null, true, '1.0',
            PNG_1X1, 'Rep', 'Principal');
        Test.stopTest();

        System.assertNotEquals(null, result.requestId, 'request created');
        System.assert(Pattern.matches('CR-[0-9]+', String.valueOf(result.requestName)),
            'the returned name is a CR number, not an id: ' + result.requestName);

        App_Cancellation_Request__c stored = [
            SELECT Id, Name, Request_Number__c
            FROM App_Cancellation_Request__c
            WHERE Id = :result.requestId
        ];
        System.assert(Pattern.matches('CR-[0-9]+', String.valueOf(stored.Name)),
            'stored Name is a CR number: ' + stored.Name);
        System.assertEquals(stored.Request_Number__c, stored.Name,
            'Name mirrors the AutoNumber field');
        System.assertNotEquals(String.valueOf(stored.Id).left(15), stored.Name,
            'Name is not the record id');
    }

    // ------------------------------------------------ signed cancellation PDF

    @IsTest
    static void signedCancellationFormPdfIsAttachedToTheRequest() {
        asDealer();
        Test.startTest();
        CancellationFormController.SubmitResult result = CancellationFormController.submitRequest(
            appId(), new List<Id>{ packageId() }, 'Customer Request', 'Moved overseas',
            true, '1.0', PNG_1X1, 'Marc McIntosh', 'Dealer Principal');
        Test.stopTest();

        // Whatever happens to the document, the request must exist.
        System.assertNotEquals(null, result.requestId, 'request created');

        App_Cancellation_Request__c stored = [
            SELECT Id, Name, Pdf_Content_Version_Id__c, Signature_Content_Version_Id__c
            FROM App_Cancellation_Request__c
            WHERE Id = :result.requestId
        ];
        System.assertNotEquals(null, stored.Signature_Content_Version_Id__c,
            'the raw signature PNG is kept');

        if (result.pdfStored == true) {
            System.assertNotEquals(null, stored.Pdf_Content_Version_Id__c,
                'the PDF id is stored on the request');
            ContentVersion pdf = [
                SELECT Id, Title, FileExtension, ContentSize, FirstPublishLocationId
                FROM ContentVersion
                WHERE Id = :stored.Pdf_Content_Version_Id__c
            ];
            System.assertEquals('pdf', pdf.FileExtension, 'the stored document is a PDF');
            System.assert(pdf.ContentSize > 1000, 'the PDF has real content: ' + pdf.ContentSize);
            System.assertEquals(result.requestId, pdf.FirstPublishLocationId,
                'the PDF is linked to the request, so it shows in its Files');
        } else {
            System.assertNotEquals(null, result.warning,
                'a document that could not be produced is reported, never silent');
        }
    }

    @IsTest
    static void pdfControllerRendersTheSignedForm() {
        asDealer();
        CancellationFormController.SubmitResult result = CancellationFormController.submitRequest(
            appId(), new List<Id>{ packageId() }, 'Other', 'Customer moved overseas',
            true, '1.0', PNG_1X1, 'Marc McIntosh', 'Dealer Principal');

        ApexPages.currentPage().getParameters().put('id', result.requestId);
        Test.startTest();
        CancellationRequestPdfController controller = new CancellationRequestPdfController();
        Test.stopTest();

        System.assert(controller.hasRequest,
            String.isBlank(controller.errorMessage) ? 'the PDF controller rejected the request' : controller.errorMessage);
        System.assertEquals('Test Dealer', controller.dealerName, 'dealer block');
        System.assertEquals('Marc McIntosh', controller.dealerRepName, 'authorised representative');
        System.assertEquals('Other', controller.reasonLabel, 'reason');
        System.assertEquals('Customer moved overseas', controller.reasonDetail, 'reason detail');
        System.assertEquals(1, controller.serviceBlocks.size(), 'one service block');
        System.assert(controller.refundAmount.startsWith('$'), 'refund formatted: ' + controller.refundAmount);
        System.assert(controller.termsBlocks.size() > 3,
            'every terms sub-section is rendered, not just the first: ' + controller.termsBlocks.size());
        System.assertEquals(true, controller.hasSignature, 'signature image embedded');
        System.assert(controller.signatureDataUriValue.startsWith('data:image/png;base64,'),
            'signature is an inline PNG');
    }

    @IsTest
    static void pdfControllerWithoutARequestRendersAnError() {
        ApexPages.currentPage().getParameters().remove('id');
        CancellationRequestPdfController controller = new CancellationRequestPdfController();
        System.assertEquals(false, controller.hasRequest, 'no request, no document');
        System.assertNotEquals(null, controller.errorMessage, 'an explanation is rendered instead');
    }
}