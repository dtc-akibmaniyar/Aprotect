@IsTest
private class CreateClaimControllerTest {

    // Builds every dependency BEFORE the single Application__c insert, then
    // sets every field the insert itself needs - deliberately never issues a
    // separate `update app`. An unrelated, pre-existing "Update Opportunity
    // Statuses Flow" in the org fires on Application__c UPDATE and throws
    // (a record variable with no populated Id) - a real bug in the other
    // team's automation, not ours to fix here, so this test setup just
    // avoids triggering it rather than working around it.
    //
    // The Application_Package__c shape mirrors a real, already-working
    // production record (confirmed live via query on APP000492 /
    // a0VG1000008k589MAA): its own Package_Term__c is left null - the real
    // master-term link for an "engine-priced" package is reached through
    // Dealer_Package_Term__r.Package_Term__c instead - and Package_Tier__c
    // is set directly. Building the same shape here (Dealer_Package__c +
    // Dealer_Package_Term__c set, Package_Term__c left null) both matches
    // reality and avoids CommissionCalculationTrigger's out-of-range error,
    // which a directly-set Package_Term__c with no dealer chain (a shape
    // that doesn't occur in real data) was tripping.
    //
    // Parameterized (Sep 26) so Coverage_Active__c's new Start_Term__c/
    // Expiry_Term__c/Duration_Type__c window logic can be exercised with
    // different purchase dates and term shapes without duplicating the
    // whole chain-building block per test.
    private static Application__c buildFullChain() {
        return buildFullChain(6, 0, 48, 'Months');
    }

    private static Application__c buildFullChain(Integer purchaseMonthsAgo, Integer startTerm, Integer expiryTerm, String durationType) {
        Account dealer = TestDataFactory.createDealer(true);

        Vehicle__c vehicle = TestDataFactory.createVehicle(false);
        vehicle.Odometer__c = 10000;
        vehicle.Purchase_Date__c = Date.today().addMonths(-purchaseMonthsAgo);
        insert vehicle;

        Package__c pkg = TestDataFactory.createPackage('Extended_Limited_Warranty', true);
        Package_Tier__c tier = TestDataFactory.createPackageTier(pkg.Id, true);
        Package_Term__c term = TestDataFactory.createPackageTerm(pkg.Id, tier.Id, false);
        term.Restriction_Type__c = 'Fixed Odometer';
        term.Duration_Restriction_in_Months__c = 48;
        term.Mileage_Restriction_End__c = 90000;
        insert term;

        Dealer_Package__c dealerPkg = TestDataFactory.createDealerPackage(dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true);
        Dealer_Package_Tier__c dealerTier = TestDataFactory.createDealerPackageTier(dealerPkg.Id, tier.Id, true);
        Dealer_Package_Term__c dealerTerm = TestDataFactory.createDealerPackageTerm(dealerPkg.Id, term.Id, dealerTier.Id, false);
        dealerTerm.Restriction_Type__c = 'Fixed Odometer';
        dealerTerm.Mileage__c = 90000;
        dealerTerm.Mileage_Unit__c = 'KM';
        dealerTerm.Start_Term__c = startTerm;
        dealerTerm.Expiry_Term__c = expiryTerm;
        dealerTerm.Duration_Type__c = durationType;
        insert dealerTerm;

        Application__c app = new Application__c(
            Dealer_Name__c        = dealer.Id,
            RecordTypeId          = TestDataFactory.getRecordTypeId('Application__c', 'Application'),
            Application_Status__c = 'Draft',
            Payment_Status__c     = 'Paid',
            Vehicle__c             = vehicle.Id
        );
        insert app;

        Application_Package__c appPkg = new Application_Package__c(
            Application__c = app.Id,
            Dealer__c = dealer.Id,
            Dealer_Package__c = dealerPkg.Id,
            Dealer_Package_Term__c = dealerTerm.Id,
            Package_Tier__c = tier.Id,
            Active__c = true,
            Contract_Start_Date__c = Date.today().addMonths(-purchaseMonthsAgo),
            Contract_End_Date__c = Date.today().addMonths(6),
            Odometer_Start__c = 0,
            Odometer_End__c = 200000
        );
        insert appPkg;

        return app;
    }

    @IsTest
    static void getApplicationChainDataReturnsFullChain() {
        Application__c app = buildFullChain();

        Test.startTest();
        CreateClaimController.ApplicationChainData data =
            CreateClaimController.getApplicationChainData(app.Id);
        Test.stopTest();

        System.assertEquals('Toyota', data.vehicleMake, 'Vehicle make should come through the Application->Vehicle chain');
        System.assertEquals(10000, data.purchaseOdometer, 'Purchase odometer should read Vehicle__r.Odometer__c');
        System.assertEquals('Paid', data.paymentStatus, 'Payment status should read straight off Application__c');
        System.assertNotEquals(null, data.contractStartDate, 'Contract start date should resolve from the active Application_Package__c');
        System.assertNotEquals(null, data.dealerPackageName, 'Dealer Package name should resolve from the dealer chain');
        System.assertNotEquals(null, data.dealerPackageTermName, 'Dealer Package Term name should resolve from the dealer chain');
        System.assertNotEquals(null, data.dealerPackageTierName, 'Dealer Package Tier name should resolve from the dealer chain');
        System.assertEquals(0, data.startTerm);
        System.assertEquals(48, data.expiryTerm);
        System.assertEquals('Months', data.durationType);
        System.assertEquals('Fixed Odometer', data.restrictionType);
        System.assertEquals(90000, data.maxEligibleMileage);
        System.assertEquals('KM', data.maxEligibleMileageUnit);
    }

