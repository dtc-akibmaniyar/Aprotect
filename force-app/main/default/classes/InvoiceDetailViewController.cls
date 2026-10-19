public without sharing class InvoiceDetailViewController {
    private static Decimal getDisplayPrice(Application_Package__c pkg) {
        return pkg.Contract_Cost_Price__c != null ? pkg.Contract_Cost_Price__c : 0;
    }
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
    private static String stripOptionalSuffix(String value) {
        if (value == null) {
            return '';
        }
        String trimmed = value.trim();
        if (trimmed.endsWith(InvoiceOptionLineService.OPTIONAL_SUFFIX)) {
            return trimmed.substring(0,
                trimmed.length() - InvoiceOptionLineService.OPTIONAL_SUFFIX.length());
        }
        return trimmed;
    }
    private static Boolean checkPaymentInitiated(Id remittanceFormId) {
        if (remittanceFormId == null) return false;
        return [
            SELECT COUNT()
            FROM Payment__c
            WHERE Remittance_Form__c = :remittanceFormId
        ] > 0;
    }
    @AuraEnabled(cacheable=true)
    public static InvoiceDetailData getInvoiceDetail(String invoiceId) {
        try {
        if (String.isBlank(invoiceId)) {
            throw new AuraHandledException('Invoice ID is required');
        }
        List<Invoice__c> invoices = [
            SELECT Id, Name, Status__c, CreatedDate,
                   Total_Balance_Amount__c, Invoice_Due_Date__c,
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
        if (invoices.isEmpty()) {
            throw new AuraHandledException('Invoice not found');
        }
        Invoice__c inv = invoices[0];
        Boolean paymentInitiated = checkPaymentInitiated(inv.Remittance_Form__c);
        List<Invoice_Line_Item__c> lineItems = [
            SELECT Id, Invoice__c, Application_Package__c,
                   Contract_Cost_Price__c,
                   Tax_Amount__c, Status__c, Amount__c, Description__c
            FROM Invoice_Line_Item__c
            WHERE Invoice__c = :invoiceId
            ORDER BY Application_Package_Name__c ASC
            LIMIT 1000
        ];
        Set<String> billedOptionKeys = new Set<String>();
        for (Invoice_Line_Item__c li : lineItems) {
            if (li.Application_Package__c == null && li.Amount__c != null && li.Amount__c != 0) {
                billedOptionKeys.add(
                    InvoiceOptionLineService.normalize(stripOptionalSuffix(li.Description__c)));
            }
        }
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
                       Dealer_Package__c, Dealer_Package__r.Name,
                       Dealer_Package__r.Package__r.Name,
                       Dealer_Package_Term__r.Dealer_Package__c,
                       Dealer_Package_Term__r.Name,
                       Dealer_Package_Term__r.Package_Term__r.Name,
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
                       Add_Ons_Price__c,
                       Premium_Model_Fee__c
                FROM Application_Package__c
                WHERE Id IN :packageIds
              ];
        Map<Id, FeeSet> feeByPkg = loadFeeLinesByPackage(packageIds);
        Map<Id, Decimal> pkgDisplayPrice = new Map<Id, Decimal>();
        for (Application_Package__c pkg : packages) {
            FeeSet fs = feeByPkg.get(pkg.Id);
            Decimal extraWithTax = 0;
            if (fs != null && fs.extraFee > 0) {
                Decimal rate = pkg.Tax_Percentage__c != null ? pkg.Tax_Percentage__c : 0;
                extraWithTax = (fs.extraFee + (fs.extraFee * rate / 100))
                    .setScale(2, System.RoundingMode.HALF_UP);
            }
            pkgDisplayPrice.put(pkg.Id, getDisplayPrice(pkg) + extraWithTax);
        }
        Map<Id, List<OptionData>> pkgToOptions = new Map<Id, List<OptionData>>();
        if (!packageIds.isEmpty()) {
            Map<Id, Id> dealerPkgByPkg = new Map<Id, Id>();
            for (Application_Package__c p : packages) {
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
                if (billedOptionKeys.contains(
                        InvoiceOptionLineService.normalize(line.Description__c))) {
                    continue; // already rendered as a real (billed) invoice line
                }
                List<OptionData> rows = pkgToOptions.get(line.Application_Package__c);
                if (rows == null) {
                    rows = new List<OptionData>();
                    pkgToOptions.put(line.Application_Package__c, rows);
                }
                Dealer_Package_Option__c mirror = line.Package_Option__c != null
                    ? mirrorByMaster.get(line.Package_Option__c) : null;
                OptionData od = new OptionData();
                od.optionId   = line.Id;
                od.optionName = String.isNotBlank(line.Description__c) ? line.Description__c : 'Additional Option';
                od.costPrice  = mirror != null && mirror.Net_Cost__c != null
                    ? mirror.Net_Cost__c : (line.Amount__c != null ? line.Amount__c : 0);
                od.selectionType = 'Optional';
                rows.add(od);
            }
        }
        Map<String, Id> optionNameToPkg   = new Map<String, Id>();
        Set<String>     ambiguousOption   = new Set<String>();
        Map<Id, List<OptionData>> billedOptionsByPkg = new Map<Id, List<OptionData>>();
        Set<Id>         nestedOptionLineIds = new Set<Id>();
        Decimal         nestedOptionSubTotal = 0;
        try {
            if (!packageIds.isEmpty()) {
                for (Application_Package_Line_Item__c line : (List<Application_Package_Line_Item__c>) Database.queryWithBinds(
                        'SELECT Id, Name, Application_Package__c' +
                        ' FROM Application_Package_Line_Item__c' +
                        ' WHERE Application_Package__c IN :packageIds',
                        new Map<String, Object>{ 'packageIds' => packageIds },
                        System.AccessLevel.SYSTEM_MODE)) {
                    if (line.Application_Package__c == null || String.isBlank(line.Name)) {
                        continue;
                    }
                    String key = InvoiceOptionLineService.normalize(line.Name);
                    if (String.isBlank(key)) {
                        continue;
                    }
                    if (!optionNameToPkg.containsKey(key)) {
                        optionNameToPkg.put(key, line.Application_Package__c);
                    } else if (optionNameToPkg.get(key) != line.Application_Package__c) {
                        ambiguousOption.add(key);   // same option name on more than one package
                    }
                }
            }
            for (Invoice_Line_Item__c li : lineItems) {
                if (li.Application_Package__c != null || li.Amount__c == null || li.Amount__c == 0) {
                    continue;
                }
                if (!(li.Description__c != null
                        && li.Description__c.trim().endsWith(InvoiceOptionLineService.OPTIONAL_SUFFIX))) {
                    continue;   // not a billed option line — leave it untouched
                }
                String stem = InvoiceOptionLineService.normalize(stripOptionalSuffix(li.Description__c));
                if (String.isBlank(stem) || ambiguousOption.contains(stem)) {
                    continue;
                }
                Id ownerPkg = optionNameToPkg.get(stem);
                if (ownerPkg == null) {
                    continue;   // owning package could not be determined — keep the fallback
                }
                OptionData od     = new OptionData();
                od.optionId       = li.Id;
                od.optionName     = stripOptionalSuffix(li.Description__c);
                od.costPrice      = li.Amount__c;
                od.selectionType  = 'Optional';
                od.isBilledOption = true;
                List<OptionData> rows = billedOptionsByPkg.get(ownerPkg);
                if (rows == null) {
                    rows = new List<OptionData>();
                    billedOptionsByPkg.put(ownerPkg, rows);
                }
                rows.add(od);
                nestedOptionLineIds.add(li.Id);
                nestedOptionSubTotal += li.Amount__c;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'LWC: option->package mapping unavailable: ' + e.getMessage());
            billedOptionsByPkg.clear();
            nestedOptionLineIds.clear();
            nestedOptionSubTotal = 0;
        }
        Map<Id, List<Invoice_Line_Item__c>> pkgToLineItems = new Map<Id, List<Invoice_Line_Item__c>>();
        Map<Id, Decimal> lineItemDisplayPrice = new Map<Id, Decimal>();
        Decimal grandTotal = 0;
        Decimal standaloneSubTotal = 0;
        for (Invoice_Line_Item__c li : lineItems) {
            Decimal displayAmt = (li.Application_Package__c != null && pkgDisplayPrice.containsKey(li.Application_Package__c))
                ? pkgDisplayPrice.get(li.Application_Package__c)
                : (li.Amount__c != null ? li.Amount__c : 0);
            lineItemDisplayPrice.put(li.Id, displayAmt);
            grandTotal += displayAmt;
            if (li.Application_Package__c == null) {
                standaloneSubTotal += displayAmt;
            } else {
                if (!pkgToLineItems.containsKey(li.Application_Package__c)) {
                    pkgToLineItems.put(li.Application_Package__c, new List<Invoice_Line_Item__c>());
                }
                pkgToLineItems.get(li.Application_Package__c).add(li);
            }
        }
        InvoiceDetailData result = new InvoiceDetailData();
        result.invoiceId     = inv.Id;
        result.invoiceName   = inv.Name;
        result.invoiceStatus = inv.Status__c;
        result.invoiceDate   = inv.CreatedDate != null
            ? inv.CreatedDate.format('MMM dd, yyyy')
            : null;
        result.hasRemittanceForm = inv.Remittance_Form__c != null;
        result.dueDate = inv.Invoice_Due_Date__c != null ? String.valueOf(inv.Invoice_Due_Date__c) : null;
        result.hasPaymentInitiated = paymentInitiated;
        result.dealerName = inv.Remittance_Form__r?.Dealer_Name__r?.Name != null
            ? inv.Remittance_Form__r.Dealer_Name__r.Name
            : (inv.Application__r?.Dealer_Name__r?.Name != null ? inv.Application__r.Dealer_Name__r.Name : null);
        if (inv.Remittance_Form__r?.Bill_To__c != null) {
            result.billTo = inv.Remittance_Form__r.Bill_To__c;
        } else if (inv.Application__r?.Dealer_Name__r != null) {
            Account dlr = inv.Application__r.Dealer_Name__r;
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
            result.billTo = String.join(addrParts, '<br/>');
        } else {
            result.billTo = null;
        }
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
            pd.isOptionRow   = false;
            pd.packageName   = resolvePackageName(pkg);
            pd.packageTerm   = resolveTermName(pkg);
            pd.startDate     = pkg.Contract_Start_Date__c != null
                ? Datetime.newInstance(pkg.Contract_Start_Date__c, Time.newInstance(0,0,0,0)).format('dd-MM-yyyy')
                : null;
            pd.expiryDate    = pkg.Contract_End_Date__c != null
                ? Datetime.newInstance(pkg.Contract_End_Date__c, Time.newInstance(0,0,0,0)).format('dd-MM-yyyy')
                : null;
            pd.startOdometer  = pkg.Odometer_Start__c;
            pd.expiryOdometer = pkg.Odometer_End__c;
            pd.baseCostPrice = pkg.Dealer_Package_Price__c != null ? pkg.Dealer_Package_Price__c : 0;
            pd.addOnsTotal   = pkg.Add_Ons_Price__c != null ? pkg.Add_Ons_Price__c : 0;
            pd.hasBreakdown  = pd.addOnsTotal > 0;
            pd.premiumModelFee = pkg.Premium_Model_Fee__c != null ? pkg.Premium_Model_Fee__c : 0;
            pd.hasPremiumModelFee = pd.premiumModelFee > 0;
            FeeSet fs = feeByPkg.get(pkg.Id);
            pd.dieselFee         = fs != null ? fs.dieselFee : 0;
            pd.commercialFee     = fs != null ? fs.commercialFee : 0;
            pd.powersportsFee    = fs != null ? fs.powersportsFee : 0;
            pd.hasDieselFee      = pd.dieselFee > 0;
            pd.hasCommercialFee  = pd.commercialFee > 0;
            pd.hasPowersportsFee = pd.powersportsFee > 0;
            pd.extraFeeTotal     = fs != null ? fs.extraFee : 0;
            pd.hasExtraFees      = pd.extraFeeTotal > 0;
            pd.hasStoredLineSet  = fs != null && fs.hasLines;
            pd.basePriceWithoutTax = (pkg.Contract_Cost_Price_Without_Tax__c != null ? pkg.Contract_Cost_Price_Without_Tax__c : 0)
                + pd.extraFeeTotal;
            pd.taxPercentage = pkg.Tax_Percentage__c != null ? pkg.Tax_Percentage__c : 0;
            Decimal costWithTax = pkg.Contract_Cost_Price__c != null ? pkg.Contract_Cost_Price__c : 0;
            Decimal costWithoutTax = pd.basePriceWithoutTax - pd.extraFeeTotal;
            pd.taxAmount = costWithTax - costWithoutTax;
            pd.hasTax = pd.taxPercentage > 0 || pd.taxAmount > 0 || pd.extraFeeTotal > 0;
            List<OptionData> pkgOptionRows = pkgToOptions.containsKey(pkg.Id)
                ? new List<OptionData>(pkgToOptions.get(pkg.Id))
                : new List<OptionData>();
            if (billedOptionsByPkg.containsKey(pkg.Id)) {
                pkgOptionRows.addAll(billedOptionsByPkg.get(pkg.Id));
            }
            pd.additionalOptions = pkgOptionRows;
            pd.lineItems = new List<LineItemData>();
            if (pkgToLineItems.containsKey(pkg.Id)) {
                for (Invoice_Line_Item__c li : pkgToLineItems.get(pkg.Id)) {
                    LineItemData ld = new LineItemData();
                    ld.lineItemId = li.Id;
                    ld.status     = li.Status__c;
                    ld.amount     = lineItemDisplayPrice.get(li.Id);
                    pd.lineItems.add(ld);
                }
            }
            result.packages.add(pd);
        }
        for (Invoice_Line_Item__c li : lineItems) {
            if (li.Application_Package__c != null) {
                continue;
            }
            Decimal amt = li.Amount__c != null ? li.Amount__c : 0;
            if (amt == 0) {
                continue;
            }
            if (nestedOptionLineIds.contains(li.Id)) {
                continue;
            }
            PackageData pd         = new PackageData();
            pd.packageId           = li.Id;
            pd.recordTypeName      = 'Options';
            pd.packageName         = String.isNotBlank(li.Description__c) ? li.Description__c : 'Option';
            pd.packageTerm         = '';
            pd.lineItems           = new List<LineItemData>();
            pd.additionalOptions   = new List<OptionData>();
            pd.baseCostPrice       = amt;
            pd.addOnsTotal         = 0;
            pd.hasBreakdown        = false;
            pd.premiumModelFee     = 0;
            pd.hasPremiumModelFee  = false;
            pd.basePriceWithoutTax = amt;
            pd.taxPercentage       = 0;
            pd.taxAmount           = 0;
            pd.hasTax              = false;
            pd.extraFeeTotal       = 0;
            pd.hasExtraFees        = false;
            pd.hasStoredLineSet    = false;
            pd.isOptionRow         = true;
            result.packages.add(pd);
        }
        Decimal subTotalCalc = 0;
        Decimal taxTotalCalc = 0;
        for (PackageData pd2 : result.packages) {
            if (pd2.basePriceWithoutTax != null) subTotalCalc += pd2.basePriceWithoutTax;
            if (pd2.hasTax == true && pd2.taxPercentage != null && pd2.basePriceWithoutTax != null) {
                taxTotalCalc += pd2.basePriceWithoutTax * (pd2.taxPercentage / 100);
            }
        }
        result.totalAmount   = grandTotal;
        result.subTotal      = subTotalCalc + nestedOptionSubTotal;
        result.taxTotal      = taxTotalCalc;
        result.balanceAmount = inv.Total_Balance_Amount__c != null ? inv.Total_Balance_Amount__c : 0;
        result.packageCount  = result.packages.size();
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
                SELECT Id, Name, Status__c, Remittance_Form__c
                FROM Invoice__c
                WHERE Id = :invoiceId
                LIMIT 1
            ];
            if (invoices.isEmpty()) {
                return new OperationResult(false, 'Invoice not found.');
            }
            Invoice__c inv = invoices[0];
            if (checkPaymentInitiated(inv.Remittance_Form__c)) {
                throw new AuraHandledException('Packages cannot be removed after a payment has been initiated on this invoice.');
            }
            Cancellation__c cancellation = new Cancellation__c();
            cancellation.Invoice__c                    = inv.Id;
            cancellation.Cancellation_Reason__c        = reason;
            cancellation.Cancellation_Status__c        = 'Pending';
            cancellation.Invoice_Status_At_Request__c  = inv.Status__c;
            if (String.isBlank(lineItemId)) {
                if (inv.Status__c == 'Cancelled') {
                    return new OperationResult(false, 'This invoice is already cancelled.');
                }
                cancellation.Cancellation_Type__c = 'Invoice';
                insert cancellation;
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
            if (inv.Application__c != null) {
                update new Application__c(Id = inv.Application__c, Remittance_Form__c = rf.Id);
            }
            update new Invoice__c(Id = inv.Id, Remittance_Form__c = rf.Id);
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
                List<Remittance_Line_Item_Junction__c> staleJunctions = [
                    SELECT Id
                    FROM Remittance_Line_Item_Junction__c
                    WHERE Invoice_Line_Item__c IN :unpaidLineItemIds
                    AND Payment_Status__c = 'Planned'
                ];
                if (!staleJunctions.isEmpty()) delete staleJunctions;
                List<Remittance_Line_Item_Junction__c> junctions = new List<Remittance_Line_Item_Junction__c>();
                for (Invoice_Line_Item__c li : lineItems3) {
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
    public class InvoiceDetailData {
        @AuraEnabled public String  invoiceId;
        @AuraEnabled public String  invoiceName;
        @AuraEnabled public String  invoiceStatus;
        @AuraEnabled public String  invoiceDate;
        @AuraEnabled public Boolean hasRemittanceForm;
        @AuraEnabled public Boolean hasPaymentInitiated;
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
        @AuraEnabled public Decimal balanceAmount;
        @AuraEnabled public Integer packageCount;
        @AuraEnabled public String  dueDate;
        @AuraEnabled public Decimal subTotal;
        @AuraEnabled public Decimal taxTotal;
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
        @AuraEnabled public Decimal premiumModelFee;
        @AuraEnabled public Boolean hasPremiumModelFee;
        @AuraEnabled public Decimal basePriceWithoutTax;
        @AuraEnabled public Decimal taxPercentage;
        @AuraEnabled public Decimal taxAmount;
        @AuraEnabled public Boolean hasTax;
        @AuraEnabled public Decimal dieselFee;
        @AuraEnabled public Decimal commercialFee;
        @AuraEnabled public Decimal powersportsFee;
        @AuraEnabled public Boolean hasDieselFee;
        @AuraEnabled public Boolean hasCommercialFee;
        @AuraEnabled public Boolean hasPowersportsFee;
        @AuraEnabled public Decimal extraFeeTotal;
        @AuraEnabled public Boolean hasExtraFees;
        @AuraEnabled public Boolean hasStoredLineSet;
        @AuraEnabled public Boolean isOptionRow;
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
        @AuraEnabled public Boolean isBilledOption;
    }
    public class FeeSet {
        public Boolean hasLines       = false;
        public Decimal premiumFee     = 0;
        public Decimal dieselFee      = 0;
        public Decimal commercialFee  = 0;
        public Decimal powersportsFee = 0;
        public Decimal extraFee       = 0;   // diesel + commercial + powersports
    }
    @TestVisible
    private static Map<Id, FeeSet> loadFeeLinesByPackage(Set<Id> pkgIds) {
        Map<Id, FeeSet> byPkg = new Map<Id, FeeSet>();
        if (pkgIds == null || pkgIds.isEmpty()) {
            return byPkg;
        }
        try {
            for (Application_Package_Line_Item__c line : (List<Application_Package_Line_Item__c>) Database.queryWithBinds(
                    'SELECT Application_Package__c, Line_Type__c, Amount__c' +
                    ' FROM Application_Package_Line_Item__c' +
                    ' WHERE Application_Package__c IN :pkgIds' +
                    ' ORDER BY Application_Package__c, Sort_Order__c, Id',
                    new Map<String, Object>{ 'pkgIds' => pkgIds },
                    System.AccessLevel.SYSTEM_MODE)) {
                if (line.Application_Package__c == null) {
                    continue;
                }
                FeeSet fs = byPkg.get(line.Application_Package__c);
                if (fs == null) {
                    fs = new FeeSet();
                    byPkg.put(line.Application_Package__c, fs);
                }
                fs.hasLines = true;
                Decimal amt = line.Amount__c != null ? line.Amount__c : 0;
                if ('Premium_Fee'.equals(line.Line_Type__c)) {
                    fs.premiumFee += amt;
                } else if ('Diesel_Fee'.equals(line.Line_Type__c)) {
                    fs.dieselFee += amt;
                } else if ('Commercial_Surcharge'.equals(line.Line_Type__c)) {
                    fs.commercialFee += amt;
                } else if ('Powersports_Adjustment'.equals(line.Line_Type__c)) {
                    fs.powersportsFee += amt;
                }
            }
            for (FeeSet fs : byPkg.values()) {
                fs.extraFee = fs.dieselFee + fs.commercialFee + fs.powersportsFee;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'InvoiceDetailViewController: fee line read unavailable: ' + e.getMessage());
            byPkg.clear();
        }
        return byPkg;
    }
}