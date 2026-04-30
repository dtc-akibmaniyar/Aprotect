trigger DealerPackageOptionTrigger on Dealer_Package_Option__c (after insert, after update, after delete, after undelete) {
    Set<Id> packageIds = new Set<Id>();

    if(Trigger.isInsert || Trigger.isUndelete) {
        for(Dealer_Package_Option__c opt : Trigger.new) {
            if(opt.Dealer_Package__c != null) {
                packageIds.add(opt.Dealer_Package__c);
            }
        }
    }
    if(Trigger.isUpdate) {
        for(Integer i = 0; i < Trigger.new.size(); i++) {
            Dealer_Package_Option__c newOpt = Trigger.new[i];
            Dealer_Package_Option__c oldOpt = Trigger.old[i];
            // Only process if Retail_Price__c has changed
            if(newOpt.Retail_Price__c != oldOpt.Retail_Price__c && newOpt.Dealer_Package__c != null) {
                packageIds.add(newOpt.Dealer_Package__c);
            }
        }
    }
    if(Trigger.isDelete) {
        for(Dealer_Package_Option__c opt : Trigger.old) {
            if(opt.Dealer_Package__c != null) {
                packageIds.add(opt.Dealer_Package__c);
            }
        }
    }

    if(!packageIds.isEmpty()) {
        DealerPackageOptionTriggerHandler.updateTermsForOptions(packageIds);
    }
}