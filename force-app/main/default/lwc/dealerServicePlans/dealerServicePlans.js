import { LightningElement } from 'lwc';
import EXTENDED from '@salesforce/resourceUrl/ExtendedWarrantyService';
import EV from '@salesforce/resourceUrl/EVWarranties';
import PRO from '@salesforce/resourceUrl/ProWarranties';
import POWER from '@salesforce/resourceUrl/PowerSupportWarranties';
import TIRE from '@salesforce/resourceUrl/TireAndRimProtection';
import CAR from '@salesforce/resourceUrl/CarLoanProtection';
import DOWNLOAD from '@salesforce/resourceUrl/downloadIcon';

export default class DealerServicePlans extends LightningElement {
    cards = [
        { id: 'extended', img: EXTENDED, cardClass: 'plan-card' },
        { id: 'ev', img: EV, cardClass: 'plan-card' },
        { id: 'pro', img: PRO, cardClass: 'plan-card' },
        { id: 'powersports', img: POWER, cardClass: 'plan-card' },
        { id: 'tire', img: TIRE, cardClass: 'plan-card' },
        { id: 'carloan', img: CAR, cardClass: 'plan-card'}
    ];
    staticResources = {
        downloadIcon: DOWNLOAD
    };

    handleClick(event) {
        const btn = event.target.closest('button');
        if (!btn) return;
        const action = btn.dataset.action;
        const cardEl = btn.closest('[data-id]');
        const cardId = cardEl ? cardEl.dataset.id : '';
        // alert(`Action: ${action} on ${cardId}`);
    }
}