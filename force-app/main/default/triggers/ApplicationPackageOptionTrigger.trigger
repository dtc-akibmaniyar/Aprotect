trigger ApplicationPackageOptionTrigger on Application_Package_Option__c (after insert, after update, after delete) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert || Trigger.isUpdate) {
            ApplicationPackageOptionHelper.updateParentAddOns(Trigger.new, Trigger.oldMap);
        }
        if (Trigger.isDelete) {
            ApplicationPackageOptionHelper.updateParentAddOns(Trigger.old, null);
        }
    }
}