/**
 * DealerPortalTierOptInTest
 *
 * P7-f — tier-OPT-IN change set (owner decision D1 = opt-in; spec §9 locked).
 * Covers C2 (eligibility: R3 tier-band precedence + R1 term-level odometer
 * fallback + R2 age) and C3 (tier-less warranty terms render on the flat
 * dto.terms list, no synthetic "Tier null" group), plus C6 parity.
 *
 * Everything is exercised end-to-end through the public read path
 * DealerPortalController.getDealerPackages (the only consumer of
 * isWarrantyTermEligible) and the public selection path
 * createApplicationPackageWithoutSharing. The dealer mirror is built by the
 * real sync fan-out (Dealer_Package__c after-insert → reconcile), so these
 * tests also exercise C1 (tier-less master terms mirrored with a null tier).
 *
 * Owner-locked rules under test (spec §9):
 *   • R1: a tier-less (or empty-band) term is capped by its own
 *     Odometer_KM__c — reject strictly above; boundary inclusive.
 *   • R1 skip: only Restriction_Type__c = 'Unlimited' skips the cap.
 *     ROLLING ODOMETER IS NOT SKIPPED (validated like Fixed).
 *   • R2: ByYear__c age limit, existing dealer-level convention
 *     (Date.today().year() - Vehicle__r.Year__c; reject when > ByYear__c).
 *   • R3: when the term's tier is linked + resolved + band-populated, the
 *     TIER BAND governs and the term's own Odometer_KM__c is NOT consulted.
 *   • Tier linked but band empty → fall through to the term-level check.
 *   • Tier linked but unresolved → ineligible (unchanged).
 */
@isTest(SeeAllData=false)
private class DealerPortalTierOptInTest {

    private static final String ELW = 'Extended_Limited_Warranty';
    private static Integer seq = 0;
    private static Integer nextSeq() { seq++; return seq; }

    // ------------------------------------------------------------------
    // Fixtures
    // ------------------------------------------------------------------

    private static Account mkDealer(String tag) {
        Integer n = nextSeq();
        String uniq = tag + '-' + Datetime.now().getTime() + '-' + n;
        Account a = new Account(
            Name = 'P7F Dealer ' + uniq,
            RecordTypeId = TestDataFactory.getRecordTypeId('Account', 'Dealer_Account'),
            Phone = '416555' + String.valueOf(1000 + n),
            BillingStreet = 'Street ' + uniq,
            BillingCity = 'Toronto', BillingState = 'ON',
            BillingCountry = 'Canada', BillingPostalCode = 'M5V 0A' + Math.mod(n, 10)
        );
        insert a;
        return a;
    }

    /** Vehicle with the reading the eligibility math consumes (KM). */
    private static Vehicle__c mkVehicle(String year, Decimal odo, String unit) {
        Vehicle__c v = new Vehicle__c(
            Name = 'P7F Vehicle ' + Datetime.now().getTime() + '-' + nextSeq(),
            Year__c = year,
            Odometer__c = odo,
            Odometer_Unit__c = unit,
            Usage_Type__c = 'Personal Use'
        );
        insert v;
        return v;
    }

    private static Application__c mkApp(Account d, Vehicle__c v) {
        Application__c a = new Application__c(
            Dealer_Name__c = d.Id,
            Vehicle__c = v.Id,
            RecordTypeId = TestDataFactory.getRecordTypeId('Application__c', 'Application'),
            Application_Status__c = 'Draft',
            Payment_Status__c = 'Unpaid'
        );
        insert a;
        return a;
    }

    private static Package__c mkMasterPkg() {
        Package__c p = TestDataFactory.createPackage(ELW, true);
        update new Package__c(Id = p.Id, Is_Active__c = true);
        return p;
    }

