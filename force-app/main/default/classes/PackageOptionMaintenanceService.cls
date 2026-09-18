/**
 * PackageOptionMaintenanceService
 *
 * Admin catalogue-maintenance service for master Package_Option__c rows —
 * the "Create Package Options" admin capability (change-implementation plan
 * §06.1 / §05.2 / §09.3, Phase 5 fold-in).
 *
 * Why it exists
 * ─────────────
 * The capability was reachable ONLY through the Create_Package_Options
 * SCREEN FLOW (quick action "Create Options" on Package__c / Package_Term__c
 * record pages + layouts) hosting the createPackageOptions LWC
 * (lightning__FlowScreen target only — the LWC cannot run outside a flow).
 * The flow itself is a zero-logic host: one screen, one component instance,
 * no DML. The real work is this: create Included / Optional
 * Package_Option__c rows against a Package__c (or, via Package_Term__c →
 * Package_Tier__c → Package__c, a Package_Term__c) master.
 *
 * Phase-5 fold-in (2026-09-08): that logic now lives here as a typed,
 * @AuraEnabled service so the consolidated catalogue admin LWC (plan §09.3,
 * built after admin UAT) can call it directly once the screen flow + legacy
 * LWC are retired. CreatePackageOptionsController delegates here unchanged,
 * so the legacy flow-launched UI keeps working byte-for-byte until then.
 *
 * Behaviour is a faithful extraction of the legacy controller method:
 * validation ORDER, per-row first-error semantics, and the exact
 * field-set/Selection_Type contract are preserved. `without sharing`
 * deliberately matches the legacy controller and the engine/admin service
 * pattern on this org (DealerPackageSyncService, PricingEngineService,
 * ApplicationSnapshotService) — catalogue master rows are org-wide by
 * design; nothing here changes record-visibility behaviour.
 *
 * Row contract (unchanged from the legacy tool):
 *   • Included  — Package__c = resolved package; Selection_Type__c =
 *                  'Included'; Inclusion/Exclusion_Text__c copied.
 *   • Optional (launched from a Package_Term__c) — Package_Term__c set
 *                  (row.packageTermId or the launch record); Package__c ALSO
 *                  set to the package resolved from that term (the same
 *                  tier-first/direct-link resolution used for validation);
 *                  Price__c required >= 0. Stamping Package__c is what lets
 *                  the dealer sync mirror term-anchored additional options out
 *                  to dealers (it keys the master row by its package).
 *   • Optional (launched from a Package__c, legacy shape) — Package__c set;
 *                  Category__c / Minimum_Value__c / Maximum_Value__c copied
 *                  (min <= max enforced); Price__c required >= 0.
 *
 * p11 — manage EXISTING rows (read / delete / price update)
 * ─────────────────────────────────────────────────────────
 * The LWC now also loads and manages the rows that already exist for the launch
 * record, so this service gained three @AuraEnabled operations beside create:
 *   • getPackageOptions(recordId, isIncluded)      — read the existing rows.
 *   • deletePackageOption(recordId, isIncluded, id) — delete one row.
 *   • updatePackageOptionPrices(recordId, rows)     — edit Optional prices in place.
 * All three share ONE term → package resolver (resolvePackageId: tier route
 * first, then the term's direct Package__c — the same order create already used)
 * and ONE ownership guard (rowBelongsToContext), so read, create, delete and
 * update can never disagree about which rows belong to a context.
 *
 * Display / anchor rules (confirmed against live data):
 *   • Included rows are PACKAGE-level — Selection_Type__c='Included',
 *     Package__c = resolved package, Package_Term__c null. A term launch shows
 *     the Included rows of the term's package (they are shared by every term).
 *   • Additional rows are TERM-level when launched from a term
 *     (Package_Term__c = term) and PACKAGE-level when launched from a package
 *     (Package__c = package AND Package_Term__c null).
 */
