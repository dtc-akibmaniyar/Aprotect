@isTest
public class VinDecoderServiceTest {
    
    @TestSetup
    static void setupTestData() {
        // No test data needed for this service
    }
    
    @isTest
    static void testDecodeVin_Success() {
        // Mock HTTP response for successful VIN decode
        String mockResponse = '{"Count": 1, "Message": "Results returned successfully", "SearchCriteria": "VIN:1HGBH41JXMN109186", "Results": [{"Variable": "Make", "Value": "HONDA", "VariableId": 26, "VariableName": "Make"}, {"Variable": "Model", "Value": "CIVIC", "VariableId": 28, "VariableName": "Model"}, {"Variable": "Model Year", "Value": "2021", "VariableId": 29, "VariableName": "Model Year"}, {"Variable": "Trim", "Value": "Sport", "VariableId": 30, "VariableName": "Trim"}, {"Variable": "Body Class", "Value": "Sedan/Saloon", "VariableId": 5, "VariableName": "Body Class"}, {"Variable": "Manufacturer Name", "Value": "HONDA OF AMERICA MFG., INC.", "VariableId": 27, "VariableName": "Manufacturer Name"}, {"Variable": "Vehicle Type", "Value": "PASSENGER CAR", "VariableId": 2, "VariableName": "Vehicle Type"}]}';
        
        Test.setMock(HttpCalloutMock.class, new VinDecoderMockHttpResponse(200, mockResponse));
        
        Test.startTest();
        VinDecoderService.VinDecodeResponse response = VinDecoderService.decodeVin('1HGBH41JXMN109186');
        Test.stopTest();
        
        // Assertions
        System.assertEquals(true, response.success, 'Response should be successful');
        System.assertEquals('VIN decoded successfully', response.message, 'Message should indicate success');
        System.assertNotEquals(null, response.vehicleData, 'Vehicle data should not be null');
        System.assertEquals('HONDA', response.vehicleData.make, 'Make should be HONDA');
        System.assertEquals('CIVIC', response.vehicleData.model, 'Model should be CIVIC');
        System.assertEquals('2021', response.vehicleData.year, 'Year should be 2021');
        System.assertEquals('Sport', response.vehicleData.trim, 'Trim should be Sport');
        System.assertEquals('Sedan/Saloon', response.vehicleData.bodyClass, 'Body class should be Sedan/Saloon');
    }
    
    @isTest
    static void testDecodeVin_NotFound() {
        // Mock HTTP response for VIN not found
        String mockResponse = '{"Count": 0, "Message": "Results returned successfully", "SearchCriteria": "VIN:INVALID123456789", "Results": []}';
        
        Test.setMock(HttpCalloutMock.class, new VinDecoderMockHttpResponse(200, mockResponse));
        
        Test.startTest();
        VinDecoderService.VinDecodeResponse response = VinDecoderService.decodeVin('INVALID123456789');
        Test.stopTest();
        
        // Assertions
        System.assertEquals(false, response.success, 'Response should not be successful');
        System.assertEquals('VIN not found or no vehicle data available', response.message, 'Message should indicate VIN not found');
        System.assertEquals('NO_DATA_FOUND', response.errorCode, 'Error code should be NO_DATA_FOUND');
    }
    
    @isTest
    static void testDecodeVin_InvalidVin() {
        Test.startTest();
        VinDecoderService.VinDecodeResponse response = VinDecoderService.decodeVin('');
        Test.stopTest();
        
        // Assertions
        System.assertEquals(false, response.success, 'Response should not be successful');
        System.assertEquals('VIN cannot be empty', response.message, 'Message should indicate empty VIN');
        System.assertEquals('INVALID_VIN', response.errorCode, 'Error code should be INVALID_VIN');
    }
    
    @isTest
    static void testDecodeVin_InvalidVinLength() {
        Test.startTest();
        VinDecoderService.VinDecodeResponse response = VinDecoderService.decodeVin('123456789');
        Test.stopTest();
        
        // Assertions
        System.assertEquals(false, response.success, 'Response should not be successful');
        System.assertEquals('VIN must be exactly 17 characters long', response.message, 'Message should indicate invalid length');
        System.assertEquals('INVALID_VIN_LENGTH', response.errorCode, 'Error code should be INVALID_VIN_LENGTH');
    }
    
