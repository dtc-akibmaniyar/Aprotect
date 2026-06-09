import { LightningElement, track, api, wire } from 'lwc';
import { refreshApex } from 'lightning/uiRecordApi';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getApplicationStatus from '@salesforce/apex/DealerPortalController.getApplicationStatus';
import convertApplicationToQuote from '@salesforce/apex/DealerPortalController.convertApplicationToQuote';
import convertQuoteToApplication from '@salesforce/apex/DealerPortalController.convertQuoteToApplication';
import generateQuotePDF from '@salesforce/apex/QuotePDFGeneratorService.generateQuotePDF';
import communityBasePath from '@salesforce/community/basePath';

/**
 * 🔓 TAB LOCKING TEMPORARILY DISABLED
 * 
 * All tabs are now accessible without completion requirements.
 * To re-enable tab locking, simply uncomment the original logic in the canAccessTab method.
 * 
 * Current behavior: Users can navigate to any tab freely
 * Original behavior: Users must complete previous tabs before accessing next ones
 */

export default class DealerPortalContainer extends NavigationMixin(LightningElement) {
    _applicationId;
    @track activeTab = 'vehicle';
    @track _lastVehicleSignature = null;
    @track applicationStatus = null;
    @track applicationLockDate = null;
    // @track isApplicationLocked = false;
    applicationPaymentStatus = null;
    @track showConvertToAppModal = false;
    @track isConvertingToApp = false;
    @track isGeneratingQuotePDF = false;
    
    // Removed @wire decorator - using imperative approach instead for better cache control
    
    // Tab locking is temporarily disabled - can be re-enabled later
    
    // Tab completion tracking
    @track tabCompletionStatus = {
        vehicle: false,
        warranty: false,
        moreProducts: false,
        gap: false,
        customer: false,
        summary: false
    };
    
    // Tab dependencies (which tabs need to be completed first)
    tabDependencies = {
        warranty: ['vehicle'],
        moreProducts: ['vehicle', 'warranty'],
        gap: ['vehicle', 'warranty', 'moreProducts'],
        customer: ['vehicle'],
        summary: ['vehicle', 'warranty', 'moreProducts', 'gap', 'customer']
    };
    
    connectedCallback() {
        console.log('🏢 Container component connected');
        console.log('🏢 Initial applicationId:', this._applicationId);
        
        // Try to get application ID from URL or record context
        this.tryToGetApplicationIdFromContext();
        
        // Load application status imperatively
        if (this._applicationId) {
            this.loadApplicationStatus();
        }
        
        // Check for existing warranty packages after a delay to allow child components to load
        setTimeout(() => {
            this.checkForExistingWarrantyPackage();
        }, 2000);
    }
    
    // Imperative method to load application status
    async loadApplicationStatus() {
        try {
            console.log('🔄 Loading application status imperatively for:', this._applicationId);
            const result = await getApplicationStatus({ applicationId: this._applicationId });

            if (result) {
                console.log('📋 Application status loaded:', result);
                this.applicationStatus = result.Application_Status__c;
                this.applicationLockDate = result.Application_Lock_Date__c;
                this.applicationPaymentStatus = result.Payment_Status__c;
                console.log('✅ Application status set to:', this.applicationStatus);

                // If the application is locked, force the user to the Summary tab only
                if (this.isApplicationLocked) {
                    console.log('🔒 Application is locked — forcing Summary tab');
                    this.activeTab = 'summary';
                }
            }
        } catch (error) {
            console.error('❌ Error loading application status:', error);
        }
    }
    
    // Method to try to get application ID from context
    tryToGetApplicationIdFromContext() {
        // Method 1: Check if applicationId was passed via @api
        if (this._applicationId) {
            console.log('🏢 ApplicationId already set via @api:', this._applicationId);
            return;
        }
        
        // Method 2: Try to get from URL parameters
        const urlParams = new URLSearchParams(window.location.search);
        const applicationIdFromUrl = urlParams.get('c__applicationId') || urlParams.get('applicationId');
        
        if (applicationIdFromUrl) {
            console.log('🏢 ApplicationId found in URL:', applicationIdFromUrl);
            this._applicationId = applicationIdFromUrl;
            console.log('🏢 Setting applicationId from URL:', this._applicationId);
            return;
        }
        
        // Method 3: Try to get from record ID if this is on a record page
        const recordId = this.getRecordIdFromUrl();
        if (recordId && recordId.startsWith('a01')) { // Application object starts with a01
            console.log('🏢 ApplicationId found from record context:', recordId);
            this._applicationId = recordId;
            console.log('🏢 Setting applicationId from record context:', this._applicationId);
            return;
        }
        
        console.log('⚠️ No applicationId found in context, URL, or record');
    }
    
