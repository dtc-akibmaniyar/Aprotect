/**
 * DealerPackageSyncController
 *
 * P7 — Dealer Package Sync Console backend (architecture doc
 * `Aprotect_Dealer_Sync_Architecture.md` §4.2). Admin-facing, internal-app
 * only. All methods are @AuraEnabled, DTO-in/DTO-out; no LWC-visible SOQL.
 *
 * Responsibilities
 * ────────────────
 *   • getSyncInventory(accountId) — one call returning the account's dealer
 *     package inventory: every dealer mirror with its staleness state
 *     (watermark rule, §3.2), every Active catalogue package not yet assigned
 *     to this dealer (gap-create candidates), and orphaned/inactive mirrors.
 *     Server-side only: the LWC never filters and never does date math.
 *   • createFromMaster(...)     — gap-create Dealer_Package__c headers for one
 *     dealer from chosen master packages (dry-run supported). The existing
 *     after-insert trigger fan-out (DealerPackageSyncService) builds the mirror
 *     children in the same transaction — the ONLY writer for children.
 *   • syncFromMaster(...)       — reconcile chosen dealer mirrors against their
 *     masters (dry-run supported) via DealerPackageSyncService.reconcileDealer
 *     Packages; the watermark (Last_Synced_At__c) commits in the same
 *     transaction (service §5). Sync NEVER writes dealer markup/discount/
 *     incentive fields and NEVER deletes anything (D3).
 *
 * Staleness rule (§3.2, locked): a dealer package needs sync when
 *     MAX(master Package__c.LastModifiedDate,
 *         MAX(Package_Tier__c.LastModifiedDate  GROUP BY Package__c),
 *         MAX(Package_Term__c.LastModifiedDate  GROUP BY Package__c),
 *         MAX(Package_Option__c.LastModifiedDate GROUP BY Package__c))
 *     > Dealer_Package__c.Last_Synced_At__c
 * Vehicle-schedule changes are deliberately excluded (informational only, D2).
 *
 * Catalogue eligibility (D1, locked): master Package__c eligible for the
 * "Available catalogue" list = Is_Active__c = true AND NOT part of a
 * Superseded release (Draft and Published both count; sandbox demo runs on
 * Draft rows). The valid-date-range check applies only where a release
 * Effective_Date__c exists. The whole predicate lives in the single isolated
 * method shouldShowInCatalogue() — tightening to published-only later is a
 * one-line change.
 *
 * Gating (D4): console WRITES (create/sync real runs) honour
 * PortalFeatureFlagService.isDealerSyncEnabled() (Dealer_Sync_Enabled__c);
 * reads and dry-runs are always allowed. `without sharing` (admin service
 * pattern) plus explicit Schema CRUD/FLS assertions so the action stays safe
 * if ever surfaced to a lesser profile.
 *
 * Plain-language labels (P7-e)
 * ────────────────────────────
 *   No raw API / object / field / record-type name ever reaches the console.
 *   Every user-facing string is produced here — the ONE place the mapping
 *   lives — and handed to the LWC as a ready label field on the DTO:
 *     - DTO label fields: recordTypeLabel, planTypeLabel, releaseLabel,
 *       countsLabel, scheduleLabel, statusLabel, primaryActionLabel,
 *       lastSyncedLabel, reason (all human-readable, built by label* helpers).
 *     - STATUS_LABELS / STATUS_TONES / ACTION_LABELS maps below hold the
 *       status → business-word mapping (Available to add / Already available /
 *       Update available). Change wording HERE, never in the component.
 *     - ChangeSummary.describe() renders the change set in business words.
 *   The LWC is a pure renderer: it prints label fields and never maps a
 *   technical name itself.
 */
