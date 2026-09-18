import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSyncInventory from '@salesforce/apex/DealerPackageSyncController.getSyncInventory';
import createFromMaster from '@salesforce/apex/DealerPackageSyncController.createFromMaster';
import syncFromMaster from '@salesforce/apex/DealerPackageSyncController.syncFromMaster';

/**
 * Dealer Package Sync console (P7-e).
 *
 * ONE unified list: every eligible master package as a single row carrying its
 * state for this dealer —
 *   • "Available to add"  → primary action Add to dealer
 *   • "Already available" → no action
 *   • "Update available"  → primary action Sync now
 *
 * The component is a dumb renderer: every status, chip, count and message
 * string is computed server-side (DealerPackageSyncController) and arrives as a
 * ready label on the DTO. It never maps a technical name, never does date math,
 * and never writes on its own — all writes go through the controller behind a
 * confirmation dialog fed by the server dry-run summary. After every action the
 * inventory is re-fetched (the server is the truth).
 */
export default class DealerPortalPackageSync extends LightningElement {
    @api recordId;

    viewState = 'loading';           // loading | ready | error | notDealer
    inventory = null;
    errorMessage = '';
    busyRowId = null;
    filter = 'all';                  // all | add | update | uptodate

    dialogOpen = false;
    dialogBusy = false;
    dialogTitle = '';
    dialogSummary = '';
    dialogNote = '';
    dialogConfirmLabel = '';
    pendingAction = null;            // { kind: 'add'|'sync', id }

    // ---------------------------------------------------------------------
    // Lifecycle
    // ---------------------------------------------------------------------

    connectedCallback() {
        this.loadInventory();
    }

    // ---------------------------------------------------------------------
    // View-state getters
    // ---------------------------------------------------------------------

    get viewLoading() { return this.viewState === 'loading'; }
    get viewError() { return this.viewState === 'error'; }
    get viewNotDealer() { return this.viewState === 'notDealer'; }
    get viewReady() { return this.viewState === 'ready'; }

    get flagOff() {
        return this.inventory !== null && this.inventory.syncEnabled === false;
    }

    get flagOffMessage() {
        return this.inventory !== null && this.inventory.syncEnabledMessage
            ? this.inventory.syncEnabledMessage
            : 'Package sync is switched off, so adding and syncing are unavailable.';
    }

    get accountName() {
        return this.inventory !== null ? this.inventory.accountName : '';
    }

    get syncEnabledMessage() {
        return this.inventory !== null && this.inventory.syncEnabledMessage
            ? this.inventory.syncEnabledMessage
            : '';
    }

    get updateCount() {
        return this.inventory !== null ? this.inventory.updateAvailableCount : 0;
    }

    get toAddCount() {
        return this.inventory !== null ? this.inventory.availableToAddCount : 0;
    }

    get uptodateCount() {
        return this.inventory !== null ? this.inventory.alreadyAvailableCount : 0;
    }

    // ---------------------------------------------------------------------
    // Data shaping (presentation only — no eligibility logic lives here)
    // ---------------------------------------------------------------------

    get allRows() {
        return this.inventory !== null && this.inventory.packages
            ? this.inventory.packages
            : [];
    }

    get filterButtons() {
        return [
            this.mkFilter('all', 'All packages', this.allRows.length),
            this.mkFilter('add', 'To add', this.toAddCount),
            this.mkFilter('update', 'Updates', this.updateCount),
            this.mkFilter('uptodate', 'Up to date', this.uptodateCount)
        ];
    }

    get visibleRows() {
        return this.allRows
            .filter((r) => this.matchesFilter(r))
            .map((r) => this.decorate(r));
    }

    get noRows() {
        return this.visibleRows.length === 0;
    }

    get emptyMessage() {
        if (this.allRows.length === 0) {
            return 'No catalogue packages are available yet.';
        }
        return 'No packages match this filter.';
    }

    get hasFooterRows() {
        return this.footerRows.length > 0;
    }

    /** Inactive-master and master-less copies — informational only. */
    get footerRows() {
        if (this.inventory === null || !this.inventory.mirrored) return [];
        return this.inventory.mirrored
            .filter((r) => r.status === 'InactiveMaster' || r.status === 'Orphaned')
            .map((r) => ({
                dealerPackageId: r.dealerPackageId,
                name: r.name,
                statusLabel: r.statusLabel,
                reason: r.reason
            }));
    }

    mkFilter(value, label, count) {
        const active = this.filter === value;
        return {
            value: value,
            text: label + ' (' + count + ')',
            cls: active
                ? 'slds-button slds-button_brand filter-btn'
                : 'slds-button slds-button_neutral filter-btn',
            aria: active ? 'true' : 'false'
        };
    }

