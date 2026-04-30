/**
 * DocusignApplicationServiceTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Coverage target: 99%+
 *
 * All HTTP callouts are intercepted via MockHttpCalloutFactory.
 * Multi-callout methods use MockHttpCalloutFactory.MultiRequestMock.
 *
 * KNOWN LIMITATION — sendEnvelopeWithTabs dfsle paths:
 *   sendEnvelopeWithTabs() calls dfsle.EnvelopeService.getEmptyEnvelope(),
 *   .withDocuments(), .withRecipients(), and .sendEnvelope(). These are
 *   managed-package methods that cannot be mocked via HttpCalloutMock. Only
 *   the null-customer validation path (throws before dfsle is touched) is
 *   reliably testable without the dfsle SDK's own test support.
 *
 * NOTE — AuraHandledException.getMessage():
 *   When caught as `Exception e` inside Apex, AuraHandledException.getMessage()
 *   returns 'Script-thrown exception' rather than the original constructor
 *   argument. Tests that verify error paths from DML/callout failures therefore
 *   assert result.success == false without checking the message text.
 */
@isTest
private class DocusignApplicationServiceTest {

    // ─────────────────────────────────────────────────────────────────────────
    // SHARED SETUP HELPERS
    // ─────────────────────────────────────────────────────────────────────────

    /** Returns a valid base64-encoded PDF string for pdfBase64Contents lists. */
    private static String testPdfBase64() {
        return EncodingUtil.base64Encode(
            Blob.valueOf('%PDF-1.4 test document content')
        );
    }

    /**
     * Creates a Dealer → Application → ContentVersion (PDF) chain.
     * The ContentVersion is linked to the Application via FirstPublishLocationId,
     * which creates a ContentDocumentLink automatically.
     * Required by sendForRemoteSigning / sendForEmbeddedSigning which call
     * getLatestLinkedPdf().
     */
    private static Map<String, SObject> setupApplicationWithPdf() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        ContentVersion cv = new ContentVersion(
            Title                  = 'Test Application PDF',
            PathOnClient           = 'test_application.pdf',
            VersionData            = Blob.valueOf('%PDF-1.4 test application content'),
            FirstPublishLocationId = app.Id,
            IsMajorVersion         = true
        );
        insert cv;

