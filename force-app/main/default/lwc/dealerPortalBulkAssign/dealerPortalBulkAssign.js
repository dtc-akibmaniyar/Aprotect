import { LightningElement, api, track } from 'lwc';
import assignPlanToAllDealers from '@salesforce/apex/DealerPackageSyncService.assignPlanToAllDealers';

/**
 * dealerPortalBulkAssign — admin bulk-assign tool (change plan §09.1, P2).
 *
 * Hosted on the master Package__c record page (internal A-Protect app). Runs a
 * dry-run preview first, then assigns the plan to every eligible Dealer Account
 * via DealerPackageSyncService.assignPlanToAllDealers. The underlying sync is
 * idempotent — re-running is safe and duplicates nothing.
 */
export default class DealerPortalBulkAssign extends LightningElement {
    @api recordId;
    @api objectApiName;

    @track scope = 'ALL';
    @track running = false;
    @track hasResult = false;
    @track resultMessage = '';
    @track resultTitle = '';
    @track resultVariant = 'info';
    @track totalDealers = 0;
    @track alreadyAssigned = 0;
    @track toAssign = 0;
    @track batchJobIdText = '—';

    get scopeOptions() {
        return [
            { label: 'ALL — every Dealer Account', value: 'ALL' },
            { label: 'FAMILY — dealers already selling this plan group', value: 'FAMILY' }
        ];
    }

    get isPackageRecord() {
        return this.objectApiName === 'Package__c' && this.recordId != null;
    }

    handleScopeChange(event) {
        this.scope = event.detail.value;
        this.hasResult = false;
    }

    handlePreview() {
        this.invoke(false, true);
    }

    handleAssign() {
        this.invoke(true, false);
    }

    handleCheck() {
        this.invoke(false, false);
    }

    async invoke(apply, dryRun) {
        this.running = true;
        this.hasResult = false;
        this.resultMessage = '';
        try {
            const res = await assignPlanToAllDealers({
                packageId: this.recordId,
                scope: this.scope,
                dryRun: dryRun || !apply
            });
            this.hasResult = true;
            this.totalDealers = res.totalDealersConsidered;
            this.alreadyAssigned = res.alreadyAssigned;
            this.toAssign = res.newlyAssigned != null && res.newlyAssigned > 0
                ? res.newlyAssigned
                : res.toAssign;
            this.batchJobIdText = res.batchJobId ? String(res.batchJobId) : '—';
            this.resultMessage = res.message;
            this.resultVariant = res.success ? 'success' : 'error';
            this.resultTitle = res.success ? 'Done' : 'Error';
        } catch (e) {
            this.hasResult = true;
            this.resultVariant = 'error';
            this.resultTitle = 'Error';
            this.resultMessage = e.body && e.body.message ? e.body.message : String(e);
        } finally {
            this.running = false;
        }
    }
}