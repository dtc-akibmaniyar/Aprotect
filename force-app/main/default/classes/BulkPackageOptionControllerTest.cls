/**
 * BulkPackageOptionControllerTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Covers BulkPackageOptionController (Visualforce page controller):
 *   • Constructor                — initialises list with one empty row
 *   • addRow()                   — appends a new PackageOptionWrapper
 *   • removeRow()                — removes the selected index and re-indexes
 *   • getSelectionTypeOptions()  — returns SelectOption list for the picklist
 *   • saveRecords()              — bulk inserts valid Package_Option__c rows
 *
 * Test Strategy:
 *   ✔ @isTest(SeeAllData=false)
 *   ✔ All DML via TestDataFactory; Option__c created inline (no factory method)
 *   ✔ Positive + Negative per branch
 *   ✔ System.assert* with descriptive messages
 *   ✔ Test.startTest / Test.stopTest
 */
@isTest(SeeAllData=false)
private class BulkPackageOptionControllerTest {

    @TestSetup
    static void setup() {
        // Option__c catalog entry — no TestDataFactory method, created inline
        insert new Option__c(Name = 'Test Option For Bulk');
        TestDataFactory.createPackage('Extended_Limited_Warranty', true);
    }

    // ── Query helpers ─────────────────────────────────────────────────────────

    private static Option__c getOption() {
        return [SELECT Id FROM Option__c LIMIT 1];
    }

