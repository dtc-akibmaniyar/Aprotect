/**
 * DealerPackageFileCopyHandlerTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Covers DealerPackageFileCopyHandler.handleAfterInsert() via the
 * DealerPackageFileCopyTrigger (after insert on Dealer_Package__c) and via a
 * direct static call for the empty-list guard.
 *
 * Handler behaviour under test:
 *   • Empty Dealer_Package list     → no-op, no Package_File__c created
 *   • Dealer has no file attachments → no Package_File__c created (guard)
 *   • Dealer has a logo CDL          → Package_File__c (File_Type = 'Dealer Logo')
 *                                       created + CDL re-linked
 *   • Package has a Package_File__c with a CDL attachment
 *       – File_Type_del__c set       → preserved on the copy
 *       – File_Type_del__c = null    → defaults to 'Package Brochure'
 *   • Package has a Package_File__c with NO CDL → no Package_File__c created
 *   • Both dealer logo and package brochure present → both Package_File__c created
 *
 * File setup pattern:
 *   ContentVersion.FirstPublishLocationId = entity.Id
 *   → Salesforce auto-creates ContentDocument + ContentDocumentLink to entity
 *   → handler's getFilesForEntities / getPackageFilesWithAttachments find it
 *
 * Test Strategy:
 *   ✔ @isTest(SeeAllData=false)
 *   ✔ @TestSetup for shared Dealer + Package
 *   ✔ All data exclusively via TestDataFactory — no inline SObject creation
 *   ✔ Trigger fires naturally on Dealer_Package__c insert (no direct handler call
 *     except for the empty-list guard)
 *   ✔ Assertions scoped to the specific Dealer_Package__c under test
 *   ✔ System.assert* with descriptive messages on every assertion
 *   ✔ No hardcoded Ids
 */
