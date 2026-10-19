import { LightningElement, api } from 'lwc';
import TIME_ZONE from '@salesforce/i18n/timeZone';

const CAD = new Intl.NumberFormat('en-CA', { style: 'currency', currency: 'CAD' });
const NUM = new Intl.NumberFormat('en-CA');
const NA = 'n/a';

/**
 * Work Order Summary (TASK-047), the new UI Noelle's Repair Price Scenarios
 * Feedback 1.0 puts directly below the scenario cards.
 *
 * Replaces the "What Client Sees / What A-Protect sees" breakdown that
 * createWorkOrderAction renders on the Work Order tab. The underlying numbers
 * are the same idea; the presentation is the authorization document from the
 * design, not the two-column internal view.
 *
 * PREVIEW ONLY, and deliberately so (Osama's decision 3): this component
 * never creates a Work_Order__c. Main.dc.html has no Create Work Order button
 * and shows the preview permanently for whichever scenario is marked Use, so
 * that is what this does. Actually creating the record stays where it already
 * is, on the Work Order tab via createWorkOrderAction, which is untouched.
 *
 * Takes everything as @api properties rather than making its own Apex call.
 * That is what makes it reusable per requirement 20: the parent has already
 * computed every figure live for the scenario cards, so re-querying here
 * would both duplicate the round trip and risk the preview disagreeing with
 * the card above it.
 */
export default class ShowOrderWorkSummary extends LightningElement {
    @api claimNumber;
    @api vehicle;
    @api scenarioName;
    @api shopName;
    @api shopContact;
    @api cap;
    @api deductible;

    /**
     * The computed scenario, shaped by the parent to mirror
     * ClaimPricingService.ScenarioResult:
     *   { isReimbursement, lines: [{description, amount}], subTotal,
     *     taxPercent, tax, totalDue, coverageApplied, benefits:
     *     [{name, amount}], benefitsTotal, customerPays, fullyCovered,
     *     reimbursedToCustomer }
     * plus, on a reimbursement (TASK-051): benefits rows also carry
     * {receipts, leftOnTerm, over}, and receiptsTotal, paymentMethod,
     * expectedPaymentDate.
     */
    @api summary;

    /**
     * Document header, READ from the claim. It used to be typed into the
     * preview by hand, which meant the figures on a document going out for
     * authorization depended on an agent retyping them correctly. TASK-050:
     * every value now comes from an existing field on Claim__c and the work
     * order snapshots the same values when it is created.
     */
    @api header = {};

    // ───────────────────────────── state ─────────────────────────────

    get hasSummary() {
        return !!this.summary;
    }

    get isReimbursement() {
        return !!(this.summary && this.summary.isReimbursement);
    }

    get isRepair() {
        return this.hasSummary && !this.isReimbursement;
    }

    get title() {
        return this.isReimbursement ? 'Reimbursement Authorization' : 'Claim Authorization';
    }

    get sourceLabel() {
        return this.scenarioName ? `From scenario: ${this.scenarioName}` : '';
    }

    /**
     * Osama, 2026-10-09: the preview showed 9 October while the PDF showed 8
     * October. The preview was using the BROWSER's timezone and the PDF uses
     * Date.today(), which is the Salesforce user's. Across midnight the two
     * documents disagreed about their own date.
     *
     * Both now use the Salesforce user's timezone, which is the right one for
     * a document A-Protect issues: it should not change because the person
     * looking at it is travelling.
     */
    get today() {
        return new Date().toLocaleDateString('en-CA', {
            timeZone: TIME_ZONE,
            year: 'numeric',
            month: 'long',
            day: 'numeric'
        });
    }

    get shopDisplay() {
        return this.shopName || NA;
    }

    get shopContactDisplay() {
        return this.shopContact || NA;
    }

    get vehicleDisplay() {
        return this.vehicle || NA;
    }

    // ──────────────────────── formatted figures ───────────────────────

    get lines() {
        const lines = (this.summary && this.summary.lines) || [];
        return lines.map((l, index) => ({
            key: `${index}-${l.description}`,
            description: l.description,
            amount: this.money(l.amount)
        }));
    }

    get benefitLines() {
        const benefits = (this.summary && this.summary.benefits) || [];
        return benefits.map((b, index) => ({
            key: `${index}-${b.name}`,
            name: b.name,
            label: `Ancillary Benefit: ${b.name}`,
            amount: this.money(b.amount),
            credit: this.negative(b.amount),
            // TASK-051, reimbursement rows only: the parent sends these just
            // for a Reimbursement Only scenario.
            receipts: this.money(b.receipts),
            // null means no balance was found for the benefit. Number(null)
            // is 0, so it has to be caught here or it would print $0.00.
            leftOnTerm: b.leftOnTerm === null || b.leftOnTerm === undefined ? NA : this.money(b.leftOnTerm),
            overNote: Number(b.over) > 0
                ? `${this.money(b.over)} is over the benefit limit and is not covered`
                : ''
        }));
    }

