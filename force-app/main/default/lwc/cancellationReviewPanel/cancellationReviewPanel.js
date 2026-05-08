import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getRequestDetails from '@salesforce/apex/CancellationReviewController.getRequestDetails';
import approveRequest from '@salesforce/apex/CancellationReviewController.approveRequest';
import rejectRequest from '@salesforce/apex/CancellationReviewController.rejectRequest';

const COLUMNS = [
    { label: 'Package Name', fieldName: 'packageName', type: 'text' },
    { label: 'Coverage Plan', fieldName: 'coveragePlan', type: 'text' },
    { label: 'Term', fieldName: 'coverageTerm', type: 'text' },
    { label: 'Refund Amount', fieldName: 'Refund_Amount__c', type: 'currency', 
      typeAttributes: { currencyCode: 'USD' } }
];

export default class CancellationReviewPanel extends LightningElement {
    @api recordId;
    requestData;
    services = [];
    error;
    isLoading = true;
    showRejectModal = false;
    rejectionReason = '';
    columns = COLUMNS;
    _wiredResult;

    @wire(getRequestDetails, { requestId: '$recordId' })
    wiredDetails(result) {
        this._wiredResult = result;
        const { data, error } = result;
        if (data) {
            this.requestData = data.request;
            this.services = (data.services || []).map(s => ({
                ...s,
                packageName: s.Application_Package__r ? s.Application_Package__r.Name : 'N/A',
                coveragePlan: s.Application_Package__r ? s.Application_Package__r.Coverage_Plan__c : '',
                coverageTerm: s.Application_Package__r ? s.Application_Package__r.Coverage_Term__c : ''
            }));
            this.error = undefined;
            this.isLoading = false;
        } else if (error) {
            this.error = error.body ? error.body.message : 'An error occurred';
            this.requestData = undefined;
            this.isLoading = false;
        }
    }

    get hasData() { return this.requestData != null; }
    get hasServices() { return this.services && this.services.length > 0; }
    get applicationName() {
        return this.requestData && this.requestData.Application__r ? this.requestData.Application__r.Name : '';
    }
    get submittedBy() {
        if (this.requestData && this.requestData.Requested_By_Name__c) return this.requestData.Requested_By_Name__c;
        return this.requestData && this.requestData.CreatedBy ? this.requestData.CreatedBy.Name : '';
    }
    get formattedDate() {
        const d = this.requestData ? (this.requestData.Date_Requested__c || this.requestData.CreatedDate) : null;
        if (!d) return '';
        return new Date(d).toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
    }
    get formattedTotalRefund() {
        const amt = this.requestData ? this.requestData.Total_Refund_Amount__c : 0;
        return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(amt || 0);
    }
    get statusBadgeClass() {
        const s = this.requestData ? this.requestData.Status__c : '';
        if (s === 'Approved') return 'slds-badge slds-badge_inverse slds-theme_success';
        if (s === 'Rejected') return 'slds-badge slds-badge_inverse slds-theme_error';
        return 'slds-badge slds-badge_inverse slds-theme_warning';
    }
    get showSalesReviewActions() { return this.requestData && this.requestData.Status__c === 'Pending Sales Review'; }
    get showAccountingReviewActions() { return this.requestData && this.requestData.Status__c === 'Pending Accounting Review'; }
    get isTerminalStatus() {
        if (!this.requestData) return false;
        return ['Approved', 'Rejected', 'Withdrawn', 'Cancelled'].includes(this.requestData.Status__c);
    }
    get terminalMessage() {
        const s = this.requestData ? this.requestData.Status__c : '';
        if (s === 'Approved') return 'This cancellation request has been approved and processed.';
        if (s === 'Rejected') return 'This cancellation request has been rejected.';
        return 'This cancellation request is ' + s + '.';
    }
    get terminalMessageClass() {
        const s = this.requestData ? this.requestData.Status__c : '';
        let base = 'slds-box slds-p-around_small slds-text-align_center ';
        if (s === 'Approved') return base + 'slds-theme_success slds-text-color_inverse';
        if (s === 'Rejected') return base + 'slds-theme_error slds-text-color_inverse';
        return base + 'slds-theme_info slds-text-color_inverse';
    }
    get isRejectDisabled() { return !this.rejectionReason || this.rejectionReason.trim() === ''; }

    handleSendToAccounting() { this._approve('accounting_review'); }
    handleApproveFinal() { this._approve('final'); }

    async _approve(approvalType) {
        this.isLoading = true;
        try {
            await approveRequest({ requestId: this.recordId, approvalType: approvalType });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: approvalType === 'accounting_review' ? 'Sent to Accounting Review' : 'Request Approved',
                variant: 'success'
            }));
            await refreshApex(this._wiredResult);
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error', message: e.body ? e.body.message : e.message, variant: 'error'
            }));
        }
        this.isLoading = false;
    }

    handleOpenRejectModal() { this.showRejectModal = true; }
    handleCloseRejectModal() { this.showRejectModal = false; this.rejectionReason = ''; }
    handleReasonChange(e) { this.rejectionReason = e.target.value; }

    async handleConfirmReject() {
        this.showRejectModal = false;
        this.isLoading = true;
        try {
            await rejectRequest({ requestId: this.recordId, rejectionReason: this.rejectionReason });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success', message: 'Request Rejected', variant: 'success'
            }));
            this.rejectionReason = '';
            await refreshApex(this._wiredResult);
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error', message: e.body ? e.body.message : e.message, variant: 'error'
            }));
        }
        this.isLoading = false;
    }
}