import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getManageEstimatesData from '@salesforce/apex/ClaimEstimateService.getManageEstimatesData';
import {
    groupDocumentLines,
    TYPE_PART,
    TYPE_LABOUR,
    TYPE_SUPPLIES,
    TYPE_WARRANTY
} from 'c/workOrderDocument';
/**
 * The JSON entry point, deliberately. Osama, 2026-10-08: passing the scenarios
 * as typed objects lost every field between here and Apex, which received a
 * ScenarioRow with all nulls and no child rows while this component had the
 * data in hand. The Aura layer that maps LWC objects onto a custom Apex type
 * does not reliably enumerate objects originating from a reactive proxy, and it
 * fails silently. Serialising here and deserialising in Apex removes that layer
 * from the path. See ClaimEstimateService.saveManageEstimatesFromJson.
 */
import saveManageEstimates from '@salesforce/apex/ClaimEstimateService.saveManageEstimatesFromJson';

const CAD = new Intl.NumberFormat('en-CA', { style: 'currency', currency: 'CAD' });
const NUM = new Intl.NumberFormat('en-CA');
const NA = 'n/a';
const MINUS = '−';

const PERCENT = 'Percent';
const AMOUNT = 'Amount';
const REIMBURSEMENT = 'Reimbursement Only';
const REPAIR = 'Repair';

const CONDITIONS = ['NEW', 'USED', 'RECONDITIONED', 'REMANUFACTURED', 'AFTERMARKET'];
const WARRANTY_SOURCES = ['Supplier', 'A-Protect', 'Garage'];
const COVERS = ['Parts and Labour', 'Parts Only'];

let seq = 0;
const tempId = (prefix) => `${prefix}-new-${++seq}`;
const isTemp = (id) => typeof id === 'string' && id.indexOf('-new-') > -1;

/**
 * Manage Estimates (TASK-047), rebuilt from Noelle's Repair Price Scenarios
 * Feedback 1.0. This is the main component: it composes the reused
 * ancillaryBenefits editor above the scenario cards and showOrderWorkSummary
 * below them, per requirement 20.
 *
 * Replaces the old Column Compare grid. The scenario cards sit in one
 * horizontal row that grows as estimates are added, exactly as the design
 * specifies.
 *
 * LIVE CALCULATION, then AUTHORITATIVE SAVE. Everything recalculates on every
 * keystroke here with a JavaScript mirror of
 * ClaimPricingService.calculateScenario, so the agent sees results without
 * waiting for a round trip. The saved figures always come back from Apex,
 * which recomputes them server side from the children, so the browser can
 * never write a number the markup and coverage rules would not produce.
 *
 * One known and accepted consequence: JavaScript uses binary floating point
 * and Apex uses exact Decimal, so a figure landing on an exact half cent can
 * differ by one cent between this live preview and the saved record. Apex is
 * correct. See ClaimPricingServiceTest for the worked case.
 *
 * Cap and deductible are DISPLAY ONLY (Osama's decision 4): they come from the
 * purchased contract through Application_Package__c, not from the agent, even
 * though the mockup draws them as inputs.
 */
export default class RepairPriceScenarios extends LightningElement {
    /**
     * Populated by the framework on a record page. On the standalone
     * Manage Estimates app page there is no record context, so the claim id
     * arrives as a URL parameter instead, see the wire below.
     */
    @api recordId;

    claimId;

    /**
     * The Manage Estimates app page is a lightning__AppPage, which by design
     * carries no recordId. claimEstimatesList navigates here with the claim
     * in state (c__claimId), which is how this screen gets full browser width
     * instead of the old lightning/modal that was running out of room
     * (Osama's decision 2).
     */
    @wire(CurrentPageReference)
    setPageReference(pageRef) {
        const fromUrl = pageRef && pageRef.state && pageRef.state.c__claimId;
        const resolved = this.recordId || fromUrl;
        if (resolved && resolved !== this.claimId) {
            this.claimId = resolved;
            this.loadData();
        }
    }

    @track scenarios = [];
    claimNumber;
    vehicle;
    cap = 0;
    deductible = 0;
    shops = [];
    suppliers = [];
    /** TASK-051. From Estimate__c.Reimbursement_Payment_Method__c, so the picklist is the one definition. */
    paymentMethodOptions = [];

    benefitsTotal = 0;
    benefitList = [];
    /** True once ancillaryBenefits has published; see applyData and handleBenefitsChange. */
    benefitsPublished = false;

    deletedEstimateIds = [];
    deletedChildIds = [];

    isLoading = true;
    isSaving = false;
    woHeader = {};

    // ───────────────────────────── loading ─────────────────────────────

    /**
     * Belt and braces alongside the wire: on a record page the @api recordId
     * and the CurrentPageReference wire can land in either order, so whichever
     * arrives first starts the load and the guard stops it happening twice.
     */
    connectedCallback() {
        if (this.recordId && !this.claimId) {
            this.claimId = this.recordId;
            this.loadData();
        }
    }

    async loadData() {
        if (!this.claimId) {
            return;
        }
        this.isLoading = true;
        try {
            this.applyData(await getManageEstimatesData({ claimId: this.claimId }));
        } catch (error) {
            this.showError('Could Not Load Manage Estimates', error);
        } finally {
            this.isLoading = false;
        }
    }

    applyData(data) {
        this.claimNumber = data.claimNumber;
        this.vehicle = data.vehicle;
        this.cap = Number(data.cap) || 0;
        this.deductible = Number(data.deductible) || 0;
        this.shops = data.shops || [];
        this.suppliers = data.suppliers || [];
        this.paymentMethodOptions = data.paymentMethodOptions || [];
        this.deletedEstimateIds = [];
        this.deletedChildIds = [];
        this.scenarios = (data.scenarios || []).map((s) => this.toScenario(s));
        // Osama, 2026-10-09: benefits added were not reaching the A-Protect
        // Coverage section. seedBenefitsFrom keeps only benefits with a SAVED
        // usageAmount above zero, so running it after every save discarded a
        // benefit the agent had entered but not yet saved through the
        // ancillaryBenefits child's own Save button. The child went on showing
        // the typed amount while the summary quietly stopped counting it.
        //
        // Once the child has published, it is the live source of truth for
        // benefits for as long as this screen is open, so the server copy must
        // not overwrite it. On a genuine first load nothing has published yet
        // and the saved benefits seed the cards as before.
        if (!this.benefitsPublished) {
            this.seedBenefitsFrom(data.benefits || []);
        }
        // TASK-050. The work order header is READ from the claim now, not typed
        // into the preview by hand. Every value is an existing field, including
        // the two created for this: Claim__c.Vehicle_Description__c composes
        // year/make/model/trim and Claim__c.Customer_Phone__c holds the
        // home-then-business precedence, so neither is derived here.
        this.woHeader = {
            applicationNumber: data.applicationNumber || '',
            customerName: data.customerName || '',
            customerAddress: data.customerAddress || '',
            customerPhone: data.customerPhone || '',
            customerEmail: data.customerEmail || '',
            vin: data.vin || '',
            odometer: data.odometer,
            odometerUnit: data.odometerUnit || ''
        };
    }

