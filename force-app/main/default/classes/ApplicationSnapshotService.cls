/**
 * ApplicationSnapshotService
 *
 * P4 snapshot writer (change-implementation plan §04.1 / §11 P4 [A]; design
 * doc §7.1). The engine's commit path calls this service to persist the
 * resolved quote as explicit Application_Package_Line_Item__c rows so that
 * stored = displayed = invoiced holds by construction (§07.3): every total on
 * the Application_Package__c is the sum of persisted lines.
 *
 * What it writes, per engine QuoteResult:
 *   - one row per engine QuoteLine (Base_Coverage, fee lines, option lines)
 *     with Amount__c = pre-tax line total, Taxable__c, per-line Tax_Amount__c
 *     (informational allocation), Quantity__c, Sort_Order__c and the
 *     provenance lookups (Package_Term__c / Package_Option__c /
 *     Vehicle_Schedule__c / Vehicle_Schedule_Member__c).
 *   - one Tax line (Line_Type__c = Tax) carrying the single engine-computed
 *     tax amount (D5: taxable-subtotal × region rate, half-up), so that
 *     sum(Amount of non-Tax lines) = Contract_Premium_Price_Without_Tax__c and
 *     sum(Amount of ALL lines) = Contract_Premium_Price__c (with-tax total).
 *
 * Idempotency: the snapshot is a delete-then-insert for the package inside one
 * transaction — re-committing the same context converges to the same rows
 * (no duplicates on re-run). It is safe to call on every engine-priced save.
 *
 * Gating: rows are written only when the Line_Item_Snapshot_Enabled__c flag is
 * on (toggle T5) AND the record was priced by the engine (Priced_By_Engine__c
 * true, dual-writer guard — the create-time flow never touches these rows).
 * While T5 is off this service is inert: legacy behaviour is unchanged.
 *
 * Callers: DealerPortalController save seams after a successful insert/update
 * of an engine-priced Application_Package__c. Never throws on snapshot
 * failures — the quote save itself must not fail because of the audit write.
 */
