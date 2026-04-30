/* Test Class Name: FlowHelperTest
 */
global with sharing class DateCalculationFlowHelper {
    global class MonthsBetweenRequest {
        @InvocableVariable
        public Date startDate;
        @InvocableVariable
        public Date endDate;
    }
    global class MonthsBetweenResponse {
        @InvocableVariable
        public Integer months;
    }

    @InvocableMethod(label='Calculate Months Between Dates' description='Returns the number of months between two dates')
    global static List<MonthsBetweenResponse> monthsBetweenDates(List<MonthsBetweenRequest> requests) {
        List<MonthsBetweenResponse> responses = new List<MonthsBetweenResponse>();
        for (MonthsBetweenRequest req : requests) {
            MonthsBetweenResponse resp = new MonthsBetweenResponse();
            if (req.startDate == null || req.endDate == null) {
                resp.months = null;
            } else {
                Integer months = (req.endDate.year() - req.startDate.year()) * 12 + (req.endDate.month() - req.startDate.month());
                if (req.endDate.day() < req.startDate.day()) months--;
                resp.months = months;
            }
            responses.add(resp);
        }
        return responses;
    }
}