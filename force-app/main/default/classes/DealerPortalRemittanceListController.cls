public with sharing class DealerPortalRemittanceListController {

    public class RemittanceListResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public List<RemittanceRow> data;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public Integer pageNumber;
        @AuraEnabled public Integer pageSize;
        @AuraEnabled public Integer totalPages;
        public RemittanceListResponse() {}
    }

    public class RemittanceRow {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Date expiryDate;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Decimal balance;
        @AuraEnabled public Decimal paidAmount;
        @AuraEnabled public String dealerName;
        @AuraEnabled public String payerName;
        @AuraEnabled public Integer plannedLineItems;
        @AuraEnabled public Integer paidLineItems;
        @AuraEnabled public String recordUrl;
        public RemittanceRow() {}
    }

    @AuraEnabled
    public static RemittanceListResponse getRemittanceFormsList(
        Integer pageNumber, Integer pageSize, String statusFilter
    ) {
        RemittanceListResponse resp = new RemittanceListResponse();
        resp.success = false;
        resp.message = '';

        try {
            if (pageNumber == null || pageNumber < 1) pageNumber = 1;
            if (pageSize == null || pageSize < 1) pageSize = 10;
            if (pageSize > 200) pageSize = 200;

            if (String.isBlank(statusFilter) || statusFilter == 'All') statusFilter = null;

            // Build WHERE clause
            List<String> conditions = new List<String>();

            if (statusFilter != null) {
                conditions.add('Status__c = :statusFilter');
            }

            String whereClause = conditions.isEmpty() ? '' : 'WHERE ' + String.join(conditions, ' AND ');

            // Count
            String countQuery = 'SELECT COUNT() FROM Remittance_Form__c ' + whereClause;
            Integer totalCount = Database.countQuery(countQuery);

            Integer totalPages = (totalCount > 0) ? Integer.valueOf(Math.ceil((Decimal)totalCount / (Decimal)pageSize)) : 1;
            if (pageNumber > totalPages) pageNumber = totalPages;
            Integer offset = (pageNumber - 1) * pageSize;

            // Fetch
            String query = 'SELECT Id, Name, Status__c, CreatedDate, Expiry_Date__c, ' +
                'Amount__c, Balance__c, Paid_Amount__c, Dealer_Name__r.Name, Payer_Name__c, ' +
                'Planned_Line_Items_Count__c, Paid_Line_Items_Count__c ' +
                'FROM Remittance_Form__c ' + whereClause +
                ' ORDER BY CreatedDate DESC LIMIT :pageSize OFFSET :offset';

            List<Remittance_Form__c> forms = Database.query(query);

            List<RemittanceRow> rows = new List<RemittanceRow>();
            for (Remittance_Form__c f : forms) {
                RemittanceRow row = new RemittanceRow();
                row.id = f.Id;
                row.name = f.Name;
                row.status = f.Status__c;
                row.createdDate = f.CreatedDate;
                row.expiryDate = f.Expiry_Date__c;
                row.amount = f.Amount__c;
                row.balance = f.Balance__c;
                row.paidAmount = f.Paid_Amount__c;
                row.dealerName = f.Dealer_Name__r != null ? f.Dealer_Name__r.Name : null;
                row.payerName = f.Payer_Name__c;
                row.plannedLineItems = f.Planned_Line_Items_Count__c != null ? Integer.valueOf(f.Planned_Line_Items_Count__c) : 0;
                row.paidLineItems = f.Paid_Line_Items_Count__c != null ? Integer.valueOf(f.Paid_Line_Items_Count__c) : 0;
                row.recordUrl = '/dealerportal/s/detail/' + f.Id;
                rows.add(row);
            }

            resp.success = true;
            resp.data = rows;
            resp.totalCount = totalCount;
            resp.pageNumber = pageNumber;
            resp.pageSize = pageSize;
            resp.totalPages = totalPages;

        } catch (Exception e) {
            resp.message = 'Error fetching remittance forms: ' + e.getMessage();
            System.debug('DealerPortalRemittanceListController error: ' + e.getMessage());
        }

        return resp;
    }
}