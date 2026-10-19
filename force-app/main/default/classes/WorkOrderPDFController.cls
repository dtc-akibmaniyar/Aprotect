/**
 * Page controller for WorkOrderPDF, the work order document sent to the
 * customer and the repair shop for authorization (TASK-050, requirement 3).
 *
 * The document mirrors showOrderWorkSummary section for section, on Osama's
 * instruction of 2026-10-08, so that what an agent checks on Manage Estimates
 * is what the customer receives. Its structure is therefore fixed by that
 * component rather than chosen here: Customer Information and Vehicle
 * Information side by side, Authorized Repair Facility, Service / Description
 * ending in Sub-Total, tax and Total Due, Warranty Coverage ending in Customer
 * Pays, then Customer Acknowledgement.
 *
 * Two deliberate differences from the preview, both because this is the real
 * document rather than a preview of one:
 *   - the "Preview of what the Work Order document will show. Nothing here is
 *     saved." paragraph is omitted, since it would be false here;
 *   - the figures come from the saved work order, not from unsaved scenario
 *     input.
 *
 * It reads the work order's own snapshot fields and never follows Claim__r back
 * to the live formulas. That is the whole point of the TASK-050 snapshot: a
 * document already sent out must not change when somebody later corrects a
 * phone number on the application.
 *
 * Replaces the older DocuSign Gen "Work Order Template" button, which Osama
 * confirmed on 2026-10-08 is out of date. DocuSign is not in use now though he
 * expects it may be again, so nothing about it has been removed.
 */
