import { LightningElement, api, track } from 'lwc';
import TrisuraLogo from '@salesforce/resourceUrl/TrisuraLogo';
import getGAPProgramInfo from '@salesforce/apex/GAPProgramInfoController.getGAPProgramInfo';

export default class DealerPortalGap extends LightningElement {
    trisuraLogoUrl = TrisuraLogo;

    @track portalUrl = 'https://www.trisura.com';
    @track programContent = '';
    @track loading = false;

    // Preserve all @api properties the container sets
    @api isLocked = false;
    @api applicationStatus;

    _applicationId;

    @api
    get applicationId() {
        return this._applicationId;
    }
    set applicationId(value) {
        this._applicationId = value;
    }

    // Preserve all @api methods the container may call
    @api
    onTabActivated() {
        console.log('🎯 GAP TAB ACTIVATED (Trisura info page)');
        this.loadProgramInfo();
    }

    @api
    checkForExistingApplicationPackage() {
        // No-op: Trisura info page has no package logic
        return Promise.resolve();
    }

    @api
    restoreData(data) {
        // No-op: no data to restore
    }

    @api
    testComponent() {
        return { success: true, component: 'dealerPortalGap-trisura' };
    }

    @api
    setApplicationId(id) {
        this._applicationId = id;
    }

    get isQuoteStatus() {
        return this.applicationStatus === 'Quote';
    }

    connectedCallback() {
        this.loadProgramInfo();
    }

    async loadProgramInfo() {
        try {
            const result = await getGAPProgramInfo();
            if (result) {
                this.portalUrl = result.portalUrl || 'https://www.trisura.com';
                this.programContent = result.content || '';
            }
        } catch (error) {
            console.error('Error loading GAP program info:', error);
            // Fallback content if Apex call fails (e.g. permission issue)
            this.programContent = [
                'Trisura Guarantee Insurance Company – GAP Program:',
                '',
                'Trisura provides Guaranteed Asset Protection (GAP) coverage that bridges the gap between what you owe on your vehicle and what your primary insurance pays in the event of a total loss.',
                '',
                'Key Features:',
                '• Covers the difference between the vehicle\'s actual cash value and the outstanding loan/lease balance',
                '• Available for new and used vehicles',
                '• Seamless claims process',
                '',
                'For full program details and to submit claims, please visit the Trisura portal using the link above.'
            ].join('\n');
        }
    }

    // Format the program content for display with line breaks
    get formattedContentLines() {
        if (!this.programContent) return [];
        return this.programContent.split('\n').map((line, index) => {
            const isBullet = line.trim().startsWith('•');
            return {
                key: 'line-' + index,
                text: line,
                isBullet: isBullet,
                isHeader: !isBullet && line.trim().endsWith(':') && line.trim().length > 0,
                isEmpty: line.trim().length === 0
            };
        });
    }

    // Navigation handlers - preserve all events
    handleBack() {
        this.dispatchEvent(new CustomEvent('back', {
            detail: { data: {} },
            bubbles: true
        }));
    }

    handleContinue() {
        this.dispatchEvent(new CustomEvent('gapcomplete', {
            detail: {
                success: true,
                skipped: true,
                applicationId: this._applicationId
            }
        }));
    }

    handleSaveAsQuote() {
        this.dispatchEvent(new CustomEvent('saveasquote', {
            detail: {
                applicationId: this._applicationId
            },
            bubbles: true
        }));
    }

    handleSkip() {
        this.dispatchEvent(new CustomEvent('gapcomplete', {
            detail: {
                success: true,
                skipped: true,
                applicationId: this._applicationId
            }
        }));
    }
}