/**
 * DealerPackageBulkActiveController
 *
 * The DEALER pane's bulk Active / Inactive save for the Dealer Package Sync
 * console (dealerPortalPackageSync). Selection → saved state:
 *
 *   • A dealer package whose checkbox was cleared  → Active__c = false
 *   • A dealer package whose checkbox was ticked   → Active__c = true
 *
 * The console sends ONLY the rows whose checkbox differs from the saved state,
 * so saving again with nothing changed writes nothing (idempotent).
 *
 * TRANSPORT NOTE: the toggles arrive as a JSON *string*, not as a typed Apex
 * List<DealerPackageToggle>. Aura's typed-list binding silently produced
 * entries whose dealerPackageId was null (the payload reached the server with
 * the right ids but the DTO lost them), so the contract is now
 * (Id accountId, String togglesJson) and the class deserializes the exact
 * [{ "dealerPackageId": "...", "active": true|false }] array the client builds.
 * That removes the Aura/DTO binding step entirely.
 *
 * Scope is enforced here, never trusted from the client: every Id must resolve
 * to a Dealer_Package__c whose Dealer__c is the account the console is open on.
 * Anything else is reported per row and left untouched. This class NEVER
 * creates a mirror for a master package the dealer does not have — that stays
 * the sync / gap-create flow's job.
 *
 * A soft state only: Active__c is flipped, nothing is deleted, and terms,
 * pricing, discounts, premium fees and sync semantics are untouched.
 *
 * `without sharing` to match the console's admin-service controller, with
 * explicit object/field-level access assertions so it stays safe if the action
 * is ever surfaced to a lesser profile.
 */
