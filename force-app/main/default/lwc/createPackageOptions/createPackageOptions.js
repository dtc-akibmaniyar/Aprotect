import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { FlowNavigationFinishEvent } from 'lightning/flowSupport';
import getRecordInfo from '@salesforce/apex/CreatePackageOptionsController.getRecordInfo';
import getPackageName from '@salesforce/apex/CreatePackageOptionsController.getPackageName';
import getOptions from '@salesforce/apex/CreatePackageOptionsController.getOptions';
import getCategoryPicklistValues from '@salesforce/apex/CreatePackageOptionsController.getCategoryPicklistValues';
import createPackageOptions from '@salesforce/apex/CreatePackageOptionsController.createPackageOptions';

export default class CreatePackageOptions extends LightningElement {
    /**
     * The recordId will be passed in from the Screen Flow.
     * Make sure to map the Flow recordId variable to this input
     * when you configure the component in the Flow Builder.
     */
    @api recordId;

    // View state: 'buttons', 'additionalOptionsTable', or 'includedOptionsTable'
    currentView = 'buttons';
    
    // Table rows data
    tableRows = [];
    rowCounter = 0;
    isSaving = false;
    hasInitialized = false; // Track if we've already initialized the view

    recordInfo;

    @wire(getRecordInfo, { recordId: '$recordId' })
    wiredRecordInfo(result) {
        this.recordInfo = result;
        // Log for debugging
        if (result.error) {
            console.error('Error loading record info:', result.error);
        }
        if (result.data) {
            console.log('Record info loaded:', result.data);
        }
        // Auto-navigate to appropriate table when record info is loaded
        if (result.data && !this.hasInitialized) {
            // Use setTimeout to ensure reactive properties are updated
            setTimeout(() => {
                this.initializeView();
            }, 0);
        }
    }

    @wire(getPackageName, { recordId: '$recordId' })
    packageNameResult;

    @wire(getOptions)
    optionsResult;

    @wire(getCategoryPicklistValues)
    categoryPicklistResult;

    get hasRecordInfo() {
        const hasData = this.recordInfo && this.recordInfo.data !== null && this.recordInfo.data !== undefined && !this.recordInfo.error;
        return hasData;
    }

    get recordInfoError() {
        return this.recordInfo?.error;
    }

    get recordInfoErrorMessage() {
        if (!this.recordInfoError) {
            return '';
        }
        return this.recordInfoError.body?.message || this.recordInfoError.message || 'Unknown error';
    }

    get displayRecordId() {
        return this.recordId || 'Not provided';
    }

    get isLoadingRecordInfo() {
        return this.recordInfo === undefined || (this.recordInfo && !this.recordInfo.data && !this.recordInfo.error);
    }

    get objectApiName() {
        return this.hasRecordInfo ? this.recordInfo.data.objectApiName : '';
    }

    get objectLabel() {
        return this.hasRecordInfo ? this.recordInfo.data.objectLabel : '';
    }

    get recordTypeName() {
        return this.hasRecordInfo ? this.recordInfo.data.recordTypeName : '';
    }

    get termName() {
        return this.hasRecordInfo ? (this.recordInfo.data.termName || '') : '';
    }

    get tierName() {
        return this.hasRecordInfo ? (this.recordInfo.data.tierName || '') : '';
    }

    get packageIdFromRecord() {
        return this.hasRecordInfo ? (this.recordInfo.data.packageId || this.recordId) : this.recordId;
    }

    get relationshipPath() {
        if (this.objectApiName === 'Package_Term__c') {
            let path = this.termName || 'Term';
            if (this.tierName) {
                path += ' > ' + this.tierName;
            }
            if (this.packageName) {
                path += ' > ' + this.packageName;
            }
            if (this.recordTypeName) {
                path += ' (' + this.recordTypeName + ')';
            }
            return path;
        }
        return '';
    }

    get isTotalLossCoverage() {
        return (
            (this.objectApiName === 'Package__c' || this.objectApiName === 'Package_Term__c') &&
            this.recordTypeName === 'Total Loss Coverage'
        );
    }

    get isTireAndRimProtectionPlan() {
        return (
            (this.objectApiName === 'Package__c' || this.objectApiName === 'Package_Term__c') &&
            this.recordTypeName === 'Tire & Rim Protection Plan'
        );
    }

    get isExtendedLimitedWarranty() {
        return (
            (this.objectApiName === 'Package__c' || this.objectApiName === 'Package_Term__c') &&
            this.recordTypeName === 'Extended Limited Warranty'
        );
    }

    get showButtons() {
        return (this.isTotalLossCoverage || this.isTireAndRimProtectionPlan || this.isExtendedLimitedWarranty) && this.currentView === 'buttons';
    }

