import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCompanyNotices from '@salesforce/apex/DealerActionBoardController.getCompanyNotices';
import getDealerNotices from '@salesforce/apex/DealerActionBoardController.getDealerNotices';
import getUnpaidApplications from '@salesforce/apex/DealerActionBoardController.getUnpaidApplications';
import createNewQuote from '@salesforce/apex/QuotesListViewController.createNewQuote';
import createNewApplication from '@salesforce/apex/ApplicationsListViewController.createNewApplication';
import createRemittanceForm from '@salesforce/apex/DealerPortalRemittanceHandler.createRemittanceForm';
import BUILD_QUOTE from '@salesforce/resourceUrl/BuildQuote';
import ADD_NEW_APP from '@salesforce/resourceUrl/AddNewApplication';
import VIEW_Q_APP from '@salesforce/resourceUrl/ViewQuoteAndViewApplication';
import DEALER_SUPP from '@salesforce/resourceUrl/DealerSuppost';
import MAKE_PAYMENT from '@salesforce/resourceUrl/MakePayment';

export default class DealerActionBoard extends NavigationMixin(LightningElement) {
    messages = [
        { id: 1, title: 'System Update', body: 'New Sales Dashboard features available now.' },
        { id: 2, title: 'Dealer Event', body: 'Annual Dealer Meet scheduled for December 10th.' },
        { id: 3, title: 'Reminder', body: 'Submit inventory reports by Friday.' }
    ];
    staticResources = {
        buildQuote: BUILD_QUOTE,
        addNewApplication: ADD_NEW_APP,
        viewQuoteAndViewApplication: VIEW_Q_APP,
        dealerSuppost: DEALER_SUPP,
        makePayment: MAKE_PAYMENT
    };

    // Tab state
    activeTab = 'aprotect';
    
    // Modal states
    @track showNewQuoteModal = false;
    @track showNewApplicationModal = false;
    @track isCreating = false;

    // Make Payment modal state
    @track showMakePaymentModal = false;
    @track unpaidApplications = [];
    @track selectedAppIds = [];
    @track isLoadingApplications = false;
    @track isCreatingRemittance = false;

    // Company notices
    companyNotices = [];
    companyNoticesError;

    @wire(getCompanyNotices)
    wiredCompanyNotices({ error, data }) {
        if (data) {
            this.companyNotices = data;
            this.companyNoticesError = undefined;
        } else if (error) {
            this.companyNoticesError = error;
            this.companyNotices = [];
        }
    }

    // Dealer notices
    dealerNotices = [];
    dealerNoticesError;

    @wire(getDealerNotices)
    wiredDealerNotices({ error, data }) {
        if (data) {
            this.dealerNotices = data;
            this.dealerNoticesError = undefined;
        } else if (error) {
            this.dealerNoticesError = error;
            this.dealerNotices = [];
        }
    }

    get hasCompanyNotices() {
        return this.companyNotices && this.companyNotices.length > 0;
    }

    get hasDealerNotices() {
        return this.dealerNotices && this.dealerNotices.length > 0;
    }

