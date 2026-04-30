public with sharing class claimsWorksheetController {
    
    @AuraEnabled(cacheable=true)
    public static List<Part__c> getPartsForEstimate() {
        return [
            SELECT Id, Part_Name__c, Supplier_Name__c, Part_Type__c, 
                   KMS__c, Part_Cost__c, Retail_Markup__c, Quantity__c,
                   Additional_Part__c
            FROM Part__c
            WHERE Estimate__r.Name = 'E-0033'
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Service__c> getLabourForEstimate() {
        return [
            SELECT Id, Time__c, Wholesale_Labour_Rate_HR__c, Retail_Markup__c,
                   Shop_Supplies__c, Shop_Supplies_Description__c, Shop_Supplies_Markup__c
            FROM Service__c
            WHERE Estimate__r.Name = 'E-0033'
        ];
    }

    @AuraEnabled
    public static String updateParts(List<Part__c> partsToUpdate) {
        try {
            // Create a list to store the parts to update
            List<Part__c> updateList = new List<Part__c>();
            
            // Loop through the parts and create Part__c records for update
            for(Part__c part : partsToUpdate) {
                Part__c updatePart = new Part__c(
                    Id = part.Id,
                    Part_Name__c = part.Part_Name__c,
                    Part_Cost__c = part.Part_Cost__c,
                    Quantity__c = part.Quantity__c,
                    Retail_Markup__c = part.Retail_Markup__c
                );
                updateList.add(updatePart);
            }
            
            // Update the records
            if(!updateList.isEmpty()) {
                update updateList;
            }
            
            return 'Success';
        } catch(Exception e) {
            throw new AuraHandledException('Error updating parts: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String updateServices(List<Service__c> servicesToUpdate) {
        try {
            // Create a list to store the services to update
            List<Service__c> updateList = new List<Service__c>();
            
            // Loop through the services and create Service__c records for update
            for(Service__c service : servicesToUpdate) {
                Service__c updateService = new Service__c(
                    Id = service.Id,
                    Time__c = service.Time__c,
                    Wholesale_Labour_Rate_HR__c = service.Wholesale_Labour_Rate_HR__c,
                    Retail_Markup__c = service.Retail_Markup__c,
                    Shop_Supplies__c = service.Shop_Supplies__c,
                    Shop_Supplies_Description__c = service.Shop_Supplies_Description__c,
                    Shop_Supplies_Markup__c = service.Shop_Supplies_Markup__c
                );
                updateList.add(updateService);
            }
            
            // Update the records
            if(!updateList.isEmpty()) {
                update updateList;
            }
            
            return 'Success';
        } catch(Exception e) {
            throw new AuraHandledException('Error updating services: ' + e.getMessage());
        }
    }

    // Method to handle both parts and services update in a single transaction
    @AuraEnabled
    public static String saveAllRecords(List<Part__c> parts, List<Service__c> services) {
        Savepoint sp = Database.setSavepoint();
        try {
            if(parts != null && !parts.isEmpty()) {
                updateParts(parts);
            }
            if(services != null && !services.isEmpty()) {
                updateServices(services);
            }
            return 'All records updated successfully';
        } catch(Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException('Error updating records: ' + e.getMessage());
        }
    }
}