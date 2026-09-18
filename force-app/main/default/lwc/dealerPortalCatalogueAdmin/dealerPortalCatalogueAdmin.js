import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord } from 'lightning/uiRecordApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';

import createPackageOptions from '@salesforce/apex/PackageOptionMaintenanceService.createPackageOptions';
import getPackageOptions from '@salesforce/apex/PackageOptionMaintenanceService.getPackageOptions';
import deletePackageOption from '@salesforce/apex/PackageOptionMaintenanceService.deletePackageOption';
import updatePackageOptionPrices from '@salesforce/apex/PackageOptionMaintenanceService.updatePackageOptionPrices';

/**
 * dealerPortalCatalogueAdmin
 *
 * Consolidated catalogue-admin screen (change-plan §09.3 / §11 Phase 5 [L]) —
 * the "catalogue concern" of the one-admin-LWC-per-concern consolidation.
 *
 * What it does
 * ────────────
 * From a Package__c or Package_Term__c record page an admin creates master
 * Package_Option__c catalogue rows in TWO INDEPENDENT sections, exactly the
 * legacy contract:
 *   • Included in Cover — Option__c + inclusion/exclusion text; rows land on
 *     the Package (Package_Term__c launches resolve term → package server-side,
 *     via the tier route or the term's direct package link).
 *   • Additional Options — priced rows: Option__c + Price (required, >= 0).
 *     Launched from a Package__c the legacy shape adds Category__c /
 *     Minimum_Value__c / Maximum_Value__c (min <= max). Launched from a
 *     Package_Term__c the Category/Min/Max columns are hidden; the service
 *     stamps BOTH the Package_Term__c link AND the Package__c resolved from
 *     the term (the link the dealer sync needs to mirror term-anchored
 *     additional options out to dealers).
 *
 * p8 — the two sections are maintained INDEPENDENTLY:
 *   • Two separate row models (includedRows / additionalRows), separate row-id
 *     counters, separate add/remove handlers, separate save buttons, separate
 *     busy flags and separate result/error surfaces. One section saving never
 *     touches the other.
 *   • Split state means an admin can create ONLY Additional, ONLY Included, or
 *     both in one session.
 *   • Save-time hardening: immediately before each payload is built the live
 *     lightning-record-picker values are re-read from the DOM (scoped per
 *     section) and reconciled into the row models, and fully blank rows are
 *     dropped before validation — so a picker that visibly shows a value can
 *     never be reported as empty.
 *   • The "open this screen from a Package or Package Term" guard is wired to a
 *     real getter (recordHasProblem) so an unusable record context shows the
 *     alert instead of an endless spinner or a dead editor.
 *   • mapServiceFailure gained explicit duplicate / integrity / locking /
 *     cross-reference-access buckets (plain, non-technical wording).
 *
 * p10 — the client-side blank check now matches the service's
 * definition exactly: Apex String.isBlank treats null, empty AND whitespace-only
 * as blank, so a row whose optionId is whitespace-only is reported accurately as
 * "a required option is missing" (row N) rather than being treated as present.
 *
 * p11 (this change) — the screen now MANAGES existing options, not just creates
 * them. Per section the rows shown are the EXISTING Package_Option__c rows for
 * the launch context (loaded from PackageOptionMaintenanceService
 * .getPackageOptions) followed by any unsaved NEW rows added with Add Row:
 *   • Included section  — the package's Included rows (Selection_Type__c =
 *     'Included', resolved from the launch Package__c or the term's package).
 *     Rendered read-only (option label + inclusion/exclusion text); a term
 *     screen deliberately shows its package's Included rows because Inclusion
 *     is a package-level concept.
 *   • Additional section — the term's Optional rows on a term launch, or the
 *     package-level Optional rows on a package launch. Price is EDITABLE IN
 *     PLACE; Save pushes changed prices through updatePackageOptionPrices (an
 *     update, never a create) and creates any new rows in the same press.
 *   • A delete (trash) button on every row removes it: existing rows via
 *     deletePackageOption (guarded server-side against cross-context and
 *     already-deleted rows) and new rows locally. The list is reloaded from the
 *     server after every delete / save so the screen always mirrors the org.
 * Existing rows are never treated as "new" rows: they are never blank-dropped,
 * never re-created, and their picker is not reconciled (a text label is shown).
 *
 * Single backend: every write goes to PackageOptionMaintenanceService
 * .createPackageOptions (P5-F) — called once per section with its own payload
 * (isIncluded = true for Included in Cover, false for Additional Options).
 * Reads (record object, Category picklist) come from Lightning Data Service —
 * no controller read methods are used.
 *
 * Supersedes the legacy near-duplicate admin components (plan §05.2): the
 * Create_Package_Options screen flow + createPackageOptions LWC (retired
 * p5-f/p5-h), bulkPackageOptionLWC + bulkPackageOptionAura + their quick
 * actions, and the dealerPortalAdmin family shells.
 *
 * p7-j fixes retained:
 *   • lightning-record-picker change events deliver { recordId } — not an
 *     array; the selection is stored on the row (and cleared to undefined when
 *     the picker is cleared).
 *   • "Wire pending" is separated from "wire failed": a failed or missing
 *     record context renders a clear alert instead of an endless spinner.
 *   • Dealer-facing wording throughout; service messages are mapped to human
 *     phrasing (validation / permission / system categories) client-side —
 *     the Apex strings stay pinned by tests.
 */
