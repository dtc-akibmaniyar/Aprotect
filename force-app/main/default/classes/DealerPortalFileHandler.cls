/**
 * File handling utility for Dealer Portal
 * Handles file operations for dealer packages and application packages
 */
public without sharing class DealerPortalFileHandler {
    
    // DTO for file information
    public class FileDTO {
        @AuraEnabled public String Id;
        @AuraEnabled public String ContentDocumentId;
        @AuraEnabled public String Name;
        @AuraEnabled public String Title;
        @AuraEnabled public Decimal Size;
        @AuraEnabled public String FileType;
        @AuraEnabled public DateTime CreatedDate;
        @AuraEnabled public String CreatedByName;
        @AuraEnabled public String DownloadUrl;
        @AuraEnabled public String ViewUrl; // For viewing PDFs in new tab
        @AuraEnabled public String formattedSize; // Human readable size
        @AuraEnabled public String iconName; // Icon for file type
        
        public FileDTO() {}
    }
    
    // Response for file operations
    public class FileResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public List<FileDTO> data;
        @AuraEnabled public Integer fileCount;
        
        public FileResponse() {}
    }
    
    /**
     * Get PDF content as base64 for viewing in new tab
     */
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getPDFContent(String contentDocumentId) {
        try {
            System.debug('🔍 Getting PDF content for document: ' + contentDocumentId);
            
            if (String.isBlank(contentDocumentId)) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'Content Document ID is required'
                };
            }
            
            // Query for the PDF content
            List<ContentVersion> contentVersions = [
                SELECT Id, Title, FileType, ContentSize, VersionData
                FROM ContentVersion 
                WHERE ContentDocumentId = :contentDocumentId 
                AND IsLatest = true
                AND FileType = 'PDF'
                LIMIT 1
            ];
            
            if (contentVersions.isEmpty()) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'PDF file not found'
                };
            }
            
            ContentVersion pdfVersion = contentVersions[0];
            
            // Convert PDF blob to base64
            String base64Data = EncodingUtil.base64Encode(pdfVersion.VersionData);
            
            System.debug('✅ PDF content retrieved. Size: ' + pdfVersion.ContentSize + ' bytes');
            
            return new Map<String, Object>{
                'success' => true,
                'fileName' => pdfVersion.Title,
                'fileType' => pdfVersion.FileType,
                'fileSize' => pdfVersion.ContentSize,
                'base64Data' => base64Data
            };
            
        } catch (Exception e) {
            System.debug('❌ Error getting PDF content: ' + e.getMessage());
            return new Map<String, Object>{
                'success' => false,
                'error' => 'Failed to retrieve PDF: ' + e.getMessage()
            };
        }
    }
    
    /**
     * *** NEW: Remove file from package ***
     * @param packageId The dealer package ID
     * @param contentDocumentId The ContentDocument ID to remove
     * @return FileResponse with operation result
     */
    @AuraEnabled
    public static FileResponse removeFileFromPackage(String packageId, String contentDocumentId) {
        FileResponse response = new FileResponse();
        
        try {
            System.debug('🗑️ Starting removeFileFromPackage');
            System.debug('📦 Package ID: ' + packageId);
            System.debug('📄 Document ID: ' + contentDocumentId);
            
            if (String.isBlank(packageId)) {
                response.success = false;
                response.message = 'Package ID is required';
                return response;
            }
            
            if (String.isBlank(contentDocumentId)) {
                response.success = false;
                response.message = 'Content Document ID is required';
                return response;
            }
            
            // Find the ContentDocumentLink to remove
            List<ContentDocumentLink> linksToDelete = [
                SELECT Id, ContentDocument.Title
                FROM ContentDocumentLink 
                WHERE LinkedEntityId = :packageId 
                AND ContentDocumentId = :contentDocumentId
                LIMIT 1
            ];
            
            if (linksToDelete.isEmpty()) {
                response.success = false;
                response.message = 'File association not found. The file may have already been removed.';
                return response;
            }
            
            ContentDocumentLink linkToDelete = linksToDelete[0];
            String fileName = linkToDelete.ContentDocument.Title;
            
            System.debug('🔍 Found link to delete: ' + linkToDelete.Id);
            System.debug('📄 File name: ' + fileName);
            
            // Delete the ContentDocumentLink (removes association, not the file itself)
            delete linkToDelete;
            
            response.success = true;
            response.message = 'File "' + fileName + '" has been removed from this package successfully.';
            response.fileCount = 1;
            
            System.debug('✅ File removed successfully: ' + fileName);
            
        } catch (DmlException e) {
            System.debug('❌ DML Error in removeFileFromPackage: ' + e.getMessage());
            System.debug('❌ DML Stack Trace: ' + e.getStackTraceString());
            
            response.success = false;
            response.message = 'Database error while removing file: ' + e.getDmlMessage(0);
            
        } catch (Exception e) {
            System.debug('❌ General Error in removeFileFromPackage: ' + e.getMessage());
            System.debug('❌ General Stack Trace: ' + e.getStackTraceString());
            
            response.success = false;
            response.message = 'Error removing file from package: ' + e.getMessage();
        }
        
        return response;
    }
    
    /**
     * Get existing files associated with a dealer package
     * @param packageId The dealer package ID
     * @return FileResponse with existing files or empty list
     */
    @AuraEnabled(cacheable=false)
    public static FileResponse getPackageFiles(String packageId) {
        FileResponse response = new FileResponse();
        
        try {
            if (String.isBlank(packageId)) {
                response.success = false;
                response.message = 'Package ID is required';
                response.data = new List<FileDTO>();
                response.fileCount = 0;
                return response;
            }
            
            // Query for ContentDocumentLinks associated with the dealer package
            // Allow all file types (not just PDF) for tire & rim images
            List<ContentDocumentLink> documentLinks = [
                SELECT Id, ContentDocumentId, ContentDocument.Title, ContentDocument.LatestPublishedVersionId,
                       ContentDocument.FileType, ContentDocument.ContentSize,
                       ContentDocument.CreatedDate, ContentDocument.CreatedBy.Name
                FROM ContentDocumentLink 
                WHERE LinkedEntityId = :packageId 
                ORDER BY ContentDocument.CreatedDate DESC
            ];
            
            system.debug(documentLinks);
            
            List<FileDTO> fileDTOs = new List<FileDTO>();
            
            for (ContentDocumentLink link : documentLinks) {
                FileDTO fileDto = new FileDTO();
                fileDto.Id = link.Id;
                fileDto.ContentDocumentId = link.ContentDocumentId;
                fileDto.Name = link.ContentDocument.Title;
                fileDto.Title = link.ContentDocument.Title;
                fileDto.Size = link.ContentDocument.ContentSize;
                fileDto.FileType = link.ContentDocument.FileType;
                fileDto.CreatedDate = link.ContentDocument.CreatedDate;
                fileDto.CreatedByName = link.ContentDocument.CreatedBy.Name;
                
                // Format file size for display
                fileDto.formattedSize = formatFileSize(link.ContentDocument.ContentSize);
                
                // Set icon based on file type
                fileDto.iconName = getFileIcon(link.ContentDocument.FileType);
                
                Organization a_ORG = [Select Id, Name, IsSandbox from Organization limit 1];

                if(a_ORG.IsSandbox){   
                    fileDto.DownloadUrl = 'https://business-platform-7607--dtcsandbox.sandbox.lightning.force.com//sfc/servlet.shepherd/document/download/' + link.ContentDocumentId+'?operationContext=S1';
                }
                else{
                   fileDto.DownloadUrl = 'https://business-platform-7607.lightning.force.com//sfc/servlet.shepherd/document/download/' + link.ContentDocumentId+'?operationContext=S1'; 
                }
                
                // Add view URL for opening in new tab (will be handled by LWC)
                fileDto.ViewUrl = 'view_pdf:' + link.ContentDocumentId;
                
                fileDTOs.add(fileDto);
            }
            
            response.success = true;
            response.data = fileDTOs;
            response.fileCount = fileDTOs.size();
            response.message = fileDTOs.size() + ' file(s) found';
            
        } catch (Exception e) {
            response.success = false;
            response.message = 'Error retrieving package files: ' + e.getMessage();
            response.data = new List<FileDTO>();
            response.fileCount = 0;
            System.debug('Error in getPackageFiles: ' + e.getMessage());
        }
        
        return response;
    }
    
    /**
     * Helper method to format file size
     */
    private static String formatFileSize(Decimal sizeInBytes) {
        if (sizeInBytes == null) return '0 KB';
        
        Decimal size = sizeInBytes;
        List<String> units = new List<String>{'B', 'KB', 'MB', 'GB'};
        Integer unitIndex = 0;
        
        while (size >= 1024 && unitIndex < units.size() - 1) {
            size = size / 1024;
            unitIndex++;
        }
        
        return String.valueOf(Math.round(size * 100) / 100) + ' ' + units[unitIndex];
    }
    
    /**
     * Helper method to get icon name for file type
     */
    private static String getFileIcon(String fileType) {
        if (String.isBlank(fileType)) return 'doctype:attachment';
        
        switch on fileType.toUpperCase() {
            when 'PDF' {
                return 'doctype:pdf';
            }
            when 'DOC', 'DOCX' {
                return 'doctype:word';
            }
            when 'XLS', 'XLSX' {
                return 'doctype:excel';
            }
            when 'PPT', 'PPTX' {
                return 'doctype:ppt';
            }
            when 'JPG', 'JPEG', 'PNG', 'GIF' {
                return 'doctype:image';
            }
            when 'ZIP', 'RAR' {
                return 'doctype:zip';
            }
            when else {
                return 'doctype:attachment';
            }
        }
    }
    
    /**
     * Associate uploaded files with a dealer package (prevents duplicates)
     * @param packageId The dealer package ID
     * @param contentDocumentIds List of ContentDocument IDs to associate
     * @return FileResponse with operation result
     */
    @AuraEnabled
    public static FileResponse saveFilesToPackage(String packageId, List<String> contentDocumentIds) {
        FileResponse response = new FileResponse();
        
        try {
            System.debug('🔗 Starting saveFilesToPackage with packageId: ' + packageId);
            System.debug('📁 ContentDocument IDs: ' + contentDocumentIds);
            
            if (String.isBlank(packageId)) {
                response.success = false;
                response.message = 'Package ID is required';
                return response;
            }
            
            if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
                response.success = false;
                response.message = 'No files to associate';
                return response;
            }
            
            // Validate package exists
            List<Dealer_Package__c> packages = [
                SELECT Id, Name FROM Dealer_Package__c 
                WHERE Id = :packageId LIMIT 1
            ];
            if (packages.isEmpty()) {
                response.success = false;
                response.message = 'Dealer package not found';
                return response;
            }
            
            System.debug('✅ Package found: ' + packages[0].Name);
            
            // Check for existing links to prevent duplicates
            Map<String, ContentDocumentLink> existingLinks = new Map<String, ContentDocumentLink>();
            List<ContentDocumentLink> existingLinksList = [
                SELECT Id, ContentDocumentId, LinkedEntityId
                FROM ContentDocumentLink 
                WHERE LinkedEntityId = :packageId 
                AND ContentDocumentId IN :contentDocumentIds
            ];
            
            for (ContentDocumentLink existingLink : existingLinksList) {
                existingLinks.put(existingLink.ContentDocumentId, existingLink);
            }
            
            System.debug('🔍 Found ' + existingLinks.size() + ' existing links');
            
            // Create ContentDocumentLinks only for new associations
            List<ContentDocumentLink> linksToCreate = new List<ContentDocumentLink>();
            List<String> skippedDocuments = new List<String>();
            List<String> newDocuments = new List<String>();
            
            for (String contentDocId : contentDocumentIds) {
                if (existingLinks.containsKey(contentDocId)) {
                    // Document is already linked, skip it
                    skippedDocuments.add(contentDocId);
                    System.debug('⏭️ Skipping already linked document: ' + contentDocId);
                } else {
                    // Document is not linked, create new link
                    ContentDocumentLink link = new ContentDocumentLink();
                    link.LinkedEntityId = packageId;
                    link.ContentDocumentId = contentDocId;
                    link.ShareType = 'V'; // Viewer permission
                    link.Visibility = 'AllUsers';
                    linksToCreate.add(link);
                    newDocuments.add(contentDocId);
                    System.debug('➕ Will create new link for document: ' + contentDocId);
                }
            }
            
            // Insert only the new links
            Integer newLinksCount = 0;
            if (!linksToCreate.isEmpty()) {
                insert linksToCreate;
                newLinksCount = linksToCreate.size();
                System.debug('✅ Successfully created ' + newLinksCount + ' new ContentDocumentLinks');
            }
            
            // Build response message
            String message = '';
            if (newLinksCount > 0 && skippedDocuments.size() > 0) {
                message = newLinksCount + ' new file(s) linked successfully. ' + 
                         skippedDocuments.size() + ' file(s) were already associated with this package.';
            } else if (newLinksCount > 0) {
                message = newLinksCount + ' file(s) linked successfully.';
            } else if (skippedDocuments.size() > 0) {
                message = 'All ' + skippedDocuments.size() + ' file(s) were already associated with this package.';
            } else {
                message = 'No files were processed.';
            }
            
            response.success = true;
            response.message = message;
            response.fileCount = newLinksCount;
            
            System.debug('🎉 Operation completed: ' + message);
            
        } catch (DmlException e) {
            System.debug('❌ DML Error in saveFilesToPackage: ' + e.getMessage());
            System.debug('❌ DML Stack Trace: ' + e.getStackTraceString());
            
            response.success = false;
            response.message = 'Database error: ' + e.getDmlMessage(0);
            
            // Additional debugging for DML errors
            for (Integer i = 0; i < e.getNumDml(); i++) {
                System.debug('DML Error ' + i + ': ' + e.getDmlMessage(i));
                System.debug('Failed Record ID: ' + e.getDmlId(i));
            }
            
        } catch (Exception e) {
            System.debug('❌ General Error in saveFilesToPackage: ' + e.getMessage());
            System.debug('❌ General Stack Trace: ' + e.getStackTraceString());
            
            response.success = false;
            response.message = 'Error associating files with package: ' + e.getMessage();
        }
        
        return response;
    }
    
    /**
     * Get files for Application Package (if needed for other components)
     * @param applicationPackageId The application package ID
     * @return FileResponse with existing files
     */
    @AuraEnabled(cacheable=false)
    public static FileResponse getApplicationPackageFiles(String applicationPackageId) {
        FileResponse response = new FileResponse();
        
        try {
            if (String.isBlank(applicationPackageId)) {
                response.success = false;
                response.message = 'Application Package ID is required';
                response.data = new List<FileDTO>();
                response.fileCount = 0;
                return response;
            }
            
            // Query for ContentDocumentLinks associated with the application package
            List<ContentDocumentLink> documentLinks = [
                SELECT Id, ContentDocumentId, ContentDocument.Title, ContentDocument.LatestPublishedVersionId,
                       ContentDocument.FileType, ContentDocument.ContentSize,
                       ContentDocument.CreatedDate, ContentDocument.CreatedBy.Name
                FROM ContentDocumentLink 
                WHERE LinkedEntityId = :applicationPackageId 
                ORDER BY ContentDocument.CreatedDate DESC
            ];
            
            List<FileDTO> fileDTOs = new List<FileDTO>();
            
            for (ContentDocumentLink link : documentLinks) {
                FileDTO fileDto = new FileDTO();
                fileDto.Id = link.Id;
                fileDto.ContentDocumentId = link.ContentDocumentId;
                fileDto.Name = link.ContentDocument.Title;
                fileDto.Title = link.ContentDocument.Title;
                fileDto.Size = link.ContentDocument.ContentSize;
                fileDto.FileType = link.ContentDocument.FileType;
                fileDto.CreatedDate = link.ContentDocument.CreatedDate;
                fileDto.CreatedByName = link.ContentDocument.CreatedBy.Name;
                fileDto.formattedSize = formatFileSize(link.ContentDocument.ContentSize);
                fileDto.iconName = getFileIcon(link.ContentDocument.FileType);
                
                Organization a_ORG = [Select Id, Name, IsSandbox from Organization limit 1];

                if(a_ORG.IsSandbox){   
                    fileDto.DownloadUrl = 'https://business-platform-7607--dtcsandbox.sandbox.lightning.force.com//sfc/servlet.shepherd/document/download/' + link.ContentDocumentId+'?operationContext=S1';
                }
                else{
                   fileDto.DownloadUrl = 'https://business-platform-7607.lightning.force.com//sfc/servlet.shepherd/document/download/' + link.ContentDocumentId+'?operationContext=S1'; 
                }
                
                fileDto.ViewUrl = 'view_pdf:' + link.ContentDocumentId;
                
                fileDTOs.add(fileDto);
            }
            
            response.success = true;
            response.data = fileDTOs;
            response.fileCount = fileDTOs.size();
            response.message = fileDTOs.size() + ' file(s) found';
            
        } catch (Exception e) {
            response.success = false;
            response.message = 'Error retrieving application package files: ' + e.getMessage();
            response.data = new List<FileDTO>();
            response.fileCount = 0;
            System.debug('Error in getApplicationPackageFiles: ' + e.getMessage());
        }
        
        return response;
    }
    
    /**
     * Upload files to Application Package using base64 data
     * @param applicationPackageId The application package ID
     * @param fileDataList List of file data objects with name, base64Content, and contentType
     * @return FileResponse with operation result
     */
    @AuraEnabled
    public static FileResponse uploadFilesToApplicationPackage(String applicationPackageId, List<Map<String, String>> fileDataList) {
        FileResponse response = new FileResponse();
        
        try {
            System.debug('📤 Starting uploadFilesToApplicationPackage with packageId: ' + applicationPackageId);
            System.debug('📁 Files to upload: ' + fileDataList.size());
            
            if (String.isBlank(applicationPackageId)) {
                response.success = false;
                response.message = 'Application Package ID is required';
                return response;
            }
            
            if (fileDataList == null || fileDataList.isEmpty()) {
                response.success = false;
                response.message = 'No files to upload';
                return response;
            }
            
            // Validate application package exists
            List<Application_Package__c> packages = [
                SELECT Id, Name FROM Application_Package__c 
                WHERE Id = :applicationPackageId LIMIT 1
            ];
            if (packages.isEmpty()) {
                response.success = false;
                response.message = 'Application package not found';
                return response;
            }
            
            System.debug('✅ Application Package found: ' + packages[0].Name);
            
            // Create ContentVersions for each file
            List<ContentVersion> contentVersions = new List<ContentVersion>();
            List<ContentDocumentLink> documentLinks = new List<ContentDocumentLink>();
            
            for (Map<String, String> fileData : fileDataList) {
                String fileName = fileData.get('name');
                String base64Content = fileData.get('base64Content');
                String contentType = fileData.get('contentType');
                
                if (String.isBlank(fileName) || String.isBlank(base64Content)) {
                    System.debug('⚠️ Skipping file with missing data: ' + fileName);
                    continue;
                }
                
                // Clean base64 if it contains data URL prefix
                String cleanBase64 = base64Content.contains(',') ? base64Content.substringAfter(',') : base64Content;
                
                // Create ContentVersion
                ContentVersion cv = new ContentVersion();
                cv.Title = fileName;
                cv.PathOnClient = fileName;
                cv.VersionData = EncodingUtil.base64Decode(cleanBase64);
                cv.FirstPublishLocationId = applicationPackageId; // This will create the link automatically
                cv.IsMajorVersion = true;
                
                contentVersions.add(cv);
            }
            
            if (contentVersions.isEmpty()) {
                response.success = false;
                response.message = 'No valid files to upload';
                return response;
            }
            
            // Insert ContentVersions
            insert contentVersions;
            
            System.debug('✅ Successfully uploaded ' + contentVersions.size() + ' file(s)');
            
            response.success = true;
            response.message = contentVersions.size() + ' file(s) uploaded successfully';
            response.fileCount = contentVersions.size();
            
        } catch (DmlException e) {
            System.debug('❌ DML Error in uploadFilesToApplicationPackage: ' + e.getMessage());
            response.success = false;
            response.message = 'Database error: ' + e.getDmlMessage(0);
        } catch (Exception e) {
            System.debug('❌ Error in uploadFilesToApplicationPackage: ' + e.getMessage());
            response.success = false;
            response.message = 'Error uploading files: ' + e.getMessage();
        }
        
        return response;
    }
}