/**
 * RemittanceDuplicateInvoiceCleanupTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Tests for:
 *   - Scenario 1: Invoice available on multiple unpaid remittances
 *   - Scenario 2: Auto-cleanup of duplicate junctions on remittance completion
 *
 * Uses TestDataFactory for all data creation.
 */
@isTest(SeeAllData=false)
private class RemittanceDuplicateInvoiceCleanupTest {

    @TestSetup
    static void setup() {
        Account dealer = TestDataFactory.createDealer(true);
        Package__c pkg = TestDataFactory.createPackage('Extended_Limited_Warranty', true);
        Package_Term__c pkgTerm = TestDataFactory.createPackageTerm(pkg.Id, null, true);
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true);
        Dealer_Package_Term__c dpt = TestDataFactory.createDealerPackageTerm(dp.Id, pkgTerm.Id, null, true);
        Application__c app = TestDataFactory.createApplication(dealer.Id, true);
        Application_Package__c appPkg = TestDataFactory.createApplicationPackage(
            app.Id, dp.Id, dpt.Id, dealer.Id, 1200.00, 13, true
        );

        // Create two remittance forms (both Open, no payments)
        Remittance_Form__c rf1 = TestDataFactory.createDealerRemittanceForm(dealer.Id, true);
        Remittance_Form__c rf2 = TestDataFactory.createDealerRemittanceForm(dealer.Id, true);

        // Create invoice linked to rf1
        Invoice__c inv = TestDataFactory.createInvoiceLinkedToRF(app.Id, rf1.Id, 'INV-DUP-001', true);
        Invoice_Line_Item__c ili = TestDataFactory.createInvoiceLineItem(inv.Id, appPkg.Id, true);

