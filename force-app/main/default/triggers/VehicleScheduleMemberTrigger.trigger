/**
 * VehicleScheduleMemberTrigger
 *
 * Before-insert / before-update key maintenance for Vehicle_Schedule_Member__c
 * (change-plan §04.1/§04.3, P1). Keeps the resolver's Member_Key__c index honest.
 */
trigger VehicleScheduleMemberTrigger on Vehicle_Schedule_Member__c (before insert, before update) {
    VehicleScheduleMemberKeyHandler.deriveMemberKeys(Trigger.new);
}