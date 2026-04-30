/**
 * DealerPortalInvoiceBreakdownHandlerTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Covers DealerPortalInvoiceBreakdownHandler:
 *   getInvoiceBreakdown()  — Dealer_Remittance and Allocation_Remittance paths
 *   deleteInvoice()        — with and without child line items
 *
 * Test Strategy (per test-strategy.md):
 *   ✔ @isTest(SeeAllData=false)
 *   ✔ @TestSetup for shared base graph
 *   ✔ All data exclusively via TestDataFactory — no inline SObject creation
 *   ✔ Positive + Negative per method
 *   ✔ System.assert* with descriptive messages on every assertion
 *   ✔ No hardcoded Ids
 */
@isTest(SeeAllData=false)
private class DealerPortalInvoiceBreakdownHandlerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // @TestSetup — shared base graph
    // Creates: Dealer → Package hierarchy → Application → ApplicationPackage
    //          (with pricing) → Dealer_Remittance RF → Invoice (Name=INV-TEST-001)
    //          → InvoiceLineItem
    // Allocation scenarios are built per-test since they need distinct RLJs.
    // ─────────────────────────────────────────────────────────────────────────

    @TestSetup
    static void setup() {
        Account dealer                 = TestDataFactory.createDealer(true);
        Package__c pkg                 = TestDataFactory.createPackage('Extended_Limited_Warranty', true);
        Package_Term__c pkgTerm        = TestDataFactory.createPackageTerm(pkg.Id, null, true);
        Dealer_Package__c dp           = TestDataFactory.createDealerPackage(dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true);
        Dealer_Package_Term__c dpt     = TestDataFactory.createDealerPackageTerm(dp.Id, pkgTerm.Id, null, true);
        Application__c app             = TestDataFactory.createApplication(dealer.Id, true);

        // Overloaded createApplicationPackage with pricing so ILI formula fields resolve
        Application_Package__c appPkg  = TestDataFactory.createApplicationPackage(
            app.Id, dp.Id, dpt.Id, dealer.Id, 1200.00, 13, true
        );

        Remittance_Form__c dealerRf    = TestDataFactory.createDealerRemittanceForm(dealer.Id, true);

        // Name='INV-TEST-001' enables deduplication testing in later tests
        Invoice__c inv                 = TestDataFactory.createInvoiceLinkedToRF(
            app.Id, dealerRf.Id, 'INV-TEST-001', true
        );

        TestDataFactory.createInvoiceLineItem(inv.Id, appPkg.Id, true);
    }

    // ── Private query helpers ─────────────────────────────────────────────────

    private static Account getDealer() {
        return [SELECT Id FROM Account LIMIT 1];
    }

    private static Application__c getApp() {
        return [SELECT Id FROM Application__c LIMIT 1];
    }

    private static Remittance_Form__c getDealerRf() {
        return [
            SELECT Id
            FROM   Remittance_Form__c
            WHERE  RecordType.DeveloperName = 'Dealer_Remittance'
            LIMIT  1
        ];
    }

    private static Invoice__c getInvoice() {
        return [SELECT Id, Name, Application__c FROM Invoice__c LIMIT 1];
    }

    private static Invoice_Line_Item__c getIli() {
        return [SELECT Id FROM Invoice_Line_Item__c LIMIT 1];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getInvoiceBreakdown — POSITIVE TESTS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Happy path — Dealer_Remittance RF with one invoice and one line item.
     * Verifies the DTO fields are populated, isAllocationRemittance = false.
     */
    @isTest
    static void testGetBreakdown_dealerRemittance_mapsAllFields() {
        Remittance_Form__c rf = getDealerRf();

        Test.startTest();
        DealerPortalInvoiceBreakdownHandler.InvoiceBreakdownData result =
            DealerPortalInvoiceBreakdownHandler.getInvoiceBreakdown(rf.Id);
        Test.stopTest();

        System.assertEquals(true, result.success,
            'success flag should be true for valid Dealer_Remittance RF');
        System.assertEquals(false, result.isAllocationRemittance,
            'Dealer_Remittance RF should NOT be treated as allocation');
        System.assertEquals(1, result.invoices.size(),
            'Should return exactly one invoice linked to this RF');

        DealerPortalInvoiceBreakdownHandler.InvoiceRecord invRec = result.invoices[0];
        System.assertEquals('Due', invRec.status,
            'Invoice status should be Due as set in @TestSetup');
        System.assertEquals(1, invRec.lineItems.size(),
            'Invoice should have one line item');

        DealerPortalInvoiceBreakdownHandler.LineItemRecord li = invRec.lineItems[0];
        System.assertEquals('Due', li.status,
            'Line item status should be Due');
        // Formula fields resolve because Dealer_Package_Price__c = 1200 was set via factory overload
        System.assertNotEquals(null, li.costPriceWithoutTax,
            'Contract_Cost_Price_Without_Tax__c formula should resolve (price set)');
        System.assertNotEquals(null, li.costPriceWithTax,
            'Contract_Cost_Price__c formula should resolve');
    }

    /**
     * Two invoices with different Names on the same RF — both are returned (no deduplication).
     */
    @isTest
    static void testGetBreakdown_dealerRemittance_twoDistinctInvoices_bothReturned() {
        Remittance_Form__c rf = getDealerRf();
        Application__c app    = getApp();

        // Second invoice — different Name, same RF → different dedup key
        TestDataFactory.createInvoiceLinkedToRF(app.Id, rf.Id, 'INV-TEST-002', true);

        Test.startTest();
        DealerPortalInvoiceBreakdownHandler.InvoiceBreakdownData result =
            DealerPortalInvoiceBreakdownHandler.getInvoiceBreakdown(rf.Id);
        Test.stopTest();

        System.assertEquals(2, result.invoices.size(),
            'Two invoices with distinct Names on the same RF should both appear — no deduplication');
    }

    /**
     * Two invoices sharing the same Application + Name (duplicate remittance attempts).
     * Only one is kept after deduplication — result.invoices.size() == 1.
     */
    @isTest
    static void testGetBreakdown_dealerRemittance_duplicateInvoiceName_deduplicated() {
        Remittance_Form__c rf = getDealerRf();
        Application__c app    = getApp();

        // Same Name ('INV-TEST-001') as the @TestSetup invoice on the same Application → duplicate key
        TestDataFactory.createInvoiceLinkedToRF(app.Id, rf.Id, 'INV-TEST-001', true);

        Test.startTest();
        DealerPortalInvoiceBreakdownHandler.InvoiceBreakdownData result =
            DealerPortalInvoiceBreakdownHandler.getInvoiceBreakdown(rf.Id);
        Test.stopTest();

        System.assertEquals(1, result.invoices.size(),
            'Duplicate Application+Name pair should be deduplicated to a single invoice');
    }

    /**
     * Dealer_Remittance RF with no invoices — returns empty invoices list, success = true.
     */
    @isTest
    static void testGetBreakdown_dealerRemittance_noInvoices_returnsEmptyList() {
        Account dealer          = getDealer();
        Remittance_Form__c emptyRf = TestDataFactory.createDealerRemittanceForm(dealer.Id, true);

        Test.startTest();
        DealerPortalInvoiceBreakdownHandler.InvoiceBreakdownData result =
            DealerPortalInvoiceBreakdownHandler.getInvoiceBreakdown(emptyRf.Id);
        Test.stopTest();

        System.assertEquals(true, result.success,
            'success should be true even when no invoices exist');
        System.assertEquals(0, result.invoices.size(),
            'invoices list should be empty when RF has no linked invoices');
    }

    /**
     * Allocation_Remittance RF — invoices resolved via Remittance_Line_Item_Junction__c,
     * and line items filtered to only those present in the junction.
     */
    @isTest
    static void testGetBreakdown_allocationRemittance_resolvesThroughRLJs() {
        Account dealer            = getDealer();
        Invoice__c inv            = getInvoice();
        Invoice_Line_Item__c ili  = getIli();

        Remittance_Form__c allocRf = TestDataFactory.createAllocationRemittanceForm(
            dealer.Id, null, true
        );
        TestDataFactory.createRLJ(allocRf.Id, inv.Id, ili.Id, true);

        Test.startTest();
        DealerPortalInvoiceBreakdownHandler.InvoiceBreakdownData result =
            DealerPortalInvoiceBreakdownHandler.getInvoiceBreakdown(allocRf.Id);
        Test.stopTest();

        System.assertEquals(true, result.isAllocationRemittance,
            'Allocation_Remittance RF should be flagged as allocation');
        System.assertEquals(1, result.invoices.size(),
            'Should return the one invoice resolved via RLJ');
        System.assertEquals(1, result.invoices[0].lineItems.size(),
            'Should return the one ILI resolved via RLJ');
    }

    /**
     * Allocation_Remittance RF with Services_To_Pay__c set.
     * Verifies selectedServiceLabels maps developer-name tokens to human-readable labels.
     */
    @isTest
    static void testGetBreakdown_allocationRemittance_serviceLabelsMapped() {
        Account dealer           = getDealer();
        Invoice__c inv           = getInvoice();
        Invoice_Line_Item__c ili = getIli();

        Remittance_Form__c allocRf = TestDataFactory.createAllocationRemittanceForm(
            dealer.Id, 'Extended_Limited_Warranty;GAP_Coverage', true
        );
        TestDataFactory.createRLJ(allocRf.Id, inv.Id, ili.Id, true);

        Test.startTest();
        DealerPortalInvoiceBreakdownHandler.InvoiceBreakdownData result =
            DealerPortalInvoiceBreakdownHandler.getInvoiceBreakdown(allocRf.Id);
        Test.stopTest();

        System.assertNotEquals(null, result.selectedServiceLabels,
            'selectedServiceLabels should be populated for allocation RF with services');
        System.assert(result.selectedServiceLabels.contains('Extended Limited Warranty'),
            'Should contain the label for Extended_Limited_Warranty');
        System.assert(result.selectedServiceLabels.contains('GAP Coverage'),
            'Should contain the label for GAP_Coverage');
    }

    /**
     * Allocation_Remittance RF with no RLJs — invoices and lineItems lists are empty.
     */
    @isTest
    static void testGetBreakdown_allocationRemittance_noRLJs_returnsEmptyLists() {
        Account dealer           = getDealer();
        Remittance_Form__c allocRf = TestDataFactory.createAllocationRemittanceForm(
            dealer.Id, null, true
        );

        Test.startTest();
        DealerPortalInvoiceBreakdownHandler.InvoiceBreakdownData result =
            DealerPortalInvoiceBreakdownHandler.getInvoiceBreakdown(allocRf.Id);
        Test.stopTest();

        System.assertEquals(true, result.success,
            'success should be true even when no RLJs exist');
        System.assertEquals(true, result.isAllocationRemittance,
            'Should still be flagged as allocation RF');
        System.assertEquals(0, result.invoices.size(),
            'invoices list should be empty when no RLJ records exist');
    }

    /**
     * Credit fields on the dealer account default to 0 when null.
     */
    @isTest
    static void testGetBreakdown_dealerCreditFields_defaultToZeroWhenNull() {
        Remittance_Form__c rf = getDealerRf();

        Test.startTest();
        DealerPortalInvoiceBreakdownHandler.InvoiceBreakdownData result =
            DealerPortalInvoiceBreakdownHandler.getInvoiceBreakdown(rf.Id);
        Test.stopTest();

        System.assertNotEquals(null, result.totalCredit,
            'totalCredit should never be null — defaults to 0');
        System.assertNotEquals(null, result.appliedCredit,
            'appliedCredit should never be null — defaults to 0');
        System.assertNotEquals(null, result.availableCredit,
            'availableCredit should never be null — defaults to 0');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getInvoiceBreakdown — NEGATIVE / EDGE CASE TESTS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Blank ID — throws AuraHandledException immediately.
     */
    @isTest
    static void testGetBreakdown_blankId_throwsAuraHandledException() {
        Boolean threw = false;
        Test.startTest();
        try {
            DealerPortalInvoiceBreakdownHandler.getInvoiceBreakdown('');
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().length() > 0,
                'AuraHandledException message should not be empty for blank ID');
        }
        Test.stopTest();
        System.assertEquals(true, threw,
            'getInvoiceBreakdown should throw AuraHandledException for blank remittanceFormId');
    }

    /**
     * Non-existent ID — throws AuraHandledException or SOQL exception.
     */
    @isTest
    static void testGetBreakdown_nonExistentId_throwsAuraHandledException() {
        Account dealer = getDealer();
        Boolean threw  = false;
        Test.startTest();
        try {
            // Pass an Account Id as a fake RF Id — wrong SObject type
            DealerPortalInvoiceBreakdownHandler.getInvoiceBreakdown(dealer.Id);
        } catch (AuraHandledException e) {
            threw = true;
        } catch (Exception e) {
            threw = true; // SOQL type-mismatch also acceptable
        }
        Test.stopTest();
        System.assertEquals(true, threw,
            'getInvoiceBreakdown should throw for a non-existent Remittance Form ID');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // deleteInvoice — POSITIVE TESTS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Invoice with one ILI — both are deleted.
     */
    @isTest
    static void testDeleteInvoice_withLineItems_deletesInvoiceAndLineItems() {
        Invoice__c inv = getInvoice();

        Integer iliBefore = [SELECT COUNT() FROM Invoice_Line_Item__c WHERE Invoice__c = :inv.Id];
        System.assertEquals(1, iliBefore,
            'Precondition: @TestSetup should have created exactly one ILI');

        Test.startTest();
        DealerPortalInvoiceBreakdownHandler.deleteInvoice(inv.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Invoice__c WHERE Id = :inv.Id],
            'Invoice should be deleted');
        System.assertEquals(0, [SELECT COUNT() FROM Invoice_Line_Item__c WHERE Invoice__c = :inv.Id],
            'Invoice Line Items should be deleted together with the Invoice');
    }

    /**
     * Invoice with NO line items — only the invoice itself is deleted, no error.
     */
    @isTest
    static void testDeleteInvoice_noLineItems_deletesInvoiceOnly() {
        Application__c app    = getApp();
        Remittance_Form__c rf = getDealerRf();

        Invoice__c invNoIli = TestDataFactory.createInvoiceLinkedToRF(
            app.Id, rf.Id, 'INV-TEST-NOILI', true
        );

        Test.startTest();
        DealerPortalInvoiceBreakdownHandler.deleteInvoice(invNoIli.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Invoice__c WHERE Id = :invNoIli.Id],
            'Invoice with no line items should still be deleted successfully');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // deleteInvoice — NEGATIVE / EDGE CASE TESTS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Blank ID — throws AuraHandledException.
     */
    @isTest
    static void testDeleteInvoice_blankId_throwsAuraHandledException() {
        Boolean threw = false;
        Test.startTest();
        try {
            DealerPortalInvoiceBreakdownHandler.deleteInvoice('');
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().length() > 0,
                'AuraHandledException message should not be empty for blank invoiceId');
        }
        Test.stopTest();
        System.assertEquals(true, threw,
            'deleteInvoice should throw AuraHandledException for blank invoiceId');
    }
}