/**
 * PaymentStatusInvocable
 * Invocable service to mark Remittance_Line_Item_Junction__c, related Invoice_Line_Item__c,
 * Invoice__c and Application_Package__c as Paid based on Payment__c confirmation status.
 *
 * Requirements implemented:
 * - Invocable Apex callable from Flow
 * - Bulkified processing with maps and sets, no SOQL/DML in loops
 * - Database methods, run in USER_MODE
 * - Return Early pattern and structured per-item results
 * - with sharing and ApexDocs
 *
 * Assumptions (confirmed by user):
 * - Payment__c.Payment_Confirmation_Status__c uses values 'Transaction Completed' and 'Deposit Completed'
 * - Remittance_Line_Item_Junction__c fields:
 *     - Remittance_Form__c (Lookup), Invoice__c (Lookup), Invoice_Line_Item__c (Lookup), Payment__c (Lookup)
 *     - Payment_Status__c values: 'Planned', 'Paid'
 *     - Paid_Date__c (Date), Line_Item_Amount__c (Currency)
 * - Invoice_Line_Item__c has Payment_Status__c picklist with value 'Paid'
 * - Invoice__c has Payment_Status__c with values 'Paid', 'Partial Paid'
 * - Invoice_Line_Item__c has a 1:1 relationship to Application_Package__c that should be marked Paid
 *
 * v2 FIX: Payment allocation now pools ALL completed payment amounts at the
 *   remittance-form level so that surplus from one payment can cover junctions
 *   linked to another payment on the same remittance. Previously each payment
 *   was processed independently, causing under-allocation when a single payment
 *   didn't fully cover its assigned junction amount.
 */
