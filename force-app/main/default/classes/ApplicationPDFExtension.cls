// public without sharing class ApplicationPDFExtension {
//     private final Application__c application;
//     public String dealerLogoUrl {get; set;}
//     public Boolean hasDealerLogo {get; set;}
//     public List<Application_Package__c> applicationPackages { get; private set; }
//     private Map<Id, List<Application_Package_Option__c>> packageOptions;
//     private Map<Id, String> packageLogoUrls;
//     private Map<Id, Boolean> packageHasLogo;
    
//     public class PackageWrapper {
//         public Application_Package__c pkg { get; set; }
//         public List<Application_Package_Option__c> includedOptions { get; set; }
//         public List<Application_Package_Option__c> optionalOptions { get; set; }
//         public List<String> inclusionsList { get; set; }
//         public List<String> exclusionsList { get; set; }
//         public String packageLogoUrl { get; set; }
//         public Boolean hasPackageLogo { get; set; }
//         public String contractStartDate {get; set; }
//         public String contractEndDate {get; set; }
//     }
    
//     public class RecordTypeWrapper {
//         public String recordTypeName { get; set; }
//         public List<PackageWrapper> packages { get; set; }
        
//         public RecordTypeWrapper(String name) {
//             this.recordTypeName = name;
//             this.packages = new List<PackageWrapper>();
//         }
//     }
    
//     public Map<String, RecordTypeWrapper> recordTypeWrappers { get; private set; }
//     public List<RecordTypeWrapper> recordTypeWrappersList { get; private set; }
    
//     public ApplicationPDFExtension(ApexPages.StandardController stdController) {
//         this.application = (Application__c)stdController.getRecord();
        
//         getDealerLogoUrl();
        
//         packageOptions = new Map<Id, List<Application_Package_Option__c>>();
//         packageLogoUrls = new Map<Id, String>();
//         packageHasLogo = new Map<Id, Boolean>();
//         recordTypeWrappers = new Map<String, RecordTypeWrapper>();
//         recordTypeWrappersList = new List<RecordTypeWrapper>();
        
//         getLatestPackagesFromEachRecordType();
//         getPackageLogos();
        
//         for(Application_Package__c pkg : applicationPackages) {
//             packageOptions.put(pkg.Id, pkg.Application_Package_Options__r);
//         }
        
//         for(Application_Package__c pkg : applicationPackages) {
//             PackageWrapper wrapper = new PackageWrapper();
//             wrapper.pkg = pkg;
//             wrapper.includedOptions = getIncludedOptionsImpl(pkg.Id);
//             wrapper.optionalOptions = getOptionalOptionsImpl(pkg.Id);
            
//             wrapper.packageLogoUrl = packageLogoUrls.get(pkg.Id);
//             wrapper.hasPackageLogo = packageHasLogo.get(pkg.Id) != null ? packageHasLogo.get(pkg.Id) : false;
            
//             DateTime csDate = pkg.Contract_Start_Date__c;
//             DateTime ceDate = pkg.Contract_End_Date__c; 

//             if (pkg.Contract_Start_Date__c != null) {
//                 wrapper.contractStartDate = csDate.format('yyyy-mm-dd');
//             }
//             if (pkg.Contract_End_Date__c != null) {
//                 wrapper.contractEndDate = ceDate.format('yyyy-mm-dd');
//             }
            
//             String inclusionsStr = getPackageInclusionsImpl(pkg.Id);
//             String exclusionsStr = getPackageExclusionsImpl(pkg.Id);
            
//             wrapper.inclusionsList = new List<String>();
//             if(String.isNotBlank(inclusionsStr)) {
//                 wrapper.inclusionsList = inclusionsStr.split('\\n');
//             }
            
//             wrapper.exclusionsList = new List<String>();
//             if(String.isNotBlank(exclusionsStr)) {
//                 wrapper.exclusionsList = exclusionsStr.split('\\n');
//             }
            
//             String recordType = pkg.Package_Record_Type__c;
//             if(String.isBlank(recordType)) {
//                 recordType = 'Other';
//             }
            
//             if(!recordTypeWrappers.containsKey(recordType)) {
//                 RecordTypeWrapper rtWrapper = new RecordTypeWrapper(recordType);
//                 recordTypeWrappers.put(recordType, rtWrapper);
//                 recordTypeWrappersList.add(rtWrapper);
//             }
            
