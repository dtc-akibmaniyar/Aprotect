public without sharing class InvoiceDetailViewController {

    /**
     * Returns the dealer cost price (base + tax) for an Application Package.
     * Used on the dealer portal invoice page to show what the dealer owes.
     */
    private static Decimal getDisplayPrice(Application_Package__c pkg) {
        return pkg.Contract_Cost_Price__c != null ? pkg.Contract_Cost_Price__c : 0;
    }

    @AuraEnabled(cacheable=true)
    public static InvoiceDetailData getInvoiceDetail(String invoiceId) {
        try {
        if (String.isBlank(invoiceId)) {
            throw new AuraHandledException('Invoice ID is required');
        }

        // ── 1. Query Invoice + Application + Remittance Bill To ──────────────
        List<Invoice__c> invoices = [
            SELECT Id, Name, Status__c, CreatedDate,
                   Remittance_Form__c,
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

        if (invoices.isEmpty()) {
            throw new AuraHandledException('Invoice not found');
        }

        Invoice__c inv = invoices[0];

        // ── 2. Query Invoice Line Items first to determine which packages to load ─
        List<Invoice_Line_Item__c> lineItems = [
            SELECT Id, Invoice__c, Application_Package__c,
                   Contract_Cost_Price__c,
                   Tax_Amount__c, Status__c
            FROM Invoice_Line_Item__c
            WHERE Invoice__c = :invoiceId
            ORDER BY Application_Package_Name__c ASC
            LIMIT 1000
        ];

        // ── 3. Query only the Application Packages referenced by line items ────
        //       Now includes retail/custom pricing fields for display
        Set<Id> packageIds = new Set<Id>();
        for (Invoice_Line_Item__c li : lineItems) {
            if (li.Application_Package__c != null) packageIds.add(li.Application_Package__c);
        }
        List<Application_Package__c> packages = packageIds.isEmpty()
            ? new List<Application_Package__c>()
            : [
                SELECT Id, Application__c, Package__r.Name, Package_Term__r.Name,
                       Odometer_Start__c, Odometer_End__c,
                       Contract_Start_Date__c, Contract_End_Date__c,
                       RecordType.Name,
                       Contract_Cost_Price__c,
                       Contract_Cost_Price_Without_Tax__c,
                       Contract_Premium_Price__c,
                       Contract_Premium_Price_Without_Tax__c,
                       Tax_Amount__c,
                       Tax_Amount_Cost__c,
                       Dealer_Price_Override__c,
                       Tax_Percentage__c,
                       Dealer_Package_Price__c,
                       Add_Ons_Price__c
                FROM Application_Package__c
                WHERE Id IN :packageIds
              ];

        // Build a map of package Id → display price
        Map<Id, Decimal> pkgDisplayPrice = new Map<Id, Decimal>();
        for (Application_Package__c pkg : packages) {
            pkgDisplayPrice.put(pkg.Id, getDisplayPrice(pkg));
        }

        // ── 3b. Query Application Package Options for breakdown ──────────────
        Map<Id, List<Application_Package_Option__c>> pkgToOptions = new Map<Id, List<Application_Package_Option__c>>();
        if (!packageIds.isEmpty()) {
            for (Application_Package_Option__c opt : [
                SELECT Id, Application_Package__c, Option__c, Net_Cost__c,
                       Selection_Type__c
                FROM Application_Package_Option__c
                WHERE Application_Package__c IN :packageIds
                AND Net_Cost__c != null AND Net_Cost__c != 0
                ORDER BY Option__c ASC
            ]) {
                if (!pkgToOptions.containsKey(opt.Application_Package__c)) {
                    pkgToOptions.put(opt.Application_Package__c, new List<Application_Package_Option__c>());
                }
                pkgToOptions.get(opt.Application_Package__c).add(opt);
            }
        }

        // ── 4. Map package → line items using display prices ──────────────────
        Map<Id, List<Invoice_Line_Item__c>> pkgToLineItems = new Map<Id, List<Invoice_Line_Item__c>>();
        // Track display price per line item (for grand total)
        Map<Id, Decimal> lineItemDisplayPrice = new Map<Id, Decimal>();
        Decimal grandTotal = 0;
        for (Invoice_Line_Item__c li : lineItems) {
            // Use display price from package instead of cost price
            Decimal displayAmt = (li.Application_Package__c != null && pkgDisplayPrice.containsKey(li.Application_Package__c))
                ? pkgDisplayPrice.get(li.Application_Package__c)
                : (li.Contract_Cost_Price__c != null ? li.Contract_Cost_Price__c : 0);
            lineItemDisplayPrice.put(li.Id, displayAmt);
            grandTotal += displayAmt;
            if (li.Application_Package__c != null) {
                if (!pkgToLineItems.containsKey(li.Application_Package__c)) {
                    pkgToLineItems.put(li.Application_Package__c, new List<Invoice_Line_Item__c>());
                }
                pkgToLineItems.get(li.Application_Package__c).add(li);
            }
        }

        // ── 5. Build result ───────────────────────────────────────────────────
        InvoiceDetailData result = new InvoiceDetailData();
        result.invoiceId     = inv.Id;
        result.invoiceName   = inv.Name;
        result.invoiceStatus = inv.Status__c;
        result.invoiceDate   = inv.CreatedDate != null
            ? inv.CreatedDate.format('MMM dd, yyyy')
            : null;
        result.hasRemittanceForm = inv.Remittance_Form__c != null;
        result.dealerName = inv.Remittance_Form__r?.Dealer_Name__r?.Name;
        result.billTo     = inv.Remittance_Form__r?.Bill_To__c;
        result.applicationId       = inv.Application__r?.Name;
        result.applicationRecordId = inv.Application__c;

        Application__c app = inv.Application__r;
        if (app != null) {
            String fn = app.Customer_First_Name__c != null ? app.Customer_First_Name__c : '';
            String ln = app.Customer_Last_Name__c  != null ? app.Customer_Last_Name__c  : '';
            result.customerFullName = (fn + ' ' + ln).trim();
            result.customerAddress  = app.Customer_Address__c;
            result.vin              = app.Vehicle_VIN__c;

            List<String> vParts = new List<String>();
            if (app.Vehicle_Year__c  != null)             vParts.add(String.valueOf(app.Vehicle_Year__c));
            if (String.isNotBlank(app.Vehicle_Make__c))  vParts.add(app.Vehicle_Make__c);
            if (String.isNotBlank(app.Vehicle_Model__c)) vParts.add(app.Vehicle_Model__c);
            result.vehicleInfo = String.join(vParts, '/');
            result.odometer    = app.Odometer__c;
            result.odometerUnit = app.Odometer_Unit__c != null ? app.Odometer_Unit__c : 'KM';
        }

        result.packages = new List<PackageData>();
        for (Application_Package__c pkg : packages) {
            PackageData pd   = new PackageData();
            pd.packageId     = pkg.Id;
            pd.recordTypeName = pkg.RecordType?.Name;
            pd.packageName   = pkg.Package__r?.Name;
            pd.packageTerm   = pkg.Package_Term__r?.Name;
            pd.startDate     = pkg.Contract_Start_Date__c != null
                ? Datetime.newInstance(pkg.Contract_Start_Date__c, Time.newInstance(0,0,0,0)).format('dd-MM-yyyy')
                : null;
            pd.expiryDate    = pkg.Contract_End_Date__c != null
                ? Datetime.newInstance(pkg.Contract_End_Date__c, Time.newInstance(0,0,0,0)).format('dd-MM-yyyy')
                : null;
            pd.startOdometer  = pkg.Odometer_Start__c;
            pd.expiryOdometer = pkg.Odometer_End__c;

            // Price breakdown
            pd.baseCostPrice = pkg.Dealer_Package_Price__c != null ? pkg.Dealer_Package_Price__c : 0;
            pd.addOnsTotal   = pkg.Add_Ons_Price__c != null ? pkg.Add_Ons_Price__c : 0;
            pd.hasBreakdown  = pd.addOnsTotal > 0;

            // Additional options
            pd.additionalOptions = new List<OptionData>();
            if (pkgToOptions.containsKey(pkg.Id)) {
                for (Application_Package_Option__c opt : pkgToOptions.get(pkg.Id)) {
                    OptionData od = new OptionData();
                    od.optionId   = opt.Id;
                    od.optionName = opt.Option__c;
                    od.costPrice  = opt.Net_Cost__c != null ? opt.Net_Cost__c : 0;
                    od.selectionType = opt.Selection_Type__c;
                    pd.additionalOptions.add(od);
                }
            }

            pd.lineItems = new List<LineItemData>();
            if (pkgToLineItems.containsKey(pkg.Id)) {
                for (Invoice_Line_Item__c li : pkgToLineItems.get(pkg.Id)) {
                    LineItemData ld = new LineItemData();
                    ld.lineItemId = li.Id;
                    ld.status     = li.Status__c;
                    // Use retail/custom display price instead of cost
                    ld.amount     = lineItemDisplayPrice.get(li.Id);
                    pd.lineItems.add(ld);
                }
            }
            result.packages.add(pd);
        }

        result.totalAmount  = grandTotal;
        result.packageCount = result.packages.size();
        return result;

        } catch (AuraHandledException e) {
            throw e;
        } catch (QueryException e) {
            AuraHandledException ahe = new AuraHandledException('Failed to load invoice data: ' + e.getMessage());
            ahe.setMessage('Failed to load invoice data: ' + e.getMessage());
            throw ahe;
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException('An unexpected error occurred: ' + e.getMessage());
            ahe.setMessage('An unexpected error occurred: ' + e.getMessage());
            throw ahe;
        }
    }

    // ── Cancellation Request ──────────────────────────────────────────────────

    @AuraEnabled
    public static OperationResult submitCancellationRequest(String invoiceId, String lineItemId, String reason) {
        try {
            if (String.isBlank(invoiceId)) {
                return new OperationResult(false, 'Invoice ID is required.');
            }
            if (String.isBlank(reason)) {
                return new OperationResult(false, 'Cancellation reason is required.');
            }

            List<Invoice__c> invoices = [
                SELECT Id, Name, Status__c
                FROM Invoice__c
                WHERE Id = :invoiceId
                LIMIT 1
            ];
            if (invoices.isEmpty()) {
                return new OperationResult(false, 'Invoice not found.');
            }
            Invoice__c inv = invoices[0];

            Cancellation__c cancellation = new Cancellation__c();
            cancellation.Invoice__c                    = inv.Id;
            cancellation.Cancellation_Reason__c        = reason;
            cancellation.Cancellation_Status__c        = 'Pending';
            cancellation.Invoice_Status_At_Request__c  = inv.Status__c;

            if (String.isBlank(lineItemId)) {
                // Invoice-level cancellation
                if (inv.Status__c == 'Cancelled') {
                    return new OperationResult(false, 'This invoice is already cancelled.');
                }
                cancellation.Cancellation_Type__c = 'Invoice';
                insert cancellation;

                // Create a Cancellation__c record for each line item immediately
                List<Invoice_Line_Item__c> allLineItems = [
                    SELECT Id, Status__c
                    FROM Invoice_Line_Item__c
                    WHERE Invoice__c = :invoiceId
                ];
                if (!allLineItems.isEmpty()) {
                    List<Cancellation__c> liCancellations = new List<Cancellation__c>();
                    for (Invoice_Line_Item__c li : allLineItems) {
                        liCancellations.add(new Cancellation__c(
                            Invoice__c                      = inv.Id,
                            Invoice_Line_Item__c            = li.Id,
                            Cancellation_Type__c            = 'Invoice Line Item',
                            Cancellation_Status__c          = 'Pending',
                            Cancellation_Reason__c          = 'Auto-created from Invoice cancellation request: ' + inv.Name,
                            Invoice_Status_At_Request__c    = inv.Status__c,
                            Line_Item_Status_At_Request__c  = li.Status__c
                        ));
                    }
                    insert liCancellations;
                }
                return new OperationResult(true, 'Cancellation request submitted successfully.');
            } else {
                // Line item-level cancellation
                List<Invoice_Line_Item__c> lineItems2 = [
                    SELECT Id, Status__c
                    FROM Invoice_Line_Item__c
                    WHERE Id = :lineItemId
                    LIMIT 1
                ];
                if (lineItems2.isEmpty()) {
                    return new OperationResult(false, 'Invoice line item not found.');
                }
                Invoice_Line_Item__c li = lineItems2[0];
                if (li.Status__c == 'Cancelled') {
                    return new OperationResult(false, 'This line item is already cancelled.');
                }
                cancellation.Cancellation_Type__c          = 'Invoice Line Item';
                cancellation.Invoice_Line_Item__c          = li.Id;
                cancellation.Line_Item_Status_At_Request__c = li.Status__c;
                insert cancellation;
                return new OperationResult(true, 'Cancellation request submitted successfully.');
            }

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException('Error submitting cancellation: ' + e.getMessage());
            ahe.setMessage('Error submitting cancellation: ' + e.getMessage());
            throw ahe;
        }
    }

    // ── Pay Now: Create Remittance Form for a single Invoice ─────────────────

    @AuraEnabled
    public static OperationResult createRemittanceForInvoice(String invoiceId) {
        try {
            if (String.isBlank(invoiceId)) {
                return new OperationResult(false, 'Invoice ID is required.');
            }

            List<Invoice__c> invoices = [
                SELECT Id, Name, Status__c, Remittance_Form__c,
                       Application__c,
                       Application__r.Dealer_Name__c,
                       Application__r.Dealer_Name__r.Name
                FROM Invoice__c
                WHERE Id = :invoiceId
                LIMIT 1
            ];

            if (invoices.isEmpty()) {
                return new OperationResult(false, 'Invoice not found.');
            }

            Invoice__c inv = invoices[0];

            if (inv.Status__c == 'Paid') {
                return new OperationResult(false, 'This invoice has already been paid.');
            }
            if (inv.Status__c == 'Cancelled') {
                return new OperationResult(false, 'This invoice has been cancelled.');
            }

            String dealerId   = inv.Application__r?.Dealer_Name__c;
            String dealerName2 = inv.Application__r?.Dealer_Name__r?.Name != null
                ? inv.Application__r.Dealer_Name__r.Name : '';

            Remittance_Form__c rf = new Remittance_Form__c(
                RecordTypeId     = Schema.SObjectType.Remittance_Form__c
                                       .getRecordTypeInfosByDeveloperName()
                                       .get('Dealer_Remittance').getRecordTypeId(),
                Receiver_Name__c = 'A-Protect',
                Payer_Name__c    = dealerName2,
                Dealer_Name__c   = dealerId,
                Status__c        = 'Open'
            );
            insert rf;

            // Link Application to the new remittance form
            if (inv.Application__c != null) {
                update new Application__c(Id = inv.Application__c, Remittance_Form__c = rf.Id);
            }

            // Link Invoice to the new remittance form
            update new Invoice__c(Id = inv.Id, Remittance_Form__c = rf.Id);

            // Query unpaid line items for this invoice (include package reference)
            List<Invoice_Line_Item__c> lineItems3 = [
                SELECT Id, Contract_Cost_Price__c, Application_Package__c
                FROM Invoice_Line_Item__c
                WHERE Invoice__c = :invoiceId
                AND Status__c != 'Paid'
            ];

            if (!lineItems3.isEmpty()) {
                Set<Id> unpaidLineItemIds = new Set<Id>();
                Set<Id> packageIds = new Set<Id>();
                for (Invoice_Line_Item__c li : lineItems3) {
                    unpaidLineItemIds.add(li.Id);
                    if (li.Application_Package__c != null) packageIds.add(li.Application_Package__c);
                }

                // ── FIX: Query Application Packages for retail pricing ──
                Map<Id, Application_Package__c> pkgMap = new Map<Id, Application_Package__c>();
                if (!packageIds.isEmpty()) {
                    for (Application_Package__c pkg : [
                        SELECT Id, Contract_Premium_Price__c, Dealer_Price_Override__c
                        FROM Application_Package__c
                        WHERE Id IN :packageIds
                    ]) {
                        pkgMap.put(pkg.Id, pkg);
                    }
                }

                // Delete stale Planned junctions from previous remittance attempts
                List<Remittance_Line_Item_Junction__c> staleJunctions = [
                    SELECT Id
                    FROM Remittance_Line_Item_Junction__c
                    WHERE Invoice_Line_Item__c IN :unpaidLineItemIds
                    AND Payment_Status__c = 'Planned'
                ];
                if (!staleJunctions.isEmpty()) delete staleJunctions;

                // Create fresh junction records on the new remittance form
                List<Remittance_Line_Item_Junction__c> junctions = new List<Remittance_Line_Item_Junction__c>();
                for (Invoice_Line_Item__c li : lineItems3) {
                    // Use dealer cost price for remittance payable amount
                    Decimal displayAmount = li.Contract_Cost_Price__c != null ? li.Contract_Cost_Price__c : 0;

                    junctions.add(new Remittance_Line_Item_Junction__c(
                        Remittance_Form__c   = rf.Id,
                        Invoice__c           = inv.Id,
                        Invoice_Line_Item__c = li.Id,
                        Line_Item_Amount__c  = displayAmount,
                        Payment_Status__c    = 'Planned'
                    ));
                }
                insert junctions;
            }

            return new OperationResult(true, 'Remittance form created successfully.', rf.Id);

        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException('Error creating remittance form: ' + e.getMessage());
            ahe.setMessage('Error creating remittance form: ' + e.getMessage());
            throw ahe;
        }
    }

    public class OperationResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String  message;
        @AuraEnabled public String  remittanceFormId;

        public OperationResult(Boolean success, String message) {
            this.success = success;
            this.message = message;
        }

        public OperationResult(Boolean success, String message, String remittanceFormId) {
            this.success = success;
            this.message = message;
            this.remittanceFormId = remittanceFormId;
        }
    }

    // ── PDF Download ──────────────────────────────────────────────────────────

    @AuraEnabled
    public static PDFDownloadResponse downloadInvoicePDF(String invoiceId) {
        try {
            List<Invoice__c> invoices = [SELECT Id, Name FROM Invoice__c WHERE Id = :invoiceId LIMIT 1];
            if (invoices.isEmpty()) {
                PDFDownloadResponse r = new PDFDownloadResponse();
                r.success = false;
                r.message = 'Invoice not found';
                return r;
            }
            PageReference pdfPage = new PageReference('/apex/InvoiceDetailPDF?id=' + invoiceId);
            Blob pdfBlob = pdfPage.getContentAsPDF();
            PDFDownloadResponse r = new PDFDownloadResponse();
            r.success  = true;
            r.pdfData  = EncodingUtil.base64Encode(pdfBlob);
            r.fileName = 'Invoice_' + invoices[0].Name + '_' + DateTime.now().format('yyyyMMdd_HHmmss') + '.pdf';
            return r;
        } catch (Exception e) {
            PDFDownloadResponse r = new PDFDownloadResponse();
            r.success = false;
            r.message = 'Error generating PDF: ' + e.getMessage();
            return r;
        }
    }

    public class PDFDownloadResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String  message;
        @AuraEnabled public String  pdfData;
        @AuraEnabled public String  fileName;
    }

    // ── Wrapper classes ───────────────────────────────────────────────────────
    public class InvoiceDetailData {
        @AuraEnabled public String  invoiceId;
        @AuraEnabled public String  invoiceName;
        @AuraEnabled public String  invoiceStatus;
        @AuraEnabled public String  invoiceDate;
        @AuraEnabled public Boolean hasRemittanceForm;
        @AuraEnabled public String  dealerName;
        @AuraEnabled public String  billTo;
        @AuraEnabled public String  applicationId;
        @AuraEnabled public String  applicationRecordId;
        @AuraEnabled public String  customerFullName;
        @AuraEnabled public String  customerAddress;
        @AuraEnabled public String  vehicleInfo;
        @AuraEnabled public String  vin;
        @AuraEnabled public Decimal odometer;
        @AuraEnabled public String  odometerUnit;
        @AuraEnabled public List<PackageData> packages;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public Integer packageCount;
    }

    public class PackageData {
        @AuraEnabled public String  packageId;
        @AuraEnabled public String  recordTypeName;
        @AuraEnabled public String  packageName;
        @AuraEnabled public String  packageTerm;
        @AuraEnabled public String  startDate;
        @AuraEnabled public String  expiryDate;
        @AuraEnabled public Decimal startOdometer;
        @AuraEnabled public Decimal expiryOdometer;
        @AuraEnabled public List<LineItemData> lineItems;
        @AuraEnabled public Decimal baseCostPrice;
        @AuraEnabled public Decimal addOnsTotal;
        @AuraEnabled public Boolean hasBreakdown;
        @AuraEnabled public List<OptionData> additionalOptions;
    }

    public class LineItemData {
        @AuraEnabled public String  lineItemId;
        @AuraEnabled public String  status;
        @AuraEnabled public Decimal amount;
    }

    public class OptionData {
        @AuraEnabled public String  optionId;
        @AuraEnabled public String  optionName;
        @AuraEnabled public Decimal costPrice;
        @AuraEnabled public String  selectionType;
    }
}