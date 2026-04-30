import { LightningElement, track, wire } from 'lwc';
import getDealerPackagesHierarchy from '@salesforce/apex/DealerPortalMarkupController.getDealerPackagesHierarchy';

export default class DealerPortalMarkup extends LightningElement {
    @track isLoading = false;
    @track error;
    @track packages = [];

    @wire(getDealerPackagesHierarchy)
    wiredPackages({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.error = undefined;
            this.packages = this.normalizePackages(data);
        } else if (error) {
            this.packages = [];
            this.error = this.normalizeError(error);
        }
    }

    connectedCallback() {
        this.isLoading = true;
    }

    normalizePackages(rawPackages) {
        const packagesArray = Array.isArray(rawPackages) ? rawPackages : [];
        return packagesArray.map((pkg) => {
            const tiers = Array.isArray(pkg.tiers) ? pkg.tiers : [];
            const terms = Array.isArray(pkg.terms) ? pkg.terms : [];

            const tierIds = new Set(tiers.map((t) => t?.Id).filter(Boolean));
            const noTierTerms = terms.filter((t) => !t?.tierId);

            const normalizedTiers = tiers.map((tier) => ({
                ...tier,
                terms: Array.isArray(tier?.terms) ? tier.terms : [],
                displayLabel: this.tierLabel(tier)
            }));

            if (noTierTerms.length > 0) {
                normalizedTiers.push({
                    Id: `no-tier-${pkg.Id}`,
                    Name: 'No Tier',
                    mileageRestrictionStart: null,
                    mileageRestrictionEnd: null,
                    terms: noTierTerms,
                    displayLabel: 'No Tier'
                });
            }

            // If we somehow got terms with tierId but no tier container, add pseudo tiers for them
            const orphanTierIdToTerms = new Map();
            terms
                .filter((t) => t?.tierId && !tierIds.has(t.tierId))
                .forEach((t) => {
                    if (!orphanTierIdToTerms.has(t.tierId)) orphanTierIdToTerms.set(t.tierId, []);
                    orphanTierIdToTerms.get(t.tierId).push(t);
                });

            for (const [tierId, orphanTerms] of orphanTierIdToTerms.entries()) {
                normalizedTiers.push({
                    Id: `missing-tier-${tierId}`,
                    Name: `Tier ${tierId}`,
                    mileageRestrictionStart: null,
                    mileageRestrictionEnd: null,
                    terms: orphanTerms,
                    displayLabel: `Tier ${tierId}`
                });
            }

            return {
                ...pkg,
                tiers: normalizedTiers,
                packageLabel: pkg?.PackageName || pkg?.Name || 'Dealer Package',
                tierCount: normalizedTiers.length,
                termCount: terms.length
            };
        });
    }

    tierLabel(tier) {
        const name = tier?.Name || 'Tier';
        const start = tier?.mileageRestrictionStart;
        const end = tier?.mileageRestrictionEnd;
        if (start != null && end != null) {
            return `${name} (${start}-${end})`;
        }
        return name;
    }

    normalizeError(err) {
        try {
            if (err?.body?.message) return err.body.message;
            if (Array.isArray(err?.body) && err.body.length > 0 && err.body[0]?.message) return err.body[0].message;
            if (err?.message) return err.message;
            return 'Unknown error loading dealer packages.';
        } catch (e) {
            return 'Unknown error loading dealer packages.';
        }
    }

    get hasError() {
        return Boolean(this.error);
    }

    get hasPackages() {
        return Array.isArray(this.packages) && this.packages.length > 0;
    }
}