    /**
     * Seeds the approved benefit total from what is already saved, so the
     * cards are right on first paint. The reused ancillaryBenefits child then
     * keeps it live through its benefitschange event.
     */
    seedBenefitsFrom(benefits) {
        const approved = benefits
            .filter((b) => Number(b.usageAmount) > 0)
            .map((b) => ({ name: b.benefitType, amount: Number(b.usageAmount) || 0 }));
        this.benefitList = approved;
        this.benefitsTotal = approved.reduce((a, b) => a + b.amount, 0);
    }

    toScenario(s) {
        return {
            id: s.id,
            name: s.name || '',
            repairShopId: s.repairShopId,
            repairShopName: s.repairShopName,
            network: s.network || 'In-Network',
            claimType: s.claimType || REPAIR,
            taxPercent: s.taxPercent,
            deductible: s.deductible,
            isSelected: !!s.isSelected,
            paymentMethod: s.paymentMethod || null,
            expectedPaymentDate: s.expectedPaymentDate || null,
            openPartId: (s.parts && s.parts.length) ? s.parts[0].id : null,
            parts: (s.parts || []).map((p) => ({ ...p })),
            labour: (s.labour || []).length ? s.labour.map((l) => ({ ...l })) : [this.blankLabour()],
            supplies: (s.supplies || []).map((x) => ({ ...x })),
            // savedBalanceId: the balance this line's countedAmount was saved
            // against, for reimbRoom. A new line has neither.
            reimbursements: (s.reimbursements || []).map((r) => ({ ...r, savedBalanceId: r.benefitBalanceId }))
        };
    }

    blankPart() {
        return {
            id: tempId('p'), name: '', partNumber: '', category: '', condition: '',
            supplierId: null, stockNumber: '', kms: null, qty: 1,
            unitWholesale: null, markupType: PERCENT, markupValue: null, coreCharge: null,
            warrantySource: '', includedWarranty: false, includedWarrantyCovers: COVERS[0],
            includedWarrantyMonths: null, includedWarrantyKm: null,
            extendedWarranty: false, extendedWarrantyMonths: null, extendedWarrantyKm: null,
            extendedWarrantyCost: null, extendedWarrantyMarkupType: PERCENT,
            extendedWarrantyMarkupValue: null, warrantyNotes: ''
        };
    }

    blankLabour() {
        return {
            id: tempId('l'), description: '', wholesaleHours: null, wholesaleRate: null,
            retailHours: null, retailRate: null, guideMitchell: null, guideAllData: null
        };
    }

    blankSupply() {
        return { id: tempId('s'), description: '', wholesaleCost: null, markupType: PERCENT, markupValue: null };
    }

    // ──────────────────── calculation (mirrors Apex) ────────────────────

    num(v) {
        const n = parseFloat(v);
        return Number.isFinite(n) ? n : 0;
    }

    /** ClaimPricingService.applyMarkup, same rule. */
    markup(base, type, value) {
        const b = this.num(base);
        const m = this.num(value);
        return type === AMOUNT ? b + m : b * (1 + m / 100);
    }

    /** ClaimPricingService.calculateScenario, line for line. */
    calc(s) {
        const isR = s.claimType === REIMBURSEMENT;

        let partsW = 0, partsR = 0, warrW = 0, warrR = 0, core = 0;
        let labW = 0, labR = 0, supW = 0, supR = 0, reimb = 0;

        if (!isR) {
            s.parts.forEach((p) => {
                const q = this.num(p.qty) || 1;
                partsW += q * this.num(p.unitWholesale);
                partsR += q * this.markup(p.unitWholesale, p.markupType, p.markupValue);
                core += q * this.num(p.coreCharge);
                if (p.extendedWarranty) {
                    warrW += this.num(p.extendedWarrantyCost);
                    warrR += this.markup(p.extendedWarrantyCost, p.extendedWarrantyMarkupType, p.extendedWarrantyMarkupValue);
                }
            });
            s.labour.forEach((l) => {
                labW += this.num(l.wholesaleHours) * this.num(l.wholesaleRate);
                labR += this.num(l.retailHours) * this.num(l.retailRate);
            });
            s.supplies.forEach((x) => {
                supW += this.num(x.wholesaleCost);
                supR += this.markup(x.wholesaleCost, x.markupType, x.markupValue);
            });
        } else {
            reimb = s.reimbursements.reduce((a, r) => a + this.approvedReceipt(s, r), 0);
        }

        const ded = isR ? 0 : (s.deductible != null ? this.num(s.deductible) : this.deductible);
        const ben = isR ? reimb : this.benefitsTotal;
        const t = this.num(this.taxFor(s)) / 100;

        const subW = partsW + warrW + labW + supW;
        const subR = partsR + warrR + labR + supR;
        const retailRepair = partsR + warrR + labR;
        const repairTax = retailRepair * t;
        const repairInc = retailRepair + repairTax;
        const covApplied = Math.max(0, Math.min(repairInc, this.cap) - ded);
        const overLimit = Math.max(0, repairInc - this.cap);
        const custRepair = repairInc - covApplied;
        const supTax = supR * t;
        const supInc = supR + supTax;
        const rawPay = custRepair + supInc - ben;
        const customerPays = Math.max(0, rawPay);
        const reimbursedToCustomer = Math.max(0, -rawPay);
        const pre = t === -1 ? 0 : customerPays / (1 + t);
        const custSub = pre - reimbursedToCustomer;
        const custTaxAmt = customerPays - pre;
        const claimCost = subW;
        const whTax = claimCost * t;
        const costInc = claimCost + whTax;
        const guides = [this.num(s.labour[0] && s.labour[0].guideMitchell), this.num(s.labour[0] && s.labour[0].guideAllData)].filter((x) => x > 0);
        const gmin = guides.length ? Math.min(...guides) : 0;
        const chargedHours = s.labour.reduce((a, l) => a + this.num(l.wholesaleHours), 0);

        return {
            isR, partsW, partsR, warrW, warrR, core, labW, labR, supW, supR,
            subW, subR, retailRepair, repairTax, repairInc, taxTotal: repairTax + supTax,
            supTax, supInc, covApplied, overLimit, customerPays, custSub, custTaxAmt,
            reimbursedToCustomer, claimCost, whTax, costInc, benefits: ben,
            pnl: custSub - claimCost,
            pnlInclTax: customerPays - reimbursedToCustomer - costInc,
            apLoss: claimCost - custSub,
            fullyCovered: !isR && retailRepair > 0 && overLimit <= 0,
            gmin, chargedHours, guideFlag: gmin > 0 && chargedHours > gmin,
            reimb
        };
    }

