/**
 * CancellationFormController
 *
 * Server side of the dealer portal Service Contract Cancellation Form.
 *
 * Security model
 *  - `with sharing`, and every read/write is scoped to the running user's dealer
 *    (User -> Contact -> Account). An application belonging to a different
 *    dealer is REFUSED with a message; it is never silently filtered away.
 *  - Package selection is validated against the application it is submitted for,
 *    so a dealer cannot cancel another application's services by passing ids.
 *  - Pricing and refund amounts are computed here, never trusted from the client.
 *
 * Approval
 *  - The controller inserts the request with Status = 'Pending Sales Review'.
 *    CancellationRequestTrigger/CancellationRequestHandler then sets the SLA date,
 *    routes to the Sales queue and submits the approval process. The controller
 *    does NOT submit it again; it verifies afterwards that a pending approval
 *    actually exists and reports failure if it does not, so a swallowed
 *    approval error can never be shown to the dealer as success.
 */
public with sharing class CancellationFormController {

    public class CancellationFormException extends Exception {}

    /** Test seam: tests cannot create a community user, so they set the dealer here. */
    @TestVisible private static Id dealerAccountOverride;

    private static final String STATUS_PENDING_SALES = 'Pending Sales Review';
    private static final String SETTINGS_DEFAULT = 'Default';
    private static final String DEFAULT_TERMS_VERSION = '1.0';
    private static final Integer MAX_PNG_CHARS = 3000000; // ~2 MB decoded

    /**
     * Shown when the entry point was handed something that is not an
     * Application__c id at all - a ListView id (00B...) being the realistic case,
     * because the Applications list page passes its own id in the url.
     */
    public static final String LINK_MESSAGE =
        'This link doesn\'t point to an application — open it from the Applications list.';

    /** Test seam: forces the approval probe to fail after the request row is inserted. */
    @TestVisible private static Boolean forceApprovalProbeFailure = false;

    private static final Set<String> OPEN_STATUSES = new Set<String>{
        'Draft', STATUS_PENDING_SALES, 'Pending Accounting Review'
    };

    private static final Set<String> REASON_CODES = new Set<String>{
        'Customer Request', 'Vehicle Sold/Traded', 'Repossession',
        'Total Loss', 'Contract Back Out', 'Other'
    };

    // ------------------------------------------------------------------ DTOs

    public class AddOn {
        @AuraEnabled public String name;
        @AuraEnabled public Decimal price;
    }

    public class PackageLine {
        @AuraEnabled public String packageId;
        @AuraEnabled public String name;
        /**
         * Real service category, taken from Dealer_Package__r.Plan_Type__r.Name
         * (the Package_Group lookup). Null when the dealer package has no plan
         * type assigned - the UI may then fall back to its own heuristic.
         */
        @AuraEnabled public String category;
        @AuraEnabled public String term;
        @AuraEnabled public Decimal retailPrice;
        @AuraEnabled public Decimal addOnsTotal;
        @AuraEnabled public Decimal estimate;
        @AuraEnabled public List<AddOn> addOns;
    }

    public class FormContext {
        @AuraEnabled public String applicationId;
        @AuraEnabled public String applicationNumber;
        @AuraEnabled public String customerName;
        @AuraEnabled public String vehicle;
        @AuraEnabled public String vin;
        @AuraEnabled public String status;
        @AuraEnabled public String dealerName;
        @AuraEnabled public String dealerAddress;
        @AuraEnabled public String dealerPhone;
        @AuraEnabled public String dealerEmail;
        @AuraEnabled public String repName;
        @AuraEnabled public String repTitle;
        @AuraEnabled public String termsVersion;
        @AuraEnabled public String termsText;
        @AuraEnabled public Boolean hasOpenRequest;
        @AuraEnabled public Boolean eligible;
        @AuraEnabled public String ineligibleReason;
        @AuraEnabled public List<PackageLine> packages;
        @AuraEnabled public Decimal estimatedTotal;
    }

    public class EstimateResult {
        @AuraEnabled public List<PackageLine> lines;
        @AuraEnabled public Decimal total;
    }

    public class SubmitResult {
        /**
         * True only when the request reached a pending approval. The record is
         * reported to the caller on `requestId`, not on this flag: a request that
         * was saved but not routed still exists and must be shown as saved.
         */
        @AuraEnabled public Boolean success;
        @AuraEnabled public Id requestId;
        @AuraEnabled public String requestName;
        @AuraEnabled public String message;
        /** True when the signature image was stored and linked to the request. */
        @AuraEnabled public Boolean signatureStored;
        /** True when the cancellation form PDF was stored and linked to the request. */
        @AuraEnabled public Boolean pdfStored;
        /** Non-fatal problem the dealer should be told about (record still exists). */
        @AuraEnabled public String warning;
    }

    public class RequestRow {
        @AuraEnabled public Id requestId;
        @AuraEnabled public String requestName;
        @AuraEnabled public String dateIso;
        @AuraEnabled public String applicationNumber;
        @AuraEnabled public String customerName;
        @AuraEnabled public String vehicle;
        @AuraEnabled public String vin;
        @AuraEnabled public String services;
        @AuraEnabled public String reason;
        @AuraEnabled public Decimal estimatedAmount;
        @AuraEnabled public Decimal approvedAmount;
        @AuraEnabled public String refundNote;
        @AuraEnabled public String statusKey;
        @AuraEnabled public String statusLabel;
    }

    public class RequestSummary {
        @AuraEnabled public String requestName;
        @AuraEnabled public String statusLabel;
        @AuraEnabled public String applicationNumber;
        @AuraEnabled public String customerName;
        @AuraEnabled public String vehicle;
        @AuraEnabled public String vin;
        @AuraEnabled public String reason;
        @AuraEnabled public String reasonDetail;
        @AuraEnabled public Decimal estimatedAmount;
        @AuraEnabled public Decimal approvedAmount;
        @AuraEnabled public String refundNote;
        @AuraEnabled public String submittedBy;
        @AuraEnabled public String repTitle;
        @AuraEnabled public String submittedOn;
        @AuraEnabled public List<PackageLine> services;
    }

    // ------------------------------------------------------------ entry points

    @AuraEnabled(cacheable=false)
    public static FormContext getFormContext(Id applicationId) {
        assertApplicationId(applicationId);
        Id dealerId = currentDealerAccountId();
        Application__c app = loadApplication(applicationId, dealerId);
        User me = runningUser();
        Id repContactId = me.ContactId;

        FormContext ctx = new FormContext();
        ctx.applicationId = app.Id;
        ctx.applicationNumber = app.Name;
        ctx.customerName = trimAll(new List<String>{ app.Customer_First_Name__c, app.Customer_Last_Name__c });
        ctx.vehicle = trimAll(new List<String>{ app.Vehicle_Year__c, app.Vehicle_Make__c, app.Vehicle_Model__c });
        ctx.vin = app.Vehicle_VIN__c;
        ctx.status = app.Application_Status__c;
        ctx.dealerName = app.Dealer_Name__r != null ? app.Dealer_Name__r.Name : null;
        ctx.dealerAddress = dealerAddress(app.Dealer_Name__r, app.Dealer_Address__c);
        ctx.dealerPhone = app.Dealer_Name__r != null && String.isNotBlank(app.Dealer_Name__r.Phone)
            ? app.Dealer_Name__r.Phone : app.Dealer_Phone__c;
        ctx.dealerEmail = app.Dealer_Name__r != null ? app.Dealer_Name__r.Email__c : null;
        ctx.hasOpenRequest = hasOpenRequest(applicationId);
        ctx.eligible = true;

        if (repContactId != null) {
            List<Contact> reps = [SELECT Name, Title FROM Contact WHERE Id = :repContactId LIMIT 1];
            if (!reps.isEmpty()) {
                ctx.repName = reps[0].Name;
                ctx.repTitle = reps[0].Title;
            }
        }
        if (String.isBlank(ctx.repName)) {
            ctx.repName = me.Name;
        }

        Cancellation_Settings__mdt settings = loadSettings();
        ctx.termsVersion = settings != null && String.isNotBlank(settings.Terms_Version__c)
            ? settings.Terms_Version__c : DEFAULT_TERMS_VERSION;
        ctx.termsText = settings != null ? settings.Terms_Text__c : null;

        if (app.Application_Status__c == 'Cancelled' || app.Application_Status__c == 'Deleted') {
            ctx.eligible = false;
            ctx.ineligibleReason = 'This application is ' + app.Application_Status__c.toLowerCase() + ' and cannot be cancelled.';
        } else if (ctx.hasOpenRequest) {
            ctx.eligible = false;
            ctx.ineligibleReason = 'A cancellation request is already open for this application.';
        }

        ctx.packages = loadPackages(applicationId, dealerId);
        Decimal total = 0;
        for (PackageLine line : ctx.packages) {
            total += line.estimate;
        }
        ctx.estimatedTotal = total;
        return ctx;
    }

    @AuraEnabled(cacheable=false)
    public static EstimateResult estimateRefund(Id applicationId, List<Id> packageIds) {
        assertApplicationId(applicationId);
        if (packageIds == null || packageIds.isEmpty()) {
            EstimateResult empty = new EstimateResult();
            empty.lines = new List<PackageLine>();
            empty.total = 0;
            return empty;
        }
        Id dealerId = currentDealerAccountId();
        loadApplication(applicationId, dealerId);

        EstimateResult result = new EstimateResult();
        result.lines = new List<PackageLine>();
        result.total = 0;
        for (PackageLine line : loadPackages(applicationId, dealerId)) {
            if (packageIds.contains(line.packageId)) {
                result.lines.add(line);
                result.total += line.estimate;
            }
        }
        if (result.lines.size() != packageIds.size()) {
            throw new CancellationFormException('One or more selected services do not belong to this application.');
        }
        return result;
    }

    @AuraEnabled
    public static SubmitResult submitRequest(
            Id applicationId,
            List<Id> packageIds,
            String reasonCode,
            String reasonDetail,
            Boolean termsAccepted,
            String termsVersion,
            String signaturePngB64,
            String repName,
            String repTitle) {

        assertApplicationId(applicationId);
        Id dealerId = currentDealerAccountId();
        Application__c app = loadApplication(applicationId, dealerId);

        if (app.Application_Status__c == 'Cancelled' || app.Application_Status__c == 'Deleted') {
            throw new CancellationFormException('This application is already ' + app.Application_Status__c.toLowerCase() + '.');
        }
        if (packageIds == null || packageIds.isEmpty()) {
            throw new CancellationFormException('Select at least one service to cancel.');
        }
        if (String.isBlank(reasonCode) || !REASON_CODES.contains(reasonCode)) {
            throw new CancellationFormException('Select a reason for cancellation.');
        }
        if (reasonCode == 'Other' && String.isBlank(reasonDetail)) {
            throw new CancellationFormException('Please explain the reason for cancellation.');
        }
        if (termsAccepted != true) {
            throw new CancellationFormException('The cancellation terms must be accepted.');
        }
        String currentVersion = currentTermsVersion();
        String submittedVersion = String.isBlank(termsVersion) ? currentVersion : termsVersion.trim();
        if (submittedVersion != currentVersion) {
            throw new CancellationFormException('The cancellation terms have changed. Reload the form and accept them again.');
        }
        if (String.isBlank(signaturePngB64)) {
            throw new CancellationFormException('A dealer representative signature is required.');
        }
        String png = signaturePngB64.trim();
        if (png.startsWith('data:')) {
            Integer comma = png.indexOf(',');
            png = comma >= 0 ? png.substring(comma + 1) : png;
        }
        if (!png.startsWith('iVBORw0KGgo')) {
            throw new CancellationFormException('The signature could not be read. Please sign again.');
        }
        if (png.length() > MAX_PNG_CHARS) {
            throw new CancellationFormException('The signature is too large. Please sign again.');
        }
        if (hasOpenRequest(applicationId)) {
            throw new CancellationFormException('A cancellation request is already open for this application.');
        }

        // Package validation: every id must belong to this application and be active.
        List<Application_Package__c> selected = [
            SELECT Id, Name, Dealer_Package__c,
                   Dealer_Package__r.Name,
                   Dealer_Package_Term__r.Name,
                   Dealer_Package_Retail_Price__c,
                   Dealer_Package_Price__c,
                   Add_Ons_Retail_Price__c,
                   Add_Ons_Price__c
            FROM Application_Package__c
            WHERE Id IN :packageIds
              AND Application__c = :applicationId
              AND Active__c = true
        ];
        if (selected.size() != packageIds.size()) {
            throw new CancellationFormException('One or more selected services do not belong to this application or are no longer active.');
        }
        for (Application_Package__c pkg : selected) {
            List<App_Cancellation_Request__c> openForPackage = [
                SELECT Id
                FROM App_Cancellation_Request__c
                WHERE Status__c IN :OPEN_STATUSES
                  AND Id IN (SELECT App_Cancellation_Request__c FROM Cancellation_Service__c WHERE Application_Package__c = :pkg.Id)
                LIMIT 1
            ];
            if (!openForPackage.isEmpty()) {
                throw new CancellationFormException('Service ' + pkg.Name + ' is already on an open cancellation request.');
            }
        }

        Decimal total = 0;
        Map<Id, Decimal> estimateByPackage = new Map<Id, Decimal>();
        Map<Id, String> optionsByPackage = new Map<Id, String>();
        for (PackageLine line : loadPackages(applicationId, dealerId)) {
            estimateByPackage.put(line.packageId, line.estimate);
            optionsByPackage.put(line.packageId, describeAddOns(line.addOns));
            total += line.estimate;
        }

        App_Cancellation_Request__c request = new App_Cancellation_Request__c(
            Application__c = app.Id,
            Status__c = STATUS_PENDING_SALES,
            Reason_Code__c = reasonCode,
            Reason_Detail__c = String.isBlank(reasonDetail) ? null : reasonDetail.trim(),
            Reason__c = buildLegacyReason(reasonCode, reasonDetail),
            Date_Requested__c = Datetime.now(),
            Requested_By__c = UserInfo.getUserId(),
            Requested_By_Name__c = UserInfo.getName(),
            Payment_Status_At_Request__c = String.isBlank(app.Application_Status__c) ? null : app.Application_Status__c.left(50),
            Refund_Eligible__c = total > 0,
            Total_Refund_Amount__c = total,
            Terms_Version__c = currentVersion,
            Terms_Accepted__c = true,
            Terms_Accepted_On__c = Datetime.now(),
            Authorized_Rep_Name__c = String.isBlank(repName) ? UserInfo.getName() : repName.trim(),
            Authorized_Rep_Title__c = String.isBlank(repTitle) ? null : repTitle.trim(),
            Dealer_Snapshot__c = app.Dealer_Name__r != null ? app.Dealer_Name__r.Name : null,
            Dealer_Address_Snapshot__c = dealerAddress(app.Dealer_Name__r, app.Dealer_Address__c),
            Customer_Name_Snapshot__c = trimAll(new List<String>{ app.Customer_First_Name__c, app.Customer_Last_Name__c }),
            Vehicle_Snapshot__c = trimAll(new List<String>{ app.Vehicle_Year__c, app.Vehicle_Make__c, app.Vehicle_Model__c }),
            VIN_Snapshot__c = app.Vehicle_VIN__c,
            Submitted_From_Portal__c = true
        );
        insert request;

        // ------------------------------------------------------------------
        // From here on the request EXISTS and must stay. Nothing below may throw
        // out of this method: an uncaught exception rolls the whole transaction
        // back, so the dealer would see "failed" while no trace of the attempt
        // remains anywhere in the org. That is exactly how every portal
        // submission before this change vanished.
        // ------------------------------------------------------------------
        SubmitResult result = new SubmitResult();
        result.requestId = request.Id;
        result.requestName = request.Name;
        result.signatureStored = false;
        result.pdfStored = false;

        // The after-insert trigger has already stamped the CR-number onto Name, so
        // the record we inserted still carries the id-derived placeholder. Read the
        // stored value back so the dealer is shown CR-00034, never an 18-char id.
        try {
            List<App_Cancellation_Request__c> named = [
                SELECT Id, Name FROM App_Cancellation_Request__c WHERE Id = :request.Id LIMIT 1
            ];
            if (!named.isEmpty() && String.isNotBlank(named[0].Name)) {
                result.requestName = named[0].Name;
            }
        } catch (Exception ignored) {
            // Display only - the id-derived name is still better than an error.
        }

        List<Cancellation_Service__c> services = new List<Cancellation_Service__c>();
        for (Application_Package__c pkg : selected) {
            services.add(new Cancellation_Service__c(
                App_Cancellation_Request__c = request.Id,
                Application_Package__c = pkg.Id,
                Service_Name__c = pkg.Dealer_Package__r != null ? pkg.Dealer_Package__r.Name : pkg.Name,
                Term_Text__c = pkg.Dealer_Package_Term__r != null ? pkg.Dealer_Package_Term__r.Name : null,
                Options_Text__c = optionsByPackage.get(pkg.Id),
                Estimated_Refund__c = estimateByPackage.containsKey(pkg.Id) ? estimateByPackage.get(pkg.Id) : 0,
                Refund_Amount__c = 0
            ));
        }
        if (!services.isEmpty()) {
            try {
                // Same reason as the signature: the trigger has already moved the
                // request to the Sales queue, so a sharing-checked child insert
                // fails for the dealer.
                new RequestWriter().insertServices(services);
            } catch (Exception e) {
                result.warning = 'Your request was saved, but its service lines could not be recorded. A-Protect has been notified.';
                noteSafely(request.Id, 'Service lines could not be inserted: ' + e.getMessage());
            }
        }

        // The signature is published into the request record. This has to run
        // without sharing: the after-insert trigger moves the request to the Sales
        // review queue, which takes the record away from the portal user, and a
        // record-sharing-checked publish fails for them.
        try {
            new RequestWriter().attachSignature(request.Id, app.Name, png);
            result.signatureStored = true;
        } catch (Exception e) {
            result.warning = String.isBlank(result.warning)
                ? 'Your request was saved, but the signature image could not be attached. A-Protect has been notified.'
                : result.warning;
            noteSafely(request.Id, 'Signature could not be attached: ' + e.getMessage());
        }

        // A lone PNG is not a document. Render the cancellation form itself - the
        // same layout and styling the dealer just signed - and publish that onto
        // the record as well. Never fatal: the request already exists.
        try {
            CancellationPdfService.PdfResult pdf = CancellationPdfService.generateAndAttach(request.Id);
            if (pdf.getSucceeded()) {
                result.pdfStored = true;
            } else {
                noteSafely(request.Id, 'Cancellation PDF could not be generated: ' + pdf.error);
                // The synchronous render runs inside the dealer's Lightning
                // transaction, where VF-to-PDF can be refused. Retry once
                // asynchronously rather than losing the document.
                try {
                    System.enqueueJob(new CancellationPdfQueueable(request.Id));
                    result.warning = String.isBlank(result.warning)
                        ? 'Your request was saved. The signed cancellation form PDF is still being generated and will appear on the request shortly.'
                        : result.warning;
                } catch (Exception queueError) {
                    result.warning = String.isBlank(result.warning)
                        ? 'Your request was saved, but the signed cancellation form PDF could not be generated. A-Protect has been notified.'
                        : result.warning;
                    noteSafely(request.Id, 'Cancellation PDF queueable could not be enqueued: ' + queueError.getMessage());
                }
            }
        } catch (Exception e) {
            result.warning = String.isBlank(result.warning)
                ? 'Your request was saved, but the signed cancellation form PDF could not be generated. A-Protect has been notified.'
                : result.warning;
            noteSafely(request.Id, 'Cancellation PDF could not be generated: ' + e.getMessage());
        }

        // The trigger submits the approval. Verify it actually happened rather than
        // trusting a path that logs its failures to the debug log.
        Boolean routed = false;
        try {
            if (forceApprovalProbeFailure) {
                throw new CancellationFormException('simulated approval probe failure');
            }
            routed = new ApprovalProbe().hasPendingApproval(request.Id);
        } catch (Exception e) {
            noteSafely(request.Id, 'Approval probe failed: ' + e.getMessage());
            routed = false;
        }

        if (routed) {
            result.success = true;
            result.message = 'Cancellation request submitted for review.';
        } else {
            noteSafely(request.Id, 'Request saved, but it could not be routed to the approval process. Check the queue and approval configuration.');
            result.success = false;
            result.message = 'Your request was saved but could not be routed for approval. Please contact A-Protect support.';
        }
        return result;
    }

    @AuraEnabled(cacheable=false)
    public static List<RequestRow> getRequests(String statusFilter, String monthFilter, String searchTerm, String sortBy) {
        Id dealerId = currentDealerAccountId();
        String soql =
            'SELECT Id, Name, Date_Requested__c, Status__c, Reason_Code__c, Reason__c, ' +
            'Total_Refund_Amount__c, Approved_Refund_Amount__c, Refund_Note__c, ' +
            'Application__r.Name, Application__r.Customer_First_Name__c, Application__r.Customer_Last_Name__c, ' +
            'Application__r.Vehicle_Year__c, Application__r.Vehicle_Make__c, Application__r.Vehicle_Model__c, ' +
            'Application__r.Vehicle_VIN__c ' +
            'FROM App_Cancellation_Request__c ' +
            'WHERE Application__r.Dealer_Name__c = :dealerId';

        // Declared here, not inside the if-blocks below: a bind variable must be
        // in scope where Database.query() runs.
        String likeTerm = null;
        Date startDate = null;
        Date endDate = null;

        if (String.isNotBlank(statusFilter) && statusFilter != 'all') {
            if (statusFilter == 'approved') {
                soql += ' AND Status__c = \'Approved\'';
            } else if (statusFilter == 'pending') {
                soql += ' AND Status__c IN (\'Draft\',\'Pending Sales Review\',\'Pending Accounting Review\')';
            }
        }
        if (String.isNotBlank(monthFilter) && monthFilter != 'all') {
            List<String> parts = monthFilter.split('-');
            if (parts.size() == 2) {
                Integer y = Integer.valueOf(parts[0]);
                Integer m = Integer.valueOf(parts[1]);
                startDate = Date.newInstance(y, m, 1);
                endDate = startDate.addMonths(1).addDays(-1);
                soql += ' AND Date_Requested__c >= :startDate AND Date_Requested__c <= :endDate';
            }
        }
        if (String.isNotBlank(searchTerm)) {
            likeTerm = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
            soql += ' AND (Name LIKE :likeTerm OR Application__r.Name LIKE :likeTerm OR Application__r.Customer_Last_Name__c LIKE :likeTerm OR Application__r.Vehicle_VIN__c LIKE :likeTerm)';
        }
        if (sortBy == 'oldest') {
            soql += ' ORDER BY Date_Requested__c ASC';
        } else if (sortBy == 'customer') {
            soql += ' ORDER BY Application__r.Customer_Last_Name__c ASC';
        } else if (sortBy == 'amount') {
            soql += ' ORDER BY Total_Refund_Amount__c DESC';
        } else {
            soql += ' ORDER BY Date_Requested__c DESC';
        }
        soql += ' LIMIT 500';

        List<RequestRow> rows = new List<RequestRow>();
        for (App_Cancellation_Request__c r : (List<App_Cancellation_Request__c>) Database.query(soql)) {
            RequestRow row = new RequestRow();
            row.requestId = r.Id;
            row.requestName = r.Name;
            row.dateIso = r.Date_Requested__c == null ? null : r.Date_Requested__c.format('yyyy-MM-dd');
            row.applicationNumber = r.Application__r != null ? r.Application__r.Name : null;
            row.customerName = trimAll(new List<String>{
                r.Application__r != null ? r.Application__r.Customer_First_Name__c : null,
                r.Application__r != null ? r.Application__r.Customer_Last_Name__c : null
            });
            row.vehicle = trimAll(new List<String>{
                r.Application__r != null ? r.Application__r.Vehicle_Year__c : null,
                r.Application__r != null ? r.Application__r.Vehicle_Make__c : null,
                r.Application__r != null ? r.Application__r.Vehicle_Model__c : null
            });
            row.vin = r.Application__r != null ? r.Application__r.Vehicle_VIN__c : null;
            row.reason = String.isNotBlank(r.Reason_Code__c) ? r.Reason_Code__c : r.Reason__c;
            row.estimatedAmount = r.Total_Refund_Amount__c;
            row.approvedAmount = r.Approved_Refund_Amount__c != null ? r.Approved_Refund_Amount__c : r.Total_Refund_Amount__c;
            row.refundNote = r.Refund_Note__c;
            row.statusKey = statusKey(r.Status__c);
            row.statusLabel = statusLabel(r.Status__c);
            rows.add(row);
        }
        if (!rows.isEmpty()) {
            Set<Id> requestIds = new Set<Id>();
            for (RequestRow row : rows) {
                requestIds.add(row.requestId);
            }
            Map<Id, List<String>> servicesByRequest = new Map<Id, List<String>>();
            for (Cancellation_Service__c cs : [
                SELECT App_Cancellation_Request__c, Service_Name__c
                FROM Cancellation_Service__c
                WHERE App_Cancellation_Request__c IN :requestIds
                ORDER BY Service_Name__c
            ]) {
                if (!servicesByRequest.containsKey(cs.App_Cancellation_Request__c)) {
                    servicesByRequest.put(cs.App_Cancellation_Request__c, new List<String>());
                }
                if (String.isNotBlank(cs.Service_Name__c)) {
                    servicesByRequest.get(cs.App_Cancellation_Request__c).add(cs.Service_Name__c);
                }
            }
            for (RequestRow row : rows) {
                List<String> names = servicesByRequest.get(row.requestId);
                row.services = names == null ? null : String.join(names, ', ');
            }
        }
        return rows;
    }

    @AuraEnabled(cacheable=false)
    public static RequestSummary getRequestSummary(Id requestId) {
        Id dealerId = currentDealerAccountId();
        List<App_Cancellation_Request__c> rows = [
            SELECT Id, Name, Status__c, Reason_Code__c, Reason_Detail__c, Reason__c,
                   Total_Refund_Amount__c, Approved_Refund_Amount__c, Refund_Note__c,
                   Date_Requested__c, Requested_By_Name__c, Authorized_Rep_Title__c,
                   Customer_Name_Snapshot__c, Vehicle_Snapshot__c, VIN_Snapshot__c,
                   Application__r.Name, Application__r.Dealer_Name__c
            FROM App_Cancellation_Request__c
            WHERE Id = :requestId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new CancellationFormException('Cancellation request not found.');
        }
        App_Cancellation_Request__c r = rows[0];
        if (r.Application__r == null || r.Application__r.Dealer_Name__c != dealerId) {
            throw new CancellationFormException('This cancellation request belongs to another dealership.');
        }
        RequestSummary s = new RequestSummary();
        s.requestName = r.Name;
        s.statusLabel = statusLabel(r.Status__c);
        s.applicationNumber = r.Application__r != null ? r.Application__r.Name : null;
        s.customerName = r.Customer_Name_Snapshot__c;
        s.vehicle = r.Vehicle_Snapshot__c;
        s.vin = r.VIN_Snapshot__c;
        s.reason = String.isNotBlank(r.Reason_Code__c) ? r.Reason_Code__c : r.Reason__c;
        s.reasonDetail = r.Reason_Detail__c;
        s.estimatedAmount = r.Total_Refund_Amount__c;
        s.approvedAmount = r.Approved_Refund_Amount__c;
        s.refundNote = r.Refund_Note__c;
        s.submittedBy = r.Requested_By_Name__c;
        s.repTitle = r.Authorized_Rep_Title__c;
        s.submittedOn = r.Date_Requested__c == null ? null : r.Date_Requested__c.format('d MMMM yyyy');
        s.services = new List<PackageLine>();
        for (Cancellation_Service__c cs : [
            SELECT Service_Name__c, Term_Text__c, Options_Text__c, Estimated_Refund__c, Refund_Amount__c
            FROM Cancellation_Service__c
            WHERE App_Cancellation_Request__c = :requestId
            ORDER BY Service_Name__c
        ]) {
            PackageLine line = new PackageLine();
            line.name = cs.Service_Name__c;
            line.term = cs.Term_Text__c;
            line.estimate = cs.Estimated_Refund__c;
            line.addOns = new List<AddOn>();
            s.services.add(line);
        }
        return s;
    }

    @AuraEnabled(cacheable=false)
    public static List<Map<String, String>> searchApplications(String term) {
        Id dealerId = currentDealerAccountId();
        List<Map<String, String>> out = new List<Map<String, String>>();
        if (String.isBlank(term) || term.trim().length() < 2) {
            return out;
        }
        String likeTerm = '%' + String.escapeSingleQuotes(term.trim()) + '%';
        for (Application__c app : [
            SELECT Id, Name, Application_Status__c, Customer_First_Name__c, Customer_Last_Name__c,
                   Vehicle_Year__c, Vehicle_Make__c, Vehicle_Model__c, Vehicle_VIN__c
            FROM Application__c
            WHERE Dealer_Name__c = :dealerId
              AND Application_Status__c NOT IN ('Deleted', 'Cancelled')
              AND (Name LIKE :likeTerm
                   OR Customer_Last_Name__c LIKE :likeTerm
                   OR Customer_First_Name__c LIKE :likeTerm
                   OR Vehicle_VIN__c LIKE :likeTerm)
            ORDER BY Name DESC
            LIMIT 20
        ]) {
            Map<String, String> row = new Map<String, String>();
            row.put('id', app.Id);
            row.put('applicationNumber', app.Name);
            row.put('status', app.Application_Status__c);
            row.put('customerName', trimAll(new List<String>{ app.Customer_First_Name__c, app.Customer_Last_Name__c }));
            row.put('vehicle', trimAll(new List<String>{ app.Vehicle_Year__c, app.Vehicle_Make__c, app.Vehicle_Model__c }));
            row.put('vin', app.Vehicle_VIN__c);
            out.add(row);
        }
        return out;
    }

    // --------------------------------------------------------------- internals

    /**
     * Guards the entry points against an id that is not an Application__c id.
     *
     * The Applications list page in the portal passes its own ListView id
     * (00B...) in the page url, so a dealer who opens the form from a bookmark
     * or a stale link hands us that instead. Loading it as an application used
     * to produce "Application not found." - technically true, useless to the
     * dealer, and the form still rendered underneath it.
     */
    private static void assertApplicationId(Id applicationId) {
        if (applicationId == null) {
            throw new CancellationFormException(LINK_MESSAGE);
        }
        if (applicationId.getSObjectType() != Application__c.SObjectType) {
            throw new CancellationFormException(LINK_MESSAGE);
        }
    }

    /** Writes a diagnostic note without ever letting the note itself fail the submit. */
    private static void noteSafely(Id requestId, String note) {
        try {
            new RequestWriter().noteFailure(requestId, note);
        } catch (Exception ignored) {
            // A missing note must never cost the dealer the request itself.
        }
    }

    private static User runningUser() {
        return [SELECT Id, Name, ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
    }

    private static Id currentDealerAccountId() {
        if (Test.isRunningTest() && dealerAccountOverride != null) {
            return dealerAccountOverride;
        }
        User me = runningUser();
        if (me.ContactId == null) {
            throw new CancellationFormException('Your portal user is not linked to a dealership.');
        }
        List<Contact> contacts = [SELECT AccountId FROM Contact WHERE Id = :me.ContactId LIMIT 1];
        if (contacts.isEmpty() || contacts[0].AccountId == null) {
            throw new CancellationFormException('Your portal user is not linked to a dealership.');
        }
        return contacts[0].AccountId;
    }

    private static Application__c loadApplication(Id applicationId, Id dealerId) {
        if (applicationId == null) {
            throw new CancellationFormException('No application was supplied.');
        }
        List<Application__c> apps = [
            SELECT Id, Name, Application_Status__c, Dealer_Name__c,
                   Customer_First_Name__c, Customer_Last_Name__c,
                   Vehicle_Year__c, Vehicle_Make__c, Vehicle_Model__c, Vehicle_VIN__c,
                   Dealer_Address__c, Dealer_Phone__c,
                   Dealer_Name__r.Name, Dealer_Name__r.Phone, Dealer_Name__r.Email__c,
                   Dealer_Name__r.BillingStreet, Dealer_Name__r.BillingCity,
                   Dealer_Name__r.BillingState, Dealer_Name__r.BillingPostalCode,
                   Dealer_Name__r.BillingCountry
            FROM Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            throw new CancellationFormException('Application not found.');
        }
        Application__c app = apps[0];
        if (app.Dealer_Name__c != dealerId) {
            throw new CancellationFormException('This application belongs to another dealership.');
        }
        return app;
    }

    private static List<PackageLine> loadPackages(Id applicationId, Id dealerId) {
        Map<Id, List<AddOn>> addOnsByDealerPackage = new Map<Id, List<AddOn>>();
        Set<Id> dealerPackageIds = new Set<Id>();
        for (Application_Package__c pkg : [
            SELECT Id, Dealer_Package__c
            FROM Application_Package__c
            WHERE Application__c = :applicationId AND Active__c = true
        ]) {
            if (pkg.Dealer_Package__c != null) {
                dealerPackageIds.add(pkg.Dealer_Package__c);
            }
        }
        if (!dealerPackageIds.isEmpty()) {
            for (Dealer_Package_Option__c opt : [
                SELECT Id, Dealer_Package__c, Option__r.Name,
                       Original_Package_Option_Price__c, Retail_Price__c
                FROM Dealer_Package_Option__c
                WHERE Dealer_Package__c IN :dealerPackageIds
                  AND Selection_Type__c = 'Optional'
                  AND Is_Removed__c = false
                ORDER BY Option__r.Name
            ]) {
                if (!addOnsByDealerPackage.containsKey(opt.Dealer_Package__c)) {
                    addOnsByDealerPackage.put(opt.Dealer_Package__c, new List<AddOn>());
                }
                AddOn addOn = new AddOn();
                addOn.name = opt.Option__r != null ? opt.Option__r.Name : null;
                addOn.price = opt.Retail_Price__c != null ? opt.Retail_Price__c : opt.Original_Package_Option_Price__c;
                addOnsByDealerPackage.get(opt.Dealer_Package__c).add(addOn);
            }
        }

        List<PackageLine> lines = new List<PackageLine>();
        for (Application_Package__c pkg : [
            SELECT Id, Name, Dealer_Package__c,
                   Dealer_Package__r.Name,
                   Dealer_Package__r.Plan_Type__r.Name,
                   Dealer_Package_Term__r.Name,
                   Dealer_Package_Retail_Price__c,
                   Dealer_Package_Price__c,
                   Add_Ons_Retail_Price__c,
                   Add_Ons_Price__c
            FROM Application_Package__c
            WHERE Application__c = :applicationId AND Active__c = true
            ORDER BY Name
        ]) {
            PackageLine line = new PackageLine();
            line.packageId = pkg.Id;
            line.name = pkg.Dealer_Package__r != null ? pkg.Dealer_Package__r.Name : pkg.Name;
            // Category comes from the plan type (Package_Group) - never derived from the name.
            line.category = pkg.Dealer_Package__r != null && pkg.Dealer_Package__r.Plan_Type__r != null
                ? pkg.Dealer_Package__r.Plan_Type__r.Name : null;
            line.term = pkg.Dealer_Package_Term__r != null ? pkg.Dealer_Package_Term__r.Name : null;
            line.retailPrice = pkg.Dealer_Package_Retail_Price__c != null
                ? pkg.Dealer_Package_Retail_Price__c : pkg.Dealer_Package_Price__c;
            line.addOnsTotal = pkg.Add_Ons_Retail_Price__c != null
                ? pkg.Add_Ons_Retail_Price__c : pkg.Add_Ons_Price__c;
            if (line.addOnsTotal == null) {
                line.addOnsTotal = 0;
            }
            line.estimate = (line.retailPrice == null ? 0 : line.retailPrice) + line.addOnsTotal;
            line.addOns = addOnsByDealerPackage.containsKey(pkg.Dealer_Package__c)
                ? addOnsByDealerPackage.get(pkg.Dealer_Package__c) : new List<AddOn>();
            lines.add(line);
        }
        return lines;
    }

    private static Boolean hasOpenRequest(Id applicationId) {
        return ![
            SELECT Id FROM App_Cancellation_Request__c
            WHERE Application__c = :applicationId AND Status__c IN :OPEN_STATUSES
            LIMIT 1
        ].isEmpty();
    }

    private static String currentTermsVersion() {
        Cancellation_Settings__mdt settings = loadSettings();
        return settings != null && String.isNotBlank(settings.Terms_Version__c)
            ? settings.Terms_Version__c : DEFAULT_TERMS_VERSION;
    }

    /**
     * Reads Cancellation_Settings__mdt.Default.
     *
     * NOT getInstance(): for a LongTextArea custom metadata field, getInstance()
     * returns Terms_Text__c cut at 255 characters (measured: 255 vs 2720 via
     * SOQL), so the dealer was shown only the first paragraph of the terms and
     * the PDF reproduced the same truncation. A SOQL read returns the whole field;
     * getInstance stays as the fallback if the record is somehow unreadable.
     */
    private static Cancellation_Settings__mdt loadSettings() {
        try {
            List<Cancellation_Settings__mdt> rows = [
                SELECT Terms_Version__c, Terms_Text__c
                FROM Cancellation_Settings__mdt
                WHERE DeveloperName = 'Default'
                LIMIT 1
            ];
            if (!rows.isEmpty()) {
                return rows[0];
            }
        } catch (Exception ignored) {
            // Fall through to the cached read.
        }
        return Cancellation_Settings__mdt.getInstance(SETTINGS_DEFAULT);
    }

    private static String dealerAddress(Account dealer, String fallbackFormula) {
        if (dealer != null) {
            List<String> parts = new List<String>();
            if (String.isNotBlank(dealer.BillingStreet)) parts.add(dealer.BillingStreet);
            if (String.isNotBlank(dealer.BillingCity)) parts.add(dealer.BillingCity);
            if (String.isNotBlank(dealer.BillingState)) parts.add(dealer.BillingState);
            if (String.isNotBlank(dealer.BillingPostalCode)) parts.add(dealer.BillingPostalCode);
            if (!parts.isEmpty()) {
                return String.join(parts, ', ');
            }
        }
        if (String.isBlank(fallbackFormula)) {
            return null;
        }
        return fallbackFormula.replace('<br>', ', ').replace('<br/>', ', ').replace('<br />', ', ');
    }

    private static String describeAddOns(List<AddOn> addOns) {
        if (addOns == null || addOns.isEmpty()) {
            return '-';
        }
        List<String> parts = new List<String>();
        for (AddOn a : addOns) {
            parts.add(String.isBlank(a.name) ? 'Option' : a.name);
        }
        return String.join(parts, ', ');
    }

    private static String buildLegacyReason(String reasonCode, String detail) {
        return String.isBlank(detail) ? reasonCode : reasonCode + '\n\nAdditional Details:\n' + detail.trim();
    }

    private static String trimAll(List<String> parts) {
        List<String> kept = new List<String>();
        for (String p : parts) {
            if (String.isNotBlank(p)) {
                kept.add(p.trim());
            }
        }
        return kept.isEmpty() ? null : String.join(kept, ' ');
    }

    private static String statusKey(String status) {
        if (status == 'Approved') return 'approved';
        if (status == 'Draft' || status == 'Pending Sales Review' || status == 'Pending Accounting Review') return 'pending';
        if (status == 'Rejected') return 'rejected';
        if (status == 'Cancelled') return 'cancelled';
        if (status == 'Withdrawn') return 'withdrawn';
        return 'other';
    }

    private static String statusLabel(String status) {
        if (status == 'Approved') return 'CANCELLATION SUCCESSFUL';
        if (status == 'Draft' || status == 'Pending Sales Review' || status == 'Pending Accounting Review') return 'PENDING CANCELLATION';
        if (status == 'Rejected') return 'CANCELLATION DECLINED';
        if (status == 'Withdrawn') return 'WITHDRAWN';
        if (status == 'Cancelled') return 'CANCELLED';
        return status;
    }

    /** Portal users cannot see ProcessInstance through sharing, so this probe runs in system mode. */
    private without sharing class ApprovalProbe {
        public Boolean hasPendingApproval(Id requestId) {
            return ![
                SELECT Id FROM ProcessInstance
                WHERE TargetObjectId = :requestId AND Status = 'Pending'
                LIMIT 1
            ].isEmpty();
        }
    }

    /**
     * Post-insert writes on the request that was created a moment ago.
     *
     * Runs without sharing by design. CancellationRequestHandler reassigns a new
     * request to the Sales review queue in its after-insert trigger, so the portal
     * user who created it loses record access at that instant. Publishing the
     * signature ContentVersion into the request (FirstPublishLocationId) and the
     * follow-up update that stores its id then fail with INSUFFICIENT_ACCESS for
     * the dealer, and because those calls sit after `insert request` the exception
     * used to roll the whole submit back - leaving no request, no service rows and
     * no signature. Every write here is id-addressed against a record this
     * transaction created and already validated as the dealer's own.
     */
    private without sharing class RequestWriter {
        public void insertServices(List<Cancellation_Service__c> services) {
            insert services;
        }

        public Id attachSignature(Id requestId, String applicationNumber, String base64Png) {
            String title = 'Cancellation Signature ' + applicationNumber + ' ' + String.valueOf(Date.today());
            Blob body = EncodingUtil.base64Decode(base64Png);
            Id contentVersionId = null;

            // Preferred: publish the file straight onto the request.
            try {
                ContentVersion published = new ContentVersion(
                    Title = title,
                    PathOnClient = 'cancellation-signature.png',
                    VersionData = body,
                    FirstPublishLocationId = requestId
                );
                Database.insert(published, AccessLevel.SYSTEM_MODE);
                contentVersionId = published.Id;
            } catch (Exception publishError) {
                // A portal user publishing into a queue-owned record is refused with
                // INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY [NetworkId]. The file
                // itself is still the record of the signature, so store it in the
                // dealer's library and link it where that is permitted.
                ContentVersion stored = new ContentVersion(
                    Title = title,
                    PathOnClient = 'cancellation-signature.png',
                    VersionData = body
                );
                Database.insert(stored, AccessLevel.SYSTEM_MODE);
                contentVersionId = stored.Id;
                try {
                    Id documentId = [
                        SELECT ContentDocumentId FROM ContentVersion WHERE Id = :stored.Id LIMIT 1
                    ].ContentDocumentId;
                    insert new ContentDocumentLink(
                        ContentDocumentId = documentId,
                        LinkedEntityId = requestId,
                        ShareType = 'V'
                    );
                } catch (Exception linkError) {
                    // Unlinked file is better than no signature at all; the id is
                    // still on the request and the file is retrievable from the library.
                }
            }

            update new App_Cancellation_Request__c(
                Id = requestId,
                Signature_Content_Version_Id__c = contentVersionId,
                Signature_Captured_On__c = Datetime.now()
            );
            return contentVersionId;
        }

        public void noteFailure(Id requestId, String note) {
            List<App_Cancellation_Request__c> rows = [
                SELECT Id, Sales_Notes__c FROM App_Cancellation_Request__c WHERE Id = :requestId LIMIT 1
            ];
            if (rows.isEmpty()) {
                return;
            }
            App_Cancellation_Request__c row = rows[0];
            String existing = String.isBlank(row.Sales_Notes__c) ? '' : row.Sales_Notes__c + '\n';
            row.Sales_Notes__c = (existing + note).left(32000);
            update row;
        }
    }
}