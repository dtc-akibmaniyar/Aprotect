/**
 * DealerPackagePortalSharingTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Covers DealerPackagePortalSharing.shareDealerPackagesWithPortalUsers()
 * called via DealerPackageFileCopyTrigger (after insert on Dealer_Package__c)
 * and directly for guard-path testing.
 *
 * Handler behaviour under test:
 *   • Empty input list          → early exit, no shares created
 *   • All DPs have null Dealer__c → dealerAccountIds empty, early exit
 *   • Dealer has no portal users  → portalUsers empty, early exit
 *   • Dealer has one portal user  → Dealer_Package__Share (Read/Manual) created
 *                                    Package__Share (Read/Manual) created
 *   • Dealer has two portal users → two Dealer_Package__Share records created
 *
 * Test strategy:
 *   ✔ @isTest(SeeAllData=false)
 *   ✔ @TestSetup for shared Dealer + Package
 *   ✔ All data via TestDataFactory — no inline SObject creation
 *   ✔ Guard paths tested via direct static call (no trigger DML needed)
 *   ✔ Happy paths fire the trigger naturally via createDealerPackage(doInsert=true)
 *   ✔ Share assertions scoped to the specific Dealer_Package__c under test
 *   ✔ System.assert* with descriptive messages on every assertion
 */
@isTest(SeeAllData=false)
private class DealerPackagePortalSharingTest {

    // ─────────────────────────────────────────────────────────────────────────
    // @TestSetup — shared Dealer + Package (no Package_Tier/Term/Option so
    // DealerPackageTrigger exits early without creating child records)
    // No portal user in @TestSetup — some tests require the dealer to have none.
    // ─────────────────────────────────────────────────────────────────────────

    @TestSetup
    static void setup() {
        TestDataFactory.createDealer(true);
        TestDataFactory.createPackage('Extended_Limited_Warranty', true);
    }

    // ── Private query helpers ─────────────────────────────────────────────────

    private static Account getDealer() {
        return [SELECT Id FROM Account LIMIT 1];
    }

    private static Package__c getPkg() {
        return [SELECT Id FROM Package__c LIMIT 1];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GUARD PATHS  (direct static call — no DML trigger needed)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Empty input list → loop never executes → dealerAccountIds is empty →
     * handler returns early; no Dealer_Package__Share created.
     */
    @isTest
    static void testEmptyList_noSharesCreated() {
        Test.startTest();
        DealerPackagePortalSharing.shareDealerPackagesWithPortalUsers(
            new List<Dealer_Package__c>()
        );
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Dealer_Package__Share WHERE RowCause = 'Manual'],
            'No Dealer_Package__Share records should be created for an empty input list'
        );
    }

    /**
     * All DPs in the list have Dealer__c = null → dealerAccountIds stays empty →
     * handler returns early; no shares created.
     */
    @isTest
    static void testNullDealerAccount_earlyReturn() {
        // Factory with doInsert=false produces an in-memory DP with Dealer__c = null
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            null, null, 'Extended_Limited_Warranty', false
        );

        Test.startTest();
        DealerPackagePortalSharing.shareDealerPackagesWithPortalUsers(
            new List<Dealer_Package__c>{ dp }
        );
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Dealer_Package__Share WHERE RowCause = 'Manual'],
            'No shares should be created when all DPs have a null Dealer__c'
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // NO PORTAL USERS PATH
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Dealer has no portal users → portalUsers query returns empty list →
     * handler returns early; no Dealer_Package__Share created for the DP.
     */
    @isTest
    static void testNoPortalUsers_noSharesCreated() {
        Account    dealer = getDealer();
        Package__c pkg    = getPkg();
        // No portal user linked to this dealer — handler must find none

        Test.startTest();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true
        );
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Dealer_Package__Share
             WHERE ParentId = :dp.Id AND RowCause = 'Manual'],
            'No Dealer_Package__Share should be created when the dealer has no portal users'
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PORTAL USER EXISTS — SHARE CREATION PATHS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Dealer has one portal user → handler creates one Dealer_Package__Share
     * (AccessLevel = Read, RowCause = Manual) for that user.
     */
    @isTest
    static void testPortalUser_dealerPackageShareCreated() {
        Account    dealer     = getDealer();
        Package__c pkg        = getPkg();
        User       portalUser = TestDataFactory.createPortalUser(dealer.Id, true);

        Test.startTest();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true
        );
        Test.stopTest();

        List<Dealer_Package__Share> shares = [
            SELECT Id, UserOrGroupId, AccessLevel
            FROM   Dealer_Package__Share
            WHERE  ParentId = :dp.Id
            AND    RowCause = 'Manual'
        ];
        System.assertEquals(1, shares.size(),
            'One Dealer_Package__Share should be created for the portal user');
        System.assertEquals(portalUser.Id, shares[0].UserOrGroupId,
            'The Dealer_Package__Share should be granted to the portal user');
        System.assertEquals('Read', shares[0].AccessLevel,
            'The Dealer_Package__Share access level should be Read');
    }

    /**
     * Dealer has one portal user → handler also creates one Package__Share
     * (AccessLevel = Read, RowCause = Manual) to enable ControlledByParent access.
     */
    @isTest
    static void testPortalUser_packageShareCreated() {
        Account    dealer     = getDealer();
        Package__c pkg        = getPkg();
        User       portalUser = TestDataFactory.createPortalUser(dealer.Id, true);

        Test.startTest();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true
        );
        Test.stopTest();

        List<Package__Share> shares = [
            SELECT Id, UserOrGroupId, AccessLevel
            FROM   Package__Share
            WHERE  ParentId = :pkg.Id
            AND    RowCause = 'Manual'
        ];
        System.assertEquals(1, shares.size(),
            'One Package__Share should be created for the portal user');
        System.assertEquals(portalUser.Id, shares[0].UserOrGroupId,
            'The Package__Share should be granted to the portal user');
        System.assertEquals('Read', shares[0].AccessLevel,
            'The Package__Share access level should be Read');
    }

    /**
     * Dealer has two portal users → handler creates two Dealer_Package__Share
     * records — one for each user.
     */
    @isTest
    static void testMultiplePortalUsers_multipleSharesCreated() {
        Account    dealer      = getDealer();
        Package__c pkg         = getPkg();
        User       portalUser1 = TestDataFactory.createPortalUser(dealer.Id, true);
        User       portalUser2 = TestDataFactory.createPortalUser(dealer.Id, true);

        Test.startTest();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true
        );
        Test.stopTest();

        List<Dealer_Package__Share> shares = [
            SELECT Id, UserOrGroupId
            FROM   Dealer_Package__Share
            WHERE  ParentId = :dp.Id
            AND    RowCause = 'Manual'
        ];
        System.assertEquals(2, shares.size(),
            'Two Dealer_Package__Share records should be created — one per portal user');

        Set<Id> sharedUserIds = new Set<Id>();
        for (Dealer_Package__Share s : shares) {
            sharedUserIds.add(s.UserOrGroupId);
        }
        System.assert(sharedUserIds.contains(portalUser1.Id),
            'Dealer_Package__Share should include portal user 1');
        System.assert(sharedUserIds.contains(portalUser2.Id),
            'Dealer_Package__Share should include portal user 2');
    }
}