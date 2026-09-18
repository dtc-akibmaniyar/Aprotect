/**
 * DealerPackageBulkAssignBatch
 *
 * Batchable path for the §09.1 bulk "assign plan to all dealers" tool when the
 * candidate dealer count exceeds the inline threshold (plan §11 P2 / §09.1).
 * Each batch creates the missing Dealer_Package__c header rows for the given
 * master package; the DealerPackageTrigger after-insert reconcile builds the
 * mirror children idempotently. Existing mirrors are skipped so re-runs and
 * batch overlap are safe.
 */
public class DealerPackageBulkAssignBatch implements Database.Batchable<sObject> {

    private final Id masterPackageId;
    private final List<Id> dealerIds;

    public DealerPackageBulkAssignBatch(Id masterPackageId, List<Id> dealerIds) {
        this.masterPackageId = masterPackageId;
        this.dealerIds = dealerIds;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            'SELECT Id FROM Account WHERE Id IN :dealerIds'
        );
    }

    public void execute(Database.BatchableContext bc, List<sObject> scope) {
        List<Id> ids = new List<Id>();
        for (sObject s : scope) ids.add((Id) s.get('Id'));

        List<Package__c> masters = [
            SELECT Id, Name, RecordTypeId, RecordType.DeveloperName
            FROM Package__c
            WHERE Id = :masterPackageId
            LIMIT 1
        ];
        if (masters.isEmpty()) return;

        // Re-run safety inside the batch too: skip dealers that already have a mirror.
        Set<Id> haveMirror = new Set<Id>();
        for (Dealer_Package__c dp : [
            SELECT Dealer__c FROM Dealer_Package__c
            WHERE Package__c = :masterPackageId AND Dealer__c IN :ids
        ]) {
            haveMirror.add(dp.Dealer__c);
        }

        List<Id> toCreate = new List<Id>();
        for (Id d : ids) {
            if (!haveMirror.contains(d)) toCreate.add(d);
        }
        if (!toCreate.isEmpty()) {
            DealerPackageSyncService.createDealerMirrors(masters[0], toCreate);
        }
    }

    public void finish(Database.BatchableContext bc) {}
}