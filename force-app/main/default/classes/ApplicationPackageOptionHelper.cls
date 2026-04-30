public class ApplicationPackageOptionHelper {
    public static void updateParentAddOns(List<Application_Package_Option__c> recordList, Map<Id, Application_Package_Option__c> oldMap) {
        Set<Id> parentIds = new Set<Id>();

        for (Application_Package_Option__c option : recordList) {
            if (oldMap == null) {
                // Delete context: only recalculate for Optional options
                if (option.Application_Package__c != null && option.Selection_Type__c == 'Optional') {
                    parentIds.add(option.Application_Package__c);
                }
            } else if (!oldMap.containsKey(option.Id)) {
                // Insert context: only recalculate for Optional options
                if (option.Application_Package__c != null && option.Selection_Type__c == 'Optional') {
                    parentIds.add(option.Application_Package__c);
                }
            } else {
                // Update context - check if fields affecting Add_Ons calculations changed
                Application_Package_Option__c oldOption = oldMap.get(option.Id);
                Boolean netCostChanged = option.Net_Cost__c != oldOption.Net_Cost__c;
                Boolean markupChanged = option.Dealer_Markup__c != oldOption.Dealer_Markup__c;
                Boolean markupTypeChanged = option.Markup_Type__c != oldOption.Markup_Type__c;
                Boolean parentChanged = option.Application_Package__c != oldOption.Application_Package__c;
                Boolean typeChanged = option.Selection_Type__c != oldOption.Selection_Type__c;
                
                // Recalculate if any field affecting Add_Ons_Price__c or Add_Ons_Markup__c changed
                if ((netCostChanged || markupChanged || markupTypeChanged || parentChanged || typeChanged) 
                    && (option.Application_Package__c != null || oldOption.Application_Package__c != null)) {
                    if (option.Application_Package__c != null && option.Selection_Type__c == 'Optional') parentIds.add(option.Application_Package__c);
                    if (oldOption.Application_Package__c != null && oldOption.Selection_Type__c == 'Optional') parentIds.add(oldOption.Application_Package__c);
                }
            }
        }

        if (parentIds.isEmpty()) return;

        // Query all Optional options with their Net_Cost, Markup, and Markup_Type
        List<Application_Package_Option__c> optionalOptions = [
            SELECT Application_Package__c, Net_Cost__c, Dealer_Markup__c, Markup_Type__c
            FROM Application_Package_Option__c
            WHERE Application_Package__c IN :parentIds 
            AND Selection_Type__c = 'Optional'
            AND Net_Cost__c != null
        ];

        // Calculate sums for each parent
        Map<Id, Decimal> parentToNetCostTotal = new Map<Id, Decimal>();
        Map<Id, Decimal> parentToMarkupTotal = new Map<Id, Decimal>();

        for (Application_Package_Option__c option : optionalOptions) {
            Id parentId = option.Application_Package__c;
            Decimal netCost = option.Net_Cost__c != null ? option.Net_Cost__c : 0;
            Decimal markup = option.Dealer_Markup__c != null ? option.Dealer_Markup__c : 0;
            String markupType = option.Markup_Type__c;

            // Sum Net_Cost for Add_Ons_Price__c
            if (!parentToNetCostTotal.containsKey(parentId)) {
                parentToNetCostTotal.put(parentId, 0);
            }
            parentToNetCostTotal.put(parentId, parentToNetCostTotal.get(parentId) + netCost);

            // Calculate markup amount based on markup type
            Decimal markupAmount = 0;
            if (markupType == '$' && markup > 0) {
                // Fixed dollar markup
                markupAmount = markup;
            } else if (markupType == '%' && markup > 0) {
                // Percentage markup: Net_Cost * Markup / 100
                markupAmount = (netCost * markup) / 100;
            }
            // If markupType is null/blank or not $/%, markupAmount remains 0

            // Sum markup amounts for Add_Ons_Markup__c
            if (!parentToMarkupTotal.containsKey(parentId)) {
                parentToMarkupTotal.put(parentId, 0);
            }
            parentToMarkupTotal.put(parentId, parentToMarkupTotal.get(parentId) + markupAmount);
        }

        // Update parent Application_Package__c records
        List<Application_Package__c> parentsToUpdate = new List<Application_Package__c>();
        for (Id parentId : parentIds) {
            Application_Package__c parentToUpdate = new Application_Package__c(Id = parentId);
            
            // Set Add_Ons_Price__c to sum of Net_Cost__c
            parentToUpdate.Add_Ons_Price__c = parentToNetCostTotal.containsKey(parentId) 
                ? parentToNetCostTotal.get(parentId) 
                : 0;
            
            // Set Add_Ons_Markup__c to sum of calculated markup amounts
            parentToUpdate.Add_Ons_Markup__c = parentToMarkupTotal.containsKey(parentId) 
                ? parentToMarkupTotal.get(parentId) 
                : 0;
            
            parentsToUpdate.add(parentToUpdate);
        }
        
        if (!parentsToUpdate.isEmpty()) {
            try {
                update parentsToUpdate;
                System.debug('✅ Updated Add_Ons_Price__c and Add_Ons_Markup__c for ' + parentsToUpdate.size() + ' Application_Package__c records');
            } catch (DmlException e) {
                System.debug('❌ Failed to update parent Application_Package__c: ' + e.getMessage());
            }
        }
    }
}