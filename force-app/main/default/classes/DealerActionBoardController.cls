public without sharing class DealerActionBoardController {

    /** Suffix the invoice uses to mark a package option line. */
    private static final String OPTIONAL_SUFFIX = ' (Optional)';
    /** The package's own tax row — surfaced separately, never as an option. */
    private static final String TAX_LINE_NAME = 'tax';

    public class UnpaidPackageItem {
        // ── Original contract (unchanged) ────────────────────────────────
        @AuraEnabled public String id;
        @AuraEnabled public String name;      // package record type, as before
        @AuraEnabled public Decimal price;    // billed package cost, as before

        // ── Additive: product detail for the products cell ───────────────
        @AuraEnabled public String packageName;   // resolved package name
        @AuraEnabled public String recordTypeName;
        @AuraEnabled public String termName;

        // ── Additive: priced breakdown for the expanded drawer ───────────
        @AuraEnabled public Decimal basePrice;
        @AuraEnabled public Decimal taxAmount;
        @AuraEnabled public Boolean hasTax;
        @AuraEnabled public Decimal optionsTotal;
        @AuraEnabled public Decimal displayTotal;
        @AuraEnabled public Decimal billedAmount;
        @AuraEnabled public Boolean hasBillingVariance;
        @AuraEnabled public Integer optionCount;
        @AuraEnabled public List<UnpaidPackageOption> options;
    }

    public class UnpaidPackageOption {
        @AuraEnabled public String optionId;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String selectionType;
        @AuraEnabled public Boolean isBilled;
    }

    public class UnpaidApplicationRow {
        @AuraEnabled public String id;
        @AuraEnabled public String appNumber;
        @AuraEnabled public String customerName;
        @AuraEnabled public String vehicleInfo;
        @AuraEnabled public String vin;
        @AuraEnabled public String paymentStatus;
        @AuraEnabled public List<UnpaidPackageItem> packages;
        @AuraEnabled public Decimal subTotal;
        @AuraEnabled public Decimal total;
        @AuraEnabled public Decimal taxAmount;
        @AuraEnabled public Decimal taxPercentage;
        // New fields for Make Payment Modal refactor
        @AuraEnabled public String invoiceId;
        @AuraEnabled public Boolean hasInvoice;
        @AuraEnabled public String invoiceStatus;
        @AuraEnabled public Decimal invoiceBalance;
        @AuraEnabled public Date invoiceDueDate;
        @AuraEnabled public Integer agingDays;
        @AuraEnabled public String customerPhone;
        @AuraEnabled public String customerEmail;
        @AuraEnabled public String odometer;
        @AuraEnabled public DateTime appCreatedDate;
    }

    // ── Package / option resolution (mirrors the invoice renderers) ──────

    /** Same precedence the invoice uses to label a package. */
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
        return pkg.RecordType != null ? pkg.RecordType.Name : '';
    }

    /** Same precedence the invoice uses to label a package term. */
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

    /** Case/space-insensitive key — same normalisation the invoice uses. */
    private static String normalize(String value) {
        return value == null ? '' : value.trim().toLowerCase();
    }

    private static String stripOptionalSuffix(String value) {
        if (value == null) {
            return '';
        }
        String trimmed = value.trim();
        if (trimmed.endsWith(OPTIONAL_SUFFIX)) {
            return trimmed.substring(0, trimmed.length() - OPTIONAL_SUFFIX.length());
        }
        return trimmed;
    }

    /**
     * The term is normally carried by the package term lookup, but many packages
     * in this org have no term lookup — the chosen term survives only as a
     * Application_Package_Line_Item__c row ("24 Months/Unlimited KM"). When the
     * lookup is blank, fall back to the line that is not a billed option so the
     * drawer can still show the term next to the package name.
     */
    private static String deriveTermName(List<Application_Package_Line_Item__c> lines,
                                         Map<String, Decimal> optionPrices) {
        if (lines == null || lines.isEmpty()) {
            return '';
        }
        String fallback = '';
        for (Application_Package_Line_Item__c line : lines) {
            String key = normalize(line.Name);
            if (String.isBlank(key) || key == TAX_LINE_NAME) {
                continue;
            }
            if (optionPrices != null && optionPrices.containsKey(key)) {
                continue;   // this line is a priced option, never the term
            }
            if (key.contains('month') || key.contains('km') || key.contains('mile')) {
                return line.Name.trim();
            }
            if (String.isBlank(fallback)) {
                fallback = line.Name.trim();
            }
        }
        return fallback;
    }

    @AuraEnabled
    public static List<UnpaidApplicationRow> getUnpaidApplications() {
        Id userId = UserInfo.getUserId();
        List<User> users = [SELECT ContactId FROM User WHERE Id = :userId LIMIT 1];

        if (users.isEmpty() || users[0].ContactId == null) {
            return new List<UnpaidApplicationRow>();
        }

        List<Contact> contacts = [SELECT AccountId FROM Contact WHERE Id = :users[0].ContactId LIMIT 1];

        if (contacts.isEmpty() || contacts[0].AccountId == null) {
            return new List<UnpaidApplicationRow>();
        }

        Id dealerAccountId = contacts[0].AccountId;

        List<Application__c> apps = [
            SELECT Id, Name, CreatedDate,
                   Customer_Name__r.Name, Customer_Name__r.Phone,
                   Vehicle_Year__c, Vehicle_Make__c,
                   Vehicle_Model__c, Vehicle_Trim__c, Vehicle_VIN__c,
                   Odometer__c,
                   Payment_Status__c,
                   (SELECT Id, RecordType.Name, Contract_Cost_Price__c,
                           Contract_Cost_Price_Without_Tax__c, Tax_Amount_Cost__c, Tax_Percentage__c,
                           Package__r.Name, Dealer_Package__r.Name, Dealer_Package__r.Package__r.Name,
                           Package_Term__r.Name, Dealer_Package_Term__r.Name,
                           Dealer_Package_Term__r.Package_Term__r.Name,
                           Dealer_Package_Price__c, Add_Ons_Price__c
                    FROM Application_Packages__r
                    WHERE Active__c = true
                    ORDER BY RecordType.Name ASC),
                   (SELECT Id, Status__c, Invoice_Due_Date__c, Total_Balance_Amount__c, Amount__c
                    FROM Invoice__r
                    ORDER BY CreatedDate DESC)
            FROM Application__c
            WHERE Dealer_Name__c = :dealerAccountId
              AND Application_Status__c = 'Submitted'
              AND (Payment_Status__c = null OR Payment_Status__c != 'Paid')
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];

        // ── Pre-load what the drawer needs, in two bulk queries ──────────
        Set<Id> pkgIds = new Set<Id>();
        Set<Id> invoiceIds = new Set<Id>();
        for (Application__c app : apps) {
            for (Application_Package__c pkg : app.Application_Packages__r) {
                pkgIds.add(pkg.Id);
            }
            for (Invoice__c inv : app.Invoice__r) {
                invoiceIds.add(inv.Id);
            }
        }

        // Option selections recorded on the application package, by line name.
        // (Application_Package_Line_Item__c carries the chosen option and term names.)
        Map<Id, List<Application_Package_Line_Item__c>> linesByPkg =
            new Map<Id, List<Application_Package_Line_Item__c>>();
        if (!pkgIds.isEmpty()) {
            for (Application_Package_Line_Item__c line : [
                    SELECT Id, Name, Application_Package__c
                    FROM Application_Package_Line_Item__c
                    WHERE Application_Package__c IN :pkgIds
                    ORDER BY Application_Package__c, Name]) {
                if (line.Application_Package__c == null) {
                    continue;
                }
                if (!linesByPkg.containsKey(line.Application_Package__c)) {
                    linesByPkg.put(line.Application_Package__c,
                        new List<Application_Package_Line_Item__c>());
                }
                linesByPkg.get(line.Application_Package__c).add(line);
            }
        }

        // Billed option amounts: the invoice materialises each priced option as a
        // line named "<Option Name> (Optional)" with no package link. That is the
        // amount actually charged, so it wins over catalogue pricing.
        Map<Id, Map<String, Decimal>> optionPriceByInvoice =
            new Map<Id, Map<String, Decimal>>();
        if (!invoiceIds.isEmpty()) {
            for (Invoice_Line_Item__c li : [
                    SELECT Id, Name, Description__c, Amount__c, Invoice__c
                    FROM Invoice_Line_Item__c
                    WHERE Invoice__c IN :invoiceIds
                      AND Application_Package__c = null
                      AND Amount__c != null
                      AND Amount__c != 0
                    ORDER BY Invoice__c, Id]) {
                String label = String.isNotBlank(li.Description__c) ? li.Description__c : li.Name;
                if (label == null || !label.trim().endsWith(OPTIONAL_SUFFIX)) {
                    continue;
                }
                String key = normalize(stripOptionalSuffix(label));
                if (String.isBlank(key)) {
                    continue;
                }
                Map<String, Decimal> byName = optionPriceByInvoice.get(li.Invoice__c);
                if (byName == null) {
                    byName = new Map<String, Decimal>();
                    optionPriceByInvoice.put(li.Invoice__c, byName);
                }
                if (!byName.containsKey(key)) {
                    byName.put(key, li.Amount__c);
                }
            }
        }

        // Invoice-style tax. The invoice puts the tax INSIDE each line's
        // Amount__c, so the sub-total is the invoice balance minus this tax and
        // sub-total + HST always reconciles to the invoice's own TOTAL DUE.
        Map<Id, Decimal> invTaxByInvoice = new Map<Id, Decimal>();
        Map<Id, Decimal> invTaxPctByInvoice = new Map<Id, Decimal>();
        if (!invoiceIds.isEmpty()) {
            for (Invoice_Line_Item__c li : [
                    SELECT Invoice__c, Amount__c, Balance_Amount__c, Paid_Amount__c,
                           Tax_Amount__c, Tax_Percentage__c
                    FROM Invoice_Line_Item__c
                    WHERE Invoice__c IN :invoiceIds]) {
                Decimal gross = li.Amount__c != null ? li.Amount__c : 0;
                Decimal bal = li.Balance_Amount__c;
                if (bal == null) {
                    Decimal paid = li.Paid_Amount__c != null ? li.Paid_Amount__c : 0;
                    bal = gross - paid;
                }
                if (bal < 0) {
                    bal = 0;
                }
                Decimal tax = li.Tax_Amount__c != null ? li.Tax_Amount__c : 0;
                if (tax > 0 && gross > 0 && bal != gross) {
                    // partially paid line: keep only the unpaid share of its tax
                    tax = (tax * bal / gross).setScale(2, System.RoundingMode.HALF_UP);
                }
                if (tax > bal) {
                    tax = bal;
                }
                Decimal taxRunning = invTaxByInvoice.containsKey(li.Invoice__c)
                    ? invTaxByInvoice.get(li.Invoice__c) : 0;
                invTaxByInvoice.put(li.Invoice__c, taxRunning + tax);
                if (li.Tax_Percentage__c != null && li.Tax_Percentage__c > 0
                        && !invTaxPctByInvoice.containsKey(li.Invoice__c)) {
                    invTaxPctByInvoice.put(li.Invoice__c, li.Tax_Percentage__c);
                }
            }
        }

        List<UnpaidApplicationRow> result = new List<UnpaidApplicationRow>();
        for (Application__c app : apps) {
            // Post-filter: skip if invoice exists, is Paid, and balance <= 0
            if (!app.Invoice__r.isEmpty()) {
                Invoice__c inv = app.Invoice__r[0];
                if (inv.Status__c == 'Paid' && (inv.Total_Balance_Amount__c == null || inv.Total_Balance_Amount__c <= 0)) {
                    continue;
                }
            }

            UnpaidApplicationRow row = new UnpaidApplicationRow();
            row.id = app.Id;
            row.appNumber = app.Name;
            row.customerName = app.Customer_Name__r != null ? app.Customer_Name__r.Name : '';
            row.appCreatedDate = app.CreatedDate;
            row.customerPhone = app.Customer_Name__r != null ? app.Customer_Name__r.Phone : '';
            row.customerEmail = ''; // Account does not have a standard Email field
            row.odometer = app.Odometer__c != null ? String.valueOf(app.Odometer__c) : '';

            List<String> parts = new List<String>();
            if (app.Vehicle_Year__c != null) parts.add(String.valueOf(app.Vehicle_Year__c));
            if (String.isNotBlank(app.Vehicle_Make__c)) parts.add(app.Vehicle_Make__c);
            if (String.isNotBlank(app.Vehicle_Model__c)) parts.add(app.Vehicle_Model__c);
            if (String.isNotBlank(app.Vehicle_Trim__c)) parts.add(app.Vehicle_Trim__c);
            row.vehicleInfo = String.join(parts, '/');

            row.vin = app.Vehicle_VIN__c;
            row.paymentStatus = app.Payment_Status__c;

            Map<String, Decimal> optPrices = null;
            if (!app.Invoice__r.isEmpty()) {
                optPrices = optionPriceByInvoice.get(app.Invoice__r[0].Id);
            }

            List<UnpaidPackageItem> pkgList = new List<UnpaidPackageItem>();
            Decimal subTotal = 0;
            Decimal totalAmt = 0;
            Decimal taxAmt = 0;
            Decimal taxPct = 0;

            for (Application_Package__c pkg : app.Application_Packages__r) {
                UnpaidPackageItem item = new UnpaidPackageItem();
                item.id = pkg.Id;
                item.name = pkg.RecordType != null ? pkg.RecordType.Name : '';
                item.price = pkg.Contract_Cost_Price__c != null ? pkg.Contract_Cost_Price__c : 0;
                item.recordTypeName = item.name;
                item.packageName = resolvePackageName(pkg);
                List<Application_Package_Line_Item__c> lines = linesByPkg.get(pkg.Id);
                // Prefer the package term lookup; fall back to the recorded term line.
                String resolvedTerm = resolveTermName(pkg);
                item.termName = String.isNotBlank(resolvedTerm)
                    ? resolvedTerm
                    : deriveTermName(lines, optPrices);
                item.billedAmount = item.price;
                item.optionCount = 0;
                item.optionsTotal = 0;
                item.options = new List<UnpaidPackageOption>();

                Decimal addOns = pkg.Add_Ons_Price__c != null ? pkg.Add_Ons_Price__c : 0;
                Decimal base = 0;
                if (pkg.Dealer_Package_Price__c != null && pkg.Dealer_Package_Price__c > 0) {
                    base = pkg.Dealer_Package_Price__c;
                } else if (item.price - addOns > 0) {
                    base = item.price - addOns;
                } else {
                    base = item.price;
                }
                item.basePrice = base;

                // Tax already carried inside the billed package cost. It is shown
                // separately so base + options + tax reconciles to the package
                // amount the remittance charges.
                Decimal tax = 0;
                if (pkg.Contract_Cost_Price_Without_Tax__c != null
                        && item.price > pkg.Contract_Cost_Price_Without_Tax__c) {
                    Decimal taxDelta = item.price - pkg.Contract_Cost_Price_Without_Tax__c;
                    tax = taxDelta.setScale(2, System.RoundingMode.HALF_UP);
                }
                item.taxAmount = tax;
                item.hasTax = tax > 0;

                // Option rows: every recorded line that is not the term itself.
                String termKey = normalize(item.termName);
                Decimal optsTotal = 0;
                Boolean allPriced = true;
                if (lines != null) {
                    Set<String> seen = new Set<String>();
                    for (Application_Package_Line_Item__c line : lines) {
                        String lineKey = normalize(line.Name);
                        if (String.isBlank(lineKey) || lineKey == termKey || lineKey == TAX_LINE_NAME) {
                            continue;   // neither the term nor the tax row is an option
                        }
                        if (seen.contains(lineKey)) {
                            continue;
                        }
                        seen.add(lineKey);

                        UnpaidPackageOption opt = new UnpaidPackageOption();
                        opt.optionId = line.Id;
                        opt.name = line.Name.trim();
                        opt.selectionType = 'Optional';
                        Decimal amt = null;
                        if (optPrices != null) {
                            amt = optPrices.get(lineKey);
                        }
                        opt.amount = amt;
                        opt.isBilled = amt != null;
                        if (amt == null) {
                            allPriced = false;
                        } else {
                            optsTotal += amt;
                        }
                        item.options.add(opt);
                    }
                }

                item.optionCount = item.options.size();
                item.optionsTotal = optsTotal;
                // The drawer total is the honest sum: base + every priced option.
                // When an option carries no billed price we cannot itemise, so the
                // billed package cost is shown instead and no variance is claimed.
                if (!item.options.isEmpty() && allPriced) {
                    item.displayTotal = (base + optsTotal + tax).setScale(2, System.RoundingMode.HALF_UP);
                } else {
                    item.displayTotal = item.price;
                }
                item.hasBillingVariance = item.displayTotal.setScale(2, System.RoundingMode.HALF_UP)
                    != item.price.setScale(2, System.RoundingMode.HALF_UP);

                pkgList.add(item);

                if (pkg.Contract_Cost_Price_Without_Tax__c != null) {
                    subTotal += pkg.Contract_Cost_Price_Without_Tax__c;
                }
                if (pkg.Contract_Cost_Price__c != null) {
                    totalAmt += pkg.Contract_Cost_Price__c;
                }
                if (taxAmt == 0 && pkg.Tax_Amount_Cost__c != null) {
                    taxAmt = pkg.Tax_Amount_Cost__c;
                }
                if (taxPct == 0 && pkg.Tax_Percentage__c != null) {
                    taxPct = pkg.Tax_Percentage__c;
                }
            }

            row.packages = pkgList;

            // The invoice is the source of truth: the TOTAL column, the aging
            // tiles and the summary must equal what the invoice asks the dealer
            // to pay, not the package contract price.
            Boolean hasInvoice = !app.Invoice__r.isEmpty();
            Decimal invoiceDue = 0;
            Decimal invTax = 0;
            Decimal invPct = 0;
            Boolean anyUnpaidInvoice = false;
            for (Invoice__c inv : app.Invoice__r) {
                if (inv.Status__c == 'Paid') {
                    continue;
                }
                anyUnpaidInvoice = true;
                // an application can carry more than one open invoice: sum them,
                // never take the first one and drop the rest
                invoiceDue += inv.Total_Balance_Amount__c != null
                    ? inv.Total_Balance_Amount__c
                    : (inv.Amount__c != null ? inv.Amount__c : 0);
                if (invTaxByInvoice.containsKey(inv.Id)) {
                    invTax += invTaxByInvoice.get(inv.Id);
                }
                if (invPct == 0 && invTaxPctByInvoice.containsKey(inv.Id)) {
                    invPct = invTaxPctByInvoice.get(inv.Id);
                }
            }

            if (hasInvoice) {
                Decimal due = invoiceDue;
                if (!anyUnpaidInvoice) {
                    due = 0;
                }
                due = due.setScale(2, System.RoundingMode.HALF_UP);
                Decimal tax = invTax.setScale(2, System.RoundingMode.HALF_UP);
                if (tax > due) {
                    tax = due;
                }
                if (tax < 0) {
                    tax = 0;
                }
                row.subTotal = (due - tax).setScale(2, System.RoundingMode.HALF_UP);
                row.taxAmount = tax;
                row.taxPercentage = invPct;
                row.total = due;
            } else {
                // No invoice yet: createRemittanceForm raises one from the package
                // contract price, so that is what the drawer must show.
                row.subTotal = subTotal;
                row.taxAmount = taxAmt;
                row.taxPercentage = taxPct;
                row.total = totalAmt;
            }

            // Invoice fields from subquery
            if (!app.Invoice__r.isEmpty()) {
                Invoice__c inv = app.Invoice__r[0];
                row.invoiceId = inv.Id;
                row.hasInvoice = true;
                row.invoiceStatus = inv.Status__c;
                row.invoiceBalance = inv.Total_Balance_Amount__c;
                row.invoiceDueDate = inv.Invoice_Due_Date__c;
                if (inv.Invoice_Due_Date__c != null) {
                    Integer daysBetween = Date.today().daysBetween(inv.Invoice_Due_Date__c) * -1;
                    row.agingDays = daysBetween < 0 ? 0 : daysBetween;
                } else {
                    row.agingDays = 0;
                }
            } else {
                row.hasInvoice = false;
                row.invoiceId = null;
                row.invoiceStatus = null;
                row.invoiceBalance = null;
                row.invoiceDueDate = null;
                row.agingDays = 0;
            }

            result.add(row);
        }
        return result;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Notice__c> getCompanyNotices() {
        return [
            SELECT Id, Name, Notice_Message__c, CreatedDate
            FROM Notice__c
            WHERE IsActive__c = TRUE 
            AND RecordType.DeveloperName = 'Company_Specific_Notice'
            ORDER BY CreatedDate DESC
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Notice__c> getDealerNotices() {
        // Get the logged-in user's contact account
        Id userId = UserInfo.getUserId();
        List<User> users = [SELECT ContactId FROM User WHERE Id = :userId LIMIT 1];
        
        if (users.isEmpty() || users[0].ContactId == null) {
            return new List<Notice__c>();
        }
        
        List<Contact> contacts = [SELECT AccountId FROM Contact WHERE Id = :users[0].ContactId LIMIT 1];
        
        if (contacts.isEmpty() || contacts[0].AccountId == null) {
            return new List<Notice__c>();
        }
        
        Id dealerAccountId = contacts[0].AccountId;
        
        // Query notices through the junction object
        List<Dealer_Notice_Assignment__c> assignments = [
            SELECT Notice__c, Notice__r.Id, Notice__r.Name, Notice__r.Notice_Message__c, Notice__r.CreatedDate
            FROM Dealer_Notice_Assignment__c
            WHERE Dealer_Name__c = :dealerAccountId
            AND Notice__r.IsActive__c = TRUE
            AND Notice__r.RecordType.DeveloperName = 'Dealer_Specific_Notice'
            ORDER BY Notice__r.CreatedDate DESC
        ];
        
        List<Notice__c> notices = new List<Notice__c>();
        for (Dealer_Notice_Assignment__c assignment : assignments) {
            notices.add(assignment.Notice__r);
        }
        
        return notices;
    }
}