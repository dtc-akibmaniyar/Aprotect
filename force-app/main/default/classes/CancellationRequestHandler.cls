public class CancellationRequestHandler {

    // Queue IDs - cached to avoid repeated queries
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
        List<App_Cancellation_Request__c> toAssign = new List<App_Cancellation_Request__c>();
        Map<Id, String> appStatusMap = new Map<Id, String>();

        for (App_Cancellation_Request__c req : newList) {
            if (req.Status__c == 'Pending Sales Review') {
                if (salesQueueId != null) {
                    toAssign.add(new App_Cancellation_Request__c(Id = req.Id, OwnerId = salesQueueId));
                }
                if (req.Application__c != null) {
                    appStatusMap.put(req.Application__c, 'Pending Sales Review');
                }
            }
        }

        if (!toAssign.isEmpty()) {
            update toAssign;
        }
        if (!appStatusMap.isEmpty()) {
            syncApplicationStatus(appStatusMap, true);
        }
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

            // Pending Sales Review -> Pending Accounting Review
            if (oldStatus == 'Pending Sales Review' && newStatus == 'Pending Accounting Review') {
                if (accountingQueueId != null) {
                    toReassign.add(new App_Cancellation_Request__c(Id = req.Id, OwnerId = accountingQueueId));
                }
                if (req.Application__c != null) {
                    appStatusMap.put(req.Application__c, 'Pending Accounting Review');
                }
            }
            // Pending Sales Review -> Approved (non-paid, direct approval)
            else if (oldStatus == 'Pending Sales Review' && newStatus == 'Approved') {
                if (req.Application__c != null) {
                    appStatusMap.put(req.Application__c, 'Cancelled');
                }
            }
            // Pending Accounting Review -> Approved (with refund)
            else if (oldStatus == 'Pending Accounting Review' && newStatus == 'Approved') {
                approvedWithRefund.add(req);
                if (req.Application__c != null) {
                    appStatusMap.put(req.Application__c, 'Cancelled');
                }
            }
            // Any -> Rejected
            else if (newStatus == 'Rejected') {
                if (req.Application__c != null) {
                    appStatusMap.put(req.Application__c, 'Rejected');
                }
            }
            // Any -> Withdrawn
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

        // Query applications to get Dealer
        Map<Id, Application__c> appMap = new Map<Id, Application__c>(
            [SELECT Id, Dealer_Name__c FROM Application__c WHERE Id IN :applicationIds]
        );

        // Sum refund amounts from cancellation services
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