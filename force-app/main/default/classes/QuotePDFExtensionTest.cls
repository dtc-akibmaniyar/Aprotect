@isTest
private class QuotePDFExtensionTest {

    @TestSetup
    static void setupTestData() {
        // Create Account (dealer) with Show_Logo_On_PDF__c
        Account dealer = new Account(
            Name = 'Test Dealer',
            Phone = '555-1234',
            BillingStreet = '123 Test St',
            BillingCity = 'Toronto',
            BillingState = 'ON',
            BillingPostalCode = 'M5V 1A1',
            Show_Logo_On_PDF__c = true
        );
        insert dealer;

        // Create Account without logo permission
        Account dealerNoLogo = new Account(
            Name = 'No Logo Dealer',
            Show_Logo_On_PDF__c = false
        );
        insert dealerNoLogo;
    }

    @isTest
    static void testQuotePDFExtension_WithLogoPermission() {
        Account dealer = [SELECT Id FROM Account WHERE Name = 'Test Dealer' LIMIT 1];

        // Create Application linked to dealer
        Application__c app = new Application__c(
            Dealer_Name__c = dealer.Id,
            Application_Status__c = 'Quote'
        );
        insert app;

        Test.startTest();
        ApexPages.StandardController stdCtrl = new ApexPages.StandardController(app);
        QuotePDFExtension ext = new QuotePDFExtension(stdCtrl);
        Test.stopTest();

        System.assertNotEquals(null, ext.packageWrappersList, 'Package wrappers list should not be null');
        System.assertEquals('Test Dealer', ext.dealerName, 'Dealer name should be populated');
        System.assertEquals(true, ext.showLogoOnPdf, 'Show logo should be true');
    }

    @isTest
    static void testQuotePDFExtension_WithoutLogoPermission() {
        Account dealer = [SELECT Id FROM Account WHERE Name = 'No Logo Dealer' LIMIT 1];

        Application__c app = new Application__c(
            Dealer_Name__c = dealer.Id,
            Application_Status__c = 'Quote'
        );
        insert app;

        Test.startTest();
        ApexPages.StandardController stdCtrl = new ApexPages.StandardController(app);
        QuotePDFExtension ext = new QuotePDFExtension(stdCtrl);
        Test.stopTest();

        System.assertEquals(false, ext.showLogoOnPdf, 'Show logo should be false');
        System.assertEquals(false, ext.hasDealerLogo, 'Dealer logo should be hidden');
    }

    @isTest
    static void testQuotePDFExtension_NoDealer() {
        Application__c app = new Application__c(
            Application_Status__c = 'Quote'
        );
        insert app;

        Test.startTest();
        ApexPages.StandardController stdCtrl = new ApexPages.StandardController(app);
        QuotePDFExtension ext = new QuotePDFExtension(stdCtrl);
        Test.stopTest();

        System.assertNotEquals(null, ext.packageWrappersList, 'Package wrappers list should not be null');
        System.assertEquals(0, ext.packageWrappersList.size(), 'Should have no packages');
    }

    @isTest
    static void testGenerateQuotePDF() {
        Account dealer = [SELECT Id FROM Account WHERE Name = 'Test Dealer' LIMIT 1];

        Application__c app = new Application__c(
            Dealer_Name__c = dealer.Id,
            Application_Status__c = 'Quote'
        );
        insert app;

        Test.startTest();
        ApplicationSummaryController.PDFResponse response = ApplicationSummaryController.generateQuotePDF(app.Id);
        Test.stopTest();

        System.assertEquals(true, response.success, 'PDF generation should succeed: ' + response.message);
        System.assertNotEquals(null, response.attachmentId, 'Should have attachment ID');
    }

    @isTest
    static void testGenerateQuotePDF_NoPackages() {
        Application__c app = new Application__c(
            Application_Status__c = 'Quote'
        );
        insert app;

        Test.startTest();
        ApplicationSummaryController.PDFResponse response = ApplicationSummaryController.generateQuotePDF(app.Id);
        Test.stopTest();

        System.assertEquals(true, response.success, 'PDF generation should succeed even with no packages');
    }
}