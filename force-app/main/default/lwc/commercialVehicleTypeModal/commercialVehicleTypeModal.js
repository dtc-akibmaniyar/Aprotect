import { LightningElement, api } from 'lwc';

/**
 * commercialVehicleTypeModal
 *
 * Modal component for selecting a Commercial_Vehicle_Type__c value when the
 * Usage Type on a Vehicle__c record is "Commercial/Business Use".
 *
 * Events dispatched:
 *   - commercialvehicletypeselected : { value: String }
 *       Fired when the user clicks a "Select" card button.
 *       `value` is the exact picklist API value for Commercial_Vehicle_Type__c.
 *
 *   - commercialvehicletypeclose
 *       Fired when the user dismisses the modal without selecting.
 */
export default class CommercialVehicleTypeModal extends LightningElement {
    /**
     * Controls modal visibility. Set to true from the parent to open.
     */
    @api isOpen = false;

    /**
     * Handle the "Select" button click on any card.
     * Reads `data-value` from the button to know which picklist value was chosen.
     */
    handleSelect(event) {
        const selectedValue = event.currentTarget.dataset.value;

        console.log('🚗 Commercial vehicle type selected:', selectedValue);

        this.dispatchEvent(
            new CustomEvent('commercialvehicletypeselected', {
                detail: { value: selectedValue },
                bubbles: false,
                composed: false
            })
        );
    }

    /**
     * Handle the close button (X) click — modal dismissed without selection.
     */
    handleClose() {
        console.log('🚗 Commercial vehicle type modal closed without selection');

        this.dispatchEvent(
            new CustomEvent('commercialvehicletypeclose', {
                bubbles: false,
                composed: false
            })
        );
    }
}