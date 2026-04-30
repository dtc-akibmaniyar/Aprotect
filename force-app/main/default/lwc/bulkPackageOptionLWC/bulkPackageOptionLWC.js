import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';

import { refreshApex } from '@salesforce/apex';
import getPackageOptions from '@salesforce/apex/PackageOptionBulkController.getPackageOptions';
import getAvailableOptions from '@salesforce/apex/PackageOptionBulkController.getAvailableOptions';
import savePackageOption from '@salesforce/apex/PackageOptionBulkController.savePackageOption';

export default class PackageOptionsManager extends LightningElement {
    wiredPackageOptionsResult;
    
    @wire(getPackageOptions, { packageId: '$recordId' })
    wiredPackageOptions(result) {
        this.wiredPackageOptionsResult = result;
        if (result.data) {
            this.packageOptions = result.data;
        }
    }

    @api
    async refresh() {
        if (this.wiredPackageOptionsResult) {
            await refreshApex(this.wiredPackageOptionsResult);
        }
    }
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        console.log('Record ID set:', value);
        if (value) {
            this.loadData();
        }
    }
    _recordId;

    @track packageOptions = [];
    @track availableOptions = [];
    @track error;
    @track isLoading = false;
    @track newOption = {
        optionId: '',
        inclusionText: '',
        exclusionText: ''
    };

    columns = [
        {
            label: 'Option',
            fieldName: 'optionName',
            type: 'text'
        },
        {
            label: 'Inclusion Text',
            fieldName: 'inclusionText',
            type: 'text'
        },
        {
            label: 'Exclusion Text',
            fieldName: 'exclusionText',
            type: 'text'
        }
    ];

    connectedCallback() {
        // Clear any cached data
        this.packageOptions = [];
        this.availableOptions = [];
        this.error = undefined;
        this.isLoading = false;
        this.newOption = {
            optionId: '',
            inclusionText: '',
            exclusionText: ''
        };

        // Load fresh data if recordId exists
        if (this._recordId) {
            this.loadData();
        }
    }

    async loadData() {
        if (!this._recordId) return;
        
        try {
            this.isLoading = true;

            // Force cache refresh by adding timestamp
            const timestamp = new Date().getTime();
            
            
            // Load package options
            const packageOpts = await getPackageOptions({ packageId: this._recordId });
            console.log('Package Options:', packageOpts);
            // Create a new array reference to trigger reactivity
            this.packageOptions = [...packageOpts];

            // Load available options
            const options = await getAvailableOptions();
            console.log('Available Options:', options);
            this.availableOptions = [...options];
            
        } catch (error) {
            console.error('Error loading data:', error);
            this.error = error.message || 'An error occurred while loading data';
        } finally {
            this.isLoading = false;
        }
    }

    handleOptionChange(event) {
        this.newOption.optionId = event.detail.value;
    }

    handleInclusionTextChange(event) {
        this.newOption.inclusionText = event.detail.value;
    }

    handleExclusionTextChange(event) {
        this.newOption.exclusionText = event.detail.value;
    }

    async handleSave() {
        if (!this.newOption.optionId) {
            this.showToast('Error', 'Please select an option', 'error');
            return;
        }

        try {
            this.isLoading = true;
            
            await savePackageOption({ 
                packageId: this._recordId,
                optionId: this.newOption.optionId,
                inclusionText: this.newOption.inclusionText,
                exclusionText: this.newOption.exclusionText
            });

            // Reset form
            this.newOption = {
                optionId: '',
                inclusionText: '',
                exclusionText: ''
            };

            // Explicitly reload the data
            await this.loadData();
            
            this.showToast('Success', 'Package option added successfully', 'success');
            // Refresh the view
            this.dispatchEvent(new CustomEvent('refresh'));
            
        } catch (error) {
            console.error('Error saving:', error);
            this.showToast('Error', error.message || 'An error occurred while saving', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
    closeQuickAction() {
        debugger;
        // First refresh the record view
        this[NavigationMixin.Navigate](
            {
                type: 'standard__recordPage',
                attributes: {
                    recordId: this._recordId,
                    actionName: 'view'
                }
            },
            true // Replaces the current page in browser history
        );

        // Then close the modal
        this.dispatchEvent(new CloseActionScreenEvent());
    }
    async handleRefresh() {
        try {
            this.isLoading = true;
            await this.loadData();
            this.showToast('Success', 'List refreshed successfully', 'success');
        } catch (error) {
            console.error('Error refreshing:', error);
            this.showToast('Error', 'Failed to refresh list', 'error');
        } finally {
            this.isLoading = false;
        }
    }
}