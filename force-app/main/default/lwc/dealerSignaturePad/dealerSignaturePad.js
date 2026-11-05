import { LightningElement, api, track } from 'lwc';
import getStatus from '@salesforce/apex/SignaturePadController.getStatus';
import saveSignature from '@salesforce/apex/SignaturePadController.saveSignature';
import stageImage from '@salesforce/apex/SignaturePadController.stageImage';
import issuePdf from '@salesforce/apex/SignaturePadController.issuePdf';
import dropResource from '@salesforce/apex/SignaturePadController.dropResource';
import currentUserName from '@salesforce/apex/SignaturePadController.currentUserName';
import getPreview from '@salesforce/apex/SignaturePadController.getPreview';
import getSignatureRequirements from '@salesforce/apex/SignaturePadController.getSignatureRequirements';

/** The two signatures that go on EACH contract document. */
const SIG_ROLES = [
    {
        role: 'Customer',
        label: 'CUSTOMER',
        hint: 'The customer named on this contract — this signature also signs as the Contract Holder'
    },
    { role: 'DealerRep', label: 'DEALERSHIP REP.', hint: 'The salesperson signing for the dealership' }
];

/**
 * Two separate contracts, signed separately, produced as two separate PDFs.
 * `key` is the Document_Type__c value the Apex side expects.
 */
const DOCS = [
    { key: 'Warranty', label: 'Extended Warranty', shortLabel: 'WARRANTY' },
    { key: 'TireRim', label: 'Tire & Rim', shortLabel: 'TIRE & RIM' }
];

function blankDoc(label) {
    return {
        label,
        signed: false,
        disabled: true,
        activeIndex: 0,
        captured: {},
        names: {},
        idem: {},
        errorMessage: null,
        successMessage: null,
        previewUrl: null,
        previewLoading: false,
        previewError: null,
        previewBlocked: false
    };
}

export default class DealerSignaturePad extends LightningElement {
    @api applicationId;
    @api documentType = 'Warranty';
    @api customerName = '';
    @api salesPersonName = '';

    @track showPad = false;
    @track activeTab = 'Warranty';
    @track docs = { Warranty: blankDoc('Extended Warranty'), TireRim: blankDoc('Tire & Rim') };
    @track inlineError = null;
    @track isSubmitting = false;
    @track steps = [];
    @track submitLabel = 'SIGN & FINISH';
    /** Server-side gate state: which documents are required and complete. */
    @track requirements = null;

    drawing = false;
    lastX = 0;
    lastY = 0;

    // ------------------------------------------------------------- state plumbing

    patch(key, values) {
        this.docs = { ...this.docs, [key]: { ...this.docs[key], ...values } };
    }

    get active() {
        return this.docs[this.activeTab] || this.docs.Warranty;
    }

    get activeLabel() {
        return this.active.label;
    }

    get activeRole() {
        return SIG_ROLES[this.active.activeIndex] || SIG_ROLES[0];
    }

    get activeName() {
        return this.active.names[this.activeRole.role] || '';
    }

    get activeHint() {
        return this.activeRole.hint;
    }

    get activeSigned() {
        return this.active.signed === true;
    }

    get activeError() {
        return this.active.errorMessage;
    }

    get activeSuccess() {
        return this.active.successMessage;
    }

    get previewUrl() {
        return this.active.previewUrl;
    }

    get previewLoading() {
        return this.active.previewLoading === true;
    }

    get previewError() {
        return this.active.previewError;
    }

    get previewReady() {
        return !!this.active.previewUrl && this.active.previewBlocked !== true;
    }

    get tabs() {
        return DOCS.map((d) => {
            const st = this.docs[d.key];
            return {
                key: d.key,
                label: d.label,
                signed: st.signed === true,
                className:
                    'sig-tab' +
                    (d.key === this.activeTab ? ' sig-tab--active' : '') +
                    (st.signed === true ? ' sig-tab--signed' : '')
            };
        });
    }

    /** True when every contract document this application carries is signed. */
    get allDocumentsSigned() {
        const req = this.requirements;
        if (req) {
            if (req.hasRequiredDocuments === false) return true;
            return req.allComplete === true;
        }
        return false;
    }

    /** ONE button: SIGN DOCUMENTS -> REVIEW SIGNATURES once everything is signed. */
    get signatureButtonLabel() {
        return this.allDocumentsSigned ? 'REVIEW SIGNATURES' : 'SIGN DOCUMENTS';
    }

    get signatureButtonClass() {
        return this.allDocumentsSigned
            ? 'sig-btn sig-btn--ghost sig-btn--review'
            : 'sig-btn sig-btn--primary';
    }