    private static Package_Tier__c mkMasterTier(Id pkgId, Decimal startKm, Decimal endKm) {
        Package_Tier__c t = new Package_Tier__c(
            Name = 'P7F Tier ' + nextSeq(),
            Package__c = pkgId,
            Mileage_Restriction_Start__c = startKm,
            Mileage_Restriction_End__c = endKm,
            Mileage_Unit__c = 'KM'
        );
        insert t;
        return t;
    }

    /** Master term. tierId null → tier-less (C1); otherwise the tiered path. */
    private static Package_Term__c mkMasterTerm(Id pkgId, Id tierId, Decimal odoKm, String restriction, Decimal byYear) {
        Package_Term__c t = new Package_Term__c(
            Name = 'P7F Term ' + nextSeq(),
            Package__c = pkgId,
            Package_Tier__c = tierId,
            Price__c = 1000.00,
            Month__c = '24',
            Odometer_KM__c = odoKm,
            Restriction_Type__c = restriction,
            ByYear__c = byYear
        );
        insert t;
        return t;
    }

    /** Build the mirror via the real fan-out (after-insert → reconcile). */
    private static Dealer_Package__c mkMirror(Account d, Package__c pkg) {
        return TestDataFactory.createDealerPackage(d.Id, pkg.Id, ELW, true);
    }

    private static DealerPortalController.DealerPackagesResponse render(Id appId) {
        return DealerPortalController.getDealerPackages(appId, ELW);
    }

    private static DealerPortalController.DealerPackageDTO pkgById(
        DealerPortalController.DealerPackagesResponse r, Id dealerPackageId
    ) {
        if (r == null || r.data == null) return null;
        for (DealerPortalController.DealerPackageDTO p : r.data) {
            if (p.Id == dealerPackageId) return p;
        }
        return null;
    }

    private static Integer termCount(DealerPortalController.DealerPackageDTO p) {
        return p == null || p.terms == null ? 0 : p.terms.size();
    }

    // ------------------------------------------------------------------
    // C2 / R1 — term-level odometer cap on the fallback
    // ------------------------------------------------------------------

    @isTest
    static void test_tierlessTermEligibleByTermAttributes() {
        Account d = mkDealer('A');
        Application__c app = mkApp(d, mkVehicle('2026', 50000, 'KM'));
        Package__c pkg = mkMasterPkg();
        // at cap (60,000 ≥ 50,000), Fixed Odometer, no age limit.
        mkMasterTerm(pkg.Id, null, 60000, 'Fixed Odometer', null);
        Dealer_Package__c dp = mkMirror(d, pkg);

        DealerPortalController.DealerPackagesResponse r = render(app.Id);
        DealerPortalController.DealerPackageDTO p = pkgById(r, dp.Id);
        System.assertNotEquals(null, p, 'Tier-less term within its cap must render the package');
        System.assertEquals(1, termCount(p), 'One tier-less term expected');
        System.assertEquals(0, p.tiers.size(), 'No synthetic tier group for tier-less warranty terms');
    }

    @isTest
    static void test_tierlessFixedOdometerTermRejectedWhenVehicleAboveCap() {
        Account d = mkDealer('B');
        Application__c app = mkApp(d, mkVehicle('2026', 50000, 'KM'));
        Package__c pkg = mkMasterPkg();
        mkMasterTerm(pkg.Id, null, 40000, 'Fixed Odometer', null); // cap below the reading
        Dealer_Package__c dp = mkMirror(d, pkg);

        DealerPortalController.DealerPackagesResponse r = render(app.Id);
        System.assertEquals(null, pkgById(r, dp.Id),
            'A tier-less Fixed Odometer term capped below the reading must be excluded (R1)');
    }

    @isTest
    static void test_tierlessUnlimitedTermSkipsOdometer() {
        Account d = mkDealer('C');
        Application__c app = mkApp(d, mkVehicle('2026', 50000, 'KM'));
        Package__c pkg = mkMasterPkg();
        mkMasterTerm(pkg.Id, null, null, 'Unlimited', null);
        Dealer_Package__c dp = mkMirror(d, pkg);

        DealerPortalController.DealerPackagesResponse r = render(app.Id);
        System.assertNotEquals(null, pkgById(r, dp.Id),
            'Unlimited skips the term-level odometer cap (R1)');
    }

