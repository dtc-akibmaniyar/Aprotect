/**
 * InvoiceOptionLineService
 *
 * Bills a package's priced OPTION selections on the invoice that covers the
 * package. Options live on Application_Package__c as priced Option line items
 * (Application_Package_Line_Item__c.Line_Type__c = 'Option'); this service
 * materialises them as real Invoice_Line_Item__c rows so the invoice actually
 * charges for them.
 *
 * Why this works (org facts, verified 2026-10-08):
 *   • Invoice__c.Amount__c is the running sum of its child line items'
 *     Amount__c (INV000506 / INV000507 / the INV-CWO-* repair invoices all
 *     reconcile exactly), and Invoice__c.Total_Balance_Amount__c is a formula
 *     reading Amount__c. Adding a line therefore lifts the amount owed — no
 *     code here touches Amount__c or Total_Balance_Amount__c.
 *   • Invoice_Line_Item__c.Amount__c = IF(ISBLANK(Application_Package__c),
 *     Repair_Charge_Amount__c, Application_Package__r.Contract_Cost_Price__c).
 *     So a line with Application_Package__c = null is valued from the writable
 *     Repair_Charge_Amount__c — exactly how the existing repair-invoice lines
 *     carry their charge.
 *
 * Line shape (approved design):
 *   Invoice__c              = the invoice
 *   Application_Package__c  = null   — DELIBERATE. A non-null link makes the
 *                            line's Contract_Cost_Price__c / Amount__c formulas
 *                            read the WHOLE package cost (once per line), which
 *                            the portal renderers would double count.
 *   Name / Description__c   = "<Option Name> (Optional)"
 *   Repair_Charge_Amount__c = gross = retail × (1 + Tax_Percentage__c/100),
 *                             rounded 2dp HALF_UP (mirrors PricingEngineService.money).
 *   Status__c               = 'Due'
 *
 * Amount billed per package = Σ(option line Amount__c) − Add_Ons_Price__c,
 * floored at 0: $0 / "Included" options are never charged, and a package whose
 * Add_Ons_Price__c already carries the option money is treated as billed.
 *
 * Idempotent: a line is skipped when one with the same (Invoice__c, Description__c)
 * already exists, so a re-run of the trigger and the future backfill cannot
 * double-add. seedForInvoices() is public and scoped to the invoices handed to
 * it, so the same logic can drive that backfill.
 *
 * Fix-forward only: nothing here writes to existing invoices; the trigger only
 * runs for invoices inserted after deployment.
 *
 * Apex v67 runs plain SOQL in USER mode; the portal profile has no FLS on the
 * package / line-item pricing fields, so every read and the insert are pinned
 * to SYSTEM_MODE (the same mode ApplicationSnapshotService / PricingEngineService
 * / the invoice renderers use).
 */
