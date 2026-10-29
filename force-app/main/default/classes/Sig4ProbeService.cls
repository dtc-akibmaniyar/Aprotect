public class Sig4ProbeService {
    public static final String DOC_TIRE_RIM = 'TireRim';
    public static String normaliseDocumentType(String documentType) {
        if (String.isBlank(documentType)) return 'Warranty';
        String t = documentType.trim();
        if (t.equalsIgnoreCase('Warranty')) return 'Warranty';
        if (t.equalsIgnoreCase(DOC_TIRE_RIM) || t.equalsIgnoreCase('Tire & Rim')) return DOC_TIRE_RIM;
        throw new IllegalArgumentException('unsupported documentType: ' + documentType);
    }
    public static String documentLabel(String documentType) {
        return normaliseDocumentType(documentType) == DOC_TIRE_RIM ? 'Tire & Rim' : 'Extended Warranty';
    }
    public static String documentFileName(String documentType, Date onDate, Integer version) {
        Integer v = (version == null || version < 1) ? 1 : version;
        Date d = (onDate == null) ? Date.today() : onDate;
        return documentLabel(documentType) + ' ' + String.valueOf(d) + ' v' + v;
    }
    public static Integer nextVersionFor(Id applicationId, String label) {
        if (applicationId == null || String.isBlank(label)) return 1;
        String prefix = label + ' %';
        Integer used = [SELECT COUNT() FROM ContentVersion WHERE FirstPublishLocationId = :applicationId AND Title LIKE :prefix];
        return used + 1;
    }
}