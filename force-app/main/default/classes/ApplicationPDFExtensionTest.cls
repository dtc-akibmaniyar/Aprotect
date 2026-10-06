/**
 * ApplicationPDFExtensionTest
 * ───────────────────────────────────────────────────────────────────────────
 * Covers the Lubrico-contract rewrite of DealerPortalVehicleApplicationPDFs:
 *   • the record-type grouping key resolves to the package's real RecordType
 *     name (so the key equals what the Summary PDF button sends — no blank PDF)
 *   • an engine-priced package with NULL master links still resolves
 *   • isTireRim is true for a Tire & Rim package
 *   • an unresolved rt param renders ALL packages (never blank)
 *   • the page renders non-blank
 *   • a versioned filename is produced for a single package record type
 */
@isTest
private class ApplicationPDFExtensionTest {

    /**
     * Builds an application with a single Active__c package of the given
     * Application_Package__c record type. Master Package__c / Package_Term__c
     * links are intentionally left NULL (engine-priced shape); the plan/term
     * resolve through the dealer-copy links instead.
     */
    private static Id buildApp(String pkgRecordTypeDeveloperName, Boolean unlimitedTerm) {
        Account dealer = TestDataFactory.createDealer(true);

        Vehicle__c veh = TestDataFactory.createVehicle(true);
        veh.Vehicle_Purchase_Price__c = 32000;
        update veh;

        Application__c app = TestDataFactory.createApplication(dealer.Id, true);
        // Vehicle_* / Customer_* fields on Application__c are FORMULAS derived
        // from these lookups — they are read-only, so link the source records.
        app.Vehicle__c       = veh.Id;
        app.Customer_Name__c = TestDataFactory.createCustomerAccount(true).Id;
        update app;

        Package__c pkg = TestDataFactory.createPackage(pkgRecordTypeDeveloperName, true);
        Package_Term__c term = TestDataFactory.createPackageTerm(pkg.Id, null, true);
        Dealer_Package__c dp = TestDataFactory.createDealerPackage(dealer.Id, pkg.Id, pkgRecordTypeDeveloperName, true);
        Dealer_Package_Term__c dterm = TestDataFactory.createDealerPackageTerm(dp.Id, term.Id, null, true);

        if (unlimitedTerm) {
            dterm.Restriction_Type__c = 'Unlimited';
            update dterm;
        }
        dp.Per_Claim_Limit__c = 5000;
        dp.Deductable__c      = 150;
        update dp;

        TestDataFactory.createApplicationPackage(
            app.Id, dp.Id, dterm.Id, dealer.Id, pkgRecordTypeDeveloperName, 1499, 5, true
        );
        return app.Id;
    }

    private static ApplicationPDFExtension buildExtension(Id appId, String rtParam) {
        Application__c app = [SELECT Id FROM Application__c WHERE Id = :appId LIMIT 1];
        PageReference pg = Page.DealerPortalVehicleApplicationPDFs;
        Test.setCurrentPage(pg);
        pg.getParameters().put('id', appId);
        if (rtParam != null) {
            pg.getParameters().put('rt', rtParam);
        }
        return new ApplicationPDFExtension(new ApexPages.StandardController(app));
    }

    @isTest
    static void groupingKey_resolvesToRecordTypeName_enginePriced() {
        Id appId = buildApp('Extended_Limited_Warranty', true);

        Test.startTest();
        ApplicationPDFExtension ext = buildExtension(appId, 'Extended Limited Warranty');
        Test.stopTest();

        System.assertEquals(1, ext.recordTypeWrappersList.size(), 'One wrapper for the requested record type');
        ApplicationPDFExtension.RecordTypeWrapper rtw = ext.recordTypeWrappersList[0];
        System.assertEquals('Extended Limited Warranty', rtw.recordTypeName,
            'Grouping key must equal RecordType.Name (what the PDF button sends)');
        System.assertEquals(1, rtw.packages.size(), 'One package in the wrapper');

        ApplicationPDFExtension.PackageWrapper w = rtw.packages[0];
        System.assert(!w.isTireRim, 'Warranty package must not be flagged tire/rim');
        System.assertEquals('Unlimited KM', w.odometerEndDisplay,
            'Unlimited restriction must render "Unlimited <KM>" (Summary parity)');
        System.assert(w.perClaimLimitDisplay.contains('5,000'), 'Per-claim resolved: ' + w.perClaimLimitDisplay);
        System.assert(w.deductibleDisplay.contains('150'), 'Deductible resolved: ' + w.deductibleDisplay);
        System.assertEquals('$32,000.00', w.liabilityDisplay, 'Liability = vehicle purchase price');
    }

    @isTest
    static void tireRimPackage_isTireRim() {
        Id appId = buildApp('Tire_Rim_Protection_Plan', false);

        Test.startTest();
        ApplicationPDFExtension ext = buildExtension(appId, 'Tire & Rim Protection Plan');
        Test.stopTest();

        System.assertEquals(1, ext.recordTypeWrappersList.size());
        ApplicationPDFExtension.RecordTypeWrapper rtw = ext.recordTypeWrappersList[0];
        System.assertEquals('Tire & Rim Protection Plan', rtw.recordTypeName);
        System.assert(rtw.packages[0].isTireRim, 'Tire & Rim package must be flagged isTireRim');
    }

    @isTest
    static void unresolvedRt_rendersAllNeverBlank() {
        Id appId = buildApp('Extended_Limited_Warranty', false);

        Test.startTest();
        ApplicationPDFExtension ext = buildExtension(appId, 'Other');
        Test.stopTest();

        System.assert(!ext.recordTypeWrappersList.isEmpty(),
            'An unresolved rt must render ALL packages, never a blank PDF');
    }

    @isTest
    static void pageContextPopulatesKeySections() {
        // Test methods cannot call PageReference.getContent(); the real
        // non-blank render is verified functionally via anonymous Apex. Here we
        // assert the page's data source (the extension the page is bound to)
        // is populated for every section the template reads.
        Id appId = buildApp('Extended_Limited_Warranty', true);

        ApplicationPDFExtension ext = buildExtension(appId, 'Extended Limited Warranty');

        System.assert(!ext.recordTypeWrappersList.isEmpty(), 'Page has a record-type block to render');
        ApplicationPDFExtension.RecordTypeWrapper rtw = ext.recordTypeWrappersList[0];
        System.assert(!rtw.packages.isEmpty(), 'Page has a package block to render');
        ApplicationPDFExtension.PackageWrapper w = rtw.packages[0];
        System.assert(String.isNotBlank(w.renderedPlanName), 'Program renders: ' + w.renderedPlanName);
        System.assert(String.isNotBlank(w.renderedTermName), 'Term renders: ' + w.renderedTermName);
        System.assert(String.isNotBlank(w.totalPremiumDisplay), 'Total premium renders: ' + w.totalPremiumDisplay);
        System.assert(String.isNotBlank(w.liabilityDisplay), 'Liability renders: ' + w.liabilityDisplay);
    }

    @isTest
    static void versionedFilename_perPackageRecordType() {
        Id appId = buildApp('Extended_Limited_Warranty', false);

        Test.startTest();
        ApplicationSummaryController.PDFResponse res =
            ApplicationSummaryController.generatePDFForPackageRecordType(appId, 'Extended Limited Warranty');
        Test.stopTest();

        System.assert(res.success, res.message);
        System.assert(res.fileName != null && res.fileName.startsWith('Extended_Limited_Warranty_'),
            'Versioned filename suffix from record-type label: ' + res.fileName);
        System.assert(res.fileName.endsWith('.pdf'), 'Filename is a .pdf: ' + res.fileName);
    }
}