@isTest
private class TempDiagTest {
    @isTest
    static void diag() {
        Make__c p = new Make__c(Name='Porsche');
        insert p;
        Model__c mo = new Model__c(Name='911 GT3', Make__c=p.Id);
        insert mo;
        Vehicle_Schedule__c s = new Vehicle_Schedule__c(Name='Diag Sched 3', Type__c='Premium_Tier', Is_Active__c=true, Valid_From__c=Date.today());
        insert s;
        Vehicle_Schedule_Member__c m = new Vehicle_Schedule_Member__c(
            Name='Diag Member 3', Vehicle_Schedule__c=s.Id, Make__c=p.Id, Model__c=mo.Id,
            Include_All_Models__c=false, Is_Exclusion__c=false);
        insert m;

        Vehicle_Schedule_Member__c stored = [SELECT Member_Key__c FROM Vehicle_Schedule_Member__c WHERE Id = :m.Id];
        System.debug('TDIAG3 key1=' + stored.Member_Key__c);

        m.Is_Exclusion__c = true;
        try {
            update m;
            System.debug('TDIAG3 plain update OK');
        } catch (DmlException e) {
            System.debug('TDIAG3 PLAIN UPDATE FAIL fields=' + e.getDmlFields(0) + ' msg=' + e.getDmlMessage(0));
        }
        stored = [SELECT Member_Key__c FROM Vehicle_Schedule_Member__c WHERE Id = :m.Id];
        System.debug('TDIAG3 key2=' + stored.Member_Key__c);
        System.assert(true);
    }
}