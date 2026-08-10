import { LightningElement, track, api, wire } from 'lwc';
import saveVehicleData from '@salesforce/apex/DealerPortalController.saveVehicleData';
// FIXED: Use correct parameter format (object wrapper)
import loadVehicleData from '@salesforce/apex/DealerPortalController.loadVehicleData';
import updateVehicleFieldsSelective from '@salesforce/apex/DealerPortalController.updateVehicleFieldsSelective';
import decodeVin from '@salesforce/apex/DealerPortalController.decodeVin';
import getDealershipInfo from '@salesforce/apex/DealerPortalController.getDealershipInfo';
import getDealerContacts from '@salesforce/apex/DealerPortalController.getDealerContacts';
import getVehicleWarrantyPicklists from '@salesforce/apex/DealerPortalController.getVehicleWarrantyPicklists';
import checkDuplicateVIN from '@salesforce/apex/DealerPortalController.checkDuplicateVIN';

// Powersports brand tier detection constants
const PREMIUM_MAKES = ['harley-davidson','harley davidson','bmw motorrad','bmw','ducati','triumph','indian','can-am spyder','can-am outlander','yamaha raptor','polaris sportsman','can-am defender','polaris ranger','yamaha viking','honda pioneer','ski-doo','polaris switchback','polaris indy','arctic cat'];
const EXOTIC_MAKES = ['ktm','aprilia','mv agusta','ducati panigale','bimota','polaris rzr','can-am maverick','yamaha yxz','krx turbo','ski-doo summit turbo','polaris matryx','arctic cat m alpha'];

function deriveBrandTier(make) {
    if (!make) return 'Standard';
    const m = make.toLowerCase();
    if (EXOTIC_MAKES.some(x => m.includes(x))) return 'Exotic';
    if (PREMIUM_MAKES.some(x => m.includes(x))) return 'Premium';
    return 'Standard';
}

export default class DealerPortalVehicle extends LightningElement {
    _applicationId;
    @api isLocked = false;
    @track loading = false;
    @track errorMessage = '';
    @track showError = false;
    @track successMessage = '';
    @track showSuccess = false;
    @track showMoreInfoModal = false;
    @track additionalInfoSections = [];
    @track hasAdditionalInfo = false;
    @track hasVehicleData = false;
    @track additionalVehicleData = null;
    @track rawJsonResponse = null; // Store raw JSON response from API

    // Powersports state
    @track vehicleCategory = '';
    @track vehicleSubType = '';
    @track isPowersports = false;
    @track powersportsModalData = null;

    // VIN decode status
    @track vinDecodeSuccess = false;
    @track vinDecodeWarning = false;

    // Duplicate VIN modal
    @track showDuplicateVinModal = false;
    @track duplicateVinRecords = [];
    @track selectedDuplicateId = '';
    @track isCrossDealerVin = false;
    @track existingVehicleData = null;
    @track showDuplicateSubList = false;
    
    // Manufacturer warranty section toggle - start expanded to match image
    @track showManufacturerWarranty = true;
    @track manufacturerWarrantyTypeOptions = [{ label: '--None--', value: '' }];
    @track warrantyTermOptions = [{ label: '--None--', value: '' }];

    // Getter for field disabled state based on lock status
    get fieldDisabled() {
        return this.isLocked;
    }

    get isNotPowersports() {
        return !this.isPowersports;
    }
    
    get isPremiumBrandTier() {
        const tier = this.vehicleData && this.vehicleData.brandTier;
        return tier === 'Premium' || tier === 'Exotic';
    }
    
    // Getters for warranty fields that combine lock status with warranty logic
    get manufacturerWarrantyTypeDisabled() {
        return this.fieldDisabled;
    }
    
    get warrantyInServiceDateDisabled() {
        return this.fieldDisabled;
    }
    
    // Getter for button disabled state
    get isVehicleDataDisabled() {
        // Enable button if we have additional vehicle data (from VIN decode)
        return !this.additionalVehicleData || Object.keys(this.additionalVehicleData || {}).length === 0;
    }
    
    // Getter for warranty section icon - shows down arrow when expanded (matching image)
    get warrantySectionIcon() {
        return 'utility:chevrondown';
    }
    
    // Getter for warranty toggle icon class
    get warrantyToggleIconClass() {
        return this.showManufacturerWarranty ? 'warranty-toggle-icon open' : 'warranty-toggle-icon closed';
    }
    
    // Getters for conditional required state of manufacturer warranty fields
    // All three fields become required once the user selects a Manufacturer Warranty Type
    get isManufacturerWarrantyTypeRequired() {
        return !!(this.vehicleData && this.vehicleData.manufacturerWarrantyType);
    }

    get isWarrantyTermRequired() {
        return !!(this.vehicleData && this.vehicleData.manufacturerWarrantyType);
    }

    get isWarrantyInServiceDateRequired() {
        return !!(this.vehicleData && this.vehicleData.manufacturerWarrantyType);
    }

    // Getter for manufacturer warranty section title
    get manufacturerWarrantySectionTitle() {
        if (this.vehicleData && this.vehicleData.manufacturerWarrantyType) {
            return 'MANUFACTURER WARRANTY (REQUIRED)';
        }
        return 'MANUFACTURER WARRANTY (OPTIONAL)';
    }
    
    @track vehicleData = {
        stockNumber: '',
        vin: '',
        vehicleIdentificationNumberVIN: '',
        year: '',
        make: '',
        model: '',
        trim: '',
        dateSold: '',
        purchasePrice: '',
        isCommercial: false,
        isBrandedRebuilt: false,
        inServiceDate: '',
        odometerReading: '',
        odometerUnit: 'KM',
        commercialUse: 'NON-COMMERCIAL',
        // New Vehicle Details fields
        engine: '',
        transmission: '',
        fuelType: '',
        driveType: '',
        bodyStyle: '',
        color: '',
        gvwr: '',
        // Manufacturer Warranty fields
        manufacturerWarrantyType: '',
        warrantyTerm: '',
        warrantyInServiceDate: '',
        deferralOption: false,
        // Delivery Date
        deliveryDate: '',
        lienHolder: '',
        // Usage Type
        usageType: 'Personal Use',
        // Powersports fields
        vehicleCategory: '',
        vehicleSubType: '',
        engineCC: '',
        coolingType: '',
        hoursUsage: '',
        vehicleClass: ''
    };
    
    // Application data for dealer comments and dealership info
    @track applicationData = {
        dealerCommentsNotes: '',
        showCommentsOnPrint: false,
        dealershipName: '',
        dealershipAddress: '',
        cityProvincePostal: '',
        salesRepresentative: '',
        dealerSalesId: ''
    };

    get dealershipAddressDisplay() {
        const address = this.applicationData.dealershipAddress || '';
        const city = this.applicationData.cityProvincePostal || '';
        if (address && city) {
            return `${address}\n${city}`;
        }
        return address || city || '';
    }
    
    // Store dealer account ID and contacts
    @track dealerAccountId = '';
    @track dealerContacts = [];
    @track currentUserContactId = '';
    
    @track vehicleId = '';
    @track isNewRecord = true;
    @track originalVehicleData = {};
    @track changedFields = new Set();
    @track autoSaveTimeout;
    
    // Getter and setter for applicationId to handle changes
    @api
    get applicationId() {
        return this._applicationId;
    }
    
    set applicationId(value) {
        console.log('🚚 Vehicle component ApplicationId setter called with value:', value);
        console.log('🚚 Current _applicationId:', this._applicationId);
        
        // Only process if the value is actually different
        if (this._applicationId !== value) {
            console.log('🚚 ApplicationId changed from', this._applicationId, 'to', value);
            this._applicationId = value;
            
            // Clear existing data when application changes
            if (value) {
                this.clearVehicleData();
                this.loadVehicleData();
            }
        } else {
            console.log('🚚 ApplicationId unchanged, no action needed');
            return; // Exit early to prevent any processing
        }
    }
    
    // Method to clear vehicle data for new application
    clearVehicleData() {
        console.log('🧹 Clearing vehicle data for new application');
        
        // Reset all form fields to empty/default values
        this.vehicleData = {
            stockNumber: '',
            vin: '',
            vehicleIdentificationNumberVIN: '',
            year: '',
            make: '',
            model: '',
            trim: '',
            dateSold: '',
            purchasePrice: '',
            isCommercial: false,
            isBrandedRebuilt: false,
            inServiceDate: '',
            odometerReading: '',
            odometerUnit: 'KM',
            commercialUse: 'NON-COMMERCIAL',
            engine: '',
            transmission: '',
            fuelType: '',
            driveType: '',
            bodyStyle: '',
            color: '',
            gvwr: '',
            manufacturerWarrantyType: '',
            warrantyTerm: '',
            warrantyInServiceDate: '',
            deferralOption: false,
            deliveryDate: '',
            lienHolder: '',
            usageType: 'Personal Use',
            vehicleCategory: '',
            vehicleSubType: '',
            engineCC: '',
            coolingType: '',
            hoursUsage: '',
            vehicleClass: ''
        };

        // Reset application data
        this.applicationData = {
            dealerCommentsNotes: '',
            showCommentsOnPrint: false,
            dealershipName: '',
            dealershipAddress: '',
            cityProvincePostal: '',
            salesRepresentative: '',
            dealerSalesId: ''
        };
        
        // Reset VIN decode status
        this.vinDecodeSuccess = false;
        this.vinDecodeWarning = false;
        this.showManufacturerWarranty = false;

        // Reset Powersports state
        this.vehicleCategory = '';
        this.vehicleSubType = '';
        this.isPowersports = false;
        this.powersportsModalData = null;
        
        // Reset component state
        this.vehicleId = '';
        this.isNewRecord = true;
        this.showError = false;
        this.errorMessage = '';
        
        // Clear session storage for this application
        if (this._applicationId) {
            sessionStorage.removeItem(`vehicleData_${this._applicationId}`);
            sessionStorage.removeItem(`vehicleId_${this._applicationId}`);
            sessionStorage.removeItem(`isNewRecord_${this._applicationId}`);
            console.log('🧹 Cleared session storage for application:', this._applicationId);
        }
        
        // Also clear global session storage to prevent data mixing
        sessionStorage.removeItem('vehicleData');
        sessionStorage.removeItem('vehicleId');
        sessionStorage.removeItem('isNewRecord');
        
        console.log('🧹 Vehicle data completely cleared');
        console.log('🧹 New vehicleData object:', this.vehicleData);
    }
    
    // Method to ensure vehicleData is always properly initialized
    ensureVehicleDataInitialized() {
        if (!this.vehicleData) {
            console.log('🔄 Re-initializing vehicleData as it was null/undefined');
            this.vehicleData = {
                stockNumber: '',
                vin: '',
                vehicleIdentificationNumberVIN: '',
                year: '',
                make: '',
                model: '',
                trim: '',
                dateSold: '',
                purchasePrice: '',
                isCommercial: false,
                isBrandedRebuilt: false,
                inServiceDate: '',
                odometerReading: '',
                odometerUnit: 'KM',
                commercialUse: 'NON-COMMERCIAL'
            };
        }
    }
    
    // Method to check if user has entered critical required data
    hasUserEnteredData() {
        if (!this.vehicleData) return false;
        
        const criticalFields = ['vin', 'year', 'make', 'model'];
        return criticalFields.every(field => {
            const value = this.vehicleData[field];
            const hasValue = value !== '' && value !== null && value !== undefined;
            console.log(`🔍 User input check - ${field}: "${value}" (hasValue: ${hasValue})`);
            return hasValue;
        });
    }
    
    /**
     * Store application ID in session storage to pass to Apex
     * This bypasses the String parameter serialization bug
     */
    /**
     * Create a hash from application ID for integer parameter passing
     */
    hashApplicationId(applicationId) {
        // Simple hash function to convert application ID to integer
        let hash = 0;
        for (let i = 0; i < applicationId.length; i++) {
            const char = applicationId.charCodeAt(i);
            hash = ((hash << 5) - hash) + char;
            hash = hash & hash; // Convert to 32-bit integer
        }
        return Math.abs(hash);
    }

    storeApplicationIdInSession(applicationId) {
        console.log('💾 Storing applicationId in session storage:', applicationId);
        
        // Store in browser session storage
        sessionStorage.setItem('currentApplicationId', applicationId);
        
        // Store the hash mapping for Apex to use
        const hash = this.hashApplicationId(applicationId);
        sessionStorage.setItem('appIdHash_' + hash, applicationId);
        
        console.log('💾 Application ID stored with hash:', hash);
    }

