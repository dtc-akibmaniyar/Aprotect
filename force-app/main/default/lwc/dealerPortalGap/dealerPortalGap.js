import { LightningElement, track, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LoanProtectionLogo from '@salesforce/resourceUrl/LoanProtectionLogo';
import getTotalLossDealerPackages from '@salesforce/apex/DealerPortalController.getTotalLossDealerPackages';
import getTotalLossExistingApplicationPackageByRecordType from '@salesforce/apex/DealerPortalController.getTotalLossExistingApplicationPackageByRecordType';
import getActiveApplicationPackageByRecordType from '@salesforce/apex/DealerPortalController.getActiveApplicationPackageByRecordType';
import savePackageWithActiveManagement from '@salesforce/apex/DealerPortalController.savePackageWithActiveManagement';
import createTotalLossApplicationPackageFromMap from '@salesforce/apex/DealerPortalController.createTotalLossApplicationPackageFromMap';
import updateTotalLossApplicationPackage from '@salesforce/apex/DealerPortalController.updateTotalLossApplicationPackage';
import getTotalLossAdditionalOptions from '@salesforce/apex/DealerPortalController.getTotalLossAdditionalOptions';
import getTotalLossAdditionalOptionsByPackage from '@salesforce/apex/DealerPortalController.getTotalLossAdditionalOptionsByPackage';
import getTotalLossExistingAdditionalOptions from '@salesforce/apex/DealerPortalController.getTotalLossExistingAdditionalOptions';
import updateTotalLossAdditionalOptions from '@salesforce/apex/DealerPortalController.updateTotalLossAdditionalOptions';
import updateTotalLossFieldsSelective from '@salesforce/apex/DealerPortalController.updateTotalLossFieldsSelective';
import loadVehicleData from '@salesforce/apex/DealerPortalController.loadVehicleData';
import convertQuoteToApplication from '@salesforce/apex/DealerPortalController.convertQuoteToApplication';

export default class DealerPortalGap extends LightningElement {
    loanHeroImage = LoanProtectionLogo;
    @track loading = false
    @track renderKey = 0 // Used to force re-renders;
    @track price = 0.00;
    @track selectedProgram = '';
    @track selectedTerm = '4';
    @track selectedClaim = '5000';
    @track selectedAdditionalOptions = []; // Array of selected additional option IDs
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
    @track dealerHasGapPackages = false;
    @track packageSearchPerformed = false;
    @track selectedDealerPackage = null;
    @track selectedWarrantyTerm = null;
    @track showPriceModal = false;
    @track currentPriceBreakdown = {};
    @track dealerReferenceBreakdown = {};
    @track showDealerReferencePrice = false;
    @track existingApplicationPackage = null;
    @track isExistingApplication = false;
    @track isPriceEditMode = false;
    @track priceOverrideInput = '';
    @track isPriceOverridden = false;
    @track comparePackages = [];
    @track showCompareModal = false;
    @track selectedForComparison = [];
    @track showCompareButton = false;
    @track showComparisonModal = false;
    @track comparisonTerms = [];
    @track showHelpModal = false;
    @track helpModalTitle = '';
    @track helpModalText = '';
    @track showWarrantyModal = false;
    @track selectedDealerPackageName = '';
    @track selectedWarrantyTermName = '';
    @track packageHasFiles = false;
    @track packageFileCount = 0;
    @track totalTermCount = 0; // Track total number of terms matching the month filter
    
    // Down Payment Protection input fields
    @track cashDown = '';
    @track vehicleTradeInEquity = '';
    
    // Filtered additional options by category
    @track commercialOptions = [];
    @track downPaymentOptions = [];
    @track filteredDownPaymentOptions = [];
    
    // Loading states
    @track isLoadingPackages = false;
    @track isLoadingOptions = false;
    
    // Vehicle data for display
    @track vehicleData = {};
    
    @api isLocked = false;
    
    // Getter for field disabled state based on lock status
    get fieldDisabled() {
        return this.isLocked;
    }
    
    // Getter for skip button label - "Next" when locked, "Skip" when not locked
    get skipButtonLabel() {
        return this.isLocked ? 'Next' : 'Decline Loan Protection';
    }
    
    // Getter for search button disabled state (combines loading state with lock)
    get searchButtonDisabled() {
        return this.isLoadingPackages || this.fieldDisabled;
    }
    
    // Getter for find options button disabled state (combines loading state with lock)
    get findOptionsButtonDisabled() {
        return this.isLoadingOptions || this.fieldDisabled;
    }

    get showContinueButton() {
        return !this.loading && !this.fieldDisabled;
    }

    get sowSaveAsQuoteButton() {
        return !this.loading && !this.isQuoteStatus && !this.fieldDisabled;
    }
    
    // Button labels
    get findPackagesButtonLabel() {
        return this.isLoadingPackages ? 'Loading...' : 'Find Packages';
    }
    
    get findOptionsButtonLabel() {
        return this.isLoadingOptions ? 'Finding...' : 'Find Options';
    }
    
    // Display helpers for term-count info when values may come from saved package
    get displayFinanceLoanTerm() {
        if (this.financeLoanTerm) {
            return this.financeLoanTerm;
        }
        // Fallback to selected term duration if available
        if (this.selectedWarrantyTerm) {
            return this.selectedWarrantyTerm.durationRestrictionInMonths || this.selectedWarrantyTerm.Duration_Restriction_in_Months__c || '';
        }
        // Fallback to existing package value if hydrated
        if (this.isExistingApplication && this.existingApplicationPackage && this.existingApplicationPackage.financeLoanTerm) {
            return this.existingApplicationPackage.financeLoanTerm;
        }
        return '';
    }

    get displayInterestRate() {
        if (this.interestRate !== '' && this.interestRate != null) {
            return this.interestRate;
        }
        if (this.isExistingApplication && this.existingApplicationPackage && this.existingApplicationPackage.interestRate != null) {
            return this.existingApplicationPackage.interestRate;
        }
        return '';
    }

    get displayLoanAmount() {
        if (this.loanAmount !== '' && this.loanAmount != null) {
            return this.loanAmount;
        }
        if (this.isExistingApplication && this.existingApplicationPackage && this.existingApplicationPackage.loanAmount != null) {
            return this.existingApplicationPackage.loanAmount;
        }
        return '';
    }

    // Always-render text for month part to avoid incomplete sentence on first paint
    get displayFinanceLoanTermText() {
        const month = this.displayFinanceLoanTerm;
        return month ? `${month}-month` : '';
    }

    // Build a human-readable filters summary for the term-count message
    get filtersSummary() {
        const parts = [];
        const month = this.displayFinanceLoanTerm;
        const rate = this.displayInterestRate;
        const amount = this.displayLoanAmount;
        if (month) {
            parts.push(`${month}-month finance loan term`);
        }
        if (rate !== '' && rate != null) {
            parts.push(`${rate}% interest rate`);
        }
        if (amount !== '' && amount != null) {
            parts.push(`$${amount} loan amount`);
        }
        if (parts.length === 0) {
            return '';
        }
        if (parts.length === 1) {
            return parts[0];
        }
        // Oxford comma style join
        return parts.slice(0, -1).join(', ') + ', and ' + parts[parts.length - 1];
    }

    // Debug helper to log filter sources and computed display values
    logFilterDebug(context) {
        try {
            console.log('🧪 [GAP] Filter Debug - ' + context);
            console.log('   Raw fields:', {
                lenderLienholder: this.lenderLienholder,
                financeLoanTerm: this.financeLoanTerm,
                interestRate: this.interestRate,
                loanAmount: this.loanAmount,
                paymentFrequency: this.paymentFrequency
            });
            console.log('   Existing package fields:', this.existingApplicationPackage ? {
                lenderLienholder: this.existingApplicationPackage.lenderLienholder,
                financeLoanTerm: this.existingApplicationPackage.financeLoanTerm,
                interestRate: this.existingApplicationPackage.interestRate,
                loanAmount: this.existingApplicationPackage.loanAmount,
                paymentFrequency: this.existingApplicationPackage.paymentFrequency
            } : 'n/a');
            console.log('   Display getters:', {
                displayFinanceLoanTerm: this.displayFinanceLoanTerm,
                displayInterestRate: this.displayInterestRate,
                displayLoanAmount: this.displayLoanAmount,
                displayFinanceLoanTermText: this.displayFinanceLoanTermText,
                filtersSummary: this.filtersSummary
            });
        } catch (e) {
            console.warn('⚠️ [GAP] logFilterDebug error:', e);
        }
    }

    // GAP Input Fields
    @track lenderLienholder = '';
    @track financeLoanTerm = '';
    @track loanAmount = '';
    @track interestRate = '';
    @track paymentFrequency = '';
    @track showPackageSelection = false;
    @track forceShowInputFields = false; // Override to show inputs even for existing applications
    @track originalGapData = {};
    @track gapChangedFields = new Set();
    @track gapAutoSaveTimeout;
    _applicationId;
    
    // Getter and setter for applicationId to handle changes
    @api
    get applicationId() {
        return this._applicationId;
    }
    
    set applicationId(value) {
        if (this._applicationId !== value) {
            this._applicationId = value;
            
            // Don't load packages immediately - let the tab activation flow handle it
            // This ensures filters are hydrated from existing package first
            if (value) {
                console.log('🔍 GAP - applicationId set to:', value, '- waiting for tab activation to load packages');
            }
        }
    }

    @api applicationStatus;

    get isQuoteStatus() {
        return this.applicationStatus === 'Quote';
    }

    get continueButtonLabel() {
        return 'Save & Continue';
    }

    async connectedCallback() {
        console.log('🔍 GAP - connectedCallback started');
        console.log('🔍 GAP - Initial state: isExistingApplication:', this.isExistingApplication, 'showPackageSelection:', this.showPackageSelection);

        // If we have an applicationId, ensure we hydrate from any existing package BEFORE clearing inputs
        if (this.applicationId) {
            console.log('🔍 GAP - connectedCallback: awaiting existing package check with applicationId:', this.applicationId);
            await this.checkForExistingApplicationPackage();
            console.log('🔍 GAP - connectedCallback: after existing package check:', {
                isExistingApplication: this.isExistingApplication,
                hasExistingPackage: !!this.existingApplicationPackage,
                existingPackagePreview: this.existingApplicationPackage ? {
                    id: this.existingApplicationPackage.Id,
                    dealerPackageId: this.existingApplicationPackage.dealerPackageId,
                    selectedTermId: this.existingApplicationPackage.selectedTermId,
                    financeLoanTerm: this.existingApplicationPackage.financeLoanTerm,
                    interestRate: this.existingApplicationPackage.interestRate,
                    loanAmount: this.existingApplicationPackage.loanAmount
                } : null
            });
        }

        // Load GAP input data after existing-package check
        // This will only clear inputs for new applications
        this.loadGapInputData();

        // If existing application, ensure local filters are hydrated for client-side filtering
        if (this.isExistingApplication && this.existingApplicationPackage) {
            const pkg = this.existingApplicationPackage;
            this.lenderLienholder = (pkg.lenderLienholder != null && pkg.lenderLienholder !== '') ? pkg.lenderLienholder : this.lenderLienholder;
            this.financeLoanTerm = (pkg.financeLoanTerm != null && pkg.financeLoanTerm !== '') ? String(pkg.financeLoanTerm) : this.financeLoanTerm;
            this.loanAmount = (pkg.loanAmount != null && pkg.loanAmount !== '') ? String(pkg.loanAmount) : this.loanAmount;
            this.interestRate = (pkg.interestRate != null && pkg.interestRate !== '') ? String(pkg.interestRate) : this.interestRate;
            this.paymentFrequency = (pkg.paymentFrequency != null && pkg.paymentFrequency !== '') ? pkg.paymentFrequency : this.paymentFrequency;
            this.renderKey++;
            console.log('🔍 GAP - connectedCallback: hydrated filters from existing package:', {
                lenderLienholder: this.lenderLienholder,
                financeLoanTerm: this.financeLoanTerm,
                interestRate: this.interestRate,
                loanAmount: this.loanAmount,
                paymentFrequency: this.paymentFrequency
            });
        }

        // Auto-populate with saved UI state if available
        if (sessionStorage.getItem('gapData')) {
            const savedData = JSON.parse(sessionStorage.getItem('gapData'));
            this.selectedProgram = savedData.selectedProgram || this.selectedProgram;
            this.selectedTerm = savedData.selectedTerm || this.selectedTerm;
            this.selectedClaim = savedData.selectedClaim || this.selectedClaim;
            this.selectedDeductible = savedData.selectedDeductible || this.selectedDeductible;
            this.testDrive = savedData.testDrive || this.testDrive;

            if (savedData.selectedDealerPackage) {
                this.selectedDealerPackage = savedData.selectedDealerPackage;
                console.log('GAP Selected DealerPackage :: ');
                console.log(this.selectedDealerPackage.Id);
            }

            this.updatePrice();
        }

        // If we have an applicationId AND an existing package, load packages now using hydrated filters
        // For new applications, package load is deferred to the Search button click
        if (this.applicationId && this.isExistingApplication) {
            console.log('🔍 GAP - connectedCallback: loading dealer packages for existing application');
            await this.loadDealerPackages();
        }
    }
    
    // Method to update UI selection highlighting
    // NOTE: We rely on the reactive getter (dealerPackagesDisplay) to set rowClass
    // No DOM manipulation needed - the getter will automatically update when selectedWarrantyTerm changes
    updateSelectionHighlighting() {
        // Just trigger a re-render - the getter will handle the highlighting reactively
        this.renderKey++;
    }
    
    // Called when GAP tab is activated
    @api
    onTabActivated() {
        console.log('🎯 ===== GAP TAB ACTIVATED =====');
        console.log('🔄 Application ID:', this.applicationId);
        console.log('🔄 Current packages loaded:', this.dealerPackages ? this.dealerPackages.length : 0);
        console.log('🔄 Selected package:', this.selectedDealerPackage?.PackageName || 'None');
        console.log('🔄 Selected term:', this.selectedWarrantyTerm?.packageTermName || this.selectedWarrantyTerm?.Name || 'None');
        console.log('🔄 Is existing application:', this.isExistingApplication);
        
        // Always reload packages when tab is activated to ensure fresh data
        if (this.applicationId) {
            console.log('🔄 Loading existing package first to drive filters...');
            this.checkForExistingApplicationPackage()
                .then(() => {
                    this.logFilterDebug('after checkForExistingApplicationPackage');
                    // If existing, hydrate inputs from saved values to drive filtering
                    if (this.isExistingApplication && this.existingApplicationPackage) {
                        // Hydrate from server payload FIRST so UI getters have values on first paint
                        const pkg = this.existingApplicationPackage;
                        this.lenderLienholder = (pkg.lenderLienholder != null && pkg.lenderLienholder !== '') ? pkg.lenderLienholder : this.lenderLienholder;
                        this.financeLoanTerm = (pkg.financeLoanTerm != null && pkg.financeLoanTerm !== '') ? String(pkg.financeLoanTerm) : this.financeLoanTerm;
                        this.loanAmount = (pkg.loanAmount != null && pkg.loanAmount !== '') ? String(pkg.loanAmount) : this.loanAmount;
                        this.interestRate = (pkg.interestRate != null && pkg.interestRate !== '') ? String(pkg.interestRate) : this.interestRate;
                        this.paymentFrequency = (pkg.paymentFrequency != null && pkg.paymentFrequency !== '') ? pkg.paymentFrequency : this.paymentFrequency;
                        // Force re-render of filter info now that values are hydrated
                        this.renderKey++;
                        this.logFilterDebug('after hydration');
                    }
                    console.log('🔄 Loading dealer packages for GAP tab...');
                    this.loadVehicleData();
                    // Only auto-load packages for existing applications
                    // For new applications, package load is triggered by the Search button
                    if (this.isExistingApplication) {
                        return this.loadDealerPackages();
                    }
                });
        } else {
            console.log('❌ CRITICAL: No application ID available for GAP tab');
        }
    }
    
    // Load vehicle data for display
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
            }
        } catch (error) {
            console.error('Error loading vehicle data:', error);
        }
    }
    
    // Load dealer packages from Salesforce
    async loadDealerPackages() {
        try {
            console.log('🔍 GAP - loadDealerPackages called with applicationId:', this.applicationId);
            console.log('🔍 GAP - Current filter values:');
            console.log('  - financeLoanTerm:', this.financeLoanTerm, '(type:', typeof this.financeLoanTerm, ')');
            console.log('  - interestRate:', this.interestRate, '(type:', typeof this.interestRate, ')');
            console.log('  - loanAmount:', this.loanAmount, '(type:', typeof this.loanAmount, ')');
            console.log('  - lenderLienholder:', this.lenderLienholder);
            console.log('  - paymentFrequency:', this.paymentFrequency);
            console.log('🔍 GAP - isExistingApplication:', this.isExistingApplication);
            this.loading = true;
                
                const result = await getTotalLossDealerPackages({
                    applicationId: this.applicationId,
                    recordType: 'Total_Loss_Coverage',
                    financeLoanTerm: this.financeLoanTerm ? parseInt(this.financeLoanTerm) : null,
                    interestRate: this.interestRate ? parseFloat(this.interestRate) : null,
                    loanAmount: this.loanAmount ? parseFloat(this.loanAmount) : null
                });
                console.log('🔍 GAP - getTotalLossDealerPackages result:', result);
            console.log('🔍 GAP - result.success:', result.success);
            console.log('🔍 GAP - result.data:', result.data);
            console.log('🔍 GAP - result.data length:', result.data ? result.data.length : 'null');
            console.log('🔍 GAP - result.termCount:', result.termCount);
                if (result && result.debugFilters) {
                    console.log('🧪 GAP DEBUG (from Apex) - debugFilters:', result.debugFilters);
                }
            
            
            if (result.success) {
                // Store the total term count
                this.totalTermCount = result.termCount || 0;
                console.log('🔍 GAP - Total terms matching month filter:', this.totalTermCount);

                if (!result.data || result.data.length === 0) {
                    this.dealerPackages = [];
                    this.dealerHasGapPackages = false;
                    this.loading = false;
                    return;
                }
                this.dealerHasGapPackages = true;
                
                // Map the data to include warranty terms and options
                // IMPORTANT: Do NOT client-filter by month here; Apex already applies Month__c filter
                // to avoid double-filtering mismatches across fields
                this.dealerPackages = result.data.map(pkg => {
                    const allTerms = pkg.terms || [];
                    // Debug: log first term fields to verify server payload shape
                    if (allTerms.length > 0) {
                        const t = allTerms[0];
                        console.log('🔬 GAP - Sample term fields for package', pkg.Name, {
                            Id: t.Id,
                            Name: t.Name,
                            Month__c: t.Month__c,
                            Duration_Restriction_in_Months__c: t.Duration_Restriction_in_Months__c,
                            durationRestrictionInMonths: t.durationRestrictionInMonths,
                            month: t.month
                        });
                    }
                    return {
                        ...pkg,
                        warrantyTerms: allTerms,
                        options: pkg.options || []
                    };
                });
                // Update totalTermCount for logs/UX
                this.totalTermCount = this.dealerPackages.reduce((sum, pkg) => sum + (pkg.warrantyTerms ? pkg.warrantyTerms.length : 0), 0);
                console.log('🔍 GAP - Total terms after mapping (no client month filter):', this.totalTermCount);
                
                // Check for existing application package and auto-select it
                await this.checkForExistingApplicationPackage();
                
                // Update price after checking for existing package
                this.updatePrice();
                
                // Update selection highlighting after packages are loaded
                this.updateSelectionHighlighting();
            } else {
                this.dealerHasGapPackages = result.hasGapPackages === true;
                this.dealerPackages = [];
                if (!this.packageSearchPerformed) {
                    this.errorMessage = result.message;
                    this.showError = true;
                }
            }
        } catch (error) {
            console.error('❌ GAP - Error loading packages:', error);
            this.errorMessage = 'Error loading Total Loss Protection packages. Please try again.';
            this.showError = false;
        } finally {
            this.loading = false;
            this.isLoadingPackages = false;
        }
    }
    
    // Check for existing application package and auto-select it
    @api
    async checkForExistingApplicationPackage() {
        try {
            console.log('🔎 [GAP] Loading ACTIVE total loss package...');
            console.log('   applicationId:', this.applicationId);
            
            const result = await getActiveApplicationPackageByRecordType({ 
                applicationId: this.applicationId, 
                recordType: 'GAP_Coverage' 
            });
            
            console.log('📦 [GAP] Active package result:', result);
            if (result && result.debugFilters) {
                console.log('🧪 GAP DEBUG (from Apex) - debugFilters:', result.debugFilters);
            }
            console.log('🔎 GAP - existing package response', {
                success: result && result.success,
                hasData: result && !!result.data,
                message: result && result.message,
                dataPreview: result && result.data ? {
                    id: result.data.Id,
                    dealerPackageId: result.data.dealerPackageId,
                    selectedTermId: result.data.selectedTermId,
                    dealerPackagePrice: result.data.dealerPackagePrice,
                    dealerMarkup: result.data.dealerMarkup,
                    lenderLienholder: result.data.lenderLienholder,
                    financeLoanTerm: result.data.financeLoanTerm,
                    interestRate: result.data.interestRate,
                    loanAmount: result.data.loanAmount,
                    paymentFrequency: result.data.paymentFrequency
                } : null
            });
            
            if (result.success && result.data) {
                
                // Store the existing application package data
                this.existingApplicationPackage = result.data;
                this.isExistingApplication = true;

                // Restore dealer price override if one was previously saved
                if (result.data.dealerPriceOverride != null && result.data.dealerPriceOverride !== undefined) {
                    this.price = result.data.dealerPriceOverride;
                    this.isPriceOverridden = true;
                }

                // Ensure we skip the input fields and show the package selection UI
                if (!this.showPackageSelection) {
                    console.log('✅ GAP - Setting showPackageSelection=true due to existing package');
                    this.showPackageSelection = true;
                }
                
                // Find the matching dealer package from our loaded packages
                const matchingDealerPackage = this.dealerPackages.find(pkg => pkg.Id === result.data.dealerPackageId);
                
                if (matchingDealerPackage) {
                    // Auto-select the existing package
                    this.selectedDealerPackage = matchingDealerPackage;
                    this.selectedProgram = matchingDealerPackage.PackageName;
                    
                    // Find and select the matching term
                    if (matchingDealerPackage.warrantyTerms && result.data.selectedTermId) {
                        const matchingTerm = matchingDealerPackage.warrantyTerms.find(term => 
                            term.Id === result.data.selectedTermId
                        );
                        
                        if (matchingTerm) {
                            this.selectedWarrantyTerm = matchingTerm;
                            
                            // Load additional options for the existing selected term
                            await this.loadAdditionalOptions(matchingTerm.Id);
                            
                            // Load existing additional options for this application package
                            await this.loadExistingAdditionalOptions(result.data.Id);
                        }
                    }
                    
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
                    this.initializeOriginalGapData();
                    // Do not auto-dispatch completion here; keep user on GAP tab
                } else {
                    console.log('⚠️ GAP - Could not find matching dealer package for', result.data.dealerPackageId);
                }
                // Log hydrated filter values used by UI getters
                console.log('🧪 GAP - Saved filters on package:', {
                    lenderLienholder: this.existingApplicationPackage.lenderLienholder,
                    financeLoanTerm: this.existingApplicationPackage.financeLoanTerm,
                    interestRate: this.existingApplicationPackage.interestRate,
                    loanAmount: this.existingApplicationPackage.loanAmount,
                    paymentFrequency: this.existingApplicationPackage.paymentFrequency
                });
                console.log('🧪 GAP - Current component filter fields (pre-hydration):', {
                    lenderLienholder: this.lenderLienholder,
                    financeLoanTerm: this.financeLoanTerm,
                    interestRate: this.interestRate,
                    loanAmount: this.loanAmount,
                    paymentFrequency: this.paymentFrequency
                });
            } else {
                console.log('🔍 No existing application found, showPackageSelection before:', this.showPackageSelection);
                console.log('🔍 No existing application found, isExistingApplication before:', this.isExistingApplication);
                
                // Clear selections for new applications
                this.selectedDealerPackage = null;
                this.selectedWarrantyTerm = null;
                this.existingApplicationPackage = null;
                this.isExistingApplication = false;
                
                // Don't override showPackageSelection if user has already clicked "Find Packages"
                // Only set to false if we're starting fresh (no packages loaded yet)
                if (this.dealerPackages.length === 0) {
                    this.showPackageSelection = false;
                    console.log('🔍 No packages loaded yet, showing input fields');
                } else {
                    console.log('🔍 Packages already loaded, keeping showPackageSelection as:', this.showPackageSelection);
                }
                
                console.log('🔍 No existing application found, isExistingApplication after:', this.isExistingApplication);
                console.log('🔍 No existing application found, showPackageSelection after:', this.showPackageSelection);
                console.log('🔍 Final state: isExistingApplication=false, showPackageSelection=', this.showPackageSelection);
            }
            console.log('🔎 GAP - checkForExistingApplicationPackage END', {
                isExistingApplication_after: this.isExistingApplication,
                showPackageSelection_after: this.showPackageSelection
            });
        } catch (error) {
            console.error('❌ GAP - checkForExistingApplicationPackage error:', error);
        }
    }
    
    // Get dynamic dealer packages for display
    get dealerPackagesDisplay() {
        
        return this.dealerPackages.map(pkg => {
            const isSelected = this.selectedDealerPackage && this.selectedDealerPackage.Id === pkg.Id;
            
            // Process terms for display - using warranty-style term-row buttons
            const processedTerms = (pkg.warrantyTerms || []).map(term => {
                const isTermSelected = this.selectedWarrantyTerm && 
                                     this.selectedWarrantyTerm.Id === term.Id;
                
                // Check if this is the existing selected term (should be disabled)
                const isExistingSelectedTerm = this.isExistingApplication && 
                                             this.existingApplicationPackage &&
                                             this.existingApplicationPackage.selectedTermId === term.Id;
                
                // Terms are now always enabled - package will be auto-selected when term is selected
                // Note: Removed existing term disabling - allow re-selection for UX feedback
                const isTermDisabled = false;
                
                
                // Use the totalPrice from the term (already includes proper markup calculation from backend)
                const displayPrice = term.totalPrice || term.netCost || 0;
                
                
                // Use warranty-style term-row class
                const termRowClass = isTermSelected ? 'term-row selected' : 'term-row';
                
                if (isTermSelected) {
                }
                
                return {
                    ...term,
                    id: term.Id, // Ensure id is explicitly set
                    cssClass: isTermSelected ? 'term-option selected' : 'term-option',
                    rowClass: termRowClass,
                    isSelected: isTermSelected,
                    isDisabled: isTermDisabled,
                    price: this.formatPrice(displayPrice),
                    termDisplayName: term.packageTermName || term.Name || 'Unknown Term',
                    termDuration: term.durationRestrictionInMonths || 0,
                    termMileage: `${term.mileageRestriction || 0} ${term.mileageUnit || 'KM'}`,
                    // Keep all markup details for further use
                    netCost: term.netCost || 0,
                    markup: term.markup || 0,
                    markupType: term.markupType || '',
                    selectionText: isExistingSelectedTerm ? 'Currently Selected' : 
                                  isTermSelected ? 'Selected' : 
                                  isTermDisabled ? 'Unavailable' : 'Select',
                    buttonVariant: isExistingSelectedTerm ? 'success' : 
                                  isTermSelected ? 'success' : 
                                  isTermDisabled ? 'neutral' : 'brand',
                    buttonDisabled: isTermDisabled,
                    isSelectedForCompare: this.selectedForComparison.includes(term.Id)
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
            if (isSelected) {
            }
            
            return {
            id: pkg.Id,
            name: pkg.PackageName,
            description: pkg.PackageDescription,
                isSelected: isSelected,
                cssClass: cssClass,
                buttonVariant: isSelected ? 'success' : 'brand',
                buttonLabel: isSelected ? 'Selected' : 'Select Package',
            dealerPackageId: pkg.Id,
            dealerId: pkg.DealerId,
                buttonClass: isSelected ? 'select-program-btn selected' : 'select-program-btn',
                buttonDisabled: isSelected,
                terms: processedTerms,
                options: processedOptions
            };
        });
    }
    
    // Get warranty terms for display
    get warrantyTermsDisplay() {
        if (!this.selectedDealerPackage || !this.selectedDealerPackage.warrantyTerms) {
            return [];
        }
        
        return this.selectedDealerPackage.warrantyTerms.map(term => {
            const isSelected = this.selectedWarrantyTerm && 
                             this.selectedWarrantyTerm.Id === term.Id;
            
            let displayPrice;
            if (this.isExistingApplication && this.existingApplicationPackage) {
                // For existing applications, show the sold price (dealerPackagePrice + dealerMarkup)
                displayPrice = this.formatPrice(
                    (this.existingApplicationPackage.dealerPackagePrice || 0) + 
                    (this.existingApplicationPackage.dealerMarkup || 0)
                );
            } else {
                // For new selections, show the current term price
                displayPrice = this.formatPrice(term.totalPrice || term.netCost || 0);
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
        const packageId = event.currentTarget.dataset.package;
        const selectedPackage = this.dealerPackages.find(pkg => pkg.Id === packageId);
        
        console.log('========================================');
        console.log('🔍 DEBUG: Package Selection');
        console.log('========================================');
        console.log('🔍 packageId:', packageId);
        console.log('🔍 selectedPackage:', JSON.stringify(selectedPackage, null, 2));
        console.log('========================================');
        
        if (selectedPackage) {
            // Check if this is a different package than currently selected
            const isPackageChange = this.selectedDealerPackage && this.selectedDealerPackage.Id !== selectedPackage.Id;
            
            if (isPackageChange) {
                console.log('📦 [GAP] Package changed - will save when user clicks Continue');
                
                // DON'T save immediately - wait for user to click Continue
                /* OLD CODE - Disabled to prevent premature save
                if (this.isExistingApplication && this.existingApplicationPackage) {
                    await this.updateExistingApplicationPackage(selectedPackage, null);
                }
                */
                
                // CRITICAL: Clear ALL additional options when package changes
                console.log('🧹 [GAP] Clearing additional options for new package');
                this.selectedAdditionalOptions = [];
                this.existingAdditionalOptions = [];
                this.selectedNewOptions = [];
                this.optionsToRemove = [];
                this.commercialOptions = [];
                this.downPaymentOptions = [];
                this.filteredDownPaymentOptions = [];
            }
            
            // Clear term selection when package changes (validation requirement)
            this.selectedWarrantyTerm = null;
            
            // Track the package change
            const oldPackageId = this.originalGapData.selectedDealerPackageId;
            const newPackageId = selectedPackage.Id;
            
            this.selectedDealerPackage = selectedPackage;
            this.selectedProgram = selectedPackage.PackageName;
            
            
            // Track change for auto-save
            this.trackGapChange('package', oldPackageId, newPackageId);
            
            // Force UI refresh to show selection highlighting
            this.template.querySelectorAll('.program-section').forEach(section => {
                section.classList.remove('selected');
            });
            
            // Update selection highlighting
            this.updateSelectionHighlighting();
            
            // Load additional options for the selected package
            console.log('🔍 GAP - About to load package-level additional options for packageId:', selectedPackage.Id);
            await this.loadAdditionalOptionsByPackage(selectedPackage.Id);
            console.log('🔍 GAP - After loading package-level additional options, availableAdditionalOptionsData length:', this.availableAdditionalOptionsData.length);
            
            // Update price (will be 0 until term is selected)
            this.updatePrice();
            
            // Save data
            this.saveDataToSession();
        }
    }
    
    // Handle warranty term selection
    async handleGapTermSelection(event) {
        const termId = event.currentTarget.dataset.term;
        const packageId = event.currentTarget.dataset.package;
        const isDisabled = event.currentTarget.dataset.disabled === 'true';
        
        console.log('🔍 GAP - Term selection clicked:', { termId, packageId, isDisabled });
        
        // Check if term is disabled
        if (isDisabled) {
            this.showErrorMessage('This term is not available for selection.');
            return;
        }
        
        // Check if this is the already selected term - but allow selection if package was just auto-selected
        // This prevents the "already selected" message when clicking the same term after package auto-selection
        if (this.selectedWarrantyTerm && 
            this.selectedWarrantyTerm.Id === termId && 
            this.selectedDealerPackage && 
            this.selectedDealerPackage.Id === packageId) {
            // Term is already selected and package matches - no need to do anything
            console.log('🔍 Term already selected:', termId);
            return;
        }
        
        // Find the package and term first - before setting any state
        const selectedPackage = this.dealerPackages.find(pkg => pkg.Id === packageId);
        if (!selectedPackage) {
            this.showErrorMessage('Package not found. Please try again.');
            return;
        }
        
        if (!selectedPackage.warrantyTerms || !selectedPackage.warrantyTerms.length) {
            console.error('🔍 Package has no terms:', selectedPackage);
            this.showErrorMessage('No terms available for this package.');
            return;
        }
        
        const selectedTerm = selectedPackage.warrantyTerms.find(term => term.Id === termId);
        if (!selectedTerm) {
            console.error('🔍 Term not found in package:', termId, selectedPackage.warrantyTerms);
            this.showErrorMessage('Term not found. Please try again.');
            return;
        }
        
        // Now set both package and term synchronously in a single operation
        // Auto-select the package if it's not already selected
        if (!this.selectedDealerPackage || this.selectedDealerPackage.Id !== packageId) {
            // Check if this is a different package than currently selected
            const isPackageChange = this.selectedDealerPackage && this.selectedDealerPackage.Id !== selectedPackage.Id;
            
            if (isPackageChange) {
                console.log('📦 [GAP] Package changed - will save when user clicks Continue');
                
                // CRITICAL: Clear ALL additional options when package changes
                console.log('🧹 [GAP] Clearing additional options for new package');
                this.selectedAdditionalOptions = [];
                this.existingAdditionalOptions = [];
                this.selectedNewOptions = [];
                this.optionsToRemove = [];
                this.commercialOptions = [];
                this.downPaymentOptions = [];
                this.filteredDownPaymentOptions = [];
            }
            
            // Track the package change
            const oldPackageId = this.originalGapData.selectedDealerPackageId;
            const newPackageId = selectedPackage.Id;
            
            // Set package synchronously
            this.selectedDealerPackage = selectedPackage;
            this.selectedProgram = selectedPackage.PackageName;
            
            // Track change for auto-save
            this.trackGapChange('package', oldPackageId, newPackageId);
            
            // Load additional options for the selected package (don't await - do it in background)
            // This ensures term selection can proceed immediately without waiting
            this.loadAdditionalOptionsByPackage(selectedPackage.Id).catch(err => {
                console.error('Error loading additional options:', err);
            });
        }
        
        // Check if user has additional options selected and warn them
        const hasSelectedOptions = this.selectedNewOptions.length > 0;
        
        if (hasSelectedOptions) {
            const proceed = await this.confirmTermChangeWithOptions(selectedTerm);
            if (!proceed) {
                return; // User cancelled
            }
        }
        
        // Track the term change
        const oldTermId = this.originalGapData.selectedWarrantyTermId;
        const newTermId = selectedTerm.Id;
        
        // Reset any manual price override when a new term is selected
        this.isPriceOverridden = false;
        this.isPriceEditMode = false;
        this.priceOverrideInput = '';

        // Set the selected term - this is a tracked property so it will trigger reactive updates
        // Use Promise.resolve() to ensure the state update happens in the next microtask
        // This ensures the getter sees the updated value when it recalculates
        this.selectedWarrantyTerm = selectedTerm;
        
        // DO NOT clear user selections when switching terms - options are package-level
        // this.clearAdditionalOptionsForTermSwitch();
        
        // Track change for auto-save
        this.trackGapChange('term', oldTermId, newTermId);
        
        // ✅ IMPORTANT: Additional options are loaded at PACKAGE level, NOT term level
        // They persist and remain visible when switching terms within the same package
        // DO NOT reload options here - they stay from package selection
        console.log('🔍 Additional options remain from package selection:', this.availableAdditionalOptionsData?.length || 0);
        
        this.updatePrice();
        this.saveDataToSession();
        
        console.log('🔍 handleGapTermSelection - Term selected, will create package on Continue');
        console.log('🔍 Commercial options count:', this.commercialOptions?.length || 0);
        console.log('🔍 Down Payment options count:', this.downPaymentOptions?.length || 0);
        console.log('🔍 Selected term ID:', this.selectedWarrantyTerm?.Id);
        console.log('🔍 Selected term object:', this.selectedWarrantyTerm);
        
        // Force re-render immediately - the reactive getter will automatically update rowClass
        // Since selectedWarrantyTerm is @track, setting it above will trigger reactivity
        // The getter checks: isTermSelected = this.selectedWarrantyTerm && this.selectedWarrantyTerm.Id === term.Id
        this.renderKey++;
    }
    
    // Force highlighting update by manually applying CSS classes to DOM
    forceHighlightingUpdate() {
        try {
            // Remove 'selected' class from ALL accordion sections - we don't want to highlight the box
            this.template.querySelectorAll('lightning-accordion-section').forEach(section => {
                section.classList.remove('selected', 'program-section-selected');
            });
            
            // Remove 'selected' class from all terms first
            this.template.querySelectorAll('[data-term]').forEach(termEl => {
                termEl.classList.remove('selected');
            });
            
            // Find and highlight ONLY the selected term button
            if (this.selectedWarrantyTerm) {
                const termElement = this.template.querySelector(`[data-term="${this.selectedWarrantyTerm.Id}"]`);
                if (termElement) {
                    termElement.classList.add('selected');
                }
            }
        } catch (error) {
            console.error('Error in forceHighlightingUpdate:', error);
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
            
            
            const result = await updateTotalLossApplicationPackage(packageDataMap);
            
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
    
    // Handle compare package
    handleComparePackage(event) {
        const packageId = event.currentTarget.dataset.package;
        const packageToCompare = this.dealerPackages.find(pkg => pkg.Id === packageId);
        
        if (packageToCompare) {
            // Check if package is already in compare list
            const existingIndex = this.comparePackages.findIndex(pkg => pkg.Id === packageId);
            
            if (existingIndex >= 0) {
                // Remove from compare list
                this.comparePackages.splice(existingIndex, 1);
                console.log('✅ Removed package from compare:', packageToCompare.PackageName);
            } else {
                // Add to compare list (max 3 packages)
                if (this.comparePackages.length < 3) {
                    this.comparePackages.push(packageToCompare);
                    console.log('✅ Added package to compare:', packageToCompare.PackageName);
                } else {
                    this.showError = true;
                    this.errorMessage = 'You can compare up to 3 packages at a time.';
                    return;
                }
            }
            
            // Update compare list
            this.comparePackages = [...this.comparePackages];
            
            // Show compare modal if we have packages to compare
            if (this.comparePackages.length > 0) {
                this.showCompareModal = true;
            }
        }
    }
    
    // Close compare modal
    closeCompareModal() {
        this.showCompareModal = false;
    }
    
    // Handle compare toggle for terms
    
    // Update compare button visibility and text
    updateCompareButton() {
        this.showCompareButton = this.selectedForComparison.length > 0;
        this.compareButtonText = `Compare ${this.selectedForComparison.length} Term${this.selectedForComparison.length > 1 ? 's' : ''}`;
    }
    
    
    
    // Close comparison modal
    closeComparison() {
        this.showComparisonModal = false;
    }
    
    // Clear comparison selection
    clearComparison() {
        this.selectedForComparison = [];
        this.showCompareButton = false;
        this.comparisonTerms = [];
        
        // Uncheck all compare checkboxes
        const checkboxes = this.template.querySelectorAll('.compare-checkbox');
        checkboxes.forEach(checkbox => {
            checkbox.checked = false;
        });
    }
    
    // Select term from comparison
    async selectFromComparison(event) {
        const termId = event.target.dataset.term;
        
        // Find and select the term
        for (const pkg of this.dealerPackages) {
            if (pkg.warrantyTerms) {
                const term = pkg.warrantyTerms.find(t => t.Id === termId);
                if (term) {
                    this.selectedDealerPackage = pkg;
                    this.selectedWarrantyTerm = term;
                    this.updatePrice();
                    this.saveWarrantyData();
                    console.log('🔍 selectFromComparison - Term selected, will create package on Continue');
                    // Don't create application package here - will be handled on Continue
                    this.closeComparison();
                    this.showToast('Success', 'Warranty term selected successfully!', 'success');
                    break;
                }
            }
        }
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
        // Only Lien Holder is required
        if (!this.lenderLienholder) {
            this.errorMessage = 'Lien Holder / Financial Institution is required.';
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
        const gapData = {
            selectedProgram: this.selectedProgram,
            selectedTerm: this.selectedTerm,
            selectedClaim: this.selectedClaim,
            selectedDeductible: this.selectedDeductible,
            testDrive: this.testDrive,
            price: this.price,
            selectedDealerPackage: this.selectedDealerPackage,
            selectedWarrantyTerm: this.selectedWarrantyTerm,
        };
        
        sessionStorage.setItem('gapData', JSON.stringify(gapData));
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
            
            // Restore selected dealer package if available
            if (data.selectedDealerPackage) {
                this.selectedDealerPackage = data.selectedDealerPackage;
                console.log('✅ Restored selected dealer package:', this.selectedDealerPackage);
            }
            
            // Restore selected warranty term if available
            if (data.selectedWarrantyTerm) {
                this.selectedWarrantyTerm = data.selectedWarrantyTerm;
                console.log('✅ Restored selected warranty term:', this.selectedWarrantyTerm);
            }
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
    
    handleDeclineGap() {
        this.showDeclineModal = true;
    }
    
    // Handle confirm decline from modal - REMOVED DUPLICATE
    // The correct version is at line 1401
    
    // Handle cancel decline from modal
    cancelDeclineGap() {
        this.showDeclineModal = false;
    }
    
    
    // Handle back button click
    handleBack() {
        console.log('🔙 Back button clicked from gap component');
        
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
    async handleSaveAsQuote() {
        console.log('💾 Save as Quote - Loan Protection (GAP) tab');
        
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
        
        this.loading = true;
        
        try {
            // If there's a selected package, save it first
            if (this.selectedDealerPackage && this.selectedGapTerm) {
                const packageData = {
                    applicationId: this.applicationId,
                    dealerId: this.selectedDealerPackage.DealerId,
                    dealerPackageId: this.selectedDealerPackage.Id,
                    packageName: this.selectedDealerPackage.PackageName,
                    selectedTermId: this.selectedGapTerm.Id,
                    lenderLienholder: this.lenderLienholder,
                    financeLoanTerm: this.selectedFinanceTerm,
                    loanAmount: this.loanAmount,
                    interestRate: this.interestRate,
                    paymentFrequency: this.selectedPaymentFrequency,
                    dealerPriceOverride: this.isPriceOverridden ? this.price : null
                };
                
                packageData.recordType = 'GAP_Coverage';
                
                const result = await savePackageWithActiveManagement({
                    packageDataMap: packageData
                });
                
                if (!result.success) {
                    this.errorMessage = 'Failed to save loan protection selection: ' + result.message;
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
            
        } catch (error) {
            console.error('❌ Error in handleSaveAsQuote:', error);
            this.errorMessage = 'Error processing loan protection selection. Please try again.';
            this.showError = true;
        } finally {
            this.loading = false;
        }
    }

    handleSkip() {
        console.log('⏭️ Loan Protection tab skipped - navigating to next tab without saving');
        this.dispatchEvent(new CustomEvent('gapcomplete', {
            detail: { 
                success: true,
                skipped: true,
                applicationId: this.applicationId
            }
        }));
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
            // Custom price is pre-tax; calculate tax and add to total
            const customPreTax = parseFloat(val.toFixed(2));
            const taxRate = this._getCurrentTaxRate();
            const taxAmount = taxRate > 0 ? customPreTax * (taxRate / 100) : 0;
            this._overridePreTaxPrice = customPreTax;
            this._overrideTaxAmount = parseFloat(taxAmount.toFixed(2));
            this.price = parseFloat((customPreTax + taxAmount).toFixed(2));
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
        } else {
            this.updatePrice();
        }
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
        
        // For Draft/Pending, always recalculate from current term pricing so admin changes reflect
        const upAppStatus = this.applicationStatus || '';
        const shouldUseStoredPrice = isSameTerm && !['Draft', 'Pending', 'Quote'].includes(upAppStatus);
        
        if (shouldUseStoredPrice) {
            // For submitted/active applications with same term, use stored pricing directly from Application_Package__c.
            const hasStoredOverride = this.existingApplicationPackage.dealerPriceOverride != null &&
                                      this.existingApplicationPackage.dealerPriceOverride !== undefined;
            if (hasStoredOverride) {
                const basePrice = this.existingApplicationPackage.contractPremiumPriceWithoutTax || 0;
                const taxAmount = this.existingApplicationPackage.taxAmount || 0;
                this.price = parseFloat((basePrice + taxAmount).toFixed(2));
            } else {
                this.price = this.existingApplicationPackage.contractPremiumPrice || 0;
            }
            
            console.log('💰 Existing app price (using stored values from Application_Package__c):', {
                dealerPackagePrice: this.existingApplicationPackage.dealerPackagePrice,
                dealerMarkup: this.existingApplicationPackage.dealerMarkup,
                dealerPackageRetailPrice: this.existingApplicationPackage.dealerPackageRetailPrice,
                contractPremiumPriceWithoutTax: this.existingApplicationPackage.contractPremiumPriceWithoutTax,
                taxPercentage: this.existingApplicationPackage.taxPercentage,
                taxAmount: this.existingApplicationPackage.taxAmount,
                contractPremiumPrice: this.existingApplicationPackage.contractPremiumPrice,
                total: this.price
            });
        } else if (this.isExistingApplication && this.existingApplicationPackage) {
            // For existing applications but different term, calculate with tax
            const basePrice = this.existingApplicationPackage.dealerPackagePrice || 0;
            const markup = this.existingApplicationPackage.dealerMarkup || 0;
            const priceWithMarkup = basePrice + markup;
            
            // Calculate existing additional options price (minus ones marked for removal)
            const existingOptionsPrice = this.existingAdditionalOptions
                .filter(option => !this.optionsToRemove.includes(option.id))
                .reduce((total, option) => total + (option.retailPrice || 0), 0);
            
            // Calculate new additional options price
            const newOptionsPrice = this.selectedNewOptions.reduce((total, optionId) => {
                const option = this.availableAdditionalOptionsData.find(opt => opt.id === optionId);
                return total + (option ? (option.retailPrice || option.netCost || 0) : 0);
            }, 0);
            
            // Calculate total taxable amount (term retail price + all additional options)
            const totalTaxableAmount = priceWithMarkup + existingOptionsPrice + newOptionsPrice;
            
            // Calculate tax on total taxable amount
            const taxRate = this.existingApplicationPackage.taxPercentage || 0;
            let taxAmount = 0;
            if (taxRate > 0) {
                taxAmount = totalTaxableAmount * (taxRate / 100);
            } else if (this.existingApplicationPackage.taxAmount !== undefined && this.existingApplicationPackage.taxAmount !== null) {
                // Fallback to stored taxAmount if taxRate not available
                taxAmount = this.existingApplicationPackage.taxAmount || 0;
            }
            
            this.price = totalTaxableAmount + taxAmount;
            console.log('💰 Existing app price calculation (with tax):', {
                basePrice,
                markup,
                priceWithMarkup,
                taxAmount,
                existingOptionsPrice,
                newOptionsPrice,
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
            
            // Calculate total taxable amount (term retail price + additional options)
            const totalTaxableAmount = priceWithMarkup + newOptionsPrice;
            
            // Calculate tax on total taxable amount - use taxRate (term taxAmount is only for term, recalculate for total)
            let taxAmount = 0;
            const taxRate = this.selectedWarrantyTerm.taxRate || this.selectedDealerPackage?.taxRate || 0;
            if (taxRate > 0) {
                taxAmount = totalTaxableAmount * (taxRate / 100);
            }
            
            // Total price = taxable amount + tax
            this.price = totalTaxableAmount + taxAmount;
            console.log('💰 New selection price calculation:', {
                netCost,
                markup,
                markupType,
                priceWithMarkup,
                newOptionsPrice,
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
            console.log('💰 No valid pricing data, setting price to 0');
        }
        
        console.log('💰 Final price:', this.price);
        console.log('💰 === UPDATE PRICE END ===');
    }
    
    // Price breakdown modal methods
    showPriceBreakdownModal() {
        console.log('💰 Showing price breakdown modal');
        console.log('🔍 Price breakdown conditions:', {
            isExistingApplication: this.isExistingApplication,
            hasExistingPackage: !!this.existingApplicationPackage,
            hasSelectedWarrantyTerm: !!this.selectedWarrantyTerm,
            selectedWarrantyTermId: this.selectedWarrantyTerm?.Id
        });
        
        // Enhanced null safety check
        if (!this.selectedWarrantyTerm) {
            console.log('⚠️ No warranty term selected for price breakdown');
            return;
        }
        
        if (!this.selectedWarrantyTerm.packageTermName && !this.selectedWarrantyTerm.Name) {
            console.log('⚠️ Selected warranty term has no name property');
            return;
        }
        
        // Check if user selected a different term than the stored one
        const isSameTerm = this.isExistingApplication && 
                          this.existingApplicationPackage && 
                          this.selectedWarrantyTerm && 
                          this.selectedWarrantyTerm.Id === this.existingApplicationPackage.selectedTermId;
        
        const bdAppStatus = this.applicationStatus || '';
        const useStoredForBreakdown = isSameTerm && !['Draft', 'Pending', 'Quote'].includes(bdAppStatus);
        
        let netCost, markup, retailPrice, totalPrice;
        
        if (useStoredForBreakdown) {
            // For submitted/active applications with same term, use stored values directly from Application_Package__c
            netCost = this.existingApplicationPackage.dealerPackagePrice || 0;
            markup = this.existingApplicationPackage.dealerMarkup || 0;
            retailPrice = this.existingApplicationPackage.dealerPackageRetailPrice || 0;
            
            // Use stored tax values
            const taxRate = this.existingApplicationPackage.taxPercentage || 0;
            const taxAmount = this.existingApplicationPackage.taxAmount || 0;
            
            console.log('🔍 Existing app price breakdown (using stored values):', {
                netCost: netCost,
                markup: markup,
                retailPrice: retailPrice,
                taxRate: taxRate,
                taxAmount: taxAmount,
                contractPremiumPriceWithoutTax: this.existingApplicationPackage.contractPremiumPriceWithoutTax,
                contractPremiumPrice: this.existingApplicationPackage.contractPremiumPrice
            });
            
            // Use stored total price directly
            totalPrice = this.existingApplicationPackage.contractPremiumPrice || 0;
        } else if (this.isExistingApplication && this.existingApplicationPackage) {
            // For existing applications but different term, calculate with tax
            netCost = this.existingApplicationPackage.dealerPackagePrice || 0;
            markup = this.existingApplicationPackage.dealerMarkup || 0;
            retailPrice = netCost + markup;
            
            // Calculate tax - use stored taxAmount if available, otherwise calculate from taxRate
            let taxAmount = 0;
            if (this.existingApplicationPackage.taxAmount !== undefined && this.existingApplicationPackage.taxAmount !== null) {
                taxAmount = this.existingApplicationPackage.taxAmount || 0;
            } else {
                const taxRate = this.existingApplicationPackage.taxPercentage || 0;
                if (taxRate > 0) {
                    taxAmount = retailPrice * (taxRate / 100);
                }
            }
            
            console.log('🔍 Existing app price breakdown (with tax):', {
                netCost: netCost,
                markup: markup,
                retailPrice: retailPrice,
                taxAmount: taxAmount
            });
            
            // Calculate existing additional options price (minus ones marked for removal)
            const existingOptionsPrice = this.existingAdditionalOptions
                .filter(option => !this.optionsToRemove.includes(option.id))
                .reduce((total, option) => total + (option.retailPrice || 0), 0);
            
            // Calculate new additional options price
            const newOptionsPrice = this.selectedNewOptions.reduce((total, optionId) => {
                const option = this.availableAdditionalOptionsData.find(opt => opt.id === optionId);
                return total + (option ? (option.retailPrice || option.netCost || 0) : 0);
            }, 0);
            
            // Calculate total taxable amount (term retail price + all additional options)
            const totalTaxableAmount = retailPrice + existingOptionsPrice + newOptionsPrice;
            
            // Calculate tax on total taxable amount
            const taxRate = this.existingApplicationPackage.taxPercentage || 0;
            if (taxRate > 0) {
                taxAmount = totalTaxableAmount * (taxRate / 100);
            }
            
            // Total price includes total taxable amount + tax
            totalPrice = totalTaxableAmount + taxAmount;
        } else if (this.selectedWarrantyTerm) {
            // For new selections, calculate price with tax explicitly
            netCost = this.selectedWarrantyTerm.netCost || 0;
            const markupValue = this.selectedWarrantyTerm.markup || 0;
            const markupType = this.selectedWarrantyTerm.markupType || '';
            
            // Calculate the actual markup amount for display
            if (markupType === '%' && markupValue > 0) {
                markup = netCost * markupValue / 100;
            } else if (markupType === '$' && markupValue > 0) {
                markup = markupValue;
            } else {
                markup = 0; // No markup
            }
            
            // Retail price is netCost + markup (before tax)
            retailPrice = netCost + markup;
            
            // Get tax rate (term taxAmount is only for term, we'll recalculate for total)
            const taxRate = this.selectedWarrantyTerm.taxRate || this.selectedDealerPackage?.taxRate || 0;
            
            // Add new additional options pricing
            const newOptionsPrice = this.selectedNewOptions.reduce((total, optionId) => {
                const option = this.availableAdditionalOptionsData.find(opt => opt.id === optionId);
                return total + (option ? (option.retailPrice || option.netCost || 0) : 0);
            }, 0);
            
            // Calculate total taxable amount (term retail price + additional options)
            const totalTaxableAmount = retailPrice + newOptionsPrice;
            
            // Calculate tax on total taxable amount
            let taxAmount = 0;
            if (taxRate > 0) {
                taxAmount = totalTaxableAmount * (taxRate / 100);
            }
            
            // Debug logging for price breakdown
            console.log('🔍 Price breakdown debug:', {
                termId: this.selectedWarrantyTerm?.Id,
                termName: this.selectedWarrantyTerm?.packageTermName || this.selectedWarrantyTerm?.Name,
                netCost: netCost,
                markupValue: markupValue,
                markupType: markupType,
                markup: markup,
                taxRate: taxRate,
                taxAmount: taxAmount,
                retailPrice: retailPrice,
                newOptionsPrice: newOptionsPrice,
                totalTaxableAmount: totalTaxableAmount,
                totalPrice: totalTaxableAmount + taxAmount
            });
            
            // Total price includes total taxable amount + tax
            totalPrice = totalTaxableAmount + taxAmount;
        } else {
            netCost = markup = retailPrice = totalPrice = 0;
        }
        
        // Get tax information for display - calculate on total taxable amount
        let displayTaxAmount = 0;
        let displayTaxRate = 0;
        
        // Calculate total taxable amount for tax calculation
        let totalTaxableForDisplay = retailPrice;
        if (!isSameTerm) {
            // Add options for new selections
            if (this.selectedNewOptions && this.selectedNewOptions.length > 0) {
                const optionsPrice = this.selectedNewOptions.reduce((total, optionId) => {
                    const option = this.availableAdditionalOptionsData.find(opt => opt.id === optionId);
                    return total + (option ? (option.retailPrice || option.netCost || 0) : 0);
                }, 0);
                totalTaxableForDisplay += optionsPrice;
            }
        } else if (isSameTerm || (this.isExistingApplication && this.existingApplicationPackage)) {
            // Add existing and new options for existing applications
            const existingOptionsPrice = this.existingAdditionalOptions
                .filter(option => !this.optionsToRemove.includes(option.id))
                .reduce((total, option) => total + (option.retailPrice || 0), 0);
            const newOptionsPrice = this.selectedNewOptions.reduce((total, optionId) => {
                const option = this.availableAdditionalOptionsData.find(opt => opt.id === optionId);
                return total + (option ? (option.retailPrice || option.netCost || 0) : 0);
            }, 0);
            totalTaxableForDisplay += existingOptionsPrice + newOptionsPrice;
        }
        
        if (isSameTerm || (this.isExistingApplication && this.existingApplicationPackage)) {
            displayTaxRate = this.existingApplicationPackage.taxPercentage || 0;
            if (displayTaxRate > 0) {
                displayTaxAmount = totalTaxableForDisplay * (displayTaxRate / 100);
            } else {
                displayTaxAmount = this.existingApplicationPackage.taxAmount || 0;
            }
        } else if (this.selectedWarrantyTerm) {
            displayTaxRate = this.selectedWarrantyTerm.taxRate || this.selectedDealerPackage?.taxRate || 0;
            if (displayTaxRate > 0) {
                displayTaxAmount = totalTaxableForDisplay * (displayTaxRate / 100);
            }
        } else if (this.selectedDealerPackage && this.selectedDealerPackage.taxRate) {
            displayTaxRate = this.selectedDealerPackage.taxRate || 0;
            if (displayTaxRate > 0) {
                displayTaxAmount = totalTaxableForDisplay * (displayTaxRate / 100);
            }
        }
        
        // When price is overridden, show custom price + tax breakdown
        if (this.isPriceOverridden) {
            const overrideTaxRate = this._getCurrentTaxRate();
            const overridePreTax = this._overridePreTaxPrice || this.price;
            const overrideTax = this._overrideTaxAmount || 0;
            this.currentPriceBreakdown = {
                netCost: '—',
                markup: '—',
                retailPrice: this.formatPrice(overridePreTax),
                taxRate: overrideTaxRate > 0 ? overrideTaxRate.toFixed(2) + '%' : '0%',
                taxAmount: this.formatPrice(overrideTax),
                totalPrice: this.formatPrice(this.price)
            };
            // Populate dealer reference pricing for toggle
            this.dealerReferenceBreakdown = {
                netCost: this.formatPrice(netCost),
                markup: this.formatPrice(markup),
                retailPrice: this.formatPrice(retailPrice),
                taxRate: displayTaxRate > 0 ? displayTaxRate.toFixed(2) + '%' : '0%',
                taxAmount: this.formatPrice(displayTaxAmount),
                totalPrice: this.formatPrice(totalPrice)
            };
        } else {
            this.currentPriceBreakdown = {
                netCost: this.formatPrice(netCost),
                markup: this.formatPrice(markup),
                retailPrice: this.formatPrice(retailPrice),
                taxRate: displayTaxRate > 0 ? displayTaxRate.toFixed(2) + '%' : '0%',
                taxAmount: this.formatPrice(displayTaxAmount),
                totalPrice: this.formatPrice(totalPrice)
            };
        }
        
        this.showPriceModal = true;
    }
    
    handleToggleDealerReference(event) {
        this.showDealerReferencePrice = event.target.checked;
    }

    hidePriceBreakdownModal() {
        this.showPriceModal = false;
        this.showDealerReferencePrice = false;
    }
    
    stopPropagation(event) {
        event.stopPropagation();
    }
    
    
    
    // Create or update application package
    async createOrUpdateApplicationPackage() {
        console.log('🔍 ===== createOrUpdateApplicationPackage CALLED =====');
        console.log('🔍 Call stack:', new Error().stack);
        console.log('🔍 Timestamp:', new Date().toISOString());
        
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
                dealerPriceOverride: this.isPriceOverridden ? this.price : null,
                // GAP input fields to persist on Application_Package__c
                lenderLienholder: this.lenderLienholder || null,
                financeLoanTerm: this.financeLoanTerm || null,
                loanAmount: this.loanAmount !== '' ? this.loanAmount : null,
                interestRate: this.interestRate !== '' ? this.interestRate : null,
                paymentFrequency: this.paymentFrequency || null,
            };
            
            console.log('📦 [GAP createOrUpdate] Saving with active management:', packageData);
            
            // ========== NEW ACTIVE MANAGEMENT CODE ==========
            packageData.recordType = 'GAP_Coverage';
            
            const result = await savePackageWithActiveManagement({
                packageDataMap: packageData
            });
            
            console.log('✅ [GAP createOrUpdate] Save result:', result);
            
            /* ========== OLD CODE (RESTORE IF NEEDED) ==========
            const existingPackage = await getTotalLossExistingApplicationPackageByRecordType({ 
                applicationId: this.applicationId, 
                recordType: 'GAP_Coverage' 
            });
            
            let result;
            if (existingPackage && existingPackage.data && existingPackage.data.Id) {
                result = await updateTotalLossApplicationPackage({
                    packageId: existingPackage.data.Id,
                    selectedTermId: packageData.selectedTermId,
                    includeDeductible: false,
                    lenderLienholder: this.lenderLienholder || null,
                    financeLoanTerm: this.financeLoanTerm || null,
                    loanAmount: this.loanAmount !== '' ? this.loanAmount : null,
                    interestRate: this.interestRate !== '' ? this.interestRate : null,
                    paymentFrequency: this.paymentFrequency || null,
                });
            } else {
                packageData.recordType = 'GAP_Coverage';
                result = await createTotalLossApplicationPackageFromMap({packageDataMap: packageData});
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
                tab: 'gap',
                completed: this.selectedWarrantyTerm !== null
            },
            bubbles: true
        });
        this.dispatchEvent(completionEvent);
    }
    
    formatPrice(price) {
        return new Intl.NumberFormat('en-CA', {
            style: 'currency',
            currency: 'CAD',
            minimumFractionDigits: 2
        }).format(price || 0);
    }
    
    // Get vehicle display name
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
    
    // Test method to verify component functionality
    @api
    async testComponent() {
        try {
            console.log('🧪 Testing gap component...');
            console.log('✅ Component is working correctly');
            return { success: true, message: 'Gap component is functional' };
        } catch (error) {
            console.error('❌ Component test error:', error);
            return { success: false, error: error.message };
        }
    }
    
    // Method to manually set application ID for testing
    @api
    setApplicationId(id) {
        console.log('🔒 Manually setting applicationId to:', id);
        this._applicationId = id;
        console.log('🔒 applicationId now set to:', this.applicationId);
        
        // Use the proper flow: check existing package first, then load packages
        if (id) {
            this.checkForExistingApplicationPackage()
                .then(() => {
                    // Hydrate filters from existing package if found
                    if (this.isExistingApplication && this.existingApplicationPackage) {
                        const pkg = this.existingApplicationPackage;
                        this.lenderLienholder = (pkg.lenderLienholder != null && pkg.lenderLienholder !== '') ? pkg.lenderLienholder : this.lenderLienholder;
                        this.financeLoanTerm = (pkg.financeLoanTerm != null && pkg.financeLoanTerm !== '') ? String(pkg.financeLoanTerm) : this.financeLoanTerm;
                        this.loanAmount = (pkg.loanAmount != null && pkg.loanAmount !== '') ? String(pkg.loanAmount) : this.loanAmount;
                        this.interestRate = (pkg.interestRate != null && pkg.interestRate !== '') ? String(pkg.interestRate) : this.interestRate;
                        this.paymentFrequency = (pkg.paymentFrequency != null && pkg.paymentFrequency !== '') ? pkg.paymentFrequency : this.paymentFrequency;
                        this.renderKey++;
                    }
                    return this.loadDealerPackages();
                });
        }
    }
    
    async handleContinue() {
        console.log('🔍 ===== handleContinue CALLED =====');
        console.log('🔍 Call stack:', new Error().stack);
        console.log('🔍 Timestamp:', new Date().toISOString());
        console.log('🔍 selectedDealerPackage:', this.selectedDealerPackage);
        console.log('🔍 selectedWarrantyTerm:', this.selectedWarrantyTerm);
        console.log('🔍 applicationId:', this.applicationId);
        
        // Check if applicationId is missing
        if (!this.applicationId) {
            console.error('❌ CRITICAL: applicationId is missing!');
            
            // Try to get application ID from URL as fallback
            const urlParams = new URLSearchParams(window.location.search);
            const applicationIdFromUrl = urlParams.get('c__applicationId') || urlParams.get('applicationId');
            
            if (applicationIdFromUrl) {
                console.log('🔒 Found applicationId in URL, setting it:', applicationIdFromUrl);
                this._applicationId = applicationIdFromUrl;
            } else {
                this.errorMessage = 'Application ID is missing. Please refresh the page and try again.';
                this.showError = true;
                return;
            }
        }
        
        // Validate the form before continuing
        if (this.validateForm()) {
            console.log('✅ Form validation passed');
            this.loading = true;
            
            try {
                // If no package selected, just save lien holder data and continue
                if (!this.selectedDealerPackage || !this.selectedWarrantyTerm) {
                    console.log('🔍 No GAP package selected — saving lien holder data and continuing');
                    // Persist lien holder to session storage
                    const gapData = {
                        lenderLienholder: this.lenderLienholder || null,
                        financeLoanTerm: this.financeLoanTerm || null,
                        loanAmount: this.loanAmount !== '' ? this.loanAmount : null,
                        interestRate: this.interestRate !== '' ? this.interestRate : null,
                        paymentFrequency: this.paymentFrequency || null,
                    };
                    sessionStorage.setItem('gapInputData', JSON.stringify(gapData));
                    this.loading = false;
                    this.dispatchEvent(new CustomEvent('gapcomplete', {
                        detail: {
                            applicationId: this.applicationId,
                            skipped: true
                        }
                    }));
                    return;
                }

                // Create application package in Salesforce
                console.log('========================================');
                console.log('🔍 DEBUG: Starting Application Package Creation');
                console.log('========================================');
                console.log('🔍 DEBUG: this.applicationId =', this.applicationId);
                console.log('🔍 DEBUG: this.selectedDealerPackage =', JSON.stringify(this.selectedDealerPackage, null, 2));
                console.log('🔍 DEBUG: this.selectedWarrantyTerm =', JSON.stringify(this.selectedWarrantyTerm, null, 2));
                console.log('🔍 DEBUG: DealerId =', this.selectedDealerPackage.DealerId);
                console.log('🔍 DEBUG: DealerPackageId =', this.selectedDealerPackage.Id);
                console.log('🔍 DEBUG: PackageName =', this.selectedDealerPackage.PackageName);
                console.log('🔍 DEBUG: SelectedTermId =', this.selectedWarrantyTerm.Id);
                
                const packageData = {
                    applicationId: this.applicationId,
                    dealerId: this.selectedDealerPackage.DealerId,
                    dealerPackageId: this.selectedDealerPackage.Id,
                    packageName: this.selectedDealerPackage.PackageName,
                    selectedTermId: this.selectedWarrantyTerm.Id,
                    dealerPriceOverride: this.isPriceOverridden ? this.price : null,
                    // GAP input fields to persist on Application_Package__c
                    lenderLienholder: this.lenderLienholder || null,
                    financeLoanTerm: this.financeLoanTerm || null,
                    loanAmount: this.loanAmount !== '' ? this.loanAmount : null,
                    interestRate: this.interestRate !== '' ? this.interestRate : null,
                    paymentFrequency: this.paymentFrequency || null,
                };
                
                console.log('🔍 DEBUG: packageData object =', JSON.stringify(packageData, null, 2));
                console.log('🔍 DEBUG: Type checks:');
                console.log('  - applicationId type:', typeof packageData.applicationId);
                console.log('  - dealerId type:', typeof packageData.dealerId);
                console.log('  - dealerPackageId type:', typeof packageData.dealerPackageId);
                console.log('  - packageName type:', typeof packageData.packageName);
                console.log('  - selectedTermId type:', typeof packageData.selectedTermId);
                console.log('========================================');
                
                // ========== NEW ACTIVE MANAGEMENT CODE ==========
                packageData.recordType = 'GAP_Coverage';
                
                console.log('🔍 [GAP handleContinue] BEFORE SAVE:', packageData);
                
                const result = await savePackageWithActiveManagement({
                    packageDataMap: packageData
                });
                
                console.log('🔍 [GAP handleContinue] AFTER SAVE:', result);
                
                let applicationPackageId;
                if (result.success && result.data) {
                    applicationPackageId = result.data.packageId;
                    console.log('✅ [GAP] Package saved:');
                    console.log('   📌 Package ID:', applicationPackageId);
                    console.log('   📌 Is New:', result.data.isNewPackage);
                    console.log('   📌 Changed:', result.data.isPackageChange);
                    console.log('   📌 Active:', result.data.active);
                }
                
                /* ========== OLD CODE (RESTORE IF NEEDED) ==========
                let result;
                let applicationPackageId;
                
                if (this.isExistingApplication && this.existingApplicationPackage && this.existingApplicationPackage.Id) {
                    const isSamePackage = this.existingApplicationPackage.dealerPackageId === this.selectedDealerPackage.Id;
                    const isSameTerm = this.existingApplicationPackage.selectedTermId === (this.selectedWarrantyTerm ? this.selectedWarrantyTerm.Id : null);
                    
                    if (isSamePackage && isSameTerm) {
                        applicationPackageId = this.existingApplicationPackage.Id;
                        result = { success: true, recordId: applicationPackageId };
                    } else {
                        try {
                            await this.updateExistingApplicationPackage(this.selectedDealerPackage, this.selectedWarrantyTerm);
                            applicationPackageId = this.existingApplicationPackage.Id;
                            result = { success: true, recordId: applicationPackageId };
                        } catch (updateError) {
                            packageData.recordType = 'GAP_Coverage';
                            result = await createTotalLossApplicationPackageFromMap({packageDataMap: packageData});
                            applicationPackageId = result.recordId;
                        }
                    }
                } else {
                    packageData.recordType = 'GAP_Coverage';
                    result = await createTotalLossApplicationPackageFromMap({packageDataMap: packageData});
                    applicationPackageId = result.recordId;
                }
                ========== END OLD CODE ========== */
                
                if (result.success) {
                    console.log('✅ Application package processed successfully:', applicationPackageId);
                    
                    // Process additional options if any changes exist
                    if (this.hasAdditionalOptionsChanges()) {
                        console.log('💾 Processing additional options changes...');
                        const optionsResult = await this.processAdditionalOptionsChanges(applicationPackageId);
                        
                        if (!optionsResult.success) {
                            console.error('❌ Failed to save additional options:', optionsResult.message);
                            this.errorMessage = 'Warranty package saved, but failed to save additional options: ' + optionsResult.message;
                            this.showError = true;
                            return;
                        }
                        console.log('✅ Additional options processed successfully');
                    }
                    
                    // Save data to session storage
                    this.saveDataToSession();
                    
                    // Fire gap completion event to unlock next tab
                    this.dispatchEvent(new CustomEvent('gapcomplete', {
                        detail: { 
                            success: true,
                            gapData: this.getCurrentData(),
                            applicationId: this.applicationId
                        }
                    }));
                    
                    // Navigation will be handled automatically by the container
                    // after the warranty completion event is fired
                    console.log('🔍 Gap completed - container will handle navigation');
                    
                } else {
                    console.log('========================================');
                    console.error('❌ DEBUG: FAILED TO CREATE APPLICATION PACKAGE');
                    console.log('========================================');
                    console.error('❌ Result:', JSON.stringify(result, null, 2));
                    console.error('❌ Error Message:', result.message);
                    console.error('❌ Success:', result.success);
                    console.log('========================================');
                    this.errorMessage = 'Failed to save Total Loss Protection selection: ' + result.message;
                    this.showError = true;
                }
                
            } catch (error) {
                console.log('========================================');
                console.error('❌ DEBUG: EXCEPTION IN handleContinue');
                console.log('========================================');
                console.error('❌ Error:', error);
                console.error('❌ Error Message:', error.message);
                console.error('❌ Error Stack:', error.stack);
                console.log('========================================');
                this.errorMessage = 'Error processing Total Loss Protection selection. Please try again.';
                this.showError = true;
            } finally {
                this.loading = false;
            }
        } else {
            console.log('❌ Form validation failed');
        }
    }
    
    get selectedClaimLabel() {
        const claimOption = this.claimOptions.find(option => option.value === this.selectedClaim);
        return claimOption ? claimOption.label.split('/').slice(2).join('/').trim() : '';
    }
    
    // Check if gap is unlocked (has selected package)
    get isGapUnlocked() {
        return this.selectedDealerPackage !== null;
    }
    
    // Get gap status for display
    get gapStatus() {
        if (this.selectedDealerPackage) {
            return `✅ Total Loss Protection Package Selected: ${this.selectedDealerPackage.PackageName}`;
        }
        return '⚠️ Please select a Total Loss Protection package';
    }
    
    get hasPackages() {
        return this.dealerPackages && this.dealerPackages.length > 0;
    }
    
    
    get hasSelectedTerm() {
        return this.selectedWarrantyTerm !== null;
    }
    
    get formattedPrice() {
        return this.formatPrice(this.price);
    }
    
    
    get availableTerms() {
        if (!this.selectedDealerPackage || !this.selectedDealerPackage.warrantyTerms) {
            return [];
        }
        return this.selectedDealerPackage.warrantyTerms;
    }
    
    
    get compareButtonText() {
        return `Compare ${this.selectedForComparison.length} Term${this.selectedForComparison.length > 1 ? 's' : ''}`;
    }
    
    // Additional methods for the new functionality
    // handleBack method moved to avoid duplicates
    
    confirmDeclineGap() {
        this.selectedDealerPackage = null;
        this.selectedWarrantyTerm = null;
        this.price = 0.00;
        this.showDeclineModal = false;
        
        sessionStorage.removeItem('gapData');
        this.fireCompletionEvent();
    }
    
    closeGapModal() {
        this.showGapModal = false;
    }
    
    get gapStatus() {
        if (this.selectedDealerPackage && this.selectedWarrantyTerm) {
            return `Total Loss Protection Selected: ${this.selectedDealerPackage.PackageName} - ${this.selectedWarrantyTerm.packageTermName || this.selectedWarrantyTerm.Name || 'Unknown Term'}`;
        }
        return 'No Total Loss Protection selected';
    }

    get selectedTermName() {
        if (this.selectedWarrantyTerm) {
            return this.selectedWarrantyTerm.packageTermName || this.selectedWarrantyTerm.Name || 'No term selected';
        }
        return 'No term selected';
    }

    get selectedTermDuration() {
        if (this.selectedWarrantyTerm) {
            return this.selectedWarrantyTerm.durationRestrictionInMonths || 0;
        }
        return 0;
    }

    get selectedTermMileage() {
        if (this.selectedWarrantyTerm) {
            const mileage = this.selectedWarrantyTerm.mileageRestriction || 0;
            const unit = this.selectedWarrantyTerm.mileageUnit || 'KM';
            return `${mileage} ${unit}`;
        }
        return '0 KM';
    }

    // GAP Input Fields Getters
    get isFindPackagesDisabled() {
        return !this.lenderLienholder || !this.financeLoanTerm || !this.loanAmount || !this.interestRate || this.isLoadingPackages;
    }
    
    // Debug getter for template visibility
    get shouldShowInputFields() {
        const shouldShow = this.forceShowInputFields || (!this.isExistingApplication && !this.showPackageSelection);
        console.log('🔍 GAP - shouldShowInputFields:', shouldShow, '(isExistingApplication:', this.isExistingApplication, ', showPackageSelection:', this.showPackageSelection, ')');
        return shouldShow;
    }
    
    // Generate term display name based on input field data
    getTermDisplayName(term) {
        if (!this.lenderLienholder && !this.financeLoanTerm && !this.loanAmount && !this.interestRate) {
            // If no input data, show original term name
            return term.packageTermName || term.Name || 'Unknown Term';
        }
        
        // Create display name with input field information
        const parts = [];
        
        if (this.lenderLienholder) {
            parts.push(`Lender: ${this.lenderLienholder}`);
        }
        
        if (this.financeLoanTerm) {
            parts.push(`${this.financeLoanTerm} months`);
        }
        
        if (this.loanAmount) {
            parts.push(`$${this.formatNumber(this.loanAmount)}`);
        }
        
        if (this.interestRate) {
            parts.push(`${this.interestRate}% APR`);
        }
        
        return parts.length > 0 ? parts.join(' • ') : (term.packageTermName || term.Name || 'Unknown Term');
    }
    
    // Helper method to format numbers
    formatNumber(value) {
        if (!value) return '0';
        const num = parseFloat(value);
        return isNaN(num) ? '0' : num.toLocaleString();
    }
    
    // File handling methods
    handleFilesLoaded(event) {
        const fileDetails = event.detail;
        this.packageHasFiles = fileDetails.hasFiles;
        this.packageFileCount = fileDetails.fileCount;
        console.log('📁 Files loaded:', fileDetails);
        console.log('📁 Files hasFiles:', packageHasFiles);
        console.log('📁 Files fileCount:', packageFileCount);
    }
    
    get showPackageFiles() {
        return this.hasSelectedPackage && this.packageHasFiles;
    }
    
    get hasSelectedPackage() {
        return this.selectedDealerPackage !== null;
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
    
    // Compare functionality methods
    handleCompareToggle(event) {
        const termId = event.target.dataset.term;
        const isChecked = event.target.checked;
        
        if (isChecked) {
            if (this.selectedForComparison.length >= 4) {
                event.target.checked = false;
                this.showErrorMessage('You can only compare up to 4 terms at once.');
                return;
            }
            this.selectedForComparison.push(termId);
            console.log('✅ Added term to comparison (', this.selectedForComparison.length, '/4 )');
        } else {
            this.selectedForComparison = this.selectedForComparison.filter(id => id !== termId);
            console.log('❌ Removed term from comparison (', this.selectedForComparison.length, '/4 )');
        }
        
        this.updateCompareButton();
    }
    
    updateCompareButton() {
        this.showCompareButton = this.selectedForComparison.length > 1;
        console.log('🔍 Compare button updated - showing:', this.showCompareButton, 'terms selected:', this.selectedForComparison.length);
    }
    
    get compareButtonText() {
        const count = this.selectedForComparison.length;
        return `Compare ${count} Terms`;
    }
    
    openComparison() {
        console.log('🔍 Opening comparison with selected terms:', this.selectedForComparison);
        this.comparisonTerms = this.buildComparisonTerms();
        console.log('🔍 Comparison terms built:', this.comparisonTerms);
        this.showComparisonModal = true;
    }
    
    buildComparisonTerms() {
        const terms = [];
        
        this.selectedForComparison.forEach(termId => {
            // Find the term across all packages
            for (const pkg of this.dealerPackages) {
                if (pkg.warrantyTerms) {
                    const term = pkg.warrantyTerms.find(t => t.Id === termId);
                    if (term) {
                        terms.push({
                            id: term.Id,
                            name: term.packageTermName || term.Name || 'Unknown Term',
                            packageName: pkg.PackageName || pkg.Name || 'Unknown Package',
                            price: this.formatPrice(term.totalPrice || term.netCost || 0),
                            duration: term.durationRestrictionInMonths || term.durationMonths || term.duration || 'N/A',
                            mileage: term.mileageRestriction || term.mileage || 'N/A',
                            mileageUnit: term.mileageUnit || 'KM',
                            inputFieldInfo: this.getTermDisplayName(term), // Add input field information
                            includedOptions: (pkg.options || []).map(option => ({
                                id: option.Id || option.id,
                                name: option.optionName || option.Name || option.label || 'Unknown Option'
                            })),
                            buttonLabel: 'Select This Term',
                            buttonVariant: 'brand',
                            buttonDisabled: pkg.Id !== this.selectedDealerPackage?.Id // Only allow selection from selected package
                        });
                        console.log('🔍 Added term to comparison:', term.packageTermName || term.Name, 'from', pkg.PackageName);
                        break;
                    }
                }
            }
        });
        
        console.log('🔍 Built comparison with', terms.length, 'terms');
        return terms;
    }
    
    closeComparison() {
        this.showComparisonModal = false;
    }
    
    clearComparison() {
        this.selectedForComparison = [];
        this.showCompareButton = false;
        this.comparisonTerms = [];
        
        // Uncheck all compare checkboxes
        const checkboxes = this.template.querySelectorAll('.compare-checkbox');
        checkboxes.forEach(checkbox => {
            checkbox.checked = false;
        });
    }
    
    get comparisonTermsWithButtons() {
        return this.comparisonTerms.map(term => {
            // Find the package for this term
            let termPackage = null;
            for (const pkg of this.dealerPackages) {
                if (pkg.warrantyTerms) {
                    const foundTerm = pkg.warrantyTerms.find(t => t.Id === term.id);
                    if (foundTerm) {
                        termPackage = pkg;
                        break;
                    }
                }
            }
            
            const isSelected = this.selectedWarrantyTerm && this.selectedWarrantyTerm.Id === term.id;
            const isFromSelectedPackage = this.selectedDealerPackage && termPackage && termPackage.Id === this.selectedDealerPackage.Id;
            const canSelect = !this.selectedDealerPackage || isFromSelectedPackage; // Can select if no package selected or from selected package
            
            return {
                ...term,
                buttonLabel: isSelected ? 'Selected' : canSelect ? 'Select This Term' : 'Select Package First',
                buttonVariant: isSelected ? 'success' : canSelect ? 'brand' : 'neutral',
                buttonDisabled: !canSelect || isSelected
            };
        });
    }
    
    get availableTerms() {
        if (!this.selectedDealerPackage || !this.selectedDealerPackage.warrantyTerms) {
            return [];
        }
        return this.selectedDealerPackage.warrantyTerms;
    }
    
    get showNoPackageDisclaimer() {
        return this.packageSearchPerformed && !this.dealerHasGapPackages && this.dealerPackages.length === 0;
    }

    get showVehicleNotEligibleDisclaimer() {
        return this.packageSearchPerformed && this.dealerHasGapPackages && this.dealerPackages.length === 0;
    }

    get showPackagesList() {
        return !this.showNoPackageDisclaimer && !this.showVehicleNotEligibleDisclaimer;
    }

    get isContinueDisabled() {
        return false;
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
        return this.availableAdditionalOptionsData.map(option => ({
            ...option,
            isSelected: this.selectedAdditionalOptions.includes(option.id)
        }));
    }

    // Get available additional options display data
    get availableAdditionalOptionsDisplay() {
        return this.availableAdditionalOptionsData.map(option => ({
            ...option,
            isSelected: this.selectedNewOptions.includes(option.id)
        }));
    }

    // Get existing additional options display data - warranty style
    get existingAdditionalOptionsDisplay() {
        return this.existingAdditionalOptions.map(option => {
            const isMarkedForRemoval = this.optionsToRemove.includes(option.id);
            return {
            ...option,
                cssClass: isMarkedForRemoval ? 'additional-option-item-card option-removing' : 'additional-option-item-card',
                textClass: isMarkedForRemoval ? 'option-removing-text' : 'additional-option-item-text',
                priceClass: isMarkedForRemoval ? 'option-removing-text' : 'additional-option-price',
                buttonTitle: isMarkedForRemoval ? 'Undo Remove' : 'Remove',
                isMarkedForRemoval: isMarkedForRemoval
            };
        });
    }
    
    // Get package header banner class based on package name
    get packageHeaderBannerClass() {
        if (!this.selectedDealerPackage) {
            return 'package-header-banner gradient-default';
        }
        
        const packageName = (this.selectedDealerPackage.PackageName || '').toUpperCase();
        
        if (packageName.includes('PLATINUM')) {
            return 'package-header-banner gradient-default';
        } else if (packageName.includes('TITANIUM')) {
            return 'package-header-banner gradient-default';
        } else if (packageName.includes('GOLD')) {
            return 'package-header-banner gradient-default';
        } else if (packageName.includes('SILVER')) {
            return 'package-header-banner gradient-default';
        } else if (packageName.includes('BRONZE')) {
            return 'package-header-banner gradient-default';
        }
        
        return 'package-header-banner gradient-default';
    }
    
    // Check if there are no additional options
    get hasNoAdditionalOptions() {
        const hasExisting = this.existingAdditionalOptions && this.existingAdditionalOptions.length > 0;
        const hasAvailable = this.availableAdditionalOptionsDisplay && this.availableAdditionalOptionsDisplay.length > 0;
        return !hasExisting && !hasAvailable;
    }
    
    // Get warranty terms for selected package (warranty-style)
    get hasWarrantyTerms() {
        if (!this.selectedDealerPackage || !this.selectedDealerPackage.warrantyTerms) {
            return false;
        }
        return this.selectedDealerPackage.warrantyTerms.length > 0;
    }
    
    // Get selected package terms for display (warranty-style)
    get selectedPackageTerms() {
        if (!this.selectedDealerPackage || !this.selectedDealerPackage.warrantyTerms) {
            return [];
        }
        
        return this.selectedDealerPackage.warrantyTerms.map(term => {
            const isTermSelected = this.selectedWarrantyTerm && 
                                 this.selectedWarrantyTerm.Id === term.Id;
            
            const displayPrice = term.totalPrice || term.netCost || 0;
            const termRowClass = isTermSelected ? 'term-row selected' : 'term-row';
            
            return {
                ...term,
                id: term.Id,
                rowClass: termRowClass,
                isSelected: isTermSelected,
                isDisabled: false,
                price: this.formatPrice(displayPrice),
                termDisplayName: term.packageTermName || term.Name || 'Unknown Term'
            };
        });
    }

    // Check if there are available additional options
    get hasAvailableAdditionalOptions() {
        return this.availableAdditionalOptionsData && this.availableAdditionalOptionsData.length > 0;
    }

    // Check if there are existing additional options
    get hasExistingAdditionalOptions() {
        return this.existingAdditionalOptions && this.existingAdditionalOptions.length > 0;
    }

    // Get selected GAP term (alias for selectedWarrantyTerm)
    get selectedGapTerm() {
        return this.selectedWarrantyTerm;
    }

    // Get formatted existing application price for display
    get formattedExistingPrice() {
        if (this.isExistingApplication && this.existingApplicationPackage) {
            // Use the SOLD pricing (what customer actually paid)
            const basePrice = this.existingApplicationPackage.dealerPackagePrice || 0;
            const markup = this.existingApplicationPackage.dealerMarkup || 0;
            const totalPrice = basePrice + markup;
            return this.formatPrice(totalPrice);
        }
        return '0.00';
    }
    
    // Load additional options for the selected package
    async loadAdditionalOptionsByPackage(packageId) {
        try {
            console.log('🔍 GAP - Loading additional options for package:', packageId);
            
            const result = await getTotalLossAdditionalOptionsByPackage({ dealerPackageId: packageId });
            console.log('🔍 GAP - Package-level Apex result:', result);
            
            if (result.success) {
                console.log('🔍 GAP - Raw package-level data from Apex:', result.data);
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
                    exclusion: option.exclusion,
                    category: option.category,
                    minimumValue: option.minimumValue || 0,
                    maximumValue: option.maximumValue || 0
                }));
                
                console.log('✅ GAP - Loaded', this.availableAdditionalOptionsData.length, 'package-level additional options');
                console.log('🔍 GAP - Mapped package-level options:', this.availableAdditionalOptionsData);
                
                // Process options by category
                this.processAdditionalOptionsByCategory();
                console.log('🔍 GAP - existingAdditionalOptions length:', this.existingAdditionalOptions.length);
                console.log('🔍 GAP - hasAvailableAdditionalOptions will be:', this.availableAdditionalOptionsDisplay?.length > 0);
            } else {
                console.error('❌ GAP - Failed to load package-level additional options:', result.message);
                this.availableAdditionalOptionsData = [];
            }
        } catch (error) {
            console.error('❌ GAP - Error loading package-level additional options:', error);
            this.availableAdditionalOptionsData = [];
        }
    }

    // Load additional options for the selected term
    async loadAdditionalOptions(termId) {
        try {
            console.log('🔍 GAP - Loading additional options for term:', termId);
            
            const result = await getTotalLossAdditionalOptions({ dealerPackageTermId: termId });
            console.log('🔍 GAP - Apex result:', result);
            
            if (result.success) {
                console.log('🔍 GAP - Raw data from Apex:', result.data);
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
                    exclusion: option.exclusion,
                    category: option.category,
                    minimumValue: option.minimumValue || 0,
                    maximumValue: option.maximumValue || 0
                }));
                
                console.log('✅ GAP - Loaded', this.availableAdditionalOptionsData.length, 'additional options');
                console.log('🔍 GAP - Mapped options:', this.availableAdditionalOptionsData);
                
                // Process options by category
                this.processAdditionalOptionsByCategory();
            } else {
                console.error('❌ GAP - Failed to load additional options:', result.message);
                this.availableAdditionalOptionsData = [];
            }
        } catch (error) {
            console.error('❌ GAP - Error loading additional options:', error);
            this.availableAdditionalOptionsData = [];
        }
    }
    
    // Load existing additional options for an application package
    async loadExistingAdditionalOptions(applicationPackageId) {
        try {
            console.log('🔍 Loading existing additional options for application package:', applicationPackageId);
            
            const result = await getTotalLossExistingAdditionalOptions({ applicationPackageId: applicationPackageId });
            
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
                    category: option.category,
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
        
        // Update the isSelected property in the option objects to reflect the change immediately
        // Update in commercialOptions
        const commercialOption = this.commercialOptions.find(opt => opt.id === optionId);
        if (commercialOption) {
            commercialOption.isSelected = isChecked;
        }
        
        // Update in downPaymentOptions
        const downPaymentOption = this.downPaymentOptions.find(opt => opt.id === optionId);
        if (downPaymentOption) {
            downPaymentOption.isSelected = isChecked;
        }
        
        // Update in filteredDownPaymentOptions
        const filteredOption = this.filteredDownPaymentOptions.find(opt => opt.id === optionId);
        if (filteredOption) {
            filteredOption.isSelected = isChecked;
        }
        
        // Update in availableAdditionalOptionsData
        const optionInData = this.availableAdditionalOptionsData.find(opt => opt.id === optionId);
        if (optionInData) {
            optionInData.isSelected = isChecked;
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
            
            // Convert to plain arrays and ensure all values are strings
            const optionsToAddArray = Array.from(this.selectedNewOptions || [])
                .filter(id => id != null && id !== undefined && id !== '')
                .map(String);
            const optionsToRemoveArray = Array.from(this.optionsToRemove || [])
                .filter(id => id != null && id !== undefined && id !== '')
                .map(String);
            
            console.log('🔍 Converted arrays:');
            console.log('🔍 optionsToAddArray:', optionsToAddArray);
            console.log('🔍 optionsToAddArray types:', optionsToAddArray.map(id => typeof id));
            console.log('🔍 optionsToRemoveArray:', optionsToRemoveArray);
            console.log('🔍 optionsToRemoveArray types:', optionsToRemoveArray.map(id => typeof id));
            
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
            
            const result = await updateTotalLossAdditionalOptions({ optionsData: optionsData });
            
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
        const displayOptions = this.existingAdditionalOptions.map(option => {
            const isMarkedForRemoval = option.isMarkedForRemoval || false;
            const displayOption = {
                ...option,
                cssClass: isMarkedForRemoval ? 'existing-option-card option-removing' : 'existing-option-card option-active',
                buttonLabel: isMarkedForRemoval ? 'Undo Remove' : 'Remove',
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
        // Start with available options from the package (Dealer_Package_Option__c)
        let availableOptions = [...(this.availableAdditionalOptionsData || [])];
        
        console.log('🔍 GAP - availableAdditionalOptionsDisplay - Raw available options:', availableOptions.length);
        console.log('🔍 GAP - availableAdditionalOptionsDisplay - existingAdditionalOptions:', this.existingAdditionalOptions.length);
        
        // Get IDs of already selected options (Application_Package_Option__c)
        const selectedOptionIds = this.existingAdditionalOptions
            .filter(option => !this.optionsToRemove.includes(option.id))
            .map(option => option.id);
        
        console.log('🔍 GAP - availableAdditionalOptionsDisplay - selectedOptionIds:', selectedOptionIds);
        
        // Filter out already selected options
        const filteredOptions = availableOptions.filter(option => {
            return !selectedOptionIds.includes(option.id);
        });
        
        console.log('🔍 GAP - availableAdditionalOptionsDisplay - filteredOptions:', filteredOptions.length);
        
        // Add back options that are marked for removal (they become available again)
        const removedOptionIds = this.optionsToRemove || [];
        if (removedOptionIds.length > 0) {
            const removedOptions = this.existingAdditionalOptions
                .filter(option => removedOptionIds.includes(option.id))
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
        console.log('🔍 GAP - hasAvailableAdditionalOptions:', hasOptions, 'Count:', this.availableAdditionalOptionsDisplay?.length || 0);
        console.log('🔍 GAP - selectedDealerPackage:', this.selectedDealerPackage?.Id);
        console.log('🔍 GAP - selectedWarrantyTerm:', this.selectedWarrantyTerm?.Id);
        console.log('🔍 GAP - availableAdditionalOptionsData length:', this.availableAdditionalOptionsData?.length || 0);
        return hasOptions;
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

        // Category breakdown for existing options
        const existingCommercialPrice = this.existingAdditionalOptions
            .filter(option => !this.optionsToRemove.includes(option.id))
            .filter(option => option.category === 'Commercial/Business Premium Use')
            .reduce((total, option) => total + (option.retailPrice || 0), 0);
        const existingDownPaymentPrice = this.existingAdditionalOptions
            .filter(option => !this.optionsToRemove.includes(option.id))
            .filter(option => option.category === 'Down Payment Protection')
            .reduce((total, option) => total + (option.retailPrice || 0), 0);

        // Category breakdown for new options (look up category from availableAdditionalOptionsData)
        const newCommercialPrice = this.selectedNewOptions.reduce((total, optionId) => {
            const option = this.availableAdditionalOptionsData.find(opt => opt.id === optionId);
            if (option && option.category === 'Commercial/Business Premium Use') {
                return total + (option.retailPrice || option.netCost || 0);
            }
            return total;
        }, 0);
        const newDownPaymentPrice = this.selectedNewOptions.reduce((total, optionId) => {
            const option = this.availableAdditionalOptionsData.find(opt => opt.id === optionId);
            if (option && option.category === 'Down Payment Protection') {
                return total + (option.retailPrice || option.netCost || 0);
            }
            return total;
        }, 0);

        // Counts for each category
        const existingCommercialCount = this.existingAdditionalOptions
            .filter(option => !this.optionsToRemove.includes(option.id))
            .filter(option => option.category === 'Commercial/Business Premium Use').length;
        const existingDownPaymentCount = this.existingAdditionalOptions
            .filter(option => !this.optionsToRemove.includes(option.id))
            .filter(option => option.category === 'Down Payment Protection').length;
        const newCommercialCount = this.selectedNewOptions.reduce((count, optionId) => {
            const option = this.availableAdditionalOptionsData.find(opt => opt.id === optionId);
            return count + (option && option.category === 'Commercial/Business Premium Use' ? 1 : 0);
        }, 0);
        const newDownPaymentCount = this.selectedNewOptions.reduce((count, optionId) => {
            const option = this.availableAdditionalOptionsData.find(opt => opt.id === optionId);
            return count + (option && option.category === 'Down Payment Protection' ? 1 : 0);
        }, 0);

        return {
            existingOptionsPrice,
            newOptionsPrice,
            totalAdditionalOptionsPrice: existingOptionsPrice + newOptionsPrice,
            formattedExistingOptionsPrice: this.formatPrice(existingOptionsPrice),
            formattedNewOptionsPrice: this.formatPrice(newOptionsPrice),
            formattedTotalAdditionalOptionsPrice: this.formatPrice(existingOptionsPrice + newOptionsPrice),
            // Category breakdowns
            existingCommercialPrice,
            existingDownPaymentPrice,
            newCommercialPrice,
            newDownPaymentPrice,
            formattedExistingCommercialPrice: this.formatPrice(existingCommercialPrice),
            formattedExistingDownPaymentPrice: this.formatPrice(existingDownPaymentPrice),
            formattedNewCommercialPrice: this.formatPrice(newCommercialPrice),
            formattedNewDownPaymentPrice: this.formatPrice(newDownPaymentPrice),
            // Counts
            existingCommercialCount,
            existingDownPaymentCount,
            newCommercialCount,
            newDownPaymentCount
        };
    }

    // Initialize original gap data for change tracking
    initializeOriginalGapData() {
        this.originalGapData = {
            selectedDealerPackageId: this.selectedDealerPackage?.Id || null,
            selectedWarrantyTermId: this.selectedWarrantyTerm?.Id || null,
            selectedAdditionalOptions: [...(this.selectedNewOptions || [])],
            existingAdditionalOptions: [...(this.existingAdditionalOptions || [])]
        };
        this.gapChangedFields.clear();
        console.log('🔄 Original gap data initialized for change tracking');
    }
    
    // Track gap field changes
    trackGapChange(changeType, oldValue, newValue) {
        console.log('🔍 Tracking gap change:', {
            changeType,
            oldValue,
            newValue,
            hasChanged: oldValue !== newValue
        });
        
        if (oldValue !== newValue) {
            this.gapChangedFields.add(changeType);
            console.log('📝 Gap change marked:', changeType);
        } else {
            this.gapChangedFields.delete(changeType);
            console.log('↩️ Gap change reverted:', changeType);
        }
        
        console.log('📋 Total gap changes:', Array.from(this.gapChangedFields));
        
        // AUTO-SAVE DISABLED - User must click Continue to save
        /* OLD AUTO-SAVE CODE (disabled)
        if (this.isExistingApplication && this.existingApplicationPackage) {
            this.debouncedGapAutoSave();
        }
        */
        console.log('ℹ️ [GAP] Auto-save disabled - changes will save on Continue click');
    }
    
    // Debounced auto-save for gap changes
    debouncedGapAutoSave() {
        // Clear existing timeout
        if (this.gapAutoSaveTimeout) {
            clearTimeout(this.gapAutoSaveTimeout);
        }
        
        // Set new timeout for auto-save (2 seconds after last change)
        this.gapAutoSaveTimeout = setTimeout(() => {
            this.autoSaveGapChanges();
        }, 2000);
        
        console.log('⏱️ Gap auto-save scheduled in 2 seconds...');
    }
    
    // Auto-save only changed gap fields
    async autoSaveGapChanges() {
        if (this.gapChangedFields.size === 0) {
            console.log('ℹ️ No gap changes to auto-save');
            return;
        }
        
        if (!this.isExistingApplication || !this.existingApplicationPackage) {
            console.log('ℹ️ Skipping gap auto-save for new application');
            return;
        }
        
        try {
            console.log('💾 Auto-saving gap changes:', Array.from(this.gapChangedFields));
            
            // Prepare selective update data
            const updateData = {
                applicationPackageId: this.existingApplicationPackage.Id,
                applicationId: this.applicationId
            };
            
            // Add changed fields
            if (this.gapChangedFields.has('package')) {
                updateData.dealerPackageId = this.selectedDealerPackage?.Id;
            }
            
            if (this.gapChangedFields.has('term')) {
                updateData.dealerPackageTermId = this.selectedWarrantyTerm?.Id;
            }
            
            // Call selective update method (to be implemented)
            const result = await updateTotalLossFieldsSelective({ updateData: updateData });
            
            if (result.success) {
                console.log('✅ Gap auto-save successful');
                
                // Update original data and clear changed fields
                this.initializeOriginalGapData();
                
                // Show subtle success indicator
                this.showGapAutoSaveSuccess();
            } else {
                console.error('❌ Gap auto-save failed:', result.message);
            }
        } catch (error) {
            console.error('❌ Gap auto-save error:', error);
        }
    }
    
    // Show gap auto-save success indicator
    showGapAutoSaveSuccess() {
        console.log('✅ Gap auto-save success indicator shown');
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
        console.log('🔄 Previous selections:', this.selectedNewOptions.length);
        
        // Clear new selections (these haven't been saved yet)
        this.selectedNewOptions = [];
        
        console.log('🔄 New selections cleared for term switch');
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
    
    // Generic toast helper method
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant, // 'success', 'error', 'warning', 'info'
            mode: 'dismissable'
        });
        this.dispatchEvent(event);
    }
    
    // GAP Input Fields Event Handlers
    handleLenderLienholderChange(event) {
        this.lenderLienholder = event.target.value;
        this.saveGapInputData();
    }
    
    handleFinanceLoanTermChange(event) {
        // Support both input and combobox
        this.financeLoanTerm = (event.detail && event.detail.value) ? event.detail.value : event.target.value;
        this.saveGapInputData();
    }
    
    handleLoanAmountChange(event) {
        this.loanAmount = event.target.value;
        this.saveGapInputData();
    }
    
    handleInterestRateChange(event) {
        this.interestRate = event.target.value;
        this.saveGapInputData();
    }
    
    handleFindPackages() {
        console.log('🔍 Finding packages with GAP input data:', {
            lenderLienholder: this.lenderLienholder,
            financeLoanTerm: this.financeLoanTerm,
            loanAmount: this.loanAmount,
            interestRate: this.interestRate,
            paymentFrequency: this.paymentFrequency,
            cashDown: this.cashDown,
            vehicleTradeInEquity: this.vehicleTradeInEquity
        });
        
        // Validate all required fields
        const missingFields = [];
        
        if (!this.lenderLienholder || this.lenderLienholder.trim() === '') {
            missingFields.push('Lien Holder / Financial Institution');
        }
        
        if (!this.financeLoanTerm || this.financeLoanTerm === '') {
            missingFields.push('Financed Loan Term (Months)');
        }
        
        if (!this.loanAmount || this.loanAmount === '') {
            missingFields.push('Total Amount Financed');
        }
        
        if (!this.interestRate || this.interestRate === '') {
            missingFields.push('Interest Rate (APR %)');
        }
        
        // If any fields are missing, show error toast and return
        if (missingFields.length > 0) {
            this.showToast(
                'Required Fields Missing',
                `Please fill in all required fields: ${missingFields.join(', ')}`,
                'error'
            );
            return;
        }
        
        // Additional validation for numeric fields
        const loanTermNum = parseInt(this.financeLoanTerm);
        const loanAmountNum = parseFloat(this.loanAmount);
        const interestRateNum = parseFloat(this.interestRate);
        
        if (isNaN(loanTermNum) || loanTermNum <= 0 || loanTermNum > 120) {
            this.showToast(
                'Invalid Finance Loan Term',
                'Finance Loan Term must be a valid number between 1 and 120 months',
                'error'
            );
            return;
        }
        
        if (isNaN(loanAmountNum) || loanAmountNum <= 0) {
            this.showToast(
                'Invalid Loan Amount',
                'Loan Amount must be a valid positive number',
                'error'
            );
            return;
        }
        
        if (isNaN(interestRateNum) || interestRateNum < 0 || interestRateNum > 50) {
            this.showToast(
                'Invalid Interest Rate',
                'Interest Rate must be a valid number between 0 and 50',
                'error'
            );
            return;
        }
        
        // Set loading state
        this.isLoadingPackages = true;
        this.packageSearchPerformed = true;
        this.forceShowInputFields = false; // Return to normal flow after user submits filters
        
        // Save the input data first
        this.saveGapInputData();
        
        // Show package selection and load packages
        this.showPackageSelection = true;
        console.log('🔍 showPackageSelection set to:', this.showPackageSelection);
        console.log('🔍 isExistingApplication:', this.isExistingApplication);
        
        this.loadDealerPackages();
        
        console.log('🔍 After loadDealerPackages - showPackageSelection:', this.showPackageSelection);
    }
    
    // Handle Change Filters button click
    handleChangeFilters() {
        console.log('🔍 Change Filters clicked - returning to input fields');
        
        // Hide package selection to show input fields again
        this.showPackageSelection = false;
        this.forceShowInputFields = true;
        
        // Clear selected packages and terms
        this.selectedDealerPackage = null;
        this.selectedWarrantyTerm = null;
        this.dealerPackages = [];
        this.totalTermCount = 0;
        this.packageSearchPerformed = false;
        this.dealerHasGapPackages = false;

        // Keep input field values so user can modify them
        // Don't clear: lenderLienholder, financeLoanTerm, loanAmount, interestRate
        
        console.log('🔍 Returned to input fields - showPackageSelection:', this.showPackageSelection);
    }
    
    // Handle Back to Package Selection button click
    handleBackToPackageSelection() {
        console.log('🔍 Back to Package Selection clicked - returning to package view');
        
        // Show package selection and hide input fields
        this.showPackageSelection = true;
        this.forceShowInputFields = false;
        
        // Reload packages with current filter values
        this.loadDealerPackages();
        
        console.log('🔍 Returned to package selection - showPackageSelection:', this.showPackageSelection);
    }
    
    saveGapInputData() {
        const gapInputData = {
            lenderLienholder: this.lenderLienholder,
            financeLoanTerm: this.financeLoanTerm,
            loanAmount: this.loanAmount,
            interestRate: this.interestRate
        };
        sessionStorage.setItem('gapInputData', JSON.stringify(gapInputData));
    }
    
    loadGapInputData() {
        console.log('🔍 GAP - loadGapInputData called');
        
        // Only clear fields if we don't have an existing application
        // This prevents overriding the existing package check and filter hydration
        if (!this.isExistingApplication) {
            this.lenderLienholder = '';
            this.financeLoanTerm = '';
            this.loanAmount = '';
            this.interestRate = '';
            this.vehicleTradeInEquity = '';
            this.cashDown = '';
            this.paymentFrequency = '';
            this.showPackageSelection = false;

            // Clear any saved input data from session storage
            sessionStorage.removeItem('gapInputData');

            console.log('🔍 GAP - Cleared input fields for new application');
        } else {
            console.log('🔍 GAP - Preserving existing application filter values');
        }
        
        console.log('🔍 GAP - loadGapInputData complete, showPackageSelection:', this.showPackageSelection, 'isExistingApplication:', this.isExistingApplication);
    }
    
    clearGapInputData() {
        this.lenderLienholder = '';
        this.financeLoanTerm = '';
        this.loanAmount = '';
        this.interestRate = '';
        this.showPackageSelection = false;
        this.cashDown = '';
        this.vehicleTradeInEquity = '';
        this.commercialOptions = [];
        this.downPaymentOptions = [];
        this.filteredDownPaymentOptions = [];
        this.isLoadingPackages = false;
        this.isLoadingOptions = false;
        sessionStorage.removeItem('gapInputData');
        console.log('🧹 GAP input data cleared for fresh start');
    }
    
    // Down Payment Protection input handlers
    handleCashDownChange(event) {
        this.cashDown = event.target.value;
        console.log('🔍 Cash Down changed to:', this.cashDown);
        this.saveGapInputData();
    }
    
    handleVehicleTradeInEquityChange(event) {
        this.vehicleTradeInEquity = event.target.value;
        console.log('🔍 Vehicle Trade In Equity changed to:', this.vehicleTradeInEquity);
        this.saveGapInputData();
    }
    
    // Filter Down Payment Protection options based on input values
    handleFindDownPaymentOptions() {
        console.log('🔍 Finding Down Payment Protection options...');
        console.log('🔍 Cash Down:', this.cashDown);
        console.log('🔍 Vehicle Trade In Equity:', this.vehicleTradeInEquity);
        
        // Show loading spinner
        this.isLoadingOptions = true;
        
        // Simulate a small delay to show the spinner (optional)
        setTimeout(() => {
            const cashDownValue = parseFloat(this.cashDown) || 0;
            const tradeInValue = parseFloat(this.vehicleTradeInEquity) || 0;
            const totalDownPayment = cashDownValue + tradeInValue;
            
            console.log('🔍 Total Down Payment:', totalDownPayment);
            
            this.filteredDownPaymentOptions = this.downPaymentOptions.filter(option => {
                const minValue = option.minimumValue || 0;
                const maxValue = option.maximumValue || 0;
                
                console.log('🔍 Option:', option.optionName, 'Min:', minValue, 'Max:', maxValue);
                
                // If no range is set, include the option
                if (minValue === 0 && maxValue === 0) {
                    return true;
                }
                
                // Check if total down payment falls within the range
                const isInRange = totalDownPayment >= minValue && totalDownPayment <= maxValue;
                console.log('🔍 Option', option.optionName, 'is in range:', isInRange);
                
                return isInRange;
            });
            
            console.log('🔍 Filtered Down Payment options:', this.filteredDownPaymentOptions.length);
            
            // Hide loading spinner
            this.isLoadingOptions = false;
        }, 500); // 500ms delay to show spinner
    }

    // Finance Loan Term dropdown options
    get financeLoanTermOptions() {
        return [
            { label: '--None--', value: '' },
            { label: '24', value: '24' },
            { label: '36', value: '36' },
            { label: '48', value: '48' },
            { label: '60', value: '60' },
            { label: '72', value: '72' },
            { label: '78', value: '78' },
            { label: '84', value: '84' },
            { label: '90', value: '90' },
            { label: '96', value: '96' }
        ];
    }

    get financeLoanTermSelectOptions() {
        return this.financeLoanTermOptions
            .filter(option => option.value !== '')
            .map(option => ({
                ...option,
                selected: option.value === this.financeLoanTerm
            }));
    }

    // Payment Frequency dropdown options
    get paymentFrequencyOptions() {
        return [
            { label: '--None--', value: '' },
            { label: 'Monthly', value: 'Monthly' },
            { label: 'Bi-Weekly', value: 'Bi-Weekly' }
        ];
    }

    get paymentFrequencySelectOptions() {
        return this.paymentFrequencyOptions
            .filter(option => option.value !== '')
            .map(option => ({
                ...option,
                selected: option.value === this.paymentFrequency
            }));
    }

    handlePaymentFrequencyChange(event) {
        this.paymentFrequency = (event.detail && event.detail.value) ? event.detail.value : event.target.value;
        console.log('🔍 Payment Frequency changed to:', this.paymentFrequency);
        // Persist in session
        this.saveDataToSession();
        this.saveGapInputData();
    }
    
    // Process additional options by category when they are loaded
    processAdditionalOptionsByCategory() {
        console.log('🔍 Processing additional options by category...');
        console.log('🔍 Available options:', this.availableAdditionalOptionsData);
        
        this.commercialOptions = [];
        this.downPaymentOptions = [];
        this.filteredDownPaymentOptions = [];
        
        if (this.availableAdditionalOptionsData && this.availableAdditionalOptionsData.length > 0) {
            this.availableAdditionalOptionsData.forEach(option => {
                console.log('🔍 Processing option:', option.optionName, 'Category:', option.category);
                
                // Set isSelected based on selectedNewOptions array
                const optionWithSelection = {
                    ...option,
                    isSelected: this.selectedNewOptions.includes(option.id)
                };
                
                if (option.category === 'Commercial/Business Premium Use') {
                    this.commercialOptions.push(optionWithSelection);
                } else if (option.category === 'Down Payment Protection') {
                    this.downPaymentOptions.push(optionWithSelection);
                }
            });
        }
        
        console.log('🔍 Commercial options:', this.commercialOptions.length);
        console.log('🔍 Down Payment options:', this.downPaymentOptions.length);
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
                        message: result.message,
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
                        message: result.message,
                        variant: 'error'
                    })
                );
            }
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Failed to convert quote to application: ' + error.message,
                    variant: 'error'
                })
            );
            console.error('❌ Error converting to application:', error);
        }
    }

}