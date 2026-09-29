/**
 * Backs the "Create Claim" quick action on Application__c (a self-contained
 * screen-action LWC, createClaimModal). Always inserts a brand-new Claim__c -
 * deliberately no edit/update path, even if the Application already has
 * other claims (Osama, testing directly: "this LWC is only there to create
 * new claims. not update an existing claim").
 *
 * Scope, deliberately narrow: the popup only captures the 5 "Claim Details"
 * fields (Date_Filed__c, Current_Odometer__c, Current_Odometer_Unit__c,
 * Claim_Description__c, Customer_Location__c) plus Application__c itself.
 * Every derived field (Dealer_Name__c, Vehicle__c, Package__c/Package_Term__c/
 * Package_Tier__c, Dealer_Package__c/Dealer_Package_Term__c/Dealer_Package_Tier__c,
 * Application_Package__c, Purchase_Date__c, Purchase_Odometer__c,
 * Contract_Start_Date__c/Contract_End_Date__c, Odometer_Start__c/Odometer_End__c)
 * is deliberately left to Claim_Update_Claim_Fields_On_Claim_Creation (the
 * existing on-creation flow, fixed alongside this class) - kept as the
 * single source of truth for creation-time field population rather than
 * having this class and that flow both write the same fields.
 *
 * getApplicationChainData deliberately runs WITHOUT WITH USER_MODE, matching
 * ApplicationSummaryController's existing precedent for reading this same
 * Application__c/Vehicle__c/Application_Package__c chain: those are the
 * Application/Package team's own objects, not Claims-owned, so Claims has no
 * standing to unilaterally decide FLS policy on them via this permission set.
 * createClaim touches only Claim__c, which IS Claims-owned, so it runs
 * through Database.insert(..., AccessLevel.USER_MODE) per the standing
 * hardening convention.
 */
