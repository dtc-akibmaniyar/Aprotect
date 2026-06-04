public class RemittanceFormPDFController {
    public Remittance_Form__c remittanceForm     { get; set; }
    public List<InvoiceWithItems> invoicesWithItems { get; set; }
    public Decimal  totalAmount            { get; set; }
    public Decimal  totalTax               { get; set; }
    public Decimal  grandTotal             { get; set; }
    public Boolean  isAllocationRemittance { get; set; }
    public String   selectedServiceLabels  { get; set; }
    public String   remittanceDate         { get; set; }

    private static final Map<String, String> SERVICE_LABEL_MAP = new Map<String, String>{
        'Extended_Limited_Warranty' => 'Extended Limited Warranty',
        'Tire_Rim_Protection_Plan'  => 'Tire & Rim Protection',
        'Loan_Protection'           => 'Car Loan Protection',
        'GAP_Coverage'              => 'GAP Coverage'
    };

    /**
     * Returns the dealer/cost price (tax-inclusive) for an Application Package.
     */
    private static Decimal getDisplayPrice(Application_Package__c pkg) {
        return pkg.Contract_Cost_Price__c != null ? pkg.Contract_Cost_Price__c : 0;
    }

    /**
     * Returns the dealer/cost price (pre-tax) for an Application Package.
     */
    private static Decimal getDisplayPriceWithoutTax(Application_Package__c pkg) {
        return pkg.Contract_Cost_Price_Without_Tax__c != null ? pkg.Contract_Cost_Price_Without_Tax__c : 0;
    }

    /**
     * Computes a duration string like "12 Months / 20,000 KM" from package fields.
     */
    public static String getDurationString(Application_Package__c pkg) {
        String monthsStr = null;
        String kmStr = null;

        if (pkg.Month__c != null) {
            monthsStr = String.valueOf(pkg.Month__c);
        } else if (pkg.Dealer_Package_Term__r != null && pkg.Dealer_Package_Term__r.Month__c != null) {
            monthsStr = String.valueOf(pkg.Dealer_Package_Term__r.Month__c);
        }

        if (pkg.Dealer_Package_Term__r != null && pkg.Dealer_Package_Term__r.Odometer_KM__c != null) {
            kmStr = String.valueOf(pkg.Dealer_Package_Term__r.Odometer_KM__c);
            // Format with commas if numeric
            if (kmStr != null && kmStr.isNumeric()) {
                kmStr = Decimal.valueOf(kmStr).format();
            }
        }

        String result = '';
        if (String.isNotBlank(monthsStr)) {
            result = monthsStr + ' Months';
        }
        if (String.isNotBlank(kmStr)) {
            if (String.isNotBlank(result)) result += ' / ';
            result += kmStr + ' KM';
        }
        return result;
    }

    /**
     * Returns the package display name from Package_Record_Type__c.
     */
    public static String getPackageDisplayName(Application_Package__c pkg) {
        if (String.isNotBlank(pkg.Package_Record_Type__c)) {
            return pkg.Package_Record_Type__c;
        }
        if (pkg.RecordType != null && String.isNotBlank(pkg.RecordType.Name)) {
            return pkg.RecordType.Name;
        }
        return '';
    }

    public RemittanceFormPDFController() {
        invoicesWithItems      = new List<InvoiceWithItems>();
        totalAmount            = 0;
        totalTax               = 0;
        grandTotal             = 0;
        isAllocationRemittance = false;
        selectedServiceLabels  = '';
        remittanceDate         = '';

        String remittanceFormId = ApexPages.currentPage().getParameters().get('id');

        if (String.isBlank(remittanceFormId)) {
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'Remittance Form ID is required'));
            return;
        }

        try {
            // -- 1. Query Remittance Form (added Date__c) --
            List<Remittance_Form__c> forms = [
                SELECT Id, Name, Payer_Name__c, Receiver_Name__c,
                       Dealer_Name__c, Dealer_Name__r.Name, CreatedDate, Date__c,
                       Status__c, Cancelation_Reason__c, Bill_To__c, Credit_Note__c,
                       Credit_Issued_By__r.Name, Discount_Amount__c,
                       Remittance_Form_Total_After_Discount__c, Balance__c, Paid_Amount__c,
                       RecordType.DeveloperName, Services_To_Pay__c
                FROM Remittance_Form__c
                WHERE Id = :remittanceFormId
                LIMIT 1
            ];

            if (forms.isEmpty()) {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'Remittance Form not found'));
                return;
            }

            remittanceForm         = forms[0];
            isAllocationRemittance = remittanceForm.RecordType != null &&
                                     remittanceForm.RecordType.DeveloperName == 'Allocation_Remittance';

            // Format remittance date
            if (remittanceForm.Date__c != null) {
                Datetime dt = Datetime.newInstance(remittanceForm.Date__c.year(), remittanceForm.Date__c.month(), remittanceForm.Date__c.day());
                remittanceDate = dt.format('MMM dd, yyyy');
            }

            // Build friendly service labels for allocation remittance
            if (isAllocationRemittance && String.isNotBlank(remittanceForm.Services_To_Pay__c)) {
                List<String> labels = new List<String>();
                for (String dev : remittanceForm.Services_To_Pay__c.split(';')) {
                    String lbl = SERVICE_LABEL_MAP.get(dev.trim());
                    if (lbl != null) labels.add(lbl);
                }
                selectedServiceLabels = String.join(labels, ', ');
            }

            // -- 2. Resolve IDs via junction records (Allocation only) --
            Set<Id> allowedLineItemIds = null;
            Set<Id> allowedPackageIds  = null;
            Set<Id> invoiceFilterIds   = null;

            if (isAllocationRemittance) {
                allowedLineItemIds = new Set<Id>();
                allowedPackageIds  = new Set<Id>();
                invoiceFilterIds   = new Set<Id>();

                for (Remittance_Line_Item_Junction__c j : [
                    SELECT Invoice_Line_Item__c,
                           Invoice_Line_Item__r.Application_Package__c,
                           Invoice__c
                    FROM Remittance_Line_Item_Junction__c
                    WHERE Remittance_Form__c = :remittanceFormId
                ]) {
                    if (j.Invoice_Line_Item__c != null)
                        allowedLineItemIds.add(j.Invoice_Line_Item__c);
                    if (j.Invoice__c != null)
                        invoiceFilterIds.add(j.Invoice__c);
                    if (j.Invoice_Line_Item__r != null &&
                        j.Invoice_Line_Item__r.Application_Package__c != null)
                        allowedPackageIds.add(j.Invoice_Line_Item__r.Application_Package__c);
                }
            }

            // -- 3. Query Invoices --
            String invoiceWhere = isAllocationRemittance
                ? 'WHERE Id IN :invoiceFilterIds'
                : 'WHERE Remittance_Form__c = :remittanceFormId';

            List<Invoice__c> invoices = Database.query(
                'SELECT Id, Name, Application__c, Application_Id__c, Customer_Name__c, ' +
                '       Vehicle_Year__c, Vehicle_Make__c, Vehicle_Model__c, Vehicle_Trim__c, Vin__c, ' +
                '       Amount__c, Status__c, CreatedDate, ' +
                '       Application__r.Id, Application__r.Name, ' +
                '       Application__r.Customer_First_Name__c, Application__r.Customer_Last_Name__c, ' +
                '       Application__r.Customer_Address__c, Application__r.Customer_Phone__c, ' +
                '       Application__r.Customer_Email__c, Application__r.Customer_Name__c, ' +
                '       Application__r.Customer_Name__r.Name, Application__r.Customer_Name__r.License_Number__c, ' +
                '       Application__r.Co_Buyer__r.Name, Application__r.Co_Buyer__r.BillingStreet, ' +
                '       Application__r.Co_Buyer__r.Phone, Application__r.Co_Buyer__r.PersonEmail, ' +
                '       Application__r.Vehicle_VIN__c, Application__r.Vehicle_Year__c, ' +
                '       Application__r.Vehicle_Make__c, Application__r.Vehicle_Model__c, ' +
                '       Application__r.Vehicle_Purchase_Price__c, Application__r.Odometer__c, ' +
                '       Application__r.Odometer_Unit__c, Application__r.Vehicle_Transmission__c, ' +
                '       Application__r.Vehicle__r.Id, Application__r.Vehicle__r.Delivery_Date__c, ' +
                '       Application__r.Vehicle__r.Type_Of_Commercial_Use__c, Application__r.Vehicle__r.Engine__c, ' +
                '       Application__r.Vehicle__r.Fuel_Type__c, Application__r.Vehicle__r.Drive_Type__c, ' +
                '       Application__r.Vehicle__r.Body_Type__c, Application__r.Vehicle__r.Color__c, ' +
                '       Application__r.Vehicle__r.GVWR__c, Application__r.Vehicle__r.Manufacturer_Warranty_Type__c, ' +
                '       Application__r.Vehicle__r.Warranty_Term__c, Application__r.Vehicle__r.In_Service_Date__c, ' +
                '       Application__r.Dealer_Name__r.Name, Application__r.Dealer_Name__r.BillingStreet, ' +
                '       Application__r.Dealer_Name__r.BillingCity, Application__r.Dealer_Name__r.BillingState, ' +
                '       Application__r.Dealer_Name__r.BillingPostalCode, ' +
                '       Application__r.Financial_Institution_Lender__c, Application__r.Lender_Address__c ' +
                'FROM Invoice__c ' +
                invoiceWhere +
                ' ORDER BY CreatedDate DESC LIMIT 1000'
            );

            Set<Id> invoiceIds     = new Set<Id>();
            Set<Id> applicationIds = new Set<Id>();
            for (Invoice__c inv : invoices) {
                invoiceIds.add(inv.Id);
                if (inv.Application__c != null) applicationIds.add(inv.Application__c);
            }

            // -- 4. Query Application Packages with cost pricing + new fields --
            Map<Id, List<Application_Package__c>> appToPackages = new Map<Id, List<Application_Package__c>>();
            Map<Id, Application_Package__c> packageById = new Map<Id, Application_Package__c>();
            Set<Id> packageIds = new Set<Id>();

            if (!applicationIds.isEmpty()) {
                String pkgWhere = isAllocationRemittance
                    ? 'WHERE Id IN :allowedPackageIds'
                    : 'WHERE Application__c IN :applicationIds';

                List<Application_Package__c> packages = Database.query(
                    'SELECT Id, Application__c, Package__r.Name, Package_Term__r.Name, ' +
                    '       Odometer_Start__c, Odometer_End__c, Contract_Start_Date__c, Contract_End_Date__c, ' +
                    '       RecordType.Name, Dealer_Package_Price__c, ' +
                    '       Contract_Premium_Price__c, Contract_Premium_Price_Without_Tax__c, ' +
                    '       Dealer_Price_Override__c, Tax_Amount__c, Tax_Percentage__c, ' +
                    '       Package_Record_Type__c, Month__c, ' +
                    '       Dealer_Package_Term__r.Month__c, Dealer_Package_Term__r.Odometer_KM__c, ' +
                    '       Contract_Cost_Price__c, Contract_Cost_Price_Without_Tax__c ' +
                    'FROM Application_Package__c ' +
                    pkgWhere +
                    ' LIMIT 10000'
                );

                for (Application_Package__c pkg : packages) {
                    packageIds.add(pkg.Id);
                    packageById.put(pkg.Id, pkg);
                    if (!appToPackages.containsKey(pkg.Application__c)) {
                        appToPackages.put(pkg.Application__c, new List<Application_Package__c>());
                    }
                    appToPackages.get(pkg.Application__c).add(pkg);
                }
            }

            // -- 5. Query Package Options --
            Map<Id, List<Application_Package_Option__c>> packageToOptions = new Map<Id, List<Application_Package_Option__c>>();
            if (!packageIds.isEmpty()) {
                for (Application_Package_Option__c opt : [
                    SELECT Id, Application_Package__c, Option__c, Retail_Price__c, Net_Cost__c, Selection_Type__c
                    FROM Application_Package_Option__c
                    WHERE Application_Package__c IN :packageIds
                    AND Selection_Type__c = 'Optional'
                    LIMIT 10000
                ]) {
                    if (!packageToOptions.containsKey(opt.Application_Package__c)) {
                        packageToOptions.put(opt.Application_Package__c, new List<Application_Package_Option__c>());
                    }
                    packageToOptions.get(opt.Application_Package__c).add(opt);
                }
            }

            // -- 6. Query Invoice Line Items --
            String liWhere = isAllocationRemittance
                ? 'WHERE Id IN :allowedLineItemIds'
                : 'WHERE Invoice__c IN :invoiceIds';

            List<Invoice_Line_Item__c> lineItems = Database.query(
                'SELECT Id, Invoice__c, Application_Package__c, Application_Package_Name__c, ' +
                '       Contract_Cost_Price_Without_Tax__c, Contract_Cost_Price__c, ' +
                '       Tax_Amount__c, Tax_Percentage__c, Status__c ' +
                'FROM Invoice_Line_Item__c ' +
                liWhere +
                ' ORDER BY Application_Package_Name__c ASC LIMIT 10000'
            );

            // -- 7. Build InvoiceWithItems using cost prices --
            Map<Id, List<Invoice_Line_Item__c>> invoiceToLineItems = new Map<Id, List<Invoice_Line_Item__c>>();
            for (Invoice_Line_Item__c item : lineItems) {
                if (!invoiceToLineItems.containsKey(item.Invoice__c)) {
                    invoiceToLineItems.put(item.Invoice__c, new List<Invoice_Line_Item__c>());
                }
                invoiceToLineItems.get(item.Invoice__c).add(item);
            }

            for (Invoice__c invoice : invoices) {
                InvoiceWithItems invWithItems = new InvoiceWithItems();
                invWithItems.invoice     = invoice;
                invWithItems.application = invoice.Application__r;
                invWithItems.invoiceName = invoice.Name;

                // Map package ID -> line items for this invoice
                Map<Id, List<Invoice_Line_Item__c>> pkgToLineItems = new Map<Id, List<Invoice_Line_Item__c>>();
                if (invoiceToLineItems.containsKey(invoice.Id)) {
                    for (Invoice_Line_Item__c li : invoiceToLineItems.get(invoice.Id)) {
                        if (li.Application_Package__c != null) {
                            if (!pkgToLineItems.containsKey(li.Application_Package__c)) {
                                pkgToLineItems.put(li.Application_Package__c, new List<Invoice_Line_Item__c>());
                            }
                            pkgToLineItems.get(li.Application_Package__c).add(li);
                        }
                    }
                }

                // Packages
                invWithItems.packages = new List<PackageWithOptions>();
                if (appToPackages.containsKey(invoice.Application__c)) {
                    for (Application_Package__c pkg : appToPackages.get(invoice.Application__c)) {
                        PackageWithOptions pkgWithOpts = new PackageWithOptions();
                        pkgWithOpts.applicationPackage = pkg;
                        pkgWithOpts.additionalOptions  = packageToOptions.containsKey(pkg.Id)
                            ? packageToOptions.get(pkg.Id)
                            : new List<Application_Package_Option__c>();

                        // Duration and display name
                        pkgWithOpts.duration    = getDurationString(pkg);
                        pkgWithOpts.displayName = getPackageDisplayName(pkg);

                        // Cost pricing
                        pkgWithOpts.dealerPrice = getDisplayPriceWithoutTax(pkg);
                        pkgWithOpts.taxAmount   = getDisplayPrice(pkg) - getDisplayPriceWithoutTax(pkg);
                        pkgWithOpts.subtotal    = getDisplayPrice(pkg);

                        // Build display line items with cost prices
                        List<Invoice_Line_Item__c> rawLineItems = pkgToLineItems.containsKey(pkg.Id)
                            ? pkgToLineItems.get(pkg.Id)
                            : new List<Invoice_Line_Item__c>();
                        pkgWithOpts.packageLineItems = rawLineItems;

                        List<LineItemDisplay> displayItems = new List<LineItemDisplay>();
                        for (Invoice_Line_Item__c li : rawLineItems) {
                            LineItemDisplay d = new LineItemDisplay();
                            d.lineItemId = li.Id;
                            d.status = li.Status__c;
                            d.displayPrice = getDisplayPrice(pkg);
                            displayItems.add(d);
                        }
                        pkgWithOpts.displayLineItems = displayItems;

                        invWithItems.packages.add(pkgWithOpts);
                    }
                }

                // All line items for this invoice
                invWithItems.lineItems = invoiceToLineItems.containsKey(invoice.Id)
                    ? invoiceToLineItems.get(invoice.Id)
                    : new List<Invoice_Line_Item__c>();

                // Totals using cost prices from Application_Package__c
                invWithItems.invoiceSubTotal = 0;
                invWithItems.invoiceTaxTotal = 0;
                for (Invoice_Line_Item__c item : invWithItems.lineItems) {
                    Application_Package__c pkg = item.Application_Package__c != null
                        ? packageById.get(item.Application_Package__c) : null;

                    if (pkg != null) {
                        Decimal priceWithoutTax = getDisplayPriceWithoutTax(pkg);
                        Decimal priceWithTax    = getDisplayPrice(pkg);
                        invWithItems.invoiceSubTotal += priceWithoutTax;
                        invWithItems.invoiceTaxTotal += (priceWithTax - priceWithoutTax);
                    } else {
                        // Fallback to cost fields if no package found
                        if (item.Contract_Cost_Price_Without_Tax__c != null)
                            invWithItems.invoiceSubTotal += item.Contract_Cost_Price_Without_Tax__c;
                        if (item.Tax_Amount__c != null)
                            invWithItems.invoiceTaxTotal += item.Tax_Amount__c;
                    }
                }
                invWithItems.invoiceGrandTotal = invWithItems.invoiceSubTotal + invWithItems.invoiceTaxTotal;

                invoicesWithItems.add(invWithItems);
                totalAmount += invWithItems.invoiceSubTotal;
                totalTax    += invWithItems.invoiceTaxTotal;
                grandTotal  += invWithItems.invoiceGrandTotal;
            }

        } catch (Exception e) {
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'Error loading remittance form: ' + e.getMessage()));
            System.debug('RemittanceFormPDFController error: ' + e.getMessage());
        }
    }

    // Wrapper: display-ready line item with cost price
    public class LineItemDisplay {
        public String  lineItemId   { get; set; }
        public String  status       { get; set; }
        public Decimal displayPrice { get; set; }
    }

    public class InvoiceWithItems {
        public Invoice__c invoice                   { get; set; }
        public Application__c application           { get; set; }
        public List<Invoice_Line_Item__c> lineItems { get; set; }
        public List<PackageWithOptions> packages     { get; set; }
        public Decimal invoiceSubTotal              { get; set; }
        public Decimal invoiceTaxTotal              { get; set; }
        public Decimal invoiceGrandTotal            { get; set; }
        public String  invoiceName                  { get; set; }
    }

    public class PackageWithOptions {
        public Application_Package__c applicationPackage          { get; set; }
        public List<Application_Package_Option__c> additionalOptions { get; set; }
        public List<Invoice_Line_Item__c> packageLineItems        { get; set; }
        public List<LineItemDisplay> displayLineItems             { get; set; }
        public String  duration    { get; set; }
        public String  displayName { get; set; }
        public Decimal dealerPrice { get; set; }
        public Decimal taxAmount   { get; set; }
        public Decimal subtotal    { get; set; }
    }
}