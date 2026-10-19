/**
 * PricingEngineService
 *
 * The single server-side pricing computation for the Aprotect dealer-portal
 * transformation (change-implementation plan §04.1 / §11 P3; design doc §7.1).
 *
 * Computes the complete quote price server-side for one context:
 *
 *   1. Load context  — dealer Account (tax region + premium-fee gate/override),
 *      vehicle, dealer package + dealer term (wholesale anchor + dealer-local
 *      markup/discount), master package.
 *   2. Resolve schedule lines — premium tier / diesel / commercial surcharge /
 *      powersports adjustment / T&R category via VehicleScheduleResolver (R1–R6),
 *      dealer override (R5) already applied by the resolver for premium fees.
 *   3. Build the line set — Base_Coverage (dealer term retail, or the pre-tax
 *      Dealer_Price_Override__c), fee lines, option lines (optional selections
 *      at dealer retail), all carried as taxable lines; no client recalc.
 *   4. Compute tax once — taxable subtotal x Tax__c region rate, half-up to 2dp
 *      (decision D5); per-line Tax_Amount__c derived for the payload.
 *   5. Return the payload / stamp the engine-owned summary fields.
 *
 * Tax-symmetry guarantee (plan §07.3, success criterion 3): the without-tax
 * total = sum of every non-tax line (fees INCLUDED), the tax line is computed
 * once over that taxable subtotal, and with-tax = without-tax + tax. The
 * invariant without-tax = with-tax − tax therefore holds for every mix of
 * premium/diesel/commercial/powersports/T&R fees and options — including the
 * pre-tax dealer override — with 0 variance.
 *
 * ORG FACT (corrected from plan §07.1): Application_Package__c carries ten
 * FORMULA fields (Contract_Premium_Price__c / _Without_Tax__c, Tax_Amount__c,
 * Dealer_Package_Retail_Price__c, Add_Ons_Retail_Price__c, Contract_Cost_Price__c /
 * _Without_Tax__c, Tax_Amount_Cost__c, Package_Record_Type__c — and previously the
 * double-tax "Total Package Price" formula, deleted in P3 unit d). The engine
 * therefore writes the STORED INPUTS those formulas read
 * (Dealer_Package_Price__c, Dealer_Markup__c, Add_Ons_Price__c,
 * Add_Ons_Markup__c, Premium_Model_Fee__c, Dealer_Price_Override__c,
 * Tax_Percentage__c, Tax_Region__c) — never the formula outputs — and the P3 tax
 * fix (§07.3) aligns the Without-Tax formula so stored = displayed = invoiced
 * holds by construction.
 *
 * Legacy parity anchors used by the Base_Coverage line (identical arithmetic
 * to the legacy portal DTO builder and the create-time Flow):
 *   - Dealer_Package_Term__c.Net_Cost__c   = Original − discount ($ or %)
 *   - Dealer_Package_Term__c.Retail_Price__c = Net_Cost + markup ($ or %)
 *   (both live formula fields on the org — the engine reads the formula values)
 * Options (P4 [S]): priced optional selections are carried on the package's
 * Option LINE ITEMS (Line_Type__c = 'Option', Application_Package_Line_Item__c)
 * — the engine's own priced state, written by ApplicationSnapshotService at
 * the previous save; the line's Amount__c is the dealer-retail the engine
 * priced then, so re-pricing an unchanged quote is byte-identical (R6). The
 * wholesale/markup split is not persisted on the line; net is re-derived from
 * the dealer-option mirror (Dealer_Package_Option__c formula chain) when one
 * exists, else wholesale = retail (markup 0).
 *
 * Safety (§10): the engine is NOT called by any live portal path while the
 * Pricing_Engine_Enabled__c flag is off. PortalFeatureFlagService gates every
 * entry point. The engine is `without sharing` (schedule data is private;
 * dealers never see it — the engine returns resolved amounts only).
 *
 * P3: engine computes + stamps the retail-side summary fields on
 * Application_Package__c for preview/save paths when the flag is on. Line-item
 * rows (Application_Package_Line_Item__c) are written by ApplicationSnapshotService
 * at P4; the engine unit-tests the line math in preview (plan §11 P3 [S]).
 */
