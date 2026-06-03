import { LightningElement, api, wire, track } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import PAYMENT_STATUS_CHANNEL from '@salesforce/messageChannel/PaymentStatusChange__c';
import getInvoiceBreakdown from '@salesforce/apex/DealerPortalInvoiceBreakdownHandler.getInvoiceBreakdown';
import downloadRemittanceFormPDF from '@salesforce/apex/DealerPortalRemittanceHandler.downloadRemittanceFormPDF';
import removeInvoiceFromRemittance from '@salesforce/apex/DealerPortalInvoiceBreakdownHandler.removeInvoiceFromRemittance';
import getAvailableInvoicesForRemittance from '@salesforce/apex/DealerPortalInvoiceBreakdownHandler.getAvailableInvoicesForRemittance';
import addInvoiceToRemittance from '@salesforce/apex/DealerPortalInvoiceBreakdownHandler.addInvoiceToRemittance';

// Maps a line-item name to one of three service column keys
const SERVICE_COLS = [
    { key: 'warranty',       keywords: ['warranty', 'extended limited'] },
    { key: 'tireRim',        keywords: ['tire', 'rim'] },
    { key: 'loanProtection', keywords: ['loan protection', 'gap', 'total loss', 'loan'] }
];

export default class DealerPortalInvoiceBreakDown extends NavigationMixin(LightningElement) {
    @api recordId;
    @track isLoading = true;
    @track invoiceData = null;
    @track error = null;

    // Add Invoice modal state
    @track showAddInvoiceModal = false;
    @track availableInvoices = [];
    @track isLoadingAvailable = false;

    _dataLoaded = false;

    // LMS subscription
    _subscription = null;
    _pollTimers = [];

    @wire(MessageContext)
    messageContext;

    @wire(CurrentPageReference)
    handlePageReference(pageRef) {
        if (!pageRef || this._dataLoaded) return;
        if (!this.recordId) {
            this.recordId = pageRef.attributes?.recordId;
        }
        if (this.recordId) {
            this._dataLoaded = true;
            this.loadInvoiceData();
        }
    }

    connectedCallback() {
        if (this.recordId && !this._dataLoaded) {
            this._dataLoaded = true;
            this.loadInvoiceData();
        }
        // Subscribe to payment status changes
        this._subscription = subscribe(
            this.messageContext,
            PAYMENT_STATUS_CHANNEL,
            (message) => this.handlePaymentMessage(message)
        );
    }

    disconnectedCallback() {
        if (this._subscription) {
            unsubscribe(this._subscription);
            this._subscription = null;
        }
        this._pollTimers.forEach(t => clearTimeout(t));
        this._pollTimers = [];
    }

    handlePaymentMessage(message) {
        // Only react to messages for our remittance form
        if (message.remittanceFormId !== this.recordId) return;

        // Immediate refresh
        this.loadInvoiceData();

        // Delayed polls to catch flow-driven updates (invoice status, balance, junction statuses)
        this._pollTimers.forEach(t => clearTimeout(t));
        this._pollTimers = [
            setTimeout(() => this.loadInvoiceData(), 3000),
            setTimeout(() => this.loadInvoiceData(), 6000)
        ];
    }

