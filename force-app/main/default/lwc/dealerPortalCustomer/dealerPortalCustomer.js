import { LightningElement, track, api } from 'lwc';
import getCustomerData from '@salesforce/apex/DealerPortalCustomerController.getCustomerData';
import saveCustomerData from '@salesforce/apex/DealerPortalCustomerController.saveCustomerData';

export default class DealerPortalCustomer extends LightningElement {
    _applicationId;
    @api isLocked = false;
    
    @track firstName = '';
    @track lastName = '';
    @track email = '';
    @track phone = '';
    @track streetAddress = '';
    @track city = '';
    @track province = '';
    @track postalCode = '';
    @track country = '';
    @track coBuyerFirstName = '';
    @track coBuyerLastName = '';
    @track coBuyerStreetAddress = '';
    @track coBuyerCity = '';
    @track coBuyerProvince = '';
    @track coBuyerPostalCode = '';
    @track coBuyerCountry = '';
    @track coBuyerEmail = '';
    @track coBuyerPhone = '';
    @track licenseNumber = '';
    @track licenseProvince = '';
    @track licenseExpiry = '';
    @track companyBusiness = '';
    @track businessNumber = '';
    @track insuranceProvider = '';
    @track insurancePolicy = '';
    @track companyProvince = '';
    @track companyEmail = '';
    @track companyContactName = '';
    @track companyBusinessPhone = '';
    @track companyBusinessAltPhone = '';
    @track companyBusinessAddress = '';
    @track companyBusinessCity = '';
    @track companyBusinessPostalCode = '';
    @track companyBusinessCountry = '';
    @track showError = false;
    @track errorMessage = '';
    
    // Getter for field disabled state based on lock status
    get fieldDisabled() {
        return this.isLocked;
    }
    
    // Getter and setter for applicationId to handle changes
    @api
    get applicationId() {
        return this._applicationId;
    }
    
    set applicationId(value) {
        if (this._applicationId !== value) {
            this._applicationId = value;
            console.log('🔄 Customer ApplicationId changed from', this._applicationId, 'to', value);
            
            // Clear existing data when application changes
            if (value) {
                this.clearCustomerData();
                this.loadCustomerData();
            }
        }
    }
    
    // Method to clear customer data for new application
    clearCustomerData() {
        console.log('🧹 Clearing customer data for new application');
        this.firstName = '';
        this.lastName = '';
        this.email = '';
        this.phone = '';
        this.streetAddress = '';
        this.city = '';
        this.province = '';
        this.postalCode = '';
        this.country = '';
        this.coBuyerFirstName = '';
        this.coBuyerLastName = '';
        this.coBuyerStreetAddress = '';
        this.coBuyerCity = '';
        this.coBuyerProvince = '';
        this.coBuyerPostalCode = '';
        this.coBuyerCountry = '';
        this.coBuyerEmail = '';
        this.coBuyerPhone = '';
        this.licenseNumber = '';
        this.licenseProvince = '';
        this.licenseExpiry = '';
        this.companyBusiness = '';
        this.businessNumber = '';
        this.insuranceProvider = '';
        this.insurancePolicy = '';
        this.companyProvince = '';
        this.companyEmail = '';
        this.companyContactName = '';
        this.companyBusinessPhone = '';
        this.companyBusinessAltPhone = '';
        this.companyBusinessAddress = '';
        this.companyBusinessCity = '';
        this.companyBusinessPostalCode = '';
        this.companyBusinessCountry = '';
        
        // Clear session storage for this application
        if (this._applicationId) {
            sessionStorage.removeItem(`customerData_${this._applicationId}`);
        }
    }
    
