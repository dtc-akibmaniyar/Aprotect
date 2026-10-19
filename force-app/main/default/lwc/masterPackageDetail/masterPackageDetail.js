import { LightningElement, api } from 'lwc';
import getPackageDetail from '@salesforce/apex/MasterPackageAdminService.getPackageDetail';
import getFormOptions from '@salesforce/apex/MasterPackageAdminService.getFormOptions';
import getContextAssignments from '@salesforce/apex/MasterPackageScheduleService.getContextAssignments';

export default class MasterPackageDetail extends LightningElement {
    _packageId;
    _autoEdit = false;
    _autoOpened = false;
    @api packageName = '';
    @api backLabel = 'Package Group';
    detail;
    formOptions = {};
    schedules = [];
    loading = false;
    errorMessage;
    notice;
    noticeTone;
    // Options regrouped under their package term (display only).
    tierBlocksView = [];
    unassignedIncluded = [];
    unassignedOptional = [];
    hasUnassigned = false;
    hasUnassignedIncluded = false;
    hasUnassignedOptional = false;

    @api get packageId() { return this._packageId; }
    set packageId(value) {
        this._packageId = value;
        this._autoOpened = false;
        if (value) {
            this.load(value);
        } else {
            this.detail = undefined;
            this.schedules = [];
            this._clearOptionGroups();
        }
    }
    @api get autoEdit() { return this._autoEdit; }
    set autoEdit(value) { this._autoEdit = value === true || value === 'true'; }

    connectedCallback() { this.loadFormOptions(); }

    get hasDetail() { return !!(this.detail && this.detail.id); }
    get title() { return this.detail && this.detail.name ? this.detail.name : (this.packageName || ''); }
    get isInactive() { return this.detail ? this.detail.isActive === false : false; }
    get toggleActiveLabel() { return this.isInactive ? 'Activate' : 'Deactivate'; }
    get statusClass() { return 'ap-status-pill ap-status-pill_' + (this.isInactive ? 'draft' : 'published'); }
    get hasNotice() { return !!this.notice; }
    get noticeClass() { return 'ap-toast ' + (this.noticeTone === 'error' ? 'ap-toast_error' : 'ap-toast_ok'); }
    get hasTierBlocks() { return this.tierBlocksView.length > 0; }
    get hasAddOns() { return !!(this.detail && this.detail.addOns && this.detail.addOns.length); }
    get hasBenefitCaps() { return !!(this.detail && this.detail.benefitCaps && this.detail.benefitCaps.length); }
    get hasSchedules() { return this.schedules.length > 0; }
    get optionSummary() {
        if (!this.detail) { return ''; }
        return (this.detail.optionCount || 0) + ' option' + (this.detail.optionCount === 1 ? '' : 's');
    }
    get addOnSummary() {
        if (!this.detail) { return ''; }
        return (this.detail.addOnCount || 0) + ' add-on' + (this.detail.addOnCount === 1 ? '' : 's');
    }
    get capSummary() {
        if (!this.detail) { return ''; }
        return (this.detail.benefitCapCount || 0) + ' capped benefit' + (this.detail.benefitCapCount === 1 ? '' : 's');
    }

    async loadFormOptions() {
        try { this.formOptions = await getFormOptions(); } catch (error) { this.formOptions = {}; }
    }
    async load(packageId) {
        this.loading = true;
        this.errorMessage = undefined;
        try {
            this.detail = await getPackageDetail({ packageId });
        } catch (error) {
            this.detail = undefined;
            this.errorMessage = this.reduceError(error);
        } finally {
            this.loading = false;
        }
        this._rebuildOptionGroups();
        await this.loadSchedules(packageId);
        if (this._autoEdit && !this._autoOpened && this.detail && this.detail.id) {
            this._autoOpened = true;
            this.handleEditPackage();
        }
    }
    async loadSchedules(packageId) {
        try {
            const panel = await getContextAssignments({ contextType: 'package', contextId: packageId });
            this.schedules = (panel && panel.assignments) ? panel.assignments : [];
        } catch (error) {
            this.schedules = [];
        }
    }
    async refresh() {
        if (this._packageId) { await this.load(this._packageId); }
    }
    editor() { return this.template.querySelector('c-master-package-editor'); }
    schedulePanel() { return this.template.querySelector('c-master-package-schedule'); }
    openEditor(entity, mode, seed) {
        const child = this.editor();
        if (!child) { return; }
        child.open({ entity, mode, seed: seed || {}, detail: this.detail || {}, formOptions: this.formOptions || {}, packageName: this.title });
    }

    // ---- Options grouped under each package term (display only) ----
    _clearOptionGroups() {
        this.tierBlocksView = [];
        this.unassignedIncluded = [];
        this.unassignedOptional = [];
        this.hasUnassigned = false;
    }
    _rebuildOptionGroups() {
        const detail = this.detail;
        if (!detail || !detail.id) { this._clearOptionGroups(); return; }
        const blocks = detail.tierBlocks || [];
        const knownTerms = {};
        blocks.forEach((b) => {
            (b.terms || []).forEach((t) => { knownTerms[t.id] = true; });
        });
        const byTerm = {};
        const unassigned = { included: [], optional: [] };
        (detail.options || []).forEach((o) => {
            const kind = String(o.selectionType || '').toLowerCase() === 'optional' ? 'optional' : 'included';
            const termId = o.termId;
            if (termId && knownTerms[termId]) {
                if (!byTerm[termId]) { byTerm[termId] = { included: [], optional: [] }; }
                byTerm[termId][kind].push(o);
            } else {
                unassigned[kind].push(o);
            }
        });
        this.tierBlocksView = blocks.map((b) => {
            const rows = [];
            (b.terms || []).forEach((t) => {
                const g = byTerm[t.id] || { included: [], optional: [] };
                const termRow = Object.assign({}, t, {
                    key: 'term-' + t.id,
                    isTerm: true
                });
                rows.push(termRow);
                rows.push({
                    key: 'opts-' + t.id,
                    isTerm: false,
                    termId: t.id,
                    termName: t.name,
                    includedOptions: g.included,
                    optionalOptions: g.optional,
                    hasIncluded: g.included.length > 0,
                    hasOptional: g.optional.length > 0
                });
            });
            return {
                groupKey: b.groupKey,
                bandLabel: b.bandLabel,
                tierName: b.tierName,
                hasTier: b.hasTier,
                tierId: b.tierId,
                startMileage: b.startMileage,
                endMileage: b.endMileage,
                mileageUnit: b.mileageUnit,
                rows: rows,
                hasRows: rows.length > 0
            };
        });
        this.unassignedIncluded = unassigned.included;
        this.unassignedOptional = unassigned.optional;
        this.hasUnassigned = unassigned.included.length > 0 || unassigned.optional.length > 0;
    }

