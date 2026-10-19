/**
 * Centralized Claims pricing service. Direct port of calc() from
 * warranty_claims_dashboard (2).html, which superseded the original
 * warranty_claims_dashboard.html as the pricing source of truth (Osama,
 * Sep 22) when the Repair Price Scenarios screen was redesigned into a
 * multi-row grid. One Estimate__c = one scenario row.
 *
 * Sep 22 deviation from the original baseline, flagged deliberately: file
 * (2) drops Core Charge entirely (no coreOn/core, no netParts - wholesale
 * cost is simply parts + labour + supplies + insurance). The original
 * $200-core-charge LKQ baseline (wsTotal=2170) no longer applies; the same
 * inputs now total 2370. Core_Charge_Applies__c/Core_Charge__c/
 * Net_Parts__c stay deployed on Estimate__c (deleting is riskier than
 * leaving an unused field, same precedent as Part__c.Net_Parts__c) but are
 * no longer read or written here.
 *
 * Two entry points:
 *  - calculateLive: pure math on raw inputs, no DML, for an LWC to call on
 *    every keystroke so nothing has to be saved first.
 *  - recalculateAndStamp: reads an Estimate__c, computes, and writes the
 *    results onto its Calculated Totals fields.
 *
 * FLS/CRUD hardening (Sep 22, Osama's explicit request): every SOQL query
 * here uses WITH USER_MODE, and the stamp in recalculateAndStamp goes
 * through Database.update(records, AccessLevel.USER_MODE) rather than a
 * bare update, throwing System.NoAccessException (caught and rethrown as an
 * AuraHandledException) instead of silently saving a partial record if the
 * running user lacks permission on one of the stamped fields.
 */