//             recordTypeWrappers.get(recordType).packages.add(wrapper);
//         }
//     }
    
//     private void getLatestPackagesFromEachRecordType() {
//         try {
//             List<Application_Package__c> allPackages = [
//                 SELECT Id, Name, Application_Status__c,
//                 Package_Plan_Type__r.Name,
//                 Package__r.Name,
//                 Package__r.Id,
//                 Package_Tier__r.Name,
//                 Package_Term__r.Name,
//                 Coverage_Plan__c,
//                 Package_Record_Type__c,
//                 Disclaimer_Heading__c,
//                 Disclaimer_Body__c,
//                 Payment_Status__c,
//                 Deductible__c,
//                 Contract_Start_Date__c,
//                 Contract_End_Date__c,
//                 Odometer_Start__c,
//                 Odometer_End__c,
//                 Contract_Premium_Price__c,
//                 Tax_Amount__c,
//                 Total_Package_Price__c,
//                 Dealer_Package__c,
//                 Dealer_Package__r.Package__c,
//                 CreatedDate,
//                 (SELECT Id, Name, Option__c, Selection_Type__c, 
//                  Inclusion__c, Exclusion__c
//                  FROM Application_Package_Options__r
//                  ORDER BY Selection_Type__c)
//                 FROM Application_Package__c
//                 WHERE Application__c = :application.Id
//                 ORDER BY Package_Record_Type__c, CreatedDate DESC
//             ];
            
//             applicationPackages = new List<Application_Package__c>();
//             Set<String> processedRecordTypes = new Set<String>();
            
//             for(Application_Package__c pkg : allPackages) {
//                 String recordType = pkg.Package_Record_Type__c;
//                 if(String.isBlank(recordType)) {
//                     recordType = 'Other';
//                 }
                
//                 if(!processedRecordTypes.contains(recordType)) {
//                     applicationPackages.add(pkg);
//                     processedRecordTypes.add(recordType);
//                 }
//             }
            
//         } catch (Exception e) {
//             applicationPackages = new List<Application_Package__c>();
//         }
//     }
    
//     // ✅ EXACT SAME APPROACH AS DEALER LOGO - NO PREFIX
//     private void getPackageLogos() {
//         try {
//             for(Application_Package__c appPkg : applicationPackages) {
                
//                 if(appPkg.Dealer_Package__c == null) {
//                     continue;
//                 }
                
//                 List<Package_File__c> packageLogoFiles = [
//                     SELECT Id, 
//                            (SELECT ContentDocumentId, ContentDocument.Title,
//                                    ContentDocument.LatestPublishedVersionId
//                             FROM ContentDocumentLinks
//                             WHERE ContentDocument.FileExtension IN ('jpg', 'jpeg', 'png', 'gif', 'bmp')
//                             LIMIT 1)
//                     FROM Package_File__c
//                     WHERE Dealer_Package__c = :appPkg.Dealer_Package__c
//                     AND File_Type_del__c = 'Header Logo'
//                     LIMIT 1
//                 ];
                
//                 if(!packageLogoFiles.isEmpty() && 
//                    packageLogoFiles[0].ContentDocumentLinks != null && 
//                    !packageLogoFiles[0].ContentDocumentLinks.isEmpty()) {
                    
//                     ContentDocumentLink logoLink = packageLogoFiles[0].ContentDocumentLinks[0];
                    
//                     // ✅ EXACT SAME URL FORMAT AS DEALER LOGO (no prefix)
//                     String logoUrl = '/sfc/servlet.shepherd/version/download/' + 
//                                    logoLink.ContentDocument.LatestPublishedVersionId;
                    
//                     packageLogoUrls.put(appPkg.Id, logoUrl);
//                     packageHasLogo.put(appPkg.Id, true);
//                 }
//             }
            
//         } catch (Exception e) {
//             System.debug('Error in getPackageLogos: ' + e.getMessage());
//         }
//     }
    
//     // ✅ DEALER LOGO - ORIGINAL WORKING VERSION (no prefix)
//     private void getDealerLogoUrl() {
//         hasDealerLogo = false;
//         dealerLogoUrl = '';
        
//         try {
//             Application__c app = [
//                 SELECT Id, Dealer_Name__c, Dealer_Name__r.Name 
//                 FROM Application__c 
//                 WHERE Id = :application.Id 
//                 LIMIT 1
//             ];
            
//             if (app.Dealer_Name__c == null) {
//                 return;
//             }
            
