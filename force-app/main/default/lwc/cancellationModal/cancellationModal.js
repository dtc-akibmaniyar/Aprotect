import { LightningElement, api, wire, track } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';
import getApplicationDetails from '@salesforce/apex/CancellationModalController.getApplicationDetails';
import submitCancellationRequest from '@salesforce/apex/CancellationModalController.submitCancellationRequest';

const REASON_OPTIONS = [
    { label: 'Customer Request', value: 'Customer Request' },
    { label: 'Duplicate', value: 'Duplicate' },
    { label: 'Pricing Issue', value: 'Pricing Issue' },
    { label: 'Service Issue', value: 'Service Issue' },
    { label: 'Other', value: 'Other' }
];

export default class CancellationModal extends NavigationMixin(LightningElement) {
    @api recordId;
    
    @track currentStep = 1;
    @track services = [];
    @track selectedServiceIds = new Set();
    @track applicationName = '';
    @track applicationStatus = '';
    @track cancellationStatus = '';
    @track selectedReason = '';
    @track additionalDetails = '';
    @track isLoading = true;
    @track hasError = false;
    @track errorMessage = '';
    @track submitSuccess = false;
    @track requestId = '';

    reasonOptions = REASON_OPTIONS;

    @wire(getApplicationDetails, { applicationId: '$recordId' })
    wiredDetails({ error, data }) {
        this.isLoading = false;
        if (data) {
            const app = data.application;
            this.applicationName = app.name;
            this.applicationStatus = app.status || 'Unknown';
            this.cancellationStatus = app.cancellationStatus;
            
            this.services = (data.services || []).map(svc => ({
                id: svc.id,
                name: svc.name,
                coveragePlan: svc.coveragePlan,
                coverageTerm: svc.coverageTerm || 'N/A',
                price: svc.price || 0,
                active: svc.active,
                packageType: svc.packageType,
                selected: false
            }));
        } else if (error) {
            this.hasError = true;
            this.errorMessage = this.reduceErrors(error);
        }
    }

    // Computed properties
    get isStep1() { return this.currentStep === 1 && !this.hasError; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }

    get hasServices() { return this.services.length > 0; }

    get serviceOptions() {
        return this.services.map(svc => ({
            ...svc,
            displayName: svc.coveragePlan ? `${svc.name} — ${svc.coveragePlan}` : svc.name,
            selected: this.selectedServiceIds.has(svc.id),
            rowClass: this.selectedServiceIds.has(svc.id) 
                ? 'service-row service-row-selected slds-border_bottom' 
                : 'service-row slds-border_bottom'
        }));
    }

    get selectedCount() { return this.selectedServiceIds.size; }

    get allSelected() {
        return this.services.length > 0 && this.selectedServiceIds.size === this.services.length;
    }

    get totalRefundAmount() {
        let total = 0;
        this.services.forEach(svc => {
            if (this.selectedServiceIds.has(svc.id)) {
                total += svc.price;
            }
        });
        return total;
    }

    get isNextDisabled() { return this.selectedServiceIds.size === 0; }
    get isSubmitDisabled() { return !this.selectedReason; }

    get expectedOutcome() {
        const s = this.applicationStatus;
        if (s === 'Draft' || s === 'Quote') {
            return 'Immediate Cancellation';
        }
        return 'Pending Sales Review';
    }

    // Handlers
    handleSelectAll(event) {
        if (event.target.checked) {
            this.selectedServiceIds = new Set(this.services.map(s => s.id));
        } else {
            this.selectedServiceIds = new Set();
        }
    }

    handleServiceToggle(event) {
        const svcId = event.target.dataset.id;
        const newSet = new Set(this.selectedServiceIds);
        if (event.target.checked) {
            newSet.add(svcId);
        } else {
            newSet.delete(svcId);
        }
        this.selectedServiceIds = newSet;
    }

    handleReasonChange(event) { this.selectedReason = event.detail.value; }
    handleDetailsChange(event) { this.additionalDetails = event.detail.value; }

    handleNext() { this.currentStep = 2; }
    handleBack() { this.currentStep = 1; }
    handleBackToReason() { this.currentStep = 2; }

    handleClose() {
        // CloseActionScreenEvent for Quick Action context
        this.dispatchEvent(new CloseActionScreenEvent());
        // Custom close event for when embedded in other components
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleCloseAndRefresh() {
        // CloseActionScreenEvent for Quick Action context
        this.dispatchEvent(new CloseActionScreenEvent());
        // Custom close event for when embedded in other components
        this.dispatchEvent(new CustomEvent('close'));
        // Refresh the page
        setTimeout(() => {
            eval("$A.get('e.force:refreshView').fire()");
        }, 300);
    }

    async handleSubmit() {
        this.isLoading = true;
        try {
            this.requestId = await submitCancellationRequest({
                applicationId: this.recordId,
                serviceIds: Array.from(this.selectedServiceIds),
                reason: this.selectedReason,
                details: this.additionalDetails
            });
            this.submitSuccess = true;
            this.currentStep = 3;
        } catch (error) {
            this.submitSuccess = false;
            this.errorMessage = this.reduceErrors(error);
            this.currentStep = 3;
        } finally {
            this.isLoading = false;
        }
    }

    reduceErrors(error) {
        if (!error) return 'Unknown error';
        if (typeof error === 'string') return error;
        if (error.body) {
            if (typeof error.body.message === 'string') return error.body.message;
            if (error.body.fieldErrors) {
                return Object.values(error.body.fieldErrors)
                    .flat()
                    .map(e => e.message)
                    .join(', ');
            }
        }
        if (error.message) return error.message;
        return JSON.stringify(error);
    }
}