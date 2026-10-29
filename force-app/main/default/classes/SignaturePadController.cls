/**
 * SignaturePadController
 * Thin @AuraEnabled facade over SignatureService for the dealer portal signature pad.
 *
 * One method = one server call = one transaction. Never chain stageImage() or
 * issuePdf() into saveSignature(): a callout after DML raises
 * "uncommitted work pending". The LWC calls them sequentially.
 *
 * Three signers (Customer, DealerRep, ContractHolder) are captured in one modal
 * session; saveSignature/stageImage are called once per role, issuePdf once.
 */
public with sharing class SignaturePadController {

    /** The document preview returned to the pad's left pane. */
    public class PreviewResult {
        @AuraEnabled public Boolean ok;
        /** Same-origin Visualforce PDF path, e.g. "/apex/Page?id=...&docType=Warranty". */
        @AuraEnabled public String url;
        @AuraEnabled public String message;
    }

    /** Logged-in user's display name, used to prefill the signer field. */
    @AuraEnabled(cacheable=true)
    public static String currentUserName() {
        try {
            String n = UserInfo.getName();
            return String.isBlank(n) ? '' : n;
        } catch (Exception e) {
            return '';
        }
    }

    /** Never throws: the pad must still open if the status read fails. */
    @AuraEnabled(cacheable=true)
    public static SignatureService.SignatureStatus getStatus(Id applicationId, String documentType) {
        try {
            return SignatureService.getStatus(applicationId, documentType);
        } catch (Exception e) {
            SignatureService.SignatureStatus empty = new SignatureService.SignatureStatus();
            empty.hasSignature = false;
            empty.allRolesCaptured = false;
            empty.hasPdf = false;
            empty.roles = new List<SignatureService.RoleState>();
            return empty;
        }
    }

    /** One @AuraEnabled entry point only: Aura cannot resolve overloads by arity. */
    @AuraEnabled
    public static SignatureService.SaveResult saveSignature(Id applicationId, String pngB64,
            String signedBy, String idemKey, String documentType, String signerRole) {
        try {
            return SignatureService.saveSignature(applicationId, pngB64, signedBy, idemKey,
                documentType, signerRole);
        } catch (Exception e) {
            throw new AuraHandledException(friendly(e));
        }
    }

    @AuraEnabled
    public static String stageImage(Id signatureId) {
        try {
            return SignatureService.stageImage(signatureId);
        } catch (Exception e) {
            throw new AuraHandledException(friendly(e));
        }
    }

    @AuraEnabled
    public static String issuePdf(Id signatureId) {
        try {
            return SignatureService.issuePdf(signatureId);
        } catch (Exception e) {
            throw new AuraHandledException(friendly(e));
        }
    }

    @AuraEnabled
    public static void dropResource(Id signatureId) {
        try {
            SignatureService.dropResource(signatureId);
        } catch (Exception e) {
            throw new AuraHandledException(friendly(e));
        }
    }

    /**
     * The URL the pad frames for the contract preview.
     *
     * Deliberately NOT a Blob URL: an Experience Cloud page runs under a CSP that
     * blocks blob: frames ("This content is blocked"). The contract page is
     * already renderAs="pdf", so pointing the iframe at the same-origin
     * Visualforce URL returns application/pdf inline - the browser's own PDF
     * viewer renders it inside the pane.
     *
     * The path is relative to the site root: the component prefixes the site
     * base (/<urlPathPrefix>) from window.location, so it stays same-origin.
     *
     * The `docType` parameter is the same one issuePdf sends, so the preview
     * shows exactly the ONE document the PDF will contain.
     *
     * Never throws: a preview problem must not block signing.
     */
    @AuraEnabled(cacheable=true)
    public static PreviewResult getPreview(Id applicationId, String documentType) {
        PreviewResult r = new PreviewResult();
        r.ok = false;
        if (applicationId == null) {
            r.message = 'No application selected.';
            return r;
        }
        try {
            String docType = SignatureDocument.normaliseDocumentType(documentType);
            String rt = SignatureDocument.recordTypeKey(applicationId, docType);
            if (String.isBlank(rt)) {
                r.message = 'This application has no ' + SignatureDocument.documentLabel(docType)
                    + ' document to preview.';
                return r;
            }
            r.url = previewPath(applicationId, docType);
            r.ok = true;
            return r;
        } catch (Exception e) {
            r.message = 'The document preview is unavailable.';
            return r;
        }
    }

    /**
     * The submit gate's state for this application: which contract documents it
     * carries, whether each is fully signed, and the exact sentence SUBMIT shows
     * while blocked. Same rule the server enforces on submit
     * (SignatureSubmitGuard) - the button and the server cannot disagree.
     */
    @AuraEnabled(cacheable=false)
    public static SignatureSubmitGuard.Requirements getSignatureRequirements(Id applicationId) {
        return SignatureSubmitGuard.forApplication(applicationId);
    }

    /**
     * The same-origin PDF path for one application + document type. Public so the
     * URL shape is unit-testable without an application that carries packages.
     */
    public static String previewPath(Id applicationId, String documentType) {
        return '/apex/DealerPortalVehicleApplicationPDFs?id=' + String.valueOf(applicationId)
            + '&docType=' + EncodingUtil.urlEncode(documentType, 'UTF-8');
    }

    private static String friendly(Exception e) {
        String m = e.getMessage();
        if (String.isBlank(m)) {
            m = e.getTypeName();
        }
        return m != null && m.length() > 900 ? m.left(900) : m;
    }
}