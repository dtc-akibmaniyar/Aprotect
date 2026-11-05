/**
 * Controller for the DealerPortalSignatureBlock VF component.
 *
 * Deliberately independent of ApplicationPDFExtension (which cannot be edited
 * in this org). Resolves the staged signature image for one application +
 * document type + signer role and exposes it to the component.
 *
 * FAIL CLOSED: anything unexpected (blank/!Id appId, unknown doc type, unknown
 * role, no staged resource, resource name that is not a plain identifier) yields
 * hasSignature = false and the component renders nothing at all - no
 * placeholder, no spacing. The signature LINE and its label stay, they are page
 * markup, not this component.
 *
 * Status note: SignatureService.issuePdf writes ResourceName__c BEFORE
 * getContentAsPDF() and only flips Status__c to RENDERED afterwards. During
 * the first render the row is still CAPTURED, so the filter cannot be
 * "RENDERED" alone - it is ResourceName__c != null (the real "image is
 * staged" test) AND status CAPTURED or RENDERED. dropResource clears
 * ResourceName__c, which is what makes the block disappear again.
 */
public without sharing class SignatureBlockController {

    /* assignTo targets - set by the page before render, not before construction */
    public String applicationId { get; set; }
    public String signatureDocType { get; set; }
    public String signatureRole { get; set; }
    /* optional explicit size in px, set by the page via the widthPx / heightPx
       attributes; falls back to the per-role defaults when absent or invalid */
    public String imageWidthPx { get; set; }
    public String imageHeightPx { get; set; }

    private Boolean loaded = false;
    private Boolean found = false;
    private String imageName;
    private String signedOn;
    private String role = 'Customer';

    private void load() {
        if (loaded) return;
        loaded = true;
        found = false;
        imageName = null;
        signedOn = null;

        if (String.isBlank(applicationId)) return;

        Id appRecordId;
        try {
            appRecordId = (Id) applicationId.trim();
        } catch (Exception e) {
            return;
        }

        String dt = 'Warranty';
        if (String.isNotBlank(signatureDocType)) {
            String d = signatureDocType.trim();
            if (d == 'TireRim' || d == 'Tire & Rim' || d == 'Tire And Rim' || d == 'Tire and Rim') {
                dt = 'TireRim';
            }
        }

        String r = 'Customer';
        if (String.isNotBlank(signatureRole)) {
            String v = signatureRole.trim();
            if (v.equalsIgnoreCase('Customer')) {
                r = 'Customer';
            } else if (v.equalsIgnoreCase('DealerRep') || v.equalsIgnoreCase('Dealership Rep')
                    || v.equalsIgnoreCase('Dealership Rep.') || v.equalsIgnoreCase('Dealer Rep')) {
                r = 'DealerRep';
            } else if (v.equalsIgnoreCase('ContractHolder') || v.equalsIgnoreCase('Contract Holder')) {
                r = 'ContractHolder';
            } else {
                return; // unknown role -> render nothing
            }
        }
        role = r;

        List<Application_Signature__c> rows;
        if (r == 'Customer') {
            // Blank Signer_Role__c is a legacy row and belongs to the customer line.
            rows = [
                SELECT ResourceName__c, Signed_At__c
                FROM Application_Signature__c
                WHERE Application__c = :appRecordId
                  AND Document_Type__c = :dt
                  AND ResourceName__c != null
                  AND Status__c IN ('CAPTURED', 'RENDERED')
                  AND (Signer_Role__c = :r OR Signer_Role__c = null)
                ORDER BY Signed_At__c DESC NULLS LAST
                LIMIT 1
            ];
        } else {
            rows = [
                SELECT ResourceName__c, Signed_At__c
                FROM Application_Signature__c
                WHERE Application__c = :appRecordId
                  AND Document_Type__c = :dt
                  AND ResourceName__c != null
                  AND Status__c IN ('CAPTURED', 'RENDERED')
                  AND Signer_Role__c = :r
                ORDER BY Signed_At__c DESC NULLS LAST
                LIMIT 1
            ];
        }
        if (rows.isEmpty()) return;

        String rn = rows[0].ResourceName__c;
        if (String.isBlank(rn)) return;
        rn = rn.trim();
        // A resource name is a plain identifier. Refuse anything else rather
        // than emit an arbitrary /resource/<value> URL into the PDF.
        if (!Pattern.matches('[A-Za-z0-9_]{1,80}', rn)) return;

        found = true;
        imageName = rn;
        Datetime d = rows[0].Signed_At__c;
        signedOn = (d == null) ? null : d.format('d MMMM yyyy');
    }

    public Boolean getHasSignature() {
        load();
        return found;
    }

    public String getResourceName() {
        load();
        return imageName;
    }

    public String getSignedOnDisplay() {
        load();
        return signedOn;
    }

    public Boolean getHasSignedOn() {
        load();
        return found && String.isNotBlank(signedOn);
    }

    /**
     * The signature lines have different amounts of room left on their page, so
     * the image is sized per role unless the page passes an explicit size via the
     * widthPx / heightPx component attributes. Widths are in px, which this
     * renderer converts at 96 dpi (162px = 1.69in).
     *
     * With both signatures present the customer and rep images share the
     * free space at the foot of the application page (45.3 pt on APP000517),
     * so both lines are smaller than in the single-signature build:
     * 90x30 px (0.94x0.31 in) + 72x24 px (0.75x0.25 in) = 40.5 pt, which keeps
     * the warranty application page at one page. The contract-holder line at the
     * foot of the terms (which now carries the customer's stroke) has room to
     * spare and keeps 120x40 px.
     *
     * An override must be a plain integer 20..200; anything else fails closed to
     * the per-role default so a bad attribute can never break the render.
     */
    public String getImageWidth() {
        load();
        String pxOverride = validSizeOverride(imageWidthPx);
        if (pxOverride != null) return pxOverride;
        if (role == 'DealerRep') return '72';
        if (role == 'ContractHolder') return '120';
        return '90';
    }

    public String getImageHeight() {
        load();
        String pxOverride = validSizeOverride(imageHeightPx);
        if (pxOverride != null) return pxOverride;
        if (role == 'DealerRep') return '24';
        if (role == 'ContractHolder') return '40';
        return '30';
    }

    /** A plain integer 20..200 px, or null when the override is absent / odd. */
    private static String validSizeOverride(String raw) {
        if (String.isBlank(raw)) return null;
        String v = raw.trim();
        if (!Pattern.matches('[0-9]{1,3}', v)) return null;
        Integer px = Integer.valueOf(v);
        if (px < 20 || px > 200) return null;
        return String.valueOf(px);
    }
}