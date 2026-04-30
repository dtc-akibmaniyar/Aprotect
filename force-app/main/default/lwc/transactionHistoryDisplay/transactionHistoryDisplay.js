import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import getTransactionHistory from '@salesforce/apex/DealerPortalTransactionHistoryController.getTransactionHistory';

export default class TransactionHistoryDisplay extends NavigationMixin(LightningElement) {
    @api recordId;
    transactions = [];
    isLoading = true;
    error;

    // hold wire result to allow manual refreshApex
    _wiredResult;

    @wire(getTransactionHistory, { recordId: '$recordId' })
    wiredTransactions(result) {
        // keep reference for refreshApex
        this._wiredResult = result;

        const { data, error } = result;
        if (data) {
            this.transactions = data.map(t => ({
                id: t.Id,
                recordType: t.RecordType.DeveloperName,
                isCheque: t.RecordType.DeveloperName === 'Cheque_Payment',
                isCard: t.RecordType.DeveloperName === 'Card_Payment',
                isETransfer: t.RecordType.DeveloperName === 'E_Transfer',
                chequeNumber: t.Cheque_Number__c,
                amount: t.Amount__c,
                formattedAmount: this.formatCurrency(t.Amount__c),
                notes: t.Notes__c,
                transactionReference: t.Transaction_Reference__c,
                cardNumber: t.Card_Number__c,
                status: t.Payment_Confirmation_Status__c,
                statusBadgeClass: this.getStatusBadgeClass(t.Payment_Confirmation_Status__c),
                statusHistory: this.buildStatusHistory(t)
            }));
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.transactions = [];
        }
        this.isLoading = false;
    }

    get variables() {
        return { recordId: this.recordId };
    }

    get hasTransactions() {
        return this.transactions && this.transactions.length > 0;
    }

    buildStatusHistory(t) {
        const entries = [
            { label: 'Payment Initiated',     date: t.Payment_Initiated_Date__c,      iconClass: 'timeline-icon icon-initiated' },
            { label: 'Deposit Pending',        date: t.Deposit_Pending_Date__c,         iconClass: 'timeline-icon icon-pending' },
            { label: 'Transaction Pending',    date: t.Transaction_Pending_Date__c,     iconClass: 'timeline-icon icon-pending' },
            { label: 'Pending Delivery',       date: t.Pending_Delivery_Date__c,        iconClass: 'timeline-icon icon-info' },
            { label: 'Deposit Completed',      date: t.Deposit_Completed_Date__c,       iconClass: 'timeline-icon icon-success' },
            { label: 'Transaction Completed',  date: t.Transaction_Completed_Date__c,   iconClass: 'timeline-icon icon-success' },
            { label: 'On Hold',                date: t.Hold_Date__c,                    iconClass: 'timeline-icon icon-hold' },
            { label: 'Failed Payment',         date: t.Failed_Payment_Date__c,          iconClass: 'timeline-icon icon-error' }
        ];
        const sorted = entries
            .filter(e => e.date)
            .map(e => ({ ...e, formattedDate: this.formatDateTime(e.date) }))
            .sort((a, b) => new Date(a.date) - new Date(b.date));
        if (sorted.length > 0) sorted[0].isFirst = true;
        return sorted;
    }

    formatDateTime(isoString) {
        if (!isoString) return '';
        const d = new Date(isoString);
        return d.toLocaleString('en-US', {
            month: 'short', day: 'numeric', year: 'numeric',
            hour: 'numeric', minute: '2-digit', hour12: true
        });
    }

    getStatusBadgeClass(status) {
        const map = {
            'Transaction Completed': 'status-badge status-badge--success',
            'Deposit Completed':     'status-badge status-badge--success',
            'Deposit Pending':       'status-badge status-badge--warning',
            'Transaction Pending':   'status-badge status-badge--warning',
            'Pending Delivery':      'status-badge status-badge--info',
            'Hold':                  'status-badge status-badge--hold',
            'Failed Payment':        'status-badge status-badge--error'
        };
        return map[status] || 'status-badge status-badge--default';
    }

    formatCurrency(value) {
        if (!value) return '';
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD',
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        }).format(value);
    }

    getDisplayStatus(status) {
        if (!status) return 'Pending';
        const statusMap = {
            'Transaction Completed': 'Approved',
            'Deposit Pending': 'Pending',
            'Failed Payment': 'Failed'
        };
        return statusMap[status] || status;
    }

    @api
    refreshTransactions() {
        if (this._wiredResult) {
            return refreshApex(this._wiredResult);
        }
    }

    handleViewTransaction(event) {
        event.preventDefault();
        const transactionId = event.currentTarget?.dataset?.id;
        if (!transactionId) return;
        
        const pageRef = {
            type: 'standard__recordPage',
            attributes: {
                recordId: transactionId,
                objectApiName: 'Payment__c',
                actionName: 'view'
            }
        };
        
        this[NavigationMixin.GenerateUrl](pageRef).then(url => {
            window.open(url, '_blank');
        });
    }
}