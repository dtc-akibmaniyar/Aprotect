trigger BrochureFileVisibilityTrigger on ContentDocumentLink (before insert) {
    // Auto-set visibility to AllUsers when files are linked to Brochure_Document__c records
    // This ensures portal users can access brochure files
    Set<Id> linkedIds = new Set<Id>();
    for (ContentDocumentLink cdl : Trigger.new) {
        if (cdl.LinkedEntityId != null) {
            linkedIds.add(cdl.LinkedEntityId);
        }
    }
    
    if (linkedIds.isEmpty()) return;
    
    // Check which LinkedEntityIds are Brochure_Document__c records
    Set<Id> brochureDocIds = new Set<Id>();
    for (Id lid : linkedIds) {
        if (lid.getSObjectType() == Brochure_Document__c.SObjectType) {
            brochureDocIds.add(lid);
        }
    }
    
    if (brochureDocIds.isEmpty()) return;
    
    for (ContentDocumentLink cdl : Trigger.new) {
        if (brochureDocIds.contains(cdl.LinkedEntityId)) {
            cdl.Visibility = 'AllUsers';
        }
    }
}