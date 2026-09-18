/**
 * CatalogueReleaseServiceTest
 *
 * Unit tests for the catalogue-release lifecycle (change-plan §11 Phase 5
 * [S/A]): publish/supersede/validation/effective-date semantics and the
 * one-Published-release invariant. Data-only object — no other Apex depends on
 * this service, so tests are pure unit (insert Catalogue_Release__c rows).
 */
@IsTest
private class CatalogueReleaseServiceTest {

    // ── Fixtures ─────────────────────────────────────────────────────────────

    private static Catalogue_Release__c makeRelease(String num, String status, Date effective) {
        return new Catalogue_Release__c(
            Name = num,
            Release_Number__c = num,
            Effective_Date__c = effective,
            Status__c = status
        );
    }

    private static Catalogue_Release__c insertRelease(String num, String status, Date effective) {
        Catalogue_Release__c rel = makeRelease(num, status, effective);
        insert rel;
        return rel;
    }

    // ── Publish + supersede semantics ────────────────────────────────────────

    @IsTest
    static void publishHonoursEffectiveDateAndSupersedesPreviousPublished() {
        // Two Drafts: V25 (earlier effective) already live, V27 (later) about to ship.
        Catalogue_Release__c v25 = insertRelease('V25', CatalogueReleaseService.STATUS_PUBLISHED, Date.newInstance(2026, 9, 1));
        Catalogue_Release__c v27 = insertRelease('V27', CatalogueReleaseService.STATUS_DRAFT, Date.newInstance(2026, 12, 1));

        Test.startTest();
        CatalogueReleaseService.ReleaseInfo published = CatalogueReleaseService.publish(v27.Id);
        Test.stopTest();

        // Effective date honoured — carried through to the Published row.
        Assert.areEqual('Published', published.status, 'new release should be Published');
        Assert.areEqual(Date.newInstance(2026, 12, 1), published.effectiveDate,
            'Effective_Date__c must be preserved on publish');

        Map<Id, Catalogue_Release__c> after = new Map<Id, Catalogue_Release__c>([
            SELECT Id, Status__c FROM Catalogue_Release__c WHERE Id IN :new Set<Id>{ v25.Id, v27.Id }
        ]);
        Assert.areEqual('Superseded', after.get(v25.Id).Status__c,
            'previously Published release must be superseded');
        Assert.areEqual('Published', after.get(v27.Id).Status__c);

        // One-Published invariant.
        Integer publishedCount = [SELECT COUNT() FROM Catalogue_Release__c
                                  WHERE Status__c = :CatalogueReleaseService.STATUS_PUBLISHED];
        Assert.areEqual(1, publishedCount, 'exactly one Published release may exist');
    }

    @IsTest
    static void publishRequiresEffectiveDate() {
        Catalogue_Release__c rel = insertRelease('V27', CatalogueReleaseService.STATUS_DRAFT, null);

        Test.startTest();
        Exception thrown = null;
        try {
            CatalogueReleaseService.publish(rel.Id);
        } catch (AuraHandledException e) {
            thrown = e;
        }
        Test.stopTest();

        Assert.isNotNull(thrown, 'publishing a Draft without an Effective Date must fail');
        Assert.isInstanceOfType(thrown, AuraHandledException.class,
            'the guard must surface as an AuraHandledException for the admin LWC');
        Catalogue_Release__c after = [SELECT Status__c FROM Catalogue_Release__c WHERE Id = :rel.Id];
        Assert.areEqual('Draft', after.Status__c, 'release must stay Draft on validation failure');
    }

    @IsTest
    static void publishValidatesStatusAndReleaseNumber() {
        Catalogue_Release__c published = insertRelease('V25', CatalogueReleaseService.STATUS_PUBLISHED, Date.newInstance(2026, 9, 1));
        Catalogue_Release__c superseded = insertRelease('V24', CatalogueReleaseService.STATUS_SUPERSEDED, Date.newInstance(2026, 6, 1));
        Catalogue_Release__c draftNoNumber = new Catalogue_Release__c(Name = 'blank number', Status__c = CatalogueReleaseService.STATUS_DRAFT);
        insert draftNoNumber;

        Test.startTest();
        // Publishing a non-Draft is refused.
        Exception err1 = capturePublishError(published.Id);
        Exception err2 = capturePublishError(superseded.Id);
        // Draft without a release number is refused.
        Exception err3 = capturePublishError(draftNoNumber.Id);
        Test.stopTest();

        Assert.isNotNull(err1, 'a Published release cannot be published again');
        Assert.isNotNull(err2, 'a Superseded release cannot be published');
        Assert.isNotNull(err3, 'a Draft without a Release Number cannot be published');
    }

