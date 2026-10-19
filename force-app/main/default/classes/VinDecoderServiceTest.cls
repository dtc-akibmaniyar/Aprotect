@isTest
public class VinDecoderServiceTest {

    // ------------------------------------------------------------------
    // decodeVin -- VIN format validation gate
    // ------------------------------------------------------------------

    @isTest
    static void testDecodeVin_InvalidVin() {
        Test.startTest();
        VinDecoderService.VinDecodeResponse response = VinDecoderService.decodeVin('');
        Test.stopTest();

        System.assertEquals(false, response.success, 'Empty VIN should not be successful');
        System.assertEquals('VIN cannot be empty', response.message, 'Message should indicate empty VIN');
        System.assertEquals('INVALID_VIN', response.errorCode, 'Error code should be INVALID_VIN');
    }

    @isTest
    static void testDecodeVin_InvalidVinLength() {
        Test.startTest();
        VinDecoderService.VinDecodeResponse response = VinDecoderService.decodeVin('123456789');
        Test.stopTest();

        System.assertEquals(false, response.success, 'Short VIN should not be successful');
        System.assertEquals('VIN must be exactly 17 characters long', response.message, 'Message should indicate invalid length');
        System.assertEquals('INVALID_VIN_LENGTH', response.errorCode, 'Error code should be INVALID_VIN_LENGTH');
    }

    @isTest
    static void testDecodeVin_InvalidVinCharacters() {
        Test.startTest();
        VinDecoderService.VinDecodeResponse response = VinDecoderService.decodeVin('1HGBH41JXMN10918I');
        Test.stopTest();

        System.assertEquals(false, response.success, 'VIN with I should not be successful');
        System.assertEquals('VIN contains invalid characters', response.message, 'Message should indicate invalid characters');
        System.assertEquals('INVALID_VIN_CHARS', response.errorCode, 'Error code should be INVALID_VIN_CHARS');
    }

    // ------------------------------------------------------------------
    // decodeVin -- Black Book path
    // ------------------------------------------------------------------

    @isTest
    static void testDecodeVin_BlackbookSuccess() {
        String body = '{"model_year":"2021","make":"HONDA","model":"CIVIC","series":"Sport","style":"Sedan","fuel_type":"Gas"}';
        Test.setMock(HttpCalloutMock.class, new VinDecoderMockHttpResponse(200, body));

        Test.startTest();
        VinDecoderService.VinDecodeResponse response = VinDecoderService.decodeVin('1HGBH41JXMN109186');
        Test.stopTest();

        System.assertEquals(true, response.success, 'Response should be successful');
        System.assertEquals('BLACKBOOK', response.apiSource, 'API source should be BLACKBOOK');
        System.assertEquals('HONDA', response.vehicleData.make, 'Make should be HONDA');
        System.assertEquals('CIVIC', response.vehicleData.model, 'Model should be CIVIC');
        System.assertEquals('2021', response.vehicleData.year, 'Year should be 2021');
        System.assertEquals('Sport', response.vehicleData.trim, 'Trim should be Sport');
        System.assertEquals('Gas', response.vehicleData.fuelType, 'Fuel type should be Gas');
    }

    @isTest
    static void testDecodeVin_BlackbookUsedVehicleList() {
        String body = '{"used_vehicles":{"data_available":true,"used_vehicle_list":['
            + '{"model_year":"2019","make":"FORD","model":"F-150","series":"XLT","fuel_type":"Diesel"}]}}';
        Test.setMock(HttpCalloutMock.class, new VinDecoderMockHttpResponse(200, body));

        Test.startTest();
        VinDecoderService.VinDecodeResponse response = VinDecoderService.decodeVin('1FTFW1ET5DFC12345');
        Test.stopTest();

        System.assertEquals(true, response.success, 'Response should be successful from used_vehicle_list');
        System.assertEquals('FORD', response.vehicleData.make, 'Make should be FORD');
        System.assertEquals('F-150', response.vehicleData.model, 'Model should be F-150');
        System.assertEquals('Diesel', response.vehicleData.fuelType, 'Fuel type should be Diesel');
    }