    async loadInvoiceData() {
        this.isLoading = true;
        this.error = null;
        try {
            const result = await getInvoiceBreakdown({ remittanceFormId: this.recordId });
            if (result && result.invoices) {
                this.invoiceData = this.transformInvoiceData(result);
                this.setRichTextContent();
            } else {
                this.invoiceData = null;
            }
        } catch (error) {
            console.error('Error loading invoice data:', error);
            this.error = error.body?.message || 'Error loading invoice data';
            this.showToast('Error', this.error, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    setRichTextContent() {
        setTimeout(() => {
            const el = this.template.querySelector('[data-id="billToContent"]');
            if (el && this.invoiceData.billTo) {
                el.innerHTML = this.invoiceData.billTo;
            }
        }, 0);
    }

    // ─── Transform ────────────────────────────────────────────────────

    transformInvoiceData(result) {
        const colTotals    = { warranty: 0, tireRim: 0, loanProtection: 0 };
        const colTotalsNet = { warranty: 0, tireRim: 0, loanProtection: 0 };
        const colTotalsTax = { warranty: 0, tireRim: 0, loanProtection: 0 };
        const colCounts    = { warranty: 0, tireRim: 0, loanProtection: 0 };
        // Track tax percentages to compute weighted average
        const colTaxPctWeighted = { warranty: 0, tireRim: 0, loanProtection: 0 };

        const hasPayments = result.hasPayments === true;
        const invoiceCount = (result.invoices || []).length;

        const tableRows = (result.invoices || []).map((invoice, idx) => {
            const cols = this._mapServiceCols(invoice.lineItems || []);

            ['warranty', 'tireRim', 'loanProtection'].forEach(k => {
                if (cols[k]) {
                    colTotals[k]    += cols[k].costPriceWithTax    || 0;
                    colTotalsNet[k] += cols[k].costPriceWithoutTax || 0;
                    colTotalsTax[k] += cols[k].taxAmount           || 0;
                    colCounts[k]++;
                    colTaxPctWeighted[k] += (cols[k].taxPercentage || 0) * (cols[k].costPriceWithoutTax || 0);
                }
            });

            const subtotal = (cols.warranty?.costPriceWithTax || 0)
                           + (cols.tireRim?.costPriceWithTax || 0)
                           + (cols.loanProtection?.costPriceWithTax || 0);

            return {
                id:              invoice.id,
                invoiceName:     invoice.invoiceName || invoice.applicationNumber,
                rowIndex:        invoice.rowIndex || (idx + 1),
                customerName:    invoice.customerName || '',
                vehicleInfo:     invoice.vehicleInfo  || '',
                vin:             invoice.vin           || '',
                invoiceStatus:   invoice.status        || '',
                invoiceStatusClass: this._statusClass(invoice.status || ''),
                warranty:        cols.warranty       ? this._colCell(cols.warranty)       : null,
                tireRim:         cols.tireRim        ? this._colCell(cols.tireRim)        : null,
                loanProtection:  cols.loanProtection ? this._colCell(cols.loanProtection) : null,
                formattedSubTotal: this._fmt(subtotal),
                canRemove: !hasPayments && invoiceCount > 1
            };
        });

        // Compute average tax percentage per column (weighted by net amount)
        const colAvgTaxPct = {};
        ['warranty', 'tireRim', 'loanProtection'].forEach(k => {
            if (colTotalsNet[k] > 0) {
                colAvgTaxPct[k] = colTaxPctWeighted[k] / colTotalsNet[k];
            } else {
                colAvgTaxPct[k] = 0;
            }
        });

        return {
            remittanceFormName:                   result.remittanceFormName,
            payerName:                            result.payerName,
            receiverName:                         result.receiverName,
            dealerName:                           result.dealerName,
            status:                               result.status,
            cancellationReason:                   result.cancellationReason,
            billTo:                               result.billTo,
            creditNote:                           result.creditNote,
            creditIssuedBy:                       result.creditIssuedBy,
            discountAmount:                       result.discountAmount,
            formattedDiscountAmount:              this._fmt(result.discountAmount || 0),
            remittanceFormTotalAfterDiscount:     result.remittanceFormTotalAfterDiscount,
            formattedRemittanceFormTotalAfterDiscount: this._fmt(result.remittanceFormTotalAfterDiscount || 0),
            balance:                              result.balance,
            formattedBalance:                     this._fmt(result.balance || 0),
            paidAmount:                           result.paidAmount,
            formattedPaidAmount:                  this._fmt(result.paidAmount || 0),
            isCancelled:                          result.status === 'Canceled' || result.status === 'canceled' || result.status === 'Cancelled',
            statusBadgeClass:                     this._remittanceStatusClass(result.status),
            isAllocationRemittance:               result.isAllocationRemittance === true,
            selectedServiceLabels:                result.selectedServiceLabels || '',
            hasPayments,
            canModifyInvoices: !hasPayments,
            tableRows,
            invoiceCount:           tableRows.length,
            warrantyColTotal:       this._fmt(colTotals.warranty),
            tireRimColTotal:        this._fmt(colTotals.tireRim),
            loanProtectionColTotal: this._fmt(colTotals.loanProtection),
            // Net (excl. tax) totals
            warrantyColNet:         this._fmt(colTotalsNet.warranty),
            tireRimColNet:          this._fmt(colTotalsNet.tireRim),
            loanProtectionColNet:   this._fmt(colTotalsNet.loanProtection),
            // Tax amount totals
            warrantyColTax:         this._fmt(colTotalsTax.warranty),
            tireRimColTax:          this._fmt(colTotalsTax.tireRim),
            loanProtectionColTax:   this._fmt(colTotalsTax.loanProtection),
            // Average tax percentage per column
            warrantyTaxPct:         this._fmtPct(colAvgTaxPct.warranty),
            tireRimTaxPct:          this._fmtPct(colAvgTaxPct.tireRim),
            loanProtectionTaxPct:   this._fmtPct(colAvgTaxPct.loanProtection),
            warrantyCount:          colCounts.warranty,
            tireRimCount:           colCounts.tireRim,
            loanProtectionCount:    colCounts.loanProtection,
            hasWarrantyCol:       colCounts.warranty       > 0,
            hasTireRimCol:        colCounts.tireRim        > 0,
            hasLoanProtectionCol: colCounts.loanProtection > 0,
            grandTotal:           this._fmt(
                (result.invoices || []).reduce((sum, inv) => {
                    const cols = this._mapServiceCols(inv.lineItems || []);
                    return sum + (cols.warranty?.costPriceWithTax || 0)
                               + (cols.tireRim?.costPriceWithTax  || 0)
                               + (cols.loanProtection?.costPriceWithTax || 0);
                }, 0)
            ),
            totalCredit:               result.totalCredit     || 0,
            appliedCredit:             result.appliedCredit   || 0,
            availableCredit:           result.availableCredit || 0,
            formattedTotalCredit:      this._fmt(result.totalCredit     || 0),
            formattedAppliedCredit:    this._fmt(result.appliedCredit   || 0),
            formattedAvailableCredit:  this._fmt(result.availableCredit || 0),
            hasAvailableCredit:        (result.totalCredit || 0) > 0
        };
    }

    _mapServiceCols(lineItems) {
        const cols = { warranty: null, tireRim: null, loanProtection: null };
        lineItems.forEach(item => {
            const n = (item.name || '').toLowerCase();
            const col = SERVICE_COLS.find(c => c.keywords.some(k => n.includes(k)));
            if (col && !cols[col.key]) {
                cols[col.key] = item;
            }
        });
        return cols;
    }

    _colCell(item) {
        const status = item.status || '';
        const hasBreakdown = item.hasBreakdown === true;
        return {
            amount:          item.costPriceWithTax || 0,
            formattedAmount: this._fmt(item.costPriceWithTax || 0),
            status,
            statusClass:     this._statusClass(status),
            hasStatus:       !!status,
            // Breakdown fields
            hasBreakdown,
            formattedBaseCostPrice: this._fmt(item.baseCostPrice || 0),
            formattedAddOnsTotal:   this._fmt(item.addOnsTotal || 0),
            additionalOptions: (item.additionalOptions || []).map((opt, i) => ({
                key: 'opt-' + i,
                optionName: opt.optionName || 'Additional Option',
                formattedCostPrice: this._fmt(opt.costPrice || 0)
            }))
        };
    }

    _statusClass(status) {
        const map = {
            'Paid':         'li-badge li-badge--paid',
            'Partial Paid': 'li-badge li-badge--partial',
            'Planned':      'li-badge li-badge--planned',
            'Due':          'li-badge li-badge--due',
            'Cancelled':    'li-badge li-badge--cancelled'
        };
        return map[status] || 'li-badge li-badge--default';
    }

    _remittanceStatusClass(status) {
        const map = {
            'Open':                 'rf-badge rf-badge--open',
            'Completed':            'rf-badge rf-badge--completed',
            'Partially Completed':  'rf-badge rf-badge--partial',
            'Cancelled':            'rf-badge rf-badge--cancelled',
            'Canceled':             'rf-badge rf-badge--cancelled',
            'Expired':              'rf-badge rf-badge--expired',
            'Paid':                 'rf-badge rf-badge--completed',
            'Partial Paid':         'rf-badge rf-badge--partial',
            'Due':                  'rf-badge rf-badge--due'
        };
        return map[status] || 'rf-badge rf-badge--default';
    }

    _fmt(value) {
        return '$' + (parseFloat(value) || 0).toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    _fmtPct(value) {
        return (parseFloat(value) || 0).toFixed(2) + '%';
    }

    // ─── Navigation ───────────────────────────────────────────────────

    handleInvoiceClick(event) {
        event.preventDefault();
        const invoiceId = event.currentTarget.dataset.id;
        if (!invoiceId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId:      invoiceId,
                objectApiName: 'Invoice__c',
                actionName:    'view'
            }
        });
    }

    // ─── Remove Invoice ───────────────────────────────────────────────

    async handleRemoveInvoice(event) {
        const invoiceId = event.currentTarget.dataset.id;
        if (!invoiceId) return;
        try {
            this.isLoading = true;
            await removeInvoiceFromRemittance({
                remittanceFormId: this.recordId,
                invoiceId: invoiceId
            });
            this.showToast('Success', 'Invoice removed from remittance', 'success');
            await this.loadInvoiceData();
            // Notify LDS cache so sibling components (e.g. payment) refresh Balance__c
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Error removing invoice', 'error');
            this.isLoading = false;
        }
    }

    // ─── Add Invoice Modal ────────────────────────────────────────────

    async handleOpenAddInvoice() {
        this.showAddInvoiceModal = true;
        this.isLoadingAvailable = true;
        try {
            const invoices = await getAvailableInvoicesForRemittance({
                remittanceFormId: this.recordId
            });
            this.availableInvoices = (invoices || []).map(inv => ({
                ...inv,
                formattedAmount: this._fmt(inv.amount || 0)
            }));
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Error loading available invoices', 'error');
            this.availableInvoices = [];
        } finally {
            this.isLoadingAvailable = false;
        }
    }

    handleCloseAddInvoice() {
        this.showAddInvoiceModal = false;
        this.availableInvoices = [];
    }

    async handleSelectInvoice(event) {
        const invoiceId = event.currentTarget.dataset.id;
        if (!invoiceId) return;
        try {
            this.isLoadingAvailable = true;
            await addInvoiceToRemittance({
                remittanceFormId: this.recordId,
                invoiceId: invoiceId
            });
            this.showToast('Success', 'Invoice added to remittance', 'success');
            this.showAddInvoiceModal = false;
            this.availableInvoices = [];
            await this.loadInvoiceData();
            // Notify LDS cache so sibling components (e.g. payment) refresh Balance__c
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Error adding invoice', 'error');
            this.isLoadingAvailable = false;
        }
    }

    // ─── PDF Download ─────────────────────────────────────────────────

    async handleDownloadPDF() {
        try {
            this.isLoading = true;
            const result = await downloadRemittanceFormPDF({ remittanceFormId: this.recordId });
            if (result && result.pdfData) {
                const byteCharacters = atob(result.pdfData);
                const byteNumbers = new Array(byteCharacters.length);
                for (let i = 0; i < byteCharacters.length; i++) {
                    byteNumbers[i] = byteCharacters.charCodeAt(i);
                }
                const blob = new Blob([new Uint8Array(byteNumbers)], { type: 'application/pdf' });
                const link = document.createElement('a');
                link.href = URL.createObjectURL(blob);
                link.download = result.fileName || 'RemittanceForm.pdf';
                link.click();
                this.showToast('Success', 'PDF downloaded successfully', 'success');
            } else {
                this.showToast('Error', 'Failed to generate PDF', 'error');
            }
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Error downloading PDF', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}