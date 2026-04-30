public without sharing class ContentManagerService {
    
    @AuraEnabled
    public static String getRecord(String recordId) {
        try {
            // Query the Application record with related Contact information
            List<SObject> records = Database.query(
                'SELECT Id, Customer_Name__r.Name, Customer_Name__r.PersonEmail ' +
                'FROM Application__c ' +
                'WHERE Id = :recordId ' +
                'LIMIT 1'
            );
            
            if (!records.isEmpty()) {
                return JSON.serialize(records[0]);
            }
            return null;
        } catch (Exception e) {
            System.debug('Error in getRecord: ' + e.getMessage());
            throw new AuraHandledException('Error fetching record: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static String getContentDetails(String recordId) {
        List<ContentDocumentLink> contentDocumentList = [SELECT ContentDocumentId, LinkedEntityId 
                                                            FROM   ContentDocumentLink 
                                                            WHERE  LinkedEntityId =: recordId AND ContentDocument.Title IN('Total Loss Coverage','Extended Limited Warranty','Tire & Rim Protection Plan')];
        Set<Id> contentDocumentId = new Set<Id>();
            
        for(ContentDocumentLink cdl : contentDocumentList){
            contentDocumentId.add(cdl.ContentDocumentId);
        }
            
        List<ContentVersion> contentVersionList = [SELECT Id, VersionData, FileType, Title, FileExtension,
                                                    ContentDocument.CreatedBy.Name, ContentDocument.ContentSize,
                                                    CreatedDate, ContentDocumentId, ContentDocument.FileType
                                                    FROM   ContentVersion 
                                                    WHERE  ContentDocumentId IN : contentDocumentId];
        system.debug('*** Content Version List: ' + contentVersionList);
        system.debug('*** Content Version List size: ' + contentVersionList.size());
                                                    return JSON.serialize(contentVersionList);
    }

    @AuraEnabled
    public static void deleteContentDocument(String recordId) {
        Database.delete(recordId);
    }

    public static string ContentType(String fileType) {

        switch on fileType.toLowerCase(){
            when 'docx' {
                return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
            }
            when 'csv' {
                return 'application/vnd.ms-excel';
            }
            when 'wav' {
                return 'audio/wav';
            }
            when 'wmv' {
                return 'video/x-ms-wmv';
            }
            when 'mp3' {
                return 'audio/mpeg';
            }
            when 'mp4' {
                return 'video/mp4';
            }
            when 'png' {
                return 'image/png';
                
            }
            when 'pdf' {
                return 'application/pdf';
                
            }
            when else {
                return 'image/jpeg';
            }
        }

    }
}