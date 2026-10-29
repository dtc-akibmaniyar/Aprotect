/**
 * SignatureSubmitGuard
 * ONE rule, enforced on the server: an application cannot move to Submitted
 * until every contract document it actually carries has been signed by all
 * three signers (Customer, Dealership Rep, Contract Holder).
 *
 * "The documents it actually carries" = the ACTIVE Application_Package__c record
 * types on the application:
 *     Extended_Limited_Warranty   -> Extended Warranty document
 *     Tire_Rim_Protection_Plan    -> Tire & Rim document
 * A warranty-only application is therefore never blocked by a Tire & Rim
 * document it does not have, and an application with neither package (quote,
 * GAP-only, empty draft) is not gated at all - there is nothing to sign.
 *
 * Pure read logic: no DML, no callout, no render. Called from
 *   - DealerPortalController.updateApplicationStatus  (the hard block)
 *   - SignaturePadController.getSignatureRequirements (the portal button state)
 * so the button and the server can never disagree about what is missing.
 */
public without sharing class SignatureSubmitGuard {

    public static final String RT_WARRANTY = 'Extended_Limited_Warranty';
    public static final String RT_TIRE_RIM = 'Tire_Rim_Protection_Plan';

    /** Suffix both the button tooltip and the refused submit share. */
    public static final String THREE_SIGNER_NOTE =
        ' — all three signatures (customer, dealership rep and contract holder) are required on each document.';

    public class DocumentRequirement {
        @AuraEnabled public String documentType;   // Warranty | TireRim
        @AuraEnabled public String label;          // Extended Warranty | Tire & Rim
        @AuraEnabled public Boolean required;
        @AuraEnabled public Boolean complete;
        @AuraEnabled public Integer rolesCaptured;
        @AuraEnabled public Integer rolesRequired;
    }

    public class Requirements {
        @AuraEnabled public Boolean allComplete;
        @AuraEnabled public Boolean hasRequiredDocuments;
        @AuraEnabled public List<DocumentRequirement> documents;
        /** "Extended Warranty and Tire & Rim" — null when nothing is missing. */
        @AuraEnabled public String missingLabels;
        /** The exact sentence the dealer sees. Null when allComplete. */
        @AuraEnabled public String missingMessage;
    }

    /**
     * The gate state for one application. Never throws: a failed read returns
     * allComplete = false with a message, so a caller can never mistake an
     * unreadable signature state for a signed application.
     */
    public static Requirements forApplication(Id applicationId) {
        Requirements req = new Requirements();
        req.documents = new List<DocumentRequirement>();
        req.allComplete = true;
        req.hasRequiredDocuments = false;

        if (applicationId == null) {
            return req;
        }

        try {
            Set<String> present = presentDocumentTypes(applicationId);
            List<String> missing = new List<String>();

            if (present.contains(SignatureService.DOC_WARRANTY)) {
                req.documents.add(buildRequirement(
                    applicationId, SignatureService.DOC_WARRANTY, missing));
            }
            if (present.contains(SignatureService.DOC_TIRE_RIM)) {
                req.documents.add(buildRequirement(
                    applicationId, SignatureService.DOC_TIRE_RIM, missing));
            }

            req.hasRequiredDocuments = !req.documents.isEmpty();
            req.allComplete = missing.isEmpty();
            if (req.allComplete) {
                return req;
            }

            req.missingLabels = joinLabels(missing);
            req.missingMessage = 'Sign the ' + req.missingLabels
                + (missing.size() > 1 ? ' documents' : ' document')
                + ' before submitting' + THREE_SIGNER_NOTE;
            return req;
        } catch (Exception e) {
            req.allComplete = false;
            req.hasRequiredDocuments = true;
            req.missingMessage = 'Signature status could not be checked'
                + THREE_SIGNER_NOTE;
            return req;
        }
    }

    /** True only when nothing is required or everything required is signed. */
    public static Boolean canSubmit(Id applicationId) {
        Requirements req = forApplication(applicationId);
        return req != null && req.allComplete == true;
    }

    /** The exact refusal sentence, or null when the submit is allowed. */
    public static String blockedMessage(Id applicationId) {
        Requirements req = forApplication(applicationId);
        return (req == null || req.allComplete == true) ? null : req.missingMessage;
    }

    // ------------------------------------------------------------------ helpers

    private static DocumentRequirement buildRequirement(
            Id applicationId, String documentType, List<String> missingLabels) {
        DocumentRequirement d = new DocumentRequirement();
        d.documentType = documentType;
        d.label = SignatureDocument.documentLabel(documentType);
        d.required = true;
        d.rolesRequired = SignatureService.ROLES.size();

        Integer captured = 0;
        Boolean complete = false;
        try {
            SignatureService.SignatureStatus status =
                SignatureService.getStatus(applicationId, documentType);
            if (status != null && status.roles != null) {
                for (SignatureService.RoleState rs : status.roles) {
                    if (rs.captured == true) {
                        captured++;
                    }
                }
            }
            complete = status != null
                && status.allRolesCaptured == true
                && captured >= SignatureService.ROLES.size();
        } catch (Exception e) {
            complete = false;
        }

        d.rolesCaptured = captured;
        d.complete = complete;
        if (!complete) {
            missingLabels.add(d.label);
        }
        return d;
    }

    /** Which contract documents this application actually carries. */
    private static Set<String> presentDocumentTypes(Id applicationId) {
        Set<String> types = new Set<String>();
        for (Application_Package__c pkg : [
            SELECT Id, RecordType.DeveloperName
            FROM Application_Package__c
            WHERE Application__c = :applicationId
              AND Active__c = true
        ]) {
            String rt = pkg.RecordType == null ? null : pkg.RecordType.DeveloperName;
            if (rt == RT_WARRANTY) {
                types.add(SignatureService.DOC_WARRANTY);
            } else if (rt == RT_TIRE_RIM) {
                types.add(SignatureService.DOC_TIRE_RIM);
            }
        }
        return types;
    }

    private static String joinLabels(List<String> labels) {
        if (labels == null || labels.isEmpty()) {
            return '';
        }
        if (labels.size() == 1) {
            return labels[0];
        }
        if (labels.size() == 2) {
            return labels[0] + ' and ' + labels[1];
        }
        List<String> head = new List<String>();
        for (Integer i = 0; i < labels.size() - 1; i++) {
            head.add(labels[i]);
        }
        return String.join(head, ', ') + ' and ' + labels[labels.size() - 1];
    }
}