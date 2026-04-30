({
    doInit : function(component, event, helper) {
        var lwc = component.find("lwc");
        if(lwc){
            lwc.refresh();
        }
    },
    
    handleRefresh: function(component, event, helper) {
        $A.get('e.force:refreshView').fire();
    },
    handleManualRefresh: function(component, event, helper) {
        var lwc = component.find("lwcComponent");
        if(lwc){
            lwc.refresh();
        }
    },
})