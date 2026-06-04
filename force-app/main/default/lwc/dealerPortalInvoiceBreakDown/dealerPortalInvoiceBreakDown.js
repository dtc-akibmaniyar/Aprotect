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

const MONTH_NAMES = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];

export default class DealerPortalInvoiceBreakDown extends NavigationMixin(LightningElement) {
    @api recordId;
    @track isLoading = true;
    @track invoiceData = null;
    @track error = null;

    // Add Invoice modal state
    @track showAddInvoiceModal = false;
    @track availableInvoices = [];
    @track isLoadingAvailable = false;

    // Expand/collapse state
    @track expandedRows = {};

    _dataLoaded = false;
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
        if (message.remittanceFormId !== this.recordId) return;
        this.loadInvoiceData();
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

    // ─── Date Formatting ──────────────────────────────────────────────

    _formatRemittanceDate(dateVal) {
        if (!dateVal) return '';
        const d = new Date(dateVal);
        const month = MONTH_NAMES[d.getMonth()];
        const day = d.getDate();
        const year = d.getFullYear();
        return `${month} ${day < 10 ? '0' + day : day}, ${year}`;
    }

    _formatDateGenerated(datetimeVal) {
        if (!datetimeVal) return '';
        const d = new Date(datetimeVal);
        const dd = String(d.getDate()).padStart(2, '0');
        const mm = String(d.getMonth() + 1).padStart(2, '0');
        const yyyy = d.getFullYear();
        return `${dd}-${mm}-${yyyy}`;
    }

    // ─── Transform ────────────────────────────────────────────────────

    transformInvoiceData(result) {
        const hasPayments = result.hasPayments === true;
        const hasCheckPendingVerification = result.hasCheckPendingVerification === true;
        const invoiceCount = (result.invoices || []).length;

        const tableRows = (result.invoices || []).map((invoice, idx) => {
            // Compute subtotal for this invoice
            const subtotal = (invoice.lineItems || []).reduce((sum, li) => {
                return sum + (li.costPriceWithTax || 0);
            }, 0);

            // Build package list for expanded view
            const packages = (invoice.lineItems || []).map((li, liIdx) => {
                const addOns = (li.additionalOptions || []).map((opt, oi) => ({
                    key: 'opt-' + oi,
                    optionName: opt.optionName || 'Add-On',
                    formattedCostPrice: this._fmt(opt.costPrice || 0)
                }));

                return {
                    key: 'pkg-' + liIdx,
                    packageName: li.packageRecordType || li.packageTierName || li.name || 'Package',
                    packageRecordType: li.packageRecordType || '',
                    packageTierName: li.packageTierName || '',
                    duration: li.duration || '',
                    hasDuration: !!li.duration,
                    hasAddOns: addOns.length > 0,
                    addOns,
                    formattedDealerPrice: this._fmt(li.dealerPrice || li.baseCostPrice || 0),
                    formattedSubtotalWithTax: this._fmt(li.subtotalWithTax || li.costPriceWithTax || 0)
                };
            });

            // Vehicle info for expanded view
            const vYear = invoice.vehicleYearApp || '';
            const vMake = invoice.vehicleMakeApp || '';
            const vModel = invoice.vehicleModelApp || '';
            const vehicleFullName = [vYear, vMake, vModel].filter(Boolean).join(' ');
            const vinDisplay = invoice.vehicleVINApp || invoice.vin || '';
            const odometerDisplay = invoice.odometer
                ? `${Number(invoice.odometer).toLocaleString()} ${invoice.odometerUnit || 'KM'}`
                : '';
            const deliveryDate = invoice.vehicleDeliveryDate
                ? this._formatDateGenerated(invoice.vehicleDeliveryDate)
                : '';

            return {
                id: invoice.id,
                applicationId: invoice.applicationId || '',
                invoiceName: invoice.invoiceName || invoice.applicationNumber,
                applicationNumber: invoice.applicationNumber || '',
                rowIndex: invoice.rowIndex || (idx + 1),
                customerName: invoice.customerName || '',
                customerFirstName: invoice.customerFirstName || '',
                customerLastName: invoice.customerLastName || '',
                customerAddress: invoice.customerAddress || '',
                customerPhone: invoice.customerPhone || '',
                vehicleInfo: invoice.vehicleInfo || '',
                vehicleFullName,
                vinDisplay,
                odometerDisplay,
                hasOdometer: !!odometerDisplay,
                deliveryDate,
                hasDeliveryDate: !!deliveryDate,
                vin: invoice.vin || '',
                formattedSubTotal: this._fmt(subtotal),
                canRemove: !hasPayments && !hasCheckPendingVerification && invoiceCount > 1,
                isExpanded: !!this.expandedRows[invoice.id],
                chevronIcon: this.expandedRows[invoice.id] ? '▽' : '▷',
                packages
            };
        });

        return {
            remittanceFormName: result.remittanceFormName,
            payerName: result.payerName,
            receiverName: result.receiverName,
            dealerName: result.dealerName,
            status: result.status,
            cancellationReason: result.cancellationReason,
            billTo: result.billTo,
            creditNote: result.creditNote,
            creditIssuedBy: result.creditIssuedBy,
            discountAmount: result.discountAmount,
            formattedDiscountAmount: this._fmt(result.discountAmount || 0),
            remittanceFormTotalAfterDiscount: result.remittanceFormTotalAfterDiscount,
            formattedRemittanceFormTotalAfterDiscount: this._fmt(result.remittanceFormTotalAfterDiscount || 0),
            balance: result.balance,
            formattedBalance: this._fmt(result.balance || 0),
            paidAmount: result.paidAmount,
            formattedPaidAmount: this._fmt(result.paidAmount || 0),
            isCancelled: result.status === 'Canceled' || result.status === 'canceled' || result.status === 'Cancelled',
            statusBadgeClass: this._remittanceStatusClass(result.status),
            isAllocationRemittance: result.isAllocationRemittance === true,
            selectedServiceLabels: result.selectedServiceLabels || '',
            hasPayments,
            canModifyInvoices: !hasPayments && !hasCheckPendingVerification,
            hasCheckPendingVerification,
            tableRows,
            invoiceCount: tableRows.length,
            grandTotal: this._fmt(
                (result.invoices || []).reduce((sum, inv) => {
                    return sum + (inv.lineItems || []).reduce((s, li) => s + (li.costPriceWithTax || 0), 0);
                }, 0)
            ),
            // Remittance date & date generated
            formattedRemittanceDate: this._formatRemittanceDate(result.remittanceDate),
            hasRemittanceDate: !!result.remittanceDate,
            formattedDateGenerated: this._formatDateGenerated(result.dateGenerated),
            hasDateGenerated: !!result.dateGenerated,
            // Credit
            totalCredit: result.totalCredit || 0,
            appliedCredit: result.appliedCredit || 0,
            availableCredit: result.availableCredit || 0,
            formattedTotalCredit: this._fmt(result.totalCredit || 0),
            formattedAppliedCredit: this._fmt(result.appliedCredit || 0),
            formattedAvailableCredit: this._fmt(result.availableCredit || 0),
            hasAvailableCredit: (result.totalCredit || 0) > 0
        };
    }

