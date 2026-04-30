import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import Toast from 'lightning/toast';
import getRemittanceForm from '@salesforce/apex/DealerPortalRemittanceHandler.getRemittanceForm';
import createRemittanceForm from '@salesforce/apex/DealerPortalRemittanceHandler.createRemittanceForm';
import deleteRemittanceForm from '@salesforce/apex/DealerPortalRemittanceHandler.deleteRemittanceForm';
import getBulkConfirmationData from '@salesforce/apex/DealerPortalRemittanceHandler.getBulkConfirmationData';

const COLUMNS = [
    {
        label: 'Remittance Form Name',
        fieldName: 'recordUrl',
        type: 'url',
        typeAttributes: {
            label: { fieldName: 'Name' },
            target: '_self'
        },
        sortable: true,
        cellAttributes: { alignment: 'left' }
    }
];

const CONFIRMATION_COLUMNS = [
    {
        label: 'Application Number',
        fieldName: 'applicationNumber',
        type: 'text',
        sortable: true,
        cellAttributes: { alignment: 'left' }
    }
];

export default class DealerPostalRemitanceForm extends NavigationMixin(LightningElement) {
    @api recordIds; // List of Application record Ids
    @api bulkMode = false; // Flag to indicate bulk mode

    @track remittanceFormList = [];
    @track columns = COLUMNS;
    @track confirmationColumns = CONFIRMATION_COLUMNS;
    @track errorMessage = '';
    @track isLoading = true;
    @track showCreateButton = false;
    @track isCreating = false;
    @track isDeleting = false;
    @track showConfirmationModal = false;
    @track confirmationData = [];
    @track selectedRecordIds = [];

    wiredRemittanceFormResult;

    @wire(getRemittanceForm, { applicationIds: '$recordIds' })
    wiredRemittanceForm(result) {
        // Only call this wire if we're in single mode (bulkMode = false)
        if (this.bulkModeBoolean || !this.recordIds || this.recordIds.length === 0) {
            this.isLoading = false;
            return;
        }

        this.wiredRemittanceFormResult = result;
        const { data, error } = result;
        this.isLoading = true;

        if (data) {
            this.errorMessage = data.errorMessage || '';
            this.remittanceFormList = data.remittanceFormList || [];
            this.showCreateButton = data.showCreateButton;
            this.isLoading = false;
        } else if (error) {
            this.isLoading = false;
            this.showCreateButton = false;
            this.errorMessage =
                error?.body?.message || 'Error loading remittance form';
            console.error('Remittance Form load error:', error);
        }
    }
    connectedCallback() {
        // If in bulk mode, load confirmation data immediately
        console.log('Connected Callback - bulkMode:', this.bulkMode);
    }

    renderedCallback() {
        // Check if confirmation modal is visible and scroll to it
        if (this.showConfirmationModal) {
            console.log('🎯 renderedCallback: Modal is visible, attempting scroll');
            
            // Find the modal element
            const modal = this.template.querySelector('.slds-modal_small');
            if (modal) {
                console.log('✅ Found modal element, scrolling into view');
                modal.scrollIntoView({ behavior: 'smooth', block: 'center' });
            } else {
                console.warn('⚠️ Modal element not found in DOM');
            }
        }
    }

    get hasRecords() {
        return this.remittanceFormList.length > 0;
    }

    get bulkModeBoolean() {
        return this.bulkMode === true || this.bulkMode === 'true';
    }

    get remittanceFormNumber() {
        if (this.confirmationData && this.confirmationData.length > 0) {
            return this.confirmationData[0].remittanceFormNumber || 'R01';
        }
        return 'R01';
    }

    // Disable remove button when only one application remains
    get disableRemove() {
        return (this.confirmationData?.length || 0) <= 1;
    }