    matchesFilter(row) {
        if (this.filter === 'add') return row.status === 'AvailableToAdd';
        if (this.filter === 'update') return row.status === 'UpdateAvailable';
        if (this.filter === 'uptodate') return row.status === 'AlreadyAvailable';
        return true;
    }

    decorate(row) {
        const isSync = row.primaryAction === 'sync';
        const isAdd = row.primaryAction === 'add';
        return Object.assign({}, row, {
            busy: this.busyRowId === row.rowId || this.flagOff,
            hasAction: isSync || isAdd,
            primaryAction: row.primaryAction,
            actionId: isSync ? row.dealerPackageId : row.masterPackageId,
            chipClass: this.chipClass(row.statusTone),
            rowClass: row.status === 'UpdateAvailable'
                ? 'pkg-row pkg-row_attention'
                : 'pkg-row',
            hasPlanType: !!(row.planTypeLabel),
            hasRelease: !!(row.releaseLabel),
            hasSchedule: !!(row.scheduleLabel),
            hasLastSynced: !!(row.lastSyncedLabel)
        });
    }

    chipClass(tone) {
        if (tone === 'attention') return 'slds-badge slds-theme_warning';
        if (tone === 'new') return 'slds-badge slds-theme_info';
        return 'slds-badge slds-badge_lightest';
    }

    handleFilter(event) {
        const value = event.currentTarget.dataset.value;
        if (value) this.filter = value;
    }

    // ---------------------------------------------------------------------
    // Data
    // ---------------------------------------------------------------------

    async loadInventory() {
        if (!this.recordId) {
            this.viewState = 'error';
            this.errorMessage = 'No record context. Open this action from an Account record page.';
            return;
        }
        this.viewState = 'loading';
        try {
            const dto = await getSyncInventory({ accountId: this.recordId });
            this.inventory = dto;
            this.viewState = dto.isDealerAccount ? 'ready' : 'notDealer';
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

    toast(title, variant) {
        this.dispatchEvent(new ShowToastEvent({ title: title, message: '', variant: variant }));
    }

    closeAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    // ---------------------------------------------------------------------
    // Row action → dry-run → shared confirm dialog → real run → refetch
    // ---------------------------------------------------------------------

    handleRowAction(event) {
        const id = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name || '';
        const kind = event.currentTarget.dataset.kind;
        if (!id || (kind !== 'add' && kind !== 'sync')) return;
        this.busyRowId = event.currentTarget.dataset.rowid || id;
        this.openConfirm(kind, id, name);
    }

    async openConfirm(kind, id, name) {
        this.dialogBusy = true;
        try {
            const dry = kind === 'sync'
                ? await syncFromMaster({ dealerPackageIds: [id], dryRun: true })
                : await createFromMaster({
                    accountId: this.recordId, masterPackageIds: [id], dryRun: true });
            if (!dry || !dry.success) {
                this.toast((dry && dry.message) || 'Could not prepare this action.', 'error');
                return;
            }
            const rowMsg = dry.results && dry.results.length ? dry.results[0].message : '';
            this.dialogTitle = kind === 'sync'
                ? 'Sync "' + name + '" from the master catalogue?'
                : 'Add "' + name + '" to this dealer?';
            this.dialogSummary = rowMsg;
            this.dialogNote = kind === 'sync'
                ? 'Your dealer pricing (markup, discounts and incentives) is never changed, and nothing is deleted.'
                : 'Coverage tiers, terms and add-ons are created automatically, with your pricing left blank.';
            this.dialogConfirmLabel = kind === 'sync' ? 'Sync now' : 'Add to dealer';
            this.pendingAction = { kind: kind, id: id };
            this.dialogOpen = true;
        } catch (err) {
            this.toast(this.readError(err), 'error');
        } finally {
            this.dialogBusy = false;
            this.busyRowId = null;
        }
    }

    dialogCancel() {
        this.dialogOpen = false;
        this.pendingAction = null;
    }

    async dialogConfirm() {
        const action = this.pendingAction;
        if (!action) return;
        this.dialogBusy = true;
        try {
            const result = action.kind === 'sync'
                ? await syncFromMaster({ dealerPackageIds: [action.id], dryRun: false })
                : await createFromMaster({
                    accountId: this.recordId, masterPackageIds: [action.id], dryRun: false });
            this.dialogOpen = false;
            this.pendingAction = null;
            if (result && result.success) {
                this.toast(result.message || 'Done.', 'success');
                await this.loadInventory();
            } else {
                this.toast((result && result.message) || 'The action did not complete.', 'error');
            }
        } catch (err) {
            this.dialogOpen = false;
            this.pendingAction = null;
            this.toast(this.readError(err), 'error');
        } finally {
            this.dialogBusy = false;
        }
    }
}