    taxFor(s) {
        if (s.taxPercent != null && s.taxPercent !== '') {
            return s.taxPercent;
        }
        const shop = this.shops.find((x) => x.id === s.repairShopId);
        return shop ? shop.taxPercent : 0;
    }

    /** rLine from the design: a receipt is approved only up to what the term has left. */
    approvedReceipt(s, r) {
        return Math.max(0, Math.min(this.num(r.receiptAmount), this.reimbRoom(s, r.benefitBalanceId)));
    }

    /**
     * TASK-051. Live mirror of ClaimEstimateService.getApprovedReimbursements,
     * which is the rule Apex saves: the room on a balance for THIS scenario is
     * Remaining__c plus this scenario's own saved draws on it that Remaining__c
     * already has subtracted (countedAmount, set while the scenario is marked
     * Use). It used availableToUse, which adds back the CLAIM-LEVEL ancillary
     * draw instead, so on a saved, selected scenario its own receipts were
     * subtracted twice and Left on term read 260 and 30 where the term really
     * had 280 and 115 left (CL ID - 00054, Osama, 2026-10-13).
     *
     * countedAmount belongs to the balance the line was SAVED against
     * (savedBalanceId), so it is only added back for that balance.
     */
    reimbRoom(s, balanceId) {
        const bal = this.benefitBalances.find((b) => b.balanceId === balanceId);
        if (!bal) return Infinity;
        const own = s.reimbursements
            .filter((x) => x.savedBalanceId === balanceId)
            .reduce((a, x) => a + this.num(x.countedAmount), 0);
        return Math.max(0, this.num(bal.remaining) + own);
    }

    benefitBalances = [];

    // ───────────────────────── view model ─────────────────────────

    get cards() {
        const calcs = this.scenarios.map((s) => this.calc(s));

        let best = -1;
        calcs.forEach((c, i) => {
            if (c.subW <= 0) return;
            if (best < 0) { best = i; return; }
            const b = calcs[best];
            if (c.apLoss < b.apLoss - 0.005 || (Math.abs(c.apLoss - b.apLoss) <= 0.005 && c.customerPays < b.customerPays)) {
                best = i;
            }
        });
        const bestLoss = best >= 0 ? calcs[best].apLoss : 0;

        return this.scenarios.map((s, i) => {
            const c = calcs[i];
            const shop = this.shops.find((x) => x.id === s.repairShopId);
            const isBest = i === best;
            return {
                id: s.id,
                name: s.name || 'Untitled estimate',
                nameValue: s.name,
                cardClass: isBest ? 'rp-card rp-card-best' : 'rp-card',
                isBest,
                showDelta: !isBest && best >= 0 && c.subW > 0,
                deltaText: `${this.money(Math.max(0, c.apLoss - bestLoss))} worse than best`,
                isSelected: s.isSelected,
                isRepair: !c.isR,
                isReimbursement: c.isR,
                claimType: s.claimType,
                claimTypeOptions: [
                    { label: 'Repair', value: REPAIR },
                    { label: 'Reimbursement only (no repair)', value: REIMBURSEMENT }
                ],
                isCovered: c.fullyCovered,
                isOver: !c.isR && c.retailRepair > 0 && c.overLimit > 0,
                overPill: `Over limit ${this.money(c.overLimit)}`,

                repairShopId: s.repairShopId,
                shopOptions: this.shopOptions,
                shopInfo: this.shopInfo(shop, s),
                network: s.network,
                // Segmented toggles, not dropdowns: Osama pointed out on
                // 2026-10-07 that the design uses a two-button control here
                // and for Claim type, and I had built both as comboboxes.
                netInClass: this.segClass(s.network !== 'Out-of-Network'),
                netOutClass: this.segClass(s.network === 'Out-of-Network'),
                isNetIn: String(s.network !== 'Out-of-Network'),
                isNetOut: String(s.network === 'Out-of-Network'),
                ctRepairClass: this.segClass(s.claimType !== REIMBURSEMENT),
                ctReimbClass: this.segClass(s.claimType === REIMBURSEMENT),
                isCtRepair: String(s.claimType !== REIMBURSEMENT),
                isCtReimb: String(s.claimType === REIMBURSEMENT),
                taxPercent: this.taxFor(s),

                partsTitle: `Parts (${s.parts.length})`,
                partsW: this.money(c.partsW),
                partsR: this.money(c.partsR),
                parts: s.parts.map((p) => this.partVm(s, p)),

                labour: s.labour.map((l) => this.labourVm(l)),
                labourW: this.money(c.labW),
                labourR: this.money(c.labR),
                labourDiff: this.signed(c.labR - c.labW),
                labourDiffClass: c.labR - c.labW < 0 ? 'rp-neg' : '',
                guideFlag: c.guideFlag,
                guideText: `Charged ${c.chargedHours} h is above the lowest guide time (${c.gmin} h).`,
                rateHint: this.rateHint(shop, s),
                showRateHint: !!this.rateHint(shop, s),

                supTitle: `Shop Supplies (${s.supplies.length})`,
                supW: this.money(c.supW),
                supR: this.money(c.supR),
                supplies: s.supplies.map((x) => this.supplyVm(x)),

                reimbTitle: `Reimbursement (${s.reimbursements.length})`,
                reimbTotal: `${this.money(c.reimb)} approved`,
                reimbursements: s.reimbursements.map((r) => this.reimbVm(s, r)),
                benefitOptions: this.benefitOptions,
                paymentMethod: s.paymentMethod,
                paymentMethodOptions: this.paymentMethodOptions,
                expectedPaymentDate: s.expectedPaymentDate,

                rows: this.summaryRows(s, c),
                fcRows: this.fullyCoveredRows(c),
                customerPays: this.money(c.customerPays),
                reimbursedOut: this.money(c.reimbursedToCustomer),
                fcTitle: `Fully covered: the repair is within the ${this.money(this.cap)} claim limit`,

                pnlClass: c.pnl < 0 ? 'rp-pnl' : 'rp-pnl rp-pnl-profit',
                pnlTitle: c.pnl < 0 ? 'A-Protect LOSS on this claim' : 'A-Protect PROFIT on this claim',
                pnlInclTax: this.signed(c.pnlInclTax),
                pnlInclTaxClass: c.pnlInclTax >= 0 ? 'rp-pos' : '',
                pnlInclTaxSub: c.isR
                    ? `${this.money(c.benefits)} reimbursed, no tax recovered`
                    : `${this.money(c.customerPays)} customer pays · ${this.money(c.costInc)} cost`,
                pnlPreTax: this.signed(c.pnl),
                pnlPreTaxClass: c.pnl >= 0 ? 'rp-pos' : '',
                pnlPreTaxSub: c.isR
                    ? `${this.money(c.benefits)} reimbursed to customer`
                    : `${this.money(c.custSub)} collected · ${this.money(c.claimCost)} cost`
            };
        });
    }

