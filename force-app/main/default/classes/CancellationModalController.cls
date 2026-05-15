public without sharing class CancellationModalController {
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getApplicationDetails(Id applicationId) {
        Application__c app = [
            SELECT Id, Name, Application_Status__c, Cancellation_Status__c, Dealer_Name__c
            FROM Application__c 
            WHERE Id = :applicationId
            LIMIT 1
        ];
        
        List<Application_Package__c> packages = [
            SELECT Id, Name, Coverage_Plan__c, Coverage_Term__c, 
                   Total_Package_Price__c, Dealer_Package_Retail_Price__c,
                   Active__c, Package_Record_Type__c
            FROM Application_Package__c
            WHERE Application__c = :applicationId AND Active__c = true
            ORDER BY Name ASC
        ];
        
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
        Application__c app = [
            SELECT Id, Application_Status__c, Dealer_Name__c
            FROM Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        
        String requestStatus;
        String appStatus = app.Application_Status__c;
        if (appStatus == 'Draft' || appStatus == 'Quote') {
            requestStatus = 'Approved';
        } else {
            requestStatus = 'Pending Sales Review';
        }
        
        // Determine if application is in a pending/unpaid status
        Boolean isUnpaid = appStatus == 'Draft' || appStatus == 'Quote' || (appStatus != null && appStatus.containsIgnoreCase('Pending'));
        
        List<Application_Package__c> selectedPackages = [
            SELECT Id, Total_Package_Price__c
            FROM Application_Package__c
            WHERE Id IN :serviceIds
        ];
        
        Decimal totalRefund = 0;
        if (!isUnpaid) {
            for (Application_Package__c pkg : selectedPackages) {
                if (pkg.Total_Package_Price__c != null) {
                    totalRefund += pkg.Total_Package_Price__c;
                }
            }
        }
        
        App_Cancellation_Request__c request = new App_Cancellation_Request__c();
        request.Application__c = applicationId;
        request.Status__c = requestStatus;
        request.Reason__c = reason + (String.isNotBlank(details) ? '\n\nAdditional Details:\n' + details : '');
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
            cs.Refund_Amount__c = isUnpaid ? 0 : (pkg.Total_Package_Price__c != null ? pkg.Total_Package_Price__c : 0);
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
}