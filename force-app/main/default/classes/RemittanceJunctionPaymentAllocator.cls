/**
 * RemittanceJunctionPaymentAllocator
 *
 * Replaces the broken "Update_Remittance_Line_Item_Junction" flow logic.
 * When a Payment__c is created on a Remittance_Form__c, this class allocates
 * Remittance_Line_Item_Junction__c records to payments using a first-fit
 * decreasing algorithm based on payment amounts.
 *
 * The old flow blindly set Payment__c on ALL junctions for the remittance
 * to the triggering payment's Id, so the last-created payment "stole" all junctions.
 *
 * New logic:
 *  1. Collect all payments on the remittance, sorted by CreatedDate ASC.
 *  2. Collect all unallocated junctions (Payment__c IS NULL) plus junctions
 *     already allocated to any payment in this remittance.
 *  3. Clear all junction Payment__c assignments and re-allocate from scratch:
 *     For each payment (in creation order), assign junctions (smallest-amount-first)
 *     until the payment's Amount__c is exhausted.
 *  4. Update junction records.
 *
 * Invocable so it can be called from a replacement flow or from triggers.
 */
public with sharing class RemittanceJunctionPaymentAllocator {

    public class Request {
        @InvocableVariable(required=true description='The Payment__c Id that was just created or updated')
        public Id paymentId;
    }

    public class Result {
        @InvocableVariable
        public Boolean success;
        @InvocableVariable
        public String message;
        @InvocableVariable
        public Integer junctionsUpdated;
    }

    @InvocableMethod(
        label='Allocate Junctions to Payments'
        description='Distributes Remittance_Line_Item_Junction__c records across all payments on a remittance using amount-based allocation.'
    )
    public static List<Result> allocate(List<Request> requests) {
        List<Result> results = new List<Result>();

        if (requests == null || requests.isEmpty()) {
            results.add(buildResult(false, 'No requests provided.', 0));
            return results;
        }

        // Collect payment Ids and look up their remittance forms
        Set<Id> paymentIds = new Set<Id>();
        for (Request req : requests) {
            if (req != null && req.paymentId != null) {
                paymentIds.add(req.paymentId);
            }
        }

        if (paymentIds.isEmpty()) {
            results.add(buildResult(false, 'No payment Ids provided.', 0));
            return results;
        }

        // Get the payments and their remittance form Ids
        Map<Id, Payment__c> paymentsById = new Map<Id, Payment__c>([
            SELECT Id, Name, Amount__c, Remittance_Form__c, CreatedDate
            FROM Payment__c
            WHERE Id IN :paymentIds
        ]);

        // Group by remittance form — we process each remittance form once
        Set<Id> remittanceFormIds = new Set<Id>();
        for (Payment__c pmt : paymentsById.values()) {
            if (pmt.Remittance_Form__c != null) {
                remittanceFormIds.add(pmt.Remittance_Form__c);
            }
        }

        if (remittanceFormIds.isEmpty()) {
            results.add(buildResult(false, 'No remittance forms found for given payments.', 0));
            return results;
        }

        // Get ALL payments for each remittance form, sorted by CreatedDate
        List<Payment__c> allPayments = [
            SELECT Id, Name, Amount__c, Remittance_Form__c, CreatedDate
            FROM Payment__c
            WHERE Remittance_Form__c IN :remittanceFormIds
            ORDER BY CreatedDate ASC
        ];

        Map<Id, List<Payment__c>> paymentsByRemittance = new Map<Id, List<Payment__c>>();
        for (Payment__c pmt : allPayments) {
            if (!paymentsByRemittance.containsKey(pmt.Remittance_Form__c)) {
                paymentsByRemittance.put(pmt.Remittance_Form__c, new List<Payment__c>());
            }
            paymentsByRemittance.get(pmt.Remittance_Form__c).add(pmt);
        }

        // Get ALL junctions for these remittance forms
        List<Remittance_Line_Item_Junction__c> allJunctions = [
            SELECT Id, Name, Line_Item_Amount__c, Payment__c, Remittance_Form__c
            FROM Remittance_Line_Item_Junction__c
            WHERE Remittance_Form__c IN :remittanceFormIds
            ORDER BY Line_Item_Amount__c ASC
        ];

        Map<Id, List<Remittance_Line_Item_Junction__c>> junctionsByRemittance = new Map<Id, List<Remittance_Line_Item_Junction__c>>();
        for (Remittance_Line_Item_Junction__c rlj : allJunctions) {
            if (!junctionsByRemittance.containsKey(rlj.Remittance_Form__c)) {
                junctionsByRemittance.put(rlj.Remittance_Form__c, new List<Remittance_Line_Item_Junction__c>());
            }
            junctionsByRemittance.get(rlj.Remittance_Form__c).add(rlj);
        }

        // Allocate junctions to payments for each remittance form
        List<Remittance_Line_Item_Junction__c> junctionsToUpdate = new List<Remittance_Line_Item_Junction__c>();
        Integer totalUpdated = 0;

        for (Id remFormId : remittanceFormIds) {
            List<Payment__c> payments = paymentsByRemittance.get(remFormId);
            List<Remittance_Line_Item_Junction__c> junctions = junctionsByRemittance.get(remFormId);

            if (payments == null || payments.isEmpty() || junctions == null || junctions.isEmpty()) {
                continue;
            }

            // Sort junctions by amount ascending (already ordered by query)
            // Allocate: for each payment in creation order, fill junctions until amount exhausted
            Set<Id> allocatedJunctionIds = new Set<Id>();

            for (Payment__c pmt : payments) {
                Decimal remaining = pmt.Amount__c != null ? pmt.Amount__c : 0;

                for (Remittance_Line_Item_Junction__c rlj : junctions) {
                    if (allocatedJunctionIds.contains(rlj.Id)) {
                        continue; // already assigned to an earlier payment
                    }
                    Decimal amt = rlj.Line_Item_Amount__c != null ? rlj.Line_Item_Amount__c : 0;
                    if (amt <= remaining) {
                        // This junction fits within this payment's remaining amount
                        allocatedJunctionIds.add(rlj.Id);
                        remaining -= amt;

                        // Only update if the Payment__c lookup actually changed
                        if (rlj.Payment__c != pmt.Id) {
                            junctionsToUpdate.add(new Remittance_Line_Item_Junction__c(
                                Id = rlj.Id,
                                Payment__c = pmt.Id
                            ));
                            totalUpdated++;
                        }
                    }
                }
            }

            // Any junctions that couldn't be allocated to any payment
            // (shouldn't happen if total payments = total line items)
            // leave them unassigned or assign to the last payment as fallback
            for (Remittance_Line_Item_Junction__c rlj : junctions) {
                if (!allocatedJunctionIds.contains(rlj.Id)) {
                    // Fallback: assign to last payment
                    Payment__c lastPayment = payments.get(payments.size() - 1);
                    if (rlj.Payment__c != lastPayment.Id) {
                        junctionsToUpdate.add(new Remittance_Line_Item_Junction__c(
                            Id = rlj.Id,
                            Payment__c = lastPayment.Id
                        ));
                        totalUpdated++;
                    }
                }
            }
        }

        // DML
        if (!junctionsToUpdate.isEmpty()) {
            Database.SaveResult[] srs = Database.update(junctionsToUpdate, false);
            Integer successCount = 0;
            for (Database.SaveResult sr : srs) {
                if (sr.isSuccess()) successCount++;
            }
            results.add(buildResult(true, 'Allocated ' + successCount + ' junction(s) across payments.', successCount));
        } else {
            results.add(buildResult(true, 'No junction updates needed — allocations already correct.', 0));
        }

        return results;
    }

    private static Result buildResult(Boolean success, String message, Integer count) {
        Result r = new Result();
        r.success = success;
        r.message = message;
        r.junctionsUpdated = count;
        return r;
    }
}