public with sharing class ApplicationsListViewController {

    // Response wrapper for LWC
    public class ApplicationsResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public List<ApplicationRow> data;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public Integer pageNumber;
        @AuraEnabled public Integer pageSize;
        @AuraEnabled public Integer totalPages;
        public ApplicationsResponse() {}
    }

    // Row DTO returned to the LWC
    public class ApplicationRow {
        @AuraEnabled public String id;
        @AuraEnabled public String appNumber;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String vehicleName;
        @AuraEnabled public List<ServiceInfo> services;
        @AuraEnabled public String customerName;
        @AuraEnabled public String billingStreet;
        @AuraEnabled public String billingCity;
        @AuraEnabled public String billingState;
        @AuraEnabled public String billingPostalCode;
        @AuraEnabled public Decimal odometer;
        @AuraEnabled public String oddometerUnit;
        @AuraEnabled public String vehicleVin;
        @AuraEnabled public Decimal purchasePrice;
        @AuraEnabled public String paymentStatus;
        @AuraEnabled public String applicationStatus;
        @AuraEnabled public String cancellationStatus;
        @AuraEnabled public String invoiceId;
        public ApplicationRow() {}
    }

    /**
     * Fetch list data for Applications List View with server-side pagination and search.
     */
    @AuraEnabled
    public static ApplicationsResponse getApplicationsList(Integer pageNumber, Integer pageSize, String searchTerm, String statusFilter, String fromDate, String toDate) {
        ApplicationsResponse resp = new ApplicationsResponse();
        resp.success = false;
        resp.message = '';

        try {
            if (pageNumber == null || pageNumber < 1) pageNumber = 1;
            if (pageSize == null || pageSize < 1) pageSize = 10;
            if (pageSize > 25000) pageSize = 25000;

            searchTerm = String.isBlank(searchTerm) ? null : searchTerm.trim();
            if (String.isBlank(statusFilter)) statusFilter = 'Draft';

            Date fromDateParsed = String.isNotBlank(fromDate) ? Date.valueOf(fromDate) : null;
            Date toDateParsed   = String.isNotBlank(toDate)   ? Date.valueOf(toDate)   : null;

            Integer totalCount = getApplicationsCount(searchTerm, statusFilter, fromDateParsed, toDateParsed);

            Integer offset = (pageNumber - 1) * pageSize;
            Integer totalPages = (totalCount > 0) ? Integer.valueOf(Math.ceil((Decimal)totalCount / (Decimal)pageSize)) : 1;

            if (pageNumber > totalPages) pageNumber = totalPages;
            offset = (pageNumber - 1) * pageSize;

            List<Application__c> apps = fetchApplications(pageSize, offset, searchTerm, statusFilter, fromDateParsed, toDateParsed);
            
            if (apps.isEmpty()) {
                resp.success = true;
                resp.data = new List<ApplicationRow>();
                resp.totalCount = totalCount;
                resp.pageNumber = pageNumber;
                resp.pageSize = pageSize;
                resp.totalPages = totalPages;
                return resp;
            }
            
            Map<Id, List<ServiceInfo>> appIdToServiceInfo = buildServiceLabelsByApplication(apps, statusFilter);
            Map<Id, String> appIdToLatestInvoiceId = getLatestInvoiceForApplications(apps);
            List<ApplicationRow> rows = buildRows(apps, appIdToServiceInfo, appIdToLatestInvoiceId);
            
            resp.success = true;
            resp.data = rows;
            resp.totalCount = totalCount;
            resp.pageNumber = pageNumber;
            resp.pageSize = pageSize;
            resp.totalPages = totalPages;
        } catch (Exception e) {
            resp.message = 'Error fetching applications: ' + e.getMessage();
        }
        return resp;
    }

    /**
     * For the Cancelled filter, pre-query Application IDs that have at least one cancelled package.
     * SOQL does not allow semi-join subselects inside OR groups, so we must pre-resolve the IDs.
     */
    private static Set<Id> getCancelledPackageAppIds() {
        Set<Id> appIds = new Set<Id>();
        for (Application_Package__c pkg : [
            SELECT Application__c FROM Application_Package__c 
            WHERE Application_Status__c = 'Cancelled' AND Application__c != null
        ]) {
            appIds.add(pkg.Application__c);
        }
        return appIds;
    }

    private static String buildWhereClause(String searchTerm, String statusFilter) {
        List<String> conditions = new List<String>();

        if (String.isBlank(statusFilter)) statusFilter = 'Draft';

        if (statusFilter == 'All') {
            conditions.add('Application_Status__c != \'Deleted\'');
            conditions.add('Application_Status__c != \'Quote\'');
        } else if (statusFilter == 'Submitted') {
            conditions.add('Application_Status__c IN (\'Submitted\', \'Active\')');
        } else if (statusFilter == 'Pending Cancellation') {
            conditions.add('Cancellation_Status__c IN (\'Pending Sales Review\', \'Pending Accounting Review\')');
        } else if (statusFilter == 'Cancelled') {
            // Uses bind variable :cancelledAppIds — caller must supply it in query scope
            conditions.add('(Application_Status__c = \'Cancelled\' OR Id IN :cancelledAppIds)');
        } else {
            // Default: Pending/Draft
            conditions.add('Application_Status__c != \'Submitted\'');
            conditions.add('Application_Status__c != \'Active\'');
            conditions.add('Application_Status__c != \'Deleted\'');
            conditions.add('Application_Status__c != \'Cancelled\'');
            conditions.add('Application_Status__c != \'Quote\'');
        }

        conditions.add('Vehicle__c != null');

        if (String.isNotBlank(searchTerm)) {
            String safe = String.escapeSingleQuotes(searchTerm.trim());
            conditions.add('(Customer_Name__r.Name LIKE \'%' + safe + '%\' OR Name LIKE \'%' + safe + '%\' OR Vehicle_VIN__c LIKE \'%' + safe + '%\')');
        }

        return String.join(conditions, ' AND ');
    }

    private static Integer getApplicationsCount(String searchTerm, String statusFilter, Date fromDate, Date toDate) {
        Datetime fromDt = fromDate != null ? DateTime.newInstance(fromDate, Time.newInstance(0, 0, 0, 0)) : null;
        Datetime toDt   = toDate   != null ? DateTime.newInstance(toDate.addDays(1), Time.newInstance(0, 0, 0, 0)) : null;

        // Pre-resolve cancelled package app IDs for bind variable
        Set<Id> cancelledAppIds = (statusFilter == 'Cancelled') ? getCancelledPackageAppIds() : new Set<Id>();

        String whereClause = buildWhereClause(searchTerm, statusFilter);
        if (fromDt != null) whereClause += ' AND CreatedDate >= :fromDt';
        if (toDt   != null) whereClause += ' AND CreatedDate < :toDt';

        return Database.countQuery('SELECT COUNT() FROM Application__c WHERE ' + whereClause);
    }

    private static List<Application__c> fetchApplications(Integer pageSize, Integer offset, String searchTerm, String statusFilter, Date fromDate, Date toDate) {
        Datetime fromDt = fromDate != null ? DateTime.newInstance(fromDate, Time.newInstance(0, 0, 0, 0)) : null;
        Datetime toDt   = toDate   != null ? DateTime.newInstance(toDate.addDays(1), Time.newInstance(0, 0, 0, 0)) : null;

        // Pre-resolve cancelled package app IDs for bind variable
        Set<Id> cancelledAppIds = (statusFilter == 'Cancelled') ? getCancelledPackageAppIds() : new Set<Id>();

        String whereClause = buildWhereClause(searchTerm, statusFilter);
        if (fromDt != null) whereClause += ' AND CreatedDate >= :fromDt';
        if (toDt   != null) whereClause += ' AND CreatedDate < :toDt';

        String fields = 'Id, Name, CreatedDate, Vehicle__c, Vehicle__r.Name, Vehicle_VIN__c, Odometer__c, Application_Status__c, Cancellation_Status__c, Payment_Status__c, Odometer_Unit__c, Vehicle_Purchase_Price__c, Customer_Name__c, Customer_Name__r.Name, Customer_Name__r.BillingStreet, Customer_Name__r.BillingCity, Customer_Name__r.BillingState, Customer_Name__r.BillingPostalCode';
        String query = 'SELECT ' + fields + ' FROM Application__c WHERE ' + whereClause + ' ORDER BY CreatedDate DESC LIMIT ' + pageSize + ' OFFSET ' + offset;
        System.debug('Fetching applications: ' + query);
        List<Application__c> apps = Database.query(query);
        System.debug('Fetched :: ' + apps.size() + ' applications');
        return apps;
    }

    // Wrapper class for service information with prices
    public class ServiceInfo {
        @AuraEnabled public String label;
        @AuraEnabled public Decimal costPriceWithTax;
        @AuraEnabled public Decimal costPriceWithoutTax;
        
        public ServiceInfo(String label, Decimal costPriceWithTax, Decimal costPriceWithoutTax) {
            this.label = label;
            this.costPriceWithTax = costPriceWithTax;
            this.costPriceWithoutTax = costPriceWithoutTax;
        }
    }

    private static Map<Id, String> getLatestInvoiceForApplications(List<Application__c> apps) {
        Set<Id> appIds = new Set<Id>();
        for (Application__c a : apps) {
            appIds.add(a.Id);
        }
        if (appIds.isEmpty()) {
            return new Map<Id, String>();
        }
        
        List<Invoice__c> invoices = [
            SELECT Id, Application__c
            FROM Invoice__c
            WHERE Application__c IN :appIds
            ORDER BY CreatedDate DESC
        ];
        
        Map<Id, String> appIdToLatestInvoiceId = new Map<Id, String>();
        for (Invoice__c inv : invoices) {
            if (!appIdToLatestInvoiceId.containsKey(inv.Application__c)) {
                appIdToLatestInvoiceId.put(inv.Application__c, inv.Id);
            }
        }
        return appIdToLatestInvoiceId;
    }

    private static Map<Id, List<ServiceInfo>> buildServiceLabelsByApplication(List<Application__c> apps, String statusFilter) {
        Set<Id> appIds = new Set<Id>();
        for (Application__c a : apps) {
            appIds.add(a.Id);
        }
        if (appIds.isEmpty()) {
            return new Map<Id, List<ServiceInfo>>();
        }
        
        List<Application_Package__c> packages;
        if (statusFilter == 'Cancelled') {
            packages = [
                SELECT Id, Application__c, RecordType.DeveloperName, RecordType.Name, Contract_Cost_Price__c, Contract_Cost_Price_Without_Tax__c
                FROM Application_Package__c
                WHERE Application_Status__c = 'Cancelled' AND Application__c IN :appIds
                ORDER BY RecordType.Name ASC
            ];
        } else {
            packages = [
                SELECT Id, Application__c, RecordType.DeveloperName, RecordType.Name, Contract_Cost_Price__c, Contract_Cost_Price_Without_Tax__c
                FROM Application_Package__c
                WHERE Active__c = true AND Application__c IN :appIds
                ORDER BY RecordType.Name ASC
            ];
        }
        
        Map<Id, List<ServiceInfo>> appIdToServices = new Map<Id, List<ServiceInfo>>();
        for (Application_Package__c pkg : packages) {
            if (pkg.Application__c == null) continue;
            List<ServiceInfo> services = appIdToServices.get(pkg.Application__c);
            if (services == null) {
                services = new List<ServiceInfo>();
                appIdToServices.put(pkg.Application__c, services);
            }
            String label = pkg.RecordType != null ? pkg.RecordType.Name : null;
            if (String.isNotBlank(label)) {
                services.add(new ServiceInfo(label, pkg.Contract_Cost_Price__c, pkg.Contract_Cost_Price_Without_Tax__c));
            }
        }
        return appIdToServices;
    }

    // Map record type developer/name to UI chip label
    private static String mapRecordTypeToLabel(String developerName, String nameVal) {
        if (developerName == 'Extended_Limited_Warranty' || nameVal == 'Extended Limited Warranty') {
            return 'Extended Warranty';
        }
        if (developerName == 'Loan_Protection' || nameVal == 'Loan Protection') {
            return 'Loan Protection';
        }
        if (developerName == 'GAP_Coverage' || nameVal == 'GAP Coverage') {
            return 'GAP Coverage';
        }
        if (developerName == 'Tire_Rim_Protection_Plan' || nameVal == 'Tire & Rim Protection Plan') {
            return 'Tire & Rim Protection';
        }
        return null;
    }

    /**
     * Create a new Application record with 'Application' record type
     */
    @AuraEnabled
    public static CreateApplicationResponse createNewApplication() {
        try {
            Application__c newApp = new Application__c();
            newApp.RecordTypeId = Schema.SObjectType.Application__c.getRecordTypeInfosByDeveloperName().get('Application').getRecordTypeId();
            
            insert newApp;
            
            CreateApplicationResponse response = new CreateApplicationResponse();
            response.success = true;
            response.message = 'Application created successfully';
            response.recordId = newApp.Id;
            return response;
        } catch (Exception e) {
            CreateApplicationResponse response = new CreateApplicationResponse();
            response.success = false;
            response.message = 'Error creating application: ' + e.getMessage();
            response.recordId = null;
            return response;
        }
    }

    // Response wrapper for application creation
    public class CreateApplicationResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public String recordId;
        public CreateApplicationResponse() {}
    }

    // Build DTO rows from apps and labels
    private static List<ApplicationRow> buildRows(List<Application__c> apps, Map<Id, List<ServiceInfo>> appIdToServiceInfo, Map<Id, String> appIdToLatestInvoiceId) {
        List<ApplicationRow> rows = new List<ApplicationRow>();
        for (Application__c a : apps) {
            ApplicationRow row = new ApplicationRow();
            row.id = a.Id;
            row.appNumber = a.Name;
            row.createdDate = a.CreatedDate;
            row.vehicleName = (a.Vehicle__r != null ? a.Vehicle__r.Name : null);
            row.odometer = a.Odometer__c;
            row.oddometerUnit = a.Odometer_Unit__c;
            row.vehicleVin = a.Vehicle_VIN__c;
            row.purchasePrice = a.Vehicle_Purchase_Price__c;
            row.paymentStatus = a.Payment_Status__c;
            row.applicationStatus = a.Application_Status__c;
            row.cancellationStatus = a.Cancellation_Status__c;
            row.invoiceId = appIdToLatestInvoiceId != null && appIdToLatestInvoiceId.containsKey(a.Id) ? appIdToLatestInvoiceId.get(a.Id) : null;
            row.services = new List<ServiceInfo>();
            if (appIdToServiceInfo != null && appIdToServiceInfo.containsKey(a.Id)) {
                row.services.addAll(appIdToServiceInfo.get(a.Id));
            }
            if (a.Customer_Name__r != null) {
                row.customerName = a.Customer_Name__r.Name;
                row.billingStreet = a.Customer_Name__r.BillingStreet;
                row.billingCity = a.Customer_Name__r.BillingCity;
                row.billingState = a.Customer_Name__r.BillingState;
                row.billingPostalCode = a.Customer_Name__r.BillingPostalCode;
            }
            rows.add(row);
        }
        return rows;
    }
}