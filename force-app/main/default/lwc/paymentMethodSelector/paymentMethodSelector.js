import { LightningElement, api } from 'lwc';
import CHEQUE_PAYMENT from '@salesforce/resourceUrl/ChequePayment';
import ETRANSFER_PAYMENT from '@salesforce/resourceUrl/ETransfer';
import CARDS_ICONS from '@salesforce/resourceUrl/Cards_Icons';

export default class PaymentMethodSelector extends LightningElement {
    @api disabled = false;

    staticResources = {
        chequePayment: CHEQUE_PAYMENT,
        eTransfer: ETRANSFER_PAYMENT,
        cardsIcons: CARDS_ICONS
    };
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
}