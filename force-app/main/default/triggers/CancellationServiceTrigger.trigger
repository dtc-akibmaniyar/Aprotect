trigger CancellationServiceTrigger on Cancellation_Service__c (after insert) {
    // Service numbering is presentation only and must never be able to abort the
    // caller's transaction. These rows are inserted as part of the dealer portal
    // submit transaction, so an exception escaping here would roll back the parent
    // App_Cancellation_Request__c too and the dealer would be told the submission
    // failed even though the request was valid.
    try {
        CancellationRequestHandler.handleServiceAfterInsert(Trigger.new);
    } catch (Exception e) {
        System.debug(LoggingLevel.WARN, 'CancellationServiceTrigger swallowed a non-fatal error: ' + e.getMessage());
    }
}