@isTest
private class SignatureBlockControllerTest {

    private static Id newApplication() {
        Application__c app = new Application__c(
            Commercial_Business_Use__c = false,
            Show_Comments_On_Print__c = false,
            Is_Vehicle_Financed__c = false
        );
        insert app;
        return app.Id;
    }

    private static void addSignature(Id appId, String docType, String role, String resourceName) {
        insert new Application_Signature__c(
            Application__c = appId,
            Document_Type__c = docType,
            Signer_Role__c = role,
            IdemKey__c = 'BLK_' + String.valueOf(Datetime.now().getTime()) + '_' + role + docType,
            PngBytes__c = 96,
            Status__c = 'CAPTURED',
            ResourceName__c = resourceName,
            Signed_At__c = System.now()
        );
    }

    @isTest
    static void failsClosedWithoutUsableAppId() {
        SignatureBlockController blank = new SignatureBlockController();
        System.assertEquals(false, blank.getHasSignature());
        System.assertEquals(null, blank.getResourceName());
        System.assertEquals(false, blank.getHasSignedOn());

        SignatureBlockController junk = new SignatureBlockController();
        junk.applicationId = 'not-an-id';
        junk.signatureDocType = 'Warranty';
        System.assertEquals(false, junk.getHasSignature());
        System.assertEquals(null, junk.getResourceName());

        SignatureBlockController unknownRole = new SignatureBlockController();
        unknownRole.applicationId = String.valueOf(newApplication());
        unknownRole.signatureDocType = 'Warranty';
        unknownRole.signatureRole = 'NotARole';
        System.assertEquals(false, unknownRole.getHasSignature());
    }

    /** Each signature line resolves its OWN role, never the newest row. */
    @isTest
    static void resolvesOneRolePerSignatureLine() {
        Id appId = newApplication();
        addSignature(appId, 'Warranty', 'Customer', 'SIGTMP_blk_customer');
        addSignature(appId, 'Warranty', 'DealerRep', 'SIGTMP_blk_rep');
        addSignature(appId, 'Warranty', 'ContractHolder', 'SIGTMP_blk_holder');

        SignatureBlockController customer = new SignatureBlockController();
        customer.applicationId = String.valueOf(appId);
        customer.signatureDocType = 'Warranty';
        customer.signatureRole = 'Customer';
        System.assertEquals(true, customer.getHasSignature());
        System.assertEquals('SIGTMP_blk_customer', customer.getResourceName());
        System.assertNotEquals(null, customer.getSignedOnDisplay());
        System.assertEquals(true, customer.getHasSignedOn());
        System.assertEquals('90', customer.getImageWidth());

        SignatureBlockController rep = new SignatureBlockController();
        rep.applicationId = String.valueOf(appId);
        rep.signatureDocType = 'Warranty';
        rep.signatureRole = 'DealerRep';
        System.assertEquals(true, rep.getHasSignature());
        System.assertEquals('SIGTMP_blk_rep', rep.getResourceName());
        System.assertEquals('72', rep.getImageWidth());

        SignatureBlockController holder = new SignatureBlockController();
        holder.applicationId = String.valueOf(appId);
        holder.signatureDocType = 'Warranty';
        holder.signatureRole = 'ContractHolder';
        System.assertEquals(true, holder.getHasSignature());
        System.assertEquals('SIGTMP_blk_holder', holder.getResourceName());
        System.assertEquals('120', holder.getImageWidth());

        // a role that has not signed renders nothing at all
        SignatureBlockController tire = new SignatureBlockController();
        tire.applicationId = String.valueOf(appId);
        tire.signatureDocType = 'Tire & Rim';
        tire.signatureRole = 'DealerRep';
        System.assertEquals(false, tire.getHasSignature());
        System.assertEquals(null, tire.getResourceName());

        // an unrelated application -> nothing to show
        SignatureBlockController other = new SignatureBlockController();
        other.applicationId = String.valueOf(appId).substring(0, 15) + 'AAA';
        other.signatureDocType = 'Warranty';
        other.signatureRole = 'Customer';
        System.assertEquals(false, other.getHasSignature());
    }

