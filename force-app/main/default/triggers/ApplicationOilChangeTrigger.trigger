trigger ApplicationOilChangeTrigger on Application_Oil_Change__c (before insert, after insert, after delete) {
    if (Trigger.isBefore && Trigger.isInsert) {
        ApplicationOilChangeHandler.calculateOdometerDifference(Trigger.new);
    }
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isDelete)) {
        List<Application_Oil_Change__c> oilChanges = Trigger.isInsert ? Trigger.new : Trigger.old;
        ApplicationOilChangeHandler.updateClaimOilChangeCounts(oilChanges);
    }
}