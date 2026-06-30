trigger ContentDocumentLinkPackageLogoTrigger on ContentDocumentLink (after insert) {
    Set<Id> linkedEntityIds = new Set<Id>();
    List<ContentDocumentLink> relevantLinks = new List<ContentDocumentLink>();

    for (ContentDocumentLink cdl : Trigger.new) {
        if (cdl.LinkedEntityId != null) {
            linkedEntityIds.add(cdl.LinkedEntityId);
            relevantLinks.add(cdl);
        }
    }

    if (linkedEntityIds.isEmpty()) return;

    // Filter to only Package_File__c IDs by object type prefix to avoid cross-object SOQL errors
    Set<Id> packageFileIds = new Set<Id>();
    String packageFilePrefix = Package_File__c.getSObjectType().getDescribe().getKeyPrefix();
    for (Id lid : linkedEntityIds) {
        if (String.valueOf(lid).startsWith(packageFilePrefix)) {
            packageFileIds.add(lid);
        }
    }

    if (packageFileIds.isEmpty()) return;

    Map<Id, Package_File__c> logoPackageFiles = new Map<Id, Package_File__c>([
        SELECT Id, File_Type_del__c
        FROM Package_File__c
        WHERE Id IN :packageFileIds
          AND File_Type_del__c = 'Package Logo'
    ]);

    if (logoPackageFiles.isEmpty()) return;

    // Re-query the inserted ContentDocumentLinks so we can update Visibility and ShareType
    Set<Id> cdlIds = new Set<Id>();
    for (ContentDocumentLink cdl : relevantLinks) {
        if (logoPackageFiles.containsKey(cdl.LinkedEntityId)) {
            cdlIds.add(cdl.Id);
        }
    }

    if (!cdlIds.isEmpty()) {
        List<ContentDocumentLink> cdlsToUpdate = [
            SELECT Id, Visibility, ShareType
            FROM ContentDocumentLink
            WHERE Id IN :cdlIds
        ];
        for (ContentDocumentLink cdl : cdlsToUpdate) {
            cdl.Visibility = 'AllUsers';
            cdl.ShareType  = 'V';
        }
        update cdlsToUpdate;
    }

    // Collect ContentDocumentIds for links pointing to Package Logo files
    Set<Id> contentDocIds = new Set<Id>();
    for (ContentDocumentLink cdl : relevantLinks) {
        if (logoPackageFiles.containsKey(cdl.LinkedEntityId)) {
            contentDocIds.add(cdl.ContentDocumentId);
        }
    }

    if (contentDocIds.isEmpty()) return;

    Map<Id, ContentDocument> contentDocs = new Map<Id, ContentDocument>([
        SELECT Id, Title, LatestPublishedVersionId
        FROM ContentDocument
        WHERE Id IN :contentDocIds
    ]);

    // Collect version IDs to check for existing distributions (duplicate prevention)
    Set<Id> versionIds = new Set<Id>();
    for (ContentDocument doc : contentDocs.values()) {
        if (doc.LatestPublishedVersionId != null) versionIds.add(doc.LatestPublishedVersionId);
    }

    Set<Id> alreadyDistributed = new Set<Id>();
    if (!versionIds.isEmpty()) {
        for (ContentDistribution existing : [
            SELECT ContentVersionId
            FROM ContentDistribution
            WHERE ContentVersionId IN :versionIds
        ]) {
            alreadyDistributed.add(existing.ContentVersionId);
        }
    }

    // Build a map of ContentDocumentId -> LinkedEntityId (Package_File__c Id)
    Map<Id, Id> contentDocToPackageFile = new Map<Id, Id>();
    for (ContentDocumentLink cdl : relevantLinks) {
        if (logoPackageFiles.containsKey(cdl.LinkedEntityId)) {
            contentDocToPackageFile.put(cdl.ContentDocumentId, cdl.LinkedEntityId);
        }
    }

    List<ContentDistribution> toInsert = new List<ContentDistribution>();
    for (ContentDocumentLink cdl : relevantLinks) {
        if (!logoPackageFiles.containsKey(cdl.LinkedEntityId)) continue;
        ContentDocument doc = contentDocs.get(cdl.ContentDocumentId);
        if (doc == null || doc.LatestPublishedVersionId == null) continue;
        if (alreadyDistributed.contains(doc.LatestPublishedVersionId)) continue;

        ContentDistribution dist = new ContentDistribution();
        dist.Name = 'Package Logo - ' + (doc.Title != null ? doc.Title : 'Image');
        dist.ContentVersionId = doc.LatestPublishedVersionId;
        dist.RelatedRecordId = cdl.LinkedEntityId; // Set to Package_File__c Id for URL lookup
        dist.PreferencesAllowViewInBrowser = true;
        dist.PreferencesLinkLatestVersion = true;
        dist.PreferencesNotifyOnVisit = false;
        dist.PreferencesPasswordRequired = false;
        dist.PreferencesExpires = false;
        toInsert.add(dist);
        alreadyDistributed.add(doc.LatestPublishedVersionId); // prevent dupes within same batch
    }

    if (!toInsert.isEmpty()) {
        insert toInsert;
    }
}