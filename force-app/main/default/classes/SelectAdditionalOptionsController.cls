/**
 * Controller for SelectAdditionalOptions LWC component
 * Fetches package details including package tier and package terms
 */
public without sharing class SelectAdditionalOptionsController {
    
    /**
     * Response wrapper for package details
     */
    public class PackageDetailsResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public PackageDetailsDTO data;
        
        public PackageDetailsResponse() {}
    }

    /**
     * Response wrapper for save operation
     */
    public class SaveResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Integer savedCount;
        
        public SaveResponse() {}
    }

    /**
     * DTO for selected option data
     */
    public class SelectedOptionDTO {
        @AuraEnabled public String packageOptionId;
        @AuraEnabled public String optionId;
        @AuraEnabled public String dealerPackageId;
        @AuraEnabled public String discountType;
        @AuraEnabled public Decimal discountValue;
        @AuraEnabled public String selectionType;
        @AuraEnabled public Decimal originalPrice;
        
        public SelectedOptionDTO() {}
        
        public SelectedOptionDTO(String packageOptionId, String optionId, String dealerPackageId, 
                                String discountType, Decimal discountValue, String selectionType, 
                                Decimal originalPrice) {
            this.packageOptionId = packageOptionId;
            this.optionId = optionId;
            this.dealerPackageId = dealerPackageId;
            this.discountType = discountType;
            this.discountValue = discountValue;
            this.selectionType = selectionType;
            this.originalPrice = originalPrice;
        }
    }
    
    /**
     * DTO for package details
     */
        public class PackageDetailsDTO {
            @AuraEnabled public String id;
            @AuraEnabled public String name;
            @AuraEnabled public String packageName;
            @AuraEnabled public String packageDescription;
            @AuraEnabled public String dealerName;
            @AuraEnabled public String dealerId;
            @AuraEnabled public PackageTierDTO packageTier;
            @AuraEnabled public List<PackageTermDTO> packageTerms;
            
            public PackageDetailsDTO() {}
        }
    
    /**
     * DTO for package tier details
     */
    public class PackageTierDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String description;
        
        public PackageTierDTO() {}
    }
    
    /**
     * DTO for package term details
     */
    public class PackageTermDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String tierName;
        @AuraEnabled public Decimal durationRestrictionInMonths;
        @AuraEnabled public Decimal mileageRestriction;
        @AuraEnabled public String mileageUnit;
        @AuraEnabled public Decimal price;
        @AuraEnabled public Decimal markup;
        @AuraEnabled public Decimal totalPrice;
        @AuraEnabled public String priceDisplay;
        @AuraEnabled public String mileageDisplay;
        @AuraEnabled public String markupDisplay;
        @AuraEnabled public String totalPriceDisplay;
        @AuraEnabled public List<PackageOptionDTO> packageOptions;
        
        public PackageTermDTO() {
            this.packageOptions = new List<PackageOptionDTO>();
        }
    }
    
    /**
     * DTO for package option details
     */
    public class PackageOptionDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String optionId; // The Option__c ID from Package_Option__c
        @AuraEnabled public String selectionType;
        @AuraEnabled public String inclusionText;
        @AuraEnabled public String exclusionText;
        @AuraEnabled public Decimal price;
        @AuraEnabled public String priceDisplay;
        @AuraEnabled public Boolean isSelected;
        
        // Discount fields
        @AuraEnabled public Decimal discountPercentage;
        @AuraEnabled public Decimal discountAmount;
        @AuraEnabled public String discountDisplay;
        @AuraEnabled public Decimal finalPrice;
        @AuraEnabled public String finalPriceDisplay;
        @AuraEnabled public String discountDescription;
        
        public PackageOptionDTO() {
            this.isSelected = false;
            this.discountAmount = 0;
            this.finalPrice = 0;
        }
    }
    
    /**
     * Comparator class to sort PackageTermDTO by tier name, then by duration
     * Fixed decimal comparison issue
     */
    public class PackageTermComparator implements Comparator<PackageTermDTO> {
        public Integer compare(PackageTermDTO a, PackageTermDTO b) {
            // First sort by tier name
            if (a.tierName != b.tierName) {
                if (a.tierName == null) return 1;
                if (b.tierName == null) return -1;
                return a.tierName.compareTo(b.tierName);
            }
            
            // Then sort by duration
            if (a.durationRestrictionInMonths != b.durationRestrictionInMonths) {
                if (a.durationRestrictionInMonths == null) return 1;
                if (b.durationRestrictionInMonths == null) return -1;
                if (a.durationRestrictionInMonths < b.durationRestrictionInMonths) return -1;
                if (a.durationRestrictionInMonths > b.durationRestrictionInMonths) return 1;
            }
            
            // Finally sort by name
            if (a.name != b.name) {
                if (a.name == null) return 1;
                if (b.name == null) return -1;
                return a.name.compareTo(b.name);
            }
            
            return 0;
        }
    }
    
    /**
     * Get package details for a dealer package
     * @param dealerPackageId The ID of the Dealer_Package__c record
     * @return PackageDetailsResponse containing package details
     */
    @AuraEnabled(cacheable=true)
    public static PackageDetailsResponse getPackageDetails(String dealerPackageId) {
        PackageDetailsResponse response = new PackageDetailsResponse();
        
        try {
            // Updated to use correct relationship structure with basic fields only
            System.debug('🔍 SelectAdditionalOptionsController: Fetching package details for ID: ' + dealerPackageId);
            
            if (String.isBlank(dealerPackageId)) {
                response.success = false;
                response.message = 'Dealer Package ID is required.';
                return response;
            }
            
            // First get the dealer package to find the Package__c
            List<Dealer_Package__c> dealerPackages = [
                SELECT Id, Name, Package__c, Package__r.Name, Package__r.Description__c,
                       Dealer__c, Dealer__r.Name
                FROM Dealer_Package__c 
                WHERE Id = :dealerPackageId
                LIMIT 1
            ];
            
            if (dealerPackages.isEmpty()) {
                response.success = false;
                response.message = 'Dealer Package not found.';
                System.debug('❌ No dealer package found with ID: ' + dealerPackageId);
                return response;
            }
            
            Dealer_Package__c dealerPackage = dealerPackages[0];
            String packageId = dealerPackage.Package__c;
            
            // Query Package__c directly first
            List<Package__c> packages = [
                SELECT Id, Name, Description__c
                FROM Package__c 
                WHERE Id = :packageId
                LIMIT 1
            ];
            
            if (packages.isEmpty()) {
                response.success = false;
                response.message = 'Package not found.';
                System.debug('❌ No package found with ID: ' + packageId);
                return response;
            }
            
            Package__c packageRecord = packages[0];
            
            // Build the response data
            PackageDetailsDTO packageData = new PackageDetailsDTO();
            packageData.id = dealerPackage.Id;
            packageData.name = dealerPackage.Name;
            packageData.packageName = packageRecord.Name;
            packageData.packageDescription = packageRecord.Description__c;
            packageData.dealerName = dealerPackage.Dealer__r?.Name;
            packageData.dealerId = dealerPackage.Dealer__c;
            
            // Query ALL Package_Tier__c records that belong to this Package__c
            List<Package_Tier__c> packageTiers = [
                SELECT Id, Name
                FROM Package_Tier__c
                WHERE Package__c = :packageId
                ORDER BY Name
            ];
            
            // Set the first tier as the main tier (for backward compatibility)
            if (!packageTiers.isEmpty()) {
                Package_Tier__c firstTier = packageTiers[0];
                PackageTierDTO tier = new PackageTierDTO();
                tier.id = firstTier.Id;
                tier.name = firstTier.Name;
                tier.description = null; // Description field doesn't exist on Package_Tier__c
                packageData.packageTier = tier;
            }
            
            // Query Package_Term__c records for ALL tiers and include tier information
            List<PackageTermDTO> terms = new List<PackageTermDTO>();
            for (Package_Tier__c packageTier : packageTiers) {
                List<Package_Term__c> packageTerms = [
                    SELECT Id, Name, Duration_Restriction_in_Months__c,
                           Mileage_Restriction__c, Mileage_Unit__c, Price__c
                    FROM Package_Term__c
                    WHERE Package_Tier__c = :packageTier.Id
                    ORDER BY Duration_Restriction_in_Months__c, Name
                ];
                
                for (Package_Term__c packageTerm : packageTerms) {
                    PackageTermDTO term = new PackageTermDTO();
                    term.id = packageTerm.Id;
                    term.name = packageTerm.Name;
                    term.durationRestrictionInMonths = packageTerm.Duration_Restriction_in_Months__c;
                    term.mileageRestriction = packageTerm.Mileage_Restriction__c;
                    term.mileageUnit = packageTerm.Mileage_Unit__c;
                    term.price = packageTerm.Price__c;
                    term.tierName = packageTier.Name; // Add tier name to term
                    // Since we're accessing Package_Term__c directly, we don't have markup/totalPrice from dealer package
                    term.markup = null;
                    term.totalPrice = term.price; // Use the base price as total price
                    
                    // Format display values
                    term.priceDisplay = formatCurrency(term.price);
                    term.markupDisplay = formatPercentage(term.markup);
                    term.totalPriceDisplay = formatCurrency(term.totalPrice);
                    term.mileageDisplay = formatMileage(term.mileageRestriction, term.mileageUnit);
                    
                    // Fetch Package_Option__c records for this term
                    List<Package_Option__c> packageOptions = [
                        SELECT Id, Name, Selection_Type__c, Inclusion_Text__c, Exclusion_Text__c, Price__c, Option__c, Option__r.Name
                        FROM Package_Option__c
                        WHERE Package_Term__c = :packageTerm.Id
                        AND Selection_Type__c = 'Optional'
                        ORDER BY Name
                    ];
                    
                    System.debug('🔍 Found ' + packageOptions.size() + ' optional options for term: ' + packageTerm.Name);
                    
                    // Build package options
                    List<PackageOptionDTO> options = new List<PackageOptionDTO>();
                    for (Package_Option__c packageOption : packageOptions) {
                        PackageOptionDTO option = new PackageOptionDTO();
                        option.id = packageOption.Id;
                        option.name = packageOption.Option__r.Name; // Use Option__c.Name instead of Package_Option__c.Name
                        option.optionId = packageOption.Option__c; // Store the Option__c ID
                        
                        System.debug('🔍 Package Option ' + packageOption.Id + ' has Option__c: ' + packageOption.Option__c + ', Option Name: ' + packageOption.Option__r.Name);
                        option.selectionType = packageOption.Selection_Type__c;
                        option.inclusionText = packageOption.Inclusion_Text__c;
                        option.exclusionText = packageOption.Exclusion_Text__c;
                        option.price = packageOption.Price__c;
                        option.priceDisplay = formatCurrency(option.price);
                        
                        // Initialize discount fields
                        option.discountPercentage = 0;
                        option.discountAmount = 0;
                        option.discountDisplay = formatCurrency(0);
                        option.finalPrice = option.price;
                        option.finalPriceDisplay = option.priceDisplay;
                        option.discountDescription = '';
                        
                        System.debug('📦 Built option: ' + option.name + ' | Price: ' + option.price + ' | Inclusion: ' + option.inclusionText);
                        options.add(option);
                    }
                    term.packageOptions = options;
                    
                    System.debug('✅ Added ' + options.size() + ' options to term: ' + term.name);
                    
                    terms.add(term);
                }
            }
            
            // Sort terms by tier name, then by duration
            terms.sort(new PackageTermComparator());
            packageData.packageTerms = terms;
            
            response.success = true;
            response.data = packageData;
            response.message = 'Package details loaded successfully.';
            
            System.debug('✅ Package details loaded successfully for: ' + packageData.packageName);
            System.debug('📊 Found ' + terms.size() + ' package terms');
            
        } catch (Exception e) {
            System.debug('❌ Error fetching package details: ' + e.getMessage());
            System.debug('❌ Stack trace: ' + e.getStackTraceString());
            
            response.success = false;
            response.message = 'An error occurred while fetching package details: ' + e.getMessage();
        }
        
        return response;
    }
    
    /**
     * Format currency value for display
     */
    private static String formatCurrency(Decimal value) {
        if (value == null) {
            return 'N/A';
        }
        return '$' + String.valueOf(value.setScale(2));
    }
    
    /**
     * Format percentage value for display
     */
    private static String formatPercentage(Decimal value) {
        if (value == null) {
            return 'N/A';
        }
        return String.valueOf(value.setScale(2)) + '%';
    }
    
    /**
     * Format mileage value for display
     */
    private static String formatMileage(Decimal mileage, String unit) {
        if (mileage == null) {
            return 'N/A';
        }
        String unitStr = String.isBlank(unit) ? '' : ' ' + unit;
        return String.valueOf(mileage) + unitStr;
    }

    /**
     * Save selected options to Dealer_Package_Option__c - Alternative method with simpler parameters
     */
    @AuraEnabled
    public static SaveResponse saveDealerPackageOptionsSimple(String dealerPackageId, List<String> packageOptionIds, 
                                                             List<String> optionIds, List<String> discountTypes, 
                                                             List<Decimal> discountValues, List<String> selectionTypes, 
                                                             List<Decimal> originalPrices) {
        SaveResponse response = new SaveResponse();
        
        try {
            System.debug('💾 Saving dealer package options for package: ' + dealerPackageId);
            System.debug('📦 Package Option IDs: ' + packageOptionIds);
            System.debug('📦 Option IDs: ' + optionIds);
            System.debug('📦 Discount Types: ' + discountTypes);
            System.debug('📦 Discount Values: ' + discountValues);
            System.debug('📦 Selection Types: ' + selectionTypes);
            System.debug('📦 Original Prices: ' + originalPrices);
            
            if (packageOptionIds == null || packageOptionIds.isEmpty()) {
                response.success = false;
                response.message = 'No options provided for saving';
                response.savedCount = 0;
                return response;
            }
            
            // First, query Package_Option__c records to get the actual Option__c IDs and Package_Term__c IDs
            Set<String> packageOptionIdSet = new Set<String>(packageOptionIds);
            Map<String, Package_Option__c> packageOptionMap = new Map<String, Package_Option__c>();
            
            for (Package_Option__c po : [SELECT Id, Option__c, Package_Term__c, Inclusion_Text__c, Exclusion_Text__c 
                                        FROM Package_Option__c WHERE Id IN :packageOptionIdSet]) {
                packageOptionMap.put(po.Id, po);
                System.debug('📦 Package Option ' + po.Id + ' -> Option: ' + po.Option__c + ', Term: ' + po.Package_Term__c);
            }
            
            // Query Dealer_Package_Term__c records to find matching records
            Set<String> packageTermIds = new Set<String>();
            for (Package_Option__c po : packageOptionMap.values()) {
                if (po.Package_Term__c != null) {
                    packageTermIds.add(po.Package_Term__c);
                }
            }
            
            Map<String, String> termToDealerPackageTermMap = new Map<String, String>();
            if (!packageTermIds.isEmpty()) {
                for (Dealer_Package_Term__c dpt : [SELECT Id, Package_Term__c FROM Dealer_Package_Term__c 
                                                  WHERE Dealer_Package__c = :dealerPackageId AND Package_Term__c IN :packageTermIds]) {
                    termToDealerPackageTermMap.put(dpt.Package_Term__c, dpt.Id);
                    System.debug('📦 Dealer Package Term ' + dpt.Id + ' for Package Term ' + dpt.Package_Term__c);
                }
            }
            
            List<Dealer_Package_Option__c> recordsToUpsert = new List<Dealer_Package_Option__c>();
            
            for (Integer i = 0; i < packageOptionIds.size(); i++) {
                String packageOptionId = packageOptionIds[i];
                String discountType = i < discountTypes.size() ? discountTypes[i] : '$';
                Decimal discountValue = i < discountValues.size() ? discountValues[i] : 0;
                String selectionType = i < selectionTypes.size() ? selectionTypes[i] : 'Optional';
                Decimal originalPrice = i < originalPrices.size() ? originalPrices[i] : 0;
                
                System.debug('📦 Processing option ' + i + ': ' + packageOptionId);
                System.debug('📦 Dealer Package ID: ' + dealerPackageId);
                
                // Validate required fields
                if (String.isBlank(packageOptionId)) {
                    System.debug('❌ Package Option ID is blank - skipping record');
                    continue;
                }
                if (String.isBlank(dealerPackageId)) {
                    System.debug('❌ Dealer Package ID is blank - skipping record');
                    continue;
                }
                
                // Get Package_Option__c details
                Package_Option__c packageOption = packageOptionMap.get(packageOptionId);
                if (packageOption == null) {
                    System.debug('❌ Package Option not found: ' + packageOptionId);
                    continue;
                }
                
                // Get Dealer_Package_Term__c ID
                String dealerPackageTermId = termToDealerPackageTermMap.get(packageOption.Package_Term__c);
                if (String.isBlank(dealerPackageTermId)) {
                    System.debug('❌ Dealer Package Term not found for Package Term: ' + packageOption.Package_Term__c);
                    continue;
                }
                
                System.debug('✅ All required fields present - creating record');
                System.debug('📦 Option ID: ' + packageOption.Option__c);
                System.debug('📦 Dealer Package Term ID: ' + dealerPackageTermId);
                System.debug('📦 Inclusion Text: ' + packageOption.Inclusion_Text__c);
                System.debug('📦 Exclusion Text: ' + packageOption.Exclusion_Text__c);
                
                Dealer_Package_Option__c record = new Dealer_Package_Option__c();
                
                // Set lookup fields
                record.Package_Option__c = packageOptionId;
                record.Option__c = packageOption.Option__c; // Use the actual Option__c ID from Package_Option__c
                record.Dealer_Package__c = dealerPackageId;
                record.Dealer_Package_Term__c = dealerPackageTermId; // Set the Dealer_Package_Term__c lookup
                
                // Set discount fields
                record.Discount_Type__c = discountType;
                record.Discount_Value__c = discountValue;
                record.Selection_Type__c = selectionType;
                record.Original_Package_Option_Price__c = originalPrice;
                
                // Set inclusion/exclusion text
                record.Inclusion__c = packageOption.Inclusion_Text__c;
                record.Exclusion__c = packageOption.Exclusion_Text__c;
                
                recordsToUpsert.add(record);
                
                System.debug('✅ Prepared record for upsert - Package Option: ' + record.Package_Option__c + 
                           ', Option: ' + record.Option__c + ', Dealer Package: ' + record.Dealer_Package__c + 
                           ', Dealer Package Term: ' + record.Dealer_Package_Term__c);
            }
            
            System.debug('📊 Total records to upsert: ' + recordsToUpsert.size());
            
            if (recordsToUpsert.isEmpty()) {
                response.success = false;
                response.message = 'No valid records to save - all records had missing required fields';
                response.savedCount = 0;
                return response;
            }
            
            // Perform upsert based on Package_Option__c + Dealer_Package__c
            Database.UpsertResult[] results = Database.upsert(recordsToUpsert, false);
            
            Integer successCount = 0;
            Integer errorCount = 0;
            List<String> errors = new List<String>();
            
            for (Database.UpsertResult result : results) {
                if (result.isSuccess()) {
                    successCount++;
                    System.debug('✅ Successfully saved record: ' + result.getId());
                } else {
                    errorCount++;
                    String errorMsg = 'Record failed: ';
                    for (Database.Error error : result.getErrors()) {
                        errorMsg += error.getMessage() + ' ';
                    }
                    errors.add(errorMsg);
                    System.debug('❌ Failed to save record: ' + errorMsg);
                }
            }
            
            response.success = successCount > 0;
            response.savedCount = successCount;
            
            if (errorCount > 0) {
                response.message = 'Saved ' + successCount + ' options successfully. ' + 
                                errorCount + ' failed: ' + String.join(errors, '; ');
            } else {
                response.message = 'All options saved successfully';
            }
            
            System.debug('🎉 Save operation completed - Success: ' + response.success + ', Saved Count: ' + response.savedCount + ', Message: ' + response.message);
            
        } catch (Exception e) {
            System.debug('❌ Error in saveDealerPackageOptionsSimple: ' + e.getMessage());
            System.debug('❌ Stack trace: ' + e.getStackTraceString());
            
            response.success = false;
            response.message = 'An error occurred while saving: ' + e.getMessage();
            response.savedCount = 0;
        }
        
        return response;
    }

    /**
     * Save selected options to Dealer_Package_Option__c
     */
    @AuraEnabled
    public static SaveResponse saveDealerPackageOptions(String dealerPackageId, List<SelectedOptionDTO> selectedOptions) {
        SaveResponse response = new SaveResponse();
        
        try {
            System.debug('💾 Saving dealer package options for package: ' + dealerPackageId);
            System.debug('📦 Selected options count: ' + selectedOptions.size());
            
            if (selectedOptions == null || selectedOptions.isEmpty()) {
                response.success = false;
                response.message = 'No options provided for saving';
                response.savedCount = 0;
                return response;
            }
            
            List<Dealer_Package_Option__c> recordsToUpsert = new List<Dealer_Package_Option__c>();
            
            for (SelectedOptionDTO optionData : selectedOptions) {
                System.debug('📦 Processing option: ' + optionData.packageOptionId);
                System.debug('📦 Dealer Package ID: ' + optionData.dealerPackageId);
                System.debug('📦 Option ID: ' + optionData.optionId);
                System.debug('📦 Discount Type: ' + optionData.discountType);
                System.debug('📦 Discount Value: ' + optionData.discountValue);
                
                // Additional debugging
                System.debug('📦 Package Option ID length: ' + (optionData.packageOptionId != null ? String.valueOf(optionData.packageOptionId.length()) : 'null'));
                System.debug('📦 Dealer Package ID length: ' + (optionData.dealerPackageId != null ? String.valueOf(optionData.dealerPackageId.length()) : 'null'));
                System.debug('📦 Is Package Option ID blank: ' + String.isBlank(optionData.packageOptionId));
                System.debug('📦 Is Dealer Package ID blank: ' + String.isBlank(optionData.dealerPackageId));
                
                // Validate required fields
                if (String.isBlank(optionData.packageOptionId)) {
                    System.debug('❌ Package Option ID is blank - skipping record');
                    continue;
                }
                if (String.isBlank(optionData.dealerPackageId)) {
                    System.debug('❌ Dealer Package ID is blank - skipping record');
                    continue;
                }
                
                System.debug('✅ All required fields present - creating record');
                
                Dealer_Package_Option__c record = new Dealer_Package_Option__c();
                
                // Set lookup fields
                record.Package_Option__c = optionData.packageOptionId;
                record.Option__c = optionData.optionId;
                record.Dealer_Package__c = optionData.dealerPackageId;
                
                // Set discount fields
                record.Discount_Type__c = optionData.discountType;
                record.Discount_Value__c = optionData.discountValue;
                record.Selection_Type__c = optionData.selectionType;
                record.Original_Package_Option_Price__c = optionData.originalPrice;
                
                recordsToUpsert.add(record);
                
                System.debug('✅ Prepared record for upsert - Package Option: ' + record.Package_Option__c + ', Dealer Package: ' + record.Dealer_Package__c);
            }
            
            System.debug('📊 Total records to upsert: ' + recordsToUpsert.size());
            
            if (recordsToUpsert.isEmpty()) {
                response.success = false;
                response.message = 'No valid records to save - all records had missing required fields';
                response.savedCount = 0;
                return response;
            }
            
            // Perform upsert based on Package_Option__c + Dealer_Package__c
            // Note: This assumes there's a unique combination of these fields
            // If there's a custom unique field, use that instead
            Database.UpsertResult[] results = Database.upsert(recordsToUpsert, false);
            
            Integer successCount = 0;
            Integer errorCount = 0;
            List<String> errors = new List<String>();
            
            for (Database.UpsertResult result : results) {
                if (result.isSuccess()) {
                    successCount++;
                    System.debug('✅ Successfully saved record: ' + result.getId());
                } else {
                    errorCount++;
                    String errorMsg = 'Record failed: ';
                    for (Database.Error error : result.getErrors()) {
                        errorMsg += error.getMessage() + ' ';
                    }
                    errors.add(errorMsg);
                    System.debug('❌ Failed to save record: ' + errorMsg);
                }
            }
            
            response.success = successCount > 0;
            response.savedCount = successCount;
            
            if (errorCount > 0) {
                response.message = 'Saved ' + successCount + ' options successfully. ' + 
                                errorCount + ' failed: ' + String.join(errors, '; ');
            } else {
                response.message = 'All options saved successfully';
            }
            
            System.debug('🎉 Save operation completed - Success: ' + response.success + ', Saved Count: ' + response.savedCount);
            
        } catch (Exception e) {
            System.debug('❌ Error in saveDealerPackageOptions: ' + e.getMessage());
            System.debug('❌ Stack trace: ' + e.getStackTraceString());
            
            response.success = false;
            response.message = 'An error occurred while saving: ' + e.getMessage();
            response.savedCount = 0;
        }
        
        return response;
    }
}