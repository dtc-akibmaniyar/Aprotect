import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadStyle } from 'lightning/platformResourceLoader';
import modalSizingCss from '@salesforce/resourceUrl/DealerConsoleModalSize';
import getSyncInventory from '@salesforce/apex/DealerPackageSyncController.getSyncInventory';
import createFromMaster from '@salesforce/apex/DealerPackageSyncController.createFromMaster';
import syncFromMaster from '@salesforce/apex/DealerPackageSyncController.syncFromMaster';
import getDealerAuthoring from '@salesforce/apex/DealerPackageSyncController.getDealerAuthoring';
import saveDealerTermPricing from '@salesforce/apex/DealerPackageSyncController.saveDealerTermPricing';
import saveDealerTermPremiumFee from '@salesforce/apex/DealerPackageSyncController.saveDealerTermPremiumFee';
import clearDealerPackagePremiumFees from '@salesforce/apex/DealerPackageSyncController.clearDealerPackagePremiumFees';
import applyDealerPackageTermDiscount from '@salesforce/apex/DealerPackageSyncController.applyDealerPackageTermDiscount';
import clearDealerPackageTermDiscounts from '@salesforce/apex/DealerPackageSyncController.clearDealerPackageTermDiscounts';
import saveDealerOptionPricing from '@salesforce/apex/DealerPackageSyncController.saveDealerOptionPricing';
import setDealerOptionRemoved from '@salesforce/apex/DealerPackageSyncController.setDealerOptionRemoved';
import saveDealerCommercialPrice from '@salesforce/apex/DealerPackageSyncController.saveDealerCommercialPrice';
import saveDealerPremiumSettings from '@salesforce/apex/DealerPackageSyncController.saveDealerPremiumSettings';
import setDealerPackageActive from '@salesforce/apex/DealerPackageSyncController.setDealerPackageActive';
import refreshDealerPriceAnchors from '@salesforce/apex/DealerPackageSyncController.refreshDealerPriceAnchors';
import setDealerPackagesActive from '@salesforce/apex/DealerPackageBulkActiveController.setDealerPackagesActive';
import getMasterPackageDetail from '@salesforce/apex/DealerPackageSyncController.getMasterPackageDetail';

/**
 * Dealer Package Sync console — rebuilt to the master-packages prototype layout.
 *
 * Information architecture:
 *   • On load the console opens on HOME — a service picker ("Select Services to
 *     Enable") listing the two A-Protect service lines. Each row carries a LIVE
 *     master-package count derived from the inventory the component already
 *     loads, plus fixed series copy.
 *   • Top-level tabs: Home · Extended Warranty · Tire & Rim Protection. A service
 *     tab (or clicking a service row on Home) opens the configuration workbench
 *     scoped to that service line — the active service comes from the top tab,
 *     never from an in-workbench filter chip.
 *   • The workbench keeps: the account header + count chips, the view-only lock
 *     alert, the Configuration / Dealer Portal Preview / Commissions sub-tabs,
 *     the two-pane master catalogue (fetch-only) | dealer packages accordion,
 *     and every confirm-gated save / keep-remove action.
 *   • Theme: DARK is the default. A Dark/Light switch in the component header
 *     toggles a class on the console root that drives the CSS custom properties.
 *
 * Binding rules honoured here:
 *   • The master pane is FETCH-ONLY — the component never offers an edit on a
 *     master row (no create/edit/delete of master records).
 *   • All authoring is dealer-level: keep/remove mirrored options, term
 *     discount / incentive / markup, option markup and the flat per-dealer
 *     commercial price.
 *   • The component is a dumb renderer: every status, chip, count and message
 *     for PACKAGES arrives as a ready label from the server. The one client-side
 *     derivation added here is the per-service master-package count shown on the
 *     Home service picker.
 */
const SERVICES = [
    { key: 'ew', name: 'Extended Warranty', series: 'Series V25, V27', seriesValue: 'V25, V27', icon: 'shield' },
    { key: 'tr', name: 'Tire & Rim Protection', series: 'Series V25', seriesValue: 'V25', icon: 'bullseye' }
];

/**
 * Static copy for the service-tab page header — the same paragraph on both
 * service lines (verbatim from the master-packages design).
 */
/**
 * Display order for the catalogue's package groups (the mock's order where it
 * maps): Powertrain → Essential → Premium Special → Luxury → Diamond /
 * Diamond Max → Commercial/Business → Tire & Rim → anything else (alphabetical).
 */
const GROUP_ORDER = ['powertrain', 'essential', 'premium', 'luxury', 'diamond', 'commercial', 'business', 'tire', 'rim'];

function groupRank(label) {
    const l = (label || '').toLowerCase();
    for (let i = 0; i < GROUP_ORDER.length; i++) {
        if (l.indexOf(GROUP_ORDER[i]) !== -1) return i + 1;
    }
    return GROUP_ORDER.length + 1;
}

const SERVICE_PAGE_SUBHEAD = 'A-Protect Warranty Corporation — dealer pricing console. '
    + 'Select the packages this dealership should carry, then copy them into the Dealer '
    + 'Package Plan below to set discounts and dealer pricing. The master library holds '
    + 'baseline pricing only — discounts, fees, and commissions are all set on the dealer\'s '
    + 'own copy, and only those dealer-level changes appear on the Dealer Portal Preview.';

export default class DealerPortalPackageSync extends LightningElement {
    @api recordId;

    viewState = 'loading';           // loading | ready | error | notDealer
    errorMessage = '';
    inventory = null;                // master catalogue + mirror status (read)
    authoring = null;                // dealer-side authoring model (read)
    busy = false;

    theme = 'dark';                  // dark (default) | light

    activeTopTab = 'home';           // home | ew | tr
    activeTab = 'config';            // config | preview | commissions
    expandedIds = [];                // dealer package ids with an open accordion

    // Grouped-tree state (Release → Group → Package), one set per pane.
    masterSelected = [];
    dealerSelected = [];
    masterCollapsedRefs = [];
    dealerCollapsedRefs = [];
    masterOpenGroups = [];
    dealerOpenGroups = [];
    masterOpenRows = [];

    // Master reference detail (tiers → terms → additional options), fetched
    // LAZILY on the first expand of a master package row and cached per package
    // for the session — never bulk-loaded into the inventory payload.
    masterDetailCache = {};
    masterDetailLoading = {};

    // Dealer-level premium vehicle fee settings (the dealer Account fields).
    // Staged locally like every other authoring value (null = not yet edited):
    // persisted together through the one confirm-gated write.
    premiumOverrideDraft = null;     // string as typed; '' cleared to null on save
    chargePremiumDraft = null;       // boolean once toggled

    // Bulk discount drafts, keyed by dealer package id. Defaults to {} so the
    // render getter never throws; a missing key renders as 0 (a no-op on apply).
    bulkDiscountDrafts = {};

    dialogOpen = false;
    dialogBusy = false;
    dialogTitle = '';
    dialogSummary = '';
    dialogNote = '';
    dialogConfirmLabel = '';
    pending = null;                  // { kind, params, message }

    // ---------------------------------------------------------------------
    // Lifecycle
    // ---------------------------------------------------------------------

    connectedCallback() {
        // The quick-action modal is sized by the platform and can't be reached
        // from inside the shadow root, so a small page-level stylesheet widens
        // it (scoped to this modal with :has()). Failure is cosmetic only.
        loadStyle(this, modalSizingCss).catch(() => {});
        this.loadAll();
    }

    /**
     * Tri-state checkboxes: `indeterminate` is not bindable from an LWC template
     * (and can't even be set as an attribute — the parser owns it), so the
     * markup tags each box with data-tri and we stamp .indeterminate here.
     */
    renderedCallback() {
        const boxes = this.template.querySelectorAll('input[type="checkbox"][data-tri]');
        for (let i = 0; i < boxes.length; i++) {
            boxes[i].indeterminate = boxes[i].dataset.tri === 'indeterminate';
        }
    }

    get viewLoading() { return this.viewState === 'loading'; }
    get viewError() { return this.viewState === 'error'; }
    get viewNotDealer() { return this.viewState === 'notDealer'; }
    get viewReady() { return this.viewState === 'ready'; }

    // ---------------------------------------------------------------------
    // Theme
    // ---------------------------------------------------------------------

    get rootClass() {
        return this.isDark ? 'console console_dark' : 'console console_light';
    }

    get isDark() { return this.theme !== 'light'; }
    get isLight() { return this.theme === 'light'; }

    get themeDarkClass() {
        return this.isDark ? 'theme-opt theme-opt_active' : 'theme-opt';
    }

    get themeLightClass() {
        return this.isLight ? 'theme-opt theme-opt_active' : 'theme-opt';
    }

    handleThemeDark() { this.theme = 'dark'; }
    handleThemeLight() { this.theme = 'light'; }

    // ---------------------------------------------------------------------
    // Top-level tabs (Home · Extended Warranty · Tire & Rim Protection)
    // ---------------------------------------------------------------------

    get topTabs() {
        const items = [{ value: 'home', label: 'Home' }].concat(
            SERVICES.map((s) => ({ value: s.key, label: s.name }))
        );
        return items.map((t) => ({
            value: t.value,
            label: t.label,
            cls: this.activeTopTab === t.value ? 'toptab toptab_active' : 'toptab',
            aria: this.activeTopTab === t.value ? 'true' : 'false'
        }));
    }

