public with sharing class VehicleTestController {
    
    /**
     * Simple test method with no parameters
     */
    @AuraEnabled
    public static String testNoParams() {
        System.debug('🔍 VehicleTestController.testNoParams called');
        return 'Test successful at ' + System.now();
    }
    
    /**
     * Simple test method with String parameter
     */
    @AuraEnabled
    public static String testStringParam(String testValue) {
        System.debug('🔍 VehicleTestController.testStringParam called with: ' + testValue);
        return 'Received: ' + testValue;
    }
    
    /**
     * Simple wrapper class for String parameters
     */
    public class StringWrapper {
        @AuraEnabled public String value { get; set; }
        
        public StringWrapper() {
            // Default constructor
        }
    }
    
    /**
     * Load vehicle data method using wrapper to avoid platform bug
     */
    @AuraEnabled
    public static String loadVehicleDataWrapper(StringWrapper request) {
        System.debug('🔍 VehicleTestController.loadVehicleDataWrapper called');
        System.debug('🔍 Request object: ' + request);
        System.debug('🔍 Request is null: ' + (request == null));
        
        if (request == null) {
            return 'Error: Request object is null';
        }
        
        System.debug('🔍 Request.value: ' + request.value);
        System.debug('🔍 Request.value is blank: ' + String.isBlank(request.value));
        
        if (String.isBlank(request.value)) {
            return 'Error: Application ID value is blank';
        }
        
        String applicationId = request.value;
        System.debug('🔍 Application ID from wrapper: ' + applicationId);
        
        try {
            List<Application__c> apps = [
                SELECT Id, Name, Vehicle__c
                FROM Application__c
                WHERE Id = :applicationId
                LIMIT 1
            ];
            
            if (!apps.isEmpty()) {
                return 'Found application: ' + apps[0].Name;
            } else {
                return 'No application found';
            }
        } catch (Exception e) {
            return 'Error: ' + e.getMessage();
        }
    }
}