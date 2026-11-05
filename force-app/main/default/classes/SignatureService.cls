/**
 * SignatureService
 * Entry points, each its own transaction:
 *   saveSignature -> DML only (safe to call from a trigger / LWC imperative call)
 *   stageImage    -> callout FIRST, then DML. MUST be its own transaction.
 *   issuePdf      -> render only; requires both staged images COMMITTED.
 *   dropResource  -> callout, then DML.
 *
 * Two signers, one sitting: a contract carries a Customer and a Dealership Rep
 * signature. One row per application + document type + signer role, and ONE PDF
 * that carries both. The Customer signature also stands for the Contract Holder
 * line on the acknowledgement page, so no separate Contract Holder signing step
 * exists any more.
 *
 * Never chain saveSignature + stageImage inside one Apex transaction: the
 * callout after DML raises "uncommitted work pending". Let the LWC call them
 * separately.
 */
public without sharing class SignatureService {

    public static final String DOC_WARRANTY = 'Warranty';
    public static final String DOC_TIRE_RIM = 'TireRim';

    public static final String ROLE_CUSTOMER = 'Customer';
    public static final String ROLE_DEALER_REP = 'DealerRep';
    /**
     * Legacy role: no longer in ROLES and no longer part of the signing flow.
     * Retained so historical rows still normalise - removing this branch would
     * make effectiveRole() throw on legacy rows and fail the submit gate closed.
     */
    public static final String ROLE_CONTRACT_HOLDER = 'ContractHolder';

    /** Render order on the page, and the order the pad walks the dealer through. */
    public static final List<String> ROLES = new List<String>{
        ROLE_CUSTOMER, ROLE_DEALER_REP
    };

    public static final String ST_CAPTURED = 'CAPTURED';
    public static final String ST_RENDERED = 'RENDERED';
    public static final String ST_DONE = 'DONE';
    public static final String ST_RENDER_FAILED = 'RENDER_FAILED';

    /** base64 chars; ~150 KB decoded. Guards governor / payload sanity. */
    public static final Integer MAX_B64_CHARS = 200000;

    public class SignatureServiceException extends Exception {}

    public class SaveResult {
        @AuraEnabled public Id signatureId;
        @AuraEnabled public String status;
        @AuraEnabled public String pdfDocumentId;
        @AuraEnabled public Boolean created;
        @AuraEnabled public String signerRole;
    }

    public class RoleState {
        @AuraEnabled public String role;
        @AuraEnabled public Boolean captured;
        @AuraEnabled public Id signatureId;
        @AuraEnabled public String signedBy;
        @AuraEnabled public Datetime signedAt;
        @AuraEnabled public String status;
    }

    public class SignatureStatus {
        /** True only when both signer roles have captured ink. */
        @AuraEnabled public Boolean hasSignature;
        @AuraEnabled public Boolean allRolesCaptured;
        @AuraEnabled public Boolean hasPdf;
        /** Customer row, kept for callers written before the two-role build. */
        @AuraEnabled public Id signatureId;
        @AuraEnabled public String signedBy;
        @AuraEnabled public Datetime signedAt;
        @AuraEnabled public String status;
        @AuraEnabled public String pdfDocumentId;
        @AuraEnabled public String pdfContentDocumentId;
        /** Human name of the produced file, e.g. "Extended Warranty 2026-10-22 v1". */
        @AuraEnabled public String pdfFileName;
        @AuraEnabled public String renderError;
        @AuraEnabled public List<RoleState> roles;
    }

    // ------------------------------------------------------------------ capture

    /** Backwards-compatible entry point: an unspecified role is the Customer. */
    public static SaveResult saveSignature(Id applicationId, String pngB64, String signedBy,
                                           String idemKey, String documentType) {
        return saveSignature(applicationId, pngB64, signedBy, idemKey, documentType, ROLE_CUSTOMER);
    }

    /**
     * Captures one signer's ink.
     *
     * Idempotent twice over:
     *   - on IdemKey__c (a retry of the same gesture returns the same row);
     *   - per (application, document type, signer role): re-signing a role REUSES
     *     and updates that role's row instead of inserting a duplicate.
     */
    public static SaveResult saveSignature(Id applicationId, String pngB64, String signedBy,
                                           String idemKey, String documentType, String signerRole) {
        if (applicationId == null) {
            throw new SignatureServiceException('applicationId is required');
        }
        if (String.isBlank(idemKey)) {
            throw new SignatureServiceException('idemKey is required');
        }
        String docType = normaliseDocumentType(documentType);
        String role = normaliseRole(signerRole);
        String b64 = normaliseBase64(pngB64);
        Integer chars = b64.length();
        if (chars > MAX_B64_CHARS) {
            throw new SignatureServiceException('signature payload too large: ' + chars
                + ' base64 chars (max ' + MAX_B64_CHARS + ')');
        }
        if (!b64.startsWith('iVBORw0KGgo')) {
            throw new SignatureServiceException('payload is not a PNG (bad PNG signature)');
        }

        // 1. Same gesture replay.
        List<Application_Signature__c> existing = [
            SELECT Id, Status__c, Pdf_Document_Id__c, PngBytes__c, Signer_Role__c
            FROM Application_Signature__c
            WHERE IdemKey__c = :idemKey
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            Application_Signature__c row = existing[0];
            if (effectiveRole(row.Signer_Role__c) != role) {
                throw new SignatureServiceException('idempotency key ' + idemKey
                    + ' already used for signer role ' + effectiveRole(row.Signer_Role__c));
            }
            if (row.PngBytes__c != null && row.PngBytes__c != chars) {
                throw new SignatureServiceException('idempotency key ' + idemKey
                    + ' already used with a different payload size');
            }
            return toSaveResult(row, false, role);
        }

        // 2. One row per application + document type + role.
        Application_Signature__c sameRole = findRoleRow(applicationId, docType, role);
        if (sameRole != null) {
            // A fresh gesture for a role that already signed: replace the ink and
            // invalidate the old PDF so issuePdf renders again.
            Application_Signature__c upd = new Application_Signature__c(
                Id = sameRole.Id,
                Signer_Role__c = role,
                IdemKey__c = idemKey.trim(),
                PngB64__c = b64,
                PngBytes__c = chars,
                Signed_By__c = String.isBlank(signedBy) ? null : signedBy.trim().left(80),
                Signed_At__c = System.now(),
                Status__c = ST_CAPTURED,
                ResourceId__c = null,
                ResourceName__c = null,
                Pdf_Document_Id__c = null,
                Render_Error__c = null
            );
            update upd;
            return toSaveResult(upd, false, role);
        }

        Application_Signature__c sig = new Application_Signature__c(
            Application__c = applicationId,
            Document_Type__c = docType,
            Signer_Role__c = role,
            IdemKey__c = idemKey.trim(),
            PngB64__c = b64,
            PngBytes__c = chars,
            Signed_By__c = String.isBlank(signedBy) ? null : signedBy.trim().left(80),
            Signed_At__c = System.now(),
            Status__c = ST_CAPTURED
        );
        insert sig;
        return toSaveResult(sig, true, role);
    }

    // ------------------------------------------------------------------- stage

    /**
     * Uploads the captured PNG as a temporary StaticResource and stores the
     * pointer on the signature row. MUST be its own transaction / server call:
     * the pointer has to be COMMITTED before the contract page is rendered,
     * because Page.getContentAsPDF() does not see uncommitted DML.
     *
     * Idempotent: returns the existing committed pointer when one is present.
     * Callout first, DML after, so no "uncommitted work pending" is possible.
     */
    public static String stageImage(Id signatureId) {
        if (signatureId == null) {
            throw new SignatureServiceException('signatureId is required');
        }
        List<Application_Signature__c> rows = [
            SELECT Id, PngB64__c, ResourceId__c, ResourceName__c, Status__c
            FROM Application_Signature__c
            WHERE Id = :signatureId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new SignatureServiceException('signature not found: ' + signatureId);
        }
        Application_Signature__c sig = rows[0];
        if (String.isNotBlank(sig.ResourceId__c) && String.isNotBlank(sig.ResourceName__c)) {
            return sig.ResourceName__c;
        }
        if (String.isBlank(sig.PngB64__c)) {
            throw new SignatureServiceException('signature ' + signatureId + ' has no PNG payload');
        }

        String resourceName;
        String resourceId;
        try {
            resourceName = SignatureResourceClient.newResourceName();
            resourceId = SignatureResourceClient.createResource(resourceName, sig.PngB64__c);
        } catch (Exception e) {
            markFailed(sig.Id, e);
            throw new SignatureServiceException('stageImage failed for ' + signatureId + ': ' + safeMessage(e));
        }

        update new Application_Signature__c(
            Id = sig.Id,
            ResourceId__c = resourceId,
            ResourceName__c = resourceName,
            Render_Error__c = null
        );
        return resourceName;
    }

    // -------------------------------------------------------------------- render

    /**
     * Renders the contract page to PDF ONCE and stores it as a ContentVersion on
     * the application. Returns the ContentVersion id.
     *
     * The page resolves both signature blocks by role, so every role's image
     * must already be staged and committed. The id argument only selects the
     * application + document type (either one of the two rows will do).
     *
     * Failure: Status=RENDER_FAILED + Render_Error__c, no PDF, resource ids kept
     * so SignatureCleanup can sweep the orphan images.
     */
    public static String issuePdf(Id signatureId) {
        if (signatureId == null) {
            throw new SignatureServiceException('signatureId is required');
        }

        List<Application_Signature__c> rows = [
            SELECT Id, Name, Application__c, Document_Type__c, Signer_Role__c, PngB64__c,
                   ResourceId__c, ResourceName__c, Pdf_Document_Id__c, Status__c
            FROM Application_Signature__c
            WHERE Id = :signatureId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new SignatureServiceException('signature not found: ' + signatureId);
        }
        Application_Signature__c sig = rows[0];

        if ((sig.Status__c == ST_RENDERED || sig.Status__c == ST_DONE)
                && String.isNotBlank(sig.Pdf_Document_Id__c)) {
            return sig.Pdf_Document_Id__c;
        }
        if (sig.Application__c == null) {
            throw new SignatureServiceException('signature ' + signatureId + ' has no application');
        }

        List<Application_Signature__c> siblings = [
            SELECT Id, Signer_Role__c, PngB64__c, ResourceId__c, ResourceName__c,
                   Pdf_Document_Id__c, Status__c
            FROM Application_Signature__c
            WHERE Application__c = :sig.Application__c
              AND Document_Type__c = :sig.Document_Type__c
        ];
        Map<String, Application_Signature__c> byRole = new Map<String, Application_Signature__c>();
        for (Application_Signature__c r : siblings) {
            byRole.put(effectiveRole(r.Signer_Role__c), r);
        }

        List<String> missing = new List<String>();
        for (String role : ROLES) {
            Application_Signature__c r = byRole.get(role);
            if (r == null || String.isBlank(r.PngB64__c)
                    || String.isBlank(r.ResourceId__c) || String.isBlank(r.ResourceName__c)) {
                missing.add(role);
            }
        }
        if (!missing.isEmpty()) {
            throw new SignatureServiceException('both signers must be staged before rendering;'
                + ' missing staged image for: ' + String.join(missing, ', '));
        }

        try {
            // ONE document type per render. The contract page renders every
            // record type the application carries; its `docType` parameter
            // narrows the render to a single document. Without it ONE file would
            // carry the warranty AND the tire & rim variants, with only the
            // customer signature attached to either.
            String rtKey = SignatureDocument.recordTypeKey(sig.Application__c, sig.Document_Type__c);
            if (String.isBlank(rtKey)) {
                throw new SignatureServiceException('this application carries no active '
                    + SignatureDocument.documentLabel(sig.Document_Type__c) + ' document to render');
            }

            PageReference pr = Page.DealerPortalVehicleApplicationPDFs;
            pr.getParameters().put('id', String.valueOf(sig.Application__c));
            pr.getParameters().put('sigId', String.valueOf(sig.Id));
            pr.getParameters().put('docType', sig.Document_Type__c);
            pr.setRedirect(false);

            Blob pdf = pr.getContentAsPDF();
            if (pdf == null || pdf.size() == 0) {
                throw new SignatureServiceException('renderer returned an empty PDF');
            }

            String label = SignatureDocument.documentLabel(sig.Document_Type__c);
            String fileName = SignatureDocument.documentFileName(sig.Document_Type__c, Date.today(),
                SignatureDocument.nextVersionFor(sig.Application__c, label));

            ContentVersion cv = new ContentVersion(
                Title = fileName.left(250),
                PathOnClient = (fileName + '.pdf').left(500),
                VersionData = pdf,
                FirstPublishLocationId = sig.Application__c
            );
            insert cv;

            // Every role points at the ONE PDF that carries both signatures.
            List<Application_Signature__c> toUpdate = new List<Application_Signature__c>();
            for (String role : ROLES) {
                toUpdate.add(new Application_Signature__c(
                    Id = byRole.get(role).Id,
                    Pdf_Document_Id__c = cv.Id,
                    Status__c = ST_RENDERED,
                    Render_Error__c = null
                ));
            }
            update toUpdate;
            return cv.Id;
        } catch (Exception e) {
            for (String role : ROLES) {
                markFailed(byRole.get(role).Id, e);
            }
            throw new SignatureServiceException('issuePdf failed for ' + signatureId + ': ' + safeMessage(e));
        }
    }

    // -------------------------------------------------------------------- cleanup

    /** Deletes the staged image and closes the row. Tolerates an already-deleted resource. */
    public static void dropResource(Id signatureId) {
        if (signatureId == null) {
            throw new SignatureServiceException('signatureId is required');
        }
        List<Application_Signature__c> rows = [
            SELECT Id, ResourceId__c, Status__c
            FROM Application_Signature__c
            WHERE Id = :signatureId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new SignatureServiceException('signature not found: ' + signatureId);
        }
        Application_Signature__c sig = rows[0];

        if (String.isNotBlank(sig.ResourceId__c)) {
            try {
                SignatureResourceClient.deleteResource(sig.ResourceId__c);
            } catch (Exception e) {
                update new Application_Signature__c(Id = sig.Id, Render_Error__c = safeMessage(e).left(255));
                throw new SignatureServiceException('dropResource failed for ' + signatureId + ': ' + safeMessage(e));
            }
        }

        update new Application_Signature__c(
            Id = sig.Id,
            ResourceId__c = null,
            ResourceName__c = null,
            Status__c = ST_DONE,
            Render_Error__c = null
        );
    }

    // ---------------------------------------------------------------------- read

    /**
     * Signed means BOTH roles captured their ink. Per-role state is exposed
     * so the pad can tick off each signer as they go.
     *
     * "Captured" is the stored PNG payload, not the transient staged resource:
     * dropResource clears the resource pointer after a successful render but the
     * signature itself stays on the row (and in the PDF).
     */
    public static SignatureStatus getStatus(Id applicationId, String documentType) {
        SignatureStatus dto = new SignatureStatus();
        dto.hasSignature = false;
        dto.allRolesCaptured = false;
        dto.hasPdf = false;
        dto.roles = new List<RoleState>();
        if (applicationId == null) {
            return dto;
        }

        String docType = normaliseDocumentType(documentType);
        List<Application_Signature__c> rows = [
            SELECT Id, Signer_Role__c, Signed_By__c, Signed_At__c, Pdf_Document_Id__c,
                   Status__c, Render_Error__c, PngB64__c
            FROM Application_Signature__c
            WHERE Application__c = :applicationId AND Document_Type__c = :docType
            ORDER BY CreatedDate ASC
        ];

        Map<String, Application_Signature__c> byRole = new Map<String, Application_Signature__c>();
        for (Application_Signature__c r : rows) {
            String role = effectiveRole(r.Signer_Role__c);
            if (!byRole.containsKey(role)) {
                byRole.put(role, r);
            }
        }

        Boolean allCaptured = true;
        String pdfId = null;
        String renderError = null;
        for (String role : ROLES) {
            Application_Signature__c r = byRole.get(role);
            RoleState st = new RoleState();
            st.role = role;
            st.captured = r != null && String.isNotBlank(r.PngB64__c);
            if (r != null) {
                st.signatureId = r.Id;
                st.signedBy = r.Signed_By__c;
                st.signedAt = r.Signed_At__c;
                st.status = r.Status__c;
                if (String.isBlank(pdfId) && String.isNotBlank(r.Pdf_Document_Id__c)) {
                    pdfId = r.Pdf_Document_Id__c;
                }
                if (String.isBlank(renderError) && String.isNotBlank(r.Render_Error__c)) {
                    renderError = r.Render_Error__c;
                }
            }
            if (!st.captured) {
                allCaptured = false;
            }
            dto.roles.add(st);
        }

        dto.allRolesCaptured = allCaptured;
        dto.hasSignature = allCaptured;
        dto.hasPdf = String.isNotBlank(pdfId);
        dto.pdfDocumentId = pdfId;
        ContentVersion pdfCv = pdfVersion(pdfId);
        dto.pdfContentDocumentId = pdfCv == null ? null : pdfCv.ContentDocumentId;
        dto.pdfFileName = pdfCv == null ? null : pdfCv.Title;
        dto.renderError = renderError;

        Application_Signature__c customer = byRole.get(ROLE_CUSTOMER);
        if (customer == null && !rows.isEmpty()) {
            customer = rows[0];
        }
        if (customer != null) {
            dto.signatureId = customer.Id;
            dto.signedBy = customer.Signed_By__c;
            dto.signedAt = customer.Signed_At__c;
            dto.status = customer.Status__c;
        }
        return dto;
    }

    // -------------------------------------------------------------------- helpers

    /** Blank on legacy rows means Customer. */
    public static String effectiveRole(String signerRole) {
        if (String.isBlank(signerRole)) {
            return ROLE_CUSTOMER;
        }
        String r = signerRole.trim();
        if (r.equalsIgnoreCase(ROLE_CUSTOMER) || r.equalsIgnoreCase('Customer Signature')) {
            return ROLE_CUSTOMER;
        }
        if (r.equalsIgnoreCase(ROLE_DEALER_REP) || r.equalsIgnoreCase('Dealership Rep')
                || r.equalsIgnoreCase('Dealership Rep.') || r.equalsIgnoreCase('Dealer Rep')) {
            return ROLE_DEALER_REP;
        }
        if (r.equalsIgnoreCase(ROLE_CONTRACT_HOLDER) || r.equalsIgnoreCase('Contract Holder')) {
            return ROLE_CONTRACT_HOLDER;
        }
        throw new SignatureServiceException('unsupported signerRole: ' + signerRole);
    }

    public static String normaliseRole(String signerRole) {
        return effectiveRole(signerRole);
    }

    private static Application_Signature__c findRoleRow(Id applicationId, String docType, String role) {
        List<Application_Signature__c> rows = [
            SELECT Id, Signer_Role__c, PngBytes__c, Status__c
            FROM Application_Signature__c
            WHERE Application__c = :applicationId AND Document_Type__c = :docType
            ORDER BY CreatedDate ASC
        ];
        for (Application_Signature__c r : rows) {
            if (effectiveRole(r.Signer_Role__c) == role) {
                return r;
            }
        }
        return null;
    }

    private static ContentVersion pdfVersion(String contentVersionId) {
        if (String.isBlank(contentVersionId)) {
            return null;
        }
        try {
            List<ContentVersion> cvs = [
                SELECT Id, Title, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :contentVersionId
                LIMIT 1
            ];
            return cvs.isEmpty() ? null : cvs[0];
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Document identity (label, file name, version, render key) lives in
     * SignatureDocument - pure logic, separately tested.
     */
    public static String normaliseDocumentType(String documentType) {
        try {
            return SignatureDocument.normaliseDocumentType(documentType);
        } catch (Exception e) {
            // keep this class's exception contract for its callers
            throw new SignatureServiceException(safeMessage(e));
        }
    }

    private static String normaliseBase64(String raw) {
        if (String.isBlank(raw)) {
            throw new SignatureServiceException('pngB64 is required');
        }
        String s = raw.trim();
        if (s.startsWithIgnoreCase('data:')) {
            Integer comma = s.indexOf(',');
            if (comma > -1) {
                s = s.substring(comma + 1);
            }
        }
        s = s.deleteWhitespace();
        if (String.isBlank(s)) {
            throw new SignatureServiceException('pngB64 is empty after normalisation');
        }
        return s;
    }

    private static SaveResult toSaveResult(Application_Signature__c row, Boolean created, String role) {
        SaveResult r = new SaveResult();
        r.signatureId = row.Id;
        r.status = row.Status__c;
        r.pdfDocumentId = row.Pdf_Document_Id__c;
        r.created = created;
        r.signerRole = role;
        return r;
    }

    private static void markFailed(Id signatureId, Exception e) {
        try {
            update new Application_Signature__c(
                Id = signatureId,
                Status__c = ST_RENDER_FAILED,
                Render_Error__c = safeMessage(e).left(255)
            );
        } catch (Exception ignored) {
            // never mask the original failure
        }
    }

    private static String safeMessage(Exception e) {
        String m = e.getMessage();
        return String.isBlank(m) ? e.getTypeName() : m;
    }
}