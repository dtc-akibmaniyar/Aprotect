/* Test Class Name: FlowHelperTest
 */
global with sharing class DistanceDrivenFlowHelper {
    global class DistanceDrivenRequest {
        @InvocableVariable(required=true)
        public Decimal purchaseOdometer;
        @InvocableVariable(required=true)
        public String purchaseOdometerUnit; // 'KM' or 'Miles'
        @InvocableVariable(required=true)
        public Decimal lossOdometer;
        @InvocableVariable(required=true)
        public String lossOdometerUnit; // 'KM' or 'Miles'
    }
    global class DistanceDrivenResponse {
        @InvocableVariable
        public Decimal distanceDriven;
        @InvocableVariable
        public String distanceDrivenUnit;
    }

    @InvocableMethod(label='Calculate Distance Driven' description='Calculates the distance driven between two odometer readings, preferring KM if units differ')
    global static List<DistanceDrivenResponse> calculateDistanceDriven(List<DistanceDrivenRequest> requests) {
        List<DistanceDrivenResponse> responses = new List<DistanceDrivenResponse>();
        for (DistanceDrivenRequest req : requests) {
            DistanceDrivenResponse resp = new DistanceDrivenResponse();
            Decimal purchase = req.purchaseOdometer;
            Decimal loss = req.lossOdometer;
            String purchaseUnit = req.purchaseOdometerUnit;
            String lossUnit = req.lossOdometerUnit;
            String resultUnit;

            if (String.isBlank(purchaseUnit) || String.isBlank(lossUnit)) {
                resp.distanceDriven = null;
                resp.distanceDrivenUnit = null;
                responses.add(resp);
                continue;
            }

            if (purchaseUnit == lossUnit) {
                // Units are the same, use that unit
                resultUnit = purchaseUnit;
            } else {
                // Units differ, convert both to KM
                if (purchaseUnit == 'Miles') {
                    purchase = purchase * 1.60934;
                }
                if (lossUnit == 'Miles') {
                    loss = loss * 1.60934;
                }
                resultUnit = 'KM';
            }

            resp.distanceDriven = loss - purchase;
            resp.distanceDrivenUnit = resultUnit;
            responses.add(resp);
        }
        return responses;
    }
}