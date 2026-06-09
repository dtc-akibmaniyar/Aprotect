public with sharing class QuotePDFGeneratorService {

    public class QuotePDFException extends Exception {}

    public class QuotePDFResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String fileName;
        @AuraEnabled public String contentDocumentId;
        @AuraEnabled public String contentVersionId;
    }

    @AuraEnabled
    public static QuotePDFResult generateQuotePDF(Id applicationId) {
        if (applicationId == null) {
            throw new QuotePDFException('Application ID is required.');
        }

        List<Application__c> apps = [
            SELECT Id, Name, QuoteName__c
            FROM Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            throw new QuotePDFException('Application not found: ' + applicationId);
        }
        Application__c app = apps[0];

        PageReference pdfPage = new PageReference('/apex/QuotePDF');
        pdfPage.getParameters().put('id', applicationId);

        Blob pdfBlob;
        if (Test.isRunningTest()) {
            pdfBlob = Blob.valueOf('Test PDF Content');
        } else {
            pdfBlob = pdfPage.getContentAsPDF();
        }

        String baseName = 'Quote';
        if (String.isNotBlank(app.QuoteName__c)) {
            baseName += ' - ' + app.QuoteName__c;
        } else if (String.isNotBlank(app.Name)) {
            baseName += ' - ' + app.Name;
        }
        
        String dateStr = Date.today().year() + '-' 
            + String.valueOf(Date.today().month()).leftPad(2, '0') + '-' 
            + String.valueOf(Date.today().day()).leftPad(2, '0');
        
        Integer versionNum = 1;
        List<ContentDocumentLink> allLinks = [
            SELECT ContentDocumentId, ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :applicationId
            AND ContentDocument.Title LIKE 'Quote%'
            ORDER BY ContentDocument.CreatedDate DESC
        ];
        if (!allLinks.isEmpty()) {
            versionNum = allLinks.size() + 1;
        }
        
        String fileName = baseName + ' - ' + dateStr + ' - v' + versionNum + '.pdf';

        List<ContentDocumentLink> existingLinks = [
            SELECT ContentDocumentId, ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :applicationId
            AND ContentDocument.Title LIKE 'Quote%'
            ORDER BY ContentDocument.CreatedDate DESC
            LIMIT 1
        ];

        ContentVersion cv = new ContentVersion();
        cv.Title = baseName + ' - ' + dateStr + ' - v' + versionNum;
        cv.PathOnClient = fileName;
        cv.VersionData = pdfBlob;

        if (!existingLinks.isEmpty()) {
            cv.ContentDocumentId = existingLinks[0].ContentDocumentId;
        } else {
            cv.FirstPublishLocationId = applicationId;
        }
        insert cv;

        ContentVersion inserted = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

        QuotePDFResult result = new QuotePDFResult();
        result.success = true;
        result.fileName = fileName;
        result.contentDocumentId = inserted.ContentDocumentId;
        result.contentVersionId = inserted.Id;

        return result;
    }

    /**
     * Get the latest Quote PDF ContentVersionId for an Application.
     * Returns null if no Quote PDF exists.
     */
    @AuraEnabled
    public static String getLatestQuotePDFVersionId(Id applicationId) {
        List<ContentDocumentLink> links = [
            SELECT ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :applicationId
            AND ContentDocument.Title LIKE 'Quote%'
            ORDER BY ContentDocument.LastModifiedDate DESC
            LIMIT 1
        ];
        if (links.isEmpty()) {
            return null;
        }
        return links[0].ContentDocument.LatestPublishedVersionId;
    }

    @AuraEnabled(cacheable=true)
    public static Boolean hasRelatedFiles(Id applicationId) {
        Integer count = [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :applicationId];
        return count > 0;
    }
}