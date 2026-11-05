/**
 * Tests for CancellationModalController.
 *
 * Behaviour this suite pins down (read from the deployed class, not assumed):
 *  - Draft applications are auto-approved on submission and the selected
 *    services are deactivated immediately (the controller also tests for
 *    'Quote', but that value is not on the restricted Application_Status__c
 *    picklist, so that branch is unreachable);
 *  - any other paid status raises a 'Pending Sales Review' request, stores the
 *    refund, and leaves the services active until approval;
 *  - a null or blank reason is refused with a handled error and writes nothing;
 *  - a null or empty selection is refused with a handled error and writes
 *    nothing — including on a Draft application, which must not be flipped to
 *    Cancelled by an empty selection;
 *  - the dealer-ownership guard applies to PowerPartner (portal) users on BOTH
 *    the read path (getApplicationDetails) and the write paths, and internal
 *    users bypass it. The branch is reached through the controller's
 *    @TestVisible dealerAccountOverride seam, because a partner-community user
 *    cannot be created inside a test and pre-existing records are invisible to
 *    SOQL in @IsTest;
 *  - selection is scoped to the application: a foreign or inactive package is
 *    refused before anything is written;
 *  - an application is only flipped to Cancelled when no active service remains.
 *
 * Fixture note: the flow "Application Package - Deactivate Previous Application
 * Package" runs on create AND update and keeps one active package per
 * (Application, RecordType). Applications that need two simultaneously active
 * services therefore use two different package record types.
 *
 * Fixture note 2: the flow Update_Opportunity_Statuses faults on an application
 * status change to Cancelled when Opportunity__c is empty, so the Draft fixture
 * (the only one this suite cancels end-to-end) links an Opportunity.
 */
@IsTest
private class CancellationModalControllerTest {

    private static final Decimal P_DRAFT      = 1000;
    private static final Decimal P_PAID_A     = 800;
    private static final Decimal P_PAID_B     = 200;
    private static final Decimal P_PARTIAL_A  = 400;
    private static final Decimal P_PARTIAL_B  = 100;
    private static final Decimal P_INACTIVE   = 300;
    private static final Decimal P_OTHER      = 10;

    private static final String DETAILS_SEPARATOR = '\n\nAdditional Details:\n';

