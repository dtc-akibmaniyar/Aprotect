public with sharing class DealerPortalTransactionHistoryController {
    @AuraEnabled(cacheable=true)
    public static List<Payment__c> getTransactionHistory(String recordId) {
        if (String.isBlank(recordId)) {
            throw new AuraHandledException('Record ID is required');
        }
        
        try {
            List<Payment__c> transactions = [
                SELECT Id,
                       RecordType.DeveloperName,
                       Cheque_Number__c,
                       Cheque_Date__c,
                       Amount__c,
                       Notes__c,
                       Transaction_Reference__c,
                       Card_Number__c,
                       Payment_Confirmation_Status__c,
                       Payment_Status__c,
                       Date_Time__c,
                       Payment_Initiated_Date__c,
                       Deposit_Pending_Date__c,
                       Transaction_Pending_Date__c,
                       Pending_Delivery_Date__c,
                       Deposit_Completed_Date__c,
                       Transaction_Completed_Date__c,
                       Hold_Date__c,
                       Failed_Payment_Date__c
                FROM Payment__c
                WHERE Remittance_Form__c = :recordId
                ORDER BY CreatedDate DESC
            ];
            
            return transactions;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving transaction history: ' + e.getMessage());
        }
    }
}