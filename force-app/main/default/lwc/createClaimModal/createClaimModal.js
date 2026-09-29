import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getApplicationChainData from '@salesforce/apex/CreateClaimController.getApplicationChainData';
import createClaim from '@salesforce/apex/CreateClaimController.createClaim';

const ODOMETER_UNIT_OPTIONS = [
    { label: 'KM', value: 'KM' },
    { label: 'Miles', value: 'Miles' }
];

const NOT_PROVIDED = 'Not provided';

/**
 * "Create Claim" quick action screen on Application__c. Left rail is
 * read-only, auto-populated from the Application the button was clicked
 * from (CreateClaimController.getApplicationChainData). Right rail is the
 * same 5 "Claim Details" fields Osama split into their own tab on
 * Claim_Intake_Record_Page.
 *
 * Visual design (Sep 26) replicates the "Claim Intake — Edit Claim" design
 * reference (card-based left rail with key/value rows, top alert banners
 * for an invalid warranty/inactive coverage instead of inline badges,
 * teal-accented form fields) - see createClaimModal.css for the ported
 * color/spacing tokens. Deliberately keeps "Create Claim" wording
 * throughout rather than the reference's "Edit Claim"/"Save Changes" -
 * that reference predates Osama's explicit correction that this screen
 * only ever creates, never edits.
 *
 * Deliberately create-only, no edit mode: Osama tested this screen finding
 * an existing claim and silently switching into editing it, and was clear
 * this screen exists only to create new claims. Every click always inserts
 * a brand-new Claim__c, regardless of how many claims already exist for
 * the Application.
 *
 * Warranty_Validity__c / Coverage_Active__c are live JS mirrors of the real
 * Claim__c formulas (see their field descriptions for the canonical
 * formula text) - recomputed on every Current Odometer keystroke, same
 * "keep this in sync with the real formula" pattern as
 * ClaimPricingService.calculate() / repairPriceScenarios.js. Keep both in
 * sync if either formula ever changes. Coverage_Active__c reads the dealer
 * package chain (Dealer_Package_Term__c), not the master catalog - see
 * that field's own description for why.
 *
 * Built as a lightning/modal (not a direct quick-action target) so its
 * width can be controlled via .open({size: 'large', ...}) - the quick
 * action's own dialog width can't be widened from inside an LWC (that
 * chrome lives outside the component's shadow boundary), which is exactly
 * why every other sizeable modal in this codebase (repairPriceScenarios)
 * uses this same pattern. The actual quick-action target is the thin
 * createClaimAction launcher, which opens this component.
 */
export default class CreateClaimModal extends LightningModal {
    @api applicationId; // set directly by createClaimAction's .open({...}) call

    isLoading = true;
    isSaving = false;
    chainData = null; // ApplicationChainData - left rail + live-calc inputs

    form = {
        dateFiled: todayIso(),
        currentOdometer: null,
        currentOdometerUnit: 'KM',
        claimDescription: '',
        customerLocation: ''
    };

    odometerUnitOptions = ODOMETER_UNIT_OPTIONS;

    connectedCallback() {
        this.loadAll();
    }

    async loadAll() {
        this.isLoading = true;
        try {
            this.chainData = await getApplicationChainData({ applicationId: this.applicationId });
        } catch (error) {
            this.showError('Could Not Load Application Details', error);
        } finally {
            this.isLoading = false;
        }
    }

    // ---- Left rail (read-only, auto-populated) ----
    get left() {
        return this.chainData || {};
    }

    get dealershipRows() {
        return buildRows([
            ['Dealer Name', this.left.dealerName],
            ['Dealer Code', this.left.dealerCode],
            ['Dealer Address', this.left.dealerAddress],
            ['Dealer Phone', this.left.dealerPhone]
        ]);
    }

    get applicationRows() {
        return buildRows([
            ['Application', this.left.applicationName],
            ['Status', this.left.applicationStatus],
            ['Customer Name', this.left.customerName],
            ['Customer Address', this.left.customerAddress],
            ['Home Phone', this.left.customerHomePhone],
            ['Email', this.left.customerEmail]
        ]);
    }

    get vehicleDescription() {
        return [this.left.vehicleYear, this.left.vehicleMake, this.left.vehicleModel, this.left.vehicleTrim]
            .filter((part) => part)
            .join(' ');
    }

