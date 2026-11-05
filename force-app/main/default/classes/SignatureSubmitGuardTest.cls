/**
 * SignatureSubmitGuardTest
 * Proof of the submit gate:
 *   - both documents signed          -> submit succeeds
 *   - one document unsigned          -> refused, message names only that one
 *   - warranty-only application      -> allowed without a Tire & Rim document
 *   - warranty-only, unsigned        -> refused naming the warranty only
 *   - one of two signers             -> still refused (both required)
 *   - no contract packages           -> not gated
 *   - a non-Submitted status         -> not gated (Quote -> Convert path)
 */
@IsTest
private class SignatureSubmitGuardTest {

    private static final String PNG_1x1 =
        'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAD0lEQVR42mP4jwMwDC0JALoev0GJ6La7AAAAAElFTkSuQmCC';

    // ------------------------------------------------------------------ fixtures

    /**
     * An application always carries an Opportunity: the org's
     * "Update Opportunity Statuses" flow rejects updating an Application whose
     * Opportunity is null, and the submit path must update the record.
     */
    private static Id newApplication(Id dealerAccountId) {
        Opportunity opp = new Opportunity(
            Name = 'Signature Gate Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(7),
            AccountId = dealerAccountId
        );
        insert opp;

        Application__c app = new Application__c(
            Commercial_Business_Use__c = false,
            Show_Comments_On_Print__c = false,
            Is_Vehicle_Financed__c = false,
            Application_Status__c = 'Draft',
            Opportunity__c = opp.Id
        );
        insert app;
        return app.Id;
    }

    private static Id newDealer() {
        Account dealer = new Account(Name = 'Signature Gate Test Dealer');
        insert dealer;
        return dealer.Id;
    }

    private static void addPackage(Id applicationId, Id dealerId, String recordTypeDeveloperName) {
        Application_Package__c pkg = new Application_Package__c(
            Application__c = applicationId,
            Dealer__c = dealerId,
            Active__c = true,
            RecordTypeId = Schema.SObjectType.Application_Package__c
                .getRecordTypeInfosByDeveloperName()
                .get(recordTypeDeveloperName)
                .getRecordTypeId()
        );
        insert pkg;
    }

    /** Both signers sign one document. */
    private static void signDocument(Id applicationId, String documentType) {
        Integer i = 0;
        for (String role : SignatureService.ROLES) {
            i++;
            SignatureService.saveSignature(applicationId, PNG_1x1, 'Signer ' + role,
                'guard-' + documentType + '-' + role + '-' + applicationId + '-' + i,
                documentType, role);
        }
    }

    private static Map<String, Object> submit(Id applicationId) {
        return DealerPortalController.updateApplicationStatus(
            String.valueOf(applicationId), 'Submitted');
    }

    private static String statusOf(Id applicationId) {
        return [
            SELECT Application_Status__c FROM Application__c WHERE Id = :applicationId
        ].Application_Status__c;
    }

    // --------------------------------------------------------------------- tests

    @IsTest
    static void bothDocumentsSignedAllowsSubmit() {
        Id dealerId = newDealer();
        Id appId = newApplication(dealerId);
        addPackage(appId, dealerId, SignatureSubmitGuard.RT_WARRANTY);
        addPackage(appId, dealerId, SignatureSubmitGuard.RT_TIRE_RIM);

        signDocument(appId, 'Warranty');
        signDocument(appId, 'TireRim');

        SignatureSubmitGuard.Requirements req = SignatureSubmitGuard.forApplication(appId);
        System.assertEquals(true, req.allComplete, 'both documents fully signed');
        System.assertEquals(2, req.documents.size(), 'both documents are required');
        System.assertEquals(null, req.missingMessage, 'nothing is missing');

        Test.startTest();
        Map<String, Object> res = submit(appId);
        Test.stopTest();

        System.assertEquals(true, res.get('success'),
            'a fully signed application submits: ' + res.get('message'));
        System.assertEquals('Submitted', statusOf(appId));
    }

    @IsTest
    static void oneMissingDocumentIsRefusedAndNamed() {
        Id dealerId = newDealer();
        Id appId = newApplication(dealerId);
        addPackage(appId, dealerId, SignatureSubmitGuard.RT_WARRANTY);
        addPackage(appId, dealerId, SignatureSubmitGuard.RT_TIRE_RIM);

        signDocument(appId, 'Warranty'); // Tire & Rim deliberately left unsigned

        SignatureSubmitGuard.Requirements req = SignatureSubmitGuard.forApplication(appId);
        System.assertEquals(false, req.allComplete);
        System.assertEquals('Tire & Rim', req.missingLabels,
            'the message names exactly the document that is missing');
        System.assert(req.missingMessage.startsWith(
            'Sign the Tire & Rim document before submitting'), req.missingMessage);
        System.assertEquals(false, req.missingMessage.contains('Extended Warranty'),
            'a signed document is never named as missing: ' + req.missingMessage);

        Test.startTest();
        Map<String, Object> res = submit(appId);
        Test.stopTest();

        System.assertEquals(false, res.get('success'), 'submit must be refused');
        String message = (String) res.get('message');
        System.assert(message.contains('Tire & Rim'), message);
        System.assertEquals(false, message.contains('Extended Warranty'), message);
        System.assertNotEquals('Submitted', statusOf(appId),
            'the refused submit must not change the status');
    }