    @isTest
    static void testDecodeVin_NoDataFound() {
        Test.setMock(HttpCalloutMock.class, new VinDecoderMockHttpResponse(200, '{}'));

        Test.startTest();
        VinDecoderService.VinDecodeResponse response = VinDecoderService.decodeVin('1HGBH41JXMN109186');
        Test.stopTest();

        System.assertEquals(false, response.success, 'Response should not be successful');
        System.assertEquals('BLACKBOOK_FAILED', response.errorCode, 'Error code should be BLACKBOOK_FAILED');
        System.assert(response.message.contains('Unable to decode VIN'), 'Message should suggest manual entry');
    }

    @isTest
    static void testDecodeVin_DataNotAvailable() {
        Test.setMock(HttpCalloutMock.class, new VinDecoderMockHttpResponse(200,
            '{"used_vehicles":{"data_available":false}}'));

        Test.startTest();
        VinDecoderService.VinDecodeResponse response = VinDecoderService.decodeVin('1HGBH41JXMN109186');
        Test.stopTest();

        System.assertEquals(false, response.success, 'Response should not be successful');
        System.assertEquals('BLACKBOOK_FAILED', response.errorCode, 'Error code should be BLACKBOOK_FAILED');
    }

    @isTest
    static void testDecodeVin_HttpError() {
        Test.setMock(HttpCalloutMock.class, new VinDecoderMockHttpResponse(500, 'Internal Server Error'));

        Test.startTest();
        VinDecoderService.VinDecodeResponse response = VinDecoderService.decodeVin('1HGBH41JXMN109186');
        Test.stopTest();

        System.assertEquals(false, response.success, 'Response should not be successful');
        System.assertEquals('BLACKBOOK_FAILED', response.errorCode, 'Error code should be BLACKBOOK_FAILED');
    }

    @isTest
    static void testDecodeVin_CalloutException() {
        Test.setMock(HttpCalloutMock.class, new VinDecoderTimeoutMock());

        Test.startTest();
        VinDecoderService.VinDecodeResponse response = VinDecoderService.decodeVin('1HGBH41JXMN109186');
        Test.stopTest();

        System.assertEquals(false, response.success, 'Response should not be successful');
        System.assertEquals('BLACKBOOK_FAILED', response.errorCode, 'Error code should be BLACKBOOK_FAILED');
    }

    // ------------------------------------------------------------------
    // isValidVinFormat
    // ------------------------------------------------------------------

    @isTest
    static void testIsValidVinFormat_ValidVins() {
        System.assertEquals(true, VinDecoderService.isValidVinFormat('1HGBH41JXMN109186'), 'Valid VIN should return true');
        System.assertEquals(true, VinDecoderService.isValidVinFormat('2T1BURHE0JC123456'), 'Valid VIN should return true');
        System.assertEquals(true, VinDecoderService.isValidVinFormat('3VWDX7AJ5DM123456'), 'Valid VIN should return true');
    }

    @isTest
    static void testIsValidVinFormat_InvalidVins() {
        System.assertEquals(false, VinDecoderService.isValidVinFormat(''), 'Empty VIN should return false');
        System.assertEquals(false, VinDecoderService.isValidVinFormat(null), 'Null VIN should return false');
        System.assertEquals(false, VinDecoderService.isValidVinFormat('123456789'), 'Short VIN should return false');
        System.assertEquals(false, VinDecoderService.isValidVinFormat('1HGBH41JXMN10918I'), 'VIN with I should return false');
        System.assertEquals(false, VinDecoderService.isValidVinFormat('1HGBH41JXMN10918O'), 'VIN with O should return false');
        System.assertEquals(false, VinDecoderService.isValidVinFormat('1HGBH41JXMN10918Q'), 'VIN with Q should return false');
        System.assertEquals(false, VinDecoderService.isValidVinFormat('1HGBH41JXMN109186X'), 'VIN with extra character should return false');
    }

    // ------------------------------------------------------------------
    // Fuel_Type normalisation (restricted picklist safety -- the mandatory
    // Diesel Fee depends on a diesel vehicle saving successfully)
    // ------------------------------------------------------------------