    @isTest
    static void testDecodeVin_InvalidVinCharacters() {
        Test.startTest();
        VinDecoderService.VinDecodeResponse response = VinDecoderService.decodeVin('1HGBH41JXMN10918I');
        Test.stopTest();
        
        // Assertions
        System.assertEquals(false, response.success, 'Response should not be successful');
        System.assertEquals('VIN contains invalid characters (I, O, or Q)', response.message, 'Message should indicate invalid characters');
        System.assertEquals('INVALID_VIN_CHARS', response.errorCode, 'Error code should be INVALID_VIN_CHARS');
    }
    
    @isTest
    static void testDecodeVin_HttpError() {
        // Mock HTTP error response
        Test.setMock(HttpCalloutMock.class, new VinDecoderMockHttpResponse(500, 'Internal Server Error'));
        
        Test.startTest();
        VinDecoderService.VinDecodeResponse response = VinDecoderService.decodeVin('1HGBH41JXMN109186');
        Test.stopTest();
        
        // Assertions
        System.assertEquals(false, response.success, 'Response should not be successful');
        System.assert(response.message.contains('VIN decoder service unavailable'), 'Message should indicate service unavailable');
        System.assertEquals('SERVICE_UNAVAILABLE', response.errorCode, 'Error code should be SERVICE_UNAVAILABLE');
    }
    
    @isTest
    static void testDecodeVin_Timeout() {
        // Mock timeout response
        Test.setMock(HttpCalloutMock.class, new VinDecoderTimeoutMock());
        
        Test.startTest();
        VinDecoderService.VinDecodeResponse response = VinDecoderService.decodeVin('1HGBH41JXMN109186');
        Test.stopTest();
        
        // Assertions
        System.assertEquals(false, response.success, 'Response should not be successful');
        System.assert(response.message.contains('Error decoding VIN'), 'Message should indicate decode error');
        System.assertEquals('DECODE_ERROR', response.errorCode, 'Error code should be DECODE_ERROR');
    }
    
    @isTest
    static void testIsValidVinFormat_ValidVins() {
        Test.startTest();
        
        // Test valid VINs
        System.assertEquals(true, VinDecoderService.isValidVinFormat('1HGBH41JXMN109186'), 'Valid VIN should return true');
        System.assertEquals(true, VinDecoderService.isValidVinFormat('2T1BURHE0JC123456'), 'Valid VIN should return true');
        System.assertEquals(true, VinDecoderService.isValidVinFormat('3VWDX7AJ5DM123456'), 'Valid VIN should return true');
        
        Test.stopTest();
    }
    
    @isTest
    static void testIsValidVinFormat_InvalidVins() {
        Test.startTest();
        
        // Test invalid VINs
        System.assertEquals(false, VinDecoderService.isValidVinFormat(''), 'Empty VIN should return false');
        System.assertEquals(false, VinDecoderService.isValidVinFormat(null), 'Null VIN should return false');
        System.assertEquals(false, VinDecoderService.isValidVinFormat('123456789'), 'Short VIN should return false');
        System.assertEquals(false, VinDecoderService.isValidVinFormat('1HGBH41JXMN10918I'), 'VIN with I should return false');
        System.assertEquals(false, VinDecoderService.isValidVinFormat('1HGBH41JXMN10918O'), 'VIN with O should return false');
        System.assertEquals(false, VinDecoderService.isValidVinFormat('1HGBH41JXMN10918Q'), 'VIN with Q should return false');
        System.assertEquals(false, VinDecoderService.isValidVinFormat('1HGBH41JXMN109186X'), 'VIN with invalid character should return false');
        
        Test.stopTest();
    }
    
