public without sharing class BrochureController {

    @AuraEnabled
    public static List<BrochureWrapper> getActiveBrochures() {
        List<Brochure__c> brochures = [
            SELECT Id, Name, Category__c, Version_Number__c, Is_Active__c,
                   Display_Order__c, Description__c, Card_Image_URL__c,
                   (SELECT Id, Document_Type__c FROM Brochure_Documents__r)
            FROM Brochure__c
            WHERE Is_Active__c = true
            ORDER BY Category__c, Version_Number__c DESC
        ];

        Map<String, Brochure__c> latestByCategory = new Map<String, Brochure__c>();
        for (Brochure__c b : brochures) {
            if (!latestByCategory.containsKey(b.Category__c)) {
                latestByCategory.put(b.Category__c, b);
            }
        }

        Set<Id> docIds = new Set<Id>();
        for (Brochure__c b : latestByCategory.values()) {
            for (Brochure_Document__c bd : b.Brochure_Documents__r) {
                docIds.add(bd.Id);
            }
        }

        // Query ContentDocumentLinks for brochure document records
        Map<Id, Id> docRecordToContentVersionId = new Map<Id, Id>();
        Map<Id, Id> docRecordToContentDocId = new Map<Id, Id>();
        Map<Id, String> docRecordToFileName = new Map<Id, String>();
        if (!docIds.isEmpty()) {
            List<ContentDocumentLink> cdls = [
                SELECT LinkedEntityId, ContentDocumentId,
                       ContentDocument.LatestPublishedVersionId,
                       ContentDocument.Title,
                       ContentDocument.FileExtension
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :docIds
                ORDER BY ContentDocument.CreatedDate DESC
            ];
            for (ContentDocumentLink cdl : cdls) {
                if (!docRecordToContentVersionId.containsKey(cdl.LinkedEntityId)) {
                    docRecordToContentVersionId.put(cdl.LinkedEntityId, cdl.ContentDocument.LatestPublishedVersionId);
                    docRecordToContentDocId.put(cdl.LinkedEntityId, cdl.ContentDocumentId);
                    docRecordToFileName.put(cdl.LinkedEntityId, cdl.ContentDocument.Title + '.' + cdl.ContentDocument.FileExtension);
                }
            }
        }

        // Get or create ContentDistribution (public links) for all content versions
        Set<Id> allVersionIds = new Set<Id>(docRecordToContentVersionId.values());
        Map<Id, String> versionIdToPublicUrl = new Map<Id, String>();

        if (!allVersionIds.isEmpty()) {
            // Check for existing distributions
            List<ContentDistribution> existingDists = [
                SELECT Id, ContentVersionId, ContentDownloadUrl, DistributionPublicUrl
                FROM ContentDistribution
                WHERE ContentVersionId IN :allVersionIds
            ];
            for (ContentDistribution cd : existingDists) {
                versionIdToPublicUrl.put(cd.ContentVersionId, cd.ContentDownloadUrl);
            }

            // Create distributions for any that don't exist yet
            List<ContentDistribution> newDists = new List<ContentDistribution>();
            for (Id versionId : allVersionIds) {
                if (!versionIdToPublicUrl.containsKey(versionId)) {
                    ContentDistribution dist = new ContentDistribution();
                    dist.Name = 'Brochure_' + versionId;
                    dist.ContentVersionId = versionId;
                    dist.PreferencesAllowViewInBrowser = true;
                    dist.PreferencesLinkLatestVersion = true;
                    dist.PreferencesNotifyOnVisit = false;
                    dist.PreferencesPasswordRequired = false;
                    dist.PreferencesAllowOriginalDownload = true;
                    newDists.add(dist);
                }
            }

            if (!newDists.isEmpty()) {
                insert newDists;
                // Re-query to get the generated URLs
                List<ContentDistribution> insertedDists = [
                    SELECT Id, ContentVersionId, ContentDownloadUrl, DistributionPublicUrl
                    FROM ContentDistribution
                    WHERE Id IN :newDists
                ];
                for (ContentDistribution cd : insertedDists) {
                    versionIdToPublicUrl.put(cd.ContentVersionId, cd.ContentDownloadUrl);
                }
            }
        }

        // Build response wrappers
        List<BrochureWrapper> results = new List<BrochureWrapper>();
        for (Brochure__c b : latestByCategory.values()) {
            BrochureWrapper bw = new BrochureWrapper();
            bw.id = b.Id;
            bw.name = b.Name;
            bw.category = b.Category__c;
            bw.versionNumber = b.Version_Number__c;
            bw.displayOrder = b.Display_Order__c;
            bw.description = b.Description__c;
            bw.cardImageUrl = b.Card_Image_URL__c;
            bw.documents = new List<DocumentWrapper>();

            for (Brochure_Document__c bd : b.Brochure_Documents__r) {
                DocumentWrapper dw = new DocumentWrapper();
                dw.id = bd.Id;
                dw.documentType = bd.Document_Type__c;
                if (docRecordToContentVersionId.containsKey(bd.Id)) {
                    dw.contentVersionId = docRecordToContentVersionId.get(bd.Id);
                    dw.fileName = docRecordToFileName.get(bd.Id);
                    // Use public download URL for portal access
                    dw.downloadUrl = versionIdToPublicUrl.get(dw.contentVersionId);
                }
                bw.documents.add(dw);
            }

            results.add(bw);
        }

        results.sort();
        return results;
    }

    @AuraEnabled
    public static void activateBrochure(Id brochureId) {
        Brochure__c brochure = [
            SELECT Id, Category__c FROM Brochure__c WHERE Id = :brochureId LIMIT 1
        ];

        List<Brochure__c> toDeactivate = [
            SELECT Id FROM Brochure__c
            WHERE Category__c = :brochure.Category__c
            AND Is_Active__c = true
            AND Id != :brochureId
        ];

        for (Brochure__c b : toDeactivate) {
            b.Is_Active__c = false;
        }

        if (!toDeactivate.isEmpty()) {
            update toDeactivate;
        }

        brochure.Is_Active__c = true;
        update brochure;
    }

    public class BrochureWrapper implements Comparable {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String category;
        @AuraEnabled public Decimal versionNumber;
        @AuraEnabled public Decimal displayOrder;
        @AuraEnabled public String description;
        @AuraEnabled public String cardImageUrl;
        @AuraEnabled public List<DocumentWrapper> documents;

        public Integer compareTo(Object other) {
            BrochureWrapper otherBw = (BrochureWrapper) other;
            Decimal thisOrder = this.displayOrder != null ? this.displayOrder : 999;
            Decimal otherOrder = otherBw.displayOrder != null ? otherBw.displayOrder : 999;
            if (thisOrder < otherOrder) return -1;
            if (thisOrder > otherOrder) return 1;
            return 0;
        }
    }

    public class DocumentWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String documentType;
        @AuraEnabled public Id contentVersionId;
        @AuraEnabled public String fileName;
        @AuraEnabled public String downloadUrl;
    }
}