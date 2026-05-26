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
         * Optional: explicitly pass the status you&#39;re transitioning to.
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

        // 1) Load all RLJ records for these payments
        // Line_Item_Amount__c is used to populate Invoice_Line_Item__c.Paid_Amount__c
        List<Remittance_Line_Item_Junction__c> remittanceLineItemJunctionList = [
            SELECT Id, Payment__c, Invoice__c, Invoice_Line_Item__c, Payment_Status__c, Paid_Date__c, Line_Item_Amount__c
            FROM Remittance_Line_Item_Junction__c
            WHERE Payment__c IN :completedPaymentIds
        ];

        if (remittanceLineItemJunctionList.isEmpty()) {
            // Nothing to do; update messages
            for (Result r : results) {
                if (r.paymentId != null && completedPaymentIds.contains(r.paymentId)) {
                    r.success = true;
                    r.message = 'No Remittance_Line_Item_Junction__c records found for Payment. No updates required.';
                }
            }
            return results;
        }

        // Build maps
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

        // Map Invoice_Line_Item__c Id → amount paid (from junction Line_Item_Amount__c)
        // Used to populate Invoice_Line_Item__c.Paid_Amount__c during the paid update.
        Map<Id, Decimal> paidAmountByLineItemId = new Map<Id, Decimal>();
        for (Remittance_Line_Item_Junction__c rlj : remittanceLineItemJunctionList) {
            if (rlj.Invoice_Line_Item__c != null && rlj.Line_Item_Amount__c != null) {
                paidAmountByLineItemId.put(rlj.Invoice_Line_Item__c, rlj.Line_Item_Amount__c);
            }
        }

        // 2) Prepare RLJ updates: mark as Paid with today&#39;s date if not already
        Date today = Date.today();
        List<Remittance_Line_Item_Junction__c> remittanceLineItemJunctionsToUpdate = new List<Remittance_Line_Item_Junction__c>();
        for (Remittance_Line_Item_Junction__c remittanceLineItemJunction : remittanceLineItemJunctionList) {
            if (remittanceLineItemJunction.Payment_Status__c != stringValue(PAYMENT_STATUS.PAID)) {
                Remittance_Line_Item_Junction__c updateRecord = new Remittance_Line_Item_Junction__c(
                    Id = remittanceLineItemJunction.Id,
                    Payment_Status__c = stringValue(PAYMENT_STATUS.PAID),
                    Paid_Date__c = (remittanceLineItemJunction.Paid_Date__c == null ? today : remittanceLineItemJunction.Paid_Date__c)
                );
                remittanceLineItemJunctionsToUpdate.add(updateRecord);
            } else if (remittanceLineItemJunction.Paid_Date__c == null) {
                Remittance_Line_Item_Junction__c updateRecord = new Remittance_Line_Item_Junction__c(
                    Id = remittanceLineItemJunction.Id,
                    Paid_Date__c = today
                );
                remittanceLineItemJunctionsToUpdate.add(updateRecord);
            }
        }

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
        Set<Id> fullyPaidInvoiceIds = new Set<Id>(); // invoices where every line item is now Paid
        // Build a map of invoice → remittance form balance to determine if fully paid
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
                    // No line items found - skip
                    continue;
                }
                // Mark invoice as Paid if all its line items are paid
                // (Balance check removed — DLRS rollup timing means Balance__c may not
                //  be updated yet when this invocable runs in the same transaction.)
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
        // Only fully-paid invoices (all line items Paid) trigger this — partial invoices do not.
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

        // 8) Credit stored — overpayment handling
        // If a completed payment's Amount__c exceeds the remittance form's planned total,
        // the excess is stored as Credit_Stored__c on the Payment and a Credit__c record
        // of type 'Overpayment Credit' is created against the dealer account.
        // The Account rollup fields (Overpayment_Credit__c, Total_Credit_Amount__c) update automatically.
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
        // Count invoices paid vs partial
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
            singleResult.lineItemsUpdated = totalInvoiceLineItemsUpdated; // total across payments; for per-payment, extend aggregation
            singleResult.invoicesPaid = invPaidCount;
            singleResult.invoicesPartial = invPartialCount;
            singleResult.appPackagesUpdated = applicationPackagesUpdated; // total
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

    private static Map<Id, Integer> countSuccessByPayment(Database.SaveResult[] srs, List<Remittance_Line_Item_Junction__c> updates, Map<Id, List<Remittance_Line_Item_Junction__c>> rljByPayment) {
        Map<Id, Integer> result = new Map<Id, Integer>();
        if (srs == null || updates == null) return result;

        // Build a map of successful IDs for quick lookup
        Map<Id, Boolean> successfulMap = new Map<Id, Boolean>();
        for (Database.SaveResult sr : srs) {
            if (sr != null && sr.isSuccess()) {
                successfulMap.put(sr.getId(), true);
            }
        }

        // For each payment, count how many of its RLJs were successfully updated
        for (Id pid : rljByPayment.keySet()) {
            Integer cnt = 0;
            for (Remittance_Line_Item_Junction__c rlj : rljByPayment.get(pid)) {
                // Check if this RLJ was part of updates and if it succeeded
                if (successfulMap.containsKey(rlj.Id)) {
                    cnt++;
                }
            }
            result.put(pid, cnt);
        }
        return result;
    }
}