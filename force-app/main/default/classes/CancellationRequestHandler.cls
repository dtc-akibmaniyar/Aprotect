public class CancellationRequestHandler {

    private static Id salesQueueId;
    private static Id accountingQueueId;

    static {
        List<Group> queues = [SELECT Id, DeveloperName FROM Group 
                              WHERE Type = 'Queue' 
                              AND DeveloperName IN ('Sales_Review_Queue', 'Accounting_Review_Queue')];
        for (Group q : queues) {
            if (q.DeveloperName == 'Sales_Review_Queue') salesQueueId = q.Id;
            if (q.DeveloperName == 'Accounting_Review_Queue') accountingQueueId = q.Id;
        }
    }

    public static void handle(List<App_Cancellation_Request__c> newList, Map<Id, App_Cancellation_Request__c> oldMap, Boolean isInsert, Boolean isUpdate) {
        if (isInsert) {
            handleAfterInsert(newList);
        }
        if (isUpdate) {
            handleAfterUpdate(newList, oldMap);
        }
    }

    private static void handleAfterInsert(List<App_Cancellation_Request__c> newList) {
        List<App_Cancellation_Request__c> toUpdate = new List<App_Cancellation_Request__c>();
        Map<Id, String> appStatusMap = new Map<Id, String>();

        Integer slaDays = 5;
        Cancellation_Settings__mdt settings = Cancellation_Settings__mdt.getInstance('Default');
        if (settings != null && settings.SLA_Business_Days__c != null) {
            slaDays = (Integer) settings.SLA_Business_Days__c;
        }

        List<Id> recordsToSubmit = new List<Id>();

        for (App_Cancellation_Request__c req : newList) {
            App_Cancellation_Request__c upd = new App_Cancellation_Request__c(Id = req.Id);
            Boolean needsUpdate = false;

            upd.SLA_Due_Date__c = addBusinessDays(Date.today(), slaDays);
            needsUpdate = true;

            if (req.Status__c == 'Pending Sales Review') {
                if (salesQueueId != null) {
                    upd.OwnerId = salesQueueId;
                }
                if (req.Application__c != null) {
                    appStatusMap.put(req.Application__c, 'Pending Sales Review');
                }
                recordsToSubmit.add(req.Id);
            }

            if (needsUpdate) {
                toUpdate.add(upd);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
        if (!appStatusMap.isEmpty()) {
            syncApplicationStatus(appStatusMap, true);
        }
        if (!recordsToSubmit.isEmpty()) {
            submitForApproval(recordsToSubmit);
        }
    }

    private static void submitForApproval(List<Id> recordIds) {
        // Get an admin user to act as submitter (portal users can't submit approvals)
        Id adminUserId;
        List<User> admins = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' AND IsActive = true LIMIT 1];
        if (!admins.isEmpty()) {
            adminUserId = admins[0].Id;
        }

        List<Approval.ProcessSubmitRequest> requests = new List<Approval.ProcessSubmitRequest>();
        for (Id recId : recordIds) {
            Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
            req.setObjectId(recId);
            req.setProcessDefinitionNameOrId('Cancellation_Approval_Process');
            req.setSkipEntryCriteria(true);
            if (adminUserId != null) {
                req.setSubmitterId(adminUserId);
            }
            requests.add(req);
        }
        if (!requests.isEmpty()) {
            try {
                List<Approval.ProcessResult> results = Approval.process(requests);
                for (Approval.ProcessResult result : results) {
                    if (!result.isSuccess()) {
                        System.debug(LoggingLevel.ERROR, 'Approval submission failed: ' + result.getErrors());
                    }
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Approval submission error: ' + e.getMessage());
            }
        }
    }

    public static Date addBusinessDays(Date startDate, Integer businessDays) {
        Date result = startDate;
        Integer added = 0;
        while (added < businessDays) {
            result = result.addDays(1);
            Datetime dt = Datetime.newInstance(result, Time.newInstance(0, 0, 0, 0));
            String dayName = dt.format('EEEE');
            if (dayName != 'Saturday' && dayName != 'Sunday') {
                added++;
            }
        }
        return result;
    }

    private static void handleAfterUpdate(List<App_Cancellation_Request__c> newList, Map<Id, App_Cancellation_Request__c> oldMap) {
        List<App_Cancellation_Request__c> toReassign = new List<App_Cancellation_Request__c>();
        Map<Id, String> appStatusMap = new Map<Id, String>();
        Set<Id> appsToClear = new Set<Id>();
        List<App_Cancellation_Request__c> approvedWithRefund = new List<App_Cancellation_Request__c>();

        for (App_Cancellation_Request__c req : newList) {
            App_Cancellation_Request__c oldReq = oldMap.get(req.Id);
            String newStatus = req.Status__c;
            String oldStatus = oldReq.Status__c;

            if (newStatus == oldStatus) continue;

            if (oldStatus == 'Pending Sales Review' && newStatus == 'Pending Accounting Review') {
                if (accountingQueueId != null) {
                    toReassign.add(new App_Cancellation_Request__c(Id = req.Id, OwnerId = accountingQueueId));
                }
                if (req.Application__c != null) {
                    appStatusMap.put(req.Application__c, 'Pending Accounting Review');
                }
            }
            else if (oldStatus == 'Pending Sales Review' && newStatus == 'Approved') {
                if (req.Application__c != null) {
                    appStatusMap.put(req.Application__c, 'Cancelled');
                }
            }
            else if (oldStatus == 'Pending Accounting Review' && newStatus == 'Approved') {
                approvedWithRefund.add(req);
                if (req.Application__c != null) {
                    appStatusMap.put(req.Application__c, 'Cancelled');
                }
            }
            else if (newStatus == 'Rejected') {
                if (req.Application__c != null) {
                    appStatusMap.put(req.Application__c, 'Rejected');
                }
            }
            else if (newStatus == 'Withdrawn') {
                if (req.Application__c != null) {
                    appsToClear.add(req.Application__c);
                }
            }
        }

        if (!toReassign.isEmpty()) {
            update toReassign;
        }
        if (!appStatusMap.isEmpty()) {
            syncApplicationStatus(appStatusMap, false);
        }
        if (!appsToClear.isEmpty()) {
            clearApplicationCancellation(appsToClear);
        }
        if (!approvedWithRefund.isEmpty()) {
            createRefundCredits(approvedWithRefund);
        }
    }

    private static void syncApplicationStatus(Map<Id, String> appIdToStatus, Boolean setDate) {
        List<Application__c> appsToUpdate = new List<Application__c>();
        for (Id appId : appIdToStatus.keySet()) {
            Application__c app = new Application__c(Id = appId);
            app.Cancellation_Status__c = appIdToStatus.get(appId);
            if (setDate) {
                app.Cancellation_Request_Date__c = Datetime.now();
            }
            appsToUpdate.add(app);
        }
        if (!appsToUpdate.isEmpty()) {
            update appsToUpdate;
        }
    }

    private static void clearApplicationCancellation(Set<Id> appIds) {
        List<Application__c> appsToUpdate = new List<Application__c>();
        for (Id appId : appIds) {
            Application__c app = new Application__c(Id = appId);
            app.Cancellation_Status__c = null;
            app.Cancellation_Request_Date__c = null;
            appsToUpdate.add(app);
        }
        if (!appsToUpdate.isEmpty()) {
            update appsToUpdate;
        }
    }

    private static void createRefundCredits(List<App_Cancellation_Request__c> approvedRequests) {
        Set<Id> requestIds = new Set<Id>();
        Set<Id> applicationIds = new Set<Id>();
        for (App_Cancellation_Request__c req : approvedRequests) {
            requestIds.add(req.Id);
            if (req.Application__c != null) applicationIds.add(req.Application__c);
        }

        Map<Id, Application__c> appMap = new Map<Id, Application__c>(
            [SELECT Id, Dealer_Name__c FROM Application__c WHERE Id IN :applicationIds]
        );

        Map<Id, Decimal> requestRefundMap = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT App_Cancellation_Request__c reqId, SUM(Refund_Amount__c) totalRefund
            FROM Cancellation_Service__c
            WHERE App_Cancellation_Request__c IN :requestIds
            GROUP BY App_Cancellation_Request__c
        ]) {
            requestRefundMap.put((Id) ar.get('reqId'), (Decimal) ar.get('totalRefund'));
        }

        List<Credit__c> creditsToInsert = new List<Credit__c>();
        List<App_Cancellation_Request__c> requestsToUpdate = new List<App_Cancellation_Request__c>();

        for (App_Cancellation_Request__c req : approvedRequests) {
            Decimal refundAmount = requestRefundMap.containsKey(req.Id) ? requestRefundMap.get(req.Id) : 0;
            if (refundAmount == null || refundAmount <= 0) continue;

            Application__c app = req.Application__c != null ? appMap.get(req.Application__c) : null;
            if (app == null || app.Dealer_Name__c == null) continue;

            Credit__c credit = new Credit__c();
            credit.Amount__c = refundAmount;
            credit.Credit_Type__c = 'Cancellation Credit';
            credit.Dealer__c = app.Dealer_Name__c;
            credit.Application__c = req.Application__c;
            credit.Cancellation_Request__c = req.Id;
            credit.Notes__c = 'Auto-generated cancellation refund credit';
            creditsToInsert.add(credit);

            requestsToUpdate.add(new App_Cancellation_Request__c(
                Id = req.Id,
                Total_Refund_Amount__c = refundAmount
            ));
        }

        if (!creditsToInsert.isEmpty()) {
            insert creditsToInsert;
        }
        if (!requestsToUpdate.isEmpty()) {
            update requestsToUpdate;
        }
    }
}