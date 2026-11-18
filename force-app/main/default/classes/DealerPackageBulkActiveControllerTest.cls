/**
 * DealerPackageBulkActiveControllerTest
 *
 * The dealer pane's bulk Active / Inactive save (selection → saved state):
 *   • activate + deactivate in ONE save (single DML),
 *   • idempotent — a save with nothing changed writes nothing,
 *   • a package that is not on this dealer (or has no mirror) is reported,
 *     never created and never written,
 *   • the feature flag gate,
 *   • a non-dealer account is refused,
 *   • field-level update access is asserted (read-only user is refused),
 *   • malformed JSON is a non-fatal no-op.
 *
 * The payload is a JSON STRING now (not a typed Apex list). Each test builds
 * the exact wire shape the console sends:
 *   [ { "dealerPackageId": "a0X...", "active": true|false }, ... ]
 */
@isTest(SeeAllData=false)
private class DealerPackageBulkActiveControllerTest {

    @TestSetup
    static void setup() {
        Account dealer = TestDataFactory.createDealer(true);
        Package__c elw = activePackage('Extended_Limited_Warranty');
        TestDataFactory.createPackageTier(elw.Id, true);
        Package__c trp = activePackage('Tire_Rim_Protection_Plan');
        TestDataFactory.createPackageTier(trp.Id, true);
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    private static Package__c activePackage(String rtDevName) {
        Package__c p = TestDataFactory.createPackage(rtDevName, true);
        update new Package__c(Id = p.Id, Is_Active__c = true);
        return p;
    }

    private static Account dealer() {
        return [SELECT Id, Name FROM Account
                WHERE RecordType.DeveloperName = 'Dealer_Account' LIMIT 1];
    }

    private static void setSyncFlag(Boolean enabled) {
        insert new Aprotect_Portal_Settings__c(
            SetupOwnerId = UserInfo.getUserId(),
            Dealer_Sync_Enabled__c = enabled
        );
    }

    private static Dealer_Package__c mirrorFor(Id dealerId, Id packageId) {
        return TestDataFactory.createDealerPackage(
            dealerId, packageId, 'Extended_Limited_Warranty', true);
    }

    private static Dealer_Package__c secondMirror(Account dealer) {
        Package__c trp = [SELECT Id FROM Package__c
                          WHERE RecordType.DeveloperName = 'Tire_Rim_Protection_Plan' LIMIT 1];
        return TestDataFactory.createDealerPackage(
            dealer.Id, trp.Id, 'Tire_Rim_Protection_Plan', true);
    }

    /**
     * Builds the exact payload the console sends: a JSON array of
     * { dealerPackageId, active } objects. Never a typed Apex list — that is
     * the binding that used to arrive with null ids.
     */
    private static String jsonToggles(Map<Id, Boolean> byId) {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (Id dpId : byId.keySet()) {
            rows.add(new Map<String, Object>{
                'dealerPackageId' => dpId,
                'active' => byId.get(dpId)
            });
        }
        return JSON.serialize(rows);
    }

    /** The single-row payload literal, character for character what the LWC builds. */
    private static String jsonOne(Id dpId, Boolean active) {
        return '[{"dealerPackageId":"' + dpId + '","active":'
            + (active == true ? 'true' : 'false') + '}]';
    }

    private static void assertNoApiNames(String s) {
        if (s == null) return;
        System.assert(!s.contains('__c'),
            'User-facing text must not contain an API name: ' + s);
        System.assert(!s.contains('__r'), 'No relationship API names: ' + s);
    }

    // ---------------------------------------------------------------------
    // Tests
    // ---------------------------------------------------------------------

    @isTest
    static void test_bulkActive_deactivatesAndReactivatesInOneSave() {
        Account dealer = dealer();
        setSyncFlag(true);
        Package__c elw = [SELECT Id FROM Package__c
                          WHERE RecordType.DeveloperName = 'Extended_Limited_Warranty' LIMIT 1];
        Dealer_Package__c activeDp = mirrorFor(dealer.Id, elw.Id);
        Dealer_Package__c inactiveDp = secondMirror(dealer);
        update new Dealer_Package__c(Id = inactiveDp.Id, Active__c = false);

        DealerPackageBulkActiveController.PackageToggleResult r =
            DealerPackageBulkActiveController.setDealerPackagesActive(dealer.Id,
                jsonToggles(new Map<Id, Boolean>{
                    activeDp.Id => false,
                    inactiveDp.Id => true
                }));

        System.assertEquals(true, r.success, r.message);
        System.assertEquals(2, r.updatedCount, r.message);
        System.assertEquals(0, r.failedCount, r.message);
        System.assertEquals(0, r.unchangedCount, r.message);
        assertNoApiNames(r.message);
        System.assertEquals(2, r.results.size());

        System.assertEquals(false,
            [SELECT Active__c FROM Dealer_Package__c WHERE Id = :activeDp.Id].Active__c,
            'A deselected package is deactivated');
        System.assertEquals(true,
            [SELECT Active__c FROM Dealer_Package__c WHERE Id = :inactiveDp.Id].Active__c,
            'A selected package is activated');
        System.assertEquals(2, [SELECT COUNT() FROM Dealer_Package__c
                                WHERE Dealer__c = :dealer.Id],
            'Deactivation is a flag flip — no deletes');

        // Single-row literal — the exact one-deactivation payload support uses.
        DealerPackageBulkActiveController.PackageToggleResult back =
            DealerPackageBulkActiveController.setDealerPackagesActive(dealer.Id,
                jsonOne(activeDp.Id, true));
        System.assertEquals(true, back.success, back.message);
        System.assertEquals(1, back.updatedCount, back.message);
        System.assertEquals(true,
            [SELECT Active__c FROM Dealer_Package__c WHERE Id = :activeDp.Id].Active__c,
            'Re-selecting a package activates it again');
    }

    @isTest
    static void test_bulkActive_idempotentSaveWritesNothing() {
        Account dealer = dealer();
        setSyncFlag(true);
        Package__c elw = [SELECT Id FROM Package__c
                          WHERE RecordType.DeveloperName = 'Extended_Limited_Warranty' LIMIT 1];
        Dealer_Package__c dp = mirrorFor(dealer.Id, elw.Id);

        Dealer_Package__c before = [SELECT Id, Active__c, LastModifiedDate
                                    FROM Dealer_Package__c WHERE Id = :dp.Id];

        DealerPackageBulkActiveController.PackageToggleResult r =
            DealerPackageBulkActiveController.setDealerPackagesActive(dealer.Id,
                jsonToggles(new Map<Id, Boolean>{ dp.Id => true }));
        System.assertEquals(true, r.success, r.message);
        System.assertEquals(0, r.updatedCount, r.message);
        System.assertEquals(1, r.unchangedCount, r.message);
        System.assertEquals(0, r.failedCount, r.message);
        System.assert(r.message.contains('already matched'), r.message);
        assertNoApiNames(r.message);

        Dealer_Package__c after = [SELECT Id, Active__c, LastModifiedDate
                                   FROM Dealer_Package__c WHERE Id = :dp.Id];
        System.assertEquals(before.LastModifiedDate, after.LastModifiedDate,
            'An unchanged save must not touch the record');

        DealerPackageBulkActiveController.setDealerPackagesActive(dealer.Id,
            jsonToggles(new Map<Id, Boolean>{ dp.Id => false }));
        Dealer_Package__c afterOne = [SELECT Id, Active__c, LastModifiedDate
                                      FROM Dealer_Package__c WHERE Id = :dp.Id];
        DealerPackageBulkActiveController.PackageToggleResult twice =
            DealerPackageBulkActiveController.setDealerPackagesActive(dealer.Id,
                jsonToggles(new Map<Id, Boolean>{ dp.Id => false }));
        System.assertEquals(0, twice.updatedCount, twice.message);
        System.assertEquals(1, twice.unchangedCount, twice.message);
        System.assertEquals(afterOne.LastModifiedDate,
            [SELECT LastModifiedDate FROM Dealer_Package__c WHERE Id = :dp.Id].LastModifiedDate,
            'The second identical save writes nothing');
    }

    @isTest
    static void test_bulkActive_rejectsPackageNotOnThisDealer() {
        Account dealer = dealer();
        setSyncFlag(true);
        Package__c elw = [SELECT Id FROM Package__c
                          WHERE RecordType.DeveloperName = 'Extended_Limited_Warranty' LIMIT 1];
        Dealer_Package__c mine = mirrorFor(dealer.Id, elw.Id);

        Account otherDealer = new Account(
            Name = 'Other Dealer ' + String.valueOf(DateTime.now().getTime()),
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Dealer_Account').getRecordTypeId()
        );
        insert otherDealer;
        Dealer_Package__c theirs = mirrorFor(otherDealer.Id, elw.Id);
        Account notAPackage = TestDataFactory.createCustomerAccount(true);

        DealerPackageBulkActiveController.PackageToggleResult r =
            DealerPackageBulkActiveController.setDealerPackagesActive(dealer.Id,
                jsonToggles(new Map<Id, Boolean>{
                    theirs.Id => false,
                    notAPackage.Id => false,
                    mine.Id => false
                }));

        System.assertEquals(false, r.success, 'Partial failures are reported, not hidden');
        System.assertEquals(1, r.updatedCount, r.message);
        System.assertEquals(2, r.failedCount, r.message);
        System.assertEquals(3, r.results.size());
        assertNoApiNames(r.message);
        for (DealerPackageBulkActiveController.ToggleRowResult row : r.results) {
            assertNoApiNames(row.message);
        }

        System.assertEquals(true,
            [SELECT Active__c FROM Dealer_Package__c WHERE Id = :theirs.Id].Active__c,
            'Another dealer\u2019s package is never changed from this console');
        System.assertEquals(1, [SELECT COUNT() FROM Dealer_Package__c
                                WHERE Dealer__c = :dealer.Id],
            'No mirror is created by the bulk save');
        System.assertEquals(false,
            [SELECT Active__c FROM Dealer_Package__c WHERE Id = :mine.Id].Active__c,
            'The valid row in the same batch still saves');
    }

    @isTest
    static void test_bulkActive_flagOffRefusesWrite() {
        Account dealer = dealer();
        setSyncFlag(false);
        Package__c elw = [SELECT Id FROM Package__c
                          WHERE RecordType.DeveloperName = 'Extended_Limited_Warranty' LIMIT 1];
        Dealer_Package__c dp = mirrorFor(dealer.Id, elw.Id);

        DealerPackageBulkActiveController.PackageToggleResult r =
            DealerPackageBulkActiveController.setDealerPackagesActive(dealer.Id,
                jsonToggles(new Map<Id, Boolean>{ dp.Id => false }));
        System.assertEquals(false, r.success);
        System.assert(r.message.contains('switched off'), r.message);
        assertNoApiNames(r.message);
        System.assertEquals(true,
            [SELECT Active__c FROM Dealer_Package__c WHERE Id = :dp.Id].Active__c,
            'Flag-off bulk save must not persist');
    }

    @isTest
    static void test_bulkActive_nonDealerAccountRefused() {
        setSyncFlag(true);
        Account dealerRow = dealer();
        Package__c elw = [SELECT Id FROM Package__c
                          WHERE RecordType.DeveloperName = 'Extended_Limited_Warranty' LIMIT 1];
        Dealer_Package__c dp = mirrorFor(dealerRow.Id, elw.Id);
        Account customer = TestDataFactory.createCustomerAccount(true);

        DealerPackageBulkActiveController.PackageToggleResult r =
            DealerPackageBulkActiveController.setDealerPackagesActive(customer.Id,
                jsonToggles(new Map<Id, Boolean>{ dp.Id => false }));
        System.assertEquals(false, r.success);
        System.assertEquals(0, r.updatedCount, r.message);
        assertNoApiNames(r.message);
        System.assertEquals(true,
            [SELECT Active__c FROM Dealer_Package__c WHERE Id = :dp.Id].Active__c,
            'A non-dealer account cannot change dealer package state');
    }

    @isTest
    static void test_bulkActive_permissionDeniedRefusesWrite() {
        Account dealer = dealer();
        Package__c elw = [SELECT Id FROM Package__c
                          WHERE RecordType.DeveloperName = 'Extended_Limited_Warranty' LIMIT 1];
        User u;
        Id dpId;

        // A test method may mix setup-object DML (User, PermissionSet,
        // ObjectPermissions, FieldPermissions) with non-setup DML only inside
        // System.runAs blocks; otherwise the second DML kind raises
        // MIXED_DML_OPERATION. Every DML statement below stays in one.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            setSyncFlag(true);
            dpId = mirrorFor(dealer.Id, elw.Id).Id;

            Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
            u = new User(
                Alias = 'dpbread', Email = 'dpbread@example.com',
                EmailEncodingKey = 'UTF-8', LastName = 'DPT Read Only',
                LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US', ProfileId = p.Id,
                TimeZoneSidKey = 'America/Los_Angeles',
                UserName = 'dpbread' + DateTime.now().getTime() + '@example.com'
            );
            insert u;

            PermissionSet ps = new PermissionSet(Name = 'DPT_Read_Only', Label = 'DPT Read Only');
            insert ps;
            List<ObjectPermissions> ops = new List<ObjectPermissions>();
            // Contact is carried explicitly: this org's Account read permission
            // depends on Contact read, so the permission set cannot be granted
            // without it.
            for (String objName : new List<String>{
                'Account', 'Contact', 'Dealer_Package__c'
            }) {
                ops.add(new ObjectPermissions(
                    ParentId = ps.Id, SobjectType = objName,
                    PermissionsRead = true, PermissionsEdit = false));
            }
            insert ops;
            List<FieldPermissions> fps = new List<FieldPermissions>();
            for (String f : new List<String>{
                'Dealer_Package__c.Active__c',
                'Dealer_Package__c.Dealer__c'
            }) {
                fps.add(new FieldPermissions(
                    ParentId = ps.Id, SobjectType = 'Dealer_Package__c', Field = f,
                    PermissionsRead = true, PermissionsEdit = false));
            }
            insert fps;
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }

        System.runAs(u) {
            DealerPackageBulkActiveController.PackageToggleResult r =
                DealerPackageBulkActiveController.setDealerPackagesActive(dealer.Id,
                    jsonToggles(new Map<Id, Boolean>{ dpId => false }));
            System.assertEquals(false, r.success, 'Read-only access must not write');
            System.assertEquals(0, r.updatedCount, r.message);
            System.assert(r.message.contains('permission'), r.message);
            assertNoApiNames(r.message);
        }

        System.assertEquals(true,
            [SELECT Active__c FROM Dealer_Package__c WHERE Id = :dpId].Active__c,
            'A user without update access must not change the state');
    }

