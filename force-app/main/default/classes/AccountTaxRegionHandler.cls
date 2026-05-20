public class AccountTaxRegionHandler {
    
    // Province name variations mapping to Tax__c Name
    private static final Map<String, String> PROVINCE_ALIASES = new Map<String, String>{
        'AB' => 'Alberta', 'Alberta' => 'Alberta',
        'BC' => 'British Columbia', 'British Columbia' => 'British Columbia',
        'MB' => 'Manitoba', 'Manitoba' => 'Manitoba',
        'NB' => 'New Brunswick', 'New Brunswick' => 'New Brunswick',
        'NL' => 'Newfoundland and Labrador', 'Newfoundland and Labrador' => 'Newfoundland and Labrador', 'Newfoundland' => 'Newfoundland and Labrador',
        'NS' => 'Nova Scotia', 'Nova Scotia' => 'Nova Scotia',
        'NT' => 'Northwest Territories', 'Northwest Territories' => 'Northwest Territories',
        'NU' => 'Nunavut', 'Nunavut' => 'Nunavut',
        'ON' => 'Ontario', 'Ontario' => 'Ontario',
        'PE' => 'Prince Edward Island', 'Prince Edward Island' => 'Prince Edward Island', 'PEI' => 'Prince Edward Island',
        'QC' => 'Quebec', 'Quebec' => 'Quebec',
        'SK' => 'Saskatchewan', 'Saskatchewan' => 'Saskatchewan',
        'YT' => 'Yukon', 'Yukon' => 'Yukon'
    };
    
    public static void autoPopulateTaxRegion(List<Account> accounts, Map<Id, Account> oldMap) {
        Set<String> normalizedProvinces = new Set<String>();
        List<Account> accountsNeedingTax = new List<Account>();
        
        for (Account acc : accounts) {
            Account oldAcc = oldMap != null ? oldMap.get(acc.Id) : null;
            Boolean stateChanged = (oldAcc == null) || (acc.BillingState != oldAcc.BillingState);
            Boolean taxRegionEmpty = acc.Tax_Region__c == null;
            
            if ((stateChanged || taxRegionEmpty) && String.isNotBlank(acc.BillingState)) {
                String normalized = PROVINCE_ALIASES.get(acc.BillingState.trim());
                if (normalized != null) {
                    normalizedProvinces.add(normalized);
                    accountsNeedingTax.add(acc);
                }
            }
        }
        
        if (accountsNeedingTax.isEmpty()) return;
        
        Map<String, Id> provinceTaxMap = new Map<String, Id>();
        for (Tax__c tax : [SELECT Id, Name FROM Tax__c WHERE Name IN :normalizedProvinces]) {
            provinceTaxMap.put(tax.Name, tax.Id);
        }
        
        for (Account acc : accountsNeedingTax) {
            String normalized = PROVINCE_ALIASES.get(acc.BillingState.trim());
            if (normalized != null && provinceTaxMap.containsKey(normalized)) {
                acc.Tax_Region__c = provinceTaxMap.get(normalized);
            }
        }
    }
}