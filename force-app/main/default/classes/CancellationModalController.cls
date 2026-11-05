/**
 * CancellationModalController
 *
 * Server side of the c-cancellation-modal LWC (Application record quick action).
 *
 * Hardening notes
 *  - Every entry point resolves the application and then runs the dealer
 *    ownership guard. Internal users (the record action) bypass it; a
 *    PowerPartner user must own the application's dealer account. Applying it to
 *    getApplicationDetails closes the read-path IDOR that let a portal user read
 *    any application's services and contract premiums by id.
 *  - A null or blank reason, and an empty or null service selection, are refused
 *    with a user-readable AuraHandledException before anything is written. This
 *    also stops an empty selection from flipping an application with no active
 *    packages to Cancelled.
 *  - cancelSelectedPackages validates its input too: it is public and called by
 *    ApplicationCancellationController.savePoliciesAndCancel and by
 *    CancellationRequestHandler.cancelPackagesForApprovedRequests, as well as
 *    from the submit path here.
 *
 * Known dead branch (left in place deliberately): the 'Quote' checks below can
 * never be true, because Application_Status__c is a restricted picklist with
 * only Draft / Submitted / Active / Cancelled. They are harmless and match what
 * the LWC already assumes; removing them is a separate, cosmetic change.
 */
public without sharing class CancellationModalController {

    /**
     * Test seam, mirroring CancellationFormController. A partner-community user
     * cannot be created inside a test, so the dealer account the ownership guard
     * compares against is injected here instead. It is private (so no other
     * class can set it) and only honoured while a test is running, so production
     * behaviour is unchanged when it is null.
     */
    @TestVisible private static Id dealerAccountOverride;

    private static final String ERR_NO_APPLICATION = 'No application was supplied.';
    private static final String ERR_APPLICATION_NOT_FOUND = 'Application not found.';
    private static final String ERR_NO_SELECTION = 'Select at least one service to cancel.';
    private static final String ERR_NO_REASON = 'Please select a cancellation reason.';
    private static final String ERR_FOREIGN_SERVICE =
        'One or more selected services do not belong to this application or are no longer active.';
    private static final String ERR_FOREIGN_PACKAGE =
        'A selected service does not belong to this application.';
    private static final String ERR_OTHER_DEALER = 'This application belongs to another dealership.';
    private static final String ERR_NO_DEALER = 'Your portal user is not linked to a dealership.';

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getApplicationDetails(Id applicationId) {
        Application__c app = loadApplication(applicationId);
        assertDealerAccess(app);

        List<Application_Package__c> packages = [
            SELECT Id, Name, Coverage_Plan__c, Coverage_Term__c,
                   Contract_Premium_Price__c, Dealer_Package_Retail_Price__c,
                   Active__c, Package_Record_Type__c
            FROM Application_Package__c
            WHERE Application__c = :app.Id AND Active__c = true
            ORDER BY Name ASC
        ];

        List<Map<String, Object>> services = new List<Map<String, Object>>();
        for (Application_Package__c pkg : packages) {
            Map<String, Object> svc = new Map<String, Object>();
            svc.put('id', pkg.Id);
            svc.put('name', pkg.Name);
            svc.put('coveragePlan', pkg.Coverage_Plan__c);
            svc.put('coverageTerm', pkg.Coverage_Term__c);
            svc.put('price', pkg.Contract_Premium_Price__c != null ? pkg.Contract_Premium_Price__c : 0);
            svc.put('retailPrice', pkg.Dealer_Package_Retail_Price__c != null ? pkg.Dealer_Package_Retail_Price__c : 0);
            svc.put('active', pkg.Active__c);
            svc.put('packageType', pkg.Package_Record_Type__c);
            services.add(svc);
        }

        Map<String, Object> appMap = new Map<String, Object>();
        appMap.put('id', app.Id);
        appMap.put('name', app.Name);
        appMap.put('status', app.Application_Status__c);
        appMap.put('cancellationStatus', app.Cancellation_Status__c);

        Map<String, Object> result = new Map<String, Object>();
        result.put('application', appMap);
        result.put('services', services);

        return result;
    }

    public static void cancelSelectedPackages(Id applicationId, List<Id> packageIds) {
        if (packageIds == null || packageIds.isEmpty()) {
            throw new AuraHandledException(ERR_NO_SELECTION);
        }
        Application__c app = loadApplication(applicationId);
        assertDealerAccess(app);

        List<Application_Package__c> allowed = [
            SELECT Id FROM Application_Package__c
            WHERE Id IN :packageIds AND Application__c = :applicationId
        ];
        Set<Id> allowedIds = new Set<Id>();
        for (Application_Package__c p : allowed) {
            allowedIds.add(p.Id);
        }
        if (allowedIds.size() != packageIds.size()) {
            throw new AuraHandledException(ERR_FOREIGN_PACKAGE);
        }
        List<Application_Package__c> packagesToUpdate = new List<Application_Package__c>();
        for (Id pkgId : packageIds) {
            Application_Package__c pkg = new Application_Package__c(Id = pkgId);
            pkg.Active__c = false;
            pkg.Application_Status__c = 'Cancelled';
            packagesToUpdate.add(pkg);
        }
        if (!packagesToUpdate.isEmpty()) {
            update packagesToUpdate;
        }

        Integer activeCount = [
            SELECT COUNT() FROM Application_Package__c
            WHERE Application__c = :applicationId AND Active__c = true
        ];

        if (activeCount == 0) {
            Application__c appToUpdate = new Application__c(Id = applicationId);
            appToUpdate.Application_Status__c = 'Cancelled';
            update appToUpdate;
        }
    }

    @AuraEnabled
    public static Id submitCancellationRequest(Id applicationId, List<Id> serviceIds, String reason, String details) {
        Application__c app = loadApplication(applicationId);
        assertDealerAccess(app);

        // Validate before anything is written: an empty selection must never
        // create a request (nor flip an application with no active packages to
        // Cancelled), and a blank reason must never be stored as "null".
        if (serviceIds == null || serviceIds.isEmpty()) {
            throw new AuraHandledException(ERR_NO_SELECTION);
        }
        if (String.isBlank(reason)) {
            throw new AuraHandledException(ERR_NO_REASON);
        }

        String appStatus = app.Application_Status__c;
        String requestStatus;
        if (appStatus == 'Draft' || appStatus == 'Quote') {
            requestStatus = 'Approved';
        } else {
            requestStatus = 'Pending Sales Review';
        }

        // Determine if application is in a pending/unpaid status
        Boolean isUnpaid = appStatus == 'Draft' || appStatus == 'Quote'
            || (appStatus != null && appStatus.containsIgnoreCase('Pending'));

        // Application scoping: a selected service must belong to THIS application.
        // Without it a request could be filed against one application while
        // deactivating another application's packages.
        List<Application_Package__c> selectedPackages = [
            SELECT Id, Contract_Premium_Price__c
            FROM Application_Package__c
            WHERE Id IN :serviceIds
              AND Application__c = :applicationId
              AND Active__c = true
        ];
        if (selectedPackages.size() != serviceIds.size()) {
            throw new AuraHandledException(ERR_FOREIGN_SERVICE);
        }

        Decimal totalRefund = 0;
        if (!isUnpaid) {
            for (Application_Package__c pkg : selectedPackages) {
                if (pkg.Contract_Premium_Price__c != null) {
                    totalRefund += pkg.Contract_Premium_Price__c;
                }
            }
        }

        App_Cancellation_Request__c request = new App_Cancellation_Request__c();
        request.Application__c = applicationId;
        request.Status__c = requestStatus;
        request.Reason__c = reason.trim()
            + (String.isNotBlank(details) ? '\n\nAdditional Details:\n' + details.trim() : '');
        request.Total_Refund_Amount__c = totalRefund;
        request.Date_Requested__c = Datetime.now();
        request.Requested_By__c = UserInfo.getUserId();
        request.Requested_By_Name__c = UserInfo.getName();
        request.Refund_Eligible__c = !isUnpaid && totalRefund > 0;
        request.Payment_Status_At_Request__c = appStatus;
        insert request;

        List<Cancellation_Service__c> cancServices = new List<Cancellation_Service__c>();
        for (Application_Package__c pkg : selectedPackages) {
            Cancellation_Service__c cs = new Cancellation_Service__c();
            cs.App_Cancellation_Request__c = request.Id;
            cs.Application_Package__c = pkg.Id;
            cs.Refund_Amount__c = isUnpaid ? 0 : (pkg.Contract_Premium_Price__c != null ? pkg.Contract_Premium_Price__c : 0);
            cancServices.add(cs);
        }
        if (!cancServices.isEmpty()) {
            insert cancServices;
        }

        // For Draft/Quote applications, immediately cancel selected packages
        if (requestStatus == 'Approved') {
            cancelSelectedPackages(applicationId, serviceIds);
        }

        return request.Id;
    }

    // --------------------------------------------------------------- internals

    private static Application__c loadApplication(Id applicationId) {
        if (applicationId == null) {
            throw new AuraHandledException(ERR_NO_APPLICATION);
        }
        List<Application__c> apps = [
            SELECT Id, Name, Application_Status__c, Cancellation_Status__c, Dealer_Name__c
            FROM Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            throw new AuraHandledException(ERR_APPLICATION_NOT_FOUND);
        }
        return apps[0];
    }

    /**
     * Portal users may only act on their own dealership's applications.
     * Internal users (the record action) are unaffected.
     */
    private static void assertDealerAccess(Application__c app) {
        Id scopedDealerId = accessScopedDealerAccountId();
        if (scopedDealerId == null) {
            return; // internal user
        }
        if (app.Dealer_Name__c == null || app.Dealer_Name__c != scopedDealerId) {
            throw new AuraHandledException(ERR_OTHER_DEALER);
        }
    }

    /**
     * Returns the dealer account the running user is confined to, or null when
     * the user is internal and therefore unrestricted.
     */
    private static Id accessScopedDealerAccountId() {
        if (Test.isRunningTest() && dealerAccountOverride != null) {
            return dealerAccountOverride;
        }
        if (UserInfo.getUserType() != 'PowerPartner') {
            return null;
        }
        List<User> me = [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        if (me.isEmpty() || me[0].ContactId == null) {
            throw new AuraHandledException(ERR_NO_DEALER);
        }
        List<Contact> contacts = [SELECT AccountId FROM Contact WHERE Id = :me[0].ContactId LIMIT 1];
        if (contacts.isEmpty() || contacts[0].AccountId == null) {
            throw new AuraHandledException(ERR_NO_DEALER);
        }
        return contacts[0].AccountId;
    }
}