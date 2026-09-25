/**
 * DealerPackagePremiumRepushBatch
 *
 * Batchable path for the head-office premium re-push when the matching dealer
 * term count exceeds the inline threshold (mirrors
 * DealerPackageBulkAssignBatch). Each batch pushes the master
 * Package_Term__c.Premium_Model_Fee__c onto the corresponding
 * Dealer_Package_Term__c rows of one master package.
 *
 * The premium fee on a dealer term is WRITE-ONCE (seeded once by the reconcile
 * when the dealer term is created) — this batch is the explicit, on-demand
 * channel a head office uses to carry a later master change onto the dealers.
 *
 * Idempotent: a re-run only writes rows whose value still differs from the
 * master, so batch overlap and re-runs are safe. Admin tooling — no
 * dealer-portal path enqueues this.
 */
public class DealerPackagePremiumRepushBatch implements Database.Batchable<sObject> {

    private final Id masterPackageId;

    public DealerPackagePremiumRepushBatch(Id masterPackageId) {
        this.masterPackageId = masterPackageId;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Every master term of the package: tier-less terms linked directly via
        // Package__c, plus tiered terms reached through the package's tiers.
        return Database.getQueryLocator(
            'SELECT Id, Premium_Model_Fee__c FROM Package_Term__c'
            + ' WHERE Package__c = :masterPackageId'
            + ' OR Package_Tier__r.Package__c = :masterPackageId'
        );
    }

    public void execute(Database.BatchableContext bc, List<sObject> scope) {
        Map<Id, Decimal> masterFeeByTermId = new Map<Id, Decimal>();
        for (sObject s : scope) {
            masterFeeByTermId.put((Id) s.get('Id'), (Decimal) s.get('Premium_Model_Fee__c'));
        }
        if (masterFeeByTermId.isEmpty()) return;

        List<Dealer_Package_Term__c> updates = new List<Dealer_Package_Term__c>();
        for (Dealer_Package_Term__c dt : [
            SELECT Id, Premium_Model_Fee__c, Package_Term__c
            FROM Dealer_Package_Term__c
            WHERE Package_Term__c IN :masterFeeByTermId.keySet()
        ]) {
            Decimal masterFee = masterFeeByTermId.get(dt.Package_Term__c);
            if (dt.Premium_Model_Fee__c != masterFee) {
                updates.add(new Dealer_Package_Term__c(
                    Id = dt.Id,
                    Premium_Model_Fee__c = masterFee
                ));
            }
        }
        if (!updates.isEmpty()) {
            Database.update(updates, false);
        }
    }

    public void finish(Database.BatchableContext bc) {}
}