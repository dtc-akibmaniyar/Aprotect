/**
 * PackageAgeLimitPropagationService
 *
 * Keeps a master Package__c "Max Vehicle Age Limit (In Years)"
 * (Package__c.Max_Vehicle_Age_Limit_In_Years__c) and the "Max. Vehicle Age"
 * (Package_Term__c.ByYear__c) of that package's master terms in agreement.
 *
 * Why it exists
 * ─────────────
 * DealerPortalController.isWarrantyTermEligible reads the max vehicle age from
 * ByYear__c on the DEALER term (Dealer_Package_Term__c) to decide warranty
 * eligibility. Nothing kept the MASTER Package_Term__c.ByYear__c in step with
 * the package's limit, so a new blank term (or a limit change) silently
 * re-broke eligibility until someone re-ran a manual backfill. This service
 * removes that drift at the source.
 *
 * The master term stays the single source of truth for the mirror: once
 * ByYear__c is correct on the master Package_Term__c, the existing
 * DealerPackageSyncService mirror carries it to Dealer_Package_Term__c. This
 * service writes ONLY the master side, then asks the existing reconcile entry
 * point (DealerPackageSyncService.reconcileForMasterPackage) to refresh the
 * dealer mirrors — it never writes a dealer row itself.
 *
 * Rules
 * ─────
 *  • Term created (Package_Term__c before insert): a term whose ByYear__c is
 *    blank takes its parent package's limit, when the package carries a
 *    non-null limit. An explicit term value is never touched.
 *  • Package limit changed (Package__c after update): that package's terms
 *    follow the new limit WHEN they were following the package — i.e. the
 *    term's current ByYear__c is blank OR equals the PREVIOUS limit. A term
 *    carrying any other value is treated as a deliberate override, is left
 *    exactly as it is, and is reported (getSkippedTermIds() /
 *    getSkippedTermReasons() + a WARN debug line).
 *  • A package whose limit is set to null propagates nothing — there is no
 *    value to take, so existing terms are left as they are (never blanked).
 *  • Following the package = taking the package's value literally; a limit of
 *    0 therefore lands on the term as 0, which the portal reads as "no age
 *    restriction" (ByYear__c > 0 is the portal's active-limit guard).
 *
 * Safety
 * ──────
 *  • Bulk-safe: one SOQL per collection and one DML — no SOQL/DML in loops.
 *  • Recursion-safe: the after-update path carries an in-transaction static
 *    guard, and the reconcile only writes dealer rows (no trigger loops back
 *    to master Package__c / Package_Term__c).
 *  • Sharing/FLS style matches the surrounding catalogue-master code
 *    (DealerPackageSyncService, PackageOptionMaintenanceService): declared
 *    `without sharing` because master catalogue rows are org-wide by design,
 *    and — like that code — it does not strip or hand-check FLS on the two
 *    master fields it owns.
 *  • The dealer-mirror reconcile is gated by the same flag the master-driven
 *    after-update path uses (PortalFeatureFlagService.isDealerSyncEnabled());
 *    the master-term fix itself is not gated.
 */
