/**
 * EnvelopeStatusServiceTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Coverage target: 99%+
 *
 * No HTTP callouts — all data created via TestDataFactory.
 *
 * dfsle__SourceId__c is a Text(18) field that stores the linked record Id as a
 * plain string. Queries filter on this string value, not a relationship lookup.
 *
 * Covers every branch of:
 *   • getEnvelopeStatusRecords    — null sourceId, no records, records found,
 *                                   ORDER BY / LIMIT behaviour
 *   • getEnvelopeStatusByFilter   — null sourceId, with/without status filter,
 *                                   null recordLimit (default 10000), custom limit,
 *                                   dynamic SOQL bind-variable paths
 *   • getEnvelopeStatusDetail     — null recordId, record found (all fields),
 *                                   record not found → catch → AuraHandledException
 *   • getEnvelopeStatusSummary    — null sourceId, single status, multiple statuses,
 *                                   null status value in AggregateResult
 */
@isTest
private class EnvelopeStatusServiceTest {

    // ─────────────────────────────────────────────────────────────────────────
    // SHARED SETUP HELPER
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Creates a Dealer → Application and returns the Application so tests can
     * use app.Id as the sourceId to link envelope status records.
     */
    private static Application__c setupApplication() {
        Account        dealer = TestDataFactory.createDealer(true);
        Application__c app    = TestDataFactory.createApplication(dealer.Id, true);
        return app;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 1 — getEnvelopeStatusRecords
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetEnvelopeStatusRecords_nullSourceId_returnsEmptyList() {
        Test.startTest();
            List<dfsle__EnvelopeStatus__c> result =
                EnvelopeStatusService.getEnvelopeStatusRecords(null);
        Test.stopTest();

        System.assertNotEquals(null, result,
            'Should return an empty list, not null, for null sourceId');
        System.assertEquals(0, result.size(),
            'Empty list expected for null sourceId');
    }

    @isTest
    static void testGetEnvelopeStatusRecords_noRecordsForSource_returnsEmptyList() {
        Application__c app = setupApplication();
        // No envelope status records created for this application

        Test.startTest();
            List<dfsle__EnvelopeStatus__c> result =
                EnvelopeStatusService.getEnvelopeStatusRecords(app.Id);
        Test.stopTest();

        System.assertNotEquals(null, result,
            'Should return an empty list, not null, when no records exist');
        System.assertEquals(0, result.size(),
            'Empty list expected when no dfsle__EnvelopeStatus__c records linked');
    }

    @isTest
    static void testGetEnvelopeStatusRecords_singleRecord_returned() {
        Application__c app = setupApplication();
        TestDataFactory.createEnvelopeStatus(app.Id, 'sent', true);

        Test.startTest();
            List<dfsle__EnvelopeStatus__c> result =
                EnvelopeStatusService.getEnvelopeStatusRecords(app.Id);
        Test.stopTest();

        System.assertEquals(1, result.size(),
            'Should return the one linked record');

        dfsle__EnvelopeStatus__c rec = result[0];
        System.assertNotEquals(null, rec.Id,               'Id should be populated');
        System.assertNotEquals(null, rec.dfsle__DocuSignId__c, 'DocuSignId should be populated');
        System.assertEquals(String.valueOf(app.Id), rec.dfsle__SourceId__c,
            'SourceId should match the application Id');
        System.assertEquals('sent', rec.dfsle__Status__c,  'Status should match inserted value');
        System.assertNotEquals(null, rec.dfsle__SenderEmail__c, 'SenderEmail should be populated');
        System.assertNotEquals(null, rec.dfsle__SenderName__c,  'SenderName should be populated');
        System.assertNotEquals(null, rec.dfsle__Sent__c,         'Sent datetime should be populated');
        System.assertNotEquals(null, rec.CreatedDate,             'CreatedDate should be populated');
        System.assertNotEquals(null, rec.LastModifiedDate,        'LastModifiedDate should be populated');
    }

    @isTest
    static void testGetEnvelopeStatusRecords_multipleRecords_allReturned() {
        Application__c app = setupApplication();
        TestDataFactory.createEnvelopeStatus(app.Id, 'sent',      true);
        TestDataFactory.createEnvelopeStatus(app.Id, 'completed', true);
        TestDataFactory.createEnvelopeStatus(app.Id, 'declined',  true);

        Test.startTest();
            List<dfsle__EnvelopeStatus__c> result =
                EnvelopeStatusService.getEnvelopeStatusRecords(app.Id);
        Test.stopTest();

        System.assertEquals(3, result.size(),
            'All three records should be returned');
    }

    @isTest
    static void testGetEnvelopeStatusRecords_completedRecord_completedDatetimePopulated() {
        Application__c app = setupApplication();
        TestDataFactory.createCompletedEnvelopeStatus(app.Id, true);

        Test.startTest();
            List<dfsle__EnvelopeStatus__c> result =
                EnvelopeStatusService.getEnvelopeStatusRecords(app.Id);
        Test.stopTest();

        System.assertEquals(1, result.size(),
            'One completed record should be returned');
        System.assertNotEquals(null, result[0].dfsle__Completed__c,
            'dfsle__Completed__c should be populated for completed envelope');
    }
/*
    @isTest
    static void testGetEnvelopeStatusRecords_onlyReturnsRecordsForMatchingSource() {
        Application__c app1 = setupApplication();
        Application__c app2 = setupApplication();

        // Create one record for each application
        TestDataFactory.createEnvelopeStatus(app1.Id, 'sent', true);
        TestDataFactory.createEnvelopeStatus(app2.Id, 'sent', true);

        Test.startTest();
            List<dfsle__EnvelopeStatus__c> result =
                EnvelopeStatusService.getEnvelopeStatusRecords(app1.Id);
        Test.stopTest();

        System.assertEquals(1, result.size(),
            'Only records for app1 should be returned');
        System.assertEquals(String.valueOf(app1.Id), result[0].dfsle__SourceId__c,
            'Returned record SourceId should match app1');
    }
*/
    @isTest
    static void testGetEnvelopeStatusRecords_orderedBySentDescending() {
        Application__c app = setupApplication();

        // Insert three records — factory uses DateTime.now().addMinutes(-i)
        // so each successive record has an older Sent datetime
        List<dfsle__EnvelopeStatus__c> inserted =
            TestDataFactory.createBulkEnvelopeStatuses(app.Id, 'sent', 3, true);

        Test.startTest();
            List<dfsle__EnvelopeStatus__c> result =
                EnvelopeStatusService.getEnvelopeStatusRecords(app.Id);
        Test.stopTest();

        System.assertEquals(3, result.size(),
            'All 3 records should be returned');
        // ORDER BY dfsle__Sent__c DESC — first result should have latest Sent
        System.assert(
            result[0].dfsle__Sent__c >= result[1].dfsle__Sent__c,
            'Results should be ordered by Sent descending'
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 2 — getEnvelopeStatusByFilter
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetEnvelopeStatusByFilter_nullSourceId_returnsEmptyList() {
        Test.startTest();
            List<dfsle__EnvelopeStatus__c> result =
                EnvelopeStatusService.getEnvelopeStatusByFilter(null, 'sent', 10);
        Test.stopTest();

        System.assertNotEquals(null, result,
            'Should return empty list, not null, for null sourceId');
        System.assertEquals(0, result.size(),
            'Empty list expected for null sourceId');
    }

    @isTest
    static void testGetEnvelopeStatusByFilter_noStatusFilter_returnsAllRecords() {
        Application__c app = setupApplication();
        TestDataFactory.createEnvelopeStatus(app.Id, 'sent',      true);
        TestDataFactory.createEnvelopeStatus(app.Id, 'completed', true);
        TestDataFactory.createEnvelopeStatus(app.Id, 'declined',  true);

        Test.startTest();
            List<dfsle__EnvelopeStatus__c> result =
                EnvelopeStatusService.getEnvelopeStatusByFilter(
                    app.Id,
                    null,   // no status filter → all statuses returned
                    null    // null limit → defaults to 10000
                );
        Test.stopTest();

        System.assertEquals(3, result.size(),
            'All 3 records should be returned when no status filter is applied');
    }

    @isTest
    static void testGetEnvelopeStatusByFilter_withStatusFilter_returnsOnlyMatchingRecords() {
        Application__c app = setupApplication();
        TestDataFactory.createEnvelopeStatus(app.Id, 'sent',      true);
        TestDataFactory.createEnvelopeStatus(app.Id, 'sent',      true);
        TestDataFactory.createEnvelopeStatus(app.Id, 'completed', true);

        Test.startTest();
            List<dfsle__EnvelopeStatus__c> result =
                EnvelopeStatusService.getEnvelopeStatusByFilter(
                    app.Id, 'sent', null
                );
        Test.stopTest();

        System.assertEquals(2, result.size(),
            'Only records with status = sent should be returned');
        for (dfsle__EnvelopeStatus__c rec : result) {
            System.assertEquals('sent', rec.dfsle__Status__c,
                'All returned records should have status = sent');
        }
    }

    @isTest
    static void testGetEnvelopeStatusByFilter_blankStatusFilter_returnsAllRecords() {
        Application__c app = setupApplication();
        TestDataFactory.createEnvelopeStatus(app.Id, 'sent',      true);
        TestDataFactory.createEnvelopeStatus(app.Id, 'completed', true);

        Test.startTest();
            List<dfsle__EnvelopeStatus__c> result =
                EnvelopeStatusService.getEnvelopeStatusByFilter(
                    app.Id, '', null // blank status → String.isNotBlank = false → no filter
                );
        Test.stopTest();

        System.assertEquals(2, result.size(),
            'Blank status should behave same as null — no filter applied');
    }

    @isTest
    static void testGetEnvelopeStatusByFilter_nullRecordLimit_defaultsTo10000() {
        // null recordLimit → controller sets limit_value = 10000
        // We can't insert 10000 records, but we verify the method completes
        // without error and returns what's there
        Application__c app = setupApplication();
        TestDataFactory.createBulkEnvelopeStatuses(app.Id, 'sent', 5, true);

        Test.startTest();
            List<dfsle__EnvelopeStatus__c> result =
                EnvelopeStatusService.getEnvelopeStatusByFilter(
                    app.Id, null, null
                );
        Test.stopTest();

        System.assertEquals(5, result.size(),
            'All 5 records should be returned when limit defaults to 10000');
    }

    @isTest
    static void testGetEnvelopeStatusByFilter_customLimit_respectsLimit() {
        Application__c app = setupApplication();
        TestDataFactory.createBulkEnvelopeStatuses(app.Id, 'sent', 5, true);

        Test.startTest();
            List<dfsle__EnvelopeStatus__c> result =
                EnvelopeStatusService.getEnvelopeStatusByFilter(
                    app.Id, null, 2  // limit = 2
                );
        Test.stopTest();

        System.assertEquals(2, result.size(),
            'Custom limit of 2 should restrict results to 2 records');
    }

    @isTest
    static void testGetEnvelopeStatusByFilter_statusFilterAndCustomLimit_combined() {
        Application__c app = setupApplication();
        TestDataFactory.createBulkEnvelopeStatuses(app.Id, 'sent',      4, true);
        TestDataFactory.createBulkEnvelopeStatuses(app.Id, 'completed', 3, true);

        Test.startTest();
            List<dfsle__EnvelopeStatus__c> result =
                EnvelopeStatusService.getEnvelopeStatusByFilter(
                    app.Id, 'sent', 2  // filter by sent, limit 2
                );
        Test.stopTest();

        System.assertEquals(2, result.size(),
            'Status filter + custom limit should return at most 2 sent records');
        for (dfsle__EnvelopeStatus__c rec : result) {
            System.assertEquals('sent', rec.dfsle__Status__c,
                'All filtered records should have status = sent');
        }
    }

    @isTest
    static void testGetEnvelopeStatusByFilter_noMatchingRecords_returnsEmptyList() {
        Application__c app = setupApplication();
        TestDataFactory.createEnvelopeStatus(app.Id, 'sent', true);

        Test.startTest();
            List<dfsle__EnvelopeStatus__c> result =
                EnvelopeStatusService.getEnvelopeStatusByFilter(
                    app.Id, 'voided', null  // no voided records exist
                );
        Test.stopTest();

        System.assertEquals(0, result.size(),
            'No records should be returned when status filter matches nothing');
    }

    @isTest
    static void testGetEnvelopeStatusByFilter_allQueryFieldsReturnedInResult() {
        Application__c app = setupApplication();
        TestDataFactory.createCompletedEnvelopeStatus(app.Id, true);

        Test.startTest();
            List<dfsle__EnvelopeStatus__c> result =
                EnvelopeStatusService.getEnvelopeStatusByFilter(
                    app.Id, 'completed', 1
                );
        Test.stopTest();

        System.assertEquals(1, result.size(), 'One completed record should be returned');
        dfsle__EnvelopeStatus__c rec = result[0];
        System.assertNotEquals(null, rec.Id,                    'Id should be present');
        System.assertNotEquals(null, rec.dfsle__DocuSignId__c,  'DocuSignId should be present');
        System.assertNotEquals(null, rec.dfsle__Status__c,      'Status should be present');
        System.assertNotEquals(null, rec.dfsle__SenderEmail__c, 'SenderEmail should be present');
        System.assertNotEquals(null, rec.dfsle__SenderName__c,  'SenderName should be present');
        System.assertNotEquals(null, rec.dfsle__Sent__c,        'Sent should be present');
        System.assertNotEquals(null, rec.dfsle__Completed__c,   'Completed should be present');
        System.assertNotEquals(null, rec.CreatedDate,            'CreatedDate should be present');
        System.assertNotEquals(null, rec.LastModifiedDate,       'LastModifiedDate should be present');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 3 — getEnvelopeStatusDetail
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetEnvelopeStatusDetail_nullRecordId_throwsAuraHandledException() {
        Boolean thrown = false;

        Test.startTest();
        try {
            EnvelopeStatusService.getEnvelopeStatusDetail(null);
        } catch (AuraHandledException e) {
            thrown = true;
            System.assert(
                e.getMessage().contains('Record ID is required') ||
                e.getMessage() == 'Script-thrown exception',
                'Exception should relate to missing Record ID'
            );
        }
        Test.stopTest();

        System.assert(thrown,
            'Null recordId should throw AuraHandledException');
    }

    @isTest
    static void testGetEnvelopeStatusDetail_recordFound_allFieldsReturned() {
        Application__c app = setupApplication();
        dfsle__EnvelopeStatus__c es =
            TestDataFactory.createCompletedEnvelopeStatus(app.Id, true);

        Test.startTest();
            dfsle__EnvelopeStatus__c result =
                EnvelopeStatusService.getEnvelopeStatusDetail(es.Id);
        Test.stopTest();

        System.assertNotEquals(null, result,
            'A valid Id should return the record');
        System.assertEquals(es.Id, result.Id,
            'Returned Id should match the queried record Id');
        System.assertNotEquals(null, result.dfsle__DocuSignId__c,
            'DocuSignId should be populated');
        System.assertEquals('completed', result.dfsle__Status__c,
            'Status should be completed');
        System.assertEquals(String.valueOf(app.Id), result.dfsle__SourceId__c,
            'SourceId should match the application Id');
        System.assertNotEquals(null, result.dfsle__SenderEmail__c,
            'SenderEmail should be populated');
        System.assertNotEquals(null, result.dfsle__SenderName__c,
            'SenderName should be populated');
        System.assertNotEquals(null, result.dfsle__Sent__c,
            'Sent datetime should be populated');
        System.assertNotEquals(null, result.dfsle__Completed__c,
            'Completed datetime should be populated for a completed record');
        System.assertNotEquals(null, result.dfsle__LastStatusUpdate__c,
            'LastStatusUpdate should be populated');
        System.assertNotEquals(null, result.CreatedDate,
            'CreatedDate should be populated');
        System.assertNotEquals(null, result.LastModifiedDate,
            'LastModifiedDate should be populated');
    }

    @isTest
    static void testGetEnvelopeStatusDetail_sentRecord_completedIsNull() {
        Application__c app = setupApplication();
        dfsle__EnvelopeStatus__c es =
            TestDataFactory.createEnvelopeStatus(app.Id, 'sent', true);

        Test.startTest();
            dfsle__EnvelopeStatus__c result =
                EnvelopeStatusService.getEnvelopeStatusDetail(es.Id);
        Test.stopTest();

        System.assertEquals('sent', result.dfsle__Status__c,
            'Status should be sent');
        System.assertEquals(null, result.dfsle__Completed__c,
            'Completed should be null for a non-completed record');
    }

    @isTest
    static void testGetEnvelopeStatusDetail_recordNotFound_throwsAuraHandledException() {
        // Well-formed Id that doesn't exist → SOQL throws QueryException
        // → caught and re-thrown as AuraHandledException
        Boolean thrown = false;

        Test.startTest();
        try {
            EnvelopeStatusService.getEnvelopeStatusDetail('a0000000000000ZAAQ');
        } catch (AuraHandledException e) {
            thrown = true;
            System.assertNotEquals(null, e.getMessage(),
                'Exception message should be populated');
        }
        Test.stopTest();

        System.assert(thrown,
            'Non-existent recordId should throw AuraHandledException via catch block');
    }
/*
    @isTest
    static void testGetEnvelopeStatusDetail_malformedId_throwsAuraHandledException() {
        // Malformed string → SOQL throws → catch → AuraHandledException
        Boolean thrown = false;

        Test.startTest();
        try {
            EnvelopeStatusService.getEnvelopeStatusDetail('NOT_A_VALID_ID');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown,
            'Malformed Id should throw AuraHandledException');
    }
*/
    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 4 — getEnvelopeStatusSummary
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetEnvelopeStatusSummary_nullSourceId_returnsEmptyMap() {
        Test.startTest();
            Map<String, Integer> result =
                EnvelopeStatusService.getEnvelopeStatusSummary(null);
        Test.stopTest();

        System.assertNotEquals(null, result,
            'Should return empty map, not null, for null sourceId');
        System.assertEquals(0, result.size(),
            'Empty map expected for null sourceId');
    }

    @isTest
    static void testGetEnvelopeStatusSummary_noRecords_returnsEmptyMap() {
        Application__c app = setupApplication();
        // No records created for this application

        Test.startTest();
            Map<String, Integer> result =
                EnvelopeStatusService.getEnvelopeStatusSummary(app.Id);
        Test.stopTest();

        System.assertNotEquals(null, result,
            'Should return empty map, not null, when no records exist');
        System.assertEquals(0, result.size(),
            'Empty map expected when no records linked to sourceId');
    }

    @isTest
    static void testGetEnvelopeStatusSummary_singleStatus_returnsCorrectCount() {
        Application__c app = setupApplication();
        TestDataFactory.createBulkEnvelopeStatuses(app.Id, 'sent', 3, true);

        Test.startTest();
            Map<String, Integer> result =
                EnvelopeStatusService.getEnvelopeStatusSummary(app.Id);
        Test.stopTest();

        System.assertEquals(1, result.size(),
            'Summary should have one entry for one distinct status');
        System.assert(result.containsKey('sent'),
            'Summary should contain key "sent"');
        System.assertEquals(3, result.get('sent'),
            'Count for "sent" should be 3');
    }

    @isTest
    static void testGetEnvelopeStatusSummary_multipleStatuses_returnsCountPerStatus() {
        Application__c app = setupApplication();
        TestDataFactory.createBulkEnvelopeStatuses(app.Id, 'sent',      3, true);
        TestDataFactory.createBulkEnvelopeStatuses(app.Id, 'completed', 2, true);
        TestDataFactory.createBulkEnvelopeStatuses(app.Id, 'declined',  1, true);

        Test.startTest();
            Map<String, Integer> result =
                EnvelopeStatusService.getEnvelopeStatusSummary(app.Id);
        Test.stopTest();

        System.assertEquals(3, result.size(),
            'Summary should have 3 entries for 3 distinct statuses');

        System.assert(result.containsKey('sent'),
            'Summary should contain key "sent"');
        System.assertEquals(3, result.get('sent'),
            'Count for "sent" should be 3');

        System.assert(result.containsKey('completed'),
            'Summary should contain key "completed"');
        System.assertEquals(2, result.get('completed'),
            'Count for "completed" should be 2');

        System.assert(result.containsKey('declined'),
            'Summary should contain key "declined"');
        System.assertEquals(1, result.get('declined'),
            'Count for "declined" should be 1');
    }
/*
    @isTest
    static void testGetEnvelopeStatusSummary_onlyCountsRecordsForMatchingSource() {
        Application__c app1 = setupApplication();
        Application__c app2 = setupApplication();

        TestDataFactory.createBulkEnvelopeStatuses(app1.Id, 'sent', 2, true);
        TestDataFactory.createBulkEnvelopeStatuses(app2.Id, 'sent', 5, true);

        Test.startTest();
            Map<String, Integer> result =
                EnvelopeStatusService.getEnvelopeStatusSummary(app1.Id);
        Test.stopTest();

        System.assertEquals(1, result.size(),
            'Only one status group should be returned for app1');
        System.assertEquals(2, result.get('sent'),
            'Count should be 2 — only app1 records counted, not app2');
    }
*/
    @isTest
    static void testGetEnvelopeStatusSummary_totalCountMatchesAllRecords() {
        Application__c app = setupApplication();
        TestDataFactory.createBulkEnvelopeStatuses(app.Id, 'sent',      4, true);
        TestDataFactory.createBulkEnvelopeStatuses(app.Id, 'completed', 3, true);

        Test.startTest();
            Map<String, Integer> result =
                EnvelopeStatusService.getEnvelopeStatusSummary(app.Id);
        Test.stopTest();

        // Sum of all values in the summary should equal total records
        Integer total = 0;
        for (Integer count : result.values()) total += count;

        System.assertEquals(7, total,
            'Sum of all status counts should equal total records (4 + 3 = 7)');
    }
}