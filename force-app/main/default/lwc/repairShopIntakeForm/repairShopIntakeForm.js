import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getVehicleAndShopInfoFromClaim from '@salesforce/apex/RepairShopIntakeFormController.getVehicleAndShopInfoFromClaim';
import createEstimate from '@salesforce/apex/RepairShopIntakeFormController.createEstimate';

export default class RepairShopIntakeForm extends LightningElement {
    @api claimId;
    @api repairShopId;
    @track loading = false;
    @track error;

    @track services = [];
    @track parts = [];
    @track supplies = [];
    @track repairComments = '';
    
    @track formData = {
        vehicleInfo: {
            vehicle: '',
            vin: '',
            odometerIn: '',
            odometerOut: ''
        },
        shopInfo: {
            name: '',
            address: '',
            email: '',
            phone: '',
            hstNumber: '',
            taxPercentage: 0
        },
        customerInfo: {
            name: '',
            address: '',
            phone: '',
            email: ''
        },
        totals: {
            laborTotal: 0,
            partsTotal: 0,
            suppliesTotal: 0,
            subtotal: 0,
            tax: 0,
            total: 0
        }
    };

    connectedCallback() {
        if (this.claimId) {
            this.loadClaimInfo();
        }
    }

    async loadClaimInfo() {
        this.loading = true;
        this.error = undefined;

        try {
            const result = await getVehicleAndShopInfoFromClaim({ 
                claimId: this.claimId 
            });
            
            if (result.vehicleInfo) {
                this.formData.vehicleInfo = result.vehicleInfo;
            }
            if (result.shopInfo) {
                this.formData.shopInfo = result.shopInfo;
            }
            if (result.customerInfo) {
                this.formData.customerInfo = result.customerInfo;
            }

        } catch (error) {
            console.error('Error loading claim info:', error);
            this.error = error.body?.message || 'Unknown error occurred while loading claim information';
        } finally {
            this.loading = false;
        }
    }

    // Service Methods
    handleAddService() {
        const newService = {
            id: Date.now(),
            category: '',
            description: '',
            serviceTime: '',
            cost: 0,
            price: 0,
            discount: 0,
            charge: 0
        };
        this.services = [...this.services, newService];
    }

    handleRemoveService(event) {
        const index = event.target.dataset.index;
        this.services = this.services.filter((_, i) => i !== parseInt(index, 10));
        this.calculateTotals();
    }

    handleServiceChange(event) {
        const index = event.target.dataset.index;
        const field = event.target.dataset.field;
        let value = event.target.value;
        
        if (['cost', 'price', 'discount', 'charge'].includes(field)) {
            value = parseFloat(value) || 0;
        }
        
        const services = [...this.services];
        services[index] = { ...services[index], [field]: value };
        this.services = services;
        this.calculateTotals();
    }

    // Supply Methods
    handleAddSupply() {
        const newSupply = {
            id: Date.now(),
            itemName: '',
            description: '',
            supplyTime: '',
            quantity: 0,
            cost: 0,
            price: 0,
            discount: 0,
            charge: 0
        };
        this.supplies = [...this.supplies, newSupply];
    }

    handleRemoveSupply(event) {
        const index = event.target.dataset.index;
        this.supplies = this.supplies.filter((_, i) => i !== parseInt(index, 10));
        this.calculateTotals();
    }

    handleSupplyChange(event) {
        const index = event.target.dataset.index;
        const field = event.target.dataset.field;
        let value = event.target.value;
        
        if (['quantity', 'cost', 'price', 'discount', 'charge'].includes(field)) {
            value = parseFloat(value) || 0;
        }
        
        const supplies = [...this.supplies];
        supplies[index] = { ...supplies[index], [field]: value };
        this.supplies = supplies;
        this.calculateTotals();
    }

    // Parts Methods
    handleAddPart() {
        const newPart = {
            id: Date.now(),
            partCode: '',
            description: '',
            quantity: 0,
            partCost: 0,
            price: 0,
            discount: 0,
            productCharge: 0
        };
        this.parts = [...this.parts, newPart];
    }

    handleRemovePart(event) {
        const index = event.target.dataset.index;
        this.parts = this.parts.filter((_, i) => i !== parseInt(index, 10));
        this.calculateTotals();
    }

    handlePartChange(event) {
        const index = event.target.dataset.index;
        const field = event.target.dataset.field;
        let value = event.target.value;
        
        if (['quantity', 'partCost', 'price', 'discount', 'productCharge'].includes(field)) {
            value = parseFloat(value) || 0;
        }
        
        const parts = [...this.parts];
        parts[index] = { ...parts[index], [field]: value };
        this.parts = parts;
        this.calculateTotals();
    }

    calculateTotals() {
        const laborTotal = this.services.reduce((sum, service) => sum + (service.charge || 0), 0);
        const partsTotal = this.parts.reduce((sum, part) => sum + (part.productCharge || 0), 0);
        const suppliesTotal = this.supplies.reduce((sum, supply) => sum + (supply.charge || 0), 0);
        const subtotal = laborTotal + partsTotal + suppliesTotal;
        const taxRate = Number(this.formData.shopInfo.taxPercentage) || 0;  // Get tax rate from shop info
        const tax = subtotal * (taxRate / 100);  // Calculate tax based on the rate
        const total = subtotal + tax;
    
        this.formData.totals = {
            laborTotal,
            partsTotal,
            suppliesTotal,
            subtotal,
            tax,
            total
        };
    }

    handleCommentsChange(event) {
        this.repairComments = event.target.value;
    }

    async handleSubmit() {
        try {
            this.loading = true;
    
            const estimateRequest = {
                claimId: this.claimId,
                repairShopId: this.repairShopId,
                services: this.services.map(service => ({
                    category: service.category,
                    description: service.description,
                    serviceTime: service.serviceTime,
                    cost: Number(service.cost),
                    price: Number(service.price),
                    discount: Number(service.discount),
                    charge: Number(service.charge)
                })),
                parts: this.parts.map(part => ({
                    partCode: part.partCode,
                    description: part.description,
                    quantity: Number(part.quantity),
                    partCost: Number(part.partCost),
                    price: Number(part.price),
                    discount: Number(part.discount),
                    productCharge: Number(part.productCharge)
                })),
                supplies: this.supplies.map(supply => ({
                    itemName: supply.itemName,
                    description: supply.description,
                    supplyTime: supply.supplyTime,
                    quantity: Number(supply.quantity),
                    cost: Number(supply.cost),
                    price: Number(supply.price),
                    discount: Number(supply.discount),
                    charge: Number(supply.charge)
                })),
                repairComments: this.repairComments
            };
    
            const response = await createEstimate({ request: estimateRequest });
    
            if (response && response.status === 'SUCCESS') {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: response.message,
                        variant: 'success'
                    })
                );
            } else {
                throw new Error(response?.message || 'Unknown error occurred');
            }
    
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: error.body?.message || error.message || 'Error creating estimate',
                    variant: 'error'
                })
            );
        } finally {
            this.loading = false;
        }
    }
}