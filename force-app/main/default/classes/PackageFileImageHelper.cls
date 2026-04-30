public class PackageFileImageHelper {
    
    /**
     * DTO for Package File with image URLs
     */
    public class PackageFileDTO {
        @AuraEnabled public String Id;
        @AuraEnabled public String Name;
        @AuraEnabled public String fileType;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public String downloadUrl;
        @AuraEnabled public String distributionUrl;
        @AuraEnabled public String contentDocumentId;
        @AuraEnabled public String contentVersionId;
        @AuraEnabled public String fileTitle;
        @AuraEnabled public String fileExtension;
    }
    
    /**
     * Get package files with portal-accessible image URLs for a Dealer Package
     * Returns URLs that work in both internal Salesforce and Experience Cloud portals
     */
    @AuraEnabled(cacheable=true)
    public static List<PackageFileDTO> getPackageFilesWithImages(String dealerPackageId) {
        try {
            System.debug('🔍 getPackageFilesWithImages called for Dealer Package: ' + dealerPackageId);
            
            if (String.isBlank(dealerPackageId)) {
                return new List<PackageFileDTO>();
            }
            
            // Detect portal context
            String urlPrefix = getPortalPrefix();
            
            // Query Package_File__c records with their attached files
            List<Package_File__c> packageFiles = [
                SELECT Id, Name, File_Type_del__c,
                       (SELECT ContentDocumentId, ContentDocument.Title, 
                               ContentDocument.FileExtension, ContentDocument.LatestPublishedVersionId
                        FROM ContentDocumentLinks)
                FROM Package_File__c
                WHERE Dealer_Package__c = :dealerPackageId
                ORDER BY File_Type_del__c, CreatedDate
            ];
            
            System.debug('🔍 Found ' + packageFiles.size() + ' Package_File__c records');
            
            List<PackageFileDTO> results = new List<PackageFileDTO>();
            
            for (Package_File__c pf : packageFiles) {
                if (pf.ContentDocumentLinks != null && !pf.ContentDocumentLinks.isEmpty()) {
                    // Get the first file (typically there's only one per Package_File__c)
                    ContentDocumentLink cdl = pf.ContentDocumentLinks[0];
                    
                    PackageFileDTO dto = new PackageFileDTO();
                    dto.Id = pf.Id;
                    dto.Name = pf.Name;
                    dto.fileType = pf.File_Type_del__c;
                    dto.contentDocumentId = cdl.ContentDocumentId;
                    dto.contentVersionId = cdl.ContentDocument.LatestPublishedVersionId;
                    dto.fileTitle = cdl.ContentDocument.Title;
                    dto.fileExtension = cdl.ContentDocument.FileExtension;
                    
                    // Generate portal-accessible image URLs with prefix
                    dto.imageUrl = urlPrefix + '/sfc/servlet.shepherd/version/download/' + dto.contentVersionId;
                    dto.downloadUrl = urlPrefix + '/sfc/servlet.shepherd/document/download/' + dto.contentDocumentId;
                    
                    // Try to get public distribution URL (works everywhere without prefix)
                    List<ContentDistribution> distributions = [
                        SELECT Id, DistributionPublicUrl, ContentDownloadUrl
                        FROM ContentDistribution
                        WHERE ContentDocumentId = :cdl.ContentDocumentId
                        AND PreferencesExpires = false
                        LIMIT 1
                    ];
                    
                    if (!distributions.isEmpty()) {
                        dto.distributionUrl = distributions[0].DistributionPublicUrl;
                    }
                    
                    results.add(dto);
                    
                    System.debug('✅ Package File: ' + pf.Name + ' (' + pf.File_Type_del__c + ')');
                    System.debug('   Image URL: ' + dto.imageUrl);
                }
            }
            
            System.debug('✅ Returning ' + results.size() + ' package files with image URLs');
            return results;
            
        } catch (Exception e) {
            System.debug('❌ Error in getPackageFilesWithImages: ' + e.getMessage());
            return new List<PackageFileDTO>();
        }
    }
    
    /**
     * Get portal URL prefix (for Experience Cloud)
     */
    private static String getPortalPrefix() {
        String prefix = '';
        
        try {
            // Check Site.getBaseUrl() for Experience Cloud
            String siteUrl = Site.getBaseUrl();
            if(String.isNotBlank(siteUrl) && siteUrl.contains('/dealerportal')) {
                prefix = '/dealerportal';
            }
        } catch(Exception e) {
            // Not in portal context
        }
        
        // Try Network API as fallback
        if(String.isBlank(prefix)) {
            try {
                String networkId = Network.getNetworkId();
                if(String.isNotBlank(networkId)) {
                    List<Network> networks = [SELECT UrlPathPrefix FROM Network WHERE Id = :networkId LIMIT 1];
                    if(!networks.isEmpty() && String.isNotBlank(networks[0].UrlPathPrefix)) {
                        prefix = '/' + networks[0].UrlPathPrefix;
                    }
                }
            } catch(Exception e) {
                // Not in portal context
            }
        }
        
        return prefix;
    }
    
    /**
     * Get package files grouped by type (Dealer Logo, Header Logo, Brochures)
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getPackageFilesByType(String dealerPackageId) {
        try {
            System.debug('🔍 getPackageFilesByType called for Dealer Package: ' + dealerPackageId);
            
            List<PackageFileDTO> allFiles = getPackageFilesWithImages(dealerPackageId);
            
            // Group by file type
            Map<String, List<PackageFileDTO>> filesByType = new Map<String, List<PackageFileDTO>>();
            filesByType.put('Dealer Logo', new List<PackageFileDTO>());
            filesByType.put('Header Logo', new List<PackageFileDTO>());
            filesByType.put('Brochures', new List<PackageFileDTO>());
            filesByType.put('Other', new List<PackageFileDTO>());
            
            for (PackageFileDTO file : allFiles) {
                String fileType = file.fileType != null ? file.fileType : 'Other';
                
                if (filesByType.containsKey(fileType)) {
                    filesByType.get(fileType).add(file);
                } else {
                    filesByType.get('Other').add(file);
                }
            }
            
            // Return as map with additional metadata
            return new Map<String, Object>{
                'success' => true,
                'dealerLogos' => filesByType.get('Dealer Logo'),
                'headerLogos' => filesByType.get('Header Logo'),
                'brochures' => filesByType.get('Brochures'),
                'otherFiles' => filesByType.get('Other'),
                'totalFileCount' => allFiles.size()
            };
            
        } catch (Exception e) {
            System.debug('❌ Error in getPackageFilesByType: ' + e.getMessage());
            return new Map<String, Object>{
                'success' => false,
                'message' => 'Error loading package files: ' + e.getMessage()
            };
        }
    }
}