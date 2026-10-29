public without sharing class ContractAdditionalOptionsController {
    // Renders the labels of the OPTIONAL/purchased add-ons of an application
    // package on page 1 of the warranty PDF (above the premium table).
    // Label-only: no prices, no money math (the add-on price is already part
    // of the rendered premium total).
    public String packageId { get; set; }

    private Boolean loaded = false;
    private Boolean hasOptions = false;
    private String optionsDisplay = '';

    public Boolean getHasOptions() {
        if (!loaded) {
            load();
        }
        return hasOptions;
    }

    public String getOptionsDisplay() {
        if (!loaded) {
            load();
        }
        return optionsDisplay;
    }

    private void load() {
        loaded = true;
        hasOptions = false;
        optionsDisplay = '';
        if (String.isBlank(packageId)) {
            return;
        }
        Id pid;
        try {
            pid = Id.valueOf(packageId);
        } catch (Exception e) {
            return;
        }

        // Resolve the dealer package the SAME way the contract PDF extension
        // and Part 3 do: the dealer package term first, then the package lookup.
        Id dpId;
        try {
            List<Application_Package__c> aps = [
                SELECT Dealer_Package__c,
                       Dealer_Package_Term__r.Dealer_Package__c
                FROM Application_Package__c
                WHERE Id = :pid
                LIMIT 1
            ];
            if (!aps.isEmpty()) {
                Application_Package__c ap = aps[0];
                if (ap.Dealer_Package_Term__r != null
                        && ap.Dealer_Package_Term__r.Dealer_Package__c != null) {
                    dpId = ap.Dealer_Package_Term__r.Dealer_Package__c;
                } else {
                    dpId = ap.Dealer_Package__c;
                }
            }
        } catch (Exception e) {
            return;
        }
        if (dpId == null) {
            return;
        }

        // Optional vs Included option names on the dealer package. A name that
        // is included anywhere in the package is coverage, not an add-on, so it
        // never prints here (Part 3 already lists the included options).
        Map<String, String> optionalNames = new Map<String, String>();
        Set<String> includedNames = new Set<String>();
        try {
            for (Dealer_Package_Option__c dpo : [
                SELECT Selection_Type__c,
                       Is_Removed__c,
                       Package_Option__r.Option__r.Name
                FROM Dealer_Package_Option__c
                WHERE Dealer_Package__c = :dpId
            ]) {
                if (dpo.Is_Removed__c == true) {
                    continue;
                }
                if (dpo.Package_Option__r == null
                        || dpo.Package_Option__r.Option__r == null
                        || String.isBlank(dpo.Package_Option__r.Option__r.Name)) {
                    continue;
                }
                String label = dpo.Package_Option__r.Option__r.Name.trim();
                String key = label.toLowerCase();
                if (dpo.Selection_Type__c == 'Optional') {
                    if (!optionalNames.containsKey(key)) {
                        optionalNames.put(key, label);
                    }
                } else if (dpo.Selection_Type__c == 'Included') {
                    includedNames.add(key);
                }
            }
        } catch (Exception e) {
            return;
        }
        if (optionalNames.isEmpty()) {
            return;
        }

        // The priced line set of the package is the purchase record: an option
        // is on the contract only when its line exists. On this org shape the
        // line carries the option text in Name, and SYSTEM_MODE is required —
        // the line fields carry no portal FLS.
        Set<String> picked = new Set<String>();
        try {
            for (Application_Package_Line_Item__c line : (List<Application_Package_Line_Item__c>) Database.query(
                    'SELECT Name FROM Application_Package_Line_Item__c' +
                    ' WHERE Application_Package__c = \'' + String.valueOf(pid) + '\'',
                    System.AccessLevel.SYSTEM_MODE)) {
                if (String.isBlank(line.Name)) {
                    continue;
                }
                String key = line.Name.trim().toLowerCase();
                if (optionalNames.containsKey(key) && !includedNames.contains(key)) {
                    picked.add(key);
                }
            }
        } catch (Exception e) {
            System.debug('ContractAdditionalOptionsController: line read failed: ' + e.getMessage());
            return;
        }
        if (picked.isEmpty()) {
            return;
        }

        List<String> display = new List<String>();
        for (String key : picked) {
            display.add(optionalNames.get(key));
        }
        display.sort();
        optionsDisplay = String.join(display, ', ');
        hasOptions = true;
    }
}