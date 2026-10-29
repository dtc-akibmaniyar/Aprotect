@isTest
private class SignatureServiceTest {

    private static final String PNG_1x1 =
        'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAD0lEQVR42mP4jwMwDC0JALoev0GJ6La7AAAAAElFTkSuQmCC';

    private static Id newApplication() {
        Application__c app = new Application__c(
            Commercial_Business_Use__c = false,
            Show_Comments_On_Print__c = false,
            Is_Vehicle_Financed__c = false
        );
        insert app;
        return app.Id;
    }

    private static List<Id> captureAllThree(Id appId, String docType, String keyPrefix) {
        List<Id> ids = new List<Id>();
        Integer i = 0;
        for (String role : SignatureService.ROLES) {
            i++;
            ids.add(SignatureService.saveSignature(
                appId, PNG_1x1, 'Signer ' + role, keyPrefix + '-' + i, docType, role).signatureId);
        }
        return ids;
    }

    private static void stage(Id sigId, String resourceName) {
        update new Application_Signature__c(
            Id = sigId, ResourceId__c = '081G1000003PhZZIA0', ResourceName__c = resourceName
        );
    }

    @isTest
    static void captureIsValidatedAndIdempotent() {
        Id appId = newApplication();

        try {
            SignatureService.saveSignature(appId, PNG_1x1, 'T', null, 'Warranty');
            System.assert(false, 'blank idemKey must throw');
        } catch (SignatureService.SignatureServiceException e) {
            System.assert(e.getMessage().contains('idemKey'));
        }

        try {
            SignatureService.saveSignature(appId, 'not-a-png', 'T', 'K1', 'Warranty');
            System.assert(false, 'non-PNG payload must throw');
        } catch (SignatureService.SignatureServiceException e) {
            System.assert(e.getMessage().contains('PNG'));
        }

        SignatureService.SaveResult first =
            SignatureService.saveSignature(appId, PNG_1x1, 'Tester', 'K1', 'Tire & Rim');
        System.assertNotEquals(null, first.signatureId);
        System.assertEquals(true, first.created);
        System.assertEquals('CAPTURED', first.status);
        System.assertEquals('Customer', first.signerRole, 'the 5-arg overload is the customer');

        SignatureService.SaveResult replay =
            SignatureService.saveSignature(appId, PNG_1x1, 'Tester', 'K1', 'Warranty');
        System.assertEquals(first.signatureId, replay.signatureId);
        System.assertEquals(false, replay.created);

        System.assertEquals(1, [SELECT COUNT() FROM Application_Signature__c WHERE Application__c = :appId]);
    }

    /** Three roles -> three rows; re-signing a role reuses its row. */
    @isTest
    static void oneRowPerRoleAndReSignReusesTheRow() {
        Id appId = newApplication();
        List<Id> ids = captureAllThree(appId, 'Warranty', 'ROLE');

        System.assertEquals(3, [
            SELECT COUNT() FROM Application_Signature__c WHERE Application__c = :appId
        ]);

        Set<String> roles = new Set<String>();
        for (Application_Signature__c r : [
            SELECT Signer_Role__c FROM Application_Signature__c WHERE Application__c = :appId
        ]) {
            roles.add(r.Signer_Role__c);
        }
        System.assertEquals(3, roles.size());
        System.assertEquals(true, roles.contains('Customer'));
        System.assertEquals(true, roles.contains('DealerRep'));
        System.assertEquals(true, roles.contains('ContractHolder'));

        // New gesture, same role -> same row, reset to CAPTURED, no duplicate.
        SignatureService.SaveResult again = SignatureService.saveSignature(
            appId, PNG_1x1, 'Rep Again', 'ROLE-again', 'Warranty', 'DealerRep');
        System.assertEquals(ids[1], again.signatureId);
        System.assertEquals(false, again.created);
        System.assertEquals(3, [
            SELECT COUNT() FROM Application_Signature__c WHERE Application__c = :appId
        ]);

        // Replaying a key under a different role is refused.
        try {
            SignatureService.saveSignature(appId, PNG_1x1, 'X', 'ROLE-again', 'Warranty', 'Customer');
            System.assert(false, 'an idemKey must not be reused for another role');
        } catch (SignatureService.SignatureServiceException e) {
            System.assert(e.getMessage().contains('signer role'));
        }

        try {
            SignatureService.saveSignature(appId, PNG_1x1, 'X', 'ROLE-X', 'Warranty', 'Nope');
            System.assert(false, 'an unknown role must throw');
        } catch (SignatureService.SignatureServiceException e) {
            System.assert(e.getMessage().contains('unsupported signerRole'));
        }

        // Blank role on a legacy row still reads as the customer.
        System.assertEquals('Customer', SignatureService.effectiveRole(null));
        System.assertEquals('ContractHolder', SignatureService.effectiveRole('Contract Holder'));
    }

