/**
 * DealerPortalCustomerControllerTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Covers DealerPortalCustomerController (with sharing):
 *
 *   getCustomerData(String applicationId)
 *     • applicationId yields no Application → returns empty Map
 *     • applicationId found              → returns Map with application fields
 *
 *   saveCustomerData(Map<String, Object> customerData)
 *     • applicationId not found          → throws AuraHandledException
 *     • app.Customer_Name__c == null     → creates new Customer Account
 *     • app.Customer_Name__c != null     → upserts existing account, returns 'Success'
 *     • coBuyerFirstName provided        → creates Co-Buyer Account
 *     • licenseExpiry string provided    → Date.valueOf converts and sets on account
 *
 *   getAccountDetails(String accountId)
 *     • account found with billing addr  → returns AccountDetailsWrapper with
 *                                          formatted billingAddress string
 *     • account not found                → returns null
 *
 *   createPersonAccount(Map<String, Object> accountData)
 *     • valid data                       → inserts Account, returns it
 *
 *   searchAccounts(String searchTerm)
 *     • term matches a person account    → returns non-empty list
 *     • term matches nothing             → returns empty list
 *
 * Test strategy:
 *   ✔ @isTest(SeeAllData=false)
 *   ✔ @TestSetup for shared Dealer + Application
 *   ✔ All SObject creation via TestDataFactory
 *   ✔ customerData / accountData Maps are not SObjects — created inline in tests
 *   ✔ System.assert* with descriptive messages on every assertion
 */
