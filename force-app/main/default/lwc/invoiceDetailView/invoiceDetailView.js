import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getInvoiceDetail from '@salesforce/apex/InvoiceDetailViewController.getInvoiceDetail';
import downloadInvoicePDF from '@salesforce/apex/InvoiceDetailViewController.downloadInvoicePDF';
import createRemittanceForInvoice from '@salesforce/apex/InvoiceDetailViewController.createRemittanceForInvoice';
import submitCancellationRequest from '@salesforce/apex/InvoiceDetailViewController.submitCancellationRequest';

export default class InvoiceDetailView extends NavigationMixin(LightningElement) {
    @api recordId;

    @track isLoading = false;
    @track invoiceData = null;
    @track error = null;
    @track showPayModal = false;
    @track isPayLoading = false;
    @track showCancelModal = false;
    @track isCancelLoading = false;
    @track cancelContext = null;
    @track cancelReason = '';

    connectedCallback() {
        if (this.recordId) {
            this.loadData();
        }
    }

    async loadData() {
        this.isLoading = true;
        this.error = null;
        this.invoiceData = null;
        try {
            const raw = await getInvoiceDetail({ invoiceId: this.recordId });
            this.invoiceData = this.transform(raw);
        } catch (err) {
            this.error = this.extractError(err);
        } finally {
            this.isLoading = false;
        }
    }

    get canPay() {
        if (!this.invoiceData) return false;
        const status = this.invoiceData.invoiceStatus;
        return status !== 'Paid' && status !== 'Cancelled';
    }

    get hasApplication() {
        return this.invoiceData && this.invoiceData.applicationRecordId;
    }

