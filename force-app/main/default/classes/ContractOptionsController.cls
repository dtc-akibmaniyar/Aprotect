public without sharing class ContractOptionsController {
    public class OptRow {
        public String label { get; set; }
        public String inclusion { get; set; }
        public String exclusion { get; set; }
        public Boolean hasExclusion { get; set; }
        public Boolean hasInclusion { get; set; }
    }

    public String packageId { get; set; }

    private List<OptRow> cachedRows;

    public List<OptRow> getRows() {
        if (cachedRows == null) {
            load();
        }
        return cachedRows;
    }

    // Runs without sharing: this controller only reads dealer-package option
    // configuration (parts text) for the contract PDF. With sharing enabled the
    // dealer-portal / community running user could not see the configuration
    // objects, so PART 3 rendered with the intro paragraph and no option rows
    // while the same page rendered all rows for an internal admin user.
    private void load() {
        cachedRows = new List<OptRow>();
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
        // does: the dealer package term first (engine-priced packages carry only
        // the term link), then the package's own dealer package lookup.
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
            System.debug('ContractOptionsController: package lookup failed: ' + e.getMessage());
            return;
        }
        if (dpId == null) {
            return;
        }

        Set<String> seen = new Set<String>();
        try {
            for (Dealer_Package_Option__c opt : [
                SELECT Option__r.Name, Inclusion__c, Exclusion__c
                FROM Dealer_Package_Option__c
                WHERE Dealer_Package__c = :dpId
                  AND Selection_Type__c = 'Included'
                  AND (Is_Removed__c = false OR Is_Removed__c = null)
                ORDER BY Option__r.Name
            ]) {
                String label = (opt.Option__r != null && opt.Option__r.Name != null)
                    ? opt.Option__r.Name : 'Option';
                if (label == 'Air Conditoning') {
                    label = 'Air Conditioning';
                }
                if (!seen.add(label)) {
                    continue;
                }
                OptRow row = new OptRow();
                row.label = label;
                row.inclusion = opt.Inclusion__c;
                row.exclusion = opt.Exclusion__c;
                row.hasInclusion = String.isNotBlank(opt.Inclusion__c);
                row.hasExclusion = String.isNotBlank(opt.Exclusion__c);
                cachedRows.add(row);
            }
        } catch (Exception e) {
            System.debug('ContractOptionsController: option read failed: ' + e.getMessage());
        }
    }
}