public with sharing class CreateClaimController {

    public class ApplicationChainData {
        // Dealership Information
        @AuraEnabled public String dealerName          { get; set; }
        @AuraEnabled public String dealerCode           { get; set; }
        @AuraEnabled public String dealerAddress        { get; set; }
        @AuraEnabled public String dealerPhone          { get; set; }
        // Application Information
        @AuraEnabled public String applicationName      { get; set; }
        @AuraEnabled public String applicationStatus    { get; set; }
        @AuraEnabled public String customerName         { get; set; }
        @AuraEnabled public String customerAddress      { get; set; }
        @AuraEnabled public String customerHomePhone    { get; set; }
        @AuraEnabled public String customerEmail        { get; set; }
        // Vehicle Information
        @AuraEnabled public String vehicleName          { get; set; }
        @AuraEnabled public String vehicleYear          { get; set; }
        @AuraEnabled public String vehicleMake          { get; set; }
        @AuraEnabled public String vehicleModel         { get; set; }
        @AuraEnabled public String vehicleTrim          { get; set; }
        @AuraEnabled public String vehicleVin           { get; set; }
        @AuraEnabled public Decimal purchaseOdometer    { get; set; }
        @AuraEnabled public String purchaseOdometerUnit { get; set; }
        @AuraEnabled public Date purchaseDate           { get; set; }
        // Plan Information - dealer-specific package/term/tier, not the
        // master catalog (Osama's explicit choice: "claim should be
        // connected to dealer package, term and tier" since that's what
        // was actually sold to the customer)
        @AuraEnabled public String dealerPackageName      { get; set; }
        @AuraEnabled public Id dealerPackageTermId        { get; set; }
        @AuraEnabled public String dealerPackageTermName  { get; set; }
        @AuraEnabled public String dealerPackageTierName  { get; set; }
        // Live-calc inputs (Warranty_Validity__c / Coverage_Active__c mirror)
        @AuraEnabled public String paymentStatus        { get; set; }
        @AuraEnabled public Date contractStartDate      { get; set; }
        @AuraEnabled public Date contractEndDate        { get; set; }
        @AuraEnabled public Decimal odometerStart       { get; set; }
        @AuraEnabled public Decimal odometerEnd         { get; set; }
        // Coverage_Active__c mirror inputs, sourced from Dealer_Package_Term__c
        @AuraEnabled public Decimal startTerm           { get; set; }
        @AuraEnabled public Decimal expiryTerm          { get; set; }
        @AuraEnabled public String durationType         { get; set; }
        @AuraEnabled public String restrictionType      { get; set; }
        @AuraEnabled public Decimal maxEligibleMileage  { get; set; }
        @AuraEnabled public String maxEligibleMileageUnit { get; set; }
    }

    /**
     * Left-rail read for the popup. Runs before any Claim__c exists, so it
     * reads straight off Application__c's own chain rather than anything on
     * Claim__c. See class comment for why this query is not WITH USER_MODE.
     */
    @AuraEnabled(cacheable=true)
    public static ApplicationChainData getApplicationChainData(Id applicationId) {
        if (applicationId == null) {
            throw new AuraHandledException('No Application was provided to Create Claim.');
        }
        List<Application__c> apps = [
            SELECT Id, Name, Application_Status__c, Payment_Status__c,
                   Dealer_Name__c, Dealer_Name__r.Name, Dealer_Code__c, Dealer_Address__c, Dealer_Phone__c,
                   Customer_Name__c, Customer_Name__r.Name, Customer_Address__c, Customer_Home_Phone__c, Customer_Email__c,
                   Vehicle__c, Vehicle__r.Name, Vehicle_Year__c, Vehicle_Make__c, Vehicle_Model__c, Vehicle_Trim__c,
                   Vehicle__r.Vehicle_Identification_Number_VIN__c, Vehicle__r.Odometer__c, Vehicle__r.Odometer_Unit__c,
                   Vehicle__r.Purchase_Date__c
            FROM Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            throw new AuraHandledException('This Application could not be found, or you do not have access to it.');
        }
        Application__c app = apps[0];

        // Real Application_Package__c records are "engine-priced": the real
        // package/term/tier a customer bought lives on the dealer chain, not
        // the master catalog (confirmed live on APP000492's
        // Application_Package__c). Application_Package__c has no direct
        // Dealer_Package_Tier__c lookup - reached one hop further through
        // Dealer_Package_Term__r.Dealer_Package_Tier__r.
        Application_Package__c pkg;
        for (Application_Package__c row : [
            SELECT Id, Contract_Start_Date__c, Contract_End_Date__c, Odometer_Start__c, Odometer_End__c,
                   Dealer_Package__c, Dealer_Package__r.Name,
                   Dealer_Package_Term__c, Dealer_Package_Term__r.Name,
                   Dealer_Package_Term__r.Start_Term__c, Dealer_Package_Term__r.Expiry_Term__c,
                   Dealer_Package_Term__r.Duration_Type__c, Dealer_Package_Term__r.Restriction_Type__c,
                   Dealer_Package_Term__r.Mileage__c, Dealer_Package_Term__r.Mileage_Unit__c,
                   Dealer_Package_Term__r.Dealer_Package_Tier__r.Name
            FROM Application_Package__c
            WHERE Application__c = :applicationId AND Active__c = true
            LIMIT 1
        ]) {
            pkg = row;
        }

        ApplicationChainData data = new ApplicationChainData();
        data.dealerName       = app.Dealer_Name__r != null ? app.Dealer_Name__r.Name : null;
        data.dealerCode       = app.Dealer_Code__c;
        data.dealerAddress    = app.Dealer_Address__c;
        data.dealerPhone      = app.Dealer_Phone__c;
        data.applicationName  = app.Name;
        data.applicationStatus = app.Application_Status__c;
        data.customerName     = app.Customer_Name__r != null ? app.Customer_Name__r.Name : null;
        data.customerAddress  = app.Customer_Address__c;
        data.customerHomePhone = app.Customer_Home_Phone__c;
        data.customerEmail    = app.Customer_Email__c;
        data.vehicleName      = app.Vehicle__r != null ? app.Vehicle__r.Name : null;
        data.vehicleYear      = app.Vehicle_Year__c;
        data.vehicleMake      = app.Vehicle_Make__c;
        data.vehicleModel     = app.Vehicle_Model__c;
        data.vehicleTrim      = app.Vehicle_Trim__c;
        data.vehicleVin       = app.Vehicle__r != null ? app.Vehicle__r.Vehicle_Identification_Number_VIN__c : null;
        data.purchaseOdometer = app.Vehicle__r != null ? app.Vehicle__r.Odometer__c : null;
        data.purchaseOdometerUnit = app.Vehicle__r != null ? app.Vehicle__r.Odometer_Unit__c : null;
        data.purchaseDate     = app.Vehicle__r != null ? app.Vehicle__r.Purchase_Date__c : null;
        data.paymentStatus    = app.Payment_Status__c;

        if (pkg != null) {
            data.dealerPackageName = pkg.Dealer_Package__r != null ? pkg.Dealer_Package__r.Name : null;
            data.dealerPackageTermId = pkg.Dealer_Package_Term__c;
            data.contractStartDate = pkg.Contract_Start_Date__c;
            data.contractEndDate   = pkg.Contract_End_Date__c;
            data.odometerStart     = pkg.Odometer_Start__c;
            data.odometerEnd       = pkg.Odometer_End__c;
            if (pkg.Dealer_Package_Term__r != null) {
                data.dealerPackageTermName = pkg.Dealer_Package_Term__r.Name;
                data.startTerm             = pkg.Dealer_Package_Term__r.Start_Term__c;
                data.expiryTerm            = pkg.Dealer_Package_Term__r.Expiry_Term__c;
                data.durationType          = pkg.Dealer_Package_Term__r.Duration_Type__c;
                data.restrictionType       = pkg.Dealer_Package_Term__r.Restriction_Type__c;
                data.maxEligibleMileage     = pkg.Dealer_Package_Term__r.Mileage__c;
                data.maxEligibleMileageUnit = pkg.Dealer_Package_Term__r.Mileage_Unit__c;
                if (pkg.Dealer_Package_Term__r.Dealer_Package_Tier__r != null) {
                    data.dealerPackageTierName = pkg.Dealer_Package_Term__r.Dealer_Package_Tier__r.Name;
                }
            }
        }
        return data;
    }

    @AuraEnabled
    public static Id createClaim(Id applicationId, Date dateFiled, Decimal currentOdometer,
        String currentOdometerUnit, String claimDescription, String customerLocation) {

        Claim__c claim = new Claim__c(
            Application__c          = applicationId,
            RecordTypeId            = warrantyClaimRecordTypeId(),
            Claim_Status__c         = 'New Claim',
            Date_Filed__c           = dateFiled,
            Current_Odometer__c     = currentOdometer,
            Current_Odometer_Unit__c = currentOdometerUnit,
            Claim_Description__c    = claimDescription,
            Customer_Location__c    = customerLocation
        );
        insertSecured(new List<Claim__c>{ claim });
        return claim.Id;
    }

    private static Id warrantyClaimRecordTypeId() {
        return Schema.SObjectType.Claim__c.getRecordTypeInfosByDeveloperName()
            .get('Warranty_Claim').getRecordTypeId();
    }

    private static void insertSecured(List<SObject> records) {
        if (records.isEmpty()) return;
        try {
            Database.insert(records, AccessLevel.USER_MODE);
        } catch (System.NoAccessException ex) {
            throw new AuraHandledException('You do not have permission to create this type of record. Contact your administrator.');
        }
    }
}