    get subTotal() {
        let total = 0;
        if (this.confirmationData) {
            this.confirmationData.forEach(app => {
                if (app.packageList) {
                    app.packageList.forEach(pkg => {
                        if (pkg.isSelected && typeof pkg.priceWithoutTax === 'number') {
                            total += pkg.priceWithoutTax;
                        }
                    });
                }
            });
        }
        return '$' + total.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    get taxAmount() {
        let total = 0;
        if (this.confirmationData) {
            this.confirmationData.forEach(app => {
                if (app.packageList) {
                    app.packageList.forEach(pkg => {
                        if (pkg.isSelected && typeof pkg.taxAmount === 'number') {
                            total += pkg.taxAmount;
                        }
                    });
                }
            });
        }
        return '$' + total.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    get formTotal() {
        let total = 0;
        if (this.confirmationData) {
            this.confirmationData.forEach(app => {
                if (app.packageList) {
                    app.packageList.forEach(pkg => {
                        if (pkg.isSelected && typeof pkg.priceWithTax === 'number') {
                            total += pkg.priceWithTax;
                        }
                    });
                }
            });
        }
        return '$' + total.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    async handleCreateRemittanceForm() {
        // Always show confirmation modal for bulk operations
        await this.showConfirmationModalWithData();
    }

    async showConfirmationModalWithData() {
        this.isLoading = true;
        try {
            const result = await getBulkConfirmationData({ 
                applicationIds: this.recordIds 
            });

            if (result && result.confirmationList && result.confirmationList.length > 0) {
                debugger;
                // Enrich data with dynamic pricing from server
                this.confirmationData = result.confirmationList.map((app, index) => {
                    const computedPackages = (app.packageList || []).map(pkg => {
                        const priceWithoutTax = typeof pkg.priceWithoutTax === 'number' ? pkg.priceWithoutTax : 0;
                        const priceWithTax = typeof pkg.priceWithTax === 'number' ? pkg.priceWithTax : priceWithoutTax;
                        return {
                            ...pkg,
                            amount: priceWithTax,
                            formattedAmount: '$' + priceWithoutTax.toFixed(2)
                        };
                    });

                    // Calculate total for this application
                    let applicationTotal = 0;
                    let applicationSubTotal = 0;
                    let applicationTaxTotal = 0;
                    let applicationTaxPercentage = 0;
                    computedPackages.forEach((pkg, idx) => {
                        if (pkg.isSelected && typeof pkg.amount === 'number') {
                            applicationTotal += pkg.amount;
                        }
                        if (pkg.isSelected && typeof pkg.priceWithoutTax === 'number') {
                            applicationSubTotal += pkg.priceWithoutTax;
                        }
                        if (pkg.isSelected && typeof pkg.taxAmount === 'number') {
                            applicationTaxTotal += pkg.taxAmount;
                        }
                        // Get tax percentage from first selected package (same for all)
                        if (idx === 0 && typeof pkg.taxPercentage === 'number') {
                            applicationTaxPercentage = pkg.taxPercentage;
                        }
                    });

                    return {
                        ...app,
                        customerName: app.customerName || '',
                        vehicleInfo: app.vehicleName || 'Year/Make/Model/Trim',
                        vin: app.vehicleVin || 'VIN Number',
                        totalDue: applicationTotal,
                        formattedTotalDue: '$' + applicationTotal.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ','),
                        subTotal: applicationSubTotal,
                        formattedSubTotal: '$' + applicationSubTotal.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ','),
                        applicationTaxAmount: applicationTaxTotal,
                        formattedApplicationTaxAmount: '$' + applicationTaxTotal.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ','),
                        applicationTaxPercentage: applicationTaxPercentage,
                        packageList: computedPackages
                    };
                });
                
                this.selectedRecordIds = result.confirmationList.map(app => app.applicationId);
                this.showConfirmationModal = true;
            } else {
                this.showToast('Error', 'No applications found with packages for remittance form creation', 'error');
            }
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Failed to load confirmation data', 'error');
            console.error('Load confirmation data error:', error);
        } finally {
            this.isLoading = false;
        }
    }