    handleEditPackage() { this.openEditor('package', 'edit', { recordId: this.detail.id }); }
    handleToggleActive() {
        const child = this.editor();
        if (child) { child.toggleActive(this.detail.id, this.isInactive, this.title); }
    }
    handleDeactivateCascade() {
        const child = this.editor();
        if (child) { child.askDeactivateCascade(this.detail.id, this.title); }
    }
    handleNewTier() { this.openEditor('tier', 'create', { packageId: this.detail.id }); }
    handleEditTier(event) {
        const id = event.currentTarget.dataset.id;
        const block = (this.detail.tierBlocks || []).find((b) => b.tierId === id) || {};
        this.openEditor('tier', 'edit', { recordId: id, packageId: this.detail.id, name: block.tierName, startMileage: block.startMileage, endMileage: block.endMileage, mileageUnit: block.mileageUnit });
    }
    handleNewTerm(event) {
        const tierId = (event && event.currentTarget && event.currentTarget.dataset.tier) || null;
        this.openEditor('term', 'create', { packageId: this.detail.id, tierId });
    }
    handleEditTerm(event) {
        const term = this.findTerm(event.currentTarget.dataset.id);
        if (term) { this.openEditor('term', 'edit', Object.assign({ packageId: this.detail.id }, term)); }
    }
    handleNewOption(event) {
        const termId = (event && event.currentTarget && event.currentTarget.dataset.term) || null;
        this.openEditor('option', 'create', { packageId: this.detail.id, selectionType: 'Included', termId });
    }
    handleNewOptionalOption(event) {
        const termId = (event && event.currentTarget && event.currentTarget.dataset.term) || null;
        this.openEditor('option', 'create', { packageId: this.detail.id, selectionType: 'Optional', termId });
    }
    handleEditOption(event) {
        const row = (this.detail.options || []).find((o) => o.id === event.currentTarget.dataset.id);
        if (row) { this.openEditor('option', 'edit', Object.assign({ packageId: this.detail.id }, row)); }
    }
    handleNewAddOn(event) { this.openEditor('addon', 'create', { termId: event.currentTarget.dataset.term }); }
    handleEditAddOn(event) {
        const row = (this.detail.addOns || []).find((a) => a.id === event.currentTarget.dataset.id);
        if (row) { this.openEditor('addon', 'edit', Object.assign({ packageId: this.detail.id }, row)); }
    }
    handleNewBenefitCap(event) { this.openEditor('benefitcap', 'create', { termId: event.currentTarget.dataset.term }); }
    handleEditBenefitCap(event) {
        const row = (this.detail.benefitCaps || []).find((b) => b.id === event.currentTarget.dataset.id);
        if (row) { this.openEditor('benefitcap', 'edit', Object.assign({ packageId: this.detail.id }, row)); }
    }
    handleDeleteTier(e) { this.deleteVia('tier', e.currentTarget.dataset.id); }
    handleDeleteTerm(e) { this.deleteVia('term', e.currentTarget.dataset.id, this.termLabel(e.currentTarget.dataset.id)); }
    handleDeleteOption(e) { this.deleteVia('option', e.currentTarget.dataset.id); }
    handleDeleteAddOn(e) { this.deleteVia('addon', e.currentTarget.dataset.id); }
    handleDeleteBenefitCap(e) { this.deleteVia('benefitcap', e.currentTarget.dataset.id); }
    deleteVia(kind, id, label) {
        const child = this.editor();
        if (child) { child.askDelete(kind, id, label); }
    }
    findTerm(id) {
        for (const block of (this.detail.tierBlocks || [])) {
            for (const t of (block.terms || [])) {
                if (t.id === id) { return t; }
            }
        }
        return undefined;
    }
    termLabel(id) {
        const t = this.findTerm(id);
        return t ? t.name : 'this term';
    }
    handleOpenSchedules() {
        if (!this.detail || !this.detail.id) { return; }
        const child = this.schedulePanel();
        if (child) {
            child.openPanel({ mode: 'context', contextType: 'package', contextId: this.detail.id, contextLabel: this.title });
        }
    }
    handleBack() { this.dispatchEvent(new CustomEvent('back')); }
    handleWritten(event) {
        this.notice = event.detail.message;
        this.noticeTone = 'ok';
        this.errorMessage = undefined;
        this.refresh();
    }
    handleWriteError(event) { this.errorMessage = event.detail.message; }
    handleDismissNotice() { this.notice = undefined; }
    reduceError(error) {
        if (Array.isArray(error) && error.length && error[0].message) { return error[0].message; }
        if (error && error.body && error.body.message) { return error.body.message; }
        if (error && error.message) { return error.message; }
        return 'Something went wrong loading this package.';
    }
}