export default class DealerPortalCatalogueAdmin extends LightningElement {
    /** Record page passes the Package__c / Package_Term__c record. */
    @api recordId;

    // ── Lightning Data Service reads (no Apex reads) ──────────────────────
    @track recordApiName;
    @track recordError;
    @track categoryValues = [];

    @wire(getRecord, { recordId: '$recordId', fields: ['Id'] })
    wiredRecord({ data, error }) {
        if (data) {
            this.recordApiName = data.apiName;
            this.recordError = undefined;
            // p11: once the context is known, load the rows that already exist.
            this.loadExistingRowsOnce();
        } else if (error) {
            this.recordApiName = undefined;
            this.recordError = (error.body && (error.body.message || error.body.exception)) ||
                error.message || 'The record for this page could not be read.';
        }
    }

    @wire(getObjectInfo, { objectApiName: 'Package_Option__c' })
    wiredObjectInfo({ data, error }) {
        if (data) {
            const field = data.fields && data.fields.Category__c;
            if (field && field.picklistValues) {
                this.categoryValues = field.picklistValues
                    .filter((pv) => pv.isActive)
                    .map((pv) => ({ label: pv.label, value: pv.value }));
            }
        } else if (error) {
            this.categoryValues = [];
        }
    }

    // ── Two INDEPENDENT row models (core p8 fix; extended in p11) ─────────
    // Each section keeps the rows ALREADY IN THE ORG (…Existing) separate from
    // the unsaved rows added on screen (…New). The template reads the
    // concatenation through the includedRows / additionalRows getters, so both
    // origins render in one table while remaining independently replaceable —
    // load/delete can refresh the existing half without disturbing unsaved rows.
    @track includedExisting = [];
    @track additionalExisting = [];
    @track includedNew = [];
    @track additionalNew = [];

    // Separate row-id counters so the two sections never share an identity.
    includedRowCounter = 0;
    additionalRowCounter = 0;

    // One existing-row load per governed record context (the record wire may
    // re-fire); also prevents a load storm while a delete/save is in flight.
    _loadedForRecordId;

    // Separate transient state per section.
    @track includedSaving = false;
    @track additionalSaving = false;
    @track includedError;
    @track includedErrorTitle;
    @track additionalError;
    @track additionalErrorTitle;
    @track includedLastResult;
    @track additionalLastResult;

    get isPackageLaunch() {
        return this.recordApiName === 'Package__c';
    }

    get isTermLaunch() {
        return this.recordApiName === 'Package_Term__c';
    }

    get hasSupportedContext() {
        return this.isPackageLaunch || this.isTermLaunch;
    }

    get contextLabel() {
        if (this.isTermLaunch) {
            return 'Package Term';
        }
        if (this.isPackageLaunch) {
            return 'Package';
        }
        return 'an unsupported record — open this from a Package or Package Term';
    }

