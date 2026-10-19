import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPreviewContext from '@salesforce/apex/WorkOrderPDFService.getPreviewContext';
import savePdf from '@salesforce/apex/WorkOrderPDFService.savePdf';
import saveAndSendPdf from '@salesforce/apex/WorkOrderPDFService.saveAndSendPdf';

/**
 * Work order PDF preview (TASK-050, requirement 3).
 *
 * Osama, 2026-10-08: "Purpose of this button when user clicks it is shows PDF.
 * then a two buttons. Save pdf, save and send pdf and then cancel button. This
 * LWC that preview PDF should show customer email on top of the LWC."
 *
 * The recipients sit at the TOP, above the document, and are editable. That is
 * deliberate beyond following the instruction: this document goes out to a
 * customer and a repair shop, so the agent should see exactly who it is
 * addressed to before pressing send, not discover it afterwards. Apex refuses
 * an empty recipient list rather than sending to nobody.
 *
 * The document itself is the Visualforce page rendered as PDF, shown in an
 * iframe. Previewing it does NOT save anything: nothing is written until Save
 * PDF or Save and Send PDF is pressed, so an agent can open this to look and
 * back out with Cancel leaving no trace.
 */
export default class WorkOrderPdfPreview extends LightningElement {
    /** Populated by the quick action on the Work Order record page. */
    @api recordId;

    /** Set by a parent that already knows the work order, e.g. the claim tab. */
    @api
    get workOrderId() {
        return this._workOrderId || this.recordId;
    }
    set workOrderId(value) {
        this._workOrderId = value;
        if (value) {
            this.load();
        }
    }
    _workOrderId;

    ctx = {};
    customerEmail = '';
    repairShopEmail = '';
    pdfUrl;
    isLoading = true;
    isWorking = false;
    error;

    connectedCallback() {
        if (this.workOrderId && !this.pdfUrl && !this.error) {
            this.load();
        }
    }

    async load() {
        this.isLoading = true;
        this.error = undefined;
        try {
            const c = await getPreviewContext({ workOrderId: this.workOrderId });
            this.ctx = c || {};
            this.customerEmail = this.ctx.customerEmail || '';
            this.repairShopEmail = this.ctx.repairShopEmail || '';
            this.pdfUrl = this.ctx.pdfUrl;
        } catch (e) {
            this.error = this.messageFrom(e);
        } finally {
            this.isLoading = false;
        }
    }

    // ───────────────────────────── recipients ─────────────────────────────

    handleCustomerEmail(event) {
        this.customerEmail = event.detail.value;
    }

    handleShopEmail(event) {
        this.repairShopEmail = event.detail.value;
    }

    get recipients() {
        return [this.customerEmail, this.repairShopEmail]
            .map((e) => (e || '').trim())
            .filter((e) => e.length > 0);
    }

    get hasNoRecipients() {
        return this.recipients.length === 0;
    }

    get isBusy() {
        return this.isLoading || this.isWorking;
    }

    get cannotSend() {
        return this.isBusy || this.hasNoRecipients;
    }

    get hasDocument() {
        return !!this.pdfUrl && !this.error;
    }

    get headerLabel() {
        const parts = [];
        if (this.ctx.workOrderName) parts.push(this.ctx.workOrderName);
        if (this.ctx.claimName) parts.push(this.ctx.claimName);
        return parts.join(' · ');
    }

    get missingShopEmailNote() {
        return this.ctx.repairShopName && !this.ctx.repairShopEmail
            ? `No email on file for ${this.ctx.repairShopName}. Add one here to send it a copy.`
            : '';
    }

    // ───────────────────────────── actions ─────────────────────────────

    async handleSave() {
        this.isWorking = true;
        try {
            const r = await savePdf({ workOrderId: this.workOrderId });
            this.toast('Work Order PDF Saved', `${r.fileName} is now on the work order.`, 'success');
            this.close({ saved: true, contentVersionId: r.contentVersionId });
        } catch (e) {
            this.toast('Could Not Save The PDF', this.messageFrom(e), 'error', 'sticky');
        } finally {
            this.isWorking = false;
        }
    }

    async handleSaveAndSend() {
        this.isWorking = true;
        try {
            const r = await saveAndSendPdf({
                workOrderId: this.workOrderId,
                recipients: this.recipients
            });
            this.toast('Work Order PDF Sent',
                `${r.fileName} saved and sent to ${(r.sentTo || []).join(', ')}.`, 'success');
            this.close({ saved: true, sent: true, contentVersionId: r.contentVersionId });
        } catch (e) {
            // Apex saves before it sends, so a send failure still leaves the
            // document on the record. Its message says so explicitly.
            this.toast('Could Not Send The PDF', this.messageFrom(e), 'error', 'sticky');
        } finally {
            this.isWorking = false;
        }
    }

    handleCancel() {
        this.close({ saved: false });
    }

    // ───────────────────────────── helpers ─────────────────────────────

    close(detail) {
        this.dispatchEvent(new CustomEvent('close', { detail }));
    }

    toast(title, message, variant, mode) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant,
            mode: mode || 'dismissable'
        }));
    }

    messageFrom(error) {
        return (
            error?.body?.message ||
            error?.body?.pageErrors?.[0]?.message ||
            error?.message ||
            'Unexpected error.'
        );
    }
}