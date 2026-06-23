import { LightningElement, track, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDealerPackages from '@salesforce/apex/DealerPortalController.getDealerPackages';
import getExistingApplicationPackage from '@salesforce/apex/DealerPortalController.getExistingApplicationPackage';
import getExistingApplicationPackageByRecordType from '@salesforce/apex/DealerPortalController.getExistingApplicationPackageByRecordType';
import getActiveApplicationPackageByRecordType from '@salesforce/apex/DealerPortalController.getActiveApplicationPackageByRecordType';
import savePackageWithActiveManagement from '@salesforce/apex/DealerPortalController.savePackageWithActiveManagement';
import createApplicationPackageFromMap from '@salesforce/apex/DealerPortalController.createApplicationPackageFromMap';
import updateApplicationPackage from '@salesforce/apex/DealerPortalController.updateApplicationPackage';
import convertQuoteToApplication from '@salesforce/apex/DealerPortalController.convertQuoteToApplication';
import getAdditionalOptions from '@salesforce/apex/DealerPortalController.getAdditionalOptions';
import getExistingAdditionalOptions from '@salesforce/apex/DealerPortalController.getExistingAdditionalOptions';
import updateAdditionalOptions from '@salesforce/apex/DealerPortalController.updateAdditionalOptions';
import updateWarrantyFieldsSelective from '@salesforce/apex/DealerPortalController.updateWarrantyFieldsSelective';
import updateVehicleFieldsSelective from '@salesforce/apex/DealerPortalController.updateVehicleFieldsSelective';
import loadVehicleData from '@salesforce/apex/DealerPortalController.loadVehicleData';
import CarImageWarranty from '@salesforce/resourceUrl/Car_Image_Warranty';

export default class DealerPortalWarranty extends LightningElement {
    @track loading = false
    @track renderKey = 0 // Used to force re-renders;
    @track price = 0.00;
    @track isPriceEditMode = false;
    @track priceOverrideInput = '';
    @track isPriceOverridden = false;
    @track priceValidationMessage = '';
    @track selectedProgram = '';
    @track selectedTerm = '4';
    @track selectedClaim = '5000';
    @track selectedAdditionalOptions = []; // Array of selected additional option IDs
    @track isPremiumVehicle = false;
    @track premiumFeeAmount = 0;
    @track modalPremiumFee = 0;
    @track vehicleConfigChangedMessage = '';
    @track availableAdditionalOptionsData = []; // Raw additional options data
    @track existingAdditionalOptions = []; // Already selected options (from Salesforce)
    @track selectedNewOptions = []; // New selections (not saved yet)
    @track optionsToRemove = []; // Existing options marked for removal
    @track testDrive = false;
    @track testDrivePrice = 729.00;
    @track errorMessage = '';
    @track showError = false;
    @track showDeclineModal = false;
    @track dealerPackages = [];
    @track dealerHasPackages = false;
    @track selectedDealerPackage = null;
    @track selectedWarrantyTerm = null;
    @track showPriceModal = false;
    @track currentPriceBreakdown = {};
    @track dealerReferenceBreakdown = {};
    @track showDealerReferencePrice = false;
    @track existingApplicationPackage = null;
    @track isExistingApplication = false;
    @track showComparisonModal = false;
    @track selectedPackagesForComparison = [];
    @track showCompareButton = false;
    @track comparisonPackages = [];
    @track showHelpModal = false;
    @track helpModalTitle = '';
    @track helpModalText = '';
    @track showWarrantyModal = false;
    @track selectedDealerPackageName = '';
    @track selectedWarrantyTermName = '';
    @track packageHasFiles = false;
    @track packageFileCount = 0;
    @track originalWarrantyData = {};
    @track warrantyChangedFields = new Set();
    @track warrantyAutoSaveTimeout;
    @track currentView = 'packageDetails';
    @track selectedPlanTypeKey = null;
    @track selectedPlanType = null;
    carImageWarranty = CarImageWarranty;
    gradientAssignments = {};
    @track vehicleData = {};
    // Deferral option state — driven by the active warranty package term
    @track deferralOption = false;
    @track vehicleIdForDeferral = '';
    @track packageTermAllowsDeferral = false;
    @track isManufacturerWarrantyExpired = false;
    otherPlanTypeKey = 'OTHER_PACKAGES';
    allDealerPackages = [];
    savedDealerPackageId = null;
    savedWarrantyTermId = null;
    @api recordId;
    @api applicationStatus;
    @api isLocked = false;
    
    // Getter for field disabled state based on lock status
    get fieldDisabled() {
        return this.isLocked;
    }
    
    // Getter for skip button label - "Next" when locked, "Skip" when not locked
    get skipButtonLabel() {
        return this.isLocked ? 'Next' : 'Decline Warranty';
    }
    
    // Getter and setter for applicationId to handle changes
    @api
    get applicationId() {
        return this._applicationId;
    }
    
    set applicationId(value) {
        if (this._applicationId !== value) {
            this._applicationId = value;
            
            // Load dealer packages when applicationId changes
            if (value) {
                this.loadDealerPackages();
            }
        }
    }
    
    connectedCallback() {
        
        // Auto-populate with saved data if available
        if (sessionStorage.getItem('warrantyData')) {
            const savedData = JSON.parse(sessionStorage.getItem('warrantyData'));
            this.selectedProgram = savedData.selectedProgram || this.selectedProgram;
            this.selectedTerm = savedData.selectedTerm || this.selectedTerm;
            this.selectedClaim = savedData.selectedClaim || this.selectedClaim;
            this.selectedDeductible = savedData.selectedDeductible || this.selectedDeductible;
            this.testDrive = savedData.testDrive || this.testDrive;
            
            this.savedDealerPackageId = savedData.selectedDealerPackageId || savedData.selectedDealerPackage?.Id || null;
            this.savedWarrantyTermId = savedData.selectedWarrantyTermId || savedData.selectedWarrantyTerm?.Id || null;
            
            // Update price based on loaded data
            this.updatePrice();
        }
        
        // Check if we have an applicationId after a short delay
        setTimeout(() => {
        }, 1000);
    }
    
    renderedCallback() {
        // Render rich text descriptions for plan type tiles and inline group headers
        const descriptionElements = this.template.querySelectorAll(
            '.package-tile__description[data-description], .plan-type-group-description[data-description]'
        );
        descriptionElements.forEach(element => {
            const htmlContent = element.getAttribute('data-description');
            if (htmlContent) {
                element.innerHTML = htmlContent;
            }
        });
    }
    
    // Method to update UI selection highlighting
    updateSelectionHighlighting() {
        if (this.selectedDealerPackage) {
            // Remove all selected classes
            this.template.querySelectorAll('.program-section, lightning-accordion-section').forEach(section => {
                section.classList.remove('selected');
            });
            
            // Add selected class to the current selection
            const selectedSection = this.template.querySelector(`[data-package="${this.selectedDealerPackage.Id}"]`) ||
                                  this.template.querySelector(`[name="${this.selectedDealerPackage.Id}"]`);
            if (selectedSection) {
                selectedSection.classList.add('selected');
            }
        }
        
        // Also update term highlighting if a term is selected
        if (this.selectedWarrantyTerm) {
            const termElement = this.template.querySelector(`[data-term="${this.selectedWarrantyTerm.Id}"]`);
            if (termElement) {
                termElement.classList.add('selected');
            }
        }
    }
    
    
    @api
    handleVehicleConfigChanged() {
        console.log('WARRANTY - Vehicle config changed, revalidating packages');
        this._previousPackageId = this.selectedDealerPackage ? this.selectedDealerPackage.Id : null;
        this._previousTermId = this.selectedWarrantyTerm ? this.selectedWarrantyTerm.Id : null;
        this._previousPackageName = this.selectedDealerPackage ? (this.selectedDealerPackage.PackageName || this.selectedDealerPackage.Name) : null;
        this._previousTermName = this.selectedWarrantyTerm ? (this.selectedWarrantyTerm.packageTermName || this.selectedWarrantyTerm.Name) : null;
        this.vehicleConfigChangedMessage = 'Vehicle details have been updated. Reloading available packages...';
        this.loadDealerPackages().then(() => { this._validatePreviousSelection(); });
    }

    _validatePreviousSelection() {
        if (!this._previousPackageId) {
            this.vehicleConfigChangedMessage = '';
            return;
        }
        const pkgExists = this.allDealerPackages && this.allDealerPackages.some(pkg => pkg.Id === this._previousPackageId);
        if (!pkgExists) {
            this.vehicleConfigChangedMessage = 'The previously selected package "' + (this._previousPackageName || '') + '" is no longer available for the updated vehicle configuration. Please select an appropriate package.';
            this.selectedDealerPackage = null;
            this.selectedWarrantyTerm = null;
            this.selectedWarrantyTermName = '';
            this.price = 0;
            this._retailPriceDisplay = 0;
            this.isPriceOverridden = false;
            this.existingAdditionalOptions = [];
            this.selectedNewOptions = [];
            this.availableAdditionalOptionsData = [];
        } else if (this._previousTermId) {
            const pkg = this.allDealerPackages.find(p => p.Id === this._previousPackageId);
            const termExists = pkg && pkg.warrantyTerms && pkg.warrantyTerms.some(t => t.Id === this._previousTermId);
            if (!termExists) {
                this.vehicleConfigChangedMessage = 'The previously selected term "' + (this._previousTermName || '') + '" is no longer available. Please select a new term.';
                this.selectedWarrantyTerm = null;
                this.selectedWarrantyTermName = '';
                this.price = 0;
                this._retailPriceDisplay = 0;
            } else {
                this.vehicleConfigChangedMessage = 'Vehicle details updated. Your current selection is still valid.';
                setTimeout(() => { this.vehicleConfigChangedMessage = ''; }, 5000);
            }
        } else {
            this.vehicleConfigChangedMessage = '';
        }
    }
    dismissVehicleConfigMessage() {
        this.vehicleConfigChangedMessage = '';
    }


    // Called when warranty tab is activated
    @api
    async onTabActivated() {
        
        
        // Always reload packages when tab is activated to ensure fresh data
        if (this.applicationId) {
            this.loadDealerPackages();
            this.loadVehicleData();
        } else {
        }
    }
    
    // Load vehicle data for display and deferral state
    async loadVehicleData() {
        if (!this.applicationId) {
            return;
        }

        try {
            const result = await loadVehicleData({ applicationId: this.applicationId });

            if (result.success && result.data) {
                const vData = result.data;
                this.vehicleData = {
                    year: vData.year || '',
                    make: vData.make || '',
                    model: vData.model || '',
                    trim: vData.trim || '',
                    vin: vData.vehicleIdentificationNumberVIN || vData.vin || '',
                    odometer: vData.odometer || '',
                    odometerUnit: vData.odometerUnit || 'KM',
                    purchasePrice: vData.vehiclePurchasePrice || vData.purchasePrice || ''
                };

                // Deferral state from Apex
                this.vehicleIdForDeferral = result.recordId || '';
                this.deferralOption = vData.deferralOption === true;
                this.packageTermAllowsDeferral = vData.packageTermAllowsDeferral === true;
                this.isManufacturerWarrantyExpired = vData.isManufacturerWarrantyExpired === true;
            }
        } catch (error) {
            console.error('Error loading vehicle data:', error);
        }
    }
    
    // Load dealer packages from Salesforce
    async loadDealerPackages() {
        try {
            console.log('🔍 WARRANTY - loadDealerPackages called');
            console.log('🔍 WARRANTY - applicationId:', this.applicationId);
            console.log('🔍 WARRANTY - recordType: Extended_Limited_Warranty');
            this.loading = true;
            
            const result = await getDealerPackages({ applicationId: this.applicationId, recordType: 'Extended_Limited_Warranty' });
            
            console.log('🔍 WARRANTY - getDealerPackages result:', result);
            console.log('🔍 WARRANTY - result.success:', result.success);
            console.log('🔍 WARRANTY - result.message:', result.message);
            console.log('🔍 WARRANTY - result.data:', result.data);
            console.log('🔍 WARRANTY - result.data length:', result.data ? result.data.length : 'null');
            if (result.debugInfo) {
                console.log('🔍 WARRANTY - Debug Info:', result.debugInfo);
                console.log('🔍 WARRANTY - Queried packages:', result.debugInfo.queriedPackagesCount);
                console.log('🔍 WARRANTY - Final packages:', result.debugInfo.finalPackagesCount);
                console.log('🔍 WARRANTY - Filtered out:', result.debugInfo.filteredOutCount);
                console.log('🔍 WARRANTY - Record Type:', result.debugInfo.recordType);
                console.log('🔍 WARRANTY - Dealer ID:', result.debugInfo.dealerId);
            }
            
            if (result.success) {
                // Capture premium vehicle status from response
                this.isPremiumVehicle = result.isPremiumVehicle === true;
                console.log('🏷️ WARRANTY - Premium Vehicle:', this.isPremiumVehicle);

                // Track whether the dealer has packages configured (before vehicle filtering)
                if (result.debugInfo) {
                    this.dealerHasPackages = (result.debugInfo.queriedPackagesCount || 0) > 0;
                } else {
                    this.dealerHasPackages = !!(result.data && result.data.length > 0);
                }

                if (!result.data || result.data.length === 0) {
                    console.log('❌ WARRANTY - No packages found in result.data');
                    console.log('❌ WARRANTY - Setting empty state');
                    this.dealerPackages = [];
                    this.allDealerPackages = [];
                    this.selectedPlanTypeKey = null;
                    this.selectedPlanType = null;
                    this.currentView = 'packageDetails';
                    this.loading = false;
                    return;
                }
                
                console.log('✅ WARRANTY - Found ' + result.data.length + ' packages in result.data');
                
                // Map the data to include warranty terms and options
                console.log('🔍 WARRANTY - Mapping packages...');
                this.allDealerPackages = result.data.map((pkg, index) => {
                    console.log('🔍 WARRANTY - Package ' + index + ':', {
                        id: pkg.Id,
                        name: pkg.Name,
                        packageName: pkg.PackageName,
                        planTypeId: pkg.planTypeId,
                        planTypeName: pkg.planTypeName,
                        termsCount: pkg.terms ? pkg.terms.length : 0,
                        optionsCount: pkg.options ? pkg.options.length : 0
                    });
                    
                    return {
                        ...pkg,
                        warrantyTerms: this._sortTerms(pkg.terms || []), // Keep for backward compatibility - sorted by km then months
                        tiers: pkg.tiers || [], // NEW: Grouped by tiers
                        options: pkg.options || []
                    };
                });
                
                console.log('✅ WARRANTY - Mapped ' + this.allDealerPackages.length + ' packages to allDealerPackages');
                this.dealerPackages = this.allDealerPackages;
                console.log('✅ WARRANTY - Set dealerPackages to ' + this.dealerPackages.length + ' packages');
                
                this.selectedPlanType = null;
                this.selectedPlanTypeKey = null;
                
                // Reset comparison selections when new packages load
                this.selectedPackagesForComparison = [];
                this.updatePackageCompareState();
                
                // Check for existing application package and auto-select it
                await this.checkForExistingApplicationPackage();
                
                // Always show all packages grouped by plan type
                this.dealerPackages = this.allDealerPackages;
                this.currentView = 'packageDetails';
                
                // Update selection highlighting after packages are loaded
                this.updateSelectionHighlighting();
                console.log('✅ WARRANTY - loadDealerPackages completed successfully');
            } else {
                console.error('❌ WARRANTY - result.success is false');
                console.error('❌ WARRANTY - Error message:', result.message);
                this.errorMessage = result.message;
                this.showError = true;
            }
        } catch (error) {
            console.error('❌ WARRANTY - Exception in loadDealerPackages:', error);
            console.error('❌ WARRANTY - Error stack:', error.stack);
            this.errorMessage = 'Error loading warranty packages. Please try again.';
            this.showError = false;
        } finally {
            this.loading = false;
            console.log('🔍 WARRANTY - loadDealerPackages finally block - loading set to false');
        }
    }
    
    // Check for existing application package and auto-select it
    @api
    async checkForExistingApplicationPackage() {
        try {
            console.log('🔍 Loading ACTIVE warranty package on init...');
            
            // USE NEW ACTIVE METHOD - Only loads packages where Active__c = true
            const result = await getActiveApplicationPackageByRecordType({ 
                applicationId: this.applicationId, 
                recordType: 'Extended_Limited_Warranty' 
            });
            
            console.log('📦 Active package load result:', result);
            
            if (result.success && result.data) {
                console.log('✅ Active package found');
                
                // Store the existing application package data
                this.existingApplicationPackage = result.data;
                this.isExistingApplication = true;

                // Restore dealer price override if one was previously saved
                if (result.data.dealerPriceOverride != null && result.data.dealerPriceOverride !== undefined) {
                    this.price = result.data.dealerPriceOverride;
                    this.isPriceOverridden = true;
                    // For override, extract pre-tax from stored override
                    const taxRate = result.data.taxPercentage || 0;
                    const preTax = taxRate > 0 ? this.price / (1 + taxRate / 100) : this.price;
                    this._retailPriceDisplay = preTax;
                    this._overridePreTaxPrice = preTax;
                    this._overrideTaxAmount = parseFloat((this.price - preTax).toFixed(2));
                }
                
                // Find the matching dealer package from our loaded packages
                const matchingDealerPackage = this.dealerPackages.find(pkg => pkg.Id === result.data.dealerPackageId);
                
                if (matchingDealerPackage) {
                    // Auto-select the existing package
                    this.selectedDealerPackage = matchingDealerPackage;
                    this.selectedProgram = matchingDealerPackage.PackageName;
                    this.savedDealerPackageId = matchingDealerPackage.Id;
                    
                    // Find and select the matching term
                    if (matchingDealerPackage.warrantyTerms && result.data.selectedTermId) {
                        const matchingTerm = matchingDealerPackage.warrantyTerms.find(term => 
                            term.Id === result.data.selectedTermId
                        );
                        
                        if (matchingTerm) {
                            this.selectedWarrantyTerm = matchingTerm;
                            this.selectedWarrantyTermName = matchingTerm.packageTermName || matchingTerm.Name || 'Selected Term';
                            this.savedWarrantyTermId = matchingTerm.Id;
                            
                            // Load additional options for the existing selected term
                            await this.loadAdditionalOptions(matchingTerm.Id);
                            
                            // Load existing additional options for this application package
                            await this.loadExistingAdditionalOptions(result.data.Id);
                        }
                    }
                    
                    // Note: currentView will be set in loadDealerPackages based on whether both package AND term are selected
                    
                    // Update price and other dependent fields
                    this.updatePrice();
                    
                    // Force re-render to update visual highlighting
                    setTimeout(() => {
                        this.renderKey++;
                        this.loading = false;
                        
                        // Apply highlighting after template is rendered
                        setTimeout(() => {
                            this.forceHighlightingUpdate();
                        }, 200);
                    }, 100);
                    
                    // Initialize original data for change tracking
                    this.initializeOriginalWarrantyData();
                    
                    // Dispatch warranty completion event after component is fully rendered
                    this.dispatchEvent(new CustomEvent('warrantycomplete', {
                        detail: { 
                            success: true,
                            warrantyData: this.getCurrentData(),
                            applicationId: this.applicationId,
                            autoSelected: true
                        }
                    }));
                }
            } else {
                console.log('ℹ️ No active package found');
                
                // Clear selections for new applications
                this.selectedDealerPackage = null;
                this.selectedWarrantyTerm = null;
                this.selectedWarrantyTermName = '';
                this.existingApplicationPackage = null;
                this.isExistingApplication = false;
                this.currentView = 'packageList';
                this.selectedDealerPackageName = '';

                if (this.savedDealerPackageId) {
                    await this.selectDealerPackageById(this.savedDealerPackageId);
                    if (this.savedWarrantyTermId) {
                        await this.selectWarrantyTermById(this.savedWarrantyTermId);
                    }
                }
            }
        } catch (error) {
        }
    }
    
    // Get dynamic dealer packages for display
    get dealerPackagesDisplay() {
        
        return this.dealerPackages.map(pkg => {
            const isSelected = this.selectedDealerPackage && this.selectedDealerPackage.Id === pkg.Id;
            const baseName = pkg.PackageName || pkg.Name || 'Warranty';
            const displayLabel = `${baseName} WARRANTY`;
            
            // Process tiers for display (NEW: Grouped structure)
            const processedTiers = (pkg.tiers || []).map(tier => {
                // Process terms within this tier
                const processedTerms = this._sortTerms(tier.terms || []).map(term => {
                    const isTermSelected = this.selectedWarrantyTerm && 
                                         this.selectedWarrantyTerm.Id === term.Id;
                    
                    // Disable terms for SELECTION if package is not selected
                    const isPackageNotSelected = this.selectedDealerPackage && this.selectedDealerPackage.Id !== pkg.Id;
                    const isTermDisabled = isPackageNotSelected;
                    
                    // Use the totalPrice from the term (already includes proper markup calculation from backend)
                    const displayPrice = term.totalPrice || term.netCost || 0;
                    
                    const termCssClass = isTermSelected ? 'term-option selected' : 'term-option';
                    
                    return {
                        ...term,
                        id: term.Id, // Ensure id is explicitly set
                        cssClass: termCssClass,
                        isSelected: isTermSelected,
                        isDisabled: isTermDisabled,
                        price: this.formatPrice(displayPrice),
                        termDisplayName: term.packageTermName || term.Name || 'Unknown Term',
                        termDuration: null,
                        termMileage: `${term.mileageRestriction || 0} ${term.mileageUnit || 'KM'}`,
                        // Keep all markup details for further use
                        netCost: term.netCost || 0,
                        markup: term.markup || 0,
                        markupType: term.markupType || '',
                        selectionText: isTermSelected ? 'Selected' : 
                                      isTermDisabled ? 'Unavailable' : 'Select',
                        buttonVariant: isTermSelected ? 'success' : 
                                      isTermDisabled ? 'neutral' : 'brand',
                        buttonDisabled: isTermDisabled
                    };
                });
                
                // Build tier display name with mileage restrictions if available
                let tierDisplayName = tier.Name || 'Tier';
                if (tier.mileageRestrictionStart != null || tier.mileageRestrictionEnd != null) {
                    const start = tier.mileageRestrictionStart != null ? this.formatMileage(tier.mileageRestrictionStart) : '';
                    const end = tier.mileageRestrictionEnd != null ? this.formatMileage(tier.mileageRestrictionEnd) : '';
                    const unit = tier.mileageUnit || 'KM';
                    if (start && end) {
                        tierDisplayName = `${tier.Name} (${start} - ${end} ${unit})`;
                    } else if (start) {
                        tierDisplayName = `${tier.Name} (${start}+ ${unit})`;
                    } else if (end) {
                        tierDisplayName = `${tier.Name} (up to ${end} ${unit})`;
                    }
                }
                
                return {
                    ...tier,
                    id: tier.Id || 'tier-' + Math.random(),
                    name: tierDisplayName,
                    terms: processedTerms,
                    hasTerms: processedTerms.length > 0
                };
            });
            
            // Process terms for backward compatibility (flat list)
            const processedTerms = this._sortTerms(pkg.warrantyTerms || []).map(term => {
                const isTermSelected = this.selectedWarrantyTerm && 
                                     this.selectedWarrantyTerm.Id === term.Id;
                
                const isPackageNotSelected = this.selectedDealerPackage && this.selectedDealerPackage.Id !== pkg.Id;
                const isTermDisabled = isPackageNotSelected;
                
                const displayPrice = term.totalPrice || term.netCost || 0;
                const termCssClass = isTermSelected ? 'term-option selected' : 'term-option';
                
                return {
                    ...term,
                    id: term.Id,
                    cssClass: termCssClass,
                    isSelected: isTermSelected,
                    isDisabled: isTermDisabled,
                    price: this.formatPrice(displayPrice),
                    termDisplayName: term.packageTermName || term.Name || 'Unknown Term',
                    termDuration: term.durationRestrictionInMonths || 0,
                    termMileage: `${term.mileageRestriction || 0} ${term.mileageUnit || 'KM'}`,
                    netCost: term.netCost || 0,
                    markup: term.markup || 0,
                    markupType: term.markupType || '',
                    selectionText: isTermSelected ? 'Selected' : 
                                  isTermDisabled ? 'Unavailable' : 'Select',
                    buttonVariant: isTermSelected ? 'success' : 
                                  isTermDisabled ? 'neutral' : 'brand',
                    buttonDisabled: isTermDisabled
                };
            });
            
            // Process options for display
            const processedOptions = (pkg.options || []).map(option => {
                const optionId = option.Id || option.id;
                return {
                    ...option,
                    id: optionId,
                    label: option.Name || option.label || option.OptionName
                };
            });
            
            const cssClass = isSelected ? 'program-section selected' : 'program-section';
            
            return {
                id: pkg.Id,
                baseName,
                name: displayLabel,
                description: pkg.PackageDescription,
                isSelected: isSelected,
                cssClass: cssClass,
                buttonVariant: isSelected ? 'success' : 'brand',
                buttonLabel: isSelected ? 'Selected' : 'Select Package',
                dealerPackageId: pkg.Id,
                dealerId: pkg.DealerId,
                buttonClass: isSelected ? 'select-program-btn selected' : 'select-program-btn',
                buttonDisabled: isSelected,
                terms: processedTerms, // Keep for backward compatibility
                tiers: processedTiers, // NEW: Grouped by tiers
                hasTiers: processedTiers.length > 0,
                options: processedOptions
            };
        });
    }
    
    // Helper method to format mileage for display
    formatMileage(mileage) {
        if (mileage == null) return '';
        // Format with commas for thousands
        return mileage.toLocaleString('en-US', { maximumFractionDigits: 0 });
    }
    
    // Get warranty terms for display

    // Sort terms by km ascending, then months ascending
    _parseKmFromName(name) {
        if (!name) return 0;
        var m = name.match(/(\d[\d,]*(?:\.\d+)?)\s*(?:KM|km|Km)/i);
        if (m) return parseFloat(m[1].replace(/,/g, ""));
        return 0;
    }

    _parseMonthsFromName(name) {
        if (!name) return 0;
        var m = name.match(/(\d+)\s*(?:Month|Months|month|months|Mo)/i);
        if (m) return parseInt(m[1], 10);
        return 0;
    }

    _sortTerms(terms) {
        return [...terms].sort((a, b) => {
            var kmA = Number(a.mileageRestriction) || this._parseKmFromName(a.packageTermName || a.Name || a.name);
            var kmB = Number(b.mileageRestriction) || this._parseKmFromName(b.packageTermName || b.Name || b.name);
            if (kmA !== kmB) return kmA - kmB;
            var moA = Number(a.durationRestrictionInMonths) || this._parseMonthsFromName(a.packageTermName || a.Name || a.name);
            var moB = Number(b.durationRestrictionInMonths) || this._parseMonthsFromName(b.packageTermName || b.Name || b.name);
            return moA - moB;
        });
    }

    get warrantyTermsDisplay() {
        if (!this.selectedDealerPackage || !this.selectedDealerPackage.warrantyTerms) {
            return [];
        }
        
        return this._sortTerms(this.selectedDealerPackage.warrantyTerms).map(term => {
            const isSelected = this.selectedWarrantyTerm && 
                             this.selectedWarrantyTerm.Id === term.Id;
            
            let displayPrice;
            if (this.isExistingApplication && this.existingApplicationPackage) {
                // For existing applications, show the retail price directly from Application_Package__c
                displayPrice = this.formatPrice(this.existingApplicationPackage.dealerPackageRetailPrice || 0);
            } else {
                // For new selections, show the retail price from Dealer_Package_Term__c
                displayPrice = this.formatPrice(term.totalPrice || term.retailPrice || term.netCost || 0);
            }
            
            return {
                ...term,
                cssClass: isSelected ? 'term-option selected' : 'term-option',
                isSelected: isSelected,
                displayPrice: displayPrice
            };
        });
    }
    
    get isTermSelected() {
        return (term) => {
            return term.value === this.selectedTerm;
        };
    }
    
    get isClaimSelected() {
        return (option) => {
            return option.value === this.selectedClaim;
        };
    }
    
    get isDeductible150Selected() {
        return this.selectedDeductible === '150';
    }
    
    get isDeductibleZeroSelected() {
        return this.selectedDeductible === 'ZERO';
    }
    
    // Handle package selection
    async handlePackageSelection(event) {
        const packageId = event.currentTarget?.dataset?.package;
        await this.selectDealerPackageById(packageId);
    }

    async handlePackageTileClick(event) {
        const packageId = event.currentTarget?.dataset?.packageId;
        await this.selectDealerPackageById(packageId);
    }

    handleBackToPackageList() {
        this.currentView = 'planTypes';
        this.dealerPackages = this.allDealerPackages;
        this.selectedPlanType = null;
        this.selectedPlanTypeKey = null;
        this.selectedDealerPackage = null;
        this.selectedWarrantyTerm = null;
        this.selectedDealerPackageName = '';
    }

    async selectDealerPackageById(packageId) {
        if (!packageId) {
            return;
        }

        const selectedPackage = this.dealerPackages.find(pkg => pkg.Id === packageId);
        
        if (!selectedPackage) {
            this.showErrorMessage('Unable to locate the selected package. Please try again.');
            return;
        }
        
        // Check if this is a different package than currently selected
        const isPackageChange = this.selectedDealerPackage && this.selectedDealerPackage.Id !== selectedPackage.Id;
        
        if (isPackageChange) {
            console.log('📦 Package selection changed - will save when user clicks Continue');
            
            // Clear additional options when package changes
            console.log('🧹 Clearing additional options for new package');
            this.selectedAdditionalOptions = [];
            this.existingAdditionalOptions = [];
            this.selectedNewOptions = [];
            this.optionsToRemove = [];
            this.availableAdditionalOptionsData = [];
        }
        
        // Clear term selection when package changes (validation requirement)
        this.selectedWarrantyTerm = null;
        this.selectedWarrantyTermName = '';
        
        // Track the package change
        const oldPackageId = this.originalWarrantyData.selectedDealerPackageId;
        const newPackageId = selectedPackage.Id;
        
        this.selectedDealerPackage = selectedPackage;
        this.selectedProgram = selectedPackage.PackageName;
        this.selectedDealerPackageName = selectedPackage.PackageName;
        this.selectedPlanTypeKey = selectedPackage.planTypeId || this.otherPlanTypeKey;
        this.setSelectedPlanTypeFromKey(this.selectedPlanTypeKey);
        this.savedDealerPackageId = selectedPackage.Id;
        this.savedWarrantyTermId = null;
        
        // Track change for auto-save
        this.trackWarrantyChange('package', oldPackageId, newPackageId);
        
        // Force UI refresh to show selection highlighting
        this.template.querySelectorAll('.program-section').forEach(section => {
            section.classList.remove('selected');
        });
        
        // Update selection highlighting
        this.updateSelectionHighlighting();
        
        // Update price (will be 0 until term is selected)
        this.updatePrice();
        
        // Save data
        this.saveDataToSession();
        this.currentView = 'packageDetails';
    }
    
    // Handle warranty term selection
    async handleWarrantyTermSelection(event) {
        const termId = event.currentTarget.dataset.term;
        const packageId = event.currentTarget.dataset.package;
        await this.selectWarrantyTermById(termId, packageId);
    }

    async selectWarrantyTermById(termId, packageId = null) {
        // If packageId is provided and different from selected package, select that package first
        if (packageId) {
            if (!this.selectedDealerPackage || this.selectedDealerPackage.Id !== packageId) {
                await this.selectDealerPackageById(packageId);
            }
        }

        if (!this.selectedDealerPackage) {
            this.showErrorMessage('Please select a warranty package before selecting a term.');
            return;
        }

        if (this.selectedWarrantyTerm && this.selectedWarrantyTerm.Id === termId) {
            return;
        }

        if (!this.selectedDealerPackage.warrantyTerms) {
            return;
        }

        const selectedTerm = this.selectedDealerPackage.warrantyTerms.find(term => term.Id === termId);

        if (selectedTerm) {
            await this.applySelectedWarrantyTerm(selectedTerm);
        }
    }

    async applySelectedWarrantyTerm(selectedTerm) {
        const hasSelectedOptions = this.selectedNewOptions.length > 0;

        if (hasSelectedOptions) {
            const proceed = await this.confirmTermChangeWithOptions(selectedTerm);
            if (!proceed) {
                return;
            }
        }

        const oldTermId = this.originalWarrantyData.selectedWarrantyTermId;
        const newTermId = selectedTerm.Id;

        this.selectedWarrantyTerm = selectedTerm;
        this.selectedWarrantyTermName = selectedTerm.packageTermName || selectedTerm.Name || 'Selected Term';
        this.savedWarrantyTermId = selectedTerm.Id;
        // Re-evaluate deferral availability based on newly selected term
        // If deferral is no longer available, uncheck and clear the saved value
        if (!selectedTerm.allowDeferral && this.deferralOption) {
            this.deferralOption = false;
            if (this.vehicleIdForDeferral) {
                updateVehicleFieldsSelective({
                    updateData: {
                        vehicleId: this.vehicleIdForDeferral,
                        applicationId: this.applicationId,
                        fields: { Deferral_Option__c: false }
                    }
                }).catch(err => console.error('❌ Error clearing deferral option on term change:', err));
            }
        }
        // Reset any manual price override when a new term is selected
        this.isPriceOverridden = false;
        this.isPriceEditMode = false;
        this.priceOverrideInput = '';

        this.clearAdditionalOptionsForTermSwitch();
        this.trackWarrantyChange('term', oldTermId, newTermId);
        await this.loadAdditionalOptions(selectedTerm.Id);
        console.log('ℹ️ Additional options loaded for new term - user must re-select');

        this.updatePrice();
        this.saveDataToSession();
        console.log('🔍 handleWarrantyTermSelection - Term selected, will create package on Continue');
        this.renderKey++;
    }
    
    /**
     * Show the Deferral Option checkbox whenever a warranty term is selected.
     */
    get showDeferralOption() {
        return !!this.selectedWarrantyTerm;
    }

    /**
     * Disable the Deferral Option checkbox when:
     * - Form is locked, OR
     * - Selected term's Package_Term__c does not have Allow_Deferral__c = true, OR
     * - Manufacturer warranty has already expired
     */
    get deferralOptionDisabled() {
        if (this.fieldDisabled) return true;
        if (!this.selectedWarrantyTerm || !this.selectedWarrantyTerm.allowDeferral) return true;
        if (this.isManufacturerWarrantyExpired) return true;
        return false;
    }

    /**
     * When the user toggles the deferral checkbox, immediately save
     * Deferral_Option__c to Vehicle__c via updateVehicleFieldsSelective.
     */
    async handleDeferralOptionChange(event) {
        const newValue = event.target.checked;
        this.deferralOption = newValue;

        if (!this.vehicleIdForDeferral) {
            console.warn('⚠️ No vehicleId available — cannot save deferral option');
            return;
        }

        try {
            await updateVehicleFieldsSelective({
                updateData: {
                    vehicleId: this.vehicleIdForDeferral,
                    applicationId: this.applicationId,
                    fields: { Deferral_Option__c: newValue }
                }
            });
            console.log('✅ Deferral option saved:', newValue);
        } catch (error) {
            console.error('❌ Error saving deferral option:', error);
            // Revert on failure
            this.deferralOption = !newValue;
        }
    }

    // Force highlighting update by manually applying CSS classes to DOM
    forceHighlightingUpdate() {
        try {
            // Find and highlight selected package accordion
            if (this.selectedDealerPackage) {
                const packageAccordion = this.template.querySelector(`lightning-accordion-section[data-package-id="${this.selectedDealerPackage.Id}"]`);
                if (packageAccordion) {
                    packageAccordion.classList.add('selected');
                }
            }
            
            // Find and highlight selected term
            if (this.selectedWarrantyTerm) {
                this.template.querySelectorAll('[data-term]').forEach(termEl => termEl.classList.remove('selected'));
                const termElement = this.template.querySelector(`[data-term="${this.selectedWarrantyTerm.Id}"]`);
                if (termElement) {
                    termElement.classList.add('selected');
                }
            }
        } catch (error) {
        }
    }
    
    // Update existing application package in Salesforce
    async updateExistingApplicationPackage(newPackage, newTerm) {
        try {
            // Validate required data before proceeding
            if (!this.existingApplicationPackage || !this.existingApplicationPackage.Id) {
                throw new Error('Existing application package data is missing');
            }
            
            if (!newPackage || !newPackage.Id) {
                throw new Error('Selected dealer package data is missing');
            }
            
            
            const packageDataMap = {
                packageId: this.existingApplicationPackage.Id,
                selectedTermId: newTerm ? newTerm.Id : null,
                includeDeductible: false // Set to false for now, can be made configurable later
            };
            
            
            const result = await updateApplicationPackage(packageDataMap);
            
            if (result.success) {
                // Update local existing package data
                this.existingApplicationPackage = {
                    ...this.existingApplicationPackage,
                    dealerPackageId: newPackage.Id,
                    selectedTermId: newTerm ? newTerm.Id : null,
                    dealerPackagePrice: newTerm ? (newTerm.totalPrice || newTerm.netCost || 0) : 0
                };
            } else {
            }
        } catch (error) {
            console.error('❌ Error updating application package:', error);
        }
    }
    
    // Show error message to user
    showErrorMessage(message) {
        this.errorMessage = message;
        this.showError = true;
        
        // Auto-hide error after 5 seconds
        setTimeout(() => {
            this.showError = false;
        }, 5000);
    }
    
    
    // Option help functionality
    toggleOptionHelp(event) {
        const optionId = event.target.dataset.optionId;
        const helpType = event.target.dataset.helpType;
        const helpText = event.target.dataset.helpText;
        
        this.helpModalTitle = helpType === 'inclusion' ? 'Inclusion Details' : 'Exclusion Details';
        this.helpModalText = helpText;
        this.showHelpModal = true;
    }
    
    // Close help modal
    closeHelpModal() {
        this.showHelpModal = false;
    }
    
    
    // Validate form before continuing
    validateForm() {
        if (!this.selectedDealerPackage) {
            this.errorMessage = 'Please select a warranty package before continuing.';
            this.showError = true;
            return false;
        }
        
        if (!this.selectedWarrantyTerm) {
            this.errorMessage = 'Please select a warranty term before continuing.';
            this.showError = true;
            return false;
        }
        
        // Clear any previous errors
        this.showError = false;
        this.errorMessage = '';
        
        return true;
    }
    
    get eligibilityRules() {
        return [
            { id: 'rule1', text: 'Vehicles with an odometer up to 160,000 KMs are eligible for 1 and 2 year terms' },
            { id: 'rule2', text: 'Vehicles with an odometer up to 120,000 KMs are eligible for 3 and 4 year terms' },
            { id: 'rule3', text: 'Vehicles with an odometer over 160,000 KMs are not eligible' }
        ];
    }
    
    get termOptions() {
        return [
            { id: '1', label: '1 Year', value: '1' },
            { id: '2', label: '2 Years', value: '2' },
            { id: '3', label: '3 Years', value: '3' },
            { id: '4', label: '4 Years', value: '4' }
        ];
    }
    
    get claimOptions() {
        if (this.selectedProgram === 'DIAMOND_PLUS') {
            return [
                { id: 'retail', label: `${this.selectedProgram} / ${this.selectedTerm} YEAR / 20,000 KMS / RETAIL MAX PER CLAIM`, value: 'retail' },
                { id: '5000', label: `${this.selectedProgram} / ${this.selectedTerm} YEAR / 20,000 KMS / $5,000 MAX PER CLAIM`, value: '5000' },
                { id: '10000', label: `${this.selectedProgram} / ${this.selectedTerm} YEAR / 20,000 KMS / $10,000 MAX PER CLAIM`, value: '10000' }
            ];
        } else {
            return [
                { id: 'retail', label: `${this.selectedProgram} / ${this.selectedTerm} YEAR / 80,000 KMS / RETAIL MAX PER CLAIM`, value: 'retail' },
                { id: '5000', label: `${this.selectedProgram} / ${this.selectedTerm} YEAR / 80,000 KMS / $5,000 MAX PER CLAIM`, value: '5000' },
                { id: '10000', label: `${this.selectedProgram} / ${this.selectedTerm} YEAR / 80,000 KMS / $10,000 MAX PER CLAIM`, value: '10000' },
                { id: '25000', label: `${this.selectedProgram} / ${this.selectedTerm} YEAR / 80,000 KMS / $25,000 MAX PER CLAIM`, value: '25000' },
                { id: 'unlimited-5000', label: `${this.selectedProgram} / ${this.selectedTerm} YEAR / UNLIMITED / $5,000 MAX PER CLAIM`, value: 'unlimited-5000' },
                { id: 'unlimited-10000', label: `${this.selectedProgram} / ${this.selectedTerm} YEAR / UNLIMITED / $10,000 MAX PER CLAIM`, value: 'unlimited-10000' },
                { id: 'unlimited-25000', label: `${this.selectedProgram} / ${this.selectedTerm} YEAR / UNLIMITED / $25,000 MAX PER CLAIM`, value: 'unlimited-25000' }
            ];
        }
    }
    
    get includedOptions() {
        if (this.selectedProgram === 'DIAMOND_PLUS') {
            return [
                { id: 'engine', label: 'ENGINE', checked: true },
                { id: 'transmission', label: 'TRANSMISSION', checked: true },
                { id: 'differential', label: 'DIFFERENTIAL', checked: true },
                { id: 'transferCase', label: 'TRANSFER CASE', checked: true },
                { id: 'auxDifferential', label: 'AUXILIARY DIFFERENTIAL', checked: true },
                { id: 'turbo', label: 'TURBOCHARGER', checked: true },
                { id: 'supercharger', label: 'SUPERCHARGER', checked: true },
                { id: 'tripInterruption', label: 'TRIP INTERRUPTION', checked: true },
                { id: 'diagnostics', label: 'DIAGNOSTICS', checked: true },
                { id: 'driveline', label: 'DRIVELINE PLUS', checked: true },
                { id: 'braking', label: 'BRAKING SYSTEM', checked: true }
            ];
        } else if (this.selectedProgram === 'TITANIUM') {
            return [
                { id: 'engine', label: 'ENGINE', checked: true },
                { id: 'transmission', label: 'TRANSMISSION', checked: true },
                { id: 'differential', label: 'DIFFERENTIAL', checked: true },
                { id: 'transferCase', label: 'TRANSFER CASE', checked: true },
                { id: 'auxDifferential', label: 'AUXILIARY DIFFERENTIAL', checked: true },
                { id: 'turbo', label: 'TURBOCHARGER', checked: true },
                { id: 'supercharger', label: 'SUPERCHARGER', checked: false },
                { id: 'tripInterruption', label: 'TRIP INTERRUPTION', checked: true },
                { id: 'diagnostics', label: 'DIAGNOSTICS', checked: true }
            ];
        } else {
            return [];
        }
    }
    
    // Save data to session storage
    saveDataToSession() {
        const warrantyData = {
            selectedProgram: this.selectedProgram,
            selectedTerm: this.selectedTerm,
            selectedClaim: this.selectedClaim,
            selectedDeductible: this.selectedDeductible,
            testDrive: this.testDrive,
            price: this.price,
            selectedDealerPackageId: this.selectedDealerPackage?.Id || null,
            selectedWarrantyTermId: this.selectedWarrantyTerm?.Id || null,
        };
        
        sessionStorage.setItem('warrantyData', JSON.stringify(warrantyData));
    }
    
    // Store component data for back navigation
    getCurrentData() {
        return {
            selectedProgram: this.selectedProgram,
            selectedTerm: this.selectedTerm,
            selectedClaim: this.selectedClaim,
            selectedDeductible: this.selectedDeductible,
            testDrive: this.testDrive,
            price: this.price,
            selectedDealerPackage: this.selectedDealerPackage,
            selectedWarrantyTerm: this.selectedWarrantyTerm,
            selectedDealerPackageId: this.selectedDealerPackage?.Id || null,
            selectedWarrantyTermId: this.selectedWarrantyTerm?.Id || null,
        };
    }
    
    // Restore data when navigating back
    @api
    restoreData(data) {
        if (data) {
            this.selectedProgram = data.selectedProgram || this.selectedProgram;
            this.selectedTerm = data.selectedTerm || this.selectedTerm;
            this.selectedClaim = data.selectedClaim || this.selectedClaim;
            this.selectedDeductible = data.selectedDeductible || this.selectedDeductible;
            this.testDrive = data.testDrive || this.testDrive;
            this.price = data.price || this.price;
            
            if (data.selectedDealerPackage?.PackageName) {
                this.selectedDealerPackageName = data.selectedDealerPackage.PackageName;
            }
            this.savedDealerPackageId = data.selectedDealerPackage?.Id || data.selectedDealerPackageId || null;
            this.savedWarrantyTermId = data.selectedWarrantyTerm?.Id || data.selectedWarrantyTermId || null;
        }
    }
    
    handleProgramClick(event) {
        const selectedProgramName = event.currentTarget.dataset.program;
        this.selectedProgram = selectedProgramName;
        
        this.updatePrice();
        
        // Hide error when user selects a program
        this.showError = false;
    }
    
    handleTermChange(event) {
        this.selectedTerm = event.target.value;
        this.updatePrice();
        
        // Hide error when user selects a term
        this.showError = false;
    }
    
    handleClaimChange(event) {
        this.selectedClaim = event.target.value;
        this.updatePrice();
        
        // Hide error when user selects a claim
        this.showError = false;
    }
    
    handleDeductibleChange(event) {
        this.selectedDeductible = event.target.value;
        this.updatePrice();
        
        // Hide error when user selects a deductible
        this.showError = false;
    }
    
    handleTestDriveChange(event) {
        this.testDrive = event.target.checked;
        this.updatePrice();
    }
    
    handleDeclineWarranty() {
        this.showDeclineModal = true;
    }
    
    // Handle confirm decline from modal - REMOVED DUPLICATE
    // The correct version is at line 1401
    
    // Handle cancel decline from modal
    cancelDeclineWarranty() {
        this.showDeclineModal = false;
    }
    
    
    // Handle back button click
    handleBack() {
        console.log('🔙 Back button clicked from warranty component');
        
        // Save current data before navigating back
        this.saveDataToSession();
        
        // Dispatch back event - container expects 'back' event
        const backEvent = new CustomEvent('back', {
            detail: { 
                data: this.getCurrentData()
            },
            bubbles: true
        });
        this.dispatchEvent(backEvent);
        console.log('🔙 Back event dispatched to container');
    }

    // Handle skip button click - navigate to next tab without saving
    handleSkip() {
        console.log('⏭️ Warranty tab skipped - navigating to next tab without saving');
        this.dispatchEvent(new CustomEvent('warrantycomplete', {
            detail: { 
                success: true,
                skipped: true,
                applicationId: this.applicationId
            }
        }));
    }
    
    updatePrice() {
        if (this.isPriceOverridden) return;
        console.log('💰 === UPDATE PRICE START ===');
        console.log('💰 isExistingApplication:', this.isExistingApplication);
        console.log('💰 existingApplicationPackage:', this.existingApplicationPackage);
        console.log('💰 selectedWarrantyTerm:', this.selectedWarrantyTerm);
        
        // Check if user selected a different term than the stored one
        const isSameTerm = this.isExistingApplication && 
                          this.existingApplicationPackage && 
                          this.selectedWarrantyTerm && 
                          this.selectedWarrantyTerm.Id === this.existingApplicationPackage.selectedTermId;
        
        // For Draft/Pending applications, always recalculate from current term pricing
        // so admin pricing changes are reflected. Only use stored values for locked/submitted apps.
        const appStatus = this.applicationStatus || '';
        const shouldUseStoredPrice = isSameTerm && !['Draft', 'Pending', 'Quote'].includes(appStatus);
        
        if (shouldUseStoredPrice) {
            // For submitted/active applications with same term, use stored pricing directly from Application_Package__c.
            // IMPORTANT: contractPremiumPrice is a formula that returns Dealer_Price_Override__c when one exists.
            // If the user has reset the override (isPriceOverridden = false), we must use the original
            // admin-calculated price (contractPremiumPriceWithoutTax + taxAmount) so that switching away
            // and back to this term does not silently re-apply the old override without the badge/reset UI.
            const hasStoredOverride = this.existingApplicationPackage.dealerPriceOverride != null &&
                                      this.existingApplicationPackage.dealerPriceOverride !== undefined;
            if (hasStoredOverride) {
                // Override exists in DB — show original admin price (base + tax), not the override value
                const basePrice = this.existingApplicationPackage.contractPremiumPriceWithoutTax || 0;
                const taxAmount = this.existingApplicationPackage.taxAmount || 0;
                this.price = parseFloat((basePrice + taxAmount).toFixed(2));
                this._retailPriceDisplay = basePrice;
            } else {
                this.price = this.existingApplicationPackage.contractPremiumPrice || 0;
                this._retailPriceDisplay = this.existingApplicationPackage.contractPremiumPriceWithoutTax || this.existingApplicationPackage.dealerPackageRetailPrice || 0;
            }

            console.log('💰 Existing app price (using stored values from Application_Package__c):', {
                dealerPackagePrice: this.existingApplicationPackage.dealerPackagePrice,
                dealerMarkup: this.existingApplicationPackage.dealerMarkup,
                dealerPackageRetailPrice: this.existingApplicationPackage.dealerPackageRetailPrice,
                addOnsPrice: this.existingApplicationPackage.addOnsPrice,
                addOnsMarkup: this.existingApplicationPackage.addOnsMarkup,
                addOnsRetailPrice: this.existingApplicationPackage.addOnsRetailPrice,
                contractPremiumPriceWithoutTax: this.existingApplicationPackage.contractPremiumPriceWithoutTax,
                taxPercentage: this.existingApplicationPackage.taxPercentage,
                taxAmount: this.existingApplicationPackage.taxAmount,
                contractPremiumPrice: this.existingApplicationPackage.contractPremiumPrice,
                total: this.price
            });
        } else if (this.selectedWarrantyTerm) {
            // For new selections, calculate price with tax explicitly
            const netCost = this.selectedWarrantyTerm.netCost || 0;
            const markup = this.selectedWarrantyTerm.markup || 0;
            const markupType = this.selectedWarrantyTerm.markupType || '';
            
            // Calculate price with markup
            let priceWithMarkup = netCost;
            if (markupType === '%' && markup > 0) {
                priceWithMarkup = netCost + (netCost * markup / 100);
            } else if (markupType === '$' && markup > 0) {
                priceWithMarkup = netCost + markup;
            }
            
            // Add new additional options pricing first
            const newOptionsPrice = this.selectedNewOptions.reduce((total, optionId) => {
                const option = this.availableAdditionalOptionsData.find(opt => opt.id === optionId);
                return total + (option ? (option.retailPrice || option.netCost || 0) : 0);
            }, 0);
            
            // Calculate premium vehicle fee
            const premiumFee = this.isPremiumVehicle && this.selectedWarrantyTerm && this.selectedWarrantyTerm.premiumModelFee ? this.selectedWarrantyTerm.premiumModelFee : 0;
            
            // Calculate total taxable amount (term retail price + additional options + premium vehicle fee)
            const totalTaxableAmount = priceWithMarkup + newOptionsPrice + premiumFee;
            
            // Calculate tax on total taxable amount - use taxRate (term taxAmount is only for term, recalculate for total)
            let taxAmount = 0;
            const taxRate = this.selectedWarrantyTerm.taxRate || this.selectedDealerPackage?.taxRate || 0;
            if (taxRate > 0) {
                taxAmount = totalTaxableAmount * (taxRate / 100);
            }
            
            // Total price = taxable amount + tax
            this.price = totalTaxableAmount + taxAmount;
            // Show base price WITHOUT premium fee (premium is displayed separately)
            this._retailPriceDisplay = priceWithMarkup + newOptionsPrice;
            console.log('💰 New selection price calculation:', {
                netCost,
                markup,
                markupType,
                priceWithMarkup,
                newOptionsPrice,
                premiumFee,
                totalTaxableAmount,
                taxAmount,
                taxRate,
                total: this.price,
                termTotalPrice: this.selectedWarrantyTerm.totalPrice,
                termTaxAmount: this.selectedWarrantyTerm.taxAmount,
                termTaxRate: this.selectedWarrantyTerm.taxRate
            });
        } else {
            this.price = 0.00;
            this._retailPriceDisplay = 0;
            console.log('💰 No valid pricing data, setting price to 0');
        }
        
        console.log('💰 Final price:', this.price);
        console.log('💰 === UPDATE PRICE END ===');
    }
    
    // Price breakdown modal methods
    showPriceBreakdownModal() {
        if (!this.selectedWarrantyTerm && !this.isExistingApplication) {
            return;
        }

        let netCost = 0;
        let taxRate = 0;
        let taxAmount = 0;

        // Check if user selected a different term than the stored one
        const isSameTerm = this.isExistingApplication && 
                          this.existingApplicationPackage && 
                          this.selectedWarrantyTerm && 
                          this.selectedWarrantyTerm.Id === this.existingApplicationPackage.selectedTermId;

        const bdAppStatus = this.applicationStatus || '';
        const useStoredForBreakdown = isSameTerm && !['Draft', 'Pending', 'Quote'].includes(bdAppStatus);

        if (useStoredForBreakdown) {
            netCost = this.existingApplicationPackage.dealerPackagePrice || 0;
            taxRate = this.existingApplicationPackage.taxPercentage || 0;
        } else if (this.selectedWarrantyTerm) {
            netCost = this.selectedWarrantyTerm.netCost || 0;
            taxRate = this.selectedWarrantyTerm.taxRate || this.selectedDealerPackage?.taxRate || 0;
        } else if (this.isExistingApplication && this.existingApplicationPackage) {
            netCost = this.existingApplicationPackage.dealerPackagePrice || 0;
            taxRate = this.existingApplicationPackage.taxPercentage || 0;
        }

        // Calculate additional options total (dealer cost / netCost)
        const existingOptionsNetCost = (this.existingAdditionalOptions || [])
            .filter(opt => !(this.optionsToRemove || []).includes(opt.id))
            .reduce((total, opt) => total + (opt.netCost || opt.retailPrice || 0), 0);

        const newOptionsNetCost = (this.selectedNewOptions || []).reduce((total, optionId) => {
            const opt = (this.availableAdditionalOptionsData || []).find(o => o.id === optionId);
            return total + (opt ? (opt.netCost || opt.retailPrice || 0) : 0);
        }, 0);

        const totalOptionsNetCost = existingOptionsNetCost + newOptionsNetCost;
        const totalDealerBeforeTax = netCost + totalOptionsNetCost;

        if (taxRate > 0) {
            taxAmount = totalDealerBeforeTax * (taxRate / 100);
        }

        // Premium vehicle fee
        const premiumFee = this.isPremiumVehicle && this.selectedWarrantyTerm && this.selectedWarrantyTerm.premiumModelFee ? this.selectedWarrantyTerm.premiumModelFee : 0;
        this.modalPremiumFee = premiumFee;
        
        this.modalDealerPrice = netCost;
        this.modalTaxRate = taxRate;
        
        // Recalculate total with premium fee included
        const totalBeforeTax = totalDealerBeforeTax + premiumFee;
        const recalcTaxAmount = taxRate > 0 ? totalBeforeTax * (taxRate / 100) : taxAmount;
        this.modalTaxAmount = recalcTaxAmount;
        this.modalTotalWithTax = totalBeforeTax + recalcTaxAmount;

        this.showPriceModal = true;
    }
    
    handleToggleDealerReference(event) {
        this.showDealerReferencePrice = event.target.checked;
    }

    // --- Dealer Pricing Modal Getters ---

    get selectedPlanName() {
        if (this.selectedDealerPackage) {
            return this.selectedDealerPackage.PackageName || this.selectedDealerPackage.Name || '';
        }
        return '';
    }

    get formattedDealerPrice() {
        if (this.modalDealerPrice != null) {
            return '$' + this.modalDealerPrice.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
        }
        return '$0.00';
    }

    get selectedAdditionalOptionsList() {
        const items = [];
        // Existing options not marked for removal
        if (this.existingAdditionalOptions) {
            this.existingAdditionalOptions
                .filter(opt => !(this.optionsToRemove || []).includes(opt.id))
                .forEach(opt => {
                    const cost = opt.netCost || opt.retailPrice || 0;
                    items.push({
                        id: opt.id,
                        optionName: opt.optionName || 'Option',
                        formattedDealerPrice: '$' + cost.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',')
                    });
                });
        }
        // Newly selected options
        if (this.selectedNewOptions && this.availableAdditionalOptionsData) {
            this.selectedNewOptions.forEach(optionId => {
                const opt = this.availableAdditionalOptionsData.find(o => o.id === optionId);
                if (opt) {
                    const cost = opt.netCost || opt.retailPrice || 0;
                    items.push({
                        id: opt.id,
                        optionName: opt.optionName || 'Option',
                        formattedDealerPrice: '$' + cost.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',')
                    });
                }
            });
        }
        return items;
    }

    get formattedTaxRate() {
        if (this.modalTaxRate != null && this.modalTaxRate > 0) {
            return this.modalTaxRate.toFixed(2) + '%';
        }
        return '0%';
    }

    get formattedTotalTaxAmount() {
        if (this.modalTaxAmount != null) {
            return '$' + this.modalTaxAmount.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
        }
        return '$0.00';
    }

    get formattedTotalWithTax() {
        if (this.modalTotalWithTax != null) {
            return '$' + this.modalTotalWithTax.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
        }
        return '$0.00';
    }

    get hasPremiumFee() {
        return this.isPremiumVehicle && this.modalPremiumFee > 0;
    }

    get formattedPremiumFee() {
        if (this.modalPremiumFee != null && this.modalPremiumFee > 0) {
            return '$' + this.modalPremiumFee.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
        }
        return '$0.00';
    }

    hidePriceBreakdownModal() {
        this.showPriceModal = false;
    }
    
    stopPropagation(event) {
        event.stopPropagation();
    }
    
    
    
    // Create or update application package
    async createOrUpdateApplicationPackage() {
        
        if (!this.applicationId || !this.selectedDealerPackage || !this.selectedWarrantyTerm) {
            console.warn('⚠️ Missing required data for application package creation');
            return;
        }
        
        this.loading = true;
        
        try {
            const packageData = {
                applicationId: this.applicationId,
                dealerId: this.selectedDealerPackage.DealerId,
                dealerPackageId: this.selectedDealerPackage.Id,
                packageName: this.selectedDealerPackage.PackageName,
                selectedTermId: this.selectedWarrantyTerm.Id,
                includeDeductible: false,
                dealerPriceOverride: this.isPriceOverridden ? this.price : null
            };

            // ========== NEW ACTIVE MANAGEMENT CODE ==========
            // Add recordType to packageData (REQUIRED for active management)
            packageData.recordType = 'Extended_Limited_Warranty';
            
            const result = await savePackageWithActiveManagement({
                packageDataMap: packageData
            });
            
            if (!result.success) {
                this.errorMessage = 'Failed to save warranty package: ' + result.message;
                this.showError = true;
            }
            
            /* ========== OLD CODE (RESTORE IF NEEDED) ==========
            const existingPackage = await getExistingApplicationPackageByRecordType({ 
                applicationId: this.applicationId, 
                recordType: 'Extended_Limited_Warranty' 
            });
            
            let result;
            if (existingPackage && existingPackage.data && existingPackage.data.Id) {
                result = await updateApplicationPackage({
                    packageId: existingPackage.data.Id,
                    selectedTermId: packageData.selectedTermId,
                    includeDeductible: false
                });
            } else {
                packageData.recordType = 'Extended_Limited_Warranty';
                result = await createApplicationPackageFromMap({packageDataMap: packageData});
            }
            ========== END OLD CODE ========== */
            
            this.fireCompletionEvent();
            
        } catch (error) {
            console.error('❌ Error creating/updating application package:', error);
            this.showError = true;
            this.errorMessage = 'Unable to save warranty selection. Please try again.';
        } finally {
            this.loading = false;
        }
    }
    
    fireCompletionEvent() {
        const completionEvent = new CustomEvent('tabcompleted', {
            detail: {
                tab: 'warranty',
                completed: this.selectedWarrantyTerm !== null
            },
            bubbles: true
        });
        this.dispatchEvent(completionEvent);
    }
    
    // Price override handlers
    handlePriceClick() {
        if (!this.selectedWarrantyTerm) return;
        this.isPriceEditMode = true;
        // Show pre-tax override price if available, otherwise show current price
        const editPrice = this._overridePreTaxPrice || this.price;
        this.priceOverrideInput = editPrice ? editPrice.toFixed(2) : '';
        // Focus the input on next tick
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const input = this.template.querySelector('.price-override-input');
            if (input) {
                input.focus();
                input.select();
            }
        }, 0);
    }

    handlePriceOverrideChange(event) {
        this.priceOverrideInput = event.target.value;
    }

    handlePriceOverrideBlur() {
        this._applyPriceOverride();
    }

    handlePriceOverrideKeyDown(event) {
        if (event.key === 'Enter') {
            this._applyPriceOverride();
        } else if (event.key === 'Escape') {
            this.isPriceEditMode = false;
            this.priceOverrideInput = '';
        }
    }

    _applyPriceOverride() {
        const val = parseFloat(this.priceOverrideInput);
        if (!isNaN(val) && val >= 0) {
            // Price floor validation removed - dealers can enter any custom price
            this.priceValidationMessage = '';
            // Custom price is pre-tax; calculate tax and add to total
            const customPreTax = parseFloat(val.toFixed(2));
            const taxRate = this._getCurrentTaxRate();
            const taxAmount = taxRate > 0 ? customPreTax * (taxRate / 100) : 0;
            this._overridePreTaxPrice = customPreTax;
            this._overrideTaxAmount = parseFloat(taxAmount.toFixed(2));
            this.price = parseFloat((customPreTax + taxAmount).toFixed(2));
            this._retailPriceDisplay = customPreTax;
            this.isPriceOverridden = true;
        } else {
            // Empty or invalid — revert to calculated price
            this.isPriceOverridden = false;
            this._overridePreTaxPrice = null;
            this._overrideTaxAmount = null;
            this.updatePrice();
        }
        this.isPriceEditMode = false;
    }

    /**
     * Get the current applicable tax rate from the best available source.
     */
    _getCurrentTaxRate() {
        if (this.existingApplicationPackage && this.existingApplicationPackage.taxPercentage) {
            return this.existingApplicationPackage.taxPercentage;
        }
        if (this.selectedWarrantyTerm && this.selectedWarrantyTerm.taxRate) {
            return this.selectedWarrantyTerm.taxRate;
        }
        if (this.selectedDealerPackage && this.selectedDealerPackage.taxRate) {
            return this.selectedDealerPackage.taxRate;
        }
        return 0;
    }

    handleResetPriceOverride() {
        this.isPriceOverridden = false;
        this.isPriceEditMode = false;
        this.priceOverrideInput = '';
        this.priceValidationMessage = '';
        this._overridePreTaxPrice = null;
        this._overrideTaxAmount = null;

        // For an existing application on the same term, restore pricing.
        // For Draft/Pending, recalculate from current term. For submitted/active, use stored values.
        const isSameTerm = this.isExistingApplication &&
                           this.existingApplicationPackage &&
                           this.selectedWarrantyTerm &&
                           this.selectedWarrantyTerm.Id === this.existingApplicationPackage.selectedTermId;

        const resetAppStatus = this.applicationStatus || '';
        const useStoredForReset = isSameTerm && !['Draft', 'Pending', 'Quote'].includes(resetAppStatus);

        if (useStoredForReset) {
            const basePrice = this.existingApplicationPackage.contractPremiumPriceWithoutTax || 0;
            const taxAmount = this.existingApplicationPackage.taxAmount || 0;
            this.price = parseFloat((basePrice + taxAmount).toFixed(2));
            this._retailPriceDisplay = basePrice;
        } else {
            this.updatePrice();
        }
    }

    formatPrice(price) {
        return new Intl.NumberFormat('en-CA', {
            style: 'currency',
            currency: 'CAD',
            minimumFractionDigits: 2
        }).format(price || 0);
    }
    
    // Test method to verify component functionality
    @api
    async testComponent() {
        try {
            return { success: true, message: 'Warranty component is functional' };
        } catch (error) {
            return { success: false, error: error.message };
        }
    }
    
    // Method to manually set application ID for testing
    @api
    setApplicationId(id) {
        this._applicationId = id;
        
        // Load dealer packages if we have an application ID
        if (id) {
            this.loadDealerPackages();
        }
    }
    
    async handleContinue() {
        if (this.showNoPackageDisclaimer || this.showVehicleNotEligibleDisclaimer) {
            this.handleSkip();
            return;
        }

        // Check if applicationId is missing
        if (!this.applicationId) {
            // Try to get application ID from URL as fallback
            const urlParams = new URLSearchParams(window.location.search);
            const applicationIdFromUrl = urlParams.get('c__applicationId') || urlParams.get('applicationId');
            
            if (applicationIdFromUrl) {
                this._applicationId = applicationIdFromUrl;
            } else {
                this.errorMessage = 'Application ID is missing. Please refresh the page and try again.';
                this.showError = true;
                return;
            }
        }
        
        // Validate the form before continuing
        if (this.validateForm()) {
            this.loading = true;
            
            try {
                // Create application package in Salesforce
                const packageData = {
                    applicationId: this.applicationId,
                    dealerId: this.selectedDealerPackage.DealerId,
                    dealerPackageId: this.selectedDealerPackage.Id,
                    packageName: this.selectedDealerPackage.PackageName,
                    selectedTermId: this.selectedWarrantyTerm.Id,
                    dealerPriceOverride: this.isPriceOverridden ? this.price : null
                };

                // ========== NEW ACTIVE MANAGEMENT CODE ==========
                packageData.recordType = 'Extended_Limited_Warranty';
                
                const result = await savePackageWithActiveManagement({
                    packageDataMap: packageData
                });
                
                let applicationPackageId;
                if (result.success && result.data) {
                    applicationPackageId = result.data.packageId;
                }
                
                /* ========== OLD CODE (RESTORE IF NEEDED) ==========
                let result;
                let applicationPackageId;
                
                if (this.isExistingApplication && this.existingApplicationPackage && this.existingApplicationPackage.Id) {
                    console.log('🔄 Updating existing application package...');
                    const isSamePackage = this.existingApplicationPackage.dealerPackageId === this.selectedDealerPackage.Id;
                    const isSameTerm = this.existingApplicationPackage.selectedTermId === (this.selectedWarrantyTerm ? this.selectedWarrantyTerm.Id : null);
                    
                    if (isSamePackage && isSameTerm) {
                        console.log('✅ No changes detected');
                        applicationPackageId = this.existingApplicationPackage.Id;
                        result = { success: true, recordId: applicationPackageId };
                    } else {
                        try {
                            await this.updateExistingApplicationPackage(this.selectedDealerPackage, this.selectedWarrantyTerm);
                            applicationPackageId = this.existingApplicationPackage.Id;
                            result = { success: true, recordId: applicationPackageId };
                        } catch (updateError) {
                            packageData.recordType = 'Extended_Limited_Warranty';
                            result = await createApplicationPackageFromMap({packageDataMap: packageData});
                            applicationPackageId = result.recordId;
                        }
                    }
                } else {
                    packageData.recordType = 'Extended_Limited_Warranty';
                    result = await createApplicationPackageFromMap({packageDataMap: packageData});
                    applicationPackageId = result.recordId;
                }
                ========== END OLD CODE ========== */
                
                if (result.success) {
                    // Process additional options if any changes exist
                    if (this.hasAdditionalOptionsChanges()) {
                        const optionsResult = await this.processAdditionalOptionsChanges(applicationPackageId);
                        
                        if (!optionsResult.success) {
                            this.errorMessage = 'Warranty package saved, but failed to save additional options: ' + optionsResult.message;
                            this.showError = true;
                            return;
                        }
                    }
                    
                    // Save data to session storage
                    this.saveDataToSession();
                    
                    // Fire warranty completion event to unlock more products tab
                    this.dispatchEvent(new CustomEvent('warrantycomplete', {
                        detail: { 
                            success: true,
                            warrantyData: this.getCurrentData(),
                            applicationId: this.applicationId
                        }
                    }));
                    
                } else {
                    console.error('❌ Failed to create application package:', result.message);
                    this.errorMessage = 'Failed to save warranty selection: ' + result.message;
                    this.showError = true;
                }
                
            } catch (error) {
                console.error('❌ Error in handleContinue:', error);
                this.errorMessage = 'Error processing warranty selection. Please try again.';
                this.showError = true;
            } finally {
                this.loading = false;
            }
        }
    }
    
    /**
     * Handle Save As Quote button click
     * Saves the current warranty selection and then converts the application to a quote
     */
    async handleSaveAsQuote() {
        
        // Check if applicationId is missing
        if (!this.applicationId) {
            // Try to get application ID from URL as fallback
            const urlParams = new URLSearchParams(window.location.search);
            const applicationIdFromUrl = urlParams.get('c__applicationId') || urlParams.get('applicationId');
            
            if (applicationIdFromUrl) {
                this._applicationId = applicationIdFromUrl;
            } else {
                this.errorMessage = 'Application ID is missing. Please refresh the page and try again.';
                this.showError = true;
                return;
            }
        }
        
        // Validate the form before saving
        if (this.validateForm()) {
            this.loading = true;
            
            try {
                // Create application package in Salesforce
                const packageData = {
                    applicationId: this.applicationId,
                    dealerId: this.selectedDealerPackage.DealerId,
                    dealerPackageId: this.selectedDealerPackage.Id,
                    packageName: this.selectedDealerPackage.PackageName,
                    selectedTermId: this.selectedWarrantyTerm.Id
                };
                
                packageData.recordType = 'Extended_Limited_Warranty';
                
                const result = await savePackageWithActiveManagement({
                    packageDataMap: packageData
                });
                
                let applicationPackageId;
                if (result.success && result.data) {
                    applicationPackageId = result.data.packageId;
                }
                
                if (result.success) {
                    // Process additional options if any changes exist
                    if (this.hasAdditionalOptionsChanges()) {
                        const optionsResult = await this.processAdditionalOptionsChanges(applicationPackageId);
                        
                        if (!optionsResult.success) {
                            this.errorMessage = 'Warranty package saved, but failed to save additional options: ' + optionsResult.message;
                            this.showError = true;
                            return;
                        }
                    }
                    
                    // Save data to session storage
                    this.saveDataToSession();
                    
                    // Fire save as quote event to parent component
                    this.dispatchEvent(new CustomEvent('saveasquote', {
                        detail: { 
                            success: true,
                            applicationId: this.applicationId
                        }
                    }));
                    
                } else {
                    console.error('❌ Failed to create application package:', result.message);
                    this.errorMessage = 'Failed to save warranty selection: ' + result.message;
                    this.showError = true;
                }
                
            } catch (error) {
                console.error('❌ Error in handleSaveAsQuote:', error);
                this.errorMessage = 'Error processing warranty selection. Please try again.';
                this.showError = true;
            } finally {
                this.loading = false;
            }
        }
    }
    
    get selectedClaimLabel() {
        const claimOption = this.claimOptions.find(option => option.value === this.selectedClaim);
        return claimOption ? claimOption.label.split('/').slice(2).join('/').trim() : '';
    }
    
    // Check if warranty is unlocked (has selected package)
    get isWarrantyUnlocked() {
        return this.selectedDealerPackage !== null;
    }
    
    // Get warranty status for display
    get warrantyStatus() {
        if (this.selectedDealerPackage) {
            return `✅ Warranty Package Selected: ${this.selectedDealerPackage.PackageName}`;
        }
        return '⚠️ Please select a warranty package';
    }
    
    get hasPackages() {
        return this.dealerPackages && this.dealerPackages.length > 0;
    }

    get showNoPackageDisclaimer() {
        return !this.dealerHasPackages;
    }

    get showVehicleNotEligibleDisclaimer() {
        return this.dealerHasPackages && !this.hasPackages;
    }

    get showPackageList() {
        return !this.showNoPackageDisclaimer && !this.showVehicleNotEligibleDisclaimer;
    }

    get hasSelectedTerm() {
        return this.selectedWarrantyTerm !== null;
    }
    
    get formattedPrice() {
        // Show retail price (before tax) in the sidebar
        if (this._retailPriceDisplay != null) {
            return this.formatPrice(this._retailPriceDisplay);
        }
        return this.formatPrice(this.price);
    }
    
    
    get availableTerms() {
        if (!this.selectedDealerPackage || !this.selectedDealerPackage.warrantyTerms) {
            return [];
        }
        return this._sortTerms(this.selectedDealerPackage.warrantyTerms);
    }
    
    
    get isContinueDisabled() {
        if (this.showNoPackageDisclaimer || this.showVehicleNotEligibleDisclaimer) return false;
        return !this.selectedDealerPackage || !this.selectedWarrantyTerm;
    }

    // Additional methods for the new functionality
    // handleBack method moved to avoid duplicates
    
    confirmDeclineWarranty() {
        this.selectedDealerPackage = null;
        this.selectedWarrantyTerm = null;
        this.price = 0.00;
        this.savedDealerPackageId = null;
        this.savedWarrantyTermId = null;
        this.showDeclineModal = false;
        
        sessionStorage.removeItem('warrantyData');
        this.fireCompletionEvent();
    }
    
    closeWarrantyModal() {
        this.showWarrantyModal = false;
    }
    
    get warrantyStatus() {
        if (this.selectedDealerPackage && this.selectedWarrantyTerm) {
            return `Warranty Selected: ${this.selectedDealerPackage.PackageName} - ${this.selectedWarrantyTerm.packageTermName || this.selectedWarrantyTerm.Name || 'Unknown Term'}`;
        }
        return 'No warranty selected';
    }

    get selectedTermName() {
        if (this.isExistingApplication && this.existingApplicationPackage && this.existingApplicationPackage.selectedTermName) {
            return this.existingApplicationPackage.selectedTermName;
        }
        if (this.selectedWarrantyTerm) {
            return this.selectedWarrantyTerm.packageTermName || this.selectedWarrantyTerm.Name || 'No term selected';
        }
        return 'No term selected';
    }

    get selectedTermDuration() {
        // Month__c not used - return null
        return null;
    }

    get selectedTermMileage() {
        if (this.selectedWarrantyTerm) {
            const mileage = this.selectedWarrantyTerm.mileageRestriction || 0;
            const unit = this.selectedWarrantyTerm.mileageUnit || 'KM';
            return `${mileage} ${unit}`;
        }
        return '0 KM';
    }
    
    // File handling methods
    handleFilesLoaded(event) {
        const fileDetails = event.detail;
        this.packageHasFiles = fileDetails.hasFiles;
        this.packageFileCount = fileDetails.fileCount;
        console.log('📁 Files loaded:', fileDetails);
    }
    
    get showPackageFiles() {
        return this.hasSelectedPackage && this.packageHasFiles;
    }
    
    // Help modal methods
    toggleOptionHelp(event) {
        const helpType = event.currentTarget.dataset.helpType;
        const helpText = event.currentTarget.dataset.helpText;
        
        this.helpModalTitle = helpType === 'inclusion' ? 'What\'s Included' : 'What\'s Excluded';
        this.helpModalText = helpText;
        this.showHelpModal = true;
    }
    
    closeHelpModal() {
        this.showHelpModal = false;
    }
    
    get availableTerms() {
        if (!this.selectedDealerPackage || !this.selectedDealerPackage.warrantyTerms) {
            return [];
        }
        return this._sortTerms(this.selectedDealerPackage.warrantyTerms);
    }
    
    // Back button handler - DUPLICATE REMOVED
    
    // Get included options for the selected package (for side panel)
    get selectedPackageOptions() {
        if (!this.selectedDealerPackage || !this.selectedDealerPackage.options) {
            return [];
        }
        return this.selectedDealerPackage.options.map(option => ({
            id: option.Id || option.id,
            optionName: option.optionName || option.Name || option.label,
            inclusion: option.inclusion,
            exclusion: option.exclusion
        }));
    }
    
    // Get count of included options for the selected package
    get selectedPackageOptionsCount() {
        return this.selectedPackageOptions.length;
    }
    
    // Get available additional options for the selected term
    get availableAdditionalOptions() {
        return this.availableAdditionalOptionsData.map(option => {
            const isSelected = this.selectedNewOptions.includes(option.id);
            return {
                ...option,
                isSelected
            };
        });
    }

    // Get formatted existing application price for display
    get formattedExistingPrice() {
        if (this.isExistingApplication && this.existingApplicationPackage) {
            // Use stored Contract_Premium_Price__c directly from Application_Package__c
            return this.formatPrice(this.existingApplicationPackage.contractPremiumPrice || 0);
        }
        return '0.00';
    }
    
    // Load additional options for the selected term
    async loadAdditionalOptions(termId) {
        try {
            console.log('🔍 Loading additional options for term:', termId);
            
            const result = await getAdditionalOptions({ dealerPackageTermId: termId });
            
            if (result.success) {
                this.availableAdditionalOptionsData = result.data.map(option => ({
                    id: option.Id,
                    optionName: option.optionName,
                    price: this.formatPrice(option.retailPrice || option.netCost || option.price || 0),
                    originalPrice: option.originalPrice || 0,
                    netCost: option.netCost || 0,
                    dealerMarkup: option.dealerMarkup || 0,
                    retailPrice: option.retailPrice || 0,
                    discountType: option.discountType,
                    discountValue: option.discountValue || 0,
                    inclusion: option.inclusion,
                    exclusion: option.exclusion
                }));
                
                console.log('✅ Loaded', this.availableAdditionalOptionsData.length, 'additional options');
            } else {
                console.error('❌ Failed to load additional options:', result.message);
                this.availableAdditionalOptionsData = [];
            }
        } catch (error) {
            console.error('❌ Error loading additional options:', error);
            this.availableAdditionalOptionsData = [];
        }
    }
    
    // Load existing additional options for an application package
    async loadExistingAdditionalOptions(applicationPackageId) {
        try {
            console.log('🔍 Loading existing additional options for application package:', applicationPackageId);
            
            const result = await getExistingAdditionalOptions({ applicationPackageId: applicationPackageId });
            
            if (result.success) {
                this.existingAdditionalOptions = result.data.map(option => ({
                    id: option.Id,
                    optionName: option.optionName,
                    price: this.formatPrice(option.retailPrice || option.price || 0),
                    originalPrice: option.originalPrice || 0,
                    dealerMarkup: option.dealerMarkup || 0,
                    retailPrice: option.retailPrice || 0,
                    discountType: option.discountType,
                    discountValue: option.discountValue || 0,
                    inclusion: option.inclusion,
                    exclusion: option.exclusion,
                    isMarkedForRemoval: false
                }));
                
                console.log('✅ Loaded', this.existingAdditionalOptions.length, 'existing additional options');
            } else {
                console.log('ℹ️ No existing additional options found');
                this.existingAdditionalOptions = [];
            }
        } catch (error) {
            console.error('❌ Error loading existing additional options:', error);
            this.existingAdditionalOptions = [];
        }
    }

    // Handle new additional option selection/deselection (real-time)
    handleAdditionalOptionToggle(event) {
        const optionId = event.target.dataset.optionId;
        const isChecked = event.target.checked;
        
        console.log('🔄 Additional option toggle:', optionId, isChecked);
        
        if (isChecked) {
            if (!this.selectedNewOptions.includes(optionId)) {
                this.selectedNewOptions.push(optionId);
                console.log('✅ Added new option:', optionId);
            }
        } else {
            this.selectedNewOptions = this.selectedNewOptions.filter(id => id !== optionId);
            console.log('❌ Removed new option:', optionId);
        }
        
        // Real-time price update (no DML)
        this.updatePrice();
        console.log('💰 Price updated, selected new options:', this.selectedNewOptions.length);
        
        // Debug: Log the actual option data to check for Proxy issues
        const selectedOption = this.availableAdditionalOptionsData.find(opt => opt.id === optionId);
        console.log('🔍 Selected option data:', selectedOption);
        console.log('🔍 Selected option type:', typeof selectedOption);
        if (selectedOption) {
            console.log('🔍 Option properties:', Object.keys(selectedOption));
            console.log('🔍 Option retailPrice:', selectedOption.retailPrice);
        }
    }

    // Handle removal of existing additional options (real-time)
    handleRemoveExistingOption(event) {
        const optionId = event.currentTarget.dataset.optionId;
        
        console.log('🗑️ Remove button clicked for option:', optionId);
        console.log('🔍 Event target:', event.currentTarget);
        console.log('🔍 Dataset:', event.currentTarget.dataset);
        console.log('🔍 Current optionsToRemove:', this.optionsToRemove);
        console.log('🔍 Current existingAdditionalOptions:', this.existingAdditionalOptions.map(opt => opt.id));
        
        if (!optionId) {
            console.error('❌ No optionId found in dataset');
            return;
        }
        
        // Toggle removal state
        if (this.optionsToRemove.includes(optionId)) {
            // Undo removal
            this.optionsToRemove = this.optionsToRemove.filter(id => id !== optionId);
            console.log('↩️ Undid removal of option:', optionId);
        } else {
            // Mark for removal
            this.optionsToRemove.push(optionId);
            console.log('🗑️ Marked option for removal:', optionId);
        }
        
        console.log('🔍 Updated optionsToRemove:', this.optionsToRemove);
        
        // Update visual state - create new array reference to trigger reactivity
        this.existingAdditionalOptions = [...this.existingAdditionalOptions.map(option => ({
            ...option,
            isMarkedForRemoval: this.optionsToRemove.includes(option.id)
        }))];
        
        console.log('🔍 Updated existingAdditionalOptions visual state');
        console.log('🔍 Options marked for removal:', this.existingAdditionalOptions.filter(opt => opt.isMarkedForRemoval).map(opt => opt.id));
        
        // Real-time price update (no DML)
        this.updatePrice();
        console.log('💰 Price updated, options to remove:', this.optionsToRemove.length);
        
        // Force re-render to update visual state
        this.renderKey++;
        console.log('🎨 Forced re-render with renderKey:', this.renderKey);
    }

    // Check if there are any additional options changes to save
    hasAdditionalOptionsChanges() {
        return this.selectedNewOptions.length > 0 || this.optionsToRemove.length > 0;
    }

    // Save additional options changes to Salesforce (called on Continue button)
    async processAdditionalOptionsChanges(applicationPackageId) {
        // Double-check if there are actually changes to save
        const hasNewOptions = this.selectedNewOptions && this.selectedNewOptions.length > 0;
        const hasRemoveOptions = this.optionsToRemove && this.optionsToRemove.length > 0;
        
        if (!hasNewOptions && !hasRemoveOptions) {
            console.log('ℹ️ No additional options changes to save - arrays are empty');
            return { success: true };
        }
        
        try {
            console.log('💾 Saving additional options changes...');
            console.log('📝 Options to add:', this.selectedNewOptions, 'Length:', this.selectedNewOptions.length);
            console.log('🗑️ Options to remove:', this.optionsToRemove, 'Length:', this.optionsToRemove.length);
            
            // Convert to plain arrays to avoid Proxy issues
            const optionsToAddArray = Array.from(this.selectedNewOptions || []);
            const optionsToRemoveArray = Array.from(this.optionsToRemove || []);
            
            console.log('🔍 Converted arrays:');
            console.log('🔍 optionsToAddArray:', optionsToAddArray);
            console.log('🔍 optionsToRemoveArray:', optionsToRemoveArray);
            
            // Debug: Check the actual option data being sent
            if (optionsToAddArray.length > 0) {
                console.log('🔍 Debugging options to add:');
                console.log('🔍 Available options data:', this.availableAdditionalOptionsData);
                console.log('🔍 Available options count:', this.availableAdditionalOptionsData.length);
                
                optionsToAddArray.forEach((optionId, index) => {
                    const optionData = this.availableAdditionalOptionsData.find(opt => opt.id === optionId);
                    console.log(`🔍 Option ${index}: ID=${optionId}, Found=`, !!optionData);
                    if (optionData) {
                        console.log(`🔍 Option ${index} Data:`, optionData);
                    } else {
                        console.error(`❌ Option ${index} NOT FOUND in availableAdditionalOptionsData!`);
                        console.log('🔍 All available option IDs:', this.availableAdditionalOptionsData.map(opt => opt.id));
                    }
                });
            }
            
            const optionsData = {
                applicationPackageId: applicationPackageId,
                applicationId: this.applicationId,
                optionsToAdd: optionsToAddArray,
                optionsToRemove: optionsToRemoveArray
            };
            
            console.log('🔍 Final optionsData being sent to Apex:', JSON.stringify(optionsData, null, 2));
            
            // Additional validation: Check if we can access the option data properly
            if (optionsToAddArray.length > 0) {
                console.log('🔍 Final validation before Apex call:');
                for (let i = 0; i < optionsToAddArray.length; i++) {
                    const optionId = optionsToAddArray[i];
                    const option = this.availableAdditionalOptionsData.find(opt => opt.id === optionId);
                    
                    console.log(`🔍 Validating option ${i}:`);
                    console.log(`  - ID: ${optionId}`);
                    console.log(`  - Found: ${!!option}`);
                    console.log(`  - Type: ${typeof option}`);
                    
                    if (option) {
                        // Try to access properties that might be causing issues
                        try {
                            console.log(`  - optionName: ${option.optionName}`);
                            console.log(`  - retailPrice: ${option.retailPrice}`);
                            console.log(`  - All properties: ${JSON.stringify(option, null, 2)}`);
                        } catch (accessError) {
                            console.error(`❌ Error accessing option properties:`, accessError);
                        }
                    }
                }
            }
            
            const result = await updateAdditionalOptions({ optionsData: optionsData });
            
            if (result.success) {
                console.log('✅ Additional options saved successfully:', result.message);
                
                // Reset state after successful save
                this.selectedNewOptions = [];
                this.optionsToRemove = [];
                
                // Reload existing options to reflect changes
                await this.loadExistingAdditionalOptions(applicationPackageId);
                
                return { success: true };
            } else {
                console.error('❌ Failed to save additional options:', result.message);
                return { success: false, message: result.message };
            }
        } catch (error) {
            console.error('❌ Error saving additional options:', error);
            return { success: false, message: error.message };
        }
    }

    // Get existing additional options for display
    get existingAdditionalOptionsDisplay() {
        if (!this.existingAdditionalOptions || this.existingAdditionalOptions.length === 0) {
            console.log('🎨 existingAdditionalOptionsDisplay: no existing options');
            return [];
        }
        
        const displayOptions = this.existingAdditionalOptions.map(option => {
            const isMarkedForRemoval = option.isMarkedForRemoval || false;
            const displayOption = {
                ...option,
                cssClass: isMarkedForRemoval ? 'additional-option-item-card option-removing' : 'additional-option-item-card',
                textClass: isMarkedForRemoval ? 'additional-option-item-text option-removing-text' : 'additional-option-item-text',
                priceClass: isMarkedForRemoval ? 'additional-option-price option-removing-text' : 'additional-option-price',
                buttonLabel: isMarkedForRemoval ? 'Undo Remove' : 'Remove',
                buttonTitle: isMarkedForRemoval ? 'Undo Remove' : 'Remove Option',
                buttonVariant: isMarkedForRemoval ? 'neutral' : 'destructive',
                priceDisplay: isMarkedForRemoval ? 'strike-through' : 'normal'
            };
            
            return displayOption;
        });

        console.log('🎨 existingAdditionalOptionsDisplay called, returning:', displayOptions.length, 'options');
        return displayOptions;
    }

    // Get available additional options for display (exclude already selected options)
    get availableAdditionalOptionsDisplay() {
        // Start with available options from the current term (Dealer_Package_Option__c)
        let availableOptions = [...(this.availableAdditionalOptionsData || [])];
        
        // Get IDs of already selected options (Application_Package_Option__c)
        const selectedOptionIds = this.existingAdditionalOptions
            .filter(option => !this.optionsToRemove.includes(option.id))
            .map(option => option.id);
        
        // Filter out already selected options
        const filteredOptions = availableOptions.filter(option => {
            return !selectedOptionIds.includes(option.id);
        });
        
        // Get IDs of options already in filteredOptions to avoid duplicates
        const existingFilteredIds = new Set(filteredOptions.map(opt => opt.id));
        
        // Add back options that are marked for removal (they become available again)
        // Only add if they're not already in the filtered list
        const removedOptionIds = this.optionsToRemove || [];
        if (removedOptionIds.length > 0) {
            const removedOptions = this.existingAdditionalOptions
                .filter(option => removedOptionIds.includes(option.id))
                .filter(option => !existingFilteredIds.has(option.id)) // Avoid duplicates
                .map(option => ({
                    id: option.id,
                    optionName: option.optionName,
                    price: option.price,
                    originalPrice: option.originalPrice,
                    dealerMarkup: option.dealerMarkup,
                    retailPrice: option.retailPrice,
                    discountType: option.discountType,
                    discountValue: option.discountValue,
                    inclusion: option.inclusion,
                    exclusion: option.exclusion
                }));

            filteredOptions.push(...removedOptions);
        }

        // Map to display format with selection state
        return filteredOptions.map(option => ({
            ...option,
            isSelected: this.selectedNewOptions.includes(option.id),
            cssClass: this.selectedNewOptions.includes(option.id) ? 'available-option-card option-selected' : 'available-option-card'
        }));
    }

    // Check if we have existing additional options
    get hasExistingAdditionalOptions() {
        return this.existingAdditionalOptions && this.existingAdditionalOptions.length > 0;
    }

    // Check if we have available additional options
    get hasAvailableAdditionalOptions() {
        const hasOptions = this.availableAdditionalOptionsDisplay && this.availableAdditionalOptionsDisplay.length > 0;
        console.log('🔍 hasAvailableAdditionalOptions:', hasOptions, 'Count:', this.availableAdditionalOptionsDisplay?.length || 0);
        return hasOptions;
    }

    // Check if there are no additional options available
    get hasNoAdditionalOptions() {
        const hasExisting = this.existingAdditionalOptions && this.existingAdditionalOptions.length > 0;
        const hasAvailable = this.availableAdditionalOptionsDisplay && this.availableAdditionalOptionsDisplay.length > 0;
        return !hasExisting && !hasAvailable;
    }

    // Get additional options pricing for price breakdown
    get additionalOptionsPricing() {
        const existingOptionsPrice = this.existingAdditionalOptions
            .filter(option => !this.optionsToRemove.includes(option.id))
            .reduce((total, option) => total + (option.retailPrice || 0), 0);
        
        const newOptionsPrice = this.selectedNewOptions.reduce((total, optionId) => {
            const option = this.availableAdditionalOptionsData.find(opt => opt.id === optionId);
            return total + (option ? (option.retailPrice || option.netCost || 0) : 0);
        }, 0);

        return {
            existingOptionsPrice,
            newOptionsPrice,
            totalAdditionalOptionsPrice: existingOptionsPrice + newOptionsPrice,
            formattedExistingOptionsPrice: this.formatPrice(existingOptionsPrice),
            formattedNewOptionsPrice: this.formatPrice(newOptionsPrice),
            formattedTotalAdditionalOptionsPrice: this.formatPrice(existingOptionsPrice + newOptionsPrice)
        };
    }

    // Check if there are any selected additional options (existing or new)
    get hasSelectedAdditionalOptions() {
        const existingCount = this.existingAdditionalOptions
            ? this.existingAdditionalOptions.filter(opt => !this.optionsToRemove.includes(opt.id)).length
            : 0;
        const newCount = this.selectedNewOptions ? this.selectedNewOptions.length : 0;
        return (existingCount + newCount) > 0;
    }

    // Get itemized breakdown of all selected additional options
    get selectedAdditionalOptionsBreakdown() {
        const items = [];
        
        // Existing additional options (not marked for removal)
        if (this.existingAdditionalOptions) {
            this.existingAdditionalOptions
                .filter(opt => !this.optionsToRemove.includes(opt.id))
                .forEach(option => {
                    items.push({
                        id: option.id,
                        name: option.optionName || 'Unknown Option',
                        price: option.retailPrice || 0,
                        formattedPrice: this.formatPrice(option.retailPrice || 0),
                        netCost: option.netCost || 0,
                        formattedNetCost: this.formatPrice(option.netCost || 0)
                    });
                });
        }
        
        // Newly selected additional options
        if (this.selectedNewOptions && this.availableAdditionalOptionsData) {
            this.selectedNewOptions.forEach(optionId => {
                const option = this.availableAdditionalOptionsData.find(opt => opt.id === optionId);
                if (option) {
                    items.push({
                        id: option.id,
                        name: option.optionName || 'Unknown Option',
                        price: option.retailPrice || option.netCost || 0,
                        formattedPrice: this.formatPrice(option.retailPrice || option.netCost || 0),
                        netCost: option.netCost || 0,
                        formattedNetCost: this.formatPrice(option.netCost || 0)
                    });
                }
            });
        }
        
        return items;
    }

    // Initialize original warranty data for change tracking
    initializeOriginalWarrantyData() {
        this.originalWarrantyData = {
            selectedDealerPackageId: this.selectedDealerPackage?.Id || null,
            selectedWarrantyTermId: this.selectedWarrantyTerm?.Id || null,
            selectedAdditionalOptions: [...(this.selectedNewOptions || [])],
            existingAdditionalOptions: [...(this.existingAdditionalOptions || [])]
        };
        this.warrantyChangedFields.clear();
        console.log('🔄 Original warranty data initialized for change tracking');
    }
    
    // Track warranty field changes
    trackWarrantyChange(changeType, oldValue, newValue) {
        console.log('🔍 Tracking warranty change:', {
            changeType,
            oldValue,
            newValue,
            hasChanged: oldValue !== newValue
        });
        
        if (oldValue !== newValue) {
            this.warrantyChangedFields.add(changeType);
            console.log('📝 Warranty change marked:', changeType);
        } else {
            this.warrantyChangedFields.delete(changeType);
            console.log('↩️ Warranty change reverted:', changeType);
        }
        
        console.log('📋 Total warranty changes:', Array.from(this.warrantyChangedFields));
        
        // AUTO-SAVE DISABLED - User must click Continue to save
        // With active package management, we don't auto-save package changes
        /* OLD AUTO-SAVE CODE (disabled)
        if (this.isExistingApplication && this.existingApplicationPackage) {
            this.debouncedWarrantyAutoSave();
        }
        */
        console.log('ℹ️ Auto-save disabled - changes will save on Continue click');
    }
    
    // Debounced auto-save for warranty changes
    debouncedWarrantyAutoSave() {
        // Clear existing timeout
        if (this.warrantyAutoSaveTimeout) {
            clearTimeout(this.warrantyAutoSaveTimeout);
        }
        
        // Set new timeout for auto-save (2 seconds after last change)
        this.warrantyAutoSaveTimeout = setTimeout(() => {
            this.autoSaveWarrantyChanges();
        }, 2000);
        
        console.log('⏱️ Warranty auto-save scheduled in 2 seconds...');
    }
    
    // Auto-save only changed warranty fields
    async autoSaveWarrantyChanges() {
        if (this.warrantyChangedFields.size === 0) {
            console.log('ℹ️ No warranty changes to auto-save');
            return;
        }
        
        if (!this.isExistingApplication || !this.existingApplicationPackage) {
            console.log('ℹ️ Skipping warranty auto-save for new application');
            return;
        }
        
        try {
            console.log('💾 Auto-saving warranty changes:', Array.from(this.warrantyChangedFields));
            
            // Prepare selective update data
            const updateData = {
                applicationPackageId: this.existingApplicationPackage.Id,
                applicationId: this.applicationId
            };
            
            // Add changed fields
            if (this.warrantyChangedFields.has('package')) {
                updateData.dealerPackageId = this.selectedDealerPackage?.Id;
            }
            
            if (this.warrantyChangedFields.has('term')) {
                updateData.dealerPackageTermId = this.selectedWarrantyTerm?.Id;
            }
            
            // Call selective update method (to be implemented)
            const result = await updateWarrantyFieldsSelective({ updateData: updateData });
            
            if (result.success) {
                console.log('✅ Warranty auto-save successful');
                
                // Update original data and clear changed fields
                this.initializeOriginalWarrantyData();
                
                // Show subtle success indicator
                this.showWarrantyAutoSaveSuccess();
            } else {
                console.error('❌ Warranty auto-save failed:', result.message);
            }
        } catch (error) {
            console.error('❌ Warranty auto-save error:', error);
        }
    }
    
    // Show warranty auto-save success indicator
    showWarrantyAutoSaveSuccess() {
        console.log('✅ Warranty auto-save success indicator shown');
        // You can implement a subtle visual indicator here
    }
    
    // Confirm term change when user has selected additional options
    async confirmTermChangeWithOptions(newTerm) {
        return new Promise((resolve) => {
            const selectedCount = this.selectedNewOptions.length;
            const termName = newTerm.packageTermName || newTerm.Name;
            
            // Create confirmation dialog
            const confirmed = confirm(
                `You have ${selectedCount} additional option(s) selected for the current term.\n\n` +
                `Switching to "${termName}" will clear these selections because additional options are specific to each term.\n\n` +
                `Do you want to continue?`
            );
            
            resolve(confirmed);
        });
    }
    
    // Clear additional options when switching terms
    clearAdditionalOptionsForTermSwitch() {
        console.log('🔄 Clearing additional options for term switch');
        console.log('🔄 Previous selections - new:', this.selectedNewOptions.length, 'existing:', this.existingAdditionalOptions.length);
        
        // Clear ALL additional option selections
        this.selectedNewOptions = [];
        this.existingAdditionalOptions = [];
        this.selectedAdditionalOptions = [];
        this.optionsToRemove = [];
        
        console.log('🧹 All additional options cleared for term switch');
    }
    
    // Show info message to user
    showInfoMessage(message) {
        // You can implement a toast or modal here
        // For now, using console and alert
        console.log('ℹ️', message);
        
        // Simple implementation - you can replace with a proper toast component
        const event = new ShowToastEvent({
            title: 'Information',
            message: message,
            variant: 'info',
            mode: 'dismissable'
        });
        this.dispatchEvent(event);
    }

    get showContinueButton() {
        return !this.loading && !this.fieldDisabled;
    }
    
    get isPlanTypeView() {
        return this.currentView === 'planTypes';
    }

    get isPackageDetailsView() {
        return this.currentView === 'packageDetails';
    }

    get isQuoteStatus() {
        return this.applicationStatus === 'Quote';
    }

    get planTypeGroups() {
        return this.buildPlanTypeGroups();
    }

    get hasPlanTypes() {
        const hasPlanTypes = this.planTypeGroups.length > 0;
        console.log('🔍 WARRANTY - hasPlanTypes getter called, planTypeGroups.length: ' + this.planTypeGroups.length + ', returning: ' + hasPlanTypes);
        return hasPlanTypes;
    }

    buildPlanTypeGroups() {
        console.log('🔍 WARRANTY - buildPlanTypeGroups called');
        console.log('🔍 WARRANTY - allDealerPackages:', this.allDealerPackages);
        console.log('🔍 WARRANTY - allDealerPackages length:', this.allDealerPackages ? this.allDealerPackages.length : 'null/undefined');
        
        if (!this.allDealerPackages || this.allDealerPackages.length === 0) {
            console.log('❌ WARRANTY - No allDealerPackages or empty array, returning empty groups');
            return [];
        }

        const groupsMap = new Map();

        this.allDealerPackages.forEach((pkg, index) => {
            const planTypeKey = pkg.planTypeId || this.otherPlanTypeKey;
            const planTypeLabel = pkg.planTypeName || 'Other Packages';
            
            console.log('🔍 WARRANTY - Package ' + index + ':', {
                id: pkg.Id,
                name: pkg.Name,
                planTypeId: pkg.planTypeId,
                planTypeName: pkg.planTypeName,
                planTypeKey: planTypeKey,
                planTypeLabel: planTypeLabel
            });

            if (!groupsMap.has(planTypeKey)) {
                console.log('✅ WARRANTY - Creating new group for planTypeKey: ' + planTypeKey + ', label: ' + planTypeLabel);
                groupsMap.set(planTypeKey, {
                    key: planTypeKey,
                    label: planTypeLabel,
                    planTypeDescription: pkg.planTypeDescription || '',
                    packageCount: 0
                });
            }

            const group = groupsMap.get(planTypeKey);
            if (!group.planTypeDescription && pkg.planTypeDescription) {
                group.planTypeDescription = pkg.planTypeDescription;
            }
            group.packageCount += 1;
            console.log('🔍 WARRANTY - Group ' + planTypeKey + ' now has ' + group.packageCount + ' packages');
        });

        const groups = Array.from(groupsMap.values());
        console.log('🔍 WARRANTY - Created ' + groups.length + ' groups before sorting:', groups);
        
        groups.sort((a, b) => {
            if (a.key === this.otherPlanTypeKey) return 1;
            if (b.key === this.otherPlanTypeKey) return -1;
            return a.label.localeCompare(b.label);
        });

        groups.forEach(group => {
            group.packageCountLabel = group.packageCount === 1 ? 'Package' : 'Packages';
            const gradientClass = this.getPackageGradientClass(group.label, group.key);
            group.tileClass = `package-list-item ${gradientClass}`.trim();
        });

        console.log('✅ WARRANTY - Final planTypeGroups:', groups);
        console.log('✅ WARRANTY - Returning ' + groups.length + ' groups');
        return groups;
    }

    createPackageListTile(pkg) {
        const baseName = pkg.PackageName || pkg.Name || 'Warranty';
        const displayName = `${baseName} WARRANTY`;
        const gradientClass = this.getPackageGradientClass(baseName, pkg.Id);
        const isActive = this.selectedDealerPackage && this.selectedDealerPackage.Id === pkg.Id;
        const warrantyLabel = pkg.planTypeName || baseName;

        return {
            id: pkg.Id,
            displayName,
            tileClass: `package-list-item ${gradientClass} ${isActive ? 'package-list-item--active' : ''}`.trim(),
            warrantyLabel
        };
    }

    setSelectedPlanTypeFromKey(planTypeKey) {
        const groups = this.buildPlanTypeGroups();
        const selectedGroup = groups.find(group => group.key === planTypeKey);
        if (selectedGroup) {
            this.selectedPlanType = selectedGroup;
        } else {
            this.selectedPlanType = null;
        }
    }

    async handlePlanTypeSelection(event) {
        const planTypeKey = event.currentTarget?.dataset?.planTypeKey;
        const planTypeLabel = event.currentTarget?.dataset?.planTypeLabel;
        const planTypeDescription = event.currentTarget?.dataset?.planTypeDescription || '';
        if (!planTypeKey) {
            return;
        }
        this.selectedPlanTypeKey = planTypeKey;
        this.selectedPlanType = {
            key: planTypeKey,
            label: planTypeLabel,
            planTypeDescription
        };
        const filteredPackages = this.allDealerPackages.filter(pkg => (pkg.planTypeId || this.otherPlanTypeKey) === planTypeKey);
        if (!filteredPackages.length) {
            this.showErrorMessage('No packages available for this plan type.');
            return;
        }

        this.dealerPackages = filteredPackages;
        this.selectedDealerPackage = null; // Don't auto-select - show all packages
        this.selectedWarrantyTerm = null;
        this.currentView = 'packageDetails'; // Go to package details view
    }

    get hasSelectedPackage() {
        return this.selectedDealerPackage !== null;
    }

    getPackageGradientClass(name, packageId) {
        const gradients = [
            'gradient-powertrain',
            'gradient-premium',
            'gradient-essential',
            'gradient-luxury',
            'gradient-diamond',
            'gradient-custom',
            'gradient-onyx',
            'gradient-graphite',
            'gradient-midnight'
        ];

        if (name) {
            const normalized = name.toLowerCase();

            if (normalized.includes('powertrain')) {
                return 'gradient-powertrain';
            }
            if (normalized.includes('premium')) {
                return 'gradient-premium';
            }
            if (normalized.includes('essential')) {
                return 'gradient-essential';
            }
            if (normalized.includes('luxury')) {
                return 'gradient-luxury';
            }
            if (normalized.includes('diamond')) {
                return 'gradient-diamond';
            }
            if (normalized.includes('custom')) {
                return 'gradient-custom';
            }
        }

        if (!this.gradientAssignments[packageId]) {
            const randomIndex = Math.floor(Math.random() * gradients.length);
            this.gradientAssignments[packageId] = gradients[randomIndex];
        }

        return this.gradientAssignments[packageId];
    }
    
    // Get gradient class for selected package
    get selectedPackageGradientClass() {
        if (!this.selectedDealerPackage) {
            return 'gradient-default';
        }
        const baseName = this.selectedDealerPackage.PackageName || this.selectedDealerPackage.Name || '';
        return this.getPackageGradientClass(baseName, this.selectedDealerPackage.Id);
    }
    
    // Compose header banner class for selected package
    get packageHeaderBannerClass() {
        return `package-header-banner ${this.selectedPackageGradientClass}`;
    }
    
    // Selected package title for header
    get selectedPackageTitle() {
        if (this.selectedPlanType && this.selectedPlanType.label) {
            return this.selectedPlanType.label;
        }
        if (this.selectedDealerPackage && this.selectedDealerPackage.planTypeName) {
            return this.selectedDealerPackage.planTypeName;
        }
        if (this.selectedDealerPackageName) {
            return `${this.selectedDealerPackageName} Warranty`;
        }
        return '';
    }
    
    // Rich text description for selected package
    get selectedPackageDescription() {
        if (!this.selectedDealerPackage) {
            return this.selectedPlanType?.planTypeDescription || '';
        }
        if (this.selectedPlanType?.planTypeDescription) {
            return this.selectedPlanType.planTypeDescription;
        }
        if (this.selectedDealerPackage.planTypeDescription) {
            return this.selectedDealerPackage.planTypeDescription;
        }
        // Check PackageDescription from DTO (comes from Package_Description__c field)
        return this.selectedDealerPackage.PackageDescription ||
               this.selectedDealerPackage.Package_Description__c ||
               this.selectedDealerPackage.Description ||
               '';
    }
    
    get warrantyTermGroups() {
        if (!this.selectedDealerPackage || !this.selectedDealerPackage.warrantyTerms) {
            return [];
        }

        const groupsMap = new Map();

        this._sortTerms(this.selectedDealerPackage.warrantyTerms).forEach(term => {
            const perClaimLimitValue = Number(term.perClaimLimit ?? 0);
            const deductibleValue = Number(term.deductible ?? 0);
            const groupKey = `${perClaimLimitValue}-${deductibleValue}`;
            const groupLabel = `${this.formatPrice(perClaimLimitValue)} Per Claim, ${this.formatPrice(deductibleValue)} Deductible`;

            if (!groupsMap.has(groupKey)) {
                groupsMap.set(groupKey, {
                    key: groupKey,
                    label: groupLabel,
                    perClaimLimit: perClaimLimitValue,
                    deductible: deductibleValue,
                    terms: []
                });
            }

            const isTermSelected = this.selectedWarrantyTerm && this.selectedWarrantyTerm.Id === term.Id;
            const durationLabel = term.packageTermName || term.Name || 'Unknown Term';
            const normalizedMileageUnit = (term.mileageUnit || 'KM').toUpperCase();
            const mileageValue = Number(term.mileageRestriction || 0);
            const isUnlimitedMileage = !mileageValue || mileageValue === 0 || normalizedMileageUnit === 'UNLIMITED';
            const mileageDisplay = isUnlimitedMileage
                ? `Unlimited ${(term.mileageUnit || 'KM').toLowerCase()}`
                : `${Number(mileageValue).toLocaleString('en-CA')} ${term.mileageUnit || 'KM'}`;

            groupsMap.get(groupKey).terms.push({
                id: term.Id,
                name: term.packageTermName || term.Name || 'Unknown Term',
                durationLabel,
                mileageDisplay,
                isUnlimitedMileage,
                price: this.formatPrice(term.totalPrice || term.netCost || 0),
                actionLabel: isTermSelected ? 'Selected' : 'Select',
                rowClass: isTermSelected ? 'term-row selected' : 'term-row',
                mileageClass: isUnlimitedMileage ? 'term-row-mileage unlimited' : 'term-row-mileage'
            });
        });

        return Array.from(groupsMap.values());
    }

    get totalWarrantyTermsCount() {
        return this.warrantyTermGroups.reduce((count, group) => count + group.terms.length, 0);
    }

    get hasWarrantyTerms() {
        return this.totalWarrantyTermsCount > 0;
    }
    
    // Get all packages with their tiers and terms for accordion display
    // Returns all packages grouped by plan type, each group with header info + packages+terms
    get planTypeGroupsWithPackageTerms() {
        if (!this.allDealerPackages || this.allDealerPackages.length === 0) return [];
        const groupsMap = new Map();
        this.allDealerPackages.forEach(pkg => {
            const key = pkg.planTypeId || this.otherPlanTypeKey;
            const label = pkg.planTypeName || 'Other Packages';
            const description = pkg.planTypeDescription || '';
            if (!groupsMap.has(key)) {
                const gradientClass = this.getPackageGradientClass(label, key);
                groupsMap.set(key, {
                    key,
                    label,
                    description,
                    hasDescription: !!description,
                    headerClass: `plan-type-section-header ${gradientClass}`,
                    packagesWithTerms: []
                });
            }
            groupsMap.get(key).packagesWithTerms.push(this.buildPackageWithTerms(pkg));
        });
        return Array.from(groupsMap.values()).sort((a, b) => {
            if (a.key === this.otherPlanTypeKey) return 1;
            if (b.key === this.otherPlanTypeKey) return -1;
            return a.label.localeCompare(b.label);
        });
    }

    buildPackageWithTerms(pkg) {
        const hasTiers = pkg.tiers && pkg.tiers.length > 0;
        const hasTerms = pkg.warrantyTerms && pkg.warrantyTerms.length > 0;
        if (!hasTiers && !hasTerms) {
            return { id: pkg.Id, name: 'No Terms Available', terms: [], tiers: [], hasTerms: false, hasTiers: false };
        }
        const firstTerm = hasTiers && pkg.tiers[0]?.terms?.[0]
            ? pkg.tiers[0].terms[0]
            : (hasTerms ? pkg.warrantyTerms[0] : null);
        if (!firstTerm) {
            return { id: pkg.Id, name: 'No Terms Available', terms: [], tiers: [], hasTerms: false, hasTiers: false };
        }
        const perClaimLimitValue = Number(firstTerm.perClaimLimit ?? 0);
        const deductibleValue = Number(firstTerm.deductible ?? 0);
        const packageLabel = `${this.formatPrice(perClaimLimitValue)} Per Claim, ${this.formatPrice(deductibleValue)} Deductible`;
        const processedTiers = hasTiers ? pkg.tiers.map(tier => {
            const formattedTerms = this._sortTerms(tier.terms || []).map(term => {
                const isTermSelected = this.selectedWarrantyTerm &&
                    this.selectedWarrantyTerm.Id === term.Id &&
                    this.selectedDealerPackage &&
                    this.selectedDealerPackage.Id === pkg.Id;
                return { id: term.Id, name: term.packageTermName || term.Name || 'Unknown Term', price: this.formatPrice(term.totalPrice || term.netCost || 0), rowClass: isTermSelected ? 'term-row selected' : 'term-row', packageId: pkg.Id };
            });
            let tierDisplayName = tier.Name || 'Tier';
            if (tier.mileageRestrictionStart != null || tier.mileageRestrictionEnd != null) {
                const start = tier.mileageRestrictionStart != null ? this.formatMileage(tier.mileageRestrictionStart) : '';
                const end = tier.mileageRestrictionEnd != null ? this.formatMileage(tier.mileageRestrictionEnd) : '';
                const unit = tier.mileageUnit || 'KM';
                if (start && end) tierDisplayName = `${tier.Name} (${start} - ${end} ${unit})`;
                else if (start) tierDisplayName = `${tier.Name} (${start}+ ${unit})`;
                else if (end) tierDisplayName = `${tier.Name} (up to ${end} ${unit})`;
            }
            return { id: tier.Id || 'tier-' + Math.random(), name: tierDisplayName, terms: formattedTerms, hasTerms: formattedTerms.length > 0 };
        }) : [];
        const formattedTerms = hasTerms ? this._sortTerms(pkg.warrantyTerms).map(term => {
            const isTermSelected = this.selectedWarrantyTerm &&
                this.selectedWarrantyTerm.Id === term.Id &&
                this.selectedDealerPackage &&
                this.selectedDealerPackage.Id === pkg.Id;
            return { id: term.Id, name: term.packageTermName || term.Name || 'Unknown Term', price: this.formatPrice(term.totalPrice || term.netCost || 0), rowClass: isTermSelected ? 'term-row selected' : 'term-row', packageId: pkg.Id };
        }) : [];
        return { id: pkg.Id, name: packageLabel, terms: formattedTerms, tiers: processedTiers, hasTerms: formattedTerms.length > 0, hasTiers: processedTiers.length > 0 };
    }

    get packagesWithTermGroups() {
        if (!this.dealerPackages || this.dealerPackages.length === 0) {
            return [];
        }

        return this.dealerPackages.map(pkg => {
            // Use tiers if available, otherwise fall back to terms for backward compatibility
            const hasTiers = pkg.tiers && pkg.tiers.length > 0;
            const hasTerms = pkg.warrantyTerms && pkg.warrantyTerms.length > 0;
            
            if (!hasTiers && !hasTerms) {
                return {
                    id: pkg.Id,
                    name: 'No Terms Available',
                    terms: [],
                    tiers: [],
                    hasTerms: false,
                    hasTiers: false
                };
            }

            // Get per claim limit and deductible from first term for accordion label
            const firstTerm = hasTiers && pkg.tiers[0]?.terms?.[0] 
                ? pkg.tiers[0].terms[0] 
                : (hasTerms ? pkg.warrantyTerms[0] : null);
            
            if (!firstTerm) {
                return {
                    id: pkg.Id,
                    name: 'No Terms Available',
                    terms: [],
                    tiers: [],
                    hasTerms: false,
                    hasTiers: false
                };
            }
            
            const perClaimLimitValue = Number(firstTerm.perClaimLimit ?? 0);
            const deductibleValue = Number(firstTerm.deductible ?? 0);
            const packageLabel = `${this.formatPrice(perClaimLimitValue)} Per Claim, ${this.formatPrice(deductibleValue)} Deductible`;

            // Process tiers (NEW: Grouped structure)
            const processedTiers = hasTiers ? pkg.tiers.map(tier => {
                const formattedTerms = this._sortTerms(tier.terms || []).map(term => {
                    const isTermSelected = this.selectedWarrantyTerm && 
                                          this.selectedWarrantyTerm.Id === term.Id &&
                                          this.selectedDealerPackage && 
                                          this.selectedDealerPackage.Id === pkg.Id;

                    return {
                        id: term.Id,
                        name: term.packageTermName || term.Name || 'Unknown Term',
                        price: this.formatPrice(term.totalPrice || term.netCost || 0),
                        rowClass: isTermSelected ? 'term-row selected' : 'term-row',
                        packageId: pkg.Id
                    };
                });

                // Build tier display name with mileage restrictions if available
                let tierDisplayName = tier.Name || 'Tier';
                if (tier.mileageRestrictionStart != null || tier.mileageRestrictionEnd != null) {
                    const start = tier.mileageRestrictionStart != null ? this.formatMileage(tier.mileageRestrictionStart) : '';
                    const end = tier.mileageRestrictionEnd != null ? this.formatMileage(tier.mileageRestrictionEnd) : '';
                    const unit = tier.mileageUnit || 'KM';
                    if (start && end) {
                        tierDisplayName = `${tier.Name} (${start} - ${end} ${unit})`;
                    } else if (start) {
                        tierDisplayName = `${tier.Name} (${start}+ ${unit})`;
                    } else if (end) {
                        tierDisplayName = `${tier.Name} (up to ${end} ${unit})`;
                    }
                }

                return {
                    id: tier.Id || 'tier-' + Math.random(),
                    name: tierDisplayName,
                    terms: formattedTerms,
                    hasTerms: formattedTerms.length > 0
                };
            }) : [];

            // Format all terms for backward compatibility (flat list)
            const formattedTerms = hasTerms ? this._sortTerms(pkg.warrantyTerms).map(term => {
                const isTermSelected = this.selectedWarrantyTerm && 
                                      this.selectedWarrantyTerm.Id === term.Id &&
                                      this.selectedDealerPackage && 
                                      this.selectedDealerPackage.Id === pkg.Id;

                return {
                    id: term.Id,
                    name: term.packageTermName || term.Name || 'Unknown Term',
                    price: this.formatPrice(term.totalPrice || term.netCost || 0),
                    rowClass: isTermSelected ? 'term-row selected' : 'term-row',
                    packageId: pkg.Id
                };
            }) : [];

            return {
                id: pkg.Id,
                name: packageLabel,
                terms: formattedTerms, // Keep for backward compatibility
                tiers: processedTiers, // NEW: Grouped by tiers
                hasTerms: formattedTerms.length > 0,
                hasTiers: processedTiers.length > 0
            };
        });
    }
    
    // Get formatted vehicle name (Year Make Model)
    get vehicleDisplayName() {
        const parts = [];
        if (this.vehicleData.year) parts.push(this.vehicleData.year);
        if (this.vehicleData.make) parts.push(this.vehicleData.make);
        if (this.vehicleData.model) parts.push(this.vehicleData.model);
        return parts.join(' ') || '';
    }
    
    // Get formatted purchase price
    get formattedPurchasePrice() {
        if (!this.vehicleData.purchasePrice) return '';
        return this.formatPrice(this.vehicleData.purchasePrice);
    }
    
    // Get formatted odometer reading
    get formattedOdometer() {
        if (!this.vehicleData.odometer) return '';
        const odometer = this.vehicleData.odometer;
        const unit = this.vehicleData.odometerUnit || 'KM';
        // Format number with commas
        const formattedOdometer = parseFloat(odometer).toLocaleString('en-US');
        return `${formattedOdometer} ${unit.toLowerCase()}`;
    }
    
    // Get selected plan display text
    get selectedPlanDisplay() {
        if (!this.selectedDealerPackage) return '';
        const packageName = this.selectedDealerPackage.PackageName || '';
        // You may need to adjust this based on actual data structure
        // For now, returning the package name
        return packageName;
    }
    
    // Get coverage term display with unlimited km in red
    get coverageTermDisplay() {
        let duration, mileage, mileageUnit;
        
        // Check if user selected a different term than the stored one
        const isSameTerm = this.isExistingApplication && 
                          this.existingApplicationPackage && 
                          this.selectedWarrantyTerm && 
                          this.selectedWarrantyTerm.Id === this.existingApplicationPackage.selectedTermId;
        
        if (isSameTerm) {
            // Use stored values from Application_Package__c
            duration = this.existingApplicationPackage.expiryTerm || 0;
            mileage = this.existingApplicationPackage.odometerEnd;
            mileageUnit = this.existingApplicationPackage.odometerEndUnit || 'KM';
        } else if (this.selectedWarrantyTerm) {
            // Use new term values from Dealer_Package_Term__c (expiryTerm and odometerKM)
            duration = this.selectedWarrantyTerm.expiryTerm || 0;
            mileage = this.selectedWarrantyTerm.odometerKM || this.selectedWarrantyTerm.mileageRestriction;
            mileageUnit = this.selectedWarrantyTerm.mileageUnit || 'KM';
        } else if (this.isExistingApplication && this.existingApplicationPackage) {
            // Fallback to stored values if no term selected yet
            duration = this.existingApplicationPackage.expiryTerm || 0;
            mileage = this.existingApplicationPackage.odometerEnd;
            mileageUnit = this.existingApplicationPackage.odometerEndUnit || 'KM';
        } else {
            return null;
        }
        
        const mileageUnitLower = mileageUnit.toLowerCase();
        const isUnlimited = !mileage || mileage === 0 || mileageUnit.toUpperCase() === 'UNLIMITED';
        
        const formattedMileage = mileage ? mileage.toLocaleString('en-US') : '0';
        
        return {
            duration: duration,
            mileage: mileage,
            formattedMileage: formattedMileage,
            mileageUnit: mileageUnit,
            mileageUnitLower: mileageUnitLower,
            isUnlimited: isUnlimited,
            displayText: isUnlimited 
                ? `${duration} Months/Unlimited ${mileageUnitLower}`
                : `${duration} Months/${formattedMileage} ${mileageUnit}`
        };
    }

    // Package comparison helpers
    handlePackageCompareToggle(event) {
        const packageId = event.target.dataset.packageId;
        const isChecked = event.target.checked;

        if (!packageId) {
            return;
        }

        if (isChecked) {
            if (this.selectedPackagesForComparison.length >= 4) {
                event.target.checked = false;
                this.showErrorMessage('You can compare up to 4 packages at a time.');
                return;
            }

            if (!this.selectedPackagesForComparison.includes(packageId)) {
                this.selectedPackagesForComparison = [...this.selectedPackagesForComparison, packageId];
            }
        } else {
            this.selectedPackagesForComparison = this.selectedPackagesForComparison.filter(id => id !== packageId);
        }

        this.updatePackageCompareState();
    }

    updatePackageCompareState() {
        this.showCompareButton = this.selectedPackagesForComparison.length > 1;
    }

    openPackageComparison() {
        this.comparisonPackages = this.buildPackageComparison();
        if (this.comparisonPackages.length < 2) {
            this.showErrorMessage('Select at least two packages to compare.');
            return;
        }
        this.showComparisonModal = true;
    }

    buildPackageComparison() {
        const packages = [];

        this.selectedPackagesForComparison.forEach(packageId => {
            const pkg = this.dealerPackages.find(p => p.Id === packageId);
            if (!pkg) {
                return;
            }

            const isSelected = this.selectedDealerPackage?.Id === pkg.Id;

            packages.push({
                id: pkg.Id,
                name: pkg.PackageName || pkg.Name || 'Warranty Package',
                description: pkg.PackageDescription || 'No description provided.',
                termCount: (pkg.warrantyTerms || []).length,
                termLabel: ((pkg.warrantyTerms || []).length === 1 ? 'term' : 'terms'),
                options: (pkg.options || []).map(option => ({
                    id: option.Id || option.id,
                    name: option.optionName || option.Name || option.label || 'Included Option'
                })),
                buttonLabel: isSelected ? 'Currently Selected' : 'Select Package',
                buttonVariant: isSelected ? 'success' : 'brand',
                buttonDisabled: isSelected
            });
        });

        return packages;
    }

    clearPackageComparison() {
        this.selectedPackagesForComparison = [];
        this.updatePackageCompareState();

        const checkboxes = this.template.querySelectorAll('.package-compare-checkbox');
        checkboxes.forEach(checkbox => {
            checkbox.checked = false;
        });
    }

    closePackageComparison() {
        this.showComparisonModal = false;
    }

    async selectPackageFromComparison(event) {
        const packageId = event.target.dataset.packageId;
        if (!packageId) {
            return;
        }

        await this.selectDealerPackageById(packageId);
        this.closePackageComparison();
    }

    async handleConvertToApplication() {
        if (!this.applicationId) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Record ID not found. Please refresh the page.',
                    variant: 'error'
                })
            );
            return;
        }

        try {
            const result = await convertQuoteToApplication({ applicationId: this.applicationId });
            
            if (result.success) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: result.message || 'Quote converted to Application',
                        variant: 'success'
                    })
                );

                // Dispatch custom event to notify parent container to reload data
                const convertEvent = new CustomEvent('applicationstatuschanged', {
                    detail: { 
                        applicationId: this.applicationId,
                        newStatus: 'Draft'
                    },
                    bubbles: true,
                    composed: true
                });
                this.dispatchEvent(convertEvent);
                console.log('✅ Application status changed event dispatched');
            } else {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: result.message || 'Failed to convert to Application',
                        variant: 'error'
                    })
                );
            }

        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: error.body?.message || error.message || 'Failed to convert to Application',
                    variant: 'error'
                })
            );
        }
    }
}