/**
 * DealerPackageSyncService
 *
 * Idempotent dealer-mirror reconciliation engine (change-implementation plan
 * §04.1 / §11 P2 — "DealerPackageSyncService").
 *
 * What it does
 * ────────────
 * Reconciles a dealer's package mirror (Dealer_Package__c + its
 * Dealer_Package_Tier__c / Dealer_Package_Term__c / Dealer_Package_Option__c
 * children) against the master catalogue (Package__c / Package_Tier__c /
 * Package_Term__c / Package_Option__c):
 *
 *   • CREATE missing tiers / terms / options (no duplicates on re-run — each
 *     child is keyed by its master reference, mirroring the pre-P2 copy
 *     semantics exactly, incl. the record-type-specific option selection rules).
 *   • UPDATE structure (master-mirrored content fields) and refresh the stored
 *     price ANCHORS — Original_Package_Term_Cost__c /
 *     Original_Package_Option_Price__c — from the master wholesale price.
 *
 *     ORG FACT (corrected from the P0 org-facts sheet): Dealer_Package_Term__c
 *     and Dealer_Package_Option__c Net_Cost__c / Retail_Price__c are ALREADY
 *     formula fields anchored on the stored Original_* snapshot plus the
 *     dealer-local discount/markup:
 *         Net_Cost   = Original_* − discount ($ or %)
 *         Retail     = Net_Cost + markup ($ or %)
 *     So the sync writes the stored anchors and the formulas derive Net/Retail
 *     live — the decision D-N2 outcome (do NOT convert to stored currency /
 *     do not fight the formula chain) is honoured by construction: one writer
 *     for the anchor, live derivation for the rest.
 *   • PRESERVE dealer-local markup/discount/incentive fields untouched
 *     (Markup__c, Markup_Type__c, Discount_Type__c, Discount_Value__c,
 *     Sales_Rep_Incentive__c on terms; Dealer_Markup__c, Markup_Type__c,
 *     Discount_Type__c, Discount_Value__c on options).
 *   • NEVER deletes dealer rows without an explicit archive decision (a child
 *     whose master no longer exists is left in place and simply no longer
 *     refreshed — see reconcile() notes).
 *
 * Entry points
 * ────────────
 *   • reconcileDealerPackages(Set<Id>)            — full mirror reconcile (create
 *                                                   missing + refresh) on demand
 *   • reconcileForMasterPackage/Tier/Term/Option  — master-change propagation:
 *                                                   resolves the dealer mirrors
 *                                                   affected by changed master
 *                                                   records and reconciles them
 *                                                   (one run updates every copy)
 *   • assignPlanToAllDealers(...)                 — §09.1 bulk-assign tool
 *                                                   (@AuraEnabled, dry-run first,
 *                                                   batchable path for scale)
 *
 * Safety (§10)
 * ────────────
 * The service never touches a portal code path: it only writes the dealer-mirror
 * rows the portal already reads. Reconcile is idempotent and additive — re-runs
 * duplicate nothing. The trigger update-path is gated behind
 * PortalFeatureFlagService.isDealerSyncEnabled() (Dealer_Sync_Enabled__c);
 * the after-insert fan-out is ungated because dealer mirrors must exist for the
 * portal to function (legacy behaviour, now routed through this service).
 */
