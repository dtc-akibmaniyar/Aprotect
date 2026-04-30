import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { FlowNavigationFinishEvent, FlowNavigationBackEvent, FlowNavigationNextEvent } from 'lightning/flowSupport';
import getAllocationConfirmationData from '@salesforce/apex/AllocationRemittanceHandler.getAllocationConfirmationData';
import createAllocationRemittanceForm from '@salesforce/apex/AllocationRemittanceHandler.createAllocationRemittanceForm';
import getApplicationsByDealer from '@salesforce/apex/AllocationRemittanceHandler.getApplicationsByDealer';

const SEARCH_DELAY_MS = 300;

// Ordered list of the 3 known service types — used to build availableServicesJson output
const ALL_SERVICE_TYPES = [
    { value: 'Extended_Limited_Warranty', label: 'Extended Limited Warranty' },
    { value: 'Tire_Rim_Protection_Plan',  label: 'Tire & Rim Protection Plan' },
    { value: 'Loan_Protection',           label: 'Car Loan Protection' }
];
// GAP_Coverage is treated as Loan_Protection for display purposes
const GAP_ALIAS = 'GAP_Coverage';

// Standalone mode: 3 options (Loan Protection covers both Loan_Protection + GAP_Coverage)
const SERVICE_TYPE_OPTIONS = [
    { label: 'Extended Limited Warranty', value: 'Extended_Limited_Warranty', checked: false },
    { label: 'Tire & Rim Protection',      value: 'Tire_Rim_Protection_Plan',  checked: false },
    { label: 'Car Loan Protection',         value: 'Loan_Protection',           checked: false }
];

