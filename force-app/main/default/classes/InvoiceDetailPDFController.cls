public without sharing class  InvoiceDetailPDFController {

    public Invoice__c         invoice      { get; set; }
    public Application__c     application  { get; set; }
    public String             dealerName   { get; set; }
    public String             billTo       { get; set; }
    public List<PackageRow>   packages     { get; set; }
    public Decimal            grandTotal   { get; set; }

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
        dealerName  = invoice.Remittance_Form__r?.Dealer_Name__r?.Name;
        billTo      = invoice.Remittance_Form__r?.Bill_To__c;

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
        for (Invoice_Line_Item__c li : lineItems) {
            grandTotal += li.Contract_Cost_Price__c != null ? li.Contract_Cost_Price__c : 0;
            if (li.Application_Package__c != null) {
                if (!pkgMap.containsKey(li.Application_Package__c))
                    pkgMap.put(li.Application_Package__c, new List<Invoice_Line_Item__c>());
                pkgMap.get(li.Application_Package__c).add(li);
            }
        }

        // ── 3. Packages ───────────────────────────────────────────────────────
        if (invoice.Application__c != null) {
            List<Application_Package__c> appPkgs = [
                SELECT Id, Package__r.Name, Package_Term__r.Name,
                       Odometer_Start__c, Odometer_End__c,
                       Contract_Start_Date__c, Contract_End_Date__c,
                       RecordType.Name
                FROM Application_Package__c
                WHERE Application__c = :invoice.Application__c
                LIMIT 200
            ];
            for (Application_Package__c pkg : appPkgs) {
                PackageRow row    = new PackageRow();
                row.pkg           = pkg;
                row.lineItems     = pkgMap.containsKey(pkg.Id) ? pkgMap.get(pkg.Id) : new List<Invoice_Line_Item__c>();
                row.packageTotal  = 0;
                for (Invoice_Line_Item__c li : row.lineItems)
                    row.packageTotal += li.Contract_Cost_Price__c != null ? li.Contract_Cost_Price__c : 0;
                packages.add(row);
            }
        }
    }

    public class PackageRow {
        public Application_Package__c      pkg          { get; set; }
        public List<Invoice_Line_Item__c>  lineItems    { get; set; }
        public Decimal                     packageTotal { get; set; }
    }
}