/**
 * DealerPackageTriggerHandlerTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Covers DealerPackageTriggerHandler + DealerPackageTrigger after the P2 rework
 * (change plan §04.2/§04.3/§11 P2): the insert fan-out is now an idempotent
 * reconcile through DealerPackageSyncService, and the trigger gained an
 * after-update re-sync path (master link change, flag-gated, re-entrancy
 * guarded).
 *
 * Mirrored content fields retired by P2 (Unit__c, Percentage__c,
 * Commercial_Eligible__c, Premium_Model_Fee__c, Min/Max_Finance_Term_In_Months__c,
 * Total_Loss_Coverage_Includes__c, Max_Liability_Limit__c, Loyalty_Credit__c,
 * Loan_Amount_Limit__c, Max_Collision_Deductible_Coverage__c,
 * Max_Vehicle_Age_Limit_In_Years__c) are no longer copied from the master.
 * Fields the portal still reads (Deductable__c, Per_Claim_Limit__c, …) are
 * refreshed so dealer copies stop going stale.
 */
@isTest(SeeAllData=false)
private class DealerPackageTriggerHandlerTest {

    @TestSetup
    static void setup() {
        // NOTE: no Account is created here — per-method dealers use distinct
        // identity fields to stay clear of the org's Account duplicate rule.
        Package__c elwPkg = TestDataFactory.createPackage('Extended_Limited_Warranty', true);
        // Enrich writable Currency/Decimal fields read by the sync header mirror.
        update new Package__c(
            Id                     = elwPkg.Id,
            Coverage_per_claim__c  = 500.00,
            Deductible__c          = 250.00
        );

        Package_Tier__c tier = TestDataFactory.createPackageTier(elwPkg.Id, true);
        TestDataFactory.createPackageTerm(elwPkg.Id, tier.Id, true);
    }

    /** Dealer with distinct identity fields (org Account duplicate rule is active). */
    private static Account createDistinctDealer(Integer n) {
        Account a = new Account(
            Name = 'P2 Handler Dealer ' + n + ' ' + Datetime.now().getTime(),
            RecordTypeId = TestDataFactory.getRecordTypeId('Account', 'Dealer_Account'),
            Phone = '4165550' + String.valueOf(100 + n),
            BillingStreet = 'Handler Street ' + n,
            BillingCity = 'Toronto', BillingState = 'ON', BillingCountry = 'Canada',
            BillingPostalCode = 'M5V 0A' + String.valueOf(n)
        );
        insert a;
        return a;
    }

    // ---------------------------------------------------------------------
    // Guard: null / no-package inserts do nothing
    // ---------------------------------------------------------------------

