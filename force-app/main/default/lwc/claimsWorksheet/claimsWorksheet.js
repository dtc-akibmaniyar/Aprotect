import { LightningElement, wire, track } from 'lwc';
import getPartsForEstimate from '@salesforce/apex/claimsWorksheetController.getPartsForEstimate';
import getLabourForEstimate from '@salesforce/apex/claimsWorksheetController.getLabourForEstimate';
import saveAllRecords from '@salesforce/apex/claimsWorksheetController.saveAllRecords';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ClaimsWorksheet extends LightningElement {
    @track isEditMode = false;
    @track parts = [];
    @track labours = [];
    isEdited = false;

    // Store original data for cancel operation
    originalParts = [];
    originalLabours = [];

    @wire(getPartsForEstimate)
    wiredParts({ error, data }) {
        if (data) {
            this.parts = this.processPartsData(data);
            this.originalParts = JSON.parse(JSON.stringify(this.parts));
        } else if (error) {
            this.showToast('Error', 'Error loading parts data', 'error');
        }
    }

    @wire(getLabourForEstimate)
    wiredLabour({ error, data }) {
        if (data) {
            this.labours = data;
            this.originalLabours = JSON.parse(JSON.stringify(this.labours));
        } else if (error) {
            this.showToast('Error', 'Error loading labour data', 'error');
        }
    }

    processPartsData(data) {
        return data.map(p => {
            const qty = Number(p.Quantity__c) || 0;
            const cost = Number(p.Part_Cost__c) || 0;
            let markup = p.Retail_Markup__c;
            if (typeof markup === 'string') {
                markup = Number(markup.replace('%', '').trim());
            } else {
                markup = Number(markup) || 0;
            }
            const subtotal = qty * cost * (1 + markup / 100);
            return { 
                ...p, 
                subtotal: subtotal,
                subtotalDisplay: subtotal ? `$${subtotal.toFixed(2)}` : '' 
            };
        });
    }

    handleEdit() {
        this.isEditMode = true;
    }

    handleCancel() {
        // Restore original data
        this.parts = JSON.parse(JSON.stringify(this.originalParts));
        this.labours = JSON.parse(JSON.stringify(this.originalLabours));
        this.isEditMode = false;
        this.isEdited = false;
    }

    async handleSave() {
        try {
            await saveAllRecords({ 
                parts: this.parts, 
                services: this.labours 
            });
            
            // Update original data after successful save
            this.originalParts = JSON.parse(JSON.stringify(this.parts));
            this.originalLabours = JSON.parse(JSON.stringify(this.labours));
            
            this.showToast('Success', 'Records updated successfully', 'success');
            this.isEditMode = false;
            this.isEdited = false;
        } catch (error) {
            this.showToast('Error', error.body.message, 'error');
        }
    }

    handlePartChange(event) {
        this.isEdited = true;
        const fieldName = event.target.name;
        const value = event.target.value;
        const partId = event.target.dataset.id;

        this.parts = this.parts.map(part => {
            if (part.Id === partId) {
                const updatedPart = { ...part, [fieldName]: value };
                // Recalculate subtotal
                const qty = Number(updatedPart.Quantity__c) || 0;
                const cost = Number(updatedPart.Part_Cost__c) || 0;
                let markup = updatedPart.Retail_Markup__c;
                if (typeof markup === 'string') {
                    markup = Number(markup.replace('%', '').trim());
                } else {
                    markup = Number(markup) || 0;
                }
                const subtotal = qty * cost * (1 + markup / 100);
                updatedPart.subtotal = subtotal;
                updatedPart.subtotalDisplay = subtotal ? `$${subtotal.toFixed(2)}` : '';
                return updatedPart;
            }
            return part;
        });
    }

    handleLabourChange(event) {
        this.isEdited = true;
        const fieldName = event.target.name;
        const value = event.target.value;
        const labourId = event.target.dataset.id;

        this.labours = this.labours.map(labour => {
            if (labour.Id === labourId) {
                return { ...labour, [fieldName]: value };
            }
            return labour;
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }

    get firstLabour() {
        return this.labours && this.labours.length > 0 ? this.labours[0] : null;
    }

    get totalPartsCost() {
        const total = this.parts.reduce((sum, part) => sum + (part.subtotal || 0), 0);
        return total ? `$${total.toFixed(2)}` : '$0.00';
    }

    get totalLabourCost() {
        return this.labours.reduce((sum, l) => {
            const time = Number(l.Time__c) || 0;
            const rate = Number(l.Wholesale_Labour_Rate_HR__c) || 0;
            return sum + (time * rate);
        }, 0);
    }

    get totalLabourCostDisplay() {
        return this.totalLabourCost ? `$${this.totalLabourCost.toFixed(2)}` : '';
    }

    get labourSubTotal() {
        return this.labours.reduce((sum, l) => {
            const time = Number(l.Time__c) || 0;
            const rate = Number(l.Wholesale_Labour_Rate_HR__c) || 0;
            let markup = l.Retail_Markup__c;
            if (typeof markup === 'string') {
                markup = Number(markup.replace('%', '').trim());
            } else {
                markup = Number(markup) || 0;
            }
            return sum + (time * rate * (1 + markup / 100));
        }, 0);
    }

    get labourSubTotalDisplay() {
        return this.labourSubTotal ? `$${this.labourSubTotal.toFixed(2)}` : '';
    }

    get shopSupplies() {
        if (this.firstLabour) {
            const wholesale = Number(this.firstLabour.Shop_Supplies__c) || 0;
            const markup = Number(this.firstLabour.Shop_Supplies_Markup__c) || 0;
            const retail = wholesale * (1 + markup/100);
            
            return {
                wholesale: wholesale ? `$${wholesale.toFixed(2)}` : '$0.00',
                description: this.firstLabour.Shop_Supplies_Description__c || '',
                markup: `${markup}%`,
                retail: retail ? `$${retail.toFixed(2)}` : '$0.00'
            };
        }
        return {
            wholesale: '$0.00',
            description: '',
            markup: '0%',
            retail: '$0.00'
        };
    }
}