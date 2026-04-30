public without sharing class VinDecoderService {
    
    // DTO class for Auto.dev API response
    public class AutodevResponse {
        public String vin;
        public Boolean vinValid;
        public String wmi;
        public String origin;
        public String squishVin;
        public String checkDigit;
        public Boolean checksum;
        public String type;
        public String make;
        public String model;
        public String trim;
        public String style;
        public AutodevVehicle vehicle;
        public AutodevApi api;
        public AutodevLinks links;
        public AutodevUser user;
    }
    
    // Nested vehicle object from Auto.dev
    public class AutodevVehicle {
        public String vin;
        public Integer year;
        public String make;
        public String model;
        public String manufacturer;
    }
    
    // Nested API info object
    public class AutodevApi {
        public String name;
        public String description;
        public String url;
        public String account;
        public String docs;
        public String type;
        public String fromField;
    }
    
    // Nested links object
    public class AutodevLinks {
        public String home;
        public String self;
        public String prev;
    }
    
    // Nested user object
    public class AutodevUser {
        public String name;
        public String email;
        public String image;
        public Boolean authenticated;
        public String plan;
        public String userAgent;
        public String ip;
        public String isp;
        public String flag;
        public String zipcode;
        public String city;
        public String region;
        public String country;
        public String continent;
        public String requestId;
        public String localTime;
        public String timezone;
        public String edgeLocation;
        public Integer edgeDistanceKilometers;
        public Integer latencyMilliseconds;
        public Integer recentInteractions;
        public Integer trustScore;
        public Integer serviceLatency;
    }
    
    // DTO class for NHTSA API response
    public class NhtsaResponse {
        public Integer Count;
        public String Message;
        public String SearchCriteria;
        public List<NhtsaResult> Results;
    }
    
    public class NhtsaResult {
        public String Variable;
        public String Value;
        public Integer VariableId;
        public String VariableName;
    }
    
    // DTO class for Blackbook API response (flexible structure to handle various response formats)
    public class BlackbookResponse {
        // Common fields that might be in the response
        public String vin;
        public String year;
        public String make;
        public String model;
        public String trim;
        public String bodyStyle;
        public String bodyClass;
        public String manufacturer;
        public String vehicleType;
        public String series;
        public String style;
        public String origin;
        public String engineSize;
        public String engineCylinders;
        public String transmission;
        public String driveType;
        public String fuelType;
        public String doors;
        public String seats;
        // Allow for additional dynamic fields
        public Map<String, Object> additionalFields;
    }
    
    // DTO class for decoded vehicle data
    public class DecodedVehicleData {
        // Core vehicle identification
        public String make;
        public String model;
        public String year;
        public String trim;
        public String bodyClass;
        public String manufacturerName;
        public String vehicleType;
        public String series;
        public String style;
        public String origin;
        
        // Engine and performance
        public String engineModel;
        public String engineCylinders;
        public String engineDisplacement;
        public String engineDisplacementCC;
        public String engineDisplacementCI;
        public String enginePower;
        public String enginePowerTo;
        public String engineStrokeCycles;
        public String engineConfiguration;
        public String engineManufacturer;
        public String engineBrakeFrom;
        public String engineBrakeTo;
        public String otherEngineInfo;
        public String turbo;
        public String topSpeed;
        public String electrificationLevel;
        public String coolingType;
        public String valveTrainDesign;
        
        // Transmission and drivetrain
        public String transmissionStyle;
        public String transmissionSpeeds;
        public String driveType;
        public String axles;
        public String axleConfiguration;
        
        // Fuel system
        public String fuelType;
        public String fuelTypeSecondary;
        public String fuelDeliveryType;
        public String fuelTankType;
        public String fuelTankMaterial;
        
        // Dimensions and weight
        public String doors;
        public String windows;
        public String wheelBase;
        public String wheelBaseFrom;
        public String wheelBaseTo;
        public String wheelBaseType;
        public String trackWidth;
        public String curbWeight;
        public String gvwr;
        public String gvwrFrom;
        public String gvwrTo;
        public String gcvwrFrom;
        public String gcvwrTo;
        public String bedLength;
        public String bedType;
        public String cabType;
        
        // Seating and interior
        public String seats;
        public String seatRows;
        public String seatBeltType;
        public String otherRestraintSystemInfo;
        public String pretensioner;
        
        // Exterior
        public String color;
        
        // Safety features
        public String abs;
        public String esc;
        public String tractionControl;
        public String airbagLocations;
        public String frontAirbagLocations;
        public String sideAirbagLocations;
        public String curtainAirbagLocations;
        public String seatCushionAirbagLocations;
        public String kneeAirbagLocations;
        public String tpmsType;
        public String activeSafetySystemNote;
        
        // Advanced safety systems
        public String adaptiveCruiseControl;
        public String crashImminentBraking;
        public String forwardCollisionWarning;
        public String dynamicBrakeSupport;
        public String pedestrianAutomaticEmergencyBraking;
        public String blindSpotWarning;
        public String laneDepartureWarning;
        public String laneKeepingAssistance;
        public String blindSpotIntervention;
        public String laneCenteringAssistance;
        public String backupCamera;
        public String parkingAssist;
        public String rearCrossTrafficAlert;
        public String rearAutomaticEmergencyBraking;
        public String automaticCrashNotification;
        public String daytimeRunningLight;
        public String headlampLightSource;
        public String semiautomaticHeadlampBeamSwitching;
        public String adaptiveDrivingBeam;
        public String autoReverseSystem;
        public String automaticPedestrianAlertingSound;
        public String eventDataRecorder;
        public String keylessIgnition;
        public String saeAutomationLevelFrom;
        public String saeAutomationLevelTo;
        
        // Braking system
        public String brakeSystemType;
        public String brakeSystemDescription;
        public String combinedBrakingSystem;
        public String wheelieMitigation;
        
        // Wheels and tires
        public String numberOfWheels;
        public String wheelSizeFront;
        public String wheelSizeRear;
        
        // Battery and electric systems
        public String batteryType;
        public String otherBatteryInfo;
        public String batteryCellsPerModule;
        public String batteryCurrentFrom;
        public String batteryVoltageFrom;
        public String batteryEnergyFrom;
        public String batteryCurrentTo;
        public String batteryVoltageTo;
        public String batteryEnergyTo;
        public String batteryModulesPerPack;
        public String batteryPacksPerVehicle;
        public String evDriveUnit;
        public String chargerLevel;
        public String chargerPower;
        
        // Entertainment and comfort
        public String entertainmentSystem;
        public String steeringLocation;
        
        // Manufacturing information
        public String plantCountry;
        public String plantState;
        public String plantCity;
        public String plantCompanyName;
        public String destinationMarket;
        public String nonLandUse;
        
        // Vehicle classification
        public String trim2;
        public String series2;
        public String note;
        public String basePrice;
        public String vehicleDescriptor;
        public String suggestedVin;
        public String errorCode;
        public String possibleValues;
        public String additionalErrorText;
        public String errorText;
        
        // Trailer information
        public String trailerTypeConnection;
        public String trailerBodyType;
        public String trailerLength;
        public String otherTrailerInfo;
        
        // Motorcycle information
        public String customMotorcycleType;
        public String motorcycleSuspensionType;
        public String motorcycleChassisType;
        public String otherMotorcycleInfo;
        
        // Bus information
        public String busLength;
        public String busFloorConfigurationType;
        public String busType;
        public String otherBusInfo;
    }
    
    // Response wrapper for VIN decode operation
    public class VinDecodeResponse {
        public Boolean success;
        public String message;
        public DecodedVehicleData vehicleData;
        public String errorCode;
        public String apiSource; // Track which API was used: 'BLACKBOOK', 'AUTO_DEV', 'NHTSA', or 'NONE'
        public String rawResponse; // Raw JSON response from the API (for debugging/inspection)
        
        public VinDecodeResponse() {
            this.success = false;
            this.message = '';
            this.vehicleData = new DecodedVehicleData();
            this.errorCode = '';
            this.apiSource = 'NONE';
            this.rawResponse = '';
        }
    }
    
    /**
     * Main method to decode VIN using Blackbook API only
     * NHTSA fallback is currently disabled (commented out)
     * @param vin The VIN to decode
     * @return VinDecodeResponse with decoded vehicle data
     */
    public static VinDecodeResponse decodeVin(String vin) {
        // Validate VIN format first
        if (!isValidVinFormat(vin)) {
            VinDecodeResponse errorResponse = new VinDecodeResponse();
            if (String.isBlank(vin)) {
                errorResponse.message = 'VIN cannot be empty';
                errorResponse.errorCode = 'INVALID_VIN';
            } else if (vin.trim().length() != 17) {
                errorResponse.message = 'VIN must be exactly 17 characters long';
                errorResponse.errorCode = 'INVALID_VIN_LENGTH';
            } else {
                errorResponse.message = 'VIN contains invalid characters';
                errorResponse.errorCode = 'INVALID_VIN_CHARS';
            }
            return errorResponse;
        }
        
        // Try Blackbook API only (NHTSA fallback disabled)
        // NOTE: If Remote Site Setting is not configured, this will fail
        VinDecodeResponse blackbookResponse;
        try {
            blackbookResponse = decodeVinBlackbook(vin);
            System.debug('🔍 Blackbook Response - Success: ' + blackbookResponse.success + ', Message: ' + blackbookResponse.message + ', ErrorCode: ' + blackbookResponse.errorCode);
            
            if (blackbookResponse.success) {
                blackbookResponse.apiSource = 'BLACKBOOK';
                blackbookResponse.message = 'VIN decoded successfully';
                return blackbookResponse;
            }
        } catch (Exception e) {
            // If Blackbook throws an unexpected exception, log it
            System.debug('❌ Unexpected exception in Blackbook decode: ' + e.getMessage());
            blackbookResponse = new VinDecodeResponse();
            blackbookResponse.success = false;
            blackbookResponse.message = 'Blackbook exception: ' + e.getMessage();
        }
        
        // Blackbook failed - NHTSA fallback is disabled
        System.debug('🔄 Blackbook failed for VIN: ' + vin);
        if (blackbookResponse != null) {
            System.debug('🔄 Blackbook failure reason: ' + blackbookResponse.message);
        }
        
        // NHTSA FALLBACK DISABLED - Commented out for now
        // System.debug('🔄 Blackbook failed, falling back to NHTSA for VIN: ' + vin);
        // VinDecodeResponse nhtsaResponse = decodeVinNhtsa(vin);
        // System.debug('🔍 NHTSA Response - Success: ' + nhtsaResponse.success + ', Message: ' + nhtsaResponse.message + ', ErrorCode: ' + nhtsaResponse.errorCode);
        // if (nhtsaResponse.success) {
        //     nhtsaResponse.apiSource = 'NHTSA';
        //     nhtsaResponse.message = 'VIN decoded successfully';
        //     return nhtsaResponse;
        // }
        
        // Blackbook failed (NHTSA fallback disabled)
        VinDecodeResponse failureResponse = new VinDecodeResponse();
        failureResponse.success = false;
        failureResponse.message = 'Unable to decode VIN using Blackbook API. Please enter vehicle information manually.';
        failureResponse.errorCode = 'BLACKBOOK_FAILED';
        failureResponse.apiSource = 'NONE';
        return failureResponse;
    }
    
    /**
     * Decode VIN using Blackbook API (Primary)
     * @param vin The VIN to decode
     * @return VinDecodeResponse with decoded vehicle data
     */
    // private static VinDecodeResponse decodeVinBlackbook(String vin) {
    //     VinDecodeResponse response = new VinDecodeResponse();
        
    //     try {
    //         // Blackbook API configuration
    //         String endpoint = 'https://service.canadianblackbook.com/UsedCarWS/CanUsedAPI/UsedVehicle/VIN/';
    //         String username = 'AProductAPI';
    //         String password = 'MB7LHBB4X4MU';
    //         String cleanVin = vin.trim().toUpperCase();
            
    //         // Build full endpoint URL
    //         String fullUrl = endpoint + cleanVin;
            
    //         // Make HTTP callout to Blackbook API
    //         Http http = new Http();
    //         HttpRequest request = new HttpRequest();
    //         request.setEndpoint(fullUrl);
    //         request.setMethod('GET');
    //         request.setTimeout(15000); // 15 second timeout
    //         request.setHeader('Accept', 'application/json');
    //         request.setHeader('Content-Type', 'application/json');
            
    //         // Set Basic Authentication
    //         Blob headerValue = Blob.valueOf(username + ':' + password);
    //         String authorizationHeader = 'Basic ' + EncodingUtil.base64Encode(headerValue);
    //         request.setHeader('Authorization', authorizationHeader);
            
    //         HttpResponse httpResponse = http.send(request);
            private static VinDecodeResponse decodeVinBlackbook(String vin) {
    VinDecodeResponse response = new VinDecodeResponse();
    
        try {
            String cleanVin = vin.trim().toUpperCase();
            
            Http http = new Http();
            HttpRequest request = new HttpRequest();
            request.setEndpoint('callout:canadianblackbook/UsedCarWS/CanUsedAPI/UsedVehicle/VIN/' + cleanVin);
            request.setMethod('GET');
            request.setTimeout(15000);
            request.setHeader('Accept', 'application/json');
            request.setHeader('Content-Type', 'application/json');
            
            System.debug('Request:::: ' + request);
            
            HttpResponse httpResponse = http.send(request);
            System.debug('httpResponse:::: ' + httpResponse);
            
            if (httpResponse.getStatusCode() == 200) {
                String responseBody = httpResponse.getBody();
                
                // Store raw JSON response for access
                response.rawResponse = responseBody;
                
                // Log raw Blackbook JSON response for debugging
                System.debug('🔍 Blackbook Raw JSON Response: ' + responseBody);
                
                if (String.isNotBlank(responseBody)) {
                    try {
                        // Parse JSON response - handle flexible structure
                        Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
                        
                        // Check for Blackbook API errors in the response
                        if (jsonMap.containsKey('error_count') && jsonMap.get('error_count') != null) {
                            Integer errorCount = (Integer) jsonMap.get('error_count');
                            if (errorCount > 0 && jsonMap.containsKey('message_list')) {
                                List<Object> messageList = (List<Object>) jsonMap.get('message_list');
                                List<String> errorMessages = new List<String>();
                                
                                for (Object msgObj : messageList) {
                                    Map<String, Object> msg = (Map<String, Object>) msgObj;
                                    if (msg.containsKey('type') && String.valueOf(msg.get('type')) == 'Error') {
                                        String description = msg.containsKey('description') ? String.valueOf(msg.get('description')) : 'Unknown error';
                                        String code = msg.containsKey('code') ? String.valueOf(msg.get('code')) : '';
                                        errorMessages.add(description + (String.isNotBlank(code) ? ' (Code: ' + code + ')' : ''));
                                    }
                                }
                                
                                if (!errorMessages.isEmpty()) {
                                    String errorMsg = 'Blackbook API Error: ' + String.join(errorMessages, '; ');
                                    System.debug('❌ ' + errorMsg);
                                    System.debug('❌ Full Blackbook Response: ' + responseBody);
                                    response.message = errorMsg + ' | Raw Response: ' + responseBody;
                                    response.errorCode = 'BLACKBOOK_API_ERROR';
                                    return response; // Return early, will fall back to NHTSA
                                }
                            }
                        }
                        
                        // Check if used_vehicles data is available and extract vehicle data
                        Map<String, Object> vehicleDataMap = null;
                        if (jsonMap.containsKey('used_vehicles')) {
                            Map<String, Object> usedVehicles = (Map<String, Object>) jsonMap.get('used_vehicles');
                            if (usedVehicles.containsKey('data_available') && usedVehicles.get('data_available') == false) {
                                System.debug('⚠️ Blackbook: data_available = false');
                                System.debug('⚠️ Full Blackbook Response: ' + responseBody);
                                response.message = 'Blackbook: Vehicle data not available. Raw Response: ' + responseBody;
                                response.errorCode = 'NO_DATA_AVAILABLE';
                                return response; // Return early, will fall back to NHTSA
                            }
                            
                            // Extract vehicle data from used_vehicle_list array
                            if (usedVehicles.containsKey('used_vehicle_list') && usedVehicles.get('used_vehicle_list') instanceof List<Object>) {
                                List<Object> vehicleList = (List<Object>) usedVehicles.get('used_vehicle_list');
                                if (vehicleList != null && !vehicleList.isEmpty()) {
                                    // Get the first vehicle from the list
                                    Object firstVehicle = vehicleList[0];
                                    if (firstVehicle instanceof Map<String, Object>) {
                                        vehicleDataMap = (Map<String, Object>) firstVehicle;
                                        System.debug('✅ Found vehicle data in used_vehicle_list, size: ' + vehicleList.size());
                                    }
                                }
                            }
                        }
                        
                        // If we didn't find vehicle data in used_vehicle_list, try root level
                        if (vehicleDataMap == null) {
                            System.debug('⚠️ No vehicle data in used_vehicle_list, trying root level');
                            vehicleDataMap = jsonMap;
                        }
                        
                        // Convert to DecodedVehicleData
                        DecodedVehicleData vehicleData = parseBlackbookResponse(vehicleDataMap);
                        
                        // Check if we got meaningful data
                        if (String.isNotBlank(vehicleData.make) && String.isNotBlank(vehicleData.model)) {
                            response.success = true;
                            response.message = 'VIN decoded successfully';
                            response.vehicleData = vehicleData;
                            response.apiSource = 'BLACKBOOK';
                        } else {
                            System.debug('⚠️ Blackbook returned incomplete data - Make: ' + vehicleData.make + ', Model: ' + vehicleData.model);
                            System.debug('⚠️ Full Blackbook Response: ' + responseBody);
                            response.message = 'Blackbook returned incomplete vehicle data. Raw Response: ' + responseBody;
                            response.errorCode = 'NO_DATA_FOUND';
                        }
                    } catch (JSONException e) {
                        System.debug('❌ Blackbook JSON parsing error: ' + e.getMessage());
                        System.debug('❌ Response body: ' + responseBody);
                        response.message = 'Blackbook returned invalid JSON format. Raw Response: ' + responseBody;
                        response.errorCode = 'JSON_PARSE_ERROR';
                    }
                } else {
                    response.message = 'Blackbook returned empty response';
                    response.errorCode = 'EMPTY_RESPONSE';
                }
            } else if (httpResponse.getStatusCode() == 401) {
                String responseBody = httpResponse.getBody();
                response.rawResponse = responseBody;
                response.message = 'Blackbook authentication failed';
                response.errorCode = 'AUTH_ERROR';
            } else if (httpResponse.getStatusCode() == 404) {
                String responseBody = httpResponse.getBody();
                response.rawResponse = responseBody;
                response.message = 'VIN not found in Blackbook database';
                response.errorCode = 'VIN_NOT_FOUND';
            } else {
                String responseBody = httpResponse.getBody();
                response.rawResponse = responseBody;
                response.message = 'Blackbook service unavailable (HTTP ' + httpResponse.getStatusCode() + ')';
                response.errorCode = 'SERVICE_UNAVAILABLE';
            }
            
        } catch (System.CalloutException e) {
            // Remote Site Setting not configured or network issue
            System.debug('❌ Blackbook CalloutException (likely Remote Site Setting not configured): ' + e.getMessage());
            response.message = 'Blackbook callout failed (check Remote Site Settings)';
            response.errorCode = 'CALLOUT_ERROR';
            response.success = false;
        } catch (Exception e) {
            System.debug('❌ Blackbook API Error: ' + e.getMessage());
            System.debug('❌ Stack Trace: ' + e.getStackTraceString());
            System.debug('❌ Error Type: ' + e.getTypeName());
            // Don't set success = true, let it fall through to NHTSA
            response.message = 'Blackbook error: ' + e.getMessage();
            response.errorCode = 'DECODE_ERROR';
            response.success = false; // Explicitly set to false
        }
        
        return response;
    }
    
    /**
     * Helper method to safely get string value from JSON map
     * @param jsonMap The JSON map
     * @param key The key to look up
     * @return String value or null
     */
    private static String getStringValueFromMap(Map<String, Object> jsonMap, String key) {
        if (jsonMap.containsKey(key) && jsonMap.get(key) != null) {
            Object value = jsonMap.get(key);
            return String.valueOf(value);
        }
        return null;
    }
    
    /**
     * Parse Blackbook API response into DecodedVehicleData
     * Handles flexible JSON structure
     * @param jsonMap The parsed JSON response as a map
     * @return DecodedVehicleData object
     */
    private static DecodedVehicleData parseBlackbookResponse(Map<String, Object> jsonMap) {
        DecodedVehicleData vehicleData = new DecodedVehicleData();
        
        // Debug: Log available keys to understand Blackbook structure
        System.debug('🔍 Blackbook vehicle data keys: ' + jsonMap.keySet());
        
        // Core vehicle identification - Map Blackbook field names
        vehicleData.year = getStringValueFromMap(jsonMap, 'model_year');
        vehicleData.make = getStringValueFromMap(jsonMap, 'make');
        vehicleData.model = getStringValueFromMap(jsonMap, 'model');
        vehicleData.trim = getStringValueFromMap(jsonMap, 'series'); // Blackbook uses 'series' for trim
        vehicleData.bodyClass = getStringValueFromMap(jsonMap, 'style'); // Blackbook uses 'style' for body class
        vehicleData.manufacturerName = getStringValueFromMap(jsonMap, 'make');
        vehicleData.vehicleType = getStringValueFromMap(jsonMap, 'class_name'); // Use class_name as vehicle type
        vehicleData.series = getStringValueFromMap(jsonMap, 'series');
        vehicleData.style = getStringValueFromMap(jsonMap, 'style');
        vehicleData.origin = getStringValueFromMap(jsonMap, 'country'); // Blackbook provides country
        
        // Engine information - Map Blackbook field names
        vehicleData.engineCylinders = getStringValueFromMap(jsonMap, 'cylinders');
        vehicleData.engineDisplacement = getStringValueFromMap(jsonMap, 'engine_displacement');
        vehicleData.engineModel = getStringValueFromMap(jsonMap, 'engine_description');
        vehicleData.enginePower = getStringValueFromMap(jsonMap, 'base_hp');
        vehicleData.enginePowerTo = getStringValueFromMap(jsonMap, 'torque');
        vehicleData.otherEngineInfo = getStringValueFromMap(jsonMap, 'oil_cap') != null ? 
                                      'Oil Capacity: ' + getStringValueFromMap(jsonMap, 'oil_cap') + 'L' : null;
        
        // Transmission and drivetrain - Map Blackbook field names
        vehicleData.transmissionStyle = getStringValueFromMap(jsonMap, 'transmission'); // 'A' = Automatic
        vehicleData.transmissionSpeeds = getStringValueFromMap(jsonMap, 'num_gears');
        vehicleData.driveType = getStringValueFromMap(jsonMap, 'drivetrain'); // 'FWD' = Front Wheel Drive
        
        // Fuel system - Map Blackbook field names
        vehicleData.fuelType = getStringValueFromMap(jsonMap, 'fuel_type');
        vehicleData.fuelDeliveryType = getStringValueFromMap(jsonMap, 'fuel_delivery');
        vehicleData.fuelTankType = getStringValueFromMap(jsonMap, 'fuel_cap') != null ? 
                                   'Capacity: ' + getStringValueFromMap(jsonMap, 'fuel_cap') + 'L' : null;
        
        // Dimensions and interior - Map Blackbook field names
        vehicleData.doors = getStringValueFromMap(jsonMap, 'ext_doors');
        vehicleData.seats = getStringValueFromMap(jsonMap, 'seat_cap');
        vehicleData.seatRows = getStringValueFromMap(jsonMap, 'seats'); // Detailed seat information
        vehicleData.wheelBase = getStringValueFromMap(jsonMap, 'wheel_base') != null ? 
                               getStringValueFromMap(jsonMap, 'wheel_base') + ' mm' : null;
        // Store GVWR as number only (without units) for form field mapping
        vehicleData.gvwr = getStringValueFromMap(jsonMap, 'gvw');
        
        // Color/Exterior - Check multiple possible field names
        vehicleData.color = getStringValueFromMap(jsonMap, 'color') != null ? 
                          getStringValueFromMap(jsonMap, 'color') : 
                          (getStringValueFromMap(jsonMap, 'exterior_color') != null ? 
                           getStringValueFromMap(jsonMap, 'exterior_color') : 
                           (getStringValueFromMap(jsonMap, 'paint') != null ? 
                            getStringValueFromMap(jsonMap, 'paint') : 
                            (getStringValueFromMap(jsonMap, 'paint_code') != null ? 
                             getStringValueFromMap(jsonMap, 'paint_code') : null)));
        
        // Additional Blackbook-specific fields
        vehicleData.vehicleDescriptor = getStringValueFromMap(jsonMap, 'class_name');
        vehicleData.destinationMarket = getStringValueFromMap(jsonMap, 'country');
        vehicleData.plantCountry = getStringValueFromMap(jsonMap, 'country');
        vehicleData.plantState = getStringValueFromMap(jsonMap, 'state');
        
        // Additional Blackbook fields - store in available fields
        // MPG information
        if (getStringValueFromMap(jsonMap, 'hwy_mpg') != null && getStringValueFromMap(jsonMap, 'city_mpg') != null) {
            vehicleData.topSpeed = 'Highway: ' + getStringValueFromMap(jsonMap, 'hwy_mpg') + ' L/100km, City: ' + getStringValueFromMap(jsonMap, 'city_mpg') + ' L/100km';
        }
        
        // Tire information
        if (getStringValueFromMap(jsonMap, 'tire_size') != null) {
            vehicleData.wheelSizeFront = getStringValueFromMap(jsonMap, 'tire_size');
        }
        
        // Airbag information
        if (getStringValueFromMap(jsonMap, 'airbags') != null) {
            vehicleData.airbagLocations = getStringValueFromMap(jsonMap, 'airbags');
        }
        
        // Sunroof/Moonroof
        if (getStringValueFromMap(jsonMap, 'moon_sunroof') != null) {
            vehicleData.entertainmentSystem = getStringValueFromMap(jsonMap, 'moon_sunroof');
        }
        
        // Navigation
        if (getStringValueFromMap(jsonMap, 'navigation') != null) {
            String navInfo = getStringValueFromMap(jsonMap, 'navigation');
            if (String.isNotBlank(vehicleData.entertainmentSystem)) {
                vehicleData.entertainmentSystem = vehicleData.entertainmentSystem + '; Navigation: ' + navInfo;
            } else {
                vehicleData.entertainmentSystem = 'Navigation: ' + navInfo;
            }
        }
        
        // Warranty information - combine all warranty fields
        List<String> warrantyInfo = new List<String>();
        if (getStringValueFromMap(jsonMap, 'basic_warranty') != null) {
            warrantyInfo.add('Basic: ' + getStringValueFromMap(jsonMap, 'basic_warranty'));
        }
        if (getStringValueFromMap(jsonMap, 'powertrain_warranty') != null) {
            warrantyInfo.add('Powertrain: ' + getStringValueFromMap(jsonMap, 'powertrain_warranty'));
        }
        if (getStringValueFromMap(jsonMap, 'anti_corrosion_warranty') != null) {
            warrantyInfo.add('Anti-Corrosion: ' + getStringValueFromMap(jsonMap, 'anti_corrosion_warranty'));
        }
        if (getStringValueFromMap(jsonMap, 'road_assist_warranty') != null) {
            warrantyInfo.add('Road Assist: ' + getStringValueFromMap(jsonMap, 'road_assist_warranty'));
        }
        if (!warrantyInfo.isEmpty()) {
            vehicleData.note = String.join(warrantyInfo, ' | ');
        }
        
        // Price information
        if (getStringValueFromMap(jsonMap, 'msrp') != null) {
            vehicleData.basePrice = getStringValueFromMap(jsonMap, 'msrp');
        }
        
        // Price includes
        if (getStringValueFromMap(jsonMap, 'price_includes') != null) {
            if (String.isNotBlank(vehicleData.note)) {
                vehicleData.note = vehicleData.note + ' | Price Includes: ' + getStringValueFromMap(jsonMap, 'price_includes');
            } else {
                vehicleData.note = 'Price Includes: ' + getStringValueFromMap(jsonMap, 'price_includes');
            }
        }
        
        // Try to extract from nested objects if present
        if (jsonMap.containsKey('vehicle') && jsonMap.get('vehicle') instanceof Map<String, Object>) {
            Map<String, Object> vehicleObj = (Map<String, Object>) jsonMap.get('vehicle');
            if (String.isBlank(vehicleData.year)) vehicleData.year = getStringValueFromMap(vehicleObj, 'year');
            if (String.isBlank(vehicleData.make)) vehicleData.make = getStringValueFromMap(vehicleObj, 'make');
            if (String.isBlank(vehicleData.model)) vehicleData.model = getStringValueFromMap(vehicleObj, 'model');
            if (String.isBlank(vehicleData.manufacturerName)) vehicleData.manufacturerName = getStringValueFromMap(vehicleObj, 'manufacturer');
        }
        
        // Try to extract from 'data' object if present
        if (jsonMap.containsKey('data') && jsonMap.get('data') instanceof Map<String, Object>) {
            Map<String, Object> dataObj = (Map<String, Object>) jsonMap.get('data');
            if (String.isBlank(vehicleData.year)) vehicleData.year = getStringValueFromMap(dataObj, 'year');
            if (String.isBlank(vehicleData.make)) vehicleData.make = getStringValueFromMap(dataObj, 'make');
            if (String.isBlank(vehicleData.model)) vehicleData.model = getStringValueFromMap(dataObj, 'model');
            if (String.isBlank(vehicleData.trim)) vehicleData.trim = getStringValueFromMap(dataObj, 'trim');
            if (String.isBlank(vehicleData.bodyClass)) {
                vehicleData.bodyClass = getStringValueFromMap(dataObj, 'bodyClass') != null ? 
                                       getStringValueFromMap(dataObj, 'bodyClass') : 
                                       getStringValueFromMap(dataObj, 'bodyStyle');
            }
        }
        
        return vehicleData;
    }
    
    /**
     * Decode VIN using Auto.dev API
     * @param vin The VIN to decode
     * @return VinDecodeResponse with decoded vehicle data
     */
    private static VinDecodeResponse decodeVinAutodev(String vin) {
        VinDecodeResponse response = new VinDecodeResponse();
        
        try {
            // Get Auto.dev configuration from Custom Metadata
            VIN_Decoder_Service__mdt config = VIN_Decoder_Service__mdt.getInstance('Auto_Dev');
            
            if (config == null || String.isBlank(config.API_Key__c) || String.isBlank(config.End_Point__c)) {
                response.message = 'Auto.dev API configuration not found';
                response.errorCode = 'CONFIG_ERROR';
                return response;
            }
            
            String apiKey = config.API_Key__c;
            String endpoint = config.End_Point__c;
            String cleanVin = vin.trim().toUpperCase();
            
            // Make HTTP callout to Auto.dev API
            Http http = new Http();
            HttpRequest request = new HttpRequest();
            request.setEndpoint(endpoint + cleanVin);
            request.setMethod('GET');
            request.setTimeout(10000); // 10 second timeout
            request.setHeader('Accept', 'application/json');
            request.setHeader('Authorization', 'Bearer ' + apiKey);
            request.setHeader('Content-Type', 'application/json');
            
            
            HttpResponse httpResponse = http.send(request);
            
            if (httpResponse.getStatusCode() == 200) {
                String responseBody = httpResponse.getBody();
                
                // Parse JSON response
                AutodevResponse autodevData = (AutodevResponse) JSON.deserialize(responseBody, AutodevResponse.class);
                
                if (autodevData != null && String.isNotBlank(autodevData.make) && String.isNotBlank(autodevData.model)) {
                    // Convert Auto.dev response to our standard format
                    DecodedVehicleData vehicleData = new DecodedVehicleData();
                    vehicleData.make = autodevData.make;
                    vehicleData.model = autodevData.model;
                    vehicleData.trim = autodevData.trim;
                    vehicleData.bodyClass = autodevData.style;
                    vehicleData.vehicleType = autodevData.type;
                    
                    // Get year from nested vehicle object
                    if (autodevData.vehicle != null && autodevData.vehicle.year != null) {
                        vehicleData.year = String.valueOf(autodevData.vehicle.year);
                    }
                    
                    // Get manufacturer from nested vehicle object
                    if (autodevData.vehicle != null && String.isNotBlank(autodevData.vehicle.manufacturer)) {
                        vehicleData.manufacturerName = autodevData.vehicle.manufacturer;
                    }
                    
                    // Map additional Auto.dev fields
                    vehicleData.origin = autodevData.origin;
                    
                    response.success = true;
                    response.message = 'VIN decoded successfully';
                    response.vehicleData = vehicleData;
                    response.apiSource = 'AUTO_DEV';
                } else {
                    response.message = 'Auto.dev returned incomplete data';
                    response.errorCode = 'NO_DATA_FOUND';
                }
            } else if (httpResponse.getStatusCode() == 429) {
                response.message = 'Auto.dev rate limit reached';
                response.errorCode = 'RATE_LIMIT';
            } else {
                response.message = 'Auto.dev service unavailable (HTTP ' + httpResponse.getStatusCode() + ')';
                response.errorCode = 'SERVICE_UNAVAILABLE';
            }
            
        } catch (Exception e) {
            response.message = 'Auto.dev error: ' + e.getMessage();
            response.errorCode = 'DECODE_ERROR';
        }
        
        return response;
    }
    
    /**
     * Decode VIN using NHTSA vPIC API (Fallback)
     * @param vin The VIN to decode
     * @return VinDecodeResponse with decoded vehicle data
     */
    private static VinDecodeResponse decodeVinNhtsa(String vin) {
        VinDecodeResponse response = new VinDecodeResponse();
        String fullUrl = ''; // Declare outside try block for catch block access
        
        try {
            // Hardcoded NHTSA endpoint with JSON format
            String endpoint = 'https://vpic.nhtsa.dot.gov/api/vehicles/DecodeVin/';
            
            // Clean VIN (remove spaces, convert to uppercase)
            String cleanVin = vin.trim().toUpperCase();
            
            // Build the full URL with JSON format
            fullUrl = endpoint + cleanVin + '?format=json';
            
            // Make HTTP callout to NHTSA API
            Http http = new Http();
            HttpRequest request = new HttpRequest();
            request.setEndpoint(fullUrl);
            request.setMethod('GET');
            request.setTimeout(10000); // 10 second timeout
            request.setHeader('Accept', 'application/json');
            
            
            HttpResponse httpResponse = http.send(request);
            
            if (httpResponse.getStatusCode() == 200) {
                String responseBody = httpResponse.getBody();
                
                // Log raw NHTSA JSON response
                System.debug('🔍 NHTSA Raw JSON Response: ' + responseBody);
                
                // Parse JSON response from NHTSA
                NhtsaResponse nhtsaResponse = (NhtsaResponse) JSON.deserialize(responseBody, NhtsaResponse.class);
                
                if (nhtsaResponse != null && nhtsaResponse.Results != null && !nhtsaResponse.Results.isEmpty()) {
                    // Parse the results into our vehicle data structure
                    DecodedVehicleData vehicleData = parseNhtsaResults(nhtsaResponse.Results);
                    
                    // Check if we got meaningful data
                    if (String.isNotBlank(vehicleData.make) && String.isNotBlank(vehicleData.model)) {
                        response.success = true;
                        response.message = 'VIN decoded successfully';
                        response.vehicleData = vehicleData;
                        response.apiSource = 'NHTSA';
                    } else {
                        response.message = 'VIN not found or no vehicle data available';
                        response.errorCode = 'NO_DATA_FOUND';
                    }
                } else {
                    response.message = 'Invalid response from VIN decoder service';
                    response.errorCode = 'INVALID_RESPONSE';
                }
            } else {
                response.message = 'VIN decoder service unavailable (HTTP ' + httpResponse.getStatusCode() + ')';
                response.errorCode = 'SERVICE_UNAVAILABLE';
            }
            
        } catch (Exception e) {
            response.message = 'Error decoding VIN: ' + e.getMessage();
            response.errorCode = 'DECODE_ERROR';
        }
        
        return response;
    }
    
    
    /**
     * Parse NHTSA API results into our vehicle data structure
     * @param results List of NHTSA result objects
     * @return DecodedVehicleData object
     */
    private static DecodedVehicleData parseNhtsaResults(List<NhtsaResult> results) {
        DecodedVehicleData vehicleData = new DecodedVehicleData();
        
        // Create a map for quick lookup - include all values, even null ones for debugging
        Map<String, String> resultMap = new Map<String, String>();
        for (NhtsaResult result : results) {
            if (String.isNotBlank(result.Variable)) {
                // Store all values, including null and empty strings for complete data capture
                resultMap.put(result.Variable, result.Value);
            }
        }
        
        // Core vehicle identification
        vehicleData.make = resultMap.get('Make');
        vehicleData.model = resultMap.get('Model');
        vehicleData.year = resultMap.get('Model Year');
        vehicleData.trim = resultMap.get('Trim');
        vehicleData.bodyClass = resultMap.get('Body Class');
        vehicleData.manufacturerName = resultMap.get('Manufacturer Name');
        vehicleData.vehicleType = resultMap.get('Vehicle Type');
        vehicleData.series = resultMap.get('Series');
        vehicleData.origin = resultMap.get('Origin');
        vehicleData.style = resultMap.get('Style');
        
        // Engine and performance
        vehicleData.engineModel = resultMap.get('Engine Model');
        vehicleData.engineCylinders = resultMap.get('Engine Number of Cylinders');
        vehicleData.engineDisplacement = resultMap.get('Displacement (L)');
        vehicleData.engineDisplacementCC = resultMap.get('Displacement (CC)');
        vehicleData.engineDisplacementCI = resultMap.get('Displacement (CI)');
        vehicleData.enginePower = resultMap.get('Engine Brake (hp) From');
        vehicleData.enginePowerTo = resultMap.get('Engine Brake (hp) To');
        vehicleData.engineStrokeCycles = resultMap.get('Engine Stroke Cycles');
        vehicleData.engineConfiguration = resultMap.get('Engine Configuration');
        vehicleData.engineManufacturer = resultMap.get('Engine Manufacturer');
        vehicleData.engineBrakeFrom = resultMap.get('Engine Brake (hp) From');
        vehicleData.engineBrakeTo = resultMap.get('Engine Brake (hp) To');
        vehicleData.otherEngineInfo = resultMap.get('Other Engine Info');
        vehicleData.turbo = resultMap.get('Turbo');
        vehicleData.topSpeed = resultMap.get('Top Speed (MPH)');
        vehicleData.electrificationLevel = resultMap.get('Electrification Level');
        vehicleData.coolingType = resultMap.get('Cooling Type');
        vehicleData.valveTrainDesign = resultMap.get('Valve Train Design');
        
        // Transmission and drivetrain
        vehicleData.transmissionStyle = resultMap.get('Transmission Style');
        vehicleData.transmissionSpeeds = resultMap.get('Transmission Speeds');
        vehicleData.driveType = resultMap.get('Drive Type');
        vehicleData.axles = resultMap.get('Axles');
        vehicleData.axleConfiguration = resultMap.get('Axle Configuration');
        
        // Fuel system
        vehicleData.fuelType = resultMap.get('Fuel Type - Primary');
        vehicleData.fuelTypeSecondary = resultMap.get('Fuel Type - Secondary');
        vehicleData.fuelDeliveryType = resultMap.get('Fuel Delivery / Fuel Injection Type');
        vehicleData.fuelTankType = resultMap.get('Fuel-Tank Type');
        vehicleData.fuelTankMaterial = resultMap.get('Fuel-Tank Material');
        
        // Dimensions and weight
        vehicleData.doors = resultMap.get('Doors');
        vehicleData.windows = resultMap.get('Windows');
        vehicleData.wheelBase = resultMap.get('Wheel Base (inches)');
        vehicleData.wheelBaseFrom = resultMap.get('Wheel Base (inches) From');
        vehicleData.wheelBaseTo = resultMap.get('Wheel Base (inches) To');
        vehicleData.wheelBaseType = resultMap.get('Wheel Base Type');
        vehicleData.trackWidth = resultMap.get('Track Width (inches)');
        vehicleData.curbWeight = resultMap.get('Curb Weight (pounds)');
        vehicleData.gvwr = resultMap.get('Gross Vehicle Weight Rating From');
        vehicleData.gvwrFrom = resultMap.get('Gross Vehicle Weight Rating From');
        vehicleData.gvwrTo = resultMap.get('Gross Vehicle Weight Rating To');
        vehicleData.gcvwrFrom = resultMap.get('Gross Combination Weight Rating From');
        vehicleData.gcvwrTo = resultMap.get('Gross Combination Weight Rating To');
        vehicleData.bedLength = resultMap.get('Bed Length (inches)');
        vehicleData.bedType = resultMap.get('Bed Type');
        vehicleData.cabType = resultMap.get('Cab Type');
        
        // Seating and interior
        vehicleData.seats = resultMap.get('Number of Seats');
        vehicleData.seatRows = resultMap.get('Number of Seat Rows');
        vehicleData.seatBeltType = resultMap.get('Seat Belt Type');
        vehicleData.otherRestraintSystemInfo = resultMap.get('Other Restraint System Info');
        vehicleData.pretensioner = resultMap.get('Pretensioner');
        
        // Safety features
        vehicleData.abs = resultMap.get('Anti-lock Braking System (ABS)');
        vehicleData.esc = resultMap.get('Electronic Stability Control (ESC)');
        vehicleData.tractionControl = resultMap.get('Traction Control');
        vehicleData.airbagLocations = resultMap.get('Front Air Bag Locations');
        vehicleData.frontAirbagLocations = resultMap.get('Front Air Bag Locations');
        vehicleData.sideAirbagLocations = resultMap.get('Side Air Bag Locations');
        vehicleData.curtainAirbagLocations = resultMap.get('Curtain Air Bag Locations');
        vehicleData.seatCushionAirbagLocations = resultMap.get('Seat Cushion Air Bag Locations');
        vehicleData.kneeAirbagLocations = resultMap.get('Knee Air Bag Locations');
        vehicleData.tpmsType = resultMap.get('Tire Pressure Monitoring System (TPMS) Type');
        vehicleData.activeSafetySystemNote = resultMap.get('Active Safety System Note');
        
        // Advanced safety systems
        vehicleData.adaptiveCruiseControl = resultMap.get('Adaptive Cruise Control (ACC)');
        vehicleData.crashImminentBraking = resultMap.get('Crash Imminent Braking (CIB)');
        vehicleData.forwardCollisionWarning = resultMap.get('Forward Collision Warning (FCW)');
        vehicleData.dynamicBrakeSupport = resultMap.get('Dynamic Brake Support (DBS)');
        vehicleData.pedestrianAutomaticEmergencyBraking = resultMap.get('Pedestrian Automatic Emergency Braking (PAEB)');
        vehicleData.blindSpotWarning = resultMap.get('Blind Spot Warning (BSW)');
        vehicleData.laneDepartureWarning = resultMap.get('Lane Departure Warning (LDW)');
        vehicleData.laneKeepingAssistance = resultMap.get('Lane Keeping Assistance (LKA)');
        vehicleData.blindSpotIntervention = resultMap.get('Blind Spot Intervention (BSI)');
        vehicleData.laneCenteringAssistance = resultMap.get('Lane Centering Assistance');
        vehicleData.backupCamera = resultMap.get('Backup Camera');
        vehicleData.parkingAssist = resultMap.get('Parking Assist');
        vehicleData.rearCrossTrafficAlert = resultMap.get('Rear Cross Traffic Alert');
        vehicleData.rearAutomaticEmergencyBraking = resultMap.get('Rear Automatic Emergency Braking');
        vehicleData.automaticCrashNotification = resultMap.get('Automatic Crash Notification (ACN) / Advanced Automatic Crash Notification (AACN)');
        vehicleData.daytimeRunningLight = resultMap.get('Daytime Running Light (DRL)');
        vehicleData.headlampLightSource = resultMap.get('Headlamp Light Source');
        vehicleData.semiautomaticHeadlampBeamSwitching = resultMap.get('Semiautomatic Headlamp Beam Switching');
        vehicleData.adaptiveDrivingBeam = resultMap.get('Adaptive Driving Beam (ADB)');
        vehicleData.autoReverseSystem = resultMap.get('Auto-Reverse System for Windows and Sunroofs');
        vehicleData.automaticPedestrianAlertingSound = resultMap.get('Automatic Pedestrian Alerting Sound (for Hybrid and EV only)');
        vehicleData.eventDataRecorder = resultMap.get('Event Data Recorder (EDR)');
        vehicleData.keylessIgnition = resultMap.get('Keyless Ignition');
        vehicleData.saeAutomationLevelFrom = resultMap.get('SAE Automation Level From');
        vehicleData.saeAutomationLevelTo = resultMap.get('SAE Automation Level To');
        
        // Braking system
        vehicleData.brakeSystemType = resultMap.get('Brake System Type');
        vehicleData.brakeSystemDescription = resultMap.get('Brake System Description');
        vehicleData.combinedBrakingSystem = resultMap.get('Combined Braking System (CBS)');
        vehicleData.wheelieMitigation = resultMap.get('Wheelie Mitigation');
        
        // Wheels and tires
        vehicleData.numberOfWheels = resultMap.get('Number of Wheels');
        vehicleData.wheelSizeFront = resultMap.get('Wheel Size Front (inches)');
        vehicleData.wheelSizeRear = resultMap.get('Wheel Size Rear (inches)');
        
        // Battery and electric systems
        vehicleData.batteryType = resultMap.get('Battery Type');
        vehicleData.otherBatteryInfo = resultMap.get('Other Battery Info');
        vehicleData.batteryCellsPerModule = resultMap.get('Number of Battery Cells per Module');
        vehicleData.batteryCurrentFrom = resultMap.get('Battery Current (Amps) From');
        vehicleData.batteryVoltageFrom = resultMap.get('Battery Voltage (Volts) From');
        vehicleData.batteryEnergyFrom = resultMap.get('Battery Energy (kWh) From');
        vehicleData.batteryCurrentTo = resultMap.get('Battery Current (Amps) To');
        vehicleData.batteryVoltageTo = resultMap.get('Battery Voltage (Volts) To');
        vehicleData.batteryEnergyTo = resultMap.get('Battery Energy (kWh) To');
        vehicleData.batteryModulesPerPack = resultMap.get('Number of Battery Modules per Pack');
        vehicleData.batteryPacksPerVehicle = resultMap.get('Number of Battery Packs per Vehicle');
        vehicleData.evDriveUnit = resultMap.get('EV Drive Unit');
        vehicleData.chargerLevel = resultMap.get('Charger Level');
        vehicleData.chargerPower = resultMap.get('Charger Power (kW)');
        
        // Entertainment and comfort
        vehicleData.entertainmentSystem = resultMap.get('Entertainment System');
        vehicleData.steeringLocation = resultMap.get('Steering Location');
        
        // Manufacturing information
        vehicleData.plantCountry = resultMap.get('Plant Country');
        vehicleData.plantState = resultMap.get('Plant State');
        vehicleData.plantCity = resultMap.get('Plant City');
        vehicleData.plantCompanyName = resultMap.get('Plant Company Name');
        vehicleData.destinationMarket = resultMap.get('Destination Market');
        vehicleData.nonLandUse = resultMap.get('Non-Land Use');
        
        // Vehicle classification
        vehicleData.trim2 = resultMap.get('Trim2');
        vehicleData.series2 = resultMap.get('Series2');
        vehicleData.note = resultMap.get('Note');
        vehicleData.basePrice = resultMap.get('Base Price ($)');
        vehicleData.vehicleDescriptor = resultMap.get('Vehicle Descriptor');
        vehicleData.suggestedVin = resultMap.get('Suggested VIN');
        vehicleData.errorCode = resultMap.get('Error Code');
        vehicleData.possibleValues = resultMap.get('Possible Values');
        vehicleData.additionalErrorText = resultMap.get('Additional Error Text');
        vehicleData.errorText = resultMap.get('Error Text');
        
        // Trailer information
        vehicleData.trailerTypeConnection = resultMap.get('Trailer Type Connection');
        vehicleData.trailerBodyType = resultMap.get('Trailer Body Type');
        vehicleData.trailerLength = resultMap.get('Trailer Length (feet)');
        vehicleData.otherTrailerInfo = resultMap.get('Other Trailer Info');
        
        // Motorcycle information
        vehicleData.customMotorcycleType = resultMap.get('Custom Motorcycle Type');
        vehicleData.motorcycleSuspensionType = resultMap.get('Motorcycle Suspension Type');
        vehicleData.motorcycleChassisType = resultMap.get('Motorcycle Chassis Type');
        vehicleData.otherMotorcycleInfo = resultMap.get('Other Motorcycle Info');
        
        // Bus information
        vehicleData.busLength = resultMap.get('Bus Length (feet)');
        vehicleData.busFloorConfigurationType = resultMap.get('Bus Floor Configuration Type');
        vehicleData.busType = resultMap.get('Bus Type');
        vehicleData.otherBusInfo = resultMap.get('Other Bus Info');
        
        return vehicleData;
    }
    
    /**
     * Validate VIN format
     * @param vin The VIN to validate
     * @return Boolean indicating if VIN is valid format
     */
    public static Boolean isValidVinFormat(String vin) {
        if (String.isBlank(vin)) {
            return false;
        }
        
        String cleanVin = vin.trim().toUpperCase();
        
        // Check length
        if (cleanVin.length() != 17) {
            return false;
        }
        
        // Check for invalid characters
        if (cleanVin.contains('I') || cleanVin.contains('O') || cleanVin.contains('Q')) {
            return false;
        }
        
        // Check if all characters are alphanumeric
        Pattern vinPattern = Pattern.compile('[A-HJ-NPR-Z0-9]{17}');
        return vinPattern.matcher(cleanVin).matches();
    }
}