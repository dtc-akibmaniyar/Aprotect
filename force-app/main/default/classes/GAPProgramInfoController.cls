public without sharing class GAPProgramInfoController {
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getGAPProgramInfo() {
        Map<String, String> result = new Map<String, String>();
        try {
            List<GAP_Program_Info__mdt> records = [
                SELECT Content__c, Portal_URL__c 
                FROM GAP_Program_Info__mdt 
                WHERE DeveloperName = 'Default' 
                LIMIT 1
            ];
            if (!records.isEmpty()) {
                result.put('content', records[0].Content__c);
                result.put('portalUrl', records[0].Portal_URL__c);
            }
        } catch (Exception e) {
            System.debug('Error fetching GAP Program Info: ' + e.getMessage());
        }
        return result;
    }
}