public without sharing class InvoiceOptionLineService {

    public static final String OPTION_LINE_TYPE = 'Option';
    public static final String OPTIONAL_SUFFIX  = ' (Optional)';
    private static final Integer SCALE = 2;

    /** Trigger entry point — bulkified. */
    public static void handleAfterInsert(List<Invoice__c> newInvoices) {
        seedForInvoices(newInvoices);
    }

    /**
     * Creates the option invoice lines for the supplied invoices. Public and
     * scoped to the invoices passed in so a later backfill can drive it.
     */
    public static void seedForInvoices(List<Invoice__c> invoices) {
        if (invoices == null || invoices.isEmpty()) {
            return;
        }

        // ── 1. Invoices that link to an application ────────────────────────
        Map<Id, Invoice__c> byId = new Map<Id, Invoice__c>();
        Set<Id> appIds = new Set<Id>();
        for (Invoice__c inv : invoices) {
            if (inv == null || inv.Id == null || inv.Application__c == null) {
                continue;
            }
            byId.put(inv.Id, inv);
            appIds.add(inv.Application__c);
        }
        if (byId.isEmpty()) {
            return;
        }

        // ── 2. The invoice's packages (SYSTEM_MODE read) ───────────────────
        Map<Id, List<Application_Package__c>> pkgsByApp =
            new Map<Id, List<Application_Package__c>>();
        Set<Id> pkgIds = new Set<Id>();
        for (Application_Package__c pkg : [
                SELECT Id, Application__c, Tax_Percentage__c, Add_Ons_Price__c
                FROM Application_Package__c
                WHERE Application__c IN :appIds
                WITH SYSTEM_MODE]) {
            if (pkg.Application__c == null) {
                continue;
            }
            if (!pkgsByApp.containsKey(pkg.Application__c)) {
                pkgsByApp.put(pkg.Application__c, new List<Application_Package__c>());
            }
            pkgsByApp.get(pkg.Application__c).add(pkg);
            pkgIds.add(pkg.Id);
        }
        if (pkgIds.isEmpty()) {
            return;
        }

        // ── 3. Their priced Option lines (SYSTEM_MODE read) ────────────────
        Map<Id, List<Application_Package_Line_Item__c>> optsByPkg =
            new Map<Id, List<Application_Package_Line_Item__c>>();
        for (Application_Package_Line_Item__c line : [
                SELECT Id, Application_Package__c, Amount__c, Description__c, Sort_Order__c
                FROM Application_Package_Line_Item__c
                WHERE Application_Package__c IN :pkgIds
                  AND Line_Type__c = :OPTION_LINE_TYPE
                WITH SYSTEM_MODE
                ORDER BY Application_Package__c, Sort_Order__c, Id]) {
            if (line.Application_Package__c == null) {
                continue;
            }
            if (!optsByPkg.containsKey(line.Application_Package__c)) {
                optsByPkg.put(line.Application_Package__c,
                    new List<Application_Package_Line_Item__c>());
            }
            optsByPkg.get(line.Application_Package__c).add(line);
        }
        if (optsByPkg.isEmpty()) {
            return;
        }

        // ── 4. Idempotency — descriptions already present per invoice ──────
        Map<Id, Set<String>> existingByInvoice = new Map<Id, Set<String>>();
        for (Invoice_Line_Item__c li : [
                SELECT Invoice__c, Description__c
                FROM Invoice_Line_Item__c
                WHERE Invoice__c IN :byId.keySet()
                WITH SYSTEM_MODE]) {
            if (li.Invoice__c == null) {
                continue;
            }
            if (!existingByInvoice.containsKey(li.Invoice__c)) {
                existingByInvoice.put(li.Invoice__c, new Set<String>());
            }
            existingByInvoice.get(li.Invoice__c).add(normalize(li.Description__c));
        }

        // ── 5. Build the chargeable option lines ───────────────────────────
        List<Invoice_Line_Item__c> toInsert = new List<Invoice_Line_Item__c>();
        Set<String> batchKeys = new Set<String>();

        for (Invoice__c inv : byId.values()) {
            List<Application_Package__c> pkgs = pkgsByApp.get(inv.Application__c);
            if (pkgs == null) {
                continue;
            }
            for (Application_Package__c pkg : pkgs) {
                List<Application_Package_Line_Item__c> optLines = optsByPkg.get(pkg.Id);
                if (optLines == null || optLines.isEmpty()) {
                    continue;
                }

                // Unbilled = Σ(retail) − Add_Ons_Price__c, floored at 0.
                Decimal sumRetail = 0;
                for (Application_Package_Line_Item__c line : optLines) {
                    if (line.Amount__c != null && line.Amount__c > 0) {
                        sumRetail += line.Amount__c;
                    }
                }
                Decimal addOns = pkg.Add_Ons_Price__c != null ? pkg.Add_Ons_Price__c : 0;
                if (sumRetail - addOns <= 0) {
                    continue; // already billed, or nothing chargeable
                }

                Decimal rate = pkg.Tax_Percentage__c != null ? pkg.Tax_Percentage__c : 0;

                for (Application_Package_Line_Item__c line : optLines) {
                    // Included / $0 options are not chargeable.
                    if (line.Amount__c == null || line.Amount__c <= 0) {
                        continue;
                    }

                    String label = optionLabel(line.Description__c);
                    String key   = inv.Id + '|' + normalize(label);
                    if (batchKeys.contains(key)) {
                        continue;
                    }
                    Set<String> existing = existingByInvoice.get(inv.Id);
                    if (existing != null && existing.contains(normalize(label))) {
                        continue;
                    }
                    batchKeys.add(key);

                    toInsert.add(new Invoice_Line_Item__c(
                        Invoice__c              = inv.Id,
                        Application_Package__c  = null,               // deliberate — see class doc
                        Name                    = label,
                        Description__c          = label,
                        Status__c               = 'Due',
                        Repair_Charge_Amount__c = money(line.Amount__c * (1 + rate / 100))
                    ));
                }
            }
        }

        if (toInsert.isEmpty()) {
            return;
        }
        // Tolerate a bad row without aborting the invoice insert that triggered us.
        Database.insert(toInsert, false, System.AccessLevel.SYSTEM_MODE);
    }

    /** "<Option Name> (Optional)" — the line's Name and Description. */
    public static String optionLabel(String optionName) {
        String base = String.isNotBlank(optionName) ? optionName.trim() : 'Option';
        if (base.endsWith(OPTIONAL_SUFFIX)) {
            return base;
        }
        return base + OPTIONAL_SUFFIX;
    }

    /** Case/space-insensitive key for idempotency and renderer de-duplication. */
    public static String normalize(String value) {
        return value == null ? '' : value.trim().toLowerCase();
    }

    /** Currency rounding: 2dp, half-up (decision D5 — mirrors PricingEngineService.money). */
    public static Decimal money(Decimal value) {
        if (value == null) {
            return 0;
        }
        return value.setScale(SCALE, System.RoundingMode.HALF_UP);
    }
}