    @isTest
    static void testDecodeVin_RealWorldExample() {
        // Mock response for a real-world VIN with comprehensive data
        String mockResponse = '{"Count": 1, "Message": "Results returned successfully", "SearchCriteria": "VIN:1HGBH41JXMN109186", "Results": [{"Variable": "Make", "Value": "HONDA", "VariableId": 26, "VariableName": "Make"}, {"Variable": "Model", "Value": "CIVIC", "VariableId": 28, "VariableName": "Model"}, {"Variable": "Model Year", "Value": "2021", "VariableId": 29, "VariableName": "Model Year"}, {"Variable": "Trim", "Value": "Sport", "VariableId": 30, "VariableName": "Trim"}, {"Variable": "Body Class", "Value": "Sedan/Saloon", "VariableId": 5, "VariableName": "Body Class"}, {"Variable": "Manufacturer Name", "Value": "HONDA OF AMERICA MFG., INC.", "VariableId": 27, "VariableName": "Manufacturer Name"}, {"Variable": "Vehicle Type", "Value": "PASSENGER CAR", "VariableId": 2, "VariableName": "Vehicle Type"}, {"Variable": "Engine Model", "Value": "1.5L 4-CYL TURBO", "VariableId": 10, "VariableName": "Engine Model"}, {"Variable": "Transmission Style", "Value": "CVT", "VariableId": 11, "VariableName": "Transmission Style"}, {"Variable": "Drive Type", "Value": "FWD", "VariableId": 12, "VariableName": "Drive Type"}, {"Variable": "Fuel Type - Primary", "Value": "Gasoline", "VariableId": 13, "VariableName": "Fuel Type - Primary"}, {"Variable": "Doors", "Value": "4", "VariableId": 14, "VariableName": "Doors"}, {"Variable": "Windows", "Value": "4", "VariableId": 15, "VariableName": "Windows"}, {"Variable": "Wheel Base (inches)", "Value": "106.3", "VariableId": 16, "VariableName": "Wheel Base (inches)"}, {"Variable": "Plant Country", "Value": "UNITED STATES (USA)", "VariableId": 17, "VariableName": "Plant Country"}, {"Variable": "Plant State", "Value": "INDIANA", "VariableId": 18, "VariableName": "Plant State"}, {"Variable": "Plant City", "Value": "GREENSBURG", "VariableId": 19, "VariableName": "Plant City"}]}';
        
        Test.setMock(HttpCalloutMock.class, new VinDecoderMockHttpResponse(200, mockResponse));
        
        Test.startTest();
        VinDecoderService.VinDecodeResponse response = VinDecoderService.decodeVin('1HGBH41JXMN109186');
        Test.stopTest();
        
        // Assertions for comprehensive data
        System.assertEquals(true, response.success, 'Response should be successful');
        System.assertEquals('HONDA', response.vehicleData.make, 'Make should be HONDA');
        System.assertEquals('CIVIC', response.vehicleData.model, 'Model should be CIVIC');
        System.assertEquals('2021', response.vehicleData.year, 'Year should be 2021');
        System.assertEquals('Sport', response.vehicleData.trim, 'Trim should be Sport');
        System.assertEquals('1.5L 4-CYL TURBO', response.vehicleData.engineModel, 'Engine model should be correct');
        System.assertEquals('CVT', response.vehicleData.transmissionStyle, 'Transmission should be CVT');
        System.assertEquals('FWD', response.vehicleData.driveType, 'Drive type should be FWD');
        System.assertEquals('Gasoline', response.vehicleData.fuelType, 'Fuel type should be Gasoline');
        System.assertEquals('4', response.vehicleData.doors, 'Doors should be 4');
        System.assertEquals('UNITED STATES (USA)', response.vehicleData.plantCountry, 'Plant country should be USA');
        System.assertEquals('INDIANA', response.vehicleData.plantState, 'Plant state should be Indiana');
    }
    
    // Mock HTTP response class for successful responses
    public class VinDecoderMockHttpResponse implements HttpCalloutMock {
        private Integer statusCode;
        private String responseBody;
        
