/**
 * TASK-050 requirement 3: the work order document, previewed then saved or
 * saved and sent for customer and repair shop authorization.
 *
 * These tests build a Work_Order__c directly with its snapshot fields rather
 * than pricing a whole estimate through createWorkOrder. That is deliberate:
 * what is under test here is the document and the save-and-send path, and the
 * pricing route is already covered exhaustively by ClaimEstimateServiceTest.
 * Going through it again would couple these tests to changes that have nothing
 * to do with the PDF.
 *
 * Note that PageReference.getContentAsPDF cannot run in a test context, so
 * WorkOrderPDFService stands in a blob behind Test.isRunningTest. That means
 * these tests prove the storing, versioning, recipient and error behaviour,
 * NOT that the Visualforce page renders. The page is exercised separately by
 * pageRendersWithoutError below, which is what catches a broken merge field or
 * a bad field reference on it.
 */
@IsTest
private class WorkOrderPDFServiceTest {

    private static Work_Order__c seedWorkOrder() {
        Estimate__c est = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);

        Work_Order__c wo = new Work_Order__c(
            Claim__c              = est.Claim__c,
            Estimate__c           = est.Id,
            Repair_Shop__c        = est.Repair_Shop__c,
            // Deductable__c is deliberately absent: it is a formula on
            // Work_Order__c deriving from the claim's package, so it is not
            // writeable. The document reads it, which needs no seeding here.
            Tax_Percentage__c     = 13,
            Application_Number__c = 'AP-TEST-1',
            Customer_Name__c      = 'Dana Fletcher',
            Customer_Address__c   = '1 Test Street, Toronto ON',
            Customer_Phone__c     = '416-555-0100',
            Customer_Email__c     = 'dana.fletcher@example.invalid',
            VIN__c                = '1HGCM82633A004352',
            Vehicle_Year__c       = '2015',
            Vehicle_Make__c       = 'BMW',
            Vehicle_Model__c      = '6-Series',
            Vehicle_Trim__c       = 'Gran Coupe',
            Odometer_In__c        = 85000,
            Odometer_In_Unit__c   = 'KM'
        );
        insert wo;

        Claim_Line_Item__c cli = new Claim_Line_Item__c(
            Claim__c        = est.Claim__c,
            Line_Type__c    = 'Part',
            Description__c  = 'Engine',
            Amount__c       = 1500,
            Retail_Amount__c = 2800
        );
        insert cli;

