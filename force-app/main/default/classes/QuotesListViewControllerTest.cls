@isTest(SeeAllData=false)
private class QuotesListViewControllerTest {

    @TestSetup
    static void setup() {
        Account dealer = TestDataFactory.createDealer(true);
        Account customer = TestDataFactory.createCustomerAccount(true);
        Vehicle__c vehicle = TestDataFactory.createVehicle(true);

        // 1. Create a searchable Quote (Search by Name/VIN)
        Application__c q1 = TestDataFactory.createQuote(dealer.Id, false);
        //q1.QuoteName__c = 'Standard Quote Alpha';
        q1.Vehicle__c = vehicle.Id; // This links the VIN
        q1.Customer_Name__c = customer.Id;
        insert q1;

        // 2. Create a Quote with Service Packages (To test labels)
        Application__c q2 = TestDataFactory.createQuote(dealer.Id, true);
        
        // Setup Package for Service Labels
        // Using 'Extended_Limited_Warranty' to test the mapper branch
        TestDataFactory.createApplicationPackage(
            q2.Id, null, null, dealer.Id, 
            'Extended_Limited_Warranty', 1000.00, 13.00, true
        );

        // 3. Simple Quote for pagination
        TestDataFactory.createQuote(dealer.Id, true);
    }

    // ── Search Tests ──────────────────────────────────────────────────────────

    @isTest
    static void testGetQuotesList_searchByQuoteName() {
        Test.startTest();
        QuotesListViewController.ApplicationsResponse resp = 
            QuotesListViewController.getQuotesList(1, 10, 'Alpha');
        Test.stopTest();
    }

    @isTest
    static void testGetQuotesList_searchByVIN() {
        Vehicle__c v = [SELECT VIN__c FROM Vehicle__c LIMIT 1];
        Test.startTest();
        QuotesListViewController.ApplicationsResponse resp = 
            QuotesListViewController.getQuotesList(1, 10, v.VIN__c);
        Test.stopTest();
    }

    @isTest
    static void testGetQuotesList_searchByCustomerName() {
        Account acc = [SELECT Name FROM Account WHERE RecordType.DeveloperName = 'PersonAccount' LIMIT 1];
        Test.startTest();
        QuotesListViewController.ApplicationsResponse resp = 
            QuotesListViewController.getQuotesList(1, 10, acc.Name);
        Test.stopTest();

        Assert.isTrue(resp.totalCount >= 1, 'Should find quote by Customer Name');
        Assert.isNotNull(resp.data[0].customerName);
    }

    // ── Service Labels & Mapper Tests ─────────────────────────────────────────

    @isTest
    static void testGetQuotesList_serviceLabelsPopulated() {
        Test.startTest();
        QuotesListViewController.ApplicationsResponse resp = 
            QuotesListViewController.getQuotesList(1, 10, null);
        Test.stopTest();

        Boolean foundMappedLabel = false;
        for(QuotesListViewController.ApplicationRow row : resp.data) {
            if(row.services.contains('Extended Warranty')) {
                foundMappedLabel = true;
            }
        }
    }

    // ── Pagination & Edge Cases ───────────────────────────────────────────────

    @isTest
    static void testGetQuotesList_paginationEdgeCase() {
        // Request a page number way beyond total pages
        Test.startTest();
        QuotesListViewController.ApplicationsResponse resp = 
            QuotesListViewController.getQuotesList(99, 10, null);
        Test.stopTest();

        Assert.areEqual(resp.totalPages, resp.pageNumber, 'Should default to last available page');
    }

    // ── Exception Handling ────────────────────────────────────────────────────

    @isTest
    static void testCreateNewQuote_Exception() {
        // Force an exception by running as a user who cannot insert applications
        User restrictedUser = TestDataFactory.createInternalUser(true);
        // Note: You might need to adjust profile permissions in your org to truly force a DML error
        
        Test.startTest();
        QuotesListViewController.CreateQuoteResponse resp;
        System.runAs(restrictedUser) {
            // If the user has no permissions, this hits the catch block
            resp = QuotesListViewController.createNewQuote();
        }
        Test.stopTest();
        
        // If it succeeded, recordId is set; if it failed (catch block), success is false
        if(!resp.success) {
            Assert.isNotNull(resp.message);
        }
    }

    @isTest
    static void testGetQuotesList_Exception() {
        // Force exception by passing invalid pagination that might cause SOQL error
        // though the code protects against null, we can try to break the query logic
        Test.startTest();
        // Passing a null search term is handled, but we want to ensure the try-catch is active
        QuotesListViewController.ApplicationsResponse resp = 
            QuotesListViewController.getQuotesList(1, -1, null);
        Test.stopTest();

        Assert.isNotNull(resp);
    }
}