    /**
     * Genuinely loading only: a record context exists, the wire has neither
     * answered nor failed yet. A missing recordId or a wire error is a
     * terminal state — never an endless spinner (p7-j fix 4).
     */
    get isLoading() {
        return this.recordId !== undefined &&
            this.recordApiName === undefined &&
            this.recordError === undefined;
    }

    /**
     * p8 fix: the HTML binds if:true/if:false on recordHasProblem, but the
     * getter did not exist — so the warning never rendered and the editor
     * always did. An unusable context is a missing recordId or a record the
     * wire could not read.
     */
    get recordHasProblem() {
        return !this.recordId || this.recordError !== undefined;
    }

    /** Human-facing reason the editor cannot render (missing/erroring record). */
    get recordLoadMessage() {
        if (!this.recordId) {
            return 'Open this screen from an existing Package or Package Term record — it doesn\u2019t work on the new-record page.';
        }
        return 'This screen can\u2019t read the record behind it. ' + (this.recordError || '');
    }

    get showUnsupportedContextWarning() {
        return this.recordApiName !== undefined && !this.hasSupportedContext;
    }

    get showCategoryColumns() {
        // Legacy shape: Category/Min/Max only when launched from a Package__c.
        return this.isPackageLaunch;
    }

    // ── Row lists (existing rows in the org + unsaved new rows) ───────────
    get includedRows() {
        return this.includedExisting.concat(this.includedNew);
    }

    get additionalRows() {
        return this.additionalExisting.concat(this.additionalNew);
    }

    /** True when an existing Additional row's price differs from the loaded value. */
    get hasDirtyAdditionalPrices() {
        return this.additionalExisting.some((r) => r.priceDirty);
    }

    // ── Per-section labels / counts / buttons ─────────────────────────────
    get includedCountLabel() {
        const n = this.includedRows.length;
        return n === 1 ? '1 option' : n + ' options';
    }

    get additionalCountLabel() {
        const n = this.additionalRows.length;
        return n === 1 ? '1 option' : n + ' options';
    }

    get includedSaveDisabled() {
        return this.includedSaving || this.includedNew.length === 0;
    }

    get additionalSaveDisabled() {
        return this.additionalSaving ||
            (this.additionalNew.length === 0 && !this.hasDirtyAdditionalPrices);
    }

    get includedSaveLabel() {
        return this.includedSaving ? 'Saving…' : 'Save Options Included in Cover';
    }

    get additionalSaveLabel() {
        return this.additionalSaving ? 'Saving…' : 'Save Additional Options';
    }

    // ── Row management (per section) ──────────────────────────────────────
    addIncludedRow() {
        this.includedRowCounter += 1;
        const row = makeRow('inc', this.includedRowCounter);
        this.includedNew = this.includedNew.concat([row]);
        this.clearMessages(true);
    }

    addAdditionalRow() {
        this.additionalRowCounter += 1;
        const row = makeRow('add', this.additionalRowCounter);
        this.additionalNew = this.additionalNew.concat([row]);
        this.clearMessages(false);
    }

    removeIncludedRow(event) {
        return this.removeRow(event, true);
    }

    removeAdditionalRow(event) {
        return this.removeRow(event, false);
    }

    /**
     * One trash handler per section. An unsaved NEW row is dropped locally; an
     * EXISTING row is deleted in the org via deletePackageOption and the section
     * is reloaded from the server so the screen mirrors reality (a row deleted
     * elsewhere, or already gone, disappears too).
     */
    removeRow(event, isIncluded) {
        const rowId = event.currentTarget.dataset.rowid;
        const rows = isIncluded ? this.includedRows : this.additionalRows;
        const row = rows.find((r) => r.rowId === rowId);
        if (!row) {
            return undefined;
        }
        if (!row.existing) {
            if (isIncluded) {
                this.includedNew = this.includedNew.filter((r) => r.rowId !== rowId);
            } else {
                this.additionalNew = this.additionalNew.filter((r) => r.rowId !== rowId);
            }
            return undefined;
        }
        return this.deleteExistingRow(isIncluded, row);
    }

