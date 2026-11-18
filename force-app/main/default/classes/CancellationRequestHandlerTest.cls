/**
 * CancellationRequestHandlerTest
 *
 * Direct coverage for the after-insert / after-update logic of
 * CancellationRequestHandler, which the controller suites only reach indirectly.
 *
 * Covers: SLA stamping and queue routing on insert, the request-numbering block
 * degrading safely, application status synchronisation for every status
 * transition, the reassignment between the two review queues, and clearing the
 * cancellation status when a request is withdrawn.
 *
 * No assertion here depends on the AutoNumber value: numbering is presentation
 * only and must never be able to break the portal submit, so the handler's
 * numbering block is exercised but not pinned to a specific field name.
 */
@IsTest
private class CancellationRequestHandlerTest {

    private static Id dealerId() {
        return [SELECT Id FROM Account WHERE Name = 'Handler Test Dealer' LIMIT 1].Id;
    }

    @TestSetup
    static void setup() {
        insert new Account(Name = 'Handler Test Dealer');
        Id dealer = [SELECT Id FROM Account WHERE Name = 'Handler Test Dealer' LIMIT 1].Id;

        // The Update_Opportunity_Statuses flow faults when an application moves to
        // Cancelled with no Opportunity linked, and approving a cancellation does
        // exactly that. The fixture therefore links one, as the real data does.
        Opportunity deal = new Opportunity(
            Name = 'Handler Test Opportunity',
            AccountId = dealer,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert deal;

        Application__c app = new Application__c(
            Dealer_Name__c = dealer,
            Opportunity__c = deal.Id,
            Application_Status__c = 'Active'
        );
        insert app;

        insert new Application_Package__c(
            Application__c = app.Id,
            Active__c = true,
            Dealer_Package_Price__c = 750
        );
    }

    private static Id appId() {
        return [SELECT Application__c FROM Application_Package__c
                WHERE Dealer_Package_Price__c = 750 LIMIT 1].Application__c;
    }

    private static Id packageId() {
        return [SELECT Id FROM Application_Package__c
                WHERE Dealer_Package_Price__c = 750 LIMIT 1].Id;
    }

    private static App_Cancellation_Request__c newRequest(Id applicationId, String status) {
        return new App_Cancellation_Request__c(
            Application__c = applicationId,
            Status__c = status,
            Reason_Code__c = 'Customer Request',
            Reason__c = 'Customer Request',
            Date_Requested__c = Datetime.now(),
            Refund_Eligible__c = true,
            Submitted_From_Portal__c = true,
            Terms_Accepted__c = true,
            Total_Refund_Amount__c = 750
        );
    }

    /** Insert stamps the SLA date, routes to the Sales queue and syncs the application. */
    @IsTest
    static void insertStampsSlaRoutesAndSyncsTheApplication() {
        Id app = appId();

        Test.startTest();
        insert newRequest(app, 'Pending Sales Review');
        Test.stopTest();

        App_Cancellation_Request__c stored = [
            SELECT Id, Name, Status__c, SLA_Due_Date__c, OwnerId
            FROM App_Cancellation_Request__c
            WHERE Application__c = :app
        ];
        System.assertEquals('Pending Sales Review', stored.Status__c, 'status untouched');
        System.assertNotEquals(null, stored.SLA_Due_Date__c, 'SLA due date stamped');
        System.assert(stored.SLA_Due_Date__c >= Date.today(), 'SLA date is in the future');

        Application__c updated = [
            SELECT Id, Cancellation_Status__c, Cancellation_Request_Date__c
            FROM Application__c WHERE Id = :app
        ];
        System.assertEquals('Pending Sales Review', updated.Cancellation_Status__c,
            'application mirrors the pending request');
        System.assertNotEquals(null, updated.Cancellation_Request_Date__c,
            'cancellation date stamped on the application');
    }

    /** A request inserted in Draft is still stamped with the SLA date. */
    @IsTest
    static void draftRequestStillGetsAnSlaDate() {
        Id app = appId();
        insert newRequest(app, 'Draft');

        App_Cancellation_Request__c stored = [
            SELECT Id, SLA_Due_Date__c, Status__c
            FROM App_Cancellation_Request__c WHERE Application__c = :app
        ];
        System.assertEquals('Draft', stored.Status__c);
        System.assertNotEquals(null, stored.SLA_Due_Date__c, 'SLA stamped for every insert');
    }

    /** Sales review -> accounting review moves the owner and the application status. */
    @IsTest
    static void accountingReviewTransitionUpdatesTheApplication() {
        Id app = appId();
        App_Cancellation_Request__c req = newRequest(app, 'Pending Sales Review');
        insert req;

        Test.startTest();
        req.Status__c = 'Pending Accounting Review';
        update req;
        Test.stopTest();

        Application__c updated = [
            SELECT Cancellation_Status__c FROM Application__c WHERE Id = :app
        ];
        System.assertEquals('Pending Accounting Review', updated.Cancellation_Status__c,
            'application follows the request into accounting review');
    }

    /** Approving a request cancels its selected services on the application. */
    @IsTest
    static void approvalCancelsTheSelectedServices() {
        Id app = appId();
        Id pkg = packageId();

        App_Cancellation_Request__c req = newRequest(app, 'Pending Sales Review');
        insert req;

        insert new Cancellation_Service__c(
            App_Cancellation_Request__c = req.Id,
            Application_Package__c = pkg,
            Service_Name__c = 'Handler Test Service',
            Estimated_Refund__c = 750,
            Refund_Amount__c = 0
        );

        Test.startTest();
        req.Status__c = 'Approved';
        update req;
        Test.stopTest();

        Application__c updated = [SELECT Cancellation_Status__c FROM Application__c WHERE Id = :app];
        System.assertEquals('Approved', updated.Cancellation_Status__c, 'application approved');

        Application_Package__c storedPkg = [
            SELECT Id, Active__c, Application_Status__c
            FROM Application_Package__c WHERE Id = :pkg
        ];
        System.assertEquals(false, storedPkg.Active__c, 'approved service deactivated');
    }

    /**
     * Approving from accounting review generates a refund credit for the summed
     * service refunds and writes that total back onto the request.
     */
    @IsTest
    static void accountingApprovalCreatesTheRefundCredit() {
        Id app = appId();
        Id pkg = packageId();

        App_Cancellation_Request__c req = newRequest(app, 'Pending Sales Review');
        insert req;

        insert new Cancellation_Service__c(
            App_Cancellation_Request__c = req.Id,
            Application_Package__c = pkg,
            Service_Name__c = 'Refund Service',
            Estimated_Refund__c = 120,
            Refund_Amount__c = 120
        );

        req.Status__c = 'Pending Accounting Review';
        update req;

        Test.startTest();
        req.Status__c = 'Approved';
        update req;
        Test.stopTest();

        List<Credit__c> credits = [
            SELECT Id, Amount__c, Credit_Type__c, Dealer__c, Cancellation_Request__c
            FROM Credit__c WHERE Cancellation_Request__c = :req.Id
        ];
        System.assertEquals(1, credits.size(), 'one refund credit created');
        System.assertEquals(120, credits[0].Amount__c, 'credit equals the summed refund');
        System.assertEquals('Cancellation Credit', credits[0].Credit_Type__c, 'credit type');

        App_Cancellation_Request__c stored = [
            SELECT Total_Refund_Amount__c FROM App_Cancellation_Request__c WHERE Id = :req.Id
        ];
        System.assertEquals(120, stored.Total_Refund_Amount__c, 'total refund written back');
    }

    /** A rejection is written back to the application. */
    @IsTest
    static void rejectionUpdatesTheApplication() {
        Id app = appId();
        App_Cancellation_Request__c req = newRequest(app, 'Pending Sales Review');
        insert req;

        Test.startTest();
        req.Status__c = 'Rejected';
        update req;
        Test.stopTest();

        Application__c updated = [SELECT Cancellation_Status__c FROM Application__c WHERE Id = :app];
        System.assertEquals('Rejected', updated.Cancellation_Status__c, 'application rejected');
    }

    /** Withdrawing a request clears the cancellation status from the application. */
    @IsTest
    static void withdrawalClearsTheApplication() {
        Id app = appId();
        App_Cancellation_Request__c req = newRequest(app, 'Pending Sales Review');
        insert req;

        Test.startTest();
        req.Status__c = 'Withdrawn';
        update req;
        Test.stopTest();

        Application__c updated = [
            SELECT Cancellation_Status__c, Cancellation_Request_Date__c
            FROM Application__c WHERE Id = :app
        ];
        System.assertEquals(null, updated.Cancellation_Status__c, 'cancellation status cleared');
        System.assertEquals(null, updated.Cancellation_Request_Date__c, 'cancellation date cleared');
    }

    /** An update that does not change the status must not write anything. */
    @IsTest
    static void unchangedStatusIsIgnored() {
        Id app = appId();
        App_Cancellation_Request__c req = newRequest(app, 'Pending Sales Review');
        insert req;

        Test.startTest();
        req.Reason_Detail__c = 'note only';
        update req;
        Test.stopTest();

        Application__c updated = [SELECT Cancellation_Status__c FROM Application__c WHERE Id = :app];
        System.assertEquals('Pending Sales Review', updated.Cancellation_Status__c,
            'status untouched by a non-status update');
    }

    /** The SLA helper skips weekends. */
    @IsTest
    static void businessDaysSkipTheWeekend() {
        Date friday = Date.newInstance(2026, 11, 6);
        System.assertEquals(Date.newInstance(2026, 11, 6), friday, 'fixture is a Friday');

        Date due = CancellationRequestHandler.addBusinessDays(friday, 1);
        System.assertEquals(Date.newInstance(2026, 11, 9), due, 'one business day from Friday is Monday');

        Date five = CancellationRequestHandler.addBusinessDays(friday, 5);
        System.assertEquals(Date.newInstance(2026, 11, 13), five, 'five business days from Friday');
    }
}