    /** Legacy rows with a blank role still print on the customer line. */
    @isTest
    static void blankRoleIsTreatedAsCustomer() {        Id appId = newApplication();
        insert new Application_Signature__c(
            Application__c = appId,
            Document_Type__c = 'Warranty',
            IdemKey__c = 'LEGACY_1',
            PngBytes__c = 96,
            Status__c = 'RENDERED',
            ResourceName__c = 'SIGTMP_legacy_row',
            Signed_At__c = System.now()
        );

        SignatureBlockController customer = new SignatureBlockController();
        customer.applicationId = String.valueOf(appId);
        customer.signatureDocType = 'Warranty';
        customer.signatureRole = 'Customer';
        System.assertEquals(true, customer.getHasSignature());
        System.assertEquals('SIGTMP_legacy_row', customer.getResourceName());

        // ... but must never leak onto the dealership rep line
        SignatureBlockController rep = new SignatureBlockController();
        rep.applicationId = String.valueOf(appId);
        rep.signatureDocType = 'Warranty';
        rep.signatureRole = 'DealerRep';
        System.assertEquals(false, rep.getHasSignature());

        // a DONE row (image already dropped) renders nothing
        update new Application_Signature__c(
            Id = [SELECT Id FROM Application_Signature__c WHERE IdemKey__c = 'LEGACY_1'].Id,
            Status__c = 'DONE'
        );
        SignatureBlockController done = new SignatureBlockController();
        done.applicationId = String.valueOf(appId);
        done.signatureDocType = 'Warranty';
        done.signatureRole = 'Customer';
        System.assertEquals(false, done.getHasSignature());
    }

    /**
     * The acknowledgement page re-uses the customer block in the Contract Holder
     * cell and pins its footprint with widthPx / heightPx.
     */
    @isTest
    static void customerBlockHonoursTheExplicitSizeOverride() {
        Id appId = newApplication();
        addSignature(appId, 'Warranty', 'Customer', 'SIGTMP_blk_override');
        addSignature(appId, 'Warranty', 'DealerRep', 'SIGTMP_blk_override_rep');

        SignatureBlockController customer = new SignatureBlockController();
        customer.applicationId = String.valueOf(appId);
        customer.signatureDocType = 'Warranty';
        customer.signatureRole = 'Customer';
        customer.imageWidthPx = '120';
        customer.imageHeightPx = '40';

        System.assertEquals(true, customer.getHasSignature());
        System.assertEquals('SIGTMP_blk_override', customer.getResourceName(),
            'the Contract Holder cell carries the CUSTOMER stroke');
        System.assertEquals('120', customer.getImageWidth());
        System.assertEquals('40', customer.getImageHeight());
    }

    /** An unusable override fails closed to the per-role default, never to 0. */
    @isTest
    static void invalidSizeOverrideFallsBackToTheRoleDefault() {
        Id appId = newApplication();
        addSignature(appId, 'Warranty', 'Customer', 'SIGTMP_blk_fallback');

        for (String bad : new List<String>{ 'abc', '0', '19', '201', '120px', '-5', ' ' }) {
            SignatureBlockController c = new SignatureBlockController();
            c.applicationId = String.valueOf(appId);
            c.signatureDocType = 'Warranty';
            c.signatureRole = 'Customer';
            c.imageWidthPx = bad;
            c.imageHeightPx = bad;
            System.assertEquals('90', c.getImageWidth(), 'width default kept for: ' + bad);
            System.assertEquals('30', c.getImageHeight(), 'height default kept for: ' + bad);
        }

        // a valid height may be overridden on its own while the width defaults
        SignatureBlockController mixed = new SignatureBlockController();
        mixed.applicationId = String.valueOf(appId);
        mixed.signatureDocType = 'Warranty';
        mixed.signatureRole = 'Customer';
        mixed.imageHeightPx = '40';
        System.assertEquals('90', mixed.getImageWidth());
        System.assertEquals('40', mixed.getImageHeight());
    }
}