@IsTest
private class CancellationSLATrackerTest {
    
    @IsTest
    static void createsTaskForOverdueRequestAndDoesNotDuplicate() {
        App_Cancellation_Request__c req = new App_Cancellation_Request__c(
            Name = 'TEST SLA CR 001',
            Status__c = 'Pending Sales Review'
        );
        insert req;
        
        // Age the request past the 7 day SLA window
        Test.setCreatedDate(req.Id, DateTime.now().addDays(-10));
        
        Test.startTest();
        CancellationSLATracker.checkOverdueRequests();
        Test.stopTest();
        
        List<Task> slaTasks = [
            SELECT Id, WhatId, Description, Subject, Status, Priority
            FROM Task
            WHERE WhatId = :req.Id AND Subject LIKE 'SLA Breach:%'
        ];
        System.assertEquals(1, slaTasks.size(), 'One SLA task should be created for the overdue request');
        System.assertEquals(req.Id, slaTasks[0].WhatId, 'Task WhatId should reference the cancellation request');
        System.assertNotEquals(null, slaTasks[0].Description, 'Task Description should be populated');
        
        // Second run must not duplicate the open SLA task
        CancellationSLATracker.checkOverdueRequests();
        
        Integer taskCount = [SELECT COUNT() FROM Task WHERE WhatId = :req.Id AND Subject LIKE 'SLA Breach:%'];
        System.assertEquals(1, taskCount, 'Re-running the tracker should not duplicate the SLA task');
    }
    
    @IsTest
    static void scheduleDailyNeverQueuesMoreThanOneJob() {
        Test.startTest();
        CancellationSLATracker.scheduleDaily();
        // A second call must be a no-op: System.schedule would otherwise queue a duplicate job
        CancellationSLATracker.scheduleDaily();
        Test.stopTest();
        
        Integer jobCount = 0;
        for (CronTrigger ct : [SELECT Id, CronJobDetail.Name FROM CronTrigger]) {
            String jobName = ct.CronJobDetail.Name;
            if (jobName != null && jobName.startsWithIgnoreCase('Cancellation SLA Tracker')) {
                jobCount++;
            }
        }
        System.assert(jobCount <= 1, 'scheduleDaily() must never queue more than one job, found ' + jobCount);
    }
}