    get vehicleRows() {
        return buildRows([
            ['Vehicle', this.vehicleDescription],
            ['Year / Make', joinDot(this.left.vehicleYear, this.left.vehicleMake)],
            ['Model / Trim', joinDot(this.left.vehicleModel, this.left.vehicleTrim)],
            ['VIN', this.left.vehicleVin],
            ['Purchase Odometer', joinUnit(this.left.purchaseOdometer, this.left.purchaseOdometerUnit)],
            ['Purchase Date', this.left.purchaseDate]
        ]);
    }

    get planRows() {
        return buildRows([
            ['Dealer Package', this.left.dealerPackageName],
            ['Dealer Package Term', this.left.dealerPackageTermName],
            ['Dealer Package Tier', this.left.dealerPackageTierName]
        ]);
    }

    // ---- Live formula mirror: Warranty_Validity__c ----
    // AND(Payment_Status__c = 'Paid', Odometer_End__c > Current_Odometer__c,
    //     Current_Odometer__c >= Odometer_Start__c, TODAY() >= Contract_Start_Date__c,
    //     TODAY() <= Contract_End_Date__c)
    // The real field declares formulaTreatBlanksAs BlankAsZero - a blank
    // Current Odometer (before the user types anything) must evaluate as 0,
    // not auto-fail, or this alert would show on load every time.
    get isWarrantyValid() {
        const src = this.chainData;
        if (!src) return false;
        const odo = numOrZero(this.form.currentOdometer);
        const odometerEnd = numOrZero(src.odometerEnd);
        const odometerStart = numOrZero(src.odometerStart);
        const today = startOfToday();
        const start = toDate(src.contractStartDate);
        const end = toDate(src.contractEndDate);
        return (
            src.paymentStatus === 'Paid' &&
            odometerEnd > odo &&
            odo >= odometerStart &&
            start !== null && today >= start &&
            end !== null && today <= end
        );
    }

    // ---- Live formula mirror: Coverage_Active__c ----
    // AND(NOT(ISBLANK(Dealer_Package_Term__c)), NOT(ISBLANK(Purchase_Date__c)),
    //     TODAY() >= ADDMONTHS(Purchase_Date__c, Start_Term__c * (Years?12:1)),
    //     TODAY() <= ADDMONTHS(Purchase_Date__c, Expiry_Term__c * (Years?12:1)),
    //     OR(Restriction_Type__c = 'Unlimited',
    //        Current_Odometer__c <= Mileage__c converted to Current_Odometer_Unit__c))
    // Reads the DEALER package term (Dealer_Package_Term__c), not the master
    // catalog - matches the real formula's Sep 26 rewrite. A blank
    // Duration_Type__c defaults to Months semantics (multiplier 1). Mileage
    // check uses Mileage__c/Mileage_Unit__c ("Max. Eligible Mileage"), not
    // the sparse Mileage_Restriction_End__c - converts for a KM/Miles
    // mismatch (1 mile = 1.60934 km). Max. Vehicle Age (ByYear__c) is
    // deliberately not part of this check - Osama's call, it's eligibility
    // criteria checked elsewhere, not a gate on an existing claim.
    get isCoverageActive() {
        const src = this.chainData;
        if (!src || !src.dealerPackageTermId) return false;
        const purchase = toDate(src.purchaseDate);
        if (!purchase) return false;

        const multiplier = src.durationType === 'Years' ? 12 : 1;
        const lowerBound = addMonths(purchase, numOrZero(src.startTerm) * multiplier);
        const upperBound = addMonths(purchase, numOrZero(src.expiryTerm) * multiplier);

        const today = startOfToday();
        if (today < lowerBound || today > upperBound) return false;

        if (src.restrictionType === 'Unlimited') return true;

        const odo = numOrZero(this.form.currentOdometer);
        const maxMileage = convertMileage(
            numOrZero(src.maxEligibleMileage),
            src.maxEligibleMileageUnit,
            this.form.currentOdometerUnit
        );
        return odo <= maxMileage;
    }

    // ---- Top alert banners (replace the earlier inline badges) ----
    // Always shown, once the chain has loaded - switches between a red
    // warning and a green confirmation rather than disappearing when valid,
    // per Osama's explicit feedback ("when these checks are true they
    // disappear, rather then showing green").
    get warrantyAlertClass() {
        return this.isWarrantyValid ? 'alertbox success' : 'alertbox';
    }
    get warrantyAlertMessage() {
        return this.isWarrantyValid
            ? 'Warranty is valid.'
            : "Warranty is not valid — verify the customer's contract status before proceeding.";
    }
    get coverageAlertClass() {
        return this.isCoverageActive ? 'alertbox success' : 'alertbox';
    }
    get coverageAlertMessage() {
        return this.isCoverageActive
            ? 'Coverage is active.'
            : 'Coverage is not active — this claim may not be eligible for reimbursement.';
    }