    // Helper method to extract record ID from URL
    getRecordIdFromUrl() {
        try {
            const url = window.location.href;
            // Look for record ID in various URL patterns
            const recordIdMatch = url.match(/\/([a-zA-Z0-9]{15,18})(?:\/|$|\?)/);
            return recordIdMatch ? recordIdMatch[1] : null;
        } catch (error) {
            console.error('Error extracting record ID from URL:', error);
            return null;
        }
    }

    // Getter and setter for applicationId to handle changes
    @api
    get applicationId() {
        return this._applicationId;
    }
    
    // Method to manually set application ID for testing
    @api
    setApplicationId(id) {
        console.log('🏢 Manually setting applicationId to:', id);
        this._applicationId = id;
        console.log('🏢 applicationId now set to:', this.applicationId);
        
        // Reset to vehicle tab when application changes
        if (id) {
            this.activeTab = 'vehicle';
            console.log('🏢 Reset to vehicle tab for new application');
            
            // Reset tab completion status for new application
            this.resetTabCompletionStatus();
        }
    }
    
    set applicationId(value) {
        console.log('🔄 Container ApplicationId setter called with value:', value);
        console.log('🔄 Current _applicationId:', this._applicationId);
        
        // Only process if the value is actually different
        if (this._applicationId !== value) {
            console.log('🔄 Container ApplicationId changed from', this._applicationId, 'to', value);
            this._applicationId = value;
            
            // Reset to vehicle tab when application changes
            if (value) {
                this.activeTab = 'vehicle';
                console.log('🔄 Reset to vehicle tab for new application');
                
                // Reset tab completion status for new application
                this.resetTabCompletionStatus();
                
                // Load application status imperatively
                this.loadApplicationStatus();
                
                // Notify child components that applicationId has changed
                this.notifyChildComponents();
            }
        } else {
            console.log('🔄 ApplicationId unchanged, no action needed');
            return; // Exit early to prevent any processing
        }
    }
    
    // Method to notify child components that applicationId has changed
    notifyChildComponents() {
        console.log('🔄 Notifying child components of applicationId change:', this._applicationId);
        
        // Get all child components that need the applicationId
        const vehicleComponent = this.template.querySelector('c-dealer-portal-vehicle');
        const warrantyComponent = this.template.querySelector('c-dealer-portal-warranty');
        const moreProductsComponent = this.template.querySelector('c-dealer-portal-more-products');
        const gapComponent = this.template.querySelector('c-dealer-portal-gap');
        const customerComponent = this.template.querySelector('c-dealer-portal-customer');
        const summaryComponent = this.template.querySelector('c-dealer-portal-summary');
        
        console.log('🔄 Found child components:', {
            vehicle: !!vehicleComponent,
            warranty: !!warrantyComponent,
            moreProducts: !!moreProductsComponent,
            gap: !!gapComponent,
            customer: !!customerComponent,
            summary: !!summaryComponent
        });
    }
    
