/**
 * Helper class to access dealer packages without sharing restrictions
 * This class is used when partner users need access to dealer packages
 * but are restricted by sharing rules
 */
public without sharing class DealerPackageAccessHelper {
    
    /**
     * Fetch dealer packages for a specific dealer without sharing restrictions
     * @param dealerId The ID of the dealer
     * @return List of Dealer_Package__c records
     */
    public static List<Dealer_Package__c> getDealerPackages(String dealerId) {
        try {
            System.debug('🔍 DealerPackageAccessHelper: Fetching packages for dealer: ' + dealerId);
            
            if (String.isBlank(dealerId)) {
                System.debug('⚠️ DealerPackageAccessHelper: Dealer ID is blank');
                return new List<Dealer_Package__c>();
            }
            
            // Query for dealer packages without sharing restrictions
            List<Dealer_Package__c> dealerPackages = [
                SELECT Id, Name, Package__c, Package__r.Name, Package__r.Deductible__c, Package__r.Description__c,
                       Dealer__c, Dealer__r.Name,
                       (SELECT Id, Name, Package_Term__c, Package_Term__r.Name, 
                               Package_Term__r.Duration_Restriction_in_Months__c,
                               Package_Term__r.Mileage_Restriction__c, Package_Term__r.Price__c,
                               Package_Term__r.Mileage_Unit__c, Markup__c, Markup_Type__c,
                               Net_Cost__c, Retail_Price__c,
                               Original_Package_Term_Cost__c, Included_Options_Price__c,
                               Additional_Options_Price__c, Discount_Type__c, Discount_Value__c
                        FROM Dealer_Package_Terms__r
                        ORDER BY Package_Term__r.Duration_Restriction_in_Months__c),
                       (SELECT Id, Name, Option__c, Option__r.Name, 
                               Inclusion__c, Exclusion__c, Selection_Type__c
                        FROM Dealer_Included_Options__r
                        WHERE Selection_Type__c = 'Included'
                        ORDER BY Option__r.Name)
                FROM Dealer_Package__c 
                WHERE Dealer__c = :dealerId
                ORDER BY Package__r.Name
            ];
            
            System.debug('✅ DealerPackageAccessHelper: Found ' + dealerPackages.size() + ' packages for dealer: ' + dealerId);
            return dealerPackages;
            
        } catch (Exception e) {
            System.debug('❌ DealerPackageAccessHelper: Error fetching dealer packages: ' + e.getMessage());
            System.debug('❌ DealerPackageAccessHelper: Stack trace: ' + e.getStackTraceString());
            return new List<Dealer_Package__c>();
        }
    }
    
    /**
     * Fetch all available packages (for admin users or system operations)
     * @return List of all Dealer_Package__c records
     */
    public static List<Dealer_Package__c> getAllDealerPackages() {
        try {
            System.debug('🔍 DealerPackageAccessHelper: Fetching all dealer packages');
            
            List<Dealer_Package__c> allPackages = [
                SELECT Id, Name, Package__c, Package__r.Name, Package__r.Deductible__c, Package__r.Description__c,
                       Dealer__c, Dealer__r.Name,
                       (SELECT Id, Name, Package_Term__c, Package_Term__r.Name, 
                               Package_Term__r.Duration_Restriction_in_Months__c,
                               Package_Term__r.Mileage_Restriction__c, Package_Term__r.Price__c,
                               Package_Term__r.Mileage_Unit__c, Markup__c, Markup_Type__c,
                               Net_Cost__c, Retail_Price__c
                        FROM Dealer_Package_Terms__r
                        ORDER BY Package_Term__r.Duration_Restriction_in_Months__c),
                       (SELECT Id, Name, Option__c, Option__r.Name, 
                               Inclusion__c, Exclusion__c, Selection_Type__c
                        FROM Dealer_Included_Options__r
                        WHERE Selection_Type__c = 'Included'
                        ORDER BY Option__r.Name)
                FROM Dealer_Package__c 
                ORDER BY Dealer__r.Name, Package__r.Name
            ];
            
            System.debug('✅ DealerPackageAccessHelper: Found ' + allPackages.size() + ' total packages');
            return allPackages;
            
        } catch (Exception e) {
            System.debug('❌ DealerPackageAccessHelper: Error fetching all dealer packages: ' + e.getMessage());
            return new List<Dealer_Package__c>();
        }
    }
    
    /**
     * Fetch dealer packages by package name (for searching)
     * @param packageName The name of the package to search for
     * @return List of Dealer_Package__c records matching the package name
     */
    public static List<Dealer_Package__c> getDealerPackagesByPackageName(String packageName) {
        try {
            System.debug('🔍 DealerPackageAccessHelper: Searching for packages with name: ' + packageName);
            
            if (String.isBlank(packageName)) {
                return new List<Dealer_Package__c>();
            }
            
            String searchPattern = '%' + packageName + '%';
            
            List<Dealer_Package__c> matchingPackages = [
                SELECT Id, Name, Package__c, Package__r.Name, Package__r.Deductible__c, Package__r.Description__c,
                       Dealer__c, Dealer__r.Name,
                       (SELECT Id, Name, Package_Term__c, Package_Term__r.Name, 
                               Package_Term__r.Duration_Restriction_in_Months__c,
                               Package_Term__r.Mileage_Restriction__c, Package_Term__r.Price__c,
                               Package_Term__r.Mileage_Unit__c, Markup__c, Markup_Type__c,
                               Net_Cost__c, Retail_Price__c
                        FROM Dealer_Package_Terms__r
                        ORDER BY Package_Term__r.Duration_Restriction_in_Months__c),
                       (SELECT Id, Name, Option__c, Option__r.Name, 
                               Inclusion__c, Exclusion__c, Selection_Type__c
                        FROM Dealer_Included_Options__r
                        WHERE Selection_Type__c = 'Included'
                        ORDER BY Option__r.Name)
                FROM Dealer_Package__c 
                WHERE Package__r.Name LIKE :searchPattern
                ORDER BY Dealer__r.Name, Package__r.Name
            ];
            
            System.debug('✅ DealerPackageAccessHelper: Found ' + matchingPackages.size() + ' packages matching: ' + packageName);
            return matchingPackages;
            
        } catch (Exception e) {
            System.debug('❌ DealerPackageAccessHelper: Error searching packages by name: ' + e.getMessage());
            return new List<Dealer_Package__c>();
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
    public static String createApplicationPackage(String applicationId, String dealerId, String dealerPackageId, String packageName, String selectedTermId, Decimal deductible) {
        try {
            System.debug('🔍 DealerPackageAccessHelper: Creating application package without sharing restrictions');
            System.debug('🔍 Application ID: ' + applicationId);
            System.debug('🔍 Dealer ID: ' + dealerId);
            System.debug('🔍 Dealer Package ID: ' + dealerPackageId);
            System.debug('🔍 Package Name: ' + packageName);
            System.debug('🔍 Selected Term ID: ' + selectedTermId);
            System.debug('🔍 Deductible: ' + deductible);
            System.debug('🔍 Current user: ' + UserInfo.getUserName() + ' (Profile: ' + UserInfo.getProfileId() + ')');
            
            // Validate input parameters
            if (String.isBlank(applicationId) || String.isBlank(dealerId) || String.isBlank(dealerPackageId)) {
                System.debug('❌ DealerPackageAccessHelper: Required parameters are missing');
                return null;
            }
            
            // Verify that the referenced records exist and are accessible
            try {
                System.debug('🔍 DealerPackageAccessHelper: Verifying referenced records exist...');
                
                // Check if application exists
                List<Application__c> apps = [SELECT Id, Name FROM Application__c WHERE Id = :applicationId LIMIT 1];
                System.debug('🔍 DealerPackageAccessHelper: Applications found: ' + apps.size());
                
                // Check if dealer exists
                List<Account> dealers = [SELECT Id, Name FROM Account WHERE Id = :dealerId LIMIT 1];
                System.debug('🔍 DealerPackageAccessHelper: Dealers found: ' + dealers.size());
                
                // Check if dealer package exists
                List<Dealer_Package__c> dealerPackages = [SELECT Id, Name FROM Dealer_Package__c WHERE Id = :dealerPackageId LIMIT 1];
                System.debug('🔍 DealerPackageAccessHelper: Dealer packages found: ' + dealerPackages.size());
                
                if (apps.isEmpty() || dealers.isEmpty() || dealerPackages.isEmpty()) {
                    System.debug('❌ DealerPackageAccessHelper: One or more referenced records not found');
                    return null;
                }
                
                System.debug('✅ DealerPackageAccessHelper: All referenced records verified');
                
            } catch (Exception verifyException) {
                System.debug('⚠️ DealerPackageAccessHelper: Error verifying referenced records: ' + verifyException.getMessage());
                // Continue anyway, as this might be due to sharing rules
            }
            
            // Create the Application_Package__c record
            Application_Package__c appPackage = new Application_Package__c();
            appPackage.Application__c = applicationId;
            appPackage.Dealer__c = dealerId;
            appPackage.Dealer_Package__c = dealerPackageId;
            appPackage.Dealer_Package_Term__c = selectedTermId;
            
            // Set only deductible field for insert (pricing handled by Flow)
            appPackage.Deductible__c = deductible;
            
            // Set record type if available
            try {
                appPackage.RecordTypeId = Schema.SObjectType.Application_Package__c.getRecordTypeInfosByDeveloperName().get('Extended_Limited_Warranty').getRecordTypeId();
                System.debug('🔍 DealerPackageAccessHelper: Set RecordTypeId: ' + appPackage.RecordTypeId);
            } catch (Exception e) {
                System.debug('⚠️ DealerPackageAccessHelper: Could not set record type: ' + e.getMessage());
            }
            
            System.debug('🔍 DealerPackageAccessHelper: Inserting application package...');
            System.debug('🔍 DealerPackageAccessHelper: Final record to insert: ' + appPackage);
            insert appPackage;
            
            System.debug('✅ DealerPackageAccessHelper: Application package created successfully: ' + appPackage.Id);
            return appPackage.Id;
            
        } catch (Exception e) {
            System.debug('❌ DealerPackageAccessHelper: Error creating application package: ' + e.getMessage());
            System.debug('❌ DealerPackageAccessHelper: Exception type: ' + e.getTypeName());
            System.debug('❌ DealerPackageAccessHelper: Stack trace: ' + e.getStackTraceString());
            return null;
        }
    }
    
    /**
     * Create application package with pricing information without sharing restrictions
     * This method bypasses sharing rules to allow partner users to create application packages
     * @param applicationId The ID of the application
     * @param dealerId The ID of the dealer
     * @param dealerPackageId The ID of the dealer package
     * @param packageName The name of the package
     * @param selectedTermId The ID of the selected dealer package term
     * @param totalPrice The total price including markup and deductible
     * @param markup The markup amount
     * @param deductible The deductible amount
     * @return Application_Package__c record ID if successful, null if failed
     */
    public static String createApplicationPackageWithPricing(String applicationId, String dealerId, String dealerPackageId, String packageName, String selectedTermId, Decimal totalPrice, Decimal markup, Decimal deductible) {
        try {
            System.debug('🔍 DealerPackageAccessHelper: Creating application package with pricing without sharing restrictions');
            System.debug('🔍 Application ID: ' + applicationId);
            System.debug('🔍 Dealer ID: ' + dealerId);
            System.debug('🔍 Dealer Package ID: ' + dealerPackageId);
            System.debug('🔍 Package Name: ' + packageName);
            System.debug('🔍 Selected Term ID: ' + selectedTermId);
            System.debug('🔍 Total Price: ' + totalPrice);
            System.debug('🔍 Markup: ' + markup);
            System.debug('🔍 Deductible: ' + deductible);
            System.debug('🔍 Current user: ' + UserInfo.getUserName() + ' (Profile: ' + UserInfo.getProfileId() + ')');
            
            // Validate input parameters
            if (String.isBlank(applicationId) || String.isBlank(dealerId) || String.isBlank(dealerPackageId)) {
                System.debug('❌ DealerPackageAccessHelper: Required parameters are missing');
                return null;
            }
            
            // Create the Application_Package__c record
            Application_Package__c appPackage = new Application_Package__c();
            appPackage.Application__c = applicationId;
            appPackage.Dealer__c = dealerId;
            appPackage.Dealer_Package__c = dealerPackageId;
            appPackage.Dealer_Package_Term__c = selectedTermId;
            
            // Set pricing fields
            appPackage.Dealer_Package_Price__c = totalPrice;
            // appPackage.Dealer_Markup__c = markup; // COMMENTED OUT FOR FIELD TYPE CHANGE
            appPackage.Deductible__c = deductible;
            
            // Set record type if available
            try {
                appPackage.RecordTypeId = Schema.SObjectType.Application_Package__c.getRecordTypeInfosByDeveloperName().get('Extended_Limited_Warranty').getRecordTypeId();
                System.debug('🔍 DealerPackageAccessHelper: Set RecordTypeId: ' + appPackage.RecordTypeId);
            } catch (Exception e) {
                System.debug('⚠️ DealerPackageAccessHelper: Could not set record type: ' + e.getMessage());
            }
            
            System.debug('🔍 DealerPackageAccessHelper: Inserting application package with pricing...');
            System.debug('🔍 DealerPackageAccessHelper: Final record to insert: ' + appPackage);
            insert appPackage;
            
            System.debug('✅ DealerPackageAccessHelper: Application package with pricing created successfully: ' + appPackage.Id);
            return appPackage.Id;
            
        } catch (Exception e) {
            System.debug('❌ DealerPackageAccessHelper: Error creating application package with pricing: ' + e.getMessage());
            System.debug('❌ DealerPackageAccessHelper: Exception type: ' + e.getTypeName());
            System.debug('❌ DealerPackageAccessHelper: Stack trace: ' + e.getStackTraceString());
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
    public static String updateApplicationPackage(String packageId, String selectedTermId, Decimal totalPrice, Decimal markup, Decimal deductible) {
        try {
            System.debug('🔍 DealerPackageAccessHelper: Updating application package without sharing restrictions');
            System.debug('🔍 Package ID: ' + packageId);
            System.debug('🔍 Selected Term ID: ' + selectedTermId);
            System.debug('🔍 Total Price: ' + totalPrice);
            System.debug('🔍 Markup: ' + markup);
            System.debug('🔍 Deductible: ' + deductible);
            System.debug('🔍 Current user: ' + UserInfo.getUserName() + ' (Profile: ' + UserInfo.getProfileId() + ')');
            
            // Validate input parameters
            if (String.isBlank(packageId) || String.isBlank(selectedTermId)) {
                System.debug('❌ DealerPackageAccessHelper: Required parameters are missing');
                return null;
            }
            
            // Query the existing Application Package record
            List<Application_Package__c> existingPackages = [
                SELECT Id, Application__c, Dealer__c, Dealer_Package__c, Dealer_Package_Term__c,
                       Dealer_Package_Price__c, /* Dealer_Markup__c, */ Deductible__c
                FROM Application_Package__c 
                WHERE Id = :packageId 
                LIMIT 1
            ];
            
            if (existingPackages.isEmpty()) {
                System.debug('❌ DealerPackageAccessHelper: No existing package found with ID: ' + packageId);
                return null;
            }
            
            Application_Package__c appPackage = existingPackages[0];
            
            // Store original values for comparison
            String originalTermId = appPackage.Dealer_Package_Term__c;
            Decimal originalPrice = appPackage.Dealer_Package_Price__c;
            // Decimal originalMarkup = appPackage.Dealer_Markup__c;
            Decimal originalMarkup = 0; // Temporarily set to 0 while field type is being changed
            Decimal originalDeductible = appPackage.Deductible__c;
            
            System.debug('🔍 DealerPackageAccessHelper: Original values:');
            System.debug('🔍 Original Term ID: ' + originalTermId);
            System.debug('🔍 Original Price: ' + originalPrice);
            System.debug('🔍 Original Markup: ' + originalMarkup);
            System.debug('🔍 Original Deductible: ' + originalDeductible);
            
            // Only update fields that have changed
            Boolean hasChanges = false;
            String changesList = '';
            
            // Check and update Dealer_Package_Term__c
            if (originalTermId != selectedTermId) {
                appPackage.Dealer_Package_Term__c = selectedTermId;
                hasChanges = true;
                changesList += 'Term ID: ' + originalTermId + ' → ' + selectedTermId + '; ';
                System.debug('🔄 DealerPackageAccessHelper: Term ID changed: ' + originalTermId + ' → ' + selectedTermId);
            }
            
            // Check and update Dealer_Package_Price__c
            if (originalPrice != totalPrice) {
                appPackage.Dealer_Package_Price__c = totalPrice;
                hasChanges = true;
                changesList += 'Price: ' + originalPrice + ' → ' + totalPrice + '; ';
                System.debug('🔄 DealerPackageAccessHelper: Price changed: ' + originalPrice + ' → ' + totalPrice);
            }
            
            // Check and update Dealer_Markup__c - COMMENTED OUT FOR FIELD TYPE CHANGE
            // if (originalMarkup != markup) {
            //     appPackage.Dealer_Markup__c = markup;
            //     hasChanges = true;
            //     changesList += 'Markup: ' + originalMarkup + ' → ' + markup + '; ';
            //     System.debug('🔄 DealerPackageAccessHelper: Markup changed: ' + originalMarkup + ' → ' + markup);
            // }
            
            // Check and update Deductible__c
            if (originalDeductible != deductible) {
                appPackage.Deductible__c = deductible;
                hasChanges = true;
                changesList += 'Deductible: ' + originalDeductible + ' → ' + deductible + '; ';
                System.debug('🔄 DealerPackageAccessHelper: Deductible changed: ' + originalDeductible + ' → ' + deductible);
            }
            
            if (!hasChanges) {
                System.debug('✅ DealerPackageAccessHelper: No changes detected - skipping update');
                return packageId; // Return the same ID to indicate success but no update
            }
            
            System.debug('🔄 DealerPackageAccessHelper: Changes detected: ' + changesList);
            System.debug('🔍 DealerPackageAccessHelper: Updating application package...');
            System.debug('🔍 DealerPackageAccessHelper: Final record to update: ' + appPackage);
            update appPackage;
            
            System.debug('✅ DealerPackageAccessHelper: Application package updated successfully: ' + appPackage.Id);
            return appPackage.Id;
            
        } catch (Exception e) {
            System.debug('❌ DealerPackageAccessHelper: Error updating application package: ' + e.getMessage());
            System.debug('❌ DealerPackageAccessHelper: Exception type: ' + e.getTypeName());
            System.debug('❌ DealerPackageAccessHelper: Stack trace: ' + e.getStackTraceString());
            return null;
        }
    }

    /**
     * Update Application Package Options without sharing restrictions
     * This method bypasses sharing rules to allow partner users to manage additional options
     * @param applicationPackageId The ID of the application package
     * @param applicationId The ID of the application
     * @param optionsToAdd List of Dealer_Package_Option__c IDs to add
     * @param optionsToRemove List of Dealer_Package_Option__c IDs to remove
     * @return String result message
     */
    // New method that accepts pre-created records from controller
    public static String updateApplicationPackageOptionsWithRecords(String applicationPackageId, List<Application_Package_Option__c> recordsToInsert, List<String> optionsToRemove) {
        try {
            System.debug('🔍 DealerPackageAccessHelper: Updating with pre-created records');
            System.debug('🔍 Records to insert: ' + recordsToInsert.size());
            System.debug('🔍 Options to remove: ' + (optionsToRemove != null ? optionsToRemove.size() : 0));
            
            List<Application_Package_Option__c> recordsToDelete = new List<Application_Package_Option__c>();
            
            // Handle removals
            if (optionsToRemove != null && !optionsToRemove.isEmpty()) {
                recordsToDelete = [
                    SELECT Id 
                    FROM Application_Package_Option__c 
                    WHERE Application_Package__c = :applicationPackageId 
                    AND Dealer_Package_Option__c IN :optionsToRemove
                ];
                System.debug('🔍 Found ' + recordsToDelete.size() + ' records to delete');
            }
            
            // Perform DML operations
            if (!recordsToInsert.isEmpty()) {
                System.debug('🔍 About to insert ' + recordsToInsert.size() + ' records');
                for (Integer i = 0; i < recordsToInsert.size(); i++) {
                    Application_Package_Option__c record = recordsToInsert[i];
                    System.debug('🔍 Record ' + i + ': App=' + record.Application__c + 
                                ', AppPkg=' + record.Application_Package__c + 
                                ', DealerPkgOpt=' + record.Dealer_Package_Option__c +
                                ', PackageOpt=' + record.Package_Option__c +
                                ', Inclusion=' + (record.Inclusion__c != null ? 'Set' : 'Null') +
                                ', Exclusion=' + (record.Exclusion__c != null ? 'Set' : 'Null'));
                }
                insert recordsToInsert;
                System.debug('✅ Inserted ' + recordsToInsert.size() + ' application package options');
            }
            
            if (!recordsToDelete.isEmpty()) {
                delete recordsToDelete;
                System.debug('✅ Deleted ' + recordsToDelete.size() + ' application package options');
            }
            
            return 'Success: Processed ' + recordsToInsert.size() + ' additions and ' + recordsToDelete.size() + ' removals';
            
        } catch (Exception e) {
            System.debug('❌ Error in updateApplicationPackageOptionsWithRecords: ' + e.getMessage());
            System.debug('❌ Exception type: ' + e.getTypeName());
            System.debug('❌ Stack trace: ' + e.getStackTraceString());
            
            // If it's a DML exception, provide more detailed information
            if (e instanceof DmlException) {
                DmlException dmlEx = (DmlException) e;
                System.debug('❌ DML Exception details:');
                System.debug('❌ Number of failed records: ' + dmlEx.getNumDml());
                for (Integer i = 0; i < dmlEx.getNumDml(); i++) {
                    System.debug('❌ Failed record index: ' + dmlEx.getDmlIndex(i));
                    System.debug('❌ Failed record ID: ' + dmlEx.getDmlId(i));
                    System.debug('❌ Error message: ' + dmlEx.getDmlMessage(i));
                    System.debug('❌ Status code: ' + dmlEx.getDmlStatusCode(i));
                }
            }
            
            return 'Error: ' + e.getMessage() + ' (Type: ' + e.getTypeName() + ')';
        }
    }

    // Original method (keeping for backward compatibility)
    public static String updateApplicationPackageOptions(String applicationPackageId, String applicationId, List<String> optionsToAdd, List<String> optionsToRemove) {
        try {
            System.debug('🔍 DealerPackageAccessHelper: Updating application package options without sharing restrictions');
            System.debug('🔍 Application Package ID: ' + applicationPackageId);
            System.debug('🔍 Application ID: ' + applicationId);
            System.debug('🔍 Options to add: ' + optionsToAdd);
            System.debug('🔍 Options to remove: ' + optionsToRemove);
            
            // Validate input parameters
            if (String.isBlank(applicationPackageId)) {
                throw new CalloutException('Application Package ID cannot be null or blank');
            }
            
            if (String.isBlank(applicationId)) {
                throw new CalloutException('Application ID cannot be null or blank');
            }
            
            // Check if there are actually any changes to process
            Boolean hasAdditions = optionsToAdd != null && !optionsToAdd.isEmpty();
            Boolean hasRemovals = optionsToRemove != null && !optionsToRemove.isEmpty();
            
            if (!hasAdditions && !hasRemovals) {
                System.debug('ℹ️ No additional options changes to process');
                return 'Success: No changes to process';
            }
            
            List<Application_Package_Option__c> recordsToInsert = new List<Application_Package_Option__c>();
            List<Application_Package_Option__c> recordsToDelete = new List<Application_Package_Option__c>();
            
            // Handle additions
            if (optionsToAdd != null && !optionsToAdd.isEmpty()) {
                System.debug('🔍 Processing ' + optionsToAdd.size() + ' options to add');
                
                // Validate that all IDs are valid before querying
                for (String optionId : optionsToAdd) {
                    if (String.isBlank(optionId)) {
                        System.debug('⚠️ Found blank option ID in optionsToAdd');
                    } else {
                        System.debug('✅ Valid option ID: ' + optionId);
                    }
                }
                
                // Get the dealer package options data for the selected options
                List<Dealer_Package_Option__c> dealerOptions;
                
                try {
                    dealerOptions = [
                        SELECT Id, Package_Option__c, Inclusion__c, Exclusion__c, 
                               Discount_Type__c, Discount_Value__c,
                               Original_Package_Option_Price__c
                        FROM Dealer_Package_Option__c
                        WHERE Id IN :optionsToAdd
                    ];
                    
                    System.debug('🔍 Found ' + dealerOptions.size() + ' dealer options from query');
                    
                    if (dealerOptions.isEmpty()) {
                        System.debug('⚠️ No dealer options found for the provided IDs');
                        return 'Error: No dealer options found for the provided IDs';
                    }
                } catch (Exception queryException) {
                    System.debug('❌ Error querying dealer options: ' + queryException.getMessage());
                    throw queryException;
                }
                
                for (Dealer_Package_Option__c dealerOption : dealerOptions) {
                    // Validate that Package_Option__c is not null
                    if (dealerOption.Package_Option__c == null) {
                        System.debug('⚠️ Skipping dealer option with null Package_Option__c: ' + dealerOption.Id);
                        continue;
                    }
                    
                    try {
                        System.debug('🔍 Processing dealer option: ' + dealerOption.Id);
                        System.debug('🔍 Package_Option__c: ' + dealerOption.Package_Option__c);
                        System.debug('🔍 applicationId: ' + applicationId);
                        System.debug('🔍 applicationPackageId: ' + applicationPackageId);
                        
                        Application_Package_Option__c appOption = new Application_Package_Option__c();
                        
                        // Set fields one by one with null checks
                        if (String.isNotBlank(applicationId)) {
                            appOption.Application__c = applicationId;
                            System.debug('✅ Set Application__c: ' + applicationId);
                        } else {
                            System.debug('❌ applicationId is blank');
                        }
                        
                        if (String.isNotBlank(applicationPackageId)) {
                            appOption.Application_Package__c = applicationPackageId;
                            System.debug('✅ Set Application_Package__c: ' + applicationPackageId);
                        } else {
                            System.debug('❌ applicationPackageId is blank');
                        }
                        
                        if (String.isNotBlank(dealerOption.Package_Option__c)) {
                            appOption.Package_Option__c = dealerOption.Package_Option__c;
                            System.debug('✅ Set Package_Option__c: ' + dealerOption.Package_Option__c);
                        } else {
                            System.debug('❌ dealerOption.Package_Option__c is blank');
                        }
                        
                        // Set other fields with null safety
                        appOption.Inclusion__c = String.isNotBlank(dealerOption.Inclusion__c) ? dealerOption.Inclusion__c : null;
                        appOption.Exclusion__c = String.isNotBlank(dealerOption.Exclusion__c) ? dealerOption.Exclusion__c : null;
                        appOption.Discount_Type__c = String.isNotBlank(dealerOption.Discount_Type__c) ? dealerOption.Discount_Type__c : null;
                        appOption.Discount_Value__c = dealerOption.Discount_Value__c != null ? dealerOption.Discount_Value__c : null;
                        appOption.Original_Package_Option_Price__c = dealerOption.Original_Package_Option_Price__c != null ? dealerOption.Original_Package_Option_Price__c : null;
                        // appOption.Dealer_Markup__c = dealerOption.Dealer_Markup__c != null ? dealerOption.Dealer_Markup__c : null; // COMMENTED OUT FOR FIELD TYPE CHANGE
                        
                        System.debug('✅ Set all fields for option: ' + dealerOption.Id);
                        
                        recordsToInsert.add(appOption);
                        System.debug('✅ Prepared Application Package Option for: ' + dealerOption.Package_Option__c);
                    } catch (Exception fieldException) {
                        System.debug('❌ Error preparing Application Package Option: ' + fieldException.getMessage());
                        System.debug('❌ Exception type: ' + fieldException.getTypeName());
                        System.debug('❌ Stack trace: ' + fieldException.getStackTraceString());
                        System.debug('❌ Dealer Option ID: ' + dealerOption.Id);
                        System.debug('❌ Package Option ID: ' + dealerOption.Package_Option__c);
                        throw fieldException;
                    }
                }
            }
            
            // Handle removals
            if (optionsToRemove != null && !optionsToRemove.isEmpty()) {
                // Get Package_Option__c IDs from Dealer_Package_Option__c records
                List<Dealer_Package_Option__c> dealerOptionsToRemove = [
                    SELECT Package_Option__c FROM Dealer_Package_Option__c WHERE Id IN :optionsToRemove
                ];
                
                List<String> packageOptionIds = new List<String>();
                for (Dealer_Package_Option__c dealerOpt : dealerOptionsToRemove) {
                    if (dealerOpt.Package_Option__c != null) {
                        packageOptionIds.add(dealerOpt.Package_Option__c);
                    }
                }
                
                if (!packageOptionIds.isEmpty()) {
                    recordsToDelete = [
                        SELECT Id FROM Application_Package_Option__c
                        WHERE Application_Package__c = :applicationPackageId
                        AND Package_Option__c IN :packageOptionIds
                        AND Selection_Type__c = 'Optional'
                    ];
                }
            }
            
            // Perform DML operations without sharing restrictions
            Integer deletedCount = 0;
            Integer insertedCount = 0;
            
            if (!recordsToDelete.isEmpty()) {
                delete recordsToDelete;
                deletedCount = recordsToDelete.size();
                System.debug('✅ Deleted ' + deletedCount + ' additional options');
            }
            
            if (!recordsToInsert.isEmpty()) {
                insert recordsToInsert;
                insertedCount = recordsToInsert.size();
                System.debug('✅ Inserted ' + insertedCount + ' additional options');
            }
            
            return 'Success: ' + insertedCount + ' options added, ' + deletedCount + ' options removed';
            
        } catch (Exception e) {
            System.debug('❌ DealerPackageAccessHelper: Error updating application package options: ' + e.getMessage());
            System.debug('❌ Stack trace: ' + e.getStackTraceString());
            return 'Error: ' + e.getMessage();
        }
    }
}