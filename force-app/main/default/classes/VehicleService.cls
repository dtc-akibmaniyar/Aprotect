public with sharing class VehicleService {

    // Custom DTO class for vehicle data
    public class VehicleDataDTO {
        @AuraEnabled public String stockNumber;
        @AuraEnabled public String vin;
        @AuraEnabled public String vehicleIdentificationNumberVIN;
        @AuraEnabled public String year;
        @AuraEnabled public String make;
        @AuraEnabled public String model;
        @AuraEnabled public String trim;
        @AuraEnabled public String dateVehicleSold;
        @AuraEnabled public Decimal vehiclePurchasePrice;
        @AuraEnabled public Boolean brandedRebuilt;
        @AuraEnabled public String inServiceDate;
        @AuraEnabled public Decimal odometer;
        @AuraEnabled public String odometerUnit;
        @AuraEnabled public Boolean businessCommercialUse;
        @AuraEnabled public String typeOfCommercialUse;
        @AuraEnabled public String vehicleCategory;
        @AuraEnabled public Decimal engineCC;
        @AuraEnabled public String coolingType;
        @AuraEnabled public Decimal hoursUsage;

        public VehicleDataDTO() {}
    }
    
    // Custom response class for vehicle operations
    public class VehicleResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public String recordId;
        @AuraEnabled public VehicleDataDTO data;
        
        public VehicleResponse() {}
    }
    
    // Custom DTO class for saving vehicle data
    public class VehicleSaveDTO {
        @AuraEnabled public String vehicleId;
        @AuraEnabled public String applicationId;
        @AuraEnabled public String stockNumber;
        @AuraEnabled public String vin;
        @AuraEnabled public String vehicleIdentificationNumberVIN;
        @AuraEnabled public String year;
        @AuraEnabled public String make;
        @AuraEnabled public String model;
        @AuraEnabled public String trim;
        @AuraEnabled public String dateVehicleSold;
        @AuraEnabled public Decimal vehiclePurchasePrice;
        @AuraEnabled public Boolean isBrandedRebuilt;
        @AuraEnabled public String inServiceDate;
        @AuraEnabled public Decimal odometer;
        @AuraEnabled public String odometerUnit;
        @AuraEnabled public Boolean businessCommercialUse;
        @AuraEnabled public String typeOfCommercialUse;
        @AuraEnabled public String vehicleCategory;
        @AuraEnabled public Decimal engineCC;
        @AuraEnabled public String coolingType;
        @AuraEnabled public Decimal hoursUsage;

        public VehicleSaveDTO() {}
    }
    
    // Custom save response class
    public class VehicleSaveResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public String recordId;
        @AuraEnabled public String applicationId;
        @AuraEnabled public VehicleDataDTO data;
        
        public VehicleSaveResponse() {}
    }

    /**
     * Load vehicle data for a specific application
     * @param applicationId The ID of the application
     * @return VehicleResponse containing vehicle data or error message
     */
    @AuraEnabled(cacheable=true)
    public static VehicleResponse loadVehicleData(String applicationId) {
        VehicleResponse response = new VehicleResponse();
        response.success = false;
        response.message = '';

        try {
            // Validate input
            if (String.isBlank(applicationId)) {
                response.message = 'Application ID is required';
                return response;
            }

            // Query the Application__c and related Vehicle__c
            List<Application__c> apps = [
                SELECT Id, Name, Vehicle__c, Vehicle__r.Id, Vehicle__r.Name, Vehicle__r.Stock_Number__c, Vehicle__r.VIN__c,
                       Vehicle__r.Vehicle_Identification_Number_VIN__c, Vehicle__r.Year__c,
                       Vehicle__r.Make__c, Vehicle__r.Model__c, Vehicle__r.Trim__c,
                       Vehicle__r.Date_Vehicle_Sold__c, Vehicle__r.Vehicle_Purchase_Price__c,
                       Vehicle__r.Branded_Rebuilt__c, Vehicle__r.In_Service_Date__c,
                       Vehicle__r.Odometer__c, Vehicle__r.Odometer_Unit__c,
                       Vehicle__r.Business_Commercial_Use__c, Vehicle__r.Type_of_Commercial_Use__c,
                       Vehicle__r.Vehicle_Type__c, Vehicle__r.Engine_CC__c,
                       Vehicle__r.Cooling_Type__c, Vehicle__r.Hours_Usage__c
                FROM Application__c
                WHERE Id = :applicationId
                LIMIT 1
            ];

            if (!apps.isEmpty()) {
                Application__c app = apps[0];
                Vehicle__c vehicle = app.Vehicle__r;

                if (vehicle != null) {
                    response.success = true;
                    response.recordId = vehicle.Id;
                    
                    // Create DTO with vehicle data
                    VehicleDataDTO vehicleData = new VehicleDataDTO();
                    vehicleData.stockNumber = vehicle.Stock_Number__c;
                    vehicleData.vin = vehicle.VIN__c;
                    vehicleData.vehicleIdentificationNumberVIN = vehicle.Vehicle_Identification_Number_VIN__c;
                    vehicleData.year = vehicle.Year__c;
                    vehicleData.make = vehicle.Make__c;
                    vehicleData.model = vehicle.Model__c;
                    vehicleData.trim = vehicle.Trim__c;
                    vehicleData.dateVehicleSold = vehicle.Date_Vehicle_Sold__c != null ? String.valueOf(vehicle.Date_Vehicle_Sold__c) : null;
                    vehicleData.vehiclePurchasePrice = vehicle.Vehicle_Purchase_Price__c;
                    vehicleData.brandedRebuilt = vehicle.Branded_Rebuilt__c;
                    vehicleData.inServiceDate = vehicle.In_Service_Date__c != null ? String.valueOf(vehicle.In_Service_Date__c) : null;
                    vehicleData.odometer = vehicle.Odometer__c;
                    vehicleData.odometerUnit = vehicle.Odometer_Unit__c;
                    vehicleData.businessCommercialUse = vehicle.Business_Commercial_Use__c;
                    vehicleData.typeOfCommercialUse   = vehicle.Type_of_Commercial_Use__c;
                    vehicleData.vehicleCategory       = vehicle.Vehicle_Type__c;
                    vehicleData.engineCC              = vehicle.Engine_CC__c;
                    vehicleData.coolingType           = vehicle.Cooling_Type__c;
                    vehicleData.hoursUsage            = vehicle.Hours_Usage__c;

                    response.data = vehicleData;
                    return response;
                } else {
                    response.message = 'No vehicle found for this application';
                    return response;
                }
            } else {
                response.message = 'Application not found';
                return response;
            }

        } catch (Exception e) {
            response.message = 'Error loading vehicle data: ' + e.getMessage();
            return response;
        }
    }

    /**
     * Save vehicle data (create new or update existing)
     * @param vehicleData The vehicle data to save
     * @return VehicleSaveResponse containing save result
     */
    @AuraEnabled
    public static VehicleSaveResponse saveVehicleData(VehicleSaveDTO vehicleData) {
        VehicleSaveResponse result = new VehicleSaveResponse();
        result.success = false;
        result.message = '';
        
        try {
            if (vehicleData == null) {
                throw new CalloutException('Vehicle data cannot be null');
            }
            
            String vehicleId = vehicleData.vehicleId;
            Boolean isUpdate = false;
            String applicationId = vehicleData.applicationId;

            if (String.isNotBlank(vehicleId)) {
                try {
                    // Validate the ID format
                    Id validId = vehicleId;
                    isUpdate = true;
                } catch (Exception e) {
                    isUpdate = false;
                    vehicleId = null;
                }
            }

            Vehicle__c vehicle;
            if (isUpdate && String.isNotBlank(vehicleId)) {
                vehicle = [SELECT Id FROM Vehicle__c WHERE Id = :vehicleId LIMIT 1];
            } else {
                vehicle = new Vehicle__c();
            }

            // Map DTO fields to Vehicle__c fields
            vehicle.Stock_Number__c = vehicleData.stockNumber;
            vehicle.VIN__c = vehicleData.vin;
            vehicle.Vehicle_Identification_Number_VIN__c = vehicleData.vehicleIdentificationNumberVIN;
            vehicle.Year__c = vehicleData.year;
            vehicle.Make__c = vehicleData.make;
            vehicle.Model__c = vehicleData.model;
            vehicle.Trim__c = vehicleData.trim;
            vehicle.Date_Vehicle_Sold__c = vehicleData.dateVehicleSold != null ? Date.valueOf(vehicleData.dateVehicleSold) : null;
            vehicle.Vehicle_Purchase_Price__c = vehicleData.vehiclePurchasePrice;
            vehicle.Branded_Rebuilt__c = vehicleData.isBrandedRebuilt;
            vehicle.In_Service_Date__c = vehicleData.inServiceDate != null ? Date.valueOf(vehicleData.inServiceDate) : null;
            vehicle.Odometer__c = vehicleData.odometer;
            vehicle.Odometer_Unit__c = vehicleData.odometerUnit;
            vehicle.Business_Commercial_Use__c = vehicleData.businessCommercialUse;
            vehicle.Type_of_Commercial_Use__c = vehicleData.typeOfCommercialUse;
            vehicle.Vehicle_Type__c           = vehicleData.vehicleCategory;
            vehicle.Engine_CC__c              = vehicleData.engineCC;
            vehicle.Cooling_Type__c           = vehicleData.coolingType;
            vehicle.Hours_Usage__c            = vehicleData.hoursUsage;

            // Create a meaningful vehicle name
            String vehicleName = '';
            if (String.isNotBlank(vehicle.Year__c)) vehicleName += vehicle.Year__c;
            if (String.isNotBlank(vehicle.Make__c)) vehicleName += (vehicleName != '' ? ' ' : '') + vehicle.Make__c;
            if (String.isNotBlank(vehicle.Model__c)) vehicleName += (vehicleName != '' ? ' ' : '') + vehicle.Model__c;
            if (String.isNotBlank(vehicle.Trim__c)) vehicleName += (vehicleName != '' ? ' ' : '') + vehicle.Trim__c;
            if (String.isNotBlank(vehicle.VIN__c)) vehicleName += (vehicleName != '' ? ' - ' : '') + vehicle.VIN__c;
            
            vehicle.Name = vehicleName;

            // Set hardcoded lookup fields
            vehicle.Make_Lookup__c = 'a2bG1000000t66PIAQ';
            vehicle.Model_Lookup__c = 'a2cG10000BAR7IxIQL';

            // Validate required fields
            if (String.isBlank(vehicle.VIN__c)) throw new CalloutException('VIN is required');
            if (String.isBlank(vehicle.Year__c)) throw new CalloutException('Year is required');
            if (String.isBlank(vehicle.Make__c)) throw new CalloutException('Make is required');
            if (String.isBlank(vehicle.Model__c)) throw new CalloutException('Model is required');

            // Save vehicle
            if (isUpdate) {
                update vehicle;
            } else {
                insert vehicle;
            }

            // Handle application linking
            if (String.isBlank(applicationId)) {
                Application__c newApp = new Application__c(
                    Vehicle__c = vehicle.Id,
                    Application_Status__c = 'Active'
                );
                
                try {
                    insert newApp;
                    applicationId = newApp.Id;
                } catch (Exception e) {
                    throw new CalloutException('Failed to create Application: ' + e.getMessage());
                }
            } else {
                if (!isUpdate) {
                    try {
                        Application__c existingApp = [SELECT Id, Vehicle__c FROM Application__c WHERE Id = :applicationId LIMIT 1];
                        if (existingApp.Vehicle__c != vehicle.Id) {
                            existingApp.Vehicle__c = vehicle.Id;
                            update existingApp;
                        }
                    } catch (Exception e) {
                        // Don't fail the vehicle creation if app update fails
                    }
                }
            }

            result.success = true;
            result.recordId = vehicle.Id;
            result.applicationId = applicationId;
            
            // Create response data
            VehicleDataDTO responseData = new VehicleDataDTO();
            responseData.stockNumber = vehicle.Stock_Number__c;
            responseData.vin = vehicle.VIN__c;
            responseData.vehicleIdentificationNumberVIN = vehicle.Vehicle_Identification_Number_VIN__c;
            responseData.year = vehicle.Year__c;
            responseData.make = vehicle.Make__c;
            responseData.model = vehicle.Model__c;
            responseData.trim = vehicle.Trim__c;
            responseData.dateVehicleSold = vehicle.Date_Vehicle_Sold__c != null ? String.valueOf(vehicle.Date_Vehicle_Sold__c) : null;
            responseData.vehiclePurchasePrice = vehicle.Vehicle_Purchase_Price__c;
            responseData.brandedRebuilt = vehicle.Branded_Rebuilt__c;
            responseData.inServiceDate = vehicle.In_Service_Date__c != null ? String.valueOf(vehicle.In_Service_Date__c) : null;
            responseData.odometer = vehicle.Odometer__c;
            responseData.odometerUnit = vehicle.Odometer_Unit__c;
            responseData.businessCommercialUse = vehicle.Business_Commercial_Use__c;
            responseData.typeOfCommercialUse = vehicle.Type_of_Commercial_Use__c;
            
            result.data = responseData;
            
        } catch (Exception e) {
            result.message = 'Error saving vehicle data: ' + e.getMessage();
        }

        return result;
    }

    /**
     * Get vehicle by ID
     * @param vehicleId The ID of the vehicle
     * @return VehicleResponse containing vehicle data
     */
    @AuraEnabled(cacheable=true)
    public static VehicleResponse getVehicleById(String vehicleId) {
        VehicleResponse response = new VehicleResponse();
        response.success = false;
        response.message = '';

        try {
            if (String.isBlank(vehicleId)) {
                response.message = 'Vehicle ID is required';
                return response;
            }

            List<Vehicle__c> vehicles = [
                SELECT Id, Name, Stock_Number__c, VIN__c, Vehicle_Identification_Number_VIN__c,
                       Year__c, Make__c, Model__c, Trim__c, Date_Vehicle_Sold__c,
                       Vehicle_Purchase_Price__c, Branded_Rebuilt__c, In_Service_Date__c,
                       Odometer__c, Odometer_Unit__c, Business_Commercial_Use__c, Type_of_Commercial_Use__c,
                       Vehicle_Type__c, Engine_CC__c, Cooling_Type__c, Hours_Usage__c
                FROM Vehicle__c
                WHERE Id = :vehicleId
                LIMIT 1
            ];

            if (!vehicles.isEmpty()) {
                Vehicle__c vehicle = vehicles[0];
                
                response.success = true;
                response.recordId = vehicle.Id;
                
                // Create DTO with vehicle data
                VehicleDataDTO vehicleData = new VehicleDataDTO();
                vehicleData.stockNumber = vehicle.Stock_Number__c;
                vehicleData.vin = vehicle.VIN__c;
                vehicleData.vehicleIdentificationNumberVIN = vehicle.Vehicle_Identification_Number_VIN__c;
                vehicleData.year = vehicle.Year__c;
                vehicleData.make = vehicle.Make__c;
                vehicleData.model = vehicle.Model__c;
                vehicleData.trim = vehicle.Trim__c;
                vehicleData.dateVehicleSold = vehicle.Date_Vehicle_Sold__c != null ? String.valueOf(vehicle.Date_Vehicle_Sold__c) : null;
                vehicleData.vehiclePurchasePrice = vehicle.Vehicle_Purchase_Price__c;
                vehicleData.brandedRebuilt = vehicle.Branded_Rebuilt__c;
                vehicleData.inServiceDate = vehicle.In_Service_Date__c != null ? String.valueOf(vehicle.In_Service_Date__c) : null;
                vehicleData.odometer = vehicle.Odometer__c;
                vehicleData.odometerUnit = vehicle.Odometer_Unit__c;
                vehicleData.businessCommercialUse = vehicle.Business_Commercial_Use__c;
                vehicleData.typeOfCommercialUse   = vehicle.Type_of_Commercial_Use__c;
                vehicleData.vehicleCategory       = vehicle.Vehicle_Type__c;
                vehicleData.engineCC              = vehicle.Engine_CC__c;
                vehicleData.coolingType           = vehicle.Cooling_Type__c;
                vehicleData.hoursUsage            = vehicle.Hours_Usage__c;

                response.data = vehicleData;
            } else {
                response.message = 'Vehicle not found';
            }

        } catch (Exception e) {
            response.message = 'Error fetching vehicle: ' + e.getMessage();
        }

        return response;
    }
    
    /**
     * Simple method that returns Hello World
     * @return String "Hello World"
     */
    @AuraEnabled(cacheable=true)
    public static String getHelloWorld() {
        return 'Hello World';
    }
}