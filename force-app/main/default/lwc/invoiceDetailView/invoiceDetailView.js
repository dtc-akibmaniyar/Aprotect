import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import APROTECT_LOGO from '@salesforce/resourceUrl/AProtectLogo';
import THANKYOU_BANNER from '@salesforce/resourceUrl/ThankYouBanner';
import getInvoiceDetail from '@salesforce/apex/InvoiceDetailViewController.getInvoiceDetail';
import downloadInvoicePDF from '@salesforce/apex/InvoiceDetailViewController.downloadInvoicePDF';
import createRemittanceForInvoice from '@salesforce/apex/InvoiceDetailViewController.createRemittanceForInvoice';
import submitCancellationRequest from '@salesforce/apex/InvoiceDetailViewController.submitCancellationRequest';
import getUnpaidApplications from '@salesforce/apex/DealerActionBoardController.getUnpaidApplications';
import createRemittanceForm from '@salesforce/apex/DealerPortalRemittanceHandler.createRemittanceForm';

export default class InvoiceDetailView extends NavigationMixin(LightningElement) {
    @api recordId;

    get aprotectLogoUrl() { return APROTECT_LOGO; }
    get thankYouBannerUrl() { return THANKYOU_BANNER; }

    @track isLoading = false;
    @track invoiceData = null;
    @track error = null;
    @track showPayModal = false;
    @track isPayLoading = false;
    @track showCancelModal = false;
    @track isCancelLoading = false;
    @track cancelContext = null;
    @track cancelReason = '';
    @track showMakePaymentModal = false;
    @track unpaidApplications = [];
    @track isLoadingApplications = false;

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

    /** True when a Payment__c exists on the invoice's Remittance Form */
    get hasPaymentInitiated() {
        return this.invoiceData && this.invoiceData.hasPaymentInitiated === true;
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
        if (!this.canPay) return;
        this.handleOpenMakePaymentModal();
    }

