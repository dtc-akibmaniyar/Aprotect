import { LightningElement, track, wire, api } from 'lwc';
import getAllApplications from '@salesforce/apex/DealerPortalController.getAllApplications';

export default class DealerPortalApplicationList extends LightningElement {
    @api title = 'Application List';
    @api description = 'Displays a list of all applications';
    @track applications = [];
    @track filteredApplications = [];
    @track searchTerm = '';
    @track loading = true;
    @track showError = false;
    @track errorMessage = '';
    @track lastRefreshTime = null;
    @track refreshLoading = false;

    get totalApplications() {
        return this.filteredApplications.length;
    }
    
    // Computed property to show applications table when not loading and no errors
    get showApplicationsTable() {
        return !this.loading && !this.showError;
    }
    
    // Computed property for refresh button class
    get refreshButtonClass() {
        return `refresh-button ${this.refreshLoading ? 'loading' : ''}`;
    }

    connectedCallback() {
        this.loadApplications();
    }

    async loadApplications() {
        this.loading = true;
        this.showError = false;
        
        try {
            const result = await getAllApplications();
            
            if (result.success) {
                const normalized = result.data.map(app => ({
                    ...app,
                    CreatedDate: this.formatDate(app.CreatedDate),
                    VehicleName: app.VehicleName || 'No Vehicle',
                    Status: app.Status || 'Active',
                    statusClass: this.getStatusClass(app.Status || 'Active')
                }));
                this.applications = normalized;
                this.applyFilter();
                
                // Log Apex debug information to browser console
                if (result.debugInfo) {
                    console.log('📋 APEX DEBUG INFO (getAllApplications):', result.debugInfo);
                    console.log('📋 Applications Found:', result.debugInfo.applicationsFound);
                    console.log('📋 Operation:', result.debugInfo.operation);
                    console.log('📋 Query Details:', result.debugInfo.queryDetails);
                }
                
                console.log('📋 Applications loaded:', this.applications);
            } else {
                this.showError = true;
                this.errorMessage = result.message || 'Failed to load applications';
                console.error('Error loading applications:', result.message);
            }
        } catch (error) {
            this.showError = true;
            this.errorMessage = 'Error loading applications: ' + error.message;
            console.error('Error loading applications:', error);
        } finally {
            this.loading = false;
            this.refreshLoading = false;
        }
    }

    handleApplicationClick(event) {
        event.preventDefault();
        const applicationId = event.currentTarget.dataset.id;
        console.log('📋 Application clicked:', applicationId);
        
        this.dispatchEvent(new CustomEvent('applicationselected', {
            detail: { applicationId: applicationId },
            bubbles: true,
            composed: true
        }));
    }

    handleNewApplication() {
        console.log('🔄 New application requested');
        this.dispatchEvent(new CustomEvent('newapplication', {
            detail: { applicationId: null },
            bubbles: true,
            composed: true
        }));
    }
    
    // Handle refresh button click
    handleRefresh() {
        this.refreshLoading = true;
        this.showError = false;
        this.errorMessage = '';
        this.lastRefreshTime = new Date().toLocaleTimeString();
        
        this.forceRefreshApplications();
    }
    
    // Force refresh with cache busting
    async forceRefreshApplications() {
        try {
            // Clear existing data first
            this.applications = [];
            
            // Call Apex method
            const result = await getAllApplications();
            
            if (result.success) {
                const normalized = result.data.map(app => ({
                    ...app,
                    CreatedDate: this.formatDate(app.CreatedDate),
                    VehicleName: app.VehicleName || 'No Vehicle',
                    Status: app.Status || 'Active',
                    statusClass: this.getStatusClass(app.Status || 'Active')
                }));
                this.applications = normalized;
                this.applyFilter();
            } else {
                this.showError = true;
                this.errorMessage = result.message || 'Failed to refresh applications';
            }
        } catch (error) {
            this.showError = true;
            this.errorMessage = 'Error refreshing applications: ' + error.message;
        } finally {
            this.loading = false;
            this.refreshLoading = false;
        }
    }

    handleSearchChange(event) {
        // Normalize incoming value from lightning-input events
        let valueFromEvent = '';
        if (event && event.target) {
            valueFromEvent = event.target.value;
        } else if (event && event.detail && typeof event.detail.value !== 'undefined') {
            valueFromEvent = event.detail.value;
        }
        // Ensure string; guard against numbers like 0 getting coerced
        this.searchTerm = (valueFromEvent || '').toString();
        // Next-tick filter to avoid timing issues
        Promise.resolve().then(() => this.applyFilter());
    }

