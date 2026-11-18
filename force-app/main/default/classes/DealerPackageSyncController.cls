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
        @AuraEnabled public String releaseName;       // Catalogue_Release__c name alone (grouping)
        @AuraEnabled public String releaseStatus;     // Draft | Published | Superseded | ''
        @AuraEnabled public String perClaimLimitLabel;// "$750 Per Claim" ('' when unset)
        @AuraEnabled public String deductibleLabel;   // "$100 Deductible" ('' when unset)
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
        // Master-pane eligibility flags (additive). The console filters the
        // MASTER pane on these two plus the package's own Is_Active__c, which
        // the query already enforces (shouldShowInCatalogue), so the dealer pane
        // and the mirror staleness comparison keep the full catalogue.
        @AuraEnabled public Boolean releasePublished; // release != null && Status__c == 'Published'
        @AuraEnabled public Boolean planTypeActive;   // package group != null && Active__c == true

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
        // Dealer-level premium vehicle fee settings (the dealer Account fields —
        // this dealer-wide section sits above every package).
        @AuraEnabled public Decimal premiumFeeOverrideAmount;  // the dealer's override, null when not set
        @AuraEnabled public String premiumFeeOverrideDisplay;  // server-formatted ("$250" / '')
        @AuraEnabled public Boolean chargePremiumVehicleFee;   // true (default) = fees are charged
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
                SELECT Id, Name, RecordType.DeveloperName,
                       Premium_Fee_Override_Amount__c, Charge_Premium_Vehicle_Fee__c
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
            dto.premiumFeeOverrideAmount = accounts[0].Premium_Fee_Override_Amount__c;
            dto.premiumFeeOverrideDisplay = accounts[0].Premium_Fee_Override_Amount__c == null
                ? '' : amountText(accounts[0].Premium_Fee_Override_Amount__c);
            dto.chargePremiumVehicleFee = accounts[0].Charge_Premium_Vehicle_Fee__c == true;
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
                           Original_Package_Term_Cost__c,
                           Markup__c, Markup_Type__c, Discount_Type__c, Discount_Value__c,
                           Sales_Rep_Incentive__c
                    FROM Dealer_Package_Term__c
                    WHERE Dealer_Package__c IN :dpIds AND Package_Term__c != null
                ]) {
                    dealerTerms.put(t.Dealer_Package__c + '_' + t.Package_Term__c, t);
                }
                for (Dealer_Package_Option__c o : [
                    SELECT Id, Dealer_Package__c, Dealer_Package_Term__c, Package_Option__c, Option__c,
                           Selection_Type__c, Inclusion__c, Exclusion__c, Category__c,
                           Minimum_Value__c, Maximum_Value__c, Original_Package_Option_Price__c,
                           Is_Removed__c, Dealer_Markup__c, Markup_Type__c, Discount_Type__c,
                           Discount_Value__c
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
                u.releaseName = releaseNameOf(m);
                u.releaseStatus = releaseStatusOf(m);
                u.releasePublished = isReleasePublished(m);
                u.planTypeActive = m.Package_Group__r != null
                    && m.Package_Group__r.Active__c == true;
                u.perClaimLimitLabel = perClaimLimitLabel(m.Coverage_per_claim__c);
                u.deductibleLabel = deductibleLabel(m.Deductible__c);
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
                       Original_Package_Term_Cost__c,
                       Markup__c, Markup_Type__c, Discount_Type__c, Discount_Value__c,
                       Sales_Rep_Incentive__c
                FROM Dealer_Package_Term__c
                WHERE Dealer_Package__c IN :ids AND Package_Term__c != null
            ]) {
                dealerTerms.put(t.Dealer_Package__c + '_' + t.Package_Term__c, t);
            }
            for (Dealer_Package_Option__c o : [
                SELECT Id, Dealer_Package__c, Dealer_Package_Term__c, Package_Option__c, Option__c,
                       Selection_Type__c, Inclusion__c, Exclusion__c, Category__c,
                       Minimum_Value__c, Maximum_Value__c, Original_Package_Option_Price__c,
                       Is_Removed__c, Dealer_Markup__c, Markup_Type__c, Discount_Type__c,
                       Discount_Value__c
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
    // 4. Dealer authoring — the console's two-pane authoring surface
    //
    //    Everything below is DEALER-SIDE only: it reads and writes Dealer_*
    //    records and never performs DML on any master object (Package__c /
    //    Package_Tier__c / Package_Term__c / Package_Option__c / Option__c /
    //    Vehicle_Schedule__c / Vehicle_Schedule_Member__c). Every write honours
    //    the package-sync kill switch and runs allOrNone = false, reporting the
    //    rows it could not save in plain words (never an API / field name).
    // =========================================================================

    /** One option row (keep/remove + local option pricing). */
    public class DealerOptionRow {
        @AuraEnabled public Id dealerOptionId;
        @AuraEnabled public Id masterOptionId;
        @AuraEnabled public String optionName;
        @AuraEnabled public String selectionType;   // Included | Optional
        @AuraEnabled public String category;
        @AuraEnabled public Boolean isRemoved;      // dealer keep/remove decision
        @AuraEnabled public Decimal originalPrice;  // stored anchor (frozen if local pricing)
        @AuraEnabled public String discountType;
        @AuraEnabled public Decimal discountValue;
        @AuraEnabled public String markupType;
        @AuraEnabled public Decimal markupValue;
        @AuraEnabled public Decimal netCost;        // formula, read-only
        @AuraEnabled public Decimal retailPrice;    // formula, read-only
        @AuraEnabled public Boolean anchorFrozen;
        public DealerOptionRow() { isRemoved = false; anchorFrozen = false; }
    }

    /**
     * One coverage tier of a dealer package (the read-only grouping label the
     * console prints in the Tier Name column of the expanded terms table).
     */
    public class DealerTierRow {
        @AuraEnabled public String tierKey;    // master tier id (fallback: the mirror id)
        @AuraEnabled public String tierName;
        public DealerTierRow() {}
    }

    /** One term row (discount / incentive / markup authoring + its options). */
    public class DealerTermRow {
        @AuraEnabled public Id dealerTermId;
        @AuraEnabled public Id masterTermId;
        @AuraEnabled public String name;
        @AuraEnabled public String months;
        @AuraEnabled public String tierKey;   // master tier id ('' when the term is tier-less)
        @AuraEnabled public String tierName;  // the tier's name ('' when the term is tier-less)
        @AuraEnabled public Decimal originalCost;
        @AuraEnabled public String discountType;
        @AuraEnabled public Decimal discountValue;
        @AuraEnabled public String markupType;
        @AuraEnabled public Decimal markupValue;
        @AuraEnabled public Decimal salesRepIncentive;
        @AuraEnabled public Decimal premiumFee;       // dealer premium vehicle fee (null = not applied)
        @AuraEnabled public Decimal masterPremiumFee; // the master term's own fee — the default on re-enable
        @AuraEnabled public Decimal netCost;
        @AuraEnabled public Decimal retailPrice;
        @AuraEnabled public Boolean anchorFrozen;
        @AuraEnabled public List<DealerOptionRow> options;   // term-level optional options
        public DealerTermRow() {
            options = new List<DealerOptionRow>();
            anchorFrozen = false;
        }
    }

    /** One dealer package accordion row for the authoring pane. */
    public class DealerPackageRow {
        @AuraEnabled public Id dealerPackageId;
        @AuraEnabled public Id masterPackageId;
        @AuraEnabled public String name;
        @AuraEnabled public String recordTypeLabel;
        @AuraEnabled public String planTypeLabel;
        @AuraEnabled public String releaseName;       // Catalogue_Release__c name alone (grouping)
        @AuraEnabled public String releaseStatus;     // Draft | Published | Superseded | ''
        @AuraEnabled public String perClaimLimitLabel;// "$750 Per Claim" ('' when unset)
        @AuraEnabled public String deductibleLabel;   // "$100 Deductible" ('' when unset)
        @AuraEnabled public Decimal commercialVehicleSurcharge; // dealer-owned commercial figure
        @AuraEnabled public Decimal masterCommercialSurcharge;  // the master's commercial value (seed source)
        @AuraEnabled public String masterCommercialLabel;       // "Master: $x" / "Master: not set"
        @AuraEnabled public String lastSyncedLabel;
        @AuraEnabled public Boolean isActive;          // Active (default) / Inactive — soft display state
        @AuraEnabled public List<DealerTermRow> terms;
        @AuraEnabled public List<DealerTierRow> tiers;             // coverage tiers (grouping)
        @AuraEnabled public List<DealerOptionRow> includedOptions; // package-level included add-ons
        public DealerPackageRow() {
            terms = new List<DealerTermRow>();
            tiers = new List<DealerTierRow>();
            includedOptions = new List<DealerOptionRow>();
        }
    }

    /** getDealerAuthoring payload. */
    public class AuthoringDTO {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Boolean isDealerAccount;
        @AuraEnabled public Boolean syncEnabled;
        @AuraEnabled public String syncEnabledMessage;
        @AuraEnabled public List<DealerPackageRow> packages;
        // Dealer-level premium vehicle fee settings (the dealer Account fields —
        // dealer-wide, applies across every package of this dealer).
        @AuraEnabled public Decimal premiumFeeOverrideAmount;  // the dealer's override, null when not set
        @AuraEnabled public String premiumFeeOverrideDisplay;  // server-formatted ("$250" / '')
        @AuraEnabled public Boolean chargePremiumVehicleFee;   // true (default) = fees are charged
        public AuthoringDTO() { packages = new List<DealerPackageRow>(); }
    }

    /** Result envelope for the authoring writes. */
    public class AuthoringResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Integer updatedCount;
        @AuraEnabled public Integer skippedCount;
        @AuraEnabled public List<String> skippedReasons;
        public AuthoringResult() {
            success = false;
            updatedCount = 0;
            skippedCount = 0;
            skippedReasons = new List<String>();
        }
    }

    private static final String AUTHORING_REJECTED_MESSAGE =
        'One or more changes could not be saved. Check the values and try again.';

    /**
     * Authoring read: every dealer mirror of the account with its terms,
     * package-level included options and term-level optional options, carrying
     * the fields the console edits (discount / incentive / markup / removal /
     * dealer commercial price). Read-only; never touches master records.
     */
    @AuraEnabled
    public static AuthoringDTO getDealerAuthoring(Id accountId) {
        AuthoringDTO dto = new AuthoringDTO();
        dto.accountId = accountId;
        dto.syncEnabled = PortalFeatureFlagService.isDealerSyncEnabled();
        dto.syncEnabledMessage = dto.syncEnabled
            ? 'Dealer pricing and options can be edited.'
            : FLAG_OFF_MESSAGE;
        try {
            assertReadAccess();
            List<Account> accounts = [
                SELECT Id, Name, RecordType.DeveloperName,
                       Premium_Fee_Override_Amount__c, Charge_Premium_Vehicle_Fee__c
                FROM Account WHERE Id = :accountId LIMIT 1
            ];
            if (accounts.isEmpty()) {
                dto.isDealerAccount = false;
                dto.accountName = '';
                return dto;
            }
            dto.accountName = accounts[0].Name;
            dto.premiumFeeOverrideAmount = accounts[0].Premium_Fee_Override_Amount__c;
            dto.premiumFeeOverrideDisplay = accounts[0].Premium_Fee_Override_Amount__c == null
                ? '' : amountText(accounts[0].Premium_Fee_Override_Amount__c);
            dto.chargePremiumVehicleFee = accounts[0].Charge_Premium_Vehicle_Fee__c == true;
            dto.isDealerAccount = accounts[0].RecordType != null
                && accounts[0].RecordType.DeveloperName == DEALER_ACCOUNT_RT;
            if (!dto.isDealerAccount) return dto;

            Map<Id, Dealer_Package__c> dps = new Map<Id, Dealer_Package__c>([
                SELECT Id, Name, Dealer__c, Package__c, RecordType.Name, RecordType.DeveloperName,
                       Plan_Type__r.Name, Commercial_Vehicle_Surcharge_Fee__c,
                       Package__r.Commercial_Vehicle_Surcharge_Fee__c,
                       Per_Claim_Limit__c, Deductable__c, Active__c,
                       Package__r.Package_Group__r.Catalogue_Release__r.Name,
                       Package__r.Package_Group__r.Catalogue_Release__r.Status__c,
                       Last_Synced_At__c, CreatedDate
                FROM Dealer_Package__c
                WHERE Dealer__c = :accountId
                ORDER BY Name
            ]);
            if (dps.isEmpty()) return dto;

            Map<Id, DealerPackageRow> rowByDp = new Map<Id, DealerPackageRow>();
            for (Dealer_Package__c dp : dps.values()) {
                DealerPackageRow r = new DealerPackageRow();
                r.dealerPackageId = dp.Id;
                r.masterPackageId = dp.Package__c;
                r.name = dp.Name;
                r.recordTypeLabel = dp.RecordType != null ? dp.RecordType.Name : '';
                r.planTypeLabel = dp.Plan_Type__r != null ? dp.Plan_Type__r.Name : '';
                r.releaseName = (dp.Package__r != null && dp.Package__r.Package_Group__r != null
                    && dp.Package__r.Package_Group__r.Catalogue_Release__r != null)
                    ? dp.Package__r.Package_Group__r.Catalogue_Release__r.Name : '';
                r.releaseStatus = (dp.Package__r != null && dp.Package__r.Package_Group__r != null
                    && dp.Package__r.Package_Group__r.Catalogue_Release__r != null)
                    ? dp.Package__r.Package_Group__r.Catalogue_Release__r.Status__c : '';
                r.perClaimLimitLabel = perClaimLimitLabel(dp.Per_Claim_Limit__c);
                r.deductibleLabel = deductibleLabel(dp.Deductable__c);
                r.isActive = dp.Active__c == true;
                r.commercialVehicleSurcharge = dp.Commercial_Vehicle_Surcharge_Fee__c;
                // The master value this dealer figure was seeded from (read-only
                // reference; the dealer figure itself is dealer-owned and never
                // refreshed from it). Blank master → plain "Master: not set".
                r.masterCommercialSurcharge = dp.Package__r != null
                    ? dp.Package__r.Commercial_Vehicle_Surcharge_Fee__c : null;
                r.masterCommercialLabel = r.masterCommercialSurcharge == null
                    ? 'Master: not set' : 'Master: ' + amountText(r.masterCommercialSurcharge);
                Datetime wm = dp.Last_Synced_At__c != null ? dp.Last_Synced_At__c : dp.CreatedDate;
                r.lastSyncedLabel = wm == null ? '' : 'Last synced ' + formatDate(wm);
                rowByDp.put(dp.Id, r);
            }

            Map<Id, DealerTermRow> termRowById = new Map<Id, DealerTermRow>();

            // Coverage tiers of each dealer mirror — the read-only grouping label
            // for the console's expanded terms table (the tier NAME the server
            // supplies; the console never derives it). Purely additive: the term
            // rows themselves are unchanged apart from their tier key / label.
            Map<Id, List<DealerTierRow>> tiersByDp = new Map<Id, List<DealerTierRow>>();
            Map<String, String> tierNameByTermKey = new Map<String, String>();
            for (Dealer_Package_Tier__c dt : [
                SELECT Id, Dealer_Package__c, Package_Tier__c, Name
                FROM Dealer_Package_Tier__c
                WHERE Dealer_Package__c IN :dps.keySet()
                ORDER BY Name
            ]) {
                DealerTierRow tierRow = new DealerTierRow();
                tierRow.tierKey = dt.Package_Tier__c != null ? String.valueOf(dt.Package_Tier__c) : String.valueOf(dt.Id);
                tierRow.tierName = dt.Name;
                if (!tiersByDp.containsKey(dt.Dealer_Package__c)) {
                    tiersByDp.put(dt.Dealer_Package__c, new List<DealerTierRow>());
                }
                tiersByDp.get(dt.Dealer_Package__c).add(tierRow);
                if (dt.Package_Tier__c != null) {
                    tierNameByTermKey.put(dt.Dealer_Package__c + '_' + dt.Package_Tier__c, dt.Name);
                }
            }
            for (DealerPackageRow pr : rowByDp.values()) {
                List<DealerTierRow> tierRows = tiersByDp.get(pr.dealerPackageId);
                pr.tiers = tierRows == null ? new List<DealerTierRow>() : tierRows;
            }

            for (Dealer_Package_Term__c t : [
                SELECT Id, Dealer_Package__c, Dealer_Package_Tier__c, Package_Tier__c, Package_Term__c, Name, Month__c,
                       Original_Package_Term_Cost__c, Net_Cost__c, Retail_Price__c,
                       Markup__c, Markup_Type__c, Discount_Type__c, Discount_Value__c,
                       Sales_Rep_Incentive__c, Premium_Model_Fee__c,
                       Package_Term__r.Premium_Model_Fee__c
                FROM Dealer_Package_Term__c
                WHERE Dealer_Package__c IN :dps.keySet()
                ORDER BY Name
            ]) {
                DealerTermRow tr = new DealerTermRow();
                tr.dealerTermId = t.Id;
                tr.masterTermId = t.Package_Term__c;
                tr.name = t.Name;
                tr.months = t.Month__c;
                tr.tierKey = t.Package_Tier__c != null ? String.valueOf(t.Package_Tier__c) : '';
                tr.tierName = t.Package_Tier__c != null
                    ? tierNameByTermKey.get(t.Dealer_Package__c + '_' + t.Package_Tier__c)
                    : '';
                if (tr.tierName == null) tr.tierName = '';
                tr.originalCost = t.Original_Package_Term_Cost__c;
                tr.discountType = t.Discount_Type__c;
                tr.discountValue = t.Discount_Value__c;
                tr.markupType = t.Markup_Type__c;
                tr.markupValue = t.Markup__c;
                tr.salesRepIncentive = t.Sales_Rep_Incentive__c;
                tr.premiumFee = t.Premium_Model_Fee__c;
                tr.masterPremiumFee = t.Package_Term__r != null
                    ? t.Package_Term__r.Premium_Model_Fee__c : null;
                tr.netCost = t.Net_Cost__c;
                tr.retailPrice = t.Retail_Price__c;
                tr.anchorFrozen = DealerPackageSyncService.hasLocalTermPricing(t);
                DealerPackageRow pr = rowByDp.get(t.Dealer_Package__c);
                if (pr != null) pr.terms.add(tr);
                termRowById.put(t.Id, tr);
            }

            for (Dealer_Package_Option__c o : [
                SELECT Id, Dealer_Package__c, Dealer_Package_Term__c, Package_Option__c, Option__c,
                       Option__r.Name, Selection_Type__c, Category__c, Is_Removed__c,
                       Original_Package_Option_Price__c, Net_Cost__c, Retail_Price__c,
                       Dealer_Markup__c, Markup_Type__c, Discount_Type__c, Discount_Value__c
                FROM Dealer_Package_Option__c
                WHERE Dealer_Package__c IN :dps.keySet()
                ORDER BY Option__r.Name
            ]) {
                DealerOptionRow orow = new DealerOptionRow();
                orow.dealerOptionId = o.Id;
                orow.masterOptionId = o.Package_Option__c;
                orow.optionName = o.Option__r != null ? o.Option__r.Name : '';
                orow.selectionType = o.Selection_Type__c;
                orow.category = o.Category__c;
                orow.isRemoved = o.Is_Removed__c == true;
                orow.originalPrice = o.Original_Package_Option_Price__c;
                orow.discountType = o.Discount_Type__c;
                orow.discountValue = o.Discount_Value__c;
                orow.markupType = o.Markup_Type__c;
                orow.markupValue = o.Dealer_Markup__c;
                orow.netCost = o.Net_Cost__c;
                orow.retailPrice = o.Retail_Price__c;
                orow.anchorFrozen = DealerPackageSyncService.hasLocalOptionPricing(o);

                if (o.Dealer_Package_Term__c != null && termRowById.containsKey(o.Dealer_Package_Term__c)) {
                    termRowById.get(o.Dealer_Package_Term__c).options.add(orow);
                } else {
                    DealerPackageRow pr = rowByDp.get(o.Dealer_Package__c);
                    if (pr != null) pr.includedOptions.add(orow);
                }
            }

            dto.packages = new List<DealerPackageRow>(rowByDp.values());
            return dto;
        } catch (Exception e) {
            throw new AuraHandledException(GENERIC_ERROR_MESSAGE);
        }
    }

    /** Term pricing authoring: discount, sales-rep incentive and markup. */
    @AuraEnabled
    public static AuthoringResult saveDealerTermPricing(
        Id dealerTermId, String discountType, Decimal discountValue,
        String markupType, Decimal markupValue, Decimal salesRepIncentive
    ) {
        AuthoringResult result = new AuthoringResult();
        try {
            assertReadAccess();
            if (dealerTermId == null) {
                result.message = 'A dealer term is required.';
                return result;
            }
            if (!PortalFeatureFlagService.isDealerSyncEnabled()) {
                result.message = FLAG_OFF_MESSAGE;
                return result;
            }
            // Dealer term only — never a master Package_Term__c.
            List<Dealer_Package_Term__c> guard = [
                SELECT Id FROM Dealer_Package_Term__c WHERE Id = :dealerTermId LIMIT 1
            ];
            if (guard.isEmpty()) {
                result.message = 'This term is not available to the dealer.';
                return result;
            }
            Dealer_Package_Term__c t = new Dealer_Package_Term__c(Id = dealerTermId);
            // Defensive type default. The console's dropdown shows a default type
            // ('%' discount / '$' markup) even when the underlying value is blank,
            // so a value can arrive with a blank type. A blank type makes the
            // Net_Cost__c / Retail_Price__c formulas ignore the amount entirely
            // (ISBLANK(TEXT(type)) branch), so when a value is supplied we store the
            // same default type the console displays instead of leaving it null.
            t.Discount_Type__c = String.isBlank(discountType)
                ? (discountValue == null ? null : '%') : discountType;
            t.Discount_Value__c = discountValue;
            t.Markup_Type__c = String.isBlank(markupType)
                ? (markupValue == null ? null : '$') : markupType;
            t.Markup__c = markupValue;
            t.Sales_Rep_Incentive__c = salesRepIncentive;

            // allOrNone = false — a rejected value never fails the whole action.
            Database.SaveResult[] saved = Database.update(new List<Dealer_Package_Term__c>{ t }, false);
            applyAuthoringSaveResults(saved, result);
            return result;
        } catch (Exception e) {
            result.success = false;
            result.message = GENERIC_ERROR_MESSAGE;
            return result;
        }
    }

    /**
     * Per-term premium vehicle fee. This is the ONE place the dealer writes
     * Dealer_Package_Term__c.Premium_Model_Fee__c:
     *   • amount != null → store it (fee ON for this term),
     *   • amount == null → blank the field (fee OFF).
     * The fee is a separate per-term amount — it is NOT part of the Net_Cost__c
     * or Retail_Price__c formulas, so clearing or changing it never moves the
     * dealer's Retail Price. Dealer term only — never a master Package_Term__c.
     */
    @AuraEnabled
    public static AuthoringResult saveDealerTermPremiumFee(Id dealerTermId, Decimal amount) {
        AuthoringResult result = new AuthoringResult();
        try {
            assertReadAccess();
            if (dealerTermId == null) {
                result.message = 'A dealer term is required.';
                return result;
            }
            if (!PortalFeatureFlagService.isDealerSyncEnabled()) {
                result.message = FLAG_OFF_MESSAGE;
                return result;
            }
            List<Dealer_Package_Term__c> guard = [
                SELECT Id FROM Dealer_Package_Term__c WHERE Id = :dealerTermId LIMIT 1
            ];
            if (guard.isEmpty()) {
                result.message = 'This term is not available to the dealer.';
                return result;
            }
            Dealer_Package_Term__c t = new Dealer_Package_Term__c(Id = dealerTermId);
            // null clears the field — "off" means no premium fee on this term.
            t.Premium_Model_Fee__c = amount;

            Database.SaveResult[] saved = Database.update(
                new List<Dealer_Package_Term__c>{ t }, false);
            applyAuthoringSaveResults(saved, result);
            if (result.success) {
                result.message = amount == null
                    ? 'Premium fee removed from this term.'
                    : 'Premium fee of ' + amountText(amount) + ' saved for this term.';
            }
            return result;
        } catch (Exception e) {
            result.success = false;
            result.message = GENERIC_ERROR_MESSAGE;
            return result;
        }
    }

    /**
     * Package-level shortcut: blank the premium vehicle fee on EVERY term of one
     * dealer package (the console's "Remove Premium Fee from Package"). Blanks
     * only rows that currently carry a fee; Retail Price is untouched because the
     * fee is not part of the Retail formula. allOrNone = false.
     */
    @AuraEnabled
    public static AuthoringResult clearDealerPackagePremiumFees(Id dealerPackageId) {
        AuthoringResult result = new AuthoringResult();
        try {
            assertReadAccess();
            if (dealerPackageId == null) {
                result.message = 'A dealer package is required.';
                return result;
            }
            if (!PortalFeatureFlagService.isDealerSyncEnabled()) {
                result.message = FLAG_OFF_MESSAGE;
                return result;
            }
            List<Dealer_Package__c> guard = [
                SELECT Id FROM Dealer_Package__c WHERE Id = :dealerPackageId LIMIT 1
            ];
            if (guard.isEmpty()) {
                result.message = 'This package is not available to the dealer.';
                return result;
            }
            List<Dealer_Package_Term__c> updates = new List<Dealer_Package_Term__c>();
            for (Dealer_Package_Term__c t : [
                SELECT Id, Premium_Model_Fee__c FROM Dealer_Package_Term__c
                WHERE Dealer_Package__c = :dealerPackageId AND Premium_Model_Fee__c != null
            ]) {
                updates.add(new Dealer_Package_Term__c(Id = t.Id, Premium_Model_Fee__c = null));
            }
            if (updates.isEmpty()) {
                result.success = true;
                result.message = 'No premium fees to remove on this package.';
                return result;
            }
            applyAuthoringSaveResults(Database.update(updates, false), result);
            if (result.success) {
                result.message = 'Premium fee removed from '
                    + updates.size() + (updates.size() == 1 ? ' term.' : ' terms.');
            }
            return result;
        } catch (Exception e) {
            result.success = false;
            result.message = GENERIC_ERROR_MESSAGE;
            return result;
        }
    }

    /**
     * Package-level bulk discount: set ONE discount (type + value) on EVERY term
     * of a dealer package in a single write (the console's "Bulk Discount" strip).
     * Writes ONLY Discount_Type__c / Discount_Value__c — never Markup__c,
     * Markup_Type__c, Sales_Rep_Incentive__c or the premium fee. Setting the
     * discount freezes the stored wholesale price anchor on every touched term
     * (the same rule as saving a discount on a single term). allOrNone = false.
     */
    @AuraEnabled
    public static AuthoringResult applyDealerPackageTermDiscount(
        Id dealerPackageId, String discountType, Decimal discountValue
    ) {
        AuthoringResult result = new AuthoringResult();
        try {
            assertReadAccess();
            if (dealerPackageId == null) {
                result.message = 'A dealer package is required.';
                return result;
            }
            if (!PortalFeatureFlagService.isDealerSyncEnabled()) {
                result.message = FLAG_OFF_MESSAGE;
                return result;
            }
            List<Dealer_Package__c> guard = [
                SELECT Id FROM Dealer_Package__c WHERE Id = :dealerPackageId LIMIT 1
            ];
            if (guard.isEmpty()) {
                result.message = 'This package is not available to the dealer.';
                return result;
            }
            // Blank or zero is a no-op by design — "Clear Discount" is the only
            // removal path, and a zero discount is never written.
            if (discountValue == null || discountValue == 0) {
                result.success = true;
                result.message = 'Enter a discount above zero to apply to every term.';
                return result;
            }
            String t = String.isBlank(discountType) ? '%' : discountType;
            List<Dealer_Package_Term__c> updates = new List<Dealer_Package_Term__c>();
            for (Dealer_Package_Term__c row : [
                SELECT Id FROM Dealer_Package_Term__c
                WHERE Dealer_Package__c = :dealerPackageId
            ]) {
                // Only the two discount fields — every other authoring value is left alone.
                updates.add(new Dealer_Package_Term__c(
                    Id = row.Id,
                    Discount_Type__c = t,
                    Discount_Value__c = discountValue
                ));
            }
            if (updates.isEmpty()) {
                result.success = true;
                result.message = 'This package has no terms to discount.';
                return result;
            }
            applyAuthoringSaveResults(Database.update(updates, false), result);
            if (result.success) {
                String shown = '$'.equals(t)
                    ? amountText(discountValue)
                    : (discountValue == null ? '' : String.valueOf(discountValue) + '%');
                result.message = 'Discount of ' + shown + ' applied to '
                    + updates.size() + (updates.size() == 1 ? ' term.' : ' terms.');
            }
            return result;
        } catch (Exception e) {
            result.success = false;
            result.message = GENERIC_ERROR_MESSAGE;
            return result;
        }
    }

    /**
     * Package-level bulk clear: remove the discount from every term of one dealer
     * package (the console's "Clear Discount" link). Blanks ONLY
     * Discount_Type__c / Discount_Value__c, and only on terms that currently carry
     * a discount — markup, incentive and the premium fee are never touched.
     * No-op-safe with an honest count. allOrNone = false.
     */
    @AuraEnabled
    public static AuthoringResult clearDealerPackageTermDiscounts(Id dealerPackageId) {
        AuthoringResult result = new AuthoringResult();
        try {
            assertReadAccess();
            if (dealerPackageId == null) {
                result.message = 'A dealer package is required.';
                return result;
            }
            if (!PortalFeatureFlagService.isDealerSyncEnabled()) {
                result.message = FLAG_OFF_MESSAGE;
                return result;
            }
            List<Dealer_Package__c> guard = [
                SELECT Id FROM Dealer_Package__c WHERE Id = :dealerPackageId LIMIT 1
            ];
            if (guard.isEmpty()) {
                result.message = 'This package is not available to the dealer.';
                return result;
            }
            List<Dealer_Package_Term__c> updates = new List<Dealer_Package_Term__c>();
            for (Dealer_Package_Term__c row : [
                SELECT Id, Discount_Type__c, Discount_Value__c FROM Dealer_Package_Term__c
                WHERE Dealer_Package__c = :dealerPackageId
                  AND (Discount_Type__c != null OR Discount_Value__c != null)
            ]) {
                updates.add(new Dealer_Package_Term__c(
                    Id = row.Id, Discount_Type__c = null, Discount_Value__c = null));
            }
            if (updates.isEmpty()) {
                result.success = true;
                result.message = 'No discounts to clear on this package.';
                return result;
            }
            applyAuthoringSaveResults(Database.update(updates, false), result);
            if (result.success) {
                result.message = 'Discount cleared from '
                    + updates.size() + (updates.size() == 1 ? ' term.' : ' terms.');
            }
            return result;
        } catch (Exception e) {
            result.success = false;
            result.message = GENERIC_ERROR_MESSAGE;
            return result;
        }
    }

    /** Option pricing authoring: discount and markup on a dealer option. */
    @AuraEnabled
    public static AuthoringResult saveDealerOptionPricing(
        Id dealerOptionId, String discountType, Decimal discountValue,
        String markupType, Decimal markupValue
    ) {
        AuthoringResult result = new AuthoringResult();
        try {
            assertReadAccess();
            if (dealerOptionId == null) {
                result.message = 'A dealer add-on is required.';
                return result;
            }
            if (!PortalFeatureFlagService.isDealerSyncEnabled()) {
                result.message = FLAG_OFF_MESSAGE;
                return result;
            }
            List<Dealer_Package_Option__c> guard = [
                SELECT Id FROM Dealer_Package_Option__c WHERE Id = :dealerOptionId LIMIT 1
            ];
            if (guard.isEmpty()) {
                result.message = 'This add-on is not available to the dealer.';
                return result;
            }
            Dealer_Package_Option__c o = new Dealer_Package_Option__c(Id = dealerOptionId);
            // Defensive type default — same rule as the term save: a value with a
            // blank type would otherwise be ignored by the option Net/Retail
            // formulas. Store the default type the console shows.
            o.Discount_Type__c = String.isBlank(discountType)
                ? (discountValue == null ? null : '%') : discountType;
            o.Discount_Value__c = discountValue;
            o.Markup_Type__c = String.isBlank(markupType)
                ? (markupValue == null ? null : '$') : markupType;
            o.Dealer_Markup__c = markupValue;

            Database.SaveResult[] saved = Database.update(new List<Dealer_Package_Option__c>{ o }, false);
            applyAuthoringSaveResults(saved, result);
            return result;
        } catch (Exception e) {
            result.success = false;
            result.message = GENERIC_ERROR_MESSAGE;
            return result;
        }
    }

    /**
     * Keep / remove a mirrored option. Dealers only KEEP or REMOVE options
     * mirrored from the master — they never invent option content. The row is
     * flagged (never deleted) so the next reconcile neither re-creates nor
     * refreshes it.
     */
    @AuraEnabled
    public static AuthoringResult setDealerOptionRemoved(Id dealerOptionId, Boolean removed) {
        AuthoringResult result = new AuthoringResult();
        try {
            assertReadAccess();
            if (dealerOptionId == null) {
                result.message = 'A dealer add-on is required.';
                return result;
            }
            if (!PortalFeatureFlagService.isDealerSyncEnabled()) {
                result.message = FLAG_OFF_MESSAGE;
                return result;
            }
            List<Dealer_Package_Option__c> guard = [
                SELECT Id FROM Dealer_Package_Option__c WHERE Id = :dealerOptionId LIMIT 1
            ];
            if (guard.isEmpty()) {
                result.message = 'This add-on is not available to the dealer.';
                return result;
            }
            Database.SaveResult[] saved = Database.update(new List<Dealer_Package_Option__c>{
                new Dealer_Package_Option__c(Id = dealerOptionId, Is_Removed__c = removed == true)
            }, false);
            applyAuthoringSaveResults(saved, result);
            return result;
        } catch (Exception e) {
            result.success = false;
            result.message = GENERIC_ERROR_MESSAGE;
            return result;
        }
    }

    /**
     * Dealer commercial price (flat per-dealer figure). Reuses the existing
     * Dealer_Package__c.Commercial_Vehicle_Surcharge_Fee__c field — dealer-owned,
     * seeded once at mirror creation and never refreshed from the master.
     */
    @AuraEnabled
    public static AuthoringResult saveDealerCommercialPrice(Id dealerPackageId, Decimal amount) {
        AuthoringResult result = new AuthoringResult();
        try {
            assertReadAccess();
            if (dealerPackageId == null) {
                result.message = 'A dealer package is required.';
                return result;
            }
            List<Dealer_Package__c> guard = [
                SELECT Id, Dealer__c FROM Dealer_Package__c WHERE Id = :dealerPackageId LIMIT 1
            ];
            if (guard.isEmpty()) {
                result.message = 'This package is not available to the dealer.';
                return result;
            }
            if (!PortalFeatureFlagService.isDealerSyncEnabled()) {
                result.message = FLAG_OFF_MESSAGE;
                return result;
            }
            Database.SaveResult[] saved = Database.update(new List<Dealer_Package__c>{
                new Dealer_Package__c(Id = dealerPackageId, Commercial_Vehicle_Surcharge_Fee__c = amount)
            }, false);
            applyAuthoringSaveResults(saved, result);
            return result;
        } catch (Exception e) {
            result.success = false;
            result.message = GENERIC_ERROR_MESSAGE;
            return result;
        }
    }

    /**
     * Dealer-level premium vehicle fee settings — the TWO premium fields on the
     * dealer Account (they apply across EVERY package for this dealer):
     *   • Premium_Fee_Override_Amount__c — this dealer's override of the standard
     *     premium vehicle fee (null = blank = use the standard package/term fee).
     *   • Charge_Premium_Vehicle_Fee__c  — on (default) / off (waive the premium
     *     vehicle fee for this dealer entirely).
     * ONE confirm-gated write for both, honouring the package-sync kill switch and
     * allOrNone = false, with plain-word messages (money formatted server-side).
     * These are Account writes, so field-level update permission is checked first
     * and surfaced plainly rather than letting the write fail silently.
     */
    @AuraEnabled
    public static AuthoringResult saveDealerPremiumSettings(
        Id accountId, Decimal overrideAmount, Boolean chargePremiumFee
    ) {
        AuthoringResult result = new AuthoringResult();
        try {
            assertReadAccess();
            if (accountId == null) {
                result.message = 'A dealer account is required.';
                return result;
            }
            if (!PortalFeatureFlagService.isDealerSyncEnabled()) {
                result.message = FLAG_OFF_MESSAGE;
                return result;
            }
            // Account writes — check field-level update access up front (the class
            // is `without sharing`, so this reads the running user's own access).
            if (!Account.Premium_Fee_Override_Amount__c.getDescribe().isUpdateable()
                || !Account.Charge_Premium_Vehicle_Fee__c.getDescribe().isUpdateable()) {
                result.message = 'You do not have permission to change the dealer premium '
                    + 'fee settings. Ask an administrator to grant access.';
                return result;
            }
            Account dealerAcc = requireDealerAccount(accountId);
            if (dealerAcc == null) {
                result.message = 'This action is for Dealer Account records only.';
                return result;
            }
            // A blank override means "use the standard package/term fees" (null);
            // the charge flag defaults ON, so only an explicit false waives fees.
            Boolean charge = chargePremiumFee != false;
            Database.SaveResult[] saved = Database.update(new List<Account>{
                new Account(
                    Id = accountId,
                    Premium_Fee_Override_Amount__c = overrideAmount,
                    Charge_Premium_Vehicle_Fee__c = charge
                )
            }, false);
            applyAuthoringSaveResults(saved, result);
            if (result.success) {
                result.message = 'Dealer premium fee settings saved. '
                    + (overrideAmount == null
                        ? 'The standard premium vehicle fees apply.'
                        : 'The premium fee override of ' + amountText(overrideAmount)
                            + ' applies for this dealer.')
                    + (charge
                        ? ' Premium vehicle fees are charged.'
                        : ' Premium vehicle fees are waived for this dealer.');
            }
            return result;
        } catch (Exception e) {
            result.success = false;
            result.message = GENERIC_ERROR_MESSAGE;
            return result;
        }
    }

    /**
     * Deliberate, dealer-initiated price-anchor refresh. Re-seeds the stored
     * wholesale anchors from the CURRENT master price for the given dealer
     * packages, overwriting the freeze — the dealer explicitly asks to move to
     * the master's latest price. Markup / discount / incentive are untouched.
     * Writes dealer rows only; allOrNone = false.
     */
    @AuraEnabled
    public static AuthoringResult refreshDealerPriceAnchors(List<Id> dealerPackageIds) {
        AuthoringResult result = new AuthoringResult();
        try {
            assertReadAccess();
            if (dealerPackageIds == null || dealerPackageIds.isEmpty()) {
                result.message = 'Select at least one package.';
                return result;
            }
            if (!PortalFeatureFlagService.isDealerSyncEnabled()) {
                result.message = FLAG_OFF_MESSAGE;
                return result;
            }
            Set<Id> ids = new Set<Id>(dealerPackageIds);

            Map<Id, Dealer_Package_Term__c> terms = new Map<Id, Dealer_Package_Term__c>([
                SELECT Id, Package_Term__c FROM Dealer_Package_Term__c
                WHERE Dealer_Package__c IN :ids AND Package_Term__c != null
            ]);
            Set<Id> masterTermIds = new Set<Id>();
            for (Dealer_Package_Term__c t : terms.values()) masterTermIds.add(t.Package_Term__c);
            Map<Id, Decimal> termPrice = new Map<Id, Decimal>();
            if (!masterTermIds.isEmpty()) {
                for (Package_Term__c mt : [SELECT Id, Price__c FROM Package_Term__c WHERE Id IN :masterTermIds]) {
                    termPrice.put(mt.Id, mt.Price__c);
                }
            }
            List<Dealer_Package_Term__c> termUpdates = new List<Dealer_Package_Term__c>();
            for (Dealer_Package_Term__c t : terms.values()) {
                Decimal p = termPrice.get(t.Package_Term__c);
                if (p != null) termUpdates.add(new Dealer_Package_Term__c(
                    Id = t.Id, Original_Package_Term_Cost__c = p));
            }
            if (!termUpdates.isEmpty()) {
                applyAuthoringSaveResults(Database.update(termUpdates, false), result);
            }

            Map<Id, Dealer_Package_Option__c> opts = new Map<Id, Dealer_Package_Option__c>([
                SELECT Id, Package_Option__c FROM Dealer_Package_Option__c
                WHERE Dealer_Package__c IN :ids AND Package_Option__c != null AND Is_Removed__c = false
            ]);
            Set<Id> masterOptionIds = new Set<Id>();
            for (Dealer_Package_Option__c o : opts.values()) masterOptionIds.add(o.Package_Option__c);
            Map<Id, Decimal> optionPrice = new Map<Id, Decimal>();
            if (!masterOptionIds.isEmpty()) {
                for (Package_Option__c mo : [SELECT Id, Price__c FROM Package_Option__c WHERE Id IN :masterOptionIds]) {
                    optionPrice.put(mo.Id, mo.Price__c);
                }
            }
            List<Dealer_Package_Option__c> optionUpdates = new List<Dealer_Package_Option__c>();
            for (Dealer_Package_Option__c o : opts.values()) {
                Decimal p = optionPrice.get(o.Package_Option__c);
                if (p != null) optionUpdates.add(new Dealer_Package_Option__c(
                    Id = o.Id, Original_Package_Option_Price__c = p));
            }
            if (!optionUpdates.isEmpty()) {
                applyAuthoringSaveResults(Database.update(optionUpdates, false), result);
            }

            if (result.updatedCount == 0 && result.skippedCount == 0) {
                result.success = true;
                result.message = 'Nothing to refresh — every price is already current.';
            } else if (result.skippedCount == 0) {
                result.message = 'Refreshed ' + result.updatedCount + ' dealer price(s) from the master catalogue.';
            }
            return result;
        } catch (Exception e) {
            result.success = false;
            result.message = GENERIC_ERROR_MESSAGE;
            return result;
        }
    }

    /**
     * Activate / deactivate ONE dealer package — the console's per-row
     * Active / Inactive toggle. A soft display / enablement state only: the
     * package stays in the dealer plan and keeps syncing exactly as before, and
     * nothing is deleted. Dealer-package row only; allOrNone = false.
     */
    @AuraEnabled
    public static AuthoringResult setDealerPackageActive(Id dealerPackageId, Boolean active) {
        AuthoringResult result = new AuthoringResult();
        try {
            assertReadAccess();
            if (dealerPackageId == null) {
                result.message = 'A dealer package is required.';
                return result;
            }
            if (!PortalFeatureFlagService.isDealerSyncEnabled()) {
                result.message = FLAG_OFF_MESSAGE;
                return result;
            }
            // Dealer package write — check field-level update access up front
            // (the class is `without sharing`, so this reads the running user's
            // own access) rather than letting the write fail silently.
            if (!Dealer_Package__c.Active__c.getDescribe().isUpdateable()) {
                result.message = 'You do not have permission to change whether a dealer '
                    + 'package is active. Ask an administrator to grant access.';
                return result;
            }
            List<Dealer_Package__c> guard = [
                SELECT Id FROM Dealer_Package__c WHERE Id = :dealerPackageId LIMIT 1
            ];
            if (guard.isEmpty()) {
                result.message = 'This package is not available to the dealer.';
                return result;
            }
            Boolean next = active == true;
            Database.SaveResult[] saved = Database.update(new List<Dealer_Package__c>{
                new Dealer_Package__c(Id = dealerPackageId, Active__c = next)
            }, false);
            applyAuthoringSaveResults(saved, result);
            if (result.success) {
                result.message = next
                    ? 'This dealer package is now Active.'
                    : 'This dealer package is now Inactive.';
            }
            return result;
        } catch (Exception e) {
            result.success = false;
            result.message = GENERIC_ERROR_MESSAGE;
            return result;
        }
    }

    /** Folds an allOrNone = false save into the authoring result (plain words). */
    private static void applyAuthoringSaveResults(Database.SaveResult[] saved, AuthoringResult result) {
        Integer ok = 0;
        Integer skipped = 0;
        if (saved != null) {
            for (Database.SaveResult sr : saved) {
                if (sr.isSuccess()) ok++;
                else skipped++;
            }
        }
        result.updatedCount += ok;
        result.skippedCount += skipped;
        if (skipped > 0) {
            result.success = false;
            result.skippedReasons.add(MIRROR_VALUE_GAP_MESSAGE);
            result.message = AUTHORING_REJECTED_MESSAGE;
        } else {
            result.success = true;
            result.message = 'Saved ' + ok + ' change(s).';
        }
    }

    // =========================================================================
    // 5. Master package detail — the lazy, read-only reference read
    //
    //    Fetched on FIRST EXPAND of a master package row (never bulk-loaded into
    //    the inventory payload — the org carries large option sets). Returns the
    //    tier → term → additional-option structure of ONE master package with
    //    server-formatted reference pricing, so the console stays a dumb
    //    renderer. Strictly read-only: this method performs no DML and never
    //    writes a master record.
    // =========================================================================

    /** One rendered row of a master package's read-only reference table. */
    public class MasterDetailRow {
        @AuraEnabled public String rowId;
        @AuraEnabled public String kind;          // Term | Option
        @AuraEnabled public String label;
        @AuraEnabled public String originalPrice; // server-formatted ("$209")
        @AuraEnabled public String discount;      // always the em dash on reference rows
        @AuraEnabled public String dealerPrice;   // server-formatted reference price
    }

    /** A tier block of a master package (tierName '' when the package has no tiers). */
    public class MasterDetailGroup {
        @AuraEnabled public String groupKey;
        @AuraEnabled public String tierName;
        @AuraEnabled public Boolean hasTier;
        @AuraEnabled public List<MasterDetailRow> rows;
        public MasterDetailGroup() {
            hasTier = false;
            rows = new List<MasterDetailRow>();
        }
    }

    /** getMasterPackageDetail payload — one master package's reference structure. */
    public class MasterPackageDetailDTO {
        @AuraEnabled public Id masterPackageId;
        @AuraEnabled public String name;
        @AuraEnabled public String groupName;     // the package group ("POWERTRAIN")
        @AuraEnabled public String releaseName;   // the catalogue release ("V25")
        @AuraEnabled public String seriesLabel;   // "Master Package Series: V25" ('' when none)
        @AuraEnabled public Boolean hasTiers;
        @AuraEnabled public Integer termCount;
        @AuraEnabled public Integer optionCount;
        @AuraEnabled public List<MasterDetailGroup> groups;
        public MasterPackageDetailDTO() {
            hasTiers = false;
            termCount = 0;
            optionCount = 0;
            groups = new List<MasterDetailGroup>();
        }
    }

    /** The em dash shown wherever a reference row has no value (never a blank). */
    private static final String DASH = '\u2014';

    /** "$209" / "—" — server-side money for the reference table (never client-side). */
    private static String moneyOrDash(Decimal v) {
        return v == null ? DASH : amountText(v);
    }

    /**
     * Read-only detail of ONE master package: its coverage tiers, the terms
     * beneath each tier (tier-less terms fall into a single un-grouped block),
     * and each term's ADDITIONAL (term-level optional) options as sub-rows.
     *
     * Reference pricing mapping (the console's three price columns):
     *   Original Dealer Price = the term's / option's own catalogue price
     *   Discount              = the em dash (nothing is discounted on the master)
     *   Dealer Price          = the same catalogue price (the master baseline)
     *
     * Package-level Included add-ons are deliberately NOT part of this table —
     * they are the dealer pane's own "Included add-ons" block, and the mock's
     * reference table carries terms + their additional options only.
     */
    @AuraEnabled
    public static MasterPackageDetailDTO getMasterPackageDetail(Id masterPackageId) {
        MasterPackageDetailDTO dto = new MasterPackageDetailDTO();
        try {
            assertReadAccess();
            if (masterPackageId == null) return dto;

            List<Package__c> pkgs = [
                SELECT Id, Name, Package_Group__r.Name,
                       Package_Group__r.Catalogue_Release__r.Name
                FROM Package__c
                WHERE Id = :masterPackageId
                LIMIT 1
            ];
            if (pkgs.isEmpty()) return dto;
            Package__c m = pkgs[0];
            dto.masterPackageId = m.Id;
            dto.name = m.Name;
            dto.groupName = m.Package_Group__r != null ? m.Package_Group__r.Name : '';
            dto.releaseName = releaseNameOf(m);
            dto.seriesLabel = String.isBlank(dto.releaseName)
                ? '' : 'Master Package Series: ' + dto.releaseName;

            List<Package_Tier__c> tiers = [
                SELECT Id, Name FROM Package_Tier__c
                WHERE Package__c = :masterPackageId
                ORDER BY Name
            ];
            List<Package_Term__c> terms = [
                SELECT Id, Name, Price__c, Package_Tier__c FROM Package_Term__c
                WHERE Package__c = :masterPackageId
                ORDER BY Name
            ];
            List<Package_Option__c> options = [
                SELECT Id, Option__r.Name, Price__c, Package_Term__c FROM Package_Option__c
                WHERE Package__c = :masterPackageId AND Package_Term__c != null
                ORDER BY Option__r.Name
            ];
            dto.hasTiers = !tiers.isEmpty();
            dto.termCount = terms.size();

            // Option sub-rows keyed by the term they ride on.
            Map<Id, List<MasterDetailRow>> optionsByTerm = new Map<Id, List<MasterDetailRow>>();
            for (Package_Option__c o : options) {
                MasterDetailRow oe = new MasterDetailRow();
                oe.rowId = String.valueOf(o.Id);
                oe.kind = 'Option';
                oe.label = o.Option__r != null && String.isNotBlank(o.Option__r.Name)
                    ? o.Option__r.Name : 'Add-on';
                oe.originalPrice = moneyOrDash(o.Price__c);
                oe.discount = DASH;
                oe.dealerPrice = moneyOrDash(o.Price__c);
                if (!optionsByTerm.containsKey(o.Package_Term__c)) {
                    optionsByTerm.put(o.Package_Term__c, new List<MasterDetailRow>());
                }
                optionsByTerm.get(o.Package_Term__c).add(oe);
                dto.optionCount++;
            }

            // Terms, each followed immediately by its own additional options.
            Map<String, List<MasterDetailRow>> rowsByTier = new Map<String, List<MasterDetailRow>>();
            List<MasterDetailRow> tierlessRows = new List<MasterDetailRow>();
            for (Package_Term__c t : terms) {
                MasterDetailRow tr = new MasterDetailRow();
                tr.rowId = String.valueOf(t.Id);
                tr.kind = 'Term';
                tr.label = t.Name;
                tr.originalPrice = moneyOrDash(t.Price__c);
                tr.discount = DASH;
                tr.dealerPrice = moneyOrDash(t.Price__c);

                List<MasterDetailRow> block = new List<MasterDetailRow>{ tr };
                if (optionsByTerm.containsKey(t.Id)) {
                    block.addAll(optionsByTerm.get(t.Id));
                }
                if (t.Package_Tier__c == null) {
                    tierlessRows.addAll(block);
                } else {
                    String key = String.valueOf(t.Package_Tier__c);
                    if (!rowsByTier.containsKey(key)) rowsByTier.put(key, new List<MasterDetailRow>());
                    rowsByTier.get(key).addAll(block);
                }
            }

            // One group per tier (empty tier blocks are skipped), then the
            // un-grouped block for tier-less terms.
            for (Package_Tier__c tier : tiers) {
                List<MasterDetailRow> rows = rowsByTier.get(String.valueOf(tier.Id));
                if (rows == null || rows.isEmpty()) continue;
                MasterDetailGroup g = new MasterDetailGroup();
                g.groupKey = String.valueOf(tier.Id);
                g.tierName = tier.Name;
                g.hasTier = true;
                g.rows = rows;
                dto.groups.add(g);
            }
            if (!tierlessRows.isEmpty()) {
                MasterDetailGroup g = new MasterDetailGroup();
                g.groupKey = 'no-tier';
                g.tierName = '';
                g.hasTier = false;
                g.rows = tierlessRows;
                dto.groups.add(g);
            }
            return dto;
        } catch (Exception e) {
            throw new AuraHandledException(GENERIC_ERROR_MESSAGE);
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
                   Package_Group__r.Active__c,
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

    /** The catalogue release NAME alone (grouping): "V25" / "V27" ('' when none). */
    private static String releaseNameOf(Package__c m) {
        return (m != null && m.Package_Group__r != null
            && m.Package_Group__r.Catalogue_Release__r != null)
            ? m.Package_Group__r.Catalogue_Release__r.Name : '';
    }

    /** True only when the package's catalogue release is literally 'Published'. */
    private static Boolean isReleasePublished(Package__c m) {
        return m != null && m.Package_Group__r != null
            && m.Package_Group__r.Catalogue_Release__r != null
            && m.Package_Group__r.Catalogue_Release__r.Status__c == 'Published';
    }

    /** The catalogue release STATUS alone: Draft | Published | Superseded | ''. */
    private static String releaseStatusOf(Package__c m) {
        return (m != null && m.Package_Group__r != null
            && m.Package_Group__r.Catalogue_Release__r != null)
            ? m.Package_Group__r.Catalogue_Release__r.Status__c : '';
    }

    /** "$750 Per Claim" — server-formatted; '' when the package carries no limit. */
    private static String perClaimLimitLabel(Decimal v) {
        return v == null ? '' : amountText(v) + ' Per Claim';
    }

    /** "$100 Deductible" — server-formatted; '' when no deductible is set. */
    private static String deductibleLabel(Decimal v) {
        return v == null ? '' : amountText(v) + ' Deductible';
    }

    /** "$1,250.50" / "$750" — whole dollars drop the decimals. Server-side only. */
    private static String amountText(Decimal v) {
        if (v == null) return '';
        Boolean whole = (v == v.setScale(0, System.RoundingMode.HALF_UP));
        String raw = whole ? String.valueOf(v.setScale(0)) : String.valueOf(v.setScale(2));
        Boolean neg = raw.startsWith('-');
        if (neg) raw = raw.substring(1);
        Integer dot = raw.indexOf('.');
        String intPart = dot == -1 ? raw : raw.substring(0, dot);
        String frac = dot == -1 ? '' : raw.substring(dot);
        return (neg ? '-$' : '$') + groupThousands(intPart) + frac;
    }

    /** "10000" → "10,000" (never locale-dependent). */
    private static String groupThousands(String digits) {
        if (String.isBlank(digits)) return '0';
        String out = '';
        Integer count = 0;
        for (Integer i = digits.length() - 1; i >= 0; i--) {
            out = digits.substring(i, i + 1) + out;
            count++;
            if (count == 3 && i > 0) {
                out = ',' + out;
                count = 0;
            }
        }
        return out;
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
        // The dealer commercial figure (Commercial_Vehicle_Surcharge_Fee__c) is
        // dealer-owned — seeded once at mirror creation and never refreshed from
        // the master — so it is deliberately NOT part of the change delta.
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
                // Anchors frozen once the dealer has local pricing: the sync will
                // NOT move them, so a master price edit is not a pending change.
                Boolean price = mterm.Price__c != null
                    && dterm.Original_Package_Term_Cost__c != mterm.Price__c
                    && !DealerPackageSyncService.hasLocalTermPricing(dterm);
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
                && dterm.Original_Package_Term_Cost__c != mterm.Price__c
                && !DealerPackageSyncService.hasLocalTermPricing(dterm);
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
            } else if (dopt.Is_Removed__c == true) {
                // Deliberately removed by the dealer — never (re-)created nor
                // reported as a pending change.
                continue;
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
            else if (dopt.Is_Removed__c == true) continue; // dealer removed it deliberately
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
        Boolean price = mo.Price__c != null && dopt.Original_Package_Option_Price__c != mo.Price__c
            && !DealerPackageSyncService.hasLocalOptionPricing(dopt);
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
            Dealer_Package__c.Active__c,
            Dealer_Package_Term__c.Original_Package_Term_Cost__c,
            Dealer_Package_Term__c.Premium_Model_Fee__c,
            Dealer_Package_Option__c.Original_Package_Option_Price__c,
            Package_Term__c.Price__c,
            Package_Option__c.Price__c,
            Package__c.Is_Active__c,
            Catalogue_Release__c.Status__c,
            // Dealer-level premium vehicle fee settings (read here; written through
            // saveDealerPremiumSettings, which additionally checks update access).
            Account.Premium_Fee_Override_Amount__c,
            Account.Charge_Premium_Vehicle_Fee__c
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