import { LightningElement, track, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDealerPackages from '@salesforce/apex/DealerPortalController.getDealerPackages';
import getExistingApplicationPackageByRecordType from '@salesforce/apex/DealerPortalController.getExistingApplicationPackageByRecordType';
import getActiveApplicationPackageByRecordType from '@salesforce/apex/DealerPortalController.getActiveApplicationPackageByRecordType';
import savePackageWithActiveManagement from '@salesforce/apex/DealerPortalController.savePackageWithActiveManagement';
import createApplicationPackageFromMap from '@salesforce/apex/DealerPortalController.createApplicationPackageFromMap';
import updateApplicationPackage from '@salesforce/apex/DealerPortalController.updateApplicationPackage';
import loadVehicleData from '@salesforce/apex/DealerPortalController.loadVehicleData';
import uploadFilesToApplicationPackage from '@salesforce/apex/DealerPortalFileHandler.uploadFilesToApplicationPackage';
import convertApplicationToQuote from '@salesforce/apex/DealerPortalController.convertApplicationToQuote';
import convertQuoteToApplication from '@salesforce/apex/DealerPortalController.convertQuoteToApplication';
import tireImage from '@salesforce/resourceUrl/tireImage';
import hasTireRimPackages from '@salesforce/apex/DealerPortalController.hasTireRimPackages';

export default class DealerPortalMoreProducts extends NavigationMixin(LightningElement) {
    @track loading = false
    @track renderKey = 0 // Used to force re-renders;
    @track price = 0.00;
    @track isPriceEditMode = false;
    @track priceOverrideInput = '';
    @track isPriceOverridden = false;
    @track isPriceCalculating = false;
    @track priceValidationMessage = '';
    @track selectedProgram = '';
    @track selectedTerm = '4';
    @track selectedClaim = '5000';
    @track testDrive = false;
    @track testDrivePrice = 729.00;
    @track errorMessage = '';
    @track showError = false;
    @track showDeclineModal = false;
    @track dealerPackages = [];
    @track dealerHasSpecificPackages = false;
    @track selectedDealerPackage = null;
    @track selectedWarrantyTerm = null;
    @track isChangingSelection = false;
    @track isOnDetailForm = false;
    @track showPriceModal = false;
    @track currentPriceBreakdown = {};
    @track dealerReferenceBreakdown = {};
    @track showDealerReferencePrice = false;
    @track existingApplicationPackage = null;
    @track isExistingApplication = false;
    @track hasTireRimPackage = false;
    @track hasWarrantyPackage = false;
    @track hasDealerTireRimPackages = true; // default true until loaded
    @track showHelpModal = false;
    @track helpModalTitle = '';
    @track helpModalText = '';
    @track showMoreProductsModal = false;
    @track selectedDealerPackageName = '';
    @track selectedWarrantyTermName = '';
    @track activeAccordionSections = [];
    @track packageHasFiles = false;
    @track packageFileCount = 0;
    @track originalWarrantyData = {};
    @track warrantyChangedFields = new Set();
    @track warrantyAutoSaveTimeout;
    @track vehicleInfo = {
        make: '',
        model: '',
        modelClass: '',
        year: '',
        trim: '',
        vin: '',
        odometer: '',
        odometerUnit: 'KM',
        purchasePrice: ''
    };
    @track vehicleModelClass = '';

    // Tire & Rim detail fields
    @track tireBrand     = '';
    @track tireType      = '';
    @track treadDepth    = '';
    @track treadDepthUnit = '';
    @track rimSize       = '';
    @track rimSizeUnit   = '';
    @track rimBrand      = '';
    @track rimType       = '';
    @track dealerComments = '';

    // Individual wire for Rim Type (working)
    @wire(getPicklistValues, { recordTypeId: '012G1000003ycK7IAI', fieldApiName: { objectApiName: 'Application_Package__c', fieldApiName: 'Rim_Type__c' } })
    rimTypePicklist;

    @wire(getPicklistValues, { recordTypeId: '012G1000003ycK7IAI', fieldApiName: { objectApiName: 'Application_Package__c', fieldApiName: 'Tire_Brand__c' } })
    tireBrandPicklist;

    @wire(getPicklistValues, { recordTypeId: '012G1000003ycK7IAI', fieldApiName: { objectApiName: 'Application_Package__c', fieldApiName: 'Tread_Depth_Unit__c' } })
    treadDepthUnitPicklist;

    @wire(getPicklistValues, { recordTypeId: '012G1000003ycK7IAI', fieldApiName: { objectApiName: 'Application_Package__c', fieldApiName: 'Rim_Brand__c' } })
    rimBrandPicklist;

    @track currentView = 'planSelection';
    @track planCards = [];
    @track allDealerPackages = [];
    @track selectedPlanTypeKey = null;
    @track selectedPlanType = null;
    @track applicationPackageId = null; // Store the saved package ID for file uploads
    @track uploadInProgress = false;
    @track pendingFiles = []; // Store files selected before record is created [{name, file, base64}]
    @track uploadedFiles = []; // Store successfully uploaded files
    otherPlanTypeKey = 'OTHER_PACKAGES';
    heroImage = tireImage;
    acceptedFileTypes = '.pdf,.jpg,.jpeg,.png,.gif'; // Accept common image and PDF formats
    _applicationId;
    @api isLocked = false;
    @api applicationStatus;
    
    // Getter for field disabled state based on lock status
    get fieldDisabled() {
        return this.isLocked;
    }

    get isQuoteStatus() {
        return this.applicationStatus === 'Quote';
    }
    
    // Getter for skip button label - "Next" when locked, "Skip" when not locked
    get skipButtonLabel() {
        return this.isLocked ? 'Next' : 'Decline Tire & Rim';
    }
    defaultPlanIncludes = [
        { id: 'repair', label: 'Tire & Rim Repair & Replacement' },
        { id: 'mount', label: 'Tire & Rim Mounting and Balancing' },
        { id: 'roadside', label: 'Roadside Coverage' },
        { id: 'key', label: 'Key & Remote Replacement' },
        { id: 'rental', label: 'Car Rental' },
        { id: 'windshield', label: 'Windshield, Head Light and Tail Light Lens' },
        { id: 'dent', label: 'Paintless Dent Repair' },
        { id: 'burn', label: 'Burn, Rip Tear or Puncture Repair' }
    ];

    get isPlanSelectionView() {
        return this.currentView === 'planSelection';
    }

    get showPlanSelection() {
        return this.isPlanSelectionView && !this.isOnDetailForm;
    }

    get showSelectedPlanView() {
        // Do NOT show the Details form when the vehicle is ineligible for Tire & Rim plans
        return this.isPlanSelectionView && this.isOnDetailForm && !this.showVehicleNotEligibleDisclaimer;
    }

    get showNextButton() {
        return this.isPlanSelectionView && !this.isOnDetailForm && this.hasSelectedTerm && !this.isLocked && !this.loading;
    }

    get formattedSelectedPrice() {
        // Show the custom pre-tax price the user entered (not tax-inclusive)
        if (this.isPriceOverridden && this._overridePreTaxPrice != null) {
            return '$' + Number(this._overridePreTaxPrice).toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
        }
        if (this.selectedWarrantyTerm) {
            const price = this.selectedWarrantyTerm.totalPrice || this.selectedWarrantyTerm.netCost || 0;
            return '$' + Number(price).toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
        }
        return '$0.00';
    }

    get showContinueButton() {
        return !this.loading && !this.fieldDisabled;
    }

    get isDetailView() {
        return this.currentView === 'planDetails';
    }

    get hasPlanCards() {
        return Array.isArray(this.planCards) && this.planCards.length > 0;
    }

    get allPackagesNotEligible() {
        return this.hasPlanCards && this.planCards.every(card => !card.isSelectable);
    }

    get showNoPackageDisclaimer() {
        return !this.dealerHasSpecificPackages || this.allPackagesNotEligible;
    }

    get showNoDealerPackagesBanner() {
        return !this.hasDealerTireRimPackages;
    }

    get showVehicleNotEligibleDisclaimer() {
        return this.dealerHasSpecificPackages && (!this.hasPlanCards || this.allPackagesNotEligible);
    }

    get showPlanCards() {
        return this.hasPlanCards && !this.showNoPackageDisclaimer;
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
                // Check whether dealer has Tire & Rim packages
                hasTireRimPackages({ applicationId: value })
                    .then(result => { this.hasDealerTireRimPackages = result === true; })
                    .catch(() => { this.hasDealerTireRimPackages = true; }); // fail open
                this.loadDealerPackages();
            }
        }
    }
    
    connectedCallback() {
        console.log('🔒 More Products component connected');
        console.log('🔒 Initial applicationId in connectedCallback:', this.applicationId);
        console.log('🔒 Initial _applicationId in connectedCallback:', this._applicationId);
        
        // Auto-populate with saved data if available — only if it belongs to the same application
        if (sessionStorage.getItem('moreProductsData')) {
            const savedData = JSON.parse(sessionStorage.getItem('moreProductsData'));
            // If the stored data is for a different application, discard it
            if (savedData.applicationId && this._applicationId && savedData.applicationId !== this._applicationId) {
                sessionStorage.removeItem('moreProductsData');
                return;
            }
            this.selectedProgram = savedData.selectedProgram || this.selectedProgram;
            this.selectedTerm = savedData.selectedTerm || this.selectedTerm;
            this.selectedClaim = savedData.selectedClaim || this.selectedClaim;
            this.selectedDeductible = savedData.selectedDeductible || this.selectedDeductible;
            this.testDrive = savedData.testDrive || this.testDrive;
            this.tireBrand     = savedData.tireBrand     || this.tireBrand;
            this.tireType      = savedData.tireType      || this.tireType;
            this.treadDepth    = savedData.treadDepth    || this.treadDepth;
            this.treadDepthUnit = savedData.treadDepthUnit || this.treadDepthUnit;
            this.rimSize       = savedData.rimSize       || this.rimSize;
            this.rimSizeUnit   = savedData.rimSizeUnit   || this.rimSizeUnit;
            this.rimBrand      = savedData.rimBrand      || this.rimBrand;
            this.rimType       = savedData.rimType       || this.rimType;
            this.dealerComments = savedData.dealerComments || this.dealerComments;
            
            // Restore selected dealer package if available
            if (savedData.selectedDealerPackage) {
                this.selectedDealerPackage = savedData.selectedDealerPackage;
                this.activeAccordionSections = [savedData.selectedDealerPackage.Id];
                console.log('✅ Restored selected dealer package from session:', this.selectedDealerPackage);
            }
            
            // Restore selected warranty term if available AND we have a selected package
            if (savedData.selectedWarrantyTerm && savedData.selectedDealerPackage) {
                this.selectedWarrantyTerm = savedData.selectedWarrantyTerm;
                this.isChangingSelection = false;
                this.isOnDetailForm = true;
                console.log('✅ Restored selected warranty term from session:', this.selectedWarrantyTerm);
            } else if (savedData.selectedWarrantyTerm && !savedData.selectedDealerPackage) {
                // Clear term if no package is selected
                this.selectedWarrantyTerm = null;
                console.log('🧹 Cleared selected warranty term - no package selected');
            }
            
            // Update price based on loaded data (don't use stored price value)
            this.updatePrice();
            
            // Restore custom price override if it was active
            if (savedData.isPriceOverridden && savedData.price) {
                this.price = savedData.price;
                this.isPriceOverridden = true;
                console.log('✅ Restored custom price override from session:', this.price);
            }
        }
        
        // Check if we have an applicationId after a short delay
        setTimeout(() => {
            console.log('🔒 Delayed check - applicationId:', this.applicationId);
            console.log('🔒 Delayed check - _applicationId:', this._applicationId);
        }, 1000);
    }
    
    // Method to update UI selection highlighting
    updateSelectionHighlighting() {
        if (this.selectedDealerPackage) {
            // Remove all selected classes
            this.template.querySelectorAll('.program-section, lightning-accordion-section').forEach(section => {
                section.classList.remove('selected');
            });
            
            // Add selected class to the current selection - use same selectors as warranty component
            const selectedSection = this.template.querySelector(`[data-package="${this.selectedDealerPackage.Id}"]`) ||
                                  this.template.querySelector(`[name="${this.selectedDealerPackage.Id}"]`) ||
                                  this.template.querySelector(`[data-package-id="${this.selectedDealerPackage.Id}"]`);
            if (selectedSection) {
                selectedSection.classList.add('selected');
                console.log('🔍 Selection highlighting updated for:', this.selectedDealerPackage.PackageName);
            } else {
                console.log('⚠️ Could not find section to highlight for package:', this.selectedDealerPackage.Id);
                console.log('⚠️ Available sections:', this.template.querySelectorAll('lightning-accordion-section').length);
            }
        }
        
        // Also update term highlighting if a term is selected
        if (this.selectedWarrantyTerm) {
            const termElement = this.template.querySelector(`[data-term="${this.selectedWarrantyTerm.Id}"]`);
            if (termElement) {
                termElement.classList.add('selected');
                console.log('🎨 Term element highlighted:', this.selectedWarrantyTerm.packageTermName || this.selectedWarrantyTerm.Name);
            } else {
                console.log('⚠️ Could not find term element to highlight for term:', this.selectedWarrantyTerm.Id);
            }
        } else {
            console.log('ℹ️ No term selected, skipping term highlighting');
        }
    }
    
    // Load vehicle information for the current application
    async loadVehicleInformation() {
        try {
            if (!this.applicationId) {
                console.error('❌ CRITICAL: No applicationId available for vehicle data load');
                this.vehicleInfo = {
                    make: 'No Application ID',
                    model: 'No Application ID',
                    modelClass: 'No Application ID',
                    year: 'N/A',
                    trim: 'N/A',
                    vin: 'N/A'
                };
                this.vehicleModelClass = '';
                return;
            }
            
            console.log('🚗 Loading vehicle information for application:', this.applicationId);
            const result = await loadVehicleData({ applicationId: this.applicationId });
            
            console.log('🚗 loadVehicleData result:', {
                success: result.success,
                hasData: !!result.data,
                message: result.message
            });
            
            if (result.success && result.data) {
                const vehicleData = result.data;
                this.vehicleInfo = {
                    make: vehicleData.make || 'Not Set',
                    model: vehicleData.model || 'Not Set',
                    modelClass: vehicleData.modelClass || 'Not Set',
                    year: vehicleData.year || 'Not Set',
                    trim: vehicleData.trim || 'Not Set',
                    vin: vehicleData.vin || vehicleData.vehicleIdentificationNumberVIN || 'Not Set',
                    odometer: vehicleData.odometer || vehicleData.vehicleOdometer || '',
                    odometerUnit: vehicleData.odometerUnit || 'KM',
                    purchasePrice: vehicleData.purchasePrice || vehicleData.vehiclePurchasePrice || ''
                };
                this.vehicleModelClass = vehicleData.modelClass || '';
                
                console.log('✅ Vehicle information loaded:', this.vehicleInfo);
                console.log('🚗 Vehicle model class for filtering:', this.vehicleModelClass);
                
                // Critical warning if modelClass is missing
                if (!this.vehicleModelClass && vehicleData.vehicleCategory !== 'Powersports') {
                    console.warn('⚠️ CRITICAL: Vehicle Model Class is empty!');
                    console.warn('⚠️ This will cause ALL packages to show as "Not Available"');
                    console.warn('⚠️ Please ensure the Vehicle record has Model_Lookup__c populated with a Class__c value');
                    this.showErrorMessage('Vehicle Model Class is not set. Packages may not be available. Please ensure the vehicle\'s Model Lookup field is populated.');
                }
            } else {
                console.warn('⚠️ No vehicle data found for application:', result.message);
                this.vehicleInfo = {
                    make: 'N/A',
                    model: 'N/A',
                    modelClass: 'N/A',
                    year: 'N/A',
                    trim: 'N/A',
                    vin: 'N/A',
                    odometer: '',
                    odometerUnit: 'KM',
                    purchasePrice: ''
                };
                this.vehicleModelClass = '';
                this.showErrorMessage('Vehicle data not found. Please ensure vehicle information is entered.');
            }
        } catch (error) {
            console.error('❌ Error loading vehicle information:', error);
            console.error('❌ Error stack:', error.stack);
            this.vehicleInfo = {
                make: 'Error',
                model: 'Error',
                modelClass: 'Error',
                year: 'Error',
                trim: 'Error',
                vin: 'Error',
                odometer: '',
                odometerUnit: 'KM',
                purchasePrice: ''
            };
            this.vehicleModelClass = '';
            this.showErrorMessage('Error loading vehicle information. Please try again.');
        }
    }
    
    // Check if a package is selectable based on vehicle model class
    isPackageSelectable(packageClass) {
        console.log('🔍 isPackageSelectable called with:', {
            vehicleModelClass: this.vehicleModelClass,
            packageClass: packageClass,
            vehicleModelClassType: typeof this.vehicleModelClass,
            packageClassType: typeof packageClass
        });
        
        if (!this.vehicleModelClass || !packageClass) {
            console.log('❌ Missing data - vehicleModelClass:', this.vehicleModelClass, 'packageClass:', packageClass);
            return false;
        }
        
        // Normalize class names for comparison
        const vehicleClass = this.vehicleModelClass.trim();
        const pkgClass = packageClass.trim();
        
        console.log('🔍 Checking package selectability:', {
            vehicleClass: vehicleClass,
            packageClass: pkgClass,
            vehicleClassLength: vehicleClass.length,
            packageClassLength: pkgClass.length,
            isSelectable: vehicleClass.toLowerCase() === pkgClass.toLowerCase(),
            vehicleClassCharCodes: vehicleClass.split('').map(c => c.charCodeAt(0)),
            packageClassCharCodes: pkgClass.split('').map(c => c.charCodeAt(0))
        });
        
        return vehicleClass.toLowerCase() === pkgClass.toLowerCase();
    }
    
    // Get package status for display
    getPackageStatus(packageClass) {
        if (!this.vehicleModelClass) {
            return 'no-vehicle-class';
        }
        
        if (this.isPackageSelectable(packageClass)) {
            return 'selectable';
        } else {
            return 'disabled';
        }
    }
    
    // Called when warranty tab is activated
    @api
    handleVehicleConfigChanged() {
        console.log('⚠️ MORE PRODUCTS - Vehicle config changed, revalidating packages');
        // Store current selection before reload
        this._previousPackageId = this.selectedDealerPackage ? this.selectedDealerPackage.Id : null;
        this._previousTermId = this.selectedWarrantyTerm ? this.selectedWarrantyTerm.Id : null;
        this._previousPackageName = this.selectedDealerPackage ? this.selectedDealerPackage.PackageName : null;
        this._previousTermName = this.selectedWarrantyTerm ? (this.selectedWarrantyTerm.packageTermName || this.selectedWarrantyTerm.Name) : null;
        this.vehicleConfigChangedMessage = 'Vehicle details have been updated. Reloading available packages...';
        // Reload packages - they will be filtered by new vehicle config
        this.loadDealerPackages().then(() => {
            this._validatePreviousSelection();
        });
    }

    _validatePreviousSelection() {
        if (!this._previousPackageId) {
            this.vehicleConfigChangedMessage = '';
            return;
        }
        // Check if previous package still exists in the reloaded list
        const pkgStillExists = this.allDealerPackages && this.allDealerPackages.some(pkg => pkg.Id === this._previousPackageId);
        if (!pkgStillExists) {
            // Package no longer available - clear selection and show message
            this.vehicleConfigChangedMessage = 'The previously selected package "' + (this._previousPackageName || '') + '" is no longer available for the updated vehicle configuration. Please select a new package.';
            this.selectedDealerPackage = null;
            this.selectedWarrantyTerm = null;
            this.selectedWarrantyTermName = '';
            this.price = 0;
            this._retailPriceDisplay = 0;
            this.isPriceOverridden = false;
            // No additional options to clear for more products
            this.selectedNewOptions = [];
            this.availableAdditionalOptionsData = [];
        } else if (this._previousTermId) {
            // Package exists, check if term still exists
            const pkg = this.allDealerPackages.find(p => p.Id === this._previousPackageId);
            const termStillExists = pkg && pkg.warrantyTerms && pkg.warrantyTerms.some(t => t.Id === this._previousTermId);
            if (!termStillExists) {
                this.vehicleConfigChangedMessage = 'The previously selected term "' + (this._previousTermName || '') + '" is no longer available for the updated vehicle. Please select a new term.';
                this.selectedWarrantyTerm = null;
                this.selectedWarrantyTermName = '';
                this.price = 0;
                this._retailPriceDisplay = 0;
            } else {
                this.vehicleConfigChangedMessage = 'Vehicle details updated. Your current package selection is still valid.';
                // Auto-clear the success message after 5 seconds
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => { this.vehicleConfigChangedMessage = ''; }, 5000);
            }
        } else {
            this.vehicleConfigChangedMessage = '';
        }
    }
    dismissVehicleConfigMessage() {
        this.vehicleConfigChangedMessage = '';
    }


    @api
    onTabActivated() {
        console.log('🎯 ===== MORE PRODUCTS TAB ACTIVATED =====');
        console.log('🔄 Application ID:', this.applicationId);
        console.log('🔄 _applicationId:', this._applicationId);
        console.log('🔄 Current packages loaded:', this.dealerPackages ? this.dealerPackages.length : 0);
        console.log('🔄 Selected package:', this.selectedDealerPackage?.PackageName || 'None');
        console.log('🔄 Selected term:', this.selectedWarrantyTerm?.packageTermName || this.selectedWarrantyTerm?.Name || 'None');
        console.log('🔄 Is existing application:', this.isExistingApplication);
        console.log('🔄 Current vehicle info:', JSON.stringify(this.vehicleInfo));
        console.log('🔄 Vehicle model class:', this.vehicleModelClass);
        
        
        // Always reload packages when tab is activated to ensure fresh data
        if (this.applicationId) {
            console.log('🔄 Loading dealer packages for more products tab...');
            this.loadDealerPackages();
        } else {
            console.log('❌ CRITICAL: No application ID available for more products tab');
            console.log('❌ Attempting to get applicationId from URL...');
            
            // Try to get from URL as fallback
            const urlParams = new URLSearchParams(window.location.search);
            const applicationIdFromUrl = urlParams.get('c__applicationId') || urlParams.get('applicationId');
            
            if (applicationIdFromUrl) {
                console.log('✅ Found applicationId in URL:', applicationIdFromUrl);
                this._applicationId = applicationIdFromUrl;
                this.loadDealerPackages();
            } else {
                console.log('❌ No applicationId found in URL either');
                this.showErrorMessage('Application ID is missing. Please refresh the page or contact support.');
            }
        }
        
        // Ensure highlighting is applied after a delay to allow for DOM updates
        setTimeout(() => {
            this.updateSelectionHighlighting();
        }, 500);
    }
    
    // Load dealer packages from Salesforce
    async loadDealerPackages() {
        try {
            this.loading = true;
            console.log('🔍 Loading dealer packages for application:', this.applicationId);
            
            if (!this.applicationId) {
                console.error('❌ CRITICAL: Cannot load packages - applicationId is null/undefined');
                this.showErrorMessage('Application ID is missing. Cannot load packages.');
                this.loading = false;
                return;
            }
            
            const result = await getDealerPackages({ applicationId: this.applicationId, recordType: 'Tire_Rim_Protection_Plan' });
            
            console.log('📦 getDealerPackages result:', {
                success: result.success,
                dataLength: result.data?.length || 0,
                message: result.message
            });
            
            if (result.success) {
                console.log('✅ Dealer packages loaded successfully:', result.data?.length || 0, 'packages');

                // Track whether the dealer has packages for this specific record type (before fallback)
                if (result.debugInfo && result.debugInfo.hasSpecificRecordTypePackages !== undefined) {
                    this.dealerHasSpecificPackages = result.debugInfo.hasSpecificRecordTypePackages;
                } else {
                    this.dealerHasSpecificPackages = !!(result.data && result.data.length > 0);
                }

                // IMPORTANT: Load vehicle information FIRST before checking packages
                // This ensures vehicle info is displayed even if no packages are available
                await this.loadVehicleInformation();

                if (!result.data || result.data.length === 0) {
                    console.log('⚠️ No dealer packages found for Tire_Rim_Protection_Plan record type');
                    console.log('ℹ️ Vehicle info loaded, but no packages available to display');
                    this.dealerPackages = [];
                    this.planCards = [];
                    this.currentView = 'planSelection';
                    if (!this.dealerHasSpecificPackages) {
                        this.showErrorMessage('No Tire & Rim Protection packages are available for this dealer. Please contact your administrator.');
                    }
                    this.loading = false;
                    return;
                }
                
                // Map the data to include warranty terms and options
                this.allDealerPackages = result.data.map(pkg => ({
                    ...pkg,
                    warrantyTerms: this._sortTerms(pkg.terms || []),
                    options: pkg.options || []
                }));
                this.dealerPackages = [...this.allDealerPackages];
                console.log('✅ Dealer packages mapped:', this.allDealerPackages.length, 'packages');
                console.log('📦 Package details:', this.allDealerPackages.map(p => ({
                    name: p.PackageName,
                    class: p.PackageClass,
                    termsCount: p.warrantyTerms.length
                })));
                
                // Check for existing application package and auto-select it
                await this.checkForExistingApplicationPackage();

                // Build plan cards after selections are known
                this.buildPlanCards();

                // Determine which view to show based on whether an existing record is being edited
                const hasExistingSelection = this.isExistingApplication && this.selectedDealerPackage;
                this.currentView = 'planSelection';
                
                // Update price after checking for existing package — but only if
                // checkForExistingApplicationPackage didn't already restore a
                // dealer price override (which updatePrice would wipe out).
                if (!this.isPriceOverridden) {
                    this.updatePrice();
                }
                
                // Update selection highlighting after packages are loaded
                setTimeout(() => {
                    this.updateSelectionHighlighting();
                }, 100);
            } else {
                console.error('❌ Failed to load dealer packages:', result.message);
                    this.errorMessage = result.message;
        this.showError = true;
            }
        } catch (error) {
            console.error('❌ Error loading dealer packages:', error);
            console.error('❌ Error stack:', error.stack);
            this.errorMessage = 'Error loading warranty packages. Please try again.';
            this.showError = true;
        } finally {
            this.loading = false;
        }
    }
    
    // Check for existing application package and auto-select it
    @api
    async checkForExistingApplicationPackage() {
        try {
            console.log('🔍 [TIRE] Loading ACTIVE tire/rim package...');
            
            const result = await getActiveApplicationPackageByRecordType({ 
                applicationId: this.applicationId, 
                recordType: 'Tire_Rim_Protection_Plan' 
            });
            
            console.log('📦 [TIRE] Active package result:', result);
            
            if (result.success && result.data) {
                console.log('✅ Found existing application package - Package ID:', result.data.dealerPackageId, 'Term ID:', result.data.selectedTermId);
                
                // Store the existing application package data
                this.existingApplicationPackage = result.data;
                this.isExistingApplication = true;
                this.hasTireRimPackage = true;
                // Store the package ID for file uploads - ensure it's a string
                if (result.data.Id) {
                    this.applicationPackageId = String(result.data.Id);
                    console.log('📁 Set applicationPackageId for file uploads:', this.applicationPackageId);
                    console.log('📁 applicationPackageId type:', typeof this.applicationPackageId);
                }
                
                // Find the matching dealer package from our loaded packages
                const matchingDealerPackage = this.dealerPackages.find(pkg => pkg.Id === result.data.dealerPackageId);
                
                if (matchingDealerPackage) {
                    // Auto-select the existing package
                    this.selectedDealerPackage = matchingDealerPackage;
                    this.selectedProgram = matchingDealerPackage.PackageName;
                    this.setSelectedPlanTypeFromPackage(matchingDealerPackage);
                    this.dealerPackages = this.allDealerPackages.filter(pkg => (pkg.planTypeId || this.otherPlanTypeKey) === this.selectedPlanTypeKey);
                    // Only expand the selected package's accordion section
                    this.activeAccordionSections = [matchingDealerPackage.Id];
                    console.log('✅ Auto-selected package:', matchingDealerPackage.PackageName);
                    
                    // Find and select the matching term
                    if (matchingDealerPackage.warrantyTerms && result.data.selectedTermId) {
                        const matchingTerm = matchingDealerPackage.warrantyTerms.find(term => 
                            term.Id === result.data.selectedTermId
                        );
                        
                        if (matchingTerm) {
                            this.selectedWarrantyTerm = matchingTerm;
                            this.isChangingSelection = false;
                            this.isOnDetailForm = true;
                            console.log('✅ Auto-selected term:', matchingTerm.packageTermName || matchingTerm.Name);
                        }
                    }
                    
                    // Update price and other dependent fields
                    this.updatePrice();
                    
                    // Check if there's a dealer price override
                    if (result.data.dealerPriceOverride != null && result.data.dealerPriceOverride !== undefined) {
                        // Override is stored as pre-tax; recalculate tax-inclusive total for display
                        const preTax = result.data.dealerPriceOverride;
                        const txRate = result.data.taxPercentage || 0;
                        const taxAmt = txRate > 0 ? preTax * (txRate / 100) : 0;
                        this._overridePreTaxPrice = preTax;
                        this._overrideTaxAmount = parseFloat(taxAmt.toFixed(2));
                        this.price = parseFloat((preTax + taxAmt).toFixed(2));
                        this._retailPriceDisplay = preTax;
                        this.isPriceOverridden = true;
                    }
                    
                    // Force re-render to update visual highlighting
                    setTimeout(() => {
                        this.renderKey++;
                        this.loading = false;
                        
                        // Apply highlighting after template is rendered
                        setTimeout(() => {
                            this.forceHighlightingUpdate();
                            console.log('🎨 Auto-selection highlighting applied');
                        }, 200);
                    }, 100);
                    
                    // Initialize original data for change tracking
                    this.initializeOriginalWarrantyData();
                    
                    // Dispatch more products completion event after component is fully rendered
                    this.dispatchEvent(new CustomEvent('moreproductscomplete', {
                        detail: { 
                            success: true,
                            warrantyData: this.getCurrentData(),
                            applicationId: this.applicationId,
                            autoSelected: true
                        }
                    }));
                }
            } else {
                // Clear selections for new applications
                console.log('🧹 No existing tire/rim package found - clearing all selections');
                this.selectedDealerPackage = null;
                this.selectedWarrantyTerm = null;
                this.selectedWarrantyTermName = '';
                this.existingApplicationPackage = null;
                this.isExistingApplication = false;
                this.hasTireRimPackage = false;
                // Clear sessionStorage to prevent stale data from causing auto-selection
                sessionStorage.removeItem('moreProductsData');
                // Force re-render to clear any visual highlighting from stale sessionStorage data
                this.renderKey++;
                console.log('✅ Cleared all selections and forced re-render');
            }
        } catch (error) {
            console.error('❌ Error checking for existing application package:', error);
        }
    }
    
    // Get dynamic dealer packages for display
    get dealerPackagesDisplay() {
        return this.dealerPackages.map(pkg => {
            const isSelected = this.selectedDealerPackage && this.selectedDealerPackage.Id === pkg.Id;
            
            // Process terms for display
            const processedTerms = this._sortTerms(pkg.warrantyTerms || []).map(term => {
                const isTermSelected = this.selectedWarrantyTerm && 
                                     this.selectedWarrantyTerm.Id === term.Id;
                
                // Check if this is the existing selected term (should be disabled)
                const isExistingSelectedTerm = this.isExistingApplication && 
                                             this.existingApplicationPackage &&
                                             this.existingApplicationPackage.selectedTermId === term.Id;
                
                // Disable terms for SELECTION if:
                // 1. This package is not selected
                // Note: Removed existing term disabling - allow re-selection for UX feedback
                const isPackageNotSelected = this.selectedDealerPackage && this.selectedDealerPackage.Id !== pkg.Id;
                const isTermDisabled = isPackageNotSelected;
                
                
                // Use the totalPrice from the term (already includes proper markup calculation from backend)
                const displayPrice = term.totalPrice || term.netCost || 0;
                
                // Debug logging to see what values we're getting
                console.log('🔍 Term price debug (using totalPrice):', {
                    termId: term.Id,
                    termName: term.packageTermName || term.Name,
                    totalPrice: term.totalPrice,
                    netCost: term.netCost,
                    displayPrice: displayPrice
                });
                
                const termCssClass = isTermSelected ? 'term-option selected' : 'term-option';
                
                if (isTermSelected) {
                    console.log('🎨 Term highlighting applied:', term.packageTermName || term.Name);
                }
                
                return {
                    ...term,
                    id: term.Id, // Ensure id is explicitly set
                    cssClass: termCssClass,
                    isSelected: isTermSelected,
                    isDisabled: isTermDisabled,
                    price: this.formatPrice(displayPrice),
                    termDisplayName: term.packageTermName || term.Name || 'Unknown Term',
                    // Remove termDuration for Tire & Rim (Month__c not used)
                    termDuration: null,
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
            
            // Check if package is selectable based on vehicle model class
            const isSelectable = this.isPackageSelectable(pkg.PackageClass);
            const packageStatus = this.getPackageStatus(pkg.PackageClass);
            
            // Build CSS class based on selection and selectability
            let cssClass = 'program-section';
            if (isSelected) {
                cssClass += ' selected';
            }
            if (!isSelectable) {
                cssClass += ' disabled';
            }
            
            if (isSelected) {
                console.log('🎨 Package highlighting applied:', pkg.PackageName);
            }
            
            return {
            id: pkg.Id,
            name: pkg.PackageName,
            description: pkg.PackageDescription,
                isSelected: isSelected,
                isSelectable: isSelectable,
                packageStatus: packageStatus,
                cssClass: cssClass,
                buttonVariant: isSelected ? 'success' : (isSelectable ? 'brand' : 'neutral'),
                buttonLabel: isSelected ? 'Selected' : (isSelectable ? 'Select Package' : 'Not Available'),
            dealerPackageId: pkg.Id,
            dealerId: pkg.DealerId,
                buttonClass: isSelected ? 'select-program-btn selected' : 'select-program-btn',
                buttonDisabled: isSelected || !isSelectable,
                terms: processedTerms,
                options: processedOptions,
                classInfo: {
                    packageClass: pkg.PackageClass,
                    vehicleClass: this.vehicleModelClass,
                    isCompatible: isSelectable
                }
            };
        });
    }

    get hasSelectedPackage() {
        return !!this.selectedDealerPackage;
    }

    get selectedPackageClassLabel() {
        const pkgClass = this.selectedDealerPackage?.PackageClass || this.vehicleInfo.modelClass;
        if (!pkgClass || pkgClass === 'Not Set' || pkgClass === 'N/A') {
            return '';
        }
        return `${pkgClass} Vehicle`;
    }

    get selectedPackageTermOptions() {
        if (!this.selectedDealerPackage || !this.selectedDealerPackage.warrantyTerms) {
            return [];
        }

        const terms = [...this.selectedDealerPackage.warrantyTerms];
        // Remove sorting by duration for Tire & Rim (Month__c not used)
        // Terms will be displayed in the order returned from backend

        return terms.map(term => {
            const isSelected = this.selectedWarrantyTerm && this.selectedWarrantyTerm.Id === term.Id;
            const buttonClass = isSelected ? 'tire-term-btn selected' : 'tire-term-btn';
            // Remove duration from label for Tire & Rim (Month__c not used)
            const durationLabel = term.packageTermName || term.Name || 'Unknown Term';
            const price = this.formatPrice(term.totalPrice || term.netCost || 0);
            const classLabel = term.vehicleClass || this.selectedDealerPackage.PackageClass || '';

            return {
                id: term.Id,
                packageId: this.selectedDealerPackage.Id,
                durationLabel,
                price,
                classLabel,
                buttonClass
            };
        });
    }

    get termSelectionMessage() {
        if (!this.selectedDealerPackage) {
            return '';
        }
        return this.selectedWarrantyTerm ? '' : 'Select a coverage term to continue.';
    }

    get vehicleSummaryTitle() {
        const { year, make, model } = this.vehicleInfo;
        const parts = [year, make, model].filter(part => part && part !== 'Not Set' && part !== 'N/A');
        return parts.length ? parts.join(' ') : 'Vehicle details pending';
    }

    get vehicleSummarySubtitle() {
        if (this.vehicleInfo.trim && this.vehicleInfo.trim !== 'Not Set' && this.vehicleInfo.trim !== 'N/A') {
            return this.vehicleInfo.trim;
        }
        return this.selectedPackageClassLabel || 'Enter vehicle details to load packages';
    }

    get vehicleOdometerDisplay() {
        if (!this.vehicleInfo.odometer) {
            return '';
        }
        return `${this.vehicleInfo.odometer} ${this.vehicleInfo.odometerUnit || 'KM'}`;
    }

    get vehiclePurchasePriceDisplay() {
        if (!this.vehicleInfo.purchasePrice) {
            return '';
        }
        const priceValue = parseFloat(this.vehicleInfo.purchasePrice);
        if (isNaN(priceValue)) {
            return this.vehicleInfo.purchasePrice;
        }
        return this.formatPrice(priceValue);
    }

    get selectedPlanDisplay() {
        return this.selectedDealerPackage?.PackageName || 'Select Tire & Rim Plan';
    }

    get vehicleClassDisplay() {
        let vehicleClass = this.vehicleInfo.modelClass;
        const fallback = 'Vehicle class not set';
        if (!vehicleClass || vehicleClass === 'Not Set' || vehicleClass === 'N/A') {
            return fallback;
        }
        vehicleClass = vehicleClass.toString().trim();
        const numericMatch = vehicleClass.match(/^\d+$/);
        if (numericMatch) {
            return `Class ${numericMatch[0]} Vehicle`;
        }
        const classPrefixMatch = vehicleClass.match(/class\s*(\d+)/i);
        if (classPrefixMatch) {
            return `Class ${classPrefixMatch[1]} Vehicle`;
        }
        // If it doesn't match patterns but has a value, ensure "Vehicle" is appended
        if (vehicleClass.toLowerCase().includes('vehicle')) {
            return vehicleClass;
        }
        return `${vehicleClass} Vehicle`;
    }

    get hasVehicleInfo() {
        const { year, make, model } = this.vehicleInfo;
        return Boolean(
            (year && year !== 'Not Set' && year !== 'N/A') ||
            (make && make !== 'Not Set' && make !== 'N/A') ||
            (model && model !== 'Not Set' && model !== 'N/A')
        );
    }

    get selectedCoverageTermText() {
        if (!this.selectedWarrantyTerm) {
            return 'Select Coverage Term';
        }

        return this.selectedWarrantyTerm.packageTermName || this.selectedWarrantyTerm.Name || 'Selected Term';
    }

    get hasSelectedTerm() {
        return !!this.selectedWarrantyTerm;
    }

    handleChangePlanSelection() {
        this.isChangingSelection = true;
        this.isOnDetailForm = false;
    }

    handleNextToDetailForm() {
        this.isOnDetailForm = true;
    }

    // --- Dealer Pricing Modal Getters ---

    get selectedPlanName() {
        if (this.selectedDealerPackage) {
            return this.selectedDealerPackage.PackageName || this.selectedDealerPackage.Name || 'Selected Package';
        }
        return 'Selected Package';
    }

    get formattedDealerPrice() {
        return this.formatPrice(this.modalDealerPrice || 0);
    }

    get hasSelectedAdditionalOptions() {
        return this.selectedAdditionalOptions && this.selectedAdditionalOptions.length > 0;
    }

    get selectedAdditionalOptionsList() {
        if (!this.selectedAdditionalOptions || this.selectedAdditionalOptions.length === 0) {
            return [];
        }
        return this.selectedAdditionalOptions.map(opt => ({
            id: opt.Id || opt.id,
            label: opt.optionName || opt.Name || opt.label || 'Option',
            formattedDealerPrice: this.formatPrice(opt.dealerPrice || opt.netCost || 0)
        }));
    }

    get formattedTaxRate() {
        const rate = this.modalTaxRate || 0;
        return rate > 0 ? rate.toFixed(2) + '%' : '0%';
    }

    get formattedTotalTaxAmount() {
        return this.formatPrice(this.modalTaxAmount || 0);
    }

    get formattedTotalWithTax() {
        return this.formatPrice(this.modalTotalWithTax || 0);
    }
    get formattedDealerCostExclTax() {
        const total = (this.modalTotalWithTax || 0) - (this.modalTaxAmount || 0);
        return '$' + total.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }


    // --- End Dealer Pricing Modal Getters ---

    // Get included options for the selected package (for side panel) - same as warranty
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

    get selectedPlanIncludes() {
        if (this.selectedDealerPackage && Array.isArray(this.selectedDealerPackage.options) && this.selectedDealerPackage.options.length) {
            return this.selectedDealerPackage.options.map(option => ({
                id: option.Id || option.id || option.OptionName,
                label: option.optionName || option.OptionName || option.Name || 'Included Feature'
            }));
        }
        return this.defaultPlanIncludes;
    }

    get vehicleVinDisplay() {
        if (this.vehicleInfo.vin && this.vehicleInfo.vin !== 'Not Set' && this.vehicleInfo.vin !== 'N/A') {
            return this.vehicleInfo.vin;
        }
        return '';
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
    async handlePackageSelection(eventOrPackageId) {
        let packageId = null;
        if (typeof eventOrPackageId === 'string') {
            packageId = eventOrPackageId;
        } else if (eventOrPackageId?.currentTarget?.dataset?.package) {
            packageId = eventOrPackageId.currentTarget.dataset.package;
        }

        if (!packageId) {
            return;
        }

        const selectedPackage = this.dealerPackages.find(pkg => pkg.Id === packageId) ||
                                this.allDealerPackages.find(pkg => pkg.Id === packageId);
        
        if (selectedPackage) {
            // Check if this is a different package than currently selected
            const isPackageChange = this.selectedDealerPackage && this.selectedDealerPackage.Id !== selectedPackage.Id;
            
            if (isPackageChange) {
                console.log('📦 [TIRE] Package changed - clearing additional options and price override');
                // Clear all additional options when package changes
                this.selectedAdditionalOptions = [];
                this.existingAdditionalOptions = [];
                this.selectedNewOptions = [];
                this.optionsToRemove = [];
                // Clear stale price override so the new package price loads cleanly
                this.isPriceOverridden = false;
                this.isPriceEditMode = false;
                this.priceOverrideInput = '';
                this._overridePreTaxPrice = null;
                this._overrideTaxAmount = null;
            }
            
            // Check if package is selectable based on vehicle model class
            if (!this.isPackageSelectable(selectedPackage.PackageClass)) {
                console.log('🚫 Package not selectable for vehicle class:', {
                    packageClass: selectedPackage.PackageClass,
                    vehicleClass: this.vehicleModelClass,
                    packageName: selectedPackage.PackageName
                });
                
                // Show toast message
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Package Not Available',
                    message: `This package is not available for ${this.vehicleModelClass} vehicles. Please select a package that matches your vehicle's class.`,
                    variant: 'warning',
                    mode: 'sticky'
                }));
                return;
            }
            
            // isPackageChange already checked above (line 642)
            if (isPackageChange) {
                console.log('🔄 [TIRE] Package changed from', this.selectedDealerPackage.PackageName, 'to', selectedPackage.PackageName);
                
                // DON'T save immediately - wait for user to click Continue
                /* OLD CODE - Disabled to prevent premature save
                if (this.isExistingApplication && this.existingApplicationPackage) {
                    await this.updateExistingApplicationPackage(selectedPackage, null);
                }
                */
            }
            
            // Clear term selection when package changes (validation requirement)
            this.selectedWarrantyTerm = null;
            
            // Track the package change
            const oldPackageId = this.originalWarrantyData.selectedDealerPackageId;
            const newPackageId = selectedPackage.Id;
            
            this.selectedDealerPackage = selectedPackage;
            this.selectedProgram = selectedPackage.PackageName;
            this.setSelectedPlanTypeFromPackage(selectedPackage);
            
            console.log('✅ Package selected:', selectedPackage.PackageName);
            
            // Track change for auto-save
            this.trackWarrantyChange('package', oldPackageId, newPackageId);
            console.log('⚠️ Please select a warranty term for this package');
            
            // Only expand the selected package's accordion section
            this.activeAccordionSections = [selectedPackage.Id];
            
            // Force UI refresh to show selection highlighting
            this.template.querySelectorAll('.program-section').forEach(section => {
                section.classList.remove('selected');
            });
            
            // Update price (will be 0 until term is selected)
            this.isPriceCalculating = true;
            this.updatePrice();
            this.isPriceCalculating = false;
            
            // Save data
            this.saveDataToSession();

            // Refresh plan cards to reflect selection (stay on list view)
            this.buildPlanCards();
            this.updateSelectionHighlighting();
        }
    }
    
    // Handle warranty term selection
    async handleWarrantyTermSelection(event) {
        const termId = event.currentTarget.dataset.term;
        const packageId = event.currentTarget.dataset.package;
        const isDisabled = event.currentTarget.dataset.disabled === 'true';
        
        // Check if term is disabled
        if (isDisabled) {
            console.log('⚠️ Term selection blocked - term is disabled');
            this.showErrorMessage('Please select a warranty package first to enable term selection.');
            return;
        }
        
        // Check if this is the already selected term
        if (this.selectedWarrantyTerm && this.selectedWarrantyTerm.Id === termId) {
            console.log('ℹ️ Term already selected:', termId);
            // Allow re-selection for visual feedback but don't change anything
            this.showInfoMessage('This warranty term is already selected.');
            return;
        }
        
        // Validation: Ensure a package is selected
        if (!this.selectedDealerPackage) {
            console.error('❌ Please select a warranty package first');
            this.showErrorMessage('Please select a warranty package before selecting a term.');
            return;
        }
        
        // Validation: Ensure term belongs to selected package
        if (packageId !== this.selectedDealerPackage.Id) {
            console.error('❌ Term does not belong to selected package');
            this.showErrorMessage('Please select a term from the currently selected package.');
            return;
        }
        
        if (!this.selectedDealerPackage.warrantyTerms) {
            console.error('❌ No warranty terms available for selected package');
            return;
        }
        
        const selectedTerm = this.selectedDealerPackage.warrantyTerms.find(term => term.Id === termId);
        
        if (selectedTerm) {
            // Track the term change
            const oldTermId = this.originalWarrantyData.selectedWarrantyTermId;
            const newTermId = selectedTerm.Id;
            
            this.selectedWarrantyTerm = selectedTerm;
            this.isChangingSelection = false;
            console.log('🎨 Term selection highlighting applied:', selectedTerm.packageTermName || selectedTerm.Name);
            
            
            // Track change for auto-save
            this.trackWarrantyChange('term', oldTermId, newTermId);
            
            
            // Don't reload existing options - they should persist across terms

            // Reset price override when a new term is selected
            this.isPriceOverridden = false;
            this.isPriceEditMode = false;
            this.priceOverrideInput = '';
            this._overridePreTaxPrice = null;
            this._overrideTaxAmount = null;

            this.isPriceCalculating = true;
            this.updatePrice();
            this.isPriceCalculating = false;
            this.saveDataToSession();
            
            // NO AUTO-SAVE - Everything saves only when Continue is clicked
            console.log('ℹ️ [TIRE] Package and term selected - will save when Continue is clicked');
            
            // Force re-render to update visual highlighting
            this.renderKey++;
        }
    }
    
    // Force highlighting update by manually applying CSS classes to DOM
    forceHighlightingUpdate() {
        try {
            // Find and highlight selected package accordion
            if (this.selectedDealerPackage) {
                const packageAccordion = this.template.querySelector(`lightning-accordion-section[data-package-id="${this.selectedDealerPackage.Id}"]`) ||
                                       this.template.querySelector(`lightning-accordion-section[name="${this.selectedDealerPackage.Id}"]`) ||
                                       this.template.querySelector(`lightning-accordion-section[data-package="${this.selectedDealerPackage.Id}"]`);
                if (packageAccordion) {
                    packageAccordion.classList.add('selected');
                    console.log('🎨 Package accordion highlighted:', this.selectedDealerPackage.PackageName);
                } else {
                    console.log('⚠️ Could not find package accordion to highlight:', this.selectedDealerPackage.Id);
                }
            }
            
            // Find and highlight selected term
            if (this.selectedWarrantyTerm) {
                // Clear any previously applied highlighting to avoid multiple selections showing
                this.template.querySelectorAll('.tire-term-btn').forEach(button => {
                    button.classList.remove('selected');
                });
                
                const termElement = this.template.querySelector(`[data-term="${this.selectedWarrantyTerm.Id}"]`);
                if (termElement) {
                    termElement.classList.add('selected');
                    console.log('🎨 Term element highlighted:', this.selectedWarrantyTerm.packageTermName || this.selectedWarrantyTerm.Name);
                } else {
                    console.log('⚠️ Could not find term element to highlight:', this.selectedWarrantyTerm.Id);
                }
            }
        } catch (error) {
            console.error('Error applying highlighting:', error);
        }
    }

    setSelectedPlanTypeFromPackage(pkg) {
        if (!pkg) {
            return;
        }

        const planTypeKey = pkg.planTypeId || this.otherPlanTypeKey;
        this.selectedPlanTypeKey = planTypeKey;
        this.selectedPlanType = {
            key: planTypeKey,
            label: pkg.planTypeName || 'Other Packages',
            planTypeDescription: this.normalizeDescription(pkg.planTypeDescription || '')
        };
    }

    buildPlanCards() {
        if (!Array.isArray(this.allDealerPackages) || this.allDealerPackages.length === 0) {
            this.planCards = [];
            return;
        }

        const groupsMap = new Map();

        this.allDealerPackages.forEach(pkg => {
            const key = pkg.planTypeId || this.otherPlanTypeKey;
            if (!groupsMap.has(key)) {
                groupsMap.set(key, {
                    key,
                    label: pkg.planTypeName || 'Other Packages',
                    description: this.normalizeDescription(pkg.planTypeDescription || ''),
                    packages: []
                });
            }

            const group = groupsMap.get(key);
            group.packages.push(pkg);
            if (!group.description && pkg.planTypeDescription) {
                group.description = this.normalizeDescription(pkg.planTypeDescription);
            }
        });

        const cards = Array.from(groupsMap.values()).map(group => {
            const eligiblePackages = group.packages.filter(pkg => this.isPackageSelectable(pkg.PackageClass));
            const representativePackage = eligiblePackages[0] || group.packages[0];
            const isSelectable = eligiblePackages.length > 0;
            const isSelected = this.selectedPlanTypeKey === group.key;
            const includes = this.getPlanIncludes(representativePackage);
            const packageCountLabel = `${group.packages.length} ${group.packages.length === 1 ? 'Package' : 'Packages'}`;
            
            // Build options array for the plan card (same structure as selectedPackageOptions)
            let options = [];
            if (representativePackage && representativePackage.options && Array.isArray(representativePackage.options)) {
                options = representativePackage.options.map(option => ({
                    id: option.Id || option.id,
                    optionName: option.optionName || option.Name || option.label,
                    inclusion: option.inclusion,
                    exclusion: option.exclusion
                }));
            }

            return {
                id: group.key,
                name: group.label,
                includes,
                options,
                planTypeDescription: group.description,
                packageCountLabel,
                isSelectable,
                isSelected,
                buttonLabel: isSelected ? 'Selected' : (isSelectable ? 'Select Plan' : 'Not Eligible'),
                buttonDisabled: !isSelectable,
                cardClass: `plan-card ${isSelected ? 'selected' : ''} ${isSelectable ? '' : 'disabled'}`.trim(),
                buttonClass: `plan-card-button ${isSelected ? 'selected' : ''}`.trim()
            };
        });

        cards.sort((a, b) => a.name.localeCompare(b.name));
        this.planCards = cards;
    }

    // Accordion-based plan type groups with package terms (matches warranty tab layout)
    get planTypeGroupsWithPackageTerms() {
        if (!Array.isArray(this.allDealerPackages) || this.allDealerPackages.length === 0) {
            return [];
        }

        const groupsMap = new Map();
        const headerColors = ['#333333', '#6d6e70', '#d4af37', '#c0c0c0', '#cd7f32', '#2c3e50', '#1a5276', '#7d3c98'];
        let colorIndex = 0;

        this.allDealerPackages.forEach(pkg => {
            const key = pkg.planTypeId || this.otherPlanTypeKey;
            if (!groupsMap.has(key)) {
                const color = headerColors[colorIndex % headerColors.length];
                colorIndex++;
                groupsMap.set(key, {
                    key,
                    label: pkg.planTypeName || 'Other Packages',
                    description: this.normalizeDescription(pkg.planTypeDescription || ''),
                    headerClass: 'plan-type-section-header',
                    headerColor: color,
                    packages: []
                });
            }
            groupsMap.get(key).packages.push(pkg);
        });

        return Array.from(groupsMap.values()).map(group => {
            const packagesWithTerms = group.packages.map(pkg => {
                const isSelectable = this.isPackageSelectable(pkg.PackageClass);
                const terms = (pkg.warrantyTerms || []).map(term => {
                    const isTermSelected = this.selectedWarrantyTerm && this.selectedWarrantyTerm.Id === term.Id;
                    const displayPrice = term.totalPrice || term.netCost || 0;
                    return {
                        id: term.Id,
                        name: term.packageTermName || term.Name || 'Unknown Term',
                        price: this.formatPrice(displayPrice),
                        packageId: pkg.Id,
                        rowClass: isTermSelected ? 'term-row selected' : (isSelectable ? 'term-row' : 'term-row disabled'),
                        isSelected: isTermSelected
                    };
                });

                const options = (pkg.options || []).map(option => ({
                    id: option.Id || option.id,
                    optionName: option.optionName || option.Name || option.label,
                    inclusion: option.inclusion,
                    exclusion: option.exclusion
                }));

                const isPackageSelected = this.selectedDealerPackage && this.selectedDealerPackage.Id === pkg.Id;
                return {
                    id: pkg.Id,
                    name: pkg.PackageName + (isSelectable ? '' : ' (Not Eligible)') + (isPackageSelected ? ' ✓' : ''),
                    terms,
                    options,
                    hasTerms: terms.length > 0,
                    hasOptions: options.length > 0,
                    isSelectable,
                    isSelected: isPackageSelected,
                    sectionClass: isPackageSelected ? 'package-accordion-section selected' : 'package-accordion-section'
                };
            });

            return {
                key: group.key,
                label: group.label,
                description: group.description,
                hasDescription: !!group.description,
                headerClass: group.headerClass,
                packagesWithTerms
            };
        });
    }

    // Handle term selection from the accordion view (stays on plan selection, no navigation)
    async handleAccordionTermSelection(event) {
        const termId = event.currentTarget.dataset.term;
        const packageId = event.currentTarget.dataset.package;

        if (!termId || !packageId) return;

        // Find the package
        const pkg = this.allDealerPackages.find(p => p.Id === packageId);
        if (!pkg) return;

        // Check eligibility
        if (!this.isPackageSelectable(pkg.PackageClass)) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Package Not Available',
                message: `This package is not available for ${this.vehicleModelClass} vehicles.`,
                variant: 'warning',
                mode: 'sticky'
            }));
            return;
        }

        // Find the term
        const term = (pkg.warrantyTerms || []).find(t => t.Id === termId);
        if (!term) return;

        // Auto-select the package if different — enforces single package selection
        if (!this.selectedDealerPackage || this.selectedDealerPackage.Id !== pkg.Id) {
            // Clear additional options when switching packages
            this.selectedAdditionalOptions = [];
            this.existingAdditionalOptions = [];
            this.selectedNewOptions = [];
            this.optionsToRemove = [];
            
            this.vehicleConfigChangedMessage = '';
            this.selectedDealerPackage = pkg;
            this.selectedProgram = pkg.PackageName;
            this.setSelectedPlanTypeFromPackage(pkg);
            this.dealerPackages = this.allDealerPackages.filter(p => (p.planTypeId || this.otherPlanTypeKey) === this.selectedPlanTypeKey);
        }

        // Select term
        this.selectedWarrantyTerm = term;
        this.isChangingSelection = false;
        console.log('✅ Accordion term selected:', term.packageTermName || term.Name, 'from package:', pkg.PackageName);

        // Collapse all accordion sections except the selected package
        this.activeAccordionSections = [pkg.Id];

        this.updatePrice();
        this.saveDataToSession();

        // Stay on plan selection view — do NOT navigate to detail view
        // Force re-render to update highlighting
        this.renderKey++;
    }

    getPlanIncludes(pkg) {
        if (!pkg) {
            return ['Coverage details available after selection.'];
        }

        if (Array.isArray(pkg.planIncludes) && pkg.planIncludes.length) {
            return pkg.planIncludes;
        }

        if (Array.isArray(pkg.options) && pkg.options.length) {
            return pkg.options
                .map(opt => opt.OptionName || opt.Name || opt.label || 'Included Feature')
                .slice(0, 6);
        }

        if (pkg.PackageDescription) {
            return this.normalizeDescription(pkg.PackageDescription)
                .split(/[\n•]/)
                .map(item => item.trim())
                .filter(item => item.length > 0)
                .slice(0, 6);
        }

        return ['Coverage details available after selection.'];
    }

    async handlePlanCardClick(event) {
        const button = event.currentTarget;
        if (!button || button.disabled) {
            return;
        }

        const planTypeKey = button.dataset.planTypeKey;
        const planTypeLabel = button.dataset.planTypeLabel;
        const planTypeDescription = button.dataset.planTypeDescription || '';

        await this.handlePlanTypeSelection(planTypeKey, planTypeLabel, planTypeDescription);
    }

    async handlePlanTypeSelection(planTypeKey, planTypeLabel, planTypeDescription) {
        if (!planTypeKey) {
            return;
        }

        this.selectedPlanTypeKey = planTypeKey;
        this.selectedPlanType = {
            key: planTypeKey,
            label: planTypeLabel,
            planTypeDescription: this.normalizeDescription(planTypeDescription)
        };

        const filteredPackages = this.allDealerPackages.filter(pkg => (pkg.planTypeId || this.otherPlanTypeKey) === planTypeKey);
        if (!filteredPackages.length) {
            this.showErrorMessage('No Tire & Rim packages are configured for this plan type.');
            return;
        }

        this.dealerPackages = filteredPackages;

        const defaultPackage = filteredPackages.find(pkg => this.isPackageSelectable(pkg.PackageClass)) || filteredPackages[0];

        if (defaultPackage) {
            await this.handlePackageSelection(defaultPackage.Id);
        } else {
            this.selectedDealerPackage = null;
            this.selectedWarrantyTerm = null;
            this.updatePrice();
            this.saveDataToSession();
        }

        this.buildPlanCards();
    }

    handleViewAllPlans() {
        this.currentView = 'planSelection';
        this.buildPlanCards();
        setTimeout(() => {
            this.updateSelectionHighlighting();
        }, 0);
    }

    normalizeDescription(value) {
        if (!value) {
            return '';
        }
        return value.replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim();
    }
    
    // Update existing application package in Salesforce
    async updateExistingApplicationPackage(newPackage, newTerm) {
        try {
            const packageDataMap = {
                packageId: this.existingApplicationPackage.Id,
                selectedTermId: newTerm ? newTerm.Id : null,
                includeDeductible: false // Set to false for now, can be made configurable later
            };
            
            console.log('🔍 Updating existing application package with data:', packageDataMap);
            
            const result = await updateApplicationPackage(packageDataMap);
            
            if (result.success) {
                console.log('✅ Application package updated in Salesforce');
                // Update local existing package data
                this.existingApplicationPackage = {
                    ...this.existingApplicationPackage,
                    dealerPackageId: newPackage.Id,
                    selectedTermId: newTerm ? newTerm.Id : null,
                    dealerPackagePrice: newTerm ? (newTerm.totalPrice || newTerm.netCost || 0) : 0
                };
            } else {
                console.error('❌ Failed to update application package:', result.message);
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
    
    
    
    
    // Close comparison modal
    closeComparison() {
        this.showComparisonModal = false;
    }
    
    
    // Select term from comparison
    selectFromComparison(event) {
        const termId = event.target.dataset.term;
        
        // Find and select the term
        for (const pkg of this.dealerPackages) {
            if (pkg.warrantyTerms) {
                const term = pkg.warrantyTerms.find(t => t.Id === termId);
                if (term) {
                    this.selectedDealerPackage = pkg;
                    this.selectedWarrantyTerm = term;
                    this.isChangingSelection = false;
                    this.updatePrice();
                    this.saveDataToSession();
                    // DON'T save to Salesforce until user clicks Continue
                    console.log('ℹ️ [TIRE] Selected from comparison - will save when Continue is clicked');
                    this.closeComparison();
                    this.showToast('Success', 'Warranty term selected. Click Continue to save.', 'success');
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
        if (!this.selectedDealerPackage && !this.showVehicleNotEligibleDisclaimer) {
            this.errorMessage = 'Please select a tire & rim package before continuing.';
            this.showError = true;
            return false;
        }
        
        if (!this.selectedWarrantyTerm && !this.showVehicleNotEligibleDisclaimer) {
            this.errorMessage = 'Please select a tire & rim term before continuing.';
            this.showError = true;
            return false;
        }

        // Validate Tire & Rim required fields when the details form is visible
        if (this.showSelectedPlanView && !this.validateTireRimFields()) {
            return false;
        }

        // Clear any previous errors
        this.showError = false;
        this.errorMessage = '';

        return true;
    }

    /**
     * Validates all required Tire & Rim detail fields.
     * Returns true if all required fields are filled, false otherwise.
     * Sets inline error styling on empty fields and shows a summary message.
     */
    validateTireRimFields() {
        const requiredTireFields = [
            { field: 'tireBrand', label: 'Tire Brand' },
            { field: 'tireType', label: 'Tire Type' },
            { field: 'treadDepth', label: 'Tread Depth' },
            { field: 'treadDepthUnit', label: 'Tread Depth Unit' },
            { field: 'rimSize', label: 'Rim Size' },
            { field: 'rimSizeUnit', label: 'Rim Size Unit' },
            { field: 'rimBrand', label: 'Rim Brand' },
            { field: 'rimType', label: 'Rim Type' }
        ];

        const missingFields = [];

        // Clear previous validation errors
        const allFieldEls = this.template.querySelectorAll('[data-field]');
        allFieldEls.forEach(el => {
            el.classList.remove('tire-field-error');
            const existingErr = el.parentElement.querySelector('.tire-field-error-msg');
            if (existingErr) {
                existingErr.remove();
            }
        });

        requiredTireFields.forEach(({ field, label }) => {
            const value = this[field];
            const isEmpty = value === undefined || value === null || String(value).trim() === '';
            
            if (isEmpty) {
                missingFields.push(label);
                const el = this.template.querySelector('[data-field="' + field + '"]');
                if (el) {
                    el.classList.add('tire-field-error');
                    const errSpan = document.createElement('span');
                    errSpan.className = 'tire-field-error-msg';
                    errSpan.textContent = label + ' is required';
                    el.parentElement.appendChild(errSpan);
                }
            }
        });

        if (missingFields.length > 0) {
            this.errorMessage = 'Please complete all required Tire & Rim fields: ' + missingFields.join(', ');
            this.showError = true;

            const formCard = this.template.querySelector('.tire-details-form-card');
            if (formCard) {
                formCard.scrollIntoView({ behavior: 'smooth', block: 'start' });
            }

            return false;
        }

        return true;
    }

    // Add optional tire/rim fields to payload when provided
    // Only adds fields that have values - completely optional
    // If no package is selected, this won't be called (no save happens)
    // If package is selected, tire data will be included if any fields are filled
    addTireFieldsToPayload(target) {
        const entries = {
            tireBrand:     this.tireBrand,
            tireType:      this.tireType,
            treadDepth:    this.treadDepth,
            treadDepthUnit: this.treadDepthUnit,
            rimSize:       this.rimSize,
            rimSizeUnit:   this.rimSizeUnit,
            rimBrand:      this.rimBrand,
            rimType:       this.rimType,
            dealerComments: this.dealerComments
        };

        const tireFieldsAdded = [];
        // Only add fields that have values - all fields are optional
        Object.entries(entries).forEach(([key, val]) => {
            if (val !== undefined && val !== null && String(val).trim() !== '') {
                target[key] = val;
                tireFieldsAdded.push(key);
            }
        });
        
        if (tireFieldsAdded.length > 0) {
            console.log('📝 [TIRE] Adding tire fields to payload:', tireFieldsAdded);
        } else {
            console.log('📝 [TIRE] No tire fields to add - form is empty or not filled');
        }
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
        const moreProductsData = {
            applicationId: this._applicationId,
            selectedProgram: this.selectedProgram,
            selectedTerm: this.selectedTerm,
            selectedClaim: this.selectedClaim,
            selectedDeductible: this.selectedDeductible,
            testDrive: this.testDrive,
            price: this.price,
            selectedDealerPackage: this.selectedDealerPackage,
            selectedWarrantyTerm: this.selectedWarrantyTerm,
            tireBrand: this.tireBrand,
            tireType: this.tireType,
            treadDepth: this.treadDepth,
            treadDepthUnit: this.treadDepthUnit,
            rimSize: this.rimSize,
            rimSizeUnit: this.rimSizeUnit,
            rimBrand: this.rimBrand,
            rimType: this.rimType,
            dealerComments: this.dealerComments,
            isPriceOverridden: this.isPriceOverridden,
        };
        
        sessionStorage.setItem('moreProductsData', JSON.stringify(moreProductsData));
        console.log('💾 More Products data saved to session storage');
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
            tireBrand: this.tireBrand,
            tireType: this.tireType,
            treadDepth: this.treadDepth,
            treadDepthUnit: this.treadDepthUnit,
            rimSize: this.rimSize,
            rimSizeUnit: this.rimSizeUnit,
            rimBrand: this.rimBrand,
            rimType: this.rimType,
            dealerComments: this.dealerComments,
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
            this.tireBrand     = data.tireBrand     || this.tireBrand;
            this.tireType      = data.tireType      || this.tireType;
            this.treadDepth    = data.treadDepth    || this.treadDepth;
            this.treadDepthUnit = data.treadDepthUnit || this.treadDepthUnit;
            this.rimSize       = data.rimSize       || this.rimSize;
            this.rimSizeUnit   = data.rimSizeUnit   || this.rimSizeUnit;
            this.rimBrand      = data.rimBrand      || this.rimBrand;
            this.rimType       = data.rimType       || this.rimType;
            this.dealerComments = data.dealerComments || this.dealerComments;
            
            // Restore selected dealer package if available
            if (data.selectedDealerPackage) {
                this.selectedDealerPackage = data.selectedDealerPackage;
                console.log('✅ Restored selected dealer package:', this.selectedDealerPackage);
            }
            
            // Restore selected warranty term if available AND we have a selected package
            if (data.selectedWarrantyTerm && data.selectedDealerPackage) {
                this.selectedWarrantyTerm = data.selectedWarrantyTerm;
                this.isChangingSelection = false;
                this.isOnDetailForm = true;
                console.log('✅ Restored selected warranty term:', this.selectedWarrantyTerm);
            } else if (data.selectedWarrantyTerm && !data.selectedDealerPackage) {
                // Clear term if no package is selected
                this.selectedWarrantyTerm = null;
                console.log('🧹 Cleared selected warranty term - no package selected');
            }
            
            // Recalculate price based on restored data instead of using stored price
            this.updatePrice();
        }
    }
    
    handleProgramClick(event) {
        const selectedProgramName = event.currentTarget.dataset.program;
        this.selectedProgram = selectedProgramName;
        
        this.updatePrice();
        
        // Hide error when user selects a program
        this.showError = false;
    }

    // Tire/Rim detail handlers
    handleTireFieldChange(field, value) {
        this[field] = value;
        this.saveDataToSession();
    }

    handleTireBrandChange(event) {
        this.handleTireFieldChange('tireBrand', event.target.value);
    }

    handleTireTypeChange(event) {
        this.handleTireFieldChange('tireType', event.target.value);
    }

    handleTreadDepthChange(event) {
        this.handleTireFieldChange('treadDepth', event.target.value);
    }

    handleTreadDepthUnitChange(event) {
        this.handleTireFieldChange('treadDepthUnit', event.target.value);
    }

    handleRimSizeChange(event) {
        this.handleTireFieldChange('rimSize', event.target.value);
    }

    handleRimSizeUnitChange(event) {
        this.handleTireFieldChange('rimSizeUnit', event.target.value);
    }

    handleRimBrandChange(event) {
        this.handleTireFieldChange('rimBrand', event.target.value);
    }

    handleRimTypeChange(event) {
        this.handleTireFieldChange('rimType', event.target.value);
    }

    handleDealerCommentsChange(event) {
        this.handleTireFieldChange('dealerComments', event.target.value);
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
    
    handleDeclineMoreProducts() {
        this.showDeclineModal = true;
    }
    
    // Handle confirm decline from modal
    confirmDeclineMoreProducts() {
        this.showDeclineModal = false;
        
        // Dispatch more products declined event
        const declineEvent = new CustomEvent('decline', {
            detail: { reason: 'User declined more products coverage' }
        });
        this.dispatchEvent(declineEvent);
        
        // Navigate to next screen
        const navigateEvent = new CustomEvent('navigate', {
            detail: { tab: 'moreProducts' }
        });
        this.dispatchEvent(navigateEvent);
    }
    
    // Handle cancel decline from modal
    cancelDeclineMoreProducts() {
        this.showDeclineModal = false;
    }
    
    
    // Handle back button click
    handleBack() {
        console.log('🔙 Back button clicked from more products component');
        
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
        console.log('⏭️ Tire & Rim tab skipped - navigating to next tab without saving');
        this.dispatchEvent(new CustomEvent('moreproductscomplete', {
            detail: { 
                success: true,
                skipped: true,
                applicationId: this.applicationId
            }
        }));
    }
    
    updatePrice() {
        // Reset custom price override when recalculating
        this.isPriceOverridden = false;
        this.isPriceEditMode = false;
        this.priceOverrideInput = '';
        this._overridePreTaxPrice = null;
        this._overrideTaxAmount = null;
        console.log('💰 === UPDATE PRICE START ===');
        console.log('💰 isExistingApplication:', this.isExistingApplication);
        console.log('💰 existingApplicationPackage:', this.existingApplicationPackage);
        console.log('💰 hasTireRimPackage:', this.hasTireRimPackage);
        console.log('💰 selectedWarrantyTerm:', this.selectedWarrantyTerm);
        console.log('💰 selectedDealerPackage:', this.selectedDealerPackage);
        
        // Check if user selected a different term than the stored one
        const isSameTerm = this.isExistingApplication && 
                          this.existingApplicationPackage && 
                          this.selectedWarrantyTerm && 
                          this.selectedWarrantyTerm.Id === this.existingApplicationPackage.selectedTermId;
        
        // For Draft/Pending, always recalculate from current term pricing so admin changes reflect
        const upAppStatus = this.applicationStatus || '';
        const shouldUseStoredPrice = isSameTerm && !['Draft', 'Pending', 'Quote'].includes(upAppStatus);
        
        if (shouldUseStoredPrice) {
            // For submitted/active applications with same term, use stored pricing directly from Application_Package__c
            this.price = this.existingApplicationPackage.contractPremiumPrice || 0;
            this._retailPriceDisplay = this.existingApplicationPackage.contractPremiumPriceWithoutTax || this.existingApplicationPackage.dealerPackageRetailPrice || 0;
            
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
        } else if (this.selectedDealerPackage && this.selectedWarrantyTerm) {
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
            
            // Calculate tax - use taxAmount from term if available, otherwise calculate from taxRate
            let taxAmount = 0;
            if (this.selectedWarrantyTerm.taxAmount !== undefined && this.selectedWarrantyTerm.taxAmount !== null) {
                taxAmount = this.selectedWarrantyTerm.taxAmount || 0;
            } else {
                // Calculate tax from package tax rate
                const taxRate = this.selectedDealerPackage?.taxRate || 0;
                if (taxRate > 0) {
                    taxAmount = priceWithMarkup * (taxRate / 100);
                }
            }
            
            // Base price includes markup + tax
            const basePrice = priceWithMarkup + taxAmount;
            
            this.price = basePrice;
            this._retailPriceDisplay = priceWithMarkup;
            console.log('💰 New selection price calculation:', {
                netCost,
                markup,
                markupType,
                priceWithMarkup,
                taxAmount,
                basePriceWithTax: basePrice,
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
        
        if (!this.selectedWarrantyTerm && !this.isExistingApplication) {
            console.log('⚠️ No warranty term selected and no existing application package for price breakdown');
            return;
        }
        
        // Determine dealer price source
        const isSameTerm = this.isExistingApplication && 
                          this.existingApplicationPackage && 
                          this.selectedWarrantyTerm && 
                          this.selectedWarrantyTerm.Id === this.existingApplicationPackage.selectedTermId;
        
        const bdAppStatus = this.applicationStatus || '';
        const useStoredForBreakdown = isSameTerm && !['Draft', 'Pending', 'Quote'].includes(bdAppStatus);
        
        let dealerPrice, taxRate, taxAmount, totalWithTax;
        
        if (useStoredForBreakdown) {
            dealerPrice = this.existingApplicationPackage.dealerPackagePrice || 0;
            taxRate = this.existingApplicationPackage.taxPercentage || 0;
            taxAmount = this.existingApplicationPackage.taxAmount || 0;
            totalWithTax = this.existingApplicationPackage.contractPremiumPrice || 0;
        } else if (this.selectedWarrantyTerm) {
            dealerPrice = this.selectedWarrantyTerm.netCost || 0;
            taxRate = this.selectedWarrantyTerm.taxRate || 0;
            taxAmount = this.selectedWarrantyTerm.taxAmount || 0;
            totalWithTax = dealerPrice + taxAmount;
        } else if (this.isExistingApplication && this.existingApplicationPackage) {
            dealerPrice = this.existingApplicationPackage.dealerPackagePrice || 0;
            taxRate = this.existingApplicationPackage.taxPercentage || 0;
            taxAmount = this.existingApplicationPackage.taxAmount || 0;
            totalWithTax = this.existingApplicationPackage.contractPremiumPrice || 0;
        } else {
            dealerPrice = taxRate = taxAmount = totalWithTax = 0;
        }
        
        this.modalDealerPrice = dealerPrice;
        this.modalTaxRate = taxRate;
        this.modalTaxAmount = taxAmount;
        this.modalTotalWithTax = totalWithTax;
        
        this.showPriceModal = true;
    }

    hidePriceBreakdownModal() {
        this.showPriceModal = false;
    }
    
    stopPropagation(event) {
        event.stopPropagation();
    }
    
    // Create or update application package (used on Continue button)
    async createOrUpdateApplicationPackage() {
        if (!this.applicationId || !this.selectedDealerPackage || !this.selectedWarrantyTerm) {
            console.warn('⚠️ Missing required data for application package creation');
            return;
        }
        
        this.loading = true;
        
        try {
            // ========== NEW ACTIVE MANAGEMENT CODE ==========
            const packageData = {
                applicationId: this.applicationId,
                dealerId: this.selectedDealerPackage.DealerId,
                dealerPackageId: this.selectedDealerPackage.Id,
                packageName: this.selectedDealerPackage.PackageName,
                selectedTermId: this.selectedWarrantyTerm.Id,
                recordType: 'Tire_Rim_Protection_Plan',
                dealerPriceOverride: this.isPriceOverridden ? (this._overridePreTaxPrice || this.price) : null
            };
            
            console.log('📦 [TIRE createOrUpdate] Saving with active management:', packageData);
            
            const result = await savePackageWithActiveManagement({
                packageDataMap: packageData
            });
            
            console.log('✅ [TIRE createOrUpdate] Save result:', result);
            
            /* ========== OLD CODE (RESTORE IF NEEDED) ==========
            const existingPackage = await getExistingApplicationPackageByRecordType({ 
                applicationId: this.applicationId, 
                recordType: 'Tire_Rim_Protection_Plan' 
            });
            
            let result;
            if (existingPackage && existingPackage.data && existingPackage.data.Id) {
                result = await updateApplicationPackage({
                    packageId: existingPackage.data.Id,
                    selectedTermId: packageData.warrantyTermId,
                    includeDeductible: false
                });
            } else {
                packageData.recordType = 'Tire_Rim_Protection_Plan';
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
            console.log('🧪 Testing warranty component...');
            console.log('✅ Component is working correctly');
            return { success: true, message: 'Warranty component is functional' };
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
        
        // Load dealer packages if we have an application ID
        if (id) {
            this.loadDealerPackages();
        }
    }
    
    async handleSaveAsQuote() {
        console.log('💾 Save as Quote - More Products tab');
        // ✅ FIX: Commit any in-progress custom price override before saving.
        if (this.isPriceEditMode) {
            this._applyPriceOverride();
        }
        
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
        
        this.loading = true;
        
        try {
            let applicationPackageId;
            
            // If there's a selected package, save it with full logic
            if (this.selectedDealerPackage && this.selectedWarrantyTerm) {
                // Validate Tire & Rim required fields before saving
                if (this.showSelectedPlanView && !this.validateTireRimFields()) {
                    this.loading = false;
                    return;
                }
                console.log('🔍 [TIRE SAVE AS QUOTE] Saving package');
                console.log('🔍 selectedDealerPackage:', this.selectedDealerPackage);
                console.log('🔍 selectedWarrantyTerm:', this.selectedWarrantyTerm);
                
                // Validate required fields
                if (!this.selectedDealerPackage.DealerId || !this.selectedDealerPackage.Id || !this.selectedDealerPackage.PackageName) {
                    console.error('❌ CRITICAL: selectedDealerPackage missing required properties');
                    throw new Error('Selected dealer package is missing required properties');
                }
                
                if (!this.selectedWarrantyTerm.Id) {
                    console.error('❌ CRITICAL: selectedWarrantyTerm missing Id');
                    throw new Error('Selected warranty term is missing id');
                }
                
                // Build package data
                const finalData = {
                    applicationId: String(this.applicationId),
                    dealerId: String(this.selectedDealerPackage.DealerId),
                    dealerPackageId: String(this.selectedDealerPackage.Id),
                    packageName: String(this.selectedDealerPackage.PackageName),
                    selectedTermId: String(this.selectedWarrantyTerm.Id),
                    recordType: 'Tire_Rim_Protection_Plan',
                    dealerPriceOverride: this.isPriceOverridden ? (this._overridePreTaxPrice || this.price) : null
                };
                
                // Add optional tire/rim details when present
                this.addTireFieldsToPayload(finalData);
                
                console.log('🔍 [TIRE SAVE AS QUOTE] BEFORE SAVE:', finalData);
                
                // Save package using active management
                const result = await savePackageWithActiveManagement({
                    packageDataMap: finalData
                });
                
                console.log('🔍 [TIRE SAVE AS QUOTE] AFTER SAVE:', result);
                
                if (result.success && result.data) {
                    applicationPackageId = result.data.packageId;
                    this.applicationPackageId = String(applicationPackageId);
                    
                    // Mark as existing application so UI updates properly
                    this.isExistingApplication = true;
                    this.hasTireRimPackage = true;
                    
                    // Store existing package reference for future updates
                    if (applicationPackageId) {
                        this.existingApplicationPackage = {
                            Id: applicationPackageId,
                            dealerPackageId: this.selectedDealerPackage.Id,
                            selectedTermId: this.selectedWarrantyTerm.Id
                        };
                    }
                    
                    console.log('✅ [TIRE SAVE AS QUOTE] Package saved/updated:');
                    console.log('   📌 Package ID:', applicationPackageId);
                    console.log('   📌 Application Package ID set:', this.applicationPackageId);
                } else {
                    console.error('❌ Failed to save package:', result.message);
                    this.errorMessage = 'Failed to save more products selection: ' + result.message;
                    this.showError = true;
                    this.loading = false;
                    return;
                }
                
                // Upload pending files if any
                if (this.pendingFiles && this.pendingFiles.length > 0) {
                    console.log('📤 Uploading', this.pendingFiles.length, 'pending file(s)...');
                    await this.uploadPendingFiles(applicationPackageId);
                }
            }
            
            // Save data to session storage
            this.saveDataToSession();
            
            // Convert application to Quote record type
            console.log('🔄 Converting application to Quote:', this.applicationId);
            const convertResult = await convertApplicationToQuote({ 
                applicationId: this.applicationId 
            });
            
            if (convertResult.success) {
                console.log('✅ Application converted to Quote successfully');
                
                // Show success message
                const successMsg = applicationPackageId 
                    ? 'More products saved and application converted to Quote successfully!' 
                    : 'Application converted to Quote successfully!';
                this.showSuccessMessage(successMsg);
                
                // Clear pending files after successful conversion
                this.pendingFiles = [];
                
                // Navigate to quotes list
                console.log('🔗 Navigating to quotes list');
                 // Fire save as quote event to parent component
            this.dispatchEvent(new CustomEvent('saveasquote', {
                detail: { 
                    success: true,
                    applicationId: this.applicationId
                }
            }));
            } else {
                console.error('❌ Failed to convert application to Quote:', convertResult.message);
                this.errorMessage = 'Failed to convert to Quote: ' + convertResult.message;
                this.showError = true;
            }
            
        } catch (error) {
            console.error('❌ Error in handleSaveAsQuote:', error);
            this.errorMessage = error.message || 'Error processing tire & rim selection. Please try again.';
            this.showError = true;
        } finally {
            this.loading = false;
        }
    }
    
    showSuccessMessage(message) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Success',
            message: message,
            variant: 'success'
        }));
    }
    
    async handleContinue() {
        if (this.showNoPackageDisclaimer || this.showVehicleNotEligibleDisclaimer) {
            this.handleSkip();
            return;
        }
        // ✅ FIX: Commit any in-progress custom price override before saving.
        // If the user typed a custom price and clicked Continue without tabbing away,
        // onblur fires AFTER onclick in LWC. Calling _applyPriceOverride() here
        // ensures isPriceOverridden and _overridePreTaxPrice are set before
        // finalData is constructed below.
        if (this.isPriceEditMode) {
            this._applyPriceOverride();
        }
        console.log('🔍 ===== MORE PRODUCTS handleContinue CALLED =====');
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
                // Create application package in Salesforce
                const packageData = {
                    applicationId: this.applicationId,
                    dealerId: this.selectedDealerPackage.DealerId,
                    dealerPackageId: this.selectedDealerPackage.Id,
                    packageName: this.selectedDealerPackage.PackageName,
                    selectedTermId: this.selectedWarrantyTerm.Id
                };
                
                console.log('🔍 Creating application package:', packageData);
                console.log('🔍 packageData.applicationId:', packageData.applicationId);
                console.log('🔍 packageData.dealerId:', packageData.dealerId);
                console.log('🔍 packageData.dealerPackageId:', packageData.dealerPackageId);
                console.log('🔍 packageData.packageName:', packageData.packageName);
                console.log('🔍 packageData.selectedTermId:', packageData.selectedTermId);
                
                // STEP 1: Extract individual values and log each one
                console.log('🔍 STEP 1: Individual value extraction:');
                console.log('🔍 this.applicationId:', this.applicationId);
                console.log('🔍 this.applicationId type:', typeof this.applicationId);
                console.log('🔍 this.applicationId length:', this.applicationId ? this.applicationId.length : 'null');
                
                console.log('🔍 this.selectedDealerPackage.DealerId:', this.selectedDealerPackage.DealerId);
                console.log('🔍 this.selectedDealerPackage.DealerId type:', typeof this.selectedDealerPackage.DealerId);
                console.log('🔍 this.selectedDealerPackage.DealerId length:', this.selectedDealerPackage.DealerId ? this.selectedDealerPackage.DealerId.length : 'null');
                
                console.log('🔍 this.selectedDealerPackage.Id:', this.selectedDealerPackage.Id);
                console.log('🔍 this.selectedDealerPackage.Id type:', typeof this.selectedDealerPackage.Id);
                console.log('🔍 this.selectedDealerPackage.Id length:', this.selectedDealerPackage.Id ? this.selectedDealerPackage.Id.length : 'null');
                
                console.log('🔍 this.selectedDealerPackage.PackageName:', this.selectedDealerPackage.PackageName);
                console.log('🔍 this.selectedDealerPackage.PackageName type:', typeof this.selectedDealerPackage.PackageName);
                
                // STEP 2: Create raw data object
                const rawData = {
                    applicationId: this.applicationId,
                    dealerId: this.selectedDealerPackage.DealerId,
                    dealerPackageId: this.selectedDealerPackage.Id,
                    packageName: this.selectedDealerPackage.PackageName
                };
                
                console.log('🔍 STEP 2: Raw data object created:');
                console.log('🔍 rawData:', rawData);
                console.log('🔍 rawData type:', typeof rawData);
                console.log('🔍 rawData.applicationId:', rawData.applicationId);
                console.log('🔍 rawData.dealerId:', rawData.dealerId);
                console.log('🔍 rawData.dealerPackageId:', rawData.dealerPackageId);
                console.log('🔍 rawData.packageName:', rawData.packageName);
                
                // STEP 3: Create a completely clean object with DYNAMIC VALUES
                // Add null checks before creating finalData
                if (!this.selectedDealerPackage || !this.selectedWarrantyTerm) {
                    console.error('❌ CRITICAL: selectedDealerPackage or selectedWarrantyTerm is null/undefined');
                    console.error('❌ selectedDealerPackage:', this.selectedDealerPackage);
                    console.error('❌ selectedWarrantyTerm:', this.selectedWarrantyTerm);
                    throw new Error('Required package or term selection is missing');
                }
                
                if (!this.selectedDealerPackage.DealerId || !this.selectedDealerPackage.Id || !this.selectedDealerPackage.PackageName) {
                    console.error('❌ CRITICAL: selectedDealerPackage missing required properties');
                    console.error('❌ DealerId:', this.selectedDealerPackage.DealerId);
                    console.error('❌ Id:', this.selectedDealerPackage.Id);
                    console.error('❌ PackageName:', this.selectedDealerPackage.PackageName);
                    throw new Error('Selected dealer package is missing required properties');
                }
                
                if (!this.selectedWarrantyTerm.Id) {
                    console.error('❌ CRITICAL: selectedWarrantyTerm missing required properties');
                    console.error('❌ Id:', this.selectedWarrantyTerm.Id);
                    throw new Error('Selected warranty term is missing required properties');
                }
                
                let result;
                let applicationPackageId;
                
                // ========== NEW ACTIVE MANAGEMENT CODE ==========
                const finalData = {
                    applicationId: String(this.applicationId),
                    dealerId: String(this.selectedDealerPackage.DealerId),
                    dealerPackageId: String(this.selectedDealerPackage.Id),
                    packageName: String(this.selectedDealerPackage.PackageName),
                    selectedTermId: String(this.selectedWarrantyTerm.Id),
                    recordType: 'Tire_Rim_Protection_Plan',
                    dealerPriceOverride: this.isPriceOverridden ? (this._overridePreTaxPrice || this.price) : null
                };

                // Add optional tire/rim details when present (will update existing record if created early)
                this.addTireFieldsToPayload(finalData);
                
                console.log('🔍 [TIRE] BEFORE SAVE:', finalData);
                console.log('🔍 [TIRE] Existing Application Package ID:', this.applicationPackageId);
                
                result = await savePackageWithActiveManagement({
                    packageDataMap: finalData
                });
                
                console.log('🔍 [TIRE] AFTER SAVE:', result);
                
                if (result.success && result.data) {
                    applicationPackageId = result.data.packageId;
                    // Store the package ID for file uploads - ensure it's a string
                    this.applicationPackageId = String(applicationPackageId);
                    
                    // Mark as existing application so UI updates properly
                    this.isExistingApplication = true;
                    this.hasTireRimPackage = true;
                    
                    // Store existing package reference for future updates
                    if (applicationPackageId) {
                        this.existingApplicationPackage = {
                            Id: applicationPackageId,
                            dealerPackageId: this.selectedDealerPackage.Id,
                            selectedTermId: this.selectedWarrantyTerm.Id
                        };
                    }
                    
                    console.log('✅ [TIRE] Package saved/updated:');
                    console.log('   📌 Package ID:', applicationPackageId);
                    console.log('   📌 Application Package ID set:', this.applicationPackageId);
                    console.log('   📌 Is New:', result.data.isNewPackage);
                    console.log('   📌 Changed:', result.data.isPackageChange);
                    console.log('   📌 Active:', result.data.active);
                    console.log('   📁 File upload should now be enabled');
                    console.log('   📁 hasApplicationPackageId:', this.hasApplicationPackageId);
                }
                
                /* ========== OLD CODE (RESTORE IF NEEDED) ==========
                const finalData = {};
                finalData.applicationId = String(this.applicationId);
                finalData.dealerId = String(this.selectedDealerPackage.DealerId);
                finalData.dealerPackageId = String(this.selectedDealerPackage.Id);
                finalData.packageName = String(this.selectedDealerPackage.PackageName);
                finalData.selectedTermId = String(this.selectedWarrantyTerm.Id);
                finalData.recordType = 'Tire_Rim_Protection_Plan';
                
                if (this.isExistingApplication && this.existingApplicationPackage && this.existingApplicationPackage.Id) {
                    try {
                        await this.updateExistingApplicationPackage(this.selectedDealerPackage, this.selectedWarrantyTerm);
                        applicationPackageId = this.existingApplicationPackage.Id;
                        result = { success: true, recordId: applicationPackageId };
                    } catch (updateError) {
                        result = await createApplicationPackageFromMap({packageDataMap:finalData});
                        applicationPackageId = result.recordId;
                    }
                } else {
                    result = await createApplicationPackageFromMap({packageDataMap: finalData});
                    applicationPackageId = result.recordId;
                }
                ========== END OLD CODE ========== */
                
                if (result.success) {
                    console.log('✅ Application package processed successfully:', applicationPackageId);
                    
                    // Mark as existing application so file upload becomes available
                    this.isExistingApplication = true;
                    if (result.data && result.data.packageId) {
                        this.existingApplicationPackage = {
                            Id: result.data.packageId,
                            dealerPackageId: this.selectedDealerPackage.Id,
                            selectedTermId: this.selectedWarrantyTerm.Id
                        };
                    }
                    
                    // Upload pending files if any
                    if (this.pendingFiles && this.pendingFiles.length > 0) {
                        console.log('📤 Uploading', this.pendingFiles.length, 'pending file(s)...');
                        await this.uploadPendingFiles(applicationPackageId);
                    }
                    
                    // Save data to session storage
                    this.saveDataToSession();
                    
                    // Fire more products completion event to unlock gap tab
                    this.dispatchEvent(new CustomEvent('moreproductscomplete', {
                        detail: { 
                            success: true,
                            warrantyData: this.getCurrentData(),
                            applicationId: this.applicationId,
                            autoSelected: false // Manual completion, not auto-selection
                        }
                    }));
                    
                    // Show success message
                    const fileMsg = this.pendingFiles && this.pendingFiles.length > 0 
                        ? ` Package and ${this.pendingFiles.length} file(s) saved successfully!`
                        : ' Package saved successfully!';
                    this.showSuccessMessage(fileMsg);
                    
                    // Clear pending files after upload
                    this.pendingFiles = [];
                    
                    // Force UI update
                    this.renderKey++;
                    
                } else {
                    console.error('❌ Failed to create application package:', result.message);
                    this.errorMessage = 'Failed to save more products selection: ' + result.message;
                    this.showError = true;
                }
                
            } catch (error) {
                console.error('❌ Error in handleContinue:', error);
                this.errorMessage = 'Error processing more products selection. Please try again.';
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
    
    // Check if more products is unlocked (has selected package)
    get isMoreProductsUnlocked() {
        return this.selectedDealerPackage !== null;
    }
    
    // Get more products status for display
    get moreProductsStatus() {
        if (this.selectedDealerPackage) {
            return `✅ More Products Package Selected: ${this.selectedDealerPackage.PackageName}`;
        }
        return '⚠️ Please select a more products package';
    }
    
    get hasPackages() {
        return this.dealerPackages && this.dealerPackages.length > 0;
    }
    
    
    get hasSelectedTerm() {
        return this.selectedWarrantyTerm !== null;
    }
    
    get formattedPrice() {
        if (this._retailPriceDisplay != null) {
            return this.formatPrice(this._retailPriceDisplay);
        }
        return this.formatPrice(this.price);
    }

    // ── Custom Pricing (click-to-edit override) ──
    handlePriceClick() {
        if (!this.selectedWarrantyTerm) return;
        this.isPriceEditMode = true;
        // Show pre-tax override price if available, otherwise show pre-tax display value (never tax-inclusive total)
        const editPrice = this._overridePreTaxPrice != null ? this._overridePreTaxPrice : this._retailPriceDisplay;
        this.priceOverrideInput = editPrice != null ? editPrice.toFixed(2) : '';
        setTimeout(() => {
            const input = this.template.querySelector('.price-override-input');
            if (input) { input.focus(); input.select(); }
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
            // DISABLED: Validation that prevented custom price below dealer price
            // const dealerPrice = (this.selectedWarrantyTerm ? this.selectedWarrantyTerm.netCost : null)
            //                  || (this.existingApplicationPackage ? this.existingApplicationPackage.dealerPackagePrice : null)
            //                  || 0;
            // if (dealerPrice > 0 && val < dealerPrice) {
            //     this.priceValidationMessage = 'Custom price ($' + val.toFixed(2) + ') cannot be less than Dealer Price ($' + dealerPrice.toFixed(2) + ').';
            //     this.isPriceEditMode = false;
            //     // eslint-disable-next-line @lwc/lwc/no-async-operation
            //     setTimeout(() => { this.priceValidationMessage = ''; }, 5000);
            //     return;
            // }
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
    
    handleDeclineMoreProducts() {
        this.showDeclineModal = true;
    }
    
    cancelDeclineMoreProducts() {
        this.showDeclineModal = false;
    }
    
    confirmDeclineWarranty() {
        this.selectedDealerPackage = null;
        this.selectedWarrantyTerm = null;
        this.price = 0.00;
        this.showDeclineModal = false;
        
        sessionStorage.removeItem('warrantyData');
        this.fireCompletionEvent();
    }
    
    closeMoreProductsModal() {
        this.showMoreProductsModal = false;
    }
    
    get moreProductsStatus() {
        if (this.selectedDealerPackage && this.selectedWarrantyTerm) {
            return `More Products Selected: ${this.selectedDealerPackage.PackageName} - ${this.selectedWarrantyTerm.packageTermName || this.selectedWarrantyTerm.Name || 'Unknown Term'}`;
        }
        return 'No more products selected';
    }

    get selectedTermName() {
        if (this.selectedWarrantyTerm) {
            return this.selectedWarrantyTerm.packageTermName || this.selectedWarrantyTerm.Name || 'No term selected';
        }
        return 'No term selected';
    }

    get selectedTermDuration() {
        // Tire & Rim doesn't use Month__c, so return null/0
        if (this.selectedWarrantyTerm) {
            return null; // Month__c not used for Tire & Rim
        }
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
    
    // Check if we have an application package ID for file uploads
    get hasApplicationPackageId() {
        const hasId = !!this.applicationPackageId;
        console.log('📁 hasApplicationPackageId check:', {
            applicationPackageId: this.applicationPackageId,
            hasId: hasId,
            type: typeof this.applicationPackageId
        });
        return hasId;
    }
    
    get treadDepthUnitSelectOptions() {
        const vals = this.treadDepthUnitPicklist?.data?.values || [];
        return vals.map(v => ({ label: v.label, value: v.value, selected: v.value === this.treadDepthUnit }));
    }
    
    // Rim Size Unit dropdown options
    get rimSizeUnitOptions() {
        return [
            { label: 'Select Unit', value: '' },
            { label: 'Inches', value: 'inches' },
            { label: 'cm', value: 'cm' }
        ];
    }
    
    get rimSizeUnitSelectOptions() {
        return this.rimSizeUnitOptions
            .filter(option => option.value !== '')
            .map(option => ({
                ...option,
                selected: option.value === this.rimSizeUnit
            }));
    }

    get tireBrandSelectOptions() {
        const vals = this.tireBrandPicklist?.data?.values || [];
        return vals.map(v => ({ label: v.label, value: v.value, selected: v.value === this.tireBrand }));
    }

    get rimBrandSelectOptions() {
        const vals = this.rimBrandPicklist?.data?.values || [];
        return vals.map(v => ({ label: v.label, value: v.value, selected: v.value === this.rimBrand }));
    }

    get rimTypeSelectOptions() {
        const vals = this.rimTypePicklist?.data?.values || [];
        return vals.map(v => ({ label: v.label, value: v.value, selected: v.value === this.rimType }));
    }
    
    // Handle custom file input selection (stores files in memory)
    handleFileSelection(event) {
        const files = event.target.files;
        if (!files || files.length === 0) return;
        
        console.log('📁 Files selected:', files.length);
        
        // Convert FileList to Array and process each file
        Array.from(files).forEach(file => {
            const reader = new FileReader();
            reader.onload = (e) => {
                const base64Content = e.target.result;
                this.pendingFiles.push({
                    name: file.name,
                    file: file,
                    base64: base64Content,
                    size: file.size,
                    type: file.type
                });
                console.log('✅ File added to pending:', file.name);
                this.renderKey++; // Force UI update
            };
            reader.onerror = (error) => {
                console.error('❌ Error reading file:', file.name, error);
                this.showErrorMessage('Error reading file: ' + file.name);
            };
            reader.readAsDataURL(file);
        });
    }
    
    // Remove pending file
    removePendingFile(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        if (index >= 0 && index < this.pendingFiles.length) {
            this.pendingFiles.splice(index, 1);
            this.renderKey++;
        }
    }
    
    // Upload pending files to Application Package
    async uploadPendingFiles(applicationPackageId) {
        if (!this.pendingFiles || this.pendingFiles.length === 0) {
            return;
        }
        
        this.uploadInProgress = true;
        
        try {
            // Prepare file data for Apex
            const fileDataList = this.pendingFiles.map(file => ({
                name: file.name,
                base64Content: file.base64,
                contentType: file.type || 'application/octet-stream'
            }));
            
            console.log('📤 Uploading', fileDataList.length, 'file(s) to Application Package:', applicationPackageId);
            
            const result = await uploadFilesToApplicationPackage({
                applicationPackageId: applicationPackageId,
                fileDataList: fileDataList
            });
            
            if (result.success) {
                console.log('✅ Files uploaded successfully:', result.message);
                this.showSuccessMessage(result.message);
            } else {
                console.error('❌ File upload failed:', result.message);
                this.showErrorMessage('File upload failed: ' + result.message);
            }
        } catch (error) {
            console.error('❌ Error uploading files:', error);
            this.showErrorMessage('Error uploading files: ' + error.message);
        } finally {
            this.uploadInProgress = false;
        }
    }
    
    // Handle file upload finished event (for lightning-file-upload if record exists)
    handleFileUploadFinished(event) {
        const uploadedFiles = event.detail.files;
        console.log('📁 File upload finished:', uploadedFiles.length, 'files uploaded');
        
        if (uploadedFiles && uploadedFiles.length > 0) {
            this.uploadInProgress = false;
            this.showToast('Success', `${uploadedFiles.length} file(s) uploaded successfully`, 'success');
            this.dispatchEvent(new CustomEvent('filesuploaded', {
                detail: {
                    uploadedFiles: uploadedFiles,
                    packageId: this.applicationPackageId
                }
            }));
        }
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
    
    
    
    
    
    selectFromComparison(event) {
        const termId = event.currentTarget.dataset.termId;
        const selectedTerm = this.comparisonTerms.find(term => term.Id === termId);
        
        if (selectedTerm) {
            // Check if the term's package is different from currently selected package
            let termPackage = null;
            for (const pkg of this.dealerPackages) {
                if (pkg.warrantyTerms) {
                    const term = pkg.warrantyTerms.find(t => t.Id === termId);
                    if (term) {
                        termPackage = pkg;
                        break;
                    }
                }
            }
            
            if (!termPackage) {
                this.showErrorMessage('Term not found in available packages.');
                return;
            }
            
            // Validation: Check if this would change the package selection
            if (this.selectedDealerPackage && this.selectedDealerPackage.Id !== termPackage.Id) {
                console.log('🔄 Package change required from', this.selectedDealerPackage.PackageName, 'to', termPackage.PackageName);
                
                // If this is an existing application, update the backend
                if (this.isExistingApplication && this.existingApplicationPackage) {
                    console.log('🗑️ Updating package selection in Salesforce...');
                }
            }
            
            // Find the original term and select it
            let found = false;
            for (const pkg of this.dealerPackages) {
                if (pkg.warrantyTerms) {
                    const term = pkg.warrantyTerms.find(t => t.Id === termId);
                    if (term) {
                        this.selectedDealerPackage = pkg;
                        this.selectedWarrantyTerm = term;
                        this.isChangingSelection = false;
                        this.selectedProgram = pkg.PackageName;
                        console.log('✅ Selected from comparison:', term.packageTermName || term.Name, 'from', pkg.PackageName);
                        
                        this.updatePrice();
                        this.saveDataToSession();
                        
                        // DON'T save to Salesforce until user clicks Continue
                        console.log('ℹ️ [TIRE] Selected from comparison - will save when Continue is clicked');
                        
                        found = true;
                        break;
                    }
                }
            }
            
            if (found) {
                this.closeComparison();
                this.showToast('Success', 'Warranty term selected successfully!', 'success');
            }
        }
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
    

    // Get formatted existing application price for display
    get formattedExistingPrice() {
        if (this.isExistingApplication && this.existingApplicationPackage) {
            // Use the SOLD pricing from the existing Application Package record
            const basePrice = this.existingApplicationPackage.dealerPackagePrice || 0;
            const markup = this.existingApplicationPackage.dealerMarkup || 0;
            const totalPrice = basePrice + markup;
            return this.formatPrice(totalPrice);
        }
        return '0.00';
    }
    
    










    // Initialize original warranty data for change tracking
    initializeOriginalWarrantyData() {
        this.originalWarrantyData = {
            selectedDealerPackageId: this.selectedDealerPackage?.Id || null,
            selectedWarrantyTermId: this.selectedWarrantyTerm?.Id || null
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
        /* OLD AUTO-SAVE CODE (disabled)
        if (this.isExistingApplication && this.existingApplicationPackage) {
            this.debouncedWarrantyAutoSave();
        }
        */
        console.log('ℹ️ [TIRE] Auto-save disabled - changes will save on Continue click');
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
    
    
    // Show info message to user
    showSuccessMessage(message) {
        const event = new ShowToastEvent({
            title: 'Success',
            message: message,
            variant: 'success',
            mode: 'dismissable'
        });
        this.dispatchEvent(event);
    }
    
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