    @isTest
    static void testNormalizeFuelType_ExactPicklistValues() {
        System.assertEquals('Gas', VinDecoderService.normalizeFuelType('Gas'));
        System.assertEquals('Diesel', VinDecoderService.normalizeFuelType('Diesel'));
        System.assertEquals('Electric Vehicle', VinDecoderService.normalizeFuelType('Electric Vehicle'));
        System.assertEquals('Hybrid', VinDecoderService.normalizeFuelType('Hybrid'));
        System.assertEquals('Gasoline', VinDecoderService.normalizeFuelType('Gasoline'));
        System.assertEquals('Electric', VinDecoderService.normalizeFuelType('Electric'));
        System.assertEquals('Plug-in Hybrid', VinDecoderService.normalizeFuelType('Plug-in Hybrid'));
        System.assertEquals('Hydrogen', VinDecoderService.normalizeFuelType('Hydrogen'));
        System.assertEquals('Flex Fuel', VinDecoderService.normalizeFuelType('Flex Fuel'));
    }

    @isTest
    static void testNormalizeFuelType_CaseInsensitiveExact() {
        System.assertEquals('Gas', VinDecoderService.normalizeFuelType('gas'));
        System.assertEquals('Diesel', VinDecoderService.normalizeFuelType('diesel'));
        System.assertEquals('Diesel', VinDecoderService.normalizeFuelType('DIESEL'));
        System.assertEquals('Hybrid', VinDecoderService.normalizeFuelType('hybrid'));
        System.assertEquals('Gasoline', VinDecoderService.normalizeFuelType('gasoline'));
        System.assertEquals('Electric', VinDecoderService.normalizeFuelType('electric'));
    }

    @isTest
    static void testNormalizeFuelType_DieselVariants() {
        System.assertEquals('Diesel', VinDecoderService.normalizeFuelType('Diesel Fuel'));
        System.assertEquals('Diesel', VinDecoderService.normalizeFuelType('Turbo Diesel'));
        System.assertEquals('Diesel', VinDecoderService.normalizeFuelType('diesel engine'));
        System.assertEquals('Diesel', VinDecoderService.normalizeFuelType('DIESEL FUEL'));
        System.assertEquals('Diesel', VinDecoderService.normalizeFuelType('  Diesel  '));
    }

    @isTest
    static void testNormalizeFuelType_OtherVariants() {
        System.assertEquals('Gas', VinDecoderService.normalizeFuelType('Gasoline Fuel'));
        System.assertEquals('Gas', VinDecoderService.normalizeFuelType('Petrol'));
        System.assertEquals('Gas', VinDecoderService.normalizeFuelType('Unleaded'));
        System.assertEquals('Electric Vehicle', VinDecoderService.normalizeFuelType('Battery Electric'));
        System.assertEquals('Electric Vehicle', VinDecoderService.normalizeFuelType('EV'));
        System.assertEquals('Plug-in Hybrid', VinDecoderService.normalizeFuelType('Plug In Hybrid'));
        System.assertEquals('Hydrogen', VinDecoderService.normalizeFuelType('Hydrogen Fuel Cell'));
    }

    @isTest
    static void testNormalizeFuelType_UnknownPassthrough() {
        System.assertEquals('Steam', VinDecoderService.normalizeFuelType('Steam'), 'Unknown token should pass through unchanged');
        System.assertEquals('CNG', VinDecoderService.normalizeFuelType('CNG'), 'Unknown token should pass through unchanged');
        System.assertEquals(null, VinDecoderService.normalizeFuelType(null), 'Null should stay null');
        System.assertEquals('', VinDecoderService.normalizeFuelType(''), 'Blank should stay blank');
    }

    @isTest
    static void testDecodeVin_NormalizesDieselFuelType() {
        String body = '{"model_year":"2023","make":"TOYOTA","model":"RAV4","series":"XLE","fuel_type":"Diesel Fuel"}';
        Test.setMock(HttpCalloutMock.class, new VinDecoderMockHttpResponse(200, body));

        Test.startTest();
        VinDecoderService.VinDecodeResponse response = VinDecoderService.decodeVin('4T1B11HK5JU123456');
        Test.stopTest();

        System.assertEquals(true, response.success, 'Response should be successful');
        System.assertEquals('Diesel', response.vehicleData.fuelType,
            'A "Diesel Fuel" token must be normalised to the picklist value Diesel');
    }

    // ------------------------------------------------------------------
    // Callout mocks
    // ------------------------------------------------------------------

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

    public class VinDecoderTimeoutMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            throw new CalloutException('Read timed out');
        }
    }
}