    handleTopTab(event) {
        const value = event.currentTarget.dataset.tab;
        if (!value) return;
        this.activeTopTab = value;
        this.activeTab = 'config';
    }

    get showHome() { return this.activeTopTab === 'home'; }
    get showService() { return this.activeTopTab !== 'home'; }

    get activeServiceName() {
        const found = SERVICES.filter((s) => s.key === this.activeTopTab)[0];
        return found ? found.name : '';
    }

    get activeService() {
        return SERVICES.filter((s) => s.key === this.activeTopTab)[0] || null;
    }

    get isShieldService() {
        const s = this.activeService;
        return !!s && s.icon === 'shield';
    }

    get isBullseyeService() {
        const s = this.activeService;
        return !!s && s.icon === 'bullseye';
    }

    /** Fixed series copy for the active service (the stat value, no "Series" prefix). */
    get activeServiceSeries() {
        const s = this.activeService;
        return s ? s.seriesValue : '';
    }

    /**
     * LIVE master-package count for the active service — the same client-side
     * grouping the Home picker rows use, so the two always agree.
     */
    get activeServiceCount() {
        const counts = this.serviceCounts;
        return counts[this.activeTopTab] || 0;
    }

    get servicePageSubhead() {
        return SERVICE_PAGE_SUBHEAD;
    }

    /** Breadcrumb "Services" link — back to the Home service picker. */
    handleBackToServices() {
        this.activeTopTab = 'home';
    }

    // ---------------------------------------------------------------------
    // Service classification + the Home picker (live counts)
    // ---------------------------------------------------------------------

    /**
     * The service line a package belongs to, from the server's own label
     * fields. planTypeLabel (the package group) is preferred; recordTypeLabel
     * is the fallback. Matching is case-insensitive and by "contains" so the
     * two canonical service lines are recognised whatever the org's exact
     * group / record-type wording is.
     */
    serviceKeyForRow(row) {
        if (!row) return null;
        const labels = [row.planTypeLabel, row.recordTypeLabel];
        for (let i = 0; i < labels.length; i++) {
            const label = (labels[i] || '').toLowerCase();
            if (!label) continue;
            if (label.indexOf('tire') !== -1 || label.indexOf('rim') !== -1) return 'tr';
            if (label.indexOf('warranty') !== -1) return 'ew';
        }
        return null;
    }

    matchesActiveService(row) {
        return this.serviceKeyForRow(row) === this.activeTopTab;
    }

    /** LIVE master-package count per service, from the loaded inventory. */
    get serviceCounts() {
        const counts = { ew: 0, tr: 0 };
        (this.masterEligibleRows || []).forEach((r) => {
            const key = this.serviceKeyForRow(r);
            if (key !== null) counts[key] += 1;
        });
        return counts;
    }

    /** The two fixed Home rows. Count is live; series copy is fixed. */
    get serviceRows() {
        const counts = this.serviceCounts;
        return SERVICES.map((s) => ({
            key: s.key,
            value: s.key,
            name: s.name,
            isShield: s.icon === 'shield',
            isBullseye: s.icon === 'bullseye',
            meta: counts[s.key] + ' master packages \u00B7 ' + s.series
        }));
    }

    get servicesCountLabel() {
        const n = this.serviceRows.length;
        return n + (n === 1 ? ' service' : ' services');
    }

    handleServiceRow(event) {
        this.openService(event.currentTarget.dataset.service);
    }

    handleServiceRowKey(event) {
        if (event.key === 'Enter' || event.key === ' ' || event.key === 'Spacebar') {
            event.preventDefault();
            this.openService(event.currentTarget.dataset.service);
        }
    }

    /** Carry the selected service into the configuration workbench. */
    openService(serviceKey) {
        if (!serviceKey) return;
        this.activeTopTab = serviceKey;
        this.activeTab = 'config';
    }

    // ---------------------------------------------------------------------
    // Sub-tabs
    // ---------------------------------------------------------------------

    get tabs() {
        const mk = (value, label) => ({
            value: value,
            label: label,
            cls: this.activeTab === value
                ? 'tab tab_active' : 'tab',
            aria: this.activeTab === value ? 'true' : 'false'
        });
        return [
            mk('config', 'Package Configuration'),
            mk('preview', 'Dealer Portal Preview'),
            mk('commissions', 'Commissions')
        ];
    }

    get showConfig() { return this.activeTab === 'config'; }
    get showPreview() { return this.activeTab === 'preview'; }
    get showCommissions() { return this.activeTab === 'commissions'; }

    handleTab(event) {
        const value = event.currentTarget.dataset.tab;
        if (value) this.activeTab = value;
    }

    // ---------------------------------------------------------------------
    // Entry context
    // ---------------------------------------------------------------------

    get accountName() {
        return this.inventory !== null ? this.inventory.accountName : '';
    }

    get flagOff() {
        return this.inventory !== null && this.inventory.syncEnabled === false;
    }

    get flagOffMessage() {
        if (this.inventory !== null && this.inventory.syncEnabledMessage) {
            return this.inventory.syncEnabledMessage;
        }
        return 'Package sync is switched off, so adding, syncing and editing are unavailable.';
    }

    // ---------------------------------------------------------------------
    // Dealer-level premium vehicle fee settings (dealer-wide, all packages)
    // ---------------------------------------------------------------------

    /** The staged override value (falls back to the persisted account value). */
    get premiumOverrideValue() {
        if (this.premiumOverrideDraft !== null) return this.premiumOverrideDraft;
        return this.inventory !== null ? this.numStr(this.inventory.premiumFeeOverrideAmount) : '';
    }

    /** The persisted override, server-formatted ("$250" / "Not set"). */
    get premiumOverrideDisplay() {
        const shown = this.inventory !== null && this.inventory.premiumFeeOverrideDisplay
            ? this.inventory.premiumFeeOverrideDisplay : '';
        return shown || 'Not set';
    }

    /** On unless the dealer account was explicitly switched off (default true). */
    get chargePremiumChecked() {
        if (this.chargePremiumDraft !== null) return this.chargePremiumDraft;
        return this.inventory !== null && this.inventory.chargePremiumVehicleFee === true;
    }

    get premiumDisabled() {
        return this.flagOff || this.busy;
    }

    /** Plain word for the switch state beside the toggle. */
    get chargePremiumStateLabel() {
        return this.chargePremiumChecked ? 'On' : 'Off';
    }

    /** "Current setting — …" — assembled from the server's own labels. */
    get premiumStateLine() {
        const inv = this.inventory;
        if (inv === null) return '';
        return 'Current setting \u2014 override: ' + this.premiumOverrideDisplay
            + ' \u00B7 premium vehicle fees: '
            + (inv.chargePremiumVehicleFee === true ? 'charged' : 'waived');
    }

    handlePremiumOverrideField(event) {
        this.premiumOverrideDraft = event.currentTarget.value;
    }

    handleChargePremiumToggle(event) {
        this.chargePremiumDraft = event.currentTarget.checked;
    }

    handleSavePremiumSettings() {
        if (this.flagOff) {
            this.toast(this.flagOffMessage, 'error');
            return;
        }
        const amount = this.parseNum(this.premiumOverrideValue);
        const charge = this.chargePremiumChecked;
        this.openConfirm({
            kind: 'premiumSettings',
            params: { accountId: this.recordId, overrideAmount: amount, chargePremiumFee: charge },
            title: 'Save the dealer premium vehicle fee settings?',
            summary: 'These settings apply to every package in this dealer\u2019s plan. '
                + (amount === null
                    ? 'The standard premium vehicle fees from the packages and terms will apply.'
                    : 'A premium vehicle fee override will apply for this dealer.')
                + (charge
                    ? ' Premium vehicle fees will be charged.'
                    : ' Premium vehicle fees will be waived for this dealer.'),
            note: 'These are dealer-level settings \u2014 a package synchronisation or a copy into the plan never changes them.',
            confirmLabel: 'Save dealer fee settings'
        });
    }

    get syncEnabledMessage() {
        return this.inventory !== null && this.inventory.syncEnabledMessage
            ? this.inventory.syncEnabledMessage
            : '';
    }

    // The three header chips are derived from the SAME eligible set the master
    // pane renders, so a hidden package is never counted in the console either.
    get updateCount() {
        return this.masterEligibleRows.filter((r) => r.status === 'UpdateAvailable').length;
    }

    get toAddCount() {
        return this.masterEligibleRows.filter((r) => r.status === 'AvailableToAdd').length;
    }

    get uptodateCount() {
        return this.masterEligibleRows.filter((r) => r.status === 'AlreadyAvailable').length;
    }

    // ---------------------------------------------------------------------
    // Left pane — the master catalogue (FETCH-ONLY), scoped to active service
    // ---------------------------------------------------------------------

    get masterRows() {
        // The FULL catalogue as the server sent it — deliberately unfiltered.
        // The dealer pane's staleness lookup (masterByMasterId) and the copy
        // flow's "already in the plan" detection need every master row,
        // including the ones the Master Packages pane hides.
        return this.inventory !== null && this.inventory.packages
            ? this.inventory.packages
            : [];
    }

