/**
 * CancellationPdfService
 *
 * Renders the cancellation form as a PDF (CancellationRequestPdf, a Visualforce
 * page with renderAs="pdf") and publishes it onto the App_Cancellation_Request__c
 * record as a ContentVersion, so the document sits in the record's Files next to
 * the raw signature PNG.
 *
 * `without sharing`: the request is already owned by the Sales review queue by the
 * time this runs, so the dealer who submitted it has no record access.
 *
 * Nothing here may throw into the submit path. Callers wrap every call; a failed
 * PDF must never cost the dealer the request.
 */
public without sharing class CancellationPdfService {

    public class PdfResult {
        public Id contentVersionId;
        public String error;
        public Boolean getSucceeded() {
            return contentVersionId != null;
        }
    }

    /** Renders and attaches the PDF for one request. Never throws. */
    public static PdfResult generateAndAttach(Id requestId) {
        PdfResult result = new PdfResult();
        if (requestId == null) {
            result.error = 'No request id was supplied.';
            return result;
        }

        Blob body;
        try {
            PageReference page = Page.CancellationRequestPdf;
            page.getParameters().put('id', String.valueOf(requestId));
            page.setRedirect(false);
            body = page.getContentAsPDF();
        } catch (Exception e) {
            result.error = 'PDF could not be rendered: ' + e.getMessage();
            return result;
        }

        if (body == null || body.size() == 0) {
            result.error = 'PDF rendering returned no content.';
            return result;
        }

        try {
            result.contentVersionId = attach(requestId, body);
        } catch (Exception e) {
            result.error = 'PDF could not be attached: ' + e.getMessage();
        }
        return result;
    }

    private static Id attach(Id requestId, Blob body) {
        String requestName = String.valueOf(requestId);
        try {
            List<App_Cancellation_Request__c> rows = [
                SELECT Id, Name FROM App_Cancellation_Request__c WHERE Id = :requestId LIMIT 1
            ];
            if (!rows.isEmpty() && String.isNotBlank(rows[0].Name)) {
                requestName = rows[0].Name;
            }
        } catch (Exception ignored) {
            // A missing label must never stop the document being stored.
        }

        String title = 'Cancellation Request ' + requestName;
        Id contentVersionId = null;

        // Preferred: publish the document straight onto the request.
        try {
            ContentVersion published = new ContentVersion(
                Title = title,
                PathOnClient = safeFileName(requestName) + '.pdf',
                VersionData = body,
                FirstPublishLocationId = requestId
            );
            Database.insert(published, AccessLevel.SYSTEM_MODE);
            contentVersionId = published.Id;
        } catch (Exception publishError) {
            // Same fallback the signature uses: store the file in the user's
            // library and link it to the record where that is permitted.
            ContentVersion stored = new ContentVersion(
                Title = title,
                PathOnClient = safeFileName(requestName) + '.pdf',
                VersionData = body
            );
            Database.insert(stored, AccessLevel.SYSTEM_MODE);
            contentVersionId = stored.Id;
            try {
                Id documentId = [
                    SELECT ContentDocumentId FROM ContentVersion WHERE Id = :stored.Id LIMIT 1
                ].ContentDocumentId;
                insert new ContentDocumentLink(
                    ContentDocumentId = documentId,
                    LinkedEntityId = requestId,
                    ShareType = 'V'
                );
            } catch (Exception linkError) {
                // An unlinked document is still better than none; the id is on the record.
            }
        }

        update new App_Cancellation_Request__c(
            Id = requestId,
            Pdf_Content_Version_Id__c = contentVersionId
        );
        return contentVersionId;
    }

    private static String safeFileName(String requestName) {
        if (String.isBlank(requestName)) {
            return 'Cancellation-Request';
        }
        return ('Cancellation-Request-' + requestName).replaceAll('[^A-Za-z0-9\\-]', '-');
    }
}