import { LightningElement, api, wire, track } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getInvoiceBreakdown from '@salesforce/apex/DealerPortalInvoiceBreakdownHandler.getInvoiceBreakdown';
import downloadRemittanceFormPDF from '@salesforce/apex/DealerPortalRemittanceHandler.downloadRemittanceFormPDF';

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

    _dataLoaded = false;

    @wire(CurrentPageReference)
    handlePageReference(pageRef) {
        if (!pageRef || this._dataLoaded) return;
        // Never override @api recordId — it is the authoritative source.
        // The CurrentPageReference wire can transiently fire with the *previous*
        // page's recordId (e.g. the invoice record) while navigating away or
        // returning via browser back, which would cause a "not found" error.
        // We only fall back to pageRef when @api recordId was not provided at all.
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

    // ─── Transform ────────────────────────────────────────────────────────────

    transformInvoiceData(result) {
        const colTotals = { warranty: 0, tireRim: 0, loanProtection: 0 };
        const colCounts = { warranty: 0, tireRim: 0, loanProtection: 0 };

        const tableRows = (result.invoices || []).map((invoice, idx) => {
            const cols = this._mapServiceCols(invoice.lineItems || []);

            ['warranty', 'tireRim', 'loanProtection'].forEach(k => {
                if (cols[k]) {
                    colTotals[k] += cols[k].costPriceWithoutTax || 0;
                    colCounts[k]++;
                }
            });

            // Sub-total = sum of prices WITH tax across all service line items for this row
            const subtotal = (cols.warranty?.costPriceWithTax || 0)
                           + (cols.tireRim?.costPriceWithTax || 0)
                           + (cols.loanProtection?.costPriceWithTax || 0);

            return {
                id:              invoice.id,
                invoiceName:     invoice.invoiceName || invoice.applicationNumber,
                rowIndex:        idx + 1,
                customerName:    invoice.customerName || '',
                vehicleInfo:     invoice.vehicleInfo  || '',
                vin:             invoice.vin           || '',
                invoiceStatus:   invoice.status        || '',
                invoiceStatusClass: this._statusClass(invoice.status || ''),
                warranty:        cols.warranty       ? this._colCell(cols.warranty)       : null,
                tireRim:         cols.tireRim        ? this._colCell(cols.tireRim)        : null,
                loanProtection:  cols.loanProtection ? this._colCell(cols.loanProtection) : null,
                formattedSubTotal: this._fmt(subtotal)
            };
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
            // Table-specific
            tableRows,
            invoiceCount:           tableRows.length,
            warrantyColTotal:       this._fmt(colTotals.warranty),
            tireRimColTotal:        this._fmt(colTotals.tireRim),
            loanProtectionColTotal: this._fmt(colTotals.loanProtection),
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

    // Assign each line item to a service column key (first match wins)
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
        return {
            amount:          item.costPriceWithoutTax || 0,
            formattedAmount: this._fmt(item.costPriceWithoutTax || 0),
            status,
            statusClass:     this._statusClass(status),
            hasStatus:       !!status
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

    // ─── Navigation ───────────────────────────────────────────────────────────

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

    // ─── PDF Download ─────────────────────────────────────────────────────────

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