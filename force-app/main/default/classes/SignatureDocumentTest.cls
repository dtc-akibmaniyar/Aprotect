@IsTest
private class SignatureDocumentTest {

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
    static void documentTypeIsNormalised() {
        System.assertEquals('Warranty', SignatureDocument.normaliseDocumentType(null));
        System.assertEquals('Warranty', SignatureDocument.normaliseDocumentType('  '));
        System.assertEquals('Warranty', SignatureDocument.normaliseDocumentType('Warranty'));
        System.assertEquals('Warranty', SignatureDocument.normaliseDocumentType('warranty'));
        System.assertEquals('TireRim', SignatureDocument.normaliseDocumentType('TireRim'));
        System.assertEquals('TireRim', SignatureDocument.normaliseDocumentType('Tire & Rim'));
        System.assertEquals('TireRim', SignatureDocument.normaliseDocumentType('Tire and Rim'));
        System.assertEquals('TireRim', SignatureDocument.normaliseDocumentType('tire and rim'));

        Boolean threw = false;
        try {
            SignatureDocument.normaliseDocumentType('Boat');
        } catch (SignatureDocument.SignatureDocumentException e) {
            threw = true;
            System.assert(e.getMessage().contains('unsupported documentType'), e.getMessage());
        }
        System.assertEquals(true, threw, 'an unknown document type must be refused');
    }

    @IsTest
    static void labelsAreUserFacingNotRecordNames() {
        System.assertEquals('Extended Warranty', SignatureDocument.documentLabel('Warranty'));
        System.assertEquals('Extended Warranty', SignatureDocument.documentLabel(''));
        System.assertEquals('Tire & Rim', SignatureDocument.documentLabel('TireRim'));
        System.assertEquals('Tire & Rim', SignatureDocument.documentLabel('Tire & Rim'));
        System.assert(!SignatureDocument.documentLabel('Warranty').contains('SIG-'),
            'never a record name');
    }

    @IsTest
    static void fileNamesCarryLabelDateAndVersion() {
        Date d = Date.newInstance(2026, 10, 22);
        System.assertEquals('Extended Warranty 2026-10-22 v1',
            SignatureDocument.documentFileName('Warranty', d, 1));
        System.assertEquals('Tire & Rim 2026-10-22 v1',
            SignatureDocument.documentFileName('TireRim', d, 1));
        System.assertEquals('Tire & Rim 2026-10-22 v3',
            SignatureDocument.documentFileName('Tire & Rim', d, 3));
        // a null / zero version is v1, a null date is today
        System.assertEquals('Extended Warranty 2026-10-22 v1',
            SignatureDocument.documentFileName('Warranty', d, 0));
        System.assertEquals('Extended Warranty 2026-10-22 v1',
            SignatureDocument.documentFileName('Warranty', d, null));
        System.assertEquals('Extended Warranty ' + String.valueOf(Date.today()) + ' v1',
            SignatureDocument.documentFileName('Warranty', null, null));
    }

    @IsTest
    static void versionCountsPerApplicationAndDocumentType() {
        System.assertEquals(1, SignatureDocument.nextVersionFor(null, 'Extended Warranty'));
        Id appId = newApplication();
        System.assertEquals(1, SignatureDocument.nextVersionFor(appId, null));

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

    @IsTest
    static void renderKeyMatchesTheContractPageContract() {
        System.assertEquals(null, SignatureDocument.recordTypeKey(null, 'Warranty'));

        Id appId = newApplication();
        System.assertEquals(null, SignatureDocument.recordTypeKey(appId, 'Warranty'),
            'an application without packages has no document to render');
        System.assertEquals(null, SignatureDocument.recordTypeKey(appId, 'TireRim'));
    }
}