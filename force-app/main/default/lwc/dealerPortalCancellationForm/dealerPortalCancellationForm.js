import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import getFormContext from '@salesforce/apex/CancellationFormController.getFormContext';
import estimateRefund from '@salesforce/apex/CancellationFormController.estimateRefund';
import submitRequest from '@salesforce/apex/CancellationFormController.submitRequest';

const REASONS = [
    { label: 'Customer Request', value: 'Customer Request' },
    { label: 'Vehicle Sold/Traded', value: 'Vehicle Sold/Traded' },
    { label: 'Repossession', value: 'Repossession' },
    { label: 'Total Loss', value: 'Total Loss' },
    { label: 'Contract Back Out', value: 'Contract Back Out' },
    { label: 'Other', value: 'Other' }
];

const TERMS_HEADINGS = [
    'Cancellation Request',
    'Dealer Responsibility for Refunds',
    'Customer Funds',
    'Financed Contracts / Lienholders',
    'Accuracy of Information',
    'Supporting Documentation',
    'Dealer Accountability',
    'A-Protect Review'
];

const GROUP_ORDER = [
    'Extended Limited Warranty',
    'Tire and Rim Protection Plan',
    'GAP Coverage',
    'Roadside Assistance'
];

// Used ONLY when the server supplies no category (Dealer_Package__r.Plan_Type__r.Name
// is blank). A service that has a real category never lands here.
const FALLBACK_CATEGORY = 'Other Services';

// Printed once by the template, above the parsed sub-sections. If the stored
// terms text also contains it, the parser strips it so it cannot appear twice.
const TERMS_LEAD_IN = 'By signing and submitting this form, the dealership acknowledges and agrees to the following:';

// Shown when the page was opened without a real application id. The portal's
// Applications list passes its own ListView id (00B...) in the url, so this is
// the common case for a bookmarked or stale link.
const LINK_MESSAGE = "This link doesn't point to an application — open it from the Applications list.";

// Application__c ids start with a01. Anything else (a ListView 00B id, an
// account id, a truncated string) is not an application.
const APPLICATION_ID_RE = /^a01[a-zA-Z0-9]{12}([a-zA-Z0-9]{3})?$/;

// The server rejects anything above 3,000,000 base64 characters (~2 MB). Catching
// it here means an oversized canvas signature fails before the Apex call rather
// than after the dealer has waited for a round trip.
const MAX_SIGNATURE_CHARS = 3000000;