    applyFilter() {
        const term = (this.searchTerm || '').trim().toLowerCase();
        const source = Array.isArray(this.applications) ? this.applications : [];
        if (!term) {
            this.filteredApplications = [...source];
            return;
        }
        this.filteredApplications = source.filter(app => {
            const name = (app.Name || '').toLowerCase();
            const vehicle = (app.VehicleName || '').toLowerCase();
            const status = (app.Status || '').toLowerCase();
            return name.includes(term) || vehicle.includes(term) || status.includes(term);
        });
        // Ensure reactivity by cloning
        this.filteredApplications = [...this.filteredApplications];
    }
    
    // Method to refresh applications (can be called from parent)
    @api
    refreshApplications() {
        console.log('🔄 refreshApplications called from parent');
        this.forceRefreshApplications();
    }
    
    // Method to test refresh functionality from browser console
    @api
    testRefresh() {
        console.log('🧪 Testing refresh functionality');
        console.log('🧪 Current state:', {
            loading: this.loading,
            refreshLoading: this.refreshLoading,
            showError: this.showError,
            applicationsCount: this.applications.length,
            lastRefreshTime: this.lastRefreshTime
        });
    }
    
    // Method to manually test Apex call from browser console
    // Usage: In browser console, type: document.querySelector('c-dealer-portal-application-list').testApexCall()
    @api
    async testApexCall() {
        console.log('🧪 Testing Apex getAllApplications call directly');
        
        try {
            console.log('🧪 Calling Apex getAllApplications...');
            const result = await getAllApplications();
            console.log('🧪 Apex result:', result);
            console.log('🧪 Result success:', result.success);
            console.log('🧪 Result data count:', result.data ? result.data.length : 'null');
            console.log('🧪 Result totalCount:', result.totalCount);
            console.log('🧪 Result message:', result.message);
            
            if (result.debugInfo) {
                console.log('🧪 Debug info:', result.debugInfo);
            }
            
            if (result.data) {
                console.log('🧪 First few applications:');
                result.data.slice(0, 5).forEach((app, index) => {
                    console.log(`  ${index + 1}. ${app.Id} - ${app.Name} - ${app.VehicleName}`);
                });
            }
            
            return result;
        } catch (error) {
            console.error('🧪 Apex call error:', error);
            return { error: error.message };
        }
    }
    
    // Method to check current application count and details
    // Usage: In browser console, type: document.querySelector('c-dealer-portal-application-list').checkCurrentState()
    @api
    checkCurrentState() {
        console.log('🔍 Current application list state:');
        console.log('  - Total applications:', this.applications.length);
        console.log('  - Loading:', this.loading);
        console.log('  - Refresh loading:', this.refreshLoading);
        console.log('  - Show error:', this.showError);
        console.log('  - Last refresh time:', this.lastRefreshTime);
        
        if (this.applications.length > 0) {
            console.log('  - First application:', this.applications[0]);
            console.log('  - Last application:', this.applications[this.applications.length - 1]);
        }
        
        return {
            count: this.applications.length,
            loading: this.loading,
            refreshLoading: this.refreshLoading,
            lastRefreshTime: this.lastRefreshTime
        };
    }

    formatDate(dateValue) {
        if (!dateValue) return 'N/A';
        
        try {
            const date = new Date(dateValue);
            return date.toLocaleDateString('en-US', {
                year: 'numeric',
                month: 'short',
                day: 'numeric'
            });
        } catch (error) {
            console.error('Error formatting date:', error);
            return 'Invalid Date';
        }
    }

    getStatusClass(status) {
        const statusMap = {
            'Active': 'slds-badge slds-theme_success',
            'Pending': 'slds-badge slds-theme_warning',
            'Completed': 'slds-badge slds-theme_info',
            'Cancelled': 'slds-badge slds-theme_error'
        };
        
        return statusMap[status] || 'slds-badge slds-theme_default';
    }

    // Empty state messages adapt to search/no data
    get emptyTitle() {
        return this.searchTerm ? 'No matches' : 'No Applications Found';
    }
    get emptyMessage() {
        return this.searchTerm ? 'Try a different search or clear the search box.' : 'There are no applications to display. Create a new application to get started.';
    }
}