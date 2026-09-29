import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import LightningConfirm from 'lightning/confirm';
import getEstimateDetailsForClaim from '@salesforce/apex/ClaimEstimateService.getEstimateDetailsForClaim';
import saveEstimates from '@salesforce/apex/ClaimEstimateService.saveEstimates';
import getDefaults from '@salesforce/apex/ClaimPricingService.getDefaults';

const SOURCE_OPTIONS = [
    { label: 'Same shop as diagnostics', value: 'Same shop as diagnostics' },
    { label: 'Network shop', value: 'Network shop' }
];
const INSURANCE_SOURCE_OPTIONS = [
    { label: 'None', value: 'None' },
    { label: 'From Parts Supplier', value: 'From Parts Supplier' },
    { label: 'From A-Protect', value: 'From A-Protect' }
];
const PART_COMPONENT_OPTIONS = [
    'Engine', 'Transmission', 'Alternator', 'A/C Compressor', 'Suspension',
    'Brakes', 'Electrical', 'Starter', 'Differential', 'Other'
].map((v) => ({ label: v, value: v }));
const JOB_TYPE_OPTIONS = ['REPLACEMENT', 'RECONDITIONED', 'REBUILD', 'NEW'].map((v) => ({ label: v, value: v }));
const CONDITION_OPTIONS = ['NEW', 'USED', 'AFTERMARKET'].map((v) => ({ label: v, value: v }));

const EMPTY_RESULT = { labour: 0, wsTotal: 0, coverage: 0, custPre: 0, custTax: 0, pl: 0, retailTotal: 0 };

const BEST_BG = '#f4fbf9';
const WHITE_BG = '#ffffff';
const ACCENT = '#1f9e8f';
const PROFIT_BG = '#e3f6ea';
const LOSS_BG = '#fdebeb';

/**
 * Repair Price Scenarios "Column Compare" grid - a manage screen for every
 * estimate on a claim (Sep 22 feedback: not just an add-new form). Loads
 * every existing Estimate__c for the claim as an editable column, plus lets
 * the agent add new ones and remove any (pending removal is only applied on
 * Save, same as every other edit here - nothing is destructive until Save
 * All Estimates is clicked). Field order mirrors
 * warranty_claims_dashboard (2).html exactly (Osama, Sep 22: that file, not
 * any design mockup, is the single source of truth for field order, the
 * same way it already is for the pricing formula). Live math is a
 * client-side port of ClaimPricingService.calculate() (must stay in sync
 * with it; that class carries the same note pointing back here) so every
 * keystroke across every column recomputes instantly with no server round
 * trip.
 */
export default class RepairPriceScenarios extends LightningModal {
    @api claimId;

    rows = [];
    rowSeq = 1;
    pendingDeleteIds = [];
    defaults = { cap: null, ded: null, claimRef: '' };

    isSaving = false;
    isLoading = true;
    errorMessage;

    sourceOptions = SOURCE_OPTIONS;
    insuranceSourceOptions = INSURANCE_SOURCE_OPTIONS;
    partComponentOptions = PART_COMPONENT_OPTIONS;
    jobTypeOptions = JOB_TYPE_OPTIONS;
    conditionOptions = CONDITION_OPTIONS;

    async connectedCallback() {
        await this.loadClaimDefaults();
        await this.loadExistingEstimates();
        this.isLoading = false;
        this.recalcAll();
    }

    async loadExistingEstimates() {
        try {
            const existing = await getEstimateDetailsForClaim({ claimId: this.claimId });
            if (existing && existing.length) {
                const hasSelected = existing.some((e) => e.Is_Selected__c);
                this.rows = existing.map((e, idx) =>
                    this.rowFromEstimate(e, hasSelected ? e.Is_Selected__c : idx === 0)
                );
                return;
            }
        } catch (e) {
            this.errorMessage = 'Could not load existing estimates for this claim.';
        }
        this.rows = [this.makeRow(true)];
    }

