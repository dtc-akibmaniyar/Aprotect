import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createWorkOrderForSelectedEstimate from '@salesforce/apex/ClaimEstimateService.createWorkOrderForSelectedEstimate';

/**
 * The explicit "Create Work Order" button on the Work Order tab (Sep 22).
 * Deliberately NOT automatic on the Claim_Status__c change to "Work Order" -
 * Osama caught that the plan originally had this fire on the status change
 * itself (mirroring the Invoice trigger), which was wrong: the agent needs
 * a deliberate moment to log Ancillary Benefits on this same tab first, and
 * the HTML reference itself has a real button, not automatic behavior.
 * Kept intentionally small (just this button) so it fully closes the "how
 * does a work order ever get created" gap on its own, without waiting on
 * the Ancillary Benefits LWC (the next, separate pass).
 */
export default class CreateWorkOrderAction extends NavigationMixin(LightningElement) {
    @api recordId; // the Claim__c Id, injected by the record page

    isCreating = false;

    get isDisabled() {
        return this.isCreating;
    }

    async handleCreateWorkOrder() {
        this.isCreating = true;
        try {
            const result = await createWorkOrderForSelectedEstimate({ claimId: this.recordId });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Work Order Created',
                    message: `${result.claimLineItems} line item(s) generated.`,
                    variant: 'success'
                })
            );
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: result.workOrderId,
                    objectApiName: 'Work_Order__c',
                    actionName: 'view'
                }
            });
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could Not Create Work Order',
                    message: (error && error.body && error.body.message) || 'An unexpected error occurred.',
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        } finally {
            this.isCreating = false;
        }
    }
}