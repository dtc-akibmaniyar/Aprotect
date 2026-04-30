import { LightningElement, api, wire, track } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import getEnvelopeStatusRecords from '@salesforce/apex/EnvelopeStatusService.getEnvelopeStatusRecords';
import { refreshApex } from '@salesforce/apex';

const COLUMNS = [
    {
        label: 'Envelope#',
        fieldName: 'recordUrl',
        type: 'url',
        typeAttributes: {
            label: { fieldName: 'Name' },
            target: '_blank'
        },
        sortable: true,
        cellAttributes: { alignment: 'left' }
    },
    {
        label: 'Sender Name',
        fieldName: 'dfsle__SenderName__c',
        type: 'text',
        sortable: true
    },
    {
        label: 'Sent',
        fieldName: 'dfsle__Sent__c',
        type: 'date',
        sortable: true,
        typeAttributes: {
            day: 'numeric',
            month: 'short',
            year: 'numeric',
            hour: '2-digit',
            minute: '2-digit'
        }
    },
    {
        label: 'Status',
        fieldName: 'dfsle__Status__c',
        type: 'text',
        sortable: true
    }
];

export default class EnvelopeStatusRelatedList extends LightningElement {
    @api recordId; // Application ID passed from parent
    @api sourceFieldName = 'dfsle__SourceId__c'; // Field name to filter by

    @track envelopeStatusList = [];
    @track columns = COLUMNS;
    @track errorMessage = '';
    @track isLoading = true;

    wiredEnvelopeData;

    connectedCallback() {
        // Extract recordId from URL if not passed as property
        if (!this.recordId) {
            const pathArray = window.location.pathname.split('/');
            const contentdocIndex = pathArray.indexOf('contentdocument');
            if (contentdocIndex !== -1 && pathArray[contentdocIndex + 2]) {
                this.recordId = pathArray[contentdocIndex + 2];
            }
        }
    }

    @wire(getEnvelopeStatusRecords, { sourceId: '$recordId' })
    wiredEnvelopeStatus(result) {
        debugger;
        this.wiredEnvelopeData = result;
        const { data, error } = result;

        if (data) {
            this.isLoading = false;
            // Format dates for display
            this.envelopeStatusList = data.map(record => ({
                ...record,
                recordUrl: '/dealerportal/s/detail/' + record.Id,
                dfsle__Sent__c: record.dfsle__Sent__c ? new Date(record.dfsle__Sent__c) : null,
                dfsle__Completed__c: record.dfsle__Completed__c ? new Date(record.dfsle__Completed__c) : null
            }));
            this.errorMessage = '';
        } else if (error) {
            this.isLoading = false;
            this.errorMessage = error.body?.message || 'Error loading envelope status records';
            console.error('Error loading envelope status:', error);
        }
    }

    get hasRecords() {
        return this.envelopeStatusList && this.envelopeStatusList.length > 0;
    }

    get spinnerClass() {
        return this.isLoading ? 'slds-show' : 'slds-hide';
    }

    // Handle refresh button click
    handleRefresh() {
        this.isLoading = true;
        refreshApex(this.wiredEnvelopeData)
            .then(() => {
                this.isLoading = false;
            })
            .catch((error) => {
                console.error('Error refreshing data:', error);
                this.isLoading = false;
            });
    }

    // Refresh method for parent to call if needed
    @api
    refreshEnvelopeStatus() {
        refreshApex(this.wiredEnvelopeData);
    }
}