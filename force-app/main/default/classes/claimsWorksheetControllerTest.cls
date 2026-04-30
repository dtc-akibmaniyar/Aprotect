@isTest
private class claimsWorksheetControllerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // SHARED SETUP HELPER
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Builds the full parent chain required before any Part__c or Service__c
     * can be created:
     *
     *   Dealer Account
     *     └─ Application__c
     *           └─ Repair_Shop__c  (required by Claim validation)
     *           └─ Claim__c  (Warranty_Claim)
     *                 └─ Estimate__c   ← returned
     *
     * All records are inserted.
     */
    private static Estimate__c setupEstimate() {
        Account        dealer     = TestDataFactory.createDealer(true);
        Application__c app        = TestDataFactory.createApplication(dealer.Id, true);
        Repair_Shop__c repairShop = TestDataFactory.createRepairShop(true);
        Claim__c       claim      = TestDataFactory.createClaim(
                                        app.Id,
                                        repairShop.Id,
                                        'Warranty_Claim',
                                        true
                                    );
        return TestDataFactory.createEstimate(claim.Id, repairShop.Id, true);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 1 — getPartsForEstimate
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * NOTE: getPartsForEstimate() and getLabourForEstimate() both filter on
     * WHERE Estimate__r.Name = 'E-0033'. Because Name is an auto-number field
     * it cannot be controlled in test context, so these methods will always
     * return empty lists here. Tests assert no exception is thrown only.
     *
     * Recommended fix: refactor controller to accept an estimateId parameter.
     */
    @isTest
    static void testGetPartsForEstimate_returnsWithoutException() {
        Estimate__c est = setupEstimate();
        TestDataFactory.createPart(est.Id, true);

        Test.startTest();
            List<Part__c> result = claimsWorksheetController.getPartsForEstimate();
        Test.stopTest();

        System.assertNotEquals(null, result,
            'getPartsForEstimate should never return null');
    }

    @isTest
    static void testGetPartsForEstimate_noPartsReturnsEmptyList() {
        Test.startTest();
            List<Part__c> result = claimsWorksheetController.getPartsForEstimate();
        Test.stopTest();

        System.assertNotEquals(null, result,
            'Should return an empty list, not null');
        System.assertEquals(0, result.size(),
            'Expected 0 parts — auto-number Name cannot match E-0033 in test context');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 2 — getLabourForEstimate
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetLabourForEstimate_returnsWithoutException() {
        Estimate__c est = setupEstimate();
        TestDataFactory.createService(est.Id, true);

        Test.startTest();
            List<Service__c> result = claimsWorksheetController.getLabourForEstimate();
        Test.stopTest();

        System.assertNotEquals(null, result,
            'getLabourForEstimate should never return null');
    }

    @isTest
    static void testGetLabourForEstimate_noServicesReturnsEmptyList() {
        Test.startTest();
            List<Service__c> result = claimsWorksheetController.getLabourForEstimate();
        Test.stopTest();

        System.assertNotEquals(null, result,
            'Should return an empty list, not null');
        System.assertEquals(0, result.size(),
            'Expected 0 services — auto-number Name cannot match E-0033 in test context');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 3 — updateParts
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testUpdateParts_singlePartUpdatesSuccessfully() {
        Estimate__c est = setupEstimate();
        Part__c p       = TestDataFactory.createPart(est.Id, true);

        p.Part_Name__c     = 'Updated Rotor';
        p.Part_Cost__c     = 200.00;
        p.Quantity__c      = 4;
        p.Retail_Markup__c = '20%';

        Test.startTest();
            String result = claimsWorksheetController.updateParts(
                new List<Part__c>{ p }
            );
        Test.stopTest();

        System.assertEquals('Success', result,
            'updateParts should return Success');

        Part__c updated = [
            SELECT Part_Name__c, Part_Cost__c, Quantity__c, Retail_Markup__c
            FROM   Part__c
            WHERE  Id = :p.Id
        ];
        System.assertEquals('Updated Rotor', updated.Part_Name__c,
            'Part name should be updated');
        System.assertEquals(200.00,          updated.Part_Cost__c,
            'Part cost should be updated');
        System.assertEquals(4,               updated.Quantity__c,
            'Quantity should be updated');
        System.assertEquals('20%',           updated.Retail_Markup__c,
            'Retail markup should be updated');
    }

    @isTest
    static void testUpdateParts_bulkUpdate200Parts() {
        Estimate__c   est   = setupEstimate();
        List<Part__c> parts = TestDataFactory.createBulkParts(est.Id, 200, true);

        for (Part__c p : parts) {
            p.Part_Cost__c = 75.00;
        }

        Test.startTest();
            String result = claimsWorksheetController.updateParts(parts);
        Test.stopTest();

        System.assertEquals('Success', result,
            'Bulk updateParts should return Success');

        List<Part__c> refreshed = [
            SELECT Part_Cost__c FROM Part__c WHERE Estimate__c = :est.Id
        ];
        System.assertEquals(200, refreshed.size(),
            'All 200 parts should be present');
        for (Part__c p : refreshed) {
            System.assertEquals(75.00, p.Part_Cost__c,
                'Every part should have the updated cost');
        }
    }

    @isTest
    static void testUpdateParts_emptyListReturnsSuccess() {
        Test.startTest();
            String result = claimsWorksheetController.updateParts(
                new List<Part__c>()
            );
        Test.stopTest();

        System.assertEquals('Success', result,
            'Empty list should still return Success');
    }

    @isTest
    static void testUpdateParts_nullListThrowsAuraHandledException() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            claimsWorksheetController.updateParts(null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown,
            'Null parts list should throw AuraHandledException');
    }

    @isTest
    static void testUpdateParts_missingIdThrowsAuraHandledException() {
        Estimate__c est = setupEstimate();
        Part__c phantom = TestDataFactory.createPart(est.Id, false);

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            claimsWorksheetController.updateParts(new List<Part__c>{ phantom });
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown,
            'Part with no Id should throw AuraHandledException');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 4 — updateServices
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testUpdateServices_singleServiceUpdatesSuccessfully() {
        Estimate__c est = setupEstimate();
        Service__c s    = TestDataFactory.createService(est.Id, true);

        s.Time__c                      = '2.5';
        s.Wholesale_Labour_Rate_HR__c  = 90.00;
        s.Retail_Markup__c             = '20%';
        s.Shop_Supplies__c             = 30.00;
        s.Shop_Supplies_Description__c = 'Updated supplies';
        s.Shop_Supplies_Markup__c      = 12.00;

        Test.startTest();
            String result = claimsWorksheetController.updateServices(
                new List<Service__c>{ s }
            );
        Test.stopTest();

        System.assertEquals('Success', result,
            'updateServices should return Success');

        Service__c updated = [
            SELECT Time__c, Wholesale_Labour_Rate_HR__c, Retail_Markup__c,
                   Shop_Supplies__c, Shop_Supplies_Description__c,
                   Shop_Supplies_Markup__c
            FROM   Service__c
            WHERE  Id = :s.Id
        ];
        System.assertEquals('2.5',             updated.Time__c,
            'Time should be updated');
        System.assertEquals(90.00,             updated.Wholesale_Labour_Rate_HR__c,
            'Labour rate should be updated');
        System.assertEquals('20%',             updated.Retail_Markup__c,
            'Retail markup should be updated');
        System.assertEquals(30.00,             updated.Shop_Supplies__c,
            'Shop supplies amount should be updated');
        System.assertEquals('Updated supplies',updated.Shop_Supplies_Description__c,
            'Description should be updated');
        System.assertEquals(12.00,             updated.Shop_Supplies_Markup__c,
            'Shop supplies markup should be updated');
    }

    @isTest
    static void testUpdateServices_emptyListReturnsSuccess() {
        Test.startTest();
            String result = claimsWorksheetController.updateServices(
                new List<Service__c>()
            );
        Test.stopTest();

        System.assertEquals('Success', result,
            'Empty list should return Success');
    }

    @isTest
    static void testUpdateServices_nullListThrowsAuraHandledException() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            claimsWorksheetController.updateServices(null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown,
            'Null services list should throw AuraHandledException');
    }

    @isTest
    static void testUpdateServices_missingIdThrowsAuraHandledException() {
        Estimate__c    est     = setupEstimate();
        Service__c phantom    = TestDataFactory.createService(est.Id, false);

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            claimsWorksheetController.updateServices(
                new List<Service__c>{ phantom }
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown,
            'Service with no Id should throw AuraHandledException');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 5 — saveAllRecords
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testSaveAllRecords_bothListsUpdatedSuccessfully() {
        Estimate__c est = setupEstimate();
        Part__c p       = TestDataFactory.createPart(est.Id, true);
        Service__c s    = TestDataFactory.createService(est.Id, true);

        p.Part_Cost__c = 250.00;
        s.Time__c      = '3.0';

        Test.startTest();
            String result = claimsWorksheetController.saveAllRecords(
                new List<Part__c>{ p },
                new List<Service__c>{ s }
            );
        Test.stopTest();

        System.assertEquals('All records updated successfully', result,
            'saveAllRecords should return full success message');

        Part__c    updatedPart    = [SELECT Part_Cost__c FROM Part__c    WHERE Id = :p.Id];
        Service__c updatedService = [SELECT Time__c      FROM Service__c WHERE Id = :s.Id];

        System.assertEquals(250.00, updatedPart.Part_Cost__c,
            'Part cost should be updated via saveAllRecords');
        System.assertEquals('3.0',  updatedService.Time__c,
            'Service time should be updated via saveAllRecords');
    }

    @isTest
    static void testSaveAllRecords_onlyPartsNullServices() {
        Estimate__c est = setupEstimate();
        Part__c p       = TestDataFactory.createPart(est.Id, true);
        p.Part_Cost__c  = 99.00;

        Test.startTest();
            String result = claimsWorksheetController.saveAllRecords(
                new List<Part__c>{ p },
                null
            );
        Test.stopTest();

        System.assertEquals('All records updated successfully', result,
            'Null services should be handled gracefully');

        Part__c updated = [SELECT Part_Cost__c FROM Part__c WHERE Id = :p.Id];
        System.assertEquals(99.00, updated.Part_Cost__c,
            'Part should still be updated when services is null');
    }

    @isTest
    static void testSaveAllRecords_onlyServicesNullParts() {
        Estimate__c est = setupEstimate();
        Service__c s    = TestDataFactory.createService(est.Id, true);
        s.Time__c       = '4.0';

        Test.startTest();
            String result = claimsWorksheetController.saveAllRecords(
                null,
                new List<Service__c>{ s }
            );
        Test.stopTest();

        System.assertEquals('All records updated successfully', result,
            'Null parts should be handled gracefully');

        Service__c updated = [SELECT Time__c FROM Service__c WHERE Id = :s.Id];
        System.assertEquals('4.0', updated.Time__c,
            'Service should still be updated when parts is null');
    }

    @isTest
    static void testSaveAllRecords_bothNullReturnsSuccess() {
        Test.startTest();
            String result = claimsWorksheetController.saveAllRecords(null, null);
        Test.stopTest();

        System.assertEquals('All records updated successfully', result,
            'Both null — no DML — should still return success');
    }

    @isTest
    static void testSaveAllRecords_rollsBackOnServiceError() {
        Estimate__c est   = setupEstimate();
        Part__c validPart = TestDataFactory.createPart(est.Id, true);
        validPart.Part_Cost__c = 300.00;

        // doInsert=false → no Id → DML error on services → triggers rollback
        Service__c badService = TestDataFactory.createService(est.Id, false);

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            claimsWorksheetController.saveAllRecords(
                new List<Part__c>{ validPart },
                new List<Service__c>{ badService }
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown,
            'Invalid service should trigger rollback and AuraHandledException');

        Part__c rolledBack = [SELECT Part_Cost__c FROM Part__c WHERE Id = :validPart.Id];
        System.assertNotEquals(300.00, rolledBack.Part_Cost__c,
            'Savepoint rollback should have reverted the part update');
    }
}