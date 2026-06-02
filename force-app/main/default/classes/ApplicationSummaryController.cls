public without sharing class ApplicationSummaryController {
    
    // DTO class for Customer Address
    public class CustomerAddressWrapper {
        @AuraEnabled public String street { get; set; }
        @AuraEnabled public String city { get; set; }
        @AuraEnabled public String state { get; set; }
        @AuraEnabled public String postalCode { get; set; }
        @AuraEnabled public String country { get; set; }
    }

    /**
     * @description Customer/Lessee Information
     */
    public class CustomerLesseeInfo {
        @AuraEnabled public String firstName { get; set; }
        @AuraEnabled public String lastName { get; set; }
        @AuraEnabled public String street { get; set; }
        @AuraEnabled public String city { get; set; }
        @AuraEnabled public String state { get; set; }
        @AuraEnabled public String postalCode { get; set; }
        @AuraEnabled public String country { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String fullName { get; set; }
        @AuraEnabled public String formattedAddress { get; set; }
    }
    
    /**
     * @description Customer/Co-Lessee Information
     */
    public class CustomerCoLesseeInfo {
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String street { get; set; }
        @AuraEnabled public String city { get; set; }
        @AuraEnabled public String state { get; set; }
        @AuraEnabled public String postalCode { get; set; }
        @AuraEnabled public String country { get; set; }
        @AuraEnabled public String businessPhone { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String formattedAddress { get; set; }
    }
    
    /**
     * @description Company/Business Information
     */
    public class CompanyBusinessInfo {
        @AuraEnabled public String companyName { get; set; }
        @AuraEnabled public String licenseNumber { get; set; }
        @AuraEnabled public String street { get; set; }
        @AuraEnabled public String city { get; set; }
        @AuraEnabled public String state { get; set; }
        @AuraEnabled public String postalCode { get; set; }
        @AuraEnabled public String country { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String formattedAddress { get; set; }
    }

    /**
     * @description Dealership Information
     */
    public class DealershipInformation {
        @AuraEnabled public String dealerName { get; set; }
        @AuraEnabled public String street { get; set; }
        @AuraEnabled public String city { get; set; }
        @AuraEnabled public String state { get; set; }
        @AuraEnabled public String postalCode { get; set; }
        @AuraEnabled public String country { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String formattedAddress { get; set; }
    }

    /**
     * @description Lien Holder/Lender Information
     */
    public class LienHolderInformation {
        @AuraEnabled public String lenderName { get; set; }
        @AuraEnabled public String street { get; set; }
        @AuraEnabled public String city { get; set; }
        @AuraEnabled public String state { get; set; }
        @AuraEnabled public String postalCode { get; set; }
        @AuraEnabled public String country { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String formattedAddress { get; set; }
    }

    /**
     * @description Financed Vehicle Loan Details
     */
    public class FinancedVehicleLoanDetails {
        @AuraEnabled public String loanTerm { get; set; }
        @AuraEnabled public Decimal amountFinanced { get; set; }
        @AuraEnabled public String formattedAmountFinanced { get; set; }
        @AuraEnabled public String interestRate { get; set; }
        @AuraEnabled public Decimal downPayment { get; set; }
        @AuraEnabled public String formattedDownPayment { get; set; }
        @AuraEnabled public String tradeInVehicle { get; set; }
        @AuraEnabled public Decimal tradeInLienPayout { get; set; }
        @AuraEnabled public String formattedTradeInLienPayout { get; set; }
    }

    /**
     * @description Vehicle Specifications Information
     */
    public class VehicleSpecifications {
        @AuraEnabled public String yearMakeModel { get; set; }
        @AuraEnabled public String year { get; set; }
        @AuraEnabled public String make { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public String vin { get; set; }
        @AuraEnabled public String odometer { get; set; }
        @AuraEnabled public String odometerUnit { get; set; }
        @AuraEnabled public Decimal purchasePrice { get; set; }
        @AuraEnabled public String formattedPurchasePrice { get; set; }
        @AuraEnabled public String purchaseDate { get; set; }
        @AuraEnabled public String deliveryDate { get; set; }
        @AuraEnabled public String commercialBusinessUse { get; set; }
        @AuraEnabled public String engine { get; set; }
        @AuraEnabled public String transmission { get; set; }
        @AuraEnabled public String fuelType { get; set; }
        @AuraEnabled public String drive { get; set; }
        @AuraEnabled public String bodyType { get; set; }
        @AuraEnabled public String color { get; set; }
        @AuraEnabled public String gvwr { get; set; }
    }

    /**
     * @description Manufacturer Warranty Information
     */
    public class ManufacturerWarranty {
        @AuraEnabled public String factoryWarrantyType { get; set; }
        @AuraEnabled public String coverageTerm { get; set; }
        @AuraEnabled public String inServiceDate { get; set; }
    }
    /**
     * @description Tire & Rim Details Information
     */
    public class TireRimDetails {
        @AuraEnabled public String tireBrand { get; set; }
        @AuraEnabled public String tireType { get; set; }
        @AuraEnabled public String treadDepth { get; set; }
        @AuraEnabled public String treadDepthUnit { get; set; }
        @AuraEnabled public String rimBrand { get; set; }
        @AuraEnabled public String rimType { get; set; }
        @AuraEnabled public String rimSize { get; set; }
        @AuraEnabled public String rimSizeUnit { get; set; }
    }
    /**
     * @description Vehicle Information container
     */
    public class VehicleInformation {
        @AuraEnabled public VehicleSpecifications specifications { get; set; }
        @AuraEnabled public ManufacturerWarranty warranty { get; set; }
        @AuraEnabled public TireRimDetails tireRimDetails { get; set; }
    }

    // DTO class for LWC integration
    public class ApplicationSummaryData {
        @AuraEnabled public Application__c application { get; set; }
        @AuraEnabled public String salesPersonName { get; set; }
        @AuraEnabled public CustomerAddressWrapper customerAddress { get; set; }
        @AuraEnabled public CustomerLesseeInfo customerLessee { get; set; }
        @AuraEnabled public CustomerCoLesseeInfo customerCoLessee { get; set; }
        @AuraEnabled public CompanyBusinessInfo company { get; set; }
        @AuraEnabled public DealershipInformation dealershipInfo { get; set; }
        @AuraEnabled public LienHolderInformation lienHolderInfo { get; set; }
        @AuraEnabled public FinancedVehicleLoanDetails financedVehicleLoans { get; set; }
        @AuraEnabled public VehicleInformation vehicle { get; set; }
        @AuraEnabled public List<ApplicationPackageRecordTypeWrapper> applicationPackages { get; set; }
        @AuraEnabled public List<Application_Package_Option__c> includedOptions { get; set; }
        @AuraEnabled public List<Application_Package_Option__c> optionalOptions { get; set; }
        
        // Constructor to initialize application with salesPersonName
        public ApplicationSummaryData() {
            this.application = new Application__c();
        }
    }

    /**
     * @description Application Package Wrapper for Summary Display
     */
    public class ApplicationPackageWrapper {
        @AuraEnabled public String packageHeaderName { get; set; }
        @AuraEnabled public String planName { get; set; }
        @AuraEnabled public String coverageTerm { get; set; }
        @AuraEnabled public Decimal retailCost { get; set; }
        @AuraEnabled public String formattedRetailCost { get; set; }
        @AuraEnabled public Decimal deductible { get; set; }
        @AuraEnabled public String formattedDeductible { get; set; }
        @AuraEnabled public Decimal tax { get; set; }
        @AuraEnabled public String formattedTax { get; set; }
        @AuraEnabled public Decimal taxRate { get; set; }
        @AuraEnabled public String formattedTaxRate { get; set; }
        @AuraEnabled public Decimal total { get; set; }
        @AuraEnabled public String formattedTotal { get; set; }
        @AuraEnabled public String contractStartDate { get; set; }
        @AuraEnabled public String contractExpiryDate { get; set; }
        @AuraEnabled public Decimal contractStartOdometer { get; set; }
        @AuraEnabled public Decimal contractExpiryOdometer { get; set; }
        @AuraEnabled public String contractStartOdometerUnit { get; set; }
        @AuraEnabled public String contractExpiryOdometerUnit { get; set; }
        @AuraEnabled public List<String> additionalOptionsPurchased { get; set; }
    }

    /**
     * @description Application Package Record Type Wrapper for grouping packages by type
     */
    public class ApplicationPackageRecordTypeWrapper {
        @AuraEnabled public String recordTypeName { get; set; }
        @AuraEnabled public List<ApplicationPackageWrapper> packages { get; set; }

        public ApplicationPackageRecordTypeWrapper(String recordType) {
            this.recordTypeName = recordType;
            this.packages = new List<ApplicationPackageWrapper>();
        }
    }

    // DTO class for Application Package data
    public class ApplicationPackageData {
        @AuraEnabled public List<RecordTypeWrapperDTO> recordTypeWrappers { get; set; }
        @AuraEnabled public String dealerLogoUrl { get; set; }
        @AuraEnabled public Boolean hasDealerLogo { get; set; }
        
        public ApplicationPackageData() {
            this.recordTypeWrappers = new List<RecordTypeWrapperDTO>();
        }
    }

    public class RecordTypeWrapperDTO {
        @AuraEnabled public String recordTypeName { get; set; }
        @AuraEnabled public List<PackageWrapperDTO> packages { get; set; }
        
        public RecordTypeWrapperDTO(String name) {
            this.recordTypeName = name;
            this.packages = new List<PackageWrapperDTO>();
        }
    }

    public class PackageWrapperDTO {
        @AuraEnabled public Application_Package__c pkg { get; set; }
        @AuraEnabled public List<Application_Package_Option__c> includedOptions { get; set; }
        @AuraEnabled public List<Application_Package_Option__c> optionalOptions { get; set; }
        @AuraEnabled public List<String> inclusionsList { get; set; }
        @AuraEnabled public List<String> exclusionsList { get; set; }
        @AuraEnabled public String packageLogoUrl { get; set; }
        @AuraEnabled public Boolean hasPackageLogo { get; set; }
        
        public PackageWrapperDTO() {
            this.includedOptions = new List<Application_Package_Option__c>();
            this.optionalOptions = new List<Application_Package_Option__c>();
            this.inclusionsList = new List<String>();
            this.exclusionsList = new List<String>();
        }
    }

    // PDF Generation Response
    public class PDFResponse {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String attachmentId { get; set; }
        @AuraEnabled public String fileName { get; set; }
    }

    @AuraEnabled
    public static ApplicationSummaryData getApplicationSummaryData(Id applicationId) {
        try {
            Application__c app = [
                SELECT Id, Name, Application_Status__c, Dealer_Logo__c, LastModifiedDate,
                Customer_Name__r.BillingStreet,
                Customer_Name__r.BillingCity,
                Customer_Name__r.BillingState,
                Customer_Name__r.BillingPostalCode,
                Customer_Name__r.BillingCountry,
                Customer_Name__r.Name,Customer_Name__c,Coverage_Term__c,Customer_Name__r.License_Number__c,
                Customer_Phone__c, Customer_First_Name__c, Customer_Last_Name__c, Customer_Email__c, 
                Customer_Home_Phone__c, Customer_Business_Phone__c, Customer_Address__c,
                Co_Buyer__c, Co_Buyer__r.Name, Co_Buyer__r.Phone, Co_Buyer__r.PersonEmail,
                Co_Buyer__r.BillingStreet, Co_Buyer__r.License_Number__c, Co_Buyer__r.BillingCity, Co_Buyer__r.BillingState,
                Co_Buyer__r.BillingPostalCode, Co_Buyer__r.BillingCountry,
                Company_Business__c, Dealer_Sales_ID_License__c,
                Vehicle__c, Vehicle__r.Year__c, Vehicle__r.Make__c, Vehicle__r.Model__c, Vehicle__r.VIN__c,
                Vehicle__r.Odometer__c, Vehicle__r.Odometer_Unit__c, Vehicle__r.Vehicle_Purchase_Price__c, Vehicle__r.Purchase_Date__c,
                Vehicle__r.Business_Commercial_Use__c, Vehicle__r.Type_Of_Commercial_Use__c, Vehicle__r.Engine__c, Vehicle__r.Transmission__c, Vehicle__r.Fuel_Type__c,
                Vehicle__r.Drive_Type__c, Vehicle__r.Body_Type__c, Vehicle__r.Color__c, Vehicle__r.GVWR__c,
                Vehicle__r.Factory_Warranty__c, Vehicle__r.Warranty_Term__c, Vehicle__r.In_Service_Date__c, Vehicle__r.Delivery_Date__c, Vehicle__r.Manufacturer_Warranty_Type__c,
                Dealer_Name__c,Dealer_Name__r.Name, Dealer_Name__r.Email__c, Dealer_Name__r.BillingStreet, Dealer_Name__r.BillingCity, Dealer_Name__r.BillingState, Dealer_Name__r.BillingPostalCode, Dealer_Name__r.BillingCountry, Dealer_Address__c, Dealer_Phone__c,
                Financial_Institution_Lender__c, Lender_Address__c, Lender_Phone__c,
                Finance_Loan_Term_Months__c, Amount_Financed__c, Interest_Rate__c, 
                Cash_Down_Payment__c, Trade_in_Amount__c,
                Sales_Person__c,Sales_Person__r.Name,Sales_Rep__r.Name, Sales_Rep__c,
                Package_Plan_Type__r.Name, Package__r.Name, Package_Tier__r.Name, Package_Term__r.Name
                FROM Application__c 
                WHERE Id = :applicationId 
                LIMIT 1
            ];

            ApplicationSummaryData data = new ApplicationSummaryData();
            data.application = app;
            
            // Set sales person name
            if (app.Sales_Rep__r != null) {
                data.salesPersonName = app.Sales_Rep__r.Name;
            }
            
            // Populate customer address wrapper - with null checks
            data.customerAddress = new CustomerAddressWrapper();
            if (app.Customer_Name__r != null) {
                data.customerAddress.street = app.Customer_Name__r.BillingStreet;
                data.customerAddress.city = app.Customer_Name__r.BillingCity;
                data.customerAddress.state = app.Customer_Name__r.BillingState;
                data.customerAddress.postalCode = app.Customer_Name__r.BillingPostalCode;
                data.customerAddress.country = app.Customer_Name__r.BillingCountry;
            }
            
            // Populate Customer/Lessee Information - with null checks
            data.customerLessee = new CustomerLesseeInfo();
            if (app.Customer_Name__c != null && app.Customer_Name__r != null) {
                data.customerLessee.firstName = app.Customer_First_Name__c;
                data.customerLessee.lastName = app.Customer_Last_Name__c;
                data.customerLessee.fullName = app.Customer_Name__r.Name;
                data.customerLessee.street = app.Customer_Name__r.BillingStreet;
                data.customerLessee.city = app.Customer_Name__r.BillingCity;
                data.customerLessee.state = app.Customer_Name__r.BillingState;
                data.customerLessee.postalCode = app.Customer_Name__r.BillingPostalCode;
                data.customerLessee.country = app.Customer_Name__r.BillingCountry;
                data.customerLessee.phone = app.Customer_Phone__c;
                data.customerLessee.email = app.Customer_Email__c;
                data.customerLessee.formattedAddress = formatAddress(
                    app.Customer_Name__r.BillingCity,
                    app.Customer_Name__r.BillingState,
                    app.Customer_Name__r.BillingPostalCode,
                    app.Customer_Name__r.BillingCountry
                );
            }
            
            // Populate Customer/Co-Lessee Information
            data.customerCoLessee = new CustomerCoLesseeInfo();
            if (app.Co_Buyer__c != null && app.Co_Buyer__r != null) {
                data.customerCoLessee.name = app.Co_Buyer__r.Name;
                data.customerCoLessee.street = app.Co_Buyer__r.BillingStreet;
                data.customerCoLessee.city = app.Co_Buyer__r.BillingCity;
                data.customerCoLessee.state = app.Co_Buyer__r.BillingState;
                data.customerCoLessee.postalCode = app.Co_Buyer__r.BillingPostalCode;
                data.customerCoLessee.country = app.Co_Buyer__r.BillingCountry;
                data.customerCoLessee.businessPhone = app.Co_Buyer__r.Phone;
                data.customerCoLessee.email = app.Co_Buyer__r.PersonEmail;
                data.customerCoLessee.formattedAddress = formatAddress(
                    app.Co_Buyer__r.BillingCity,
                    app.Co_Buyer__r.BillingState,
                    app.Co_Buyer__r.BillingPostalCode,
                    app.Co_Buyer__r.BillingCountry
                );
            }
            
            // Populate Company/Business Information - with null checks
            data.company = new CompanyBusinessInfo();
            if (String.isNotBlank(app.Company_Business__c)) {
                data.company.companyName = app.Company_Business__c;
            }
            if (app.Co_Buyer__c != null && app.Co_Buyer__r != null) {
                data.company.licenseNumber = app.Customer_Name__r.License_Number__c;
            }
            
            // Populate Dealership Information
            data.dealershipInfo = new DealershipInformation();
            if (app.Dealer_Name__c != null && app.Dealer_Name__r != null) {
                data.dealershipInfo.dealerName = app.Dealer_Name__r.Name;
                data.dealershipInfo.phone = app.Dealer_Phone__c;
                data.dealershipInfo.email = app.Dealer_Name__r.Email__c;
                data.dealershipInfo.street = app.Dealer_Name__r.BillingStreet;
                data.dealershipInfo.city = app.Dealer_Name__r.BillingCity;
                data.dealershipInfo.state = app.Dealer_Name__r.BillingState;
                data.dealershipInfo.postalCode = app.Dealer_Name__r.BillingPostalCode;
                data.dealershipInfo.country = app.Dealer_Name__r.BillingCountry;
                data.dealershipInfo.formattedAddress = formatAddress(
                    app.Dealer_Name__r.BillingCity,
                    app.Dealer_Name__r.BillingState,
                    app.Dealer_Name__r.BillingPostalCode,
                    app.Dealer_Name__r.BillingCountry
                );
            }
            
            // Populate Lien Holder/Lender Information - with null checks
            data.lienHolderInfo = new LienHolderInformation();
            if (String.isNotBlank(app.Financial_Institution_Lender__c)) {
                data.lienHolderInfo.lenderName = app.Financial_Institution_Lender__c;
                data.lienHolderInfo.phone = app.Lender_Phone__c;
                data.lienHolderInfo.street = app.Lender_Address__c;
            } else {
                // Fallback: try to read from GAP/Loan Protection Application_Package__c
                try {
                    List<Application_Package__c> gapPackages = [
                        SELECT Lender_Lienholder__c
                        FROM Application_Package__c
                        WHERE Application__c = :applicationId
                            AND (RecordType.DeveloperName = 'GAP_Coverage' OR RecordType.DeveloperName = 'Loan_Protection')
                            AND Active__c = true
                            AND Lender_Lienholder__c != null
                        ORDER BY LastModifiedDate DESC
                        LIMIT 1
                    ];
                    if (!gapPackages.isEmpty()) {
                        data.lienHolderInfo.lenderName = gapPackages[0].Lender_Lienholder__c;
                    }
                } catch (Exception gapEx) {
                    // Non-fatal: GAP package fallback failed
                }
            }
            
            // Populate Financed Vehicle Loan Details - with null checks
            data.financedVehicleLoans = new FinancedVehicleLoanDetails();
            if (app.Finance_Loan_Term_Months__c != null) {
                data.financedVehicleLoans.loanTerm = formatTerms(app.Finance_Loan_Term_Months__c);
            }
            data.financedVehicleLoans.amountFinanced = app.Amount_Financed__c != null ? app.Amount_Financed__c : 0;
            data.financedVehicleLoans.formattedAmountFinanced = app.Amount_Financed__c != null ? 
                formatCurrency(app.Amount_Financed__c) : '$0.00';
            data.financedVehicleLoans.interestRate = formatPercentage(app.Interest_Rate__c);
            data.financedVehicleLoans.downPayment = app.Cash_Down_Payment__c != null ? app.Cash_Down_Payment__c : 0;
            data.financedVehicleLoans.formattedDownPayment = app.Cash_Down_Payment__c != null ? 
                formatCurrency(app.Cash_Down_Payment__c) : '$0.00';
            data.financedVehicleLoans.tradeInVehicle = app.Trade_in_Amount__c != null ? 
                formatCurrency(app.Trade_in_Amount__c) : '$0.00';
            data.financedVehicleLoans.tradeInLienPayout = app.Trade_in_Amount__c != null ? app.Trade_in_Amount__c : 0;
            data.financedVehicleLoans.formattedTradeInLienPayout = app.Trade_in_Amount__c != null ? 
                formatCurrency(app.Trade_in_Amount__c) : '$0.00';
            
            // Populate Vehicle Information - Always initialize with empty objects
            data.vehicle = new VehicleInformation();
            data.vehicle.specifications = new VehicleSpecifications();
            data.vehicle.warranty = new ManufacturerWarranty();
            
            if (app.Vehicle__c != null && app.Vehicle__r != null) {
                // Populate Year/Make/Model if available
                if (app.Vehicle__r.Year__c != null || app.Vehicle__r.Make__c != null || app.Vehicle__r.Model__c != null) {
                    String yearMakeModel = String.valueOf(app.Vehicle__r.Year__c != null ? app.Vehicle__r.Year__c : '') + ' ' +
                                         String.valueOf(app.Vehicle__r.Make__c != null ? app.Vehicle__r.Make__c : '') + ' ' +
                                         String.valueOf(app.Vehicle__r.Model__c != null ? app.Vehicle__r.Model__c : '');
                    data.vehicle.specifications.yearMakeModel = yearMakeModel.trim();
                    data.vehicle.specifications.year = app.Vehicle__r.Year__c != null ? String.valueOf(app.Vehicle__r.Year__c) : '';
                    data.vehicle.specifications.make = app.Vehicle__r.Make__c != null ? app.Vehicle__r.Make__c : '';
                    data.vehicle.specifications.model = app.Vehicle__r.Model__c != null ? app.Vehicle__r.Model__c : '';
                }
                
                data.vehicle.specifications.vin = app.Vehicle__r.VIN__c != null ? app.Vehicle__r.VIN__c : '';
                data.vehicle.specifications.odometer = app.Vehicle__r.Odometer__c != null ? String.valueOf(app.Vehicle__r.Odometer__c) : '';
                data.vehicle.specifications.odometerUnit = app.Vehicle__r.Odometer_Unit__c != null ? app.Vehicle__r.Odometer_Unit__c : '';
                data.vehicle.specifications.purchasePrice = app.Vehicle__r.Vehicle_Purchase_Price__c != null ? app.Vehicle__r.Vehicle_Purchase_Price__c : 0;
                data.vehicle.specifications.formattedPurchasePrice = app.Vehicle__r.Vehicle_Purchase_Price__c != null ? 
                    formatCurrency(app.Vehicle__r.Vehicle_Purchase_Price__c) : '$0.00';
                data.vehicle.specifications.purchaseDate = app.Vehicle__r.Purchase_Date__c != null ? 
                    app.Vehicle__r.Purchase_Date__c.format() : '';
                data.vehicle.specifications.deliveryDate = app.Vehicle__r.Delivery_Date__c != null ? 
                    app.Vehicle__r.Delivery_Date__c.format() : '';
                data.vehicle.specifications.commercialBusinessUse = app.Vehicle__r.Type_Of_Commercial_Use__c != null ? app.Vehicle__r.Type_Of_Commercial_Use__c : '';
                data.vehicle.specifications.engine = app.Vehicle__r.Engine__c != null ? app.Vehicle__r.Engine__c : '';
                data.vehicle.specifications.transmission = app.Vehicle__r.Transmission__c != null ? app.Vehicle__r.Transmission__c : '';
                data.vehicle.specifications.fuelType = app.Vehicle__r.Fuel_Type__c != null ? app.Vehicle__r.Fuel_Type__c : '';
                data.vehicle.specifications.drive = app.Vehicle__r.Drive_Type__c != null ? app.Vehicle__r.Drive_Type__c : '';
                data.vehicle.specifications.bodyType = app.Vehicle__r.Body_Type__c != null ? app.Vehicle__r.Body_Type__c : '';
                data.vehicle.specifications.color = app.Vehicle__r.Color__c != null ? app.Vehicle__r.Color__c : '';
                data.vehicle.specifications.gvwr = app.Vehicle__r.GVWR__c != null ? String.valueOf(app.Vehicle__r.GVWR__c) : '';
                
                data.vehicle.warranty.factoryWarrantyType = app.Vehicle__r.Manufacturer_Warranty_Type__c != null ? app.Vehicle__r.Manufacturer_Warranty_Type__c : '';
                data.vehicle.warranty.coverageTerm = app.Vehicle__r.Warranty_Term__c != null ? app.Vehicle__r.Warranty_Term__c : '';
                data.vehicle.warranty.inServiceDate = app.Vehicle__r.In_Service_Date__c != null ? String.valueOf(app.Vehicle__r.In_Service_Date__c) : '';
                
                data.vehicle.tireRimDetails = getTireRimDetails(applicationId);
            }
            
            data.applicationPackages = getApplicationPackagesForSummary(applicationId);
            
            return data;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving application summary: ' + e.getMessage());
        }
    }
    
    /**
     * @description Get Application Packages for Summary Display
     */
    private static List<ApplicationPackageRecordTypeWrapper> getApplicationPackagesForSummary(Id applicationId) {
        Map<String, ApplicationPackageRecordTypeWrapper> recordTypeMap = new Map<String, ApplicationPackageRecordTypeWrapper>();
        
        try {
            List<Application_Package__c> packages = [
                SELECT Id, Name, RecordType.Name, Coverage_Plan__c, Coverage_Term__c,
                        Package__r.Name, Package_Term__r.Name,
                        Deductible__c, Tax_Amount__c,Tax_Amount_Cost__c, Total_Package_Price__c, Contract_Premium_Price__c,Contract_Premium_Price_Without_Tax__c,
                        Contract_Cost_Price_Without_Tax__c, Contract_Cost_Price__c,
                        Dealer_Price_Override__c, Tax_Percentage__c,
                       Contract_Start_Date__c, Contract_End_Date__c, 
                       Odometer_Start__c, Odometer_End__c, Odometer_Start_Unit__c, Odometer_End_Unit__c
                FROM Application_Package__c
                WHERE Application__c = :applicationId AND Active__c = true
                ORDER BY RecordType.Name ASC, CreatedDate ASC
            ];
            
            Set<Id> packageIds = new Set<Id>();
            for (Application_Package__c pkg : packages) {
                packageIds.add(pkg.Id);
            }
            
            Map<Id, List<String>> packageOptionsMap = new Map<Id, List<String>>();
            if (!packageIds.isEmpty()) {
                List<Application_Package_Option__c> options = [
                    SELECT Id, Option__c, Application_Package__c
                    FROM Application_Package_Option__c 
                    WHERE Selection_Type__c = 'Included' AND Application_Package__c IN :packageIds
                ];
                
                for (Application_Package_Option__c option : options) {
                    if (!packageOptionsMap.containsKey(option.Application_Package__c)) {
                        packageOptionsMap.put(option.Application_Package__c, new List<String>());
                    }
                    packageOptionsMap.get(option.Application_Package__c).add(option.Option__c);
                }
            }
            
            for (Application_Package__c pkg : packages) {
                String recordTypeName = pkg.RecordType.Name;
                
                if (!recordTypeMap.containsKey(recordTypeName)) {
                    recordTypeMap.put(recordTypeName, new ApplicationPackageRecordTypeWrapper(recordTypeName));
                }
                
                ApplicationPackageWrapper pkgWrapper = new ApplicationPackageWrapper();
                
                String packageName = String.isNotBlank(pkg.Name) ? pkg.Name : '';
                pkgWrapper.packageHeaderName = recordTypeName + ' - ' + packageName;
                
                pkgWrapper.planName = pkg.Package__r != null && String.isNotBlank(pkg.Package__r.Name) ? pkg.Package__r.Name : pkg.Coverage_Plan__c;
                pkgWrapper.coverageTerm = pkg.Package_Term__r != null && String.isNotBlank(pkg.Package_Term__r.Name) ? pkg.Package_Term__r.Name : '';
                
                if (pkg.Dealer_Price_Override__c != null) {
                    pkgWrapper.retailCost = pkg.Dealer_Price_Override__c;
                    pkgWrapper.formattedRetailCost = formatCurrency(pkg.Dealer_Price_Override__c);
                    pkgWrapper.tax = pkg.Tax_Amount__c;
                    pkgWrapper.formattedTax = formatCurrency(pkg.Tax_Amount__c);
                    pkgWrapper.taxRate = pkg.Tax_Percentage__c;
                    pkgWrapper.formattedTaxRate = pkg.Tax_Percentage__c != null ? String.valueOf(pkg.Tax_Percentage__c.setScale(2)) + '%' : '0%';
                    pkgWrapper.total = pkg.Contract_Premium_Price__c;
                    pkgWrapper.formattedTotal = formatCurrency(pkg.Contract_Premium_Price__c);
                } else {
                    pkgWrapper.retailCost = pkg.Contract_Premium_Price_Without_Tax__c;
                    pkgWrapper.formattedRetailCost = pkg.Contract_Premium_Price_Without_Tax__c != null ? 
                        formatCurrency(pkg.Contract_Premium_Price_Without_Tax__c) : '$0.00';
                    pkgWrapper.tax = pkg.Tax_Amount__c;
                    pkgWrapper.formattedTax = formatCurrency(pkg.Tax_Amount__c);
                    pkgWrapper.taxRate = pkg.Tax_Percentage__c;
                    pkgWrapper.formattedTaxRate = pkg.Tax_Percentage__c != null ? String.valueOf(pkg.Tax_Percentage__c.setScale(2)) + '%' : '0%';
                    pkgWrapper.total = pkg.Contract_Premium_Price__c;
                    pkgWrapper.formattedTotal = formatCurrency(pkg.Contract_Premium_Price__c);
                }
                
                pkgWrapper.deductible = pkg.Deductible__c;
                pkgWrapper.formattedDeductible = pkg.Deductible__c != null ? 
                    formatCurrency(pkg.Deductible__c) : '$0.00';
                
                pkgWrapper.contractStartDate = pkg.Contract_Start_Date__c != null ? 
                    pkg.Contract_Start_Date__c.format() : '';
                pkgWrapper.contractExpiryDate = formatDate(pkg.Contract_End_Date__c);
                
                pkgWrapper.contractStartOdometer = pkg.Odometer_Start__c;
                pkgWrapper.contractExpiryOdometer = pkg.Odometer_End__c;
                pkgWrapper.contractStartOdometerUnit = pkg.Odometer_Start_Unit__c != null ? pkg.Odometer_Start_Unit__c : 'KM';
                pkgWrapper.contractExpiryOdometerUnit = pkg.Odometer_End_Unit__c != null ? pkg.Odometer_End_Unit__c : 'KM';
                
                pkgWrapper.additionalOptionsPurchased = packageOptionsMap.containsKey(pkg.Id) ? 
                    packageOptionsMap.get(pkg.Id) : new List<String>();
                
                recordTypeMap.get(recordTypeName).packages.add(pkgWrapper);
            }
            
        } catch (Exception e) {
            System.debug('Error retrieving application packages: ' + e.getMessage());
        }
        
        List<ApplicationPackageRecordTypeWrapper> result = new List<ApplicationPackageRecordTypeWrapper>();
        for (String key : recordTypeMap.keySet()) {
            result.add(recordTypeMap.get(key));
        }
        return result;
    }    

    @AuraEnabled
    public static ApplicationPackageData getApplicationPackageData(Id applicationId) {
        try {
            Application__c app = [SELECT Id FROM Application__c WHERE Id = :applicationId LIMIT 1];
            ApexPages.StandardController stdController = new ApexPages.StandardController(app);
            
            ApplicationPDFExtension pdfExtension = new ApplicationPDFExtension(stdController);
            
            ApplicationPackageData packageData = new ApplicationPackageData();
            packageData.dealerLogoUrl = pdfExtension.dealerLogoUrl;
            packageData.hasDealerLogo = pdfExtension.hasDealerLogo;
            
            for (ApplicationPDFExtension.RecordTypeWrapper rtWrapper : pdfExtension.recordTypeWrappersList) {
                RecordTypeWrapperDTO rtDTO = new RecordTypeWrapperDTO(rtWrapper.recordTypeName);
                
                for (ApplicationPDFExtension.PackageWrapper pkgWrapper : rtWrapper.packages) {
                    PackageWrapperDTO pkgDTO = new PackageWrapperDTO();
                    pkgDTO.pkg = pkgWrapper.pkg;
                    pkgDTO.includedOptions = pkgWrapper.includedOptions;
                    pkgDTO.optionalOptions = pkgWrapper.optionalOptions;
                    pkgDTO.inclusionsList = pkgWrapper.inclusionsList;
                    pkgDTO.exclusionsList = pkgWrapper.exclusionsList;
                    pkgDTO.packageLogoUrl = pkgWrapper.packageLogoUrl;
                    pkgDTO.hasPackageLogo = pkgWrapper.hasPackageLogo;
                    
                    rtDTO.packages.add(pkgDTO);
                }
                
                packageData.recordTypeWrappers.add(rtDTO);
            }
            
            return packageData;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving application package data: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Application_Package_Option__c> getIncludedOptions(Id applicationId) {
        return [
            SELECT Id, Option__c, Package_Option__r.Name, Package_Option__r.Price__c
            FROM Application_Package_Option__c 
            WHERE Application__c = :applicationId 
            AND Selection_Type__c = 'Included'
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Application_Package_Option__c> getOptionalOptions(Id applicationId) {
        return [
            SELECT Id, Option__c, Package_Option__r.Name, Package_Option__r.Price__c
            FROM Application_Package_Option__c 
            WHERE Application__c = :applicationId 
            AND Selection_Type__c = 'Optional'
        ];
    }

    /**
     * @description Generate and attach versioned PDFs for each package record type.
     * File naming: {RecordTypeLabel}_{YYYY-MM-DD}_v{N}.pdf
     * Each call creates new versioned files; all previous versions remain on the record.
     */
    @AuraEnabled
    public static PDFResponse generateAndAttachPDF(Id applicationId) {
        PDFResponse response = new PDFResponse();

        try {
            // Collect record types for this application
            Set<String> recordTypeSet = new Set<String>();
            for (Application_Package__c pkg : [
                SELECT Package_Record_Type__c
                FROM Application_Package__c
                WHERE Application__c = :applicationId
                  AND Active__c = true
            ]) {
                String rt = String.isBlank(pkg.Package_Record_Type__c) ? 'Other' : pkg.Package_Record_Type__c;
                recordTypeSet.add(rt);
            }

            if (recordTypeSet.isEmpty()) {
                recordTypeSet.add('');
            }

            List<String> recordTypes = new List<String>(recordTypeSet);

            // ── VERSION TRACKING ──
            // Query existing PDF files attached to this application to determine next version number
            String todayStr = Date.today().year() + '-' +
                              String.valueOf(Date.today().month()).leftPad(2, '0') + '-' +
                              String.valueOf(Date.today().day()).leftPad(2, '0');

            Map<String, Integer> maxVersionByType = new Map<String, Integer>();
            List<ContentDocumentLink> existingLinks = [
                SELECT ContentDocument.Title
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :applicationId
            ];
            for (ContentDocumentLink cdl : existingLinks) {
                String title = cdl.ContentDocument.Title;
                if (title == null) continue;
                // Parse titles like "Extended_Limited_Warranty_2026-05-19_v3"
                for (String rtName : recordTypes) {
                    String rtLabel = resolvePackageRecordTypeLabel(rtName);
                    String rtSuffix = (String.isBlank(rtLabel) ? 'All' : rtLabel).replaceAll('[^A-Za-z0-9_\\-]', '_');
                    String prefix = rtSuffix + '_' + todayStr + '_v';
                    if (title.startsWith(prefix)) {
                        String vStr = title.substring(prefix.length());
                        try {
                            Integer v = Integer.valueOf(vStr);
                            Integer current = maxVersionByType.containsKey(rtName) ? maxVersionByType.get(rtName) : 0;
                            if (v > current) {
                                maxVersionByType.put(rtName, v);
                            }
                        } catch (Exception ex) {
                            // not a version number, skip
                        }
                    }
                }
            }

            List<ContentVersion> versionsToInsert = new List<ContentVersion>();

            for (String rtName : recordTypes) {
                String rtLabel = resolvePackageRecordTypeLabel(rtName);
                PageReference pdfPage = Page.DealerPortalVehicleApplicationPDFs;
                pdfPage.getParameters().put('id', applicationId);
                if (String.isNotBlank(rtName)) {
                    pdfPage.getParameters().put('rt', rtName);
                }
                pdfPage.getParameters().put('sfdc.override', '1');
                pdfPage.getParameters().put('core.apexpages.request.devconsole', '1');

                Blob pdfBlob;
                if (Test.isRunningTest()) {
                    pdfBlob = Blob.valueOf('Test PDF Content for Application: ' + applicationId + ' RT: ' + rtName);
                } else {
                    pdfBlob = pdfPage.getContentAsPDF();
                }

                // Determine next version number
                Integer nextVersion = (maxVersionByType.containsKey(rtName) ? maxVersionByType.get(rtName) : 0) + 1;

                String rtSuffixRaw = String.isBlank(rtLabel) ? 'All' : rtLabel;
                String rtSuffix = rtSuffixRaw.replaceAll('[^A-Za-z0-9_\\-]', '_');
                String versionedTitle = rtSuffix + '_' + todayStr + '_v' + nextVersion;
                String versionedFileName = versionedTitle + '.pdf';

                ContentVersion cv = new ContentVersion();
                cv.Title = versionedTitle;
                cv.PathOnClient = versionedFileName;
                cv.VersionData = pdfBlob;
                cv.FirstPublishLocationId = applicationId;
                cv.IsMajorVersion = true;
                versionsToInsert.add(cv);
            }

            insert versionsToInsert;

            Set<Id> cvIds = new Set<Id>();
            for (ContentVersion cv : versionsToInsert) {
                cvIds.add(cv.Id);
            }

            List<ContentVersion> inserted = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id IN :cvIds];
            String firstDocId;
            for (ContentVersion cv : inserted) {
                if (firstDocId == null) {
                    firstDocId = cv.ContentDocumentId;
                }
            }

            response.success = true;
            response.message = 'PDFs generated and attached successfully';
            response.attachmentId = firstDocId;

        } catch (Exception e) {
            response.success = false;
            response.message = 'Error generating PDFs: ' + e.getMessage();
            System.debug('PDF Generation Error: ' + e.getMessage() + ' | Stack: ' + e.getStackTraceString());
        }

        return response;
    }

    /**
     * @description Generate and attach a versioned PDF for a single package record type.
     * Called from the per-package PDF button on the summary page.
     */
    @AuraEnabled
    public static PDFResponse generatePDFForPackageRecordType(Id applicationId, String recordTypeName) {
        PDFResponse response = new PDFResponse();

        try {
            if (String.isBlank(recordTypeName)) {
                recordTypeName = '';
            }

            // ── VERSION TRACKING ──
            String todayStr = Date.today().year() + '-' +
                              String.valueOf(Date.today().month()).leftPad(2, '0') + '-' +
                              String.valueOf(Date.today().day()).leftPad(2, '0');

            String rtLabel = resolvePackageRecordTypeLabel(recordTypeName);
            String rtSuffix = (String.isBlank(rtLabel) ? 'All' : rtLabel).replaceAll('[^A-Za-z0-9_\\-]', '_');
            String prefix = rtSuffix + '_' + todayStr + '_v';

            Integer maxVersion = 0;
            List<ContentDocumentLink> existingLinks = [
                SELECT ContentDocument.Title
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :applicationId
            ];
            for (ContentDocumentLink cdl : existingLinks) {
                String title = cdl.ContentDocument.Title;
                if (title != null && title.startsWith(prefix)) {
                    String vStr = title.substring(prefix.length());
                    try {
                        Integer v = Integer.valueOf(vStr);
                        if (v > maxVersion) {
                            maxVersion = v;
                        }
                    } catch (Exception ex) {
                        // not a version number, skip
                    }
                }
            }

            PageReference pdfPage = Page.DealerPortalVehicleApplicationPDFs;
            pdfPage.getParameters().put('id', applicationId);
            if (String.isNotBlank(recordTypeName)) {
                pdfPage.getParameters().put('rt', recordTypeName);
            }
            pdfPage.getParameters().put('sfdc.override', '1');
            pdfPage.getParameters().put('core.apexpages.request.devconsole', '1');

            Blob pdfBlob;
            if (Test.isRunningTest()) {
                pdfBlob = Blob.valueOf('Test PDF Content for Application: ' + applicationId + ' RT: ' + recordTypeName);
            } else {
                pdfBlob = pdfPage.getContentAsPDF();
            }

            Integer nextVersion = maxVersion + 1;
            String versionedTitle = rtSuffix + '_' + todayStr + '_v' + nextVersion;
            String versionedFileName = versionedTitle + '.pdf';

            ContentVersion cv = new ContentVersion();
            cv.Title = versionedTitle;
            cv.PathOnClient = versionedFileName;
            cv.VersionData = pdfBlob;
            cv.FirstPublishLocationId = applicationId;
            cv.IsMajorVersion = true;
            insert cv;

            ContentVersion inserted = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

            response.success = true;
            response.message = 'PDF generated successfully for ' + (String.isBlank(rtLabel) ? 'All' : rtLabel);
            response.attachmentId = inserted.ContentDocumentId;
            response.fileName = versionedFileName;

        } catch (Exception e) {
            response.success = false;
            response.message = 'Error generating PDF: ' + e.getMessage();
            System.debug('PDF Generation Error (single RT): ' + e.getMessage() + ' | Stack: ' + e.getStackTraceString());
        }

        return response;
    }

    // Map record type name/developer name to label for filenames
    private static String resolvePackageRecordTypeLabel(String rtName) {
        if (String.isBlank(rtName)) {
            return 'All';
        }
        try {
            Schema.DescribeSObjectResult describe = Application_Package__c.SObjectType.getDescribe();
            Map<String, Schema.RecordTypeInfo> byName = describe.getRecordTypeInfosByName();
            if (byName != null && byName.containsKey(rtName)) {
                return byName.get(rtName).getName();
            }
            Map<String, Schema.RecordTypeInfo> byDevName = describe.getRecordTypeInfosByDeveloperName();
            if (byDevName != null && byDevName.containsKey(rtName)) {
                return byDevName.get(rtName).getName();
            }
        } catch (Exception e) {
            // ignore and fall through
        }
        return rtName;
    }

    @AuraEnabled
    public static PDFResponse getPDFContentBase64(Id contentDocumentId) {
        PDFResponse response = new PDFResponse();
        try {
            ContentVersion cv = [SELECT VersionData, PathOnClient FROM ContentVersion WHERE ContentDocumentId = :contentDocumentId ORDER BY CreatedDate DESC LIMIT 1];
            if (cv != null && cv.VersionData != null) {
                response.success = true;
                response.message = 'PDF content retrieved successfully';
                response.attachmentId = EncodingUtil.base64Encode(cv.VersionData);
                response.fileName = cv.PathOnClient;
            } else {
                response.success = false;
                response.message = 'PDF content not found or is empty.';
            }
        } catch (Exception e) {
            response.success = false;
            response.message = 'Error retrieving PDF content: ' + e.getMessage();
            System.debug('getPDFContentBase64 Error: ' + e.getMessage() + ' | Stack: ' + e.getStackTraceString());
        }
        return response;
    }

    // VM class for VF page (preserved from original)
    public class VM {
        public String applicationId { get; set; }
        public String applicationName { get; set; }
        public String firstName { get; set; }
        public String lastName { get; set; }
        public String email { get; set; }
        public String homePhone { get; set; }
        public String businessPhone { get; set; }
        public String address { get; set; }
        public String city { get; set; }
        public String province { get; set; }
        public String postalCode { get; set; }
        public String year { get; set; }
        public String make { get; set; }
        public String model { get; set; }
        public String vin { get; set; }
        public String odometer { get; set; }
        public Decimal purchasePrice { get; set; }
        public String purchasePriceFmt { get { return formatCurrency(purchasePrice); } }
        public String dealerName { get; set; }
        public String dealerCode { get; set; }
        public String dealerPhone { get; set; }
        public String dealerAddress { get; set; }
        public String programName { get; set; }
        public String coverageTerm { get; set; }
        public String amountFinancedBracket { get; set; }
        public Decimal charge { get; set; }
        public Decimal tax { get; set; }
        public Decimal total { get; set; }
        public String chargeFmt { get { return formatCurrency(charge); } }
        public String taxFmt { get { return formatCurrency(tax); } }
        public String totalFmt { get { return formatCurrency(total); } }
        public Date purchaseDate { get; set; }
        public Date expirationDate { get; set; }
        public String purchaseDateFmt { get { return formatDate(purchaseDate); } }
        public String expirationDateFmt { get { return formatDate(expirationDate); } }
        public String financialInstitutionNote { get; set; }
        public String amountFinancedRange { get; set; }
        public String financialInstitution { get; set; }
    }

    public VM vm { get; private set; }

    // VF page constructor (preserved)
    public ApplicationSummaryController() {
        Id appId = ApexPages.currentPage().getParameters().get('id');
        if (appId == null) {
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR,'Missing id parameter'));
            vm = new VM();
            return;
        }

        Application__c app = [
            SELECT Id, Name,
                   Customer_Name__c,Customer_First_Name__c, Customer_Last_Name__c, Customer_Email__c, 
                   Customer_Home_Phone__c, Customer_Business_Phone__c,
                   Customer_Name__r.BillingStreet,Customer_Name__r.BillingCity, Customer_Name__r.BillingState, Customer_Name__r.BillingPostalCode,
                   Vehicle__c,Vehicle_Year__c, Vehicle_Make__c, Vehicle_Model__c, Vehicle_VIN__c, 
                   Odometer__c, Vehicle_Purchase_Price__c,Odometer_Unit__c,
                   Dealer_Name__c, Dealer_Code__c, Dealer_Phone__c,
                   Dealer_Name__r.BillingStreet, Dealer_Name__r.BillingCity, Dealer_Name__r.BillingState, Dealer_Name__r.BillingPostalCode
            FROM Application__c
            WHERE Id = :appId
            LIMIT 1
        ];

        vm = new VM();
        vm.applicationId = app.Id;
        vm.applicationName = app.Name;
        vm.firstName = app.Customer_First_Name__c;
        vm.lastName = app.Customer_Last_Name__c;
        vm.email = app.Customer_Email__c;
        vm.homePhone = app.Customer_Home_Phone__c;
        vm.businessPhone = app.Customer_Business_Phone__c;
        vm.address = app.Customer_Name__r.BillingStreet;
        vm.city = app.Customer_Name__r.BillingCity;
        vm.province = app.Customer_Name__r.BillingState;
        vm.postalCode = app.Customer_Name__r.BillingPostalCode;
        vm.year = String.valueOf(app.Vehicle_Year__c);
        vm.make = app.Vehicle_Make__c;
        vm.model = app.Vehicle_Model__c;
        vm.vin = app.Vehicle_VIN__c;
        vm.odometer = String.valueOf(app.Odometer__c);
        vm.purchasePrice = app.Vehicle_Purchase_Price__c;
        vm.dealerName = app.Dealer_Name__c;
        vm.dealerCode = app.Dealer_Code__c;
        vm.dealerPhone = app.Dealer_Phone__c;
    }

    private static String formatCurrency(Decimal amount) {
        if (amount == null) {
            return '$0.00';
        }
        Decimal formatted = amount.setScale(2);
        return '$' + formatted.format();
    }

    private static String formatPercentage(Decimal amount) {
        if (amount == null) {
            return '0.00%';
        }
        Decimal formatted = amount.setScale(2);
        return formatted.format() + '%';
    }

    private static String formatTerms(Decimal terms) {
        if (terms == null) {
            return '';
        }
        return terms.format() + ' Months';
    }

    private static String formatDate(Date dt) {
        if (dt == null) return '';
        return dt.format();
    }

    private static String formatAddress(String city, String state, String postalCode, String country) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(city)) parts.add(city);
        if (String.isNotBlank(state)) parts.add(state);
        if (String.isNotBlank(postalCode)) parts.add(postalCode);
        if (String.isNotBlank(country)) parts.add(country);
        return String.join(parts, ', ');
    }

    private static TireRimDetails getTireRimDetails(Id applicationId) {
        TireRimDetails details = new TireRimDetails();
        try {
            List<Application_Package__c> tireRimPackages = [
                SELECT Id, Tire_Brand__c, Tire_Type__c, Tread_Depth__c, Tread_Depth_Unit__c,
                       Rim_Brand__c, Rim_Type__c, Rim_Size__c, Rim_Size_Unit__c, RecordType.DeveloperName
                FROM Application_Package__c
                WHERE Application__c = :applicationId 
                AND RecordType.DeveloperName = 'Tire_Rim_Protection_Plan'
                LIMIT 1
            ];
            if (!tireRimPackages.isEmpty()) {
                Application_Package__c pkg = tireRimPackages[0];
                details.tireBrand = pkg.Tire_Brand__c != null ? pkg.Tire_Brand__c : '';
                details.tireType = pkg.Tire_Type__c != null ? pkg.Tire_Type__c : '';
                details.treadDepth = pkg.Tread_Depth__c != null ? String.valueOf(pkg.Tread_Depth__c) : '';
                details.treadDepthUnit = pkg.Tread_Depth_Unit__c != null ? pkg.Tread_Depth_Unit__c : '';
                details.rimBrand = pkg.Rim_Brand__c != null ? pkg.Rim_Brand__c : '';
                details.rimType  = pkg.Rim_Type__c  != null ? pkg.Rim_Type__c  : '';
                details.rimSize = pkg.Rim_Size__c != null ? String.valueOf(pkg.Rim_Size__c) : '';
                details.rimSizeUnit = pkg.Rim_Size_Unit__c != null ? pkg.Rim_Size_Unit__c : '';
            }
        } catch (Exception e) {
            System.debug('Error retrieving Tire & Rim details: ' + e.getMessage());
        }
        return details;
    }

    @AuraEnabled
    public static List<PDFFileWrapper> getAttachedPDFs(Id applicationId) {
        List<PDFFileWrapper> pdfFiles = new List<PDFFileWrapper>();
        try {
            List<ContentDocumentLink> docLinks = [
                SELECT ContentDocumentId, ContentDocument.Title, ContentDocument.CreatedDate
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :applicationId
                ORDER BY ContentDocument.CreatedDate DESC
            ];
            Set<Id> docIds = new Set<Id>();
            for (ContentDocumentLink link : docLinks) {
                docIds.add(link.ContentDocumentId);
            }
            Map<Id, ContentVersion> versionMap = new Map<Id, ContentVersion>();
            for (ContentVersion cv : [
                SELECT Id, ContentDocumentId, VersionData, Title, FileType
                FROM ContentVersion
                WHERE ContentDocumentId IN :docIds
                AND IsLatest = true
            ]) {
                versionMap.put(cv.ContentDocumentId, cv);
            }
            for (ContentDocumentLink link : docLinks) {
                ContentVersion cv = versionMap.get(link.ContentDocumentId);
                pdfFiles.add(new PDFFileWrapper(
                    link.ContentDocumentId,
                    cv != null ? cv.Id : '',
                    link.ContentDocument.Title,
                    link.ContentDocument.CreatedDate.format()
                ));
            }
        } catch (Exception e) {
            System.debug('Error getting attached PDFs: ' + e.getMessage());
            throw new AuraHandledException('Failed to retrieve PDFs: ' + e.getMessage());
        }
        return pdfFiles;
    }

    @AuraEnabled
    public static PDFEmailResponse sendPDFByEmail(String contentDocumentId, String recipientEmail, String subject, Id applicationId) {
        PDFEmailResponse response = new PDFEmailResponse();
        try {
            if (String.isBlank(contentDocumentId) || String.isBlank(recipientEmail)) {
                throw new IllegalArgumentException('Missing required parameters');
            }
            List<ContentVersion> versions = [
                SELECT Id, VersionData, Title, FileType
                FROM ContentVersion
                WHERE ContentDocumentId = :contentDocumentId
                AND IsLatest = true
                LIMIT 1
            ];
            if (versions.isEmpty()) {
                throw new IllegalArgumentException('PDF file not found');
            }
            ContentVersion cv = versions[0];
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new String[] { recipientEmail });
            mail.setSubject(subject);
            mail.setPlainTextBody('Please find the attached application PDF.');
            Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
            attachment.setFileName(cv.Title + '.' + cv.FileType);
            attachment.setBody(cv.VersionData);
            mail.setFileAttachments(new Messaging.EmailFileAttachment[] { attachment });
            Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
            if (results[0].isSuccess()) {
                response.success = true;
                response.message = 'Email sent successfully';
            } else {
                response.success = false;
                response.message = results[0].getErrors()[0].getMessage();
            }
        } catch (Exception e) {
            response.success = false;
            response.message = 'Error sending email: ' + e.getMessage();
            System.debug('Email send error: ' + e.getMessage());
        }
        return response;
    }

    @AuraEnabled
    public static String getPDFDataUrl(String contentVersionId) {
        try {
            if (String.isBlank(contentVersionId)) {
                throw new IllegalArgumentException('ContentVersionId is required');
            }
            ContentVersion cv = [
                SELECT VersionData
                FROM ContentVersion
                WHERE Id = :contentVersionId
                LIMIT 1
            ];
            String base64PDF = EncodingUtil.base64Encode(cv.VersionData);
            return 'data:application/pdf;base64,' + base64PDF;
        } catch (Exception e) {
            System.debug('Error getting PDF data URL: ' + e.getMessage());
            throw new AuraHandledException('Failed to retrieve PDF: ' + e.getMessage());
        }
    }

    public class PDFFileWrapper {
        @AuraEnabled public String contentDocumentId { get; set; }
        @AuraEnabled public String contentVersionId { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String createdDate { get; set; }
        @AuraEnabled public String base64PDF { get; set; }
        
        public PDFFileWrapper(String contentDocumentId, String contentVersionId, String title, String createdDate) {
            this.contentDocumentId = contentDocumentId;
            this.contentVersionId = contentVersionId;
            this.title = title;
            this.createdDate = createdDate;
            this.base64PDF = null;
        }
    }

    public class PDFEmailResponse {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
    }
    
    @AuraEnabled
    public static InvoiceOperationResult createInvoiceOnApplicationSubmit(String applicationId) {
        try {
            if (String.isBlank(applicationId)) {
                return new InvoiceOperationResult(false, 'Application ID is required');
            }
            List<Application__c> applicationsWithDealer = [
                SELECT Id, Name, Dealer_Name__r.Name, Dealer_Name__c,
                       (SELECT Id, Name FROM Application_Packages__r WHERE Active__c = true)
                FROM Application__c
                WHERE Id = :applicationId
                LIMIT 1
            ];
            if (applicationsWithDealer.isEmpty()) {
                return new InvoiceOperationResult(false, 'Application not found');
            }
            Application__c application = applicationsWithDealer[0];
            List<Application_Package__c> activePackages = application.Application_Packages__r;
            if (activePackages.isEmpty()) {
                return new InvoiceOperationResult(false, 'No active packages found for this application');
            }
            Invoice__c newInvoice = new Invoice__c();
            newInvoice.Application__c = applicationId;
            newInvoice.Status__c = 'Due';
            if (String.isNotBlank(application.Name)) {
                newInvoice.Name = application.Name.replaceAll('APP', 'INV');
            }
            try {
                Dealer_Portal_Configs__mdt config = Dealer_Portal_Configs__mdt.getInstance('A_Protect_Configs');
                if (config != null) {
                    Date dueDate = Date.today();
                    if (config.Invoice_Due_Duration_Type__c == 'Days') {
                        dueDate = dueDate.addDays(config.Invoice_Due_Duration__c.intValue());
                    } else if (config.Invoice_Due_Duration_Type__c == 'Months') {
                        dueDate = dueDate.addMonths(config.Invoice_Due_Duration__c.intValue());
                    }
                    newInvoice.Invoice_Due_Date__c = dueDate;
                }
            } catch (Exception metadataError) {
                System.debug('Error processing custom metadata for Invoice_Due_Date__c: ' + metadataError.getMessage());
            }
            insert newInvoice;
            List<Invoice_Line_Item__c> lineItems = new List<Invoice_Line_Item__c>();
            for (Application_Package__c pkg : activePackages) {
                Invoice_Line_Item__c lineItem = new Invoice_Line_Item__c();
                lineItem.Invoice__c = newInvoice.Id;
                lineItem.Application_Package__c = pkg.Id;
                lineItem.Status__c = 'Due';
                if (String.isNotBlank(pkg.Name)) {
                    lineItem.Name = pkg.Name.replaceAll('APP', 'INV');
                }
                lineItems.add(lineItem);
            }
            if (!lineItems.isEmpty()) {
                insert lineItems;
            }
            return new InvoiceOperationResult(true, 'Invoice created successfully for submitted application', newInvoice.Id);
        } catch (Exception e) {
            System.debug('ApplicationSummaryController createInvoiceOnApplicationSubmit error: ' + e.getMessage());
            return new InvoiceOperationResult(false, 'Error creating invoice: ' + e.getMessage());
        }
    }
    
    public class InvoiceOperationResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String invoiceId { get; set; }
        
        public InvoiceOperationResult(Boolean success, String message) {
            this.success = success;
            this.message = message;
            this.invoiceId = null;
        }
        
        public InvoiceOperationResult(Boolean success, String message, String invoiceId) {
            this.success = success;
            this.message = message;
            this.invoiceId = invoiceId;
        }
    }

    /**
     * @description Get the invoice associated with an application (if any)
     * @param applicationId The Application record Id
     * @return Map with invoiceId and invoiceName, or null if no invoice exists
     */
    @AuraEnabled(cacheable=false)
    public static Map<String, String> getInvoiceForApplication(String applicationId) {
        if (String.isBlank(applicationId)) {
            return null;
        }
        List<Invoice__c> invoices = [
            SELECT Id, Name 
            FROM Invoice__c 
            WHERE Application__c = :applicationId 
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (invoices.isEmpty()) {
            return null;
        }
        Map<String, String> result = new Map<String, String>();
        result.put('invoiceId', invoices[0].Id);
        result.put('invoiceName', invoices[0].Name);
        return result;
    }

}