    /** Deletes an existing org row, then reloads that section from the server. */
    async deleteExistingRow(isIncluded, row) {
        if (this.deleting) {
            return;
        }
        this.clearMessages(isIncluded);
        this.deleting = true;
        try {
            const result = await deletePackageOption({
                recordId: this.recordId,
                isIncluded,
                optionRowId: row.recordId
            });
            if (result && result.success) {
                const message = isIncluded
                    ? 'Included option removed.'
                    : 'Additional option removed.';
                this.setLastResult(isIncluded, message);
                this.dispatchEvent(
                    new ShowToastEvent({ title: 'Option removed', message, variant: 'success' })
                );
            } else {
                const mapped = mapServiceFailure(result && result.message);
                this.setError(isIncluded, mapped.title, mapped.detail);
                this.dispatchEvent(
                    new ShowToastEvent({ title: mapped.title, message: mapped.detail, variant: 'error' })
                );
            }
        } catch (e) {
            const raw = (e && e.body && (e.body.message || e.body.exception)) ||
                (e && e.message) || 'Unexpected error while removing the option.';
            const mapped = mapServiceFailure(raw);
            this.setError(isIncluded, mapped.title, mapped.detail);
            this.dispatchEvent(
                new ShowToastEvent({ title: mapped.title, message: mapped.detail, variant: 'error' })
            );
        } finally {
            this.deleting = false;
            await this.loadExistingRows(isIncluded);
        }
    }

    handleOptionChange(event) {
        // lightning-record-picker's change event is non-bubbling/non-composed; do not
        // assume currentTarget is populated for it. Read the host defensively and bail
        // (never throw) if it — or its dataset — is missing, so a real selection is not
        // silently lost on the handler's first line.
        const host = event.currentTarget || event.target;
        if (!host || !host.dataset) {
            return;
        }
        const section = host.dataset.section;
        const isIncluded = section === 'included';
        const rowId = host.dataset.rowid;
        // lightning-record-picker fires a change event whose documented detail
        // shape is { recordId } — null when the selection is cleared. Sibling
        // variants across api versions have been seen emitting a bare string,
        // { value }, { id }, or a legacy array of entries. Read every shape
        // defensively so payload-shape drift can never silently drop the
        // selection (the documented shape is read first — proven primary path).
        const recordId = extractPickerValue(event.detail);
        // Only NEW rows carry a picker; existing rows render a text label.
        const rows = isIncluded ? this.includedNew : this.additionalNew;
        const updated = rows.map((r) => r.rowId === rowId
            ? this.refreshRowValidity(
                Object.assign({}, r, { optionId: isBlankValue(recordId) ? undefined : recordId }), isIncluded)
            : r);
        this.assignList(isIncluded, false, updated);
        this.clearMessages(isIncluded);
    }

    handleInput(event) {
        const host = event.currentTarget;
        const section = host.dataset.section;
        const isIncluded = section === 'included';
        const isExisting = host.dataset.existing === 'true';
        const rowId = host.dataset.rowid;
        const field = host.dataset.field;
        let value = event.detail.value;
        if (field === 'price' || field === 'minimumValue' || field === 'maximumValue') {
            value = value === '' || value === null || value === undefined ? null : Number(value);
        }
        const list = isExisting
            ? (isIncluded ? this.includedExisting : this.additionalExisting)
            : (isIncluded ? this.includedNew : this.additionalNew);
        const updated = list.map((r) => {
            if (r.rowId !== rowId) {
                return r;
            }
            let next = Object.assign({}, r, { [field]: value });
            if (isExisting && field === 'price') {
                // Edit-in-place: flag when the price differs from the stored one
                // so the section Save knows there is an update to push.
                next.priceDirty = next.price !== r.loadedPrice;
            }
            next = this.refreshRowValidity(next, isIncluded);
            return next;
        });
        this.assignList(isIncluded, isExisting, updated);
        this.clearMessages(isIncluded);
    }

    /** Returns a NEW row with per-row validity flags applied (never mutates in place). */
    refreshRowValidity(row, isIncluded) {
        const optionMissing = isBlankValue(row.optionId);
        const priceBad = !isIncluded &&
            (row.price === null || row.price === undefined || row.price < 0);
        return Object.assign({}, row, {
            optionMissing,
            optionCellClass: optionMissing ? 'cell-invalid' : '',
            priceInvalid: priceBad,
            priceCellClass: priceBad ? 'cell-invalid' : ''
        });
    }

