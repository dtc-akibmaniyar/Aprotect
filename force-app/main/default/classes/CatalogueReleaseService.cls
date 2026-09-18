/**
 * CatalogueReleaseService
 *
 * Catalogue-release lifecycle service (change-implementation plan §04.1 / §11
 * Phase 5 [S/A] — "Catalogue_Release__c lifecycle service + publish/supersede
 * rules"; §09.2 "Catalogue release lifecycle"). Built P1 (object + fields),
 * lifecycle P5.
 *
 * What it owns
 * ────────────
 * The one-`Published`-release invariant for the A-Protect plan book:
 *
 *   • Draft      — admin-authored book in progress. Editable (Name,
 *                  Release_Number__c, Effective_Date__c, Notes__c); deletable.
 *   • Published  — the live book. Exactly ONE release may be Published at any
 *                  time. Publishing validates the Draft and supersedes the
 *                  previously Published release (it becomes Superseded — kept
 *                  for audit).
 *   • Superseded — historical. Read-only; publish/supersede/unpublish refuse.
 *
 * Effective_Date__c is honoured at publish: a Draft without an effective date
 * cannot be published (an admin cannot ship a book whose effective date is
 * unknown). The effective date itself is preserved on the Published record so
 * quoting/admin tooling can reason about which book was live when (design R1
 * date semantics are enforced by the schedule resolver; this service keeps the
 * book-level invariant).
 *
 * Data-only by construction: no Apex/JS behaviour in the dealer portal
 * depends on this service; it exists for internal admins (admin LWCs call the
 * @AuraEnabled surface below). Publish/supersede are pure status transitions
 * on Catalogue_Release__c rows — rollback is data (unpublish → Draft), never
 * a code deploy (plan §11 Phase 5 rollback).
 */
