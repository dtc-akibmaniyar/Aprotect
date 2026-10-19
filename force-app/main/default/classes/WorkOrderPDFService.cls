/**
 * Saves and sends the work order document (TASK-050, requirement 3).
 *
 * Backs the workOrderPdfPreview LWC, which Osama specified on 2026-10-08:
 * the button shows the PDF, with Save PDF, Save and Send PDF, and Cancel.
 *
 * Follows QuotePDFGeneratorService, the pattern already working on this org:
 * render the Visualforce page to a Blob, store it as a ContentVersion, and add
 * later renders as new VERSIONS of the same ContentDocument rather than as
 * separate files, so a work order accumulates a history instead of a pile of
 * near-identical attachments. The Test.isRunningTest guard is required, not
 * defensive: PageReference.getContentAsPDF throws in a test context.
 */
public with sharing class WorkOrderPDFService {

    private static final String TITLE_PREFIX = 'Work Order';

    public class PdfResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String fileName;
        @AuraEnabled public Id contentVersionId;
        @AuraEnabled public Id contentDocumentId;
        /** Populated only by saveAndSend, so the screen can say who it went to. */
        @AuraEnabled public List<String> sentTo;
    }

    /**
     * What the preview screen needs before it renders: the recipients, so the
     * agent sees who this will go to BEFORE sending, and the page url for the
     * preview frame.
     */
    public class PreviewContext {
        @AuraEnabled public String workOrderName;
        @AuraEnabled public String claimName;
        @AuraEnabled public String customerName;
        @AuraEnabled public String customerEmail;
        @AuraEnabled public String repairShopName;
        @AuraEnabled public String repairShopEmail;
        @AuraEnabled public String pdfUrl;
    }

    @AuraEnabled
    public static PreviewContext getPreviewContext(Id workOrderId) {
        List<Work_Order__c> found = [
            SELECT Id, Name, Claim__r.Name, Customer_Name__c, Customer_Email__c,
                   Repair_Shop__r.Name, Repair_Shop__r.Email__c
            FROM Work_Order__c WHERE Id = :workOrderId
            WITH USER_MODE
        ];
        if (found.isEmpty()) {
            throw badRequest('That work order could not be found, or you do not have access to it.');
        }
        Work_Order__c wo = found[0];

        PreviewContext c = new PreviewContext();
        c.workOrderName    = wo.Name;
        c.claimName        = wo.Claim__r?.Name;
        c.customerName     = wo.Customer_Name__c;
        c.customerEmail    = wo.Customer_Email__c;
        c.repairShopName   = wo.Repair_Shop__r?.Name;
        c.repairShopEmail  = wo.Repair_Shop__r?.Email__c;
        c.pdfUrl           = '/apex/WorkOrderPDF?id=' + workOrderId;
        return c;
    }

    /** Save PDF. Stores the document against the work order and returns it. */
    @AuraEnabled
    public static PdfResult savePdf(Id workOrderId) {
        return store(workOrderId, render(workOrderId));
    }

    /**
     * Save and Send PDF. Saves first, then emails the saved file, so a send
     * failure still leaves the document on the record rather than losing it.
     *
     * Recipients come from the screen rather than being re-derived here: the
     * agent can see and correct them before sending, and an empty list is
     * refused instead of silently sending to nobody.
     */
    @AuraEnabled
    public static PdfResult saveAndSendPdf(Id workOrderId, List<String> recipients) {
        List<String> clean = new List<String>();
        for (String r : (recipients == null ? new List<String>() : recipients)) {
            if (String.isNotBlank(r)) clean.add(r.trim());
        }
        if (clean.isEmpty()) {
            throw badRequest('Add at least one email address before sending.');
        }

        PdfResult result = store(workOrderId, render(workOrderId));

        Work_Order__c wo = [
            SELECT Id, Name, Claim__r.Name, Customer_Name__c
            FROM Work_Order__c WHERE Id = :workOrderId
            WITH USER_MODE
        ];

        Messaging.EmailFileAttachment att = new Messaging.EmailFileAttachment();
        att.setFileName(result.fileName);
        att.setBody([
            SELECT VersionData FROM ContentVersion WHERE Id = :result.contentVersionId
            WITH USER_MODE
        ].VersionData);
        att.setContentType('application/pdf');

        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(clean);
        msg.setSubject('Work order ' + wo.Name + ' for authorization'
            + (String.isNotBlank(wo.Claim__r?.Name) ? ' - claim ' + wo.Claim__r.Name : ''));
        msg.setPlainTextBody(
            'Please find the attached work order for your review and authorization.\n\n'
            + (String.isNotBlank(wo.Customer_Name__c) ? 'Customer: ' + wo.Customer_Name__c + '\n' : '')
            + 'Work order: ' + wo.Name + '\n'
            + (String.isNotBlank(wo.Claim__r?.Name) ? 'Claim: ' + wo.Claim__r.Name + '\n' : '')
            + '\nA-Protect Warranty');
        msg.setFileAttachments(new List<Messaging.EmailFileAttachment>{ att });
        // The work order is the record this correspondence belongs against.
        msg.setWhatId(workOrderId);
        msg.setSaveAsActivity(false);

        if (!Test.isRunningTest()) {
            List<Messaging.SendEmailResult> sent = Messaging.sendEmail(
                new List<Messaging.SingleEmailMessage>{ msg }, false);
            if (!sent.isEmpty() && !sent[0].isSuccess()) {
                String why = sent[0].getErrors().isEmpty()
                    ? 'unknown reason' : sent[0].getErrors()[0].getMessage();
                // The document IS saved at this point, so say so rather than
                // leaving the agent thinking nothing happened.
                throw badRequest('The work order was saved to the record, but the email could not be sent: ' + why);
            }
        }

        result.sentTo = clean;
        return result;
    }

    // ───────────────────────────── internals ─────────────────────────────

    private static Blob render(Id workOrderId) {
        PageReference page = new PageReference('/apex/WorkOrderPDF');
        page.getParameters().put('id', workOrderId);
        // getContentAsPDF cannot run in a test context, so stand in a blob.
        return Test.isRunningTest() ? Blob.valueOf('Test PDF Content') : page.getContentAsPDF();
    }

    /**
     * Stores the blob against the work order, as a new version of the existing
     * work order document when there is one.
     */
    private static PdfResult store(Id workOrderId, Blob pdf) {
        Work_Order__c wo = [
            SELECT Id, Name FROM Work_Order__c WHERE Id = :workOrderId WITH USER_MODE
        ];

        List<ContentDocumentLink> existing = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :workOrderId
              AND ContentDocument.Title LIKE :(TITLE_PREFIX + '%')
            ORDER BY ContentDocument.CreatedDate DESC
            LIMIT 1
        ];

        String title = TITLE_PREFIX + ' - ' + wo.Name;
        String fileName = title + ' - ' + String.valueOf(Date.today()) + '.pdf';

        ContentVersion cv = new ContentVersion();
        cv.Title = title;
        cv.PathOnClient = fileName;
        cv.VersionData = pdf;
        if (!existing.isEmpty()) {
            cv.ContentDocumentId = existing[0].ContentDocumentId;
        } else {
            cv.FirstPublishLocationId = workOrderId;
        }
        insertSecured(new List<ContentVersion>{ cv });

        ContentVersion saved = [
            SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id
            WITH USER_MODE
        ];

        PdfResult r = new PdfResult();
        r.success = true;
        r.fileName = fileName;
        r.contentVersionId = saved.Id;
        r.contentDocumentId = saved.ContentDocumentId;
        return r;
    }

    private static void insertSecured(List<SObject> records) {
        if (records == null || records.isEmpty()) return;
        try {
            Database.insert(records, AccessLevel.USER_MODE);
        } catch (Exception ex) {
            throw badRequest('Could not save the work order document: ' + ex.getMessage());
        }
    }

    /**
     * AuraHandledException.getMessage() returns the useless "Script-thrown
     * exception" unless setMessage is called explicitly, which hides the real
     * cause from the screen. Same convention as ClaimEstimateService.
     */
    private static AuraHandledException badRequest(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}