    @IsTest
    static void warrantyOnlyApplicationIsNotBlockedByMissingTireRim() {
        Id dealerId = newDealer();
        Id appId = newApplication(dealerId);
        addPackage(appId, dealerId, SignatureSubmitGuard.RT_WARRANTY);

        signDocument(appId, 'Warranty');

        SignatureSubmitGuard.Requirements req = SignatureSubmitGuard.forApplication(appId);
        System.assertEquals(1, req.documents.size(),
            'only the document the application carries is required');
        System.assertEquals('Warranty', req.documents[0].documentType);
        System.assertEquals(true, req.allComplete,
            'a warranty-only application has nothing else to sign');

        Test.startTest();
        Map<String, Object> res = submit(appId);
        Test.stopTest();

        System.assertEquals(true, res.get('success'),
            'warranty-only application submits: ' + res.get('message'));
        System.assertEquals('Submitted', statusOf(appId));
    }

    @IsTest
    static void warrantyOnlyUnsignedNamesOnlyTheWarranty() {
        Id dealerId = newDealer();
        Id appId = newApplication(dealerId);
        addPackage(appId, dealerId, SignatureSubmitGuard.RT_WARRANTY);
        // no Tire & Rim package at all

        Map<String, Object> res = submit(appId);

        System.assertEquals(false, res.get('success'));
        String message = (String) res.get('message');
        System.assert(message.contains('Extended Warranty'), message);
        System.assertEquals(false, message.contains('Tire & Rim'),
            'a document the application does not carry is never demanded: ' + message);
        System.assertNotEquals('Submitted', statusOf(appId));
    }

    @IsTest
    static void bothSignersAreRequired() {
        Id dealerId = newDealer();
        Id appId = newApplication(dealerId);
        addPackage(appId, dealerId, SignatureSubmitGuard.RT_WARRANTY);

        SignatureService.saveSignature(appId, PNG_1x1, 'Customer', 'one-of-two-1', 'Warranty', 'Customer');

        SignatureSubmitGuard.Requirements req = SignatureSubmitGuard.forApplication(appId);
        System.assertEquals(false, req.allComplete);
        System.assertEquals(1, req.documents[0].rolesCaptured);
        System.assertEquals(2, req.documents[0].rolesRequired);

        Map<String, Object> res = submit(appId);
        System.assertEquals(false, res.get('success'), 'one of two signers is not signed');
        System.assert(((String) res.get('message')).contains('Extended Warranty'),
            (String) res.get('message'));
        System.assert(((String) res.get('message')).contains('both signatures'),
            (String) res.get('message'));
    }

    @IsTest
    static void applicationWithNoContractDocumentsIsNotGated() {
        Id dealerId = newDealer();
        Id appId = newApplication(dealerId);
        addPackage(appId, dealerId, 'GAP_Coverage'); // Total Loss only - no contract to sign

        SignatureSubmitGuard.Requirements req = SignatureSubmitGuard.forApplication(appId);
        System.assertEquals(false, req.hasRequiredDocuments);
        System.assertEquals(true, req.allComplete);
        System.assertEquals(null, req.missingMessage);

        Map<String, Object> res = submit(appId);
        System.assertEquals(true, res.get('success'),
            'nothing to sign, nothing to block: ' + res.get('message'));
    }

    @IsTest
    static void otherStatusTransitionsAreNotGated() {
        Id dealerId = newDealer();
        Id appId = newApplication(dealerId);
        addPackage(appId, dealerId, SignatureSubmitGuard.RT_WARRANTY);

        // Quote -> Convert path (status Draft) and any non-Submitted write is untouched.
        Map<String, Object> res = DealerPortalController.updateApplicationStatus(
            String.valueOf(appId), 'Cancelled');
        System.assertEquals(true, res.get('success'),
            'only Submitted is gated: ' + res.get('message'));
        System.assertEquals('Cancelled', statusOf(appId));
    }

    @IsTest
    static void requirementsPayloadDrivesTheButton() {
        Id dealerId = newDealer();
        Id appId = newApplication(dealerId);
        addPackage(appId, dealerId, SignatureSubmitGuard.RT_WARRANTY);
        addPackage(appId, dealerId, SignatureSubmitGuard.RT_TIRE_RIM);

        SignatureSubmitGuard.Requirements before =
            SignaturePadController.getSignatureRequirements(appId);
        System.assertEquals(false, before.allComplete);
        System.assertEquals(2, before.documents.size());
        System.assertEquals(0, before.documents[0].rolesCaptured);
        System.assertEquals('Extended Warranty and Tire & Rim', before.missingLabels);
        System.assert(before.missingMessage.startsWith(
            'Sign the Extended Warranty and Tire & Rim documents before submitting'),
            before.missingMessage);

        signDocument(appId, 'Warranty');
        signDocument(appId, 'TireRim');

        SignatureSubmitGuard.Requirements after =
            SignaturePadController.getSignatureRequirements(appId);
        System.assertEquals(true, after.allComplete);
        System.assertEquals(null, after.missingMessage);
        System.assertEquals(true, after.documents[0].complete);
        System.assertEquals(true, after.documents[1].complete);

        // no application selected -> nothing to gate
        SignatureSubmitGuard.Requirements none =
            SignaturePadController.getSignatureRequirements(null);
        System.assertEquals(true, none.allComplete);
    }
}