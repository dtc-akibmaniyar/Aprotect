/**
 * @description Controller extension for the QuotePDF Visualforce page.
 * Similar to ApplicationPDFExtension but:
 * - Shows ALL active packages (no record type filtering)
 * - Checks Show_Logo_On_PDF__c on dealer Account for logo visibility
 */
public without sharing class QuotePDFExtension {
    private final Application__c application;

    public String  dealerLogoUrl   { get; set; }
    public Boolean hasDealerLogo   { get; set; }
    
    // Dealer branding properties
    public String  dealerName      { get; set; }
    public String  dealerPhone     { get; set; }
    public String  dealerEmail     { get; set; }
    public String  dealerWebsite   { get; set; }
    public String  dealerAddress   { get; set; }

    // Vehicle/Customer display fields (populated via SOQL for PDF compatibility)
    public String vehicleYear       { get; set; }
    public String vehicleMake       { get; set; }
    public String vehicleModel      { get; set; }
    public String vehicleTrim       { get; set; }
    public String vehicleVIN        { get; set; }
    public String vehicleOdometer   { get; set; }
    public String vehicleOdometerUnit { get; set; }
    public String vehiclePurchasePrice { get; set; }
    public String vehicleDeliveryDate { get; set; }
    public String vehicleTransmission { get; set; }
    public String vehicleFuel       { get; set; }
    public String vehicleEngine     { get; set; }
    public String vehicleColor      { get; set; }
    public String vehicleBodyStyle  { get; set; }
    public String vehicleCommercial { get; set; }
    public String customerFirstName { get; set; }
    public String customerLastName  { get; set; }
    public String customerStreet    { get; set; }
    public String customerCity      { get; set; }
    public String customerState     { get; set; }
    public String customerPostalCode { get; set; }
    public String customerPhone     { get; set; }
    public String customerEmail     { get; set; }

    // Logo whitelisting flag
    public Boolean showLogoOnPdf   { get; set; }

    // Computed quote total across all active packages
    public Decimal quoteTotal { get; private set; }

    // Aprotect fallback branding
    public Boolean useAprotectBranding { get; set; }

    public List<Application_Package__c> applicationPackages { get; private set; }
    private Map<Id, String>  packageLogoUrls;
    private Map<Id, Boolean> packageHasLogo;

    /**
     * P4 [S]: one optional add-on rendered on the quote PDF. Plain display
     * values (no SObject) sourced from the package's priced Option LINE ITEMS
     * (Line_Type__c = 'Option' — the engine snapshot contract the S5 option
     * writers create on add; Application_Package_Option__c children are
     * retired). A package with no Option lines renders no additional options
     * (the same empty state every real quote renders today).
     */
    public class OptionDisplay {
        public String  optionName   { get; set; }
        public Decimal retailPrice  { get; set; }
        public OptionDisplay(String name, Decimal retail) {
            this.optionName = name;
            this.retailPrice = retail;
        }
    }

    /**
     * P4 [T] stored-snapshot money (change-implementation plan §11 P4 [T],
     * §07.3): when an engine-priced Application_Package carries its persisted
     * line-item snapshot, the PDF's package price / quote totals render from
     * the stored lines (sum(non-Tax lines) = no-tax total, sum(Tax lines) =
     * tax, sum(all) = with-tax total — the exact rebuild the per-tab payloads
     * use), so contract PDF, portal and invoice agree on mixed-fee deals
     * (P4 exit criteria). Fee lines with no stored carrier on
     * Application_Package__c (diesel / commercial / powersports) and the
     * premium fee otherwise fall out of the legacy formula surface; the line
     * set carries them. Packages WITHOUT a line set keep the legacy
     * stored/formula build byte-for-byte (the flag-off state renders exactly
     * as before this change).
     */
    public class StoredLineMoney {
        public Boolean hasLines   { get; set; }
        public Decimal noTaxTotal { get; set; }
        public Decimal taxTotal   { get; set; }
    }
    private Map<Id, StoredLineMoney> storedLineMoneyByPkg = new Map<Id, StoredLineMoney>();

    public class PackageWrapper {
        public Application_Package__c              pkg              { get; set; }
        public String                              packageName      { get; set; }
        public String                              termName         { get; set; }
        // P4 [S]: optional add-ons rendered with their priced retail, read
        // from the package's Option LINE ITEMS (see OptionDisplay).
        public List<OptionDisplay>                 optionalOptions  { get; set; }
        public String                              packageLogoUrl   { get; set; }
        public Boolean                             hasPackageLogo   { get; set; }
        public String                              contractStartDate{ get; set; }
        public String                              contractEndDate  { get; set; }
        public String                              termsAndConditions { get; set; }
        public Boolean                             hasTermsAndConditions { get; set; }
        public String                              recordTypeName   { get; set; }
        public Boolean                             isTireRim        { get; set; }
        public Decimal                             retailPriceTotal { get; set; }
        // P4 [T]: when true the wrapper's money comes from the stored line set.
        public Boolean                             hasStoredLineMoney { get; set; }
        public Decimal                             storedTaxTotal     { get; set; }
    }

    // Single flat list (no record-type grouping needed for quote)
    public List<PackageWrapper> packageWrappersList { get; private set; }

    public QuotePDFExtension(ApexPages.StandardController stdController) {
        // Ensure all fields used in VF merge expressions are loaded
        if (!Test.isRunningTest()) {
            stdController.addFields(new List<String>{
                'Customer_First_Name__c', 'Customer_Last_Name__c',
                'Customer_Name__c',
                'Customer_Name__r.BillingStreet', 'Customer_Name__r.BillingCity',
                'Customer_Name__r.BillingState', 'Customer_Name__r.BillingPostalCode',
                'Customer_Name__r.Phone', 'Customer_Name__r.PersonEmail',
                'Vehicle_Year__c', 'Vehicle_Make__c', 'Vehicle_Model__c',
                'Vehicle__r.Trim__c', 'Vehicle_VIN__c', 'Odometer__c',
                'Vehicle__r.Odometer_Unit__c', 'Vehicle_Purchase_Price__c',
                'Vehicle__r.Delivery_Date__c', 'Vehicle__r.Transmission__c',
                'Vehicle__r.Fuel_Type__c', 'Vehicle__r.Engine__c',
                'Vehicle__r.Color__c', 'Vehicle__r.Body_Style__c',
                'Vehicle__r.Business_Commercial_Use__c',
                'Dealer_Name__c', 'Dealer_Name__r.Name',
                'Dealer_Name__r.DealerLogo__c', 'Dealer_Name__r.Show_Logo_On_PDF__c'
            });
        }
        this.application = (Application__c) stdController.getRecord();

        loadDealerBranding();
        getDealerLogoUrl();

        // Show dealer logo if DealerLogo__c is populated (no opt-in gate needed)

        // Set Aprotect fallback branding flag
        useAprotectBranding = !hasDealerLogo || !showLogoOnPdf;

        loadVehicleAndCustomerFields();

        packageLogoUrls        = new Map<Id, String>();
        packageHasLogo         = new Map<Id, Boolean>();
        packageWrappersList    = new List<PackageWrapper>();

        getAllActivePackages();
        getPackageLogos();
        loadStoredLineMoney();
        // P4 [S]: optional add-on display state — priced Option line items of
        // the package (the engine snapshot contract); APO children retired.
        Map<Id, List<OptionDisplay>> optionDisplaysByPkg = loadOptionalOptionDisplays();

        // Pre-load T&C for all packages
        Map<Id, String> termsMap = loadTermsAndConditions();

        for (Application_Package__c pkg : applicationPackages) {
            PackageWrapper wrapper  = new PackageWrapper();
            wrapper.pkg             = pkg;
            // P4 flip [T]-follow-up: engine-priced Application_Package records
            // carry NO master Package__c / Package_Term__c links (the
            // create-time flow that wrote them backs off at its engine guard),
            // so the plan header would render blank and the term 'N/A' on
            // engine-quote PDFs. Resolve the display through the dealer copy
            // links the engine path DOES carry (Dealer_Package__c /
            // Dealer_Package_Term__c -> their masters, then the copy names),
            // master-first so the legacy path stays byte-identical.
            wrapper.packageName = pkg.Package__r != null && String.isNotBlank(pkg.Package__r.Name)
                ? pkg.Package__r.Name
                : (pkg.Dealer_Package__r != null && pkg.Dealer_Package__r.Package__r != null
                        && String.isNotBlank(pkg.Dealer_Package__r.Package__r.Name)
                    ? pkg.Dealer_Package__r.Package__r.Name
                    : (pkg.Dealer_Package__r != null && String.isNotBlank(pkg.Dealer_Package__r.Name)
                        ? pkg.Dealer_Package__r.Name : ''));
            wrapper.termName = pkg.Package_Term__r != null && String.isNotBlank(pkg.Package_Term__r.Name)
                ? pkg.Package_Term__r.Name
                : (pkg.Dealer_Package_Term__r != null && pkg.Dealer_Package_Term__r.Package_Term__r != null
                        && String.isNotBlank(pkg.Dealer_Package_Term__r.Package_Term__r.Name)
                    ? pkg.Dealer_Package_Term__r.Package_Term__r.Name
                    : (pkg.Dealer_Package_Term__r != null && String.isNotBlank(pkg.Dealer_Package_Term__r.Name)
                        ? pkg.Dealer_Package_Term__r.Name : 'N/A'));
            wrapper.optionalOptions = optionDisplaysByPkg.containsKey(pkg.Id)
                ? optionDisplaysByPkg.get(pkg.Id) : new List<OptionDisplay>();
            wrapper.packageLogoUrl  = packageLogoUrls.get(pkg.Id);
            wrapper.hasPackageLogo  = packageHasLogo.containsKey(pkg.Id) ? packageHasLogo.get(pkg.Id) : false;

            if (pkg.Contract_Start_Date__c != null) {
                wrapper.contractStartDate = String.valueOf(pkg.Contract_Start_Date__c);
            }
            if (pkg.Contract_End_Date__c != null) {
                wrapper.contractEndDate   = String.valueOf(pkg.Contract_End_Date__c);
            }

            wrapper.termsAndConditions = termsMap.containsKey(pkg.Id) ? termsMap.get(pkg.Id) : '';
            wrapper.hasTermsAndConditions = String.isNotBlank(wrapper.termsAndConditions);
            
            String rt = String.isBlank(pkg.Package_Record_Type__c) ? 'Other' : pkg.Package_Record_Type__c;
            wrapper.recordTypeName = rt;
            wrapper.isTireRim = rt.containsIgnoreCase('Tire') && rt.containsIgnoreCase('Rim');

            Decimal retailBase = pkg.Dealer_Package_Retail_Price__c != null ? pkg.Dealer_Package_Retail_Price__c : 0;
            Decimal retailAddons = pkg.Add_Ons_Retail_Price__c != null ? pkg.Add_Ons_Retail_Price__c : 0;
            StoredLineMoney lineMoney = storedLineMoneyByPkg.get(pkg.Id);
            if (lineMoney != null && lineMoney.hasLines) {
                // Engine-priced package with a persisted line set: PDF money
                // renders from the stored snapshot (§07.3 rebuild).
                wrapper.hasStoredLineMoney = true;
                wrapper.retailPriceTotal = lineMoney.noTaxTotal;
                wrapper.storedTaxTotal = lineMoney.taxTotal;
            } else {
                wrapper.retailPriceTotal = retailBase + retailAddons;
            }

            packageWrappersList.add(wrapper);
        }

        // Calculate quote total (sub-total) = sum of retail prices (pre-tax)
        Decimal total = 0;
        for (PackageWrapper pw : packageWrappersList) {
            total += pw.retailPriceTotal;
        }
        quoteTotal = total;
    }

    private void loadDealerBranding() {
        dealerName = '';
        dealerPhone = '';
        dealerEmail = '';
        dealerWebsite = '';
        dealerAddress = '';
        showLogoOnPdf = false;

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
                       Dealer_Name__r.DealerLogo__c,
                       Dealer_Name__r.Show_Logo_On_PDF__c
                FROM Application__c
                WHERE Id = :application.Id
                LIMIT 1
            ];

            if (app.Dealer_Name__c != null && app.Dealer_Name__r != null) {
                dealerName = app.Dealer_Name__r.Name != null ? app.Dealer_Name__r.Name : '';
                dealerPhone = app.Dealer_Name__r.Phone != null ? app.Dealer_Name__r.Phone : '';
                dealerEmail = app.Dealer_Name__r.Email__c != null ? app.Dealer_Name__r.Email__c : '';
                dealerWebsite = app.Dealer_Name__r.Website != null ? app.Dealer_Name__r.Website : '';
                showLogoOnPdf = app.Dealer_Name__r.Show_Logo_On_PDF__c == true;
                
                List<String> addrParts = new List<String>();
                if (String.isNotBlank(app.Dealer_Name__r.BillingStreet)) addrParts.add(app.Dealer_Name__r.BillingStreet);
                if (String.isNotBlank(app.Dealer_Name__r.BillingCity)) addrParts.add(app.Dealer_Name__r.BillingCity);
                if (String.isNotBlank(app.Dealer_Name__r.BillingState)) addrParts.add(app.Dealer_Name__r.BillingState);
                if (String.isNotBlank(app.Dealer_Name__r.BillingPostalCode)) addrParts.add(app.Dealer_Name__r.BillingPostalCode);
                dealerAddress = String.join(addrParts, ', ');

                if (String.isNotBlank(app.Dealer_Name__r.DealerLogo__c)) {
                    String logoField = app.Dealer_Name__r.DealerLogo__c;
                    if (logoField.containsIgnoreCase('<img') && logoField.containsIgnoreCase('src=')) {
                        Integer srcStart = logoField.indexOfIgnoreCase('src="');
                        if (srcStart >= 0) {
                            srcStart += 5;
                            Integer srcEnd = logoField.indexOf('"', srcStart);
                            if (srcEnd > srcStart) {
                                dealerLogoUrl = logoField.substring(srcStart, srcEnd);
                                dealerLogoUrl = dealerLogoUrl.replace('&amp;', '&');
                                hasDealerLogo = true;
                            }
                        }
                    } else if (logoField.startsWithIgnoreCase('http')) {
                        dealerLogoUrl = logoField.trim();
                        hasDealerLogo = true;
                    }
                }
            }
        } catch (Exception e) {
            System.debug('Error loading dealer branding: ' + e.getMessage());
        }
    }

    private Map<Id, String> loadTermsAndConditions() {
        Map<Id, String> termsMap = new Map<Id, String>();

        try {
            Application__c app = [
                SELECT Dealer_Name__c FROM Application__c WHERE Id = :application.Id LIMIT 1
            ];
            Id dealerId = app.Dealer_Name__c;

            Set<Id> packageIds = new Set<Id>();
            Set<Id> packageGroupIds = new Set<Id>();
            Map<Id, Id> appPkgToPackage = new Map<Id, Id>();
            Map<Id, Id> appPkgToPackageGroup = new Map<Id, Id>();

            for (Application_Package__c appPkg : applicationPackages) {
                if (appPkg.Package__r != null && appPkg.Package__r.Id != null) {
                    packageIds.add(appPkg.Package__r.Id);
                    appPkgToPackage.put(appPkg.Id, appPkg.Package__r.Id);
                }
            }

            if (packageIds.isEmpty()) return termsMap;

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

            for (Id appPkgId : appPkgToPackage.keySet()) {
                Id pkgId = appPkgToPackage.get(appPkgId);
                if (pkgToGroup.containsKey(pkgId)) {
                    appPkgToPackageGroup.put(appPkgId, pkgToGroup.get(pkgId));
                }
            }

            Map<Id, String> dealerOverridesByPkg = new Map<Id, String>();
            Map<Id, String> dealerOverridesByGroup = new Map<Id, String>();
            if (dealerId != null) {
                for (Dealer_Package_Terms__c dpt : [
                    SELECT Package__c, Package__r.Package_Group__c, Terms_and_Conditions__c
                    FROM Dealer_Package_Terms__c
                    WHERE Dealer__c = :dealerId
                ]) {
                    if (String.isBlank(dpt.Terms_and_Conditions__c)) continue;
                    if (packageIds.contains(dpt.Package__c)) {
                        dealerOverridesByPkg.put(dpt.Package__c, dpt.Terms_and_Conditions__c);
                    }
                    if (dpt.Package__r != null && dpt.Package__r.Package_Group__c != null
                        && packageGroupIds.contains(dpt.Package__r.Package_Group__c)) {
                        dealerOverridesByGroup.put(dpt.Package__r.Package_Group__c, dpt.Terms_and_Conditions__c);
                    }
                }
            }

            Map<Id, String> defaultTerms = new Map<Id, String>();
            for (Package__c pkg : [
                SELECT Id, Terms_and_Conditions__c
                FROM Package__c
                WHERE Id IN :packageIds
            ]) {
                if (pkg.Terms_and_Conditions__c != null) defaultTerms.put(pkg.Id, pkg.Terms_and_Conditions__c);
            }

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

    /**
     * @description Get ALL active packages — no record type filtering, no dedup
     */
    private void loadVehicleAndCustomerFields() {
        try {
            Application__c fullApp = [
                SELECT Customer_First_Name__c, Customer_Last_Name__c,
                       Customer_Name__r.BillingStreet, Customer_Name__r.BillingCity,
                       Customer_Name__r.BillingState, Customer_Name__r.BillingPostalCode,
                       Customer_Name__r.Phone, Customer_Name__r.PersonEmail,
                       Vehicle_Year__c, Vehicle_Make__c, Vehicle_Model__c,
                       Vehicle__r.Trim__c, Vehicle_VIN__c, Odometer__c,
                       Vehicle__r.Odometer_Unit__c, Vehicle_Purchase_Price__c,
                       Vehicle__r.Delivery_Date__c, Vehicle__r.Transmission__c,
                       Vehicle__r.Fuel_Type__c, Vehicle__r.Engine__c,
                       Vehicle__r.Color__c, Vehicle__r.Body_Style__c,
                       Vehicle__r.Business_Commercial_Use__c
                FROM Application__c WHERE Id = :application.Id LIMIT 1
            ];
            customerFirstName = fullApp.Customer_First_Name__c != null ? fullApp.Customer_First_Name__c : '';
            customerLastName = fullApp.Customer_Last_Name__c != null ? fullApp.Customer_Last_Name__c : '';
            if (fullApp.Customer_Name__r != null) {
                customerStreet = fullApp.Customer_Name__r.BillingStreet;
                customerCity = fullApp.Customer_Name__r.BillingCity;
                customerState = fullApp.Customer_Name__r.BillingState;
                customerPostalCode = fullApp.Customer_Name__r.BillingPostalCode;
                customerPhone = fullApp.Customer_Name__r.Phone;
                customerEmail = fullApp.Customer_Name__r.PersonEmail;
            }
            vehicleYear = fullApp.Vehicle_Year__c != null ? fullApp.Vehicle_Year__c : '';
            vehicleMake = fullApp.Vehicle_Make__c != null ? fullApp.Vehicle_Make__c : '';
            vehicleModel = fullApp.Vehicle_Model__c != null ? fullApp.Vehicle_Model__c : '';
            vehicleVIN = fullApp.Vehicle_VIN__c != null ? fullApp.Vehicle_VIN__c : '';
            if (fullApp.Vehicle__r != null) {
                vehicleTrim = fullApp.Vehicle__r.Trim__c;
                vehicleOdometerUnit = fullApp.Vehicle__r.Odometer_Unit__c;
                vehicleTransmission = fullApp.Vehicle__r.Transmission__c;
                vehicleFuel = fullApp.Vehicle__r.Fuel_Type__c;
                vehicleEngine = fullApp.Vehicle__r.Engine__c;
                vehicleColor = fullApp.Vehicle__r.Color__c;
                vehicleBodyStyle = fullApp.Vehicle__r.Body_Style__c;
                vehicleCommercial = fullApp.Vehicle__r.Business_Commercial_Use__c ? 'Yes' : 'No';
                if (fullApp.Vehicle__r.Delivery_Date__c != null) {
                    vehicleDeliveryDate = fullApp.Vehicle__r.Delivery_Date__c.format();
                }
            }
            if (fullApp.Odometer__c != null) {
                vehicleOdometer = String.valueOf(fullApp.Odometer__c.intValue());
            }
            if (fullApp.Vehicle_Purchase_Price__c != null) {
                vehiclePurchasePrice = '$' + fullApp.Vehicle_Purchase_Price__c.setScale(2).format();
            }
        } catch (Exception e) {
            System.debug('Error loading vehicle/customer fields: ' + e.getMessage());
        }
    }

    private void getAllActivePackages() {
        try {
            applicationPackages = [
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
                       Dealer_Package_Retail_Price__c,
                       Add_Ons_Retail_Price__c,
                       Dealer_Package__c,
                       Dealer_Package__r.Package__c,
                       Dealer_Package__r.Name,
                       Dealer_Package__r.Package__r.Name,
                       Dealer_Package_Term__r.Name,
                       Dealer_Package_Term__r.Package_Term__r.Name,
                       Tire_Brand__c,
                       Tire_Type__c,
                       Tread_Depth__c,
                       Tread_Depth_Unit__c,
                       Rim_Brand__c,
                       Rim_Type__c,
                       Rim_Size__c,
                       Rim_Size_Unit__c,
                       CreatedDate
                FROM Application_Package__c
                WHERE Application__c = :application.Id
                  AND Active__c = true
                ORDER BY Package_Record_Type__c, CreatedDate DESC
            ];
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
        List<ContentDistribution> dists = [
            SELECT DistributionPublicUrl, ExpiryDate, PreferencesAllowViewInBrowser
            FROM ContentDistribution
            WHERE RelatedRecordId = :packageFileId
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        return dists.isEmpty() ? null : dists[0].DistributionPublicUrl;
    }

    private void getPackageLogos() {
        try {
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

    private void getDealerLogoUrl() {
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
                      AND File_Type_del__c  = 'Dealer Logo'
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

    /**
     * P4 [S]: the quote PDF's optional add-ons come from the package's priced
     * Option LINE ITEMS (the engine snapshot contract — the S5 option writers
     * create these on add with Amount = the priced retail, Description = the
     * option name). Packages without Option lines render no additional
     * options. SYSTEM_MODE read: the P4 line-item fields carry no portal FLS
     * yet (the same mode the engine writes and every line reader uses).
     */
    private Map<Id, List<OptionDisplay>> loadOptionalOptionDisplays() {
        Map<Id, List<OptionDisplay>> byPkg = new Map<Id, List<OptionDisplay>>();
        if (applicationPackages == null || applicationPackages.isEmpty()) {
            return byPkg;
        }
        Set<Id> pkgIds = new Set<Id>();
        for (Application_Package__c p : applicationPackages) {
            pkgIds.add(p.Id);
        }
        String idIn = '(';
        for (Id i : pkgIds) {
            idIn += '\'' + String.valueOf(i) + '\',';
        }
        idIn = idIn.removeEnd(',') + ')';
        try {
            for (Application_Package_Line_Item__c line : (List<Application_Package_Line_Item__c>) Database.query(
                    'SELECT Application_Package__c, Description__c, Amount__c,' +
                    ' Package_Option__r.Option__r.Name' +
                    ' FROM Application_Package_Line_Item__c' +
                    ' WHERE Application_Package__c IN ' + idIn +
                    ' AND Line_Type__c = \'Option\'' +
                    ' ORDER BY Application_Package__c, Sort_Order__c, Id',
                    System.AccessLevel.SYSTEM_MODE)) {
                if (line.Application_Package__c == null) {
                    continue;
                }
                List<OptionDisplay> rows = byPkg.get(line.Application_Package__c);
                if (rows == null) {
                    rows = new List<OptionDisplay>();
                    byPkg.put(line.Application_Package__c, rows);
                }
                String name = String.isNotBlank(line.Description__c)
                    ? line.Description__c
                    : (line.Package_Option__r != null && line.Package_Option__r.Option__r != null
                        && String.isNotBlank(line.Package_Option__r.Option__r.Name)
                        ? line.Package_Option__r.Option__r.Name : 'Option');
                rows.add(new OptionDisplay(name, line.Amount__c));
            }
        } catch (Exception e) {
            System.debug('QuotePDFExtension: optional option lines unavailable: ' + e.getMessage());
            byPkg.clear();
        }
        return byPkg;
    }
    
    /**
     * P4 [T]: load the persisted engine line set (SYSTEM_MODE — the P4
     * line-item fields carry no portal FLS yet, same mode the engine writes
     * use) and reduce it to per-package money. Only packages that actually
     * carry a line set enter the map; everything else keeps the legacy build.
     */
    private void loadStoredLineMoney() {
        if (applicationPackages == null || applicationPackages.isEmpty()) {
            return;
        }
        Set<Id> pkgIds = new Set<Id>();
        for (Application_Package__c p : applicationPackages) {
            pkgIds.add(p.Id);
        }
        String idIn = '(';
        for (Id i : pkgIds) {
            idIn += '\'' + String.valueOf(i) + '\',';
        }
        idIn = idIn.removeEnd(',') + ')';
        Map<Id, StoredLineMoney> totals = new Map<Id, StoredLineMoney>();
        try {
            for (Application_Package_Line_Item__c line : (List<Application_Package_Line_Item__c>) Database.query(
                    'SELECT Application_Package__c, Line_Type__c, Amount__c' +
                    ' FROM Application_Package_Line_Item__c' +
                    ' WHERE Application_Package__c IN ' + idIn +
                    ' ORDER BY Application_Package__c, Sort_Order__c, Id',
                    System.AccessLevel.SYSTEM_MODE)) {
                if (line.Application_Package__c == null || line.Amount__c == null) {
                    continue;
                }
                StoredLineMoney m = totals.get(line.Application_Package__c);
                if (m == null) {
                    m = new StoredLineMoney();
                    m.noTaxTotal = 0;
                    m.taxTotal = 0;
                    totals.put(line.Application_Package__c, m);
                }
                if ('Tax'.equals(line.Line_Type__c)) {
                    m.taxTotal = money(m.taxTotal + line.Amount__c);
                } else {
                    m.noTaxTotal = money(m.noTaxTotal + line.Amount__c);
                }
                m.hasLines = true;
            }
        } catch (Exception e) {
            System.debug('QuotePDFExtension: stored line money unavailable: ' + e.getMessage());
            totals.clear();
        }
        storedLineMoneyByPkg = totals;
    }

    private static Decimal money(Decimal value) {
        return value == null ? 0 : value.setScale(2, System.RoundingMode.HALF_UP);
    }

    private Decimal wrapperTaxAmount(PackageWrapper wrapper) {
        if (wrapper.hasStoredLineMoney == true) {
            return wrapper.storedTaxTotal != null ? wrapper.storedTaxTotal : 0;
        }
        return wrapper.pkg.Tax_Amount__c != null ? wrapper.pkg.Tax_Amount__c : 0;
    }

    public Decimal taxTotal {
        get {
            Decimal total = 0;
            if (packageWrappersList != null) {
                for (PackageWrapper wrapper : packageWrappersList) {
                    total += wrapperTaxAmount(wrapper);
                }
            }
            return total;
        }
        private set;
    }
    public Decimal grandTotal { 
        get {
            if (grandTotal == null) {
            grandTotal = 0;
                for (PackageWrapper wrapper : packageWrappersList) {
                    grandTotal += wrapper.retailPriceTotal;
                    grandTotal += wrapperTaxAmount(wrapper);
                }
            }
            return grandTotal;
        }
        private set; 
    }
}