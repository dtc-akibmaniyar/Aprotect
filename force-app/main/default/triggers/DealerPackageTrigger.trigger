trigger DealerPackageTrigger on Dealer_Package__c (after insert) {
    Set<Id> packageIds = new Set<Id>();

    for(Dealer_Package__c dp : Trigger.new) {
        if(dp.Package__c != null) {
            packageIds.add(dp.Package__c);
        }
    }

    if(!packageIds.isEmpty()) {
        DealerPackageTriggerHandler.populateFieldsFromPackage(Trigger.new, packageIds);
    }
}