public without sharing class DealerPackageBulkActiveController {

    private static final String DEALER_ACCOUNT_RT = 'Dealer_Account';

    /** Upper bound on one bulk save — the dealer pane is never bigger than this. */
    private static final Integer MAX_TOGGLE_ROWS = 200;

    /** Raw payload longer than this is logged as length + first id, not in full. */
    private static final Integer MAX_RAW_LOG_CHARS = 600;

    private static final String NO_CHANGES_MESSAGE = 'There are no package changes to save.';

    private static final String FLAG_OFF_MESSAGE =
        'Package sync is switched off, so package changes are unavailable. '
        + 'An administrator can turn it back on in portal settings.';
    private static final String PERMISSION_MESSAGE =
        'You do not have permission to change whether a dealer package is active. '
        + 'Ask an administrator to grant access.';
    private static final String REJECTED_MESSAGE =
        'This package could not be saved. Try again in a moment.';
    private static final String GENERIC_ERROR_MESSAGE =
        'Something went wrong. Please close this window and try again.';

    // =========================================================================
    // DTO shapes (@AuraEnabled, flat — the LWC is a dumb renderer)
    // =========================================================================

    /** One requested state change from the dealer pane's checkbox selection. */
    public class DealerPackageToggle {
        @AuraEnabled public Id dealerPackageId;
        @AuraEnabled public Boolean active;
        public DealerPackageToggle() {}
    }

    /** Per-row outcome (plain words only — never an API name). */
    public class ToggleRowResult {
        @AuraEnabled public Id dealerPackageId;
        @AuraEnabled public String name;
        @AuraEnabled public Boolean changed;   // true only when a write was attempted
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
    }

    /** Result envelope. */
    public class PackageToggleResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Integer updatedCount;
        @AuraEnabled public Integer unchangedCount;   // already matched the saved state
        @AuraEnabled public Integer failedCount;      // not on this dealer / rejected
        @AuraEnabled public List<ToggleRowResult> results;
        public PackageToggleResult() {
            success = false;
            updatedCount = 0;
            unchangedCount = 0;
            failedCount = 0;
            results = new List<ToggleRowResult>();
        }
    }

    // =========================================================================
    // The save
    // =========================================================================

    /**
     * Applies a dealer pane selection as the packages' saved Active state.
     *
     * @param accountId    the dealer Account the console is open on (record id)
     * @param togglesJson  JSON array of { "dealerPackageId": Id, "active": Boolean }
     *                     — only the rows whose checkbox differs from the saved state
     */
    @AuraEnabled
    public static PackageToggleResult setDealerPackagesActive(
        Id accountId, String togglesJson
    ) {
        PackageToggleResult result = new PackageToggleResult();
        try {
            debugToggles(togglesJson);

            // Deserialize by hand: this is the point that used to lose the ids.
            // A malformed payload is a no-op with the friendly message, never an
            // uncaught exception and never a partial write.
            List<DealerPackageToggle> toggles;
            try {
                toggles = (togglesJson == null || togglesJson.trim().length() == 0)
                    ? new List<DealerPackageToggle>()
                    : (List<DealerPackageToggle>) JSON.deserialize(
                        togglesJson, List<DealerPackageToggle>.class);
            } catch (Exception parseError) {
                System.debug(LoggingLevel.WARN,
                    'dealerToggles parse failed: ' + parseError.getMessage());
                result.message = NO_CHANGES_MESSAGE;
                return result;
            }
            System.debug('dealerToggles parsed=' + (toggles == null ? 0 : toggles.size()));

            if (accountId == null) {
                result.message = 'Open this console from a dealer account and try again.';
                return result;
            }
            if (toggles == null || toggles.isEmpty()) {
                result.message = NO_CHANGES_MESSAGE;
                return result;
            }
            if (toggles.size() > MAX_TOGGLE_ROWS) {
                result.message = 'Too many packages were sent at once. Save them in smaller batches.';
                return result;
            }
            // FLS — exactly the objects/fields this write touches, checked up
            // front (the class is `without sharing`, so these describe calls read
            // the RUNNING user's own access). Deny before any query or DML.
            if (!Account.SObjectType.getDescribe().isAccessible()
                || !Dealer_Package__c.SObjectType.getDescribe().isAccessible()
                || !Dealer_Package__c.SObjectType.getDescribe().isUpdateable()
                || !Dealer_Package__c.Active__c.getDescribe().isAccessible()
                || !Dealer_Package__c.Active__c.getDescribe().isUpdateable()
                || !Dealer_Package__c.Dealer__c.getDescribe().isAccessible()
                || !Dealer_Package__c.Name.getDescribe().isAccessible()) {
                result.message = PERMISSION_MESSAGE;
                return result;
            }
            if (!PortalFeatureFlagService.isDealerSyncEnabled()) {
                result.message = FLAG_OFF_MESSAGE;
                return result;
            }
            if (requireDealerAccount(accountId) == null) {
                result.message = 'This account is not a dealer account, so its packages cannot be changed.';
                return result;
            }

            // Requested state by package id, in the order the console sent them.
            // Duplicates collapse (last request wins) so one package is never
            // written twice in the same save.
            List<Id> orderedIds = new List<Id>();
            Map<Id, Boolean> requested = new Map<Id, Boolean>();
            for (DealerPackageToggle t : toggles) {
                if (t == null || t.dealerPackageId == null) continue;
                if (!requested.containsKey(t.dealerPackageId)) orderedIds.add(t.dealerPackageId);
                requested.put(t.dealerPackageId, t.active == true);
            }
            if (orderedIds.isEmpty()) {
                result.message = NO_CHANGES_MESSAGE;
                return result;
            }

            // Read the SAVED truth for exactly the ids the client named. Dealer
            // scope is applied per row below so a foreign id is reported rather
            // than silently dropped.
            Map<Id, Dealer_Package__c> mirrors = new Map<Id, Dealer_Package__c>([
                SELECT Id, Name, Dealer__c, Active__c
                FROM Dealer_Package__c
                WHERE Id IN :orderedIds
            ]);

            List<Dealer_Package__c> toUpdate = new List<Dealer_Package__c>();
            Map<Id, ToggleRowResult> changedRowById = new Map<Id, ToggleRowResult>();
            Map<Id, Boolean> nextById = new Map<Id, Boolean>();

            for (Id dpId : orderedIds) {
                Boolean next = requested.get(dpId);
                Dealer_Package__c dp = mirrors.get(dpId);
                ToggleRowResult row = new ToggleRowResult();
                row.dealerPackageId = dpId;
                row.changed = false;

                if (dp == null) {
                    // No mirror exists for this package — reported, never created.
                    row.name = '';
                    row.success = false;
                    row.message = 'This package is not in the dealer\u2019s plan, so it was left alone.';
                    result.failedCount++;
                    result.results.add(row);
                    continue;
                }
                row.name = dp.Name;

                if (dp.Dealer__c != accountId) {
                    // Belongs to another dealer — never written from this console.
                    row.success = false;
                    row.message = 'This package belongs to another dealer and was not changed.';
                    result.failedCount++;
                    result.results.add(row);
                    continue;
                }
                if (dp.Active__c == next) {
                    // Already where the user wants it — no write, no DML.
                    row.success = true;
                    row.message = next ? 'Already active.' : 'Already inactive.';
                    result.unchangedCount++;
                    result.results.add(row);
                    continue;
                }

                row.success = true;   // provisional; the save result refines it
                row.changed = true;
                result.results.add(row);
                changedRowById.put(dpId, row);
                nextById.put(dpId, next);
                toUpdate.add(new Dealer_Package__c(Id = dpId, Active__c = next));
            }

            // Idempotent: nothing differs from the saved truth → NO DML at all.
            if (toUpdate.isEmpty()) {
                result.success = result.failedCount == 0;
                result.message = toggleSummary(result);
                return result;
            }

            // ONE transaction, ONE DML statement — allOrNone = false so a single
            // rejected row cannot roll back the rows that were fine.
            Database.SaveResult[] saved = Database.update(toUpdate, false);
            Integer ok = 0;
            for (Integer i = 0; i < saved.size(); i++) {
                Id dpId = toUpdate[i].Id;
                ToggleRowResult row = changedRowById.get(dpId);
                if (saved[i].isSuccess()) {
                    ok++;
                    row.success = true;
                    row.message = nextById.get(dpId) == true ? 'Now active.' : 'Now inactive.';
                } else {
                    row.success = false;
                    row.message = REJECTED_MESSAGE;
                    result.failedCount++;
                }
            }
            result.updatedCount = ok;
            result.success = result.failedCount == 0;
            result.message = toggleSummary(result);
            return result;
        } catch (Exception e) {
            result.success = false;
            result.message = GENERIC_ERROR_MESSAGE;
            return result;
        }
    }

    /**
     * Logs the incoming payload so the NEXT failure is diagnosable from the log
     * alone. Long payloads are summarised (length + first id) rather than dumped.
     */
    private static void debugToggles(String togglesJson) {
        if (togglesJson == null) {
            System.debug(LoggingLevel.INFO, 'dealerToggles raw=null');
            return;
        }
        String raw = togglesJson;
        if (raw.length() > MAX_RAW_LOG_CHARS) {
            Integer firstId = raw.indexOf('"dealerPackageId"');
            String firstIdBit = firstId < 0
                ? ''
                : raw.substring(firstId, Math.min(raw.length(), firstId + 60));
            raw = 'len=' + togglesJson.length() + ' first=' + firstIdBit;
        }
        System.debug(LoggingLevel.INFO, 'dealerToggles raw=' + raw);
    }

    /** Plain-word one-liner for a bulk Active / Inactive save. */
    private static String toggleSummary(PackageToggleResult r) {
        List<String> parts = new List<String>();
        if (r.updatedCount > 0) {
            parts.add(r.updatedCount == 1
                ? '1 package updated.'
                : r.updatedCount + ' packages updated.');
        }
        if (r.unchangedCount > 0) {
            parts.add(r.unchangedCount == 1
                ? '1 package already matched and was left alone.'
                : r.unchangedCount + ' packages already matched and were left alone.');
        }
        if (r.failedCount > 0) {
            parts.add(r.failedCount == 1
                ? '1 package could not be changed.'
                : r.failedCount + ' packages could not be changed.');
        }
        if (parts.isEmpty()) {
            return 'No changes to save \u2014 every package already matches the saved state.';
        }
        return String.join(parts, ' ');
    }

    /** The Account the console is open on must be a dealer account. */
    private static Account requireDealerAccount(Id accountId) {
        List<Account> accs = [
            SELECT Id, Name, RecordType.DeveloperName
            FROM Account
            WHERE Id = :accountId AND RecordType.DeveloperName = :DEALER_ACCOUNT_RT
            LIMIT 1
        ];
        return accs.isEmpty() ? null : accs[0];
    }
}