    // Tab completion event handlers - mark as completed and navigate to next tab
    handleVehicleComplete(event) {
        console.log('✅ Vehicle tab completed');
        console.log('🔍 Vehicle completion event details:', event.detail);
        console.log('🔍 Current activeTab before switch:', this.activeTab);
        
        
        // Check if vehicle config changed (affects package filtering)
        const vData = event.detail && event.detail.vehicleData ? event.detail.vehicleData : {};
        const newSig = [vData.year, vData.make, vData.model, vData.odometerReading, vData.odometerUnit, vData.isCommercial, vData.vehicleCategory].join('|');
        const vehicleChanged = this._lastVehicleSignature !== null && this._lastVehicleSignature !== newSig;
        this._lastVehicleSignature = newSig;
        if (vehicleChanged) {
            console.log('Vehicle config changed - notifying package tabs');
            const wComp = this.template.querySelector('c-dealer-portal-warranty');
            if (wComp && typeof wComp.handleVehicleConfigChanged === 'function') wComp.handleVehicleConfigChanged();
            const mpComp = this.template.querySelector('c-dealer-portal-more-products');
            if (mpComp && typeof mpComp.handleVehicleConfigChanged === 'function') mpComp.handleVehicleConfigChanged();
            this.tabCompletionStatus.warranty = false;
            this.tabCompletionStatus.moreProducts = false;
            this.tabCompletionStatus.gap = false;
        }
        this.markTabAsCompleted('vehicle');
        this.switchToTab('warranty');
        
        console.log('🔍 Current activeTab after switch:', this.activeTab);
    }
    
    handleWarrantyComplete(event) {
        console.log('✅ Warranty tab completed');
        console.log('🔍 Warranty completion event details:', event.detail);
        
        // Mark warranty tab as completed
        this.markTabAsCompleted('warranty');
        
        // Only auto-navigate if this is NOT an auto-selection
        if (!event.detail.autoSelected) {
            console.log('🔄 Auto-navigating to More Products tab');
            this.switchToTab('moreProducts');
        } else {
            console.log('⏸️ Auto-selection detected, staying on warranty tab');
        }
    }
    
    handleMoreProductsComplete(event) {
        console.log('✅ More Products tab completed');
        console.log('🔍 More Products completion event details:', event.detail);
        
        // Mark more products tab as completed
        this.markTabAsCompleted('moreProducts');
        
        // Only auto-navigate if this is NOT an auto-selection
        if (!event.detail.autoSelected) {
            console.log('🔄 Auto-navigating to Car Loan Protection tab');
            this.switchToTab('gap');
        } else {
            console.log('⏸️ Auto-selection detected, staying on more products tab');
        }
    }
    
    handleGapComplete() {
        console.log('✅ Car Loan Protection tab completed');
        this.markTabAsCompleted('gap');
        
        // If status is Quote, skip customer and go to summary
        if (this.applicationStatus === 'Quote') {
            console.log('📋 Application is a Quote - skipping Customer tab, going to Summary');
            this.switchToTab('summary');
        } else {
            this.switchToTab('customer');
        }
    }
    
    handleCustomerComplete() {
        console.log('✅ Customer tab completed');
        this.markTabAsCompleted('customer');
        this.switchToTab('summary');
    }
    
    handleSummaryComplete() {
        console.log('✅ Summary tab completed');
        this.markTabAsCompleted('summary');
    }

    // Computed property: show convert button when status is Quote
    get showConvertToApplicationButton() {
        return false;
    }

    // Computed properties for tab classes with completion status and locking
    get vehicleTabClass() {
        if (this.isApplicationLocked) return 'tab-button hidden';
        const isCompleted = this.tabCompletionStatus.vehicle;
        const isActive = this.activeTab === 'vehicle';
        const isAccessible = this.canAccessTab('vehicle');
        return `tab-button ${isActive ? 'active' : ''} ${isCompleted ? 'completed' : ''} ${!isAccessible ? 'locked' : ''}`;
    }

    get warrantyTabClass() {
        if (this.isApplicationLocked) return 'tab-button hidden';
        const isCompleted = this.tabCompletionStatus.warranty;
        const isActive = this.activeTab === 'warranty';
        const isAccessible = this.canAccessTab('warranty');
        return `tab-button ${isActive ? 'active' : ''} ${isCompleted ? 'completed' : ''} ${!isAccessible ? 'locked' : ''}`;
    }

    get moreProductsTabClass() {
        if (this.isApplicationLocked) return 'tab-button hidden';
        const isCompleted = this.tabCompletionStatus.moreProducts;
        const isActive = this.activeTab === 'moreProducts';
        const isAccessible = this.canAccessTab('moreProducts');
        return `tab-button ${isActive ? 'active' : ''} ${isCompleted ? 'completed' : ''} ${!isAccessible ? 'locked' : ''}`;
    }

