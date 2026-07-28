import { LightningElement, api, track } from 'lwc';

export default class DealerMakePaymentModal extends LightningElement {
    @api unpaidApplications = [];
    @api isLoading = false;

    @track searchTerm = '';
    @track activeFilter = 'all';
    @track expandedAppIds = new Set();
    @track selectedAppIds = [];
    @track summarySearchTerm = '';
    @track isSummaryExpanded = true;
    @track showCheckbox = true;

    // ── Aging helpers ──────────────────────────────────────────
    _agingBucket(agingDays) {
        if (agingDays == null || agingDays < 30) return 'current';
        if (agingDays < 60) return '30plus';
        if (agingDays < 90) return '60plus';
        return '90plus';
    }

    _agingLabel(agingDays) {
        const b = this._agingBucket(agingDays);
        if (b === 'current') return 'Current';
        if (b === '30plus') return '30+ Days';
        if (b === '60plus') return '60+ Days';
        return '90+ Days';
    }

    _agingClass(agingDays) {
        const b = this._agingBucket(agingDays);
        if (b === 'current') return 'aging-badge aging-current';
        if (b === '30plus') return 'aging-badge aging-30';
        if (b === '60plus') return 'aging-badge aging-60';
        return 'aging-badge aging-90';
    }

    _formatCurrency(amount) {
        if (amount == null) return '$0.00';
        return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(amount);
    }

    _formatDate(dateVal) {
        if (!dateVal) return '';
        const d = new Date(dateVal);
        return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
    }

    // ── Enriched apps (add computed display fields) ──────────
    get enrichedApps() {
        return (this.unpaidApplications || []).map(app => {
            const isSelected = this.selectedAppIds.includes(app.id);
            const isExpanded = this.expandedAppIds.has(app.id);
            return {
                ...app,
                agingLabel: this._agingLabel(app.agingDays),
                agingClass: this._agingClass(app.agingDays),
                agingBucket: this._agingBucket(app.agingDays),
                formattedDate: this._formatDate(app.appCreatedDate),
                formattedTotal: this._formatCurrency(app.total),
                packages: (app.packages || []).map(pkg => ({
                    ...pkg,
                    formattedPrice: this._formatCurrency(pkg.price)
                })),
                packageCountLabel: (app.packages || []).length === 1
                    ? '(1) Product'
                    : `(${(app.packages || []).length}) Products`,
                isExpanded: isExpanded,
                isSelected: isSelected,
                appRowClass: isSelected ? 'app-row selected' : 'app-row',
                expandIcon: isExpanded ? 'utility:chevronup' : 'utility:chevrondown'
            };
        });
    }

    // ── Filter counts ─────────────────────────────────────────
    get allCount() { return this.enrichedApps.length; }
    get currentCount() { return this.enrichedApps.filter(a => a.agingBucket === 'current').length; }
    get thirtyCount() { return this.enrichedApps.filter(a => a.agingBucket === '30plus').length; }
    get sixtyCount() { return this.enrichedApps.filter(a => a.agingBucket === '60plus').length; }
    get ninetyCount() { return this.enrichedApps.filter(a => a.agingBucket === '90plus').length; }

    _tabClass(id) {
        return this.activeFilter === id ? 'filter-tab active' : 'filter-tab';
    }

    get filterTabs() {
        return [
            { id: 'all', label: 'ALL', count: this.allCount, isActive: this.activeFilter === 'all', tabClass: this._tabClass('all') },
            { id: 'current', label: 'Current', count: this.currentCount, isActive: this.activeFilter === 'current', tabClass: this._tabClass('current') },
            { id: '30plus', label: '30+ Days', count: this.thirtyCount, isActive: this.activeFilter === '30plus', tabClass: this._tabClass('30plus') },
            { id: '60plus', label: '60+ Days', count: this.sixtyCount, isActive: this.activeFilter === '60plus', tabClass: this._tabClass('60plus') },
            { id: '90plus', label: '90+ Days', count: this.ninetyCount, isActive: this.activeFilter === '90plus', tabClass: this._tabClass('90plus') },
        ];
    }

