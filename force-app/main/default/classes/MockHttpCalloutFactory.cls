/**
 * MockHttpCalloutFactory
 * ──────────────────────────────────────────────────────────────────────────────
 * Single, centralised HttpCalloutMock for ALL external HTTP callouts made by
 * the A-Protect Dealer Portal.  Every test class that exercises code with an
 * HTTP callout registers this mock via:
 *
 *   Test.setMock(HttpCalloutMock.class, new MockHttpCalloutFactory('SCENARIO'));
 *
 * For methods that make multiple sequential callouts, use the inner class:
 *
 *   Test.setMock(HttpCalloutMock.class,
 *       new MockHttpCalloutFactory.MultiRequestMock(
 *           new List<String>{ 'SCENARIO_1', 'SCENARIO_2', ... }
 *       )
 *   );
 *
 * Supported scenarios
 * ───────────────────
 * VIN Decoder (NHTSA API):
 *   VIN_SUCCESS          – 200, valid decoded vehicle data (Honda Civic 2021)
 *   VIN_NOT_FOUND        – 200, zero results (valid HTTP but no data)
 *   VIN_ERROR            – 500, server error
 *   VIN_INVALID          – 400, bad request
 *
 * Moneris (card payment):
 *   MONERIS_SUCCESS      – 200, paymentStatus = SUCCEEDED
 *   MONERIS_DECLINED     – 200, paymentStatus = DECLINED
 *   MONERIS_ERROR        – 500, server error body
 *   MONERIS_AUTH_SUCCESS – 200, OAuth access_token response
 *
 * DocuSign (envelope + signing):
 *   DOCUSIGN_ENVELOPE_CREATED         – 201, envelope created with envelopeId
 *   DOCUSIGN_STATUS_COMPLETED         – 200, envelope status = completed (no recipients)
 *   DOCUSIGN_STATUS_SENT              – 200, envelope status = sent (no recipients)
 *   DOCUSIGN_ERROR                    – 400, API error with message field
 *   DOCUSIGN_RECIPIENT_VIEW           – 200, embedded signing URL returned
 *   DOCUSIGN_TEMPLATES_LIST           – 200, two templates in envelopeTemplates list
 *   DOCUSIGN_ENVELOPE_DOCUMENTS       – 200, two docs in envelopeDocuments list (ids 1 and 2)
 *   DOCUSIGN_DOCUMENT_ADDED           – 200, document added to envelope (status created)
 *   DOCUSIGN_ENVELOPE_UPDATED         – 200, envelope updated / sent (status sent)
 *   DOCUSIGN_PDF_DOWNLOAD             – 200, PDF binary for combined document download
 *   DOCUSIGN_STATUS_WITH_SIGNER_COMPLETED – 200, recipients.signers[0].status = completed
 *   DOCUSIGN_STATUS_WITH_SIGNER_SENT      – 200, recipients.signers[0].status = sent
 *   DOCUSIGN_STATUS_NO_SIGNERS            – 200, recipients.signers = [] (empty)
 *
 * Design rules:
 *   • This class is @isTest — it never ships to production.
 *   • Responses are realistic: same JSON keys the production classes parse.
 *   • Unknown scenarios throw an explicit exception to catch typos early.
 *   • MultiRequestMock dispatches scenarios in order; repeats last for overflow.
 */
