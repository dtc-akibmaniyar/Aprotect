public class DealerPortalRemittanceHandler {
    
    @AuraEnabled(cacheable=true)
    public static RemittanceFormData getRemittanceForm(List<String> applicationIds) {
        try {
            RemittanceFormData result = new RemittanceFormData();
            
            // Query all Application records with Remittance Form lookup
            List<Application__c> applications = [
                SELECT Id, Remittance_Form__c, Remittance_Form__r.Id, Remittance_Form__r.Name
                FROM Application__c
                WHERE Id IN :applicationIds
                LIMIT 1000
            ];
            
            List<RemittanceFormRecord> recordList = new List<RemittanceFormRecord>();
            
            for (Application__c app : applications) {
                if (app.Remittance_Form__c != null && app.Remittance_Form__r != null) {
                    // Remittance form exists
                    RemittanceFormRecord record = new RemittanceFormRecord();
                    record.Id = app.Remittance_Form__r.Id;
                    record.Name = app.Remittance_Form__r.Name;
                    record.recordUrl = '/dealerportal/s/detail/' + app.Remittance_Form__r.Id;
                    recordList.add(record);
                }
            }
            
            result.remittanceFormList = recordList;
            result.hasRecords = !recordList.isEmpty();
            result.showCreateButton = recordList.isEmpty();
            result.errorMessage = null;
            
            return result;
            
        } catch (Exception e) {
            RemittanceFormData errorResult = new RemittanceFormData();
            errorResult.errorMessage = 'Error loading remittance form: ' + e.getMessage();
            errorResult.remittanceFormList = new List<RemittanceFormRecord>();
            errorResult.hasRecords = false;
            errorResult.showCreateButton = false;
            
            System.debug('DealerPortalRemittanceHandler error: ' + e.getMessage());
            return errorResult;
        }
    }
    
    // Wrapper class for selected packages
    public class SelectedPackage {
        @AuraEnabled 
        public String packageId { get; set; }
        @AuraEnabled 
        public String applicationId { get; set; }
    }
    
    @AuraEnabled
    public static OperationResult createRemittanceForm(List<String> applicationIds) {
        try {
            // Query applications to get dealer information
            List<Application__c> applicationsWithDealer = [
                SELECT Id, Dealer_Name__r.Name, Dealer_Name__c
                FROM Application__c
                WHERE Id IN :applicationIds
                LIMIT 1
            ];
            
            String dealerName = '';
            String dealerId = '';
            if (!applicationsWithDealer.isEmpty() && applicationsWithDealer[0].Dealer_Name__r != null) {
                dealerName = applicationsWithDealer[0].Dealer_Name__r.Name;
                dealerId = applicationsWithDealer[0].Dealer_Name__c;
            }
            
            // Create ONE new Remittance Form record for all applications
            Remittance_Form__c newRemittanceForm = new Remittance_Form__c();
            newRemittanceForm.RecordTypeId = Schema.SObjectType.Remittance_Form__c.getRecordTypeInfosByDeveloperName().get('Dealer_Remittance').getRecordTypeId();
            newRemittanceForm.Receiver_Name__c = 'A-Protect';
            newRemittanceForm.Payer_Name__c = dealerName;
            newRemittanceForm.Dealer_Name__c = dealerId;
            newRemittanceForm.Status__c = 'Open';
            insert newRemittanceForm;
            
            // Update all Application records to link the new Remittance Form
            List<Application__c> applicationsToUpdate = new List<Application__c>();
            for (String appId : applicationIds) {
                Application__c app = new Application__c();
                app.Id = appId;
                app.Remittance_Form__c = newRemittanceForm.Id;
                applicationsToUpdate.add(app);
            }
            update applicationsToUpdate;
            
            // Query invoices for these applications and link them to the new remittance form.
            // ORDER BY CreatedDate DESC so the most-recent invoice per application is first.
            List<Invoice__c> allCandidateInvoices = [
                SELECT Id, Name, Application__c
                FROM Invoice__c
                WHERE Application__c IN :applicationIds
                AND Status__c != 'Paid'
                ORDER BY CreatedDate DESC
            ];

            // Deduplicate by Application + Name: multiple failed remittance-form attempts
            // can leave several Invoice records with the same Name for the same Application.
            // Key = AppId + Name so that genuinely different invoices on the same application
            // (e.g. a second invoice for additional packages) are still included, while true
            // duplicates (same App + same Name) are reduced to the most-recent copy only.
            // This also preserves partial-payment scenarios where an older invoice still has
            // unpaid line items — as long as it has a different Name it will not be dropped.
            Map<String, Invoice__c> seenInvoices = new Map<String, Invoice__c>();
            for (Invoice__c inv : allCandidateInvoices) {
                String key = inv.Application__c + '|' + inv.Name;
                if (!seenInvoices.containsKey(key)) {
                    seenInvoices.put(key, inv);
                }
            }
            List<Invoice__c> invoicesToUpdate = seenInvoices.values();

            for (Invoice__c invoice : invoicesToUpdate) {
                invoice.Remittance_Form__c = newRemittanceForm.Id;
            }
            if (!invoicesToUpdate.isEmpty()) {
                update invoicesToUpdate;

                List<Id> invoiceIds = new List<Id>();
                for (Invoice__c invoice : invoicesToUpdate) {
                    invoiceIds.add(invoice.Id);
                }

                // Query unpaid line items for the deduplicated invoices only
                List<Invoice_Line_Item__c> lineItems = [
                    SELECT Id, Invoice__c, Contract_Cost_Price__c
                    FROM Invoice_Line_Item__c
                    WHERE Invoice__c IN :invoiceIds
                    AND Status__c != 'Paid'
                ];

                // Guard against duplicate junctions (e.g. if this runs more than once)
                Set<Id> existingLineItemIds = new Set<Id>();
                for (Remittance_Line_Item_Junction__c existing : [
                    SELECT Invoice_Line_Item__c
                    FROM Remittance_Line_Item_Junction__c
                    WHERE Remittance_Form__c = :newRemittanceForm.Id
                    AND Invoice_Line_Item__c != null
                ]) {
                    existingLineItemIds.add(existing.Invoice_Line_Item__c);
                }

                List<Remittance_Line_Item_Junction__c> newJunctionRecords = new List<Remittance_Line_Item_Junction__c>();
                for (Invoice_Line_Item__c lineItem : lineItems) {
                    if (!existingLineItemIds.contains(lineItem.Id)) {
                        newJunctionRecords.add(new Remittance_Line_Item_Junction__c(
                            Remittance_Form__c   = newRemittanceForm.Id,
                            Invoice__c           = lineItem.Invoice__c,
                            Invoice_Line_Item__c = lineItem.Id,
                            Line_Item_Amount__c  = lineItem.Contract_Cost_Price__c,
                            Payment_Status__c    = 'Planned'
                        ));
                    }
                }
                if (!newJunctionRecords.isEmpty()) {
                    insert newJunctionRecords;
                }
            }
            
            return new OperationResult(true, 'Remittance Form created successfully for all selected applications', newRemittanceForm.Id);
            
        } catch (Exception e) {
            System.debug('DealerPortalRemittanceHandler createRemittanceForm error: ' + e.getMessage());
            return new OperationResult(false, 'Error creating remittance form: ' + e.getMessage());
        }
    }

        // Map record type developer/name to UI chip label
    private static String mapRecordTypeToLabel(String developerName, String nameVal) {
        if (developerName == 'Extended_Limited_Warranty' || nameVal == 'Extended Limited Warranty') {
            return 'Extended Warranty';
        }
        if (developerName == 'Loan_Protection' || nameVal == 'Loan Protection') {
            return 'Loan Protection';
        }
        if (developerName == 'GAP_Coverage' || nameVal == 'GAP Coverage') {
            return 'GAP Coverage';
        }
        if (developerName == 'Tire_Rim_Protection_Plan' || nameVal == 'Tire & Rim Protection Plan') {
            return 'Tire & Rim Protection';
        }
        return null;
    }
    
    @AuraEnabled
    public static BulkConfirmationData getBulkConfirmationData(List<String> applicationIds) {
        try {
            BulkConfirmationData result = new BulkConfirmationData();
            List<BulkConfirmationRecord> confirmationList = new List<BulkConfirmationRecord>();
            
            // Query all applications with their packages and fields needed for dynamic display
            List<Application__c> applications = [
                SELECT Id,
                       Name,
                       Customer_Name__r.name,
                       Vehicle_VIN__c,
                       Vehicle_Year__c,
                       Vehicle_Make__c,
                       Vehicle_Model__c,
                       Vehicle_Trim__c,
                       (SELECT Id, RecordType.DeveloperName, RecordType.Name, Name,
                               Contract_Cost_Price__c, Contract_Cost_Price_Without_Tax__c,
                               Tax_Amount_Cost__c, Tax_Percentage__c
                        FROM Application_Packages__r
                        WHERE Active__c = true ORDER BY RecordType.Name ASC )
                FROM Application__c
                WHERE Id IN :applicationIds
                LIMIT 1000
            ];
            
            // Build confirmation data
            for (Application__c app : applications) {
                BulkConfirmationRecord record = new BulkConfirmationRecord();
                record.applicationId = app.Id;
                record.applicationNumber = app.Name != null ? app.Name : app.Id;

                // Dynamic fields to match ApplicationsListView shaping
                record.customerName = app.Customer_Name__r.name;
                // Build vehicle display as Year/Make/Model/Trim (skip nulls)
                List<String> parts = new List<String>();
                if (app.Vehicle_Year__c != null) parts.add(String.valueOf(app.Vehicle_Year__c));
                if (String.isNotBlank(app.Vehicle_Make__c)) parts.add(app.Vehicle_Make__c);
                if (String.isNotBlank(app.Vehicle_Model__c)) parts.add(app.Vehicle_Model__c);
                if (String.isNotBlank(app.Vehicle_Trim__c)) parts.add(app.Vehicle_Trim__c);
                record.vehicleName = String.join(parts, '/');
                record.vehicleVin = app.Vehicle_VIN__c;

                // Build packages list with pricing information
                List<PackageItem> packageList = new List<PackageItem>();
                Decimal applicationTax = 0;
                Decimal applicationTaxPercentage = 0;
                
                for (Application_Package__c pkg : app.Application_Packages__r) {
                    String label = (pkg.RecordType != null ? pkg.RecordType.Name : null);

                    PackageItem packageItem = new PackageItem();
                    packageItem.id = pkg.Id;
                    packageItem.name = label;
                    packageItem.isSelected = true; // Select all by default
                    packageItem.priceWithoutTax = pkg.Contract_Cost_Price_Without_Tax__c;
                    packageItem.priceWithTax = pkg.Contract_Cost_Price__c;
                    packageItem.taxAmount = pkg.Tax_Amount_Cost__c;
                    packageItem.taxPercentage = pkg.Tax_Percentage__c;
                    
                    // Capture tax info from first package (same for all under this application)
                    if (applicationTax == 0 && pkg.Tax_Amount_Cost__c != null) {
                        applicationTax = pkg.Tax_Amount_Cost__c;
                    }
                    if (applicationTaxPercentage == 0 && pkg.Tax_Percentage__c != null) {
                        applicationTaxPercentage = pkg.Tax_Percentage__c;
                    }
                    
                    packageList.add(packageItem);
                }
                
                record.packageList = packageList;
                record.applicationTaxAmount = applicationTax;
                record.applicationTaxPercentage = applicationTaxPercentage;
                confirmationList.add(record);
            }
            
            result.confirmationList = confirmationList;
            return result;
            
        } catch (Exception e) {
            BulkConfirmationData errorResult = new BulkConfirmationData();
            errorResult.confirmationList = new List<BulkConfirmationRecord>();
            errorResult.errorMessage = 'Error loading confirmation data: ' + e.getMessage();
            
            System.debug('DealerPortalRemittanceHandler getBulkConfirmationData error: ' + e.getMessage());
            return errorResult;
        }
    }
    
    @AuraEnabled
    public static OperationResult deleteRemittanceForm(String applicationId, String remittanceFormId) {
        try {
            // Delete the Remittance Form record
            delete new Remittance_Form__c(Id = remittanceFormId);
            
            // Clear the lookup on the Application record
            Application__c app = new Application__c();
            app.Id = applicationId;
            app.Remittance_Form__c = null;
            
            update app;
            
            return new OperationResult(true, 'Remittance Form deleted successfully');
            
        } catch (Exception e) {
            System.debug('DealerPortalRemittanceHandler deleteRemittanceForm error: ' + e.getMessage());
            return new OperationResult(false, 'Error deleting remittance form: ' + e.getMessage());
        }
    }
    
    
    // Simple wrapper class for operation results
    public class OperationResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public String remittanceFormId;
        
        public OperationResult(Boolean success, String message) {
            this.success = success;
            this.message = message;
            this.remittanceFormId = null;
        }
        
        public OperationResult(Boolean success, String message, String remittanceFormId) {
            this.success = success;
            this.message = message;
            this.remittanceFormId = remittanceFormId;
        }
    }
    
    // Wrapper class for remittance form record
    public class RemittanceFormRecord {
        @AuraEnabled public String Id;
        @AuraEnabled public String Name;
        @AuraEnabled public String recordUrl;
    }
    
    // Wrapper class for response data
    public class RemittanceFormData {
        @AuraEnabled public List<RemittanceFormRecord> remittanceFormList;
        @AuraEnabled public Boolean hasRecords;
        @AuraEnabled public Boolean showCreateButton;
        @AuraEnabled public String errorMessage;
    }
    
    // Wrapper class for bulk confirmation record
    public class BulkConfirmationRecord {
        @AuraEnabled public String applicationId;
        @AuraEnabled public String applicationNumber;
        // Dynamic display fields
        @AuraEnabled public String customerName;
        @AuraEnabled public String vehicleName;
        @AuraEnabled public String vehicleVin;
        @AuraEnabled public List<PackageItem> packageList;
        @AuraEnabled public Decimal applicationTaxAmount;
        @AuraEnabled public Decimal applicationTaxPercentage;
    }
    
    // Wrapper class for package item
    public class PackageItem {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public Boolean isSelected;
        @AuraEnabled public Decimal priceWithoutTax;
        @AuraEnabled public Decimal priceWithTax;
        @AuraEnabled public Decimal taxAmount;
        @AuraEnabled public Decimal taxPercentage;
    }
    
    // Wrapper class for bulk confirmation data
    public class BulkConfirmationData {
        @AuraEnabled public List<BulkConfirmationRecord> confirmationList;
        @AuraEnabled public String errorMessage;
    }

    // Download Remittance Form as PDF
    @AuraEnabled
    public static PDFDownloadResponse downloadRemittanceFormPDF(String remittanceFormId) {
        try {
            System.debug('=== downloadRemittanceFormPDF START ===');
            System.debug('Input remittanceFormId: ' + remittanceFormId);
            
            PDFDownloadResponse response = new PDFDownloadResponse();
            
            // Query Remittance Form for name
            List<Remittance_Form__c> remittanceForms = [
                SELECT Id, Name
                FROM Remittance_Form__c
                WHERE Id = :remittanceFormId
                LIMIT 1
            ];
            
            System.debug('Query result count: ' + remittanceForms.size());
            if (!remittanceForms.isEmpty()) {
                System.debug('Remittance Form Found - Id: ' + remittanceForms[0].Id + ', Name: ' + remittanceForms[0].Name);
            }
            
            if (remittanceForms.isEmpty()) {
                System.debug('ERROR: Remittance Form not found for Id: ' + remittanceFormId);
                response.success = false;
                response.message = 'Remittance Form not found';
                return response;
            }

            Remittance_Form__c form = remittanceForms[0];
            System.debug('Processing form: ' + form.Name);
            
            // Generate PDF using PageReference
            PageReference pdfPage = new PageReference('/apex/RemittanceFormPDF?id=' + remittanceFormId);
            System.debug('PDF Page Reference created: ' + pdfPage.getUrl());
            
            Blob pdfBlob;
            
            try {
                pdfBlob = pdfPage.getContentAsPDF();
                System.debug('PDF Blob generated successfully, Size: ' + pdfBlob.size() + ' bytes');
            } catch (Exception e) {
                System.debug('ERROR during PDF generation: ' + e.getMessage());
                System.debug('Stack trace: ' + e.getStackTraceString());
                response.success = false;
                response.message = 'Error generating PDF: ' + e.getMessage();
                return response;
            }
            
            // Encode to base64
            String base64PDF = EncodingUtil.base64Encode(pdfBlob);
            System.debug('Base64 encoding completed, Encoded length: ' + base64PDF.length());
            
            response.success = true;
            response.pdfData = base64PDF;
            response.fileName = 'RemittanceForm_' + form.Name + '_' + DateTime.now().format('yyyyMMdd_HHmmss') + '.pdf';
            
            System.debug('Response prepared - Success: ' + response.success + ', FileName: ' + response.fileName);
            System.debug('=== downloadRemittanceFormPDF END ===');
            
            return response;
            
        } catch (Exception e) {
            System.debug('ERROR in downloadRemittanceFormPDF: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            
            PDFDownloadResponse errorResponse = new PDFDownloadResponse();
            errorResponse.success = false;
            errorResponse.message = 'Error generating PDF: ' + e.getMessage();
            System.debug('Error Response: ' + errorResponse.message);
            return errorResponse;
        }
    }
    
    // Wrapper class for PDF download response
    public class PDFDownloadResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public String pdfData;
        @AuraEnabled public String fileName;
    }
}