public without sharing class PricingEngineService {

    // Line types (values of Application_Package_Line_Item__c.Line_Type__c, §03.5)
    public static final String LT_BASE_COVERAGE = 'Base_Coverage';
    public static final String LT_PREMIUM_FEE = 'Premium_Fee';
    public static final String LT_DIESEL_FEE = 'Diesel_Fee';
    public static final String LT_COMMERCIAL_SURCHARGE = 'Commercial_Surcharge';
    public static final String LT_POWERSPORTS_ADJUSTMENT = 'Powersports_Adjustment';
    public static final String LT_OPTION = 'Option';
    public static final String LT_ADD_ON = 'Add_On';
    public static final String LT_DISCOUNT = 'Discount';
    public static final String LT_TAX = 'Tax';

    public static final Decimal SCALE = 2;

    // ------------------------------------------------------------------
    // DTOs
    // ------------------------------------------------------------------

    /** Inputs to one quote computation. */
    public class QuoteRequest {
        public Id dealerId { get; set; }
        public Id vehicleId { get; set; }
        public Id dealerPackageId { get; set; }
        public Id dealerTermId { get; set; }
        public Id applicationId { get; set; }       // optional; not needed for math
        public Id applicationPackageId { get; set; } // optional: read options from APO rows
        public Date asOfDate { get; set; }
        /** Pre-tax dealer custom price. Null = no override. */
        public Decimal dealerPriceOverride { get; set; }
        /** Premium fee waived (admin waiver). Default false. */
        public Boolean waivePremiumFee { get; set; }
        /** Optional Dealer_Package_Option__c ids for preview (no package yet). */
        public List<Id> selectedOptionIds { get; set; }

        public QuoteRequest() {
            this.waivePremiumFee = false;
        }
    }

    /** One priced line. Plain values only — LWC-serialisable. */
    public class QuoteLine {
        public String lineType { get; set; }
        public String description { get; set; }
        public Decimal amount { get; set; }        // pre-tax line total
        public Boolean taxable { get; set; }
        public Decimal taxAmount { get; set; }     // per-line tax (2dp, HALF_UP)
        public Decimal quantity { get; set; }
        public Id provenanceTermId { get; set; }
        public Id provenanceOptionId { get; set; }
        public Id provenanceScheduleId { get; set; }
        public Id provenanceMemberId { get; set; }

        public QuoteLine() {
            this.taxable = true;
            this.quantity = 1;
        }
    }

    /** Engine outcome: line set + totals + eligibility facts. */
    public class QuoteResult {
        public Boolean success { get; set; }
        public List<String> errors { get; set; }
        public List<String> blocks { get; set; }
        public List<QuoteLine> lines { get; set; }
        public Decimal noTaxTotal { get; set; }     // Contract_Premium_Price_Without_Tax__c
        public Decimal taxAmount { get; set; }      // Tax_Amount__c
        public Decimal withTaxTotal { get; set; }   // Contract_Premium_Price__c
        public Decimal taxRate { get; set; }        // Tax_Percentage__c
        public Decimal baseCoverage { get; set; }   // Dealer_Package_Retail_Price__c anchor
        public Decimal netCost { get; set; }        // Dealer_Package_Price__c anchor
        public Decimal markupAmount { get; set; }   // Dealer_Markup__c anchor
        public Decimal premiumFee { get; set; }     // Premium_Model_Fee__c audit value
        public Decimal dieselFee { get; set; }      // Diesel_Fee__c audit value (mandatory diesel fee)
        public Decimal addOnsNet { get; set; }
        public Decimal addOnsMarkup { get; set; }
        public Decimal addOnsRetail { get; set; }
        public Date asOfDate { get; set; }
        public Boolean dealerOverrideApplied { get; set; }
        public Boolean premiumFeeWaived { get; set; }
        public Id dealerTermId { get; set; }

        public QuoteResult() {
            this.success = true;
            this.errors = new List<String>();
            this.blocks = new List<String>();
            this.lines = new List<QuoteLine>();
            this.noTaxTotal = 0;
            this.taxAmount = 0;
            this.withTaxTotal = 0;
            this.baseCoverage = 0;
            this.netCost = 0;
            this.markupAmount = 0;
            this.premiumFee = 0;
            this.dieselFee = 0;
            this.addOnsNet = 0;
            this.addOnsMarkup = 0;
            this.addOnsRetail = 0;
        }

        public Boolean hasErrors() {
            return !errors.isEmpty();
        }
    }

    // ------------------------------------------------------------------
    // Entry points
    // ------------------------------------------------------------------

    /**
     * Compute a quote without persisting anything. Never throws for missing
     * context — returns errors/blocks for data-quality surfacing.
     */
    public static QuoteResult computeQuote(QuoteRequest req) {
        QuoteResult result = new QuoteResult();
        if (req == null) {
            result.success = false;
            result.errors.add('Quote request is required.');
            return result;
        }
        Date asOf = req.asOfDate != null ? req.asOfDate : Date.today();
        result.asOfDate = asOf;

        // ---- 1. Load context ----
        if (req.dealerTermId == null) {
            result.success = false;
            result.errors.add('A dealer package term is required.');
            return result;
        }

        Dealer_Package_Term__c term = selectDealerTerm(req.dealerTermId);
        if (term == null) {
            result.success = false;
            result.errors.add('Dealer package term not found: ' + req.dealerTermId);
            return result;
        }
        result.dealerTermId = term.Id;

        Id masterPackageId = term.Dealer_Package__r != null
            ? term.Dealer_Package__r.Package__c : null;
        Id dealerId = req.dealerId != null ? req.dealerId
            : (term.Dealer_Package__r != null ? term.Dealer_Package__r.Dealer__c : null);
        Id dealerPackageId = req.dealerPackageId != null ? req.dealerPackageId
            : (term.Dealer_Package__c != null ? term.Dealer_Package__c : null);

        Account dealer = dealerId != null ? selectDealerAccount(dealerId) : null;
        Decimal taxRate = dealer != null && dealer.Tax_Region__r != null
            ? dealer.Tax_Region__r.Total_Tax_Rate__c : null;
        result.taxRate = taxRate != null ? money(taxRate) : 0;

        // ---- 2. Base coverage (legacy parity: term retail formula, or pre-tax override) ----
        Decimal customOverride = req.dealerPriceOverride;
        Boolean overrideApplied = customOverride != null;
        Decimal baseRetail;
        Decimal netCost;
        Decimal markupAmount;

        if (overrideApplied) {
            baseRetail = money(customOverride);
            // Override is pre-tax and replaces the whole customer price (legacy
            // convention: stored Dealer_Package_Price = override, markups and
            // add-on aggregates zeroed; the with-tax formula taxes only the
            // override). Fees and options are suppressed in this mode.
            netCost = baseRetail;
            markupAmount = 0;
        } else {
            // Retail_Price__c formula = Net_Cost + markup. Compute explicitly so
            // the engine never depends on formula evaluation quirks.
            Decimal original = term.Original_Package_Term_Cost__c != null ? term.Original_Package_Term_Cost__c : 0;
            netCost = applyDiscount(original, term.Discount_Type__c, term.Discount_Value__c);
            markupAmount = applyMarkup(netCost, term.Markup_Type__c, term.Markup__c);
            baseRetail = money(netCost + markupAmount);
        }
        result.netCost = money(netCost);
        result.markupAmount = money(markupAmount);
        result.baseCoverage = baseRetail;
        result.dealerOverrideApplied = overrideApplied;

        // ---- 3. Resolve schedule fee lines (R1–R6 via VehicleScheduleResolver) ----
        List<QuoteLine> lines = new List<QuoteLine>();
        QuoteLine baseLine = new QuoteLine();
        baseLine.lineType = LT_BASE_COVERAGE;
        baseLine.description = term.Name != null ? term.Name : 'Base coverage';
        baseLine.amount = baseRetail;
        baseLine.taxable = true;
        baseLine.provenanceTermId = term.Package_Term__c;
        lines.add(baseLine);

        // Fee resolution runs whenever a vehicle is present; the resolver
        // matches dealer-scoped assignments with no package context (R2).
        if (!overrideApplied && req.vehicleId != null) {
            VehicleScheduleResolver.ResolveRequest resolveReq = new VehicleScheduleResolver.ResolveRequest();
            resolveReq.dealerId = dealerId;
            resolveReq.vehicleId = req.vehicleId;
            resolveReq.packageId = masterPackageId;
            resolveReq.termId = term.Package_Term__c; // P-3: base-coverage/term anchor
            resolveReq.asOfDate = asOf;
            VehicleScheduleResolver.ResolverResult resolved = VehicleScheduleResolver.resolve(resolveReq);

            if (resolved != null) {
                result.blocks.addAll(resolved.blocks);
                Boolean premiumWaived = req.waivePremiumFee == true;
                result.premiumFeeWaived = premiumWaived;

                for (VehicleScheduleResolver.ResolvedFeeLine feeLine : resolved.lines) {
                    QuoteLine line = feeLineToQuoteLine(feeLine, baseRetail);
                    if (line == null) {
                        continue;
                    }
                    // Premium waiver suppresses the premium fee line entirely.
                    if (VehicleScheduleResolver.TYPE_PREMIUM_TIER.equals(feeLine.scheduleType)) {
                        if (premiumWaived) {
                            continue;
                        }
                        // P-4 (Design P-B), dealer-first: the premium fee is
                        // anchored on the DEALER term's Premium_Model_Fee__c
                        // when populated and > 0 (seeded once from the master
                        // at dealer-package creation; a dealer edit survives
                        // every later sync). Fall back to the master term's
                        // Package_Term__r.Premium_Model_Fee__c when the dealer
                        // value is blank, else keep the member-row amount.
                        // Identical rule (and order) to
                        // DealerPortalController.resolvePremium step 3 — their
                        // parity tests exist to catch any divergence.
                        Decimal dealerTermPremium = term.Premium_Model_Fee__c;
                        Decimal masterTermPremium = term.Package_Term__r != null
                            ? term.Package_Term__r.Premium_Model_Fee__c : null;
                        if (dealerTermPremium != null && dealerTermPremium > 0) {
                            line.amount = money(dealerTermPremium);
                        } else if (masterTermPremium != null && masterTermPremium > 0) {
                            line.amount = money(masterTermPremium);
                        }
                        // A premium table that prices $0 (or a make whose term
                        // carries no fee) emits no premium line, matching the
                        // book's "$0 premium fee" tables (Step D-2-check).
                        if (line.amount == null || line.amount <= 0) {
                            continue;
                        }
                        result.premiumFee = line.amount;
                    }
                    lines.add(line);
                }
                // Dealer override fact (R5) surfaced for preview/audit.
                result.dealerOverrideApplied = result.dealerOverrideApplied
                    || resolved.dealerOverrideApplied == true;
            }
        }

        // ---- 3a. Diesel fee (term-field path; mandatory, option-independent) ----
        // The mandatory Diesel Fee is charged whenever the vehicle is Diesel,
        // INDEPENDENT of whether the "Diesel Components" OPTION is selected. The
        // fee is resolved from the package TERM fields (dealer-first, then
        // master — see resolveDieselFee), not from a Vehicle_Schedule: no
        // Diesel_Fee schedule family rows exist, so the resolver never emits a
        // diesel line today. VehicleScheduleResolver.TYPE_DIESEL_FEE remains the
        // gate / line-type reference (LT_DIESEL_FEE below); the term-field path
        // replaces the schedule dependency for diesel.
        //
        // The line is a standalone TAXABLE fee line (user decision D-diesel:
        // the fee is taxable) — it is NEVER folded into the
        // Included_Options_Price__c / Additional_Options_Price__c option
        // rollups. If a schedule-resolved diesel line IS present (legacy data),
        // it wins and this path is skipped, so the fee is never charged twice.
        if (!overrideApplied && req.vehicleId != null) {
            // Resolve the TERM fee FIRST — a pure field read, NO query. Only
            // when a fee is actually configured (dealer or master Diesel_Fee__c
            // > 0) do we read the vehicle's fuel type, so a quote whose term
            // carries no diesel fee costs ZERO extra SOQL. This matters: an
            // unconditional per-quote vehicle read pushed multi-case harness
            // tests (e.g. PricingEngineReconciliationHarnessTest) over the
            // 100-SOQL governor cap.
            Decimal dieselFee = resolveDieselFee(term);
            if (dieselFee > 0) {
                Boolean dieselLinePresent = false;
                for (QuoteLine existing : lines) {
                    if (LT_DIESEL_FEE.equals(existing.lineType)) {
                        dieselLinePresent = true;
                        break;
                    }
                }
                if (!dieselLinePresent && isDieselVehicle(req.vehicleId)) {
                    QuoteLine dieselLine = new QuoteLine();
                    dieselLine.lineType = LT_DIESEL_FEE;
                    dieselLine.description = 'Diesel Fee';
                    dieselLine.amount = money(dieselFee);
                    dieselLine.taxable = true; // user decision: the fee is taxable
                    dieselLine.quantity = 1;
                    dieselLine.provenanceTermId = term.Package_Term__c;
                    lines.add(dieselLine);
                }
            }
        }

        // ---- 3b. Option lines (optional selections at dealer retail) ----
        // (suppressed under a pre-tax custom-price override — the override is
        // the full customer price; the with-tax formula taxes only it)
        List<OptionPrice> optionPrices = overrideApplied
            ? new List<OptionPrice>()
            : selectOptionPrices(req);
        for (OptionPrice op : optionPrices) {
            QuoteLine line = new QuoteLine();
            line.lineType = LT_OPTION;
            line.description = op.name;
            line.amount = op.retail;
            line.taxable = true;
            line.provenanceOptionId = op.provenanceOptionId;
            lines.add(line);
            result.addOnsNet = money(result.addOnsNet + op.net);
            result.addOnsMarkup = money(result.addOnsMarkup + (op.retail - op.net));
            result.addOnsRetail = money(result.addOnsRetail + op.retail);
        }

        // ---- 4. Totals: taxable subtotal -> tax once -> with-tax ----
        Decimal noTaxTotal = 0;
        Decimal taxableSubtotal = 0;
        for (QuoteLine line : lines) {
            noTaxTotal = money(noTaxTotal + line.amount);
            if (line.taxable) {
                taxableSubtotal = money(taxableSubtotal + line.amount);
            }
            if (LT_DIESEL_FEE.equals(line.lineType)) {
                // Audit value for Application_Package__c.Diesel_Fee__c — the
                // single source the Contract Premium summary formulas add on
                // top of the premium-model fee. Sums every diesel line (the
                // term-field path above and any legacy schedule-resolved line)
                // so it never double counts.
                result.dieselFee = money(result.dieselFee + line.amount);
            }
        }
        result.noTaxTotal = noTaxTotal;
        result.taxAmount = taxRate != null && taxRate > 0
            ? money(taxableSubtotal * taxRate / 100)
            : 0;
        result.withTaxTotal = money(noTaxTotal + result.taxAmount);

        // Per-line tax for the payload (informational in P3; persisted P4).
        for (QuoteLine line : lines) {
            line.taxAmount = line.taxable && result.taxAmount > 0
                ? money(line.amount * taxRate / 100)
                : 0;
        }

        // Deterministic output (R6 applies to fee lines; sort the full set).
        lines.sort(new LineComparator());
        result.lines = lines;
        return result;
    }

    /**
     * Stamp the engine-owned retail-side summary fields on an
     * Application_Package__c from a computed quote. Does NOT insert/update —
     * the caller owns the DML. Sets Priced_By_Engine__c = true so the
     * create-time flow skips its own math for this record (dual-writer guard).
     *
     * Engine-owned field set (plan §07.2 target column, retail side):
     * Dealer_Package_Price__c, Dealer_Markup__c, Dealer_Package_Retail_Price__c,
     * Contract_Premium_Price_Without_Tax__c, Tax_Amount__c,
     * Contract_Premium_Price__c, Premium_Model_Fee__c, Add_Ons_Price__c,
     * Add_Ons_Markup__c, Add_Ons_Retail_Price__c, Tax_Region__c,
     * Tax_Percentage__c, Priced_By_Engine__c.
     * Cost/commission fields (Wholesale_Price__c, Aprotect_Net__c, Reserve_*,
     * Commission_*, CRM_Charge__c, Owed_To_Dealer__c, Dealer_Discount_Amount__c,
     * Sales_Rep_Incentive__c, Total_Discount_*) stay owned by
     * CommissionCalculationHandler (P4 re-wires them to line items).
     */
    public static QuoteResult applyEnginePricing(Application_Package__c pkg, QuoteRequest req) {
        QuoteResult result = computeQuote(req);
        if (!result.success || pkg == null) {
            return result;
        }

        // STORED inputs only — the Application_Package display/cost formulas
        // derive Contract_Premium_Price__c / _Without_Tax__c / Tax_Amount__c /
        // Dealer_Package_Retail_Price__c / Add_Ons_Retail_Price__c from these.
        pkg.Dealer_Package_Price__c = result.netCost;
        pkg.Dealer_Markup__c = result.markupAmount;
        pkg.Add_Ons_Price__c = result.addOnsNet;
        pkg.Add_Ons_Markup__c = result.addOnsMarkup;
        pkg.Premium_Model_Fee__c = result.premiumFee;
        pkg.Diesel_Fee__c = result.dieselFee;
        pkg.Dealer_Price_Override__c = result.dealerOverrideApplied ? req.dealerPriceOverride : null;
        if (result.taxRate != null) {
            pkg.Tax_Percentage__c = result.taxRate;
        }
        if (req.dealerId != null && pkg.Dealer__c == null) {
            pkg.Dealer__c = req.dealerId;
        }
        pkg.Priced_By_Engine__c = true;
        return result;
    }

    // ------------------------------------------------------------------
    // Selectors (single query path)
    //
    // P7-g (2026-09-10): API v67 runs plain Apex SOQL/DML in USER mode by
    // default (Summer '26 secure-by-default). This engine is `without sharing`
    // and is deliberately an elevated, server-side pricing path — the dealer
    // portal profile carries NO FLS/object access to the pricing, schedule and
    // wholesale-cost data (decision D7), so a user-mode read here surfaces to
    // the running portal user as the misleading "No such column". Every query
    // in this class is therefore pinned to WITH SYSTEM_MODE, restoring the
    // pre-v67 semantics the engine was designed around (the line-item read and
    // the snapshot write already ran in SYSTEM_MODE).
    // ------------------------------------------------------------------

    private static Dealer_Package_Term__c selectDealerTerm(Id termId) {
        List<Dealer_Package_Term__c> terms = [
            SELECT Id, Name, Dealer_Package__c, Package_Term__c,
                   Dealer_Package__r.Dealer__c, Dealer_Package__r.Package__c,
                   Original_Package_Term_Cost__c,
                   Premium_Model_Fee__c,
                   Diesel_Fee__c,
                   Discount_Type__c, Discount_Value__c,
                   Markup__c, Markup_Type__c,
                   Package_Term__r.Premium_Model_Fee__c,
                   Package_Term__r.Diesel_Fee__c
            FROM Dealer_Package_Term__c
            WHERE Id = :termId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return terms.isEmpty() ? null : terms[0];
    }

    /**
     * True when the vehicle's fuel type is Diesel.
     *
     * Vehicle__c.Fuel_Type__c is a RESTRICTED picklist whose active API value is
     * exactly 'Diesel'; the comparison is case-insensitive so a legacy/stored
     * casing never silently drops the mandatory fee. SYSTEM_MODE (v67
     * secure-by-default): the dealer-portal profile carries no FLS on the
     * vehicle pricing fields — the same mode every selector in this class uses.
     */
    private static Boolean isDieselVehicle(Id vehicleId) {
        if (vehicleId == null) {
            return false;
        }
        List<Vehicle__c> vehicles = [
            SELECT Id, Fuel_Type__c
            FROM Vehicle__c
            WHERE Id = :vehicleId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (vehicles.isEmpty()) {
            return false;
        }
        return 'Diesel'.equalsIgnoreCase(vehicles[0].Fuel_Type__c);
    }

    /**
     * Mandatory Diesel Fee amount — DEALER-term-first, MASTER-term fallback,
     * else 0 (no fee). Identical rule and order to
     * DealerPortalController.resolveDieselFee (parity tests exist to catch any
     * divergence):
     *   1. dealer term  Diesel_Fee__c            when populated and > 0
     *   2. master term  Package_Term__r.Diesel_Fee__c when populated and > 0
     *   3. 0 — no fee
     * Currency is rounded to 2dp HALF_UP (money()). The dealer value is seeded
     * once from the master at dealer-package creation, so a dealer-local edit
     * survives every later sync; the master term is the fallback when the dealer
     * value is blank/zero.
     */
    private static Decimal resolveDieselFee(Dealer_Package_Term__c term) {
        if (term == null) {
            return 0;
        }
        Decimal dealerDiesel = term.Diesel_Fee__c;
        if (dealerDiesel != null && dealerDiesel > 0) {
            return money(dealerDiesel);
        }
        Decimal masterDiesel = term.Package_Term__r != null
            ? term.Package_Term__r.Diesel_Fee__c : null;
        if (masterDiesel != null && masterDiesel > 0) {
            return money(masterDiesel);
        }
        return 0;
    }

    private static Account selectDealerAccount(Id dealerId) {
        List<Account> accounts = [
            SELECT Id, Name, Charge_Premium_Vehicle_Fee__c,
                   Premium_Fee_Override_Amount__c,
                   Tax_Region__c, Tax_Region__r.Total_Tax_Rate__c
            FROM Account
            WHERE Id = :dealerId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return accounts.isEmpty() ? null : accounts[0];
    }

    /** Simple value holder for option pricing facts. */
    private class OptionPrice {
        public Decimal net;
        public Decimal retail;
        public String name;
        public Id provenanceOptionId;
    }

    /**
     * Optional selections priced at dealer retail. Source precedence:
     * 1. The package's priced Option LINE ITEMS (Line_Type__c = 'Option') —
     *    the engine's own priced state, written by the S5 option writers on
     *    option-add and by ApplicationSnapshotService on every engine save
     *    (P4 [S]: the line item is the single source of option state;
     *    Application_Package_Option__c is retired and never read here). Each
     *    line carries its already-priced retail (Amount__c) plus the master
     *    option provenance (Package_Option__c lookup), so a re-price of an
     *    unchanged quote reproduces byte-identical option lines (R6).
     * 2. Explicit Dealer_Package_Option__c ids (preview / new selection).
     * In every case the priced retail comes from the dealer-option formulas
     * (Net_Cost__c / Retail_Price__c = Original − discount / + markup) — for
     * carried lines those values were computed by the engine (or the writer,
     * from the same mirror formulas) at the previous save, so carrying the
     * line Amount forward is byte-identical.
     */
    private static List<OptionPrice> selectOptionPrices(QuoteRequest req) {
        List<OptionPrice> result = new List<OptionPrice>();
        // Canonical dedupe key: the master Package_Option the option points at
        // (identical across the line-item state and explicit Dealer_Package_
        // Option ids). DPO ids are also tracked so an explicit id never
        // double-prices an option already carried or listed twice.
        Set<Id> seenMasters = new Set<Id>();
        Set<Id> seenDpos = new Set<Id>();

        if (req.applicationPackageId != null) {
            // Precedence 1 — the engine's own priced state (P4 [S] primary
            // source): Option lines written by the S5 writers / last snapshot.
            // Amount__c is the priced retail; carry it forward unchanged (R6).
            // SYSTEM_MODE read: line-item fields carry no portal FLS yet (same
            // mode the snapshot writer and every line-item reader use).
            List<Application_Package_Line_Item__c> optionLines = new List<Application_Package_Line_Item__c>();
            String apIdLit = '\'' + String.valueOf(req.applicationPackageId) + '\'';
            for (Application_Package_Line_Item__c line : (List<Application_Package_Line_Item__c>) Database.query(
                    'SELECT Id, Description__c, Amount__c, Package_Option__c' +
                    ' FROM Application_Package_Line_Item__c' +
                    ' WHERE Application_Package__c = ' + apIdLit +
                    ' AND Line_Type__c = \'Option\'' +
                    ' AND Package_Option__c != null' +
                    ' ORDER BY Sort_Order__c, Id',
                    System.AccessLevel.SYSTEM_MODE)) {
                optionLines.add(line);
            }
            // Net/markup split is not persisted on the line (the line carries
            // the priced retail only), so carried options re-derive net from
            // the dealer-option mirror when one exists for the quote's dealer;
            // wholesale = retail (markup 0) is the documented fallback when
            // the mirror is gone (option deactivated after the quote priced).
            Map<Id, Dealer_Package_Option__c> mirrorByMaster =
                new Map<Id, Dealer_Package_Option__c>();
            if (!optionLines.isEmpty()) {
                Set<Id> masters = new Set<Id>();
                for (Application_Package_Line_Item__c line : optionLines) {
                    masters.add(line.Package_Option__c);
                }
                Id dealerPkgId = req.dealerPackageId;
                if (dealerPkgId == null) {
                    for (Application_Package__c ap : [
                        SELECT Dealer_Package__c FROM Application_Package__c
                        WHERE Id = :req.applicationPackageId
                        WITH SYSTEM_MODE LIMIT 1
                    ]) {
                        dealerPkgId = ap.Dealer_Package__c;
                    }
                }
                if (dealerPkgId != null) {
                    for (Dealer_Package_Option__c dpo : [
                        SELECT Id, Name, Package_Option__c, Net_Cost__c, Retail_Price__c
                        FROM Dealer_Package_Option__c
                        WHERE Dealer_Package__c = :dealerPkgId
                          AND Package_Option__c IN :masters
                          AND Retail_Price__c != null
                        WITH SYSTEM_MODE
                    ]) {
                        mirrorByMaster.put(dpo.Package_Option__c, dpo);
                    }
                }
                for (Application_Package_Line_Item__c line : optionLines) {
                    OptionPrice op = new OptionPrice();
                    op.retail = money(line.Amount__c);
                    Dealer_Package_Option__c mirror =
                        mirrorByMaster.get(line.Package_Option__c);
                    op.net = mirror != null && mirror.Net_Cost__c != null
                        ? money(mirror.Net_Cost__c) : op.retail;
                    op.name = String.isNotBlank(line.Description__c)
                        ? line.Description__c : (mirror != null ? mirror.Name : 'Option');
                    op.provenanceOptionId = line.Package_Option__c;
                    seenMasters.add(line.Package_Option__c);
                    result.add(op);
                }
            }
        }

        if (req.selectedOptionIds != null && !req.selectedOptionIds.isEmpty()) {
            for (Dealer_Package_Option__c dpo : [
                SELECT Id, Name, Package_Option__c, Net_Cost__c, Retail_Price__c
                FROM Dealer_Package_Option__c
                WHERE Id IN :req.selectedOptionIds
                  AND Retail_Price__c != null
                WITH SYSTEM_MODE
                ORDER BY Name
            ]) {
                if (seenDpos.contains(dpo.Id)) {
                    continue;
                }
                if (dpo.Package_Option__c != null && seenMasters.contains(dpo.Package_Option__c)) {
                    continue;
                }
                OptionPrice op = new OptionPrice();
                op.net = dpo.Net_Cost__c != null ? money(dpo.Net_Cost__c) : 0;
                op.retail = money(dpo.Retail_Price__c);
                op.name = dpo.Name;
                op.provenanceOptionId = dpo.Package_Option__c;
                seenDpos.add(dpo.Id);
                if (dpo.Package_Option__c != null) {
                    seenMasters.add(dpo.Package_Option__c);
                }
                result.add(op);
            }
        }
        return result;
    }

    // ------------------------------------------------------------------
    // Arithmetic helpers
    // ------------------------------------------------------------------

    /** Discount ($ or %) against the wholesale anchor — same rules as the Net_Cost formula. */
    private static Decimal applyDiscount(Decimal original, String discountType, Decimal discountValue) {
        if (discountValue == null || discountValue <= 0 || String.isBlank(discountType)) {
            return money(original);
        }
        if ('$'.equals(discountType)) {
            return money(original - discountValue);
        }
        if ('%'.equals(discountType)) {
            return money(original - (original * discountValue / 100));
        }
        return money(original);
    }

    /** Markup ($ or %) against net cost — same rules as the Retail_Price formula. */
    private static Decimal applyMarkup(Decimal netCost, String markupType, Decimal markupValue) {
        if (markupValue == null || markupValue <= 0 || String.isBlank(markupType)) {
            return 0;
        }
        if ('$'.equals(markupType)) {
            return money(markupValue);
        }
        if ('%'.equals(markupType)) {
            return money(netCost * markupValue / 100);
        }
        return 0;
    }

    /** Map one resolver fee line to a priced quote line (2dp, HALF_UP). */
    private static QuoteLine feeLineToQuoteLine(
        VehicleScheduleResolver.ResolvedFeeLine feeLine, Decimal baseRetail) {

        if (feeLine == null || feeLine.scheduleType == null) {
            return null;
        }
        String type = feeLine.scheduleType;
        QuoteLine line = new QuoteLine();
        line.provenanceScheduleId = feeLine.scheduleId;
        line.provenanceMemberId = feeLine.memberId;
        line.taxable = true;

        if (VehicleScheduleResolver.TYPE_PREMIUM_TIER.equals(type)) {
            line.lineType = LT_PREMIUM_FEE;
            line.description = feeLine.tier != null ? ('Premium ' + feeLine.tier) : 'Premium fee';
            line.amount = resolvedAmount(feeLine, baseRetail);
        } else if (VehicleScheduleResolver.TYPE_DIESEL_FEE.equals(type)) {
            line.lineType = LT_DIESEL_FEE;
            line.description = 'Diesel fee';
            line.amount = resolvedAmount(feeLine, baseRetail);
        } else if (VehicleScheduleResolver.TYPE_COMMERCIAL_SURCHARGE.equals(type)) {
            line.lineType = LT_COMMERCIAL_SURCHARGE;
            line.description = 'Commercial surcharge';
            line.amount = resolvedAmount(feeLine, baseRetail);
        } else if (VehicleScheduleResolver.TYPE_POWERSPORTS_PROGRAM.equals(type)) {
            // Powersports multiplier applies to the base coverage: legacy
            // equivalent was totalPrice x (multiplier - 1) — now a data row.
            line.lineType = LT_POWERSPORTS_ADJUSTMENT;
            line.description = feeLine.scheduleName != null ? feeLine.scheduleName : 'Powersports adjustment';
            Decimal mult = feeLine.multiplier != null ? feeLine.multiplier : 1;
            line.amount = mult > 0 ? money(baseRetail * (mult - 1)) : 0;
        } else if (VehicleScheduleResolver.TYPE_TIRE_RIM_CATEGORY.equals(type)) {
            // T&R category rows are membership/classification rows: the category
            // price lives on the package TERM (base coverage). A row that carries
            // an explicit amount (category surcharge) is priced as an option line;
            // amount-less rows add nothing (R4-equivalent for the line set).
            Decimal amt = resolvedAmount(feeLine, baseRetail);
            if (amt <= 0) {
                return null;
            }
            line.lineType = LT_OPTION;
            line.description = feeLine.tier != null
                ? ('Tire & Rim category ' + feeLine.tier)
                : 'Tire & Rim category';
            line.amount = amt;
        } else {
            return null;
        }
        if (line.amount == null || line.amount < 0) {
            line.amount = 0;
        }
        return line;
    }

    /** Resolve the money value of a schedule row: Flat amount, % of base, or multiplier on base. */
    private static Decimal resolvedAmount(VehicleScheduleResolver.ResolvedFeeLine feeLine, Decimal baseRetail) {
        String amountType = String.isNotBlank(feeLine.amountType)
            ? feeLine.amountType : VehicleScheduleResolver.AMOUNT_TYPE_FLAT;
        if (VehicleScheduleResolver.AMOUNT_TYPE_PERCENT.equals(amountType)
            && feeLine.amount != null) {
            return money(baseRetail * feeLine.amount / 100);
        }
        if (VehicleScheduleResolver.AMOUNT_TYPE_MULTIPLIER.equals(amountType)
            && feeLine.multiplier != null) {
            return money(baseRetail * feeLine.multiplier);
        }
        return feeLine.amount != null ? money(feeLine.amount) : 0;
    }

    /** Currency rounding: 2dp, half-up (decision D5). */
    public static Decimal money(Decimal value) {
        if (value == null) {
            return 0;
        }
        return value.setScale(SCALE.intValue(), System.RoundingMode.HALF_UP);
    }

    /** Output-order rank for deterministic line sorting (R6). */
    private static final Map<String, Integer> LINE_ORDER = new Map<String, Integer>{
        LT_BASE_COVERAGE => 0,
        LT_PREMIUM_FEE => 1,
        LT_DIESEL_FEE => 2,
        LT_COMMERCIAL_SURCHARGE => 3,
        LT_POWERSPORTS_ADJUSTMENT => 4,
        LT_OPTION => 5,
        LT_ADD_ON => 6,
        LT_DISCOUNT => 7,
        LT_TAX => 8
    };

    /** Deterministic output ordering (R6 for the whole line set). */
    private class LineComparator implements Comparator<QuoteLine> {
        public Integer compare(QuoteLine a, QuoteLine b) {
            Integer oa = LINE_ORDER.containsKey(a.lineType) ? LINE_ORDER.get(a.lineType) : 99;
            Integer ob = LINE_ORDER.containsKey(b.lineType) ? LINE_ORDER.get(b.lineType) : 99;
            if (oa != ob) {
                return oa < ob ? -1 : 1;
            }
            String da = a.description != null ? a.description : '';
            String db = b.description != null ? b.description : '';
            Integer byDesc = da.compareTo(db);
            if (byDesc != 0) {
                return byDesc;
            }
            Decimal aa = a.amount != null ? a.amount : 0;
            Decimal bb = b.amount != null ? b.amount : 0;
            return aa == bb ? 0 : (aa < bb ? -1 : 1);
        }
    }
}