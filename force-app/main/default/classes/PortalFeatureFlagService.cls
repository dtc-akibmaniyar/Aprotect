/**
 * PortalFeatureFlagService
 *
 * Single read point for the Aprotect dealer-portal transformation engine flags.
 * Flags live on the hierarchy custom setting Aprotect_Portal_Settings__c and ALL
 * default to false — the legacy dealer-portal code path stays authoritative until
 * engine parity is proven (change-plan safety architecture §10).
 *
 * Hierarchy resolution (P3): reads use getInstance(), so a USER-level row for an
 * internal/admin test user with Pricing_Engine_Enabled__c = true enables the
 * engine PREVIEW for exactly that user (toggle T2, per-user scoping). Dealer
 * portal users have no row → org default (absent → field defaults false) keeps
 * the legacy path. The org-wide default is never flipped in this sandbox.
 *
 * Every new engine entry point must check the relevant flag here before doing work.
 *
 * P1 scope: PortalFeatureFlagService + the setting are shipped additive and inert.
 * No portal behaviour changes while every flag is false.
 */
public inherited sharing class PortalFeatureFlagService {

    private PortalFeatureFlagService() {}

    /**
     * Pricing engine + schedule resolver active. Kept FALSE through P1/P2;
     * preview-only for internal users at P3 (toggle T2, hierarchy user rows),
     * portal at P4 (T4).
     */
    public static Boolean isPricingEngineEnabled() {
        return getSettings().Pricing_Engine_Enabled__c == true;
    }

    /**
     * Application_Package line-item snapshot writing. FALSE until P4/T5.
     */
    public static Boolean isLineItemSnapshotEnabled() {
        return getSettings().Line_Item_Snapshot_Enabled__c == true;
    }

    /**
     * Dealer-package sync runs (admin-side, additive). Default TRUE from P2
     * (toggle T1); shipped FALSE in P1.
     */
    public static Boolean isDealerSyncEnabled() {
        return getSettings().Dealer_Sync_Enabled__c == true;
    }

    /**
     * Parity logging between legacy path and engine (P3/P6 shadow mode). FALSE.
     */
    public static Boolean isParityLoggingEnabled() {
        return getSettings().Parity_Logging_Enabled__c == true;
    }

    /**
     * Hierarchy-instance read: user row > profile row > org-default row >
     * field defaults (all false). No org row + no user row ⇒ every flag is
     * false. Apex reads of custom settings are not FLS-gated, so engine code
     * works regardless of profile FLS.
     */
    private static Aprotect_Portal_Settings__c getSettings() {
        return Aprotect_Portal_Settings__c.getInstance();
    }
}