    get shopOptions() {
        return this.shops.map((s) => ({ label: s.name, value: s.id }));
    }

    get benefitOptions() {
        return this.benefitBalances.map((b) => ({ label: b.benefitType, value: b.balanceId }));
    }

    shopInfo(shop, s) {
        if (!shop) {
            return s.repairShopId ? 'Not in the network list, treated as out-of-network' : 'Pick a network shop from the list.';
        }
        const bits = [];
        if (shop.city) bits.push(shop.city);
        if (shop.region) bits.push(shop.region);
        const where = bits.join(' · ');
        const rate = shop.postedRate ? `${this.money(shop.postedRate)}/h` : 'not listed';
        const pays = shop.paysBy || 'not listed';
        return `${where ? where + ' · ' : ''}${shop.address || NA}`
             + `${shop.phone ? ' · ' + shop.phone : ''}`
             + ` · Posted rate: ${rate} · Pays by: ${pays}`;
    }

    rateHint(shop, s) {
        if (!shop || !shop.postedRate) return '';
        const current = this.num(s.labour[0] && s.labour[0].wholesaleRate);
        return current === this.num(shop.postedRate)
            ? `Matches network rate ${this.money(shop.postedRate)}/h`
            : `Network posted rate ${this.money(shop.postedRate)}/h`;
    }

    partVm(s, p) {
        const q = this.num(p.qty) || 1;
        const w = this.num(p.unitWholesale);
        const unitRetail = this.markup(p.unitWholesale, p.markupType, p.markupValue);
        const extRetail = this.markup(p.extendedWarrantyCost, p.extendedWarrantyMarkupType, p.extendedWarrantyMarkupValue);
        const bits = [p.name || 'New part'];
        if (p.condition) bits.push(p.condition);
        if (p.includedWarranty) bits.push((p.includedWarrantyCovers === 'Parts Only' ? 'Parts' : 'P&L') + ' warranty');
        if (p.extendedWarranty) bits.push('+Ext.');
        return {
            id: p.id,
            open: s.openPartId === p.id,
            partClass: s.openPartId === p.id ? 'rp-part rp-part-open' : 'rp-part',
            summary: bits.join(' · '),
            lineText: `${q} × ${this.money(w)}`,
            name: p.name, partNumber: p.partNumber, category: p.category,
            condition: p.condition, conditionOptions: CONDITIONS.map((v) => ({ label: v, value: v })),
            supplierId: p.supplierId, supplierOptions: this.suppliers.map((x) => ({ label: x.name, value: x.id })),
            stockNumber: p.stockNumber, kms: p.kms, qty: p.qty,
            unitWholesale: p.unitWholesale,
            markupValue: p.markupValue,
            isPercent: p.markupType !== AMOUNT,
            isAmount: p.markupType === AMOUNT,
            pctClass: p.markupType !== AMOUNT ? 'rp-segb rp-segb-on' : 'rp-segb',
            dolClass: p.markupType === AMOUNT ? 'rp-segb rp-segb-on' : 'rp-segb',
            unitRetailText: w > 0 ? this.money(unitRetail) : NA,
            markupText: w > 0 ? `+${this.money((unitRetail - w) * q)} (${Math.round((unitRetail - w) / w * 1000) / 10}%)` : '',
            coreCharge: p.coreCharge,
            warrantySource: p.warrantySource,
            srcSupplierClass: this.segClass(p.warrantySource === 'Supplier'),
            srcAProtectClass: this.segClass(p.warrantySource === 'A-Protect'),
            srcGarageClass: this.segClass(p.warrantySource === 'Garage'),
            isSrcSupplier: String(p.warrantySource === 'Supplier'),
            isSrcAProtect: String(p.warrantySource === 'A-Protect'),
            isSrcGarage: String(p.warrantySource === 'Garage'),
            includedWarranty: p.includedWarranty,
            includedWarrantyCovers: p.includedWarrantyCovers,
            coversPlClass: this.segClass(p.includedWarrantyCovers !== 'Parts Only'),
            coversPClass: this.segClass(p.includedWarrantyCovers === 'Parts Only'),
            isCoversPl: String(p.includedWarrantyCovers !== 'Parts Only'),
            isCoversP: String(p.includedWarrantyCovers === 'Parts Only'),
            includedWarrantyMonths: p.includedWarrantyMonths,
            includedWarrantyKm: p.includedWarrantyKm,
            includedExpiry: this.expiry(p, true),
            extendedWarranty: p.extendedWarranty,
            extendedWarrantyMonths: p.extendedWarrantyMonths,
            extendedWarrantyKm: p.extendedWarrantyKm,
            extendedExpiry: this.expiry(p, false),
            extendedWarrantyCost: p.extendedWarrantyCost,
            extendedWarrantyMarkupValue: p.extendedWarrantyMarkupValue,
            extPctClass: p.extendedWarrantyMarkupType !== AMOUNT ? 'rp-segb rp-segb-on' : 'rp-segb',
            extDolClass: p.extendedWarrantyMarkupType === AMOUNT ? 'rp-segb rp-segb-on' : 'rp-segb',
            extendedRetailText: this.num(p.extendedWarrantyCost) > 0 ? this.money(extRetail) : NA,
            extendedMarkupText: this.num(p.extendedWarrantyCost) > 0
                ? `+${this.money(extRetail - this.num(p.extendedWarrantyCost))} markup` : '',
            warrantyNotes: p.warrantyNotes,
            warrantySummary: this.warrantySummary(p)
        };
    }

    warrantySummary(p) {
        const bits = [];
        if (p.includedWarranty) {
            bits.push((p.includedWarrantyCovers === 'Parts Only' ? 'Parts ' : 'P&L ') + this.term(p.includedWarrantyMonths, p.includedWarrantyKm));
        }
        if (p.extendedWarranty) {
            bits.push(`Ext. ${this.money(this.num(p.extendedWarrantyCost))}`);
        }
        return bits.length ? bits.join(' · ') : 'None';
    }

