public with sharing class PaymentSuccessController {
    
    @AuraEnabled(cacheable=true)
    public static RemittanceFormDetails getRemittanceFormDetails(String remittanceFormId) {
        if (String.isBlank(remittanceFormId)) {
            throw new AuraHandledException('Remittance Form ID is required.');
        }
        
        List<Remittance_Form__c> forms = [
            SELECT Id, Name, Amount__c, Paid_Amount__c, Balance__c, Status__c, 
                   CreatedDate, Dealer_Name__r.Name
            FROM Remittance_Form__c
            WHERE Id = :remittanceFormId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        
        if (forms.isEmpty()) {
            throw new AuraHandledException('Remittance Form not found.');
        }
        
        Remittance_Form__c form = forms[0];
        RemittanceFormDetails details = new RemittanceFormDetails();
        details.remittanceFormId = form.Id;
        details.remittanceFormName = form.Name;
        details.totalAmount = form.Amount__c;
        details.paidAmount = form.Paid_Amount__c;
        details.balance = form.Balance__c;
        details.status = form.Status__c;
        details.createdDate = form.CreatedDate;
        details.dealerName = form.Dealer_Name__r != null ? form.Dealer_Name__r.Name : '';
        
        return details;
    }
    
    public class RemittanceFormDetails {
        @AuraEnabled public Id remittanceFormId;
        @AuraEnabled public String remittanceFormName;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public Decimal paidAmount;
        @AuraEnabled public Decimal balance;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String dealerName;
    }
}