function escapeRegExp(value) {
    return String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// The parser matches the lead-in case-insensitively. It is BUILT from
// TERMS_LEAD_IN so the string and the pattern can never drift apart again.
// The previous build referenced an undefined TERMS_LEAD_IN_RE, which threw a
// ReferenceError inside the termsBlocks getter during template render and left
// the whole component stuck on its loading spinner.
const TERMS_LEAD_IN_RE = new RegExp(escapeRegExp(TERMS_LEAD_IN), 'i');

export default class DealerPortalCancellationForm extends NavigationMixin(LightningElement) {
    @api applicationId;
    @api showBackButton = false;

    @track ctx;
    @track isLoading = true;
    @track error;
    @track selectedPackageIds = new Set();
    @track selectAll = false;
    @track reasonCode = '';
    @track reasonDetail = '';
    @track termsAccepted = false;
    @track submitting = false;
    @track submitResult;
    @track showSuccess = false;
    @track actionError = '';
    @track submitWarning = '';
    // Set when the page was opened with something that is not an application id.
    // While this is set the form is never rendered: there is nothing to submit to.
    @track linkProblem = null;

    // Refund estimate for the CURRENT selection only. Starts at 0 and is never
    // populated from the server's all-packages total on load.
    @track refundEstimate = 0;

    // Signature canvas state
    drawing = false;
    lastX = 0;
    lastY = 0;
    @track signatureDataUrl = null;
    @track hasSignature = false;

    @wire(CurrentPageReference)
    handlePageRef(pageRef) {
        if (!this.applicationId && pageRef) {
            const state = pageRef.state || {};
            const candidate = state.c__appId || state.appId || state.applicationId;
            if (candidate) {
                this.applicationId = candidate;
                // A page reference can arrive after connectedCallback saw nothing.
                if (!this.ctx && this.isApplicationId(candidate)) {
                    this.linkProblem = null;
                    this.error = null;
                    this.loadContext();
                }
            }
        }
    }

    connectedCallback() {
        if (!this.applicationId) {
            const params = new URLSearchParams(window.location.search);
            this.applicationId = params.get('c__appId') || params.get('appId') || params.get('applicationId');
        }
        if (!this.isApplicationId(this.applicationId)) {
            // Never render the form for a link that cannot be submitted.
            this.linkProblem = LINK_MESSAGE;
            this.error = LINK_MESSAGE;
            this.isLoading = false;
            return;
        }
        this.loadContext();
    }

    isApplicationId(value) {
        return !!value && APPLICATION_ID_RE.test(String(value).trim());
    }

    async loadContext() {
        if (this._loadStarted) return;
        this._loadStarted = true;
        this.isLoading = true;
        this.error = null;
        this.linkProblem = null;
        try {
            this.ctx = await getFormContext({ applicationId: this.applicationId });
            // The server's ctx.estimatedTotal is the total of ALL active packages and
            // must never be shown before the dealer selects something. Start from an
            // empty selection and a zeroed estimate.
            this.selectedPackageIds = new Set();
            this.selectAll = false;
            this.refundEstimate = 0;
            if (!this.ctx.eligible) {
                this.error = this.ctx.ineligibleReason || 'This application is not eligible for cancellation.';
            }
        } catch (e) {
            const message = this.reduceError(e);
            // A rejected identifier is not a generic failure: show the link card,
            // with the Applications list as the only way forward.
            if (message === LINK_MESSAGE || /^application not found\.?$/i.test(String(message).trim())) {
                this.linkProblem = LINK_MESSAGE;
                this.error = LINK_MESSAGE;
            } else {
                this.error = message;
            }
        } finally {
            this.isLoading = false;
        }
    }

    get reasonOptions() { return REASONS; }
    get isOtherReason() { return this.reasonCode === 'Other'; }
    get hasPackages() { return this.ctx && this.ctx.packages && this.ctx.packages.length > 0; }
    get selectedCount() { return this.selectedPackageIds.size; }
    // Zero selection => $0, regardless of what the server pre-computed.
    get estimatedTotal() {
        return this.selectedPackageIds.size === 0 ? 0 : this.refundEstimate;
    }

    // Date of Request is always the date the form is opened.
    get dateRequestedDisplay() {
        const today = new Date();
        const raw = this.ctx ? this.ctx.dateRequested : null;
        if (raw) {
            const parsed = new Date(raw);
            if (!isNaN(parsed.getTime()) && this.isSameDay(parsed, today)) {
                return this.formatDate(parsed);
            }
        }
        return this.formatDate(today);
    }

    isSameDay(a, b) {
        return a.getFullYear() === b.getFullYear()
            && a.getMonth() === b.getMonth()
            && a.getDate() === b.getDate();
    }

    formatDate(d) {
        const dd = String(d.getDate()).padStart(2, '0');
        const mm = String(d.getMonth() + 1).padStart(2, '0');
        return `${dd}/${mm}/${d.getFullYear()}`;
    }

    get canSubmit() {
        return this.missingRequirement === null && !this.submitting;
    }
    get disableSave() { return !this.canSubmit; }
    // Shown inline under the submit button so a disabled button is never a dead end.
    get submitBlocked() { return !this.submitting && this.missingRequirement !== null; }
    get missingRequirement() {
        if (!this.ctx) return 'The application has not loaded yet.';
        if (this.ctx.eligible !== true) {
            return this.ctx.ineligibleReason || 'This application is not eligible for cancellation.';
        }
        if (!this.hasPackages) return 'There are no active services to cancel on this application.';
        if (this.selectedCount === 0) return 'Select at least one service to cancel.';
        if (!this.hasReason) return 'Select a reason for cancellation.';
        if (this.isOtherReason && !this.hasReasonDetail) return 'Please explain the reason for cancellation.';
        if (this.termsAccepted !== true) return 'Accept the cancellation terms and conditions.';
        if (this.hasSignature !== true) return 'Capture the dealer representative signature above.';
        return null;
    }
    get hasReason() { return !!(this.reasonCode && String(this.reasonCode).trim()); }
    get hasReasonDetail() { return !!(this.reasonDetail && String(this.reasonDetail).trim()); }
    get showSummary() { return this.ctx && this.ctx.hasOpenRequest === true; }

    // Presentation-only: group the application's service lines for the document layout.
    // The category is the real one from the server (Dealer_Package__r.Plan_Type__r.Name);
    // the name-keyword heuristic is a fallback for packages with no plan type only.
    get groupedServices() {
        if (!this.ctx || !this.ctx.packages) return [];
        const groups = new Map();
        for (const p of this.ctx.packages) {
            const cat = this.resolveCategory(p);
            if (!groups.has(cat)) groups.set(cat, []);
            groups.get(cat).push({
                packageId: p.packageId,
                name: p.name,
                selected: this.selectedPackageIds.has(p.packageId),
                termLine: this.buildTermLine(p),
                addonsLabel: this.buildAddonsLabel(p.addOns),
                formattedEstimate: this.formatCurrency(p.estimate)
            });
        }
        return Array.from(groups.entries())
            .sort((a, b) => this.compareCategories(a[0], b[0]))
            .map(([category, items]) => ({ category, items }));
    }

    resolveCategory(p) {
        const real = p && p.category ? String(p.category).trim() : '';
        if (real) return real;
        return this.deriveCategory(p ? p.name : null);
    }

    compareCategories(a, b) {
        const ra = this.groupRank(a);
        const rb = this.groupRank(b);
        if (ra !== rb) return ra - rb;
        return String(a).localeCompare(String(b));
    }

    // Presentation-only: the prototype renders one `.service-block` per service,
    // each headed by its category name.
    get serviceRows() {
        const rows = [];
        for (const group of this.groupedServices) {
            for (const item of group.items) {
                rows.push({
                    packageId: item.packageId,
                    name: item.name,
                    selected: item.selected,
                    termLine: item.termLine,
                    addonsLabel: item.addonsLabel,
                    category: group.category
                });
            }
        }
        return rows;
    }

    get showConfirmBox() { return this.selectedCount > 0; }

    get confirmText() {
        if (this.rowsForSelection().length === 1) {
            return '1 service selected for cancellation.';
        }
        return `${this.rowsForSelection().length} services selected for cancellation.`;
    }

    rowsForSelection() {
        return (this.serviceRows || []).filter(r => r.selected);
    }

    get successSummary() {
        const rows = this.rowsForSelection();
        const parts = [];
        const requestName = this.submitResult ? String(this.submitResult.requestName || '') : '';
        if (/^CR-\d+$/i.test(requestName)) {
            parts.push(`Request ${requestName}`);
        }
        if (this.ctx && this.ctx.applicationNumber) {
            parts.push(`Application ${this.ctx.applicationNumber}`);
        }
        if (rows.length) {
            parts.push(`${rows.length} service(s)`);
        }
        parts.push(this.refundAmountDisplay);
        return parts.join(' · ');
    }

    // The dialog must not claim a clean success when the request was saved but its
    // signature or approval routing degraded - the record exists either way.
    get successTitle() {
        return this.submitResult && this.submitResult.success === true
            ? 'Request submitted successfully'
            : 'Request saved';
    }

    get successMessage() {
        if (this.submitWarning) return this.submitWarning;
        return 'Please wait for the approval from A-Protect for confirmation of cancellation.';
    }

    handleCloseSuccess() {
        // The cancellations list page is not configured in the dealer portal, so
        // "View All Requests" led nowhere. The dialog now has one action: close it
        // and return to the applications list, exactly like the form's Cancel.
        this.showSuccess = false;
        this.handleBackToList();
    }

    groupRank(name) {
        if (name === FALLBACK_CATEGORY) return Number.MAX_SAFE_INTEGER;
        const i = GROUP_ORDER.indexOf(name);
        return i < 0 ? GROUP_ORDER.length : i;
    }

    // Fallback only - used when the dealer package has no Plan_Type (category null).
    deriveCategory(name) {
        const s = (name || '').toLowerCase();
        if (s.indexOf('tire') > -1 || s.indexOf('rim') > -1) return 'Tire and Rim Protection Plan';
        if (s.indexOf('gap') > -1) return 'GAP Coverage';
        if (s.indexOf('roadside') > -1) return 'Roadside Assistance';
        if (s.indexOf('warranty') > -1 || s.indexOf('protection') > -1) return 'Extended Limited Warranty';
        return FALLBACK_CATEGORY;
    }

    buildTermLine(p) {
        const term = p.term || '—';
        if (p.retailPrice == null) return `Selected Term: ${term}`;
        return `Selected Term: ${term} (${this.formatCompact(p.retailPrice)})`;
    }

    buildAddonsLabel(addOns) {
        if (!addOns || !addOns.length) return '-';
        return addOns
            .map(a => a.price == null ? a.name : `${a.name} (${this.formatCompact(a.price)})`)
            .join(', ');
    }

    // Presentation-only: split termsText into heading/body blocks.
    //
    // The stored copy (Cancellation_Settings__mdt.Terms_Text__c) is plain text that
    // already begins with the lead-in sentence the template prints above the blocks,
    // and its sub-section titles are ALL CAPS. Rendering it naively produced a
    // synthetic "Terms" heading followed by a second copy of the lead-in, so the
    // text is normalised first: HTML is flattened, the lead-in and any redundant
    // "Terms" heading are dropped, and headings are recognised case-insensitively.
    get termsBlocks() {
        if (!this.ctx || !this.ctx.termsText) return [];
        let lines;
        try {
            lines = this.normaliseTermsText(this.ctx.termsText);
        } catch (e) {
            // This getter runs during template render. If it throws, the render
            // aborts and the component is left showing whatever was on screen
            // before - which is the loading spinner. Never throw here: fall back
            // to the raw terms text so the form still renders and the dealer can
            // read the terms they are being asked to accept.
            return [{ key: 'terms-0', heading: '', hasHeading: false, body: String(this.ctx.termsText) }];
        }
        const blocks = [];
        let current = null;
        let index = 0;
        for (const line of lines) {
            const heading = this.matchTermsHeading(line);
            if (heading) {
                if (current) blocks.push(current);
                current = { key: 'terms-' + (index++), heading, hasHeading: true, body: '' };
            } else if (current) {
                current.body = current.body ? current.body + ' ' + line : line;
            } else {
                // Text before the first sub-section: render as body only, never
                // under a synthetic "Terms" heading.
                current = { key: 'terms-' + (index++), heading: '', hasHeading: false, body: line };
            }
        }
        if (current) blocks.push(current);
        return blocks.filter(b => b.hasHeading || (b.body && b.body.length));
    }

    normaliseTermsText(raw) {
        let text = String(raw == null ? '' : raw);
        // Tolerate HTML in the stored value: block tags become line breaks, all
        // remaining markup is dropped, and the entities used in legal copy decode.
        text = text
            .replace(/<\s*br\s*\/?\s*>/gi, '\n')
            .replace(/<\s*\/\s*(p|div|li|h[1-6]|tr)\s*>/gi, '\n')
            .replace(/<[^>]*>/g, ' ')
            .replace(/&nbsp;/gi, ' ')
            .replace(/&quot;/gi, '"')
            .replace(/&#0?39;|&apos;/gi, "'")
            .replace(/&lt;/gi, '<')
            .replace(/&gt;/gi, '>')
            .replace(/&amp;/gi, '&');

        const rawLines = text
            .split(/\r?\n/)
            .map(line => line.replace(/\s+/g, ' ').trim())
            .filter(line => line.length > 0);

        const lines = [];
        for (const rawLine of rawLines) {
            // The lead-in is printed once by the template. When the stored copy
            // repeats it, drop the sentence but keep anything that followed it on
            // the same line (which is often the first sub-section heading).
            const remainder = this.stripTermsLeadIn(rawLine);
            const source = remainder === null ? rawLine : remainder;
            if (!source) continue;
            for (const part of this.splitHeadingLine(source)) {
                lines.push(part);
            }
        }

        // A "Terms" / "Terms and Conditions" line directly above the first
        // sub-section duplicates the section 3 heading - drop it too.
        while (lines.length && this.isRedundantTermsHeading(lines[0])) {
            lines.shift();
        }
        return lines;
    }

    /** Returns null when the line is not the lead-in, else the text after it. */
    stripTermsLeadIn(line) {
        const match = line.match(TERMS_LEAD_IN_RE);
        if (!match) return null;
        return line.substring(match[0].length).replace(/^[:\u2013\u2014-]\s*/, '').trim();
    }

    /** "CUSTOMER FUNDS: body" on one line becomes heading + body. */
    splitHeadingLine(line) {
        const match = line.match(/^([A-Z0-9][A-Z0-9\s/&'’\-()]{2,79}?)\s*:\s+(.+)$/);
        if (match && /[A-Z]{3,}/.test(match[1]) && match[1].indexOf(',') === -1) {
            return [match[1].trim(), match[2].trim()];
        }
        return [line];
    }

    isRedundantTermsHeading(line) {
        const normalised = line.toLowerCase().replace(/[\s]+/g, ' ').replace(/[.:]+$/, '').trim();
        return normalised === 'terms'
            || normalised === 'terms and conditions'
            || normalised === 'cancellation terms'
            || normalised === 'cancellation terms and conditions';
    }

    matchTermsHeading(line) {
        const trimmed = (line || '').trim();
        if (!trimmed) return null;
        const stripped = trimmed.replace(/[:\s]+$/, '');
        const canonical = TERMS_HEADINGS.find(h => h.toLowerCase() === stripped.toLowerCase());
        if (canonical) return canonical;

        // Any other short ALL-CAPS line is a heading (the stored copy uses upper
        // case titles that are not in the canonical list).
        const looksUpper = /^[A-Z0-9][A-Z0-9\s/&'’\-()]*[A-Z0-9)]$/.test(stripped);
        const hasBodyPunctuation = /[.,]/.test(stripped);
        if (looksUpper && !hasBodyPunctuation && stripped.length <= 80 && /[A-Z]{3,}/.test(stripped)) {
            return this.titleCaseHeading(stripped);
        }
        return null;
    }

    titleCaseHeading(heading) {
        const minor = new Set(['and', 'or', 'of', 'the', 'for', 'to', 'a', 'an', 'in', 'on']);
        const words = heading.toLowerCase().split(/\s+/);
        return words
            .map((word, i) => {
                if (word.indexOf('a-protect') === 0) return 'A-Protect' + word.substring('a-protect'.length);
                if (i > 0 && minor.has(word)) return word;
                return word.charAt(0).toUpperCase() + word.slice(1);
            })
            .join(' ');
    }

    get refundAmountDisplay() {
        return this.formatCompact(this.estimatedTotal || 0);
    }

    // --- Selection ---
    handleSelectAll(e) {
        const checked = e.target.checked;
        this.selectAll = checked;
        const next = new Set();
        if (checked && this.ctx && this.ctx.packages) {
            this.ctx.packages.forEach(p => next.add(p.packageId));
        }
        this.selectedPackageIds = next;
        this.refreshEstimate();
    }

    handlePackageToggle(e) {
        const pid = e.target.dataset.id;
        if (!pid) return;
        const next = new Set(this.selectedPackageIds);
        if (e.target.checked) {
            next.add(pid);
        } else {
            next.delete(pid);
            this.selectAll = false;
        }
        this.selectedPackageIds = next;
        this.refreshEstimate();
    }

    async refreshEstimate() {
        // Sequence token: a slow response for an older selection must not
        // overwrite the amount for the current one.
        this._estimateSeq = (this._estimateSeq || 0) + 1;
        const seq = this._estimateSeq;
        const ids = Array.from(this.selectedPackageIds || []);

        if (!this.applicationId || ids.length === 0) {
            this.refundEstimate = 0;
            return;
        }

        try {
            const res = await estimateRefund({
                applicationId: this.applicationId,
                packageIds: ids
            });
            if (seq !== this._estimateSeq) return;
            this.refundEstimate = this.selectedPackageIds.size === 0 ? 0 : ((res && res.total) || 0);
        } catch (e) {
            if (seq !== this._estimateSeq) return;
            // Non-fatal: fall back to the line estimates for the selected services
            // only, never to the server's all-package total.
            this.refundEstimate = this.sumSelectedEstimates(ids);
        }
    }

    sumSelectedEstimates(ids) {
        if (!this.ctx || !this.ctx.packages) return 0;
        const wanted = new Set(ids);
        let total = 0;
        for (const p of this.ctx.packages) {
            if (wanted.has(p.packageId)) total += Number(p.estimate) || 0;
        }
        return total;
    }

    // --- Reason ---
    // The reason control is a native <select>, whose change event carries the value
    // on e.target.value. Reading e.detail.value threw on every change, so reasonCode
    // stayed empty and the submit button could never enable. Accept both shapes so
    // the handler is safe if the control is later swapped for lightning-combobox.
    handleReasonChange(e) {
        const fromDetail = e && e.detail && e.detail.value !== undefined ? e.detail.value : undefined;
        const value = fromDetail !== undefined ? fromDetail : (e && e.target ? e.target.value : '');
        this.reasonCode = value == null ? '' : String(value);
    }
    handleDetailChange(e) {
        this.reasonDetail = e && e.target && e.target.value != null ? String(e.target.value) : '';
    }

    // --- Terms ---
    handleTermsAccept(e) { this.termsAccepted = e.target.checked; }

    // --- Signature canvas ---
    get canvas() { return this.template.querySelector('canvas.sig-canvas'); }

    handleCanvasPointerDown(e) {
        const c = this.canvas;
        if (!c) return;
        this.drawing = true;
        const p = this.point(e, c);
        this.lastX = p.x; this.lastY = p.y;
        const ctx = c.getContext('2d');
        ctx.beginPath(); ctx.moveTo(p.x, p.y);
    }
    handleCanvasPointerMove(e) {
        if (!this.drawing) return;
        const c = this.canvas;
        if (!c) return;
        const p = this.point(e, c);
        const ctx = c.getContext('2d');
        ctx.lineTo(p.x, p.y);
        ctx.stroke();
        this.lastX = p.x; this.lastY = p.y;
    }
    handleCanvasPointerUp() {
        if (!this.drawing) return;
        this.drawing = false;
        this.captureSignature();
    }
    point(e, c) {
        const r = c.getBoundingClientRect();
        return {
            x: ((e.clientX - r.left) / r.width) * c.width,
            y: ((e.clientY - r.top) / r.height) * c.height
        };
    }
    captureSignature() {
        const c = this.canvas;
        if (!c) return;
        this.signatureDataUrl = c.toDataURL('image/png');
        this.hasSignature = true;
    }
    handleClearSignature() {
        const c = this.canvas;
        if (!c) return;
        const ctx = c.getContext('2d');
        ctx.fillStyle = '#ffffff';
        ctx.fillRect(0, 0, c.width, c.height);
        this.signatureDataUrl = null;
        this.hasSignature = false;
    }
    initCanvas() {
        const c = this.canvas;
        if (!c) return;
        const ctx = c.getContext('2d');
        ctx.fillStyle = '#ffffff';
        ctx.fillRect(0, 0, c.width, c.height);
        ctx.lineWidth = 2.2;
        ctx.lineCap = 'round';
        ctx.lineJoin = 'round';
        ctx.strokeStyle = '#111827';
    }

    renderedCallback() {
        if (!this._canvasInit) {
            setTimeout(() => {
                this.initCanvas();
                this._canvasInit = true;
            }, 0);
        }
    }

    // --- Submit ---
    async handleSubmit() {
        if (this.submitting) return;

        // Every guard below sets a visible message. A disabled button is not an
        // explanation, and a submit that exits silently is indistinguishable from
        // one that succeeded.
        if (!this.isApplicationId(this.applicationId)) {
            this.linkProblem = LINK_MESSAGE;
            this.actionError = LINK_MESSAGE;
            return;
        }
        const missing = this.missingRequirement;
        if (missing !== null) {
            this.actionError = missing;
            return;
        }
        const pngB64 = this.signatureBase64();
        if (!pngB64) {
            this.actionError = 'Capture the dealer representative signature above.';
            return;
        }
        if (pngB64.length > MAX_SIGNATURE_CHARS) {
            this.actionError = 'The signature is too large to submit. Clear it and sign again.';
            return;
        }

        this.submitting = true;
        this.actionError = '';
        this.submitWarning = '';
        try {
            const res = await submitRequest({
                applicationId: this.applicationId,
                packageIds: Array.from(this.selectedPackageIds),
                reasonCode: this.reasonCode,
                reasonDetail: this.reasonDetail || null,
                termsAccepted: this.termsAccepted,
                termsVersion: this.ctx ? this.ctx.termsVersion : '1.0',
                signaturePngB64: pngB64,
                repName: this.ctx ? this.ctx.repName : null,
                repTitle: this.ctx ? this.ctx.repTitle : null
            });
            this.submitResult = res || null;
            // The request is only reported as created when the server returned the
            // id it inserted. Anything else is an error, never a success dialog.
            if (res && res.requestId) {
                this.submitWarning = res.warning || (res.success === true ? '' : (res.message || ''));
                this.showSuccess = true;
            } else {
                this.actionError = (res && res.message)
                    ? res.message
                    : 'Submission failed — no cancellation request was created.';
            }
        } catch (e) {
            this.actionError = this.reduceError(e) || 'Submission failed — no cancellation request was created.';
        } finally {
            this.submitting = false;
        }
    }

    /** Base64 payload of the captured signature, or null when there is none usable. */
    signatureBase64() {
        if (!this.hasSignature || !this.signatureDataUrl) return null;
        const raw = String(this.signatureDataUrl);
        const comma = raw.indexOf(',');
        const b64 = comma >= 0 ? raw.substring(comma + 1) : raw;
        const trimmed = b64 ? b64.trim() : '';
        return trimmed.length ? trimmed : null;
    }

    handleBackToList() {
        const evt = new CustomEvent('back', { bubbles: true, composed: true, cancelable: true });
        this.dispatchEvent(evt);
        if (evt.defaultPrevented) return;
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { pageName: 'applications' }
        });
    }

    handleViewRequest() {
        if (!this.submitResult || !this.submitResult.requestId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.submitResult.requestId,
                objectApiName: 'App_Cancellation_Request__c',
                actionName: 'view'
            }
        });
    }

    reduceError(e) {
        if (!e) return 'Unknown error';
        if (typeof e === 'string') return e;
        if (e.body) {
            if (typeof e.body.message === 'string') return e.body.message;
            if (e.body.fieldErrors) {
                return Object.values(e.body.fieldErrors).flat().map(x => x.message).join(', ');
            }
        }
        return e.message || JSON.stringify(e);
    }

    formatCurrency(v) {
        if (v == null) return '$0.00';
        return new Intl.NumberFormat('en-CA', { style: 'currency', currency: 'CAD' }).format(v);
    }

    formatCompact(v) {
        if (v == null) return '$0';
        const n = Number(v);
        if (isNaN(n)) return '$0';
        const isWhole = Math.abs(n - Math.round(n)) < 0.005;
        return new Intl.NumberFormat('en-CA', {
            style: 'currency',
            currency: 'CAD',
            minimumFractionDigits: isWhole ? 0 : 2,
            maximumFractionDigits: isWhole ? 0 : 2
        }).format(n);
    }
}