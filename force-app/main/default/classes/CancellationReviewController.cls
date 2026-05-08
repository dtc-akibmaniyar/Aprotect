public with sharing class CancellationReviewController {
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getRequestDetails(Id requestId) {
        App_Cancellation_Request__c req = [
            SELECT Id, Name, Status__c, Application__c, Application__r.Name, 
                   Application__r.Application_Status__c, Application__r.Dealer_Name__c,
                   Application__r.Dealer_Name__r.Name,
                   Total_Refund_Amount__c, Reason__c, Sales_Notes__c, Denial_Reason__c,
                   Requested_By_Name__c, Date_Requested__c,
                   CreatedDate, CreatedById, CreatedBy.Name, OwnerId, Owner.Name
            FROM App_Cancellation_Request__c 
            WHERE Id = :requestId 
            LIMIT 1
        ];
        
        List<Cancellation_Service__c> services = [
            SELECT Id, Name, Application_Package__c, Application_Package__r.Name,
                   Application_Package__r.Coverage_Plan__c, 
                   Application_Package__r.Coverage_Term__c,
                   Application_Package__r.Total_Package_Price__c,
                   Refund_Amount__c
            FROM Cancellation_Service__c 
            WHERE App_Cancellation_Request__c = :requestId
            ORDER BY Name
        ];
        
        Map<String, Object> result = new Map<String, Object>();
        result.put('request', req);
        result.put('services', services);
        return result;
    }
    
    @AuraEnabled
    public static void approveRequest(Id requestId, String approvalType) {
        App_Cancellation_Request__c req = [
            SELECT Id, Status__c FROM App_Cancellation_Request__c WHERE Id = :requestId LIMIT 1
        ];
        
        if (approvalType == 'accounting_review') {
            req.Status__c = 'Pending Accounting Review';
        } else if (approvalType == 'final') {
            req.Status__c = 'Approved';
        }
        
        update req;
    }
    
    @AuraEnabled
    public static void rejectRequest(Id requestId, String rejectionReason) {
        App_Cancellation_Request__c req = [
            SELECT Id, Status__c, Denial_Reason__c FROM App_Cancellation_Request__c WHERE Id = :requestId LIMIT 1
        ];
        
        req.Status__c = 'Rejected';
        String existing = req.Denial_Reason__c != null ? req.Denial_Reason__c : '';
        req.Denial_Reason__c = existing + (String.isNotBlank(existing) ? '\n' : '') + 
                       'Rejection Reason: ' + rejectionReason;
        
        update req;
    }
}