    term(months, km) {
        const bits = [];
        if (this.num(months) > 0) bits.push(`${this.num(months)} mo`);
        if (this.num(km) > 0) bits.push(`${NUM.format(this.num(km))} km`);
        return bits.join(' / ');
    }

    expiry(p, included) {
        const km = this.num(included ? p.includedWarrantyKm : p.extendedWarrantyKm);
        const months = this.num(included ? p.includedWarrantyMonths : p.extendedWarrantyMonths);
        const base = this.num(p.kms);
        const bits = [];
        if (km > 0) bits.push(`${NUM.format(base + km)} km`);
        if (months > 0) {
            const d = new Date();
            d.setMonth(d.getMonth() + months);
            bits.push(d.toLocaleDateString('en-CA', { year: 'numeric', month: 'short', day: 'numeric' }));
        }
        return bits.length ? bits.join(' or ') : NA;
    }

    labourVm(l) {
        const w = this.num(l.wholesaleHours) * this.num(l.wholesaleRate);
        const r = this.num(l.retailHours) * this.num(l.retailRate);
        return {
            id: l.id, description: l.description,
            wholesaleHours: l.wholesaleHours, wholesaleRate: l.wholesaleRate,
            retailHours: l.retailHours, retailRate: l.retailRate,
            guideMitchell: l.guideMitchell, guideAllData: l.guideAllData,
            wholesaleTotal: this.money(w), retailTotal: this.money(r),
            hoursDiff: `${this.num(l.retailHours) - this.num(l.wholesaleHours) < 0 ? MINUS : '+'}${Math.abs(this.num(l.retailHours) - this.num(l.wholesaleHours))} h`,
            rateDiff: `${this.signed(this.num(l.retailRate) - this.num(l.wholesaleRate))}/h`
        };
    }

    supplyVm(x) {
        const w = this.num(x.wholesaleCost);
        const r = this.markup(x.wholesaleCost, x.markupType, x.markupValue);
        return {
            id: x.id, description: x.description, wholesaleCost: x.wholesaleCost,
            markupValue: x.markupValue,
            pctClass: x.markupType !== AMOUNT ? 'rp-segb rp-segb-on' : 'rp-segb',
            dolClass: x.markupType === AMOUNT ? 'rp-segb rp-segb-on' : 'rp-segb',
            retailText: w > 0 ? this.money(r) : NA,
            markupText: w > 0 ? `+${this.money(r - w)} markup` : ''
        };
    }

    reimbVm(s, r) {
        const bal = this.benefitBalances.find((b) => b.balanceId === r.benefitBalanceId);
        const remaining = bal ? this.reimbRoom(s, r.benefitBalanceId) : 0;
        const approved = this.approvedReceipt(s, r);
        const over = this.num(r.receiptAmount) - approved;
        return {
            id: r.id, benefitBalanceId: r.benefitBalanceId, receiptAmount: r.receiptAmount,
            info: bal
                ? `Remaining on term: ${this.money(remaining)} · Approved ${this.money(approved)}`
                  + (over > 0 ? ` (${this.money(over)} over cap, not reimbursed)` : '')
                : `Approved ${this.money(approved)}`
        };
    }

    // ───────────────────────── summary table ─────────────────────────

    summaryRows(s, c) {
        const row = (key, label, sub, w, d, r, cls, dCls) => ({
            key, label, sub: sub || '', w, d: d || '', r, isSection: false,
            rowClass: `rp-srow ${cls || ''}`, dClass: `rp-cd ${dCls || ''}`
        });
        const section = (key, label) => ({ key, label, isSection: true });

        if (c.isR) {
            const lines = s.reimbursements
                .map((x, i) => {
                    const bal = this.benefitBalances.find((b) => b.balanceId === x.benefitBalanceId);
                    return { name: bal ? bal.benefitType : 'Benefit', amount: this.approvedReceipt(s, x), i };
                })
                .filter((x) => x.amount > 0);
            return [
                section('sec-r', 'Reimbursement (no repair, no deductible, no shop supplies)'),
                ...lines.map((x) => row(`r${x.i}`, x.name, '', this.money(x.amount), '', `${MINUS}${this.money(x.amount)}`)),
                ...(lines.length ? [] : [row('r-none', 'No approved reimbursements', '', NA, '', NA)]),
                row('r-tot', 'Total reimbursed', 'cost / P&L / customer receives',
                    this.money(c.reimb), `${MINUS}${this.money(c.reimb)}`, this.money(c.reimbursedToCustomer),
                    'rp-srow-big', 'rp-neg'),
                row('r-pay', 'Customer pays', '', NA, '', this.money(0))
            ];
        }

        const coverageSub = c.fullyCovered
            ? `fully covered within ${this.money(this.cap)} limit · ${this.money(this.deductible)} deductible`
            : `${this.money(this.cap)} cap · ${this.money(this.deductible)} deductible · repair ${this.money(c.overLimit)} over cap`;
        const benefitNames = this.benefitList.map((b) => b.name).join(', ') || 'none';
        const coreNames = s.parts.filter((p) => this.num(p.coreCharge) > 0).map((p) => p.name || 'part').join(', ');

        return [
            section('sec-1', 'Repair lines'),
            row('parts', 'Parts', '', this.money(c.partsW), this.signed(c.partsR - c.partsW), this.money(c.partsR)),
            ...(c.core > 0 ? [row('core', 'Core charge', `${coreNames} · no markup, not in totals or P&L`,
                this.money(c.core), 'no markup', this.money(c.core), 'rp-srow-core')] : []),
            row('warr', 'Extended warranty', '', this.money(c.warrW), this.signed(c.warrR - c.warrW), this.money(c.warrR)),
            row('lab', 'Labour', '', this.money(c.labW), this.signed(c.labR - c.labW), this.money(c.labR)),
            row('sup', 'Shop supplies', 'not covered', this.money(c.supW), this.signed(c.supR - c.supW), this.money(c.supR)),
            row('sub', 'Subtotal (pre-tax)', '', this.money(c.subW), this.signed(c.subR - c.subW), this.money(c.subR), 'rp-srow-sub'),
            section('sec-2', 'Tax, coverage and benefits'),
            row('tax', `Tax (${this.num(this.taxFor(s))}%)`, 'paid / charged',
                `+${this.money(c.whTax)}`, this.signed(c.taxTotal - c.whTax), `+${this.money(c.taxTotal)}`),
            row('tot', 'Total incl. tax', '', this.money(c.subW + c.whTax),
                this.signed(c.subR + c.taxTotal - c.subW - c.whTax), this.money(c.subR + c.taxTotal), 'rp-srow-sub'),
            row('cov', 'Less coverage', coverageSub, NA, '', `${MINUS}${this.money(c.covApplied)}`),
            row('ben', 'Ancillary benefits', `${benefitNames} · credited to customer`, NA, '', `${MINUS}${this.money(c.benefits)}`),
            row('big1', 'Totals (incl. tax)', 'cost / P&L / customer pays',
                this.money(c.costInc), this.signed(c.pnlInclTax), this.money(c.customerPays),
                'rp-srow-big', c.pnlInclTax < 0 ? 'rp-neg' : 'rp-pos'),
            row('lesstax', 'Less tax', "tax recovered on purchases / tax inside the customer's payment",
                `${MINUS}${this.money(c.whTax)}`, '', `${MINUS}${this.money(c.custTaxAmt)}`),
            row('big2', 'Net (pre-tax)', 'cost / P&L / customer pays pre-tax',
                this.money(c.claimCost), this.signed(c.pnl), this.money(c.custSub),
                'rp-srow-big', c.pnl < 0 ? 'rp-neg' : 'rp-pos')
        ];
    }

