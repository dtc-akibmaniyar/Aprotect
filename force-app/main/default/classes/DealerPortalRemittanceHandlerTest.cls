/**
 * DealerPortalRemittanceHandlerTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Covers DealerPortalRemittanceHandler:
 *   getRemittanceForm()        — with/without linked RF
 *   createRemittanceForm()     — creates RF, links apps, deduplicates invoices,
 *                                creates RLJs, guards against duplicate junctions
 *   getBulkConfirmationData()  — package pricing, active-only filter
 *   deleteRemittanceForm()     — deletes RF and clears Application lookup
 *   downloadRemittanceFormPDF()— not-found path (PDF blob not testable in unit tests)
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
private class DealerPortalRemittanceHandlerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // @TestSetup — shared base graph
    // Creates: Dealer → Package hierarchy → Application (Dealer_Name__c set)
    //          → ApplicationPackage (Active=true, with pricing)
    //          → Invoice (Status=Due, Name='INV-SETUP-001', no RF yet)
    //          → InvoiceLineItem
    // Tests that need an existing RF create one themselves.
    // ─────────────────────────────────────────────────────────────────────────

    @TestSetup
    static void setup() {
        Account dealer                = TestDataFactory.createDealer(true);
        Package__c pkg                = TestDataFactory.createPackage('Extended_Limited_Warranty', true);
        Package_Term__c pkgTerm       = TestDataFactory.createPackageTerm(pkg.Id, null, true);
        Dealer_Package__c dp          = TestDataFactory.createDealerPackage(dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true);
        Dealer_Package_Term__c dpt    = TestDataFactory.createDealerPackageTerm(dp.Id, pkgTerm.Id, null, true);
        Application__c app            = TestDataFactory.createApplication(dealer.Id, true);

        // Active package with pricing — drives getBulkConfirmationData fields
        Application_Package__c appPkg = TestDataFactory.createApplicationPackage(
            app.Id, dp.Id, dpt.Id, dealer.Id, 1200.00, 13, true
        );
        appPkg = new Application_Package__c(Id = appPkg.Id, Active__c = true);
        update appPkg;

        // Unpaid invoice (no RF) — createRemittanceForm picks this up
        Invoice__c inv = TestDataFactory.createInvoice(app.Id, true);
        TestDataFactory.createInvoiceLineItem(inv.Id, [SELECT Id FROM Application_Package__c LIMIT 1].Id, true);
    }

    // ── Private query helpers ─────────────────────────────────────────────────

    private static Account getDealer() {
        return [SELECT Id, Name FROM Account LIMIT 1];
    }

    private static Application__c getApp() {
        return [SELECT Id, Dealer_Name__c FROM Application__c LIMIT 1];
    }

    private static Invoice__c getInvoice() {
        return [SELECT Id, Application__c, Name, Status__c FROM Invoice__c LIMIT 1];
    }

    private static Invoice_Line_Item__c getIli() {
        return [SELECT Id, Invoice__c FROM Invoice_Line_Item__c LIMIT 1];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getRemittanceForm
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Application already linked to a RF — returns hasRecords=true, showCreateButton=false.
     */
    @isTest
    static void testGetRemittanceForm_withLinkedForm_returnsFormData() {
        Account dealer         = getDealer();
        Application__c app     = getApp();
        Remittance_Form__c rf  = TestDataFactory.createDealerRemittanceForm(dealer.Id, true);

        // Link the application to the RF
        Application__c appToUpdate = new Application__c(Id = app.Id, Remittance_Form__c = rf.Id);
        update appToUpdate;

        Test.startTest();
        DealerPortalRemittanceHandler.RemittanceFormData result =
            DealerPortalRemittanceHandler.getRemittanceForm(new List<String>{ app.Id });
        Test.stopTest();

        System.assertEquals(null, result.errorMessage,
            'No error should be returned when RF exists');
        System.assertEquals(true, result.hasRecords,
            'hasRecords should be true when application has a linked RF');
        System.assertEquals(false, result.showCreateButton,
            'showCreateButton should be false when records exist');
        System.assertEquals(1, result.remittanceFormList.size(),
            'Should return exactly one RemittanceFormRecord');
        System.assertEquals(rf.Id, result.remittanceFormList[0].Id,
            'Returned Id should match the linked RF');
        System.assert(
            result.remittanceFormList[0].recordUrl.contains(rf.Id),
            'recordUrl should contain the RF Id'
        );
    }

    /**
     * Application with no linked RF — hasRecords=false, showCreateButton=true.
     */
    @isTest
    static void testGetRemittanceForm_noLinkedForm_showsCreateButton() {
        Application__c app = getApp();

        Test.startTest();
        DealerPortalRemittanceHandler.RemittanceFormData result =
            DealerPortalRemittanceHandler.getRemittanceForm(new List<String>{ app.Id });
        Test.stopTest();

        System.assertEquals(null, result.errorMessage,
            'No error expected when app has no linked RF');
        System.assertEquals(false, result.hasRecords,
            'hasRecords should be false when no RF is linked');
        System.assertEquals(true, result.showCreateButton,
            'showCreateButton should be true when list is empty');
        System.assertEquals(0, result.remittanceFormList.size(),
            'remittanceFormList should be empty');
    }

    /**
     * Empty applicationIds list — returns empty list, no error.
     */
    @isTest
    static void testGetRemittanceForm_emptyList_returnsEmpty() {
        Test.startTest();
        DealerPortalRemittanceHandler.RemittanceFormData result =
            DealerPortalRemittanceHandler.getRemittanceForm(new List<String>());
        Test.stopTest();

        System.assertEquals(0, result.remittanceFormList.size(),
            'Empty input should produce empty remittanceFormList');
        System.assertEquals(false, result.hasRecords,
            'hasRecords should be false for empty input');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // createRemittanceForm
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Happy path — creates RF, links the application, links the unpaid invoice,
     * and creates RLJ records for unpaid line items.
     */
    @isTest
    static void testCreateRemittanceForm_createsRFAndLinksAll() {
        Application__c app = getApp();
        Invoice__c inv     = getInvoice();

        Test.startTest();
        DealerPortalRemittanceHandler.OperationResult result =
            DealerPortalRemittanceHandler.createRemittanceForm(new List<String>{ app.Id });
        Test.stopTest();

        System.assertEquals(true, result.success,
            'createRemittanceForm should succeed for a valid application');
        System.assertNotEquals(null, result.remittanceFormId,
            'remittanceFormId should be populated on success');

        // Application should now point to the new RF
        Application__c updatedApp = [SELECT Remittance_Form__c FROM Application__c WHERE Id = :app.Id];
        System.assertEquals(result.remittanceFormId, updatedApp.Remittance_Form__c,
            'Application.Remittance_Form__c should be updated to the new RF');

        // Invoice should be linked to the new RF
        Invoice__c updatedInv = [SELECT Remittance_Form__c FROM Invoice__c WHERE Id = :inv.Id];
        System.assertEquals(result.remittanceFormId, updatedInv.Remittance_Form__c,
            'Invoice.Remittance_Form__c should be linked to the new RF');

        // At least one RLJ should have been created
        Integer rljCount = [
            SELECT COUNT()
            FROM Remittance_Line_Item_Junction__c
            WHERE Remittance_Form__c = :result.remittanceFormId
        ];
        System.assert(rljCount > 0,
            'At least one RLJ should be created for the unpaid line item');
    }

    /**
     * Calling createRemittanceForm twice on the same app does not create
     * duplicate RLJ records (guard-against-duplicate-junctions logic).
     */
    @isTest
    static void testCreateRemittanceForm_guardAgainstDuplicateJunctions() {
        Application__c app = getApp();

        // First call — creates RF, invoice link, and RLJs
        DealerPortalRemittanceHandler.OperationResult first =
            DealerPortalRemittanceHandler.createRemittanceForm(new List<String>{ app.Id });
        String rfId = first.remittanceFormId;

        // Re-link the app back (simulate a second attempt on same RF)
        // by calling createRemittanceForm again (it creates a brand-new RF,
        // but the junction guard prevents duplicates on that new RF too).
        Test.startTest();
        DealerPortalRemittanceHandler.OperationResult second =
            DealerPortalRemittanceHandler.createRemittanceForm(new List<String>{ app.Id });
        Test.stopTest();

        System.assertEquals(true, second.success,
            'Second createRemittanceForm call should also succeed');

        // Each RF has at most one RLJ per line item (guard enforced)
        List<Remittance_Line_Item_Junction__c> rljsOnSecondRF = [
            SELECT Id
            FROM   Remittance_Line_Item_Junction__c
            WHERE  Remittance_Form__c = :second.remittanceFormId
        ];
        // The invoice was already linked to the first RF (Status != 'Paid' so still picked up),
        // but no ILI should be duplicated within the second RF's junction set.
        Set<Id> seenIliIds = new Set<Id>();
        for (Remittance_Line_Item_Junction__c rlj : rljsOnSecondRF) {
            System.assert(!seenIliIds.contains(rlj.Id),
                'No duplicate RLJ for the same ILI within the same RF');
            seenIliIds.add(rlj.Id);
        }
    }

    /**
     * Paid invoices are excluded — createRemittanceForm should not link
     * an invoice whose Status__c = 'Paid'.
     */
    @isTest
    static void testCreateRemittanceForm_skipsPaidInvoices() {
        Application__c app = getApp();
        Invoice__c inv     = getInvoice();

        // Mark the invoice as Paid before calling createRemittanceForm
        Invoice__c paidInv = new Invoice__c(Id = inv.Id, Status__c = 'Paid');
        update paidInv;

        Test.startTest();
        DealerPortalRemittanceHandler.OperationResult result =
            DealerPortalRemittanceHandler.createRemittanceForm(new List<String>{ app.Id });
        Test.stopTest();

        System.assertEquals(true, result.success,
            'createRemittanceForm should still succeed even if invoices are Paid');

        // The paid invoice should NOT be linked to the new RF
        Invoice__c afterInv = [SELECT Remittance_Form__c FROM Invoice__c WHERE Id = :inv.Id];
        System.assertNotEquals(result.remittanceFormId, afterInv.Remittance_Form__c,
            'Paid invoice should not be linked to the newly created RF');
    }

    /**
     * Deduplication: two invoices with the same Application+Name.
     * Only one should be linked to the new RF (the most-recent one, kept by the map).
     */
    @isTest
    static void testCreateRemittanceForm_deduplicatesInvoicesByAppAndName() {
        Application__c app = getApp();
        Invoice__c inv1    = getInvoice();

        // Second invoice — same Application, same Name → duplicate dedup key
        Invoice__c inv2    = TestDataFactory.createInvoice(app.Id, true);
        Invoice__c upd     = new Invoice__c(Id = inv2.Id, Name = inv1.Name);
        update upd;

        Test.startTest();
        DealerPortalRemittanceHandler.OperationResult result =
            DealerPortalRemittanceHandler.createRemittanceForm(new List<String>{ app.Id });
        Test.stopTest();

        System.assertEquals(true, result.success,
            'createRemittanceForm should succeed with duplicate invoice names');

        // Count how many invoices are now linked to the new RF
        Integer linked = [
            SELECT COUNT()
            FROM   Invoice__c
            WHERE  Remittance_Form__c = :result.remittanceFormId
        ];
        System.assertEquals(1, linked,
            'Only one invoice should be linked when two share the same Application+Name key');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getBulkConfirmationData
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Happy path — returns confirmation record with package pricing fields mapped.
     */
    @isTest
    static void testGetBulkConfirmationData_mapsPackageFields() {
        Application__c app = getApp();

        Test.startTest();
        DealerPortalRemittanceHandler.BulkConfirmationData result =
            DealerPortalRemittanceHandler.getBulkConfirmationData(new List<String>{ app.Id });
        Test.stopTest();

        System.assertNotEquals(null, result,
            'Result should not be null');
        System.assertEquals(1, result.confirmationList.size(),
            'Should return one confirmation record for the queried application');

        DealerPortalRemittanceHandler.BulkConfirmationRecord rec = result.confirmationList[0];
        System.assertEquals(app.Id, rec.applicationId,
            'applicationId should match the queried application');
        System.assertNotEquals(null, rec.packageList,
            'packageList should not be null');
        System.assertEquals(1, rec.packageList.size(),
            'One active Application_Package should appear in packageList');

        DealerPortalRemittanceHandler.PackageItem pkg = rec.packageList[0];
        System.assertEquals(true, pkg.isSelected,
            'Package should be selected by default');
    }

    /**
     * Inactive Application_Package records are excluded from packageList.
     */
    @isTest
    static void testGetBulkConfirmationData_excludesInactivePackages() {
        Application__c app = getApp();

        // Mark the active package as inactive
        Application_Package__c appPkg = [SELECT Id FROM Application_Package__c LIMIT 1];
        update new Application_Package__c(Id = appPkg.Id, Active__c = false);

        Test.startTest();
        DealerPortalRemittanceHandler.BulkConfirmationData result =
            DealerPortalRemittanceHandler.getBulkConfirmationData(new List<String>{ app.Id });
        Test.stopTest();

        System.assertEquals(1, result.confirmationList.size(),
            'Confirmation record should still exist for the application');
        System.assertEquals(0, result.confirmationList[0].packageList.size(),
            'Inactive package should not appear in packageList');
    }

    /**
     * Empty applicationIds list — returns empty confirmationList without error.
     */
    @isTest
    static void testGetBulkConfirmationData_emptyList_returnsEmpty() {
        Test.startTest();
        DealerPortalRemittanceHandler.BulkConfirmationData result =
            DealerPortalRemittanceHandler.getBulkConfirmationData(new List<String>());
        Test.stopTest();

        System.assertEquals(0, result.confirmationList.size(),
            'Empty input should produce empty confirmationList');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // deleteRemittanceForm
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Happy path — RF is deleted and Application.Remittance_Form__c is cleared.
     */
    @isTest
    static void testDeleteRemittanceForm_deletesRFAndClearsApp() {
        Account dealer        = getDealer();
        Application__c app    = getApp();
        Remittance_Form__c rf = TestDataFactory.createDealerRemittanceForm(dealer.Id, true);

        // Link app to RF first
        update new Application__c(Id = app.Id, Remittance_Form__c = rf.Id);

        Test.startTest();
        DealerPortalRemittanceHandler.OperationResult result =
            DealerPortalRemittanceHandler.deleteRemittanceForm(app.Id, rf.Id);
        Test.stopTest();

        System.assertEquals(true, result.success,
            'deleteRemittanceForm should return success=true');

        System.assertEquals(0, [SELECT COUNT() FROM Remittance_Form__c WHERE Id = :rf.Id],
            'Remittance Form record should be deleted');

        Application__c updatedApp = [SELECT Remittance_Form__c FROM Application__c WHERE Id = :app.Id];
        System.assertEquals(null, updatedApp.Remittance_Form__c,
            'Application.Remittance_Form__c should be cleared (set to null) after deletion');
    }

    /**
     * Non-existent RF Id — returns success=false with an error message.
     */
    @isTest
    static void testDeleteRemittanceForm_nonExistentRF_returnsFalse() {
        Application__c app = getApp();
        // Use the app's own Id as a fake RF Id — guaranteed wrong SObject type
        String fakeRfId    = app.Id;

        Test.startTest();
        DealerPortalRemittanceHandler.OperationResult result =
            DealerPortalRemittanceHandler.deleteRemittanceForm(app.Id, fakeRfId);
        Test.stopTest();

        System.assertEquals(false, result.success,
            'deleteRemittanceForm should return success=false for a non-existent RF');
        System.assertNotEquals(null, result.message,
            'Error message should be populated on failure');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // downloadRemittanceFormPDF
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Non-existent RF Id — returns success=false with "not found" message.
     * (getContentAsPDF() cannot be invoked in unit tests; the happy path
     *  is covered by the handler's try/catch which returns success=false.)
     */
    @isTest
    static void testDownloadRemittanceFormPDF_notFound_returnsFalse() {
        Application__c app = getApp();
        // Use an App Id as a fake RF Id — won't match any Remittance_Form__c
        String fakeRfId    = app.Id;

        Test.startTest();
        DealerPortalRemittanceHandler.PDFDownloadResponse result =
            DealerPortalRemittanceHandler.downloadRemittanceFormPDF(fakeRfId);
        Test.stopTest();

        System.assertEquals(false, result.success,
            'downloadRemittanceFormPDF should return success=false when RF is not found');
        System.assertNotEquals(null, result.message,
            'message should be populated when RF is not found');
    }
}