    async handleOpenMakePaymentModal() {
        this.showMakePaymentModal = true;
        this.unpaidApplications = [];
        this.isLoadingApplications = true;
        try {
            const apps = await getUnpaidApplications();
            this.unpaidApplications = apps || [];
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error loading applications',
                message: this.extractError(err),
                variant: 'error'
            }));
        } finally {
            this.isLoadingApplications = false;
        }
    }

    handleCloseMakePaymentModal() {
        this.showMakePaymentModal = false;
        this.unpaidApplications = [];
    }

    async handleCreateRemittanceFromModal(event) {
        const { applicationIds } = event.detail;
        try {
            const result = await createRemittanceForm({ applicationIds });
            if (result.success && result.remittanceFormId) {
                this.handleCloseMakePaymentModal();
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: result.remittanceFormId,
                        objectApiName: 'Remittance_Form__c',
                        actionName: 'view'
                    }
                });
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Success',
                    message: 'Remittance form created successfully',
                    variant: 'success'
                }));
            } else {
                throw new Error(result.message || 'Failed to create remittance form');
            }
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: this.extractError(err),
                variant: 'error'
            }));
        }
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
        if (this.hasPaymentInitiated) return false;
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
        const subTotal = raw.subTotal != null ? raw.subTotal : null;
        const taxTotal = raw.taxTotal != null ? raw.taxTotal : null;
        // Derive blended tax rate display (e.g. "13" for HST ON 13%)
        const blendedTaxRate = (subTotal && taxTotal && subTotal > 0)
            ? parseFloat((taxTotal / subTotal * 100).toFixed(2))
            : null;
        return {
            invoiceName:         raw.invoiceName,
            invoiceDate:         raw.invoiceDate,
            dueDate:             raw.dueDate || null,
            invoiceStatus:       raw.invoiceStatus,
            statusClass:         this.statusClass(raw.invoiceStatus),
            hasRemittanceForm:   raw.hasRemittanceForm === true,
            hasPaymentInitiated: raw.hasPaymentInitiated === true,
            dealerName:          raw.dealerName,
            billTo:              raw.billTo,
            applicationId:       raw.applicationId,
            applicationRecordId: raw.applicationRecordId,
            customerFullName: raw.customerFullName,
            customerAddress:  raw.customerAddress,
            vehicleInfo:      raw.vehicleInfo,
            vin:              raw.vin,
            formattedOdometer: raw.odometer != null
                ? parseFloat(raw.odometer).toLocaleString('en-CA') + ' ' + (raw.odometerUnit || 'KM')
                : null,
            packages:        this.transformPackages(raw.packages || [], raw.hasPaymentInitiated === true),
            hasPackages:     (raw.packages || []).length > 0,
            packageCount:    raw.packageCount || 0,
            formattedTotal:   this.formatCurrency(raw.totalAmount),
            formattedBalance: this.formatCurrency(raw.balanceAmount != null ? raw.balanceAmount : raw.totalAmount),
            formattedSubTotal: subTotal != null ? this.formatCurrency(subTotal) : null,
            formattedTaxTotal: taxTotal != null ? this.formatCurrency(taxTotal) : null,
            blendedTaxRate:    blendedTaxRate != null ? blendedTaxRate : ''
        };
    }

    transformPackages(packages, paymentInitiated) {
        return packages.map(pkg => {
            // Premium Model Fee from Apex
            const premiumModelFee = pkg.premiumModelFee || 0;
            const hasPremiumModelFee = pkg.hasPremiumModelFee === true;

            // Base price without tax from Apex (Contract_Cost_Price_Without_Tax__c)
            // This formula field now INCLUDES the premium model fee,
            // so we subtract it for the display "Base Price" line
            const basePriceWithoutTax = pkg.basePriceWithoutTax || 0;
            const displayBasePrice = basePriceWithoutTax - premiumModelFee;

            // Line total = base price + add-ons + premium fee (excluding tax)
            const baseWithAddons = (pkg.baseCostPrice || 0) + (pkg.addOnsTotal || 0) + (hasPremiumModelFee ? premiumModelFee : 0);
            return {
                packageId:    pkg.packageId,
                recordTypeName: pkg.recordTypeName,
                packageName:  pkg.packageName,
                packageTerm: (pkg.packageTerm || '').replace(/\bnull\b/g, '0'),
                coverageLabel: pkg.coverageLabel || null,
                startDate:    pkg.startDate,
                expiryDate:   pkg.expiryDate,
                categoryRowKey: pkg.packageId + '-cat',
                premiumRowKey: pkg.packageId + '-premium',
                formattedLineTotal: this.formatCurrency(baseWithAddons),
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
                // Premium Model Fee
                hasPremiumModelFee: hasPremiumModelFee,
                formattedPremiumModelFee: this.formatCurrency(premiumModelFee),
                // Tax breakdown — tax is computed on (base + premium fee)
                hasTax: pkg.hasTax === true,
                formattedBasePriceWithoutTax: this.formatCurrency(displayBasePrice),
                taxPercentageDisplay: pkg.taxPercentage != null ? parseFloat(pkg.taxPercentage).toFixed(2) : '0.00',
                formattedTaxAmount: this.formatCurrency(basePriceWithoutTax * (pkg.taxPercentage ? parseFloat(pkg.taxPercentage) / 100 : 0)),
                formattedTotalWithTax: this.formatCurrency(basePriceWithoutTax + (basePriceWithoutTax * (pkg.taxPercentage ? parseFloat(pkg.taxPercentage) / 100 : 0))),
                lineItems: (pkg.lineItems || []).map(li => ({
                    lineItemId:      li.lineItemId,
                    packageName:     pkg.packageName,
                    status:          li.status,
                    statusClass:     'line-item-status ' + this.statusClass(li.status),
                    formattedAmount: this.formatCurrency(li.amount),
                    canCancel:       li.status !== 'Cancelled' && !paymentInitiated
                }))
            };
        });
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