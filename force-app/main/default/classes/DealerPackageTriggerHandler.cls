/**
 * DealerPackageTriggerHandler
 *
 * P2 rework (change-implementation plan §04.2 / §11 P2): the insert-only copy
 * fan-out is replaced by an idempotent reconcile through
 * DealerPackageSyncService. Mirrored content fields that the plan retires
 * (P2 gated deletions) are no longer copied; the fields the portal still reads
 * are refreshed from the master on every reconcile so dealer copies stop going
 * stale.
 *
 * Trigger contract (DealerPackageTrigger):
 *   • after insert — full mirror build (required for the portal; ungated).
 *   • after update — re-sync when the master link (Package__c) actually
 *     changed, so a dealer mirror re-created against another master is
 *     reconciled in the same transaction. Gated behind
 *     PortalFeatureFlagService.isDealerSyncEnabled() so the sync can be
 *     switched off without touching portal behaviour (§10.3 P2 rollback).
 *
 * Re-entrancy: DealerPackageSyncService.reconcileDealerPackages() is guarded by
 * an in-transaction static flag. Sync child DML fires DealerPackageOptionTrigger
 * (its updateTermsForOptions is a pure idempotent sum recompute with its own
 * re-entrancy guard); no trigger exists on Dealer_Package_Tier__c or
 * Dealer_Package_Term__c, and header-mirror updates performed here never change
 * Package__c, so the after-update path cannot loop. DealerPackageFileCopyTrigger
 * and the DLRS rollup triggers are untouched by the sync (they key on their own
 * fields/objects).
 */
public class DealerPackageTriggerHandler {

    /**
     * Static re-entrancy guard. Prevents the after-update path from re-running
     * when header-mirror updates issued by the sync (or this handler) fire the
     * same trigger context recursively.
     */
    @TestVisible
    private static Boolean afterUpdateRunning = false;

    public static void onAfterInsert(List<Dealer_Package__c> dealerPackages) {
        if (dealerPackages == null || dealerPackages.isEmpty()) return;
        Set<Id> ids = new Set<Id>();
        for (Dealer_Package__c dp : dealerPackages) {
            if (dp.Package__c != null) ids.add(dp.Id);
        }
        if (ids.isEmpty()) return;

        // Full idempotent reconcile: header mirrors + create missing
        // tiers/terms/options + derived prices. Mirrors must exist for the
        // portal to function, so this path is not flag-gated (legacy behaviour).
        DealerPackageSyncService.reconcileDealerPackages(ids);
    }

    public static void onAfterUpdate(
        List<Dealer_Package__c> dealerPackages,
        Map<Id, Dealer_Package__c> oldById
    ) {
        if (afterUpdateRunning) return;
        if (dealerPackages == null || oldById == null) return;
        afterUpdateRunning = true;
        try {
            // The update path only re-syncs when the master link changed. Rollup
            // totals written by DLRS (Total_Revenue__c etc.) and file-copy
            // touches therefore never trigger a reconcile.
            if (!PortalFeatureFlagService.isDealerSyncEnabled()) return;

            Set<Id> changed = new Set<Id>();
            for (Dealer_Package__c dp : dealerPackages) {
                Dealer_Package__c old = oldById != null ? oldById.get(dp.Id) : null;
                if (old != null && dp.Package__c != old.Package__c) {
                    changed.add(dp.Id);
                }
            }
            if (changed.isEmpty()) return;

            DealerPackageSyncService.reconcileDealerPackages(changed);
        } finally {
            afterUpdateRunning = false;
        }
    }
}