    assignList(isIncluded, isExisting, rows) {
        if (isExisting) {
            if (isIncluded) {
                this.includedExisting = rows;
            } else {
                this.additionalExisting = rows;
            }
        } else {
            if (isIncluded) {
                this.includedNew = rows;
            } else {
                this.additionalNew = rows;
            }
        }
    }

    setNewRows(isIncluded, rows) {
        if (isIncluded) {
            this.includedNew = rows;
        } else {
            this.additionalNew = rows;
        }
    }

    clearMessages(isIncluded) {
        if (isIncluded) {
            this.includedError = undefined;
            this.includedErrorTitle = undefined;
        } else {
            this.additionalError = undefined;
            this.additionalErrorTitle = undefined;
        }
    }

    setError(isIncluded, title, detail) {
        if (isIncluded) {
            this.includedErrorTitle = title;
            this.includedError = detail;
        } else {
            this.additionalErrorTitle = title;
            this.additionalError = detail;
        }
    }

    setLastResult(isIncluded, message) {
        if (isIncluded) {
            this.includedLastResult = message;
        } else {
            this.additionalLastResult = message;
        }
    }

    /**
     * Save-time hardening (p8): re-read the live pickers from the DOM, scoped
     * to this section, and reconcile their current value into the row models.
     * Blank rows are dropped by the caller. Never mutates a row object.
     */
    reconcileRowsFromDom(section, rows, isIncluded) {
        let pickers = [];
        try {
            pickers = this.template.querySelectorAll(
                '.' + section + '-section lightning-record-picker');
        } catch (e) {
            pickers = [];
        }
        const valueByRowId = {};
        pickers.forEach((picker) => {
            valueByRowId[picker.dataset.rowid] = picker.value;
        });
        return rows.map((r) => {
            if (Object.prototype.hasOwnProperty.call(valueByRowId, r.rowId)) {
                const v = valueByRowId[r.rowId];
                return this.refreshRowValidity(
                    // Never let an empty (or whitespace-only) DOM read blank a row the model
                    // already populated; the picker value is published FROM the row, so a
                    // blank read is a mirror, not evidence the user made no selection.
                    Object.assign({}, r, { optionId: isBlankValue(v) ? r.optionId : v }), isIncluded);
            }
            return this.refreshRowValidity(r, isIncluded);
        });
    }

    isBlankRow(row) {
        const noOption = isBlankValue(row.optionId);
        const noText = !row.inclusionText && !row.exclusionText;
        const noPrice = row.price === null || row.price === undefined;
        const noCategory = !row.category;
        const noMin = row.minimumValue === null || row.minimumValue === undefined;
        const noMax = row.maximumValue === null || row.maximumValue === undefined;
        return noOption && noText && noPrice && noCategory && noMin && noMax;
    }

    // ── Save (one handler per section — one never touches the other) ──────
    handleSaveIncluded() {
        return this.saveSection('included');
    }

    handleSaveAdditional() {
        return this.saveSection('additional');
    }