    // ── Filtered + searched list ──────────────────────────────
    get filteredApps() {
        let apps = this.enrichedApps;
        if (this.activeFilter !== 'all') {
            apps = apps.filter(a => a.agingBucket === this.activeFilter);
        }
        if (this.searchTerm) {
            const term = this.searchTerm.toLowerCase();
            apps = apps.filter(a =>
                (a.appNumber || '').toLowerCase().includes(term) ||
                (a.customerName || '').toLowerCase().includes(term)
            );
        }
        // Sort descending by agingDays — oldest first
        apps = apps.slice().sort((a, b) => (b.agingDays || 0) - (a.agingDays || 0));
        // Build global aging order across ALL apps (ignores tab + search filters)
        // so that disable logic is always relative to true aging sequence
        const globalSorted = this.enrichedApps.slice().sort((a, b) => (b.agingDays || 0) - (a.agingDays || 0));
        apps = apps.map(app => {
            const globalIdx = globalSorted.findIndex(a => a.id === app.id);
            const isDisabled = globalIdx > 0 && !this.selectedAppIds.includes(globalSorted[globalIdx - 1].id);
            return {
                ...app,
                isDisabled,
                appRowClass: app.isSelected ? 'app-row selected' : 'app-row'
            };
        });
        return apps;
    }

    get hasFilteredApps() { return this.filteredApps.length > 0; }

    // ── Selection helpers ─────────────────────────────────────
    get selectedCount() { return this.selectedAppIds.length; }
    get totalCount() { return this.enrichedApps.length; }
    get isAllSelected() {
        return this.filteredApps.length > 0 &&
            this.filteredApps.every(a => this.selectedAppIds.includes(a.id));
    }
    get hasSelection() { return this.selectedAppIds.length > 0; }
    get isCreateDisabled() { return this.selectedAppIds.length === 0; }

    // ── Outstanding balance — ALL apps regardless of selection ──
    get outstandingCurrentTotal() {
        return this._formatCurrency(
            this.enrichedApps.filter(a => a.agingBucket === 'current').reduce((s, a) => s + (a.total || 0), 0)
        );
    }
    get outstandingThirtyTotal() {
        return this._formatCurrency(
            this.enrichedApps.filter(a => a.agingBucket === '30plus').reduce((s, a) => s + (a.total || 0), 0)
        );
    }
    get outstandingSixtyTotal() {
        return this._formatCurrency(
            this.enrichedApps.filter(a => a.agingBucket === '60plus').reduce((s, a) => s + (a.total || 0), 0)
        );
    }
    get outstandingNinetyTotal() {
        return this._formatCurrency(
            this.enrichedApps.filter(a => a.agingBucket === '90plus').reduce((s, a) => s + (a.total || 0), 0)
        );
    }
    get outstandingGrandTotal() {
        return this._formatCurrency(
            this.enrichedApps.reduce((s, a) => s + (a.total || 0), 0)
        );
    }

    // ── Summary panel ─────────────────────────────────────────
    get selectedApps() {
        const sel = new Set(this.selectedAppIds);
        return this.enrichedApps.filter(a => sel.has(a.id));
    }

    get summarySubtotal() {
        return this.selectedApps.reduce((s, a) => s + (a.subTotal || 0), 0);
    }

    get taxPercentage() {
        // Use taxPercentage from first selected app's data
        const first = this.selectedApps[0];
        return first ? (first.taxPercentage || 0) : 0;
    }

    get taxAmount() {
        return this.selectedApps.reduce((s, a) => s + (a.taxAmount || 0), 0);
    }

    get totalDue() {
        return this.selectedApps.reduce((s, a) => s + (a.total || 0), 0);
    }

    get formattedSubtotal() { return this._formatCurrency(this.summarySubtotal); }
    get formattedTax() { return this._formatCurrency(this.taxAmount); }
    get formattedTotal() { return this._formatCurrency(this.totalDue); }
    get taxLabel() { return `Tax (${this.taxPercentage}%)`; }

