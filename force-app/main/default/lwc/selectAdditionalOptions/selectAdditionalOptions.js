import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { FlowNavigationFinishEvent } from 'lightning/flowSupport';
import getPackageDetails from '@salesforce/apex/SelectAdditionalOptionsController.getPackageDetails';
import saveDealerPackageOptionsSimple from '@salesforce/apex/SelectAdditionalOptionsController.saveDealerPackageOptionsSimple';

export default class SelectAdditionalOptions extends LightningElement {
    @api recordId; // Dealer Package record ID passed from record pages
    @api dealerPackageId; // Dealer Package record ID passed from Flows or other contexts
    @track packageData;
    
    // Flow navigation properties
    @api availableActions = [];
    @api flowNavigation;
    @track isLoading = false;
    @track errorMessage;
    @track selectedOptions = new Set(); // Track selected option IDs
    @track packageDataWithDiscounts; // Package data with discount fields included
    @track bulkDiscountType = '$'; // Bulk discount type
    @track bulkDiscountValue = '0'; // Bulk discount value
    @track isSaving = false; // Track save operation status
    @track discountTypeOptions = [
        { label: '$ (Fixed Amount)', value: '$' },
        { label: '% (Percentage)', value: '%' }
    ];

    connectedCallback() {
        const packageId = this.recordId || this.dealerPackageId;
        console.log('🏢 SelectAdditionalOptions component connected with recordId:', this.recordId, 'dealerPackageId:', this.dealerPackageId);
        
        if (packageId) {
            this.loadPackageDetails();
        } else {
            this.errorMessage = 'No dealer package record ID provided. Please provide either recordId or dealerPackageId.';
            console.error('❌ No dealer package ID provided to SelectAdditionalOptions component');
        }
    }