    get headerTitle() {
        return this.applicationStatus === 'Quote' ? 'New Quote' : 'New Application';
    }

    get isApplicationLocked() {
        // Lock if payment status is 'Paid'
        if (this.applicationPaymentStatus === 'Paid') {
            console.log('🔒 Application is locked - payment status is Paid');
            return true;
        }

        // Lock if Application_Lock_Date__c is today or in the past
        if (this.applicationLockDate) {
            const lockDate = new Date(this.applicationLockDate);
            const today = new Date();
            
            // Set time to midnight for accurate date comparison
            today.setHours(0, 0, 0, 0);
            lockDate.setHours(0, 0, 0, 0);
            
            if (lockDate <= today) {
                console.log('🔒 Application is locked - lock date is today or in the past');
                console.log('  Lock Date:', lockDate.toDateString());
                console.log('  Today:', today.toDateString());
                return true;
            }
        }

        return false;
    }

    get lockedMessage() {
        if (this.applicationPaymentStatus === 'Paid') {
            return 'This application is locked because the payment status is Paid and cannot be edited.';
        }
        if (this.applicationLockDate) {
            return 'This application is locked and cannot be edited.';
        }
        return '';
    }

    get gapTabClass() {
        if (this.isApplicationLocked) return 'tab-button hidden';
        const isCompleted = this.tabCompletionStatus.gap;
        const isActive = this.activeTab === 'gap';
        const isAccessible = this.canAccessTab('gap');
        return `tab-button ${isActive ? 'active' : ''} ${isCompleted ? 'completed' : ''} ${!isAccessible ? 'locked' : ''}`;
    }

    get customerTabClass() {
        if (this.isApplicationLocked) return 'tab-button hidden';
        // Don't show customer tab if application status is Quote
        if (this.applicationStatus === 'Quote') return 'tab-button hidden';
        const isCompleted = this.tabCompletionStatus.customer;
        const isActive = this.activeTab === 'customer';
        const isAccessible = this.canAccessTab('customer');
        return `tab-button ${isActive ? 'active' : ''} ${isCompleted ? 'completed' : ''} ${!isAccessible ? 'locked' : ''}`;
    }

    get summaryTabClass() {
        // When locked, Summary is the only visible tab — always show it as active
        if (this.isApplicationLocked) {
            return 'tab-button active';
        }
        // Don't show summary tab if application status is Quote
        if (this.applicationStatus === 'Quote') return 'tab-button hidden';
        const isCompleted = this.tabCompletionStatus.summary;
        const isActive = this.activeTab === 'summary';
        const isAccessible = this.canAccessTab('summary');
        return `tab-button ${isActive ? 'active' : ''} ${isCompleted ? 'completed' : ''} ${!isAccessible ? 'locked' : ''}`;
    }
    
    // Computed properties for tab disabled states
    get vehicleTabDisabled() {
        return this.isApplicationLocked || !this.canAccessTab('vehicle');
    }

    get warrantyTabDisabled() {
        return this.isApplicationLocked || !this.canAccessTab('warranty');
    }

    get moreProductsTabDisabled() {
        return this.isApplicationLocked || !this.canAccessTab('moreProducts');
    }

    get gapTabDisabled() {
        return this.isApplicationLocked || !this.canAccessTab('gap');
    }

    get customerTabDisabled() {
        return this.isApplicationLocked || this.applicationStatus === 'Quote' || !this.canAccessTab('customer');
    }

    get summaryTabDisabled() {
        // Always enabled when locked — it's the only tab available
        if (this.isApplicationLocked) return false;
        return this.applicationStatus === 'Quote' || !this.canAccessTab('summary');
    }
    


    // Computed properties for tab content classes (CSS-based visibility)
    get vehicleTabContentClass() {
        return `tab-content-section ${this.activeTab === 'vehicle' ? 'active' : 'hidden'}`;
    }

    get warrantyTabContentClass() {
        return `tab-content-section ${this.activeTab === 'warranty' ? 'active' : 'hidden'}`;
    }