    @TestSetup
    static void setup() {
        Account dealer = new Account(Name = 'Modal Test Dealer');
        Account otherDealer = new Account(Name = 'Modal Other Dealer');
        insert new List<Account>{ dealer, otherDealer };

        Id rtWarranty = [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Application_Package__c' AND DeveloperName = 'Extended_Limited_Warranty'
            LIMIT 1
        ].Id;

        // A single active service, unpaid application (auto-approve path).
        // Applications in this org are created from an Opportunity, and the
        // Update_Opportunity_Statuses flow faults on an application update when
        // that lookup is empty, so the fixture mirrors the real shape.
        Opportunity deal = new Opportunity(
            Name = 'Modal Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert deal;

        Application__c draft = new Application__c(
            Dealer_Name__c = dealer.Id, Application_Status__c = 'Draft', Opportunity__c = deal.Id);
        insert draft;
        insert new Application_Package__c(
            Application__c = draft.Id, Active__c = true, RecordTypeId = rtWarranty,
            Dealer_Package_Price__c = P_DRAFT
        );

        // Paid application with two active services of different record types.
        Application__c paid = new Application__c(Dealer_Name__c = dealer.Id, Application_Status__c = 'Active');
        insert paid;
        insert new List<Application_Package__c>{
            new Application_Package__c(
                Application__c = paid.Id, Active__c = true, RecordTypeId = rtWarranty,
                Dealer_Package_Price__c = P_PAID_A
            ),
            new Application_Package__c(
                Application__c = paid.Id, Active__c = true,
                Dealer_Package_Price__c = P_PAID_B,
                RecordTypeId = [
                    SELECT Id FROM RecordType
                    WHERE SobjectType = 'Application_Package__c' AND DeveloperName = 'GAP_Coverage'
                    LIMIT 1
                ].Id
            )
        };

        // Draft application with two active services, for a partial cancellation.
        Application__c partial = new Application__c(Dealer_Name__c = dealer.Id, Application_Status__c = 'Draft');
        insert partial;
        insert new List<Application_Package__c>{
            new Application_Package__c(
                Application__c = partial.Id, Active__c = true, RecordTypeId = rtWarranty,
                Dealer_Package_Price__c = P_PARTIAL_A
            ),
            new Application_Package__c(
                Application__c = partial.Id, Active__c = true,
                Dealer_Package_Price__c = P_PARTIAL_B,
                RecordTypeId = [
                    SELECT Id FROM RecordType
                    WHERE SobjectType = 'Application_Package__c' AND DeveloperName = 'GAP_Coverage'
                    LIMIT 1
                ].Id
            )
        };

        // Application holding only an inactive service.
        Application__c inactive = new Application__c(Dealer_Name__c = dealer.Id, Application_Status__c = 'Active');
        insert inactive;
        insert new Application_Package__c(
            Application__c = inactive.Id, Active__c = false, RecordTypeId = rtWarranty,
            Dealer_Package_Price__c = P_INACTIVE
        );

        // Another dealership's application.
        Application__c other = new Application__c(Dealer_Name__c = otherDealer.Id, Application_Status__c = 'Active');
        insert other;
        insert new Application_Package__c(
            Application__c = other.Id, Active__c = true, RecordTypeId = rtWarranty,
            Dealer_Package_Price__c = P_OTHER
        );
    }

    // --------------------------------------------------------------- helpers

    private static Id appIdByPrice(Decimal price) {
        return [
            SELECT Application__c FROM Application_Package__c
            WHERE Dealer_Package_Price__c = :price LIMIT 1
        ].Application__c;
    }

    private static Id pkgIdByPrice(Decimal price) {
        return [
            SELECT Id FROM Application_Package__c
            WHERE Dealer_Package_Price__c = :price LIMIT 1
        ].Id;
    }

    private static Decimal premium(Decimal price) {
        return [
            SELECT Contract_Premium_Price__c FROM Application_Package__c
            WHERE Dealer_Package_Price__c = :price LIMIT 1
        ].Contract_Premium_Price__c;
    }

    private static Application_Package__c pkgById(Id pkgId) {
        return [
            SELECT Id, Active__c, Application_Status__c FROM Application_Package__c WHERE Id = :pkgId
        ];
    }

    private static Application__c appById(Id appId) {
        return [
            SELECT Id, Application_Status__c, Cancellation_Status__c FROM Application__c WHERE Id = :appId
        ];
    }

    private static Integer requestCount(Id appId) {
        return [SELECT COUNT() FROM App_Cancellation_Request__c WHERE Application__c = :appId];
    }

    private static Id dealerIdByName(String name) {
        return [SELECT Id FROM Account WHERE Name = :name LIMIT 1].Id;
    }

    private static Integer activePackageCount(Id appId) {
        return [
            SELECT COUNT() FROM Application_Package__c WHERE Application__c = :appId AND Active__c = true
        ];
    }

    // ----------------------------------------------------------- read surface

    @IsTest
    static void applicationDetailsReturnTheHeaderAndEveryActiveService() {
        Id app = appIdByPrice(P_PAID_A);
        Id pkgA = pkgIdByPrice(P_PAID_A);
        Id pkgB = pkgIdByPrice(P_PAID_B);

        Map<String, Object> result;
        Test.startTest();
        result = CancellationModalController.getApplicationDetails(app);
        Test.stopTest();

        Map<String, Object> appMap = (Map<String, Object>) result.get('application');
        System.assertEquals(app, (Id) appMap.get('id'), 'application id returned');
        System.assertEquals('Active', (String) appMap.get('status'), 'application status returned');
        System.assertEquals(null, appMap.get('cancellationStatus'), 'no cancellation recorded yet');

        List<Map<String, Object>> services = (List<Map<String, Object>>) result.get('services');
        System.assertEquals(2, services.size(), 'both active services are offered');

        Map<String, Decimal> priceById = new Map<String, Decimal>();
        Map<String, Boolean> activeById = new Map<String, Boolean>();
        for (Map<String, Object> svc : services) {
            priceById.put((String) svc.get('id'), (Decimal) svc.get('price'));
            activeById.put((String) svc.get('id'), (Boolean) svc.get('active'));
        }
        System.assertEquals(premium(P_PAID_A), priceById.get(String.valueOf(pkgA)), 'contract premium exposed for the first service');
        System.assertEquals(premium(P_PAID_B), priceById.get(String.valueOf(pkgB)), 'contract premium exposed for the second service');
        System.assertEquals(true, activeById.get(String.valueOf(pkgA)), 'service flagged active');
        System.assertEquals(true, activeById.get(String.valueOf(pkgB)), 'service flagged active');
    }

    @IsTest
    static void applicationDetailsExcludeInactiveServices() {
        Id app = appIdByPrice(P_INACTIVE);
        Map<String, Object> result = CancellationModalController.getApplicationDetails(app);
        System.assertEquals(0, ((List<Map<String, Object>>) result.get('services')).size(),
            'an inactive service is never offered for cancellation');
    }

    /**
     * The read path stays open to internal users — the modal still loads from the
     * applications list — including for another dealership's application.
     */
    @IsTest
    static void internalUsersCanReadAnyApplicationsDetails() {
        CancellationModalController.dealerAccountOverride = null;
        Id foreignApp = appIdByPrice(P_OTHER);
        Id foreignPkg = pkgIdByPrice(P_OTHER);

        Map<String, Object> result;
        Test.startTest();
        result = CancellationModalController.getApplicationDetails(foreignApp);
        Test.stopTest();

        List<Map<String, Object>> services = (List<Map<String, Object>>) result.get('services');
        System.assertEquals(1, services.size(), 'the foreign application still resolves for an internal user');
        System.assertEquals(String.valueOf(foreignPkg), (String) services[0].get('id'),
            'the internal user sees the real service row');
    }

    @IsTest
    static void getApplicationDetailsRejectsAMissingApplicationId() {
        Boolean thrown = false;
        try {
            CancellationModalController.getApplicationDetails(null);
        } catch (AuraHandledException expected) {
            thrown = true;
        }
        System.assert(thrown, 'a missing application id must produce a handled error, not a raw crash');
    }

    // --------------------------------------------------- submission behaviour

    @IsTest
    static void draftSubmissionApprovesImmediatelyAndCancelsTheService() {
        Id app = appIdByPrice(P_DRAFT);
        Id pkg = pkgIdByPrice(P_DRAFT);

        Id requestId;
        Test.startTest();
        requestId = CancellationModalController.submitCancellationRequest(
            app, new List<Id>{ pkg }, 'Customer Request', null);
        Test.stopTest();

        App_Cancellation_Request__c req = [
            SELECT Application__c, Status__c, Reason__c, Total_Refund_Amount__c, Refund_Eligible__c,
                   Payment_Status_At_Request__c, Date_Requested__c, Requested_By__c,
                   Requested_By_Name__c, SLA_Due_Date__c
            FROM App_Cancellation_Request__c WHERE Id = :requestId
        ];
        System.assertEquals(app, req.Application__c, 'request filed against the application');
        System.assertEquals('Approved', req.Status__c, 'a Draft application is auto-approved');
        System.assertEquals('Customer Request', req.Reason__c, 'reason stored verbatim when no details are supplied');
        System.assertEquals(0.00, req.Total_Refund_Amount__c, 'nothing has been paid on a Draft application');
        System.assertEquals(false, req.Refund_Eligible__c, 'no refund on an unpaid application');
        System.assertEquals('Draft', req.Payment_Status_At_Request__c, 'payment status snapshot');
        System.assertEquals(UserInfo.getUserId(), req.Requested_By__c, 'requested by the running user');
        System.assertNotEquals(null, req.Requested_By_Name__c, 'requester name stamped');
        System.assertNotEquals(null, req.Date_Requested__c, 'request date stamped');
        System.assertNotEquals(null, req.SLA_Due_Date__c, 'trigger stamped the SLA date');

        List<Cancellation_Service__c> services = [
            SELECT Application_Package__c, Refund_Amount__c FROM Cancellation_Service__c
            WHERE App_Cancellation_Request__c = :requestId
        ];
        System.assertEquals(1, services.size(), 'one service line per selected package');
        System.assertEquals(pkg, services[0].Application_Package__c, 'line points at the selected package');
        System.assertEquals(0.00, services[0].Refund_Amount__c, 'no refund amount on an unpaid application');

        Application_Package__c cancelledPkg = pkgById(pkg);
        System.assertEquals(false, cancelledPkg.Active__c, 'selected service deactivated');
        System.assertEquals('Cancelled', cancelledPkg.Application_Status__c, 'selected service marked cancelled');
        System.assertEquals('Cancelled', appById(app).Application_Status__c,
            'application cancelled once no active service remains');
    }

    @IsTest
    static void paidSubmissionCreatesPendingRequestWithRefundAndKeepsServicesActive() {
        Id app = appIdByPrice(P_PAID_A);
        Id pkgA = pkgIdByPrice(P_PAID_A);
        Id pkgB = pkgIdByPrice(P_PAID_B);
        Decimal expectedRefund = premium(P_PAID_A) + premium(P_PAID_B);
        System.assert(expectedRefund > 0, 'fixture premium must be priced');

        Id requestId;
        Test.startTest();
        requestId = CancellationModalController.submitCancellationRequest(
            app, new List<Id>{ pkgA, pkgB }, 'Vehicle Sold/Traded', 'Traded in at auction');
        Test.stopTest();

        App_Cancellation_Request__c req = [
            SELECT Status__c, Reason__c, Total_Refund_Amount__c, Refund_Eligible__c, Payment_Status_At_Request__c
            FROM App_Cancellation_Request__c WHERE Id = :requestId
        ];
        System.assertEquals('Pending Sales Review', req.Status__c, 'a paid application goes to review, never auto-approved');
        System.assertEquals(expectedRefund.setScale(2), req.Total_Refund_Amount__c.setScale(2),
            'refund sums the contract premium of every selected service');
        System.assertEquals(true, req.Refund_Eligible__c, 'paid application is refund eligible');
        System.assertEquals('Active', req.Payment_Status_At_Request__c, 'payment status snapshot');
        System.assertEquals('Vehicle Sold/Traded' + DETAILS_SEPARATOR + 'Traded in at auction',
            req.Reason__c, 'reason and details are combined onto the legacy reason field');

        List<Cancellation_Service__c> services = [
            SELECT Application_Package__c, Refund_Amount__c FROM Cancellation_Service__c
            WHERE App_Cancellation_Request__c = :requestId
        ];
        System.assertEquals(2, services.size(), 'one line per selected service');
        Map<Id, Decimal> refundByPkg = new Map<Id, Decimal>();
        for (Cancellation_Service__c cs : services) {
            refundByPkg.put(cs.Application_Package__c, cs.Refund_Amount__c);
        }
        System.assertEquals(premium(P_PAID_A).setScale(2), refundByPkg.get(pkgA).setScale(2), 'first service refunded at its premium');
        System.assertEquals(premium(P_PAID_B).setScale(2), refundByPkg.get(pkgB).setScale(2), 'second service refunded at its premium');

        System.assertEquals(true, pkgById(pkgA).Active__c, 'service stays active until the cancellation is approved');
        System.assertEquals(true, pkgById(pkgB).Active__c, 'service stays active until the cancellation is approved');

        Application__c updated = appById(app);
        System.assertEquals('Active', updated.Application_Status__c, 'application status untouched while pending');
        System.assertEquals('Pending Sales Review', updated.Cancellation_Status__c,
            'trigger records the pending cancellation on the application');
    }

    @IsTest
    static void partialCancellationLeavesTheApplicationOpen() {
        Id app = appIdByPrice(P_PARTIAL_A);
        Id pkgA = pkgIdByPrice(P_PARTIAL_A);
        Id pkgB = pkgIdByPrice(P_PARTIAL_B);
        System.assertEquals(2, [
            SELECT COUNT() FROM Application_Package__c WHERE Application__c = :app AND Active__c = true
        ], 'fixture must hold two active services');

        Test.startTest();
        CancellationModalController.submitCancellationRequest(app, new List<Id>{ pkgA }, 'Customer Request', null);
        Test.stopTest();

        System.assertEquals(false, pkgById(pkgA).Active__c, 'selected service cancelled');
        System.assertEquals(true, pkgById(pkgB).Active__c, 'unselected service untouched');
        System.assertEquals('Draft', appById(app).Application_Status__c,
            'application stays open while another service is still active');
    }

    // ------------------------------------------------------- selection guard

    @IsTest
    static void submitRefusesAPackageFromAnotherApplicationAndWritesNothing() {
        Id app = appIdByPrice(P_DRAFT);
        Id foreignPkg = pkgIdByPrice(P_OTHER);
        Integer before = requestCount(app);

        try {
            CancellationModalController.submitCancellationRequest(
                app, new List<Id>{ foreignPkg }, 'Customer Request', null);
            System.assert(false, 'a package from another application must be refused');
        } catch (AuraHandledException expected) {
            // expected
        }

        System.assertEquals(before, requestCount(app), 'no request written');
        System.assertEquals(true, pkgById(foreignPkg).Active__c, 'foreign package untouched');
        System.assertEquals('Draft', appById(app).Application_Status__c, 'application untouched');
    }

    @IsTest
    static void submitRefusesAnInactivePackageAndWritesNothing() {
        Id app = appIdByPrice(P_INACTIVE);
        Id inactivePkg = pkgIdByPrice(P_INACTIVE);

        try {
            CancellationModalController.submitCancellationRequest(
                app, new List<Id>{ inactivePkg }, 'Customer Request', null);
            System.assert(false, 'an inactive package must be refused');
        } catch (AuraHandledException expected) {
            // expected
        }

        System.assertEquals(0, requestCount(app), 'no request written');
        System.assertEquals(false, pkgById(inactivePkg).Active__c, 'inactive package left as it was');
        System.assertEquals('Active', appById(app).Application_Status__c, 'application untouched');
    }

    @IsTest
    static void cancelSelectedPackagesRefusesAPackageFromAnotherApplication() {
        Id app = appIdByPrice(P_DRAFT);
        Id foreignPkg = pkgIdByPrice(P_OTHER);

        try {
            CancellationModalController.cancelSelectedPackages(app, new List<Id>{ foreignPkg });
            System.assert(false, 'a package from another application must be refused');
        } catch (AuraHandledException expected) {
            // expected
        }

        System.assertEquals(true, pkgById(foreignPkg).Active__c, 'foreign package untouched');
        System.assertEquals('Draft', appById(app).Application_Status__c, 'application untouched');
    }

    /**
     * CORRECTED ASSERTION (previously cancelSelectedPackagesWithAnEmptySelectionChangesNothing):
     * an empty selection used to be silently accepted, which let the method fall
     * through to "activeCount == 0" and flip the application to Cancelled. It is
     * now refused with a handled error, and the previous no-write assertions are
     * kept and strengthened with the error itself.
     */
    @IsTest
    static void cancelSelectedPackagesRejectsAnEmptySelection() {
        Id app = appIdByPrice(P_PAID_A);
        Id pkg = pkgIdByPrice(P_PAID_A);
        Boolean thrown = false;

        Test.startTest();
        try {
            CancellationModalController.cancelSelectedPackages(app, new List<Id>());
        } catch (AuraHandledException expected) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown, 'an empty selection must be refused, not silently accepted');
        System.assertEquals(true, pkgById(pkg).Active__c, 'no service was deactivated');
        System.assertEquals('Active', appById(app).Application_Status__c, 'application untouched');
        System.assertEquals(2, activePackageCount(app), 'both active services survive');
    }

