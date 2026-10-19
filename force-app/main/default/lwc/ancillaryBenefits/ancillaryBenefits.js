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
            this.publishBenefits();
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
        this.publishBenefits();
    }

    handleUseAmountChange(event) {
        const balanceId = event.target.dataset.id;
        const value = event.target.value;
        this.rows = this.rows.map((row) =>
            row.balanceId === balanceId ? this.recalc({ ...row, useThisClaim: value }) : row
        );
        this.publishBenefits();
    }

    /**
     * TASK-047 integration point, the only behavioural change this component
     * needed to be reused inside Manage Estimates. It still owns and saves
     * benefits exactly as before; it now also announces the approved total so
     * repairPriceScenarios can credit it to every scenario as the agent
     * types, which is the design's "set benefits once, they flow into every
     * scenario". Harmless on the Work Order tab, where nothing listens.
     */
    publishBenefits() {
        const approved = this.rows
            .filter((row) => row.include && row.approved > 0)
            .map((row) => ({ name: row.benefitType, amount: row.approved }));
        this.dispatchEvent(
            new CustomEvent('benefitschange', {
                detail: {
                    total: approved.reduce((a, b) => a + b.amount, 0),
                    benefits: approved,
                    balances: this.rows.map((row) => ({
                        balanceId: row.balanceId,
                        benefitType: row.benefitType,
                        availableToUse: row.availableToUse,
                        // TASK-051: repairPriceScenarios.reimbRoom works from
                        // Remaining__c, not availableToUse, which adds back
                        // the claim-level draw rather than the scenario's own.
                        remaining: row.remaining
                    }))
                }
            })
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

        // Osama, 2026-10-08: unchecking a benefit and saving left it still
        // counted. Only the checked rows are sent, so an unchecked benefit that
        // already had a draw was absent from the payload and its
        // Benefit_Usage__c row survived, keeping the balance consumed and the
        // customer credited. Naming those rows is what lets Apex remove them.
        const removedUsageIds = this.rows
            .filter((row) => !row.include && row.usageId)
            .map((row) => row.usageId);

        this.isSaving = true;
        try {
            await saveBenefitUsage({ claimId: this.recordId, usages, removedUsageIds });
            const parts = [`${usages.length} benefit(s) recorded`];
            if (removedUsageIds.length) parts.push(`${removedUsageIds.length} removed`);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Ancillary Benefits Saved',
                    message: `${parts.join(', ')} for this claim.`,
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