    get formattedCompanyNotices() {
        return this.companyNotices.map(n => ({
            ...n,
            formattedDate: n.CreatedDate
                ? new Date(n.CreatedDate).toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: '2-digit' })
                : ''
        }));
    }

    get formattedDealerNotices() {
        return this.dealerNotices.map(n => ({
            ...n,
            formattedDate: n.CreatedDate
                ? new Date(n.CreatedDate).toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: '2-digit' })
                : ''
        }));
    }

    get isAProtectTab() {
        return this.activeTab === 'aprotect';
    }

    get isDealerTab() {
        return this.activeTab === 'dealer';
    }

    get aProtectTabClass() {
        return this.activeTab === 'aprotect' ? 'tab-btn active' : 'tab-btn';
    }

    get dealerTabClass() {
        return this.activeTab === 'dealer' ? 'tab-btn active' : 'tab-btn';
    }

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }

    handleClick(event) {
        const action = event.currentTarget.dataset.action;

        switch (action) {
            case 'build-quote':
                this.showNewQuoteModal = true;
                break;

            case 'add-new-application':
                this.showNewApplicationModal = true;
                break;

            case 'view-quotes':
                // Navigate to the Quotes page using NavigationMixin
                this[NavigationMixin.Navigate]({
                    type: 'comm__namedPage',
                    attributes: {
                        pageName: 'quotes'
                    }
                });
                break;

            case 'view-applications':
                // Navigate to the Record List for Application__c using NavigationMixin
                this[NavigationMixin.Navigate]({
                    type: "standard__objectPage",
                    attributes: {
                        objectApiName: "Application__c",
                        actionName: "list",
                    }
                    });
                break;

            case 'make-a-payment':
                this.handleOpenMakePaymentModal();
                break;

            case 'dealer-support':
                // Navigate to the Case object list view
                this[NavigationMixin.Navigate]({
                    type: 'standard__objectPage',
                    attributes: {
                        objectApiName: 'Case',
                        actionName: 'list'
                    }
                    ,
                    state: {
                        "Case-filterId": "MyCases"
                    }
                });
                break;

            default:
                // No action for other tiles yet
                break;
        }
    }

    // New Quote Modal Handlers
    handleCloseNewQuoteModal() {
        this.showNewQuoteModal = false;
    }

    async handleContinueToCreateQuote() {
        // Create a new quote using Apex
        this.isCreating = true;
        try {
            const result = await createNewQuote();
            
            if (result.success && result.recordId) {
                // Navigate to the new record in view mode
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: result.recordId,
                        objectApiName: 'Application__c',
                        actionName: 'view'
                    }
                });
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Created',
                    message: 'New quote created',
                    variant: 'success'
                }));
                this.handleCloseNewQuoteModal();
            } else {
                throw new Error(result.message || 'Failed to create record');
            }
        } catch (err) {
            const msg = (err && err.body && err.body.message) || err.message || JSON.stringify(err);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error creating quote',
                message: msg,
                variant: 'error'
            }));
            console.error('Error creating quote', err);
        } finally {
            this.isCreating = false;
        }
    }

    // Make Payment Modal Getters
    _formatCurrency(amount) {
        if (amount == null) return '$0.00';
        return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(amount);
    }

    get hasUnpaidApplications() {
        return this.unpaidApplications && this.unpaidApplications.length > 0;
    }

    get applicationsWithSelection() {
        const selectedSet = new Set(this.selectedAppIds);
        return this.unpaidApplications.map(app => {
            const packages = (app.packages || []).map(pkg => ({
                ...pkg,
                formattedPrice: this._formatCurrency(pkg.price)
            }));
            return {
                ...app,
                isSelected: selectedSet.has(app.id),
                packages,
                formattedSubTotal: this._formatCurrency(app.subTotal),
                formattedTotal: this._formatCurrency(app.total)
            };
        });
    }

    get isAllAppsSelected() {
        return this.unpaidApplications.length > 0 &&
               this.selectedAppIds.length === this.unpaidApplications.length;
    }

    get selectedCount() {
        return this.selectedAppIds.length;
    }

    get remittanceFormTotalFormatted() {
        const selectedSet = new Set(this.selectedAppIds);
        const total = this.unpaidApplications
            .filter(app => selectedSet.has(app.id))
            .reduce((sum, app) => sum + (app.total || 0), 0);
        return this._formatCurrency(total);
    }

    get isCreateRemittanceDisabled() {
        return this.selectedAppIds.length === 0 || this.isCreatingRemittance;
    }

    // Make Payment Modal Handlers
    async handleOpenMakePaymentModal() {
        this.showMakePaymentModal = true;
        this.selectedAppIds = [];
        this.unpaidApplications = [];
        this.isLoadingApplications = true;
        try {
            const apps = await getUnpaidApplications();
            this.unpaidApplications = apps || [];
        } catch (err) {
            const msg = (err && err.body && err.body.message) || err.message || JSON.stringify(err);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error loading applications',
                message: msg,
                variant: 'error'
            }));
        } finally {
            this.isLoadingApplications = false;
        }
    }

    handleCloseMakePaymentModal() {
        this.showMakePaymentModal = false;
        this.unpaidApplications = [];
        this.selectedAppIds = [];
    }

    handleAppCheckboxChange(event) {
        const appId = event.currentTarget.dataset.id;
        const isChecked = event.target.checked;
        if (isChecked) {
            if (!this.selectedAppIds.includes(appId)) {
                this.selectedAppIds = [...this.selectedAppIds, appId];
            }
        } else {
            this.selectedAppIds = this.selectedAppIds.filter(id => id !== appId);
        }
    }

    handleSelectAllApps(event) {
        if (event.target.checked) {
            this.selectedAppIds = this.unpaidApplications.map(app => app.id);
        } else {
            this.selectedAppIds = [];
        }
    }

    async handleCreateRemittanceForm() {
        this.isCreatingRemittance = true;
        try {
            const result = await createRemittanceForm({ applicationIds: this.selectedAppIds });
            if (result.success && result.remittanceFormId) {
                this.handleCloseMakePaymentModal();
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: result.remittanceFormId,
                        objectApiName: 'Remittance_Form__c',
                        actionName: 'view'
                    }
                });
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Success',
                    message: 'Remittance form created successfully',
                    variant: 'success'
                }));
            } else {
                throw new Error(result.message || 'Failed to create remittance form');
            }
        } catch (err) {
            const msg = (err && err.body && err.body.message) || err.message || JSON.stringify(err);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: msg,
                variant: 'error'
            }));
        } finally {
            this.isCreatingRemittance = false;
        }
    }

    // New Application Modal Handlers
    handleCloseNewApplicationModal() {
        this.showNewApplicationModal = false;
    }

    async handleContinueToCreateApplication() {
        // Create a new application using Apex with 'Application' record type
        this.isCreating = true;
        try {
            const result = await createNewApplication();
            
            if (result.success && result.recordId) {
                // Navigate to the new record in view mode so the user can fill details
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: result.recordId,
                        objectApiName: 'Application__c',
                        actionName: 'view'
                    }
                });
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Created',
                    message: 'New application created',
                    variant: 'success'
                }));
                this.handleCloseNewApplicationModal();
            } else {
                throw new Error(result.message || 'Failed to create record');
            }
        } catch (err) {
            const msg = (err && err.body && err.body.message) || err.message || JSON.stringify(err);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error creating application',
                message: msg,
                variant: 'error'
            }));
            console.error('Error creating application', err);
        } finally {
            this.isCreating = false;
        }
    }
}