        insert new Work_Order_Line_Item__c(
            Customer_Work_Order__c = wo.Id,
            Claim_Line_Item__c     = cli.Id,
            Description__c         = 'Engine, reconditioned',
            Wholesale__c           = 1500,
            // createWorkOrder sets both, and Price__c is what the work order's
            // Total_Line_Items_Cost__c rolls up, so the seed sets both too.
            Price__c               = 2800,
            Retail__c              = 2800,
            Covered_Amount__c      = 1833.12,
            Customer_Pay_Amount__c = 966.88
        );
        return wo;
    }

    @IsTest
    static void previewContextCarriesBothRecipientsAndThePageUrl() {
        Work_Order__c wo = seedWorkOrder();

        Test.startTest();
        WorkOrderPDFService.PreviewContext c = WorkOrderPDFService.getPreviewContext(wo.Id);
        Test.stopTest();

        System.assertEquals('Dana Fletcher', c.customerName);
        System.assertEquals('dana.fletcher@example.invalid', c.customerEmail,
            'the screen shows the customer email at the top, so it has to come back');
        System.assert(c.pdfUrl.contains('/apex/WorkOrderPDF'),
            'the preview frame needs the page url: ' + c.pdfUrl);
        System.assert(c.pdfUrl.contains(wo.Id), 'and it must carry the record id');
    }

    @IsTest
    static void savePdfStoresTheDocumentAgainstTheWorkOrder() {
        Work_Order__c wo = seedWorkOrder();

        Test.startTest();
        WorkOrderPDFService.PdfResult r = WorkOrderPDFService.savePdf(wo.Id);
        Test.stopTest();

        System.assertEquals(true, r.success);
        System.assert(r.fileName.endsWith('.pdf'), 'named as a pdf: ' + r.fileName);
        System.assertNotEquals(null, r.contentVersionId);

        System.assertEquals(1, [
            SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :wo.Id
        ], 'the file must be linked to the work order, not left floating');
    }

    /**
     * Re-saving must add a VERSION, not a second file. A work order that has
     * been revised three times should show one document with a history, not
     * three near-identical attachments nobody can tell apart.
     */
    @IsTest
    static void savingTwiceVersionsTheSameDocument() {
        Work_Order__c wo = seedWorkOrder();

        Test.startTest();
        WorkOrderPDFService.PdfResult first = WorkOrderPDFService.savePdf(wo.Id);
        WorkOrderPDFService.PdfResult second = WorkOrderPDFService.savePdf(wo.Id);
        Test.stopTest();

        System.assertEquals(first.contentDocumentId, second.contentDocumentId,
            'same ContentDocument, so this is a new version of one file');
        System.assertNotEquals(first.contentVersionId, second.contentVersionId,
            'but a genuinely new version');
        System.assertEquals(1, [
            SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :wo.Id
        ], 'still exactly one document on the record');
    }

    @IsTest
    static void saveAndSendSavesAndReportsWhoItWentTo() {
        Work_Order__c wo = seedWorkOrder();

        Test.startTest();
        WorkOrderPDFService.PdfResult r = WorkOrderPDFService.saveAndSendPdf(
            wo.Id, new List<String>{ 'dana.fletcher@example.invalid', 'shop@example.invalid' });
        Test.stopTest();

        System.assertEquals(true, r.success);
        System.assertEquals(2, r.sentTo.size(), 'the screen reports both recipients back to the agent');
        System.assertEquals(1, [
            SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :wo.Id
        ], 'send saves first, so the document is on the record either way');
    }

    /**
     * Sending to nobody must be refused rather than quietly doing nothing. The
     * message has to be readable, not "Script-thrown exception", which is what
     * AuraHandledException gives without setMessage.
     */
    @IsTest
    static void saveAndSendRefusesAnEmptyRecipientList() {
        Work_Order__c wo = seedWorkOrder();

        String message;
        Test.startTest();
        try {
            WorkOrderPDFService.saveAndSendPdf(wo.Id, new List<String>{ '', '   ' });
            System.assert(false, 'expected a refusal: blank strings are not recipients');
        } catch (Exception e) {
            message = e.getMessage();
        }
        Test.stopTest();

        System.assert(message != null && message.contains('at least one email'),
            'and it must say what to do about it: ' + message);
        System.assertEquals(0, [
            SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :wo.Id
        ], 'nothing may be saved when the send is refused up front');
    }

    /**
     * TASK-051. The reimbursement variant lists the work order's OWN
     * estimate's receipts and nothing else. CWO-0044 printed a 100 claim-level
     * Car Rental draw alongside the scenario's 120 and 85 and totalled 305
     * while the customer was being reimbursed 205 (Osama, 2026-10-13).
     */
    @IsTest
    static void reimbursementDocumentListsOnlyItsOwnEstimateReceipts() {
        Estimate__c est = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        Claim__c claim = [SELECT Id, Name, Application__c FROM Claim__c WHERE Id = :est.Claim__c];

        Application_Package__c pkg = new Application_Package__c(
            Application__c = claim.Application__c, Payment_Status__c = 'Not Paid',
            Per_Claim_Limit__c = 3000, Deductible__c = 100);
        insert pkg;
        claim.Application_Package__c = pkg.Id;
        update claim;

        Benefit_Balance__c rental = new Benefit_Balance__c(
            Application_Package__c = pkg.Id, Benefit_Type__c = 'Car Rental', Cap_Amount__c = 500);
        Benefit_Balance__c roadside = new Benefit_Balance__c(
            Application_Package__c = pkg.Id, Benefit_Type__c = 'Roadside Assistance', Cap_Amount__c = 200);
        insert new List<Benefit_Balance__c>{ rental, roadside };

        update new Estimate__c(Id = est.Id, Claim_Type__c = 'Reimbursement Only');
        insert new List<Benefit_Usage__c>{
            // claim-level draw: must NOT reach this document
            new Benefit_Usage__c(Benefit_Balance__c = rental.Id, Claim__c = claim.Id,
                Amount_Used__c = 100, Date__c = Date.today(), Counts_Toward_Balance__c = true),
            new Benefit_Usage__c(Benefit_Balance__c = rental.Id, Claim__c = claim.Id, Estimate__c = est.Id,
                Amount_Used__c = 120, Date__c = Date.today(), Counts_Toward_Balance__c = true),
            // 250 against a 200 cap: approved 200, 50 over
            new Benefit_Usage__c(Benefit_Balance__c = roadside.Id, Claim__c = claim.Id, Estimate__c = est.Id,
                Amount_Used__c = 250, Date__c = Date.today(), Counts_Toward_Balance__c = true)
        };

        Work_Order__c wo = new Work_Order__c(
            Claim__c = claim.Id, Estimate__c = est.Id, Customer_Name__c = 'Reimbursed Customer',
            Reimbursement_Payment_Method__c = 'Interac e-Transfer to the e-mail above',
            Reimbursement_Expected_Payment_Date__c = Date.newInstance(2026, 10, 27));
        insert wo;

        Test.startTest();
        WorkOrderPDFController ctrl = new WorkOrderPDFController(wo.Id);
        Test.stopTest();

        System.assertEquals('Reimbursement Authorization', ctrl.getTitle());
        System.assertEquals(true, ctrl.getIsReimbursement());
        System.assertEquals(false, ctrl.getIsRepair(), 'the repair section is suppressed');
        System.assertEquals(false, ctrl.getIsFullyCovered());

        System.assertEquals(2, ctrl.benefitLines.size(), 'the two receipts, not the claim-level draw');
        WorkOrderPDFController.BenefitRow car = ctrl.benefitLines[0];
        System.assertEquals('Car Rental', car.benefitType);
        System.assertEquals('$120.00', car.receiptsDisplay);
        System.assertEquals('$120.00', car.amountDisplay);
        System.assertEquals('$280.00', car.leftOnTermDisplay, '500 - 100 claim draw - 120');
        System.assertEquals(false, car.hasOver);

        WorkOrderPDFController.BenefitRow road = ctrl.benefitLines[1];
        System.assertEquals('$250.00', road.receiptsDisplay);
        System.assertEquals('$200.00', road.amountDisplay, 'approved only up to the cap');
        System.assertEquals('$0.00', road.leftOnTermDisplay);
        System.assertEquals('$50.00 is over the benefit limit and is not covered', road.overNote);

        System.assertEquals(320, ctrl.getReimbursedTotal(), '120 + 200 approved, never the 100 claim draw');
        System.assertEquals('$370.00', ctrl.getReceiptsTotalDisplay());
        System.assertEquals(true, ctrl.getAnyOver());
        System.assertEquals('Interac e-Transfer to the e-mail above', ctrl.getPaymentMethodDisplay());
        System.assertEquals('October 27, 2026', ctrl.getExpectedPaymentDisplay());
        System.assertEquals('Questions? Call 1-866-660-7444 or e-mail info@a-protectwarranty.com and quote claim '
            + claim.Name + '.', ctrl.getQuestionsLine(), 'the claim\'s own number, never a fixed one');
    }

    /** Snapshot fields blank, as on a work order created before TASK-051: n/a, nothing invented. */
    @IsTest
    static void reimbursementPaymentDetailsReadNaWhenNotSnapshotted() {
        Estimate__c est = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        update new Estimate__c(Id = est.Id, Claim_Type__c = 'Reimbursement Only');
        Work_Order__c wo = new Work_Order__c(Claim__c = est.Claim__c, Estimate__c = est.Id);
        insert wo;

        Test.startTest();
        WorkOrderPDFController ctrl = new WorkOrderPDFController(wo.Id);
        Test.stopTest();

        System.assertEquals('n/a', ctrl.getPaymentMethodDisplay());
        System.assertEquals('n/a', ctrl.getExpectedPaymentDisplay());
        System.assertEquals(0, ctrl.benefitLines.size());
        System.assertEquals('$0.00', ctrl.getReceiptsTotalDisplay());
    }

    /**
     * The repair variant still credits claim-level ancillary draws in Warranty
     * Coverage, unchanged by TASK-051.
     */
    @IsTest
    static void repairDocumentStillCreditsClaimLevelBenefits() {
        Estimate__c est = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        Claim__c claim = [SELECT Id, Application__c FROM Claim__c WHERE Id = :est.Claim__c];

        Application_Package__c pkg = new Application_Package__c(
            Application__c = claim.Application__c, Payment_Status__c = 'Not Paid',
            Per_Claim_Limit__c = 3000, Deductible__c = 100);
        insert pkg;
        claim.Application_Package__c = pkg.Id;
        update claim;

        Benefit_Balance__c balance = new Benefit_Balance__c(
            Application_Package__c = pkg.Id, Benefit_Type__c = 'Car Rental', Cap_Amount__c = 500);
        insert balance;
        insert new Benefit_Usage__c(
            Benefit_Balance__c = balance.Id, Claim__c = claim.Id, Amount_Used__c = 150,
            Date__c = Date.today(), Counts_Toward_Balance__c = true);

        Work_Order__c wo = new Work_Order__c(
            Claim__c = claim.Id, Estimate__c = est.Id, Customer_Name__c = 'Repair Customer');
        insert wo;

        Test.startTest();
        WorkOrderPDFController ctrl = new WorkOrderPDFController(wo.Id);
        Test.stopTest();

        System.assertEquals('Claim Authorization', ctrl.getTitle());
        System.assertEquals(true, ctrl.getIsRepair());

        System.assertEquals(1, ctrl.benefitLines.size(), 'the claim draw must reach the document');
        System.assertEquals('Ancillary Benefit: Car Rental', ctrl.benefitLines[0].label,
            'same label the preview uses in Warranty Coverage');
        System.assertEquals(150, ctrl.benefitLines[0].amount);
        System.assertEquals(-150, ctrl.benefitLines[0].credit,
            'credits print as negatives, as in the preview');
        System.assert(ctrl.getFullyCoveredNote().contains('claim limit'),
            'the note text is shared with the preview: ' + ctrl.getFullyCoveredNote());
    }

    /**
     * The fully-covered note must follow the SAME rule as
     * ClaimPricingService.calculateScenario, which the Manage Estimates preview
     * mirrors:
     *     !isReimbursement && retailRepair > 0 && overLimit <= 0
     * with the repair INCLUDING tax tested against the cap, and shop supplies
     * EXCLUDED because the cap is tested against the repair only.
     *
     * Osama, 2026-10-09: the note showed on the preview and not on the PDF. The
     * controller had invented its own rule, comparing Coverage_Applied__c
     * against Total_Repair_Cost__c. Both figures were wrong for the job: that
     * total includes shop supplies, and coverage is already net of the
     * deductible, so it could essentially never reach the repair plus tax when a
     * deductible applied. The numbers below are his Alternator scenario.
     */
    @IsTest
    static void fullyCoveredFollowsTheSameRuleAsThePreview() {
        Estimate__c est = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        Claim__c claim = [SELECT Id, Application__c FROM Claim__c WHERE Id = :est.Claim__c];
        Application_Package__c pkg = new Application_Package__c(
            Application__c = claim.Application__c, Payment_Status__c = 'Not Paid',
            Per_Claim_Limit__c = 3000, Deductible__c = 100);
        insert pkg;
        claim.Application_Package__c = pkg.Id;
        update claim;

        // Retail repair 960 excluding supplies. 960 x 1.13 = 1,084.80, well
        // inside the 3,000 cap, so this IS fully covered.
        update new Estimate__c(Id = est.Id, Retail_Price__c = 960);
        Work_Order__c covered = new Work_Order__c(
            Claim__c = claim.Id, Estimate__c = est.Id, Tax_Percentage__c = 13);
        insert covered;

        Test.startTest();
        WorkOrderPDFController ctrl = new WorkOrderPDFController(covered.Id);
        Test.stopTest();

        System.assertEquals(true, ctrl.getIsFullyCovered(),
            '960 plus 13% is 1,084.80, inside the 3,000 cap. The old rule compared '
                + 'coverage net of the deductible against a total that included supplies, '
                + 'and so said no.');
        System.assert(ctrl.getFullyCoveredNote().contains('claim limit'),
            'and the note it prints is the preview wording');
    }

    /** The same rule must still say NO once the repair exceeds the cap. */
    @IsTest
    static void notFullyCoveredOnceTheRepairExceedsTheCap() {
        Estimate__c est = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        Claim__c claim = [SELECT Id, Application__c FROM Claim__c WHERE Id = :est.Claim__c];
        Application_Package__c pkg = new Application_Package__c(
            Application__c = claim.Application__c, Payment_Status__c = 'Not Paid',
            Per_Claim_Limit__c = 3000, Deductible__c = 100);
        insert pkg;
        claim.Application_Package__c = pkg.Id;
        update claim;

        // 3,840 x 1.13 = 4,339.20, over the 3,000 cap.
        update new Estimate__c(Id = est.Id, Retail_Price__c = 3840);
        Work_Order__c over = new Work_Order__c(
            Claim__c = claim.Id, Estimate__c = est.Id, Tax_Percentage__c = 13);
        insert over;

        Test.startTest();
        WorkOrderPDFController ctrl = new WorkOrderPDFController(over.Id);
        Test.stopTest();

        System.assertEquals(false, ctrl.getIsFullyCovered(),
            'the tax-inclusive repair is over the cap, so the note must not print');
    }

    /**
     * Osama, 2026-10-09: a shop supply named "Oil & fluids" displayed as
     * "Oil &amp; fluids". Work_Order_Line_Item__c.Description__c is type Html,
     * a RICH TEXT field, and Salesforce HTML-encodes plain text written into
     * one. Service_Repair_Description__c is a plain TextArea that
     * createWorkOrder fills from the SAME source in the same statement, so it
     * carries the identical text uncorrupted.
     *
     * This pins the shared helper every reader now uses. The ampersand in the
     * fixture is the whole point: a name without one would pass either way.
     */
    @IsTest
    static void readableTextComesFromThePlainFieldNotTheRichTextOne() {
        Estimate__c est = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        Work_Order__c wo = new Work_Order__c(
            Claim__c = est.Claim__c, Estimate__c = est.Id, Customer_Name__c = 'Entity Test');
        insert wo;

        // A Part, not a Supply: the part description is carried into the
        // document's repair row verbatim, so the entity would be visible there
        // if any reader went back to the rich text field. The Supplies row
        // replaces its label and would hide the defect.
        Claim_Line_Item__c cli = new Claim_Line_Item__c(
            Claim__c = est.Claim__c, Line_Type__c = 'Part',
            Description__c = 'Oil & fluids', Amount__c = 60, Retail_Amount__c = 60);
        insert cli;

        insert new Work_Order_Line_Item__c(
            Customer_Work_Order__c = wo.Id, Claim_Line_Item__c = cli.Id,
            // exactly what createWorkOrder writes: the same text into both,
            // where only the Html field gets encoded by the platform
            Description__c = 'Oil & fluids',
            Service_Repair_Description__c = 'Oil & fluids',
            Price__c = 60, Retail__c = 60);

        Work_Order_Line_Item__c stored = [
            SELECT Description__c, Service_Repair_Description__c, Claim_Line_Item__r.Description__c
            FROM Work_Order_Line_Item__c WHERE Customer_Work_Order__c = :wo.Id];
        System.assertEquals('Oil &amp; fluids', stored.Description__c,
            'the rich text field really does store the entity; if this ever stops being '
                + 'true the helper can be simplified');
        System.assertEquals('Oil & fluids', stored.Service_Repair_Description__c,
            'while the plain field is clean');

        System.assertEquals('Oil & fluids', ClaimEstimateService.lineDescription(stored),
            'so the shared helper must return the clean text');

        Test.startTest();
        WorkOrderPDFController ctrl = new WorkOrderPDFController(wo.Id);
        Test.stopTest();

        System.assertEquals(1, ctrl.lines.size());
        System.assertEquals('Oil & fluids Replacement (Including Parts and Labour)',
            ctrl.lines[0].description,
            'the document must print the ampersand, not the HTML entity');
    }

    @IsTest
    static void controllerRefusesAnUnknownWorkOrder() {
        Estimate__c est = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);

        Boolean threw = false;
        try {
            new WorkOrderPDFController(est.Id);
        } catch (WorkOrderPDFController.WorkOrderPDFException e) {
            threw = true;
            System.assert(e.getMessage().contains('Work order not found'),
                'and it names the problem: ' + e.getMessage());
        }
        System.assertEquals(true, threw, 'an estimate id is not a work order id');
    }

    @IsTest
    static void previewContextRefusesAnUnknownWorkOrder() {
        String message;
        try {
            WorkOrderPDFService.getPreviewContext(
                TestDataFactory.createEstimateWithClaim('Warranty_Claim', true).Id);
            System.assert(false, 'an estimate id is not a work order id');
        } catch (Exception e) {
            message = e.getMessage();
        }
        System.assert(message != null, 'must throw rather than return an empty screen');
    }

    // ───────────────────────── the document itself ─────────────────────────

    /**
     * Renders the Visualforce page through its controller. This is what catches
     * a merge field pointing at a field that does not exist, which no amount of
     * service testing would find because the service stands the blob in.
     */
    @IsTest
    static void pageRendersWithoutError() {
        Work_Order__c wo = seedWorkOrder();

        Test.startTest();
        PageReference page = Page.WorkOrderPDF;
        page.getParameters().put('id', wo.Id);
        Test.setCurrentPage(page);

        WorkOrderPDFController ctrl = new WorkOrderPDFController(
            new ApexPages.StandardController(wo));
        Test.stopTest();

        System.assertEquals(wo.Id, ctrl.order.Id);
        System.assertEquals(1, ctrl.lines.size(), 'the one line item must reach the document');
        // 'Repair' rather than 'Part': the document collapses parts and labour
        // into a single row the way showOrderWorkSummary does. The underlying
        // Work_Order_Line_Item__c is still a Part and still traceable.
        System.assertEquals('Repair', ctrl.lines[0].lineType);
        System.assertEquals('Engine, reconditioned Replacement (Including Parts and Labour)',
            ctrl.lines[0].description,
            'the line item description wins over the claim line item as the more specific label');
        System.assertEquals(true, ctrl.getHasLines());

        System.assertEquals('2015 BMW 6-Series Gran Coupe', ctrl.getVehicleDisplay(),
            'trim included: the row is labelled Year/Make/Model/Trim');
        System.assert(ctrl.getOdometerDisplay().contains('KM'),
            'the unit comes from the record rather than being assumed: ' + ctrl.getOdometerDisplay());
        System.assertEquals(Date.today(), ctrl.getToday());
    }

    /** A work order with no line items must still produce a document. */
    @IsTest
    static void pageRendersWithNoLineItems() {
        Estimate__c est = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        Work_Order__c bare = new Work_Order__c(
            Claim__c = est.Claim__c, Estimate__c = est.Id, Customer_Name__c = 'No Lines');
        insert bare;

        Test.startTest();
        WorkOrderPDFController ctrl = new WorkOrderPDFController(bare.Id);
        Test.stopTest();

        System.assertEquals(0, ctrl.lines.size());
        System.assertEquals(false, ctrl.getHasLines(),
            'the page renders its "no line items yet" panel from this');
        // 'n/a' rather than blank, matching what showOrderWorkSummary prints
        // for the same missing value. The document mirrors that component.
        System.assertEquals('n/a', ctrl.getVehicleDisplay(), 'no vehicle snapshot, no guessing');
        System.assertEquals('n/a', ctrl.getOdometerDisplay());
        System.assertEquals('n/a', ctrl.getShopDisplay());
    }

    /**
     * The document mirrors showOrderWorkSummary section for section, so the
     * pieces that component computes have to be computed here too. Pins the
     * presentation getters the page relies on.
     */
    @IsTest
    static void documentMirrorsThePreviewPresentation() {
        Work_Order__c wo = seedWorkOrder();

        Test.startTest();
        WorkOrderPDFController ctrl = new WorkOrderPDFController(wo.Id);
        Test.stopTest();

        System.assertEquals('Claim Authorization', ctrl.getTitle(),
            'same title the preview shows for a repair');
        System.assertEquals(true, ctrl.getIsRepair());
        System.assertEquals(false, ctrl.getIsReimbursement());
        System.assert(ctrl.getTaxLabel().startsWith('HST ('),
            'the preview labels the tax row HST (x%): ' + ctrl.getTaxLabel());

        // Credits print as negatives, the way the preview shows them.
        Work_Order__c reread = [
            SELECT Deductable__c, Coverage_Applied__c FROM Work_Order__c WHERE Id = :wo.Id];
        if (reread.Deductable__c != null) {
            System.assertEquals(-reread.Deductable__c, ctrl.getDeductibleCredit(),
                'the deductible row is a credit');
        }
        if (reread.Coverage_Applied__c != null) {
            System.assertEquals(-reread.Coverage_Applied__c, ctrl.getCoverageCredit(),
                'the A-Protect Coverage row is a credit');
        }

        System.assertEquals(1, ctrl.lines.size());
        System.assertEquals(2800, ctrl.lines[0].amount,
            'the Service / Description column shows the retail amount from Price__c');
        System.assertEquals('Engine, reconditioned Replacement (Including Parts and Labour)',
            ctrl.lines[0].description,
            'the document groups parts and labour into one row, exactly as the preview does');
    }

    /**
     * The document's Service / Description rows GROUP the way
     * showOrderWorkSummary does, confirmed by Osama against a screenshot on
     * 2026-10-09: parts and labour collapse into one row, each extended
     * warranty keeps its own, and supplies are one row labelled as the
     * customer's responsibility.
     *
     * Grouping is presentation only. The Work_Order_Line_Item__c records stay
     * one per estimate child, which is what the primary rule requires, and this
     * test asserts BOTH: four underlying rows, three document rows.
     */
    @IsTest
    static void documentGroupsPartsAndLabourTheWayThePreviewDoes() {
        Estimate__c est = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        Work_Order__c wo = new Work_Order__c(
            Claim__c = est.Claim__c, Estimate__c = est.Id, Customer_Name__c = 'Grouping');
        insert wo;

        Map<String, Decimal> seed = new Map<String, Decimal>{
            'Part' => 2000, 'Labour' => 800, 'Supplies' => 200, 'Extended Warranty' => 188.50
        };
        Map<String, String> labels = new Map<String, String>{
            'Part' => 'Engine', 'Labour' => 'Engine R and R',
            'Supplies' => 'Oil and fluids', 'Extended Warranty' => 'Extended Warranty: Engine (12 mo)'
        };
        List<Claim_Line_Item__c> clis = new List<Claim_Line_Item__c>();
        for (String type : seed.keySet()) {
            clis.add(new Claim_Line_Item__c(Claim__c = est.Claim__c, Line_Type__c = type,
                Description__c = labels.get(type), Amount__c = seed.get(type),
                Retail_Amount__c = seed.get(type)));
        }
        insert clis;

        List<Work_Order_Line_Item__c> wls = new List<Work_Order_Line_Item__c>();
        for (Claim_Line_Item__c cli : clis) {
            wls.add(new Work_Order_Line_Item__c(
                Customer_Work_Order__c = wo.Id, Claim_Line_Item__c = cli.Id,
                Description__c = cli.Description__c,
                Price__c = cli.Amount__c, Retail__c = cli.Amount__c));
        }
        insert wls;

        Test.startTest();
        WorkOrderPDFController ctrl = new WorkOrderPDFController(wo.Id);
        Test.stopTest();

        System.assertEquals(4, [SELECT COUNT() FROM Work_Order_Line_Item__c
                                WHERE Customer_Work_Order__c = :wo.Id],
            'the structure keeps one row per estimate child, per the primary rule');
        System.assertEquals(3, ctrl.lines.size(),
            'but the document shows three: repair, the warranty, and supplies');

        System.assertEquals('Engine Replacement (Including Parts and Labour)',
            ctrl.lines[0].description);
        System.assertEquals(2800, ctrl.lines[0].amount, 'parts 2000 plus labour 800');

        System.assertEquals('Extended Warranty: Engine (12 mo)', ctrl.lines[1].description,
            'an extended warranty keeps its own row rather than being folded in');
        System.assertEquals(188.50, ctrl.lines[1].amount);

        System.assertEquals('Shop Supplies (Customer Responsibility)', ctrl.lines[2].description,
            'the preview labels supplies as the customer responsibility line');
        System.assertEquals(200, ctrl.lines[2].amount);
    }
}