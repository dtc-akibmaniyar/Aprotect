/**
 * THE JAVASCRIPT MIRROR of the canonical work order document grouping rule.
 *
 * The rule itself is stated in Apex, in WorkOrderDocumentLines. Read that
 * class first: it carries the reasoning and is the definition of record.
 *
 * This mirror exists because the Manage Estimates preview recalculates on
 * every keystroke against input that has not been saved, so it cannot call
 * Apex. A single definition across both runtimes is not possible. What holds
 * them together is that the SAME fixture is asserted on both sides:
 *   - Apex: WorkOrderDocumentLinesTest
 *   - Jest: ./__tests__/workOrderDocument.test.js
 * Change the rule in one place and those two tests disagree.
 *
 * Osama, 2026-10-09, chose this over merging the stored line items: the
 * Work_Order_Line_Item__c records stay one per estimate child so per-part
 * ordering and Estimate-child traceability survive, and only the document
 * groups.
 */

export const TYPE_PART = 'Part';
export const TYPE_LABOUR = 'Labour';
export const TYPE_SUPPLIES = 'Supplies';
export const TYPE_WARRANTY = 'Extended Warranty';

export const REPAIR_SUFFIX = ' Replacement (Including Parts and Labour)';
export const REPAIR_FALLBACK = 'Repair';
export const SUPPLIES_LABEL = 'Shop Supplies (Customer Responsibility)';

/**
 * @param {Array<{lineType: string, description: string, amount: number}>} source
 * @returns {Array<{lineType: string, description: string, amount: number}>}
 */
export function groupDocumentLines(source) {
    const out = [];
    if (!Array.isArray(source) || source.length === 0) {
        return out;
    }

    const partNames = [];
    const warranties = [];
    let repairTotal = 0;
    let suppliesTotal = 0;
    let sawRepairLine = false;

    source.forEach((line) => {
        if (!line) {
            return;
        }
        const amount = Number(line.amount) || 0;

        if (line.lineType === TYPE_WARRANTY) {
            warranties.push({ lineType: TYPE_WARRANTY, description: line.description, amount });
        } else if (line.lineType === TYPE_SUPPLIES) {
            suppliesTotal += amount;
        } else {
            // Part, Labour, and anything unrecognised, which belongs with the
            // repair rather than being silently dropped off a document the
            // customer is asked to authorize.
            sawRepairLine = true;
            if (line.lineType === TYPE_PART && line.description && line.description.trim()) {
                partNames.push(line.description.trim());
            }
            repairTotal += amount;
        }
    });

    if (sawRepairLine) {
        const name = partNames.length ? partNames.join(', ') : REPAIR_FALLBACK;
        out.push({ lineType: 'Repair', description: name + REPAIR_SUFFIX, amount: repairTotal });
    }
    out.push(...warranties);
    if (suppliesTotal !== 0) {
        out.push({ lineType: TYPE_SUPPLIES, description: SUPPLIES_LABEL, amount: suppliesTotal });
    }
    return out;
}