    /**
     * A payload that cannot be parsed must not throw and must not write
     * anything: the console shows the same "no changes" message it shows for an
     * empty selection.
     */
    @isTest
    static void test_bulkActive_malformedJsonIsNonFatal() {
        Account dealer = dealer();
        setSyncFlag(true);
        Package__c elw = [SELECT Id FROM Package__c
                          WHERE RecordType.DeveloperName = 'Extended_Limited_Warranty' LIMIT 1];
        Dealer_Package__c dp = mirrorFor(dealer.Id, elw.Id);

        Dealer_Package__c before = [SELECT Id, Active__c, LastModifiedDate
                                    FROM Dealer_Package__c WHERE Id = :dp.Id];

        DealerPackageBulkActiveController.PackageToggleResult r =
            DealerPackageBulkActiveController.setDealerPackagesActive(
                dealer.Id, '[{"dealerPackageId":');

        System.assertEquals(false, r.success, 'A malformed payload is not a success');
        System.assertEquals('There are no package changes to save.', r.message,
            'Malformed JSON returns the friendly no-changes message');
        System.assertEquals(0, r.updatedCount, r.message);
        System.assertEquals(0, r.failedCount, r.message);
        System.assertEquals(0, r.results.size(), 'Nothing is reported per row');
        assertNoApiNames(r.message);

        Dealer_Package__c after = [SELECT Id, Active__c, LastModifiedDate
                                   FROM Dealer_Package__c WHERE Id = :dp.Id];
        System.assertEquals(before.Active__c, after.Active__c, 'No DML on a parse failure');
        System.assertEquals(before.LastModifiedDate, after.LastModifiedDate,
            'The record is untouched by a malformed payload');

        // A JSON object (not an array) and a null payload are equally safe.
        DealerPackageBulkActiveController.PackageToggleResult objShape =
            DealerPackageBulkActiveController.setDealerPackagesActive(dealer.Id, '{"a":1}');
        System.assertEquals('There are no package changes to save.', objShape.message);

        DealerPackageBulkActiveController.PackageToggleResult empty =
            DealerPackageBulkActiveController.setDealerPackagesActive(dealer.Id, null);
        System.assertEquals('There are no package changes to save.', empty.message);
    }
}