public with sharing class CatalogueReleaseService {

    public static final String STATUS_DRAFT = 'Draft';
    public static final String STATUS_PUBLISHED = 'Published';
    public static final String STATUS_SUPERSEDED = 'Superseded';

    /** Admin-surface summary row for one release. */
    public class ReleaseInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String releaseNumber;
        @AuraEnabled public Date effectiveDate;
        @AuraEnabled public String status;
        @AuraEnabled public String notes;
        /** Number of Package_Group__c rows linked to this release (plan types). */
        @AuraEnabled public Integer groupCount;
    }

    /** One Package_Group__c (plan type family) linked to a release. */
    public class GroupInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Boolean active;
        /** Number of Package__c records under the group. */
        @AuraEnabled public Integer packageCount;
    }

    private static final Pattern NON_BLANK = Pattern.compile('\\S');

    // ── Read surface ─────────────────────────────────────────────────────────

    /**
     * All releases, newest effective date first (nulls last), then most
     * recently created first. Each row carries its linked plan-type count so
     * the admin list can show coverage without a second query per row.
     */
    @AuraEnabled(cacheable=true)
    public static List<ReleaseInfo> getReleases() {
        List<Catalogue_Release__c> releases = [
            SELECT Id, Name, Release_Number__c, Effective_Date__c, Status__c, Notes__c,
                   (SELECT Id FROM Package_Groups__r)
            FROM Catalogue_Release__c
            ORDER BY Effective_Date__c DESC NULLS LAST, CreatedDate DESC
        ];

        List<ReleaseInfo> infos = new List<ReleaseInfo>();
        for (Catalogue_Release__c rel : releases) {
            ReleaseInfo info = new ReleaseInfo();
            info.id = rel.Id;
            info.name = rel.Name;
            info.releaseNumber = rel.Release_Number__c;
            info.effectiveDate = rel.Effective_Date__c;
            info.status = rel.Status__c;
            info.notes = rel.Notes__c;
            info.groupCount = rel.Package_Groups__r == null ? 0 : rel.Package_Groups__r.size();
            infos.add(info);
        }
        return infos;
    }

    /**
     * The plan-type families (Package_Group__c rows) linked to one release —
     * the "show linked plan types" surface of the release admin LWC.
     */
    @AuraEnabled(cacheable=true)
    public static List<GroupInfo> getLinkedGroups(Id releaseId) {
        List<Package_Group__c> groups = [
            SELECT Id, Name, Active__c,
                   (SELECT Id FROM Packages__r)
            FROM Package_Group__c
            WHERE Catalogue_Release__c = :releaseId
            ORDER BY Sort_Order__c NULLS LAST, Name
        ];

        List<GroupInfo> infos = new List<GroupInfo>();
        for (Package_Group__c g : groups) {
            GroupInfo info = new GroupInfo();
            info.id = g.Id;
            info.name = g.Name;
            info.active = g.Active__c;
            info.packageCount = g.Packages__r == null ? 0 : g.Packages__r.size();
            infos.add(info);
        }
        return infos;
    }

    // ── Draft authoring ──────────────────────────────────────────────────────

    /**
     * Create a new Draft release. Only Draft rows can be created through this
     * service; Release_Number__c is required and must not collide with an
     * existing Draft/Published release.
     */
    @AuraEnabled
    public static ReleaseInfo createDraft(String name, String releaseNumber,
            Date effectiveDate, String notes) {
        validateCommon(name, releaseNumber);
        assertNumberAvailable(releaseNumber, null);

        Catalogue_Release__c rel = new Catalogue_Release__c(
            Name = normalizeName(name, releaseNumber),
            Release_Number__c = releaseNumber.trim(),
            Effective_Date__c = effectiveDate,
            Notes__c = notes,
            Status__c = STATUS_DRAFT
        );
        insert rel;
        return toInfo(fetchById(rel.Id));
    }

    /**
     * Update a Draft release's authoring fields. Published/Superseded rows are
     * immutable — an admin rolls a Published book back to Draft (unpublish)
     * before editing it.
     */
    @AuraEnabled
    public static ReleaseInfo updateDraft(Id releaseId, String name, String releaseNumber,
            Date effectiveDate, String notes) {
        Catalogue_Release__c rel = fetchById(releaseId);
        if (rel == null) {
            throw new AuraHandledException('Release not found.');
        }
        if (rel.Status__c != STATUS_DRAFT) {
            throw new AuraHandledException(
                'Only Draft releases can be edited. Unpublish or supersede the release first.');
        }
        validateCommon(name, releaseNumber);
        assertNumberAvailable(releaseNumber, releaseId);

        rel.Name = normalizeName(name, releaseNumber);
        rel.Release_Number__c = releaseNumber.trim();
        rel.Effective_Date__c = effectiveDate;
        rel.Notes__c = notes;
        update rel;
        return toInfo(fetchById(rel.Id));
    }

    /** Delete a Draft release. Published/Superseded rows are never deletable. */
    @AuraEnabled
    public static void deleteDraft(Id releaseId) {
        Catalogue_Release__c rel = fetchById(releaseId);
        if (rel == null) {
            return; // idempotent — already gone
        }
        if (rel.Status__c != STATUS_DRAFT) {
            throw new AuraHandledException(
                'Only Draft releases can be deleted. Superseded releases are kept for audit.');
        }
        delete rel;
    }

    // ── Lifecycle transitions ────────────────────────────────────────────────

    /**
     * Publish a Draft release, honouring its Effective_Date__c (a Draft with
     * no effective date cannot ship). The previously Published release — if
     * any — is superseded in the same transaction, keeping the one-Published
     * invariant. Returns the refreshed Published row.
     */
    @AuraEnabled
    public static ReleaseInfo publish(Id releaseId) {
        Catalogue_Release__c rel = fetchById(releaseId);
        if (rel == null) {
            throw new AuraHandledException('Release not found.');
        }
        if (rel.Status__c != STATUS_DRAFT) {
            throw new AuraHandledException(
                'Only Draft releases can be published (current status: ' + rel.Status__c + ').');
        }
        if (rel.Effective_Date__c == null) {
            throw new AuraHandledException(
                'Set an Effective Date before publishing — the release cannot ship without one.');
        }
        if (String.isBlank(rel.Release_Number__c)) {
            throw new AuraHandledException('Release Number is required before publishing.');
        }
        assertNumberAvailable(rel.Release_Number__c, releaseId);

        // Supersede the previously Published release in the same transaction.
        List<Catalogue_Release__c> previousPublished = [
            SELECT Id, Status__c FROM Catalogue_Release__c
            WHERE Status__c = :STATUS_PUBLISHED AND Id != :releaseId
        ];
        for (Catalogue_Release__c prev : previousPublished) {
            prev.Status__c = STATUS_SUPERSEDED;
        }
        if (!previousPublished.isEmpty()) {
            update previousPublished;
        }

        rel.Status__c = STATUS_PUBLISHED;
        update rel;
        return toInfo(fetchById(rel.Id));
    }

    /**
     * Rollback path (plan §11 Phase 5 rollback — "releases are data"): return a
     * Published release to Draft. Only used when a published book must be
     * pulled; the row stays fully editable afterwards.
     */
    @AuraEnabled
    public static ReleaseInfo unpublish(Id releaseId) {
        Catalogue_Release__c rel = fetchById(releaseId);
        if (rel == null) {
            throw new AuraHandledException('Release not found.');
        }
        if (rel.Status__c != STATUS_PUBLISHED) {
            throw new AuraHandledException(
                'Only Published releases can be unpublished (current status: ' + rel.Status__c + ').');
        }
        rel.Status__c = STATUS_DRAFT;
        update rel;
        return toInfo(fetchById(rel.Id));
    }

    /** Manually supersede a Published release (archived for audit). */
    @AuraEnabled
    public static ReleaseInfo supersede(Id releaseId) {
        Catalogue_Release__c rel = fetchById(releaseId);
        if (rel == null) {
            throw new AuraHandledException('Release not found.');
        }
        if (rel.Status__c != STATUS_PUBLISHED) {
            throw new AuraHandledException(
                'Only Published releases can be superseded (current status: ' + rel.Status__c + ').');
        }
        rel.Status__c = STATUS_SUPERSEDED;
        update rel;
        return toInfo(fetchById(rel.Id));
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private static void validateCommon(String name, String releaseNumber) {
        if (String.isBlank(releaseNumber) || !NON_BLANK.matcher(releaseNumber).find()) {
            throw new AuraHandledException('Release Number is required.');
        }
        if (String.isBlank(name) || !NON_BLANK.matcher(name).find()) {
            throw new AuraHandledException('Release Name is required.');
        }
    }

    /** The Name field defaults to the release number when no name is given. */
    private static String normalizeName(String name, String releaseNumber) {
        return (String.isBlank(name) || !NON_BLANK.matcher(name).find())
            ? releaseNumber.trim()
            : name.trim();
    }

    /** Release numbers must be unique across Draft + Published (history may repeat). */
    private static void assertNumberAvailable(String releaseNumber, Id excludeId) {
        String num = releaseNumber == null ? '' : releaseNumber.trim();
        Integer collisions = [
            SELECT COUNT()
            FROM Catalogue_Release__c
            WHERE Release_Number__c = :num
              AND Status__c IN :new List<String>{ STATUS_DRAFT, STATUS_PUBLISHED }
              AND Id != :excludeId
        ];
        if (collisions > 0) {
            throw new AuraHandledException(
                'Release Number "' + num + '" is already in use by another Draft or Published release.');
        }
    }

    private static Catalogue_Release__c fetchById(Id releaseId) {
        List<Catalogue_Release__c> rows = [
            SELECT Id, Name, Release_Number__c, Effective_Date__c, Status__c, Notes__c
            FROM Catalogue_Release__c
            WHERE Id = :releaseId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static ReleaseInfo toInfo(Catalogue_Release__c rel) {
        if (rel == null) {
            return null;
        }
        ReleaseInfo info = new ReleaseInfo();
        info.id = rel.Id;
        info.name = rel.Name;
        info.releaseNumber = rel.Release_Number__c;
        info.effectiveDate = rel.Effective_Date__c;
        info.status = rel.Status__c;
        info.notes = rel.Notes__c;
        return info;
    }
}