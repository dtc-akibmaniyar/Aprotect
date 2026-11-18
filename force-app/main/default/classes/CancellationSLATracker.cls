public class CancellationSLATracker implements Schedulable {
    
    public void execute(SchedulableContext sc) {
        checkOverdueRequests();
    }
    
    public static void checkOverdueRequests() {
        DateTime sevenDaysAgo = DateTime.now().addDays(-7);
        
        List<App_Cancellation_Request__c> overdueRequests = [
            SELECT Id, Name, Status__c, OwnerId, CreatedDate
            FROM App_Cancellation_Request__c
            WHERE Status__c IN ('Pending Sales Review', 'Pending Accounting Review')
            AND CreatedDate <= :sevenDaysAgo
        ];
        
        if (overdueRequests.isEmpty()) return;
        
        // Check for existing open SLA tasks to avoid duplicates
        Set<Id> requestIds = new Set<Id>();
        for (App_Cancellation_Request__c req : overdueRequests) {
            requestIds.add(req.Id);
        }
        
        Set<Id> alreadyTasked = new Set<Id>();
        for (Task t : [
            SELECT WhatId FROM Task 
            WHERE WhatId IN :requestIds 
            AND Subject LIKE 'SLA Breach:%'
            AND Status != 'Completed'
        ]) {
            alreadyTasked.add(t.WhatId);
        }
        
        List<Task> tasksToCreate = new List<Task>();
        for (App_Cancellation_Request__c req : overdueRequests) {
            if (req.Id == null) {
                System.debug(LoggingLevel.WARN, 'CancellationSLATracker: skipped overdue request with null Id (' + req.Name + ')');
                continue;
            }
            if (alreadyTasked.contains(req.Id)) continue;
            
            Task t = new Task();
            t.Subject = 'SLA Breach: Cancellation Request ' + req.Name + ' pending > 7 days (' + req.Status__c + ')';
            t.Priority = 'High';
            t.Status = 'Open';
            t.OwnerId = req.OwnerId;
            t.ActivityDate = Date.today();
            t.WhatId = req.Id;
            t.Description = 'This cancellation request has been pending for more than 7 days. Please review and take action.';
            
            // Skip any row whose required inputs are missing instead of letting the insert fail
            if (t.WhatId == null || t.OwnerId == null || t.Subject == null) {
                System.debug(LoggingLevel.WARN, 'CancellationSLATracker: skipped SLA task for request ' 
                    + req.Id + ' (' + req.Name + ') - required field missing');
                continue;
            }
            tasksToCreate.add(t);
        }
        
        if (!tasksToCreate.isEmpty()) {
            // Partial-save insert: one bad row must not abort the whole batch
            Database.SaveResult[] results = Database.insert(tasksToCreate, false);
            Integer createdCount = 0;
            for (Integer i = 0; i < results.size(); i++) {
                Database.SaveResult sr = results[i];
                if (sr.isSuccess()) {
                    createdCount++;
                } else {
                    Id failedRequestId = (i < tasksToCreate.size()) ? tasksToCreate[i].WhatId : null;
                    String errorText = '';
                    for (Database.Error err : sr.getErrors()) {
                        errorText += err.getStatusCode() + ': ' + err.getMessage() + '; ';
                    }
                    System.debug(LoggingLevel.ERROR, 'CancellationSLATracker: failed to create SLA task for cancellation request ' 
                        + failedRequestId + ' - ' + errorText);
                }
            }
            System.debug(LoggingLevel.INFO, 'CancellationSLATracker: created ' + createdCount 
                + ' of ' + tasksToCreate.size() + ' SLA task(s)');
        }
    }
    
    // Schedules the tracker to run daily at 08:00 org time (America/New_York).
    // Idempotent: System.schedule creates a NEW job on every call, so check for an
    // existing CronTrigger for this tracker first and skip instead of double-scheduling.
    public static void scheduleDaily() {
        String cronExp = '0 0 8 * * ?';
        String jobName = 'Cancellation SLA Tracker - Apex';
        
        for (CronTrigger existing : [
            SELECT Id, State, CronExpression, NextFireTime, CronJobDetail.Name
            FROM CronTrigger
        ]) {
            String existingName = existing.CronJobDetail.Name;
            if (existingName != null && existingName.startsWithIgnoreCase('Cancellation SLA Tracker')) {
                System.debug(LoggingLevel.WARN, 'CancellationSLATracker.scheduleDaily(): job already scheduled ('
                    + existingName + ', state=' + existing.State + ', cron=' + existing.CronExpression
                    + ') - skipping to avoid a duplicate');
                return;
            }
        }
        
        String jobId = System.schedule(jobName, cronExp, new CancellationSLATracker());
        System.debug(LoggingLevel.INFO, 'CancellationSLATracker.scheduleDaily(): scheduled "'
            + jobName + '" id=' + jobId + ' cron=' + cronExp);
    }
}