    get showAdditionalOptionsButton() {
        // Show for Total Loss Coverage, OR for Extended Limited Warranty when accessed from Package_Term__c
        const isExtendedWarrantyFromTerm = this.objectApiName === 'Package_Term__c' && 
                                           this.recordTypeName === 'Extended Limited Warranty';
        return (this.isTotalLossCoverage || isExtendedWarrantyFromTerm) && this.currentView === 'buttons';
    }

    get showIncludedOptionsButton() {
        // Show for Tire & Rim Protection Plan, OR Extended Limited Warranty when NOT from Package_Term__c
        const isExtendedWarrantyFromTerm = this.objectApiName === 'Package_Term__c' && 
                                           this.recordTypeName === 'Extended Limited Warranty';
        const showExtendedWarranty = this.isExtendedLimitedWarranty && !isExtendedWarrantyFromTerm;
        return (this.isTireAndRimProtectionPlan || showExtendedWarranty) && this.currentView === 'buttons';
    }

    get showAdditionalOptionsTable() {
        return this.currentView === 'additionalOptionsTable';
    }

    get showIncludedOptionsTable() {
        return this.currentView === 'includedOptionsTable';
    }

    get isFromPackageTerm() {
        return this.objectApiName === 'Package_Term__c';
    }

    get displayName() {
        if (this.isFromPackageTerm) {
            return this.termName || 'Package Term';
        }
        return this.packageName || 'Package';
    }

    get displaySelectionType() {
        if (this.currentView === 'includedOptionsTable') {
            return 'Included';
        }
        return 'Optional';
    }

    get packageName() {
        // Prefer packageName from recordInfo if available (for Package_Term__c)
        if (this.hasRecordInfo && this.recordInfo.data.packageName) {
            return this.recordInfo.data.packageName;
        }
        return this.packageNameResult?.data || '';
    }

    get options() {
        return this.optionsResult?.data || [];
    }

    get optionsForCombobox() {
        return this.options.map(opt => ({
            label: opt.Name,
            value: opt.Id
        }));
    }

    get categoryOptions() {
        return this.categoryPicklistResult?.data || [];
    }

    get categoryOptionsForCombobox() {
        return this.categoryOptions.map(cat => ({
            label: cat,
            value: cat
        }));
    }

    connectedCallback() {
        console.log('CreatePackageOptions connected with recordId:', this.recordId);
        if (!this.recordId) {
            console.warn('No recordId provided to CreatePackageOptions component');
        }
    }

    renderedCallback() {
        // Backup initialization if wire handler didn't trigger
        if (this.hasRecordInfo && !this.hasInitialized) {
            this.initializeView();
        }
    }

    /**
     * Automatically determine and navigate to the appropriate table view
     * based on record type and context
     */
    initializeView() {
        if (this.hasInitialized || !this.hasRecordInfo) {
            return;
        }

        // Determine which view to show based on the same logic as the buttons
        const isExtendedWarrantyFromTerm = this.objectApiName === 'Package_Term__c' && 
                                           this.recordTypeName === 'Extended Limited Warranty';
        
        // Show Additional Options table for:
        // - Total Loss Coverage, OR
        // - Extended Limited Warranty when accessed from Package_Term__c
        if (this.isTotalLossCoverage || isExtendedWarrantyFromTerm) {
            this.currentView = 'additionalOptionsTable';
            this.addRow();
        }
        // Show Included Options table for:
        // - Tire & Rim Protection Plan, OR
        // - Extended Limited Warranty when NOT from Package_Term__c
        else if (this.isTireAndRimProtectionPlan || 
                 (this.isExtendedLimitedWarranty && !isExtendedWarrantyFromTerm)) {
            this.currentView = 'includedOptionsTable';
            this.addIncludedRow();
        }

        this.hasInitialized = true;
    }

    handleCreateAdditionalOptions() {
        this.currentView = 'additionalOptionsTable';
        // Initialize with one empty row
        this.addRow();
    }

    handleCreateIncludedOptions() {
        this.currentView = 'includedOptionsTable';
        // Initialize with one empty row
        this.addIncludedRow();
    }

