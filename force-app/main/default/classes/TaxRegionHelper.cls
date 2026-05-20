public class TaxRegionHelper {
    
    /**
     * Populate tax fields on an Application_Package__c from the dealer's Tax_Region.
     * @param appPackage The Application_Package__c to populate
     * @param dealerId The dealer Account ID
     * @return The tax rate applied (for use in price calculations)
     */
    public static Decimal applyDealerTax(Application_Package__c appPackage, Id dealerId) {
        if (dealerId == null) return null;
        
        List<Account> dealers = [
            SELECT Id, Tax_Region__c, Tax_Region__r.Total_Tax_Rate__c
            FROM Account 
            WHERE Id = :dealerId 
            LIMIT 1
        ];
        
        if (!dealers.isEmpty() && dealers[0].Tax_Region__c != null) {
            appPackage.Tax_Region__c = dealers[0].Tax_Region__c;
            Decimal taxRate = dealers[0].Tax_Region__r.Total_Tax_Rate__c;
            if (taxRate != null) {
                appPackage.Tax_Percentage__c = taxRate;
            }
            return taxRate;
        }
        return null;
    }
    
    /**
     * Bulk version - populate tax for multiple packages from the same dealer.
     * Uses a single query.
     */
    public static Decimal applyDealerTaxBulk(List<Application_Package__c> packages, Id dealerId) {
        if (dealerId == null || packages == null || packages.isEmpty()) return null;
        
        List<Account> dealers = [
            SELECT Id, Tax_Region__c, Tax_Region__r.Total_Tax_Rate__c
            FROM Account 
            WHERE Id = :dealerId 
            LIMIT 1
        ];
        
        if (!dealers.isEmpty() && dealers[0].Tax_Region__c != null) {
            Id taxRegionId = dealers[0].Tax_Region__c;
            Decimal taxRate = dealers[0].Tax_Region__r.Total_Tax_Rate__c;
            for (Application_Package__c pkg : packages) {
                pkg.Tax_Region__c = taxRegionId;
                if (taxRate != null) {
                    pkg.Tax_Percentage__c = taxRate;
                }
            }
            return taxRate;
        }
        return null;
    }
}