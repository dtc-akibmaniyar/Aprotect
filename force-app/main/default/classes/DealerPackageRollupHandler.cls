public class DealerPackageRollupHandler {
    
    public static void recalculateRollups(List<Application_Package__c> records, Map<Id, Application_Package__c> oldMap) {
        Set<Id> dpIds = new Set<Id>();
        
        for (Application_Package__c ap : records) {
            if (ap.Dealer_Package__c != null) dpIds.add(ap.Dealer_Package__c);
        }
        
        // Also include old dealer package IDs (in case reparented)
        if (oldMap != null) {
            for (Application_Package__c ap : oldMap.values()) {
                if (ap.Dealer_Package__c != null) dpIds.add(ap.Dealer_Package__c);
            }
        }
        
        if (dpIds.isEmpty()) return;
        
        // Query aggregates
        Map<Id, Dealer_Package__c> toUpdate = new Map<Id, Dealer_Package__c>();
        for (Id dpId : dpIds) {
            toUpdate.put(dpId, new Dealer_Package__c(
                Id = dpId,
                Total_Reserve_Accrued__c = 0,
                Total_Commission_Earned__c = 0,
                Total_Warranties_Sold__c = 0,
                Total_Revenue__c = 0,
                Total_Owed_To_Dealer__c = 0
            ));
        }
        
        for (AggregateResult ar : [
            SELECT Dealer_Package__c dpId,
                   SUM(Reserve_Amount__c) sumReserve,
                   SUM(Commission_Amount__c) sumCommission,
                   COUNT(Id) cnt,
                   SUM(Aprotect_Net__c) sumRevenue,
                   SUM(Owed_To_Dealer__c) sumOwed
            FROM Application_Package__c
            WHERE Dealer_Package__c IN :dpIds
            GROUP BY Dealer_Package__c
        ]) {
            Id dpId = (Id) ar.get('dpId');
            Dealer_Package__c dp = toUpdate.get(dpId);
            dp.Total_Reserve_Accrued__c = (Decimal) ar.get('sumReserve');
            dp.Total_Commission_Earned__c = (Decimal) ar.get('sumCommission');
            dp.Total_Warranties_Sold__c = (Decimal) ar.get('cnt');
            dp.Total_Revenue__c = (Decimal) ar.get('sumRevenue');
            dp.Total_Owed_To_Dealer__c = (Decimal) ar.get('sumOwed');
        }
        
        update toUpdate.values();
    }
}