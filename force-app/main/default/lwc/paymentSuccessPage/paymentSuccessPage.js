import { LightningElement, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import getRemittanceFormDetails from '@salesforce/apex/PaymentSuccessController.getRemittanceFormDetails';

export default class PaymentSuccessPage extends NavigationMixin(LightningElement) {
    remittanceFormId;
    details;
    error;
    isLoading = true;

    @wire(CurrentPageReference)
    handlePageReference(pageRef) {
        if (pageRef && pageRef.state) {
            this.remittanceFormId = pageRef.state.remittanceFormId || pageRef.state.c__remittanceFormId;
        }
        // Fallback: read from URL search params
        if (!this.remittanceFormId && typeof window !== 'undefined') {
            const params = new URLSearchParams(window.location.search);
            this.remittanceFormId = params.get('remittanceFormId') || params.get('c__remittanceFormId');
        }
    }

    @wire(getRemittanceFormDetails, { remittanceFormId: '$remittanceFormId' })
    wiredDetails({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.details = data;
            this.error = undefined;
        } else if (error) {
            this.error = error.body?.message || 'Unable to load payment details.';
            this.details = undefined;
        }
    }

    get hasDetails() {
        return !!this.details;
    }

    get remittanceNumber() {
        return this.details?.remittanceFormName || '—';
    }

    get formattedTotalAmount() {
        const amt = this.details?.totalAmount;
        if (amt == null) return '$0.00';
        return '$' + parseFloat(amt).toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    get formattedPaidAmount() {
        const amt = this.details?.paidAmount;
        if (amt == null) return '$0.00';
        return '$' + parseFloat(amt).toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    get formattedDate() {
        if (!this.details?.createdDate) return '—';
        const d = new Date(this.details.createdDate);
        return d.toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' });
    }

    get paymentDate() {
        return new Date().toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' });
    }

    get dealerName() {
        return this.details?.dealerName || '—';
    }

    handleBackToDashboard() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'Home'
            }
        });
    }

    handleViewRemittance() {
        if (this.remittanceFormId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.remittanceFormId,
                    actionName: 'view'
                }
            });
        }
    }
}