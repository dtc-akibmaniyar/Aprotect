public without sharing class CancellationModalController {
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getApplicationDetails(Id applicationId) {
        // Query Application
        Application__c app = [
            SELECT Id, Name, Application_Status__c, Cancellation_Status__c, Dealer_Name__c
            FROM Application__c 
            WHERE Id = :applicationId
            LIMIT 1
        ];
        
        // Query related Application Packages (services)
        List<Application_Package__c> packages = [
            SELECT Id, Name, Coverage_Plan__c, Coverage_Term__c, 
                   Total_Package_Price__c, Dealer_Package_Retail_Price__c,
                   Active__c, Package_Record_Type__c
            FROM Application_Package__c
            WHERE Application__c = :applicationId
            ORDER BY Name ASC
        ];
        
        // Build services list
        List<Map<String, Object>> services = new List<Map<String, Object>>();
        for (Application_Package__c pkg : packages) {
            Map<String, Object> svc = new Map<String, Object>();
            svc.put('id', pkg.Id);
            svc.put('name', pkg.Name);
            svc.put('coveragePlan', pkg.Coverage_Plan__c);
            svc.put('coverageTerm', pkg.Coverage_Term__c);
            svc.put('price', pkg.Total_Package_Price__c != null ? pkg.Total_Package_Price__c : 0);
            svc.put('retailPrice', pkg.Dealer_Package_Retail_Price__c != null ? pkg.Dealer_Package_Retail_Price__c : 0);
            svc.put('active', pkg.Active__c);
            svc.put('packageType', pkg.Package_Record_Type__c);
            services.add(svc);
        }
        
        // Build application map
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
    
    @AuraEnabled
    public static Id submitCancellationRequest(Id applicationId, List<Id> serviceIds, String reason, String details) {
        // Get application to determine status-based routing
        Application__c app = [
            SELECT Id, Application_Status__c, Dealer_Name__c
            FROM Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        
        // Determine request status based on Application status
        String requestStatus;
        String appStatus = app.Application_Status__c;
        if (appStatus == 'Draft' || appStatus == 'Quote') {
            requestStatus = 'Approved';
        } else {
            requestStatus = 'Pending Sales Review';
        }
        
        // Calculate total refund from selected packages
        List<Application_Package__c> selectedPackages = [
            SELECT Id, Total_Package_Price__c
            FROM Application_Package__c
            WHERE Id IN :serviceIds
        ];
        
        Decimal totalRefund = 0;
        for (Application_Package__c pkg : selectedPackages) {
            if (pkg.Total_Package_Price__c != null) {
                totalRefund += pkg.Total_Package_Price__c;
            }
        }
        
        // Create cancellation request
        App_Cancellation_Request__c request = new App_Cancellation_Request__c();
        request.Application__c = applicationId;
        request.Status__c = requestStatus;
        request.Reason__c = reason + (String.isNotBlank(details) ? '\n\nAdditional Details:\n' + details : '');
        request.Total_Refund_Amount__c = totalRefund;
        request.Date_Requested__c = Datetime.now();
        request.Requested_By__c = UserInfo.getUserId();
        request.Requested_By_Name__c = UserInfo.getName();
        request.Refund_Eligible__c = totalRefund > 0;
        request.Payment_Status_At_Request__c = appStatus;
        insert request;
        
        // Create Cancellation_Service__c for each selected package
        List<Cancellation_Service__c> cancServices = new List<Cancellation_Service__c>();
        for (Application_Package__c pkg : selectedPackages) {
            Cancellation_Service__c cs = new Cancellation_Service__c();
            cs.App_Cancellation_Request__c = request.Id;
            cs.Application_Package__c = pkg.Id;
            cs.Refund_Amount__c = pkg.Total_Package_Price__c != null ? pkg.Total_Package_Price__c : 0;
            cancServices.add(cs);
        }
        if (!cancServices.isEmpty()) {
            insert cancServices;
        }
        
        return request.Id;
    }
}