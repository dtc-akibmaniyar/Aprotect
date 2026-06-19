import { LightningElement, track, api } from 'lwc';
import getRemittanceFormsList from '@salesforce/apex/DealerPortalRemittanceListController.getRemittanceFormsList';

const STATUS_CONFIG = {
    'Open':      { class: 'status-badge status-open',      label: 'Open' },
    'Completed': { class: 'status-badge status-completed',  label: 'Completed' },
    'Expired':   { class: 'status-badge status-expired',    label: 'Expired' },
    'Cancelled': { class: 'status-badge status-cancelled',  label: 'Cancelled' },
    'Paid':      { class: 'status-badge status-completed',  label: 'Paid' }
};

export default class DealerPortalRemittanceList extends LightningElement {
    @api title = 'Remittance Forms';
    @api description = 'View and manage your remittance forms';

    @track remittanceForms = [];
    @track loading = true;
    @track refreshLoading = false;
    @track showError = false;
    @track errorMessage = '';
    @track statusFilter = 'All';
    @track lastRefreshTime = null;

    // Pagination
    @track pageNumber = 1;
    @track pageSize = 10;
    @track totalCount = 0;
    @track totalPages = 1;

    // Sorting
    @track sortField = 'createdDate';
    @track sortDirection = 'desc';

    get statusFilterOptions() {
        return [
            { label: 'All Statuses', value: 'All' },
            { label: 'Open', value: 'Open' },
            { label: 'Completed', value: 'Completed' },
            { label: 'Expired', value: 'Expired' },
            { label: 'Cancelled', value: 'Cancelled' }
        ];
    }

    get showTable() {
        return !this.loading && !this.showError;
    }

    get hasRecords() {
        return this.remittanceForms.length > 0;
    }

    get refreshButtonClass() {
        return `refresh-button ${this.refreshLoading ? 'loading' : ''}`;
    }

    get showPagination() {
        return this.totalPages > 1;
    }

    get isFirstPage() {
        return this.pageNumber <= 1;
    }

    get isLastPage() {
        return this.pageNumber >= this.totalPages;
    }

    get paginationInfo() {
        const start = ((this.pageNumber - 1) * this.pageSize) + 1;
        const end = Math.min(this.pageNumber * this.pageSize, this.totalCount);
        return `${start}–${end} of ${this.totalCount}`;
    }

    get emptyTitle() {
        if (this.statusFilter !== 'All') return 'No matches';
        return 'No Remittance Forms Found';
    }

    get emptyMessage() {
        if (this.statusFilter !== 'All') return 'Try adjusting your filters.';
        return 'There are no remittance forms to display.';
    }

    // Sort indicators
    get sortNameIcon() { return this.sortField === 'name' ? (this.sortDirection === 'asc' ? '▲' : '▼') : ''; }
    get sortStatusIcon() { return this.sortField === 'status' ? (this.sortDirection === 'asc' ? '▲' : '▼') : ''; }
    get sortCreatedDateIcon() { return this.sortField === 'createdDate' ? (this.sortDirection === 'asc' ? '▲' : '▼') : ''; }
    get sortExpiryDateIcon() { return this.sortField === 'expiryDate' ? (this.sortDirection === 'asc' ? '▲' : '▼') : ''; }
    get sortAmountIcon() { return this.sortField === 'amount' ? (this.sortDirection === 'asc' ? '▲' : '▼') : ''; }
    get sortBalanceIcon() { return this.sortField === 'balance' ? (this.sortDirection === 'asc' ? '▲' : '▼') : ''; }

    connectedCallback() {
        this.loadRemittanceForms();
    }

    async loadRemittanceForms() {
        this.loading = true;
        this.showError = false;

        try {
            const result = await getRemittanceFormsList({
                pageNumber: this.pageNumber,
                pageSize: this.pageSize,
                statusFilter: this.statusFilter
            });

            if (result.success) {
                this.remittanceForms = result.data.map(form => this.enrichRow(form));
                this.totalCount = result.totalCount;
                this.totalPages = result.totalPages;
                this.pageNumber = result.pageNumber;
            } else {
                this.showError = true;
                this.errorMessage = result.message || 'Failed to load remittance forms';
            }
        } catch (error) {
            this.showError = true;
            this.errorMessage = 'Error loading remittance forms: ' + (error.body ? error.body.message : error.message);
        } finally {
            this.loading = false;
            this.refreshLoading = false;
        }
    }

