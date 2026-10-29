/**
 * SignatureCleanup
 * Sweeper for the signature PDF chain.
 *  1. Deletes SIGTMP% StaticResources older than N minutes that no live
 *     Application_Signature__c row still points at.
 *  2. Clears rows stuck in RENDER_FAILED that still carry a resource id:
 *     deletes the image, then nulls the pointer so a retry starts clean.
 * Runs without sharing so it sees every row, and it always deletes the images
 * BEFORE the DML (a callout cannot follow DML in the same transaction).
 */
public without sharing class SignatureCleanup implements Schedulable {

    public static final Integer DEFAULT_ORPHAN_MINUTES = 15;
    public static final Integer MAX_PER_RUN = 40;

    public void execute(SchedulableContext ctx) {
        run(DEFAULT_ORPHAN_MINUTES);
    }

    public static String run(Integer orphanMinutes) {
        Integer minutes = (orphanMinutes == null || orphanMinutes < 1)
            ? DEFAULT_ORPHAN_MINUTES : orphanMinutes;
        Datetime cutoff = System.now().addMinutes(-minutes);
        String failedStatus = SignatureService.ST_RENDER_FAILED;

        Integer imagesDeleted = 0;
        Integer rowsCleared = 0;
        Integer errors = 0;

        // A pointer a live row still owns must never be swept.
        Set<String> inUse = new Set<String>();
        for (Application_Signature__c s : [
            SELECT ResourceId__c
            FROM Application_Signature__c
            WHERE ResourceId__c != null
            LIMIT 5000
        ]) {
            inUse.add(s.ResourceId__c);
        }

        List<StaticResource> orphans = [
            SELECT Id, Name
            FROM StaticResource
            WHERE Name LIKE 'SIGTMP%' AND CreatedDate < :cutoff
            LIMIT :MAX_PER_RUN
        ];
        for (StaticResource r : orphans) {
            if (inUse.contains(r.Id)) {
                continue;
            }
            try {
                SignatureResourceClient.deleteResource(r.Id);
                imagesDeleted++;
            } catch (Exception e) {
                errors++;
            }
        }

        List<Application_Signature__c> stuck = [
            SELECT Id, ResourceId__c
            FROM Application_Signature__c
            WHERE Status__c = :failedStatus AND ResourceId__c != null AND LastModifiedDate < :cutoff
            LIMIT :MAX_PER_RUN
        ];
        List<Application_Signature__c> clears = new List<Application_Signature__c>();
        for (Application_Signature__c s : stuck) {
            try {
                SignatureResourceClient.deleteResource(s.ResourceId__c);
            } catch (Exception e) {
                errors++;
            }
            clears.add(new Application_Signature__c(
                Id = s.Id,
                ResourceId__c = null,
                ResourceName__c = null
            ));
        }
        if (!clears.isEmpty()) {
            update clears;
            rowsCleared = clears.size();
        }

        return 'orphan_images_deleted=' + imagesDeleted
            + ' stuck_rows_cleared=' + rowsCleared
            + ' errors=' + errors;
    }
}