    handleConfirmCreate() {
        // Confirm and create a single remittance form for all selected applications
        if (this.selectedRecordIds.length === 0) {
            this.showToast('Warning', 'Please select at least one application', 'warning');
            return;
        }
        this.isCreating = true;
        console.log('selectedRecordIds:', this.selectedRecordIds);
        
        // Create a single remittance form for all selected applications
        createRemittanceForm({ 
            applicationIds: this.selectedRecordIds
        })
            .then((result) => {
                // Show toast with link to the created remittance form
                if (result && result.remittanceFormId) {
                    // Toast.show({
                    //     label: 'Remittance form created successfully',
                    //     message: 'Click {remittanceFormLink} to view the created form',
                    //     messageLinks: {
                    //         remittanceFormLink: {
                    //             url: '/dealerportal/s/detail/' + result.remittanceFormId,
                    //             label: 'here'
                    //         }
                    //     },
                    //     mode: 'dismissible',
                    //     variant: 'success'
                    // }, this);
                    this.showToast('Success', 'Remittance form created successfully for selected applications', 'success');

                    // Redirect to remittance form record after 2 seconds
                    setTimeout(() => {
                        this[NavigationMixin.Navigate]({
                            type: 'standard__recordPage',
                            attributes: {
                                recordId: result.remittanceFormId,
                                actionName: 'view'
                            }
                        });
                    }, 2000);
                } 
                // else {
                //     this.showToast('Success', 'Remittance form created successfully for selected applications', 'success');
                // }
                
                this.confirmationData = [];
                this.selectedRecordIds = [];
                this.showConfirmationModal = false;
                refreshApex(this.wiredRemittanceFormResult);
                this.dispatchEvent(new CustomEvent('remittanceformsCreated'));
                
            })
            .catch(error => {
                this.showToast('Error', error.body?.message || 'Failed to create remittance form', 'error');
                console.error('Create remittance form error:', error);
            })
            .finally(() => {
                this.isCreating = false;
            });
    }

    handleCancelModal() {
        this.showConfirmationModal = false;
        this.confirmationData = [];
        this.selectedRecordIds = [];
    }

    handleRowSelection(event) {
        const selectedRows = event.detail.selectedRows;
        this.selectedRecordIds = selectedRows.map(row => row.applicationId);
    }

    // Remove an application from the modal and from recordIds
    handleRemoveApplication(event) {
        const applicationId = event.currentTarget?.dataset?.applicationId;
        if (!applicationId) {
            return;
        }

        // Remove from confirmationData
        this.confirmationData = (this.confirmationData || []).filter(app => app.applicationId !== applicationId);

        // Remove from selectedRecordIds
        this.selectedRecordIds = (this.selectedRecordIds || []).filter(id => id !== applicationId);

        // Remove from input api recordIds if available and reflect change outward
        if (Array.isArray(this.recordIds)) {
            this.recordIds = this.recordIds.filter(id => id !== applicationId);
        }

        // Recompute totals will naturally occur via getters using confirmationData
        // If no applications left, close modal
        if (!this.confirmationData || this.confirmationData.length === 0) {
            this.showConfirmationModal = false;
        }
    }

    async handleDeleteRemittanceForm() {
        if (!confirm('Are you sure you want to delete the remittance form?')) {
            return;
        }

        this.isDeleting = true;
        try {
            if (this.remittanceFormList.length > 0 && this.recordIds && this.recordIds.length > 0) {
                const remittanceFormId = this.remittanceFormList[0].Id;
                const result = await deleteRemittanceForm({
                    applicationId: this.recordIds[0],
                    remittanceFormId: remittanceFormId
                });

                if (result.success) {
                    this.showToast('Success', result.message, 'success');
                    // Refresh the wired data
                    await refreshApex(this.wiredRemittanceFormResult);
                } else {
                    this.showToast('Error', result.message, 'error');
                }
            }
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Failed to delete remittance form', 'error');
            console.error('Delete remittance form error:', error);
        } finally {
            this.isDeleting = false;
        }
    }

    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(evt);
    }
}