    get moreProductsTabContentClass() {
        return `tab-content-section ${this.activeTab === 'moreProducts' ? 'active' : 'hidden'}`;
    }

    get gapTabContentClass() {
        return `tab-content-section ${this.activeTab === 'gap' ? 'active' : 'hidden'}`;
    }

    get customerTabContentClass() {
        return `tab-content-section ${this.activeTab === 'customer' ? 'active' : 'hidden'}`;
    }

    get summaryTabContentClass() {
        return `tab-content-section ${this.activeTab === 'summary' ? 'active' : 'hidden'}`;
    }



    // Handle direct tab click navigation
    handleTabClick(event) {
        const tabName = event.currentTarget.dataset.tab;
        console.log('🖱️ Tab clicked:', tabName);
        this.switchToTab(tabName);
    }

    switchToTab(tabName) {
        console.log(`🔄 Attempting to switch to tab: ${tabName}`);

        // When locked, only the Summary tab is visible and accessible
        if (this.isApplicationLocked && tabName !== 'summary') {
            console.log(`🔒 Cannot access tab ${tabName} - application is locked`);
            return;
        }

        // Check if tab should be hidden (Quote status hides Customer and Summary)
        if (this.applicationStatus === 'Quote' && (tabName === 'customer' || tabName === 'summary')) {
            console.log(`❌ Cannot access tab ${tabName} - hidden for Quote applications`);
            return;
        }
        
        console.log(`🔒 Tab access check:`, {
            tabName,
            canAccess: this.canAccessTab(tabName),
            completionStatus: this.tabCompletionStatus,
            dependencies: this.tabDependencies[tabName] || []
        });
        
        if (this.canAccessTab(tabName)) {
            console.log('✅ Switching to tab:', tabName);
            console.log('🔍 activeTab before assignment:', this.activeTab);
            this.activeTab = tabName;
            console.log('🔍 activeTab after assignment:', this.activeTab);
            
            // Notify tab activation after a short delay to ensure DOM is ready
            setTimeout(() => {
                console.log('🔍 Notifying tab activation for:', tabName);
                this.notifyTabActivated(tabName);
            }, 100);
        } else {
            console.log(`❌ Cannot access tab ${tabName} - dependencies not met`);
            console.log(`📋 Required dependencies:`, this.tabDependencies[tabName] || []);
            console.log(`📊 Current completion status:`, this.tabCompletionStatus);
        }
    }

    canAccessTab(tabName) {
        // 🔓 TAB LOCKING TEMPORARILY DISABLED - All tabs are accessible
        console.log(`🔓 Tab access check for ${tabName}: LOCKING DISABLED - All tabs accessible`);
        return true;
        
        // 🔒 ORIGINAL LOCKING LOGIC (COMMENTED OUT FOR LATER RE-IMPLEMENTATION):
        /*
        // Vehicle tab is always accessible
        if (tabName === 'vehicle') {
            return true;
        }
        
        // Special case: If warranty tab has an existing package, allow access even if vehicle isn't marked as completed
        if (tabName === 'warranty' && this.tabCompletionStatus.warranty) {
            console.log(`🔓 Warranty tab has existing package, allowing access`);
            return true;
        }
        
        // Check if all required dependencies are completed
        const dependencies = this.tabDependencies[tabName] || [];
        const canAccess = dependencies.every(dep => this.tabCompletionStatus[dep]);
        
        console.log(`🔒 Tab access check for ${tabName}:`, {
            dependencies,
            completionStatus: dependencies.map(dep => ({ [dep]: this.tabCompletionStatus[dep] })),
            canAccess,
            fullTabCompletionStatus: JSON.stringify(this.tabCompletionStatus)
        });
        
        return canAccess;
        */
    }
    
    // Method to mark a tab as completed
    markTabAsCompleted(tabName) {
        console.log(`✅ Marking tab ${tabName} as completed`);
        console.log(`🔍 Before update - tabCompletionStatus:`, JSON.stringify(this.tabCompletionStatus));
        this.tabCompletionStatus[tabName] = true;
        console.log(`🔍 After update - tabCompletionStatus:`, JSON.stringify(this.tabCompletionStatus));
        
        // Check if we can unlock next tabs
        this.checkAndUnlockNextTabs();
    }
    