    rowFromEstimate(e, isUse) {
        const row = this.makeRow(isUse);
        row.createdId = e.Id;
        row.estimateName = e.Estimate_Name__c || '';
        row.repairShopId = e.Repair_Shop__c || null;
        // Bug fix (Sep 22, Osama caught it comparing Customer Pays (+tax) against
        // the HTML): loading an existing estimate never populated taxPercent, so
        // custTax = custPre * (1 + 0/100) = custPre - tax silently dropped out
        // for every already-saved row until its shop was touched again. Only
        // fresh rows going through handleRowShopChange got a real tax percent.
        row.taxPercent = e.Repair_Shop__r ? e.Repair_Shop__r.Tax_Percentage__c : null;
        row.source = e.Source__c || null;
        row.partComponent = e.Part_Component__c || null;
        row.jobType = e.Job_Type__c || null;
        row.partsSupplierId = e.Parts_Supplier__c || null;
        row.partCode = e.Part_Code__c || '';
        row.stockNumber = e.Stock_Number__c || '';
        row.condition = e.Condition__c || null;
        row.kms = e.KMs__c != null ? e.KMs__c : '';
        row.insuranceSource = e.Insurance_Source__c || 'None';
        row.ins = e.Insurance_Amount__c != null ? e.Insurance_Amount__c : '';
        row.partsCost = e.Parts_Cost__c != null ? e.Parts_Cost__c : '';
        row.hrs = e.Labour_Hours__c != null ? e.Labour_Hours__c : '';
        row.rate = e.Labour_Rate__c != null ? e.Labour_Rate__c : '';
        row.supC = e.Shop_Supplies__c != null ? e.Shop_Supplies__c : '';
        row.supR = e.Shop_Supplies_Retail__c != null ? e.Shop_Supplies_Retail__c : '';
        row.retail = e.Retail_Price__c != null ? e.Retail_Price__c : '';
        row.dedOverride = e.Deductable__c != null ? e.Deductable__c : '';
        return row;
    }

    makeRow(isUse) {
        return {
            id: 'row-' + this.rowSeq++,
            createdId: null,
            estimateName: '',
            repairShopId: null,
            source: null,
            partComponent: null,
            jobType: null,
            partsSupplierId: null,
            partCode: '',
            stockNumber: '',
            condition: null,
            kms: '',
            insuranceSource: 'None',
            ins: '',
            partsCost: '',
            hrs: '',
            rate: '',
            supC: '',
            supR: '',
            retail: '',
            dedOverride: '',
            taxPercent: null,
            isUse: !!isUse,
            result: EMPTY_RESULT,
            isBest: false,
            headerStyle: '',
            cellStyle: '',
            plStyle: '',
            plClass: 'v pl-val'
        };
    }

    async loadClaimDefaults() {
        try {
            const d = await getDefaults({ claimId: this.claimId, repairShopId: null });
            this.defaults = d;
        } catch (e) {
            // read-only convenience defaults; leave blank if this fails
        }
    }

    get removeRowDisabled() {
        return this.rows.length <= 1;
    }

    /** Splits ClaimPricingService.buildClaimRef's "<claim> · <vehicle>" on the
     * same middle-dot separator it uses - keep this literal in sync with
     * ClaimPricingService.buildClaimRef if that format ever changes. */
    get claimNumberDisplay() {
        const ref = this.defaults.claimRef || '';
        const idx = ref.indexOf(' · ');
        return idx === -1 ? ref : ref.substring(0, idx);
    }
    get vehicleDisplay() {
        const ref = this.defaults.claimRef || '';
        const idx = ref.indexOf(' · ');
        return idx === -1 ? '' : ref.substring(idx + 3);
    }

    handleAddRow() {
        this.rows = [...this.rows, this.makeRow(false)];
        this.recalcAll();
    }