    /**
     * CORRECTED ASSERTION: this previously accepted ANY exception (the raw
     * NullPointerException/crash path). It now pins the handled error type.
     */
    @IsTest
    static void nullSelectionIsRejectedAndWritesNothing() {
        Id app = appIdByPrice(P_PAID_A);
        Boolean thrown = false;

        try {
            CancellationModalController.submitCancellationRequest(app, null, 'Customer Request', null);
        } catch (AuraHandledException expected) {
            thrown = true;
        }

        System.assert(thrown, 'a null selection must be refused with a handled error');
        System.assertEquals(0, requestCount(app), 'no request written');
        System.assertEquals(2, activePackageCount(app), 'no service was deactivated');
        System.assertEquals('Active', appById(app).Application_Status__c, 'application untouched');
    }

    // ---------------------------------------------------- corrected defects

    /**
     * CORRECTED ASSERTION (previously nullReasonIsStoredAsTheLiteralWordNull,
     * which pinned the defect): a null reason used to be concatenated into the
     * long-text Reason__c field, storing the literal string "null". It is now
     * refused before the request is inserted, so the assertions move from
     * "the request exists and says null" to "nothing was written at all".
     */
    @IsTest
    static void nullReasonIsRejectedAndWritesNothing() {
        Id app = appIdByPrice(P_DRAFT);
        Id pkg = pkgIdByPrice(P_DRAFT);
        Boolean thrown = false;

        Test.startTest();
        try {
            CancellationModalController.submitCancellationRequest(app, new List<Id>{ pkg }, null, null);
        } catch (AuraHandledException expected) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown, 'a null reason must be refused');
        System.assertEquals(0, requestCount(app), 'no request written for a null reason');
        System.assertEquals(true, pkgById(pkg).Active__c, 'service left active');
        System.assertEquals('Draft', appById(app).Application_Status__c, 'application not cancelled');
    }

    @IsTest
    static void blankReasonIsRejectedAndWritesNothing() {
        Id app = appIdByPrice(P_PARTIAL_A);
        Id pkg = pkgIdByPrice(P_PARTIAL_A);
        Boolean thrown = false;

        Test.startTest();
        try {
            CancellationModalController.submitCancellationRequest(app, new List<Id>{ pkg }, '   ', 'details without a reason');
        } catch (AuraHandledException expected) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown, 'a whitespace-only reason must be refused');
        System.assertEquals(0, requestCount(app), 'no request written for a blank reason');
        System.assertEquals(true, pkgById(pkg).Active__c, 'service left active');
        System.assertEquals(2, activePackageCount(app), 'neither service was touched');
        System.assertEquals('Draft', appById(app).Application_Status__c, 'application not cancelled');
    }

    /**
     * CORRECTED ASSERTION (previously emptySelectionCreatesARequestWithNoServices,
     * which pinned the defect): an empty selection used to create a request with
     * zero service lines and route it for review. It is now refused before any
     * write, so the assertions move from "the request exists with no services"
     * to "no request exists and no package was deactivated".
     */
    @IsTest
    static void emptySelectionIsRejectedAndWritesNothing() {
        Id app = appIdByPrice(P_PAID_A);
        Boolean thrown = false;

        Test.startTest();
        try {
            CancellationModalController.submitCancellationRequest(
                app, new List<Id>(), 'Customer Request', null);
        } catch (AuraHandledException expected) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown, 'an empty selection must be refused');
        System.assertEquals(0, requestCount(app), 'no request written');
        System.assertEquals(2, activePackageCount(app), 'services still active');
        System.assertEquals('Active', appById(app).Application_Status__c, 'application untouched');
    }

    /**
     * An empty selection on a Draft application used to fall through to
     * cancelSelectedPackages(new List<Id>()) and flip the application to
     * Cancelled even though nothing had been selected.
     */
    @IsTest
    static void emptySelectionOnADraftApplicationDoesNotCancelTheApplication() {
        Id app = appIdByPrice(P_DRAFT);
        Id pkg = pkgIdByPrice(P_DRAFT);
        Boolean thrown = false;

        Test.startTest();
        try {
            CancellationModalController.submitCancellationRequest(app, new List<Id>(), 'Customer Request', null);
        } catch (AuraHandledException expected) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown, 'an empty selection must be refused before the Draft auto-approve path runs');
        System.assertEquals(0, requestCount(app), 'no request written');
        System.assertEquals(true, pkgById(pkg).Active__c, 'service still active');
        System.assertEquals('Draft', appById(app).Application_Status__c,
            'application must not be flipped to Cancelled by an empty selection');
    }

    // -------------------------------------------------- dealer ownership guard

    /**
     * assertDealerAccess returns immediately for internal users, so an internal
     * user may file against any dealership's application.
     */
    @IsTest
    static void internalUsersAreNotSubjectToTheDealerGuard() {
        CancellationModalController.dealerAccountOverride = null;
        Id foreignApp = appIdByPrice(P_OTHER);
        Id foreignPkg = pkgIdByPrice(P_OTHER);

        Id requestId;
        Test.startTest();
        requestId = CancellationModalController.submitCancellationRequest(
            foreignApp, new List<Id>{ foreignPkg }, 'Customer Request', null);
        Test.stopTest();

        App_Cancellation_Request__c req = [
            SELECT Application__c, Status__c, Requested_By__c
            FROM App_Cancellation_Request__c WHERE Id = :requestId
        ];
        System.assertEquals(foreignApp, req.Application__c, 'an internal user may act on any dealership application');
        System.assertEquals('Pending Sales Review', req.Status__c, 'paid application goes to review');
        System.assertEquals(UserInfo.getUserId(), req.Requested_By__c, 'filed by the internal user');
    }

    /**
     * Partner path, allowed: the dealer owns the application.
     */
    @IsTest
    static void partnerDealerMaySubmitAgainstItsOwnApplication() {
        Id dealerId = dealerIdByName('Modal Test Dealer');
        Id app = appIdByPrice(P_DRAFT);
        Id pkg = pkgIdByPrice(P_DRAFT);

        CancellationModalController.dealerAccountOverride = dealerId;

        Id requestId;
        Test.startTest();
        requestId = CancellationModalController.submitCancellationRequest(
            app, new List<Id>{ pkg }, 'Customer Request', null);
        Test.stopTest();

        App_Cancellation_Request__c req = [
            SELECT Application__c, Status__c FROM App_Cancellation_Request__c WHERE Id = :requestId
        ];
        System.assertEquals(app, req.Application__c, 'own application accepted');
        System.assertEquals('Approved', req.Status__c, 'Draft application still auto-approves for an owning dealer');
        System.assertEquals(false, pkgById(pkg).Active__c, 'own service deactivated');
        System.assertEquals('Cancelled', appById(app).Application_Status__c, 'own application cancelled');
    }

    /**
     * Partner path, refused: the application belongs to a different dealership.
     */
    @IsTest
    static void partnerDealerCannotSubmitAgainstAnotherDealersApplication() {
        Id otherDealerId = dealerIdByName('Modal Other Dealer');
        Id app = appIdByPrice(P_DRAFT);
        Id pkg = pkgIdByPrice(P_DRAFT);
        Boolean thrown = false;

        CancellationModalController.dealerAccountOverride = otherDealerId;

        Test.startTest();
        try {
            CancellationModalController.submitCancellationRequest(app, new List<Id>{ pkg }, 'Customer Request', null);
        } catch (AuraHandledException expected) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown, 'a partner user must not submit against another dealership');
        System.assertEquals(0, requestCount(app), 'no request written');
        System.assertEquals(true, pkgById(pkg).Active__c, 'service left active');
        System.assertEquals('Draft', appById(app).Application_Status__c, 'application untouched');
    }

    @IsTest
    static void partnerDealerCannotCancelAnotherDealersPackages() {
        Id otherDealerId = dealerIdByName('Modal Other Dealer');
        Id app = appIdByPrice(P_DRAFT);
        Id pkg = pkgIdByPrice(P_DRAFT);
        Boolean thrown = false;

        CancellationModalController.dealerAccountOverride = otherDealerId;

        Test.startTest();
        try {
            CancellationModalController.cancelSelectedPackages(app, new List<Id>{ pkg });
        } catch (AuraHandledException expected) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown, 'a partner user must not cancel another dealership\'s packages');
        System.assertEquals(true, pkgById(pkg).Active__c, 'service left active');
        System.assertEquals('Draft', appById(app).Application_Status__c, 'application untouched');
    }

    /**
     * The read-path IDOR: a partner user must not be able to read another
     * dealership's application details (services, contract premiums) by id.
     */
    @IsTest
    static void getApplicationDetailsRefusesANonOwningDealer() {
        Id otherDealerId = dealerIdByName('Modal Other Dealer');
        Id app = appIdByPrice(P_DRAFT);
        Boolean thrown = false;

        CancellationModalController.dealerAccountOverride = otherDealerId;

        Test.startTest();
        try {
            CancellationModalController.getApplicationDetails(app);
        } catch (AuraHandledException expected) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown, 'a non-owning partner must be refused on the read path');
        System.assertEquals(0, requestCount(app), 'the refusal wrote nothing');
        System.assertEquals('Draft', appById(app).Application_Status__c, 'application untouched');
        System.assertEquals(1, activePackageCount(app), 'service untouched');
    }

    /**
     * Positive read-path control for the partner branch: the owning dealer still
     * gets the full detail payload.
     */
    @IsTest
    static void getApplicationDetailsServesTheOwningDealer() {
        Id dealerId = dealerIdByName('Modal Test Dealer');
        Id app = appIdByPrice(P_DRAFT);
        Id pkg = pkgIdByPrice(P_DRAFT);

        CancellationModalController.dealerAccountOverride = dealerId;

        Map<String, Object> result;
        Test.startTest();
        result = CancellationModalController.getApplicationDetails(app);
        Test.stopTest();

        List<Map<String, Object>> services = (List<Map<String, Object>>) result.get('services');
        System.assertEquals(1, services.size(), 'owning dealer sees the service');
        System.assertEquals(String.valueOf(pkg), (String) services[0].get('id'), 'correct service returned');
        System.assertEquals(app, (Id) ((Map<String, Object>) result.get('application')).get('id'),
            'correct application returned');
    }
}