    async saveSection(section) {
        const isIncluded = section === 'included';
        this.clearMessages(isIncluded);

        if (!this.recordId) {
            this.setError(isIncluded, 'Options not saved',
                'No record context — open this screen from a Package or Package Term record page.');
            return;
        }

        // Reconcile live picker values into the NEW rows only, then drop blanks.
        let reconciled = this.reconcileRowsFromDom(section, this.newRowsFor(isIncluded), isIncluded);
        reconciled = reconciled.filter((r) => !this.isBlankRow(r));
        this.setNewRows(isIncluded, reconciled);

        const dirtyExisting = this.existingRowsFor(isIncluded).filter((r) => !isIncluded && r.priceDirty);

        if (reconciled.length === 0 && dirtyExisting.length === 0) {
            this.setError(isIncluded, 'Options not saved', 'Add at least one row before saving.');
            return;
        }

        // Client-side pre-check for NEW rows mirrors the service validation.
        if (reconciled.length) {
            const firstMissing = reconciled.findIndex((r) => isBlankValue(r.optionId));
            if (firstMissing !== -1) {
                this.setError(isIncluded, 'Options not saved',
                    'Select an option for each row before saving (row ' + (firstMissing + 1) + ' is missing).');
                return;
            }
            if (!isIncluded) {
                const firstBadPrice = reconciled.findIndex(
                    (r) => r.price === null || r.price === undefined || r.price < 0
                );
                if (firstBadPrice !== -1) {
                    this.setError(isIncluded, 'Options not saved',
                        'Enter a price of 0 or more for each additional option (row ' +
                        (firstBadPrice + 1) + ' needs a price).');
                    return;
                }
                const badRange = reconciled.find(
                    (r) => r.minimumValue !== null && r.maximumValue !== null &&
                        r.minimumValue !== undefined && r.maximumValue !== undefined &&
                        r.minimumValue > r.maximumValue
                );
                if (badRange) {
                    this.setError(isIncluded, 'Options not saved',
                        'Minimum Value cannot be greater than Maximum Value.');
                    return;
                }
            }
        }

        if (!isIncluded) {
            const badExisting = dirtyExisting.find(
                (r) => r.price === null || r.price === undefined || r.price < 0
            );
            if (badExisting) {
                this.setError(isIncluded, 'Options not saved',
                    'Enter a price of 0 or more for each additional option.');
                return;
            }
        }

        this.setSaving(isIncluded, true);
        try {
            let updated = 0;
            let created = 0;

            // p11 — update price on existing Optional rows first (one Apex call).
            if (dirtyExisting.length) {
                const rows = dirtyExisting.map((r) => ({
                    optionRowId: r.recordId,
                    price: r.price
                }));
                const res = await updatePackageOptionPrices({
                    recordId: this.recordId,
                    rows
                });
                if (!res || !res.success) {
                    throw res || { message: 'Unexpected error while saving.' };
                }
                updated = res.affectedCount || dirtyExisting.length;
            }

            // Create any NEW rows (unchanged p8 path).
            if (reconciled.length) {
                const rowsPayload = reconciled.map((r) => ({
                    optionId: r.optionId,
                    category: r.category,
                    minimumValue: r.minimumValue,
                    maximumValue: r.maximumValue,
                    price: r.price,
                    inclusionText: r.inclusionText,
                    exclusionText: r.exclusionText,
                    packageTermId: this.isTermLaunch ? this.recordId : null
                }));
                const result = await createPackageOptions({
                    recordId: this.recordId,
                    rows: rowsPayload,
                    isIncluded
                });
                if (!(result && result.success)) {
                    throw result || { message: 'Unexpected error while saving.' };
                }
                created = result.createdCount;
            }

            const parts = [];
            if (created) {
                parts.push(created + ' option' + (created === 1 ? '' : 's') +
                    (isIncluded ? ' added to this package' : ' added to this package term'));
            }
            if (updated) {
                parts.push(updated + ' price' + (updated === 1 ? '' : 's') + ' updated');
            }
            const message = parts.join('; ');
            this.setLastResult(isIncluded, message);
            this.dispatchEvent(
                new ShowToastEvent({ title: 'Options saved', message, variant: 'success' })
            );
            this.setNewRows(isIncluded, []);
            await this.loadExistingRows();
        } catch (e) {
            const raw = (e && e.body && (e.body.message || e.body.exception)) ||
                (e && e.message) || 'Unexpected error while saving.';
            const mapped = mapServiceFailure(raw);
            this.setError(isIncluded, mapped.title, mapped.detail);
            this.dispatchEvent(
                new ShowToastEvent({ title: mapped.title, message: mapped.detail, variant: 'error' })
            );
        } finally {
            this.setSaving(isIncluded, false);
        }
    }

    setSaving(isIncluded, value) {
        if (isIncluded) {
            this.includedSaving = value;
        } else {
            this.additionalSaving = value;
        }
    }

    newRowsFor(isIncluded) {
        return isIncluded ? this.includedNew : this.additionalNew;
    }