    get signatureButtonTitle() {
        if (this.allDocumentsSigned) {
            return 'Contract documents signed — open to review or re-sign';
        }
        const missing = (this.requirements && this.requirements.missingLabels) || '';
        return missing
            ? 'Sign the ' + missing + ' before submitting'
            : 'Sign the contract documents before submitting';
    }

    get roleDefs() {
        const captured = this.active.captured || {};
        const index = this.active.activeIndex || 0;
        return SIG_ROLES.map((d, i) => ({
            role: d.role,
            label: d.label,
            index: i,
            number: i + 1,
            captured: !!captured[d.role],
            className:
                'sig-step-item' +
                (i === index ? ' sig-step-item--active' : '') +
                (captured[d.role] ? ' sig-step-item--done' : '')
        }));
    }

    get stepCountLabel() {
        return 'SIGNER ' + ((this.active.activeIndex || 0) + 1) + ' OF ' + SIG_ROLES.length;
    }

    get isLastStep() {
        return (this.active.activeIndex || 0) === SIG_ROLES.length - 1;
    }

    get hasPrev() {
        return (this.active.activeIndex || 0) > 0;
    }

    get hasInk() {
        return !!this.active.captured[this.activeRole.role];
    }

    get allCaptured() {
        const captured = this.active.captured || {};
        return SIG_ROLES.every((d) => !!captured[d.role]);
    }

    get submitDisabled() {
        return this.isSubmitting || !this.allCaptured;
    }

    get footerNote() {
        return 'Each document is signed and issued on its own — this one: ' + this.activeLabel + '.';
    }

    // ------------------------------------------------------------------ lifecycle

    connectedCallback() {
        this.activeTab = this.normaliseKey(this.documentType);
        this.refreshAll().then(() => this.syncRequirements());
        if (!this.customerName) {
            currentUserName()
                .then((n) => {
                    this.customerName = n || '';
                })
                .catch(() => {});
        }
    }

    normaliseKey(value) {
        const v = (value || '').toString().toLowerCase();
        return v.indexOf('tire') > -1 ? 'TireRim' : 'Warranty';
    }

    /** Same-origin base of the site ("/dealerportal", or "" on a root domain). */
    siteBase() {
        const path = (window.location && window.location.pathname) || '/';
        const marker = path.indexOf('/s/');
        return marker > 0 ? path.substring(0, marker) : '';
    }

    refreshAll() {
        return Promise.all(DOCS.map((d) => this.refreshStatus(d.key)));
    }

    refreshStatus(key) {
        if (!this.applicationId) {
            this.patch(key, { disabled: true });
            return Promise.resolve();
        }
        return getStatus({ applicationId: this.applicationId, documentType: key })
            .then((s) => {
                const st = s || {};
                this.patch(key, { signed: st.hasSignature === true, disabled: false });
                this.inlineError = null;
            })
            .catch((e) => {
                this.inlineError = this.msg(e);
                this.patch(key, { disabled: false });
            });
    }

    // ----------------------------------------------------------------- open / close

    /** One button: open the first document that still needs signing. */
    handleOpenPad() {
        const required = (this.requirements && this.requirements.documents) || [];
        const pending = required.filter((d) => d.required === true && d.complete !== true);
        const target = pending.length ? pending[0].documentType : null;
        this.openPad(target || this.activeTab);
    }

    openPad(key) {
        this.activeTab = DOCS.some((d) => d.key === key) ? key : 'Warranty';
        this.isSubmitting = false;
        this.steps = [];
        this.patch(this.activeTab, {
            captured: {},
            idem: {},
            activeIndex: 0,
            errorMessage: null,
            successMessage: null,
            names: {
                Customer: this.customerName || '',
                DealerRep: this.salesPersonName || ''
            }
        });
        this.showPad = true;
        setTimeout(() => this.resetCanvas(), 0);
        this.loadPreview(this.activeTab);
    }

    handleTabClick(evt) {
        if (this.isSubmitting) return;
        const key = evt.currentTarget.dataset.key;
        if (!key || key === this.activeTab) return;
        this.activeTab = key;
        setTimeout(() => this.resetCanvas(), 0);
        this.loadPreview(key);
    }

    handleCancel() {
        if (this.isSubmitting) return;
        this.showPad = false;
    }

    // -------------------------------------------------------------------- preview