    // SCALABLE SOLUTION: Works for unlimited applications using session storage
    async loadVehicleData() {
        if (!this._applicationId) {
            console.log('No applicationId provided, skipping data load');
            return;
        }
        
        console.log('Loading vehicle data for application:', this._applicationId);
        this.loading = true;
        
        try {
            // Load vehicle data using the correct parameter format
            console.log('📥 Loading vehicle data for application:', this._applicationId);
            
            // Call Apex with object-wrapped parameter
            const result = await loadVehicleData({ applicationId: this._applicationId });
        
            if (result.success && result.data) {
                const vehicleData = result.data;
                
                // Set vehicle ID from Apex response
                if (result.recordId) {
                    this.vehicleId = result.recordId;
                    this.isNewRecord = false;
                } else {
                    this.isNewRecord = true;
                }
                
                // Map the DTO fields to our local vehicleData object
                const businessCommercialUse = vehicleData.businessCommercialUse || false;
                const loadedCategory = vehicleData.vehicleCategory || '';
                this.vehicleCategory = loadedCategory;
                this.vehicleSubType = vehicleData.vehicleSubType || '';
                this.isPowersports = (loadedCategory === 'Powersports');
                this.vehicleData = {
                    stockNumber: vehicleData.stockNumber || '',
                    vin: vehicleData.vin || '',
                    vehicleIdentificationNumberVIN: vehicleData.vehicleIdentificationNumberVIN || '',
                    year: vehicleData.year || '',
                    make: vehicleData.make || '',
                    model: vehicleData.model || '',
                    trim: vehicleData.trim || '',
                    dateSold: vehicleData.dateVehicleSold || '',
                    purchasePrice: vehicleData.vehiclePurchasePrice || '',
                    isCommercial: businessCommercialUse,
                    usageType: vehicleData.usageType || (businessCommercialUse ? 'Commercial/Business Use' : 'Personal Use'),
                    commercialVehicleType: vehicleData.commercialVehicleType || '',
                    isBrandedRebuilt: vehicleData.brandedRebuilt || false,
                    inServiceDate: vehicleData.inServiceDate || '',
                    odometerReading: vehicleData.odometer || '',
                    odometerUnit: vehicleData.odometerUnit || 'KM',
                    commercialUse: vehicleData.typeOfCommercialUse || 'NON-COMMERCIAL',
                    // New Vehicle Details fields
                    engine: vehicleData.engine || '',
                    transmission: vehicleData.transmission || '',
                    fuelType: vehicleData.fuelType || '',
                    driveType: vehicleData.driveType || '',
                    bodyStyle: vehicleData.bodyStyle || '',
                    color: vehicleData.color || '',
                    gvwr: vehicleData.gvwr || '',
                    // Manufacturer Warranty fields
                    manufacturerWarrantyType: vehicleData.manufacturerWarrantyType || '',
                    warrantyTerm: vehicleData.warrantyTerm || '',
                    warrantyInServiceDate: vehicleData.warrantyInServiceDate || '',
                    deferralOption: vehicleData.deferralOption || false,
                    deliveryDate: vehicleData.deliveryDate || '',
                    lienHolder: vehicleData.lienHolder || '',
                    // Powersports fields
                    vehicleCategory: loadedCategory,
                    vehicleSubType: this.vehicleSubType,
                    engineCC: vehicleData.engineCC || '',
                    coolingType: vehicleData.coolingType || '',
                    hoursUsage: vehicleData.hoursUsage || '',
                    vehicleClass: vehicleData.vehicleClass || '',
                    // Powersports intake hours and brand tier
                    intakeHours: vehicleData.intakeHours || null,
                    brandTier: vehicleData.brandTier || (this.isPowersports ? deriveBrandTier(vehicleData.make || '') : 'Standard')
                };

                // Populate Application fields
                if (vehicleData.dealerCommentsNotes !== undefined) {
                    this.applicationData.dealerCommentsNotes = vehicleData.dealerCommentsNotes || '';
                }
                if (vehicleData.showCommentsOnPrint !== undefined) {
                    this.applicationData.showCommentsOnPrint = vehicleData.showCommentsOnPrint || false;
                }
                if (vehicleData.salesRepId) {
                    this.applicationData.salesRepresentative = vehicleData.salesRepId;
                }
                // dealerSalesId is now read-only and always comes from Account.Dealership_ID__c
                // Don't override it from saved data - it will be set by loadDealershipInfo()
                // Dealership info from loaded data
                if (vehicleData.dealershipName) {
                    this.applicationData.dealershipName = vehicleData.dealershipName;
                }
                if (vehicleData.dealershipAddress) {
                    this.applicationData.dealershipAddress = vehicleData.dealershipAddress;
                }
                if (vehicleData.cityProvincePostal) {
                    this.applicationData.cityProvincePostal = vehicleData.cityProvincePostal;
                }
                
                // Use account ID from loaded data if available, otherwise use the one from getDealershipInfo
                if (vehicleData.dealershipAccountId) {
                    this.dealerAccountId = vehicleData.dealershipAccountId;
                }
                
                // Load dealer contacts for sales rep dropdown if we have account ID
                if (this.dealerAccountId) {
                    await this.loadDealerContacts();
                }
                
                // Ensure dealerSalesId is always set from dealership info (read-only field)
                // If dealership info hasn't loaded yet, load it now to get Dealership_ID__c
                if (!this.applicationData.dealerSalesId && this.dealerAccountId) {
                    const dealershipInfo = await getDealershipInfo();
                    if (dealershipInfo.success && dealershipInfo.dealershipId) {
                        this.applicationData.dealerSalesId = dealershipInfo.dealershipId;
                    }
                }
                
                // Save to session storage
                this.saveVehicleDataToSessionStorage();
                
                // Initialize original data for change tracking
                this.initializeOriginalData();
                
                console.log('✅ Vehicle data loaded successfully');
                
            } else {
                    console.log('ℹ️ No existing vehicle data found for this application');
                    this.initializeDefaultValues();
                    // Initialize original data for new records too
                    this.initializeOriginalData();
                }
                
            } catch (error) {
                console.error('❌ Error loading vehicle data:', error);
                this.showErrorMessage('Error loading vehicle data: ' + error.message);
            } finally {
                this.loading = false;
            }
    }
    
    requiredFields = [
        'vehicleIdentificationNumberVIN',
        'year',
        'make',
        'model',
        'trim',
        'purchasePrice',
        'odometerReading'
    ];
    
    // Commercial Vehicle Type modal (shown when Usage Type = 'Commercial/Business Use')
    @track showCommercialVehicleTypeModal = false;

    // Stored Commercial_Vehicle_Type__c picklist value
    @track commercialVehicleType = '';

    // Add commercial use dialog properties
    @track showCommercialDialog = false;
    @track commercialOptions = [
        {
            id: 'NON-COMMERCIAL',
            label: 'NON-COMMERCIAL',
            description: 'Personal use only. Vehicle not used for business purposes other than commuting to and from work.',
            icon: 'utility:user'
        },
        {
            id: 'LIGHT',
            label: 'LIGHT',
            description: 'Vehicles that are used for business purposes such as real estate, sales, etc. Not used to carry tools or equipment.',
            icon: 'utility:truck'
        },
        {
            id: 'MEDIUM',
            label: 'MEDIUM',
            description: 'Vehicles used for service or delivery: plumber, electrician, catering, etc. Carrying tools or equipment.',
            icon: 'utility:truck'
        },
        {
            id: 'HEAVY',
            label: 'HEAVY',
            description: 'Construction vehicles, dump trucks, cement trucks, tow trucks, etc. used for specific industry purposes.',
            icon: 'utility:truck'
        }
    ];
    
    initializeDefaultValues() {
        this.vehicleData = {
            stockNumber: '',
            vin: '',
            vehicleIdentificationNumberVIN: '',
            year: '',
            make: '',
            model: '',
            trim: '',
            dateSold: '',
            purchasePrice: '',
            isBrandedRebuilt: false,
            inServiceDate: '',
            odometerReading: '',
            odometerUnit: 'KM',
            commercialUse: 'NON-COMMERCIAL',
            isCommercial: false
        };
        this.vehicleId = '';
        this.isNewRecord = true;
        
        console.log('🚚 Default values initialized:', {
            vehicleId: this.vehicleId,
            isNewRecord: this.isNewRecord,
            vehicleData: this.vehicleData
        });
        console.log('🚚 vehicleData type:', typeof this.vehicleData);
        console.log('🚚 vehicleData keys:', Object.keys(this.vehicleData));
    }
    
    connectedCallback() {
        console.log('🚚 Vehicle component connected - applicationId:', this._applicationId);
        
        // Initialize default values
        this.initializeDefaultValues();

        // Load picklist metadata needed for the form
        this.loadWarrantyPicklistValues();
        
        // Load dealership info first (for new and existing applications)
        this.loadDealershipInfo();
        
        // Load vehicle data if applicationId is available
        if (this._applicationId) {
            this.loadVehicleData();
        }
    }

    async loadWarrantyPicklistValues() {
        try {
            const picklistData = await getVehicleWarrantyPicklists();
            if (picklistData) {
                this.manufacturerWarrantyTypeOptions = this.buildPicklistOptions(picklistData.manufacturerWarrantyType);
                // Warranty term options preserve allowDeferral from Manufacturer_Term__c.Allow_Defferal__c
                this.warrantyTermOptions = this.buildWarrantyTermOptionsWithAllowDeferral(picklistData.warrantyTerm);
            }
            console.log('📋 Warranty picklists loaded:', {
                manufacturerOptions: this.manufacturerWarrantyTypeOptions.length,
                warrantyTermOptions: this.warrantyTermOptions.length
            });
        } catch (error) {
            console.error('❌ Error loading warranty picklist values:', error);
        }
    }

    /**
     * Build warranty term options from Apex (Manufacturer_Term__c records).
     * Preserves allowDeferral (kept for backward compat) and durationMonths (used for expiry check).
     */
    buildWarrantyTermOptionsWithAllowDeferral(picklistValues) {
        const defaultOption = [{ label: '--None--', value: '', allowDeferral: false, durationMonths: null }];
        if (!Array.isArray(picklistValues) || picklistValues.length === 0) {
            return defaultOption;
        }
        const normalizedValues = picklistValues
            .filter(option => option && option.value)
            .map(option => ({
                label: option.label || option.value,
                value: option.value,
                allowDeferral: option.allowDeferral === true,
                durationMonths: option.durationMonths || null
            }));
        return [...defaultOption, ...normalizedValues];
    }

    buildPicklistOptions(picklistValues) {
        const defaultOption = [{ label: '--None--', value: '' }];
        if (!Array.isArray(picklistValues) || picklistValues.length === 0) {
            return defaultOption;
        }

        const normalizedValues = picklistValues
            .filter(option => option && option.value)
            .map(option => ({
                label: option.label || option.value,
                value: option.value
            }));

        return [...defaultOption, ...normalizedValues];
    }

    
    // Load dealership information from logged-in user's account
    async loadDealershipInfo() {
        try {
            const dealershipInfo = await getDealershipInfo();
            console.log('🏢 Dealership info loaded:', dealershipInfo);
            
            if (dealershipInfo.success) {
                // Populate dealership fields (read-only)
                this.applicationData.dealershipName = dealershipInfo.accountName || '';
                this.applicationData.dealershipAddress = dealershipInfo.billingStreet || '';
                this.applicationData.cityProvincePostal = dealershipInfo.cityProvincePostal || '';
                // Populate dealer sales ID from Dealership_ID__c field
                this.applicationData.dealerSalesId = dealershipInfo.dealershipId || '';
                
                // Store account ID and current user contact ID for later use
                this.dealerAccountId = dealershipInfo.accountId || '';
                this.currentUserContactId = dealershipInfo.contactId || '';
                
                // Set default sales representative to logged-in user
                if (this.currentUserContactId && !this.applicationData.salesRepresentative) {
                    this.applicationData.salesRepresentative = this.currentUserContactId;
                }
                
                // Load dealer contacts for sales rep dropdown
                if (this.dealerAccountId) {
                    await this.loadDealerContacts();
                }
            } else {
                console.warn('⚠️ Failed to load dealership info:', dealershipInfo.message);
            }
        } catch (error) {
            console.error('❌ Error loading dealership info:', error);
        }
    }
    
    // Load dealer contacts for sales rep dropdown
    async loadDealerContacts() {
        if (!this.dealerAccountId) {
            console.warn('No dealer account ID available to load contacts');
            return;
        }
        
        try {
            const contacts = await getDealerContacts({ accountId: this.dealerAccountId });
            console.log('👥 Dealer contacts loaded:', contacts);
            
            this.dealerContacts = contacts || [];
            
            // If no sales rep is set and we have contacts, default to current user
            if (!this.applicationData.salesRepresentative && this.currentUserContactId) {
                const currentUserContact = this.dealerContacts.find(c => c.Id === this.currentUserContactId);
                if (currentUserContact) {
                    this.applicationData.salesRepresentative = this.currentUserContactId;
                }
            }
        } catch (error) {
            console.error('❌ Error loading dealer contacts:', error);
        }
    }
    
    // Getter for sales rep options dropdown
    get salesRepOptions() {
        const options = [{ label: '--None--', value: '' }];
        
        if (this.dealerContacts && this.dealerContacts.length > 0) {
            this.dealerContacts.forEach(contact => {
                options.push({
                    label: contact.Name || '',
                    value: contact.Id || ''
                });
            });
        }
        
        return options;
    }
    
    renderedCallback() {
        console.log('🎨 Vehicle component rendered');
        console.log('🎨 vehicleData:', this.vehicleData);
        console.log('🎨 vehicleData type:', typeof this.vehicleData);
        console.log('🎨 vehicleData keys:', Object.keys(this.vehicleData || {}));
    }
    

    
    // Helper method to format date for input field
    formatDateForInput(dateValue) {
        if (dateValue) {
            const date = new Date(dateValue);
            return date.toISOString().split('T')[0];
        }
        return '';
    }

    getCommercialUseValueForSalesforce(lwcValue) {
        // Handle null, undefined, or empty values
        if (!lwcValue || lwcValue === '' || lwcValue === 'null') {
            return 'Non-Commercial'; // Default to Non-Commercial
        }
        
        const map = {
            'NON-COMMERCIAL': 'Non-Commercial',
            'LIGHT': 'Light',
            'MEDIUM': 'Medium',
            'HEAVY': 'Heavy'
        };
        
        const mappedValue = map[lwcValue];
        console.log('🔄 Commercial use to Salesforce mapping:', lwcValue, '->', mappedValue);
        
        return mappedValue || 'Non-Commercial'; // Default to Non-Commercial if no mapping found
    }
    
    getCommercialUseValueForLWC(sfValue) {
        // Handle null, undefined, or empty values
        if (!sfValue || sfValue === '' || sfValue === 'null') {
            return 'NON-COMMERCIAL'; // Default to NON-COMMERCIAL
        }
        
        const map = {
            'Non-Commercial': 'NON-COMMERCIAL',
            'Light': 'LIGHT',
            'Medium': 'MEDIUM',
            'Heavy': 'HEAVY'
        };
        
        const mappedValue = map[sfValue];
        console.log('🔄 Commercial use mapping:', sfValue, '->', mappedValue);
        
        return mappedValue || 'NON-COMMERCIAL'; // Default to NON-COMMERCIAL if no mapping found
    }

    getOdometerUnitForSalesforce(lwcValue) {
        // Handle null, undefined, or empty values
        if (!lwcValue || lwcValue === '' || lwcValue === 'null') {
            return 'KM'; // Default to KM
        }
        
        const map = {
            'KM': 'KM',
            'MILES': 'Miles'
        };
        
        const mappedValue = map[lwcValue];
        console.log('🔄 Odometer unit to Salesforce mapping:', lwcValue, '->', mappedValue);
        
        return mappedValue || 'KM'; // Default to KM if no mapping found
    }
    
    getOdometerUnitForLWC(sfValue) {
        // Handle null, undefined, or empty values
        if (!sfValue || sfValue === '' || sfValue === 'null') {
            return 'KM'; // Default to KM
        }
        
        const map = {
            'KM': 'KM',
            'Miles': 'MILES'
        };
        
        const mappedValue = map[sfValue];
        console.log('🔄 Odometer unit mapping:', sfValue, '->', mappedValue);
        
        return mappedValue || 'KM'; // Default to KM if no mapping found
    }

