public without sharing class InvoiceDetailPDFController {

    public Invoice__c         invoice      { get; set; }
    public Application__c     application  { get; set; }
    public String             dealerName   { get; set; }
    public String             billTo       { get; set; }
    public List<PackageRow>   packages     { get; set; }
    public Decimal            grandTotal   { get; set; }

    /**
     * Returns the dealer cost price (base + tax) for an Application Package.
     * Matches the invoice detail page which shows base pricing, not retail.
     */
    private static Decimal getDisplayPrice(Application_Package__c pkg) {
        return pkg.Contract_Cost_Price__c != null ? pkg.Contract_Cost_Price__c : 0;
    }

    public InvoiceDetailPDFController() {
        packages   = new List<PackageRow>();
        grandTotal = 0;

        String invoiceId = ApexPages.currentPage().getParameters().get('id');
        if (String.isBlank(invoiceId)) return;

        // ── 1. Invoice + Application + Bill To ───────────────────────────────
        List<Invoice__c> invoices = [
            SELECT Id, Name, Status__c, CreatedDate,
                   Application__c,
                   Application__r.Name,
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
                   Remittance_Form__r.Dealer_Name__r.Name
            FROM Invoice__c
            WHERE Id = :invoiceId
            LIMIT 1
        ];
        if (invoices.isEmpty()) return;

        invoice     = invoices[0];
        application = invoice.Application__r;
        if (invoice.Remittance_Form__c != null) {
            if (invoice.Remittance_Form__r != null) {
                billTo = invoice.Remittance_Form__r.Bill_To__c;
                if (invoice.Remittance_Form__r.Dealer_Name__c != null && invoice.Remittance_Form__r.Dealer_Name__r != null) {
                    dealerName = invoice.Remittance_Form__r.Dealer_Name__r.Name;
                }
            }
        }

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

        // ── 2b. Query Application Package Options for breakdown ──────────────
        Map<Id, List<OptionWrapper>> pkgToOptions = new Map<Id, List<OptionWrapper>>();
        try {
            if (!packageIds.isEmpty()) {
                for (Application_Package_Option__c opt : [
                    SELECT Id, Application_Package__c, Option__c, Net_Cost__c, Selection_Type__c
                    FROM Application_Package_Option__c
                    WHERE Application_Package__c IN :packageIds
                    AND Net_Cost__c != null AND Net_Cost__c != 0
                    ORDER BY Option__c ASC
                ]) {
                    if (!pkgToOptions.containsKey(opt.Application_Package__c)) {
                        pkgToOptions.put(opt.Application_Package__c, new List<OptionWrapper>());
                    }
                    OptionWrapper ow = new OptionWrapper();
                    ow.optionName = opt.Option__c;
                    ow.costPrice  = opt.Net_Cost__c != null ? opt.Net_Cost__c : 0;
                    pkgToOptions.get(opt.Application_Package__c).add(ow);
                }
            }
        } catch (Exception e) {
            // Silently continue without options if query fails (e.g., FLS issue in community context)
            System.debug(LoggingLevel.WARN, 'PDF: Failed to query package options: ' + e.getMessage());
        }

        // ── 3. Packages with retail/custom pricing fields ─────────────────────
        if (invoice.Application__c != null) {
            List<Application_Package__c> appPkgs = [
                SELECT Id, Package__r.Name, Package_Term__r.Name,
                       Odometer_Start__c, Odometer_End__c,
                       Contract_Start_Date__c, Contract_End_Date__c,
                       RecordType.Name,
                       Contract_Cost_Price__c,
                       Contract_Premium_Price__c,
                       Contract_Premium_Price_Without_Tax__c,
                       Tax_Amount__c,
                       Dealer_Price_Override__c,
                       Tax_Percentage__c,
                       Dealer_Package_Price__c,
                       Add_Ons_Price__c
                FROM Application_Package__c
                WHERE Application__c = :invoice.Application__c
                LIMIT 200
            ];

            // Build display price map
            Map<Id, Decimal> pkgDisplayPrice = new Map<Id, Decimal>();
            for (Application_Package__c pkg : appPkgs) {
                pkgDisplayPrice.put(pkg.Id, getDisplayPrice(pkg));
            }

            for (Application_Package__c pkg : appPkgs) {
                PackageRow row    = new PackageRow();
                row.pkg           = pkg;
                row.lineItems     = new List<LineItemWrapper>();
                row.packageTotal  = 0;
                row.baseCostPrice = pkg.Dealer_Package_Price__c != null ? pkg.Dealer_Package_Price__c : 0;
                row.addOnsTotal   = pkg.Add_Ons_Price__c != null ? pkg.Add_Ons_Price__c : 0;
                row.hasBreakdown  = row.addOnsTotal > 0;
                row.options       = pkgToOptions.containsKey(pkg.Id)
                    ? pkgToOptions.get(pkg.Id)
                    : new List<OptionWrapper>();

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
            }
        }
    }

    public class PackageRow {
        public Application_Package__c      pkg          { get; set; }
        public List<LineItemWrapper>        lineItems    { get; set; }
        public Decimal                     packageTotal { get; set; }
        public Decimal                     baseCostPrice { get; set; }
        public Decimal                     addOnsTotal   { get; set; }
        public Boolean                     hasBreakdown  { get; set; }
        public List<OptionWrapper>         options       { get; set; }
    }

    public class LineItemWrapper {
        public Invoice_Line_Item__c lineItem     { get; set; }
        public Decimal              displayPrice { get; set; }
    }

    public class OptionWrapper {
        public String  optionName { get; set; }
        public Decimal costPrice  { get; set; }
    }
}