public without sharing class PackageOptionMaintenanceService {

    /**
     * One editable row of the admin option-creation table (JSON round-trip shape).
     *
     * p10fix — every member MUST be a property with a getter AND setter
     * (`{ get; set; }`), NOT a bare `@AuraEnabled public` field. The Lightning
     * (Aura) framework does not bind inbound JSON object keys onto plain
     * parameter-DTO fields: it only writes through property accessors. With
     * bare fields, a row the component clearly populated arrived at this
     * method with every value null, so validation reported
     * "Option is required for all rows" even though the client sent a valid
     * 18-character optionId. Output is unaffected — bare `@AuraEnabled` fields
     * still serialize back to the client, which is why the LWC received
     * CreateResult normally while the request DTO silently lost its data.
     * Do not "simplify" these back to fields.
     */
    public class PackageOptionRowDTO {
        @AuraEnabled public String optionId { get; set; }
        @AuraEnabled public String category { get; set; }
        @AuraEnabled public Decimal minimumValue { get; set; }
        @AuraEnabled public Decimal maximumValue { get; set; }
        @AuraEnabled public Decimal price { get; set; }
        @AuraEnabled public String inclusionText { get; set; }
        @AuraEnabled public String exclusionText { get; set; }
        @AuraEnabled public String packageTermId { get; set; }

        public PackageOptionRowDTO() {
            // Default constructor for deserialization
        }
    }

    /** Typed outcome for the future consolidated admin LWC. */
    public class CreateResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Integer createdCount;

        public CreateResult(Boolean success, String message, Integer createdCount) {
            this.success = success;
            this.message = message;
            this.createdCount = createdCount;
        }
    }

    /**
     * p11 — one EXISTING Package_Option__c row as the admin LWC renders it
     * (option label + current text/price/limits). Read model only: returned by
     * getPackageOptions, never accepted inbound.
     *
     * Members carry accessors (not bare fields) so the class is safe if it is
     * ever reused as a parameter type — the p10fix inbound-binding rule
     * (bare @AuraEnabled fields never bind) is honoured defensively here.
     */
    public class PackageOptionView {
        @AuraEnabled public String id { get; set; }          // Package_Option__c Id
        @AuraEnabled public String optionId { get; set; }
        @AuraEnabled public String optionName { get; set; }
        @AuraEnabled public Decimal price { get; set; }
        @AuraEnabled public String inclusionText { get; set; }
        @AuraEnabled public String exclusionText { get; set; }
        @AuraEnabled public String category { get; set; }
        @AuraEnabled public Decimal minimumValue { get; set; }
        @AuraEnabled public Decimal maximumValue { get; set; }

        public PackageOptionView() {}
    }

    /**
     * p11 — request row for a bulk price update. PARAMETER DTO, so every member
     * must be a `{ get; set; }` property (see PackageOptionRowDTO / p10fix).
     */
    public class PriceUpdateRowDTO {
        @AuraEnabled public String optionRowId { get; set; }
        @AuraEnabled public Decimal price { get; set; }

        public PriceUpdateRowDTO() {}
    }

    /** p11 — typed outcome for the delete / price-update operations. */
    public class OperationResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Integer affectedCount;

        public OperationResult(Boolean success, String message, Integer affectedCount) {
            this.success = success;
            this.message = message;
            this.affectedCount = affectedCount;
        }
    }

    /**
     * Creates Package_Option__c rows for one Package__c / Package_Term__c.
     *
     * @param recordId  the Package__c or Package_Term__c the admin launched from
     * @param rows      the rows to create (validated in order; first error wins)
     * @param isIncluded true → Included rows; false → Optional (priced) rows
     * @return CreateResult — success=false carries the human-readable reason
     */
    @AuraEnabled
    public static CreateResult createPackageOptions(Id recordId, List<PackageOptionRowDTO> rows, Boolean isIncluded) {
        try {
            return createPackageOptionsInner(recordId, rows, isIncluded);
        } catch (Exception e) {
            return new CreateResult(false, e.getMessage(), 0);
        }
    }

    private static CreateResult createPackageOptionsInner(Id recordId, List<PackageOptionRowDTO> rows, Boolean isIncluded) {
        if (recordId == null) {
            return new CreateResult(false, 'Record ID is required', 0);
        }
        if (rows == null || rows.isEmpty()) {
            return new CreateResult(false, 'At least one row is required', 0);
        }

        // Determine the actual Package__c ID and Package_Term__c ID
        Id packageId = recordId;
        Id packageTermId = null;
        SObjectType sobjectType = recordId.getSObjectType();
        String objectApiName = sobjectType.getDescribe().getName();

        // If it's a Package_Term__c, get the Package__c ID from the relationship
        if (objectApiName == 'Package_Term__c') {
            packageTermId = recordId;
            // Single shared term → package resolution (see resolvePackageId):
            // tier route first, then the term's direct Package__c. The read
            // (getPackageOptions), the guards (rowBelongsToContext) and this
            // writer all call the SAME helper, so they can never disagree.
            packageId = resolvePackageId(recordId);
            if (packageId == null) {
                return new CreateResult(false, 'Could not find Package from Package Term relationship', 0);
            }
        }

        List<Package_Option__c> optionsToInsert = new List<Package_Option__c>();

        for (Integer i = 0; i < rows.size(); i++) {
            PackageOptionRowDTO row = rows[i];

            // Validation
            if (row.optionId == null || String.isBlank(row.optionId)) {
                return new CreateResult(false, 'Option is required for all rows', 0);
            }

            Package_Option__c option = new Package_Option__c();
            option.Option__c = row.optionId;

            if (isIncluded != null && isIncluded) {
                // Included Options - always set Package__c
                option.Package__c = packageId;
                option.Selection_Type__c = 'Included';
                option.Inclusion_Text__c = row.inclusionText;
                option.Exclusion_Text__c = row.exclusionText;
            } else {
                // Additional Options
                if (row.price == null || row.price < 0) {
                    return new CreateResult(false, 'Price must be greater than or equal to 0', 0);
                }
                option.Selection_Type__c = 'Optional';
                option.Price__c = row.price;
                option.Inclusion_Text__c = row.inclusionText;
                option.Exclusion_Text__c = row.exclusionText;

                // If creating from Package_Term__c, set Package_Term__c AND the
                // Package__c resolved from the term.
                if (packageTermId != null) {
                    // Set Package_Term__c lookup if provided (for Package_Term__c records)
                    if (String.isNotBlank(row.packageTermId)) {
                        option.Package_Term__c = row.packageTermId;
                    } else {
                        // Fallback to the recordId if packageTermId not in row
                        option.Package_Term__c = packageTermId;
                    }
                    // Also stamp the package resolved from the term — the exact
                    // same resolution used above for validation (term tier route
                    // first, then the term's direct Package__c). The dealer sync
                    // needs this package link to mirror term-anchored additional
                    // options out to dealers.
                    option.Package__c = packageId;
                } else {
                    // Legacy: When creating from Package__c directly, set Package__c
                    option.Package__c = packageId;
                    if (row.minimumValue != null && row.maximumValue != null && row.minimumValue > row.maximumValue) {
                        return new CreateResult(false, 'Minimum Value cannot be greater than Maximum Value', 0);
                    }
                    option.Category__c = row.category;
                    option.Minimum_Value__c = row.minimumValue;
                    option.Maximum_Value__c = row.maximumValue;
                }
            }

            optionsToInsert.add(option);
        }

        insert optionsToInsert;
        return new CreateResult(true, 'Created ' + optionsToInsert.size() + ' package options', optionsToInsert.size());
    }

    // =========================================================================
    // p11 — read / delete / update on EXISTING rows
    // =========================================================================

    /**
     * Reads the Package_Option__c rows that already exist for the launch record.
     *
     * Display rule (the "Included = package-level" anchoring, confirmed against
     * live data — 426 Included rows, all Package__c-set / Package_Term__c-null):
     *   • Included section  → rows with Selection_Type__c = 'Included' AND
     *                         Package__c = the package resolved from the launch
     *                         record (the launch Package__c itself, or the
     *                         term's resolved package). Included rows are a
     *                         package-level concept shared by every term of that
     *                         package, so a term launch shows the package's
     *                         Included rows.
     *   • Additional section, launched from a Package_Term__c → rows with
     *                         Selection_Type__c = 'Optional' AND
     *                         Package_Term__c = that term.
     *   • Additional section, launched from a Package__c → rows with
     *                         Selection_Type__c = 'Optional' AND
     *                         Package__c = that package AND Package_Term__c = null
     *                         (package-level priced rows; term-anchored rows are
     *                         excluded because they belong to a term screen).
     *
     * @param recordId  the Package__c or Package_Term__c the admin launched from
     * @param isIncluded true → Included section; false → Additional section
     * @return the existing rows (empty when none / unresolvable context)
     */
    @AuraEnabled
    public static List<PackageOptionView> getPackageOptions(Id recordId, Boolean isIncluded) {
        List<PackageOptionView> views = new List<PackageOptionView>();
        if (recordId == null) {
            return views;
        }

        List<Package_Option__c> rows;
        if (isIncluded == true) {
            Id packageId = resolvePackageId(recordId);
            if (packageId == null) {
                return views;
            }
            rows = [
                SELECT Id, Option__c, Option__r.Name, Price__c, Inclusion_Text__c, Exclusion_Text__c,
                       Category__c, Minimum_Value__c, Maximum_Value__c
                FROM Package_Option__c
                WHERE Selection_Type__c = 'Included' AND Package__c = :packageId
                ORDER BY Option__r.Name
            ];
        } else {
            String objectApiName = recordId.getSObjectType().getDescribe().getName();
            if (objectApiName == 'Package_Term__c') {
                rows = [
                    SELECT Id, Option__c, Option__r.Name, Price__c, Inclusion_Text__c, Exclusion_Text__c,
                           Category__c, Minimum_Value__c, Maximum_Value__c
                    FROM Package_Option__c
                    WHERE Selection_Type__c = 'Optional' AND Package_Term__c = :recordId
                    ORDER BY Option__r.Name
                ];
            } else {
                rows = [
                    SELECT Id, Option__c, Option__r.Name, Price__c, Inclusion_Text__c, Exclusion_Text__c,
                           Category__c, Minimum_Value__c, Maximum_Value__c
                    FROM Package_Option__c
                    WHERE Selection_Type__c = 'Optional' AND Package__c = :recordId AND Package_Term__c = null
                    ORDER BY Option__r.Name
                ];
            }
        }

        for (Package_Option__c r : rows) {
            PackageOptionView v = new PackageOptionView();
            v.id = r.Id;
            v.optionId = r.Option__c;
            v.optionName = r.Option__r != null ? r.Option__r.Name : null;
            v.price = r.Price__c;
            v.inclusionText = r.Inclusion_Text__c;
            v.exclusionText = r.Exclusion_Text__c;
            v.category = r.Category__c;
            v.minimumValue = r.Minimum_Value__c;
            v.maximumValue = r.Maximum_Value__c;
            views.add(v);
        }
        return views;
    }

    /**
     * Deletes one existing Package_Option__c row, guarding that it genuinely
     * belongs to the launch context first (fail-closed):
     *   • Included → the row is Included AND sits on the package resolved from
     *     the launch record.
     *   • Additional from a term → the row is Optional AND anchored to that term.
     *   • Additional from a package → the row is Optional AND package-level
     *     (Package__c = launch package, Package_Term__c = null).
     * A row that is already gone (deleted by someone else, or a stale row id)
     * is reported rather than silently ignored.
     */
    @AuraEnabled
    public static OperationResult deletePackageOption(Id recordId, Boolean isIncluded, Id optionRowId) {
        try {
            if (recordId == null) {
                return new OperationResult(false, 'Record ID is required', 0);
            }
            if (optionRowId == null) {
                return new OperationResult(false, 'Option row ID is required', 0);
            }
            List<Package_Option__c> found = [
                SELECT Id, Selection_Type__c, Package__c, Package_Term__c
                FROM Package_Option__c
                WHERE Id = :optionRowId
                LIMIT 1
            ];
            if (found.isEmpty()) {
                return new OperationResult(false, 'That option row no longer exists', 0);
            }
            if (!rowBelongsToContext(found[0], recordId, isIncluded)) {
                return new OperationResult(false, 'That option row does not belong to this package or term', 0);
            }
            delete found[0];
            return new OperationResult(true, 'Option removed', 1);
        } catch (Exception e) {
            return new OperationResult(false, e.getMessage(), 0);
        }
    }

    /**
     * Updates the Price__c of one or more existing Optional rows (the edit-in-
     * place path — an UPDATE, never a create). All rows are validated and
     * ownership-checked up front, so a single bad row rejects the whole request
     * with no partial DML.
     *
     * @param recordId the launch Package__c / Package_Term__c
     * @param rows     { optionRowId, price } pairs (price required, >= 0)
     */
    @AuraEnabled
    public static OperationResult updatePackageOptionPrices(Id recordId, List<PriceUpdateRowDTO> rows) {
        try {
            if (recordId == null) {
                return new OperationResult(false, 'Record ID is required', 0);
            }
            if (rows == null || rows.isEmpty()) {
                return new OperationResult(false, 'At least one row is required', 0);
            }

            Set<Id> ids = new Set<Id>();
            for (PriceUpdateRowDTO r : rows) {
                if (r == null || String.isBlank(r.optionRowId)) {
                    return new OperationResult(false, 'Option row ID is required', 0);
                }
                if (r.price == null || r.price < 0) {
                    return new OperationResult(false, 'Price must be greater than or equal to 0', 0);
                }
                ids.add(r.optionRowId);
            }

            Map<Id, Package_Option__c> existing = new Map<Id, Package_Option__c>([
                SELECT Id, Selection_Type__c, Package__c, Package_Term__c
                FROM Package_Option__c
                WHERE Id IN :ids
            ]);

            // Fail-closed: validate every row before any DML.
            for (PriceUpdateRowDTO r : rows) {
                Package_Option__c row = existing.get(r.optionRowId);
                if (row == null) {
                    return new OperationResult(false, 'That option row no longer exists', 0);
                }
                if (!rowBelongsToContext(row, recordId, false)) {
                    return new OperationResult(false, 'That option row does not belong to this package or term', 0);
                }
            }

            List<Package_Option__c> updates = new List<Package_Option__c>();
            for (PriceUpdateRowDTO r : rows) {
                updates.add(new Package_Option__c(Id = r.optionRowId, Price__c = r.price));
            }
            update updates;
            return new OperationResult(true,
                'Updated ' + updates.size() + ' option price' + (updates.size() == 1 ? '' : 's'),
                updates.size());
        } catch (Exception e) {
            return new OperationResult(false, e.getMessage(), 0);
        }
    }

    // =========================================================================
    // Internals shared by create / read / delete / update
    // =========================================================================

    /**
     * Resolves the Package__c for a launch record. For a Package__c it is the
     * record itself; for a Package_Term__c it coalesces the two supported links:
     *   1. Term → Package_Tier__r → Package__c (tier route — legacy contract)
     *   2. Term → Package__c (direct link — the majority of terms on this org
     *      carry no Package_Tier__c at all)
     * Tier route wins when both are present, preserving the legacy traversal and
     * matching DealerPackageSyncService. Returns null when unresolvable.
     */
    private static Id resolvePackageId(Id recordId) {
        if (recordId == null) {
            return null;
        }
        String objectApiName = recordId.getSObjectType().getDescribe().getName();
        if (objectApiName == 'Package__c') {
            return recordId;
        }
        if (objectApiName == 'Package_Term__c') {
            List<Package_Term__c> terms = [
                SELECT Package_Tier__r.Package__c, Package__c
                FROM Package_Term__c
                WHERE Id = :recordId
                LIMIT 1
            ];
            if (terms.isEmpty()) {
                return null;
            }
            return (terms[0].Package_Tier__r != null && terms[0].Package_Tier__r.Package__c != null)
                ? terms[0].Package_Tier__r.Package__c
                : terms[0].Package__c;
        }
        return null;
    }

    /**
     * True when the row is genuinely part of the launch context — the guard
     * behind delete and price update. See deletePackageOption for the rules.
     */
    private static Boolean rowBelongsToContext(Package_Option__c row, Id recordId, Boolean isIncluded) {
        if (row == null || recordId == null) {
            return false;
        }
        if (isIncluded == true) {
            if (row.Selection_Type__c != 'Included') {
                return false;
            }
            Id packageId = resolvePackageId(recordId);
            return packageId != null && row.Package__c == packageId;
        }
        if (row.Selection_Type__c != 'Optional') {
            return false;
        }
        String objectApiName = recordId.getSObjectType().getDescribe().getName();
        if (objectApiName == 'Package_Term__c') {
            return row.Package_Term__c == recordId;
        }
        return row.Package__c == recordId && row.Package_Term__c == null;
    }
}