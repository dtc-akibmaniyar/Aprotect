public without sharing class DealerActionBoardController {

    public class UnpaidPackageItem {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal price;
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
                           Contract_Cost_Price_Without_Tax__c, Tax_Amount_Cost__c, Tax_Percentage__c
                    FROM Application_Packages__r
                    WHERE Active__c = true
                    ORDER BY RecordType.Name ASC),
                   (SELECT Id, Status__c, Invoice_Due_Date__c, Total_Balance_Amount__c, Amount__c
                    FROM Invoice__r
                    ORDER BY CreatedDate DESC
                    LIMIT 1)
            FROM Application__c
            WHERE Dealer_Name__c = :dealerAccountId
              AND Application_Status__c = 'Submitted'
              AND (Payment_Status__c = null OR Payment_Status__c != 'Paid')
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];

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
            row.subTotal = subTotal;
            row.total = totalAmt;
            row.taxAmount = taxAmt;
            row.taxPercentage = taxPct;

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