// Flow context: datatable columns
const APP_COLUMNS = [
    { label: 'Application #',    fieldName: 'applicationNumber', type: 'text', sortable: true },
    { label: 'Customer',         fieldName: 'customerName',      type: 'text', sortable: true },
    { label: 'Vehicle',          fieldName: 'vehicleName',       type: 'text', sortable: true },
    { label: 'VIN',              fieldName: 'vehicleVin',        type: 'text', sortable: true },
    { label: 'Invoice Status',   fieldName: 'invoiceStatus',     type: 'text', sortable: true },
    { label: 'Invoice Due Date', fieldName: 'invoiceDueDate',    type: 'date',  sortable: true,
      typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' } },
    { label: 'Overdue Status',         fieldName: 'dueDaysLabel',      type: 'text',  sortable: true,
      cellAttributes: { class: { fieldName: 'dueDaysClass' } } }
];

export default class AllocationRemittanceForm extends NavigationMixin(LightningElement) {

    // ─── Standalone context ────────────────────────────────────────────────────
    @api recordIds = [];

    // ─── Flow context inputs ───────────────────────────────────────────────────
    @api dealerId;
    @api includeWarranty       = false;
    @api includeTireRim        = false;
    @api includeLoanProtection = false;

    // ─── Flow context outputs ──────────────────────────────────────────────────
    @api remittanceFormId;
    @api selectedApplicationIds; // comma-separated IDs of selected apps
    @api availableServicesJson;  // JSON [{label, value}] of services present in selected apps

    // ─── Tracked state ─────────────────────────────────────────────────────────
    @track serviceTypeOptions    = SERVICE_TYPE_OPTIONS.map(o => ({ ...o }));
    @track confirmationData      = [];
    @track showConfirmationModal = false;
    @track isLoading             = false;
    @track isCreating            = false;
    @track errorMessage          = '';

    // Flow context — application list
    @track applications    = [];
    @track selectedAppIds  = [];
    @track searchTerm      = '';
    @track isLoadingMore   = false;
    @track hasMoreRecords  = true;

    columns        = APP_COLUMNS;
    _currentOffset = 0;
    _searchTimer   = null;

    @track sortedBy        = '';
    @track sortedDirection = 'asc';

    // ─── Lifecycle ─────────────────────────────────────────────────────────────

    connectedCallback() {
        if (this.isFlowContext) {
            this.loadDealerApplications();
        }
    }

    // ─── Getters ───────────────────────────────────────────────────────────────

    get isFlowContext() {
        return !!this.dealerId;
    }

    get selectedServiceTypes() {
        if (this.isFlowContext) {
            const types = [];
            if (this.includeWarranty)        types.push('Extended_Limited_Warranty');
            if (this.includeTireRim)         types.push('Tire_Rim_Protection_Plan');
            if (this.includeLoanProtection)  { types.push('Loan_Protection'); types.push('GAP_Coverage'); }
            // If no specific services configured, load all — service selection happens on the next screen
            if (types.length === 0) return ALL_SERVICE_TYPES.map(s => s.value).concat(['GAP_Coverage']);
            return types;
        }
        const types = this.serviceTypeOptions.filter(o => o.checked).map(o => o.value);
        if (types.includes('Loan_Protection') && !types.includes('GAP_Coverage')) {
            types.push('GAP_Coverage');
        }
        return types;
    }

    get selectedServiceLabels() {
        const labels = this.serviceTypeOptions.filter(o => o.checked).map(o => o.label);
        return labels.length ? labels.join(', ') : 'None';
    }

    get isPreviewDisabled() {
        return this.isLoading || this.selectedServiceTypes.length === 0;
    }

    get hasConfirmationData() {
        return this.confirmationData && this.confirmationData.length > 0;
    }

    get hasApplications() {
        return this.applications && this.applications.length > 0;
    }

    get isNextDisabled() {
        return this.selectedAppIds.length === 0;
    }

    get isCreateDisabled() {
        return this.isCreating || this.selectedAppIds.length === 0;
    }

    get grandTotal() {
        let total = 0;
        this.confirmationData.forEach(app => {
            app.lineItems.forEach(li => { total += li.priceWithTax || 0; });
        });
        return this.formatCurrency(total);
    }

    get selectedCount() {
        return this.selectedAppIds.length;
    }

    // ─── Flow context — search ─────────────────────────────────────────────────

    handleSearch(event) {
        const val = event.target.value;
        clearTimeout(this._searchTimer);
        this._searchTimer = setTimeout(() => {
            this.searchTerm = val;
            this.loadDealerApplications(); // reset list with new search
        }, SEARCH_DELAY_MS);
    }

    // ─── Flow context — initial load (reset) ──────────────────────────────────

    async loadDealerApplications() {
        this.isLoading       = true;
        this.errorMessage    = '';
        this.applications    = [];
        this.selectedAppIds  = [];
        this._currentOffset  = 0;
        this.hasMoreRecords  = true;

        try {
            const result = await getApplicationsByDealer({
                dealerId:             this.dealerId,
                selectedServiceTypes: this.selectedServiceTypes,
                searchTerm:           this.searchTerm,
                pageOffset:           0
            });
            if (result.errorMessage) {
                this.errorMessage = result.errorMessage;
                return;
            }
            this.applications    = (result.confirmationList || []).map(a => this._mapApp(a));
            this.hasMoreRecords  = result.hasMore === true;
            this._currentOffset  = this.applications.length;
        } catch (error) {
            this.errorMessage = error.body?.message || 'Failed to load applications.';
        } finally {
            this.isLoading = false;
        }
    }

    // ─── Flow context — load next page (append) ────────────────────────────────

    handleLoadMore() {
        if (!this.hasMoreRecords || this.isLoadingMore) return;
        this.loadMoreApplications();
    }

    async loadMoreApplications() {
        this.isLoadingMore = true;
        try {
            const result = await getApplicationsByDealer({
                dealerId:             this.dealerId,
                selectedServiceTypes: this.selectedServiceTypes,
                searchTerm:           this.searchTerm,
                pageOffset:           this._currentOffset
            });
            if (result.errorMessage) {
                this.errorMessage = result.errorMessage;
                return;
            }
            const next = (result.confirmationList || []).map(a => this._mapApp(a));
            this.applications    = [...this.applications, ...next];
            this.hasMoreRecords  = result.hasMore === true;
            this._currentOffset  = this.applications.length;
        } catch (error) {
            this.errorMessage = error.body?.message || 'Failed to load more applications.';
        } finally {
            this.isLoadingMore = false;
        }
    }

    // ─── Flow context — row selection / create ─────────────────────────────────

    handleRowSelection(event) {
        const selectedRows = event.detail.selectedRows;
        this.selectedAppIds = selectedRows.map(row => row.applicationId);

        // Build union of service types across selected apps
        const unionSet = new Set();
        selectedRows.forEach(row => {
            (row.serviceTypes || []).forEach(st => {
                // Normalise GAP_Coverage → Loan_Protection for display
                unionSet.add(st === GAP_ALIAS ? 'Loan_Protection' : st);
            });
        });

        // Filter known services in order, keeping only those present in selection
        const available = ALL_SERVICE_TYPES.filter(s => unionSet.has(s.value));
        this.availableServicesJson = JSON.stringify(available);
    }

    handleFlowNext() {
        if (this.selectedAppIds.length === 0) {
            this.errorMessage = 'Please select at least one application.';
            return;
        }
        this.errorMessage = '';
        this.selectedApplicationIds = this.selectedAppIds.join(',');
        this.dispatchEvent(new FlowNavigationNextEvent());
    }

    handleFlowBack() {
        this.dispatchEvent(new FlowNavigationBackEvent());
    }

    // ─── Standalone context event handlers ────────────────────────────────────

    handleServiceTypeChange(event) {
        const value = event.target.value;
        this.serviceTypeOptions = this.serviceTypeOptions.map(o =>
            o.value === value ? { ...o, checked: event.target.checked } : o
        );
        this.errorMessage = '';
    }

    async handlePreview() {
        if (this.selectedServiceTypes.length === 0) {
            this.errorMessage = 'Please select at least one service type.';
            return;
        }
        if (!this.recordIds || this.recordIds.length === 0) {
            this.errorMessage = 'No applications provided.';
            return;
        }
        this.isLoading    = true;
        this.errorMessage = '';
        try {
            const result = await getAllocationConfirmationData({
                applicationIds:       this.recordIds,
                selectedServiceTypes: this.selectedServiceTypes
            });
            if (result.errorMessage) { this.errorMessage = result.errorMessage; return; }
            this.confirmationData = (result.confirmationList || []).map(app => ({
                ...app,
                lineItems: (app.lineItems || []).map(li => ({
                    ...li,
                    formattedPrice: this.formatCurrency(li.priceWithTax || 0)
                })),
                formattedTotal: this.formatCurrency(
                    (app.lineItems || []).reduce((sum, li) => sum + (li.priceWithTax || 0), 0)
                )
            }));
            this.showConfirmationModal = true;
        } catch (error) {
            this.errorMessage = error.body?.message || 'Failed to load preview data.';
        } finally {
            this.isLoading = false;
        }
    }

    handleBack() {
        this.showConfirmationModal = false;
        this.confirmationData      = [];
        this.errorMessage          = '';
    }

    async handleConfirmCreate() {
        this.isCreating   = true;
        this.errorMessage = '';
        try {
            const result = await createAllocationRemittanceForm({
                applicationIds:       this.recordIds,
                selectedServiceTypes: this.selectedServiceTypes
            });
            if (result.success) {
                this.showToast('Success', 'Allocation Remittance Form created successfully.', 'success');
                debugger;
                setTimeout(() => {
                    this[NavigationMixin.Navigate]({
                        type: 'standard__recordPage',
                        attributes: {
                            recordId:      result.remittanceFormId,
                            objectApiName: 'Remittance_Form__c',
                            actionName:    'view'
                        }
                    });
                }, 1500);
            } else {
                this.errorMessage = result.message;
            }
        } catch (error) {
            this.errorMessage = error.body?.message || 'Failed to create Allocation Remittance Form.';
        } finally {
            this.isCreating = false;
        }
    }

    // ─── Flow context — column sort ────────────────────────────────────────────

    handleSort(event) {
        const { fieldName, sortDirection } = event.detail;
        this.sortedBy        = fieldName;
        this.sortedDirection = sortDirection;

        // dueDaysLabel is a formatted string — sort by numeric invoiceDueDays instead
        const sortKey = fieldName === 'dueDaysLabel' ? 'invoiceDueDays' : fieldName;
        const multiplier = sortDirection === 'asc' ? 1 : -1;

        this.applications = [...this.applications].sort((a, b) => {
            const aVal = a[sortKey] ?? '';
            const bVal = b[sortKey] ?? '';
            if (aVal === bVal) return 0;
            if (aVal === '' || aVal == null) return 1;
            if (bVal === '' || bVal == null) return -1;
            return aVal < bVal ? -1 * multiplier : 1 * multiplier;
        });
    }

    // ─── Helpers ───────────────────────────────────────────────────────────────

    _mapApp(app) {
        const days = app.invoiceDueDays;
        let dueDaysLabel = '';
        let dueDaysClass = '';

        if (days != null) {
            if (days === 0) {
                dueDaysLabel = 'Due Today';
                dueDaysClass = 'slds-text-color_warning';
            } else if (days > 0) {
                dueDaysLabel = days + ' day' + (days === 1 ? '' : 's') + ' overdue';
                dueDaysClass = 'slds-text-color_error';
            } else {
                const remaining = Math.abs(days);
                dueDaysLabel = 'In ' + remaining + ' day' + (remaining === 1 ? '' : 's');
                dueDaysClass = 'slds-text-color_success';
            }
        }

        return {
            applicationId:     app.applicationId,
            applicationNumber: app.applicationNumber,
            customerName:      app.customerName,
            vehicleName:       app.vehicleName,
            vehicleVin:        app.vehicleVin,
            serviceTypes:      app.serviceTypes || [],
            invoiceStatus:     app.invoiceStatus  || '',
            invoiceDueDate:    app.invoiceDueDate  || null,
            invoiceDueDays:    days,
            dueDaysLabel,
            dueDaysClass
        };
    }

    formatCurrency(value) {
        return '$' + (value || 0).toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}