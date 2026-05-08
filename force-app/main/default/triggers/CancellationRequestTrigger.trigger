trigger CancellationRequestTrigger on App_Cancellation_Request__c (after insert, after update) {
    CancellationRequestHandler.handle(Trigger.new, Trigger.oldMap, Trigger.isInsert, Trigger.isUpdate);
}