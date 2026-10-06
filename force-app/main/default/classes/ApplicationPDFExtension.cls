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

    /**
     * Lubrico-contract PDF support: printed-on date rendered in the running
     * footer ("Printed on: <date>"), and the application's vehicle purchase
     * price used as the contract liability limit ("Total liability equals the
     * purchase price of the vehicle before taxes").
     */
    public String printedOn {
        get {
            Date t = Date.today();
            return DateTime.newInstance(t.year(), t.month(), t.day()).format('MMM d, yyyy');
        }
    }
    private Decimal applicationVehiclePurchasePrice;

    public List<Application_Package__c> applicationPackages { get; private set; }
    private Map<Id, String>  packageLogoUrls;
    private Map<Id, Boolean> packageHasLogo;

    /**
     * P4 [S]: one optional add-on rendered on the application PDFs / summary
     * package data. Plain display values (no SObject) sourced from the
     * package's priced Option LINE ITEMS (Line_Type__c = 'Option' — the
     * engine snapshot contract the S5 option writers create on add;
     * Application_Package_Option__c children are retired). A package with no
     * Option lines carries no optional options.
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
     * §07.3): per-package totals reduced from the persisted engine line set so
     * these PDFs render the stored snapshot for engine-priced packages
     * (rendered* keys on PackageWrapper) — contract PDF, portal and invoice
     * agree on mixed-fee deals. Packages without a line set keep the
     * stored/formula fields byte-for-byte (flag-off state unchanged).
     */
    public class StoredLineMoney {
        public Boolean hasLines   { get; set; }
        public Decimal noTaxTotal { get; set; }
        public Decimal taxTotal   { get; set; }
    }
    private Map<Id, StoredLineMoney> storedLineMoneyByPkg = new Map<Id, StoredLineMoney>();

    /**
     * P4 flip [T]-follow-up + P4 [S]: Included-option NAME list for the
     * application PDFs / summary package data. The legacy create-time flow
     * copies the dealer package's Included Dealer_Package_Option__c rows into
     * Application_Package_Option__c children; those children are RETIRED in
     * P4 [S] (object deleted org-side), so the name list renders from the
     * dealer mirror directly — the SAME rows the flow copied from — on every
     * shape: for each package this map holds the NAMES of the dealer
     * package's Included Dealer_Package_Option__c rows (via the master Option
     * each points at — the identical text APO.Option__c's formula rendered
     * for legacy children). Packages without a resolvable dealer package (no
     * Dealer_Package__c / Dealer_Package_Term__c chain) render no names —
     * the same empty state such records show today (children only ever came
     * from those dealer rows).
     */
    private Map<Id, List<String>> dealerIncludedOptionNamesByPkg =
        new Map<Id, List<String>>();

    /** Engine shape = an engine-priced package carrying its persisted line set. */
    private Boolean isEngineSnapshotShape(Application_Package__c pkg) {
        StoredLineMoney m = storedLineMoneyByPkg.get(pkg.Id);
        return m != null && m.hasLines == true;
    }

    /**
     * P4 flip [T]-follow-up + P4 [S]: load the Included Dealer_Package_Option__c
     * row NAMES per package (the rows the legacy create-time flow copies into
     * APO children — flow filter: Dealer_Package__c = the term's dealer
     * package, Selection_Type = Included). Display-only: never DMLs. Names
     * come from the master Option reachable via the dealer option's
     * Package_Option__c master (the same text APO.Option__c's formula
     * rendered for legacy children).
     */
    private void loadDealerIncludedOptionNames() {
        if (applicationPackages == null || applicationPackages.isEmpty()) {
            return;
        }
        Map<Id, Id> dealerPackageIdByPkg = new Map<Id, Id>();
        for (Application_Package__c p : applicationPackages) {
            Id dpId = (p.Dealer_Package_Term__r != null && p.Dealer_Package_Term__r.Dealer_Package__c != null)
                ? p.Dealer_Package_Term__r.Dealer_Package__c
                : p.Dealer_Package__c;
            if (dpId != null) {
                dealerPackageIdByPkg.put(p.Id, dpId);
            }
        }
        if (dealerPackageIdByPkg.isEmpty()) {
            return;
        }
        try {
            Map<Id, List<String>> namesByDp = new Map<Id, List<String>>();
            for (Dealer_Package_Option__c dpo : [
                SELECT Id, Dealer_Package__c,
                       Package_Option__r.Option__r.Name
                FROM Dealer_Package_Option__c
                WHERE Dealer_Package__c IN :dealerPackageIdByPkg.values()
                  AND Selection_Type__c = 'Included'
                ORDER BY Id
            ]) {
                if (dpo.Dealer_Package__c == null
                        || dpo.Package_Option__r == null
                        || dpo.Package_Option__r.Option__r == null
                        || String.isBlank(dpo.Package_Option__r.Option__r.Name)) {
                    continue;
                }
                List<String> names = namesByDp.get(dpo.Dealer_Package__c);
                if (names == null) {
                    names = new List<String>();
                    namesByDp.put(dpo.Dealer_Package__c, names);
                }
                names.add(dpo.Package_Option__r.Option__r.Name);
            }
            for (Id pkgId : dealerPackageIdByPkg.keySet()) {
                Id dpId = dealerPackageIdByPkg.get(pkgId);
                if (namesByDp.containsKey(dpId)) {
                    dealerIncludedOptionNamesByPkg.put(pkgId, namesByDp.get(dpId));
                }
            }
        } catch (Exception e) {
            System.debug('ApplicationPDFExtension: dealer included option names unavailable: ' + e.getMessage());
            dealerIncludedOptionNamesByPkg.clear();
        }
    }

    /**
     * P4 [T]: load the persisted engine line set (SYSTEM_MODE — the P4
     * line-item fields carry no portal FLS yet) and reduce it to per-package
     * money; packages without lines never enter the map.
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
            System.debug('ApplicationPDFExtension: stored line money unavailable: ' + e.getMessage());
            totals.clear();
        }
        storedLineMoneyByPkg = totals;
    }

    private static Decimal money(Decimal value) {
        return value == null ? 0 : value.setScale(2, System.RoundingMode.HALF_UP);
    }

    /**
     * P4 [S]: the application PDFs / summary package-data optional add-ons
     * come from the package's priced Option LINE ITEMS (the engine snapshot
     * contract — the S5 option writers create these on add with Amount = the
     * priced retail, Description = the option name). Packages without Option
     * lines carry no optional options. SYSTEM_MODE read: the P4 line-item
     * fields carry no portal FLS yet (the same mode the engine writes and
     * every line reader uses).
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
            System.debug('ApplicationPDFExtension: optional option lines unavailable: ' + e.getMessage());
            byPkg.clear();
        }
        return byPkg;
    }

    public class PackageWrapper {
        public Application_Package__c              pkg              { get; set; }
        // P4 flip [T]-follow-up + P4 [S]: rendered "Additional Options" name
        // list — the names of the dealer package's Included
        // Dealer_Package_Option__c rows (the rows the legacy create-time flow
        // copied into APO children; the children are retired in P4 [S]).
        public List<String>                       includedOptionNames { get; set; }
        // P4 [S]: optional add-ons with their priced retail, read from the
        // package's Option LINE ITEMS (see OptionDisplay).
        public List<OptionDisplay>                optionalOptions  { get; set; }
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
        // Lubrico-contract PDF display bindings (pre-formatted, null-safe).
        // Populated in the constructor loop from the real record data so the
        // page markup stays presentation-only.
        public String                              contractStartDateDisplay { get; set; }
        public String                              contractEndDateDisplay   { get; set; }
        public String                              odometerStartDisplay     { get; set; }
        public String                              odometerEndDisplay       { get; set; }
        public String                              mileageDisplay           { get; set; }
        public String                              deductibleDisplay        { get; set; }
        public String                              perClaimLimitDisplay     { get; set; }
        public String                              liabilityDisplay         { get; set; }
        public String                              premiumWithoutTaxDisplay { get; set; }
        public String                              taxDisplay               { get; set; }
        public String                              totalPremiumDisplay      { get; set; }
        // P4 [T]: when true the package carries a persisted engine line set and
        // the rendered* money keys below come from the stored lines (§07.3
        // rebuild — sum(non-Tax lines), sum(Tax lines), sum(all)); otherwise
        // they fall back to the stored/formula fields (legacy byte-identical).
        public Boolean                             hasStoredLineMoney { get; set; }
        public Decimal                             storedNoTaxTotal   { get; set; }
        public Decimal                             storedTaxTotal     { get; set; }
        public Decimal renderedContractPremiumWithoutTax {
            get { return hasStoredLineMoney == true ? storedNoTaxTotal : pkg.Contract_Premium_Price_Without_Tax__c; }
        }
        public Decimal renderedTaxAmount {
            get { return hasStoredLineMoney == true ? storedTaxTotal : pkg.Tax_Amount__c; }
        }
        public Decimal renderedContractPremium {
            get {
                return hasStoredLineMoney == true
                    ? (storedNoTaxTotal == null ? 0 : storedNoTaxTotal)
                        + (storedTaxTotal == null ? 0 : storedTaxTotal)
                    : pkg.Contract_Premium_Price__c;
            }
        }
        // P4 flip [T]-follow-up: master-first plan/term display for the
        // CarLoanProtection page merges. Legacy master-linked records render
        // the master names exactly as before; engine-priced records (no master
        // links — the create-time flow that wrote them is engine-guarded off)
        // resolve through the dealer copy links the engine path carries, so
        // the PDF term/plan never render blank/'N/A' on engine quotes.
        public String renderedPlanName {
            get {
                if (pkg.Package__r != null && String.isNotBlank(pkg.Package__r.Name)) {
                    return pkg.Package__r.Name;
                }
                if (pkg.Dealer_Package__r != null && pkg.Dealer_Package__r.Package__r != null
                        && String.isNotBlank(pkg.Dealer_Package__r.Package__r.Name)) {
                    return pkg.Dealer_Package__r.Package__r.Name;
                }
                return planName;
            }
        }
        public String renderedTermName {
            get {
                if (pkg.Package_Term__r != null && String.isNotBlank(pkg.Package_Term__r.Name)) {
                    return pkg.Package_Term__r.Name;
                }
                if (pkg.Dealer_Package_Term__r != null && pkg.Dealer_Package_Term__r.Package_Term__r != null
                        && String.isNotBlank(pkg.Dealer_Package_Term__r.Package_Term__r.Name)) {
                    return pkg.Dealer_Package_Term__r.Package_Term__r.Name;
                }
                return termName;
            }
        }
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

        packageLogoUrls        = new Map<Id, String>();
        packageHasLogo         = new Map<Id, Boolean>();
        recordTypeWrappers     = new Map<String, RecordTypeWrapper>();
        recordTypeWrappersList = new List<RecordTypeWrapper>();

        getLatestPackagesFromEachRecordType();
        getPackageLogos();
        loadStoredLineMoney();
        loadDealerIncludedOptionNames();
        // P4 [S]: optional add-on display state — priced Option line items of
        // the package (the engine snapshot contract); APO children retired.
        Map<Id, List<OptionDisplay>> optionalOptionDisplaysByPkg = loadOptionalOptionDisplays();

        // Pre-load T&C for all packages
        Map<Id, String> termsMap = loadTermsAndConditions();

        for (Application_Package__c pkg : applicationPackages) {
            PackageWrapper wrapper  = new PackageWrapper();
            wrapper.pkg             = pkg;
            // P4 [S]: Included-option names render from the dealer mirror (the
            // rows the legacy create-time flow copied into the now-retired APO
            // children) on every shape — no children exist org-side.
            wrapper.includedOptionNames = dealerIncludedOptionNamesByPkg.containsKey(pkg.Id)
                ? dealerIncludedOptionNamesByPkg.get(pkg.Id) : new List<String>();
            wrapper.optionalOptions = optionalOptionDisplaysByPkg.containsKey(pkg.Id)
                ? optionalOptionDisplaysByPkg.get(pkg.Id) : new List<OptionDisplay>();
            wrapper.packageLogoUrl  = packageLogoUrls.get(pkg.Id);
            wrapper.hasPackageLogo  = packageHasLogo.containsKey(pkg.Id) ? packageHasLogo.get(pkg.Id) : false;

            // Display name: prefer the dealer-selected package, fall back to the master package
            wrapper.planName = (pkg.Dealer_Package__r != null && pkg.Dealer_Package__r.Name != null)
                ? pkg.Dealer_Package__r.Name
                : ((pkg.Package__r != null && pkg.Package__r.Name != null)
                    ? pkg.Package__r.Name : '');
            // Display name: prefer the dealer-selected term, fall back to the master term
            wrapper.termName = (pkg.Dealer_Package_Term__r != null && pkg.Dealer_Package_Term__r.Name != null)
                ? pkg.Dealer_Package_Term__r.Name
                : ((pkg.Package_Term__r != null && pkg.Package_Term__r.Name != null)
                    ? pkg.Package_Term__r.Name : '');

            if (pkg.Contract_Start_Date__c != null) {
                wrapper.contractStartDate = ((DateTime) pkg.Contract_Start_Date__c).format('yyyy-MM-dd');
            }
            if (pkg.Contract_End_Date__c != null) {
                wrapper.contractEndDate   = ((DateTime) pkg.Contract_End_Date__c).format('yyyy-MM-dd');
            }

            // T&C resolution
            wrapper.termsAndConditions = termsMap.containsKey(pkg.Id) ? termsMap.get(pkg.Id) : '';
            wrapper.hasTermsAndConditions = String.isNotBlank(wrapper.termsAndConditions);

            // P4 [T]: engine-priced package with a persisted line set — the
            // rendered* money keys (the fields the PDF pages merge) rebuild
            // from the stored lines (§07.3); otherwise legacy fields stand.
            StoredLineMoney lineMoney = storedLineMoneyByPkg.get(pkg.Id);
            if (lineMoney != null && lineMoney.hasLines) {
                wrapper.hasStoredLineMoney = true;
                wrapper.storedNoTaxTotal = lineMoney.noTaxTotal;
                wrapper.storedTaxTotal = lineMoney.taxTotal;
            }

            // --- Lubrico-contract PDF display bindings (real record data) ---
            wrapper.contractStartDateDisplay = formatDateLong(pkg.Contract_Start_Date__c);
            wrapper.contractEndDateDisplay   = formatDateLong(pkg.Contract_End_Date__c);

            String startUnit = String.isNotBlank(pkg.Odometer_Start_Unit__c) ? pkg.Odometer_Start_Unit__c : 'KM';
            String endUnit   = String.isNotBlank(pkg.Odometer_End_Unit__c)   ? pkg.Odometer_End_Unit__c   : 'KM';
            wrapper.odometerStartDisplay = (pkg.Odometer_Start__c == null)
                ? '' : (groupNumber(pkg.Odometer_Start__c) + ' ' + startUnit);

            // Unlimited-KM substitution ported from the Summary tab: an
            // 'Unlimited' restriction displays "Unlimited" with the KM unit
            // instead of a blank odometer (matches the dealerPortalSummary rule).
            String restriction = resolveRestrictionType(pkg);
            if (restriction != null && restriction.equalsIgnoreCase('Unlimited')) {
                wrapper.odometerEndDisplay = 'Unlimited ' + endUnit;
            } else if (pkg.Odometer_End__c != null) {
                wrapper.odometerEndDisplay = groupNumber(pkg.Odometer_End__c) + ' ' + endUnit;
            } else {
                wrapper.odometerEndDisplay = '';
            }
            wrapper.mileageDisplay = wrapper.odometerEndDisplay;

            wrapper.deductibleDisplay    = formatMoney(resolveDeductible(pkg));
            wrapper.perClaimLimitDisplay = formatMoney(resolvePerClaimLimit(pkg));
            wrapper.liabilityDisplay     = formatMoney(applicationVehiclePurchasePrice);

            // Money display stays sourced from the rendered* keys so the
            // contract matches the portal and the invoice on mixed-fee deals.
            wrapper.premiumWithoutTaxDisplay = formatMoney(wrapper.renderedContractPremiumWithoutTax);
            wrapper.taxDisplay               = formatMoney(wrapper.renderedTaxAmount);
            wrapper.totalPremiumDisplay      = formatMoney(wrapper.renderedContractPremium);

            // Record type info
            String rt = resolveRecordTypeName(pkg);
            wrapper.recordTypeName = rt;
            wrapper.isTireRim = rt.containsIgnoreCase('Tire') && rt.containsIgnoreCase('Rim');

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

        // Filter by rt param if present. The rt key equals the package's real
        // record type (resolveRecordTypeName) — the SAME key the Summary PDF
        // button sends. If the key still does not resolve we keep ALL wrappers
        // rather than filtering to an empty list, so a call never renders a
        // blank PDF.
        PageReference currentPage = ApexPages.currentPage();
        if (currentPage != null) {
            String rtFilter = currentPage.getParameters().get('rt');
            if (!String.isBlank(rtFilter) && recordTypeWrappers.containsKey(rtFilter)) {
                recordTypeWrappersList = new List<RecordTypeWrapper>{ recordTypeWrappers.get(rtFilter) };
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
                       Vehicle_Purchase_Price__c,
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

            // Liability limit = the vehicle purchase price (before taxes).
            applicationVehiclePurchasePrice = app.Vehicle_Purchase_Price__c;

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
                } else if (isEngineSnapshotShape(appPkg)
                        && appPkg.Dealer_Package__r != null
                        && appPkg.Dealer_Package__r.Package__c != null) {
                    // P4 flip [T]-follow-up: engine-priced packages carry no
                    // master Package__c link (the create-time flow that wrote
                    // it is engine-guarded off) — resolve the T&C through the
                    // dealer copy's master link so the contract PDF shows the
                    // same dealer-override/default T&C the legacy path would.
                    packageIds.add(appPkg.Dealer_Package__r.Package__c);
                    appPkgToPackage.put(appPkg.Id, appPkg.Dealer_Package__r.Package__c);
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
                       RecordType.Name,
                       Package_Plan_Type__r.Name,
                       Package__r.Name,
                       Package__r.Id,
                       Dealer_Package__r.Name,
                       Package_Tier__r.Name,
                       Package_Term__r.Name,
                       Dealer_Package_Term__r.Name,
                       Dealer_Package__r.Package__r.Name,
                       Dealer_Package_Term__r.Package_Term__r.Name,
                       Dealer_Package_Term__r.Dealer_Package__c,
                       Coverage_Plan__c,
                       Package_Record_Type__c,
                       Disclaimer_Heading__c,
                       Disclaimer_Body__c,
                       Payment_Status__c,
                       Deductible__c,
                       Per_Claim_Limit__c,
                       Package_Term__r.Per_Claim_Limit__c,
                       Package_Term__r.Restriction_Type__c,
                       Dealer_Package__r.Per_Claim_Limit__c,
                       Dealer_Package__r.Deductable__c,
                       Dealer_Package_Term__r.Restriction_Type__c,
                       Dealer_Package_Term__r.Odometer_KM__c,
                       Dealer_Package_Term__r.Package_Term__r.Per_Claim_Limit__c,
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
                       CreatedDate
                FROM Application_Package__c
                WHERE Application__c = :application.Id
                  AND Active__c = true
                ORDER BY RecordTypeId, CreatedDate DESC
            ];

            applicationPackages = new List<Application_Package__c>();
            Set<String> seen = new Set<String>();
            for (Application_Package__c p : all) {
                // Group/dedupe on the package's REAL record type (fallback to
                // Package_Record_Type__c then 'Other') so the key matches what
                // the Summary PDF button sends and never lumps every engine
                // package under a single 'Other' bucket.
                String rt = resolveRecordTypeName(p);
                if (!seen.contains(rt)) {
                    applicationPackages.add(p);
                    seen.add(rt);
                }
            }
        } catch (Exception e) {
            applicationPackages = new List<Application_Package__c>();
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Lubrico-contract PDF helpers
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * The grouping/filter key for a package = its REAL record type name, with a
     * fallback so the key always equals what the Summary PDF button sends
     * (never a blank PDF):
     *   rt = blank(RecordType.Name)
     *          ? (blank(Package_Record_Type__c) ? 'Other' : Package_Record_Type__c)
     *          : RecordType.Name
     */
    private static String resolveRecordTypeName(Application_Package__c p) {
        String rtName = (p.RecordType != null) ? p.RecordType.Name : null;
        if (String.isNotBlank(rtName)) {
            return rtName;
        }
        return String.isBlank(p.Package_Record_Type__c) ? 'Other' : p.Package_Record_Type__c;
    }

    /** Restriction type from the dealer term, falling back to the master term. */
    private static String resolveRestrictionType(Application_Package__c p) {
        if (p.Dealer_Package_Term__r != null
                && String.isNotBlank(p.Dealer_Package_Term__r.Restriction_Type__c)) {
            return p.Dealer_Package_Term__r.Restriction_Type__c;
        }
        if (p.Package_Term__r != null && String.isNotBlank(p.Package_Term__r.Restriction_Type__c)) {
            return p.Package_Term__r.Restriction_Type__c;
        }
        return null;
    }

    /** Per-claim limit: package field, then master term, then the dealer links. */
    private static Decimal resolvePerClaimLimit(Application_Package__c p) {
        if (p.Per_Claim_Limit__c != null) {
            return p.Per_Claim_Limit__c;
        }
        if (p.Package_Term__r != null && p.Package_Term__r.Per_Claim_Limit__c != null) {
            return p.Package_Term__r.Per_Claim_Limit__c;
        }
        if (p.Dealer_Package_Term__r != null
                && p.Dealer_Package_Term__r.Package_Term__r != null
                && p.Dealer_Package_Term__r.Package_Term__r.Per_Claim_Limit__c != null) {
            return p.Dealer_Package_Term__r.Package_Term__r.Per_Claim_Limit__c;
        }
        if (p.Dealer_Package__r != null && p.Dealer_Package__r.Per_Claim_Limit__c != null) {
            return p.Dealer_Package__r.Per_Claim_Limit__c;
        }
        return null;
    }

    /** Deductible: package field, then the dealer package override (Deductable__c). */
    private static Decimal resolveDeductible(Application_Package__c p) {
        if (p.Deductible__c != null) {
            return p.Deductible__c;
        }
        if (p.Dealer_Package__r != null && p.Dealer_Package__r.Deductable__c != null) {
            return p.Dealer_Package__r.Deductable__c;
        }
        return null;
    }

    /** "MMM d, yyyy" (e.g. Jul 29, 2026); '' when null. */
    private static String formatDateLong(Date d) {
        if (d == null) {
            return '';
        }
        return DateTime.newInstance(d.year(), d.month(), d.day()).format('MMM d, yyyy');
    }

    /** "$1,234.56"; null renders as $0.00 (prototype shows $0 for empty). */
    private static String formatMoney(Decimal value) {
        if (value == null) {
            return '$0.00';
        }
        Decimal v = value.setScale(2, System.RoundingMode.HALF_UP);
        Boolean negative = v < 0;
        v = v.abs();
        String s = v.toPlainString();
        Integer dot = s.indexOf('.');
        String whole = (dot >= 0) ? s.substring(0, dot) : s;
        String cents = (dot >= 0) ? s.substring(dot + 1) : '00';
        if (cents.length() == 1) {
            cents += '0';
        } else if (cents.length() > 2) {
            cents = cents.substring(0, 2);
        }
        return (negative ? '-$' : '$') + groupDigits(whole) + '.' + cents;
    }

    /** "40,000" for a whole-number odometer reading. */
    private static String groupNumber(Decimal value) {
        if (value == null) {
            return '';
        }
        return groupDigits(value.setScale(0, System.RoundingMode.HALF_UP).toPlainString());
    }

    private static String groupDigits(String digits) {
        String out = '';
        Integer c = 0;
        for (Integer i = digits.length() - 1; i >= 0; i--) {
            out = digits.substring(i, i + 1) + out;
            c++;
            if (Math.mod(c, 3) == 0 && i > 0) {
                out = ',' + out;
            }
        }
        return out;
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

}