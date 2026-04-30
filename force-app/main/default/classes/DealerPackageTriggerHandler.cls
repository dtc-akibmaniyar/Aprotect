public class DealerPackageTriggerHandler {
    // Map Package__c RecordType DeveloperNames to Dealer_Package__c RecordType DeveloperNames
    private static final Map<String, String> RECORD_TYPE_MAP = new Map<String, String>{
        'Extended_Limited_Warranty' => 'Extended_Limited_Warranty',
        'Car_Loan_Protection' => 'Car_Loan_Protection',
        'Tire_Rim_Protection_Plan' => 'Tire_Rim_Protection_Plan',
        'Gap_Coverage' => 'Total_Loss_Coverage'
    };

    public static void populateFieldsFromPackage(List<Dealer_Package__c> dealerPackages, Set<Id> packageIds) {
        if(packageIds == null || packageIds.isEmpty()) return;

        // Query Package records with all needed fields and RecordType info
        Map<Id, Package__c> packageMap = new Map<Id, Package__c>([
            SELECT Id, Name, Coverage_per_claim__c, Deductible__c, RecordTypeId, 
                   RecordType.DeveloperName, Premium_Model_Fee__c, Package_Group__c,
                   Class__c, Max_Liability_Limit__c, Finance_Term_Min__c,
                   Max_Finance_Term_In_Months__c, Total_Loss_Coverage_Includes__c,
                   Loyalty_Credit__c, Loan_Amount_Limit__c, Max_Collision_Deductible_Coverage__c,
                   Max_Vehicle_Age_Limit_In_Years__c
            FROM Package__c
            WHERE Id IN :packageIds
        ]);

        // Get RecordType map for Dealer_Package__c
        Map<String, Id> dealerPackageRecordTypeMap = new Map<String, Id>();
        for(RecordType rt : [
            SELECT Id, DeveloperName 
            FROM RecordType 
            WHERE SobjectType = 'Dealer_Package__c'
        ]) {
            dealerPackageRecordTypeMap.put(rt.DeveloperName, rt.Id);
        }

        List<Dealer_Package__c> packagesToUpdate = new List<Dealer_Package__c>();

        for(Dealer_Package__c dp : dealerPackages) {
            if(dp.Package__c != null && packageMap.containsKey(dp.Package__c)) {
                Package__c pkg = packageMap.get(dp.Package__c);
                Dealer_Package__c dpToUpdate = new Dealer_Package__c(Id = dp.Id);
                Boolean hasChanges = false;

                // Get RecordType DeveloperName to determine field mappings
                String packageRecordTypeDevName = (pkg.RecordType != null) ? pkg.RecordType.DeveloperName : null;
                Boolean isTotalLoss = (packageRecordTypeDevName == 'Gap_Coverage');

                // Populate Name
                if(String.isNotBlank(pkg.Name)) {
                    dpToUpdate.Name = pkg.Name;
                    hasChanges = true;
                }

                // Populate RecordTypeId by mapping DeveloperName
                if(pkg.RecordTypeId != null && packageRecordTypeDevName != null) {
                    String dealerPackageRecordTypeDevName = RECORD_TYPE_MAP.get(packageRecordTypeDevName);
                    
                    if(dealerPackageRecordTypeDevName != null && dealerPackageRecordTypeMap.containsKey(dealerPackageRecordTypeDevName)) {
                        dpToUpdate.RecordTypeId = dealerPackageRecordTypeMap.get(dealerPackageRecordTypeDevName);
                        hasChanges = true;
                    }
                }

                // Populate Premium_Model_Fee__c
                if(pkg.Premium_Model_Fee__c != null) {
                    dpToUpdate.Premium_Model_Fee__c = pkg.Premium_Model_Fee__c;
                    hasChanges = true;
                }

                // Populate Plan_Type__c from Package_Group__c
                if(pkg.Package_Group__c != null) {
                    dpToUpdate.Plan_Type__c = pkg.Package_Group__c;
                    hasChanges = true;
                }

                // Populate Class__c
                if(String.isNotBlank(pkg.Class__c)) {
                    dpToUpdate.Class__c = pkg.Class__c;
                    hasChanges = true;
                }

                // RecordType-specific field mappings
                if(isTotalLoss) {
                    // Total Loss (Gap_Coverage) specific fields
                    // Populate Min_Finance_Term_In_Months__c from Finance_Term_Min__c
                    if(pkg.Finance_Term_Min__c != null) {
                        dpToUpdate.Min_Finance_Term_In_Months__c = pkg.Finance_Term_Min__c;
                        hasChanges = true;
                    }

                    // Populate Max_Finance_Term_In_Months__c
                    if(pkg.Max_Finance_Term_In_Months__c != null) {
                        dpToUpdate.Max_Finance_Term_In_Months__c = pkg.Max_Finance_Term_In_Months__c;
                        hasChanges = true;
                    }

                    // Populate Total_Loss_Coverage_Includes__c
                    if(String.isNotBlank(pkg.Total_Loss_Coverage_Includes__c)) {
                        dpToUpdate.Total_Loss_Coverage_Includes__c = pkg.Total_Loss_Coverage_Includes__c;
                        hasChanges = true;
                    }

                    // Populate Loyalty_Credit__c
                    if(pkg.Loyalty_Credit__c != null) {
                        dpToUpdate.Loyalty_Credit__c = pkg.Loyalty_Credit__c;
                        hasChanges = true;
                    }

                    // Populate Loan_Amount_Limit__c
                    if(pkg.Loan_Amount_Limit__c != null) {
                        dpToUpdate.Loan_Amount_Limit__c = pkg.Loan_Amount_Limit__c;
                        hasChanges = true;
                    }

                    // Populate Max_Collision_Deductible_Coverage__c
                    if(pkg.Max_Collision_Deductible_Coverage__c != null) {
                        dpToUpdate.Max_Collision_Deductible_Coverage__c = pkg.Max_Collision_Deductible_Coverage__c;
                        hasChanges = true;
                    }

                    // Populate Max_Vehicle_Age_Limit_In_Years__c
                    if(pkg.Max_Vehicle_Age_Limit_In_Years__c != null) {
                        dpToUpdate.Max_Vehicle_Age_Limit_In_Years__c = pkg.Max_Vehicle_Age_Limit_In_Years__c;
                        hasChanges = true;
                    }
                } else {
                    // Other RecordTypes: include Deductible, Max_Liability_Limit, and Per_Claim_Limit
                    // Populate Per_Claim_Limit__c from Coverage_per_claim__c
                    if(pkg.Coverage_per_claim__c != null) {
                        dpToUpdate.Per_Claim_Limit__c = pkg.Coverage_per_claim__c;
                        hasChanges = true;
                    }

                    // Populate Deductable__c from Deductible__c
                    if(pkg.Deductible__c != null) {
                        dpToUpdate.Deductable__c = pkg.Deductible__c;
                        hasChanges = true;
                    }

                    // Populate Max_Liability_Limit__c
                    if(pkg.Max_Liability_Limit__c != null) {
                        dpToUpdate.Max_Liability_Limit__c = pkg.Max_Liability_Limit__c;
                        hasChanges = true;
                    }
                }

                if(hasChanges) {
                    packagesToUpdate.add(dpToUpdate);
                }
            }
        }

        if(!packagesToUpdate.isEmpty()) {
            update packagesToUpdate;
        }

        // Create Dealer Package Tiers and Terms after updating Dealer Package fields
        Map<Id, Id> dealerPackageToPackageMap = new Map<Id, Id>();
        for(Dealer_Package__c dp : dealerPackages) {
            if(dp.Package__c != null && packageMap.containsKey(dp.Package__c)) {
                dealerPackageToPackageMap.put(dp.Id, dp.Package__c);
            }
        }
        
        if(!dealerPackageToPackageMap.isEmpty()) {
            // First create tiers, then terms
            Map<String, Id> packageTierToDealerPackageTierMap = createDealerPackageTiers(dealerPackageToPackageMap);
            createDealerPackageTerms(dealerPackageToPackageMap, packageTierToDealerPackageTierMap);
        }
    }

    /**
     * Creates Dealer_Package_Tier__c records from Package_Tier__c records
     * Maps all fields from Package_Tier__c to Dealer_Package_Tier__c
     * 
     * @param dealerPackageToPackageMap Map of Dealer_Package__c Id → Package__c Id
     * @return Map of composite key (Package_Tier__c Id + '_' + Dealer_Package__c Id) → Dealer_Package_Tier__c Id
     */
    public static Map<String, Id> createDealerPackageTiers(Map<Id, Id> dealerPackageToPackageMap) {
        if(dealerPackageToPackageMap == null || dealerPackageToPackageMap.isEmpty()) {
            return new Map<String, Id>();
        }

        Set<Id> packageIds = new Set<Id>(dealerPackageToPackageMap.values());

        // Query all Package_Tier__c records for the packages with all needed fields
        List<Package_Tier__c> packageTiers = [
            SELECT Id, Name, Package__c, Business_Premium_Fee__c,
                   Financed_Interest_Rate_Min__c, Financed_Interest_Rate_Max__c,
                   Minimum_Financed_Amount__c, Maximum_Financed_Amount__c,
                   Mileage_Restriction_Start__c, Mileage_Restriction_End__c,
                   Mileage_Unit__c, Price__c
            FROM Package_Tier__c
            WHERE Package__c IN :packageIds
        ];

        if(packageTiers.isEmpty()) {
            return new Map<String, Id>();
        }

        // Create reverse map from Package Id to Dealer Package Id(s) - handle multiple dealer packages per package
        Map<Id, List<Id>> packageToDealerPackageMap = new Map<Id, List<Id>>();
        for(Id dealerPackageId : dealerPackageToPackageMap.keySet()) {
            Id packageId = dealerPackageToPackageMap.get(dealerPackageId);
            if(!packageToDealerPackageMap.containsKey(packageId)) {
                packageToDealerPackageMap.put(packageId, new List<Id>());
            }
            packageToDealerPackageMap.get(packageId).add(dealerPackageId);
        }

        // Create Dealer_Package_Tier__c records
        List<Dealer_Package_Tier__c> dealerPackageTiersToInsert = new List<Dealer_Package_Tier__c>();

        for(Package_Tier__c packageTier : packageTiers) {
            Id packageId = packageTier.Package__c;
            List<Id> dealerPackageIds = packageToDealerPackageMap.get(packageId);
            
            if(dealerPackageIds == null || dealerPackageIds.isEmpty()) continue;

            // Create a Dealer_Package_Tier__c record for each Dealer Package
            for(Id dealerPackageId : dealerPackageIds) {
                Dealer_Package_Tier__c dealerTier = new Dealer_Package_Tier__c();
                
                // Relationship fields
                dealerTier.Dealer_Package__c = dealerPackageId;
                dealerTier.Package_Tier__c = packageTier.Id;
                
                // Map all fields from Package_Tier__c to Dealer_Package_Tier__c
                dealerTier.Name = packageTier.Name;
                
                if(packageTier.Business_Premium_Fee__c != null) {
                    dealerTier.Business_Premium_Fee__c = packageTier.Business_Premium_Fee__c;
                }
                
                if(packageTier.Financed_Interest_Rate_Min__c != null) {
                    dealerTier.Interest_Rate_Min__c = packageTier.Financed_Interest_Rate_Min__c;
                }
                
                if(packageTier.Financed_Interest_Rate_Max__c != null) {
                    dealerTier.Interest_Rate_Max__c = packageTier.Financed_Interest_Rate_Max__c;
                }
                
                if(packageTier.Minimum_Financed_Amount__c != null) {
                    dealerTier.Minimum_Financed_Amount__c = packageTier.Minimum_Financed_Amount__c;
                }
                
                if(packageTier.Maximum_Financed_Amount__c != null) {
                    dealerTier.Maximum_Financed_Amount__c = packageTier.Maximum_Financed_Amount__c;
                }
                
                if(packageTier.Mileage_Unit__c != null) {
                    dealerTier.Mileage_Unit__c = packageTier.Mileage_Unit__c;
                }
                
                // Map restriction fields: Mileage_Restriction_Start__c → Minimum__c, Mileage_Restriction_End__c → Maximum__c
                if(packageTier.Mileage_Restriction_Start__c != null) {
                    dealerTier.Minimum__c = packageTier.Mileage_Restriction_Start__c;
                }
                
                if(packageTier.Mileage_Restriction_End__c != null) {
                    dealerTier.Maximum__c = packageTier.Mileage_Restriction_End__c;
                }
                
                dealerPackageTiersToInsert.add(dealerTier);
            }
        }

        if(!dealerPackageTiersToInsert.isEmpty()) {
            insert dealerPackageTiersToInsert;
            
            // Build map from composite key (Package_Tier__c Id + '_' + Dealer_Package__c Id) to Dealer_Package_Tier__c Id
            Map<String, Id> packageTierToDealerPackageTierMap = new Map<String, Id>();
            for(Dealer_Package_Tier__c dealerTier : dealerPackageTiersToInsert) {
                String compositeKey = dealerTier.Package_Tier__c + '_' + dealerTier.Dealer_Package__c;
                packageTierToDealerPackageTierMap.put(compositeKey, dealerTier.Id);
            }
            
            return packageTierToDealerPackageTierMap;
        }

        return new Map<String, Id>();
    }

    public static void createDealerPackageTerms(Map<Id, Id> dealerPackageToPackageMap, Map<String, Id> packageTierToDealerPackageTierMap) {
        if(dealerPackageToPackageMap == null || dealerPackageToPackageMap.isEmpty()) return;

        Set<Id> packageIds = new Set<Id>(dealerPackageToPackageMap.values());

        // Query all Package_Tier__c records for the packages
        List<Package_Tier__c> tiers = [
            SELECT Id, Package__c
            FROM Package_Tier__c
            WHERE Package__c IN :packageIds
        ];

        if(tiers.isEmpty()) return;

        // Create map from Tier Id to Package Id for efficient lookup
        Map<Id, Id> tierToPackageMap = new Map<Id, Id>();
        Set<Id> tierIds = new Set<Id>();
        for(Package_Tier__c tier : tiers) {
            tierIds.add(tier.Id);
            tierToPackageMap.put(tier.Id, tier.Package__c);
        }

        // Query Package records to get RecordType information
        Map<Id, Package__c> packageRecordTypeMap = new Map<Id, Package__c>([
            SELECT Id, RecordType.DeveloperName
            FROM Package__c
            WHERE Id IN :packageIds
        ]);

        // Query all Package_Term__c records for the tiers with all required fields
        List<Package_Term__c> terms = [
            SELECT Id, Name, Mileage__c, ByYear__c, Mileage_Unit__c, Class__c,
                   Premium_Model_Fee__c, Mileage_Restriction__c,
                   Mileage_Restriction_Start__c, Mileage_Restriction_End__c,
                   Price__c, Package_Tier__c, Start_Term__c, Expiry_Term__c,
                   Duration_Type__c, Odometer_KM__c, Restriction_Type__c
            FROM Package_Term__c
            WHERE Package_Tier__c IN :tierIds
        ];

        if(terms.isEmpty()) return;

        // Create reverse map from Package Id to Dealer Package Id(s) - handle multiple dealer packages per package
        Map<Id, List<Id>> packageToDealerPackageMap = new Map<Id, List<Id>>();
        for(Id dealerPackageId : dealerPackageToPackageMap.keySet()) {
            Id packageId = dealerPackageToPackageMap.get(dealerPackageId);
            if(!packageToDealerPackageMap.containsKey(packageId)) {
                packageToDealerPackageMap.put(packageId, new List<Id>());
            }
            packageToDealerPackageMap.get(packageId).add(dealerPackageId);
        }

        // Create Dealer_Package_Term__c records
        List<Dealer_Package_Term__c> dealerPackageTermsToInsert = new List<Dealer_Package_Term__c>();

        for(Package_Term__c term : terms) {
            // Get Package Id from Tier
            Id packageId = tierToPackageMap.get(term.Package_Tier__c);
            if(packageId == null) continue;

            // Get Dealer Package Id(s) for this Package Id
            List<Id> dealerPackageIds = packageToDealerPackageMap.get(packageId);
            if(dealerPackageIds == null || dealerPackageIds.isEmpty()) continue;

            // Get Package RecordType for field mapping
            Package__c pkg = packageRecordTypeMap.get(packageId);
            String recordTypeDevName = (pkg != null && pkg.RecordType != null) ? pkg.RecordType.DeveloperName : null;

            // Create a Dealer_Package_Term__c record for each Dealer Package
            for(Id dealerPackageId : dealerPackageIds) {
                Dealer_Package_Term__c dealerTerm = new Dealer_Package_Term__c();
                
                // Get the Dealer_Package_Tier__c Id for this term's tier and dealer package
                String compositeKey = term.Package_Tier__c + '_' + dealerPackageId;
                Id dealerPackageTierId = packageTierToDealerPackageTierMap.get(compositeKey);
                
                // Map fields based on RecordType (includes relationship fields)
                mapFieldsToDealerPackageTerm(dealerTerm, term, dealerPackageId, dealerPackageTierId, recordTypeDevName);

                dealerPackageTermsToInsert.add(dealerTerm);
            }
        }

        if(!dealerPackageTermsToInsert.isEmpty()) {
            insert dealerPackageTermsToInsert;
        }

        // Create Dealer Package Options after inserting Dealer Package Terms
        if(!dealerPackageTermsToInsert.isEmpty()) {
            // Build map from Dealer_Package_Term__c Id to Package_Term__c Id
            Map<Id, Id> dealerPackageTermToPackageTermMap = new Map<Id, Id>();
            for(Dealer_Package_Term__c dealerTerm : dealerPackageTermsToInsert) {
                dealerPackageTermToPackageTermMap.put(dealerTerm.Id, dealerTerm.Package_Term__c);
            }
            
            createDealerPackageOptions(dealerPackageTermToPackageTermMap, dealerPackageToPackageMap, packageRecordTypeMap);
        }
    }

    /**
     * Maps fields from Package_Term__c to Dealer_Package_Term__c based on RecordType
     * This method allows for RecordType-specific field mappings and can be extended
     * with additional fields for different RecordTypes as needed.
     * 
     * @param dealerTerm The Dealer_Package_Term__c record to populate
     * @param term The source Package_Term__c record
     * @param dealerPackageId The Dealer Package Id for the relationship
     * @param dealerPackageTierId The Dealer Package Tier Id for the relationship
     * @param recordTypeDevName The DeveloperName of the Package RecordType
     */
    private static void mapFieldsToDealerPackageTerm(Dealer_Package_Term__c dealerTerm, Package_Term__c term, Id dealerPackageId, Id dealerPackageTierId, String recordTypeDevName) {
        // Relationship fields (required for all RecordTypes)
        dealerTerm.Dealer_Package__c = dealerPackageId;
        dealerTerm.Package_Term__c = term.Id;
        dealerTerm.Dealer_Package_Tier__c = dealerPackageTierId;
        
        // Common data fields that apply to all RecordTypes
        dealerTerm.Name = term.Name;
        dealerTerm.Premium_Model_Fee__c = term.Premium_Model_Fee__c;
        dealerTerm.Start_Term__c = term.Start_Term__c;
        dealerTerm.Expiry_Term__c = term.Expiry_Term__c;
        dealerTerm.Duration_Type__c = term.Duration_Type__c;
        dealerTerm.Odometer_KM__c = term.Odometer_KM__c;
        dealerTerm.Restriction_Type__c = term.Restriction_Type__c;
        dealerTerm.Mileage__c = term.Mileage__c;
        dealerTerm.ByYear__c = term.ByYear__c;
        dealerTerm.Mileage_Unit__c = term.Mileage_Unit__c;
        dealerTerm.Class__c = term.Class__c;
        dealerTerm.Mileage_Restriction__c = term.Mileage_Restriction__c;
        dealerTerm.Mileage_Restriction_Start__c = term.Mileage_Restriction_Start__c;
        dealerTerm.Mileage_Restriction_End__c = term.Mileage_Restriction_End__c;
        dealerTerm.Original_Package_Term_Cost__c = term.Price__c;

        // RecordType-specific field mappings can be added here as needed
        // Example:
        // if(recordTypeDevName == 'Extended_Limited_Warranty') {
        //     dealerTerm.SomeField__c = term.SomeField__c;
        // }
    }

    /**
     * Creates Dealer_Package_Option__c records from Package_Option__c records based on RecordType
     * Handles RecordType-specific logic:
     * - Car Loan Protection: Optional options at Package level only
     * - Other RecordTypes: Included options at Package level, Optional options at Term level
     * 
     * @param dealerPackageTermToPackageTermMap Map of Dealer_Package_Term__c Id → Package_Term__c Id
     * @param dealerPackageToPackageMap Map of Dealer_Package__c Id → Package__c Id
     * @param packageRecordTypeMap Map of Package__c Id → Package__c (with RecordType info)
     */
    public static void createDealerPackageOptions(Map<Id, Id> dealerPackageTermToPackageTermMap, Map<Id, Id> dealerPackageToPackageMap, Map<Id, Package__c> packageRecordTypeMap) {
        if(dealerPackageTermToPackageTermMap == null || dealerPackageTermToPackageTermMap.isEmpty() ||
           dealerPackageToPackageMap == null || dealerPackageToPackageMap.isEmpty()) {
            return;
        }

        Set<Id> packageIds = new Set<Id>(dealerPackageToPackageMap.values());
        Set<Id> packageTermIds = new Set<Id>(dealerPackageTermToPackageTermMap.values());

        // Build map from Package_Term__c Id to Dealer_Package_Term__c Id(s) - handle multiple dealer terms per package term
        Map<Id, List<Id>> packageTermToDealerPackageTermMap = new Map<Id, List<Id>>();
        for(Id dealerPackageTermId : dealerPackageTermToPackageTermMap.keySet()) {
            Id packageTermId = dealerPackageTermToPackageTermMap.get(dealerPackageTermId);
            if(!packageTermToDealerPackageTermMap.containsKey(packageTermId)) {
                packageTermToDealerPackageTermMap.put(packageTermId, new List<Id>());
            }
            packageTermToDealerPackageTermMap.get(packageTermId).add(dealerPackageTermId);
        }

        // Build map from Dealer_Package_Term__c Id to Dealer_Package__c Id
        Map<Id, Id> dealerPackageTermToDealerPackageMap = new Map<Id, Id>();
        for(Dealer_Package_Term__c dealerTerm : [
            SELECT Id, Dealer_Package__c
            FROM Dealer_Package_Term__c
            WHERE Id IN :dealerPackageTermToPackageTermMap.keySet()
        ]) {
            dealerPackageTermToDealerPackageMap.put(dealerTerm.Id, dealerTerm.Dealer_Package__c);
        }

        List<Dealer_Package_Option__c> dealerPackageOptionsToInsert = new List<Dealer_Package_Option__c>();

        // Process each Package to determine RecordType and query options accordingly
        for(Id packageId : packageIds) {
            Package__c pkg = packageRecordTypeMap.get(packageId);
            if(pkg == null || pkg.RecordType == null) continue;

            String recordTypeDevName = pkg.RecordType.DeveloperName;
            
            // Build list of Dealer Package Ids for this Package
            List<Id> dealerPackageIds = new List<Id>();
            for(Id dealerPackageId : dealerPackageToPackageMap.keySet()) {
                if(dealerPackageToPackageMap.get(dealerPackageId) == packageId) {
                    dealerPackageIds.add(dealerPackageId);
                }
            }
            if(dealerPackageIds.isEmpty()) continue;

            if(recordTypeDevName == 'Car_Loan_Protection') {
                // Car Loan Protection: Optional options at Package level only
                List<Package_Option__c> packageOptions = [
                    SELECT Id, Option__c, Selection_Type__c, Inclusion_Text__c, Exclusion_Text__c,
                           Price__c, Category__c, Minimum_Value__c, Maximum_Value__c
                    FROM Package_Option__c
                    WHERE Package__c = :packageId
                    AND Selection_Type__c = 'Optional'
                    AND Package_Term__c = null
                ];

                for(Package_Option__c packageOption : packageOptions) {
                    for(Id dealerPackageId : dealerPackageIds) {
                        Dealer_Package_Option__c dealerOption = new Dealer_Package_Option__c();
                        mapFieldsToDealerPackageOption(dealerOption, packageOption, dealerPackageId, null, recordTypeDevName);
                        dealerPackageOptionsToInsert.add(dealerOption);
                    }
                }
            } else {
                // Other RecordTypes:
                // - Included options at Package level
                // - Optional options:
                //     - Total Loss (Gap_Coverage): at Package level
                //     - Others: at Term level
                
                // Query Included options at Package level
                List<Package_Option__c> includedOptions = [
                    SELECT Id, Option__c, Selection_Type__c, Inclusion_Text__c, Exclusion_Text__c,
                           Price__c, Category__c, Minimum_Value__c, Maximum_Value__c
                    FROM Package_Option__c
                    WHERE Package__c = :packageId
                    AND Selection_Type__c = 'Included'
                    AND Package_Term__c = null
                ];

                for(Package_Option__c packageOption : includedOptions) {
                    for(Id dealerPackageId : dealerPackageIds) {
                        Dealer_Package_Option__c dealerOption = new Dealer_Package_Option__c();
                        mapFieldsToDealerPackageOption(dealerOption, packageOption, dealerPackageId, null, recordTypeDevName);
                        dealerPackageOptionsToInsert.add(dealerOption);
                    }
                }
                
                // Optional options behaviour differs by RecordType
                if(recordTypeDevName == 'Gap_Coverage') {
                    // Total Loss (Gap_Coverage): Optional options at Package level
                    List<Package_Option__c> optionalOptions = [
                        SELECT Id, Option__c, Selection_Type__c, Inclusion_Text__c, Exclusion_Text__c,
                               Price__c, Category__c, Minimum_Value__c, Maximum_Value__c
                        FROM Package_Option__c
                        WHERE Package__c = :packageId
                        AND Selection_Type__c = 'Optional'
                    ];

                    for(Package_Option__c packageOption : optionalOptions) {
                        for(Id dealerPackageId : dealerPackageIds) {
                            Dealer_Package_Option__c dealerOption = new Dealer_Package_Option__c();
                            mapFieldsToDealerPackageOption(dealerOption, packageOption, dealerPackageId, null, recordTypeDevName);
                            dealerPackageOptionsToInsert.add(dealerOption);
                        }
                    }
                } else {
                    // Other non-Car Loan Protection RecordTypes: Optional options at Term level
                    List<Package_Option__c> optionalOptions = [
                        SELECT Id, Option__c, Selection_Type__c, Inclusion_Text__c, Exclusion_Text__c,
                               Price__c, Category__c, Minimum_Value__c, Maximum_Value__c, Package_Term__c
                        FROM Package_Option__c
                        WHERE Package_Term__c IN :packageTermIds
                        AND Selection_Type__c = 'Optional'
                    ];

                    for(Package_Option__c packageOption : optionalOptions) {
                        List<Id> dealerPackageTermIds = packageTermToDealerPackageTermMap.get(packageOption.Package_Term__c);
                        if(dealerPackageTermIds == null || dealerPackageTermIds.isEmpty()) continue;

                        for(Id dealerPackageTermId : dealerPackageTermIds) {
                            Id dealerPackageId = dealerPackageTermToDealerPackageMap.get(dealerPackageTermId);
                            if(dealerPackageId == null) continue;

                            Dealer_Package_Option__c dealerOption = new Dealer_Package_Option__c();
                            mapFieldsToDealerPackageOption(dealerOption, packageOption, dealerPackageId, dealerPackageTermId, recordTypeDevName);
                            dealerPackageOptionsToInsert.add(dealerOption);
                        }
                    }
                }
            }
        }

        if(!dealerPackageOptionsToInsert.isEmpty()) {
            insert dealerPackageOptionsToInsert;
        }
    }

    /**
     * Maps fields from Package_Option__c to Dealer_Package_Option__c based on RecordType
     * This method allows for RecordType-specific field mappings and can be extended
     * with additional fields for different RecordTypes as needed.
     * 
     * @param dealerOption The Dealer_Package_Option__c record to populate
     * @param packageOption The source Package_Option__c record
     * @param dealerPackageId The Dealer Package Id for the relationship
     * @param dealerPackageTermId The Dealer Package Term Id (null for package-level options)
     * @param recordTypeDevName The DeveloperName of the Package RecordType
     */
    private static void mapFieldsToDealerPackageOption(Dealer_Package_Option__c dealerOption, Package_Option__c packageOption, Id dealerPackageId, Id dealerPackageTermId, String recordTypeDevName) {
        // Relationship fields (required for all RecordTypes)
        dealerOption.Dealer_Package__c = dealerPackageId;
        dealerOption.Package_Option__c = packageOption.Id;
        dealerOption.Dealer_Package_Term__c = dealerPackageTermId; // null for package-level, set for term-level
        dealerOption.Option__c = packageOption.Option__c;
        
        // Common data fields that apply to all RecordTypes
        dealerOption.Selection_Type__c = packageOption.Selection_Type__c;
        dealerOption.Inclusion__c = packageOption.Inclusion_Text__c;
        dealerOption.Exclusion__c = packageOption.Exclusion_Text__c;
        dealerOption.Original_Package_Option_Price__c = packageOption.Price__c;
        dealerOption.Category__c = packageOption.Category__c;
        dealerOption.Minimum_Value__c = packageOption.Minimum_Value__c;
        dealerOption.Maximum_Value__c = packageOption.Maximum_Value__c;

        // Gap_Coverage (Total Loss) specific behaviour:
        // ensure Category__c is populated even if the source option left it blank
        if(recordTypeDevName == 'Gap_Coverage' && String.isBlank(dealerOption.Category__c)) {
            dealerOption.Category__c = 'Total Loss';
        }

        // RecordType-specific field mappings can be added here as needed
        // Example:
        // if(recordTypeDevName == 'Extended_Limited_Warranty') {
        //     dealerOption.SomeField__c = packageOption.SomeField__c;
        // }
    }
}