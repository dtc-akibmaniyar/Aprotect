/**
 * Batch Job to mark invoices as Overdue
 * Marks all invoices with Status__c = 'Due' and Invoice_Due_Date__c < Today as 'Overdue'
 * 
 * Usage:
 * - Schedule via Setup > Scheduled Actions > Scheduled Jobs
 * - Or execute manually: Database.executeBatch(new InvoiceOverdueMarkingBatch(), 200);
 */
public class InvoiceOverdueMarkingBatch implements Database.Batchable<SObject>, Schedulable {
    
    /**
     * Schedulable execute method - allows this to be scheduled as a job
     * @param context SchedulableContext
     */
    public void execute(SchedulableContext context) {
        Database.executeBatch(new InvoiceOverdueMarkingBatch(), 200);
    }
    
    /**
     * Batchable start method - queries all due invoices with passed due dates
     * @param bc BatchableContext
     * @return Database.QueryLocator for invoices to process
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Query invoices with Status__c = 'Due' and Invoice_Due_Date__c < Today
        String query = 'SELECT Id, Status__c, Invoice_Due_Date__c ' +
                       'FROM Invoice__c ' +
                       'WHERE Status__c = \'Due\' ' +
                       'AND Invoice_Due_Date__c < TODAY ' +
                       'ORDER BY Invoice_Due_Date__c ASC';
        
        System.debug('InvoiceOverdueMarkingBatch - Query: ' + query);
        return Database.getQueryLocator(query);
    }
    
    /**
     * Batchable execute method - updates invoices to Overdue status
     * @param bc BatchableContext
     * @param invoices List of Invoice__c records to process
     */
    public void execute(Database.BatchableContext bc, List<Invoice__c> invoices) {
        if (invoices == null || invoices.isEmpty()) {
            System.debug('InvoiceOverdueMarkingBatch - No invoices to process');
            return;
        }
        
        System.debug('InvoiceOverdueMarkingBatch - Processing ' + invoices.size() + ' invoices');
        
        // Mark all invoices as Overdue
        for (Invoice__c invoice : invoices) {
            invoice.Status__c = 'Overdue';
        }
        
        // Update all invoices
        try {
            update invoices;
            System.debug('InvoiceOverdueMarkingBatch - Successfully marked ' + invoices.size() + ' invoices as Overdue');
        } catch (DmlException e) {
            System.debug('InvoiceOverdueMarkingBatch - Error updating invoices: ' + e.getMessage());
            System.debug('InvoiceOverdueMarkingBatch - Stack Trace: ' + e.getStackTraceString());
        }
    }
    
    /**
     * Batchable finish method - runs after batch completes
     * @param bc BatchableContext
     */
    public void finish(Database.BatchableContext bc) {
        System.debug('InvoiceOverdueMarkingBatch - Batch job completed');
        
        // Get batch job info
        AsyncApexJob job = [SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems 
                            FROM AsyncApexJob 
                            WHERE Id = :bc.getJobId()];
        
        System.debug('InvoiceOverdueMarkingBatch - Job Status: ' + job.Status);
        System.debug('InvoiceOverdueMarkingBatch - Items Processed: ' + job.JobItemsProcessed);
        System.debug('InvoiceOverdueMarkingBatch - Total Items: ' + job.TotalJobItems);
        System.debug('InvoiceOverdueMarkingBatch - Errors: ' + job.NumberOfErrors);
    }
}