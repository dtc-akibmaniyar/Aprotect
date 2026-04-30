public without sharing class CreatePackageOptionsController {

    public class RecordInfoDTO {
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String objectLabel;
        @AuraEnabled public String recordTypeName;
        @AuraEnabled public String termName;
        @AuraEnabled public String tierName;
        @AuraEnabled public String packageName;
        @AuraEnabled public Id packageId;
    }

    @AuraEnabled(cacheable=true)
    public static RecordInfoDTO getRecordInfo(Id recordId) {
        if (recordId == null) {
            return null;
        }

        try {
            // Determine the sObject type from the Id
            SObjectType sobjectType = recordId.getSObjectType();
            Schema.DescribeSObjectResult describeResult = sobjectType.getDescribe();
            String objectApiName = describeResult.getName();

            RecordInfoDTO dto = new RecordInfoDTO();
            dto.objectApiName = objectApiName;
            dto.objectLabel = describeResult.getLabel();

            // Handle Package_Term__c records - traverse Term > Tier > Package
            if (objectApiName == 'Package_Term__c') {
                List<Package_Term__c> terms = [
                    SELECT Id, Name, 
                           Package_Tier__c, Package_Tier__r.Name,
                           Package_Tier__r.Package__c, Package_Tier__r.Package__r.Name,
                           Package_Tier__r.Package__r.RecordType.Name
                    FROM Package_Term__c
                    WHERE Id = :recordId
                    LIMIT 1
                ];

                if (!terms.isEmpty()) {
                    Package_Term__c term = terms[0];
                    dto.termName = term.Name;
                    
                    if (term.Package_Tier__r != null) {
                        dto.tierName = term.Package_Tier__r.Name;
                        
                        if (term.Package_Tier__r.Package__r != null) {
                            dto.packageName = term.Package_Tier__r.Package__r.Name;
                            dto.packageId = term.Package_Tier__r.Package__c;
                            
                            // Get RecordType from Package
                            SObject packageObj = term.Package_Tier__r.Package__r;
                            SObject rt = packageObj.getSObject('RecordType');
                            if (rt != null) {
                                dto.recordTypeName = (String)rt.get('Name');
                            }
                        }
                    }
                }
            } else {
                // Handle other objects (like Package__c directly)
                String soql = 'SELECT RecordTypeId, RecordType.Name FROM ' + objectApiName +
                              ' WHERE Id = :recordId LIMIT 1';
                SObject sobj = Database.query(soql);

                SObject rt = sobj.getSObject('RecordType');
                if (rt != null) {
                    dto.recordTypeName = (String)rt.get('Name');
                }

                // If it's a Package__c, also get the package name and ID
                if (objectApiName == 'Package__c') {
                    dto.packageId = recordId;
                    Package__c pkg = [SELECT Name FROM Package__c WHERE Id = :recordId LIMIT 1];
                    dto.packageName = pkg.Name;
                }
            }

            return dto;
        } catch (Exception e) {
            // In case of any error, return null so the LWC can handle it gracefully
            return null;
        }
    }

    @AuraEnabled(cacheable=true)
    public static String getPackageName(Id recordId) {
        if (recordId == null) {
            return null;
        }
        try {
            // Determine the sObject type from the Id
            SObjectType sobjectType = recordId.getSObjectType();
            String objectApiName = sobjectType.getDescribe().getName();

            // Handle Package_Term__c - get package name from relationship
            if (objectApiName == 'Package_Term__c') {
                List<Package_Term__c> terms = [
                    SELECT Package_Tier__r.Package__r.Name
                    FROM Package_Term__c
                    WHERE Id = :recordId
                    LIMIT 1
                ];
                if (!terms.isEmpty() && terms[0].Package_Tier__r != null && 
                    terms[0].Package_Tier__r.Package__r != null) {
                    return terms[0].Package_Tier__r.Package__r.Name;
                }
            } else if (objectApiName == 'Package__c') {
                // Handle Package__c directly
                Package__c pkg = [SELECT Name FROM Package__c WHERE Id = :recordId LIMIT 1];
                return pkg.Name;
            }
            
            return null;
        } catch (Exception e) {
            return null;
        }
    }

    public class OptionDTO {
        @AuraEnabled public String Id;
        @AuraEnabled public String Name;
    }

    @AuraEnabled(cacheable=true)
    public static List<OptionDTO> getOptions() {
        try {
            List<Option__c> options = [SELECT Id, Name FROM Option__c ORDER BY Name];
            List<OptionDTO> dtos = new List<OptionDTO>();
            for (Option__c opt : options) {
                OptionDTO dto = new OptionDTO();
                dto.Id = opt.Id;
                dto.Name = opt.Name;
                dtos.add(dto);
            }
            return dtos;
        } catch (Exception e) {
            return new List<OptionDTO>();
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getCategoryPicklistValues() {
        try {
            Schema.DescribeFieldResult fieldResult = Package_Option__c.Category__c.getDescribe();
            List<Schema.PicklistEntry> picklistValues = fieldResult.getPicklistValues();
            List<String> values = new List<String>();
            for (Schema.PicklistEntry entry : picklistValues) {
                values.add(entry.getValue());
            }
            return values;
        } catch (Exception e) {
            return new List<String>();
        }
    }

    public class PackageOptionRowDTO {
        @AuraEnabled public String optionId;
        @AuraEnabled public String category;
        @AuraEnabled public Decimal minimumValue;
        @AuraEnabled public Decimal maximumValue;
        @AuraEnabled public Decimal price;
        @AuraEnabled public String inclusionText;
        @AuraEnabled public String exclusionText;
        @AuraEnabled public String packageTermId;
        
        public PackageOptionRowDTO() {
            // Default constructor for deserialization
        }
    }

    @AuraEnabled
    public static String createPackageOptions(Id recordId, String rowsJson, Boolean isIncluded) {
        List<PackageOptionRowDTO> rows = new List<PackageOptionRowDTO>();
        
        try {
            if (String.isNotBlank(rowsJson)) {
                rows = (List<PackageOptionRowDTO>) JSON.deserialize(rowsJson, List<PackageOptionRowDTO>.class);
            }
        } catch (Exception e) {
            return 'Error deserializing rows: ' + e.getMessage();
        }
        
        if (recordId == null) {
            return 'Error: Record ID is required';
        }
        if (rows == null || rows.isEmpty()) {
            return 'Error: At least one row is required';
        }

        try {
            // Determine the actual Package__c ID and Package_Term__c ID
            Id packageId = recordId;
            Id packageTermId = null;
            SObjectType sobjectType = recordId.getSObjectType();
            String objectApiName = sobjectType.getDescribe().getName();

            // If it's a Package_Term__c, get the Package__c ID from the relationship
            if (objectApiName == 'Package_Term__c') {
                packageTermId = recordId;
                List<Package_Term__c> terms = [
                    SELECT Package_Tier__r.Package__c
                    FROM Package_Term__c
                    WHERE Id = :recordId
                    LIMIT 1
                ];
                if (terms.isEmpty() || terms[0].Package_Tier__r == null || 
                    terms[0].Package_Tier__r.Package__c == null) {
                    return 'Error: Could not find Package from Package Term relationship';
                }
                packageId = terms[0].Package_Tier__r.Package__c;
            }

            List<Package_Option__c> optionsToInsert = new List<Package_Option__c>();
            
            for (Integer i = 0; i < rows.size(); i++) {
                PackageOptionRowDTO row = rows[i];
                
                // Validation
                if (row.optionId == null || String.isBlank(row.optionId)) {
                    return 'Error: Option is required for all rows';
                }
                
                Package_Option__c option = new Package_Option__c();
                option.Option__c = row.optionId;
                
                if (isIncluded != null && isIncluded) {
                    // Included Options - always set Package__c
                    option.Package__c = packageId;
                    option.Selection_Type__c = 'Included';
                    option.Inclusion_Text__c = row.inclusionText;
                    option.Exclusion_Text__c = row.exclusionText;
                } else {
                    // Additional Options
                    if (row.price == null || row.price < 0) {
                        return 'Error: Price must be greater than or equal to 0';
                    }
                    option.Selection_Type__c = 'Optional';
                    option.Price__c = row.price;
                    option.Inclusion_Text__c = row.inclusionText;
                    option.Exclusion_Text__c = row.exclusionText;
                    
                    // If creating from Package_Term__c, set Package_Term__c but NOT Package__c
                    if (packageTermId != null) {
                        // Set Package_Term__c lookup if provided (for Package_Term__c records)
                        if (String.isNotBlank(row.packageTermId)) {
                            option.Package_Term__c = row.packageTermId;
                        } else {
                            // Fallback to the recordId if packageTermId not in row
                            option.Package_Term__c = packageTermId;
                        }
                        // Do NOT set Package__c for Package_Term__c records
                    } else {
                        // Legacy: When creating from Package__c directly, set Package__c
                        option.Package__c = packageId;
                        if (row.minimumValue != null && row.maximumValue != null && row.minimumValue > row.maximumValue) {
                            return 'Error: Minimum Value cannot be greater than Maximum Value';
                        }
                        option.Category__c = row.category;
                        option.Minimum_Value__c = row.minimumValue;
                        option.Maximum_Value__c = row.maximumValue;
                    }
                }
                
                optionsToInsert.add(option);
            }

            insert optionsToInsert;
            return 'Success: Created ' + optionsToInsert.size() + ' package options';
        } catch (Exception e) {
            return 'Error: ' + e.getMessage();
        }
    }
}