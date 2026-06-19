public class CommissionCalculationHandler {

    // Default config values if Package fields are null
    private static final Decimal DEFAULT_THRESHOLD = 0.15;
    private static final Decimal DEFAULT_RESERVE_PCT = 0.50;
    private static final Decimal DEFAULT_COMM_RATE = 0.20;

    public static void calculate(List<Application_Package__c> records) {
        // Step 1: Collect related record IDs
        Set<Id> packageTermIds = new Set<Id>();
        Set<Id> dealerPkgTermIds = new Set<Id>();
        Set<Id> dealerPkgIds = new Set<Id>();
        Set<Id> packageIds = new Set<Id>();

        for (Application_Package__c ap : records) {
            if (ap.Package_Term__c != null) packageTermIds.add(ap.Package_Term__c);
            if (ap.Dealer_Package_Term__c != null) dealerPkgTermIds.add(ap.Dealer_Package_Term__c);
            if (ap.Dealer_Package__c != null) dealerPkgIds.add(ap.Dealer_Package__c);
            if (ap.Package__c != null) packageIds.add(ap.Package__c);
        }

        // Step 2: Query related data in bulk
        Map<Id, Package_Term__c> packageTermMap = new Map<Id, Package_Term__c>(
            [SELECT Id, Price__c, Package__c FROM Package_Term__c WHERE Id IN :packageTermIds]
        );

        // Collect package IDs from Package_Term records too
        for (Package_Term__c pt : packageTermMap.values()) {
            if (pt.Package__c != null) packageIds.add(pt.Package__c);
        }

        Map<Id, Package__c> packageMap = new Map<Id, Package__c>(
            [SELECT Id, Discount_Threshold_Pct__c, Reserve_Pct__c, Reserve_Floor__c, Commission_Rate_Pct__c
             FROM Package__c WHERE Id IN :packageIds]
        );

        Map<Id, Dealer_Package_Term__c> dptMap = new Map<Id, Dealer_Package_Term__c>(
            [SELECT Id, Discount_Value__c, Discount_Type__c, Markup__c, Markup_Type__c, Sales_Rep_Incentive__c
             FROM Dealer_Package_Term__c WHERE Id IN :dealerPkgTermIds]
        );

        // Step 3: Calculate for each record
        for (Application_Package__c ap : records) {
            // Get related records
            Package_Term__c pt = ap.Package_Term__c != null ? packageTermMap.get(ap.Package_Term__c) : null;
            Dealer_Package_Term__c dpt = ap.Dealer_Package_Term__c != null ? dptMap.get(ap.Dealer_Package_Term__c) : null;

            // Get wholesale price
            Decimal wholesalePrice = (pt != null && pt.Price__c != null) ? pt.Price__c : 0;
            ap.Wholesale_Price__c = wholesalePrice;

            if (wholesalePrice == 0) {
                // Avoid divide-by-zero; set all output fields to 0
                ap.Dealer_Discount_Amount__c = 0;
                ap.Sales_Rep_Incentive__c = 0;
                ap.Total_Discount_Amount__c = 0;
                ap.Total_Discount_Pct__c = 0;
                ap.Aprotect_Net__c = 0;
                ap.Reserve_Amount__c = 0;
                ap.Commission_Base__c = 0;
                ap.Commission_Rate_Pct__c = 0;
                ap.Commission_Amount__c = 0;
                ap.CRM_Charge__c = 0;
                ap.Owed_To_Dealer__c = 0;
                continue;
            }

            // Get Package config
            Id pkgId = (pt != null && pt.Package__c != null) ? pt.Package__c : ap.Package__c;
            Package__c pkg = (pkgId != null) ? packageMap.get(pkgId) : null;

            // Percent fields in Salesforce are stored as e.g. 15.0 for 15%, so divide by 100
            Decimal discThreshold = DEFAULT_THRESHOLD;
            Decimal reservePct = DEFAULT_RESERVE_PCT;
            Decimal commRate = DEFAULT_COMM_RATE;

            if (pkg != null) {
                if (pkg.Discount_Threshold_Pct__c != null) discThreshold = pkg.Discount_Threshold_Pct__c / 100;
                if (pkg.Reserve_Pct__c != null) reservePct = pkg.Reserve_Pct__c / 100;
                if (pkg.Commission_Rate_Pct__c != null) commRate = pkg.Commission_Rate_Pct__c / 100;
            }

            Decimal reserveFloor = (pkg != null) ? pkg.Reserve_Floor__c : null;

            // Step 2: Calculate dealer discount amount
            Decimal discountValue = (dpt != null && dpt.Discount_Value__c != null) ? dpt.Discount_Value__c : 0;
            String discountType = (dpt != null && dpt.Discount_Type__c != null) ? dpt.Discount_Type__c : '$';
            Decimal dealerDiscountAmt;
            if (discountType == '%') {
                dealerDiscountAmt = wholesalePrice * (discountValue / 100);
            } else {
                dealerDiscountAmt = discountValue;
            }

            // Step 3: Get markup amount
            Decimal markupValue = (dpt != null && dpt.Markup__c != null) ? dpt.Markup__c : 0;
            String markupType = (dpt != null && dpt.Markup_Type__c != null) ? dpt.Markup_Type__c : '$';
            Decimal markupAmt;
            if (markupType == '%') {
                markupAmt = wholesalePrice * (markupValue / 100);
            } else {
                markupAmt = markupValue;
            }

            // Step 4: Get sales rep incentive
            Decimal salesRepIncentive = (dpt != null && dpt.Sales_Rep_Incentive__c != null) ? dpt.Sales_Rep_Incentive__c : 0;

            // Step 5: Commission calculation
            Decimal totalDiscountAmt = dealerDiscountAmt + salesRepIncentive;
            Decimal totalDiscountPct = totalDiscountAmt / wholesalePrice;
            Decimal aprotectNet = wholesalePrice - totalDiscountAmt;

            // Step 6: Reserve floor auto-calculation
            if (reserveFloor == null) {
                reserveFloor = reservePct * (wholesalePrice - (wholesalePrice * discThreshold));
            }

            // Step 7: Threshold check
            Decimal reserve;
            Decimal commissionBase;
            if (totalDiscountPct <= discThreshold) {
                reserve = aprotectNet * reservePct;
                commissionBase = aprotectNet * (1 - reservePct);
            } else {
                reserve = reserveFloor;
                commissionBase = Math.max(0, aprotectNet - reserveFloor);
            }

            Decimal commission = commissionBase * commRate;

            // Step 8: Dealer ledger
            Decimal crmCharge = (wholesalePrice - dealerDiscountAmt) + markupAmt;
            Decimal owedToDealer = markupAmt + salesRepIncentive;

            // Write all values - Total_Discount_Pct__c is a Percent field, store as percentage value
            ap.Dealer_Discount_Amount__c = dealerDiscountAmt;
            ap.Sales_Rep_Incentive__c = salesRepIncentive;
            ap.Total_Discount_Amount__c = totalDiscountAmt;
            ap.Total_Discount_Pct__c = totalDiscountPct * 100; // Store as percent (e.g. 15.0 for 15%)
            ap.Aprotect_Net__c = aprotectNet;
            ap.Reserve_Amount__c = reserve;
            ap.Commission_Base__c = commissionBase;
            ap.Commission_Rate_Pct__c = commRate * 100; // Store as percent
            ap.Commission_Amount__c = commission;
            ap.CRM_Charge__c = crmCharge;
            ap.Owed_To_Dealer__c = owedToDealer;
        }
    }
}