    /**
     * Load package details from Apex controller
     */
    async loadPackageDetails() {
        this.isLoading = true;
        this.errorMessage = null;
        
        try {
            const packageId = this.recordId || this.dealerPackageId;
            console.log('🔍 Loading package details for packageId:', packageId);
            
            const result = await getPackageDetails({ dealerPackageId: packageId });
            
            if (result.success) {
                this.packageData = result.data;
                console.log('✅ Package data loaded successfully:', this.packageData);
                
                // Initialize selected options Set and create discount-enabled data
                this.selectedOptions = new Set();
                this.createPackageDataWithDiscounts();
                
                this.showToast('Success', 'Package details loaded successfully', 'success');
            } else {
                this.errorMessage = result.message || 'Failed to load package details.';
                console.error('❌ Failed to load package details:', result.message);
                this.showToast('Error', result.message || 'Failed to load package details', 'error');
            }
        } catch (error) {
            this.errorMessage = 'An unexpected error occurred while loading package details.';
            console.error('❌ Error loading package details:', error);
            this.showToast('Error', 'An unexpected error occurred while loading package details', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Handle option selection change
     */
    handleOptionChange(event) {
        try {
            console.log('📋 handleOptionChange called with event:', event);
            
            const checkbox = event.target;
            const optionId = checkbox.dataset.optionId;
            const isSelected = checkbox.checked;
            
            console.log('📋 Option changed:', { 
                optionId, 
                isSelected,
                checkboxName: checkbox.name
            });
            
            if (!optionId) {
                console.error('❌ Missing option ID from event');
                return;
            }
            
            // Find and update the option
            const option = this.findOptionById(null, optionId);
            if (option) {
                option.isSelected = isSelected;
                
                // Update the selected options Set
                if (isSelected) {
                    this.selectedOptions.add(optionId);
                    console.log('✅ Added option to selection:', optionId);
                } else {
                    this.selectedOptions.delete(optionId);
                    console.log('✅ Removed option from selection:', optionId);
                }
                
                // Force reactivity
                this.selectedOptions = new Set(this.selectedOptions);
                
                console.log('✅ Updated selected options:', Array.from(this.selectedOptions));
                
                this.showToast('Success', `Option ${isSelected ? 'selected' : 'deselected'} successfully`, 'success');
            } else {
                console.error('❌ Option not found:', optionId);
            }
            
        } catch (error) {
            console.error('❌ Error handling option change:', error);
            this.showToast('Error', 'An error occurred while updating your selection', 'error');
        }
    }

    /**
     * Create package data with discount fields included
     */
    createPackageDataWithDiscounts() {
        console.log('🔧 Creating package data with discounts...');
        
        if (!this.packageData || !this.packageData.packageTerms) {
            console.log('❌ No package data available');
            return;
        }
        
        // Deep clone the package data and add discount fields
        this.packageDataWithDiscounts = JSON.parse(JSON.stringify(this.packageData));
        
        console.log(`📊 Found ${this.packageDataWithDiscounts.packageTerms.length} terms`);
        
        this.packageDataWithDiscounts.packageTerms.forEach(term => {
            console.log(`📋 Processing term ${term.id} (${term.name})`);
            
            if (term.packageOptions) {
                console.log(`🎯 Found ${term.packageOptions.length} options in term ${term.id}`);
                
                term.packageOptions.forEach(option => {
                    console.log(`💰 Adding discount fields to option ${option.id} (${option.name})`);
                    
                    // Add discount fields to the cloned option
                    option.discountType = '$'; // Default to fixed amount
                    option.discountValue = '0';
                    option.finalPrice = option.price; // Initialize with base price
                    option.finalPriceDisplay = option.priceDisplay;
                    option.isSelected = false; // Initialize selection state
                    
                    console.log(`✅ Added discount fields to ${option.name} (${option.id}):`, {
                        basePrice: option.price,
                        discountType: option.discountType,
                        discountValue: option.discountValue,
                        finalPrice: option.finalPrice
                    });
                });
            } else {
                console.log(`⚠️ No package options found in term ${term.id}`);
            }
        });
        
        console.log('🎉 Package data with discounts created successfully');
    }

    /**
     * Handle discount type change
     */
    handleDiscountTypeChange(event) {
        try {
            const discountType = event.detail.value;
            const optionId = event.target.dataset.optionId;
            
            console.log('💰 Discount type changed:', { optionId, discountType });
            
            // Find and update the option directly
            const option = this.findOptionById(null, optionId);
            if (option) {
                option.discountType = discountType;
                this.calculateFinalPrice(option);
                console.log('✅ Updated discount type successfully');
            } else {
                console.error('❌ Option not found:', optionId);
            }
            
        } catch (error) {
            console.error('❌ Error handling discount type change:', error);
            this.showToast('Error', 'An error occurred while updating discount type', 'error');
        }
    }

    /**
     * Handle discount value change
     */
    handleDiscountValueChange(event) {
        try {
            const discountValue = event.detail.value;
            const optionId = event.target.dataset.optionId;
            
            console.log('💰 Discount value changed:', { optionId, discountValue });
            
            // Find and update the option directly
            const option = this.findOptionById(null, optionId);
            if (option) {
                option.discountValue = discountValue || '0';
                this.calculateFinalPrice(option);
                console.log('✅ Updated discount value successfully');
            } else {
                console.error('❌ Option not found:', optionId);
            }
            
        } catch (error) {
            console.error('❌ Error handling discount value change:', error);
            this.showToast('Error', 'An error occurred while updating discount value', 'error');
        }
    }

    /**
     * Find option by term and option ID
     */
    findOptionById(termId, optionId) {
        if (!this.packageDataWithDiscounts || !this.packageDataWithDiscounts.packageTerms) {
            console.log('❌ No package data with discounts available');
            return null;
        }
        
        console.log(`🔍 Searching for option ${optionId} in term ${termId}`);
        
        for (const term of this.packageDataWithDiscounts.packageTerms) {
            if (term.packageOptions) {
                console.log(`📋 Checking term ${term.id} with ${term.packageOptions.length} options`);
                
                // If termId is null, search across all terms for the optionId
                if (termId === null) {
                    const option = term.packageOptions.find(option => option.id === optionId);
                    if (option) {
                        console.log(`✅ Found option ${optionId} in term ${term.id}`);
                        return option;
                    }
                } else if (term.id === termId) {
                    const option = term.packageOptions.find(option => option.id === optionId);
                    if (option) {
                        console.log(`✅ Found option ${optionId} in specified term ${termId}`);
                        return option;
                    }
                }
            }
        }
        
        console.log(`❌ Option ${optionId} not found in any term`);
        return null;
    }

    /**
     * Calculate final price based on discount type and value
     */
    calculateFinalPrice(option) {
        try {
            const basePrice = parseFloat(option.price) || 0;
            const discountValue = parseFloat(option.discountValue) || 0;
            const discountType = option.discountType || '$';
            
            let finalPrice = basePrice;
            
            if (discountType === '$') {
                // Fixed amount discount
                finalPrice = Math.max(0, basePrice - discountValue);
            } else if (discountType === '%') {
                // Percentage discount
                const discountAmount = (basePrice * discountValue) / 100;
                finalPrice = Math.max(0, basePrice - discountAmount);
            }
            
            // Update the option with calculated values
            option.finalPrice = finalPrice;
            option.finalPriceDisplay = `$${finalPrice.toFixed(2)}`;
            
            console.log(`💰 Final price calculated for ${option.name}:`, {
                basePrice,
                discountType,
                discountValue,
                finalPrice,
                finalPriceDisplay: option.finalPriceDisplay
            });
            
        } catch (error) {
            console.error('❌ Error calculating final price:', error);
            option.finalPrice = option.price;
            option.finalPriceDisplay = option.priceDisplay;
        }
    }


    /**
     * Get count of selected options
     */
    get selectedOptionsCount() {
        return this.selectedOptions.size;
    }

    /**
     * Check if bulk discount button should be disabled
     */
    get isBulkDiscountDisabled() {
        return this.selectedOptionsCount === 0 || !this.bulkDiscountValue || this.bulkDiscountValue === '0';
    }

    /**
     * Check if save button should be disabled
     */
    get isSaveButtonDisabled() {
        return this.selectedOptionsCount === 0 || this.isSaving;
    }

    /**
     * Check if all options are selected
     */
    get isAllSelected() {
        if (!this.packageDataWithDiscounts || !this.packageDataWithDiscounts.packageTerms) {
            console.log('🔍 isAllSelected: No package data available');
            return false;
        }
        
        let totalOptions = 0;
        this.packageDataWithDiscounts.packageTerms.forEach(term => {
            if (term.packageOptions) {
                totalOptions += term.packageOptions.length;
            }
        });
        
        const isAllSelected = totalOptions > 0 && this.selectedOptionsCount === totalOptions;
        console.log('🔍 isAllSelected check:', {
            totalOptions,
            selectedOptionsCount: this.selectedOptionsCount,
            isAllSelected
        });
        
        return isAllSelected;
    }

    /**
     * Get total number of available options
     */
    get totalOptionsCount() {
        if (!this.packageDataWithDiscounts || !this.packageDataWithDiscounts.packageTerms) {
            return 0;
        }
        
        let totalOptions = 0;
        this.packageDataWithDiscounts.packageTerms.forEach(term => {
            if (term.packageOptions) {
                totalOptions += term.packageOptions.length;
            }
        });
        
        return totalOptions;
    }


    /**
     * Handle select all options change
     */
    handleSelectAllChange(event) {
        console.log('🚀 METHOD CALLED: handleSelectAllChange');
        try {
            console.log('🔄 Select All Change Event:', event);
            const isSelected = event.target.checked;
            console.log('🎯 Select All isSelected:', isSelected);
            
            if (isSelected) {
                // Select all options
                console.log('📋 Selecting all options...');
                this.selectedOptions.clear();
                
                if (this.packageDataWithDiscounts && this.packageDataWithDiscounts.packageTerms) {
                    console.log('📊 Found package data with terms:', this.packageDataWithDiscounts.packageTerms.length);
                    
                    this.packageDataWithDiscounts.packageTerms.forEach((term, termIndex) => {
                        console.log(`📋 Processing term ${termIndex}: ${term.id} (${term.name})`);
                        
                        if (term.packageOptions) {
                            console.log(`🎯 Term has ${term.packageOptions.length} options`);
                            
                            term.packageOptions.forEach((option, optionIndex) => {
                                console.log(`✅ Selecting option ${optionIndex}: ${option.id} (${option.name})`);
                                option.isSelected = true;
                                this.selectedOptions.add(option.id);
                            });
                        } else {
                            console.log(`⚠️ Term ${term.id} has no package options`);
                        }
                    });
                } else {
                    console.log('❌ No package data with discounts available');
                }
                
                console.log('🎉 Final selected options:', Array.from(this.selectedOptions));
                console.log('🎉 Total options count:', this.totalOptionsCount);
                
                this.showToast('Success', `All ${this.totalOptionsCount} options selected`, 'success');
            } else {
                // Deselect all options
                console.log('📋 Deselecting all options...');
                const previousCount = this.selectedOptions.size;
                console.log('📊 Previous count:', previousCount);
                
                this.selectedOptions.clear();
                
                if (this.packageDataWithDiscounts && this.packageDataWithDiscounts.packageTerms) {
                    this.packageDataWithDiscounts.packageTerms.forEach(term => {
                        if (term.packageOptions) {
                            term.packageOptions.forEach(option => {
                                option.isSelected = false;
                            });
                        }
                    });
                }
                
                console.log('🎉 All options deselected');
                this.showToast('Success', `${previousCount} options deselected`, 'success');
            }
            
            // Force reactivity
            this.selectedOptions = new Set(this.selectedOptions);
            this.packageDataWithDiscounts = JSON.parse(JSON.stringify(this.packageDataWithDiscounts));
            console.log('🔄 Forced reactivity, selected options:', Array.from(this.selectedOptions));
            console.log('🔄 Forced package data reactivity');
            
        } catch (error) {
            console.error('❌ Error handling select all change:', error);
            this.showToast('Error', 'An error occurred while selecting/deselecting options', 'error');
        }
    }

    /**
     * Handle bulk discount type change
     */
    handleBulkDiscountTypeChange(event) {
        this.bulkDiscountType = event.detail.value;
        console.log('💰 Bulk discount type changed:', this.bulkDiscountType);
    }

    /**
     * Handle bulk discount value change
     */
    handleBulkDiscountValueChange(event) {
        this.bulkDiscountValue = event.detail.value || '0';
        console.log('💰 Bulk discount value changed:', this.bulkDiscountValue);
    }

    /**
     * Apply bulk discount to all selected options
     */
    applyBulkDiscount() {
        try {
            if (this.selectedOptions.size === 0) {
                this.showToast('Warning', 'Please select at least one option to apply bulk discount', 'warning');
                return;
            }

            if (!this.bulkDiscountValue || this.bulkDiscountValue === '0') {
                this.showToast('Warning', 'Please enter a discount value', 'warning');
                return;
            }

            let updatedCount = 0;

            // Apply bulk discount to all selected options
            this.selectedOptions.forEach(optionId => {
                const option = this.findOptionById(null, optionId);
                if (option) {
                    // Apply bulk discount settings
                    option.discountType = this.bulkDiscountType;
                    option.discountValue = this.bulkDiscountValue;
                    this.calculateFinalPrice(option);
                    updatedCount++;
                }
            });

            this.showToast('Success', `Bulk discount applied to ${updatedCount} selected options`, 'success');
            console.log(`✅ Applied bulk discount to ${updatedCount} options`);

        } catch (error) {
            console.error('❌ Error applying bulk discount:', error);
            this.showToast('Error', 'An error occurred while applying bulk discount', 'error');
        }
    }

    /**
     * Clear bulk discount from all selected options
     */
    clearBulkDiscount() {
        try {
            if (this.selectedOptions.size === 0) {
                this.showToast('Warning', 'Please select at least one option to clear bulk discount', 'warning');
                return;
            }

            let clearedCount = 0;

            // Clear discount from all selected options
            this.selectedOptions.forEach(optionId => {
                const option = this.findOptionById(null, optionId);
                if (option) {
                    // Reset to default values
                    option.discountType = '$';
                    option.discountValue = '0';
                    this.calculateFinalPrice(option);
                    clearedCount++;
                }
            });

            // Clear bulk discount fields
            this.bulkDiscountType = '$';
            this.bulkDiscountValue = '0';

            this.showToast('Success', `Bulk discount cleared from ${clearedCount} selected options`, 'success');
            console.log(`✅ Cleared bulk discount from ${clearedCount} options`);

        } catch (error) {
            console.error('❌ Error clearing bulk discount:', error);
            this.showToast('Error', 'An error occurred while clearing bulk discount', 'error');
        }
    }

    /**
     * Save selected options to Salesforce
     */
    async saveSelections() {
        try {
            if (this.selectedOptions.size === 0) {
                this.showToast('Warning', 'Please select at least one option to save', 'warning');
                return;
            }

            this.isSaving = true;
            console.log('💾 Starting save operation...');

            // Prepare data for selected options
            const selectedOptionsData = [];
            const dealerPackageId = this.recordId || this.dealerPackageId;
            
            console.log('🔍 Component recordId:', this.recordId);
            console.log('🔍 Component dealerPackageId:', this.dealerPackageId);
            console.log('🔍 Final dealerPackageId:', dealerPackageId);

            this.selectedOptions.forEach(optionId => {
                const option = this.findOptionById(null, optionId);
                if (option) {
                    // Create a plain object (not a proxy) to ensure proper serialization
                    const optionData = {
                        packageOptionId: String(optionId), // Ensure it's a string
                        optionId: String(optionId), // Ensure it's a string
                        dealerPackageId: String(dealerPackageId), // Ensure it's a string
                        discountType: String(option.discountType || '$'), // Ensure it's a string
                        discountValue: Number(parseFloat(option.discountValue) || 0), // Ensure it's a number
                        selectionType: String('Optional'), // Ensure it's a string
                        originalPrice: Number(parseFloat(option.price) || 0) // Ensure it's a number
                    };
                    
                    // Deep clone to ensure it's a clean object
                    const cleanOptionData = JSON.parse(JSON.stringify(optionData));
                    selectedOptionsData.push(cleanOptionData);
                    
                    console.log('📦 Original option data:', JSON.stringify(optionData));
                    console.log('📦 Clean option data:', JSON.stringify(cleanOptionData));
                    console.log('📦 Option ID (Package_Option__c):', optionId);
                    console.log('📦 Dealer Package ID (Dealer_Package__c):', dealerPackageId);
                    console.log('📦 Option object:', option);
                    console.log('📦 Discount Type:', option.discountType);
                    console.log('📦 Discount Value:', option.discountValue);
                    console.log('📦 Price:', option.price);
                    console.log('📦 Clean data types:', {
                        packageOptionId: typeof cleanOptionData.packageOptionId,
                        optionId: typeof cleanOptionData.optionId,
                        dealerPackageId: typeof cleanOptionData.dealerPackageId,
                        discountType: typeof cleanOptionData.discountType,
                        discountValue: typeof cleanOptionData.discountValue,
                        selectionType: typeof cleanOptionData.selectionType,
                        originalPrice: typeof cleanOptionData.originalPrice
                    });
                } else {
                    console.error('❌ Option not found for ID:', optionId);
                }
            });

            console.log('💾 Saving data (raw):', selectedOptionsData);
            console.log('💾 Saving data (JSON):', JSON.stringify(selectedOptionsData));
            console.log('💾 Dealer Package ID:', dealerPackageId);
            console.log('💾 Selected Options Count:', selectedOptionsData.length);
            
            // Ensure the entire array is clean for Apex
            const cleanSelectedOptionsData = JSON.parse(JSON.stringify(selectedOptionsData));
            console.log('💾 Clean array for Apex:', JSON.stringify(cleanSelectedOptionsData));
            
            // Try a different approach - create separate arrays for each field
            const packageOptionIds = [];
            const optionIds = [];
            const discountTypes = [];
            const discountValues = [];
            const selectionTypes = [];
            const originalPrices = [];
            
            cleanSelectedOptionsData.forEach(option => {
                packageOptionIds.push(option.packageOptionId);
                // Use the actual optionId from the PackageOptionDTO, not the packageOptionId
                optionIds.push(option.optionId || option.packageOptionId); // Fallback to packageOptionId if optionId is missing
                discountTypes.push(option.discountType);
                discountValues.push(option.discountValue);
                selectionTypes.push(option.selectionType);
                originalPrices.push(option.originalPrice);
            });
            
            console.log('💾 Separate arrays for Apex:');
            console.log('  - Package Option IDs:', packageOptionIds);
            console.log('  - Option IDs:', optionIds);
            console.log('  - Discount Types:', discountTypes);
            console.log('  - Discount Values:', discountValues);
            console.log('  - Selection Types:', selectionTypes);
            console.log('  - Original Prices:', originalPrices);

            // Validate data before saving
            if (!dealerPackageId) {
                this.showToast('Error', 'Dealer Package ID is missing', 'error');
                console.error('❌ Dealer Package ID is missing');
                return;
            }

            if (selectedOptionsData.length === 0) {
                this.showToast('Warning', 'No valid options to save', 'warning');
                console.error('❌ No valid options to save');
                return;
            }

            // Additional validation - check if any option has missing Package Option ID
            const invalidOptions = packageOptionIds.filter(id => !id);
            if (invalidOptions.length > 0) {
                this.showToast('Error', 'Some options are missing Package Option ID', 'error');
                console.error('❌ Invalid options found:', invalidOptions);
                return;
            }

            console.log('🚀 Calling Apex with separate arrays...');
            // Call Apex method with separate arrays
            const result = await saveDealerPackageOptionsSimple({ 
                dealerPackageId: dealerPackageId,
                packageOptionIds: packageOptionIds,
                optionIds: optionIds,
                discountTypes: discountTypes,
                discountValues: discountValues,
                selectionTypes: selectionTypes,
                originalPrices: originalPrices
            });

            console.log('🔍 Raw result from Apex:', result);
            console.log('🔍 Result success:', result.success);
            console.log('🔍 Result message:', result.message);
            console.log('🔍 Result savedCount:', result.savedCount);

                    if (result.success) {
                        this.showToast('Success', `Successfully saved ${result.savedCount} options`, 'success');
                        console.log('✅ Save successful:', result);
                        
                        // Close the Flow modal automatically after successful save
                        setTimeout(() => {
                            this.closeFlowModal();
                        }, 2000); // Wait 2 seconds to show the success message
                    } else {
                        this.showToast('Error', result.message || 'Failed to save selections', 'error');
                        console.error('❌ Save failed:', result);
                    }

        } catch (error) {
            console.error('❌ Error saving selections:', error);
            this.showToast('Error', 'An unexpected error occurred while saving', 'error');
        } finally {
            this.isSaving = false;
        }
    }

    /**
     * Show toast notification
     */
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }

    /**
     * Close Flow modal
     */
    closeFlowModal() {
        try {
            console.log('🔄 Attempting to close Flow modal...');
            
            // Method 1: Use FlowNavigationFinishEvent (most reliable for Flow screens)
            const finishEvent = new FlowNavigationFinishEvent();
            this.dispatchEvent(finishEvent);
            console.log('✅ FlowNavigationFinishEvent dispatched');
            
        } catch (error) {
            console.error('❌ Error closing Flow modal:', error);
            
            // Method 2: Fallback - try custom events
            try {
                const flowFinishEvent = new CustomEvent('flowfinish', {
                    detail: {
                        outcome: 'FINISH'
                    }
                });
                this.dispatchEvent(flowFinishEvent);
                console.log('✅ Custom flowfinish event dispatched');
                
            } catch (fallbackError) {
                console.error('❌ Fallback method also failed:', fallbackError);
                
                // Method 3: Final fallback
                const closeEvent = new CustomEvent('flowclose');
                this.dispatchEvent(closeEvent);
                console.log('✅ Generic flowclose event dispatched');
            }
        }
    }

    /**
     * Handle Flow navigation actions
     */
    handleFlowNavigation(event) {
        console.log('🔄 Flow navigation event received:', event);
        if (event.detail && event.detail.action === 'FINISH') {
            console.log('✅ Flow finish action received');
        }
    }

    /**
     * Refresh the package details
     */
    @api
    refresh() {
        console.log('🔄 Refreshing package details...');
        this.loadPackageDetails();
    }
}