    fullyCoveredRows(c) {
        return [
            { key: 'ded', label: 'Deductible', value: this.money(this.deductible) },
            { key: 'sup', label: 'Shop supplies', value: this.money(c.supR) },
            { key: 'suptax', label: `HST on shop supplies`, value: this.money(c.supTax) },
            ...this.benefitList.map((b, i) => ({
                key: `b${i}`, label: `Less ${b.name} (ancillary)`, value: `${MINUS}${this.money(b.amount)}`
            }))
        ];
    }

    // ───────────────────── work order summary feed ─────────────────────

    get selectedScenario() {
        return this.scenarios.find((s) => s.isSelected) || null;
    }

    get workOrderSummary() {
        const s = this.selectedScenario;
        if (!s) return null;
        const c = this.calc(s);

        // The grouping rule is NOT written here. It lives once in Apex, in
        // WorkOrderDocumentLines, and is mirrored in c/workOrderDocument for
        // this preview, which recalculates on every keystroke against unsaved
        // input and so cannot call Apex. Osama chose that on 2026-10-09 after
        // this preview and the work order PDF disagreed about how many rows a
        // job had, because each had its own copy of the grouping. All this
        // does now is put the scenario into the rule's input shape.
        let lines = [];
        if (!c.isR) {
            const source = [];
            s.parts.forEach((p) => {
                source.push({
                    lineType: TYPE_PART,
                    description: p.name,
                    amount: this.markup(this.num(p.unitWholesale) * (this.num(p.qty) || 1),
                        p.markupType, p.markupValue)
                });
            });
            // One labour entry carrying the whole labour retail: the rule only
            // needs parts and labour to total correctly and only parts to name
            // themselves, so splitting labour per line would change nothing.
            source.push({ lineType: TYPE_LABOUR, description: 'Labour', amount: c.labR });
            s.parts.filter((p) => p.extendedWarranty && this.num(p.extendedWarrantyCost) > 0).forEach((p) => {
                const t = this.term(p.extendedWarrantyMonths, p.extendedWarrantyKm);
                source.push({
                    lineType: TYPE_WARRANTY,
                    description: `Extended Warranty: ${p.name || 'part'}${t ? ` (${t})` : ''}`,
                    amount: this.markup(p.extendedWarrantyCost, p.extendedWarrantyMarkupType, p.extendedWarrantyMarkupValue)
                });
            });
            source.push({ lineType: TYPE_SUPPLIES, description: 'Shop supplies', amount: c.supR });
            lines = groupDocumentLines(source);
        }
        const subTotal = lines.reduce((a, l) => a + l.amount, 0);
        const taxPercent = this.num(this.taxFor(s));
        const tax = subTotal * taxPercent / 100;

        // TASK-051. The reimbursement notice from Feedback 1.0 (rLine/openRN):
        // receipts submitted, approved, and what the term has left after this
        // approval, which is reimbRoom less the approval, the same rule Apex
        // prints on the work order PDF. A receipt entirely over the cap still
        // shows, with Approved $0.00.
        const reimbRows = c.isR
            ? s.reimbursements
                  .filter((r) => this.num(r.receiptAmount) > 0)
                  .map((r) => {
                      const bal = this.benefitBalances.find((b) => b.balanceId === r.benefitBalanceId);
                      const receipts = this.num(r.receiptAmount);
                      const approved = this.approvedReceipt(s, r);
                      return {
                          name: bal ? bal.benefitType : 'Benefit',
                          receipts,
                          amount: approved,
                          leftOnTerm: bal ? Math.max(0, this.reimbRoom(s, r.benefitBalanceId) - approved) : null,
                          over: Math.max(0, receipts - approved)
                      };
                  })
            : [];

        return {
            isReimbursement: c.isR,
            lines,
            subTotal,
            taxPercent,
            tax,
            totalDue: subTotal + tax,
            coverageApplied: c.covApplied,
            benefits: c.isR ? reimbRows : this.benefitList,
            benefitsTotal: c.benefits,
            receiptsTotal: reimbRows.reduce((a, r) => a + r.receipts, 0),
            customerPays: c.customerPays,
            reimbursedToCustomer: c.reimbursedToCustomer,
            fullyCovered: c.fullyCovered,
            paymentMethod: c.isR ? s.paymentMethod : null,
            expectedPaymentDate: c.isR ? s.expectedPaymentDate : null
        };
    }

    get selectedScenarioName() {
        const s = this.selectedScenario;
        return s ? s.name : '';
    }

    get selectedShopName() {
        const s = this.selectedScenario;
        if (!s) return '';
        const shop = this.shops.find((x) => x.id === s.repairShopId);
        return shop ? shop.name : '';
    }

    get selectedShopContact() {
        const s = this.selectedScenario;
        if (!s) return '';
        const shop = this.shops.find((x) => x.id === s.repairShopId);
        if (!shop) return '';
        return `${shop.address || ''}${shop.phone ? ' · ' + shop.phone : ''}`;
    }

    // ───────────────────────────── events ─────────────────────────────

    /**
     * The reused ancillaryBenefits child reports its approved total here, so
     * every scenario recalculates the moment a benefit changes. That is the
     * design's "set benefits once, they flow into every scenario".
     */
    handleBenefitsChange(event) {
        const detail = event.detail || {};
        this.benefitsTotal = Number(detail.total) || 0;
        this.benefitList = detail.benefits || [];
        this.benefitBalances = detail.balances || this.benefitBalances;
        // From here on the child owns the benefit figures for this screen, so
        // a reload after saving must not overwrite them with the saved-only
        // copy. See the guard in applyData.
        this.benefitsPublished = true;
    }

