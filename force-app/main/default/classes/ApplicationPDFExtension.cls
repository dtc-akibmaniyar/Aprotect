public without sharing class ApplicationPDFExtension {
    private final Application__c application;

    public String  dealerLogoUrl   { get; set; }
    public Boolean hasDealerLogo   { get; set; }
    
    // Dealer branding properties (replaces A-Protect branding)
    public String  dealerName      { get; set; }
    public String  dealerPhone     { get; set; }
    public String  dealerEmail     { get; set; }
    public String  dealerWebsite   { get; set; }
    public String  dealerAddress   { get; set; }

    public List<Application_Package__c> applicationPackages { get; private set; }
    private Map<Id, List<Application_Package_Option__c>>     packageOptions;
    private Map<Id, String>  packageLogoUrls;
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
        public String                              termsAndConditions { get; set; }
        public Boolean                             hasTermsAndConditions { get; set; }
        public String                              recordTypeName   { get; set; }
        public Boolean                             isTireRim        { get; set; }
        public Boolean                             isLast           { get; set; }
        // Flattened relationship fields for PDF renderer compatibility
        public String                              planName         { get; set; }
        public String                              termName         { get; set; }
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

        loadDealerBranding();  // sets dealer branding + logo
        getDealerLogoUrl();    // sets dealerLogoUrl / hasDealerLogo

        packageOptions         = new Map<Id, List<Application_Package_Option__c>>();
        packageLogoUrls        = new Map<Id, String>();
        packageHasLogo         = new Map<Id, Boolean>();
        recordTypeWrappers     = new Map<String, RecordTypeWrapper>();
        recordTypeWrappersList = new List<RecordTypeWrapper>();

        getLatestPackagesFromEachRecordType();
        getPackageLogos();

        // Pre-load T&C for all packages
        Map<Id, String> termsMap = loadTermsAndConditions();

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

            // Flatten relationship fields to avoid PDF renderer traversal issues
            wrapper.planName = (pkg.Package__r != null && pkg.Package__r.Name != null)
                ? pkg.Package__r.Name : '';
            wrapper.termName = (pkg.Package_Term__r != null && pkg.Package_Term__r.Name != null)
                ? pkg.Package_Term__r.Name : '';

            if (pkg.Contract_Start_Date__c != null) {
                wrapper.contractStartDate = ((DateTime) pkg.Contract_Start_Date__c).format('yyyy-MM-dd');
            }
            if (pkg.Contract_End_Date__c != null) {
                wrapper.contractEndDate   = ((DateTime) pkg.Contract_End_Date__c).format('yyyy-MM-dd');
            }

            // T&C resolution
            wrapper.termsAndConditions = termsMap.containsKey(pkg.Id) ? termsMap.get(pkg.Id) : '';
            wrapper.hasTermsAndConditions = String.isNotBlank(wrapper.termsAndConditions);
            
            // Record type info
            String rt = String.isBlank(pkg.Package_Record_Type__c) ? 'Other' : pkg.Package_Record_Type__c;
            wrapper.recordTypeName = rt;
            wrapper.isTireRim = rt.containsIgnoreCase('Tire') && rt.containsIgnoreCase('Rim');

            String inclusionsStr = getPackageInclusionsImpl(pkg.Id);
            String exclusionsStr = getPackageExclusionsImpl(pkg.Id);

            wrapper.inclusionsList = String.isBlank(inclusionsStr) ? new List<String>() : inclusionsStr.split('\\n');
            wrapper.exclusionsList = String.isBlank(exclusionsStr) ? new List<String>() : exclusionsStr.split('\\n');

            if (!recordTypeWrappers.containsKey(rt)) {
                RecordTypeWrapper rtw = new RecordTypeWrapper(rt);
                recordTypeWrappers.put(rt, rtw);
                recordTypeWrappersList.add(rtw);
            }
            recordTypeWrappers.get(rt).packages.add(wrapper);
        }

        for (RecordTypeWrapper rtw : recordTypeWrappersList) {
            if (!rtw.packages.isEmpty()) {
                rtw.packages[rtw.packages.size() - 1].isLast = true;
            }
        }

        // Filter by rt param if present
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

    /**
     * @description Load dealer branding info from the Application's dealer Account
     */
    private void loadDealerBranding() {
        dealerName = '';
        dealerPhone = '';
        dealerEmail = '';
        dealerWebsite = '';
        dealerAddress = '';

        try {
            Application__c app = [
                SELECT Id, Dealer_Name__c,
                       Dealer_Name__r.Name,
                       Dealer_Name__r.Phone,
                       Dealer_Name__r.Email__c,
                       Dealer_Name__r.Website,
                       Dealer_Name__r.BillingStreet,
                       Dealer_Name__r.BillingCity,
                       Dealer_Name__r.BillingState,
                       Dealer_Name__r.BillingPostalCode,
                       Dealer_Name__r.BillingCountry,
                       Dealer_Name__r.DealerLogo__c
                FROM Application__c
                WHERE Id = :application.Id
                LIMIT 1
            ];

            if (app.Dealer_Name__c != null && app.Dealer_Name__r != null) {
                dealerName = app.Dealer_Name__r.Name != null ? app.Dealer_Name__r.Name : '';
                dealerPhone = app.Dealer_Name__r.Phone != null ? app.Dealer_Name__r.Phone : '';
                dealerEmail = app.Dealer_Name__r.Email__c != null ? app.Dealer_Name__r.Email__c : '';
                dealerWebsite = app.Dealer_Name__r.Website != null ? app.Dealer_Name__r.Website : '';
                
                List<String> addrParts = new List<String>();
                if (String.isNotBlank(app.Dealer_Name__r.BillingStreet)) addrParts.add(app.Dealer_Name__r.BillingStreet);
                if (String.isNotBlank(app.Dealer_Name__r.BillingCity)) addrParts.add(app.Dealer_Name__r.BillingCity);
                if (String.isNotBlank(app.Dealer_Name__r.BillingState)) addrParts.add(app.Dealer_Name__r.BillingState);
                if (String.isNotBlank(app.Dealer_Name__r.BillingPostalCode)) addrParts.add(app.Dealer_Name__r.BillingPostalCode);
                dealerAddress = String.join(addrParts, ', ');

                // Dealer logo from DealerLogo__c field (rich text - extract img src URL)
                if (String.isNotBlank(app.Dealer_Name__r.DealerLogo__c)) {
                    String logoField = app.Dealer_Name__r.DealerLogo__c;
                    // Extract URL from rich text HTML (e.g. <img src="https://...">)
                    if (logoField.containsIgnoreCase('<img') && logoField.containsIgnoreCase('src=')) {
                        Integer srcStart = logoField.indexOfIgnoreCase('src="');
                        if (srcStart >= 0) {
                            srcStart += 5; // skip past src="
                            Integer srcEnd = logoField.indexOf('"', srcStart);
                            if (srcEnd > srcStart) {
                                dealerLogoUrl = logoField.substring(srcStart, srcEnd);
                                // Decode HTML entities
                                dealerLogoUrl = dealerLogoUrl.replace('&amp;', '&');
                                hasDealerLogo = true;
                            }
                        }
                    } else if (logoField.startsWithIgnoreCase('http')) {
                        // Plain URL
                        dealerLogoUrl = logoField.trim();
                        hasDealerLogo = true;
                    }
                }
            }
        } catch (Exception e) {
            System.debug('Error loading dealer branding: ' + e.getMessage());
        }
    }

    /**
     * @description Load Terms & Conditions for each application package.
     * Priority: Dealer_Package_Terms__c (dealer override) > Package__c.Terms_and_Conditions__c (default)
     * @return Map of Application_Package__c.Id => T&C HTML content
     */
    private Map<Id, String> loadTermsAndConditions() {
        Map<Id, String> termsMap = new Map<Id, String>();

        try {
            // Get dealer ID from application
            Application__c app = [
                SELECT Dealer_Name__c FROM Application__c WHERE Id = :application.Id LIMIT 1
            ];
            Id dealerId = app.Dealer_Name__c;

            // Collect Package__c IDs and Package_Group__c IDs from application packages
            Set<Id> packageIds = new Set<Id>();
            Set<Id> packageGroupIds = new Set<Id>();
            Map<Id, Id> appPkgToPackage = new Map<Id, Id>();       // AppPkg.Id => Package__c.Id
            Map<Id, Id> appPkgToPackageGroup = new Map<Id, Id>();  // AppPkg.Id => Package_Group__c.Id

            for (Application_Package__c appPkg : applicationPackages) {
                if (appPkg.Package__r != null && appPkg.Package__r.Id != null) {
                    packageIds.add(appPkg.Package__r.Id);
                    appPkgToPackage.put(appPkg.Id, appPkg.Package__r.Id);
                }
            }

            if (packageIds.isEmpty()) return termsMap;

            // Load Package_Group__c for each application package's Package
            Map<Id, Id> pkgToGroup = new Map<Id, Id>();
            for (Package__c pkg : [
                SELECT Id, Package_Group__c
                FROM Package__c
                WHERE Id IN :packageIds
            ]) {
                if (pkg.Package_Group__c != null) {
                    pkgToGroup.put(pkg.Id, pkg.Package_Group__c);
                    packageGroupIds.add(pkg.Package_Group__c);
                }
            }

            // Map AppPkg => Package_Group
            for (Id appPkgId : appPkgToPackage.keySet()) {
                Id pkgId = appPkgToPackage.get(appPkgId);
                if (pkgToGroup.containsKey(pkgId)) {
                    appPkgToPackageGroup.put(appPkgId, pkgToGroup.get(pkgId));
                }
            }

            // 1. Load dealer-specific overrides (if dealer exists)
            // Match by exact Package__c OR by Package_Group__c (same warranty family)
            Map<Id, String> dealerOverridesByPkg = new Map<Id, String>();
            Map<Id, String> dealerOverridesByGroup = new Map<Id, String>();
            if (dealerId != null) {
                for (Dealer_Package_Terms__c dpt : [
                    SELECT Package__c, Package__r.Package_Group__c, Terms_and_Conditions__c
                    FROM Dealer_Package_Terms__c
                    WHERE Dealer__c = :dealerId
                ]) {
                    if (String.isBlank(dpt.Terms_and_Conditions__c)) continue;
                    // Exact package match
                    if (packageIds.contains(dpt.Package__c)) {
                        dealerOverridesByPkg.put(dpt.Package__c, dpt.Terms_and_Conditions__c);
                    }
                    // Package Group match (same warranty family)
                    if (dpt.Package__r != null && dpt.Package__r.Package_Group__c != null
                        && packageGroupIds.contains(dpt.Package__r.Package_Group__c)) {
                        dealerOverridesByGroup.put(dpt.Package__r.Package_Group__c, dpt.Terms_and_Conditions__c);
                    }
                }
            }

            // 2. Load default T&C from Package__c
            Map<Id, String> defaultTerms = new Map<Id, String>();
            for (Package__c pkg : [
                SELECT Id, Terms_and_Conditions__c
                FROM Package__c
                WHERE Id IN :packageIds
            ]) {
                if (pkg.Terms_and_Conditions__c != null) defaultTerms.put(pkg.Id, pkg.Terms_and_Conditions__c);
            }

            // 3. Resolve priority: exact dealer override > group dealer override > package default
            for (Id appPkgId : appPkgToPackage.keySet()) {
                Id pkgId = appPkgToPackage.get(appPkgId);
                Id groupId = appPkgToPackageGroup.containsKey(appPkgId) ? appPkgToPackageGroup.get(appPkgId) : null;

                if (dealerOverridesByPkg.containsKey(pkgId)) {
                    termsMap.put(appPkgId, dealerOverridesByPkg.get(pkgId));
                } else if (groupId != null && dealerOverridesByGroup.containsKey(groupId)) {
                    termsMap.put(appPkgId, dealerOverridesByGroup.get(groupId));
                } else if (defaultTerms.containsKey(pkgId)) {
                    termsMap.put(appPkgId, defaultTerms.get(pkgId));
                }
            }

        } catch (Exception e) {
            System.debug('Error loading Terms & Conditions: ' + e.getMessage());
        }

        return termsMap;
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
                       Odometer_Start_Unit__c,
                       Odometer_End_Unit__c,
                       Contract_Premium_Price__c,
                       Tax_Percentage__c,
                       Contract_Premium_Price_Without_Tax__c,
                       Tax_Amount__c,
                       Total_Package_Price__c,
                       Dealer_Package__c,
                       Dealer_Package__r.Package__c,
                       Tire_Brand__c,
                       Tire_Type__c,
                       Tread_Depth__c,
                       Tread_Depth_Unit__c,
                       Rim_Brand__c,
                       Rim_Type__c,
                       Rim_Size__c,
                       Rim_Size_Unit__c,
                       CreatedDate,
                       (SELECT Id, Name, Option__c, Selection_Type__c, Inclusion__c, Exclusion__c
                        FROM Application_Package_Options__r
                        ORDER BY Selection_Type__c)
                FROM Application_Package__c
                WHERE Application__c = :application.Id
                  AND Active__c = true
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

    private String buildFileUrl(String versionId) {
        String prefix = Site.getPathPrefix();
        if (!String.isBlank(prefix) && prefix.startsWith('/sfsites')) {
            return prefix + '/sfc/servlet.shepherd/version/download/' + versionId;
        }
        return '/sfc/servlet.shepherd/version/download/' + versionId;
    }

    private String tryGetDistributionUrl(Id packageFileId) {
        System.debug('Trying to get distribution URL for package file: ' + packageFileId);

        List<ContentDistribution> dists = [
            SELECT DistributionPublicUrl, ExpiryDate, PreferencesAllowViewInBrowser
            FROM ContentDistribution
            WHERE RelatedRecordId = :packageFileId
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];

        System.debug('Found distributions: ' + dists);

        return dists.isEmpty() ? null : dists[0].DistributionPublicUrl;
    }

    private void getPackageLogos() {
        try {
            System.debug('Getting package logos for application packages: ' + applicationPackages);
            for (Application_Package__c appPkg : applicationPackages) {
                if (appPkg.Dealer_Package__c == null) continue;

                List<Package_File__c> packageLogoFiles = [
                    SELECT Id,
                           (SELECT ContentDocumentId,
                                   ContentDocument.Title,
                                   ContentDocument.LatestPublishedVersionId,
                                   Visibility,
                                   ShareType
                            FROM ContentDocumentLinks
                            WHERE ContentDocument.FileExtension IN ('jpg','jpeg','png','gif','bmp')
                            ORDER BY Id DESC
                            LIMIT 1)
                    FROM Package_File__c
                    WHERE Dealer_Package__c = :appPkg.Dealer_Package__c
                      AND File_Type_del__c  = 'Package Logo'
                    LIMIT 1
                ];

                System.debug('Found package logo files for package ' + appPkg.Id + ': ' + packageLogoFiles);

                Boolean found = false;

                if (!packageLogoFiles.isEmpty() &&
                    packageLogoFiles[0].ContentDocumentLinks != null &&
                    !packageLogoFiles[0].ContentDocumentLinks.isEmpty()) {
                    ContentDocumentLink logoLink = packageLogoFiles[0].ContentDocumentLinks[0];
                    String logoUrl = buildFileUrl(logoLink.ContentDocument.LatestPublishedVersionId);
                    packageLogoUrls.put(appPkg.Id, logoUrl);
                    System.debug('Set package logo URL for package ' + appPkg.Id + ': ' + logoUrl);
                    packageHasLogo.put(appPkg.Id, true);
                    found = true;
                }

                if (!found) {
                    packageHasLogo.put(appPkg.Id, false);
                }
            }
        } catch (Exception e) {
            System.debug('Error in getPackageLogos: ' + e.getMessage());
        }
    }

    private void getDealerLogoUrl() {
        // If already set by loadDealerBranding (from DealerLogo__c field), skip
        if (hasDealerLogo != null && hasDealerLogo) return;

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
                      AND File_Type_del__c  = 'Package Logo'
                    LIMIT 1
                ];

                if (!dealerLogoFiles.isEmpty()) {
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

            // Fallback to Dealer Account files
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