    renderedCallback() {
        if (!this.vehicleData) {
            this.isFormVisible = false;
        }
    }
    @api
restoreData(data) {
    if (data && data.vehicleData) {
        console.log('🚚 restoreData called with:', JSON.stringify(data));

        // Transform fields with proper mapping
        const transformedData = {
            ...data.vehicleData,
            odometerUnit: this.getOdometerUnitForLWC(data.vehicleData.odometerUnit),
            commercialUse: this.getCommercialUseValueForLWC(data.vehicleData.commercialUse),
            isCommercial: data.vehicleData.isCommercial || false
        };

        this.vehicleData = JSON.parse(JSON.stringify(transformedData));
        this.vehicleId = data.vehicleId || this.vehicleId;
                    this._applicationId = data.applicationId || this._applicationId;
        this.isNewRecord = data.isNewRecord !== undefined ? data.isNewRecord : this.isNewRecord;
        
        console.log('🚚 Data restored - applicationId:', this._applicationId, 'vehicleId:', this.vehicleId, 'isNewRecord:', this.isNewRecord);
        console.log('🚚 Odometer Unit restored:', this.vehicleData.odometerUnit);
        console.log('🚚 Commercial Use restored:', this.vehicleData.commercialUse);
        console.log('🚚 Is Commercial restored:', this.vehicleData.isCommercial);
        
        // Also try to restore from session storage for additional data
        this.restoreFromSessionStorage();
    }
}


    
getCurrentData() {
    const currentData = {
        vehicleData: this.vehicleData,
        applicationId: this._applicationId,
        vehicleId: this.vehicleId,
        isNewRecord: this.isNewRecord
    };
    console.log('🔁 getCurrentData result:', JSON.stringify(currentData, null, 2));
    return currentData;
}
    
    // Save data to session storage
    saveDataToSession() {
        console.log('💾 Saving vehicle data to session storage for application:', this._applicationId);
        
        if (this._applicationId) {
            // Use application-specific keys to avoid conflicts
            sessionStorage.setItem(`vehicleData_${this._applicationId}`, JSON.stringify(this.vehicleData));
            sessionStorage.setItem(`vehicleInfo_${this._applicationId}`, JSON.stringify(this.vehicleData));
            sessionStorage.setItem(`vehicleId_${this._applicationId}`, this.vehicleId || '');
            sessionStorage.setItem(`isNewRecord_${this._applicationId}`, JSON.stringify(this.isNewRecord));
            console.log('💾 Saved to application-specific keys');
        }
        
        // Keep global keys for backward compatibility
        sessionStorage.setItem('vehicleData', JSON.stringify(this.vehicleData));
        sessionStorage.setItem('vehicleInfo', JSON.stringify(this.vehicleData));
        sessionStorage.setItem('applicationId', this._applicationId || '');
        sessionStorage.setItem('vehicleId', this.vehicleId || '');
        sessionStorage.setItem('isNewRecord', JSON.stringify(this.isNewRecord));
        console.log('💾 Saved to global keys');
        
        console.log('💾 Vehicle data saved:', {
            vehicleData: this.vehicleData,
            vehicleId: this.vehicleId,
            isNewRecord: this.isNewRecord
        });
    }
    
    // Dropdown options
    get yearOptions() {
        const currentYear = new Date().getFullYear();
        const options = [];
        for (let i = currentYear; i >= currentYear - 15; i--) {
            options.push({ label: i.toString(), value: i.toString() });
        }
        return options;
    }
    
    // Fuel Type options
    get fuelTypeOptions() {
        return [
            { label: '--None--', value: '' },
            { label: 'Gasoline', value: 'Gasoline' },
            { label: 'Diesel', value: 'Diesel' },
            { label: 'Electric', value: 'Electric' },
            { label: 'Hybrid', value: 'Hybrid' },
            { label: 'Plug-in Hybrid', value: 'Plug-in Hybrid' },
            { label: 'Hydrogen', value: 'Hydrogen' },
            { label: 'Flex Fuel', value: 'Flex Fuel' }
        ];
    }
    
    get vehicleCategoryOptions() {
        return [
            { label: '', value: '' },
            { label: 'Used Car', value: 'Used Car' },
            { label: 'Powersports', value: 'Powersports' }
        ];
    }

    // Drive Type options
    get driveTypeOptions() {
        return [
            { label: '--None--', value: '' },
            { label: 'FWD', value: 'FWD' },
            { label: 'RWD', value: 'RWD' },
            { label: 'AWD', value: 'AWD' },
            { label: '4WD', value: '4WD' }
        ];
    }
    
    // Body Style options
    get bodyStyleOptions() {
        return [
            { label: '--None--', value: '' },
            { label: 'Sedan', value: 'Sedan' },
            { label: 'SUV', value: 'SUV' },
            { label: 'Truck', value: 'Truck' },
            { label: 'Coupe', value: 'Coupe' },
            { label: 'Hatchback', value: 'Hatchback' },
            { label: 'Wagon', value: 'Wagon' },
            { label: 'Van', value: 'Van' }
        ];
    }

    // Usage Type options for radio buttons
    get usageTypeOptions() {
        return [
            { label: 'Personal Use', value: 'Personal Use' },
            { label: 'Commercial/Business Use', value: 'Commercial/Business Use' }
        ];
    }

    // Show the commercial vehicle type display field when usage is Commercial/Business Use and a type has been selected
    get showCommercialVehicleTypeField() {
        return this.vehicleData.usageType === 'Commercial/Business Use' &&
               !!this.vehicleData.commercialVehicleType;
    }

    // Allow user to re-open the modal to change their selection
    handleChangeCommercialVehicleType() {
        this.showCommercialVehicleTypeModal = true;
    }

    // Handle usage type change (radio button)
    handleUsageTypeChange(event) {
        const value = event.detail.value;
        this.vehicleData = {
            ...this.vehicleData,
            usageType: value,
            isCommercial: value === 'Commercial/Business Use'
        };
        console.log('Usage type changed:', value);

        // Open the Commercial Vehicle Type modal when "Commercial/Business Use" is selected
        if (value === 'Commercial/Business Use') {
            this.showCommercialVehicleTypeModal = true;
        } else {
            // Reset commercial vehicle type if user switches away
            this.showCommercialVehicleTypeModal = false;
            this.commercialVehicleType = '';
            this.vehicleData = {
                ...this.vehicleData,
                commercialVehicleType: ''
            };
        }
    }

    // Handle selection from the Commercial Vehicle Type modal
    handleCommercialVehicleTypeSelected(event) {
        const selectedValue = event.detail.value;
        this.commercialVehicleType = selectedValue;
        this.vehicleData = {
            ...this.vehicleData,
            commercialVehicleType: selectedValue
        };
        this.showCommercialVehicleTypeModal = false;
        console.log('✅ Commercial vehicle type set:', selectedValue);
    }

    // Handle modal close without selection
    handleCommercialVehicleTypeClose() {
        this.showCommercialVehicleTypeModal = false;
        // If they close without selecting, revert usage type to Personal Use
        if (!this.commercialVehicleType) {
            this.vehicleData = {
                ...this.vehicleData,
                usageType: 'Personal Use',
                isCommercial: false
            };
        }
    }
    
    // Enhanced vehicle database for VIN search
    get vehicleDatabase() {
        return [
            {
                vin: '1HGBH41JXMN109186',
                stockNumber: 'ST001',
                year: '2023',
                make: 'Honda',
                model: 'Civic',
                trim: 'Sport',
                dateSold: '2023-12-15',
                purchasePrice: '28000',
                odometerReading: '5000',
                odometerUnit: 'KM'
            },
            {
                vin: '2T1BURHE0JC123456',
                stockNumber: 'ST002',
                year: '2023',
                make: 'Toyota',
                model: 'Camry',
                trim: 'SE',
                dateSold: '2023-11-20',
                purchasePrice: '32000',
                odometerReading: '3500',
                odometerUnit: 'KM'
            },
            {
                vin: '3VWDX7AJ5DM123456',
                stockNumber: 'ST003',
                year: '2023',
                make: 'Volkswagen',
                model: 'Jetta',
                trim: 'SEL',
                dateSold: '2023-10-10',
                purchasePrice: '26000',
                odometerReading: '8000',
                odometerUnit: 'KM'
            },
            {
                vin: '4T1B11HK5JU123456',
                stockNumber: 'ST004',
                year: '2023',
                make: 'Toyota',
                model: 'RAV4',
                trim: 'XLE',
                dateSold: '2023-12-01',
                purchasePrice: '38000',
                odometerReading: '2500',
                odometerUnit: 'KM'
            },
            {
                vin: '5NPE34AF5FH123456',
                stockNumber: 'ST005',
                year: '2023',
                make: 'Hyundai',
                model: 'Sonata',
                trim: 'Limited',
                dateSold: '2023-09-15',
                purchasePrice: '29000',
                odometerReading: '12000',
                odometerUnit: 'KM'
            },
            {
                vin: '6G1ZT51806L123456',
                stockNumber: 'ST006',
                year: '2023',
                make: 'Chevrolet',
                model: 'Malibu',
                trim: 'Premier',
                dateSold: '2023-08-22',
                purchasePrice: '27000',
                odometerReading: '15000',
                odometerUnit: 'KM'
            },
            {
                vin: '7FARW2H85BE123456',
                stockNumber: 'ST007',
                year: '2023',
                make: 'Ford',
                model: 'Escape',
                trim: 'Titanium',
                dateSold: '2023-11-05',
                purchasePrice: '34000',
                odometerReading: '6000',
                odometerUnit: 'KM'
            },
            {
                vin: '8XJDF4G25BN123456',
                stockNumber: 'ST008',
                year: '2023',
                make: 'Audi',
                model: 'A4',
                trim: 'Premium Plus',
                dateSold: '2023-12-08',
                purchasePrice: '45000',
                odometerReading: '3000',
                odometerUnit: 'KM'
            },
            {
                vin: '9BWDE21J924123456',
                stockNumber: 'ST009',
                year: '2023',
                make: 'Volkswagen',
                model: 'Passat',
                trim: 'R-Line',
                dateSold: '2023-10-30',
                purchasePrice: '31000',
                odometerReading: '9000',
                odometerUnit: 'KM'
            },
            {
                vin: '1ZVBP8CF4E5123456',
                stockNumber: 'ST010',
                year: '2023',
                make: 'Ford',
                model: 'Mustang',
                trim: 'GT',
                dateSold: '2023-09-28',
                purchasePrice: '52000',
                odometerReading: '4000',
                odometerUnit: 'KM'
            }
        ];
    }
    
    get odometerOptions() {
        return [
            { label: 'KM', value: 'KM' },
            { label: 'MILES', value: 'MILES' }
        ];
    }

    get convertedOdometerValue() {
        const reading = parseFloat(this.vehicleData.odometerReading);
        if (!reading && reading !== 0) return '';
        const unit = this.vehicleData.odometerUnit || 'KM';
        // Only show converted value when odometer is in Miles (show KM equivalent)
        // Do not show miles conversion when odometer is in KM
        if (unit === 'KM') {
            return '';
        }
        return Math.round(reading * 1.60934);
    }

    get convertedOdometerLabel() {
        return 'Odometer (KM)';
    }
    
    // Handle input changes with field-level tracking and auto-save
    handleVehicleSubTypeChange(event) {
        this.vehicleSubType = event.target.value;
    }

    handleInputChange(event) {
        const field = event.target.name;
        let value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;

        // Parse numbers
        if (event.target.type === 'number' && value !== '') {
            value = parseFloat(value);
        }
        
        console.log('🔄 Field changed:', field, 'from', this.vehicleData[field], 'to', value);
        
        // Update vehicle data
        this.vehicleData = { ...this.vehicleData, [field]: value };
        
        // Track field changes for selective updates
        this.trackFieldChange(field, value);
        
        // Notify parent that vehicle data has changed (for tab completion status)
        this.notifyParentOfDataChange();
        this.showError = false;
        debugger;
        // Auto-save after debounce (only if not a new record)
        if (!this.isNewRecord && this.vehicleId) {
            this.debouncedAutoSave();
        }
    }
    
    // Track field changes for selective updates
    trackFieldChange(field, newValue) {
        const originalValue = this.originalVehicleData[field];
        
        console.log('🔍 Tracking field change:', {
            field,
            originalValue,
            newValue,
            hasChanged: originalValue !== newValue
        });
        
        if (originalValue !== newValue) {
            this.changedFields.add(field);
            console.log('📝 Field marked as changed:', field);
        } else {
            this.changedFields.delete(field);
            console.log('↩️ Field reverted to original:', field);
        }
        
        console.log('📋 Total changed fields:', Array.from(this.changedFields));
    }
    
    // Debounced auto-save to avoid excessive DML
    debouncedAutoSave() {
        // Clear existing timeout
        if (this.autoSaveTimeout) {
            clearTimeout(this.autoSaveTimeout);
        }
        
        // Set new timeout for auto-save (2 seconds after last change)
        this.autoSaveTimeout = setTimeout(() => {
            this.autoSaveChangedFields();
        }, 2000);
        
        console.log('⏱️ Auto-save scheduled in 2 seconds...');
    }
    
    // Auto-save only changed fields
    async autoSaveChangedFields() {
        if (this.changedFields.size === 0) {
            console.log('ℹ️ No changed fields to auto-save');
            return;
        }
        
        if (!this.vehicleId || this.isNewRecord) {
            console.log('ℹ️ Skipping auto-save for new record');
            return;
        }
        
        try {
            console.log('💾 Auto-saving changed fields:', Array.from(this.changedFields));
            
            // Prepare only changed fields for update
            const fieldsToUpdate = {};
            this.changedFields.forEach(field => {
                fieldsToUpdate[field] = this.vehicleData[field];
            });
            
            // Call selective update method (to be implemented)
            const result = await this.updateVehicleFields(fieldsToUpdate);
            
            if (result.success) {
                console.log('✅ Auto-save successful for fields:', Array.from(this.changedFields));
                
                // Update original data and clear changed fields
                this.changedFields.forEach(field => {
                    this.originalVehicleData[field] = this.vehicleData[field];
                });
                this.changedFields.clear();
                
                // Show subtle success indicator
                this.showAutoSaveSuccess();
            } else {
                console.error('❌ Auto-save failed:', result.message);
            }
        } catch (error) {
            console.error('❌ Auto-save error:', error);
        }
    }
    
    // Initialize original data for change tracking
    initializeOriginalData() {
        this.originalVehicleData = { ...this.vehicleData };
        this.changedFields.clear();
        console.log('🔄 Original vehicle data initialized for change tracking');
    }
    
    // Show auto-save success indicator
    showAutoSaveSuccess() {
        // Add a subtle visual indicator that data was auto-saved
        console.log('✅ Auto-save success indicator shown');
        // You can implement a toast or temporary icon here
    }
    
    // Method to update only changed vehicle fields
    async updateVehicleFields(fieldsToUpdate) {
        try {
            console.log('💾 Updating vehicle fields:', fieldsToUpdate);
            
            // Map LWC field names to Salesforce field names if needed
            const salesforceFields = this.mapToSalesforceFields(fieldsToUpdate);
            
            // Call new selective update Apex method (to be implemented)
            const result = await updateVehicleFieldsSelective({
                vehicleId: this.vehicleId,
                applicationId: this._applicationId,
                fields: salesforceFields
            });
            
            return result;
        } catch (error) {
            console.error('❌ Error updating vehicle fields:', error);
            return { success: false, message: error.message };
        }
    }
    
