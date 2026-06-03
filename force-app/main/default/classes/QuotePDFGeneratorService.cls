public with sharing class QuotePDFGeneratorService {

    public class QuotePDFException extends Exception {}

    /**
     * Generate a PDF from the QuotePDF Visualforce page for the given Application__c record,
     * save it as a ContentVersion (File) linked to the Application, and return the ContentVersion Id.
     * @param applicationId The Application__c record Id
     * @return The Id of the created ContentVersion record
     */
    @AuraEnabled
    public static String generateQuotePDF(Id applicationId) {
        if (applicationId == null) {
            throw new QuotePDFException('Application ID is required.');
        }

        // Query application for a meaningful file name
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

        // Build PageReference to the QuotePDF VF page
        PageReference pdfPage = new PageReference('/apex/QuotePDF');
        pdfPage.getParameters().put('id', applicationId);

        // Get PDF content
        Blob pdfBlob;
        if (Test.isRunningTest()) {
            // getContentAsPDF() is not supported in test context
            pdfBlob = Blob.valueOf('Test PDF Content');
        } else {
            pdfBlob = pdfPage.getContentAsPDF();
        }

        // Build file title
        String fileName = 'Quote';
        if (String.isNotBlank(app.QuoteName__c)) {
            fileName += ' - ' + app.QuoteName__c;
        } else if (String.isNotBlank(app.Name)) {
            fileName += ' - ' + app.Name;
        }
        fileName += '.pdf';

        // Create ContentVersion (File)
        ContentVersion cv = new ContentVersion();
        cv.Title = fileName;
        cv.PathOnClient = fileName;
        cv.VersionData = pdfBlob;
        cv.FirstPublishLocationId = applicationId; // Links to the Application record
        insert cv;

        return cv.Id;
    }
}