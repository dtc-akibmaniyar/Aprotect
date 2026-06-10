import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import processPayment from '@salesforce/apex/DealerPortalMonerisIntegrationServices.processPayment';
import processChequePayment from '@salesforce/apex/DealerPortalMonerisIntegrationServices.processChequePayment';
import processETransferPayment from '@salesforce/apex/DealerPortalMonerisIntegrationServices.processETransferPayment';
import processDealerCreditPayment from '@salesforce/apex/DealerPortalMonerisIntegrationServices.processDealerCreditPayment';
import getDealerAvailableCredit from '@salesforce/apex/DealerPortalMonerisIntegrationServices.getDealerAvailableCredit';
import getInvoiceBreakdown from '@salesforce/apex/DealerPortalInvoiceBreakdownHandler.getInvoiceBreakdown';
import { updateRecord, getRecord, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import { publish, MessageContext } from 'lightning/messageService';
import PAYMENT_STATUS_CHANNEL from '@salesforce/messageChannel/PaymentStatusChange__c';
import STATUS_FIELD from '@salesforce/schema/Remittance_Form__c.Status__c';
import AMOUNT_FIELD from '@salesforce/schema/Remittance_Form__c.Balance__c';
import CHEQUE_PAYMENT from '@salesforce/resourceUrl/ChequePayment';
import ETRANSFER_PAYMENT from '@salesforce/resourceUrl/ETransfer';
import CARDS_ICONS from '@salesforce/resourceUrl/Cards_Icons';

import { getObjectInfo, getPicklistValues } from "lightning/uiObjectInfoApi";
import PAYMENT_OBJECT from "@salesforce/schema/Payment__c";
import CHEQUE_DELIVERY_FIELD from "@salesforce/schema/Payment__c.Cheque_Delivery_Mthod__c";

export default class DealerPortalCreatePayment extends NavigationMixin(LightningElement) {
    @api recordId;
    @api amount;

    staticResources = {
        chequePayment: CHEQUE_PAYMENT,
        eTransfer: ETRANSFER_PAYMENT,
        cardsIcons: CARDS_ICONS
    };

    @wire(MessageContext)
    messageContext;

    @track isGenerating = false;
    @track showPaymentModal = false;
    @track cardData = null;
    @track showCancellationModal = false;
    @track isCancelling = false;
    @track remittanceFormStatus = null;
    @track cancellationReason = '';
    @track remittanceFormAmount = null;
    @track paymentAmount = null;
    @track amountError = '';
    @track showChequeModal = false;
    @track chequeDeliveryMethod = '';
    @track chequeNumber = '';
    @track chequeDate = '';
    @track chequeAmount = '';
    @track chequeAmountError = '';
    @track chequeNotes = '';
    @track deliveryMethodOptions = [];
    @track showETransferModal = false;
    @track eTransferReferenceNumber = '';
    @track eTransferDate = '';
    @track eTransferAmount = '';
    @track eTransferAmountError = '';
    @track eTransferNotes = '';
    @track eTransferSenderEmail = '';
    
    // Invoice Selection Modal
    @track showInvoiceSelectionModal = false;
    @track invoiceData = null;
    @track remittanceFormName = null;
    @track selectedInvoices = [];
    @track isLoadingInvoices = false;
    @track invoiceLoadError = null;
    @track selectedPaymentMethod = null;

    // Dealer Credit Modal
    @track showDealerCreditModal = false;
    @track dealerAvailableCredit = 0;
    @track dealerCreditAmount = 0;
    @track dealerCreditNotes = '';
    @track isProcessingDealerCredit = false;

    @track monerisObjectInfo;
    @track picklistError;

    // Fetch dealer credit imperatively (not cached) to always get fresh data
    async fetchDealerCredit() {
        try {
            const credit = await getDealerAvailableCredit({ recordId: this.recordId });
            this.dealerAvailableCredit = credit !== undefined ? credit : 0;
        } catch (error) {
            console.error('Error fetching dealer credit:', error);
            this.dealerAvailableCredit = 0;
        }
    }

    connectedCallback() {
        this.fetchDealerCredit();
    }

    @wire(getObjectInfo, { objectApiName: PAYMENT_OBJECT })
    wiredMonerisObjectInfo({ error, data }) {
        debugger;
        if (data) {
            this.monerisObjectInfo = data;
            this.picklistError = undefined;
        } else if (error) {
            this.picklistError = error;
            this.monerisObjectInfo = undefined;
        }
        console.log('Moneris Object Info:', this.monerisObjectInfo);
        console.log('Picklist Error:', this.picklistError);
    }

    @wire(getPicklistValues, { recordTypeId: '$monerisObjectInfo.defaultRecordTypeId', fieldApiName: CHEQUE_DELIVERY_FIELD })
    wiredDeliveryMethodPicklist({ error, data }) {
        if (data) {
            this.deliveryMethodOptions = data.values.map(item => ({
                label: item.label,
                value: item.label
            }));
            this.picklistError = undefined;
        } else if (error) {
            this.picklistError = error;
            this.deliveryMethodOptions = undefined;
        }
    }

    @wire(getRecord, { recordId: '$recordId', fields: [STATUS_FIELD, AMOUNT_FIELD] })
    wiredRemittanceForm({ data, error }) {
        if (data) {
            this.remittanceFormStatus = data.fields.Status__c.value;
            this.remittanceFormAmount = data.fields.Balance__c.value;
            this.paymentAmount = this.remittanceFormAmount;
        } else if (error) {
            console.error('Error fetching remittance form status:', error);
        }
    }

    get isCancelButtonDisabled() {
        return this.remittanceFormStatus !== 'Open';
    }

    get isPaymentDisabled() {
        return this.remittanceFormStatus === 'Completed' || this.remittanceFormStatus === 'Cancelled' || this.remittanceFormStatus === 'Expired';
    }

    // Dealer Credit getters
    get formattedDealerCredit() {
        const credit = this.dealerAvailableCredit || 0;
        return '$' + parseFloat(credit).toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    get isDealerCreditInsufficient() {
        return (this.dealerAvailableCredit || 0) < (this.dealerCreditAmount || 0);
    }

    get formattedRemainingCredit() {
        const remaining = (this.dealerAvailableCredit || 0) - (this.dealerCreditAmount || 0);
        return '$' + Math.max(0, remaining).toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    get isDealerCreditSubmitDisabled() {
        return this.isDealerCreditInsufficient || this.isProcessingDealerCredit || !this.dealerCreditAmount || this.dealerCreditAmount <= 0 || this.dealerCreditAmount > this.remittanceFormAmount;
    }

    get formattedDealerCreditAmount() {
        const amount = this.dealerCreditAmount || 0;
        return '$' + parseFloat(amount).toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    get dealerCreditAmountMaxError() {
        return `Amount cannot exceed $${(this.remittanceFormAmount || 0).toFixed(2)}`;
    }

    handlePaymentMethodSelected(event) {
        // Prevent payment when remittance form is already paid
        if (this.isPaymentDisabled) {
            return;
        }
        
        const paymentMethod = event.detail.method;
        this.selectedPaymentMethod = paymentMethod;
        
        // Load invoices and show selection modal
        this.loadInvoicesForSelection();
    }

    async loadInvoicesForSelection() {
        this.isLoadingInvoices = true;
        this.invoiceLoadError = null;
        
        try {
            const result = await getInvoiceBreakdown({ remittanceFormId: this.recordId });
            
            if (result && result.invoices) {
                this.invoiceData = this.transformInvoiceData(result);
                this.remittanceFormName = result.remittanceFormName || 'Remittance Form';
                // Select all invoices by default
                this.selectedInvoices = this.invoiceData.invoices.map(invoice => invoice.id);
                this.showInvoiceSelectionModal = true;
            } else {
                this.invoiceLoadError = 'No invoice data available';
                this.showToast('Error', this.invoiceLoadError, 'error');
            }
        } catch (error) {
            console.error('Error loading invoices:', error);
            this.invoiceLoadError = error.body?.message || 'Error loading invoices';
            this.showToast('Error', this.invoiceLoadError, 'error');
        } finally {
            this.isLoadingInvoices = false;
        }
    }

    transformInvoiceData(result) {
        let grandTotal = 0;
        let grandTaxTotal = 0;
        let grandSubTotal = 0;

        // Include invoices that are fully Due/Overdue, or Partial Paid (remaining line items still owed)
        const invoices = result.invoices.filter(invoice =>
            invoice.status === 'Due' || invoice.status === 'Overdue' || invoice.status === 'Partial Paid'
        );
        
        // Sort: Overdue first, then Due
        invoices.sort((a, b) => {
            if (a.status === 'Overdue' && b.status !== 'Overdue') return -1;
            if (a.status !== 'Overdue' && b.status === 'Overdue') return 1;
            return 0;
        });

        const transformedInvoices = invoices.map(invoice => {
            const lineItems = (invoice.lineItems || []).map(item => {
                const costWithoutTax = item.costPriceWithoutTax || 0;
                return {
                    id: item.id,
                    name: item.name,
                    amount: costWithoutTax,
                    formattedAmount: '$' + parseFloat(costWithoutTax).toFixed(2)
                };
            });

            // Calculate totals for this invoice
            let invoiceSubTotal = 0;
            let invoiceTaxTotal = 0;
            let invoiceTaxPercentage = 0;

            lineItems.forEach((item, idx) => {
                invoiceSubTotal += item.amount;
                if (idx === 0) {
                    const firstLineItem = invoice.lineItems[0];
                    if (firstLineItem) {
                        invoiceTaxPercentage = firstLineItem.taxPercentage || 0;
                    }
                }
                const lineItemTax = invoice.lineItems[idx]?.taxAmount || 0;
                invoiceTaxTotal += lineItemTax;
            });

            const invoiceTotal = invoiceSubTotal + invoiceTaxTotal;

            grandSubTotal += invoiceSubTotal;
            grandTaxTotal += invoiceTaxTotal;
            grandTotal += invoiceTotal;

            return {
                id: invoice.id,
                applicationNumber: invoice.applicationNumber,
                customerName: invoice.customerName,
                vehicleInfo: invoice.vehicleInfo,
                vin: invoice.vin,
                lineItems: lineItems,
                subTotal: invoiceSubTotal,
                formattedSubTotal: '$' + invoiceSubTotal.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ','),
                applicationTaxAmount: invoiceTaxTotal,
                formattedApplicationTaxAmount: '$' + invoiceTaxTotal.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ','),
                applicationTaxPercentage: invoiceTaxPercentage,
                totalDue: invoiceTotal,
                formattedTotalDue: '$' + invoiceTotal.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',')
            };
        });

        return {
            invoices: transformedInvoices,
            grandTotal: grandTotal,
            formattedGrandTotal: '$' + grandTotal.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',')
        };
    }

    handleSelectAll(event) {
        const isChecked = event.currentTarget.checked;
        
        if (isChecked) {
            // Select all invoices
            this.selectedInvoices = this.invoiceData.invoices.map(invoice => invoice.id);
        } else {
            // Deselect all invoices
            this.selectedInvoices = [];
        }
    }

    handleInvoiceCheckboxChange(event) {
        const invoiceId = event.currentTarget.dataset.invoiceId;
        const isChecked = event.currentTarget.checked;

        if (isChecked) {
            // Add invoice if not already selected
            if (!this.selectedInvoices.includes(invoiceId)) {
                this.selectedInvoices = [...this.selectedInvoices, invoiceId];
            }
        } else {
            // Remove invoice from selection
            this.selectedInvoices = this.selectedInvoices.filter(id => id !== invoiceId);
        }
    }

    isInvoiceSelected(invoiceId) {
        return this.selectedInvoices.includes(invoiceId);
    }

    handleCloseInvoiceSelectionModal() {
        this.showInvoiceSelectionModal = false;
        this.invoiceData = null;
        this.remittanceFormName = null;
        this.selectedInvoices = [];
        this.invoiceLoadError = null;
        this.selectedPaymentMethod = null;
    }

    handleNextPaymentMethod() {
        if (this.selectedInvoices.length === 0) {
            this.showToast('Error', 'Please select at least one invoice to proceed', 'error');
            return;
        }

        // Close invoice selection modal
        this.showInvoiceSelectionModal = false;

        // Open the appropriate payment modal based on selected payment method
        switch(this.selectedPaymentMethod) {
            case 'creditCard':
                this.paymentAmount = this.remittanceFormAmount;
                this.showPaymentModal = true;
                break;
            case 'cheque':
                this.chequeAmount = this.remittanceFormAmount;
                this.showChequeModal = true;
                break;
            case 'eTransfer':
                this.eTransferAmount = this.remittanceFormAmount;
                this.showETransferModal = true;
                break;
            case 'dealerCredit':
                this.dealerCreditAmount = this.remittanceFormAmount;
                this.showDealerCreditModal = true;
                break;
        }
    }

    get selectedInvoicesData() {
        if (!this.invoiceData || !this.invoiceData.invoices) {
            return [];
        }
        return this.invoiceData.invoices.filter(invoice => 
            this.selectedInvoices.includes(invoice.id)
        );
    }

    get allInvoicesWithSelection() {
        if (!this.invoiceData || !this.invoiceData.invoices) {
            return [];
        }
        return this.invoiceData.invoices.map(invoice => ({
            ...invoice,
            isSelected: this.selectedInvoices.includes(invoice.id)
        }));
    }

    get isAllSelected() {
        if (!this.invoiceData || this.invoiceData.invoices.length === 0) {
            return false;
        }
        return this.selectedInvoices.length === this.invoiceData.invoices.length;
    }

    get selectedInvoicesTotalFormatted() {
        const selectedData = this.selectedInvoicesData;
        if (selectedData.length === 0) {
            return '$0.00';
        }
        
        let total = 0;
        selectedData.forEach(invoice => {
            total += invoice.totalDue;
        });
        
        return '$' + total.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    // Helper method to get selected invoices total as numeric value
    get selectedInvoicesTotalAmount() {
        const selectedData = this.selectedInvoicesData;
        if (selectedData.length === 0) {
            return 0;
        }
        
        let total = 0;
        selectedData.forEach(invoice => {
            total += invoice.totalDue;
        });

        return Math.round(total * 100) / 100;
    }

    get paymentAmountMaxError() {
        return `Payment amount cannot exceed the balance of ${this.remittanceFormAmount?.toFixed(2)}`;
    }

    // Disable remove button when only one invoice remains


    handleClosePaymentModal() {
        this.showPaymentModal = false;
    }

    handleBackFromPaymentModal() {
        this.showPaymentModal = false;
        this.showInvoiceSelectionModal = true;
    }

    handleCloseChequeModal() {
        this.showChequeModal = false;
        this.resetChequeForm();
    }

    handleBackFromChequeModal() {
        this.showChequeModal = false;
        this.resetChequeForm();
        this.showInvoiceSelectionModal = true;
    }

    resetChequeForm() {
        this.chequeDeliveryMethod = '';
        this.chequeNumber = '';
        this.chequeDate = '';
        this.chequeAmount = '';
        this.chequeAmountError = '';
        this.chequeNotes = '';
    }

    handleChequeDeliveryMethodChange(event) {
        this.chequeDeliveryMethod = event.target.value;
    }

    handleChequeNumberChange(event) {
        this.chequeNumber = event.target.value;
    }

    handleChequeDateChange(event) {
        this.chequeDate = event.target.value;
    }

    handleChequeAmountChange(event) {
        const inputValue = parseFloat(event.target.value);
        this.chequeAmount = inputValue;
        
        // Validate the amount
        this.chequeAmountError = '';
        if (isNaN(inputValue) || inputValue <= 0) {
            this.chequeAmountError = 'Please enter a valid cheque amount';
        } else if (this.selectedInvoicesTotalAmount && inputValue > this.selectedInvoicesTotalAmount) {
            this.chequeAmountError = `Payment amount cannot exceed $${this.selectedInvoicesTotalAmount.toFixed(2)}`;
        }
    }

    handleChequeNotesChange(event) {
        this.chequeNotes = event.target.value;
    }

    handleSubmitCheque() {
        // Validate required fields
        if (!this.chequeDeliveryMethod) {
            this.showToast('Error', 'Please select a delivery method', 'error');
            return;
        }
        if (!this.chequeNumber) {
            this.showToast('Error', 'Please enter a cheque number', 'error');
            return;
        }
        if (!this.chequeDate) {
            this.showToast('Error', 'Please enter a cheque date', 'error');
            return;
        }
        if (!this.chequeAmount || this.chequeAmount <= 0) {
            this.showToast('Error', 'Please enter a valid cheque amount', 'error');
            return;
        }

        // Call Apex method to save cheque payment details
        this.saveChequePayment();
    }

    async saveChequePayment() {
        // Prevent cheque payment when remittance form is already paid
        if (this.isPaymentDisabled) {
            return;
        }

        try {
            const result = await processChequePayment({
                recordId: this.recordId,
                chequeDate: this.chequeDate,
                chequeDeliveryMethod: this.chequeDeliveryMethod,
                chequeNumber: this.chequeNumber,
                chequeAmount: this.remittanceFormAmount,
                notes: this.chequeNotes
            });

            if (result && result.success) {
                // Immediately update local balance (DLRS rollup is async)
                this.remittanceFormAmount = Math.max(0, (this.remittanceFormAmount || 0) - (this.chequeAmount || 0));
                this.paymentAmount = this.remittanceFormAmount;
                this.showToast('Success', 'Cheque details submitted successfully', 'success');
                // Navigate to success page if fully paid
                this.navigateToSuccessPageIfFullyPaid();
                this.dispatchEvent(new CustomEvent('chequesubmitted', {
                    detail: {
                        method: 'cheque',
                        deliveryMethod: this.chequeDeliveryMethod,
                        chequeNumber: this.chequeNumber,
                        date: this.chequeDate,
                        amount: parseFloat(this.chequeAmount),
                        notes: this.chequeNotes,
                        transactionId: result.transactionId
                    }
                }));
                this.showChequeModal = false;
                this.resetChequeForm();
                // Notify sibling components via LMS
                this.publishPaymentUpdate('cheque');
                // Single delayed refresh for DLRS rollup + flow updates
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => { notifyRecordUpdateAvailable([{ recordId: this.recordId }]); }, 4000);
            } else {
                this.showToast('Error', result?.errorMessage || 'Failed to save cheque details', 'error');
            }
        } catch (error) {
            console.error('Cheque payment error:', error);
            this.showToast('Error', error.body?.message || 'An error occurred while saving cheque details', 'error');
        }
    }

    handleCloseETransferModal() {
        this.showETransferModal = false;
        this.resetETransferForm();
    }

    handleBackFromETransferModal() {
        this.showETransferModal = false;
        this.resetETransferForm();
        this.showInvoiceSelectionModal = true;
    }

    resetETransferForm() {
        this.eTransferReferenceNumber = '';
        this.eTransferDate = '';
        this.eTransferAmount = '';
        this.eTransferAmountError = '';
        this.eTransferNotes = '';
        this.eTransferSenderEmail = '';
    }

    handleETransferReferenceNumberChange(event) {
        this.eTransferReferenceNumber = event.target.value;
    }

    handleETransferDateChange(event) {
        this.eTransferDate = event.target.value;
    }

    handleETransferAmountChange(event) {
        const inputValue = parseFloat(event.target.value);
        this.eTransferAmount = inputValue;
        
        // Validate the amount
        this.eTransferAmountError = '';
        if (isNaN(inputValue) || inputValue <= 0) {
            this.eTransferAmountError = 'Please enter a valid transaction amount';
        } else if (this.selectedInvoicesTotalAmount && inputValue > this.selectedInvoicesTotalAmount) {
            this.eTransferAmountError = `Payment amount cannot exceed $${this.selectedInvoicesTotalAmount.toFixed(2)}`;
        }
    }

    handleETransferNotesChange(event) {
        this.eTransferNotes = event.target.value;
    }

    handleETransferSenderEmailChange(event) {
        this.eTransferSenderEmail = event.target.value;
    }

    handleSubmitETransfer() {
        // Validate required fields
        if (!this.eTransferReferenceNumber) {
            this.showToast('Error', 'Please enter a transaction reference number', 'error');
            return;
        }
        if (!this.eTransferDate) {
            this.showToast('Error', 'Please enter a transaction date', 'error');
            return;
        }
        if (!this.eTransferAmount || this.eTransferAmount <= 0) {
            this.showToast('Error', 'Please enter a valid transaction amount', 'error');
            return;
        }
        if (!this.eTransferSenderEmail) {
            this.showToast('Error', 'Please enter sender email', 'error');
            return;
        }

        // Call Apex method to save E-Transfer payment details
        this.saveETransferPayment();
    }

    async saveETransferPayment() {
        // Prevent E-Transfer payment when remittance form is already paid
        if (this.isPaymentDisabled) {
            return;
        }

        try {
            const result = await processETransferPayment({
                recordId: this.recordId,
                transactionReferenceNumber: this.eTransferReferenceNumber,
                transactionDate: this.eTransferDate,
                transactionAmount: this.remittanceFormAmount,
                notes: this.eTransferNotes,
                senderEmail: this.eTransferSenderEmail
            });

            if (result && result.success) {
                // Immediately update local balance (DLRS rollup is async)
                this.remittanceFormAmount = Math.max(0, (this.remittanceFormAmount || 0) - (this.eTransferAmount || 0));
                this.paymentAmount = this.remittanceFormAmount;
                this.showToast('Success', 'E-Transfer details submitted successfully', 'success');
                // Navigate to success page if fully paid
                this.navigateToSuccessPageIfFullyPaid();
                this.dispatchEvent(new CustomEvent('etransfersubmitted', {
                    detail: {
                        method: 'eTransfer',
                        referenceNumber: this.eTransferReferenceNumber,
                        date: this.eTransferDate,
                        amount: parseFloat(this.eTransferAmount),
                        notes: this.eTransferNotes,
                        senderEmail: this.eTransferSenderEmail,
                        transactionId: result.transactionId
                    }
                }));
                this.showETransferModal = false;
                this.resetETransferForm();
                // Notify sibling components via LMS
                this.publishPaymentUpdate('eTransfer');
                // Single delayed refresh for DLRS rollup + flow updates
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => { notifyRecordUpdateAvailable([{ recordId: this.recordId }]); }, 4000);
            } else {
                this.showToast('Error', result?.errorMessage || 'Failed to save E-Transfer details', 'error');
            }
        } catch (error) {
            console.error('E-Transfer payment error:', error);
            this.showToast('Error', error.body?.message || 'An error occurred while saving E-Transfer details', 'error');
        }
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Dealer Credit Payment Handlers
    // ─────────────────────────────────────────────────────────────────────────────

    handleCloseDealerCreditModal() {
        this.showDealerCreditModal = false;
        this.dealerCreditNotes = '';
        this.dealerCreditAmount = 0;
    }

    handleBackFromDealerCreditModal() {
        this.showDealerCreditModal = false;
        this.dealerCreditNotes = '';
        this.dealerCreditAmount = 0;
        this.showInvoiceSelectionModal = true;
    }

    handleDealerCreditAmountChange(event) {
        const inputValue = parseFloat(event.target.value);
        if (!isNaN(inputValue)) {
            this.dealerCreditAmount = inputValue;
        }
    }

    handleDealerCreditNotesChange(event) {
        this.dealerCreditNotes = event.target.value;
    }

    handleSubmitDealerCredit() {
        // Validate amount entered
        if (!this.dealerCreditAmount || this.dealerCreditAmount <= 0) {
            this.showToast('Error', 'Please enter a valid credit amount', 'error');
            return;
        }

        // Validate amount doesn't exceed balance
        if (this.dealerCreditAmount > this.remittanceFormAmount) {
            this.showToast('Error', `Credit amount cannot exceed the balance of $${this.remittanceFormAmount.toFixed(2)}`, 'error');
            return;
        }

        // Validate sufficient credit
        if (this.isDealerCreditInsufficient) {
            this.showToast('Error', 'Insufficient dealer credit to complete this payment', 'error');
            return;
        }

        // Call Apex method to process dealer credit payment
        this.saveDealerCreditPayment();
    }

    async saveDealerCreditPayment() {
        // Prevent payment when remittance form is already paid
        if (this.isPaymentDisabled) {
            return;
        }

        if (this.isProcessingDealerCredit) {
            return;
        }

        this.isProcessingDealerCredit = true;

        try {
            const result = await processDealerCreditPayment({
                recordId: this.recordId,
                paymentAmount: this.dealerCreditAmount,
                notes: this.dealerCreditNotes
            });

            if (result && result.success) {
                // Immediately update local balance (DLRS rollup is async)
                this.remittanceFormAmount = Math.max(0, (this.remittanceFormAmount || 0) - (this.dealerCreditAmount || 0));
                this.paymentAmount = this.remittanceFormAmount;
                this.showToast('Success', 'Dealer credit applied successfully', 'success');
                // Navigate to success page if fully paid
                this.navigateToSuccessPageIfFullyPaid();
                this.dispatchEvent(new CustomEvent('dealercreditapplied', {
                    detail: {
                        method: 'dealerCredit',
                        amount: this.dealerCreditAmount,
                        notes: this.dealerCreditNotes,
                        transactionId: result.transactionId,
                        remainingCredit: result.remainingCredit
                    }
                }));
                this.showDealerCreditModal = false;
                this.dealerCreditNotes = '';
                // Notify sibling components via LMS
                this.publishPaymentUpdate('dealerCredit');
                // Single delayed refresh for DLRS rollup + flow updates
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => {
                    notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
                    this.fetchDealerCredit();
                }, 4000);
            } else {
                this.showToast('Error', result?.errorMessage || 'Failed to apply dealer credit', 'error');
            }
        } catch (error) {
            console.error('Dealer credit payment error:', error);
            this.showToast('Error', error.body?.message || 'An error occurred while applying dealer credit', 'error');
        } finally {
            this.isProcessingDealerCredit = false;
        }
    }

    handleCardComplete(event) {
        console.log('Card complete event received:', event.detail);
        this.cardData = event.detail.value;
    }

    handlePaymentAmountChange(event) {
        const inputValue = parseFloat(event.target.value);
        this.paymentAmount = inputValue;
        
        // Validate the amount
        this.amountError = '';
        if (inputValue <= 0) {
            this.amountError = 'Please enter a valid payment amount';
        } else if (this.remittanceFormAmount && inputValue > this.remittanceFormAmount) {
            this.amountError = `Payment amount cannot exceed $${this.remittanceFormAmount.toFixed(2)}`;
        }
    }

    async handleProcessPayment() {
        // Prevent payment when remittance form is already paid
        if (this.isPaymentDisabled) {
            return;
        }

        if (this.isGenerating) {
            return;
        }

        // Validate payment amount
        if (!this.paymentAmount || this.paymentAmount <= 0) {
            this.showToast('Error', 'Please enter a valid payment amount', 'error');
            return;
        }

        if (this.paymentAmount > this.remittanceFormAmount) {
            this.showToast('Error', `Payment amount cannot exceed $${this.remittanceFormAmount.toFixed(2)}`, 'error');
            return;
        }

        // Check if card data is available
        if (!this.cardData) {
            this.showToast('Error', 'Please enter valid card information', 'error');
            return;
        }

        this.isGenerating = true;

        try {
            const result = await processPayment({
                recordId: this.recordId,
                cardNumber: this.cardData.cardNumber,
                expiryMonth: this.parseExpiryMonth(this.cardData.cardExpiry),
                expiryYear: this.parseExpiryYear(this.cardData.cardExpiry),
                cvv: this.cardData.cardCVV,
                paymentAmount: this.paymentAmount,
                cardHolderName: this.cardData.cardHolderName
            });

            if (result && result.success) {
                // Immediately update local balance (DLRS rollup is async)
                this.remittanceFormAmount = Math.max(0, (this.remittanceFormAmount || 0) - (this.paymentAmount || 0));
                this.paymentAmount = this.remittanceFormAmount;
                this.showToast('Success', 'Payment processed successfully', 'success');
                this.dispatchEvent(new CustomEvent('paymentprocessed', { detail: result }));
                this.showPaymentModal = false;
                this.cardData = null;
                // Notify sibling components via LMS
                this.publishPaymentUpdate('creditCard');
                // Single delayed refresh for DLRS rollup + flow updates
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => { notifyRecordUpdateAvailable([{ recordId: this.recordId }]); }, 4000);
                // Navigate to success page if fully paid
                this.navigateToSuccessPageIfFullyPaid();
            } else {
                this.showToast('Error', result?.errorMessage || 'Payment processing failed', 'error');
            }
        } catch (error) {
            console.error('Payment processing error:', error);
            this.showToast('Error', error.body?.message || 'An error occurred while processing the payment', 'error');
        } finally {
            this.isGenerating = false;
        }
    }

    handleCancelRemittanceForm() {
        this.showCancellationModal = true;
    }

    handleCloseCancellationModal() {
        this.showCancellationModal = false;
        this.cancellationReason = '';
    }

    handleCancellationReasonChange(event) {
        this.cancellationReason = event.target.value;
    }

    async handleConfirmCancellation() {
        if (this.isCancelling) {
            return;
        }

        this.isCancelling = true;

        try {
            // Prepare the record to update
            const fields = {};
            fields.Id = this.recordId;
            fields.Status__c = 'Canceled';
            fields.Cancelation_Reason__c = this.cancellationReason || '';
            
            const recordInput = { fields };
            
            // Update the record using uiRecordApi
            await updateRecord(recordInput);

            this.showToast('Success', 'Remittance form cancelled successfully', 'success');
            this.showCancellationModal = false;
            this.cancellationReason = '';
            // Dispatch an event to notify parent components that the form was cancelled
            this.dispatchEvent(new CustomEvent('formcancelled'));
        } catch (error) {
            console.error('Cancellation error:', error);
            this.showToast('Error', error.body?.message || 'An error occurred while cancelling the remittance form', 'error');
        } finally {
            this.isCancelling = false;
        }
    }

    parseExpiryMonth(expiryString) {
        // expiryString format is "MM/YYYY" - accepts 4-digit year
        if (expiryString && expiryString.includes('/')) {
            return parseInt(expiryString.split('/')[0], 10);
        }
        return null;
    }

    parseExpiryYear(expiryString) {
        // expiryString format is "MM/YYYY" - extracts 4-digit year
        if (expiryString && expiryString.includes('/')) {
            return parseInt(expiryString.split('/')[1], 10);
        }
        return null;
    }

    publishPaymentUpdate(paymentMethod) {
        publish(this.messageContext, PAYMENT_STATUS_CHANNEL, {
            remittanceFormId: this.recordId,
            action: 'PAYMENT_COMPLETED',
            paymentMethod: paymentMethod,
            timestamp: Date.now()
        });
    }

    showToast(title, message, variant) {
        const toastEvent = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(toastEvent);
    }

    /**
     * Navigate to the Payment Success page when the entire remittance balance is paid off.
     * Uses a small delay to allow the toast to display before navigation.
     */
    navigateToSuccessPageIfFullyPaid() {
        // Balance is 0 or effectively 0 (handle floating point)
        if (this.remittanceFormAmount != null && this.remittanceFormAmount <= 0.005) {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                // Navigate to the custom Experience Cloud page
                // The page must be created in Experience Builder at /payment-success
                this[NavigationMixin.Navigate]({
                    type: 'standard__webPage',
                    attributes: {
                        url: '/dealerportal/s/payment-success?remittanceFormId=' + this.recordId
                    }
                });
            }, 1500);
        }
    }
}