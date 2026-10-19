import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createWorkOrderForSelectedEstimate from '@salesforce/apex/ClaimEstimateService.createWorkOrderForSelectedEstimate';
import getActiveWorkOrderDetailsForClaim from '@salesforce/apex/ClaimEstimateService.getActiveWorkOrderDetailsForClaim';
import getSelectedEstimateForClaim from '@salesforce/apex/ClaimEstimateService.getSelectedEstimateForClaim';

/**
 * The Work Order tab's single component (Sep 22, extended in place rather
 * than adding a second LWC - Osama's explicit call): shows the "Create Work
 * Order" button when the claim has no active work order yet, and switches
 * to a detail view once one exists, instead of navigating away to the
 * Work_Order__c record - both the action and the result now live on this
 * same tab.
 *
 * Sep 24 added a two-column "Customer Work Order / A-Protect Internal Cost"
 * breakdown here. TASK-050 REMOVED it on Osama's instruction, 2026-10-08: the
 * work order PDF is now the customer-facing document and opens from the Work
 * Order PDF button on this card, so the breakdown was duplicating it. The card
 * now shows the header figures, the approved-repairs table and that button.
 * getActiveWorkOrderDetailsForClaim still returns the breakdown fields; they
 * are simply no longer rendered.
 *
 * Deliberately NOT automatic on the Claim_Status__c change to "Work Order" -
 * see the header comment history in ClaimEstimateService.cls for why.
 */
export default class CreateWorkOrderAction extends NavigationMixin(LightningElement) {
    @api recordId; // the Claim__c Id, injected by the record page

    isLoading = true;
    isCreating = false;
    workOrderDetail = null;

    /**
     * TASK-050 item 5. The claim's estimate marked Use, or null when there is
     * none. The button is disabled until there is one, so the agent is told
     * what to do instead of being refused after the click.
     * createWorkOrderForSelectedEstimate still refuses server side, and that
     * remains the authoritative check: this only moves the message earlier.
     *
     * Osama, 2026-10-09: it holds the record rather than a Boolean because the
     * tab now names the estimate above the button, so the agent can see which
     * one they are about to commit to before an action that is hard to undo.
     */
    selectedEstimate = null;

    get estimateSelected() {
        return !!this.selectedEstimate;
    }

    get noEstimateSelected() {
        return !this.isLoading && !this.estimateSelected;
    }

    get cannotCreate() {
        return this.isCreating || !this.estimateSelected;
    }

    /** Estimate_Name__c is the name agents use; Name is the auto-number. */
    get selectedEstimateName() {
        if (!this.selectedEstimate) return '';
        return this.selectedEstimate.Estimate_Name__c || this.selectedEstimate.Name;
    }

    get selectedEstimateShop() {
        return this.selectedEstimate &&
            this.selectedEstimate.Repair_Shop__r &&
            this.selectedEstimate.Repair_Shop__r.Name;
    }

    get selectedEstimateUrl() {
        return this.selectedEstimate ? '/' + this.selectedEstimate.Id : '';
    }

    get selectedEstimateRetail() {
        return this.selectedEstimate && this.selectedEstimate.Retail_Total__c;
    }

    get selectedEstimateCustomerPays() {
        return this.selectedEstimate && this.selectedEstimate.Customer_Pays_With_Tax__c;
    }

    /**
     * TASK-050. Whether the Work Order PDF preview modal is open. Opening it
     * saves nothing; workOrderPdfPreview writes only on Save PDF or Save and
     * Send PDF, so closing with Cancel leaves no trace on the record.
     */
    showPdf = false;

    handleShowPdf() {
        this.showPdf = true;
    }

    handlePdfClose() {
        this.showPdf = false;
    }

    connectedCallback() {
        this.loadDetail();
    }

    async loadDetail() {
        this.isLoading = true;
        try {
            this.workOrderDetail = await getActiveWorkOrderDetailsForClaim({ claimId: this.recordId });
            if (!this.workOrderDetail) {
                // Only matters on the branch that offers the button.
                this.selectedEstimate = await getSelectedEstimateForClaim({ claimId: this.recordId });
            }
        } catch (error) {
            this.showError('Could Not Load Work Order', error);
        } finally {
            this.isLoading = false;
        }
    }

    get hasActiveWorkOrder() {
        return !!this.workOrderDetail;
    }

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
            await this.loadDetail();
        } catch (error) {
            this.showError('Could Not Create Work Order', error, 'sticky');
        } finally {
            this.isCreating = false;
        }
    }

    navigateToRecord(event, objectApiName) {
        event.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: event.currentTarget.dataset.id,
                objectApiName,
                actionName: 'view'
            }
        });
    }

    handleWorkOrderClick(event) {
        this.navigateToRecord(event, 'Work_Order__c');
    }

    handleLineClick(event) {
        this.navigateToRecord(event, 'Work_Order_Line_Item__c');
    }

    handleEstimateClick(event) {
        this.navigateToRecord(event, 'Estimate__c');
    }

    showError(title, error, mode) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message: (error && error.body && error.body.message) || 'An unexpected error occurred.',
                variant: 'error',
                mode: mode || 'dismissable'
            })
        );
    }
}