    private static Package__c getPackage() {
        return [SELECT Id FROM Package__c LIMIT 1];
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Constructor
    // ═════════════════════════════════════════════════════════════════════════

    @isTest
    static void testConstructor_initializesWithOneRow() {
        Test.startTest();
        BulkPackageOptionController ctrl = new BulkPackageOptionController();
        Test.stopTest();

        System.assertNotEquals(null, ctrl.packageOptionList,
            'packageOptionList should be initialised by the constructor');
        System.assertEquals(1, ctrl.packageOptionList.size(),
            'Constructor should initialise the list with exactly one row via addRow()');
        System.assertEquals(0, ctrl.packageOptionList[0].index,
            'First row index should be 0');
        System.assertNotEquals(null, ctrl.packageOptionList[0].packageOption,
            'PackageOptionWrapper should contain a non-null Package_Option__c instance');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // addRow
    // ═════════════════════════════════════════════════════════════════════════

    @isTest
    static void testAddRow_appendsNewRowsWithCorrectIndices() {
        BulkPackageOptionController ctrl = new BulkPackageOptionController();

        Test.startTest();
        ctrl.addRow();
        ctrl.addRow();
        Test.stopTest();

        System.assertEquals(3, ctrl.packageOptionList.size(),
            'After two addRow() calls the list should contain 3 rows total');
        System.assertEquals(2, ctrl.packageOptionList[2].index,
            'Third row should have index 2');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // removeRow
    // ═════════════════════════════════════════════════════════════════════════

    @isTest
    static void testRemoveRow_removesSelectedIndexAndReindexes() {
        BulkPackageOptionController ctrl = new BulkPackageOptionController();
        ctrl.addRow(); // rows 0 and 1

        Test.startTest();
        ctrl.selectedRowIndex = 0;
        ctrl.removeRow();
        Test.stopTest();

        System.assertEquals(1, ctrl.packageOptionList.size(),
            'List should have 1 row after removing row at index 0');
        System.assertEquals(0, ctrl.packageOptionList[0].index,
            'Remaining row should be re-indexed to 0');
    }

    @isTest
    static void testRemoveRow_nullIndex_doesNotModifyList() {
        BulkPackageOptionController ctrl = new BulkPackageOptionController();

        Test.startTest();
        ctrl.selectedRowIndex = null;
        ctrl.removeRow();
        Test.stopTest();

        System.assertEquals(1, ctrl.packageOptionList.size(),
            'List size should not change when selectedRowIndex is null');
    }

    @isTest
    static void testRemoveRow_outOfBoundsIndex_doesNotModifyList() {
        BulkPackageOptionController ctrl = new BulkPackageOptionController();

        Test.startTest();
        ctrl.selectedRowIndex = 99;
        ctrl.removeRow();
        Test.stopTest();

        System.assertEquals(1, ctrl.packageOptionList.size(),
            'List size should not change when selectedRowIndex is out of bounds');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // getSelectionTypeOptions
    // ═════════════════════════════════════════════════════════════════════════

    @isTest
    static void testGetSelectionTypeOptions_returnsNonEmptyList() {
        BulkPackageOptionController ctrl = new BulkPackageOptionController();

        Test.startTest();
        List<SelectOption> options = ctrl.getSelectionTypeOptions();
        Test.stopTest();

        System.assertNotEquals(null, options,
            'getSelectionTypeOptions should not return null');
        System.assert(options.size() >= 1,
            'At least one SelectOption (the --None-- placeholder) should be returned');
    }

    @isTest
    static void testGetSelectionTypeOptions_firstOptionIsNonePlaceholder() {
        BulkPackageOptionController ctrl = new BulkPackageOptionController();

        Test.startTest();
        List<SelectOption> options = ctrl.getSelectionTypeOptions();
        Test.stopTest();

        System.assertEquals('--None--', options[0].getValue(),
            'First SelectOption should be the --None-- placeholder');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // saveRecords
    // ═════════════════════════════════════════════════════════════════════════

    @isTest
    static void testSaveRecords_validRow_insertsPackageOptionAndResetsForm() {
        Option__c opt  = getOption();
        Package__c pkg = getPackage();

        BulkPackageOptionController ctrl = new BulkPackageOptionController();
        ctrl.packageOptionList[0].packageOption.Option__c         = opt.Id;
        ctrl.packageOptionList[0].packageOption.Price__c          = 100.00;
        ctrl.packageOptionList[0].packageOption.Package__c        = pkg.Id;
        ctrl.packageOptionList[0].packageOption.Selection_Type__c = 'Optional';

        Test.startTest();
        ctrl.saveRecords();
        Test.stopTest();

        List<Package_Option__c> inserted = [
            SELECT Id FROM Package_Option__c
            WHERE Package__c = :pkg.Id AND Option__c = :opt.Id
        ];
        System.assertEquals(1, inserted.size(),
            'saveRecords should insert the Package_Option__c row when Option__c and Price__c are set');
        System.assertEquals(1, ctrl.packageOptionList.size(),
            'After a successful save the form should be reset to one empty row');
    }

    @isTest
    static void testSaveRecords_rowMissingOptionId_skipsRow() {
        Package__c pkg = getPackage();

        BulkPackageOptionController ctrl = new BulkPackageOptionController();
        ctrl.packageOptionList[0].packageOption.Price__c   = 100.00;
        ctrl.packageOptionList[0].packageOption.Package__c = pkg.Id;
        // Option__c intentionally left null

        Integer before = [SELECT COUNT() FROM Package_Option__c];

        Test.startTest();
        ctrl.saveRecords();
        Test.stopTest();

        System.assertEquals(before, [SELECT COUNT() FROM Package_Option__c],
            'Row missing Option__c should be skipped — no record inserted');
    }

    @isTest
    static void testSaveRecords_rowMissingPrice_skipsRow() {
        Option__c opt  = getOption();
        Package__c pkg = getPackage();

        BulkPackageOptionController ctrl = new BulkPackageOptionController();
        ctrl.packageOptionList[0].packageOption.Option__c  = opt.Id;
        ctrl.packageOptionList[0].packageOption.Package__c = pkg.Id;
        // Price__c intentionally left null

        Integer before = [SELECT COUNT() FROM Package_Option__c];

        Test.startTest();
        ctrl.saveRecords();
        Test.stopTest();

        System.assertEquals(before, [SELECT COUNT() FROM Package_Option__c],
            'Row missing Price__c should be skipped — no record inserted');
    }

    @isTest
    static void testSaveRecords_allRowsInvalid_noInsert() {
        BulkPackageOptionController ctrl = new BulkPackageOptionController();
        // Both Option__c and Price__c left null

        Integer before = [SELECT COUNT() FROM Package_Option__c];

        Test.startTest();
        ctrl.saveRecords();
        Test.stopTest();

        System.assertEquals(before, [SELECT COUNT() FROM Package_Option__c],
            'saveRecords with all-invalid rows should not insert anything');
    }
}