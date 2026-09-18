@IsTest
private class ClaimEstimateServiceTest {

    /** Estimate under a real claim, with one Part, one Service and one Shop Supply child. */
    private static Estimate__c seedEstimateWithChildren() {
        Estimate__c created = TestDataFactory.createEstimateWithClaim('Warranty_Claim', true);
        insert new List<SObject>{
            new Part__c(Estimate__c = created.Id, Part_Name__c = 'LKQ used engine', Part_Code__c = 'ENG-2010-LKQ',
                        Part_Cost_Wholesale__c = 1300, Repair_Shop__c = created.Repair_Shop__c),
            new Service__c(Estimate__c = created.Id, Service_Repair_Description__c = 'Engine R&R',
                        Repair_Time_Adj__c = 8, Wholesale_Labour_Rate_HR__c = 75, Wholesale__c = 600,
                        Repair_Shop__c = created.Repair_Shop__c),
            new Shop_Supply__c(Estimate__c = created.Id, Item_Name__c = 'Shop supplies', Cost__c = 150,
                        Repair_Shop__c = created.Repair_Shop__c)
        };
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
        e.Parts_Cost__c = 1500; e.Core_Charge_Applies__c = true; e.Core_Charge__c = 200;
        e.Labour_Hours__c = 8; e.Labour_Rate__c = 75; e.Insurance_Amount__c = 120;
        e.Shop_Supplies__c = 150; e.Shop_Supplies_Retail__c = 300; e.Retail_Price__c = 4000;
        e.Deductable__c = 100;

        ClaimPricingService.PricingResult r = ClaimEstimateService.updateEstimate(e, 3000);

        System.assertEquals(2170, r.wsTotal);
        System.assertEquals(2170, [SELECT Wholesale_Cost__c FROM Estimate__c WHERE Id = :e.Id].Wholesale_Cost__c,
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
    static void createWorkOrderGeneratesLinesAndSelectsEstimate() {
        Estimate__c chosen = seedEstimateWithChildren();
        // A sibling on the same claim that must end up NOT selected.
        Estimate__c sibling = ClaimEstimateService.createEstimate(chosen.Claim__c, chosen.Repair_Shop__c, 'Other option');

        Test.startTest();
        ClaimEstimateService.WorkOrderResult r = ClaimEstimateService.createWorkOrder(chosen.Id);
        Test.stopTest();

        System.assertEquals(3, r.claimLineItems, 'one Claim Line Item per Part, Service, Shop Supply');
        System.assertEquals(3, r.workOrderLines, 'one Work Order Line Item per Claim Line Item');

        Work_Order__c wo = [SELECT Estimate__c, Claim__c, Repair_Shop__c, Total_Line_Items_Cost__c,
                                   Tax_13__c, Total_Repair_Cost__c
                            FROM Work_Order__c WHERE Id = :r.workOrderId];
        System.assertEquals(chosen.Id, wo.Estimate__c, 'existing lookup records which estimate won');
        System.assertEquals(chosen.Claim__c, wo.Claim__c);
        System.assertEquals(chosen.Repair_Shop__c, wo.Repair_Shop__c);
        // The work order's own formulas derive from the generated lines' Price__c.
        System.assertEquals(2050,    wo.Total_Line_Items_Cost__c, 'roll-up of Price__c: 1300 + 600 + 150');
        System.assertEquals(266.50,  wo.Tax_13__c,                '13% of the line items');
        System.assertEquals(2316.50, wo.Total_Repair_Cost__c,     'line items plus tax');

        Map<String, Claim_Line_Item__c> byType = new Map<String, Claim_Line_Item__c>();
        for (Claim_Line_Item__c cli : [SELECT Line_Type__c, Role__c, Amount__c, Hours__c, Rate__c, Part_Code__c, Description__c
                                       FROM Claim_Line_Item__c WHERE Claim__c = :chosen.Claim__c]) {
            byType.put(cli.Line_Type__c, cli);
        }
        System.assertEquals(1300, byType.get('Part').Amount__c);
        System.assertEquals('Parts Supplier', byType.get('Part').Role__c);
        System.assertEquals('ENG-2010-LKQ', byType.get('Part').Part_Code__c);
        System.assertEquals(600,  byType.get('Labour').Amount__c);
        System.assertEquals(8,    byType.get('Labour').Hours__c);
        System.assertEquals(75,   byType.get('Labour').Rate__c);
        System.assertEquals('Repair Shop', byType.get('Labour').Role__c);
        System.assertEquals(150,  byType.get('Supplies').Amount__c);

        System.assertEquals(true,  [SELECT Is_Selected__c FROM Estimate__c WHERE Id = :chosen.Id].Is_Selected__c);
        System.assertEquals(false, [SELECT Is_Selected__c FROM Estimate__c WHERE Id = :sibling.Id].Is_Selected__c,
            'selecting one estimate clears its sibling on the same claim');
    }

    @IsTest
    static void createWorkOrderRefusesDuplicate() {
        Estimate__c e = seedEstimateWithChildren();
        ClaimEstimateService.createWorkOrder(e.Id);
        try {
            ClaimEstimateService.createWorkOrder(e.Id);
            System.assert(false, 'expected an exception on the second work order');
        } catch (AuraHandledException ex) {
            System.assert(true);
        }
        System.assertEquals(1, [SELECT COUNT() FROM Work_Order__c WHERE Estimate__c = :e.Id]);
    }

    private static Integer countChildren(Id estimateId) {
        return [SELECT COUNT() FROM Part__c WHERE Estimate__c = :estimateId]
             + [SELECT COUNT() FROM Service__c WHERE Estimate__c = :estimateId]
             + [SELECT COUNT() FROM Shop_Supply__c WHERE Estimate__c = :estimateId];
    }
}