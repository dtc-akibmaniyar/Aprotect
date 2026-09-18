/**
 * Centralized Claims pricing service. Direct port of calc() from
 * warranty_claims_dashboard.html, which is the pricing source of truth
 * (decision Sep 18). One Estimate__c = one HTML scenario row.
 *
 * Two entry points:
 *  - calculateLive: pure math on raw inputs, no DML, for an LWC to call on
 *    every keystroke so nothing has to be saved first.
 *  - recalculateAndStamp: reads an Estimate__c, computes, and writes the
 *    results onto its Calculated Totals fields.
 */
public with sharing class ClaimPricingService {

    public class PricingInput {
        @AuraEnabled public Decimal parts        { get; set; }
        @AuraEnabled public Boolean coreOn       { get; set; }
        @AuraEnabled public Decimal core         { get; set; }
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
        @AuraEnabled public Decimal core         { get; set; }
        @AuraEnabled public Decimal netParts     { get; set; }
        @AuraEnabled public Decimal wsTotal      { get; set; }
        @AuraEnabled public Decimal coverage     { get; set; }
        @AuraEnabled public Decimal custPre      { get; set; }
        @AuraEnabled public Decimal custTax      { get; set; }
        @AuraEnabled public Decimal pl           { get; set; }
        @AuraEnabled public Decimal retailTotal  { get; set; }
    }

    /** calc(s) from the HTML, line for line. */
    public static PricingResult calculate(PricingInput i) {
        Decimal parts  = nz(i.parts);
        Decimal core   = (i.coreOn == true) ? nz(i.core) : 0;
        Decimal labour = nz(i.hrs) * nz(i.rate);
        Decimal netParts = parts - core;
        Decimal wsTotal  = netParts + labour + nz(i.supC) + nz(i.ins);
        Decimal retail   = nz(i.retail);
        Decimal coverage = Math.max(0, Math.min(nz(i.cap), retail) - nz(i.ded));
        Decimal custPre  = Math.max(0, retail - coverage) + nz(i.supR);
        Decimal custTax  = custPre * (1 + nz(i.taxPercent) / 100);
        Decimal pl       = custPre - wsTotal;
        Decimal retailTotal = retail + nz(i.supR);

        PricingResult r = new PricingResult();
        r.labour      = money(labour);
        r.core        = money(core);
        r.netParts    = money(netParts);
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

    /**
     * Reads the Estimate and its shop, computes, stamps the totals, saves.
     * cap is passed in because the per-claim limit lives on Package_Term__c
     * (the other team's object); resolving it through the Claim ->
     * Application_Package chain is a follow-up, not guessed here.
     */
    @AuraEnabled
    public static PricingResult recalculateAndStamp(Id estimateId, Decimal cap) {
        Estimate__c e = [
            SELECT Id, Parts_Cost__c, Core_Charge_Applies__c, Core_Charge__c,
                   Labour_Hours__c, Labour_Rate__c, Insurance_Amount__c,
                   Shop_Supplies__c, Shop_Supplies_Retail__c, Retail_Price__c,
                   Deductable__c, Repair_Shop__r.Tax_Percentage__c,
                   Repair_Shop__r.Labour_Rate_On_File__c
            FROM Estimate__c WHERE Id = :estimateId LIMIT 1
        ];

        PricingInput i = new PricingInput();
        i.parts      = e.Parts_Cost__c;
        i.coreOn     = e.Core_Charge_Applies__c;
        i.core       = e.Core_Charge__c;
        i.hrs        = e.Labour_Hours__c;
        i.rate       = e.Labour_Rate__c != null ? e.Labour_Rate__c : e.Repair_Shop__r?.Labour_Rate_On_File__c;
        i.ins        = e.Insurance_Amount__c;
        i.supC       = e.Shop_Supplies__c;
        i.supR       = e.Shop_Supplies_Retail__c;
        i.retail     = e.Retail_Price__c;
        i.ded        = e.Deductable__c;
        i.taxPercent = e.Repair_Shop__r?.Tax_Percentage__c;
        i.cap        = cap;

        PricingResult r = calculate(i);

        e.Labour_Cost__c            = r.labour;
        e.Net_Parts__c              = r.netParts;
        e.Wholesale_Cost__c         = r.wsTotal;
        e.Coverage_Applied__c       = r.coverage;
        e.Customer_Pays__c          = r.custPre;
        e.Customer_Pays_With_Tax__c = r.custTax;
        e.Profit_Loss__c            = r.pl;
        e.Retail_Total__c           = r.retailTotal;
        update e;
        return r;
    }

    private static Decimal nz(Decimal d) { return d == null ? 0 : d; }
    private static Decimal money(Decimal d) { return d.setScale(2, RoundingMode.HALF_UP); }
}