//             List<Application_Package__c> appPackages = [
//                 SELECT Dealer_Package__c
//                 FROM Application_Package__c
//                 WHERE Application__c = :application.Id
//                 AND Dealer_Package__c != null
//                 LIMIT 1
//             ];
            
//             if(!appPackages.isEmpty() && appPackages[0].Dealer_Package__c != null) {
                
//                 List<Package_File__c> dealerLogoFiles = [
//                     SELECT Id, 
//                            (SELECT ContentDocumentId, ContentDocument.Title,
//                                    ContentDocument.LatestPublishedVersionId
//                             FROM ContentDocumentLinks
//                             WHERE ContentDocument.FileExtension IN ('jpg', 'jpeg', 'png', 'gif', 'bmp')
//                             LIMIT 1)
//                     FROM Package_File__c
//                     WHERE Dealer_Package__c = :appPackages[0].Dealer_Package__c
//                     AND File_Type_del__c = 'Dealer Logo'
//                     LIMIT 1
//                 ];
                
//                 if(!dealerLogoFiles.isEmpty() && 
//                    dealerLogoFiles[0].ContentDocumentLinks != null && 
//                    !dealerLogoFiles[0].ContentDocumentLinks.isEmpty()) {
                    
//                     ContentDocumentLink logoLink = dealerLogoFiles[0].ContentDocumentLinks[0];
                    
//                     // ✅ SAME URL FORMAT (no prefix)
//                     dealerLogoUrl = '/sfc/servlet.shepherd/version/download/' + 
//                                   logoLink.ContentDocument.LatestPublishedVersionId;
//                     hasDealerLogo = true;
//                     return;
//                 }
//             }
            
//             // Fallback to Dealer Account files
//             List<ContentDocumentLink> dealerFiles = [
//                 SELECT ContentDocumentId, ContentDocument.Title, ContentDocument.FileExtension,
//                 ContentDocument.LatestPublishedVersionId
//                 FROM ContentDocumentLink 
//                 WHERE LinkedEntityId = :app.Dealer_Name__c
//                 AND ContentDocument.FileExtension IN ('jpg', 'jpeg', 'png', 'gif', 'bmp')
//                 ORDER BY ContentDocument.CreatedDate DESC
//             ];
            
//             if (dealerFiles.isEmpty()) {
//                 return;
//             }
            
//             ContentDocumentLink logoFile = null;
            
//             for (ContentDocumentLink file : dealerFiles) {
//                 if (file.ContentDocument.Title.toLowerCase().contains('logo')) {
//                     logoFile = file;
//                     break;
//                 }
//             }
            
//             if (logoFile == null && !dealerFiles.isEmpty()) {
//                 logoFile = dealerFiles[0];
//             }
            
//             if (logoFile != null) {
//                 dealerLogoUrl = '/sfc/servlet.shepherd/version/download/' + 
//                               logoFile.ContentDocument.LatestPublishedVersionId;
//                 hasDealerLogo = true;
//             }
            
//         } catch (Exception e) {
//             hasDealerLogo = false;
//         }
//     }
    
//     @AuraEnabled(cacheable=false)
//     public static String generatePDFName(Id applicationId) {
//         Application__c app = [SELECT Name FROM Application__c WHERE Id = :applicationId];
//         return 'Application_' + app.Name + '.pdf';
//     }
    
//     public List<Application_Package_Option__c> getIncludedOptions(Id packageId) {
//         return getIncludedOptionsImpl(packageId);
//     }
    
//     public List<Application_Package_Option__c> getOptionalOptions(Id packageId) {
//         return getOptionalOptionsImpl(packageId);
//     }
    
//     public String getPackageInclusions(Id packageId) {
//         return getPackageInclusionsImpl(packageId);
//     }
    
//     public String getPackageExclusions(Id packageId) {
//         return getPackageExclusionsImpl(packageId);
//     }
    
//     private List<Application_Package_Option__c> getIncludedOptionsImpl(Id packageId) {
//         List<Application_Package_Option__c> result = new List<Application_Package_Option__c>();
//         List<Application_Package_Option__c> allOptions = packageOptions.get(packageId);
//         if (allOptions != null) {
//             for (Application_Package_Option__c opt : allOptions) {
//                 if (opt.Selection_Type__c == 'Included') {
//                     result.add(opt);
//                 }
//             }
//         }
//         return result;
//     }
    