public without sharing class DealerPackageSyncController {

    private static final String DEALER_ACCOUNT_RT = 'Dealer_Account';
    private static final String RT_CAR_LOAN = 'Car_Loan_Protection';
    private static final String RT_GAP = 'Gap_Coverage';

    // ── The ONE label map (business words; no API names) ────────────────────
    /** Unified-list status → the chip text the admin sees. */
    private static final Map<String, String> STATUS_LABELS = new Map<String, String>{
        'AvailableToAdd'   => 'Available to add',
        'AlreadyAvailable' => 'Already available',
        'UpdateAvailable'  => 'Update available'
    };
    /** Unified-list status → semantic tone token the LWC turns into a chip style. */
    private static final Map<String, String> STATUS_TONES = new Map<String, String>{
        'AvailableToAdd'   => 'new',
        'AlreadyAvailable' => 'ok',
        'UpdateAvailable'  => 'attention'
    };
    /** Row primary action → button text. */
    private static final Map<String, String> ACTION_LABELS = new Map<String, String>{
        'add'  => 'Add to dealer',
        'sync' => 'Sync now'
    };
    /** Mirror footer status → plain word (never the machine status). */
    private static final Map<String, String> MIRROR_STATUS_LABELS = new Map<String, String>{
        'Synced'           => 'Up to date',
        'UpdatesAvailable' => 'Update available',
        'InactiveMaster'   => 'Inactive',
        'Orphaned'         => 'No master'
    };
    /** The friendly name of the on/off switch (never the field API name). */
    private static final String SETTING_LABEL = 'Package sync';
    private static final String FLAG_OFF_MESSAGE =
        'Package sync is switched off, so adding and syncing are unavailable. '
        + 'An administrator can turn it back on in portal settings.';
    private static final String GENERIC_ERROR_MESSAGE =
        'Something went wrong. Please close this window and try again.';
    /**
     * Shown on a row when a package detail could not be copied because the
     * dealer catalogue does not accept one of the values this package uses
     * (the sync skips the detail instead of failing the whole action). Plain
     * business words — never an API / object / field name.
     */
    private static final String MIRROR_VALUE_GAP_MESSAGE =
        'Part of this package could not be copied because one of its coverage '
        + 'settings is not available to dealers yet. Ask an administrator to '
        + 'update the package setup, then try again.';

    // =========================================================================
    // Result / DTO shapes (@AuraEnabled, flat — the LWC is a dumb renderer)
    // =========================================================================

    /** What a create/sync would do (or did). Mirrors the sync's mirror-field contract. */
    public class ChangeSummary {
        @AuraEnabled public Boolean headerChanged;
        @AuraEnabled public Integer tiersAdded;
        @AuraEnabled public Integer tiersChanged;
        @AuraEnabled public Integer termsAdded;
        @AuraEnabled public Integer termsChanged;
        @AuraEnabled public Integer priceChanges;   // term wholesale anchors that differ
        @AuraEnabled public Integer optionsAdded;
        @AuraEnabled public Integer optionsChanged;

        public ChangeSummary() {
            headerChanged = false;
            tiersAdded = 0; tiersChanged = 0;
            termsAdded = 0; termsChanged = 0; priceChanges = 0;
            optionsAdded = 0; optionsChanged = 0;
        }

        public Boolean hasChanges() {
            return headerChanged || tiersAdded > 0 || tiersChanged > 0
                || termsAdded > 0 || termsChanged > 0 || priceChanges > 0
                || optionsAdded > 0 || optionsChanged > 0;
        }

        /** One-line plain-language summary fed to the console confirm dialog / chips. */
        public String describe() {
            List<String> parts = new List<String>();
            if (headerChanged) parts.add('package details updated');
            if (tiersAdded > 0) parts.add(countLabel(tiersAdded, 'tier') + ' added');
            if (tiersChanged > 0) parts.add(countLabel(tiersChanged, 'tier') + ' updated');
            if (termsAdded > 0) parts.add(countLabel(termsAdded, 'term') + ' added');
            if (termsChanged > 0) parts.add(countLabel(termsChanged, 'term') + ' updated');
            if (priceChanges > 0) parts.add(countLabel(priceChanges, 'wholesale price') + ' updated');
            if (optionsAdded > 0) parts.add(countLabel(optionsAdded, 'add-on') + ' added');
            if (optionsChanged > 0) parts.add(countLabel(optionsChanged, 'add-on') + ' updated');
            return String.join(parts, ', ');
        }

        /** "3 tiers" / "1 term" — plural helper for the plain-language summary. */
        private String countLabel(Integer n, String noun) {
            return n + ' ' + (n == 1 ? noun : noun + 's');
        }
    }

    /** Per-package outcome of a create/sync call. */
    public class RowResult {
        @AuraEnabled public Id masterPackageId;   // create rows
        @AuraEnabled public Id dealerPackageId;   // sync rows
        @AuraEnabled public String name;
        @AuraEnabled public String status;        // created|skipped|synced|failed|would-create|would-update
        @AuraEnabled public String message;
        @AuraEnabled public ChangeSummary changes;

        public RowResult() {
            changes = new ChangeSummary();
        }
    }

    /** Envelope for createFromMaster / syncFromMaster. */
    public class ActionResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Boolean dryRun;
        @AuraEnabled public Integer createdCount;
        @AuraEnabled public Integer skippedCount;
        @AuraEnabled public Integer failedCount;
        @AuraEnabled public List<RowResult> results;

        public ActionResult() {
            success = false;
            dryRun = false;
            createdCount = 0; skippedCount = 0; failedCount = 0;
            results = new List<RowResult>();
        }
    }

    /** A master package offered in the "Available catalogue" gap-create list. */
    public class CatalogueRow {
        @AuraEnabled public Id masterPackageId;
        @AuraEnabled public String name;
        @AuraEnabled public String recordTypeLabel;
        @AuraEnabled public String planTypeName;     // Package_Group__c name
        @AuraEnabled public String releaseName;      // Catalogue_Release__c name (chip)
        @AuraEnabled public String releaseStatus;    // Draft | Published | Superseded | ''
        @AuraEnabled public Integer tierCount;
        @AuraEnabled public Integer termCount;
        @AuraEnabled public Integer optionCount;
        @AuraEnabled public Integer scheduleAssignments; // informational (D2)
    }

    /** A dealer mirror row with its staleness state. */
    public class MirrorRow {
        @AuraEnabled public Id dealerPackageId;
        @AuraEnabled public Id masterPackageId;      // null when orphaned
        @AuraEnabled public String name;
        @AuraEnabled public String recordTypeLabel;
        @AuraEnabled public String status;           // Synced | UpdatesAvailable | InactiveMaster | Orphaned
        @AuraEnabled public String statusLabel;      // plain words (never the machine status)
        @AuraEnabled public String reason;           // human reason (server-built)
        @AuraEnabled public Datetime lastSyncedAt;   // watermark (GMT; display only)
        @AuraEnabled public String lastSyncedLabel;  // server-formatted — no client date math
        @AuraEnabled public Datetime lastMasterChangeAt;
        @AuraEnabled public ChangeSummary changes;
        @AuraEnabled public Integer scheduleAssignments; // informational (D2)
        @AuraEnabled public String scheduleLabel;    // plain words (e.g. "2 schedules")

        public MirrorRow() {
            changes = new ChangeSummary();
            scheduleAssignments = 0;
        }
    }

    /**
     * One row of the unified package list — every eligible master package with
     * its state for THIS dealer. Replaces the old available/mirrored split:
     *   • AvailableToAdd   — eligible master the dealer does not have yet (Add).
     *   • AlreadyAvailable — mirror present and current (no action).
     *   • UpdateAvailable  — mirror present but stale vs the master (Sync).
     * Only label fields are rendered by the LWC (no API names, no date math).
     */
    public class UnifiedPackageRow {
        @AuraEnabled public String rowId;             // stable render key
        @AuraEnabled public Id masterPackageId;
        @AuraEnabled public Id dealerPackageId;       // null until the dealer has it
        @AuraEnabled public String name;
        @AuraEnabled public String recordTypeLabel;
        @AuraEnabled public String planTypeLabel;
        @AuraEnabled public String releaseLabel;      // '' when no release context
        @AuraEnabled public String status;            // AvailableToAdd | AlreadyAvailable | UpdateAvailable
        @AuraEnabled public String statusLabel;       // plain words
        @AuraEnabled public String statusTone;        // new | ok | attention
        @AuraEnabled public String reason;            // plain words ("what changed / what to do")
        @AuraEnabled public String countsLabel;       // "3 tiers · 12 terms · 15 add-ons"
        @AuraEnabled public String scheduleLabel;     // '' or "2 schedules"
        @AuraEnabled public String lastSyncedLabel;   // '' when not yet added
        @AuraEnabled public String primaryAction;     // add | sync | none
        @AuraEnabled public String primaryActionLabel;// button text ('' when none)
        @AuraEnabled public ChangeSummary changes;

        public UnifiedPackageRow() {
            changes = new ChangeSummary();
        }
    }

    /** getSyncInventory payload. */
    public class SyncInventoryDTO {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Boolean isDealerAccount;
        @AuraEnabled public Boolean syncEnabled;     // kill-switch state (Dealer_Package__c gate)
        @AuraEnabled public String syncEnabledLabel; // plain words: "On" / "Off"
        @AuraEnabled public String syncEnabledMessage; // plain-language one-liner for the header/banner
        @AuraEnabled public List<UnifiedPackageRow> packages; // THE unified list (default view)
        @AuraEnabled public Integer availableToAddCount;
        @AuraEnabled public Integer alreadyAvailableCount;
        @AuraEnabled public Integer updateAvailableCount;
        @AuraEnabled public List<CatalogueRow> available;     // retained: gap-create candidates
        @AuraEnabled public List<MirrorRow> mirrored;         // retained: all mirrors (footer + deltas)
    }

    // =========================================================================
    // 1. Inventory — the single read call behind the console
    // =========================================================================

    @AuraEnabled
    public static SyncInventoryDTO getSyncInventory(Id accountId) {
        SyncInventoryDTO dto = new SyncInventoryDTO();
        dto.accountId = accountId;
        dto.packages = new List<UnifiedPackageRow>();
        dto.available = new List<CatalogueRow>();
        dto.mirrored = new List<MirrorRow>();
        dto.availableToAddCount = 0;
        dto.alreadyAvailableCount = 0;
        dto.updateAvailableCount = 0;
        dto.syncEnabled = PortalFeatureFlagService.isDealerSyncEnabled();
        dto.syncEnabledLabel = dto.syncEnabled ? 'On' : 'Off';
        dto.syncEnabledMessage = dto.syncEnabled
            ? 'Adding and syncing dealer packages is available.'
            : FLAG_OFF_MESSAGE;

        try {
            assertReadAccess();

            List<Account> accounts = [
                SELECT Id, Name, RecordType.DeveloperName
                FROM Account
                WHERE Id = :accountId
                LIMIT 1
            ];
            if (accounts.isEmpty()) {
                dto.isDealerAccount = false;
                dto.accountName = '';
                return dto;
            }
            dto.accountName = accounts[0].Name;
            dto.isDealerAccount = accounts[0].RecordType != null
                && accounts[0].RecordType.DeveloperName == DEALER_ACCOUNT_RT;
            if (!dto.isDealerAccount) return dto;

            // ---- the whole catalogue (bounded: admin-managed master books) ----
            List<Package__c> masters = allMasterPackages();

            // ---- this dealer's mirrors ----
            Map<Id, Dealer_Package__c> dps = new Map<Id, Dealer_Package__c>([
                SELECT Id, Name, Dealer__c, Package__c, Plan_Type__c, RecordTypeId,
                       RecordType.Name, RecordType.DeveloperName,
                       Class__c, Per_Claim_Limit__c, Deductable__c, Package_Description__c,
                       Commercial_Vehicle_Surcharge_Fee__c,
                       Last_Synced_At__c, CreatedDate
                FROM Dealer_Package__c
                WHERE Dealer__c = :accountId
                ORDER BY Name
            ]);

            // ---- master subtree rows for the whole catalogue (constant shape:
            //      all children carry Package__c, so 3 queries cover the subtree) ----
            Set<Id> masterIds = new Set<Id>();
            for (Package__c m : masters) masterIds.add(m.Id);

            Map<Id, List<Package_Tier__c>> tiersByPackage = tiersByPackage(masterIds);
            Map<Id, List<Package_Term__c>> termsByPackage = termsByPackage(masterIds);
            Map<Id, List<Package_Option__c>> optionsByPackage = optionsByPackage(masterIds);

            // ---- this dealer's mirror children (for exact change deltas) ----
            Set<Id> dpIds = dps.keySet();
            Map<String, Dealer_Package_Tier__c> dealerTiers = new Map<String, Dealer_Package_Tier__c>();
            Map<String, Dealer_Package_Term__c> dealerTerms = new Map<String, Dealer_Package_Term__c>();
            Map<String, Dealer_Package_Option__c> dealerOptions = new Map<String, Dealer_Package_Option__c>();
            if (!dpIds.isEmpty()) {
                for (Dealer_Package_Tier__c t : [
                    SELECT Id, Dealer_Package__c, Package_Tier__c, Name, Minimum__c, Maximum__c,
                           Mileage_Unit__c, Interest_Rate_Min__c, Interest_Rate_Max__c,
                           Minimum_Financed_Amount__c, Maximum_Financed_Amount__c
                    FROM Dealer_Package_Tier__c
                    WHERE Dealer_Package__c IN :dpIds AND Package_Tier__c != null
                ]) {
                    dealerTiers.put(t.Dealer_Package__c + '_' + t.Package_Tier__c, t);
                }
                for (Dealer_Package_Term__c t : [
                    SELECT Id, Dealer_Package__c, Dealer_Package_Tier__c, Package_Tier__c, Package_Term__c,
                           Name, Month__c, Mileage__c, Mileage_Unit__c, ByYear__c, Class__c,
                           Premium_Model_Fee__c, Mileage_Restriction__c, Mileage_Restriction_Start__c,
                           Mileage_Restriction_End__c, Restriction_Type__c, Duration_Type__c,
                           Start_Term__c, Expiry_Term__c, Odometer_KM__c,
                           Original_Package_Term_Cost__c
                    FROM Dealer_Package_Term__c
                    WHERE Dealer_Package__c IN :dpIds AND Package_Term__c != null
                ]) {
                    dealerTerms.put(t.Dealer_Package__c + '_' + t.Package_Term__c, t);
                }
                for (Dealer_Package_Option__c o : [
                    SELECT Id, Dealer_Package__c, Dealer_Package_Term__c, Package_Option__c, Option__c,
                           Selection_Type__c, Inclusion__c, Exclusion__c, Category__c,
                           Minimum_Value__c, Maximum_Value__c, Original_Package_Option_Price__c
                    FROM Dealer_Package_Option__c
                    WHERE Dealer_Package__c IN :dpIds AND Package_Option__c != null
                ]) {
                    dealerOptions.put(o.Dealer_Package__c + '_' + o.Package_Option__c, o);
                }
            }

            // ---- informational schedule-assignment counts (D2: never drives sync) ----
            Map<Id, Integer> scheduleCountsByPackage = scheduleAssignmentCounts(
                masterIds, accountId);

            // ---- mirrored rows ----
            Set<Id> mirroredMasterIds = new Set<Id>();
            Map<Id, MirrorRow> mirrorByMaster = new Map<Id, MirrorRow>();
            for (Dealer_Package__c dp : dps.values()) {
                MirrorRow row = buildMirrorRow(
                    dp, masters, tiersByPackage, termsByPackage, optionsByPackage,
                    dealerTiers, dealerTerms, dealerOptions, scheduleCountsByPackage
                );
                dto.mirrored.add(row);
                if (dp.Package__c != null) {
                    mirroredMasterIds.add(dp.Package__c);
                    mirrorByMaster.put(dp.Package__c, row);
                }
            }

            // ---- available catalogue (retained payload): eligible, not yet mirrored ----
            for (Package__c m : masters) {
                if (!shouldShowInCatalogue(m)) continue;
                if (mirroredMasterIds.contains(m.Id)) continue;
                CatalogueRow row = new CatalogueRow();
                row.masterPackageId = m.Id;
                row.name = m.Name;
                row.recordTypeLabel = m.RecordType != null ? m.RecordType.Name : '';
                row.planTypeName = m.Package_Group__r != null ? m.Package_Group__r.Name : '';
                if (m.Package_Group__r != null && m.Package_Group__r.Catalogue_Release__r != null) {
                    row.releaseName = m.Package_Group__r.Catalogue_Release__r.Name;
                    row.releaseStatus = m.Package_Group__r.Catalogue_Release__r.Status__c;
                }
                row.tierCount = tiersByPackage.get(m.Id) != null ? tiersByPackage.get(m.Id).size() : 0;
                row.termCount = termsByPackage.get(m.Id) != null ? termsByPackage.get(m.Id).size() : 0;
                row.optionCount = optionsByPackage.get(m.Id) != null ? optionsByPackage.get(m.Id).size() : 0;
                row.scheduleAssignments = scheduleCountsByPackage.get(m.Id) != null
                    ? scheduleCountsByPackage.get(m.Id) : 0;
                dto.available.add(row);
            }

            // ---- THE unified list: one row per eligible master package ----
            // Statuses: AvailableToAdd (no mirror) · AlreadyAvailable (mirror,
            // current) · UpdateAvailable (mirror, stale). Built from the same
            // server-computed mirror rows, so staleness/D1/D3 stay single-sourced.
            for (Package__c m : masters) {
                if (!shouldShowInCatalogue(m)) continue;
                UnifiedPackageRow u = new UnifiedPackageRow();
                u.rowId = m.Id;
                u.masterPackageId = m.Id;
                u.name = m.Name;
                u.recordTypeLabel = m.RecordType != null ? m.RecordType.Name : '';
                u.planTypeLabel = m.Package_Group__r != null ? m.Package_Group__r.Name : '';
                u.releaseLabel = releaseLabel(m);
                u.countsLabel = countsLabel(m, tiersByPackage, termsByPackage, optionsByPackage);
                u.scheduleLabel = scheduleLabel(scheduleCountsByPackage.get(m.Id));

                MirrorRow mr = mirrorByMaster.get(m.Id);
                if (mr == null) {
                    u.status = 'AvailableToAdd';
                    u.reason = 'Not yet available to this dealer.';
                    u.primaryAction = 'add';
                } else {
                    u.dealerPackageId = mr.dealerPackageId;
                    u.changes = mr.changes;
                    u.lastSyncedLabel = mr.lastSyncedLabel;
                    if (mr.status == 'UpdatesAvailable') {
                        u.status = 'UpdateAvailable';
                        u.reason = String.isNotBlank(mr.reason)
                            ? mr.reason
                            : 'The master package changed since the last sync.';
                        u.primaryAction = 'sync';
                    } else {
                        u.status = 'AlreadyAvailable';
                        u.reason = 'Up to date with the master package.';
                        u.primaryAction = 'none';
                    }
                }
                u.statusLabel = STATUS_LABELS.get(u.status);
                u.statusTone = STATUS_TONES.get(u.status);
                u.primaryActionLabel = u.primaryAction == 'none'
                    ? '' : ACTION_LABELS.get(u.primaryAction);
                dto.packages.add(u);
            }

            // Needs-attention first, then additions, then settled (name order kept).
            dto.packages = sortUnified(dto.packages);
            for (UnifiedPackageRow u : dto.packages) {
                if (u.status == 'UpdateAvailable') dto.updateAvailableCount++;
                else if (u.status == 'AvailableToAdd') dto.availableToAddCount++;
                else dto.alreadyAvailableCount++;
            }
            return dto;
        } catch (Exception e) {
            throw new AuraHandledException(GENERIC_ERROR_MESSAGE);
        }
    }

    // =========================================================================
    // 2. Gap-create — createFromMaster
    // =========================================================================

    @AuraEnabled
    public static ActionResult createFromMaster(Id accountId, List<Id> masterPackageIds, Boolean dryRun) {
        ActionResult result = new ActionResult();
        result.dryRun = dryRun == true;
        try {
            assertReadAccess();

            if (accountId == null || masterPackageIds == null || masterPackageIds.isEmpty()) {
                result.message = 'A dealer account and at least one master package are required.';
                return result;
            }
            Account acc = requireDealerAccount(accountId);
            if (acc == null) {
                result.message = 'This action is for Dealer Account records only.';
                return result;
            }

            List<Package__c> masters = allMasterPackages();
            Map<Id, Package__c> masterById = new Map<Id, Package__c>();
            for (Package__c m : masters) {
                if (masterPackageIds.contains(m.Id)) masterById.put(m.Id, m);
            }

            // Concurrency-safe mirror-existence re-check inside this transaction.
            Set<Id> already = new Set<Id>();
            for (Dealer_Package__c dp : [
                SELECT Package__c FROM Dealer_Package__c
                WHERE Dealer__c = :accountId AND Package__c IN :masterPackageIds
            ]) {
                already.add(dp.Package__c);
            }

            for (Id mid : masterPackageIds) {
                RowResult rr = new RowResult();
                rr.masterPackageId = mid;
                Package__c m = masterById.get(mid);
                if (m == null) {
                    rr.status = 'failed';
                    rr.message = 'This package is no longer available. Refresh and try again.';
                    result.results.add(rr);
                    result.failedCount++;
                    continue;
                }
                rr.name = m.Name;
                if (already.contains(mid)) {
                    rr.status = 'skipped';
                    rr.message = 'Already available to this dealer.';
                    result.results.add(rr);
                    result.skippedCount++;
                    continue;
                }
                rr.status = result.dryRun ? 'would-create' : 'created';
                rr.message = result.dryRun
                    ? 'Would add this package to the dealer, with its coverage tiers, terms and add-ons.'
                    : 'Added to the dealer with its coverage tiers, terms and add-ons.';
                result.results.add(rr);
                result.createdCount++;
            }

            if (result.dryRun || result.createdCount == 0) {
                result.success = true;
                result.message = result.dryRun
                    ? 'Dry run: ' + packageCountLabel(result.createdCount) + ' would be added for ' + acc.Name + '.'
                    : 'Nothing to add for ' + acc.Name + '.';
                return result;
            }

            // Real run — writes honour the package-sync kill switch (D4).
            if (!PortalFeatureFlagService.isDealerSyncEnabled()) {
                result.success = false;
                result.message = FLAG_OFF_MESSAGE;
                for (RowResult rr : result.results) {
                    if (rr.status == 'created') {
                        rr.status = 'failed';
                        rr.message = 'Not added. ' + FLAG_OFF_MESSAGE;
                    }
                }
                return result;
            }

            List<Package__c> toCreate = new List<Package__c>();
            for (RowResult rr : result.results) {
                if (rr.status == 'created') toCreate.add(masterById.get(rr.masterPackageId));
            }
            // One DML statement → one after-insert fan-out reconcile over all headers.
            DealerPackageSyncService.createDealerMirrorsForDealer(toCreate, accountId);

            // Defensive flag: the service skips a mirror detail it cannot copy
            // (e.g. a value the dealer catalogue rejects) rather than failing the
            // whole action. Mark the exact packages so the admin sees what needs
            // attention — plain words, no API / field names.
            Integer flagged = flagSkippedRows(
                result.results, DealerPackageSyncService.getSkippedMirrorReasons(), true, null);
            if (flagged > 0) {
                result.createdCount = Math.max(0, result.createdCount - flagged);
                result.failedCount += flagged;
                result.success = false;
                result.message = 'Added ' + packageCountLabel(result.createdCount) + ' to ' + acc.Name
                    + ', but ' + packageCountLabel(flagged) + ' could not be fully added. '
                    + MIRROR_VALUE_GAP_MESSAGE;
            } else {
                result.success = true;
                result.message = 'Added ' + packageCountLabel(result.createdCount) + ' to ' + acc.Name + '.';
            }
            return result;
        } catch (Exception e) {
            result.success = false;
            result.message = GENERIC_ERROR_MESSAGE;
            return result;
        }
    }

    // =========================================================================
    // 3. Change-sync — syncFromMaster
    // =========================================================================

    @AuraEnabled
    public static ActionResult syncFromMaster(List<Id> dealerPackageIds, Boolean dryRun) {
        ActionResult result = new ActionResult();
        result.dryRun = dryRun == true;
        try {
            assertReadAccess();

            if (dealerPackageIds == null || dealerPackageIds.isEmpty()) {
                result.message = 'Select at least one package to sync.';
                return result;
            }
            Set<Id> ids = new Set<Id>(dealerPackageIds);

            // Everything the diff needs, in constant-shape whole-set queries.
            Map<Id, Dealer_Package__c> dps = new Map<Id, Dealer_Package__c>([
                SELECT Id, Name, Dealer__c, Package__c, Plan_Type__c, RecordTypeId,
                       RecordType.Name, RecordType.DeveloperName,
                       Class__c, Per_Claim_Limit__c, Deductable__c, Package_Description__c,
                       Commercial_Vehicle_Surcharge_Fee__c,
                       Last_Synced_At__c, CreatedDate
                FROM Dealer_Package__c
                WHERE Id IN :ids
            ]);
            if (dps.isEmpty()) {
                result.message = 'These packages were not found. Refresh and try again.';
                return result;
            }

            Set<Id> masterIds = new Set<Id>();
            for (Dealer_Package__c dp : dps.values()) {
                if (dp.Package__c != null) masterIds.add(dp.Package__c);
            }
            Map<Id, Package__c> masters = new Map<Id, Package__c>();
            if (!masterIds.isEmpty()) {
                for (Package__c m : allMasterPackages()) {
                    if (masterIds.contains(m.Id)) masters.put(m.Id, m);
                }
            }
            Map<Id, List<Package_Tier__c>> tiersByPackage = tiersByPackage(masterIds);
            Map<Id, List<Package_Term__c>> termsByPackage = termsByPackage(masterIds);
            Map<Id, List<Package_Option__c>> optionsByPackage = optionsByPackage(masterIds);

            Map<String, Dealer_Package_Tier__c> dealerTiers = new Map<String, Dealer_Package_Tier__c>();
            Map<String, Dealer_Package_Term__c> dealerTerms = new Map<String, Dealer_Package_Term__c>();
            Map<String, Dealer_Package_Option__c> dealerOptions = new Map<String, Dealer_Package_Option__c>();
            for (Dealer_Package_Tier__c t : [
                SELECT Id, Dealer_Package__c, Package_Tier__c, Name, Minimum__c, Maximum__c,
                       Mileage_Unit__c, Interest_Rate_Min__c, Interest_Rate_Max__c,
                       Minimum_Financed_Amount__c, Maximum_Financed_Amount__c
                FROM Dealer_Package_Tier__c
                WHERE Dealer_Package__c IN :ids AND Package_Tier__c != null
            ]) {
                dealerTiers.put(t.Dealer_Package__c + '_' + t.Package_Tier__c, t);
            }
            for (Dealer_Package_Term__c t : [
                SELECT Id, Dealer_Package__c, Dealer_Package_Tier__c, Package_Tier__c, Package_Term__c,
                       Name, Month__c, Mileage__c, Mileage_Unit__c, ByYear__c, Class__c,
                       Premium_Model_Fee__c, Mileage_Restriction__c, Mileage_Restriction_Start__c,
                       Mileage_Restriction_End__c, Restriction_Type__c, Duration_Type__c,
                       Start_Term__c, Expiry_Term__c, Odometer_KM__c,
                       Original_Package_Term_Cost__c
                FROM Dealer_Package_Term__c
                WHERE Dealer_Package__c IN :ids AND Package_Term__c != null
            ]) {
                dealerTerms.put(t.Dealer_Package__c + '_' + t.Package_Term__c, t);
            }
            for (Dealer_Package_Option__c o : [
                SELECT Id, Dealer_Package__c, Dealer_Package_Term__c, Package_Option__c, Option__c,
                       Selection_Type__c, Inclusion__c, Exclusion__c, Category__c,
                       Minimum_Value__c, Maximum_Value__c, Original_Package_Option_Price__c
                FROM Dealer_Package_Option__c
                WHERE Dealer_Package__c IN :ids AND Package_Option__c != null
            ]) {
                dealerOptions.put(o.Dealer_Package__c + '_' + o.Package_Option__c, o);
            }

            // Dry-run: report the exact change summary, no DML.
            for (Dealer_Package__c dp : dps.values()) {
                RowResult rr = new RowResult();
                rr.dealerPackageId = dp.Id;
                rr.name = dp.Name;
                Package__c m = dp.Package__c != null ? masters.get(dp.Package__c) : null;
                if (m == null) {
                    rr.status = 'failed';
                    rr.message = 'The master package is missing, so there is nothing to sync.';
                    result.results.add(rr);
                    result.failedCount++;
                    continue;
                }
                rr.changes = diffMirror(dp, m, tiersByPackage, termsByPackage, optionsByPackage,
                    dealerTiers, dealerTerms, dealerOptions);
                rr.status = result.dryRun ? 'would-update' : 'synced';
                rr.message = result.dryRun
                    ? (rr.changes.hasChanges()
                        ? 'Would update: ' + rr.changes.describe() + '. Your dealer pricing is never changed.'
                        : 'Already up to date — no changes needed.')
                    : (rr.changes.hasChanges()
                        ? 'Updated: ' + rr.changes.describe() + '. Your dealer pricing is unchanged.'
                        : 'Nothing to update — already up to date.');
                result.results.add(rr);
                if (rr.changes.hasChanges()) result.createdCount++;
                else result.skippedCount++;
            }

            if (result.dryRun) {
                result.success = true;
                result.message = 'Dry run: ' + packageCountLabel(result.createdCount) + ' need updating.';
                return result;
            }

            if (!PortalFeatureFlagService.isDealerSyncEnabled()) {
                result.success = false;
                result.message = FLAG_OFF_MESSAGE;
                return result;
            }

            DealerPackageSyncService.reconcileDealerPackages(ids);

            // Defensive flag: mirror details the service had to skip (a value the
            // dealer catalogue rejects) are surfaced per package, plain words.
            Map<Id, Id> masterByDealer = new Map<Id, Id>();
            for (Dealer_Package__c d : dps.values()) {
                if (d.Package__c != null) masterByDealer.put(d.Id, d.Package__c);
            }
            Integer flagged = flagSkippedRows(
                result.results, DealerPackageSyncService.getSkippedMirrorReasons(), false, masterByDealer);
            if (flagged > 0) {
                result.failedCount += flagged;
                result.success = false;
                result.message = 'Updated ' + packageCountLabel(Math.max(0, ids.size() - flagged))
                    + ' from the master catalogue, but ' + packageCountLabel(flagged)
                    + ' could not be fully updated. ' + MIRROR_VALUE_GAP_MESSAGE;
            } else {
                result.success = true;
                result.message = 'Updated ' + packageCountLabel(ids.size()) + ' from the master catalogue.';
            }
            return result;
        } catch (Exception e) {
            result.success = false;
            result.message = GENERIC_ERROR_MESSAGE;
            return result;
        }
    }

    // =========================================================================
    // Shared queries
    // =========================================================================

    /** Whole-catalogue master packages with release context (bounded admin book). */
    private static List<Package__c> allMasterPackages() {
        return [
            SELECT Id, Name, Is_Active__c, Package_Group__c, RecordTypeId,
                   RecordType.Name, RecordType.DeveloperName,
                   Class__c, Coverage_per_claim__c, Deductible__c, Description__c,
                   Commercial_Business_Use__c, Commercial_Vehicle_Surcharge_Fee__c,
                   LastModifiedDate,
                   Package_Group__r.Name,
                   Package_Group__r.Catalogue_Release__r.Name,
                   Package_Group__r.Catalogue_Release__r.Status__c,
                   Package_Group__r.Catalogue_Release__r.Effective_Date__c
            FROM Package__c
            ORDER BY Name
        ];
    }

    private static Map<Id, List<Package_Tier__c>> tiersByPackage(Set<Id> masterIds) {
        Map<Id, List<Package_Tier__c>> out = new Map<Id, List<Package_Tier__c>>();
        if (masterIds == null || masterIds.isEmpty()) return out;
        for (Package_Tier__c t : [
            SELECT Id, Package__c, LastModifiedDate, Mileage_Restriction_Start__c,
                   Mileage_Restriction_End__c, Mileage_Unit__c,
                   Financed_Interest_Rate_Min__c, Financed_Interest_Rate_Max__c,
                   Minimum_Financed_Amount__c, Maximum_Financed_Amount__c
            FROM Package_Tier__c
            WHERE Package__c IN :masterIds
            ORDER BY Name
        ]) {
            if (!out.containsKey(t.Package__c)) out.put(t.Package__c, new List<Package_Tier__c>());
            out.get(t.Package__c).add(t);
        }
        return out;
    }

    private static Map<Id, List<Package_Term__c>> termsByPackage(Set<Id> masterIds) {
        Map<Id, List<Package_Term__c>> out = new Map<Id, List<Package_Term__c>>();
        if (masterIds == null || masterIds.isEmpty()) return out;
        for (Package_Term__c t : [
            SELECT Id, Package__c, Package_Tier__c, LastModifiedDate, Price__c, Month__c,
                   Mileage__c, Mileage_Unit__c, ByYear__c, Class__c, Premium_Model_Fee__c,
                   Mileage_Restriction__c, Mileage_Restriction_Start__c,
                   Mileage_Restriction_End__c, Restriction_Type__c, Duration_Type__c,
                   Start_Term__c, Expiry_Term__c, Odometer_KM__c
            FROM Package_Term__c
            WHERE Package__c IN :masterIds
            ORDER BY Name
        ]) {
            if (!out.containsKey(t.Package__c)) out.put(t.Package__c, new List<Package_Term__c>());
            out.get(t.Package__c).add(t);
        }
        return out;
    }

    private static Map<Id, List<Package_Option__c>> optionsByPackage(Set<Id> masterIds) {
        Map<Id, List<Package_Option__c>> out = new Map<Id, List<Package_Option__c>>();
        if (masterIds == null || masterIds.isEmpty()) return out;
        for (Package_Option__c o : [
            SELECT Id, Package__c, Package_Term__c, LastModifiedDate, Option__c,
                   Selection_Type__c, Inclusion_Text__c, Exclusion_Text__c, Price__c,
                   Category__c, Minimum_Value__c, Maximum_Value__c
            FROM Package_Option__c
            WHERE Package__c IN :masterIds
            ORDER BY Name
        ]) {
            if (!out.containsKey(o.Package__c)) out.put(o.Package__c, new List<Package_Option__c>());
            out.get(o.Package__c).add(o);
        }
        return out;
    }

    /**
     * D1 — the ONE catalogue-eligibility predicate. Available = active AND not
     * part of a Superseded release (Draft and Published both count); the
     * valid-date-range check applies only where a release Effective_Date__c
     * exists. Tightening to published-only later = edit this method only.
     */
    private static Boolean shouldShowInCatalogue(Package__c m) {
        if (m.Is_Active__c != true) return false;
        if (m.Package_Group__r != null && m.Package_Group__r.Catalogue_Release__r != null) {
            if (m.Package_Group__r.Catalogue_Release__r.Status__c == 'Superseded') return false;
            Date eff = m.Package_Group__r.Catalogue_Release__r.Effective_Date__c;
            if (eff != null && eff > System.today()) return false;
        }
        return true;
    }

    // =========================================================================
    // Staleness + exact change deltas (read-only mirror of the sync contract)
    // =========================================================================

    private static MirrorRow buildMirrorRow(
        Dealer_Package__c dp,
        List<Package__c> masters,
        Map<Id, List<Package_Tier__c>> tiersByPackage,
        Map<Id, List<Package_Term__c>> termsByPackage,
        Map<Id, List<Package_Option__c>> optionsByPackage,
        Map<String, Dealer_Package_Tier__c> dealerTiers,
        Map<String, Dealer_Package_Term__c> dealerTerms,
        Map<String, Dealer_Package_Option__c> dealerOptions,
        Map<Id, Integer> scheduleCountsByPackage
    ) {
        MirrorRow row = new MirrorRow();
        row.dealerPackageId = dp.Id;
        row.name = dp.Name;
        row.recordTypeLabel = dp.RecordType != null ? dp.RecordType.Name : '';
        row.lastSyncedAt = dp.Last_Synced_At__c != null ? dp.Last_Synced_At__c : dp.CreatedDate;

        Package__c m = null;
        for (Package__c candidate : masters) {
            if (candidate.Id == dp.Package__c) { m = candidate; break; }
        }

        if (dp.Package__c == null || m == null) {
            // Orphaned header (no master, or master deleted): informational only.
            row.status = 'Orphaned';
            row.reason = 'The master package is missing. This copy is kept but no longer updated.';
            return finishMirrorRow(row);
        }

        row.masterPackageId = m.Id;
        row.scheduleAssignments = scheduleCountsByPackage.get(m.Id) != null
            ? scheduleCountsByPackage.get(m.Id) : 0;

        if (m.Is_Active__c != true) {
            row.status = 'InactiveMaster';
            row.reason = 'The master package is inactive. This copy is kept; syncing only refreshes its structure.';
            // Still report the delta so an admin can decide to sync a just-deactivated master.
            row.changes = diffMirror(dp, m, tiersByPackage, termsByPackage, optionsByPackage,
                dealerTiers, dealerTerms, dealerOptions);
            return finishMirrorRow(row);
        }

        // Watermark staleness rule (§3.2) — masterChangeTs vs Last_Synced_At__c.
        Datetime masterChangeTs = m.LastModifiedDate;
        Datetime watermark = dp.Last_Synced_At__c != null ? dp.Last_Synced_At__c : dp.CreatedDate;
        for (Package_Tier__c t : listOrEmpty(tiersByPackage.get(m.Id))) {
            if (t.LastModifiedDate > masterChangeTs) masterChangeTs = t.LastModifiedDate;
        }
        for (Package_Term__c t : listOrEmpty(termsByPackage.get(m.Id))) {
            if (t.LastModifiedDate > masterChangeTs) masterChangeTs = t.LastModifiedDate;
        }
        for (Package_Option__c o : listOrEmpty(optionsByPackage.get(m.Id))) {
            if (o.LastModifiedDate > masterChangeTs) masterChangeTs = o.LastModifiedDate;
        }
        row.lastMasterChangeAt = masterChangeTs;

        row.changes = diffMirror(dp, m, tiersByPackage, termsByPackage, optionsByPackage,
            dealerTiers, dealerTerms, dealerOptions);

        if (masterChangeTs > watermark) {
            row.status = 'UpdatesAvailable';
            row.reason = row.changes.hasChanges()
                ? row.changes.describe()
                : 'The master package changed since the last sync.';
        } else {
            row.status = 'Synced';
            row.reason = row.changes.hasChanges()
                ? 'Up to date. Differences here come from your own edits.'
                : 'Up to date';
        }
        return finishMirrorRow(row);
    }

    /** Stamp the plain-word labels on a mirror row (footer + reason text). */
    private static MirrorRow finishMirrorRow(MirrorRow row) {
        row.statusLabel = MIRROR_STATUS_LABELS.get(row.status);
        row.scheduleLabel = scheduleLabel(row.scheduleAssignments);
        row.lastSyncedLabel = row.lastSyncedAt == null
            ? '' : 'Last synced ' + formatDate(row.lastSyncedAt);
        return row;
    }

    /** "12 Sep 2026" — server-side, so the LWC does no date math. */
    private static String formatDate(Datetime d) {
        return d == null ? '' : d.format('d MMM yyyy');
    }

    /** Release chip text for a master package: "Draft · V27 Book" ('' when none). */
    private static String releaseLabel(Package__c m) {
        if (m.Package_Group__r == null || m.Package_Group__r.Catalogue_Release__r == null) {
            return '';
        }
        String status = m.Package_Group__r.Catalogue_Release__r.Status__c;
        String name = m.Package_Group__r.Catalogue_Release__r.Name;
        String statusLabel = String.isBlank(status) ? '' : status;
        if (String.isBlank(name)) return statusLabel;
        return String.isBlank(statusLabel) ? name : statusLabel + ' · ' + name;
    }

    /** "3 tiers · 12 terms · 15 add-ons" — what a package contains, in plain words. */
    private static String countsLabel(
        Package__c m,
        Map<Id, List<Package_Tier__c>> tiersByPackage,
        Map<Id, List<Package_Term__c>> termsByPackage,
        Map<Id, List<Package_Option__c>> optionsByPackage
    ) {
        Integer t = tiersByPackage.get(m.Id) != null ? tiersByPackage.get(m.Id).size() : 0;
        Integer te = termsByPackage.get(m.Id) != null ? termsByPackage.get(m.Id).size() : 0;
        Integer o = optionsByPackage.get(m.Id) != null ? optionsByPackage.get(m.Id).size() : 0;
        return t + ' tiers · ' + te + ' terms · ' + o + ' add-ons';
    }

    /** "2 schedules" / "1 schedule" / '' — informational only (D2). */
    private static String scheduleLabel(Integer n) {
        if (n == null || n == 0) return '';
        return n == 1 ? '1 schedule' : n + ' schedules';
    }

    /** "2 packages" / "1 package" — plain count for result messages. */
    private static String packageCountLabel(Integer n) {
        Integer c = n == null ? 0 : n;
        return c + (c == 1 ? ' package' : ' packages');
    }

    /**
     * Flags result rows whose master package the sync skipped a mirror detail
     * for (see DealerPackageSyncService.getSkippedMirrorReasons). Returns the
     * flagged count and stamps the plain-word message. `byMaster` = true for
     * create rows (key = masterPackageId); false for sync rows (key =
     * dealerPackageId → master via masterByDealer). Never touches dealer pricing.
     */
    private static Integer flagSkippedRows(
        List<RowResult> rows,
        Map<Id, String> skippedByMasterPackageId,
        Boolean byMaster,
        Map<Id, Id> masterByDealer
    ) {
        if (rows == null || skippedByMasterPackageId == null || skippedByMasterPackageId.isEmpty()) return 0;
        Integer flagged = 0;
        for (RowResult rr : rows) {
            if (rr.status == 'failed') continue;
            Id masterId = byMaster
                ? rr.masterPackageId
                : (rr.dealerPackageId == null || masterByDealer == null
                    ? null : masterByDealer.get(rr.dealerPackageId));
            if (masterId == null || !skippedByMasterPackageId.containsKey(masterId)) continue;
            rr.status = 'failed';
            rr.message = MIRROR_VALUE_GAP_MESSAGE;
            flagged++;
        }
        return flagged;
    }

    /** Needs-attention first, then additions, then settled — name order preserved. */
    private static List<UnifiedPackageRow> sortUnified(List<UnifiedPackageRow> rows) {
        List<UnifiedPackageRow> updates = new List<UnifiedPackageRow>();
        List<UnifiedPackageRow> adds = new List<UnifiedPackageRow>();
        List<UnifiedPackageRow> settled = new List<UnifiedPackageRow>();
        for (UnifiedPackageRow r : rows) {
            if (r.status == 'UpdateAvailable') updates.add(r);
            else if (r.status == 'AvailableToAdd') adds.add(r);
            else settled.add(r);
        }
        List<UnifiedPackageRow> out = new List<UnifiedPackageRow>();
        out.addAll(updates);
        out.addAll(adds);
        out.addAll(settled);
        return out;
    }

    /**
     * Exact read-only delta between one dealer mirror and its master, mirroring
     * DealerPackageSyncService's mirror-field contract field-for-field. Never
     * considers dealer markup/discount/incentive (D3 — the sync never writes
     * them, so they can never be "changed" by a sync).
     */
    private static ChangeSummary diffMirror(
        Dealer_Package__c dp,
        Package__c m,
        Map<Id, List<Package_Tier__c>> tiersByPackage,
        Map<Id, List<Package_Term__c>> termsByPackage,
        Map<Id, List<Package_Option__c>> optionsByPackage,
        Map<String, Dealer_Package_Tier__c> dealerTiers,
        Map<String, Dealer_Package_Term__c> dealerTerms,
        Map<String, Dealer_Package_Option__c> dealerOptions
    ) {
        ChangeSummary cs = new ChangeSummary();

        // ---- header (structure mirrors only; name/RT/plan-type/class/limits/desc/surcharge) ----
        if (dp.Name != m.Name
            || dp.Plan_Type__c != m.Package_Group__c
            || dp.Class__c != m.Class__c
            || dp.Per_Claim_Limit__c != m.Coverage_per_claim__c
            || dp.Deductable__c != m.Deductible__c
            || (String.isNotBlank(m.Description__c) && dp.Package_Description__c != m.Description__c)) {
            cs.headerChanged = true;
        }
        Boolean masterCommercial = m.Commercial_Business_Use__c == true;
        Decimal wantSurcharge = masterCommercial ? m.Commercial_Vehicle_Surcharge_Fee__c : null;
        if (dp.Commercial_Vehicle_Surcharge_Fee__c != wantSurcharge) cs.headerChanged = true;

        String rtDev = m.RecordType != null ? m.RecordType.DeveloperName : null;

        // ---- tiers / terms ----
        for (Package_Tier__c mt : listOrEmpty(tiersByPackage.get(m.Id))) {
            Dealer_Package_Tier__c dt = dealerTiers.get(dp.Id + '_' + mt.Id);
            if (dt == null) {
                cs.tiersAdded++;
                // A missing tier carries every term under it (fan-out contract).
                for (Package_Term__c mt2 : listOrEmpty(termsByPackage.get(m.Id))) {
                    if (mt2.Package_Tier__c == mt.Id) {
                        cs.termsAdded++;
                        countTermLevelOptions(dp, mt2, optionsByPackage, dealerTerms, dealerOptions, rtDev, cs);
                    }
                }
                continue;
            }
            if (tierChanged(dt, mt)) cs.tiersChanged++;

            for (Package_Term__c mterm : listOrEmpty(termsByPackage.get(m.Id))) {
                if (mterm.Package_Tier__c != mt.Id) continue;
                Dealer_Package_Term__c dterm = dealerTerms.get(dp.Id + '_' + mterm.Id);
                if (dterm == null) {
                    cs.termsAdded++;
                    countTermLevelOptions(dp, mterm, optionsByPackage, dealerTerms, dealerOptions, rtDev, cs);
                    continue;
                }
                Boolean struct = termStructureChanged(dterm, mterm);
                Boolean price = mterm.Price__c != null
                    && dterm.Original_Package_Term_Cost__c != mterm.Price__c;
                if (price) cs.priceChanges++;
                else if (struct) cs.termsChanged++;
                countTermLevelOptions(dp, mterm, optionsByPackage, dealerTerms, dealerOptions, rtDev, cs);
            }
        }

        // ---- tier-less terms (C5, tier-opt-in) ----
        // A master term with no Package_Tier__c is a standalone catalogue row
        // mirrored directly to the dealer package (DealerPackageSyncService C1),
        // so it must be counted in the delta. Handled here, outside the tier
        // loop, with the identical comparison logic as the tiered pass — the
        // tier loop never reaches it (there is no tier to iterate).
        for (Package_Term__c mterm : listOrEmpty(termsByPackage.get(m.Id))) {
            if (mterm.Package_Tier__c != null) continue; // owned by the tier loop above
            Dealer_Package_Term__c dterm = dealerTerms.get(dp.Id + '_' + mterm.Id);
            if (dterm == null) {
                cs.termsAdded++;
                countTermLevelOptions(dp, mterm, optionsByPackage, dealerTerms, dealerOptions, rtDev, cs);
                continue;
            }
            Boolean struct = termStructureChanged(dterm, mterm);
            Boolean price = mterm.Price__c != null
                && dterm.Original_Package_Term_Cost__c != mterm.Price__c;
            if (price) cs.priceChanges++;
            else if (struct) cs.termsChanged++;
            countTermLevelOptions(dp, mterm, optionsByPackage, dealerTerms, dealerOptions, rtDev, cs);
        }

        // ---- package-level options (record-type-specific selection rules) ----
        for (Package_Option__c mo : listOrEmpty(optionsByPackage.get(m.Id))) {
            Boolean include = false;
            if (rtDev == RT_CAR_LOAN) {
                include = mo.Selection_Type__c == 'Optional' && mo.Package_Term__c == null;
            } else if (rtDev == RT_GAP) {
                include = mo.Package_Term__c == null; // Total Loss: Included + Optional package-level
            } else {
                include = mo.Selection_Type__c == 'Included' && mo.Package_Term__c == null;
            }
            if (!include) continue; // term-level options counted above with their term

            Dealer_Package_Option__c dopt = dealerOptions.get(dp.Id + '_' + mo.Id);
            if (dopt == null) {
                cs.optionsAdded++;
            } else if (optionChanged(dopt, mo, rtDev)) {
                cs.optionsChanged++;
            }
        }
        return cs;
    }

    /** Term-level optional options ride on their term mirror (fan-out contract). */
    private static void countTermLevelOptions(
        Dealer_Package__c dp,
        Package_Term__c mterm,
        Map<Id, List<Package_Option__c>> optionsByPackage,
        Map<String, Dealer_Package_Term__c> dealerTerms,
        Map<String, Dealer_Package_Option__c> dealerOptions,
        String rtDev,
        ChangeSummary cs
    ) {
        if (rtDev == RT_CAR_LOAN || rtDev == RT_GAP) return; // term-level options only in the default family
        for (Package_Option__c mo : listOrEmpty(optionsByPackage.get(dp.Package__c))) {
            if (mo.Package_Term__c != mterm.Id) continue;
            if (!(mo.Selection_Type__c == 'Optional')) continue;
            Dealer_Package_Term__c dterm = dealerTerms.get(dp.Id + '_' + mterm.Id);
            if (dterm == null) {
                // The term is missing → the option would be created with it.
                if (dealerOptions.get(dp.Id + '_' + mo.Id) == null) cs.optionsAdded++;
                continue;
            }
            Dealer_Package_Option__c dopt = dealerOptions.get(dp.Id + '_' + mo.Id);
            if (dopt == null) cs.optionsAdded++;
            else if (optionChanged(dopt, mo, rtDev)) cs.optionsChanged++;
        }
    }

    private static Boolean tierChanged(Dealer_Package_Tier__c dt, Package_Tier__c mt) {
        return dt.Mileage_Unit__c != mt.Mileage_Unit__c
            || dt.Minimum__c != mt.Mileage_Restriction_Start__c
            || dt.Maximum__c != mt.Mileage_Restriction_End__c
            || dt.Interest_Rate_Min__c != mt.Financed_Interest_Rate_Min__c
            || dt.Interest_Rate_Max__c != mt.Financed_Interest_Rate_Max__c
            || dt.Minimum_Financed_Amount__c != mt.Minimum_Financed_Amount__c
            || dt.Maximum_Financed_Amount__c != mt.Maximum_Financed_Amount__c;
    }

    private static Boolean termStructureChanged(Dealer_Package_Term__c dt, Package_Term__c mt) {
        return dt.Month__c != mt.Month__c
            || dt.Mileage__c != mt.Mileage__c
            || dt.Mileage_Unit__c != mt.Mileage_Unit__c
            || dt.ByYear__c != mt.ByYear__c
            || dt.Class__c != mt.Class__c
            || dt.Premium_Model_Fee__c != mt.Premium_Model_Fee__c
            || dt.Mileage_Restriction__c != mt.Mileage_Restriction__c
            || dt.Mileage_Restriction_Start__c != mt.Mileage_Restriction_Start__c
            || dt.Mileage_Restriction_End__c != mt.Mileage_Restriction_End__c
            || dt.Restriction_Type__c != mt.Restriction_Type__c
            || dt.Duration_Type__c != mt.Duration_Type__c
            || dt.Start_Term__c != mt.Start_Term__c
            || dt.Expiry_Term__c != mt.Expiry_Term__c
            || dt.Odometer_KM__c != mt.Odometer_KM__c;
    }

    private static Boolean optionChanged(Dealer_Package_Option__c dopt, Package_Option__c mo, String rtDev) {
        String wantCategory = mo.Category__c;
        if (rtDev == RT_GAP && String.isBlank(wantCategory)) wantCategory = 'Total Loss';
        Boolean struct = dopt.Option__c != mo.Option__c
            || dopt.Selection_Type__c != mo.Selection_Type__c
            || dopt.Inclusion__c != mo.Inclusion_Text__c
            || dopt.Exclusion__c != mo.Exclusion_Text__c
            || dopt.Category__c != wantCategory
            || dopt.Minimum_Value__c != mo.Minimum_Value__c
            || dopt.Maximum_Value__c != mo.Maximum_Value__c;
        Boolean price = mo.Price__c != null && dopt.Original_Package_Option_Price__c != mo.Price__c;
        return struct || price;
    }

    /**
     * Informational schedule-assignment counts (D2). Never part of the
     * staleness rule: schedule/fee changes re-price quotes live, nothing is
     * mirrored. Scope: package-scoped + group-scoped + dealer-scoped rows.
     */
    private static Map<Id, Integer> scheduleAssignmentCounts(
        Set<Id> masterIds,
        Id accountId
    ) {
        Map<Id, Integer> out = new Map<Id, Integer>();
        Set<Id> groupIds = new Set<Id>();
        Map<Id, Id> packageToGroup = new Map<Id, Id>();
        for (Package__c m : allMasterPackages()) {
            if (masterIds.contains(m.Id) && m.Package_Group__c != null) {
                groupIds.add(m.Package_Group__c);
                packageToGroup.put(m.Id, m.Package_Group__c);
            }
        }
        // prime all packages we may ask about
        for (Id pid : masterIds) out.put(pid, 0);
        for (Vehicle_Schedule_Assignment__c a : [
            SELECT Id, Package__c, Package_Group__c, Dealer__c
            FROM Vehicle_Schedule_Assignment__c
            WHERE (Package__c IN :masterIds OR Package_Group__c IN :groupIds OR Dealer__c = :accountId)
        ]) {
            if (a.Package__c != null) {
                out.put(a.Package__c, (out.containsKey(a.Package__c) ? out.get(a.Package__c) : 0) + 1);
            } else if (a.Package_Group__c != null) {
                // group-scoped rows govern every package in the group
                for (Id pid : packageToGroup.keySet()) {
                    if (packageToGroup.get(pid) == a.Package_Group__c) {
                        out.put(pid, out.get(pid) + 1);
                    }
                }
            } else if (a.Dealer__c == accountId) {
                // dealer-scoped override row — informational
            }
        }
        return out;
    }

    private static List<Package_Tier__c> listOrEmpty(List<Package_Tier__c> l) {
        return l == null ? new List<Package_Tier__c>() : l;
    }
    private static List<Package_Term__c> listOrEmpty(List<Package_Term__c> l) {
        return l == null ? new List<Package_Term__c>() : l;
    }
    private static List<Package_Option__c> listOrEmpty(List<Package_Option__c> l) {
        return l == null ? new List<Package_Option__c>() : l;
    }

    // =========================================================================
    // Guards
    // =========================================================================

    private static Account requireDealerAccount(Id accountId) {
        List<Account> accs = [
            SELECT Id, Name, RecordType.DeveloperName
            FROM Account
            WHERE Id = :accountId AND RecordType.DeveloperName = :DEALER_ACCOUNT_RT
            LIMIT 1
        ];
        return accs.isEmpty() ? null : accs[0];
    }

    /**
     * Explicit CRUD/FLS assertions (admin console pattern). `without sharing`
     * gets the data; these keep the class honest if the action is ever surfaced
     * to a lesser profile. Throws on first denial.
     */
    private static void assertReadAccess() {
        SObjectType[] types = new SObjectType[]{
            Account.SObjectType,
            Dealer_Package__c.SObjectType,
            Dealer_Package_Tier__c.SObjectType,
            Dealer_Package_Term__c.SObjectType,
            Dealer_Package_Option__c.SObjectType,
            Package__c.SObjectType,
            Package_Tier__c.SObjectType,
            Package_Term__c.SObjectType,
            Package_Option__c.SObjectType,
            Package_Group__c.SObjectType,
            Catalogue_Release__c.SObjectType,
            Vehicle_Schedule_Assignment__c.SObjectType
        };
        for (SObjectType t : types) {
            if (!t.getDescribe().isAccessible()) {
                throw new SyncConsoleSecurityException(
                    'You do not have permission to view this package data.');
            }
        }
        // Field-level: the watermark + the money/structure anchors the console reads.
        SObjectField[] fields = new SObjectField[]{
            Dealer_Package__c.Last_Synced_At__c,
            Dealer_Package_Term__c.Original_Package_Term_Cost__c,
            Dealer_Package_Option__c.Original_Package_Option_Price__c,
            Package_Term__c.Price__c,
            Package_Option__c.Price__c,
            Package__c.Is_Active__c,
            Catalogue_Release__c.Status__c
        };
        for (SObjectField f : fields) {
            if (!f.getDescribe().isAccessible()) {
                throw new SyncConsoleSecurityException(
                    'You do not have permission to view this package data.');
            }
        }
    }

    private class SyncConsoleSecurityException extends Exception {}
}