    // Map LWC field names to Salesforce field names
    mapToSalesforceFields(lwcFields) {
        const fieldMapping = {
            'stockNumber': 'Stock_Number__c',
            'vin': 'VIN__c',
            'vehicleIdentificationNumberVIN': 'Vehicle_Identification_Number_VIN__c',
            'year': 'Year__c',
            'make': 'Make__c',
            'model': 'Model__c',
            'trim': 'Trim__c',
            'dateSold': 'Date_Vehicle_Sold__c',
            'purchasePrice': 'Vehicle_Purchase_Price__c',
            'isCommercial': 'Business_Commercial_Use__c',
            'isBrandedRebuilt': 'Branded_Rebuilt__c',
            // inServiceDate removed from mapping - using only warrantyInServiceDate
            'odometerReading': 'Odometer__c',
            'odometerUnit': 'Odometer_Unit__c',
            'commercialUse': 'Type_of_Commercial_Use__c',
            // New Vehicle Details fields
            'engine': 'Engine__c',
            'transmission': 'Transmission__c',
            'fuelType': 'Fuel_Type__c',
            'driveType': 'Drive_Type__c',
            'bodyStyle': 'Body_Style__c',
            'color': 'Color__c',
            'gvwr': 'GVWR__c',
            // Manufacturer Warranty fields
            'manufacturerWarrantyType': 'Manufacturer_Warranty_Type__c',
            'warrantyTerm': 'Warranty_Term__c',
            'warrantyInServiceDate': 'In_Service_Date__c', // Only field mapping for In_Service_Date__c
            'deferralOption': 'Deferral_Option__c',
            'deliveryDate': 'Delivery_Date__c',
            'usageType': 'Usage_Type__c',
            'commercialVehicleType': 'Commercial_Vehicle_Type__c',
            'lienHolder': 'Financial_Institution_Lender__c'
        };
        
        const salesforceFields = {};
        Object.keys(lwcFields).forEach(lwcField => {
            const sfField = fieldMapping[lwcField] || lwcField;
            salesforceFields[sfField] = lwcFields[lwcField];
        });
        
        console.log('🔄 Mapped fields:', { lwcFields, salesforceFields });
        return salesforceFields;
    }
    
    // Handle search button click - checks for duplicate VIN first, then decodes
    async handleSearch() {
        const searchVin = this.vehicleData.vehicleIdentificationNumberVIN;
        
        if (!searchVin || searchVin.trim() === '') {
            this.showErrorMessage('Please enter a VIN to search');
            return;
        }
        
        this.loading = true;
        this.showError = false;
        this.errorMessage = '';
        
        try {
            // STEP 1: Check for duplicate VIN before calling Black Book
            console.log('🔍 Checking for duplicate VIN: ' + searchVin);
            const dupResult = await checkDuplicateVIN({ 
                vin: searchVin.trim(), 
                currentApplicationId: this._applicationId || '' 
            });
            
            if (dupResult && dupResult.hasDuplicates && dupResult.duplicates && dupResult.duplicates.length > 0) {
                console.log('⚠️ Duplicate VIN found:', dupResult.duplicates);
                
                // Store cross-dealer flag and existing vehicle data
                this.isCrossDealerVin = dupResult.isCrossDealer || false;
                this.existingVehicleData = dupResult.existingVehicleData || null;
                
                this.duplicateVinRecords = dupResult.duplicates.map((dup, index) => ({
                    ...dup,
                    index: index
                }));
                
                // Always start on the main options view
                this.showDuplicateSubList = false;
                this.showDuplicateVinModal = true;
                this.loading = false;
                return; // Stop here — user must choose. NO API call.
            }
            
            // No duplicates — proceed with VIN decode (API call)
            await this.proceedWithVinDecode(searchVin);
            
        } catch (error) {
            console.error('❌ Error during VIN search:', error);
            // If duplicate check fails, proceed with decode anyway
            try {
                await this.proceedWithVinDecode(searchVin);
            } catch (decodeError) {
                console.error('❌ Error during VIN decode:', decodeError);
                this.showErrorMessage('Error connecting to VIN decoder service. Please try again or enter vehicle information manually.');
                this.loading = false;
            }
        }
    }

    // Handle selecting a duplicate record row


    // Handle "Open Existing Record" button in duplicate modal
    handleOpenExistingRecord() {
        if (this.duplicateVinRecords.length === 1) {
            // Single match — navigate directly
            const record = this.duplicateVinRecords[0];
            this.navigateToApplication(record.recordId, record.recordName);
        } else {
            // Multiple matches — show sub-list for user to pick
            this.showDuplicateSubList = true;
        }
    }

    handleSelectAndOpenRecord(event) {
        const recordId = event.currentTarget.dataset.id;
        const record = this.duplicateVinRecords.find(dup => dup.recordId === recordId);
        if (record) {
            this.navigateToApplication(record.recordId, record.recordName);
        }
    }

    navigateToApplication(recordId, recordName) {
        this.showDuplicateVinModal = false;
        this.showDuplicateSubList = false;
        const url = `/dealerportal/s/application/${recordId}/${recordName || ''}`;
        window.location.href = url;
    }

    handleBackToOptions() {
        this.showDuplicateSubList = false;
    }

    // Handle "Continue with New Record" button in duplicate modal
    handleStartNewApplication() {
        this.showDuplicateVinModal = false;
        this.showDuplicateSubList = false;
        this.loading = true;

        try {
            if (this.existingVehicleData) {
                console.log('📋 Populating vehicle data from existing record (no API call)');
                
                const existingData = this.existingVehicleData;
                
                // Populate the vehicle form fields from existing record data
                this.vehicleData = {
                    ...this.vehicleData,
                    vin: existingData.vin || this.vehicleData.vehicleIdentificationNumberVIN,
                    vehicleIdentificationNumberVIN: existingData.vehicleIdentificationNumberVIN || this.vehicleData.vehicleIdentificationNumberVIN,
                    year: existingData.year || '',
                    make: existingData.make || '',
                    model: existingData.model || '',
                    trim: existingData.trim || '',
                    engine: existingData.engine || '',
                    fuelType: existingData.fuelType || '',
                    driveType: existingData.driveType || '',
                    transmission: existingData.transmission || '',
                    bodyStyle: existingData.bodyStyle || '',
                    color: existingData.color || '',
                    vehicleCategory: existingData.vehicleCategory || ''
                };
                
                // Set vehicle category and powersports state
                this.vehicleCategory = existingData.vehicleCategory || '';
                this.isPowersports = (this.vehicleCategory === 'Powersports');
                
                // Mark that we have vehicle data (enables the form sections)
                this.hasVehicleData = true;
                this.vinDecoded = true;
                
                // Store for additional vehicle info modal
                this.additionalVehicleData = existingData;
                
                this.loading = false;
                
                // Show success message
                this.showSuccessMessage('Vehicle information populated from existing records. Please review and complete the remaining fields.');
            } else {
                // Fallback: if no existing data available, just enable manual entry
                console.log('⚠️ No existing vehicle data available, enabling manual entry');
                this.hasVehicleData = true;
                this.vinDecoded = true;
                this.loading = false;
                this.showSuccessMessage('Please enter vehicle information manually.');
            }
        } catch (error) {
            console.error('❌ Error populating vehicle data:', error);
            this.loading = false;
            this.showErrorMessage('Error populating vehicle data. Please enter information manually.');
        }
    }

    // Close duplicate VIN modal
    closeDuplicateVinModal() {
        this.showDuplicateVinModal = false;
        this.showDuplicateSubList = false;
    }

    handleContactSupport() {
        this.showDuplicateVinModal = false;
        this.showDuplicateSubList = false;
        
        // Show support contact information
        this.showErrorMessage(
            'This VIN is associated with a record from another dealership. ' +
            'Please contact A-Protect Support to resolve this VIN duplication. ' +
            'Email: support@a-protect.ca | Phone: 1-866-667-1965'
        );
    }

    // Getter: is the "Open Existing Record" button disabled?


    // Proceed with VIN decode (Black Book integration)
    async proceedWithVinDecode(searchVin) {
        this.loading = true;
        
        try {
            console.log('🔍 Starting VIN decode for: ' + searchVin);
            
            // Call the real VIN decoder API
            const result = await decodeVin({ vin: searchVin });
            
            // Log the complete API response to browser console
            console.log('🔍 Complete VIN Decode API Response:', result);
            console.log('🔍 API Source:', result.apiSource);
            console.log('🔍 Success:', result.success);
            console.log('🔍 Message:', result.message);
            console.log('🔍 Vehicle Data:', result.data);
            console.log('🔍 Vehicle Data Keys:', Object.keys(result.data || {}));
            console.log('🔍 Year Value:', result.data?.year);
            console.log('🔍 Make Value:', result.data?.make);
            console.log('🔍 Model Value:', result.data?.model);
            console.log('🔍 Raw JSON Response:', result.rawResponse);
            
            // Store raw JSON response for display in Additional Vehicle Information
            this.rawJsonResponse = result.rawResponse || null;
            
            // Special logging for NHTSA responses
            if (result.apiSource === 'NHTSA') {
                console.log('🚨 NHTSA API RESPONSE DETECTED - FORCED FOR TESTING');
                console.log('🚨 NHTSA Raw Response Data:', JSON.stringify(result.data, null, 2));
                console.log('🚨 NHTSA All Fields:', result.data);
            }
            
            if (result.success && result.data) {
                const decodedData = result.data;
                
                // Store additional vehicle data for "More Information" modal
                this.additionalVehicleData = decodedData;
                this.hasVehicleData = true;
                console.log('💾 Additional vehicle data stored:', this.additionalVehicleData);
                console.log('💾 hasVehicleData set to:', this.hasVehicleData);
                console.log('💾 Additional vehicle data keys:', Object.keys(this.additionalVehicleData || {}));
                console.log('💾 Additional vehicle data count:', Object.keys(this.additionalVehicleData || {}).length);
                console.log('💾 Button should be enabled:', !this.isVehicleDataDisabled);
                
                // Helper function to convert Blackbook transmission code to readable format
                const convertTransmission = (transCode) => {
                    if (!transCode) return '';
                    const transMap = {
                        'A': 'Automatic',
                        'M': 'Manual',
                        'CVT': 'CVT',
                        'AM': 'Automated Manual',
                        'AS': 'Automated Shift'
                    };
                    return transMap[transCode] || transCode;
                };
                
                // Helper function to convert Blackbook fuel type to form format
                const convertFuelType = (fuelType) => {
                    if (!fuelType) return '';
                    const fuelMap = {
                        'Gas': 'Gasoline',
                        'Diesel': 'Diesel',
                        'Electric': 'Electric',
                        'Hybrid': 'Hybrid',
                        'Plug-in Hybrid': 'Plug-in Hybrid',
                        'Hydrogen': 'Hydrogen',
                        'Flex Fuel': 'Flex Fuel'
                    };
                    return fuelMap[fuelType] || fuelType;
                };
                
                // Helper function to extract body style from Blackbook style field
                const extractBodyStyle = (style) => {
                    if (!style) return '';
                    // Blackbook style format: "4D Sedan", "SUV", etc.
                    const styleLower = style.toLowerCase();
                    if (styleLower.includes('sedan')) return 'Sedan';
                    if (styleLower.includes('suv') || styleLower.includes('sport utility')) return 'SUV';
                    if (styleLower.includes('truck') || styleLower.includes('pickup')) return 'Truck';
                    if (styleLower.includes('coupe')) return 'Coupe';
                    if (styleLower.includes('hatchback')) return 'Hatchback';
                    if (styleLower.includes('wagon')) return 'Wagon';
                    if (styleLower.includes('van')) return 'Van';
                    return '';
                };
                
                // Helper function to extract numeric value from GVWR (remove units if present)
                const extractGvwrNumber = (gvwr) => {
                    if (!gvwr) return '';
                    // If it's already a number, return it; otherwise extract number from string
                    if (typeof gvwr === 'number') return String(gvwr);
                    const match = String(gvwr).match(/(\d+)/);
                    return match ? match[1] : '';
                };
                
                // Set vehicle category and Powersports state from API source
                this.vehicleCategory = decodedData.vehicleCategory || '';
                this.isPowersports = (this.vehicleCategory === 'Powersports');

                // Set vehicle sub type from API response
                if (this.isPowersports) {
                    this.vehicleSubType = decodedData.powersportsModelClass || '';
                } else {
                    this.vehicleSubType = decodedData.bodyClass || '';
                }

                // Store Powersports modal data if present
                if (this.isPowersports) {
                    this.powersportsModalData = {
                        className:    decodedData.powersportsClassName,
                        modelClass:   decodedData.powersportsModelClass,
                        uvc:          decodedData.powersportsUvc,
                        cylinders:    decodedData.powersportsCylinders,
                        displacement: decodedData.engineCC,
                        wholeAvg:     decodedData.powersportsWholeAvg,
                        retailAvg:    decodedData.powersportsRetailAvg,
                        tradeinClean: decodedData.powersportsTradeinClean,
                        tradeinFair:  decodedData.powersportsTradeinFair,
                        finadv:       decodedData.powersportsFinadv,
                        msrp:         decodedData.powersportsMsrp,
                        publishDate:  decodedData.powersportsPublishDate
                    };
                } else {
                    this.powersportsModalData = null;
                }

                // Populate form with decoded vehicle data
                this.vehicleData = {
                    ...this.vehicleData,
                    vin: decodedData.vin || searchVin,
                    vehicleIdentificationNumberVIN: decodedData.vin || searchVin,
                    year: decodedData.year || this.vehicleData.year || '',
                    make: decodedData.make || this.vehicleData.make || '',
                    model: decodedData.model || this.vehicleData.model || '',
                    trim: decodedData.trim || this.vehicleData.trim || '',
                    // Map Blackbook vehicle details to form fields (Used Car only)
                    engine: decodedData.engineModel || this.vehicleData.engine || '',
                    transmission: convertTransmission(decodedData.transmissionStyle) || this.vehicleData.transmission || '',
                    fuelType: convertFuelType(decodedData.fuelType) || this.vehicleData.fuelType || '',
                    driveType: decodedData.driveType || this.vehicleData.driveType || '',
                    bodyStyle: extractBodyStyle(decodedData.bodyClass) || this.vehicleData.bodyStyle || '',
                    color: decodedData.color || this.vehicleData.color || '',
                    gvwr: extractGvwrNumber(decodedData.gvwr) || this.vehicleData.gvwr || '',
                    // Keep existing values for fields not provided by API
                    stockNumber: this.vehicleData.stockNumber || '',
                    dateSold: this.vehicleData.dateSold || '',
                    purchasePrice: this.vehicleData.purchasePrice || '',
                    odometerReading: this.vehicleData.odometerReading || '',
                    odometerUnit: this.vehicleData.odometerUnit || 'KM',
                    isCommercial: this.vehicleData.isCommercial || false,
                    isBrandedRebuilt: this.vehicleData.isBrandedRebuilt || false,
                    inServiceDate: this.vehicleData.inServiceDate || '',
                    commercialUse: this.vehicleData.commercialUse || 'NON-COMMERCIAL',
                    deliveryDate: this.vehicleData.deliveryDate || '',
                    lienHolder: this.vehicleData.lienHolder || '',
                    usageType: this.vehicleData.usageType || 'Personal Use',
                    // Powersports storable fields
                    vehicleCategory: this.vehicleCategory,
                    vehicleSubType: this.vehicleSubType,
                    engineCC: this.isPowersports ? (decodedData.engineCC || '') : '',
                    coolingType: this.vehicleData.coolingType || '',
                    hoursUsage: this.vehicleData.hoursUsage || '',
                    vehicleClass: this.isPowersports ? (decodedData.powersportsClassName || '') : '',
                    // Powersports Intake Hours (from hours/mileage field in decoded response)
                    intakeHours: this.isPowersports ? (decodedData.hoursUsage || decodedData.hours || null) : null,
                    // Brand Tier auto-derived from make
                    brandTier: this.isPowersports ? deriveBrandTier(decodedData.make || '') : 'Standard'
                };
                
                console.log('✅ VIN decoded successfully:', {
                    make: decodedData.make,
                    model: decodedData.model,
                    year: decodedData.year,
                    trim: decodedData.trim,
                    apiSource: result.apiSource
                });
                
                // Show success message with API source information
                let successMessage = 'Vehicle information loaded successfully!';
                if (result.apiSource === 'BLACKBOOK') {
                    successMessage = 'Vehicle information loaded successfully! (Blackbook - Used Car)';
                } else if (result.apiSource === 'BLACKBOOK_POWERSPORTS') {
                    successMessage = 'Vehicle information loaded successfully! (Blackbook - Powersports)';
                } else if (result.apiSource === 'AUTO_DEV') {
                    successMessage = 'Vehicle information loaded successfully! (Auto.dev - Comprehensive data)';
                } else if (result.apiSource === 'NHTSA') {
                    successMessage = 'Vehicle information loaded successfully! (NHTSA - Basic data)';
                }
                this.showSuccessMessage(successMessage);
                
            } else {
                // VIN decode failed
                console.log('❌ VIN decode failed:', result.message);
                this.showErrorMessage(result.message || 'Unable to decode VIN. Please check the VIN and try again, or enter vehicle information manually.');
            }
            
        } catch (error) {
            console.error('❌ Error during VIN decode:', error);
            this.showErrorMessage('Error connecting to VIN decoder service. Please try again or enter vehicle information manually.');
        } finally {
            this.loading = false;
        }
    }
    
  
    validateFields() {
        const missingFields = [];
        const fieldLabels = {
            vin: 'VIN',
            year: 'Year',
            make: 'Make',
            model: 'Model',
            trim: 'Trim',
            dateSold: 'Date Vehicle Sold',
            purchasePrice: 'Purchase Price',
            odometerReading: 'Odometer Reading'
        };
    
        this.requiredFields.forEach(field => {
            if (!this.vehicleData[field] || this.vehicleData[field] === '') {
                missingFields.push(fieldLabels[field] || field);
            }
        });
    
        return missingFields;
    }

// Helper to make field names user-friendly
getFieldLabel(field) {
    const labels = {
        vin: 'VIN',
        vehicleIdentificationNumberVIN: 'Salesforce VIN',
        year: 'Year',
        make: 'Make',
        model: 'Model',
        trim: 'Trim',
        dateSold: 'Date Vehicle Sold',
        purchasePrice: 'Purchase Price',
        odometerReading: 'Odometer Reading'
        // Add more as needed
    };
    return labels[field] || field;
}
    
async handleContinue() {
    this.loading = true;
    this.showError = false;
    this.errorMessage = '';

    try {
        // Validate required fields for navigation
        if (!this.validateDataForNavigation()) {
            this.loading = false;
            return;
        }

        // Debug: Log the current state
        console.log('Current vehicleId:', this.vehicleId);
        console.log('Current applicationId:', this._applicationId);
        console.log('Current vehicleData:', this.vehicleData);
        console.log('VehicleData type:', typeof this.vehicleData);
        console.log('VehicleData keys:', Object.keys(this.vehicleData || {}));
        
        // Ensure vehicleData is properly initialized before proceeding
        this.ensureVehicleDataInitialized();

                                // Since we already have an applicationId, save the vehicle data to Salesforce
                        if (this._applicationId) {
                            console.log('✅ Application already exists, saving vehicle data to Salesforce...');
                            console.log('✅ ApplicationId:', this._applicationId);
                            
                                                        // Save data to Salesforce first
                            const saveSuccess = await this.saveVehicleDataToSalesforce();
                            
                            if (saveSuccess) {
                                // Success - let the container handle navigation via vehiclecomplete event
                                console.log('✅ Vehicle save successful - container will handle navigation');
                            } else {
                                // Save failed, don't navigate
                                console.error('❌ Vehicle save failed - cannot proceed');
                                return;
                            }
                            
                        } else {
                            // This should not happen since we're using existing applications
                            console.error('❌ No applicationId found. This should not happen with existing applications.');
                            console.error('❌ _applicationId:', this._applicationId);
                            console.error('❌ applicationId getter:', this._applicationId);
                            this.errorMessage = 'No application found. Please contact support.';
                            this.showError = true;
                        }

    } catch (error) {
        console.error('❌ Error in handleContinue:', error);
        this.errorMessage = 'Error saving vehicle data. Please try again.';
        this.showError = true;
    } finally {
        this.loading = false;
    }
}