    // Aging bucket subtotals for selected apps
    get summaryCurrentSubtotal() {
        return this._formatCurrency(
            this.selectedApps.filter(a => a.agingBucket === 'current').reduce((s, a) => s + (a.total || 0), 0)
        );
    }
    get summaryThirtySubtotal() {
        return this._formatCurrency(
            this.selectedApps.filter(a => a.agingBucket === '30plus').reduce((s, a) => s + (a.total || 0), 0)
        );
    }
    get summarySixtySubtotal() {
        return this._formatCurrency(
            this.selectedApps.filter(a => a.agingBucket === '60plus').reduce((s, a) => s + (a.total || 0), 0)
        );
    }
    get summaryNinetySubtotal() {
        return this._formatCurrency(
            this.selectedApps.filter(a => a.agingBucket === '90plus').reduce((s, a) => s + (a.total || 0), 0)
        );
    }
    get summaryCurrentCount() { return this.selectedApps.filter(a => a.agingBucket === 'current').length; }
    get summaryThirtyCount() { return this.selectedApps.filter(a => a.agingBucket === '30plus').length; }
    get summarySixtyCount() { return this.selectedApps.filter(a => a.agingBucket === '60plus').length; }
    get summaryNinetyCount() { return this.selectedApps.filter(a => a.agingBucket === '90plus').length; }

    get filteredSummaryApps() {
        if (!this.summarySearchTerm) return this.selectedApps;
        const term = this.summarySearchTerm.toLowerCase();
        return this.selectedApps.filter(a =>
            (a.appNumber || '').toLowerCase().includes(term) ||
            (a.customerName || '').toLowerCase().includes(term)
        );
    }

    get summaryToggleIcon() { return this.isSummaryExpanded ? 'utility:chevrondown' : 'utility:chevronright'; }

    // ── Event handlers ────────────────────────────────────────
    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
    }

    handleFilterTab(event) {
        this.activeFilter = event.currentTarget.dataset.filter;
        if (this.activeFilter !== 'all') {
            this.showCheckbox = false;
            this.selectedAppIds = [];
        } else {
            this.showCheckbox = true;
        }
    }

    handleSelectAll(event) {
        if (event.target.checked) {
            const filteredIds = this.filteredApps.map(a => a.id);
            const combined = new Set([...this.selectedAppIds, ...filteredIds]);
            this.selectedAppIds = Array.from(combined);
        } else {
            const filteredIds = new Set(this.filteredApps.map(a => a.id));
            this.selectedAppIds = this.selectedAppIds.filter(id => !filteredIds.has(id));
        }
    }

    handleAppCheckbox(event) {
        const appId = event.currentTarget.dataset.id;
        if (event.target.checked) {
            if (!this.selectedAppIds.includes(appId)) {
                this.selectedAppIds = [...this.selectedAppIds, appId];
            }
        } else {
            // Deselect this app and all newer apps following it in sorted order
            const sortedIds = this.filteredApps.map(a => a.id);
            const idx = sortedIds.indexOf(appId);
            const toDeselect = new Set(idx >= 0 ? sortedIds.slice(idx) : [appId]);
            this.selectedAppIds = this.selectedAppIds.filter(id => !toDeselect.has(id));
        }
    }

    handleToggleExpand(event) {
        const appId = event.currentTarget.dataset.id;
        const newSet = new Set(this.expandedAppIds);
        if (newSet.has(appId)) {
            newSet.delete(appId);
        } else {
            newSet.add(appId);
        }
        this.expandedAppIds = newSet;
        // force reactivity
        this.expandedAppIds = new Set(newSet);
    }

    handleClearAll() {
        this.selectedAppIds = [];
    }

    handleSummarySearchChange(event) {
        this.summarySearchTerm = event.target.value;
    }

    handleToggleSummary() {
        this.isSummaryExpanded = !this.isSummaryExpanded;
    }

    handleCreateRemittance() {
        this.dispatchEvent(new CustomEvent('createremittance', {
            detail: { applicationIds: [...this.selectedAppIds] }
        }));
    }
}