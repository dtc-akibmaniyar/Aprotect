import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getEstimatesForClaim from '@salesforce/apex/ClaimEstimateService.getEstimatesForClaim';

const COLUMNS = [
    {
        label: 'Estimate',
        fieldName: 'estimateUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'estimateName' }, target: '_self' },
        wrapText: true
    },
    { label: 'Repair Shop', fieldName: 'repairShopName' },
    { label: 'Retail Total', fieldName: 'retailTotal', type: 'currency', typeAttributes: { currencyCode: 'CAD' } },
    // Osama, 2026-10-09: Source removed, Customer Pays (+tax) added after
    // Retail Total. The label matches Estimate__c.Customer_Pays_With_Tax__c's
    // own label, and the value is that stamped field read as-is.
    { label: 'Customer Pays (+tax)', fieldName: 'customerPaysWithTax', type: 'currency', typeAttributes: { currencyCode: 'CAD' } },
    { label: 'Selected', fieldName: 'isSelected', type: 'boolean' }
];

/**
 * Deliberately imperative, not @wire (Sep 22 fix): getEstimatesForClaim is
 * no longer cacheable, and a plain call-and-reassign on every load/refresh
 * is the simplest way to guarantee this list always reflects the result of
 * a just-completed Manage Estimates save, with no wire/refreshApex/cache
 * subtlety to reason about.
 */
export default class ClaimEstimatesList extends NavigationMixin(LightningElement) {
    @api recordId;

    columns = COLUMNS;
    estimates = [];
    isLoading = true;

    connectedCallback() {
        this.loadEstimates();
    }

    async loadEstimates() {
        this.isLoading = true;
        try {
            const data = await getEstimatesForClaim({ claimId: this.recordId });
            this.estimates = data.map((e) => ({
                id: e.Id,
                estimateUrl: '/' + e.Id,
                estimateName: e.Estimate_Name__c || e.Name,
                repairShopName: e.Repair_Shop__r ? e.Repair_Shop__r.Name : '',
                retailTotal: e.Retail_Total__c,
                customerPaysWithTax: e.Customer_Pays_With_Tax__c,
                isSelected: e.Is_Selected__c
            }));
        } finally {
            this.isLoading = false;
        }
    }

    get hasEstimates() {
        return this.estimates.length > 0;
    }

    /**
     * TASK-047: this used to open repairPriceScenarios as a lightning/modal.
     * The rebuilt Manage Estimates screen needs considerably more room than a
     * modal can give it (Osama's decision 2), so it now navigates to the
     * standalone Manage Estimates tab instead, carrying the claim in page
     * state because an App Page has no record context of its own.
     *
     * The list refreshes on the way back through connectedCallback, which is
     * why getEstimatesForClaim is deliberately not cacheable. There is no
     * modal result to await any more.
     */
    handleNewEstimate() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Manage_Estimates' },
            state: { c__claimId: this.recordId }
        });
    }
}