    existingRowsFor(isIncluded) {
        return isIncluded ? this.includedExisting : this.additionalExisting;
    }

    /** Load once per governed record context (wiredRecord may fire more than once). */
    loadExistingRowsOnce() {
        if (!this.recordId || this._loadedForRecordId === this.recordId) {
            return;
        }
        this._loadedForRecordId = this.recordId;
        return this.loadExistingRows();
    }

    /**
     * p11 — load the rows that already exist for this launch record from the
     * service. When `section` is supplied, only that section is refreshed
     * (used after a per-section delete). When omitted, both sections are
     * refreshed (used after save).
     */
    async loadExistingRows(section) {
        if (!this.recordId) {
            return;
        }
        const wantIncluded = section === undefined || section === true;
        const wantAdditional = section === undefined || section === false;
        try {
            const requests = [];
            requests.push(wantIncluded
                ? getPackageOptions({ recordId: this.recordId, isIncluded: true })
                : Promise.resolve(null));
            requests.push(wantAdditional
                ? getPackageOptions({ recordId: this.recordId, isIncluded: false })
                : Promise.resolve(null));
            const [includedViews, additionalViews] = await Promise.all(requests);
            if (wantIncluded) {
                this.includedExisting = (includedViews || []).map((v) =>
                    makeExistingRow('inc-ex', v, true));
            }
            if (wantAdditional) {
                this.additionalExisting = (additionalViews || []).map((v) =>
                    makeExistingRow('add-ex', v, false));
            }
        } catch (e) {
            const raw = (e && e.body && (e.body.message || e.body.exception)) ||
                (e && e.message) || 'Unexpected error while loading options.';
            const mapped = mapServiceFailure(raw);
            if (wantIncluded) {
                this.setError(true, mapped.title, mapped.detail);
            }
            if (wantAdditional) {
                this.setError(false, mapped.title, mapped.detail);
            }
        }
    }
}

/** A fresh, empty editable row (never shared between the two sections). */
function makeRow(idPrefix, n) {
    return {
        rowId: idPrefix + n,
        optionId: undefined,
        optionMissing: false,
        optionCellClass: '',
        category: undefined,
        minimumValue: undefined,
        maximumValue: undefined,
        price: undefined,
        priceInvalid: false,
        priceCellClass: '',
        inclusionText: undefined,
        exclusionText: undefined
    };
}

/** Existing row from getPackageOptions — rendered read-only (except price for Optional). */
function makeExistingRow(idPrefix, view, isIncluded) {
    const price = view.price;
    return {
        rowId: idPrefix + '-' + view.id,
        recordId: view.id,
        existing: true,
        optionId: view.optionId,
        optionName: view.optionName,
        price: price,
        loadedPrice: price,
        priceDirty: false,
        priceInvalid: false,
        priceCellClass: '',
        inclusionText: view.inclusionText,
        exclusionText: view.exclusionText,
        category: view.category,
        minimumValue: view.minimumValue,
        maximumValue: view.maximumValue,
        optionMissing: false,
        optionCellClass: ''
    };
}

/**
 * Server parity: what Apex String.isBlank treats as blank — null, the empty
 * string, or a whitespace-only string (incl. the NBSP the picker has been seen
 * to hand over). Keeping this in one place means the client's blank checks can
 * never drift from the service's.
 */
function isBlankValue(v) {
    return v === null || v === undefined || String(v).trim() === '';
}

/**
 * Reads the selected record id out of a lightning-record-picker change event.
 * The documented shape ({ recordId }) is read first and remains the proven
 * primary path; the other shapes are defensive fallbacks only.
 */
function extractPickerValue(detail) {
    if (Array.isArray(detail)) {
        const first = detail.length > 0 ? detail[0] || {} : {};
        return first.recordId !== undefined ? first.recordId
            : (first.id !== undefined ? first.id : first.value);
    }
    if (detail && typeof detail === 'object') {
        return detail.recordId !== undefined ? detail.recordId
            : (detail.id !== undefined ? detail.id : detail.value);
    }
    if (typeof detail === 'string' && detail !== '') {
        return detail;
    }
    return undefined;
}

