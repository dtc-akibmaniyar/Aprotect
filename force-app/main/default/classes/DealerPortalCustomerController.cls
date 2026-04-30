public with sharing class DealerPortalCustomerController {
    
    // Wrapper class for Account details
    public class AccountDetailsWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String firstName { get; set; }
        @AuraEnabled public String lastName { get; set; }
        @AuraEnabled public String accountType { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String personEmail { get; set; }
        @AuraEnabled public String personMobilePhone { get; set; }
        @AuraEnabled public String billingStreet { get; set; }
        @AuraEnabled public String billingCity { get; set; }
        @AuraEnabled public String billingState { get; set; }
        @AuraEnabled public String billingPostalCode { get; set; }
        @AuraEnabled public String billingCountry { get; set; }
        @AuraEnabled public String billingAddress { get; set; }
        @AuraEnabled public String shippingStreet { get; set; }
        @AuraEnabled public String shippingCity { get; set; }
        @AuraEnabled public String shippingState { get; set; }
        @AuraEnabled public String shippingPostalCode { get; set; }
        @AuraEnabled public String shippingCountry { get; set; }
        @AuraEnabled public String licenseNumber { get; set; }
        @AuraEnabled public String licenseProvince { get; set; }
        @AuraEnabled public Date licenseExpiry { get; set; }
        
        // Constructor
        public AccountDetailsWrapper(Account acc) {
            this.id = acc.Id;
            this.name = acc.Name;
            this.firstName = acc.FirstName;
            this.lastName = acc.LastName;
            this.accountType = acc.Type;
            this.phone = acc.Phone;
            this.personEmail = acc.PersonEmail;
            this.personMobilePhone = acc.PersonMobilePhone;
            this.billingStreet = acc.BillingStreet;
            this.billingCity = acc.BillingCity;
            this.billingState = acc.BillingState;
            this.billingPostalCode = acc.BillingPostalCode;
            this.billingCountry = acc.BillingCountry;
            this.shippingStreet = acc.ShippingStreet;
            this.shippingCity = acc.ShippingCity;
            this.shippingState = acc.ShippingState;
            this.shippingPostalCode = acc.ShippingPostalCode;
            this.shippingCountry = acc.ShippingCountry;
            this.licenseNumber = acc.License_Number__c;
            this.licenseProvince = acc.License_Province__c;
            this.licenseExpiry = acc.License_Expiry__c;
            
            // Format billing address for display
            this.billingAddress = formatAddress(
                acc.BillingStreet, 
                acc.BillingCity, 
                acc.BillingState, 
                acc.BillingPostalCode,
                acc.BillingCountry
            );
        }
        
        // Helper method to format address
        private String formatAddress(String street, String city, String state, String postalCode, String country) {
            List<String> addressParts = new List<String>();
            
            if (String.isNotBlank(street)) {
                addressParts.add(street);
            }
            if (String.isNotBlank(city)) {
                addressParts.add(city);
            }
            if (String.isNotBlank(state)) {
                addressParts.add(state);
            }
            if (String.isNotBlank(postalCode)) {
                addressParts.add(postalCode);
            }
            if (String.isNotBlank(country)) {
                addressParts.add(country);
            }
            
            return String.join(addressParts, ', ');
        }
    }
    
    @AuraEnabled
    public static Map<String, Object> getCustomerData(String applicationId) {
        try {
            // Query your customer/application object - adjust fields as needed
            List<Application__c> applications = [
                SELECT Id, Company_Business_Name__c, Business_No_License__c, Company_Province__c, Company_E_Mail_Address__c, Company_Contact_Name__c, Company_Business_Phone__c, Company_Business_ALT_Phone__c, Company_Business_Address__c, Company_Business_City__c, Company_Business_Postal_Code__c, Company_Business_Country__c,
                       Customer_Name__c, Customer_Name__r.FirstName, Customer_Name__r.LastName, 
                       Customer_Name__r.PersonEmail, Customer_Name__r.Phone,
                       Customer_Name__r.BillingStreet, Customer_Name__r.BillingCity, 
                       Customer_Name__r.BillingState, Customer_Name__r.BillingPostalCode, Customer_Name__r.BillingCountry,
                       Co_Buyer__c, Co_Buyer__r.FirstName, Co_Buyer__r.LastName, 
                       Co_Buyer__r.PersonEmail, Co_Buyer__r.Phone,
                       Co_Buyer__r.BillingStreet, Co_Buyer__r.BillingCity,
                       Co_Buyer__r.BillingState, Co_Buyer__r.BillingPostalCode, Co_Buyer__r.BillingCountry,
                       Customer_Name__r.License_Number__c, Customer_Name__r.License_Province__c, 
                       Customer_Name__r.License_Expiry__c, Customer_Name__r.Insurance_Provider__c,
                       Insurance_Provider__c, Policy_Number__c, Customer_Name__r.Policy_Number__c
                FROM Application__c 
                WHERE Id = :applicationId 
                LIMIT 1
            ];
            
            if (!applications.isEmpty()) {
                Application__c app = applications[0];
                return new Map<String, Object>{
                    'firstName' => app.Customer_Name__r?.FirstName,
                    'lastName' => app.Customer_Name__r?.LastName,
                    'email' => app.Customer_Name__r?.PersonEmail,
                    'phone' => app.Customer_Name__r?.Phone,
                    'streetAddress' => app.Customer_Name__r?.BillingStreet,
                    'city' => app.Customer_Name__r?.BillingCity,
                    'province' => app.Customer_Name__r?.BillingState,
                    'postalCode' => app.Customer_Name__r?.BillingPostalCode,
                    'country' => app.Customer_Name__r?.BillingCountry,
                    'selectedCoBuyerAccountId' => app.Co_Buyer__c,
                    'coBuyerFirstName' => app.Co_Buyer__r?.FirstName,
                    'coBuyerLastName' => app.Co_Buyer__r?.LastName,
                    'coBuyerEmail' => app.Co_Buyer__r?.PersonEmail,
                    'coBuyerPhone' => app.Co_Buyer__r?.Phone,
                    'coBuyerStreetAddress' => app.Co_Buyer__r?.BillingStreet,
                    'coBuyerCity' => app.Co_Buyer__r?.BillingCity,
                    'coBuyerProvince' => app.Co_Buyer__r?.BillingState,
                    'coBuyerPostalCode' => app.Co_Buyer__r?.BillingPostalCode,
                    'coBuyerCountry' => app.Co_Buyer__r?.BillingCountry,
                    'licenseNumber' => app.Customer_Name__r?.License_Number__c,
                    'licenseProvince' => app.Customer_Name__r?.License_Province__c,
                    'licenseExpiry' => app.Customer_Name__r?.License_Expiry__c,
                    'companyBusiness' => app.Company_Business_Name__c,
                    'businessNumber' => app.Business_No_License__c,
                    'companyProvince' => app.Company_Province__c,
                    'companyEmail' => app.Company_E_Mail_Address__c,
                    'companyContactName' => app.Company_Contact_Name__c,
                    'companyBusinessPhone' => app.Company_Business_Phone__c,
                    'companyBusinessAltPhone' => app.Company_Business_ALT_Phone__c,
                    'companyBusinessAddress' => app.Company_Business_Address__c,
                    'companyBusinessCity' => app.Company_Business_City__c,
                    'companyBusinessPostalCode' => app.Company_Business_Postal_Code__c,
                    'companyBusinessCountry' => app.Company_Business_Country__c,
                    'insuranceProvider' => app.Customer_Name__r.Insurance_Provider__c,
                    'insurancePolicy' => app.Customer_Name__r.Policy_Number__c
                };
            }
            
            return new Map<String, Object>();
            
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving customer data: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static String saveCustomerData(Map<String, Object> customerData) {
        try {
            String applicationId = (String) customerData.get('applicationId');
            
            // Start savepoint for transaction management
            Savepoint sp = Database.setSavepoint();
            
            try {
                // Query existing application
                List<Application__c> applications = [
                    SELECT Id, Customer_Name__c, Co_Buyer__c, Company_Business_Name__c, Business_No_License__c, Company_Province__c, Company_E_Mail_Address__c, Company_Contact_Name__c, Company_Business_Phone__c, Company_Business_ALT_Phone__c, Company_Business_Address__c, Company_Business_City__c, Company_Business_Postal_Code__c, Company_Business_Country__c
                    FROM Application__c 
                    WHERE Id = :applicationId 
                    LIMIT 1
                ];
                
                Application__c app;
                if (!applications.isEmpty()) {
                    app = applications[0];
                } else {
                    throw new AuraHandledException('Application not found: ' + applicationId);
                }
                
                // Upsert Customer Account
                    Account customerAccount = new Account(
                        Id = app.Customer_Name__c,
                        FirstName = (String) customerData.get('firstName'),
                        LastName = (String) customerData.get('lastName'),
                        PersonEmail = (String) customerData.get('email'),
                        Phone = (String) customerData.get('phone'),
                        BillingStreet = (String) customerData.get('streetAddress'),
                        BillingCity = (String) customerData.get('city'),
                        BillingState = (String) customerData.get('province'),
                        BillingPostalCode = (String) customerData.get('postalCode'),
                        BillingCountry = (String) customerData.get('country'),
                        License_Number__c = (String) customerData.get('licenseNumber'),
                        License_Province__c = (String) customerData.get('licenseProvince'),
                        Insurance_Provider__c = (String) customerData.get('insuranceProvider'),
                		Policy_Number__c = (String) customerData.get('insurancePolicy')
                    );
                    
                    // Handle license expiry date conversion
                    String licenseExpiryStr = (String) customerData.get('licenseExpiry');
                    if (String.isNotBlank(licenseExpiryStr)) {
                        try {
                            customerAccount.License_Expiry__c = Date.valueOf(licenseExpiryStr);
                        } catch (Exception dateEx) {
                            System.debug('Error converting license expiry date: ' + dateEx.getMessage());
                        }
                    }
                if(app.Customer_Name__c == null){
                    customerAccount.RecordTypeId = [Select Id from RecordType where sObjectType = 'Account' and Name = 'Customer Account' limit 1].Id;
                }
                    upsert customerAccount;
                    
                    if(app.Customer_Name__c == null){
                        app.Customer_Name__c = customerAccount.Id;
                    }
                    System.debug('✅ Updated customer account: ' + customerAccount.Id);
                
                
                // Handle Co-buyer Account - Create new Account if co-lessee info provided
                String coBuyerFirstName = (String) customerData.get('coBuyerFirstName');
                String coBuyerLastName = (String) customerData.get('coBuyerLastName');
                String coBuyerEmail = (String) customerData.get('coBuyerEmail');
                String coBuyerPhone = (String) customerData.get('coBuyerPhone');
                String coBuyerStreetAddress = (String) customerData.get('coBuyerStreetAddress');
                String coBuyerCity = (String) customerData.get('coBuyerCity');
                String coBuyerProvince = (String) customerData.get('coBuyerProvince');
                String coBuyerPostalCode = (String) customerData.get('coBuyerPostalCode');
                String coBuyerCountry = (String) customerData.get('coBuyerCountry');
                
                // Create new co-lessee Account if first or last name is provided
                if (String.isNotBlank(coBuyerFirstName) || String.isNotBlank(coBuyerLastName)) {
                    Account coBuyerAccount = new Account(
                        Id = app.Co_Buyer__c,
                        FirstName = String.isNotBlank(coBuyerFirstName) ? coBuyerFirstName : '',
                        LastName = String.isNotBlank(coBuyerLastName) ? coBuyerLastName : 'Co-Lessee',
                        PersonEmail = coBuyerEmail,
                        Phone = coBuyerPhone,
                        BillingStreet = coBuyerStreetAddress,
                        BillingCity = coBuyerCity,
                        BillingState = coBuyerProvince,
                        BillingPostalCode = coBuyerPostalCode,
                        BillingCountry = coBuyerCountry
                    );
                    
                    // Set record type to 'Customer Account' for person accounts
                    if(app.Co_Buyer__c == null){
                        coBuyerAccount.RecordTypeId = [Select Id from RecordType where sObjectType = 'Account' and Name = 'Customer Account' limit 1].Id;
                    }
                    
                    upsert coBuyerAccount;
                    app.Co_Buyer__c = coBuyerAccount.Id;
                    System.debug('✅ Created/updated co-lessee account: ' + coBuyerAccount.Id);
                }
                
                // Update company/business information on Application
                app.Company_Business_Name__c = (String) customerData.get('companyBusiness');
                app.Business_No_License__c = (String) customerData.get('businessNumber');
                app.Company_Province__c = (String) customerData.get('companyProvince');
                app.Company_E_Mail_Address__c = (String) customerData.get('companyEmail');
                app.Company_Contact_Name__c = (String) customerData.get('companyContactName');
                app.Company_Business_Phone__c = (String) customerData.get('companyBusinessPhone');
                app.Company_Business_ALT_Phone__c = (String) customerData.get('companyBusinessAltPhone');
                app.Company_Business_Address__c = (String) customerData.get('companyBusinessAddress');
                app.Company_Business_City__c = (String) customerData.get('companyBusinessCity');
                app.Company_Business_Postal_Code__c = (String) customerData.get('companyBusinessPostalCode');
                app.Company_Business_Country__c = (String) customerData.get('companyBusinessCountry');
                app.Company_E_Mail_Address__c = (String) customerData.get('companyEmail');
                
                update app;
                System.debug('✅ Updated application: ' + app.Id);
                
                return 'Success';
                
            } catch (Exception e) {
                Database.rollback(sp);
                throw e;
            }
            
        } catch (Exception e) {
            throw new AuraHandledException('Error saving customer data: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static AccountDetailsWrapper getAccountDetails(String accountId) {
        try {
            // Query account details including person account fields
            List<Account> accounts = [
                SELECT Id, Name, FirstName, LastName, Type, Phone, 
                       PersonEmail, PersonMobilePhone,
                       BillingStreet, BillingCity, BillingState, 
                       BillingPostalCode, BillingCountry,
                       ShippingStreet, ShippingCity, ShippingState,
                       ShippingPostalCode, ShippingCountry,
                       License_Number__c, License_Province__c, License_Expiry__c
                FROM Account 
                WHERE Id = :accountId 
                LIMIT 1
            ];
            
            if (!accounts.isEmpty()) {
                Account acc = accounts[0];
                AccountDetailsWrapper wrapper = new AccountDetailsWrapper(acc);
                
                System.debug('✅ Retrieved account details: ' + wrapper.name);
                return wrapper;
            }
            
            return null;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving account details: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static Account createPersonAccount(Map<String, Object> accountData) {
        try {
            // Create new person account for co-buyer if needed
            Account newAccount = new Account(
                FirstName = (String) accountData.get('firstName'),
                LastName = (String) accountData.get('lastName'),
                PersonEmail = (String) accountData.get('email'),
                Phone = (String) accountData.get('phone'),
                RecordTypeId = getPersonAccountRecordTypeId()
            );
            
            insert newAccount;
            System.debug('✅ Created new person account: ' + newAccount.Id);
            
            return newAccount;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error creating person account: ' + e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Account> searchAccounts(String searchTerm) {
        try {
            String searchKey = '%' + searchTerm + '%';
            
            List<Account> accounts = [
                SELECT Id, Name, FirstName, LastName, PersonEmail, Phone, Type,
                       BillingStreet, BillingCity, BillingState, BillingPostalCode
                FROM Account 
                WHERE (Name LIKE :searchKey 
                       OR FirstName LIKE :searchKey 
                       OR LastName LIKE :searchKey 
                       OR PersonEmail LIKE :searchKey
                       OR Phone LIKE :searchKey)
                AND IsPersonAccount = true
                ORDER BY Name
                LIMIT 10
            ];
            
            return accounts;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error searching accounts: ' + e.getMessage());
        }
    }
    
    // Helper method to get Person Account Record Type ID
    private static Id getPersonAccountRecordTypeId() {
        try {
            RecordType personAccountRT = [
                SELECT Id 
                FROM RecordType 
                WHERE SObjectType = 'Account' 
                AND DeveloperName = 'PersonAccount' 
                LIMIT 1
            ];
            return personAccountRT.Id;
        } catch (Exception e) {
            // Return null if Person Account record type doesn't exist
            System.debug('Person Account record type not found: ' + e.getMessage());
            return null;
        }
    }
    
    // Utility method to validate email format
    private static Boolean isValidEmail(String email) {
        String emailRegex = '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$';
        Pattern emailPattern = Pattern.compile(emailRegex);
        return emailPattern.matcher(email).matches();
    }
}