    addRow() {
        const serialNumber = this.tableRows.length + 1;
        if (this.isFromPackageTerm) {
            // For Package_Term__c: Package Term, Selection Type, Option, Inclusion Text, Exclusion Text, Price
            this.tableRows = [...this.tableRows, {
                id: 'row_' + this.rowCounter++,
                serialNumber: serialNumber,
                packageTermId: this.recordId,
                packageTermName: this.termName,
                selectionType: 'Optional',
                optionId: null,
                inclusionText: null,
                exclusionText: null,
                price: null
            }];
        } else {
            // For Package__c: Package Name, Selection Type, Category, Minimum Value, Maximum Value, Price
            // Option will be auto-matched based on Category name
            this.tableRows = [...this.tableRows, {
                id: 'row_' + this.rowCounter++,
                serialNumber: serialNumber,
                packageName: this.packageName,
                selectionType: 'Optional',
                optionId: null,
                category: null,
                minimumValue: null,
                maximumValue: null,
                price: null,
                errorMessage: null
            }];
        }
    }

    addIncludedRow() {
        const serialNumber = this.tableRows.length + 1;
        this.tableRows = [...this.tableRows, {
            id: 'row_' + this.rowCounter++,
            serialNumber: serialNumber,
            packageName: this.packageName,
            selectionType: 'Included',
            optionId: null,
            inclusionText: null,
            exclusionText: null
        }];
    }

    removeRow(event) {
        const rowId = event.currentTarget.dataset.rowId;
        this.tableRows = [...this.tableRows.filter(row => row.id !== rowId)];
        // Update serial numbers after removal
        this.updateSerialNumbers();
    }

    updateSerialNumbers() {
        this.tableRows = this.tableRows.map((row, index) => {
            return { ...row, serialNumber: index + 1 };
        });
    }

    handleOptionChange(event) {
        const rowId = event.currentTarget.dataset.rowId;
        const optionId = event.detail.value;
        this.tableRows = this.tableRows.map(row => {
            if (row.id === rowId) {
                return { ...row, optionId: optionId || null };
            }
            return row;
        });
    }

    handleCategoryChange(event) {
        const rowId = event.currentTarget.dataset.rowId;
        const category = event.detail.value;
        
        // Only process for Total Loss Coverage (Package__c records, not Package_Term__c)
        if (this.isFromPackageTerm) {
            // For Package_Term__c, just update category normally
            this.tableRows = this.tableRows.map(row => {
                if (row.id === rowId) {
                    return { ...row, category: category };
                }
                return row;
            });
            return;
        }
        
        // For Total Loss Coverage: Find matching Option by Category name
        this.tableRows = this.tableRows.map(row => {
            if (row.id === rowId) {
                let updatedRow = { ...row, category: category, errorMessage: null };
                
                if (category) {
                    // Find Option record where Name matches the Category
                    const matchingOption = this.options.find(opt => 
                        opt.Name && opt.Name.toLowerCase().trim() === category.toLowerCase().trim()
                    );
                    
                    if (matchingOption) {
                        updatedRow.optionId = matchingOption.Id;
                        updatedRow.errorMessage = null;
                    } else {
                        updatedRow.optionId = null;
                        updatedRow.errorMessage = `No Option record found matching Category "${category}"`;
                    }
                } else {
                    updatedRow.optionId = null;
                    updatedRow.errorMessage = null;
                }
                
                return updatedRow;
            }
            return row;
        });
    }

    handleMinimumValueChange(event) {
        const rowId = event.currentTarget.dataset.rowId;
        const minimumValue = event.detail.value;
        this.tableRows = this.tableRows.map(row => {
            if (row.id === rowId) {
                return { ...row, minimumValue: minimumValue ? parseFloat(minimumValue) : null };
            }
            return row;
        });
    }

    handleMaximumValueChange(event) {
        const rowId = event.currentTarget.dataset.rowId;
        const maximumValue = event.detail.value;
        this.tableRows = this.tableRows.map(row => {
            if (row.id === rowId) {
                return { ...row, maximumValue: maximumValue ? parseFloat(maximumValue) : null };
            }
            return row;
        });
    }

    handlePriceChange(event) {
        const rowId = event.currentTarget.dataset.rowId;
        const price = event.detail.value;
        this.tableRows = this.tableRows.map(row => {
            if (row.id === rowId) {
                return { ...row, price: price ? parseFloat(price) : null };
            }
            return row;
        });
    }

    handleInclusionTextChange(event) {
        const rowId = event.currentTarget.dataset.rowId;
        const inclusionText = event.target.value;
        this.tableRows = this.tableRows.map(row => {
            if (row.id === rowId) {
                return { ...row, inclusionText: inclusionText || null };
            }
            return row;
        });
    }

    handleExclusionTextChange(event) {
        const rowId = event.currentTarget.dataset.rowId;
        const exclusionText = event.target.value;
        this.tableRows = this.tableRows.map(row => {
            if (row.id === rowId) {
                return { ...row, exclusionText: exclusionText || null };
            }
            return row;
        });
    }