public with sharing class WorkOrderPDFController {

    private final Id workOrderId;

    public Work_Order__c order { get; private set; }
    public List<LineRow> lines { get; private set; }
    public List<BenefitRow> benefitLines { get; private set; }

    /** One row of the Service / Description table. */
    public class LineRow {
        public String lineType { get; set; }
        public String description { get; set; }
        public Decimal amount { get; set; }
        public Decimal retail { get; set; }
        public Decimal covered { get; set; }
        public Decimal customerPay { get; set; }
        public String amountDisplay {
            get { return money(amount); }
        }
    }

    /**
     * One ancillary benefit credit, shown as a negative in Warranty Coverage,
     * or, on a reimbursement, one receipt row of the Approved reimbursement
     * table (TASK-051), where amount is the APPROVED figure.
     */
    public class BenefitRow {
        public String label { get; set; }
        public String reimbursementLabel { get; set; }
        public String benefitType { get; set; }
        public Decimal amount { get; set; }
        public Decimal credit { get; set; }
        public Decimal receipts { get; set; }
        public Decimal leftOnTerm { get; set; }
        public Decimal over { get; set; }
        public String amountDisplay {
            get { return money(amount); }
        }
        public String creditDisplay {
            get { return negative(amount); }
        }
        public String receiptsDisplay {
            get { return money(receipts); }
        }
        public String leftOnTermDisplay {
            get { return leftOnTerm == null ? 'n/a' : money(leftOnTerm); }
        }
        public Boolean hasOver {
            get { return over != null && over > 0; }
        }
        public String overNote {
            get { return hasOver ? money(over) + ' is over the benefit limit and is not covered' : ''; }
        }
    }

    public WorkOrderPDFController(ApexPages.StandardController ctrl) {
        this(ctrl.getId());
    }

    public WorkOrderPDFController(Id workOrderIdParam) {
        this.workOrderId = workOrderIdParam;
        load();
    }

    private void load() {
        List<Work_Order__c> found = [
            SELECT Id, Name, Claim__c, Claim__r.Name, Status__c,
                   Estimate__c, Estimate__r.Claim_Type__c,
                   // the TASK-050 snapshot, deliberately not Claim__r.*
                   Application_Number__c, Customer_Name__c, Customer_Address__c,
                   Customer_Phone__c, Customer_Email__c,
                   VIN__c, Vehicle_Year__c, Vehicle_Make__c, Vehicle_Model__c,
                   Vehicle_Trim__c, Odometer_In__c, Odometer_In_Unit__c,
                   // TASK-051 snapshot, How you will be paid
                   Reimbursement_Payment_Method__c, Reimbursement_Expected_Payment_Date__c,
                   Repair_Shop__c, Repair_Shop__r.Name, Repair_Shop__r.Address__c,
                   Repair_Shop__r.Phone__c, Repair_Shop__r.Email__c,
                   // the figures, in the order the document presents them
                   Total_Line_Items_Cost__c, Tax_Percentage__c, Tax_13__c,
                   Total_Repair_Cost__c, Per_Claim_Coverage__c, Deductable__c,
                   Coverage_Applied__c, Benefits_Used__c, Total_Amount_Due__c,
                   // the retail repair EXCLUDING shop supplies, which is what
                   // the cap is tested against in getIsFullyCovered
                   Retail_Price__c
            FROM Work_Order__c
            WHERE Id = :workOrderId
            WITH USER_MODE
        ];
        if (found.isEmpty()) {
            throw new WorkOrderPDFException(
                'Work order not found, or not visible to you: ' + workOrderId);
        }
        order = found[0];

        List<Work_Order_Line_Item__c> raw = [
            SELECT Id, Description__c, Service_Repair_Description__c, Price__c, Retail__c,
                   Covered_Amount__c, Customer_Pay_Amount__c,
                   Claim_Line_Item__r.Line_Type__c, Claim_Line_Item__r.Description__c
            FROM Work_Order_Line_Item__c
            WHERE Customer_Work_Order__c = :workOrderId
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ];

        /*
         * The grouping rule is NOT written here. It lives once, in
         * WorkOrderDocumentLines, and is mirrored for the Manage Estimates
         * preview in lwc/workOrderDocument. Osama chose that arrangement on
         * 2026-10-09 after the preview and this document disagreed about how
         * many rows the job had, because each implemented the grouping
         * separately. This method's only job is to turn work order line items
         * into the rule's input shape.
         */
        List<WorkOrderDocumentLines.SourceLine> source =
            new List<WorkOrderDocumentLines.SourceLine>();
        for (Work_Order_Line_Item__c wl : raw) {
            // One shared definition of a line's readable text. Description__c
            // is a rich text field and stores "Oil &amp; fluids" for a supply
            // named "Oil & fluids", so it must not be read directly here.
            String label = ClaimEstimateService.lineDescription(wl);
            // Price__c is what a work order line carries as retail, and what
            // Total_Line_Items_Cost__c rolls up into the Sub-Total below.
            Decimal amount = wl.Price__c != null ? wl.Price__c : nz(wl.Retail__c);
            source.add(new WorkOrderDocumentLines.SourceLine(
                wl.Claim_Line_Item__r?.Line_Type__c, label, amount));
        }

        lines = new List<LineRow>();
        for (WorkOrderDocumentLines.DocumentLine d : WorkOrderDocumentLines.groupLines(source)) {
            LineRow r = new LineRow();
            r.lineType = d.lineType;
            r.description = d.description;
            r.amount = d.amount;
            lines.add(r);
        }

        benefitLines = new List<BenefitRow>();

        // TASK-051. A reimbursement lists THIS work order's estimate's own
        // receipts and nothing else, through the one approval rule in
        // ClaimEstimateService.getApprovedReimbursements, which is also what
        // the Manage Estimates preview mirrors. It used to fall through to the
        // claim-level query below, so CWO-0044 printed a 100 claim-level Car
        // Rental draw alongside the scenario's 120 and 85 and totalled 305
        // while the customer was being reimbursed 205 (Osama, 2026-10-13).
        // A receipt entirely over the cap still prints, with Approved 0.00.
        if (isReimbursement()) {
            List<ClaimEstimateService.ApprovedReimbursement> approved = order.Estimate__c == null
                ? null
                : ClaimEstimateService.getApprovedReimbursements(
                      new Set<Id>{ order.Estimate__c }).get(order.Estimate__c);
            if (approved != null) {
                for (ClaimEstimateService.ApprovedReimbursement a : approved) {
                    if (a.receipts <= 0) continue;
                    BenefitRow b = new BenefitRow();
                    b.benefitType = a.benefitType;
                    b.label = 'Ancillary Benefit: ' + a.benefitType;
                    b.reimbursementLabel = a.benefitType + ' reimbursement';
                    b.receipts = a.receipts;
                    b.amount = a.approved;
                    b.credit = -a.approved;
                    b.leftOnTerm = a.leftOnTerm;
                    b.over = a.over;
                    benefitLines.add(b);
                }
            }
            return;
        }

        // Claim-level ancillary draws, shown as credits. Estimate-scoped
        // reimbursement rows on an unchosen scenario are excluded, same rule
        // getBenefitBalancesForClaim applies.
        for (Benefit_Usage__c u : [
            SELECT Amount_Used__c, Benefit_Balance__r.Benefit_Type__c
            FROM Benefit_Usage__c
            WHERE Claim__c = :order.Claim__c
              AND Counts_Toward_Balance__c = true
              AND Amount_Used__c > 0
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ]) {
            String name = u.Benefit_Balance__r?.Benefit_Type__c;
            BenefitRow b = new BenefitRow();
            b.label = 'Ancillary Benefit: ' + name;
            b.reimbursementLabel = name + ' reimbursement';
            b.amount = u.Amount_Used__c;
            b.credit = u.Amount_Used__c == null ? null : -u.Amount_Used__c;
            benefitLines.add(b);
        }
    }

    // ───────────────────────────── presentation ─────────────────────────────

    /** "Claim Authorization" or "Reimbursement Authorization", as the preview. */
    public String getTitle() {
        return isReimbursement() ? 'Reimbursement Authorization' : 'Claim Authorization';
    }

    public Boolean getIsReimbursement() {
        return isReimbursement();
    }

    public Boolean getIsRepair() {
        return !isReimbursement();
    }

    private Boolean isReimbursement() {
        return order.Estimate__r?.Claim_Type__c == 'Reimbursement Only';
    }

    /**
     * Mirrors the canonical rule, ClaimPricingService.calculateScenario:
     *     fullyCovered = !isReimbursement && retailRepair > 0 && overLimit <= 0
     * where overLimit is the repair INCLUDING tax less the per-claim cap, and
     * retailRepair EXCLUDES shop supplies, since the cap is tested against the
     * repair only.
     *
     * The first version here invented its own rule, comparing Coverage_Applied__c
     * against Total_Repair_Cost__c, and was wrong twice over: that total
     * INCLUDES shop supplies, and coverage is already net of the deductible, so
     * it could essentially never reach the repair plus tax whenever a deductible
     * applied. The note therefore almost never printed, while the Manage
     * Estimates preview showed it correctly (Osama, 2026-10-09, on the
     * Alternator fully covered scenario: 960 plus 13% is 1,084.80, well inside
     * the 3,000 cap, yet the PDF omitted the line).
     *
     * Retail_Price__c is the retail repair excluding supplies, which is exactly
     * what calculateScenario calls retailRepair.
     */
    public Boolean getIsFullyCovered() {
        if (isReimbursement()) return false;
        Decimal retailRepair = nz(order.Retail_Price__c);
        if (retailRepair <= 0) return false;
        Decimal repairInclTax = retailRepair * (1 + nz(order.Tax_Percentage__c) / 100);
        Decimal overLimit = repairInclTax - nz(order.Per_Claim_Coverage__c);
        return overLimit <= 0;
    }

    public String getFullyCoveredNote() {
        return 'Repair fully covered within the ' + money(order.Per_Claim_Coverage__c)
            + ' claim limit. Customer is responsible for the deductible and shop supplies only.';
    }

    /**
     * "HST (13%):" as the preview writes it, not "HST (13.00%)". The preview
     * passes the raw percent through, so a whole number prints without a
     * decimal tail; stripSuffix removes the ".00" Apex would otherwise add.
     */
    public String getTaxLabel() {
        Decimal pct = nz(order.Tax_Percentage__c);
        String shown = String.valueOf(pct.setScale(2, RoundingMode.HALF_UP));
        if (shown.endsWith('.00')) shown = shown.removeEnd('.00');
        return 'HST (' + shown + '%):';
    }

    /** Credits print as negatives, the same way the preview shows them. */
    public Decimal getDeductibleCredit() {
        return order.Deductable__c == null ? null : -order.Deductable__c;
    }

    public Decimal getCoverageCredit() {
        return order.Coverage_Applied__c == null ? null : -order.Coverage_Applied__c;
    }

    /*
     * ──────────────── formatted figures ────────────────
     *
     * Rendered as strings rather than through apex:outputText with a currency
     * pattern, because that pattern prints a credit as ($100.00) while
     * showOrderWorkSummary prints −$100.00 with a real minus sign. These
     * mirror that component's money() and negative() helpers exactly, so the
     * two documents cannot drift on formatting.
     */
    public String getSubTotalDisplay()       { return money(order.Total_Line_Items_Cost__c); }
    public String getTaxDisplay()            { return money(order.Tax_13__c); }
    public String getTotalDueDisplay()       { return money(order.Total_Repair_Cost__c); }
    public String getCapDisplay()            { return money(order.Per_Claim_Coverage__c); }
    public String getDeductibleCreditDisplay() { return negative(order.Deductable__c); }
    public String getCoverageCreditDisplay() { return negative(order.Coverage_Applied__c); }
    public String getCustomerPaysDisplay()   { return money(order.Total_Amount_Due__c); }
    public String getReimbursedTotalDisplay(){ return money(getReimbursedTotal()); }
    public String getZeroDisplay()           { return money(0); }

    /**
     * The customer address as separate lines.
     *
     * Claim__c.Customer_Address__c is a formula that embeds literal <br> tags,
     * which the work order snapshots verbatim. Visualforce escapes them, so
     * the document printed "123 STREET TEST<br>Toronto, ON" on one line.
     * Splitting here and letting the page render one row per line keeps the
     * snapshot faithful while printing it properly, and avoids turning
     * escaping off on a field that reaches a customer document.
     */
    public List<String> getCustomerAddressLines() {
        List<String> out = new List<String>();
        if (String.isBlank(order.Customer_Address__c)) return out;
        for (String part : order.Customer_Address__c.replaceAll('(?i)<br\\s*/?>', '\n').split('\n')) {
            if (String.isNotBlank(part)) out.add(part.trim());
        }
        return out;
    }

    public Decimal getReimbursedTotal() {
        Decimal total = 0;
        for (BenefitRow b : benefitLines) total += nz(b.amount);
        return total;
    }

    // ─────────────────── reimbursement notice (TASK-051) ───────────────────
    // Mirrors the Reimbursement Only block of showOrderWorkSummary.

    public String getReceiptsTotalDisplay() {
        Decimal total = 0;
        for (BenefitRow b : benefitLines) total += nz(b.receipts);
        return money(total);
    }

    public Boolean getAnyOver() {
        for (BenefitRow b : benefitLines) if (b.hasOver) return true;
        return false;
    }

    /** From the work order's own snapshot, never the live estimate. */
    public String getPaymentMethodDisplay() {
        return String.isNotBlank(order.Reimbursement_Payment_Method__c)
            ? order.Reimbursement_Payment_Method__c : 'n/a';
    }

    /** "October 27, 2026", the preview's en-CA long date; n/a when blank. */
    public String getExpectedPaymentDisplay() {
        Date d = order.Reimbursement_Expected_Payment_Date__c;
        if (d == null) return 'n/a';
        return Datetime.newInstance(d.year(), d.month(), d.day()).format('MMMM d, yyyy');
    }

    public String getQuestionsLine() {
        String claimName = String.isNotBlank(order.Claim__r?.Name) ? order.Claim__r.Name : 'number';
        return 'Questions? Call 1-866-660-7444 or e-mail info@a-protectwarranty.com and quote claim '
            + claimName + '.';
    }

    /** Year, make, model and trim, from the snapshot rather than recomposed live. */
    public String getVehicleDisplay() {
        List<String> bits = new List<String>();
        for (String s : new List<String>{ order.Vehicle_Year__c, order.Vehicle_Make__c,
                                          order.Vehicle_Model__c, order.Vehicle_Trim__c }) {
            if (String.isNotBlank(s)) bits.add(s.trim());
        }
        return bits.isEmpty() ? 'n/a' : String.join(bits, ' ');
    }

    /** The unit comes from the record; this document must not assume kilometres. */
    public String getOdometerDisplay() {
        if (order.Odometer_In__c == null) return 'n/a';
        String shown = order.Odometer_In__c.setScale(0, RoundingMode.HALF_UP).format();
        return String.isNotBlank(order.Odometer_In_Unit__c)
            ? shown + ' ' + order.Odometer_In_Unit__c
            : shown;
    }

    public String getShopDisplay() {
        return String.isNotBlank(order.Repair_Shop__r?.Name) ? order.Repair_Shop__r.Name : 'n/a';
    }

    public String getShopContactDisplay() {
        List<String> bits = new List<String>();
        if (String.isNotBlank(order.Repair_Shop__r?.Address__c)) bits.add(order.Repair_Shop__r.Address__c);
        if (String.isNotBlank(order.Repair_Shop__r?.Phone__c))   bits.add(order.Repair_Shop__r.Phone__c);
        return bits.isEmpty() ? 'n/a' : String.join(bits, ' · ');
    }

    public Boolean getHasLines() {
        return lines != null && !lines.isEmpty();
    }

    public Date getToday() {
        return Date.today();
    }

    private static Decimal nz(Decimal d) {
        return d == null ? 0 : d;
    }

    /**
     * Mirrors showOrderWorkSummary.money(), but builds the cents explicitly.
     *
     * Decimal.format() drops a trailing ".00", so 3000 printed as "$3,000"
     * while 538.07 printed as "$538.07" on the same document. A money column
     * has to be uniform, so the integer part is grouped by format() and the
     * two cents digits are appended by hand.
     */
    private static String money(Decimal d) {
        Decimal v = nz(d).setScale(2, RoundingMode.HALF_UP);
        Boolean isNeg = v < 0;
        Decimal abs = isNeg ? -v : v;
        Long whole = abs.longValue();
        Integer cents = Integer.valueOf(((abs - whole) * 100).setScale(0, RoundingMode.HALF_UP));
        String out = '$' + Decimal.valueOf(whole).format()
            + '.' + String.valueOf(cents).leftPad(2, '0');
        return isNeg ? MINUS + out : out;
    }

    /**
     * A credit, shown as a negative. showOrderWorkSummary uses U+2212, a true
     * minus sign, but Salesforce's PDF renderer dropped that glyph entirely,
     * so a credit printed as "$100" with no sign at all and read as a charge
     * on a customer document. An ordinary hyphen-minus renders reliably, and
     * the project's no-dashes rule covers punctuation rather than arithmetic.
     */
    private static final String MINUS = '-';

    private static String negative(Decimal d) {
        return MINUS + money(d == null ? 0 : Math.abs(d));
    }

    public class WorkOrderPDFException extends Exception {}
}