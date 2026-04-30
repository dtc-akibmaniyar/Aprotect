public without sharing class ApplicationCancellationController {
    
    /**
     * @description Wrapper for cancellation form vehicle details
     */
    public class CancellationVehicleInfo {
        @AuraEnabled public String vehicleName { get; set; }
        @AuraEnabled public String vehicleVIN { get; set; }
        @AuraEnabled public String vehicleOdometer { get; set; }
        @AuraEnabled public String vehiclePrice { get; set; }
    }

    /**
     * @description Get vehicle information for cancellation form
     * @param applicationId The ID of the application
     * @return CancellationVehicleInfo Vehicle details
     */
    @AuraEnabled(cacheable=true)
    public static CancellationVehicleInfo getVehicleInfoForCancellation(Id applicationId) {
        try {
            Application__c app = [
                SELECT Id, 
                    Vehicle__r.Year__c, 
                    Vehicle__r.Make__c, 
                    Vehicle__r.Model__c, 
                    Vehicle__r.VIN__c,
                    Vehicle__r.Odometer__c, 
                    Vehicle__r.Odometer_Unit__c, 
                    Vehicle__r.Vehicle_Purchase_Price__c,
                    Vehicle__r.Name
                FROM Application__c 
                WHERE Id = :applicationId 
                LIMIT 1
            ];

            CancellationVehicleInfo info = new CancellationVehicleInfo();
            
            if (app.Vehicle__r != null) {
                // Build vehicle name
                String year = app.Vehicle__r.Year__c != null ? String.valueOf(app.Vehicle__r.Year__c) : '';
                String make = app.Vehicle__r.Make__c != null ? app.Vehicle__r.Make__c : '';
                String model = app.Vehicle__r.Model__c != null ? app.Vehicle__r.Model__c : '';
                info.vehicleName = app.Vehicle__r.Name;
                
                // VIN
                info.vehicleVIN = app.Vehicle__r.VIN__c != null ? app.Vehicle__r.VIN__c : '';
                
                // Odometer
                if (app.Vehicle__r.Odometer__c != null) {
                    String odometerUnit = app.Vehicle__r.Odometer_Unit__c != null ? app.Vehicle__r.Odometer_Unit__c : 'km';
                    info.vehicleOdometer = String.valueOf(app.Vehicle__r.Odometer__c.format()) + ' ' + odometerUnit;
                } else {
                    info.vehicleOdometer = '';
                }
                
                // Purchase Price
                if (app.Vehicle__r.Vehicle_Purchase_Price__c != null) {
                    info.vehiclePrice = '$' + app.Vehicle__r.Vehicle_Purchase_Price__c.format();
                } else {
                    info.vehiclePrice = '';
                }
            }
            
            return info;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving vehicle information: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
public static List<Policy__c> getPolicies() {

    // Query both policy record types
    List<Policy__c> policies = [
        SELECT Id, RecordType.DeveloperName, Policy_Text__c,Name
        FROM Policy__c
        WHERE RecordType.DeveloperName IN ('Cancellation_Policy', 'Privacy_Policy_Terms_Conditions')
        
    ];
    return policies;
}

    /**
     * Save Application_Policy__c records for an application and mark the
     * Application__c record as Canceled.
     * @param applicationId Id of the Application__c record
     * @param policies List of policy wrappers from client containing Name, Policy_Text__c and Privacy_Terms_Accepted__c
     */
    @AuraEnabled
    public static void savePoliciesAndCancel(Id applicationId, List<PolicyWrapper> policies) {
        if (applicationId == null) {
            throw new AuraHandledException('Application Id is required');
        }

        try {
            List<Application_Policy__c> toInsert = new List<Application_Policy__c>();
            if (policies != null) {
                for (PolicyWrapper pw : policies) {
                    Application_Policy__c ap = new Application_Policy__c();
                    ap.Name = pw.Name;
                    ap.Policy_Text__c = pw.policyText;
                    ap.Privacy_Terms_Accepted__c = pw.privacyTermsAccepted;
                    ap.Application__c = applicationId;
                    ap.Submission_Date_And_Time__c = System.now();
                    toInsert.add(ap);
                }
            }

            if (!toInsert.isEmpty()) {
                insert toInsert;
            }

            // Mark application as Cancelled
            Application__c appToUpdate = new Application__c(Id = applicationId, Application_Status__c = 'Cancelled');
            update appToUpdate;
        } catch (Exception e) {
            system.debug('Error:: '+ e.getMessage());
            throw new AuraHandledException('Error saving policies or updating application: ' + e.getMessage());
        }
    }

    // Wrapper class used to receive policy data from LWC
    public class PolicyWrapper {
        @AuraEnabled public String Name { get; set; }
        @AuraEnabled public String policyText { get; set; }
        @AuraEnabled public Boolean privacyTermsAccepted { get; set; }
    }

}