trigger DealerPackageFileCopyTrigger on Dealer_Package__c (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        // Copy files from Package to Dealer Package
        DealerPackageFileCopyHandler.handleAfterInsert(Trigger.new);
        
        // Share Dealer Package records with portal users for file access
        DealerPackagePortalSharing.shareDealerPackagesWithPortalUsers(Trigger.new);
    }
}