import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import createWorkOrders from '@salesforce/apex/WorkOrderCreatorController.createWorkOrders';

export default class WorkOrderCreator extends NavigationMixin(LightningElement) {
    @api estimateId;
    @track loading = false;
    @track error;

    async handleSubmit() {
        try {
            if (!this.estimateId) {
                throw new Error('Estimate ID is required');
            }
            this.loading = true;
            const workOrderIds = await createWorkOrders({ estimateId: this.estimateId });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: `Created ${workOrderIds.length} Work Order(s) successfully`,
                    variant: 'success'
                })
            );
            // Navigate to the estimate record page
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.estimateId,
                    objectApiName: 'Estimate__c',
                    actionName: 'view'
                }
            });
        } catch (error) {
            this.error = error;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: error.message || error.body?.message || 'An error occurred while creating the Work Orders',
                    variant: 'error'
                })
            );
        } finally {
            this.loading = false;
        }
    }
}