    // Close response popup - navigation is handled by container via vehiclecomplete event
    

    
    // Methods for commercial use dialog
    openCommercialDialog() {
        this.showCommercialDialog = true;
    }
    
    closeCommercialDialog() {
        this.showCommercialDialog = false;
    }
    
    selectCommercialOption(event) {
        const selectedId = event.currentTarget.dataset.id;
        this.vehicleData.commercialUse = selectedId;
        this.closeCommercialDialog();
    }
    
    get selectedCommercialOption() {
        return this.commercialOptions.find(option => option.id === this.vehicleData.commercialUse);
    }
    
    getCommercialOptionClass(optionId) {
        const baseClass = 'commercial-option';
        return this.vehicleData.commercialUse === optionId 
            ? `${baseClass} selected` 
            : baseClass;
    }
    
    getIconClass(optionId) {
        return this.vehicleData.commercialUse === optionId
            ? '' 
            : 'hidden';
    }
    
    get getNonCommercialIconClass() {
        return this.vehicleData.commercialUse === 'NON-COMMERCIAL' ? '' : 'hidden';
    }
    
    get getLightIconClass() {
        return this.vehicleData.commercialUse === 'LIGHT' ? '' : 'hidden';
    }
    
    get getMediumIconClass() {
        return this.vehicleData.commercialUse === 'MEDIUM' ? '' : 'hidden';
    }
    
    get getHeavyIconClass() {
        return this.vehicleData.commercialUse === 'HEAVY' ? '' : 'hidden';
    }
    
    get commercialStatusText() {
        return this.selectedCommercialOption ? this.selectedCommercialOption.label : 'NON-COMMERCIAL';
    }
    
    get getNonCommercialClass() {
        return this.vehicleData.commercialUse === 'NON-COMMERCIAL' 
            ? 'commercial-option selected' 
            : 'commercial-option';
    }
    
    get getLightClass() {
        return this.vehicleData.commercialUse === 'LIGHT' 
            ? 'commercial-option selected' 
            : 'commercial-option';
    }
    
    get getMediumClass() {
        return this.vehicleData.commercialUse === 'MEDIUM' 
            ? 'commercial-option selected' 
            : 'commercial-option';
    }
    
    get getHeavyClass() {
        return this.vehicleData.commercialUse === 'HEAVY' 
            ? 'commercial-option selected' 
            : 'commercial-option';
    }

    // Method to update parent container with new applicationId
    updateParentApplicationId(newApplicationId) {
        if (newApplicationId && newApplicationId !== this._applicationId) {
            const updateEvent = new CustomEvent('applicationidupdate', {
                detail: { 
                    applicationId: newApplicationId,
                    vehicleId: this.vehicleId
                }
            });
            this.dispatchEvent(updateEvent);
        }
    }

    // Handle back button click
    handleBack() {
        // Save current data before navigating back
        this.saveDataToSession();
        
        // Dispatch back event with current data
        const backEvent = new CustomEvent('back', {
            detail: { data: this.getCurrentData() }
        });
        this.dispatchEvent(backEvent);
    }

    // Save data before navigation to ensure back button works
    saveDataBeforeNavigation() {
        // Save to session storage
        this.saveDataToSession();
        
        // Save to component state for immediate use
        const currentData = this.getCurrentData();
        console.log('🚚 Data saved before navigation:', currentData);
        
        return currentData;
    }
    
    // Navigation is now handled by the container component via vehiclecomplete event

    // Validate that all required data is present for navigation
    validateDataForNavigation() {
        const missingFields = this.validateFields();
        if (missingFields.length > 0) {
            this.errorMessage = `Please fill in all required fields before continuing: ${missingFields.join(', ')}`;
            this.showError = true;
            return false;
        }
        
        // Ensure we have at least basic vehicle data
        if (!this.vehicleData.vin || !this.vehicleData.year || !this.vehicleData.make || !this.vehicleData.model) {
            this.errorMessage = 'Please provide at least VIN, Year, Make, and Model before continuing.';
            this.showError = true;
            return false;
        }
        
        // Validate Commercial Vehicle Type when usage is Commercial/Business Use
        if (this.vehicleData.usageType === 'Commercial/Business Use' && !this.vehicleData.commercialVehicleType) {
            this.errorMessage = 'Please select a Commercial Vehicle Type for Commercial/Business Use vehicles.';
            this.showError = true;
            this.showCommercialVehicleTypeModal = true;
            return false;
        }

        // Validate manufacturer warranty fields when deferral option is selected
        const warrantyValidationErrors = this.validateManufacturerWarrantyFields();
        if (warrantyValidationErrors.length > 0) {
            this.errorMessage = warrantyValidationErrors.join(' ');
            this.showError = true;
            return false;
        }
        
        return true;
    }
    
    // Validate manufacturer warranty fields when deferral option is selected
    validateManufacturerWarrantyFields() {
        const errors = [];
        if (this.vehicleData.deferralOption === true) {
            if (!this.vehicleData.manufacturerWarrantyType || this.vehicleData.manufacturerWarrantyType.trim() === '') {
                errors.push('Manufacturer Warranty Type is required when Deferral Option is selected.');
            }
            if (!this.vehicleData.warrantyTerm || this.vehicleData.warrantyTerm.trim() === '') {
                errors.push('Warranty Term is required when Deferral Option is selected.');
            }
            if (!this.vehicleData.warrantyInServiceDate || this.vehicleData.warrantyInServiceDate.trim() === '') {
                errors.push('In-Service Date is required when Deferral Option is selected.');
            }
        }
        return errors;
    }

    // Clean data before sending to Apex
    cleanDataForApex(data) {
        const cleanedData = { ...data };
        
        // Convert empty strings to null for IDs
        if (cleanedData.vehicleId === '') cleanedData.vehicleId = null;
        if (cleanedData.applicationId === '') cleanedData.applicationId = null;
        
        // Ensure proper numeric formatting
        if (cleanedData.vehiclePurchasePrice) {
            cleanedData.vehiclePurchasePrice = parseFloat(cleanedData.vehiclePurchasePrice);
        }
        if (cleanedData.odometer) {
            cleanedData.odometer = parseFloat(cleanedData.odometer);
        }
        
        // Ensure proper boolean formatting
        cleanedData.businessCommercialUse = Boolean(cleanedData.businessCommercialUse);
        cleanedData.isBrandedRebuilt = Boolean(cleanedData.isBrandedRebuilt);
        
        // Ensure proper odometer unit and commercial use formatting
        cleanedData.odometerUnit = this.getOdometerUnitForSalesforce(cleanedData.odometerUnit);
        cleanedData.typeOfCommercialUse = this.getCommercialUseValueForSalesforce(cleanedData.commercialUse);
        
        return cleanedData;
    }
    
    // Validate data structure before sending to Apex
    validateDataStructure(data) {
        const requiredFields = ['vin', 'year', 'make', 'model'];
        const missingFields = requiredFields.filter(field => !data[field]);
        
        if (missingFields.length > 0) {
            throw new Error(`Missing required fields: ${missingFields.join(', ')}`);
        }
        
        return true;
    }

    // Restore data from session storage if available
    restoreFromSessionStorage() {
        try {
            // Try to restore from application-specific keys first
            let savedVehicleData = null;
            let savedVehicleId = null;
            let savedIsNewRecord = null;
            
            if (this._applicationId) {
                savedVehicleData = sessionStorage.getItem(`vehicleData_${this._applicationId}`);
                savedVehicleId = sessionStorage.getItem(`vehicleId_${this._applicationId}`);
                savedIsNewRecord = sessionStorage.getItem(`isNewRecord_${this._applicationId}`);
            }
            
            // Fallback to global keys if no application-specific data
            if (!savedVehicleData) {
                savedVehicleData = sessionStorage.getItem('vehicleData');
                savedVehicleId = sessionStorage.getItem('vehicleId');
                savedIsNewRecord = sessionStorage.getItem('isNewRecord');
            }
            
            if (savedVehicleData) {
                const parsedData = JSON.parse(savedVehicleData);
                // Ensure odometer unit is properly set
                if (!parsedData.odometerUnit || parsedData.odometerUnit === '') {
                    parsedData.odometerUnit = 'KM';
                }
                // Ensure commercial use is properly set
                if (!parsedData.commercialUse || parsedData.commercialUse === '') {
                    parsedData.commercialUse = 'NON-COMMERCIAL';
                }
                // Ensure isCommercial is properly set
                if (parsedData.isCommercial === undefined || parsedData.isCommercial === null) {
                    parsedData.isCommercial = false;
                }
                
                this.vehicleData = parsedData;
                console.log('🚚 Vehicle data restored from session:', this.vehicleData);
                console.log('🚚 Odometer Unit from session:', this.vehicleData.odometerUnit);
                console.log('🚚 Commercial Use from session:', this.vehicleData.commercialUse);
                console.log('🚚 Is Commercial from session:', this.vehicleData.isCommercial);
            }
            
            if (savedVehicleId && savedVehicleId !== 'null' && savedVehicleId !== '') {
                this.vehicleId = savedVehicleId;
                console.log('🚚 Vehicle ID restored from session:', this.vehicleId);
            }
            
            if (savedIsNewRecord) {
                this.isNewRecord = JSON.parse(savedIsNewRecord);
                console.log('🚚 IsNewRecord restored from session:', this.isNewRecord);
            }
        } catch (error) {
            console.error('Error restoring from session storage:', error);
        }
    }