    @isTest
    static void test_tierlessRollingOdometerIsCappedNotSkipped() {
        Account d = mkDealer('D');
        Application__c app = mkApp(d, mkVehicle('2026', 50000, 'KM'));
        Package__c pkg = mkMasterPkg();
        // Owner-locked: Rolling is validated like Fixed (NOT skipped).
        mkMasterTerm(pkg.Id, null, 40000, 'Rolling Odometer', null);
        Dealer_Package__c dp = mkMirror(d, pkg);

        DealerPortalController.DealerPackagesResponse r = render(app.Id);
        System.assertEquals(null, pkgById(r, dp.Id),
            'Rolling Odometer is NOT skipped on the fallback — cap 40,000 excludes a 50,000 km vehicle');
    }

    @isTest
    static void test_tierlessTermRejectedByOwnByYear() {
        Integer oldYear = Date.today().year() - 5;
        Account d = mkDealer('E');
        Application__c app = mkApp(d, mkVehicle(String.valueOf(oldYear), 10000, 'KM'));
        Package__c pkg = mkMasterPkg();
        // Odometer fine; ByYear 2 rejects a 5-year-old vehicle (R2, existing convention).
        mkMasterTerm(pkg.Id, null, 90000, 'Fixed Odometer', 2);
        Dealer_Package__c dp = mkMirror(d, pkg);

        DealerPortalController.DealerPackagesResponse r = render(app.Id);
        System.assertEquals(null, pkgById(r, dp.Id),
            'Term-level ByYear__c age limit must reject a vehicle older than the limit (R2)');
    }

    @isTest
    static void test_tierlessTermAgeBoundaryIsInclusive() {
        Integer year = Date.today().year() - 2;
        Account d = mkDealer('E2');
        Application__c app = mkApp(d, mkVehicle(String.valueOf(year), 10000, 'KM'));
        Package__c pkg = mkMasterPkg();
        mkMasterTerm(pkg.Id, null, 90000, 'Fixed Odometer', 2); // age == limit passes
        Dealer_Package__c dp = mkMirror(d, pkg);

        System.assertNotEquals(null, pkgById(render(app.Id), dp.Id),
            'Age == ByYear__c must pass (inclusive boundary)');
    }

    // ------------------------------------------------------------------
    // C2 / R3 — tier band precedence
    // ------------------------------------------------------------------

    @isTest
    static void test_tieredTermStillBanded() {
        Account d = mkDealer('F');
        Application__c app = mkApp(d, mkVehicle('2026', 50000, 'KM')); // 50,000 km
        Package__c pkg = mkMasterPkg();
        // Band starts at 60,001 → a 50,000 km vehicle is below the band.
        Package_Tier__c tier = mkMasterTier(pkg.Id, 60001, 100000);
        mkMasterTerm(pkg.Id, tier.Id, null, 'Unlimited', null);
        Dealer_Package__c dp = mkMirror(d, pkg);

        System.assertEquals(null, pkgById(render(app.Id), dp.Id),
            'Tiered term below the band start stays ineligible (no regression)');
    }

    @isTest
    static void test_tieredTermIgnoresOwnOdometerCap() {
        Account d = mkDealer('G');
        Application__c app = mkApp(d, mkVehicle('2026', 50000, 'KM'));
        Package__c pkg = mkMasterPkg();
        Package_Tier__c tier = mkMasterTier(pkg.Id, 0, 60000); // 0–60,000 km band
        // Term's own cap (40,000) is BELOW the reading — but R3 says the band wins.
        mkMasterTerm(pkg.Id, tier.Id, 40000, 'Fixed Odometer', null);
        Dealer_Package__c dp = mkMirror(d, pkg);

        DealerPortalController.DealerPackagesResponse r = render(app.Id);
        DealerPortalController.DealerPackageDTO p = pkgById(r, dp.Id);
        System.assertNotEquals(null, p,
            'R3 precedence: a tiered term inside its tier band is eligible and its own cap is NOT consulted');
        System.assertEquals(1, p.tiers.size(), 'Tiered term renders under its tier');
        System.assertEquals(1, p.tiers[0].terms.size(), 'One term in the band');
    }