        // Create junction on rf1
        TestDataFactory.createRLJ(rf1.Id, inv.Id, ili.Id, true);
    }

    private static Account getDealer() {
        return [SELECT Id FROM Account LIMIT 1];
    }

    private static List<Remittance_Form__c> getRemittanceForms() {
        return [SELECT Id, Status__c FROM Remittance_Form__c ORDER BY CreatedDate ASC];
    }

    private static Invoice__c getInvoice() {
        return [SELECT Id, Remittance_Form__c FROM Invoice__c LIMIT 1];
    }

    private static Invoice_Line_Item__c getIli() {
        return [SELECT Id FROM Invoice_Line_Item__c LIMIT 1];
    }

    /**
     * Helper: Mark all junctions on a remittance as 'Paid' so the
     * validation rule allows setting Status__c = 'Completed'.
     */
    private static void markJunctionsPaid(Id remittanceFormId) {
        List<Remittance_Line_Item_Junction__c> junctions = [
            SELECT Id, Payment_Status__c
            FROM Remittance_Line_Item_Junction__c
            WHERE Remittance_Form__c = :remittanceFormId
        ];
        for (Remittance_Line_Item_Junction__c j : junctions) {
            j.Payment_Status__c = 'Paid';
        }
        if (!junctions.isEmpty()) {
            update junctions;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 1: Invoice available on multiple unpaid remittances
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * An invoice on an unpaid remittance should be addable to another unpaid remittance.
     */
    @isTest
    static void testAddInvoiceToSecondUnpaidRemittance_succeeds() {
        List<Remittance_Form__c> rfs = getRemittanceForms();
        Remittance_Form__c rf1 = rfs[0];
        Remittance_Form__c rf2 = rfs[1];
        Invoice__c inv = getInvoice();

        Test.startTest();
        DealerPortalInvoiceBreakdownHandler.addInvoiceToRemittance(rf2.Id, inv.Id);
        Test.stopTest();

        // Invoice should now have junctions on both remittances
        Integer junctionsOnRf1 = [SELECT COUNT() FROM Remittance_Line_Item_Junction__c
            WHERE Remittance_Form__c = :rf1.Id AND Invoice__c = :inv.Id];
        Integer junctionsOnRf2 = [SELECT COUNT() FROM Remittance_Line_Item_Junction__c
            WHERE Remittance_Form__c = :rf2.Id AND Invoice__c = :inv.Id];

        System.assert(junctionsOnRf1 > 0, 'Invoice should still have junctions on RF1');
        System.assert(junctionsOnRf2 > 0, 'Invoice should now have junctions on RF2');
    }

    /**
     * An invoice on a remittance with payment should NOT be available to add to another.
     */
    @isTest
    static void testGetAvailableInvoices_excludesInvoicesOnPaidRemittance() {
        List<Remittance_Form__c> rfs = getRemittanceForms();
        Remittance_Form__c rf1 = rfs[0];
        Remittance_Form__c rf2 = rfs[1];
        Invoice__c inv = getInvoice();

        // Create a payment on rf1 to simulate payment initiated
        Payment__c pmt = new Payment__c(
            Remittance_Form__c = rf1.Id,
            Amount__c = 100
        );
        insert pmt;

        Test.startTest();
        List<DealerPortalInvoiceBreakdownHandler.AvailableInvoice> available =
            DealerPortalInvoiceBreakdownHandler.getAvailableInvoicesForRemittance(rf2.Id);
        Test.stopTest();

        // The invoice should NOT be in the available list (it's on a remittance with payment)
        Set<Id> availableIds = new Set<Id>();
        for (DealerPortalInvoiceBreakdownHandler.AvailableInvoice ai : available) {
            availableIds.add(ai.id);
        }
        System.assert(!availableIds.contains(inv.Id),
            'Invoice on a remittance with payment should NOT be available');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 2: Auto-cleanup on remittance completion
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * When a remittance is completed, duplicate junctions on other unpaid
     * remittances should be automatically removed.
     */
    @isTest
    static void testCompletionCleanup_removesDuplicateJunctions() {
        List<Remittance_Form__c> rfs = getRemittanceForms();
        Remittance_Form__c rf1 = rfs[0];
        Remittance_Form__c rf2 = rfs[1];
        Invoice__c inv = getInvoice();
        Invoice_Line_Item__c ili = getIli();

        // Add same invoice to rf2 (creating duplicate)
        TestDataFactory.createRLJ(rf2.Id, inv.Id, ili.Id, true);

        // Verify both have junctions
        System.assertEquals(1, [SELECT COUNT() FROM Remittance_Line_Item_Junction__c
            WHERE Remittance_Form__c = :rf2.Id AND Invoice__c = :inv.Id],
            'Precondition: RF2 should have junction for invoice');

        // Mark all junctions on rf1 as Paid so validation allows completion
        markJunctionsPaid(rf1.Id);

        Test.startTest();
        // Complete rf1
        rf1.Status__c = 'Completed';
        update rf1;
        Test.stopTest();

        // RF2's junction for this invoice should be deleted
        Integer rf2Junctions = [SELECT COUNT() FROM Remittance_Line_Item_Junction__c
            WHERE Remittance_Form__c = :rf2.Id AND Invoice__c = :inv.Id];
        System.assertEquals(0, rf2Junctions,
            'Junction on RF2 should be deleted after RF1 is completed');

        // RF1's junction should still exist
        Integer rf1Junctions = [SELECT COUNT() FROM Remittance_Line_Item_Junction__c
            WHERE Remittance_Form__c = :rf1.Id AND Invoice__c = :inv.Id];
        System.assert(rf1Junctions > 0,
            'Junction on completed RF1 should still exist');

        // Invoice lookup should point to completed remittance
        Invoice__c updatedInv = [SELECT Remittance_Form__c FROM Invoice__c WHERE Id = :inv.Id];
        System.assertEquals(rf1.Id, updatedInv.Remittance_Form__c,
            'Invoice lookup should point to the completed remittance');
    }

    /**
     * Cleanup should NOT delete junctions on remittances that have payments.
     */
    @isTest
    static void testCompletionCleanup_preservesJunctionsOnPaidRemittances() {
        List<Remittance_Form__c> rfs = getRemittanceForms();
        Remittance_Form__c rf1 = rfs[0];
        Remittance_Form__c rf2 = rfs[1];
        Invoice__c inv = getInvoice();
        Invoice_Line_Item__c ili = getIli();

        // Add same invoice to rf2
        TestDataFactory.createRLJ(rf2.Id, inv.Id, ili.Id, true);

        // Add payment to rf2 (simulating payment initiated on rf2)
        insert new Payment__c(Remittance_Form__c = rf2.Id, Amount__c = 500);

        // Mark all junctions on rf1 as Paid
        markJunctionsPaid(rf1.Id);

        Test.startTest();
        rf1.Status__c = 'Completed';
        update rf1;
        Test.stopTest();

        // RF2's junction should NOT be deleted because rf2 has payments
        Integer rf2Junctions = [SELECT COUNT() FROM Remittance_Line_Item_Junction__c
            WHERE Remittance_Form__c = :rf2.Id AND Invoice__c = :inv.Id];
        System.assert(rf2Junctions > 0,
            'Junction on RF2 with payments should NOT be deleted');
    }

    /**
     * cleanupDuplicateInvoices with empty set — no error, no-op.
     */
    @isTest
    static void testCleanup_emptySet_noOp() {
        Test.startTest();
        RemittanceDuplicateInvoiceCleanup.cleanupDuplicateInvoices(new Set<Id>());
        RemittanceDuplicateInvoiceCleanup.cleanupDuplicateInvoices(null);
        Test.stopTest();
        // No exception = pass
        System.assert(true, 'Empty/null input should not throw');
    }

    /**
     * Completion with no duplicate invoices — no error, no deletions.
     */
    @isTest
    static void testCompletionCleanup_noDuplicates_noOp() {
        List<Remittance_Form__c> rfs = getRemittanceForms();
        Remittance_Form__c rf1 = rfs[0];

        // Mark all junctions on rf1 as Paid
        markJunctionsPaid(rf1.Id);

        Integer junctionsBefore = [SELECT COUNT() FROM Remittance_Line_Item_Junction__c];

        Test.startTest();
        rf1.Status__c = 'Completed';
        update rf1;
        Test.stopTest();

        Integer junctionsAfter = [SELECT COUNT() FROM Remittance_Line_Item_Junction__c];
        System.assertEquals(junctionsBefore, junctionsAfter,
            'No junctions should be deleted when there are no duplicates');
    }
}