    // Ensure component is properly initialized
    ensureInitialization() {
        if (!this.vehicleData || Object.keys(this.vehicleData).length === 0) {
            console.log('🚚 Initializing default values due to missing vehicle data');
            this.initializeDefaultValues();
        }
        
        console.log('🚚 Component initialization complete - applicationId:', this._applicationId, 'vehicleId:', this.vehicleId);
    }

    // Clear internal state for clean testing
    clearInternalState() {
        this.initializeDefaultValues();
        this.vehicleId = '';
        this.isNewRecord = true;
        this._applicationId = null; // Clear applicationId as well
        this.showError = false;
        this.errorMessage = '';
        this.showCommercialDialog = false;
        
        console.log('🧹 Vehicle component internal state cleared');
        console.log('🧹 applicationId cleared to:', this._applicationId);
    }
    
    // Handle application-level input changes
    // Handle sales representative change
    handleSalesRepChange(event) {
        const selectedContactId = event.detail.value;
        this.applicationData = {
            ...this.applicationData,
            salesRepresentative: selectedContactId
        };
        
        // If contact has license number, populate it (when Contact license field is available)
        // For now, keep dealerSalesId as manual input
        console.log('Sales representative changed to:', selectedContactId);
    }
    
    handleApplicationInputChange(event) {
        const fieldName = event.target.name;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        
        this.applicationData = {
            ...this.applicationData,
            [fieldName]: value
        };
        
        console.log('Application data updated:', fieldName, value);
        console.log('Updated applicationData:', this.applicationData);
    }
    
    // Toggle manufacturer warranty section
    toggleManufacturerWarranty() {
        this.showManufacturerWarranty = !this.showManufacturerWarranty;
    }
    
    // (handleUsageTypeChange consolidated above with Commercial Vehicle Type modal logic)
    
    // Method to handle applicationId changes from parent
    @api
    handleApplicationIdChange(newApplicationId) {
        console.log('🔄 ApplicationId changed to:', newApplicationId);
        
        if (newApplicationId === null || newApplicationId === '') {
            console.log('🔄 Clearing state for new application scenario');
            this.clearInternalState();
            this.initializeDefaultValues();
        } else {
            console.log('🔄 Loading data for existing application:', newApplicationId);
            // Update the applicationId
            this._applicationId = newApplicationId;
            
            // Load existing vehicle data for this application
            this.loadExistingVehicleData(newApplicationId);
        }
    }
    
    // Method called when tab is activated (from parent container)
    @api
    onTabActivated() {
        console.log('🚚 Vehicle tab activated for application:', this._applicationId);
        if (this._applicationId) {
            console.log('🚚 Loading fresh data from Salesforce for application:', this._applicationId);
            this.loadVehicleData();
        } else {
            console.log('⚠️ No applicationId available for vehicle data load');
        }
    }
    
    // Public method for debugging - manually load vehicle data
    @api
    debugLoadVehicleData() {
        console.log('🔧 Manual debug load requested');
        if (this._applicationId) {
            this.loadVehicleData();
        } else {
            console.log('⚠️ No applicationId available for debug load');
        }
    }
    
    // Public method for debugging - manually save vehicle data
    @api
    debugSaveVehicleData() {
        console.log('🔧 Manual debug save requested');
        if (this._applicationId) {
            this.saveVehicleDataToSalesforce();
        } else {
            console.log('⚠️ No applicationId available for debug save');
        }
    }
    
    // Public method for debugging - get current state
    @api
    getDebugInfo() {
        return {
            applicationId: this._applicationId,
            vehicleId: this.vehicleId,
            isNewRecord: this.isNewRecord,
            vehicleData: this.vehicleData,
            loading: this.loading,
            showError: this.showError,
            errorMessage: this.errorMessage
        };
    }
    
    // Method to validate date fields before saving
    validateDateFields() {
        const dateFields = ['dateSold', 'inServiceDate'];
        const errors = [];
        
        dateFields.forEach(field => {
            const value = this.vehicleData[field];
            if (value && value !== '' && value !== null) {
                // Check if it's a valid date format (YYYY-MM-DD)
                const dateRegex = /^\d{4}-\d{2}-\d{2}$/;
                if (!dateRegex.test(value.trim())) {
                    errors.push(`${field} has invalid date format. Please use YYYY-MM-DD format.`);
                } else {
                    // Additional validation to ensure it's a real date
                    const dateObj = new Date(value);
                    if (isNaN(dateObj.getTime())) {
                        errors.push(`${field} is not a valid date.`);
                    }
                }
            }
        });
        
        if (errors.length > 0) {
            this.showErrorMessage(errors.join(' '));
            return false;
        }
        
        return true;
    }

    // Method to save vehicle data to Salesforce
    async saveVehicleDataToSalesforce() {
        if (!this._applicationId) {
            console.log('⚠️ No applicationId available for saving');
            return false;
        }
        
        // Safety check: Ensure vehicleData exists and is properly initialized
        this.ensureVehicleDataInitialized();
        
        if (!this.vehicleData) {
            console.error('❌ Vehicle data is still null after initialization attempt');
            this.showErrorMessage('Vehicle data is not available. Please refresh the page and try again.');
            return false;
        }
        
        // Validate date fields before proceeding
        if (!this.validateDateFields()) {
            return false;
        }
        
        // Additional debugging to see the exact state
        console.log('💾 Saving vehicle data to Salesforce...');
        console.log('💾 Application ID:', this._applicationId);
        console.log('💾 Vehicle ID:', this.vehicleId);
        console.log('💾 Vehicle Data:', this.vehicleData);
        console.log('💾 Vehicle Data Type:', typeof this.vehicleData);
        console.log('💾 Vehicle Data Keys:', Object.keys(this.vehicleData || {}));
        
        // Check if vehicleData has the CRITICAL required fields that Apex needs
        const criticalRequiredFields = ['vin', 'year', 'make', 'model'];
        const missingCriticalFields = criticalRequiredFields.filter(field => {
            const value = this.vehicleData[field];
            const hasValue = value !== '' && value !== null && value !== undefined;
            console.log(`🔍 Critical field ${field}: "${value}" (hasValue: ${hasValue})`);
            return !hasValue;
        });
        
        if (missingCriticalFields.length > 0) {
            console.error('❌ Missing critical required fields:', missingCriticalFields);
            this.showErrorMessage(`Please fill in the required fields: ${missingCriticalFields.join(', ').toUpperCase()}`);
            return false;
        }
        
        // Additional check: ensure user has actually entered the critical data
        if (!this.hasUserEnteredData()) {
            console.error('❌ No user input detected in critical fields');
            this.showErrorMessage('Please enter VIN, Year, Make, and Model information before saving.');
            return false;
        }
        
        this.loading = true;
        this.showError = false;
        
        try {
            // Prepare data for Apex using the EXACT DTO structure
            console.log('🔍 Creating dataToSend object...');
            console.log('🔍 this.vehicleData.vin:', this.vehicleData.vin);
            console.log('🔍 this.vehicleData.year:', this.vehicleData.year);
            console.log('🔍 this.vehicleData.make:', this.vehicleData.make);
            console.log('🔍 this.vehicleData.model:', this.vehicleData.model);
            
            // Helper function to validate and format dates
            const formatDateForSalesforce = (dateValue) => {
                if (!dateValue || dateValue === '' || dateValue === null || dateValue === undefined) {
                    return null; // Return null for blank dates instead of empty string
                }
                
                // If it's already a valid date string, return it
                if (typeof dateValue === 'string' && dateValue.trim() !== '') {
                    // Validate the date format (YYYY-MM-DD)
                    const dateRegex = /^\d{4}-\d{2}-\d{2}$/;
                    if (dateRegex.test(dateValue.trim())) {
                        return dateValue.trim();
                    }
                }
                
                // If it's a Date object, format it
                if (dateValue instanceof Date) {
                    return dateValue.toISOString().split('T')[0]; // YYYY-MM-DD format
                }
                
                // If we can't determine a valid date, return null
                console.warn('⚠️ Invalid date value provided:', dateValue);
                return null;
            };

            const dataToSend = {
                vehicleId: this.vehicleId || '',
                applicationId: this._applicationId,
                stockNumber: this.vehicleData.stockNumber || '',
                vin: this.vehicleData.vin || '',
                vehicleIdentificationNumberVIN: this.vehicleData.vehicleIdentificationNumberVIN || '',
                year: this.vehicleData.year || '',
                make: this.vehicleData.make || '',
                model: this.vehicleData.model || '',
                trim: this.vehicleData.trim || '',
                dateVehicleSold: formatDateForSalesforce(this.vehicleData.dateSold),
                vehiclePurchasePrice: this.vehicleData.purchasePrice ? parseFloat(this.vehicleData.purchasePrice) : 0,
                isBrandedRebuilt: this.vehicleData.isBrandedRebuilt || false,
                businessCommercialUse: this.vehicleData.isCommercial || false,
                typeOfCommercialUse: this.vehicleData.commercialUse || 'NON-COMMERCIAL',
                // inServiceDate removed - using only warrantyInServiceDate for In_Service_Date__c
                odometer: this.vehicleData.odometerReading ? parseFloat(this.vehicleData.odometerReading) : 0,
                odometerUnit: this.vehicleData.odometerUnit || 'KM',
                // New Vehicle Details fields
                engine: this.vehicleData.engine || '',
                transmission: this.vehicleData.transmission || '',
                fuelType: this.vehicleData.fuelType || '',
                driveType: this.vehicleData.driveType || '',
                bodyStyle: this.vehicleData.bodyStyle || '',
                color: this.vehicleData.color || '',
                gvwr: this.vehicleData.gvwr || '',
                // Manufacturer Warranty fields
                manufacturerWarrantyType: this.vehicleData.manufacturerWarrantyType || '',
                warrantyTerm: this.vehicleData.warrantyTerm || '',
                warrantyInServiceDate: formatDateForSalesforce(this.vehicleData.warrantyInServiceDate),
                deferralOption: this.vehicleData.deferralOption || false,
                deliveryDate: formatDateForSalesforce(this.vehicleData.deliveryDate),
                lienHolder: this.vehicleData.lienHolder || '',
                usageType: this.vehicleData.usageType || '',
                commercialVehicleType: this.vehicleData.commercialVehicleType || '',
                // Application fields
                dealerCommentsNotes: this.applicationData.dealerCommentsNotes || '',
                showCommentsOnPrint: this.applicationData.showCommentsOnPrint || false,
                salesRepId: this.applicationData.salesRepresentative || '',
                dealerSalesId: this.applicationData.dealerSalesId || '',
                // Powersports storable fields
                vehicleCategory: this.vehicleData.vehicleCategory || '',
                vehicleSubType: this.vehicleData.vehicleSubType || '',
                engineCC: this.vehicleData.engineCC ? parseFloat(this.vehicleData.engineCC) : null,
                coolingType: this.vehicleData.coolingType || '',
                hoursUsage: this.vehicleData.hoursUsage ? parseFloat(this.vehicleData.hoursUsage) : null,
                vehicleClass: this.vehicleData.vehicleClass || '',
                // Powersports intake hours and brand tier
                intakeHours: this.vehicleData.intakeHours ? parseInt(this.vehicleData.intakeHours) : null,
                brandTier: this.vehicleData.brandTier || 'Standard'
            };
            
            console.log('🔍 dataToSend object created:', dataToSend);
            console.log('🔍 dataToSend.vin:', dataToSend.vin);
            console.log('🔍 dataToSend.year:', dataToSend.year);
            console.log('🔍 dataToSend.make:', dataToSend.make);
            console.log('🔍 dataToSend.model:', dataToSend.model);
            console.log('🔍 dataToSend.dateVehicleSold:', dataToSend.dateVehicleSold);
            // inServiceDate removed from save payload - using only warrantyInServiceDate
            console.log('🔍 Original dateSold value:', this.vehicleData.dateSold);
            
            // Log the actual data being sent to Apex
            console.log('💾 Data being sent to Apex:', dataToSend);
            console.log('💾 Data keys:', Object.keys(dataToSend));
            console.log('💾 Data values:', Object.values(dataToSend));
            
            // Debug specific required fields
            console.log('🔍 VIN field value:', this.vehicleData.vin);
            console.log('🔍 Year field value:', this.vehicleData.year);
            console.log('🔍 Make field value:', this.vehicleData.make);
            console.log('🔍 Model field value:', this.vehicleData.model);
            
            // Verify the dataToSend object has the required values
            if (!dataToSend.vin || !dataToSend.year || !dataToSend.make || !dataToSend.model) {
                console.error('❌ dataToSend object is missing required fields!');
                console.error('❌ dataToSend.vin:', dataToSend.vin);
                console.error('❌ dataToSend.year:', dataToSend.year);
                console.error('❌ dataToSend.make:', dataToSend.make);
                console.error('❌ dataToSend.model:', dataToSend.model);
                this.showErrorMessage('Data preparation failed. Please try again.');
                return false;
            }
            

            
            // Call Apex method with direct object structure
            console.log('💾 Calling Apex saveVehicleData with dataToSend:', JSON.stringify(dataToSend, null, 2));
            
            let result;
            try {
                result = await saveVehicleData({vehicleDataMap:dataToSend});
                console.log('💾 Apex save result:', result);
                console.log('💾 Apex save success:', result.success);
                console.log('💾 Apex save message:', result.message);
            } catch (apexError) {
                console.error('❌ Apex call failed:', apexError);
                console.error('❌ Apex error details:', JSON.stringify(apexError, null, 2));
                this.showErrorMessage('Failed to save vehicle data: ' + (apexError.message || 'Unknown error'));
                return false;
            }
            
            if (result.success) {
                // Update vehicle ID if it's a new record
                if (result.recordId) {
                    this.vehicleId = result.recordId;
                    console.log('💾 Vehicle ID updated:', this.vehicleId);
                }
                
                // Update application ID if it's a new application
                if (result.applicationId && result.applicationId !== this._applicationId) {
                    this._applicationId = result.applicationId;
                    console.log('💾 Application ID updated:', this._applicationId);
                }
                
                // Update vehicle data with the response data
                if (result.data) {
                    const responseData = result.data;
                    this.vehicleData = {
                        stockNumber: responseData.stockNumber || '',
                        vin: responseData.vin || '',
                        vehicleIdentificationNumberVIN: responseData.vehicleIdentificationNumberVIN || '',
                        year: responseData.year || '',
                        make: responseData.make || '',
                        model: responseData.model || '',
                        trim: responseData.trim || '',
                        dateSold: responseData.dateVehicleSold || '',
                        purchasePrice: responseData.vehiclePurchasePrice || '',
                        isCommercial: responseData.businessCommercialUse || false,
                        isBrandedRebuilt: responseData.brandedRebuilt || false,
                        inServiceDate: responseData.inServiceDate || '',
                        odometerReading: responseData.odometer || '',
                        odometerUnit: responseData.odometerUnit || 'KM',
                        commercialUse: responseData.typeOfCommercialUse || 'NON-COMMERCIAL'
                    };
                    console.log('💾 Vehicle data updated from response:', this.vehicleData);
                }
                
                // Save to session storage
                try {
                    this.saveDataToSession();
                } catch (sessionError) {
                    console.error('❌ Error saving to session storage:', sessionError);
                }
                
                // Show success message
                try {
                    this.showSuccessMessage('Vehicle information saved successfully!');
                } catch (messageError) {
                    console.error('❌ Error showing success message:', messageError);
                }
                
                // Fire vehicle completion event to unlock warranty tab and trigger navigation
                try {
                    this.dispatchEvent(new CustomEvent('vehiclecomplete', {
                        detail: { 
                            success: true,
                            vehicleData: this.vehicleData,
                            applicationId: this._applicationId
                        }
                    }));
                } catch (eventError) {
                    console.error('❌ Error dispatching vehiclecomplete event:', eventError);
                }
                
                return true; // Return true to indicate successful save
                
            } else {
                console.error('❌ Failed to save vehicle data:', result.message);
                this.showErrorMessage('Vehicle save failed - cannot proceed: ' + result.message);
                return false;
            }
            
        } catch (error) {
            console.error('❌ Error saving vehicle data:', error);
            
            this.errorMessage = 'Error saving vehicle data: ' + error.message;
            this.showError = true;
            return false;
        } finally {
            this.loading = false;
        }
    }
    
