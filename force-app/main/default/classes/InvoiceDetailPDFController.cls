public without sharing class InvoiceDetailPDFController {

    public Invoice__c      invoice      { get; set; }
    public Application__c  application  { get; set; }
    public String          dealerName   { get; set; }
    public String          billTo       { get; set; }
    public List<PackageRow>   packages  { get; set; }
    public Decimal         grandTotal   { get; set; }

    // ── Display getters (mirror invoiceDetailView LWC) ────────────────────────
    public String  invoiceDate       { get; set; }   // 'MMM dd, yyyy' (LWC controller)
    public String  dueDate           { get; set; }   // ISO yyyy-MM-dd — exact LWC quirk (String.valueOf)
    public String  statusStyle       { get; set; }   // inline style matching LWC status classes
    public String  applicationId     { get; set; }   // Application.Name (REF)
    public String  customerFullName  { get; set; }   // First + Last, trimmed
    public String  vehicleInfo       { get; set; }   // Year/Make/Model joined '/'
    public String  vin               { get; set; }
    public String  odometerUnit      { get; set; }   // default 'KM' (LWC)
    public Boolean hasDealerName     { get; set; }
    public Boolean hasBillTo         { get; set; }
    public Decimal subTotal          { get; set; }   // Σ Contract_Cost_Price_Without_Tax__c
    public Decimal taxTotal          { get; set; }   // Σ base × taxPercentage/100 (hasTax only)
    public Decimal blendedTaxRate    { get; set; }   // taxTotal/subTotal×100, 2dp; null when subTotal=0
    public Decimal balanceAmount     { get; set; }   // Total_Balance_Amount__c, fallback grandTotal

    /**
     * Returns the dealer cost price (base + tax) for an Application Package.
     * Matches the invoice detail page which shows base pricing, not retail.
     */
    private static Decimal getDisplayPrice(Application_Package__c pkg) {
        return pkg.Contract_Cost_Price__c != null ? pkg.Contract_Cost_Price__c : 0;
    }

    /**
     * P4 [F] close-out (create-time flow retirement): engine-priced
     * Application_Package records carry NO master Package__c / Package_Term__c
     * links (the create-time flow that wrote them is retired), so the invoice
     * PDF's ITEM column and TERM column would render blank on engine records.
     * Resolve the display through the dealer copy links the engine path DOES
     * carry (Dealer_Package__c / Dealer_Package_Term__c -> their masters, then
     * the copy names), master-first so the legacy path stays byte-identical —
     * the same re-point QuotePDFExtension/ApplicationPDFExtension received in
     * the p4-t2 follow-up. Money (PackageRow.lineTotal / grandTotal) comes from
     * the stored price fields and the invoice line items — untouched by this
     * display re-point.
     */
    private static String resolvePackageName(Application_Package__c pkg) {
        if (pkg.Package__r != null && String.isNotBlank(pkg.Package__r.Name)) {
            return pkg.Package__r.Name;
        }
        if (pkg.Dealer_Package__r != null && pkg.Dealer_Package__r.Package__r != null
                && String.isNotBlank(pkg.Dealer_Package__r.Package__r.Name)) {
            return pkg.Dealer_Package__r.Package__r.Name;
        }
        if (pkg.Dealer_Package__r != null && String.isNotBlank(pkg.Dealer_Package__r.Name)) {
            return pkg.Dealer_Package__r.Name;
        }
        return '';
    }

    private static String resolveTermName(Application_Package__c pkg) {
        if (pkg.Package_Term__r != null && String.isNotBlank(pkg.Package_Term__r.Name)) {
            return pkg.Package_Term__r.Name;
        }
        if (pkg.Dealer_Package_Term__r != null && pkg.Dealer_Package_Term__r.Package_Term__r != null
                && String.isNotBlank(pkg.Dealer_Package_Term__r.Package_Term__r.Name)) {
            return pkg.Dealer_Package_Term__r.Package_Term__r.Name;
        }
        if (pkg.Dealer_Package_Term__r != null && String.isNotBlank(pkg.Dealer_Package_Term__r.Name)) {
            return pkg.Dealer_Package_Term__r.Name;
        }
        return '';
    }

    /**
     * Inline style for the STATUS meta value — mirrors the LWC status classes:
     *   Paid #5cb85c / Partial Paid #f0ad4e / Due #d9534f / Planned #5bc0de /
     *   Cancelled #999 + line-through / default #999
     */
    private static String buildStatusStyle(String status) {
        if (status == 'Paid')         return 'color:#5cb85c; font-weight:700;';
        if (status == 'Partial Paid') return 'color:#f0ad4e; font-weight:700;';
        if (status == 'Due')          return 'color:#d9534f; font-weight:700;';
        if (status == 'Planned')      return 'color:#5bc0de; font-weight:700;';
        if (status == 'Cancelled')    return 'color:#999; font-weight:700; text-decoration:line-through;';
        return 'color:#999; font-weight:700;';
    }

    /**
     * Bill To fallback built from the dealer Account billing fields.
     * Identical to InvoiceDetailViewController (bill-to fallback chain).
     */
    private static String buildBillToFromAccount(Account dlr) {
        List<String> addrParts = new List<String>();
        if (String.isNotBlank(dlr.BillingStreet))     addrParts.add(dlr.BillingStreet);
        String cityLine = '';
        if (String.isNotBlank(dlr.BillingCity))       cityLine += dlr.BillingCity;
        if (String.isNotBlank(dlr.BillingState))      cityLine += (String.isNotBlank(cityLine) ? ' ' : '') + dlr.BillingState;
        if (String.isNotBlank(dlr.BillingPostalCode)) cityLine += (String.isNotBlank(cityLine) ? ' ' : '') + dlr.BillingPostalCode;
        if (String.isNotBlank(cityLine))               addrParts.add(cityLine);
        if (String.isNotBlank(dlr.BillingCountry))    addrParts.add(dlr.BillingCountry);
        if (String.isNotBlank(dlr.Phone))              addrParts.add('Tel: ' + dlr.Phone);
        if (String.isNotBlank(dlr.Email__c))           addrParts.add('E-mail: ' + dlr.Email__c);
        return addrParts.isEmpty() ? null : String.join(addrParts, '<br/>');
    }

    public InvoiceDetailPDFController() {
        packages   = new List<PackageRow>();
        grandTotal = 0;
        subTotal   = 0;
        taxTotal   = 0;
        hasDealerName = false;
        hasBillTo     = false;

        String invoiceId = ApexPages.currentPage().getParameters().get('id');
        if (String.isBlank(invoiceId)) return;

        // ── 1. Invoice + Application + Bill To ───────────────────────────────
        List<Invoice__c> invoices = [
            SELECT Id, Name, Status__c, CreatedDate,
                   Invoice_Due_Date__c, Total_Balance_Amount__c,
                   Application__c,
                   Application__r.Name,
                   Application__r.Dealer_Name__c,
                   Application__r.Customer_First_Name__c,
                   Application__r.Customer_Last_Name__c,
                   Application__r.Customer_Address__c,
                   Application__r.Vehicle_VIN__c,
                   Application__r.Vehicle_Year__c,
                   Application__r.Vehicle_Make__c,
                   Application__r.Vehicle_Model__c,
                   Application__r.Odometer__c,
                   Application__r.Odometer_Unit__c,
                   Remittance_Form__r.Bill_To__c,
                   Remittance_Form__r.Dealer_Name__c,
                   Remittance_Form__r.Dealer_Name__r.Name,
                   Application__r.Dealer_Name__r.Name,
                   Application__r.Dealer_Name__r.BillingStreet,
                   Application__r.Dealer_Name__r.BillingCity,
                   Application__r.Dealer_Name__r.BillingState,
                   Application__r.Dealer_Name__r.BillingPostalCode,
                   Application__r.Dealer_Name__r.BillingCountry,
                   Application__r.Dealer_Name__r.Phone,
                   Application__r.Dealer_Name__r.Email__c
            FROM Invoice__c
            WHERE Id = :invoiceId
            LIMIT 1
        ];
        if (invoices.isEmpty()) return;

        invoice     = invoices[0];
        application = invoice.Application__r;

        // ── 1b. Display fields (LWC parity) ──────────────────────────────────
        invoiceDate = invoice.CreatedDate != null
            ? invoice.CreatedDate.format('MMM dd, yyyy')
            : null;
        dueDate     = invoice.Invoice_Due_Date__c != null
            ? String.valueOf(invoice.Invoice_Due_Date__c)
            : null;
        statusStyle = buildStatusStyle(invoice.Status__c);

        if (invoice.Application__c != null && invoice.Application__r != null) {
            applicationId = invoice.Application__r.Name;
            String fn = invoice.Application__r.Customer_First_Name__c != null
                ? invoice.Application__r.Customer_First_Name__c : '';
            String ln = invoice.Application__r.Customer_Last_Name__c != null
                ? invoice.Application__r.Customer_Last_Name__c : '';
            customerFullName = (fn + ' ' + ln).trim();
            vin = invoice.Application__r.Vehicle_VIN__c;

            List<String> vParts = new List<String>();
            if (invoice.Application__r.Vehicle_Year__c  != null)            vParts.add(String.valueOf(invoice.Application__r.Vehicle_Year__c));
            if (String.isNotBlank(invoice.Application__r.Vehicle_Make__c))  vParts.add(invoice.Application__r.Vehicle_Make__c);
            if (String.isNotBlank(invoice.Application__r.Vehicle_Model__c)) vParts.add(invoice.Application__r.Vehicle_Model__c);
            vehicleInfo = String.join(vParts, '/');

            odometerUnit = invoice.Application__r.Odometer_Unit__c != null
                ? invoice.Application__r.Odometer_Unit__c : 'KM';
        }

        // ── 1c. Dealer name: prefer Remittance Form dealer, fall back to Application dealer ──
        if (invoice.Remittance_Form__c != null && invoice.Remittance_Form__r != null
                && invoice.Remittance_Form__r.Dealer_Name__c != null
                && invoice.Remittance_Form__r.Dealer_Name__r != null) {
            dealerName = invoice.Remittance_Form__r.Dealer_Name__r.Name;
        }
        if (dealerName == null && invoice.Application__c != null && invoice.Application__r != null
                && invoice.Application__r.Dealer_Name__c != null
                && invoice.Application__r.Dealer_Name__r != null) {
            dealerName = invoice.Application__r.Dealer_Name__r.Name;
        }
        hasDealerName = String.isNotBlank(dealerName);

        // ── 1d. Bill To: prefer Remittance Form rich text, fall back to dealer Account fields ──
        if (invoice.Remittance_Form__c != null && invoice.Remittance_Form__r != null
                && invoice.Remittance_Form__r.Bill_To__c != null) {
            billTo = invoice.Remittance_Form__r.Bill_To__c;
        }
        if (billTo == null && invoice.Application__c != null && invoice.Application__r != null
                && invoice.Application__r.Dealer_Name__c != null
                && invoice.Application__r.Dealer_Name__r != null) {
            billTo = buildBillToFromAccount(invoice.Application__r.Dealer_Name__r);
        }
        hasBillTo = String.isNotBlank(billTo);

        // ── 2. Line items grouped by package ─────────────────────────────────
        List<Invoice_Line_Item__c> lineItems = [
            SELECT Id, Application_Package__c, Contract_Cost_Price__c,
                   Tax_Amount__c, Status__c
            FROM Invoice_Line_Item__c
            WHERE Invoice__c = :invoiceId
            ORDER BY Application_Package_Name__c ASC
            LIMIT 1000
        ];

        Map<Id, List<Invoice_Line_Item__c>> pkgMap = new Map<Id, List<Invoice_Line_Item__c>>();
        Set<Id> packageIds = new Set<Id>();
        for (Invoice_Line_Item__c li : lineItems) {
            if (li.Application_Package__c != null) {
                packageIds.add(li.Application_Package__c);
                if (!pkgMap.containsKey(li.Application_Package__c))
                    pkgMap.put(li.Application_Package__c, new List<Invoice_Line_Item__c>());
                pkgMap.get(li.Application_Package__c).add(li);
            }
        }

        // ── 2b. Query Option LINE ITEMS for add-on rows (P4 [S]: option state
        // lives on the package's priced Option lines — the engine snapshot
        // contract; Application_Package_Option__c children are retired). The
        // line carries the priced retail (Amount__c); the cost side (the
        // invoice shows cost prices) is re-derived from the dealer-option
        // mirror — the same Net_Cost formula the legacy child copied.
        Map<Id, List<OptionWrapper>> pkgToOptions = new Map<Id, List<OptionWrapper>>();
        try {
            if (!packageIds.isEmpty()) {
                Map<Id, Id> dealerPkgByPkg = new Map<Id, Id>();
                for (Application_Package__c p : [
                    SELECT Id, Dealer_Package__c, Dealer_Package_Term__r.Dealer_Package__c
                    FROM Application_Package__c WHERE Id IN :packageIds
                ]) {
                    Id dpId = (p.Dealer_Package_Term__r != null && p.Dealer_Package_Term__r.Dealer_Package__c != null)
                        ? p.Dealer_Package_Term__r.Dealer_Package__c : p.Dealer_Package__c;
                    if (dpId != null) {
                        dealerPkgByPkg.put(p.Id, dpId);
                    }
                }
                Map<Id, Dealer_Package_Option__c> mirrorByMaster = new Map<Id, Dealer_Package_Option__c>();
                Set<Id> dealerPkgIds = new Set<Id>(dealerPkgByPkg.values());
                if (!dealerPkgIds.isEmpty()) {
                    for (Dealer_Package_Option__c dpo : [
                        SELECT Id, Package_Option__c, Net_Cost__c
                        FROM Dealer_Package_Option__c
                        WHERE Dealer_Package__c IN :dealerPkgIds
                          AND Package_Option__c != null
                          AND Net_Cost__c != null AND Net_Cost__c != 0
                    ]) {
                        if (!mirrorByMaster.containsKey(dpo.Package_Option__c)) {
                            mirrorByMaster.put(dpo.Package_Option__c, dpo);
                        }
                    }
                }
                for (Application_Package_Line_Item__c line : (List<Application_Package_Line_Item__c>) Database.queryWithBinds(
                        'SELECT Application_Package__c, Description__c, Amount__c, Package_Option__c' +
                        ' FROM Application_Package_Line_Item__c' +
                        ' WHERE Application_Package__c IN :packageIds' +
                        ' AND Line_Type__c = \'Option\'' +
                        ' ORDER BY Package_Option__c, Id',
                        new Map<String, Object>{ 'packageIds' => packageIds },
                        System.AccessLevel.SYSTEM_MODE)) {
                    if (line.Application_Package__c == null) {
                        continue;
                    }
                    List<OptionWrapper> rows = pkgToOptions.get(line.Application_Package__c);
                    if (rows == null) {
                        rows = new List<OptionWrapper>();
                        pkgToOptions.put(line.Application_Package__c, rows);
                    }
                    OptionWrapper ow = new OptionWrapper();
                    Dealer_Package_Option__c mirror = line.Package_Option__c != null
                        ? mirrorByMaster.get(line.Package_Option__c) : null;
                    ow.optionName    = String.isNotBlank(line.Description__c)
                        ? line.Description__c : 'Additional Option';
                    ow.costPrice     = mirror != null && mirror.Net_Cost__c != null
                        ? mirror.Net_Cost__c : (line.Amount__c != null ? line.Amount__c : 0);
                    ow.selectionType = 'Optional';
                    rows.add(ow);
                }
            }
        } catch (Exception e) {
            // Silently continue without options if query fails (e.g., FLS issue in community context)
            System.debug(LoggingLevel.WARN, 'PDF: Failed to query option lines: ' + e.getMessage());
        }

        // ── 3. Packages scoped to the invoice's line items (LWC parity) ───────
        Map<Id, Decimal> pkgDisplayPrice = new Map<Id, Decimal>();
        if (!packageIds.isEmpty()) {
            List<Application_Package__c> appPkgs = [
                SELECT Id, Package__r.Name, Package_Term__r.Name,
                       Dealer_Package__c, Dealer_Package__r.Name,
                       Dealer_Package__r.Package__r.Name,
                       Dealer_Package_Term__c, Dealer_Package_Term__r.Name,
                       Dealer_Package_Term__r.Package_Term__r.Name,
                       Odometer_Start__c, Odometer_End__c,
                       Contract_Start_Date__c, Contract_End_Date__c,
                       RecordType.Name,
                       Contract_Cost_Price__c,
                       Contract_Cost_Price_Without_Tax__c,
                       Contract_Premium_Price__c,
                       Contract_Premium_Price_Without_Tax__c,
                       Tax_Amount__c,
                       Dealer_Price_Override__c,
                       Tax_Percentage__c,
                       Dealer_Package_Price__c,
                       Add_Ons_Price__c,
                       Premium_Model_Fee__c
                FROM Application_Package__c
                WHERE Id IN :packageIds
                LIMIT 1000
            ];

            for (Application_Package__c pkg : appPkgs) {
                pkgDisplayPrice.put(pkg.Id, getDisplayPrice(pkg));
            }

            for (Application_Package__c pkg : appPkgs) {
                PackageRow row    = new PackageRow();
                row.pkg           = pkg;
                row.packageName   = resolvePackageName(pkg);
                row.lineItems     = new List<LineItemWrapper>();
                row.packageTotal  = 0;
                row.baseCostPrice = pkg.Dealer_Package_Price__c != null ? pkg.Dealer_Package_Price__c : 0;
                row.addOnsTotal   = pkg.Add_Ons_Price__c != null ? pkg.Add_Ons_Price__c : 0;
                row.hasBreakdown  = row.addOnsTotal > 0;
                row.options       = pkgToOptions.containsKey(pkg.Id)
                    ? pkgToOptions.get(pkg.Id)
                    : new List<OptionWrapper>();

                // ── LWC line-item row fields ──
                row.premiumModelFee    = pkg.Premium_Model_Fee__c != null ? pkg.Premium_Model_Fee__c : 0;
                row.hasPremiumModelFee = row.premiumModelFee > 0;
                row.lineTotal          = row.baseCostPrice + row.addOnsTotal + row.premiumModelFee;
                row.termDisplay        = resolveTermName(pkg).replaceAll('\\bnull\\b', '0');

                // Tax breakdown
                row.basePriceWithoutTax = pkg.Contract_Cost_Price_Without_Tax__c != null ? pkg.Contract_Cost_Price_Without_Tax__c : 0;
                row.taxPercentage = pkg.Tax_Percentage__c != null ? pkg.Tax_Percentage__c : 0;
                Decimal costWithTax = pkg.Contract_Cost_Price__c != null ? pkg.Contract_Cost_Price__c : 0;
                row.taxAmount = costWithTax - row.basePriceWithoutTax;
                row.hasTax = row.taxPercentage > 0 || row.taxAmount > 0;

                if (pkgMap.containsKey(pkg.Id)) {
                    Decimal displayPrice = pkgDisplayPrice.get(pkg.Id);
                    for (Invoice_Line_Item__c li : pkgMap.get(pkg.Id)) {
                        LineItemWrapper liw = new LineItemWrapper();
                        liw.lineItem = li;
                        liw.displayPrice = displayPrice;
                        row.lineItems.add(liw);
                        row.packageTotal += displayPrice;
                    }
                }
                grandTotal += row.packageTotal;
                packages.add(row);

                // ── LWC totals accumulation ──
                subTotal += row.basePriceWithoutTax;
                if (row.hasTax && row.taxPercentage != null && row.basePriceWithoutTax != null) {
                    taxTotal += row.basePriceWithoutTax * (row.taxPercentage / 100);
                }
            }
        }

        // ── 3b. grandTotal parity: include line items with no package (LWC) ──
        for (Invoice_Line_Item__c li : lineItems) {
            if (li.Application_Package__c == null) {
                grandTotal += li.Contract_Cost_Price__c != null ? li.Contract_Cost_Price__c : 0;
            }
        }

        // ── 3c. Blended tax rate + balance (LWC parity) ──────────────────────
        blendedTaxRate = (subTotal != null && taxTotal != null && subTotal > 0)
            ? (taxTotal / subTotal * 100).setScale(2)
            : null;
        balanceAmount = invoice.Total_Balance_Amount__c != null
            ? invoice.Total_Balance_Amount__c
            : grandTotal;
    }

    public class PackageRow {
        public Application_Package__c      pkg          { get; set; }
        public String                      packageName  { get; set; }
        public List<LineItemWrapper>        lineItems    { get; set; }
        public Decimal                     packageTotal { get; set; }
        public Decimal                     baseCostPrice { get; set; }
        public Decimal                     addOnsTotal   { get; set; }
        public Boolean                     hasBreakdown  { get; set; }
        public List<OptionWrapper>         options       { get; set; }
        // Tax breakdown fields
        public Decimal                     basePriceWithoutTax { get; set; }
        public Decimal                     taxPercentage       { get; set; }
        public Decimal                     taxAmount           { get; set; }
        public Boolean                     hasTax              { get; set; }
        // LWC line-item row fields
        public Decimal                     premiumModelFee     { get; set; }
        public Boolean                     hasPremiumModelFee  { get; set; }
        public Decimal                     lineTotal           { get; set; }
        public String                      termDisplay         { get; set; }
    }

    public class LineItemWrapper {
        public Invoice_Line_Item__c lineItem     { get; set; }
        public Decimal              displayPrice { get; set; }
    }

    public class OptionWrapper {
        public String  optionName    { get; set; }
        public Decimal costPrice     { get; set; }
        public String  selectionType { get; set; }
    }
}