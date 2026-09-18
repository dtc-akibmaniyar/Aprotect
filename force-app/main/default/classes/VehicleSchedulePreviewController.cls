/**
 * VehicleSchedulePreviewController
 *
 * Preview-mode entry point for schedule resolution (change-plan §11 P1, [A]
 * "preview-mode entry point (@AuraEnabled resolve-for-preview)").
 *
 * Internal admins preview what a seeded vehicle + package resolve to BEFORE
 * anything is sold. The endpoint is inert while the engine flag is off:
 * Pricing_Engine_Enabled__c stays FALSE through P1/P2 (no portal or admin
 * behaviour change); it is enabled preview-only for internal users at P3 (T2).
 */
public with sharing class VehicleSchedulePreviewController {

    /**
     * Resolve fee lines for preview. Returns null when the pricing-engine flag
     * is off (preview unavailable) so callers can degrade gracefully. Never
     * throws for missing context — block codes are returned on the result.
     */
    @AuraEnabled(cacheable=true)
    public static VehicleScheduleResolver.ResolverResult resolveForPreview(
        Id dealerId, Id vehicleId, Id packageId, Date asOfDate) {

        if (!PortalFeatureFlagService.isPricingEngineEnabled()) {
            return null;
        }

        VehicleScheduleResolver.ResolveRequest req = new VehicleScheduleResolver.ResolveRequest(
            dealerId, vehicleId, packageId, asOfDate);

        return VehicleScheduleResolver.resolve(req);
    }
}