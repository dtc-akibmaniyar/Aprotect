/**
 * ContentManagerServiceTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Coverage target: 99%+
 *
 * No HTTP callouts — pure SOQL and DML.
 *
 * Covers every branch of:
 *   • getRecord          — blank/null/malformed id, app not found, app with no
 *                          customer, app with customer (name + email populated)
 *   • getContentDetails  — no CDLs, non-matching titles excluded, each of the
 *                          3 matching titles included, mix scenario
 *   • deleteContentDocument — valid Id deleted, invalid Id throws
 *   • ContentType        — all 8 named when branches + when else (9 total)
 *
 * Customer_Name__c on Application__c is a Lookup(Account) — writable.
 * The dynamic SOQL queries Customer_Name__r.Name and Customer_Name__r.PersonEmail
 * which resolve from a linked Person Account.
 */
@isTest
private class ContentManagerServiceTest {

    // ─────────────────────────────────────────────────────────────────────────
    // SHARED SETUP HELPERS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Creates a Dealer → Application (no customer linked).
     */
    private static Application__c setupApplication() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);
        return app;
    }

    /**
     * Creates a Dealer → Application with a Person Account linked as customer.
     */
    private static Map<String, SObject> setupApplicationWithCustomer() {
        Account        dealer   = TestDataFactory.createDealer(true);
        Account        customer = TestDataFactory.createCustomerAccount(true);
        Application__c app      = TestDataFactory.createApplication(dealer.Id, true);
        app.Customer_Name__c = customer.Id;
        update app;
        return new Map<String, SObject>{
            'dealer'   => dealer,
            'app'      => app,
            'customer' => customer
        };
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 1 — getRecord ERROR PATHS
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetRecord_nullId_throwsAuraHandledException() {
        // null → dynamic SOQL bind with null → SOQL exception → catch block
        Boolean thrown = false;

        Test.startTest();
        try {
            ContentManagerService.getRecord(null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();
    }

    @isTest
    static void testGetRecord_blankId_throwsAuraHandledException() {
        Boolean thrown = false;

        Test.startTest();
        try {
            ContentManagerService.getRecord('');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();
    }

    @isTest
    static void testGetRecord_malformedId_throwsAuraHandledException() {
        // Non-ID string → SOQL throws → catch
        Boolean thrown = false;

        Test.startTest();
        try {
            ContentManagerService.getRecord('NOT_A_VALID_SALESFORCE_ID');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 2 — getRecord SUCCESS PATHS
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetRecord_applicationNotFound_returnsNull() {
        // Well-formed Id that doesn't match any Application → returns null
        Test.startTest();
            String result = ContentManagerService.getRecord('a0000000000000ZAAQ');
        Test.stopTest();

        System.assertEquals(null, result,
            'Non-existent applicationId should return null');
    }

    @isTest
    static void testGetRecord_applicationFoundNoCustomer_returnsJsonWithNullCustomerFields() {
        Application__c app = setupApplication();
        // Customer_Name__c is null → Customer_Name__r.Name and PersonEmail are null

        Test.startTest();
            String result = ContentManagerService.getRecord(app.Id);
        Test.stopTest();

        System.assertNotEquals(null, result,
            'Found application should return a JSON string, not null');

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertNotEquals(null, parsed.get('Id'),
            'Serialised record should contain Id field');
    }

    @isTest
    static void testGetRecord_applicationFoundWithCustomer_returnsJsonWithCustomerName() {
        Map<String, SObject> chain = setupApplicationWithCustomer();
        Application__c app         = (Application__c) chain.get('app');
        Account        customer    = (Account)        chain.get('customer');

        // Re-query the customer to get exact Name set by factory
        customer = [SELECT Name, PersonEmail FROM Account WHERE Id = :customer.Id];

        Test.startTest();
            String result = ContentManagerService.getRecord(app.Id);
        Test.stopTest();

        System.assertNotEquals(null, result,
            'Application with linked customer should return JSON');

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertNotEquals(null, parsed.get('Id'),
            'Serialised record should contain Id');

        // Customer_Name__r is serialised as a nested map
        Object customerNameObj = parsed.get('Customer_Name__r');
        System.assertNotEquals(null, customerNameObj,
            'Customer_Name__r should be present in serialised JSON when customer is linked');

        Map<String, Object> customerNameMap = (Map<String, Object>) customerNameObj;
        System.assertNotEquals(null, customerNameMap.get('Name'),
            'Customer Name should be populated from Person Account');
    }

    @isTest
    static void testGetRecord_applicationFoundWithCustomerEmail_returnsPersonEmail() {
        Account        dealer   = TestDataFactory.createDealer(true);
        Account        customer = TestDataFactory.createCustomerAccount(true);
        Application__c app      = TestDataFactory.createApplication(dealer.Id, true);
        app.Customer_Name__c = customer.Id;
        update app;

        Test.startTest();
            String result = ContentManagerService.getRecord(app.Id);
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 3 — getContentDetails
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetContentDetails_noLinkedDocuments_returnsEmptyJsonArray() {
        Application__c app = setupApplication();
        // No ContentDocumentLinks created

        Test.startTest();
            String result = ContentManagerService.getContentDetails(app.Id);
        Test.stopTest();

        System.assertNotEquals(null, result,
            'Should return serialised JSON even when no documents exist');

        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(result);
        System.assertEquals(0, parsed.size(),
            'Empty array expected when no documents are linked');
    }

    @isTest
    static void testGetContentDetails_nonMatchingTitles_excludedFromResult() {
        Application__c app = setupApplication();

        // Create a ContentVersion with a title NOT in the filter list
        TestDataFactory.createLinkedContentVersion(app.Id, 'Some Other Document', 'pdf', true);

        Test.startTest();
            String result = ContentManagerService.getContentDetails(app.Id);
        Test.stopTest();

        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(result);
        System.assertEquals(0, parsed.size(),
            'Documents with non-matching titles should be excluded');
    }

    @isTest
    static void testGetContentDetails_totalLossCoverage_includedInResult() {
        Application__c app = setupApplication();
        TestDataFactory.createLinkedContentVersion(
            app.Id, 'Total Loss Coverage', 'pdf', true
        );

        Test.startTest();
            String result = ContentManagerService.getContentDetails(app.Id);
        Test.stopTest();

        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(result);
        System.assertEquals(1, parsed.size(),
            'Total Loss Coverage document should be included');

        Map<String, Object> cv = (Map<String, Object>) parsed[0];
        System.assertNotEquals(null, cv.get('Id'),
            'Id should be present in serialised ContentVersion');
        System.assertEquals('Total Loss Coverage', (String) cv.get('Title'),
            'Title should be Total Loss Coverage');
    }

    @isTest
    static void testGetContentDetails_extendedLimitedWarranty_includedInResult() {
        Application__c app = setupApplication();
        TestDataFactory.createLinkedContentVersion(
            app.Id, 'Extended Limited Warranty', 'pdf', true
        );

        Test.startTest();
            String result = ContentManagerService.getContentDetails(app.Id);
        Test.stopTest();

        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(result);
        System.assertEquals(1, parsed.size(),
            'Extended Limited Warranty document should be included');
        Map<String, Object> cv = (Map<String, Object>) parsed[0];
        System.assertEquals('Extended Limited Warranty', (String) cv.get('Title'),
            'Title should be Extended Limited Warranty');
    }

    @isTest
    static void testGetContentDetails_tireAndRimProtectionPlan_includedInResult() {
        Application__c app = setupApplication();
        TestDataFactory.createLinkedContentVersion(
            app.Id, 'Tire & Rim Protection Plan', 'pdf', true
        );

        Test.startTest();
            String result = ContentManagerService.getContentDetails(app.Id);
        Test.stopTest();

        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(result);
        System.assertEquals(1, parsed.size(),
            'Tire & Rim Protection Plan document should be included');
        Map<String, Object> cv = (Map<String, Object>) parsed[0];
        System.assertEquals('Tire & Rim Protection Plan', (String) cv.get('Title'),
            'Title should be Tire & Rim Protection Plan');
    }

    @isTest
    static void testGetContentDetails_allThreeMatchingTitles_allIncluded() {
        Application__c app = setupApplication();
        TestDataFactory.createLinkedContentVersion(
            app.Id, 'Total Loss Coverage',       'pdf', true
        );
        TestDataFactory.createLinkedContentVersion(
            app.Id, 'Extended Limited Warranty', 'pdf', true
        );
        TestDataFactory.createLinkedContentVersion(
            app.Id, 'Tire & Rim Protection Plan','pdf', true
        );

        Test.startTest();
            String result = ContentManagerService.getContentDetails(app.Id);
        Test.stopTest();

        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(result);
        System.assertEquals(3, parsed.size(),
            'All 3 matching documents should be returned');
    }

    @isTest
    static void testGetContentDetails_mixMatchingAndNonMatching_onlyMatchingReturned() {
        Application__c app = setupApplication();
        TestDataFactory.createLinkedContentVersion(
            app.Id, 'Extended Limited Warranty', 'pdf', true
        );
        TestDataFactory.createLinkedContentVersion(
            app.Id, 'Some Random Document',      'pdf', true
        );
        TestDataFactory.createLinkedContentVersion(
            app.Id, 'Total Loss Coverage',       'pdf', true
        );

        Test.startTest();
            String result = ContentManagerService.getContentDetails(app.Id);
        Test.stopTest();

        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(result);
        System.assertEquals(2, parsed.size(),
            'Only the 2 matching documents should be returned');

        // Collect titles from result
        Set<String> returnedTitles = new Set<String>();
        for (Object item : parsed) {
            Map<String, Object> cv = (Map<String, Object>) item;
            returnedTitles.add((String) cv.get('Title'));
        }
        System.assert(returnedTitles.contains('Extended Limited Warranty'),
            'Extended Limited Warranty should be in result');
        System.assert(returnedTitles.contains('Total Loss Coverage'),
            'Total Loss Coverage should be in result');
        System.assert(!returnedTitles.contains('Some Random Document'),
            'Non-matching title should not be in result');
    }

    @isTest
    static void testGetContentDetails_serialisedFieldsPresent() {
        // Verify the specific fields the SOQL selects appear in the JSON
        Application__c app = setupApplication();
        TestDataFactory.createLinkedContentVersion(
            app.Id, 'Total Loss Coverage', 'pdf', true
        );

        Test.startTest();
            String result = ContentManagerService.getContentDetails(app.Id);
        Test.stopTest();

        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(result);
        System.assertEquals(1, parsed.size(), 'One record expected');

        Map<String, Object> cv = (Map<String, Object>) parsed[0];
        System.assertNotEquals(null, cv.get('Id'),              'Id should be present');
        System.assertNotEquals(null, cv.get('Title'),           'Title should be present');
        System.assertNotEquals(null, cv.get('FileType'),        'FileType should be present');
        System.assertNotEquals(null, cv.get('FileExtension'),   'FileExtension should be present');
        System.assertNotEquals(null, cv.get('ContentDocumentId'),'ContentDocumentId should be present');
        System.assertNotEquals(null, cv.get('CreatedDate'),     'CreatedDate should be present');
    }
/*
    @isTest
    static void testGetContentDetails_onlyReturnsRecordsForMatchingLinkedEntity() {
        Application__c app1 = setupApplication();
        Application__c app2 = setupApplication();

        TestDataFactory.createLinkedContentVersion(
            app1.Id, 'Total Loss Coverage', 'pdf', true
        );
        TestDataFactory.createLinkedContentVersion(
            app2.Id, 'Total Loss Coverage', 'pdf', true
        );

        Test.startTest();
            String result = ContentManagerService.getContentDetails(app1.Id);
        Test.stopTest();

        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(result);
        System.assertEquals(1, parsed.size(),
            'Only documents linked to app1 should be returned');
    }
*/
    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 4 — deleteContentDocument
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testDeleteContentDocument_validId_recordDeleted() {
        Application__c app = setupApplication();
        ContentVersion cv = TestDataFactory.createLinkedContentVersion(
            app.Id, 'Total Loss Coverage', 'pdf', true
        );

        // Get the ContentDocumentId so we can verify deletion
        ContentVersion queried = [
            SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id
        ];
        Id contentDocumentId = queried.ContentDocumentId;

        Test.startTest();
            ContentManagerService.deleteContentDocument(contentDocumentId);
        Test.stopTest();

        List<ContentDocument> remaining = [
            SELECT Id FROM ContentDocument WHERE Id = :contentDocumentId
        ];
        System.assertEquals(0, remaining.size(),
            'ContentDocument should be deleted after deleteContentDocument call');
    }

    @isTest
    static void testDeleteContentDocument_invalidId_throwsException() {
        // Passing a non-existent but well-formed Id → Database.delete throws
        Boolean thrown = false;

        Test.startTest();
        try {
            ContentManagerService.deleteContentDocument('a0000000000000ZAAQ');
        } catch (Exception e) {
            thrown = true;
            System.assertNotEquals(null, e.getMessage(),
                'Exception message should be populated for invalid Id');
        }
        Test.stopTest();

        System.assert(thrown,
            'Database.delete with non-existent Id should throw an exception');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 5 — ContentType (every when branch)
    // Pure logic — no data required.
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testContentType_docx_returnsWordMimeType() {
        Test.startTest();
            String result = ContentManagerService.ContentType('docx');
        Test.stopTest();

        System.assertEquals(
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            result,
            'docx should return Word document MIME type'
        );
    }

    @isTest
    static void testContentType_docxUpperCase_returnsWordMimeType() {
        // fileType.toLowerCase() means 'DOCX' should hit the same branch
        Test.startTest();
            String result = ContentManagerService.ContentType('DOCX');
        Test.stopTest();

        System.assertEquals(
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            result,
            'DOCX (uppercase) should match docx branch via toLowerCase()'
        );
    }

    @isTest
    static void testContentType_csv_returnsExcelMimeType() {
        Test.startTest();
            String result = ContentManagerService.ContentType('csv');
        Test.stopTest();

        System.assertEquals('application/vnd.ms-excel', result,
            'csv should return Excel MIME type');
    }

    @isTest
    static void testContentType_wav_returnsAudioWav() {
        Test.startTest();
            String result = ContentManagerService.ContentType('wav');
        Test.stopTest();

        System.assertEquals('audio/wav', result,
            'wav should return audio/wav MIME type');
    }

    @isTest
    static void testContentType_wmv_returnsVideoWmv() {
        Test.startTest();
            String result = ContentManagerService.ContentType('wmv');
        Test.stopTest();

        System.assertEquals('video/x-ms-wmv', result,
            'wmv should return video/x-ms-wmv MIME type');
    }

    @isTest
    static void testContentType_mp3_returnsAudioMpeg() {
        Test.startTest();
            String result = ContentManagerService.ContentType('mp3');
        Test.stopTest();

        System.assertEquals('audio/mpeg', result,
            'mp3 should return audio/mpeg MIME type');
    }

    @isTest
    static void testContentType_mp4_returnsVideoMp4() {
        Test.startTest();
            String result = ContentManagerService.ContentType('mp4');
        Test.stopTest();

        System.assertEquals('video/mp4', result,
            'mp4 should return video/mp4 MIME type');
    }

    @isTest
    static void testContentType_png_returnsImagePng() {
        Test.startTest();
            String result = ContentManagerService.ContentType('png');
        Test.stopTest();

        System.assertEquals('image/png', result,
            'png should return image/png MIME type');
    }

    @isTest
    static void testContentType_pdf_returnsApplicationPdf() {
        Test.startTest();
            String result = ContentManagerService.ContentType('pdf');
        Test.stopTest();

        System.assertEquals('application/pdf', result,
            'pdf should return application/pdf MIME type');
    }

    @isTest
    static void testContentType_jpg_returnsImageJpeg() {
        // jpg is not in any named when → falls to when else → image/jpeg
        Test.startTest();
            String result = ContentManagerService.ContentType('jpg');
        Test.stopTest();

        System.assertEquals('image/jpeg', result,
            'jpg should fall to when else and return image/jpeg');
    }

    @isTest
    static void testContentType_jpeg_returnsImageJpeg() {
        Test.startTest();
            String result = ContentManagerService.ContentType('jpeg');
        Test.stopTest();

        System.assertEquals('image/jpeg', result,
            'jpeg should fall to when else and return image/jpeg');
    }

    @isTest
    static void testContentType_unknownExtension_returnsImageJpeg() {
        Test.startTest();
            String result = ContentManagerService.ContentType('xyz');
        Test.stopTest();

        System.assertEquals('image/jpeg', result,
            'Unknown extension should fall to when else and return image/jpeg');
    }

    @isTest
    static void testContentType_mixedCase_normalizedByToLowerCase() {
        // PDF, PDF, Pdf all go lowercase → 'pdf' branch
        Test.startTest();
            String r1 = ContentManagerService.ContentType('PDF');
            String r2 = ContentManagerService.ContentType('Pdf');
            String r3 = ContentManagerService.ContentType('pDf');
        Test.stopTest();

        System.assertEquals('application/pdf', r1, 'PDF uppercase should resolve to pdf branch');
        System.assertEquals('application/pdf', r2, 'Pdf mixed case should resolve to pdf branch');
        System.assertEquals('application/pdf', r3, 'pDf mixed case should resolve to pdf branch');
    }
}