    // ─────────────────── reimbursement notice (TASK-051) ───────────────────

    get receiptsTotal() { return this.money(this.summary && this.summary.receiptsTotal); }

    get approvedTotal() {
        const benefits = (this.summary && this.summary.benefits) || [];
        return this.money(benefits.reduce((a, b) => a + (Number(b.amount) || 0), 0));
    }

    get anyOver() {
        const benefits = (this.summary && this.summary.benefits) || [];
        return benefits.some((b) => Number(b.over) > 0);
    }

    get paymentMethodDisplay() {
        return (this.summary && this.summary.paymentMethod) || NA;
    }

    /**
     * Estimate__c.Reimbursement_Expected_Payment_Date__c arrives as YYYY-MM-DD.
     * Built as a local calendar date, not parsed as UTC midnight, so it cannot
     * print as the day before in a timezone west of Greenwich.
     */
    get expectedPaymentDisplay() {
        const raw = this.summary && this.summary.expectedPaymentDate;
        const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(raw || '');
        if (!m) return NA;
        return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])).toLocaleDateString('en-CA', {
            year: 'numeric',
            month: 'long',
            day: 'numeric'
        });
    }

    get questionsLine() {
        return 'Questions? Call 1-866-660-7444 or e-mail info@a-protectwarranty.com and quote claim '
             + `${this.claimNumber || 'number'}.`;
    }

    get hasBenefitLines() {
        return this.benefitLines.length > 0;
    }

    get subTotal()        { return this.money(this.summary && this.summary.subTotal); }
    get taxLabel()        { return `HST (${this.numberOr(this.summary && this.summary.taxPercent, 0)}%):`; }
    get tax()             { return this.money(this.summary && this.summary.tax); }
    get totalDue()        { return this.money(this.summary && this.summary.totalDue); }
    get capDisplay()      { return this.money(this.cap); }
    get deductibleCredit(){ return this.negative(this.deductible); }
    get coverageCredit()  { return this.negative(this.summary && this.summary.coverageApplied); }
    get customerPays()    { return this.money(this.summary && this.summary.customerPays); }
    get reimbursedTotal() { return this.money(this.summary && this.summary.reimbursedToCustomer); }
    get zero()            { return this.money(0); }

    get isFullyCovered() {
        return !!(this.summary && this.summary.fullyCovered);
    }

    get fullyCoveredNote() {
        return `Repair fully covered within the ${this.money(this.cap)} claim limit. `
             + 'Customer is responsible for the deductible and shop supplies only.';
    }

    // ───────────────────────────── header ─────────────────────────────

    get applicationNumber() { return this.header.applicationNumber; }
    get customerName()      { return this.header.customerName; }
    get customerAddress()   { return this.header.customerAddress; }

    /**
     * Claim__c.Customer_Address__c is a formula that embeds literal <br> tags,
     * so the address printed as "123 STREET TEST<br>Toronto, ON" on one line.
     * Splitting here renders it properly without resorting to innerHTML on a
     * value that reaches a customer-facing document. The PDF controller does
     * the same thing in getCustomerAddressLines; the two must stay in step.
     */
    get customerAddressLines() {
        return (this.header.customerAddress || '')
            .split(/<br\s*\/?>/i)
            .map((line) => line.trim())
            .filter((line) => line.length > 0)
            .map((text, index) => ({ key: `${index}-${text}`, text }));
    }
    get customerPhone()     { return this.header.customerPhone; }
    get customerEmail()     { return this.header.customerEmail; }
    get vin()               { return this.header.vin; }

    /**
     * The unit comes from the record rather than being assumed. The label used
     * to read "Odometer In (KM)" regardless of what the claim actually said.
     */
    get odometerDisplay() {
        const v = this.header.odometer;
        if (v === null || v === undefined || v === '') {
            return '';
        }
        const n = Number(v);
        const shown = Number.isFinite(n) ? NUM.format(n) : v;
        return this.header.odometerUnit ? `${shown} ${this.header.odometerUnit}` : `${shown}`;
    }

    // ───────────────────────────── helpers ────────────────────────────

    /** Empty cells read "n/a", never a blank or a dash, per the content rules. */
    money(value) {
        const n = Number(value);
        return Number.isFinite(n) ? CAD.format(n) : NA;
    }

    /** A credit shown against the customer's bill, using a real minus sign. */
    negative(value) {
        const n = Number(value);
        return Number.isFinite(n) ? `−${CAD.format(Math.abs(n))}` : NA;
    }

    numberOr(value, fallback) {
        const n = Number(value);
        return Number.isFinite(n) ? n : fallback;
    }
}