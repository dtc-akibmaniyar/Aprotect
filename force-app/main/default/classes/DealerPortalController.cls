public without sharing class DealerPortalController {



public class ApplicationDataDTO {
    @AuraEnabled public String Id;
    @AuraEnabled public String Name;
    @AuraEnabled public DateTime CreatedDate;
    @AuraEnabled public String Status;
    @AuraEnabled public String VehicleName;
    @AuraEnabled public Date PaymentDueDate;
    
    public ApplicationDataDTO() {}
}


public class ApplicationsResponse {
    @AuraEnabled public Boolean success;
    @AuraEnabled public String message;
    @AuraEnabled public List<ApplicationDataDTO> data;
    @AuraEnabled public Integer totalCount;
    
    public ApplicationsResponse() {}
}


public class VehicleDataDTO {

    @AuraEnabled public String stockNumber;
    @AuraEnabled public String vin;
    @AuraEnabled public String vehicleIdentificationNumberVIN;
    @AuraEnabled public String year;
    @AuraEnabled public String make;
    @AuraEnabled public String model;
    @AuraEnabled public String modelClass;
    @AuraEnabled public String trim;
    @AuraEnabled public String dateVehicleSold;
    @AuraEnabled public Decimal vehiclePurchasePrice;
    @AuraEnabled public Boolean brandedRebuilt;
    @AuraEnabled public String inServiceDate;
    @AuraEnabled public Decimal odometer;
    @AuraEnabled public String odometerUnit;
    @AuraEnabled public Boolean businessCommercialUse;
    @AuraEnabled public Boolean isVehicleFinanced;
    @AuraEnabled public String typeOfCommercialUse;
    

    @AuraEnabled public String engine;
    @AuraEnabled public String transmission;
    @AuraEnabled public String bodyStyle;
    @AuraEnabled public String color;
    

    @AuraEnabled public String manufacturerWarrantyType;
    @AuraEnabled public String warrantyTerm;
    @AuraEnabled public String warrantyInServiceDate;
    @AuraEnabled public Boolean deferralOption;
    /** True when the active warranty Application_Package has a Dealer_Package_Term with Allow_Deferral__c = true. Used by the warranty tab to show the Deferral Option checkbox. */
    @AuraEnabled public Boolean packageTermAllowsDeferral;
    /** True when the manufacturer warranty has already expired (In_Service_Date + term duration <= today). Used by the warranty tab to disable the Deferral Option when expired. */
    @AuraEnabled public Boolean isManufacturerWarrantyExpired;
    @AuraEnabled public String deliveryDate;
    @AuraEnabled public String usageType;
    

    @AuraEnabled public String dealerCommentsNotes;
    @AuraEnabled public Boolean showCommentsOnPrint;
    @AuraEnabled public String salesRepId;
    @AuraEnabled public String salesRepName;
    @AuraEnabled public String dealerSalesId;
    @AuraEnabled public String lienHolder;
    @AuraEnabled public String dealershipName;
    @AuraEnabled public String dealershipAddress;
    @AuraEnabled public String cityProvincePostal;
    @AuraEnabled public String dealershipAccountId; // Account ID for loading contacts
    

    @AuraEnabled public String bodyClass;
    @AuraEnabled public String manufacturerName;
    @AuraEnabled public String vehicleType;
    @AuraEnabled public String vehicleSubType;
    @AuraEnabled public String series;
    @AuraEnabled public String style;
    @AuraEnabled public String origin;
    

    @AuraEnabled public String engineModel;
    @AuraEnabled public String engineCylinders;
    @AuraEnabled public String engineDisplacement;
    @AuraEnabled public String engineDisplacementCC;
    @AuraEnabled public String engineDisplacementCI;
    @AuraEnabled public String enginePower;
    @AuraEnabled public String enginePowerTo;
    @AuraEnabled public String engineStrokeCycles;
    @AuraEnabled public String engineConfiguration;
    @AuraEnabled public String engineManufacturer;
    @AuraEnabled public String engineBrakeFrom;
    @AuraEnabled public String engineBrakeTo;
    @AuraEnabled public String otherEngineInfo;
    @AuraEnabled public String turbo;
    @AuraEnabled public String topSpeed;
    @AuraEnabled public String electrificationLevel;
    @AuraEnabled public String coolingType;
    @AuraEnabled public String valveTrainDesign;
    

    @AuraEnabled public String transmissionStyle;
    @AuraEnabled public String transmissionSpeeds;
    @AuraEnabled public String driveType;
    @AuraEnabled public String axles;
    @AuraEnabled public String axleConfiguration;
    

    @AuraEnabled public String fuelType;
    @AuraEnabled public String fuelTypeSecondary;
    @AuraEnabled public String fuelDeliveryType;
    @AuraEnabled public String fuelTankType;
    @AuraEnabled public String fuelTankMaterial;
    

    @AuraEnabled public String doors;
    @AuraEnabled public String windows;
    @AuraEnabled public String wheelBase;
    @AuraEnabled public String wheelBaseFrom;
    @AuraEnabled public String wheelBaseTo;
    @AuraEnabled public String wheelBaseType;
    @AuraEnabled public String trackWidth;
    @AuraEnabled public String curbWeight;
    @AuraEnabled public String gvwr;
    @AuraEnabled public String gvwrFrom;
    @AuraEnabled public String gvwrTo;
    @AuraEnabled public String gcvwrFrom;
    @AuraEnabled public String gcvwrTo;
    @AuraEnabled public String bedLength;
    @AuraEnabled public String bedType;
    @AuraEnabled public String cabType;
    

    @AuraEnabled public String seats;
    @AuraEnabled public String seatRows;
    @AuraEnabled public String seatBeltType;
    @AuraEnabled public String otherRestraintSystemInfo;
    @AuraEnabled public String pretensioner;
    

    @AuraEnabled public String abs;
    @AuraEnabled public String esc;
    @AuraEnabled public String tractionControl;
    @AuraEnabled public String airbagLocations;
    @AuraEnabled public String frontAirbagLocations;
    @AuraEnabled public String sideAirbagLocations;
    @AuraEnabled public String curtainAirbagLocations;
    @AuraEnabled public String seatCushionAirbagLocations;
    @AuraEnabled public String kneeAirbagLocations;
    @AuraEnabled public String tpmsType;
    @AuraEnabled public String activeSafetySystemNote;
    

    @AuraEnabled public String adaptiveCruiseControl;
    @AuraEnabled public String crashImminentBraking;
    @AuraEnabled public String forwardCollisionWarning;
    @AuraEnabled public String dynamicBrakeSupport;
    @AuraEnabled public String pedestrianAutomaticEmergencyBraking;
    @AuraEnabled public String blindSpotWarning;
    @AuraEnabled public String laneDepartureWarning;
    @AuraEnabled public String laneKeepingAssistance;
    @AuraEnabled public String blindSpotIntervention;
    @AuraEnabled public String laneCenteringAssistance;
    @AuraEnabled public String backupCamera;
    @AuraEnabled public String parkingAssist;
    @AuraEnabled public String rearCrossTrafficAlert;
    @AuraEnabled public String rearAutomaticEmergencyBraking;
    @AuraEnabled public String automaticCrashNotification;
    @AuraEnabled public String daytimeRunningLight;
    @AuraEnabled public String headlampLightSource;
    @AuraEnabled public String semiautomaticHeadlampBeamSwitching;
    @AuraEnabled public String adaptiveDrivingBeam;
    @AuraEnabled public String autoReverseSystem;
    @AuraEnabled public String automaticPedestrianAlertingSound;
    @AuraEnabled public String eventDataRecorder;
    @AuraEnabled public String keylessIgnition;
    @AuraEnabled public String saeAutomationLevelFrom;
    @AuraEnabled public String saeAutomationLevelTo;
    

    @AuraEnabled public String brakeSystemType;
    @AuraEnabled public String brakeSystemDescription;
    @AuraEnabled public String combinedBrakingSystem;
    @AuraEnabled public String wheelieMitigation;
    

    @AuraEnabled public String numberOfWheels;
    @AuraEnabled public String wheelSizeFront;
    @AuraEnabled public String wheelSizeRear;
    

    @AuraEnabled public String batteryType;
    @AuraEnabled public String otherBatteryInfo;
    @AuraEnabled public String batteryCellsPerModule;
    @AuraEnabled public String batteryCurrentFrom;
    @AuraEnabled public String batteryVoltageFrom;
    @AuraEnabled public String batteryEnergyFrom;
    @AuraEnabled public String batteryCurrentTo;
    @AuraEnabled public String batteryVoltageTo;
    @AuraEnabled public String batteryEnergyTo;
    @AuraEnabled public String batteryModulesPerPack;
    @AuraEnabled public String batteryPacksPerVehicle;
    @AuraEnabled public String evDriveUnit;
    @AuraEnabled public String chargerLevel;
    @AuraEnabled public String chargerPower;
    

    @AuraEnabled public String entertainmentSystem;
    @AuraEnabled public String steeringLocation;
    

    @AuraEnabled public String plantCountry;
    @AuraEnabled public String plantState;
    @AuraEnabled public String plantCity;
    @AuraEnabled public String plantCompanyName;
    @AuraEnabled public String destinationMarket;
    @AuraEnabled public String nonLandUse;
    

    @AuraEnabled public String trim2;
    @AuraEnabled public String series2;
    @AuraEnabled public String note;
    @AuraEnabled public String basePrice;
    @AuraEnabled public String vehicleDescriptor;
    @AuraEnabled public String suggestedVin;
    @AuraEnabled public String errorCode;
    @AuraEnabled public String possibleValues;
    @AuraEnabled public String additionalErrorText;
    @AuraEnabled public String errorText;
    

    @AuraEnabled public String trailerTypeConnection;
    @AuraEnabled public String trailerBodyType;
    @AuraEnabled public String trailerLength;
    @AuraEnabled public String otherTrailerInfo;
    

    @AuraEnabled public String customMotorcycleType;
    @AuraEnabled public String motorcycleSuspensionType;
    @AuraEnabled public String motorcycleChassisType;
    @AuraEnabled public String otherMotorcycleInfo;
    

    @AuraEnabled public String busLength;
    @AuraEnabled public String busFloorConfigurationType;
    @AuraEnabled public String busType;
    @AuraEnabled public String otherBusInfo;

    // Powersports integration fields
    @AuraEnabled public String vehicleCategory;   // 'Used Car' or 'Powersports' — set by cascade logic
    @AuraEnabled public Decimal engineCC;          // engine_displacement from Powersports API (stored on Vehicle__c)
    @AuraEnabled public Decimal hoursUsage;        // manual entry, stored on Vehicle__c
    @AuraEnabled public String vehicleClass;       // Powersports class_name, stored on Vehicle__c / Application__c

    // Powersports modal-only display fields (not stored in database)
    @AuraEnabled public String powersportsClassName;
    @AuraEnabled public String powersportsModelClass;
    @AuraEnabled public String powersportsUvc;
    @AuraEnabled public String powersportsCylinders;
    @AuraEnabled public String powersportsPublishDate;
    @AuraEnabled public Decimal powersportsWholeAvg;
    @AuraEnabled public Decimal powersportsRetailAvg;
    @AuraEnabled public Decimal powersportsTradeinClean;
    @AuraEnabled public Decimal powersportsTradeinFair;
    @AuraEnabled public Decimal powersportsFinadv;
    @AuraEnabled public Decimal powersportsMsrp;

    public VehicleDataDTO() {}
}


public class VehicleResponse {
    @AuraEnabled public Boolean success;
    @AuraEnabled public String message;
    @AuraEnabled public String recordId;
    @AuraEnabled public VehicleDataDTO data;
    @AuraEnabled public String apiSource; // Track which API was used: 'AUTO_DEV', 'NHTSA', 'BLACKBOOK', or 'NONE'
    @AuraEnabled public String rawResponse; // Raw JSON response from the API (for debugging/inspection)
    
    public VehicleResponse() {
        this.apiSource = 'NONE';
        this.rawResponse = '';
    }
}


public class PicklistOptionDTO {
    @AuraEnabled public String label;
    @AuraEnabled public String value;
    /** Preserved from Manufacturer_Term__c.Allow_Defferal__c. No longer used to gate the deferral checkbox (now controlled by Dealer_Package_Term__c.Allow_Deferral__c), but kept for backward compatibility. */
    @AuraEnabled public Boolean allowDeferral;
    /** Duration of this manufacturer term in months. Used by the LWC to calculate whether the manufacturer warranty has expired. */
    @AuraEnabled public Integer durationMonths;
}



public class DealerPackageDTO {
    @AuraEnabled public String Id;
    @AuraEnabled public String Name;
    @AuraEnabled public String PackageName;
    @AuraEnabled public String PackageDescription;
    @AuraEnabled public String planTypeId;
    @AuraEnabled public String planTypeName;
    @AuraEnabled public String planTypeDescription;
    @AuraEnabled public String DealerName;
    @AuraEnabled public String DealerId;
    @AuraEnabled public String PackageClass;
    @AuraEnabled public String taxRegionId; // Tax_Region__c ID from Dealer
    @AuraEnabled public Decimal taxRate; // Total_Tax_Rate__c from Tax_Region lookup
    @AuraEnabled public List<DealerPackageTermDTO> terms; // Keep for backward compatibility
    @AuraEnabled public List<DealerPackageTierDTO> tiers; // NEW: Grouped by tiers
    @AuraEnabled public List<DealerPackageOptionDTO> options;
    
    public DealerPackageDTO() {}
}


public class GapPackageDTO {
    @AuraEnabled public String Id;
    @AuraEnabled public String Name;
    @AuraEnabled public String PackageName;
    @AuraEnabled public String PackageDescription;
    @AuraEnabled public String DealerName;
    @AuraEnabled public String DealerId;
    @AuraEnabled public List<GapPackageTermDTO> terms;
    @AuraEnabled public List<GapPackageOptionDTO> options;
    
    public GapPackageDTO() {}
}


public class GapPackageTermDTO {
    @AuraEnabled public String Id;
    @AuraEnabled public Decimal netCost;
    @AuraEnabled public Decimal markup;
    @AuraEnabled public String markupType;
    @AuraEnabled public Decimal totalPrice;
    @AuraEnabled public Decimal deductible;
    @AuraEnabled public Decimal durationRestrictionInMonths;
    @AuraEnabled public Decimal mileageRestriction;
    @AuraEnabled public String mileageUnit;
    @AuraEnabled public String packageTermName;

    @AuraEnabled public Decimal originalPackageTermCost;
    @AuraEnabled public Decimal includedOptionsPrice;
    @AuraEnabled public Decimal additionalOptionsPrice;
    @AuraEnabled public String discountType;
    @AuraEnabled public Decimal discountValue;
    
    public GapPackageTermDTO() {}
}


public class GapPackageOptionDTO {
    @AuraEnabled public String Id;
    @AuraEnabled public String Name;
    @AuraEnabled public String optionName;
    @AuraEnabled public Decimal netCost;
    @AuraEnabled public Decimal dealerMarkup;
    @AuraEnabled public String markupType;
    @AuraEnabled public Decimal totalPrice;
    
    public GapPackageOptionDTO() {}
}



public class DealerPackageTermDTO {
    @AuraEnabled public String Id;
    @AuraEnabled public Decimal netCost;
    @AuraEnabled public Decimal markup;
    @AuraEnabled public String markupType;
    @AuraEnabled public Decimal totalPrice;
    @AuraEnabled public Decimal taxAmount;
    @AuraEnabled public Decimal taxRate;
    @AuraEnabled public Decimal deductible;
    @AuraEnabled public Decimal perClaimLimit;
    @AuraEnabled public Decimal durationRestrictionInMonths;
    @AuraEnabled public Decimal mileageRestriction;
    @AuraEnabled public String mileageUnit;
    @AuraEnabled public String packageTermName;
    /** When true, the Deferral Option checkbox is eligible for this term on the warranty tab. */
    @AuraEnabled public Boolean allowDeferral;

    @AuraEnabled public Decimal originalPackageTermCost;
    @AuraEnabled public Decimal includedOptionsPrice;
    @AuraEnabled public Decimal additionalOptionsPrice;
    @AuraEnabled public String discountType;
    @AuraEnabled public Decimal discountValue;

    @AuraEnabled public Decimal expiryTerm;
    @AuraEnabled public Decimal odometerKM;
    
    public DealerPackageTermDTO() {}
}


public class DealerPackageTierDTO {
    @AuraEnabled public String Id;
    @AuraEnabled public String Name;
    @AuraEnabled public Decimal mileageRestrictionStart;
    @AuraEnabled public Decimal mileageRestrictionEnd;
    @AuraEnabled public String mileageUnit;
    @AuraEnabled public List<DealerPackageTermDTO> terms;
    
    public DealerPackageTierDTO() {}
}

public class DealerPackageOptionDTO {
    @AuraEnabled public String Id;
    @AuraEnabled public String Name;
    @AuraEnabled public String optionName;
    @AuraEnabled public String inclusion;
    @AuraEnabled public String exclusion;
    
    public DealerPackageOptionDTO() {}
}


@AuraEnabled(cacheable=true)
public static AdditionalOptionsResponse getAdditionalOptions(String dealerPackageTermId) {
    try {
        
        List<Dealer_Package_Option__c> additionalOptions = [
            SELECT Id, Name, Option__c, Option__r.Name,
                    Inclusion__c, Exclusion__c, Selection_Type__c,
                    Dealer_Package_Term__c, Dealer_Package_Term__r.Name,
                    Discount_Type__c, Discount_Value__c, 
                    Original_Package_Option_Price__c, Net_Cost__c,
                    Dealer_Markup__c, Markup_Type__c, Retail_Price__c
            FROM Dealer_Package_Option__c
            WHERE Dealer_Package_Term__c = :dealerPackageTermId
            AND Selection_Type__c = 'Optional'
            ORDER BY Option__r.Name
        ];
        
        List<AdditionalOptionDTO> optionList = new List<AdditionalOptionDTO>();
        for (Dealer_Package_Option__c option : additionalOptions) {
            AdditionalOptionDTO dto = new AdditionalOptionDTO();
            dto.Id = option.Id;
            dto.Name = option.Name;
            dto.optionName = option.Option__r.Name;
            dto.price = option.Retail_Price__c != null ? option.Retail_Price__c : 0;
            dto.originalPrice = option.Original_Package_Option_Price__c != null ? option.Original_Package_Option_Price__c : 0;
            dto.netCost = option.Net_Cost__c != null ? option.Net_Cost__c : 0;
            dto.dealerMarkup = option.Dealer_Markup__c != null ? option.Dealer_Markup__c : 0;
            dto.markupType = option.Markup_Type__c != null ? option.Markup_Type__c : '';
            dto.retailPrice = option.Retail_Price__c != null ? option.Retail_Price__c : 0;
            dto.discountType = option.Discount_Type__c;
            dto.discountValue = option.Discount_Value__c != null ? option.Discount_Value__c : 0;
            dto.inclusion = option.Inclusion__c;
            dto.exclusion = option.Exclusion__c;
            dto.dealerPackageTermId = option.Dealer_Package_Term__c;
            optionList.add(dto);
        }
        
        
        AdditionalOptionsResponse response = new AdditionalOptionsResponse();
        response.success = true;
        response.data = optionList;
        response.message = 'Additional options retrieved successfully';
        return response;
        
    } catch (Exception e) {
AdditionalOptionsResponse response = new AdditionalOptionsResponse();
        response.success = false;
        response.data = new List<AdditionalOptionDTO>();
        response.message = 'Error fetching additional options: ' + e.getMessage();
        return response;
    }
}


public class AdditionalOptionDTO {
    @AuraEnabled public String Id;
    @AuraEnabled public String Name;
    @AuraEnabled public String optionName;
    @AuraEnabled public Decimal price;
    @AuraEnabled public Decimal originalPrice;
    @AuraEnabled public Decimal netCost;
    @AuraEnabled public Decimal dealerMarkup;
    @AuraEnabled public String markupType;
    @AuraEnabled public Decimal retailPrice;
    @AuraEnabled public String discountType;
    @AuraEnabled public Decimal discountValue;
    @AuraEnabled public String inclusion;
    @AuraEnabled public String exclusion;
    @AuraEnabled public String dealerPackageTermId;
    @AuraEnabled public String category;
    @AuraEnabled public Decimal minimumValue;
    @AuraEnabled public Decimal maximumValue;
    
    public AdditionalOptionDTO() {}
}


public class AdditionalOptionsResponse {
    @AuraEnabled public Boolean success;
    @AuraEnabled public String message;
    @AuraEnabled public List<AdditionalOptionDTO> data;
    
    public AdditionalOptionsResponse() {}
}



public class DealerPackagesResponse {
    @AuraEnabled public Boolean success;
    @AuraEnabled public String message;
    @AuraEnabled public List<DealerPackageDTO> data;
    @AuraEnabled public Map<String, Object> debugInfo; // Debug information for troubleshooting
    
    public DealerPackagesResponse() {}
}



public class ApplicationPackageResponse {
    @AuraEnabled public Boolean success;
    @AuraEnabled public String message;
    @AuraEnabled public String recordId;
    @AuraEnabled public Map<String, Object> data;
    
    public ApplicationPackageResponse() {}
}


/**
 * Fetch application status information to determine if application is locked
 * @param applicationId The ID of the application
 * @return Application__c record with Application_Status__c, Application_Lock_Date__c, and Payment_Status__c fields
 */
@AuraEnabled
public static Application__c getApplicationStatus(String applicationId) {
    List<Application__c> applications = [
        SELECT Id, Application_Status__c, Application_Lock_Date__c, Payment_Status__c
        FROM Application__c
        WHERE Id = :applicationId
        LIMIT 1
    ];
    
    if (!applications.isEmpty()) {
        return applications[0];
    }
    
    return null;
}


@AuraEnabled
public static ApplicationsResponse getAllApplications() {
    ApplicationsResponse response = new ApplicationsResponse();
    response.success = false;
    response.message = '';
    
    try {
        List<Application__c> applications = queryApplications(null, false);
        
        List<ApplicationDataDTO> applicationData = new List<ApplicationDataDTO>();
        
        for (Application__c app : applications) {
            String vehicleName = 'No Vehicle';
            if (app.Vehicle__r != null) {
                List<String> nameParts = new List<String>();
                if (String.isNotBlank(app.Vehicle__r.Year__c)) nameParts.add(app.Vehicle__r.Year__c);
                if (String.isNotBlank(app.Vehicle__r.Make__c)) nameParts.add(app.Vehicle__r.Make__c);
                if (String.isNotBlank(app.Vehicle__r.Model__c)) nameParts.add(app.Vehicle__r.Model__c);
                if (String.isNotBlank(app.Vehicle__r.Trim__c)) nameParts.add(app.Vehicle__r.Trim__c);
                
                if (!nameParts.isEmpty()) {
                    vehicleName = String.join(nameParts, ' ');
                }
            }
            
            ApplicationDataDTO appData = new ApplicationDataDTO();
            appData.Id = app.Id;
            appData.Name = app.Name;
            appData.CreatedDate = app.CreatedDate;
            appData.Status = app.Application_Status__c;
            appData.VehicleName = vehicleName;
            
            applicationData.add(appData);
        }
        
        // Query nearest future Invoice_Due_Date__c for each application
        if (!applicationData.isEmpty()) {
            Set<String> appIds = new Set<String>();
            for (ApplicationDataDTO appDto : applicationData) {
                appIds.add(appDto.Id);
            }
            
            // Get the earliest Invoice_Due_Date__c per application
            Map<String, Date> appToInvoiceDueDate = new Map<String, Date>();
            List<Invoice__c> invoices = [
                SELECT Application__c, Invoice_Due_Date__c
                FROM Invoice__c
                WHERE Application__c IN :appIds
                AND Invoice_Due_Date__c != null
                ORDER BY Invoice_Due_Date__c ASC
            ];
            
            for (Invoice__c inv : invoices) {
                // Only keep the earliest due date per application
                if (!appToInvoiceDueDate.containsKey(inv.Application__c)) {
                    appToInvoiceDueDate.put(inv.Application__c, inv.Invoice_Due_Date__c);
                }
            }
            
            // Populate PaymentDueDate on each DTO
            for (ApplicationDataDTO appDto : applicationData) {
                if (appToInvoiceDueDate.containsKey(appDto.Id)) {
                    appDto.PaymentDueDate = appToInvoiceDueDate.get(appDto.Id);
                }
            }
        }
        
        response.success = true;
        response.data = applicationData;
        response.totalCount = applicationData.size();
        
    } catch (Exception e) {
        response.message = 'Error fetching applications: ' + e.getMessage();
    }
    
    return response;
}

/**
 * Wrapper class for String parameters to avoid LWC-to-Apex casting bug
 * where String parameters cause: Class Cast Exception: class java.lang.String cannot be cast to class java.util.Map
 */
public class LoadVehicleRequest {
    @AuraEnabled public String applicationId { get; set; }
    
    public LoadVehicleRequest() {

    }
}

/**
 * Provide picklist values for Manufacturer Warranty fields on Vehicle__c
 */
@AuraEnabled(cacheable=true)
public static Map<String, List<PicklistOptionDTO>> getVehicleWarrantyPicklists() {
    try {
        Map<String, List<PicklistOptionDTO>> picklists = new Map<String, List<PicklistOptionDTO>>();
        picklists.put('manufacturerWarrantyType', buildPicklistOptions(Vehicle__c.Manufacturer_Warranty_Type__c));
        picklists.put('warrantyTerm', buildWarrantyTermOptionsFromObject());
        return picklists;
    } catch (Exception e) {
        throw new AuraHandledException('Error retrieving warranty picklists: ' + e.getMessage());
    }
}

/**
 * Build warranty term options from Manufacturer_Term__c records
 * Queries all Manufacturer_Term__c records and uses their Name field as the picklist values
 * Orders by Duration value (converting Years to Months for consistent sorting)
 */
private static List<PicklistOptionDTO> buildWarrantyTermOptionsFromObject() {
    List<PicklistOptionDTO> options = new List<PicklistOptionDTO>();
    
    try {
        // Query active Manufacturer_Term__c records with Duration and Allow_Defferal__c
        List<Manufacturer_Term__c> manufacturerTerms = [
            SELECT Id, Name, Duration__c, Duration_Type__c, Allow_Defferal__c
            FROM Manufacturer_Term__c
            WHERE Active__c = true
            ORDER BY Duration__c ASC, Duration_Type__c ASC
        ];
        
        // Create a wrapper list to sort by duration in months
        List<TermWrapper> termWrappers = new List<TermWrapper>();
        for (Manufacturer_Term__c term : manufacturerTerms) {
            TermWrapper wrapper = new TermWrapper();
            wrapper.term = term;
            // Convert duration to months for consistent sorting
            // If Duration_Type__c is "Years", multiply by 12; if "Months" or null, use as is
            Decimal durationInMonths = term.Duration__c != null ? term.Duration__c : 0;
            if (term.Duration_Type__c == 'Years' && durationInMonths > 0) {
                durationInMonths = durationInMonths * 12;
            }
            // If Duration_Type__c is null or 'Months', durationInMonths is already in months
            wrapper.durationInMonths = durationInMonths;
            termWrappers.add(wrapper);
        }
        
        // Sort by duration in months
        termWrappers.sort(new TermWrapperComparator());
        
        // Convert sorted records to PicklistOptionDTO format
        for (TermWrapper wrapper : termWrappers) {
            PicklistOptionDTO option = new PicklistOptionDTO();
            option.label = wrapper.term.Name;
            option.value = wrapper.term.Name; // Use Name as both label and value
            option.allowDeferral = Boolean.valueOf(wrapper.term.Allow_Defferal__c); // kept for backward compat
            option.durationMonths = Integer.valueOf(wrapper.durationInMonths); // used by LWC for expiry check
            options.add(option);
        }
    } catch (Exception e) {
        // If Manufacturer_Term__c object doesn't exist or query fails, return empty list
        System.debug('Error querying Manufacturer_Term__c: ' + e.getMessage());
    }
    
    return options;
}

/**
 * Wrapper class to hold Manufacturer_Term__c record with calculated duration in months
 */
private class TermWrapper {
    Manufacturer_Term__c term;
    Decimal durationInMonths;
}

/**
 * Comparator class to sort TermWrapper by durationInMonths
 */
private class TermWrapperComparator implements Comparator<TermWrapper> {
    public Integer compare(TermWrapper wrapper1, TermWrapper wrapper2) {
        if (wrapper1.durationInMonths == wrapper2.durationInMonths) {
            return 0;
        } else if (wrapper1.durationInMonths > wrapper2.durationInMonths) {
            return 1;
        } else {
            return -1;
        }
    }
}

private static List<PicklistOptionDTO> buildPicklistOptions(Schema.SObjectField fieldToken) {
    List<PicklistOptionDTO> options = new List<PicklistOptionDTO>();
    if (fieldToken == null) {
        return options;
    }

    for (Schema.PicklistEntry entry : fieldToken.getDescribe().getPicklistValues()) {
        if (!entry.isActive()) {
            continue;
        }

        PicklistOptionDTO option = new PicklistOptionDTO();
        option.label = entry.getLabel();
        option.value = entry.getValue();
        options.add(option);
    }

    return options;
}








/**
 * Load vehicle data for a specific application (original method - kept for internal use)
 * @param applicationId The ID of the application
 * @return VehicleResponse containing vehicle data or error message
 */
@AuraEnabled
public static VehicleResponse loadVehicleData(String applicationId) {
    VehicleResponse response = new VehicleResponse();
    response.success = false;
    response.message = '';

    try {
        

        if (String.isBlank(applicationId)) {
            response.message = 'Application ID is required';
            return response;
        }


        List<Application__c> apps = queryApplications(applicationId, true);

        if (!apps.isEmpty()) {
            Application__c app = apps[0];
            Vehicle__c vehicle = app.Vehicle__r;

            if (vehicle != null) {
                response.success = true;
                response.recordId = vehicle.Id;
                

                VehicleDataDTO vehicleData = new VehicleDataDTO();
                vehicleData.stockNumber = vehicle.Stock_Number__c;
                vehicleData.vin = vehicle.VIN__c;
                vehicleData.vehicleIdentificationNumberVIN = vehicle.Vehicle_Identification_Number_VIN__c;
                vehicleData.year = vehicle.Year__c;
                vehicleData.make = vehicle.Make__c;
                vehicleData.model = vehicle.Model__c;
                vehicleData.modelClass = vehicle.Model_Lookup__r != null ? vehicle.Model_Lookup__r.Class__c : null;
                vehicleData.trim = vehicle.Trim__c;
                vehicleData.dateVehicleSold = vehicle.Date_Vehicle_Sold__c != null ? String.valueOf(vehicle.Date_Vehicle_Sold__c) : null;
                vehicleData.vehiclePurchasePrice = vehicle.Vehicle_Purchase_Price__c;
                vehicleData.brandedRebuilt = vehicle.Branded_Rebuilt__c;
                vehicleData.inServiceDate = vehicle.In_Service_Date__c != null ? String.valueOf(vehicle.In_Service_Date__c) : null;
                vehicleData.odometer = vehicle.Odometer__c;
                vehicleData.odometerUnit = vehicle.Odometer_Unit__c;
                vehicleData.businessCommercialUse = vehicle.Business_Commercial_Use__c;
                vehicleData.isVehicleFinanced = app.Is_Vehicle_Financed__c;
                vehicleData.typeOfCommercialUse = vehicle.Type_of_Commercial_Use__c;
                

                vehicleData.engine = vehicle.Engine__c;
                vehicleData.transmission = vehicle.Transmission__c;
                vehicleData.fuelType = vehicle.Fuel_Type__c;
                vehicleData.driveType = vehicle.Drive_Type__c;
                vehicleData.bodyStyle = vehicle.Body_Style__c;
                vehicleData.color = vehicle.Color__c;
                vehicleData.gvwr = vehicle.GVWR__c != null ? String.valueOf(vehicle.GVWR__c) : null;
                

                vehicleData.manufacturerWarrantyType = vehicle.Manufacturer_Warranty_Type__c;
                vehicleData.warrantyTerm = vehicle.Warranty_Term__c;
                vehicleData.warrantyInServiceDate = vehicle.In_Service_Date__c != null ? String.valueOf(vehicle.In_Service_Date__c) : null;
                vehicleData.deferralOption = vehicle.Deferral_Option__c != null ? vehicle.Deferral_Option__c : false;

                // Check if the active warranty package term's base Package_Term__c has Allow_Deferral__c enabled
                vehicleData.packageTermAllowsDeferral = false;
                try {
                    List<Application_Package__c> warrantyPackages = [
                        SELECT Dealer_Package_Term__r.Package_Term__r.Allow_Deferral__c
                        FROM Application_Package__c
                        WHERE Application__c = :applicationId
                            AND RecordType.DeveloperName = 'Extended_Limited_Warranty'
                            AND Active__c = true
                        LIMIT 1
                    ];
                    if (!warrantyPackages.isEmpty() && warrantyPackages[0].Dealer_Package_Term__c != null) {
                        vehicleData.packageTermAllowsDeferral =
                            warrantyPackages[0].Dealer_Package_Term__r.Package_Term__r != null &&
                            warrantyPackages[0].Dealer_Package_Term__r.Package_Term__r.Allow_Deferral__c == true;
                    }
                } catch (Exception pkgEx) {
                    System.debug('Could not load warranty package term for deferral check: ' + pkgEx.getMessage());
                }

                // Calculate if the manufacturer warranty has already expired
                vehicleData.isManufacturerWarrantyExpired = false;
                if (vehicle.In_Service_Date__c != null && String.isNotBlank(vehicle.Warranty_Term__c)) {
                    try {
                        List<Manufacturer_Term__c> mfgTerms = [
                            SELECT Duration__c, Duration_Type__c
                            FROM Manufacturer_Term__c
                            WHERE Name = :vehicle.Warranty_Term__c AND Active__c = true
                            LIMIT 1
                        ];
                        if (!mfgTerms.isEmpty() && mfgTerms[0].Duration__c != null) {
                            Integer durationMonths = Integer.valueOf(mfgTerms[0].Duration__c);
                            if (mfgTerms[0].Duration_Type__c == 'Years') {
                                durationMonths = durationMonths * 12;
                            }
                            Date expiryDate = vehicle.In_Service_Date__c.addMonths(durationMonths);
                            vehicleData.isManufacturerWarrantyExpired = expiryDate <= Date.today();
                        }
                    } catch (Exception expiryEx) {
                        System.debug('Could not calculate manufacturer warranty expiry: ' + expiryEx.getMessage());
                    }
                }

                vehicleData.deliveryDate = vehicle.Delivery_Date__c != null ? String.valueOf(vehicle.Delivery_Date__c) : null;
                vehicleData.usageType = vehicle.Usage_Type__c;
                vehicleData.vehicleSubType = vehicle.Vehicle_Sub_Type__c;
                vehicleData.vehicleClass = vehicle.Vehicle_Class__c;
                vehicleData.vehicleCategory = vehicle.Vehicle_Category__c;
                

                if (app.Dealer_Comments_Notes__c != null) {
                    vehicleData.dealerCommentsNotes = app.Dealer_Comments_Notes__c;
                }
                if (app.Show_Comments_On_Print__c != null) {
                    vehicleData.showCommentsOnPrint = app.Show_Comments_On_Print__c;
                }
                if (app.Sales_Rep__c != null) {
                    vehicleData.salesRepId = app.Sales_Rep__c;
                    vehicleData.salesRepName = app.Sales_Rep__r != null ? app.Sales_Rep__r.Name : null;
                }
                if (app.Dealer_Sales_ID_License__c != null) {
                    vehicleData.dealerSalesId = app.Dealer_Sales_ID_License__c;
                }
                if (app.Financial_Institution_Lender__c != null) {
                    vehicleData.lienHolder = app.Financial_Institution_Lender__c;
                }

                if (app.Dealer_Name__r != null) {
                    vehicleData.dealershipName = app.Dealer_Name__r.Name;
                    vehicleData.dealershipAddress = app.Dealer_Name__r.BillingStreet;
                    vehicleData.dealershipAccountId = app.Dealer_Name__c; // Store Account ID for loading contacts
                    String cityProvincePostal = '';
                    if (String.isNotBlank(app.Dealer_Name__r.BillingCity)) {
                        cityProvincePostal = app.Dealer_Name__r.BillingCity;
                    }
                    if (String.isNotBlank(app.Dealer_Name__r.BillingState)) {
                        cityProvincePostal += (cityProvincePostal != '' ? ', ' : '') + app.Dealer_Name__r.BillingState;
                    }
                    if (String.isNotBlank(app.Dealer_Name__r.BillingPostalCode)) {
                        cityProvincePostal += (cityProvincePostal != '' ? ' ' : '') + app.Dealer_Name__r.BillingPostalCode;
                    }
                    vehicleData.cityProvincePostal = cityProvincePostal;
                }
                
                response.data = vehicleData;
                return response;
            } else {
                response.message = 'No vehicle found for this application';
                return response;
            }
        } else {
            response.message = 'Application not found';
            return response;
        }

    } catch (Exception e) {
response.message = 'Error loading vehicle data: ' + e.getMessage();
    }

    return response;
}

/**
 * Get dealership information for the logged-in user
 * Returns the account (dealer) information associated with the current user's contact
 * @return Map containing dealership info: accountId, accountName, billingStreet, billingCity, billingState, billingPostalCode, contactId, contactName
 */
@AuraEnabled(cacheable=true)
public static Map<String, Object> getDealershipInfo() {
    Map<String, Object> result = new Map<String, Object>();
    
    try {
        String currentUserId = UserInfo.getUserId();
        

        List<User> currentUser = [
            SELECT Id, ContactId, Contact.Id, Contact.Name, 
                    Contact.AccountId, Contact.Account.Id, Contact.Account.Name,
                    Contact.Account.BillingStreet, Contact.Account.BillingCity,
                    Contact.Account.BillingState, Contact.Account.BillingPostalCode,
                    Contact.Account.BillingCountry, Contact.Account.Dealership_ID__c
            FROM User 
            WHERE Id = :currentUserId 
            LIMIT 1
        ];
        
        if (!currentUser.isEmpty() && currentUser[0].ContactId != null && currentUser[0].Contact.AccountId != null) {
            User user = currentUser[0];
            result.put('success', true);
            result.put('accountId', user.Contact.AccountId);
            result.put('accountName', user.Contact.Account.Name);
            result.put('billingStreet', user.Contact.Account.BillingStreet);
            result.put('billingCity', user.Contact.Account.BillingCity);
            result.put('billingState', user.Contact.Account.BillingState);
            result.put('billingPostalCode', user.Contact.Account.BillingPostalCode);
            result.put('billingCountry', user.Contact.Account.BillingCountry);
            result.put('dealershipId', user.Contact.Account.Dealership_ID__c);
            result.put('contactId', user.ContactId);
            result.put('contactName', user.Contact.Name);
            

            String cityProvincePostal = '';
            if (String.isNotBlank(user.Contact.Account.BillingCity)) {
                cityProvincePostal = user.Contact.Account.BillingCity;
            }
            if (String.isNotBlank(user.Contact.Account.BillingState)) {
                cityProvincePostal += (cityProvincePostal != '' ? ', ' : '') + user.Contact.Account.BillingState;
            }
            if (String.isNotBlank(user.Contact.Account.BillingPostalCode)) {
                cityProvincePostal += (cityProvincePostal != '' ? ' ' : '') + user.Contact.Account.BillingPostalCode;
            }
            result.put('cityProvincePostal', cityProvincePostal);
        } else {
            result.put('success', false);
            result.put('message', 'User does not have a contact or account association');
        }
    } catch (Exception e) {
result.put('success', false);
        result.put('message', 'Error getting dealership info: ' + e.getMessage());
    }
    
    return result;
}

/**
 * Get all contacts for a dealer account
 * @param accountId The ID of the dealer account
 * @return List of maps containing contact information: Id, Name, and License Number (if field exists)
 */
@AuraEnabled(cacheable=true)
public static List<Map<String, Object>> getDealerContacts(String accountId) {
    List<Map<String, Object>> contacts = new List<Map<String, Object>>();
    
    try {
        if (String.isBlank(accountId)) {
            return contacts;
        }
        


        List<Contact> dealerContacts = [
            SELECT Id, Name
            FROM Contact
            WHERE AccountId = :accountId
            ORDER BY Name
        ];
        
        for (Contact c : dealerContacts) {
            Map<String, Object> contactMap = new Map<String, Object>();
            contactMap.put('Id', c.Id);
            contactMap.put('Name', c.Name);


            contacts.add(contactMap);
        }
    } catch (Exception e) {
}
    
    return contacts;
}

/**
 * Fetch dealer packages for a given application
 * 
 * This method retrieves all dealer packages associated with a specific application.
 * It first queries the application to get the dealer information, then fetches
 * all packages for that dealer. The method handles both sharing and non-sharing
 * scenarios to ensure partner users can access the data.
 * 
 * @param applicationId The ID of the application to fetch packages for
 * @return DealerPackagesResponse containing:
 *         - success: Boolean indicating if the operation was successful
 *         - message: String with success/error message
 *         - data: List of DealerPackageDTO objects with package details
 * 
 * @example
 * DealerPackagesResponse response = DealerPortalController.getDealerPackages('a1234567890');
 * if (response.success) {
 *     List<DealerPackageDTO> packages = response.data;
 *     // Process packages...
 * }
 */
@AuraEnabled
public static DealerPackagesResponse getDealerPackages(String applicationId, String recordType) {
    String methodName = 'getDealerPackages';
    Map<String, Object> params = new Map<String, Object>{'applicationId' => applicationId, 'recordType' => recordType};
    logMethodEntry(methodName, params);
try {

        List<String> missingParams = validateRequiredParams(params);
        if (!missingParams.isEmpty()) {
DealerPackagesResponse response = new DealerPackagesResponse();
            response.success = false;
            response.message = 'Missing required parameters: ' + String.join(missingParams, ', ');
            response.data = null;
            logMethodExit(methodName, false, null);
            return response;
        }
        

List<Application__c> applications = [
            SELECT Id, Dealer_Name__c, Dealer_Name__r.Id, Dealer_Name__r.Name,
                    Vehicle__r.Year__c, Vehicle__r.Odometer__c, Vehicle__r.Odometer_Unit__c,
                    Vehicle__r.Model_Lookup__c, Vehicle__r.Model_Lookup__r.Class__c,
                    Vehicle__r.Business_Commercial_Use__c, Vehicle__r.Type_of_Commercial_Use__c
            FROM Application__c 
            WHERE Id = :applicationId
            LIMIT 1
        ];
        
        if (applications.isEmpty()) {
DealerPackagesResponse response = new DealerPackagesResponse();
            response.success = false;
            response.message = 'No application found with ID: ' + applicationId;
            response.data = null;
            logMethodExit(methodName, false, null);
            return response;
        }
        
        Application__c application = applications[0];

        if (application.Dealer_Name__c == null) {
DealerPackagesResponse response = new DealerPackagesResponse();
            response.success = false;
            response.message = 'No dealer specified for this application';
            response.data = null;
            logMethodExit(methodName, false, null);
            return response;
        }
        
        String dealerId = application.Dealer_Name__r.Id;

        List<Dealer_Package__c> dealerPackages = queryDealerPackages(dealerId, true, recordType);

        if (dealerPackages.isEmpty()) {
dealerPackages = getDealerPackagesWithoutSharing(dealerId, recordType);
}

        Boolean hasSpecificRecordTypePackages = !dealerPackages.isEmpty();

        if (dealerPackages.isEmpty()) {

            List<Dealer_Package__c> allPackages = queryDealerPackages(dealerId, true, null);
if (allPackages.isEmpty()) {
                allPackages = getDealerPackagesWithoutSharing(dealerId, null);
}

            if (allPackages.isEmpty()) {
DealerPackagesResponse response = new DealerPackagesResponse();
                response.success = false;
                response.message = 'No packages available for this dealer with record type: ' + recordType;
                response.data = null;
                return response;
            } else {
dealerPackages = allPackages;
            }
        }

        String vehicleYear = null;
        Decimal vehicleOdometer = null;
        String vehicleOdometerUnit = null;
        String vehicleClass = null;
        if (application.Vehicle__r != null) {
            vehicleYear = application.Vehicle__r.Year__c;
            vehicleOdometer = application.Vehicle__r.Odometer__c;
            vehicleOdometerUnit = application.Vehicle__r.Odometer_Unit__c;
            vehicleClass = application.Vehicle__r.Model_Lookup__r != null ? application.Vehicle__r.Model_Lookup__r.Class__c : null;
} else {
}
        
        Boolean isCommercialUse = application.Vehicle__r != null && application.Vehicle__r.Business_Commercial_Use__c == true;
        String typeOfCommercialUse = (application.Vehicle__r != null) ? application.Vehicle__r.Type_of_Commercial_Use__c : null;
        

        Boolean isTireRimRequest = String.isNotBlank(recordType) && recordType.containsIgnoreCase('Tire_Rim');




        if (!isTireRimRequest) {
            List<Dealer_Package__c> filteredPackages = new List<Dealer_Package__c>();
            
            for (Dealer_Package__c dp : dealerPackages) {
                String packageClass = dp.Class__c;
                
                if (String.isNotBlank(packageClass)) {
                    if (String.isBlank(vehicleClass)) {
continue;
                    }
                    
                    if (!vehicleClass.equalsIgnoreCase(packageClass)) {
continue;
                    }
} else {

}
                
                filteredPackages.add(dp);
            }
dealerPackages = filteredPackages;
        }
        
        // Commercial use filtering
        {
            List<Dealer_Package__c> commercialFiltered = new List<Dealer_Package__c>();
            for (Dealer_Package__c dp : dealerPackages) {
                String eligibility = dp.Commercial_Eligible__c;
                if (String.isBlank(eligibility) || eligibility == 'All') {
                    commercialFiltered.add(dp);
                } else if (eligibility == 'Personal Only' && !isCommercialUse) {
                    commercialFiltered.add(dp);
                } else if (eligibility == 'Commercial Only' && isCommercialUse) {
                    commercialFiltered.add(dp);
                } else if (eligibility == 'Light Duty Commercial Only') {
                    if (isCommercialUse && typeOfCommercialUse != null && typeOfCommercialUse.containsIgnoreCase('Light Duty')) {
                        commercialFiltered.add(dp);
                    } else if (!isCommercialUse) {
                        // Personal use vehicles are not eligible for commercial-only packages
                    }
                }
            }
            dealerPackages = commercialFiltered;
        }


        Set<Id> packageIds = new Set<Id>();
        for (Dealer_Package__c dp : dealerPackages) {
            packageIds.add(dp.Id);
        }

        List<Dealer_Package_Term__c> allTerms = [
            SELECT Id, Name, Package_Term__c,
                    Mileage_Restriction__c, Original_Package_Term_Cost__c,
                    Mileage__c, Mileage_Unit__c, Month__c, ByYear__c,
                    Markup__c, Markup_Type__c,
                    Net_Cost__c, Retail_Price__c,
                    Included_Options_Price__c,
                    Additional_Options_Price__c, Discount_Type__c, Discount_Value__c,
                    Expiry_Term__c, Odometer_KM__c,
                    Package_Term__r.Allow_Deferral__c,
                    Dealer_Package_Tier__c, Dealer_Package__c,
                    Dealer_Package_Tier__r.Id,
                    Dealer_Package_Tier__r.Name,
                    Dealer_Package_Tier__r.Minimum__c,
                    Dealer_Package_Tier__r.Maximum__c,
                    Dealer_Package_Tier__r.Mileage_Unit__c
            FROM Dealer_Package_Term__c
            WHERE Dealer_Package__c IN :packageIds
            ORDER BY Dealer_Package__c, Dealer_Package_Tier__c
            LIMIT 50000
        ];
        


        List<Dealer_Package_Option__c> allOptions = [
            SELECT Id, Name, Option__c, Option__r.Name, 
                    Inclusion__c, Exclusion__c, Selection_Type__c,
                    Dealer_Package__c
            FROM Dealer_Package_Option__c
            WHERE Dealer_Package__c IN :packageIds
            AND Selection_Type__c = 'Included'
            ORDER BY Dealer_Package__c, Option__r.Name
            LIMIT 50000
        ];

        Map<Id, List<Dealer_Package_Term__c>> termsByPackageId = new Map<Id, List<Dealer_Package_Term__c>>();
        Map<Id, List<Dealer_Package_Option__c>> optionsByPackageId = new Map<Id, List<Dealer_Package_Option__c>>();
        
        for (Dealer_Package_Term__c term : allTerms) {
            if (!termsByPackageId.containsKey(term.Dealer_Package__c)) {
                termsByPackageId.put(term.Dealer_Package__c, new List<Dealer_Package_Term__c>());
            }
            termsByPackageId.get(term.Dealer_Package__c).add(term);
        }
        
        for (Dealer_Package_Option__c option : allOptions) {
            if (!optionsByPackageId.containsKey(option.Dealer_Package__c)) {
                optionsByPackageId.put(option.Dealer_Package__c, new List<Dealer_Package_Option__c>());
            }
            optionsByPackageId.get(option.Dealer_Package__c).add(option);
        }

List<DealerPackageDTO> packageList = new List<DealerPackageDTO>();
        Integer packageIndex = 0;
        for (Dealer_Package__c dp : dealerPackages) {
            try {
                packageIndex++;

                List<Dealer_Package_Term__c> packageTerms = termsByPackageId.containsKey(dp.Id) ? termsByPackageId.get(dp.Id) : new List<Dealer_Package_Term__c>();
                List<Dealer_Package_Option__c> packageOptions = optionsByPackageId.containsKey(dp.Id) ? optionsByPackageId.get(dp.Id) : new List<Dealer_Package_Option__c>();
DealerPackageDTO dto = new DealerPackageDTO();
            dto.Id = dp.Id;
            dto.Name = dp.Name;
            dto.PackageName = dp.Name;
            dto.planTypeId = dp.Plan_Type__c;
            dto.planTypeName = dp.Plan_Type__r != null ? dp.Plan_Type__r.Name : null;
            dto.planTypeDescription = dp.Plan_Type__r != null ? dp.Plan_Type__r.Package_Description__c : null;

            if (String.isNotBlank(dp.Package_Description__c)) {
                dto.PackageDescription = dp.Package_Description__c;
            } else {
                dto.PackageDescription = 'Comprehensive warranty coverage for your vehicle.';
            }
            dto.DealerName = dp.Dealer__r != null ? dp.Dealer__r.Name : null;
            dto.DealerId = dp.Dealer__c;
            dto.PackageClass = dp.Class__c;
            dto.taxRegionId = dp.Dealer__r != null ? dp.Dealer__r.Tax_Region__c : null;
            dto.taxRate = (dp.Dealer__r != null && dp.Dealer__r.Tax_Region__r != null) ? dp.Dealer__r.Tax_Region__r.Total_Tax_Rate__c : null;

            List<DealerPackageTermDTO> termList = new List<DealerPackageTermDTO>(); // Keep for backward compatibility
            List<DealerPackageTierDTO> tierList = new List<DealerPackageTierDTO>(); // NEW: Grouped by tiers
            
            if (packageTerms != null && !packageTerms.isEmpty()) {

                Integer totalTerms = packageTerms.size();
                Integer filteredByTier = 0;
                Integer filteredByEligibility = 0;
                Integer eligibleTerms = 0;
                
                if (isTireRimRequest) {
}
                

                Integer debugCount = 0;
                for (Dealer_Package_Term__c t : packageTerms) {
                    if (debugCount < 10) {
debugCount++;
                    }
                }
                if (packageTerms.size() > 10) {
}
                

                Map<Id, List<Dealer_Package_Term__c>> termsByTierId = new Map<Id, List<Dealer_Package_Term__c>>();
                Map<Id, Dealer_Package_Tier__c> tierMap = new Map<Id, Dealer_Package_Tier__c>();
                
                Integer termIndex = 0;
                for (Dealer_Package_Term__c term : packageTerms) {
                    termIndex++;
if (term == null) {
continue;
                    }
                    

                    if (!isTireRimRequest && term.Dealer_Package_Tier__c == null) {
                        // Allow tier-less terms to proceed - they will be grouped under the package ID
                        filteredByTier++;
                    }

                    Boolean isEligible = false;
                    if (isTireRimRequest) {

                        String packageClass = dp.Class__c;
isEligible = isTermEligibleForTireRim(term, vehicleYear, vehicleClass, packageClass);
                        if (!isEligible) {
filteredByEligibility++;
                            continue;
                        }
} else {

                        isEligible = isWarrantyTermEligible(term, vehicleYear, vehicleOdometer, vehicleOdometerUnit);
                        if (!isEligible) {
continue;
                        }
                    }
                    
                    eligibleTerms++;

                    Id tierId = term.Dealer_Package_Tier__c;
                    if (tierId == null && isTireRimRequest) {

                        tierId = dp.Id;
}
                    
                    if (!termsByTierId.containsKey(tierId)) {
                        termsByTierId.put(tierId, new List<Dealer_Package_Term__c>());
}
                    termsByTierId.get(tierId).add(term);

                    if (term.Dealer_Package_Tier__r != null) {
                        tierMap.put(tierId, term.Dealer_Package_Tier__r);
} else {
}
                }
                

                if (isTireRimRequest) {
if (eligibleTerms == 0 && totalTerms > 0) {
}
}
for (Id tierId : termsByTierId.keySet()) {
}
                

for (Id tierId : termsByTierId.keySet()) {
                    List<Dealer_Package_Term__c> tierTerms = termsByTierId.get(tierId);
if (tierTerms.isEmpty()) {
continue; // Skip empty tiers
                    }
                    

                    tierTerms.sort(new MileageComparator());
DealerPackageTierDTO tierDto = new DealerPackageTierDTO();
                    
                    if (tierMap.containsKey(tierId)) {
                        Dealer_Package_Tier__c tier = tierMap.get(tierId);
                        tierDto.Id = tier.Id;
                        tierDto.Name = tier.Name;
                        tierDto.mileageRestrictionStart = tier.Minimum__c;
                        tierDto.mileageRestrictionEnd = tier.Maximum__c;
                        tierDto.mileageUnit = tier.Mileage_Unit__c;
                    } else {

                        tierDto.Id = String.valueOf(tierId);
                        tierDto.Name = 'Tier ' + String.valueOf(tierId);
                        tierDto.mileageRestrictionStart = null;
                        tierDto.mileageRestrictionEnd = null;
                        tierDto.mileageUnit = null;
                    }
                    

                    List<DealerPackageTermDTO> tierTermList = new List<DealerPackageTermDTO>();
for (Dealer_Package_Term__c term : tierTerms) {
DealerPackageTermDTO termDto = new DealerPackageTermDTO();
                        termDto.Id = term.Id;
                        

                        termDto.originalPackageTermCost = term.Original_Package_Term_Cost__c != null ? term.Original_Package_Term_Cost__c : 0;
                        termDto.includedOptionsPrice = term.Included_Options_Price__c != null ? term.Included_Options_Price__c : 0;
                        termDto.additionalOptionsPrice = term.Additional_Options_Price__c != null ? term.Additional_Options_Price__c : 0;
                        termDto.discountType = term.Discount_Type__c;
                        termDto.discountValue = term.Discount_Value__c != null ? term.Discount_Value__c : 0;
                        termDto.markup = term.Markup__c != null ? term.Markup__c : 0;
                        termDto.markupType = term.Markup_Type__c != null ? term.Markup_Type__c : '';
                        termDto.deductible = dp.Deductable__c;
                        termDto.perClaimLimit = dp.Per_Claim_Limit__c;
                        

                        Decimal basePrice = termDto.originalPackageTermCost + termDto.includedOptionsPrice + termDto.additionalOptionsPrice;
                        Decimal discountAmount = 0;
                        if (termDto.discountType == '$' && termDto.discountValue > 0) {
                            discountAmount = termDto.discountValue;
                        } else if (termDto.discountType == '%' && termDto.discountValue > 0) {
                            discountAmount = (basePrice * termDto.discountValue) / 100;
                        }
                        
                        termDto.netCost = term.Net_Cost__c != null ? term.Net_Cost__c : (basePrice - discountAmount);
                        

                        Decimal priceWithMarkup = termDto.netCost;
                        if (termDto.markupType == '%' && termDto.markup > 0) {
                            priceWithMarkup = termDto.netCost + (termDto.netCost * termDto.markup / 100);
                        } else if (termDto.markupType == '$' && termDto.markup > 0) {
                            priceWithMarkup = termDto.netCost + termDto.markup;
                        }
                        



                        Decimal totalTaxableAmount = priceWithMarkup + termDto.additionalOptionsPrice;
                        

                        Decimal taxRate = dp.Dealer__r != null && dp.Dealer__r.Tax_Region__r != null ? dp.Dealer__r.Tax_Region__r.Total_Tax_Rate__c : null;
                        Decimal taxAmount = 0;
                        if (taxRate != null && taxRate > 0) {
                            taxAmount = totalTaxableAmount * (taxRate / 100);
                        }
                        

                        termDto.taxRate = taxRate != null ? taxRate : 0;
                        termDto.taxAmount = taxAmount;
                        

                        termDto.totalPrice = priceWithMarkup;
                        

                        termDto.durationRestrictionInMonths = null;
                        termDto.mileageRestriction = term.Mileage_Restriction__c;
                        termDto.mileageUnit = term.Mileage_Unit__c;
                        termDto.packageTermName = term.Name;
                        termDto.expiryTerm = term.Expiry_Term__c;
                        termDto.odometerKM = term.Odometer_KM__c;
                        termDto.allowDeferral = term.Package_Term__r != null && term.Package_Term__r.Allow_Deferral__c == true;

                        tierTermList.add(termDto);
                        termList.add(termDto); // Also add to flat list for backward compatibility
}
                    
                    tierDto.terms = tierTermList;
                    tierList.add(tierDto);
}
            } else {
}
            
            dto.terms = termList; // Keep for backward compatibility
            dto.tiers = tierList; // NEW: Grouped by tiers

            List<DealerPackageOptionDTO> optionList = new List<DealerPackageOptionDTO>();
            if (packageOptions != null && !packageOptions.isEmpty()) {
for (Dealer_Package_Option__c option : packageOptions) {
                    DealerPackageOptionDTO optionDto = new DealerPackageOptionDTO();
                    optionDto.Id = option.Id;
                    optionDto.Name = option.Name;
                    optionDto.optionName = option.Option__r != null ? option.Option__r.Name : null;
                    optionDto.inclusion = option.Inclusion__c;
                    optionDto.exclusion = option.Exclusion__c;
                    optionList.add(optionDto);
                }
            } else {
}
            dto.options = optionList;

            if (!termList.isEmpty()) {
                packageList.add(dto);
} else {

                if (isTireRimRequest) {
if (String.isBlank(vehicleClass)) {
}
                    if (String.isBlank(vehicleYear)) {
}
                    if (String.isNotBlank(dp.Class__c) && String.isNotBlank(vehicleClass) && !vehicleClass.equalsIgnoreCase(dp.Class__c)) {
}
} else {
}
            }
            } catch (Exception pkgEx) {

            }
        }
        

        if (isTireRimRequest) {
if (packageList.isEmpty() && !dealerPackages.isEmpty()) {
}
}
for (Integer i = 0; i < packageList.size(); i++) {
            DealerPackageDTO pkg = packageList[i];
}
        

        String responseMessage = 'Dealer packages loaded successfully';
        if (packageList.isEmpty()) {
            if (dealerPackages.isEmpty()) {
                responseMessage = 'No packages found for this dealer with record type: ' + recordType;
            } else {
                if (isTireRimRequest) {
                    responseMessage = 'Found ' + dealerPackages.size() + ' Tire & Rim packages but all were filtered out (no eligible terms). Check debug logs for details.';
                } else {
                    responseMessage = 'Found ' + dealerPackages.size() + ' packages but all were filtered out (no terms available)';
                }
            }
        }
        
        DealerPackagesResponse response = new DealerPackagesResponse();
        response.success = true;
        response.message = responseMessage;
        response.data = packageList;
        

        Map<String, Object> debugInfo = new Map<String, Object>();
        debugInfo.put('queriedPackagesCount', dealerPackages.size());
        debugInfo.put('finalPackagesCount', packageList.size());
        debugInfo.put('filteredOutCount', dealerPackages.size() - packageList.size());
        debugInfo.put('recordType', recordType);
        debugInfo.put('dealerId', dealerId);
        debugInfo.put('hasSpecificRecordTypePackages', hasSpecificRecordTypePackages);
        response.debugInfo = debugInfo;
logMethodExit(methodName, true, packageList.size());
        return response;
        
    } catch (Exception e) {
Map<String, Object> errorResponse = createErrorResponse(methodName, e, 'Error loading dealer packages: ' + e.getMessage());
        DealerPackagesResponse response = new DealerPackagesResponse();
        response.success = (Boolean) errorResponse.get('success');

        String errorMsg = 'Error loading dealer packages';
        if (String.isNotBlank(e.getMessage())) {
            errorMsg += ': ' + e.getMessage();
        }
        response.message = errorMsg;
        response.data = null;
        logMethodExit(methodName, false, null);
        return response;
    }
}

/**
 * Helper method to fetch dealer packages without sharing restrictions
 * 
 * This method is used when partner users don't have access to dealer packages
 * due to sharing rules. It bypasses sharing restrictions to ensure all users
 * can access the necessary package data for their applications.
 * 
 * @param dealerId The ID of the dealer to fetch packages for
 * @return List of Dealer_Package__c records with all related data including:
 *         - Package terms with pricing and markup information
 *         - Included options with selection details
 *         - Package metadata (name, description, deductible)
 * 
 * @throws QueryException if the dealer ID is invalid or no packages are found
 * @throws DmlException if there are issues with data access permissions
 */
private static List<Dealer_Package__c> getDealerPackagesWithoutSharing(String dealerId, String recordType) {
    try {
        if (String.isBlank(dealerId)) {
            return new List<Dealer_Package__c>();
        }
        

        List<Dealer_Package__c> packages = queryDealerPackages(dealerId, false, recordType);
        
        
        return packages;
        
    } catch (Exception e) {
return new List<Dealer_Package__c>();
    }
}

/**
 * Get existing application package for an application
 * @param applicationId The ID of the application
 * @return ApplicationPackageResponse containing existing package data or null if none exists
 */
@AuraEnabled
public static ApplicationPackageResponse getExistingApplicationPackage(String applicationId) {
    try {
        

        List<Application_Package__c> existingPackages = [
            SELECT Id, Name, Application__c, Dealer__c, Dealer_Package__c, Dealer_Package_Term__c,
                    Dealer_Package__r.Name, Dealer_Package__r.Package_Description__c,
                    Dealer_Package__r.Dealer__r.Name, Dealer_Package__r.Dealer__r.Id,
                    Dealer_Package_Term__r.Name, Dealer_Package_Term__r.Month__c,
                    Dealer_Package_Term__r.Mileage_Restriction__c,
                    Dealer_Package_Term__r.Mileage_Unit__c,
                    Dealer_Package_Term__r.Original_Package_Term_Cost__c,
                    Dealer_Package_Price__c, Dealer_Markup__c, Deductible__c,
                    CreatedDate, LastModifiedDate
            FROM Application_Package__c 
            WHERE Application__c = :applicationId
            LIMIT 1
        ];
        
        if (existingPackages.isEmpty()) {
            ApplicationPackageResponse response = new ApplicationPackageResponse();
            response.success = true;
            response.message = 'No existing package found';
            response.data = null;
            return response;
        }
        
        Application_Package__c existingPackage = existingPackages[0];
        

        Map<String, Object> packageData = new Map<String, Object>();
        packageData.put('Id', existingPackage.Id);
        packageData.put('applicationId', existingPackage.Application__c);
        packageData.put('dealerId', existingPackage.Dealer__c);
        packageData.put('dealerPackageId', existingPackage.Dealer_Package__c);
        packageData.put('packageName', existingPackage.Dealer_Package__r.Name);
        packageData.put('packageDescription', existingPackage.Dealer_Package__r.Package_Description__c);
        packageData.put('dealerName', existingPackage.Dealer_Package__r.Dealer__r.Name);
        packageData.put('createdDate', existingPackage.CreatedDate);
        packageData.put('lastModifiedDate', existingPackage.LastModifiedDate);
        

        if (existingPackage.Dealer_Package_Term__c != null) {
            packageData.put('selectedTermId', existingPackage.Dealer_Package_Term__c);
            packageData.put('selectedTermName', existingPackage.Dealer_Package_Term__r.Name);
            packageData.put('selectedTermDuration', existingPackage.Dealer_Package_Term__r.Month__c);
            packageData.put('selectedTermMileage', existingPackage.Dealer_Package_Term__r.Mileage_Restriction__c);
            packageData.put('selectedTermMileageUnit', existingPackage.Dealer_Package_Term__r.Mileage_Unit__c);
            packageData.put('selectedTermPrice', existingPackage.Dealer_Package_Term__r.Original_Package_Term_Cost__c);
        }
        

        packageData.put('dealerPackagePrice', existingPackage.Dealer_Package_Price__c);
        packageData.put('dealerMarkup', existingPackage.Dealer_Markup__c);
        packageData.put('deductible', existingPackage.Deductible__c);
        
        ApplicationPackageResponse response = new ApplicationPackageResponse();
        response.success = true;
        response.message = 'Existing application package found';
        response.data = packageData;
        return response;
        
    } catch (Exception e) {
ApplicationPackageResponse response = new ApplicationPackageResponse();
        response.success = false;
        response.message = 'Error fetching existing application package: ' + e.getMessage();
        response.data = null;
        return response;
    }
}

/**
 * Get existing application package for a specific record type
 * @param applicationId The ID of the application
 * @param recordType The record type to filter by (e.g., 'Tire_Rim_Protection_Plan', 'Extended_Limited_Warranty')
 * @return ApplicationPackageResponse containing existing package data or null if none exists
 */
@AuraEnabled
public static ApplicationPackageResponse getExistingApplicationPackageByRecordType(String applicationId, String recordType) {
    try {

        List<Application_Package__c> allPackages = [
            SELECT Id, Name, Application__c, RecordType.DeveloperName, RecordType.Name
            FROM Application_Package__c 
            WHERE Application__c = :applicationId
        ];
for (Application_Package__c pkg : allPackages) {
}
        

        List<Application_Package__c> existingPackages = [
            SELECT Id, Name, Application__c, Dealer__c, Dealer_Package__c, Dealer_Package_Term__c,
                    Dealer_Package__r.Name, Dealer_Package__r.Package_Description__c,
                    Dealer_Package__r.Dealer__r.Name, Dealer_Package__r.Dealer__r.Id,
                    Dealer_Package_Term__r.Name, Dealer_Package_Term__r.Month__c,
                    Dealer_Package_Term__r.Mileage_Restriction__c,
                    Dealer_Package_Term__r.Mileage_Unit__c,
                    Dealer_Package_Term__r.Original_Package_Term_Cost__c,
                    Dealer_Package_Price__c, Dealer_Markup__c, Deductible__c,
                    Lender_Lienholder__c, Month__c, Loan_Amount__c, Interest_Rate__c, Payment_Frequency__c,
                    CreatedDate, LastModifiedDate, RecordType.DeveloperName
            FROM Application_Package__c 
            WHERE Application__c = :applicationId
            AND RecordType.DeveloperName = :recordType
            LIMIT 1
        ];
if (existingPackages.isEmpty()) {
            ApplicationPackageResponse response = new ApplicationPackageResponse();
            response.success = true;
            response.message = 'No existing package found for record type: ' + recordType;
            response.data = null;
            return response;
        }
        
        Application_Package__c existingPackage = existingPackages[0];
        

        Map<String, Object> packageData = new Map<String, Object>();
        packageData.put('Id', existingPackage.Id);
        packageData.put('applicationId', existingPackage.Application__c);
        packageData.put('dealerId', existingPackage.Dealer__c);
        packageData.put('dealerPackageId', existingPackage.Dealer_Package__c);
        packageData.put('packageName', existingPackage.Dealer_Package__r.Name);
        packageData.put('packageDescription', existingPackage.Dealer_Package__r.Package_Description__c);
        packageData.put('dealerName', existingPackage.Dealer_Package__r.Dealer__r.Name);
        packageData.put('createdDate', existingPackage.CreatedDate);
        packageData.put('lastModifiedDate', existingPackage.LastModifiedDate);
        packageData.put('recordType', existingPackage.RecordType.DeveloperName);


        packageData.put('lenderLienholder', existingPackage.Lender_Lienholder__c);
        packageData.put('financeLoanTerm', existingPackage.Month__c);
        packageData.put('loanAmount', existingPackage.Loan_Amount__c);
        packageData.put('interestRate', existingPackage.Interest_Rate__c);
        packageData.put('paymentFrequency', existingPackage.Payment_Frequency__c);

        Map<String, Object> debugFilters = new Map<String, Object>{
            'Lender_Lienholder__c' => existingPackage.Lender_Lienholder__c,
            'Month__c' => existingPackage.Month__c,
            'Interest_Rate__c' => existingPackage.Interest_Rate__c,
            'Loan_Amount__c' => existingPackage.Loan_Amount__c,
            'Payment_Frequency__c' => existingPackage.Payment_Frequency__c,
            'lenderLienholder' => packageData.get('lenderLienholder'),
            'financeLoanTerm' => packageData.get('financeLoanTerm'),
            'interestRate' => packageData.get('interestRate'),
            'loanAmount' => packageData.get('loanAmount'),
            'paymentFrequency' => packageData.get('paymentFrequency')
        };
        

        if (existingPackage.Dealer_Package_Term__c != null) {
            packageData.put('selectedTermId', existingPackage.Dealer_Package_Term__c);
            packageData.put('selectedTermName', existingPackage.Dealer_Package_Term__r.Name);
            packageData.put('selectedTermDuration', existingPackage.Dealer_Package_Term__r.Month__c);
            packageData.put('selectedTermMileage', existingPackage.Dealer_Package_Term__r.Mileage_Restriction__c);
            packageData.put('selectedTermMileageUnit', existingPackage.Dealer_Package_Term__r.Mileage_Unit__c);
            packageData.put('selectedTermPrice', existingPackage.Dealer_Package_Term__r.Original_Package_Term_Cost__c);
        }
        

        packageData.put('dealerPackagePrice', existingPackage.Dealer_Package_Price__c);
        packageData.put('dealerMarkup', existingPackage.Dealer_Markup__c);
        packageData.put('deductible', existingPackage.Deductible__c);
        
        ApplicationPackageResponse response = new ApplicationPackageResponse();
        response.success = true;
        response.message = 'Existing application package found for record type: ' + recordType;
        response.data = packageData;
        return response;
        
    } catch (Exception e) {
ApplicationPackageResponse response = new ApplicationPackageResponse();
        response.success = false;
        response.message = 'Error fetching existing application package by record type: ' + e.getMessage();
        response.data = null;
        return response;
    }
}





/**
 * Get ACTIVE application package by record type (with Active__c = true filter)
 * This is a NEW method that doesn't replace getExistingApplicationPackageByRecordType
 * @param applicationId The Application record ID
 * @param recordType The RecordType Developer Name (Extended_Limited_Warranty, Tire_Rim_Protection, Total_Loss_Protection)
 * @return ApplicationPackageResponse with active package data
 */
@AuraEnabled(cacheable=false)
public static ApplicationPackageResponse getActiveApplicationPackageByRecordType(String applicationId, String recordType) {
    try {

        List<Application_Package__c> activePackages = [
            SELECT Id, Name, Application__c, Dealer__c, Dealer_Package__c, Dealer_Package_Term__c,
                    Dealer_Package__r.Name, Dealer_Package__r.Package_Description__c,
                    Dealer_Package__r.Dealer__r.Name, Dealer_Package__r.Dealer__r.Id,
                    Dealer_Package_Term__r.Name, Dealer_Package_Term__r.Month__c,
                    Dealer_Package_Term__r.Mileage_Restriction__c,
                    Dealer_Package_Term__r.Mileage_Unit__c,
                    Dealer_Package_Term__r.Original_Package_Term_Cost__c,
                    Dealer_Package_Term__r.Expiry_Term__c, Odometer_End__c, Odometer_End_Unit__c,
                    Dealer_Package_Price__c, Dealer_Markup__c, Deductible__c,
                    Dealer_Package_Retail_Price__c, Add_Ons_Price__c, Add_Ons_Markup__c,
                    Add_Ons_Retail_Price__c, Contract_Premium_Price_Without_Tax__c,
                    Tax_Percentage__c, Tax_Amount__c, Contract_Premium_Price__c,
                    Dealer_Price_Override__c,
                    Lender_Lienholder__c, Month__c, Loan_Amount__c, Interest_Rate__c, Payment_Frequency__c,
                    Active__c, CreatedDate, LastModifiedDate, RecordType.DeveloperName
            FROM Application_Package__c 
            WHERE Application__c = :applicationId
                AND RecordType.DeveloperName = :recordType
                AND Active__c = true
            LIMIT 1
        ];
if (activePackages.isEmpty()) {
ApplicationPackageResponse response = new ApplicationPackageResponse();
            response.success = true;
            response.message = 'No active package found for record type: ' + recordType;
            response.data = null;
            return response;
        }
        
        Application_Package__c activePackage = activePackages[0];

        Map<String, Object> packageData = new Map<String, Object>();
        packageData.put('Id', activePackage.Id);
        packageData.put('applicationId', activePackage.Application__c);
        packageData.put('dealerId', activePackage.Dealer__c);
        packageData.put('dealerPackageId', activePackage.Dealer_Package__c);
        packageData.put('packageName', activePackage.Dealer_Package__r.Name);
        packageData.put('packageDescription', activePackage.Dealer_Package__r.Package_Description__c);
        packageData.put('dealerName', activePackage.Dealer_Package__r.Dealer__r.Name);
        packageData.put('createdDate', activePackage.CreatedDate);
        packageData.put('lastModifiedDate', activePackage.LastModifiedDate);
        packageData.put('recordType', activePackage.RecordType.DeveloperName);
        packageData.put('isActive', activePackage.Active__c);
        

        packageData.put('lenderLienholder', activePackage.Lender_Lienholder__c);
        packageData.put('financeLoanTerm', activePackage.Month__c);
        packageData.put('loanAmount', activePackage.Loan_Amount__c);
        packageData.put('interestRate', activePackage.Interest_Rate__c);
        packageData.put('paymentFrequency', activePackage.Payment_Frequency__c);
        

        if (activePackage.Dealer_Package_Term__c != null) {
            packageData.put('selectedTermId', activePackage.Dealer_Package_Term__c);
            packageData.put('selectedTermName', activePackage.Dealer_Package_Term__r.Name);
            packageData.put('selectedTermDuration', activePackage.Dealer_Package_Term__r.Month__c);
            packageData.put('selectedTermMileage', activePackage.Dealer_Package_Term__r.Mileage_Restriction__c);
            packageData.put('selectedTermMileageUnit', activePackage.Dealer_Package_Term__r.Mileage_Unit__c);
            packageData.put('selectedTermPrice', activePackage.Dealer_Package_Term__r.Original_Package_Term_Cost__c);
            packageData.put('expiryTerm', activePackage.Dealer_Package_Term__r.Expiry_Term__c);
        }

        packageData.put('odometerEnd', activePackage.Odometer_End__c);
        packageData.put('odometerEndUnit', activePackage.Odometer_End_Unit__c);
        

        packageData.put('dealerPackagePrice', activePackage.Dealer_Package_Price__c);
        packageData.put('dealerMarkup', activePackage.Dealer_Markup__c);
        packageData.put('deductible', activePackage.Deductible__c);
        packageData.put('dealerPackageRetailPrice', activePackage.Dealer_Package_Retail_Price__c);
        packageData.put('addOnsPrice', activePackage.Add_Ons_Price__c);
        packageData.put('addOnsMarkup', activePackage.Add_Ons_Markup__c);
        packageData.put('addOnsRetailPrice', activePackage.Add_Ons_Retail_Price__c);
        packageData.put('contractPremiumPriceWithoutTax', activePackage.Contract_Premium_Price_Without_Tax__c);
        packageData.put('taxPercentage', activePackage.Tax_Percentage__c);
        packageData.put('taxAmount', activePackage.Tax_Amount__c);
        packageData.put('contractPremiumPrice', activePackage.Contract_Premium_Price__c);
        packageData.put('dealerPriceOverride', activePackage.Dealer_Price_Override__c);

        ApplicationPackageResponse response = new ApplicationPackageResponse();
        response.success = true;
        response.message = 'Active application package found for record type: ' + recordType;
        response.data = packageData;
        return response;
        
    } catch (Exception e) {
ApplicationPackageResponse response = new ApplicationPackageResponse();
        response.success = false;
        response.message = 'Error fetching active application package: ' + e.getMessage();
        response.data = null;
        return response;
    }
}

/**
 * Save application package with Active management
 * Handles the logic: If different package selected, deactivate old and create new
 * If same package, just update existing
 * @param packageDataMap Map containing package data
 * @return ApplicationPackageResponse with result
 */
@AuraEnabled
public static ApplicationPackageResponse savePackageWithActiveManagement(Map<String, Object> packageDataMap) {
    try {

        String applicationId = (String) packageDataMap.get('applicationId');
        String dealerPackageId = (String) packageDataMap.get('dealerPackageId');
        String recordType = (String) packageDataMap.get('recordType');
        
        if (String.isBlank(applicationId) || String.isBlank(dealerPackageId) || String.isBlank(recordType)) {
            throw new CalloutException('Missing required fields: applicationId, dealerPackageId, or recordType');
        }
        

List<Application_Package__c> existingActive;
        try {
            existingActive = [
                SELECT Id, Dealer_Package__c, Dealer_Package_Term__c, Active__c
                FROM Application_Package__c
                WHERE Application__c = :applicationId
                    AND RecordType.DeveloperName = :recordType
                    AND Active__c = true
                LIMIT 1
            ];
} catch (Exception queryError) {

            existingActive = [
                SELECT Id, Dealer_Package__c, Dealer_Package_Term__c
                FROM Application_Package__c
                WHERE Application__c = :applicationId
                    AND RecordType.DeveloperName = :recordType
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
}
        

        
        Application_Package__c packageToSave;
        Boolean isNewPackage = false;
        Boolean isPackageChange = false;
        String oldPackageId = null;
        
        if (existingActive.isEmpty()) {

packageToSave = new Application_Package__c();
            packageToSave.Application__c = applicationId;
            packageToSave.RecordTypeId = getRecordTypeIdHelper('Application_Package__c', recordType);
            packageToSave.Active__c = true; // Explicitly set to true
            isNewPackage = true;
            
        } else {
            Application_Package__c existingPkg = existingActive[0];
            

            String selectedTermId = (String) packageDataMap.get('selectedTermId');
            


            Boolean packageChanged = existingPkg.Dealer_Package__c != dealerPackageId;
            Boolean termChanged = (selectedTermId != null && existingPkg.Dealer_Package_Term__c != selectedTermId);
            
            if (packageChanged || termChanged) {

                String changeReason = packageChanged ? 'Package CHANGED' : 'Term CHANGED';
oldPackageId = existingPkg.Id;
                

                packageToSave = new Application_Package__c();
                packageToSave.Application__c = applicationId;
                packageToSave.RecordTypeId = getRecordTypeIdHelper('Application_Package__c', recordType);
                packageToSave.Active__c = true; // Explicitly set to true
                isNewPackage = true;
                isPackageChange = true;
} else {

packageToSave = existingPkg;
                isNewPackage = false;
            }
        }
        

        String dealerId = (String) packageDataMap.get('dealerId');
        String selectedTermId = (String) packageDataMap.get('selectedTermId');
        
        packageToSave.Dealer__c = dealerId;
        packageToSave.Dealer_Package__c = dealerPackageId;
        packageToSave.Dealer_Package_Term__c = selectedTermId;
        
        // Query the term to get tier information
        Id dealerPackageTierId = null;
        Id packageTierId = null;
        
        if (String.isNotBlank(selectedTermId)) {
            try {
                List<Dealer_Package_Term__c> terms = [
                    SELECT Id, Dealer_Package_Tier__c, Dealer_Package_Tier__r.Package_Tier__c, Package_Tier__c
                    FROM Dealer_Package_Term__c
                    WHERE Id = :selectedTermId
                    LIMIT 1
                ];
                
                if (!terms.isEmpty()) {
                    Dealer_Package_Term__c term = terms[0];
                    dealerPackageTierId = term.Dealer_Package_Tier__c;
                    
                    packageTierId = term.Dealer_Package_Tier__r != null && term.Dealer_Package_Tier__r.Package_Tier__c != null 
                                    ? term.Dealer_Package_Tier__r.Package_Tier__c 
                                    : term.Package_Tier__c;
                }
            } catch (Exception e) {
            }
        }
        
        // Set tier fields on the package
        packageToSave.Dealer_Package_Tier__c = dealerPackageTierId;
        packageToSave.Package_Tier__c = packageTierId;
        

        // Use TaxRegionHelper to populate tax fields from dealer's region
        Decimal dealerTaxRate = TaxRegionHelper.applyDealerTax(packageToSave, dealerId);
        

        if (packageDataMap.containsKey('dealerPackagePrice')) {
            Object priceValue = packageDataMap.get('dealerPackagePrice');
            packageToSave.Dealer_Package_Price__c = priceValue != null ? Decimal.valueOf(String.valueOf(priceValue)) : null;
        }
        if (packageDataMap.containsKey('dealerPriceOverride')) {
            Object overrideValue = packageDataMap.get('dealerPriceOverride');
            packageToSave.Dealer_Price_Override__c = (overrideValue != null && String.valueOf(overrideValue) != 'null')
                ? Decimal.valueOf(String.valueOf(overrideValue))
                : null;
            // When custom pricing (override) is applied, zero out markups and
            // back-calculate Dealer_Package_Price__c so formula fields like
            // Contract_Premium_Price_Without_Tax__c, Tax_Amount__c, and
            // Dealer_Package_Retail_Price__c reflect the custom price correctly.
            if (packageToSave.Dealer_Price_Override__c != null) {
                packageToSave.Dealer_Markup__c = 0;
                packageToSave.Add_Ons_Markup__c = 0;
                // Override is now pre-tax (LWC sends the raw user-entered value).
                // Store it directly as the base price so formula fields
                // (Contract_Premium_Price_Without_Tax__c, Tax_Amount__c,
                // Dealer_Package_Retail_Price__c) compute correctly.
                packageToSave.Dealer_Package_Price__c = packageToSave.Dealer_Price_Override__c;
            } else {
                // Override removed — restore original base price and markup from
                // the Dealer_Package_Term__c record so the summary shows the
                // correct retail price instead of stale back-calculated values.
                String termIdForRestore = (String) packageDataMap.get('selectedTermId');
                if (String.isBlank(termIdForRestore)) {
                    termIdForRestore = packageToSave.Dealer_Package_Term__c;
                }
                if (String.isNotBlank(termIdForRestore)) {
                    List<Dealer_Package_Term__c> originalTerms = [
                        SELECT Original_Package_Term_Cost__c, Net_Cost__c, Markup__c
                        FROM Dealer_Package_Term__c
                        WHERE Id = :termIdForRestore
                        LIMIT 1
                    ];
                    if (!originalTerms.isEmpty()) {
                        Dealer_Package_Term__c origTerm = originalTerms[0];
                        Decimal origCost = origTerm.Net_Cost__c != null ? origTerm.Net_Cost__c : origTerm.Original_Package_Term_Cost__c;
                        packageToSave.Dealer_Package_Price__c = origCost;
                        packageToSave.Dealer_Markup__c = origTerm.Markup__c != null ? origTerm.Markup__c : 0;
                        packageToSave.Add_Ons_Markup__c = 0;
                    }
                }
            }
        }
        if (packageDataMap.containsKey('dealerMarkup')) {
            // Only apply markup from the map if no custom price override is active
            if (packageToSave.Dealer_Price_Override__c == null) {
                Object markupValue = packageDataMap.get('dealerMarkup');
                packageToSave.Dealer_Markup__c = markupValue != null ? Decimal.valueOf(String.valueOf(markupValue)) : null;
            }
        }
        if (packageDataMap.containsKey('deductible')) {
            Object deductibleValue = packageDataMap.get('deductible');
            packageToSave.Deductible__c = deductibleValue != null ? Decimal.valueOf(String.valueOf(deductibleValue)) : null;
        }
        

        if (packageDataMap.containsKey('lenderLienholder')) {
            packageToSave.Lender_Lienholder__c = (String) packageDataMap.get('lenderLienholder');
        }
        if (packageDataMap.containsKey('financeLoanTerm')) {
            Object loanTermValue = packageDataMap.get('financeLoanTerm');
            packageToSave.Month__c = loanTermValue != null ? String.valueOf(loanTermValue) : null;
        }
        if (packageDataMap.containsKey('loanAmount')) {
            Object loanAmountValue = packageDataMap.get('loanAmount');
            packageToSave.Loan_Amount__c = loanAmountValue != null ? Decimal.valueOf(String.valueOf(loanAmountValue)) : null;
        }
        if (packageDataMap.containsKey('interestRate')) {
            Object interestRateValue = packageDataMap.get('interestRate');
            packageToSave.Interest_Rate__c = interestRateValue != null ? Decimal.valueOf(String.valueOf(interestRateValue)) : null;
        }
        if (packageDataMap.containsKey('paymentFrequency')) {
            packageToSave.Payment_Frequency__c = (String) packageDataMap.get('paymentFrequency');
        }


        if (packageDataMap.containsKey('tireBrand')) {
            packageToSave.Tire_Brand__c = (String) packageDataMap.get('tireBrand');
        }
        if (packageDataMap.containsKey('tireType')) {
            packageToSave.Tire_Type__c = (String) packageDataMap.get('tireType');
        }
        if (packageDataMap.containsKey('treadDepth')) {
            Object treadDepthVal = packageDataMap.get('treadDepth');
            packageToSave.Tread_Depth__c = (treadDepthVal != null && String.valueOf(treadDepthVal).trim() != '')
                ? Decimal.valueOf(String.valueOf(treadDepthVal))
                : null;
        }
        if (packageDataMap.containsKey('treadDepthUnit')) {
            packageToSave.Tread_Depth_Unit__c = (String) packageDataMap.get('treadDepthUnit');
        }
        if (packageDataMap.containsKey('rimSize')) {
            Object rimSizeVal = packageDataMap.get('rimSize');
            packageToSave.Rim_Size__c = (rimSizeVal != null && String.valueOf(rimSizeVal).trim() != '')
                ? Decimal.valueOf(String.valueOf(rimSizeVal))
                : null;
        }
        if (packageDataMap.containsKey('rimSizeUnit')) {
            packageToSave.Rim_Size_Unit__c = (String) packageDataMap.get('rimSizeUnit');
        }
        if (packageDataMap.containsKey('rimBrand')) {
            packageToSave.Rim_Brand__c = (String) packageDataMap.get('rimBrand');
        }
        if (packageDataMap.containsKey('rimType')) {
            packageToSave.Rim_Type__c = (String) packageDataMap.get('rimType');
        }
        if (packageDataMap.containsKey('dealerComments')) {
            packageToSave.Dealer_Comments__c = (String) packageDataMap.get('dealerComments');
        }
        
        // Generate and set the package name
        try {
            List<Application__c> appForName = [
                SELECT Id, Name
                FROM Application__c
                WHERE Id = :applicationId
                LIMIT 1
            ];
            
            if (!appForName.isEmpty()) {
                String applicationName = appForName[0].Name;
                String recordTypeAbbr = getRecordTypeAbbreviation(recordType);
                packageToSave.Name = applicationName + ' - ' + recordTypeAbbr;
            }
        } catch (Exception e) {
            // If name cannot be generated, continue without setting it
        }
        
if (isNewPackage) {
            insert packageToSave;
} else {
            update packageToSave;
}

        // When the package or term changed, re-link any existing Invoice Line Items
        // from the old package to the new one so invoices reflect updated details.
        if (isPackageChange && String.isNotBlank(oldPackageId)) {
            try {
                List<Invoice_Line_Item__c> lineItemsToRelink = [
                    SELECT Id
                    FROM Invoice_Line_Item__c
                    WHERE Application_Package__c = :oldPackageId
                ];
                if (!lineItemsToRelink.isEmpty()) {
                    for (Invoice_Line_Item__c li : lineItemsToRelink) {
                        li.Application_Package__c = packageToSave.Id;
                    }
                    update lineItemsToRelink;
                }
            } catch (Exception relinkEx) {
                // Non-fatal: log and continue
            }
        }

        // Sync lien holder / financial institution to Application__c so the summary page can read it
        if (packageDataMap.containsKey('lenderLienholder') && String.isNotBlank(applicationId)) {
            try {
                Application__c appToUpdate = new Application__c(Id = applicationId);
                appToUpdate.Financial_Institution_Lender__c = (String) packageDataMap.get('lenderLienholder');
                if (packageDataMap.containsKey('isVehicleFinanced')) {
                    appToUpdate.Is_Vehicle_Financed__c = Boolean.valueOf(String.valueOf(packageDataMap.get('isVehicleFinanced')));
                }
                update appToUpdate;
            } catch (Exception lienEx) {
                // Non-fatal: log and continue
                System.debug('Warning: Could not sync lien holder to Application: ' + lienEx.getMessage());
            }
        }

        populateOdometerAndContractDateFields(String.valueOf(packageToSave.Id), applicationId);
        

        Map<String, Object> responseData = new Map<String, Object>();
        responseData.put('packageId', packageToSave.Id);
        responseData.put('isNewPackage', isNewPackage);
        responseData.put('isPackageChange', isPackageChange);
        responseData.put('active', packageToSave.Active__c);
        responseData.put('oldPackageId', oldPackageId);
        
        String message;
        if (isPackageChange) {
            message = 'Package changed - old package deactivated, new package created';
        } else if (isNewPackage) {
            message = 'New package created and activated';
        } else {
            message = 'Package updated successfully';
        }
        
        ApplicationPackageResponse response = new ApplicationPackageResponse();
        response.success = true;
        response.message = message;
        response.data = responseData;
        return response;
        
    } catch (Exception e) {
ApplicationPackageResponse response = new ApplicationPackageResponse();
        response.success = false;
        response.message = 'Error saving package: ' + e.getMessage();
        response.data = null;
        return response;
    }
}

/**
 * Helper method to get RecordTypeId by DeveloperName
 */
private static Id getRecordTypeIdHelper(String objectName, String developerName) {
    try {
List<RecordType> rts = [
            SELECT Id, DeveloperName 
            FROM RecordType 
            WHERE SObjectType = :objectName 
                AND DeveloperName = :developerName 
            LIMIT 1
        ];
        
        if (rts.isEmpty()) {
List<RecordType> allRts = [SELECT Id, DeveloperName FROM RecordType WHERE SObjectType = :objectName];
            for (RecordType rt : allRts) {
}
            throw new AuraHandledException('RecordType not found: ' + objectName + '.' + developerName);
        }
return rts[0].Id;
        
    } catch (Exception e) {
throw new AuraHandledException('RecordType error: ' + e.getMessage());
    }
}

/**
 * Helper method to get record type abbreviation for package naming
 * Maps record type developer name to single letter abbreviation
 * @param recordType The RecordType DeveloperName
 * @return String Single letter abbreviation (W, T, or P)
 */
private static String getRecordTypeAbbreviation(String recordType) {
    if (recordType == 'Extended_Limited_Warranty') {
        return 'W';
    } else if (recordType == 'Tire_Rim_Protection_Plan') {
        return 'T';
    } else if (recordType == 'GAP_Coverage') {
        return 'P';
    }
    return '';
}

/**
 * Populate odometer and contract date fields on Application_Package__c record
 * Queries the saved package with its Dealer_Package_Term__c and Package_Term__c relationships,
 * then updates with calculated odometer and contract date values.
 * 
 * @param packageId The ID of the Application_Package__c record to update
 * @param applicationId The ID of the related Application__c record
 */
private static void populateOdometerAndContractDateFields(String packageId, String applicationId) {
    try {

        List<Application_Package__c> savedPackages = [
            SELECT Id, Application__c, Dealer_Package_Term__c,
                    RecordType.DeveloperName,
                    Dealer_Package_Term__r.Package_Term__c,
                    Dealer_Package_Term__r.Mileage_Restriction_End__c,
                    Dealer_Package_Term__r.Month__c,
                    Dealer_Package_Term__r.Start_Term__c,
                    Dealer_Package_Term__r.Expiry_Term__c,
                    Dealer_Package_Term__r.Duration_Type__c,
                    Dealer_Package_Term__r.Odometer_KM__c,
                    Dealer_Package_Term__r.Restriction_Type__c
            FROM Application_Package__c
            WHERE Id = :packageId
            LIMIT 1
        ];
        
        if (savedPackages.isEmpty()) {
return;
        }
        
        Application_Package__c savedPackage = savedPackages[0];

        List<Application__c> applicationsForData = [
            SELECT Id, Odometer__c, Odometer_Unit__c, Vehicle__c, 
                    Vehicle__r.Delivery_Date__c, Vehicle__r.Deferral_Option__c, 
                    Vehicle__r.In_Service_Date__c
            FROM Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        
        if (applicationsForData.isEmpty()) {
return;
        }
        
        Application__c appData = applicationsForData[0];

        if (savedPackage.Dealer_Package_Term__r == null || 
            savedPackage.Dealer_Package_Term__r.Package_Term__c == null) {
return;
        }

        Application_Package__c updatePackage = new Application_Package__c();
        updatePackage.Id = savedPackage.Id;
        

        Decimal odometerStartValue = convertOdometerToKilometers(appData.Odometer__c, appData.Odometer_Unit__c);
        updatePackage.Odometer_Start__c = odometerStartValue;

        updatePackage.Odometer_Start_Unit__c = 'KM';

        Decimal odometerEndValue = null;
        String restrictionType = savedPackage.Dealer_Package_Term__r.Restriction_Type__c;
        Decimal odometerKM = savedPackage.Dealer_Package_Term__r.Odometer_KM__c;
        
        if (String.isNotBlank(restrictionType) && odometerKM != null) {
            if (restrictionType == 'Rolling Odometer') {

                odometerEndValue = odometerStartValue + odometerKM;
} else if (restrictionType == 'Fixed Odometer') {

                odometerEndValue = odometerKM;
}
        }
        

        if (odometerEndValue == null && savedPackage.Dealer_Package_Term__r.Mileage_Restriction_End__c != null) {
            odometerEndValue = savedPackage.Dealer_Package_Term__r.Mileage_Restriction_End__c;
}
        
        if (odometerEndValue != null) {
            updatePackage.Odometer_End__c = odometerEndValue;
}
        

        updatePackage.Odometer_End_Unit__c = 'KM';



        Date baseDate = null;
        String dateSource = '';
        String recordTypeDevName = savedPackage.RecordType != null ? savedPackage.RecordType.DeveloperName : '';
        Boolean isWarranty = (recordTypeDevName == 'Extended_Limited_Warranty');
        
        if (appData.Vehicle__r != null) {


            if (isWarranty) {
                Boolean deferralOption = appData.Vehicle__r.Deferral_Option__c != null && appData.Vehicle__r.Deferral_Option__c;
                
                if (deferralOption && appData.Vehicle__r.In_Service_Date__c != null) {

                    baseDate = appData.Vehicle__r.In_Service_Date__c;
                    dateSource = 'In_Service_Date';
} else if (appData.Vehicle__r.Delivery_Date__c != null) {

                    baseDate = appData.Vehicle__r.Delivery_Date__c;
                    dateSource = 'Delivery_Date';
}
            } else {

                if (appData.Vehicle__r.Delivery_Date__c != null) {
                    baseDate = appData.Vehicle__r.Delivery_Date__c;
                    dateSource = 'Delivery_Date';
}
            }
            
            if (baseDate != null) {
                Decimal startTerm = savedPackage.Dealer_Package_Term__r.Start_Term__c;
                Decimal expiryTerm = savedPackage.Dealer_Package_Term__r.Expiry_Term__c;
                String durationType = savedPackage.Dealer_Package_Term__r.Duration_Type__c;
                


                if (startTerm != null && startTerm != 0 && durationType != null) {
                    Date contractStartDate = calculateContractDate(baseDate, startTerm, durationType);
                    updatePackage.Contract_Start_Date__c = contractStartDate;
} else {

                    updatePackage.Contract_Start_Date__c = baseDate;
}
                


                if (expiryTerm != null && durationType != null) {
                    Date contractEndDate = calculateContractDate(baseDate, expiryTerm, durationType);
                    updatePackage.Contract_End_Date__c = contractEndDate;
} else if (expiryTerm == null && savedPackage.Dealer_Package_Term__r.Month__c != null) {

                    Date startDate = baseDate;
                    Integer monthsToAdd = Integer.valueOf(savedPackage.Dealer_Package_Term__r.Month__c);
                    Date endDate = startDate.addMonths(monthsToAdd);
                    updatePackage.Contract_End_Date__c = endDate;
} else {

}
            }
        }
        

        update updatePackage;
} catch (Exception e) {

    }
}





/**
 * Convert odometer value from Miles to Kilometers if needed
 * @param odometerValue The odometer value to convert
 * @param odometerUnit The unit of the odometer (Miles, KM, etc.)
 * @return Decimal The converted odometer value in KM (or original value if not Miles)
 */
private static Decimal convertOdometerToKilometers(Decimal odometerValue, String odometerUnit) {
    try {

        if (String.isNotBlank(odometerUnit) && odometerUnit.equalsIgnoreCase('Miles')) {
            Decimal conversionFactor = 1.60934;
            Decimal convertedValue = odometerValue != null ? odometerValue * conversionFactor : null;
return convertedValue;
        }
        

return odometerValue;
        
    } catch (Exception e) {
return odometerValue; // Return original value on error
    }
}

/**
 * Calculate contract date by adding term to delivery date
 * @param deliveryDate The vehicle delivery date
 * @param term The term value (Start_Term__c or Expiry_Term__c)
 * @param durationType The duration type ('Months' or 'Years')
 * @return Date The calculated contract date
 */
private static Date calculateContractDate(Date deliveryDate, Decimal term, String durationType) {
    if (deliveryDate == null || term == null || String.isBlank(durationType)) {
        return deliveryDate;
    }
    
    Integer termValue = Integer.valueOf(term);
    
    if (durationType.equalsIgnoreCase('Months')) {
        return deliveryDate.addMonths(termValue);
    } else if (durationType.equalsIgnoreCase('Years')) {
        return deliveryDate.addYears(termValue);
    } else {

return deliveryDate.addMonths(termValue);
    }
}







/**
 * Create application package in Salesforce using Map approach (same as vehicle data)
 * @param packageDataMap Map containing application package data
 * @return ApplicationPackageResponse containing success status or error message
 */
@AuraEnabled
public static ApplicationPackageResponse createApplicationPackageFromMap(Map<String, Object> packageDataMap) {
    try {

        if (packageDataMap == null) {
throw new CalloutException('Package data cannot be null');
        }
        

        if (packageDataMap.isEmpty()) {
throw new CalloutException('Package data map is empty');
        }
        
        

        Object appIdObj = packageDataMap.get('applicationId');
        Object dealerIdObj = packageDataMap.get('dealerId');
        Object dealerPackageIdObj = packageDataMap.get('dealerPackageId');
        Object packageNameObj = packageDataMap.get('packageName');
        Object selectedTermIdObj = packageDataMap.get('selectedTermId');
        Object includeDeductibleObj = packageDataMap.get('includeDeductible');
        
        

        String applicationId = appIdObj != null ? String.valueOf(appIdObj) : null;
        String dealerId = dealerIdObj != null ? String.valueOf(dealerIdObj) : null;
        String dealerPackageId = dealerPackageIdObj != null ? String.valueOf(dealerPackageIdObj) : null;
        String packageName = packageNameObj != null ? String.valueOf(packageNameObj) : null;
        String selectedTermId = selectedTermIdObj != null ? String.valueOf(selectedTermIdObj) : null;
        Boolean includeDeductible = includeDeductibleObj != null ? Boolean.valueOf(includeDeductibleObj) : false;
        
        

        if (String.isBlank(applicationId)) {
            throw new CalloutException('Application ID is required');
        }
        
        if (String.isBlank(dealerId)) {
            throw new CalloutException('Dealer ID is required');
        }
        
        if (String.isBlank(dealerPackageId)) {
            throw new CalloutException('Dealer Package ID is required');
        }
        
        if (String.isBlank(selectedTermId)) {
            throw new CalloutException('Term selection is required');
        }
        
        

        Decimal deductible = 0;
        Decimal perClaimLimit = 0;
        

        Id packageTierId = null;
        

        Id dealerPackageTierId = null;
        
        try {

            List<Dealer_Package_Term__c> terms = [
                SELECT Id, Dealer_Package__r.Deductable__c, Dealer_Package__r.Per_Claim_Limit__c, 
                        Dealer_Package_Tier__c, Dealer_Package_Tier__r.Package_Tier__c, Package_Tier__c
                FROM Dealer_Package_Term__c 
                WHERE Id = :selectedTermId 
                LIMIT 1
            ];
            
            if (!terms.isEmpty()) {
                Dealer_Package_Term__c term = terms[0];
                deductible = term.Dealer_Package__r.Deductable__c != null ? term.Dealer_Package__r.Deductable__c : 0;
                perClaimLimit = term.Dealer_Package__r.Per_Claim_Limit__c != null ? term.Dealer_Package__r.Per_Claim_Limit__c : 0;

                dealerPackageTierId = term.Dealer_Package_Tier__c;

                packageTierId = term.Dealer_Package_Tier__r != null && term.Dealer_Package_Tier__r.Package_Tier__c != null 
                                ? term.Dealer_Package_Tier__r.Package_Tier__c 
                                : term.Package_Tier__c;
                

} else {
}
        } catch (Exception e) {


        }
        

        Application_Package__c appPackage = new Application_Package__c();
        

        appPackage.Application__c = applicationId;
        appPackage.Dealer__c = dealerId;
        appPackage.Dealer_Package__c = dealerPackageId;
        appPackage.Dealer_Package_Term__c = selectedTermId;
        appPackage.Dealer_Package_Tier__c = dealerPackageTierId;
        appPackage.Package_Tier__c = packageTierId;
        


        appPackage.Deductible__c = includeDeductible ? deductible : 0;
        appPackage.Per_Claim_Limit__c = perClaimLimit;
        

        String recordTypeName = (String) packageDataMap.get('recordType');
        if (String.isBlank(recordTypeName)) {
            recordTypeName = 'Extended_Limited_Warranty'; // Default for warranty
        }
        
        try {
            appPackage.RecordTypeId = Schema.SObjectType.Application_Package__c.getRecordTypeInfosByDeveloperName().get(recordTypeName).getRecordTypeId();
} catch (Exception e) {

            try {
                appPackage.RecordTypeId = Schema.SObjectType.Application_Package__c.getRecordTypeInfosByDeveloperName().get('Extended_Limited_Warranty').getRecordTypeId();
} catch (Exception fallbackException) {
}
        }
        
        

        String recordId = null;
        try {
        insert appPackage;
            recordId = appPackage.Id;
        } catch (Exception insertException) {
            

            try {
                recordId = createApplicationPackageWithoutSharing(applicationId, dealerId, dealerPackageId, packageName, selectedTermId, includeDeductible ? deductible : 0, recordTypeName);
                if (recordId != null) {

                } else {
throw new CalloutException('Failed to create application package with both sharing and non-sharing methods');
                }
            } catch (Exception helperException) {
throw new CalloutException('Failed to create application package: ' + helperException.getMessage());
            }
        }
        

        

        ApplicationPackageResponse response = new ApplicationPackageResponse();
        response.success = true;
        response.message = 'Application package created successfully';
        response.recordId = recordId;
        

        return response;
        
    } catch (Exception e) {
ApplicationPackageResponse response = new ApplicationPackageResponse();
        response.success = false;
        response.message = 'Error creating application package: ' + e.getMessage();
        response.recordId = null;
        return response;
    }
}

/**
 * Create application package using individual parameters (alternative to Map approach)
 * @param applicationId Application ID
 * @param dealerId Dealer ID
 * @param dealerPackageId Dealer Package ID
 * @param packageName Package Name
 * @param selectedTermId Selected Term ID
 * @param includeDeductible Include Deductible flag
 * @param recordType Record Type
 * @return ApplicationPackageResponse containing success status or error message
 */
@AuraEnabled
public static ApplicationPackageResponse createApplicationPackageFromParams(
    String applicationId, 
    String dealerId, 
    String dealerPackageId, 
    String packageName, 
    String selectedTermId, 
    Boolean includeDeductible, 
    String recordType) {
    
    try {

        if (String.isBlank(applicationId)) {
            throw new CalloutException('Application ID is required');
        }
        
        if (String.isBlank(dealerId)) {
            throw new CalloutException('Dealer ID is required');
        }
        
        if (String.isBlank(dealerPackageId)) {
            throw new CalloutException('Dealer Package ID is required');
        }
        
        if (String.isBlank(packageName)) {
            throw new CalloutException('Package Name is required');
        }
        
        if (String.isBlank(selectedTermId)) {
            throw new CalloutException('Term selection is required');
        }
        
        if (String.isBlank(recordType)) {
            throw new CalloutException('Record Type is required');
        }
        

        Decimal deductible = 0;
        Decimal perClaimLimit = 0;
        

        Id dealerPackageTierId = null;
        Id packageTierId = null;
        
        try {

            List<Dealer_Package_Term__c> terms = [
                SELECT Id, Markup__c, Dealer_Package__r.Deductable__c, Dealer_Package__r.Per_Claim_Limit__c,
                        Original_Package_Term_Cost__c, Included_Options_Price__c, Additional_Options_Price__c,
                        Discount_Type__c, Discount_Value__c, Dealer_Package_Tier__c,
                        Dealer_Package_Tier__r.Package_Tier__c, Package_Tier__c
                FROM Dealer_Package_Term__c 
                WHERE Id = :selectedTermId 
                LIMIT 1
            ];
            
            if (!terms.isEmpty()) {
                Dealer_Package_Term__c term = terms[0];
                deductible = includeDeductible && term.Dealer_Package__r.Deductable__c != null 
                            ? term.Dealer_Package__r.Deductable__c 
                            : 0;
                perClaimLimit = term.Dealer_Package__r.Per_Claim_Limit__c != null 
                                ? term.Dealer_Package__r.Per_Claim_Limit__c 
                                : 0;

                dealerPackageTierId = term.Dealer_Package_Tier__c;

                packageTierId = term.Dealer_Package_Tier__r != null && term.Dealer_Package_Tier__r.Package_Tier__c != null 
                                ? term.Dealer_Package_Tier__r.Package_Tier__c 
                                : term.Package_Tier__c;
                

} else {
}
        } catch (Exception e) {
deductible = 0;
        }
        

        Application_Package__c appPackage = new Application_Package__c();
        appPackage.Application__c = applicationId;
        appPackage.Dealer__c = dealerId;
        appPackage.Dealer_Package__c = dealerPackageId;
        appPackage.Dealer_Package_Term__c = selectedTermId;
        appPackage.Dealer_Package_Tier__c = dealerPackageTierId;
        appPackage.Package_Tier__c = packageTierId;
        

appPackage.Deductible__c = deductible;
        appPackage.Per_Claim_Limit__c = perClaimLimit;
        appPackage.RecordTypeId = Schema.SObjectType.Application_Package__c.getRecordTypeInfosByDeveloperName().get(recordType).getRecordTypeId();
        

        insert appPackage;
ApplicationPackageResponse response = new ApplicationPackageResponse();
        response.success = true;
        response.message = 'Application package created successfully';
        response.recordId = appPackage.Id;
        response.data = new Map<String, Object>{
            'Id' => appPackage.Id,
            'applicationId' => applicationId,
            'dealerId' => dealerId,
            'dealerPackageId' => dealerPackageId,
            'packageName' => packageName,
            'selectedTermId' => selectedTermId,
            'includeDeductible' => includeDeductible,
            'recordType' => recordType
        };
        
        return response;
        
    } catch (Exception e) {
ApplicationPackageResponse response = new ApplicationPackageResponse();
        response.success = false;
        response.message = 'Error creating application package: ' + e.getMessage();
        response.recordId = null;
        response.data = null;
        return response;
    }
}

/**
 * Update existing application package
 * @param packageDataMap Map containing application package data for update
 * @return ApplicationPackageResponse containing success status or error message
 */
@AuraEnabled
public static ApplicationPackageResponse updateApplicationPackage(Map<String, Object> packageDataMap) {
    try {


        

        if (packageDataMap == null) {
            throw new CalloutException('Package data cannot be null');
        }
        

        Object packageIdObj = packageDataMap.get('packageId');
        Object selectedTermIdObj = packageDataMap.get('selectedTermId');
        Object includeDeductibleObj = packageDataMap.get('includeDeductible');
        




        

        String packageId = packageIdObj != null ? String.valueOf(packageIdObj) : null;
        String selectedTermId = selectedTermIdObj != null ? String.valueOf(selectedTermIdObj) : null;
        Boolean includeDeductible = includeDeductibleObj != null ? Boolean.valueOf(includeDeductibleObj) : false;
        




        

        if (String.isBlank(packageId)) {
throw new CalloutException('Package ID is required for update');
        }
        




        

        

        Decimal netCost = 0;
        Decimal markup = 0;
        Decimal deductible = 0;
        Decimal totalPrice = 0;
        Id dealerPackageTierId = null;
        Id packageTierId = null;
        
        try {

            if (!String.isBlank(selectedTermId)) {

                List<Dealer_Package_Term__c> terms = [
                    SELECT Id, Markup__c, Dealer_Package__r.Deductable__c,
                            Original_Package_Term_Cost__c, Included_Options_Price__c, Additional_Options_Price__c,
                            Discount_Type__c, Discount_Value__c, Dealer_Package_Tier__c,
                            Dealer_Package_Tier__r.Package_Tier__c, Package_Tier__c
                    FROM Dealer_Package_Term__c 
                    WHERE Id = :selectedTermId 
                    LIMIT 1
                ];
            
            if (!terms.isEmpty()) {
                Dealer_Package_Term__c term = terms[0];
                

                Decimal originalPackageTermCost = term.Original_Package_Term_Cost__c != null ? term.Original_Package_Term_Cost__c : 0;
                Decimal additionalOptionsPrice = term.Additional_Options_Price__c != null ? term.Additional_Options_Price__c : 0;
                Decimal includedOptionsPrice = term.Included_Options_Price__c != null ? term.Included_Options_Price__c : 0;
                String discountType = term.Discount_Type__c;
                Decimal discountValue = term.Discount_Value__c != null ? term.Discount_Value__c : 0;
                markup = term.Markup__c != null ? term.Markup__c : 0;
                deductible = term.Dealer_Package__r.Deductable__c != null ? term.Dealer_Package__r.Deductable__c : 0;
                

                Id dealerPackageTierIdFromTerm = term.Dealer_Package_Tier__c;

                Id tierIdFromRelationship = term.Dealer_Package_Tier__r != null && term.Dealer_Package_Tier__r.Package_Tier__c != null 
                                            ? term.Dealer_Package_Tier__r.Package_Tier__c 
                                            : term.Package_Tier__c;
                dealerPackageTierId = dealerPackageTierIdFromTerm;
                packageTierId = tierIdFromRelationship;
                








                
                Decimal dealerPackagePrice;
                if (String.isBlank(discountType)) {

                    dealerPackagePrice = originalPackageTermCost + additionalOptionsPrice + includedOptionsPrice;

                } else if (discountType == '$') {

                    dealerPackagePrice = (originalPackageTermCost - discountValue) + additionalOptionsPrice + includedOptionsPrice;

                } else if (discountType == '%') {

                    Decimal discountAmount = (originalPackageTermCost * discountValue) / 100;
                    dealerPackagePrice = (originalPackageTermCost - discountAmount) + additionalOptionsPrice + includedOptionsPrice;

                } else {

                    dealerPackagePrice = originalPackageTermCost + additionalOptionsPrice + includedOptionsPrice;

                }
                

                netCost = dealerPackagePrice;
                

                totalPrice = netCost + markup;
                

                if (includeDeductible && deductible > 0) {
                    totalPrice += deductible;
                }
                











            }
            } else {


            }
        } catch (Exception e) {


        }
        

        List<Application_Package__c> existingPackages = [
            SELECT Id, Application__c, Dealer__c, Dealer_Package__c, Dealer_Package_Term__c,
                    Dealer_Package_Price__c, /* Dealer_Markup__c, */ Deductible__c
            FROM Application_Package__c 
            WHERE Id = :packageId 
            LIMIT 1
        ];
        
        if (existingPackages.isEmpty()) {
throw new CalloutException('Application package not found');
        }
        
        Application_Package__c appPackage = existingPackages[0];
        

        String originalTermId = appPackage.Dealer_Package_Term__c;
        Decimal originalPrice = appPackage.Dealer_Package_Price__c;

        Decimal originalMarkup = 0; // Temporarily set to 0 while field type is being changed
        Decimal originalDeductible = appPackage.Deductible__c;
        





        

        Decimal newDeductible = includeDeductible ? deductible : 0;
        

        Boolean hasChanges = false;
        String changesList = '';
        

        if (!String.isBlank(selectedTermId) && originalTermId != selectedTermId) {
            appPackage.Dealer_Package_Term__c = selectedTermId;

            if (dealerPackageTierId != null) {
                appPackage.Dealer_Package_Tier__c = dealerPackageTierId;
            }
            if (packageTierId != null) {
                appPackage.Package_Tier__c = packageTierId;
            }
            hasChanges = true;
            changesList += 'Term ID: ' + originalTermId + ' → ' + selectedTermId + '; ';
}
        

        if (!String.isBlank(selectedTermId) && originalPrice != netCost) {
            appPackage.Dealer_Package_Price__c = netCost;
            hasChanges = true;
            changesList += 'Dealer Package Price: ' + originalPrice + ' → ' + netCost + '; ';
}
        







        

        if (originalDeductible != newDeductible) {
            appPackage.Deductible__c = newDeductible;
            hasChanges = true;
            changesList += 'Deductible: ' + originalDeductible + ' → ' + newDeductible + '; ';
}
        
        if (!hasChanges) {

            ApplicationPackageResponse response = new ApplicationPackageResponse();
            response.success = true;
            response.message = 'No changes detected - no update needed';
            response.recordId = packageId;
            return response;
        }






        

        String recordId = null;
        try {

            update appPackage;
            recordId = appPackage.Id;

        } catch (Exception updateException) {


            

            try {

                recordId = updateApplicationPackageWithoutSharing(packageId, selectedTermId, totalPrice, markup, includeDeductible ? deductible : 0);
                if (recordId != null) {

                } else {
throw new CalloutException('Failed to update application package with both sharing and non-sharing methods');
                }
            } catch (Exception helperException) {
throw new CalloutException('Failed to update application package: ' + helperException.getMessage());
            }
        }
        

        

        ApplicationPackageResponse response = new ApplicationPackageResponse();
        response.success = true;
        response.message = 'Application package updated successfully';
        response.recordId = recordId;
        

        return response;
        
    } catch (Exception e) {
ApplicationPackageResponse response = new ApplicationPackageResponse();
        response.success = false;
        response.message = 'Error updating application package: ' + e.getMessage();
        response.recordId = null;
        return response;
    }
}


/**
 * Save vehicle data (create new or update existing)
 * @param vehicleData The vehicle data to save
 * @return Map containing save result
 */
@AuraEnabled
public static Map<String, Object> saveVehicleData(Map<String, Object> vehicleDataMap) {
    Map<String, Object> result = new Map<String, Object>();
    result.put('success', false);
    result.put('message', '');
    
    try {

        
        if (vehicleDataMap == null) {
            throw new CalloutException('Vehicle data cannot be null');
        }
        

        // When Manufacturer Warranty Type is selected, Term and In-Service Date are also required
        String manufacturerWarrantyType = (String) vehicleDataMap.get('manufacturerWarrantyType');
        if (String.isNotBlank(manufacturerWarrantyType)) {
            String warrantyTerm = (String) vehicleDataMap.get('warrantyTerm');
            String warrantyInServiceDate = (String) vehicleDataMap.get('warrantyInServiceDate');

            if (String.isBlank(warrantyTerm) || String.isBlank(warrantyInServiceDate)) {
                result.put('success', false);
                result.put('message', 'Warranty Term and In-Service Date are required when Manufacturer Warranty Type is selected.');
                return result;
            }
        }
        
        String vehicleId = (String) vehicleDataMap.get('vehicleId');
        Boolean isUpdate = false;
        String applicationId = (String) vehicleDataMap.get('applicationId');
        


        if (String.isNotBlank(vehicleId)) {
            try {

                Id validId = vehicleId;
                isUpdate = true;
            } catch (Exception e) {
                isUpdate = false;
                vehicleId = null;
            }
        }

        Vehicle__c vehicle;
        if (isUpdate && String.isNotBlank(vehicleId)) {
            vehicle = [SELECT Id FROM Vehicle__c WHERE Id = :vehicleId LIMIT 1];
        } else {
            vehicle = new Vehicle__c();
        }


        vehicle.Stock_Number__c = (String) vehicleDataMap.get('stockNumber');
        vehicle.VIN__c = (String) vehicleDataMap.get('vin');
        vehicle.Vehicle_Identification_Number_VIN__c = (String) vehicleDataMap.get('vehicleIdentificationNumberVIN');
        vehicle.Year__c = (String) vehicleDataMap.get('year');
        vehicle.Make__c = (String) vehicleDataMap.get('make');
        vehicle.Model__c = (String) vehicleDataMap.get('model');
        vehicle.Trim__c = (String) vehicleDataMap.get('trim');

        Object dateSoldObj = vehicleDataMap.get('dateVehicleSold');
        if (dateSoldObj != null && String.isNotBlank((String) dateSoldObj)) {
            try {
                vehicle.Date_Vehicle_Sold__c = Date.valueOf((String) dateSoldObj);

            } catch (Exception e) {
vehicle.Date_Vehicle_Sold__c = null;
            }
        } else {
            vehicle.Date_Vehicle_Sold__c = null;
        }

        Object purchasePriceObj = vehicleDataMap.get('vehiclePurchasePrice');
        if (purchasePriceObj != null && purchasePriceObj != '') {
            try {
                vehicle.Vehicle_Purchase_Price__c = (Decimal) purchasePriceObj;
            } catch (Exception e) {
                vehicle.Vehicle_Purchase_Price__c = 0;
            }
        } else {
            vehicle.Vehicle_Purchase_Price__c = 0;
        }
        
        vehicle.Branded_Rebuilt__c = (Boolean) vehicleDataMap.get('isBrandedRebuilt');

        Object warrantyInServiceDateObj = vehicleDataMap.get('warrantyInServiceDate');
        
        if (warrantyInServiceDateObj != null && String.isNotBlank((String) warrantyInServiceDateObj)) {
            try {
                vehicle.In_Service_Date__c = Date.valueOf((String) warrantyInServiceDateObj);

            } catch (Exception e) {
vehicle.In_Service_Date__c = null;
            }
        } else {
            vehicle.In_Service_Date__c = null;
        }
        

        Object odometerObj = vehicleDataMap.get('odometer');
        if (odometerObj != null && odometerObj != '') {
            try {
                vehicle.Odometer__c = (Decimal) odometerObj;
            } catch (Exception e) {
                vehicle.Odometer__c = 0;
            }
        } else {
            vehicle.Odometer__c = 0;
        }
        vehicle.Odometer_Unit__c = (String) vehicleDataMap.get('odometerUnit');
        vehicle.Business_Commercial_Use__c = (Boolean) vehicleDataMap.get('businessCommercialUse');
        vehicle.Type_of_Commercial_Use__c = (String) vehicleDataMap.get('typeOfCommercialUse');
        

        vehicle.Engine__c = (String) vehicleDataMap.get('engine');
        vehicle.Transmission__c = (String) vehicleDataMap.get('transmission');
        vehicle.Fuel_Type__c = (String) vehicleDataMap.get('fuelType');
        vehicle.Drive_Type__c = (String) vehicleDataMap.get('driveType');
        vehicle.Body_Style__c = (String) vehicleDataMap.get('bodyStyle');
        vehicle.Color__c = (String) vehicleDataMap.get('color');

        Object gvwrObj = vehicleDataMap.get('gvwr');
        if (gvwrObj != null && gvwrObj != '') {
            try {
                if (gvwrObj instanceof String && String.isNotBlank((String) gvwrObj)) {
                    vehicle.GVWR__c = Decimal.valueOf((String) gvwrObj);
                } else if (gvwrObj instanceof Decimal) {
                    vehicle.GVWR__c = (Decimal) gvwrObj;
                }
            } catch (Exception e) {
vehicle.GVWR__c = null;
            }
        } else {
            vehicle.GVWR__c = null;
        }
        

        vehicle.Manufacturer_Warranty_Type__c = (String) vehicleDataMap.get('manufacturerWarrantyType');
        vehicle.Warranty_Term__c = (String) vehicleDataMap.get('warrantyTerm');

        vehicle.Deferral_Option__c = (Boolean) vehicleDataMap.get('deferralOption');

        Object deliveryDateObj = vehicleDataMap.get('deliveryDate');
        if (deliveryDateObj != null && String.isNotBlank((String) deliveryDateObj)) {
            try {
                vehicle.Delivery_Date__c = Date.valueOf((String) deliveryDateObj);
            } catch (Exception e) {
vehicle.Delivery_Date__c = null;
            }
        } else {
            vehicle.Delivery_Date__c = null;
        }
        vehicle.Usage_Type__c = (String) vehicleDataMap.get('usageType');
        vehicle.Vehicle_Sub_Type__c = (String) vehicleDataMap.get('vehicleSubType');
        vehicle.Vehicle_Class__c = (String) vehicleDataMap.get('vehicleClass');
        vehicle.Vehicle_Category__c = (String) vehicleDataMap.get('vehicleCategory');


        String vehicleName = '';
        if (String.isNotBlank(vehicle.Year__c)) vehicleName += vehicle.Year__c;
        if (String.isNotBlank(vehicle.Make__c)) vehicleName += (vehicleName != '' ? ' ' : '') + vehicle.Make__c;
        if (String.isNotBlank(vehicle.Model__c)) vehicleName += (vehicleName != '' ? ' ' : '') + vehicle.Model__c;
        if (String.isNotBlank(vehicle.Trim__c)) vehicleName += (vehicleName != '' ? ' ' : '') + vehicle.Trim__c;
        if (String.isNotBlank(vehicle.VIN__c)) vehicleName += (vehicleName != '' ? ' - ' : '') + vehicle.VIN__c;
        
        vehicle.Name = vehicleName;


        if (String.isNotBlank(vehicle.Make__c)) {
            List<Make__c> makeRecords = [SELECT Id, Class__c FROM Make__c WHERE Name = :vehicle.Make__c LIMIT 1];
            if (makeRecords.isEmpty()) {
                throw new CalloutException('We don\'t work with this type of manufacturer. Please contact support for assistance.');
            }
            vehicle.Make_Lookup__c = makeRecords[0].Id;
            

            if (String.isNotBlank(vehicle.Model__c)) {
                List<Model__c> modelRecords = [SELECT Id FROM Model__c WHERE Name = :vehicle.Model__c LIMIT 1];
                if (modelRecords.isEmpty()) {

                    Model__c newModel = new Model__c();
                    newModel.Make__c = makeRecords[0].Id;
                    newModel.Name = vehicle.Model__c;
                    newModel.Class__c = makeRecords[0].Class__c;
                    
                    try {
                        insert newModel;
                        vehicle.Model_Lookup__c = newModel.Id;
                    } catch (Exception e) {
                        throw new CalloutException('Failed to create model record: ' + e.getMessage());
                    }
                } else {
                    vehicle.Model_Lookup__c = modelRecords[0].Id;
                }
            }
        }


        if (String.isBlank(vehicle.VIN__c)) throw new CalloutException('VIN is required');
        if (String.isBlank(vehicle.Year__c)) throw new CalloutException('Year is required');
        if (String.isBlank(vehicle.Make__c)) throw new CalloutException('Make is required');
        if (String.isBlank(vehicle.Model__c)) throw new CalloutException('Model is required');


        if (isUpdate) {
            update vehicle;
        } else {
            insert vehicle;
        }



        
        Application__c appToUpdate = null;
        
        if (String.isBlank(applicationId)) {

            appToUpdate = new Application__c(
                Vehicle__c = vehicle.Id,
                Application_Status__c = 'Active'
            );
            
            try {
                insert appToUpdate;
                applicationId = appToUpdate.Id;

            } catch (Exception e) {
throw new CalloutException('Failed to create Application: ' + e.getMessage());
            }
        } else {

            try {
                appToUpdate = [SELECT Id, Vehicle__c FROM Application__c WHERE Id = :applicationId LIMIT 1];
                if (!isUpdate) {

                    if (appToUpdate.Vehicle__c != vehicle.Id) {
                        appToUpdate.Vehicle__c = vehicle.Id;
                    }
                }
            } catch (Exception e) {

            }
        }
        

        if (appToUpdate != null && String.isNotBlank(applicationId)) {

            appToUpdate.Dealer_Comments_Notes__c = (String) vehicleDataMap.get('dealerCommentsNotes');
            appToUpdate.Show_Comments_On_Print__c = (Boolean) vehicleDataMap.get('showCommentsOnPrint');
            appToUpdate.Dealer_Sales_ID_License__c = (String) vehicleDataMap.get('dealerSalesId');
            appToUpdate.Financial_Institution_Lender__c = (String) vehicleDataMap.get('lienHolder');
            appToUpdate.Vehicle_Sub_Type__c = (String) vehicleDataMap.get('vehicleSubType');
            appToUpdate.Vehicle_Class__c = (String) vehicleDataMap.get('vehicleClass');
            

            Object salesRepIdObj = vehicleDataMap.get('salesRepId');
            if (salesRepIdObj != null && String.isNotBlank((String) salesRepIdObj)) {
                try {
                    appToUpdate.Sales_Rep__c = (String) salesRepIdObj;
                } catch (Exception e) {
}
            }
            
            try {
                update appToUpdate;

            } catch (Exception e) {

            }
        }

        result.put('success', true);
        result.put('recordId', vehicle.Id);
        result.put('applicationId', applicationId);
        

        Map<String, Object> responseData = new Map<String, Object>();
        responseData.put('stockNumber', vehicle.Stock_Number__c);
        responseData.put('vin', vehicle.VIN__c);
        responseData.put('vehicleIdentificationNumberVIN', vehicle.Vehicle_Identification_Number_VIN__c);
        responseData.put('year', vehicle.Year__c);
        responseData.put('make', vehicle.Make__c);
        responseData.put('model', vehicle.Model__c);
        responseData.put('trim', vehicle.Trim__c);
        responseData.put('dateVehicleSold', vehicle.Date_Vehicle_Sold__c != null ? String.valueOf(vehicle.Date_Vehicle_Sold__c) : null);
        responseData.put('vehiclePurchasePrice', vehicle.Vehicle_Purchase_Price__c);
        responseData.put('brandedRebuilt', vehicle.Branded_Rebuilt__c);
        responseData.put('inServiceDate', vehicle.In_Service_Date__c != null ? String.valueOf(vehicle.In_Service_Date__c) : null);
        responseData.put('odometer', vehicle.Odometer__c);
        responseData.put('odometerUnit', vehicle.Odometer_Unit__c);
        responseData.put('businessCommercialUse', vehicle.Business_Commercial_Use__c);
        responseData.put('typeOfCommercialUse', vehicle.Type_of_Commercial_Use__c);
        
        result.put('data', responseData);
        
    } catch (Exception e) {
        result.put('message', 'Error saving vehicle data: ' + e.getMessage());
    }

    return result;
}

// -----------------------------------------------------------------------------
// Markup API compatibility wrappers
// -----------------------------------------------------------------------------
// IMPORTANT:
// - All markup logic lives in DealerPortalMarkupController.
// - These wrappers exist ONLY to keep older/cached Experience Cloud bundles
//   working if they still call DealerPortalController.<markupMethod>.
// - New code should import @salesforce/apex/DealerPortalMarkupController.<method>.
@AuraEnabled(cacheable=true)
public static List<DealerPortalMarkupController.AdminDealerPackageDTO> getAdminDealerPackages() {
    return DealerPortalMarkupController.getAdminDealerPackages();
}

@AuraEnabled
public static List<DealerPortalMarkupController.PackageWithOptionsDTO> getAdminDealerPackageOptions(String timestamp) {
    return DealerPortalMarkupController.getAdminDealerPackageOptions(timestamp);
}

@AuraEnabled
public static String updateTermMarkup(String termId, Decimal markup, String markupType) {
    return DealerPortalMarkupController.updateTermMarkup(termId, markup, markupType);
}

@AuraEnabled
public static String updateAllTermMarkups(Decimal defaultMarkup, String defaultMarkupType) {
    return DealerPortalMarkupController.updateAllTermMarkups(defaultMarkup, defaultMarkupType);
}

@AuraEnabled
public static String updateSpecificTermMarkups(Decimal defaultMarkup, String defaultMarkupType, List<String> termIds) {
    return DealerPortalMarkupController.updateSpecificTermMarkups(defaultMarkup, defaultMarkupType, termIds);
}

@AuraEnabled
public static String updateOptionMarkup(String optionId, Decimal markup, String markupType) {
    return DealerPortalMarkupController.updateOptionMarkup(optionId, markup, markupType);
}

@AuraEnabled
public static String updateAllOptionMarkups(Decimal defaultMarkup, String defaultMarkupType) {
    return DealerPortalMarkupController.updateAllOptionMarkups(defaultMarkup, defaultMarkupType);
}

@AuraEnabled
public static String updateSpecificOptionMarkups(Decimal defaultMarkup, String defaultMarkupType, List<String> optionIds) {
    return DealerPortalMarkupController.updateSpecificOptionMarkups(defaultMarkup, defaultMarkupType, optionIds);
}

/**
 * Get existing additional options for an application package
 * @param applicationPackageId The ID of the application package
 * @return AdditionalOptionsResponse containing existing options
 */
@AuraEnabled
public static AdditionalOptionsResponse getExistingAdditionalOptions(String applicationPackageId) {
    try {

        

        if (String.isBlank(applicationPackageId)) {
            throw new CalloutException('Application Package ID is required');
        }
        

        List<Application_Package_Option__c> existingOptions = [
            SELECT Id, Name, Application__c, Application_Package__c, Package_Option__c,
                    Inclusion__c, Exclusion__c, Discount_Type__c, Discount_Value__c,
                    Original_Package_Option_Price__c, Dealer_Markup__c, Markup_Type__c,
                    Selection_Type__c, Option__c, CreatedDate
            FROM Application_Package_Option__c
            WHERE Application_Package__c = :applicationPackageId
            AND Selection_Type__c = 'Optional'
            ORDER BY CreatedDate ASC
        ];
        

        Set<String> packageOptionIds = new Set<String>();
        for (Application_Package_Option__c option : existingOptions) {
            if (option.Package_Option__c != null) {
                packageOptionIds.add(option.Package_Option__c);
            }
        }
        

        Map<String, String> packageOptionToDealerOptionMap = new Map<String, String>();
        if (!packageOptionIds.isEmpty()) {
            List<Dealer_Package_Option__c> dealerOptions = [
                SELECT Id, Package_Option__c
                FROM Dealer_Package_Option__c
                WHERE Package_Option__c IN :packageOptionIds
            ];
            
            for (Dealer_Package_Option__c dealerOpt : dealerOptions) {
                packageOptionToDealerOptionMap.put(dealerOpt.Package_Option__c, dealerOpt.Id);
            }
        }
        

        List<AdditionalOptionDTO> optionList = new List<AdditionalOptionDTO>();
        for (Application_Package_Option__c option : existingOptions) {
            AdditionalOptionDTO dto = new AdditionalOptionDTO();

            dto.Id = packageOptionToDealerOptionMap.get(option.Package_Option__c);
            dto.Name = option.Name;
            dto.optionName = option.Option__c;
            dto.dealerMarkup = option.Dealer_Markup__c != null ? option.Dealer_Markup__c : 0;
            dto.markupType = option.Markup_Type__c != null ? option.Markup_Type__c : '';
            dto.originalPrice = option.Original_Package_Option_Price__c != null ? option.Original_Package_Option_Price__c : 0;
            dto.discountType = option.Discount_Type__c;
            dto.discountValue = option.Discount_Value__c != null ? option.Discount_Value__c : 0;
            dto.inclusion = option.Inclusion__c;
            dto.exclusion = option.Exclusion__c;

            Decimal netCost = dto.originalPrice;
            if (dto.discountType == '$') {
                netCost = dto.originalPrice - dto.discountValue;
            } else if (dto.discountType == '%') {
                netCost = dto.originalPrice - (dto.originalPrice * dto.discountValue / 100);
            }
            

            Decimal markupAmount = 0;
            if (dto.markupType == '%' && dto.dealerMarkup > 0) {
                markupAmount = netCost * dto.dealerMarkup / 100;
            } else if (dto.markupType == '$' && dto.dealerMarkup > 0) {
                markupAmount = dto.dealerMarkup;
            }
            
            dto.retailPrice = netCost + markupAmount;
            dto.price = dto.retailPrice;
            optionList.add(dto);
        }
        

        
        AdditionalOptionsResponse response = new AdditionalOptionsResponse();
        response.success = true;
        response.message = 'Existing additional options retrieved successfully';
        response.data = optionList;
        return response;
        
    } catch (Exception e) {
AdditionalOptionsResponse response = new AdditionalOptionsResponse();
        response.success = false;
        response.message = 'Error retrieving existing additional options: ' + e.getMessage();
        response.data = new List<AdditionalOptionDTO>();
        return response;
    }
}

/**
 * Update additional options for an application package (bulk add/remove operation)
 * @param optionsData Map containing application package ID, options to add, and options to remove
 * @return AdditionalOptionsResponse containing update result
 */
@AuraEnabled
public static AdditionalOptionsResponse updateAdditionalOptions(Map<String, Object> optionsData) {
    try {

        

        String applicationPackageId = (String) optionsData.get('applicationPackageId');
        String applicationId = (String) optionsData.get('applicationId');
        

        List<String> optionsToAdd = new List<String>();
        List<String> optionsToRemove = new List<String>();
        

        Object optionsToAddObj = optionsData.get('optionsToAdd');
        if (optionsToAddObj != null) {
            if (optionsToAddObj instanceof List<Object>) {
                List<Object> optionsToAddList = (List<Object>) optionsToAddObj;
                for (Object obj : optionsToAddList) {
                    optionsToAdd.add(String.valueOf(obj));
                }
            } else if (optionsToAddObj instanceof List<String>) {
                optionsToAdd = (List<String>) optionsToAddObj;
            }
        }
        

        Object optionsToRemoveObj = optionsData.get('optionsToRemove');
        if (optionsToRemoveObj != null) {
            if (optionsToRemoveObj instanceof List<Object>) {
                List<Object> optionsToRemoveList = (List<Object>) optionsToRemoveObj;
                for (Object obj : optionsToRemoveList) {
                    optionsToRemove.add(String.valueOf(obj));
                }
            } else if (optionsToRemoveObj instanceof List<String>) {
                optionsToRemove = (List<String>) optionsToRemoveObj;
            }
        }
        


        

        if (String.isBlank(applicationPackageId)) {
            throw new CalloutException('Application Package ID is required');
        }
        
        if (String.isBlank(applicationId)) {
            throw new CalloutException('Application ID is required');
        }
        

        List<Application_Package_Option__c> recordsToInsert = new List<Application_Package_Option__c>();
        
        if (optionsToAdd != null && !optionsToAdd.isEmpty()) {

            

            List<Dealer_Package_Option__c> dealerOptions = [
                SELECT Id, Package_Option__c, Option__r.Name, Inclusion__c, Exclusion__c, 
                        Discount_Type__c, Discount_Value__c, Original_Package_Option_Price__c,
                        Dealer_Markup__c, Markup_Type__c
                FROM Dealer_Package_Option__c 
                WHERE Id IN :optionsToAdd
            ];
            

            








            

            for (Dealer_Package_Option__c dealerOption : dealerOptions) {
                if (dealerOption.Package_Option__c == null) {

                    continue;
                }
                
                Application_Package_Option__c appOption = new Application_Package_Option__c();
                appOption.Application__c = applicationId;
                appOption.Application_Package__c = applicationPackageId;
                appOption.Dealer_Package_Option__c = dealerOption.Id; // Populate the new lookup field (Package_Option__c is formula)
                appOption.Package_Option__c = dealerOption.Package_Option__c; // Map Package_Option__c field
                appOption.Inclusion__c = dealerOption.Inclusion__c;
                appOption.Exclusion__c = dealerOption.Exclusion__c;
                appOption.Discount_Type__c = dealerOption.Discount_Type__c;
                appOption.Discount_Value__c = dealerOption.Discount_Value__c;
                appOption.Original_Package_Option_Price__c = dealerOption.Original_Package_Option_Price__c;
                appOption.Dealer_Markup__c = dealerOption.Dealer_Markup__c;
                appOption.Markup_Type__c = dealerOption.Markup_Type__c;

                
                recordsToInsert.add(appOption);

            }
        }
        

        for (Application_Package_Option__c record : recordsToInsert) {

        }
        

        String result = updateApplicationPackageOptionsWithoutSharing(
            applicationPackageId, recordsToInsert, optionsToRemove
        );
        
        if (!result.startsWith('Success')) {
            throw new CalloutException(result);
        }
        

        
        String message = result;
        
        AdditionalOptionsResponse response = new AdditionalOptionsResponse();
        response.success = true;
        response.message = message;
        response.data = new List<AdditionalOptionDTO>();
        return response;
        
    } catch (Exception e) {
AdditionalOptionsResponse response = new AdditionalOptionsResponse();
        response.success = false;
        response.message = 'Error updating additional options: ' + e.getMessage();
        response.data = new List<AdditionalOptionDTO>();
        return response;
    }
}

/**
 * Update only specific vehicle fields (selective update for auto-save)
 * @param updateData Map containing vehicle ID, application ID, and fields to update
 * @return VehicleResponse containing update result
 */
@AuraEnabled
public static VehicleResponse updateVehicleFieldsSelective(Map<String, Object> updateData) {
    try {


        

        String vehicleId = (String) updateData.get('vehicleId');
        String applicationId = (String) updateData.get('applicationId');
        Map<String, Object> fieldsToUpdate = (Map<String, Object>) updateData.get('fields');
        

        if (String.isBlank(vehicleId)) {
            throw new CalloutException('Vehicle ID is required for selective update');
        }
        
        if (fieldsToUpdate == null || fieldsToUpdate.isEmpty()) {
            VehicleResponse response = new VehicleResponse();
            response.success = true;
            response.message = 'No fields to update';
            return response;
        }
        

        

        Vehicle__c vehicle = new Vehicle__c(Id = vehicleId);
        

        for (String fieldName : fieldsToUpdate.keySet()) {
            Object fieldValue = fieldsToUpdate.get(fieldName);

            vehicle.put(fieldName, fieldValue);
        }
        

        update vehicle;
        

        
        VehicleResponse response = new VehicleResponse();
        response.success = true;
        response.message = 'Successfully updated ' + fieldsToUpdate.size() + ' vehicle fields';
        response.recordId = vehicleId;
        return response;
        
    } catch (Exception e) {
VehicleResponse response = new VehicleResponse();
        response.success = false;
        response.message = 'Error updating vehicle fields: ' + e.getMessage();
        return response;
    }
}

/**
 * Update only specific warranty/application package fields (selective update for auto-save)
 * @param updateData Map containing application package ID and fields to update
 * @return ApplicationPackageResponse containing update result
 */
@AuraEnabled
public static ApplicationPackageResponse updateWarrantyFieldsSelective(Map<String, Object> updateData) {
    try {


        

        String applicationPackageId = (String) updateData.get('applicationPackageId');
        String applicationId = (String) updateData.get('applicationId');
        String dealerPackageId = (String) updateData.get('dealerPackageId');
        String dealerPackageTermId = (String) updateData.get('dealerPackageTermId');
        

        if (String.isBlank(applicationPackageId)) {
            throw new CalloutException('Application Package ID is required for selective update');
        }
        

        

        Application_Package__c appPackage = new Application_Package__c(Id = applicationPackageId);
        
        Boolean hasChanges = false;
        

        if (String.isNotBlank(dealerPackageId)) {
            appPackage.Dealer_Package__c = dealerPackageId;
            hasChanges = true;

        }
        
        if (String.isNotBlank(dealerPackageTermId)) {
            appPackage.Dealer_Package_Term__c = dealerPackageTermId;
            hasChanges = true;

        }
        

        if (hasChanges) {
            update appPackage;

        } else {
}
        
        ApplicationPackageResponse response = new ApplicationPackageResponse();
        response.success = true;
        response.message = hasChanges ? 'Warranty fields updated successfully' : 'No changes to update';
        response.recordId = applicationPackageId;
        return response;
        
    } catch (Exception e) {
ApplicationPackageResponse response = new ApplicationPackageResponse();
        response.success = false;
        response.message = 'Error updating warranty fields: ' + e.getMessage();
        return response;
    }
}





/**
 * Standardized error response creation
 * @param methodName The name of the method where error occurred
 * @param error The exception that occurred
 * @param customMessage Optional custom error message
 * @return Map containing standardized error response
 */
private static Map<String, Object> createErrorResponse(String methodName, Exception error, String customMessage) {
    Map<String, Object> errorResponse = new Map<String, Object>();
    errorResponse.put('success', false);
    
    String errorMessage = String.isNotBlank(customMessage) ? customMessage : 'An unexpected error occurred';
    errorResponse.put('message', errorMessage);
    


    Map<String, Object> errorDetails = new Map<String, Object>();
    errorDetails.put('method', methodName);
    errorDetails.put('errorType', error.getTypeName());
    errorDetails.put('errorMessage', error.getMessage());
    errorDetails.put('stackTrace', error.getStackTraceString());
    errorResponse.put('errorDetails', errorDetails);
    
    return errorResponse;
}

/**
 * Standardized success response creation
 * @param message Optional success message
 * @param data Optional data to include in response
 * @return Map containing standardized success response
 */
private static Map<String, Object> createSuccessResponse(String message, Object data) {
    Map<String, Object> successResponse = new Map<String, Object>();
    successResponse.put('success', true);
    successResponse.put('message', String.isNotBlank(message) ? message : 'Operation completed successfully');
    
    if (data != null) {
        successResponse.put('data', data);
    }
    
    return successResponse;
}

/**
 * Validate required parameters
 * @param params Map of parameter names to values
 * @return List of missing parameter names
 */
private static List<String> validateRequiredParams(Map<String, Object> params) {
    List<String> missingParams = new List<String>();
    
    for (String paramName : params.keySet()) {
        Object paramValue = params.get(paramName);
        
        if (paramValue == null) {
            missingParams.add(paramName);
        } else if (paramValue instanceof String && String.isBlank((String)paramValue)) {
            missingParams.add(paramName);
        }
    }
    
    return missingParams;
}

/**
 * Log method entry with parameters
 * @param methodName The name of the method
 * @param params Map of parameter names to values
 */
private static void logMethodEntry(String methodName, Map<String, Object> params) {
if (params != null && !params.isEmpty()) {
        for (String paramName : params.keySet()) {
}
    }
}

/**
 * Log method exit with result summary
 * @param methodName The name of the method
 * @param success Whether the method completed successfully
 * @param resultCount Optional count of results returned
 */
private static void logMethodExit(String methodName, Boolean success, Integer resultCount) {
    String status = success ? '✅' : '❌';
    String message = success ? 'Completed successfully' : 'Failed';
    if (resultCount != null) {
        message += ' (returned ' + resultCount + ' records)';
    }
}





/**
 * Centralized pricing calculation method
 * @param basePrice The base price before markup
 * @param markup The markup amount
 * @param markupType The type of markup ('Percentage' or 'Amount')
 * @param discountType The type of discount ('Percentage' or 'Amount')
 * @param discountValue The discount value
 * @return Map containing calculated pricing values
 */
private static Map<String, Decimal> calculatePricing(Decimal basePrice, Decimal markup, String markupType, String discountType, Decimal discountValue) {
    Map<String, Decimal> pricing = new Map<String, Decimal>();
    
    try {

        basePrice = basePrice != null ? basePrice : 0;
        markup = markup != null ? markup : 0;
        discountValue = discountValue != null ? discountValue : 0;
        

        Decimal discountAmount = 0;
        if (discountType == 'Percentage' && discountValue > 0) {
            discountAmount = (basePrice * discountValue) / 100;
        } else if (discountType == 'Amount' && discountValue > 0) {
            discountAmount = discountValue;
        }
        

        Decimal netCost = basePrice - discountAmount;
        

        Decimal markupAmount = 0;
        if (markupType == 'Percentage' && markup > 0) {
            markupAmount = (netCost * markup) / 100;
        } else if (markupType == 'Amount' && markup > 0) {
            markupAmount = markup;
        }
        

        Decimal retailPrice = netCost + markupAmount;
        

        pricing.put('basePrice', basePrice);
        pricing.put('discountAmount', discountAmount);
        pricing.put('netCost', netCost);
        pricing.put('markupAmount', markupAmount);
        pricing.put('retailPrice', retailPrice);
        






        
    } catch (Exception e) {

        pricing.put('basePrice', basePrice != null ? basePrice : 0);
        pricing.put('discountAmount', 0);
        pricing.put('netCost', basePrice != null ? basePrice : 0);
        pricing.put('markupAmount', 0);
        pricing.put('retailPrice', basePrice != null ? basePrice : 0);
    }
    
    return pricing;
}

/**
 * Centralized method to query dealer packages with consistent field selection
 * @param dealerId The ID of the dealer
 * @param useSharing Whether to use sharing rules (true) or bypass them (false)
 * @return List of Dealer_Package__c records
 */
private static List<Dealer_Package__c> queryDealerPackages(String dealerId, Boolean useSharing, String recordType) {
    try {

        try {
            List<Dealer_Package__c> allDealerPackages = [
                SELECT Id, Name, RecordType.DeveloperName, RecordType.Name, Package__r.Name, Package__r.Class__c, Class__c
                FROM Dealer_Package__c 
                WHERE Dealer__c = :dealerId
                LIMIT 100
            ];
for (Dealer_Package__c pkg : allDealerPackages) {
}
} catch (Exception e) {

        }
        

        List<Dealer_Package__c> samplePackages = [
            SELECT RecordType.DeveloperName
            FROM Dealer_Package__c 
            WHERE Dealer__c = :dealerId
            LIMIT 10
        ];
        Set<String> availableRecordTypes = new Set<String>();
        for (Dealer_Package__c pkg : samplePackages) {
            availableRecordTypes.add(pkg.RecordType.DeveloperName);
        }
if (String.isBlank(dealerId)) {
return new List<Dealer_Package__c>();
        }
        

        String whereClause = 'Dealer__c = :dealerId';
        if (String.isNotBlank(recordType)) {
            whereClause += ' AND Package__r.RecordType.DeveloperName = :recordType';
        }
        
        List<Dealer_Package__c> packages;
        if (String.isNotBlank(recordType)) {
try {

                packages = [
                    SELECT Id, Name, Package__c, Deductable__c, Per_Claim_Limit__c, Package_Description__c, Class__c, Commercial_Eligible__c,
                            Plan_Type__c, Plan_Type__r.Name, Plan_Type__r.Package_Description__c,
                            Dealer__c, Dealer__r.Name, Dealer__r.Tax_Region__c, Dealer__r.Tax_Region__r.Total_Tax_Rate__c,
                            RecordType.DeveloperName, RecordType.Name
                    FROM Dealer_Package__c 
                    WHERE Dealer__c = :dealerId AND RecordType.DeveloperName = :recordType
                    ORDER BY Name
                    LIMIT 50000
                ];
for (Dealer_Package__c pkg : packages) {
}
            } catch (Exception queryEx) {
packages = new List<Dealer_Package__c>();
            }
        } else {

            packages = [
                SELECT Id, Name, Package__c, Deductable__c, Per_Claim_Limit__c, Package_Description__c, Class__c, Commercial_Eligible__c,
                        Plan_Type__c, Plan_Type__r.Name, Plan_Type__r.Package_Description__c,
                        Dealer__c, Dealer__r.Name, Dealer__r.Tax_Region__c, Dealer__r.Tax_Region__r.Total_Tax_Rate__c,
                        RecordType.DeveloperName, RecordType.Name
                FROM Dealer_Package__c 
                WHERE Dealer__c = :dealerId
                ORDER BY Name
                LIMIT 50000
            ];
        }
return packages;
        
    } catch (Exception e) {
return new List<Dealer_Package__c>();
    }
}

/**
 * Check if a dealer package term meets the filtering criteria
 * - Exact month match on the term
 * - Interest rate within tier range (if tier data available)
 * - Loan financed amount within tier range (if tier data available)
 */
private static Boolean isTermEligible(Dealer_Package_Term__c term) {
    try {

        if (term == null) {
return false;
        }
return true;
        
    } catch (Exception e) {
return false;
    }
}

/**
 * Check if a tire & rim term is eligible based on:
 * 1. Vehicle Class vs Package Class validation
 * 2. Max Vehicle Age (ByYear__c) validation
 * @param term The Dealer_Package_Term__c to check
 * @param vehicleYear The vehicle year (String)
 * @param vehicleClass The vehicle's model class (from Model_Lookup__r.Class__c)
 * @param packageClass The package's class (from Package__r.Class__c)
 * @return true if term is eligible, false otherwise
 */
private static Boolean isTermEligibleForTireRim(Dealer_Package_Term__c term, String vehicleYear, String vehicleClass, String packageClass) {
    try {
        if (term == null) {
return false;
        }



        if (String.isNotBlank(packageClass)) {
if (String.isBlank(vehicleClass)) {
return false;
            }
            

            if (!vehicleClass.equalsIgnoreCase(packageClass)) {
return false;
            }
} else {
}
        



        if (term.ByYear__c != null && term.ByYear__c > 0) {
if (String.isBlank(vehicleYear)) {
return false;
            }
            

            Integer vYear;
            try {
                vYear = Integer.valueOf(vehicleYear);
            } catch (Exception e) {
return false;
            }
            

            Integer currentYear = Date.today().year();
            Integer vehicleAge = currentYear - vYear;

            if (vehicleAge > term.ByYear__c) {
return false;
            }
} else {
}
return true;
        
    } catch (Exception e) {
return false;
    }
}

/**
 * Check if a warranty term is eligible based on vehicle mileage and age
 * Validation order: 1) Tier restrictions (if tier exists), 2) Term mileage restrictions, 3) Vehicle age
 * @param term The Dealer_Package_Term__c to check
 * @param vehicleYear The vehicle year (String)
 * @param vehicleOdometer The vehicle odometer reading (Decimal)
 * @param vehicleOdometerUnit The vehicle odometer unit (KM or Miles)
 * @return true if term is eligible, false otherwise
 */
private static Boolean isWarrantyTermEligible(Dealer_Package_Term__c term, String vehicleYear, Decimal vehicleOdometer, String vehicleOdometerUnit) {
    try {
        if (term == null) {
return false;
        }
        


        if (String.isBlank(vehicleYear) || vehicleOdometer == null) {
            // Vehicle data incomplete - treat term as eligible until vehicle is fully populated
            return true;
        }
        

        Decimal vehicleOdometerKM = convertOdometerToKilometers(vehicleOdometer, vehicleOdometerUnit);
        if (vehicleOdometerKM == null) {
return false;
        }



        if (term.Dealer_Package_Tier__c != null) {
            if (term.Dealer_Package_Tier__r != null) {
                Decimal tierMileageStart = term.Dealer_Package_Tier__r.Minimum__c;
                Decimal tierMileageEnd = term.Dealer_Package_Tier__r.Maximum__c;
                String tierMileageUnit = term.Dealer_Package_Tier__r.Mileage_Unit__c;

                if (tierMileageStart != null || tierMileageEnd != null) {

                    Decimal tierMileageStartKM = tierMileageStart;
                    Decimal tierMileageEndKM = tierMileageEnd;
                    
                    if (String.isNotBlank(tierMileageUnit) && tierMileageUnit.equalsIgnoreCase('Miles')) {
                        if (tierMileageStart != null) {
                            tierMileageStartKM = tierMileageStart * 1.60934;
                        }
                        if (tierMileageEnd != null) {
                            tierMileageEndKM = tierMileageEnd * 1.60934;
                        }
}
                    

                    if (tierMileageStart != null && vehicleOdometerKM < tierMileageStartKM) {
return false;
                    }
                    
                    if (tierMileageEnd != null && vehicleOdometerKM > tierMileageEndKM) {
return false;
                    }
} else {
}
            } else {
}
        } else {
}
        




        if (term.Mileage__c != null) {
            Decimal termMileageKM = term.Mileage__c;
            if (String.isNotBlank(term.Mileage_Unit__c) && term.Mileage_Unit__c.equalsIgnoreCase('Miles')) {
                termMileageKM = term.Mileage__c * 1.60934;
            }
            if (vehicleOdometerKM > termMileageKM) {
                return false;
            }
        }
        // null Mileage__c = no mileage restriction
        




        if (term.ByYear__c != null && term.ByYear__c > 0) {
            Integer vehicleAge;
            try {
                Integer vehicleYearInt = Integer.valueOf(vehicleYear);
                vehicleAge = Date.today().year() - vehicleYearInt;
            } catch (Exception e) {
                return false;
            }
            if (vehicleAge < 0) {
                return false;
            }
            if (vehicleAge > term.ByYear__c) {
                return false;
            }
        }
        // null ByYear__c = no year restriction
return true;
        
    } catch (Exception e) {
return false;
    }
}

/**
 * Centralized method to query application packages with consistent field selection
 * @param applicationId The ID of the application
 * @return List of Application_Package__c records
 */
private static List<Application_Package__c> queryApplicationPackages(String applicationId) {
    try {

        
        if (String.isBlank(applicationId)) {

            return new List<Application_Package__c>();
        }
        
        List<Application_Package__c> packages = [
            SELECT Id, Name, Application__c, Dealer__c, Dealer_Package__c, Dealer_Package_Term__c,
                    Dealer_Package_Price__c, /* Dealer_Markup__c, */ Deductible__c,
                    Dealer_Package__r.Name, Dealer_Package__r.Package_Description__c,
                    Dealer_Package__r.Dealer__r.Name, Dealer_Package_Term__r.Name,
                    Dealer_Package_Term__r.Month__c,
                    Dealer_Package_Term__r.Mileage_Restriction__c,
                    Dealer_Package_Term__r.Original_Package_Term_Cost__c,
                    Dealer_Package_Term__r.Mileage_Unit__c,
                    CreatedDate, LastModifiedDate
            FROM Application_Package__c 
            WHERE Application__c = :applicationId
            ORDER BY CreatedDate DESC
        ];
        

        return packages;
        
    } catch (Exception e) {
return new List<Application_Package__c>();
    }
}

/**
 * Centralized method to query applications with consistent field selection
 * @param applicationId The ID of the application (optional, if null returns all)
 * @param includeVehicleDetails Whether to include detailed vehicle information
 * @return List of Application__c records
 */
private static List<Application__c> queryApplications(String applicationId, Boolean includeVehicleDetails) {
    try {


        
        String whereClause = String.isNotBlank(applicationId) ? 'WHERE Id = :applicationId' : '';
        String vehicleFields = includeVehicleDetails ? 
            'Vehicle__c, Vehicle__r.Id, Vehicle__r.Name, Vehicle__r.Stock_Number__c, Vehicle__r.VIN__c, ' +
            'Vehicle__r.Vehicle_Identification_Number_VIN__c, Vehicle__r.Year__c, Vehicle__r.Make__c, Vehicle__r.Model__c, Vehicle__r.Model_Lookup__c, Vehicle__r.Model_Lookup__r.Class__c, Vehicle__r.Trim__c, ' +
            'Vehicle__r.Date_Vehicle_Sold__c, Vehicle__r.Vehicle_Purchase_Price__c, Vehicle__r.Branded_Rebuilt__c, Vehicle__r.In_Service_Date__c, ' +
            'Vehicle__r.Odometer__c, Vehicle__r.Odometer_Unit__c, Vehicle__r.Business_Commercial_Use__c, Vehicle__r.Type_of_Commercial_Use__c, ' +
            'Vehicle__r.Engine__c, Vehicle__r.Transmission__c, Vehicle__r.Fuel_Type__c, Vehicle__r.Drive_Type__c, Vehicle__r.Body_Style__c, ' +
            'Vehicle__r.Color__c, Vehicle__r.GVWR__c, Vehicle__r.Manufacturer_Warranty_Type__c, Vehicle__r.Warranty_Term__c, ' +
            'Vehicle__r.Deferral_Option__c, Vehicle__r.Delivery_Date__c, Vehicle__r.Usage_Type__c, Vehicle__r.Vehicle_Sub_Type__c, Vehicle__r.Vehicle_Class__c, Vehicle__r.Vehicle_Category__c, ' +
            'Dealer_Name__c, Dealer_Name__r.Id, Dealer_Name__r.Name, Dealer_Name__r.BillingStreet, Dealer_Name__r.BillingCity, ' +
            'Dealer_Name__r.BillingState, Dealer_Name__r.BillingPostalCode, Dealer_Comments_Notes__c, Show_Comments_On_Print__c, ' +
            'Sales_Rep__c, Sales_Rep__r.Id, Sales_Rep__r.Name, Dealer_Sales_ID_License__c, Financial_Institution_Lender__c' :
            'Vehicle__r.Id, Vehicle__r.Name, Vehicle__r.Year__c, Vehicle__r.Make__c, Vehicle__r.Model__c, Vehicle__r.Trim__c';
        
        String query = 'SELECT Id, Name, CreatedDate, Application_Status__c, Is_Vehicle_Financed__c, ' + vehicleFields + ' ' +
                        'FROM Application__c ' + whereClause + ' ' +
                        'ORDER BY CreatedDate DESC';
        
        List<Application__c> applications = Database.query(query);
        

        return applications;
        
    } catch (Exception e) {
return new List<Application__c>();
    }
}






/**
 * Create application package without sharing restrictions
 * This method bypasses sharing rules to allow partner users to create application packages
 * @param applicationId The ID of the application
 * @param dealerId The ID of the dealer
 * @param dealerPackageId The ID of the dealer package
 * @param packageName The name of the package
 * @param selectedTermId The ID of the selected dealer package term
 * @param deductible The deductible amount to set
 * @return Application_Package__c record ID if successful, null if failed
 */
public static String createApplicationPackageWithoutSharing(String applicationId, String dealerId, String dealerPackageId, String packageName, String selectedTermId, Decimal deductible, String recordType) {
    try {








        

        if (String.isBlank(applicationId) || String.isBlank(dealerId) || String.isBlank(dealerPackageId)) {
return null;
        }
        

        Decimal perClaimLimit = 0;
        Id dealerPackageTierId = null;
        Id packageTierId = null;
        
        try {
            Dealer_Package__c dealerPackage = [
                SELECT Per_Claim_Limit__c
                FROM Dealer_Package__c
                WHERE Id = :dealerPackageId
                LIMIT 1
            ];
            if (dealerPackage != null && dealerPackage.Per_Claim_Limit__c != null) {
                perClaimLimit = dealerPackage.Per_Claim_Limit__c;
            }
        } catch (Exception e) {

}
        

        if (String.isNotBlank(selectedTermId)) {
            try {
                List<Dealer_Package_Term__c> terms = [
                    SELECT Id, Dealer_Package_Tier__c, Dealer_Package_Tier__r.Package_Tier__c, Package_Tier__c
                    FROM Dealer_Package_Term__c
                    WHERE Id = :selectedTermId
                    LIMIT 1
                ];
                if (!terms.isEmpty()) {
                    Dealer_Package_Term__c term = terms[0];

                    dealerPackageTierId = term.Dealer_Package_Tier__c;

                    packageTierId = term.Dealer_Package_Tier__r != null && term.Dealer_Package_Tier__r.Package_Tier__c != null 
                                    ? term.Dealer_Package_Tier__r.Package_Tier__c 
                                    : term.Package_Tier__c;
                }
            } catch (Exception e) {
}
        }
        

        Application_Package__c appPackage = new Application_Package__c();
        appPackage.Application__c = applicationId;
        appPackage.Dealer__c = dealerId;
        appPackage.Dealer_Package__c = dealerPackageId;
        appPackage.Dealer_Package_Term__c = selectedTermId;
        appPackage.Dealer_Package_Tier__c = dealerPackageTierId;
        appPackage.Package_Tier__c = packageTierId;
        appPackage.Deductible__c = deductible;
        appPackage.Per_Claim_Limit__c = perClaimLimit;
        

        String recordTypeName = String.isNotBlank(recordType) ? recordType : 'Extended_Limited_Warranty';
        try {
            appPackage.RecordTypeId = Schema.SObjectType.Application_Package__c.getRecordTypeInfosByDeveloperName().get(recordTypeName).getRecordTypeId();
} catch (Exception e) {

            try {
                appPackage.RecordTypeId = Schema.SObjectType.Application_Package__c.getRecordTypeInfosByDeveloperName().get('Extended_Limited_Warranty').getRecordTypeId();
} catch (Exception fallbackException) {
}
        }
        

        // Populate tax from dealer's region
        TaxRegionHelper.applyDealerTax(appPackage, dealerId);
        
        insert appPackage;
        

        return appPackage.Id;
        
    } catch (Exception e) {
return null;
    }
}

/**
 * Update application package with pricing information without sharing restrictions
 * This method bypasses sharing rules to allow partner users to update application packages
 * @param packageId The ID of the application package to update
 * @param selectedTermId The ID of the selected dealer package term
 * @param totalPrice The total price including markup and deductible
 * @param markup The markup amount
 * @param deductible The deductible amount
 * @return Application_Package__c record ID if successful, null if failed
 */
public static String updateApplicationPackageWithoutSharing(String packageId, String selectedTermId, Decimal totalPrice, Decimal markup, Decimal deductible) {
    try {






        

        if (String.isBlank(packageId) || String.isBlank(selectedTermId)) {
return null;
        }
        

        List<Application_Package__c> existingPackages = [
            SELECT Id, Application__c, Dealer__c, Dealer_Package__c, Dealer_Package_Term__c,
                    Dealer_Package_Price__c, /* Dealer_Markup__c, */ Deductible__c
            FROM Application_Package__c 
            WHERE Id = :packageId 
            LIMIT 1
        ];
        
        if (existingPackages.isEmpty()) {
return null;
        }
        
        Application_Package__c appPackage = existingPackages[0];
        

        Boolean hasChanges = false;
        
        if (appPackage.Dealer_Package_Term__c != selectedTermId) {
            appPackage.Dealer_Package_Term__c = selectedTermId;

            try {
                List<Dealer_Package_Term__c> terms = [
                    SELECT Id, Dealer_Package_Tier__c, Dealer_Package_Tier__r.Package_Tier__c, Package_Tier__c
                    FROM Dealer_Package_Term__c
                    WHERE Id = :selectedTermId
                    LIMIT 1
                ];
                if (!terms.isEmpty()) {
                    Dealer_Package_Term__c term = terms[0];

                    if (term.Dealer_Package_Tier__c != null) {
                        appPackage.Dealer_Package_Tier__c = term.Dealer_Package_Tier__c;
                    }

                    Id tierId = term.Dealer_Package_Tier__r != null && term.Dealer_Package_Tier__r.Package_Tier__c != null 
                                ? term.Dealer_Package_Tier__r.Package_Tier__c 
                                : term.Package_Tier__c;
                    if (tierId != null) {
                        appPackage.Package_Tier__c = tierId;
                    }
                }
            } catch (Exception e) {
}
            hasChanges = true;
        }
        
        if (appPackage.Dealer_Package_Price__c != totalPrice) {
            appPackage.Dealer_Package_Price__c = totalPrice;
            hasChanges = true;
        }
        




        
        if (appPackage.Deductible__c != deductible) {
            appPackage.Deductible__c = deductible;
            hasChanges = true;
        }
        
        if (!hasChanges) {

            return packageId;
        }
        

        update appPackage;
        

        return appPackage.Id;
        
    } catch (Exception e) {
return null;
    }
}

/**
 * Update Application Package Options without sharing restrictions
 * This method bypasses sharing rules to allow partner users to manage additional options
 * @param applicationPackageId The ID of the application package
 * @param recordsToInsert List of Application_Package_Option__c records to insert
 * @param optionsToRemove List of Dealer_Package_Option__c IDs to remove
 * @return String result message
 */
public static String updateApplicationPackageOptionsWithoutSharing(String applicationPackageId, List<Application_Package_Option__c> recordsToInsert, List<String> optionsToRemove) {
    try {



        
        List<Application_Package_Option__c> recordsToDelete = new List<Application_Package_Option__c>();
        

        if (optionsToRemove != null && !optionsToRemove.isEmpty()) {
            recordsToDelete = [
                SELECT Id 
                FROM Application_Package_Option__c 
                WHERE Application_Package__c = :applicationPackageId 
                AND Dealer_Package_Option__c IN :optionsToRemove
            ];

        }
        

        if (!recordsToInsert.isEmpty()) {

            insert recordsToInsert;

        }
        
        if (!recordsToDelete.isEmpty()) {
            delete recordsToDelete;

        }
        
        return 'Success: Processed ' + recordsToInsert.size() + ' additions and ' + recordsToDelete.size() + ' removals';
        
    } catch (Exception e) {

        if (e instanceof DmlException) {
            DmlException dmlEx = (DmlException) e;
for (Integer i = 0; i < dmlEx.getNumDml(); i++) {
}
        }
        
        return 'Error: ' + e.getMessage() + ' (Type: ' + e.getTypeName() + ')';
    }
}

/**
 * Update application status
 * @param applicationId The ID of the application to update
 * @param status The new status to set
 * @return Response indicating success or failure
 */
@AuraEnabled
public static Map<String, Object> updateApplicationStatus(String applicationId, String status) {
    try {
        if (String.isBlank(applicationId)) {
            return new Map<String, Object>{
                'success' => false,
                'message' => 'Application ID is required'
            };
        }
        
        if (String.isBlank(status)) {
            return new Map<String, Object>{
                'success' => false,
                'message' => 'Status is required'
            };
        }
        

        List<Application__c> applications = [
            SELECT Id, Application_Status__c, Application_Submission_Date__c, Application_Source_Submitted_By__c, Application_Lock_Date__c
            FROM Application__c 
            WHERE Id = :applicationId 
            LIMIT 1
        ];
        
        if (applications.isEmpty()) {
            return new Map<String, Object>{
                'success' => false,
                'message' => 'Application not found'
            };
        }
        

        Application__c app = applications[0];
        app.Application_Status__c = status;
        

        if (status == 'Submitted') {
            app.Application_Submission_Date__c = DateTime.now();
            app.Application_Source_Submitted_By__c = 'Dealership User';
            
            // Get custom metadata configuration and calculate lock date
            try {
                // Fetch custom metadata type "A-Protect Configs" without SOQL
                Dealer_Portal_Configs__mdt config = Dealer_Portal_Configs__mdt.getInstance('A_Protect_Configs');
                system.debug('Fetched A-Protect_Configs metadata: ' + config);
                if (config != null) {
                    Date lockDate = Date.today();
                    
                    // Calculate lock date based on duration type and duration value
                    if (config.Application_Lock_Duration_type__c == 'Days') {
                        lockDate = lockDate.addDays(config.Application_Lock_Duration__c.intValue());
                    } else if (config.Application_Lock_Duration_type__c == 'Months') {
                        lockDate = lockDate.addMonths(config.Application_Lock_Duration__c.intValue());
                    }
                    
                    app.Application_Lock_Date__c = lockDate;
                    System.debug('Application_Lock_Date__c calculated: ' + lockDate + ' (Duration: ' + config.Application_Lock_Duration__c + ' ' + config.Application_Lock_Duration_type__c + ')');
                } else {
                    System.debug('A-Protect_Configs metadata not found');
                }
            } catch (Exception metadataError) {
                System.debug('Error processing custom metadata for Application_Lock_Date__c: ' + metadataError.getMessage());
            }
}
        
        update app;
return new Map<String, Object>{
            'success' => true,
            'message' => 'Application status updated successfully',
            'status' => status
        };
        
    } catch (Exception e) {
return new Map<String, Object>{
            'success' => false,
            'message' => 'Error updating application status: ' + e.getMessage()
        };
    }
}





/**
 * Get dealer packages for Total Loss Protection (GAP)
 * @param applicationId The application ID
 * @param recordType The record type for Total Loss Protection
 * @return Map containing success status and dealer packages data
 */
@AuraEnabled
public static Map<String, Object> getTotalLossDealerPackages(String applicationId, String recordType, Integer financeLoanTerm, Decimal interestRate, Decimal loanAmount) {
    try {
if (String.isBlank(applicationId)) {
            return new Map<String, Object>{
                'success' => false,
                'message' => 'Application ID is required'
            };
        }
        

        Application__c application = [
            SELECT Id, Dealer_Name__c, Dealer_Name__r.Id, Dealer_Name__r.Name
            FROM Application__c 
            WHERE Id = :applicationId 
            LIMIT 1
        ];
        
        if (application == null) {
            return new Map<String, Object>{
                'success' => false,
                'message' => 'Application not found'
            };
        }


        if (financeLoanTerm == null || interestRate == null || loanAmount == null) {
            List<Application_Package__c> existingGapPkgs = [
                SELECT Id, Month__c, Interest_Rate__c, Loan_Amount__c
                FROM Application_Package__c
                WHERE Application__c = :applicationId
                AND RecordType.DeveloperName = 'GAP_Coverage'
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!existingGapPkgs.isEmpty()) {
                Application_Package__c ep = existingGapPkgs[0];
                if (financeLoanTerm == null && ep.Month__c != null) {
                    try { financeLoanTerm = Integer.valueOf(ep.Month__c); } catch (Exception ignore) {}
                }
                if (interestRate == null && ep.Interest_Rate__c != null) {
                    interestRate = ep.Interest_Rate__c;
                }
                if (loanAmount == null && ep.Loan_Amount__c != null) {
                    loanAmount = ep.Loan_Amount__c;
                }
            }
        }
        
        String dealerId = application.Dealer_Name__r.Id;

        Integer gapPackageCount = [SELECT COUNT() FROM Dealer_Package__c WHERE Dealer__c = :dealerId AND RecordType.DeveloperName = :recordType];
        Boolean dealerHasAnyGapPackages = gapPackageCount > 0;

        List<Dealer_Package__c> samplePackages = [
            SELECT RecordType.DeveloperName
            FROM Dealer_Package__c 
            WHERE Dealer__c = :dealerId
            LIMIT 10
        ];
        Set<String> availableRecordTypes = new Set<String>();
        for (Dealer_Package__c pkg : samplePackages) {
            availableRecordTypes.add(pkg.RecordType.DeveloperName);
        }

        List<Dealer_Package__c> dealerPackages;
        Map<Id, List<Dealer_Package_Term__c>> termsByPackageId = new Map<Id, List<Dealer_Package_Term__c>>();
        Map<Id, List<Dealer_Package_Option__c>> optionsByPackageId = new Map<Id, List<Dealer_Package_Option__c>>();
        
        if (financeLoanTerm != null) {




            Decimal expiryTermFilterMonths = Decimal.valueOf(financeLoanTerm);
            Decimal expiryTermFilterYears = expiryTermFilterMonths / 12; // Convert months to years for comparison
            

            dealerPackages = [
                SELECT Id, Name, Package__c, Package__r.Name, Package__r.Description__c, Package__r.Deductible__c,
                        Package_Description__c,
                        Dealer__c, Dealer__r.Name, Dealer__r.Tax_Region__c, Dealer__r.Tax_Region__r.Total_Tax_Rate__c,
                        RecordType.Name, RecordType.DeveloperName
                FROM Dealer_Package__c 
                WHERE Dealer__c = :dealerId
                AND RecordType.DeveloperName = :recordType
                ORDER BY Package__r.Name
            ];
if (dealerPackages.isEmpty()) {

                List<Dealer_Package__c> allPackagesForDealer = [
                    SELECT Id, Name, RecordType.Name, RecordType.DeveloperName
                    FROM Dealer_Package__c 
                    WHERE Dealer__c = :dealerId
                    LIMIT 20
                ];
for (Dealer_Package__c pkg : allPackagesForDealer) {
}
            }
            


            List<Dealer_Package_Term__c> matchingTerms = [
                SELECT Id, Name, Package_Term__c, Package_Term__r.Name, 
                        Markup__c, Markup_Type__c,
                        Net_Cost__c, Retail_Price__c,
                        Original_Package_Term_Cost__c, Included_Options_Price__c,
                        Additional_Options_Price__c, Discount_Type__c, Discount_Value__c,
                        Expiry_Term__c, Duration_Type__c, Mileage_Restriction__c, Mileage_Unit__c,
                        Dealer_Package_Tier__c, Dealer_Package__c,
                        Dealer_Package_Tier__r.Interest_Rate_Min__c, Dealer_Package_Tier__r.Interest_Rate_Max__c,
                        Dealer_Package_Tier__r.Minimum_Financed_Amount__c, Dealer_Package_Tier__r.Maximum_Financed_Amount__c
                FROM Dealer_Package_Term__c
                WHERE Dealer_Package__r.Dealer__c = :dealerId
                AND Dealer_Package__r.RecordType.DeveloperName = :recordType
                AND (

                    (Expiry_Term__c = :expiryTermFilterMonths AND Duration_Type__c = 'Months')
                    OR

                    (Expiry_Term__c = :expiryTermFilterYears AND Duration_Type__c = 'Years')
                )
                ORDER BY Expiry_Term__c
                LIMIT 2000
            ];

            for (Dealer_Package_Term__c term : matchingTerms) {

                Boolean termMatchesInterestRate = true;
                if (interestRate != null && term.Dealer_Package_Tier__c != null) {
                    Decimal minRate = term.Dealer_Package_Tier__r.Interest_Rate_Min__c;
                    Decimal maxRate = term.Dealer_Package_Tier__r.Interest_Rate_Max__c;
if (minRate != null && interestRate < minRate) {
termMatchesInterestRate = false;
                    }
                    if (maxRate != null && interestRate > maxRate) {
termMatchesInterestRate = false;
                    }
                }
                

                Boolean termMatchesLoanAmount = true;
                if (loanAmount != null && term.Dealer_Package_Tier__c != null) {
                    Decimal minAmount = term.Dealer_Package_Tier__r.Minimum_Financed_Amount__c;
                    Decimal maxAmount = term.Dealer_Package_Tier__r.Maximum_Financed_Amount__c;
if (minAmount != null && loanAmount < minAmount) {
termMatchesLoanAmount = false;
                    }
                    if (maxAmount != null && loanAmount > maxAmount) {
termMatchesLoanAmount = false;
                    }
                }
                

                Boolean termMatchesExpiryTerm = false;
                if (term.Expiry_Term__c != null && String.isNotBlank(term.Duration_Type__c)) {
                    if (term.Duration_Type__c == 'Months' && term.Expiry_Term__c == expiryTermFilterMonths) {
                        termMatchesExpiryTerm = true;
                    } else if (term.Duration_Type__c == 'Years' && term.Expiry_Term__c == expiryTermFilterYears) {
                        termMatchesExpiryTerm = true;
                    }
                }
                

                if (termMatchesExpiryTerm && termMatchesInterestRate && termMatchesLoanAmount) {
                    if (!termsByPackageId.containsKey(term.Dealer_Package__c)) {
                        termsByPackageId.put(term.Dealer_Package__c, new List<Dealer_Package_Term__c>());
                    }
                    termsByPackageId.get(term.Dealer_Package__c).add(term);
} else {
}
            }
            

            List<Dealer_Package_Option__c> packageOptions = [
                SELECT Id, Name, Option__c, Option__r.Name, 
                        Inclusion__c, Exclusion__c, Selection_Type__c, Dealer_Package__c
                FROM Dealer_Package_Option__c
                WHERE Selection_Type__c = 'Optional'
                AND Dealer_Package__c IN :termsByPackageId.keySet()
                ORDER BY Option__r.Name
                LIMIT 1000
            ];
            

            for (Dealer_Package_Option__c option : packageOptions) {
                if (!optionsByPackageId.containsKey(option.Dealer_Package__c)) {
                    optionsByPackageId.put(option.Dealer_Package__c, new List<Dealer_Package_Option__c>());
                }
                optionsByPackageId.get(option.Dealer_Package__c).add(option);
            }
            

            List<Dealer_Package__c> filteredPackages = new List<Dealer_Package__c>();
            for (Dealer_Package__c pkg : dealerPackages) {
                if (termsByPackageId.containsKey(pkg.Id)) {
                    filteredPackages.add(pkg);
                }
            }
            dealerPackages = filteredPackages;
        } else {

            dealerPackages = [
                SELECT Id, Name, Package__c, Package__r.Name, Package__r.Description__c, Package__r.Deductible__c,
                        Package_Description__c,
                        Dealer__c, Dealer__r.Name, Dealer__r.Tax_Region__c, Dealer__r.Tax_Region__r.Total_Tax_Rate__c,
                        RecordType.Name
                FROM Dealer_Package__c 
                WHERE Dealer__c = :dealerId
                AND RecordType.DeveloperName = :recordType
                ORDER BY Package__r.Name
            ];
            

            List<Dealer_Package_Term__c> allTerms = [
                SELECT Id, Name, Package_Term__c, Package_Term__r.Name, 
                        Markup__c, Markup_Type__c,
                        Net_Cost__c, Retail_Price__c,
                        Original_Package_Term_Cost__c, Included_Options_Price__c,
                        Additional_Options_Price__c, Discount_Type__c, Discount_Value__c,
                        Expiry_Term__c, Mileage_Restriction__c, Mileage_Unit__c,
                        Dealer_Package_Tier__c, Dealer_Package__c,
                        Dealer_Package_Tier__r.Interest_Rate_Min__c, Dealer_Package_Tier__r.Interest_Rate_Max__c,
                        Dealer_Package_Tier__r.Minimum_Financed_Amount__c, Dealer_Package_Tier__r.Maximum_Financed_Amount__c
                FROM Dealer_Package_Term__c
                WHERE Dealer_Package__c IN :dealerPackages
                ORDER BY Expiry_Term__c
                LIMIT 2000
            ];

            for (Dealer_Package_Term__c term : allTerms) {
                if (!termsByPackageId.containsKey(term.Dealer_Package__c)) {
                    termsByPackageId.put(term.Dealer_Package__c, new List<Dealer_Package_Term__c>());
                }
                termsByPackageId.get(term.Dealer_Package__c).add(term);
            }
            

            List<Dealer_Package_Option__c> packageOptions = [
                SELECT Id, Name, Option__c, Option__r.Name, 
                        Inclusion__c, Exclusion__c, Selection_Type__c, Dealer_Package__c
                FROM Dealer_Package_Option__c
                WHERE Selection_Type__c = 'Optional'
                AND Dealer_Package__c IN :dealerPackages
                ORDER BY Option__r.Name
                LIMIT 1000
            ];
            

            for (Dealer_Package_Option__c option : packageOptions) {
                if (!optionsByPackageId.containsKey(option.Dealer_Package__c)) {
                    optionsByPackageId.put(option.Dealer_Package__c, new List<Dealer_Package_Option__c>());
                }
                optionsByPackageId.get(option.Dealer_Package__c).add(option);
            }
        }

        if (dealerPackages.isEmpty()) {

            if (financeLoanTerm != null) {




                Decimal expiryTermFilterMonths = Decimal.valueOf(financeLoanTerm);
                Decimal expiryTermFilterYears = expiryTermFilterMonths / 12; // Convert months to years for comparison
                


                dealerPackages = [
                    SELECT Id, Name, Package__c, Package__r.Name, Package__r.Description__c, Package__r.Deductible__c,
                            Package_Description__c,
                            Dealer__c, Dealer__r.Name, Dealer__r.Tax_Region__c, Dealer__r.Tax_Region__r.Total_Tax_Rate__c,
                            RecordType.Name, RecordType.DeveloperName
                    FROM Dealer_Package__c 
                    WHERE Dealer__c = :dealerId
                    AND RecordType.DeveloperName = :recordType
                    ORDER BY Package__r.Name
                ];
                


                List<Dealer_Package_Term__c> matchingTerms = [
                    SELECT Id, Name, Package_Term__c, Package_Term__r.Name, 
                            Markup__c, Markup_Type__c,
                            Net_Cost__c, Retail_Price__c,
                            Original_Package_Term_Cost__c, Included_Options_Price__c,
                            Additional_Options_Price__c, Discount_Type__c, Discount_Value__c,
                            Expiry_Term__c, Duration_Type__c, Mileage_Restriction__c, Mileage_Unit__c,
                            Dealer_Package_Tier__c, Dealer_Package__c,
                            Dealer_Package_Tier__r.Interest_Rate_Min__c, Dealer_Package_Tier__r.Interest_Rate_Max__c,
                            Dealer_Package_Tier__r.Minimum_Financed_Amount__c, Dealer_Package_Tier__r.Maximum_Financed_Amount__c
                    FROM Dealer_Package_Term__c
                    WHERE Dealer_Package__r.Dealer__c = :dealerId
                    AND Dealer_Package__r.RecordType.DeveloperName = :recordType
                    AND (

                        (Expiry_Term__c = :expiryTermFilterMonths AND Duration_Type__c = 'Months')
                        OR

                        (Expiry_Term__c = :expiryTermFilterYears AND Duration_Type__c = 'Years')
                    )
                    ORDER BY Expiry_Term__c
                    LIMIT 2000
                ];

                for (Dealer_Package_Term__c term : matchingTerms) {

                    Boolean termMatchesInterestRate = true;
                    if (interestRate != null && term.Dealer_Package_Tier__c != null) {
                        Decimal minRate = term.Dealer_Package_Tier__r.Interest_Rate_Min__c;
                        Decimal maxRate = term.Dealer_Package_Tier__r.Interest_Rate_Max__c;
if (minRate != null && interestRate < minRate) {
termMatchesInterestRate = false;
                        }
                        if (maxRate != null && interestRate > maxRate) {
termMatchesInterestRate = false;
                        }
                    }
                    

                    Boolean termMatchesLoanAmount = true;
                    if (loanAmount != null && term.Dealer_Package_Tier__c != null) {
                        Decimal minAmount = term.Dealer_Package_Tier__r.Minimum_Financed_Amount__c;
                        Decimal maxAmount = term.Dealer_Package_Tier__r.Maximum_Financed_Amount__c;
if (minAmount != null && loanAmount < minAmount) {
termMatchesLoanAmount = false;
                        }
                        if (maxAmount != null && loanAmount > maxAmount) {
termMatchesLoanAmount = false;
                        }
                    }
                    

                    Boolean termMatchesExpiryTerm = false;
                    if (term.Expiry_Term__c != null && String.isNotBlank(term.Duration_Type__c)) {
                        if (term.Duration_Type__c == 'Months' && term.Expiry_Term__c == expiryTermFilterMonths) {
                            termMatchesExpiryTerm = true;
                        } else if (term.Duration_Type__c == 'Years' && term.Expiry_Term__c == expiryTermFilterYears) {
                            termMatchesExpiryTerm = true;
                        }
                    }
                    

                    if (termMatchesExpiryTerm && termMatchesInterestRate && termMatchesLoanAmount) {
                        if (!termsByPackageId.containsKey(term.Dealer_Package__c)) {
                            termsByPackageId.put(term.Dealer_Package__c, new List<Dealer_Package_Term__c>());
                        }
                        termsByPackageId.get(term.Dealer_Package__c).add(term);
} else {
}
                }
                

                List<Dealer_Package_Option__c> packageOptions = [
                    SELECT Id, Name, Option__c, Option__r.Name, 
                            Inclusion__c, Exclusion__c, Selection_Type__c, Dealer_Package__c
                    FROM Dealer_Package_Option__c
                    WHERE Selection_Type__c = 'Optional'
                    AND Dealer_Package__c IN :termsByPackageId.keySet()
                    ORDER BY Option__r.Name
                    LIMIT 1000
                ];
                

                for (Dealer_Package_Option__c option : packageOptions) {
                    if (!optionsByPackageId.containsKey(option.Dealer_Package__c)) {
                        optionsByPackageId.put(option.Dealer_Package__c, new List<Dealer_Package_Option__c>());
                    }
                    optionsByPackageId.get(option.Dealer_Package__c).add(option);
                }
                

                List<Dealer_Package__c> filteredPackages = new List<Dealer_Package__c>();
                for (Dealer_Package__c pkg : dealerPackages) {
                    if (termsByPackageId.containsKey(pkg.Id)) {
                        filteredPackages.add(pkg);
                    }
                }
                dealerPackages = filteredPackages;
            } else {

                dealerPackages = [
                    SELECT Id, Name, Package__c, Package__r.Name, Package__r.Description__c, Package__r.Deductible__c,
                            Package_Description__c, Dealer__c, Dealer__r.Name, Dealer__r.Tax_Region__c, Dealer__r.Tax_Region__r.Total_Tax_Rate__c,
                            RecordType.Name, RecordType.DeveloperName,
                            (SELECT Id, Name, Package_Term__c, Package_Term__r.Name, 
                                    Markup__c, Markup_Type__c,
                                    Net_Cost__c, Retail_Price__c,
                                    Original_Package_Term_Cost__c, Included_Options_Price__c,
                                    Additional_Options_Price__c, Discount_Type__c, Discount_Value__c,
                                    Expiry_Term__c, Duration_Type__c, Mileage_Restriction__c, Mileage_Unit__c,
                                    Dealer_Package_Tier__c,
                                    Dealer_Package_Tier__r.Interest_Rate_Min__c, Dealer_Package_Tier__r.Interest_Rate_Max__c,
                                    Dealer_Package_Tier__r.Minimum_Financed_Amount__c, Dealer_Package_Tier__r.Maximum_Financed_Amount__c
                            FROM Dealer_Package_Terms__r
                            ORDER BY Expiry_Term__c
                            LIMIT 200),
                            (SELECT Id, Name, Option__c, Option__r.Name, 
                                    Inclusion__c, Exclusion__c, Selection_Type__c
                            FROM Dealer_Included_Options__r
                            WHERE Selection_Type__c = 'Optional'
                            ORDER BY Option__r.Name
                            LIMIT 50)
                    FROM Dealer_Package__c 
                    WHERE Dealer__c = :dealerId
                    AND RecordType.DeveloperName = :recordType
                    ORDER BY Package__r.Name
                ];
            }
            
            if (dealerPackages.isEmpty()) {
                return new Map<String, Object>{
                    'success' => false,
                    'message' => 'No packages available for this dealer with record type: ' + recordType,
                    'hasGapPackages' => dealerHasAnyGapPackages
                };
            } else {
}
        }
        

        List<DealerPackageDTO> packageDTOs = new List<DealerPackageDTO>();
for (Integer i = 0; i < dealerPackages.size(); i++) {
            Dealer_Package__c pkg = dealerPackages[i];
DealerPackageDTO dto = new DealerPackageDTO();
            dto.Id = pkg.Id;
            dto.Name = pkg.Name;
            dto.PackageName = pkg.Name;

            dto.PackageDescription = String.isNotBlank(pkg.Package_Description__c) ? pkg.Package_Description__c : 'Comprehensive warranty coverage for your vehicle.';

            dto.DealerId = pkg.Dealer__c;
            dto.DealerName = pkg.Dealer__r.Name;

            dto.taxRegionId = pkg.Dealer__r != null ? pkg.Dealer__r.Tax_Region__c : null;
            dto.taxRate = (pkg.Dealer__r != null && pkg.Dealer__r.Tax_Region__r != null) ? pkg.Dealer__r.Tax_Region__r.Total_Tax_Rate__c : null;
            

            List<DealerPackageTermDTO> termList = new List<DealerPackageTermDTO>();
            List<Dealer_Package_Term__c> packageTerms = termsByPackageId.get(pkg.Id);
            if (packageTerms != null) {
for (Dealer_Package_Term__c term : packageTerms) {
DealerPackageTermDTO termDto = new DealerPackageTermDTO();
                    termDto.Id = term.Id;
                    termDto.packageTermName = term.Name;
                    termDto.durationRestrictionInMonths = term.Expiry_Term__c;
                    termDto.mileageRestriction = term.Mileage_Restriction__c;
                    termDto.mileageUnit = term.Mileage_Unit__c;
                    termDto.netCost = term.Net_Cost__c != null ? term.Net_Cost__c : 0;
                    termDto.markup = term.Markup__c != null ? term.Markup__c : 0;
                    termDto.markupType = term.Markup_Type__c != null ? term.Markup_Type__c : '';
                    

                    Decimal additionalOptionsPrice = term.Additional_Options_Price__c != null ? term.Additional_Options_Price__c : 0;
                    termDto.additionalOptionsPrice = additionalOptionsPrice;
                    

                    Decimal priceWithMarkup = termDto.netCost;
                    if (termDto.markupType == '%' && termDto.markup > 0) {
                        priceWithMarkup = termDto.netCost + (termDto.netCost * termDto.markup / 100);
                    } else if (termDto.markupType == '$' && termDto.markup > 0) {
                        priceWithMarkup = termDto.netCost + termDto.markup;
                    }
                    


                    Decimal totalTaxableAmount = priceWithMarkup + additionalOptionsPrice;
                    

                    Decimal taxRate = pkg.Dealer__r != null && pkg.Dealer__r.Tax_Region__r != null ? pkg.Dealer__r.Tax_Region__r.Total_Tax_Rate__c : null;
                    Decimal taxAmount = 0;
                    if (taxRate != null && taxRate > 0) {
                        taxAmount = totalTaxableAmount * (taxRate / 100);
                    }
                    

                    termDto.taxRate = taxRate != null ? taxRate : 0;
                    termDto.taxAmount = taxAmount;
                    

                    termDto.totalPrice = priceWithMarkup;
                    
                    termList.add(termDto);
}
            }
            dto.terms = termList;


            List<DealerPackageOptionDTO> optionList = new List<DealerPackageOptionDTO>();
            List<Dealer_Package_Option__c> packageOptions = optionsByPackageId.get(pkg.Id);
            if (packageOptions != null) {
                for (Dealer_Package_Option__c option : packageOptions) {
                    DealerPackageOptionDTO optionDto = new DealerPackageOptionDTO();
                    optionDto.Id = option.Id;
                    optionDto.Name = option.Name;
                    optionDto.optionName = option.Option__r.Name;
                    optionDto.inclusion = option.Inclusion__c;
                    optionDto.exclusion = option.Exclusion__c;
                    optionList.add(optionDto);
                }
            }
            dto.options = optionList;
            

if (!termList.isEmpty()) {
                packageDTOs.add(dto);
} else {
}
        }
for (DealerPackageDTO pkg : packageDTOs) {
}

for (Dealer_Package__c pkg : dealerPackages) {
if (pkg.Dealer_Package_Terms__r != null) {
for (Dealer_Package_Term__c term : pkg.Dealer_Package_Terms__r) {
if (term.Dealer_Package_Tier__c != null) {
} else {
}
                }
            } else {
}
        }
        

        Integer totalTermCount = 0;
        for (DealerPackageDTO pkg : packageDTOs) {
            if (pkg.terms != null) {
                totalTermCount += pkg.terms.size();
            }
        }
        
        return new Map<String, Object>{
            'success' => true,
            'data' => packageDTOs,
            'termCount' => totalTermCount
        };
        
    } catch (Exception e) {
return new Map<String, Object>{
            'success' => false,
            'message' => 'Error loading Total Loss Protection packages: ' + e.getMessage()
        };
    }
}

/**
 * Get existing Total Loss Protection application package by record type
 * @param applicationId The application ID
 * @param recordType The record type for Total Loss Protection
 * @return Map containing success status and existing package data
 */
@AuraEnabled
public static Map<String, Object> getTotalLossExistingApplicationPackageByRecordType(String applicationId, String recordType) {
    try {
if (String.isBlank(applicationId)) {
            return new Map<String, Object>{
                'success' => false,
                'message' => 'Application ID is required'
            };
        }
        

        List<Application_Package__c> existingPackages = [
            SELECT Id, Application__c, Dealer_Package__c, Dealer_Package__r.Name, 
                    Dealer_Package_Term__c, Dealer_Package_Term__r.Name,
                    Dealer_Package_Price__c, Dealer_Markup__c,
                    Lender_Lienholder__c, Month__c, Interest_Rate__c, Loan_Amount__c, Payment_Frequency__c,
                    RecordType.DeveloperName, RecordType.Name, CreatedDate, LastModifiedDate
            FROM Application_Package__c
            WHERE Application__c = :applicationId
            AND RecordType.DeveloperName = :recordType
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        
        if (existingPackages.isEmpty()) {
            return new Map<String, Object>{
                'success' => true,
                'data' => null,
                'message' => 'No existing Total Loss Protection package found'
            };
        }
        
        Application_Package__c existingPackage = existingPackages[0];
        

        Map<String, Object> packageData = new Map<String, Object>{
            'Id' => existingPackage.Id,
            'applicationId' => existingPackage.Application__c,
            'dealerPackageId' => existingPackage.Dealer_Package__c,
            'dealerPackageName' => existingPackage.Dealer_Package__r.Name,
            'selectedTermId' => existingPackage.Dealer_Package_Term__c,
            'selectedTermName' => existingPackage.Dealer_Package_Term__r.Name,
            'dealerPackagePrice' => existingPackage.Dealer_Package_Price__c,
            'dealerMarkup' => existingPackage.Dealer_Markup__c,
            'totalPrice' => existingPackage.Dealer_Package_Price__c,
            'recordType' => existingPackage.RecordType.Name,
            'createdDate' => existingPackage.CreatedDate,
            'lastModifiedDate' => existingPackage.LastModifiedDate,

            'lenderLienholder' => existingPackage.Lender_Lienholder__c,
            'financeLoanTerm' => existingPackage.Month__c,
            'interestRate' => existingPackage.Interest_Rate__c,
            'loanAmount' => existingPackage.Loan_Amount__c,
            'paymentFrequency' => existingPackage.Payment_Frequency__c
        };

        Map<String, Object> debugFilters = new Map<String, Object>{
            'Lender_Lienholder__c' => existingPackage.Lender_Lienholder__c,
            'Month__c' => existingPackage.Month__c,
            'Interest_Rate__c' => existingPackage.Interest_Rate__c,
            'Loan_Amount__c' => existingPackage.Loan_Amount__c,
            'Payment_Frequency__c' => existingPackage.Payment_Frequency__c,
            'lenderLienholder' => packageData.get('lenderLienholder'),
            'financeLoanTerm' => packageData.get('financeLoanTerm'),
            'interestRate' => packageData.get('interestRate'),
            'loanAmount' => packageData.get('loanAmount'),
            'paymentFrequency' => packageData.get('paymentFrequency')
        };

        return new Map<String, Object>{
            'success' => true,
            'data' => packageData,
            'debugFilters' => debugFilters
        };
        
    } catch (Exception e) {
return new Map<String, Object>{
            'success' => false,
            'message' => 'Error checking for existing Total Loss Protection package: ' + e.getMessage()
        };
    }
}

/**
 * Create Total Loss Protection application package from map
 * @param packageDataMap Map containing package data
 * @return Map containing success status and record ID
 */
@AuraEnabled
public static Map<String, Object> createTotalLossApplicationPackageFromMap(Map<String, Object> packageDataMap) {
    try {
if (packageDataMap == null) {
throw new CalloutException('Package data cannot be null');
        }
        

        String applicationId = (String) packageDataMap.get('applicationId');
        String dealerId = (String) packageDataMap.get('dealerId');
        String dealerPackageId = (String) packageDataMap.get('dealerPackageId');
        String packageName = (String) packageDataMap.get('packageName');
        String selectedTermId = (String) packageDataMap.get('selectedTermId');
        String recordTypeName = (String) packageDataMap.get('recordType');

        if (String.isBlank(applicationId) || String.isBlank(dealerId) || String.isBlank(dealerPackageId) || 
            String.isBlank(packageName) || String.isBlank(selectedTermId)) {
            throw new CalloutException('Required fields are missing from package data');
        }
        

        List<Dealer_Package_Term__c> terms = [
            SELECT Id, Net_Cost__c, Markup__c, Markup_Type__c, Dealer_Package_Tier__c,
                    Dealer_Package_Tier__r.Package_Tier__c, Package_Tier__c
            FROM Dealer_Package_Term__c
            WHERE Id = :selectedTermId
            LIMIT 1
        ];
        
        if (terms.isEmpty()) {
            throw new CalloutException('Selected term not found');
        }
        
        Dealer_Package_Term__c term = terms[0];
        Decimal netCost = term.Net_Cost__c != null ? term.Net_Cost__c : 0;
        Decimal markup = term.Markup__c != null ? term.Markup__c : 0;
        String markupType = term.Markup_Type__c != null ? term.Markup_Type__c : '';

        Id dealerPackageTierId = term.Dealer_Package_Tier__c;

        Id packageTierId = term.Dealer_Package_Tier__r != null && term.Dealer_Package_Tier__r.Package_Tier__c != null 
                            ? term.Dealer_Package_Tier__r.Package_Tier__c 
                            : term.Package_Tier__c;
        

        Decimal totalPrice = netCost;
        if (markupType == '%' && markup > 0) {
            totalPrice = netCost + (netCost * markup / 100);
        } else if (markupType == '$' && markup > 0) {
            totalPrice = netCost + markup;
        }
        

        Application_Package__c appPackage = new Application_Package__c();
        appPackage.Application__c = applicationId;
        appPackage.Dealer__c = dealerId;
        appPackage.Dealer_Package__c = dealerPackageId;
        appPackage.Dealer_Package_Term__c = selectedTermId;
        appPackage.Dealer_Package_Tier__c = dealerPackageTierId;
        appPackage.Package_Tier__c = packageTierId;
        appPackage.Dealer_Package_Price__c = netCost;
        appPackage.Dealer_Markup__c = markup;


        if (packageDataMap.containsKey('lenderLienholder')) {
            appPackage.Lender_Lienholder__c = (String) packageDataMap.get('lenderLienholder');
        }
        if (packageDataMap.containsKey('financeLoanTerm')) {
            appPackage.Month__c = (String) packageDataMap.get('financeLoanTerm');
        }
        if (packageDataMap.containsKey('loanAmount')) {
            Object loanAmt = packageDataMap.get('loanAmount');
            appPackage.Loan_Amount__c = loanAmt == null ? null : Decimal.valueOf(String.valueOf(loanAmt));
        }
        if (packageDataMap.containsKey('interestRate')) {
            Object intRate = packageDataMap.get('interestRate');
            appPackage.Interest_Rate__c = intRate == null ? null : Decimal.valueOf(String.valueOf(intRate));
        }
        if (packageDataMap.containsKey('paymentFrequency')) {
            appPackage.Payment_Frequency__c = (String) packageDataMap.get('paymentFrequency');
        }

        // Save Is_Vehicle_Financed__c on the parent Application__c
        if (packageDataMap.containsKey('isVehicleFinanced') && String.isNotBlank(applicationId)) {
            try {
                Application__c appForFinance = new Application__c(Id = applicationId);
                appForFinance.Is_Vehicle_Financed__c = Boolean.valueOf(String.valueOf(packageDataMap.get('isVehicleFinanced')));
                update appForFinance;
            } catch (Exception finEx) {
                System.debug('Warning: Could not update Is_Vehicle_Financed__c: ' + finEx.getMessage());
            }
        }
        

        if (String.isNotBlank(recordTypeName)) {
            List<RecordType> recordTypes = [SELECT Id FROM RecordType WHERE Name = :recordTypeName AND SObjectType = 'Application_Package__c' LIMIT 1];
            if (!recordTypes.isEmpty()) {
                appPackage.RecordTypeId = recordTypes[0].Id;
            }
        }
        
        // Populate tax from dealer's region
        TaxRegionHelper.applyDealerTax(appPackage, dealerId);
        
        String recordId;
        try {
            insert appPackage;
            recordId = appPackage.Id;
        } catch (Exception insertException) {
            try {
                recordId = createTotalLossApplicationPackageWithoutSharing(applicationId, dealerId, dealerPackageId, packageName, selectedTermId, 0, recordTypeName);
            } catch (Exception helperException) {
throw new CalloutException('Error creating application package: ' + insertException.getMessage());
            }
        }
return new Map<String, Object>{
            'success' => true,
            'recordId' => recordId,
            'message' => 'Total Loss Protection package created successfully'
        };
        
    } catch (Exception e) {
return new Map<String, Object>{
            'success' => false,
            'message' => 'Error creating Total Loss Protection package: ' + e.getMessage()
        };
    }
}

/**
 * Update Total Loss Protection application package
 * @param packageDataMap Map containing package update data
 * @return Map containing success status
 */
@AuraEnabled
public static Map<String, Object> updateTotalLossApplicationPackage(Map<String, Object> packageDataMap) {
    try {
if (packageDataMap == null) {
            throw new CalloutException('Package data cannot be null');
        }
        
        String packageId = (String) packageDataMap.get('packageId');
        String selectedTermId = (String) packageDataMap.get('selectedTermId');
        Boolean includeDeductible = (Boolean) packageDataMap.get('includeDeductible');
        
        if (String.isBlank(packageId)) {
            throw new CalloutException('Package ID is required');
        }
        

        List<Application_Package__c> packages = [
            SELECT Id, Dealer_Package_Term__c, Dealer_Package_Price__c, Dealer_Markup__c,
                    Lender_Lienholder__c, Month__c, Loan_Amount__c, Interest_Rate__c, Payment_Frequency__c
            FROM Application_Package__c
            WHERE Id = :packageId
            LIMIT 1
        ];
        
        if (packages.isEmpty()) {
            throw new CalloutException('Application package not found');
        }
        
        Application_Package__c appPackage = packages[0];
        

        if (String.isNotBlank(selectedTermId)) {

            List<Dealer_Package_Term__c> terms = [
                SELECT Id, Net_Cost__c, Markup__c, Markup_Type__c, Dealer_Package_Tier__c,
                        Dealer_Package_Tier__r.Package_Tier__c, Package_Tier__c
                FROM Dealer_Package_Term__c
                WHERE Id = :selectedTermId
                LIMIT 1
            ];
            
            if (!terms.isEmpty()) {
                Dealer_Package_Term__c term = terms[0];
                Decimal netCost = term.Net_Cost__c != null ? term.Net_Cost__c : 0;
                Decimal markup = term.Markup__c != null ? term.Markup__c : 0;
                String markupType = term.Markup_Type__c != null ? term.Markup_Type__c : '';

                Id dealerPackageTierId = term.Dealer_Package_Tier__c;

                Id packageTierId = term.Dealer_Package_Tier__r != null && term.Dealer_Package_Tier__r.Package_Tier__c != null 
                                    ? term.Dealer_Package_Tier__r.Package_Tier__c 
                                    : term.Package_Tier__c;
                

                Decimal totalPrice = netCost;
                if (markupType == '%' && markup > 0) {
                    totalPrice = netCost + (netCost * markup / 100);
                } else if (markupType == '$' && markup > 0) {
                    totalPrice = netCost + markup;
                }
                
                appPackage.Dealer_Package_Term__c = selectedTermId;
                appPackage.Dealer_Package_Tier__c = dealerPackageTierId;
                appPackage.Package_Tier__c = packageTierId;
                appPackage.Dealer_Package_Price__c = netCost;
                appPackage.Dealer_Markup__c = markup;

            }
        }


        if (packageDataMap.containsKey('lenderLienholder')) {
            appPackage.Lender_Lienholder__c = (String) packageDataMap.get('lenderLienholder');
        }
        if (packageDataMap.containsKey('financeLoanTerm')) {
            appPackage.Month__c = (String) packageDataMap.get('financeLoanTerm');
        }
        if (packageDataMap.containsKey('loanAmount')) {
            Object loanAmt = packageDataMap.get('loanAmount');
            appPackage.Loan_Amount__c = loanAmt == null ? null : Decimal.valueOf(String.valueOf(loanAmt));
        }
        if (packageDataMap.containsKey('interestRate')) {
            Object intRate = packageDataMap.get('interestRate');
            appPackage.Interest_Rate__c = intRate == null ? null : Decimal.valueOf(String.valueOf(intRate));
        }
        if (packageDataMap.containsKey('paymentFrequency')) {
            appPackage.Payment_Frequency__c = (String) packageDataMap.get('paymentFrequency');
        }
        
        update appPackage;
return new Map<String, Object>{
            'success' => true,
            'message' => 'Total Loss Protection package updated successfully'
        };
        
    } catch (Exception e) {
return new Map<String, Object>{
            'success' => false,
            'message' => 'Error updating Total Loss Protection package: ' + e.getMessage()
        };
    }
}

/**
 * Get additional options for Total Loss Protection at package level
 * @param dealerPackageId The dealer package ID
 * @return AdditionalOptionsResponse containing success status and additional options data
 */
@AuraEnabled(cacheable=true)
public static AdditionalOptionsResponse getTotalLossAdditionalOptionsByPackage(String dealerPackageId) {
    try {
if (String.isBlank(dealerPackageId)) {
            AdditionalOptionsResponse response = new AdditionalOptionsResponse();
            response.success = false;
            response.message = 'Dealer package ID is required';
            return response;
        }
        

        List<Dealer_Package_Option__c> allOptions = [
            SELECT Id, Name, Option__c, Option__r.Name, 
                    Net_Cost__c, Dealer_Markup__c, Markup_Type__c, Retail_Price__c,
                    Original_Package_Option_Price__c, Discount_Type__c, Discount_Value__c,
                    Inclusion__c, Exclusion__c, Selection_Type__c, Dealer_Package__c,
                    Dealer_Package_Term__c, Category__c, Minimum_Value__c, Maximum_Value__c
            FROM Dealer_Package_Option__c
            WHERE Dealer_Package__c = :dealerPackageId
            ORDER BY Category__c, Option__r.Name
        ];

        List<Dealer_Package_Option__c> options = new List<Dealer_Package_Option__c>();
        for (Dealer_Package_Option__c option : allOptions) {
            if (option.Selection_Type__c == 'Optional') {
                options.add(option);
            }
        }

        List<AdditionalOptionDTO> optionDTOs = new List<AdditionalOptionDTO>();
        for (Dealer_Package_Option__c option : options) {
            AdditionalOptionDTO dto = new AdditionalOptionDTO();
            dto.Id = option.Id;
            dto.Name = option.Name;
            dto.optionName = option.Option__r.Name;
            dto.price = option.Retail_Price__c != null ? option.Retail_Price__c : 0;
            dto.originalPrice = option.Original_Package_Option_Price__c != null ? option.Original_Package_Option_Price__c : 0;
            dto.netCost = option.Net_Cost__c != null ? option.Net_Cost__c : 0;
            dto.dealerMarkup = option.Dealer_Markup__c != null ? option.Dealer_Markup__c : 0;
            dto.markupType = option.Markup_Type__c != null ? option.Markup_Type__c : '';
            dto.retailPrice = option.Retail_Price__c != null ? option.Retail_Price__c : 0;
            dto.discountType = option.Discount_Type__c;
            dto.discountValue = option.Discount_Value__c != null ? option.Discount_Value__c : 0;
            dto.inclusion = option.Inclusion__c;
            dto.exclusion = option.Exclusion__c;
            dto.dealerPackageTermId = option.Dealer_Package_Term__c;
            dto.category = option.Category__c;
            dto.minimumValue = option.Minimum_Value__c;
            dto.maximumValue = option.Maximum_Value__c;
            optionDTOs.add(dto);
        }
        
        AdditionalOptionsResponse response = new AdditionalOptionsResponse();
        response.success = true;
        response.data = optionDTOs;
        return response;
        
    } catch (Exception e) {
AdditionalOptionsResponse errorResponse = new AdditionalOptionsResponse();
        errorResponse.success = false;
        errorResponse.message = 'Error loading Total Loss Protection additional options: ' + e.getMessage();
        return errorResponse;
    }
}

/**
 * Get additional options for Total Loss Protection
 * @param dealerPackageTermId The dealer package term ID
 * @return Map containing success status and additional options data
 */
@AuraEnabled(cacheable=true)
public static AdditionalOptionsResponse getTotalLossAdditionalOptions(String dealerPackageTermId) {
    try {
if (String.isBlank(dealerPackageTermId)) {
            AdditionalOptionsResponse response = new AdditionalOptionsResponse();
            response.success = false;
            response.message = 'Dealer package term ID is required';
            return response;
        }
        

        List<Dealer_Package_Option__c> options = [
            SELECT Id, Name, Option__c, Option__r.Name, 
                    Net_Cost__c, Dealer_Markup__c, Markup_Type__c, Retail_Price__c,
                    Original_Package_Option_Price__c, Discount_Type__c, Discount_Value__c,
                    Inclusion__c, Exclusion__c, Selection_Type__c, Category__c,
                    Minimum_Value__c, Maximum_Value__c
            FROM Dealer_Package_Option__c
            WHERE Dealer_Package_Term__c = :dealerPackageTermId
            AND Selection_Type__c = 'Optional'
            ORDER BY Category__c, Option__r.Name
        ];

        List<AdditionalOptionDTO> optionDTOs = new List<AdditionalOptionDTO>();
        for (Dealer_Package_Option__c option : options) {
            AdditionalOptionDTO dto = new AdditionalOptionDTO();
            dto.Id = option.Id;
            dto.Name = option.Name;
            dto.optionName = option.Option__r.Name;
            dto.price = option.Retail_Price__c != null ? option.Retail_Price__c : 0;
            dto.originalPrice = option.Original_Package_Option_Price__c != null ? option.Original_Package_Option_Price__c : 0;
            dto.netCost = option.Net_Cost__c != null ? option.Net_Cost__c : 0;
            dto.dealerMarkup = option.Dealer_Markup__c != null ? option.Dealer_Markup__c : 0;
            dto.markupType = option.Markup_Type__c != null ? option.Markup_Type__c : '';
            dto.retailPrice = option.Retail_Price__c != null ? option.Retail_Price__c : 0;
            dto.discountType = option.Discount_Type__c;
            dto.discountValue = option.Discount_Value__c != null ? option.Discount_Value__c : 0;
            dto.inclusion = option.Inclusion__c;
            dto.exclusion = option.Exclusion__c;
            dto.dealerPackageTermId = option.Dealer_Package_Term__c;
            dto.category = option.Category__c;
            dto.minimumValue = option.Minimum_Value__c;
            dto.maximumValue = option.Maximum_Value__c;
            optionDTOs.add(dto);
        }
        
        AdditionalOptionsResponse response = new AdditionalOptionsResponse();
        response.success = true;
        response.data = optionDTOs;
        return response;
        
    } catch (Exception e) {
AdditionalOptionsResponse errorResponse = new AdditionalOptionsResponse();
        errorResponse.success = false;
        errorResponse.message = 'Error loading Total Loss Protection additional options: ' + e.getMessage();
        return errorResponse;
    }
}

/**
 * Get existing additional options for Total Loss Protection application package
 * @param applicationPackageId The application package ID
 * @return Map containing success status and existing options data
 */
@AuraEnabled
public static AdditionalOptionsResponse getTotalLossExistingAdditionalOptions(String applicationPackageId) {
    try {
if (String.isBlank(applicationPackageId)) {
            AdditionalOptionsResponse response = new AdditionalOptionsResponse();
            response.success = false;
            response.message = 'Application package ID is required';
            return response;
        }
        

        List<Application_Package_Option__c> existingOptions = [
            SELECT Id, Name, Dealer_Package_Option__c, Dealer_Package_Option__r.Name,
                    Dealer_Package_Option__r.Option__r.Name, Net_Cost__c, Dealer_Markup__c,
                    Markup_Type__c, Retail_Price__c, Original_Package_Option_Price__c, Discount_Type__c,
                    Discount_Value__c, Inclusion__c, Exclusion__c, Selection_Type__c,
                    Dealer_Package_Option__r.Category__c
            FROM Application_Package_Option__c
            WHERE Application_Package__c = :applicationPackageId
            AND Selection_Type__c = 'Optional'
            ORDER BY Dealer_Package_Option__r.Option__r.Name
        ];

        List<AdditionalOptionDTO> optionDTOs = new List<AdditionalOptionDTO>();
        for (Application_Package_Option__c option : existingOptions) {
            AdditionalOptionDTO dto = new AdditionalOptionDTO();
            dto.Id = option.Id;
            dto.Name = option.Name;
            dto.optionName = option.Dealer_Package_Option__r.Option__r.Name;
            dto.price = option.Retail_Price__c != null ? option.Retail_Price__c : 0;
            dto.originalPrice = option.Original_Package_Option_Price__c != null ? option.Original_Package_Option_Price__c : 0;
            dto.netCost = option.Net_Cost__c != null ? option.Net_Cost__c : 0;
            dto.dealerMarkup = option.Dealer_Markup__c != null ? option.Dealer_Markup__c : 0;
            dto.markupType = option.Markup_Type__c != null ? option.Markup_Type__c : '';
            dto.retailPrice = option.Retail_Price__c != null ? option.Retail_Price__c : 0;
            dto.discountType = option.Discount_Type__c;
            dto.discountValue = option.Discount_Value__c != null ? option.Discount_Value__c : 0;
            dto.inclusion = option.Inclusion__c;
            dto.exclusion = option.Exclusion__c;
            dto.dealerPackageTermId = option.Dealer_Package_Option__c;
            dto.category = option.Dealer_Package_Option__r.Category__c;
            optionDTOs.add(dto);
        }
        
        AdditionalOptionsResponse response = new AdditionalOptionsResponse();
        response.success = true;
        response.data = optionDTOs;
        return response;
        
    } catch (Exception e) {
AdditionalOptionsResponse errorResponse = new AdditionalOptionsResponse();
        errorResponse.success = false;
        errorResponse.message = 'Error loading existing Total Loss Protection additional options: ' + e.getMessage();
        return errorResponse;
    }
}

/**
 * Update Total Loss Protection additional options
 * @param optionsData Map containing options data
 * @return Map containing success status
 */
@AuraEnabled
public static AdditionalOptionsResponse updateTotalLossAdditionalOptions(Map<String, Object> optionsData) {
    try {
if (optionsData == null) {
            throw new CalloutException('Options data cannot be null');
        }
        
        String applicationPackageId = (String) optionsData.get('applicationPackageId');
        String applicationId = (String) optionsData.get('applicationId');
        

        List<String> optionsToAdd = new List<String>();
        List<String> optionsToRemove = new List<String>();
        
        Object optionsToAddObj = optionsData.get('optionsToAdd');
if (optionsToAddObj instanceof List<Object>) {
for (Object obj : (List<Object>) optionsToAddObj) {
                optionsToAdd.add(String.valueOf(obj));
            }
        } else if (optionsToAddObj instanceof List<String>) {
optionsToAdd = (List<String>) optionsToAddObj;
        }
        
        Object optionsToRemoveObj = optionsData.get('optionsToRemove');
if (optionsToRemoveObj instanceof List<Object>) {
for (Object obj : (List<Object>) optionsToRemoveObj) {
                optionsToRemove.add(String.valueOf(obj));
            }
        } else if (optionsToRemoveObj instanceof List<String>) {
optionsToRemove = (List<String>) optionsToRemoveObj;
        }
if (String.isBlank(applicationPackageId) || String.isBlank(applicationId)) {
            throw new CalloutException('Application package ID and application ID are required');
        }
        

        if (optionsToRemove != null && !optionsToRemove.isEmpty()) {
            List<Application_Package_Option__c> optionsToDelete = [
                SELECT Id FROM Application_Package_Option__c 
                WHERE Id IN :optionsToRemove
            ];
            if (!optionsToDelete.isEmpty()) {
                delete optionsToDelete;
}
        }
        

        if (optionsToAdd != null && !optionsToAdd.isEmpty()) {
            List<Application_Package_Option__c> newOptions = new List<Application_Package_Option__c>();
            
            for (String optionId : optionsToAdd) {

                List<Dealer_Package_Option__c> dealerOptions = [
                    SELECT Id, Package_Option__c, Net_Cost__c, Dealer_Markup__c, Markup_Type__c, Retail_Price__c,
                            Original_Package_Option_Price__c, Discount_Type__c, Discount_Value__c, Inclusion__c, Exclusion__c
                    FROM Dealer_Package_Option__c
                    WHERE Id = :optionId
                    LIMIT 1
                ];
                
                if (!dealerOptions.isEmpty()) {
                    Dealer_Package_Option__c dealerOption = dealerOptions[0];
                    
                    Application_Package_Option__c newOption = new Application_Package_Option__c();
                    newOption.Application__c = applicationId;
                    newOption.Application_Package__c = applicationPackageId;
                    newOption.Dealer_Package_Option__c = optionId;
                    newOption.Package_Option__c = dealerOption.Package_Option__c;

                    newOption.Original_Package_Option_Price__c = dealerOption.Original_Package_Option_Price__c;
                    newOption.Dealer_Markup__c = dealerOption.Dealer_Markup__c;
                    newOption.Markup_Type__c = dealerOption.Markup_Type__c;
                    newOption.Discount_Type__c = dealerOption.Discount_Type__c;
                    newOption.Discount_Value__c = dealerOption.Discount_Value__c;
                    newOption.Inclusion__c = dealerOption.Inclusion__c;
                    newOption.Exclusion__c = dealerOption.Exclusion__c;
                    
                    newOptions.add(newOption);
                }
            }
            
            if (!newOptions.isEmpty()) {
                insert newOptions;
}
        }
        
        AdditionalOptionsResponse response = new AdditionalOptionsResponse();
        response.success = true;
        response.message = 'Total Loss Protection additional options updated successfully';
        return response;
        
    } catch (Exception e) {
AdditionalOptionsResponse errorResponse = new AdditionalOptionsResponse();
        errorResponse.success = false;
        errorResponse.message = 'Error updating Total Loss Protection additional options: ' + e.getMessage();
        return errorResponse;
    }
}

/**
 * Update Total Loss Protection fields selectively
 * @param updateData Map containing update data
 * @return Map containing success status
 */
@AuraEnabled
public static Map<String, Object> updateTotalLossFieldsSelective(Map<String, Object> updateData) {
    try {
if (updateData == null) {
            throw new CalloutException('Update data cannot be null');
        }
        
        String applicationPackageId = (String) updateData.get('applicationPackageId');
        String applicationId = (String) updateData.get('applicationId');
        
        if (String.isBlank(applicationPackageId) || String.isBlank(applicationId)) {
            throw new CalloutException('Application package ID and application ID are required');
        }
        

        List<Application_Package__c> packages = [
            SELECT Id, Dealer_Package__c, Dealer_Package_Term__c, Dealer_Package_Price__c, 
                    Dealer_Markup__c
            FROM Application_Package__c
            WHERE Id = :applicationPackageId
            LIMIT 1
        ];
        
        if (packages.isEmpty()) {
            throw new CalloutException('Application package not found');
        }
        
        Application_Package__c appPackage = packages[0];
        Boolean hasChanges = false;
        

        if (updateData.containsKey('dealerPackageId')) {
            String newDealerPackageId = (String) updateData.get('dealerPackageId');
            if (String.isNotBlank(newDealerPackageId) && appPackage.Dealer_Package__c != newDealerPackageId) {
                appPackage.Dealer_Package__c = newDealerPackageId;
                hasChanges = true;
            }
        }
        

        if (updateData.containsKey('dealerPackageTermId')) {
            String newDealerPackageTermId = (String) updateData.get('dealerPackageTermId');
            if (String.isNotBlank(newDealerPackageTermId) && appPackage.Dealer_Package_Term__c != newDealerPackageTermId) {

                List<Dealer_Package_Term__c> terms = [
                    SELECT Id, Net_Cost__c, Markup__c, Markup_Type__c, Dealer_Package_Tier__c,
                            Dealer_Package_Tier__r.Package_Tier__c, Package_Tier__c
                    FROM Dealer_Package_Term__c
                    WHERE Id = :newDealerPackageTermId
                    LIMIT 1
                ];
                
                if (!terms.isEmpty()) {
                    Dealer_Package_Term__c term = terms[0];
                    Decimal netCost = term.Net_Cost__c != null ? term.Net_Cost__c : 0;
                    Decimal markup = term.Markup__c != null ? term.Markup__c : 0;
                    String markupType = term.Markup_Type__c != null ? term.Markup_Type__c : '';

                    Id dealerPackageTierId = term.Dealer_Package_Tier__c;

                    Id packageTierId = term.Dealer_Package_Tier__r != null && term.Dealer_Package_Tier__r.Package_Tier__c != null 
                                        ? term.Dealer_Package_Tier__r.Package_Tier__c 
                                        : term.Package_Tier__c;
                    

                    Decimal totalPrice = netCost;
                    if (markupType == '%' && markup > 0) {
                        totalPrice = netCost + (netCost * markup / 100);
                    } else if (markupType == '$' && markup > 0) {
                        totalPrice = netCost + markup;
                    }
                    
                    appPackage.Dealer_Package_Term__c = newDealerPackageTermId;
                    appPackage.Dealer_Package_Tier__c = dealerPackageTierId;
                    appPackage.Package_Tier__c = packageTierId;
                    appPackage.Dealer_Package_Price__c = netCost;
                    appPackage.Dealer_Markup__c = markup;

                    hasChanges = true;
                }
            }
        }
        
        if (hasChanges) {
            update appPackage;
} else {
}
        
        return new Map<String, Object>{
            'success' => true,
            'message' => 'Total Loss Protection fields updated successfully'
        };
        
    } catch (Exception e) {
return new Map<String, Object>{
            'success' => false,
            'message' => 'Error updating Total Loss Protection fields: ' + e.getMessage()
        };
    }
}

/**
 * Helper method to create Total Loss Protection application package without sharing restrictions
 * @param applicationId The application ID
 * @param dealerId The dealer ID
 * @param dealerPackageId The dealer package ID
 * @param packageName The package name
 * @param selectedTermId The selected term ID
 * @param deductible The deductible amount
 * @param recordTypeName The record type name
 * @return String The created record ID
 */
private static String createTotalLossApplicationPackageWithoutSharing(String applicationId, String dealerId, String dealerPackageId, String packageName, String selectedTermId, Decimal deductible, String recordTypeName) {
    try {

        List<Dealer_Package_Term__c> terms = [
            SELECT Id, Net_Cost__c, Markup__c, Markup_Type__c, Dealer_Package_Tier__c,
                    Dealer_Package_Tier__r.Package_Tier__c, Package_Tier__c
            FROM Dealer_Package_Term__c
            WHERE Id = :selectedTermId
            LIMIT 1
        ];
        
        if (terms.isEmpty()) {
            throw new CalloutException('Selected term not found');
        }
        
        Dealer_Package_Term__c term = terms[0];
        Decimal netCost = term.Net_Cost__c != null ? term.Net_Cost__c : 0;
        Decimal markup = term.Markup__c != null ? term.Markup__c : 0;
        String markupType = term.Markup_Type__c != null ? term.Markup_Type__c : '';

        Id dealerPackageTierId = term.Dealer_Package_Tier__c;

        Id packageTierId = term.Dealer_Package_Tier__r != null && term.Dealer_Package_Tier__r.Package_Tier__c != null 
                            ? term.Dealer_Package_Tier__r.Package_Tier__c 
                            : term.Package_Tier__c;
        

        Decimal totalPrice = netCost;
        if (markupType == '%' && markup > 0) {
            totalPrice = netCost + (netCost * markup / 100);
        } else if (markupType == '$' && markup > 0) {
            totalPrice = netCost + markup;
        }
        

        Application_Package__c appPackage = new Application_Package__c();
        appPackage.Application__c = applicationId;
        appPackage.Dealer__c = dealerId;
        appPackage.Dealer_Package__c = dealerPackageId;
        appPackage.Dealer_Package_Term__c = selectedTermId;
        appPackage.Dealer_Package_Tier__c = dealerPackageTierId;
        appPackage.Package_Tier__c = packageTierId;
        appPackage.Dealer_Package_Price__c = netCost;
        appPackage.Dealer_Markup__c = markup;

        

        if (String.isNotBlank(recordTypeName)) {
            List<RecordType> recordTypes = [SELECT Id FROM RecordType WHERE Name = :recordTypeName AND SObjectType = 'Application_Package__c' LIMIT 1];
            if (!recordTypes.isEmpty()) {
                appPackage.RecordTypeId = recordTypes[0].Id;
            }
        }
        
        // Populate tax from dealer's region
        TaxRegionHelper.applyDealerTax(appPackage, dealerId);
        
        insert appPackage;
return appPackage.Id;
        
    } catch (Exception e) {
throw new CalloutException('Error creating Total Loss Protection application package: ' + e.getMessage());
    }
}

/**
 * Decode VIN using NHTSA API
 * @param vin The VIN to decode
 * @return VehicleResponse with decoded vehicle data
 */
@AuraEnabled
public static VehicleResponse decodeVin(String vin) {
    VehicleResponse response = new VehicleResponse();
    
    try {

        VinDecoderService.VinDecodeResponse decodeResponse = VinDecoderService.decodeVin(vin);
        
        if (decodeResponse.success && decodeResponse.vehicleData != null) {

            VehicleDataDTO vehicleData = new VehicleDataDTO();
            VinDecoderService.DecodedVehicleData sourceData = decodeResponse.vehicleData;

            vehicleData.vin = vin;
            vehicleData.year = sourceData.year;
            vehicleData.make = sourceData.make;
            vehicleData.model = sourceData.model;
            vehicleData.trim = sourceData.trim;
            vehicleData.vehicleIdentificationNumberVIN = vin; // Set both VIN fields
            vehicleData.modelClass = sourceData.bodyClass;
            

            vehicleData.bodyClass = sourceData.bodyClass;
            vehicleData.manufacturerName = sourceData.manufacturerName;
            vehicleData.vehicleType = sourceData.vehicleType;
            vehicleData.series = sourceData.series;
            vehicleData.style = sourceData.style;
            vehicleData.origin = sourceData.origin;
            

            vehicleData.engineModel = sourceData.engineModel;
            vehicleData.engineCylinders = sourceData.engineCylinders;
            vehicleData.engineDisplacement = sourceData.engineDisplacement;
            vehicleData.engineDisplacementCC = sourceData.engineDisplacementCC;
            vehicleData.engineDisplacementCI = sourceData.engineDisplacementCI;
            vehicleData.enginePower = sourceData.enginePower;
            vehicleData.enginePowerTo = sourceData.enginePowerTo;
            vehicleData.engineStrokeCycles = sourceData.engineStrokeCycles;
            vehicleData.engineConfiguration = sourceData.engineConfiguration;
            vehicleData.engineManufacturer = sourceData.engineManufacturer;
            vehicleData.engineBrakeFrom = sourceData.engineBrakeFrom;
            vehicleData.engineBrakeTo = sourceData.engineBrakeTo;
            vehicleData.otherEngineInfo = sourceData.otherEngineInfo;
            vehicleData.turbo = sourceData.turbo;
            vehicleData.topSpeed = sourceData.topSpeed;
            vehicleData.electrificationLevel = sourceData.electrificationLevel;
            vehicleData.coolingType = sourceData.coolingType;
            vehicleData.valveTrainDesign = sourceData.valveTrainDesign;
            

            vehicleData.transmissionStyle = sourceData.transmissionStyle;
            vehicleData.transmissionSpeeds = sourceData.transmissionSpeeds;
            vehicleData.driveType = sourceData.driveType;
            vehicleData.axles = sourceData.axles;
            vehicleData.axleConfiguration = sourceData.axleConfiguration;
            

            vehicleData.fuelType = sourceData.fuelType;
            vehicleData.fuelTypeSecondary = sourceData.fuelTypeSecondary;
            vehicleData.fuelDeliveryType = sourceData.fuelDeliveryType;
            vehicleData.fuelTankType = sourceData.fuelTankType;
            vehicleData.fuelTankMaterial = sourceData.fuelTankMaterial;
            

            vehicleData.doors = sourceData.doors;
            vehicleData.windows = sourceData.windows;
            vehicleData.wheelBase = sourceData.wheelBase;
            vehicleData.wheelBaseFrom = sourceData.wheelBaseFrom;
            vehicleData.wheelBaseTo = sourceData.wheelBaseTo;
            vehicleData.wheelBaseType = sourceData.wheelBaseType;
            vehicleData.trackWidth = sourceData.trackWidth;
            vehicleData.curbWeight = sourceData.curbWeight;
            vehicleData.gvwr = sourceData.gvwr;
            vehicleData.gvwrFrom = sourceData.gvwrFrom;
            vehicleData.gvwrTo = sourceData.gvwrTo;
            vehicleData.gcvwrFrom = sourceData.gcvwrFrom;
            vehicleData.gcvwrTo = sourceData.gcvwrTo;
            vehicleData.bedLength = sourceData.bedLength;
            vehicleData.bedType = sourceData.bedType;
            vehicleData.cabType = sourceData.cabType;
            

            vehicleData.seats = sourceData.seats;
            vehicleData.seatRows = sourceData.seatRows;
            vehicleData.seatBeltType = sourceData.seatBeltType;
            vehicleData.otherRestraintSystemInfo = sourceData.otherRestraintSystemInfo;
            vehicleData.pretensioner = sourceData.pretensioner;

            
            

            vehicleData.color = sourceData.color;
            

            vehicleData.abs = sourceData.abs;
            vehicleData.esc = sourceData.esc;
            vehicleData.tractionControl = sourceData.tractionControl;
            vehicleData.airbagLocations = sourceData.airbagLocations;
            vehicleData.frontAirbagLocations = sourceData.frontAirbagLocations;
            vehicleData.sideAirbagLocations = sourceData.sideAirbagLocations;
            vehicleData.curtainAirbagLocations = sourceData.curtainAirbagLocations;
            vehicleData.seatCushionAirbagLocations = sourceData.seatCushionAirbagLocations;
            vehicleData.kneeAirbagLocations = sourceData.kneeAirbagLocations;
            vehicleData.tpmsType = sourceData.tpmsType;
            vehicleData.activeSafetySystemNote = sourceData.activeSafetySystemNote;
            

            vehicleData.adaptiveCruiseControl = sourceData.adaptiveCruiseControl;
            vehicleData.crashImminentBraking = sourceData.crashImminentBraking;
            vehicleData.forwardCollisionWarning = sourceData.forwardCollisionWarning;
            vehicleData.dynamicBrakeSupport = sourceData.dynamicBrakeSupport;
            vehicleData.pedestrianAutomaticEmergencyBraking = sourceData.pedestrianAutomaticEmergencyBraking;
            vehicleData.blindSpotWarning = sourceData.blindSpotWarning;
            vehicleData.laneDepartureWarning = sourceData.laneDepartureWarning;
            vehicleData.laneKeepingAssistance = sourceData.laneKeepingAssistance;
            vehicleData.blindSpotIntervention = sourceData.blindSpotIntervention;
            vehicleData.laneCenteringAssistance = sourceData.laneCenteringAssistance;
            vehicleData.backupCamera = sourceData.backupCamera;
            vehicleData.parkingAssist = sourceData.parkingAssist;
            vehicleData.rearCrossTrafficAlert = sourceData.rearCrossTrafficAlert;
            vehicleData.rearAutomaticEmergencyBraking = sourceData.rearAutomaticEmergencyBraking;
            vehicleData.automaticCrashNotification = sourceData.automaticCrashNotification;
            vehicleData.daytimeRunningLight = sourceData.daytimeRunningLight;
            vehicleData.headlampLightSource = sourceData.headlampLightSource;
            vehicleData.semiautomaticHeadlampBeamSwitching = sourceData.semiautomaticHeadlampBeamSwitching;
            vehicleData.adaptiveDrivingBeam = sourceData.adaptiveDrivingBeam;
            vehicleData.autoReverseSystem = sourceData.autoReverseSystem;
            vehicleData.automaticPedestrianAlertingSound = sourceData.automaticPedestrianAlertingSound;
            vehicleData.eventDataRecorder = sourceData.eventDataRecorder;
            vehicleData.keylessIgnition = sourceData.keylessIgnition;
            vehicleData.saeAutomationLevelFrom = sourceData.saeAutomationLevelFrom;
            vehicleData.saeAutomationLevelTo = sourceData.saeAutomationLevelTo;
            

            vehicleData.brakeSystemType = sourceData.brakeSystemType;
            vehicleData.brakeSystemDescription = sourceData.brakeSystemDescription;
            vehicleData.combinedBrakingSystem = sourceData.combinedBrakingSystem;
            vehicleData.wheelieMitigation = sourceData.wheelieMitigation;
            

            vehicleData.numberOfWheels = sourceData.numberOfWheels;
            vehicleData.wheelSizeFront = sourceData.wheelSizeFront;
            vehicleData.wheelSizeRear = sourceData.wheelSizeRear;
            

            vehicleData.batteryType = sourceData.batteryType;
            vehicleData.otherBatteryInfo = sourceData.otherBatteryInfo;
            vehicleData.batteryCellsPerModule = sourceData.batteryCellsPerModule;
            vehicleData.batteryCurrentFrom = sourceData.batteryCurrentFrom;
            vehicleData.batteryVoltageFrom = sourceData.batteryVoltageFrom;
            vehicleData.batteryEnergyFrom = sourceData.batteryEnergyFrom;
            vehicleData.batteryCurrentTo = sourceData.batteryCurrentTo;
            vehicleData.batteryVoltageTo = sourceData.batteryVoltageTo;
            vehicleData.batteryEnergyTo = sourceData.batteryEnergyTo;
            vehicleData.batteryModulesPerPack = sourceData.batteryModulesPerPack;
            vehicleData.batteryPacksPerVehicle = sourceData.batteryPacksPerVehicle;
            vehicleData.evDriveUnit = sourceData.evDriveUnit;
            vehicleData.chargerLevel = sourceData.chargerLevel;
            vehicleData.chargerPower = sourceData.chargerPower;
            

            vehicleData.entertainmentSystem = sourceData.entertainmentSystem;
            vehicleData.steeringLocation = sourceData.steeringLocation;
            

            vehicleData.plantCountry = sourceData.plantCountry;
            vehicleData.plantState = sourceData.plantState;
            vehicleData.plantCity = sourceData.plantCity;
            vehicleData.plantCompanyName = sourceData.plantCompanyName;
            vehicleData.destinationMarket = sourceData.destinationMarket;
            vehicleData.nonLandUse = sourceData.nonLandUse;
            

            vehicleData.trim2 = sourceData.trim2;
            vehicleData.series2 = sourceData.series2;
            vehicleData.note = sourceData.note;
            vehicleData.basePrice = sourceData.basePrice;
            vehicleData.vehicleDescriptor = sourceData.vehicleDescriptor;
            vehicleData.suggestedVin = sourceData.suggestedVin;
            vehicleData.errorCode = sourceData.errorCode;
            vehicleData.possibleValues = sourceData.possibleValues;
            vehicleData.additionalErrorText = sourceData.additionalErrorText;
            vehicleData.errorText = sourceData.errorText;
            

            vehicleData.trailerTypeConnection = sourceData.trailerTypeConnection;
            vehicleData.trailerBodyType = sourceData.trailerBodyType;
            vehicleData.trailerLength = sourceData.trailerLength;
            vehicleData.otherTrailerInfo = sourceData.otherTrailerInfo;
            

            vehicleData.customMotorcycleType = sourceData.customMotorcycleType;
            vehicleData.motorcycleSuspensionType = sourceData.motorcycleSuspensionType;
            vehicleData.motorcycleChassisType = sourceData.motorcycleChassisType;
            vehicleData.otherMotorcycleInfo = sourceData.otherMotorcycleInfo;
            

            vehicleData.busLength = sourceData.busLength;
            vehicleData.busFloorConfigurationType = sourceData.busFloorConfigurationType;
            vehicleData.busType = sourceData.busType;
            vehicleData.otherBusInfo = sourceData.otherBusInfo;
            
            vehicleData.vehicleCategory = 'Used Car';

            response.success = true;
            response.message = decodeResponse.message;
            response.data = vehicleData;
            response.apiSource = decodeResponse.apiSource;
            response.rawResponse = decodeResponse.rawResponse;

        } else {
            // Used Car API failed — cascade to Powersports only on "not found" errors.
            // Do NOT cascade on auth, timeout, or service errors.
            String ec = decodeResponse.errorCode != null ? decodeResponse.errorCode : '';
            Boolean isNotFound = (ec == 'NO_DATA_FOUND'
                               || ec == 'NO_DATA_AVAILABLE'
                               || ec == 'BLACKBOOK_API_ERROR'
                               || ec == 'VIN_NOT_FOUND'
                               || ec == 'BLACKBOOK_FAILED');

            if (isNotFound) {
                PowersportsVinDecoderService.PowersportsDecodeResponse psResult =
                    PowersportsVinDecoderService.decode(vin);

                if (psResult.success) {
                    VehicleDataDTO vehicleData = new VehicleDataDTO();
                    VinDecoderService.DecodedVehicleData sd = psResult.vehicleData;
                    System.debug('power sport data test: ' + JSON.serializePretty(sd));
                    PowersportsVinDecoderService.PowersportsVehicleData pd = psResult.powersportsData;

                    vehicleData.vin                           = vin;
                    vehicleData.vehicleIdentificationNumberVIN = vin;
                    vehicleData.year                          = sd.year;
                    vehicleData.make                          = sd.make;
                    vehicleData.model                         = sd.model;
                    vehicleData.engineCylinders               = sd.engineCylinders;
                    vehicleData.engineDisplacement            = sd.engineDisplacement;

                    vehicleData.vehicleCategory               = 'Powersports';
                    vehicleData.engineCC                      = pd.engineDisplacement != null
                                                                ? Decimal.valueOf(pd.engineDisplacement) : null;

                    vehicleData.powersportsClassName          = pd.className;
                    vehicleData.powersportsModelClass         = pd.modelClass;
                    vehicleData.powersportsUvc                = pd.uvc;
                    vehicleData.powersportsCylinders          = pd.cylinders != null
                                                                ? String.valueOf(pd.cylinders) : null;
                    vehicleData.powersportsPublishDate        = pd.publishDate;
                    vehicleData.powersportsWholeAvg           = pd.wholeAvg;
                    vehicleData.powersportsRetailAvg          = pd.retailAvg;
                    vehicleData.powersportsTradeinClean       = pd.tradeinClean;
                    vehicleData.powersportsTradeinFair        = pd.tradeinFair;
                    vehicleData.powersportsFinadv             = pd.finadv;
                    vehicleData.powersportsMsrp               = pd.msrp;

                    response.success     = true;
                    response.message     = 'VIN decoded successfully';
                    response.data        = vehicleData;
                    response.apiSource   = 'BLACKBOOK_POWERSPORTS';
                    response.rawResponse = psResult.rawResponse;
                } else {
                    response.success     = false;
                    response.message     = 'Unable to decode VIN. Please enter vehicle information manually.';
                    response.apiSource   = 'NONE';
                }
            } else {
                response.success     = false;
                response.message     = decodeResponse.message;
                response.apiSource   = decodeResponse.apiSource;
                response.rawResponse = decodeResponse.rawResponse;
            }
        }
        
    } catch (Exception e) {
        response.success = false;
        response.message = 'Error decoding VIN: ' + e.getMessage();
    }
    
    return response;
}

/**
 * Comparator class to sort Dealer_Package_Term__c records by total price in ascending order
 * Total price is calculated as: (basePrice - discount) + markup
 * Terms with null/zero prices will be placed at the end
 */
public class MileageComparator implements Comparator<Dealer_Package_Term__c> {
    public Integer compare(Dealer_Package_Term__c term1, Dealer_Package_Term__c term2) {

        Decimal price1 = calculateTotalPrice(term1);

        Decimal price2 = calculateTotalPrice(term2);
        

        if (price1 == null || price1 == 0) {
            if (price2 == null || price2 == 0) {
                return 0;
            }
            return 1; // term1 has no price, place it after term2
        }
        if (price2 == null || price2 == 0) {
            return -1; // term2 has no price, place it after term1
        }
        

        if (price1 < price2) {
            return -1;
        } else if (price1 > price2) {
            return 1;
        } else {
            return 0; // Equal prices
        }
    }
    
    /**
     * Calculate total price for a term (same logic as in DTO creation)
     */
    private Decimal calculateTotalPrice(Dealer_Package_Term__c term) {
        try {

            Decimal basePrice = (term.Original_Package_Term_Cost__c != null ? term.Original_Package_Term_Cost__c : 0) +
                                (term.Included_Options_Price__c != null ? term.Included_Options_Price__c : 0) +
                                (term.Additional_Options_Price__c != null ? term.Additional_Options_Price__c : 0);
            

            Decimal discountAmount = 0;
            if (term.Discount_Type__c == '$' && term.Discount_Value__c != null && term.Discount_Value__c > 0) {
                discountAmount = term.Discount_Value__c;
            } else if (term.Discount_Type__c == '%' && term.Discount_Value__c != null && term.Discount_Value__c > 0) {
                discountAmount = (basePrice * term.Discount_Value__c) / 100;
            }
            

            Decimal netCost = term.Net_Cost__c != null ? term.Net_Cost__c : (basePrice - discountAmount);
            

            Decimal totalPrice = netCost;
            if (term.Markup_Type__c == '%' && term.Markup__c != null && term.Markup__c > 0) {
                totalPrice = netCost + (netCost * term.Markup__c / 100);
            } else if (term.Markup_Type__c == '$' && term.Markup__c != null && term.Markup__c > 0) {
                totalPrice = netCost + term.Markup__c;
            }
            
            return totalPrice;
        } catch (Exception e) {
            return 0;
        }
    }
}

    /**
     * Convert an application to a quote
     * Saves the current application and updates it to have Quote status and record type
     * @param applicationId The ID of the application to convert
     * @return ApplicationPackageResponse with success status and message
     */
    @AuraEnabled
    public static ApplicationPackageResponse convertApplicationToQuote(String applicationId) {
        try {
            if (String.isBlank(applicationId)) {
                throw new CalloutException('Application ID is required');
            }

            // Fetch the application
            List<Application__c> applications = [
                SELECT Id, Application_Status__c, RecordTypeId, RecordType.DeveloperName
                FROM Application__c
                WHERE Id = :applicationId
                LIMIT 1
            ];

            if (applications.isEmpty()) {
                throw new CalloutException('Application not found');
            }

            Application__c app = applications[0];

            // Update the application status to Quote
            app.Application_Status__c = 'Quote';

            // Get the Quote record type ID and update the record type
            Id quoteRecordTypeId = Schema.SObjectType.Application__c.getRecordTypeInfosByDeveloperName().get('Quote').getRecordTypeId();
            app.RecordTypeId = quoteRecordTypeId;

            // Update the application
            update app;

            // Return success response
            ApplicationPackageResponse response = new ApplicationPackageResponse();
            response.success = true;
            response.message = 'Application successfully converted to Quote';
            response.recordId = applicationId;
            response.data = new Map<String, Object>{
                'applicationId' => applicationId,
                'newStatus' => 'Quote',
                'recordTypeId' => quoteRecordTypeId
            };

            return response;

        } catch (Exception e) {
            ApplicationPackageResponse response = new ApplicationPackageResponse();
            response.success = false;
            response.message = 'Error converting application to quote: ' + e.getMessage();
            response.recordId = null;
            return response;
        }
    }

    @AuraEnabled
    public static ApplicationPackageResponse convertQuoteToApplication(String applicationId) {
        try {
            if (String.isBlank(applicationId)) {
                throw new CalloutException('Application ID is required');
            }

            // Fetch the application
            List<Application__c> applications = [
                SELECT Id, Application_Status__c, RecordTypeId, RecordType.DeveloperName
                FROM Application__c
                WHERE Id = :applicationId
                LIMIT 1
            ];

            if (applications.isEmpty()) {
                throw new CalloutException('Application not found');
            }

            Application__c app = applications[0];

            // Update the application status to Draft
            app.Application_Status__c = 'Draft';

            // Get the Application record type ID and update the record type
            Id applicationRecordTypeId = Schema.SObjectType.Application__c.getRecordTypeInfosByDeveloperName().get('Application').getRecordTypeId();
            app.RecordTypeId = applicationRecordTypeId;

            // Update the application
            update app;

            // Return success response
            ApplicationPackageResponse response = new ApplicationPackageResponse();
            response.success = true;
            response.message = 'Quote successfully converted to Application';
            response.recordId = applicationId;
            response.data = new Map<String, Object>{
                'applicationId' => applicationId,
                'newStatus' => 'Draft',
                'recordTypeId' => applicationRecordTypeId
            };

            return response;

        } catch (Exception e) {
            ApplicationPackageResponse response = new ApplicationPackageResponse();
            response.success = false;
            response.message = 'Error converting quote to application: ' + e.getMessage();
            response.recordId = null;
            return response;
        }
    }

    /**
     * Save lien holder / financial institution data directly to Application__c
     * Called when the GAP tab is completed WITHOUT selecting a package (skip path).
     * This ensures lien holder data is persisted even without a GAP Application_Package__c.
     * @param applicationId The Application record ID
     * @param lenderLienholder The lien holder / financial institution name
     * @return Map with success status
     */
    @AuraEnabled
    public static Map<String, Object> saveLienHolderToApplication(String applicationId, String lenderLienholder, Boolean isVehicleFinanced) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            if (String.isBlank(applicationId)) {
                result.put('success', false);
                result.put('message', 'Application ID is required');
                return result;
            }
            
            Application__c app = new Application__c(Id = applicationId);
            app.Financial_Institution_Lender__c = String.isNotBlank(lenderLienholder) ? lenderLienholder : null;
            app.Is_Vehicle_Financed__c = isVehicleFinanced != null ? isVehicleFinanced : false;
            update app;
            
            result.put('success', true);
            result.put('message', 'Lien holder saved to application');
        } catch (Exception e) {
            result.put('success', false);
            result.put('message', 'Error saving lien holder: ' + e.getMessage());
        }
        return result;
    }



    /**
     * Check for duplicate VIN across existing Applications and Quotes.
     * Called BEFORE the Black Book VIN decode to warn the dealer.
     * @param vin The VIN to check
     * @param currentApplicationId The current application ID to exclude from results
     * @return Map with 'hasDuplicates' (Boolean) and 'duplicates' (List of Maps)
     */
    @AuraEnabled
    public static Map<String, Object> checkDuplicateVIN(String vin, String currentApplicationId) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('hasDuplicates', false);
        result.put('duplicates', new List<Map<String, Object>>());

        try {
            if (String.isBlank(vin)) {
                return result;
            }

            String trimmedVin = vin.trim();

            // Query Application__c records that have a Vehicle with the same VIN
            // Exclude the current application and look across all record types (Application + Quote)
            List<Application__c> matchingApps = [
                SELECT Id, Name, Application_Status__c, RecordType.Name,
                       Customer_First_Name__c, Customer_Last_Name__c, Customer_Name__c,
                       Vehicle__r.VIN__c, Vehicle__r.Vehicle_Identification_Number_VIN__c,
                       CreatedDate
                FROM Application__c
                WHERE Vehicle__r.VIN__c = :trimmedVin
                AND Id != :currentApplicationId
                AND Application_Status__c != 'Cancelled'
                ORDER BY CreatedDate DESC
                LIMIT 20
            ];

            // Also check by Vehicle_Identification_Number_VIN__c if different from VIN__c
            List<Application__c> matchingApps2 = [
                SELECT Id, Name, Application_Status__c, RecordType.Name,
                       Customer_First_Name__c, Customer_Last_Name__c, Customer_Name__c,
                       Vehicle__r.VIN__c, Vehicle__r.Vehicle_Identification_Number_VIN__c,
                       CreatedDate
                FROM Application__c
                WHERE Vehicle__r.Vehicle_Identification_Number_VIN__c = :trimmedVin
                AND Id != :currentApplicationId
                AND Application_Status__c != 'Cancelled'
                ORDER BY CreatedDate DESC
                LIMIT 20
            ];

            // Merge results, avoiding duplicates by Id
            Map<Id, Application__c> allMatches = new Map<Id, Application__c>();
            for (Application__c app : matchingApps) {
                allMatches.put(app.Id, app);
            }
            for (Application__c app : matchingApps2) {
                allMatches.put(app.Id, app);
            }

            if (!allMatches.isEmpty()) {
                List<Map<String, Object>> duplicates = new List<Map<String, Object>>();
                for (Application__c app : allMatches.values()) {
                    Map<String, Object> dup = new Map<String, Object>();
                    dup.put('recordId', app.Id);
                    dup.put('recordName', app.Name);
                    dup.put('recordType', app.RecordType != null ? app.RecordType.Name : 'Application');
                    dup.put('status', app.Application_Status__c);
                    dup.put('customerName', String.isNotBlank(app.Customer_Name__c) ? app.Customer_Name__c :
                        ((String.isNotBlank(app.Customer_First_Name__c) ? app.Customer_First_Name__c : '') + ' ' +
                         (String.isNotBlank(app.Customer_Last_Name__c) ? app.Customer_Last_Name__c : '')).trim());
                    dup.put('vin', app.Vehicle__r != null ? (String.isNotBlank(app.Vehicle__r.VIN__c) ? app.Vehicle__r.VIN__c : app.Vehicle__r.Vehicle_Identification_Number_VIN__c) : trimmedVin);
                    duplicates.add(dup);
                }
                result.put('hasDuplicates', true);
                result.put('duplicates', duplicates);
            }

        } catch (Exception e) {
            // On error, allow the flow to continue (don't block VIN decode)
            System.debug('Error checking duplicate VIN: ' + e.getMessage());
            result.put('hasDuplicates', false);
            result.put('error', e.getMessage());
        }

        return result;
    }

}