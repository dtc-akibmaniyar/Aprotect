/**
 * ClaimCostUpdateControllerTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Coverage target: 99%+
 *
 * Controller is a Visualforce page controller that reads the claim Id from
 * page parameters and updates cost fields on Claim__c via submitClaim().
 *
 * All SObject creation goes through TestDataFactory.
 * ApexPages.currentPage() is set up before each controller instantiation.
 */
@isTest
private class ClaimCostUpdateControllerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // SHARED SETUP HELPER
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Builds the full parent chain and returns an inserted Claim__c.
     *
     *   Dealer Account
     *     └─ Application__c
     *           └─ Repair_Shop__c  (required by Claim validation rule)
     *                 └─ Claim__c  (Warranty_Claim)  ← returned
     */
    private static Claim__c setupClaim() {
        Account        dealer     = TestDataFactory.createDealer(true);
        Application__c app        = TestDataFactory.createApplication(dealer.Id, true);
        Repair_Shop__c repairShop = TestDataFactory.createRepairShop(true);
        return TestDataFactory.createClaim(
            app.Id,
            repairShop.Id,
            'Warranty_Claim',
            true
        );
    }

    /**
     * Wires up a mock Visualforce page with the given Id parameter and
     * returns a fully initialised controller instance.
     *
     * Must be called inside Test.startTest() / Test.stopTest() block or
     * before it — ApexPages.currentPage() must be set before the
     * controller constructor runs.
     */
    private static ClaimCostUpdateController buildController(Id claimId) {
        PageReference page = Page.ClaimCostUpdate; // VF page name
        page.getParameters().put('id', claimId != null ? String.valueOf(claimId) : null);
        Test.setCurrentPage(page);
        return new ClaimCostUpdateController();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 1 — CONSTRUCTOR
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testConstructor_readsClaimIdFromPageParameters() {
        Claim__c claim = setupClaim();

        Test.startTest();
            ClaimCostUpdateController ctrl = buildController(claim.Id);
        Test.stopTest();

        // Controller should have stored the Id without throwing
        // (private field — we verify indirectly via submitClaim behaviour)
        System.assertNotEquals(null, ctrl,
            'Controller should instantiate without error when Id param is present');
    }

    @isTest
    static void testConstructor_nullIdParameterDoesNotThrow() {
        // Page has no 'id' param — getParameters().get('id') returns null
        PageReference page = Page.ClaimCostUpdate;
        Test.setCurrentPage(page);

        Test.startTest();
            ClaimCostUpdateController ctrl = new ClaimCostUpdateController();
        Test.stopTest();

        System.assertNotEquals(null, ctrl,
            'Controller should instantiate without error even when id param is absent');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 2 — submitClaim — SUCCESS PATH
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testSubmitClaim_updatesAllCostFieldsAndRedirects() {
        Claim__c claim = setupClaim();

        ClaimCostUpdateController ctrl = buildController(claim.Id);
        ctrl.estimatedRepairCost = 1200.00;
        ctrl.laborCost           = 300.00;
        ctrl.shopSupplies        = 75.00;
        ctrl.wholesalePrice      = 950.00;

        Test.startTest();
            PageReference result = ctrl.submitClaim();
        Test.stopTest();

        // Should return a redirect PageReference, not null
        System.assertNotEquals(null, result,
            'submitClaim should return a PageReference on success');
        System.assert(result.getRedirect(),
            'Returned PageReference should have redirect set to true');
        System.assert(
            result.getUrl().contains('a-protectwarranty.com'),
            'Redirect URL should point to a-protectwarranty.com'
        );

        // Verify all four fields were persisted
        Claim__c updated = [
            SELECT Estimated_Repair_Cost__c, Labor_Cost__c,
                   Shop_Supplies__c, Wholesale_Price__c
            FROM   Claim__c
            WHERE  Id = :claim.Id
        ];
        System.assertEquals(1200.00, updated.Estimated_Repair_Cost__c,
            'Estimated repair cost should be persisted');
        System.assertEquals(300.00,  updated.Labor_Cost__c,
            'Labor cost should be persisted');
        System.assertEquals(75.00,   updated.Shop_Supplies__c,
            'Shop supplies should be persisted');
        System.assertEquals(950.00,  updated.Wholesale_Price__c,
            'Wholesale price should be persisted');
    }

    @isTest
    static void testSubmitClaim_zeroValuesUpdateSuccessfully() {
        Claim__c claim = setupClaim();

        ClaimCostUpdateController ctrl = buildController(claim.Id);
        ctrl.estimatedRepairCost = 0;
        ctrl.laborCost           = 0;
        ctrl.shopSupplies        = 0;
        ctrl.wholesalePrice      = 0;

        Test.startTest();
            PageReference result = ctrl.submitClaim();
        Test.stopTest();

        System.assertNotEquals(null, result,
            'Zero cost values should still produce a successful redirect');

        Claim__c updated = [
            SELECT Estimated_Repair_Cost__c, Labor_Cost__c,
                   Shop_Supplies__c, Wholesale_Price__c
            FROM   Claim__c
            WHERE  Id = :claim.Id
        ];
        System.assertEquals(0, updated.Estimated_Repair_Cost__c,
            'Estimated repair cost should be saved as 0');
        System.assertEquals(0, updated.Labor_Cost__c,
            'Labor cost should be saved as 0');
        System.assertEquals(0, updated.Shop_Supplies__c,
            'Shop supplies should be saved as 0');
        System.assertEquals(0, updated.Wholesale_Price__c,
            'Wholesale price should be saved as 0');
    }

    @isTest
    static void testSubmitClaim_largeDecimalValuesUpdateSuccessfully() {
        Claim__c claim = setupClaim();

        ClaimCostUpdateController ctrl = buildController(claim.Id);
        ctrl.estimatedRepairCost = 99999.99;
        ctrl.laborCost           = 88888.88;
        ctrl.shopSupplies        = 7777.77;
        ctrl.wholesalePrice      = 66666.66;

        Test.startTest();
            PageReference result = ctrl.submitClaim();
        Test.stopTest();

        System.assertNotEquals(null, result,
            'Large decimal values should still redirect on success');

        Claim__c updated = [
            SELECT Estimated_Repair_Cost__c, Labor_Cost__c,
                   Shop_Supplies__c, Wholesale_Price__c
            FROM   Claim__c
            WHERE  Id = :claim.Id
        ];
        System.assertEquals(99999.99, updated.Estimated_Repair_Cost__c,
            'Large estimated repair cost should be persisted correctly');
        System.assertEquals(88888.88, updated.Labor_Cost__c,
            'Large labor cost should be persisted correctly');
    }

    @isTest
    static void testSubmitClaim_partialFieldsUpdateSuccessfully() {
        Claim__c claim = setupClaim();

        // Only set two of the four fields — others remain null
        ClaimCostUpdateController ctrl = buildController(claim.Id);
        ctrl.estimatedRepairCost = 500.00;
        ctrl.wholesalePrice      = 400.00;
        // laborCost and shopSupplies intentionally left null

        Test.startTest();
            PageReference result = ctrl.submitClaim();
        Test.stopTest();

        System.assertNotEquals(null, result,
            'Partial field population should still redirect on success');

        Claim__c updated = [
            SELECT Estimated_Repair_Cost__c, Wholesale_Price__c,
                   Labor_Cost__c, Shop_Supplies__c
            FROM   Claim__c
            WHERE  Id = :claim.Id
        ];
        System.assertEquals(500.00, updated.Estimated_Repair_Cost__c,
            'Estimated repair cost should be persisted');
        System.assertEquals(400.00, updated.Wholesale_Price__c,
            'Wholesale price should be persisted');
        System.assertEquals(null, updated.Labor_Cost__c,
            'Unpopulated labor cost should remain null');
        System.assertEquals(null, updated.Shop_Supplies__c,
            'Unpopulated shop supplies should remain null');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 3 — submitClaim — ERROR / CATCH PATH
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testSubmitClaim_invalidIdReturnsNullAndAddsPageMessage() {
        // Pass a well-formed but non-existent Claim Id to force a DML exception
        // (record not found → update fails)
        PageReference page = Page.ClaimCostUpdate;
        page.getParameters().put('id', 'a0000000000000ZAAQ'); // fake Id
        Test.setCurrentPage(page);
        ClaimCostUpdateController ctrl = new ClaimCostUpdateController();

        ctrl.estimatedRepairCost = 100.00;
        ctrl.laborCost           = 50.00;
        ctrl.shopSupplies        = 10.00;
        ctrl.wholesalePrice      = 80.00;

        Test.startTest();
            PageReference result = ctrl.submitClaim();
        Test.stopTest();

        // Error path must return null
        System.assertEquals(null, result,
            'submitClaim should return null when an exception occurs');

        // Error path must add exactly one ERROR page message
        List<ApexPages.Message> messages = ApexPages.getMessages();
        System.assertEquals(1, messages.size(),
            'Exactly one page message should be added on error');
        System.assertEquals(ApexPages.Severity.ERROR, messages[0].getSeverity(),
            'Page message severity should be ERROR');
        System.assert(
            messages[0].getDetail().contains('Error submitting claim:'),
            'Page message detail should contain the error prefix'
        );
    }

    @isTest
    static void testSubmitClaim_nullIdReturnsNullAndAddsPageMessage() {
        // No 'id' param at all — claimId is null — update throws
        PageReference page = Page.ClaimCostUpdate;
        Test.setCurrentPage(page);
        ClaimCostUpdateController ctrl = new ClaimCostUpdateController();

        ctrl.estimatedRepairCost = 200.00;
        ctrl.laborCost           = 100.00;
        ctrl.shopSupplies        = 20.00;
        ctrl.wholesalePrice      = 150.00;

        Test.startTest();
            PageReference result = ctrl.submitClaim();
        Test.stopTest();

        System.assertEquals(null, result,
            'Null claimId should cause exception and return null');

        List<ApexPages.Message> messages = ApexPages.getMessages();
        System.assertEquals(1, messages.size(),
            'Exactly one page message should be added when claimId is null');
        System.assertEquals(ApexPages.Severity.ERROR, messages[0].getSeverity(),
            'Page message severity should be ERROR');
    }

    @isTest
    static void testSubmitClaim_emptyStringIdReturnsNullAndAddsPageMessage() {
        // Empty string Id — Salesforce will throw a StringException on Id cast
        PageReference page = Page.ClaimCostUpdate;
        page.getParameters().put('id', '');
        Test.setCurrentPage(page);
        ClaimCostUpdateController ctrl = new ClaimCostUpdateController();

        ctrl.estimatedRepairCost = 100.00;
        ctrl.laborCost           = 50.00;

        Test.startTest();
            PageReference result = ctrl.submitClaim();
        Test.stopTest();

        System.assertEquals(null, result,
            'Empty string Id should cause exception and return null');

        List<ApexPages.Message> messages = ApexPages.getMessages();
        System.assert(messages.size() >= 1,
            'At least one page message should be added for empty Id');
        System.assertEquals(ApexPages.Severity.ERROR, messages[0].getSeverity(),
            'Page message severity should be ERROR');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 4 — PROPERTY GETTERS / SETTERS
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testProperties_getAndSetCorrectly() {
        Claim__c claim = setupClaim();
        ClaimCostUpdateController ctrl = buildController(claim.Id);

        Test.startTest();
            ctrl.estimatedRepairCost = 111.11;
            ctrl.laborCost           = 222.22;
            ctrl.shopSupplies        = 333.33;
            ctrl.wholesalePrice      = 444.44;
        Test.stopTest();

        System.assertEquals(111.11, ctrl.estimatedRepairCost,
            'estimatedRepairCost getter should return the set value');
        System.assertEquals(222.22, ctrl.laborCost,
            'laborCost getter should return the set value');
        System.assertEquals(333.33, ctrl.shopSupplies,
            'shopSupplies getter should return the set value');
        System.assertEquals(444.44, ctrl.wholesalePrice,
            'wholesalePrice getter should return the set value');
    }
}