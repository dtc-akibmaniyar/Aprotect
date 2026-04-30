import { LightningElement, track, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getAdminDealerPackageOptions from '@salesforce/apex/DealerPortalMarkupController.getAdminDealerPackageOptions';
import updateOptionMarkup from '@salesforce/apex/DealerPortalMarkupController.updateOptionMarkup';
import updateAllOptionMarkups from '@salesforce/apex/DealerPortalMarkupController.updateAllOptionMarkups';
import updateSpecificOptionMarkups from '@salesforce/apex/DealerPortalMarkupController.updateSpecificOptionMarkups';

export default class DealerPortalAdminAdditionalOptions extends LightningElement {
    @track defaultMarkup = 0;
    @track defaultMarkupType = '$';
    @track isDefaultDollar = true;
    @track isDefaultNone = false;
    @track isDefaultPercent = false;
    @track dealerPackages = [];
    @track isLoading = true;
    @track error;
    
    // Options for markup type picklist
    markupTypeOptions = [
        { label: 'None', value: '' },
        { label: '$', value: '$' },
        { label: '%', value: '%' }
    ];
    
    // Section visibility state - dynamic based on packages, terms, and categories
    @track packageVisibility = {};
    @track termVisibility = {};
    @track categoryVisibility = {};
    
    
    // Wire method to get dealer package options
    wiredDealerPackageOptionsResult;
    
    connectedCallback() {
        this.loadDealerPackageOptions();
    }
    
    async loadDealerPackageOptions() {
        try {
            this.isLoading = true;
            console.log('🔍 ===== loadDealerPackageOptions START =====');
            
            const result = await getAdminDealerPackageOptions({ timestamp: Date.now() });
            
            console.log('🔍 ===== loadDealerPackageOptions RESULT =====');
            console.log('🔍 Result data:', result);
            
            if (result) {
            console.log('🔍 Raw Apex data received:', JSON.stringify(result, null, 2));
            console.log('🔍 Number of packages from Apex:', result.length);
            
            // Display debug info if available
            if (result.length > 0 && result[0].debugInfo) {
                console.log('🔍 APEX DEBUG INFO:', result[0].debugInfo);
            }
            
            // Log each package from Apex
            result.forEach((pkg, index) => {
                console.log('🔍 Package ' + index + ':', {
                    Id: pkg.Id,
                    Name: pkg.Name,
                    PackageName: pkg.PackageName,
                    recordType: pkg.recordType,
                    termsCount: pkg.terms ? pkg.terms.length : 0,
                    terms: pkg.terms
                });
                
                if (pkg.terms) {
                    pkg.terms.forEach((term, termIndex) => {
                        console.log('🔍   Term ' + termIndex + ':', {
                            Id: term.Id,
                            termName: term.termName,
                            optionsCount: term.options ? term.options.length : 0,
                            options: term.options
                        });
                        
                        if (term.options) {
                            term.options.forEach((option, optionIndex) => {
                                console.log('🔍     Option ' + optionIndex + ':', {
                                    Id: option.Id,
                                    optionName: option.optionName,
                                    netCost: option.netCost,
                                    dealerMarkup: option.dealerMarkup,
                                    markupType: option.markupType
                                });
                            });
                        }
                    });
                }
            });
            
            // Initialize term markup property for each term and dealer markup for each option
            this.dealerPackages = result.map(pkg => ({
                ...pkg,
                terms: pkg.terms ? pkg.terms.map(term => ({
                    ...term,
                    termMarkup: '0', // Initialize term markup to 0
                    options: term.options ? term.options.map(option => ({
                        ...option,
                        dealerMarkup: option.dealerMarkup != null ? String(option.dealerMarkup) : '0', // Ensure dealer markup is properly initialized
                        markupType: String(option.markupType || ''), // Force markupType to be a string (like dealerPortalAdminMarkup)
                        isDollar: (option.markupType || '') === '$', // Add isDollar property for template conditional rendering
                        isNone: (option.markupType || '') === '', // Add isNone property for select
                        isPercent: (option.markupType || '') === '%' // Add isPercent property for select
                    })) : []
                })) : [],
                categories: pkg.categories ? pkg.categories.map(category => ({
                    ...category,
                    options: category.options ? category.options.map(option => ({
                        ...option,
                        dealerMarkup: option.dealerMarkup != null ? String(option.dealerMarkup) : '0', // Ensure dealer markup is properly initialized
                        markupType: String(option.markupType || ''), // Force markupType to be a string (like dealerPortalAdminMarkup)
                        isDollar: (option.markupType || '') === '$', // Add isDollar property for template conditional rendering
                        isNone: (option.markupType || '') === '', // Add isNone property for select
                        isPercent: (option.markupType || '') === '%' // Add isPercent property for select
                    })) : []
                })) : []
            }));
            
            console.log('🔍 Processed dealer packages:', this.dealerPackages);
            console.log('🔍 Number of processed packages:', this.dealerPackages.length);
            
            // Initialize visibility - all packages and terms closed by default
            this.initializeVisibility();
            console.log('🔍 Loaded dealer package options:', this.dealerPackages);
            
            // Note: Select values are set via HTML template binding value={option.markupType}
            
            // Debug: Check for duplicate packages
            const packageCountMap = new Map();
            result.forEach(pkg => {
                const key = pkg.Id + '|' + pkg.PackageName;
                if (packageCountMap.has(key)) {
                    packageCountMap.set(key, packageCountMap.get(key) + 1);
                    console.warn('⚠️ DUPLICATE PACKAGE IN LWC:', pkg.PackageName, 'Count:', packageCountMap.get(key));
                } else {
                    packageCountMap.set(key, 1);
                    console.log('✅ Package in LWC:', pkg.PackageName, 'Terms:', pkg.terms ? pkg.terms.length : 0);
                }
            });
        } else {
            console.log('🔍 No data received from Apex');
        }
        } catch (error) {
            console.error('❌ Error loading dealer package options:', error);
            this.error = error.body?.message || 'Error loading dealer package options';
        } finally {
            this.isLoading = false;
        }
    }
    
    // Initialize visibility state for packages, terms, and categories
    initializeVisibility() {
        this.packageVisibility = {};
        this.termVisibility = {};
        this.categoryVisibility = {};
        
        this.dealerPackages.forEach(pkg => {
            this.packageVisibility[pkg.Id] = false;
            if (pkg.terms) {
                pkg.terms.forEach(term => {
                    this.termVisibility[term.Id] = false;
                });
            }
            if (pkg.categories) {
                pkg.categories.forEach(category => {
                    this.categoryVisibility[category.categoryName] = false;
                });
            }
        });
    }

    // Set select values programmatically after component renders
    setSelectValues() {
        // Use setTimeout to ensure DOM is fully rendered
        setTimeout(() => {
            // Set individual option markup type selects (like dealerPortalAdminMarkup)
            this.dealerPackages.forEach(pkg => {
                // Check terms (Extended Limited Warranty)
                if (pkg.terms) {
                    pkg.terms.forEach(term => {
                        if (term.options) {
                            term.options.forEach(option => {
                                const optionSelect = this.template.querySelector(`select[data-option-id="${option.Id}"]`);
                                if (optionSelect) {
                                    optionSelect.value = option.markupType || '';
                                }
                            });
                        }
                    });
                }
                
                // Check categories (Total Loss Coverage)
                if (pkg.categories) {
                    pkg.categories.forEach(category => {
                        if (category.options) {
                            category.options.forEach(option => {
                                const optionSelect = this.template.querySelector(`select[data-option-id="${option.Id}"]`);
                                if (optionSelect) {
                                    optionSelect.value = option.markupType || '';
                                }
                            });
                        }
                    });
                }
            });
        }, 100);
    }
    
    // Called after every render
    renderedCallback() {
        // Set select values after each render to ensure they're correct
        if (this.dealerPackages && this.dealerPackages.length > 0) {
            this.setSelectValues();
        }
    }

    // Toggle package visibility
    togglePackage(event) {
        const packageId = event.currentTarget.dataset.packageId;
        this.packageVisibility[packageId] = !this.packageVisibility[packageId];
        // Force reactivity
        this.packageVisibility = {...this.packageVisibility};
    }
    
    // Toggle term visibility
    toggleTerm(event) {
        const termId = event.currentTarget.dataset.termId;
        this.termVisibility[termId] = !this.termVisibility[termId];
        // Force reactivity
        this.termVisibility = {...this.termVisibility};
        
        // Set select values after term is expanded (when DOM elements are rendered)
        if (this.termVisibility[termId]) {
            setTimeout(() => {
                this.setSelectValues();
            }, 50);
        }
    }
    
    // Toggle category visibility
    toggleCategory(event) {
        const categoryName = event.currentTarget.dataset.categoryName;
        this.categoryVisibility[categoryName] = !this.categoryVisibility[categoryName];
        // Force reactivity
        this.categoryVisibility = {...this.categoryVisibility};
        
        // Set select values after category is expanded (when DOM elements are rendered)
        if (this.categoryVisibility[categoryName]) {
            setTimeout(() => {
                this.setSelectValues();
            }, 50);
        }
    }
    
    // Get toggle icon for a package
    getPackageToggleIcon(packageId) {
        return this.packageVisibility[packageId] ? 'utility:chevrondown' : 'utility:chevronright';
    }
    
    // Get toggle icon for a term
    getTermToggleIcon(termId) {
        return this.termVisibility[termId] ? 'utility:chevrondown' : 'utility:chevronright';
    }
    
    // Check if package is visible
    isPackageVisible(packageId) {
        return this.packageVisibility[packageId] || false;
    }
    
    // Check if term is visible
    isTermVisible(termId) {
        return this.termVisibility[termId] || false;
    }
    
    // Handler for default markup change
    handleDefaultMarkupChange(event) {
        this.defaultMarkup = event.target.value;
    }
    
    // Handler for default markup type change
    handleDefaultMarkupTypeChange(event) {
        this.defaultMarkupType = event.target.value;
        this.isDefaultDollar = this.defaultMarkupType === '$';
        this.isDefaultNone = this.defaultMarkupType === '';
        this.isDefaultPercent = this.defaultMarkupType === '%';
    }
    
    // Handler for individual option markup change
    handleOptionMarkupChange(event) {
        const optionId = event.target.dataset.optionId;
        const newMarkup = parseFloat(event.target.value) || 0;
        
        console.log('🔍 Option markup change - OptionId:', optionId, 'New markup:', newMarkup);
        console.log('🔍 Event target value:', event.target.value);
        console.log('🔍 Parsed markup:', newMarkup);
        
        // Find and update the option in the packages
        this.updateOptionMarkup(optionId, newMarkup);
        
        console.log('🔍 Updated local markup for option:', optionId);
    }
    
    // Handler for option markup type change
    handleOptionMarkupTypeChange(event) {
        const optionId = event.target.dataset.optionId;
        const newMarkupType = event.target.value;
        
        console.log('🔍 Option markup type change - OptionId:', optionId, 'New markup type:', newMarkupType);
        
        // Find and update the option in the packages
        this.updateOptionMarkupType(optionId, newMarkupType);
        
        console.log('🔍 Updated local markup type for option:', optionId);
    }
    
    // Handler for markup input keydown - prevent letters
    handleMarkupKeydown(event) {
        // Allow: backspace, delete, tab, escape, enter, decimal point
        if ([8, 9, 27, 13, 46, 110, 190].indexOf(event.keyCode) !== -1 ||
            // Allow: Ctrl+A, Ctrl+C, Ctrl+V, Ctrl+X
            (event.keyCode === 65 && event.ctrlKey === true) ||
            (event.keyCode === 67 && event.ctrlKey === true) ||
            (event.keyCode === 86 && event.ctrlKey === true) ||
            (event.keyCode === 88 && event.ctrlKey === true) ||
            // Allow: home, end, left, right, down, up
            (event.keyCode >= 35 && event.keyCode <= 40)) {
            return;
        }
        // Ensure that it is a number and stop the keypress
        if ((event.shiftKey || (event.keyCode < 48 || event.keyCode > 57)) && (event.keyCode < 96 || event.keyCode > 105)) {
            event.preventDefault();
        }
    }
    
    // Handler for term-level markup change
    handleTermMarkupChange(event) {
        const termId = event.target.dataset.termId;
        const newMarkup = parseFloat(event.target.value) || 0;
        
        console.log('🔍 Term markup change - TermId:', termId, 'New markup:', newMarkup);
        
        // Update the term markup in the local data
        this.updateLocalTermMarkup(termId, newMarkup);
    }
    
    // Update term markup in the packages array
    updateLocalTermMarkup(termId, markup) {
        this.dealerPackages = this.dealerPackages.map(pkg => {
            if (pkg.terms) {
                const updatedTerms = pkg.terms.map(term => {
                    if (term.Id === termId) {
                        return {
                            ...term,
                            termMarkup: String(markup)
                        };
                    }
                    return term;
                });
                
                return {
                    ...pkg,
                    terms: updatedTerms
                };
            }
            return pkg;
        });
    }
    
    // Update all options in a term
    async updateTermMarkup(event) {
        const termId = event.currentTarget.dataset.termId;
        const term = this.findTermById(termId);
        
        if (!term) {
            this.showToast('Error', 'Term not found', 'error');
            return;
        }
        
        const markup = parseFloat(term.termMarkup) || 0;
        const optionCount = term.options ? term.options.length : 0;
        
        console.log('🔍 Updating term markup - TermId:', termId, 'Markup:', markup, 'Options:', optionCount);
        console.log('🔍 Term options:', term.options);
        console.log('🔍 Option IDs to update:', term.options ? term.options.map(option => option.Id) : []);
        
        // Show confirmation dialog
        const confirmed = confirm(`Are you sure you want to update ALL ${optionCount} options in "${term.termName}" with $${markup} markup?`);
        
        if (!confirmed) {
            return;
        }
        
        try {
            this.isLoading = true;
            
            // Update all options in the term
            const optionIds = term.options ? term.options.map(option => option.Id) : [];
            const result = await updateSpecificOptionMarkups({ 
                defaultMarkup: markup,
                defaultMarkupType: term.termMarkupType || '$',
                optionIds: optionIds 
            });
            
            if (result.includes('Success')) {
                this.showToast('Success', `Successfully updated all ${optionCount} options in "${term.termName}" with $${markup} markup`, 'success');
                // Update local data for all options in the term
                this.updateLocalTermData(termId, markup);
            } else {
                this.showToast('Error', result, 'error');
            }
        } catch (error) {
            console.error('❌ Error updating term markup:', error);
            this.showToast('Error', 'Failed to update term markup', 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    // Update local term data after successful server update
    updateLocalTermData(termId, markup) {
        console.log('🔍 Updating local term data - TermId:', termId, 'Markup:', markup);
        this.dealerPackages = this.dealerPackages.map(pkg => {
            if (pkg.terms) {
                const updatedTerms = pkg.terms.map(term => {
                    if (term.Id === termId && term.options) {
                        console.log('🔍 Found term to update - Options count:', term.options.length);
                        const updatedOptions = term.options.map(option => {
                            console.log('🔍 Updating option:', option.Id, 'Old markup:', option.dealerMarkup, 'New markup:', markup);
                            return {
                                ...option,
                                dealerMarkup: String(markup),
                                totalPrice: this.calculateTotal(option.netCost, markup)
                            };
                        });
                        
                        return {
                            ...term,
                            options: updatedOptions
                        };
                    }
                    return term;
                });
                
                return {
                    ...pkg,
                    terms: updatedTerms
                };
            }
            return pkg;
        });
    }
    
    // Helper to find a term by ID across all packages
    findTermById(termId) {
        console.log('🔍 Finding term by ID:', termId);
        console.log('🔍 Available packages:', this.dealerPackages.length);
        
        for (let pkg of this.dealerPackages) {
            if (pkg.terms) {
                console.log('🔍 Package terms:', pkg.terms.length);
                const term = pkg.terms.find(t => t.Id === termId);
                if (term) {
                    console.log('🔍 Found term:', term);
                    return term;
                }
            }
        }
        console.log('🔍 Term not found');
        return null;
    }
    
    // Apply default markup to all options
    async applyDefaultMarkup() {
        // Show confirmation dialog
        const confirmed = confirm(`Are you sure you want to apply $${this.defaultMarkup} markup to ALL ${this.totalOptions} additional options? This action cannot be undone.`);
        
        if (!confirmed) {
            return;
        }
        
        try {
            this.isLoading = true;
            const result = await updateAllOptionMarkups({ defaultMarkup: this.defaultMarkup, defaultMarkupType: this.defaultMarkupType });
            
            if (result.includes('Success')) {
                // Refresh the data
                this.refreshData();
                this.showToast('Success', `Successfully updated all ${this.totalOptions} additional options with $${this.defaultMarkup} markup`, 'success');
            } else {
                this.showToast('Error', result, 'error');
            }
        } catch (error) {
            console.error('Error applying default markup:', error);
            this.showToast('Error', 'Failed to apply default markup', 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    // Update a specific option's markup
    async updateMarkup(event) {
        const optionId = event.currentTarget.dataset.optionId;
        const option = this.findOptionById(optionId);
        
        console.log('🔍 Updating markup for option:', optionId);
        console.log('🔍 Found option:', option);
        console.log('🔍 Option markup value:', option?.dealerMarkup);
        console.log('🔍 Option netCost value:', option?.netCost);
        
        if (option) {
            // Show confirmation dialog
            const confirmed = confirm(`Are you sure you want to update the markup to $${option.dealerMarkup} for "${option.optionName}"?`);
            
            if (!confirmed) {
                return;
            }
            
            try {
                this.isLoading = true;
                console.log('🔍 Calling updateOptionMarkup with:', { optionId: optionId, markup: option.dealerMarkup });
                
                const result = await updateOptionMarkup({ optionId: optionId, markup: option.dealerMarkup, markupType: option.markupType });
                
                console.log('🔍 Update result:', result);
                
                if (result === 'Success') {
                    this.showToast('Success', `Markup updated to $${option.dealerMarkup} for "${option.optionName}"`, 'success');
                    // Update the local data immediately
                    this.updateLocalOptionData(optionId, option.dealerMarkup);
                    // Debug: Log current data state
                    this.logCurrentData();
                    // Note: Not calling refreshData() to preserve accordion state
                } else {
                    this.showToast('Error', result, 'error');
                }
            } catch (error) {
                console.error('❌ Error updating option markup:', error);
                this.showToast('Error', 'Failed to update option markup', 'error');
            } finally {
                this.isLoading = false;
            }
        } else {
            console.error('❌ Option not found for ID:', optionId);
            this.showToast('Error', 'Option not found', 'error');
        }
    }
    
    // Helper to find an option by ID across all packages, terms, and categories
    findOptionById(optionId) {
        for (let pkg of this.dealerPackages) {
            // Search in terms (Extended Limited Warranty)
            if (pkg.terms) {
                for (let term of pkg.terms) {
                    if (term.options) {
                        const option = term.options.find(o => o.Id === optionId);
                        if (option) return option;
                    }
                }
            }
            
            // Search in categories (Total Loss Coverage)
            if (pkg.categories) {
                for (let category of pkg.categories) {
                    if (category.options) {
                        const option = category.options.find(o => o.Id === optionId);
                        if (option) return option;
                    }
                }
            }
        }
        return null;
    }
    
    // Update option markup in the packages array
    updateOptionMarkup(optionId, markup) {
        console.log('🔍 updateOptionMarkup called with optionId:', optionId, 'markup:', markup);
        console.log('🔍 Total packages to check:', this.dealerPackages.length);
        
        // Create a new packages array with updated option data
        this.dealerPackages = this.dealerPackages.map(pkg => {
            console.log('🔍 Checking package:', pkg.PackageName, 'has terms:', !!pkg.terms, 'has categories:', !!pkg.categories);
            
            let updatedPkg = { ...pkg };
            
            // Update options in terms (Extended Limited Warranty)
            if (pkg.terms) {
                console.log('🔍 Checking terms in package:', pkg.PackageName, 'terms count:', pkg.terms.length);
                const updatedTerms = pkg.terms.map(term => {
                    if (term.options) {
                        const updatedOptions = term.options.map(option => {
                            console.log('🔍 Checking term option:', option.Id, 'against target:', optionId, 'Match:', option.Id === optionId);
                            if (option.Id === optionId) {
                                console.log('🔍 Found term option to update:', option.optionName, 'Old markup:', option.dealerMarkup, 'New markup:', markup);
                                // Create a new option object instead of modifying the existing one
                                return {
                                    ...option,
                                    dealerMarkup: String(markup),
                                    totalPrice: this.calculateTotal(option.netCost, markup, option.markupType)
                                };
                            }
                            return option;
                        });
                        
                        return {
                            ...term,
                            options: updatedOptions
                        };
                    }
                    return term;
                });
                
                updatedPkg.terms = updatedTerms;
            }
            
            // Update options in categories (Total Loss Coverage)
            if (pkg.categories) {
                console.log('🔍 Found package with categories:', pkg.categories.length);
                const updatedCategories = pkg.categories.map(category => {
                    console.log('🔍 Checking category:', category.categoryName, 'with', category.options ? category.options.length : 0, 'options');
                    if (category.options) {
                        const updatedOptions = category.options.map(option => {
                            console.log('🔍 Checking option:', option.Id, 'against target:', optionId, 'Match:', option.Id === optionId);
                            if (option.Id === optionId) {
                                console.log('🔍 Found category option to update:', option.optionName, 'Old markup:', option.dealerMarkup, 'New markup:', markup, 'MarkupType:', option.markupType);
                                // Create a new option object instead of modifying the existing one
                                return {
                                    ...option,
                                    dealerMarkup: String(markup),
                                    totalPrice: this.calculateTotal(option.netCost, markup, option.markupType)
                                };
                            }
                            return option;
                        });
                        
                        return {
                            ...category,
                            options: updatedOptions
                        };
                    }
                    return category;
                });
                
                updatedPkg.categories = updatedCategories;
            }
            
            return updatedPkg;
        });
    }
    
    // Update option markup type in the packages array
    updateOptionMarkupType(optionId, markupType) {
        // Create a new packages array with updated option data
        this.dealerPackages = this.dealerPackages.map(pkg => {
            let updatedPkg = { ...pkg };
            
            // Update options in terms (Extended Limited Warranty)
            if (pkg.terms) {
                const updatedTerms = pkg.terms.map(term => {
                    if (term.options) {
                        const updatedOptions = term.options.map(option => {
                            if (option.Id === optionId) {
                                // Create a new option object instead of modifying the existing one
                                return {
                                    ...option,
                                    markupType: markupType,
                                    isDollar: markupType === '$',
                                    isNone: markupType === '',
                                    isPercent: markupType === '%',
                                    totalPrice: this.calculateTotal(option.netCost, option.dealerMarkup, markupType)
                                };
                            }
                            return option;
                        });
                        
                        return {
                            ...term,
                            options: updatedOptions
                        };
                    }
                    return term;
                });
                
                updatedPkg.terms = updatedTerms;
            }
            
            // Update options in categories (Total Loss Coverage)
            if (pkg.categories) {
                const updatedCategories = pkg.categories.map(category => {
                    if (category.options) {
                        const updatedOptions = category.options.map(option => {
                            if (option.Id === optionId) {
                                // Create a new option object instead of modifying the existing one
                                return {
                                    ...option,
                                    markupType: markupType,
                                    isDollar: markupType === '$',
                                    isNone: markupType === '',
                                    isPercent: markupType === '%',
                                    totalPrice: this.calculateTotal(option.netCost, option.dealerMarkup, markupType)
                                };
                            }
                            return option;
                        });
                        
                        return {
                            ...category,
                            options: updatedOptions
                        };
                    }
                    return category;
                });
                
                updatedPkg.categories = updatedCategories;
            }
            
            return updatedPkg;
        });
        
        // Update the select element value (like in dealerPortalAdminMarkup)
        setTimeout(() => {
            const optionSelect = this.template.querySelector(`select[data-option-id="${optionId}"]`);
            if (optionSelect) {
                optionSelect.value = markupType;
            }
        }, 10);
    }
    
    // Update local option data after successful server update
    updateLocalOptionData(optionId, markup) {
        console.log('🔄 Updating local data for option:', optionId, 'with markup:', markup);
        
        // Create a new packages array with updated option data
        this.dealerPackages = this.dealerPackages.map(pkg => {
            // Update options in terms (Extended Limited Warranty)
            if (pkg.terms) {
                const updatedTerms = pkg.terms.map(term => {
                    if (term.options) {
                        const updatedOptions = term.options.map(option => {
                            if (option.Id === optionId) {
                                // Create a new option object instead of modifying the existing one
                                return {
                                    ...option,
                                    dealerMarkup: String(markup),
                                    totalPrice: this.calculateTotal(option.netCost, markup)
                                };
                            }
                            return option;
                        });
                        
                        return {
                            ...term,
                            options: updatedOptions
                        };
                    }
                    return term;
                });
                
                return {
                    ...pkg,
                    terms: updatedTerms
                };
            }
            
            // Update options in categories (Total Loss Coverage)
            if (pkg.categories) {
                const updatedCategories = pkg.categories.map(category => {
                    if (category.options) {
                        const updatedOptions = category.options.map(option => {
                            if (option.Id === optionId) {
                                // Create a new option object instead of modifying the existing one
                                return {
                                    ...option,
                                    dealerMarkup: String(markup),
                                    totalPrice: this.calculateTotal(option.netCost, markup)
                                };
                            }
                            return option;
                        });
                        
                        return {
                            ...category,
                            options: updatedOptions
                        };
                    }
                    return category;
                });
                
                return {
                    ...pkg,
                    categories: updatedCategories
                };
            }
            
            return pkg;
        });
        
        console.log('✅ Updated local option data for option:', optionId);
        console.log('🔄 Forced reactivity update');
    }
    
    // Refresh data from server
    async refreshData() {
        try {
            this.isLoading = true;
            console.log('🔄 Refreshing data from server...');
            await refreshApex(this.wiredDealerPackageOptionsResult);
            console.log('✅ Data refreshed successfully');
        } catch (error) {
            console.error('❌ Error refreshing data:', error);
        } finally {
            this.isLoading = false;
        }
    }
    
    // Show toast notification
    showToast(title, message, variant) {
        // You can implement toast notifications here
        console.log(`${title}: ${message}`);
    }
    
    // Debug method to log current package data
    logCurrentData() {
        console.log('🔍 Current dealer packages data:', JSON.stringify(this.dealerPackages, null, 2));
    }
    
    // Calculate total price based on markup type
    calculateTotal(basePrice, markup, markupType) {
        const base = parseFloat(basePrice) || 0;
        const mark = parseFloat(markup) || 0;
        
        console.log('🔍 calculateTotal called with:', { basePrice, markup, markupType, base, mark });
        
        let total;
        if (markupType === '%') {
            // Percentage markup: Base + (Base * Markup / 100)
            total = base + (base * mark / 100);
            console.log('🔍 Percentage calculation:', base, '+ (', base, '*', mark, '/ 100) =', total);
        } else if (markupType === '$') {
            // Dollar markup: Base + Markup
            total = base + mark;
            console.log('🔍 Dollar calculation:', base, '+', mark, '=', total);
        } else {
            // No markup or empty: Just Base
            total = base;
            console.log('🔍 No markup calculation:', base);
        }
        
        const result = total.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
        console.log('🔍 Final result:', result);
        return result;
    }
    
    // Getter for packages grouped by record type
    get packagesByRecordType() {
        console.log('🔍 ===== packagesByRecordType getter called =====');
        console.log('🔍 Current dealerPackages:', this.dealerPackages);
        console.log('🔍 Number of dealerPackages:', this.dealerPackages.length);
        
        const grouped = {};
        
        this.dealerPackages.forEach((pkg, index) => {
            const recordType = pkg.recordType || 'Other';
            console.log('🔍 Processing package ' + index + ':', pkg.PackageName, 'with recordType:', recordType);
            
            if (!grouped[recordType]) {
                grouped[recordType] = [];
                console.log('🔍 Created new record type group:', recordType);
            }
            
            const processedTerms = pkg.terms ? pkg.terms.map(term => {
                console.log('🔍   Processing term:', term.termName, 'with', term.options ? term.options.length : 0, 'options');
                
                const processedOptions = term.options ? term.options.map(option => ({
                    Id: option.Id,
                    Name: option.Name,
                    optionName: option.optionName,
                    netCost: option.netCost || 0,
                    dealerMarkup: option.dealerMarkup != null ? String(option.dealerMarkup) : '0',
                    markupType: String(option.markupType || ''),
                    isDollar: (option.markupType || '') === '$',
                    totalPrice: this.calculateTotal(option.netCost, option.dealerMarkup != null ? option.dealerMarkup : 0, option.markupType || '')
                })) : [];
                
                return {
                    Id: term.Id,
                    Name: term.Name,
                    termName: term.termName,
                    termMarkup: term.termMarkup || '0',
                    options: processedOptions,
                    isVisible: this.termVisibility[term.Id] || false,
                    toggleIcon: this.termVisibility[term.Id] ? 'utility:chevrondown' : 'utility:chevronright'
                };
            }) : [];
            
            const processedCategories = pkg.categories ? pkg.categories.map(category => {
                console.log('🔍   Processing category:', category.categoryName, 'with', category.options ? category.options.length : 0, 'options');
                
                const processedOptions = category.options ? category.options.map(option => ({
                    Id: option.Id,
                    Name: option.Name,
                    optionName: option.optionName,
                    netCost: option.netCost || 0,
                    dealerMarkup: option.dealerMarkup != null ? String(option.dealerMarkup) : '0',
                    markupType: String(option.markupType || ''),
                    isDollar: (option.markupType || '') === '$',
                    totalPrice: this.calculateTotal(option.netCost, option.dealerMarkup != null ? option.dealerMarkup : 0, option.markupType || '')
                })) : [];
                
                return {
                    categoryName: category.categoryName,
                    options: processedOptions,
                    isVisible: this.categoryVisibility[category.categoryName] || false,
                    toggleIcon: this.categoryVisibility[category.categoryName] ? 'utility:chevrondown' : 'utility:chevronright'
                };
            }) : [];
            
            grouped[recordType].push({
                Id: pkg.Id,
                Name: pkg.Name,
                PackageName: pkg.PackageName,
                terms: processedTerms,
                categories: processedCategories,
                isVisible: this.packageVisibility[pkg.Id] || false,
                toggleIcon: this.packageVisibility[pkg.Id] ? 'utility:chevrondown' : 'utility:chevronright'
            });
        });
        
        // Convert to array and filter out empty sections
        const result = Object.keys(grouped)
            .filter(recordType => grouped[recordType].length > 0)
            .map(recordType => ({
                recordType: recordType,
                packages: grouped[recordType]
            }));
            
        console.log('🔍 Final packagesByRecordType result:', result);
        console.log('🔍 Number of record type groups:', result.length);
        result.forEach((group, index) => {
            console.log('🔍 Record type group ' + index + ':', group.recordType, 'with', group.packages.length, 'packages');
        });
        
        return result;
    }

    // Getter for packages with processed terms and options - With option details (kept for backward compatibility)
    get processedPackages() {
        return this.dealerPackages.map(pkg => {
            const processedTerms = pkg.terms ? pkg.terms.map(term => {
                const processedOptions = term.options ? term.options.map(option => ({
                    Id: option.Id,
                    Name: option.Name,
                    optionName: option.optionName,
                    netCost: option.netCost || 0,
                    dealerMarkup: option.dealerMarkup != null ? String(option.dealerMarkup) : '0',
                    markupType: String(option.markupType || ''),
                    isDollar: (option.markupType || '') === '$',
                    totalPrice: this.calculateTotal(option.netCost, option.dealerMarkup != null ? option.dealerMarkup : 0, option.markupType || '')
                })) : [];
                
                return {
                    Id: term.Id,
                    Name: term.Name,
                    termName: term.termName,
                    termMarkup: term.termMarkup || '0',
                    options: processedOptions,
                    isVisible: this.termVisibility[term.Id] || false,
                    toggleIcon: this.termVisibility[term.Id] ? 'utility:chevrondown' : 'utility:chevronright'
                };
            }) : [];
            
            return {
                Id: pkg.Id,
                Name: pkg.Name,
                PackageName: pkg.PackageName,
                terms: processedTerms,
                isVisible: this.packageVisibility[pkg.Id] || false,
                toggleIcon: this.packageVisibility[pkg.Id] ? 'utility:chevrondown' : 'utility:chevronright'
            };
        });
    }

    // Getter for total options count
    get totalOptions() {
        return this.dealerPackages.reduce((total, pkg) => {
            if (pkg.terms) {
                return total + pkg.terms.reduce((termTotal, term) => {
                    return termTotal + (term.options ? term.options.length : 0);
                }, 0);
            }
            return total;
        }, 0);
    }

    // Getter to check if no packages are available
    get noPackagesAvailable() {
        return this.dealerPackages.length === 0;
    }
    
    // Method to refresh data by updating cache version
    refreshData() {
        this.cacheVersion = Date.now();
        console.log('🔍 Cache version updated to:', this.cacheVersion);
    }
}