    @IsTest
    static void createClaimHappyPathStampsRecordTypeAndStatusAndDoesNotRequireRepairShop() {
        Application__c app = buildFullChain();
        Date filed = Date.today();

        Test.startTest();
        Id claimId = CreateClaimController.createClaim(
            app.Id, filed, 15000, 'KM', 'Rattling noise from the front end.', 'At the dealership'
        );
        Test.stopTest();

        Claim__c claim = [
            SELECT Id, RecordType.DeveloperName, Claim_Status__c, Date_Filed__c, Current_Odometer__c,
                   Current_Odometer_Unit__c, Claim_Description__c, Customer_Location__c,
                   Repair_Shop__c, Email_Sent_To_Repair_Shop__c
            FROM Claim__c
            WHERE Id = :claimId
        ];
        System.assertEquals('Warranty_Claim', claim.RecordType.DeveloperName);
        System.assertEquals('New Claim', claim.Claim_Status__c);
        System.assertEquals(filed, claim.Date_Filed__c);
        System.assertEquals(15000, claim.Current_Odometer__c);
        System.assertEquals('KM', claim.Current_Odometer_Unit__c);
        System.assertEquals('Rattling noise from the front end.', claim.Claim_Description__c);
        System.assertEquals('At the dealership', claim.Customer_Location__c);
        System.assertEquals(null, claim.Repair_Shop__c, 'Create Claim deliberately never sets Repair_Shop__c');
        System.assertEquals(false, claim.Email_Sent_To_Repair_Shop__c, 'No repair shop yet, so no referral email should have gone out');
    }

    @IsTest
    static void flowStampsApplicationPackagePackageTermPackageTierAndPurchaseDate() {
        Application__c app = buildFullChain();

        Test.startTest();
        Id claimId = CreateClaimController.createClaim(
            app.Id, Date.today(), 15000, 'KM', 'desc', 'loc'
        );
        Test.stopTest();

        Claim__c claim = [
            SELECT Application_Package__c, Package_Term__c, Package_Tier__c, Purchase_Date__c,
                   Purchase_Odometer__c, Purchase_Odometer_Unit__c, Vehicle__c, Dealer_Name__c,
                   Dealer_Package__c, Dealer_Package_Term__c, Dealer_Package_Tier__c
            FROM Claim__c
            WHERE Id = :claimId
        ];
        System.assertNotEquals(null, claim.Application_Package__c, 'Flow fix should stamp the active Application_Package__c');
        System.assertNotEquals(null, claim.Package_Term__c, 'Flow fix should stamp Package_Term__c');
        System.assertNotEquals(null, claim.Package_Tier__c, 'Flow fix should stamp Package_Tier__c');
        System.assertNotEquals(null, claim.Purchase_Date__c, 'Flow fix should stamp Purchase_Date__c from Vehicle__r');
        System.assertEquals(10000, claim.Purchase_Odometer__c, 'Warranty branch should now stamp Purchase_Odometer__c too');
        System.assertEquals('KM', claim.Purchase_Odometer_Unit__c);
        System.assertNotEquals(null, claim.Vehicle__c);
        System.assertNotEquals(null, claim.Dealer_Name__c);
        System.assertNotEquals(null, claim.Dealer_Package__c, 'Flow should stamp Dealer_Package__c');
        System.assertNotEquals(null, claim.Dealer_Package_Term__c, 'Flow should stamp Dealer_Package_Term__c');
        System.assertNotEquals(null, claim.Dealer_Package_Tier__c, 'Flow should stamp Dealer_Package_Tier__c via Dealer_Package_Term__r');
    }

    @IsTest
    static void flowSendsReferralEmailOnceRepairShopIsSetByLaterUpdate() {
        Application__c app = buildFullChain();
        Repair_Shop__c shop = new Repair_Shop__c(Name = 'Test Repair Shop', Email__c = 'shop@example.com');
        insert shop;

        Id claimId = CreateClaimController.createClaim(app.Id, Date.today(), 15000, 'KM', 'desc', 'loc');
        Claim__c beforeShop = [SELECT Email_Sent_To_Repair_Shop__c FROM Claim__c WHERE Id = :claimId];
        System.assertEquals(false, beforeShop.Email_Sent_To_Repair_Shop__c, 'No email until a repair shop is set');

        Test.startTest();
        update new Claim__c(Id = claimId, Repair_Shop__c = shop.Id);
        Test.stopTest();

        Claim__c afterShop = [SELECT Email_Sent_To_Repair_Shop__c FROM Claim__c WHERE Id = :claimId];
        System.assertEquals(true, afterShop.Email_Sent_To_Repair_Shop__c, 'Setting Repair_Shop__c later should trigger the referral email exactly once');
    }

