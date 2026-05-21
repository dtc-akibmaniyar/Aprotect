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
            result.availableCredit = form.Dealer_Name__r?.Total_Available_Credit__c != null ? form.Dealer_Name__r.Total_Available_Credit__c : 0;

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
                        invRecord.lineItems.add(li);
                    }
                }
                invoiceRecords.add(invRecord);
            }

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
    }

    public class InvoiceRecord {
        @AuraEnabled public String id;
        @AuraEnabled public String invoiceName;
        @AuraEnabled public String applicationNumber;
        @AuraEnabled public String customerName;
        @AuraEnabled public String vehicleInfo;
        @AuraEnabled public String vin;
        @AuraEnabled public String status;
        @AuraEnabled public List<LineItemRecord> lineItems;
    }

    public class LineItemRecord {
        @AuraEnabled public String  id;
        @AuraEnabled public String  name;
        @AuraEnabled public Decimal costPriceWithoutTax;
        @AuraEnabled public Decimal costPriceWithTax;
        @AuraEnabled public Decimal taxAmount;
        @AuraEnabled public Decimal taxPercentage;
        @AuraEnabled public String  status;
    }
}