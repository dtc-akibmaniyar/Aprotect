public with sharing class QuotesListViewController {

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
        @AuraEnabled public String quoteName;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String vehicleName;
        @AuraEnabled public List<String> services;
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
        @AuraEnabled public Boolean hasFiles;
        public ApplicationRow() {}
    }

    /**
     * Fetch list data for Quotes List View with server-side pagination and search.
     * Fetches only applications where Application_Status__c = 'Quote'.
     * - Base object: Application__c
     * - Vehicle: show Vehicle__r.Name
     * - Services: include static labels if related Application_Package__c records exist with:
     *     RecordType.Name = 'Extended Limited Warranty'  -> 'Extended Warranty'
     *     OR RecordType.DeveloperName = 'Total_Loss_Coverage' -> 'Loan Protection'
     * @param pageNumber Page number (1-based)
     * @param pageSize Number of records per page (10, 20, 50, or up to 25000 for initial load)
     * @param searchTerm Optional search term to filter by customer name, app number, or vehicle VIN
     */
    @AuraEnabled
    public static ApplicationsResponse getQuotesList(Integer pageNumber, Integer pageSize, String searchTerm) {
        ApplicationsResponse resp = new ApplicationsResponse();
        resp.success = false;
        resp.message = '';
        
        try {
            // Validate inputs
            if (pageNumber == null || pageNumber < 1) pageNumber = 1;
            if (pageSize == null || pageSize < 1) pageSize = 10;
            // Cap pageSize to 25000 (allows initial bulk fetch)
            if (pageSize > 25000) pageSize = 25000;
            
            // Normalize search term
            searchTerm = String.isBlank(searchTerm) ? null : searchTerm.trim();
            
            // Get total count with search filter if applicable
            Integer totalCount = fetchQuotesCount(searchTerm);
            
            // Calculate offset and pages
            Integer offset = (pageNumber - 1) * pageSize;
            Integer totalPages = (totalCount > 0) ? Integer.valueOf(Math.ceil((Decimal)totalCount / (Decimal)pageSize)) : 1;
            
            // Validate page number
            if (pageNumber > totalPages) pageNumber = totalPages;
            offset = (pageNumber - 1) * pageSize;
            
            // Fetch applications with LIMIT and OFFSET
            List<Application__c> apps = fetchQuotes(pageSize, offset, searchTerm);
            
            if (apps.isEmpty()) {
                resp.success = true;
                resp.data = new List<ApplicationRow>();
                resp.totalCount = totalCount;
                resp.pageNumber = pageNumber;
                resp.pageSize = pageSize;
                resp.totalPages = totalPages;
                return resp;
            }
            
            Map<Id, Set<String>> appIdToServiceLabels = buildServiceLabelsByApplication(apps);

            // Bulk check for related files (ContentDocumentLink)
            Set<Id> appIds = new Set<Id>();
            for (Application__c a : apps) {
                appIds.add(a.Id);
            }
            Map<Id, Boolean> hasFilesMap = new Map<Id, Boolean>();
            for (AggregateResult ar : [
                SELECT LinkedEntityId, COUNT(Id) cnt
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :appIds
                GROUP BY LinkedEntityId
            ]) {
                hasFilesMap.put((Id)ar.get('LinkedEntityId'), true);
            }

            List<ApplicationRow> rows = buildRows(apps, appIdToServiceLabels, hasFilesMap);
            
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

    // Get count of quotes (Application_Status__c = 'Quote'), optionally filtered by search term
    private static Integer fetchQuotesCount(String searchTerm) {
        if (searchTerm == null) {
            return [SELECT COUNT() FROM Application__c WHERE Application_Status__c = 'Quote' AND Application_Status__c != 'Deleted'];
        }
        String likePattern = '%' + searchTerm + '%';
        return [SELECT COUNT() FROM Application__c 
                WHERE Application_Status__c = 'Quote' AND Application_Status__c != 'Deleted'
                AND (Customer_Name__r.Name LIKE :likePattern
                   OR Customer_Name__r.Phone LIKE :likePattern
                   OR Name LIKE :likePattern
                   OR QuoteName__c LIKE :likePattern
                   OR Vehicle_VIN__c LIKE :likePattern)];
    }

    // Fetch quotes (Application_Status__c = 'Quote') with vehicle and customer account details
    private static List<Application__c> fetchQuotes(Integer pageSize, Integer offset, String searchTerm) {
        List<Application__c> apps;
        if (searchTerm == null) {
            apps = [
                SELECT Id, Name, CreatedDate, Vehicle__c, Vehicle__r.Name,Vehicle_VIN__c,Odometer__c,Payment_Status__c, Odometer_Unit__c,Vehicle_Purchase_Price__c,
                       Customer_Name__c, Customer_Name__r.Name,
                       Customer_Name__r.BillingStreet, Customer_Name__r.BillingCity,
                       Customer_Name__r.BillingState, Customer_Name__r.BillingPostalCode, QuoteName__c
                FROM Application__c
                WHERE Application_Status__c = 'Quote' AND Application_Status__c != 'Deleted'
                ORDER BY CreatedDate DESC
                LIMIT :pageSize
                OFFSET :offset
            ];
        } else {
            String likePattern = '%' + searchTerm + '%';
            apps = [
                SELECT Id, Name, CreatedDate, Vehicle__c, Vehicle__r.Name,Vehicle_VIN__c,Odometer__c,Payment_Status__c, Odometer_Unit__c,Vehicle_Purchase_Price__c,
                       Customer_Name__c, Customer_Name__r.Name,
                       Customer_Name__r.BillingStreet, Customer_Name__r.BillingCity,
                       Customer_Name__r.BillingState, Customer_Name__r.BillingPostalCode, QuoteName__c
                FROM Application__c
                WHERE Application_Status__c = 'Quote' AND Application_Status__c != 'Deleted'
                AND (Customer_Name__r.Name LIKE :likePattern
                   OR Customer_Name__r.Phone LIKE :likePattern
                   OR Name LIKE :likePattern
                   OR QuoteName__c LIKE :likePattern
                   OR Vehicle_VIN__c LIKE :likePattern)
                ORDER BY CreatedDate DESC
                LIMIT :pageSize
                OFFSET :offset
            ];
        }
        return apps;
    }

    // Build a map of application Id -> set of chip labels from active packages
    private static Map<Id, Set<String>> buildServiceLabelsByApplication(List<Application__c> apps) {
        Set<Id> appIds = new Set<Id>();
        for (Application__c a : apps) {
            appIds.add(a.Id);
        }
        if (appIds.isEmpty()) {
            return new Map<Id, Set<String>>();
        }
        List<Application_Package__c> packages = [
            SELECT Id, Application__c, RecordType.DeveloperName, RecordType.Name
            FROM Application_Package__c
            WHERE Active__c = true AND Application__c IN :appIds
        ];
        Map<Id, Set<String>> appIdToLabels = new Map<Id, Set<String>>();
        for (Application_Package__c pkg : packages) {
            if (pkg.Application__c == null) continue;
            Set<String> labels = appIdToLabels.get(pkg.Application__c);
            if (labels == null) {
                labels = new Set<String>();
                appIdToLabels.put(pkg.Application__c, labels);
            }
            String label = (pkg.RecordType != null ? pkg.RecordType.Name : null);
            if (String.isNotBlank(label)) {
                labels.add(label);
            }
        }
        return appIdToLabels;
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
     * Create a new Application quote record with 'Quote' record type
     * @return CreateQuoteResponse containing the created record ID or error message
     */
    @AuraEnabled
    public static CreateQuoteResponse createNewQuote() {
        try {
            Application__c newApp = new Application__c();
            newApp.RecordTypeId = Schema.SObjectType.Application__c.getRecordTypeInfosByDeveloperName().get('Quote').getRecordTypeId();
            newApp.Application_Status__c = 'Quote';
            
            insert newApp;
            
            CreateQuoteResponse response = new CreateQuoteResponse();
            response.success = true;
            response.message = 'Quote created successfully';
            response.recordId = newApp.Id;
            return response;
        } catch (Exception e) {
            CreateQuoteResponse response = new CreateQuoteResponse();
            response.success = false;
            response.message = 'Error creating quote: ' + e.getMessage();
            response.recordId = null;
            return response;
        }
    }

    // Response wrapper for quote creation
    public class CreateQuoteResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public String recordId;
        public CreateQuoteResponse() {}
    }

    // Build DTO rows from apps, labels, and file existence map
    private static List<ApplicationRow> buildRows(List<Application__c> apps, Map<Id, Set<String>> appIdToServiceLabels, Map<Id, Boolean> hasFilesMap) {
        List<ApplicationRow> rows = new List<ApplicationRow>();
        for (Application__c a : apps) {
            ApplicationRow row = new ApplicationRow();
            row.id = a.Id;
            row.appNumber = a.Name;
            row.quoteName = a.QuoteName__c;
            row.createdDate = a.CreatedDate;
            row.vehicleName = (a.Vehicle__r != null ? a.Vehicle__r.Name : null);
            row.odometer = a.Odometer__c;
            row.oddometerUnit = a.Odometer_Unit__c;
            row.vehicleVin = a.Vehicle_VIN__c;
            row.purchasePrice = a.Vehicle_Purchase_Price__c;
            row.paymentStatus = a.Payment_Status__c;
            row.hasFiles = hasFilesMap.containsKey(a.Id);
            row.services = new List<String>();
            if (appIdToServiceLabels != null && appIdToServiceLabels.containsKey(a.Id)) {
                row.services.addAll(appIdToServiceLabels.get(a.Id));
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