public without sharing class DealerPackageSyncService {

    // Map Package__c RecordType DeveloperNames to Dealer_Package__c RecordType
    // DeveloperNames (moved from DealerPackageTriggerHandler).
    private static final Map<String, String> RECORD_TYPE_MAP = new Map<String, String>{
        'Extended_Limited_Warranty' => 'Extended_Limited_Warranty',
        'Car_Loan_Protection' => 'Car_Loan_Protection',
        'Tire_Rim_Protection_Plan' => 'Tire_Rim_Protection_Plan',
        'Gap_Coverage' => 'Total_Loss_Coverage'
    };

    /**
     * Re-entrancy guard for trigger-driven sync. DML performed by this service
     * (child term/option/tier updates) must never loop back into the sync paths.
     */
    @TestVisible
    private static Boolean syncInProgress = false;

    // ---- Defensive mirror writers (P7-e-fix) --------------------------------
    // A single master value the dealer-side metadata cannot accept must never
    // take the whole create/sync transaction down. Child mirror DML therefore
    // runs allOrNone = false: the good rows commit, rejects are recorded below
    // so the console can flag the exact package with a plain reason (never a
    // raw exception / field name). Transaction-scoped; reset at the start of
    // every reconcile.
    @TestVisible
    private static Set<Id> skippedMasterPackageIds = new Set<Id>();
    @TestVisible
    private static Map<Id, String> skippedMasterPackageReasons = new Map<Id, String>();

    /**
     * Test-only seam: master Package_Term__c ids whose dealer mirror row is
     * forced to carry a value the dealer metadata rejects, exercising the
     * defensive skip/flag path without touching org metadata. Production never
     * sets this (stays null).
     */
    @TestVisible
    private static Set<Id> forcedRejectMasterTermIds;
    private static final String FORCED_REJECT_VALUE = 'ZZ-Injected-Invalid-ZZ';

    /**
     * Plain reasons (keyed by master Package__c id) the last reconcile skipped
     * one or more mirror rows for. Empty when nothing was skipped. The console
     * maps this key to business words — this method never leaks a raw value.
     */
    public static Map<Id, String> getSkippedMirrorReasons() {
        return skippedMasterPackageReasons;
    }

    /** Records a rejected mirror row against the master Package it belongs to. */
    private static void noteMirrorFailure(SObject row, Map<Id, Id> masterPackageByDealerPackage) {
        if (row == null || masterPackageByDealerPackage == null) return;
        Id dealerPackageId = (Id) row.get('Dealer_Package__c');
        Id masterPackageId = dealerPackageId == null ? null : masterPackageByDealerPackage.get(dealerPackageId);
        if (masterPackageId == null) return;
        skippedMasterPackageIds.add(masterPackageId);
        if (!skippedMasterPackageReasons.containsKey(masterPackageId)) {
            skippedMasterPackageReasons.put(masterPackageId, 'MIRROR_VALUE_REJECTED');
        }
    }

    private DealerPackageSyncService() {}

    // =========================================================================
    // Public entry points
    // =========================================================================

    /**
     * Full idempotent reconcile of the given dealer mirrors.
     * Creates missing children and refreshes structure + derived prices.
     */
    public static void reconcileDealerPackages(Set<Id> dealerPackageIds) {
        if (dealerPackageIds == null || dealerPackageIds.isEmpty()) return;
        if (syncInProgress) return;
        syncInProgress = true;
        skippedMasterPackageIds.clear();
        skippedMasterPackageReasons.clear();
        try {
            reconcile(new List<Id>(dealerPackageIds));
        } finally {
            syncInProgress = false;
        }
    }

    /**
     * Master-change propagation: a master Package__c (or any of its children)
     * changed → reconcile every dealer mirror of that master package.
     * One run refreshes all affected dealer copies; re-runs duplicate nothing.
     */
    public static void reconcileForMasterPackage(Set<Id> masterPackageIds) {
        Set<Id> dpIds = affectedDealerPackagesByMasterPackage(masterPackageIds);
        reconcileDealerPackages(dpIds);
    }

    /** Master Package_Tier__c changed (structure/band) → reconcile affected mirrors. */
    public static void reconcileForMasterTier(Set<Id> masterTierIds) {
        Set<Id> dpIds = affectedDealerPackagesByMasterTier(masterTierIds);
        reconcileDealerPackages(dpIds);
    }

    /** Master Package_Term__c changed (wholesale Price__c / restrictions) → reconcile affected mirrors. */
    public static void reconcileForMasterTerm(Set<Id> masterTermIds) {
        Set<Id> dpIds = affectedDealerPackagesByMasterTerm(masterTermIds);
        reconcileDealerPackages(dpIds);
    }

    /** Master Package_Option__c changed (price/structure) → reconcile affected mirrors. */
    public static void reconcileForMasterOption(Set<Id> masterOptionIds) {
        Set<Id> dpIds = affectedDealerPackagesByMasterOption(masterOptionIds);
        reconcileDealerPackages(dpIds);
    }

    // =========================================================================
    // Bulk assign — change plan §09.1 (admin LWC dealerPortalBulkAssign)
    // =========================================================================

    public class BulkAssignResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Boolean dryRun;
        @AuraEnabled public String scope;            // 'ALL' | 'FAMILY'
        @AuraEnabled public Integer totalDealersConsidered;
        @AuraEnabled public Integer alreadyAssigned; // dealers that already have this master package
        @AuraEnabled public Integer toAssign;        // dealers the run would create a mirror for
        @AuraEnabled public Integer newlyAssigned;   // populated on a real (non-dry) run
        @AuraEnabled public String batchJobId;       // set when the run was enqueued as a batch

        public BulkAssignResult() {
            success = false;
            dryRun = false;
            scope = 'ALL';
            totalDealersConsidered = 0;
            alreadyAssigned = 0;
            toAssign = 0;
            newlyAssigned = 0;
        }
    }

    /**
     * Create a Dealer_Package__c mirror for every eligible active Dealer Account
     * for the given master Package__c (one per dealer; existing mirrors are
     * skipped so re-runs are safe).
     *
     * @param packageId master Package__c id
     * @param scope     'ALL'    → every Dealer Account
     *                  'FAMILY' → dealers already selling the package's plan
     *                             family (they hold a mirror of another package
     *                             in the same Package_Group__c)
     * @param dryRun    true → return counts only, no DML
     *
     * Small candidate sets run inline; large sets enqueue
     * BulkAssignBatch (Database.Batchable) and return the job id.
     */
    @AuraEnabled
    public static BulkAssignResult assignPlanToAllDealers(Id packageId, String scope, Boolean dryRun) {
        BulkAssignResult result = new BulkAssignResult();
        result.dryRun = dryRun == true;
        result.scope = String.isBlank(scope) ? 'ALL' : scope;

        try {
            if (packageId == null) {
                result.message = 'A master Package is required.';
                return result;
            }
            List<Package__c> masters = [
                SELECT Id, Name, RecordTypeId, RecordType.DeveloperName, Package_Group__c
                FROM Package__c
                WHERE Id = :packageId
                LIMIT 1
            ];
            if (masters.isEmpty()) {
                result.message = 'Master package not found.';
                return result;
            }
            Package__c master = masters[0];

            List<Id> candidateDealerIds = candidateDealers(master, result.scope);
            result.totalDealersConsidered = candidateDealerIds.size();

            // Dealers that already hold a mirror of this master package.
            Set<Id> existing = new Set<Id>();
            for (Dealer_Package__c dp : [
                SELECT Dealer__c FROM Dealer_Package__c
                WHERE Package__c = :packageId AND Dealer__c != null
            ]) {
                existing.add(dp.Dealer__c);
            }
            result.alreadyAssigned = existing.size();

            List<Id> toCreate = new List<Id>();
            for (Id dealerId : candidateDealerIds) {
                if (!existing.contains(dealerId)) toCreate.add(dealerId);
            }
            result.toAssign = toCreate.size();

            if (result.dryRun || toCreate.isEmpty()) {
                result.success = true;
                result.message = result.dryRun
                    ? 'Dry run: ' + toCreate.size() + ' dealer(s) would be assigned.'
                    : 'All ' + candidateDealerIds.size() + ' eligible dealer(s) already have this plan.';
                result.newlyAssigned = 0;
                return result;
            }

            if (toCreate.size() <= 200) {
                result.newlyAssigned = createDealerMirrors(master, toCreate);
                result.success = true;
                result.message = 'Assigned to ' + result.newlyAssigned + ' dealer(s).';
            } else {
                result.batchJobId = Database.executeBatch(
                    new DealerPackageBulkAssignBatch(master.Id, toCreate),
                    200
                );
                result.success = true;
                result.message = 'Bulk assign enqueued for ' + toCreate.size() + ' dealer(s) (job ' + result.batchJobId + ').';
            }
            return result;
        } catch (Exception e) {
            result.message = 'Error: ' + e.getMessage();
            return result;
        }
    }

    // =========================================================================
    // Internals
    // =========================================================================

    /** Eligible dealers: all Dealer Accounts, or (FAMILY) those already selling the plan family. */
    private static List<Id> candidateDealers(Package__c master, String scope) {
        Set<Id> familyPackageIds = new Set<Id>();
        if (scope == 'FAMILY' && master.Package_Group__c != null) {
            for (Package__c p : [
                SELECT Id FROM Package__c WHERE Package_Group__c = :master.Package_Group__c
            ]) {
                familyPackageIds.add(p.Id);
            }
        }

        Map<Id, Account> dealerMap = new Map<Id, Account>([
            SELECT Id FROM Account
            WHERE RecordType.DeveloperName = 'Dealer_Account'
            ORDER BY Id
        ]);
        if (scope != 'FAMILY') return new List<Id>(dealerMap.keySet());

        // FAMILY scope: dealers holding a mirror of any package in the family.
        Set<Id> familyDealers = new Set<Id>();
        for (Dealer_Package__c dp : [
            SELECT Dealer__c FROM Dealer_Package__c
            WHERE Package__c IN :familyPackageIds AND Dealer__c != null
        ]) {
            familyDealers.add(dp.Dealer__c);
        }
        List<Id> result = new List<Id>();
        for (Id d : dealerMap.keySet()) {
            if (familyDealers.contains(d)) result.add(d);
        }
        return result;
    }

    /** Creates Dealer_Package__c header rows; the after-insert trigger builds the mirror children. */
    public static Integer createDealerMirrors(Package__c master, List<Id> dealerIds) {
        List<Dealer_Package__c> mirrors = buildMirrorHeaders(master, dealerIds);
        insert mirrors;
        return mirrors.size();
    }

    /**
     * P7 console gap-create: build headers for SEVERAL master packages for ONE
     * dealer in a single DML statement, so the after-insert fan-out reconciles
     * all of them in one bulk pass (one trigger invocation, one reconcile run —
     * see the §4.2 budget table). Idempotent callers must pre-check mirror
     * existence; this method inserts blindly.
     */
    public static Integer createDealerMirrorsForDealer(List<Package__c> masters, Id dealerId) {
        List<Dealer_Package__c> mirrors = new List<Dealer_Package__c>();
        for (Package__c master : masters) {
            if (master == null) continue;
            mirrors.addAll(buildMirrorHeaders(master, new List<Id>{ dealerId }));
        }
        if (mirrors.isEmpty()) return 0;
        insert mirrors;
        return mirrors.size();
    }

    private static List<Dealer_Package__c> buildMirrorHeaders(Package__c master, List<Id> dealerIds) {
        String dealerRTDevName = RECORD_TYPE_MAP.get(master.RecordType != null ? master.RecordType.DeveloperName : null);
        Id dealerRTId = null;
        if (dealerRTDevName != null) {
            dealerRTId = Schema.SObjectType.Dealer_Package__c.getRecordTypeInfosByDeveloperName()
                .get(dealerRTDevName)?.getRecordTypeId();
        }
        // Name uniqueness: Dealer_Package__c.Name is not unique, but keep the mirror name readable.
        List<Dealer_Package__c> mirrors = new List<Dealer_Package__c>();
        for (Id dealerId : dealerIds) {
            mirrors.add(new Dealer_Package__c(
                Name = master.Name,
                Dealer__c = dealerId,
                Package__c = master.Id,
                RecordTypeId = dealerRTId,
                // P7 watermark: a freshly gap-created mirror is born "as fresh as
                // now" — the after-insert reconcile bumps it again at the end of
                // the same transaction (see reconcile()).
                Last_Synced_At__c = System.now()
            ));
        }
        return mirrors;
    }

    // -------------------------------------------------------------------------
    // Full reconcile
    // -------------------------------------------------------------------------

    private static void reconcile(List<Id> dealerPackageIds) {
        if (dealerPackageIds.isEmpty()) return;

        Map<Id, Dealer_Package__c> dps = new Map<Id, Dealer_Package__c>([
            SELECT Id, Name, Dealer__c, Package__c, Plan_Type__c, RecordTypeId,
                   Deductable__c, Per_Claim_Limit__c, Package_Description__c, Class__c,
                   Commercial_Vehicle_Surcharge_Fee__c
            FROM Dealer_Package__c
            WHERE Id IN :dealerPackageIds
        ]);

        Set<Id> masterPackageIds = new Set<Id>();
        Map<Id, Id> masterPackageByDealerPackage = new Map<Id, Id>();
        for (Dealer_Package__c dp : dps.values()) {
            if (dp.Package__c != null) {
                masterPackageIds.add(dp.Package__c);
                masterPackageByDealerPackage.put(dp.Id, dp.Package__c);
            }
        }
        if (masterPackageIds.isEmpty()) return;

        Map<Id, Package__c> masters = new Map<Id, Package__c>([
            SELECT Id, Name, RecordTypeId, RecordType.DeveloperName, Package_Group__c,
                   Coverage_per_claim__c, Deductible__c, Description__c, Class__c,
                   Commercial_Business_Use__c, Commercial_Vehicle_Type__c,
                   Commercial_Vehicle_Surcharge_Fee__c
            FROM Package__c
            WHERE Id IN :masterPackageIds
        ]);

        // ---- 1. Header mirror refresh (structure only; Dealer__c / rollups / Package__c untouched) ----
        Map<String, Id> dealerRTByDevName = new Map<String, Id>();
        for (RecordType rt : [
            SELECT Id, DeveloperName FROM RecordType WHERE SobjectType = 'Dealer_Package__c'
        ]) {
            dealerRTByDevName.put(rt.DeveloperName, rt.Id);
        }

        List<Dealer_Package__c> headerUpdates = new List<Dealer_Package__c>();
        for (Dealer_Package__c dp : dps.values()) {
            Package__c m = masters.get(dp.Package__c);
            if (m == null) continue;
            Dealer_Package__c u = new Dealer_Package__c(Id = dp.Id);
            Boolean dirty = false;

            if (dp.Name != m.Name) { u.Name = m.Name; dirty = true; }

            String mappedRTDev = RECORD_TYPE_MAP.get(m.RecordType != null ? m.RecordType.DeveloperName : null);
            Id mappedRTId = mappedRTDev != null ? dealerRTByDevName.get(mappedRTDev) : null;
            if (mappedRTId != null && dp.RecordTypeId != mappedRTId) { u.RecordTypeId = mappedRTId; dirty = true; }

            if (dp.Plan_Type__c != m.Package_Group__c) { u.Plan_Type__c = m.Package_Group__c; dirty = true; }
            if (dp.Class__c != m.Class__c) { u.Class__c = m.Class__c; dirty = true; }
            if (dp.Per_Claim_Limit__c != m.Coverage_per_claim__c) { u.Per_Claim_Limit__c = m.Coverage_per_claim__c; dirty = true; }
            if (dp.Deductable__c != m.Deductible__c) { u.Deductable__c = m.Deductible__c; dirty = true; }

            // Package description: mirror master description; never wipe a populated
            // dealer description with a blank master value.
            if (String.isNotBlank(m.Description__c) && dp.Package_Description__c != m.Description__c) {
                u.Package_Description__c = m.Description__c;
                dirty = true;
            }

            // Commercial_Business_Use__c and Commercial_Vehicle_Type__c are
            // FORMULA fields mirroring Package__r.* (org fact) — live already,
            // never written. Only the stored surcharge mirror is refreshed.
            Boolean masterCommercial = m.Commercial_Business_Use__c == true;
            Decimal surcharge = masterCommercial ? m.Commercial_Vehicle_Surcharge_Fee__c : null;
            if (dp.Commercial_Vehicle_Surcharge_Fee__c != surcharge) { u.Commercial_Vehicle_Surcharge_Fee__c = surcharge; dirty = true; }

            if (dirty) headerUpdates.add(u);
        }
        if (!headerUpdates.isEmpty()) update headerUpdates;

        // ---- 2. Tiers ----
        Map<Id, List<Package_Tier__c>> tiersByPackage = new Map<Id, List<Package_Tier__c>>();
        for (Package_Tier__c t : [
            SELECT Id, Name, Package__c, Mileage_Restriction_Start__c, Mileage_Restriction_End__c,
                   Mileage_Unit__c, Financed_Interest_Rate_Min__c, Financed_Interest_Rate_Max__c,
                   Minimum_Financed_Amount__c, Maximum_Financed_Amount__c
            FROM Package_Tier__c
            WHERE Package__c IN :masterPackageIds
            ORDER BY Name
        ]) {
            if (!tiersByPackage.containsKey(t.Package__c)) tiersByPackage.put(t.Package__c, new List<Package_Tier__c>());
            tiersByPackage.get(t.Package__c).add(t);
        }

        Map<String, Dealer_Package_Tier__c> existingTiers = new Map<String, Dealer_Package_Tier__c>();
        for (Dealer_Package_Tier__c t : [
            SELECT Id, Dealer_Package__c, Package_Tier__c, Name, Minimum__c, Maximum__c,
                   Mileage_Unit__c, Interest_Rate_Min__c, Interest_Rate_Max__c,
                   Minimum_Financed_Amount__c, Maximum_Financed_Amount__c
            FROM Dealer_Package_Tier__c
            WHERE Dealer_Package__c IN :dealerPackageIds AND Package_Tier__c != null
        ]) {
            existingTiers.put(t.Dealer_Package__c + '_' + t.Package_Tier__c, t);
        }

        List<Dealer_Package_Tier__c> tierInserts = new List<Dealer_Package_Tier__c>();
        List<Dealer_Package_Tier__c> tierUpdates = new List<Dealer_Package_Tier__c>();
        // composite key (master tier id + '_' + dealer package id) → dealer tier id
        Map<String, Id> dealerTierIdByKey = new Map<String, Id>();

        for (Dealer_Package__c dp : dps.values()) {
            List<Package_Tier__c> mtiers = dp.Package__c != null ? tiersByPackage.get(dp.Package__c) : null;
            if (mtiers == null) continue;
            for (Package_Tier__c mt : mtiers) {
                String key = dp.Id + '_' + mt.Id;
                Dealer_Package_Tier__c existing = existingTiers.get(key);
                if (existing == null) {
                    Dealer_Package_Tier__c nt = new Dealer_Package_Tier__c(
                        Name = mt.Name,
                        Dealer_Package__c = dp.Id,
                        Package_Tier__c = mt.Id
                    );
                    applyTierMirror(nt, mt);
                    tierInserts.add(nt);
                } else {
                    Dealer_Package_Tier__c ut = new Dealer_Package_Tier__c(Id = existing.Id);
                    Boolean dirty = false;
                    if (existing.Name != mt.Name) { ut.Name = mt.Name; dirty = true; }
                    dirty = applyTierMirrorCompared(existing, ut, mt) || dirty;
                    if (dirty) tierUpdates.add(ut);
                    dealerTierIdByKey.put(key, existing.Id);
                }
            }
        }
        if (!tierInserts.isEmpty()) {
            Database.SaveResult[] tierResults = Database.insert(tierInserts, false);
            for (Integer i = 0; i < tierResults.size(); i++) {
                if (!tierResults[i].isSuccess()) {
                    noteMirrorFailure(tierInserts[i], masterPackageByDealerPackage);
                    continue;
                }
                Dealer_Package_Tier__c nt = tierInserts[i];
                dealerTierIdByKey.put(nt.Dealer_Package__c + '_' + nt.Package_Tier__c, nt.Id);
            }
        }
        if (!tierUpdates.isEmpty()) {
            Database.SaveResult[] tierUpd = Database.update(tierUpdates, false);
            for (Integer i = 0; i < tierUpd.size(); i++) {
                if (!tierUpd[i].isSuccess()) noteMirrorFailure(tierUpdates[i], masterPackageByDealerPackage);
            }
        }

        // ---- 3. Terms ----
        Set<Id> masterTierIds = new Set<Id>();
        for (List<Package_Tier__c> tierList : tiersByPackage.values()) {
            for (Package_Tier__c t : tierList) masterTierIds.add(t.Id);
        }

        Map<Id, List<Package_Term__c>> termsByTier = new Map<Id, List<Package_Term__c>>();
        if (!masterTierIds.isEmpty()) {
            for (Package_Term__c term : [
                SELECT Id, Name, Package_Tier__c, Price__c, Month__c, Mileage__c, Mileage_Unit__c,
                       ByYear__c, Class__c, Premium_Model_Fee__c, Mileage_Restriction__c,
                       Mileage_Restriction_Start__c, Mileage_Restriction_End__c,
                       Restriction_Type__c, Duration_Type__c, Start_Term__c, Expiry_Term__c,
                       Odometer_KM__c, Allow_Deferral__c, Vehicle_Sub_Type__c
                FROM Package_Term__c
                WHERE Package_Tier__c IN :masterTierIds
                ORDER BY Name
            ]) {
                if (!termsByTier.containsKey(term.Package_Tier__c)) termsByTier.put(term.Package_Tier__c, new List<Package_Term__c>());
                termsByTier.get(term.Package_Tier__c).add(term);
            }
        }

        // C1 (tier-opt-in): a master term with NO Package_Tier__c is its own
        // sellable catalogue row — the tier is an optional availability band, not
        // a required parent. Mirror it package-keyed (not tier-keyed) to every
        // dealer mirror of its master package, with a null dealer tier. The
        // tiered pass above is untouched (Diamond keeps its tier bands and its
        // term set byte-for-byte).
        Map<Id, List<Package_Term__c>> tierlessTermsByPackage = new Map<Id, List<Package_Term__c>>();
        for (Package_Term__c term : [
            SELECT Id, Name, Package__c, Package_Tier__c, Price__c, Month__c, Mileage__c, Mileage_Unit__c,
                   ByYear__c, Class__c, Premium_Model_Fee__c, Mileage_Restriction__c,
                   Mileage_Restriction_Start__c, Mileage_Restriction_End__c,
                   Restriction_Type__c, Duration_Type__c, Start_Term__c, Expiry_Term__c,
                   Odometer_KM__c, Allow_Deferral__c, Vehicle_Sub_Type__c
            FROM Package_Term__c
            WHERE Package__c IN :masterPackageIds AND Package_Tier__c = null
            ORDER BY Name
        ]) {
            if (!tierlessTermsByPackage.containsKey(term.Package__c)) tierlessTermsByPackage.put(term.Package__c, new List<Package_Term__c>());
            tierlessTermsByPackage.get(term.Package__c).add(term);
        }

        Map<String, Dealer_Package_Term__c> existingTerms = new Map<String, Dealer_Package_Term__c>();
        for (Dealer_Package_Term__c t : [
            SELECT Id, Dealer_Package__c, Dealer_Package_Tier__c, Package_Tier__c, Package_Term__c,
                   Name, Month__c, Mileage__c, Mileage_Unit__c, ByYear__c, Class__c,
                   Premium_Model_Fee__c, Mileage_Restriction__c, Mileage_Restriction_Start__c,
                   Mileage_Restriction_End__c, Restriction_Type__c, Duration_Type__c,
                   Start_Term__c, Expiry_Term__c, Odometer_KM__c,
                   Original_Package_Term_Cost__c,
                   Markup__c, Markup_Type__c, Discount_Type__c, Discount_Value__c, Sales_Rep_Incentive__c
            FROM Dealer_Package_Term__c
            WHERE Dealer_Package__c IN :dealerPackageIds AND Package_Term__c != null
        ]) {
            existingTerms.put(t.Dealer_Package__c + '_' + t.Package_Term__c, t);
        }

        List<Dealer_Package_Term__c> termInserts = new List<Dealer_Package_Term__c>();
        List<Dealer_Package_Term__c> termUpdates = new List<Dealer_Package_Term__c>();
        // dealer package → (dealer tier id) per master tier — needed for term creation
        Map<String, Id> dealerTermIdByKey = new Map<String, Id>();

        for (Dealer_Package__c dp : dps.values()) {
            List<Package_Tier__c> mtiers = dp.Package__c != null ? tiersByPackage.get(dp.Package__c) : null;
            if (mtiers == null) continue;
            for (Package_Tier__c mt : mtiers) {
                List<Package_Term__c> mterms = termsByTier.get(mt.Id);
                if (mterms == null) continue;
                Id dealerTierId = dealerTierIdByKey.get(dp.Id + '_' + mt.Id);
                for (Package_Term__c mterm : mterms) {
                    String key = dp.Id + '_' + mterm.Id;
                    Dealer_Package_Term__c existing = existingTerms.get(key);
                    if (existing == null) {
                        Dealer_Package_Term__c nt = new Dealer_Package_Term__c(
                            Name = mterm.Name,
                            Dealer_Package__c = dp.Id,
                            Package_Term__c = mterm.Id,
                            Dealer_Package_Tier__c = dealerTierId,
                            Package_Tier__c = mt.Id
                        );
                        applyTermMirror(nt, mterm);
                        // Test seam: simulate a dealer-side metadata gap (a master
                        // value the dealer catalogue rejects) to exercise the
                        // defensive skip/flag path. Production never sets it.
                        if (Test.isRunningTest() && forcedRejectMasterTermIds != null
                            && forcedRejectMasterTermIds.contains(mterm.Id)) {
                            nt.Restriction_Type__c = FORCED_REJECT_VALUE;
                        }
                        termInserts.add(nt);
                    } else {
                        Dealer_Package_Term__c ut = new Dealer_Package_Term__c(Id = existing.Id);
                        Boolean dirty = false;
                        dirty = applyTermMirrorCompared(existing, ut, mterm) || dirty;
                        if (dirty) termUpdates.add(ut);
                        dealerTermIdByKey.put(key, existing.Id);
                    }
                }
            }
        }

        // C1 (continued): mirror the tier-less master terms (null dealer tier /
        // null master-tier link). Existing dealer rows are matched by the same
        // dp.Id + '_' + masterTerm.Id idempotency key, so re-runs duplicate
        // nothing. Term-level options follow automatically once
        // dealerTermIdByKey is populated below — the options pass resolves a
        // term-level Optional option through it and includes it only when
        // non-null.
        for (Dealer_Package__c dp : dps.values()) {
            List<Package_Term__c> tlessTerms = dp.Package__c != null ? tierlessTermsByPackage.get(dp.Package__c) : null;
            if (tlessTerms == null) continue;
            for (Package_Term__c mterm : tlessTerms) {
                String key = dp.Id + '_' + mterm.Id;
                Dealer_Package_Term__c existing = existingTerms.get(key);
                if (existing == null) {
                    Dealer_Package_Term__c nt = new Dealer_Package_Term__c(
                        Name = mterm.Name,
                        Dealer_Package__c = dp.Id,
                        Package_Term__c = mterm.Id,
                        Dealer_Package_Tier__c = null,
                        Package_Tier__c = null
                    );
                    applyTermMirror(nt, mterm);
                    // Same test seam as the tiered pass (defensive skip exercise).
                    if (Test.isRunningTest() && forcedRejectMasterTermIds != null
                        && forcedRejectMasterTermIds.contains(mterm.Id)) {
                        nt.Restriction_Type__c = FORCED_REJECT_VALUE;
                    }
                    termInserts.add(nt);
                } else {
                    Dealer_Package_Term__c ut = new Dealer_Package_Term__c(Id = existing.Id);
                    Boolean dirty = false;
                    dirty = applyTermMirrorCompared(existing, ut, mterm) || dirty;
                    if (dirty) termUpdates.add(ut);
                    dealerTermIdByKey.put(key, existing.Id);
                }
            }
        }

        if (!termInserts.isEmpty()) {
            Database.SaveResult[] termResults = Database.insert(termInserts, false);
            for (Integer i = 0; i < termResults.size(); i++) {
                if (!termResults[i].isSuccess()) {
                    noteMirrorFailure(termInserts[i], masterPackageByDealerPackage);
                    continue;
                }
                Dealer_Package_Term__c nt = termInserts[i];
                dealerTermIdByKey.put(nt.Dealer_Package__c + '_' + nt.Package_Term__c, nt.Id);
            }
        }
        if (!termUpdates.isEmpty()) {
            Database.SaveResult[] termUpd = Database.update(termUpdates, false);
            for (Integer i = 0; i < termUpd.size(); i++) {
                if (!termUpd[i].isSuccess()) noteMirrorFailure(termUpdates[i], masterPackageByDealerPackage);
            }
        }

        // ---- 4. Options (record-type-specific selection semantics preserved) ----
        Map<Id, Package__c> packageRT = new Map<Id, Package__c>();
        for (Package__c m : masters.values()) {
            packageRT.put(m.Id, m);
        }

        Map<Id, List<Package_Option__c>> optionsByPackage = new Map<Id, List<Package_Option__c>>();
        for (Package_Option__c o : [
            SELECT Id, Name, Package__c, Package_Term__c, Option__c, Selection_Type__c,
                   Inclusion_Text__c, Exclusion_Text__c, Price__c, Category__c,
                   Minimum_Value__c, Maximum_Value__c
            FROM Package_Option__c
            WHERE Package__c IN :masterPackageIds
            ORDER BY Name
        ]) {
            if (!optionsByPackage.containsKey(o.Package__c)) optionsByPackage.put(o.Package__c, new List<Package_Option__c>());
            optionsByPackage.get(o.Package__c).add(o);
        }

        // ---- 4b. Term-anchored options (option (b), p8) ----
        // PackageOptionMaintenanceService sets Package_Term__c and NOT Package__c
        // for a term launch, so the package-keyed query above never sees those
        // rows — term-level Additional options silently failed to mirror. Resolve
        // each master term to its package and fold the row in under the resolved
        // package, so the record-type include rules below treat it exactly like
        // any other option.
        //
        // Resolution order (tier route first, direct Package__c fallback) mirrors
        // both PackageOptionMaintenanceService.createPackageOptions and the way
        // the term passes above build the dealer term mirrors — the tiered pass
        // links a both-links term to the TIER's package, so the tier route must
        // win here or the dealerTermIdByKey lookup below would miss.
        Map<Id, Id> packageByTier = new Map<Id, Id>();
        for (Id pkgId : tiersByPackage.keySet()) {
            for (Package_Tier__c t : tiersByPackage.get(pkgId)) {
                packageByTier.put(t.Id, pkgId);
            }
        }
        Map<Id, Id> packageByTerm = new Map<Id, Id>();
        // Tier-less terms (direct Package__c link) first …
        for (Id pkgId : tierlessTermsByPackage.keySet()) {
            for (Package_Term__c term : tierlessTermsByPackage.get(pkgId)) {
                packageByTerm.put(term.Id, pkgId);
            }
        }
        // … then tiered terms, so the tier route wins on any overlap.
        for (Id tierId : termsByTier.keySet()) {
            Id pkgId = packageByTier.get(tierId);
            if (pkgId == null) continue;
            for (Package_Term__c term : termsByTier.get(tierId)) {
                packageByTerm.put(term.Id, pkgId);
            }
        }

        // Only the term-anchored case is added (Package__c = null AND
        // Package_Term__c set). Package-keyed rows are untouched, so no row that
        // did not previously mirror starts mirroring except this one.
        if (!packageByTerm.isEmpty()) {
            for (Package_Option__c o : [
                SELECT Id, Name, Package__c, Package_Term__c, Option__c, Selection_Type__c,
                       Inclusion_Text__c, Exclusion_Text__c, Price__c, Category__c,
                       Minimum_Value__c, Maximum_Value__c
                FROM Package_Option__c
                WHERE Package__c = null AND Package_Term__c IN :packageByTerm.keySet()
                ORDER BY Name
            ]) {
                Id resolvedPkg = packageByTerm.get(o.Package_Term__c);
                if (resolvedPkg == null || !masterPackageIds.contains(resolvedPkg)) continue;
                if (!optionsByPackage.containsKey(resolvedPkg)) optionsByPackage.put(resolvedPkg, new List<Package_Option__c>());
                optionsByPackage.get(resolvedPkg).add(o);
            }
        }

        Map<String, Dealer_Package_Option__c> existingOptions = new Map<String, Dealer_Package_Option__c>();
        for (Dealer_Package_Option__c o : [
            SELECT Id, Dealer_Package__c, Dealer_Package_Term__c, Package_Option__c, Option__c,
                   Selection_Type__c, Inclusion__c, Exclusion__c, Category__c,
                   Minimum_Value__c, Maximum_Value__c,
                   Original_Package_Option_Price__c, Dealer_Markup__c, Markup_Type__c,
                   Discount_Type__c, Discount_Value__c
            FROM Dealer_Package_Option__c
            WHERE Dealer_Package__c IN :dealerPackageIds AND Package_Option__c != null
        ]) {
            existingOptions.put(o.Dealer_Package__c + '_' + o.Package_Option__c, o);
        }

        List<Dealer_Package_Option__c> optionInserts = new List<Dealer_Package_Option__c>();
        List<Dealer_Package_Option__c> optionUpdates = new List<Dealer_Package_Option__c>();

        for (Dealer_Package__c dp : dps.values()) {
            if (dp.Package__c == null) continue;
            Package__c m = packageRT.get(dp.Package__c);
            List<Package_Option__c> moptions = optionsByPackage.get(dp.Package__c);
            if (moptions == null) continue;
            String rtDevName = m != null && m.RecordType != null ? m.RecordType.DeveloperName : null;

            for (Package_Option__c mo : moptions) {
                // Faithful reproduction of the pre-P2 copy rules:
                Boolean include = false;
                Id dealerTermId = null; // null = package-level option

                if (rtDevName == 'Car_Loan_Protection') {
                    include = mo.Selection_Type__c == 'Optional' && mo.Package_Term__c == null;
                } else if (rtDevName == 'Gap_Coverage') {
                    // Included + Optional both copied at package level for Total Loss.
                    include = mo.Package_Term__c == null;
                } else {
                    if (mo.Selection_Type__c == 'Included' && mo.Package_Term__c == null) {
                        include = true; // package-level included
                    } else if (mo.Selection_Type__c == 'Optional' && mo.Package_Term__c != null) {
                        // term-level optional → attach to the dealer term mirror
                        dealerTermId = dealerTermIdByKey.get(dp.Id + '_' + mo.Package_Term__c);
                        include = dealerTermId != null;
                    }
                }
                if (!include) continue;

                String key = dp.Id + '_' + mo.Id;
                Dealer_Package_Option__c existing = existingOptions.get(key);
                if (existing == null) {
                    // Dealer_Package_Option__c.Name is Auto Number (not writable).
                    Dealer_Package_Option__c no = new Dealer_Package_Option__c(
                        Dealer_Package__c = dp.Id,
                        Package_Option__c = mo.Id,
                        Option__c = mo.Option__c,
                        Dealer_Package_Term__c = dealerTermId
                    );
                    applyOptionMirror(no, mo, rtDevName);
                    optionInserts.add(no);
                } else {
                    Dealer_Package_Option__c uo = new Dealer_Package_Option__c(Id = existing.Id);
                    Boolean dirty = applyOptionMirrorCompared(existing, uo, mo, rtDevName);
                    if (dirty) optionUpdates.add(uo);
                }
            }
        }
        if (!optionInserts.isEmpty()) {
            Database.SaveResult[] optionResults = Database.insert(optionInserts, false);
            for (Integer i = 0; i < optionResults.size(); i++) {
                if (!optionResults[i].isSuccess()) noteMirrorFailure(optionInserts[i], masterPackageByDealerPackage);
            }
        }
        if (!optionUpdates.isEmpty()) {
            Database.SaveResult[] optionUpd = Database.update(optionUpdates, false);
            for (Integer i = 0; i < optionUpd.size(); i++) {
                if (!optionUpd[i].isSuccess()) noteMirrorFailure(optionUpdates[i], masterPackageByDealerPackage);
            }
        }

        // ---- 5. Watermark commit (P7 console contract) ----
        // Last_Synced_At__c = now for every reconciled dealer package, inside the
        // same transaction as the child sync — all-or-nothing, so the console's
        // staleness read can never observe a half-synced mirror as "current".
        // The watermark forces one header update even when nothing else was dirty
        // (cheap). It cannot loop the trigger: DealerPackageTrigger's after-update
        // path only re-syncs when Package__c changed (never true here) and is
        // additionally flag-gated and re-entrancy-guarded.
        List<Dealer_Package__c> watermarkTouches = new List<Dealer_Package__c>();
        for (Dealer_Package__c dp : dps.values()) {
            if (dp.Package__c != null && masters.containsKey(dp.Package__c)) {
                watermarkTouches.add(new Dealer_Package__c(
                    Id = dp.Id,
                    Last_Synced_At__c = System.now()
                ));
            }
        }
        if (!watermarkTouches.isEmpty()) update watermarkTouches;
    }

    // -------------------------------------------------------------------------
    // Mirror field application
    // -------------------------------------------------------------------------

    private static void applyTierMirror(Dealer_Package_Tier__c target, Package_Tier__c master) {
        target.Mileage_Unit__c = master.Mileage_Unit__c;
        target.Minimum__c = master.Mileage_Restriction_Start__c;
        target.Maximum__c = master.Mileage_Restriction_End__c;
        target.Interest_Rate_Min__c = master.Financed_Interest_Rate_Min__c;
        target.Interest_Rate_Max__c = master.Financed_Interest_Rate_Max__c;
        target.Minimum_Financed_Amount__c = master.Minimum_Financed_Amount__c;
        target.Maximum_Financed_Amount__c = master.Maximum_Financed_Amount__c;
    }

    private static Boolean applyTierMirrorCompared(Dealer_Package_Tier__c existing, Dealer_Package_Tier__c upd, Package_Tier__c master) {
        Boolean dirty = false;
        if (existing.Mileage_Unit__c != master.Mileage_Unit__c) { upd.Mileage_Unit__c = master.Mileage_Unit__c; dirty = true; }
        if (existing.Minimum__c != master.Mileage_Restriction_Start__c) { upd.Minimum__c = master.Mileage_Restriction_Start__c; dirty = true; }
        if (existing.Maximum__c != master.Mileage_Restriction_End__c) { upd.Maximum__c = master.Mileage_Restriction_End__c; dirty = true; }
        if (existing.Interest_Rate_Min__c != master.Financed_Interest_Rate_Min__c) { upd.Interest_Rate_Min__c = master.Financed_Interest_Rate_Min__c; dirty = true; }
        if (existing.Interest_Rate_Max__c != master.Financed_Interest_Rate_Max__c) { upd.Interest_Rate_Max__c = master.Financed_Interest_Rate_Max__c; dirty = true; }
        if (existing.Minimum_Financed_Amount__c != master.Minimum_Financed_Amount__c) { upd.Minimum_Financed_Amount__c = master.Minimum_Financed_Amount__c; dirty = true; }
        if (existing.Maximum_Financed_Amount__c != master.Maximum_Financed_Amount__c) { upd.Maximum_Financed_Amount__c = master.Maximum_Financed_Amount__c; dirty = true; }
        return dirty;
    }

    /**
     * Structure mirrors + derived prices from master wholesale + dealer markup.
     * Markup__c / Markup_Type__c / Discount_Type__c / Discount_Value__c /
     * Sales_Rep_Incentive__c are NEVER written here (dealer-local).
     */
    private static void applyTermMirror(Dealer_Package_Term__c target, Package_Term__c master) {
        target.Month__c = master.Month__c;
        target.Mileage__c = master.Mileage__c;
        target.Mileage_Unit__c = master.Mileage_Unit__c;
        target.ByYear__c = master.ByYear__c;
        target.Class__c = master.Class__c;
        target.Premium_Model_Fee__c = master.Premium_Model_Fee__c;
        target.Mileage_Restriction__c = master.Mileage_Restriction__c;
        target.Mileage_Restriction_Start__c = master.Mileage_Restriction_Start__c;
        target.Mileage_Restriction_End__c = master.Mileage_Restriction_End__c;
        target.Restriction_Type__c = master.Restriction_Type__c;
        target.Duration_Type__c = master.Duration_Type__c;
        target.Start_Term__c = master.Start_Term__c;
        target.Expiry_Term__c = master.Expiry_Term__c;
        target.Odometer_KM__c = master.Odometer_KM__c;
        if (master.Price__c != null) {
            // Net_Cost / Retail are formulas anchored on this stored snapshot.
            target.Original_Package_Term_Cost__c = master.Price__c;
        }
    }

    private static Boolean applyTermMirrorCompared(Dealer_Package_Term__c existing, Dealer_Package_Term__c upd, Package_Term__c master) {
        Boolean dirty = false;
        if (existing.Month__c != master.Month__c) { upd.Month__c = master.Month__c; dirty = true; }
        if (existing.Mileage__c != master.Mileage__c) { upd.Mileage__c = master.Mileage__c; dirty = true; }
        if (existing.Mileage_Unit__c != master.Mileage_Unit__c) { upd.Mileage_Unit__c = master.Mileage_Unit__c; dirty = true; }
        if (existing.ByYear__c != master.ByYear__c) { upd.ByYear__c = master.ByYear__c; dirty = true; }
        if (existing.Class__c != master.Class__c) { upd.Class__c = master.Class__c; dirty = true; }
        if (existing.Premium_Model_Fee__c != master.Premium_Model_Fee__c) { upd.Premium_Model_Fee__c = master.Premium_Model_Fee__c; dirty = true; }
        if (existing.Mileage_Restriction__c != master.Mileage_Restriction__c) { upd.Mileage_Restriction__c = master.Mileage_Restriction__c; dirty = true; }
        if (existing.Mileage_Restriction_Start__c != master.Mileage_Restriction_Start__c) { upd.Mileage_Restriction_Start__c = master.Mileage_Restriction_Start__c; dirty = true; }
        if (existing.Mileage_Restriction_End__c != master.Mileage_Restriction_End__c) { upd.Mileage_Restriction_End__c = master.Mileage_Restriction_End__c; dirty = true; }
        if (existing.Restriction_Type__c != master.Restriction_Type__c) { upd.Restriction_Type__c = master.Restriction_Type__c; dirty = true; }
        if (existing.Duration_Type__c != master.Duration_Type__c) { upd.Duration_Type__c = master.Duration_Type__c; dirty = true; }
        if (existing.Start_Term__c != master.Start_Term__c) { upd.Start_Term__c = master.Start_Term__c; dirty = true; }
        if (existing.Expiry_Term__c != master.Expiry_Term__c) { upd.Expiry_Term__c = master.Expiry_Term__c; dirty = true; }
        if (existing.Odometer_KM__c != master.Odometer_KM__c) { upd.Odometer_KM__c = master.Odometer_KM__c; dirty = true; }

        if (master.Price__c != null && existing.Original_Package_Term_Cost__c != master.Price__c) {
            upd.Original_Package_Term_Cost__c = master.Price__c;
            dirty = true;
        }
        return dirty;
    }

    private static void applyOptionMirror(Dealer_Package_Option__c target, Package_Option__c master, String packageRTDevName) {
        target.Selection_Type__c = master.Selection_Type__c;
        target.Inclusion__c = master.Inclusion_Text__c;
        target.Exclusion__c = master.Exclusion_Text__c;
        target.Category__c = master.Category__c;
        if (packageRTDevName == 'Gap_Coverage' && String.isBlank(target.Category__c)) {
            target.Category__c = 'Total Loss';
        }
        target.Minimum_Value__c = master.Minimum_Value__c;
        target.Maximum_Value__c = master.Maximum_Value__c;
        if (master.Price__c != null) {
            // Net_Cost / Retail are formulas anchored on this stored snapshot.
            target.Original_Package_Option_Price__c = master.Price__c;
        }
    }

    private static Boolean applyOptionMirrorCompared(Dealer_Package_Option__c existing, Dealer_Package_Option__c upd, Package_Option__c master, String packageRTDevName) {
        Boolean dirty = false;
        if (existing.Option__c != master.Option__c) { upd.Option__c = master.Option__c; dirty = true; }
        if (existing.Selection_Type__c != master.Selection_Type__c) { upd.Selection_Type__c = master.Selection_Type__c; dirty = true; }
        if (existing.Inclusion__c != master.Inclusion_Text__c) { upd.Inclusion__c = master.Inclusion_Text__c; dirty = true; }
        if (existing.Exclusion__c != master.Exclusion_Text__c) { upd.Exclusion__c = master.Exclusion_Text__c; dirty = true; }
        String wantCategory = master.Category__c;
        if (packageRTDevName == 'Gap_Coverage' && String.isBlank(wantCategory)) wantCategory = 'Total Loss';
        if (existing.Category__c != wantCategory) { upd.Category__c = wantCategory; dirty = true; }
        if (existing.Minimum_Value__c != master.Minimum_Value__c) { upd.Minimum_Value__c = master.Minimum_Value__c; dirty = true; }
        if (existing.Maximum_Value__c != master.Maximum_Value__c) { upd.Maximum_Value__c = master.Maximum_Value__c; dirty = true; }

        if (master.Price__c != null && existing.Original_Package_Option_Price__c != master.Price__c) {
            upd.Original_Package_Option_Price__c = master.Price__c;
            dirty = true;
        }
        return dirty;
    }

    // -------------------------------------------------------------------------
    // Affected-dealer resolution for master-driven propagation
    // -------------------------------------------------------------------------

    private static Set<Id> affectedDealerPackagesByMasterPackage(Set<Id> masterPackageIds) {
        Set<Id> dpIds = new Set<Id>();
        if (masterPackageIds == null || masterPackageIds.isEmpty()) return dpIds;
        for (Dealer_Package__c dp : [
            SELECT Id FROM Dealer_Package__c WHERE Package__c IN :masterPackageIds
        ]) {
            dpIds.add(dp.Id);
        }
        return dpIds;
    }

    private static Set<Id> affectedDealerPackagesByMasterTier(Set<Id> masterTierIds) {
        Set<Id> dpIds = new Set<Id>();
        if (masterTierIds == null || masterTierIds.isEmpty()) return dpIds;
        for (Dealer_Package_Tier__c t : [
            SELECT Dealer_Package__c FROM Dealer_Package_Tier__c
            WHERE Package_Tier__c IN :masterTierIds AND Dealer_Package__c != null
        ]) {
            dpIds.add(t.Dealer_Package__c);
        }
        return dpIds;
    }

    private static Set<Id> affectedDealerPackagesByMasterTerm(Set<Id> masterTermIds) {
        Set<Id> dpIds = new Set<Id>();
        if (masterTermIds == null || masterTermIds.isEmpty()) return dpIds;
        for (Dealer_Package_Term__c t : [
            SELECT Dealer_Package__c FROM Dealer_Package_Term__c
            WHERE Package_Term__c IN :masterTermIds AND Dealer_Package__c != null
        ]) {
            dpIds.add(t.Dealer_Package__c);
        }
        return dpIds;
    }

    private static Set<Id> affectedDealerPackagesByMasterOption(Set<Id> masterOptionIds) {
        Set<Id> dpIds = new Set<Id>();
        if (masterOptionIds == null || masterOptionIds.isEmpty()) return dpIds;
        for (Dealer_Package_Option__c o : [
            SELECT Dealer_Package__c FROM Dealer_Package_Option__c
            WHERE Package_Option__c IN :masterOptionIds AND Dealer_Package__c != null
        ]) {
            dpIds.add(o.Dealer_Package__c);
        }
        return dpIds;
    }
}