    /**
     * currentTarget first, then target. A native button with a nested span
     * reports the span as event.target, which carries no data attributes, so
     * reading target alone silently loses the row being edited. The base
     * components report themselves either way, so this is safe for both.
     */
    dataFrom(event) {
        const ct = event.currentTarget;
        if (ct && ct.dataset && ct.dataset.scenario) {
            return ct.dataset;
        }
        return (event.target && event.target.dataset) || {};
    }

    scenarioFrom(event) {
        return this.scenarios.find((s) => s.id === this.dataFrom(event).scenario);
    }

    handleScenarioField(event) {
        const s = this.scenarioFrom(event);
        if (!s) return;
        const field = this.dataFrom(event).field;
        s[field] = event.detail ? event.detail.value : event.target.value;
        if (field === 'repairShopId') {
            const shop = this.shops.find((x) => x.id === s.repairShopId);
            s.network = shop ? 'In-Network' : 'Out-of-Network';
            if (shop && shop.taxPercent != null) s.taxPercent = shop.taxPercent;
        }
        if (field === 'claimType' && s.claimType === REIMBURSEMENT && !s.reimbursements.length) {
            const first = this.benefitBalances[0];
            if (first) {
                s.reimbursements = [{ id: tempId('r'), benefitBalanceId: first.balanceId, receiptAmount: null }];
            }
        }
        this.scenarios = [...this.scenarios];
    }

    handleChildField(event) {
        const s = this.scenarioFrom(event);
        if (!s) return;
        const { collection, child, field } = this.dataFrom(event);
        const row = s[collection].find((x) => x.id === child);
        if (!row) return;
        row[field] = event.target.type === 'checkbox'
            ? event.target.checked
            : (event.detail ? event.detail.value : event.target.value);
        this.scenarios = [...this.scenarios];
    }

    /** Shared by every segmented toggle on a child row: markup type, warranty source, covers. */
    handleMarkupType(event) {
        const s = this.scenarioFrom(event);
        if (!s) return;
        const { collection, child, field, value } = this.dataFrom(event);
        const row = s[collection].find((x) => x.id === child);
        if (!row) return;
        row[field] = value;
        this.scenarios = [...this.scenarios];
    }

    /**
     * Segmented toggles at scenario level: Network and Claim type. A button
     * click carries no value the way a combobox change does, so the chosen
     * value rides on data-value instead.
     */
    handleScenarioSegment(event) {
        const s = this.scenarioFrom(event);
        if (!s) return;
        const { field, value } = this.dataFrom(event);
        s[field] = value;
        // Same courtesy the combobox path gave: switching to Reimbursement
        // Only seeds a first line so the section is not empty.
        if (field === 'claimType' && value === REIMBURSEMENT && !s.reimbursements.length) {
            const first = this.benefitBalances[0];
            if (first) {
                s.reimbursements = [{ id: tempId('r'), benefitBalanceId: first.balanceId, receiptAmount: null }];
            }
        }
        this.scenarios = [...this.scenarios];
    }

    segClass(isOn) {
        return isOn ? 'rp-segb rp-segb-on' : 'rp-segb';
    }

    handleTogglePart(event) {
        const s = this.scenarioFrom(event);
        if (!s) return;
        const id = this.dataFrom(event).child;
        s.openPartId = s.openPartId === id ? null : id;
        this.scenarios = [...this.scenarios];
    }

    handleUseScenario(event) {
        const id = this.dataFrom(event).scenario;
        this.scenarios = this.scenarios.map((s) => ({ ...s, isSelected: s.id === id }));
    }

    handleUseNetworkRate(event) {
        const s = this.scenarioFrom(event);
        if (!s) return;
        const shop = this.shops.find((x) => x.id === s.repairShopId);
        if (shop && shop.postedRate != null && s.labour.length) {
            s.labour[0].wholesaleRate = shop.postedRate;
            this.scenarios = [...this.scenarios];
        }
    }

    handleAddPart(event) {
        const s = this.scenarioFrom(event);
        if (!s) return;
        const p = this.blankPart();
        s.parts = [...s.parts, p];
        s.openPartId = p.id;
        this.scenarios = [...this.scenarios];
    }

    handleAddSupply(event) {
        const s = this.scenarioFrom(event);
        if (!s) return;
        s.supplies = [...s.supplies, this.blankSupply()];
        this.scenarios = [...this.scenarios];
    }

    handleAddReimbursement(event) {
        const s = this.scenarioFrom(event);
        if (!s) return;
        const first = this.benefitBalances[0];
        s.reimbursements = [...s.reimbursements,
            { id: tempId('r'), benefitBalanceId: first ? first.balanceId : null, receiptAmount: null }];
        this.scenarios = [...this.scenarios];
    }

    handleRemoveChild(event) {
        const s = this.scenarioFrom(event);
        if (!s) return;
        const { collection, child } = this.dataFrom(event);
        if (!isTemp(child)) {
            this.deletedChildIds = [...this.deletedChildIds, child];
        }
        s[collection] = s[collection].filter((x) => x.id !== child);
        this.scenarios = [...this.scenarios];
    }

    handleAddScenario() {
        const n = this.scenarios.length + 1;
        this.scenarios = [...this.scenarios, {
            id: tempId('e'),
            name: `Repair Shop ${n} - Option ${String.fromCharCode(64 + n)}`,
            repairShopId: null, repairShopName: '', network: 'In-Network',
            claimType: REPAIR, taxPercent: null, deductible: null, isSelected: false,
            paymentMethod: null, expectedPaymentDate: null,
            openPartId: null, parts: [], labour: [this.blankLabour()], supplies: [], reimbursements: []
        }];
    }

    handleRemoveScenario(event) {
        const id = this.dataFrom(event).scenario;
        if (!isTemp(id)) {
            this.deletedEstimateIds = [...this.deletedEstimateIds, id];
        }
        this.scenarios = this.scenarios.filter((s) => s.id !== id);
    }


    // ───────────────────────────── saving ─────────────────────────────

    /**
     * Mirrors ClaimEstimateService.isEmptyScenario. Network and claim type are
     * deliberately ignored: both are seeded with a default the moment a card is
     * added, so counting them would make every card look filled in. The
     * generated "Repair Shop 1 - Option A" name is a suggestion, not content,
     * so it does not count either.
     */
    isEmptyScenarioRow(s) {
        const placeholder = /^repair shop \d+ - option [a-z]$/i;
        const named = s.name && String(s.name).trim() && !placeholder.test(String(s.name).trim());
        if (named) return false;
        if (s.repairShopId || s.taxPercent != null || s.deductible != null) return false;
        if (s.parts.length || s.supplies.length || s.reimbursements.length) return false;
        return !s.labour.some((l) => (l.description && String(l.description).trim())
            || l.wholesaleHours != null || l.wholesaleRate != null
            || l.retailHours != null || l.retailRate != null);
    }

