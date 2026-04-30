@isTest
private class DealerPortalFileHandlerTest {

    @TestSetup
    static void setupData() {
        Account dealer = TestDataFactory.createDealer(true);
        Package__c pkg = TestDataFactory.createPackage('Tire_Rim_Protection_Plan', true);
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(dealer.Id, pkg.Id, 'Tire_Rim_Protection_Plan', true);

        Application__c app = TestDataFactory.createApplication(dealer.Id, true);
        TestDataFactory.createApplicationPackage(app.Id, dp.Id, null, dealer.Id, true);

        // Cover multiple branches of getFileIcon() switch
        List<ContentVersion> cvs = new List<ContentVersion>();
        cvs.add(new ContentVersion(Title='Test PDF',   PathOnClient='test.pdf',  VersionData=Blob.valueOf('Unit Test'), FirstPublishLocationId=dp.Id));
        cvs.add(new ContentVersion(Title='Test Word',  PathOnClient='test.docx', VersionData=Blob.valueOf('Unit Test'), FirstPublishLocationId=dp.Id));
        cvs.add(new ContentVersion(Title='Test Excel', PathOnClient='test.xlsx', VersionData=Blob.valueOf('Unit Test'), FirstPublishLocationId=dp.Id));
        cvs.add(new ContentVersion(Title='Test Img',   PathOnClient='test.png',  VersionData=Blob.valueOf('Unit Test'), FirstPublishLocationId=dp.Id));
        insert cvs;
    }

    // ─── getPDFContent ────────────────────────────────────────────────────────

    @isTest
    static void testGetPDFContentFull() {
        ContentVersion cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Title = 'Test PDF' LIMIT 1];

