@IsTest
private class QuotePDFGeneratorServiceTest {

    @TestSetup
    static void setupData() {
        // Create an Account (required if Application__c has a lookup to Account)
        Account acc = new Account(Name = 'Test Dealer Account');
        insert acc;

        // Create an Application__c record with Quote record type
        Id quoteRtId = Schema.SObjectType.Application__c.getRecordTypeInfosByDeveloperName().get('Quote').getRecordTypeId();
        Application__c app = new Application__c(
            Application_Status__c = 'Quote',
            RecordTypeId = quoteRtId,
            Customer_Name__c = acc.Id
        );
        insert app;
    }

    @IsTest
    static void testGenerateQuotePDF_Success() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Test.startTest();
        String cvId = QuotePDFGeneratorService.generateQuotePDF(app.Id);
        Test.stopTest();

        System.assertNotEquals(null, cvId, 'ContentVersion Id should be returned');

        // Verify ContentVersion was created
        ContentVersion cv = [SELECT Id, Title, PathOnClient FROM ContentVersion WHERE Id = :cvId];
        System.assert(cv.Title.startsWith('Quote'), 'Title should start with Quote');
        System.assert(cv.PathOnClient.endsWith('.pdf'), 'File should be a PDF');

        // Verify it is linked to the Application
        List<ContentDocumentLink> links = [
            SELECT Id FROM ContentDocumentLink
            WHERE LinkedEntityId = :app.Id
        ];
        System.assert(!links.isEmpty(), 'PDF should be linked to the Application record');
    }

    @IsTest
    static void testGenerateQuotePDF_NullId() {
        Test.startTest();
        try {
            QuotePDFGeneratorService.generateQuotePDF(null);
            System.assert(false, 'Should have thrown exception');
        } catch (QuotePDFGeneratorService.QuotePDFException e) {
            System.assert(e.getMessage().contains('required'), 'Error should mention required');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGenerateQuotePDF_InvalidId() {
        // Use a fake but valid-format Application Id
        Id fakeId = Application__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001';

        Test.startTest();
        try {
            QuotePDFGeneratorService.generateQuotePDF(fakeId);
            System.assert(false, 'Should have thrown exception');
        } catch (QuotePDFGeneratorService.QuotePDFException e) {
            System.assert(e.getMessage().contains('not found'), 'Error should mention not found');
        }
        Test.stopTest();
    }
}