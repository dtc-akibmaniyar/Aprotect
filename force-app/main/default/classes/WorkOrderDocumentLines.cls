/**
 * THE CANONICAL GROUPING RULE for the work order document (TASK-050).
 *
 * Osama chose this arrangement on 2026-10-09. The problem it solves: the
 * Manage Estimates preview and the work order PDF each implemented the same
 * grouping separately, so they disagreed about how many rows the document had,
 * and fixing one never fixed the other.
 *
 * THE RULE, stated once:
 *   1. Every Part and Labour line collapses into ONE row, described as
 *      "<part descriptions, comma separated> Replacement (Including Parts and
 *      Labour)", or "Repair Replacement (Including Parts and Labour)" when no
 *      part is named. Its amount is the sum of those lines.
 *   2. Each Extended Warranty keeps its own row, with its own description.
 *   3. Every Shop Supply line collapses into one row described as
 *      "Shop Supplies (Customer Responsibility)", omitted when the total is
 *      zero.
 *   4. Order is always: the repair row, then the warranty rows, then supplies.
 *
 * This groups PRESENTATION ONLY. The stored Work_Order_Line_Item__c records
 * remain one per estimate child, each traceable through Claim_Line_Item__c to
 * its Part__c, Service__c or Shop_Supply__c, which is what the TASK-050
 * primary rule requires. A customer document that lists a repair as one line
 * is not a different data structure, only a summary of one.
 *
 * MIRRORED IN JAVASCRIPT at lwc/workOrderDocument/workOrderDocument.js,
 * because the Manage Estimates preview recalculates on every keystroke against
 * unsaved input and cannot call Apex. A single definition across both runtimes
 * is not possible; what IS possible is one canonical statement of the rule
 * here, a mirror there, and the SAME fixture asserted on both sides:
 *   - Apex: WorkOrderDocumentLinesTest
 *   - Jest: lwc/workOrderDocument/__tests__/workOrderDocument.test.js
 * Change the rule in one place and those two tests disagree, which is the
 * point. The pricing engine is held together the same way.
 */
public with sharing class WorkOrderDocumentLines {

    public static final String TYPE_PART     = 'Part';
    public static final String TYPE_LABOUR   = 'Labour';
    public static final String TYPE_SUPPLIES = 'Supplies';
    public static final String TYPE_WARRANTY = 'Extended Warranty';

    public static final String REPAIR_SUFFIX   = ' Replacement (Including Parts and Labour)';
    public static final String REPAIR_FALLBACK = 'Repair';
    public static final String SUPPLIES_LABEL  = 'Shop Supplies (Customer Responsibility)';

    /** One stored line, as it exists on the estimate or the work order. */
    public class SourceLine {
        public String lineType;
        public String description;
        public Decimal amount;

        public SourceLine(String lineType, String description, Decimal amount) {
            this.lineType = lineType;
            this.description = description;
            this.amount = amount;
        }
    }

    /** One row as the document prints it. */
    public class DocumentLine {
        @AuraEnabled public String lineType { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
    }

    /**
     * Applies the rule above. Pure: no SOQL, no DML, no dependency on the work
     * order, so it can be unit tested directly against a fixture and reused by
     * anything that needs to render this document.
     */
    public static List<DocumentLine> groupLines(List<SourceLine> source) {
        List<DocumentLine> out = new List<DocumentLine>();
        if (source == null || source.isEmpty()) return out;

        List<String> partNames = new List<String>();
        Decimal repairTotal = 0;
        Decimal suppliesTotal = 0;
        Boolean sawRepairLine = false;
        List<DocumentLine> warranties = new List<DocumentLine>();

        for (SourceLine s : source) {
            if (s == null) continue;
            Decimal amount = s.amount == null ? 0 : s.amount;

            if (s.lineType == TYPE_WARRANTY) {
                warranties.add(row(TYPE_WARRANTY, s.description, amount));
            } else if (s.lineType == TYPE_SUPPLIES) {
                suppliesTotal += amount;
            } else {
                // Part, Labour, and anything unrecognised, which belongs with
                // the repair rather than being silently dropped off a document
                // the customer is asked to authorize.
                sawRepairLine = true;
                if (s.lineType == TYPE_PART && String.isNotBlank(s.description)) {
                    partNames.add(s.description.trim());
                }
                repairTotal += amount;
            }
        }

        if (sawRepairLine) {
            String name = partNames.isEmpty() ? REPAIR_FALLBACK : String.join(partNames, ', ');
            out.add(row('Repair', name + REPAIR_SUFFIX, repairTotal));
        }
        out.addAll(warranties);
        if (suppliesTotal != 0) {
            out.add(row(TYPE_SUPPLIES, SUPPLIES_LABEL, suppliesTotal));
        }
        return out;
    }

    private static DocumentLine row(String lineType, String description, Decimal amount) {
        DocumentLine d = new DocumentLine();
        d.lineType = lineType;
        d.description = description;
        d.amount = amount;
        return d;
    }
}