    // Method to load customer data via Apex first, then session storage as fallback
    async loadCustomerData() {
        if (!this._applicationId) {
            console.log('⚠️ No applicationId provided, skipping data load');
            return;
        }
        
        console.log('📥 Loading customer data for application:', this._applicationId);
        
        try {
            // First, try to get data from Salesforce via Apex
            console.log('🌐 Attempting to load customer data from Salesforce...');
            const customerData = await getCustomerData({ applicationId: this._applicationId });
            
            if (customerData && Object.keys(customerData).length > 0) {
                console.log('✅ Customer data loaded from Salesforce:', customerData);
                await this.populateFormFields(customerData);
                
                // Save to session storage for quick access
                this.saveDataToSession();
                return;
            } else {
                console.log('📋 No customer data found in Salesforce, trying session storage...');
            }
        } catch (error) {
            console.error('❌ Error loading customer data from Salesforce:', error);
            this.showError = true;
            this.errorMessage = 'Unable to load customer information. Please try refreshing the page.';
        }
        
        // Fallback to session storage if Apex fails or returns no data
        try {
            const savedData = sessionStorage.getItem(`customerData_${this._applicationId}`);
            if (savedData) {
                const parsedData = JSON.parse(savedData);
                console.log('📥 Customer data restored from session storage for application:', this._applicationId);
                await this.populateFormFields(parsedData);
            } else {
                console.log('📥 No saved customer data found for application:', this._applicationId);
            }
        } catch (error) {
            console.error('❌ Error parsing customer data from session storage:', error);
        }
    }
    
    // Helper method to populate form fields from data object
    async populateFormFields(data) {
        debugger;
        this.firstName = data.firstName || data.First_Name__c || '';
        this.lastName = data.lastName || data.Last_Name__c || '';
        this.email = data.email || data.Email__c || '';
        this.phone = data.phone || data.Phone__c || '';
        this.streetAddress = data.streetAddress || data.Street_Address__c || '';
        this.city = data.city || data.City__c || '';
        this.province = data.province || data.Province__c || '';
        this.postalCode = data.postalCode || data.Postal_Code__c || '';
        this.country = data.country || data.Country__c || '';
        this.coBuyerFirstName = data.coBuyerFirstName || '';
        this.coBuyerLastName = data.coBuyerLastName || '';
        this.coBuyerStreetAddress = data.coBuyerStreetAddress || '';
        this.coBuyerCity = data.coBuyerCity || '';
        this.coBuyerProvince = data.coBuyerProvince || '';
        this.coBuyerPostalCode = data.coBuyerPostalCode || '';
        this.coBuyerCountry = data.coBuyerCountry || '';
        this.coBuyerEmail = data.coBuyerEmail || data.Co_Buyer_Email__c || '';
        this.coBuyerPhone = data.coBuyerPhone || data.Co_Buyer_Phone__c || '';
        this.licenseNumber = data.licenseNumber || data.License_Number__c || '';
        this.licenseProvince = data.licenseProvince || data.License_Province__c || '';
        this.licenseExpiry = data.licenseExpiry || data.License_Expiry__c || '';
        this.companyBusiness = data.companyBusiness || data.Company_Business__c || '';        this.businessNumber = data.businessNumber || data.Business_No_License__c || '';        this.insuranceProvider = data.insuranceProvider || data.Insurance_Provider__c || '';
        this.insurancePolicy = data.insurancePolicy || data.Insurance_Policy__c || '';
        this.companyProvince = data.companyProvince || data.Company_Province__c || '';
        this.companyEmail = data.companyEmail || data.Company_E_Mail_Address__c || '';
        this.companyContactName = data.companyContactName || data.Company_Contact_Name__c || '';
        this.companyBusinessPhone = data.companyBusinessPhone || data.Company_Business_Phone__c || '';
        this.companyBusinessAltPhone = data.companyBusinessAltPhone || data.Company_Business_ALT_Phone__c || '';
        this.companyBusinessAddress = data.companyBusinessAddress || data.Company_Business_Address__c || '';
        this.companyBusinessCity = data.companyBusinessCity || data.Company_Business_City__c || '';
        this.companyBusinessPostalCode = data.companyBusinessPostalCode || data.Company_Business_Postal_Code__c || '';
        this.companyBusinessCountry = data.companyBusinessCountry || data.Company_Business_Country__c || '';
    }
    
    
    // Method to save customer data to Salesforce via Apex
    async saveCustomerDataToSalesforce() {
        if (!this._applicationId) {
            console.log('⚠️ No applicationId provided, skipping Salesforce save');
            return false;
        }
        
        try {
            console.log('💾 Saving customer data to Salesforce...');
            const customerData = {
                applicationId: this._applicationId,
                firstName: this.firstName,
                lastName: this.lastName,
                email: this.email,
                phone: this.phone,
                streetAddress: this.streetAddress,
                city: this.city,
                province: this.province,
                postalCode: this.postalCode,
                country: this.country,
                coBuyerFirstName: this.coBuyerFirstName,
                coBuyerLastName: this.coBuyerLastName,
                coBuyerStreetAddress: this.coBuyerStreetAddress,
                coBuyerCity: this.coBuyerCity,
                coBuyerProvince: this.coBuyerProvince,
                coBuyerPostalCode: this.coBuyerPostalCode,
                coBuyerCountry: this.coBuyerCountry,
                coBuyerEmail: this.coBuyerEmail,
                coBuyerPhone: this.coBuyerPhone,
                licenseNumber: this.licenseNumber,
                licenseProvince: this.licenseProvince,
                licenseExpiry: this.licenseExpiry,
                companyBusiness: this.companyBusiness,
                businessNumber: this.businessNumber,
                insuranceProvider: this.insuranceProvider,
                insurancePolicy: this.insurancePolicy,
                companyProvince: this.companyProvince,
                companyEmail: this.companyEmail,
                companyContactName: this.companyContactName,
                companyBusinessPhone: this.companyBusinessPhone,
                companyBusinessAltPhone: this.companyBusinessAltPhone,
                companyBusinessAddress: this.companyBusinessAddress,
                companyBusinessCity: this.companyBusinessCity,
                companyBusinessPostalCode: this.companyBusinessPostalCode,
                companyBusinessCountry: this.companyBusinessCountry
            };
            
            const result = await saveCustomerData({ customerData: customerData });
            console.log('✅ Customer data saved to Salesforce successfully:', result);
            return true;
        } catch (error) {
            console.error('❌ Error saving customer data to Salesforce:', error);
            this.showError = true;
            this.errorMessage = 'Unable to save customer information. Please try again.';
            return false;
        }
    }
    
