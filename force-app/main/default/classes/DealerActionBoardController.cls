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
            SELECT Id, Name, Customer_Name__r.Name, Vehicle_Year__c, Vehicle_Make__c,
                   Vehicle_Model__c, Vehicle_Trim__c, Vehicle_VIN__c, Payment_Status__c,
                   (SELECT Id, RecordType.Name, Contract_Cost_Price__c,
                           Contract_Cost_Price_Without_Tax__c, Tax_Amount_Cost__c, Tax_Percentage__c
                    FROM Application_Packages__r
                    WHERE Active__c = true
                    ORDER BY RecordType.Name ASC)
            FROM Application__c
            WHERE Dealer_Name__c = :dealerAccountId
              AND Application_Status__c = 'Submitted'
              AND (Payment_Status__c = null OR Payment_Status__c != 'Paid')
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];

        List<UnpaidApplicationRow> result = new List<UnpaidApplicationRow>();
        for (Application__c app : apps) {
            UnpaidApplicationRow row = new UnpaidApplicationRow();
            row.id = app.Id;
            row.appNumber = app.Name;
            row.customerName = app.Customer_Name__r != null ? app.Customer_Name__r.Name : '';

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