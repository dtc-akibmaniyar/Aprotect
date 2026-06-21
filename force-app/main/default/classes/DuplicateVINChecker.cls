public without sharing class DuplicateVINChecker {
    public static List<Application__c> findDuplicateApplications(String vin, String currentApplicationId) {
        Map<Id, Application__c> deduped = new Map<Id, Application__c>();
        
        if (String.isBlank(vin) || vin.length() < 17) {
            return deduped.values();
        }
        
        for (Application__c app : [
            SELECT Id, Name, Application_Status__c, RecordTypeId, RecordType.Name,
                   Customer_First_Name__c, Customer_Last_Name__c, Customer_Name__c,
                   Vehicle__r.VIN__c, Vehicle__r.Vehicle_Identification_Number_VIN__c,
                   CreatedDate
            FROM Application__c 
            WHERE Vehicle__r.VIN__c = :vin 
            AND Id != :currentApplicationId
            AND Application_Status__c IN ('Pending Application', 'Active', 'Submitted', 'Draft')
            ORDER BY CreatedDate DESC
            LIMIT 50
        ]) {
            deduped.put(app.Id, app);
        }
        
        for (Application__c app : [
            SELECT Id, Name, Application_Status__c, RecordTypeId, RecordType.Name,
                   Customer_First_Name__c, Customer_Last_Name__c, Customer_Name__c,
                   Vehicle__r.VIN__c, Vehicle__r.Vehicle_Identification_Number_VIN__c,
                   CreatedDate
            FROM Application__c 
            WHERE Vehicle__r.Vehicle_Identification_Number_VIN__c = :vin 
            AND Id != :currentApplicationId
            AND Application_Status__c IN ('Pending Application', 'Active', 'Submitted', 'Draft')
            ORDER BY CreatedDate DESC
            LIMIT 50
        ]) {
            deduped.put(app.Id, app);
        }
        
        return deduped.values();
    }
}