    // Notify parent container when vehicle data changes
    notifyParentOfDataChange() {
        // Dispatch event to notify parent that vehicle data has changed
        this.dispatchEvent(new CustomEvent('vehicledatachanged', {
            detail: {
                hasData: this.hasVehicleData(),
                vehicleData: this.vehicleData,
                applicationId: this._applicationId
            },
            bubbles: true,
            composed: true
        }));
        
        console.log('🔔 Notified parent of vehicle data change:', {
            hasData: this.hasVehicleData(),
            applicationId: this._applicationId
        });
    }

    // Check if vehicle form has meaningful data
    @api
    hasVehicleData() {
        // Check if essential vehicle fields have data
        const essentialFields = [
            'vehicleIdentificationNumberVIN',
            'year',
            'make',
            'model'
        ];
        
        const hasEssentialData = essentialFields.some(field => 
            this.vehicleData[field] && this.vehicleData[field].toString().trim() !== ''
        );
        
        console.log('🔍 Vehicle data check:', {
            hasEssentialData,
            essentialFields: essentialFields.map(field => ({
                field,
                value: this.vehicleData[field],
                hasValue: this.vehicleData[field] && this.vehicleData[field].toString().trim() !== ''
            }))
        });
        
        return hasEssentialData;
    }

    // Comprehensive form reset method
    @api
    resetForm() {
        console.log('🧹 Comprehensive form reset initiated');
        
        // Clear all internal state
        this.clearInternalState();
        
        // Reset all form fields to empty/default values
        this.vehicleData = {
            stockNumber: '',
            vin: '',
            vehicleIdentificationNumberVIN: '',
            year: '',
            make: '',
            model: '',
            trim: '',
            dateSold: '',
            purchasePrice: '',
            isCommercial: false,
            isBrandedRebuilt: false,
            inServiceDate: '',
            odometerReading: '',
            odometerUnit: 'KM',
            commercialUse: 'NON-COMMERCIAL'
        };
        
        // Reset all component properties
        this.vehicleId = '';
        this.isNewRecord = true;
        this._applicationId = null;
        
        // Clear all UI states
        this.showError = false;
        this.errorMessage = '';
        this.showCommercialDialog = false;
        this.loading = false;
        
        // Force re-render by updating tracked properties
        this.vehicleData = { ...this.vehicleData };
        
        console.log('🧹 Form completely reset - all fields cleared');
        console.log('�� Current state:', {
            applicationId: this._applicationId,
            vehicleId: this.vehicleId,
            isNewRecord: this.isNewRecord,
            vehicleData: this.vehicleData
        });
    }

    // Ensure clean state for new applications
    ensureCleanStateForNewApplication() {
        console.log('🧹 Ensuring clean state for new application');
        
        // Clear all internal state
        this.clearInternalState();
        
        // Initialize with default values
        this.initializeDefaultValues();
        
        // Clear applicationId to ensure this is treated as a new application
        this._applicationId = null;
        
        // Clear any error states
        this.showError = false;
        this.errorMessage = '';
        
        // Clear any popup states
        
        // Navigation is handled by container component
        
        console.log('🧹 Clean state established for new application');
        console.log('🧹 applicationId cleared to:', this._applicationId);
    }

    // Method to test vehicle form functionality from browser console
    // Usage: In browser console, type: document.querySelector('c-dealer-portal-vehicle').testVehicleForm()

    

    
    // Show success message
    showSuccessMessage(message) {
        this.successMessage = message;
        this.showSuccess = true;
        this.showError = false; // Hide any existing error messages
        console.log('✅ Success:', message);
        
        // Auto-hide success message after 5 seconds
        setTimeout(() => {
            this.showSuccess = false;
            this.successMessage = '';
        }, 5000);
    }
    
    // Show error message
    showErrorMessage(message) {
        this.errorMessage = message;
        this.showError = true;
        console.error('❌ Error:', message);
    }
    
    // Close error modal
    closeErrorModal() {
        this.showError = false;
        this.errorMessage = '';
    }
    
    // Close success message
    closeSuccessMessage() {
        this.showSuccess = false;
        this.successMessage = '';
    }
    
    // Show more information modal
    handleShowMoreInfo() {
        console.log('🔍 More Info button clicked');
        console.log('🔍 additionalVehicleData:', this.additionalVehicleData);
        console.log('🔍 hasVehicleData:', this.hasVehicleData);
        
        if (!this.additionalVehicleData) {
            console.log('❌ No additional vehicle data available');
            return;
        }
        
        this.processAdditionalVehicleData();
        this.showMoreInfoModal = true;
        console.log('✅ Modal should be showing now');
    }
    
    // Close more information modal
    closeMoreInfoModal() {
        this.showMoreInfoModal = false;
    }
    