    _remittanceStatusClass(status) {
        const map = {
            'Open': 'rf-badge rf-badge--open',
            'Completed': 'rf-badge rf-badge--completed',
            'Partially Completed': 'rf-badge rf-badge--partial',
            'Cancelled': 'rf-badge rf-badge--cancelled',
            'Canceled': 'rf-badge rf-badge--cancelled',
            'Expired': 'rf-badge rf-badge--expired',
            'Paid': 'rf-badge rf-badge--completed',
            'Partial Paid': 'rf-badge rf-badge--partial',
            'Due': 'rf-badge rf-badge--due'
        };
        return map[status] || 'rf-badge rf-badge--default';
    }

    _fmt(value) {
        return '$' + (parseFloat(value) || 0).toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    // ─── Expand/Collapse ──────────────────────────────────────────────

    handleToggleRow(event) {
        const invoiceId = event.currentTarget.dataset.id;
        if (!invoiceId) return;
        this.expandedRows = {
            ...this.expandedRows,
            [invoiceId]: !this.expandedRows[invoiceId]
        };
        // Re-transform to update isExpanded/chevron
        if (this.invoiceData && this.invoiceData.tableRows) {
            this.invoiceData = {
                ...this.invoiceData,
                tableRows: this.invoiceData.tableRows.map(row => ({
                    ...row,
                    isExpanded: !!this.expandedRows[row.id],
                    chevronIcon: this.expandedRows[row.id] ? '▽' : '▷'
                }))
            };
        }
    }

    // ─── Navigation ───────────────────────────────────────────────────

    handleApplicationClick(event) {
        event.preventDefault();
        event.stopPropagation();
        const applicationId = event.currentTarget.dataset.id;
        if (!applicationId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: applicationId,
                objectApiName: 'Application__c',
                actionName: 'view'
            }
        });
    }

    handleInvoiceClick(event) {
        event.preventDefault();
        event.stopPropagation();
        const invoiceId = event.currentTarget.dataset.id;
        if (!invoiceId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: invoiceId,
                objectApiName: 'Invoice__c',
                actionName: 'view'
            }
        });
    }

    // ─── Remove Invoice ───────────────────────────────────────────────

    async handleRemoveInvoice(event) {
        event.stopPropagation();
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