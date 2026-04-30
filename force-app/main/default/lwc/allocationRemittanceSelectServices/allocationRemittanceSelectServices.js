import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { FlowNavigationBackEvent, FlowNavigationFinishEvent } from 'lightning/flowSupport';
import createAllocationRemittanceForm from '@salesforce/apex/AllocationRemittanceHandler.createAllocationRemittanceForm';

export default class AllocationRemittanceSelectServices extends NavigationMixin(LightningElement) {

    // ─── Flow inputs ───────────────────────────────────────────────────────────
    // JSON string: [{"label":"Extended Limited Warranty","value":"Extended_Limited_Warranty"}, ...]
    @api availableServicesJson;

    // Comma-separated application IDs selected in the previous screen
    @api selectedApplicationIds;

    // ─── Flow output ───────────────────────────────────────────────────────────
    @api remittanceFormId;

    // ─── Tracked state ─────────────────────────────────────────────────────────
    @track selectedServices = [];
    @track isLoading        = false;
    @track errorMessage     = '';

    // ─── Computed: parse services from JSON prop ────────────────────────────────

    get serviceOptions() {
        if (!this.availableServicesJson) return [];
        try {
            return JSON.parse(this.availableServicesJson);
        } catch (e) {
            return [];
        }
    }

    get hasServices() {
        return this.serviceOptions.length > 0;
    }

    get isCreateDisabled() {
        return this.isLoading || !this.hasServices || this.selectedServices.length === 0;
    }

    // ─── Event handlers ────────────────────────────────────────────────────────

    handleServiceChange(event) {
        this.selectedServices = event.detail.value;
        this.errorMessage = '';
    }

    handlePrevious() {
        this.dispatchEvent(new FlowNavigationBackEvent());
    }

    async handleCreate() {
        if (this.selectedServices.length === 0) {
            this.errorMessage = 'Please select at least one service.';
            return;
        }

        const appIds = this.selectedApplicationIds
            ? this.selectedApplicationIds.split(',').map(id => id.trim()).filter(Boolean)
            : [];

        if (appIds.length === 0) {
            this.errorMessage = 'No applications provided. Please go back and select applications.';
            return;
        }

        // Expand Loan_Protection to also include GAP_Coverage
        const serviceTypes = [...this.selectedServices];
        if (serviceTypes.includes('Loan_Protection') && !serviceTypes.includes('GAP_Coverage')) {
            serviceTypes.push('GAP_Coverage');
        }

        this.isLoading    = true;
        this.errorMessage = '';

        try {
            const result = await createAllocationRemittanceForm({
                applicationIds:       appIds,
                selectedServiceTypes: serviceTypes
            });

            if (result.success) {
                this.remittanceFormId = result.remittanceFormId;
                this.dispatchEvent(new ShowToastEvent({
                    title:   'Success',
                    message: 'Allocation Remittance Form created successfully.',
                    variant: 'success'
                }));
                // Generate the community URL first, then assign directly.
                // NavigationMixin.Navigate is suppressed by FlowNavigationFinishEvent
                // (the Flow unmounts this component before the navigation fires).
                const url = await this[NavigationMixin.GenerateUrl]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId:      result.remittanceFormId,
                        objectApiName: 'Remittance_Form__c',
                        actionName:    'view'
                    }
                });
                window.location.assign(url);
            } else {
                this.errorMessage = result.message;
            }
        } catch (error) {
            this.errorMessage = error.body?.message || 'Failed to create Allocation Remittance Form.';
        } finally {
            this.isLoading = false;
        }
    }
}