    enrichRow(form) {
        const config = STATUS_CONFIG[form.status] || { class: 'status-badge status-default', label: form.status || 'Unknown' };
        const isExpiringSoon = form.expiryDate && this.isWithinDays(form.expiryDate, 7) && form.status === 'Open';

        return {
            ...form,
            statusClass: config.class,
            statusLabel: config.label,
            createdDateFormatted: this.formatDate(form.createdDate),
            expiryDateFormatted: form.expiryDate ? this.formatDate(form.expiryDate) : '—',
            expiryDateClass: isExpiringSoon ? 'expiry-warning' : '',
            amountFormatted: this.formatCurrency(form.amount),
            balanceFormatted: this.formatCurrency(form.balance),
            paidAmountFormatted: this.formatCurrency(form.paidAmount),
            lineItemsSummary: `${form.paidLineItems || 0}/${form.plannedLineItems || 0}`,
            progressPercent: form.plannedLineItems > 0 ? Math.round((form.paidLineItems / form.plannedLineItems) * 100) : 0,
            progressClass: form.paidLineItems === form.plannedLineItems && form.plannedLineItems > 0 ? 'progress-complete' : 'progress-partial'
        };
    }

    isWithinDays(dateStr, days) {
        const date = new Date(dateStr);
        const now = new Date();
        const diffMs = date.getTime() - now.getTime();
        const diffDays = diffMs / (1000 * 60 * 60 * 24);
        return diffDays >= 0 && diffDays <= days;
    }

    formatDate(dateValue) {
        if (!dateValue) return '—';
        try {
            const date = new Date(dateValue);
            return date.toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' });
        } catch (e) {
            return 'Invalid Date';
        }
    }

    formatCurrency(value) {
        if (value == null) return '$0.00';
        return '$' + Number(value).toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    handleStatusFilterChange(event) {
        this.statusFilter = event.detail.value;
        this.pageNumber = 1;
        this.loadRemittanceForms();
    }

    handleRefresh() {
        this.refreshLoading = true;
        this.lastRefreshTime = new Date().toLocaleTimeString();
        this.loadRemittanceForms();
    }

    handleSort(event) {
        const field = event.currentTarget.dataset.field;
        if (this.sortField === field) {
            this.sortDirection = this.sortDirection === 'asc' ? 'desc' : 'asc';
        } else {
            this.sortField = field;
            this.sortDirection = 'asc';
        }
        this.sortData();
    }

    sortData() {
        const field = this.sortField;
        const dir = this.sortDirection === 'asc' ? 1 : -1;

        this.remittanceForms = [...this.remittanceForms].sort((a, b) => {
            let valA = a[field];
            let valB = b[field];
            if (valA == null) valA = '';
            if (valB == null) valB = '';
            if (typeof valA === 'string') valA = valA.toLowerCase();
            if (typeof valB === 'string') valB = valB.toLowerCase();
            if (valA < valB) return -1 * dir;
            if (valA > valB) return 1 * dir;
            return 0;
        });
    }

    handleRemittanceClick(event) {
        event.preventDefault();
        const remittanceId = event.currentTarget.dataset.id;
        const recordUrl = event.currentTarget.dataset.url;

        // Navigate to record detail in community
        if (recordUrl) {
            window.location.href = recordUrl;
        }
    }

    handlePrevPage() {
        if (this.pageNumber > 1) {
            this.pageNumber--;
            this.loadRemittanceForms();
        }
    }

    handleNextPage() {
        if (this.pageNumber < this.totalPages) {
            this.pageNumber++;
            this.loadRemittanceForms();
        }
    }

    @api
    refreshList() {
        this.loadRemittanceForms();
    }
}