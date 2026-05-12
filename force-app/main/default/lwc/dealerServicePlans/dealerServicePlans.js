import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getActiveBrochures from '@salesforce/apex/BrochureController.getActiveBrochures';
import DOWNLOAD_ICON from '@salesforce/resourceUrl/downloadIcon';

// Fallback images from static resources (used when Card_Image_URL__c is empty)
import EXTENDED from '@salesforce/resourceUrl/ExtendedWarrantyService';
import EV from '@salesforce/resourceUrl/EVWarranties';
import PRO from '@salesforce/resourceUrl/ProWarranties';
import POWER from '@salesforce/resourceUrl/PowerSupportWarranties';
import TIRE from '@salesforce/resourceUrl/TireAndRimProtection';
import CAR from '@salesforce/resourceUrl/CarLoanProtection';

const FALLBACK_IMAGES = {
    'Extended Warranty': EXTENDED,
    'EV Warranty': EV,
    'Pro Warranty': PRO,
    'Powersport Warranty': POWER,
    'Tire & Rim Protection': TIRE,
    'Tire and Rim Protection': TIRE,
    'Car Loan Protection': CAR
};

export default class DealerServicePlans extends NavigationMixin(LightningElement) {
    @track cards = [];
    @track isLoading = true;
    @track hasError = false;
    @track errorMessage = '';

    downloadIcon = DOWNLOAD_ICON;

    connectedCallback() {
        this.loadBrochures();
    }

    async loadBrochures() {
        this.isLoading = true;
        try {
            const data = await getActiveBrochures();
            this.cards = data.map(b => {
                const docs = b.documents || [];
                const categoryPlan = docs.find(d => d.documentType === 'Category Plan');
                const fullBrochure = docs.find(d => d.documentType === 'Full Brochure');
                const sampleVsa = docs.find(d => d.documentType === 'Sample Vehicle Service Agreement');

                return {
                    id: b.id,
                    category: b.category,
                    cardImageUrl: b.cardImageUrl || FALLBACK_IMAGES[b.category] || '',
                    versionNumber: b.versionNumber,
                    description: b.description,
                    cardClass: 'plan-card',
                    categoryPlanUrl: categoryPlan ? categoryPlan.downloadUrl : null,
                    fullBrochureUrl: fullBrochure ? fullBrochure.downloadUrl : null,
                    sampleVsaUrl: sampleVsa ? sampleVsa.downloadUrl : null,
                    hasCategoryPlan: !!(categoryPlan && categoryPlan.downloadUrl),
                    hasFullBrochure: !!(fullBrochure && fullBrochure.downloadUrl),
                    hasSampleVsa: !!(sampleVsa && sampleVsa.downloadUrl)
                };
            });
            this.hasError = false;
        } catch (error) {
            this.hasError = true;
            this.errorMessage = this.reduceErrors(error);
            this.cards = [];
        } finally {
            this.isLoading = false;
        }
    }

    get hasCards() {
        return this.cards.length > 0;
    }

    _getCard(event) {
        const cardEl = event.target.closest('[data-id]');
        if (!cardEl) return null;
        return this.cards.find(c => c.id === cardEl.dataset.id);
    }

    handleViewPlans(event) {
        const card = this._getCard(event);
        if (card && card.categoryPlanUrl) {
            window.open(card.categoryPlanUrl, '_blank');
        }
    }

    handleDownloadBrochure(event) {
        const card = this._getCard(event);
        if (card && card.fullBrochureUrl) {
            window.open(card.fullBrochureUrl, '_blank');
        }
    }

    handleViewSample(event) {
        const card = this._getCard(event);
        if (card && card.sampleVsaUrl) {
            window.open(card.sampleVsaUrl, '_blank');
        }
    }

    reduceErrors(error) {
        if (!error) return 'Unknown error';
        if (typeof error === 'string') return error;
        if (error.body) {
            if (typeof error.body.message === 'string') return error.body.message;
        }
        if (error.message) return error.message;
        return JSON.stringify(error);
    }
}