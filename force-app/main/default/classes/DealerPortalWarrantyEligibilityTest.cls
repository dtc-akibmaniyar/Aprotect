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

    // ------------------------------------------------------------------
    // CATALOGUE MARKER (Catalogue_Release__c carried on the plan type)
    // ------------------------------------------------------------------

    /**
     * The dealer package is attached to a Package_Group__c (Plan_Type__c) whose
     * Catalogue_Release__c lookup is set. The warranty tab reads
     * planTypeCatalogueName to append the release (e.g. "(V25)") to the section
     * header, so two same-named plan types from different catalogues can be told
     * apart.
     */
    @IsTest
    static void catalogueName_PopulatedFromPlanType() {
        Fixture f = buildFixture('CAT');

        Catalogue_Release__c cat = new Catalogue_Release__c(Name = 'V25');
        insert cat;

        Package_Group__c grp = new Package_Group__c(
            Name = 'Essential Warranties', Active__c = true, Catalogue_Release__c = cat.Id);
        insert grp;

        // Point the existing dealer package at the group that carries the catalogue.
        Dealer_Package__c dp = [
            SELECT Id FROM Dealer_Package__c WHERE Id = :f.dealerPackageId LIMIT 1
        ];
        dp.Plan_Type__c = grp.Id;
        update dp;

        Vehicle__c v = buildVehicle('CAT', '2022', 50000);
        Application__c app = buildApplication(f.dealer, v);

        Test.startTest();
        DealerPortalController.DealerPackagesResponse res = readPackages(app.Id);
        Test.stopTest();

        System.assertEquals(true, res.success, 'read should succeed: ' + res.message);
        System.assertNotEquals(null, res.data, 'packages expected');
        System.assertEquals(1, res.data.size(), 'the single eligible package must be returned');

        DealerPortalController.DealerPackageDTO pkg = res.data[0];
        System.assertEquals(grp.Id, pkg.planTypeId, 'plan type id must be the group');
        System.assertEquals(cat.Id, pkg.planTypeCatalogueId,
            'catalogue id must come from Plan_Type__r.Catalogue_Release__c');
        System.assertEquals('V25', pkg.planTypeCatalogueName,
            'catalogue name must come from Plan_Type__r.Catalogue_Release__r.Name');
    }

    /**
     * A group with NO Catalogue_Release__c must not break the read — the Apex
     * traversal guards the null parent — and must surface a blank catalogue, so
     * the LWC renders the plain label with no empty parentheses.
     */
    @IsTest
    static void noCatalogue_PlanTypeCatalogueBlank_NoNullPointer() {
        Fixture f = buildFixture('NOCAT');

        Package_Group__c grp = new Package_Group__c(Name = 'Legacy Plan', Active__c = true);
        insert grp;

        Dealer_Package__c dp = [
            SELECT Id FROM Dealer_Package__c WHERE Id = :f.dealerPackageId LIMIT 1
        ];
        dp.Plan_Type__c = grp.Id;
        update dp;

        Vehicle__c v = buildVehicle('NOCAT', '2022', 50000);
        Application__c app = buildApplication(f.dealer, v);

        Test.startTest();
        DealerPortalController.DealerPackagesResponse res = readPackages(app.Id);
        Test.stopTest();

        System.assertEquals(true, res.success,
            'read must still succeed when the plan type has no catalogue: ' + res.message);
        System.assertNotEquals(null, res.data, 'packages expected');
        System.assertEquals(1, res.data.size(), 'the single eligible package must be returned');

        DealerPortalController.DealerPackageDTO pkg = res.data[0];
        System.assertEquals((String) null, pkg.planTypeCatalogueId, 'no catalogue id expected');
        System.assert(String.isBlank(pkg.planTypeCatalogueName),
            'catalogue name must be blank rather than throwing a null-pointer');
    }

    // ------------------------------------------------------------------
    // PLAN-TYPE SECTION ORDER + FLAT HEADER COLOUR
    // (Package_Group__c.Sort_Order__c / Package_Group__c.Package_Color__c)
    // ------------------------------------------------------------------

    /**
     * The plan type / Package_Group__c carries a Sort_Order__c and a
     * Package_Color__c. The warranty tab orders its sections by the sort order
     * and paints each section header with the colour, so both must reach the
     * DTO. Read from Plan_Type__r -- the group the section is keyed by.
     */
    @IsTest
    static void planTypeSortOrderAndColor_CarriedFromGroup() {
        Fixture f = buildFixture('ORD');

        Package_Group__c grp = new Package_Group__c(
            Name = 'Luxury Warranties', Active__c = true,
            Sort_Order__c = 4, Package_Color__c = '#B01D1A');
        insert grp;

        Dealer_Package__c dp = [
            SELECT Id FROM Dealer_Package__c WHERE Id = :f.dealerPackageId LIMIT 1
        ];
        dp.Plan_Type__c = grp.Id;
        update dp;

        Vehicle__c v = buildVehicle('ORD', '2022', 50000);
        Application__c app = buildApplication(f.dealer, v);

        Test.startTest();
        DealerPortalController.DealerPackagesResponse res = readPackages(app.Id);
        Test.stopTest();

        System.assertEquals(true, res.success, 'read should succeed: ' + res.message);
        System.assertNotEquals(null, res.data, 'packages expected');
        System.assertEquals(1, res.data.size(), 'the single eligible package must be returned');

        DealerPortalController.DealerPackageDTO pkg = res.data[0];
        System.assertEquals(grp.Id, pkg.planTypeId, 'plan type id must be the group');
        System.assertEquals(4, pkg.planTypeSortOrder.intValue(),
            'planTypeSortOrder must come from Plan_Type__r.Sort_Order__c');
        System.assertEquals('#B01D1A', pkg.planTypeColor,
            'planTypeColor must come from Plan_Type__r.Package_Color__c');
    }

    /**
     * A group with a blank Sort_Order__c / Package_Color__c must not break the
     * read (the LWC sorts null order last and falls back to the gradient class
     * when the colour is blank).
     */
    @IsTest
    static void blankSortOrderAndColor_NullSafe() {
        Fixture f = buildFixture('BLANK');

        Package_Group__c grp = new Package_Group__c(Name = 'Legacy Plan', Active__c = true);
        insert grp;

        Dealer_Package__c dp = [
            SELECT Id FROM Dealer_Package__c WHERE Id = :f.dealerPackageId LIMIT 1
        ];
        dp.Plan_Type__c = grp.Id;
        update dp;

        Vehicle__c v = buildVehicle('BLANK', '2022', 50000);
        Application__c app = buildApplication(f.dealer, v);

        Test.startTest();
        DealerPortalController.DealerPackagesResponse res = readPackages(app.Id);
        Test.stopTest();

        System.assertEquals(true, res.success,
            'read must still succeed when the group has no order / colour: ' + res.message);
        System.assertEquals(1, res.data.size(), 'the single eligible package must be returned');

        DealerPortalController.DealerPackageDTO pkg = res.data[0];
        System.assertEquals(true, pkg.planTypeSortOrder == null,
            'a blank Sort_Order__c must surface as null (the LWC sorts nulls last)');
        System.assert(String.isBlank(pkg.planTypeColor),
            'a blank Package_Color__c must surface blank (the LWC keeps the gradient fallback)');
    }

    // ------------------------------------------------------------------
    // TERM RESTRICTION TYPE (Unlimited odometer identified from data)
    // ------------------------------------------------------------------

    /**
     * An unlimited-odometer term is stored as Odometer_KM__c = null +
     * Restriction_Type__c = 'Unlimited'. The warranty tab must be able to tell
     * that apart from a genuinely missing cap, so Restriction_Type__c is carried
     * onto the term DTO. Without it the LWC would place the highest-coverage
     * term where a missing value goes.
     */
    @IsTest
    static void restrictionType_Surfaced_ForUnlimitedTerm() {
        Fixture f = buildFixture('UNL');

        Dealer_Package_Term__c term = [
            SELECT Id FROM Dealer_Package_Term__c WHERE Id = :f.dealerTermId LIMIT 1
        ];
        term.Restriction_Type__c = 'Unlimited';
        term.Odometer_KM__c = null; // unlimited terms carry no finite KM cap
        update term;

        Vehicle__c v = buildVehicle('UNL', '2022', 50000);
        Application__c app = buildApplication(f.dealer, v);

        Test.startTest();
        DealerPortalController.DealerPackagesResponse res = readPackages(app.Id);
        Test.stopTest();

        System.assertEquals(true, res.success, 'read should succeed: ' + res.message);
        System.assertEquals(1, res.data.size(), 'the single eligible package must be returned');

        DealerPortalController.DealerPackageDTO pkg = res.data[0];
        System.assertNotEquals(null, pkg.terms, 'flat terms expected');
        System.assertEquals(1, pkg.terms.size(), 'the eligible term must survive the eligibility gate');

        DealerPortalController.DealerPackageTermDTO t = pkg.terms[0];
        System.assertEquals('Unlimited', t.restrictionType,
            'restrictionType must come from Dealer_Package_Term__c.Restriction_Type__c');
        System.assertEquals(null, t.odometerKM,
            'an unlimited term carries no finite Odometer_KM__c cap');
    }

    // ------------------------------------------------------------------
    // SECTION ORDER: Sort_Order__c ascending, nulls last
    // ------------------------------------------------------------------

    /**
     * Two plan types / Package_Group__c records: one with Sort_Order__c = 1 and a
     * label that sorts EARLIER alphabetically ("Aaa..."), one with a NULL
     * Sort_Order__c and a label that sorts LATER ("Zzz..."). The Apex package
     * list is ordered by the group's Sort_Order__c ascending with nulls last, and
     * each DTO carries the group sort order + colour the warranty tab orders and
     * paints its sections from.
     *
     * The client-side section sort itself is exercised by
     * tests/lwc-order-harness.js (the LWC cannot run in an Apex test).
     */
    @IsTest
    static void sectionOrder_ByGroupSortOrder_AscendingNullsLast() {
        Account dealer = new Account(Name = 'DEALER ORD2',
            RecordTypeId = rt('Account', 'Dealer_Account'));
        insert dealer;

        Package_Group__c firstGroup = new Package_Group__c(
            Name = 'Aaa First By Order', Active__c = true,
            Sort_Order__c = 1, Package_Color__c = '#111111');
        Package_Group__c nullGroup = new Package_Group__c(
            Name = 'Zzz No Order', Active__c = true, Package_Color__c = '#222222');
        insert new List<Package_Group__c>{ firstGroup, nullGroup };

        Package__c masterFirst = new Package__c(
            Name = 'PKG FIRST', RecordTypeId = rt('Package__c', 'Extended_Limited_Warranty'),
            Package_Group__c = firstGroup.Id);
        Package__c masterNull = new Package__c(
            Name = 'PKG NULL', RecordTypeId = rt('Package__c', 'Extended_Limited_Warranty'),
            Package_Group__c = nullGroup.Id);
        insert new List<Package__c>{ masterFirst, masterNull };

        Dealer_Package__c dpFirst = new Dealer_Package__c(
            Name = 'DP FIRST', Dealer__c = dealer.Id, Package__c = masterFirst.Id,
            Plan_Type__c = firstGroup.Id,
            RecordTypeId = rt('Dealer_Package__c', 'Extended_Limited_Warranty'));
        Dealer_Package__c dpNull = new Dealer_Package__c(
            Name = 'DP NULL', Dealer__c = dealer.Id, Package__c = masterNull.Id,
            Plan_Type__c = nullGroup.Id,
            RecordTypeId = rt('Dealer_Package__c', 'Extended_Limited_Warranty'));
        insert new List<Dealer_Package__c>{ dpFirst, dpNull };

        Package_Term__c mtFirst = new Package_Term__c(Name = 'PT FIRST');
        Package_Term__c mtNull = new Package_Term__c(Name = 'PT NULL');
        insert new List<Package_Term__c>{ mtFirst, mtNull };

        insert new List<Dealer_Package_Term__c>{
            new Dealer_Package_Term__c(Name = 'DPT FIRST', Dealer_Package__c = dpFirst.Id,
                Package_Term__c = mtFirst.Id, Original_Package_Term_Cost__c = 1000, Markup__c = 0),
            new Dealer_Package_Term__c(Name = 'DPT NULL', Dealer_Package__c = dpNull.Id,
                Package_Term__c = mtNull.Id, Original_Package_Term_Cost__c = 1000, Markup__c = 0)
        };

        Vehicle__c v = buildVehicle('ORD2', '2022', 50000);
        Application__c app = buildApplication(dealer, v);

        Test.startTest();
        DealerPortalController.DealerPackagesResponse res = readPackages(app.Id);
        Test.stopTest();

        System.assertEquals(true, res.success, 'read should succeed: ' + res.message);
        System.assertNotEquals(null, res.data, 'packages expected');
        System.assertEquals(2, res.data.size(), 'both packages must be returned');

        // Sorted by the group's Sort_Order__c ascending, nulls last -- NOT by the
        // package/group label (Aaa would come first either way here, so the null
        // group is the discriminating case: its label sorts LAST and its order is
        // null, and it must land last).
        System.assertEquals(1, res.data[0].planTypeSortOrder.intValue(),
            'the package whose group has Sort_Order__c = 1 must come first');
        System.assertEquals(true, res.data[1].planTypeSortOrder == null,
            'the package whose group has a NULL Sort_Order__c must sort last');
        System.assertEquals(firstGroup.Id, res.data[0].planTypeId, 'ordered-first group id expected');
        System.assertEquals(nullGroup.Id, res.data[1].planTypeId, 'null-order group id expected');
        System.assertEquals('#111111', res.data[0].planTypeColor, 'ordered-first group colour expected');
        System.assertEquals('#222222', res.data[1].planTypeColor, 'null-order group colour expected');
    }

    // ------------------------------------------------------------------
    // PACKAGE ORDER WITHIN A SECTION: numeric per-claim, then deductible
    // ------------------------------------------------------------------

    /**
     * One plan type / Package_Group__c (Sort_Order__c = 2) holding four dealer
     * packages whose NAMES embed the raw amount -- "Essential / $10000 Per
     * Claim". A name-led (TEXT) sort would order them $1000, $10000, $1500 (the
     * reported defect); the read path must instead order them by the NUMERIC
     * per-claim limit, then the numeric deductible:
     *
     *   1000/100, 1500/50, 1500/100, 10000/100
     *
     * The two 1500 per-claim rows also prove the deductible is the secondary key.
     */
    @IsTest
    static void packageOrderWithinSection_ByNumericAmount_NotByName() {
        Account dealer = new Account(Name = 'DEALER PKGORD',
            RecordTypeId = rt('Account', 'Dealer_Account'));
        insert dealer;

        Package_Group__c grp = new Package_Group__c(
            Name = 'Essential PkgOrd', Active__c = true, Sort_Order__c = 2);
        insert grp;

        Package__c master = new Package__c(
            Name = 'PKG ESSENTIAL',
            RecordTypeId = rt('Package__c', 'Extended_Limited_Warranty'),
            Package_Group__c = grp.Id);
        insert master;

        // Names chosen so a TEXT sort is provably wrong: "$10000" sorts before
        // "$1500" (the 5th character is '0' vs '5').
        List<Dealer_Package__c> pkgs = new List<Dealer_Package__c>{
            new Dealer_Package__c(Name = 'Essential / $10000 Per Claim',
                Dealer__c = dealer.Id, Package__c = master.Id, Plan_Type__c = grp.Id,
                Per_Claim_Limit__c = 10000, Deductable__c = 100,
                RecordTypeId = rt('Dealer_Package__c', 'Extended_Limited_Warranty')),
            new Dealer_Package__c(Name = 'Essential / $1000 Per Claim',
                Dealer__c = dealer.Id, Package__c = master.Id, Plan_Type__c = grp.Id,
                Per_Claim_Limit__c = 1000, Deductable__c = 100,
                RecordTypeId = rt('Dealer_Package__c', 'Extended_Limited_Warranty')),
            new Dealer_Package__c(Name = 'Essential / $1500 Per Claim',
                Dealer__c = dealer.Id, Package__c = master.Id, Plan_Type__c = grp.Id,
                Per_Claim_Limit__c = 1500, Deductable__c = 100,
                RecordTypeId = rt('Dealer_Package__c', 'Extended_Limited_Warranty')),
            new Dealer_Package__c(Name = 'Essential / $1500 Low Deductible',
                Dealer__c = dealer.Id, Package__c = master.Id, Plan_Type__c = grp.Id,
                Per_Claim_Limit__c = 1500, Deductable__c = 50,
                RecordTypeId = rt('Dealer_Package__c', 'Extended_Limited_Warranty'))
        };
        insert pkgs;

        List<Dealer_Package_Term__c> terms = new List<Dealer_Package_Term__c>();
        for (Dealer_Package__c dp : pkgs) {
            Package_Term__c mt = new Package_Term__c(Name = 'PT ' + dp.Name);
            insert mt;
            terms.add(new Dealer_Package_Term__c(Name = 'DPT ' + dp.Name,
                Dealer_Package__c = dp.Id, Package_Term__c = mt.Id,
                Original_Package_Term_Cost__c = 1000.00, Markup__c = 0, Markup_Type__c = '$'));
        }
        insert terms;

        Vehicle__c v = buildVehicle('PKGORD', '2022', 50000);
        Application__c app = buildApplication(dealer, v);

        Test.startTest();
        DealerPortalController.DealerPackagesResponse res = readPackages(app.Id);
        Test.stopTest();

        System.assertEquals(true, res.success, 'read should succeed: ' + res.message);
        System.assertNotEquals(null, res.data, 'packages expected');
        System.assertEquals(4, res.data.size(), 'all four packages must be returned');

        // Numeric per-claim ascending; "$10000" must land LAST, not second.
        System.assertEquals(1000, res.data[0].perClaimLimit.intValue(),
            'first package must be the $1000 per-claim one');
        System.assertEquals(1500, res.data[1].perClaimLimit.intValue(),
            'second package must be a $1500 per-claim one');
        System.assertEquals(1500, res.data[2].perClaimLimit.intValue(),
            'third package must be a $1500 per-claim one');
        System.assertEquals(10000, res.data[3].perClaimLimit.intValue(),
            'the $10000 per-claim package must sort LAST');

        // Deductible is the secondary key: 1500/50 precedes 1500/100.
        System.assertEquals(50, res.data[1].deductible.intValue(),
            'the lower deductible must come first within equal per-claim');
        System.assertEquals(100, res.data[2].deductible.intValue(),
            'the higher deductible must come second within equal per-claim');

        // Guard the defect directly: a name-led (text) order would put the
        // five-digit amount at index 1, not index 3.
        System.assertEquals('Essential / $10000 Per Claim', res.data[3].PackageName,
            'the five-digit amount must not sort second by name');
    }
}