    @IsTest
    static void publishRejectsDuplicateReleaseNumberAmongActiveBooks() {
        insertRelease('V25', CatalogueReleaseService.STATUS_PUBLISHED, Date.newInstance(2026, 9, 1));
        Catalogue_Release__c dupDraft = insertRelease('V25', CatalogueReleaseService.STATUS_DRAFT, Date.newInstance(2026, 12, 1));

        Test.startTest();
        Exception err = capturePublishError(dupDraft.Id);
        Test.stopTest();

        Assert.isNotNull(err, 'duplicate Release Number across Draft/Published must be rejected');
        Assert.isInstanceOfType(err, AuraHandledException.class);
    }

    @IsTest
    static void createAndUpdateDraftRoundTrip() {
        Test.startTest();
        CatalogueReleaseService.ReleaseInfo created = CatalogueReleaseService.createDraft(
            'V28 Draft', 'V28', Date.newInstance(2027, 1, 1), 'Next book');
        CatalogueReleaseService.ReleaseInfo updated = CatalogueReleaseService.updateDraft(
            created.id, 'V28 renamed', 'V28', Date.newInstance(2027, 2, 1), 'Moved');
        Test.stopTest();

        Assert.areEqual('V28 renamed', updated.name);
        Assert.areEqual(Date.newInstance(2027, 2, 1), updated.effectiveDate);
        Assert.areEqual('Moved', updated.notes);

        // Editing a Published release is refused.
        Catalogue_Release__c live = insertRelease('V26', CatalogueReleaseService.STATUS_PUBLISHED, Date.newInstance(2026, 9, 1));
        String err = null;
        try {
            CatalogueReleaseService.updateDraft(live.Id, 'nope', 'V26', Date.newInstance(2026, 9, 1), null);
        } catch (AuraHandledException e) {
            err = e.getMessage();
        }
        Assert.isNotNull(err, 'Published releases must be immutable via updateDraft');
    }

    @IsTest
    static void createDraftRejectsDuplicateNumber() {
        insertRelease('V25', CatalogueReleaseService.STATUS_DRAFT, Date.newInstance(2026, 9, 1));
        String err = null;
        try {
            CatalogueReleaseService.createDraft('V25 again', 'V25', Date.newInstance(2026, 9, 1), null);
        } catch (AuraHandledException e) {
            err = e.getMessage();
        }
        Assert.isNotNull(err, 'duplicate Release Number on create must be rejected');
    }

    // ── Manual lifecycle: unpublish rollback + supersede ────────────────────

    @IsTest
    static void unpublishRollsPublishedBackToDraft() {
        Catalogue_Release__c live = insertRelease('V25', CatalogueReleaseService.STATUS_PUBLISHED, Date.newInstance(2026, 9, 1));

        Test.startTest();
        CatalogueReleaseService.ReleaseInfo rolled = CatalogueReleaseService.unpublish(live.Id);
        Test.stopTest();

        Assert.areEqual('Draft', rolled.status, 'unpublish must return the release to Draft');

        // Unpublishing a Draft is refused.
        String err = null;
        try {
            CatalogueReleaseService.unpublish(live.Id);
        } catch (AuraHandledException e) {
            err = e.getMessage();
        }
        Assert.isNotNull(err, 'only Published releases can be unpublished');
    }