    // Process additional vehicle data into organized sections
    processAdditionalVehicleData() {
        if (!this.additionalVehicleData) {
            this.hasAdditionalInfo = false;
            return;
        }

        // Powersports vehicles get their own dedicated modal layout
        if (this.isPowersports && this.powersportsModalData) {
            const pd = this.powersportsModalData;
            const fmt = (v) => (v != null && v !== undefined) ? '$' + Number(v).toLocaleString('en-CA') : 'N/A';
            this.additionalInfoSections = [
                {
                    key: 'ps-ident', title: 'Vehicle Identification',
                    items: [
                        { key: 'vin',    label: 'VIN',         value: this.vehicleData.vehicleIdentificationNumberVIN },
                        { key: 'year',   label: 'Year',        value: this.vehicleData.year },
                        { key: 'make',   label: 'Make',        value: this.vehicleData.make },
                        { key: 'model',  label: 'Model',       value: this.vehicleData.model },
                        { key: 'class',  label: 'Class',       value: pd.className },
                        { key: 'mclass', label: 'Model Class', value: pd.modelClass },
                        { key: 'uvc',    label: 'UVC',         value: pd.uvc }
                    ].filter(f => f.value)
                },
                {
                    key: 'ps-engine', title: 'Engine',
                    items: [
                        { key: 'cyl',  label: 'Cylinders',           value: pd.cylinders },
                        { key: 'disp', label: 'Engine Displacement',  value: pd.displacement ? pd.displacement + ' cc' : null }
                    ].filter(f => f.value)
                },
                {
                    key: 'ps-val', title: 'Valuation (Canadian Black Book)',
                    items: [
                        { key: 'whole',  label: 'Wholesale Average', value: fmt(pd.wholeAvg) },
                        { key: 'retail', label: 'Retail Average',    value: fmt(pd.retailAvg) },
                        { key: 'clean',  label: 'Trade-in Clean',    value: fmt(pd.tradeinClean) },
                        { key: 'fair',   label: 'Trade-in Fair',     value: fmt(pd.tradeinFair) },
                        { key: 'fin',    label: 'Finance Advance',   value: fmt(pd.finadv) },
                        { key: 'msrp',   label: 'MSRP',              value: fmt(pd.msrp) }
                    ]
                },
                {
                    key: 'ps-pub', title: 'Publication',
                    items: [
                        { key: 'pub', label: 'Publish Date', value: pd.publishDate }
                    ].filter(f => f.value)
                }
            ].filter(s => s.items.length > 0);
            this.hasAdditionalInfo = this.additionalInfoSections.length > 0;
            return;
        }

        const data = this.additionalVehicleData;
        const sections = [];
        
        // Fields already displayed on the main vehicle page (exclude these)
        const excludedFields = ['vin', 'year', 'make', 'model', 'trim'];
        
        console.log('🔍 Processing additional vehicle data:', data);
        console.log('🔍 Available data fields:', Object.keys(data));
        console.log('🔍 Excluded fields (already on main page):', excludedFields);
        
        // Debug: Show all field values
        console.log('🔍 ALL FIELD VALUES:');
        Object.keys(data).forEach(key => {
            console.log(`  ${key}: "${data[key]}" (type: ${typeof data[key]})`);
        });
        
        // Debug: Count non-null fields
        const nonNullFields = Object.keys(data).filter(key => {
            const value = data[key];
            return value && value !== 'null' && value !== 'undefined' && value !== '' && value !== 'Not Applicable';
        });
        console.log('🔍 Non-null fields count:', nonNullFields.length);
        console.log('🔍 Non-null fields:', nonNullFields);
        
        // Vehicle Information Section (only additional fields not on main page)
        const vehicleInfo = [];
        console.log('🔍 Checking additional vehicle info fields:');
        console.log('  - bodyClass:', data.bodyClass);
        console.log('  - vehicleType:', data.vehicleType);
        console.log('  - manufacturerName:', data.manufacturerName);
        console.log('  - origin:', data.origin);
        console.log('  - doors:', data.doors);
        console.log('  - seats:', data.seats);
        console.log('  - seatRows:', data.seatRows);
        
        if (data.bodyClass && data.bodyClass !== 'null' && data.bodyClass !== '') {
            vehicleInfo.push({ key: 'bodyClass', label: 'Body Class', value: data.bodyClass });
        }
        if (data.vehicleType && data.vehicleType !== 'null' && data.vehicleType !== '') {
            vehicleInfo.push({ key: 'vehicleType', label: 'Vehicle Type', value: data.vehicleType });
        }
        if (data.manufacturerName && data.manufacturerName !== 'null' && data.manufacturerName !== '') {
            vehicleInfo.push({ key: 'manufacturerName', label: 'Manufacturer', value: data.manufacturerName });
        }
        if (data.origin && data.origin !== 'null' && data.origin !== '') {
            vehicleInfo.push({ key: 'origin', label: 'Origin', value: data.origin });
        }
        if (data.series && data.series !== 'null' && data.series !== '') {
            vehicleInfo.push({ key: 'series', label: 'Series', value: data.series });
        }
        if (data.style && data.style !== 'null' && data.style !== '') {
            vehicleInfo.push({ key: 'style', label: 'Style', value: data.style });
        }
        if (data.vehicleDescriptor && data.vehicleDescriptor !== 'null' && data.vehicleDescriptor !== '') {
            vehicleInfo.push({ key: 'vehicleDescriptor', label: 'Vehicle Descriptor', value: data.vehicleDescriptor });
        }
        if (data.destinationMarket && data.destinationMarket !== 'null' && data.destinationMarket !== '') {
            vehicleInfo.push({ key: 'destinationMarket', label: 'Destination Market', value: data.destinationMarket });
        }
        
        if (vehicleInfo.length > 0) {
            sections.push({ key: 'vehicleInfo', title: 'Vehicle Information', items: vehicleInfo });
        }
        
        // Engine & Performance Section
        const engineInfo = [];
        if (data.engineModel && data.engineModel !== 'null' && data.engineModel !== '') {
            engineInfo.push({ key: 'engineModel', label: 'Engine Model', value: data.engineModel });
        }
        if (data.engineCylinders && data.engineCylinders !== 'null' && data.engineCylinders !== '') {
            engineInfo.push({ key: 'engineCylinders', label: 'Cylinders', value: data.engineCylinders });
        }
        if (data.engineDisplacement && data.engineDisplacement !== 'null' && data.engineDisplacement !== '') {
            engineInfo.push({ key: 'engineDisplacement', label: 'Displacement (L)', value: data.engineDisplacement });
        }
        if (data.engineDisplacementCC && data.engineDisplacementCC !== 'null' && data.engineDisplacementCC !== '') {
            engineInfo.push({ key: 'engineDisplacementCC', label: 'Displacement (CC)', value: data.engineDisplacementCC });
        }
        if (data.engineDisplacementCI && data.engineDisplacementCI !== 'null' && data.engineDisplacementCI !== '') {
            engineInfo.push({ key: 'engineDisplacementCI', label: 'Displacement (CI)', value: data.engineDisplacementCI });
        }
        if (data.enginePower && data.enginePower !== 'null' && data.enginePower !== '') {
            engineInfo.push({ key: 'enginePower', label: 'Power (hp)', value: data.enginePower });
        }
        if (data.enginePowerTo && data.enginePowerTo !== 'null' && data.enginePowerTo !== '') {
            engineInfo.push({ key: 'enginePowerTo', label: 'Power Range (hp)', value: data.enginePowerTo });
        }
        if (data.engineStrokeCycles && data.engineStrokeCycles !== 'null' && data.engineStrokeCycles !== '') {
            engineInfo.push({ key: 'engineStrokeCycles', label: 'Stroke Cycles', value: data.engineStrokeCycles });
        }
        if (data.engineConfiguration && data.engineConfiguration !== 'null' && data.engineConfiguration !== '') {
            engineInfo.push({ key: 'engineConfiguration', label: 'Engine Configuration', value: data.engineConfiguration });
        }
        if (data.engineManufacturer && data.engineManufacturer !== 'null' && data.engineManufacturer !== '') {
            engineInfo.push({ key: 'engineManufacturer', label: 'Engine Manufacturer', value: data.engineManufacturer });
        }
        if (data.otherEngineInfo && data.otherEngineInfo !== 'null' && data.otherEngineInfo !== '') {
            engineInfo.push({ key: 'otherEngineInfo', label: 'Other Engine Info', value: data.otherEngineInfo });
        }
        if (data.turbo && data.turbo !== 'null' && data.turbo !== '') {
            engineInfo.push({ key: 'turbo', label: 'Turbo', value: data.turbo });
        }
        if (data.topSpeed && data.topSpeed !== 'null' && data.topSpeed !== '') {
            engineInfo.push({ key: 'topSpeed', label: 'Top Speed (MPH)', value: data.topSpeed });
        }
        if (data.electrificationLevel && data.electrificationLevel !== 'null' && data.electrificationLevel !== '') {
            engineInfo.push({ key: 'electrificationLevel', label: 'Electrification Level', value: data.electrificationLevel });
        }
        if (data.coolingType && data.coolingType !== 'null' && data.coolingType !== '') {
            engineInfo.push({ key: 'coolingType', label: 'Cooling Type', value: data.coolingType });
        }
        if (data.valveTrainDesign && data.valveTrainDesign !== 'null' && data.valveTrainDesign !== '') {
            engineInfo.push({ key: 'valveTrainDesign', label: 'Valve Train Design', value: data.valveTrainDesign });
        }
        if (data.fuelType && data.fuelType !== 'null' && data.fuelType !== '') {
            engineInfo.push({ key: 'fuelType', label: 'Fuel Type', value: data.fuelType });
        }
        if (data.fuelTypeSecondary && data.fuelTypeSecondary !== 'null' && data.fuelTypeSecondary !== '') {
            engineInfo.push({ key: 'fuelTypeSecondary', label: 'Secondary Fuel Type', value: data.fuelTypeSecondary });
        }
        if (data.fuelDeliveryType && data.fuelDeliveryType !== 'null' && data.fuelDeliveryType !== '') {
            engineInfo.push({ key: 'fuelDeliveryType', label: 'Fuel Delivery Type', value: data.fuelDeliveryType });
        }
        if (data.fuelTankType && data.fuelTankType !== 'null' && data.fuelTankType !== '') {
            engineInfo.push({ key: 'fuelTankType', label: 'Fuel Tank Type', value: data.fuelTankType });
        }
        if (data.fuelTankMaterial && data.fuelTankMaterial !== 'null' && data.fuelTankMaterial !== '') {
            engineInfo.push({ key: 'fuelTankMaterial', label: 'Fuel Tank Material', value: data.fuelTankMaterial });
        }
        
        if (engineInfo.length > 0) {
            sections.push({ key: 'engineInfo', title: 'Engine & Performance', items: engineInfo });
        }
        
        // Transmission & Drivetrain Section
        const transmissionInfo = [];
        if (data.transmissionStyle && data.transmissionStyle !== 'null' && data.transmissionStyle !== '') {
            transmissionInfo.push({ key: 'transmissionStyle', label: 'Transmission Style', value: data.transmissionStyle });
        }
        if (data.transmissionSpeeds && data.transmissionSpeeds !== 'null' && data.transmissionSpeeds !== '') {
            transmissionInfo.push({ key: 'transmissionSpeeds', label: 'Transmission Speeds', value: data.transmissionSpeeds });
        }
        if (data.driveType && data.driveType !== 'null' && data.driveType !== '') {
            transmissionInfo.push({ key: 'driveType', label: 'Drive Type', value: data.driveType });
        }
        if (data.axles && data.axles !== 'null' && data.axles !== '') {
            transmissionInfo.push({ key: 'axles', label: 'Axles', value: data.axles });
        }
        if (data.axleConfiguration && data.axleConfiguration !== 'null' && data.axleConfiguration !== '') {
            transmissionInfo.push({ key: 'axleConfiguration', label: 'Axle Configuration', value: data.axleConfiguration });
        }
        
        if (transmissionInfo.length > 0) {
            sections.push({ key: 'transmissionInfo', title: 'Transmission', items: transmissionInfo });
        }
        
        // Safety Features Section
        const safetyInfo = [];
        if (data.abs && data.abs !== 'null' && data.abs !== '') {
            safetyInfo.push({ key: 'abs', label: 'Anti-lock Braking System (ABS)', value: data.abs });
        }
        if (data.esc && data.esc !== 'null' && data.esc !== '') {
            safetyInfo.push({ key: 'esc', label: 'Electronic Stability Control (ESC)', value: data.esc });
        }
        if (data.tractionControl && data.tractionControl !== 'null' && data.tractionControl !== '') {
            safetyInfo.push({ key: 'tractionControl', label: 'Traction Control', value: data.tractionControl });
        }
        if (data.frontAirbagLocations && data.frontAirbagLocations !== 'null' && data.frontAirbagLocations !== '') {
            safetyInfo.push({ key: 'frontAirbagLocations', label: 'Front Air Bag Locations', value: data.frontAirbagLocations });
        }
        if (data.sideAirbagLocations && data.sideAirbagLocations !== 'null' && data.sideAirbagLocations !== '') {
            safetyInfo.push({ key: 'sideAirbagLocations', label: 'Side Air Bag Locations', value: data.sideAirbagLocations });
        }
        if (data.curtainAirbagLocations && data.curtainAirbagLocations !== 'null' && data.curtainAirbagLocations !== '') {
            safetyInfo.push({ key: 'curtainAirbagLocations', label: 'Curtain Air Bag Locations', value: data.curtainAirbagLocations });
        }
        if (data.seatCushionAirbagLocations && data.seatCushionAirbagLocations !== 'null' && data.seatCushionAirbagLocations !== '') {
            safetyInfo.push({ key: 'seatCushionAirbagLocations', label: 'Seat Cushion Air Bag Locations', value: data.seatCushionAirbagLocations });
        }
        if (data.kneeAirbagLocations && data.kneeAirbagLocations !== 'null' && data.kneeAirbagLocations !== '') {
            safetyInfo.push({ key: 'kneeAirbagLocations', label: 'Knee Air Bag Locations', value: data.kneeAirbagLocations });
        }
        if (data.tpmsType && data.tpmsType !== 'null' && data.tpmsType !== '') {
            safetyInfo.push({ key: 'tpmsType', label: 'TPMS Type', value: data.tpmsType });
        }
        if (data.activeSafetySystemNote && data.activeSafetySystemNote !== 'null' && data.activeSafetySystemNote !== '') {
            safetyInfo.push({ key: 'activeSafetySystemNote', label: 'Active Safety System Note', value: data.activeSafetySystemNote });
        }
        
        if (safetyInfo.length > 0) {
            sections.push({ key: 'safetyInfo', title: 'Safety Features', items: safetyInfo });
        }
        
        // Dimensions & Weight Section
        const dimensionsInfo = [];
        if (data.doors && data.doors !== 'null' && data.doors !== '') {
            dimensionsInfo.push({ key: 'doors', label: 'Doors', value: data.doors });
        }
        if (data.windows && data.windows !== 'null' && data.windows !== '') {
            dimensionsInfo.push({ key: 'windows', label: 'Windows', value: data.windows });
        }
        if (data.wheelBase && data.wheelBase !== 'null' && data.wheelBase !== '') {
            dimensionsInfo.push({ key: 'wheelBase', label: 'Wheelbase (inches)', value: data.wheelBase });
        }
        if (data.wheelBaseFrom && data.wheelBaseFrom !== 'null' && data.wheelBaseFrom !== '') {
            dimensionsInfo.push({ key: 'wheelBaseFrom', label: 'Wheelbase Range From', value: data.wheelBaseFrom });
        }
        if (data.wheelBaseTo && data.wheelBaseTo !== 'null' && data.wheelBaseTo !== '') {
            dimensionsInfo.push({ key: 'wheelBaseTo', label: 'Wheelbase Range To', value: data.wheelBaseTo });
        }
        if (data.wheelBaseType && data.wheelBaseType !== 'null' && data.wheelBaseType !== '') {
            dimensionsInfo.push({ key: 'wheelBaseType', label: 'Wheelbase Type', value: data.wheelBaseType });
        }
        if (data.trackWidth && data.trackWidth !== 'null' && data.trackWidth !== '') {
            dimensionsInfo.push({ key: 'trackWidth', label: 'Track Width (inches)', value: data.trackWidth });
        }
        if (data.curbWeight && data.curbWeight !== 'null' && data.curbWeight !== '') {
            dimensionsInfo.push({ key: 'curbWeight', label: 'Curb Weight (pounds)', value: data.curbWeight });
        }
        if (data.gvwrFrom && data.gvwrFrom !== 'null' && data.gvwrFrom !== '') {
            dimensionsInfo.push({ key: 'gvwrFrom', label: 'GVWR From', value: data.gvwrFrom });
        }
        if (data.gvwrTo && data.gvwrTo !== 'null' && data.gvwrTo !== '') {
            dimensionsInfo.push({ key: 'gvwrTo', label: 'GVWR To', value: data.gvwrTo });
        }
        if (data.gcvwrFrom && data.gcvwrFrom !== 'null' && data.gcvwrFrom !== '') {
            dimensionsInfo.push({ key: 'gcvwrFrom', label: 'GCVWR From', value: data.gcvwrFrom });
        }
        if (data.gcvwrTo && data.gcvwrTo !== 'null' && data.gcvwrTo !== '') {
            dimensionsInfo.push({ key: 'gcvwrTo', label: 'GCVWR To', value: data.gcvwrTo });
        }
        if (data.bedLength && data.bedLength !== 'null' && data.bedLength !== '') {
            dimensionsInfo.push({ key: 'bedLength', label: 'Bed Length (inches)', value: data.bedLength });
        }
        if (data.bedType && data.bedType !== 'null' && data.bedType !== '') {
            dimensionsInfo.push({ key: 'bedType', label: 'Bed Type', value: data.bedType });
        }
        if (data.cabType && data.cabType !== 'null' && data.cabType !== '') {
            dimensionsInfo.push({ key: 'cabType', label: 'Cab Type', value: data.cabType });
        }
        
        if (dimensionsInfo.length > 0) {
            sections.push({ key: 'dimensionsInfo', title: 'Dimensions & Weight', items: dimensionsInfo });
        }
        
        // Seating & Interior Section
        const seatingInfo = [];
        if (data.seats && data.seats !== 'null' && data.seats !== '') {
            seatingInfo.push({ key: 'seats', label: 'Number of Seats', value: data.seats });
        }
        if (data.seatRows && data.seatRows !== 'null' && data.seatRows !== '') {
            seatingInfo.push({ key: 'seatRows', label: 'Number of Seat Rows', value: data.seatRows });
        }
        if (data.seatBeltType && data.seatBeltType !== 'null' && data.seatBeltType !== '') {
            seatingInfo.push({ key: 'seatBeltType', label: 'Seat Belt Type', value: data.seatBeltType });
        }
        if (data.otherRestraintSystemInfo && data.otherRestraintSystemInfo !== 'null' && data.otherRestraintSystemInfo !== '') {
            seatingInfo.push({ key: 'otherRestraintSystemInfo', label: 'Other Restraint System Info', value: data.otherRestraintSystemInfo });
        }
        if (data.pretensioner && data.pretensioner !== 'null' && data.pretensioner !== '') {
            seatingInfo.push({ key: 'pretensioner', label: 'Pretensioner', value: data.pretensioner });
        }
        if (data.entertainmentSystem && data.entertainmentSystem !== 'null' && data.entertainmentSystem !== '') {
            seatingInfo.push({ key: 'entertainmentSystem', label: 'Entertainment System', value: data.entertainmentSystem });
        }
        if (data.steeringLocation && data.steeringLocation !== 'null' && data.steeringLocation !== '') {
            seatingInfo.push({ key: 'steeringLocation', label: 'Steering Location', value: data.steeringLocation });
        }
        
        if (seatingInfo.length > 0) {
            sections.push({ key: 'seatingInfo', title: 'Seating & Interior', items: seatingInfo });
        }
        
        // Manufacturing Information Section
        const manufacturingInfo = [];
        if (data.plantCountry && data.plantCountry !== 'null' && data.plantCountry !== '') {
            manufacturingInfo.push({ key: 'plantCountry', label: 'Plant Country', value: data.plantCountry });
        }
        if (data.plantState && data.plantState !== 'null' && data.plantState !== '') {
            manufacturingInfo.push({ key: 'plantState', label: 'Plant State', value: data.plantState });
        }
        if (data.plantCity && data.plantCity !== 'null' && data.plantCity !== '') {
            manufacturingInfo.push({ key: 'plantCity', label: 'Plant City', value: data.plantCity });
        }
        if (data.plantCompanyName && data.plantCompanyName !== 'null' && data.plantCompanyName !== '') {
            manufacturingInfo.push({ key: 'plantCompanyName', label: 'Plant Company Name', value: data.plantCompanyName });
        }
        if (data.nonLandUse && data.nonLandUse !== 'null' && data.nonLandUse !== '') {
            manufacturingInfo.push({ key: 'nonLandUse', label: 'Non-Land Use', value: data.nonLandUse });
        }
        
        if (manufacturingInfo.length > 0) {
            sections.push({ key: 'manufacturingInfo', title: 'Manufacturing Information', items: manufacturingInfo });
        }
        
        // If no sections were created, create a fallback section with all available data (excluding main page fields)
        if (sections.length === 0) {
            console.log('⚠️ No sections created, creating fallback with additional data only');
            const fallbackItems = [];
            console.log('🔍 Processing fallback items...');
            for (const [key, value] of Object.entries(data)) {
                console.log(`🔍 Checking fallback field: ${key} = "${value}" (type: ${typeof value})`);
                // Skip fields already on main page and null/empty values
                if (!excludedFields.includes(key) && 
                    value && 
                    value !== '' && 
                    value !== 'null' && 
                    value !== 'undefined' && 
                    value !== 'Not Applicable' &&
                    value !== null) {
                    console.log(`✅ Adding fallback item: ${key} = "${value}"`);
                    fallbackItems.push({ 
                        key: key, 
                        label: key.replace(/([A-Z])/g, ' $1').replace(/^./, str => str.toUpperCase()), 
                        value: value 
                    });
                } else {
                    console.log(`❌ Skipping fallback item: ${key} = "${value}" (excluded or null)`);
                }
            }
            console.log('🔍 Total fallback items created:', fallbackItems.length);
            if (fallbackItems.length > 0) {
                sections.push({ key: 'fallback', title: 'Additional Vehicle Data', items: fallbackItems });
            }
        }
        
        this.additionalInfoSections = sections;
        this.hasAdditionalInfo = sections.length > 0;
        
        console.log('🔍 Created sections:', sections);
        console.log('🔍 hasAdditionalInfo:', this.hasAdditionalInfo);
        console.log('🔍 Number of sections:', sections.length);
    }
    
    // Save vehicle data to session storage
    saveVehicleDataToSessionStorage() {
        if (this._applicationId) {
            const key = `vehicleData_${this._applicationId}`;
            sessionStorage.setItem(key, JSON.stringify(this.vehicleData));
            console.log('💾 Vehicle data saved to session storage for application:', this._applicationId);
        }
    }
    
    // Handle next button click - navigate to next tab
    handleNext() {
        console.log('⏭️ Next button clicked from vehicle component');
        const navigateEvent = new CustomEvent('navigate', {
            detail: { tab: 'warranty' },
            bubbles: true
        });
        this.dispatchEvent(navigateEvent);
    }
    

}