trigger PackageTrigger on Package__c (after update) {
    // When the Max Vehicle Age Limit changes, move the terms that were
    // following the package and refresh the dealer mirrors.
    PackageAgeLimitPropagationService.propagateOnPackageLimitChange(Trigger.new, Trigger.oldMap);
}