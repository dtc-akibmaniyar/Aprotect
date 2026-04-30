public class ApplicationOilChangeHandler {
    // Helper to calculate months between two dates
    public static Integer monthsBetween(Date startDate, Date endDate) {
        if (startDate == null || endDate == null) return null;
        Integer months = (endDate.year() - startDate.year()) * 12 + (endDate.month() - startDate.month());
        if (endDate.day() < startDate.day()) months--;
        return months;
    }

    // Odometer Difference and Duration_Months__c Logic
    public static void calculateOdometerDifference(List<Application_Oil_Change__c> newRecords) {
        Set<Id> applicationIds = new Set<Id>();
        for (Application_Oil_Change__c rec : newRecords) {
            if (rec.Application__c != null) {
                applicationIds.add(rec.Application__c);
            }
        }
        if (applicationIds.isEmpty()) return;

        // Query latest previous oil change for each Application__c
        Map<Id, Application_Oil_Change__c> latestByApp = new Map<Id, Application_Oil_Change__c>();
        List<Application_Oil_Change__c> latestRecords = [
            SELECT Id, Application__c, Odometer_KM__c, CreatedDate, Schedule_Date_Of_Service__c
            FROM Application_Oil_Change__c
            WHERE Application__c IN :applicationIds
            AND Id NOT IN :newRecords
            ORDER BY Application__c, Schedule_Date_Of_Service__c DESC
        ];
        for (Application_Oil_Change__c rec : latestRecords) {
            if (!latestByApp.containsKey(rec.Application__c)) {
                latestByApp.put(rec.Application__c, rec);
            }
        }

        // For Application__c with no previous oil change, get Vehicle__r.Odometer__c and Purchase_Date__c
        Map<Id, Decimal> appToVehicleOdometer = new Map<Id, Decimal>();
        Map<Id, Date> appToVehiclePurchaseDate = new Map<Id, Date>();
        Set<Id> appsNeedingVehicleData = new Set<Id>();
        for (Application_Oil_Change__c rec : newRecords) {
            if (rec.Application__c != null && !latestByApp.containsKey(rec.Application__c)) {
                appsNeedingVehicleData.add(rec.Application__c);
            }
        }
        if (!appsNeedingVehicleData.isEmpty()) {
            for (Application__c app : [
                SELECT Id, Vehicle__r.Odometer__c, Vehicle__r.Purchase_Date__c
                FROM Application__c
                WHERE Id IN :appsNeedingVehicleData
            ]) {
                if (app.Vehicle__r != null) {
                    appToVehicleOdometer.put(app.Id, app.Vehicle__r.Odometer__c);
                    appToVehiclePurchaseDate.put(app.Id, app.Vehicle__r.Purchase_Date__c);
                }
            }
        }

        // Set the difference value in Odometer_Difference_KM__c and Duration_Months__c
        for (Application_Oil_Change__c rec : newRecords) {
            if (rec.Application__c != null) {
                // Odometer Difference
                if (rec.Odometer_KM__c != null) {
                    Application_Oil_Change__c latest = latestByApp.get(rec.Application__c);
                    if (latest != null && latest.Odometer_KM__c != null) {
                        rec.Odometer_Difference_KM__c = rec.Odometer_KM__c - latest.Odometer_KM__c;
                    } else {
                        Decimal vehicleOdometer = appToVehicleOdometer.get(rec.Application__c);
                        if (vehicleOdometer != null) {
                            rec.Odometer_Difference_KM__c = rec.Odometer_KM__c - vehicleOdometer;
                        } else {
                            rec.Odometer_Difference_KM__c = null; // Or 0 if you prefer
                        }
                    }
                }
                // Duration_Months__c
                if (rec.Schedule_Date_Of_Service__c != null) {
                    Application_Oil_Change__c latest = latestByApp.get(rec.Application__c);
                    if (latest != null && latest.Schedule_Date_Of_Service__c != null) {
                        rec.Duration_Months__c = monthsBetween(latest.Schedule_Date_Of_Service__c, rec.Schedule_Date_Of_Service__c);
                    } else {
                        Date purchaseDate = appToVehiclePurchaseDate.get(rec.Application__c);
                        if (purchaseDate != null) {
                            rec.Duration_Months__c = monthsBetween(purchaseDate, rec.Schedule_Date_Of_Service__c);
                        } else {
                            rec.Duration_Months__c = null;
                        }
                    }
                }
            }
        }
    }

    // Claim Update Logic
    public static void updateClaimOilChangeCounts(List<Application_Oil_Change__c> oilChanges) {
        Set<Id> applicationIds = new Set<Id>();
        for (Application_Oil_Change__c oil : oilChanges) {
            if (oil.Application__c != null) {
                applicationIds.add(oil.Application__c);
            }
        }
        if (applicationIds.isEmpty()) return;

        // Aggregate counts of Oil Changes by Application and Type
        Map<Id, Integer> standardCounts = new Map<Id, Integer>();
        Map<Id, Integer> syntheticCounts = new Map<Id, Integer>();

        for (AggregateResult ar : [
            SELECT Application__c, Type__c, COUNT(Id) oilChangeCount
            FROM Application_Oil_Change__c
            WHERE Application__c IN :applicationIds
            GROUP BY Application__c, Type__c
        ]) {
            Id appId = (Id)ar.get('Application__c');
            String type = (String)ar.get('Type__c');
            Integer count = (Integer)ar.get('oilChangeCount');
            if (type == 'Standard') {
                standardCounts.put(appId, count);
            } else if (type == 'Synthetic') {
                syntheticCounts.put(appId, count);
            }
        }

        // Find all Claims for these Applications
        List<Claim__c> claimsToUpdate = [
            SELECT Id, Application__c
            FROM Claim__c
            WHERE Application__c IN :applicationIds
        ];

        for (Claim__c claim : claimsToUpdate) {
            Id appId = claim.Application__c;
            claim.Actual_Oil_Change_Duration_Standard__c = standardCounts.get(appId) != null ? standardCounts.get(appId) : 0;
            claim.Actual_Oil_Change_Duration_Synthetic__c = syntheticCounts.get(appId) != null ? syntheticCounts.get(appId) : 0;
        }

        if (!claimsToUpdate.isEmpty()) {
            update claimsToUpdate;
        }
    }
}