public without sharing class ApplicationSnapshotService {

    /** Engine line type constants (mirror PricingEngineService). */
    public static final String LT_TAX = 'Tax';

    /**
     * Persist the engine's resolved line set for one Application_Package.
     * @param applicationPackageId the engine-priced package (must exist)
     * @param result the engine QuoteResult whose lines/totals are to be stored
     * @return true when rows were written; false when skipped (flag off,
     *         missing context, engine failure) — never throws for those.
     */
    public static Boolean writeSnapshot(Id applicationPackageId,
                                        PricingEngineService.QuoteResult result) {
        if (applicationPackageId == null || result == null) {
            return false;
        }
        if (!PortalFeatureFlagService.isLineItemSnapshotEnabled()) {
            return false;
        }
        if (!result.success || result.lines == null) {
            return false;
        }

        try {
            // Idempotency: replace the previous snapshot for this package.
            // P7-g (2026-09-10): system-mode read + delete. API v67 runs plain
            // SOQL/DML in USER mode by default and the Dealer Portal Profile
            // carries no FLS/CRUD on the line-item object (D7) — a portal save
            // would otherwise silently skip the snapshot here.
            List<Application_Package_Line_Item__c> priorRows = [
                SELECT Id FROM Application_Package_Line_Item__c
                WHERE Application_Package__c = :applicationPackageId
                WITH SYSTEM_MODE
            ];
            delete as system priorRows;

            List<Application_Package_Line_Item__c> rows =
                new List<Application_Package_Line_Item__c>();

            Integer sortOrder = 0;
            for (PricingEngineService.QuoteLine line : result.lines) {
                rows.add(toLineItem(applicationPackageId, line, sortOrder++));
            }

            // Tax line: the single authoritative tax amount (D5), so the full
            // line set sums to the stored with-tax total.
            if (result.taxAmount != null && result.taxAmount != 0) {
                Application_Package_Line_Item__c taxRow =
                    new Application_Package_Line_Item__c(
                        Application_Package__c = applicationPackageId,
                        Name = 'Tax',
                        Line_Type__c = LT_TAX,
                        Description__c = taxDescription(result.taxRate),
                        Amount__c = PricingEngineService.money(result.taxAmount),
                        Taxable__c = false,
                        Tax_Amount__c = 0,
                        Quantity__c = 1,
                        Sort_Order__c = sortOrder
                    );
                rows.add(taxRow);
            }

            if (!rows.isEmpty()) {
                // SYSTEM_MODE: line-item fields carry no Dealer Portal Profile
                // FLS yet (unit-a deferral) — the engine writes in system mode
                // exactly as it writes the package money fields.
                Database.insert(rows, System.AccessLevel.SYSTEM_MODE);
            }
            return true;
        } catch (Exception e) {
            // Audit write must never break the quote save.
            System.debug('ApplicationSnapshotService: snapshot skipped for '
                + applicationPackageId + ': ' + e.getMessage());
            return false;
        }
    }

    /**
     * Convenience for the controller seams: run the engine stamp + snapshot in
     * one call when the caller already holds the in-memory package. Called
     * AFTER the package insert/update succeeded (package has an Id).
     */
    public static Boolean snapshotEnginePriced(Application_Package__c pkg,
                                               PricingEngineService.QuoteResult result) {
        if (pkg == null || pkg.Id == null) {
            return false;
        }
        if (pkg.Priced_By_Engine__c != true) {
            return false;
        }
        return writeSnapshot(pkg.Id, result);
    }

    /**
     * Submit-time backfill (P4 [L] server half): before an invoice is created
     * for a submitted application, every engine-priced active package must
     * carry its line-item snapshot so stored = displayed = invoiced holds for
     * quotes created while the snapshot flag was off (pre-T5 population).
     *
     * Recomputes the engine result from the STORED context (deterministic R6:
     * same inputs -> same payload) and writes the line set idempotently. When
     * line items already exist the call is a no-op; legacy packages and the
     * flag-off org state are never touched. Never throws.
     */
    public static Boolean backfillIfMissing(Application_Package__c pkg) {
        if (pkg == null || pkg.Id == null) {
            return false;
        }
        if (!PortalFeatureFlagService.isLineItemSnapshotEnabled()) {
            return false;
        }
        if (pkg.Priced_By_Engine__c != true) {
            return false;
        }
        try {
            Integer existing = [SELECT COUNT() FROM Application_Package_Line_Item__c
                                WHERE Application_Package__c = :pkg.Id
                                WITH SYSTEM_MODE];
            if (existing > 0) {
                return true; // already snapshotted
            }
            PricingEngineService.QuoteRequest req = new PricingEngineService.QuoteRequest();
            req.dealerTermId = pkg.Dealer_Package_Term__c;
            req.dealerPackageId = pkg.Dealer_Package__c;
            req.dealerId = pkg.Dealer__c;
            req.applicationPackageId = pkg.Id;
            if (String.isNotBlank(pkg.Application__c)) {
                for (Application__c app : [
                    SELECT Vehicle__c FROM Application__c WHERE Id = :pkg.Application__c
                    WITH SYSTEM_MODE LIMIT 1
                ]) {
                    req.vehicleId = app.Vehicle__c;
                }
            }
            if (pkg.Dealer_Price_Override__c != null) {
                req.dealerPriceOverride = pkg.Dealer_Price_Override__c;
            }
            if (pkg.Waive_Premium_Fee__c == true) {
                req.waivePremiumFee = true;
            }
            PricingEngineService.QuoteResult result =
                PricingEngineService.applyEnginePricing(pkg, req);
            return writeSnapshot(pkg.Id, result);
        } catch (Exception e) {
            System.debug('ApplicationSnapshotService: backfill skipped for '
                + pkg.Id + ': ' + e.getMessage());
            return false;
        }
    }

    // ------------------------------------------------------------------
    // Mapping helpers
    // ------------------------------------------------------------------

    private static Application_Package_Line_Item__c toLineItem(
            Id pkgId, PricingEngineService.QuoteLine line, Integer sortOrder) {
        Application_Package_Line_Item__c row = new Application_Package_Line_Item__c(
            Application_Package__c = pkgId,
            Name = cleanName(line.description, line.lineType),
            Line_Type__c = line.lineType,
            Description__c = line.description,
            Amount__c = PricingEngineService.money(line.amount),
            Taxable__c = line.taxable == true,
            Tax_Amount__c = PricingEngineService.money(line.taxAmount),
            Quantity__c = line.quantity != null ? line.quantity : 1,
            Sort_Order__c = sortOrder
        );
        if (line.provenanceTermId != null) {
            row.Package_Term__c = line.provenanceTermId;
        }
        if (line.provenanceOptionId != null) {
            row.Package_Option__c = line.provenanceOptionId;
        }
        if (line.provenanceScheduleId != null) {
            row.Vehicle_Schedule__c = line.provenanceScheduleId;
        }
        if (line.provenanceMemberId != null) {
            row.Vehicle_Schedule_Member__c = line.provenanceMemberId;
        }
        return row;
    }

    private static String cleanName(String description, String lineType) {
        String base = String.isNotBlank(description)
            ? description
            : (String.isNotBlank(lineType) ? lineType : 'Line item');
        return base.length() > 60 ? base.substring(0, 60) : base;
    }

    private static String taxDescription(Decimal taxRate) {
        String pct = taxRate != null
            ? String.valueOf(PricingEngineService.money(taxRate)) : '0';
        return 'Tax (' + pct + '%)';
    }
}