    get provinces() {
        return [
            { label: 'Alberta', value: 'AB' },
            { label: 'British Columbia', value: 'BC' },
            { label: 'Manitoba', value: 'MB' },
            { label: 'New Brunswick', value: 'NB' },
            { label: 'Newfoundland and Labrador', value: 'NL' },
            { label: 'Northwest Territories', value: 'NT' },
            { label: 'Nova Scotia', value: 'NS' },
            { label: 'Nunavut', value: 'NU' },
            { label: 'Ontario', value: 'ON' },
            { label: 'Prince Edward Island', value: 'PE' },
            { label: 'Quebec', value: 'QC' },
            { label: 'Saskatchewan', value: 'SK' },
            { label: 'Yukon', value: 'YT' }
        ];
    }
    
    get coBuyerProvinces() {
        return [
            { label: 'Alberta', value: 'AB' },
            { label: 'British Columbia', value: 'BC' },
            { label: 'Manitoba', value: 'MB' },
            { label: 'New Brunswick', value: 'NB' },
            { label: 'Newfoundland and Labrador', value: 'NL' },
            { label: 'Northwest Territories', value: 'NT' },
            { label: 'Nova Scotia', value: 'NS' },
            { label: 'Nunavut', value: 'NU' },
            { label: 'Ontario', value: 'ON' },
            { label: 'Prince Edward Island', value: 'PE' },
            { label: 'Quebec', value: 'QC' },
            { label: 'Saskatchewan', value: 'SK' },
            { label: 'Yukon', value: 'YT' }
        ];
    }
    
    connectedCallback() {
        console.log('👤 Customer component connected - applicationId:', this._applicationId);
        
        // If we have an applicationId, load the data
        if (this._applicationId) {
            this.loadCustomerData();
        } else {
            // Fallback to global session storage for backward compatibility
            if (sessionStorage.getItem('customerData')) {
                const savedData = JSON.parse(sessionStorage.getItem('customerData'));
                this.populateFormFields(savedData);
            }
        }
    }
    
