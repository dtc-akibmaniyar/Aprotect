/**
 * Wrapper class for String parameters to avoid LWC-to-Apex casting bug
 * where String parameters cause: Class Cast Exception: class java.lang.String cannot be cast to class java.util.Map
 */
public class LoadVehicleRequest {
    @AuraEnabled public String applicationId { get; set; }
    
    public LoadVehicleRequest() {
        // Default constructor for deserialization
    }
}