    /**
     * Master-pane eligibility — ALL THREE must hold:
     *   1. the package's catalogue release is Published,
     *   2. its package group is Active,
     *   3. the package itself is Active.
     * (3) is already enforced server-side before a row reaches this payload, so
     * every row here is Active by construction. A null release or null group
     * fails (1)/(2) and the package is hidden — its release status cannot be
     * confirmed, so it is not offered.
     */
    isMasterEligible(row) {
        return !!row && row.releasePublished === true && row.planTypeActive === true;
    }

    /** Eligible master rows only — the master pane, counts and grouping. */
    get masterEligibleRows() {
        return this.masterRows.filter((r) => this.isMasterEligible(r));
    }

    /** Every eligible master package id (selection is scoped to these). */
    get masterEligibleIds() {
        return this.masterEligibleRows.map((r) => r.masterPackageId);
    }

    /** Master rows for the active service, in the server's shape (fetch-only). */
    get masterRaw() {
        return this.masterEligibleRows.filter((r) => this.showService && this.matchesActiveService(r));
    }

    /** Release → Group → Package tree for the master pane. */
    get masterTree() {
        const rows = this.masterRaw.map((r) => ({
            rowId: r.rowId,
            selId: r.masterPackageId,
            name: r.name,
            releaseName: r.releaseName || '',
            planTypeLabel: r.planTypeLabel,
            perClaimLimitLabel: r.perClaimLimitLabel,
            deductibleLabel: r.deductibleLabel,
            seriesLabel: r.releaseName || '',
            recordTypeLabel: r.recordTypeLabel,
            countsLabel: r.countsLabel,
            scheduleLabel: r.scheduleLabel,
            hasSchedule: !!r.scheduleLabel,
            lastSyncedLabel: r.lastSyncedLabel,
            hasLastSynced: !!r.lastSyncedLabel,
            statusLabel: r.statusLabel,
            chipClass: this.chipClass(r.statusTone),
            reason: r.reason,
            disabled: this.flagOff || this.busy,
            // A stale mirror can be refreshed through the existing sync path.
            hasSync: r.status === 'UpdateAvailable' && !!r.dealerPackageId,
            syncId: r.dealerPackageId,
            // Reference detail (lazy — fetched on first expand, cached per package).
            detailLoading: this.masterDetailLoading[r.masterPackageId] === true,
            hasDetail: !!this.masterDetailCache[r.masterPackageId],
            detailSeriesLabel: this.masterDetailSeriesLabel(r.masterPackageId),
            detailGroupName: this.masterDetailGroupName(r.masterPackageId),
            detailGroups: this.masterDetailGroups(r.masterPackageId),
            detailNote: this.masterDetailNote(r.masterPackageId)
        }));
        return this.buildTree(rows, 'master', this.masterSelected);
    }

    // ---------------------------------------------------------------------
    // Master reference detail — lazy read, cached per package for the session
    // ---------------------------------------------------------------------

    /** The lazy read is kicked off on the first expand; a second expand reuses the cache. */
    async ensureMasterDetail(masterPackageId) {
        if (!masterPackageId) return;
        if (this.masterDetailCache[masterPackageId] || this.masterDetailLoading[masterPackageId]) return;
        this.masterDetailLoading = Object.assign({}, this.masterDetailLoading, { [masterPackageId]: true });
        try {
            const dto = await getMasterPackageDetail({ masterPackageId: masterPackageId });
            this.masterDetailCache = Object.assign({}, this.masterDetailCache, { [masterPackageId]: dto });
        } catch (err) {
            this.toast(this.readError(err), 'error');
        } finally {
            const next = Object.assign({}, this.masterDetailLoading);
            delete next[masterPackageId];
            this.masterDetailLoading = next;
        }
    }

    _masterDetail(id) {
        return this.masterDetailCache[id] || null;
    }

    masterDetailSeriesLabel(id) {
        const dto = this._masterDetail(id);
        return dto && dto.seriesLabel ? dto.seriesLabel : '';
    }

    masterDetailGroupName(id) {
        const dto = this._masterDetail(id);
        return dto && dto.groupName ? dto.groupName : '';
    }

    /** "3 tiers · 12 terms · 15 add-ons" style line — server-counted, plain words. */
    masterDetailNote(id) {
        const dto = this._masterDetail(id);
        if (!dto) return '';
        const t = dto.termCount || 0;
        const o = dto.optionCount || 0;
        return t + (t === 1 ? ' term' : ' terms') + ' \u00B7 ' + o + (o === 1 ? ' additional option' : ' additional options');
    }

    /**
     * The reference table's tier blocks → rows. Each row is read-only; the
     * tier name rides the first row of its block ('' when the package has no
     * tiers), and an additional option is a muted, indented sub-row.
     */
    masterDetailGroups(id) {
        const dto = this._masterDetail(id);
        if (!dto || !dto.groups) return [];
        return dto.groups.map((g) => ({
            key: g.groupKey,
            tierName: g.tierName,
            rows: (g.rows || []).map((row, i) => ({
                rowId: row.rowId,
                isOption: row.kind === 'Option',
                levelLabel: row.kind === 'Option' ? 'Option' : 'Term',
                label: row.label,
                originalPrice: row.originalPrice,
                discount: row.discount,
                dealerPrice: row.dealerPrice,
                firstOfBlock: i === 0,
                tierCell: i === 0 && g.hasTier ? g.tierName : '',
                levelChipClass: row.kind === 'Option' ? 'lvl-chip lvl-chip_opt' : 'lvl-chip lvl-chip_term',
                labelClass: row.kind === 'Option' ? 'addon-label' : 'term-label',
                rowClass: (i === 0 ? 'trow trow_group-start' : 'trow') + (row.kind === 'Option' ? ' trow_addon' : '')
            }))
        }));
    }

    get masterPaneEmpty() {
        return this.masterTree.length === 0;
    }

    // ---------------------------------------------------------------------
    // Grouped tree — shared by BOTH panes (Release → Group → Package)
    // ---------------------------------------------------------------------

    get masterTotalCount() { return this.masterRaw.length; }
    get masterSelectedCount() {
        return this.masterRaw.filter((r) => this.masterSelected.indexOf(r.masterPackageId) !== -1).length;
    }
    get masterEnabledLabel() {
        return this.masterSelectedCount + ' of ' + this.masterTotalCount + ' enabled';
    }

    get dealerTotalCount() { return this.dealerRows.length; }
    get dealerSelectedCount() {
        return this.dealerRows.filter((r) => this.dealerSelected.indexOf(r.dealerPackageId) !== -1).length;
    }
    get dealerEnabledLabel() {
        return this.dealerSelectedCount + ' of ' + this.dealerTotalCount + ' enabled';
    }

    /** Saved-Active ids of every dealer package in the payload (all services). */
    dealerActiveIds(auth) {
        const ids = [];
        ((auth && auth.packages) || []).forEach((p) => {
            if (p.isActive === true && p.dealerPackageId) ids.push(p.dealerPackageId);
        });
        return ids;
    }

    /**
     * The DEALER pane's pending diff: one entry per visible row whose checkbox
     * no longer matches its saved Active state. This — not the absolute
     * selection — is what a save writes, so an untouched pane saves nothing.
     */
    get dealerPendingChanges() {
        const changes = [];
        this.dealerRows.forEach((row) => {
            const selected = this.dealerSelected.indexOf(row.dealerPackageId) !== -1;
            if (selected !== row.isActive) {
                changes.push({
                    dealerPackageId: row.dealerPackageId,
                    active: selected,
                    name: row.name
                });
            }
        });
        return changes;
    }

    get dealerPendingCount() {
        return this.dealerPendingChanges.length;
    }

    get dealerSaveDisabled() {
        return this.flagOff || this.busy || this.dealerPendingCount === 0;
    }

    get dealerSaveLabel() {
        const n = this.dealerPendingCount;
        return n > 0 ? 'Save changes (' + n + ')' : 'Save changes';
    }

    isSelected(list, id) {
        return id !== null && id !== undefined && list.indexOf(id) !== -1;
    }

    /** 'checked' | 'unchecked' | 'indeterminate' for a count of selected items. */
    triFor(selected, total) {
        if (total > 0 && selected === total) return 'checked';
        if (selected > 0 && selected < total) return 'indeterminate';
        return 'unchecked';
    }

    isRefCollapsed(pane, key) {
        const list = pane === 'master' ? this.masterCollapsedRefs : this.dealerCollapsedRefs;
        return list.indexOf(key) !== -1;
    }

    isGroupOpen(pane, key) {
        const list = pane === 'master' ? this.masterOpenGroups : this.dealerOpenGroups;
        return list.indexOf(key) !== -1;
    }

    isRowOpen(pane, rowId) {
        const list = pane === 'master' ? this.masterOpenRows : this.expandedIds;
        return list.indexOf(rowId) !== -1;
    }