    // Store component data for back navigation
    getCurrentData() {
        return {
            firstName: this.firstName,
            lastName: this.lastName,
            email: this.email,
            phone: this.phone,
            streetAddress: this.streetAddress,
            city: this.city,
            province: this.province,
            postalCode: this.postalCode,
            country: this.country,
            coBuyerFirstName: this.coBuyerFirstName,
            coBuyerLastName: this.coBuyerLastName,
            coBuyerStreetAddress: this.coBuyerStreetAddress,
            coBuyerCity: this.coBuyerCity,
            coBuyerProvince: this.coBuyerProvince,
            coBuyerPostalCode: this.coBuyerPostalCode,
            coBuyerCountry: this.coBuyerCountry,
            coBuyerEmail: this.coBuyerEmail,
            coBuyerPhone: this.coBuyerPhone,
            licenseNumber: this.licenseNumber,
            licenseProvince: this.licenseProvince,
            licenseExpiry: this.licenseExpiry,
            companyBusiness: this.companyBusiness,
            businessNumber: this.businessNumber,
            insuranceProvider: this.insuranceProvider,
            insurancePolicy: this.insurancePolicy,
            companyProvince: this.companyProvince,
            companyEmail: this.companyEmail,
            companyContactName: this.companyContactName,
            companyBusinessPhone: this.companyBusinessPhone,
            companyBusinessAltPhone: this.companyBusinessAltPhone,
            companyBusinessAddress: this.companyBusinessAddress,
            companyBusinessCity: this.companyBusinessCity,
            companyBusinessPostalCode: this.companyBusinessPostalCode,
            companyBusinessCountry: this.companyBusinessCountry
        };
    }
    
    // Save data to session storage
    saveDataToSession() {
        if (this._applicationId) {
            sessionStorage.setItem(`customerData_${this._applicationId}`, JSON.stringify(this.getCurrentData()));
        }
        sessionStorage.setItem('customerData', JSON.stringify(this.getCurrentData()));
    }
    
    // Restore data when navigating back
    @api
    restoreData(data) {
        if (data) {
            this.populateFormFields(data);
        }
    }
    
    // Event handlers for form fields (keeping all your existing handlers)
    handleFirstNameChange(event) {
        console.log('🔍 handleFirstNameChange called with value:', event.target.value);
        this.firstName = event.target.value;
        this.showError = false;
    }
    
    handleLastNameChange(event) {
        console.log('🔍 handleLastNameChange called with value:', event.target.value);
        this.lastName = event.target.value;
        this.showError = false;
    }
    
    handleEmailChange(event) {
        console.log('🔍 handleEmailChange called with value:', event.target.value);
        this.email = event.target.value;
        this.showError = false;
    }
    
    handlePhoneChange(event) {
        console.log('🔍 handlePhoneChange called with value:', event.target.value);
        let value = event.target.value;
        
        // Auto-format phone number as user types ((123) 456-7890 format)
        if (value.length > 0) {
            value = value.replace(/\D/g, '');
            if (value.length >= 1) {
                value = '(' + value;
            }
            if (value.length >= 4) {
                value = value.substring(0, 4) + ') ' + value.substring(4);
            }
            if (value.length >= 8) {
                value = value.substring(0, 8) + '-' + value.substring(8);
            }
            if (value.length > 14) {
                value = value.substring(0, 14);
            }
        }
        
        this.phone = value;
        this.showError = false;
    }
    
    handleStreetAddressChange(event) {
        console.log('🔍 handleStreetAddressChange called with value:', event.target.value);
        this.streetAddress = event.target.value;
        this.showError = false;
    }
    
    handleCityChange(event) {
        console.log('🔍 handleCityChange called with value:', event.target.value);
        this.city = event.target.value;
        this.showError = false;
    }
    