    /**
     * Same-origin preview. The Apex controller hands back the Visualforce path of
     * the contract page (already renderAs="pdf"), so the iframe gets a real
     * application/pdf response from this site instead of a blob: URL, which the
     * Experience Cloud CSP blocks.
     */
    loadPreview(key) {
        const st = this.docs[key];
        if (!this.applicationId || st.previewUrl || st.previewLoading) return;
        this.patch(key, { previewLoading: true, previewError: null, previewBlocked: false });
        getPreview({ applicationId: this.applicationId, documentType: key })
            .then((r) => {
                if (!r || !r.ok || !r.url) {
                    this.patch(key, {
                        previewLoading: false,
                        previewError: (r && r.message) || 'The document preview is unavailable.'
                    });
                    return;
                }
                const url = this.siteBase() + r.url;
                this.patch(key, { previewUrl: url, previewLoading: false });
                this.verifyPreview(key, url);
            })
            .catch(() => {
                this.patch(key, {
                    previewLoading: false,
                    previewError: 'The document preview is unavailable.'
                });
            });
    }

    /**
     * Prove the route really answers with a PDF before trusting the frame. If it
     * answers with something else (for example a login page) say so inline and
     * leave OPEN IN NEW TAB as the way out. A blocked probe (CSP) is not treated
     * as a failure - the frame still gets its chance.
     */
    verifyPreview(key, url) {
        if (typeof fetch !== 'function') return;
        fetch(url, { credentials: 'same-origin', headers: { Accept: 'application/pdf' } })
            .then((res) => {
                const type = (res.headers.get('content-type') || '').toLowerCase();
                if (!res.ok || type.indexOf('pdf') === -1) {
                    this.patch(key, {
                        previewBlocked: true,
                        previewError:
                            'The preview can’t be shown inside this window. Use OPEN IN NEW TAB.'
                    });
                }
            })
            .catch(() => {
                /* probe blocked or offline: let the frame try on its own */
            });
    }

    handleOpenPreviewTab() {
        const url = this.active.previewUrl;
        if (url) {
            window.open(url, '_blank', 'noopener');
        }
    }

    // --------------------------------------------------------------------- canvas

    get canvas() {
        return this.template.querySelector('canvas.sig-canvas');
    }

    resetCanvas() {
        const c = this.canvas;
        if (!c) return;
        const ctx = c.getContext('2d');
        ctx.fillStyle = '#ffffff';
        ctx.fillRect(0, 0, c.width, c.height);
        ctx.lineWidth = 2.4;
        ctx.lineCap = 'round';
        ctx.lineJoin = 'round';
        ctx.strokeStyle = '#101828';
        const saved = this.active.captured[this.activeRole.role];
        if (saved) {
            const img = new Image();
            img.onload = () => ctx.drawImage(img, 0, 0, c.width, c.height);
            img.src = saved;
        }
    }

    point(evt) {
        const c = this.canvas;
        const r = c.getBoundingClientRect();
        return {
            x: ((evt.clientX - r.left) / r.width) * c.width,
            y: ((evt.clientY - r.top) / r.height) * c.height
        };
    }

    handlePointerDown(evt) {
        if (this.isSubmitting) return;
        const c = this.canvas;
        if (!c) return;
        evt.preventDefault();
        this.drawing = true;
        const p = this.point(evt);
        this.lastX = p.x;
        this.lastY = p.y;
        const ctx = c.getContext('2d');
        ctx.beginPath();
        ctx.moveTo(p.x, p.y);
        ctx.lineTo(p.x + 0.1, p.y + 0.1);
        ctx.stroke();
    }

    handlePointerMove(evt) {
        if (!this.drawing || this.isSubmitting) return;
        const c = this.canvas;
        if (!c) return;
        evt.preventDefault();
        const p = this.point(evt);
        const ctx = c.getContext('2d');
        ctx.beginPath();
        ctx.moveTo(this.lastX, this.lastY);
        ctx.lineTo(p.x, p.y);
        ctx.stroke();
        this.lastX = p.x;
        this.lastY = p.y;
    }

    handlePointerUp() {
        if (!this.drawing) return;
        this.drawing = false;
        const c = this.canvas;
        if (!c) return;
        const role = this.activeRole.role;
        const data = c.toDataURL('image/png');
        const captured = { ...this.active.captured, [role]: data };
        const idem = { ...this.active.idem };
        if (!idem[role]) {
            idem[role] = this.newKey(role);
        }
        this.patch(this.activeTab, { captured, idem });
    }

    handleClear() {
        const role = this.activeRole.role;
        const captured = { ...this.active.captured, [role]: null };
        const idem = { ...this.active.idem, [role]: this.newKey(role) };
        this.patch(this.activeTab, { captured, idem });
        this.resetCanvas();
    }

