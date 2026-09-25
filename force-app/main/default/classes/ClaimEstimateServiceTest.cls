@IsTest
private class ClaimEstimateServiceTest {

    /**
     * Estimate under a real claim, with one Part, one Service and one Shop
     * Supply child - kept only for deleteEstimateRemovesChildrenNotOrphansThem,
     * which specifically tests that deleteEstimate still cleans up any
     * lingering children. createWorkOrder itself no longer reads these
     * (Sep 22 rewrite) - see seedEstimateWithLineData below for that.
     */
    private static Estimate__c seedEstimateWithChildren() {
        Estimate__c created = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        insert new List<SObject>{
            // wholesale (what A-Protect owes) and retail (what the customer is charged) on every line
            new Part__c(Estimate__c = created.Id, Part_Name__c = 'LKQ used engine', Part_Code__c = 'ENG-2010-LKQ',
                        Part_Cost_Wholesale__c = 1300, Price__c = 2500, Repair_Shop__c = created.Repair_Shop__c),
            new Service__c(Estimate__c = created.Id, Service_Repair_Description__c = 'Engine R&R',
                        Repair_Time_Adj__c = 8, Wholesale_Labour_Rate_HR__c = 75, Wholesale__c = 600, Retail__c = 1500,
                        Repair_Shop__c = created.Repair_Shop__c),
            new Shop_Supply__c(Estimate__c = created.Id, Item_Name__c = 'Shop supplies', Cost__c = 150, Price__c = 300,
                        Repair_Shop__c = created.Repair_Shop__c)
        };
        return created;
    }

    /**
     * Estimate under a real claim, with its own scalar pricing fields set
     * directly (Sep 22: createWorkOrder/buildClaimLineItems now read these,
     * not Part__c/Service__c/Shop_Supply__c children). Parts wholesale 1300,
     * labour 8hrs x $75 = 600 wholesale, supplies 150/300. Retail_Price__c
     * (3800) covers parts+labour combined and gets proportionally split by
     * ClaimEstimateService.buildClaimLineItems in the same 1300:600 ratio as
     * the wholesale amounts, landing on exactly 2600/1200 - chosen so the
     * split comes out to whole dollars, not because it's a realistic markup.
     */
    private static Estimate__c seedEstimateWithLineData() {
        Estimate__c created = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        update new Estimate__c(
            Id = created.Id,
            Part_Component__c = 'Engine',
            Part_Code__c = 'ENG-2010-LKQ',
            Parts_Cost__c = 1300,
            Job_Type__c = 'REPLACEMENT',
            Labour_Hours__c = 8,
            Labour_Rate__c = 75,
            Shop_Supplies__c = 150,
            Shop_Supplies_Retail__c = 300,
            Retail_Price__c = 3800
        );
        return created;
    }

    @IsTest
    static void createEstimateDefaultsRateFromShop() {
        Estimate__c seed = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        Repair_Shop__c shop = [SELECT Id FROM Repair_Shop__c WHERE Id = :seed.Repair_Shop__c];
        shop.Labour_Rate_On_File__c = 85;
        update shop;

        Estimate__c e = ClaimEstimateService.createEstimate(seed.Claim__c, shop.Id, 'Aftermarket new engine');

        Estimate__c saved = [SELECT Estimate_Name__c, Labour_Rate__c, Claim__c FROM Estimate__c WHERE Id = :e.Id];
        System.assertEquals('Aftermarket new engine', saved.Estimate_Name__c);
        System.assertEquals(85, saved.Labour_Rate__c, 'rate defaulted from the shop on-file rate');
        System.assertEquals(seed.Claim__c, saved.Claim__c);
    }

    @IsTest
    static void updateEstimateRestampsTotals() {
        Estimate__c created = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        Estimate__c e = [SELECT Id FROM Estimate__c WHERE Id = :created.Id];
        e.Parts_Cost__c = 1500;
        e.Labour_Hours__c = 8; e.Labour_Rate__c = 75; e.Insurance_Amount__c = 120;
        e.Shop_Supplies__c = 150; e.Shop_Supplies_Retail__c = 300; e.Retail_Price__c = 4000;
        e.Deductable__c = 100;

        ClaimPricingService.PricingResult r = ClaimEstimateService.updateEstimate(e, 3000);

        System.assertEquals(2370, r.wsTotal, 'no core charge in the Sep 22 formula');
        System.assertEquals(2370, [SELECT Wholesale_Cost__c FROM Estimate__c WHERE Id = :e.Id].Wholesale_Cost__c,
            'totals stamped onto the record after edit');
    }