public without sharing class PackageAgeLimitPropagationService {

    private PackageAgeLimitPropagationService() {}

    /** Reason code recorded for a term whose value is a deliberate override. */
    public static final String REASON_DELIBERATE_VALUE = 'DELIBERATE_VALUE_REMAINS';

    /**
     * Terms left untouched on the last limit change, keyed by master
     * Package_Term__c id. Empty when nothing was skipped.
     */
    private static final Map<Id, String> skippedTermReasons = new Map<Id, String>();

    /**
     * Master packages whose blank terms the insert path just filled. Consumed
     * (and cleared) by reconcileAfterTermInsert().
     */
    private static final Set<Id> propagatedPackageIds = new Set<Id>();

    /** Re-entrancy guard for the package after-update path. */
    @TestVisible
    private static Boolean packageUpdateRunning = false;

    /** Terms reported as skipped by the most recent propagation. */
    public static Map<Id, String> getSkippedTermReasons() {
        return skippedTermReasons;
    }

    /** Ids of the terms reported as skipped by the most recent propagation. */
    public static Set<Id> getSkippedTermIds() {
        return skippedTermReasons.keySet();
    }

    // =====================================================================
    // Term creation (Package_Term__c before insert)
    // =====================================================================

    /**
     * Fills ByYear__c from the parent package's limit for every new term that
     * is blank. Bulk-safe: one query for all parent packages; no DML (the row
     * is still being inserted, so the field is set in place).
     */
    public static void applyPackageLimitOnInsert(List<Package_Term__c> newTerms) {
        if (newTerms == null || newTerms.isEmpty()) return;

        // Start clean so a stale id from an aborted prior chunk can never leak.
        propagatedPackageIds.clear();

        Set<Id> packageIds = new Set<Id>();
        for (Package_Term__c t : newTerms) {
            if (t.ByYear__c == null && t.Package__c != null) packageIds.add(t.Package__c);
        }
        if (packageIds.isEmpty()) return;

        Map<Id, Decimal> limitByPackage = limitsByPackage(packageIds);

        for (Package_Term__c t : newTerms) {
            if (t.ByYear__c != null || t.Package__c == null) 
                continue;

            Decimal limitTemp = limitByPackage.get(t.Package__c);

            if (limitTemp != null) {
                t.ByYear__c = limitTemp;
                propagatedPackageIds.add(t.Package__c);
            }
        }
    }

    /**
     * After term insert: refresh the dealer mirrors of the packages whose terms
     * this propagation just filled, so the existing DealerPackageSyncService
     * mirror carries the limit onto Dealer_Package_Term__c. Gated by the same
     * dealer-sync flag as the package path; a no-op when nothing was filled.
     */
    public static void reconcileAfterTermInsert() {
        if (propagatedPackageIds.isEmpty()) return;
        Set<Id> packageIds = new Set<Id>(propagatedPackageIds);
        propagatedPackageIds.clear();
        if (!PortalFeatureFlagService.isDealerSyncEnabled()) return;
        DealerPackageSyncService.reconcileForMasterPackage(packageIds);
    }

    // =====================================================================
    // Package limit change (Package__c after update)
    // =====================================================================

    /**
     * Propagates a changed package limit onto that package's terms, then
     * refreshes the dealer mirrors. Only packages whose limit actually changed
     * — and whose new limit is non-null — are touched.
     */
    public static void propagateOnPackageLimitChange(
        List<Package__c> newPackages,
        Map<Id, Package__c> oldMap
    ) {
        if (packageUpdateRunning) return;
        if (newPackages == null || newPackages.isEmpty() || oldMap == null) return;

        Map<Id, Decimal> newLimitByPackage = new Map<Id, Decimal>();
        Map<Id, Decimal> oldLimitByPackage = new Map<Id, Decimal>();
        for (Package__c p : newPackages) {
            Package__c old = oldMap.get(p.Id);
            if (old == null) continue;
            Decimal newLimit = p.Max_Vehicle_Age_Limit_In_Years__c;
            Decimal oldLimit = old.Max_Vehicle_Age_Limit_In_Years__c;
            // Null new limit = nothing to propagate; unchanged limit = no-op.
            if (newLimit == null || newLimit == oldLimit) continue;
            newLimitByPackage.put(p.Id, newLimit);
            oldLimitByPackage.put(p.Id, oldLimit);
        }
        if (newLimitByPackage.isEmpty()) return;

        packageUpdateRunning = true;
        try {
            applyLimitToTerms(newLimitByPackage, oldLimitByPackage);

            if (PortalFeatureFlagService.isDealerSyncEnabled()) {
                DealerPackageSyncService.reconcileForMasterPackage(newLimitByPackage.keySet());
            }
        } finally {
            packageUpdateRunning = false;
        }
    }

    /**
     * Core follow logic. One query for every affected term; each term that was
     * following the package (blank or equal to the previous limit) moves to the
     * new limit, and every deliberate override is recorded as skipped.
     */
    private static void applyLimitToTerms(
        Map<Id, Decimal> newLimitByPackage,
        Map<Id, Decimal> oldLimitByPackage
    ) {
        skippedTermReasons.clear();

        Set<Id> packageIds = newLimitByPackage.keySet();
        List<Package_Term__c> updates = new List<Package_Term__c>();
        for (Package_Term__c t : [
            SELECT Id, Package__c, ByYear__c
            FROM Package_Term__c
            WHERE Package__c IN :packageIds
        ]) {
            Decimal newLimit = newLimitByPackage.get(t.Package__c);
            if (newLimit == null) continue;
            Decimal oldLimit = oldLimitByPackage.get(t.Package__c);

            if (t.ByYear__c == null || t.ByYear__c == oldLimit) {
                if (t.ByYear__c != newLimit) {
                    updates.add(new Package_Term__c(Id = t.Id, ByYear__c = newLimit));
                }
            } else {
                skippedTermReasons.put(t.Id, REASON_DELIBERATE_VALUE);
            }
        }

        if (!updates.isEmpty()) update updates;

        if (!skippedTermReasons.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'PackageAgeLimitPropagationService: left '
                    + skippedTermReasons.size()
                    + ' term(s) with a deliberate Max. Vehicle Age untouched (skipped ids: '
                    + String.valueOf(skippedTermReasons.keySet()) + ').'
            );
        }
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    /** Limit for each given package, including only packages with a limit. */
    private static Map<Id, Decimal> limitsByPackage(Set<Id> packageIds) {
        Map<Id, Decimal> limitByPackage = new Map<Id, Decimal>();
        if (packageIds == null || packageIds.isEmpty()) return limitByPackage;
        for (Package__c p : [
            SELECT Id, Max_Vehicle_Age_Limit_In_Years__c
            FROM Package__c
            WHERE Id IN :packageIds
        ]) {
            if (p.Max_Vehicle_Age_Limit_In_Years__c != null) {
                limitByPackage.put(p.Id, p.Max_Vehicle_Age_Limit_In_Years__c);
            }
        }
        return limitByPackage;
    }
}