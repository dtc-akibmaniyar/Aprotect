/**
 * DealerPortalWarrantyEligibilityTest
 *
 * Covers the 2026-09-22 fail-closed change in
 * DealerPortalController.isWarrantyTermEligible plus the new
 * DealerPackagesResponse.vehicleDataIncomplete response flag:
 *
 *   1. Application has NO vehicle            -> no eligible terms, flag TRUE.
 *   2. Vehicle present, Year__c blank        -> no eligible terms, flag TRUE.
 *   3. Vehicle present, Odometer__c null     -> no eligible terms, flag TRUE.
 *   4. Vehicle data COMPLETE (year+odometer) -> behaviour UNCHANGED: the
 *      eligible package and its term come back and the flag is FALSE.
 *
 * These exercise the public read path the warranty tab uses
 * (DealerPortalController.getDealerPackages); isWarrantyTermEligible is private
 * and is judged exactly as the portal judges it.
 *
 * The fixture deliberately builds a TIER-LESS term with no odometer / year /
 * mileage cap, so a complete vehicle is always eligible and any ineligibility
 * observed comes from the vehicle data alone.
 *
 * Run with RunSpecifiedTests (RunLocalTests is blocked by pre-existing,
 * unrelated compile failures elsewhere in the org).
 */
@IsTest
private class DealerPortalWarrantyEligibilityTest {

    private static Map<String, Id> recordTypes;
    private static Id rt(String sObjectType, String devName) {
        if (recordTypes == null) {
            recordTypes = new Map<String, Id>();
            for (RecordType r : [
                SELECT Id, SObjectType, DeveloperName FROM RecordType
                WHERE SObjectType IN ('Account', 'Package__c', 'Dealer_Package__c')
            ]) {
                recordTypes.put(r.SObjectType + '.' + r.DeveloperName, r.Id);
            }
        }
        return recordTypes.get(sObjectType + '.' + devName);
    }

    private class Fixture {
        Account dealer;
        Id dealerPackageId;
        Id dealerTermId;
    }

    /**
     * One dealer + one master package + one dealer package + one dealer term.
     * The master package carries the Extended_Limited_Warranty record type so
     * queryDealerPackages finds it under that record-type filter.
     */
    private static Fixture buildFixture(String tag) {
        Fixture f = new Fixture();

        f.dealer = new Account(Name = 'DEALER ' + tag,
            RecordTypeId = rt('Account', 'Dealer_Account'));
        insert f.dealer;

        Package__c masterPackage = new Package__c(Name = 'PKG ' + tag,
            RecordTypeId = rt('Package__c', 'Extended_Limited_Warranty'));
        insert masterPackage;

        Dealer_Package__c dealerPackage = new Dealer_Package__c(Name = 'DP ' + tag,
            Dealer__c = f.dealer.Id,
            Package__c = masterPackage.Id,
            RecordTypeId = rt('Dealer_Package__c', 'Extended_Limited_Warranty'));
        insert dealerPackage;
        f.dealerPackageId = dealerPackage.Id;

        Package_Term__c masterTerm = new Package_Term__c(Name = 'PT ' + tag);
        insert masterTerm;

        Dealer_Package_Term__c dealerTerm = new Dealer_Package_Term__c(Name = 'DPT ' + tag,
            Dealer_Package__c = dealerPackage.Id,
            Package_Term__c = masterTerm.Id,
            Original_Package_Term_Cost__c = 1000.00,
            Markup__c = 100.00,
            Markup_Type__c = '$');
        insert dealerTerm;
        f.dealerTermId = dealerTerm.Id;

        return f;
    }

    private static Vehicle__c buildVehicle(String tag, String year, Decimal odometer) {
        Make__c mk = new Make__c(Name = 'MK ' + tag);
        insert mk;
        Model__c mo = new Model__c(Name = 'MD ' + tag, Make__c = mk.Id);
        insert mo;
        Vehicle__c v = new Vehicle__c(Name = 'V ' + tag,
            Make_Lookup__c = mk.Id,
            Model_Lookup__c = mo.Id,
            Year__c = year,
            Odometer__c = odometer,
            Odometer_Unit__c = 'KM',
            Usage_Type__c = 'Personal Use');
        insert v;
        return v;
    }

