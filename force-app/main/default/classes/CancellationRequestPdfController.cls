/**
 * CancellationRequestPdfController
 *
 * Backing controller for CancellationRequestPdf (Visualforce, renderAs="pdf").
 * Renders the dealer cancellation request as a printable document that mirrors
 * the deployed dealer portal form: navy section bars, white cards, grey read-only
 * fields, grey service blocks, the refund bar and the dealership authorisation
 * block with the captured signature.
 *
 * `without sharing` on purpose: by the time this page renders, the after-insert
 * trigger has already moved the request to the Sales review queue, so the dealer
 * who submitted it no longer has record access. The document is generated for the
 * request the transaction itself just created, and the id is the only input.
 */
public without sharing class CancellationRequestPdfController {

    private static final String LEAD_IN =
        'By signing and submitting this form, the dealership acknowledges and agrees to the following:';

    /** 1x1 transparent PNG, emitted when no signature was captured. */
    private static final String BLANK_PNG =
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

    public class TermsBlock {
        public String heading { get; set; }
        public String body { get; set; }
        public Boolean hasHeading { get; set; }
    }

    public class ServiceBlock {
        public String category { get; set; }
        public String name { get; set; }
        public String termLine { get; set; }
        public String options { get; set; }
        public String amount { get; set; }
    }

    private App_Cancellation_Request__c request;
    private List<Cancellation_Service__c> services = new List<Cancellation_Service__c>();
    private String signatureDataUri = BLANK_PNG;
    private String termsText;

    public Boolean hasRequest { get; private set; }
    public String errorMessage { get; private set; }

    public CancellationRequestPdfController() {
        Id requestId = null;
        try {
            requestId = ApexPages.currentPage().getParameters().get('id');
        } catch (Exception e) {
            requestId = null;
        }
        if (requestId == null) {
            hasRequest = false;
            errorMessage = 'No cancellation request was supplied.';
            return;
        }
        try {
            load(requestId);
            hasRequest = true;
        } catch (Exception e) {
            hasRequest = false;
            errorMessage = 'This cancellation request could not be rendered: ' + e.getMessage();
        }
    }

    private void load(Id requestId) {
        List<App_Cancellation_Request__c> rows = [
            SELECT Id, Name, Status__c, Reason_Code__c, Reason_Detail__c, Reason__c,
                   Date_Requested__c, Total_Refund_Amount__c, Terms_Version__c,
                   Terms_Accepted__c, Terms_Accepted_On__c,
                   Authorized_Rep_Name__c, Authorized_Rep_Title__c,
                   Dealer_Snapshot__c, Dealer_Address_Snapshot__c,
                   Customer_Name_Snapshot__c, Vehicle_Snapshot__c, VIN_Snapshot__c,
                   Signature_Content_Version_Id__c,
                   Application__r.Name, Application__r.Dealer_Name__r.Name,
                   Application__r.Dealer_Name__r.Phone, Application__r.Dealer_Name__r.Email__c
            FROM App_Cancellation_Request__c
            WHERE Id = :requestId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new QueryException('Cancellation request not found.');
        }
        request = rows[0];

        services = [
            SELECT Id, Service_Name__c, Term_Text__c, Options_Text__c,
                   Estimated_Refund__c, Refund_Amount__c,
                   Application_Package__r.Dealer_Package_Retail_Price__c,
                   Application_Package__r.Add_Ons_Retail_Price__c,
                   Application_Package__r.Dealer_Package__r.Plan_Type__r.Name
            FROM Cancellation_Service__c
            WHERE App_Cancellation_Request__c = :requestId
            ORDER BY Service_Name__c
        ];

        if (String.isNotBlank(request.Signature_Content_Version_Id__c)) {
            List<ContentVersion> files = [
                SELECT Id, VersionData, FileType
                FROM ContentVersion
                WHERE Id = :request.Signature_Content_Version_Id__c
                LIMIT 1
            ];
            if (!files.isEmpty() && files[0].VersionData != null) {
                signatureDataUri = 'data:image/png;base64,' + EncodingUtil.base64Encode(files[0].VersionData);
            }
        }

        // SOQL, not getInstance(): getInstance() returns a LongTextArea custom
        // metadata field cut at 255 characters, which silently truncated the
        // terms to their first paragraph.
        try {
            List<Cancellation_Settings__mdt> settings = [
                SELECT Terms_Version__c, Terms_Text__c
                FROM Cancellation_Settings__mdt
                WHERE DeveloperName = 'Default'
                LIMIT 1
            ];
            termsText = settings.isEmpty() ? null : settings[0].Terms_Text__c;
        } catch (Exception ignored) {
            Cancellation_Settings__mdt cached = Cancellation_Settings__mdt.getInstance('Default');
            termsText = cached == null ? null : cached.Terms_Text__c;
        }
    }

    // ------------------------------------------------------------------ header

    public String requestName {
        get { return request == null ? null : request.Name; }
    }

    public String applicationNumber {
        get { return request == null || request.Application__r == null ? '' : nz(request.Application__r.Name); }
    }

    public String customerName {
        get { return request == null ? '' : nz(request.Customer_Name_Snapshot__c); }
    }

    public String vehicle {
        get { return request == null ? '' : nz(request.Vehicle_Snapshot__c); }
    }

    public String vin {
        get { return request == null ? '' : nz(request.VIN_Snapshot__c); }
    }

    public String dateRequested {
        get {
            if (request == null || request.Date_Requested__c == null) return '';
            return request.Date_Requested__c.format('dd/MM/yyyy');
        }
    }

    public String statusLabel {
        get {
            if (request == null || String.isBlank(request.Status__c)) return '';
            return request.Status__c.toUpperCase();
        }
    }

    public String signatureDataUriValue {
        get { return signatureDataUri; }
    }

    public Boolean hasSignature {
        get { return signatureDataUri != BLANK_PNG; }
    }

    // -------------------------------------------------------------- section 2

    public List<ServiceBlock> serviceBlocks {
        get {
            List<ServiceBlock> out = new List<ServiceBlock>();
            for (Cancellation_Service__c cs : services) {
                ServiceBlock b = new ServiceBlock();
                String category = cs.Application_Package__r != null
                        && cs.Application_Package__r.Dealer_Package__r != null
                        && cs.Application_Package__r.Dealer_Package__r.Plan_Type__r != null
                    ? cs.Application_Package__r.Dealer_Package__r.Plan_Type__r.Name
                    : null;
                b.category = String.isBlank(category) ? 'Other Services' : category;
                b.name = nz(cs.Service_Name__c);
                String term = String.isBlank(cs.Term_Text__c) ? '—' : cs.Term_Text__c;
                b.termLine = 'Selected Term: ' + term + ' (' + money(cs.Estimated_Refund__c) + ')';
                b.options = 'Additional Options: ' + (String.isBlank(cs.Options_Text__c) ? '-' : cs.Options_Text__c);
                b.amount = money(cs.Estimated_Refund__c);
                out.add(b);
            }
            return out;
        }
    }

    public Boolean hasServices {
        get { return !services.isEmpty(); }
    }

    public String reasonLabel {
        get {
            if (request == null) return '';
            String code = String.isNotBlank(request.Reason_Code__c) ? request.Reason_Code__c : request.Reason__c;
            return nz(code);
        }
    }

    public Boolean hasReasonDetail {
        get { return request != null && String.isNotBlank(request.Reason_Detail__c); }
    }

    public String reasonDetail {
        get { return request == null ? '' : nz(request.Reason_Detail__c); }
    }

    public String refundAmount {
        get { return money(request == null ? null : request.Total_Refund_Amount__c); }
    }

    // -------------------------------------------------------------- section 3

    public List<TermsBlock> termsBlocks {
        get {
            List<TermsBlock> blocks = new List<TermsBlock>();
            if (String.isBlank(termsText)) {
                return blocks;
            }
            List<String> lines = new List<String>();
            for (String raw : termsText.split('\n')) {
                String line = raw.replace('\r', '').replaceAll('\\s+', ' ').trim();
                if (String.isBlank(line)) continue;
                if (line.equalsIgnoreCase(LEAD_IN)) continue;
                if (line.equalsIgnoreCase(LEAD_IN.replace(':', ''))) continue;
                lines.add(line);
            }

            TermsBlock current = null;
            Integer index = 0;
            for (String line : lines) {
                if (isHeading(line)) {
                    if (current != null) blocks.add(current);
                    current = new TermsBlock();
                    current.heading = titleCase(line.replaceAll('[:\\s]+$', ''));
                    current.hasHeading = true;
                    current.body = '';
                    index++;
                } else if (current == null) {
                    current = new TermsBlock();
                    current.heading = '';
                    current.hasHeading = false;
                    current.body = line;
                    index++;
                } else {
                    current.body = String.isBlank(current.body) ? line : current.body + ' ' + line;
                }
            }
            if (current != null) blocks.add(current);
            return blocks;
        }
    }

    /** A short ALL-CAPS line with no sentence punctuation is a sub-section title. */
    private Boolean isHeading(String line) {
        String stripped = line.replaceAll('[:\\s]+$', '');
        if (stripped.length() == 0 || stripped.length() > 80) return false;
        if (stripped.contains('.') || stripped.contains(',')) return false;
        if (!stripped.contains(' ')) return false;
        if (!Pattern.matches('[A-Z0-9][^a-z]*', stripped)) return false;
        return Pattern.matches('.*[A-Z]{3,}.*', stripped);
    }

    private String titleCase(String heading) {
        Set<String> minor = new Set<String>{'and', 'or', 'of', 'the', 'for', 'to', 'a', 'an', 'in', 'on'};
        List<String> words = heading.toLowerCase().split('\\s+');
        List<String> out = new List<String>();
        for (Integer i = 0; i < words.size(); i++) {
            String w = words[i];
            if (w.startsWith('a-protect')) {
                out.add('A-Protect' + w.substring(9));
            } else if (i > 0 && minor.contains(w)) {
                out.add(w);
            } else if (w.length() > 0) {
                out.add(w.substring(0, 1).toUpperCase() + w.substring(1));
            }
        }
        return String.join(out, ' ');
    }

    public String termsVersion {
        get { return request == null ? '' : nz(request.Terms_Version__c); }
    }

    public String termsAcceptedOn {
        get {
            if (request == null || request.Terms_Accepted_On__c == null) return '';
            return request.Terms_Accepted_On__c.format('dd/MM/yyyy');
        }
    }

    public String termsAcceptedNote {
        get {
            if (request == null || request.Terms_Accepted_On__c == null) return '';
            return ' \u00b7 accepted ' + request.Terms_Accepted_On__c.format('dd/MM/yyyy');
        }
    }

    // -------------------------------------------------------------- section 4

    public String dealerName {
        get {
            if (request == null) return '';
            if (String.isNotBlank(request.Dealer_Snapshot__c)) return request.Dealer_Snapshot__c;
            return request.Application__r != null && request.Application__r.Dealer_Name__r != null
                ? nz(request.Application__r.Dealer_Name__r.Name) : '';
        }
    }

    public String dealerAddress {
        get { return request == null ? '' : nz(request.Dealer_Address_Snapshot__c); }
    }

    public String dealerContact {
        get {
            if (request == null || request.Application__r == null
                    || request.Application__r.Dealer_Name__r == null) {
                return '';
            }
            List<String> parts = new List<String>();
            if (String.isNotBlank(request.Application__r.Dealer_Name__r.Phone)) {
                parts.add(request.Application__r.Dealer_Name__r.Phone);
            }
            if (String.isNotBlank(request.Application__r.Dealer_Name__r.Email__c)) {
                parts.add(request.Application__r.Dealer_Name__r.Email__c);
            }
            return String.join(parts, ' · ');
        }
    }

    public String dealerRepName {
        get { return request == null ? '' : nz(request.Authorized_Rep_Name__c); }
    }

    public String dealerRepTitle {
        get { return request == null ? '' : nz(request.Authorized_Rep_Title__c); }
    }

    public String generatedOn {
        get { return Datetime.now().format('dd/MM/yyyy HH:mm'); }
    }

    // --------------------------------------------------------------- internals

    private static String nz(String value) {
        return value == null ? '' : value;
    }

    /** $1,398 / $1,398.50 — the form's compact currency, with thousands separators. */
    private static String money(Decimal value) {
        Decimal amount = value == null ? 0 : value;
        Boolean whole = amount == amount.setScale(0);
        Decimal scaled = whole ? amount.setScale(0) : amount.setScale(2);
        String plain = scaled.toPlainString();
        String sign = '';
        if (plain.startsWith('-')) {
            sign = '-';
            plain = plain.substring(1);
        }
        Integer dot = plain.indexOf('.');
        String intPart = dot < 0 ? plain : plain.substring(0, dot);
        String decPart = dot < 0 ? '' : plain.substring(dot);
        String grouped = '';
        Integer count = 0;
        for (Integer i = intPart.length() - 1; i >= 0; i--) {
            grouped = intPart.substring(i, i + 1) + grouped;
            count++;
            if (count == 3 && i > 0) {
                grouped = ',' + grouped;
                count = 0;
            }
        }
        return sign + '$' + grouped + decPart;
    }
}