@isTest
global class MockHttpCalloutFactory implements HttpCalloutMock {

    private final String scenario;

    global MockHttpCalloutFactory(String scenario) {
        this.scenario = scenario;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // DISPATCH
    // ─────────────────────────────────────────────────────────────────────────────

    global HTTPResponse respond(HTTPRequest req) {
        switch on scenario {

            // ── VIN DECODER ──────────────────────────────────────────────────────
            when 'VIN_SUCCESS'      { return vinSuccess(); }
            when 'VIN_NOT_FOUND'    { return vinNotFound(); }
            when 'VIN_ERROR'        { return serverError('VIN decoder service unavailable'); }
            when 'VIN_INVALID'      { return badRequest('Invalid VIN format'); }

            // ── MONERIS ──────────────────────────────────────────────────────────
            when 'MONERIS_SUCCESS'      { return monerisSuccess(); }
            when 'MONERIS_DECLINED'     { return monerisDeclined(); }
            when 'MONERIS_ERROR'        { return serverError('Moneris gateway error'); }
            when 'MONERIS_AUTH_SUCCESS' { return monerisAuthSuccess(); }

            // ── DOCUSIGN — ENVELOPE ──────────────────────────────────────────────
            when 'DOCUSIGN_ENVELOPE_CREATED'  { return docuSignEnvelopeCreated(); }
            when 'DOCUSIGN_STATUS_COMPLETED'  { return docuSignStatusCompleted(); }
            when 'DOCUSIGN_STATUS_SENT'       { return docuSignStatusSent(); }
            when 'DOCUSIGN_ERROR'             { return docuSignError(); }

            // ── DOCUSIGN — SIGNING & RECIPIENT VIEW ──────────────────────────────
            when 'DOCUSIGN_RECIPIENT_VIEW'    { return docuSignRecipientView(); }

            // ── DOCUSIGN — TEMPLATES ─────────────────────────────────────────────
            when 'DOCUSIGN_TEMPLATES_LIST'    { return docuSignTemplatesList(); }

            // ── DOCUSIGN — DOCUMENTS ─────────────────────────────────────────────
            when 'DOCUSIGN_ENVELOPE_DOCUMENTS'{ return docuSignEnvelopeDocuments(); }
            when 'DOCUSIGN_DOCUMENT_ADDED'    { return docuSignDocumentAdded(); }
            when 'DOCUSIGN_ENVELOPE_UPDATED'  { return docuSignEnvelopeUpdated(); }
            when 'DOCUSIGN_PDF_DOWNLOAD'      { return docuSignPdfDownload(); }

            // ── DOCUSIGN — STATUS WITH SIGNER INFO ───────────────────────────────
            when 'DOCUSIGN_STATUS_WITH_SIGNER_COMPLETED' { return docuSignStatusWithSignerCompleted(); }
            when 'DOCUSIGN_STATUS_WITH_SIGNER_SENT'      { return docuSignStatusWithSignerSent(); }
            when 'DOCUSIGN_STATUS_NO_SIGNERS'             { return docuSignStatusNoSigners(); }

            // ── UNKNOWN ──────────────────────────────────────────────────────────
            when else {
                throw new MockHttpCalloutFactoryException(
                    'MockHttpCalloutFactory: unrecognised scenario [' + scenario + ']. '
                    + 'Add it to MockHttpCalloutFactory.respond() before using it in a test.'
                );
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // VIN DECODER RESPONSES
    // ─────────────────────────────────────────────────────────────────────────────

    private static HTTPResponse vinSuccess() {
        String body =
            '{'
            + '"Count": 7,'
            + '"Message": "Results returned successfully",'
            + '"SearchCriteria": "VIN:1HGBH41JXMN109186",'
            + '"Results": ['
            +   '{"VariableId": 26, "Variable": "Make",        "Value": "HONDA",             "VariableName": "Make"},'
            +   '{"VariableId": 28, "Variable": "Model",       "Value": "CIVIC",             "VariableName": "Model"},'
            +   '{"VariableId": 29, "Variable": "Model Year",  "Value": "2021",              "VariableName": "Model Year"},'
            +   '{"VariableId": 30, "Variable": "Trim",        "Value": "Sport",             "VariableName": "Trim"},'
            +   '{"VariableId":  5, "Variable": "Body Class",  "Value": "Sedan/Saloon",      "VariableName": "Body Class"},'
            +   '{"VariableId": 27, "Variable": "Manufacturer Name", "Value": "HONDA OF AMERICA MFG., INC.", "VariableName": "Manufacturer Name"},'
            +   '{"VariableId":  2, "Variable": "Vehicle Type","Value": "PASSENGER CAR",     "VariableName": "Vehicle Type"}'
            + ']'
            + '}';
        return buildResponse(200, body);
    }

    private static HTTPResponse vinNotFound() {
        String body =
            '{'
            + '"Count": 0,'
            + '"Message": "Results returned successfully",'
            + '"SearchCriteria": "VIN:INVALID123456789",'
            + '"Results": []'
            + '}';
        return buildResponse(200, body);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // MONERIS RESPONSES
    // ─────────────────────────────────────────────────────────────────────────────

    private static HTTPResponse monerisSuccess() {
        String body =
            '{'
            + '"paymentId":           "pay-test-success-001",'
            + '"merchantId":          "store_test_001",'
            + '"orderId":             "ord-test-001",'
            + '"invoiceNumber":       "INV-TEST-001",'
            + '"paymentStatus":       "SUCCEEDED",'
            + '"transactionDateTime": "' + String.valueOf(DateTime.now()) + '",'
            + '"createdAt":           "' + String.valueOf(DateTime.now()) + '",'
            + '"amount":              {"value": 1500.00, "currencyCode": "CAD"},'
            + '"authorizedAmount":    {"value": 1500.00, "currencyCode": "CAD"},'
            + '"transactionDetails":  {'
            +   '"transactionUniqueId": "txn-unique-001",'
            +   '"isoResponseCode":     "00",'
            +   '"authorizationCode":   "654321",'
            +   '"responseCode":        "027",'
            +   '"message":             "APPROVED"'
            + '},'
            + '"success": true'
            + '}';
        return buildResponse(200, body);
    }

    private static HTTPResponse monerisDeclined() {
        String body =
            '{'
            + '"paymentId":     "pay-test-declined-001",'
            + '"merchantId":    "store_test_001",'
            + '"orderId":       "ord-test-002",'
            + '"paymentStatus": "DECLINED",'
            + '"transactionDetails": {'
            +   '"isoResponseCode": "05",'
            +   '"responseCode":    "481",'
            +   '"message":         "DECLINED"'
            + '},'
            + '"success":       false,'
            + '"errorMessage":  "Card declined by issuer"'
            + '}';
        return buildResponse(200, body);
    }

    private static HTTPResponse monerisAuthSuccess() {
        String body =
            '{'
            + '"access_token": "mock-moneris-bearer-token-abc123",'
            + '"token_type":   "Bearer",'
            + '"expires_in":   3600'
            + '}';
        return buildResponse(200, body);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // DOCUSIGN — EXISTING ENVELOPE RESPONSES
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * 201 — Envelope successfully created (remote signing, template, multi-PDF etc.).
     * Any DocusignApplicationService method that POSTs to /envelopes and parses
     * envelopeId / status / statusDateTime uses this scenario.
     */
    private static HTTPResponse docuSignEnvelopeCreated() {
        String body =
            '{'
            + '"envelopeId":       "env-test-abc-123-def",'
            + '"uri":              "/envelopes/env-test-abc-123-def",'
            + '"statusDateTime":   "' + String.valueOf(DateTime.now()) + '",'
            + '"status":           "sent"'
            + '}';
        return buildResponse(201, body);
    }

    /**
     * 200 — Envelope status completed (no recipients block).
     * Used by checkEnvelopeStatus tests that don't need signer detail.
     */
    private static HTTPResponse docuSignStatusCompleted() {
        String body =
            '{'
            + '"envelopeId":         "env-test-abc-123-def",'
            + '"status":             "completed",'
            + '"completedDateTime":  "' + String.valueOf(DateTime.now()) + '",'
            + '"sentDateTime":       "' + String.valueOf(DateTime.now().addMinutes(-30)) + '",'
            + '"statusChangedDateTime": "' + String.valueOf(DateTime.now()) + '"'
            + '}';
        return buildResponse(200, body);
    }

    /**
     * 200 — Envelope sent but not signed (no recipients block).
     * Used by checkEnvelopeStatus / getEnvelopeStatus "no recipients" path.
     */
    private static HTTPResponse docuSignStatusSent() {
        String body =
            '{'
            + '"envelopeId": "env-test-abc-123-def",'
            + '"status":     "sent",'
            + '"sentDateTime": "' + String.valueOf(DateTime.now().addMinutes(-10)) + '"'
            + '}';
        return buildResponse(200, body);
    }

    /**
     * 400 — DocuSign API validation error.
     * Has a parseable "message" field so the controller's JSON error-parse branch runs.
     */
    private static HTTPResponse docuSignError() {
        String body =
            '{'
            + '"errorCode": "INVALID_REQUEST_BODY",'
            + '"message":   "The request body is missing or improperly formatted."'
            + '}';
        return buildResponse(400, body);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // DOCUSIGN — NEW: RECIPIENT VIEW (embedded signing URL)
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * 200 — Recipient view created; returns the embedded signing URL.
     * DocusignApplicationService.createRecipientView() parses responseBody.get('url').
     * Used by all embedded-signing methods (sendForEmbeddedSigning,
     * sendMultiplePdfsForEmbeddedSigning, sendUsingMultipleTemplatesWithCustomPDFEmbedded, etc.).
     */
    private static HTTPResponse docuSignRecipientView() {
        String body =
            '{'
            + '"url": "https://demo.docusign.net/Signing/v2/MTRedeem/mock-signing-token-abc123?authType=none"'
            + '}';
        return buildResponse(200, body);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // DOCUSIGN — NEW: TEMPLATES LIST
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * 200 — Returns two templates in the envelopeTemplates array.
     * DocusignApplicationService.getDocuSignTemplates() parses envelopeTemplates.
     */
    private static HTTPResponse docuSignTemplatesList() {
        String body =
            '{'
            + '"envelopeTemplates": ['
            +   '{'
            +     '"templateId":   "tmpl-001-signature",'
            +     '"name":         "Signature Template",'
            +     '"description":  "Main signature and terms template"'
            +   '},'
            +   '{'
            +     '"templateId":   "tmpl-002-terms",'
            +     '"name":         "Terms and Conditions",'
            +     '"description":  "Terms and conditions document"'
            +   '}'
            + ']'
            + '}';
        return buildResponse(200, body);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // DOCUSIGN — NEW: ENVELOPE DOCUMENTS
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * 200 — Returns two documents (ids "1" and "2") in envelopeDocuments.
     *
     * Used by:
     *   • getEnvelopeDocuments()       — parses the list for the LWC
     *   • updateTemplateDocumentOrder()— skips doc "1", processes doc "2" via
     *                                    updateDocumentOrder() (triggers a PUT callout)
     *
     * IMPORTANT: doc id "1" is skipped by the controller (custom PDF placeholder).
     * Doc id "2" triggers an updateDocumentOrder() PUT callout. Tests using
     * MultiRequestMock for sendUsingTemplateWithCustomPDFTwoStep must therefore
     * include a DOCUSIGN_ENVELOPE_UPDATED response after this one.
     */
    private static HTTPResponse docuSignEnvelopeDocuments() {
        String body =
            '{'
            + '"envelopeDocuments": ['
            +   '{'
            +     '"documentId": "1",'
            +     '"name":       "Application Details.pdf",'
            +     '"type":       "content",'
            +     '"order":      "1"'
            +   '},'
            +   '{'
            +     '"documentId": "2",'
            +     '"name":       "Template Document.pdf",'
            +     '"type":       "content",'
            +     '"order":      "2"'
            +   '}'
            + ']'
            + '}';
        return buildResponse(200, body);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // DOCUSIGN — NEW: DOCUMENT ADDED TO ENVELOPE
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * 200 — Custom PDF added to draft envelope successfully.
     * Used by addDocumentToEnvelopeFirst() in the two-step approach.
     */
    private static HTTPResponse docuSignDocumentAdded() {
        String body =
            '{'
            + '"envelopeId": "env-test-abc-123-def",'
            + '"status":     "created"'
            + '}';
        return buildResponse(200, body);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // DOCUSIGN — NEW: ENVELOPE UPDATED (PUT responses)
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * 200 — Envelope successfully updated (status changed to sent, or doc order updated).
     *
     * Used by:
     *   • sendDraftEnvelope()  — PUT /envelopes/{id}
     *   • updateDocumentOrder()— PUT /envelopes/{id}/documents/{docId}
     *
     * Both methods check statusCode >= 300; this 200 passes both checks.
     */
    private static HTTPResponse docuSignEnvelopeUpdated() {
        String body =
            '{'
            + '"envelopeId": "env-test-abc-123-def",'
            + '"status":     "sent"'
            + '}';
        return buildResponse(200, body);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // DOCUSIGN — NEW: PDF DOCUMENT DOWNLOAD (combined signed document)
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * 200 — Combined signed PDF returned as binary.
     * downloadAndAttachSignedDocument() calls getBodyAsBlob() on this response
     * to create a ContentVersion. Content-Type is application/pdf.
     */
    private static HTTPResponse docuSignPdfDownload() {
        HTTPResponse res = new HTTPResponse();
        res.setStatusCode(200);
        res.setHeader('Content-Type', 'application/pdf');
        // Use setBody (string) — getBodyAsBlob() works on string-backed responses
        res.setBody('%PDF-1.4 mock signed document content for testing purposes only');
        return res;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // DOCUSIGN — NEW: ENVELOPE STATUS WITH SIGNER DETAIL
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * 200 — Envelope status with recipients.signers[0].status = completed.
     * DocusignApplicationService.getEnvelopeStatus() → result.isComplete = true.
     */
    private static HTTPResponse docuSignStatusWithSignerCompleted() {
        String body =
            '{'
            + '"envelopeId": "env-test-abc-123-def",'
            + '"status":     "completed",'
            + '"recipients": {'
            +   '"signers": ['
            +     '{'
            +       '"status":          "completed",'
            +       '"signedDateTime":  "2024-06-15T10:30:00.000Z",'
            +       '"name":            "Test Signer",'
            +       '"email":           "signer@test.invalid",'
            +       '"recipientId":     "1"'
            +     '}'
            +   ']'
            + '}'
            + '}';
        return buildResponse(200, body);
    }

    /**
     * 200 — Envelope status with recipients.signers[0].status = sent (not yet signed).
     * DocusignApplicationService.getEnvelopeStatus() → result.isComplete = false.
     */
    private static HTTPResponse docuSignStatusWithSignerSent() {
        String body =
            '{'
            + '"envelopeId": "env-test-abc-123-def",'
            + '"status":     "sent",'
            + '"recipients": {'
            +   '"signers": ['
            +     '{'
            +       '"status":      "sent",'
            +       '"name":        "Test Signer",'
            +       '"email":       "signer@test.invalid",'
            +       '"recipientId": "1"'
            +     '}'
            +   ']'
            + '}'
            + '}';
        return buildResponse(200, body);
    }

    /**
     * 200 — Envelope status with recipients.signers = [] (empty list).
     * DocusignApplicationService.getEnvelopeStatus() falls through to
     * result.errorMessage = 'No signer information found'.
     */
    private static HTTPResponse docuSignStatusNoSigners() {
        String body =
            '{'
            + '"envelopeId": "env-test-abc-123-def",'
            + '"status":     "sent",'
            + '"recipients": {'
            +   '"signers": []'
            + '}'
            + '}';
        return buildResponse(200, body);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // GENERIC RESPONSES
    // ─────────────────────────────────────────────────────────────────────────────

    private static HTTPResponse serverError(String message) {
        String body = '{"error": "Internal Server Error", "message": "' + message + '"}';
        return buildResponse(500, body);
    }

    private static HTTPResponse badRequest(String message) {
        String body = '{"error": "Bad Request", "message": "' + message + '"}';
        return buildResponse(400, body);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // BUILDER HELPER
    // ─────────────────────────────────────────────────────────────────────────────

    private static HTTPResponse buildResponse(Integer statusCode, String body) {
        HTTPResponse res = new HTTPResponse();
        res.setStatusCode(statusCode);
        res.setHeader('Content-Type', 'application/json');
        res.setBody(body);
        return res;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // MULTI-REQUEST MOCK
    // Used when a single @AuraEnabled method makes multiple sequential HTTP calls.
    //
    // Usage:
    //   Test.setMock(HttpCalloutMock.class,
    //       new MockHttpCalloutFactory.MultiRequestMock(
    //           new List<String>{
    //               'DOCUSIGN_ENVELOPE_CREATED',   // 1st callout
    //               'DOCUSIGN_DOCUMENT_ADDED',     // 2nd callout
    //               'DOCUSIGN_ENVELOPE_DOCUMENTS', // 3rd callout
    //               'DOCUSIGN_ENVELOPE_UPDATED',   // 4th callout
    //               'DOCUSIGN_ENVELOPE_UPDATED'    // 5th callout
    //           }
    //       )
    //   );
    //
    // If more callouts are made than scenarios provided, the last scenario repeats.
    // ─────────────────────────────────────────────────────────────────────────────

    global class MultiRequestMock implements HttpCalloutMock {
        private final List<String> scenarios;
        private Integer callIndex = 0;

        global MultiRequestMock(List<String> orderedScenarios) {
            this.scenarios = orderedScenarios;
        }

        global HTTPResponse respond(HTTPRequest req) {
            String scenario = callIndex < scenarios.size()
                ? scenarios[callIndex]
                : scenarios[scenarios.size() - 1]; // repeat last if overrun
            callIndex++;
            return new MockHttpCalloutFactory(scenario).respond(req);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // EXCEPTION
    // ─────────────────────────────────────────────────────────────────────────────

    public class MockHttpCalloutFactoryException extends Exception {}
}