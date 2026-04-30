import { LightningElement, track } from 'lwc';

export default class DealerPortalAdmin extends LightningElement {
    @track activeTab = 'markup'; // Default active tab
    
    // Tab definitions
    tabs = [
        { label: 'Markup Management', value: 'markup', tabClass: 'tab active' },
        { label: 'User Management', value: 'users', tabClass: 'tab' },
        { label: 'Settings', value: 'settings', tabClass: 'tab' }
    ];
    
    // Handle tab click
    handleTabClick(event) {
        const selectedTab = event.currentTarget.dataset.id;
        
        // Update active tab
        this.activeTab = selectedTab;
        
        // Update tab classes
        this.tabs = this.tabs.map(tab => {
            return {
                ...tab,
                tabClass: tab.value === selectedTab ? 'tab active' : 'tab'
            };
        });
        
    }
    
    // Getters for conditional rendering
    get isMarkupTab() {
        return this.activeTab === 'markup';
    }
    
    get isUsersTab() {
        return this.activeTab === 'users';
    }
    
    get isSettingsTab() {
        return this.activeTab === 'settings';
    }
    
}