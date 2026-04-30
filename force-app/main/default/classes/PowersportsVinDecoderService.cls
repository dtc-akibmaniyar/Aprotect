public without sharing class PowersportsVinDecoderService {

    // Powersports-specific API response fields (modal display + engineCC storage)
    public class PowersportsVehicleData {
        @AuraEnabled public String publishDate;
        @AuraEnabled public String country;
        @AuraEnabled public String uvc;
        @AuraEnabled public String className;
        @AuraEnabled public String modelClass;
        @AuraEnabled public Decimal wholeAvg;
        @AuraEnabled public Decimal retailAvg;
        @AuraEnabled public Decimal tradeinClean;
        @AuraEnabled public Decimal tradeinFair;
        @AuraEnabled public Decimal finadv;
        @AuraEnabled public Decimal msrp;
        @AuraEnabled public Integer cylinders;
        @AuraEnabled public Integer engineDisplacement;
    }

    // Response wrapper returned to VinDecoderService
    public class PowersportsDecodeResponse {
        public Boolean success;
        public String message;
        public String errorCode;
        public String rawResponse;
        public VinDecoderService.DecodedVehicleData vehicleData;
        public PowersportsVehicleData powersportsData;

        public PowersportsDecodeResponse() {
            this.success         = false;
            this.message         = '';
            this.errorCode       = '';
            this.rawResponse     = '';
            this.vehicleData     = new VinDecoderService.DecodedVehicleData();
            this.powersportsData = null;
        }
    }

    /**
     * Decode a VIN using the Canadian Black Book Powersports API.
     * Called by VinDecoderService as a fallback when the Used Car API returns not-found.
     */
    public static PowersportsDecodeResponse decode(String vin) {
        PowersportsDecodeResponse response = new PowersportsDecodeResponse();

        try {
            String cleanVin = vin.trim().toUpperCase();

            Http http = new Http();
            HttpRequest req = new HttpRequest();
            req.setEndpoint(
                'callout:Canadian_BlackBook_PowerSupport/PowersportsAPI/PowersportsAPI/Vehicle/VIN/'
                + cleanVin + '?country=C&template=1&customerid=test'
            );
            req.setMethod('GET');
            req.setTimeout(15000);
            req.setHeader('Accept', 'application/json');
            req.setHeader('Content-Type', 'application/json');

            HttpResponse httpRes = http.send(req);

            if (httpRes.getStatusCode() == 200) {
                String body = httpRes.getBody();
                response.rawResponse = body;

                Map<String, Object> json =
                    (Map<String, Object>) JSON.deserializeUntyped(body);

                Integer errCount = json.containsKey('error_count')
                    ? (Integer) json.get('error_count') : 0;

                if (errCount > 0) {
                    response.message   = extractErrorMessage(json);
                    response.errorCode = 'POWERSPORTS_NOT_FOUND';
                    return response;
                }

                Map<String, Object> ps =
                    (Map<String, Object>) json.get('powersports_vehicles');

                if (ps == null || ps.get('data_available') != true) {
                    response.message   = 'Powersports: data not available';
                    response.errorCode = 'NO_DATA_AVAILABLE';
                    return response;
                }

                List<Object> vehicleList =
                    (List<Object>) ps.get('powersports_vehicle_list');

                if (vehicleList == null || vehicleList.isEmpty()) {
                    response.message   = 'Powersports: empty vehicle list';
                    response.errorCode = 'NO_DATA_FOUND';
                    return response;
                }

                Map<String, Object> v = (Map<String, Object>) vehicleList[0];

                response.vehicleData     = mapStandardFields(v);
                response.powersportsData = mapPowersportsFields(v);

                if (String.isNotBlank(response.vehicleData.make)
                    && String.isNotBlank(response.vehicleData.model)) {
                    response.success = true;
                } else {
                    response.message   = 'Powersports API returned incomplete data';
                    response.errorCode = 'NO_DATA_FOUND';
                }

            } else if (httpRes.getStatusCode() == 401) {
                response.message   = 'Powersports API authentication failed';
                response.errorCode = 'AUTH_ERROR';
            } else {
                response.message   = 'Powersports API unavailable (HTTP ' + httpRes.getStatusCode() + ')';
                response.errorCode = 'SERVICE_UNAVAILABLE';
            }

        } catch (System.CalloutException e) {
            response.message   = 'Powersports callout failed: ' + e.getMessage();
            response.errorCode = 'CALLOUT_ERROR';
        } catch (Exception e) {
            response.message   = 'Powersports error: ' + e.getMessage();
            response.errorCode = 'DECODE_ERROR';
        }

        return response;
    }

    // --- Private helpers ---

    private static String extractErrorMessage(Map<String, Object> json) {
        List<Object> msgs = (List<Object>) json.get('message_list');
        List<String> errs = new List<String>();
        if (msgs != null) {
            for (Object m : msgs) {
                Map<String, Object> msg = (Map<String, Object>) m;
                if ('Error'.equals(String.valueOf(msg.get('type')))) {
                    errs.add(String.valueOf(msg.get('description')));
                }
            }
        }
        return errs.isEmpty() ? 'Powersports API error' : String.join(errs, '; ');
    }

    private static VinDecoderService.DecodedVehicleData mapStandardFields(
        Map<String, Object> v
    ) {
        VinDecoderService.DecodedVehicleData vd =
            new VinDecoderService.DecodedVehicleData();
        vd.year               = str(v, 'model_year');
        vd.make               = str(v, 'make');
        vd.model              = str(v, 'model');
        vd.engineCylinders    = str(v, 'cylinders');
        vd.engineDisplacement = str(v, 'engine_displacement');
        vd.bodyClass          = str(v, 'class_name');
        return vd;
    }

    private static PowersportsVehicleData mapPowersportsFields(
        Map<String, Object> v
    ) {
        PowersportsVehicleData pd = new PowersportsVehicleData();
        pd.publishDate        = str(v, 'publish_date');
        pd.country            = str(v, 'country');
        pd.uvc                = str(v, 'uvc');
        pd.className          = str(v, 'class_name');
        pd.modelClass         = str(v, 'model_class');
        pd.cylinders          = intVal(v, 'cylinders');
        pd.engineDisplacement = intVal(v, 'engine_displacement');
        pd.wholeAvg           = decVal(v, 'whole_avg');
        pd.retailAvg          = decVal(v, 'retail_avg');
        pd.tradeinClean       = decVal(v, 'tradein_clean');
        pd.tradeinFair        = decVal(v, 'tradein_fair');
        pd.finadv             = decVal(v, 'finadv');
        pd.msrp               = decVal(v, 'msrp');
        return pd;
    }

    private static String str(Map<String, Object> m, String key) {
        return (m.containsKey(key) && m.get(key) != null)
            ? String.valueOf(m.get(key)) : null;
    }

    private static Integer intVal(Map<String, Object> m, String key) {
        return (m.containsKey(key) && m.get(key) != null)
            ? Integer.valueOf(String.valueOf(m.get(key))) : null;
    }

    private static Decimal decVal(Map<String, Object> m, String key) {
        return (m.containsKey(key) && m.get(key) != null)
            ? Decimal.valueOf(String.valueOf(m.get(key))) : null;
    }
}