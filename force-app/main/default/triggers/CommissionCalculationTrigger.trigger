trigger CommissionCalculationTrigger on Application_Package__c (before insert, before update, after insert, after update) {
    if (Trigger.isBefore) {
        CommissionCalculationHandler.calculate(Trigger.new);
    }
    if (Trigger.isAfter) {
        DealerPackageRollupHandler.recalculateRollups(Trigger.new, Trigger.oldMap);
    }
}