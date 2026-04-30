import { LightningElement } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class AllocationRemittanceFlowAction extends LightningElement {

    handleStatusChange(event) {
        if (event.detail.status === 'FINISHED') {
            this.dispatchEvent(new CloseActionScreenEvent());
        }
    }
}