    // Method to check and unlock next available tabs
    checkAndUnlockNextTabs() {
        Object.keys(this.tabDependencies).forEach(tabName => {
            if (!this.tabCompletionStatus[tabName] && this.canAccessTab(tabName)) {
                console.log(`🔓 Tab ${tabName} is now accessible`);
            }
        });
    }
    
    // Method to reset tab completion status for new applications
    resetTabCompletionStatus() {
        console.log('🔄 Resetting tab completion status for new application');
        this.tabCompletionStatus = {
            vehicle: false,
            warranty: false,
            moreProducts: false,
            gap: false,
            customer: false,
            summary: false
        };
        console.log('🔄 Tab completion status reset:', this.tabCompletionStatus);
    }
    
    // Method to check for existing warranty packages and unlock warranty tab
    async checkForExistingWarrantyPackage() {
        if (!this._applicationId) {
            console.log('⚠️ No applicationId available for warranty package check');
            return;
        }
        
        try {
            console.log('🔍 Checking for existing warranty packages in container...');
            
            // Get the warranty component
            const warrantyComponent = this.template.querySelector('c-dealer-portal-warranty');
            if (warrantyComponent && typeof warrantyComponent.checkForExistingApplicationPackage === 'function') {
                console.log('🔍 Calling checkForExistingApplicationPackage on warranty component');
                await warrantyComponent.checkForExistingApplicationPackage();
            } else {
                console.log('⚠️ Warranty component not found or method not available');
            }
        } catch (error) {
            console.error('❌ Error checking for existing warranty package:', error);
        }
    }

    notifyTabActivated(tabName) {
        console.log('🔄 Notifying tab activated:', tabName);
        console.log('🔄 Current applicationId:', this._applicationId);
        
        // Call onTabActivated on the appropriate component
        this.callOnTabActivated(tabName);
    }
    
    // Call onTabActivated on the appropriate component
    callOnTabActivated(tabName) {
        try {
            let component;
            switch (tabName) {
                case 'vehicle':
                    component = this.template.querySelector('c-dealer-portal-vehicle');
                    break;
                case 'warranty':
                    component = this.template.querySelector('c-dealer-portal-warranty');
                    break;
                case 'moreProducts':
                    component = this.template.querySelector('c-dealer-portal-more-products');
                    break;
                case 'gap':
                    component = this.template.querySelector('c-dealer-portal-gap');
                    break;
                case 'customer':
                    component = this.template.querySelector('c-dealer-portal-customer');
                    break;
                case 'summary':
                    component = this.template.querySelector('c-dealer-portal-summary');
                    break;
            }
            
            if (component && typeof component.onTabActivated === 'function') {
                console.log('🎯 ===== CALLING onTabActivated on', tabName, 'component =====');
                console.log('🔄 Component found:', !!component);
                console.log('🔄 Method exists:', typeof component.onTabActivated);
                component.onTabActivated();
                console.log('✅ onTabActivated called successfully on', tabName);
            } else {
                console.log('❌ Component or onTabActivated method not found for', tabName);
                console.log('🔍 Component:', !!component);
                console.log('🔍 Method type:', component ? typeof component.onTabActivated : 'N/A');
            }
        } catch (error) {
            console.error('❌ Error calling onTabActivated:', error);
        }
    }


    
    // Handle navigate events from child components
    handleVehicleNavigate(event) {
        const { tab, data } = event.detail;
        console.log('🚚 Vehicle component navigating to:', tab, 'with data:', data);
        this.switchToTab(tab);
    }
    
    handleVehicleBack(event) {
        console.log('🚚 Vehicle component going back - staying on vehicle tab');
        // Vehicle is the first tab, so just stay here
        // Could add logic here if needed for going back to a previous application
    }
    
    handleWarrantyNavigate(event) {
        const { tab, data } = event.detail;
        console.log('🔒 Warranty component navigating to:', tab, 'with data:', data);
        this.switchToTab(tab);
    }
    
    handleWarrantyBack(event) {
        console.log('🔒 Warranty component going back to vehicle tab');
        this.switchToTab('vehicle');
    }
    
