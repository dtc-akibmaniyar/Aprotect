public class DealerPackagePortalSharing {
    
    /**
     * Shares Dealer_Package__c AND Package__c records with portal users
     * This ensures portal users can see Package_File__c records (which are ControlledByParent)
     * and their associated files
     */
    public static void shareDealerPackagesWithPortalUsers(List<Dealer_Package__c> newDealerPackages) {
        System.debug('Starting DealerPackagePortalSharing for ' + newDealerPackages.size() + ' records');
        
        try {
            // Collect Dealer (Account) IDs and Package IDs
            Set<Id> dealerAccountIds = new Set<Id>();
            Set<Id> packageIds = new Set<Id>();
            
            for (Dealer_Package__c dp : newDealerPackages) {
                if (dp.Dealer__c != null) {
                    dealerAccountIds.add(dp.Dealer__c);
                }
                if (dp.Package__c != null) {
                    packageIds.add(dp.Package__c);
                }
            }
            
            if (dealerAccountIds.isEmpty()) {
                System.debug('No dealer accounts found');
                return;
            }
            
            // Get portal users associated with these Dealer Accounts
            List<User> portalUsers = [
                SELECT Id, ContactId, Contact.AccountId 
                FROM User 
                WHERE IsActive = true 
                AND Contact.AccountId IN :dealerAccountIds
                AND (UserType = 'PowerPartner' OR UserType LIKE '%Portal%' OR UserType LIKE '%Community%')
            ];
            
            System.debug('Found ' + portalUsers.size() + ' portal users for these dealers');
            
            if (portalUsers.isEmpty()) {
                System.debug('No portal users found for these dealer accounts');
                return;
            }
            
            // Create a map of Account ID to Portal Users
            Map<Id, List<Id>> accountToUsersMap = new Map<Id, List<Id>>();
            for (User u : portalUsers) {
                if (u.Contact != null && u.Contact.AccountId != null) {
                    if (!accountToUsersMap.containsKey(u.Contact.AccountId)) {
                        accountToUsersMap.put(u.Contact.AccountId, new List<Id>());
                    }
                    accountToUsersMap.get(u.Contact.AccountId).add(u.Id);
                }
            }
            
            // Collections for bulk DML
            List<Dealer_Package__Share> dealerPackageSharesToInsert = new List<Dealer_Package__Share>();
            List<Package__Share> packageSharesToInsert = new List<Package__Share>();
            
            // Create Dealer_Package__Share records
            for (Dealer_Package__c dp : newDealerPackages) {
                if (dp.Dealer__c != null && accountToUsersMap.containsKey(dp.Dealer__c)) {
                    List<Id> userIds = accountToUsersMap.get(dp.Dealer__c);
                    
                    for (Id userId : userIds) {
                        // Share Dealer_Package__c
                        Dealer_Package__Share dpShare = new Dealer_Package__Share();
                        dpShare.ParentId = dp.Id;
                        dpShare.UserOrGroupId = userId;
                        dpShare.AccessLevel = 'Read';
                        dpShare.RowCause = Schema.Dealer_Package__Share.RowCause.Manual;
                        dealerPackageSharesToInsert.add(dpShare);
                        
                        // Share Package__c (CRITICAL for ControlledByParent access)
                        if (dp.Package__c != null) {
                            Package__Share pkgShare = new Package__Share();
                            pkgShare.ParentId = dp.Package__c;
                            pkgShare.UserOrGroupId = userId;
                            pkgShare.AccessLevel = 'Read';
                            pkgShare.RowCause = Schema.Package__Share.RowCause.Manual;
                            packageSharesToInsert.add(pkgShare);
                        }
                    }
                }
            }
            
            // Insert Dealer_Package__Share records
            if (!dealerPackageSharesToInsert.isEmpty()) {
                System.debug('Creating ' + dealerPackageSharesToInsert.size() + ' Dealer_Package__Share records');
                
                Database.SaveResult[] results = Database.insert(dealerPackageSharesToInsert, false);
                
                Integer successCount = 0;
                for (Database.SaveResult result : results) {
                    if (result.isSuccess()) {
                        successCount++;
                    } else {
                        for (Database.Error err : result.getErrors()) {
                            System.debug('Dealer_Package__Share error: ' + err.getMessage());
                        }
                    }
                }
                
                System.debug('✅ Created ' + successCount + ' Dealer_Package__Share records');
            }
            
            // Insert Package__Share records (CRITICAL FIX)
            if (!packageSharesToInsert.isEmpty()) {
                System.debug('Creating ' + packageSharesToInsert.size() + ' Package__Share records');
                
                Database.SaveResult[] results = Database.insert(packageSharesToInsert, false);
                
                Integer successCount = 0;
                for (Database.SaveResult result : results) {
                    if (result.isSuccess()) {
                        successCount++;
                    } else {
                        for (Database.Error err : result.getErrors()) {
                            System.debug('Package__Share error: ' + err.getMessage());
                        }
                    }
                }
                
                System.debug('✅ Created ' + successCount + ' Package__Share records for portal access');
            }
            
        } catch (Exception e) {
            System.debug('❌ ERROR in DealerPackagePortalSharing: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
        }
        
        System.debug('Completed DealerPackagePortalSharing');
    }
}