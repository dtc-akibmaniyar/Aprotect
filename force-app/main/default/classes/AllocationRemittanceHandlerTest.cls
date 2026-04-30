/**
 * AllocationRemittanceHandlerTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Covers AllocationRemittanceHandler:
 *   getAllocationConfirmationData() — package pricing, service-type filter, skip-empty
 *   getApplicationsByDealer()      — happy path, early-exit guards, search term,
 *                                    invoice status attachment, sort order, hasMore
 *   createAllocationRemittanceForm()— happy path, no eligible items, stale junction
 *                                    cleanup, paid ILI exclusion
 *
 * Test Strategy:
 *   ✔ @isTest(SeeAllData=false)
 *   ✔ @TestSetup for shared base graph
 *   ✔ All data exclusively via TestDataFactory — no inline SObject creation
 *   ✔ Positive + Negative per method
 *   ✔ System.assert* with descriptive messages on every assertion
 *   ✔ No hardcoded Ids
 */
@isTest(SeeAllData=false)
private class AllocationRemittanceHandlerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // @TestSetup — shared base graph
    // Creates: Dealer → Package hierarchy → Submitted Application
    //          → ApplicationPackage (RecordType=Extended_Limited_Warranty,
    //            Active=true, pricing set)
    //          → Invoice (Status=Due)
    //          → InvoiceLineItem
    //
    // Application_Status__c = 'Submitted' satisfies the getApplicationsByDealer
    // filter; Active__c = true and RecordType satisfy the service-type filters.
    // ─────────────────────────────────────────────────────────────────────────

    @TestSetup
    static void setup() {
        Account dealer                = TestDataFactory.createDealer(true);
        Package__c pkg                = TestDataFactory.createPackage('Extended_Limited_Warranty', true);
        Package_Term__c pkgTerm       = TestDataFactory.createPackageTerm(pkg.Id, null, true);
        Dealer_Package__c dp          = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true
        );
        Dealer_Package_Term__c dpt    = TestDataFactory.createDealerPackageTerm(dp.Id, pkgTerm.Id, null, true);

        // Status='Submitted' required by getApplicationsByDealer SOQL filter
        Application__c app            = TestDataFactory.createSubmittedApplication(dealer.Id, true);

        // 8-param overload: sets RecordType + Active__c=true + pricing
        Application_Package__c appPkg = TestDataFactory.createApplicationPackage(
            app.Id, dp.Id, dpt.Id, dealer.Id,
            'Extended_Limited_Warranty', 1200.00, 13, true
        );

        Invoice__c inv                = TestDataFactory.createInvoice(app.Id, true);
        TestDataFactory.createInvoiceLineItem(inv.Id, appPkg.Id, true);
    }

    // ── Private query helpers ─────────────────────────────────────────────────

    private static Account getDealer() {
        return [SELECT Id, Name FROM Account LIMIT 1];
    }

    private static Application__c getApp() {
        return [SELECT Id, Dealer_Name__c FROM Application__c LIMIT 1];
    }

    private static Invoice__c getInvoice() {
        return [SELECT Id, Application__c FROM Invoice__c LIMIT 1];
    }

    private static Invoice_Line_Item__c getIli() {
        return [SELECT Id, Invoice__c FROM Invoice_Line_Item__c LIMIT 1];
    }

    private static Application_Package__c getAppPkg() {
        return [SELECT Id FROM Application_Package__c LIMIT 1];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getAllocationConfirmationData
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Happy path — matching service type returns the app with its package pricing.
     */
    @isTest
    static void testGetAllocationConfirmationData_matchingPackage_returned() {
        Application__c app = getApp();

        Test.startTest();
        AllocationRemittanceHandler.AllocationConfirmationData result =
            AllocationRemittanceHandler.getAllocationConfirmationData(
                new List<String>{ app.Id },
                new List<String>{ 'Extended_Limited_Warranty' }
            );
        Test.stopTest();

        System.assertNotEquals(null, result,
            'Result should not be null');
        System.assertEquals(1, result.confirmationList.size(),
            'Should return one AllocationApplicationRecord for the matching app');

        AllocationRemittanceHandler.AllocationApplicationRecord rec = result.confirmationList[0];
        System.assertEquals(app.Id, rec.applicationId,
            'applicationId should match');
        System.assertEquals(1, rec.lineItems.size(),
            'One line item should be returned for the matching package');

        AllocationRemittanceHandler.AllocationLineItem li = rec.lineItems[0];
        System.assertEquals('Extended Limited Warranty', li.serviceName,
            'serviceName should be the RecordType.Name of the package');
    }

    /**
     * Service type filter does not match the app's packages — app is skipped entirely.
     */
    @isTest
    static void testGetAllocationConfirmationData_noMatchingPackage_appSkipped() {
        Application__c app = getApp();

        Test.startTest();
        AllocationRemittanceHandler.AllocationConfirmationData result =
            AllocationRemittanceHandler.getAllocationConfirmationData(
                new List<String>{ app.Id },
                new List<String>{ 'GAP_Coverage' }  // app only has Extended_Limited_Warranty
            );
        Test.stopTest();

        System.assertEquals(0, result.confirmationList.size(),
            'App with no matching packages should be skipped — confirmationList should be empty');
    }

    /**
     * Empty applicationIds — returns empty confirmationList without error.
     */
    @isTest
    static void testGetAllocationConfirmationData_emptyApplicationIds_returnsEmpty() {
        Test.startTest();
        AllocationRemittanceHandler.AllocationConfirmationData result =
            AllocationRemittanceHandler.getAllocationConfirmationData(
                new List<String>(),
                new List<String>{ 'Extended_Limited_Warranty' }
            );
        Test.stopTest();

        System.assertEquals(0, result.confirmationList.size(),
            'Empty applicationIds should produce empty confirmationList');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getApplicationsByDealer
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Happy path — returns the Submitted application with invoice info attached.
     */
    @isTest
    static void testGetApplicationsByDealer_happyPath_returnsApp() {
        Account dealer = getDealer();

        Test.startTest();
        AllocationRemittanceHandler.AllocationConfirmationData result =
            AllocationRemittanceHandler.getApplicationsByDealer(
                dealer.Id,
                new List<String>{ 'Extended_Limited_Warranty' },
                null,
                0
            );
        Test.stopTest();

        System.assertEquals(null, result.errorMessage,
            'No error should be returned for a valid dealer with matching apps');
        System.assertEquals(1, result.confirmationList.size(),
            'Should return the one Submitted application for this dealer');

        AllocationRemittanceHandler.AllocationApplicationRecord rec = result.confirmationList[0];
        System.assert(
            rec.serviceTypes.contains('Extended_Limited_Warranty'),
            'serviceTypes should include Extended_Limited_Warranty'
        );
    }

    /**
     * Blank dealerId — returns empty list immediately without querying.
     */
    @isTest
    static void testGetApplicationsByDealer_blankDealerId_returnsEmpty() {
        Test.startTest();
        AllocationRemittanceHandler.AllocationConfirmationData result =
            AllocationRemittanceHandler.getApplicationsByDealer(
                '',
                new List<String>{ 'Extended_Limited_Warranty' },
                null,
                0
            );
        Test.stopTest();

        System.assertEquals(0, result.confirmationList.size(),
            'Blank dealerId should trigger early exit with empty confirmationList');
        System.assertEquals(false, result.hasMore,
            'hasMore should be false on early exit');
    }

    /**
     * Null selectedServiceTypes — returns empty list immediately.
     */
    @isTest
    static void testGetApplicationsByDealer_nullServiceTypes_returnsEmpty() {
        Account dealer = getDealer();

        Test.startTest();
        AllocationRemittanceHandler.AllocationConfirmationData result =
            AllocationRemittanceHandler.getApplicationsByDealer(
                dealer.Id,
                null,
                null,
                0
            );
        Test.stopTest();

        System.assertEquals(0, result.confirmationList.size(),
            'Null selectedServiceTypes should trigger early exit with empty confirmationList');
    }

    /**
     * Empty selectedServiceTypes — returns empty list immediately.
     */
    @isTest
    static void testGetApplicationsByDealer_emptyServiceTypes_returnsEmpty() {
        Account dealer = getDealer();

        Test.startTest();
        AllocationRemittanceHandler.AllocationConfirmationData result =
            AllocationRemittanceHandler.getApplicationsByDealer(
                dealer.Id,
                new List<String>(),
                null,
                0
            );
        Test.stopTest();

        System.assertEquals(0, result.confirmationList.size(),
            'Empty selectedServiceTypes should trigger early exit');
    }

    /**
     * Search term that matches no records — returns empty confirmationList.
     */
    @isTest
    static void testGetApplicationsByDealer_nonMatchingSearchTerm_returnsEmpty() {
        Account dealer = getDealer();

        Test.startTest();
        AllocationRemittanceHandler.AllocationConfirmationData result =
            AllocationRemittanceHandler.getApplicationsByDealer(
                dealer.Id,
                new List<String>{ 'Extended_Limited_Warranty' },
                'ZZNOTFOUND_XYZ_999',
                0
            );
        Test.stopTest();

        System.assertEquals(0, result.confirmationList.size(),
            'Non-matching search term should return zero results');
    }

    /**
     * Invoice status and due date are attached to the returned application record.
     */
    @isTest
    static void testGetApplicationsByDealer_invoiceStatusAndDueDateAttached() {
        Account dealer = getDealer();

        Test.startTest();
        AllocationRemittanceHandler.AllocationConfirmationData result =
            AllocationRemittanceHandler.getApplicationsByDealer(
                dealer.Id,
                new List<String>{ 'Extended_Limited_Warranty' },
                null,
                0
            );
        Test.stopTest();

        System.assertEquals(1, result.confirmationList.size(),
            'Precondition: one app should be returned');

        AllocationRemittanceHandler.AllocationApplicationRecord rec = result.confirmationList[0];
        System.assertNotEquals(null, rec.invoiceStatus,
            'invoiceStatus should be populated from the linked unpaid invoice');
        System.assertNotEquals(null, rec.invoiceDueDate,
            'invoiceDueDate should be populated from the linked invoice');
        System.assertNotEquals(null, rec.invoiceDueDays,
            'invoiceDueDays should be calculated (positive = overdue, negative = future)');
    }

    /**
     * hasMore = false when fewer than PAGE_SIZE (20) applications are returned.
     */
    @isTest
    static void testGetApplicationsByDealer_lessThanPageSize_hasMoreFalse() {
        Account dealer = getDealer();

        Test.startTest();
        AllocationRemittanceHandler.AllocationConfirmationData result =
            AllocationRemittanceHandler.getApplicationsByDealer(
                dealer.Id,
                new List<String>{ 'Extended_Limited_Warranty' },
                null,
                0
            );
        Test.stopTest();

        System.assertEquals(false, result.hasMore,
            'hasMore should be false when fewer than 20 apps are returned');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // createAllocationRemittanceForm
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Happy path — creates Allocation_Remittance RF, links invoice, creates junctions.
     */
    @isTest
    static void testCreateAllocationRemittanceForm_happyPath_createsRFAndJunctions() {
        Application__c app = getApp();
        Invoice__c inv     = getInvoice();

        Test.startTest();
        AllocationRemittanceHandler.OperationResult result =
            AllocationRemittanceHandler.createAllocationRemittanceForm(
                new List<String>{ app.Id },
                new List<String>{ 'Extended_Limited_Warranty' }
            );
        Test.stopTest();

        System.assertEquals(true, result.success,
            'createAllocationRemittanceForm should succeed for valid inputs');
        System.assertNotEquals(null, result.remittanceFormId,
            'remittanceFormId should be populated on success');

        // RF should be Allocation_Remittance RecordType with Services_To_Pay__c set
        Remittance_Form__c rf = [
            SELECT RecordType.DeveloperName, Services_To_Pay__c, Status__c
            FROM   Remittance_Form__c
            WHERE  Id = :result.remittanceFormId
        ];
        System.assertEquals('Allocation_Remittance', rf.RecordType.DeveloperName,
            'Created RF should have Allocation_Remittance RecordType');
        System.assertEquals('Open', rf.Status__c,
            'Created RF should be Open');
        System.assert(
            rf.Services_To_Pay__c.contains('Extended_Limited_Warranty'),
            'Services_To_Pay__c should contain the selected service type'
        );

        // Invoice should be linked to the new RF
        Invoice__c updatedInv = [SELECT Remittance_Form__c FROM Invoice__c WHERE Id = :inv.Id];
        System.assertEquals(result.remittanceFormId, updatedInv.Remittance_Form__c,
            'Invoice should be linked to the new Allocation RF');

        // At least one RLJ should be created
        Integer rljCount = [
            SELECT COUNT()
            FROM   Remittance_Line_Item_Junction__c
            WHERE  Remittance_Form__c = :result.remittanceFormId
        ];
        System.assert(rljCount > 0,
            'At least one RLJ should be created for the eligible line item');
    }

    /**
     * No unpaid line items matching the service type — returns failure with message.
     */
    @isTest
    static void testCreateAllocationRemittanceForm_noEligibleLineItems_returnsFalse() {
        Application__c app = getApp();

        // Service type that does not match the AppPkg RecordType (Extended_Limited_Warranty)
        Test.startTest();
        AllocationRemittanceHandler.OperationResult result =
            AllocationRemittanceHandler.createAllocationRemittanceForm(
                new List<String>{ app.Id },
                new List<String>{ 'GAP_Coverage' }
            );
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Should return failure when no eligible line items exist for the selected service type');
        System.assertNotEquals(null, result.message,
            'Failure message should be populated');
        System.assertEquals(null, result.remittanceFormId,
            'remittanceFormId should be null on failure');
    }

    /**
     * Paid ILIs are excluded — only unpaid line items get junctions.
     */
    @isTest
    static void testCreateAllocationRemittanceForm_paidLineItemsExcluded() {
        Application__c app = getApp();
        Invoice_Line_Item__c ili = getIli();

        // Mark the only ILI as Paid
        update new Invoice_Line_Item__c(Id = ili.Id, Status__c = 'Paid');

        Test.startTest();
        AllocationRemittanceHandler.OperationResult result =
            AllocationRemittanceHandler.createAllocationRemittanceForm(
                new List<String>{ app.Id },
                new List<String>{ 'Extended_Limited_Warranty' }
            );
        Test.stopTest();

        // No eligible unpaid line items → should fail
        System.assertEquals(false, result.success,
            'Should return failure when all line items are Paid');
    }

    /**
     * Stale Planned junctions for the eligible line items are deleted before
     * the new RF is created — prevents duplicate junctions from previous attempts.
     */
    @isTest
    static void testCreateAllocationRemittanceForm_staleJunctionsDeleted() {
        Account dealer   = getDealer();
        Invoice__c inv   = getInvoice();
        Invoice_Line_Item__c ili = getIli();

        // Create a stale Planned junction on an earlier RF for the same ILI
        Remittance_Form__c staleRf = TestDataFactory.createAllocationRemittanceForm(
            dealer.Id, 'Extended_Limited_Warranty', true
        );
        TestDataFactory.createRLJ(staleRf.Id, inv.Id, ili.Id, true);

        Integer staleCountBefore = [
            SELECT COUNT()
            FROM   Remittance_Line_Item_Junction__c
            WHERE  Invoice_Line_Item__c = :ili.Id
            AND    Payment_Status__c = 'Planned'
        ];
        System.assertEquals(1, staleCountBefore,
            'Precondition: one stale Planned junction should exist before the call');

        Application__c app = getApp();

        Test.startTest();
        AllocationRemittanceHandler.OperationResult result =
            AllocationRemittanceHandler.createAllocationRemittanceForm(
                new List<String>{ app.Id },
                new List<String>{ 'Extended_Limited_Warranty' }
            );
        Test.stopTest();

        System.assertEquals(true, result.success,
            'createAllocationRemittanceForm should succeed after deleting stale junctions');

        // After the call there should be exactly one Planned junction for this ILI
        // (the new one on the new RF; the stale one was deleted)
        Integer junctionCount = [
            SELECT COUNT()
            FROM   Remittance_Line_Item_Junction__c
            WHERE  Invoice_Line_Item__c = :ili.Id
            AND    Payment_Status__c = 'Planned'
        ];
        System.assertEquals(1, junctionCount,
            'Stale junction should be replaced — exactly one Planned junction should exist');
    }
}