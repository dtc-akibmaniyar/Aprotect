/**
 * DealerPackageSyncControllerTest
 *
 * P7-b exit-criteria tests (architecture doc §8 P7-b):
 *   • Inventory staleness: watermark rule — Synced baseline, flips to
 *     UpdatesAvailable when a master child changes (exact delta: price change),
 *     clears again after syncFromMaster.
 *   • D1 catalogue filter: active-only, Superseded releases excluded, future
 *     effective dates excluded where a date exists, Draft (no date) included.
 *   • createFromMaster: dry-run → real run creates header + children via the
 *     existing after-insert fan-out → re-run skips (idempotent).
 *   • syncFromMaster: wholesale anchor updated, dealer markup NEVER overwritten
 *     (D3), watermark bumped, re-sync duplicates nothing.
 *   • Flag gate (D4): real writes refused when Dealer_Sync_Enabled__c is false;
 *     dry-runs always allowed.
 *   • Non-dealer account → typed responses; orphaned / inactive-master rows.
 */
@isTest(SeeAllData=false)
private class DealerPackageSyncControllerTest {

    @TestSetup
    static void setup() {
        // One shared dealer + a small catalogue. Per-method tests add mirrors.
        Account dealer = TestDataFactory.createDealer(true);
        // ELW master with tier / term / package-level Included option /
        // term-level Optional option (the shapes the fan-out produces).
        Package__c elw = activePackage('Extended_Limited_Warranty');
        Package_Tier__c tier = TestDataFactory.createPackageTier(elw.Id, true);
        Package_Term__c term = TestDataFactory.createPackageTerm(elw.Id, tier.Id, true);
        TestDataFactory.createPackageOption(elw.Id, null, 'Included', true);
        TestDataFactory.createPackageOption(elw.Id, term.Id, 'Optional', true);
        // Second active master — the gap-create candidate.
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

    /** User-level flag row (hierarchy: user row wins over the org default). */
    private static void setSyncFlag(Boolean enabled) {
        insert new Aprotect_Portal_Settings__c(
            SetupOwnerId = UserInfo.getUserId(),
            Dealer_Sync_Enabled__c = enabled
        );
    }

    private static Dealer_Package__c mirrorFor(Id dealerId, Id packageId) {
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(
            dealerId, packageId, 'Extended_Limited_Warranty', true);
        return dp;
    }

    private static void backdateWatermark(Id dealerPackageId, Integer hoursAgo) {
        update new Dealer_Package__c(
            Id = dealerPackageId,
            Last_Synced_At__c = System.now().addHours(-hoursAgo)
        );
    }

    private static Package_Term__c masterTermOf(Id packageId) {
        return [SELECT Id, Price__c FROM Package_Term__c
                WHERE Package__c = :packageId LIMIT 1];
    }

    private static Dealer_Package_Term__c dealerTermOf(Id dealerPackageId) {
        return [SELECT Id, Original_Package_Term_Cost__c, Markup__c, Markup_Type__c,
                       Discount_Type__c, Discount_Value__c, Sales_Rep_Incentive__c
                FROM Dealer_Package_Term__c
                WHERE Dealer_Package__c = :dealerPackageId LIMIT 1];
    }

    private static DealerPackageSyncController.SyncInventoryDTO inventory(Id dealerId) {
        return DealerPackageSyncController.getSyncInventory(dealerId);
    }

    private static DealerPackageSyncController.MirrorRow mirrorRow(
        DealerPackageSyncController.SyncInventoryDTO dto, Id dealerPackageId
    ) {
        for (DealerPackageSyncController.MirrorRow r : dto.mirrored) {
            if (r.dealerPackageId == dealerPackageId) return r;
        }
        return null;
    }

    // ---------------------------------------------------------------------
    // Inventory staleness (watermark rule) + exact deltas
    // ---------------------------------------------------------------------

    @isTest
    static void test_inventory_watermarkRule_flipsOnMasterEdit_andClearsOnSync() {
        Account dealer = dealer();
        Package__c elw = [SELECT Id, Name FROM Package__c
                          WHERE RecordType.DeveloperName = 'Extended_Limited_Warranty' LIMIT 1];

        setSyncFlag(true);
        Dealer_Package__c dp = mirrorFor(dealer.Id, elw.Id);

        // Baseline: mirror born after the master → Synced, no changes.
        DealerPackageSyncController.SyncInventoryDTO dto = inventory(dealer.Id);
        DealerPackageSyncController.MirrorRow row = mirrorRow(dto, dp.Id);
        System.assertNotEquals(null, row, 'Mirror row expected in inventory');
        System.assertEquals('Synced', row.status, 'Fresh mirror should be Synced');

        // The ELW master must not appear in Available (already mirrored);
        // the TRP master (no mirror) must appear.
        Boolean elwAvailable = false;
        Boolean trpAvailable = false;
        for (DealerPackageSyncController.CatalogueRow c : dto.available) {
            if (c.masterPackageId == elw.Id) elwAvailable = true;
            if (c.name != null && c.name.contains('Tire_Rim')) trpAvailable = true;
        }
        System.assertEquals(false, elwAvailable, 'Mirrored master must not be in Available');
        System.assertEquals(true, trpAvailable, 'Un-mirrored active master must be in Available');

        // Master wholesale change → UpdatesAvailable with an exact price delta.
        // (Watermark backdated first so the comparison is deterministic —
        //  master LMD ~now is always > watermark = now − 2h.)
        backdateWatermark(dp.Id, 2);
        update new Package_Term__c(Id = masterTermOf(elw.Id).Id, Price__c = 1999.00);

        dto = inventory(dealer.Id);
        row = mirrorRow(dto, dp.Id);
        System.assertEquals('UpdatesAvailable', row.status, 'Master price edit must flag the mirror');
        System.assertEquals(1, row.changes.priceChanges,
            'One wholesale price change expected (anchor vs master Price__c)');
        System.assert(row.reason != null && row.reason.contains('price'),
            'Reason should mention the wholesale price change: ' + row.reason);

        // Sync → anchor refreshed, watermark bumped in the same transaction.
        Datetime watermarkBefore = [SELECT Last_Synced_At__c FROM Dealer_Package__c
                                    WHERE Id = :dp.Id].Last_Synced_At__c;
        DealerPackageSyncController.ActionResult ar =
            DealerPackageSyncController.syncFromMaster(new List<Id>{ dp.Id }, false);
        System.assertEquals(true, ar.success, ar.message);
        System.assertEquals(1, ar.createdCount, 'Sync should report the applied price change');

        Dealer_Package_Term__c dt = dealerTermOf(dp.Id);
        System.assertEquals(1999.00, dt.Original_Package_Term_Cost__c,
            'Wholesale anchor must refresh to the new master price');
        Datetime watermarkAfter = [SELECT Last_Synced_At__c FROM Dealer_Package__c
                                   WHERE Id = :dp.Id].Last_Synced_At__c;
        System.assert(watermarkAfter > watermarkBefore,
            'Reconcile must bump the watermark (' + watermarkAfter + ' vs ' + watermarkBefore + ')');

        // Clear proof is watermark-driven: forward the watermark past the master
        // edit → the same edited mirror reads Synced (console reads the
        // watermark, not CreatedDate).
        update new Dealer_Package__c(Id = dp.Id,
            Last_Synced_At__c = System.now().addHours(1));
        dto = inventory(dealer.Id);
        row = mirrorRow(dto, dp.Id);
        System.assertEquals('Synced', row.status, 'Watermark past the master change must read Synced');
    }

    // ---------------------------------------------------------------------
    // D1 catalogue filter
    // ---------------------------------------------------------------------

    @isTest
    static void test_availableCatalogue_respectsD1Predicate() {
        Account dealer = dealer();

        // Superseded release → its active package is NOT offered.
        Catalogue_Release__c superseded = new Catalogue_Release__c(
            Name = 'T Superseded Book', Status__c = 'Superseded');
        insert superseded;
        Package_Group__c g1 = new Package_Group__c(Name = 'T Group Superseded',
            Catalogue_Release__c = superseded.Id);
        insert g1;
        Package__c p1 = activePackage('Gap_Coverage');
        update new Package__c(Id = p1.Id, Package_Group__c = g1.Id);

        // Draft release with NO effective date → its active package IS offered.
        Catalogue_Release__c draft = new Catalogue_Release__c(
            Name = 'T Draft Book', Status__c = 'Draft');
        insert draft;
        Package_Group__c g2 = new Package_Group__c(Name = 'T Group Draft',
            Catalogue_Release__c = draft.Id);
        insert g2;
        Package__c p2 = activePackage('Gap_Coverage');
        update new Package__c(Id = p2.Id, Package_Group__c = g2.Id);

        // Draft release with a FUTURE effective date → excluded (date check only
        // applies where a release effective date exists).
        Catalogue_Release__c future = new Catalogue_Release__c(
            Name = 'T Future Book', Status__c = 'Draft',
            Effective_Date__c = System.today().addMonths(3));
        insert future;
        Package_Group__c g3 = new Package_Group__c(Name = 'T Group Future',
            Catalogue_Release__c = future.Id);
        insert g3;
        Package__c p3 = activePackage('Gap_Coverage');
        update new Package__c(Id = p3.Id, Package_Group__c = g3.Id);

        // Inactive master (no release) → excluded.
        Package__c p4 = TestDataFactory.createPackage('Gap_Coverage', true);
        update new Package__c(Id = p4.Id, Is_Active__c = false);

        DealerPackageSyncController.SyncInventoryDTO dto = inventory(dealer.Id);
        Set<Id> offered = new Set<Id>();
        for (DealerPackageSyncController.CatalogueRow c : dto.available) {
            offered.add(c.masterPackageId);
        }
        System.assertEquals(false, offered.contains(p1.Id), 'Superseded-release package must not be offered');
        System.assertEquals(true, offered.contains(p2.Id), 'Draft (no effective date) package must be offered');
        System.assertEquals(false, offered.contains(p3.Id), 'Future-effective-date package must not be offered');
        System.assertEquals(false, offered.contains(p4.Id), 'Inactive package must not be offered');
    }

    // ---------------------------------------------------------------------
    // P7-f C5 (tier-opt-in) — the delta counts tier-less terms too
    // ---------------------------------------------------------------------

    @isTest
    static void test_dryRunCountsTierlessTermAdditions() {
        Account dealer = dealer();
        setSyncFlag(true);
        Package__c elw = [SELECT Id FROM Package__c
                          WHERE RecordType.DeveloperName = 'Extended_Limited_Warranty' LIMIT 1];
        // Mirror exists first (built without the tier-less term)…
        Dealer_Package__c dp = mirrorFor(dealer.Id, elw.Id);
        // …then a tier-less master term is added.
        TestDataFactory.createPackageTerm(elw.Id, null, true);
        backdateWatermark(dp.Id, 2);

        DealerPackageSyncController.SyncInventoryDTO dto = inventory(dealer.Id);
        DealerPackageSyncController.MirrorRow row = mirrorRow(dto, dp.Id);
        System.assertEquals('UpdatesAvailable', row.status,
            'A new tier-less master term must flag the mirror as needing an update');
        System.assert(row.changes.termsAdded >= 1,
            'The tier-less term must be counted in the delta (C5): termsAdded=' + row.changes.termsAdded);
        System.assert(row.reason != null && row.reason.contains('term'),
            'Reason should mention the term addition: ' + row.reason);
    }

    @isTest
    static void test_availableToAddUnaffectedByTiers() {
        Account dealer = dealer();
        // A fresh active master carrying a tier-less term, with NO mirror for
        // this dealer — the D1 catalogue predicate is untouched by opt-in, so it
        // stays "available to add".
        Package__c p = activePackage('Extended_Limited_Warranty');
        TestDataFactory.createPackageTerm(p.Id, null, true);

        DealerPackageSyncController.SyncInventoryDTO dto = inventory(dealer.Id);
        Boolean offered = false;
        for (DealerPackageSyncController.CatalogueRow c : dto.available) {
            if (c.masterPackageId == p.Id) offered = true;
        }
        System.assertEquals(true, offered,
            'A tier-less master with no mirror must stay AvailableToAdd (predicate unchanged)');
    }

    // ---------------------------------------------------------------------
    // Gap-create: dry-run → run → re-run skip
    // ---------------------------------------------------------------------

    @isTest
    static void test_createFromMaster_dryRunThenRealRunThenRerunSkips() {
        Account dealer = dealer();
        setSyncFlag(true);
        Package__c trp = [SELECT Id, Name FROM Package__c
                          WHERE RecordType.DeveloperName = 'Tire_Rim_Protection_Plan' LIMIT 1];

        // Dry run — no DML.
        Test.startTest();
        DealerPackageSyncController.ActionResult dry =
            DealerPackageSyncController.createFromMaster(
                dealer.Id, new List<Id>{ trp.Id }, true);
        System.assertEquals(true, dry.success, dry.message);
        System.assertEquals(1, dry.createdCount, 'Dry run should report one would-create');
        System.assertEquals('would-create', dry.results[0].status);
        System.assertEquals(0, [SELECT COUNT() FROM Dealer_Package__c
                                WHERE Dealer__c = :dealer.Id AND Package__c = :trp.Id],
            'Dry run must not create rows');

        // Real run — header + mirror children via the fan-out.
        DealerPackageSyncController.ActionResult run =
            DealerPackageSyncController.createFromMaster(
                dealer.Id, new List<Id>{ trp.Id }, false);
        System.assertEquals(true, run.success, run.message);
        System.assertEquals(1, run.createdCount);
        Dealer_Package__c dp = [SELECT Id, Last_Synced_At__c FROM Dealer_Package__c
                                WHERE Dealer__c = :dealer.Id AND Package__c = :trp.Id LIMIT 1];
        System.assertNotEquals(null, dp.Id);
        System.assertNotEquals(null, dp.Last_Synced_At__c,
            'New mirror must carry a watermark');
        System.assertEquals(1, [SELECT COUNT() FROM Dealer_Package_Tier__c
                                WHERE Dealer_Package__c = :dp.Id],
            'Fan-out must build the tier mirror');

        // Re-run — skipped, nothing duplicated.
        DealerPackageSyncController.ActionResult rerun =
            DealerPackageSyncController.createFromMaster(
                dealer.Id, new List<Id>{ trp.Id }, false);
        System.assertEquals(true, rerun.success, rerun.message);
        System.assertEquals('skipped', rerun.results[0].status);
        System.assertEquals(1, [SELECT COUNT() FROM Dealer_Package_Tier__c
                                WHERE Dealer_Package__c = :dp.Id],
            'No duplicate tier mirrors on re-run');
        Test.stopTest();
    }

    // ---------------------------------------------------------------------
    // Sync preserves markup; re-sync is idempotent
    // ---------------------------------------------------------------------

    @isTest
    static void test_syncFromMaster_markupNeverOverwritten_andReSyncDuplicatesNothing() {
        Account dealer = dealer();
        setSyncFlag(true);
        Package__c elw = [SELECT Id FROM Package__c
                          WHERE RecordType.DeveloperName = 'Extended_Limited_Warranty' LIMIT 1];
        Dealer_Package__c dp = mirrorFor(dealer.Id, elw.Id);

        // Dealer-local markup profile — must survive every sync.
        update new Dealer_Package_Term__c(
            Id = dealerTermOf(dp.Id).Id,
            Markup__c = 250,
            Markup_Type__c = '$',
            Discount_Type__c = '$',
            Discount_Value__c = 75,
            Sales_Rep_Incentive__c = 30
        );
        // Backdate the watermark so the mirror is stale, then change the price.
        backdateWatermark(dp.Id, 2);
        update new Package_Term__c(Id = masterTermOf(elw.Id).Id, Price__c = 1750.00);

        // Dry-run summary: one price change; markup never part of the summary.
        DealerPackageSyncController.ActionResult dry =
            DealerPackageSyncController.syncFromMaster(new List<Id>{ dp.Id }, true);
        System.assertEquals(true, dry.success, dry.message);
        // The dealer already has local pricing, so the stored master-price anchor
        // is FROZEN: a master price edit is no longer a pending change here.
        System.assertEquals(0, dry.createdCount, 'Frozen anchor — no pending price change');
        System.assertEquals(0, dry.results[0].changes.priceChanges,
            'Frozen anchor: the console must not report a price change it will not apply');
        System.assertEquals('would-update', dry.results[0].status);

        // Child counts before, to prove the re-run duplicates nothing.
        Integer tiersBefore = [SELECT COUNT() FROM Dealer_Package_Tier__c WHERE Dealer_Package__c = :dp.Id];
        Integer termsBefore = [SELECT COUNT() FROM Dealer_Package_Term__c WHERE Dealer_Package__c = :dp.Id];
        Integer optionsBefore = [SELECT COUNT() FROM Dealer_Package_Option__c WHERE Dealer_Package__c = :dp.Id];

        DealerPackageSyncController.ActionResult run =
            DealerPackageSyncController.syncFromMaster(new List<Id>{ dp.Id }, false);
        System.assertEquals(true, run.success, run.message);

        Dealer_Package_Term__c dt = dealerTermOf(dp.Id);
        System.assertEquals(1500.00, dt.Original_Package_Term_Cost__c,
            'Frozen anchor: a master price edit must not move the dealer effective price');
        System.assertEquals(250, dt.Markup__c, 'Markup must never be overwritten');
        System.assertEquals('$', dt.Markup_Type__c);
        System.assertEquals(75, dt.Discount_Value__c);
        System.assertEquals(30, dt.Sales_Rep_Incentive__c);

        // Second sync — nothing left to do; zero duplication.
        DealerPackageSyncController.ActionResult run2 =
            DealerPackageSyncController.syncFromMaster(new List<Id>{ dp.Id }, false);
        System.assertEquals(true, run2.success, run2.message);
        System.assertEquals(0, run2.createdCount, 'Second sync must be a no-op');
        System.assertEquals(1, run2.skippedCount, 'Second sync reports skipped (already current)');
        System.assertEquals(tiersBefore, [SELECT COUNT() FROM Dealer_Package_Tier__c WHERE Dealer_Package__c = :dp.Id]);
        System.assertEquals(termsBefore, [SELECT COUNT() FROM Dealer_Package_Term__c WHERE Dealer_Package__c = :dp.Id]);
        System.assertEquals(optionsBefore, [SELECT COUNT() FROM Dealer_Package_Option__c WHERE Dealer_Package__c = :dp.Id]);
    }

    // ---------------------------------------------------------------------
    // Flag gate (D4)
    // ---------------------------------------------------------------------

    @isTest
    static void test_flagOff_refusesRealWrites_dryRunStillAllowed() {
        Account dealer = dealer();
        setSyncFlag(false);
        Package__c trp = [SELECT Id FROM Package__c
                          WHERE RecordType.DeveloperName = 'Tire_Rim_Protection_Plan' LIMIT 1];

        // Dry-run allowed with the flag off (read-only).
        DealerPackageSyncController.ActionResult dry =
            DealerPackageSyncController.createFromMaster(
                dealer.Id, new List<Id>{ trp.Id }, true);
        System.assertEquals(true, dry.success, dry.message);

        // Real run refused with a plain-language, API-name-free message.
        DealerPackageSyncController.ActionResult run =
            DealerPackageSyncController.createFromMaster(
                dealer.Id, new List<Id>{ trp.Id }, false);
        System.assertEquals(false, run.success);
        System.assert(run.message.contains('switched off'), run.message);
        assertNoApiNames(run.message);
        System.assertEquals(0, [SELECT COUNT() FROM Dealer_Package__c
                                WHERE Dealer__c = :dealer.Id AND Package__c = :trp.Id],
            'Flag-off run must not create rows');
    }

    // ---------------------------------------------------------------------
    // Non-dealer account + orphaned/inactive rows
    // ---------------------------------------------------------------------

    @isTest
    static void test_nonDealerAccount_typedResponses() {
        Account customer = TestDataFactory.createCustomerAccount(true);

        DealerPackageSyncController.SyncInventoryDTO dto =
            DealerPackageSyncController.getSyncInventory(customer.Id);
        System.assertEquals(false, dto.isDealerAccount,
            'Non-dealer account must be typed, not crashed');

        DealerPackageSyncController.ActionResult ar =
            DealerPackageSyncController.createFromMaster(
                customer.Id, new List<Id>{ UserInfo.getOrganizationId() }, false);
        System.assertEquals(false, ar.success);
        System.assert(ar.message.contains('Dealer Account'), ar.message);
    }

    @isTest
    static void test_orphanedAndInactiveMaster_rowsSurfaceInInventory() {
        Account dealer = dealer();
        setSyncFlag(true);
        Package__c elw = [SELECT Id FROM Package__c
                          WHERE RecordType.DeveloperName = 'Extended_Limited_Warranty' LIMIT 1];
        Dealer_Package__c dp = mirrorFor(dealer.Id, elw.Id);

        // Deactivate the master → InactiveMaster row (mirror kept).
        update new Package__c(Id = elw.Id, Is_Active__c = false);
        DealerPackageSyncController.SyncInventoryDTO dto = inventory(dealer.Id);
        DealerPackageSyncController.MirrorRow row = mirrorRow(dto, dp.Id);
        System.assertEquals('InactiveMaster', row.status,
            'Deactivated master must surface as InactiveMaster, not vanish');

        // Orphaned header (no master link).
        Dealer_Package__c orphan = new Dealer_Package__c(
            Name = 'Orphan ' + Datetime.now().getTime(),
            Dealer__c = dealer.Id,
            RecordTypeId = TestDataFactory.getRecordTypeId('Dealer_Package__c', 'Extended_Limited_Warranty')
        );
        insert orphan; // no Package__c → trigger fan-out is skipped
        dto = inventory(dealer.Id);
        row = mirrorRow(dto, orphan.Id);
        System.assertEquals('Orphaned', row.status, 'Header without a master link must surface as Orphaned');
    }

    // ---------------------------------------------------------------------
    // P7-e unified list: statuses, labels, plain-language messages
    // ---------------------------------------------------------------------

    /** Every user-facing string must read as business words — never an API name. */
    private static void assertNoApiNames(String s) {
        if (s == null) return;
        System.assert(!s.contains('__c'),
            'User-facing text must not contain an API name: ' + s);
        System.assert(!s.contains('__r'), 'No relationship API names: ' + s);
    }

    private static DealerPackageSyncController.UnifiedPackageRow unified(
        DealerPackageSyncController.SyncInventoryDTO dto, Id masterPackageId
    ) {
        for (DealerPackageSyncController.UnifiedPackageRow r : dto.packages) {
            if (r.masterPackageId == masterPackageId) return r;
        }
        return null;
    }

    @isTest
    static void test_unifiedList_carriesStatusesLabelsAndCounts() {
        Account dealer = dealer();
        setSyncFlag(true);
        Package__c elw = [SELECT Id FROM Package__c
                          WHERE RecordType.DeveloperName = 'Extended_Limited_Warranty' LIMIT 1];
        Package__c trp = [SELECT Id FROM Package__c
                          WHERE RecordType.DeveloperName = 'Tire_Rim_Protection_Plan' LIMIT 1];
        Dealer_Package__c dp = mirrorFor(dealer.Id, elw.Id);

        // ONE list holding both an un-mirrored master and a current mirror.
        DealerPackageSyncController.SyncInventoryDTO dto = inventory(dealer.Id);

        DealerPackageSyncController.UnifiedPackageRow elwRow = unified(dto, elw.Id);
        System.assertNotEquals(null, elwRow, 'Mirrored master must be in the unified list');
        System.assertEquals('AlreadyAvailable', elwRow.status);
        System.assertEquals('Already available', elwRow.statusLabel);
        System.assertEquals('ok', elwRow.statusTone);
        System.assertEquals('none', elwRow.primaryAction);
        System.assertEquals('', elwRow.primaryActionLabel);
        System.assertEquals(dp.Id, elwRow.dealerPackageId);
        System.assertNotEquals(null, elwRow.lastSyncedLabel, 'A mirrored row shows its last sync');

        DealerPackageSyncController.UnifiedPackageRow trpRow = unified(dto, trp.Id);
        System.assertNotEquals(null, trpRow, 'Un-mirrored master must be in the unified list');
        System.assertEquals('AvailableToAdd', trpRow.status);
        System.assertEquals('Available to add', trpRow.statusLabel);
        System.assertEquals('new', trpRow.statusTone);
        System.assertEquals('add', trpRow.primaryAction);
        System.assertEquals('Add to dealer', trpRow.primaryActionLabel);
        System.assertEquals(null, trpRow.dealerPackageId);

        // Header counts agree with the row statuses.
        System.assertEquals(1, dto.availableToAddCount);
        System.assertEquals(1, dto.alreadyAvailableCount);
        System.assertEquals(0, dto.updateAvailableCount);
        System.assertEquals(2, dto.packages.size());

        // A master edit flips the SAME row to UpdateAvailable.
        backdateWatermark(dp.Id, 2);
        update new Package_Term__c(Id = masterTermOf(elw.Id).Id, Price__c = 1234.00);
        dto = inventory(dealer.Id);
        elwRow = unified(dto, elw.Id);
        System.assertEquals('UpdateAvailable', elwRow.status);
        System.assertEquals('Update available', elwRow.statusLabel);
        System.assertEquals('attention', elwRow.statusTone);
        System.assertEquals('sync', elwRow.primaryAction);
        System.assertEquals('Sync now', elwRow.primaryActionLabel);
        System.assertEquals(1, dto.updateAvailableCount);
        System.assertEquals(0, dto.alreadyAvailableCount);

        // Needs-attention rows sort first.
        System.assertEquals(elw.Id, dto.packages[0].masterPackageId,
            'Rows needing a sync must lead the list');

        // No API names anywhere the admin can read.
        assertNoApiNames(dto.syncEnabledMessage);
        for (DealerPackageSyncController.UnifiedPackageRow r : dto.packages) {
            assertNoApiNames(r.statusLabel);
            assertNoApiNames(r.reason);
            assertNoApiNames(r.countsLabel);
            assertNoApiNames(r.primaryActionLabel);
            assertNoApiNames(r.recordTypeLabel);
            assertNoApiNames(r.releaseLabel);
        }
    }

    @isTest
    static void test_messages_arePlainLanguage() {
        Account dealer = dealer();
        setSyncFlag(true);
        Package__c elw = [SELECT Id FROM Package__c
                          WHERE RecordType.DeveloperName = 'Extended_Limited_Warranty' LIMIT 1];
        Package__c trp = [SELECT Id FROM Package__c
                          WHERE RecordType.DeveloperName = 'Tire_Rim_Protection_Plan' LIMIT 1];
        Dealer_Package__c dp = mirrorFor(dealer.Id, elw.Id);
        backdateWatermark(dp.Id, 2);
        update new Package_Term__c(Id = masterTermOf(elw.Id).Id, Price__c = 1888.00);

        // Dry-run summary: plain words, no API names, no "(s)" padding.
        DealerPackageSyncController.ActionResult dry =
            DealerPackageSyncController.syncFromMaster(new List<Id>{ dp.Id }, true);
        System.assertEquals(true, dry.success, dry.message);
        String rowMsg = dry.results[0].message;
        assertNoApiNames(rowMsg);
        System.assert(!rowMsg.contains('(s)'), 'No "(s)" padding: ' + rowMsg);
        System.assert(rowMsg.contains('wholesale price'), rowMsg);

        // Envelope message + create dry-run message are plain too.
        assertNoApiNames(dry.message);
        DealerPackageSyncController.ActionResult createDry =
            DealerPackageSyncController.createFromMaster(
                dealer.Id, new List<Id>{ trp.Id }, true);
        assertNoApiNames(createDry.message);
        assertNoApiNames(createDry.results[0].message);
        System.assert(!createDry.message.contains('(s)'), createDry.message);
    }

    // ---------------------------------------------------------------------
    // P7-e-fix — "Add to dealer" with a master term restricted to a value the
    // dealer picklist was missing (regression) + the defensive skip/flag path
    // ---------------------------------------------------------------------

    @isTest
    static void test_createFromMaster_unlimitedRestrictionValueMirrorsSuccessfully() {
        Account dealer = dealer();
        setSyncFlag(true);
        Package__c elw = [SELECT Id FROM Package__c
                          WHERE RecordType.DeveloperName = 'Extended_Limited_Warranty' LIMIT 1];
        // The value that used to throw INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST.
        update new Package_Term__c(Id = masterTermOf(elw.Id).Id, Restriction_Type__c = 'Unlimited');

        Test.startTest();
        DealerPackageSyncController.ActionResult run =
            DealerPackageSyncController.createFromMaster(
                dealer.Id, new List<Id>{ elw.Id }, false);
        Test.stopTest();

        System.assertEquals(true, run.success, run.message);
        System.assertEquals(1, run.createdCount, run.message);
        Dealer_Package__c dp = [SELECT Id FROM Dealer_Package__c
                                WHERE Dealer__c = :dealer.Id AND Package__c = :elw.Id LIMIT 1];
        Dealer_Package_Term__c dt = [SELECT Restriction_Type__c FROM Dealer_Package_Term__c
                                     WHERE Dealer_Package__c = :dp.Id LIMIT 1];
        System.assertEquals('Unlimited', dt.Restriction_Type__c,
            'The dealer mirror must accept the master Unlimited restriction value');
    }

    @isTest
    static void test_createFromMaster_flagsSkippedDetailInsteadOfGenericError() {
        Account dealer = dealer();
        setSyncFlag(true);
        Package__c elw = [SELECT Id FROM Package__c
                          WHERE RecordType.DeveloperName = 'Extended_Limited_Warranty' LIMIT 1];
        update new Package_Term__c(Id = masterTermOf(elw.Id).Id, Restriction_Type__c = 'Unlimited');

        // Simulate a master value the dealer catalogue rejects: the run must skip
        // that detail, create the rest, and flag the package — never a generic error.
        DealerPackageSyncService.forcedRejectMasterTermIds =
            new Set<Id>{ masterTermOf(elw.Id).Id };

        Test.startTest();
        DealerPackageSyncController.ActionResult run;
        try {
            run = DealerPackageSyncController.createFromMaster(
                dealer.Id, new List<Id>{ elw.Id }, false);
        } finally {
            DealerPackageSyncService.forcedRejectMasterTermIds = null;
        }
        Test.stopTest();

        System.assertEquals(false, run.success,
            'A skipped detail must not report a clean success');
        System.assertEquals(1, run.failedCount, run.message);
        System.assertEquals('failed', run.results[0].status);
        assertNoApiNames(run.message);
        assertNoApiNames(run.results[0].message);
        System.assertNotEquals(null, run.results[0].message,
            'The flagged row must carry a clear, plain-word reason');
        // The header still exists — the rejected detail was skipped, not fatal.
        System.assertEquals(1, [SELECT COUNT() FROM Dealer_Package__c
                                WHERE Dealer__c = :dealer.Id AND Package__c = :elw.Id]);
    }

    // ---------------------------------------------------------------------
    // Authoring (dealer-side): keep/remove, term pricing, commercial price
    // ---------------------------------------------------------------------

    @isTest
    static void test_authoring_keepRemovePricingAndCommercialPrice() {
        Account dealer = dealer();
        setSyncFlag(true);
        Package__c elw = [SELECT Id FROM Package__c
                          WHERE RecordType.DeveloperName = 'Extended_Limited_Warranty' LIMIT 1];
        Dealer_Package__c dp = mirrorFor(dealer.Id, elw.Id);

        DealerPackageSyncController.AuthoringDTO dto =
            DealerPackageSyncController.getDealerAuthoring(dealer.Id);
        System.assertEquals(true, dto.isDealerAccount);
        System.assertEquals(true, dto.syncEnabled);
        System.assertEquals(1, dto.packages.size(), 'One dealer package expected');
        System.assertEquals(1, dto.packages[0].terms.size(), 'One term expected');
        System.assertEquals(1, dto.packages[0].includedOptions.size(),
            'Package-level included add-on expected');
        System.assertEquals(1, dto.packages[0].terms[0].options.size(),
            'Term-level optional add-on expected');

        // Keep/remove: the dealer removes a mirrored add-on.
        Id optId = dto.packages[0].terms[0].options[0].dealerOptionId;
        DealerPackageSyncController.AuthoringResult rm =
            DealerPackageSyncController.setDealerOptionRemoved(optId, true);
        System.assertEquals(true, rm.success, rm.message);

        Integer optCount = [SELECT COUNT() FROM Dealer_Package_Option__c WHERE Dealer_Package__c = :dp.Id];
        DealerPackageSyncService.reconcileDealerPackages(new Set<Id>{ dp.Id });
        System.assertEquals(optCount,
            [SELECT COUNT() FROM Dealer_Package_Option__c WHERE Dealer_Package__c = :dp.Id],
            'A removed add-on is never re-created');
        System.assertEquals(true,
            [SELECT Is_Removed__c FROM Dealer_Package_Option__c WHERE Id = :optId].Is_Removed__c,
            'The removal flag survives a reconcile');

        // Dealer commercial price — flat, per-dealer.
        DealerPackageSyncController.AuthoringResult cp =
            DealerPackageSyncController.saveDealerCommercialPrice(dp.Id, 325.00);
        System.assertEquals(true, cp.success, cp.message);
        System.assertEquals(325.00,
            [SELECT Commercial_Vehicle_Surcharge_Fee__c FROM Dealer_Package__c WHERE Id = :dp.Id]
                .Commercial_Vehicle_Surcharge_Fee__c);

        // Term pricing: discount, incentive and markup.
        Id termId = dto.packages[0].terms[0].dealerTermId;
        DealerPackageSyncController.AuthoringResult tp =
            DealerPackageSyncController.saveDealerTermPricing(termId, '$', 100, '$', 250, 40);
        System.assertEquals(true, tp.success, tp.message);
        Dealer_Package_Term__c t = dealerTermOf(dp.Id);
        System.assertEquals(100, t.Discount_Value__c);
        System.assertEquals(250, t.Markup__c);
        System.assertEquals(40, t.Sales_Rep_Incentive__c);
        System.assertEquals(1500.00, t.Original_Package_Term_Cost__c,
            'Authoring local pricing freezes the stored anchor where it is');

        // A later master edit no longer moves the dealer's effective price.
        update new Package_Term__c(Id = masterTermOf(elw.Id).Id, Price__c = 2000.00);
        DealerPackageSyncService.reconcileDealerPackages(new Set<Id>{ dp.Id });
        System.assertEquals(1500.00, dealerTermOf(dp.Id).Original_Package_Term_Cost__c,
            'Frozen anchor: master edit must not move the dealer effective price');

        // The deliberate, dealer-initiated refresh moves it on purpose.
        DealerPackageSyncController.AuthoringResult rf =
            DealerPackageSyncController.refreshDealerPriceAnchors(new List<Id>{ dp.Id });
        System.assertEquals(true, rf.success, rf.message);
        System.assertEquals(2000.00, dealerTermOf(dp.Id).Original_Package_Term_Cost__c,
            'Deliberate refresh re-seeds the anchor from the master');
    }

    @isTest
    static void test_authoring_flagOff_refusesWrites() {
        Account dealer = dealer();
        setSyncFlag(false);
        Package__c elw = [SELECT Id FROM Package__c
                          WHERE RecordType.DeveloperName = 'Extended_Limited_Warranty' LIMIT 1];
        Dealer_Package__c dp = mirrorFor(dealer.Id, elw.Id);

        DealerPackageSyncController.AuthoringDTO dto =
            DealerPackageSyncController.getDealerAuthoring(dealer.Id);
        System.assertEquals(false, dto.syncEnabled, 'Read reflects the kill switch');

        Id termId = dto.packages[0].terms[0].dealerTermId;
        DealerPackageSyncController.AuthoringResult r =
            DealerPackageSyncController.saveDealerTermPricing(termId, '$', 10, '$', 10, 10);
        System.assertEquals(false, r.success);
        System.assert(r.message.contains('switched off'), r.message);
        assertNoApiNames(r.message);
        System.assertEquals(null,
            [SELECT Discount_Value__c FROM Dealer_Package_Term__c WHERE Id = :termId].Discount_Value__c,
            'Flag-off authoring must not write');

        DealerPackageSyncController.AuthoringResult rm =
            DealerPackageSyncController.setDealerOptionRemoved(
                dto.packages[0].terms[0].options[0].dealerOptionId, true);
        System.assertEquals(false, rm.success);
        assertNoApiNames(rm.message);
    }

    // ---------------------------------------------------------------------
    // Master package detail (lazy, read-only) + dealer tier grouping
    // ---------------------------------------------------------------------

    @isTest
    static void test_masterPackageDetail_groupsTiersTermsAndAdditionalOptions() {
        Package__c elw = [SELECT Id, Name FROM Package__c
                          WHERE RecordType.DeveloperName = 'Extended_Limited_Warranty' LIMIT 1];
        Package_Tier__c tier = [SELECT Id, Name FROM Package_Tier__c
                                WHERE Package__c = :elw.Id LIMIT 1];
        Package_Term__c term = [SELECT Id, Name FROM Package_Term__c
                                WHERE Package__c = :elw.Id LIMIT 1];
        Package_Option__c opt = [SELECT Id, Option__r.Name FROM Package_Option__c
                                 WHERE Package__c = :elw.Id AND Package_Term__c != null LIMIT 1];

        // The test factory links no Option__c, so name the add-on here — the
        // reference table must carry the OPTION's own name, not the shell row's.
        Option__c optionRecord = new Option__c(Name = 'Zero Deductible');
        insert optionRecord;

        update new Package_Term__c(Id = term.Id, Price__c = 209.00);
        update new Package_Option__c(Id = opt.Id, Option__c = optionRecord.Id, Price__c = 55.00);

        Test.startTest();
        DealerPackageSyncController.MasterPackageDetailDTO dto =
            DealerPackageSyncController.getMasterPackageDetail(elw.Id);
        Test.stopTest();

        System.assertEquals(elw.Id, dto.masterPackageId);
        System.assertEquals(true, dto.hasTiers, 'The master carries a coverage tier');
        System.assertEquals(1, dto.termCount);
        System.assertEquals(1, dto.optionCount, 'One term-level additional option');
        System.assertEquals(1, dto.groups.size(), 'One tier block');
        System.assertEquals(true, dto.groups[0].hasTier);
        System.assertEquals(tier.Name, dto.groups[0].tierName);
        System.assertEquals(2, dto.groups[0].rows.size(), 'Term row + its option sub-row');

        DealerPackageSyncController.MasterDetailRow termRow = dto.groups[0].rows[0];
        System.assertEquals('Term', termRow.kind);
        System.assertEquals(term.Name, termRow.label);
        System.assertEquals('$209', termRow.originalPrice, termRow.originalPrice);
        System.assertEquals('\u2014', termRow.discount, 'Reference rows carry no discount');
        System.assertEquals('$209', termRow.dealerPrice);

        DealerPackageSyncController.MasterDetailRow optionRow = dto.groups[0].rows[1];
        System.assertEquals('Option', optionRow.kind);
        System.assertEquals('Zero Deductible', optionRow.label);
        System.assertEquals('$55', optionRow.originalPrice);
        System.assertEquals('\u2014', optionRow.discount);
        System.assertEquals('$55', optionRow.dealerPrice);

        assertNoApiNames(dto.name);
        assertNoApiNames(dto.groupName);
        assertNoApiNames(termRow.label);
    }

    @isTest
    static void test_masterPackageDetail_tierlessPackageRendersUngrouped() {
        Package__c p = activePackage('Extended_Limited_Warranty');
        Package_Term__c t = TestDataFactory.createPackageTerm(p.Id, null, true); // no tier
        update new Package_Term__c(Id = t.Id, Price__c = 149.00);

        Test.startTest();
        DealerPackageSyncController.MasterPackageDetailDTO dto =
            DealerPackageSyncController.getMasterPackageDetail(p.Id);
        Test.stopTest();

        System.assertEquals(false, dto.hasTiers, 'No tiers on this master');
        System.assertEquals(1, dto.groups.size(), 'A single un-grouped block');
        System.assertEquals(false, dto.groups[0].hasTier);
        System.assertEquals('', dto.groups[0].tierName);
        System.assertEquals(1, dto.groups[0].rows.size());
        System.assertEquals('$149', dto.groups[0].rows[0].originalPrice);
    }

    @isTest
    static void test_masterPackageDetail_nullIsTyped() {
        DealerPackageSyncController.MasterPackageDetailDTO none =
            DealerPackageSyncController.getMasterPackageDetail(null);
        System.assertEquals(0, none.groups.size());
        System.assertEquals(false, none.hasTiers);
        System.assertEquals(0, none.termCount);
    }

    @isTest
    static void test_authoring_carriesTierGroupingForTheExpandedTable() {
        Account dealer = dealer();
        setSyncFlag(true);
        Package__c elw = [SELECT Id FROM Package__c
                          WHERE RecordType.DeveloperName = 'Extended_Limited_Warranty' LIMIT 1];
        Package_Tier__c tier = [SELECT Id, Name FROM Package_Tier__c
                                WHERE Package__c = :elw.Id LIMIT 1];
        mirrorFor(dealer.Id, elw.Id);

        DealerPackageSyncController.AuthoringDTO dto =
            DealerPackageSyncController.getDealerAuthoring(dealer.Id);
        System.assertEquals(1, dto.packages.size());
        DealerPackageSyncController.DealerPackageRow row = dto.packages[0];

        System.assertEquals(1, row.tiers.size(), 'The dealer mirror carries its coverage tier');
        System.assertEquals(tier.Name, row.tiers[0].tierName);
        System.assertNotEquals(null, row.tiers[0].tierKey);

        System.assertEquals(1, row.terms.size());
        System.assertEquals(String.valueOf(tier.Id), row.terms[0].tierKey,
            'The term carries its master tier key so the console can group it');
        System.assertEquals(tier.Name, row.terms[0].tierName);
    }

    // ---------------------------------------------------------------------
    // Premium vehicle fee (per term + package-level clear) — the console's
    // fee chip. ON = store the amount on Premium_Model_Fee__c; OFF = blank it.
    // The fee is NOT part of the Net / Retail formulas.
    // ---------------------------------------------------------------------

    @isTest
    static void test_premiumFee_readsSeededValueAndRoundTrips() {
        Account dealer = dealer();
        setSyncFlag(true);
        Package__c elw = activePackage('Extended_Limited_Warranty');
        Package_Tier__c tier = TestDataFactory.createPackageTier(elw.Id, true);
        Package_Term__c term = TestDataFactory.createPackageTerm(elw.Id, tier.Id, true);
        update new Package_Term__c(Id = term.Id, Price__c = 300.00, Premium_Model_Fee__c = 250.00);

        Dealer_Package__c dp = mirrorFor(dealer.Id, elw.Id);

        // The dealer read exposes the fee AND the master term's fee (the default
        // the console reapplies the fee with).
        DealerPackageSyncController.AuthoringDTO dto =
            DealerPackageSyncController.getDealerAuthoring(dealer.Id);
        System.assertEquals(1, dto.packages.size());
        DealerPackageSyncController.DealerTermRow row = dto.packages[0].terms[0];
        System.assertEquals(250.00, row.premiumFee,
            'The dealer term carries the premium fee seeded from the master');
        System.assertEquals(250.00, row.masterPremiumFee,
            'The master term fee is exposed as the re-apply default');

        Id termId = row.dealerTermId;
        Decimal retailBefore = [SELECT Retail_Price__c FROM Dealer_Package_Term__c
                                WHERE Id = :termId].Retail_Price__c;

        // Save a different amount — dealer-owned, added on top (not in Retail).
        DealerPackageSyncController.AuthoringResult saved =
            DealerPackageSyncController.saveDealerTermPremiumFee(termId, 325.00);
        System.assertEquals(true, saved.success, saved.message);
        assertNoApiNames(saved.message);
        System.assert(saved.message.contains('$325'), saved.message);
        System.assertEquals(325.00,
            [SELECT Premium_Model_Fee__c FROM Dealer_Package_Term__c WHERE Id = :termId]
                .Premium_Model_Fee__c);

        // OFF blanks the field; Retail Price is untouched either way.
        DealerPackageSyncController.AuthoringResult cleared =
            DealerPackageSyncController.saveDealerTermPremiumFee(termId, null);
        System.assertEquals(true, cleared.success, cleared.message);
        assertNoApiNames(cleared.message);
        System.assertEquals(null,
            [SELECT Premium_Model_Fee__c FROM Dealer_Package_Term__c WHERE Id = :termId]
                .Premium_Model_Fee__c,
            'Turning the fee off blanks the stored premium fee');
        System.assertEquals(retailBefore,
            [SELECT Retail_Price__c FROM Dealer_Package_Term__c WHERE Id = :termId]
                .Retail_Price__c,
            'The premium fee is not part of the Retail Price formula');
    }

    @isTest
    static void test_premiumFee_packageLevelClearBlanksEveryTerm() {
        Account dealer = dealer();
        setSyncFlag(true);
        Package__c elw = activePackage('Extended_Limited_Warranty');
        Package_Tier__c tier = TestDataFactory.createPackageTier(elw.Id, true);
        Package_Term__c t1 = TestDataFactory.createPackageTerm(elw.Id, tier.Id, true);
        Package_Term__c t2 = TestDataFactory.createPackageTerm(elw.Id, tier.Id, true);
        update new Package_Term__c(Id = t1.Id, Price__c = 300.00, Premium_Model_Fee__c = 100.00);
        update new Package_Term__c(Id = t2.Id, Price__c = 400.00, Premium_Model_Fee__c = 150.00);

        Dealer_Package__c dp = mirrorFor(dealer.Id, elw.Id);
        System.assertEquals(2, [SELECT COUNT() FROM Dealer_Package_Term__c
                                WHERE Dealer_Package__c = :dp.Id AND Premium_Model_Fee__c != null],
            'Both mirrored terms seed the premium fee from the master');

        DealerPackageSyncController.AuthoringResult clr =
            DealerPackageSyncController.clearDealerPackagePremiumFees(dp.Id);
        System.assertEquals(true, clr.success, clr.message);
        assertNoApiNames(clr.message);
        System.assert(clr.message.contains('2 terms'), clr.message);
        System.assertEquals(0, [SELECT COUNT() FROM Dealer_Package_Term__c
                                WHERE Dealer_Package__c = :dp.Id AND Premium_Model_Fee__c != null],
            'The package-level clear blanks the fee on every term');
    }

    @isTest
    static void test_premiumFee_flagOffRefusesWrites() {
        Account dealer = dealer();
        setSyncFlag(false);
        Package__c elw = [SELECT Id FROM Package__c
                          WHERE RecordType.DeveloperName = 'Extended_Limited_Warranty' LIMIT 1];
        Dealer_Package__c dp = mirrorFor(dealer.Id, elw.Id);
        Id termId = [SELECT Id FROM Dealer_Package_Term__c
                     WHERE Dealer_Package__c = :dp.Id LIMIT 1].Id;

        DealerPackageSyncController.AuthoringResult r =
            DealerPackageSyncController.saveDealerTermPremiumFee(termId, 50.00);
        System.assertEquals(false, r.success);
        System.assert(r.message.contains('switched off'), r.message);
        assertNoApiNames(r.message);
        System.assertEquals(null,
            [SELECT Premium_Model_Fee__c FROM Dealer_Package_Term__c WHERE Id = :termId]
                .Premium_Model_Fee__c,
            'Flag-off premium fee write must not persist');

        DealerPackageSyncController.AuthoringResult c =
            DealerPackageSyncController.clearDealerPackagePremiumFees(dp.Id);
        System.assertEquals(false, c.success);
        System.assert(c.message.contains('switched off'), c.message);
        assertNoApiNames(c.message);
    }

    // ---------------------------------------------------------------------
    // Dealer-level premium vehicle fee settings (the dealer Account fields —
    // dealer-wide, applies across every package).
    // ---------------------------------------------------------------------

    @isTest
    static void test_dealerPremiumSettings_readsRoundTripsAndDisplays() {
        Account dealer = dealer();
        setSyncFlag(true);
        Package__c elw = [SELECT Id FROM Package__c
                          WHERE RecordType.DeveloperName = 'Extended_Limited_Warranty' LIMIT 1];
        mirrorFor(dealer.Id, elw.Id);

        // Fresh dealer: no override yet; the charge flag is always a Boolean.
        DealerPackageSyncController.AuthoringDTO before =
            DealerPackageSyncController.getDealerAuthoring(dealer.Id);
        System.assertEquals(null, before.premiumFeeOverrideAmount, 'No override yet');
        System.assertEquals('', before.premiumFeeOverrideDisplay);
        System.assertNotEquals(null, before.chargePremiumVehicleFee,
            'The charge flag is exposed as a Boolean');

        // The inventory payload carries the same dealer-level settings.
        DealerPackageSyncController.SyncInventoryDTO inv =
            DealerPackageSyncController.getSyncInventory(dealer.Id);
        System.assertEquals(before.chargePremiumVehicleFee, inv.chargePremiumVehicleFee);
        System.assertEquals(before.premiumFeeOverrideAmount, inv.premiumFeeOverrideAmount);
        System.assertEquals(before.premiumFeeOverrideDisplay, inv.premiumFeeOverrideDisplay);

        // Save an override AND waive the fees — one write, both fields.
        DealerPackageSyncController.AuthoringResult r =
            DealerPackageSyncController.saveDealerPremiumSettings(dealer.Id, 250.00, false);
        System.assertEquals(true, r.success, r.message);
        assertNoApiNames(r.message);
        System.assert(r.message.contains('$250'), r.message);
        System.assert(r.message.contains('waived'), r.message);
        Account after = [
            SELECT Premium_Fee_Override_Amount__c, Charge_Premium_Vehicle_Fee__c
            FROM Account WHERE Id = :dealer.Id
        ];
        System.assertEquals(250.00, after.Premium_Fee_Override_Amount__c);
        System.assertEquals(false, after.Charge_Premium_Vehicle_Fee__c);

        // Read back: the console sees both settings (money formatted server-side).
        DealerPackageSyncController.AuthoringDTO mid =
            DealerPackageSyncController.getDealerAuthoring(dealer.Id);
        System.assertEquals(250.00, mid.premiumFeeOverrideAmount);
        System.assertEquals('$250', mid.premiumFeeOverrideDisplay);
        System.assertEquals(false, mid.chargePremiumVehicleFee);

        // Blank override + charge again → the standard package/term fees apply.
        DealerPackageSyncController.AuthoringResult r2 =
            DealerPackageSyncController.saveDealerPremiumSettings(dealer.Id, null, true);
        System.assertEquals(true, r2.success, r2.message);
        assertNoApiNames(r2.message);
        System.assert(r2.message.contains('standard'), r2.message);
        after = [
            SELECT Premium_Fee_Override_Amount__c, Charge_Premium_Vehicle_Fee__c
            FROM Account WHERE Id = :dealer.Id
        ];
        System.assertEquals(null, after.Premium_Fee_Override_Amount__c,
            'A blank override clears the field (standard fees apply)');
        System.assertEquals(true, after.Charge_Premium_Vehicle_Fee__c);
    }

    @isTest
    static void test_dealerPremiumSettings_flagOffRefusesWrite() {
        Account dealer = dealer();
        setSyncFlag(false);

        DealerPackageSyncController.AuthoringResult r =
            DealerPackageSyncController.saveDealerPremiumSettings(dealer.Id, 300.00, false);
        System.assertEquals(false, r.success);
        System.assert(r.message.contains('switched off'), r.message);
        assertNoApiNames(r.message);
        System.assertEquals(null, [
            SELECT Premium_Fee_Override_Amount__c FROM Account WHERE Id = :dealer.Id
        ].Premium_Fee_Override_Amount__c,
            'Flag-off premium settings write must not persist');
    }

    @isTest
    static void test_dealerPremiumSettings_nonDealerAccountRefused() {
        Account customer = TestDataFactory.createCustomerAccount(true);
        setSyncFlag(true);

        DealerPackageSyncController.AuthoringResult r =
            DealerPackageSyncController.saveDealerPremiumSettings(customer.Id, 100.00, true);
        System.assertEquals(false, r.success);
        System.assert(r.message.contains('Dealer Account'), r.message);
        assertNoApiNames(r.message);
    }

    // ---------------------------------------------------------------------
    // Dealer package row: the master commercial value behind the dealer-owned
    // commercial (surcharge) figure.
    // ---------------------------------------------------------------------

    @isTest
    static void test_authoring_masterCommercialHint_showsValueAndNotSet() {
        Account dealer = dealer();
        setSyncFlag(true);
        Package__c elw = [SELECT Id FROM Package__c
                          WHERE RecordType.DeveloperName = 'Extended_Limited_Warranty' LIMIT 1];
        mirrorFor(dealer.Id, elw.Id);

        // Blank master → the plain "not set" hint (today's org state).
        DealerPackageSyncController.AuthoringDTO dto =
            DealerPackageSyncController.getDealerAuthoring(dealer.Id);
        System.assertEquals(1, dto.packages.size());
        System.assertEquals(null, dto.packages[0].masterCommercialSurcharge);
        System.assertEquals('Master: not set', dto.packages[0].masterCommercialLabel);

        // A master value is surfaced as a server-formatted hint.
        update new Package__c(Id = elw.Id, Commercial_Vehicle_Surcharge_Fee__c = 150.00);
        dto = DealerPackageSyncController.getDealerAuthoring(dealer.Id);
        System.assertEquals(150.00, dto.packages[0].masterCommercialSurcharge);
        System.assertEquals('Master: $150', dto.packages[0].masterCommercialLabel,
            'Money is formatted server-side');

        // The hint follows the master; the dealer-owned figure does not.
        Id dpId = dto.packages[0].dealerPackageId;
        update new Dealer_Package__c(Id = dpId, Commercial_Vehicle_Surcharge_Fee__c = 200.00);
        update new Package__c(Id = elw.Id, Commercial_Vehicle_Surcharge_Fee__c = 999.00);
        DealerPackageSyncService.reconcileDealerPackages(new Set<Id>{ dpId });
        dto = DealerPackageSyncController.getDealerAuthoring(dealer.Id);
        System.assertEquals(999.00, dto.packages[0].masterCommercialSurcharge,
            'The master hint tracks the current master value');
        System.assertEquals(200.00, dto.packages[0].commercialVehicleSurcharge,
            'The dealer-owned commercial figure is never refreshed from the master');
    }
}