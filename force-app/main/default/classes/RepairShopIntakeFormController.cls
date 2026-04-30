public without sharing class RepairShopIntakeFormController {

    public class VehicleInfo {
        @AuraEnabled public String vehicle { get; set; }
        @AuraEnabled public String vin { get; set; }
        @AuraEnabled public String odometerIn { get; set; }
        @AuraEnabled public String odometerOut { get; set; }
    }

    public class ShopInfo {
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String address { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String hstNumber { get; set; }
        @AuraEnabled public Decimal taxPercentage { get; set; } 
    }

    public class CustomerInfo {
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String address { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String email { get; set; }
    }

    public class ServiceWrapper {
        @AuraEnabled public String category { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String serviceTime { get; set; }
        @AuraEnabled public Decimal cost { get; set; }
        @AuraEnabled public Decimal price { get; set; }
        @AuraEnabled public Decimal discount { get; set; }
        @AuraEnabled public Decimal charge { get; set; }
    }

    public class PartWrapper {
        @AuraEnabled public String partCode { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Decimal quantity { get; set; }
        @AuraEnabled public Decimal partCost { get; set; }
        @AuraEnabled public Decimal price { get; set; }
        @AuraEnabled public Decimal discount { get; set; }
        @AuraEnabled public Decimal productCharge { get; set; }
    }

    public class SupplyWrapper {
        @AuraEnabled public String itemName { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String supplyTime { get; set; }
        @AuraEnabled public Decimal quantity { get; set; }
        @AuraEnabled public Decimal cost { get; set; }
        @AuraEnabled public Decimal price { get; set; }
        @AuraEnabled public Decimal discount { get; set; }
        @AuraEnabled public Decimal charge { get; set; }
    }

    public class ClaimInfoWrapper {
        @AuraEnabled public VehicleInfo vehicleInfo { get; set; }
        @AuraEnabled public ShopInfo shopInfo { get; set; }
        @AuraEnabled public CustomerInfo customerInfo { get; set; }
    }

    public class EstimateRequest {
        @AuraEnabled public String claimId { get; set; }
        @AuraEnabled public String repairShopId { get; set; }
        @AuraEnabled public List<ServiceWrapper> services { get; set; }
        @AuraEnabled public List<PartWrapper> parts { get; set; }
        @AuraEnabled public List<SupplyWrapper> supplies { get; set; }
        @AuraEnabled public String repairComments { get; set; }
    }

    public class EstimateResponse {
        @AuraEnabled public String estimateId { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String message { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static ClaimInfoWrapper getVehicleAndShopInfoFromClaim(String claimId) {
        try {
            Claim__c claim = [
                SELECT 
                    Vehicle__r.Name,
                    Vehicle__r.VIN__c,
                    Vehicle__r.Odometer__c,
                    Repair_Shop__r.Tax_Percentage__c,
                    Repair_Shop__r.Name,
                    Repair_Shop__r.Address__c,
                    Repair_Shop__r.Email__c,
                    Repair_Shop__r.Contact_Number__c,
                    Application__r.Customer_Name__r.Name,
                    Application__r.Customer_Name__r.BillingStreet,
                    Application__r.Customer_Name__r.BillingCity,
                    Application__r.Customer_Name__r.BillingState,
                    Application__r.Customer_Name__r.BillingPostalCode,
                    Application__r.Customer_Name__r.BillingCountry,
                    Application__r.Customer_Name__r.PersonMobilePhone,
                    Application__r.Customer_Name__r.PersonEmail
                FROM Claim__c 
                WHERE Id = :claimId
                LIMIT 1
            ];

            ClaimInfoWrapper wrapper = new ClaimInfoWrapper();
            
            wrapper.vehicleInfo = new VehicleInfo();
            wrapper.vehicleInfo.vehicle = claim.Vehicle__r?.Name;
            wrapper.vehicleInfo.vin = claim.Vehicle__r?.VIN__c;
            wrapper.vehicleInfo.odometerIn = String.valueOf(claim.Vehicle__r?.Odometer__c);
            
            wrapper.shopInfo = new ShopInfo();
            wrapper.shopInfo.name = claim.Repair_Shop__r?.Name;
            wrapper.shopInfo.address = claim.Repair_Shop__r?.Address__c;
            wrapper.shopInfo.email = claim.Repair_Shop__r?.Email__c;
            wrapper.shopInfo.phone = claim.Repair_Shop__r?.Contact_Number__c;
            wrapper.shopInfo.taxPercentage = claim.Repair_Shop__r?.Tax_Percentage__c;
            
            wrapper.customerInfo = new CustomerInfo();
            wrapper.customerInfo.name = claim.Application__r?.Customer_Name__r?.Name;
            wrapper.customerInfo.address = formatAddress(
                claim.Application__r?.Customer_Name__r?.BillingStreet,
                claim.Application__r?.Customer_Name__r?.BillingCity,
                claim.Application__r?.Customer_Name__r?.BillingState,
                claim.Application__r?.Customer_Name__r?.BillingPostalCode,
                claim.Application__r?.Customer_Name__r?.BillingCountry
            );
            wrapper.customerInfo.phone = claim.Application__r?.Customer_Name__r?.PersonMobilePhone;
            wrapper.customerInfo.email = claim.Application__r?.Customer_Name__r?.PersonEmail;

            return wrapper;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching information: ' + e.getMessage());
        }
    }

    private static String formatAddress(String street, String city, String state, String postalCode, String country) {
        List<String> addressParts = new List<String>();
        
        if (String.isNotBlank(street)) {
            addressParts.add(street);
        }
        
        String cityState = '';
        if (String.isNotBlank(city)) {
            cityState = city;
        }
        if (String.isNotBlank(state)) {
            cityState += (String.isNotBlank(cityState) ? ', ' : '') + state;
        }
        if (String.isNotBlank(cityState)) {
            addressParts.add(cityState);
        }
        
        if (String.isNotBlank(postalCode)) {
            addressParts.add(postalCode);
        }
        
        if (String.isNotBlank(country)) {
            addressParts.add(country);
        }
        
        return String.join(addressParts, ', ');
    }

    @AuraEnabled
    public static EstimateResponse createEstimate(EstimateRequest request) {
        try {
            // Always create a new estimate (do not use existing estimates)
            Estimate__c estimateToUse = new Estimate__c(
                Claim__c = request.claimId,
                Repair_Shop__c = request.repairShopId,
                Repair_Comments__c = request.repairComments
            );
            insert estimateToUse;

            // Create new services
            List<Service__c> servicesToInsert = new List<Service__c>();
            for(ServiceWrapper svc : request.services) {
                Service__c newService = new Service__c(
                    Estimate__c = estimateToUse.Id,
                    Repair_Shop__c = request.repairShopId,
                    Category__c = svc.category,
                    Item_Desription__c = svc.description,
                    Service_Repair_Description__c = svc.description,  // Added this field
                    Time__c = svc.serviceTime,
                    Cost__c = svc.cost,
                    Price__c = svc.price,
                    Discount__c = svc.discount,
                    Charge__c = svc.charge
                );
                servicesToInsert.add(newService);
            }

            if(!servicesToInsert.isEmpty()) {
                insert servicesToInsert;
            }

            // Create new parts
            List<Part__c> partsToInsert = new List<Part__c>();
            for(PartWrapper part : request.parts) {
                Part__c newPart = new Part__c(
                    Estimate__c = estimateToUse.Id,
                    Repair_Shop__c = request.repairShopId,
                    Part_Code__c = part.partCode,
                    Description__c = part.description,
                    Service_Repair_Description__c = part.description,  // Added this field
                    Quantity__c = part.quantity,
                    Part_Cost__c = part.partCost,
                    Price__c = part.price,
                    Discount__c = part.discount,
                    Product_Charge__c = part.productCharge
                );
                partsToInsert.add(newPart);
            }

            if(!partsToInsert.isEmpty()) {
                insert partsToInsert;
            }

            // Create new supplies
            List<Shop_Supply__c> suppliesToInsert = new List<Shop_Supply__c>();
            for(SupplyWrapper supply : request.supplies) {
                Shop_Supply__c newSupply = new Shop_Supply__c(
                    Estimate__c = estimateToUse.Id,
                    Repair_Shop__c = request.repairShopId,
                    Item_Name__c = supply.itemName,
                    Item_Description__c = supply.description,
                    Service_Repair_Description__c = supply.description,  // Added this field
                    Time__c = supply.supplyTime,
                    Quantity__c = supply.quantity,
                    Cost__c = supply.cost,
                    Price__c = supply.price,
                    Discount__c = supply.discount,
                    Charge__c = supply.charge
                );
                suppliesToInsert.add(newSupply);
            }

            if(!suppliesToInsert.isEmpty()) {
                insert suppliesToInsert;
            }
            
            EstimateResponse response = new EstimateResponse();
            response.estimateId = estimateToUse.Id;
            response.status = 'SUCCESS';
            response.message = 'New estimate created successfully';
            
            return response;
            
        } catch (Exception e) {
            EstimateResponse response = new EstimateResponse();
            response.status = 'ERROR';
            response.message = e.getMessage();
            return response;
        }
    }
}