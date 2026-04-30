public class ContentDistributionHelper {
    
    /**
     * Creates ContentDistribution records for files to make them accessible via public URLs
     * This is especially important for portal/community users
     */
    public static void createPublicDistributionsForPackageFiles(List<Package_File__c> packageFiles) {
        System.debug('Creating public distributions for ' + packageFiles.size() + ' Package Files');
        
        try {
            // Get all ContentDocumentLinks for these Package Files
            Set<Id> packageFileIds = new Set<Id>();
            for (Package_File__c pf : packageFiles) {
                packageFileIds.add(pf.Id);
            }
            
            List<ContentDocumentLink> cdls = [
                SELECT Id, ContentDocumentId, LinkedEntityId
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :packageFileIds
                AND ContentDocument.IsDeleted = false
            ];
            
            System.debug('Found ' + cdls.size() + ' ContentDocumentLinks');
            
            if (cdls.isEmpty()) {
                return;
            }
            
            // Get existing ContentDistributions to avoid duplicates
            Set<Id> contentDocIds = new Set<Id>();
            for (ContentDocumentLink cdl : cdls) {
                contentDocIds.add(cdl.ContentDocumentId);
            }
            
            List<ContentDistribution> existingDists = [
                SELECT Id, ContentDocumentId
                FROM ContentDistribution
                WHERE ContentDocumentId IN :contentDocIds
            ];
            
            Set<Id> alreadyDistributed = new Set<Id>();
            for (ContentDistribution cd : existingDists) {
                alreadyDistributed.add(cd.ContentDocumentId);
            }
            
            System.debug('Found ' + existingDists.size() + ' existing distributions');
            
            // Create ContentDistribution records for files that don't have them
            List<ContentDistribution> distributionsToCreate = new List<ContentDistribution>();
            
            for (ContentDocumentLink cdl : cdls) {
                if (!alreadyDistributed.contains(cdl.ContentDocumentId)) {
                    ContentDistribution dist = new ContentDistribution();
                    dist.Name = 'Package File Distribution';
                    dist.ContentVersionId = getLatestVersionId(cdl.ContentDocumentId);
                    dist.PreferencesAllowViewInBrowser = true;
                    dist.PreferencesAllowOriginalDownload = true;
                    dist.PreferencesExpires = false;
                    
                    distributionsToCreate.add(dist);
                    alreadyDistributed.add(cdl.ContentDocumentId);
                }
            }
            
            // Insert distributions
            if (!distributionsToCreate.isEmpty()) {
                System.debug('Creating ' + distributionsToCreate.size() + ' new distributions');
                
                Database.SaveResult[] results = Database.insert(distributionsToCreate, false);
                
                Integer successCount = 0;
                for (Database.SaveResult result : results) {
                    if (result.isSuccess()) {
                        successCount++;
                    } else {
                        for (Database.Error err : result.getErrors()) {
                            System.debug('ContentDistribution error: ' + err.getMessage());
                        }
                    }
                }
                
                System.debug('✅ Created ' + successCount + ' public distributions');
            }
            
        } catch (Exception e) {
            System.debug('❌ ERROR in ContentDistributionHelper: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
        }
    }
    
    /**
     * Helper to get the latest ContentVersion ID for a ContentDocument
     */
    private static Id getLatestVersionId(Id contentDocumentId) {
        List<ContentVersion> versions = [
            SELECT Id
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            AND IsLatest = true
            LIMIT 1
        ];
        
        return !versions.isEmpty() ? versions[0].Id : null;
    }
    
    /**
     * Get public distribution URL for a ContentDocument
     */
    @AuraEnabled(cacheable=true)
    public static String getPublicUrl(Id contentDocumentId) {
        try {
            List<ContentDistribution> dists = [
                SELECT Id, DistributionPublicUrl, ContentDownloadUrl
                FROM ContentDistribution
                WHERE ContentDocumentId = :contentDocumentId
                AND PreferencesExpires = false
                LIMIT 1
            ];
            
            if (!dists.isEmpty()) {
                return dists[0].DistributionPublicUrl;
            }
            
            return null;
            
        } catch (Exception e) {
            System.debug('Error getting public URL: ' + e.getMessage());
            return null;
        }
    }
}