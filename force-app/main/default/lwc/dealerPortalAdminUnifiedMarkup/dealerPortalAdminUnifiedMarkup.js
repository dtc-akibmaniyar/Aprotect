import { LightningElement, track, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getAdminDealerPackages from '@salesforce/apex/DealerPortalMarkupController.getAdminDealerPackages';
import getAdminDealerPackageOptions from '@salesforce/apex/DealerPortalMarkupController.getAdminDealerPackageOptions';
import updateTermMarkup from '@salesforce/apex/DealerPortalMarkupController.updateTermMarkup';
import updateAllTermMarkups from '@salesforce/apex/DealerPortalMarkupController.updateAllTermMarkups';
import updateSpecificTermMarkups from '@salesforce/apex/DealerPortalMarkupController.updateSpecificTermMarkups';
import updateOptionMarkup from '@salesforce/apex/DealerPortalMarkupController.updateOptionMarkup';
import updateAllOptionMarkups from '@salesforce/apex/DealerPortalMarkupController.updateAllOptionMarkups';
import updateSpecificOptionMarkups from '@salesforce/apex/DealerPortalMarkupController.updateSpecificOptionMarkups';
import getPackageGroupsForDealer from '@salesforce/apex/DealerPortalMarkupController.getPackageGroupsForDealer';
import savePackageGroupSortOrders from '@salesforce/apex/DealerPortalMarkupController.savePackageGroupSortOrders';

export default class DealerPortalAdminUnifiedMarkup extends LightningElement {
    @track defaultTermMarkup = 0;
    @track defaultTermMarkupType = '$';
    @track defaultOptionMarkup = 0;
    @track defaultOptionMarkupType = '$';
    @track isDefaultDollar = true;
    @track isDefaultNone = false;
    @track isDefaultPercent = false;
    @track dealerPackages = [];
    @track isLoading = true;
    @track error;
    
    // Package Group Sort Order tile state
    @track showPackageGroupSort = false;
    @track packageGroups = [];
    @track pkgGroupSortLoading = false;
    @track pkgGroupSortError = null;
    @track pkgGroupSortSuccess = null;
    
    // Options for markup type picklist
    markupTypeOptions = [
        { label: 'None', value: '' },
        { label: '$', value: '$' },
        { label: '%', value: '%' }
    ];
    
    // Section visibility state
    @track packageVisibility = {};
    @track termVisibility = {};
    @track optionsVisibility = {}; // For additional options sub-accordion
    @track categoryVisibility = {}; // For Total Loss categories
    @track totalLossOptionsVisibility = {}; // For Total Loss additional options section (per package)
    
    // Wire method results
    wiredDealerPackagesResult;
    wiredDealerPackageOptionsResult;
    
    connectedCallback() {
        this.loadAllData();
    }
    
    async loadAllData() {
        try {
            this.isLoading = true;
            this.error = null;
            console.log('🔍 ===== loadAllData START =====');
            
            // Load both data sources in parallel
            let termPackagesResult, optionsPackagesResult;
            
            try {
                termPackagesResult = await getAdminDealerPackages();
                console.log('🔍 Term packages result:', termPackagesResult);
                console.log('🔍 Term packages result type:', typeof termPackagesResult);
                console.log('🔍 Term packages result is array:', Array.isArray(termPackagesResult));
                console.log('🔍 Term packages count:', termPackagesResult?.length || 0);
            } catch (termError) {
                console.error('❌ Error loading term packages:', termError);
                console.error('❌ Term error details:', JSON.stringify(termError, null, 2));
                termPackagesResult = [];
            }
            
            try {
                optionsPackagesResult = await getAdminDealerPackageOptions({ timestamp: Date.now() });
                console.log('🔍 Options packages result:', optionsPackagesResult);
                console.log('🔍 Options packages result type:', typeof optionsPackagesResult);
                console.log('🔍 Options packages result is array:', Array.isArray(optionsPackagesResult));
                console.log('🔍 Options packages count:', optionsPackagesResult?.length || 0);
            } catch (optionsError) {
                console.error('❌ Error loading options packages:', optionsError);
                console.error('❌ Options error details:', JSON.stringify(optionsError, null, 2));
                optionsPackagesResult = [];
            }
            
            // Check if results are valid arrays (even if empty)
            if (Array.isArray(termPackagesResult) && Array.isArray(optionsPackagesResult)) {
                console.log('✅ Both results are valid arrays');
                console.log('🔍 Term packages: ' + termPackagesResult.length);
                console.log('🔍 Options packages: ' + optionsPackagesResult.length);
                
                if (termPackagesResult.length === 0 && optionsPackagesResult.length === 0) {
                    console.warn('⚠️ Both arrays are empty - no packages found for current user');
                    this.error = 'No packages found. Please ensure you have a dealer association and packages are configured.';
                } else {
                    this.mergePackageData(termPackagesResult, optionsPackagesResult);
                    this.initializeVisibility();
                    console.log('✅ Data merged successfully. Total packages:', this.dealerPackages.length);
                }
            } else {
                console.error('❌ Error: Invalid data format');
                console.error('❌ Term packages is array:', Array.isArray(termPackagesResult));
                console.error('❌ Options packages is array:', Array.isArray(optionsPackagesResult));
                this.error = 'Error: Invalid data format received from server';
            }
        } catch (error) {
            console.error('❌ Unexpected error loading data:', error);
            console.error('❌ Error stack:', error.stack);
            console.error('❌ Error details:', JSON.stringify(error, Object.getOwnPropertyNames(error), 2));
            
            // Handle Apex exceptions
            if (error.body) {
                if (error.body.message) {
                    this.error = error.body.message;
                } else if (error.body.pageErrors && error.body.pageErrors.length > 0) {
                    this.error = error.body.pageErrors[0].message;
                } else if (error.body.fieldErrors) {
                    const fieldErrors = Object.values(error.body.fieldErrors);
                    if (fieldErrors.length > 0 && fieldErrors[0].length > 0) {
                        this.error = fieldErrors[0][0].message;
                    }
                } else {
                    this.error = 'Error loading package data: ' + JSON.stringify(error.body);
                }
            } else if (error.message) {
                this.error = error.message;
            } else {
                this.error = 'Error loading package data. Please check the browser console for details.';
            }
        } finally {
            this.isLoading = false;
            console.log('🔍 ===== loadAllData END =====');
        }
    }
    
    mergePackageData(termPackages, optionsPackages) {
        console.log('🔍 ===== mergePackageData START =====');
        console.log('🔍 Term packages input:', termPackages);
        console.log('🔍 Options packages input:', optionsPackages);
        console.log('🔍 Term packages count:', termPackages?.length || 0);
        console.log('🔍 Options packages count:', optionsPackages?.length || 0);
        
        if (!termPackages || !Array.isArray(termPackages)) {
            console.error('❌ termPackages is not a valid array:', termPackages);
            termPackages = [];
        }
        
        if (!optionsPackages || !Array.isArray(optionsPackages)) {
            console.error('❌ optionsPackages is not a valid array:', optionsPackages);
            optionsPackages = [];
        }
        
        // Create maps for both sources
        const termPackagesMap = new Map();
        termPackages.forEach(pkg => {
            if (pkg && pkg.Id) {
                termPackagesMap.set(pkg.Id, pkg);
                console.log('🔍 Mapped term package:', pkg.Id, pkg.PackageName || pkg.Name);
            }
        });
        
        const optionsPackagesMap = new Map();
        optionsPackages.forEach(pkg => {
            if (pkg && pkg.Id) {
                optionsPackagesMap.set(pkg.Id, pkg);
                console.log('🔍 Mapped options package:', pkg.Id, pkg.PackageName || pkg.Name);
            }
        });
        
        console.log('🔍 Term packages map size:', termPackagesMap.size);
        console.log('🔍 Options packages map size:', optionsPackagesMap.size);
        
        // Combine all unique package IDs from both sources
        const allPackageIds = new Set([
            ...Array.from(termPackagesMap.keys()),
            ...Array.from(optionsPackagesMap.keys())
        ]);
        
        console.log('🔍 Total unique package IDs:', allPackageIds.size);
        
        // Process all packages - use term package as base, fallback to options package
        this.dealerPackages = Array.from(allPackageIds).map(packageId => {
            const termPkg = termPackagesMap.get(packageId);
            const optionsPkg = optionsPackagesMap.get(packageId);
            
            // Use term package as base if available, otherwise use options package
            const basePkg = termPkg || optionsPkg;
            
            if (!basePkg) {
                console.warn('⚠️ Skipping null/undefined package for ID:', packageId);
                return null;
            }
            
            console.log('🔍 Processing package:', basePkg.Id, basePkg.PackageName || basePkg.Name, 'RecordType:', basePkg.recordType);
            const isTotalLoss = basePkg.recordType === 'Total Loss Coverage' || 
                               (basePkg.recordType && basePkg.recordType.includes('Total Loss'));
            
            // Start with base package data
            const mergedPkg = {
                ...basePkg,
                isTotalLoss: isTotalLoss,
                packageMarkup: '0',
                packageMarkupType: '$',
                isPackageDollar: true,
                terms: termPkg?.terms ? termPkg.terms.map(term => {
                    const processedTerm = {
                        ...term,
                        markupType: String(term.markupType || ''),
                        isDollar: (term.markupType || '') === '$',
                        additionalOptions: [] // Will be populated for Extended Limited Warranty
                    };
                    return processedTerm;
                }) : (basePkg.terms || []).map(term => {
                    const processedTerm = {
                        ...term,
                        markupType: String(term.markupType || ''),
                        isDollar: (term.markupType || '') === '$',
                        additionalOptions: []
                    };
                    return processedTerm;
                }),
                categories: [], // Will be populated for Total Loss
                directAdditionalOptions: [] // Will be populated for Total Loss
            };
            
            // Merge options data if available
            if (optionsPkg) {
                if (isTotalLoss) {
                    // For Total Loss: separate categories and direct options
                    mergedPkg.categories = optionsPkg.categories ? optionsPkg.categories.map(category => ({
                        ...category,
                        options: category.options ? category.options.map(option => ({
                            ...option,
                            dealerMarkup: option.dealerMarkup != null ? String(option.dealerMarkup) : '0',
                            markupType: String(option.markupType || ''),
                            isDollar: (option.markupType || '') === '$',
                            isNone: (option.markupType || '') === '',
                            isPercent: (option.markupType || '') === '%',
                            totalPrice: this.calculateTotal(option.netCost, option.dealerMarkup || 0, option.markupType || '')
                        })) : []
                    })) : [];
                    
                    // DO NOT create directAdditionalOptions for Total Loss - categories already show all options
                    // This prevents duplication. Only create if there are options NOT in categories (shouldn't happen)
                    mergedPkg.directAdditionalOptions = [];
                    
                    // Extract terms from options package if available (for Total Loss, terms may only be in options package)
                    // Note: getAdminDealerPackageOptions only returns terms that have optional options
                    // So we need to get ALL terms from getAdminDealerPackages, but if that's empty, use what we have
                    if (optionsPkg.terms && Array.isArray(optionsPkg.terms) && optionsPkg.terms.length > 0) {
                        console.log('🔍 Options package has ' + optionsPkg.terms.length + ' terms (may only be terms with optional options)');
                        // If we don't have terms from term package, use terms from options package
                        if (!termPkg || !mergedPkg.terms || mergedPkg.terms.length === 0) {
                            mergedPkg.terms = optionsPkg.terms.map(term => ({
                                ...term,
                                markupType: String(term.markupType || ''),
                                isDollar: (term.markupType || '') === '$',
                                additionalOptions: term.options ? term.options.map(option => ({
                                    ...option,
                                    dealerMarkup: option.dealerMarkup != null ? String(option.dealerMarkup) : '0',
                                    markupType: String(option.markupType || ''),
                                    isDollar: (option.markupType || '') === '$',
                                    isNone: (option.markupType || '') === '',
                                    isPercent: (option.markupType || '') === '%',
                                    totalPrice: this.calculateTotal(option.netCost, option.dealerMarkup || 0, option.markupType || '')
                                })) : []
                            }));
                            console.log('✅ Added ' + mergedPkg.terms.length + ' terms from options package for Total Loss');
                        } else {
                            console.log('🔍 Merging options into existing ' + mergedPkg.terms.length + ' terms from term package');
                            // Merge options into existing terms
                            mergedPkg.terms = mergedPkg.terms.map(term => {
                                const matchingTerm = optionsPkg.terms.find(t => t.Id === term.Id);
                                if (matchingTerm && matchingTerm.options) {
                                    return {
                                        ...term,
                                        additionalOptions: matchingTerm.options.map(option => ({
                                            ...option,
                                            dealerMarkup: option.dealerMarkup != null ? String(option.dealerMarkup) : '0',
                                            markupType: String(option.markupType || ''),
                                            isDollar: (option.markupType || '') === '$',
                                            isNone: (option.markupType || '') === '',
                                            isPercent: (option.markupType || '') === '%',
                                            totalPrice: this.calculateTotal(option.netCost, option.dealerMarkup || 0, option.markupType || '')
                                        }))
                                    };
                                }
                                return { ...term, additionalOptions: [] };
                            });
                        }
                    } else {
                        console.log('⚠️ Options package has no terms - Total Loss package may not have terms with optional options');
                        console.log('⚠️ This is expected if Total Loss packages only have categories, not terms with options');
                    }
                    
                } else {
                    // For Extended Limited Warranty: merge options into terms
                    if (optionsPkg.terms) {
                        // If we only have options package (no term package), use options package terms
                        if (!termPkg || !mergedPkg.terms || mergedPkg.terms.length === 0) {
                            mergedPkg.terms = optionsPkg.terms.map(term => ({
                                ...term,
                                markupType: String(term.markupType || ''),
                                isDollar: (term.markupType || '') === '$',
                                additionalOptions: term.options ? term.options.map(option => ({
                                    ...option,
                                    dealerMarkup: option.dealerMarkup != null ? String(option.dealerMarkup) : '0',
                                    markupType: String(option.markupType || ''),
                                    isDollar: (option.markupType || '') === '$',
                                    isNone: (option.markupType || '') === '',
                                    isPercent: (option.markupType || '') === '%',
                                    totalPrice: this.calculateTotal(option.netCost, option.dealerMarkup || 0, option.markupType || '')
                                })) : []
                            }));
                            console.log('🔍 Added terms from options package for Extended Limited Warranty:', mergedPkg.terms.length);
                        } else {
                            // Merge options into existing terms
                            mergedPkg.terms = mergedPkg.terms.map(term => {
                                const matchingTerm = optionsPkg.terms.find(t => t.Id === term.Id);
                                if (matchingTerm && matchingTerm.options) {
                                    return {
                                        ...term,
                                        additionalOptions: matchingTerm.options.map(option => ({
                                            ...option,
                                            dealerMarkup: option.dealerMarkup != null ? String(option.dealerMarkup) : '0',
                                            markupType: String(option.markupType || ''),
                                            isDollar: (option.markupType || '') === '$',
                                            isNone: (option.markupType || '') === '',
                                            isPercent: (option.markupType || '') === '%',
                                            totalPrice: this.calculateTotal(option.netCost, option.dealerMarkup || 0, option.markupType || '')
                                        }))
                                    };
                                }
                                return { ...term, additionalOptions: [] };
                            });
                        }
                    }
                }
            }
            
            return mergedPkg;
        }).filter(pkg => pkg !== null); // Remove any null entries
        
        console.log('🔍 ===== mergePackageData END =====');
        console.log('✅ Successfully merged ' + this.dealerPackages.length + ' packages');
        console.log('🔍 Final merged packages:', this.dealerPackages);
        
        // Log details of each merged package
        this.dealerPackages.forEach((pkg, index) => {
            console.log(`🔍 Package ${index + 1}:`, {
                Id: pkg.Id,
                Name: pkg.PackageName || pkg.Name,
                RecordType: pkg.recordType,
                IsTotalLoss: pkg.isTotalLoss,
                TermsCount: pkg.terms?.length || 0,
                CategoriesCount: pkg.categories?.length || 0,
                DirectOptionsCount: pkg.directAdditionalOptions?.length || 0
            });
        });
    }
    
    initializeVisibility() {
        this.packageVisibility = {};
        this.termVisibility = {};
        this.optionsVisibility = {};
        this.categoryVisibility = {};
        this.totalLossOptionsVisibility = {};
        
        this.dealerPackages.forEach(pkg => {
            this.packageVisibility[pkg.Id] = false;
            if (pkg.terms) {
                pkg.terms.forEach(term => {
                    this.termVisibility[term.Id] = false;
                    this.optionsVisibility[term.Id] = false; // For additional options sub-accordion
                });
            }
            if (pkg.categories) {
                pkg.categories.forEach(category => {
                    this.categoryVisibility[category.categoryName] = false;
                });
            }
            if (pkg.directAdditionalOptions && pkg.directAdditionalOptions.length > 0) {
                this.totalLossOptionsVisibility[pkg.Id] = false;
            }
        });
    }
    
    renderedCallback() {
        if (this.dealerPackages && this.dealerPackages.length > 0) {
            this.setSelectValues();
        }
    }
    
    setSelectValues() {
        setTimeout(() => {
            // Set default markup type selects
            const defaultTermSelect = this.template.querySelector('select[name="default-term-markup-type"]');
            if (defaultTermSelect) {
                defaultTermSelect.value = this.defaultTermMarkupType;
            }
            
            const defaultOptionSelect = this.template.querySelector('select[name="default-option-markup-type"]');
            if (defaultOptionSelect) {
                defaultOptionSelect.value = this.defaultOptionMarkupType;
            }
            
            // Set package markup type selects
            this.dealerPackages.forEach(pkg => {
                const packageSelect = this.template.querySelector(`select[data-package-id="${pkg.Id}"]`);
                if (packageSelect) {
                    packageSelect.value = pkg.packageMarkupType || '$';
                }
                
                // Set term markup type selects
                if (pkg.terms) {
                    pkg.terms.forEach(term => {
                        const termSelect = this.template.querySelector(`select[data-term-id="${term.Id}"]`);
                        if (termSelect) {
                            termSelect.value = term.markupType || '';
                        }
                        
                        // Set option markup type selects
                        if (term.additionalOptions) {
                            term.additionalOptions.forEach(option => {
                                const optionSelect = this.template.querySelector(`select[data-option-id="${option.Id}"]`);
                                if (optionSelect) {
                                    optionSelect.value = option.markupType || '';
                                }
                            });
                        }
                    });
                }
                
                // Set Total Loss direct options markup type selects
                if (pkg.directAdditionalOptions) {
                    pkg.directAdditionalOptions.forEach(option => {
                        const optionSelect = this.template.querySelector(`select[data-option-id="${option.Id}"]`);
                        if (optionSelect) {
                            optionSelect.value = option.markupType || '';
                        }
                    });
                }
            });
        }, 100);
    }
    
    // =====================================================================
    // ===== Package Group Sort Order tile handlers =====
    // =====================================================================

    async togglePackageGroupSort() {
        this.showPackageGroupSort = !this.showPackageGroupSort;
        if (this.showPackageGroupSort && this.packageGroups.length === 0) {
            await this.loadPackageGroups();
        }
    }

    async loadPackageGroups() {
        this.pkgGroupSortLoading = true;
        this.pkgGroupSortError = null;
        this.pkgGroupSortSuccess = null;
        try {
            const result = await getPackageGroupsForDealer();
            if (result && Array.isArray(result)) {
                this.packageGroups = result.map(pg => ({
                    Id: pg.Id,
                    Name: pg.Name,
                    sortOrder: pg.sortOrder,
                    currentSortOrderDisplay: pg.sortOrder != null ? String(pg.sortOrder) : '—',
                    newSortOrder: pg.sortOrder != null ? String(pg.sortOrder) : ''
                }));
            } else {
                this.packageGroups = [];
            }
        } catch (err) {
            console.error('❌ Error loading package groups:', err);
            this.pkgGroupSortError = err && err.body && err.body.message
                ? err.body.message
                : 'Error loading package groups.';
        } finally {
            this.pkgGroupSortLoading = false;
        }
    }

    handleSortOrderChange(event) {
        const id = event.target.dataset.id;
        const val = event.target.value;
        this.packageGroups = this.packageGroups.map(pg => {
            if (pg.Id === id) {
                return { ...pg, newSortOrder: val };
            }
            return pg;
        });
    }

    async savePackageGroupSortOrders() {
        this.pkgGroupSortError = null;
        this.pkgGroupSortSuccess = null;
        this.pkgGroupSortLoading = true;
        try {
            const updates = this.packageGroups.map(pg => ({
                id: pg.Id,
                sortOrder: pg.newSortOrder !== '' && pg.newSortOrder !== null
                    ? Number(pg.newSortOrder)
                    : null
            }));
            const result = await savePackageGroupSortOrders({ updatesJson: JSON.stringify(updates) });
            if (result && result.startsWith('Success')) {
                this.pkgGroupSortSuccess = result;
                // Refresh the list to show updated sort orders
                await this.loadPackageGroups();
            } else {
                this.pkgGroupSortError = result || 'Unknown error saving sort orders.';
            }
        } catch (err) {
            console.error('❌ Error saving package group sort orders:', err);
            this.pkgGroupSortError = err && err.body && err.body.message
                ? err.body.message
                : 'Error saving sort orders.';
        } finally {
            this.pkgGroupSortLoading = false;
        }
    }

    get packageGroupSortToggleIcon() {
        return this.showPackageGroupSort ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get hasPackageGroups() {
        return this.packageGroups && this.packageGroups.length > 0;
    }

    // =====================================================================
    // ===== End Package Group Sort Order handlers =====
    // =====================================================================

    // Toggle handlers
    togglePackage(event) {
        const packageId = event.currentTarget.dataset.packageId;
        this.packageVisibility[packageId] = !this.packageVisibility[packageId];
        this.packageVisibility = {...this.packageVisibility};
    }
    
    toggleTerm(event) {
        const termId = event.currentTarget.dataset.termId;
        this.termVisibility[termId] = !this.termVisibility[termId];
        this.termVisibility = {...this.termVisibility};
    }
    
    toggleOptions(event) {
        const termId = event.currentTarget.dataset.termId;
        this.optionsVisibility[termId] = !this.optionsVisibility[termId];
        this.optionsVisibility = {...this.optionsVisibility};
        
        if (this.optionsVisibility[termId]) {
            setTimeout(() => {
                this.setSelectValues();
            }, 50);
        }
    }
    
    toggleCategory(event) {
        const categoryName = event.currentTarget.dataset.categoryName;
        this.categoryVisibility[categoryName] = !this.categoryVisibility[categoryName];
        this.categoryVisibility = {...this.categoryVisibility};
    }
    
    toggleTotalLossOptions(event) {
        const packageId = event.currentTarget.dataset.packageId;
        this.totalLossOptionsVisibility[packageId] = !this.totalLossOptionsVisibility[packageId];
        this.totalLossOptionsVisibility = {...this.totalLossOptionsVisibility};
        
        if (this.totalLossOptionsVisibility[packageId]) {
            setTimeout(() => {
                this.setSelectValues();
            }, 50);
        }
    }
    
    // Getters for visibility and icons
    isPackageVisible(packageId) {
        return this.packageVisibility[packageId] || false;
    }
    
    getPackageToggleIcon(packageId) {
        return this.packageVisibility[packageId] ? 'utility:chevrondown' : 'utility:chevronright';
    }
    
    isTermVisible(termId) {
        return this.termVisibility[termId] || false;
    }
    
    getTermToggleIcon(termId) {
        return this.termVisibility[termId] ? 'utility:chevrondown' : 'utility:chevronright';
    }
    
    isOptionsVisible(termId) {
        return this.optionsVisibility[termId] || false;
    }
    
    getOptionsToggleIcon(termId) {
        return this.optionsVisibility[termId] ? 'utility:chevrondown' : 'utility:chevronright';
    }
    
    isCategoryVisible(categoryName) {
        return this.categoryVisibility[categoryName] || false;
    }
    
    getCategoryToggleIcon(categoryName) {
        return this.categoryVisibility[categoryName] ? 'utility:chevrondown' : 'utility:chevronright';
    }
    
    isTotalLossOptionsVisible(packageId) {
        return this.totalLossOptionsVisibility[packageId] || false;
    }
    
    getTotalLossOptionsToggleIcon(packageId) {
        return this.totalLossOptionsVisibility[packageId] ? 'utility:chevrondown' : 'utility:chevronright';
    }
    
    // Check if package is Total Loss
    isTotalLossPackage(pkg) {
        return pkg.recordType === 'Total Loss Coverage' || 
               (pkg.recordType && pkg.recordType.includes('Total Loss'));
    }
    
    // Handlers for default markup changes
    handleDefaultTermMarkupChange(event) {
        this.defaultTermMarkup = event.target.value;
    }
    
    handleDefaultTermMarkupTypeChange(event) {
        this.defaultTermMarkupType = event.target.value;
        this.isDefaultDollar = this.defaultTermMarkupType === '$';
        this.isDefaultNone = this.defaultTermMarkupType === '';
        this.isDefaultPercent = this.defaultTermMarkupType === '%';
    }
    
    handleDefaultOptionMarkupChange(event) {
        this.defaultOptionMarkup = event.target.value;
    }
    
    handleDefaultOptionMarkupTypeChange(event) {
        this.defaultOptionMarkupType = event.target.value;
    }
    
    // Handlers for term markup changes
    handleTermMarkupChange(event) {
        const termId = event.target.dataset.termId;
        const newMarkup = parseFloat(event.target.value) || 0;
        this.updateTermMarkup(termId, newMarkup);
    }
    
    handleTermMarkupTypeChange(event) {
        const termId = event.target.dataset.termId;
        const newMarkupType = event.target.value;
        this.updateTermMarkupType(termId, newMarkupType);
    }
    
    // Handlers for option markup changes
    handleOptionMarkupChange(event) {
        const optionId = event.target.dataset.optionId;
        const newMarkup = parseFloat(event.target.value) || 0;
        this.updateOptionMarkup(optionId, newMarkup);
    }
    
    handleOptionMarkupTypeChange(event) {
        const optionId = event.target.dataset.optionId;
        const newMarkupType = event.target.value;
        this.updateOptionMarkupType(optionId, newMarkupType);
    }
    
    // Handler for markup input keydown - prevent letters
    handleMarkupKeydown(event) {
        if ([8, 9, 27, 13, 46, 110, 190].indexOf(event.keyCode) !== -1 ||
            (event.keyCode === 65 && event.ctrlKey === true) ||
            (event.keyCode === 67 && event.ctrlKey === true) ||
            (event.keyCode === 86 && event.ctrlKey === true) ||
            (event.keyCode === 88 && event.ctrlKey === true) ||
            (event.keyCode >= 35 && event.keyCode <= 40)) {
            return;
        }
        if ((event.shiftKey || (event.keyCode < 48 || event.keyCode > 57)) && (event.keyCode < 96 || event.keyCode > 105)) {
            event.preventDefault();
        }
    }
    
    // Handler for package-level markup change
    handlePackageMarkupChange(event) {
        const packageId = event.target.dataset.packageId;
        const newMarkup = parseFloat(event.target.value) || 0;
        this.updateLocalPackageMarkup(packageId, newMarkup);
    }
    
    handlePackageMarkupTypeChange(event) {
        const packageId = event.target.dataset.packageId;
        const newMarkupType = event.target.value;
        this.updateLocalPackageMarkupType(packageId, newMarkupType);
    }
    
    // Update local state methods
    updateLocalPackageMarkup(packageId, markup) {
        this.dealerPackages = this.dealerPackages.map(pkg => {
            if (pkg.Id === packageId) {
                return { ...pkg, packageMarkup: String(markup) };
            }
            return pkg;
        });
    }
    
    updateLocalPackageMarkupType(packageId, markupType) {
        this.dealerPackages = this.dealerPackages.map(pkg => {
            if (pkg.Id === packageId) {
                return { ...pkg, packageMarkupType: markupType, isPackageDollar: markupType === '$' };
            }
            return pkg;
        });
    }
    
    updateTermMarkup(termId, markup) {
        this.dealerPackages = this.dealerPackages.map(pkg => {
            if (pkg.terms) {
                const updatedTerms = pkg.terms.map(term => {
                    if (term.Id === termId) {
                        return {
                            ...term,
                            markup: String(markup),
                            totalPrice: this.calculateTotal(term.netCost, markup, term.markupType || '')
                        };
                    }
                    return term;
                });
                return { ...pkg, terms: updatedTerms };
            }
            return pkg;
        });
    }
    
    updateTermMarkupType(termId, markupType) {
        this.dealerPackages = this.dealerPackages.map(pkg => ({
            ...pkg,
            terms: pkg.terms ? pkg.terms.map(term => {
                if (term.Id === termId) {
                    return {
                        ...term,
                        markupType: markupType,
                        isDollar: markupType === '$'
                    };
                }
                return term;
            }) : []
        }));
        
        setTimeout(() => {
            const termSelect = this.template.querySelector(`select[data-term-id="${termId}"]`);
            if (termSelect) {
                termSelect.value = markupType;
            }
        }, 10);
    }
    
    updateOptionMarkup(optionId, markup) {
        this.dealerPackages = this.dealerPackages.map(pkg => {
            let updatedPkg = { ...pkg };
            
            // Update options in terms (Extended Limited Warranty)
            if (pkg.terms) {
                updatedPkg.terms = pkg.terms.map(term => {
                    if (term.additionalOptions) {
                        const updatedOptions = term.additionalOptions.map(option => {
                            if (option.Id === optionId) {
                                return {
                                    ...option,
                                    dealerMarkup: String(markup),
                                    totalPrice: this.calculateTotal(option.netCost, markup, option.markupType)
                                };
                            }
                            return option;
                        });
                        return { ...term, additionalOptions: updatedOptions };
                    }
                    return term;
                });
            }
            
            // Update direct options (Total Loss)
            if (pkg.directAdditionalOptions) {
                updatedPkg.directAdditionalOptions = pkg.directAdditionalOptions.map(option => {
                    if (option.Id === optionId) {
                        return {
                            ...option,
                            dealerMarkup: String(markup),
                            totalPrice: this.calculateTotal(option.netCost, markup, option.markupType)
                        };
                    }
                    return option;
                });
            }
            
            return updatedPkg;
        });
    }
    
    updateOptionMarkupType(optionId, markupType) {
        this.dealerPackages = this.dealerPackages.map(pkg => {
            let updatedPkg = { ...pkg };
            
            // Update options in terms (Extended Limited Warranty)
            if (pkg.terms) {
                updatedPkg.terms = pkg.terms.map(term => {
                    if (term.additionalOptions) {
                        const updatedOptions = term.additionalOptions.map(option => {
                            if (option.Id === optionId) {
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
                        return { ...term, additionalOptions: updatedOptions };
                    }
                    return term;
                });
            }
            
            // Update direct options (Total Loss)
            if (pkg.directAdditionalOptions) {
                updatedPkg.directAdditionalOptions = pkg.directAdditionalOptions.map(option => {
                    if (option.Id === optionId) {
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
            }
            
            return updatedPkg;
        });
        
        setTimeout(() => {
            const optionSelect = this.template.querySelector(`select[data-option-id="${optionId}"]`);
            if (optionSelect) {
                optionSelect.value = markupType;
            }
        }, 10);
    }
    
    // Apex method calls - Term updates
    async updateTermMarkupApex(event) {
        const termId = event.currentTarget.dataset.termId;
        const term = this.findTermById(termId);
        
        if (!term) {
            this.showToast('Error', 'Term not found', 'error');
            return;
        }
        
        const confirmed = confirm(`Are you sure you want to update the markup to $${term.markup} for "${term.termName}"?`);
        if (!confirmed) return;
        
        try {
            this.isLoading = true;
            const result = await updateTermMarkup({ 
                termId: termId, 
                markup: parseFloat(term.markup) || 0, 
                markupType: term.markupType || '' 
            });
            
            if (result === 'Success') {
                this.showToast('Success', `Markup updated to $${term.markup} for "${term.termName}"`, 'success');
                this.updateLocalTermData(termId, term.markup, term.markupType);
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
    
    async updatePackageMarkup(event) {
        const packageId = event.currentTarget.dataset.packageId;
        const packageData = this.dealerPackages.find(pkg => pkg.Id === packageId);
        
        if (!packageData) {
            this.showToast('Error', 'Package not found', 'error');
            return;
        }
        
        const markup = parseFloat(packageData.packageMarkup) || 0;
        const termCount = packageData.terms ? packageData.terms.length : 0;
        
        const confirmed = confirm(`Are you sure you want to update ALL ${termCount} terms in "${packageData.PackageName}" with $${markup} markup?`);
        if (!confirmed) return;
        
        try {
            this.isLoading = true;
            const termIds = packageData.terms ? packageData.terms.map(term => term.Id) : [];
            const result = await updateSpecificTermMarkups({ 
                defaultMarkup: markup,
                defaultMarkupType: packageData.packageMarkupType || '$',
                termIds: termIds 
            });
            
            if (result.includes('Success')) {
                this.showToast('Success', `Successfully updated all ${termCount} terms in "${packageData.PackageName}"`, 'success');
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
    
    async applyDefaultTermMarkup() {
        const confirmed = confirm(`Are you sure you want to apply $${this.defaultTermMarkup} markup to ALL ${this.totalTerms} terms?`);
        if (!confirmed) return;
        
        try {
            this.isLoading = true;
            const result = await updateAllTermMarkups({ 
                defaultMarkup: this.defaultTermMarkup, 
                defaultMarkupType: this.defaultTermMarkupType 
            });
            
            if (result.includes('Success')) {
                this.refreshData();
                this.showToast('Success', `Successfully updated all ${this.totalTerms} terms`, 'success');
            } else {
                this.showToast('Error', result, 'error');
            }
        } catch (error) {
            console.error('Error applying default term markup:', error);
            this.showToast('Error', 'Failed to apply default term markup', 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    // Apex method calls - Option updates
    async updateOptionMarkupApex(event) {
        const optionId = event.currentTarget.dataset.optionId;
        const option = this.findOptionById(optionId);
        
        if (!option) {
            this.showToast('Error', 'Option not found', 'error');
            return;
        }
        
        const confirmed = confirm(`Are you sure you want to update the markup to $${option.dealerMarkup} for "${option.optionName}"?`);
        if (!confirmed) return;
        
        try {
            this.isLoading = true;
            const result = await updateOptionMarkup({ 
                optionId: optionId, 
                markup: parseFloat(option.dealerMarkup) || 0, 
                markupType: option.markupType 
            });
            
            if (result === 'Success') {
                this.showToast('Success', `Markup updated to $${option.dealerMarkup} for "${option.optionName}"`, 'success');
                this.updateLocalOptionData(optionId, option.dealerMarkup);
            } else {
                this.showToast('Error', result, 'error');
            }
        } catch (error) {
            console.error('❌ Error updating option markup:', error);
            this.showToast('Error', 'Failed to update option markup', 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    async updateTermOptionsMarkup(event) {
        const termId = event.currentTarget.dataset.termId;
        const term = this.findTermById(termId);
        
        if (!term || !term.additionalOptions || term.additionalOptions.length === 0) {
            this.showToast('Error', 'Term or options not found', 'error');
            return;
        }
        
        // Get markup from the input field
        const markupInput = this.template.querySelector(`input[data-term-id="${termId}"][data-markup]`);
        const markup = parseFloat(markupInput?.dataset.markup || markupInput?.value || 0);
        const optionCount = term.additionalOptions.length;
        
        const confirmed = confirm(`Are you sure you want to update ALL ${optionCount} options in "${term.termName}" with $${markup} markup?`);
        if (!confirmed) return;
        
        try {
            this.isLoading = true;
            const optionIds = term.additionalOptions.map(option => option.Id);
            const result = await updateSpecificOptionMarkups({ 
                defaultMarkup: markup,
                defaultMarkupType: '$',
                optionIds: optionIds 
            });
            
            if (result.includes('Success')) {
                this.showToast('Success', `Successfully updated all ${optionCount} options in "${term.termName}"`, 'success');
                this.updateLocalTermOptionsData(termId, markup);
            } else {
                this.showToast('Error', result, 'error');
            }
        } catch (error) {
            console.error('❌ Error updating term options markup:', error);
            this.showToast('Error', 'Failed to update term options markup', 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    async applyDefaultOptionMarkup() {
        const confirmed = confirm(`Are you sure you want to apply $${this.defaultOptionMarkup} markup to ALL ${this.totalOptions} additional options?`);
        if (!confirmed) return;
        
        try {
            this.isLoading = true;
            const result = await updateAllOptionMarkups({ 
                defaultMarkup: this.defaultOptionMarkup, 
                defaultMarkupType: this.defaultOptionMarkupType 
            });
            
            if (result.includes('Success')) {
                this.refreshData();
                this.showToast('Success', `Successfully updated all ${this.totalOptions} additional options`, 'success');
            } else {
                this.showToast('Error', result, 'error');
            }
        } catch (error) {
            console.error('Error applying default option markup:', error);
            this.showToast('Error', 'Failed to apply default option markup', 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    // Handler for term options markup change (for bulk update input)
    handleTermOptionsMarkupChange(event) {
        const termId = event.target.dataset.termId;
        const newMarkup = parseFloat(event.target.value) || 0;
        // Store markup value in dataset for use in updateTermOptionsMarkup
        event.target.dataset.markup = String(newMarkup);
    }
    
    handleTotalLossOptionsMarkupChange(event) {
        const packageId = event.target.dataset.packageId;
        const newMarkup = parseFloat(event.target.value) || 0;
        event.target.dataset.markup = newMarkup;
    }
    
    async updateTotalLossOptionsMarkup(event) {
        const packageId = event.currentTarget.dataset.packageId;
        const pkg = this.dealerPackages.find(p => p.Id === packageId);
        
        if (!pkg || !pkg.directAdditionalOptions || pkg.directAdditionalOptions.length === 0) {
            this.showToast('Error', 'Package or options not found', 'error');
            return;
        }
        
        const markupInput = this.template.querySelector(`input[data-package-id="${packageId}"][data-markup]`);
        const markup = parseFloat(markupInput?.dataset.markup || markupInput?.value || 0);
        const optionCount = pkg.directAdditionalOptions.length;
        
        const confirmed = confirm(`Are you sure you want to update ALL ${optionCount} additional options with $${markup} markup?`);
        if (!confirmed) return;
        
        try {
            this.isLoading = true;
            const optionIds = pkg.directAdditionalOptions.map(option => option.Id);
            const result = await updateSpecificOptionMarkups({ 
                defaultMarkup: markup,
                defaultMarkupType: '$',
                optionIds: optionIds 
            });
            
            if (result.includes('Success')) {
                this.showToast('Success', `Successfully updated all ${optionCount} additional options`, 'success');
                this.updateLocalTotalLossOptionsData(packageId, markup);
            } else {
                this.showToast('Error', result, 'error');
            }
        } catch (error) {
            console.error('❌ Error updating Total Loss options markup:', error);
            this.showToast('Error', 'Failed to update Total Loss options markup', 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    updateLocalTotalLossOptionsData(packageId, markup) {
        this.dealerPackages = this.dealerPackages.map(pkg => {
            if (pkg.Id === packageId && pkg.directAdditionalOptions) {
                const updatedOptions = pkg.directAdditionalOptions.map(option => ({
                    ...option,
                    dealerMarkup: String(markup),
                    totalPrice: this.calculateTotal(option.netCost, markup, option.markupType)
                }));
                return { ...pkg, directAdditionalOptions: updatedOptions };
            }
            return pkg;
        });
    }
    
    // Helper methods
    findTermById(termId) {
        for (let pkg of this.dealerPackages) {
            if (pkg.terms) {
                const term = pkg.terms.find(t => t.Id === termId);
                if (term) return term;
            }
        }
        return null;
    }
    
    findOptionById(optionId) {
        for (let pkg of this.dealerPackages) {
            // Search in term additional options (Extended Limited Warranty)
            if (pkg.terms) {
                for (let term of pkg.terms) {
                    if (term.additionalOptions) {
                        const option = term.additionalOptions.find(o => o.Id === optionId);
                        if (option) return option;
                    }
                }
            }
            
            // Search in direct additional options (Total Loss)
            if (pkg.directAdditionalOptions) {
                const option = pkg.directAdditionalOptions.find(o => o.Id === optionId);
                if (option) return option;
            }
        }
        return null;
    }
    
    updateLocalTermData(termId, markup, markupType) {
        this.dealerPackages = this.dealerPackages.map(pkg => {
            if (pkg.terms) {
                const updatedTerms = pkg.terms.map(term => {
                    if (term.Id === termId) {
                        return {
                            ...term,
                            markup: String(markup),
                            markupType: markupType || term.markupType || '',
                            totalPrice: this.calculateTotal(term.netCost, markup, markupType || term.markupType || '')
                        };
                    }
                    return term;
                });
                return { ...pkg, terms: updatedTerms };
            }
            return pkg;
        });
    }
    
    updateLocalPackageData(packageId, markup, markupType) {
        this.dealerPackages = this.dealerPackages.map(pkg => {
            if (pkg.Id === packageId && pkg.terms) {
                const updatedTerms = pkg.terms.map(term => ({
                    ...term,
                    markup: String(markup),
                    markupType: markupType || term.markupType || '',
                    totalPrice: this.calculateTotal(term.netCost, markup, markupType || term.markupType || '')
                }));
                return { ...pkg, terms: updatedTerms };
            }
            return pkg;
        });
    }
    
    updateLocalOptionData(optionId, markup) {
        this.dealerPackages = this.dealerPackages.map(pkg => {
            let updatedPkg = { ...pkg };
            
            if (pkg.terms) {
                updatedPkg.terms = pkg.terms.map(term => {
                    if (term.additionalOptions) {
                        const updatedOptions = term.additionalOptions.map(option => {
                            if (option.Id === optionId) {
                                return {
                                    ...option,
                                    dealerMarkup: String(markup),
                                    totalPrice: this.calculateTotal(option.netCost, markup, option.markupType)
                                };
                            }
                            return option;
                        });
                        return { ...term, additionalOptions: updatedOptions };
                    }
                    return term;
                });
            }
            
            if (pkg.directAdditionalOptions) {
                updatedPkg.directAdditionalOptions = pkg.directAdditionalOptions.map(option => {
                    if (option.Id === optionId) {
                        return {
                            ...option,
                            dealerMarkup: String(markup),
                            totalPrice: this.calculateTotal(option.netCost, markup, option.markupType)
                        };
                    }
                    return option;
                });
            }
            
            return updatedPkg;
        });
    }
    
    updateLocalTermOptionsData(termId, markup) {
        this.dealerPackages = this.dealerPackages.map(pkg => {
            if (pkg.terms) {
                const updatedTerms = pkg.terms.map(term => {
                    if (term.Id === termId && term.additionalOptions) {
                        const updatedOptions = term.additionalOptions.map(option => ({
                            ...option,
                            dealerMarkup: String(markup),
                            totalPrice: this.calculateTotal(option.netCost, markup, option.markupType)
                        }));
                        return { ...term, additionalOptions: updatedOptions };
                    }
                    return term;
                });
                return { ...pkg, terms: updatedTerms };
            }
            return pkg;
        });
    }
    
    async refreshData() {
        try {
            this.isLoading = true;
            await this.loadAllData();
        } catch (error) {
            console.error('❌ Error refreshing data:', error);
        } finally {
            this.isLoading = false;
        }
    }
    
    showToast(title, message, variant) {
        console.log(`${title}: ${message}`);
    }
    
    calculateTotal(basePrice, markup, markupType = '$') {
        const base = parseFloat(basePrice) || 0;
        const mark = parseFloat(markup) || 0;
        
        if (!markupType || markupType === '') {
            return base.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
        }
        
        let total;
        if (markupType === '%') {
            total = base + (base * mark / 100);
        } else {
            total = base + mark;
        }
        
        return total.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
    }
    
    // Getters
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
                markupType: term.markupType || '',
                totalPrice: this.calculateTotal(term.netCost, term.markup != null ? term.markup : 0, term.markupType || ''),
                additionalOptions: term.additionalOptions || [],
                isOptionsVisible: this.optionsVisibility[term.Id] || false,
                optionsToggleIcon: this.optionsVisibility[term.Id] ? 'utility:chevrondown' : 'utility:chevronright'
            })) : [];
            
            const processedCategories = pkg.categories ? pkg.categories.map(category => ({
                ...category,
                isVisible: this.categoryVisibility[category.categoryName] || false,
                toggleIcon: this.categoryVisibility[category.categoryName] ? 'utility:chevrondown' : 'utility:chevronright'
            })) : [];
            
            grouped[recordType].push({
                Id: pkg.Id,
                Name: pkg.Name,
                PackageName: pkg.PackageName,
                recordType: pkg.recordType,
                isTotalLoss: pkg.isTotalLoss || false,
                packageMarkup: pkg.packageMarkup || '0',
                packageMarkupType: pkg.packageMarkupType || '$',
                terms: processedTerms,
                categories: processedCategories,
                directAdditionalOptions: pkg.directAdditionalOptions || [],
                isVisible: this.packageVisibility[pkg.Id] || false,
                toggleIcon: this.packageVisibility[pkg.Id] ? 'utility:chevrondown' : 'utility:chevronright',
                isTotalLossOptionsVisible: this.totalLossOptionsVisibility[pkg.Id] || false,
                totalLossOptionsToggleIcon: this.totalLossOptionsVisibility[pkg.Id] ? 'utility:chevrondown' : 'utility:chevronright'
            });
        });
        
        return Object.keys(grouped)
            .filter(recordType => grouped[recordType].length > 0)
            .map(recordType => ({
                recordType: recordType,
                packages: grouped[recordType]
            }));
    }
    
    get totalTerms() {
        return this.dealerPackages.reduce((total, pkg) => {
            return total + (pkg.terms ? pkg.terms.length : 0);
        }, 0);
    }
    
    get totalOptions() {
        return this.dealerPackages.reduce((total, pkg) => {
            let optionCount = 0;
            
            // Count options in terms (Extended Limited Warranty)
            if (pkg.terms) {
                pkg.terms.forEach(term => {
                    if (term.additionalOptions) {
                        optionCount += term.additionalOptions.length;
                    }
                });
            }
            
            // Count direct options (Total Loss)
            if (pkg.directAdditionalOptions) {
                optionCount += pkg.directAdditionalOptions.length;
            }
            
            return total + optionCount;
        }, 0);
    }
    
    get noPackagesAvailable() {
        return this.dealerPackages.length === 0;
    }
}