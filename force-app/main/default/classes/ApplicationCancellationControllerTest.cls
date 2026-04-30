@isTest(SeeAllData=false)
private class ApplicationCancellationControllerTest {

    @TestSetup
    static void setup() {
        Account        dealer  = TestDataFactory.createDealer(true);
        Vehicle__c     vehicle = TestDataFactory.createVehicle(true);
        Application__c app     = TestDataFactory.createSubmittedApplication(dealer.Id, false);
        app.Vehicle__c = vehicle.Id;
         Opportunity opp = new Opportunity(
        Name        = 'Test Opportunity',
        AccountId   = dealer.Id,
        StageName   = 'Prospecting',
        CloseDate   = Date.today().addDays(30)
    );
    insert opp;
    app.Opportunity__c = opp.Id;
    insert app;

        Id cancelRT  = TestDataFactory.getRecordTypeId('Policy__c', 'Cancellation_Policy');
        Id privacyRT = TestDataFactory.getRecordTypeId('Policy__c', 'Privacy_Policy_Terms_Conditions');
        insert new List<Policy__c>{
            new Policy__c(Name = 'Cancellation Policy Test',  Policy_Text__c = 'Test cancellation text.', RecordTypeId = cancelRT),
            new Policy__c(Name = 'Privacy Policy Test',       Policy_Text__c = 'Test privacy text.',      RecordTypeId = privacyRT)
        };
    }

    private static Application__c getApplication() {
        return [SELECT Id FROM Application__c LIMIT 1];
    }

    @isTest
    static void testGetVehicleInfo_withVehicle_returnsPopulatedInfo() {
        Application__c app = getApplication();
        Test.startTest();
            ApplicationCancellationController.CancellationVehicleInfo result =
                ApplicationCancellationController.getVehicleInfoForCancellation(app.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        // VIN is set by factory createVehicle
        System.assertNotEquals(null, result.vehicleVIN, 'vehicleVIN should be populated');
    }

    @isTest
static void testGetVehicleInfo_noVehicleLinked_returnsNullFields() {
    Account dealer = [
        SELECT Id FROM Account
        WHERE RecordType.DeveloperName = 'Dealer_Account' LIMIT 1
    ];

    // Link Opportunity so the flow doesn't fail if this app is ever updated
    Opportunity opp = new Opportunity(
        Name      = 'Test Opp No Vehicle',
        AccountId = dealer.Id,
        StageName = 'Prospecting',
        CloseDate = Date.today().addDays(30)
    );
    insert opp;

    Application__c app = TestDataFactory.createSubmittedApplication(dealer.Id, false);
    app.Opportunity__c = opp.Id;
    // Vehicle__c intentionally not set
    insert app;

    Test.startTest();
        ApplicationCancellationController.CancellationVehicleInfo result =
            ApplicationCancellationController.getVehicleInfoForCancellation(app.Id);
    Test.stopTest();

    System.assertNotEquals(null, result,
        'Result should not be null when no vehicle linked');
    System.assertEquals(null, result.vehicleName,
        'vehicleName should be null when Vehicle__r is null');
}

    @isTest
    static void testGetVehicleInfo_invalidId_throwsAuraHandledException() {
        // Pass a well-formed but non-existent Id so the Id type is satisfied
        Boolean thrown = false;
        Test.startTest();
        try {
            ApplicationCancellationController.getVehicleInfoForCancellation(
                'a0000000000000ZAAQ'
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown,
            'Non-existent Id should throw AuraHandledException via catch block');
    }

    @isTest
    static void testGetPolicies_returnsBothRecordTypes() {
        Test.startTest();
            List<Policy__c> policies = ApplicationCancellationController.getPolicies();
        Test.stopTest();

        System.assertEquals(2, policies.size(),
            'Both Cancellation_Policy and Privacy_Policy_Terms_Conditions should be returned');
    }

    @isTest
    static void testSavePoliciesAndCancel_nullApplicationId_throwsAuraHandledException() {
        Boolean thrown = false;
        Test.startTest();
        try {
            ApplicationCancellationController.savePoliciesAndCancel(null, null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown, 'Null applicationId should throw AuraHandledException');
    }

    @isTest
    static void testSavePoliciesAndCancel_validPolicies() {
        Application__c app = getApplication();

        ApplicationCancellationController.PolicyWrapper pw =
            new ApplicationCancellationController.PolicyWrapper();
        pw.Name                 = 'Cancellation Policy Test';
        pw.policyText           = 'Test cancellation text.';
        pw.privacyTermsAccepted = true;

        Test.startTest();
            ApplicationCancellationController.savePoliciesAndCancel(
                app.Id,
                new List<ApplicationCancellationController.PolicyWrapper>{ pw }
            );
        Test.stopTest();

        Application__c updated = [SELECT Application_Status__c FROM Application__c WHERE Id = :app.Id];
        System.assertEquals('Cancelled', updated.Application_Status__c,
            'Application status should be Cancelled');
    }

    @isTest
    static void testSavePoliciesAndCancel_emptyList() {
        Application__c app = getApplication();

        Test.startTest();
            ApplicationCancellationController.savePoliciesAndCancel(
                app.Id,
                new List<ApplicationCancellationController.PolicyWrapper>()
            );
        Test.stopTest();

        Application__c updated = [SELECT Application_Status__c FROM Application__c WHERE Id = :app.Id];
        System.assertEquals('Cancelled', updated.Application_Status__c,
            'Application should be Cancelled even with empty policies list');
    }

    @isTest
    static void testSavePoliciesAndCancel_nullList() {
        Application__c app = getApplication();

        Test.startTest();
            ApplicationCancellationController.savePoliciesAndCancel(app.Id, null);
        Test.stopTest();

        Application__c updated = [SELECT Application_Status__c FROM Application__c WHERE Id = :app.Id];
        System.assertEquals('Cancelled', updated.Application_Status__c,
            'Application should be Cancelled when null policies list is passed');
    }
}