//     private List<Application_Package_Option__c> getOptionalOptionsImpl(Id packageId) {
//         List<Application_Package_Option__c> result = new List<Application_Package_Option__c>();
//         List<Application_Package_Option__c> allOptions = packageOptions.get(packageId);
//         if (allOptions != null) {
//             for (Application_Package_Option__c opt : allOptions) {
//                 if (opt.Selection_Type__c == 'Optional') {
//                     result.add(opt);
//                 }
//             }
//         }
//         return result;
//     }
    
//     private String getPackageInclusionsImpl(Id packageId) {
//         String result = '';
//         List<Application_Package_Option__c> allOptions = packageOptions.get(packageId);
//         if (allOptions != null) {
//             List<String> inclusions = new List<String>();
//             for (Application_Package_Option__c opt : allOptions) {
//                 if (opt.Selection_Type__c == 'Included' && String.isNotBlank(opt.Inclusion__c)) {
//                     inclusions.add(opt.Inclusion__c);
//                 }
//             }
//             result = String.join(inclusions, '\n');
//         }
//         return result;
//     }
    
//     private String getPackageExclusionsImpl(Id packageId) {
//         String result = '';
//         List<Application_Package_Option__c> allOptions = packageOptions.get(packageId);
//         if (allOptions != null) {
//             List<String> exclusions = new List<String>();
//             for (Application_Package_Option__c opt : allOptions) {
//                 if (opt.Selection_Type__c == 'Included' && String.isNotBlank(opt.Exclusion__c)) {
//                     exclusions.add(opt.Exclusion__c);
//                 }
//             }
//             result = String.join(exclusions, '\n');
//         }
//         return result;
//     }
// }