    // ---- Field change handling ----
    handleFieldChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
        this.form = { ...this.form, [field]: value };
    }

    // ---- Save: always creates a new Claim, then closes ----
    async handleSave() {
        this.isSaving = true;
        try {
            const claimId = await createClaim({
                applicationId: this.applicationId,
                dateFiled: this.form.dateFiled,
                currentOdometer: this.form.currentOdometer,
                currentOdometerUnit: this.form.currentOdometerUnit,
                claimDescription: this.form.claimDescription,
                customerLocation: this.form.customerLocation
            });
            this.showToast('Claim Created', 'success');
            this.close({ created: true, claimId });
        } catch (error) {
            this.showError('Could Not Create Claim', error, 'sticky');
        } finally {
            this.isSaving = false;
        }
    }

    handleClose() {
        this.close({ created: false });
    }

    showToast(title, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, variant }));
    }

    showError(title, error, mode) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message: (error && error.body && error.body.message) || 'An unexpected error occurred.',
                variant: 'error',
                mode: mode || 'dismissable'
            })
        );
    }
}

function buildRows(pairs) {
    return pairs.map(([label, rawValue], index) => {
        const hasValue = rawValue !== null && rawValue !== undefined && rawValue !== '';
        return {
            key: label + index,
            label,
            value: hasValue ? cleanValue(rawValue) : NOT_PROVIDED,
            valueClass: hasValue ? 'v' : 'v empty'
        };
    });
}

// Several address-composing formula fields (Dealer_Address__c,
// Customer_Address__c) use BR() to join lines, which renders as a literal
// "<br>" once read back as plain text - LWC escapes HTML in text
// interpolation (correctly, for XSS safety), so raw <br> tags would show
// verbatim instead of a line break. Convert them to real newlines instead;
// paired with `white-space: pre-line` in CSS this renders exactly the same
// visual result without ever injecting raw HTML.
function cleanValue(value) {
    if (typeof value !== 'string') return value;
    return value.replace(/<br\s*\/?>/gi, '\n');
}

function joinDot(a, b) {
    return [a, b].filter((part) => part).join(' · ');
}

function joinUnit(value, unit) {
    if (value === null || value === undefined || value === '') return null;
    const formatted = Number(value).toLocaleString();
    return unit ? `${formatted} ${unit}` : formatted;
}

function toDate(value) {
    if (!value) return null;
    const d = new Date(value);
    d.setHours(0, 0, 0, 0);
    return isNaN(d.getTime()) ? null : d;
}

// yyyy-mm-dd in the LOCAL timezone (not toISOString, which is UTC and can
// roll back a day depending on the user's offset) - what lightning-input
// type="date" expects as its value.
function todayIso() {
    const d = new Date();
    const yyyy = d.getFullYear();
    const mm = String(d.getMonth() + 1).padStart(2, '0');
    const dd = String(d.getDate()).padStart(2, '0');
    return `${yyyy}-${mm}-${dd}`;
}

function startOfToday() {
    const d = new Date();
    d.setHours(0, 0, 0, 0);
    return d;
}

function addMonths(date, months) {
    const d = new Date(date);
    d.setMonth(d.getMonth() + Number(months || 0));
    return d;
}

const KM_PER_MILE = 1.60934;

// Converts a mileage value from its source unit to the target unit (both
// 'KM' or 'Miles'). Mirrors Coverage_Active__c's own conversion exactly.
function convertMileage(value, fromUnit, toUnit) {
    if (!fromUnit || !toUnit || fromUnit === toUnit) return value;
    return toUnit === 'Miles' ? value / KM_PER_MILE : value * KM_PER_MILE;
}

// Mirrors Salesforce's formulaTreatBlanksAs BlankAsZero: a blank/invalid
// numeric value evaluates as 0 in the real formula, not as an automatic
// formula failure.
function numOrZero(value) {
    if (value === null || value === undefined || value === '') return 0;
    const n = Number(value);
    return isNaN(n) ? 0 : n;
}