        Test.startTest();
        DealerPortalFileHandler.getPDFContent(cv.ContentDocumentId); // success
        DealerPortalFileHandler.getPDFContent('');                    // blank guard
        DealerPortalFileHandler.getPDFContent('069000000000000AAA'); // not found
        DealerPortalFileHandler.getPDFContent('InvalidID');           // exception path
        Test.stopTest();
    }

    // ─── removeFileFromPackage ────────────────────────────────────────────────

    @isTest
    static void testRemoveFilePaths() {
        Dealer_Package__c dp = [SELECT Id FROM Dealer_Package__c LIMIT 1];
        ContentDocumentLink cdl = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :dp.Id LIMIT 1];

        Test.startTest();
        DealerPortalFileHandler.removeFileFromPackage(dp.Id, cdl.ContentDocumentId); // success
        DealerPortalFileHandler.removeFileFromPackage('', cdl.ContentDocumentId);    // missing pkg
        DealerPortalFileHandler.removeFileFromPackage(dp.Id, '');                    // missing doc
        DealerPortalFileHandler.removeFileFromPackage(dp.Id, '069000000000000AAA'); // link not found
        Test.stopTest();
    }

    // ─── getPackageFiles ─────────────────────────────────────────────────────

    @isTest
    static void testGetPackageFilesAllBranches() {
        Dealer_Package__c dp = [SELECT Id FROM Dealer_Package__c LIMIT 1];

        Test.startTest();
        DealerPortalFileHandler.FileResponse res = DealerPortalFileHandler.getPackageFiles(dp.Id);
        DealerPortalFileHandler.getPackageFiles(null); // null guard
        Test.stopTest();

        Assert.isTrue(res.success);
    }

    @isTest
    static void testGetPackageFilesWithData() {
        Dealer_Package__c dp = [SELECT Id FROM Dealer_Package__c LIMIT 1];

        // Insert files that exercise every getFileIcon() branch + formatFileSize
        // Use different sizes: small (B), medium (KB), large (MB)
        List<ContentVersion> cvs = new List<ContentVersion>();

        // PDF — small file, stays in bytes
        cvs.add(new ContentVersion(Title='Loop PDF',  PathOnClient='loop.pdf',  VersionData=Blob.valueOf('x'), IsMajorVersion=true));
        // Word — ~1.1 KB
        cvs.add(new ContentVersion(Title='Loop Word', PathOnClient='loop.docx', VersionData=Blob.valueOf('A'.repeat(1200)), IsMajorVersion=true));
        // Excel — ~1.1 MB (use repeat to cross the MB threshold)
        // Salesforce test limits prevent very large blobs; use 1 KB+ to hit the while loop twice
        cvs.add(new ContentVersion(Title='Loop XLS',  PathOnClient='loop.xlsx', VersionData=Blob.valueOf('B'.repeat(1100)), IsMajorVersion=true));
        // Image
        cvs.add(new ContentVersion(Title='Loop PNG',  PathOnClient='loop.png',  VersionData=Blob.valueOf('C'.repeat(500)),  IsMajorVersion=true));
        // PPT — covers the PPT/PPTX switch branch
        cvs.add(new ContentVersion(Title='Loop PPT',  PathOnClient='loop.pptx', VersionData=Blob.valueOf('D'.repeat(200)),  IsMajorVersion=true));
        // ZIP — covers ZIP/RAR switch branch
        cvs.add(new ContentVersion(Title='Loop ZIP',  PathOnClient='loop.zip',  VersionData=Blob.valueOf('E'.repeat(300)),  IsMajorVersion=true));
        // Unknown type — covers the 'when else' switch branch
        cvs.add(new ContentVersion(Title='Loop TXT',  PathOnClient='loop.txt',  VersionData=Blob.valueOf('F'.repeat(100)),  IsMajorVersion=true));
        insert cvs;

        // Link all of them to the dealer package
        List<Id> docIds = new List<Id>();
        for (ContentVersion cv : [SELECT ContentDocumentId FROM ContentVersion WHERE Title LIKE 'Loop%']) {
            docIds.add(cv.ContentDocumentId);
        }
        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        for (Id docId : docIds) {
            links.add(new ContentDocumentLink(LinkedEntityId=dp.Id, ContentDocumentId=docId, ShareType='V'));
        }
        insert links;

        Test.startTest();
        DealerPortalFileHandler.FileResponse response = DealerPortalFileHandler.getPackageFiles(dp.Id);
        Test.stopTest();

        Assert.isTrue(response.success);
        Assert.isTrue(response.data.size() > 0, 'Loop should have executed and returned files');
        Assert.isNotNull(response.data[0].DownloadUrl, 'DownloadUrl should be populated');
        Assert.isNotNull(response.data[0].formattedSize, 'formattedSize should be populated');
        Assert.isNotNull(response.data[0].iconName, 'iconName should be populated');
    }

    // ─── saveFilesToPackage ───────────────────────────────────────────────────

    @isTest
    static void testSaveFilesToPackageFull() {
        Dealer_Package__c dp = [SELECT Id FROM Dealer_Package__c LIMIT 1];
        ContentVersion cv = [SELECT ContentDocumentId FROM ContentVersion LIMIT 1];

        Test.startTest();
        // Package not found
        DealerPortalFileHandler.saveFilesToPackage('a00000000000000AAA', new List<String>{cv.ContentDocumentId});
        // No IDs supplied
        DealerPortalFileHandler.saveFilesToPackage(dp.Id, new List<String>());
        // Success — also exercises deduplication on second call
        DealerPortalFileHandler.saveFilesToPackage(dp.Id, new List<String>{cv.ContentDocumentId});
        // Duplicate call — hits the "all files already linked" branch
        DealerPortalFileHandler.saveFilesToPackage(dp.Id, new List<String>{cv.ContentDocumentId});
        Test.stopTest();
    }

    // ─── uploadFilesToApplicationPackage ─────────────────────────────────────

    @isTest
    static void testUploadFilesToApplicationPackageFull() {
        Application_Package__c ap = [SELECT Id FROM Application_Package__c LIMIT 1];

        List<Map<String, String>> files = new List<Map<String, String>>();

        // Covers data-URL prefix stripping (substringAfter ',')
        files.add(new Map<String, String>{
            'name'          => 'test.pdf',
            'base64Content' => 'data:image/png;base64,VEVTVA==',
            'contentType'   => 'pdf'
        });

        // Covers the 'continue' path (missing name + content)
        files.add(new Map<String, String>{'name' => '', 'base64Content' => ''});

        Test.startTest();
        DealerPortalFileHandler.uploadFilesToApplicationPackage(ap.Id, files);    // success
        DealerPortalFileHandler.uploadFilesToApplicationPackage('', files);        // blank ID guard
        DealerPortalFileHandler.uploadFilesToApplicationPackage(ap.Id, null);     // null list guard
        DealerPortalFileHandler.uploadFilesToApplicationPackage('a00000000000000AAA', files); // pkg not found

        // Covers the "no valid files" branch — every entry has blank data
        List<Map<String, String>> allBlank = new List<Map<String, String>>{
            new Map<String, String>{'name' => '', 'base64Content' => ''}
        };
        DealerPortalFileHandler.uploadFilesToApplicationPackage(ap.Id, allBlank);
        Test.stopTest();
    }

    // ─── getApplicationPackageFiles ──────────────────────────────────────────

    @isTest
    static void testGetApplicationPackageFiles() {
        Application_Package__c ap = [SELECT Id FROM Application_Package__c LIMIT 1];

        Test.startTest();
        DealerPortalFileHandler.getApplicationPackageFiles(ap.Id);
        DealerPortalFileHandler.getApplicationPackageFiles('');   // blank guard
        Test.stopTest();
    }

    @isTest
    static void testGetApplicationPackageFilesWithLinkedFiles() {
        Application_Package__c ap = [SELECT Id FROM Application_Package__c LIMIT 1];

        // Attach a file directly to the Application_Package__c so the for-loop
        // inside getApplicationPackageFiles() executes and builds FileDTOs
        ContentVersion cv = new ContentVersion(
            Title                  = 'AppPkg Loop PDF',
            PathOnClient           = 'apppkg.pdf',
            VersionData            = Blob.valueOf('content'),
            FirstPublishLocationId = ap.Id,
            IsMajorVersion         = true
        );
        insert cv;

        Test.startTest();
        DealerPortalFileHandler.FileResponse response = DealerPortalFileHandler.getApplicationPackageFiles(ap.Id);
        Test.stopTest();

        Assert.isTrue(response.success);
        Assert.isTrue(response.data.size() > 0, 'Loop should have executed');
        Assert.isNotNull(response.data[0].DownloadUrl, 'DownloadUrl should be set');
        Assert.isNotNull(response.data[0].formattedSize, 'formattedSize should be set');
        Assert.isNotNull(response.data[0].iconName, 'iconName should be set');
    }

    // ─── formatFileSize edge cases ────────────────────────────────────────────
