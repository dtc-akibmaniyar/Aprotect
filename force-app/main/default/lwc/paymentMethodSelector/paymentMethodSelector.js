import { LightningElement, api } from 'lwc';
import CHEQUE_PAYMENT from '@salesforce/resourceUrl/ChequePayment';
import ETRANSFER_PAYMENT from '@salesforce/resourceUrl/ETransfer';
import CARDS_ICONS from '@salesforce/resourceUrl/Cards_Icons';

export default class PaymentMethodSelector extends LightningElement {
    @api disabled = false;
    @api availableCredit = 0;

    staticResources = {
        chequePayment: CHEQUE_PAYMENT,
        eTransfer: ETRANSFER_PAYMENT,
        cardsIcons: CARDS_ICONS
    };

    get hasDealerCredit() {
        return this.availableCredit != null && this.availableCredit > 0;
    }

    get formattedAvailableCredit() {
        const credit = this.availableCredit || 0;
        return '$' + parseFloat(credit).toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    handleSelectCreditCard() {
        if (this.disabled) return;
        this.dispatchEvent(new CustomEvent('paymentmethodselected', {
            detail: {
                method: 'creditCard'
            }
        }));
    }

    handleSelectCheque() {
        if (this.disabled) return;
        this.dispatchEvent(new CustomEvent('paymentmethodselected', {
            detail: {
                method: 'cheque'
            }
        }));
    }

    handleSelectETransfer() {
        if (this.disabled) return;
        this.dispatchEvent(new CustomEvent('paymentmethodselected', {
            detail: {
                method: 'eTransfer'
            }
        }));
    }

    handleSelectDealerCredit() {
        if (this.disabled) return;
        this.dispatchEvent(new CustomEvent('paymentmethodselected', {
            detail: {
                method: 'dealerCredit'
            }
        }));
    }
}