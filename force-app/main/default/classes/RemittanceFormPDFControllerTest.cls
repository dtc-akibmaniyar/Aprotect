/**
 * RemittanceFormPDFControllerTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Covers RemittanceFormPDFController (Visualforce page controller):
 *   Constructor — blank id, RF not found, Dealer_Remittance path,
 *                 Allocation_Remittance path, service label mapping,
 *                 totals accumulation, empty data cases.
 *
 * Test Strategy:
 *   ✔ @isTest(SeeAllData=false)
 *   ✔ @TestSetup for shared base graph
 *   ✔ All data exclusively via TestDataFactory — no inline SObject creation
 *   ✔ Test.setCurrentPage() with explicit 'id' parameter to drive constructor
 *   ✔ Positive + Negative per branch
 *   ✔ System.assert* with descriptive messages on every assertion
 *   ✔ No hardcoded Ids
 */
@isTest(SeeAllData=false)
private class RemittanceFormPDFControllerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // @TestSetup — shared base graph
    // Creates: Dealer → Package hierarchy → Application
    //          → ApplicationPackage (RecordType + pricing + Active)
    //          → Dealer_Remittance RF
    //          → Invoice linked to that RF (Name='INV-PDF-001')
    //          → InvoiceLineItem
    //
    // Allocation scenarios are built per-test (need distinct RLJs).
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
        Application__c app            = TestDataFactory.createApplication(dealer.Id, true);

        // 8-param: sets RecordType + Active=true + pricing so formula fields resolve
        Application_Package__c appPkg = TestDataFactory.createApplicationPackage(
            app.Id, dp.Id, dpt.Id, dealer.Id,
            'Extended_Limited_Warranty', 1200.00, 13, true
        );

        Remittance_Form__c dealerRf   = TestDataFactory.createDealerRemittanceForm(dealer.Id, true);
        Invoice__c inv                = TestDataFactory.createInvoiceLinkedToRF(
            app.Id, dealerRf.Id, 'INV-PDF-001', true
        );
        TestDataFactory.createInvoiceLineItem(inv.Id, appPkg.Id, true);
    }

    // ── Private query helpers ─────────────────────────────────────────────────

    private static Account getDealer() {
        return [SELECT Id FROM Account LIMIT 1];
    }

    private static Remittance_Form__c getDealerRf() {
        return [
            SELECT Id
            FROM   Remittance_Form__c
            WHERE  RecordType.DeveloperName = 'Dealer_Remittance'
            LIMIT  1
        ];
    }

    private static Application__c getApp() {
        return [SELECT Id FROM Application__c LIMIT 1];
    }

    private static Invoice__c getInvoice() {
        return [SELECT Id, Application__c FROM Invoice__c LIMIT 1];
    }

    private static Invoice_Line_Item__c getIli() {
        return [SELECT Id, Invoice__c FROM Invoice_Line_Item__c LIMIT 1];
    }

    // ── Controller factory helper ─────────────────────────────────────────────

    /**
     * Sets the current page with the given 'id' parameter and instantiates
     * the controller, driving the constructor logic under test.
     * Pass null to simulate a request with no 'id' parameter at all.
     */
    private static RemittanceFormPDFController buildController(String rfId) {
        PageReference pageRef = new PageReference('/apex/RemittanceFormPDF');
        if (rfId != null) {
            pageRef.getParameters().put('id', rfId);
        }
        Test.setCurrentPage(pageRef);
        return new RemittanceFormPDFController();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // NEGATIVE / EDGE CASE TESTS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * No 'id' page parameter — constructor adds an error message and returns
     * without populating any data.
     */
    @isTest
    static void testBlankId_addsErrorMessage() {
        Test.startTest();
        RemittanceFormPDFController ctrl = buildController(null);
        Test.stopTest();

        System.assertEquals(0, ctrl.invoicesWithItems.size(),
            'invoicesWithItems should be empty when no id is supplied');
        System.assertEquals(0, ctrl.totalAmount,
            'totalAmount should be 0 when no id is supplied');
        System.assertEquals(false, ctrl.isAllocationRemittance,
            'isAllocationRemittance should default to false');

        List<ApexPages.Message> msgs = ApexPages.getMessages();
        System.assert(msgs.size() > 0,
            'At least one ApexPages error message should be added for a blank id');
        System.assertEquals(ApexPages.Severity.ERROR, msgs[0].getSeverity(),
            'Error severity should be ERROR for blank id');
    }

    /**
     * 'id' param set to a non-Remittance_Form__c record Id — RF not found,
     * error message added, no data populated.
     */
    @isTest
    static void testRFNotFound_addsErrorMessage() {
        Account dealer = getDealer();

        Test.startTest();
        // Dealer Account Id won't match any Remittance_Form__c → SOQL returns 0 rows
        RemittanceFormPDFController ctrl = buildController(dealer.Id);
        Test.stopTest();

        System.assertEquals(0, ctrl.invoicesWithItems.size(),
            'invoicesWithItems should be empty when RF is not found');

        List<ApexPages.Message> msgs = ApexPages.getMessages();
        System.assert(msgs.size() > 0,
            'An error message should be added when the RF record is not found');
        System.assertEquals(ApexPages.Severity.ERROR, msgs[0].getSeverity(),
            'Error severity should be ERROR when RF is not found');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DEALER_REMITTANCE PATH — POSITIVE TESTS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Happy path — Dealer_Remittance RF with one Invoice and one ILI.
     * Verifies: isAllocationRemittance=false, invoicesWithItems populated,
     * packages list present, lineItems present, selectedServiceLabels=''.
     */
    @isTest
    static void testDealerRemittance_populatesInvoicesAndPackages() {
        Remittance_Form__c rf = getDealerRf();

        Test.startTest();
        RemittanceFormPDFController ctrl = buildController(rf.Id);
        Test.stopTest();

        System.assertEquals(0, ApexPages.getMessages().size(),
            'No error messages should be added for a valid Dealer_Remittance RF');
        System.assertEquals(false, ctrl.isAllocationRemittance,
            'Dealer_Remittance RF should have isAllocationRemittance = false');
        System.assertEquals('', ctrl.selectedServiceLabels,
            'selectedServiceLabels should be empty for non-allocation RF');
        System.assertEquals(1, ctrl.invoicesWithItems.size(),
            'One InvoiceWithItems should be returned for the linked invoice');

        RemittanceFormPDFController.InvoiceWithItems iwi = ctrl.invoicesWithItems[0];
        System.assertNotEquals(null, iwi.invoice,
            'invoice field should be populated');
        System.assertNotEquals(null, iwi.lineItems,
            'lineItems list should be non-null');
        System.assertEquals(1, iwi.lineItems.size(),
            'One line item should be returned');
        System.assertNotEquals(null, iwi.packages,
            'packages list should be non-null');
        System.assertEquals(1, iwi.packages.size(),
            'One PackageWithOptions should be present for the Application_Package');
    }

    /**
     * Totals are accumulated from line item formula fields.
     * invoiceGrandTotal = invoiceSubTotal + invoiceTaxTotal.
     */
    @isTest
    static void testDealerRemittance_totalsAccumulated() {
        Remittance_Form__c rf = getDealerRf();

        Test.startTest();
        RemittanceFormPDFController ctrl = buildController(rf.Id);
        Test.stopTest();

        RemittanceFormPDFController.InvoiceWithItems iwi = ctrl.invoicesWithItems[0];
        System.assertNotEquals(null, iwi.invoiceSubTotal,
            'invoiceSubTotal should not be null');
        System.assertNotEquals(null, iwi.invoiceTaxTotal,
            'invoiceTaxTotal should not be null');
        System.assertEquals(
            iwi.invoiceSubTotal + iwi.invoiceTaxTotal,
            iwi.invoiceGrandTotal,
            'invoiceGrandTotal should equal invoiceSubTotal + invoiceTaxTotal'
        );
        // Controller-level totals mirror the invoice totals
        System.assertEquals(ctrl.totalAmount, iwi.invoiceSubTotal,
            'Controller totalAmount should match the single invoice sub-total');
        System.assertEquals(ctrl.grandTotal,  iwi.invoiceGrandTotal,
            'Controller grandTotal should match the single invoice grand total');
    }

    /**
     * Dealer_Remittance RF with no invoices — invoicesWithItems empty, totals = 0.
     */
    @isTest
    static void testDealerRemittance_noInvoices_emptyList() {
        Account dealer          = getDealer();
        Remittance_Form__c emptyRf = TestDataFactory.createDealerRemittanceForm(dealer.Id, true);

        Test.startTest();
        RemittanceFormPDFController ctrl = buildController(emptyRf.Id);
        Test.stopTest();

        System.assertEquals(0, ctrl.invoicesWithItems.size(),
            'invoicesWithItems should be empty when RF has no linked invoices');
        System.assertEquals(0, ctrl.totalAmount,
            'totalAmount should be 0 when there are no invoices');
        System.assertEquals(0, ctrl.grandTotal,
            'grandTotal should be 0 when there are no invoices');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ALLOCATION_REMITTANCE PATH — POSITIVE TESTS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Allocation_Remittance RF — invoices and line items resolved via RLJ junctions.
     * isAllocationRemittance = true, invoicesWithItems populated.
     */
    @isTest
    static void testAllocationRemittance_resolvesThroughRLJs() {
        Account dealer            = getDealer();
        Invoice__c inv            = getInvoice();
        Invoice_Line_Item__c ili  = getIli();

        Remittance_Form__c allocRf = TestDataFactory.createAllocationRemittanceForm(
            dealer.Id, null, true
        );
        TestDataFactory.createRLJ(allocRf.Id, inv.Id, ili.Id, true);

        Test.startTest();
        RemittanceFormPDFController ctrl = buildController(allocRf.Id);
        Test.stopTest();

        System.assertEquals(0, ApexPages.getMessages().size(),
            'No error messages should be added for a valid Allocation_Remittance RF');
        System.assertEquals(true, ctrl.isAllocationRemittance,
            'isAllocationRemittance should be true for Allocation_Remittance RF');
        System.assertEquals(1, ctrl.invoicesWithItems.size(),
            'One InvoiceWithItems should be resolved via the RLJ');

        RemittanceFormPDFController.InvoiceWithItems iwi = ctrl.invoicesWithItems[0];
        System.assertEquals(1, iwi.lineItems.size(),
            'Line items should be filtered to only those in the junction');
    }

    /**
     * Allocation_Remittance RF with Services_To_Pay__c set.
     * selectedServiceLabels should contain the human-readable labels.
     */
    @isTest
    static void testAllocationRemittance_serviceLabelsMapped() {
        Account dealer            = getDealer();
        Invoice__c inv            = getInvoice();
        Invoice_Line_Item__c ili  = getIli();

        Remittance_Form__c allocRf = TestDataFactory.createAllocationRemittanceForm(
            dealer.Id, 'Extended_Limited_Warranty;GAP_Coverage', true
        );
        TestDataFactory.createRLJ(allocRf.Id, inv.Id, ili.Id, true);

        Test.startTest();
        RemittanceFormPDFController ctrl = buildController(allocRf.Id);
        Test.stopTest();

        System.assert(
            String.isNotBlank(ctrl.selectedServiceLabels),
            'selectedServiceLabels should be populated when Services_To_Pay__c is set'
        );
        System.assert(
            ctrl.selectedServiceLabels.contains('Extended Limited Warranty'),
            'selectedServiceLabels should contain "Extended Limited Warranty"'
        );
        System.assert(
            ctrl.selectedServiceLabels.contains('GAP Coverage'),
            'selectedServiceLabels should contain "GAP Coverage"'
        );
    }

    /**
     * Allocation_Remittance RF with no RLJ records — invoicesWithItems empty, totals = 0.
     */
    @isTest
    static void testAllocationRemittance_noRLJs_emptyList() {
        Account dealer     = getDealer();
        Remittance_Form__c allocRf = TestDataFactory.createAllocationRemittanceForm(
            dealer.Id, null, true
        );

        Test.startTest();
        RemittanceFormPDFController ctrl = buildController(allocRf.Id);
        Test.stopTest();

        System.assertEquals(true, ctrl.isAllocationRemittance,
            'isAllocationRemittance should still be true even with no RLJ records');
        System.assertEquals(0, ctrl.invoicesWithItems.size(),
            'invoicesWithItems should be empty when no RLJ records exist');
        System.assertEquals(0, ctrl.totalAmount,
            'totalAmount should be 0 when no RLJ records exist');
    }
}