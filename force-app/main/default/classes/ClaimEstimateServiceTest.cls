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

    // ──────────────── Estimate -> Part/Service/Shop_Supply child sync (Sep 25) ────────────────

    @IsTest
    static void saveEstimatesCreatesChildRecordsFromScalarFields() {
        Estimate__c seed = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        Estimate__c payload = new Estimate__c(
            Id = seed.Id,
            Repair_Shop__c          = seed.Repair_Shop__c,
            Part_Component__c       = 'Engine',
            Part_Code__c             = 'ENG-1',
            Condition__c              = 'USED',
            Parts_Cost__c             = 1500,
            Retail_Price__c           = 4000,
            Job_Type__c               = 'REPLACEMENT',
            Labour_Hours__c           = 8,
            Labour_Rate__c            = 75,
            Shop_Supplies__c          = 150,
            Shop_Supplies_Retail__c   = 300
        );

        Test.startTest();
        ClaimEstimateService.saveEstimates(seed.Claim__c, new List<Estimate__c>{ payload }, null);
        Test.stopTest();

        Part__c part = [
            SELECT Part_Name__c, Part_Code__c, Part_Type__c, Part_Cost__c, Price__c,
                   Claim__c, Repair_Shop__c, Export_to_Work_Order__c, Quantity__c
            FROM Part__c WHERE Estimate__c = :seed.Id
        ];
        System.assertEquals('Engine', part.Part_Name__c);
        System.assertEquals('ENG-1', part.Part_Code__c);
        System.assertEquals('USED', part.Part_Type__c, 'Condition__c and Part_Type__c share identical value sets');
        System.assertEquals(1500, part.Part_Cost__c);
        System.assertEquals(seed.Claim__c, part.Claim__c);
        System.assertEquals(seed.Repair_Shop__c, part.Repair_Shop__c);
        System.assertEquals(false, part.Export_to_Work_Order__c, 'hard rule: never set true (checkbox defaults false)');
        System.assertEquals(1, part.Quantity__c);

        Service__c service = [
            SELECT Job_Type__c, Time__c, Repair_Time_Adj__c, Wholesale_Labour_Rate_HR__c, Wholesale__c
            FROM Service__c WHERE Estimate__c = :seed.Id
        ];
        System.assertEquals('REPLACEMENT', service.Job_Type__c);
        System.assertEquals('8.00', service.Time__c, 'Service__c.Time__c is Text, not Number - Labour_Hours__c is scale 2');
        System.assertEquals(8, service.Repair_Time_Adj__c);
        System.assertEquals(75, service.Wholesale_Labour_Rate_HR__c);
        System.assertEquals(600, service.Wholesale__c);

        Shop_Supply__c supply = [SELECT Item_Name__c, Cost__c, Price__c FROM Shop_Supply__c WHERE Estimate__c = :seed.Id];
        System.assertEquals('Shop Supplies', supply.Item_Name__c);
        System.assertEquals(150, supply.Cost__c);
        System.assertEquals(300, supply.Price__c);
    }

    @IsTest
    static void saveEstimatesUpsertsNotDuplicatesChildrenOnResave() {
        Estimate__c seed = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        Estimate__c first = new Estimate__c(Id = seed.Id, Parts_Cost__c = 1000, Retail_Price__c = 2000);
        ClaimEstimateService.saveEstimates(seed.Claim__c, new List<Estimate__c>{ first }, null);

        Test.startTest();
        Estimate__c second = new Estimate__c(Id = seed.Id, Parts_Cost__c = 1800, Retail_Price__c = 3000);
        ClaimEstimateService.saveEstimates(seed.Claim__c, new List<Estimate__c>{ second }, null);
        Test.stopTest();

        List<Part__c> parts = [SELECT Part_Cost__c FROM Part__c WHERE Estimate__c = :seed.Id];
        System.assertEquals(1, parts.size(), 'updated in place, not duplicated');
        System.assertEquals(1800, parts[0].Part_Cost__c);
    }

    @IsTest
    static void saveEstimatesDeletesChildWhenAmountZeroedOut() {
        Estimate__c seed = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        Estimate__c withSupplies = new Estimate__c(Id = seed.Id, Shop_Supplies__c = 150, Shop_Supplies_Retail__c = 300);
        ClaimEstimateService.saveEstimates(seed.Claim__c, new List<Estimate__c>{ withSupplies }, null);
        System.assertEquals(1, [SELECT COUNT() FROM Shop_Supply__c WHERE Estimate__c = :seed.Id]);

        Test.startTest();
        Estimate__c zeroed = new Estimate__c(Id = seed.Id, Shop_Supplies__c = 0, Shop_Supplies_Retail__c = 0);
        ClaimEstimateService.saveEstimates(seed.Claim__c, new List<Estimate__c>{ zeroed }, null);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Shop_Supply__c WHERE Estimate__c = :seed.Id],
            'deleted, not left behind as a stray zero-dollar record');
    }

    @IsTest
    static void saveEstimatesSkipsChildCreationWhenAmountIsZero() {
        // TestDataFactory.createEstimate defaults Shop_Supplies__c = 25.00 -
        // zero it explicitly, since syncEstimateChildren re-queries the
        // estimate's real persisted state rather than trusting this payload
        // alone (a deliberate design choice, see its own comment).
        Estimate__c seed = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        Estimate__c blank = new Estimate__c(
            Id = seed.Id,
            Estimate_Name__c = 'No parts needed',
            Parts_Cost__c = 0,
            Labour_Hours__c = 0,
            Shop_Supplies__c = 0,
            Shop_Supplies_Retail__c = 0
        );

        Test.startTest();
        ClaimEstimateService.saveEstimates(seed.Claim__c, new List<Estimate__c>{ blank }, null);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Part__c WHERE Estimate__c = :seed.Id]);
        System.assertEquals(0, [SELECT COUNT() FROM Service__c WHERE Estimate__c = :seed.Id]);
        System.assertEquals(0, [SELECT COUNT() FROM Shop_Supply__c WHERE Estimate__c = :seed.Id]);
    }

    // ──────────────── One-click part ordering (Sep 25) ────────────────

    @IsTest
    static void getOrderablePartsExcludesAlreadyOrderedParts() {
        Estimate__c seed = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        update new Estimate__c(Id = seed.Id, Is_Selected__c = true);
        Part__c part = TestDataFactory.createPart(seed.Id, true);

        List<ClaimEstimateService.OrderableSuggestion> before =
            ClaimEstimateService.getOrderableParts(seed.Claim__c);
        System.assertEquals(1, before.size());
        System.assertEquals(part.Id, before[0].partId);

        Account supplier = TestDataFactory.createSupplierAccount(true);
        Part_Order__c po = TestDataFactory.createPartOrder(seed.Claim__c, supplier.Id, true);
        TestDataFactory.createOrderedPartForPart(po.Id, seed.Claim__c, part.Id, true);

        Test.startTest();
        List<ClaimEstimateService.OrderableSuggestion> after =
            ClaimEstimateService.getOrderableParts(seed.Claim__c);
        Test.stopTest();

        System.assertEquals(0, after.size(), 'already ordered, no longer suggested');
    }

    @IsTest
    static void getOrderablePartsResurfacesPartAfterOrderIsCancelled() {
        Estimate__c seed = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        update new Estimate__c(Id = seed.Id, Is_Selected__c = true);
        Part__c part = TestDataFactory.createPart(seed.Id, true);
        Account supplier = TestDataFactory.createSupplierAccount(true);
        Part_Order__c po = TestDataFactory.createPartOrder(seed.Claim__c, supplier.Id, true);
        Ordered_Part__c op = TestDataFactory.createOrderedPartForPart(po.Id, seed.Claim__c, part.Id, true);
        update new Ordered_Part__c(Id = op.Id, Status__c = 'Cancelled');

        Test.startTest();
        List<ClaimEstimateService.OrderableSuggestion> suggestions =
            ClaimEstimateService.getOrderableParts(seed.Claim__c);
        Test.stopTest();

        System.assertEquals(1, suggestions.size(), 'a cancelled order frees the part back up');
    }

    @IsTest
    static void getOrderablePartsExcludesPartsFromNonSelectedEstimates() {
        Estimate__c selected = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        update new Estimate__c(Id = selected.Id, Is_Selected__c = true);
        Part__c selectedPart = TestDataFactory.createPart(selected.Id, true);

        Estimate__c other = TestDataFactory.createEstimate(selected.Claim__c, selected.Repair_Shop__c, true);
        TestDataFactory.createPart(other.Id, true);

        Test.startTest();
        List<ClaimEstimateService.OrderableSuggestion> suggestions =
            ClaimEstimateService.getOrderableParts(selected.Claim__c);
        Test.stopTest();

        System.assertEquals(1, suggestions.size(), 'only the selected estimate\'s part is suggested');
        System.assertEquals(selectedPart.Id, suggestions[0].partId);
    }

    @IsTest
    static void orderSuggestedPartCreatesPartOrderAndOrderedPartAndLinksWorkOrderLine() {
        Estimate__c chosen = seedEstimateWithLineData();
        // seedEstimateWithLineData's own raw `update` sets the scalar fields directly
        // in the database, not on the in-memory `chosen` it returns - re-query so
        // updateEstimate actually sees them (it reads straight off the object passed
        // in, not a fresh query).
        Estimate__c fresh = [
            SELECT Id, Parts_Cost__c, Retail_Price__c, Labour_Hours__c, Labour_Rate__c,
                   Shop_Supplies__c, Shop_Supplies_Retail__c, Part_Component__c, Part_Code__c,
                   Job_Type__c, Condition__c, Repair_Shop__c
            FROM Estimate__c WHERE Id = :chosen.Id
        ];
        ClaimEstimateService.updateEstimate(fresh, 3000); // triggers syncEstimateChildren
        Account supplier = TestDataFactory.createSupplierAccount(true);
        Part__c part = [SELECT Id, Supplier__c FROM Part__c WHERE Estimate__c = :chosen.Id];
        part.Supplier__c = supplier.Id; // set explicitly - seedEstimateWithLineData never sets Parts_Supplier__c
        update part;

        ClaimEstimateService.WorkOrderResult r = ClaimEstimateService.createWorkOrder(chosen.Id);

        Test.startTest();
        Id orderedPartId = ClaimEstimateService.orderSuggestedPart(chosen.Claim__c, part.Id);
        Test.stopTest();

        Ordered_Part__c op = [SELECT Part__c, Status__c, Part_Order__r.Supplier__c, Part_Order__r.Claim__c
                               FROM Ordered_Part__c WHERE Id = :orderedPartId];
        System.assertEquals(part.Id, op.Part__c);
        System.assertEquals('Ordered', op.Status__c);
        System.assertEquals(part.Supplier__c, op.Part_Order__r.Supplier__c, 'PO supplier defaulted from the part');
        System.assertEquals(chosen.Claim__c, op.Part_Order__r.Claim__c);

        Work_Order_Line_Item__c partLine = [
            SELECT Ordered_Part__c, Ordered_Part_Status__c
            FROM Work_Order_Line_Item__c
            WHERE Customer_Work_Order__c = :r.workOrderId AND Claim_Line_Item__r.Line_Type__c = 'Part'
        ];
        System.assertEquals(orderedPartId, partLine.Ordered_Part__c, 'work order Part line linked to the new order');
        System.assertEquals('Ordered', partLine.Ordered_Part_Status__c, 'live formula reads the linked status');
    }

    @IsTest
    static void orderSuggestedPartNoOpsWorkOrderLinkWhenNoPartLineExists() {
        Estimate__c seed = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        Part__c part = TestDataFactory.createPart(seed.Id, true);
        // No createWorkOrder call at all - no Work_Order_Line_Item__c exists for this claim.

        Test.startTest();
        Id orderedPartId = ClaimEstimateService.orderSuggestedPart(seed.Claim__c, part.Id);
        Test.stopTest();

        System.assertNotEquals(null, orderedPartId, 'still succeeds without a work order to link');
        System.assertEquals(1, [SELECT COUNT() FROM Part_Order__c WHERE Claim__c = :seed.Claim__c]);
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

    /**
     * REWRITTEN TASK-049. This was written on Sep 24 against the legacy
     * pricing path (`updateEstimate` -> `ClaimPricingService.calculate`),
     * where Coverage_Applied__c was PRE-TAX and the expected split was
     * 2071.43 / 828.57. Decision 8 made coverage TAX-INCLUSIVE, and no LWC
     * calls the legacy path any more, so the test now prices through
     * `saveManageEstimates` like the live screen does.
     *
     * Option C from the design, deliberately: 1 part at 1,700 wholesale with
     * a 300 dollar markup, 5 h labour at 140 wholesale and 160 retail, and
     * 160 of supplies marked up to 200. Cap 3,000, deductible 100, tax 13%.
     *
     * The arithmetic this pins down:
     *   retail repair 2,800 -> incl. tax 3,164 -> coverage 2,900 (capped)
     *   coverage converted to pre-tax: 2,900 / 1.13 = 2,566.37
     *   Part takes 2,000/2,800 of that = 1,833.12
     *   Labour absorbs the remainder                = 733.25
     *   customer pays 166.88 + 66.75 = 233.63 pre-tax, x 1.13 = 264.00,
     *   which is exactly repair incl. tax less coverage. That reconciliation
     *   is the real point of the test.
     * Without the pre-tax conversion both lines went NEGATIVE (-71.43, -28.57).
     */
    @IsTest
    static void createWorkOrderSplitsCoverageAcrossLinesByRetailShare() {
        ManageContext ctx = seedManageContext();
        ClaimEstimateService.ManageEstimatesData saved = ClaimEstimateService.saveManageEstimates(
            ctx.claimId, new List<ClaimEstimateService.ScenarioRow>{ optionC(ctx.shopId) }, null, null);
        Id estimateId = saved.scenarios[0].id;

        Test.startTest();
        ClaimEstimateService.WorkOrderResult r = ClaimEstimateService.createWorkOrder(estimateId);
        Test.stopTest();

        Map<String, Work_Order_Line_Item__c> byType = new Map<String, Work_Order_Line_Item__c>();
        for (Work_Order_Line_Item__c wl : [
            SELECT Claim_Line_Item__r.Line_Type__c, Retail__c, Covered_Amount__c, Customer_Pay_Amount__c
            FROM Work_Order_Line_Item__c WHERE Customer_Work_Order__c = :r.workOrderId
        ]) {
            byType.put(wl.Claim_Line_Item__r.Line_Type__c, wl);
        }

        System.assertEquals(2000.00, byType.get('Part').Retail__c, 'its own retail, no proportional allocation');
        System.assertEquals(1833.12, byType.get('Part').Covered_Amount__c);
        System.assertEquals(166.88,  byType.get('Part').Customer_Pay_Amount__c, 'positive, not the old -71.43');

        System.assertEquals(800.00, byType.get('Labour').Retail__c);
        System.assertEquals(733.25, byType.get('Labour').Covered_Amount__c, 'absorbs the rounding remainder');
        System.assertEquals(66.75,  byType.get('Labour').Customer_Pay_Amount__c);

        System.assertEquals(200.00, byType.get('Supplies').Retail__c);
        System.assertEquals(0,      byType.get('Supplies').Covered_Amount__c, 'shop supplies are never covered');
        System.assertEquals(200.00, byType.get('Supplies').Customer_Pay_Amount__c);

        Decimal totalCovered = byType.get('Part').Covered_Amount__c
            + byType.get('Labour').Covered_Amount__c
            + byType.get('Supplies').Covered_Amount__c;
        System.assertEquals(2566.37, totalCovered,
            'sums back to exactly the pre-tax equivalent of Coverage_Applied__c, no rounding drift');

        Decimal customerRepairPreTax = byType.get('Part').Customer_Pay_Amount__c
            + byType.get('Labour').Customer_Pay_Amount__c;
        System.assertEquals(264.00, (customerRepairPreTax * 1.13).setScale(2, RoundingMode.HALF_UP),
            'reconciles to repair incl. tax 3,164.00 less coverage 2,900.00');
    }

    /**
     * Osama, 2026-10-07: the live screen inserted three blank estimates on
     * CL ID - 00054 (E-0053, E-0056, E-0057) from cards that had never been
     * filled in - every scalar null and no child rows. recalculateRollups then
     * stamped a deductible and a negative customer-pays onto them, so they read
     * like real estimates in the related list and the agent saw a blank
     * estimate appear on every save.
     *
     * An untouched card is exactly this payload: the generated placeholder
     * name, the seeded 'In-Network'/'Repair' defaults the LWC applies the
     * moment a card is added, and the one blank labour row it always seeds.
     * None of that is content, so none of it may create an Estimate__c.
     */
    @IsTest
    static void saveSkipsScenarioThatWasNeverFilledIn() {
        ManageContext ctx = seedManageContext();

        ClaimEstimateService.ScenarioRow untouched = new ClaimEstimateService.ScenarioRow();
        untouched.name           = 'Repair Shop 1 - Option A';
        untouched.network        = 'In-Network';
        untouched.claimType      = 'Repair';
        untouched.parts          = new List<ClaimEstimateService.PartRow>();
        untouched.supplies       = new List<ClaimEstimateService.SupplyRow>();
        untouched.reimbursements = new List<ClaimEstimateService.ReimbursementRow>();
        untouched.labour         = new List<ClaimEstimateService.LabourRow>{
            new ClaimEstimateService.LabourRow()
        };

        Test.startTest();
        ClaimEstimateService.ManageEstimatesData saved = ClaimEstimateService.saveManageEstimates(
            ctx.claimId, new List<ClaimEstimateService.ScenarioRow>{ untouched }, null, null);
        Test.stopTest();

        System.assertEquals(0, saved.scenarios.size(),
            'an untouched card must not come back as a saved scenario');
        System.assertEquals(0, [SELECT COUNT() FROM Estimate__c WHERE Claim__c = :ctx.claimId],
            'no blank Estimate__c may be inserted for a card that was never filled in');
    }

    /**
     * The guard must not swing too far the other way: the moment the agent
     * picks a repair shop, that card is real and must save, even though it
     * still has no parts, no labour and only the placeholder name.
     */
    @IsTest
    static void saveKeepsScenarioOnceShopIsChosen() {
        ManageContext ctx = seedManageContext();

        ClaimEstimateService.ScenarioRow started = new ClaimEstimateService.ScenarioRow();
        started.name           = 'Repair Shop 1 - Option A';
        started.network        = 'In-Network';
        started.claimType      = 'Repair';
        started.repairShopId   = ctx.shopId;
        started.parts          = new List<ClaimEstimateService.PartRow>();
        started.supplies       = new List<ClaimEstimateService.SupplyRow>();
        started.reimbursements = new List<ClaimEstimateService.ReimbursementRow>();
        started.labour         = new List<ClaimEstimateService.LabourRow>{
            new ClaimEstimateService.LabourRow()
        };

        Test.startTest();
        ClaimEstimateService.ManageEstimatesData saved = ClaimEstimateService.saveManageEstimates(
            ctx.claimId, new List<ClaimEstimateService.ScenarioRow>{ started }, null, null);
        Test.stopTest();

        System.assertEquals(1, saved.scenarios.size(), 'a card with a shop chosen is real work');
        Estimate__c e = [SELECT Repair_Shop__c, Network__c FROM Estimate__c WHERE Claim__c = :ctx.claimId];
        System.assertEquals(ctx.shopId, e.Repair_Shop__c);
        System.assertEquals('In-Network', e.Network__c, 'the seeded default is written, not left null');
    }

    /**
     * Osama, 2026-10-08: the screen sent a filled-in scenario and Apex received
     * a ScenarioRow with every field null and no child rows. The Aura layer
     * mapping LWC objects onto a custom Apex type was losing it silently, so
     * the LWC now sends JSON and saveManageEstimatesFromJson deserialises it.
     *
     * This is the real regression test for that: the literal JSON below is the
     * shape repairPriceScenarios.handleSave builds, property for property.
     *
     * It has to be spelled out literally, because JSON.deserialize silently
     * IGNORES properties it has no field for rather than throwing. So nothing
     * at runtime would catch the LWC payload and these wrapper classes drifting
     * apart: a renamed property would just arrive null, which is the original
     * bug all over again. Pinning the shape here is the guard. Keep this JSON
     * in step with handleSave whenever either side changes.
     */
    @IsTest
    static void saveFromJsonRoundTripsTheScreenPayload() {
        ManageContext ctx = seedManageContext();

        String json = '[{'
            + '"id":null,"name":"LKQ used engine","repairShopId":"' + ctx.shopId + '",'
            + '"network":"In-Network","claimType":"Repair","taxPercent":13,"deductible":100,'
            + '"isSelected":true,'
            + '"parts":[{"id":null,"name":"Engine","partNumber":"ENG-1","category":"Engine",'
            + '"condition":"RECONDITIONED","supplierId":null,"stockNumber":"SN-1","kms":90000,'
            + '"qty":1,"unitWholesale":1700,"markupType":"Amount","markupValue":300,"coreCharge":0,'
            + '"warrantySource":"Supplier","includedWarranty":true,'
            + '"includedWarrantyCovers":"Parts and Labour","includedWarrantyMonths":12,'
            + '"includedWarrantyKm":20000,"extendedWarranty":false,"extendedWarrantyMonths":null,'
            + '"extendedWarrantyKm":null,"extendedWarrantyCost":null,'
            + '"extendedWarrantyMarkupType":"Percent","extendedWarrantyMarkupValue":null,'
            + '"warrantyNotes":""}],'
            + '"labour":[{"id":null,"description":"Engine R and R","wholesaleHours":5,'
            + '"wholesaleRate":140,"retailHours":5,"retailRate":160,"guideMitchell":5,'
            + '"guideAllData":6}],'
            + '"supplies":[{"id":null,"description":"Oil and fluids","wholesaleCost":160,'
            + '"markupType":"Amount","markupValue":40}],'
            + '"reimbursements":[]}]';

        Test.startTest();
        ClaimEstimateService.ManageEstimatesData saved =
            ClaimEstimateService.saveManageEstimatesFromJson(ctx.claimId, json, null, null);
        Test.stopTest();

        System.assertEquals(0, saved.skippedEmptyScenarios,
            'a filled-in card must never be read as empty');
        System.assertEquals(1, saved.scenarios.size());

        ClaimEstimateService.ScenarioRow r = saved.scenarios[0];
        System.assertEquals('LKQ used engine', r.name, 'the name must survive the JSON hop');
        System.assertEquals(ctx.shopId, r.repairShopId);
        System.assertEquals('In-Network', r.network);
        System.assertEquals('Repair', r.claimType);
        System.assertEquals(13, r.taxPercent);

        System.assertEquals(1, r.parts.size(), 'the part must be saved, not dropped');
        System.assertEquals('Engine', r.parts[0].name);
        System.assertEquals(1, r.labour.size(), 'the labour line must be saved, not dropped');
        System.assertEquals(1, r.supplies.size(), 'the supply line must be saved, not dropped');

        System.assertEquals(1, [SELECT COUNT() FROM Part__c WHERE Estimate__c = :r.id],
            'a real Part__c row, which is what was missing entirely before');
        System.assertEquals(1, [SELECT COUNT() FROM Service__c WHERE Estimate__c = :r.id]);
        System.assertEquals(1, [SELECT COUNT() FROM Shop_Supply__c WHERE Estimate__c = :r.id]);
    }

    /**
     * The parse must name its own failure. Silence here is exactly what let a
     * blank estimate look like a successful save.
     *
     * Malformed JSON, deliberately, not an unknown property: a first version of
     * this test used an unknown property and FAILED, because JSON.deserialize
     * ignores those instead of throwing. Worth knowing, and worth not
     * mis-stating in a comment.
     */
    @IsTest
    static void saveFromJsonNamesABadPayloadRatherThanSavingNothing() {
        ManageContext ctx = seedManageContext();
        String bad = '[{"name":"Option A","taxPercent":';

        String message;
        try {
            ClaimEstimateService.saveManageEstimatesFromJson(ctx.claimId, bad, null, null);
        } catch (Exception ex) {
            message = ex.getMessage();
        }

        System.assert(message != null, 'a payload Apex cannot read must throw, not save nothing');
        System.assert(message.contains('could not read the data the screen sent'),
            'and the message must say so plainly, not "Script-thrown exception": ' + message);
        System.assertEquals(0, [SELECT COUNT() FROM Estimate__c WHERE Claim__c = :ctx.claimId],
            'and nothing may be left behind');
    }

    /**
     * TASK-050. Osama chose a snapshot over live formulas on 2026-10-08: a work
     * order goes to the customer and the repair shop for authorization, so it
     * has to say what was true when it was issued. Every Claim__c source field
     * is itself a formula reaching through Application__r or Vehicle__r, so a
     * live reference would let the other team's edits silently rewrite a
     * document that had already been sent out. That the snapshot cannot drift
     * is structural, because these are plain fields and not formulas.
     *
     * Asserts the mechanism rather than hard-coded names and VINs: whatever the
     * claim's formulas resolve to, the work order must have captured exactly
     * that. That keeps the test honest regardless of what TestDataFactory
     * happens to wire up, and it will not break when the factory changes.
     */
    @IsTest
    static void createWorkOrderSnapshotsTheApplicationCustomerAndVehicle() {
        ManageContext ctx = seedManageContext();
        ClaimEstimateService.ManageEstimatesData saved = ClaimEstimateService.saveManageEstimates(
            ctx.claimId, new List<ClaimEstimateService.ScenarioRow>{ optionC(ctx.shopId) }, null, null);
        Id estimateId = saved.scenarios[0].id;

        Claim__c claim = [
            SELECT Application__r.Name, Customer_Name__c, Customer_Address__c, Customer_Email__c,
                   Customer_Home_Phone__c, Customer_Business_Phone__c,
                   Vehicle_Identification_Number_VIN__c, Vehicle_Year__c, Vehicle_Make__c,
                   Vehicle_Model__c, Vehicle_Trim__c, Current_Odometer__c, Current_Odometer_Unit__c
            FROM Claim__c WHERE Id = :ctx.claimId
        ];

        Test.startTest();
        ClaimEstimateService.WorkOrderResult r = ClaimEstimateService.createWorkOrder(estimateId);
        Test.stopTest();

        Work_Order__c wo = [
            SELECT Application_Number__c, Customer_Name__c, Customer_Address__c, Customer_Phone__c,
                   Customer_Email__c, VIN__c, Vehicle_Year__c, Vehicle_Make__c, Vehicle_Model__c,
                   Vehicle_Trim__c, Odometer_In__c, Odometer_In_Unit__c
            FROM Work_Order__c WHERE Id = :r.workOrderId
        ];

        System.assertEquals(claim.Application__r?.Name, wo.Application_Number__c);
        System.assertEquals(claim.Customer_Name__c, wo.Customer_Name__c);
        System.assertEquals(claim.Customer_Address__c, wo.Customer_Address__c);
        System.assertEquals(claim.Customer_Email__c, wo.Customer_Email__c);
        System.assertEquals(claim.Vehicle_Identification_Number_VIN__c, wo.VIN__c);
        System.assertEquals(claim.Vehicle_Year__c, wo.Vehicle_Year__c);
        System.assertEquals(claim.Vehicle_Make__c, wo.Vehicle_Make__c);
        System.assertEquals(claim.Vehicle_Model__c, wo.Vehicle_Model__c);
        System.assertEquals(claim.Vehicle_Trim__c, wo.Vehicle_Trim__c);
        System.assertEquals(claim.Current_Odometer_Unit__c, wo.Odometer_In_Unit__c,
            'restricted picklist matching the Claim value set, so the stamp cannot invent a unit');
        System.assertEquals(claim.Current_Odometer__c, wo.Odometer_In__c,
            'precision and scale match the Claim source exactly, so the snapshot never rounds it');

        String expectedPhone = String.isNotBlank(claim.Customer_Home_Phone__c)
            ? claim.Customer_Home_Phone__c
            : claim.Customer_Business_Phone__c;
        System.assertEquals(expectedPhone, wo.Customer_Phone__c,
            'home phone is the line the shop should call, business phone is the fallback');
    }

    /**
     * TASK-050. Labour detail was being lost on its way to the work order.
     * Claim_Line_Item__c has a single Hours__c and Rate__c, so routing labour
     * through it could only carry the WHOLESALE pair: the retail rate, the
     * retail hours and both guide times were dropped, and the wholesale hours
     * were written into Repair_Time_Adj__c, which means the ADJUSTED (retail)
     * time on both objects.
     *
     * The wholesale and retail hours are DELIBERATELY DIFFERENT here (5 and 6).
     * With equal hours the old mislabelling was invisible, which is exactly why
     * it survived: optionC uses 5 and 5, so a test built on it would have
     * passed either way.
     */
    @IsTest
    static void createWorkOrderCarriesEveryLabourFieldToTheLine() {
        ManageContext ctx = seedManageContext();

        ClaimEstimateService.LabourRow labour = new ClaimEstimateService.LabourRow();
        labour.description    = 'Engine R and R';
        labour.wholesaleHours = 5;
        labour.wholesaleRate  = 140;
        labour.retailHours    = 6;
        labour.retailRate     = 160;
        labour.guideMitchell  = 5;
        labour.guideAllData   = 7;

        ClaimEstimateService.ScenarioRow s = new ClaimEstimateService.ScenarioRow();
        s.name           = 'Labour detail';
        s.repairShopId   = ctx.shopId;
        s.network        = 'In-Network';
        s.claimType      = 'Repair';
        s.isSelected     = true;
        s.parts          = new List<ClaimEstimateService.PartRow>();
        s.supplies       = new List<ClaimEstimateService.SupplyRow>();
        s.reimbursements = new List<ClaimEstimateService.ReimbursementRow>();
        s.labour         = new List<ClaimEstimateService.LabourRow>{ labour };

        ClaimEstimateService.ManageEstimatesData saved = ClaimEstimateService.saveManageEstimates(
            ctx.claimId, new List<ClaimEstimateService.ScenarioRow>{ s }, null, null);
        Id estimateId = saved.scenarios[0].id;

        Test.startTest();
        ClaimEstimateService.WorkOrderResult r = ClaimEstimateService.createWorkOrder(estimateId);
        Test.stopTest();

        Work_Order_Line_Item__c wl = [
            SELECT Repair_Time_EST__c, Wholesale_Labour_Rate_HR__c,
                   Repair_Time_Adj__c, Retail_Labour_Rate__c,
                   Labour_Guide_Time_Mitchell__c, Labour_Guide_Time_All_Data__c
            FROM Work_Order_Line_Item__c
            WHERE Customer_Work_Order__c = :r.workOrderId
              AND Claim_Line_Item__r.Line_Type__c = 'Labour'
        ];

        System.assertEquals(5, wl.Repair_Time_EST__c,
            'wholesale hours belong in the EST field, which used to be left empty');
        System.assertEquals(6, wl.Repair_Time_Adj__c,
            'retail hours belong in the Adj field, which used to hold the WHOLESALE hours');
        System.assertEquals(140, wl.Wholesale_Labour_Rate_HR__c);
        System.assertEquals(160, wl.Retail_Labour_Rate__c,
            'the retail rate had nowhere to travel through Claim_Line_Item__c and was lost');
        System.assertEquals(5, wl.Labour_Guide_Time_Mitchell__c, 'guide times were lost too');
        System.assertEquals(7, wl.Labour_Guide_Time_All_Data__c);
    }

    /**
     * TASK-050 PRIMARY RULE. The Estimate is the source of truth for the
     * structure, and every downstream line item must be traceable back to the
     * Estimate and to the Estimate CHILD it came from, through
     * Estimate -> Claim Line Item -> Work Order Line Item -> Invoice Line Item.
     *
     * Claim_Line_Item__c used to hold Claim__c, Parts_Supplier__c and
     * Repair_Shop__c only, so the chain broke at its very first hop:
     * Line_Type__c said 'Part' but nothing said WHICH Part__c. Work Order Line
     * Item and Invoice Line Item already chained correctly, which is why
     * repairing this one object restores traceability for the whole workflow.
     *
     * This test walks the chain in the direction a reader would: from the work
     * order line back to the estimate child.
     */
    @IsTest
    static void everyDownstreamLineTracesBackToItsEstimateChild() {
        ManageContext ctx = seedManageContext();
        ClaimEstimateService.ManageEstimatesData saved = ClaimEstimateService.saveManageEstimates(
            ctx.claimId, new List<ClaimEstimateService.ScenarioRow>{ optionC(ctx.shopId) }, null, null);
        Id estimateId = saved.scenarios[0].id;

        Id partId   = [SELECT Id FROM Part__c        WHERE Estimate__c = :estimateId LIMIT 1].Id;
        Id svcId    = [SELECT Id FROM Service__c     WHERE Estimate__c = :estimateId LIMIT 1].Id;
        Id supplyId = [SELECT Id FROM Shop_Supply__c WHERE Estimate__c = :estimateId LIMIT 1].Id;

        Test.startTest();
        ClaimEstimateService.WorkOrderResult r = ClaimEstimateService.createWorkOrder(estimateId);
        Test.stopTest();

        Map<String, Work_Order_Line_Item__c> byType = new Map<String, Work_Order_Line_Item__c>();
        for (Work_Order_Line_Item__c wl : [
            SELECT Claim_Line_Item__r.Line_Type__c,
                   Claim_Line_Item__r.Estimate__c, Claim_Line_Item__r.Part__c,
                   Claim_Line_Item__r.Service__c, Claim_Line_Item__r.Shop_Supply__c
            FROM Work_Order_Line_Item__c
            WHERE Customer_Work_Order__c = :r.workOrderId
        ]) {
            byType.put(wl.Claim_Line_Item__r.Line_Type__c, wl);
        }
        System.assertEquals(3, byType.size(), 'one line per estimate child: part, labour, supplies');

        // Every line traces to the estimate.
        for (String type : byType.keySet()) {
            System.assertEquals(estimateId, byType.get(type).Claim_Line_Item__r.Estimate__c,
                type + ' must trace back to the estimate');
        }

        // And each traces to the specific child it was generated from.
        System.assertEquals(partId, byType.get('Part').Claim_Line_Item__r.Part__c,
            'the Part line must name WHICH Part__c, not merely that it is a part');
        System.assertEquals(svcId, byType.get('Labour').Claim_Line_Item__r.Service__c);
        System.assertEquals(supplyId, byType.get('Supplies').Claim_Line_Item__r.Shop_Supply__c);

        // Cross-contamination check: a labour line must not claim a part.
        System.assertEquals(null, byType.get('Labour').Claim_Line_Item__r.Part__c);
        System.assertEquals(null, byType.get('Supplies').Claim_Line_Item__r.Service__c);
    }

    /**
     * An extended warranty is sold against a part, so its line traces to the
     * same Part__c as the part line beside it. Both must still be separate
     * lines, which is what TASK-049 established.
     */
    @IsTest
    static void extendedWarrantyLineTracesToThePartItWasSoldAgainst() {
        ManageContext ctx = seedManageContext();

        ClaimEstimateService.PartRow part = new ClaimEstimateService.PartRow();
        part.name = 'Engine';
        part.qty = 1;
        part.unitWholesale = 1700;
        part.markupType = 'Amount';
        part.markupValue = 300;
        part.extendedWarranty = true;
        part.extendedWarrantyCost = 145;
        part.extendedWarrantyMarkupType = 'Percent';
        part.extendedWarrantyMarkupValue = 30;
        part.extendedWarrantyMonths = 12;

        ClaimEstimateService.ScenarioRow s = new ClaimEstimateService.ScenarioRow();
        s.name = 'With warranty';
        s.repairShopId = ctx.shopId;
        s.network = 'In-Network';
        s.claimType = 'Repair';
        s.isSelected = true;
        s.parts = new List<ClaimEstimateService.PartRow>{ part };
        s.labour = new List<ClaimEstimateService.LabourRow>();
        s.supplies = new List<ClaimEstimateService.SupplyRow>();
        s.reimbursements = new List<ClaimEstimateService.ReimbursementRow>();

        ClaimEstimateService.ManageEstimatesData saved = ClaimEstimateService.saveManageEstimates(
            ctx.claimId, new List<ClaimEstimateService.ScenarioRow>{ s }, null, null);
        Id estimateId = saved.scenarios[0].id;
        Id partId = [SELECT Id FROM Part__c WHERE Estimate__c = :estimateId LIMIT 1].Id;

        Test.startTest();
        ClaimEstimateService.createWorkOrder(estimateId);
        Test.stopTest();

        List<Claim_Line_Item__c> warranty = [
            SELECT Estimate__c, Part__c FROM Claim_Line_Item__c
            WHERE Estimate__c = :estimateId AND Line_Type__c = 'Extended Warranty'];
        System.assertEquals(1, warranty.size(), 'its own line, per TASK-049');
        System.assertEquals(partId, warranty[0].Part__c,
            'and it traces to the part it was sold against');
        System.assertEquals(estimateId, warranty[0].Estimate__c);
    }

    /** Requirement 9: a purchased extended warranty gets its OWN line, never merged into the part. */
    @IsTest
    static void createWorkOrderGivesTheExtendedWarrantyItsOwnLine() {
        ManageContext ctx = seedManageContext();
        ClaimEstimateService.ScenarioRow s = optionC(ctx.shopId);
        s.parts[0].extendedWarranty = true;
        s.parts[0].extendedWarrantyCost = 145;
        s.parts[0].extendedWarrantyMarkupType = 'Percent';
        s.parts[0].extendedWarrantyMarkupValue = 30;
        s.parts[0].extendedWarrantyMonths = 12;
        s.parts[0].extendedWarrantyKm = 20000;

        ClaimEstimateService.ManageEstimatesData saved = ClaimEstimateService.saveManageEstimates(
            ctx.claimId, new List<ClaimEstimateService.ScenarioRow>{ s }, null, null);

        Test.startTest();
        ClaimEstimateService.WorkOrderResult r = ClaimEstimateService.createWorkOrder(saved.scenarios[0].id);
        Test.stopTest();

        List<Claim_Line_Item__c> warrantyLines = [
            SELECT Description__c, Amount__c, Retail_Amount__c
            FROM Claim_Line_Item__c
            WHERE Claim__c = :ctx.claimId AND Line_Type__c = 'Extended Warranty'
        ];
        System.assertEquals(1, warrantyLines.size(), 'exactly one extended warranty line');
        System.assertEquals(145.00, warrantyLines[0].Amount__c, 'its own wholesale, not merged into the part');
        System.assertEquals(188.50, warrantyLines[0].Retail_Amount__c, '145 plus 30 percent');
        System.assert(warrantyLines[0].Description__c.startsWith('Extended Warranty: Engine'),
            'named after the part it belongs to, got: ' + warrantyLines[0].Description__c);
        System.assert(warrantyLines[0].Description__c.contains('12 mo'),
            'carries its term, got: ' + warrantyLines[0].Description__c);

        System.assertEquals(1, [SELECT COUNT() FROM Claim_Line_Item__c
                                WHERE Claim__c = :ctx.claimId AND Line_Type__c = 'Part'],
            'the part itself is still its own separate line');
    }

    /** Requirement 9: many children produce many lines, not the old hardcoded three. */
    @IsTest
    static void createWorkOrderBuildsOneLinePerChildRatherThanThree() {
        ManageContext ctx = seedManageContext();
        ClaimEstimateService.ScenarioRow s = optionC(ctx.shopId);

        ClaimEstimateService.PartRow gasket = new ClaimEstimateService.PartRow();
        gasket.name = 'Gasket kit';
        gasket.qty = 1;
        gasket.unitWholesale = 120;
        gasket.markupType = 'Percent';
        gasket.markupValue = 35;
        s.parts.add(gasket);

        ClaimEstimateService.SupplyRow rags = new ClaimEstimateService.SupplyRow();
        rags.description = 'Shop rags';
        rags.wholesaleCost = 40;
        rags.markupType = 'Amount';
        rags.markupValue = 10;
        s.supplies.add(rags);

        ClaimEstimateService.ManageEstimatesData saved = ClaimEstimateService.saveManageEstimates(
            ctx.claimId, new List<ClaimEstimateService.ScenarioRow>{ s }, null, null);

        Test.startTest();
        ClaimEstimateService.createWorkOrder(saved.scenarios[0].id);
        Test.stopTest();

        System.assertEquals(2, [SELECT COUNT() FROM Claim_Line_Item__c
                                WHERE Claim__c = :ctx.claimId AND Line_Type__c = 'Part'],
            'two parts, two lines, no longer lumped under the first part name');
        System.assertEquals(2, [SELECT COUNT() FROM Claim_Line_Item__c
                                WHERE Claim__c = :ctx.claimId AND Line_Type__c = 'Supplies'],
            'two supply lines, not one merged Shop Supplies');
        System.assertEquals(1, [SELECT COUNT() FROM Claim_Line_Item__c
                                WHERE Claim__c = :ctx.claimId AND Line_Type__c = 'Labour']);

        Set<String> names = new Set<String>();
        for (Claim_Line_Item__c cli : [SELECT Description__c FROM Claim_Line_Item__c
                                       WHERE Claim__c = :ctx.claimId AND Line_Type__c = 'Part']) {
            names.add(cli.Description__c);
        }
        System.assert(names.contains('Engine') && names.contains('Gasket kit'),
            'each part is named on its own line, got: ' + names);
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

    /**
     * Osama, 2026-10-09: every invoice line this trigger created showed its
     * record id instead of a name. Invoice_Line_Item__c.Name is a TEXT name
     * field, not an auto number, and nothing ever set it.
     *
     * The Name must come from the same source as Description__c so the two can
     * never disagree about one line, and it must carry the SPECIFIC child's
     * name rather than a generic type, because TASK-049 already put that
     * specificity in the data.
     */
    @IsTest
    static void wrapUpInvoiceLinesAreNamedNotLeftBlank() {
        Estimate__c e = seedEstimateWithLineData();
        ClaimEstimateService.createWorkOrder(e.Id);

        Test.startTest();
        update new Claim__c(Id = e.Claim__c, Claim_Status__c = 'Invoice And Wrap Up');
        Test.stopTest();

        List<Invoice_Line_Item__c> lines = [
            SELECT Name, Description__c
            FROM Invoice_Line_Item__c
            WHERE Invoice__r.Claim__c = :e.Claim__c
        ];
        System.assertNotEquals(0, lines.size(), 'the trigger must have produced lines to check');

        for (Invoice_Line_Item__c line : lines) {
            System.assert(String.isNotBlank(line.Name),
                'a blank Name is why these records displayed their record id');
            System.assertEquals(line.Description__c, line.Name,
                'Name and Description come from one source, so they cannot drift apart');
            System.assert(!line.Name.startsWith('a'),
                'and the name is a business name, not an id: ' + line.Name);
        }
    }

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
        }, null);
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

    /**
     * Osama, 2026-10-08: "Ancillary Benefits - Capped per Term is showing two
     * benefits even I uncheck a benefit and save". The editor sends only the
     * CHECKED rows, so an unchecked benefit was absent from the payload and its
     * Benefit_Usage__c row simply survived. Not a display problem: the draw kept
     * consuming the balance and kept crediting the customer. The balance
     * assertions below are the real point of this test.
     */
    @IsTest
    static void saveBenefitUsageRemovesADrawWhenTheBenefitIsUnchecked() {
        BenefitTestContext ctx = seedBenefitBalance(500, 'Car Rental');
        Benefit_Usage__c existing = new Benefit_Usage__c(
            Benefit_Balance__c = ctx.balanceId, Claim__c = ctx.claimId,
            Amount_Used__c = 100, Date__c = Date.today(),
            Counts_Toward_Balance__c = true);
        insert existing;

        Benefit_Balance__c before = [
            SELECT Used_To_Date__c, Remaining__c FROM Benefit_Balance__c WHERE Id = :ctx.balanceId];
        System.assertEquals(100, before.Used_To_Date__c, 'the draw is consuming the balance to begin with');

        Test.startTest();
        // Unchecking the only benefit: nothing included, that one draw removed.
        ClaimEstimateService.saveBenefitUsage(
            ctx.claimId, new List<Benefit_Usage__c>(), new List<Id>{ existing.Id });
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Benefit_Usage__c WHERE Id = :existing.Id],
            'unchecking must actually remove the draw, not leave it behind');

        Benefit_Balance__c after = [
            SELECT Used_To_Date__c, Remaining__c FROM Benefit_Balance__c WHERE Id = :ctx.balanceId];
        System.assertEquals(0, after.Used_To_Date__c, 'and the balance must be given back');
        System.assertEquals(500, after.Remaining__c);
    }

    /**
     * A removal must not reach a draw belonging to some other claim. The
     * `AND Claim__c = :claimId` filter on the delete query in saveBenefitUsage
     * is what enforces that. NOT covered by a test: building a second claim
     * through TestDataFactory trips a duplicate rule on the Account it creates
     * (DUPLICATES_DETECTED), and working around that was not worth more
     * machinery than the one-line filter it would be guarding. If a second
     * claim ever becomes cheap to seed here, this is worth adding.
     */
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
        }, null);
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
        }, null);
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
            }, null);
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
        }, null);
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
        }, null);
        Test.stopTest();

        System.assertEquals(null, [SELECT Total_Profit__c FROM Claim__c WHERE Id = :e.Claim__c].Total_Profit__c,
            'nothing to base the P&L on yet without a selected estimate - must not throw or stamp a bogus number');
    }

    // ──────────────── Work Order detail (createWorkOrderAction detail view) ────────────────

    @IsTest
    static void getActiveWorkOrderDetailsForClaimReturnsNullWithNoActiveWorkOrder() {
        Estimate__c e = seedEstimateWithLineData(); // no work order created yet

        Test.startTest();
        ClaimEstimateService.WorkOrderDetail detail =
            ClaimEstimateService.getActiveWorkOrderDetailsForClaim(e.Claim__c);
        Test.stopTest();

        System.assertEquals(null, detail);
    }

    @IsTest
    static void getActiveWorkOrderDetailsForClaimReturnsHeaderAndLines() {
        Estimate__c e = seedEstimateWithLineData();
        ClaimEstimateService.WorkOrderResult r = ClaimEstimateService.createWorkOrder(e.Id);

        Test.startTest();
        ClaimEstimateService.WorkOrderDetail detail =
            ClaimEstimateService.getActiveWorkOrderDetailsForClaim(e.Claim__c);
        Test.stopTest();

        Work_Order__c wo = [SELECT Deductable__c, Total_Amount_Due__c FROM Work_Order__c WHERE Id = :r.workOrderId];
        System.assertEquals(r.workOrderId, detail.workOrderId);
        System.assertEquals(wo.Deductable__c, detail.deductible);
        System.assertEquals(wo.Total_Amount_Due__c, detail.balanceAmountDue);
        System.assertEquals(3, detail.lines.size(), 'one per Part/Labour/Supplies');
        for (ClaimEstimateService.WorkOrderLineRow row : detail.lines) {
            System.assertNotEquals(null, row.description);
            System.assertNotEquals(null, row.price);
        }
    }

    @IsTest
    static void getActiveWorkOrderDetailsForClaimIgnoresVoidedWorkOrder() {
        Estimate__c first = seedEstimateWithLineData();
        ClaimEstimateService.WorkOrderResult r = ClaimEstimateService.createWorkOrder(first.Id);
        update new Work_Order__c(Id = r.workOrderId, Status__c = 'Voided');

        Test.startTest();
        ClaimEstimateService.WorkOrderDetail detail =
            ClaimEstimateService.getActiveWorkOrderDetailsForClaim(first.Claim__c);
        Test.stopTest();

        System.assertEquals(null, detail, 'a Voided work order does not count as active');
    }

    @IsTest
    static void getActiveWorkOrderDetailsForClaimIncludesSelectedScenarioBreakdown() {
        Estimate__c created = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        Estimate__c e = [SELECT Id FROM Estimate__c WHERE Id = :created.Id];
        e.Part_Component__c    = 'Engine';
        e.Job_Type__c           = 'REPLACEMENT';
        e.Condition__c          = 'USED';
        e.KMs__c                = 85000;
        e.Part_Code__c          = 'ENG-2010-LKQ';
        e.Stock_Number__c       = 'STK-44821';
        e.Parts_Cost__c         = 1500;
        e.Labour_Hours__c       = 8;
        e.Labour_Rate__c        = 75;
        e.Insurance_Amount__c   = 120;
        e.Insurance_Source__c   = 'From Parts Supplier';
        e.Shop_Supplies__c      = 150;
        e.Shop_Supplies_Retail__c = 300;
        e.Retail_Price__c       = 4000;
        e.Deductable__c         = 100;
        update e;

        Application_Package__c pkg = new Application_Package__c(
            Application__c = [SELECT Application__c FROM Claim__c WHERE Id = :created.Claim__c].Application__c,
            Payment_Status__c = 'Not Paid',
            Per_Claim_Limit__c = 3000
        );
        insert pkg;
        update new Claim__c(Id = created.Claim__c, Application_Package__c = pkg.Id);

        ClaimEstimateService.updateEstimate(e, 3000);
        ClaimEstimateService.WorkOrderResult r = ClaimEstimateService.createWorkOrder(e.Id);

        Test.startTest();
        ClaimEstimateService.WorkOrderDetail detail =
            ClaimEstimateService.getActiveWorkOrderDetailsForClaim(created.Claim__c);
        Test.stopTest();

        System.assertEquals('Engine', detail.partComponent);
        System.assertEquals('REPLACEMENT', detail.jobType);
        System.assertEquals('USED', detail.condition);
        System.assertEquals(85000, detail.kms);
        System.assertEquals('ENG-2010-LKQ', detail.partCode);
        System.assertEquals('STK-44821', detail.stockNumber);
        System.assertEquals(8, detail.labourHours);
        System.assertEquals(75, detail.labourRate);
        System.assertEquals('From Parts Supplier', detail.insuranceSource);
        System.assertEquals(3000, detail.capAmount, 'resolved live from the claim\'s Application_Package__c');

        System.assertEquals(4000, detail.retailPrice);
        System.assertEquals(2900, detail.coverageApplied);
        System.assertEquals(1100, detail.customerRepairPortion);
        System.assertEquals(300, detail.shopSuppliesRetail);
        System.assertEquals(1400, detail.customerPaysPreTax);
        System.assertEquals(1500, detail.partsCost);
        System.assertEquals(600, detail.labourCost);
        System.assertEquals(150, detail.shopSuppliesCost);
        System.assertEquals(120, detail.insuranceAmount);
        System.assertEquals(2370, detail.wholesaleCost, 'no core charge in the Sep 22 formula');
        System.assertEquals(0, detail.benefitsUsed, 'no Ancillary Benefits used on this claim');
        System.assertEquals(2370, detail.totalClaimCost, 'wholesale cost plus zero benefits used');
        System.assertEquals(detail.customerPaysWithTax, detail.balanceAmountDue,
            'same field (Total_Amount_Due__c), exposed under both names');
    }

    // ──────────────── Repair Progress (repairProgressTimeline LWC) ────────────────

    @IsTest
    static void getRepairProgressForClaimReturnsNullWithNoActiveWorkOrder() {
        Estimate__c e = seedEstimateWithLineData(); // no work order created yet

        Test.startTest();
        ClaimEstimateService.RepairProgress progress =
            ClaimEstimateService.getRepairProgressForClaim(e.Claim__c);
        Test.stopTest();

        System.assertEquals(null, progress);
    }

    @IsTest
    static void getRepairProgressForClaimReturnsMilestoneAndDates() {
        Estimate__c e = seedEstimateWithLineData();
        ClaimEstimateService.WorkOrderResult r = ClaimEstimateService.createWorkOrder(e.Id);
        update new Work_Order__c(
            Id = r.workOrderId,
            Repair_Milestone__c = 'Repair In Progress',
            Vehicle_Received_Date__c = Date.newInstance(2026, 9, 25),
            Repair_Started_Date__c = Date.newInstance(2026, 9, 29)
        );

        Test.startTest();
        ClaimEstimateService.RepairProgress progress =
            ClaimEstimateService.getRepairProgressForClaim(e.Claim__c);
        Test.stopTest();

        System.assertEquals(r.workOrderId, progress.workOrderId);
        System.assertEquals('Repair In Progress', progress.currentMilestone);
        System.assertEquals(Date.newInstance(2026, 9, 25), progress.vehicleReceivedDate);
        System.assertEquals(Date.newInstance(2026, 9, 29), progress.repairStartedDate);
        System.assertEquals(null, progress.qualityCheckDate);
        System.assertEquals(null, progress.readyForPickupDate);
    }

    @IsTest
    static void getRepairProgressForClaimIgnoresVoidedWorkOrder() {
        Estimate__c first = seedEstimateWithLineData();
        ClaimEstimateService.WorkOrderResult r = ClaimEstimateService.createWorkOrder(first.Id);
        update new Work_Order__c(Id = r.workOrderId, Status__c = 'Voided');

        Test.startTest();
        ClaimEstimateService.RepairProgress progress =
            ClaimEstimateService.getRepairProgressForClaim(first.Claim__c);
        Test.stopTest();

        System.assertEquals(null, progress, 'a Voided work order does not count as active');
    }

    @IsTest
    static void saveRepairProgressUpdatesMilestoneAndStageDate() {
        Estimate__c e = seedEstimateWithLineData();
        ClaimEstimateService.WorkOrderResult r = ClaimEstimateService.createWorkOrder(e.Id);

        Test.startTest();
        ClaimEstimateService.saveRepairProgress(new Work_Order__c(
            Id = r.workOrderId,
            Repair_Milestone__c = 'Quality Check',
            Quality_Check_Date__c = Date.newInstance(2026, 9, 30)
        ));
        Test.stopTest();

        Work_Order__c saved = [SELECT Repair_Milestone__c, Quality_Check_Date__c FROM Work_Order__c WHERE Id = :r.workOrderId];
        System.assertEquals('Quality Check', saved.Repair_Milestone__c);
        System.assertEquals(Date.newInstance(2026, 9, 30), saved.Quality_Check_Date__c);
    }

    // ──────────────── Part Orders (partOrderManager LWC) ────────────────

    @IsTest
    static void getPartOrdersForClaimReturnsEmptyListForClaimWithNoPartOrders() {
        Estimate__c e = seedEstimateWithLineData();

        Test.startTest();
        List<ClaimEstimateService.PartOrderGroup> groups =
            ClaimEstimateService.getPartOrdersForClaim(e.Claim__c);
        Test.stopTest();

        System.assertEquals(0, groups.size());
    }

    @IsTest
    static void getPartOrdersForClaimReturnsGroupsWithNestedLines() {
        Estimate__c e = seedEstimateWithLineData();
        Account supplier = TestDataFactory.createSupplierAccount(true);
        Part_Order__c po1 = TestDataFactory.createPartOrder(e.Claim__c, supplier.Id, true);
        Part_Order__c po2 = TestDataFactory.createPartOrder(e.Claim__c, supplier.Id, true);
        TestDataFactory.createOrderedPart(po1.Id, e.Claim__c, true);
        TestDataFactory.createOrderedPart(po1.Id, e.Claim__c, true);
        TestDataFactory.createOrderedPart(po2.Id, e.Claim__c, true);

        Test.startTest();
        List<ClaimEstimateService.PartOrderGroup> groups =
            ClaimEstimateService.getPartOrdersForClaim(e.Claim__c);
        Test.stopTest();

        System.assertEquals(2, groups.size(), 'a claim can have more than one Part Order');
        Map<Id, ClaimEstimateService.PartOrderGroup> byId = new Map<Id, ClaimEstimateService.PartOrderGroup>();
        for (ClaimEstimateService.PartOrderGroup g : groups) byId.put(g.id, g);
        System.assertEquals(2, byId.get(po1.Id).lines.size());
        System.assertEquals(1, byId.get(po2.Id).lines.size());
        System.assertEquals(supplier.Name, byId.get(po1.Id).supplierName, 'Supplier__r.Name resolves');
    }

    @IsTest
    static void createPartOrderInsertsUnderClaim() {
        Estimate__c e = seedEstimateWithLineData();
        Account supplier = TestDataFactory.createSupplierAccount(true);

        Test.startTest();
        Id newId = ClaimEstimateService.createPartOrder(e.Claim__c, new Part_Order__c(
            Supplier__c = supplier.Id, PO_Number__c = 'PO-9001', Expected_Delivery__c = Date.today().addDays(5)
        ));
        Test.stopTest();

        Part_Order__c saved = [SELECT Claim__c, PO_Number__c FROM Part_Order__c WHERE Id = :newId];
        System.assertEquals(e.Claim__c, saved.Claim__c);
        System.assertEquals('PO-9001', saved.PO_Number__c);
    }

    @IsTest
    static void addOrderedPartSetsPartOrderAndClaimBothLookups() {
        Estimate__c e = seedEstimateWithLineData();
        Account supplier = TestDataFactory.createSupplierAccount(true);
        Part_Order__c po = TestDataFactory.createPartOrder(e.Claim__c, supplier.Id, true);

        Test.startTest();
        ClaimEstimateService.addOrderedPart(po.Id, e.Claim__c, new Ordered_Part__c(
            Part_Name__c = 'Alternator', Quantity__c = 2, Status__c = 'Ordered'
        ));
        Test.stopTest();

        Ordered_Part__c saved = [SELECT Part_Order__c, Claim__c, Part_Name__c FROM Ordered_Part__c WHERE Part_Order__c = :po.Id];
        System.assertEquals(po.Id, saved.Part_Order__c);
        System.assertEquals(e.Claim__c, saved.Claim__c, 'the direct shortcut lookup is also populated');
    }

    @IsTest
    static void saveOrderedPartStatusesUpdatesInPlace() {
        Estimate__c e = seedEstimateWithLineData();
        Account supplier = TestDataFactory.createSupplierAccount(true);
        Part_Order__c po = TestDataFactory.createPartOrder(e.Claim__c, supplier.Id, true);
        Ordered_Part__c op1 = TestDataFactory.createOrderedPart(po.Id, e.Claim__c, true);
        Ordered_Part__c op2 = TestDataFactory.createOrderedPart(po.Id, e.Claim__c, true);

        Test.startTest();
        ClaimEstimateService.saveOrderedPartStatuses(new List<Ordered_Part__c>{
            new Ordered_Part__c(Id = op1.Id, Status__c = 'Received'),
            new Ordered_Part__c(Id = op2.Id, Status__c = 'Backordered')
        });
        Test.stopTest();

        System.assertEquals('Received', [SELECT Status__c FROM Ordered_Part__c WHERE Id = :op1.Id].Status__c);
        System.assertEquals('Backordered', [SELECT Status__c FROM Ordered_Part__c WHERE Id = :op2.Id].Status__c);
        System.assertEquals(2, [SELECT COUNT() FROM Ordered_Part__c WHERE Part_Order__c = :po.Id],
            'updated in place, not duplicated');
    }

    @IsTest
    static void savePartOrderEditsUpdatesPoAndLines() {
        Estimate__c e = seedEstimateWithLineData();
        Account supplier = TestDataFactory.createSupplierAccount(true);
        Part_Order__c po = TestDataFactory.createPartOrder(e.Claim__c, supplier.Id, true);
        Ordered_Part__c op = TestDataFactory.createOrderedPart(po.Id, e.Claim__c, true);

        Test.startTest();
        ClaimEstimateService.savePartOrderEdits(
            new Part_Order__c(Id = po.Id, PO_Number__c = 'PO-9999', Expected_Delivery__c = Date.today().addDays(14)),
            new List<Ordered_Part__c>{
                new Ordered_Part__c(Id = op.Id, Part_Description__c = 'Front bumper cover',
                    Brand__c = 'Aftermarket', Condition__c = 'New')
            }
        );
        Test.stopTest();

        Part_Order__c savedPo = [SELECT PO_Number__c, Expected_Delivery__c FROM Part_Order__c WHERE Id = :po.Id];
        System.assertEquals('PO-9999', savedPo.PO_Number__c);
        System.assertEquals(Date.today().addDays(14), savedPo.Expected_Delivery__c);
        Ordered_Part__c savedOp = [SELECT Part_Description__c, Brand__c, Condition__c FROM Ordered_Part__c WHERE Id = :op.Id];
        System.assertEquals('Front bumper cover', savedOp.Part_Description__c);
        System.assertEquals('Aftermarket', savedOp.Brand__c);
        System.assertEquals('New', savedOp.Condition__c);
    }

    @IsTest
    static void getSupplierAccountsReturnsOnlySupplierAccountRecordType() {
        Account supplier = TestDataFactory.createSupplierAccount(true);
        TestDataFactory.createDealer(true); // a non-supplier Account, must not appear

        Test.startTest();
        List<Account> suppliers = ClaimEstimateService.getSupplierAccounts();
        Test.stopTest();

        System.assertEquals(1, suppliers.size());
        System.assertEquals(supplier.Id, suppliers[0].Id);
    }

    // =====================================================================
    // TASK-047: Manage Estimates
    // =====================================================================
    //
    // The architectural change these cover is that Part__c / Service__c /
    // Shop_Supply__c are now the source of truth, MANY of each per Estimate,
    // where syncEstimateChildren above allowed exactly one of each and
    // derived them from the Estimate's own scalars.
    //
    // The existing tests in this class are deliberately untouched and must
    // keep passing: saveEstimates and ClaimPricingService.calculate were not
    // modified, so the old path still behaves exactly as it always did.
    // Osama's decision 8 (the cap now covers tax) reaches only the new
    // saveManageEstimates path, and decision 10 means no historical record is
    // restated.

    private class ManageContext {
        Id claimId;
        Id shopId;
        Id balanceId;
    }

    /**
     * A claim whose purchased contract carries a real per-claim limit and
     * deductible, plus one Car Rental benefit balance. Cap 3,000 and
     * deductible 100 are the settings every figure in Noelle's design and in
     * ClaimPricingServiceTest is worked against.
     */
    private static ManageContext seedManageContext() {
        Estimate__c seed = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        Claim__c claim = [SELECT Id, Application__c FROM Claim__c WHERE Id = :seed.Claim__c];

        Application_Package__c pkg = new Application_Package__c(
            Application__c      = claim.Application__c,
            Payment_Status__c   = 'Not Paid',
            Per_Claim_Limit__c  = 3000,
            Deductible__c       = 100
        );
        insert pkg;
        claim.Application_Package__c = pkg.Id;
        update claim;

        Benefit_Balance__c balance = new Benefit_Balance__c(
            Application_Package__c = pkg.Id,
            Benefit_Type__c        = 'Car Rental',
            Cap_Amount__c          = 500
        );
        insert balance;

        // The factory estimate is not wanted here: these tests build their
        // scenarios through saveManageEstimates so the whole path is exercised.
        delete seed;

        ManageContext ctx = new ManageContext();
        ctx.claimId   = claim.Id;
        ctx.shopId    = seed.Repair_Shop__c;
        ctx.balanceId = balance.Id;
        return ctx;
    }

    /** Option C from the design: 1 engine at 1,700 + $300, 5 h labour, 160 supplies + $40. */
    private static ClaimEstimateService.ScenarioRow optionC(Id shopId) {
        ClaimEstimateService.PartRow part = new ClaimEstimateService.PartRow();
        part.name = 'Engine';
        part.condition = 'RECONDITIONED';
        part.qty = 1;
        part.unitWholesale = 1700;
        part.markupType = 'Amount';
        part.markupValue = 300;

        ClaimEstimateService.LabourRow labour = new ClaimEstimateService.LabourRow();
        labour.description = 'Engine R and R';
        labour.wholesaleHours = 5;
        labour.wholesaleRate = 140;
        labour.retailHours = 5;
        labour.retailRate = 160;
        labour.guideMitchell = 5;
        labour.guideAllData = 6;

        ClaimEstimateService.SupplyRow supply = new ClaimEstimateService.SupplyRow();
        supply.description = 'Oil and fluids';
        supply.wholesaleCost = 160;
        supply.markupType = 'Amount';
        supply.markupValue = 40;

        ClaimEstimateService.ScenarioRow s = new ClaimEstimateService.ScenarioRow();
        s.name = 'Repair Shop 3 - Option C';
        s.repairShopId = shopId;
        s.network = 'In-Network';
        s.claimType = 'Repair';
        s.taxPercent = 13;
        s.isSelected = true;
        s.parts = new List<ClaimEstimateService.PartRow>{ part };
        s.labour = new List<ClaimEstimateService.LabourRow>{ labour };
        s.supplies = new List<ClaimEstimateService.SupplyRow>{ supply };
        s.reimbursements = new List<ClaimEstimateService.ReimbursementRow>();
        return s;
    }

    private static void approveClaimBenefit(ManageContext ctx, Decimal amount) {
        insert new Benefit_Usage__c(
            Benefit_Balance__c = ctx.balanceId,
            Claim__c           = ctx.claimId,
            Amount_Used__c     = amount,
            Date__c            = Date.today()
        );
    }

    @IsTest
    static void getManageEstimatesDataReturnsTheClaimBarFromTheContract() {
        ManageContext ctx = seedManageContext();

        Test.startTest();
        ClaimEstimateService.ManageEstimatesData d =
            ClaimEstimateService.getManageEstimatesData(ctx.claimId);
        Test.stopTest();

        System.assertEquals(3000, d.cap, 'cap comes from Application_Package__c.Per_Claim_Limit__c, not the agent');
        System.assertEquals(100, d.deductible, 'deductible comes from the contract too (decision 4)');
        System.assertNotEquals(null, d.claimNumber);
        System.assertEquals(1, d.benefits.size(), 'the Car Rental balance is offered');
        System.assertEquals(0, d.scenarios.size(), 'no estimates on this claim yet');
        System.assertNotEquals(null, d.shops, 'the network shop list is returned for the picker');
    }

    /**
     * THE architectural test. One Estimate, three Parts, two Labour lines and
     * two Shop Supplies, which the old one-child-per-type model could not
     * represent at all.
     */
    @IsTest
    static void saveManageEstimatesCreatesManyChildrenOfEachType() {
        ManageContext ctx = seedManageContext();
        ClaimEstimateService.ScenarioRow s = optionC(ctx.shopId);

        ClaimEstimateService.PartRow gasket = new ClaimEstimateService.PartRow();
        gasket.name = 'Gasket kit';
        gasket.qty = 2;
        gasket.unitWholesale = 120;
        gasket.markupType = 'Percent';
        gasket.markupValue = 35;

        ClaimEstimateService.PartRow filter = new ClaimEstimateService.PartRow();
        filter.name = 'Oil filter';
        filter.qty = 1;
        filter.unitWholesale = 40;
        filter.markupType = 'Percent';
        filter.markupValue = 25;

        s.parts.add(gasket);
        s.parts.add(filter);

        ClaimEstimateService.LabourRow diag = new ClaimEstimateService.LabourRow();
        diag.description = 'Diagnostic';
        diag.wholesaleHours = 1;
        diag.wholesaleRate = 100;
        diag.retailHours = 1;
        diag.retailRate = 120;
        s.labour.add(diag);

        ClaimEstimateService.SupplyRow rags = new ClaimEstimateService.SupplyRow();
        rags.description = 'Shop rags';
        rags.wholesaleCost = 40;
        rags.markupType = 'Amount';
        rags.markupValue = 10;
        s.supplies.add(rags);

        Test.startTest();
        ClaimEstimateService.ManageEstimatesData d = ClaimEstimateService.saveManageEstimates(
            ctx.claimId, new List<ClaimEstimateService.ScenarioRow>{ s }, null, null);
        Test.stopTest();

        System.assertEquals(1, d.scenarios.size(), 'one estimate');
        System.assertEquals(3, d.scenarios[0].parts.size(), 'three Part__c children under one Estimate');
        System.assertEquals(2, d.scenarios[0].labour.size(), 'two Service__c children under one Estimate');
        System.assertEquals(2, d.scenarios[0].supplies.size(), 'two Shop_Supply__c children under one Estimate');

        Estimate__c saved = [SELECT Parts_Cost__c, Parts_Retail__c, Labour_Cost__c, Labour_Retail__c
                             FROM Estimate__c WHERE Claim__c = :ctx.claimId LIMIT 1];
        System.assertEquals(1980, saved.Parts_Cost__c, '1700 + (2 x 120) + 40');
        System.assertEquals(2374, saved.Parts_Retail__c, '2000 + (2 x 162) + 50');
        System.assertEquals(800, saved.Labour_Cost__c, '(5 x 140) + (1 x 100)');
        System.assertEquals(920, saved.Labour_Retail__c, '(5 x 160) + (1 x 120)');
    }

    /**
     * Option C end to end, asserted against the exact figures validated
     * against Formulas.dc.html before any of this was written. This is the
     * single strongest check that the children, the rollups and
     * calculateScenario all agree.
     */
    @IsTest
    static void saveManageEstimatesStampsTheFullOptionCScenario() {
        ManageContext ctx = seedManageContext();
        approveClaimBenefit(ctx, 100);

        Test.startTest();
        ClaimEstimateService.saveManageEstimates(
            ctx.claimId, new List<ClaimEstimateService.ScenarioRow>{ optionC(ctx.shopId) }, null, null);
        Test.stopTest();

        Estimate__c e = [
            SELECT Parts_Cost__c, Parts_Retail__c, Labour_Cost__c, Labour_Retail__c,
                   Shop_Supplies__c, Shop_Supplies_Retail__c, Retail_Price__c, Retail_Total__c,
                   Wholesale_Cost__c, Tax_Amount__c, Coverage_Applied__c, Customer_Pays__c,
                   Customer_Pays_With_Tax__c, Profit_Loss__c, Deductable__c,
                   Ancillary_Benefits_Paid__c, A_Protect_P_L_Incl_Benefits__c, Profit_Loss_Incl_Tax__c
            FROM Estimate__c WHERE Claim__c = :ctx.claimId LIMIT 1
        ];

        // existing scalars, same names and same meanings as before TASK-047
        System.assertEquals(1700.00, e.Parts_Cost__c);
        System.assertEquals(2000.00, e.Parts_Retail__c,   'card 1: 1,700 + 300 dollar markup');
        System.assertEquals(700.00,  e.Labour_Cost__c,    'card 4: 5 h x 140');
        System.assertEquals(800.00,  e.Labour_Retail__c,  'card 4: 5 h x 160');
        System.assertEquals(160.00,  e.Shop_Supplies__c);
        System.assertEquals(200.00,  e.Shop_Supplies_Retail__c, 'card 5: 160 + 40');
        System.assertEquals(2800.00, e.Retail_Price__c,   'card 7: retail repair, supplies excluded');
        System.assertEquals(3000.00, e.Retail_Total__c,   'retail including supplies');
        System.assertEquals(2560.00, e.Wholesale_Cost__c, 'card 6: the A-Protect claim cost');
        // Tax_Amount__c is a FORMULA (Customer_Pays_With_Tax__c - Customer_Pays__c)
        // and has been since Sep 22, so it is the tax sitting INSIDE what the
        // customer pays, not the total tax charged across repair and supplies.
        // 390.00 - 345.13 = 44.87, which is exactly calculateScenario's
        // customerTaxAmount and card 10 of the formula reference. The agreement
        // between the platform formula and the Apex model is the real check here.
        System.assertEquals(44.87,  e.Tax_Amount__c,
            'formula: tax inside the customer payment, 390.00 less 345.13');
        System.assertEquals(100.00,  e.Deductable__c,     'falls back to the contract deductible');
        System.assertEquals(2900.00, e.Coverage_Applied__c,
            'card 8 AND decision 8: min(3,164 tax-inclusive repair, 3,000 cap) - 100');
        System.assertEquals(390.00,  e.Customer_Pays_With_Tax__c, 'card 9: 264 + 226 - 100 benefit');
        System.assertEquals(345.13,  e.Customer_Pays__c,  'card 10: 390 / 1.13');

        // TASK-047 additions
        System.assertEquals(100.00,   e.Ancillary_Benefits_Paid__c, 'benefits are now recorded on the Estimate');
        System.assertEquals(-2214.87, e.A_Protect_P_L_Incl_Benefits__c, 'card 11: 345.13 - 2,560');
        System.assertEquals(-2502.80, e.Profit_Loss_Incl_Tax__c, 'card 11: 390 - 2,892.80');
        System.assertEquals(-2126.37, e.Profit_Loss__c,
            'Profit_Loss__c stays the repair-only P&L with no benefit term (decision 9)');
    }

    /**
     * The browser is not trusted on money. A payload claiming a retail price
     * the markup rule would never produce is recomputed server side.
     */
    @IsTest
    static void saveManageEstimatesRecomputesRetailAndIgnoresABadPayload() {
        ManageContext ctx = seedManageContext();
        ClaimEstimateService.ScenarioRow s = optionC(ctx.shopId);
        s.parts[0].unitRetail = 999999;          // tampered or stale
        s.supplies[0].retailPrice = 1;

        Test.startTest();
        ClaimEstimateService.saveManageEstimates(
            ctx.claimId, new List<ClaimEstimateService.ScenarioRow>{ s }, null, null);
        Test.stopTest();

        Part__c p = [SELECT Price__c FROM Part__c WHERE Estimate__r.Claim__c = :ctx.claimId LIMIT 1];
        Shop_Supply__c x = [SELECT Price__c FROM Shop_Supply__c WHERE Estimate__r.Claim__c = :ctx.claimId LIMIT 1];
        System.assertEquals(2000, p.Price__c, 'recomputed from 1,700 + 300, not taken from the payload');
        System.assertEquals(200, x.Price__c, 'recomputed from 160 + 40, not taken from the payload');
    }

    /** Card 3: only the ticked optional extension costs anything. */
    @IsTest
    static void extendedWarrantyCountsOnlyWhenTicked() {
        ManageContext ctx = seedManageContext();
        ClaimEstimateService.ScenarioRow s = optionC(ctx.shopId);
        s.parts[0].extendedWarrantyCost = 145;
        s.parts[0].extendedWarrantyMarkupType = 'Percent';
        s.parts[0].extendedWarrantyMarkupValue = 30;
        s.parts[0].extendedWarranty = false;     // priced but not taken

        Test.startTest();
        ClaimEstimateService.saveManageEstimates(
            ctx.claimId, new List<ClaimEstimateService.ScenarioRow>{ s }, null, null);
        Test.stopTest();

        Estimate__c e = [SELECT Extended_Warranty_Cost__c, Extended_Warranty_Retail__c, Wholesale_Cost__c
                         FROM Estimate__c WHERE Claim__c = :ctx.claimId LIMIT 1];
        System.assertEquals(0, e.Extended_Warranty_Cost__c, 'an untaken extension adds nothing');
        System.assertEquals(0, e.Extended_Warranty_Retail__c);
        System.assertEquals(2560, e.Wholesale_Cost__c, 'the claim cost is unchanged by an untaken extension');
    }

    /** Card 2: a core charge is reported but never enters a total or the P&L. */
    @IsTest
    static void coreChargeIsRolledUpButExcludedFromTotalsAndProfit() {
        ManageContext ctx = seedManageContext();
        ClaimEstimateService.ScenarioRow s = optionC(ctx.shopId);
        s.parts[0].coreCharge = 400;

        Test.startTest();
        ClaimEstimateService.saveManageEstimates(
            ctx.claimId, new List<ClaimEstimateService.ScenarioRow>{ s }, null, null);
        Test.stopTest();

        Estimate__c e = [SELECT Core_Charge__c, Wholesale_Cost__c, Parts_Cost__c, Profit_Loss__c
                         FROM Estimate__c WHERE Claim__c = :ctx.claimId LIMIT 1];
        System.assertEquals(400, e.Core_Charge__c, 'reported for the record');
        System.assertEquals(1700, e.Parts_Cost__c, 'and left out of the parts total');
        System.assertEquals(2560, e.Wholesale_Cost__c, 'and left out of the claim cost');
        System.assertEquals(-2126.37, e.Profit_Loss__c, 'and left out of the P&L');
    }

    /** Removing a line in the UI actually deletes the record, not just blanks it. */
    @IsTest
    static void saveManageEstimatesDeletesRemovedChildren() {
        ManageContext ctx = seedManageContext();
        ClaimEstimateService.ManageEstimatesData first = ClaimEstimateService.saveManageEstimates(
            ctx.claimId, new List<ClaimEstimateService.ScenarioRow>{ optionC(ctx.shopId) }, null, null);

        ClaimEstimateService.ScenarioRow s = first.scenarios[0];
        Id doomedSupplyId = s.supplies[0].id;
        s.supplies = new List<ClaimEstimateService.SupplyRow>();

        Test.startTest();
        ClaimEstimateService.saveManageEstimates(
            ctx.claimId, new List<ClaimEstimateService.ScenarioRow>{ s },
            null, new List<Id>{ doomedSupplyId });
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Shop_Supply__c WHERE Id = :doomedSupplyId],
            'the removed supply is deleted, not orphaned');
        Estimate__c e = [SELECT Shop_Supplies__c, Shop_Supplies_Retail__c
                         FROM Estimate__c WHERE Claim__c = :ctx.claimId LIMIT 1];
        System.assertEquals(0, e.Shop_Supplies__c, 'and the rollup drops with it');
        System.assertEquals(0, e.Shop_Supplies_Retail__c);
    }

    /** Card 15: no repair, no deductible, no supplies, customer pays nothing. */
    @IsTest
    static void reimbursementScenarioStoresItsLinesAgainstTheEstimate() {
        ManageContext ctx = seedManageContext();

        ClaimEstimateService.ReimbursementRow line = new ClaimEstimateService.ReimbursementRow();
        line.benefitBalanceId = ctx.balanceId;
        line.receiptAmount = 120;

        ClaimEstimateService.ScenarioRow s = new ClaimEstimateService.ScenarioRow();
        s.name = 'Car rental reimbursement';
        s.claimType = 'Reimbursement Only';
        s.taxPercent = 13;
        s.isSelected = true;
        s.parts = new List<ClaimEstimateService.PartRow>();
        s.labour = new List<ClaimEstimateService.LabourRow>();
        s.supplies = new List<ClaimEstimateService.SupplyRow>();
        s.reimbursements = new List<ClaimEstimateService.ReimbursementRow>{ line };

        Test.startTest();
        ClaimEstimateService.saveManageEstimates(
            ctx.claimId, new List<ClaimEstimateService.ScenarioRow>{ s }, null, null);
        Test.stopTest();

        Estimate__c e = [SELECT Reimbursement_Total__c, Customer_Pays_With_Tax__c, Coverage_Applied__c,
                                A_Protect_P_L_Incl_Benefits__c
                         FROM Estimate__c WHERE Claim__c = :ctx.claimId LIMIT 1];
        System.assertEquals(120, e.Reimbursement_Total__c);
        System.assertEquals(0, e.Customer_Pays_With_Tax__c, 'the customer pays nothing on a reimbursement');
        System.assertEquals(0, e.Coverage_Applied__c, 'no repair, so no coverage applies');
        System.assertEquals(-120, e.A_Protect_P_L_Incl_Benefits__c, 'A-Protect is out the reimbursement');

        Benefit_Usage__c u = [SELECT Estimate__c, Claim__c, Amount_Used__c, Counts_Toward_Balance__c
                              FROM Benefit_Usage__c LIMIT 1];
        System.assertNotEquals(null, u.Estimate__c,
            'a reimbursement line is scoped to its own scenario, not to the claim as a whole');
        System.assertEquals(true, u.Counts_Toward_Balance__c,
            'this scenario IS the one marked Use, so its receipt does consume the balance');

        Benefit_Balance__c bal = [SELECT Used_To_Date__c, Remaining__c
                                  FROM Benefit_Balance__c WHERE Id = :ctx.balanceId];
        System.assertEquals(120, bal.Used_To_Date__c);
        System.assertEquals(380, bal.Remaining__c, '500 cap less the 120 approved');
    }

    /** TASK-051: How you will be paid is saved with the scenario and read back. */
    @IsTest
    static void reimbursementScenarioRoundTripsItsPaymentDetails() {
        ManageContext ctx = seedManageContext();

        ClaimEstimateService.ReimbursementRow line = new ClaimEstimateService.ReimbursementRow();
        line.benefitBalanceId = ctx.balanceId;
        line.receiptAmount = 120;

        ClaimEstimateService.ScenarioRow s = new ClaimEstimateService.ScenarioRow();
        s.name = 'Car rental reimbursement';
        s.claimType = 'Reimbursement Only';
        s.isSelected = true;
        s.paymentMethod = 'Interac e-Transfer to the e-mail above';
        s.expectedPaymentDate = Date.newInstance(2026, 10, 27);
        s.parts = new List<ClaimEstimateService.PartRow>();
        s.labour = new List<ClaimEstimateService.LabourRow>();
        s.supplies = new List<ClaimEstimateService.SupplyRow>();
        s.reimbursements = new List<ClaimEstimateService.ReimbursementRow>{ line };

        Test.startTest();
        ClaimEstimateService.ManageEstimatesData d = ClaimEstimateService.saveManageEstimates(
            ctx.claimId, new List<ClaimEstimateService.ScenarioRow>{ s }, null, null);
        Test.stopTest();

        ClaimEstimateService.ScenarioRow back = d.scenarios[0];
        System.assertEquals('Interac e-Transfer to the e-mail above', back.paymentMethod);
        System.assertEquals(Date.newInstance(2026, 10, 27), back.expectedPaymentDate);

        List<String> values = new List<String>();
        for (ClaimEstimateService.ValueOption o : d.paymentMethodOptions) values.add(o.value);
        System.assertEquals(new List<String>{
            'Cheque mailed to the address above',
            'Interac e-Transfer to the e-mail above',
            'Direct deposit (banking details on file)'
        }, values, 'options come from the picklist, in the reference order');
    }

    /**
     * TASK-051. The CL ID - 00054 shape that printed 305 on CWO-0044: a
     * claim-level Car Rental draw of 100 on the same balance as the chosen
     * reimbursement scenario's own 120 receipt. Saves and then a work order.
     */
    private static Id seedChosenReimbursement(ManageContext ctx, Decimal receipt) {
        insert new Benefit_Usage__c(
            Benefit_Balance__c = ctx.balanceId, Claim__c = ctx.claimId, Amount_Used__c = 100,
            Date__c = Date.today(), Counts_Toward_Balance__c = true);

        ClaimEstimateService.ReimbursementRow line = new ClaimEstimateService.ReimbursementRow();
        line.benefitBalanceId = ctx.balanceId;
        line.receiptAmount = receipt;

        ClaimEstimateService.ScenarioRow s = new ClaimEstimateService.ScenarioRow();
        s.name = 'Car rental reimbursement';
        s.claimType = 'Reimbursement Only';
        s.isSelected = true;
        s.paymentMethod = 'Cheque mailed to the address above';
        s.expectedPaymentDate = Date.newInstance(2026, 10, 27);
        s.parts = new List<ClaimEstimateService.PartRow>();
        s.labour = new List<ClaimEstimateService.LabourRow>();
        s.supplies = new List<ClaimEstimateService.SupplyRow>();
        s.reimbursements = new List<ClaimEstimateService.ReimbursementRow>{ line };

        return ClaimEstimateService.saveManageEstimates(
            ctx.claimId, new List<ClaimEstimateService.ScenarioRow>{ s }, null, null).scenarios[0].id;
    }

    /**
     * Left on term is the term's real balance after this approval, 500 less
     * the 100 claim draw less the 120 receipt. The old LWC figure subtracted
     * the scenario's own saved receipt twice and added the claim draw back.
     */
    @IsTest
    static void approvedReimbursementLeavesTheTrueBalanceOnTheTerm() {
        ManageContext ctx = seedManageContext();
        Id estimateId = seedChosenReimbursement(ctx, 120);

        Test.startTest();
        List<ClaimEstimateService.ApprovedReimbursement> lines =
            ClaimEstimateService.getApprovedReimbursements(new Set<Id>{ estimateId }).get(estimateId);
        Test.stopTest();

        System.assertEquals(1, lines.size(), 'only the scenario receipt, never the claim-level draw');
        System.assertEquals(120, lines[0].receipts);
        System.assertEquals(120, lines[0].approved);
        System.assertEquals(280, lines[0].leftOnTerm, '500 - 100 claim draw - 120 receipt');
        System.assertEquals(0, lines[0].over);

        Claim__c claim = [SELECT Total_Benefits_Used__c FROM Claim__c WHERE Id = :ctx.claimId];
        System.assertEquals(120, claim.Total_Benefits_Used__c,
            'a chosen reimbursement pays its receipts only; the 100 claim draw is for repair scenarios');
    }

    /** A receipt over what the term has left is saved capped, as the preview shows it. */
    @IsTest
    static void receiptOverTheTermIsApprovedOnlyUpToWhatIsLeft() {
        ManageContext ctx = seedManageContext();

        Test.startTest();
        Id estimateId = seedChosenReimbursement(ctx, 450);
        Test.stopTest();

        ClaimEstimateService.ApprovedReimbursement a =
            ClaimEstimateService.getApprovedReimbursements(new Set<Id>{ estimateId }).get(estimateId)[0];
        System.assertEquals(400, a.approved, '500 cap less the 100 claim draw');
        System.assertEquals(50, a.over);
        System.assertEquals(0, a.leftOnTerm);

        Estimate__c e = [SELECT Reimbursement_Total__c FROM Estimate__c WHERE Id = :estimateId];
        System.assertEquals(400, e.Reimbursement_Total__c,
            'the saved total is the approved figure, not the raw 450 receipt');
    }

    /**
     * The work order for a reimbursement: payment snapshot stamped, one
     * Reimbursement claim line item payable to the Customer, no work order
     * line items, and Wrap Up raises an empty $0 invoice (Osama, 2026-10-13).
     */
    @IsTest
    static void reimbursementWorkOrderRecordsThePayoutWithAnEmptyInvoice() {
        ManageContext ctx = seedManageContext();
        Id estimateId = seedChosenReimbursement(ctx, 120);

        Test.startTest();
        ClaimEstimateService.WorkOrderResult r = ClaimEstimateService.createWorkOrder(estimateId);
        update new Claim__c(Id = ctx.claimId, Claim_Status__c = 'Invoice And Wrap Up');
        Test.stopTest();

        Work_Order__c wo = [
            SELECT Reimbursement_Payment_Method__c, Reimbursement_Expected_Payment_Date__c, Benefits_Used__c,
                   (SELECT Id FROM Customer_Work_Order_Line_Items__r)
            FROM Work_Order__c WHERE Id = :r.workOrderId
        ];
        System.assertEquals('Cheque mailed to the address above', wo.Reimbursement_Payment_Method__c);
        System.assertEquals(Date.newInstance(2026, 10, 27), wo.Reimbursement_Expected_Payment_Date__c);
        System.assertEquals(120, wo.Benefits_Used__c, 'not 220: the claim draw does not apply');
        System.assertEquals(0, wo.Customer_Work_Order_Line_Items__r.size(),
            'no repair work, so nothing the customer is charged for');

        List<Claim_Line_Item__c> cli = [
            SELECT Line_Type__c, Role__c, Description__c, Amount__c, Estimate__c
            FROM Claim_Line_Item__c WHERE Claim__c = :ctx.claimId
        ];
        System.assertEquals(1, cli.size());
        System.assertEquals('Reimbursement', cli[0].Line_Type__c);
        System.assertEquals('Customer', cli[0].Role__c);
        System.assertEquals('Car Rental reimbursement', cli[0].Description__c);
        System.assertEquals(120, cli[0].Amount__c);
        System.assertEquals(estimateId, cli[0].Estimate__c);
        System.assertEquals(1, r.claimLineItems);

        List<Invoice__c> invoices = [
            SELECT Net_Amount_Due__c, (SELECT Id FROM Invoice_Line_Items__r)
            FROM Invoice__c WHERE Claim__c = :ctx.claimId
        ];
        System.assertEquals(1, invoices.size(), 'Wrap Up still closes the claim with an invoice');
        System.assertEquals(0, invoices[0].Invoice_Line_Items__r.size(),
            'no work order lines, so no invoice lines');
        System.assertEquals(0, invoices[0].Net_Amount_Due__c, 'the customer owes nothing');
    }

    /** TASK-051: payment details mean nothing on a repair, so they are not kept. */
    @IsTest
    static void repairScenarioDoesNotKeepPaymentDetails() {
        ManageContext ctx = seedManageContext();

        ClaimEstimateService.ScenarioRow s = new ClaimEstimateService.ScenarioRow();
        s.name = 'Alternator replacement';
        s.claimType = 'Repair';
        s.paymentMethod = 'Cheque mailed to the address above';
        s.expectedPaymentDate = Date.newInstance(2026, 10, 27);
        s.parts = new List<ClaimEstimateService.PartRow>();
        s.labour = new List<ClaimEstimateService.LabourRow>();
        s.supplies = new List<ClaimEstimateService.SupplyRow>();
        s.reimbursements = new List<ClaimEstimateService.ReimbursementRow>();

        Test.startTest();
        ClaimEstimateService.saveManageEstimates(
            ctx.claimId, new List<ClaimEstimateService.ScenarioRow>{ s }, null, null);
        Test.stopTest();

        Estimate__c e = [SELECT Reimbursement_Payment_Method__c, Reimbursement_Expected_Payment_Date__c
                         FROM Estimate__c WHERE Claim__c = :ctx.claimId LIMIT 1];
        System.assertEquals(null, e.Reimbursement_Payment_Method__c);
        System.assertEquals(null, e.Reimbursement_Expected_Payment_Date__c);
    }

    /**
     * Regression for the leak found writing these tests: a receipt typed into
     * a competing scenario that was never marked Use must be recorded without
     * eating the customer's remaining benefit for the term. Pricing two
     * reimbursement options used to drain the balance by both.
     */
    @IsTest
    static void unchosenReimbursementIsRecordedWithoutConsumingTheBalance() {
        ManageContext ctx = seedManageContext();

        ClaimEstimateService.ReimbursementRow chosenLine = new ClaimEstimateService.ReimbursementRow();
        chosenLine.benefitBalanceId = ctx.balanceId;
        chosenLine.receiptAmount = 120;

        ClaimEstimateService.ReimbursementRow rejectedLine = new ClaimEstimateService.ReimbursementRow();
        rejectedLine.benefitBalanceId = ctx.balanceId;
        rejectedLine.receiptAmount = 300;

        ClaimEstimateService.ScenarioRow chosen = reimbursementScenario('Chosen rental', true, chosenLine);
        ClaimEstimateService.ScenarioRow rejected = reimbursementScenario('Pricier rental, not chosen', false, rejectedLine);

        Test.startTest();
        ClaimEstimateService.saveManageEstimates(
            ctx.claimId, new List<ClaimEstimateService.ScenarioRow>{ chosen, rejected }, null, null);
        Test.stopTest();

        System.assertEquals(2, [SELECT COUNT() FROM Benefit_Usage__c WHERE Claim__c = :ctx.claimId],
            'both receipts are stored, nothing is silently discarded');

        Benefit_Balance__c bal = [SELECT Used_To_Date__c, Remaining__c
                                  FROM Benefit_Balance__c WHERE Id = :ctx.balanceId];
        System.assertEquals(120, bal.Used_To_Date__c,
            'only the chosen scenario consumes the balance, not 120 + 300');
        System.assertEquals(380, bal.Remaining__c,
            'the customer still has 380 left on the term, not 80');
    }

    /** Moving Use between scenarios must move which receipt consumes the balance. */
    @IsTest
    static void movingUseMovesWhichReimbursementConsumesTheBalance() {
        ManageContext ctx = seedManageContext();

        ClaimEstimateService.ReimbursementRow a = new ClaimEstimateService.ReimbursementRow();
        a.benefitBalanceId = ctx.balanceId;
        a.receiptAmount = 120;
        ClaimEstimateService.ReimbursementRow b = new ClaimEstimateService.ReimbursementRow();
        b.benefitBalanceId = ctx.balanceId;
        b.receiptAmount = 300;

        ClaimEstimateService.ManageEstimatesData saved = ClaimEstimateService.saveManageEstimates(
            ctx.claimId,
            new List<ClaimEstimateService.ScenarioRow>{
                reimbursementScenario('First', true, a),
                reimbursementScenario('Second', false, b)
            }, null, null);

        // the agent changes their mind and marks the second one Use instead
        saved.scenarios[0].isSelected = false;
        saved.scenarios[1].isSelected = true;

        Test.startTest();
        ClaimEstimateService.saveManageEstimates(ctx.claimId, saved.scenarios, null, null);
        Test.stopTest();

        Benefit_Balance__c bal = [SELECT Used_To_Date__c FROM Benefit_Balance__c WHERE Id = :ctx.balanceId];
        System.assertEquals(300, bal.Used_To_Date__c,
            'the balance now follows the second scenario, and the first has released its hold');
    }

    private static ClaimEstimateService.ScenarioRow reimbursementScenario(
            String name, Boolean selected, ClaimEstimateService.ReimbursementRow line) {
        ClaimEstimateService.ScenarioRow s = new ClaimEstimateService.ScenarioRow();
        s.name = name;
        s.claimType = 'Reimbursement Only';
        s.taxPercent = 13;
        s.isSelected = selected;
        s.parts = new List<ClaimEstimateService.PartRow>();
        s.labour = new List<ClaimEstimateService.LabourRow>();
        s.supplies = new List<ClaimEstimateService.SupplyRow>();
        s.reimbursements = new List<ClaimEstimateService.ReimbursementRow>{ line };
        return s;
    }

    /**
     * Regression for the first of the two fixes the estimate-scoped benefit
     * rows forced. Without the Estimate__c = null filter a reimbursement line
     * would surface here as the claim's own ancillary draw and be counted twice.
     */
    @IsTest
    static void getBenefitBalancesIgnoresEstimateScopedReimbursementLines() {
        ManageContext ctx = seedManageContext();
        ClaimEstimateService.ManageEstimatesData d = ClaimEstimateService.saveManageEstimates(
            ctx.claimId, new List<ClaimEstimateService.ScenarioRow>{ optionC(ctx.shopId) }, null, null);

        insert new Benefit_Usage__c(
            Benefit_Balance__c = ctx.balanceId, Claim__c = ctx.claimId,
            Estimate__c = d.scenarios[0].id, Amount_Used__c = 75,
            Counts_Toward_Balance__c = false, Date__c = Date.today());

        Test.startTest();
        List<ClaimEstimateService.BenefitBalanceRow> rows =
            ClaimEstimateService.getBenefitBalancesForClaim(ctx.claimId);
        Test.stopTest();

        System.assertEquals(1, rows.size());
        System.assertEquals(null, rows[0].usageId,
            'the estimate-scoped line is not the claim-level draw and must not be shown as one');
    }

    /**
     * Regression for the second fix. A reimbursement typed into a scenario
     * the agent never marked Use must not move the claim's P&L.
     */
    @IsTest
    static void claimProfitIgnoresReimbursementsOnScenariosNotMarkedUse() {
        ManageContext ctx = seedManageContext();

        ClaimEstimateService.ReimbursementRow line = new ClaimEstimateService.ReimbursementRow();
        line.benefitBalanceId = ctx.balanceId;
        line.receiptAmount = 200;

        ClaimEstimateService.ScenarioRow losing = new ClaimEstimateService.ScenarioRow();
        losing.name = 'Rental reimbursement, not chosen';
        losing.claimType = 'Reimbursement Only';
        losing.taxPercent = 13;
        losing.isSelected = false;
        losing.parts = new List<ClaimEstimateService.PartRow>();
        losing.labour = new List<ClaimEstimateService.LabourRow>();
        losing.supplies = new List<ClaimEstimateService.SupplyRow>();
        losing.reimbursements = new List<ClaimEstimateService.ReimbursementRow>{ line };

        Test.startTest();
        ClaimEstimateService.saveManageEstimates(
            ctx.claimId,
            new List<ClaimEstimateService.ScenarioRow>{ optionC(ctx.shopId), losing },
            null, null);
        Test.stopTest();

        Claim__c claim = [SELECT Total_Benefits_Used__c, Total_Profit__c FROM Claim__c WHERE Id = :ctx.claimId];
        System.assertEquals(0, claim.Total_Benefits_Used__c,
            'the 200 belongs to the unchosen scenario and must not reach the claim');
        System.assertEquals(-2126.37, claim.Total_Profit__c,
            'claim profit is the chosen scenario repair-only P&L, with no stray reimbursement');
    }

    /** An edit must update the existing children, never duplicate them. */
    @IsTest
    static void resavingEditsChildrenInPlaceRatherThanDuplicatingThem() {
        ManageContext ctx = seedManageContext();
        ClaimEstimateService.ManageEstimatesData first = ClaimEstimateService.saveManageEstimates(
            ctx.claimId, new List<ClaimEstimateService.ScenarioRow>{ optionC(ctx.shopId) }, null, null);

        ClaimEstimateService.ScenarioRow s = first.scenarios[0];
        s.parts[0].unitWholesale = 1800;

        Test.startTest();
        ClaimEstimateService.saveManageEstimates(
            ctx.claimId, new List<ClaimEstimateService.ScenarioRow>{ s }, null, null);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Estimate__c WHERE Claim__c = :ctx.claimId],
            'still one estimate');
        System.assertEquals(1, [SELECT COUNT() FROM Part__c WHERE Estimate__r.Claim__c = :ctx.claimId],
            'still one part, edited in place');
        Estimate__c e = [SELECT Parts_Cost__c, Parts_Retail__c
                         FROM Estimate__c WHERE Claim__c = :ctx.claimId LIMIT 1];
        System.assertEquals(1800, e.Parts_Cost__c);
        System.assertEquals(2100, e.Parts_Retail__c, '1,800 + the same 300 dollar markup');
    }

    /** Removing a whole scenario takes its children with it rather than orphaning them. */
    @IsTest
    static void deletingAScenarioRemovesItsChildren() {
        ManageContext ctx = seedManageContext();
        ClaimEstimateService.ManageEstimatesData first = ClaimEstimateService.saveManageEstimates(
            ctx.claimId, new List<ClaimEstimateService.ScenarioRow>{ optionC(ctx.shopId) }, null, null);
        Id estimateId = first.scenarios[0].id;

        Test.startTest();
        ClaimEstimateService.saveManageEstimates(
            ctx.claimId, new List<ClaimEstimateService.ScenarioRow>(),
            new List<Id>{ estimateId }, null);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Estimate__c WHERE Id = :estimateId]);
        System.assertEquals(0, [SELECT COUNT() FROM Part__c WHERE Estimate__c = :estimateId],
            'Part__c looks up to Estimate__c with SetNull, so it has to be deleted explicitly');
        System.assertEquals(0, [SELECT COUNT() FROM Service__c WHERE Estimate__c = :estimateId]);
        System.assertEquals(0, [SELECT COUNT() FROM Shop_Supply__c WHERE Estimate__c = :estimateId]);
    }
}