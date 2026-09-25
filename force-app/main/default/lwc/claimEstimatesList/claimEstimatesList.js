import { LightningElement, api } from 'lwc';
import getEstimatesForClaim from '@salesforce/apex/ClaimEstimateService.getEstimatesForClaim';
import RepairPriceScenarios from 'c/repairPriceScenarios';

const COLUMNS = [
    {
        label: 'Estimate',
        fieldName: 'estimateUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'estimateName' }, target: '_self' },
        wrapText: true
    },
    { label: 'Repair Shop', fieldName: 'repairShopName' },
    { label: 'Source', fieldName: 'source' },
    { label: 'Retail Total', fieldName: 'retailTotal', type: 'currency', typeAttributes: { currencyCode: 'CAD' } },
    { label: 'Selected', fieldName: 'isSelected', type: 'boolean' }
];

/**
 * Deliberately imperative, not @wire (Sep 22 fix): getEstimatesForClaim is
 * no longer cacheable, and a plain call-and-reassign on every load/refresh
 * is the simplest way to guarantee this list always reflects the result of
 * a just-completed Manage Estimates save, with no wire/refreshApex/cache
 * subtlety to reason about.
 */
export default class ClaimEstimatesList extends LightningElement {
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
                source: e.Source__c,
                retailTotal: e.Retail_Total__c,
                isSelected: e.Is_Selected__c
            }));
        } finally {
            this.isLoading = false;
        }
    }

    get hasEstimates() {
        return this.estimates.length > 0;
    }

    async handleNewEstimate() {
        const result = await RepairPriceScenarios.open({
            size: 'large',
            label: 'Repair Price Scenarios',
            claimId: this.recordId
        });
        if (result === 'saved') {
            await this.loadEstimates();
        }
    }
}