/**
 * DealerActionBoardControllerTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Covers:
 * • getCompanyNotices() - Public notices for all users
 * • getDealerNotices()  - Notices assigned via junction object to specific dealers
 */
@isTest(SeeAllData=false)
private class DealerActionBoardControllerTest {

    @TestSetup
    static void setup() {
        // 1. Setup Dealer and Portal User
        Account dealer = TestDataFactory.createDealer(true);
        User portalUser = TestDataFactory.createPortalUser(dealer.Id, true);

        // 2. Setup Company-Specific Notice
        // We use the RecordType mapping defined in your TestDataFactory
        Notice__c companyNotice = TestDataFactory.createNotice(false);
        companyNotice.RecordTypeId = TestDataFactory.getRecordTypeId('Notice__c', 'Company_Specific_Notice');
        companyNotice.IsActive__c = true;
        insert companyNotice;

        // 3. Setup Dealer-Specific Notice
        Notice__c dealerNotice = TestDataFactory.createNotice(false);
        dealerNotice.RecordTypeId = TestDataFactory.getRecordTypeId('Notice__c', 'Dealer_Specific_Notice');
        dealerNotice.IsActive__c = true;
        insert dealerNotice;

        // 4. Create the Junction Assignment
        // (Assuming Dealer_Notice_Assignment__c has fields: Notice__c and Dealer_Name__c)
        Dealer_Notice_Assignment__c assignment = new Dealer_Notice_Assignment__c(
            Notice__c = dealerNotice.Id,
            Dealer_Name__c = dealer.Id
        );
        insert assignment;
    }

    private static User getPortalUser() {
        return [SELECT Id FROM User WHERE Alias = 'ptlu' LIMIT 1];
    }

    // ── Company Notices Test ──────────────────────────────────────────────────

    @isTest
    static void testGetCompanyNotices_ReturnsActiveCompanyNotices() {
        Test.startTest();
        List<Notice__c> results = DealerActionBoardController.getCompanyNotices();
        Test.stopTest();

        Assert.isFalse(results.isEmpty(), 'Should return active company notices');
        // Verify only Company_Specific_Notice is returned (dealer notice should be excluded)
        Assert.areEqual(1, results.size(), 'Only one company notice should be returned');
    }

    // ── Dealer Notices Tests ───────────────────────────────────────────────────

    @isTest
    static void testGetDealerNotices_PortalUser_ReturnsAssignedNotices() {
        User portalUser = getPortalUser();

        System.runAs(portalUser) {
            Test.startTest();
            List<Notice__c> results = DealerActionBoardController.getDealerNotices();
            Test.stopTest();

            Assert.isFalse(results.isEmpty(), 'Portal user should see assigned dealer notices');
            Assert.areEqual(1, results.size(), 'Should return exactly 1 assigned notice');
            Assert.isNotNull(results[0].Notice_Message__c);
        }
    }

    @isTest
    static void testGetDealerNotices_InternalUser_ReturnsEmptyList() {
        // Create an internal user (no Contact/Account association)
        User internalUser = TestDataFactory.createInternalUser(true);

        System.runAs(internalUser) {
            Test.startTest();
            List<Notice__c> results = DealerActionBoardController.getDealerNotices();
            Test.stopTest();

            Assert.isTrue(results.isEmpty(), 'Internal user with no contact should return empty list');
        }
    }
/*
    @isTest
    static void testGetDealerNotices_NoAccount_ReturnsEmptyList() {
        // Create a contact WITHOUT an account to test that specific null check
        Contact c = new Contact(FirstName = 'No', LastName = 'Account', Email = 'noacc@test.com');
        insert c;

        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = 'noacc', Email='noacc@test.com', LastName='Testing', 
            ProfileId = p.Id, ContactId = c.Id, // Linking to contact with null AccountId
            Username='noacc' + System.currentTimeMillis() + '@test.com',
            TimeZoneSidKey='America/Toronto', LocaleSidKey='en_US', 
            EmailEncodingKey='UTF-8', LanguageLocaleKey='en_US'
        );
        insert u;

        System.runAs(u) {
            Test.startTest();
            List<Notice__c> results = DealerActionBoardController.getDealerNotices();
            Test.stopTest();

            Assert.isTrue(results.isEmpty(), 'User linked to contact with no account should return empty');
        }
    }
*/
}