public without sharing class DealerPortalInvoiceBreakdownHandler {

    private static final Map<String, String> SERVICE_LABEL_MAP = new Map<String, String>{
        'Extended_Limited_Warranty' => 'Extended Limited Warranty',
        'Tire_Rim_Protection_Plan'  => 'Tire & Rim Protection',
        'Loan_Protection'           => 'Car Loan Protection',
        'GAP_Coverage'              => 'GAP Coverage'
    };

    /**
     * Computes the display price for an Application Package (cost/base price).
     */
    private static Decimal getDisplayPrice(Application_Package__c pkg) {
        return pkg.Contract_Cost_Price__c != null ? pkg.Contract_Cost_Price__c : 0;
    }

    /**
     * Returns the pre-tax display price for an Application Package.
     */
    private static Decimal getDisplayPriceWithoutTax(Application_Package__c pkg) {
        Decimal totalPrice = pkg.Contract_Cost_Price__c != null ? pkg.Contract_Cost_Price__c : 0;
        Decimal taxAmt = pkg.Tax_Amount__c != null ? pkg.Tax_Amount__c : 0;
        return totalPrice - taxAmt;
    }

    /**
     * Returns the tax amount for display purposes.
     */
    private static Decimal getDisplayTaxAmount(Application_Package__c pkg) {
        return pkg.Tax_Amount__c != null ? pkg.Tax_Amount__c : 0;
    }

    @AuraEnabled(cacheable=false)
    public static InvoiceBreakdownData getInvoiceBreakdown(String remittanceFormId) {
        // try {
            if (String.isBlank(remittanceFormId)) {
                throw new AuraHandledException('Remittance Form ID is required');
            }

            InvoiceBreakdownData result = new InvoiceBreakdownData();

            // ── 1. Query Remittance Form ──────────────────────────────────────
            List<Remittance_Form__c> remittanceForms = [
                SELECT Id, Name, Payer_Name__c, Receiver_Name__c, Dealer_Name__c,
                       Dealer_Name__r.Name,
                       Dealer_Name__r.Total_Credit_Amount__c,
                       Dealer_Name__r.Applied_Credit__c,
                       Dealer_Name__r.Total_Available_Credit__c,
                       Status__c, Cancelation_Reason__c, Bill_To__c,
                       Credit_Note__c, Credit_Issued_By__r.Name,
                       Discount_Amount__c, Remittance_Form_Total_After_Discount__c,
                       Balance__c, Paid_Amount__c,
                       RecordType.DeveloperName, Services_To_Pay__c
                FROM Remittance_Form__c
                WHERE Id = :remittanceFormId
                LIMIT 1
            ];

            if (remittanceForms.isEmpty()) {
                throw new AuraHandledException('Remittance Form not found');
            }

            Remittance_Form__c form = remittanceForms[0];
            result.remittanceFormName               = form.Name;
            result.payerName                        = form.Payer_Name__c;
            result.receiverName                     = form.Receiver_Name__c;
            result.dealerName                       = form.Dealer_Name__r?.Name;
            result.status                           = form.Status__c;
            result.cancellationReason               = form.Cancelation_Reason__c;
            result.billTo                           = form.Bill_To__c;
            result.creditNote                       = form.Credit_Note__c;
            result.creditIssuedBy                   = form.Credit_Issued_By__r?.Name;
            result.discountAmount                   = form.Discount_Amount__c;
            result.remittanceFormTotalAfterDiscount = form.Remittance_Form_Total_After_Discount__c;
            result.balance                          = form.Balance__c;
            result.paidAmount                       = form.Paid_Amount__c;
            result.isAllocationRemittance           = form.RecordType != null &&
                                                      form.RecordType.DeveloperName == 'Allocation_Remittance';
            result.totalCredit     = form.Dealer_Name__r?.Total_Credit_Amount__c   != null ? form.Dealer_Name__r.Total_Credit_Amount__c   : 0;
            result.appliedCredit   = form.Dealer_Name__r?.Applied_Credit__c         != null ? form.Dealer_Name__r.Applied_Credit__c         : 0;
            // Base available credit from Account formula
            Decimal baseAvailable = form.Dealer_Name__r?.Total_Available_Credit__c != null ? form.Dealer_Name__r.Total_Available_Credit__c : 0;
            // Subtract completed Dealer Credit payments (not tracked by DLRS rollup)
            if (form.Dealer_Name__c != null) {
                AggregateResult[] dcPayments = [
                    SELECT SUM(Amount__c) total
                    FROM Payment__c
                    WHERE Remittance_Form__r.Dealer_Name__c = :form.Dealer_Name__c
                      AND RecordType.DeveloperName = 'Dealer_Credit'
                      AND Payment_Confirmation_Status__c IN ('Transaction Completed', 'Deposit Completed')
                ];
                Decimal totalDCApplied = dcPayments != null && dcPayments[0].get('total') != null
                    ? (Decimal) dcPayments[0].get('total') : 0;
                baseAvailable -= totalDCApplied;
            }
            result.availableCredit = baseAvailable;

            // Friendly service labels
            if (result.isAllocationRemittance == true && String.isNotBlank(form.Services_To_Pay__c)) {
                List<String> labels = new List<String>();
                for (String dev : form.Services_To_Pay__c.split(';')) {
                    String lbl = SERVICE_LABEL_MAP.get(dev.trim());
                    if (lbl != null) labels.add(lbl);
                }
                result.selectedServiceLabels = String.join(labels, ', ');
            }

            // ── 2. Query Invoices ─────────────────────────────────────────────
            List<Invoice__c> invoices;

            if (result.isAllocationRemittance == true) {
                // Resolve invoice IDs via junction records
                Set<Id> invoiceFilterIds = new Set<Id>();
                for (Remittance_Line_Item_Junction__c j : [
                    SELECT Invoice__c
                    FROM Remittance_Line_Item_Junction__c
                    WHERE Remittance_Form__c = :remittanceFormId
                    AND Invoice__c != null
                ]) {
                    invoiceFilterIds.add(j.Invoice__c);
                }

                invoices = invoiceFilterIds.isEmpty()
                    ? new List<Invoice__c>()
                    : [
                        SELECT Id, Name, Application__c, Status__c, Application__r.Name,
                               Application_Id__c, Customer_Name__c,
                               Vehicle_Year__c, Vehicle_Make__c, Vehicle_Model__c, Vehicle_Trim__c, Vin__c,
                               Amount__c
                        FROM Invoice__c
                        WHERE Id IN :invoiceFilterIds
                        ORDER BY CreatedDate DESC
                        LIMIT 1000
                    ];
            } else {
                List<Invoice__c> allInvoices = [
                    SELECT Id, Name, Application__c, Status__c, Application__r.Name,
                           Application_Id__c, Customer_Name__c,
                           Vehicle_Year__c, Vehicle_Make__c, Vehicle_Model__c, Vehicle_Trim__c, Vin__c,
                           Amount__c
                    FROM Invoice__c
                    WHERE Remittance_Form__c = :remittanceFormId
                    ORDER BY CreatedDate DESC
                    LIMIT 1000
                ];
                // Deduplicate by Application + Name
                Map<String, Invoice__c> seenInvoices = new Map<String, Invoice__c>();
                for (Invoice__c inv : allInvoices) {
                    String key = inv.Application__c + '|' + inv.Name;
                    if (!seenInvoices.containsKey(key)) {
                        seenInvoices.put(key, inv);
                    }
                }
                invoices = seenInvoices.values();
            }

            Set<Id> invoiceIds = new Set<Id>();
            for (Invoice__c inv : invoices) invoiceIds.add(inv.Id);

            // ── 3. Query Invoice Line Items ───────────────────────────────────
            List<Invoice_Line_Item__c> lineItems;

            if (result.isAllocationRemittance == true) {
                // Only the line items junctioned to this remittance form
                Set<Id> allowedLineItemIds = new Set<Id>();
                for (Remittance_Line_Item_Junction__c j : [
                    SELECT Invoice_Line_Item__c
                    FROM Remittance_Line_Item_Junction__c
                    WHERE Remittance_Form__c = :remittanceFormId
                    AND Invoice_Line_Item__c != null
                ]) {
                    allowedLineItemIds.add(j.Invoice_Line_Item__c);
                }

                lineItems = allowedLineItemIds.isEmpty()
                    ? new List<Invoice_Line_Item__c>()
                    : [
                        SELECT Id, Invoice__c, Application_Package__c, Application_Package_Name__c,
                               Contract_Cost_Price_Without_Tax__c, Contract_Cost_Price__c,
                               Tax_Amount__c, Tax_Percentage__c, Status__c
                        FROM Invoice_Line_Item__c
                        WHERE Id IN :allowedLineItemIds
                        ORDER BY Application_Package_Name__c ASC
                        LIMIT 10000
                    ];
            } else {
                lineItems = invoiceIds.isEmpty()
                    ? new List<Invoice_Line_Item__c>()
                    : [
                        SELECT Id, Invoice__c, Application_Package__c, Application_Package_Name__c,
                               Contract_Cost_Price_Without_Tax__c, Contract_Cost_Price__c,
                               Tax_Amount__c, Tax_Percentage__c, Status__c
                        FROM Invoice_Line_Item__c
                        WHERE Invoice__c IN :invoiceIds
                        ORDER BY Application_Package_Name__c ASC
                        LIMIT 10000
                    ];
            }

            // ── 3b. Collect package IDs and query options for breakdown ────────
            Set<Id> allPackageIds = new Set<Id>();
            for (Invoice_Line_Item__c item : lineItems) {
                if (item.Application_Package__c != null) {
                    allPackageIds.add(item.Application_Package__c);
                }
            }

            // Query Application Packages for base price info
            Map<Id, Application_Package__c> appPkgMap = new Map<Id, Application_Package__c>();
            if (!allPackageIds.isEmpty()) {
                for (Application_Package__c pkg : [
                    SELECT Id, Dealer_Package_Price__c, Add_Ons_Price__c
                    FROM Application_Package__c
                    WHERE Id IN :allPackageIds
                ]) {
                    appPkgMap.put(pkg.Id, pkg);
                }
            }

            // Query Application Package Options for breakdown
            Map<Id, List<OptionRecord>> pkgToOptions = new Map<Id, List<OptionRecord>>();
            if (!allPackageIds.isEmpty()) {
                for (Application_Package_Option__c opt : [
                    SELECT Id, Application_Package__c, Option__c, Net_Cost__c, Selection_Type__c
                    FROM Application_Package_Option__c
                    WHERE Application_Package__c IN :allPackageIds
                    AND Net_Cost__c != null AND Net_Cost__c != 0
                    ORDER BY Option__c ASC
                ]) {
                    if (!pkgToOptions.containsKey(opt.Application_Package__c)) {
                        pkgToOptions.put(opt.Application_Package__c, new List<OptionRecord>());
                    }
                    OptionRecord or2 = new OptionRecord();
                    or2.optionName = opt.Option__c;
                    or2.costPrice  = opt.Net_Cost__c != null ? opt.Net_Cost__c : 0;
                    or2.selectionType = opt.Selection_Type__c;
                    pkgToOptions.get(opt.Application_Package__c).add(or2);
                }
            }

            // ── 4. Build map Invoice → line items ─────────────────────────────
            Map<Id, List<Invoice_Line_Item__c>> invoiceToLineItems = new Map<Id, List<Invoice_Line_Item__c>>();
            for (Invoice_Line_Item__c item : lineItems) {
                if (!invoiceToLineItems.containsKey(item.Invoice__c)) {
                    invoiceToLineItems.put(item.Invoice__c, new List<Invoice_Line_Item__c>());
                }
                invoiceToLineItems.get(item.Invoice__c).add(item);
            }

            // ── 5. Build InvoiceRecord list ───────────────────────────────────
            List<InvoiceRecord> invoiceRecords = new List<InvoiceRecord>();
            for (Invoice__c invoice : invoices) {
                InvoiceRecord invRecord    = new InvoiceRecord();
                invRecord.id              = invoice.Id;
                invRecord.invoiceName     = invoice.Name;
                invRecord.applicationNumber = invoice.Application_Id__c != null
                    ? invoice.Application_Id__c
                    : invoice.Application__c;
                invRecord.customerName    = invoice.Customer_Name__c;

                List<String> vehicleParts = new List<String>();
                if (invoice.Vehicle_Year__c  != null)            vehicleParts.add(String.valueOf(invoice.Vehicle_Year__c));
                if (String.isNotBlank(invoice.Vehicle_Make__c))  vehicleParts.add(invoice.Vehicle_Make__c);
                if (String.isNotBlank(invoice.Vehicle_Model__c)) vehicleParts.add(invoice.Vehicle_Model__c);
                if (String.isNotBlank(invoice.Vehicle_Trim__c))  vehicleParts.add(invoice.Vehicle_Trim__c);
                invRecord.vehicleInfo = String.join(vehicleParts, '/');
                invRecord.vin         = invoice.Vin__c;
                invRecord.status      = invoice.Status__c;

                invRecord.lineItems = new List<LineItemRecord>();
                if (invoiceToLineItems.containsKey(invoice.Id)) {
                    for (Invoice_Line_Item__c item : invoiceToLineItems.get(invoice.Id)) {
                        LineItemRecord li      = new LineItemRecord();
                        li.id                  = item.Id;
                        li.name                = item.Application_Package_Name__c;
                        li.costPriceWithoutTax = item.Contract_Cost_Price_Without_Tax__c;
                        li.costPriceWithTax    = item.Contract_Cost_Price__c;
                        li.taxAmount           = item.Tax_Amount__c;
                        li.taxPercentage       = item.Tax_Percentage__c;
                        li.status              = item.Status__c;

                        // Price breakdown
                        if (item.Application_Package__c != null && appPkgMap.containsKey(item.Application_Package__c)) {
                            Application_Package__c pkg = appPkgMap.get(item.Application_Package__c);
                            li.baseCostPrice = pkg.Dealer_Package_Price__c != null ? pkg.Dealer_Package_Price__c : 0;
                            li.addOnsTotal   = pkg.Add_Ons_Price__c != null ? pkg.Add_Ons_Price__c : 0;
                            li.hasBreakdown  = li.addOnsTotal > 0;
                            li.additionalOptions = pkgToOptions.containsKey(item.Application_Package__c)
                                ? pkgToOptions.get(item.Application_Package__c)
                                : new List<OptionRecord>();
                        } else {
                            li.baseCostPrice = 0;
                            li.addOnsTotal   = 0;
                            li.hasBreakdown  = false;
                            li.additionalOptions = new List<OptionRecord>();
                        }

                        invRecord.lineItems.add(li);
                    }
                }
                invoiceRecords.add(invRecord);
            }

            // Sort invoices by total payable amount ascending (lowest first)
            invoiceRecords.sort(new InvoiceAmountComparator());
            // Re-number rows after sorting
            for (Integer i = 0; i < invoiceRecords.size(); i++) {
                invoiceRecords[i].rowIndex = i + 1;
            }

            // Check if payments exist for this remittance
            Integer paymentCount = [
                SELECT COUNT() FROM Payment__c WHERE Remittance_Form__c = :remittanceFormId LIMIT 1
            ];
            result.hasPayments = paymentCount > 0;

            result.invoices = invoiceRecords;
            result.success  = true;
            return result;

        // } catch (Exception e) {
        //     AuraHandledException ahe = new AuraHandledException(e.getMessage());
        //     ahe.setMessage(e.getMessage());
        //     throw ahe;
        // }
    }

    @AuraEnabled(cacheable=false)
    public static void deleteInvoice(String invoiceId) {
        try {
            if (String.isBlank(invoiceId)) {
                throw new AuraHandledException('Invoice ID is required');
            }
            List<Invoice_Line_Item__c> lineItems = [
                SELECT Id FROM Invoice_Line_Item__c WHERE Invoice__c = :invoiceId
            ];
            if (!lineItems.isEmpty()) delete lineItems;
            delete new Invoice__c(Id = invoiceId);
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    // ── Wrapper classes ───────────────────────────────────────────────────────
    // ── Remove Invoice from Remittance ────────────────────────────────
    @AuraEnabled
    public static void removeInvoiceFromRemittance(String remittanceFormId, String invoiceId) {
        if (String.isBlank(remittanceFormId) || String.isBlank(invoiceId)) {
            throw new AuraHandledException('Remittance Form ID and Invoice ID are required');
        }
        // Check no payments exist
        Integer paymentCount = [SELECT COUNT() FROM Payment__c WHERE Remittance_Form__c = :remittanceFormId LIMIT 1];
        if (paymentCount > 0) {
            throw new AuraHandledException('Cannot remove invoices after a payment has been initiated');
        }
        // Must keep at least 1 invoice
        Integer invoiceCount = [SELECT COUNT() FROM Invoice__c WHERE Remittance_Form__c = :remittanceFormId];
        // Also count via junctions for allocation remittances
        Set<Id> junctionInvoiceIds = new Set<Id>();
        for (Remittance_Line_Item_Junction__c j : [
            SELECT Invoice__c FROM Remittance_Line_Item_Junction__c
            WHERE Remittance_Form__c = :remittanceFormId AND Invoice__c != null
        ]) {
            junctionInvoiceIds.add(j.Invoice__c);
        }
        Integer totalInvoices = Math.max(invoiceCount, junctionInvoiceIds.size());
        if (totalInvoices <= 1) {
            throw new AuraHandledException('Cannot remove the last invoice from a remittance');
        }
        // Delete junction records for this invoice on this remittance
        List<Remittance_Line_Item_Junction__c> junctions = [
            SELECT Id FROM Remittance_Line_Item_Junction__c
            WHERE Remittance_Form__c = :remittanceFormId AND Invoice__c = :invoiceId
        ];
        if (!junctions.isEmpty()) {
            delete junctions;
        }
        // Clear the Remittance_Form__c lookup on the invoice
        update new Invoice__c(Id = invoiceId, Remittance_Form__c = null);
    }

    // ── Get Available Invoices for Remittance ─────────────────────────
    @AuraEnabled
    public static List<AvailableInvoice> getAvailableInvoicesForRemittance(String remittanceFormId) {
        if (String.isBlank(remittanceFormId)) {
            throw new AuraHandledException('Remittance Form ID is required');
        }
        // Check no payments exist
        Integer paymentCount = [SELECT COUNT() FROM Payment__c WHERE Remittance_Form__c = :remittanceFormId LIMIT 1];
        if (paymentCount > 0) {
            throw new AuraHandledException('Cannot add invoices after a payment has been initiated');
        }
        // Get the dealer from the remittance form
        Remittance_Form__c form = [SELECT Dealer_Name__c FROM Remittance_Form__c WHERE Id = :remittanceFormId LIMIT 1];
        if (form.Dealer_Name__c == null) {
            throw new AuraHandledException('Remittance Form has no dealer');
        }
        // Get invoice IDs already on this remittance
        Set<Id> existingInvoiceIds = new Set<Id>();
        for (Invoice__c inv : [SELECT Id FROM Invoice__c WHERE Remittance_Form__c = :remittanceFormId]) {
            existingInvoiceIds.add(inv.Id);
        }
        for (Remittance_Line_Item_Junction__c j : [
            SELECT Invoice__c FROM Remittance_Line_Item_Junction__c
            WHERE Remittance_Form__c = :remittanceFormId AND Invoice__c != null
        ]) {
            existingInvoiceIds.add(j.Invoice__c);
        }
        // Query available invoices: same dealer, submitted applications, Due status, not on this remittance
        List<Invoice__c> available = [
            SELECT Id, Name, Application_Id__c, Customer_Name__c, Amount__c, Status__c,
                   Vehicle_Year__c, Vehicle_Make__c, Vehicle_Model__c
            FROM Invoice__c
            WHERE Application__r.Dealer_Name__c = :form.Dealer_Name__c
              AND Application__r.Application_Status__c = 'Submitted'
              AND Status__c = 'Due'
              AND Remittance_Form__c = null
              AND Id NOT IN :existingInvoiceIds
            ORDER BY Amount__c ASC
            LIMIT 200
        ];
        List<AvailableInvoice> results = new List<AvailableInvoice>();
        for (Invoice__c inv : available) {
            AvailableInvoice ai = new AvailableInvoice();
            ai.id = inv.Id;
            ai.invoiceName = inv.Name;
            ai.applicationNumber = inv.Application_Id__c;
            ai.customerName = inv.Customer_Name__c;
            ai.amount = inv.Amount__c;
            List<String> vParts = new List<String>();
            if (inv.Vehicle_Year__c != null) vParts.add(String.valueOf(inv.Vehicle_Year__c));
            if (String.isNotBlank(inv.Vehicle_Make__c)) vParts.add(inv.Vehicle_Make__c);
            if (String.isNotBlank(inv.Vehicle_Model__c)) vParts.add(inv.Vehicle_Model__c);
            ai.vehicleInfo = String.join(vParts, ' ');
            results.add(ai);
        }
        return results;
    }

    // ── Add Invoice to Remittance ─────────────────────────────────────
    @AuraEnabled
    public static void addInvoiceToRemittance(String remittanceFormId, String invoiceId) {
        if (String.isBlank(remittanceFormId) || String.isBlank(invoiceId)) {
            throw new AuraHandledException('Remittance Form ID and Invoice ID are required');
        }
        // Check no payments exist
        Integer paymentCount = [SELECT COUNT() FROM Payment__c WHERE Remittance_Form__c = :remittanceFormId LIMIT 1];
        if (paymentCount > 0) {
            throw new AuraHandledException('Cannot add invoices after a payment has been initiated');
        }
        // Link the invoice to the remittance form
        update new Invoice__c(Id = invoiceId, Remittance_Form__c = remittanceFormId);
        // Create junction records for each line item
        List<Invoice_Line_Item__c> lineItems = [
            SELECT Id, Contract_Cost_Price__c FROM Invoice_Line_Item__c WHERE Invoice__c = :invoiceId AND Status__c != 'Paid'
        ];
        List<Remittance_Line_Item_Junction__c> junctions = new List<Remittance_Line_Item_Junction__c>();
        for (Invoice_Line_Item__c ili : lineItems) {
            Decimal displayPrice = ili.Contract_Cost_Price__c != null ? ili.Contract_Cost_Price__c : 0;
            junctions.add(new Remittance_Line_Item_Junction__c(
                Remittance_Form__c = remittanceFormId,
                Invoice__c = invoiceId,
                Invoice_Line_Item__c = ili.Id,
                Line_Item_Amount__c = displayPrice,
                Payment_Status__c = 'Planned'
            ));
        }
        if (!junctions.isEmpty()) {
            insert junctions;
        }
    }

    // ── Comparator for sorting invoices by total amount ascending ─────
    private class InvoiceAmountComparator implements Comparator<InvoiceRecord> {
        public Integer compare(InvoiceRecord a, InvoiceRecord b) {
            Decimal amtA = 0;
            Decimal amtB = 0;
            if (a.lineItems != null) {
                for (LineItemRecord li : a.lineItems) {
                    amtA += li.costPriceWithTax != null ? li.costPriceWithTax : 0;
                }
            }
            if (b.lineItems != null) {
                for (LineItemRecord li : b.lineItems) {
                    amtB += li.costPriceWithTax != null ? li.costPriceWithTax : 0;
                }
            }
            if (amtA < amtB) return -1;
            if (amtA > amtB) return 1;
            return 0;
        }
    }

    // ── Wrapper classes ───────────────────────────────────────────────────────
    public class InvoiceBreakdownData {
        @AuraEnabled public List<InvoiceRecord> invoices;
        @AuraEnabled public Boolean success;
        @AuraEnabled public String  remittanceFormName;
        @AuraEnabled public String  payerName;
        @AuraEnabled public String  receiverName;
        @AuraEnabled public String  dealerName;
        @AuraEnabled public String  status;
        @AuraEnabled public String  cancellationReason;
        @AuraEnabled public String  billTo;
        @AuraEnabled public String  creditNote;
        @AuraEnabled public String  creditIssuedBy;
        @AuraEnabled public Decimal discountAmount;
        @AuraEnabled public Decimal remittanceFormTotalAfterDiscount;
        @AuraEnabled public Decimal balance;
        @AuraEnabled public Decimal paidAmount;
        @AuraEnabled public Boolean isAllocationRemittance;
        @AuraEnabled public String  selectedServiceLabels;
        @AuraEnabled public Decimal totalCredit;
        @AuraEnabled public Decimal appliedCredit;
        @AuraEnabled public Decimal availableCredit;
        @AuraEnabled public Boolean hasPayments;
    }

    public class InvoiceRecord {
        @AuraEnabled public String id;
        @AuraEnabled public String invoiceName;
        @AuraEnabled public String applicationNumber;
        @AuraEnabled public String customerName;
        @AuraEnabled public String vehicleInfo;
        @AuraEnabled public String vin;
        @AuraEnabled public String status;
        @AuraEnabled public Integer rowIndex;
        @AuraEnabled public List<LineItemRecord> lineItems;
    }

    public class AvailableInvoice {
        @AuraEnabled public String id;
        @AuraEnabled public String invoiceName;
        @AuraEnabled public String applicationNumber;
        @AuraEnabled public String customerName;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String vehicleInfo;
    }

    public class LineItemRecord {
        @AuraEnabled public String  id;
        @AuraEnabled public String  name;
        @AuraEnabled public Decimal costPriceWithoutTax;
        @AuraEnabled public Decimal costPriceWithTax;
        @AuraEnabled public Decimal taxAmount;
        @AuraEnabled public Decimal taxPercentage;
        @AuraEnabled public String  status;
        @AuraEnabled public Decimal baseCostPrice;
        @AuraEnabled public Decimal addOnsTotal;
        @AuraEnabled public Boolean hasBreakdown;
        @AuraEnabled public List<OptionRecord> additionalOptions;
    }

    public class OptionRecord {
        @AuraEnabled public String  optionName;
        @AuraEnabled public Decimal costPrice;
        @AuraEnabled public String  selectionType;
    }
}