    @IsTest
    static void manualSupersedeArchivesPublishedRelease() {
        Catalogue_Release__c live = insertRelease('V25', CatalogueReleaseService.STATUS_PUBLISHED, Date.newInstance(2026, 9, 1));

        Test.startTest();
        CatalogueReleaseService.ReleaseInfo archived = CatalogueReleaseService.supersede(live.Id);
        Test.stopTest();

        Assert.areEqual('Superseded', archived.status);
        // Superseding a Draft is refused.
        Catalogue_Release__c draft = insertRelease('V28', CatalogueReleaseService.STATUS_DRAFT, Date.newInstance(2027, 1, 1));
        String err = null;
        try {
            CatalogueReleaseService.supersede(draft.Id);
        } catch (AuraHandledException e) {
            err = e.getMessage();
        }
        Assert.isNotNull(err, 'only Published releases can be superseded');
    }

    @IsTest
    static void deleteDraftOnly() {
        Catalogue_Release__c draft = insertRelease('V28', CatalogueReleaseService.STATUS_DRAFT, Date.newInstance(2027, 1, 1));
        Catalogue_Release__c live = insertRelease('V25', CatalogueReleaseService.STATUS_PUBLISHED, Date.newInstance(2026, 9, 1));

        Test.startTest();
        CatalogueReleaseService.deleteDraft(draft.Id);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Catalogue_Release__c WHERE Id = :draft.Id]);

        String err = null;
        try {
            CatalogueReleaseService.deleteDraft(live.Id);
        } catch (AuraHandledException e) {
            err = e.getMessage();
        }
        Assert.isNotNull(err, 'Published releases must never be deletable');
        Assert.areEqual(1, [SELECT COUNT() FROM Catalogue_Release__c WHERE Id = :live.Id]);
    }

    // ── Read surface ─────────────────────────────────────────────────────────

    @IsTest
    static void getReleasesOrdersAndRollsUpGroupCounts() {
        Catalogue_Release__c older = insertRelease('V24', CatalogueReleaseService.STATUS_SUPERSEDED, Date.newInstance(2026, 6, 1));
        Catalogue_Release__c newer = insertRelease('V25', CatalogueReleaseService.STATUS_PUBLISHED, Date.newInstance(2026, 9, 1));

        // Two plan-type families linked to the newer release, one with packages.
        Package_Group__c g1 = new Package_Group__c(Name = 'Essential Warranties', Active__c = true,
            Catalogue_Release__c = newer.Id);
        Package_Group__c g2 = new Package_Group__c(Name = 'Tire and Rim Protection', Active__c = true,
            Catalogue_Release__c = newer.Id);
        insert new List<Package_Group__c>{ g1, g2 };

        Test.startTest();
        List<CatalogueReleaseService.ReleaseInfo> infos = CatalogueReleaseService.getReleases();
        List<CatalogueReleaseService.GroupInfo> groups = CatalogueReleaseService.getLinkedGroups(newer.Id);
        Test.stopTest();

        // Newest effective date first.
        Assert.areEqual('V25', infos[0].releaseNumber);
        Assert.areEqual(2, infos[0].groupCount, 'group count rollup must reflect linked groups');
        Assert.areEqual('V24', infos[1].releaseNumber);
        Assert.areEqual(0, infos[1].groupCount);

        Assert.areEqual(2, groups.size());
        Assert.areEqual('Essential Warranties', groups[0].name);
    }

    @IsTest
    static void publishWithNoPriorPublishedStillSucceeds() {
        // First book ever — nothing to supersede.
        Catalogue_Release__c first = insertRelease('V23', CatalogueReleaseService.STATUS_DRAFT, Date.newInstance(2026, 1, 1));

        Test.startTest();
        CatalogueReleaseService.ReleaseInfo published = CatalogueReleaseService.publish(first.Id);
        Test.stopTest();

        Assert.areEqual('Published', published.status);
        Integer publishedCount = [SELECT COUNT() FROM Catalogue_Release__c
                                  WHERE Status__c = :CatalogueReleaseService.STATUS_PUBLISHED];
        Assert.areEqual(1, publishedCount);
    }

    // ── Helper ───────────────────────────────────────────────────────────────

    private static Exception capturePublishError(Id releaseId) {
        try {
            CatalogueReleaseService.publish(releaseId);
            return null;
        } catch (AuraHandledException e) {
            return e;
        }
    }
}