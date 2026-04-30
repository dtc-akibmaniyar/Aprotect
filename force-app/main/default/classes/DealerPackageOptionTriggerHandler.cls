public class DealerPackageOptionTriggerHandler {
    public static void updateTermsForOptions(Set<Id> packageIds) {
        if(packageIds == null || packageIds.isEmpty()) return;

        // Query all options for these packages
        List<Dealer_Package_Option__c> options = [
            SELECT Dealer_Package__c, Selection_Type__c, Retail_Price__c, Dealer_Package_Term__c
            FROM Dealer_Package_Option__c
            WHERE Dealer_Package__c IN :packageIds
        ];

        // Calculate sums for included options (package level) and optional options (term level)
        Map<Id, Decimal> includedSums = new Map<Id, Decimal>(); // Package-level sums for included options
        Map<Id, Decimal> optionalSumsByTerm = new Map<Id, Decimal>(); // Term-level sums for optional options
        Set<Id> termIds = new Set<Id>(); // Track terms that need updating for optional options

        for(Dealer_Package_Option__c opt : options) {
            if(opt.Dealer_Package__c == null) continue;
            
            if(opt.Selection_Type__c == 'Included') {
                // Included options: sum at package level (affects all terms)
                includedSums.put(
                    opt.Dealer_Package__c,
                    (includedSums.get(opt.Dealer_Package__c) == null ? 0 : includedSums.get(opt.Dealer_Package__c)) +
                    (opt.Retail_Price__c == null ? 0 : opt.Retail_Price__c)
                );
            } else if(opt.Selection_Type__c == 'Optional' && opt.Dealer_Package_Term__c != null) {
                // Optional options: sum at term level (affects only specific term)
                termIds.add(opt.Dealer_Package_Term__c);
                optionalSumsByTerm.put(
                    opt.Dealer_Package_Term__c,
                    (optionalSumsByTerm.get(opt.Dealer_Package_Term__c) == null ? 0 : optionalSumsByTerm.get(opt.Dealer_Package_Term__c)) +
                    (opt.Retail_Price__c == null ? 0 : opt.Retail_Price__c)
                );
            }
        }

        // Query all terms for these packages
        List<Dealer_Package_Term__c> termsToUpdate = [
            SELECT Id, Dealer_Package__c
            FROM Dealer_Package_Term__c
            WHERE Dealer_Package__c IN :packageIds
        ];

        List<Dealer_Package_Term__c> updates = new List<Dealer_Package_Term__c>();
        for(Dealer_Package_Term__c term : termsToUpdate) {
            // Always update included options price (package-level calculation)
            term.Included_Options_Price__c = includedSums.get(term.Dealer_Package__c) == null ? 0 : includedSums.get(term.Dealer_Package__c);
            
            // Update additional options price only if this specific term has optional options
            if(optionalSumsByTerm.containsKey(term.Id)) {
                term.Additional_Options_Price__c = optionalSumsByTerm.get(term.Id);
            } else if(termIds.size() > 0) {
                // If other terms in this package have optional options but this one doesn't, set to 0
                term.Additional_Options_Price__c = 0;
            }
            // If no optional options exist for this package, leave Additional_Options_Price__c unchanged
            
            updates.add(term);
        }

        if(!updates.isEmpty()) {
            update updates;
        }
    }
}