/**
 * Maps a service / Apex failure to human phrasing, and classifies it so the
 * alert tells the admin whether it is their input, their permissions, or a
 * system problem. Apex strings stay untouched (tests pin them). Wording stays
 * plain and non-technical — no API names are ever surfaced.
 */
function mapServiceFailure(rawMessage) {
    const raw = rawMessage || '';

    // Known service validation messages → human phrasing, "your input" category.
    const known = [
        {
            match: 'Could not find Package from Package Term relationship',
            detail: 'This term isn\u2019t linked to a package tier, so options can\u2019t be attached. ' +
                'Link it to a tier/package first or contact your administrator.'
        },
        { match: 'Record ID is required', detail: 'No record context — reopen this screen from a Package or Package Term.' },
        { match: 'At least one row is required', detail: 'Add at least one row before saving.' },
        { match: 'Option is required for all rows', detail: 'A required option was missing — select an option for each row.' },
        { match: 'Price must be greater than or equal to 0', detail: 'Enter a price of 0 or more for each additional option.' },
        { match: 'Minimum Value cannot be greater than Maximum Value', detail: 'Minimum Value cannot be greater than Maximum Value.' },
        { match: 'Option row ID is required', detail: 'Select a row to update.' },
        { match: 'That option row no longer exists', detail: 'That option was already removed — the list has been refreshed.' },
        { match: 'That option row does not belong to this package or term', detail: 'That option isn\u2019t part of this package or term.' }
    ];
    for (const k of known) {
        if (raw.includes(k.match)) {
            return { title: 'Options not saved', detail: k.detail };
        }
    }

    const upper = raw.toUpperCase();
    const lower = raw.toLowerCase();

    // Duplicate — the same option already sits on this package/term.
    if (upper.includes('DUPLICATE_VALUE') || lower.includes('duplicate value')) {
        return {
            title: 'Options not saved — already added',
            detail: 'One of these options is already on this package, so it can\u2019t be added twice. ' +
                'Remove the duplicate row and try again.'
        };
    }

    // Integrity — a value the record won\u2019t accept (missing required, bad
    // picklist value, too long, or a related record that has gone away).
    if (upper.includes('FIELD_INTEGRITY_EXCEPTION') ||
        upper.includes('REQUIRED_FIELD_MISSING') ||
        upper.includes('INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST') ||
        upper.includes('STRING_TOO_LONG') ||
        lower.includes('restricted picklist') ||
        lower.includes('too long')) {
        return {
            title: 'Options not saved — check the details',
            detail: 'One of the values isn\u2019t valid for this package. Check the option, its category ' +
                'and any value limits, then try again.'
        };
    }

    // Locking — someone else is editing the same record right now.
    if (upper.includes('UNABLE_TO_LOCK_ROW') ||
        lower.includes('unable to lock row') ||
        lower.includes('could not obtain exclusive access')) {
        return {
            title: 'Options not saved — record busy',
            detail: 'This record was being updated by someone else at the same time. ' +
                'Wait a moment and save again.'
        };
    }

    // Cross-reference access — one of the linked records isn\u2019t reachable.
    if (upper.includes('INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY') ||
        lower.includes('insufficient access on cross reference')) {
        return {
            title: 'Options not saved — permission needed',
            detail: 'One of the selected records can\u2019t be linked by your login. ' +
                'Ask your administrator to check your access.'
        };
    }

    // Permission-shaped failures (Apex class access, object CRUD, sharing).
    if (
        lower.includes('insufficient access') ||
        lower.includes('insufficient privileges') ||
        lower.includes('not accessible') ||
        lower.includes('apex class') ||
        lower.includes('access to the apex') ||
        lower.includes('entity is not accessible') ||
        lower.includes('you don\u2019t have access') ||
        lower.includes("you don't have access") ||
        lower.includes('unauthorized')
    ) {
        return {
            title: 'Options not saved — permission needed',
            detail: 'Your login doesn\u2019t have permission to save options here. ' +
                'Ask your administrator to check your access.'
        };
    }

    // Everything else is a system failure.
    return {
        title: 'Options not saved — system error',
        detail: 'Something went wrong while saving. Try again, and if it keeps happening ' +
            'contact your administrator.'
    };
}