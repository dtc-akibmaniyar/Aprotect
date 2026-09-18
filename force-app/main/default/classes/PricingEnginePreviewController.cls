/**
 * PricingEnginePreviewController
 *
 * Preview-mode entry point for the full server-side pricing engine
 * (change-plan §11 P3 [A] "exposed @AuraEnabled (preview + save path)").
 *
 * Internal admins pick a dealer + vehicle + dealer package term (+ optional
 * selections / pre-tax override / premium-fee waiver) and see the complete
 * resolved quote: line set, fee lines, option lines, tax and totals — before
 * anything is sold (design §9.2 preview; toggle T2 scope = internal users
 * with a hierarchy row Pricing_Engine_Enabled__c = true).
 *
 * Inert while the flag is off: returns null so callers degrade gracefully
 * (same contract as VehicleSchedulePreviewController). Dealers (no flag row)
 * are never routed here — the legacy portal path stays authoritative.
 */
public with sharing class PricingEnginePreviewController {

    @AuraEnabled(cacheable=true)
    public static PricingEngineService.QuoteResult previewQuote(
        Id dealerId,
        Id vehicleId,
        Id dealerPackageId,
        Id dealerTermId,
        List<Id> selectedOptionIds,
        Decimal dealerPriceOverride,
        Boolean waivePremiumFee) {

        if (!PortalFeatureFlagService.isPricingEngineEnabled()) {
            return null;
        }
        if (dealerId == null || vehicleId == null || dealerTermId == null) {
            PricingEngineService.QuoteResult r = new PricingEngineService.QuoteResult();
            r.success = false;
            r.errors.add('dealerId, vehicleId and dealerTermId are required for a preview.');
            return r;
        }

        PricingEngineService.QuoteRequest req = new PricingEngineService.QuoteRequest();
        req.dealerId = dealerId;
        req.vehicleId = vehicleId;
        req.dealerPackageId = dealerPackageId;
        req.dealerTermId = dealerTermId;
        req.selectedOptionIds = selectedOptionIds;
        req.dealerPriceOverride = dealerPriceOverride;
        req.waivePremiumFee = waivePremiumFee == true;
        return PricingEngineService.computeQuote(req);
    }
}