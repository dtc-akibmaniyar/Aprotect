/**
 * Auto Generated and Deployed by the Declarative Lookup Rollup Summaries Tool package (dlrs)
 **/
trigger dlrs_Remittance_Line_Item_JunctionTrigger on Remittance_Line_Item_Junction__c
    (before delete, before insert, before update, after delete, after insert, after undelete, after update)
{
    dlrs.RollupService.triggerHandler(Remittance_Line_Item_Junction__c.SObjectType);
}