import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getBenefitBalancesForClaim from '@salesforce/apex/ClaimEstimateService.getBenefitBalancesForClaim';
import saveBenefitUsage from '@salesforce/apex/ClaimEstimateService.saveBenefitUsage';

/**
 * Ancillary Benefits editor (Pass 2), on the Work Order tab. Benefits are
 * claim-level (Benefit_Balance__c is keyed off the claim's purchased
 * Application Package, not any one Estimate), which is why this lives here
 * rather than inside the Estimate grid. Live client-side calc mirrors the
 * same pattern as repairPriceScenarios: Approved = min(use, availableToUse),
 * Remaining After = availableToUse - Approved, recomputed on every keystroke,
 * no Apex round trip until Save.
 */
export default class AncillaryBenefits extends LightningElement {
    @api recordId;

    rows = [];
    isLoading = true;
    isSaving = false;

    connectedCallback() {
        this.loadBalances();
    }

    async loadBalances() {
        this.isLoading = true;
        try {
            const data = await getBenefitBalancesForClaim({ claimId: this.recordId });
            this.rows = data.map((r) => this.toRow(r));
        } catch (error) {
            this.showError('Could Not Load Ancillary Benefits', error);
        } finally {
            this.isLoading = false;
        }
    }

    toRow(r) {
        const included = r.usageAmount != null;
        const useThisClaim = r.usageAmount != null ? r.usageAmount : 0;
        return this.recalc({
            balanceId: r.balanceId,
            usageId: r.usageId,
            benefitType: r.benefitType,
            capAmount: r.capAmount,
            usedToDate: r.usedToDate,
            remaining: r.remaining,
            availableToUse: r.availableToUse,
            include: included,
            useThisClaim
        });
    }

    recalc(row) {
        const use = Number(row.useThisClaim) || 0;
        const approved = Math.min(use, row.availableToUse);
        return {
            ...row,
            approved,
            remainingAfter: row.availableToUse - approved,
            overLimit: use > row.availableToUse,
            excluded: !row.include
        };
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get isDisabled() {
        return this.isSaving;
    }

    handleIncludeChange(event) {
        const balanceId = event.target.dataset.id;
        const checked = event.target.checked;
        this.rows = this.rows.map((row) =>
            row.balanceId === balanceId ? this.recalc({ ...row, include: checked }) : row
        );
    }

    handleUseAmountChange(event) {
        const balanceId = event.target.dataset.id;
        const value = event.target.value;
        this.rows = this.rows.map((row) =>
            row.balanceId === balanceId ? this.recalc({ ...row, useThisClaim: value }) : row
        );
    }

    async handleSave() {
        const included = this.rows.filter((row) => row.include);
        if (included.some((row) => row.overLimit)) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Cannot Save',
                    message: "One or more benefits have a Use This Claim amount over their remaining balance.",
                    variant: 'error'
                })
            );
            return;
        }

        const usages = included.map((row) => ({
            Id: row.usageId || undefined,
            Benefit_Balance__c: row.balanceId,
            Amount_Used__c: row.useThisClaim
        }));

        this.isSaving = true;
        try {
            await saveBenefitUsage({ claimId: this.recordId, usages });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Ancillary Benefits Saved',
                    message: `${usages.length} benefit(s) recorded for this claim.`,
                    variant: 'success'
                })
            );
            await this.loadBalances();
        } catch (error) {
            this.showError('Could Not Save Ancillary Benefits', error, 'sticky');
        } finally {
            this.isSaving = false;
        }
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