    async handleRemoveRow(event) {
        if (this.rows.length <= 1) return;
        const rowId = event.currentTarget.dataset.rowId;
        const removed = this.rows.find((r) => r.id === rowId);
        if (!removed) return;

        const name = removed.estimateName || 'this estimate';
        const confirmed = await LightningConfirm.open({
            message: removed.createdId
                ? `Remove "${name}"? It will be permanently deleted when you click Save All Estimates.`
                : `Remove "${name}"? It hasn't been saved, so this can't be undone.`,
            label: 'Remove Estimate',
            theme: 'warning'
        });
        if (!confirmed) return;

        if (removed.createdId) {
            this.pendingDeleteIds = [...this.pendingDeleteIds, removed.createdId];
        }
        this.rows = this.rows.filter((r) => r.id !== rowId);
        if (removed.isUse && this.rows.length) {
            this.rows = this.rows.map((r, idx) => ({ ...r, isUse: idx === 0 }));
        }
        this.recalcAll();
    }

    handleUseChange(event) {
        const rowId = event.currentTarget.dataset.rowId;
        this.rows = this.rows.map((r) => ({ ...r, isUse: r.id === rowId }));
        this.recalcAll();
    }

    handleRowFieldChange(event) {
        const rowId = event.currentTarget.dataset.rowId;
        const field = event.currentTarget.dataset.field;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        this.updateRow(rowId, { [field]: value });
        this.recalcAll();
    }

    handleRowComboChange(event) {
        const rowId = event.currentTarget.dataset.rowId;
        const field = event.currentTarget.dataset.field;
        this.updateRow(rowId, { [field]: event.detail.value });
        this.recalcAll();
    }

    handleRowPartsSupplierChange(event) {
        const rowId = event.currentTarget.dataset.rowId;
        this.updateRow(rowId, { partsSupplierId: event.detail.recordId });
    }

    async handleRowShopChange(event) {
        const rowId = event.currentTarget.dataset.rowId;
        const repairShopId = event.detail.recordId;
        this.updateRow(rowId, { repairShopId });
        try {
            const d = await getDefaults({ claimId: this.claimId, repairShopId });
            const row = this.rows.find((r) => r.id === rowId);
            const patch = { taxPercent: d.taxPercent };
            if (!row.rate && d.labourRateOnFile != null) patch.rate = d.labourRateOnFile;
            this.updateRow(rowId, patch);
        } catch (e) {
            // shop defaults are a convenience only
        }
        this.recalcAll();
    }

    updateRow(rowId, patch) {
        this.rows = this.rows.map((r) => (r.id === rowId ? { ...r, ...patch } : r));
    }

    /** Client-side mirror of ClaimPricingService.calculate() - keep both in sync. */
    calcRow(row) {
        const parts = this.numOrZero(row.partsCost);
        const labour = this.numOrZero(row.hrs) * this.numOrZero(row.rate);
        const wsTotal = parts + labour + this.numOrZero(row.supC) + this.numOrZero(row.ins);
        const retail = this.numOrZero(row.retail);
        const cap = this.numOrZero(this.defaults.cap);
        const ded = this.numOrZero(row.dedOverride !== '' && row.dedOverride != null ? row.dedOverride : this.defaults.ded);
        const coverage = Math.max(0, Math.min(cap, retail) - ded);
        const custPre = Math.max(0, retail - coverage) + this.numOrZero(row.supR);
        const taxPercent = this.numOrZero(row.taxPercent);
        const custTax = custPre * (1 + taxPercent / 100);
        const pl = custPre - wsTotal;
        const retailTotal = retail + this.numOrZero(row.supR);
        return {
            labour: this.round2(labour),
            wsTotal: this.round2(wsTotal),
            coverage: this.round2(coverage),
            custPre: this.round2(custPre),
            custTax: this.round2(custTax),
            pl: this.round2(pl),
            retailTotal: this.round2(retailTotal)
        };
    }

