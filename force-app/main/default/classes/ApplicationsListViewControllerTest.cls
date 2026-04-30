@isTest(SeeAllData=false)
private class ApplicationsListViewControllerTest {

    @TestSetup
    static void setup() {
        Account dealer = TestDataFactory.createDealer(true);
        Vehicle__c vehicle = TestDataFactory.createVehicle(true);

        // 1. Create Drafts (LINK VEHICLE)
        List<Application__c> drafts = TestDataFactory.createBulkApplications(dealer.Id, 3, false);
        for(Application__c app : drafts) app.Vehicle__c = vehicle.Id;
        insert drafts;

        // 2. Create Submitted (LINK VEHICLE)
        Application__c sub1 = TestDataFactory.createSubmittedApplication(dealer.Id, false);
        sub1.Vehicle__c = vehicle.Id;
        Application__c sub2 = TestDataFactory.createSubmittedApplication(dealer.Id, false);
        sub2.Vehicle__c = vehicle.Id;
        insert new List<Application__c>{sub1, sub2};

        // 3. Create Cancelled (LINK VEHICLE)
        Application__c cancelled = TestDataFactory.createApplication(dealer.Id, false);
        cancelled.Application_Status__c = 'Cancelled';
        cancelled.Vehicle__c = vehicle.Id;
        insert cancelled;

        // 4. Setup Services/Invoice for the first app
        Package__c pkg = TestDataFactory.createPackage('Extended_Limited_Warranty', true);
        Package_Tier__c tier = TestDataFactory.createPackageTier(pkg.Id, true);
        Package_Term__c term = TestDataFactory.createPackageTerm(pkg.Id, tier.Id, true);
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true);
        Dealer_Package_Tier__c dpt = TestDataFactory.createDealerPackageTier(dp.Id, tier.Id, true);
        Dealer_Package_Term__c dterm = TestDataFactory.createDealerPackageTerm(dp.Id, term.Id, dpt.Id, true);

        TestDataFactory.createApplicationPackage(drafts[0].Id, dp.Id, dterm.Id, dealer.Id, 'Extended_Limited_Warranty', 1500.00, 13.00, true);
        TestDataFactory.createInvoice(drafts[0].Id, true);
    }

    @isTest
    static void testGetApplicationsList_draftFilter() {
        Test.startTest();
        ApplicationsListViewController.ApplicationsResponse resp = ApplicationsListViewController.getApplicationsList(1, 10, null, 'Draft', null, null);
        Test.stopTest();

        Assert.isTrue(resp.success);
        Assert.isTrue(resp.totalCount >= 3, 'Should find the 3 draft apps');
    }

    @isTest
    static void testGetApplicationsList_submittedFilter() {
        Test.startTest();
        ApplicationsListViewController.ApplicationsResponse resp = ApplicationsListViewController.getApplicationsList(1, 10, null, 'Submitted', null, null);
        Test.stopTest();

        Assert.isTrue(resp.success);
        Assert.isTrue(resp.totalCount >= 2);
    }

    @isTest
    static void testGetApplicationsList_withDateFilter() {
        String todayStr = String.valueOf(Date.today());
        String nextDayStr = String.valueOf(Date.today().addDays(1));

        Test.startTest();
        ApplicationsListViewController.ApplicationsResponse resp = ApplicationsListViewController.getApplicationsList(1, 10, null, 'Draft', todayStr, nextDayStr);
        Test.stopTest();

        Assert.isTrue(resp.success);
        Assert.isTrue(resp.totalCount >= 3);
    }

    @isTest
    static void testGetApplicationsList_pagination() {
        Test.startTest();
        ApplicationsListViewController.ApplicationsResponse resp = ApplicationsListViewController.getApplicationsList(1, 2, null, 'Draft', null, null);
        Test.stopTest();

        Assert.areEqual(2, resp.data.size(), 'Should only return 2 records due to pageSize');
    }

    @isTest
    static void testGetApplicationsList_search() {
        Test.startTest();
        ApplicationsListViewController.ApplicationsResponse resp = ApplicationsListViewController.getApplicationsList(1, 10, 'XYZ_INVALID_VIN', 'Draft', null, null);
        Test.stopTest();

        Assert.areEqual(0, resp.totalCount, 'Should return 0 for non-matching search');
    }

    @isTest
    static void testCreateNewApplication() {
        Test.startTest();
        ApplicationsListViewController.CreateApplicationResponse result = ApplicationsListViewController.createNewApplication();
        Test.stopTest();

        Assert.isTrue(result.success);
        Assert.isNotNull(result.recordId);
    }
}