    /**
     * Nest rows as Release → Group → Package. Releases sort by name (V25 before
     * V27); groups follow the mock's order; packages sort by name. Releases
     * start expanded, groups start collapsed.
     */
    buildTree(rows, pane, selectedIds) {
        if (!rows.length) return [];

        const byRelease = {};
        rows.forEach((r) => {
            const rel = r.releaseName || 'No catalogue release';
            if (!byRelease[rel]) byRelease[rel] = [];
            byRelease[rel].push(r);
        });

        const releaseNames = Object.keys(byRelease).sort((a, b) => a.localeCompare(b));

        return releaseNames.map((rel) => {
            const relKey = pane + '|R|' + rel;
            const relPkgs = byRelease[rel];
            const relSel = relPkgs.filter((p) => this.isSelected(selectedIds, p.selId)).length;
            const relTotal = relPkgs.length;
            const relOpen = !this.isRefCollapsed(pane, relKey);

            const byGroup = {};
            relPkgs.forEach((p) => {
                const g = p.planTypeLabel || 'Other';
                if (!byGroup[g]) byGroup[g] = [];
                byGroup[g].push(p);
            });
            const groupNames = Object.keys(byGroup).sort((a, b) => {
                const ra = groupRank(a);
                const rb = groupRank(b);
                return ra === rb ? a.localeCompare(b) : ra - rb;
            });

            const groups = groupNames.map((g) => {
                const grpKey = relKey + '|G|' + g;
                const grpPkgs = byGroup[g].slice().sort((a, b) => a.name.localeCompare(b.name));
                const grpSel = grpPkgs.filter((p) => this.isSelected(selectedIds, p.selId)).length;
                const grpTotal = grpPkgs.length;
                const grpOpen = this.isGroupOpen(pane, grpKey);
                return {
                    key: grpKey,
                    name: g,
                    upperName: g.toUpperCase(),
                    counterLabel: '(' + grpSel + ' of ' + grpTotal + ' selected)',
                    tri: this.triFor(grpSel, grpTotal),
                    checked: grpTotal > 0 && grpSel === grpTotal,
                    expanded: grpOpen,
                    chevronClass: grpOpen ? 'chev chev_open' : 'chev',
                    packages: grpPkgs.map((row) => {
                        const open = this.isRowOpen(pane, row.rowId);
                        const selected = this.isSelected(selectedIds, row.selId);
                        // The dealer pane rows carry one extra track (the Active /
                        // Inactive toggle); the master pane keeps the shared grid.
                        const rowBase = pane === 'dealer'
                            ? 'tree-row tree-row_wide' : 'tree-row';
                        return Object.assign({}, row, {
                            open: open,
                            selected: selected,
                            tri: selected ? 'checked' : 'unchecked',
                            rowClass: open ? rowBase + ' tree-row_open' : rowBase,
                            chevronClass: open ? 'chev chev_open' : 'chev'
                        });
                    })
                };
            });

            return {
                key: relKey,
                label: 'Master Package Series: ' + rel,
                counterLabel: '(' + relSel + ' of ' + relTotal + ' selected)',
                tri: this.triFor(relSel, relTotal),
                checked: relTotal > 0 && relSel === relTotal,
                expanded: relOpen,
                chevronClass: relOpen ? 'chev chev_open' : 'chev',
                groups: groups
            };
        });
    }

    // ---------------------------------------------------------------------
    // Tree interaction — expand / collapse + selection cascade
    // ---------------------------------------------------------------------

    toggleIn(listName, key) {
        const list = this[listName].slice();
        const i = list.indexOf(key);
        if (i === -1) list.push(key); else list.splice(i, 1);
        this[listName] = list;
    }

    setSelection(pane, ids, checked) {
        const list = (pane === 'master' ? this.masterSelected : this.dealerSelected).slice();
        ids.forEach((id) => {
            const i = list.indexOf(id);
            if (checked && i === -1) list.push(id);
            if (!checked && i !== -1) list.splice(i, 1);
        });
        if (pane === 'master') this.masterSelected = list;
        else this.dealerSelected = list;
    }

    /** Every package id currently rendered in a pane (both panes' trees). */
    idsInPane(pane) {
        const tree = pane === 'master' ? this.masterTree : this.dealerTree;
        const ids = [];
        (tree || []).forEach((ref) => {
            ref.groups.forEach((grp) => {
                grp.packages.forEach((p) => ids.push(p.selId));
            });
        });
        return ids;
    }

    /** Checkbox clicks must not also toggle the row / header they sit in. */
    handleCheckboxStop(event) {
        event.stopPropagation();
    }

    handlePkgSelect(event) {
        event.stopPropagation();
        const pane = event.currentTarget.dataset.pane;
        const id = event.currentTarget.dataset.id;
        this.setSelection(pane, [id], event.currentTarget.checked);
    }

    handleRefSelect(event) {
        event.stopPropagation();
        const pane = event.currentTarget.dataset.pane;
        const key = event.currentTarget.dataset.key;
        const tree = pane === 'master' ? this.masterTree : this.dealerTree;
        const ids = [];
        (tree || []).forEach((ref) => {
            if (ref.key !== key) return;
            ref.groups.forEach((grp) => grp.packages.forEach((p) => ids.push(p.selId)));
        });
        this.setSelection(pane, ids, event.currentTarget.checked);
    }

    handleGroupSelect(event) {
        event.stopPropagation();
        const pane = event.currentTarget.dataset.pane;
        const key = event.currentTarget.dataset.key;
        const tree = pane === 'master' ? this.masterTree : this.dealerTree;
        const ids = [];
        (tree || []).forEach((ref) => {
            ref.groups.forEach((grp) => {
                if (grp.key === key) grp.packages.forEach((p) => ids.push(p.selId));
            });
        });
        this.setSelection(pane, ids, event.currentTarget.checked);
    }

    handleRefToggle(event) {
        this.toggleIn(
            event.currentTarget.dataset.pane === 'master' ? 'masterCollapsedRefs' : 'dealerCollapsedRefs',
            event.currentTarget.dataset.key);
    }

    handleRefChevron(event) {
        event.stopPropagation();
        this.handleRefToggle(event);
    }

    handleGroupToggle(event) {
        this.toggleIn(
            event.currentTarget.dataset.pane === 'master' ? 'masterOpenGroups' : 'dealerOpenGroups',
            event.currentTarget.dataset.key);
    }

    handleGroupChevron(event) {
        event.stopPropagation();
        this.handleGroupToggle(event);
    }

    handleMasterPkgChevron(event) {
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        this.toggleIn('masterOpenRows', id);
        // Open first (the panel shows its loading state), then fetch on first expand.
        this.ensureMasterDetail(id);
    }

    handleDealerPkgChevron(event) {
        event.stopPropagation();
        this.toggleIn('expandedIds', event.currentTarget.dataset.id);
    }

    handleSelectAll(event) {
        const pane = event.currentTarget.dataset.pane;
        this.setSelection(pane, this.idsInPane(pane), true);
    }

    handleClearAll(event) {
        const pane = event.currentTarget.dataset.pane;
        this.setSelection(pane, this.idsInPane(pane), false);
    }

    handleSaveDealerSelection() {
        if (this.busy || this.flagOff) return;
        const changes = this.dealerPendingChanges;
        if (!changes.length) return;

        const activating = changes.filter((c) => c.active).length;
        const deactivating = changes.length - activating;
        const parts = [];
        if (activating > 0) parts.push(activating + ' will be marked Active');
        if (deactivating > 0) parts.push(deactivating + ' will be marked Inactive');

        this.openConfirm({
            kind: 'saveDealerSelection',
            params: {
                accountId: this.recordId,
                toggles: changes.map((c) => ({
                    dealerPackageId: c.dealerPackageId,
                    active: c.active
                }))
            },
            title: changes.length === 1
                ? 'Save 1 package change?'
                : 'Save ' + changes.length + ' package changes?',
            summary: 'Only the packages whose selection changed will be updated: ' + parts.join(', ') + '.',
            note: 'This is a soft state — the packages stay in the dealer\u2019s plan, keep their terms and add-ons, '
                + 'and keep syncing. Nothing is deleted and no pricing changes. A package with no dealer copy is left alone.',
            confirmLabel: 'Save changes'
        });
    }

    handleRefresh(event) {
        const pane = event.currentTarget.dataset.pane;
        if ((pane === 'master' || pane === 'preview') && !this.busy) this.loadAll();
    }

    // ---------------------------------------------------------------------
    // Right pane — the dealer's packages (authoring accordion), active service
    // ---------------------------------------------------------------------

    /** Master row by master package id — the staleness source for BOTH panes. */
    get masterByMasterId() {
        const map = {};
        this.masterRows.forEach((r) => {
            if (r.masterPackageId) map[r.masterPackageId] = r;
        });
        return map;
    }