        public VinDecoderMockHttpResponse(Integer statusCode, String responseBody) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(statusCode);
            res.setBody(responseBody);
            return res;
        }
    }
    
    // Mock HTTP response class for timeout scenarios
    public class VinDecoderTimeoutMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            // Simulate a timeout by throwing an exception
            throw new CalloutException('Read timed out');
        }
    }
    
    // ========== AUTO.DEV AND FALLBACK TESTS ==========
    
    @isTest
    static void testDecodeVin_AutodevSuccess() {
        // Mock successful Auto.dev response
        String autodevResponse = '{"vin": "1HGBH41JXMN109186", "vinValid": true, "wmi": "1HG", "origin": "United States", "squishVin": "1HGBH41JXMN", "checkDigit": "1", "checksum": true, "type": "Passenger Cars", "make": "Honda", "model": "Civic", "trim": "Sport", "style": "4dr Sedan", "vehicle": {"vin": "1HGBH41JXMN109186", "year": 2021, "make": "Honda", "model": "Civic", "manufacturer": "Honda of America Mfg., Inc."}, "api": {"name": "api.auto.dev", "description": "Vehicle VIN Decode", "url": "https://api.auto.dev/vin", "account": "https://api.auto.dev/account", "docs": "https://docs.auto.dev/v2/products/vin-decode", "type": "data", "from": "https://auto.dev"}, "links": {"home": "https://api.auto.dev", "self": "https://api.auto.dev/vin/1HGBH41JXMN109186", "prev": "https://api.auto.dev/vin"}, "user": {"name": "Test User", "email": "test@example.com", "authenticated": true, "plan": "Starter"}}';
        
        Test.setMock(HttpCalloutMock.class, new MultiTierMock(200, autodevResponse, 'AUTO_DEV'));
        
        Test.startTest();
        VinDecoderService.VinDecodeResponse response = VinDecoderService.decodeVin('1HGBH41JXMN109186');
        Test.stopTest();
        
        // Assertions
        System.assertEquals(true, response.success, 'Response should be successful');
        System.assert(response.message.contains('Auto.dev'), 'Message should indicate Auto.dev was used');
        System.assertEquals('AUTO_DEV', response.apiSource, 'API source should be AUTO_DEV');
        System.assertEquals('Honda', response.vehicleData.make, 'Make should be Honda');
        System.assertEquals('Civic', response.vehicleData.model, 'Model should be Civic');
        System.assertEquals('2021', response.vehicleData.year, 'Year should be 2021');
        System.assertEquals('Sport', response.vehicleData.trim, 'Trim should be Sport');
        System.assertEquals('CVT', response.vehicleData.transmissionStyle, 'Transmission should be CVT');
    }
    
    @isTest
    static void testDecodeVin_AutodevFailsNhtsaSucceeds() {
        // Mock Auto.dev failure, NHTSA success
        String nhtsaResponse = '{"Count": 1, "Message": "Results returned successfully", "Results": [{"Variable": "Make", "Value": "HONDA"}, {"Variable": "Model", "Value": "CIVIC"}, {"Variable": "Model Year", "Value": "2021"}, {"Variable": "Trim", "Value": "Sport"}]}';
        
        Test.setMock(HttpCalloutMock.class, new MultiTierMock(500, '', 'AUTO_DEV_FAILS', nhtsaResponse));
        
        Test.startTest();
        VinDecoderService.VinDecodeResponse response = VinDecoderService.decodeVin('1HGBH41JXMN109186');
        Test.stopTest();
        
        // Assertions - should fallback to NHTSA
        System.assertEquals(true, response.success, 'Response should be successful via NHTSA fallback');
        System.assert(response.message.contains('NHTSA'), 'Message should indicate NHTSA was used');
        System.assertEquals('NHTSA', response.apiSource, 'API source should be NHTSA');
        System.assertEquals('HONDA', response.vehicleData.make, 'Make should be HONDA');
        System.assertEquals('CIVIC', response.vehicleData.model, 'Model should be CIVIC');
    }
    
    @isTest
    static void testDecodeVin_AutodevRateLimitNhtsaSucceeds() {
        // Mock Auto.dev rate limit (429), NHTSA success
        String nhtsaResponse = '{"Count": 1, "Message": "Results returned successfully", "Results": [{"Variable": "Make", "Value": "TOYOTA"}, {"Variable": "Model", "Value": "CAMRY"}, {"Variable": "Model Year", "Value": "2020"}]}';
        
        Test.setMock(HttpCalloutMock.class, new MultiTierMock(429, 'Rate limit exceeded', 'AUTO_DEV_RATE_LIMIT', nhtsaResponse));
        
        Test.startTest();
        VinDecoderService.VinDecodeResponse response = VinDecoderService.decodeVin('2T1BURHE0JC123456');
        Test.stopTest();
        
        // Assertions - should fallback to NHTSA
        System.assertEquals(true, response.success, 'Response should be successful via NHTSA fallback');
        System.assertEquals('NHTSA', response.apiSource, 'API source should be NHTSA after rate limit');
        System.assertEquals('TOYOTA', response.vehicleData.make, 'Make should be TOYOTA');
    }
    
    @isTest
    static void testDecodeVin_BothApisFail() {
        // Mock both Auto.dev and NHTSA failures
        Test.setMock(HttpCalloutMock.class, new MultiTierMock(500, 'Server Error', 'BOTH_FAIL'));
        
        Test.startTest();
        VinDecoderService.VinDecodeResponse response = VinDecoderService.decodeVin('1HGBH41JXMN109186');
        Test.stopTest();
        
        // Assertions - both should fail
        System.assertEquals(false, response.success, 'Response should not be successful');
        System.assertEquals('ALL_APIS_FAILED', response.errorCode, 'Error code should indicate all APIs failed');
        System.assertEquals('NONE', response.apiSource, 'API source should be NONE');
        System.assert(response.message.contains('manually'), 'Message should suggest manual entry');
    }
    
    @isTest
    static void testDecodeVin_AutodevIncompleteData() {
        // Mock Auto.dev with incomplete data (no make/model)
        String autodevResponse = '{"vin": "1FTFW1ET5DFC12345", "vinValid": true, "trim": "Sport", "vehicle": {"vin": "1FTFW1ET5DFC12345", "year": 2021, "make": null, "model": null, "manufacturer": null}}';
        String nhtsaResponse = '{"Count": 1, "Message": "Results returned successfully", "Results": [{"Variable": "Make", "Value": "FORD"}, {"Variable": "Model", "Value": "F-150"}, {"Variable": "Model Year", "Value": "2019"}]}';
        
        Test.setMock(HttpCalloutMock.class, new MultiTierMock(200, autodevResponse, 'AUTO_DEV_INCOMPLETE', nhtsaResponse));
        
        Test.startTest();
        VinDecoderService.VinDecodeResponse response = VinDecoderService.decodeVin('1FTFW1ET5DFC12345');
        Test.stopTest();
        
        // Should fallback to NHTSA since Auto.dev data was incomplete
        System.assertEquals(true, response.success, 'Should succeed via NHTSA fallback');
        System.assertEquals('NHTSA', response.apiSource, 'Should use NHTSA after incomplete Auto.dev data');
        System.assertEquals('FORD', response.vehicleData.make, 'Make should be FORD from NHTSA');
    }
    
    // Multi-tier HTTP mock that simulates Auto.dev then NHTSA
    public class MultiTierMock implements HttpCalloutMock {
        private Integer statusCode;
        private String responseBody;
        private String scenario;
        private String nhtsaResponse;
        private Integer callCount = 0;
        
        public MultiTierMock(Integer statusCode, String responseBody, String scenario) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
            this.scenario = scenario;
        }
        
        public MultiTierMock(Integer statusCode, String responseBody, String scenario, String nhtsaResponse) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
            this.scenario = scenario;
            this.nhtsaResponse = nhtsaResponse;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            
            callCount++;
            
            // Check if this is Auto.dev or NHTSA call based on endpoint
            if (req.getEndpoint().contains('api.auto.dev')) {
                // Auto.dev call
                if (scenario == 'AUTO_DEV') {
                    res.setStatusCode(200);
                    res.setBody(responseBody);
                } else if (scenario == 'AUTO_DEV_FAILS' || scenario == 'BOTH_FAIL') {
                    res.setStatusCode(500);
                    res.setBody('Server Error');
                } else if (scenario == 'AUTO_DEV_RATE_LIMIT') {
                    res.setStatusCode(429);
                    res.setBody('Rate limit exceeded');
                } else if (scenario == 'AUTO_DEV_INCOMPLETE') {
                    res.setStatusCode(200);
                    res.setBody(responseBody);
                }
            } else if (req.getEndpoint().contains('vpic.nhtsa.dot.gov')) {
                // NHTSA call (fallback)
                if (scenario == 'BOTH_FAIL') {
                    res.setStatusCode(500);
                    res.setBody('Server Error');
                } else if (nhtsaResponse != null) {
                    res.setStatusCode(200);
                    res.setBody(nhtsaResponse);
                } else {
                    res.setStatusCode(200);
                    res.setBody('{"Count": 0, "Results": []}');
                }
            }
            
            return res;
        }
    }
}