    handleProvinceChange(event) {
        console.log('🔍 handleProvinceChange called with value:', event.target.value);
        this.province = event.target.value;
        this.showError = false;
    }
    
    handlePostalCodeChange(event) {
        console.log('🔍 handlePostalCodeChange called with value:', event.target.value);
        let value = event.target.value.toUpperCase();
        
        if (value.length > 0) {
            value = value.replace(/[^A-Z0-9]/g, '');
            if (value.length >= 3) {
                value = value.substring(0, 3) + ' ' + value.substring(3);
            }
            if (value.length >= 6) {
                value = value.substring(0, 6) + ' ' + value.substring(6);
            }
            if (value.length > 7) {
                value = value.substring(0, 7);
            }
        }
        
        this.postalCode = value;
        this.showError = false;
    }

    handleCountryChange(event) {
        this.country = event.target.value;
        this.showError = false;
    }

    // Co-buyer/Co-lessee handlers
    handleCoBuyerFirstNameChange(event) { 
        this.coBuyerFirstName = event.target.value; 
        this.showError = false; 
    }
    
    handleCoBuyerLastNameChange(event) { 
        this.coBuyerLastName = event.target.value; 
        this.showError = false; 
    }
    
    handleCoBuyerStreetAddressChange(event) { 
        this.coBuyerStreetAddress = event.target.value; 
        this.showError = false; 
    }
    
    handleCoBuyerCityChange(event) { 
        this.coBuyerCity = event.target.value; 
        this.showError = false; 
    }
    
    handleCoBuyerProvinceChange(event) { 
        this.coBuyerProvince = event.target.value; 
        this.showError = false; 
    }
    
    handleCoBuyerPostalCodeChange(event) { 
        let value = event.target.value.toUpperCase();
        
        if (value.length > 0) {
            value = value.replace(/[^A-Z0-9]/g, '');
            if (value.length >= 3) {
                value = value.substring(0, 3) + ' ' + value.substring(3);
            }
            if (value.length >= 6) {
                value = value.substring(0, 6) + ' ' + value.substring(6);
            }
            if (value.length > 7) {
                value = value.substring(0, 7);
            }
        }
        
        this.coBuyerPostalCode = value; 
        this.showError = false; 
    }
    
    handleCoBuyerCountryChange(event) { 
        this.coBuyerCountry = event.target.value; 
        this.showError = false; 
    }
    
    handleCoBuyerEmailChange(event) { 
        this.coBuyerEmail = event.target.value; 
        this.showError = false; 
    }
    
    handleCoBuyerPhoneChange(event) { 
        this.coBuyerPhone = event.target.value; 
        this.showError = false; 
    }
    
    // Optional handlers
    handleLicenseNumberChange(event) { this.licenseNumber = event.target.value; this.showError = false; }
    handleLicenseProvinceChange(event) { this.licenseProvince = event.target.value; this.showError = false; }
    handleLicenseExpiryChange(event) { this.licenseExpiry = event.target.value; this.showError = false; }
    handleCompanyBusinessChange(event) { this.companyBusiness = event.target.value; this.showError = false; }
    handleBusinessNumberChange(event) { this.businessNumber = event.target.value; this.showError = false; }
    handleInsuranceProviderChange(event) { this.insuranceProvider = event.target.value; this.showError = false; }
    handleInsurancePolicyChange(event) { this.insurancePolicy = event.target.value; this.showError = false; }
    handleCompanyProvinceChange(event) { this.companyProvince = event.target.value; this.showError = false; }
    handleCompanyEmailChange(event) { this.companyEmail = event.target.value; this.showError = false; }
    handleCompanyContactNameChange(event) { this.companyContactName = event.target.value; this.showError = false; }
    handleCompanyBusinessPhoneChange(event) { this.companyBusinessPhone = event.target.value; this.showError = false; }
    handleCompanyBusinessAltPhoneChange(event) { this.companyBusinessAltPhone = event.target.value; this.showError = false; }
    handleCompanyBusinessAddressChange(event) { this.companyBusinessAddress = event.target.value; this.showError = false; }
    handleCompanyBusinessCityChange(event) { this.companyBusinessCity = event.target.value; this.showError = false; }
    handleCompanyBusinessPostalCodeChange(event) { this.companyBusinessPostalCode = event.target.value; this.showError = false; }
    handleCompanyBusinessCountryChange(event) { this.companyBusinessCountry = event.target.value; this.showError = false; }
    
