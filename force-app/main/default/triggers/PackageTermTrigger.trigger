trigger PackageTermTrigger on Package_Term__c (before insert, after insert) {
    if (Trigger.isBefore && Trigger.isInsert) {
        // Blank term takes its parent package's Max Vehicle Age Limit.
        PackageAgeLimitPropagationService.applyPackageLimitOnInsert(Trigger.new);
    } else if (Trigger.isAfter && Trigger.isInsert) {
        // Carry the newly-set limit onto dealer mirrors via the existing sync.
        PackageAgeLimitPropagationService.reconcileAfterTermInsert();
    }
}