/*
    @isTest
    static void testFormatFileSizeEdgeCases() {
        // formatFileSize is private, but we can drive it indirectly through
        // getPackageFiles by attaching files whose sizes cross the unit boundaries.
        Dealer_Package__c dp = [SELECT Id FROM Dealer_Package__c LIMIT 1];

        // 0 bytes → "0 KB" guard inside formatFileSize
        ContentVersion cvNull = new ContentVersion(
            Title='Zero Byte File', PathOnClient='zero.txt',
            VersionData=Blob.valueOf(''), IsMajorVersion=true
        );
        insert cvNull;
        Id zeroDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cvNull.Id].ContentDocumentId;
        insert new ContentDocumentLink(LinkedEntityId=dp.Id, ContentDocumentId=zeroDocId, ShareType='V');

        Test.startTest();
        DealerPortalFileHandler.FileResponse r = DealerPortalFileHandler.getPackageFiles(dp.Id);
        Test.stopTest();

        Assert.isTrue(r.success);
    }
*/
    // ─── getFileIcon — JPG, JPEG, GIF, RAR branches ───────────────────────────

    @isTest
    static void testGetFileIconAdditionalBranches() {
        Dealer_Package__c dp = [SELECT Id FROM Dealer_Package__c LIMIT 1];

        List<ContentVersion> cvs = new List<ContentVersion>();
        cvs.add(new ContentVersion(Title='Test JPG',  PathOnClient='img.jpg',  VersionData=Blob.valueOf('x'), IsMajorVersion=true));
        cvs.add(new ContentVersion(Title='Test JPEG', PathOnClient='img.jpeg', VersionData=Blob.valueOf('x'), IsMajorVersion=true));
        cvs.add(new ContentVersion(Title='Test GIF',  PathOnClient='img.gif',  VersionData=Blob.valueOf('x'), IsMajorVersion=true));
        cvs.add(new ContentVersion(Title='Test RAR',  PathOnClient='arch.rar', VersionData=Blob.valueOf('x'), IsMajorVersion=true));
        cvs.add(new ContentVersion(Title='Test DOC',  PathOnClient='doc.doc',  VersionData=Blob.valueOf('x'), IsMajorVersion=true));
        cvs.add(new ContentVersion(Title='Test XLS',  PathOnClient='ss.xls',   VersionData=Blob.valueOf('x'), IsMajorVersion=true));
        insert cvs;

        List<Id> docIds = new List<Id>();
        for (ContentVersion cv : [SELECT ContentDocumentId FROM ContentVersion WHERE Title IN ('Test JPG','Test JPEG','Test GIF','Test RAR','Test DOC','Test XLS')]) {
            docIds.add(cv.ContentDocumentId);
        }
        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        for (Id docId : docIds) {
            links.add(new ContentDocumentLink(LinkedEntityId=dp.Id, ContentDocumentId=docId, ShareType='V'));
        }
        insert links;

        Test.startTest();
        DealerPortalFileHandler.FileResponse response = DealerPortalFileHandler.getPackageFiles(dp.Id);
        Test.stopTest();

        Assert.isTrue(response.success);
        Assert.isTrue(response.data.size() > 0);
    }
}