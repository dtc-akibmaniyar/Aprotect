@IsTest
private class SignaturePadControllerTest {

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

    @IsTest
    static void statusIsEmptyWithoutApplication() {
        SignatureService.SignatureStatus s = SignaturePadController.getStatus(null, 'Warranty');
        System.assertNotEquals(null, s);
        System.assertEquals(false, s.hasSignature);
        System.assertEquals(false, s.allRolesCaptured);
        System.assertEquals(0, s.roles.size());
        System.assertNotEquals(null, SignaturePadController.currentUserName());
    }

    @IsTest
    static void badInputIsRejectedAsAuraHandled() {
        Boolean threw = false;
        try {
            SignaturePadController.saveSignature(null, PNG_1x1, 'Tester', 'k1', 'Warranty', 'Customer');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'saveSignature without an application must fail');

        threw = false;
        try {
            SignaturePadController.saveSignature(null, PNG_1x1, 'Tester', 'k1', 'Warranty', 'Nope');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'an unknown signer role must fail');

        threw = false;
        try {
            SignaturePadController.stageImage(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'stageImage without an id must fail');

        threw = false;
        try {
            SignaturePadController.issuePdf(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'issuePdf without an id must fail');

        threw = false;
        try {
            SignaturePadController.dropResource(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'dropResource without an id must fail');
    }

    /** One row per role; a re-sign updates that role instead of adding a row. */
    @IsTest
    static void saveSignatureIsIdempotentPerRole() {
        Id appId = newApplication();

        SignatureService.SaveResult cust = SignaturePadController.saveSignature(
            appId, PNG_1x1, 'Customer Person', 'pad-cust-1', 'Warranty', 'Customer');
        SignatureService.SaveResult rep = SignaturePadController.saveSignature(
            appId, PNG_1x1, 'Sales Person', 'pad-rep-1', 'Warranty', 'DealerRep');
        SignatureService.SaveResult holder = SignaturePadController.saveSignature(
            appId, PNG_1x1, 'Customer Person', 'pad-holder-1', 'Warranty', 'ContractHolder');

        System.assertEquals(true, cust.created);
        System.assertEquals(true, rep.created);
        System.assertEquals(true, holder.created);
        System.assertEquals('Customer', cust.signerRole);
        System.assertEquals('DealerRep', rep.signerRole);
        System.assertEquals('ContractHolder', holder.signerRole);
        System.assertEquals(3, [
            SELECT COUNT() FROM Application_Signature__c WHERE Application__c = :appId
        ]);

        // Same gesture replayed -> same row, no duplicate.
        SignatureService.SaveResult replay = SignaturePadController.saveSignature(
            appId, PNG_1x1, 'Customer Person', 'pad-rep-1', 'Warranty', 'DealerRep');
        System.assertEquals(rep.signatureId, replay.signatureId);
        System.assertEquals(false, replay.created);

        // A NEW gesture for the same role -> reuses the row, still three rows.
        SignatureService.SaveResult resigned = SignaturePadController.saveSignature(
            appId, PNG_1x1, 'Sales Person', 'pad-rep-2', 'Warranty', 'DealerRep');
        System.assertEquals(rep.signatureId, resigned.signatureId);
        System.assertEquals(false, resigned.created);
        System.assertEquals('CAPTURED', resigned.status);
        System.assertEquals(3, [
            SELECT COUNT() FROM Application_Signature__c WHERE Application__c = :appId
        ]);
        System.assertEquals('pad-rep-2', [
            SELECT IdemKey__c FROM Application_Signature__c WHERE Id = :rep.signatureId
        ].IdemKey__c);
    }

    /** Signed is reported only when all three roles carry ink. */
    @IsTest
    static void statusRequiresAllThreeRoles() {
        Id appId = newApplication();

        SignaturePadController.saveSignature(appId, PNG_1x1, 'A', 'three-1', 'Warranty', 'Customer');
        SignaturePadController.saveSignature(appId, PNG_1x1, 'B', 'three-2', 'Warranty', 'DealerRep');

        SignatureService.SignatureStatus partial = SignaturePadController.getStatus(appId, 'Warranty');
        System.assertEquals(false, partial.hasSignature, 'two of three is not signed');
        System.assertEquals(false, partial.allRolesCaptured);
        System.assertEquals(3, partial.roles.size());
        System.assertEquals(true, partial.roles[0].captured, 'Customer captured');
        System.assertEquals(true, partial.roles[1].captured, 'DealerRep captured');
        System.assertEquals(false, partial.roles[2].captured, 'ContractHolder still missing');
        System.assertEquals('ContractHolder', partial.roles[2].role);

        SignaturePadController.saveSignature(appId, PNG_1x1, 'A', 'three-3', 'Warranty', 'ContractHolder');

        SignatureService.SignatureStatus full = SignaturePadController.getStatus(appId, 'Warranty');
        System.assertEquals(true, full.hasSignature);
        System.assertEquals(true, full.allRolesCaptured);
        System.assertEquals(3, full.roles.size());
        System.assertEquals(false, full.hasPdf, 'no PDF has been rendered yet');

        // the other document type is untouched
        System.assertEquals(false, SignaturePadController.getStatus(appId, 'TireRim').hasSignature);
    }

    /** The read path the pad and the download chip depend on, as a portal user. */
    @IsTest
    static void completedPdfIsReadableAsIntegrationUser() {
        Id appId = newApplication();

        ContentVersion cv = new ContentVersion(
            Title = 'three-signer contract',
            PathOnClient = 'three-signer.pdf',
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
                IdemKey__c = 'portal-' + i,
                PngB64__c = PNG_1x1,
                PngBytes__c = PNG_1x1.length(),
                Signed_By__c = 'Signer ' + role,
                Signed_At__c = System.now(),
                Status__c = 'DONE',
                Pdf_Document_Id__c = String.valueOf(cv.Id)
            ));
        }
        insert rows;

        List<User> users = [SELECT Id FROM User WHERE Id = '005G100000IGdj0IAD' LIMIT 1];
        SignatureService.SignatureStatus s;
        if (users.isEmpty()) {
            s = SignaturePadController.getStatus(appId, 'Warranty');
        } else {
            System.runAs(users[0]) {
                s = SignaturePadController.getStatus(appId, 'Warranty');
            }
        }

        System.assertNotEquals(null, s);
        System.assertEquals(true, s.hasSignature, 'all three roles captured');
        System.assertEquals(true, s.hasPdf);
        System.assertEquals(String.valueOf(cv.Id), s.pdfDocumentId);
        System.assertEquals(String.valueOf(cv.ContentDocumentId), s.pdfContentDocumentId);
        System.assertEquals('three-signer contract', s.pdfFileName, 'the file name the dealer sees');
        System.assertEquals(3, s.roles.size());
    }

    /**
     * The preview is a same-origin Visualforce PDF URL - never a blob: URL (the
     * Experience Cloud CSP blocks blob: frames) and never a download link. It
     * carries the `docType` parameter - the same one issuePdf sends - so it
     * shows ONE document type.
     */
    @IsTest
    static void previewPointsAtTheSameOriginPdfRoute() {
        Id appId = newApplication();

        String path = SignaturePadController.previewPath(appId, 'Warranty');
        System.assert(path.startsWith('/apex/DealerPortalVehicleApplicationPDFs?id='), path);
        System.assert(path.indexOf(String.valueOf(appId)) > -1, path);
        System.assert(path.endsWith('&docType=Warranty'), path);

        String tire = SignaturePadController.previewPath(appId, 'TireRim');
        System.assert(tire.endsWith('&docType=TireRim'), tire);
        System.assertNotEquals(path, tire, 'each document type previews its own render');

        // the parameter is URL-encoded, so a spaced label cannot break the query
        String spaced = SignaturePadController.previewPath(appId, 'Tire & Rim');
        System.assert(spaced.endsWith('&docType=Tire+%26+Rim'), spaced);

        // no package of that kind on the application -> a message, not a blank PDF
        SignaturePadController.PreviewResult none =
            SignaturePadController.getPreview(appId, 'Warranty');
        System.assertEquals(false, none.ok);
        System.assert(none.message.contains('Extended Warranty'), none.message);

        SignaturePadController.PreviewResult tireMiss =
            SignaturePadController.getPreview(appId, 'Tire & Rim');
        System.assertEquals(false, tireMiss.ok);
        System.assert(tireMiss.message.contains('Tire & Rim'), tireMiss.message);

        SignaturePadController.PreviewResult noApp =
            SignaturePadController.getPreview(null, 'Warranty');
        System.assertEquals(false, noApp.ok);
        System.assertEquals('No application selected.', noApp.message);
    }

    /** The render key is per document type, and null when there is no such package. */
    @IsTest
    static void recordTypeKeyMatchesTheContactPageContract() {
        Id appId = newApplication();
        System.assertEquals(null, SignatureDocument.recordTypeKey(appId, 'Warranty'));
        System.assertEquals(null, SignatureDocument.recordTypeKey(appId, 'TireRim'));
        System.assertEquals(null, SignatureDocument.recordTypeKey(null, 'Warranty'));
    }

    /**
     * Warranty and Tire & Rim are separate documents: signing one must leave the
     * other untouched, and each gets its own three rows.
     */
    @IsTest
    static void documentsAreSignedSeparately() {
        Id appId = newApplication();

        for (String role : SignatureService.ROLES) {
            SignaturePadController.saveSignature(
                appId, PNG_1x1, 'W ' + role, 'sep-w-' + role, 'Warranty', role);
        }

        SignatureService.SignatureStatus w = SignaturePadController.getStatus(appId, 'Warranty');
        SignatureService.SignatureStatus t = SignaturePadController.getStatus(appId, 'TireRim');
        System.assertEquals(true, w.hasSignature, 'warranty carries all three');
        System.assertEquals(false, t.hasSignature, 'tire & rim is untouched by the warranty signing');
        System.assertEquals(3, w.roles.size());
        System.assertEquals(3, t.roles.size());
        System.assertEquals(false, t.roles[0].captured);
        System.assertEquals(3, [
            SELECT COUNT() FROM Application_Signature__c
            WHERE Application__c = :appId AND Document_Type__c = 'Warranty'
        ]);
        System.assertEquals(0, [
            SELECT COUNT() FROM Application_Signature__c
            WHERE Application__c = :appId AND Document_Type__c = 'TireRim'
        ]);

        for (String role : SignatureService.ROLES) {
            SignaturePadController.saveSignature(
                appId, PNG_1x1, 'T ' + role, 'sep-t-' + role, 'TireRim', role);
        }

        w = SignaturePadController.getStatus(appId, 'Warranty');
        t = SignaturePadController.getStatus(appId, 'TireRim');
        System.assertEquals(true, w.hasSignature);
        System.assertEquals(true, t.hasSignature, 'tire & rim is signable on its own');
        System.assertEquals(6, [
            SELECT COUNT() FROM Application_Signature__c WHERE Application__c = :appId
        ]);
        System.assertEquals(3, [
            SELECT COUNT() FROM Application_Signature__c
            WHERE Application__c = :appId AND Document_Type__c = 'TireRim'
        ]);

        // the same role name exists once per document type
        System.assertEquals(2, [
            SELECT COUNT() FROM Application_Signature__c
            WHERE Application__c = :appId AND Signer_Role__c = 'ContractHolder'
        ]);
    }

    /** The produced file is named "<Document label> <YYYY-MM-DD> v<n>". */
    @IsTest
    static void producedFileIsNamedByDocumentDateAndVersion() {
        Date d = Date.newInstance(2026, 10, 22);
        System.assertEquals('Extended Warranty 2026-10-22 v1',
            SignatureDocument.documentFileName('Warranty', d, 1));
        System.assertEquals('Tire & Rim 2026-10-22 v1',
            SignatureDocument.documentFileName('TireRim', d, 1));
        System.assertEquals('Tire & Rim 2026-10-22 v3',
            SignatureDocument.documentFileName('Tire & Rim', d, 3));
        System.assertEquals('Extended Warranty 2026-10-22 v1',
            SignatureDocument.documentFileName('Warranty', d, 0));
        System.assertEquals('Extended Warranty', SignatureDocument.documentLabel(''));
        System.assertEquals('Tire & Rim', SignatureDocument.documentLabel('TireRim'));
        System.assertEquals(false,
            SignatureDocument.documentFileName('Warranty', d, 1).contains('SIG-'),
            'no record name in a user-facing file name');

        // version counts per application + document type
        Id appId = newApplication();
        System.assertEquals(1, SignatureDocument.nextVersionFor(appId, 'Extended Warranty'));
        insert new ContentVersion(
            Title = 'Extended Warranty 2026-10-21 v1',
            PathOnClient = 'prior.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 test'),
            FirstPublishLocationId = appId
        );
        System.assertEquals(2, SignatureDocument.nextVersionFor(appId, 'Extended Warranty'));
        System.assertEquals(1, SignatureDocument.nextVersionFor(appId, 'Tire & Rim'),
            'the other document type keeps its own numbering');
    }
}