    @isTest
    static void test_nullPackageListIsSafe() {
        Test.startTest();
        DealerPackageTriggerHandler.onAfterInsert(null);
        DealerPackageTriggerHandler.onAfterInsert(new List<Dealer_Package__c>());
        DealerPackageTriggerHandler.onAfterUpdate(null, null);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Dealer_Package_Tier__c],
            'No tiers created for null/empty input');
        System.assertEquals(0, [SELECT COUNT() FROM Dealer_Package_Term__c],
            'No terms created for null/empty input');
    }

    // ---------------------------------------------------------------------
    // Trigger after-insert builds the mirror with retained structure fields
    // ---------------------------------------------------------------------

    @isTest
    static void test_afterInsertBuildsMirrorAndMapsRetainedFields() {
        Account dealer = createDistinctDealer(1);
        Package__c elwPkg = [
            SELECT Id, Name FROM Package__c WHERE RecordType.DeveloperName = 'Extended_Limited_Warranty' LIMIT 1
        ];

        Dealer_Package__c dp;
        Test.startTest();
        dp = TestDataFactory.createDealerPackage(dealer.Id, elwPkg.Id, 'Extended_Limited_Warranty', true);
        Test.stopTest();

        Dealer_Package__c refreshed = [
            SELECT Id, Name, Per_Claim_Limit__c, Deductable__c, Class__c
            FROM Dealer_Package__c WHERE Id = :dp.Id
        ];
        System.assertEquals(elwPkg.Name, refreshed.Name, 'Name mirrored from master package');
        System.assertEquals(500.00, refreshed.Per_Claim_Limit__c,
            'Per_Claim_Limit__c mirrored from Coverage_per_claim__c (retained portal field)');
        System.assertEquals(250.00, refreshed.Deductable__c,
            'Deductable__c mirrored from Deductible__c (retained portal field)');

        // Retired P2 mirror fields must NOT have been copied: they stay null.
        System.assertEquals(null, refreshed.Class__c,
            'Class__c null (master Class not set — copy semantics unchanged)');

        // Children exist exactly once.
        System.assertEquals(1, [SELECT COUNT() FROM Dealer_Package_Tier__c WHERE Dealer_Package__c = :dp.Id]);
        System.assertEquals(1, [SELECT COUNT() FROM Dealer_Package_Term__c WHERE Dealer_Package__c = :dp.Id]);
    }

    // ---------------------------------------------------------------------
    // Trigger after-update re-syncs when the master link changes
    // ---------------------------------------------------------------------

    @isTest
    static void test_afterUpdateOnMasterLinkChangeReconciles() {
        // Enable Dealer_Sync_Enabled__c (org defaults row) for the update path.
        insert new Aprotect_Portal_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Dealer_Sync_Enabled__c = true
        );

        Account dealer = createDistinctDealer(1);
        Package__c pkgA = [
            SELECT Id FROM Package__c WHERE RecordType.DeveloperName = 'Extended_Limited_Warranty' LIMIT 1
        ];
        Package__c pkgB = TestDataFactory.createPackage('Extended_Limited_Warranty', true);
        Package_Tier__c tierB = TestDataFactory.createPackageTier(pkgB.Id, true);
        Package_Term__c termB = TestDataFactory.createPackageTerm(pkgB.Id, tierB.Id, true);

        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkgA.Id, 'Extended_Limited_Warranty', true);
        System.assertEquals(1, [SELECT COUNT() FROM Dealer_Package_Term__c WHERE Dealer_Package__c = :dp.Id]);

        Test.startTest();
        // Reparent to pkgB → after-update path reconciles (creates B children;
        // never deletes the A children — sync contract).
        update new Dealer_Package__c(Id = dp.Id, Package__c = pkgB.Id);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Dealer_Package_Term__c
            WHERE Dealer_Package__c = :dp.Id AND Package_Term__c = :termB.Id],
            'Term mirror for new master created on reparent');
        System.assertEquals(2, [SELECT COUNT() FROM Dealer_Package_Term__c WHERE Dealer_Package__c = :dp.Id],
            'Old master children retained (sync never deletes)');

        // Re-run idempotency via another touch of the same record.
        update new Dealer_Package__c(Id = dp.Id, Name = dp.Name + ' (touch)');
        System.assertEquals(2, [SELECT COUNT() FROM Dealer_Package_Term__c WHERE Dealer_Package__c = :dp.Id],
            'No duplicates after non-master update');
    }

    // ---------------------------------------------------------------------
    // Trigger after-update is flag-gated and skips rollup-only updates
    // ---------------------------------------------------------------------

    @isTest
    static void test_afterUpdateSkipsWhenFlagOffOrMasterUnchanged() {
        Account dealer = createDistinctDealer(1);
        Package__c pkg = [
            SELECT Id FROM Package__c WHERE RecordType.DeveloperName = 'Extended_Limited_Warranty' LIMIT 1
        ];
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true);

        Map<Id, Dealer_Package__c> oldMap = new Map<Id, Dealer_Package__c>{
            dp.Id => new Dealer_Package__c(Id = dp.Id, Package__c = pkg.Id)
        };

        Test.startTest();
        // Flag is off by default → update path must not reconcile.
        DealerPackageTriggerHandler.onAfterUpdate(
            new List<Dealer_Package__c>{ new Dealer_Package__c(Id = dp.Id, Package__c = pkg.Id) },
            oldMap
        );
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Dealer_Package_Tier__c WHERE Dealer_Package__c = :dp.Id],
            'No extra tiers when flag off');
    }
}