    async handleSave() {
        // Osama, 2026-10-07: an untouched card used to be sent and inserted as
        // a blank Estimate__c (E-0053, E-0056, E-0057 on CL ID - 00054). The
        // server refuses it now, but silence there would just look like a save
        // that did nothing, so say which cards were left out and why.
        const toSave = this.scenarios.filter((s) => !isTemp(s.id) || !this.isEmptyScenarioRow(s));
        const skipped = this.scenarios.length - toSave.length;
        // Removing every card and saving is how the agent clears estimates that
        // should not be there, so pending deletions have to reach Apex even
        // when nothing is left to save. saveManageEstimates runs its delete
        // blocks before the empty-scenarios early return, so it handles this.
        const hasDeletions = this.deletedEstimateIds.length > 0 || this.deletedChildIds.length > 0;
        if (!toSave.length && !hasDeletions) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Nothing To Save Yet',
                message: 'Pick a repair shop, or add a part or a labour line, before saving.',
                variant: 'warning'
            }));
            return;
        }
        this.isSaving = true;
        try {
            const payload = toSave.map((s) => ({
                id: isTemp(s.id) ? null : s.id,
                name: s.name,
                repairShopId: s.repairShopId,
                network: s.network,
                claimType: s.claimType,
                taxPercent: this.toNumberOrNull(s.taxPercent),
                deductible: this.toNumberOrNull(s.deductible),
                isSelected: s.isSelected,
                // TASK-051. Apex keeps these only on a Reimbursement Only
                // scenario. A cleared date input gives '', which Apex's JSON
                // Date parse refuses, so blank goes over as null.
                paymentMethod: s.paymentMethod || null,
                expectedPaymentDate: s.expectedPaymentDate || null,
                parts: s.parts.map((p) => ({
                    ...p,
                    id: isTemp(p.id) ? null : p.id,
                    qty: this.toNumberOrNull(p.qty),
                    kms: this.toNumberOrNull(p.kms),
                    unitWholesale: this.toNumberOrNull(p.unitWholesale),
                    markupValue: this.toNumberOrNull(p.markupValue),
                    coreCharge: this.toNumberOrNull(p.coreCharge),
                    includedWarrantyMonths: this.toNumberOrNull(p.includedWarrantyMonths),
                    includedWarrantyKm: this.toNumberOrNull(p.includedWarrantyKm),
                    extendedWarrantyMonths: this.toNumberOrNull(p.extendedWarrantyMonths),
                    extendedWarrantyKm: this.toNumberOrNull(p.extendedWarrantyKm),
                    extendedWarrantyCost: this.toNumberOrNull(p.extendedWarrantyCost),
                    extendedWarrantyMarkupValue: this.toNumberOrNull(p.extendedWarrantyMarkupValue)
                })),
                labour: s.labour.map((l) => ({
                    ...l,
                    id: isTemp(l.id) ? null : l.id,
                    wholesaleHours: this.toNumberOrNull(l.wholesaleHours),
                    wholesaleRate: this.toNumberOrNull(l.wholesaleRate),
                    retailHours: this.toNumberOrNull(l.retailHours),
                    retailRate: this.toNumberOrNull(l.retailRate),
                    guideMitchell: this.toNumberOrNull(l.guideMitchell),
                    guideAllData: this.toNumberOrNull(l.guideAllData)
                })),
                supplies: s.supplies.map((x) => ({
                    ...x,
                    id: isTemp(x.id) ? null : x.id,
                    wholesaleCost: this.toNumberOrNull(x.wholesaleCost),
                    markupValue: this.toNumberOrNull(x.markupValue)
                })),
                reimbursements: s.reimbursements.map((r) => ({
                    id: isTemp(r.id) ? null : r.id,
                    benefitBalanceId: r.benefitBalanceId,
                    benefitType: r.benefitType,
                    receiptAmount: this.toNumberOrNull(r.receiptAmount)
                }))
            }));

            const data = await saveManageEstimates({
                claimId: this.claimId,
                scenariosJson: JSON.stringify(payload),
                deletedEstimateIds: this.deletedEstimateIds,
                deletedChildIds: this.deletedChildIds
            });
            // applyData clears both delete lists, so read the count first.
            const removed = this.deletedEstimateIds.length;
            const refused = Number(data.skippedEmptyScenarios) || 0;
            this.applyData(data);
            const stored = toSave.length - refused;
            const parts = [`${stored} scenario(s) saved`];
            if (removed) parts.push(`${removed} removed`);
            if (skipped) parts.push(`${skipped} empty card(s) not sent`);
            // Apex refusing a card this screen was willing to send means the
            // payload did not arrive the way it left here. Report that rather
            // than claiming a successful save that stored nothing, which is
            // what made the original problem so hard to see.
            if (refused) parts.push(`${refused} refused by the server as empty`);
            this.dispatchEvent(new ShowToastEvent({
                title: stored > 0 ? 'Estimates Saved' : 'Nothing Was Saved',
                message: `${parts.join('. ')}.`,
                variant: stored > 0 ? 'success' : 'warning'
            }));
        } catch (error) {
            this.showError('Could Not Save Estimates', error, 'sticky');
        } finally {
            this.isSaving = false;
        }
    }

    toNumberOrNull(v) {
        if (v === '' || v == null) return null;
        const n = Number(v);
        return Number.isFinite(n) ? n : null;
    }

    // ───────────────────────────── helpers ────────────────────────────

    get hasScenarios() {
        return this.scenarios.length > 0;
    }

    get capDisplay() {
        return this.money(this.cap);
    }

    get deductibleDisplay() {
        return this.money(this.deductible);
    }

    get benefitsTotalDisplay() {
        return this.money(this.benefitsTotal);
    }

    get isBusy() {
        return this.isLoading || this.isSaving;
    }

    money(value) {
        const n = Number(value);
        return Number.isFinite(n) ? CAD.format(n) : NA;
    }

    signed(value) {
        const n = Number(value) || 0;
        return `${n < 0 ? MINUS : '+'}${CAD.format(Math.abs(n))}`;
    }

    showError(title, error, mode) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message: (error && error.body && error.body.message) || 'An unexpected error occurred.',
            variant: 'error',
            mode: mode || 'dismissable'
        }));
    }
}