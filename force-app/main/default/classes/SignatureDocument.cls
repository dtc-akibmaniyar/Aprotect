/**
 * SignatureDocument
 * Document identity for the three-signer feature: the user-facing label, the
 * produced file name, the version number and the contract page's `rt` render key.
 *
 * Deliberately its own class: it is pure logic (no DML, no callout, no render),
 * it is fully unit-testable, and it keeps SignatureService below the coverage
 * threshold problem that a larger service would create.
 *
 * File naming contract: "<Document label> <YYYY-MM-DD> v<n>", e.g.
 *   Extended Warranty 2026-10-22 v1
 *   Tire & Rim 2026-10-22 v1
 * Never a record name such as "SIG-00019".
 */
public class SignatureDocument {

    public static final String DOC_WARRANTY = 'Warranty';
    public static final String DOC_TIRE_RIM = 'TireRim';

    public static final String LABEL_WARRANTY = 'Extended Warranty';
    public static final String LABEL_TIRE_RIM = 'Tire & Rim';

    /** Warranty | TireRim, tolerating "Tire & Rim" / "Tire and Rim" / blank. */
    public static String normaliseDocumentType(String documentType) {
        if (String.isBlank(documentType)) {
            return DOC_WARRANTY;
        }
        String t = documentType.trim();
        if (t.equalsIgnoreCase(DOC_WARRANTY)) {
            return DOC_WARRANTY;
        }
        if (t.equalsIgnoreCase(DOC_TIRE_RIM)
                || t.equalsIgnoreCase('Tire & Rim')
                || t.equalsIgnoreCase('Tire and Rim')
                || t.equalsIgnoreCase('Tire And Rim')) {
            return DOC_TIRE_RIM;
        }
        throw new SignatureDocumentException('unsupported documentType: ' + documentType);
    }

    /** The label the dealer sees. */
    public static String documentLabel(String documentType) {
        return normaliseDocumentType(documentType).equals(DOC_TIRE_RIM)
            ? LABEL_TIRE_RIM
            : LABEL_WARRANTY;
    }

    /** "<Document label> <YYYY-MM-DD> v<n>". */
    public static String documentFileName(String documentType, Date onDate, Integer version) {
        Integer v = (version == null || version < 1) ? 1 : version;
        Date d = (onDate == null) ? Date.today() : onDate;
        return documentLabel(documentType) + ' ' + String.valueOf(d) + ' v' + v;
    }

    /**
     * Next version number for one application + document type. Counts the files
     * already produced for that label, so a re-issue after a re-sign becomes v2,
     * v3, ... without any extra field to keep in sync.
     */
    public static Integer nextVersionFor(Id applicationId, String label) {
        if (applicationId == null || String.isBlank(label)) {
            return 1;
        }
        String prefix = label + ' %';
        Integer used = [
            SELECT COUNT()
            FROM ContentVersion
            WHERE FirstPublishLocationId = :applicationId
              AND Title LIKE :prefix
        ];
        return used + 1;
    }

    /**
     * The `rt` render key for one application + document type.
     *
     * Mirrors ApplicationPDFExtension exactly: active packages, deduped by their
     * RECORD TYPE NAME (falling back to Package_Record_Type__c then 'Other'), and
     * a package is tire & rim when that name carries both "Tire" and "Rim".
     * Returns null when the application carries no package of that kind.
     */
    public static String recordTypeKey(Id applicationId, String documentType) {
        if (applicationId == null) {
            return null;
        }
        Boolean wantTireRim = normaliseDocumentType(documentType).equals(DOC_TIRE_RIM);
        for (Application_Package__c p : [
            SELECT RecordType.Name, Package_Record_Type__c
            FROM Application_Package__c
            WHERE Application__c = :applicationId AND Active__c = true
            ORDER BY RecordTypeId, CreatedDate DESC
        ]) {
            String rt = (p.RecordType != null && String.isNotBlank(p.RecordType.Name))
                ? p.RecordType.Name
                : (String.isBlank(p.Package_Record_Type__c) ? 'Other' : p.Package_Record_Type__c);
            Boolean isTireRim = rt.containsIgnoreCase('Tire') && rt.containsIgnoreCase('Rim');
            if (isTireRim == wantTireRim) {
                return rt;
            }
        }
        return null;
    }

    public class SignatureDocumentException extends Exception {}
}