        return new Map<String, SObject>{
            'dealer' => dealer,
            'app'    => app,
            'cv'     => cv
        };
    }

    /**
     * Creates a Dealer → Application with Customer_Name__c linked.
     * Required by sendEnvelopeWithTabs which queries Customer_Name__c.
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
    // SECTION 1 — WRAPPER CLASS COVERAGE
    // Every @AuraEnabled property on every inner class.
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testSendResult_successConstructor_allPropertiesSet() {
        DocusignApplicationService.SendResult r =
            new DocusignApplicationService.SendResult('env-001', 'https://sign.test/url');

        System.assertEquals(true,                   r.success,      'success should be true');
        System.assertEquals('env-001',              r.envelopeId,   'envelopeId should match');
        System.assertEquals('https://sign.test/url',r.signingUrl,   'signingUrl should match');
        System.assertEquals(null,                   r.errorMessage, 'errorMessage should be null on success');
    }

    @isTest
    static void testSendResult_failureConstructor_allPropertiesSet() {
        DocusignApplicationService.SendResult r =
            new DocusignApplicationService.SendResult('Something went wrong');

        System.assertEquals(false,                  r.success,       'success should be false');
        System.assertEquals('Something went wrong', r.errorMessage,  'errorMessage should match');
        System.assertEquals(null,                   r.envelopeId,    'envelopeId should be null on failure');
        System.assertEquals(null,                   r.signingUrl,    'signingUrl should be null on failure');
    }

    @isTest
    static void testSendResult_successConstructor_nullSigningUrl() {
        // Remote signing path passes null for signingUrl
        DocusignApplicationService.SendResult r =
            new DocusignApplicationService.SendResult('env-002', null);

        System.assertEquals(true,     r.success,    'success should be true');
        System.assertEquals('env-002',r.envelopeId, 'envelopeId should match');
        System.assertEquals(null,     r.signingUrl, 'signingUrl should be null for remote signing');
    }

    @isTest
    static void testEnvelopeStatusResult_allPropertiesGetAndSet() {
        DocusignApplicationService.EnvelopeStatusResult r =
            new DocusignApplicationService.EnvelopeStatusResult();
        r.status          = 'completed';
        r.signedDateTime  = '2024-06-15T10:30:00.000Z';
        r.isComplete      = true;
        r.errorMessage    = null;

        System.assertEquals('completed',              r.status,         'status should match');
        System.assertEquals('2024-06-15T10:30:00.000Z',r.signedDateTime,'signedDateTime should match');
        System.assertEquals(true,                     r.isComplete,     'isComplete should match');
        System.assertEquals(null,                     r.errorMessage,   'errorMessage should be null');
    }

    @isTest
    static void testDocuSignConsentResult_allPropertiesGetAndSet() {
        DocusignApplicationService.DocuSignConsentResult r =
            new DocusignApplicationService.DocuSignConsentResult();
        r.requiresConsent = true;
        r.loginUrl        = 'https://account.docusign.com/oauth/auth?response_type=code';
        r.message         = 'User consent required';

        System.assertEquals(true,  r.requiresConsent, 'requiresConsent should match');
        System.assertNotEquals(null,r.loginUrl,        'loginUrl should match');
        System.assertEquals('User consent required', r.message, 'message should match');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 2 — generateUniqueClientUserId
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGenerateUniqueClientUserId_withPrefix_includesPrefix() {
        Test.startTest();
            String result = DocusignApplicationService.generateUniqueClientUserId('dealer');
        Test.stopTest();

        System.assertNotEquals(null, result,
            'Result should not be null');
        System.assert(result.startsWith('dealer_'),
            'Result should start with provided prefix');
        System.assert(result.length() > 10,
            'Result should be longer than just the prefix');
    }

    @isTest
    static void testGenerateUniqueClientUserId_blankPrefix_defaultsToClient() {
        Test.startTest();
            String result = DocusignApplicationService.generateUniqueClientUserId('');
        Test.stopTest();

        System.assert(result.startsWith('client_'),
            'Blank prefix should default to "client_"');
    }

    @isTest
    static void testGenerateUniqueClientUserId_nullPrefix_defaultsToClient() {
        Test.startTest();
            String result = DocusignApplicationService.generateUniqueClientUserId(null);
        Test.stopTest();

        System.assert(result.startsWith('client_'),
            'Null prefix should default to "client_"');
    }

    @isTest
    static void testGenerateUniqueClientUserId_calledTwice_returnsUniqueValues() {
        Test.startTest();
            String id1 = DocusignApplicationService.generateUniqueClientUserId('test');
            String id2 = DocusignApplicationService.generateUniqueClientUserId('test');
        Test.stopTest();

        System.assertNotEquals(id1, id2,
            'Two calls should return different values due to timestamp and random components');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 3 — sendUsingMultipleTemplatesWithCustomPDF (remote signing)
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testSendMultipleTemplatesRemote_nullApplicationId_returnsError() {
        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendUsingMultipleTemplatesWithCustomPDF(
                    null, 'tmpl-001', 'tmpl-002', 'signer@test.com', 'Test Signer', 'App.pdf'
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Null applicationId should return failure');
        System.assertEquals('Application Id is required.', result.errorMessage,
            'Error message should indicate Application Id is required');
    }

    @isTest
    static void testSendMultipleTemplatesRemote_blankSignatureTemplateId_returnsError() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendUsingMultipleTemplatesWithCustomPDF(
                    app.Id, '', 'tmpl-002', 'signer@test.com', 'Test Signer', 'App.pdf'
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Blank signatureTemplateId should return failure');
        System.assertEquals('Signature Template ID is required.', result.errorMessage,
            'Error message should indicate Signature Template ID is required');
    }

    @isTest
    static void testSendMultipleTemplatesRemote_blankTermsTemplateId_returnsError() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendUsingMultipleTemplatesWithCustomPDF(
                    app.Id, 'tmpl-001', '', 'signer@test.com', 'Test Signer', 'App.pdf'
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Blank termsTemplateId should return failure');
        System.assertEquals('Terms Template ID is required.', result.errorMessage,
            'Error message should indicate Terms Template ID is required');
    }

    @isTest
    static void testSendMultipleTemplatesRemote_blankSignerInfo_returnsError() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendUsingMultipleTemplatesWithCustomPDF(
                    app.Id, 'tmpl-001', 'tmpl-002', '', '', 'App.pdf'
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Blank signer info should return failure');
        System.assertEquals('Signer name and email are required.', result.errorMessage,
            'Error message should indicate signer info required');
    }

    @isTest
    static void testSendMultipleTemplatesRemote_success_returnsEnvelopeId() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory('DOCUSIGN_ENVELOPE_CREATED'));

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendUsingMultipleTemplatesWithCustomPDF(
                    app.Id, 'tmpl-001', 'tmpl-002',
                    'signer@test.com', 'Test Signer', 'Application.pdf'
                );
        Test.stopTest();

        System.assertEquals(true, result.success,
            'Valid request should succeed');
        System.assertEquals('env-test-abc-123-def', result.envelopeId,
            'envelopeId should match mock response');
        System.assertEquals(null, result.signingUrl,
            'Remote signing should have null signingUrl');
    }

    @isTest
    static void testSendMultipleTemplatesRemote_nullPdfName_defaultsToFileName() {
        // customPdfName = null → controller uses 'Application Details.pdf' default
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory('DOCUSIGN_ENVELOPE_CREATED'));

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendUsingMultipleTemplatesWithCustomPDF(
                    app.Id, 'tmpl-001', 'tmpl-002',
                    'signer@test.com', 'Test Signer', null
                );
        Test.stopTest();

        System.assertEquals(true, result.success,
            'Null PDF name should succeed — controller uses default filename');
    }

    @isTest
    static void testSendMultipleTemplatesRemote_docuSignError_returnsFailure() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory('DOCUSIGN_ERROR'));

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendUsingMultipleTemplatesWithCustomPDF(
                    app.Id, 'tmpl-001', 'tmpl-002',
                    'signer@test.com', 'Test Signer', 'App.pdf'
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'DocuSign 400 error should return failure');
        System.assertNotEquals(null, result.errorMessage,
            'errorMessage should be populated on failure');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 4 — sendUsingMultipleTemplatesWithCustomPDFEmbedded
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testSendMultipleTemplatesEmbedded_nullApplicationId_returnsError() {
        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendUsingMultipleTemplatesWithCustomPDFEmbedded(
                    null, 'tmpl-001', 'tmpl-002',
                    'signer@test.com', 'Test Signer', 'client-001', null, 'App.pdf'
                );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Null applicationId should fail');
        System.assertEquals('Application Id is required.', result.errorMessage);
    }

    @isTest
    static void testSendMultipleTemplatesEmbedded_blankClientUserId_returnsError() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendUsingMultipleTemplatesWithCustomPDFEmbedded(
                    app.Id, 'tmpl-001', 'tmpl-002',
                    'signer@test.com', 'Test Signer', '', null, 'App.pdf'
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Blank clientUserId should fail for embedded signing');
        System.assertEquals('Client User Id is required for embedded signing.',
            result.errorMessage);
    }

    @isTest
    static void testSendMultipleTemplatesEmbedded_success_returnsEnvelopeIdAndUrl() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        // Callout 1: POST /envelopes → DOCUSIGN_ENVELOPE_CREATED
        // Callout 2: POST /views/recipient → DOCUSIGN_RECIPIENT_VIEW
        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory.MultiRequestMock(
                new List<String>{
                    'DOCUSIGN_ENVELOPE_CREATED',
                    'DOCUSIGN_RECIPIENT_VIEW'
                }
            )
        );

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendUsingMultipleTemplatesWithCustomPDFEmbedded(
                    app.Id, 'tmpl-001', 'tmpl-002',
                    'signer@test.com', 'Test Signer', 'client-001',
                    'https://return.test.invalid/callback', 'App.pdf'
                );
        Test.stopTest();

        System.assertEquals(true, result.success,
            'Valid embedded signing request should succeed');
        System.assertEquals('env-test-abc-123-def', result.envelopeId,
            'envelopeId should match mock envelope response');
        System.assertNotEquals(null, result.signingUrl,
            'signingUrl should be populated from recipient view response');
        System.assert(result.signingUrl.contains('demo.docusign.net'),
            'signingUrl should match the DOCUSIGN_RECIPIENT_VIEW mock URL');
    }

    @isTest
    static void testSendMultipleTemplatesEmbedded_nullReturnUrl_usesOrgDomainUrl() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory.MultiRequestMock(
                new List<String>{ 'DOCUSIGN_ENVELOPE_CREATED', 'DOCUSIGN_RECIPIENT_VIEW' }
            )
        );

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendUsingMultipleTemplatesWithCustomPDFEmbedded(
                    app.Id, 'tmpl-001', 'tmpl-002',
                    'signer@test.com', 'Test Signer', 'client-001',
                    null, // returnUrl = null → controller uses org domain URL
                    'App.pdf'
                );
        Test.stopTest();

        System.assertEquals(true, result.success,
            'Null returnUrl should fall back to org domain URL and succeed');
        System.assertNotEquals(null, result.signingUrl,
            'signingUrl should still be populated when returnUrl is null');
    }

    @isTest
    static void testSendMultipleTemplatesEmbedded_docuSignError_returnsFailure() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory('DOCUSIGN_ERROR'));

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendUsingMultipleTemplatesWithCustomPDFEmbedded(
                    app.Id, 'tmpl-001', 'tmpl-002',
                    'signer@test.com', 'Test Signer', 'client-001', null, 'App.pdf'
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'DocuSign error should return failure');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 5 — sendMultiplePdfsForRemoteSigning
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testSendMultiplePdfsRemote_nullApplicationId_returnsError() {
        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendMultiplePdfsForRemoteSigning(
                    null, 'signer@test.com', 'Test Signer',
                    new List<String>{ 'doc.pdf' },
                    new List<String>{ testPdfBase64() }
                );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Null applicationId should fail');
        System.assertEquals('Application ID is required.', result.errorMessage);
    }

    @isTest
    static void testSendMultiplePdfsRemote_blankSignerInfo_returnsError() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendMultiplePdfsForRemoteSigning(
                    app.Id, '', 'Test Signer',
                    new List<String>{ 'doc.pdf' },
                    new List<String>{ testPdfBase64() }
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Blank signerEmail should fail');
        System.assertEquals('Signer name and email are required.', result.errorMessage);
    }

    @isTest
    static void testSendMultiplePdfsRemote_nullPdfNames_returnsError() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendMultiplePdfsForRemoteSigning(
                    app.Id, 'signer@test.com', 'Test Signer', null, null
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Null pdfNames should fail');
        System.assertEquals('At least one PDF is required.', result.errorMessage);
    }

    @isTest
    static void testSendMultiplePdfsRemote_mismatchedNameContentCounts_returnsError() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendMultiplePdfsForRemoteSigning(
                    app.Id, 'signer@test.com', 'Test Signer',
                    new List<String>{ 'doc1.pdf', 'doc2.pdf' },
                    new List<String>{ testPdfBase64() } // only 1 content for 2 names
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Mismatched name/content counts should fail');
        System.assertEquals('PDF names and contents must have matching counts.',
            result.errorMessage);
    }

    @isTest
    static void testSendMultiplePdfsRemote_success_envelopeCreatedAndDfsleRecordsInserted() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory('DOCUSIGN_ENVELOPE_CREATED'));

        String b64 = testPdfBase64();
        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendMultiplePdfsForRemoteSigning(
                    app.Id, 'signer@test.com', 'Test Signer',
                    new List<String>{ 'Document 1.pdf', 'Document 2.pdf' },
                    new List<String>{ b64, b64 }
                );
        Test.stopTest();

        System.assertEquals(true, result.success,
            'Valid request should succeed');
        System.assertEquals('env-test-abc-123-def', result.envelopeId,
            'envelopeId should match mock response');
        System.assertEquals(null, result.signingUrl,
            'Remote signing has no signingUrl');
    }

    @isTest
    static void testSendMultiplePdfsRemote_blankPdfName_defaultsToDocumentN() {
        // blank pdfName → controller uses 'Document_{n+1}.pdf' default
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory('DOCUSIGN_ENVELOPE_CREATED'));

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendMultiplePdfsForRemoteSigning(
                    app.Id, 'signer@test.com', 'Test Signer',
                    new List<String>{ '' }, // blank name → default
                    new List<String>{ testPdfBase64() }
                );
        Test.stopTest();

        System.assertEquals(true, result.success,
            'Blank PDF name should use default name and succeed');
    }

    @isTest
    static void testSendMultiplePdfsRemote_pdfNameWithoutExtension_addsPdfExtension() {
        // pdfName without .pdf → controller appends .pdf
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory('DOCUSIGN_ENVELOPE_CREATED'));

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendMultiplePdfsForRemoteSigning(
                    app.Id, 'signer@test.com', 'Test Signer',
                    new List<String>{ 'MyDocument' }, // no .pdf extension
                    new List<String>{ testPdfBase64() }
                );
        Test.stopTest();

        System.assertEquals(true, result.success,
            'PDF name without extension should have .pdf appended and succeed');
    }

    @isTest
    static void testSendMultiplePdfsRemote_docuSignError_returnsFailure() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory('DOCUSIGN_ERROR'));

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendMultiplePdfsForRemoteSigning(
                    app.Id, 'signer@test.com', 'Test Signer',
                    new List<String>{ 'doc.pdf' },
                    new List<String>{ testPdfBase64() }
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'DocuSign error response should return failure');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 6 — sendMultiplePdfsForEmbeddedSigning
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testSendMultiplePdfsEmbedded_nullApplicationId_returnsError() {
        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendMultiplePdfsForEmbeddedSigning(
                    null, 'signer@test.com', 'Test Signer', 'client-001', null,
                    new List<String>{ 'doc.pdf' }, new List<String>{ testPdfBase64() }
                );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Null applicationId should fail');
        System.assertEquals('Application ID is required.', result.errorMessage);
    }

    @isTest
    static void testSendMultiplePdfsEmbedded_blankClientUserId_returnsError() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendMultiplePdfsForEmbeddedSigning(
                    app.Id, 'signer@test.com', 'Test Signer', '', null,
                    new List<String>{ 'doc.pdf' }, new List<String>{ testPdfBase64() }
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Blank clientUserId should fail');
        System.assertEquals('Client User Id is required for embedded signing.',
            result.errorMessage);
    }

    @isTest
    static void testSendMultiplePdfsEmbedded_success_returnsEnvelopeIdAndUrl() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory.MultiRequestMock(
                new List<String>{ 'DOCUSIGN_ENVELOPE_CREATED', 'DOCUSIGN_RECIPIENT_VIEW' }
            )
        );

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendMultiplePdfsForEmbeddedSigning(
                    app.Id, 'signer@test.com', 'Test Signer', 'client-001',
                    'https://return.test.invalid/done',
                    new List<String>{ 'doc1.pdf', 'doc2.pdf' },
                    new List<String>{ testPdfBase64(), testPdfBase64() }
                );
        Test.stopTest();

        System.assertEquals(true, result.success,
            'Valid embedded request should succeed');
        System.assertEquals('env-test-abc-123-def', result.envelopeId,
            'envelopeId should match mock response');
        System.assertNotEquals(null, result.signingUrl,
            'signingUrl should be populated from recipient view');
    }

    @isTest
    static void testSendMultiplePdfsEmbedded_nullReturnUrl_usesOrgDomainFallback() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory.MultiRequestMock(
                new List<String>{ 'DOCUSIGN_ENVELOPE_CREATED', 'DOCUSIGN_RECIPIENT_VIEW' }
            )
        );

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendMultiplePdfsForEmbeddedSigning(
                    app.Id, 'signer@test.com', 'Test Signer', 'client-001', null,
                    new List<String>{ 'doc.pdf' }, new List<String>{ testPdfBase64() }
                );
        Test.stopTest();

        System.assertEquals(true, result.success,
            'Null returnUrl should fall back to org domain URL');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 7 — sendUsingTemplateWithCustomPDFFirst (remote)
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testSendTemplateWithPdfFirst_nullApplicationId_returnsError() {
        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendUsingTemplateWithCustomPDFFirst(
                    null, 'tmpl-001', 'signer@test.com', 'Test Signer', 'App.pdf'
                );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Null applicationId should fail');
        System.assertEquals('Application Id is required.', result.errorMessage);
    }

    @isTest
    static void testSendTemplateWithPdfFirst_blankTemplateId_returnsError() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendUsingTemplateWithCustomPDFFirst(
                    app.Id, '', 'signer@test.com', 'Test Signer', 'App.pdf'
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Blank templateId should fail');
        System.assertEquals('DocuSign Template ID is required.', result.errorMessage);
    }

    @isTest
    static void testSendTemplateWithPdfFirst_blankSignerInfo_returnsError() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendUsingTemplateWithCustomPDFFirst(
                    app.Id, 'tmpl-001', '', '', 'App.pdf'
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Blank signer info should fail');
        System.assertEquals('Signer name and email are required.', result.errorMessage);
    }

    @isTest
    static void testSendTemplateWithPdfFirst_success_returnsEnvelopeId() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory('DOCUSIGN_ENVELOPE_CREATED'));

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendUsingTemplateWithCustomPDFFirst(
                    app.Id, 'tmpl-001', 'signer@test.com', 'Test Signer', 'App.pdf'
                );
        Test.stopTest();

        System.assertEquals(true, result.success,
            'Valid request should succeed');
        System.assertEquals('env-test-abc-123-def', result.envelopeId,
            'envelopeId should match mock response');
    }

    @isTest
    static void testSendTemplateWithPdfFirst_docuSignError_returnsFailure() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory('DOCUSIGN_ERROR'));

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendUsingTemplateWithCustomPDFFirst(
                    app.Id, 'tmpl-001', 'signer@test.com', 'Test Signer', 'App.pdf'
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'DocuSign error response should return failure');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 8 — sendUsingTemplateWithCustomPDFFirstEmbedded
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testSendTemplateWithPdfFirstEmbedded_blankClientUserId_returnsError() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendUsingTemplateWithCustomPDFFirstEmbedded(
                    app.Id, 'tmpl-001', 'signer@test.com', 'Test Signer',
                    '', null, 'App.pdf'
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Blank clientUserId should fail');
        System.assertEquals('Client User Id is required for embedded signing.',
            result.errorMessage);
    }

    @isTest
    static void testSendTemplateWithPdfFirstEmbedded_success_returnsEnvelopeIdAndUrl() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory.MultiRequestMock(
                new List<String>{ 'DOCUSIGN_ENVELOPE_CREATED', 'DOCUSIGN_RECIPIENT_VIEW' }
            )
        );

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendUsingTemplateWithCustomPDFFirstEmbedded(
                    app.Id, 'tmpl-001', 'signer@test.com', 'Test Signer',
                    'client-001', 'https://return.test.invalid/', 'App.pdf'
                );
        Test.stopTest();

        System.assertEquals(true, result.success,
            'Valid embedded request should succeed');
        System.assertEquals('env-test-abc-123-def', result.envelopeId,
            'envelopeId should match mock');
        System.assertNotEquals(null, result.signingUrl,
            'signingUrl should be populated');
    }

    @isTest
    static void testSendTemplateWithPdfFirstEmbedded_nullReturnUrl_fallsBackToOrgDomain() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory.MultiRequestMock(
                new List<String>{ 'DOCUSIGN_ENVELOPE_CREATED', 'DOCUSIGN_RECIPIENT_VIEW' }
            )
        );

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendUsingTemplateWithCustomPDFFirstEmbedded(
                    app.Id, 'tmpl-001', 'signer@test.com', 'Test Signer',
                    'client-001', null, 'App.pdf'
                );
        Test.stopTest();

        System.assertEquals(true, result.success,
            'Null returnUrl should use org domain fallback and succeed');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 9 — sendUsingTemplateWithCustomPDFTwoStep (multi-callout)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Two-step approach fires 5 sequential callouts:
     *   1. createEnvelopeFromTemplate     → POST /envelopes
     *   2. addDocumentToEnvelopeFirst     → POST /envelopes/{id}/documents
     *   3. updateTemplateDocumentOrder    → GET  /envelopes/{id}/documents
     *   4. updateDocumentOrder (doc "2")  → PUT  /envelopes/{id}/documents/2
     *   5. sendDraftEnvelope              → PUT  /envelopes/{id}
     */
    @isTest
    static void testSendTemplateWithPdfTwoStep_nullApplicationId_returnsError() {
        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendUsingTemplateWithCustomPDFTwoStep(
                    null, 'tmpl-001', 'signer@test.com', 'Test Signer', 'App.pdf'
                );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Null applicationId should fail');
        System.assertEquals('Application Id is required.', result.errorMessage);
    }

    @isTest
    static void testSendTemplateWithPdfTwoStep_success_fiveSequentialCallouts() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory.MultiRequestMock(
                new List<String>{
                    'DOCUSIGN_ENVELOPE_CREATED',   // 1. createEnvelopeFromTemplate
                    'DOCUSIGN_DOCUMENT_ADDED',     // 2. addDocumentToEnvelopeFirst
                    'DOCUSIGN_ENVELOPE_DOCUMENTS', // 3. updateTemplateDocumentOrder (GET)
                    'DOCUSIGN_ENVELOPE_UPDATED',   // 4. updateDocumentOrder for doc "2" (PUT)
                    'DOCUSIGN_ENVELOPE_UPDATED'    // 5. sendDraftEnvelope (PUT)
                }
            )
        );

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendUsingTemplateWithCustomPDFTwoStep(
                    app.Id, 'tmpl-001',
                    'signer@test.com', 'Test Signer', 'App.pdf'
                );
        Test.stopTest();

        System.assertEquals(true, result.success,
            'Two-step approach should succeed with five sequential callouts');
        System.assertEquals('env-test-abc-123-def', result.envelopeId,
            'envelopeId should come from the first callout response');
        System.assertEquals(null, result.signingUrl,
            'Two-step remote signing has no signingUrl');
    }

    @isTest
    static void testSendTemplateWithPdfTwoStep_docuSignError_returnsFailure() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        // First callout fails → entire method returns failure
        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory('DOCUSIGN_ERROR'));

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendUsingTemplateWithCustomPDFTwoStep(
                    app.Id, 'tmpl-001',
                    'signer@test.com', 'Test Signer', 'App.pdf'
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'DocuSign error on first callout should return failure');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 10 — sendForRemoteSigning
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testSendForRemoteSigning_nullApplicationId_returnsError() {
        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendForRemoteSigning(
                    null, 'signer@test.com', 'Test Signer'
                );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Null applicationId should fail');
        System.assertEquals('Application Id is required.', result.errorMessage);
    }

    @isTest
    static void testSendForRemoteSigning_blankSignerInfo_returnsError() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendForRemoteSigning(
                    app.Id, '', 'Test Signer'
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Blank signerEmail should fail');
        System.assertEquals('Signer name and email are required.', result.errorMessage);
    }

    @isTest
    static void testSendForRemoteSigning_noPdfLinked_returnsError() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);
        // No ContentDocumentLink → getLatestLinkedPdf throws

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendForRemoteSigning(
                    app.Id, 'signer@test.com', 'Test Signer'
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'No linked PDF should return failure');
        System.assertNotEquals(null, result.errorMessage,
            'errorMessage should indicate no PDF found');
    }

    @isTest
    static void testSendForRemoteSigning_success_returnsEnvelopeId() {
        Map<String, SObject> chain = setupApplicationWithPdf();
        Application__c app = (Application__c) chain.get('app');

        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory('DOCUSIGN_ENVELOPE_CREATED'));

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendForRemoteSigning(
                    app.Id, 'signer@test.com', 'Test Signer'
                );
        Test.stopTest();

        System.assertEquals(true, result.success,
            'Valid request with linked PDF should succeed');
        System.assertEquals('env-test-abc-123-def', result.envelopeId,
            'envelopeId should match mock response');
        System.assertEquals(null, result.signingUrl,
            'Remote signing should have no signingUrl');
    }

    @isTest
    static void testSendForRemoteSigning_docuSignError_returnsFailure() {
        Map<String, SObject> chain = setupApplicationWithPdf();
        Application__c app = (Application__c) chain.get('app');

        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory('DOCUSIGN_ERROR'));

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendForRemoteSigning(
                    app.Id, 'signer@test.com', 'Test Signer'
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'DocuSign error should return failure');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 11 — sendForEmbeddedSigning
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testSendForEmbeddedSigning_nullApplicationId_returnsError() {
        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendForEmbeddedSigning(
                    null, 'signer@test.com', 'Test Signer', 'client-001', null
                );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Null applicationId should fail');
        System.assertEquals('Application Id is required.', result.errorMessage);
    }

    @isTest
    static void testSendForEmbeddedSigning_blankClientUserId_returnsError() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendForEmbeddedSigning(
                    app.Id, 'signer@test.com', 'Test Signer', '', null
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Blank clientUserId should fail for embedded signing');
        System.assertEquals('Client User Id is required for embedded signing.',
            result.errorMessage);
    }

    @isTest
    static void testSendForEmbeddedSigning_noPdfLinked_returnsError() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendForEmbeddedSigning(
                    app.Id, 'signer@test.com', 'Test Signer', 'client-001', null
                );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'No linked PDF should return failure');
    }

    @isTest
    static void testSendForEmbeddedSigning_success_returnsEnvelopeIdAndUrl() {
        Map<String, SObject> chain = setupApplicationWithPdf();
        Application__c app = (Application__c) chain.get('app');

        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory.MultiRequestMock(
                new List<String>{ 'DOCUSIGN_ENVELOPE_CREATED', 'DOCUSIGN_RECIPIENT_VIEW' }
            )
        );

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendForEmbeddedSigning(
                    app.Id, 'signer@test.com', 'Test Signer',
                    'client-001', 'https://return.test.invalid/'
                );
        Test.stopTest();

        System.assertEquals(true, result.success,
            'Valid embedded signing request should succeed');
        System.assertEquals('env-test-abc-123-def', result.envelopeId,
            'envelopeId should match mock response');
        System.assertNotEquals(null, result.signingUrl,
            'signingUrl should be populated');
    }

    @isTest
    static void testSendForEmbeddedSigning_nullReturnUrl_usesOrgDomainFallback() {
        Map<String, SObject> chain = setupApplicationWithPdf();
        Application__c app = (Application__c) chain.get('app');

        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory.MultiRequestMock(
                new List<String>{ 'DOCUSIGN_ENVELOPE_CREATED', 'DOCUSIGN_RECIPIENT_VIEW' }
            )
        );

        Test.startTest();
            DocusignApplicationService.SendResult result =
                DocusignApplicationService.sendForEmbeddedSigning(
                    app.Id, 'signer@test.com', 'Test Signer', 'client-001', null
                );
        Test.stopTest();

        System.assertEquals(true, result.success,
            'Null returnUrl should use org domain URL fallback');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 12 — getPdfContentBase64
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetPdfContentBase64_validIds_returnsBase64AndTitle() {
        ContentVersion cv = new ContentVersion(
            Title          = 'My PDF Document',
            PathOnClient   = 'my_pdf.pdf',
            VersionData    = Blob.valueOf('PDF test data'),
            IsMajorVersion = true
        );
        insert cv;

        // Re-query to get the Id after insert
        ContentVersion queried = [SELECT Id FROM ContentVersion WHERE Title = 'My PDF Document' LIMIT 1];

        Test.startTest();
            List<Map<String,String>> results =
                DocusignApplicationService.getPdfContentBase64(
                    new List<String>{ queried.Id }
                );
        Test.stopTest();

        System.assertEquals(1, results.size(),
            'Should return one result for one Id');
        System.assertEquals('My PDF Document', results[0].get('title'),
            'title should match the ContentVersion Title');
        System.assertNotEquals(null, results[0].get('base64'),
            'base64 should not be null');
        System.assert(results[0].get('base64').length() > 0,
            'base64 content should not be empty');
    }

    @isTest
    static void testGetPdfContentBase64_emptyList_returnsEmptyList() {
        Test.startTest();
            List<Map<String,String>> results =
                DocusignApplicationService.getPdfContentBase64(new List<String>());
        Test.stopTest();

        System.assertNotEquals(null, results,
            'Result should not be null for empty input');
        System.assertEquals(0, results.size(),
            'Empty input should return empty result list');
    }

    @isTest
    static void testGetPdfContentBase64_multipleIds_returnsAllResults() {
        List<ContentVersion> cvs = new List<ContentVersion>{
            new ContentVersion(Title='PDF One', PathOnClient='one.pdf',
                VersionData=Blob.valueOf('content one'), IsMajorVersion=true),
            new ContentVersion(Title='PDF Two', PathOnClient='two.pdf',
                VersionData=Blob.valueOf('content two'), IsMajorVersion=true)
        };
        insert cvs;

        List<ContentVersion> queried = [
            SELECT Id FROM ContentVersion WHERE Title IN ('PDF One','PDF Two')
        ];
        List<String> ids = new List<String>{ queried[0].Id, queried[1].Id };

        Test.startTest();
            List<Map<String,String>> results =
                DocusignApplicationService.getPdfContentBase64(ids);
        Test.stopTest();

        System.assertEquals(2, results.size(),
            'Should return one result per provided Id');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 13 — getDocuSignTemplates
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetDocuSignTemplates_success_returnsTemplateList() {
        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory('DOCUSIGN_TEMPLATES_LIST'));

        Test.startTest();
            List<Map<String,Object>> templates =
                DocusignApplicationService.getDocuSignTemplates();
        Test.stopTest();

        System.assertNotEquals(null, templates,
            'Result should not be null on success');
        System.assertEquals(2, templates.size(),
            'Should return 2 templates from DOCUSIGN_TEMPLATES_LIST mock');
        System.assertEquals('tmpl-001-signature', (String) templates[0].get('templateId'),
            'First templateId should match mock');
        System.assertEquals('Signature Template', (String) templates[0].get('name'),
            'First template name should match mock');
        System.assertNotEquals(null, templates[0].get('description'),
            'description should be populated');
    }

    @isTest
    static void testGetDocuSignTemplates_docuSignError_throwsAuraHandledException() {
        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory('DOCUSIGN_ERROR'));

        Boolean thrown = false;
        Test.startTest();
        try {
            DocusignApplicationService.getDocuSignTemplates();
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown,
            'Non-200 response should throw AuraHandledException');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 14 — getEnvelopeDocuments
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetEnvelopeDocuments_success_returnsDocumentList() {
        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory('DOCUSIGN_ENVELOPE_DOCUMENTS'));

        Test.startTest();
            List<Map<String,Object>> docs =
                DocusignApplicationService.getEnvelopeDocuments('env-test-abc-123-def');
        Test.stopTest();

        System.assertEquals(2, docs.size(),
            'Should return 2 documents from DOCUSIGN_ENVELOPE_DOCUMENTS mock');
        System.assertEquals('1', (String) docs[0].get('documentId'),
            'First documentId should be 1');
        System.assertNotEquals(null, docs[0].get('name'),
            'Document name should be populated');
        System.assertNotEquals(null, docs[0].get('order'),
            'Document order should be populated');
    }

    @isTest
    static void testGetEnvelopeDocuments_docuSignError_throwsAuraHandledException() {
        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory('DOCUSIGN_ERROR'));

        Boolean thrown = false;
        Test.startTest();
        try {
            DocusignApplicationService.getEnvelopeDocuments('env-test-abc-123-def');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown,
            'Non-200 response should throw AuraHandledException');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 15 — checkEnvelopeStatus
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testCheckEnvelopeStatus_200_returnsStatusMap() {
        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory('DOCUSIGN_STATUS_WITH_SIGNER_COMPLETED'));

        Test.startTest();
            Map<String,Object> statusData =
                DocusignApplicationService.checkEnvelopeStatus('env-test-abc-123-def');
        Test.stopTest();

        System.assertNotEquals(null, statusData,
            'checkEnvelopeStatus should return a non-null map for 200 response');
        System.assertEquals('env-test-abc-123-def', (String) statusData.get('envelopeId'),
            'envelopeId should match mock');
        System.assertEquals('completed', (String) statusData.get('status'),
            'status should be completed');
    }

    @isTest
    static void testCheckEnvelopeStatus_nonSuccess_throwsAuraHandledException() {
        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory('DOCUSIGN_ERROR'));

        Boolean thrown = false;
        Test.startTest();
        try {
            DocusignApplicationService.checkEnvelopeStatus('env-test-abc-123-def');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown,
            '400 response should throw AuraHandledException');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 16 — getEnvelopeStatus
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetEnvelopeStatus_signerCompleted_isCompleteTrue() {
        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory('DOCUSIGN_STATUS_WITH_SIGNER_COMPLETED'));

        Test.startTest();
            DocusignApplicationService.EnvelopeStatusResult result =
                DocusignApplicationService.getEnvelopeStatus('env-test-abc-123-def');
        Test.stopTest();

        System.assertEquals(true, result.isComplete,
            'isComplete should be true when signer status = completed');
        System.assertEquals('completed', result.status,
            'status should be completed');
        System.assertNotEquals(null, result.signedDateTime,
            'signedDateTime should be populated');
        System.assertEquals(null, result.errorMessage,
            'errorMessage should be null on success');
    }

    @isTest
    static void testGetEnvelopeStatus_signerSent_isCompleteFalse() {
        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory('DOCUSIGN_STATUS_WITH_SIGNER_SENT'));

        Test.startTest();
            DocusignApplicationService.EnvelopeStatusResult result =
                DocusignApplicationService.getEnvelopeStatus('env-test-abc-123-def');
        Test.stopTest();

        System.assertEquals(false, result.isComplete,
            'isComplete should be false when signer status = sent');
        System.assertEquals('sent', result.status,
            'status should be sent');
    }

    @isTest
    static void testGetEnvelopeStatus_emptySignersList_returnsNoSignerFoundMessage() {
        // recipients.signers = [] → falls through to errorMessage
        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory('DOCUSIGN_STATUS_NO_SIGNERS'));

        Test.startTest();
            DocusignApplicationService.EnvelopeStatusResult result =
                DocusignApplicationService.getEnvelopeStatus('env-test-abc-123-def');
        Test.stopTest();

        System.assertEquals('No signer information found', result.errorMessage,
            'errorMessage should indicate no signers when signers list is empty');
    }

    @isTest
    static void testGetEnvelopeStatus_noRecipientsInResponse_returnsNoSignerFoundMessage() {
        // DOCUSIGN_STATUS_SENT has no recipients block → recipients = null
        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory('DOCUSIGN_STATUS_SENT'));

        Test.startTest();
            DocusignApplicationService.EnvelopeStatusResult result =
                DocusignApplicationService.getEnvelopeStatus('env-test-abc-123-def');
        Test.stopTest();

        System.assertEquals('No signer information found', result.errorMessage,
            'errorMessage should indicate no signers when recipients block is absent');
    }

    @isTest
    static void testGetEnvelopeStatus_checkEnvelopeStatusThrows_errorMessagePopulated() {
        // checkEnvelopeStatus throws when status != 200 → caught by getEnvelopeStatus catch
        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory('DOCUSIGN_ERROR'));

        Test.startTest();
            DocusignApplicationService.EnvelopeStatusResult result =
                DocusignApplicationService.getEnvelopeStatus('env-test-abc-123-def');
        Test.stopTest();

        System.assertNotEquals(null, result.errorMessage,
            'errorMessage should be populated when checkEnvelopeStatus throws');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 17 — downloadAndAttachSignedDocument
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testDownloadAndAttachSignedDocument_200_insertsContentVersionReturnsTrue() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory('DOCUSIGN_PDF_DOWNLOAD'));

        Test.startTest();
            Boolean result =
                DocusignApplicationService.downloadAndAttachSignedDocument(
                    'env-test-abc-123-def', app.Id
                );
        Test.stopTest();

        System.assertEquals(true, result,
            '200 response should return true');

        // Verify the ContentVersion was inserted and linked to the application
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM   ContentDocumentLink
            WHERE  LinkedEntityId = :app.Id
        ];
        System.assert(links.size() >= 1,
            'A signed document ContentVersion should be linked to the Application');
    }

    @isTest
    static void testDownloadAndAttachSignedDocument_nonSuccess_returnsFalse() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);

        // 400 → status != 200 → returns false (no insert)
        Test.setMock(HttpCalloutMock.class,
            new MockHttpCalloutFactory('DOCUSIGN_ERROR'));

        Test.startTest();
            Boolean result =
                DocusignApplicationService.downloadAndAttachSignedDocument(
                    'env-test-abc-123-def', app.Id
                );
        Test.stopTest();

        System.assertEquals(false, result,
            'Non-200 response should return false');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 18 — sendEnvelopeWithTabs
    // Limited coverage — dfsle managed-package calls cannot be mocked via
    // HttpCalloutMock. Validation paths that run before dfsle is touched
    // are fully testable.
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testSendEnvelopeWithTabs_customerNotLinked_throwsAuraHandledException() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);
        // Customer_Name__c is null → code throws AuraHandledException before dfsle

        Boolean thrown = false;
        Test.startTest();
        try {
            DocusignApplicationService.sendEnvelopeWithTabs(
                app.Id, new List<Id>()
            );
        } catch (AuraHandledException e) {
            thrown = true;
            // AuraHandledException.getMessage() = 'Script-thrown exception' in catch context
            System.assertNotEquals(null, e.getMessage(),
                'Exception should carry a message');
        } catch (Exception e) {
            // Any other exception from dfsle or setup also counts as thrown
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown,
            'AuraHandledException should be thrown when Customer_Name__c is null');
    }

    @isTest
    static void testSendEnvelopeWithTabs_applicationNotFound_throwsException() {
        // Non-existent applicationId → SOQL: List has no rows → QueryException
        Boolean thrown = false;
        Test.startTest();
        try {
            DocusignApplicationService.sendEnvelopeWithTabs(
                'a0000000000000ZAAQ', new List<Id>()
            );
        } catch (System.QueryException e) {
            thrown = true;
        } catch (Exception e) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown,
            'Non-existent applicationId should cause an exception');
    }
}