    handleNameChange(evt) {
        const role = this.activeRole.role;
        const names = { ...this.active.names, [role]: evt.target.value };
        this.patch(this.activeTab, { names });
    }

    selectStep(evt) {
        const i = Number(evt.currentTarget.dataset.index);
        if (Number.isNaN(i) || i === this.active.activeIndex) return;
        this.patch(this.activeTab, { activeIndex: i });
        setTimeout(() => this.resetCanvas(), 0);
    }

    handleNextStep() {
        const i = this.active.activeIndex || 0;
        if (i < SIG_ROLES.length - 1) {
            this.patch(this.activeTab, { activeIndex: i + 1 });
            setTimeout(() => this.resetCanvas(), 0);
        }
    }

    handlePrevStep() {
        const i = this.active.activeIndex || 0;
        if (i > 0) {
            this.patch(this.activeTab, { activeIndex: i - 1 });
            setTimeout(() => this.resetCanvas(), 0);
        }
    }

    handleSignAgain() {
        if (this.isSubmitting) return;
        this.patch(this.activeTab, {
            captured: {},
            idem: {},
            activeIndex: 0,
            successMessage: null,
            errorMessage: null
        });
        setTimeout(() => this.resetCanvas(), 0);
    }

    newKey(role) {
        return role + '-' + this.activeTab + '-' + this.applicationId + '-' + Date.now() + '-' +
            Math.floor(Math.random() * 1e6);
    }

    // --------------------------------------------------------------------- submit

    async handleSubmit() {
        if (this.isSubmitting || !this.allCaptured) return;
        const key = this.activeTab;
        const doc = this.active;
        this.isSubmitting = true;
        this.patch(key, { errorMessage: null, successMessage: null });
        const ids = {};

        try {
            this.steps = this.buildSteps(0);
            for (const d of SIG_ROLES) {
                const res = await saveSignature({
                    applicationId: this.applicationId,
                    pngB64: doc.captured[d.role],
                    signedBy: doc.names[d.role] || d.label,
                    idemKey: doc.idem[d.role] || this.newKey(d.role),
                    documentType: key,
                    signerRole: d.role
                });
                ids[d.role] = res.signatureId;
            }

            this.steps = this.buildSteps(1);
            for (const d of SIG_ROLES) {
                await stageImage({ signatureId: ids[d.role] });
            }

            this.steps = this.buildSteps(2);
            await issuePdf({ signatureId: ids.Customer });

            this.steps = this.buildSteps(3);
            for (const d of SIG_ROLES) {
                try {
                    await dropResource({ signatureId: ids[d.role] });
                } catch (e) {
                    /* the document is already produced; cleanup retries later */
                }
            }

            this.steps = this.buildSteps(4);
            await this.refreshStatus(key);
            // Tell the summary tab the gate state changed, so SUBMIT enables
            // without a page reload. The payload is the server's own verdict.
            await this.syncRequirements();
            this.patch(key, {
                captured: {},
                idem: {},
                activeIndex: 0,
                successMessage:
                    doc.label + ' signed. The PDF carries the customer and dealership rep signatures.'
            });
        } catch (e) {
            this.patch(key, { errorMessage: this.msg(e) });
            this.steps = [];
        } finally {
            this.isSubmitting = false;
        }
    }

    /**
     * Reads the submit gate from the server (SignatureSubmitGuard) and tells the
     * host component. Deliberately the server's own verdict rather than a local
     * guess, so the button state and the submit refusal can never disagree.
     */
    async syncRequirements() {
        if (!this.applicationId) return null;
        try {
            const req = await getSignatureRequirements({ applicationId: this.applicationId });
            this.requirements = req;
            this.dispatchEvent(new CustomEvent('signaturestatuschange', {
                detail: { requirements: req },
                bubbles: true,
                composed: true
            }));
            return req;
        } catch (e) {
            return null;
        }
    }

    buildSteps(done) {
        const labels = [
            'Capturing signatures',
            'Uploading images',
            'Producing the PDF',
            'Cleaning up',
            'Done'
        ];
        return labels.map((label, i) => ({
            key: label,
            label,
            className: 'sig-step' + (i < done ? ' sig-step--done' : i === done ? ' sig-step--active' : '')
        }));
    }

    handleKeydown(evt) {
        if (evt.key === 'Escape' && !this.isSubmitting) {
            this.showPad = false;
        }
    }

    msg(e) {
        if (!e) return 'Something went wrong.';
        return e.body ? e.body.message || String(e.body) : e.message || String(e);
    }
}