@isTest(SeeAllData=false)
private class DealerPortalCustomerControllerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // @TestSetup — shared Dealer Account + Application (no customer yet)
    // ─────────────────────────────────────────────────────────────────────────

    @TestSetup
    static void setup() {
        Account dealer = TestDataFactory.createDealer(true);
        TestDataFactory.createApplication(dealer.Id, true);
    }

    // ── Private query helpers ─────────────────────────────────────────────────

    private static Account getDealer() {
        return [SELECT Id FROM Account
                WHERE RecordType.DeveloperName = 'Dealer_Account' LIMIT 1];
    }

    private static Application__c getApp() {
        return [SELECT Id, Customer_Name__c, Co_Buyer__c FROM Application__c LIMIT 1];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getCustomerData
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Non-matching applicationId (passing the dealer Account Id) → SOQL finds
     * no Application → returns an empty Map.
     */
    @isTest
    static void testGetCustomerData_noApplication_returnsEmpty() {
        String nonExistentId = getDealer().Id; // Account Id ≠ Application Id

        Test.startTest();
        Map<String, Object> result =
            DealerPortalCustomerController.getCustomerData(nonExistentId);
        Test.stopTest();

        System.assertEquals(0, result.size(),
            'getCustomerData should return an empty map when no Application matches the Id');
    }

    /**
     * Valid applicationId → returns a Map populated with application fields
     * (Customer_Name__r fields are null since the app has no linked customer).
     */
    @isTest
    static void testGetCustomerData_appFound_returnsMap() {
        Application__c app = getApp();

        Test.startTest();
        Map<String, Object> result =
            DealerPortalCustomerController.getCustomerData(app.Id);
        Test.stopTest();

        System.assertNotEquals(null, result,
            'getCustomerData should return a non-null map when the Application is found');
        System.assert(result.containsKey('firstName'),
            'Returned map should contain the firstName key');
        System.assert(result.containsKey('selectedCoBuyerAccountId'),
            'Returned map should contain the selectedCoBuyerAccountId key');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getAccountDetails  (also covers AccountDetailsWrapper + formatAddress)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Valid accountId → returns AccountDetailsWrapper; billingAddress is
     * formatted from the dealer's billing fields (all 5 parts present).
     */
    @isTest
    static void testGetAccountDetails_accountFound_returnsWrapper() {
        Account dealer = getDealer();

        Test.startTest();
        DealerPortalCustomerController.AccountDetailsWrapper wrapper =
            DealerPortalCustomerController.getAccountDetails(dealer.Id);
        Test.stopTest();

        System.assertNotEquals(null, wrapper,
            'getAccountDetails should return a non-null wrapper when the account is found');
        System.assertEquals(dealer.Id, wrapper.id,
            'Wrapper id should match the queried account Id');
        // Dealer has BillingStreet, City, State, PostalCode, Country set by factory
        System.assertNotEquals(null, wrapper.billingAddress,
            'billingAddress should be formatted from the dealer billing fields');
        System.assert(wrapper.billingAddress.contains('Toronto'),
            'billingAddress should include the billing city');
    }

    /**
     * Non-existent accountId → returns null.
     */
    @isTest
    static void testGetAccountDetails_notFound_returnsNull() {
        Application__c app = getApp();
        // Application Id will not match any Account record
        String nonExistentId = app.Id;

        Test.startTest();
        DealerPortalCustomerController.AccountDetailsWrapper wrapper =
            DealerPortalCustomerController.getAccountDetails(nonExistentId);
        Test.stopTest();

        System.assertEquals(null, wrapper,
            'getAccountDetails should return null when no Account matches the Id');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // saveCustomerData
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * applicationId points to no Application → inner code throws
     * AuraHandledException (application not found).
     */
    @isTest
    static void testSaveCustomerData_appNotFound_throwsException() {
        Map<String, Object> customerData = new Map<String, Object>{
            'applicationId' => getDealer().Id   // Account Id, not Application Id
        };

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            DealerPortalCustomerController.saveCustomerData(customerData);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown,
            'saveCustomerData should throw AuraHandledException when the Application is not found');
    }

    /**
     * app.Customer_Name__c == null → handler creates a new Customer Account,
     * links it to the Application, and returns 'Success'.
     */
    @isTest
    static void testSaveCustomerData_newCustomer_createsAccount() {
        Application__c app = getApp();
        // app.Customer_Name__c is null from @TestSetup

        Map<String, Object> customerData = new Map<String, Object>{
            'applicationId'  => app.Id,
            'firstName'      => 'Jane',
            'lastName'       => 'Doe',
            'email'          => null,
            'phone'          => null,
            'streetAddress'  => null,
            'city'           => null,
            'province'       => null,
            'postalCode'     => null,
            'country'        => null,
            'licenseNumber'  => null,
            'licenseProvince'=> null,
            'licenseExpiry'  => null,
            'insuranceProvider' => null,
            'insurancePolicy'   => null
        };

        Test.startTest();
        String result = DealerPortalCustomerController.saveCustomerData(customerData);
        Test.stopTest();

        System.assertEquals('Success', result,
            'saveCustomerData should return Success when a new customer account is created');

        Application__c updated = [SELECT Customer_Name__c FROM Application__c WHERE Id = :app.Id];
        System.assertNotEquals(null, updated.Customer_Name__c,
            'Application.Customer_Name__c should be linked to the newly created Account');
    }

    /**
     * app.Customer_Name__c != null → handler upserts the existing account
     * and returns 'Success'.
     */
    @isTest
    static void testSaveCustomerData_existingCustomer_returnsSuccess() {
        Application__c app   = getApp();
        Account        cust  = TestDataFactory.createCustomerAccount(true);
        update new Application__c(Id = app.Id, Customer_Name__c = cust.Id);

        Map<String, Object> customerData = new Map<String, Object>{
            'applicationId'  => app.Id,
            'firstName'      => 'Updated',
            'lastName'       => 'Name',
            'email'          => null,
            'phone'          => null,
            'streetAddress'  => null,
            'city'           => null,
            'province'       => null,
            'postalCode'     => null,
            'country'        => null,
            'licenseNumber'  => null,
            'licenseProvince'=> null,
            'licenseExpiry'  => null,
            'insuranceProvider' => null,
            'insurancePolicy'   => null
        };

        Test.startTest();
        String result = DealerPortalCustomerController.saveCustomerData(customerData);
        Test.stopTest();

        System.assertEquals('Success', result,
            'saveCustomerData should return Success when updating an existing customer account');
    }

    /**
     * coBuyerFirstName is non-blank → handler creates a new Co-Buyer Account
     * and links it to the Application.
     */
    @isTest
    static void testSaveCustomerData_withCoBuyer_createsCoBuyerAccount() {
        Application__c app  = getApp();
        Account        cust = TestDataFactory.createCustomerAccount(true);
        update new Application__c(Id = app.Id, Customer_Name__c = cust.Id);

        Map<String, Object> customerData = new Map<String, Object>{
            'applicationId'    => app.Id,
            'firstName'        => 'John',
            'lastName'         => 'Doe',
            'email'            => null,
            'phone'            => null,
            'streetAddress'    => null,
            'city'             => null,
            'province'         => null,
            'postalCode'       => null,
            'country'          => null,
            'licenseNumber'    => null,
            'licenseProvince'  => null,
            'licenseExpiry'    => null,
            'insuranceProvider'=> null,
            'insurancePolicy'  => null,
            'coBuyerFirstName' => 'Jane',
            'coBuyerLastName'  => 'Smith',
            'coBuyerEmail'     => null,
            'coBuyerPhone'     => null,
            'coBuyerStreetAddress' => null,
            'coBuyerCity'      => null,
            'coBuyerProvince'  => null,
            'coBuyerPostalCode'=> null,
            'coBuyerCountry'   => null
        };

        Test.startTest();
        String result = DealerPortalCustomerController.saveCustomerData(customerData);
        Test.stopTest();

        System.assertEquals('Success', result,
            'saveCustomerData should return Success when a co-buyer account is created');

        Application__c updated = [SELECT Co_Buyer__c FROM Application__c WHERE Id = :app.Id];
        System.assertNotEquals(null, updated.Co_Buyer__c,
            'Application.Co_Buyer__c should be linked to the newly created co-buyer Account');
    }

    /**
     * licenseExpiry string provided → Date.valueOf parses it and sets
     * License_Expiry__c on the customer account.
     */
    @isTest
    static void testSaveCustomerData_withLicenseExpiry_setsDate() {
        Application__c app  = getApp();
        Account        cust = TestDataFactory.createCustomerAccount(true);
        update new Application__c(Id = app.Id, Customer_Name__c = cust.Id);

        Map<String, Object> customerData = new Map<String, Object>{
            'applicationId'  => app.Id,
            'firstName'      => 'John',
            'lastName'       => 'Doe',
            'email'          => null,
            'phone'          => null,
            'streetAddress'  => null,
            'city'           => null,
            'province'       => null,
            'postalCode'     => null,
            'country'        => null,
            'licenseNumber'  => 'DL123456',
            'licenseProvince'=> 'ON',
            'licenseExpiry'  => '2028-06-30',
            'insuranceProvider' => null,
            'insurancePolicy'   => null
        };

        Test.startTest();
        String result = DealerPortalCustomerController.saveCustomerData(customerData);
        Test.stopTest();

        System.assertEquals('Success', result,
            'saveCustomerData should return Success when licenseExpiry is provided');

        Account updatedCust = [
            SELECT License_Expiry__c, License_Number__c
            FROM   Account
            WHERE  Id = :cust.Id
        ];
        System.assertEquals(Date.newInstance(2028, 6, 30), updatedCust.License_Expiry__c,
            'License_Expiry__c should be set to the parsed date');
        System.assertEquals('DL123456', updatedCust.License_Number__c,
            'License_Number__c should be updated on the customer account');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // createPersonAccount
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Valid accountData → inserts a new Account and returns it with an Id.
     */
    @isTest
    static void testCreatePersonAccount_createsAccount() {
        Map<String, Object> accountData = new Map<String, Object>{
            'firstName' => 'New',
            'lastName'  => 'Person',
            'email'     => 'newperson@test.invalid',
            'phone'     => '416-555-9999'
        };

        Test.startTest();
        Account result = DealerPortalCustomerController.createPersonAccount(accountData);
        Test.stopTest();

        System.assertNotEquals(null, result,
            'createPersonAccount should return a non-null Account');
        System.assertNotEquals(null, result.Id,
            'createPersonAccount should return an Account with a non-null Id');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // searchAccounts
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Search term matches an existing person account → returns it.
     */
    @isTest
    static void testSearchAccounts_matchFound_returnsAccounts() {
        Account cust = TestDataFactory.createCustomerAccount(true);

        Test.startTest();
        // Query uses LIKE '%searchTerm%' against Name, so 'Customer' matches factory names
        List<Account> results = DealerPortalCustomerController.searchAccounts('Customer');
        Test.stopTest();

        System.assert(results.size() >= 1,
            'searchAccounts should return at least one record when a person account name matches');
    }

    /**
     * Search term matches nothing → returns empty list.
     */
    @isTest
    static void testSearchAccounts_noMatch_returnsEmpty() {
        Test.startTest();
        List<Account> results =
            DealerPortalCustomerController.searchAccounts('XYZ_NOMATCH_99999_CUSTOMER');
        Test.stopTest();

        System.assertEquals(0, results.size(),
            'searchAccounts should return an empty list when no account name matches');
    }
}