    handleBackToApplication() {
        if (!this.invoiceData?.applicationRecordId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.invoiceData.applicationRecordId,
                actionName: 'view'
            }
        });
    }

    handlePayNow() {
        this.showPayModal = true;
    }

    handleClosePayModal() {
        this.showPayModal = false;
    }

    handleModalBoxClick(event) {
        event.stopPropagation();
    }

    async handleConfirmPay() {
        this.isPayLoading = true;
        try {
            const result = await createRemittanceForInvoice({ invoiceId: this.recordId });
            this.showPayModal = false;
            if (result && result.success) {
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId:   result.remittanceFormId,
                        actionName: 'view'
                    }
                });
            } else {
                this.dispatchEvent(new ShowToastEvent({
                    title:   'Error',
                    message: result?.message || 'Failed to create remittance form.',
                    variant: 'error'
                }));
            }
        } catch (err) {
            this.showPayModal = false;
            this.dispatchEvent(new ShowToastEvent({
                title:   'Error',
                message: this.extractError(err),
                variant: 'error'
            }));
        } finally {
            this.isPayLoading = false;
        }
    }

    get canCancelInvoice() {
        if (!this.invoiceData) return false;
        return this.invoiceData.invoiceStatus !== 'Cancelled';
    }

    get cancelSubmitDisabled() {
        return this.isCancelLoading || !this.cancelReason || !this.cancelReason.trim();
    }

    handleCancelInvoice() {
        this.cancelContext = {
            type:          'invoice',
            lineItemId:    null,
            displayTitle:  'Cancel Invoice',
            displayName:   'Invoice # ' + this.invoiceData.invoiceName,
            currentStatus: this.invoiceData.invoiceStatus,
            statusClass:   this.invoiceData.statusClass
        };
        this.cancelReason = '';
        this.showCancelModal = true;
    }

    handleCancelLineItem(event) {
        event.stopPropagation();
        const lineItemId  = event.currentTarget.dataset.lineitemid;
        const packageName = event.currentTarget.dataset.packagename;
        const status      = event.currentTarget.dataset.status;
        this.cancelContext = {
            type:          'lineItem',
            lineItemId:    lineItemId,
            displayTitle:  'Cancel Line Item',
            displayName:   packageName,
            currentStatus: status,
            statusClass:   'line-item-status ' + this.statusClass(status)
        };
        this.cancelReason = '';
        this.showCancelModal = true;
    }

    handleCancelReasonChange(event) {
        this.cancelReason = event.target.value;
    }

    handleCloseCancelModal() {
        this.showCancelModal = false;
        this.cancelContext = null;
        this.cancelReason = '';
    }

    async handleConfirmCancellation() {
        this.isCancelLoading = true;
        try {
            const result = await submitCancellationRequest({
                invoiceId:  this.recordId,
                lineItemId: this.cancelContext.lineItemId,
                reason:     this.cancelReason
            });
            this.showCancelModal = false;
            this.cancelContext = null;
            this.cancelReason = '';
            if (result && result.success) {
                this.dispatchEvent(new ShowToastEvent({
                    title:   'Cancellation Requested',
                    message: 'Your cancellation request has been submitted for review.',
                    variant: 'success'
                }));
                await this.loadData();
            } else {
                this.dispatchEvent(new ShowToastEvent({
                    title:   'Error',
                    message: result?.message || 'Failed to submit cancellation request.',
                    variant: 'error'
                }));
            }
        } catch (err) {
            this.showCancelModal = false;
            this.dispatchEvent(new ShowToastEvent({
                title:   'Error',
                message: this.extractError(err),
                variant: 'error'
            }));
        } finally {
            this.isCancelLoading = false;
        }
    }

    handleApplicationClick() {
        if (!this.invoiceData?.applicationRecordId) return;
        this[NavigationMixin.GenerateUrl]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.invoiceData.applicationRecordId,
                actionName: 'view'
            }
        }).then(url => {
            window.open(url, '_blank');
        });
    }

    async handleDownloadPDF() {
        this.isLoading = true;
        try {
            const result = await downloadInvoicePDF({ invoiceId: this.recordId });
            if (result && result.pdfData) {
                const bytes = atob(result.pdfData);
                const arr = new Uint8Array(bytes.length);
                for (let i = 0; i < bytes.length; i++) arr[i] = bytes.charCodeAt(i);
                const blob = new Blob([arr], { type: 'application/pdf' });
                const link = document.createElement('a');
                link.href = URL.createObjectURL(blob);
                link.download = result.fileName || 'Invoice.pdf';
                link.click();
            } else {
                this.dispatchEvent(new ShowToastEvent({
                    title:   'Download Failed',
                    message: result?.message || 'Failed to generate PDF.',
                    variant: 'error'
                }));
            }
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title:   'Download Failed',
                message: this.extractError(err),
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }

    extractError(err) {
        if (!err) return 'An unknown error occurred.';

        // AuraHandledException / Apex error
        if (err.body) {
            if (typeof err.body.message === 'string' && err.body.message) {
                return err.body.message;
            }
            if (Array.isArray(err.body.pageErrors) && err.body.pageErrors.length > 0) {
                return err.body.pageErrors.map(e => e.message).join(' ');
            }
            if (err.body.fieldErrors) {
                const msgs = Object.values(err.body.fieldErrors)
                    .flat()
                    .map(e => e.message)
                    .filter(Boolean);
                if (msgs.length > 0) return msgs.join(' ');
            }
            if (typeof err.body === 'string') return err.body;
        }

        if (typeof err.message === 'string' && err.message) return err.message;
        return 'An unexpected error occurred. Please try again.';
    }

    transform(raw) {
        return {
            invoiceName:         raw.invoiceName,
            invoiceDate:         raw.invoiceDate,
            invoiceStatus:       raw.invoiceStatus,
            statusClass:         'invoice-status ' + this.statusClass(raw.invoiceStatus),
            hasRemittanceForm:   raw.hasRemittanceForm === true,
            dealerName:          raw.dealerName,
            billTo:              raw.billTo,
            applicationId:       raw.applicationId,
            applicationRecordId: raw.applicationRecordId,
            customerFullName: raw.customerFullName,
            customerAddress:  raw.customerAddress,
            vehicleInfo:      raw.vehicleInfo,
            vin:              raw.vin,
            formattedOdometer: raw.odometer != null
                ? parseFloat(raw.odometer).toFixed(2) + ' ' + (raw.odometerUnit || 'KM')
                : null,
            packages:     this.transformPackages(raw.packages || []),
            hasPackages:  (raw.packages || []).length > 0,
            packageCount: raw.packageCount || 0,
            formattedTotal: this.formatCurrency(raw.totalAmount)
        };
    }

    transformPackages(packages) {
        return packages.map(pkg => ({
            packageId:    pkg.packageId,
            recordTypeName: pkg.recordTypeName,
            packageName:  pkg.packageName,
            packageTerm:  pkg.packageTerm,
            startDate:    pkg.startDate,
            expiryDate:   pkg.expiryDate,
            formattedStartOdometer: pkg.startOdometer != null
                ? this.formatNumber(pkg.startOdometer) + ' KM'
                : null,
            formattedExpiryOdometer: pkg.expiryOdometer != null
                ? this.formatNumber(pkg.expiryOdometer) + ' KM'
                : null,
            // Price breakdown
            hasBreakdown: pkg.hasBreakdown === true,
            formattedBaseCostPrice: this.formatCurrency(pkg.baseCostPrice),
            formattedAddOnsTotal: this.formatCurrency(pkg.addOnsTotal),
            additionalOptions: (pkg.additionalOptions || []).map(opt => ({
                optionId:          opt.optionId,
                optionName:        opt.optionName || 'Additional Option',
                formattedCostPrice: this.formatCurrency(opt.costPrice),
                selectionType:     opt.selectionType
            })),
            // Tax breakdown
            hasTax: pkg.hasTax === true,
            formattedBasePriceWithoutTax: this.formatCurrency(pkg.basePriceWithoutTax),
            taxPercentageDisplay: pkg.taxPercentage != null ? parseFloat(pkg.taxPercentage).toFixed(2) : '0.00',
            formattedTaxAmount: this.formatCurrency(pkg.taxAmount),
            formattedTotalWithTax: this.formatCurrency((pkg.basePriceWithoutTax || 0) + (pkg.taxAmount || 0)),
            lineItems: (pkg.lineItems || []).map(li => ({
                lineItemId:      li.lineItemId,
                packageName:     pkg.packageName,
                status:          li.status,
                statusClass:     'line-item-status ' + this.statusClass(li.status),
                formattedAmount: this.formatCurrency(li.amount),
                canCancel:       li.status !== 'Cancelled'
            }))
        }));
    }

    statusClass(status) {
        if (status === 'Paid')          return 'status-paid';
        if (status === 'Partial Paid')  return 'status-partial';
        if (status === 'Due')           return 'status-due';
        if (status === 'Planned')       return 'status-planned';
        if (status === 'Cancelled')      return 'status-canceled';
        return 'status-default';
    }

    formatCurrency(value) {
        if (value == null) return '$0.00';
        return '$' + parseFloat(value).toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    formatNumber(value) {
        if (value == null) return '';
        return Math.round(parseFloat(value)).toLocaleString('en-CA');
    }

    get hasContent() {
        return !this.isLoading && (this.invoiceData != null || this.error != null);
    }
}