// ApplicationPDFExtension.cls
public without sharing class ApplicationPDFExtension {
    private final Application__c application;

    public String  dealerLogoUrl   { get; set; }
    public Boolean hasDealerLogo   { get; set; }

    public List<Application_Package__c> applicationPackages { get; private set; }
    private Map<Id, List<Application_Package_Option__c>>     packageOptions;
    private Map<Id, String>  packageLogoUrls;  // key = Application_Package__c.Id
    private Map<Id, Boolean> packageHasLogo;

    public class PackageWrapper {
        public Application_Package__c              pkg              { get; set; }
        public List<Application_Package_Option__c> includedOptions  { get; set; }
        public List<Application_Package_Option__c> optionalOptions  { get; set; }
        public List<String>                        inclusionsList   { get; set; }
        public List<String>                        exclusionsList   { get; set; }
        public String                              packageLogoUrl   { get; set; }
        public Boolean                             hasPackageLogo   { get; set; }
        public String                              contractStartDate{ get; set; }
        public String                              contractEndDate  { get; set; }
    }

    public class RecordTypeWrapper {
        public String               recordTypeName { get; set; }
        public List<PackageWrapper> packages       { get; set; }
        public RecordTypeWrapper(String name) {
            this.recordTypeName = name;
            this.packages       = new List<PackageWrapper>();
        }
    }

    public Map<String, RecordTypeWrapper> recordTypeWrappers     { get; private set; }
    public List<RecordTypeWrapper>        recordTypeWrappersList { get; private set; }

    public ApplicationPDFExtension(ApexPages.StandardController stdController) {
        this.application = (Application__c) stdController.getRecord();

        getDealerLogoUrl(); // sets dealerLogoUrl / hasDealerLogo

        packageOptions         = new Map<Id, List<Application_Package_Option__c>>();
        packageLogoUrls        = new Map<Id, String>();
        packageHasLogo         = new Map<Id, Boolean>();
        recordTypeWrappers     = new Map<String, RecordTypeWrapper>();
        recordTypeWrappersList = new List<RecordTypeWrapper>();

        getLatestPackagesFromEachRecordType();
        getPackageLogos();

        for (Application_Package__c pkg : applicationPackages) {
            packageOptions.put(pkg.Id, pkg.Application_Package_Options__r);
        }

        for (Application_Package__c pkg : applicationPackages) {
            PackageWrapper wrapper  = new PackageWrapper();
            wrapper.pkg             = pkg;
            wrapper.includedOptions = getIncludedOptionsImpl(pkg.Id);
            wrapper.optionalOptions = getOptionalOptionsImpl(pkg.Id);
            wrapper.packageLogoUrl  = packageLogoUrls.get(pkg.Id);
            wrapper.hasPackageLogo  = packageHasLogo.containsKey(pkg.Id) ? packageHasLogo.get(pkg.Id) : false;

            if (pkg.Contract_Start_Date__c != null) {
                wrapper.contractStartDate = ((DateTime) pkg.Contract_Start_Date__c).format('yyyy-MM-dd');
            }
            if (pkg.Contract_End_Date__c != null) {
                wrapper.contractEndDate   = ((DateTime) pkg.Contract_End_Date__c).format('yyyy-MM-dd');
            }

            String inclusionsStr = getPackageInclusionsImpl(pkg.Id);
            String exclusionsStr = getPackageExclusionsImpl(pkg.Id);

            wrapper.inclusionsList = String.isBlank(inclusionsStr) ? new List<String>() : inclusionsStr.split('\\n');
            wrapper.exclusionsList = String.isBlank(exclusionsStr) ? new List<String>() : exclusionsStr.split('\\n');

            String rt = String.isBlank(pkg.Package_Record_Type__c) ? 'Other' : pkg.Package_Record_Type__c;
            if (!recordTypeWrappers.containsKey(rt)) {
                RecordTypeWrapper rtw = new RecordTypeWrapper(rt);
                recordTypeWrappers.put(rt, rtw);
                recordTypeWrappersList.add(rtw);
            }
            recordTypeWrappers.get(rt).packages.add(wrapper);
        }

        // If the VF page is invoked with an "rt" parameter, emit only that record type.
        PageReference currentPage = ApexPages.currentPage();
        if (currentPage != null) {
            String rtFilter = currentPage.getParameters().get('rt');
            if (!String.isBlank(rtFilter)) {
                if (recordTypeWrappers.containsKey(rtFilter)) {
                    recordTypeWrappersList = new List<RecordTypeWrapper>{ recordTypeWrappers.get(rtFilter) };
                } else {
                    recordTypeWrappersList = new List<RecordTypeWrapper>();
                }
            }
        }
    }

    // Pull latest package per record type
    private void getLatestPackagesFromEachRecordType() {
        try {
            List<Application_Package__c> all = [
                SELECT Id, Name, Application_Status__c,
                       Package_Plan_Type__r.Name,
                       Package__r.Name,
                       Package__r.Id,
                       Package_Tier__r.Name,
                       Package_Term__r.Name,
                       Coverage_Plan__c,
                       Package_Record_Type__c,
                       Disclaimer_Heading__c,
                       Disclaimer_Body__c,
                       Payment_Status__c,
                       Deductible__c,
                       Contract_Start_Date__c,
                       Contract_End_Date__c,
                       Odometer_Start__c,
                       Odometer_End__c,
                       Contract_Premium_Price__c,
                       Tax_Percentage__c,
                       Contract_Premium_Price_Without_Tax__c,
                       Tax_Amount__c,
                       Total_Package_Price__c,
                       Dealer_Package__c,
                       Dealer_Package__r.Package__c,
                       CreatedDate,
                       (SELECT Id, Name, Option__c, Selection_Type__c, Inclusion__c, Exclusion__c
                        FROM Application_Package_Options__r
                        ORDER BY Selection_Type__c)
                FROM Application_Package__c
                WHERE Application__c = :application.Id
                ORDER BY Package_Record_Type__c, CreatedDate DESC
            ];

            applicationPackages = new List<Application_Package__c>();
            Set<String> seen = new Set<String>();
            for (Application_Package__c p : all) {
                String rt = String.isBlank(p.Package_Record_Type__c) ? 'Other' : p.Package_Record_Type__c;
                if (!seen.contains(rt)) {
                    applicationPackages.add(p);
                    seen.add(rt);
                }
            }
        } catch (Exception e) {
            applicationPackages = new List<Application_Package__c>();
        }
    }

    // Build a URL that works both internally and in Experience Cloud PDFs
    private String buildFileUrl(String versionId) {
        String prefix = Site.getPathPrefix(); // e.g., "/sfsites/c" in community, "" internally
        if (!String.isBlank(prefix) && prefix.startsWith('/sfsites')) {
            return prefix + '/sfc/servlet.shepherd/version/download/' + versionId;
        }
        return '/sfc/servlet.shepherd/version/download/' + versionId;
    }

    // Prefer a public distribution URL if one exists (created by your helper in the copy handler)
    private String tryGetDistributionUrl(Id packageFileId) {
        List<ContentDistribution> dists = [
            SELECT DistributionPublicUrl, ExpiryDate, PreferencesAllowViewInBrowser
            FROM ContentDistribution
            WHERE RelatedRecordId = :packageFileId
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        return dists.isEmpty() ? null : dists[0].DistributionPublicUrl;
    }

    // ====== PACKAGE HEADER LOGOS (community-safe) ======
    private void getPackageLogos() {
        try {
            for (Application_Package__c appPkg : applicationPackages) {
                if (appPkg.Dealer_Package__c == null) continue;

                // 1) Try to find the Package_File__c for Header Logo
                List<Package_File__c> packageLogoFiles = [
                    SELECT Id,
                           (SELECT ContentDocumentId,
                                   ContentDocument.Title,
                                   ContentDocument.LatestPublishedVersionId,
                                   Visibility,
                                   ShareType
                            FROM ContentDocumentLinks
                            WHERE ContentDocument.FileExtension IN ('jpg','jpeg','png','gif','bmp')
                              AND Visibility = 'AllUsers'
                              AND ShareType  IN ('V','C')
                            ORDER BY Id DESC
                            LIMIT 1)
                    FROM Package_File__c
                    WHERE Dealer_Package__c = :appPkg.Dealer_Package__c
                      AND File_Type_del__c  = 'Header Logo'
                    LIMIT 1
                ];

                Boolean found = false;

                if (!packageLogoFiles.isEmpty()) {
                    // 2) Prefer distribution URL if available
                    String distUrl = tryGetDistributionUrl(packageLogoFiles[0].Id);
                    if (String.isNotBlank(distUrl)) {
                        packageLogoUrls.put(appPkg.Id, distUrl);
                        packageHasLogo.put(appPkg.Id, true);
                        found = true;
                    } else if (packageLogoFiles[0].ContentDocumentLinks != null &&
                               !packageLogoFiles[0].ContentDocumentLinks.isEmpty()) {
                        ContentDocumentLink logoLink = packageLogoFiles[0].ContentDocumentLinks[0];
                        String logoUrl = buildFileUrl(logoLink.ContentDocument.LatestPublishedVersionId);
                        packageLogoUrls.put(appPkg.Id, logoUrl);
                        packageHasLogo.put(appPkg.Id, true);
                        found = true;
                    }
                }

                if (!found) {
                    packageHasLogo.put(appPkg.Id, false);
                }
            }
        } catch (Exception e) {
            System.debug('Error in getPackageLogos: ' + e.getMessage());
        }
    }

    // ====== DEALER LOGO (community-safe) ======
    private void getDealerLogoUrl() {
        hasDealerLogo = false;
        dealerLogoUrl = '';

        try {
            Application__c app = [
                SELECT Id, Dealer_Name__c, Dealer_Name__r.Name
                FROM Application__c
                WHERE Id = :application.Id
                LIMIT 1
            ];
            if (app.Dealer_Name__c == null) return;

            // Prefer dealer logo from Dealer_Package__c (already copied + linked with AllUsers visibility)
            List<Application_Package__c> appPackages = [
                SELECT Dealer_Package__c
                FROM Application_Package__c
                WHERE Application__c = :application.Id
                  AND Dealer_Package__c != null
                LIMIT 1
            ];

            if (!appPackages.isEmpty()) {
                List<Package_File__c> dealerLogoFiles = [
                    SELECT Id,
                           (SELECT ContentDocumentId,
                                   ContentDocument.Title,
                                   ContentDocument.LatestPublishedVersionId,
                                   Visibility,
                                   ShareType
                            FROM ContentDocumentLinks
                            WHERE ContentDocument.FileExtension IN ('jpg','jpeg','png','gif','bmp')
                              AND Visibility = 'AllUsers'
                              AND ShareType  IN ('V','C')
                            ORDER BY Id DESC
                            LIMIT 1)
                    FROM Package_File__c
                    WHERE Dealer_Package__c = :appPackages[0].Dealer_Package__c
                      AND File_Type_del__c  = 'Dealer Logo'
                    LIMIT 1
                ];

                if (!dealerLogoFiles.isEmpty()) {
                    // Prefer distribution URL first
                    String distUrl = tryGetDistributionUrl(dealerLogoFiles[0].Id);
                    if (String.isNotBlank(distUrl)) {
                        dealerLogoUrl = distUrl;
                        hasDealerLogo = true;
                        return;
                    }
                    if (dealerLogoFiles[0].ContentDocumentLinks != null &&
                        !dealerLogoFiles[0].ContentDocumentLinks.isEmpty()) {
                        ContentDocumentLink logoLink = dealerLogoFiles[0].ContentDocumentLinks[0];
                        dealerLogoUrl = buildFileUrl(logoLink.ContentDocument.LatestPublishedVersionId);
                        hasDealerLogo = true;
                        return;
                    }
                }
            }

            // Fallback: pull from Dealer Account directly (try to pick something that looks like logo)
            List<ContentDocumentLink> dealerFiles = [
                SELECT ContentDocumentId,
                       ContentDocument.Title,
                       ContentDocument.FileExtension,
                       ContentDocument.LatestPublishedVersionId,
                       Visibility,
                       ShareType
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :app.Dealer_Name__c
                  AND ContentDocument.FileExtension IN ('jpg','jpeg','png','gif','bmp')
                  AND Visibility = 'AllUsers'
                  AND ShareType  IN ('V','C')
                ORDER BY Id DESC
                LIMIT 50
            ];

            if (dealerFiles.isEmpty()) return;

            ContentDocumentLink logoFile = null;
            for (ContentDocumentLink file : dealerFiles) {
                if (file.ContentDocument.Title != null &&
                    file.ContentDocument.Title.toLowerCase().contains('logo')) {
                    logoFile = file;
                    break;
                }
            }
            if (logoFile == null) logoFile = dealerFiles[0];

            if (logoFile != null) {
                dealerLogoUrl = buildFileUrl(logoFile.ContentDocument.LatestPublishedVersionId);
                hasDealerLogo = true;
            }
        } catch (Exception e) {
            hasDealerLogo = false;
        }
    }

    @AuraEnabled(cacheable=false)
    public static String generatePDFName(Id applicationId) {
        Application__c app = [SELECT Name FROM Application__c WHERE Id = :applicationId];
        return 'Application_' + app.Name + '.pdf';
    }

    public List<Application_Package_Option__c> getIncludedOptions(Id packageId) {
        return getIncludedOptionsImpl(packageId);
    }
    public List<Application_Package_Option__c> getOptionalOptions(Id packageId) {
        return getOptionalOptionsImpl(packageId);
    }
    public String getPackageInclusions(Id packageId) {
        return getPackageInclusionsImpl(packageId);
    }
    public String getPackageExclusions(Id packageId) {
        return getPackageExclusionsImpl(packageId);
    }

    private List<Application_Package_Option__c> getIncludedOptionsImpl(Id packageId) {
        List<Application_Package_Option__c> result = new List<Application_Package_Option__c>();
        List<Application_Package_Option__c> allOptions = packageOptions.get(packageId);
        if (allOptions != null) {
            for (Application_Package_Option__c opt : allOptions) {
                if (opt.Selection_Type__c == 'Included') result.add(opt);
            }
        }
        return result;
    }

    private List<Application_Package_Option__c> getOptionalOptionsImpl(Id packageId) {
        List<Application_Package_Option__c> result = new List<Application_Package_Option__c>();
        List<Application_Package_Option__c> allOptions = packageOptions.get(packageId);
        if (allOptions != null) {
            for (Application_Package_Option__c opt : allOptions) {
                if (opt.Selection_Type__c == 'Optional') result.add(opt);
            }
        }
        return result;
    }

    private String getPackageInclusionsImpl(Id packageId) {
        String result = '';
        List<Application_Package_Option__c> allOptions = packageOptions.get(packageId);
        if (allOptions != null) {
            List<String> inclusions = new List<String>();
            for (Application_Package_Option__c opt : allOptions) {
                if (opt.Selection_Type__c == 'Included' && String.isNotBlank(opt.Inclusion__c)) {
                    inclusions.add(opt.Inclusion__c);
                }
            }
            result = String.join(inclusions, '\n');
        }
        return result;
    }

    private String getPackageExclusionsImpl(Id packageId) {
        String result = '';
        List<Application_Package_Option__c> allOptions = packageOptions.get(packageId);
        if (allOptions != null) {
            List<String> exclusions = new List<String>();
            for (Application_Package_Option__c opt : allOptions) {
                if (opt.Selection_Type__c == 'Included' && String.isNotBlank(opt.Exclusion__c)) {
                    exclusions.add(opt.Exclusion__c);
                }
            }
            result = String.join(exclusions, '\n');
        }
        return result;
    }
}