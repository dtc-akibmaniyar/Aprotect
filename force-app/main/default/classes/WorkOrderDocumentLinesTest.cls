/**
 * The Apex half of the pair that holds the work order document grouping rule
 * together (TASK-050).
 *
 * THE FIXTURE BELOW IS SHARED. Its twin is
 * lwc/workOrderDocument/__tests__/workOrderDocument.test.js, which asserts the
 * same inputs produce the same rows in JavaScript. The rule has to exist in
 * both runtimes, because the Manage Estimates preview recalculates on unsaved
 * input and cannot call Apex, so these two tests are what stop the two copies
 * drifting apart. That drift is exactly what produced a 3-row PDF against a
 * 2-row preview on 2026-10-09.
 *
 * If you change the rule, change BOTH tests, or one of them will tell you.
 */
@IsTest
private class WorkOrderDocumentLinesTest {

    private static WorkOrderDocumentLines.SourceLine line(String t, String d, Decimal a) {
        return new WorkOrderDocumentLines.SourceLine(t, d, a);
    }

    /**
     * THE SHARED FIXTURE: one part, one labour, one supply and one extended
     * warranty, the shape a normal repair estimate produces.
     */
    private static List<WorkOrderDocumentLines.SourceLine> fixture() {
        return new List<WorkOrderDocumentLines.SourceLine>{
            line('Part', 'Engine', 2800),
            line('Labour', 'Engine R and R', 1040),
            line('Extended Warranty', 'Extended Warranty: Engine (12 mo)', 188.50),
            line('Supplies', 'Shop supplies', 299)
        };
    }

    @IsTest
    static void groupsTheSharedFixtureIntoThreeRows() {
        List<WorkOrderDocumentLines.DocumentLine> rows =
            WorkOrderDocumentLines.groupLines(fixture());

        System.assertEquals(3, rows.size(),
            'four stored lines become three document rows: repair, warranty, supplies');

        System.assertEquals('Repair', rows[0].lineType);
        System.assertEquals('Engine Replacement (Including Parts and Labour)', rows[0].description);
        System.assertEquals(3840, rows[0].amount, 'parts 2800 plus labour 1040');

        System.assertEquals('Extended Warranty', rows[1].lineType,
            'a warranty keeps its own row and its own description');
        System.assertEquals('Extended Warranty: Engine (12 mo)', rows[1].description);
        System.assertEquals(188.50, rows[1].amount);

        System.assertEquals('Supplies', rows[2].lineType);
        System.assertEquals('Shop Supplies (Customer Responsibility)', rows[2].description);
        System.assertEquals(299, rows[2].amount);
    }

    /** Several parts all name themselves in the one repair row, in order. */
    @IsTest
    static void namesEveryPartInTheRepairRow() {
        List<WorkOrderDocumentLines.DocumentLine> rows = WorkOrderDocumentLines.groupLines(
            new List<WorkOrderDocumentLines.SourceLine>{
                line('Part', 'Engine', 2000),
                line('Part', 'Turbocharger', 900),
                line('Labour', 'Engine R and R', 800)
            });

        System.assertEquals(1, rows.size());
        System.assertEquals('Engine, Turbocharger Replacement (Including Parts and Labour)',
            rows[0].description);
        System.assertEquals(3700, rows[0].amount);
    }

    /** Labour with no part still produces a repair row rather than vanishing. */
    @IsTest
    static void labourWithoutAPartFallsBackToRepair() {
        List<WorkOrderDocumentLines.DocumentLine> rows = WorkOrderDocumentLines.groupLines(
            new List<WorkOrderDocumentLines.SourceLine>{ line('Labour', 'Diagnosis', 240) });

        System.assertEquals(1, rows.size());
        System.assertEquals('Repair Replacement (Including Parts and Labour)', rows[0].description);
        System.assertEquals(240, rows[0].amount);
    }

    /** Supplies of zero are omitted; the customer should not read a zero row. */
    @IsTest
    static void omitsSuppliesWhenTheyAreZero() {
        List<WorkOrderDocumentLines.DocumentLine> rows = WorkOrderDocumentLines.groupLines(
            new List<WorkOrderDocumentLines.SourceLine>{
                line('Part', 'Engine', 2800),
                line('Supplies', 'Shop supplies', 0)
            });

        System.assertEquals(1, rows.size(), 'the supplies row is dropped, not printed as $0.00');
        System.assertEquals('Repair', rows[0].lineType);
    }

    /** Reimbursement-only work orders have nothing to list here. */
    @IsTest
    static void emptyInputProducesNoRows() {
        System.assertEquals(0,
            WorkOrderDocumentLines.groupLines(new List<WorkOrderDocumentLines.SourceLine>()).size());
        System.assertEquals(0, WorkOrderDocumentLines.groupLines(null).size(),
            'null must be treated as nothing to show, not thrown');
    }

    /**
     * An unrecognised type joins the repair row rather than disappearing. A
     * customer is asked to authorize this document, so a line with an
     * unexpected type must still be visible and still counted.
     */
    @IsTest
    static void anUnknownTypeJoinsTheRepairRowRatherThanVanishing() {
        List<WorkOrderDocumentLines.DocumentLine> rows = WorkOrderDocumentLines.groupLines(
            new List<WorkOrderDocumentLines.SourceLine>{
                line('Part', 'Engine', 2000),
                line('Sublet', 'Machine shop', 350)
            });

        System.assertEquals(1, rows.size());
        System.assertEquals(2350, rows[0].amount, 'the sublet amount is still on the document');
        System.assertEquals('Engine Replacement (Including Parts and Labour)', rows[0].description,
            'but only parts name themselves in the label');
    }
}