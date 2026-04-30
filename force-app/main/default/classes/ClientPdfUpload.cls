// File: ClientPdfUpload.cls
public with sharing class ClientPdfUpload {
    public class SaveResult {
        @AuraEnabled public Id contentVersionId;
        @AuraEnabled public String downloadUrl;
    }

    @AuraEnabled
    public static SaveResult savePdf(Id applicationId, String base64Data, String fileName){
        if(String.isBlank(base64Data)) throw new AuraHandledException('No PDF data.');

        // Support both pure base64 and data URLs
        String clean = base64Data.contains(',') ? base64Data.substringAfter(',') : base64Data;

        ContentVersion cv = new ContentVersion();
        cv.Title = (String.isBlank(fileName) ? 'Application Summary' : fileName).replace('.pdf','');
        cv.PathOnClient = (String.isBlank(fileName) ? 'ApplicationSummary.pdf' : fileName);
        cv.VersionData = EncodingUtil.base64Decode(clean);
        insert cv;

        ContentVersion insertedV = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        insert new ContentDocumentLink(
            ContentDocumentId = insertedV.ContentDocumentId,
            LinkedEntityId = applicationId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        SaveResult res = new SaveResult();
        res.contentVersionId = cv.Id;
        res.downloadUrl = '/sfc/servlet.shepherd/version/download/' + cv.Id;
        return res;
    }
}