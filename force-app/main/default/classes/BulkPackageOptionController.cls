public class BulkPackageOptionController {
    
    public List<PackageOptionWrapper> packageOptionList { get; set; }
    public Integer selectedRowIndex { get; set; }
    
    public BulkPackageOptionController() {
        packageOptionList = new List<PackageOptionWrapper>();
        addRow();
    }
    
    // Wrapper class to hold package option and additional information
    public class PackageOptionWrapper {
        public Package_Option__c packageOption { get; set; }
        public String selectionType { get; set; }
        public Integer index { get; set; }
        
        public PackageOptionWrapper(Integer idx) {
            packageOption = new Package_Option__c();
            selectionType = '';
            index = idx;
        }
    }
    
    // Add new row
    public void addRow() {
        packageOptionList.add(new PackageOptionWrapper(packageOptionList.size()));
    }
    
    // Remove row
    public void removeRow() {
        if(selectedRowIndex != null && selectedRowIndex < packageOptionList.size()) {
            packageOptionList.remove(selectedRowIndex);
            // Update indices
            for(Integer i = 0; i < packageOptionList.size(); i++) {
                packageOptionList[i].index = i;
            }
        }
    }
    
    // Get Selection Type options
    public List<SelectOption> getSelectionTypeOptions() {
        List<SelectOption> options = new List<SelectOption>();
        options.add(new SelectOption('--None--', '--None--'));
        options.add(new SelectOption('Type1', 'Type 1'));
        options.add(new SelectOption('Type2', 'Type 2'));
        // Add more options as needed
        return options;
    }
    
    // Save records
    public void saveRecords() {
        try {
            List<Package_Option__c> recordsToInsert = new List<Package_Option__c>();
            
            for(PackageOptionWrapper pow : packageOptionList) {
                if(pow.packageOption.Option__c != null && pow.packageOption.Price__c != null) {
                    // Add any additional field mappings here
                    recordsToInsert.add(pow.packageOption);
                }
            }
            
            if(!recordsToInsert.isEmpty()) {
                insert recordsToInsert;
                ApexPages.addMessage(new ApexPages.Message(
                    ApexPages.Severity.CONFIRM,
                    'Successfully saved ' + recordsToInsert.size() + ' records.'
                ));
                
                // Reset the list after successful save
                packageOptionList = new List<PackageOptionWrapper>();
                addRow();
            }
            
        } catch(Exception e) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                'Error: ' + e.getMessage()
            ));
        }
    }
}