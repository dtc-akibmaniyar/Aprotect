trigger CancellationServiceTrigger on Cancellation_Service__c (after insert) {
    CancellationRequestHandler.handleServiceAfterInsert(Trigger.new);
}