    get dealerRows() {
        const pkgs = this.authoring !== null && this.authoring.packages
            ? this.authoring.packages
            : [];
        const masters = this.masterByMasterId;
        return pkgs
            .filter((p) => this.showService && this.matchesActiveService(p))
            .map((p) => {
                const open = this.expandedIds.indexOf(p.dealerPackageId) !== -1;
                // "Outdated" mirrors the master pane's Update available status.
                const m = p.masterPackageId ? masters[p.masterPackageId] : null;
                const stale = !!m && m.status === 'UpdateAvailable';
                return {
                    dealerPackageId: p.dealerPackageId,
                    selId: p.dealerPackageId,
                    masterPackageId: p.masterPackageId,
                    rowId: p.dealerPackageId,
                    name: p.name,
                    recordTypeLabel: p.recordTypeLabel,
                    planTypeLabel: p.planTypeLabel,
                    releaseName: p.releaseName || '',
                    seriesLabel: p.releaseName || '',
                    perClaimLimitLabel: p.perClaimLimitLabel,
                    deductibleLabel: p.deductibleLabel,
                    lastSyncedLabel: p.lastSyncedLabel,
                    // Active / Inactive soft state — the per-row toggle.
                    isActive: p.isActive === true,
                    activeLabel: p.isActive === true ? 'Active' : 'Inactive',
                    activeChipClass: p.isActive === true
                        ? 'state-chip state-chip_active' : 'state-chip state-chip_inactive',
                    toggleActiveLabel: p.isActive === true ? 'Deactivate' : 'Activate',
                    toggleActiveTitle: p.isActive === true
                        ? 'Deactivate this dealer package' : 'Activate this dealer package',
                    commercialPrice: this.numStr(p.commercialVehicleSurcharge),
                    commercialDisplay: this.money(p.commercialVehicleSurcharge),
                    // The master value this figure was seeded from — server-built label.
                    masterCommercialHint: p.masterCommercialLabel || 'Master: not set',
                    open: open,
                    chevron: open ? '\u25BE' : '\u25B8',
                    formOpen: !open,
                    hasBadge: stale,
                    badgeLabel: 'Outdated',
                    badgeClass: 'count-badge count-badge_attention',
                    hasSync: stale && !!p.dealerPackageId,
                    syncId: p.dealerPackageId,
                    disabled: this.flagOff || this.busy,
                    terms: (p.terms || []).map((t) => this.decorateTerm(t, p)),
                    termGroups: this.groupTermsByTier(
                        (p.terms || []).map((t) => this.decorateTerm(t, p)), p.tiers),
                    tiers: (p.tiers || []).map((tr) => ({ tierKey: tr.tierKey, tierName: tr.tierName })),
                    hasTiers: (p.tiers || []).length > 0,
                    hasTerms: (p.terms || []).length > 0,
                    includedOptions: (p.includedOptions || []).map((o) => this.decorateOption(o, p)),
                    hasIncluded: (p.includedOptions || []).length > 0,
                    termCount: (p.terms || []).length,
                    // The package-level bulk clear is offered only when at least one
                    // term currently carries a premium fee (and the row is editable).
                    feeRemoveDisabled: this.flagOff || this.busy
                        || !(p.terms || []).some((t) => this.hasPremiumFee(t)),
                    // Bulk Discount strip — one discount for every term of this package.
                    bulkDiscountDraft: this.bulkDiscountDraftFor(p.dealerPackageId),
                    bulkDiscountDisabled: this.flagOff || this.busy
                };
            });
    }

    /** Release → Group → Package tree for the dealer pane (same grouping). */
    get dealerTree() {
        return this.buildTree(this.dealerRows, 'dealer', this.dealerSelected);
    }

    decorateTerm(t, pkg) {
        const rowKey = pkg.dealerPackageId + '|' + t.dealerTermId;
        const feeOn = this.hasPremiumFee(t);
        const retailNum = this.parseNum(t.retailPrice);
        const feeNum = this.parseNum(t.premiumFee);
        // The combined figure shown when the fee is on: Retail Price + fee.
        const feeTotal = feeOn && retailNum !== null
            ? this.money(retailNum + (feeNum === null ? 0 : feeNum))
            : '';
        return {
            dealerTermId: t.dealerTermId,
            rowKey: rowKey,
            name: t.name,
            months: t.months,
            tierKey: t.tierKey || '',
            tierName: t.tierName || '',
            originalCost: this.money(t.originalCost),
            anchorFrozen: t.anchorFrozen,
            anchorNote: t.anchorFrozen
                ? 'Price locked to your own pricing'
                : 'Follows the master price',
            discountType: t.discountType || '%',
            discountValue: this.numStr(t.discountValue),
            markupType: t.markupType || '$',
            markupValue: this.numStr(t.markupValue),
            incentiveValue: this.numStr(t.salesRepIncentive),
            netCost: this.money(t.netCost),
            retailPrice: this.money(t.retailPrice),
            // Premium Fee — a separate per-term amount stored on Premium_Model_Fee__c
            // (fee is ON when the field holds a value, OFF when it is blank).
            premiumFee: feeOn ? this.numStr(t.premiumFee) : '',
            feeOn: feeOn,
            feeChipLabel: feeOn ? '\u2713 Premium Fee' : '+ Premium Fee',
            feeChipClass: feeOn ? 'fee-chip fee-chip_on' : 'fee-chip',
            feeAria: feeOn ? 'true' : 'false',
            feeTitle: feeOn
                ? 'Remove the premium vehicle fee from this term'
                : 'Apply the premium vehicle fee to this term',
            feeTotal: feeTotal,
            disabled: this.flagOff || this.busy,
            options: (t.options || []).map((o) => this.decorateOption(o, pkg, rowKey)),
            hasOptions: (t.options || []).length > 0
        };
    }

    /** A dealer term carries a premium fee when the stored amount is present. */
    hasPremiumFee(t) {
        return !!t && t.premiumFee !== null && t.premiumFee !== undefined;
    }

    /**
     * The amount the fee defaults to when it is switched back on: the term's own
     * stored amount first, else the master term's fee (the seed source), else 0.
     */
    premiumFeeDefault(t) {
        const stored = this.parseNum(t.premiumFee);
        if (stored !== null) return stored;
        const master = this.parseNum(t.masterPremiumFee);
        return master === null ? 0 : master;
    }

    decorateOption(o, pkg, parentKey) {
        const rowKey = (parentKey || pkg.dealerPackageId) + '|' + o.dealerOptionId;
        return {
            dealerOptionId: o.dealerOptionId,
            rowKey: rowKey,
            optionName: o.optionName,
            selectionType: o.selectionType,
            category: o.category,
            removed: o.isRemoved,
            keepLabel: o.isRemoved ? 'Removed' : 'Kept',
            keepCls: o.isRemoved ? 'opt-state opt-state_removed' : 'opt-state opt-state_kept',
            originalPrice: this.money(o.originalPrice),
            discountType: o.discountType || '%',
            discountValue: this.numStr(o.discountValue),
            markupType: o.markupType || '$',
            markupValue: this.numStr(o.markupValue),
            netCost: this.money(o.netCost),
            retailPrice: this.money(o.retailPrice),
            anchorFrozen: o.anchorFrozen,
            removedLabel: o.isRemoved ? 'Keep add-on' : 'Remove add-on',
            disabled: this.flagOff || this.busy
        };
    }

    /**
     * Group a package's decorated term rows under their coverage tier, in the
     * tier's own name order; tier-less terms fall into one un-grouped block at
     * the end. The FIRST term of a block carries the tier name / the "Term"
     * level cue — every term keeps its own controls and its own options.
     */
    groupTermsByTier(terms, tiers) {
        const order = [];
        const map = {};
        (tiers || []).forEach((t) => {
            const key = t.tierKey || t.tierName;
            if (!key || map[key]) return;
            map[key] = { key: key, tierName: t.tierName || '', hasTier: true, terms: [] };
            order.push(key);
        });
        const untiered = { key: 'no-tier', tierName: '', hasTier: false, terms: [] };

        (terms || []).forEach((t) => {
            const key = t.tierKey || '';
            if (key && map[key]) {
                map[key].terms.push(t);
            } else if (key) {
                map[key] = { key: key, tierName: t.tierName || '', hasTier: true, terms: [] };
                order.push(key);
                map[key].terms.push(t);
            } else {
                untiered.terms.push(t);
            }
        });

        const groups = order.map((k) => map[k]).filter((g) => g.terms.length > 0);
        if (untiered.terms.length) groups.push(untiered);

        groups.forEach((g) => {
            g.terms.forEach((t, i) => {
                t.firstOfGroup = i === 0;
                t.groupKey = g.key;
                t.tierCell = i === 0 && g.hasTier ? g.tierName : '';
                t.authRowClass = 'trow trow_auth' + (i === 0 ? ' trow_group-start' : '');
            });
            g.termCount = g.terms.length;
        });
        return groups;
    }

    get dealerRowsEmpty() {
        return this.dealerRows.length === 0;
    }

    // ---------------------------------------------------------------------
    // Copy Selected to Dealer Plan — the mock's flow arrow (confirm-gated)
    // ---------------------------------------------------------------------

    /**
     * The selected ids that are allowed to travel: any id the pane no longer
     * offers (hidden by the eligibility filter, or dropped from the catalogue)
     * is discarded here, so a stale selection can neither be counted nor copied.
     */
    get masterSelectedEligible() {
        const ids = this.masterEligibleIds;
        return this.masterSelected.filter((id) => ids.indexOf(id) !== -1);
    }

    get copyDisabled() {
        return this.flagOff || this.busy || this.masterSelectedEligible.length === 0;
    }

    get copyLabel() {
        const n = this.masterSelectedEligible.length;
        return n
            ? 'Copy Selected to Dealer Plan (' + n + ')'
            : 'Copy Selected to Dealer Plan';
    }