    @isTest
    static void stageImageIsGuardedAndIdempotentWhenAlreadyStaged() {
        // missing row
        try {
            SignatureService.stageImage(null);
            System.assert(false, 'null id must throw');
        } catch (SignatureService.SignatureServiceException e) {
            System.assert(e.getMessage().contains('required'));
        }

        Id appId = newApplication();
        Id sigId = SignatureService.saveSignature(appId, PNG_1x1, 'Tester', 'K2', 'Warranty').signatureId;

        // already staged -> returns the committed name, does not call out
        stage(sigId, 'SIGTMP_test000001');
        System.assertEquals('SIGTMP_test000001', SignatureService.stageImage(sigId));

        // blank payload on an unstaged row -> throws before any callout
        Application_Signature__c empty = new Application_Signature__c(
            Application__c = appId,
            Document_Type__c = 'Warranty',
            Signer_Role__c = 'DealerRep',
            IdemKey__c = 'K9',
            PngBytes__c = 0,
            Status__c = 'CAPTURED'
        );
        insert empty;
        try {
            SignatureService.stageImage(empty.Id);
            System.assert(false, 'blank payload must throw');
        } catch (SignatureService.SignatureServiceException e) {
            System.assert(e.getMessage().contains('PNG'));
        }
    }

    /** issuePdf refuses until every role has a committed staged image. */
    @isTest
    static void renderNeedsAllThreeStagedRoles() {
        Id appId = newApplication();
        List<Id> ids = captureAllThree(appId, 'Warranty', 'STAGE');
        System.assertEquals(3, ids.size());
        System.assertEquals(3, new Set<Id>(ids).size(), 'each role gets its own row');
        stage(ids[0], 'SIGTMP_stage_customer');
        stage(ids[1], 'SIGTMP_stage_rep');

        try {
            SignatureService.issuePdf(ids[0]);
            System.assert(false, 'two staged images must not be rendered');
        } catch (SignatureService.SignatureServiceException e) {
            System.assert(e.getMessage().contains('ContractHolder'), e.getMessage());
            System.assert(e.getMessage().contains('all three signers'), e.getMessage());
        }

        stage(ids[2], 'SIGTMP_stage_holder');

        SignatureService.SignatureStatus st = SignatureService.getStatus(appId, 'Warranty');
        System.assertEquals(true, st.hasSignature);
        System.assertEquals(true, st.allRolesCaptured);
        System.assertEquals(false, st.hasPdf, 'nothing rendered yet');
        System.assertEquals(3, st.roles.size());
    }

    /** An already-rendered contract returns the stored PDF without touching the renderer. */
    @isTest
    static void issuePdfReturnsTheStoredPdfWithoutRendering() {
        Id appId = newApplication();

        ContentVersion cv = new ContentVersion(
            Title = 'already rendered', PathOnClient = 'already.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 test'));
        insert cv;
        cv = [SELECT Id FROM ContentVersion WHERE Id = :cv.Id];

        List<Application_Signature__c> rows = new List<Application_Signature__c>();
        Integer i = 0;
        for (String role : SignatureService.ROLES) {
            i++;
            rows.add(new Application_Signature__c(
                Application__c = appId,
                Document_Type__c = 'Warranty',
                Signer_Role__c = role,
                IdemKey__c = 'PDFREADY-' + i,
                PngB64__c = PNG_1x1,
                PngBytes__c = 1,
                Status__c = 'RENDERED',
                Pdf_Document_Id__c = String.valueOf(cv.Id)
            ));
        }
        insert rows;