    @isTest
    static void test_tierWithEmptyBandFallsBackToTermCap() {
        Account d = mkDealer('H');
        Application__c app = mkApp(d, mkVehicle('2026', 50000, 'KM'));
        Package__c pkg = mkMasterPkg();
        // Tier linked + resolved but with NO band values → fall through to R1.
        Package_Tier__c tier = mkMasterTier(pkg.Id, null, null);
        mkMasterTerm(pkg.Id, tier.Id, 40000, 'Fixed Odometer', null);
        Dealer_Package__c dp = mkMirror(d, pkg);

        System.assertEquals(null, pkgById(render(app.Id), dp.Id),
            'Empty-band tier falls through to the term-level cap → 40,000 excludes 50,000 km (R3 fall-through)');
    }

    @isTest
    static void test_tierWithEmptyBandTermWithinCapRenders() {
        Account d = mkDealer('H2');
        Application__c app = mkApp(d, mkVehicle('2026', 50000, 'KM'));
        Package__c pkg = mkMasterPkg();
        Package_Tier__c tier = mkMasterTier(pkg.Id, null, null);
        mkMasterTerm(pkg.Id, tier.Id, 90000, 'Fixed Odometer', null); // within cap
        Dealer_Package__c dp = mkMirror(d, pkg);

        DealerPortalController.DealerPackageDTO p = pkgById(render(app.Id), dp.Id);
        System.assertNotEquals(null, p, 'Empty-band tier within the term cap must render');
        System.assertEquals(1, p.tiers.size(), 'Still grouped under the (empty-band) tier it is linked to');
    }

    // ------------------------------------------------------------------
    // C3 — flat rendering / grouping
    // ------------------------------------------------------------------

    @isTest
    static void test_tierlessPackageReturnsFlatTerms() {
        Account d = mkDealer('I');
        Application__c app = mkApp(d, mkVehicle('2026', 50000, 'KM'));
        Package__c pkg = mkMasterPkg();
        mkMasterTerm(pkg.Id, null, 60000, 'Fixed Odometer', null);
        mkMasterTerm(pkg.Id, null, null, 'Unlimited', null);
        Dealer_Package__c dp = mkMirror(d, pkg);

        DealerPortalController.DealerPackageDTO p = pkgById(render(app.Id), dp.Id);
        System.assertNotEquals(null, p, 'Tier-less package must render');
        System.assertEquals(2, termCount(p), 'Both tier-less terms render on the flat list');
        System.assertEquals(0, p.tiers.size(), 'No tiers on a tier-less-only package');
    }

    @isTest
    static void test_tieredPackageStillReturnsTiers() {
        Account d = mkDealer('J');
        Application__c app = mkApp(d, mkVehicle('2026', 50000, 'KM'));
        Package__c pkg = mkMasterPkg();
        Package_Tier__c tier = mkMasterTier(pkg.Id, 0, 60000);
        mkMasterTerm(pkg.Id, tier.Id, null, 'Unlimited', null);
        Dealer_Package__c dp = mkMirror(d, pkg);

        DealerPortalController.DealerPackageDTO p = pkgById(render(app.Id), dp.Id);
        System.assertNotEquals(null, p);
        System.assertEquals(1, p.tiers.size(), 'Tiered package still renders its tier group');
        System.assertEquals(1, p.tiers[0].terms.size(), 'One term under the tier');
        System.assertEquals(1, termCount(p), 'Flat list kept for backward compatibility');
    }

