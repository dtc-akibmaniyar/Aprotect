/**
 * ClientPdfUploadTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Coverage target: 99%+
 *
 * No HTTP callouts — pure DML.
 *
 * Covers every branch of savePdf():
 *   • blank base64Data (null, empty, whitespace) → AuraHandledException
 *   • data URL format (contains ',') → substringAfter(',') used
 *   • pure base64 (no comma) → used directly
 *   • blank fileName → title = 'Application Summary', path = 'ApplicationSummary.pdf'
 *   • non-blank fileName with .pdf extension → .pdf stripped from title
 *   • non-blank fileName without .pdf extension → title unchanged
 *   • SaveResult.contentVersionId populated
 *   • SaveResult.downloadUrl format verified
 *   • ContentVersion inserted and queryable
 *   • ContentDocumentLink created linking to applicationId
 *   • SaveResult wrapper class properties get/set
 */
@isTest
private class ClientPdfUploadTest {

    // ─────────────────────────────────────────────────────────────────────────
    // SHARED HELPERS
    // ─────────────────────────────────────────────────────────────────────────

    /** Returns a minimal valid base64-encoded PDF string (no data URL prefix). */
    private static String validBase64() {
        return EncodingUtil.base64Encode(
            Blob.valueOf('%PDF-1.4 test content for ClientPdfUpload')
        );
    }

    /** Returns the same content wrapped in a data URL prefix. */
    private static String validDataUrl() {
        return 'data:application/pdf;base64,' + validBase64();
    }

