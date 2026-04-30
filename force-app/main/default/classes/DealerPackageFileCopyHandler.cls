public class DealerPackageFileCopyHandler {
    
    /**
     * Handles the after insert trigger logic for Dealer_Package__c
     * Copies files from Dealer Account (logos) and Package Package_File__c (brochures) 
     * to new Dealer_Package Package_File__c records
     * WITH PORTAL USER ACCESS
     */
    public static void handleAfterInsert(List<Dealer_Package__c> newDealerPackages) {
        System.debug('Starting DealerPackageFileCopyHandler.handleAfterInsert with ' + newDealerPackages.size() + ' records');
        
        try {
            // Collections for bulk operations
            Set<Id> dealerIds = new Set<Id>();
            Set<Id> packageIds = new Set<Id>();
            
            // Collect all Dealer and Package IDs
            for (Dealer_Package__c dp : newDealerPackages) {
                System.debug('Processing Dealer Package: ' + dp.Id + ', Dealer: ' + dp.Dealer__c + ', Package: ' + dp.Package__c);
                if (dp.Dealer__c != null) {
                    dealerIds.add(dp.Dealer__c);
                }
                if (dp.Package__c != null) {
                    packageIds.add(dp.Package__c);
                }
            }
            
            System.debug('Collected Dealer IDs: ' + dealerIds);
            System.debug('Collected Package IDs: ' + packageIds);
            
            // Get files from Dealer Accounts (logo files)
            Map<Id, List<ContentDocumentLink>> dealerFilesMap = getFilesForEntities(dealerIds);
            System.debug('Found dealer files for ' + dealerFilesMap.keySet().size() + ' dealers');
            
            // Get Package_File__c records and their attached files for Packages
            Map<Id, List<PackageFileWithFiles>> packageFilesMap = getPackageFilesWithAttachments(packageIds);
            System.debug('Found package files for ' + packageFilesMap.keySet().size() + ' packages');
            
            // Collections for bulk DML
            List<Package_File__c> packageFilesToInsert = new List<Package_File__c>();
            List<ContentDocumentLink> contentLinksToInsert = new List<ContentDocumentLink>();
            
            // Process each Dealer Package
            for (Dealer_Package__c dp : newDealerPackages) {
                
                // ========================================
                // PART 1: Copy Dealer Logo Files from Account
                // ========================================
                if (dp.Dealer__c != null && dealerFilesMap.containsKey(dp.Dealer__c)) {
                    List<ContentDocumentLink> dealerFiles = dealerFilesMap.get(dp.Dealer__c);
                    System.debug('Processing ' + dealerFiles.size() + ' dealer logo files for dealer ' + dp.Dealer__c);
                    
                    for (ContentDocumentLink cdl : dealerFiles) {
                        // Create Package_File__c record for dealer logo
                        Package_File__c pf = new Package_File__c(
                            Package__c = dp.Package__c,
                            Dealer_Package__c = dp.Id,
                            File_Type_del__c = 'Dealer Logo'  // ✅ Clearly marked as Dealer Logo
                        );
                        packageFilesToInsert.add(pf);
                        
                        // Prepare ContentDocumentLink with PORTAL USER ACCESS
                        ContentDocumentLink newCDL = new ContentDocumentLink(
                            ContentDocumentId = cdl.ContentDocumentId,
                            ShareType = 'V',  // View access (required for portal users)
                            Visibility = 'AllUsers'  // Make visible to portal users
                        );
                        contentLinksToInsert.add(newCDL);
                        
                        System.debug('✅ Queued Dealer Logo: ' + cdl.ContentDocumentId + ' for Dealer Package ' + dp.Id);
                    }
                }
                
                // ========================================
                // PART 2: Copy Package Brochure Files from Package_File__c
                // ========================================
                if (dp.Package__c != null && packageFilesMap.containsKey(dp.Package__c)) {
                    List<PackageFileWithFiles> packageFilesWithAttachments = packageFilesMap.get(dp.Package__c);
                    System.debug('Processing ' + packageFilesWithAttachments.size() + ' package files with attachments for package ' + dp.Package__c);
                    
                    for (PackageFileWithFiles pfwf : packageFilesWithAttachments) {
                        System.debug('Processing Package_File__c: ' + pfwf.originalPackageFile.Id + ' with ' + pfwf.attachedFiles.size() + ' attached files');
                        
                        // For each Package_File__c record, copy its files
                        for (ContentDocumentLink cdl : pfwf.attachedFiles) {
                            System.debug('Copying package brochure file: ' + cdl.ContentDocumentId);
                            
                            // Determine file type - keep original if available, otherwise default
                            String fileType = pfwf.originalPackageFile.File_Type_del__c != null ? 
                                pfwf.originalPackageFile.File_Type_del__c : 'Package Brochure';
                            
                            // Create new Package_File__c record for dealer package
                            Package_File__c pf = new Package_File__c(
                                Package__c = dp.Package__c,
                                Dealer_Package__c = dp.Id,
                                File_Type_del__c = fileType  // ✅ Preserve original file type or use Package Brochure
                            );
                            packageFilesToInsert.add(pf);
                            
                            // Prepare ContentDocumentLink with PORTAL USER ACCESS
                            ContentDocumentLink newCDL = new ContentDocumentLink(
                                ContentDocumentId = cdl.ContentDocumentId,
                                ShareType = 'V',  // View access (required for portal users)
                                Visibility = 'AllUsers'  // Make visible to portal users
                            );
                            contentLinksToInsert.add(newCDL);
                            
                            System.debug('✅ Queued Package File: ' + cdl.ContentDocumentId + ' (Type: ' + fileType + ') for Dealer Package ' + dp.Id);
                        }
                    }
                }
            }
            
            System.debug('Preparing to create ' + packageFilesToInsert.size() + ' Package_File__c records');
            System.debug('Preparing to create ' + contentLinksToInsert.size() + ' ContentDocumentLink records');
            
            // Bulk DML operations with error handling
            if (!packageFilesToInsert.isEmpty()) {
                Database.SaveResult[] results = Database.insert(packageFilesToInsert, false);
                
                // Handle any errors in Package_File__c creation
                List<String> errors = new List<String>();
                List<Id> successfulIds = new List<Id>();
                
                for (Integer i = 0; i < results.size(); i++) {
                    if (!results[i].isSuccess()) {
                        for (Database.Error err : results[i].getErrors()) {
                            errors.add('Error creating Package File ' + i + ': ' + err.getMessage());
                        }
                    } else {
                        successfulIds.add(results[i].getId());
                    }
                }
                
                if (!errors.isEmpty()) {
                    System.debug('Package File creation errors: ' + String.join(errors, '; '));
                }
                
                System.debug('Successfully created ' + successfulIds.size() + ' Package_File__c records');
                
                // Link files to successfully created Package_File__c records
                List<ContentDocumentLink> validLinks = new List<ContentDocumentLink>();
                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess() && i < contentLinksToInsert.size()) {
                        contentLinksToInsert[i].LinkedEntityId = results[i].getId();
                        validLinks.add(contentLinksToInsert[i]);
                    }
                }
                
                // Bulk insert ContentDocumentLinks
                if (!validLinks.isEmpty()) {
                    System.debug('Linking ' + validLinks.size() + ' files to Package_File__c records with PORTAL ACCESS');
                    Database.SaveResult[] linkResults = Database.insert(validLinks, false);
                    
                    // Handle ContentDocumentLink errors
                    List<String> linkErrors = new List<String>();
                    Integer successfulLinks = 0;
                    for (Integer i = 0; i < linkResults.size(); i++) {
                        if (!linkResults[i].isSuccess()) {
                            for (Database.Error err : linkResults[i].getErrors()) {
                                linkErrors.add('Error linking file ' + i + ': ' + err.getMessage());
                            }
                        } else {
                            successfulLinks++;
                        }
                    }
                    
                    if (!linkErrors.isEmpty()) {
                        System.debug('File linking errors: ' + String.join(linkErrors, '; '));
                    }
                    
                    System.debug('✅ FINAL SUCCESS: Copied ' + successfulLinks + ' files (with portal access) to ' + 
                        successfulIds.size() + ' Package File records');
                    
                    // Create public distributions for portal access
                    if (!successfulIds.isEmpty()) {
                        List<Package_File__c> newPackageFiles = [SELECT Id FROM Package_File__c WHERE Id IN :successfulIds];
                        ContentDistributionHelper.createPublicDistributionsForPackageFiles(newPackageFiles);
                    }
                }
            } else {
                System.debug('No files to copy - no Package_File__c records or files found');
            }
            
        } catch (Exception e) {
            System.debug('❌ ERROR in DealerPackageFileCopyHandler: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            // Log the error but don't fail the entire transaction
        }
        
        System.debug('Completed DealerPackageFileCopyHandler.handleAfterInsert');
    }
    
    /**
     * Helper method to get Package_File__c records and their attached files for packages
     */
    private static Map<Id, List<PackageFileWithFiles>> getPackageFilesWithAttachments(Set<Id> packageIds) {
        Map<Id, List<PackageFileWithFiles>> packageFilesMap = new Map<Id, List<PackageFileWithFiles>>();
        
        if (packageIds.isEmpty()) {
            System.debug('No package IDs provided to getPackageFilesWithAttachments');
            return packageFilesMap;
        }
        
        try {
            System.debug('Querying Package_File__c records for packages: ' + packageIds);
            
            // First, get all Package_File__c records for the packages
            List<Package_File__c> packageFiles = [
                SELECT Id, Package__c, File_Type_del__c, Name
                FROM Package_File__c 
                WHERE Package__c IN :packageIds
                AND Dealer_Package__c = null  // Only get Package files, not Dealer Package files
            ];
            
            System.debug('Found ' + packageFiles.size() + ' Package_File__c records');
            
            // Get file IDs for these Package_File__c records
            Set<Id> packageFileIds = new Set<Id>();
            for (Package_File__c pf : packageFiles) {
                packageFileIds.add(pf.Id);
                System.debug('Package_File__c: ' + pf.Id + ' (' + pf.Name + ') - Type: ' + pf.File_Type_del__c);
            }
            
            // Get ContentDocumentLinks for all Package_File__c records
            Map<Id, List<ContentDocumentLink>> packageFileToFilesMap = new Map<Id, List<ContentDocumentLink>>();
            if (!packageFileIds.isEmpty()) {
                System.debug('Querying ContentDocumentLinks for Package_File__c records: ' + packageFileIds);
                
                List<ContentDocumentLink> cdls = [
                    SELECT Id, ContentDocumentId, LinkedEntityId, ShareType
                    FROM ContentDocumentLink 
                    WHERE LinkedEntityId IN :packageFileIds
                    AND ContentDocument.IsDeleted = false
                ];
                
                System.debug('Found ' + cdls.size() + ' ContentDocumentLink records');
                
                // Group files by Package_File__c ID
                for (ContentDocumentLink cdl : cdls) {
                    if (!packageFileToFilesMap.containsKey(cdl.LinkedEntityId)) {
                        packageFileToFilesMap.put(cdl.LinkedEntityId, new List<ContentDocumentLink>());
                    }
                    packageFileToFilesMap.get(cdl.LinkedEntityId).add(cdl);
                    System.debug('File ' + cdl.ContentDocumentId + ' attached to Package_File__c ' + cdl.LinkedEntityId);
                }
            }
            
            // Build the final map: Package ID -> List of PackageFileWithFiles
            for (Package_File__c pf : packageFiles) {
                if (!packageFilesMap.containsKey(pf.Package__c)) {
                    packageFilesMap.put(pf.Package__c, new List<PackageFileWithFiles>());
                }
                
                List<ContentDocumentLink> attachedFiles = packageFileToFilesMap.get(pf.Id);
                if (attachedFiles == null) {
                    attachedFiles = new List<ContentDocumentLink>();
                }
                
                PackageFileWithFiles pfwf = new PackageFileWithFiles();
                pfwf.originalPackageFile = pf;
                pfwf.attachedFiles = attachedFiles;
                
                packageFilesMap.get(pf.Package__c).add(pfwf);
                System.debug('Mapped Package ' + pf.Package__c + ' -> Package_File__c ' + pf.Id + ' with ' + attachedFiles.size() + ' files');
            }
            
        } catch (Exception e) {
            System.debug('❌ Error querying Package Files with attachments: ' + e.getMessage());
        }
        
        return packageFilesMap;
    }
    
    /**
     * Helper method to get files for a set of entity IDs (for Dealer Accounts)
     */
    private static Map<Id, List<ContentDocumentLink>> getFilesForEntities(Set<Id> entityIds) {
        Map<Id, List<ContentDocumentLink>> filesMap = new Map<Id, List<ContentDocumentLink>>();
        
        if (entityIds.isEmpty()) {
            return filesMap;
        }
        
        try {
            System.debug('Querying ContentDocumentLinks for entities (Dealer Accounts): ' + entityIds);
            
            // Query all ContentDocumentLinks for the entities
            List<ContentDocumentLink> cdls = [
                SELECT Id, ContentDocumentId, LinkedEntityId, ShareType
                FROM ContentDocumentLink 
                WHERE LinkedEntityId IN :entityIds
                AND ContentDocument.IsDeleted = false
            ];
            
            System.debug('Found ' + cdls.size() + ' dealer logo files for entities');
            
            // Group files by entity ID
            for (ContentDocumentLink cdl : cdls) {
                if (!filesMap.containsKey(cdl.LinkedEntityId)) {
                    filesMap.put(cdl.LinkedEntityId, new List<ContentDocumentLink>());
                }
                filesMap.get(cdl.LinkedEntityId).add(cdl);
            }
            
        } catch (Exception e) {
            System.debug('❌ Error querying files for entities: ' + e.getMessage());
        }
        
        return filesMap;
    }
    
    /**
     * Inner class to hold Package_File__c record with its attached files
     */
    public class PackageFileWithFiles {
        public Package_File__c originalPackageFile;
        public List<ContentDocumentLink> attachedFiles;
    }
}