    @isTest
    static void test_mixedPackageNoSilentDrop() {
        Account d = mkDealer('K');
        Application__c app = mkApp(d, mkVehicle('2026', 50000, 'KM'));
        Package__c pkg = mkMasterPkg();
        Package_Tier__c tier = mkMasterTier(pkg.Id, 0, 60000);
        mkMasterTerm(pkg.Id, tier.Id, null, 'Unlimited', null);   // tiered
        mkMasterTerm(pkg.Id, null, 90000, 'Fixed Odometer', null); // tier-less
        Dealer_Package__c dp = mkMirror(d, pkg);

        DealerPortalController.DealerPackageDTO p = pkgById(render(app.Id), dp.Id);
        System.assertNotEquals(null, p);
        // Documented mixed-package contract: hasTiers=true → the LWC renders the
        // tier group; the tier-less term is present on the flat list (dto.terms)
        // but is not rendered while tiers exist. No V25 package mixes the two.
        System.assertEquals(1, p.tiers.size(), 'Tier group present');
        System.assertEquals(1, p.tiers[0].terms.size(), 'Tier group carries the tiered term only');
        System.assertEquals(2, termCount(p), 'Flat list carries BOTH terms (tiered + tier-less)');
    }

    // ------------------------------------------------------------------
    // C6 — pricing/selection parity for a tier-less term
    // ------------------------------------------------------------------

    @isTest
    static void test_tierlessTermSelectionSnapshotKeepsNullTierAndStoresPrice() {
        Account d = mkDealer('L');
        Vehicle__c v = mkVehicle('2026', 50000, 'KM');
        Application__c app = mkApp(d, v);
        Package__c pkg = mkMasterPkg();
        mkMasterTerm(pkg.Id, null, 60000, 'Fixed Odometer', null);
        Dealer_Package__c dp = mkMirror(d, pkg);

        Dealer_Package_Term__c dterm = [
            SELECT Id, Dealer_Package_Tier__c, Package_Tier__c, Original_Package_Term_Cost__c
            FROM Dealer_Package_Term__c WHERE Dealer_Package__c = :dp.Id LIMIT 1
        ];
        System.assertEquals(null, dterm.Dealer_Package_Tier__c, 'Mirror term is tier-less');

        // Select the tier-less term → the snapshot must persist the dealer term
        // and keep both tier lookups null (guard tolerates null), then price it.
        // Portal, PDF and invoice all derive from this one snapshot → parity.
        Test.startTest();
        String appPkgId = DealerPortalController.createApplicationPackageWithoutSharing(
            app.Id, d.Id, dp.Id, pkg.Name, dterm.Id, 100, ELW);
        Test.stopTest();
        System.assertNotEquals(null, appPkgId, 'Tier-less term selection must succeed');

        Application_Package__c snap = [
            SELECT Id, Dealer_Package_Term__c, Dealer_Package_Tier__c, Package_Tier__c
            FROM Application_Package__c WHERE Id = :appPkgId
        ];
        System.assertEquals(dterm.Id, snap.Dealer_Package_Term__c, 'Snapshot keys on the dealer term');
        System.assertEquals(null, snap.Dealer_Package_Tier__c, 'Tier field stays null for a tier-less term');
        System.assertEquals(null, snap.Package_Tier__c, 'Master tier field stays null for a tier-less term');

        String upd = DealerPortalController.updateApplicationPackageWithoutSharing(
            appPkgId, dterm.Id, 1234.00, 200.00, 100);
        System.assertEquals(appPkgId, upd, 'Price update on a tier-less snapshot must succeed');
        System.assertEquals(1234.00, [
            SELECT Dealer_Package_Price__c FROM Application_Package__c WHERE Id = :appPkgId
        ].Dealer_Package_Price__c, 'Stored price is the single source for portal / PDF / invoice');
    }

}