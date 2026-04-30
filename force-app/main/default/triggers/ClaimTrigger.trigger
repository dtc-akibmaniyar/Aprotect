trigger ClaimTrigger on Claim__c (before insert) {
    // Collect Application Ids from new Claims
    Set<Id> applicationIds = new Set<Id>();
    for (Claim__c claim : Trigger.new) {
        if (claim.Application__c != null) {
            applicationIds.add(claim.Application__c);
        }
    }

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

    // Set the counts on the appropriate fields
    for (Claim__c claim : Trigger.new) {
        Id appId = claim.Application__c;
        claim.Actual_Oil_Change_Duration_Standard__c = standardCounts.get(appId) != null ? standardCounts.get(appId) : 0;
        claim.Actual_Oil_Change_Duration_Synthetic__c = syntheticCounts.get(appId) != null ? syntheticCounts.get(appId) : 0;
    }
}