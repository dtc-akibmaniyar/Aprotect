trigger SetFileVisibility on ContentDocumentLink (before insert) {

    // Collect ContentDocumentIds
    Set<Id> contentDocIds = new Set<Id>();
    for (ContentDocumentLink cdl : Trigger.new) {
        if (cdl.ContentDocumentId != null) {
            contentDocIds.add(cdl.ContentDocumentId);
        }
    }
    system.debug('contentDocIds:: '+contentDocIds);

    // Query ContentDocument titles
    Map<Id, ContentDocument> contentDocs = new Map<Id, ContentDocument>(
        [
            SELECT Id, Title
            FROM ContentDocument
            WHERE Id IN :contentDocIds
        ]
    );

    // Set visibility based on title
    for (ContentDocumentLink cdl : Trigger.new) {
        ContentDocument cd = contentDocs.get(cdl.ContentDocumentId);
        if (cd != null && cd.Title != null && cd.Title.endsWith('_Completed.pdf')) {
            cdl.Visibility = 'AllUsers';
        }
    }
}