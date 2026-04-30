public with sharing class PackageOptionBulkController {
    
    @AuraEnabled(cacheable=true)
    public static List<OptionWrapper> getAvailableOptions() {
        List<OptionWrapper> options = new List<OptionWrapper>();
        for(Option__c opt : [SELECT Id, Name 
                           FROM Option__c 
                           ORDER BY Name ASC]) {
            options.add(new OptionWrapper(opt.Id, opt.Name));
        }
        return options;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<PackageOptionWrapper> getPackageOptions(Id packageId) {
        // Query only Package Options related to this Package
        List<PackageOptionWrapper> wrappers = new List<PackageOptionWrapper>();
        
        List<Package_Option__c> packageOptions = [
            SELECT Id, 
                   Option__c, 
                   Option__r.Name, 
                   Inclusion_Text__c, 
                   Exclusion_Text__c
            FROM Package_Option__c
            WHERE Package__c = :packageId
            ORDER BY Option__r.Name ASC
        ];

        System.debug('Package Options found: ' + packageOptions.size());
        System.debug('For Package Id: ' + packageId);
        
        for(Package_Option__c po : packageOptions) {
            wrappers.add(new PackageOptionWrapper(po));
        }
        
        return wrappers;
    }
    
    @AuraEnabled
    public static void savePackageOption(Id packageId, Id optionId, String inclusionText, String exclusionText) {
        // Check for existing package option
        List<Package_Option__c> existingOptions = [
            SELECT Id 
            FROM Package_Option__c 
            WHERE Package__c = :packageId 
            AND Option__c = :optionId
            LIMIT 1
        ];
        
        if(existingOptions.isEmpty()) {
            Package_Option__c po = new Package_Option__c(
                Package__c = packageId,
                Option__c = optionId,
                Inclusion_Text__c = inclusionText,
                Exclusion_Text__c = exclusionText,
                Selection_Type__c = 'Included'
            );
            insert po;
        }
    }
    
    public class OptionWrapper {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        
        public OptionWrapper(Id optId, String optName) {
            this.value = optId;
            this.label = optName;
        }
    }
    
    public class PackageOptionWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String optionId;
        @AuraEnabled public String optionName;
        @AuraEnabled public String inclusionText;
        @AuraEnabled public String exclusionText;
        
        public PackageOptionWrapper(Package_Option__c po) {
            this.id = po.Id;
            this.optionId = po.Option__c;
            this.optionName = po.Option__r.Name;
            this.inclusionText = po.Inclusion_Text__c;
            this.exclusionText = po.Exclusion_Text__c;
        }
    }
}