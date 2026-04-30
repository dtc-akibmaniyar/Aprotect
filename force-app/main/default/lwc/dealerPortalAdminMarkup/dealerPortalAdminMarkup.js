import { LightningElement, track, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getAdminDealerPackages from '@salesforce/apex/DealerPortalMarkupController.getAdminDealerPackages';
import updateTermMarkup from '@salesforce/apex/DealerPortalMarkupController.updateTermMarkup';
import updateAllTermMarkups from '@salesforce/apex/DealerPortalMarkupController.updateAllTermMarkups';
import updateSpecificTermMarkups from '@salesforce/apex/DealerPortalMarkupController.updateSpecificTermMarkups';

export default class DealerPortalAdminMarkup extends LightningElement {
    @track defaultMarkup = 0;
    @track defaultMarkupType = '$';
    @track isDefaultDollar = true;
    @track isDefaultNone = false;
    @track isDefaultPercent = false;
    
    // Options for markup type picklist
    markupTypeOptions = [
        { label: 'None', value: '' },
        { label: '$', value: '$' },
        { label: '%', value: '%' }
    ];
    @track dealerPackages = [];
    @track isLoading = true;
    @track error;
    
    
    // Section visibility state - now dynamic based on packages
    @track packageVisibility = {};
    
    // Wire method to get dealer packages
    wiredDealerPackagesResult;
    
    @wire(getAdminDealerPackages)
    wiredDealerPackages(result) {
        this.wiredDealerPackagesResult = result;
        this.isLoading = false;
        if (result.data) {
            
            // Initialize package markup property for each package
            this.dealerPackages = result.data.map(pkg => ({
                ...pkg,
                packageMarkup: '0', // Initialize package markup to 0
                packageMarkupType: '$', // Initialize package markup type to $
                isPackageDollar: true, // Initialize package markup type to dollar
                // Initialize markup type for each term
                terms: pkg.terms ? pkg.terms.map(term => {
                    const processedTerm = {
                        ...term,
                        markupType: term.markupType || '' // Use actual value from database, default to empty string for "None"
                    };
                    
                    // Force the markupType to be a fresh string to ensure reactivity
                    processedTerm.markupType = String(processedTerm.markupType);
                    
                    // Add isDollar property for template conditional rendering
                    processedTerm.isDollar = processedTerm.markupType === '$';
                    
                    return processedTerm;
                }) : []
            }));
            // Initialize package visibility - all packages closed by default
            // No packages will be expanded initially
            
            
        } else if (result.error) {
            this.error = result.error;
            console.error('Error loading dealer packages:', result.error);
        }
    }

    renderedCallback() {
        // Set select values after each render to ensure they're correct
        if (this.dealerPackages && this.dealerPackages.length > 0) {
            this.setSelectValues();
        }
    }

    // Set select values programmatically after component renders
    setSelectValues() {
        // Use setTimeout to ensure DOM is fully rendered
        setTimeout(() => {
            // Set default markup type select
            const defaultSelect = this.template.querySelector('select[name="default-markup-type"]');
            if (defaultSelect) {
                defaultSelect.value = this.defaultMarkupType;
            }

            // Set package markup type selects
            this.dealerPackages.forEach(pkg => {
                const packageSelect = this.template.querySelector(`select[data-package-id="${pkg.Id}"]`);
                if (packageSelect) {
                    packageSelect.value = pkg.packageMarkupType || '$';
                }
            });

            // Set individual term markup type selects
            this.dealerPackages.forEach(pkg => {
                if (pkg.terms) {
                    pkg.terms.forEach(term => {
                        const termSelect = this.template.querySelector(`select[data-term-id="${term.Id}"]`);
                        if (termSelect) {
                            termSelect.value = term.markupType || '';
                        }
                    });
                }
            });
        }, 100);
    }
    
    // Toggle package visibility
    togglePackage(event) {
        const packageId = event.currentTarget.dataset.packageId;
        this.packageVisibility[packageId] = !this.packageVisibility[packageId];
        // Force reactivity
        this.packageVisibility = {...this.packageVisibility};
    }
    
    // Get toggle icon for a package
    getToggleIcon(packageId) {
        return this.packageVisibility[packageId] ? 'utility:chevrondown' : 'utility:chevronright';
    }
    
    // Check if package is visible
    isPackageVisible(packageId) {
        return this.packageVisibility[packageId] || false;
    }
    
    // Getter for package visibility map
    get packageVisibilityMap() {
        return this.packageVisibility;
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
    
    // Handler for individual markup change
    handleMarkupChange(event) {
        const termId = event.target.dataset.termId;
        const newMarkup = parseFloat(event.target.value) || 0;
        
        
        // Find and update the term in the packages
        this.updateTermMarkup(termId, newMarkup);
        
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
    
    // Handler for package-level markup change
    handlePackageMarkupChange(event) {
        const packageId = event.target.dataset.packageId;
        const newMarkup = parseFloat(event.target.value) || 0;
        
        
        // Update the package markup in the local data
        this.updateLocalPackageMarkup(packageId, newMarkup);
    }
    
    // Handler for package markup type change
    handlePackageMarkupTypeChange(event) {
        const packageId = event.target.dataset.packageId;
        const newMarkupType = event.target.value;
        
        
        // Update the package markup type in the local data
        this.updateLocalPackageMarkupType(packageId, newMarkupType);
    }
    
    // Handler for individual term markup type change
    handleMarkupTypeChange(event) {
        const termId = event.target.dataset.termId;
        const newMarkupType = event.target.value;
        
        
        // Update the markup type in the local data
        this.updateTermMarkupType(termId, newMarkupType);
    }
    
    // Update package markup in the packages array
    updateLocalPackageMarkup(packageId, markup) {
        this.dealerPackages = this.dealerPackages.map(pkg => {
            if (pkg.Id === packageId) {
                return {
                    ...pkg,
                    packageMarkup: String(markup)
                };
            }
            return pkg;
        });
    }
    
    // Update package markup type in the packages array
    updateLocalPackageMarkupType(packageId, markupType) {
        this.dealerPackages = this.dealerPackages.map(pkg => {
            if (pkg.Id === packageId) {
                return {
                    ...pkg,
                    packageMarkupType: markupType,
                    isPackageDollar: markupType === '$'
                };
            }
            return pkg;
        });
    }
    
    // Update term markup type in the packages array
    updateTermMarkupType(termId, markupType) {
        this.dealerPackages = this.dealerPackages.map(pkg => ({
            ...pkg,
            terms: pkg.terms.map(term => {
                if (term.Id === termId) {
                    return {
                        ...term,
                        markupType: markupType,
                        isDollar: markupType === '$'
                    };
                }
                return term;
            })
        }));
        
        // Update the select element value
        setTimeout(() => {
            const termSelect = this.template.querySelector(`select[data-term-id="${termId}"]`);
            if (termSelect) {
                termSelect.value = markupType;
            }
        }, 10);
    }
    
    // Update all terms in a package
    async updatePackageMarkup(event) {
        const packageId = event.currentTarget.dataset.packageId;
        const packageData = this.dealerPackages.find(pkg => pkg.Id === packageId);
        
        if (!packageData) {
            this.showToast('Error', 'Package not found', 'error');
            return;
        }
        
        const markup = parseFloat(packageData.packageMarkup) || 0;
        const termCount = packageData.terms ? packageData.terms.length : 0;
        
        
        // Show confirmation dialog
        const confirmed = confirm(`Are you sure you want to update ALL ${termCount} terms in "${packageData.PackageName}" with $${markup} markup?`);
        
        if (!confirmed) {
            return;
        }
        
        try {
            this.isLoading = true;
            
            // Update all terms in the package
            const termIds = packageData.terms ? packageData.terms.map(term => term.Id) : [];
            const result = await updateSpecificTermMarkups({ 
                defaultMarkup: markup,
                defaultMarkupType: packageData.packageMarkupType || '$',
                termIds: termIds 
            });
            
            if (result.includes('Success')) {
                this.showToast('Success', `Successfully updated all ${termCount} terms in "${packageData.PackageName}" with $${markup} markup`, 'success');
                // Update local data for all terms in the package
                this.updateLocalPackageData(packageId, markup, packageData.packageMarkupType);
            } else {
                this.showToast('Error', result, 'error');
            }
        } catch (error) {
            console.error('❌ Error updating package markup:', error);
            this.showToast('Error', 'Failed to update package markup', 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    // Update local package data after successful server update
    updateLocalPackageData(packageId, markup, markupType) {
        this.dealerPackages = this.dealerPackages.map(pkg => {
            if (pkg.Id === packageId && pkg.terms) {
                const updatedTerms = pkg.terms.map(term => ({
                    ...term,
                    markup: String(markup),
                    markupType: markupType || term.markupType || '',
                    totalPrice: this.calculateTotal(term.netCost, markup, markupType || term.markupType || '')
                }));
                
                return {
                    ...pkg,
                    terms: updatedTerms
                };
            }
            return pkg;
        });
    }
    
    // Apply default markup to all terms
    async applyDefaultMarkup() {
        // Show confirmation dialog
        const confirmed = confirm(`Are you sure you want to apply $${this.defaultMarkup} markup to ALL ${this.totalTerms} terms? This action cannot be undone.`);
        
        if (!confirmed) {
            return;
        }
        
        try {
            this.isLoading = true;
            const result = await updateAllTermMarkups({ defaultMarkup: this.defaultMarkup, defaultMarkupType: this.defaultMarkupType });
            
            if (result.includes('Success')) {
                // Refresh the data
                this.refreshData();
                this.showToast('Success', `Successfully updated all ${this.totalTerms} terms with $${this.defaultMarkup} markup`, 'success');
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
    
    // Update a specific term's markup
    async updateMarkup(event) {
        const termId = event.currentTarget.dataset.termId;
        const term = this.findTermById(termId);
        
        
        if (term) {
            // Show confirmation dialog
            const confirmed = confirm(`Are you sure you want to update the markup to $${term.markup} for "${term.termName}"?`);
            
            if (!confirmed) {
                return;
            }
            
            try {
                this.isLoading = true;
                
                const result = await updateTermMarkup({ termId: termId, markup: term.markup, markupType: term.markupType || '' });
                
                
                if (result === 'Success') {
                    this.showToast('Success', `Markup updated to $${term.markup} for "${term.termName}"`, 'success');
                    // Update the local data immediately
                    this.updateLocalTermData(termId, term.markup, term.markupType);
                    // Debug: Log current data state
                    this.logCurrentData();
                    // Note: Not calling refreshData() to preserve accordion state
                } else {
                    this.showToast('Error', result, 'error');
                }
            } catch (error) {
                console.error('❌ Error updating term markup:', error);
                this.showToast('Error', 'Failed to update term markup', 'error');
            } finally {
                this.isLoading = false;
            }
        } else {
            console.error('❌ Term not found for ID:', termId);
            this.showToast('Error', 'Term not found', 'error');
        }
    }
    
    // Helper to find a term by ID across all packages
    findTermById(termId) {
        for (let pkg of this.dealerPackages) {
            if (pkg.terms) {
                const term = pkg.terms.find(t => t.Id === termId);
                if (term) return term;
            }
        }
        return null;
    }
    
    // Update term markup in the packages array
    updateTermMarkup(termId, markup) {
        // Create a new packages array with updated term data
        this.dealerPackages = this.dealerPackages.map(pkg => {
            if (pkg.terms) {
                const updatedTerms = pkg.terms.map(term => {
                    if (term.Id === termId) {
                        // Create a new term object instead of modifying the existing one
                        return {
                            ...term,
                            markup: String(markup),
                            totalPrice: this.calculateTotal(term.netCost, markup, term.markupType || '')
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
    
    // Update local term data after successful server update
    updateLocalTermData(termId, markup, markupType) {
        
        // Create a new packages array with updated term data
        this.dealerPackages = this.dealerPackages.map(pkg => {
            if (pkg.terms) {
                const updatedTerms = pkg.terms.map(term => {
                    if (term.Id === termId) {
                        // Create a new term object instead of modifying the existing one
                        const updatedMarkupType = markupType || term.markupType || '';
                        return {
                            ...term,
                            markup: String(markup),
                            markupType: updatedMarkupType,
                            totalPrice: this.calculateTotal(term.netCost, markup, updatedMarkupType)
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
    
    // Refresh data from server
    async refreshData() {
        try {
            this.isLoading = true;
            await refreshApex(this.wiredDealerPackagesResult);
        } catch (error) {
            console.error('❌ Error refreshing data:', error);
        } finally {
            this.isLoading = false;
        }
    }
    
    // Show toast notification
    showToast(title, message, variant) {
        // You can implement toast notifications here
    }
    
    
    
    // Get markup type for a term (ensures fresh value)
    getMarkupType(term) {
        return term.markupType || '';
    }
    
    
    // Calculate total price (base + markup)
    calculateTotal(basePrice, markup, markupType = '$') {
        const base = parseFloat(basePrice) || 0;
        const mark = parseFloat(markup) || 0;
        
        // If markup type is empty, return just the base price (no markup calculation)
        if (!markupType || markupType === '') {
            return base.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
        }
        
        let total;
        if (markupType === '%') {
            // For percentage markup, calculate percentage of base price
            total = base + (base * mark / 100);
        } else {
            // For dollar markup, add directly
            total = base + mark;
        }
        
        return total.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
    }
    
    // Getter for packages grouped by record type
    get packagesByRecordType() {
        const grouped = {};
        
        this.dealerPackages.forEach(pkg => {
            const recordType = pkg.recordType || 'Other';
            
            if (!grouped[recordType]) {
                grouped[recordType] = [];
            }
            
            const processedTerms = pkg.terms ? pkg.terms.map(term => ({
                Id: term.Id,
                Name: term.Name,
                termName: term.termName,
                netCost: term.netCost || 0,
                markup: term.markup != null ? String(term.markup) : '0',
                totalPrice: this.calculateTotal(term.netCost, term.markup != null ? term.markup : 0, term.markupType || '')
            })) : [];
            
            grouped[recordType].push({
                Id: pkg.Id,
                Name: pkg.Name,
                PackageName: pkg.PackageName,
                packageMarkup: pkg.packageMarkup || '0',
                terms: processedTerms,
                isVisible: this.packageVisibility[pkg.Id] || false,
                toggleIcon: this.packageVisibility[pkg.Id] ? 'utility:chevrondown' : 'utility:chevronright'
            });
        });
        
        // Convert to array and filter out empty sections
        return Object.keys(grouped)
            .filter(recordType => grouped[recordType].length > 0)
            .map(recordType => ({
                recordType: recordType,
                packages: grouped[recordType]
            }));
    }

    // Getter for packages with processed terms and visibility info - With term details (kept for backward compatibility)
    get processedPackages() {
        return this.dealerPackages.map(pkg => {
            const processedTerms = pkg.terms ? pkg.terms.map(term => ({
                Id: term.Id,
                Name: term.Name,
                termName: term.termName,
                netCost: term.netCost || 0,
                markup: term.markup != null ? String(term.markup) : '0',
                totalPrice: this.calculateTotal(term.netCost, term.markup != null ? term.markup : 0, term.markupType || '')
            })) : [];
            
            return {
                Id: pkg.Id,
                Name: pkg.Name,
                PackageName: pkg.PackageName,
                packageMarkup: pkg.packageMarkup || '0',
                terms: processedTerms,
                isVisible: this.packageVisibility[pkg.Id] || false,
                toggleIcon: this.packageVisibility[pkg.Id] ? 'utility:chevrondown' : 'utility:chevronright'
            };
        });
    }

    // Getter for total terms count
    get totalTerms() {
        return this.dealerPackages.reduce((total, pkg) => {
            return total + (pkg.terms ? pkg.terms.length : 0);
        }, 0);
    }
}