public with sharing class ClaimPricingService {

    public class PricingInput {
        @AuraEnabled public Decimal parts        { get; set; }
        @AuraEnabled public Decimal hrs          { get; set; }
        @AuraEnabled public Decimal rate         { get; set; }
        @AuraEnabled public Decimal ins          { get; set; }
        @AuraEnabled public Decimal supC         { get; set; }
        @AuraEnabled public Decimal supR         { get; set; }
        @AuraEnabled public Decimal retail       { get; set; }
        @AuraEnabled public Decimal cap          { get; set; }
        @AuraEnabled public Decimal ded          { get; set; }
        @AuraEnabled public Decimal taxPercent   { get; set; }
    }

    public class PricingResult {
        @AuraEnabled public Decimal labour       { get; set; }
        @AuraEnabled public Decimal wsTotal      { get; set; }
        @AuraEnabled public Decimal coverage     { get; set; }
        @AuraEnabled public Decimal custPre      { get; set; }
        @AuraEnabled public Decimal custTax      { get; set; }
        @AuraEnabled public Decimal pl           { get; set; }
        @AuraEnabled public Decimal retailTotal  { get; set; }
    }

    // =====================================================================
    // TASK-047 scenario model (Noelle, Repair Price Scenarios Feedback 1.0)
    // =====================================================================
    //
    // This is calcEst() from Main.dc.html, line for line, cross-checked
    // against all 15 cards of Formulas.dc.html. It REPLACES the coverage and
    // tax sequence in calculate() above for everything built from TASK-047
    // onward. The two differ on real money, which is why the switch was
    // raised with Osama before any of this was written:
    //
    //   calculate()      tests the cap against the PRE-TAX retail repair and
    //                    taxes the customer's leftover share at the very end,
    //                    so a $3,000 cap actually pays out $3,390 all in.
    //   calculateScenario() tests the cap against the TAX-INCLUSIVE repair,
    //                    so a $3,000 cap means $3,000 all in, and subtracts
    //                    approved ancillary benefits from the customer's bill.
    //
    // calculate() is deliberately left in place and untouched: its callers,
    // its own tests, and every Estimate__c stamped before this deploy still
    // depend on it, and Osama's decision was that historical records are not
    // restated (forward only, no backfill).
    //
    // Pure math, no SOQL and no DML, so the LWC can call it on every
    // keystroke and get exactly what a save would stamp.

    /** Percent or flat-dollar markup. One rule, shared by parts, extended warranties and supplies. */
    public static Decimal applyMarkup(Decimal base, String markupType, Decimal markupValue) {
        Decimal b = nz(base), m = nz(markupValue);
        return markupType == 'Amount' ? b + m : b * (1 + m / 100);
    }

    /**
     * Already-aggregated scenario figures. Rolling the Part__c/Service__c/
     * Shop_Supply__c children up into these totals is ClaimEstimateService's
     * job; this class stays pure arithmetic, same split calculate() already has.
     */
    public class ScenarioInput {
        @AuraEnabled public Decimal partsWholesale     { get; set; }
        @AuraEnabled public Decimal partsRetail        { get; set; }
        @AuraEnabled public Decimal warrantyWholesale  { get; set; }
        @AuraEnabled public Decimal warrantyRetail     { get; set; }
        @AuraEnabled public Decimal labourWholesale    { get; set; }
        @AuraEnabled public Decimal labourRetail       { get; set; }
        @AuraEnabled public Decimal suppliesWholesale  { get; set; }
        @AuraEnabled public Decimal suppliesRetail     { get; set; }
        @AuraEnabled public Decimal coreTotal          { get; set; }
        @AuraEnabled public Decimal cap                { get; set; }
        @AuraEnabled public Decimal deductible         { get; set; }
        @AuraEnabled public Decimal taxPercent         { get; set; }
        @AuraEnabled public Decimal benefitsApproved   { get; set; }
        @AuraEnabled public Boolean isReimbursement    { get; set; }
        @AuraEnabled public Decimal reimbursementTotal { get; set; }
    }

    public class ScenarioResult {
        @AuraEnabled public Decimal partsWholesale    { get; set; }
        @AuraEnabled public Decimal partsRetail       { get; set; }
        @AuraEnabled public Decimal warrantyWholesale { get; set; }
        @AuraEnabled public Decimal warrantyRetail    { get; set; }
        @AuraEnabled public Decimal labourWholesale   { get; set; }
        @AuraEnabled public Decimal labourRetail      { get; set; }
        @AuraEnabled public Decimal suppliesWholesale { get; set; }
        @AuraEnabled public Decimal suppliesRetail    { get; set; }
        /** Tracked for the record, never in a total and never in P&L. */
        @AuraEnabled public Decimal coreTotal         { get; set; }
        @AuraEnabled public Decimal subtotalWholesale { get; set; }
        @AuraEnabled public Decimal subtotalRetail    { get; set; }
        @AuraEnabled public Decimal retailRepair      { get; set; }
        @AuraEnabled public Decimal repairTax         { get; set; }
        @AuraEnabled public Decimal repairInclTax     { get; set; }
        @AuraEnabled public Decimal suppliesTax       { get; set; }
        @AuraEnabled public Decimal suppliesInclTax   { get; set; }
        @AuraEnabled public Decimal taxTotal          { get; set; }
        @AuraEnabled public Decimal wholesaleTax      { get; set; }
        @AuraEnabled public Decimal costInclTax       { get; set; }
        @AuraEnabled public Decimal coverageApplied   { get; set; }
        @AuraEnabled public Decimal overLimit         { get; set; }
        @AuraEnabled public Decimal customerPays      { get; set; }
        @AuraEnabled public Decimal customerPaysPreTax{ get; set; }
        @AuraEnabled public Decimal customerTaxAmount { get; set; }
        @AuraEnabled public Decimal reimbursedToCustomer { get; set; }
        @AuraEnabled public Decimal claimCost         { get; set; }
        @AuraEnabled public Decimal benefitsApproved  { get; set; }
        /** Repair-only P&L with no benefit term. Keeps Estimate__c.Profit_Loss__c meaning what it always meant. */
        @AuraEnabled public Decimal profitLossRepairOnly { get; set; }
        /** Pre-tax P&L WITH benefits. Estimate__c.A_Protect_P_L_Incl_Benefits__c. */
        @AuraEnabled public Decimal profitLossInclBenefits { get; set; }
        /** Tax-inclusive P&L. Estimate__c.Profit_Loss_Incl_Tax__c. */
        @AuraEnabled public Decimal profitLossInclTax { get; set; }
        /** Loss as a positive number, the BEST ranking key. */
        @AuraEnabled public Decimal apLoss            { get; set; }
        @AuraEnabled public Boolean fullyCovered      { get; set; }
        @AuraEnabled public Boolean isReimbursement   { get; set; }
    }

    /** calcEst() from Main.dc.html, line for line. */
    public static ScenarioResult calculateScenario(ScenarioInput i) {
        Boolean isR = i.isReimbursement == true;

        Decimal partsW = nz(i.partsWholesale), partsR = nz(i.partsRetail);
        Decimal warrW  = nz(i.warrantyWholesale), warrR = nz(i.warrantyRetail);
        Decimal labW   = nz(i.labourWholesale), labR = nz(i.labourRetail);
        Decimal supW   = nz(i.suppliesWholesale), supR = nz(i.suppliesRetail);
        Decimal core   = nz(i.coreTotal);
        Decimal cap    = nz(i.cap);
        Decimal ded    = nz(i.deductible);
        Decimal ben    = nz(i.benefitsApproved);

        // A reimbursement-only scenario has no repair, no deductible and no
        // shop supplies. Its benefit total is the sum of its approved
        // receipts, not the claim-level ancillary benefits.
        if (isR) {
            partsW = 0; partsR = 0; warrW = 0; warrR = 0;
            labW = 0; labR = 0; supW = 0; supR = 0; core = 0;
            ded = 0;
            ben = nz(i.reimbursementTotal);
        }

        Decimal t = nz(i.taxPercent) / 100;

        Decimal subW = partsW + warrW + labW + supW;
        Decimal subR = partsR + warrR + labR + supR;

        // Supplies are excluded so the warranty cap is tested against the repair only.
        Decimal retailRepair = partsR + warrR + labR;
        Decimal repairTax    = retailRepair * t;
        Decimal repairInc    = retailRepair + repairTax;

        Decimal covApplied = Math.max(0, Math.min(repairInc, cap) - ded);
        Decimal overLimit  = Math.max(0, repairInc - cap);
        Decimal custRepair = repairInc - covApplied;

        Decimal supTax = supR * t;
        Decimal supInc = supR + supTax;

        Decimal rawPay   = custRepair + supInc - ben;
        Decimal custPay  = Math.max(0, rawPay);
        Decimal reimbOut = Math.max(0, -rawPay);

        Decimal custPreTaxPortion = divide(custPay, 1 + t);
        Decimal custSub    = custPreTaxPortion - reimbOut;
        Decimal custTaxAmt = custPay - custPreTaxPortion;

        Decimal claimCost = subW;
        Decimal whTax     = claimCost * t;
        Decimal costInc   = claimCost + whTax;

        // Repair-only P&L: the same arithmetic with the benefit term removed,
        // so Profit_Loss__c keeps meaning exactly what it has always meant.
        Decimal rawPayNoBen = custRepair + supInc;
        Decimal custSubNoBen = divide(Math.max(0, rawPayNoBen), 1 + t);

        ScenarioResult r = new ScenarioResult();
        r.partsWholesale    = money(partsW);
        r.partsRetail       = money(partsR);
        r.warrantyWholesale = money(warrW);
        r.warrantyRetail    = money(warrR);
        r.labourWholesale   = money(labW);
        r.labourRetail      = money(labR);
        r.suppliesWholesale = money(supW);
        r.suppliesRetail    = money(supR);
        r.coreTotal         = money(core);
        r.subtotalWholesale = money(subW);
        r.subtotalRetail    = money(subR);
        r.retailRepair      = money(retailRepair);
        r.repairTax         = money(repairTax);
        r.repairInclTax     = money(repairInc);
        r.suppliesTax       = money(supTax);
        r.suppliesInclTax   = money(supInc);
        r.taxTotal          = money(repairTax + supTax);
        r.wholesaleTax      = money(whTax);
        r.costInclTax       = money(costInc);
        r.coverageApplied   = money(covApplied);
        r.overLimit         = money(overLimit);
        r.customerPays      = money(custPay);
        r.customerPaysPreTax= money(custSub);
        r.customerTaxAmount = money(custTaxAmt);
        r.reimbursedToCustomer = money(reimbOut);
        r.claimCost         = money(claimCost);
        r.benefitsApproved  = money(ben);
        r.profitLossRepairOnly   = money(custSubNoBen - claimCost);
        r.profitLossInclBenefits = money(custSub - claimCost);
        r.profitLossInclTax      = money(custPay - reimbOut - costInc);
        r.apLoss            = money(claimCost - custSub);
        // "Fully covered" is a repair state. A scenario with nothing priced is
        // neither covered nor over limit, and a reimbursement is neither.
        r.fullyCovered      = !isR && retailRepair > 0 && overLimit <= 0;
        r.isReimbursement   = isR;
        return r;
    }

    @AuraEnabled(cacheable=false)
    public static ScenarioResult calculateScenarioLive(ScenarioInput input) {
        return calculateScenario(input);
    }

    /** calc(s) from warranty_claims_dashboard (2).html, line for line. */
    public static PricingResult calculate(PricingInput i) {
        Decimal parts  = nz(i.parts);
        Decimal labour = nz(i.hrs) * nz(i.rate);
        Decimal wsTotal  = parts + labour + nz(i.supC) + nz(i.ins);
        Decimal retail   = nz(i.retail);
        Decimal coverage = Math.max(0, Math.min(nz(i.cap), retail) - nz(i.ded));
        Decimal custPre  = Math.max(0, retail - coverage) + nz(i.supR);
        Decimal custTax  = custPre * (1 + nz(i.taxPercent) / 100);
        Decimal pl       = custPre - wsTotal;
        Decimal retailTotal = retail + nz(i.supR);

        PricingResult r = new PricingResult();
        r.labour      = money(labour);
        r.wsTotal     = money(wsTotal);
        r.coverage    = money(coverage);
        r.custPre     = money(custPre);
        r.custTax     = money(custTax);
        r.pl          = money(pl);
        r.retailTotal = money(retailTotal);
        return r;
    }

    @AuraEnabled(cacheable=true)
    public static PricingResult calculateLive(PricingInput input) {
        return calculate(input);
    }

    public class PricingDefaults {
        @AuraEnabled public Decimal cap              { get; set; }
        @AuraEnabled public Decimal ded              { get; set; }
        @AuraEnabled public Decimal taxPercent       { get; set; }
        @AuraEnabled public Decimal labourRateOnFile { get; set; }
        @AuraEnabled public String  claimRef         { get; set; }
    }

    /**
     * Read-only preview of the same defaults recalculateAndStamp resolves at
     * save time (claim's Application_Package__c for cap/deductible, shop's
     * region-synced percentage for tax), so the Repair Price Scenarios LWC's
     * live total matches what actually gets saved instead of guessing.
     * claimRef is a compact display string (claim number + vehicle) for the
     * grid's header bar, not used in any calculation.
     */
    @AuraEnabled(cacheable=true)
    public static PricingDefaults getDefaults(Id claimId, Id repairShopId) {
        PricingDefaults d = new PricingDefaults();
        if (claimId != null) {
            Claim__c c = [
                SELECT Name, Vehicle_Year__c, Vehicle_Make__c, Vehicle_Model__c,
                       Application_Package__r.Per_Claim_Limit__c, Application_Package__r.Deductible__c
                FROM Claim__c WHERE Id = :claimId
                WITH USER_MODE
            ];
            d.cap = c.Application_Package__r?.Per_Claim_Limit__c;
            d.ded = c.Application_Package__r?.Deductible__c;
            d.claimRef = buildClaimRef(c);
        }
        if (repairShopId != null) {
            Repair_Shop__c s = [
                SELECT Tax_Percentage__c, Labour_Rate_On_File__c
                FROM Repair_Shop__c WHERE Id = :repairShopId
                WITH USER_MODE
            ];
            d.taxPercent = s.Tax_Percentage__c;
            d.labourRateOnFile = s.Labour_Rate_On_File__c;
        }
        return d;
    }

    /**
     * Reads the Estimate and its shop, computes, stamps the totals, saves.
     * cap (per-claim limit) and the deductible come from the claim's
     * Application_Package__c (Per_Claim_Limit__c / Deductible__c), the
     * customer's actual purchased contract. A non-null cap parameter, or a
     * Deductable__c entered on the estimate itself, overrides that - the
     * HTML calculator lets the agent adjust both. If neither source has a
     * cap, it is treated as 0, which yields zero coverage rather than
     * silently unlimited coverage.
     */
    @AuraEnabled
    public static PricingResult recalculateAndStamp(Id estimateId, Decimal cap) {
        Estimate__c e = [
            SELECT Id, Parts_Cost__c,
                   Labour_Hours__c, Labour_Rate__c, Insurance_Amount__c,
                   Shop_Supplies__c, Shop_Supplies_Retail__c, Retail_Price__c,
                   Deductable__c, Repair_Shop__r.Tax_Percentage__c,
                   Repair_Shop__r.Labour_Rate_On_File__c,
                   Claim__r.Application_Package__r.Per_Claim_Limit__c,
                   Claim__r.Application_Package__r.Deductible__c
            FROM Estimate__c WHERE Id = :estimateId
            WITH USER_MODE
            LIMIT 1
        ];
        if (cap == null) cap = e.Claim__r?.Application_Package__r?.Per_Claim_Limit__c;
        Decimal ded = e.Deductable__c != null ? e.Deductable__c : e.Claim__r?.Application_Package__r?.Deductible__c;

        PricingInput i = new PricingInput();
        i.parts      = e.Parts_Cost__c;
        i.hrs        = e.Labour_Hours__c;
        i.rate       = e.Labour_Rate__c != null ? e.Labour_Rate__c : e.Repair_Shop__r?.Labour_Rate_On_File__c;
        i.ins        = e.Insurance_Amount__c;
        i.supC       = e.Shop_Supplies__c;
        i.supR       = e.Shop_Supplies_Retail__c;
        i.retail     = e.Retail_Price__c;
        i.ded        = ded;
        i.taxPercent = e.Repair_Shop__r?.Tax_Percentage__c;
        i.cap        = cap;

        PricingResult r = calculate(i);

        // Stamp onto a fresh record, not the queried one: the query above pulls
        // Claim__r.* which populates the non-reparentable master-detail Claim__c,
        // and an update carrying that field is rejected by the platform.
        List<Estimate__c> toStamp = new List<Estimate__c>{ new Estimate__c(
            Id                        = e.Id,
            Labour_Cost__c            = r.labour,
            Wholesale_Cost__c         = r.wsTotal,
            Coverage_Applied__c       = r.coverage,
            Customer_Pays__c          = r.custPre,
            Customer_Pays_With_Tax__c = r.custTax,
            Profit_Loss__c            = r.pl,
            Retail_Total__c           = r.retailTotal,
            // Sep 22 (Osama): write back the deductible actually used (the
            // estimate's own override if set, else the claim's), so the
            // record shows the real number instead of staying blank -
            // same fix as ClaimEstimateService.saveEstimates.
            Deductable__c             = ded
        ) };
        try {
            Database.update(toStamp, AccessLevel.USER_MODE);
        } catch (System.NoAccessException ex) {
            throw new AuraHandledException(
                'You do not have permission to update one or more calculated total fields. Contact your administrator.'
            );
        }
        return r;
    }

    private static Decimal nz(Decimal d) { return d == null ? 0 : d; }
    private static Decimal money(Decimal d) { return d.setScale(2, RoundingMode.HALF_UP); }

    /**
     * Apex Decimal division needs an explicit scale, unlike the JavaScript the
     * scenario model is ported from. 6 decimal places keeps the intermediate
     * precision well clear of the 2 the results are rounded to, so
     * customerPaysPreTax and customerTaxAmount still add back up to
     * customerPays exactly. Guards divide-by-zero, which only arises if a tax
     * rate of -100% were ever entered.
     */
    private static Decimal divide(Decimal n, Decimal d) {
        return d == 0 ? 0 : n.divide(d, 6, RoundingMode.HALF_UP);
    }

    /** "CL ID - 00043 · 2015 BMW 6-Series", skipping any blank vehicle part. */
    private static String buildClaimRef(Claim__c c) {
        List<String> vehicleParts = new List<String>();
        if (String.isNotBlank(c.Vehicle_Year__c)) vehicleParts.add(c.Vehicle_Year__c);
        if (String.isNotBlank(c.Vehicle_Make__c)) vehicleParts.add(c.Vehicle_Make__c);
        if (String.isNotBlank(c.Vehicle_Model__c)) vehicleParts.add(c.Vehicle_Model__c);
        String vehicle = String.join(vehicleParts, ' ');
        if (String.isBlank(vehicle)) return c.Name;
        return c.Name + ' · ' + vehicle;
    }
}