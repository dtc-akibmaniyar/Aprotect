public with sharing class AllocationRemittanceHandler {

    /**
     * Computes the display price for an Application Package (cost/base price).
     */
    private static Decimal getDisplayPrice(Application_Package__c pkg) {
        return pkg.Contract_Cost_Price__c != null ? pkg.Contract_Cost_Price__c : 0;
    }

    /**
     * Returns the pre-tax display price for an Application Package.
     */
    private static Decimal getDisplayPriceWithoutTax(Application_Package__c pkg) {
        Decimal totalPrice = pkg.Contract_Cost_Price__c != null ? pkg.Contract_Cost_Price__c : 0;
        Decimal taxAmt = pkg.Tax_Amount__c != null ? pkg.Tax_Amount__c : 0;
        return totalPrice - taxAmt;
    }

    /**
     * Returns the tax amount for display purposes.
     */
    private static Decimal getDisplayTaxAmount(Application_Package__c pkg) {
        return pkg.Tax_Amount__c != null ? pkg.Tax_Amount__c : 0;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Get confirmation/preview data filtered by selected service types
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static AllocationConfirmationData getAllocationConfirmationData(
        List<String> applicationIds,
        List<String> selectedServiceTypes
    ) {
        try {
            AllocationConfirmationData result = new AllocationConfirmationData();
            List<AllocationApplicationRecord> confirmationList = new List<AllocationApplicationRecord>();

            List<Application__c> applications = [
                SELECT Id,
                       Name,
                       Customer_Name__r.Name,
                       Vehicle_VIN__c,
                       Vehicle_Year__c,
                       Vehicle_Make__c,
                       Vehicle_Model__c,
                       Vehicle_Trim__c,
                       (SELECT Id, RecordType.DeveloperName, RecordType.Name,
                               Contract_Cost_Price__c,
                               Tax_Amount__c, Tax_Percentage__c
                        FROM Application_Packages__r
                        WHERE Active__c = true
                        AND RecordType.DeveloperName IN :selectedServiceTypes
                        ORDER BY RecordType.Name ASC)
                FROM Application__c
                WHERE Id IN :applicationIds
                LIMIT 1000
            ];

            for (Application__c app : applications) {
                if (app.Application_Packages__r.isEmpty()) continue;

                AllocationApplicationRecord record = new AllocationApplicationRecord();
                record.applicationId  = app.Id;
                record.applicationNumber = app.Name != null ? app.Name : app.Id;
                record.customerName   = app.Customer_Name__r != null ? app.Customer_Name__r.Name : '';

                List<String> parts = new List<String>();
                if (app.Vehicle_Year__c   != null)            parts.add(String.valueOf(app.Vehicle_Year__c));
                if (String.isNotBlank(app.Vehicle_Make__c))   parts.add(app.Vehicle_Make__c);
                if (String.isNotBlank(app.Vehicle_Model__c))  parts.add(app.Vehicle_Model__c);
                if (String.isNotBlank(app.Vehicle_Trim__c))   parts.add(app.Vehicle_Trim__c);
                record.vehicleName = String.join(parts, '/');
                record.vehicleVin  = app.Vehicle_VIN__c;

                List<AllocationLineItem> lineItems = new List<AllocationLineItem>();
                for (Application_Package__c pkg : app.Application_Packages__r) {
                    AllocationLineItem li = new AllocationLineItem();
                    li.packageId        = pkg.Id;
                    li.serviceName      = pkg.RecordType != null ? pkg.RecordType.Name : '';
                    li.priceWithoutTax  = getDisplayPriceWithoutTax(pkg);
                    li.priceWithTax     = getDisplayPrice(pkg);
                    li.taxAmount        = getDisplayTaxAmount(pkg);
                    li.taxPercentage    = pkg.Tax_Percentage__c;
                    lineItems.add(li);
                }

                record.lineItems = lineItems;
                confirmationList.add(record);
            }

            result.confirmationList = confirmationList;
            return result;

        } catch (Exception e) {
            AllocationConfirmationData err = new AllocationConfirmationData();
            err.confirmationList = new List<AllocationApplicationRecord>();
            err.errorMessage = 'Error loading confirmation data: ' + e.getMessage();
            System.debug('AllocationRemittanceHandler.getAllocationConfirmationData error: ' + e.getMessage());
            return err;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Get all eligible (unpaid) applications for a dealer, filtered by service types
    // Used by the Create Allocation Remittance screen flow (step 3)
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static AllocationConfirmationData getApplicationsByDealer(
        String       dealerId,
        List<String> selectedServiceTypes,
        String       searchTerm,
        Integer      pageOffset
    ) {
        try {
            AllocationConfirmationData result = new AllocationConfirmationData();
            List<AllocationApplicationRecord> appList = new List<AllocationApplicationRecord>();

            if (String.isBlank(dealerId) || selectedServiceTypes == null || selectedServiceTypes.isEmpty()) {
                result.confirmationList = appList;
                result.hasMore = false;
                return result;
            }

            final Integer PAGE_SIZE = 20;
            Integer offset = (pageOffset != null && pageOffset > 0) ? pageOffset : 0;

            // Build dynamic query so the LIKE clause is only added when a search term exists
            String soql =
                'SELECT Id, Name, Customer_Name__r.Name, ' +
                '       Vehicle_VIN__c, Vehicle_Year__c, Vehicle_Make__c, ' +
                '       Vehicle_Model__c, Vehicle_Trim__c, ' +
                '       (SELECT RecordType.DeveloperName FROM Application_Packages__r ' +
                '        WHERE Active__c = true ' +
                '        AND RecordType.DeveloperName IN :selectedServiceTypes) ' +
                'FROM Application__c ' +
                'WHERE Dealer_Name__c = :dealerId ' +
                'AND Payment_Status__c != \'Paid\' ' +
                'AND Application_Status__c = \'Submitted\' ' +
                'AND Id IN (' +
                '    SELECT Application__c FROM Application_Package__c ' +
                '    WHERE Active__c = true ' +
                '    AND RecordType.DeveloperName IN :selectedServiceTypes' +
                ') ';

            String likePattern;
            if (String.isNotBlank(searchTerm)) {
                likePattern = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
                soql += 'AND (Name LIKE :likePattern OR Customer_Name__r.Name LIKE :likePattern) ';
            }

            soql += 'ORDER BY CreatedDate DESC LIMIT :PAGE_SIZE OFFSET :offset';

            List<Application__c> applications = Database.query(soql);

            for (Application__c app : applications) {
                AllocationApplicationRecord record = new AllocationApplicationRecord();
                record.applicationId     = app.Id;
                record.applicationNumber = app.Name != null ? app.Name : app.Id;
                record.customerName      = app.Customer_Name__r != null ? app.Customer_Name__r.Name : '';

                List<String> parts = new List<String>();
                if (app.Vehicle_Year__c   != null)            parts.add(String.valueOf(app.Vehicle_Year__c));
                if (String.isNotBlank(app.Vehicle_Make__c))   parts.add(app.Vehicle_Make__c);
                if (String.isNotBlank(app.Vehicle_Model__c))  parts.add(app.Vehicle_Model__c);
                if (String.isNotBlank(app.Vehicle_Trim__c))   parts.add(app.Vehicle_Trim__c);
                record.vehicleName = String.join(parts, ' ');
                record.vehicleVin  = app.Vehicle_VIN__c;
                record.lineItems   = new List<AllocationLineItem>();

                Set<String> stSet = new Set<String>();
                for (Application_Package__c pkg : app.Application_Packages__r) {
                    if (pkg.RecordType != null && String.isNotBlank(pkg.RecordType.DeveloperName)) {
                        stSet.add(pkg.RecordType.DeveloperName);
                    }
                }
                record.serviceTypes = new List<String>(stSet);

                appList.add(record);
            }

            // Fetch unpaid invoices for the returned apps, ordered by due date
            List<Id> fetchedAppIds = new List<Id>();
            for (AllocationApplicationRecord r : appList) fetchedAppIds.add(r.applicationId);

            Map<String, Invoice__c> invoiceByApp = new Map<String, Invoice__c>();
            for (Invoice__c inv : [
                SELECT Id, Application__c, Status__c, Invoice_Due_Date__c
                FROM Invoice__c
                WHERE Application__c IN :fetchedAppIds
                AND Status__c != 'Paid'
                ORDER BY Invoice_Due_Date__c ASC NULLS LAST
            ]) {
                String appId = inv.Application__c;
                if (!invoiceByApp.containsKey(appId)) {
                    invoiceByApp.put(appId, inv);
                }
            }

            for (AllocationApplicationRecord r : appList) {
                Invoice__c inv = invoiceByApp.get(r.applicationId);
                if (inv != null) {
                    r.invoiceStatus  = inv.Status__c;
                    r.invoiceDueDate = inv.Invoice_Due_Date__c;
                    r.invoiceDueDays = inv.Invoice_Due_Date__c != null
                        ? inv.Invoice_Due_Date__c.daysBetween(Date.today())
                        : null;
                }
            }

            appList.sort(); // sorts by invoiceDueDate ASC via Comparable

            result.confirmationList = appList;
            result.hasMore          = (applications.size() == PAGE_SIZE);
            return result;

        } catch (Exception e) {
            AllocationConfirmationData err = new AllocationConfirmationData();
            err.confirmationList = new List<AllocationApplicationRecord>();
            err.hasMore          = false;
            err.errorMessage = 'Error loading dealer applications: ' + e.getMessage();
            System.debug('AllocationRemittanceHandler.getApplicationsByDealer error: ' + e.getMessage());
            return err;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Create Allocation Remittance with junction records for selected services only
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static OperationResult createAllocationRemittanceForm(
        List<String> applicationIds,
        List<String> selectedServiceTypes
    ) {
        try {
            List<Application__c> apps = [
                SELECT Id, Dealer_Name__r.Name, Dealer_Name__c
                FROM Application__c
                WHERE Id IN :applicationIds
                LIMIT 1
            ];

            String dealerName = '';
            String dealerId   = '';
            if (!apps.isEmpty() && apps[0].Dealer_Name__r != null) {
                dealerName = apps[0].Dealer_Name__r.Name;
                dealerId   = apps[0].Dealer_Name__c;
            }

            // Build semi-colon separated multi-select value for Services_To_Pay__c
            String servicesToPay = String.join(selectedServiceTypes, ';');

            // ── Pre-flight: gather line items BEFORE creating the form ──────────
            List<Invoice__c> invoices = [
                SELECT Id
                FROM Invoice__c
                WHERE Application__c IN :applicationIds
                AND Status__c != 'Paid'
            ];

            List<Invoice_Line_Item__c> eligibleLineItems = new List<Invoice_Line_Item__c>();

            if (!invoices.isEmpty()) {
                List<Id> invoiceIds = new List<Id>();
                for (Invoice__c inv : invoices) invoiceIds.add(inv.Id);

                eligibleLineItems = [
                    SELECT Id, Invoice__c, Application_Package__c,
                           Contract_Cost_Price__c
                    FROM Invoice_Line_Item__c
                    WHERE Invoice__c IN :invoiceIds
                    AND Status__c != 'Paid'
                    AND Application_Package__r.RecordType.DeveloperName IN :selectedServiceTypes
                ];
            }

            // Abort before creating anything if there are truly no unpaid line items
            if (eligibleLineItems.isEmpty()) {
                return new OperationResult(false,
                    'No unpaid invoice line items found for the selected services.');
            }

            // Delete stale Planned junctions for these line items so previous
            // remittance attempts do not block or duplicate the new form.
            // Paid junctions are preserved.
            Set<Id> eligibleLineItemIds = new Set<Id>();
            for (Invoice_Line_Item__c li : eligibleLineItems) eligibleLineItemIds.add(li.Id);

            List<Remittance_Line_Item_Junction__c> staleJunctions = [
                SELECT Id
                FROM Remittance_Line_Item_Junction__c
                WHERE Invoice_Line_Item__c IN :eligibleLineItemIds
                AND Payment_Status__c = 'Planned'
            ];
            if (!staleJunctions.isEmpty()) delete staleJunctions;

            // ── Create the Allocation Remittance form ───────────────────────────
            Remittance_Form__c remittanceForm = new Remittance_Form__c(
                RecordTypeId  = Schema.SObjectType.Remittance_Form__c
                                    .getRecordTypeInfosByDeveloperName()
                                    .get('Allocation_Remittance')
                                    .getRecordTypeId(),
                Receiver_Name__c  = 'A-Protect',
                Payer_Name__c     = dealerName,
                Dealer_Name__c    = dealerId,
                Status__c         = 'Open',
                Services_To_Pay__c = servicesToPay
            );
            insert remittanceForm;

            // Link invoices to the remittance form
            for (Invoice__c inv : invoices) {
                inv.Remittance_Form__c = remittanceForm.Id;
            }
            update invoices;

            // Insert junctions for all eligible line items using cost prices
            List<Remittance_Line_Item_Junction__c> junctions = new List<Remittance_Line_Item_Junction__c>();
            for (Invoice_Line_Item__c li : eligibleLineItems) {
                Decimal displayPrice = li.Contract_Cost_Price__c != null ? li.Contract_Cost_Price__c : 0;
                junctions.add(new Remittance_Line_Item_Junction__c(
                    Remittance_Form__c    = remittanceForm.Id,
                    Invoice__c            = li.Invoice__c,
                    Invoice_Line_Item__c  = li.Id,
                    Line_Item_Amount__c   = displayPrice,
                    Payment_Status__c     = 'Planned'
                ));
            }
            insert junctions;

            // Associate all selected applications to the remittance form
            List<Application__c> appsToLink = new List<Application__c>();
            for (String appId : applicationIds) {
                appsToLink.add(new Application__c(
                    Id                 = appId,
                    Remittance_Form__c = remittanceForm.Id
                ));
            }
            if (!appsToLink.isEmpty()) {
                Database.update(appsToLink, false);
            }

            return new OperationResult(true, 'Allocation Remittance Form created successfully', remittanceForm.Id);

        } catch (Exception e) {
            System.debug('AllocationRemittanceHandler.createAllocationRemittanceForm error: ' + e.getMessage());
            return new OperationResult(false, 'Error creating Allocation Remittance Form: ' + e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Wrapper classes
    // ─────────────────────────────────────────────────────────────────────────
    public class OperationResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String  message;
        @AuraEnabled public String  remittanceFormId;

        public OperationResult(Boolean success, String message) {
            this.success = success;
            this.message = message;
        }

        public OperationResult(Boolean success, String message, String remittanceFormId) {
            this.success         = success;
            this.message         = message;
            this.remittanceFormId = remittanceFormId;
        }
    }

    public class AllocationConfirmationData {
        @AuraEnabled public List<AllocationApplicationRecord> confirmationList;
        @AuraEnabled public String  errorMessage;
        @AuraEnabled public Boolean hasMore; // true when another page of results exists
    }

    public class AllocationApplicationRecord implements Comparable {
        @AuraEnabled public String  applicationId;
        @AuraEnabled public String  applicationNumber;
        @AuraEnabled public String  customerName;
        @AuraEnabled public String  vehicleName;
        @AuraEnabled public String  vehicleVin;
        @AuraEnabled public List<AllocationLineItem> lineItems;
        @AuraEnabled public List<String> serviceTypes; // DeveloperNames of services on this app
        @AuraEnabled public String  invoiceStatus;
        @AuraEnabled public Date    invoiceDueDate;
        @AuraEnabled public Integer invoiceDueDays;   // positive = overdue, 0 = today, negative = days remaining

        public Integer compareTo(Object other) {
            AllocationApplicationRecord o = (AllocationApplicationRecord) other;
            if (this.invoiceDueDate == null && o.invoiceDueDate == null) return 0;
            if (this.invoiceDueDate == null) return 1;
            if (o.invoiceDueDate == null) return -1;
            return this.invoiceDueDate < o.invoiceDueDate ? -1 : (this.invoiceDueDate > o.invoiceDueDate ? 1 : 0);
        }
    }

    public class AllocationLineItem {
        @AuraEnabled public String  packageId;
        @AuraEnabled public String  serviceName;
        @AuraEnabled public Decimal priceWithoutTax;
        @AuraEnabled public Decimal priceWithTax;
        @AuraEnabled public Decimal taxAmount;
        @AuraEnabled public Decimal taxPercentage;
    }
}