        System.assertEquals(String.valueOf(cv.Id), SignatureService.issuePdf(rows[0].Id));
        System.assertEquals(String.valueOf(cv.Id), SignatureService.issuePdf(rows[2].Id));
    }

    /** A row with no staged image closes cleanly; drop is idempotent on the pointer. */
    @isTest
    static void dropClosesEveryRoleRow() {
        Id appId = newApplication();
        List<Id> ids = captureAllThree(appId, 'TireRim', 'DROP');
        for (Id sigId : ids) {
            SignatureService.dropResource(sigId);
        }
        for (Application_Signature__c r : [
            SELECT Status__c, ResourceId__c, ResourceName__c
            FROM Application_Signature__c WHERE Application__c = :appId
        ]) {
            System.assertEquals('DONE', r.Status__c);
            System.assertEquals(null, r.ResourceId__c);
            System.assertEquals(null, r.ResourceName__c);
        }
    }

    @isTest
    static void guardsAndStatusBranches() {
        Id appId = newApplication();

        try {
            SignatureService.saveSignature(null, PNG_1x1, 'T', 'KA', 'Warranty');
            System.assert(false, 'missing applicationId must throw');
        } catch (SignatureService.SignatureServiceException e) {
            System.assert(e.getMessage().contains('applicationId'));
        }

        try {
            SignatureService.saveSignature(appId, '   ', 'T', 'KB', 'Warranty');
            System.assert(false, 'blank payload must throw');
        } catch (SignatureService.SignatureServiceException e) {
            System.assert(e.getMessage().contains('pngB64'));
        }

        try {
            SignatureService.saveSignature(appId, PNG_1x1, 'T', 'KC', 'Boat');
            System.assert(false, 'unsupported document type must throw');
        } catch (SignatureService.SignatureServiceException e) {
            System.assert(e.getMessage().contains('unsupported'));
        }

        String huge = 'iVBORw0KGgo' + 'A'.repeat(200000);
        try {
            SignatureService.saveSignature(appId, huge, 'T', 'KD', 'Warranty');
            System.assert(false, 'oversized payload must throw');
        } catch (SignatureService.SignatureServiceException e) {
            System.assert(e.getMessage().contains('too large'));
        }

        // data-URI prefix + embedded whitespace are normalised away
        SignatureService.SaveResult ok = SignatureService.saveSignature(
            appId, 'data:image/png;base64,' + PNG_1x1.left(40) + ' ' + PNG_1x1.substring(40), 'T', 'KE', '');
        System.assertEquals('CAPTURED', ok.status);

        // same idemKey, different payload size -> refused
        update new Application_Signature__c(Id = ok.signatureId, PngBytes__c = 1);
        try {
            SignatureService.saveSignature(appId, PNG_1x1, 'T', 'KE', 'Warranty');
            System.assert(false, 'size mismatch must throw');
        } catch (SignatureService.SignatureServiceException e) {
            System.assert(e.getMessage().contains('different payload size'));
        }

        // a "data:" prefix without a comma is not a data-URI and must not be stripped
        try {
            SignatureService.saveSignature(appId, 'data:image/png;base64' + PNG_1x1, 'T', 'KF', 'Warranty');
            System.assert(false, 'a data: prefix with no comma must be treated as raw base64');
        } catch (SignatureService.SignatureServiceException e) {
            System.assert(e.getMessage().contains('PNG'));
        }

        // status branches: null app, blank type, explicit tire & rim
        System.assertEquals(false, SignatureService.getStatus(null, null).hasSignature);
        SignatureService.SignatureStatus onlyCustomer = SignatureService.getStatus(appId, null);
        System.assertEquals(false, onlyCustomer.hasSignature, 'one role is not signed');
        System.assertEquals(true, onlyCustomer.roles[0].captured);
        System.assertEquals(false, onlyCustomer.roles[1].captured);
        System.assertEquals(false, SignatureService.getStatus(appId, 'TireRim').hasSignature);

        try {
            SignatureService.dropResource(null);
            System.assert(false, 'null id must throw');
        } catch (SignatureService.SignatureServiceException e) {
            System.assert(e.getMessage().contains('required'));
        }
        try {
            SignatureService.dropResource('a3EG10000000000AAA');
            System.assert(false, 'unknown id must throw');
        } catch (SignatureService.SignatureServiceException e) {
            System.assert(e.getMessage().contains('not found'));
        }
    }

    @isTest
    static void statusResolvesTheContentDocumentOfAStoredPdf() {
        Id appId = newApplication();

        ContentVersion cv = new ContentVersion(
            Title = 'stored contract',
            PathOnClient = 'stored.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 test')
        );
        insert cv;
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        List<Application_Signature__c> rows = new List<Application_Signature__c>();
        Integer i = 0;
        for (String role : SignatureService.ROLES) {
            i++;
            rows.add(new Application_Signature__c(
                Application__c = appId,
                Document_Type__c = 'Warranty',
                Signer_Role__c = role,
                IdemKey__c = 'KPDF-' + i,
                PngB64__c = PNG_1x1,
                PngBytes__c = 1,
                Status__c = 'RENDERED',
                Pdf_Document_Id__c = String.valueOf(cv.Id)
            ));
        }
        insert rows;

        SignatureService.SignatureStatus st = SignatureService.getStatus(appId, 'Warranty');
        System.assertEquals(true, st.hasSignature);
        System.assertEquals(String.valueOf(cv.Id), st.pdfDocumentId);
        System.assertEquals(String.valueOf(cv.ContentDocumentId), st.pdfContentDocumentId);
    }
}