@isTest(SeeAllData=false)
private class DealerPackageFileCopyHandlerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // @TestSetup — shared Dealer + Package (no Package_Tier/Term/Option so
    // DealerPackageTrigger exits early without creating child records)
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
    // EMPTY-LIST GUARD
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Empty list → handler processes nothing; no Package_File__c created.
     */
    @isTest
    static void testEmptyList_handlerNoOp() {
        Test.startTest();
        DealerPackageFileCopyHandler.handleAfterInsert(new List<Dealer_Package__c>());
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Package_File__c],
            'No Package_File__c should be created when the input list is empty');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DEALER LOGO PATH
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Dealer account has no ContentDocumentLinks → handler finds no logo files;
     * no Package_File__c created for the Dealer_Package.
     */
    @isTest
    static void testDealerHasNoFiles_noPackageFileCreated() {
        Account    dealer = getDealer();
        Package__c pkg    = getPkg();
        // No ContentVersion linked to dealer — no CDL will be found

        Test.startTest();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true
        );
        Test.stopTest();

        System.assertEquals(0,
            [SELECT COUNT() FROM Package_File__c WHERE Dealer_Package__c = :dp.Id],
            'No Package_File__c should be created when the dealer has no file attachments');
    }

    /**
     * Dealer account has one ContentDocumentLink (logo) → handler creates one
     * Package_File__c with File_Type_del__c = 'Dealer Logo' for the Dealer_Package.
     */
    @isTest
    static void testDealerLogo_createsPackageFileWithDealerLogoType() {
        Account    dealer = getDealer();
        Package__c pkg    = getPkg();
        // ContentVersion linked to dealer auto-creates CDL for dealer
        TestDataFactory.createContentVersion(dealer.Id, 'Dealer Logo', true);

        Test.startTest();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true
        );
        Test.stopTest();

        List<Package_File__c> pfs = [
            SELECT Id, File_Type_del__c
            FROM   Package_File__c
            WHERE  Dealer_Package__c = :dp.Id
        ];
        System.assertEquals(1, pfs.size(),
            'One Package_File__c should be created for the dealer logo');
        System.assertEquals('Dealer Logo', pfs[0].File_Type_del__c,
            'File_Type_del__c should be "Dealer Logo" for files copied from the dealer account');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PACKAGE BROCHURE PATH
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Package has a Package_File__c (Dealer_Package__c = null) with one CDL
     * and an explicit File_Type_del__c → that type is preserved on the copy.
     */
    @isTest
    static void testPackageBrochure_preservesFileType() {
        Account    dealer = getDealer();
        Package__c pkg    = getPkg();
        // Source Package_File__c at package level with explicit file type
        Package_File__c srcPf = TestDataFactory.createPackageFile(
            pkg.Id, null, 'Package Brochure', true
        );
        // ContentVersion linked to the source Package_File__c → auto-creates CDL
        TestDataFactory.createContentVersion(srcPf.Id, 'Brochure', true);

        Test.startTest();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true
        );
        Test.stopTest();

        List<Package_File__c> pfs = [
            SELECT Id, File_Type_del__c
            FROM   Package_File__c
            WHERE  Dealer_Package__c = :dp.Id
        ];
        System.assertEquals(1, pfs.size(),
            'One Package_File__c should be created for the package brochure');
        System.assertEquals('Package Brochure', pfs[0].File_Type_del__c,
            'File_Type_del__c should be preserved from the source Package_File__c');
    }

    /**
     * Package_File__c.File_Type_del__c is null → handler defaults to
     * 'Package Brochure' on the copied Dealer_Package record.
     */
    @isTest
    static void testPackageFileNullType_defaultsToPackageBrochure() {
        Account    dealer = getDealer();
        Package__c pkg    = getPkg();
        // Source Package_File__c with null File_Type_del__c
        Package_File__c srcPf = TestDataFactory.createPackageFile(
            pkg.Id, null, null, true
        );
        TestDataFactory.createContentVersion(srcPf.Id, 'Brochure', true);

        Test.startTest();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true
        );
        Test.stopTest();

        List<Package_File__c> pfs = [
            SELECT Id, File_Type_del__c
            FROM   Package_File__c
            WHERE  Dealer_Package__c = :dp.Id
        ];
        System.assertEquals(1, pfs.size(),
            'One Package_File__c should be created even when source File_Type_del__c is null');
        System.assertEquals('Package Brochure', pfs[0].File_Type_del__c,
            'File_Type_del__c should default to "Package Brochure" when source type is null');
    }

    /**
     * Package has a Package_File__c with no ContentDocumentLinks attached →
     * the inner CDL loop is empty; no Package_File__c created for the Dealer_Package.
     */
    @isTest
    static void testPackageFileWithNoAttachments_noPackageFileCreated() {
        Account    dealer = getDealer();
        Package__c pkg    = getPkg();
        // Source Package_File__c exists but no ContentVersion linked to it
        TestDataFactory.createPackageFile(pkg.Id, null, 'Package Brochure', true);

        Test.startTest();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true
        );
        Test.stopTest();

        System.assertEquals(0,
            [SELECT COUNT() FROM Package_File__c WHERE Dealer_Package__c = :dp.Id],
            'No Package_File__c should be created when the source Package_File__c has no attached files');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // BOTH PATHS ACTIVE
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Dealer has a logo file AND Package has a brochure file → handler creates
     * two Package_File__c records for the Dealer_Package (one of each type).
     */
    @isTest
    static void testBothDealerLogoAndPackageBrochure_bothCopied() {
        Account    dealer = getDealer();
        Package__c pkg    = getPkg();
        // Dealer logo
        TestDataFactory.createContentVersion(dealer.Id, 'Dealer Logo', true);
        // Package brochure
        Package_File__c srcPf = TestDataFactory.createPackageFile(
            pkg.Id, null, 'Package Brochure', true
        );
        TestDataFactory.createContentVersion(srcPf.Id, 'Brochure', true);

        Test.startTest();
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealer.Id, pkg.Id, 'Extended_Limited_Warranty', true
        );
        Test.stopTest();

        List<Package_File__c> pfs = [
            SELECT Id, File_Type_del__c
            FROM   Package_File__c
            WHERE  Dealer_Package__c = :dp.Id
            ORDER BY File_Type_del__c
        ];
        System.assertEquals(2, pfs.size(),
            'Two Package_File__c records should be created — one logo and one brochure');

        Set<String> types = new Set<String>();
        for (Package_File__c pf : pfs) {
            types.add(pf.File_Type_del__c);
        }
        System.assert(types.contains('Dealer Logo'),
            'One Package_File__c should have File_Type_del__c = "Dealer Logo"');
        System.assert(types.contains('Package Brochure'),
            'One Package_File__c should have File_Type_del__c = "Package Brochure"');
    }
}