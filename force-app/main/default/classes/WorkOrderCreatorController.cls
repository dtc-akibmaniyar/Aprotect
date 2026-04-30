public with sharing class WorkOrderCreatorController {
    
    @AuraEnabled
    public static List<String> createWorkOrders(String estimateId) {
        SavePoint sp = Database.setSavePoint();
        try {
            if (String.isBlank(estimateId)) {
                throw new AuraHandledException('Estimate ID is required');
            }

            // Query related Shop Supplies, Services, and Parts with Export_to_Work_Order__c = true
            List<Shop_Supply__c> shopSupplies = [
                SELECT Id, Warranty_Coverage_Status__c, Priority__c, Coverage_Category__c, Repair_Shop__c, Service_Repair_Description__c, Comments__c, Charge__c
                FROM Shop_Supply__c
                WHERE Estimate__c = :estimateId AND Export_to_Work_Order__c = true AND Repair_Shop__c != null
            ];
            List<Service__c> services = [
                SELECT Id, Warranty_Coverage_Status__c, Priority__c, Coverage_Category__c, Repair_Shop__c, Service_Repair_Description__c, Comments__c, Charge__c, Labour_Guide_Time_All_Data__c, Labour_Guide_Time_Mitchell__c, Repair_Time_Adj__c, Repair_Time_EST__c, Retail__c, Retail_Labour_Rate__c, Total_Repair__c, Wholesale__c, Wholesale_Labour_Rate_HR__c
                FROM Service__c
                WHERE Estimate__c = :estimateId AND Export_to_Work_Order__c = true AND Repair_Shop__c != null
            ];
            List<Part__c> parts = [
                SELECT Id, Warranty_Coverage_Status__c, Priority__c, Coverage_Category__c, Repair_Shop__c, Service_Repair_Description__c, Comments__c, Product_Charge__c
                FROM Part__c
                WHERE Estimate__c = :estimateId AND Export_to_Work_Order__c = true AND Repair_Shop__c != null
            ];

            // Group all items by Repair_Shop__c
            Map<Id, List<SObject>> itemsByShop = new Map<Id, List<SObject>>();
            for (Shop_Supply__c ss : shopSupplies) {
                if (!itemsByShop.containsKey(ss.Repair_Shop__c)) {
                    itemsByShop.put(ss.Repair_Shop__c, new List<SObject>());
                }
                itemsByShop.get(ss.Repair_Shop__c).add(ss);
            }
            for (Service__c svc : services) {
                if (!itemsByShop.containsKey(svc.Repair_Shop__c)) {
                    itemsByShop.put(svc.Repair_Shop__c, new List<SObject>());
                }
                itemsByShop.get(svc.Repair_Shop__c).add(svc);
            }
            for (Part__c part : parts) {
                if (!itemsByShop.containsKey(part.Repair_Shop__c)) {
                    itemsByShop.put(part.Repair_Shop__c, new List<SObject>());
                }
                itemsByShop.get(part.Repair_Shop__c).add(part);
            }

            List<Work_Order__c> workOrdersToInsert = new List<Work_Order__c>();
            Map<Id, List<SObject>> shopToItems = itemsByShop;
            Map<Id, Id> shopToWorkOrderId = new Map<Id, Id>();

            // Create a Work Order for each Repair_Shop__c
            for (Id shopId : shopToItems.keySet()) {
                Work_Order__c wo = new Work_Order__c(
                    Estimate__c = estimateId,
                    Repair_Shop__c = shopId
                );
                workOrdersToInsert.add(wo);
            }
            insert workOrdersToInsert;

            // Map inserted Work Orders to their Repair_Shop__c
            for (Work_Order__c wo : workOrdersToInsert) {
                shopToWorkOrderId.put(wo.Repair_Shop__c, wo.Id);
            }

            // Prepare line items for all work orders
            List<Work_Order_Line_Item__c> lineItemsToInsert = new List<Work_Order_Line_Item__c>();
            for (Id shopId : shopToItems.keySet()) {
                Id workOrderId = shopToWorkOrderId.get(shopId);
                for (SObject item : shopToItems.get(shopId)) {
                    if (item instanceof Part__c) {
                        Part__c part = (Part__c)item;
                        lineItemsToInsert.add(new Work_Order_Line_Item__c(
                            Customer_Work_Order__c = workOrderId,
                            Repair_Shop__c = shopId,
                            Comments__c = part.Comments__c,
                            Coverage_Category__c = part.Coverage_Category__c,
                            Description__c = part.Comments__c,
                            Price__c = part.Product_Charge__c,
                            Priority__c = part.Priority__c,
                            Service_Repair_Description__c = part.Service_Repair_Description__c
                        ));
                    } else if (item instanceof Shop_Supply__c) {
                        Shop_Supply__c ss = (Shop_Supply__c)item;
                        lineItemsToInsert.add(new Work_Order_Line_Item__c(
                            Customer_Work_Order__c = workOrderId,
                            Repair_Shop__c = shopId,
                            Comments__c = ss.Comments__c,
                            Coverage_Category__c = ss.Coverage_Category__c,
                            Description__c = ss.Comments__c,
                            Price__c = ss.Charge__c,
                            Priority__c = ss.Priority__c,
                            Service_Repair_Description__c = ss.Service_Repair_Description__c
                        ));
                    } else if (item instanceof Service__c) {
                        Service__c svc = (Service__c)item;
                        lineItemsToInsert.add(new Work_Order_Line_Item__c(
                            Customer_Work_Order__c = workOrderId,
                            Repair_Shop__c = shopId,
                            Comments__c = svc.Comments__c,
                            Coverage_Category__c = svc.Coverage_Category__c,
                            Description__c = svc.Comments__c,
                            Price__c = svc.Charge__c,
                            Priority__c = svc.Priority__c,
                            Service_Repair_Description__c = svc.Service_Repair_Description__c,
                            Labour_Guide_Time_All_Data__c = svc.Labour_Guide_Time_All_Data__c,
                            Labour_Guide_Time_Mitchell__c = svc.Labour_Guide_Time_Mitchell__c,
                            Repair_Time_Adj__c = svc.Repair_Time_Adj__c,
                            Repair_Time_EST__c = svc.Repair_Time_EST__c,
                            Retail__c = svc.Retail__c,
                            Retail_Labour_Rate__c = svc.Retail_Labour_Rate__c,
                            Total_Repair__c = svc.Total_Repair__c,
                            Wholesale__c = svc.Wholesale__c,
                            Wholesale_Labour_Rate_HR__c = svc.Wholesale_Labour_Rate_HR__c
                        ));
                    }
                }
            }
            if (!lineItemsToInsert.isEmpty()) {
                insert lineItemsToInsert;
            }

            // Return the list of created Work Order Ids
            List<String> workOrderIdStrings = new List<String>();
            for (Id woId : shopToWorkOrderId.values()) {
                workOrderIdStrings.add((String)woId);
            }
            return workOrderIdStrings;
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException('Error creating work orders: ' + e.getMessage());
        }
    }
}