    async handleApplicationStatusChanged(event) {
        console.log('🔄 Application status changed, updating UI...');
        const { newStatus } = event.detail;
        
        // Immediately update UI with new status
        this.applicationStatus = newStatus;
        console.log('✅ Application status updated to:', this.applicationStatus);
        
        // Reload application data imperatively to ensure fresh data
        // (no wire cache to worry about - imperative calls always fetch fresh)
        await this.loadApplicationStatus();
        console.log('✅ Fresh application status loaded imperatively');
    }
    
    handleMoreProductsNavigate(event) {
        const { tab, data } = event.detail;
        console.log('🛍️ More Products component navigating to:', tab, 'with data:', data);
        this.switchToTab(tab);
    }
    
    handleMoreProductsBack(event) {
        console.log('🛍️ More Products component going back to warranty tab');
        this.switchToTab('warranty');
    }
    
    /**
     * Handle Save As Quote from Warranty tab
     * Converts application to quote and navigates to quotes list
     */
    async handleWarrantySaveAsQuote(event) {
        try {
            console.log('📋 Warranty component - Save As Quote clicked');
            const { applicationId } = event.detail;
            
            // First save the current warranty form (handled by child component)
            // Then convert the application to a quote
            const result = await convertApplicationToQuote({ applicationId });
            
            if (result.success) {
                console.log('✅ Application converted to Quote');
                this.applicationStatus = 'Quote';
                
                // Navigate to quotes list
                this.navigateToQuotesList();
            } else {
                console.error('❌ Error converting application to quote:', result.message);
                // Show error to user
                const event = new CustomEvent('shownotification', {
                    detail: {
                        type: 'error',
                        message: result.message || 'Failed to convert application to quote'
                    }
                });
                this.dispatchEvent(event);
            }
        } catch (error) {
            console.error('❌ Error handling Save As Quote:', error);
            const event = new CustomEvent('shownotification', {
                detail: {
                    type: 'error',
                    message: 'An error occurred while converting to quote: ' + error.message
                }
            });
            this.dispatchEvent(event);
        }
    }

    /**
     * Handle Save As Quote from Tire & Rim (More Products) tab
     * Converts application to quote and navigates to quotes list
     */
    async handleMoreProductsSaveAsQuote(event) {
        try {
            console.log('📋 More Products component - Save As Quote clicked');
            const { applicationId } = event.detail;
            
            // Convert the application to a quote
            const result = await convertApplicationToQuote({ applicationId });
            
            if (result.success) {
                console.log('✅ Application converted to Quote');
                this.applicationStatus = 'Quote';
                
                // Navigate to quotes list
                this.navigateToQuotesList();
            } else {
                console.error('❌ Error converting application to quote:', result.message);
                const event = new CustomEvent('shownotification', {
                    detail: {
                        type: 'error',
                        message: result.message || 'Failed to convert application to quote'
                    }
                });
                this.dispatchEvent(event);
            }
        } catch (error) {
            console.error('❌ Error handling Save As Quote:', error);
            const event = new CustomEvent('shownotification', {
                detail: {
                    type: 'error',
                    message: 'An error occurred while converting to quote: ' + error.message
                }
            });
            this.dispatchEvent(event);
        }
    }

    /**
     * Handle Save As Quote from Loan Protection (GAP) tab
     * Converts application to quote and navigates to quotes list
     */
    async handleGapSaveAsQuote(event) {
        try {
            console.log('📋 GAP component - Save As Quote clicked');
            const { applicationId } = event.detail;
            
            // Convert the application to a quote
            const result = await convertApplicationToQuote({ applicationId });
            
            if (result.success) {
                console.log('✅ Application converted to Quote');
                this.applicationStatus = 'Quote';
                
                // Navigate to quotes list
                this.navigateToQuotesList();
            } else {
                console.error('❌ Error converting application to quote:', result.message);
                const event = new CustomEvent('shownotification', {
                    detail: {
                        type: 'error',
                        message: result.message || 'Failed to convert application to quote'
                    }
                });
                this.dispatchEvent(event);
            }
        } catch (error) {
            console.error('❌ Error handling Save As Quote:', error);
            const event = new CustomEvent('shownotification', {
                detail: {
                    type: 'error',
                    message: 'An error occurred while converting to quote: ' + error.message
                }
            });
            this.dispatchEvent(event);
        }
    }

