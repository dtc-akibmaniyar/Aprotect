/**
 * WorkOrderCreatorControllerTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Coverage target: 99%+
 *
 * Covers every branch of createWorkOrders():
 *   • Blank estimateId  → catch block → AuraHandledException
 *   • Malformed estimateId → SOQL exception → catch + rollback → AuraHandledException
 *   • No eligible items (Export_to_Work_Order__c=false or Repair_Shop__c=null)
 *   • Part__c instanceof branch  → Work_Order_Line_Item__c with part fields
 *   • Service__c instanceof branch → WOLI with all 9 service-specific fields
 *   • Shop_Supply__c instanceof branch → WOLI with supply fields
 *   • All three types same repair shop → one Work Order, three line items
 *   • Two repair shops → two Work Orders, items grouped correctly
 *   • Return value is a List<String> of valid Work Order Ids
 */
@isTest
private class WorkOrderCreatorControllerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // SHARED SETUP HELPER
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Builds the full parent chain required before any Part/Service/Supply
     * can be created with Estimate__c:
     *
     *   Dealer → Application → Repair_Shop__c → Claim__c → Estimate__c
     *
     * Returns a map with keys: 'dealer', 'app', 'repairShop', 'claim', 'estimate'
     */
    private static Map<String, SObject> setupEstimate() {
        Account        dealer     = TestDataFactory.createDealer(true);
        Application__c app        = TestDataFactory.createApplication(dealer.Id, true);
        Repair_Shop__c repairShop = TestDataFactory.createRepairShop(true);
        Claim__c       claim      = TestDataFactory.createClaim(
                                        app.Id, repairShop.Id, 'Warranty_Claim', true
                                    );
        Estimate__c    estimate   = TestDataFactory.createEstimate(
                                        claim.Id, repairShop.Id, true
                                    );
        return new Map<String, SObject>{
            'dealer'     => dealer,
            'app'        => app,
            'repairShop' => repairShop,
            'claim'      => claim,
            'estimate'   => estimate
        };
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 1 — ERROR PATHS (blank ID + catch/rollback)
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testCreateWorkOrders_blankEstimateId_throwsAuraHandledException() {
        // Blank string → AuraHandledException thrown inside try →
        // caught by catch(Exception e) → rollback → rethrown with
        // 'Error creating work orders:' prefix
        Boolean thrown = false;

        Test.startTest();
        try {
            WorkOrderCreatorController.createWorkOrders('');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown,
            'Blank estimateId should throw AuraHandledException');
    }

    @isTest
    static void testCreateWorkOrders_nullEstimateId_throwsAuraHandledException() {
        // String.isBlank(null) = true → same path as blank
        Boolean thrown = false;

        Test.startTest();
        try {
            WorkOrderCreatorController.createWorkOrders(null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown,
            'Null estimateId should throw AuraHandledException');
    }

    @isTest
    static void testCreateWorkOrders_malformedEstimateId_catchRollbackThrows() {
        // Non-blank, non-ID string → SOQL throws QueryException →
        // catch block runs rollback → rethrows AuraHandledException
        Boolean thrown = false;

        Test.startTest();
        try {
            WorkOrderCreatorController.createWorkOrders('NOT_A_VALID_SALESFORCE_ID');
        } catch (AuraHandledException e) {
            thrown = true;
            System.assert(
                e.getMessage().contains('Error creating work orders:'),
                'Catch block should prefix the message'
            );
        }
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 2 — NO ELIGIBLE ITEMS
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testCreateWorkOrders_noItems_returnsEmptyList() {
        // Estimate exists but has no eligible items at all
        Map<String, SObject> chain   = setupEstimate();
        Estimate__c          estimate = (Estimate__c) chain.get('estimate');

        Test.startTest();
            List<String> result =
                WorkOrderCreatorController.createWorkOrders(estimate.Id);
        Test.stopTest();

        System.assertNotEquals(null, result,
            'Result should never be null');
        System.assertEquals(0, result.size(),
            'Empty result expected when no items match the SOQL filter');
        System.assertEquals(0,
            [SELECT COUNT() FROM Work_Order__c WHERE Estimate__c = :estimate.Id],
            'No Work Orders should be created when there are no eligible items');
    }

    @isTest
    static void testCreateWorkOrders_exportFalse_itemsExcluded() {
        // Parts/Services/Supplies exist but Export_to_Work_Order__c = false
        // → SOQL filter excludes them → no work orders
        Map<String, SObject> chain      = setupEstimate();
        Estimate__c          estimate   = (Estimate__c)   chain.get('estimate');
        Repair_Shop__c       repairShop = (Repair_Shop__c) chain.get('repairShop');

        // Create items with Export_to_Work_Order__c = false (factory default)
        TestDataFactory.createPart(estimate.Id, true);
        TestDataFactory.createService(estimate.Id, true);
        TestDataFactory.createShopSupply(estimate.Id, repairShop.Id, true);

        Test.startTest();
            List<String> result =
                WorkOrderCreatorController.createWorkOrders(estimate.Id);
        Test.stopTest();

        System.assertEquals(0, result.size(),
            'Items with Export_to_Work_Order__c=false should be excluded');
        System.assertEquals(0,
            [SELECT COUNT() FROM Work_Order__c WHERE Estimate__c = :estimate.Id],
            'No Work Orders should be created for non-exported items');
    }

    @isTest
    static void testCreateWorkOrders_nullRepairShop_itemsExcluded() {
        // Items with Repair_Shop__c = null → excluded by SOQL filter
        Map<String, SObject> chain    = setupEstimate();
        Estimate__c          estimate = (Estimate__c) chain.get('estimate');

        // createPart / createService without repairShop → Repair_Shop__c = null
        Part__c p = new Part__c(
            Estimate__c             = estimate.Id,
            Part_Name__c            = 'No Shop Part',
            Export_to_Work_Order__c = true,
            Supplier_Name__c        = 'MEGACITY',
            Part_Type__c            = 'NEW',
            KMS__c                  = 10000,
            Part_Cost__c            = 50.00,
            Retail_Markup__c        = '20%',
            Quantity__c             = 1,
            Additional_Part__c      = false
            // Repair_Shop__c intentionally omitted
        );
        insert p;

        Test.startTest();
            List<String> result =
                WorkOrderCreatorController.createWorkOrders(estimate.Id);
        Test.stopTest();

        System.assertEquals(0, result.size(),
            'Items with null Repair_Shop__c should be excluded by SOQL filter');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 3 — PART instanceof BRANCH
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testCreateWorkOrders_partOnly_createsWorkOrderAndLineItem() {
        Map<String, SObject> chain      = setupEstimate();
        Estimate__c          estimate   = (Estimate__c)   chain.get('estimate');
        Repair_Shop__c       repairShop = (Repair_Shop__c) chain.get('repairShop');

        Part__c part = TestDataFactory.createPartForWorkOrder(
                           estimate.Id, repairShop.Id, true
                       );

        Test.startTest();
            List<String> result =
                WorkOrderCreatorController.createWorkOrders(estimate.Id);
        Test.stopTest();

        System.assertEquals(1, result.size(),
            'One Work Order should be created for one repair shop');

        Id workOrderId = (Id) result[0];
        Work_Order__c wo = [
            SELECT Estimate__c, Repair_Shop__c
            FROM   Work_Order__c
            WHERE  Id = :workOrderId
        ];
        System.assertEquals(estimate.Id,   wo.Estimate__c,   'WO should reference the Estimate');
        System.assertEquals(repairShop.Id, wo.Repair_Shop__c,'WO should reference the Repair Shop');

        List<Work_Order_Line_Item__c> lineItems = [
            SELECT Customer_Work_Order__c, Repair_Shop__c,
                   Comments__c, Coverage_Category__c, Description__c,
                   Price__c, Priority__c, Service_Repair_Description__c
            FROM   Work_Order_Line_Item__c
            WHERE  Customer_Work_Order__c = :workOrderId
        ];
        System.assertEquals(1, lineItems.size(),
            'Exactly one line item should be created for the part');

        Work_Order_Line_Item__c woli = lineItems[0];
        System.assertEquals(repairShop.Id,                  woli.Repair_Shop__c,
            'WOLI Repair_Shop__c should match the part Repair_Shop__c');
        System.assertEquals(part.Comments__c,               woli.Comments__c,
            'WOLI Comments__c should come from Part.Comments__c');
        System.assertEquals(part.Coverage_Category__c,      woli.Coverage_Category__c,
            'WOLI Coverage_Category__c should come from Part.Coverage_Category__c');
        System.assertEquals(part.Comments__c,               woli.Description__c,
            'WOLI Description__c should come from Part.Comments__c');
        System.assertEquals(part.Product_Charge__c,         woli.Price__c,
            'WOLI Price__c should come from Part.Product_Charge__c');
        System.assertEquals(part.Priority__c,               woli.Priority__c,
            'WOLI Priority__c should come from Part.Priority__c');
        System.assertEquals(part.Service_Repair_Description__c,
            woli.Service_Repair_Description__c,
            'WOLI Service_Repair_Description__c should come from Part');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 4 — SERVICE instanceof BRANCH (including all 9 extra fields)
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testCreateWorkOrders_serviceOnly_createsWorkOrderAndLineItem() {
        Map<String, SObject> chain      = setupEstimate();
        Estimate__c          estimate   = (Estimate__c)   chain.get('estimate');
        Repair_Shop__c       repairShop = (Repair_Shop__c) chain.get('repairShop');

        Service__c svc = TestDataFactory.createServiceForWorkOrder(
                             estimate.Id, repairShop.Id, true
                         );

        Test.startTest();
            List<String> result =
                WorkOrderCreatorController.createWorkOrders(estimate.Id);
        Test.stopTest();

        System.assertEquals(1, result.size(),
            'One Work Order should be created for one repair shop');

        Id workOrderId = (Id) result[0];
        List<Work_Order_Line_Item__c> lineItems = [
            SELECT Customer_Work_Order__c, Repair_Shop__c,
                   Comments__c, Coverage_Category__c, Description__c,
                   Price__c, Priority__c, Service_Repair_Description__c,
                   Labour_Guide_Time_All_Data__c, Labour_Guide_Time_Mitchell__c,
                   Repair_Time_Adj__c, Repair_Time_EST__c,
                   Retail__c, Retail_Labour_Rate__c, Total_Repair__c,
                   Wholesale__c, Wholesale_Labour_Rate_HR__c
            FROM   Work_Order_Line_Item__c
            WHERE  Customer_Work_Order__c = :workOrderId
        ];
        System.assertEquals(1, lineItems.size(),
            'Exactly one line item should be created for the service');

        Work_Order_Line_Item__c woli = lineItems[0];

        // Common fields
        System.assertEquals(repairShop.Id,                  woli.Repair_Shop__c,
            'WOLI Repair_Shop__c should match service Repair_Shop__c');
        System.assertEquals(svc.Comments__c,                woli.Comments__c,
            'WOLI Comments__c should come from Service.Comments__c');
        System.assertEquals(svc.Coverage_Category__c,       woli.Coverage_Category__c,
            'WOLI Coverage_Category__c should come from Service.Coverage_Category__c');
        System.assertEquals(svc.Comments__c,                woli.Description__c,
            'WOLI Description__c should come from Service.Comments__c');
        System.assertEquals(svc.Charge__c,                  woli.Price__c,
            'WOLI Price__c should come from Service.Charge__c');
        System.assertEquals(svc.Priority__c,                woli.Priority__c,
            'WOLI Priority__c should come from Service.Priority__c');
        System.assertEquals(svc.Service_Repair_Description__c,
            woli.Service_Repair_Description__c,
            'WOLI Service_Repair_Description__c should come from Service');

        // Service-specific fields
        System.assertEquals(svc.Labour_Guide_Time_All_Data__c,
            woli.Labour_Guide_Time_All_Data__c,
            'Labour_Guide_Time_All_Data__c should be mapped from Service');
        System.assertEquals(svc.Labour_Guide_Time_Mitchell__c,
            woli.Labour_Guide_Time_Mitchell__c,
            'Labour_Guide_Time_Mitchell__c should be mapped from Service');
        System.assertEquals(svc.Repair_Time_Adj__c,         woli.Repair_Time_Adj__c,
            'Repair_Time_Adj__c should be mapped from Service');
        System.assertEquals(svc.Repair_Time_EST__c,         woli.Repair_Time_EST__c,
            'Repair_Time_EST__c should be mapped from Service');
        System.assertEquals(svc.Retail__c,                  woli.Retail__c,
            'Retail__c should be mapped from Service');
        System.assertEquals(svc.Retail_Labour_Rate__c,      woli.Retail_Labour_Rate__c,
            'Retail_Labour_Rate__c should be mapped from Service');
        System.assertEquals(svc.Total_Repair__c,            woli.Total_Repair__c,
            'Total_Repair__c should be mapped from Service');
        System.assertEquals(svc.Wholesale__c,               woli.Wholesale__c,
            'Wholesale__c should be mapped from Service');
        System.assertEquals(svc.Wholesale_Labour_Rate_HR__c,woli.Wholesale_Labour_Rate_HR__c,
            'Wholesale_Labour_Rate_HR__c should be mapped from Service');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 5 — SHOP_SUPPLY instanceof BRANCH
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testCreateWorkOrders_shopSupplyOnly_createsWorkOrderAndLineItem() {
        Map<String, SObject> chain      = setupEstimate();
        Estimate__c          estimate   = (Estimate__c)   chain.get('estimate');
        Repair_Shop__c       repairShop = (Repair_Shop__c) chain.get('repairShop');

        Shop_Supply__c supply = TestDataFactory.createShopSupplyForWorkOrder(
                                    estimate.Id, repairShop.Id, true
                                );

        Test.startTest();
            List<String> result =
                WorkOrderCreatorController.createWorkOrders(estimate.Id);
        Test.stopTest();

        System.assertEquals(1, result.size(),
            'One Work Order should be created for one repair shop');

        Id workOrderId = (Id) result[0];
        List<Work_Order_Line_Item__c> lineItems = [
            SELECT Customer_Work_Order__c, Repair_Shop__c,
                   Comments__c, Coverage_Category__c, Description__c,
                   Price__c, Priority__c, Service_Repair_Description__c
            FROM   Work_Order_Line_Item__c
            WHERE  Customer_Work_Order__c = :workOrderId
        ];
        System.assertEquals(1, lineItems.size(),
            'Exactly one line item should be created for the supply');

        Work_Order_Line_Item__c woli = lineItems[0];
        System.assertEquals(repairShop.Id,                   woli.Repair_Shop__c,
            'WOLI Repair_Shop__c should match supply Repair_Shop__c');
        System.assertEquals(supply.Comments__c,              woli.Comments__c,
            'WOLI Comments__c should come from Shop_Supply.Comments__c');
        System.assertEquals(supply.Coverage_Category__c,     woli.Coverage_Category__c,
            'WOLI Coverage_Category__c should come from Shop_Supply.Coverage_Category__c');
        System.assertEquals(supply.Comments__c,              woli.Description__c,
            'WOLI Description__c should come from Shop_Supply.Comments__c');
        System.assertEquals(supply.Charge__c,                woli.Price__c,
            'WOLI Price__c should come from Shop_Supply.Charge__c');
        System.assertEquals(supply.Priority__c,              woli.Priority__c,
            'WOLI Priority__c should come from Shop_Supply.Priority__c');
        System.assertEquals(supply.Service_Repair_Description__c,
            woli.Service_Repair_Description__c,
            'WOLI Service_Repair_Description__c should come from Shop_Supply');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 6 — ALL THREE TYPES, SAME REPAIR SHOP
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testCreateWorkOrders_allThreeTypes_sameShop_oneWorkOrderThreeLineItems() {
        Map<String, SObject> chain      = setupEstimate();
        Estimate__c          estimate   = (Estimate__c)   chain.get('estimate');
        Repair_Shop__c       repairShop = (Repair_Shop__c) chain.get('repairShop');

        TestDataFactory.createPartForWorkOrder(estimate.Id,       repairShop.Id, true);
        TestDataFactory.createServiceForWorkOrder(estimate.Id,    repairShop.Id, true);
        TestDataFactory.createShopSupplyForWorkOrder(estimate.Id, repairShop.Id, true);

        Test.startTest();
            List<String> result =
                WorkOrderCreatorController.createWorkOrders(estimate.Id);
        Test.stopTest();

        // All three items are in the same shop → one Work Order
        System.assertEquals(1, result.size(),
            'All items in the same shop should produce exactly one Work Order');

        Id workOrderId = (Id) result[0];
        System.assertEquals(3,
            [SELECT COUNT() FROM Work_Order_Line_Item__c
             WHERE Customer_Work_Order__c = :workOrderId],
            'Three line items should be created (one per item type)');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 7 — MULTIPLE REPAIR SHOPS → MULTIPLE WORK ORDERS
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testCreateWorkOrders_twoShops_twoWorkOrdersCreated() {
        Map<String, SObject> chain       = setupEstimate();
        Estimate__c          estimate    = (Estimate__c)   chain.get('estimate');
        Repair_Shop__c       repairShop1 = (Repair_Shop__c) chain.get('repairShop');
        Repair_Shop__c       repairShop2 = TestDataFactory.createRepairShop(true);

        // Shop 1 gets a Part, Shop 2 gets a Service
        TestDataFactory.createPartForWorkOrder(estimate.Id,    repairShop1.Id, true);
        TestDataFactory.createServiceForWorkOrder(estimate.Id, repairShop2.Id, true);

        Test.startTest();
            List<String> result =
                WorkOrderCreatorController.createWorkOrders(estimate.Id);
        Test.stopTest();

        System.assertEquals(2, result.size(),
            'Two repair shops should produce two Work Orders');

        Set<Id> returnedIds = new Set<Id>();
        for (String idStr : result) returnedIds.add((Id) idStr);

        List<Work_Order__c> wos = [
            SELECT Repair_Shop__c
            FROM   Work_Order__c
            WHERE  Id IN :returnedIds
        ];
        System.assertEquals(2, wos.size(),
            'Two Work_Order__c records should exist in the database');

        // Verify the two WOs point to different repair shops
        Set<Id> shopIds = new Set<Id>();
        for (Work_Order__c wo : wos) shopIds.add(wo.Repair_Shop__c);
        System.assertEquals(2, shopIds.size(),
            'The two Work Orders should be linked to different repair shops');
        System.assert(shopIds.contains(repairShop1.Id),
            'Work Order for shop 1 should exist');
        System.assert(shopIds.contains(repairShop2.Id),
            'Work Order for shop 2 should exist');
    }

    @isTest
    static void testCreateWorkOrders_twoShops_lineItemsGroupedCorrectly() {
        Map<String, SObject> chain       = setupEstimate();
        Estimate__c          estimate    = (Estimate__c)   chain.get('estimate');
        Repair_Shop__c       repairShop1 = (Repair_Shop__c) chain.get('repairShop');
        Repair_Shop__c       repairShop2 = TestDataFactory.createRepairShop(true);

        // Shop 1 gets two parts, Shop 2 gets one supply
        TestDataFactory.createPartForWorkOrder(estimate.Id, repairShop1.Id, true);
        TestDataFactory.createPartForWorkOrder(estimate.Id, repairShop1.Id, true);
        TestDataFactory.createShopSupplyForWorkOrder(estimate.Id, repairShop2.Id, true);

        Test.startTest();
            List<String> result =
                WorkOrderCreatorController.createWorkOrders(estimate.Id);
        Test.stopTest();

        System.assertEquals(2, result.size(),
            'Two shops should produce two Work Orders');

        // Find which WO belongs to which shop
        Set<Id> woIds = new Set<Id>();
        for (String s : result) woIds.add((Id) s);

        List<Work_Order__c> wos = [
            SELECT Id, Repair_Shop__c FROM Work_Order__c WHERE Id IN :woIds
        ];

        Id shop1WoId;
        Id shop2WoId;
        for (Work_Order__c wo : wos) {
            if (wo.Repair_Shop__c == repairShop1.Id) shop1WoId = wo.Id;
            if (wo.Repair_Shop__c == repairShop2.Id) shop2WoId = wo.Id;
        }

        System.assertEquals(2,
            [SELECT COUNT() FROM Work_Order_Line_Item__c
             WHERE Customer_Work_Order__c = :shop1WoId],
            'Shop 1 Work Order should have 2 line items');
        System.assertEquals(1,
            [SELECT COUNT() FROM Work_Order_Line_Item__c
             WHERE Customer_Work_Order__c = :shop2WoId],
            'Shop 2 Work Order should have 1 line item');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 8 — RETURN VALUE VERIFICATION
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testCreateWorkOrders_returnedIds_areValidWorkOrderIds() {
        Map<String, SObject> chain      = setupEstimate();
        Estimate__c          estimate   = (Estimate__c)   chain.get('estimate');
        Repair_Shop__c       repairShop = (Repair_Shop__c) chain.get('repairShop');

        TestDataFactory.createPartForWorkOrder(estimate.Id, repairShop.Id, true);

        Test.startTest();
            List<String> result =
                WorkOrderCreatorController.createWorkOrders(estimate.Id);
        Test.stopTest();

        System.assertEquals(1, result.size(),
            'One Work Order ID should be returned');
        System.assertNotEquals(null, result[0],
            'Returned Work Order ID string should not be null');

        // Cast must succeed — string must be a valid Salesforce Id
        Id parsedId;
        try {
            parsedId = (Id) result[0];
        } catch (Exception e) {
            System.assert(false,
                'Returned string should be castable to a Salesforce Id: ' + result[0]);
        }

        // Verify the ID actually points to a Work_Order__c record
        List<Work_Order__c> wos = [SELECT Id FROM Work_Order__c WHERE Id = :parsedId];
        System.assertEquals(1, wos.size(),
            'Returned ID should correspond to a real Work_Order__c record');
    }

    @isTest
    static void testCreateWorkOrders_returnsStringList_notIdList() {
        // Return type is List<String> — verify each element is a String
        Map<String, SObject> chain      = setupEstimate();
        Estimate__c          estimate   = (Estimate__c)   chain.get('estimate');
        Repair_Shop__c       repairShop = (Repair_Shop__c) chain.get('repairShop');

        TestDataFactory.createServiceForWorkOrder(estimate.Id, repairShop.Id, true);

        Test.startTest();
            List<String> result =
                WorkOrderCreatorController.createWorkOrders(estimate.Id);
        Test.stopTest();

        System.assertNotEquals(null, result,
            'Return value should not be null');
        System.assertEquals(1, result.size(),
            'One element should be returned');
        System.assertNotEquals(null, result[0],
            'The returned element should not be null');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 9 — MIXED ELIGIBLE AND INELIGIBLE ITEMS
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testCreateWorkOrders_mixedExportFlags_onlyEligibleItemsIncluded() {
        Map<String, SObject> chain      = setupEstimate();
        Estimate__c          estimate   = (Estimate__c)   chain.get('estimate');
        Repair_Shop__c       repairShop = (Repair_Shop__c) chain.get('repairShop');

        // Eligible — Export=true, Repair_Shop set
        TestDataFactory.createPartForWorkOrder(estimate.Id, repairShop.Id, true);

        // Ineligible — Export=false (factory default does not set Export=true)
        TestDataFactory.createPart(estimate.Id, true);

        Test.startTest();
            List<String> result =
                WorkOrderCreatorController.createWorkOrders(estimate.Id);
        Test.stopTest();

        System.assertEquals(1, result.size(),
            'Only one Work Order should be created for the eligible part');

        Id workOrderId = (Id) result[0];
        System.assertEquals(1,
            [SELECT COUNT() FROM Work_Order_Line_Item__c
             WHERE Customer_Work_Order__c = :workOrderId],
            'Only the eligible part should produce a line item');
    }

    @isTest
    static void testCreateWorkOrders_bulkItems_200Parts_governorLimitSafe() {
        Map<String, SObject> chain      = setupEstimate();
        Estimate__c          estimate   = (Estimate__c)   chain.get('estimate');
        Repair_Shop__c       repairShop = (Repair_Shop__c) chain.get('repairShop');

        // 200 eligible parts all in the same shop
        List<Part__c> parts = new List<Part__c>();
        for (Integer i = 0; i < 200; i++) {
            parts.add(new Part__c(
                Estimate__c                   = estimate.Id,
                Repair_Shop__c                = repairShop.Id,
                Export_to_Work_Order__c       = true,
                Part_Name__c                  = 'Bulk Part ' + i,
                Supplier_Name__c              = 'MEGACITY',
                Part_Type__c                  = 'NEW',
                KMS__c                        = 10000,
                Part_Cost__c                  = 20.00,
                Retail_Markup__c              = '20%',
                Quantity__c                   = 1,
                Product_Charge__c             = 30.00,
                Coverage_Category__c          = 'Engine',
                Priority__c                   = 'Critical - Required',
                Warranty_Coverage_Status__c   = 'Covered',
                Service_Repair_Description__c = 'Bulk desc ' + i,
                Comments__c                   = 'Bulk comment ' + i,
                Additional_Part__c            = false
            ));
        }
        insert parts;

        Test.startTest();
            List<String> result =
                WorkOrderCreatorController.createWorkOrders(estimate.Id);
        Test.stopTest();

        System.assertEquals(1, result.size(),
            '200 parts in one shop should produce one Work Order');
        System.assertEquals(200,
            [SELECT COUNT() FROM Work_Order_Line_Item__c
             WHERE Customer_Work_Order__c = :(Id)result[0]],
            '200 line items should be created');
    }
}