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
            if (alreadyTasked.contains(req.Id)) continue;
            
            Task t = new Task();
            t.Subject = 'SLA Breach: Cancellation Request ' + req.Name + ' pending > 7 days (' + req.Status__c + ')';
            t.Priority = 'High';
            t.Status = 'Open';
            t.OwnerId = req.OwnerId;
            t.ActivityDate = Date.today();
            t.WhatId = req.Id;
            t.Description = 'This cancellation request has been pending for more than 7 days. Please review and take action.';
            tasksToCreate.add(t);
        }
        
        if (!tasksToCreate.isEmpty()) {
            insert tasksToCreate;
        }
    }
    
    // Call this to schedule: runs daily at 8 AM
    public static void scheduleDaily() {
        String cronExp = '0 0 8 * * ?';
        System.schedule('Cancellation SLA Tracker - Daily', cronExp, new CancellationSLATracker());
    }
}