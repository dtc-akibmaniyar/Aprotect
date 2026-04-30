public with sharing class EnvelopeStatusService {
    
    @AuraEnabled(cacheable=true)
    public static List<dfsle__EnvelopeStatus__c> getEnvelopeStatusRecords(Id sourceId) {
        try {
            if (sourceId == null) {
                return new List<dfsle__EnvelopeStatus__c>();
            }

            // Query envelope status records filtered by source ID
            List<dfsle__EnvelopeStatus__c> statusRecords = [
                SELECT 
                    Id,
                    Name,
                    dfsle__DocuSignId__c,
                    dfsle__Status__c,
                    dfsle__SenderEmail__c,
                    dfsle__SenderName__c,
                    dfsle__Sent__c,
                    dfsle__Completed__c,
                    dfsle__SourceId__c,
                    dfsle__LastStatusUpdate__c,
                    dfsle__Reason__c,
                    CreatedDate,
                    LastModifiedDate
                FROM dfsle__EnvelopeStatus__c
                WHERE dfsle__SourceId__c = :sourceId
                ORDER BY dfsle__Sent__c DESC
                LIMIT 10000
            ];

            return statusRecords;

        } catch (Exception e) {
            System.debug('Error in getEnvelopeStatusRecords: ' + e.getMessage());
            throw new AuraHandledException('Error retrieving envelope status records: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<dfsle__EnvelopeStatus__c> getEnvelopeStatusByFilter(
        Id sourceId, 
        String status, 
        Integer recordLimit
    ) {
        try {
            if (sourceId == null) {
                return new List<dfsle__EnvelopeStatus__c>();
            }

            Integer limit_value = recordLimit != null ? recordLimit : 10000;

            String query = 'SELECT Id, Name, dfsle__DocuSignId__c, dfsle__Status__c, dfsle__SenderEmail__c, ' +
                          'dfsle__SenderName__c, dfsle__Sent__c, dfsle__Completed__c, dfsle__SourceId__c, ' +
                          'dfsle__LastStatusUpdate__c, dfsle__Reason__c, CreatedDate, LastModifiedDate ' +
                          'FROM dfsle__EnvelopeStatus__c WHERE dfsle__SourceId__c = :sourceId';

            if (String.isNotBlank(status)) {
                query += ' AND dfsle__Status__c = :status';
            }

            query += ' ORDER BY dfsle__Sent__c DESC LIMIT ' + limit_value;

            List<dfsle__EnvelopeStatus__c> statusRecords = Database.query(query);
            return statusRecords;

        } catch (Exception e) {
            System.debug('Error in getEnvelopeStatusByFilter: ' + e.getMessage());
            throw new AuraHandledException('Error retrieving filtered envelope status records: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static dfsle__EnvelopeStatus__c getEnvelopeStatusDetail(Id recordId) {
        try {
            if (recordId == null) {
                throw new AuraHandledException('Record ID is required.');
            }

            dfsle__EnvelopeStatus__c statusRecord = [
                SELECT 
                    Id,
                    Name,
                    dfsle__DocuSignId__c,
                    dfsle__Status__c,
                    dfsle__SenderEmail__c,
                    dfsle__SenderName__c,
                    dfsle__Sent__c,
                    dfsle__Completed__c,
                    dfsle__SourceId__c,
                    dfsle__LastStatusUpdate__c,
                    dfsle__Reason__c,
                    dfsle__Expires__c,
                    dfsle__Account__c,
                    dfsle__Contact__c,
                    CreatedDate,
                    LastModifiedDate
                FROM dfsle__EnvelopeStatus__c
                WHERE Id = :recordId
                LIMIT 1
            ];

            return statusRecord;

        } catch (Exception e) {
            System.debug('Error in getEnvelopeStatusDetail: ' + e.getMessage());
            throw new AuraHandledException('Error retrieving envelope status detail: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Integer> getEnvelopeStatusSummary(Id sourceId) {
        try {
            if (sourceId == null) {
                return new Map<String, Integer>();
            }

            Map<String, Integer> statusSummary = new Map<String, Integer>();

            // Get all status values and their counts
            AggregateResult[] groupedResults = [
                SELECT dfsle__Status__c, COUNT(Id) recordCount
                FROM dfsle__EnvelopeStatus__c
                WHERE dfsle__SourceId__c = :sourceId
                GROUP BY dfsle__Status__c
            ];

            for (AggregateResult result : groupedResults) {
                String statusValue = (String) result.get('dfsle__Status__c');
                Integer count = (Integer) result.get('recordCount');
                statusSummary.put(statusValue != null ? statusValue : 'Unknown', count);
            }

            return statusSummary;

        } catch (Exception e) {
            System.debug('Error in getEnvelopeStatusSummary: ' + e.getMessage());
            throw new AuraHandledException('Error retrieving envelope status summary: ' + e.getMessage());
        }
    }
}