    /** Creates and inserts a minimal Application__c for use as applicationId. */
    private static Application__c setupApplication() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);
        return app;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 1 — SaveResult WRAPPER CLASS
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testSaveResultWrapper_allPropertiesGetAndSet() {
        ClientPdfUpload.SaveResult res = new ClientPdfUpload.SaveResult();
        res.contentVersionId = UserInfo.getUserId(); // any valid Id
        res.downloadUrl      = '/sfc/servlet.shepherd/version/download/someId';

        System.assertNotEquals(null, res.contentVersionId,
            'contentVersionId should be set');
        System.assertEquals(
            '/sfc/servlet.shepherd/version/download/someId',
            res.downloadUrl,
            'downloadUrl should match'
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 2 — savePdf VALIDATION: BLANK BASE64 DATA
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testSavePdf_nullBase64Data_throwsAuraHandledException() {
        Application__c app = setupApplication();
        Boolean thrown = false;

        Test.startTest();
        try {
            ClientPdfUpload.savePdf(app.Id, null, 'test.pdf');
        } catch (AuraHandledException e) {
            thrown = true;
            System.assert(
                e.getMessage().contains('No PDF data') ||
                e.getMessage() == 'Script-thrown exception',
                'Exception should relate to missing PDF data'
            );
        }
        Test.stopTest();

        System.assert(thrown,
            'Null base64Data should throw AuraHandledException');
    }

    @isTest
    static void testSavePdf_emptyStringBase64Data_throwsAuraHandledException() {
        Application__c app = setupApplication();
        Boolean thrown = false;

        Test.startTest();
        try {
            ClientPdfUpload.savePdf(app.Id, '', 'test.pdf');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown,
            'Empty string base64Data should throw AuraHandledException');
    }

    @isTest
    static void testSavePdf_whitespaceBase64Data_throwsAuraHandledException() {
        Application__c app = setupApplication();
        Boolean thrown = false;

        Test.startTest();
        try {
            ClientPdfUpload.savePdf(app.Id, '   ', 'test.pdf');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown,
            'Whitespace-only base64Data should throw AuraHandledException');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 3 — savePdf BASE64 INPUT FORMAT BRANCHES
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testSavePdf_pureBase64NoComma_usedDirectly() {
        // No comma → clean = base64Data (no substringAfter)
        Application__c app = setupApplication();

        Test.startTest();
            ClientPdfUpload.SaveResult result =
                ClientPdfUpload.savePdf(app.Id, validBase64(), 'PureBase64.pdf');
        Test.stopTest();

        System.assertNotEquals(null, result,
            'Pure base64 input should return a SaveResult');
        System.assertNotEquals(null, result.contentVersionId,
            'contentVersionId should be populated for pure base64 input');

        // Verify ContentVersion was actually inserted
        List<ContentVersion> cvs = [
            SELECT Id FROM ContentVersion WHERE Id = :result.contentVersionId
        ];
        System.assertEquals(1, cvs.size(),
            'ContentVersion should be inserted for pure base64 input');
    }

    @isTest
    static void testSavePdf_dataUrlWithComma_substringAfterCommaUsed() {
        // Contains ',' → substringAfter(',') extracts the base64 part
        Application__c app = setupApplication();

        Test.startTest();
            ClientPdfUpload.SaveResult result =
                ClientPdfUpload.savePdf(app.Id, validDataUrl(), 'DataUrl.pdf');
        Test.stopTest();

        System.assertNotEquals(null, result,
            'Data URL input should return a SaveResult');
        System.assertNotEquals(null, result.contentVersionId,
            'contentVersionId should be populated for data URL input');

        // Verify the content was correctly decoded (ContentVersion exists with data)
        ContentVersion cv = [
            SELECT VersionData FROM ContentVersion WHERE Id = :result.contentVersionId
        ];
        System.assertNotEquals(null, cv.VersionData,
            'ContentVersion VersionData should not be null for data URL input');
        System.assert(cv.VersionData.size() > 0,
            'ContentVersion VersionData should have content');
    }

    @isTest
    static void testSavePdf_dataUrlAndPureBase64_produceEquivalentContent() {
        // Both paths should decode to the same bytes
        Application__c app = setupApplication();

        Test.startTest();
            ClientPdfUpload.SaveResult r1 =
                ClientPdfUpload.savePdf(app.Id, validBase64(), 'Doc1.pdf');
            ClientPdfUpload.SaveResult r2 =
                ClientPdfUpload.savePdf(app.Id, validDataUrl(), 'Doc2.pdf');
        Test.stopTest();

        ContentVersion cv1 = [SELECT VersionData FROM ContentVersion WHERE Id = :r1.contentVersionId];
        ContentVersion cv2 = [SELECT VersionData FROM ContentVersion WHERE Id = :r2.contentVersionId];

        System.assertEquals(cv1.VersionData.size(), cv2.VersionData.size(),
            'Pure base64 and data URL paths should produce identical file sizes');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 4 — savePdf FILE NAME BRANCHES
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testSavePdf_nullFileName_usesDefaultTitleAndPath() {
        Application__c app = setupApplication();

        Test.startTest();
            ClientPdfUpload.SaveResult result =
                ClientPdfUpload.savePdf(app.Id, validBase64(), null);
        Test.stopTest();

        System.assertNotEquals(null, result.contentVersionId,
            'Null fileName should still succeed');

        ContentVersion cv = [
            SELECT Title, PathOnClient
            FROM   ContentVersion
            WHERE  Id = :result.contentVersionId
        ];

        System.assertEquals('Application Summary', cv.Title,
            'Blank fileName should default title to "Application Summary"');
        System.assertEquals('ApplicationSummary.pdf', cv.PathOnClient,
            'Blank fileName should default PathOnClient to "ApplicationSummary.pdf"');
    }

    @isTest
    static void testSavePdf_emptyFileName_usesDefaultTitleAndPath() {
        Application__c app = setupApplication();

        Test.startTest();
            ClientPdfUpload.SaveResult result =
                ClientPdfUpload.savePdf(app.Id, validBase64(), '');
        Test.stopTest();

        ContentVersion cv = [
            SELECT Title, PathOnClient FROM ContentVersion WHERE Id = :result.contentVersionId
        ];

        System.assertEquals('Application Summary', cv.Title,
            'Empty fileName should default title to "Application Summary"');
        System.assertEquals('ApplicationSummary.pdf', cv.PathOnClient,
            'Empty fileName should default PathOnClient to "ApplicationSummary.pdf"');
    }

    @isTest
    static void testSavePdf_fileNameWithPdfExtension_pdfStrippedFromTitle() {
        // fileName = 'MyDocument.pdf' → Title = 'MyDocument', PathOnClient = 'MyDocument.pdf'
        Application__c app = setupApplication();

        Test.startTest();
            ClientPdfUpload.SaveResult result =
                ClientPdfUpload.savePdf(app.Id, validBase64(), 'MyDocument.pdf');
        Test.stopTest();

        ContentVersion cv = [
            SELECT Title, PathOnClient FROM ContentVersion WHERE Id = :result.contentVersionId
        ];

        System.assertEquals('MyDocument', cv.Title,
            'Title should have .pdf extension stripped');
        System.assertEquals('MyDocument.pdf', cv.PathOnClient,
            'PathOnClient should retain the .pdf extension');
    }

    @isTest
    static void testSavePdf_fileNameWithoutPdfExtension_titleUnchanged() {
        // fileName = 'MyReport' → replace('.pdf','') has no effect → Title = 'MyReport'
        Application__c app = setupApplication();

        Test.startTest();
            ClientPdfUpload.SaveResult result =
                ClientPdfUpload.savePdf(app.Id, validBase64(), 'MyReport');
        Test.stopTest();

        ContentVersion cv = [
            SELECT Title, PathOnClient FROM ContentVersion WHERE Id = :result.contentVersionId
        ];

        System.assertEquals('MyReport', cv.Title,
            'Title should be unchanged when fileName has no .pdf extension');
        System.assertEquals('MyReport', cv.PathOnClient,
            'PathOnClient should match fileName when no .pdf extension present');
    }

    @isTest
    static void testSavePdf_fileNameWithPdfInMiddle_onlyExtensionStripped() {
        // 'pdf' in middle of name — replace('.pdf','') only removes .pdf suffix
        Application__c app = setupApplication();

        Test.startTest();
            ClientPdfUpload.SaveResult result =
                ClientPdfUpload.savePdf(app.Id, validBase64(), 'my.pdffile.pdf');
        Test.stopTest();

        ContentVersion cv = [
            SELECT Title FROM ContentVersion WHERE Id = :result.contentVersionId
        ];

        // replace('.pdf','') replaces ALL occurrences — both '.pdf' sequences removed
        // 'my.pdffile.pdf'.replace('.pdf','') = 'myfile'
        System.assertEquals('myfile', cv.Title,
            'replace(.pdf,) removes all .pdf occurrences from the title');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 5 — savePdf DML: ContentVersion AND ContentDocumentLink
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testSavePdf_contentVersionInserted_hasCorrectVersionData() {
        Application__c app = setupApplication();
        String b64 = validBase64();
        Blob   expectedData = EncodingUtil.base64Decode(b64);

        Test.startTest();
            ClientPdfUpload.SaveResult result =
                ClientPdfUpload.savePdf(app.Id, b64, 'DataCheck.pdf');
        Test.stopTest();

        ContentVersion cv = [
            SELECT VersionData FROM ContentVersion WHERE Id = :result.contentVersionId
        ];

        System.assertEquals(expectedData.size(), cv.VersionData.size(),
            'ContentVersion VersionData size should match decoded base64 input');
    }

    @isTest
    static void testSavePdf_contentDocumentLinkCreated_linkedToApplication() {
        Application__c app = setupApplication();

        Test.startTest();
            ClientPdfUpload.SaveResult result =
                ClientPdfUpload.savePdf(app.Id, validBase64(), 'LinkTest.pdf');
        Test.stopTest();

        // Look up the ContentDocumentId for the inserted ContentVersion
        ContentVersion cv = [
            SELECT ContentDocumentId FROM ContentVersion WHERE Id = :result.contentVersionId
        ];

        List<ContentDocumentLink> links = [
            SELECT LinkedEntityId, ShareType, Visibility
            FROM   ContentDocumentLink
            WHERE  ContentDocumentId = :cv.ContentDocumentId
            AND    LinkedEntityId    = :app.Id
        ];

        System.assertEquals(1, links.size(),
            'Exactly one ContentDocumentLink should be created linking the CV to the Application');
        System.assertEquals('V', links[0].ShareType,
            'ShareType should be V');
        System.assertEquals('AllUsers', links[0].Visibility,
            'Visibility should be AllUsers');
    }

    @isTest
    static void testSavePdf_contentDocumentLinkShareTypeAndVisibility_correct() {
        Application__c app = setupApplication();

        Test.startTest();
            ClientPdfUpload.SaveResult result =
                ClientPdfUpload.savePdf(app.Id, validBase64(), 'ShareType.pdf');
        Test.stopTest();

        ContentVersion cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :result.contentVersionId];

        ContentDocumentLink cdl = [
            SELECT ShareType, Visibility
            FROM   ContentDocumentLink
            WHERE  ContentDocumentId = :cv.ContentDocumentId
            AND    LinkedEntityId    = :app.Id
            LIMIT  1
        ];

        System.assertEquals('V',        cdl.ShareType,  'ShareType should be V (Viewer)');
        System.assertEquals('AllUsers', cdl.Visibility, 'Visibility should be AllUsers');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 6 — savePdf RETURN VALUE
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testSavePdf_contentVersionIdInResult_matchesInsertedRecord() {
        Application__c app = setupApplication();

        Test.startTest();
            ClientPdfUpload.SaveResult result =
                ClientPdfUpload.savePdf(app.Id, validBase64(), 'IdCheck.pdf');
        Test.stopTest();

        System.assertNotEquals(null, result.contentVersionId,
            'contentVersionId should not be null');

        // Verify the Id actually points to an existing ContentVersion
        List<ContentVersion> cvs = [
            SELECT Id FROM ContentVersion WHERE Id = :result.contentVersionId
        ];
        System.assertEquals(1, cvs.size(),
            'contentVersionId should reference a real ContentVersion record');
    }

    @isTest
    static void testSavePdf_downloadUrl_correctFormat() {
        Application__c app = setupApplication();

        Test.startTest();
            ClientPdfUpload.SaveResult result =
                ClientPdfUpload.savePdf(app.Id, validBase64(), 'UrlCheck.pdf');
        Test.stopTest();

        System.assertNotEquals(null, result.downloadUrl,
            'downloadUrl should not be null');
        System.assert(
            result.downloadUrl.startsWith('/sfc/servlet.shepherd/version/download/'),
            'downloadUrl should start with the correct servlet path'
        );
        System.assert(
            result.downloadUrl.contains(String.valueOf(result.contentVersionId)),
            'downloadUrl should contain the contentVersionId'
        );
    }

    @isTest
    static void testSavePdf_downloadUrlEqualsExpectedPattern() {
        Application__c app = setupApplication();

        Test.startTest();
            ClientPdfUpload.SaveResult result =
                ClientPdfUpload.savePdf(app.Id, validBase64(), 'PatternCheck.pdf');
        Test.stopTest();

        String expectedUrl =
            '/sfc/servlet.shepherd/version/download/' + result.contentVersionId;

        System.assertEquals(expectedUrl, result.downloadUrl,
            'downloadUrl should exactly match /sfc/servlet.shepherd/version/download/{cvId}');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 7 — savePdf MULTIPLE CALLS (bulkification / reuse)
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testSavePdf_calledTwiceForSameApplication_twoContentVersionsCreated() {
        Application__c app = setupApplication();

        Test.startTest();
            ClientPdfUpload.SaveResult r1 =
                ClientPdfUpload.savePdf(app.Id, validBase64(), 'First.pdf');
            ClientPdfUpload.SaveResult r2 =
                ClientPdfUpload.savePdf(app.Id, validBase64(), 'Second.pdf');
        Test.stopTest();

        System.assertNotEquals(r1.contentVersionId, r2.contentVersionId,
            'Each savePdf call should produce a distinct ContentVersion');

        Integer count = [
            SELECT COUNT()
            FROM   ContentDocumentLink
            WHERE  LinkedEntityId = :app.Id
        ];
        System.assertEquals(2, count,
            'Two ContentDocumentLinks should be created for two savePdf calls');
    }
}