    validateRows() {
        if (this.tableRows.length === 0) {
            return 'Please add at least one row';
        }

        const isIncludedOptions = this.currentView === 'includedOptionsTable';

        for (let i = 0; i < this.tableRows.length; i++) {
            const row = this.tableRows[i];
            const serialNumber = row.serialNumber || (i + 1);
            
            // Check for error messages (for Total Loss Coverage - Category matching errors)
            if (row.errorMessage) {
                return `Row ${serialNumber}: ${row.errorMessage}`;
            }
            
            // For Total Loss Coverage (Package__c, not Package_Term__c), Category is required and Option must be auto-matched
            if (!this.isFromPackageTerm && !isIncludedOptions) {
                if (!row.category || row.category === '' || row.category === null) {
                    return `Row ${serialNumber}: Category is required`;
                }
                
                if (!row.optionId || row.optionId === '' || row.optionId === null || row.optionId === undefined) {
                    return `Row ${serialNumber}: No Option record found matching Category "${row.category}". Please select a valid Category.`;
                }
            }
            
            // For Package_Term__c or Included Options, Option is required
            if (this.isFromPackageTerm || isIncludedOptions) {
                if (!row.optionId || row.optionId === '' || row.optionId === null || row.optionId === undefined) {
                    return `Row ${serialNumber}: Option is required`;
                }
            }
            
            // Additional options validation
            if (!isIncludedOptions) {
                if (row.price === null || row.price === undefined || row.price < 0) {
                    return `Row ${serialNumber}: Price must be greater than or equal to 0`;
                }

                // For Package__c (not Package_Term__c), validate min/max values
                if (!this.isFromPackageTerm) {
                    if (row.minimumValue !== null && row.minimumValue !== undefined && 
                        row.maximumValue !== null && row.maximumValue !== undefined &&
                        row.minimumValue > row.maximumValue) {
                        return `Row ${serialNumber}: Minimum Value cannot be greater than Maximum Value`;
                    }
                }
            }
        }

        return null;
    }

    async handleSave() {
        const validationError = this.validateRows();
        if (validationError) {
            this.showToast('Error', validationError, 'error');
            return;
        }

        // Show confirmation dialog
        const isIncludedOptions = this.currentView === 'includedOptionsTable';
        const optionType = isIncludedOptions ? 'Included' : 'Additional';
        const rowCount = this.tableRows.length;
        const confirmMessage = `Are you sure you want to save ${rowCount} ${optionType} ${rowCount === 1 ? 'Option' : 'Options'}?`;
        
        if (!confirm(confirmMessage)) {
            return;
        }

        this.isSaving = true;
        
        try {
            const currentRows = [...this.tableRows];
            const isIncludedOptions = this.currentView === 'includedOptionsTable';
            
            const rowsToSave = currentRows.map((row) => {
                let optionIdValue = null;
                if (row.optionId !== null && row.optionId !== undefined && row.optionId !== '') {
                    optionIdValue = String(row.optionId);
                }
                
                if (isIncludedOptions) {
                    return {
                        optionId: optionIdValue,
                        inclusionText: row.inclusionText || null,
                        exclusionText: row.exclusionText || null
                    };
                } else {
                    // Additional options
                    if (this.isFromPackageTerm) {
                        // For Package_Term__c records
                        return {
                            optionId: optionIdValue,
                            packageTermId: row.packageTermId || null,
                            inclusionText: row.inclusionText || null,
                            exclusionText: row.exclusionText || null,
                            price: row.price || null
                        };
                    } else {
                        // For Package__c records (Total Loss Coverage)
                        return {
                            optionId: optionIdValue,
                            category: row.category || null,
                            minimumValue: row.minimumValue || null,
                            maximumValue: row.maximumValue || null,
                            price: row.price || null
                        };
                    }
                }
            });

            const rowsJson = JSON.stringify(rowsToSave);

            const result = await createPackageOptions({ 
                recordId: this.recordId, 
                rowsJson: rowsJson,
                isIncluded: isIncludedOptions
            });

            if (result.startsWith('Success')) {
                this.showToast('Success', result, 'success');
                
                // Close the flow modal
                setTimeout(() => {
                    const finishEvent = new FlowNavigationFinishEvent();
                    this.dispatchEvent(finishEvent);
                }, 1000);
            } else {
                this.showToast('Error', result, 'error');
            }
        } catch (error) {
            this.showToast('Error', error.body?.message || 'An error occurred while saving', 'error');
        } finally {
            this.isSaving = false;
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

    handleBack() {
        // Don't allow going back to buttons - keep on table view
        // If needed, you could navigate away or close the flow instead
        // For now, we'll just keep the current view
    }
}