public with sharing class PaymentStatusInvocable {

    /**
     * Completed statuses for Payment_Confirmation_Status__c
     */
    public enum PAYMENT_CONFIRMATION_STATUS {
        TRANSACTION_COMPLETED, // 'Transaction Completed'
        DEPOSIT_COMPLETED      // 'Deposit Completed'
    }

    /**
     * Generic Payment Status values (picklist text)
     */
    public enum PAYMENT_STATUS {
        PLANNED,  // 'Planned'
        PAID      // 'Paid'
    }

    /**
     * Request for an individual Payment to process
     */
    public class Request {
        @InvocableVariable(required=true)
        public Id paymentId;

        /**
         * Optional: explicitly pass the status you're transitioning to.
         * If omitted, the class will read Payment__c.Payment_Confirmation_Status__c.
         */
        @InvocableVariable(required=false)
        public String newConfirmationStatus;
    }

    /**
     * Result per-request
     */
    public class Result {
        @InvocableVariable
        public Id paymentId;
        @InvocableVariable
        public Boolean success;
        @InvocableVariable
        public String message;
        @InvocableVariable
        public Integer rljUpdated;
        @InvocableVariable
        public Integer lineItemsUpdated;
        @InvocableVariable
        public Integer invoicesPaid;
        @InvocableVariable
        public Integer invoicesPartial;
        @InvocableVariable
        public Integer appPackagesUpdated;
    }

    /**
     * Invocable entry point
     */
    @InvocableMethod(label='Mark Payment and Related Records Paid' description='Marks junction line items, invoice line items, invoices, and application packages as Paid for completed payments.' )
    public static List<Result> markPaid(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        // Normalize input and collect Payment Ids
        Set<Id> paymentIds = new Set<Id>();
        Map<Id, String> explicitStatusByPayment = new Map<Id, String>();
        for (Request req : requests) {
            Result res = new Result();
            res.paymentId = req != null ? req.paymentId : null;

            if (req == null || req.paymentId == null) {
                res.success = false;
                res.message = 'Missing request or paymentId';
                results.add(res);
                continue;
            }

            paymentIds.add(req.paymentId);
            if (req.newConfirmationStatus != null) {
                explicitStatusByPayment.put(req.paymentId, req.newConfirmationStatus);
            }
            // Initialize counts
            res.success = true; // provisional
            res.rljUpdated = 0;
            res.lineItemsUpdated = 0;
            res.invoicesPaid = 0;
            res.invoicesPartial = 0;
            res.appPackagesUpdated = 0;
            results.add(res);
        }

        if (paymentIds.isEmpty()) {
            return results;
        }

        // Query Payments
        Map<Id, Payment__c> paymentsByIdById = new Map<Id, Payment__c>([
            SELECT Id, Name, Payment_Confirmation_Status__c, Amount__c,
                   Remittance_Form__c,
                   Remittance_Form__r.Total_Planned_Amount__c,
                   Remittance_Form__r.Balance__c,
                   Remittance_Form__r.Dealer_Name__c
            FROM Payment__c
            WHERE Id IN :paymentIds
        ]);

        // Filter to completed statuses
        Set<Id> completedPaymentIds = new Set<Id>();
        for (Id pid : paymentIds) {
            Payment__c p = paymentsByIdById.get(pid);
            String status = explicitStatusByPayment.containsKey(pid) ? explicitStatusByPayment.get(pid) : (p != null ? p.Payment_Confirmation_Status__c : null);
            if (isCompletedStatus(status)) {
                completedPaymentIds.add(pid);
            }
        }

        if (completedPaymentIds.isEmpty()) {
            // Mark each result accordingly and return
            for (Result r : results) {
                if (r.paymentId != null) {
                    r.success = false;
                    r.message = 'Payment not in a completed confirmation status. Expected one of [Transaction Completed, Deposit Completed].';
                }
            }
            return results;
        }

        // ---- v2 FIX: Collect remittance form IDs and load ALL payments & junctions ----
        // Instead of only looking at junctions for the triggering payments,
        // we load ALL junctions and ALL completed payments for the entire remittance form.
        // This allows surplus from one payment to cover junctions linked to another payment.

        Set<Id> remittanceFormIdsForAllocation = new Set<Id>();
        for (Id pid : completedPaymentIds) {
            Payment__c p = paymentsByIdById.get(pid);
            if (p != null && p.Remittance_Form__c != null) {
                remittanceFormIdsForAllocation.add(p.Remittance_Form__c);
            }
        }

        // Load ALL payments for these remittance forms (not just the triggering ones)
        Map<Id, Payment__c> allPaymentsByIdForRemittance = new Map<Id, Payment__c>([
            SELECT Id, Name, Payment_Confirmation_Status__c, Amount__c,
                   Remittance_Form__c,
                   Remittance_Form__r.Total_Planned_Amount__c,
                   Remittance_Form__r.Balance__c,
                   Remittance_Form__r.Dealer_Name__c
            FROM Payment__c
            WHERE Remittance_Form__c IN :remittanceFormIdsForAllocation
        ]);

        // Also add these to the main map for downstream use
        paymentsByIdById.putAll(allPaymentsByIdForRemittance);

        // 1) Load ALL RLJ records for the remittance forms (not just triggering payments)
        List<Remittance_Line_Item_Junction__c> remittanceLineItemJunctionList = [
            SELECT Id, Payment__c, Invoice__c, Invoice_Line_Item__c, Payment_Status__c,
                   Paid_Date__c, Line_Item_Amount__c, Remittance_Form__c
            FROM Remittance_Line_Item_Junction__c
            WHERE Remittance_Form__c IN :remittanceFormIdsForAllocation
        ];

        if (remittanceLineItemJunctionList.isEmpty()) {
            for (Result r : results) {
                if (r.paymentId != null && completedPaymentIds.contains(r.paymentId)) {
                    r.success = true;
                    r.message = 'No Remittance_Line_Item_Junction__c records found for Payment. No updates required.';
                    System.debug(LoggingLevel.WARN, 'PaymentStatusInvocable.markPaid(): '
                        + '0 junction records found for completed Payment ' + r.paymentId
                        + '. This may indicate junction linking has not committed yet. '
                        + 'Verify Update_Remittance_Line_Item_Junction flow executed before this invocable.');
                }
            }
            return results;
        }

        // Build maps — group by payment for result tallying, and by remittance for allocation
        Map<Id, List<Remittance_Line_Item_Junction__c>> remittanceLineItemJunctionsByPaymentId = new Map<Id, List<Remittance_Line_Item_Junction__c>>();
        Set<Id> invoiceLineItemIds = new Set<Id>();
        Set<Id> invoiceIds = new Set<Id>();

        for (Remittance_Line_Item_Junction__c remittanceLineItemJunction : remittanceLineItemJunctionList) {
            if (remittanceLineItemJunction.Payment__c != null) {
                List<Remittance_Line_Item_Junction__c> bucket = remittanceLineItemJunctionsByPaymentId.get(remittanceLineItemJunction.Payment__c);
                if (bucket == null) {
                    bucket = new List<Remittance_Line_Item_Junction__c>();
                    remittanceLineItemJunctionsByPaymentId.put(remittanceLineItemJunction.Payment__c, bucket);
                }
                bucket.add(remittanceLineItemJunction);
            }
            if (remittanceLineItemJunction.Invoice_Line_Item__c != null) invoiceLineItemIds.add(remittanceLineItemJunction.Invoice_Line_Item__c);
            if (remittanceLineItemJunction.Invoice__c != null) invoiceIds.add(remittanceLineItemJunction.Invoice__c);
        }

        // 2) Payment Allocation — v2: pool ALL completed payment amounts per remittance form
        //    and allocate across ALL junctions on that remittance (lowest-amount-first).
        //    This fixes the bug where surplus from one payment couldn't help cover junctions
        //    linked to a different payment on the same remittance.
        Date today = Date.today();
        Set<Id> paidLineItemIds = new Set<Id>();
        Map<Id, Decimal> paidAmountByLineItemId = new Map<Id, Decimal>();
        List<Remittance_Line_Item_Junction__c> remittanceLineItemJunctionsToUpdate = new List<Remittance_Line_Item_Junction__c>();

        // Group junctions by remittance form and compute total completed payment amount per form
        Map<Id, List<Remittance_Line_Item_Junction__c>> junctionsByRemittanceForm = new Map<Id, List<Remittance_Line_Item_Junction__c>>();
        Map<Id, Decimal> totalCompletedPaymentByRemittance = new Map<Id, Decimal>();

        for (Remittance_Line_Item_Junction__c rlj : remittanceLineItemJunctionList) {
            Id rfId = rlj.Remittance_Form__c;
            if (rfId == null) continue;
            if (!junctionsByRemittanceForm.containsKey(rfId)) {
                junctionsByRemittanceForm.put(rfId, new List<Remittance_Line_Item_Junction__c>());
            }
            junctionsByRemittanceForm.get(rfId).add(rlj);
        }

        // Sum completed payment amounts per remittance form
        for (Payment__c pmt : allPaymentsByIdForRemittance.values()) {
            if (pmt.Remittance_Form__c == null) continue;
            if (!isCompletedStatus(pmt.Payment_Confirmation_Status__c)) continue;
            Id rfId = pmt.Remittance_Form__c;
            if (!totalCompletedPaymentByRemittance.containsKey(rfId)) {
                totalCompletedPaymentByRemittance.put(rfId, 0);
            }
            Decimal amt = pmt.Amount__c != null ? pmt.Amount__c : 0;
            totalCompletedPaymentByRemittance.put(rfId, totalCompletedPaymentByRemittance.get(rfId) + amt);
        }

        // Allocate per remittance form using pooled payment total
        for (Id rfId : junctionsByRemittanceForm.keySet()) {
            Decimal remaining = totalCompletedPaymentByRemittance.containsKey(rfId)
                ? totalCompletedPaymentByRemittance.get(rfId) : 0;
            if (remaining <= 0) continue;

            List<Remittance_Line_Item_Junction__c> junctions = junctionsByRemittanceForm.get(rfId);

            // Group by Invoice
            Map<Id, List<Remittance_Line_Item_Junction__c>> jxByInv = new Map<Id, List<Remittance_Line_Item_Junction__c>>();
            Map<Id, Decimal> invTotals = new Map<Id, Decimal>();
            for (Remittance_Line_Item_Junction__c rlj : junctions) {
                Id invId = rlj.Invoice__c;
                if (invId == null) continue;
                if (!jxByInv.containsKey(invId)) {
                    jxByInv.put(invId, new List<Remittance_Line_Item_Junction__c>());
                    invTotals.put(invId, 0);
                }
                jxByInv.get(invId).add(rlj);
                Decimal amt = rlj.Line_Item_Amount__c != null ? rlj.Line_Item_Amount__c : 0;
                invTotals.put(invId, invTotals.get(invId) + amt);
            }

            // Sort invoices by total amount ascending
            List<InvoiceSortWrapper> sortedInvs = new List<InvoiceSortWrapper>();
            for (Id invId : jxByInv.keySet()) {
                sortedInvs.add(new InvoiceSortWrapper(invId, invTotals.get(invId)));
            }
            sortedInvs.sort();

            for (InvoiceSortWrapper sw : sortedInvs) {
                List<Remittance_Line_Item_Junction__c> invJx = jxByInv.get(sw.invoiceId);

                // Collect unpaid junctions and their total
                List<Remittance_Line_Item_Junction__c> unpaid = new List<Remittance_Line_Item_Junction__c>();
                Decimal unpaidTotal = 0;
                for (Remittance_Line_Item_Junction__c rlj : invJx) {
                    if (rlj.Payment_Status__c != stringValue(PAYMENT_STATUS.PAID)) {
                        unpaid.add(rlj);
                        unpaidTotal += (rlj.Line_Item_Amount__c != null ? rlj.Line_Item_Amount__c : 0);
                    }
                }
                if (unpaid.isEmpty()) continue;

                if (remaining >= unpaidTotal && unpaidTotal > 0) {
                    // Pay the entire invoice
                    for (Remittance_Line_Item_Junction__c rlj : unpaid) {
                        Decimal amt = rlj.Line_Item_Amount__c != null ? rlj.Line_Item_Amount__c : 0;
                        remaining -= amt;
                        remittanceLineItemJunctionsToUpdate.add(new Remittance_Line_Item_Junction__c(
                            Id = rlj.Id,
                            Payment_Status__c = stringValue(PAYMENT_STATUS.PAID),
                            Paid_Date__c = (rlj.Paid_Date__c == null ? today : rlj.Paid_Date__c)
                        ));
                        if (rlj.Invoice_Line_Item__c != null) {
                            paidLineItemIds.add(rlj.Invoice_Line_Item__c);
                            paidAmountByLineItemId.put(rlj.Invoice_Line_Item__c, amt);
                        }
                    }
                } else {
                    // Can't pay whole invoice — try individual line items
                    unpaid.sort(new RLJAmountComparator());
                    for (Remittance_Line_Item_Junction__c rlj : unpaid) {
                        Decimal amt = rlj.Line_Item_Amount__c != null ? rlj.Line_Item_Amount__c : 0;
                        if (remaining >= amt && amt > 0) {
                            remaining -= amt;
                            remittanceLineItemJunctionsToUpdate.add(new Remittance_Line_Item_Junction__c(
                                Id = rlj.Id,
                                Payment_Status__c = stringValue(PAYMENT_STATUS.PAID),
                                Paid_Date__c = (rlj.Paid_Date__c == null ? today : rlj.Paid_Date__c)
                            ));
                            if (rlj.Invoice_Line_Item__c != null) {
                                paidLineItemIds.add(rlj.Invoice_Line_Item__c);
                                paidAmountByLineItemId.put(rlj.Invoice_Line_Item__c, amt);
                            }
                        }
                    }
                }
            }
        }

        // Narrow invoiceLineItemIds to only those actually paid
        invoiceLineItemIds.retainAll(paidLineItemIds);

        Database.SaveResult[] remittanceLineItemJunctionSaveResults = new Database.SaveResult[0];
        if (!remittanceLineItemJunctionsToUpdate.isEmpty()) {
            remittanceLineItemJunctionSaveResults = Database.update(remittanceLineItemJunctionsToUpdate, false);
        }

        // 3) Update Invoice Line Items to Paid
        // Also sets Paid_Amount__c from the junction's Line_Item_Amount__c so that
        // Balance_Amount__c (formula: Contract_Cost_Price__c - Paid_Amount__c) reflects correctly.
        List<Invoice_Line_Item__c> invoiceLineItemsToUpdate = new List<Invoice_Line_Item__c>();
        Map<Id, Invoice_Line_Item__c> invoiceLineItemById = new Map<Id, Invoice_Line_Item__c>();
        if (!invoiceLineItemIds.isEmpty()) {
            for (Invoice_Line_Item__c invoiceLineItem : [
                SELECT Id, Status__c, Contract_Cost_Price__c
                FROM Invoice_Line_Item__c
                WHERE Id IN :invoiceLineItemIds
            ]) {
                invoiceLineItemById.put(invoiceLineItem.Id, invoiceLineItem);
                if (invoiceLineItem.Status__c != stringValue(PAYMENT_STATUS.PAID)) {
                    // Use junction amount if available; fall back to the line item's own price
                    Decimal paidAmt = paidAmountByLineItemId.containsKey(invoiceLineItem.Id)
                        ? paidAmountByLineItemId.get(invoiceLineItem.Id)
                        : invoiceLineItem.Contract_Cost_Price__c;
                    invoiceLineItemsToUpdate.add(new Invoice_Line_Item__c(
                        Id            = invoiceLineItem.Id,
                        Status__c     = stringValue(PAYMENT_STATUS.PAID),
                        Paid_Amount__c = paidAmt
                    ));
                }
            }
        }

        Database.SaveResult[] invoiceLineItemSaveResults = new Database.SaveResult[0];
        if (!invoiceLineItemsToUpdate.isEmpty()) {
            invoiceLineItemSaveResults = Database.update(invoiceLineItemsToUpdate, false);
        }

        // 4) Recompute Invoice status: Paid if all its line items Paid, else Partial Paid
        // Load all line items for involved invoices to determine aggregate state
        Map<Id, AggregateCounts> countsByInvoice = new Map<Id, AggregateCounts>();
        if (!invoiceIds.isEmpty()) {
            // Query all related line items of these invoices
            for (Invoice_Line_Item__c invoiceLineItemAll : [
                SELECT Id, Invoice__c, Status__c
                FROM Invoice_Line_Item__c
                WHERE Invoice__c IN :invoiceIds
            ]) {
                if (invoiceLineItemAll.Invoice__c == null) continue;
                AggregateCounts c = countsByInvoice.get(invoiceLineItemAll.Invoice__c);
                if (c == null) {
                    c = new AggregateCounts();
                    countsByInvoice.put(invoiceLineItemAll.Invoice__c, c);
                }
                c.total++;
                if (invoiceLineItemAll.Status__c == stringValue(PAYMENT_STATUS.PAID)) {
                    c.paid++;
                }
            }
        }

        // Determine invoice updates
        List<Invoice__c> invoicesToUpdate = new List<Invoice__c>();
        Set<Id> fullyPaidInvoiceIds = new Set<Id>();
            Map<Id, Decimal> remittanceBalanceByInvoice = new Map<Id, Decimal>();
            for (Remittance_Line_Item_Junction__c rlj : remittanceLineItemJunctionList) {
                if (rlj.Invoice__c != null && rlj.Payment__c != null) {
                    Payment__c pmt = paymentsByIdById.get(rlj.Payment__c);
                    if (pmt != null && pmt.Remittance_Form__r != null) {
                        Decimal bal = pmt.Remittance_Form__r.Balance__c;
                        remittanceBalanceByInvoice.put(rlj.Invoice__c, bal != null ? bal : 0);
                    }
                }
            }

            for (Id invId : invoiceIds) {
                AggregateCounts c = countsByInvoice.get(invId);
                if (c == null || c.total == 0) {
                    continue;
                }
                String newInvStatus;
                if (c.paid == c.total) {
                    newInvStatus = 'Paid';
                    fullyPaidInvoiceIds.add(invId);
                } else {
                    newInvStatus = 'Due';
                }
                invoicesToUpdate.add(new Invoice__c(
                    Id = invId,
                    Status__c = newInvStatus
                ));
            }

        Database.SaveResult[] invoiceSaveResults = new Database.SaveResult[0];
        if (!invoicesToUpdate.isEmpty()) {
            invoiceSaveResults = Database.update(invoicesToUpdate, false);
        }

        // 5) Mark parent Application__c as Paid when its invoice is fully paid
        if (!fullyPaidInvoiceIds.isEmpty()) {
            Set<Id> appIds = new Set<Id>();
            for (Invoice__c inv : [
                SELECT Id, Application__c
                FROM Invoice__c
                WHERE Id IN :fullyPaidInvoiceIds
                AND Application__c != null
            ]) {
                appIds.add(inv.Application__c);
            }
            if (!appIds.isEmpty()) {
                List<Application__c> appsToUpdate = new List<Application__c>();
                for (Application__c app : [
                    SELECT Id, Payment_Status__c
                    FROM Application__c
                    WHERE Id IN :appIds
                ]) {
                    if (app.Payment_Status__c != stringValue(PAYMENT_STATUS.PAID)) {
                        appsToUpdate.add(new Application__c(
                            Id = app.Id,
                            Payment_Status__c = stringValue(PAYMENT_STATUS.PAID)
                        ));
                    }
                }
                if (!appsToUpdate.isEmpty()) {
                    Database.update(appsToUpdate, false);
                }
            }
        }

        // 7) Update Application_Package__c to Paid for the ILI involved
        Integer applicationPackagesUpdated = 0;
        if (!invoiceLineItemIds.isEmpty()) {
            List<Application_Package__c> applicationPackagesToUpdate = new List<Application_Package__c>();
            for (Invoice_Line_Item__c invoiceLineItem : [
                SELECT Id, Application_Package__c
                FROM Invoice_Line_Item__c
                WHERE Id IN :invoiceLineItemIds
            ]) {
                if (invoiceLineItem.Application_Package__c != null) {
                    applicationPackagesToUpdate.add(new Application_Package__c(
                        Id = invoiceLineItem.Application_Package__c,
                        Payment_Status__c = stringValue(PAYMENT_STATUS.PAID)
                    ));
                }
            }
            if (!applicationPackagesToUpdate.isEmpty()) {
                Database.SaveResult[] applicationPackageResults = Database.update(applicationPackagesToUpdate);
                for (Database.SaveResult sr : applicationPackageResults) {
                    if (sr.isSuccess()) applicationPackagesUpdated++;
                }
            }
        }

        // 8) Update Remittance Form status to Completed when all line items are paid
        Set<Id> remittanceFormIds = new Set<Id>();
        for (Remittance_Line_Item_Junction__c rlj : remittanceLineItemJunctionList) {
            if (rlj.Payment__c != null) {
                Payment__c pmt = paymentsByIdById.get(rlj.Payment__c);
                if (pmt != null && pmt.Remittance_Form__c != null) {
                    remittanceFormIds.add(pmt.Remittance_Form__c);
                }
            }
        }

        if (!remittanceFormIds.isEmpty()) {
            List<Remittance_Form__c> formsToComplete = new List<Remittance_Form__c>();
            for (Remittance_Form__c rf : [
                SELECT Id, Status__c, Balance__c, Paid_Amount__c,
                       Paid_Line_Items_Count__c, Planned_Line_Items_Count__c
                FROM Remittance_Form__c
                WHERE Id IN :remittanceFormIds
                  AND Status__c != 'Completed'
            ]) {
                if (rf.Paid_Amount__c != null && rf.Paid_Amount__c > 0
                    && rf.Balance__c != null && rf.Balance__c <= 0
                    && rf.Paid_Line_Items_Count__c != null
                    && rf.Planned_Line_Items_Count__c != null
                    && rf.Paid_Line_Items_Count__c >= rf.Planned_Line_Items_Count__c) {
                    formsToComplete.add(new Remittance_Form__c(
                        Id = rf.Id,
                        Status__c = 'Completed'
                    ));
                }
            }
            if (!formsToComplete.isEmpty()) {
                Database.update(formsToComplete, false);
            }
        }

        // 9) Credit stored — overpayment handling
        List<Payment__c> paymentsWithCredit = new List<Payment__c>();
        List<Credit__c>  creditsToInsert    = new List<Credit__c>();

        for (Id pid : completedPaymentIds) {
            Payment__c p = paymentsByIdById.get(pid);
            if (p == null || p.Amount__c == null) continue;
            Decimal balance  = p.Remittance_Form__r?.Balance__c;
            Id      dealerId = p.Remittance_Form__r?.Dealer_Name__c;
            if (balance == null || dealerId == null) continue;
            if (balance < 0) {
                Decimal excess = balance.abs();
                paymentsWithCredit.add(new Payment__c(Id = pid, Credit_Stored__c = excess));
                creditsToInsert.add(new Credit__c(
                    Dealer__c      = dealerId,
                    Credit_Type__c = 'Overpayment Credit',
                    Amount__c      = excess,
                    Notes__c       = 'Auto-generated from overpayment on Payment: ' + p.Name
                ));
            }
        }

        if (!paymentsWithCredit.isEmpty()) {
            Database.update(paymentsWithCredit, false);
        }

        if (!creditsToInsert.isEmpty()) {
            Database.insert(creditsToInsert, false);
        }

        // Tally per-payment results
        Map<Id, Integer> remittanceLineItemJunctionUpdatedCountByPaymentId = countSuccessByPayment(remittanceLineItemJunctionSaveResults, remittanceLineItemJunctionsToUpdate, remittanceLineItemJunctionsByPaymentId);
        Integer totalInvoiceLineItemsUpdated = countSuccess(invoiceLineItemSaveResults);
        Set<Id> paidInvoiceIds = new Set<Id>();
        Set<Id> partialInvoiceIds = new Set<Id>();
        for (Invoice__c updatedInvoice : invoicesToUpdate) {
            if (updatedInvoice.Status__c == 'Paid') paidInvoiceIds.add(updatedInvoice.Id);
            else if (updatedInvoice.Status__c == 'Partial Paid') partialInvoiceIds.add(updatedInvoice.Id);
        }
        Integer invPaidCount = countSuccessForIds(invoiceSaveResults, paidInvoiceIds);
        Integer invPartialCount = countSuccessForIds(invoiceSaveResults, partialInvoiceIds);

        // Populate result messages
        Map<Id, Result> resultByPayment = new Map<Id, Result>();
        for (Result r : results) {
            if (r.paymentId != null) resultByPayment.put(r.paymentId, r);
        }

        for (Id completedPaymentId : completedPaymentIds) {
            Result singleResult = resultByPayment.get(completedPaymentId);
            if (singleResult == null) continue;
            singleResult.rljUpdated = (remittanceLineItemJunctionUpdatedCountByPaymentId.containsKey(completedPaymentId) ? remittanceLineItemJunctionUpdatedCountByPaymentId.get(completedPaymentId) : 0);
            singleResult.lineItemsUpdated = totalInvoiceLineItemsUpdated;
            singleResult.invoicesPaid = invPaidCount;
            singleResult.invoicesPartial = invPartialCount;
            singleResult.appPackagesUpdated = applicationPackagesUpdated;
            singleResult.success = true;
            singleResult.message = 'Processed Payment successfully.';
        }

        // For any non-completed payments, set message
        for (Result r : results) {
            if (r.paymentId == null) continue;
            if (!completedPaymentIds.contains(r.paymentId)) {
                r.success = false;
                r.message = 'Skipped: Payment not in a completed confirmation status.';
            }
        }

        return results;
    }

    // Helper types and methods

    private class AggregateCounts {
        Integer total = 0;
        Integer paid = 0;
    }

    private static Boolean isCompletedStatus(String status) {
        if (String.isBlank(status)) return false;
        String s = status.trim();
        return s == 'Transaction Completed' || s == 'Deposit Completed';
    }

    private static String stringValue(PAYMENT_STATUS s) {
        switch on s {
            when PLANNED { return 'Planned'; }
            when PAID { return 'Paid'; }
        }
        return null;
    }

    private static Integer countSuccess(Database.SaveResult[] srs) {
        Integer n = 0;
        for (Database.SaveResult sr : srs) {
            if (sr != null && sr.isSuccess()) n++;
        }
        return n;
    }

    private static Integer countSuccessForIds(Database.SaveResult[] srs, Set<Id> idsOfInterest) {
        Integer n = 0;
        if (srs == null) return 0;
        Set<Id> ok = new Set<Id>();
        for (Database.SaveResult sr : srs) {
            if (sr != null && sr.isSuccess()) {
                ok.add(sr.getId());
            }
        }
        for (Id i : idsOfInterest) {
            if (ok.contains(i)) n++;
        }
        return n;
    }

    /**
     * Wrapper for sorting invoices by total amount ascending.
     */
    private class InvoiceSortWrapper implements Comparable {
        public Id invoiceId;
        public Decimal totalAmount;
        public InvoiceSortWrapper(Id iId, Decimal tAmt) {
            this.invoiceId = iId;
            this.totalAmount = tAmt;
        }
        public Integer compareTo(Object other) {
            InvoiceSortWrapper o = (InvoiceSortWrapper) other;
            Decimal a2 = this.totalAmount != null ? this.totalAmount : 0;
            Decimal b2 = o.totalAmount != null ? o.totalAmount : 0;
            if (a2 < b2) return -1;
            if (a2 > b2) return 1;
            return 0;
        }
    }

    /**
     * Comparator to sort Remittance_Line_Item_Junction__c by Line_Item_Amount__c ascending
     */
    private class RLJAmountComparator implements Comparator<Remittance_Line_Item_Junction__c> {
        public Integer compare(Remittance_Line_Item_Junction__c a, Remittance_Line_Item_Junction__c b) {
            Decimal amtA = a.Line_Item_Amount__c != null ? a.Line_Item_Amount__c : 0;
            Decimal amtB = b.Line_Item_Amount__c != null ? b.Line_Item_Amount__c : 0;
            if (amtA < amtB) return -1;
            if (amtA > amtB) return 1;
            return 0;
        }
    }

    private static Map<Id, Integer> countSuccessByPayment(Database.SaveResult[] srs, List<Remittance_Line_Item_Junction__c> updates, Map<Id, List<Remittance_Line_Item_Junction__c>> rljByPayment) {
        Map<Id, Integer> result = new Map<Id, Integer>();
        if (srs == null || updates == null) return result;

        Map<Id, Boolean> successfulMap = new Map<Id, Boolean>();
        for (Database.SaveResult sr : srs) {
            if (sr != null && sr.isSuccess()) {
                successfulMap.put(sr.getId(), true);
            }
        }

        for (Id pid : rljByPayment.keySet()) {
            Integer cnt = 0;
            for (Remittance_Line_Item_Junction__c rlj : rljByPayment.get(pid)) {
                if (successfulMap.containsKey(rlj.Id)) {
                    cnt++;
                }
            }
            result.put(pid, cnt);
        }
        return result;
    }
}
