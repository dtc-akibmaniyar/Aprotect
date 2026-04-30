({
    doInit: function(component, event, helper) {
        var flow = component.find('allocationFlow');
        flow.startFlow('Create_Allocation_Remittance');
    },

    handleStatusChange: function(component, event, helper) {
        if (event.getParam('status') === 'FINISHED') {
            component.set('v.showFlow', false);
            var closeEvent = $A.get('e.force:closeQuickAction');
            if (closeEvent) {
                closeEvent.fire();
            }
            var navEvent = $A.get('e.force:navigateToObjectHome');
            navEvent.setParams({ scope: 'Remittance_Form__c' });
            navEvent.fire();
        }
    },

    closeFlowModal: function(component, event, helper) {
        component.set('v.showFlow', false);
        var closeEvent = $A.get('e.force:closeQuickAction');
        if (closeEvent) {
            closeEvent.fire();
        }
        var navEvent = $A.get('e.force:navigateToObjectHome');
        navEvent.setParams({ scope: 'Remittance_Form__c' });
        navEvent.fire();
    }
})