    @IsTest
    static void coverageActiveAndWarrantyValidityComputeCorrectlyOnReadback() {
        // Default buildFullChain shape: purchased 6 months ago, dealer term
        // window 0-48 months - well inside the window, odometer under the
        // mileage restriction.
        Application__c app = buildFullChain();
        Id claimId = CreateClaimController.createClaim(app.Id, Date.today(), 15000, 'KM', 'desc', 'loc');

        Claim__c claim = [SELECT Coverage_Active__c, Warranty_Validity__c FROM Claim__c WHERE Id = :claimId];
        System.assertEquals(true, claim.Coverage_Active__c, 'Odometer 15000 is within the dealer term 0-48mo window and under the 90000 mileage restriction');
        System.assertNotEquals(null, claim.Warranty_Validity__c, 'Warranty_Validity__c should always resolve to one of the two badge images');
    }

    // Split into two @IsTest methods (each gets its own isolated, rolled-back
    // transaction) rather than calling buildFullChain() twice in one method -
    // TestDataFactory.createDealer's Account fields (Phone/Billing Address)
    // are hardcoded identically on every call, which trips a pre-existing
    // Account Duplicate Rule on the SECOND insert within the same
    // transaction. Not a bug in anything built here.
    @IsTest
    static void coverageActiveIsFalseBeforeDeferredStartTermBegins() {
        // Purchased 6 months ago, but coverage doesn't start until month 12 -
        // today is before the lower bound, so Coverage_Active__c must be
        // false even though the odometer/mileage restriction would pass.
        Application__c app = buildFullChain(6, 12, 60, 'Months');
        Id claimId = CreateClaimController.createClaim(app.Id, Date.today(), 15000, 'KM', 'desc', 'loc');
        Claim__c claim = [SELECT Coverage_Active__c FROM Claim__c WHERE Id = :claimId];
        System.assertEquals(false, claim.Coverage_Active__c, 'Today is before Start_Term__c=12 months, coverage has not started yet');
    }

    @IsTest
    static void coverageActiveIsTrueWithinDeferredStartTermWindow() {
        // Purchased 18 months ago, 12-60 month window - today is inside the
        // window now.
        Application__c app = buildFullChain(18, 12, 60, 'Months');
        Id claimId = CreateClaimController.createClaim(app.Id, Date.today(), 15000, 'KM', 'desc', 'loc');
        Claim__c claim = [SELECT Coverage_Active__c FROM Claim__c WHERE Id = :claimId];
        System.assertEquals(true, claim.Coverage_Active__c, 'Today is within the deferred 12-60 month window');
    }

    @IsTest
    static void coverageActiveConvertsYearsToMonthsCorrectly() {
        // Purchased 30 months ago, Expiry_Term__c=4 with Duration_Type__c=
        // 'Years' means the real window is 0-48 months - a bug that forgot
        // the *12 conversion would evaluate this as a 0-4 month window and
        // report false at 30 months elapsed, failing this assertion.
        Application__c app = buildFullChain(30, 0, 4, 'Years');
        Id claimId = CreateClaimController.createClaim(app.Id, Date.today(), 15000, 'KM', 'desc', 'loc');
        Claim__c claim = [SELECT Coverage_Active__c FROM Claim__c WHERE Id = :claimId];
        System.assertEquals(true, claim.Coverage_Active__c, 'Expiry_Term__c=4 Years must convert to 48 months, not be read as 4 months');
    }

    @IsTest
    static void coverageActiveConvertsMileageUnitMismatchCorrectly() {
        // Dealer term's Max. Eligible Mileage is 90000 KM (from buildFullChain's
        // default). Claim's own odometer is entered in Miles at 60000 - a
        // bug that skipped unit conversion would wrongly compare
        // 60000 <= 90000 and pass. Converted correctly, 90000 KM is
        // ~55923 miles, and 60000 miles exceeds that, so this must be false.
        Application__c app = buildFullChain();
        Id claimId = CreateClaimController.createClaim(app.Id, Date.today(), 60000, 'Miles', 'desc', 'loc');
        Claim__c claim = [SELECT Coverage_Active__c FROM Claim__c WHERE Id = :claimId];
        System.assertEquals(false, claim.Coverage_Active__c,
            '60000 miles exceeds the 90000 KM (~55923 mile) limit once correctly converted');
    }

    @IsTest
    static void createClaimAlwaysInsertsNewClaimEvenWhenOneAlreadyExistsForApplication() {
        Application__c app = buildFullChain();

        Id firstClaimId = CreateClaimController.createClaim(app.Id, Date.today(), 15000, 'KM', 'first', 'loc');

        Test.startTest();
        Id secondClaimId = CreateClaimController.createClaim(app.Id, Date.today(), 16000, 'KM', 'second', 'loc');
        Test.stopTest();

        System.assertNotEquals(firstClaimId, secondClaimId, 'Create Claim must always insert a new record, never update an existing one');
        System.assertEquals(2, [SELECT COUNT() FROM Claim__c WHERE Application__c = :app.Id],
            'Both claims must exist as separate records');
    }
}