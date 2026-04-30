public with sharing class DocusignApplicationService {

    private static final String NAMED_CREDENTIAL = 'DocuSignNew';
    
    // Consider making this configurable via Custom Settings or Custom Metadata
    private static String accountId() {
        return '8398ea20-1742-4614-9574-911f869e4ee7';
    }

    public class SendResult {
        @AuraEnabled public String envelopeId;
        @AuraEnabled public String signingUrl;
        @AuraEnabled public Boolean success;
        @AuraEnabled public String errorMessage;
        
        public SendResult(String envId, String url) { 
            this.envelopeId = envId; 
            this.signingUrl = url; 
            this.success = true;
        }
        
        public SendResult(String errorMsg) {
            this.success = false;
            this.errorMessage = errorMsg;
        }
    }

    public class EnvelopeStatusResult {
        @AuraEnabled public String status;
        @AuraEnabled public String signedDateTime;
        @AuraEnabled public Boolean isComplete;
        @AuraEnabled public String errorMessage;
    }

    // ============================================================================
    // MULTIPLE TEMPLATES METHODS (NEW - Custom PDF + Template 1 + Template 2)
    // ============================================================================

    @AuraEnabled(cacheable=false)
    public static SendResult sendUsingMultipleTemplatesWithCustomPDF(
        Id applicationId, 
        String signatureTemplateId,        // Template 1: Has signatures
        String termsTemplateId,            // Template 2: Terms & conditions
        String signerEmail, 
        String signerName,
        String customPdfName
    ) {
        try {
            // Validate inputs
            if (applicationId == null) {
                return new SendResult('Application Id is required.');
            }
            if (String.isBlank(signatureTemplateId)) {
                return new SendResult('Signature Template ID is required.');
            }
            if (String.isBlank(termsTemplateId)) {
                return new SendResult('Terms Template ID is required.');
            }
            if (String.isBlank(signerEmail) || String.isBlank(signerName)) {
                return new SendResult('Signer name and email are required.');
            }
            
            // Generate PDF from VF page
            Blob customPdf = generatePdfFromVFPage(applicationId);
            if (customPdf == null) {
                return new SendResult('Error generating PDF from Visualforce page.');
            }
            
            // Create envelope with: Custom PDF + Template 1 + Template 2
            String envelopeId = createEnvelopeWithMultipleTemplates(
                customPdf, customPdfName, signatureTemplateId, termsTemplateId, signerEmail, signerName
            );
            
            return new SendResult(envelopeId, null);
            
        } catch (Exception e) {
            System.debug('Error in sendUsingMultipleTemplatesWithCustomPDF: ' + e.getMessage());
            return new SendResult('Error sending document: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static SendResult sendUsingMultipleTemplatesWithCustomPDFEmbedded(
        Id applicationId, 
        String signatureTemplateId,        // Template 1: Has signatures
        String termsTemplateId,            // Template 2: Terms & conditions
        String signerEmail, 
        String signerName,
        String clientUserId,
        String returnUrl,
        String customPdfName
    ) {
        try {
            // Validate inputs
            if (applicationId == null) {
                return new SendResult('Application Id is required.');
            }
            if (String.isBlank(signatureTemplateId)) {
                return new SendResult('Signature Template ID is required.');
            }
            if (String.isBlank(termsTemplateId)) {
                return new SendResult('Terms Template ID is required.');
            }
            if (String.isBlank(signerEmail) || String.isBlank(signerName)) {
                return new SendResult('Signer name and email are required.');
            }
            if (String.isBlank(clientUserId)) {
                return new SendResult('Client User Id is required for embedded signing.');
            }
            
            // Generate PDF from VF page
            Blob customPdf = generatePdfFromVFPage(applicationId);
            if (customPdf == null) {
                return new SendResult('Error generating PDF from Visualforce page.');
            }
            
            // Create envelope with embedded signing
            String envelopeId = createEnvelopeWithMultipleTemplatesEmbedded(
                customPdf, customPdfName, signatureTemplateId, termsTemplateId, 
                signerEmail, signerName, clientUserId
            );
            
            // Create recipient view
            String safeReturn = String.isBlank(returnUrl)
                ? URL.getOrgDomainUrl().toExternalForm() + '/lightning/page/home'
                : returnUrl;

            String signingUrl = createRecipientView(envelopeId, signerEmail, signerName, clientUserId, safeReturn);
            return new SendResult(envelopeId, signingUrl);
            
        } catch (Exception e) {
            System.debug('Error in sendUsingMultipleTemplatesWithCustomPDFEmbedded: ' + e.getMessage());
            return new SendResult('Error sending document: ' + e.getMessage());
        }
    }

    // ============================================================================
    // MULTIPLE ARBITRARY PDFs METHODS (NEW - Dynamic PDF List Support)
    // ============================================================================

    @AuraEnabled(cacheable=false)
    public static SendResult sendMultiplePdfsForRemoteSigning(
        Id applicationId,
        String signerEmail, 
        String signerName,
        List<String> pdfNames,
        List<String> pdfBase64Contents
    ) {
        try {
            // Validate inputs
            if (applicationId == null) {
                return new SendResult('Application ID is required.');
            }
            if (String.isBlank(signerEmail) || String.isBlank(signerName)) {
                return new SendResult('Signer name and email are required.');
            }
            if (pdfNames == null || pdfNames.isEmpty()) {
                return new SendResult('At least one PDF is required.');
            }
            if (pdfBase64Contents == null || pdfBase64Contents.size() != pdfNames.size()) {
                return new SendResult('PDF names and contents must have matching counts.');
            }
            
            // Create envelope with multiple PDFs
            Map<String,Object> envelopeResponse = createEnvelopeWithMultiplePdfs(
                pdfNames, pdfBase64Contents, signerEmail, signerName, null, applicationId
            );
            
            String envelopeId = (String) envelopeResponse.get('envelopeId');
            String status = (String) envelopeResponse.get('status');
            String statusDateTime = (String) envelopeResponse.get('statusDateTime');
            
            // Create Envelope record in DFSLE
            dfsle__Envelope__c envelopeRecord = new dfsle__Envelope__c();
            envelopeRecord.dfsle__DocuSignId__c = envelopeId;
            envelopeRecord.dfsle__SourceId__c = applicationId;
            envelopeRecord.dfsle__Sent__c = String.isBlank(statusDateTime) ? System.now() : DateTime.valueOf(statusDateTime.replace('Z', '').replace('T', ' '));
            envelopeRecord.dfsle__Sender__c = UserInfo.getUserId();
            envelopeRecord.dfsle__EmailSubject__c = 'Please review and sign - ' + pdfNames.size() + ' documents';
            envelopeRecord.dfsle__EmailMessage__c = 'Please review and sign all ' + pdfNames.size() + ' document(s). Sign each document to complete the process.';
            envelopeRecord.dfsle__UpdateChatter__c = false;
            insert envelopeRecord;
            
            // Create Envelope Status record in DFSLE
            dfsle__EnvelopeStatus__c statusRecord = new dfsle__EnvelopeStatus__c();
            statusRecord.dfsle__DocuSignId__c = envelopeId;
            statusRecord.dfsle__SourceId__c = applicationId;
            // statusRecord.dfsle__Status__c = status;
            // statusRecord.dfsle__SenderEmail__c = signerEmail;
            // statusRecord.dfsle__SenderName__c = signerName;
            // statusRecord.dfsle__Sent__c = String.isBlank(statusDateTime) ? System.now() : DateTime.valueOf(statusDateTime.replace('Z', '').replace('T', ' '));
            insert statusRecord;
            
            return new SendResult(envelopeId, null);
            
        } catch (Exception e) {
            System.debug('Error in sendMultiplePdfsForRemoteSigning: ' + e.getMessage());
            return new SendResult('Error sending documents: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static SendResult sendMultiplePdfsForEmbeddedSigning(
        Id applicationId,
        String signerEmail, 
        String signerName,
        String clientUserId,
        String returnUrl,
        List<String> pdfNames,
        List<String> pdfBase64Contents
    ) {
        try {
            // Validate inputs
            if (applicationId == null) {
                return new SendResult('Application ID is required.');
            }
            if (String.isBlank(signerEmail) || String.isBlank(signerName)) {
                return new SendResult('Signer name and email are required.');
            }
            if (String.isBlank(clientUserId)) {
                return new SendResult('Client User Id is required for embedded signing.');
            }
            if (pdfNames == null || pdfNames.isEmpty()) {
                return new SendResult('At least one PDF is required.');
            }
            if (pdfBase64Contents == null || pdfBase64Contents.size() != pdfNames.size()) {
                return new SendResult('PDF names and contents must have matching counts.');
            }
            
            // Create envelope with multiple PDFs
            Map<String,Object> envelopeResponse = createEnvelopeWithMultiplePdfs(
                pdfNames, pdfBase64Contents, signerEmail, signerName, clientUserId, applicationId
            );
            
            String envelopeId = (String) envelopeResponse.get('envelopeId');
            
            // Create recipient view for embedded signing
            String safeReturn = String.isBlank(returnUrl)
                ? URL.getOrgDomainUrl().toExternalForm() + '/lightning/page/home'
                : returnUrl;

            String signingUrl = createRecipientView(envelopeId, signerEmail, signerName, clientUserId, safeReturn);
            return new SendResult(envelopeId, signingUrl);
            
        } catch (Exception e) {
            System.debug('Error in sendMultiplePdfsForEmbeddedSigning: ' + e.getMessage());
            return new SendResult('Error sending documents: ' + e.getMessage());
        }
    }

    private static Map<String,Object> createEnvelopeWithMultiplePdfs(
        List<String> pdfNames, List<String> pdfBase64Contents, 
        String signerEmail, String signerName, String clientUserId, String applicationId
    ) {
        try {
            // Build documents list dynamically
            List<Object> documents = new List<Object>();
            for (Integer i = 0; i < pdfNames.size(); i++) {
                String pdfName = String.isBlank(pdfNames[i]) ? 'Document_' + (i + 1) + '.pdf' : pdfNames[i];
                if (!pdfName.endsWith('.pdf')) {
                    pdfName += '.pdf';
                }
                
                documents.add(new Map<String,Object>{
                    'documentBase64' => pdfBase64Contents[i],
                    'name' => pdfName,
                    'fileExtension' => 'pdf',
                    'documentId' => String.valueOf(i + 1),
                    'order' => String.valueOf(i + 1)
                });
            }
            
            // Build signing tabs for ALL documents
            List<Object> signHereTabs = new List<Object>();
            List<Object> dateSignedTabs = new List<Object>();
            for (Integer i = 0; i < pdfNames.size(); i++) {
                signHereTabs.add(new Map<String,Object>{
                    'documentId' => String.valueOf(i + 1),
                    'pageNumber' => '1',
                    'recipientId' => '1',
                    'xPosition' => '100',
                    'yPosition' => '700',
                    'width' => '100',
                    'height' => '20',
                    'tabLabel' => 'SignHere_' + (i + 1)
                });
                dateSignedTabs.add(new Map<String,Object>{
                    'documentId' => String.valueOf(i + 1),
                    'pageNumber' => '1',
                    'recipientId' => '1',
                    'xPosition' => '250',
                    'yPosition' => '720',
                    'width' => '100',
                    'height' => '20',
                    'tabLabel' => 'SignDate_' + (i + 1),
                    'value' => '',
                    'font' => 'Helvetica'
                });
            }
            
            // Build signer object
            Map<String,Object> signer = new Map<String,Object>{
                'email' => signerEmail.trim(),
                'name' => signerName.trim(),
                'recipientId' => '1',
                'routingOrder' => '1',
                'tabs' => new Map<String,Object>{
                    'signHereTabs' => signHereTabs,
                    'dateSignedTabs' => dateSignedTabs
                }
            };
            
            if (!String.isBlank(clientUserId)) {
                signer.put('clientUserId', clientUserId.trim());
            }
            
            // Build envelope with custom field for tracking
            Map<String,Object> envelope = new Map<String,Object>{
                'emailSubject' => 'Please review and sign - ' + pdfNames.size() + ' documents',
                'emailBlurb' => 'Please review and sign all ' + pdfNames.size() + ' document(s). Sign each document to complete the process.',
                'documents' => documents,
                'recipients' => new Map<String,Object>{
                    'signers' => new List<Object>{ signer }
                },
                'status' => 'sent',
                'enableWetSign' => false,
                'allowMarkup' => false,
                'allowReassign' => false,
                'customFields' => new Map<String,Object>{
                    'textCustomFields' => new List<Object>{
                        new Map<String,Object>{
                            'name' => 'envelopeSourceId',
                            'value' => String.valueOf(applicationId)
                        }
                    }
                }
            };
            
            // Make HTTP request
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:' + NAMED_CREDENTIAL + '/v2.1/accounts/' + accountId() + '/envelopes');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept', 'application/json');
            req.setTimeout(120000);
            
            String requestBody = JSON.serialize(envelope);
            req.setBody(requestBody);
            
            System.debug('Multiple PDFs Envelope Request - Document Count: ' + pdfNames.size() + ', Body Length: ' + requestBody.length());
            
            Http http = new Http();
            HTTPResponse res = http.send(req);
            
            System.debug('Multiple PDFs Response Status: ' + res.getStatusCode());
            System.debug('Multiple PDFs Response Body: ' + res.getBody());
            
            if (res.getStatusCode() >= 300) {
                String errorBody = res.getBody();
                System.debug('DocuSign Error Response: ' + errorBody);
                
                try {
                    Map<String,Object> errorResponse = (Map<String,Object>) JSON.deserializeUntyped(errorBody);
                    String errorMsg = (String) errorResponse.get('message');
                    if (!String.isBlank(errorMsg)) {
                        throw new AuraHandledException('DocuSign Error: ' + errorMsg);
                    }
                } catch (JSONException je) {
                    // If we can't parse the error, use the raw response
                }
                
                throw new AuraHandledException('DocuSign envelope error (Status: ' + res.getStatusCode() + '): ' + errorBody);
            }
            
            Map<String,Object> responseBody = (Map<String,Object>) JSON.deserializeUntyped(res.getBody());
            system.debug('responseBody::' + responseBody);
            String envelopeId = (String) responseBody.get('envelopeId');
            
            if (String.isBlank(envelopeId)) {
                throw new AuraHandledException('DocuSign did not return an envelope ID.');
            }
            
            System.debug('Successfully created envelope with ' + pdfNames.size() + ' PDFs: ' + envelopeId);
            return responseBody;
            
        } catch (CalloutException e) {
            System.debug('Callout error in createEnvelopeWithMultiplePdfs: ' + e.getMessage());
            throw new AuraHandledException('Network error communicating with DocuSign: ' + e.getMessage());
        } catch (JSONException e) {
            System.debug('JSON error in createEnvelopeWithMultiplePdfs: ' + e.getMessage());
            throw new AuraHandledException('Error processing DocuSign response: ' + e.getMessage());
        }
    }

    // ============================================================================
    // SINGLE TEMPLATE METHODS (Custom PDF + Single Template)
    // ============================================================================

    @AuraEnabled(cacheable=false)
    public static SendResult sendUsingTemplateWithCustomPDFFirst(
        Id applicationId, 
        String templateId, 
        String signerEmail, 
        String signerName,
        String customPdfName
    ) {
        try {
            // Validate inputs
            if (applicationId == null) {
                return new SendResult('Application Id is required.');
            }
            if (String.isBlank(templateId)) {
                return new SendResult('DocuSign Template ID is required.');
            }
            if (String.isBlank(signerEmail) || String.isBlank(signerName)) {
                return new SendResult('Signer name and email are required.');
            }
            
            // Generate PDF from VF page
            Blob customPdf = generatePdfFromVFPage(applicationId);
            if (customPdf == null) {
                return new SendResult('Error generating PDF from Visualforce page.');
            }
            
            // Create envelope with custom PDF FIRST, template SECOND
            String envelopeId = createEnvelopeFromTemplateWithPDFProperOrder(
                templateId, customPdf, customPdfName, signerEmail, signerName
            );
            
            return new SendResult(envelopeId, null);
            
        } catch (Exception e) {
            System.debug('Error in sendUsingTemplateWithCustomPDFFirst: ' + e.getMessage());
            return new SendResult('Error sending document: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static SendResult sendUsingTemplateWithCustomPDFFirstEmbedded(
        Id applicationId, 
        String templateId, 
        String signerEmail, 
        String signerName,
        String clientUserId,
        String returnUrl,
        String customPdfName
    ) {
        try {
            // Validate inputs
            if (applicationId == null) {
                return new SendResult('Application Id is required.');
            }
            if (String.isBlank(templateId)) {
                return new SendResult('DocuSign Template ID is required.');
            }
            if (String.isBlank(signerEmail) || String.isBlank(signerName)) {
                return new SendResult('Signer name and email are required.');
            }
            if (String.isBlank(clientUserId)) {
                return new SendResult('Client User Id is required for embedded signing.');
            }
            
            // Generate PDF from VF page
            Blob customPdf = generatePdfFromVFPage(applicationId);
            if (customPdf == null) {
                return new SendResult('Error generating PDF from Visualforce page.');
            }
            
            // Create envelope with custom PDF FIRST, template SECOND (embedded)
            String envelopeId = createEnvelopeFromTemplateWithPDFProperOrderEmbedded(
                templateId, customPdf, customPdfName, signerEmail, signerName, clientUserId
            );
            
            // Create recipient view for embedded signing
            String safeReturn = String.isBlank(returnUrl)
                ? URL.getOrgDomainUrl().toExternalForm() + '/lightning/page/home'
                : returnUrl;

            String signingUrl = createRecipientView(envelopeId, signerEmail, signerName, clientUserId, safeReturn);
            return new SendResult(envelopeId, signingUrl);
            
        } catch (Exception e) {
            System.debug('Error in sendUsingTemplateWithCustomPDFFirstEmbedded: ' + e.getMessage());
            return new SendResult('Error sending document: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static SendResult sendUsingTemplateWithCustomPDFTwoStep(
        Id applicationId, 
        String templateId, 
        String signerEmail, 
        String signerName,
        String customPdfName
    ) {
        try {
            // Validate inputs
            if (applicationId == null) {
                return new SendResult('Application Id is required.');
            }
            if (String.isBlank(templateId)) {
                return new SendResult('DocuSign Template ID is required.');
            }
            if (String.isBlank(signerEmail) || String.isBlank(signerName)) {
                return new SendResult('Signer name and email are required.');
            }
            
            // Generate PDF from VF page
            Blob customPdf = generatePdfFromVFPage(applicationId);
            if (customPdf == null) {
                return new SendResult('Error generating PDF from Visualforce page.');
            }
            
            // Create envelope using two-step approach (more reliable for ordering)
            String envelopeId = createEnvelopeFromTemplateAndAddPDF(
                templateId, customPdf, customPdfName, signerEmail, signerName
            );
            
            return new SendResult(envelopeId, null);
            
        } catch (Exception e) {
            System.debug('Error in sendUsingTemplateWithCustomPDFTwoStep: ' + e.getMessage());
            return new SendResult('Error sending document: ' + e.getMessage());
        }
    }

    // ============================================================================
    // ORIGINAL METHODS (Non-Template Based - for backward compatibility)
    // ============================================================================

    @AuraEnabled(cacheable=false)
    public static SendResult sendForRemoteSigning(Id applicationId, String signerEmail, String signerName) {
        try {
            // Validate inputs
            if (applicationId == null) {
                return new SendResult('Application Id is required.');
            }
            if (String.isBlank(signerEmail) || String.isBlank(signerName)) {
                return new SendResult('Signer name and email are required.');
            }
            
            Blob pdf = getLatestLinkedPdf(applicationId);
            if (pdf == null) {
                return new SendResult('No PDF content found.');
            }
            
            String envelopeId = createAndSendEnvelope(pdf, 'application.pdf', signerEmail, signerName, null);
            return new SendResult(envelopeId, null);
            
        } catch (Exception e) {
            System.debug('Error in sendForRemoteSigning: ' + e.getMessage());
            return new SendResult('Error sending document: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static SendResult sendForEmbeddedSigning(
        Id applicationId, String signerEmail, String signerName, String clientUserId, String returnUrl
    ) {
        try {
            // Validate inputs
            if (applicationId == null) {
                return new SendResult('Application Id is required.');
            }
            if (String.isBlank(signerEmail) || String.isBlank(signerName)) {
                return new SendResult('Signer name and email are required.');
            }
            if (String.isBlank(clientUserId)) {
                return new SendResult('Client User Id is required for embedded signing.');
            }
            
            Blob pdf = getLatestLinkedPdf(applicationId);
            if (pdf == null) {
                return new SendResult('No PDF content found.');
            }
            
            String envelopeId = createAndSendEnvelope(pdf, 'application.pdf', signerEmail, signerName, clientUserId);
            
            // Use getOrgDomainUrl for v59+
            String safeReturn = String.isBlank(returnUrl)
                ? URL.getOrgDomainUrl().toExternalForm() + '/lightning/page/home'
                : returnUrl;

            String signingUrl = createRecipientView(envelopeId, signerEmail, signerName, clientUserId, safeReturn);
            return new SendResult(envelopeId, signingUrl);
            
        } catch (Exception e) {
            System.debug('Error in sendForEmbeddedSigning: ' + e.getMessage());
            return new SendResult('Error sending document: ' + e.getMessage());
        }
    }

    // ============================================================================
    // PDF GENERATION FROM VF PAGE
    // ============================================================================

    private static Blob generatePdfFromVFPage(Id applicationId) {
        try {
            // Generate PDF from Visualforce page
            PageReference pdfPage = Page.CarLoanProtectionApplicationVFP; // Your VF page name - CHANGE THIS
            pdfPage.getParameters().put('id', applicationId);
            pdfPage.setRedirect(true);
            
            Blob pdfBlob;
            if (Test.isRunningTest()) {
                // For test context, create a dummy PDF
                String pdfContent = '%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj 2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj 3 0 obj<</Type/Page/MediaBox[0 0 612 792]/Parent 2 0 R/Resources<</Font<</F1 4 0 R>>>>/Contents 5 0 R>>endobj 4 0 obj<</Type/Font/Subtype/Type1/BaseFont/Times-Roman>>endobj 5 0 obj<</Length 44>>stream BT /F1 12 Tf 100 700 Td (Test Application PDF) Tj ET endstream endobj xref 0 6 0000000000 65535 f 0000000010 00000 n 0000000053 00000 n 0000000125 00000 n 0000000348 00000 n 0000000565 00000 n trailer<</Size 6/Root 1 0 R>> startxref 631 %%EOF';
                pdfBlob = Blob.valueOf(pdfContent);
            } else {
                pdfBlob = pdfPage.getContentAsPDF();
            }
            
            System.debug('Generated PDF size: ' + pdfBlob.size() + ' bytes');
            return pdfBlob;
            
        } catch (Exception e) {
            System.debug('Error generating PDF from VF page: ' + e.getMessage());
            // Fallback: create a simple PDF if VF page fails
            String fallbackContent = '%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj 2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj 3 0 obj<</Type/Page/MediaBox[0 0 612 792]/Parent 2 0 R/Resources<</Font<</F1 4 0 R>>>>/Contents 5 0 R>>endobj 4 0 obj<</Type/Font/Subtype/Type1/BaseFont/Times-Roman>>endobj 5 0 obj<</Length 44>>stream BT /F1 12 Tf 100 700 Td (Application Details PDF) Tj ET endstream endobj xref 0 6 0000000000 65535 f 0000000010 00000 n 0000000053 00000 n 0000000125 00000 n 0000000348 00000 n 0000000565 00000 n trailer<</Size 6/Root 1 0 R>> startxref 631 %%EOF';
            return Blob.valueOf(fallbackContent);
        }
    }

    // ============================================================================
    // MULTIPLE TEMPLATES IMPLEMENTATION
    // ============================================================================

    private static String createEnvelopeWithMultipleTemplates(
        Blob customPdf, String customPdfName, String signatureTemplateId, String termsTemplateId,
        String signerEmail, String signerName
    ) {
        try {
            String docB64 = EncodingUtil.base64Encode(customPdf);
            String fileName = String.isBlank(customPdfName) ? 'Application Details.pdf' : customPdfName;
            
            // COMPOSITE TEMPLATES: Custom PDF + Template 1 + Template 2
            Map<String,Object> envelope = new Map<String,Object>{
                'emailSubject' => 'Please review and sign - Complete Application Package',
                'emailBlurb' => 'Please review: 1) Application details, 2) Signature document, 3) Terms & conditions.',
                'status' => 'sent',
                'compositeTemplates' => new List<Object>{
                    
                    // COMPOSITE 1: Custom PDF (comes first - order 1)
                    new Map<String,Object>{
                        'compositeTemplateId' => '1',
                        'inlineTemplates' => new List<Object>{
                            new Map<String,Object>{
                                'sequence' => '1', // First in sequence
                                'documents' => new List<Object>{
                                    new Map<String,Object>{
                                        'documentBase64' => docB64,
                                        'name' => fileName,
                                        'fileExtension' => 'pdf',
                                        'documentId' => '1', // Document ID 1
                                        'order' => '1' // First document
                                    }
                                }
                            }
                        }
                    },
                    
                    // COMPOSITE 2: Signature Template (comes second - order 2)
                    new Map<String,Object>{
                        'compositeTemplateId' => '2',
                        'serverTemplates' => new List<Object>{
                            new Map<String,Object>{
                                'sequence' => '2', // Second in sequence
                                'templateId' => signatureTemplateId
                            }
                        },
                        'inlineTemplates' => new List<Object>{
                            new Map<String,Object>{
                                'sequence' => '2',
                                'recipients' => new Map<String,Object>{
                                    'signers' => new List<Object>{
                                        new Map<String,Object>{
                                            'email' => signerEmail.trim(),
                                            'name' => signerName.trim(),
                                            'recipientId' => '1', // Same recipient for all templates
                                            'routingOrder' => '1',
                                            'roleName' => 'Signer' // Must match template role
                                        }
                                    }
                                }
                            }
                        }
                    },
                    
                    // COMPOSITE 3: Terms Template (comes third - order 3)
                    new Map<String,Object>{
                        'compositeTemplateId' => '3',
                        'serverTemplates' => new List<Object>{
                            new Map<String,Object>{
                                'sequence' => '3', // Third in sequence
                                'templateId' => termsTemplateId
                            }
                        },
                        'inlineTemplates' => new List<Object>{
                            new Map<String,Object>{
                                'sequence' => '3',
                                'recipients' => new Map<String,Object>{
                                    'signers' => new List<Object>{
                                        new Map<String,Object>{
                                            'email' => signerEmail.trim(),
                                            'name' => signerName.trim(),
                                            'recipientId' => '1', // Same recipient
                                            'routingOrder' => '1',
                                            'roleName' => 'Signer' // Must match template role
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            };

            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:' + NAMED_CREDENTIAL + '/v2.1/accounts/' + accountId() + '/envelopes');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept', 'application/json');
            req.setTimeout(120000);
            
            String requestBody = JSON.serialize(envelope);
            req.setBody(requestBody);

            System.debug('MULTIPLE TEMPLATES Request Length: ' + requestBody.length());

            Http http = new Http();
            HTTPResponse res = http.send(req);
            
            System.debug('MULTIPLE TEMPLATES Response Status: ' + res.getStatusCode());
            System.debug('MULTIPLE TEMPLATES Response: ' + res.getBody());
            
            if (res.getStatusCode() >= 300) {
                throw new AuraHandledException('DocuSign multiple templates error (Status: ' + res.getStatusCode() + '): ' + res.getBody());
            }
            
            Map<String,Object> responseBody = (Map<String,Object>) JSON.deserializeUntyped(res.getBody());
            String envelopeId = (String) responseBody.get('envelopeId');
            
            if (String.isBlank(envelopeId)) {
                throw new AuraHandledException('DocuSign did not return an envelope ID.');
            }
            
            System.debug('Successfully created envelope with multiple templates: ' + envelopeId);
            return envelopeId;
            
        } catch (Exception e) {
            System.debug('Error in createEnvelopeWithMultipleTemplates: ' + e.getMessage());
            throw e;
        }
    }

    private static String createEnvelopeWithMultipleTemplatesEmbedded(
        Blob customPdf, String customPdfName, String signatureTemplateId, String termsTemplateId,
        String signerEmail, String signerName, String clientUserId
    ) {
        try {
            String docB64 = EncodingUtil.base64Encode(customPdf);
            String fileName = String.isBlank(customPdfName) ? 'Application Details.pdf' : customPdfName;
            
            Map<String,Object> envelope = new Map<String,Object>{
                'emailSubject' => 'Please review and sign - Complete Application Package',
                'emailBlurb' => 'Please review: 1) Application details, 2) Signature document, 3) Terms & conditions.',
                'status' => 'sent',
                'compositeTemplates' => new List<Object>{
                    
                    // Custom PDF first
                    new Map<String,Object>{
                        'compositeTemplateId' => '1',
                        'inlineTemplates' => new List<Object>{
                            new Map<String,Object>{
                                'sequence' => '1',
                                'documents' => new List<Object>{
                                    new Map<String,Object>{
                                        'documentBase64' => docB64,
                                        'name' => fileName,
                                        'fileExtension' => 'pdf',
                                        'documentId' => '1',
                                        'order' => '1'
                                    }
                                }
                            }
                        }
                    },
                    
                    // Signature Template second with clientUserId
                    new Map<String,Object>{
                        'compositeTemplateId' => '2',
                        'serverTemplates' => new List<Object>{
                            new Map<String,Object>{
                                'sequence' => '2',
                                'templateId' => signatureTemplateId
                            }
                        },
                        'inlineTemplates' => new List<Object>{
                            new Map<String,Object>{
                                'sequence' => '2',
                                'recipients' => new Map<String,Object>{
                                    'signers' => new List<Object>{
                                        new Map<String,Object>{
                                            'email' => signerEmail.trim(),
                                            'name' => signerName.trim(),
                                            'recipientId' => '1',
                                            'routingOrder' => '1',
                                            'roleName' => 'Signer',
                                            'clientUserId' => clientUserId.trim()
                                        }
                                    }
                                }
                            }
                        }
                    },
                    
                    // Terms Template third
                    new Map<String,Object>{
                        'compositeTemplateId' => '3',
                        'serverTemplates' => new List<Object>{
                            new Map<String,Object>{
                                'sequence' => '3',
                                'templateId' => termsTemplateId
                            }
                        },
                        'inlineTemplates' => new List<Object>{
                            new Map<String,Object>{
                                'sequence' => '3',
                                'recipients' => new Map<String,Object>{
                                    'signers' => new List<Object>{
                                        new Map<String,Object>{
                                            'email' => signerEmail.trim(),
                                            'name' => signerName.trim(),
                                            'recipientId' => '1',
                                            'routingOrder' => '1',
                                            'roleName' => 'Signer',
                                            'clientUserId' => clientUserId.trim()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            };

            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:' + NAMED_CREDENTIAL + '/v2.1/accounts/' + accountId() + '/envelopes');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept', 'application/json');
            req.setTimeout(120000);
            req.setBody(JSON.serialize(envelope));

            Http http = new Http();
            HTTPResponse res = http.send(req);
            
            System.debug('MULTIPLE TEMPLATES EMBEDDED Response Status: ' + res.getStatusCode());
            System.debug('MULTIPLE TEMPLATES EMBEDDED Response: ' + res.getBody());
            
            if (res.getStatusCode() >= 300) {
                throw new AuraHandledException('DocuSign multiple templates embedded error: ' + res.getBody());
            }
            
            Map<String,Object> responseBody = (Map<String,Object>) JSON.deserializeUntyped(res.getBody());
            return (String) responseBody.get('envelopeId');
            
        } catch (Exception e) {
            System.debug('Error in createEnvelopeWithMultipleTemplatesEmbedded: ' + e.getMessage());
            throw e;
        }
    }

    // ============================================================================
    // SINGLE TEMPLATE IMPLEMENTATION - PROPER ORDERING
    // ============================================================================

    private static String createEnvelopeFromTemplateWithPDFProperOrder(
        String templateId, Blob customPdf, String customPdfName, String signerEmail, String signerName
    ) {
        try {
            String docB64 = EncodingUtil.base64Encode(customPdf);
            String fileName = String.isBlank(customPdfName) ? 'Application Details.pdf' : customPdfName;
            
            // FIXED: Proper composite template with document ordering
            Map<String,Object> envelope = new Map<String,Object>{
                'emailSubject' => 'Please review and sign - Application Documents',
                'emailBlurb' => 'Please review the application details first, then the terms and conditions.',
                'status' => 'sent',
                'compositeTemplates' => new List<Object>{
                    // Composite Template 1: Custom PDF (comes first)
                    new Map<String,Object>{
                        'compositeTemplateId' => '1',
                        'inlineTemplates' => new List<Object>{
                            new Map<String,Object>{
                                'sequence' => '1', // First in sequence
                                'documents' => new List<Object>{
                                    new Map<String,Object>{
                                        'documentBase64' => docB64,
                                        'name' => fileName,
                                        'fileExtension' => 'pdf',
                                        'documentId' => '1', // First document ID
                                        'order' => '1' // Explicit first order
                                    }
                                }
                            }
                        }
                    },
                    // Composite Template 2: Server Template (comes second)
                    new Map<String,Object>{
                        'compositeTemplateId' => '2',
                        'serverTemplates' => new List<Object>{
                            new Map<String,Object>{
                                'sequence' => '2', // Second in sequence
                                'templateId' => templateId
                            }
                        },
                        'inlineTemplates' => new List<Object>{
                            new Map<String,Object>{
                                'sequence' => '2',
                                'recipients' => new Map<String,Object>{
                                    'signers' => new List<Object>{
                                        new Map<String,Object>{
                                            'email' => signerEmail.trim(),
                                            'name' => signerName.trim(),
                                            'recipientId' => '1',
                                            'routingOrder' => '1',
                                            'roleName' => 'Signer' // Must match template role
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            };

            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:' + NAMED_CREDENTIAL + '/v2.1/accounts/' + accountId() + '/envelopes');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept', 'application/json');
            req.setTimeout(120000);
            
            String requestBody = JSON.serialize(envelope);
            req.setBody(requestBody);

            System.debug('PROPER ORDER Template Request Length: ' + requestBody.length());

            Http http = new Http();
            HTTPResponse res = http.send(req);
            
            System.debug('PROPER ORDER Response Status: ' + res.getStatusCode());
            System.debug('PROPER ORDER Response: ' + res.getBody());
            
            if (res.getStatusCode() >= 300) {
                throw new AuraHandledException('DocuSign template error (Status: ' + res.getStatusCode() + '): ' + res.getBody());
            }
            
            Map<String,Object> responseBody = (Map<String,Object>) JSON.deserializeUntyped(res.getBody());
            String envelopeId = (String) responseBody.get('envelopeId');
            
            if (String.isBlank(envelopeId)) {
                throw new AuraHandledException('DocuSign did not return an envelope ID.');
            }
            
            System.debug('Successfully created envelope with proper document order: ' + envelopeId);
            return envelopeId;
            
        } catch (Exception e) {
            System.debug('Error in createEnvelopeFromTemplateWithPDFProperOrder: ' + e.getMessage());
            throw e;
        }
    }

    private static String createEnvelopeFromTemplateWithPDFProperOrderEmbedded(
        String templateId, Blob customPdf, String customPdfName, 
        String signerEmail, String signerName, String clientUserId
    ) {
        try {
            String docB64 = EncodingUtil.base64Encode(customPdf);
            String fileName = String.isBlank(customPdfName) ? 'Application Details.pdf' : customPdfName;
            
            Map<String,Object> envelope = new Map<String,Object>{
                'emailSubject' => 'Please review and sign - Application Documents',
                'emailBlurb' => 'Please review the application details first, then the terms and conditions.',
                'status' => 'sent',
                'compositeTemplates' => new List<Object>{
                    // Custom PDF first
                    new Map<String,Object>{
                        'compositeTemplateId' => '1',
                        'inlineTemplates' => new List<Object>{
                            new Map<String,Object>{
                                'sequence' => '1',
                                'documents' => new List<Object>{
                                    new Map<String,Object>{
                                        'documentBase64' => docB64,
                                        'name' => fileName,
                                        'fileExtension' => 'pdf',
                                        'documentId' => '1',
                                        'order' => '1'
                                    }
                                }
                            }
                        }
                    },
                    // Template second with clientUserId
                    new Map<String,Object>{
                        'compositeTemplateId' => '2',
                        'serverTemplates' => new List<Object>{
                            new Map<String,Object>{
                                'sequence' => '2',
                                'templateId' => templateId
                            }
                        },
                        'inlineTemplates' => new List<Object>{
                            new Map<String,Object>{
                                'sequence' => '2',
                                'recipients' => new Map<String,Object>{
                                    'signers' => new List<Object>{
                                        new Map<String,Object>{
                                            'email' => signerEmail.trim(),
                                            'name' => signerName.trim(),
                                            'recipientId' => '1',
                                            'routingOrder' => '1',
                                            'roleName' => 'Signer',
                                            'clientUserId' => clientUserId.trim()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            };

            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:' + NAMED_CREDENTIAL + '/v2.1/accounts/' + accountId() + '/envelopes');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept', 'application/json');
            req.setTimeout(120000);
            req.setBody(JSON.serialize(envelope));

            Http http = new Http();
            HTTPResponse res = http.send(req);
            
            System.debug('Embedded Proper Order Response Status: ' + res.getStatusCode());
            System.debug('Embedded Proper Order Response: ' + res.getBody());
            
            if (res.getStatusCode() >= 300) {
                throw new AuraHandledException('DocuSign embedded template error: ' + res.getBody());
            }
            
            Map<String,Object> responseBody = (Map<String,Object>) JSON.deserializeUntyped(res.getBody());
            return (String) responseBody.get('envelopeId');
            
        } catch (Exception e) {
            System.debug('Error in createEnvelopeFromTemplateWithPDFProperOrderEmbedded: ' + e.getMessage());
            throw e;
        }
    }

    // ============================================================================
    // TWO-STEP APPROACH (More reliable for document ordering)
    // ============================================================================

    private static String createEnvelopeFromTemplateAndAddPDF(
        String templateId, Blob customPdf, String customPdfName, String signerEmail, String signerName
    ) {
        try {
            // Step 1: Create envelope from template (draft status)
            String envelopeId = createEnvelopeFromTemplate(templateId, signerEmail, signerName);
            
            // Step 2: Add custom PDF to the envelope FIRST (order 1)
            addDocumentToEnvelopeFirst(envelopeId, customPdf, customPdfName);
            
            // Step 3: Update template documents to come AFTER custom PDF
            updateTemplateDocumentOrder(envelopeId);
            
            // Step 4: Send the envelope
            sendDraftEnvelope(envelopeId);
            
            return envelopeId;
            
        } catch (Exception e) {
            System.debug('Error in createEnvelopeFromTemplateAndAddPDF: ' + e.getMessage());
            throw e;
        }
    }

    private static String createEnvelopeFromTemplate(String templateId, String signerEmail, String signerName) {
        try {
            Map<String,Object> envelope = new Map<String,Object>{
                'emailSubject' => 'Please review and sign - Application Documents',
                'templateId' => templateId,
                'templateRoles' => new List<Object>{
                    new Map<String,Object>{
                        'email' => signerEmail.trim(),
                        'name' => signerName.trim(),
                        'roleName' => 'Signer' // Must match template role name
                    }
                },
                'status' => 'created' // Draft status
            };

            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:' + NAMED_CREDENTIAL + '/v2.1/accounts/' + accountId() + '/envelopes');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept', 'application/json');
            req.setTimeout(120000);
            req.setBody(JSON.serialize(envelope));

            Http http = new Http();
            HTTPResponse res = http.send(req);
            
            System.debug('Template Envelope Creation Response: ' + res.getBody());
            
            if (res.getStatusCode() >= 300) {
                throw new AuraHandledException('Error creating template envelope: ' + res.getBody());
            }
            
            Map<String,Object> responseBody = (Map<String,Object>) JSON.deserializeUntyped(res.getBody());
            return (String) responseBody.get('envelopeId');
            
        } catch (Exception e) {
            throw new AuraHandledException('Error creating envelope from template: ' + e.getMessage());
        }
    }

    private static void addDocumentToEnvelopeFirst(String envelopeId, Blob customPdf, String customPdfName) {
        try {
            String docB64 = EncodingUtil.base64Encode(customPdf);
            String fileName = String.isBlank(customPdfName) ? 'Application Details.pdf' : customPdfName;
            
            Map<String,Object> document = new Map<String,Object>{
                'documentBase64' => docB64,
                'name' => fileName,
                'fileExtension' => 'pdf',
                'documentId' => '1', // Use documentId 1 to come first
                'order' => '1' // Explicit order - first document
            };

            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:' + NAMED_CREDENTIAL + '/v2.1/accounts/' + accountId() + 
                           '/envelopes/' + envelopeId + '/documents');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept', 'application/json');
            req.setTimeout(120000);
            req.setBody(JSON.serialize(document));

            Http http = new Http();
            HTTPResponse res = http.send(req);
            
            System.debug('Add Custom PDF Response Status: ' + res.getStatusCode());
            System.debug('Add Custom PDF Response: ' + res.getBody());
            
            if (res.getStatusCode() >= 300) {
                throw new AuraHandledException('Error adding custom PDF to envelope: ' + res.getBody());
            }
            
            System.debug('Successfully added custom PDF as first document');
            
        } catch (Exception e) {
            throw new AuraHandledException('Error adding custom PDF: ' + e.getMessage());
        }
    }

    private static void updateTemplateDocumentOrder(String envelopeId) {
        try {
            // First, get existing template documents
            HttpRequest getReq = new HttpRequest();
            getReq.setEndpoint('callout:' + NAMED_CREDENTIAL + '/v2.1/accounts/' + accountId() + 
                              '/envelopes/' + envelopeId + '/documents');
            getReq.setMethod('GET');
            getReq.setHeader('Accept', 'application/json');
            
            Http http = new Http();
            HttpResponse getRes = http.send(getReq);
            
            if (getRes.getStatusCode() == 200) {
                Map<String,Object> response = (Map<String,Object>) JSON.deserializeUntyped(getRes.getBody());
                List<Object> documents = (List<Object>) response.get('envelopeDocuments');
                
                // Update template documents to have order 2, 3, etc.
                Integer orderCounter = 2;
                for (Object docObj : documents) {
                    Map<String,Object> doc = (Map<String,Object>) docObj;
                    String docId = (String) doc.get('documentId');
                    String docName = (String) doc.get('name');
                    
                    // Skip the custom PDF (documentId 1) and summary document
                    if (!'1'.equals(docId) && !'summary'.equals(docId)) {
                        updateDocumentOrder(envelopeId, docId, String.valueOf(orderCounter));
                        System.debug('Updated document order - Name: ' + docName + ', Order: ' + orderCounter);
                        orderCounter++;
                    }
                }
            }
            
        } catch (Exception e) {
            System.debug('Warning: Could not update document order: ' + e.getMessage());
            // Don't throw - this is not critical
        }
    }

    private static void updateDocumentOrder(String envelopeId, String documentId, String newOrder) {
        try {
            Map<String,Object> docUpdate = new Map<String,Object>{
                'order' => newOrder
            };

            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:' + NAMED_CREDENTIAL + '/v2.1/accounts/' + accountId() + 
                           '/envelopes/' + envelopeId + '/documents/' + documentId);
            req.setMethod('PUT');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept', 'application/json');
            req.setTimeout(120000);
            req.setBody(JSON.serialize(docUpdate));

            Http http = new Http();
            HTTPResponse res = http.send(req);
            
            if (res.getStatusCode() >= 300) {
                System.debug('Warning: Could not update document ' + documentId + ' order: ' + res.getBody());
            }
            
        } catch (Exception e) {
            System.debug('Warning: Error updating document order: ' + e.getMessage());
        }
    }

    private static void sendDraftEnvelope(String envelopeId) {
        try {
            Map<String,Object> envelope = new Map<String,Object>{
                'status' => 'sent'
            };

            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:' + NAMED_CREDENTIAL + '/v2.1/accounts/' + accountId() + 
                           '/envelopes/' + envelopeId);
            req.setMethod('PUT');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept', 'application/json');
            req.setTimeout(120000);
            req.setBody(JSON.serialize(envelope));

            Http http = new Http();
            HTTPResponse res = http.send(req);
            
            System.debug('Send Envelope Response Status: ' + res.getStatusCode());
            System.debug('Send Envelope Response: ' + res.getBody());
            
            if (res.getStatusCode() >= 300) {
                throw new AuraHandledException('Error sending envelope: ' + res.getBody());
            }
            
            System.debug('Successfully sent envelope');
            
        } catch (Exception e) {
            throw new AuraHandledException('Error sending envelope: ' + e.getMessage());
        }
    }

    // ============================================================================
    // ORIGINAL ENVELOPE CREATION (NON-TEMPLATE)
    // ============================================================================

    private static String createAndSendEnvelope(
        Blob pdf, String fileName, String signerEmail, String signerName, String clientUserId
    ) {
        try {
            // Validate inputs
            if (pdf == null) {
                throw new AuraHandledException('PDF content is required.');
            }
            if (String.isBlank(signerEmail) || String.isBlank(signerName)) {
                throw new AuraHandledException('Signer name and email are required.');
            }

            String docB64 = EncodingUtil.base64Encode(pdf);

            // Build signer object with enhanced configuration
            Map<String,Object> signer = new Map<String,Object>{
                'email' => signerEmail.trim(),
                'name'  => signerName.trim(),
                'recipientId' => '1',
                'routingOrder' => '1',
                'tabs' => new Map<String,Object>{
                    'signHereTabs' => new List<Object>{
                        new Map<String,Object>{
                            'documentId' => '1',
                            'pageNumber' => '1',
                            'recipientId' => '1',
                            'xPosition' => '100',
                            'yPosition' => '700',
                            'width' => '100',
                            'height' => '20',
                            'tabLabel' => 'SignHere'
                        }
                    }
                }
            };
            
            if (!String.isBlank(clientUserId)) {
                signer.put('clientUserId', clientUserId.trim());
                System.debug('Setting clientUserId in envelope: ' + clientUserId.trim());
            }

            // Build envelope with enhanced settings
            Map<String,Object> envelope = new Map<String,Object>{
                'emailSubject' => 'Please review and sign this document',
                'emailBlurb' => 'Please review and sign the attached document.',
                'documents' => new List<Object>{
                    new Map<String,Object>{
                        'documentBase64' => docB64,
                        'name' => (String.isBlank(fileName) ? 'document.pdf' : fileName.trim()),
                        'fileExtension' => 'pdf',
                        'documentId' => '1'
                    }
                },
                'recipients' => new Map<String,Object>{
                    'signers' => new List<Object>{ signer }
                },
                'status' => 'sent',
                'enableWetSign' => false,
                'allowMarkup' => false,
                'allowReassign' => false
            };

            // Make HTTP request
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:' + NAMED_CREDENTIAL + '/v2.1/accounts/' + accountId() + '/envelopes');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept', 'application/json');
            req.setTimeout(120000);
            
            String requestBody = JSON.serialize(envelope);
            req.setBody(requestBody);
            
            System.debug('DocuSign Envelope Request Body Length: ' + requestBody.length());

            Http http = new Http();
            HTTPResponse res = http.send(req);
            
            System.debug('DocuSign Envelope Response Status: ' + res.getStatusCode());
            System.debug('DocuSign Envelope Response Body: ' + res.getBody());
            
            // Enhanced error handling
            if (res.getStatusCode() >= 300) {
                String errorBody = res.getBody();
                System.debug('DocuSign Error Response: ' + errorBody);
                
                // Parse DocuSign error if possible
                try {
                    Map<String,Object> errorResponse = (Map<String,Object>) JSON.deserializeUntyped(errorBody);
                    String errorMsg = (String) errorResponse.get('message');
                    if (!String.isBlank(errorMsg)) {
                        throw new AuraHandledException('DocuSign Error: ' + errorMsg);
                    }
                } catch (JSONException je) {
                    // If we can't parse the error, use the raw response
                }
                
                throw new AuraHandledException('DocuSign envelope error (Status: ' + res.getStatusCode() + '): ' + errorBody);
            }
            
            Map<String,Object> responseBody = (Map<String,Object>) JSON.deserializeUntyped(res.getBody());
            String envelopeId = (String) responseBody.get('envelopeId');
            
            if (String.isBlank(envelopeId)) {
                throw new AuraHandledException('DocuSign did not return an envelope ID.');
            }
            
            System.debug('Successfully created envelope: ' + envelopeId);
            return envelopeId;
            
        } catch (CalloutException e) {
            System.debug('Callout error in createAndSendEnvelope: ' + e.getMessage());
            throw new AuraHandledException('Network error communicating with DocuSign: ' + e.getMessage());
        } catch (JSONException e) {
            System.debug('JSON error in createAndSendEnvelope: ' + e.getMessage());
            throw new AuraHandledException('Error processing DocuSign response: ' + e.getMessage());
        }
    }

    private static String createRecipientView(
        String envelopeId, String signerEmail, String signerName, String clientUserId, String returnUrl
    ) {
        try {
            // Validate inputs
            if (String.isBlank(envelopeId)) {
                throw new AuraHandledException('Envelope ID is required.');
            }
            if (String.isBlank(clientUserId)) {
                throw new AuraHandledException('Client User ID is required for embedded signing.');
            }

            System.debug('Creating recipient view for clientUserId: ' + clientUserId);
            System.debug('Envelope ID: ' + envelopeId);
            System.debug('Return URL: ' + returnUrl);

            // FIXED: Enhanced recipient view request with proper authentication
            Map<String,Object> viewRequest = new Map<String,Object>{
                'returnUrl' => returnUrl,
                'authenticationMethod' => 'none', // Important: Use 'none' for embedded signing
                'email' => signerEmail.trim(),
                'userName' => signerName.trim(),
                'clientUserId' => clientUserId.trim(), // Must match the one used in envelope creation
                'pingFrequency' => 600, // Optional: Keep session alive (10 minutes)
                'pingUrl' => returnUrl // Optional: Where to ping
            };

            // Add frameAncestors for Salesforce embedding if needed
            String orgBaseUrl = URL.getOrgDomainUrl().toExternalForm();
            if (!String.isBlank(orgBaseUrl)) {
                viewRequest.put('frameAncestors', new List<String>{orgBaseUrl});
            }

            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:' + NAMED_CREDENTIAL + '/v2.1/accounts/' + accountId()
                            + '/envelopes/' + envelopeId.trim() + '/views/recipient');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept', 'application/json');
            req.setTimeout(120000);
            
            String requestBody = JSON.serialize(viewRequest);
            req.setBody(requestBody);

            // Add debug logging
            System.debug('Recipient View Request Body: ' + requestBody);

            Http http = new Http();
            HTTPResponse res = http.send(req);
            
            System.debug('Recipient View Response Status: ' + res.getStatusCode());
            System.debug('Recipient View Response Body: ' + res.getBody());
            
            // Enhanced error handling
            if (res.getStatusCode() >= 300) {
                String errorBody = res.getBody();
                System.debug('DocuSign Recipient View Error: ' + errorBody);
                
                try {
                    Map<String,Object> errorResponse = (Map<String,Object>) JSON.deserializeUntyped(errorBody);
                    String errorMsg = (String) errorResponse.get('message');
                    if (!String.isBlank(errorMsg)) {
                        throw new AuraHandledException('DocuSign Error: ' + errorMsg);
                    }
                } catch (JSONException je) {
                    // If we can't parse the error, use the raw response
                }
                
                throw new AuraHandledException('DocuSign recipient view error (Status: ' + res.getStatusCode() + '): ' + errorBody);
            }
            
            Map<String,Object> responseBody = (Map<String,Object>) JSON.deserializeUntyped(res.getBody());
            String signingUrl = (String) responseBody.get('url');
            
            if (String.isBlank(signingUrl)) {
                throw new AuraHandledException('DocuSign did not return a signing URL.');
            }
            
            System.debug('Successfully created recipient view URL (length: ' + signingUrl.length() + ')');
            return signingUrl;
            
        } catch (CalloutException e) {
            System.debug('Callout error in createRecipientView: ' + e.getMessage());
            throw new AuraHandledException('Network error communicating with DocuSign: ' + e.getMessage());
        } catch (JSONException e) {
            System.debug('JSON error in createRecipientView: ' + e.getMessage());
            throw new AuraHandledException('Error processing DocuSign response: ' + e.getMessage());
        }
    }

    // ============================================================================
    // UTILITY METHODS
    // ============================================================================

    @AuraEnabled(cacheable=false)
    public static List<Map<String,String>> getPdfContentBase64(List<String> contentVersionIds) {
        try {
            List<Map<String,String>> results = new List<Map<String,String>>();
            
            List<ContentVersion> versions = [
                SELECT Id, Title, VersionData
                FROM ContentVersion
                WHERE Id IN :contentVersionIds
            ];
            
            for (ContentVersion cv : versions) {
                String base64Data = EncodingUtil.base64Encode(cv.VersionData);
                results.add(new Map<String,String>{
                    'title' => cv.Title,
                    'base64' => base64Data
                });
            }
            
            return results;
        } catch (Exception e) {
            System.debug('Error getting PDF content: ' + e.getMessage());
            throw new AuraHandledException('Error retrieving PDF content: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static String generateUniqueClientUserId(String prefix) {
        if (String.isBlank(prefix)) {
            prefix = 'client';
        }
        return prefix + '_' + String.valueOf(Datetime.now().getTime()) + '_' + String.valueOf(Math.random()).substring(2, 8);
    }

    @AuraEnabled(cacheable=false)
    public static List<Map<String,Object>> getDocuSignTemplates() {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:' + NAMED_CREDENTIAL + '/v2.1/accounts/' + accountId() + '/templates');
            req.setMethod('GET');
            req.setHeader('Accept', 'application/json');
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                Map<String,Object> response = (Map<String,Object>) JSON.deserializeUntyped(res.getBody());
                List<Object> templates = (List<Object>) response.get('envelopeTemplates');
                
                List<Map<String,Object>> templateList = new List<Map<String,Object>>();
                for (Object templateObj : templates) {
                    Map<String,Object> template = (Map<String,Object>) templateObj;
                    templateList.add(new Map<String,Object>{
                        'templateId' => template.get('templateId'),
                        'name' => template.get('name'),
                        'description' => template.get('description')
                    });
                }
                return templateList;
            }
            
            throw new AuraHandledException('Error retrieving templates: ' + res.getBody());
            
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving DocuSign templates: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<Map<String,Object>> getEnvelopeDocuments(String envelopeId) {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:' + NAMED_CREDENTIAL + '/v2.1/accounts/' + accountId() + 
                           '/envelopes/' + envelopeId + '/documents');
            req.setMethod('GET');
            req.setHeader('Accept', 'application/json');
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                Map<String,Object> response = (Map<String,Object>) JSON.deserializeUntyped(res.getBody());
                List<Object> documents = (List<Object>) response.get('envelopeDocuments');
                
                List<Map<String,Object>> docList = new List<Map<String,Object>>();
                for (Object docObj : documents) {
                    Map<String,Object> doc = (Map<String,Object>) docObj;
                    docList.add(new Map<String,Object>{
                        'documentId' => doc.get('documentId'),
                        'name' => doc.get('name'),
                        'type' => doc.get('type'),
                        'order' => doc.get('order')
                    });
                }
                return docList;
            }
            
            throw new AuraHandledException('Error getting envelope documents: ' + res.getBody());
            
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving documents: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static Map<String,Object> checkEnvelopeStatus(String envelopeId) {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:' + NAMED_CREDENTIAL + '/v2.1/accounts/' + accountId() + '/envelopes/' + envelopeId);
            req.setMethod('GET');
            req.setHeader('Accept', 'application/json');
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                return (Map<String,Object>) JSON.deserializeUntyped(res.getBody());
            } else {
                throw new AuraHandledException('Error checking envelope status: ' + res.getBody());
            }
            
        } catch (Exception e) {
            throw new AuraHandledException('Error checking envelope status: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static EnvelopeStatusResult getEnvelopeStatus(String envelopeId) {
        try {
            Map<String,Object> statusData = checkEnvelopeStatus(envelopeId);
            
            Map<String,Object> recipients = (Map<String,Object>) statusData.get('recipients');
            if (recipients != null) {
                List<Object> signers = (List<Object>) recipients.get('signers');
                if (!signers.isEmpty()) {
                    Map<String,Object> signer = (Map<String,Object>) signers[0];
                    
                    EnvelopeStatusResult result = new EnvelopeStatusResult();
                    result.status = (String) signer.get('status');
                    result.signedDateTime = (String) signer.get('signedDateTime');
                    result.isComplete = 'completed'.equals(result.status);
                    return result;
                }
            }
            
            EnvelopeStatusResult result = new EnvelopeStatusResult();
            result.errorMessage = 'No signer information found';
            return result;
            
        } catch (Exception e) {
            EnvelopeStatusResult result = new EnvelopeStatusResult();
            result.errorMessage = e.getMessage();
            return result;
        }
    }

    @AuraEnabled(cacheable=false)
    public static Boolean downloadAndAttachSignedDocument(String envelopeId, Id applicationId) {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:' + NAMED_CREDENTIAL + '/v2.1/accounts/' + accountId() + 
                           '/envelopes/' + envelopeId + '/documents/combined');
            req.setMethod('GET');
            req.setHeader('Accept', 'application/pdf');
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                ContentVersion cv = new ContentVersion(
                    Title = 'Signed Document - ' + Datetime.now().format('yyyy-MM-dd HH:mm'),
                    PathOnClient = 'signed-document-' + envelopeId + '.pdf',
                    VersionData = res.getBodyAsBlob(),
                    FirstPublishLocationId = applicationId,
                    IsMajorVersion = true
                );
                insert cv;
                
                System.debug('Signed document attached successfully');
                return true;
            }
            
            return false;
            
        } catch (Exception e) {
            System.debug('Error downloading signed document: ' + e.getMessage());
            return false;
        }
    }

    // ============================================================================
    // HELPER METHODS
    // ============================================================================

    private static Blob getLatestLinkedPdf(Id applicationId) {
        try {
            // Get linked documents
            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId, ContentDocument.Title
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :applicationId
                ORDER BY SystemModstamp DESC
                LIMIT 50
            ];
            
            if (links.isEmpty()) {
                throw new AuraHandledException('No files are linked to this Application.');
            }

            Set<Id> docIds = new Set<Id>();
            for (ContentDocumentLink link : links) {
                docIds.add(link.ContentDocumentId);
            }

            // Get latest PDF version - Fixed query to handle no results
            List<ContentVersion> versions = [
                SELECT Id, Title, FileExtension, VersionData, IsLatest, ContentDocumentId, CreatedDate
                FROM ContentVersion
                WHERE ContentDocumentId IN :docIds 
                AND FileExtension = 'pdf' 
                AND IsLatest = true
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            
            if (versions.isEmpty()) {
                throw new AuraHandledException('No PDF files found on this Application.');
            }
            
            ContentVersion latestPdf = versions[0];
            if (latestPdf.VersionData == null) {
                throw new AuraHandledException('PDF content is empty or corrupted.');
            }
            
            System.debug('Found PDF: ' + latestPdf.Title + ' (Size: ' + latestPdf.VersionData.size() + ' bytes)');
            return latestPdf.VersionData;
            
        } catch (QueryException e) {
            System.debug('Query error in getLatestLinkedPdf: ' + e.getMessage());
            throw new AuraHandledException('Error retrieving PDF: ' + e.getMessage());
        }
    }



//     @AuraEnabled
//     public static void sendEnvelopeWithTabs(Id applicationId, List<Id> contentVersionIds) {
        
//         // 1. Get the Customer Name (Customer_Name__c) from Application__c
//         Application__c app = [
//             SELECT Id, Customer_Name__c
//             FROM Application__c
//             WHERE Id = :applicationId
//             LIMIT 1
//         ];

//         if (app.Customer_Name__c == null) {
//             throw new AuraHandledException('Application is not linked to a Customer.');
//         }

//         // 2. Create the envelope (empty envelope)
//         dfsle.Envelope myEnvelope = dfsle.EnvelopeService.getEmptyEnvelope(
//             new dfsle.Entity(applicationId)
//         );

//         // 3. Add documents to the envelope
//         Set<Id> contentVersionIdSet = new Set<Id>(contentVersionIds);
//         myEnvelope = myEnvelope.withDocuments(
//             dfsle.DocumentService.getDocuments(ContentVersion.SObjectType, contentVersionIdSet)
//         );

// // 4. Create Tabs for Sign Here and Date Signed - for ALL documents
//     List<dfsle.Tab> tabList = new List<dfsle.Tab>();
//     Integer docIndex = 1;

//     for (Id cvId : contentVersionIds) {
//         // Add Sign Here Tab for each document
//         tabList.add(
//             new dfsle.SignHereTab()
//                 .withRequired(true)
//                 .withPosition(new dfsle.Tab.Position(docIndex, 1, 100, 700, 100, 20))
//         );

//         // Add Date Signed Tab for each document
//         tabList.add(
//             new dfsle.DateSignedTab()
//                 .withPosition(new dfsle.Tab.Position(docIndex, 1, 250, 720, 100, 20))
//         );

//         docIndex++;
//     }

//     // 5. Create a recipient using the Customer Name (Customer_Name__c)
//     dfsle.Recipient myRecipient = dfsle.Recipient.fromSource(
//         app.Customer_Name__c,  // Customer Name as the recipient
//         'ghulam.mohayyudin@dtcforce.com',  // Adjust this with actual email logic
//         null,  // Signer phone number (optional)
//         'Signer 1',  // Signer role (optional)
//         null) // Salesforce association (optional)
//         .withTabs(tabList);

//         // 6. Add the recipient to the envelope
//         myEnvelope = myEnvelope.withRecipients(new List<dfsle.Recipient> { myRecipient });

//         // 7. Add email customization (e.g., email subject, message)
//         myEnvelope = myEnvelope.withEmail(
//             'Please review and sign the attached documents',
//             'Kindly review and sign all attached documents.'
//         );

//         // 8. Send the envelope
//         List<dfsle.Envelope> sentEnvelopes = new List<dfsle.Envelope>();
//         sentEnvelopes = dfsle.EnvelopeService.sendEnvelopes(
//             new List<dfsle.Envelope>{ myEnvelope } // The envelope to send
//         );
//         system.debug('savedEnvelopes:: '+sentEnvelopes);

//         // 9. Optionally save the sent envelope (if needed)
//        List<dfsle.Envelope> savedEnvelopes = dfsle.EnvelopeService.saveSentEnvelopes(sentEnvelopes);
       

//         // Log the result
//         System.debug('Envelope sent successfully: ' + myEnvelope);
//     }

public class DocuSignConsentResult {
    @AuraEnabled public Boolean requiresConsent;
    @AuraEnabled public String loginUrl;
    @AuraEnabled public String message;
}


// /**********************************************************************************************
//      * @description       : Sends DocuSign envelope with tabs and handles user consent
//      * @group             : DTCForce
//      * @created on        : 2025-01-13
//      * @created by        : GM
//      **********************************************************************************************/
//     @AuraEnabled
//     public static DocuSignConsentResult sendEnvelopeWithTabs(
//         Id applicationId,
//         List<Id> contentVersionIds
//     ) {
//         DocuSignConsentResult result = new DocuSignConsentResult();

//         try {
//             // Attempt normal send
//             sendEnvelopeInternal(applicationId, contentVersionIds);

//             result.requiresConsent = false;
//             result.message = 'Envelope sent successfully';
//             return result;
//         }
//         catch (dfsle.APIException ex) {
//             system.debug('ex:: '+ex.error.code);
//             // 🔐 DOCUSIGN CONSENT REQUIRED
//               if (ex.error.code == dfsle.APIErrorCode.CONSENT_REQUIRED) {

//                 // Preserve original transaction
//                 Map<String, Object> stateData = new Map<String, Object>{
//                     'applicationId' => applicationId,
//                     'contentVersionIds' => contentVersionIds
//                 };

//                 String state =
//                     EncodingUtil.urlEncode(
//                         JSON.serialize(stateData),
//                         'UTF-8'
//                     );

//                 // Experience Cloud relative URL
//                 String redirectUrl = '/s/docusign-consent';

//                 result.requiresConsent = true;
//                 result.loginUrl = dfsle.AuthService.getLoginUrl(redirectUrl).toExternalForm();
//                 result.message = 'User consent required';

//                 return result;
//             }

//             throw ex;
//         }
//     }

//     /**********************************************************************************************
//      * @description       : Internal method that builds and sends the DocuSign envelope
//      * @group             : DTCForce
//      * @created on        : 2025-01-13
//      * @created by        : GM
//      **********************************************************************************************/
//     private static void sendEnvelopeInternal(
//         Id applicationId,
//         List<Id> contentVersionIds
//     ) {
//         // 1. Fetch Application
//         Application__c app = [
//             SELECT Id, Customer_Name__c
//             FROM Application__c
//             WHERE Id = :applicationId
//             LIMIT 1
//         ];

//         if (app.Customer_Name__c == null) {
//             throw new AuraHandledException(
//                 'Application is not linked to a Customer.'
//             );
//         }

//         // 2. Create Envelope
//         dfsle.Envelope envelope =
//             dfsle.EnvelopeService.getEmptyEnvelope(
//                 new dfsle.Entity(applicationId)
//             );

//         // 3. Attach Documents
//         envelope = envelope.withDocuments(
//             dfsle.DocumentService.getDocuments(
//                 ContentVersion.SObjectType,
//                 new Set<Id>(contentVersionIds)
//             )
//         );

//         // 4. Create Tabs
//         List<dfsle.Tab> tabs = new List<dfsle.Tab>();
//         Integer docIndex = 1;

//         for (Id cvId : contentVersionIds) {
//             tabs.add(
//                 new dfsle.SignHereTab()
//                     .withRequired(true)
//                     .withPosition(
//                         new dfsle.Tab.Position(
//                             docIndex, 1, 100, 700, 100, 20
//                         )
//                     )
//             );

//             tabs.add(
//                 new dfsle.DateSignedTab()
//                     .withPosition(
//                         new dfsle.Tab.Position(
//                             docIndex, 1, 250, 720, 100, 20
//                         )
//                     )
//             );
//             docIndex++;
//         }

//         // 5. Recipient
//         dfsle.Recipient recipient =
//             dfsle.Recipient.fromSource(
//                 app.Customer_Name__c,
//                 'ghulam.mohayyudin@dtcforce.com',
//                 null,
//                 'Signer 1',
//                 null
//             ).withTabs(tabs);

//         // 6. Finalize Envelope
//         envelope = envelope
//             .withRecipients(new List<dfsle.Recipient>{ recipient })
//             .withEmail(
//                 'Please review and sign the attached documents',
//                 'Kindly review and sign all attached documents.'
//             );

//         // 7. Send
//         List<dfsle.Envelope> sent =
//             dfsle.EnvelopeService.sendEnvelopes(
//                 new List<dfsle.Envelope>{ envelope }
//             );

//         dfsle.EnvelopeService.saveSentEnvelopes(sent);
//     }


/**********************************************************************************************
 * @description       : Sends DocuSign envelope with tabs and handles user consent
 * @group             : DTCForce
 * @created on        : 2025-01-13
 * @created by        : GM
 **********************************************************************************************/
@AuraEnabled
public static DocuSignConsentResult sendEnvelopeWithTabs(
    Id applicationId,
    List<Id> contentVersionIds
) {
    DocuSignConsentResult result = new DocuSignConsentResult();

    // try {
        // 1. Fetch Application
        Application__c app = [
            SELECT Id, Customer_Name__c
            FROM Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ];

        if (app.Customer_Name__c == null) {
            throw new AuraHandledException(
                'Application is not linked to a Customer.'
            );
        }

        // 2. Create Envelope
        dfsle.Envelope envelope =
            dfsle.EnvelopeService.getEmptyEnvelope(
                new dfsle.Entity(applicationId)
            );

        // 3. Attach Documents
        envelope = envelope.withDocuments(
            dfsle.DocumentService.getDocuments(
                ContentVersion.SObjectType,
                new Set<Id>(contentVersionIds)
            )
        );

        // 4. Create Tabs
        List<dfsle.Tab> tabs = new List<dfsle.Tab>();
        Integer docIndex = 1;

        for (Id cvId : contentVersionIds) {
            tabs.add(
                new dfsle.SignHereTab()
                    .withRequired(true)
                    .withPosition(
                        new dfsle.Tab.Position(
                            docIndex, 1, 100, 700, 100, 20
                        )
                    )
            );

            tabs.add(
                new dfsle.DateSignedTab()
                    .withPosition(
                        new dfsle.Tab.Position(
                            docIndex, 1, 250, 720, 100, 20
                        )
                    )
            );
            docIndex++;
        }

        // 5. Recipient
        dfsle.Recipient recipient =
            dfsle.Recipient.fromSource(
                app.Customer_Name__c,
                'ghulam.mohayyudin@dtcforce.com',
                null,
                'Signer 1',
                null
            ).withTabs(tabs);

        // 6. Finalize Envelope
        envelope = envelope
            .withRecipients(new List<dfsle.Recipient>{ recipient })
            .withEmail(
                'Please review and sign the attached documents',
                'Kindly review and sign all attached documents.'
            );

            try {
    dfsle.EnvelopeService.sendEnvelope(envelope, true);
} catch (dfsle.APIException ex) {
    if (ex.error.code == dfsle.APIErrorCode.CONSENT_REQUIRED) {
        System.debug('DocuSign API Exception: ' + ex);

        // 🔐 CORRECT CONSENT CHECK (THIS WAS YOUR BUG)
        if (ex.error.Code == dfsle.APIErrorCode.CONSENT_REQUIRED) {

            // Experience Cloud relative redirect
            String redirectUrl = '/docusign-consent';
            Url loginUrl = dfsle.AuthService.getLoginUrl('lightning/page/home');
            System.debug(loginUrl.toExternalForm());
            // result.requiresConsent = true;
            //     result.loginUrl = dfsle.AuthService.getLoginUrl(redirectUrl).toExternalForm();
            result.requiresConsent = true;
                result.loginUrl = loginUrl.toExternalForm();
            system.debug('loginUrl:: '+result.loginUrl);
            result.message = 'User consent required';
            return result;
        }
    }
}

        // // 7. Send Envelope
        // List<dfsle.Envelope> sent =
        //     dfsle.EnvelopeService.sendEnvelopes(
        //         new List<dfsle.Envelope>{ envelope }
        //     );

        //dfsle.EnvelopeService.saveSentEnvelopes(sent);

        // ✅ SUCCESS RESPONSE
        result.requiresConsent = false;
        result.message = 'Envelope sent successfully';
        return result;
    // }
    // catch (dfsle.DocuSignException ex) {

    //     System.debug('DocuSign API Exception: ' + ex);

    //     // 🔐 CORRECT CONSENT CHECK (THIS WAS YOUR BUG)
    //     if (ex.error.Code == dfsle.APIErrorCode.CONSENT_REQUIRED) {

    //         // Experience Cloud relative redirect
    //         String redirectUrl = '/s/docusign-consent';

    //         result.requiresConsent = true;
    //             result.loginUrl = dfsle.AuthService.getLoginUrl(redirectUrl).toExternalForm();

    //         result.message = 'User consent required';
    //         return result;
    //     }

    //     // ❌ Any other DocuSign error
    //     throw ex;
    // }
}

}