    /**
     * Navigate to quotes list view
     * Uses NavigationMixin to navigate to the named page
     */
    navigateToQuotesList() {
        console.log('🔗 Navigating to quotes list');
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                pageName: 'quotes'
            }
        });
    }

    
    // Computed property: show generate quote PDF button when status is Quote
    get showGenerateQuotePDFButton() {
        return false;
    }

    // Handle Generate Quote PDF button click
    async handleGenerateQuotePDF() {
        if (!this._applicationId || this.isGeneratingQuotePDF) return;
        this.isGeneratingQuotePDF = true;
        try {
            const result = await generateQuotePDF({ applicationId: this._applicationId });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Quote PDF generated successfully',
                variant: 'success'
            }));
            // Open the generated PDF in a new browser tab (community-safe URL)
            if (result && result.contentVersionId) {
                const sfcBase = (communityBasePath || '').replace(/\/s$/, '');
                const downloadUrl = sfcBase + '/sfc/servlet.shepherd/version/download/' + result.contentVersionId;
                window.open(downloadUrl, '_blank');
            }
        } catch (err) {
            const msg = (err && err.body && err.body.message) || err.message || JSON.stringify(err);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error generating Quote PDF',
                message: msg,
                variant: 'error'
            }));
        } finally {
            this.isGeneratingQuotePDF = false;
        }
    }

handlePreviewPDF() {
        const basePath = communityBasePath || '';
        window.open(basePath + '/contentdocument/related/' + this._applicationId + '/AttachedContentDocuments', '_blank');
    }

// Convert to Application handlers
    handleConvertToApplication() {
        this.showConvertToAppModal = true;
    }

    handleCloseConvertToAppModal() {
        this.showConvertToAppModal = false;
    }

    async handleContinueConvertToApp() {
        if (!this._applicationId) return;
        this.isConvertingToApp = true;
        try {
            const result = await convertQuoteToApplication({ applicationId: this._applicationId });
            if (result.success) {
                console.log('✅ Quote converted to Application');
                // Update local status immediately
                this.applicationStatus = 'Draft';
                this.showConvertToAppModal = false;
                
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Success',
                    message: 'Quote converted to application successfully',
                    variant: 'success'
                }));
                
                // Reload application status to ensure fresh data
                await this.loadApplicationStatus();
            } else {
                throw new Error(result.message || 'Failed to convert quote');
            }
        } catch (err) {
            const msg = (err && err.body && err.body.message) || err.message || JSON.stringify(err);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error converting quote',
                message: msg,
                variant: 'error'
            }));
            console.error('Error converting quote to application', err);
        } finally {
            this.isConvertingToApp = false;
        }
    }

    handleGapNavigate(event) {
        const { tab, data } = event.detail;
        console.log('🛡️ Car Loan Protection component navigating to:', tab, 'with data:', data);
        this.switchToTab(tab);
    }

    handleGapBack(event) {
        console.log('🛡️ Car Loan Protection component going back to more products tab');
        this.switchToTab('moreProducts');
    }
    
    handleCustomerNavigate(event) {
        const { tab, data } = event.detail;
        console.log('👤 Customer component navigating to:', tab, 'with data:', data);
        this.switchToTab(tab);
    }
    
    handleCustomerBack(event) {
        console.log('👤 Customer component going back to Car Loan Protection tab');
        this.switchToTab('gap');
    }
    
    handleSummaryBack(event) {
        console.log('📋 Summary component going back');
        // If status is Quote, go back to Gap tab (skip Customer)
        if (this.applicationStatus === 'Quote') {
            console.log('📋 Application is a Quote - going back to Car Loan Protection tab');
            this.switchToTab('gap');
        } else {
            console.log('📋 Going back to customer tab');
            this.switchToTab('customer');
        }
    }

    handleSummaryNavigate(event) {
        const { tab, data } = event.detail;
        console.log('📋 Summary component navigating to:', tab, 'with data:', data);
        this.switchToTab(tab);
    }
}