    handleCopyToDealer() {
        if (this.flagOff) {
            this.toast(this.flagOffMessage, 'error');
            return;
        }
        // Only eligible (visible) master packages may be copied — a selection
        // left over from before a package was hidden never reaches the server.
        const selected = this.masterSelectedEligible.slice();
        if (!selected.length) {
            this.toast(this.masterSelected.length
                ? 'The selected packages are no longer available in the master catalogue.'
                : 'Select at least one master package first.', 'info');
            return;
        }
        const masters = this.masterByMasterId;
        const already = {};
        this.dealerRows.forEach((p) => {
            if (p.masterPackageId) already[p.masterPackageId] = p;
        });
        const toCopy = [];
        let alreadyCount = 0;
        let staleCount = 0;
        selected.forEach((id) => {
            if (already[id]) {
                alreadyCount++;
                const m = masters[id];
                if (m && m.status === 'UpdateAvailable') staleCount++;
            } else {
                toCopy.push(id);
            }
        });

        if (!toCopy.length) {
            this.toast('Nothing to copy — every selected package is already in this dealer plan.', 'info');
            return;
        }

        const plural = (n) => (n === 1 ? '' : 's');
        const summary = ['Copying ' + toCopy.length + ' package' + plural(toCopy.length)
            + ' into this dealer\u2019s Dealer Package Plan.'];
        if (alreadyCount) {
            summary.push(alreadyCount + ' selected package' + plural(alreadyCount)
                + ' already ' + (alreadyCount === 1 ? 'is' : 'are') + ' in the plan and will not be duplicated.');
        }
        if (staleCount) {
            summary.push(staleCount + ' of those ' + (staleCount === 1 ? 'has' : 'have')
                + ' a master update available — open the row and use \u201CUpdate from master\u201D so the change is not missed.');
        }

        this.openConfirm({
            kind: 'copyBulk',
            params: { accountId: this.recordId, masterPackageIds: toCopy, dryRun: false },
            title: 'Copy ' + toCopy.length + ' package' + plural(toCopy.length) + ' to the Dealer Plan?',
            summary: summary.join(' '),
            note: 'Coverage tiers, terms and add-ons are created as dealer copies with your pricing '
                + 'left blank. Nothing is deleted, and packages the dealer already has are skipped.',
            confirmLabel: 'Copy to dealer plan'
        });
    }

    // ---------------------------------------------------------------------
    // Read-only tabs — Dealer Portal Preview and Commissions
    // ---------------------------------------------------------------------

    /**
     * Dealer Portal Preview — the dealer-facing view, grouped by package group
     * (the configuration tree's family rows) and rendered as the prototype's
     * four-column read-only table: Term/Option · List Price · Discount ·
     * Dealer Price.
     *
     * Column mapping (our schema → the preview's column):
     *   • LIST PRICE   = the term/option's ORIGINAL (list) price — the stored
     *                    Original_* anchor snapshot.
     *   • DISCOUNT     = the dealer's stored discount, in its own % or $ form
     *                    ('—' when none is set).
     *   • DEALER PRICE = the term/option's RETAIL price — the figure the dealer
     *                    is actually charged.  (Term retail includes any markup.)
     * Our schema prices in three steps (Original → discount → Net → markup →
     * Retail) while the mock shows two, so List Price − Discount only reads as
     * a straight subtraction when the dealer carries no markup.
     *
     * Only what the dealer sees is rendered: each term, then its KEPT (not
     * removed) options as indented sub-rows directly beneath it, then the
     * package's included add-ons.  Removed options are dropped entirely — no
     * "n removed" chip and no "Included: …" pill.
     */
    get previewGroups() {
        const rows = this.dealerRows;
        const byGroup = {};
        rows.forEach((p) => {
            const g = p.planTypeLabel || 'Other';
            if (!byGroup[g]) byGroup[g] = [];
            byGroup[g].push(p);
        });
        const names = Object.keys(byGroup).sort((a, b) => {
            const ra = groupRank(a);
            const rb = groupRank(b);
            return ra === rb ? a.localeCompare(b) : ra - rb;
        });
        return names.map((g) => ({
            key: 'pv|' + g,
            upperName: g.toUpperCase(),
            packages: byGroup[g]
                .slice()
                .sort((a, b) => a.name.localeCompare(b.name))
                .map((p) => {
                    const rowsForPkg = this.previewTableRows(p);
                    return {
                        dealerPackageId: p.dealerPackageId,
                        name: p.name,
                        // "{per claim} · {deductible} · Series {release}"
                        metaLine: [p.perClaimLimitLabel, p.deductibleLabel,
                            p.releaseName ? 'Series ' + p.releaseName : '']
                            .filter((s) => !!s).join(' \u00b7 '),
                        hasMeta: !!(p.perClaimLimitLabel || p.deductibleLabel || p.releaseName),
                        hasRows: rowsForPkg.length > 0,
                        rows: rowsForPkg
                    };
                })
        }));
    }

    /** The prototype's flat row list for one package: each term, then its kept
     *  options as indented sub-rows, then the package's included add-ons. */
    previewTableRows(p) {
        const rows = [];
        (p.terms || []).forEach((t) => {
            const feeNote = this.previewFeeNote(t);
            rows.push({
                rowKey: 'pv|T|' + t.rowKey,
                rowClass: 'preview-trow',
                labelClass: 'pv-term',
                isOption: false,
                label: t.name,
                listPrice: t.originalCost,
                discount: this.previewDiscount(t),
                dealerPrice: t.retailPrice,
                hasFeeNote: !!feeNote,
                feeNote: feeNote
            });
            (t.options || []).filter((o) => !o.removed).forEach((o) => {
                rows.push(this.previewOptionRow(o, false));
            });
        });
        (p.includedOptions || []).filter((o) => !o.removed).forEach((o) => {
            rows.push(this.previewOptionRow(o, true));
        });
        return rows;
    }

    /** One option sub-row. A package-level "included" add-on gets the mock's
     *  Included / — / $0.00 treatment; an optional add-on shows its prices. */
    previewOptionRow(o, included) {
        return {
            rowKey: 'pv|O|' + o.rowKey,
            rowClass: 'preview-trow preview-trow_opt',
            labelClass: 'pv-opt',
            isOption: true,
            label: o.optionName,
            listPrice: included ? 'Included' : o.originalPrice,
            discount: included ? '\u2014' : this.previewDiscount(o),
            dealerPrice: included ? '$0.00' : o.retailPrice,
            hasFeeNote: false,
            feeNote: ''
        };
    }

    /** The stored discount in its own % or $ form ('—' when none is set). */
    previewDiscount(row) {
        const raw = row.discountValue;
        if (raw === '' || raw === null || raw === undefined) return '\u2014';
        return row.discountType === '$' ? this.money(raw) : raw + '%';
    }

    /** The prototype's muted fee line — "+ $<fee> fee = $<total>", where total
     *  is the dealer price plus the fee.  The fee is a separate per-term amount
     *  (never part of the list price or the discount), and the line is drawn
     *  only where the term carries a POSITIVE fee, so a stored 0 (which the
     *  configuration tab's fee chip currently treats as "on") never prints a
     *  meaningless "+ $0.00 fee" line here. */
    previewFeeNote(t) {
        const fee = this.parseNum(t.premiumFee);
        const retail = this.parseNum(t.retailPrice);
        if (!t.feeOn || fee === null || fee <= 0 || retail === null) return '';
        return '+ ' + this.money(fee) + ' fee = ' + this.money(retail + fee);
    }

    get previewEmpty() { return this.previewGroups.length === 0; }

    get commissionRows() {
        return this.dealerRows.map((p) => {
            const terms = [];
            p.terms.forEach((t) => {
                terms.push({
                    rowKey: t.rowKey,
                    name: t.name,
                    retailPrice: t.retailPrice,
                    incentive: this.money(this.parseNum(t.incentiveValue)),
                    hasIncentive: t.incentiveValue !== '' && t.incentiveValue !== null
                });
            });
            return {
                dealerPackageId: p.dealerPackageId,
                name: p.name,
                planTypeLabel: p.planTypeLabel,
                terms: terms
            };
        });
    }

    get commissionEmpty() { return this.commissionRows.length === 0; }

    // ---------------------------------------------------------------------
    // Data loading
    // ---------------------------------------------------------------------

    async loadAll() {
        if (!this.recordId) {
            this.viewState = 'error';
            this.errorMessage = 'No record context. Open this action from an Account record page.';
            return;
        }
        this.viewState = 'loading';
        // A reload invalidates the per-package reference detail (it is re-fetched
        // lazily the next time a master row is expanded) and any staged
        // dealer-level premium fee edit (the saved values come back from the server).
        this.masterDetailCache = {};
        this.masterDetailLoading = {};
        this.premiumOverrideDraft = null;
        this.chargePremiumDraft = null;
        try {
            const inv = await getSyncInventory({ accountId: this.recordId });
            this.inventory = inv;
            // Drop any selection that is no longer eligible (e.g. its release
            // went back to Draft or its group was deactivated between loads).
            this.masterSelected = this.masterSelectedEligible;
            if (!inv.isDealerAccount) {
                this.viewState = 'notDealer';
                return;
            }
            const auth = await getDealerAuthoring({ accountId: this.recordId });
            this.authoring = auth;
            // Checkboxes show the SAVED Active state, so "pending" only ever means
            // "differs from what is stored". Seeding here (and after each save,
            // which reloads) keeps the counter truthful and makes save a no-op.
            this.dealerSelected = this.dealerActiveIds(auth);
            this.viewState = 'ready';
        } catch (err) {
            this.viewState = 'error';
            this.errorMessage = this.readError(err);
        }
    }

    /** Never surface a raw technical name in an error. */
    readError(err) {
        let msg = '';
        if (err && err.body && err.body.message) msg = err.body.message;
        else if (err && err.message) msg = err.message;
        if (!msg || msg.indexOf('__c') !== -1) {
            return 'Something went wrong. Please try again.';
        }
        return msg;
    }

