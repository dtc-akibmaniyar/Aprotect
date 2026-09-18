trigger DealerPackageTrigger on Dealer_Package__c (after insert, after update) {
    if (Trigger.isInsert) {
        DealerPackageTriggerHandler.onAfterInsert(Trigger.new);
    } else if (Trigger.isUpdate) {
        DealerPackageTriggerHandler.onAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}