    private static Application__c buildApplication(Account dealer, Vehicle__c vehicle) {
        Application__c app = new Application__c(Dealer_Name__c = dealer.Id);
        if (vehicle != null) {
            app.Vehicle__c = vehicle.Id;
        }
        insert app;
        return app;
    }

    private static DealerPortalController.DealerPackagesResponse readPackages(Id applicationId) {
        return DealerPortalController.getDealerPackages(applicationId, 'Extended_Limited_Warranty');
    }

    // ------------------------------------------------------------------
    // FAIL CLOSED
    // ------------------------------------------------------------------

    @IsTest
    static void noVehicle_FailsClosed_TermIneligible_FlagSet() {
        Fixture f = buildFixture('NV');
        Application__c app = buildApplication(f.dealer, null);

        Test.startTest();
        DealerPortalController.DealerPackagesResponse res = readPackages(app.Id);
        Test.stopTest();

        System.assertEquals(true, res.success, 'read should still succeed: ' + res.message);
        System.assertEquals(true, res.vehicleDataIncomplete,
            'an application with no vehicle must set vehicleDataIncomplete');
        System.assert(res.data == null || res.data.isEmpty(),
            'no eligible terms may be returned when there is no vehicle (fail closed)');
    }

    @IsTest
    static void blankVehicleYear_FailsClosed_TermIneligible_FlagSet() {
        Fixture f = buildFixture('BY');
        Vehicle__c v = buildVehicle('BY', null, 50000);
        Application__c app = buildApplication(f.dealer, v);

        Test.startTest();
        DealerPortalController.DealerPackagesResponse res = readPackages(app.Id);
        Test.stopTest();

        System.assertEquals(true, res.success, 'read should still succeed: ' + res.message);
        System.assertEquals(true, res.vehicleDataIncomplete,
            'a blank vehicle Year__c must set vehicleDataIncomplete');
        System.assert(res.data == null || res.data.isEmpty(),
            'no eligible terms may be returned when the vehicle year is blank (fail closed)');
    }

    @IsTest
    static void nullOdometer_FailsClosed_TermIneligible_FlagSet() {
        Fixture f = buildFixture('NO');
        Vehicle__c v = buildVehicle('NO', '2022', null);
        Application__c app = buildApplication(f.dealer, v);

        Test.startTest();
        DealerPortalController.DealerPackagesResponse res = readPackages(app.Id);
        Test.stopTest();

        System.assertEquals(true, res.success, 'read should still succeed: ' + res.message);
        System.assertEquals(true, res.vehicleDataIncomplete,
            'a null vehicle Odometer__c must set vehicleDataIncomplete');
        System.assert(res.data == null || res.data.isEmpty(),
            'no eligible terms may be returned when the odometer is null (fail closed)');
    }

    // ------------------------------------------------------------------
    // UNCHANGED WHEN THE VEHICLE DATA IS PRESENT
    // ------------------------------------------------------------------

    @IsTest
    static void completeVehicleData_TermStaysEligible_FlagClear() {
        Fixture f = buildFixture('OK');
        Vehicle__c v = buildVehicle('OK', '2022', 50000);
        Application__c app = buildApplication(f.dealer, v);

        Test.startTest();
        DealerPortalController.DealerPackagesResponse res = readPackages(app.Id);
        Test.stopTest();

        System.assertEquals(true, res.success, 'read should succeed: ' + res.message);
        System.assertEquals(false, res.vehicleDataIncomplete,
            'complete vehicle data must leave vehicleDataIncomplete false');
        System.assertNotEquals(null, res.data, 'packages expected');
        System.assertEquals(1, res.data.size(), 'the single eligible package must be returned');

        DealerPortalController.DealerPackageDTO pkg = res.data[0];
        System.assertEquals(f.dealerPackageId, pkg.Id, 'the dealer package must be returned');
        System.assertNotEquals(null, pkg.terms, 'flat terms expected');
        System.assertEquals(1, pkg.terms.size(), 'the eligible term must survive the eligibility gate');
        System.assertEquals(f.dealerTermId, pkg.terms[0].Id, 'the dealer term must be returned');
    }
}