    @IsTest
    static void deleteEstimateRemovesChildrenNotOrphansThem() {
        Estimate__c e = seedEstimateWithChildren();
        System.assertEquals(3, countChildren(e.Id));

        Test.startTest();
        ClaimEstimateService.deleteEstimate(e.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Estimate__c WHERE Id = :e.Id]);
        System.assertEquals(0, [SELECT COUNT() FROM Part__c WHERE Estimate__c = null AND Part_Name__c = 'LKQ used engine'],
            'children were deleted, not left orphaned with a null Estimate__c');
        System.assertEquals(0, [SELECT COUNT() FROM Service__c WHERE Service_Repair_Description__c = 'Engine R&R']);
        System.assertEquals(0, [SELECT COUNT() FROM Shop_Supply__c WHERE Item_Name__c = 'Shop supplies']);
    }

    @IsTest
    static void getEstimateDetailsForClaimReturnsFullEditableFields() {
        Estimate__c created = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        Estimate__c e = [SELECT Id FROM Estimate__c WHERE Id = :created.Id];
        e.Parts_Cost__c = 1500; e.Labour_Hours__c = 8; e.Labour_Rate__c = 75;
        e.Estimate_Name__c = 'LKQ used engine';
        update e;

        List<Estimate__c> details = ClaimEstimateService.getEstimateDetailsForClaim(created.Claim__c);

        System.assertEquals(1, details.size());
        System.assertEquals('LKQ used engine', details[0].Estimate_Name__c);
        System.assertEquals(1500, details[0].Parts_Cost__c);
        System.assertEquals(8, details[0].Labour_Hours__c);
        System.assertEquals(75, details[0].Labour_Rate__c);
    }

    @IsTest
    static void getEstimateDetailsForClaimIncludesShopTaxPercentage() {
        // Bug fix (Sep 22, Osama caught it): the Repair Price Scenarios grid's
        // Manage Estimates load never carried the shop's tax percentage onto an
        // existing row, so Customer Pays (+tax) silently showed the pre-tax
        // figure (1400) instead of the taxed one (1582) for anything already
        // saved - only brand-new rows picked up tax, via changing the shop
        // picker. This asserts the query this bug was traced to now returns it.
        Estimate__c created = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        Repair_Shop__c shop = [SELECT Id FROM Repair_Shop__c WHERE Id = :created.Repair_Shop__c];
        shop.Tax_Percentage__c = 13;
        update shop;

        List<Estimate__c> details = ClaimEstimateService.getEstimateDetailsForClaim(created.Claim__c);

        System.assertEquals(1, details.size());
        System.assertEquals(13, details[0].Repair_Shop__r.Tax_Percentage__c);
    }

    @IsTest
    static void selectEstimateClearsSiblingsSelection() {
        Estimate__c first = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        Estimate__c second = ClaimEstimateService.createEstimate(first.Claim__c, first.Repair_Shop__c, 'Second option');

        Test.startTest();
        ClaimEstimateService.selectEstimate(first.Id);
        Test.stopTest();

        System.assertEquals(true,  [SELECT Is_Selected__c FROM Estimate__c WHERE Id = :first.Id].Is_Selected__c);
        System.assertEquals(false, [SELECT Is_Selected__c FROM Estimate__c WHERE Id = :second.Id].Is_Selected__c);

        // Re-selecting the other one flips both, same helper createWorkOrder itself uses.
        ClaimEstimateService.selectEstimate(second.Id);
        System.assertEquals(false, [SELECT Is_Selected__c FROM Estimate__c WHERE Id = :first.Id].Is_Selected__c);
        System.assertEquals(true,  [SELECT Is_Selected__c FROM Estimate__c WHERE Id = :second.Id].Is_Selected__c);
    }

    @IsTest
    static void saveEstimatesInsertsUpdatesDeletesAndSelectsInOneCall() {
        Estimate__c existing = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        Estimate__c toDelete = ClaimEstimateService.createEstimate(existing.Claim__c, existing.Repair_Shop__c, 'To be removed');

        Estimate__c updatePayload = new Estimate__c(
            Id = existing.Id,
            Estimate_Name__c = 'Updated name',
            Repair_Shop__c = existing.Repair_Shop__c,
            Parts_Cost__c = 1500, Labour_Hours__c = 8, Labour_Rate__c = 75,
            Insurance_Amount__c = 120, Shop_Supplies__c = 150, Shop_Supplies_Retail__c = 300,
            Retail_Price__c = 4000, Is_Selected__c = false
        );
        Estimate__c newPayload = new Estimate__c(
            Estimate_Name__c = 'New estimate',
            Repair_Shop__c = existing.Repair_Shop__c,
            Parts_Cost__c = 600, Labour_Hours__c = 5, Labour_Rate__c = 60,
            Retail_Price__c = 2000, Is_Selected__c = true
        );

        Test.startTest();
        ClaimEstimateService.saveEstimates(
            existing.Claim__c,
            new List<Estimate__c>{ updatePayload, newPayload },
            new List<Id>{ toDelete.Id }
        );
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Estimate__c WHERE Id = :toDelete.Id], 'removed estimate deleted');

        Estimate__c updated = [SELECT Estimate_Name__c, Wholesale_Cost__c, Is_Selected__c FROM Estimate__c WHERE Id = :existing.Id];
        System.assertEquals('Updated name', updated.Estimate_Name__c, 'existing row updated in place, not duplicated');
        System.assertEquals(2370, updated.Wholesale_Cost__c, 'totals recomputed for the existing row');
        System.assertEquals(false, updated.Is_Selected__c);

        List<Estimate__c> created = [
            SELECT Estimate_Name__c, Wholesale_Cost__c, Is_Selected__c FROM Estimate__c
            WHERE Claim__c = :existing.Claim__c AND Estimate_Name__c = 'New estimate'
        ];
        System.assertEquals(1, created.size(), 'the no-Id row was inserted as a new estimate');
        System.assertEquals(600 + 5 * 60, created[0].Wholesale_Cost__c, 'totals computed for the newly-inserted row too');
        System.assertEquals(true, created[0].Is_Selected__c, 'the row marked Is_Selected__c=true in the batch wins');
    }

    @IsTest
    static void createWorkOrderGeneratesLinesAndSelectsEstimate() {
        Estimate__c chosen = seedEstimateWithLineData();
        // A sibling on the same claim that must end up NOT selected.
        Estimate__c sibling = ClaimEstimateService.createEstimate(chosen.Claim__c, chosen.Repair_Shop__c, 'Other option');

        Test.startTest();
        ClaimEstimateService.WorkOrderResult r = ClaimEstimateService.createWorkOrder(chosen.Id);
        Test.stopTest();

        System.assertEquals(3, r.claimLineItems, 'one Claim Line Item per Part, Labour, Supplies');
        System.assertEquals(3, r.workOrderLines, 'one Work Order Line Item per Claim Line Item');

        Work_Order__c wo = [SELECT Estimate__c, Claim__c, Repair_Shop__c, Total_Line_Items_Cost__c,
                                   Tax_13__c, Total_Repair_Cost__c, Tax_Percentage__c, Tax_Region__c
                            FROM Work_Order__c WHERE Id = :r.workOrderId];
        System.assertEquals(chosen.Id, wo.Estimate__c, 'existing lookup records which estimate won');
        System.assertEquals(chosen.Claim__c, wo.Claim__c);
        System.assertEquals(chosen.Repair_Shop__c, wo.Repair_Shop__c);
        // The factory shop has neither a Tax Region nor a percentage, so the rate is the final 13 fallback.
        System.assertEquals(13, wo.Tax_Percentage__c, 'tax rate snapshotted onto the work order');
        System.assertEquals(null, wo.Tax_Region__c, 'no region on the factory shop');
        // The work order's own formulas derive from the generated lines' Price__c, which
        // now carries RETAIL, so the work order total is the customer-facing figure.
        // Retail_Price__c (3800, parts+labour combined) is allocated proportionally by
        // wholesale share (1300:600) - 2600 to Part, 1200 to Labour - plus the honest
        // Supplies retail (300): 2600 + 1200 + 300 = 4100.
        System.assertEquals(4100,    wo.Total_Line_Items_Cost__c, 'roll-up of retail: 2600 + 1200 + 300');
        System.assertEquals(533,     wo.Tax_13__c,                '13% of retail');
        System.assertEquals(4633,    wo.Total_Repair_Cost__c,     'retail plus tax: what the customer sees');

        Map<String, Claim_Line_Item__c> byType = new Map<String, Claim_Line_Item__c>();
        for (Claim_Line_Item__c cli : [SELECT Line_Type__c, Role__c, Amount__c, Retail_Amount__c, Hours__c, Rate__c, Part_Code__c, Description__c
                                       FROM Claim_Line_Item__c WHERE Claim__c = :chosen.Claim__c]) {
            byType.put(cli.Line_Type__c, cli);
        }
        System.assertEquals(2600, byType.get('Part').Retail_Amount__c,     'proportional retail split by wholesale share');
        System.assertEquals(1200, byType.get('Labour').Retail_Amount__c);
        System.assertEquals(300,  byType.get('Supplies').Retail_Amount__c, 'supplies keep their own honest retail, no allocation');
        System.assertEquals(1300, byType.get('Part').Amount__c);
        System.assertEquals('Parts Supplier', byType.get('Part').Role__c);
        System.assertEquals('ENG-2010-LKQ', byType.get('Part').Part_Code__c);
        System.assertEquals('Engine', byType.get('Part').Description__c, 'from the estimate\'s own Part_Component__c');
        System.assertEquals(600,  byType.get('Labour').Amount__c);
        System.assertEquals(8,    byType.get('Labour').Hours__c);
        System.assertEquals(75,   byType.get('Labour').Rate__c);
        System.assertEquals('Repair Shop', byType.get('Labour').Role__c);
        System.assertEquals('REPLACEMENT Labour', byType.get('Labour').Description__c, 'from the estimate\'s own Job_Type__c');
        System.assertEquals(150,  byType.get('Supplies').Amount__c);

        // Every work order line links back to a distinct claim line item.
        Set<Id> linkedClaimLines = new Set<Id>();
        for (Work_Order_Line_Item__c wl : [SELECT Claim_Line_Item__c, Claim_Line_Item__r.Line_Type__c, Price__c, Retail__c, Wholesale__c
                                           FROM Work_Order_Line_Item__c WHERE Customer_Work_Order__c = :r.workOrderId]) {
            System.assertNotEquals(null, wl.Claim_Line_Item__c, 'work order line must reference its claim line item');
            Claim_Line_Item__c src = byType.get(wl.Claim_Line_Item__r.Line_Type__c);
            System.assertEquals(src.Retail_Amount__c, wl.Price__c,     'Price__c (rolled up) carries retail');
            System.assertEquals(src.Retail_Amount__c, wl.Retail__c,    'Retail__c carries retail');
            System.assertEquals(src.Amount__c,        wl.Wholesale__c, 'Wholesale__c carries the vendor cost');
            linkedClaimLines.add(wl.Claim_Line_Item__c);
        }
        System.assertEquals(3, linkedClaimLines.size(), 'three distinct claim line items linked, none shared');

        System.assertEquals(true,  [SELECT Is_Selected__c FROM Estimate__c WHERE Id = :chosen.Id].Is_Selected__c);
        System.assertEquals(false, [SELECT Is_Selected__c FROM Estimate__c WHERE Id = :sibling.Id].Is_Selected__c,
            'selecting one estimate clears its sibling on the same claim');
    }

    @IsTest
    static void createWorkOrderForSelectedEstimateUsesTheUseFlaggedOne() {
        // Backs the createWorkOrderAction button (Sep 22) - resolves the
        // claim's Is_Selected__c estimate itself, rather than the LWC
        // needing to know the estimate Id.
        Estimate__c chosen = seedEstimateWithLineData();
        ClaimEstimateService.selectEstimate(chosen.Id);

        Test.startTest();
        ClaimEstimateService.WorkOrderResult r = ClaimEstimateService.createWorkOrderForSelectedEstimate(chosen.Claim__c);
        Test.stopTest();

        Work_Order__c wo = [SELECT Estimate__c FROM Work_Order__c WHERE Id = :r.workOrderId];
        System.assertEquals(chosen.Id, wo.Estimate__c);
    }

    @IsTest
    static void createWorkOrderForSelectedEstimateThrowsWithoutASelection() {
        Estimate__c e = seedEstimateWithLineData(); // never marked selected

        Test.startTest();
        try {
            ClaimEstimateService.createWorkOrderForSelectedEstimate(e.Claim__c);
            System.assert(false, 'expected an exception - no estimate is Is_Selected__c yet');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage().contains('USE'), 'error should point the agent at marking USE first');
        }
        Test.stopTest();
    }

    @IsTest
    static void createWorkOrderStampsTaxFromShopRegionAndFormulaUsesIt() {
        Estimate__c e = seedEstimateWithLineData();
        // A region at a rate other than 13, so the assertion cannot pass via the fallback.
        Tax__c quebec = new Tax__c(Name = 'Test Quebec', GST__c = 5, PST__c = 9.98, Total_Tax_Rate__c = 14.98);
        insert quebec;
        Repair_Shop__c shop = [SELECT Id FROM Repair_Shop__c WHERE Id = :e.Repair_Shop__c];
        shop.Tax_Region__c = quebec.Id;
        update shop;

        Test.startTest();
        ClaimEstimateService.WorkOrderResult r = ClaimEstimateService.createWorkOrder(e.Id);
        Test.stopTest();

        Work_Order__c wo = [SELECT Tax_Region__c, Tax_Percentage__c, Total_Line_Items_Cost__c, Tax_13__c, Total_Repair_Cost__c
                            FROM Work_Order__c WHERE Id = :r.workOrderId];
        System.assertEquals(quebec.Id, wo.Tax_Region__c,      'region stamped from the shop');
        System.assertEquals(14.98,     wo.Tax_Percentage__c,  'percentage snapshotted from the region');
        System.assertEquals(4100,      wo.Total_Line_Items_Cost__c);
        System.assertEquals(614.18,    wo.Tax_13__c,          'formula uses the stamped rate: 4100 x 14.98%');
        System.assertEquals(4714.18,   wo.Total_Repair_Cost__c);
    }

    @IsTest
    static void changingTaxRegionByHandResyncsPercentage() {
        Estimate__c e = seedEstimateWithLineData();
        ClaimEstimateService.WorkOrderResult r = ClaimEstimateService.createWorkOrder(e.Id);
        Tax__c ns = new Tax__c(Name = 'Test Nova Scotia', HST__c = 14, Total_Tax_Rate__c = 14);
        insert ns;

        Work_Order__c wo = new Work_Order__c(Id = r.workOrderId, Tax_Region__c = ns.Id);
        update wo; // the record-triggered flow should re-copy the rate

        Work_Order__c after = [SELECT Tax_Percentage__c FROM Work_Order__c WHERE Id = :r.workOrderId];
        System.assertEquals(14, after.Tax_Percentage__c, 'flow re-synced the percentage from the new region');
    }

    @IsTest
    static void createWorkOrderRefusesDuplicate() {
        Estimate__c e = seedEstimateWithLineData();
        ClaimEstimateService.createWorkOrder(e.Id);
        try {
            ClaimEstimateService.createWorkOrder(e.Id);
            System.assert(false, 'expected an exception on the second work order');
        } catch (AuraHandledException ex) {
            System.assert(true);
        }
        System.assertEquals(1, [SELECT COUNT() FROM Work_Order__c WHERE Estimate__c = :e.Id]);
    }

    @IsTest
    static void createWorkOrderRefusesSecondEstimateOnSameClaim() {
        Estimate__c first = seedEstimateWithLineData();
        ClaimEstimateService.createWorkOrder(first.Id);

        // A different estimate on the SAME claim - the per-estimate check
        // alone would let this through, since this estimate itself has no
        // work order yet.
        Estimate__c second = ClaimEstimateService.createEstimate(first.Claim__c, first.Repair_Shop__c, 'Second option');

        try {
            ClaimEstimateService.createWorkOrder(second.Id);
            System.assert(false, 'expected an exception - claim already has an active work order');
        } catch (AuraHandledException ex) {
            System.assert(true);
        }
        System.assertEquals(1, [SELECT COUNT() FROM Work_Order__c WHERE Claim__c = :first.Claim__c],
            'still only the one work order for the claim');
    }

    @IsTest
    static void createWorkOrderAllowedAfterFirstWorkOrderVoided() {
        Estimate__c first = seedEstimateWithLineData();
        ClaimEstimateService.WorkOrderResult r = ClaimEstimateService.createWorkOrder(first.Id);
        update new Work_Order__c(Id = r.workOrderId, Status__c = 'Voided');

        Estimate__c second = ClaimEstimateService.createEstimate(first.Claim__c, first.Repair_Shop__c, 'Second option');

        Test.startTest();
        ClaimEstimateService.WorkOrderResult r2 = ClaimEstimateService.createWorkOrder(second.Id);
        Test.stopTest();

        System.assertNotEquals(null, r2.workOrderId, 'a Voided work order does not count as active');
        System.assertEquals(2, [SELECT COUNT() FROM Work_Order__c WHERE Claim__c = :first.Claim__c]);
    }

    private static Integer countChildren(Id estimateId) {
        return [SELECT COUNT() FROM Part__c WHERE Estimate__c = :estimateId]
             + [SELECT COUNT() FROM Service__c WHERE Estimate__c = :estimateId]
             + [SELECT COUNT() FROM Shop_Supply__c WHERE Estimate__c = :estimateId];
    }

    // ─────────────── Invoice And Wrap Up: generateInvoicesForWrapUp ───────────────

    @IsTest
    static void wrapUpStatusChangeGeneratesInvoiceMatchingWorkOrder() {
        Estimate__c e = seedEstimateWithLineData();
        ClaimEstimateService.WorkOrderResult r = ClaimEstimateService.createWorkOrder(e.Id);
        // Customer_Pays_With_Tax__c is a stamped calc() output, blank until recalculateAndStamp
        // runs; set it directly so Total_Amount_Due__c has a real, non-zero figure to mirror.
        update new Estimate__c(Id = e.Id, Customer_Pays_With_Tax__c = 339);

        Test.startTest();
        update new Claim__c(Id = e.Claim__c, Claim_Status__c = 'Invoice And Wrap Up');
        Test.stopTest();

        Claim__c claim = [SELECT Application__c FROM Claim__c WHERE Id = :e.Claim__c];
        Invoice__c inv = [SELECT Amount__c, Net_Amount_Due__c, Status__c, Work_Order__c, Application__c, Application_Id__c FROM Invoice__c WHERE Claim__c = :e.Claim__c];
        System.assertEquals(r.workOrderId, inv.Work_Order__c);
        System.assertEquals(claim.Application__c, inv.Application__c, 'stamped from Claim__r.Application__c');
        System.assertNotEquals(null, inv.Application_Id__c, 'Invoice__c\'s own Application_Id__c formula populates once Application__c is set');
        // Two different totals, same pattern as Work_Order__c's own
        // Total_Line_Items_Cost__c (gross) vs Total_Amount_Due__c (net):
        // Amount__c is the DLRS-rolled-up sum of the (gross retail) line items;
        // Net_Amount_Due__c is a simple formula reading Total_Amount_Due__c
        // straight off the work order, independent of the line items.
        System.assertEquals(4100, inv.Amount__c, 'DLRS rollup of the 3 gross-retail lines');
        System.assertEquals(339, inv.Net_Amount_Due__c, 'independent formula, mirrors Work_Order__c.Total_Amount_Due__c');
        System.assertEquals('Due', inv.Status__c);

        List<Invoice_Line_Item__c> lines = [
            SELECT Description__c, Amount__c, Repair_Charge_Amount__c, Work_Order_Line_Item__c,
                   Work_Order_Line_Item__r.Price__c
            FROM Invoice_Line_Item__c WHERE Invoice__c = :inv.Id
        ];
        System.assertEquals(3, lines.size(), 'itemized, one line per work order line (Osama, Sep 21)');
        Set<Id> linkedWoLines = new Set<Id>();
        for (Invoice_Line_Item__c line : lines) {
            System.assertNotEquals(null, line.Work_Order_Line_Item__c);
            System.assertEquals(line.Work_Order_Line_Item__r.Price__c, line.Repair_Charge_Amount__c,
                'writable field carries the real (gross) price from the matching work order line');
            System.assertEquals(line.Repair_Charge_Amount__c, line.Amount__c,
                'Amount__c formula falls back to Repair_Charge_Amount__c with no Application_Package__c');
            linkedWoLines.add(line.Work_Order_Line_Item__c);
        }
        System.assertEquals(3, linkedWoLines.size(), 'three distinct work order lines linked, none shared');
    }

    @IsTest
    static void wrapUpStatusChangeIsIdempotent() {
        Estimate__c e = seedEstimateWithLineData();
        ClaimEstimateService.createWorkOrder(e.Id);

        Test.startTest();
        update new Claim__c(Id = e.Claim__c, Claim_Status__c = 'Invoice And Wrap Up');
        // Move away and back: must not generate a second invoice for the same work order.
        update new Claim__c(Id = e.Claim__c, Claim_Status__c = 'Repairs In Progress');
        update new Claim__c(Id = e.Claim__c, Claim_Status__c = 'Invoice And Wrap Up');
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Invoice__c WHERE Claim__c = :e.Claim__c],
            'no duplicate invoice on re-entering the status');
    }

    @IsTest
    static void wrapUpStatusChangeNoOpsWithoutAnActiveWorkOrder() {
        Account        dealer     = TestDataFactory.createDealer(true);
        Application__c app        = TestDataFactory.createApplication(dealer.Id, true);
        Repair_Shop__c repairShop = TestDataFactory.createRepairShop(true);
        Claim__c       claim      = TestDataFactory.createClaim(app.Id, repairShop.Id, 'Warranty_Claim', true);

        Test.startTest();
        update new Claim__c(Id = claim.Id, Claim_Status__c = 'Invoice And Wrap Up');
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Invoice__c WHERE Claim__c = :claim.Id],
            'nothing to invoice yet, and the status save itself must not fail');
    }

    // ──────────────── Ancillary Benefits (Pass 2) ────────────────

    private class BenefitTestContext {
        Id claimId;
        Id balanceId;
    }

    /**
     * A claim linked to a real Application_Package__c (bare insert, same
     * minimal pattern ClaimPricingServiceTest already uses - Benefit_Balance__c
     * only needs a valid Application_Package__c Id, not full dealer-package/
     * pricing setup), plus one Benefit_Balance__c under it.
     */
    private static BenefitTestContext seedBenefitBalance(Decimal capAmount, String benefitType) {
        Estimate__c created = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        Id balanceId = seedBenefitBalanceForExistingClaim(created.Claim__c, capAmount, benefitType);

        BenefitTestContext ctx = new BenefitTestContext();
        ctx.claimId   = created.Claim__c;
        ctx.balanceId = balanceId;
        return ctx;
    }

    /**
     * Links an already-existing claim to a real Application_Package__c (bare
     * insert, same minimal pattern ClaimPricingServiceTest uses) and adds one
     * Benefit_Balance__c under it - for tests that need the benefit tied to a
     * claim that already has its own Estimate/Work Order, not a fresh one.
     */
    private static Id seedBenefitBalanceForExistingClaim(Id claimId, Decimal capAmount, String benefitType) {
        Claim__c claim = [SELECT Id, Application__c FROM Claim__c WHERE Id = :claimId];

        Application_Package__c pkg = new Application_Package__c(
            Application__c = claim.Application__c, Payment_Status__c = 'Not Paid');
        insert pkg;
        claim.Application_Package__c = pkg.Id;
        update claim;

        Benefit_Balance__c balance = new Benefit_Balance__c(
            Application_Package__c = pkg.Id,
            Benefit_Type__c        = benefitType,
            Cap_Amount__c          = capAmount
        );
        insert balance;
        return balance.Id;
    }

    @IsTest
    static void getBenefitBalancesForClaimIncludesAnyExistingDrawForThisClaim() {
        BenefitTestContext ctx = seedBenefitBalance(500, 'Car Rental');
        insert new Benefit_Usage__c(
            Benefit_Balance__c = ctx.balanceId, Claim__c = ctx.claimId,
            Amount_Used__c = 100, Date__c = Date.today());

        Test.startTest();
        List<ClaimEstimateService.BenefitBalanceRow> rows =
            ClaimEstimateService.getBenefitBalancesForClaim(ctx.claimId);
        Test.stopTest();

        System.assertEquals(1, rows.size());
        ClaimEstimateService.BenefitBalanceRow row = rows[0];
        System.assertEquals('Car Rental', row.benefitType);
        System.assertEquals(500, row.capAmount);
        System.assertEquals(100, row.usedToDate, 'native roll-up from the Benefit_Usage__c just inserted');
        System.assertEquals(400, row.remaining, 'Cap_Amount__c - Used_To_Date__c');
        System.assertNotEquals(null, row.usageId, 'this claim already has its own draw');
        System.assertEquals(100, row.usageAmount);
        System.assertEquals(500, row.availableToUse,
            'remaining(400) + this claim\'s own existing draw(100) - the true room to edit into, not just what\'s left after it');
    }

    @IsTest
    static void getBenefitBalancesForClaimEmptyWhenClaimHasNoApplicationPackage() {
        Estimate__c created = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);

        Test.startTest();
        List<ClaimEstimateService.BenefitBalanceRow> rows =
            ClaimEstimateService.getBenefitBalancesForClaim(created.Claim__c);
        Test.stopTest();

        System.assertEquals(0, rows.size(), 'no Application_Package__c on the claim means no benefits to show, not an error');
    }

    @IsTest
    static void saveBenefitUsageInsertsOneNewDrawPerIncludedBenefit() {
        BenefitTestContext ctx = seedBenefitBalance(500, 'Towing');

        Test.startTest();
        ClaimEstimateService.saveBenefitUsage(ctx.claimId, new List<Benefit_Usage__c>{
            new Benefit_Usage__c(Benefit_Balance__c = ctx.balanceId, Amount_Used__c = 100)
        });
        Test.stopTest();

        List<Benefit_Usage__c> usages = [
            SELECT Claim__c, Amount_Used__c, Date__c FROM Benefit_Usage__c WHERE Benefit_Balance__c = :ctx.balanceId];
        System.assertEquals(1, usages.size());
        System.assertEquals(ctx.claimId, usages[0].Claim__c);
        System.assertEquals(100, usages[0].Amount_Used__c);
        System.assertEquals(Date.today(), usages[0].Date__c, 'defaulted since the LWC does not send one');

        Benefit_Balance__c balance = [SELECT Used_To_Date__c, Remaining__c FROM Benefit_Balance__c WHERE Id = :ctx.balanceId];
        System.assertEquals(100, balance.Used_To_Date__c);
        System.assertEquals(400, balance.Remaining__c);
    }

    @IsTest
    static void saveBenefitUsageUpdatesExistingDrawInPlaceNotDuplicated() {
        BenefitTestContext ctx = seedBenefitBalance(500, 'Roadside Assistance');
        Benefit_Usage__c existing = new Benefit_Usage__c(
            Benefit_Balance__c = ctx.balanceId, Claim__c = ctx.claimId,
            Amount_Used__c = 100, Date__c = Date.today());
        insert existing;

        Test.startTest();
        // Same claim re-saves the screen with a higher amount on its own,
        // already-existing draw - must edit that one row, not insert a second.
        ClaimEstimateService.saveBenefitUsage(ctx.claimId, new List<Benefit_Usage__c>{
            new Benefit_Usage__c(Id = existing.Id, Benefit_Balance__c = ctx.balanceId, Amount_Used__c = 250)
        });
        Test.stopTest();

        List<Benefit_Usage__c> usages = [SELECT Amount_Used__c FROM Benefit_Usage__c WHERE Benefit_Balance__c = :ctx.balanceId];
        System.assertEquals(1, usages.size(), 'the existing draw was updated, not duplicated');
        System.assertEquals(250, usages[0].Amount_Used__c);
        System.assertEquals(250, [SELECT Used_To_Date__c FROM Benefit_Balance__c WHERE Id = :ctx.balanceId].Used_To_Date__c);
    }

    @IsTest
    static void saveBenefitUsageAllowsRaisingAnExistingDrawUpToTheFullCap() {
        // Proves availableToUse adds the row's own existing amount back in:
        // remaining alone (400) would wrongly block raising to the full 500.
        BenefitTestContext ctx = seedBenefitBalance(500, 'Car Rental');
        Benefit_Usage__c existing = new Benefit_Usage__c(
            Benefit_Balance__c = ctx.balanceId, Claim__c = ctx.claimId,
            Amount_Used__c = 100, Date__c = Date.today());
        insert existing;

        Test.startTest();
        ClaimEstimateService.saveBenefitUsage(ctx.claimId, new List<Benefit_Usage__c>{
            new Benefit_Usage__c(Id = existing.Id, Benefit_Balance__c = ctx.balanceId, Amount_Used__c = 500)
        });
        Test.stopTest();

        System.assertEquals(500, [SELECT Amount_Used__c FROM Benefit_Usage__c WHERE Id = :existing.Id].Amount_Used__c);
    }

    @IsTest
    static void saveBenefitUsageRefusesAnAmountOverTheAvailableBalance() {
        BenefitTestContext ctx = seedBenefitBalance(500, 'Trip Interruption');

        Test.startTest();
        try {
            ClaimEstimateService.saveBenefitUsage(ctx.claimId, new List<Benefit_Usage__c>{
                new Benefit_Usage__c(Benefit_Balance__c = ctx.balanceId, Amount_Used__c = 600)
            });
            System.assert(false, 'expected an exception - 600 exceeds the 500 cap with nothing used yet');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage().contains('remaining'), 'error should explain why, not just fail silently');
        }
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Benefit_Usage__c WHERE Benefit_Balance__c = :ctx.balanceId],
            'refused before any DML, not partially saved');
    }

    // ──────────────── Claim__c.Total_Profit__c (benefits-inclusive P&L) ────────────────

    @IsTest
    static void createWorkOrderStampsClaimTotalProfitFromSelectedEstimateWhenNoBenefitsUsed() {
        Estimate__c chosen = seedEstimateWithLineData();
        update new Estimate__c(Id = chosen.Id, Profit_Loss__c = -970);

        Test.startTest();
        ClaimEstimateService.createWorkOrder(chosen.Id);
        Test.stopTest();

        System.assertEquals(-970, [SELECT Total_Profit__c FROM Claim__c WHERE Id = :chosen.Claim__c].Total_Profit__c,
            'no benefits used yet - the claim carries the repair-only P&L straight through');
    }

    @IsTest
    static void saveBenefitUsageUpdatesClaimTotalProfitToReflectBenefitsUsed() {
        Estimate__c chosen = seedEstimateWithLineData();
        update new Estimate__c(Id = chosen.Id, Profit_Loss__c = -970);
        ClaimEstimateService.createWorkOrder(chosen.Id);
        Id balanceId = seedBenefitBalanceForExistingClaim(chosen.Claim__c, 500, 'Car Rental');

        Test.startTest();
        ClaimEstimateService.saveBenefitUsage(chosen.Claim__c, new List<Benefit_Usage__c>{
            new Benefit_Usage__c(Benefit_Balance__c = balanceId, Amount_Used__c = 100)
        });
        Test.stopTest();

        System.assertEquals(-1070, [SELECT Total_Profit__c FROM Claim__c WHERE Id = :chosen.Claim__c].Total_Profit__c,
            'repair-only P&L (-970) minus the $100 benefit used - the worked example agreed with Osama');
    }

    @IsTest
    static void saveBenefitUsageNoOpsClaimTotalProfitWithoutASelectedEstimate() {
        Estimate__c e = seedEstimateWithLineData(); // never marked selected, no work order
        Id balanceId = seedBenefitBalanceForExistingClaim(e.Claim__c, 500, 'Car Rental');

        Test.startTest();
        ClaimEstimateService.saveBenefitUsage(e.Claim__c, new List<Benefit_Usage__c>{
            new Benefit_Usage__c(Benefit_Balance__c = balanceId, Amount_Used__c = 100)
        });
        Test.stopTest();

        System.assertEquals(null, [SELECT Total_Profit__c FROM Claim__c WHERE Id = :e.Claim__c].Total_Profit__c,
            'nothing to base the P&L on yet without a selected estimate - must not throw or stamp a bogus number');
    }
}