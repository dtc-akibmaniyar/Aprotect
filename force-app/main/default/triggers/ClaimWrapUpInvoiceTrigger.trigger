/**
 * Generates the customer invoice when a claim enters Invoice And Wrap Up
 * (Osama, Sep 21). Kept separate from ClaimTrigger (before insert, oil
 * change counts) since this is an after-update concern with no overlap.
 */
trigger ClaimWrapUpInvoiceTrigger on Claim__c (after update) {
    List<Id> claimIds = new List<Id>();
    for (Claim__c claim : Trigger.new) {
        Claim__c old = Trigger.oldMap.get(claim.Id);
        if (claim.Claim_Status__c == 'Invoice And Wrap Up' && old.Claim_Status__c != 'Invoice And Wrap Up') {
            claimIds.add(claim.Id);
        }
    }
    if (!claimIds.isEmpty()) {
        ClaimEstimateService.generateInvoicesForWrapUp(claimIds);
    }
}