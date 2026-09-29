import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createWorkOrderForSelectedEstimate from '@salesforce/apex/ClaimEstimateService.createWorkOrderForSelectedEstimate';
import getActiveWorkOrderDetailsForClaim from '@salesforce/apex/ClaimEstimateService.getActiveWorkOrderDetailsForClaim';

function fmt(n) {
    const v = n || 0;
    return `$${v.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

/**
 * The Work Order tab's single component (Sep 22, extended in place rather
 * than adding a second LWC - Osama's explicit call): shows the "Create Work
 * Order" button when the claim has no active work order yet, and switches
 * to a detail view once one exists, instead of navigating away to the
 * Work_Order__c record - both the action and the result now live on this
 * same tab.
 *
 * Sep 24: detail view extended to the full "Selected Scenario" breakdown
 * from warranty_claims_dashboard (2).html (Customer Work Order / a-Protect
 * Internal Cost two-column card), sourced from Work_Order__c's own mirrored
 * formula fields plus a few purely descriptive fields read through the
 * Estimate lookup - see ClaimEstimateService.getActiveWorkOrderDetailsForClaim.
 *
 * Deliberately NOT automatic on the Claim_Status__c change to "Work Order" -
 * see the header comment history in ClaimEstimateService.cls for why.
 */
export default class CreateWorkOrderAction extends NavigationMixin(LightningElement) {
    @api recordId; // the Claim__c Id, injected by the record page

    isLoading = true;
    isCreating = false;
    workOrderDetail = null;

    connectedCallback() {
        this.loadDetail();
    }

    async loadDetail() {
        this.isLoading = true;
        try {
            this.workOrderDetail = await getActiveWorkOrderDetailsForClaim({ claimId: this.recordId });
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

    get partSummary() {
        const d = this.workOrderDetail;
        if (!d) return '';
        const kmsPart = d.condition === 'USED' && d.kms ? ` ${Number(d.kms).toLocaleString()} km` : '';
        return `Part: ${d.partComponent || '-'} · ${d.jobType || ''} · ${d.condition || ''}${kmsPart}`;
    }

    get supplierSummary() {
        const d = this.workOrderDetail;
        if (!d) return '';
        return `Supplier: ${d.partsSupplierName || '-'} · part# ${d.partCode || '-'} · stock# ${d.stockNumber || '-'} · ${d.repairShopName || ''}`;
    }

    get coverageLabel() {
        const d = this.workOrderDetail;
        if (!d) return 'Less warranty coverage applied';
        return `Less warranty coverage applied (cap ${fmt(d.capAmount)} − ded ${fmt(d.deductible)})`;
    }

    get labourLabel() {
        const d = this.workOrderDetail;
        if (!d) return 'Labour';
        return `Labour (${d.labourHours || 0} hrs × ${fmt(d.labourRate)})`;
    }

    get insuranceLabel() {
        const d = this.workOrderDetail;
        if (!d) return 'Part warranty';
        return `Part warranty (${d.insuranceSource || 'None'})`;
    }

    get taxLabel() {
        const d = this.workOrderDetail;
        if (!d || !d.customerPaysPreTax) return 'Tax';
        const pct = (d.taxAmount / d.customerPaysPreTax) * 100;
        return `Tax (${pct.toFixed(2)}%)`;
    }

    get plClass() {
        const d = this.workOrderDetail;
        if (!d || d.finalProfitLoss == null) return 'pl-value';
        return d.finalProfitLoss >= 0 ? 'pl-value pl-profit' : 'pl-value pl-loss';
    }

    get plLabel() {
        const d = this.workOrderDetail;
        if (!d || d.finalProfitLoss == null) return '';
        return d.finalProfitLoss >= 0 ? 'A-Protect PROFIT on this claim' : 'A-Protect LOSS on this claim';
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