    toast(title, variant, message) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message || '',
            variant: variant
        }));
    }

    closeAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    // ---------------------------------------------------------------------
    // Formatting helpers (presentation only)
    // ---------------------------------------------------------------------

    numStr(v) {
        return v === null || v === undefined ? '' : String(v);
    }

    parseNum(v) {
        if (v === null || v === undefined || v === '') return null;
        const n = Number(v);
        return Number.isNaN(n) ? null : n;
    }

    money(v) {
        if (v === null || v === undefined || v === '') return '—';
        const n = Number(v);
        if (Number.isNaN(n)) return '—';
        return '$' + n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }

    chipClass(tone) {
        if (tone === 'attention') return 'slds-badge count-badge count-badge_attention';
        if (tone === 'new') return 'slds-badge count-badge count-badge_new';
        return 'slds-badge count-badge count-badge_ok';
    }

    // ---------------------------------------------------------------------
    // Confirm dialog → single write dispatcher
    // ---------------------------------------------------------------------

    /**
     * Stale ("Outdated / Update available") row: refresh this dealer copy from
     * the master through the existing sync path — dry-run first, then confirm.
     */
    async handleSyncRow(event) {
        const id = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name || '';
        if (!id) return;
        this.busy = true;
        try {
            const dry = await syncFromMaster({ dealerPackageIds: [id], dryRun: true });
            if (!dry || !dry.success) {
                this.toast((dry && dry.message) || 'Could not prepare this action.', 'error');
                return;
            }
            const rowMsg = dry.results && dry.results.length ? dry.results[0].message : '';
            this.openConfirm({
                kind: 'sync',
                params: { dealerPackageIds: [id], dryRun: false },
                title: 'Update "' + name + '" from the master catalogue?',
                summary: rowMsg,
                note: 'Your dealer pricing (markup, discounts and incentives) is never changed, and nothing is deleted.',
                confirmLabel: 'Update now'
            });
        } catch (err) {
            this.toast(this.readError(err), 'error');
        } finally {
            this.busy = false;
        }
    }

    // ---- Term / option edits -------------------------------------------------

    valueOf(target) {
        if (target.type === 'checkbox') return target.checked;
        return target.value;
    }

    handleTermField(event) {
        const termId = event.currentTarget.dataset.termid;
        const field = event.currentTarget.dataset.field;
        const value = this.valueOf(event.currentTarget);
        const rows = this.authoring.packages;
        rows.forEach((p) => {
            (p.terms || []).forEach((t) => {
                if (t.dealerTermId !== termId) return;
                if (field === 'discountValue') t.discountValue = this.parseNum(value);
                else if (field === 'discountType') t.discountType = value;
                else if (field === 'markupType') t.markupType = value;
                else if (field === 'markupValue') t.markupValue = this.parseNum(value);
                else if (field === 'incentive') t.salesRepIncentive = this.parseNum(value);
            });
        });
        this.refreshDealerView();
    }

    /**
     * Premium Fee chip. Staged locally like every other term authoring value and
     * persisted by the term's Save: ON = store the amount on Premium_Model_Fee__c,
     * OFF = blank it. The fee is not part of the Retail Price formula, so toggling
     * it never moves the dealer price.
     */
    handleTogglePremiumFee(event) {
        event.stopPropagation();
        const termId = event.currentTarget.dataset.termid;
        const found = this.findTerm(termId);
        if (!found) return;
        const term = found.term;
        term.premiumFee = this.hasPremiumFee(term) ? null : this.premiumFeeDefault(term);
        this.refreshDealerView();
    }

    /** The inline premium-fee amount input — staged, saved with the term. */
    handlePremiumFeeAmount(event) {
        const termId = event.currentTarget.dataset.termid;
        const found = this.findTerm(termId);
        if (!found) return;
        const raw = event.currentTarget.value;
        found.term.premiumFee = raw === '' ? null : this.parseNum(raw);
        this.refreshDealerView();
    }

    handleOptionField(event) {
        const optionId = event.currentTarget.dataset.optionid;
        const field = event.currentTarget.dataset.field;
        const value = this.valueOf(event.currentTarget);
        const rows = this.authoring.packages;
        rows.forEach((p) => {
            (p.includedOptions || []).forEach((o) => {
                if (o.dealerOptionId !== optionId) return;
                this.applyOptionField(o, field, value);
            });
            (p.terms || []).forEach((t) => {
                (t.options || []).forEach((o) => {
                    if (o.dealerOptionId !== optionId) return;
                    this.applyOptionField(o, field, value);
                });
            });
        });
        this.refreshDealerView();
    }

    applyOptionField(o, field, value) {
        if (field === 'discountValue') o.discountValue = this.parseNum(value);
        else if (field === 'discountType') o.discountType = value;
        else if (field === 'markupType') o.markupType = value;
        else if (field === 'markupValue') o.markupValue = this.parseNum(value);
    }

    /** Force reactive re-render of the derived view models. */
    refreshDealerView() {
        this.authoring = Object.assign({}, this.authoring);
    }

    // ---- Save actions (each confirm-gated) ----------------------------------

    handleSaveTerm(event) {
        const termId = event.currentTarget.dataset.termid;
        const found = this.findTerm(termId);
        if (!found) return;
        const feeOn = this.hasPremiumFee(found.term);
        this.openConfirm({
            kind: 'saveTerm',
            params: {
                dealerTermId: termId,
                // Default the type when it is blank: the dropdown already shows
                // a default ('%' / '$'), but the underlying value can be null.
                // Sending a value with a blank type makes the Net/Retail formulas
                // ignore the amount — so mirror the displayed default on save.
                discountType: found.term.discountType || '%',
                discountValue: this.parseNum(found.term.discountValue),
                markupType: found.term.markupType || '$',
                markupValue: this.parseNum(found.term.markupValue),
                salesRepIncentive: this.parseNum(found.term.salesRepIncentive),
                // null = no premium fee (the stored field is blanked).
                premiumFee: feeOn ? this.parseNum(found.term.premiumFee) : null
            },
            title: 'Save pricing for "' + found.term.name + '"?',
            summary: feeOn
                ? 'Discount, sales-rep incentive, markup and the premium vehicle fee will be saved on this dealer term.'
                : 'Discount, sales-rep incentive and markup will be saved on this dealer term.',
            note: 'Your stored wholesale price is frozen once you set your own pricing — a later master price change will not move it.',
            confirmLabel: 'Save pricing'
        });
    }

    /**
     * One Save → two additive writes: the existing term pricing, plus the premium
     * fee. Returns a failure if either write failed.
     */
    async saveTermAndFee(params) {
        const pricing = saveDealerTermPricing({
            dealerTermId: params.dealerTermId,
            discountType: params.discountType,
            discountValue: params.discountValue,
            markupType: params.markupType,
            markupValue: params.markupValue,
            salesRepIncentive: params.salesRepIncentive
        });
        const fee = saveDealerTermPremiumFee({
            dealerTermId: params.dealerTermId,
            amount: params.premiumFee
        });
        const results = await Promise.all([pricing, fee]);
        const failed = results.filter((r) => !r || !r.success);
        if (failed.length) {
            return { success: false, message: (failed[0] && failed[0].message) || 'The action did not complete.' };
        }
        return results[0];
    }

    /** Package-level bulk clear of the premium fee — confirm-gated like every write. */
    handleRemovePackageFees(event) {
        const pkgId = event.currentTarget.dataset.pkgid;
        if (!pkgId) return;
        this.openConfirm({
            kind: 'removePremiumFees',
            params: { dealerPackageId: pkgId },
            title: 'Remove the Premium Fee from this package?',
            summary: 'The premium vehicle fee will be turned off for every term in this dealer package.',
            note: 'Your dealer prices are not changed — the premium fee sits on top of the dealer price.',
            confirmLabel: 'Remove from package'
        });
    }

    /**
     * The staged bulk-discount draft for one dealer package.
     *
     * Defensive by design: a package that has never been edited has no key in
     * `bulkDiscountDrafts` yet, and the render model must NEVER throw for one.
     * A missing (or null/undefined) key renders as 0 — a no-op when applied —
     * so the Bulk Discount strip is always safe to render, on every service tab.
     */
    bulkDiscountDraftFor(dealerPackageId) {
        if (!dealerPackageId) return 0;
        const drafts = this.bulkDiscountDrafts || {};
        if (!Object.prototype.hasOwnProperty.call(drafts, dealerPackageId)) return 0;
        const raw = drafts[dealerPackageId];
        return raw === null || raw === undefined ? 0 : raw;
    }

    /** Bulk Discount input — staged locally; the strip's Apply reads this draft. */
    handleBulkDiscountField(event) {
        const pkgId = event.currentTarget.dataset.pkgid;
        if (!pkgId) return;
        const value = event.currentTarget.value;
        this.bulkDiscountDrafts = Object.assign({}, this.bulkDiscountDrafts, {
            [pkgId]: value
        });
        this.refreshDealerView();
    }

    /**
     * Bulk Discount — one fixed '%' discount for EVERY term of this package.
     * A blank or zero input is a no-op (informational toast, no confirm, no write).
     * Confirm-gated like every other authoring write.
     */
    handleApplyBulkDiscount(event) {
        const pkgId = event.currentTarget.dataset.pkgid;
        if (!pkgId) return;
        const value = this.parseNum(this.bulkDiscountDrafts[pkgId]);
        if (value === null || value === 0) {
            this.toast('Enter a discount above zero to apply to every term.', 'info');
            return;
        }
        if (this.flagOff) {
            this.toast(this.flagOffMessage, 'error');
            return;
        }
        this.openConfirm({
            kind: 'bulkDiscount',
            params: { dealerPackageId: pkgId, discountType: '%', discountValue: value },
            title: 'Apply a bulk discount to every term?',
            summary: 'A ' + value + '% discount will be set on every term in this dealer package.',
            note: 'Your stored wholesale price is frozen once you set your own pricing \u2014 "Price locked to your own pricing" will apply to every term touched by this discount.',
            confirmLabel: 'Apply to all terms'
        });
    }

    /** Clear Discount — remove the discount from every term that currently carries one. */
    handleClearBulkDiscount(event) {
        const pkgId = event.currentTarget.dataset.pkgid;
        if (!pkgId) return;
        if (this.flagOff) {
            this.toast(this.flagOffMessage, 'error');
            return;
        }
        this.openConfirm({
            kind: 'clearBulkDiscount',
            params: { dealerPackageId: pkgId },
            title: 'Clear the discount on every term?',
            summary: 'The discount will be removed from every term in this dealer package that currently carries one.',
            note: 'Markup, sales-rep incentive and the premium fee are not changed.',
            confirmLabel: 'Clear discount'
        });
    }

    handleSaveOption(event) {
        const optId = event.currentTarget.dataset.optionid;
        const found = this.findOption(optId);
        if (!found) return;
        this.openConfirm({
            kind: 'saveOption',
            params: {
                dealerOptionId: optId,
                // Same type default as the term save: a value with a blank type
                // would be ignored by the option Net/Retail formulas.
                discountType: found.option.discountType || '%',
                discountValue: this.parseNum(found.option.discountValue),
                markupType: found.option.markupType || '$',
                markupValue: this.parseNum(found.option.markupValue)
            },
            title: 'Save pricing for "' + found.option.optionName + '"?',
            summary: 'Discount and markup will be saved on this dealer add-on.',
            note: 'Your stored option price is frozen once you set your own pricing.',
            confirmLabel: 'Save add-on price'
        });
    }

    handleToggleRemoved(event) {
        const optId = event.currentTarget.dataset.optionid;
        const found = this.findOption(optId);
        if (!found) return;
        const next = !found.option.isRemoved;
        this.openConfirm({
            kind: 'removeOption',
            params: { dealerOptionId: optId, removed: next },
            title: (next ? 'Remove "' : 'Keep "') + found.option.optionName + '"' + (next ? '"?' : '"?'),
            summary: next
                ? 'The add-on is removed from this dealer package and will not come back on the next synchronisation.'
                : 'The add-on is kept on this dealer package again.',
            note: 'You can only keep or remove add-ons that come from the master catalogue — new content is not created here.',
            confirmLabel: next ? 'Remove add-on' : 'Keep add-on'
        });
    }

    handleCommercialField(event) {
        const pkgId = event.currentTarget.dataset.pkgid;
        const value = this.parseNum(event.currentTarget.value);
        (this.authoring.packages || []).forEach((p) => {
            if (p.dealerPackageId === pkgId) p.commercialVehicleSurcharge = value;
        });
        this.refreshDealerView();
    }

    handleSaveCommercial(event) {
        const pkgId = event.currentTarget.dataset.pkgid;
        let amount = null;
        (this.authoring.packages || []).forEach((p) => {
            if (p.dealerPackageId === pkgId) amount = p.commercialVehicleSurcharge;
        });
        this.openConfirm({
            kind: 'commercial',
            params: { dealerPackageId: pkgId, amount: amount },
            title: 'Save the dealer commercial price?',
            summary: 'The flat per-dealer commercial figure will be saved on this dealer package.',
            note: 'This figure is dealer-owned — it is never refreshed from the master catalogue.',
            confirmLabel: 'Save price'
        });
    }

    /**
     * Active / Inactive toggle for ONE dealer package. A soft state only — the
     * row stays in the plan and keeps syncing. Confirm-gated like every write.
     */
    handleToggleActive(event) {
        event.stopPropagation();
        const pkgId = event.currentTarget.dataset.pkgid;
        if (!pkgId) return;
        let pkg = null;
        (this.authoring.packages || []).forEach((p) => {
            if (p.dealerPackageId === pkgId) pkg = p;
        });
        if (!pkg) return;
        const next = pkg.isActive !== true;   // toggle the stored state
        this.openConfirm({
            kind: 'toggleActive',
            params: { dealerPackageId: pkgId, active: next },
            title: (next ? 'Activate ' : 'Deactivate ') + '\u201C' + (pkg.name || 'this package') + '\u201D?',
            summary: next
                ? 'This dealer package will show as Active again on this console.'
                : 'This dealer package will show as Inactive on this console. It stays in the dealer plan and keeps syncing exactly as before.',
            note: 'Changing the Active state does not remove the package, its terms or add-ons, and never changes your dealer pricing. Nothing is deleted.',
            confirmLabel: next ? 'Activate package' : 'Deactivate package'
        });
    }

    handleRefreshAnchors(event) {
        const pkgId = event.currentTarget.dataset.pkgid;
        this.openConfirm({
            kind: 'refreshAnchors',
            params: { dealerPackageIds: [pkgId] },
            title: 'Refresh dealer prices from the master?',
            summary: 'The stored wholesale prices for this package will be re-seeded from the master catalogue.',
            note: 'Your discount, markup and incentives are kept — only the stored master price anchor moves.',
            confirmLabel: 'Refresh prices'
        });
    }

    findTerm(termId) {
        let hit = null;
        this.authoring.packages.forEach((p) => {
            (p.terms || []).forEach((t) => { if (t.dealerTermId === termId) hit = { pkg: p, term: t }; });
        });
        return hit;
    }

    findOption(optionId) {
        let hit = null;
        this.authoring.packages.forEach((p) => {
            (p.includedOptions || []).forEach((o) => {
                if (o.dealerOptionId === optionId) hit = { pkg: p, option: o };
            });
            (p.terms || []).forEach((t) => {
                (t.options || []).forEach((o) => {
                    if (o.dealerOptionId === optionId) hit = { pkg: p, option: o };
                });
            });
        });
        return hit;
    }

    // ---------------------------------------------------------------------
    // Dialog plumbing
    // ---------------------------------------------------------------------

    openConfirm(cfg) {
        this.pending = {
            kind: cfg.kind,
            params: cfg.params || {},
            refreshMaster: cfg.refreshMaster === true
        };
        this.dialogTitle = cfg.title;
        this.dialogSummary = cfg.summary;
        this.dialogNote = cfg.note || '';
        this.dialogConfirmLabel = cfg.confirmLabel || 'Confirm';
        this.dialogOpen = true;
    }

    dialogCancel() {
        this.dialogOpen = false;
        this.pending = null;
    }

    async dialogConfirm() {
        const action = this.pending;
        if (!action) return;
        this.dialogBusy = true;
        try {
            const result = await this.runAction(action);
            this.dialogOpen = false;
            this.pending = null;
            if (action.kind === 'saveDealerSelection') {
                // Always reload: checkboxes must show saved truth even on a
                // partial result, and that reload clears the pending diff.
                await this.loadAll();
                this.dealerSelectionToast(result);
                return;
            }
            if (result && result.success) {
                this.toast(result.message || 'Done.', 'success');
                await this.loadAll();
            } else {
                this.toast((result && result.message) || 'The action did not complete.', 'error');
            }
        } catch (err) {
            this.dialogOpen = false;
            this.pending = null;
            this.toast(this.readError(err), 'error');
        } finally {
            this.dialogBusy = false;
        }
    }

    dealerSelectionToast(result) {
        if (!result) {
            this.toast('The changes could not be saved.', 'error');
            return;
        }
        if (result.success) {
            this.toast(result.message || 'Saved.', 'success');
            return;
        }
        const failed = (result.results || []).filter((r) => r && r.success === false);
        const detail = failed
            .slice(0, 3)
            .map((r) => (r.name ? r.name + ' — ' : '') + r.message)
            .join(' ');
        this.toast(result.message || 'Some changes were not saved.', 'warning', detail);
    }

    runAction(action) {
        switch (action.kind) {
            case 'copyBulk':
            case 'add':
                return createFromMaster(action.params);
            case 'sync':
                return syncFromMaster(action.params);
            case 'saveTerm':
                return this.saveTermAndFee(action.params);
            case 'removePremiumFees':
                return clearDealerPackagePremiumFees(action.params);
            case 'saveOption':
                return saveDealerOptionPricing(action.params);
            case 'removeOption':
                return setDealerOptionRemoved(action.params);
            case 'commercial':
                return saveDealerCommercialPrice(action.params);
            case 'premiumSettings':
                return saveDealerPremiumSettings(action.params);
            case 'refreshAnchors':
                return refreshDealerPriceAnchors(action.params);
            case 'toggleActive':
                return setDealerPackageActive(action.params);
            case 'saveDealerSelection':
                return setDealerPackagesActive(action.params);
            case 'bulkDiscount':
                return applyDealerPackageTermDiscount(action.params);
            case 'clearBulkDiscount':
                return clearDealerPackageTermDiscounts(action.params);
            default:
                return Promise.resolve({ success: false, message: 'Unknown action.' });
        }
    }
}