    // Validation (keeping your existing validation)
    validateForm() {
        // ... (keep all your existing validation logic)
        if (!this.firstName.trim()) {
            this.errorMessage = 'First Name is required.';
            this.showError = true;
            return false;
        }
        
        if (!this.lastName.trim()) {
            this.errorMessage = 'Last Name is required.';
            this.showError = true;
            return false;
        }
        
        if (!this.email.trim()) {
            this.errorMessage = 'Email Address is required.';
            this.showError = true;
            return false;
        }
        
        if (!this.phone.trim()) {
            this.errorMessage = 'Primary Phone is required.';
            this.showError = true;
            return false;
        }
        
        if (!this.streetAddress.trim()) {
            this.errorMessage = 'Street Address is required.';
            this.showError = true;
            return false;
        }
        
        if (!this.city.trim()) {
            this.errorMessage = 'City is required.';
            this.showError = true;
            return false;
        }
        
        if (!this.province) {
            this.errorMessage = 'Province is required.';
            this.showError = true;
            return false;
        }
        
        if (!this.postalCode.trim()) {
            this.errorMessage = 'Postal Code is required.';
            this.showError = true;
            return false;
        }
        
        const emailRegex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
        if (!emailRegex.test(this.email.trim())) {
            this.errorMessage = 'Please enter a valid email address format (e.g., example@email.com).';
            this.showError = true;
            return false;
        }
        
        /*const phoneRegex = /^(\+?1[-.\s]?)?\(?([0-9]{3})\)?[-.\s]?([0-9]{3})[-.\s]?([0-9]{4})$/;
        if (!phoneRegex.test(this.phone.trim())) {
            this.errorMessage = 'Please enter a valid Canadian phone number (e.g., (123) 456-7890 or 123-456-7890).';
            this.showError = true;
            return false;
        }
        
        const postalCodeRegex = /^[A-Za-z]\d[A-Za-z][ -]?\d[A-Za-z]\d$/;
        if (!postalCodeRegex.test(this.postalCode.trim().toUpperCase())) {
            this.errorMessage = 'Please enter a valid Canadian postal code format (e.g., A1A 1A1).';
            this.showError = true;
            return false;
        }*/
        
        const emailDomain = this.email.split('@')[1];
        if (emailDomain && emailDomain.length < 3) {
            this.errorMessage = 'Please enter a valid email address with a proper domain.';
            this.showError = true;
            return false;
        }
        
        return true;
    }
    
    handleBack() {
        this.saveDataToSession();
        
        const backEvent = new CustomEvent('back', {
            detail: { data: this.getCurrentData() }
        });
        this.dispatchEvent(backEvent);
    }
    
    async handleContinue() {
        if (!this.validateForm()) {
            return;
        }
        
        console.log('🔍 handleContinue called with applicationId:', this.applicationId);
        
        try {
            const saveSuccess = await this.saveCustomerDataToSalesforce();
            
            if (saveSuccess) {
                this.saveDataToSession();
                console.log('✅ Customer form data collected:', this.getCurrentData());
                
                const navigateEvent = new CustomEvent('navigate', {
                    detail: { 
                        tab: 'summary',
                        data: this.getCurrentData()
                    }
                });
                console.log('🔍 Navigating to summary tab');
                this.dispatchEvent(navigateEvent);
            }
        } catch (error) {
            console.error('❌ Error in handleContinue:', error);
        }
    }
    
    // Handle next button click - navigate to next tab when application is locked
    handleNext() {
        console.log('⏭️ Next button clicked from customer component');
        const navigateEvent = new CustomEvent('navigate', {
            detail: { tab: 'summary' },
            bubbles: true
        });
        this.dispatchEvent(navigateEvent);
    }
}