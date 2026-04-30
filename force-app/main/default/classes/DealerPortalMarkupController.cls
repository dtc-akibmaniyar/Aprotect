public without sharing class DealerPortalMarkupController {

    // ===== Shared helpers =====
    private static String getCurrentDealerId() {
        String currentUserId = UserInfo.getUserId();
        List<User> currentUser = [
            SELECT Id, ContactId, Contact.AccountId
            FROM User
            WHERE Id = :currentUserId
            LIMIT 1
        ];
        
        if (!currentUser.isEmpty() && currentUser[0].ContactId != null) {
            return currentUser[0].Contact.AccountId;
        }
        return null;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<DealerPackageDTO> getDealerPackagesHierarchy() {
        try {
            String dealerId = getCurrentDealerId();
            if (String.isBlank(dealerId)) {
                return new List<DealerPackageDTO>();
            }
            
            List<Dealer_Package__c> packages = [
                SELECT Id, Name, Package__r.Name, Dealer__c, Dealer__r.Name, RecordType.Name,
                    (SELECT Id, Name,
                            Net_Cost__c, Markup__c, Markup_Type__c,
                            Dealer_Package_Tier__c,
                            Dealer_Package_Tier__r.Name, Dealer_Package_Tier__r.Minimum__c,
                            Dealer_Package_Tier__r.Maximum__c
                     FROM Dealer_Package_Terms__r
                     ORDER BY Dealer_Package_Tier__c, Name)
                FROM Dealer_Package__c
                WHERE Dealer__c = :dealerId
                ORDER BY RecordType.Name, Package__r.Name, Name
            ];
            
            List<DealerPackageDTO> dtos = new List<DealerPackageDTO>();
            
            for (Dealer_Package__c pkg : packages) {
                DealerPackageDTO dto = new DealerPackageDTO();
                dto.Id = pkg.Id;
                dto.Name = pkg.Name;
                dto.PackageName = pkg.Name;
                dto.recordType = pkg.RecordType != null ? pkg.RecordType.Name : null;
                dto.tiers = new List<DealerPackageTierDTO>();
                dto.terms = new List<DealerPackageTermDTO>();
                
                Map<Id, DealerPackageTierDTO> tierIdToDto = new Map<Id, DealerPackageTierDTO>();
                
                if (pkg.Dealer_Package_Terms__r != null) {
                    for (Dealer_Package_Term__c term : pkg.Dealer_Package_Terms__r) {
                        DealerPackageTermDTO termDTO = createTermDTO(term);
                        dto.terms.add(termDTO);
                        
                        if (term.Dealer_Package_Tier__c != null) {
                            if (!tierIdToDto.containsKey(term.Dealer_Package_Tier__c)) {
                                DealerPackageTierDTO tierDTO = new DealerPackageTierDTO();
                                tierDTO.Id = term.Dealer_Package_Tier__c;
                                
                                if (term.Dealer_Package_Tier__r != null) {
                                    tierDTO.Name = term.Dealer_Package_Tier__r.Name;
                                    tierDTO.mileageRestrictionStart = term.Dealer_Package_Tier__r.Minimum__c;
                                    tierDTO.mileageRestrictionEnd = term.Dealer_Package_Tier__r.Maximum__c;
                                }
                                
                                tierDTO.terms = new List<DealerPackageTermDTO>();
                                tierIdToDto.put(term.Dealer_Package_Tier__c, tierDTO);
                                dto.tiers.add(tierDTO);
                            }
                            
                            tierIdToDto.get(term.Dealer_Package_Tier__c).terms.add(termDTO);
                        }
                    }
                }
                
                dtos.add(dto);
            }
            
            return dtos;
        } catch (Exception e) {
            return new List<DealerPackageDTO>();
        }
    }
    
    public class DealerPackageDTO {
        @AuraEnabled public String Id;
        @AuraEnabled public String Name;
        @AuraEnabled public String PackageName;
        @AuraEnabled public String recordType;
        @AuraEnabled public List<DealerPackageTierDTO> tiers;
        @AuraEnabled public List<DealerPackageTermDTO> terms;
        
        public DealerPackageDTO() {}
    }
    
    public class DealerPackageTierDTO {
        @AuraEnabled public String Id;
        @AuraEnabled public String Name;
        @AuraEnabled public Decimal mileageRestrictionStart;
        @AuraEnabled public Decimal mileageRestrictionEnd;
        @AuraEnabled public List<DealerPackageTermDTO> terms;
        
        public DealerPackageTierDTO() {}
    }
    
    public class DealerPackageTermDTO {
        @AuraEnabled public String Id;
        @AuraEnabled public String Name;
        @AuraEnabled public String termName;
        @AuraEnabled public Decimal netCost;
        @AuraEnabled public Decimal markup;
        @AuraEnabled public String markupType;
        @AuraEnabled public Decimal totalPrice;
        @AuraEnabled public String tierId;
        
        public DealerPackageTermDTO() {}
    }
    
    private static DealerPackageTermDTO createTermDTO(Dealer_Package_Term__c term) {
        DealerPackageTermDTO termDTO = new DealerPackageTermDTO();
        termDTO.Id = term.Id;
        termDTO.Name = term.Name;
        termDTO.termName = term.Name;
        termDTO.netCost = term.Net_Cost__c != null ? term.Net_Cost__c : 0;
        termDTO.markup = term.Markup__c != null ? term.Markup__c : 0;
        termDTO.markupType = term.Markup_Type__c != null ? term.Markup_Type__c : '';
        termDTO.tierId = term.Dealer_Package_Tier__c;
        
        Decimal base = termDTO.netCost != null ? termDTO.netCost : 0;
        Decimal mark = termDTO.markup != null ? termDTO.markup : 0;
        if (termDTO.markupType == '%') {
            termDTO.totalPrice = base + ((base * mark) / 100);
        } else if (termDTO.markupType == '$') {
            termDTO.totalPrice = base + mark;
        } else {
            termDTO.totalPrice = base;
        }
        
        return termDTO;
    }

    // =====================================================================
    // ===== Markup APIs (moved from DealerPortalController) =====
    // =====================================================================

    // ----- DTOs for term markup UI -----
    public class AdminDealerPackageDTO {
        @AuraEnabled public String Id;
        @AuraEnabled public String Name;
        @AuraEnabled public String PackageName;
        @AuraEnabled public String recordType;
        @AuraEnabled public List<AdminDealerPackageTermDTO> terms; // flat list
        @AuraEnabled public List<AdminDealerPackageTierDTO> tiers; // tiered list
        
        public AdminDealerPackageDTO() {}
    }
    
    public class AdminDealerPackageTierDTO {
        @AuraEnabled public String Id;
        @AuraEnabled public String Name;
        @AuraEnabled public Decimal mileageRestrictionStart;
        @AuraEnabled public Decimal mileageRestrictionEnd;
        @AuraEnabled public List<AdminDealerPackageTermDTO> terms;
        
        public AdminDealerPackageTierDTO() {}
    }
    
    public class AdminDealerPackageTermDTO {
        @AuraEnabled public String Id;
        @AuraEnabled public String Name;
        @AuraEnabled public String termName;
        @AuraEnabled public Decimal netCost;
        @AuraEnabled public Decimal markup;
        @AuraEnabled public String markupType;
        @AuraEnabled public Decimal totalPrice;
        @AuraEnabled public String tierId;
        
        public AdminDealerPackageTermDTO() {}
    }
    
    @AuraEnabled(cacheable=true)
    public static List<AdminDealerPackageDTO> getAdminDealerPackages() {
        try {
            String dealerId = getCurrentDealerId();
            if (String.isBlank(dealerId)) return new List<AdminDealerPackageDTO>();
            
            List<Dealer_Package__c> packages = [
                SELECT Id, Name, Package__r.Name, Dealer__c, Dealer__r.Name, RecordType.Name,
                    (SELECT Id, Name,
                            Net_Cost__c, Markup__c, Markup_Type__c,
                            Dealer_Package_Tier__c,
                            Dealer_Package_Tier__r.Name, Dealer_Package_Tier__r.Minimum__c,
                            Dealer_Package_Tier__r.Maximum__c
                     FROM Dealer_Package_Terms__r
                     ORDER BY Dealer_Package_Tier__c, Name)
                FROM Dealer_Package__c
                WHERE Dealer__c = :dealerId
                ORDER BY RecordType.Name, Package__r.Name
            ];
            
            List<AdminDealerPackageDTO> packageDTOs = new List<AdminDealerPackageDTO>();
            
            for (Dealer_Package__c pkg : packages) {
                AdminDealerPackageDTO dto = new AdminDealerPackageDTO();
                dto.Id = pkg.Id;
                dto.Name = pkg.Name;
                dto.PackageName = pkg.Name;
                dto.recordType = pkg.RecordType != null ? pkg.RecordType.Name : null;
                
                Map<Id, List<Dealer_Package_Term__c>> termsByTierId = new Map<Id, List<Dealer_Package_Term__c>>();
                Map<Id, Dealer_Package_Tier__c> tierMap = new Map<Id, Dealer_Package_Tier__c>();
                List<Dealer_Package_Term__c> termsWithoutTier = new List<Dealer_Package_Term__c>();
                
                if (pkg.Dealer_Package_Terms__r != null) {
                    for (Dealer_Package_Term__c term : pkg.Dealer_Package_Terms__r) {
                        if (term.Dealer_Package_Tier__c != null) {
                            if (!termsByTierId.containsKey(term.Dealer_Package_Tier__c)) {
                                termsByTierId.put(term.Dealer_Package_Tier__c, new List<Dealer_Package_Term__c>());
                            }
                            termsByTierId.get(term.Dealer_Package_Tier__c).add(term);
                            
                            if (term.Dealer_Package_Tier__r != null) {
                                tierMap.put(term.Dealer_Package_Tier__c, term.Dealer_Package_Tier__r);
                            }
                        } else {
                            termsWithoutTier.add(term);
                        }
                    }
                }
                
                List<AdminDealerPackageTierDTO> tierDTOs = new List<AdminDealerPackageTierDTO>();
                List<AdminDealerPackageTermDTO> allTermDTOs = new List<AdminDealerPackageTermDTO>();
                
                for (Id tierId : termsByTierId.keySet()) {
                    AdminDealerPackageTierDTO tierDTO = new AdminDealerPackageTierDTO();
                    tierDTO.Id = String.valueOf(tierId);
                    
                    if (tierMap.containsKey(tierId)) {
                        Dealer_Package_Tier__c tier = tierMap.get(tierId);
                        tierDTO.Name = tier.Name;
                        tierDTO.mileageRestrictionStart = tier.Minimum__c;
                        tierDTO.mileageRestrictionEnd = tier.Maximum__c;
                    }
                    
                    List<AdminDealerPackageTermDTO> tierTermDTOs = new List<AdminDealerPackageTermDTO>();
                    for (Dealer_Package_Term__c term : termsByTierId.get(tierId)) {
                        AdminDealerPackageTermDTO termDTO = createAdminTermDTO(term);
                        termDTO.tierId = String.valueOf(tierId);
                        tierTermDTOs.add(termDTO);
                        allTermDTOs.add(termDTO);
                    }
                    tierDTO.terms = tierTermDTOs;
                    tierDTOs.add(tierDTO);
                }
                
                for (Dealer_Package_Term__c term : termsWithoutTier) {
                    AdminDealerPackageTermDTO termDTO = createAdminTermDTO(term);
                    allTermDTOs.add(termDTO);
                }
                
                dto.tiers = tierDTOs;
                dto.terms = allTermDTOs;
                packageDTOs.add(dto);
            }
            
            return packageDTOs;
        } catch (Exception e) {
            return new List<AdminDealerPackageDTO>();
        }
    }
    
    private static AdminDealerPackageTermDTO createAdminTermDTO(Dealer_Package_Term__c term) {
        AdminDealerPackageTermDTO termDTO = new AdminDealerPackageTermDTO();
        termDTO.Id = term.Id;
        termDTO.Name = term.Name;
        termDTO.termName = term.Name;
        termDTO.netCost = term.Net_Cost__c != null ? term.Net_Cost__c : 0;
        termDTO.markup = term.Markup__c != null ? term.Markup__c : 0;
        termDTO.markupType = term.Markup_Type__c != null ? term.Markup_Type__c : '';
        
        Decimal base = termDTO.netCost != null ? termDTO.netCost : 0;
        Decimal mark = termDTO.markup != null ? termDTO.markup : 0;
        if (termDTO.markupType == '%') {
            termDTO.totalPrice = base + ((base * mark) / 100);
        } else if (termDTO.markupType == '$') {
            termDTO.totalPrice = base + mark;
        } else {
            termDTO.totalPrice = base;
        }
        return termDTO;
    }
    
    // ----- Term markup update APIs -----
    @AuraEnabled
    public static String updateTermMarkup(String termId, Decimal markup, String markupType) {
        try {
            Dealer_Package_Term__c term = [
                SELECT Id, Markup__c, Markup_Type__c
                FROM Dealer_Package_Term__c
                WHERE Id = :termId
                LIMIT 1
            ];
            
            term.Markup__c = markup;
            term.Markup_Type__c = markupType != null ? markupType : '';
            update term;
            return 'Success';
        } catch (Exception e) {
            return 'Error: ' + e.getMessage();
        }
    }
    
    @AuraEnabled
    public static String updateAllTermMarkups(Decimal defaultMarkup, String defaultMarkupType) {
        try {
            if (defaultMarkup == null || defaultMarkup < 0) {
                return 'Error: Default markup must be a positive number';
            }
            
            String dealerId = getCurrentDealerId();
            if (String.isBlank(dealerId)) return 'Error: No dealer context found';
            
            List<Dealer_Package_Term__c> terms = [
                SELECT Id, Markup__c, Markup_Type__c
                FROM Dealer_Package_Term__c
                WHERE Dealer_Package__r.Dealer__c = :dealerId
            ];
            
            if (terms.isEmpty()) return 'No terms found to update';
            
            String typeToSet = defaultMarkupType != null ? defaultMarkupType : '$';
            for (Dealer_Package_Term__c term : terms) {
                term.Markup__c = defaultMarkup;
                term.Markup_Type__c = typeToSet;
            }
            
            update terms;
            return 'Success: Updated ' + terms.size() + ' terms';
        } catch (Exception e) {
            return 'Error: ' + e.getMessage();
        }
    }
    
    @AuraEnabled
    public static String updateSpecificTermMarkups(Decimal defaultMarkup, String defaultMarkupType, List<String> termIds) {
        try {
            if (defaultMarkup == null || defaultMarkup < 0) {
                return 'Error: Markup must be a positive number';
            }
            if (termIds == null || termIds.isEmpty()) {
                return 'Error: No term IDs provided';
            }
            
            List<Dealer_Package_Term__c> terms = [
                SELECT Id, Markup__c, Markup_Type__c
                FROM Dealer_Package_Term__c
                WHERE Id IN :termIds
            ];
            
            String typeToSet = defaultMarkupType != null ? defaultMarkupType : '$';
            for (Dealer_Package_Term__c term : terms) {
                term.Markup__c = defaultMarkup;
                term.Markup_Type__c = typeToSet;
            }
            
            update terms;
            return 'Success: Updated ' + terms.size() + ' specific term markups';
        } catch (Exception e) {
            return 'Error: ' + e.getMessage();
        }
    }
    
    // ----- DTOs for options markup UI -----
    private static Decimal calculateTotalPrice(Decimal netCost, Decimal markup, String markupType) {
        Decimal base = netCost != null ? netCost : 0;
        Decimal mark = markup != null ? markup : 0;
        
        if (markupType == '%') return base + (base * mark / 100);
        if (markupType == '$') return base + mark;
        return base;
    }
    
    public class AdminAdditionalOptionDTO {
        @AuraEnabled public String Id;
        @AuraEnabled public String Name;
        @AuraEnabled public String optionName;
        @AuraEnabled public Decimal netCost;
        @AuraEnabled public Decimal dealerMarkup;
        @AuraEnabled public String markupType;
        @AuraEnabled public Decimal totalPrice;
        
        public AdminAdditionalOptionDTO() {}
    }
    
    public class TermWithOptionsDTO {
        @AuraEnabled public String Id;
        @AuraEnabled public String Name;
        @AuraEnabled public String termName;
        @AuraEnabled public List<AdminAdditionalOptionDTO> options;
        
        public TermWithOptionsDTO() {}
    }
    
    public class CategoryWithOptionsDTO {
        @AuraEnabled public String categoryName;
        @AuraEnabled public List<AdminAdditionalOptionDTO> options;
        @AuraEnabled public Boolean isVisible;
        @AuraEnabled public String toggleIcon;
        
        public CategoryWithOptionsDTO() {}
    }
    
    public class PackageWithOptionsDTO {
        @AuraEnabled public String Id;
        @AuraEnabled public String Name;
        @AuraEnabled public String PackageName;
        @AuraEnabled public String recordType;
        @AuraEnabled public List<TermWithOptionsDTO> terms;
        @AuraEnabled public List<CategoryWithOptionsDTO> categories;
        @AuraEnabled public String debugInfo;
        
        public PackageWithOptionsDTO() {}
    }
    
    @AuraEnabled
    public static List<PackageWithOptionsDTO> getAdminDealerPackageOptions(String timestamp) {
        try {
            String dealerId = getCurrentDealerId();
            if (String.isBlank(dealerId)) return new List<PackageWithOptionsDTO>();
            
            // NOTE: Salesforce SOQL does not allow subqueries more than 1 level deep.
            // We therefore query Packages, Terms, and Options separately and stitch them together.
            List<Dealer_Package__c> dealerPackages = [
                SELECT Id, Name, Package__r.Name, Dealer__c, Dealer__r.Name, RecordType.Name, RecordType.DeveloperName,
                    (SELECT Id, Name, Option__r.Name, Net_Cost__c, Dealer_Markup__c, Markup_Type__c, Category__c, Selection_Type__c, Dealer_Package_Term__c
                     FROM Dealer_Included_Options__r
                     WHERE Selection_Type__c = 'Optional' AND Dealer_Package_Term__c = null)
                FROM Dealer_Package__c
                WHERE Dealer__c = :dealerId
                AND (RecordType.Name = 'Extended Limited Warranty' OR RecordType.DeveloperName = 'Total_Loss_Coverage' OR RecordType.Name LIKE '%Total%')
                ORDER BY RecordType.Name, Package__r.Name
            ];
            
            Set<Id> dealerPackageIds = new Set<Id>();
            for (Dealer_Package__c pkg : dealerPackages) {
                dealerPackageIds.add(pkg.Id);
            }
            
            // Query terms for all packages
            Map<Id, List<Dealer_Package_Term__c>> termsByPackageId = new Map<Id, List<Dealer_Package_Term__c>>();
            Set<Id> dealerPackageTermIds = new Set<Id>();
            if (!dealerPackageIds.isEmpty()) {
                List<Dealer_Package_Term__c> terms = [
                    SELECT Id, Name, Dealer_Package__c
                    FROM Dealer_Package_Term__c
                    WHERE Dealer_Package__c IN :dealerPackageIds
                    ORDER BY Dealer_Package__c, Name
                ];
                
                for (Dealer_Package_Term__c term : terms) {
                    dealerPackageTermIds.add(term.Id);
                    if (!termsByPackageId.containsKey(term.Dealer_Package__c)) {
                        termsByPackageId.put(term.Dealer_Package__c, new List<Dealer_Package_Term__c>());
                    }
                    termsByPackageId.get(term.Dealer_Package__c).add(term);
                }
            }
            
            // Query optional options for terms
            Map<Id, List<Dealer_Package_Option__c>> optionsByTermId = new Map<Id, List<Dealer_Package_Option__c>>();
            if (!dealerPackageTermIds.isEmpty()) {
                List<Dealer_Package_Option__c> termOptions = [
                    SELECT Id, Name, Dealer_Package_Term__c, Option__r.Name,
                           Net_Cost__c, Dealer_Markup__c, Markup_Type__c, Category__c
                    FROM Dealer_Package_Option__c
                    WHERE Selection_Type__c = 'Optional'
                    AND Dealer_Package_Term__c IN :dealerPackageTermIds
                    ORDER BY Option__r.Name
                ];
                
                for (Dealer_Package_Option__c opt : termOptions) {
                    if (opt.Dealer_Package_Term__c == null) continue;
                    if (!optionsByTermId.containsKey(opt.Dealer_Package_Term__c)) {
                        optionsByTermId.put(opt.Dealer_Package_Term__c, new List<Dealer_Package_Option__c>());
                    }
                    optionsByTermId.get(opt.Dealer_Package_Term__c).add(opt);
                }
            }
            
            List<PackageWithOptionsDTO> results = new List<PackageWithOptionsDTO>();
            
            for (Dealer_Package__c pkg : dealerPackages) {
                PackageWithOptionsDTO packageDTO = new PackageWithOptionsDTO();
                packageDTO.Id = pkg.Id;
                packageDTO.Name = pkg.Name;
                packageDTO.PackageName = pkg.Name;
                packageDTO.recordType = pkg.RecordType != null ? pkg.RecordType.Name : null;
                packageDTO.terms = new List<TermWithOptionsDTO>();
                packageDTO.categories = new List<CategoryWithOptionsDTO>();
                
                Boolean isTotalLoss = (pkg.RecordType != null) && (
                    (pkg.RecordType.DeveloperName == 'Total_Loss_Coverage') ||
                    (pkg.RecordType.Name != null && pkg.RecordType.Name.contains('Total'))
                );
                
                // Terms with optional options (primarily used for Extended Limited Warranty)
                List<Dealer_Package_Term__c> pkgTerms = termsByPackageId.get(pkg.Id);
                if (pkgTerms != null) {
                    for (Dealer_Package_Term__c term : pkgTerms) {
                        List<Dealer_Package_Option__c> termOpts = optionsByTermId.get(term.Id);
                        if (termOpts == null || termOpts.isEmpty()) continue;
                        
                        TermWithOptionsDTO termDTO = new TermWithOptionsDTO();
                        termDTO.Id = term.Id;
                        termDTO.Name = term.Name;
                        termDTO.termName = term.Name;
                        termDTO.options = new List<AdminAdditionalOptionDTO>();
                        
                        for (Dealer_Package_Option__c option : termOpts) {
                            AdminAdditionalOptionDTO optionDTO = new AdminAdditionalOptionDTO();
                            optionDTO.Id = option.Id;
                            optionDTO.Name = option.Name;
                            optionDTO.optionName = option.Option__r != null ? option.Option__r.Name : option.Name;
                            optionDTO.netCost = option.Net_Cost__c != null ? option.Net_Cost__c : 0;
                            optionDTO.dealerMarkup = option.Dealer_Markup__c != null ? option.Dealer_Markup__c : 0;
                            optionDTO.markupType = option.Markup_Type__c != null ? option.Markup_Type__c : '';
                            optionDTO.totalPrice = calculateTotalPrice(optionDTO.netCost, optionDTO.dealerMarkup, optionDTO.markupType);
                            termDTO.options.add(optionDTO);
                        }
                        
                        packageDTO.terms.add(termDTO);
                    }
                }
                
                // Total Loss: categories are derived from direct options
                if (isTotalLoss && pkg.Dealer_Included_Options__r != null && !pkg.Dealer_Included_Options__r.isEmpty()) {
                    Map<String, List<Dealer_Package_Option__c>> optionsByCategory = new Map<String, List<Dealer_Package_Option__c>>();
                    
                    for (Dealer_Package_Option__c option : pkg.Dealer_Included_Options__r) {
                        String category = String.isNotBlank(option.Category__c) ? option.Category__c : 'Uncategorized';
                        if (!optionsByCategory.containsKey(category)) optionsByCategory.put(category, new List<Dealer_Package_Option__c>());
                        optionsByCategory.get(category).add(option);
                    }
                    
                    for (String categoryName : optionsByCategory.keySet()) {
                        CategoryWithOptionsDTO categoryDTO = new CategoryWithOptionsDTO();
                        categoryDTO.categoryName = categoryName;
                        categoryDTO.options = new List<AdminAdditionalOptionDTO>();
                        categoryDTO.isVisible = false;
                        categoryDTO.toggleIcon = 'utility:chevronright';
                        
                        for (Dealer_Package_Option__c option : optionsByCategory.get(categoryName)) {
                            AdminAdditionalOptionDTO optionDTO = new AdminAdditionalOptionDTO();
                            optionDTO.Id = option.Id;
                            optionDTO.Name = option.Name;
                            optionDTO.optionName = option.Option__r != null ? option.Option__r.Name : option.Name;
                            optionDTO.netCost = option.Net_Cost__c != null ? option.Net_Cost__c : 0;
                            optionDTO.dealerMarkup = option.Dealer_Markup__c != null ? option.Dealer_Markup__c : 0;
                            optionDTO.markupType = option.Markup_Type__c != null ? option.Markup_Type__c : '';
                            optionDTO.totalPrice = calculateTotalPrice(optionDTO.netCost, optionDTO.dealerMarkup, optionDTO.markupType);
                            categoryDTO.options.add(optionDTO);
                        }
                        
                        packageDTO.categories.add(categoryDTO);
                    }
                }
                
                results.add(packageDTO);
            }
            
            return results;
        } catch (Exception e) {
            return new List<PackageWithOptionsDTO>();
        }
    }
    
    // ----- Option markup update APIs -----
    @AuraEnabled
    public static String updateOptionMarkup(String optionId, Decimal markup, String markupType) {
        try {
            List<Dealer_Package_Option__c> options = [
                SELECT Id, Dealer_Markup__c, Markup_Type__c
                FROM Dealer_Package_Option__c
                WHERE Id = :optionId AND Selection_Type__c = 'Optional'
                LIMIT 1
            ];
            
            if (options.isEmpty()) return 'Error: Option not found or not optional';
            
            Dealer_Package_Option__c option = options[0];
            option.Dealer_Markup__c = markup;
            option.Markup_Type__c = markupType;
            update option;
            
            return 'Success';
        } catch (Exception e) {
            return 'Error: ' + e.getMessage();
        }
    }
    
    @AuraEnabled
    public static String updateAllOptionMarkups(Decimal defaultMarkup, String defaultMarkupType) {
        try {
            if (defaultMarkup == null || defaultMarkup < 0) {
                return 'Error: Default markup must be a positive number';
            }
            
            String dealerId = getCurrentDealerId();
            if (String.isBlank(dealerId)) return 'Error: No dealer context found';
            
            // Avoid multi-hop relationship filters (not allowed in SOQL for this context).
            // Gather package + term IDs first, then filter options by those IDs.
            List<Dealer_Package__c> dealerPackages = [
                SELECT Id
                FROM Dealer_Package__c
                WHERE Dealer__c = :dealerId
            ];
            Set<Id> packageIds = new Set<Id>();
            for (Dealer_Package__c pkg : dealerPackages) packageIds.add(pkg.Id);
            
            Set<Id> termIds = new Set<Id>();
            if (!packageIds.isEmpty()) {
                for (Dealer_Package_Term__c term : [
                    SELECT Id
                    FROM Dealer_Package_Term__c
                    WHERE Dealer_Package__c IN :packageIds
                ]) {
                    termIds.add(term.Id);
                }
            }
            
            if (packageIds.isEmpty() && termIds.isEmpty()) {
                return 'Error: No dealer packages found';
            }
            
            List<Dealer_Package_Option__c> options = [
                SELECT Id, Dealer_Markup__c, Markup_Type__c
                FROM Dealer_Package_Option__c
                WHERE Selection_Type__c = 'Optional'
                AND (
                    Dealer_Package__c IN :packageIds
                    OR Dealer_Package_Term__c IN :termIds
                )
            ];
            
            if (options.isEmpty()) return 'Error: No optional options found';
            
            for (Dealer_Package_Option__c option : options) {
                option.Dealer_Markup__c = defaultMarkup;
                option.Markup_Type__c = defaultMarkupType;
            }
            
            update options;
            return 'Success: Updated ' + options.size() + ' option markups';
        } catch (Exception e) {
            return 'Error: ' + e.getMessage();
        }
    }
    
    @AuraEnabled
    public static String updateSpecificOptionMarkups(Decimal defaultMarkup, String defaultMarkupType, List<String> optionIds) {
        try {
            if (defaultMarkup == null || defaultMarkup < 0) {
                return 'Error: Markup must be a positive number';
            }
            if (optionIds == null || optionIds.isEmpty()) {
                return 'Error: No option IDs provided';
            }
            
            List<Dealer_Package_Option__c> options = [
                SELECT Id, Dealer_Markup__c, Markup_Type__c
                FROM Dealer_Package_Option__c
                WHERE Id IN :optionIds AND Selection_Type__c = 'Optional'
            ];
            
            for (Dealer_Package_Option__c option : options) {
                option.Dealer_Markup__c = defaultMarkup;
                option.Markup_Type__c = defaultMarkupType;
            }
            
            update options;
            return 'Success: Updated ' + options.size() + ' specific option markups';
        } catch (Exception e) {
            return 'Error: ' + e.getMessage();
        }
    }
}