    recalcAll() {
        const withResults = this.rows.map((row) => ({ ...row, result: this.calcRow(row) }));
        let bestIdx = -1;
        let bestPl = -Infinity;
        withResults.forEach((row, idx) => {
            if (row.result.pl > bestPl) {
                bestPl = row.result.pl;
                bestIdx = idx;
            }
        });
        this.rows = withResults.map((row, idx) => {
            const isBest = idx === bestIdx;
            const profit = row.result.pl >= 0;
            const cellBg = isBest ? BEST_BG : WHITE_BG;
            const accent = row.isUse ? ACCENT : 'transparent';
            return {
                ...row,
                isBest,
                headerStyle: `background:${cellBg};border-top:4px solid ${accent};`,
                cellStyle: `background:${cellBg};`,
                plStyle: `background:${profit ? PROFIT_BG : LOSS_BG};`,
                plClass: profit ? 'v pl-val pos' : 'v pl-val neg'
            };
        });
    }

    numOrZero(v) {
        if (v === '' || v === null || v === undefined) return 0;
        const n = Number(v);
        return Number.isNaN(n) ? 0 : n;
    }
    numOrNull(v) {
        if (v === '' || v === null || v === undefined) return null;
        return Number(v);
    }
    round2(n) {
        return Math.round(n * 100) / 100;
    }

    get capDisplay() {
        return this.defaults.cap != null ? this.defaults.cap : 0;
    }
    get deductibleDisplay() {
        return this.defaults.ded != null ? this.defaults.ded : 0;
    }

    get gridStyle() {
        return `grid-template-columns: 190px repeat(${this.rows.length}, 240px);`;
    }

    get isSaveDisabled() {
        return this.isSaving || this.isLoading || this.rows.length === 0;
    }

    /**
     * One Apex call for the whole grid (Sep 22 perf fix), not one call per
     * row - see ClaimEstimateService.saveEstimates for why: this used to
     * await a separate round trip per row in a for loop, so N rows meant
     * N+ sequential network calls and Save All Estimates could take
     * several seconds. Building the full estimates[] payload client-side
     * and sending it in a single call fixes that at the root.
     */
    async handleSaveAll() {
        const missingName = this.rows.find((r) => !r.estimateName);
        if (missingName) {
            this.errorMessage = 'Every estimate needs a name.';
            return;
        }
        this.isSaving = true;
        this.errorMessage = null;
        try {
            const estimates = this.rows.map((row) => {
                const rec = {
                    Estimate_Name__c: row.estimateName,
                    Repair_Shop__c: row.repairShopId,
                    Source__c: row.source,
                    Part_Component__c: row.partComponent,
                    Job_Type__c: row.jobType,
                    Parts_Supplier__c: row.partsSupplierId,
                    Part_Code__c: row.partCode || null,
                    Stock_Number__c: row.stockNumber || null,
                    Condition__c: row.condition,
                    KMs__c: this.numOrNull(row.kms),
                    Insurance_Source__c: row.insuranceSource,
                    Insurance_Amount__c: this.numOrNull(row.ins),
                    Parts_Cost__c: this.numOrNull(row.partsCost),
                    Labour_Hours__c: this.numOrNull(row.hrs),
                    Labour_Rate__c: this.numOrNull(row.rate),
                    Shop_Supplies__c: this.numOrNull(row.supC),
                    Shop_Supplies_Retail__c: this.numOrNull(row.supR),
                    Retail_Price__c: this.numOrNull(row.retail),
                    Deductable__c: row.dedOverride !== '' ? this.numOrNull(row.dedOverride) : null,
                    Is_Selected__c: row.isUse
                };
                if (row.createdId) rec.Id = row.createdId;
                return rec;
            });

            await saveEstimates({
                claimId: this.claimId,
                estimates,
                deleteIds: this.pendingDeleteIds
            });
            this.pendingDeleteIds = [];
            this.close('saved');
        } catch (e) {
            this.errorMessage = (e && e.body && e.body.message) || 'Could not save the estimates.';
        } finally {
            this.isSaving = false;
        }
    }

    handleCancel() {
        this.close('cancelled');
    }
}