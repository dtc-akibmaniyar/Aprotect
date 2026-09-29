/**
 * VehicleScheduleResolver
 *
 * Schedule resolution engine (R1-R6 of the approved design, change-plan §04.1/P1).
 * Answers one question for one context: given (dealer Account, vehicle, package,
 * as-of date), what fee lines apply — resolved strictly per the documented rules:
 *
 *   R1  Effective & active only. Schedule Is_Active__c = true and the schedule's
 *       Valid_From/To window plus the assignment's Effective_From/To window
 *       contain the as-of date. Expired/draft never matches.
 *   R2  Scope precedence: dealer-scoped assignment > package-scoped >
 *       plan-type (Package_Group) scoped. Ties by most recent Valid_From__c,
 *       then deterministic (assignment Id).
 *   R3  Row precedence inside a schedule: model row over make row; exclusion
 *       over inclusion. Exact order (first match wins):
 *         1. model exclusion   (Make+Model, Is_Exclusion)
 *         2. model inclusion   (Make+Model)
 *         3. make exclusion    (Make + Include_All_Models, Is_Exclusion)
 *         4. make inclusion    (Make + Include_All_Models)
 *         5. catch-all         (no make/model, Include_All_Models)
 *       An exclusion match removes the vehicle from that schedule (no fee).
 *   R4  Fallback. No member row matches => no fee from this schedule. A model
 *       row may *add* a vehicle the make list omits (e.g. Subaru WRX).
 *   R5  Dealer override wins. Account.Charge_Premium_Vehicle_Fee__c = true with
 *       Premium_Fee_Override_Amount__c populated replaces the resolved premium
 *       fee amount for that dealer.
 *   R6  Deterministic. Same context in => same lines out (sorting is explicit).
 *
 * Schedule-type gates (design §6.4, data semantics of each schedule family):
 *   - Diesel_Fee         only resolves for Diesel-fuelled vehicles (catch-all row)
 *   - Commercial_Surcharge only resolves for commercial/business-use vehicles
 *   - Tire_Rim_Category  blocked for commercial/business-use vehicles (D2, P1 rule)
 *   - Powersports_Program rows are make rows carrying Amount_Type=Multiplier +
 *     Multiplier__c (the 1.25 / 1.60 powersports logic becomes data)
 *
 * P1 safety: this service is NOT referenced by any live portal code path. Portal
 * behaviour is unchanged; callers gate on PortalFeatureFlagService flags.
 */
public without sharing class VehicleScheduleResolver {

    public static final String TYPE_PREMIUM_TIER = 'Premium_Tier';
    public static final String TYPE_DIESEL_FEE = 'Diesel_Fee';
    public static final String TYPE_COMMERCIAL_SURCHARGE = 'Commercial_Surcharge';
    public static final String TYPE_POWERSPORTS_PROGRAM = 'Powersports_Program';
    public static final String TYPE_TIRE_RIM_CATEGORY = 'Tire_Rim_Category';

    public static final String AMOUNT_TYPE_FLAT = 'Flat';
    public static final String AMOUNT_TYPE_MULTIPLIER = 'Multiplier';
    public static final String AMOUNT_TYPE_PERCENT = 'Percent';

    public static final String SOURCE_SCHEDULE = 'SCHEDULE';
    public static final String SOURCE_DEALER_OVERRIDE = 'DEALER_OVERRIDE';

    public static final String BLOCK_TIRE_RIM_COMMERCIAL = 'Tire_Rim_Commercial_Use_Not_Eligible';
    public static final String BLOCK_VEHICLE_NOT_FOUND = 'Vehicle_Not_Found';
    public static final String BLOCK_PACKAGE_NOT_FOUND = 'Package_Not_Found';

    /** Scope ranks for R2 — lower wins. */
    private static final Integer RANK_DEALER = 0;
    private static final Integer RANK_PACKAGE = 1;
    private static final Integer RANK_PLAN_TYPE = 2;

    // ------------------------------------------------------------------
    // DTOs
    // ------------------------------------------------------------------

    /** Inputs to a resolution. termId is accepted for forward-compat with the
     *  P3 engine (base-coverage anchor); R1-R6 do not read it. */
    public class ResolveRequest {
        public Id dealerId { get; set; }
        public Id vehicleId { get; set; }
        public Id packageId { get; set; }
        public Id termId { get; set; }
        public Date asOfDate { get; set; }

        public ResolveRequest() {}
        public ResolveRequest(Id dealerId, Id vehicleId, Id packageId, Date asOfDate) {
            this.dealerId = dealerId;
            this.vehicleId = vehicleId;
            this.packageId = packageId;
            this.asOfDate = asOfDate;
        }
    }

    /** One resolved fee line. Plain values only — LWC-serialisable. */
    public class ResolvedFeeLine {
        public Id scheduleId { get; set; }
        public String scheduleName { get; set; }
        public String scheduleType { get; set; }
        public Id memberId { get; set; }
        public String tier { get; set; }
        /** P-1 (premium P-B): the matched row's classification group (row.Tier__c). */
        public String classification { get; set; }
        /** C-1 (T&R): the matched row's class (row.Class__c) — the vehicle's T&R class. */
        public String category { get; set; }
        public String amountType { get; set; }
        public Decimal amount { get; set; }
        public Decimal multiplier { get; set; }
        public String source { get; set; }
        public Boolean dealerOverrideApplied { get; set; }

        public ResolvedFeeLine() {
            this.amountType = AMOUNT_TYPE_FLAT;
            this.source = SOURCE_SCHEDULE;
            this.dealerOverrideApplied = false;
        }
    }

    /** Resolver outcome: fee lines + eligibility blocks + provenance facts. */
    public class ResolverResult {
        public List<ResolvedFeeLine> lines { get; set; }
        public List<String> blocks { get; set; }
        public Boolean dealerOverrideApplied { get; set; }
        public Date asOfDate { get; set; }

        public ResolverResult() {
            this.lines = new List<ResolvedFeeLine>();
            this.blocks = new List<String>();
            this.dealerOverrideApplied = false;
        }

        public Boolean hasBlocks() {
            return blocks != null && !blocks.isEmpty();
        }
    }

    // ------------------------------------------------------------------
    // Resolution
    // ------------------------------------------------------------------

    /**
     * Resolve fee lines for one context. Deterministic (R6). Never throws for
     * missing context records — returns block codes instead so callers can
     * surface data-quality blockers (D4 style) rather than crash a quote.
     */
    public static ResolverResult resolve(ResolveRequest req) {
        ResolverResult result = new ResolverResult();
        Date asOf = req.asOfDate != null ? req.asOfDate : Date.today();
        result.asOfDate = asOf;

        if (req.vehicleId == null) {
            result.blocks.add(BLOCK_VEHICLE_NOT_FOUND);
            return result;
        }

        Vehicle__c vehicle = VehicleScheduleSelector.selectVehicle(req.vehicleId);
        if (vehicle == null) {
            result.blocks.add(BLOCK_VEHICLE_NOT_FOUND);
            return result;
        }

        Id packageGroupId = null;
        if (req.packageId != null) {
            Package__c pkg = VehicleScheduleSelector.selectPackage(req.packageId);
            if (pkg == null) {
                result.blocks.add(BLOCK_PACKAGE_NOT_FOUND);
                return result;
            }
            packageGroupId = pkg.Package_Group__c;
        }

        Account dealer = req.dealerId != null
            ? VehicleScheduleSelector.selectDealerAccount(req.dealerId)
            : null;

        // R1 + R2: candidate assignments, one winner per schedule type.
        List<Vehicle_Schedule_Assignment__c> candidates =
            VehicleScheduleSelector.selectAssignmentCandidates(
                req.dealerId, req.packageId, packageGroupId, asOf);

        Map<String, Vehicle_Schedule_Assignment__c> winnerByType =
            pickWinningAssignmentPerType(candidates);

        if (winnerByType.isEmpty()) {
            // R4 fallback: no schedule assigned => no fee.
            return result;
        }

        // Vehicle keys (same grammar as VehicleScheduleMemberKeyHandler, incl.
        // the schedule-id prefix required by the org's UNIQUE Member_Key__c).
        String makeName = vehicle.Make_Lookup__c != null ? vehicle.Make_Lookup__r.Name : null;
        String modelName = vehicle.Model_Lookup__c != null ? vehicle.Model_Lookup__r.Name : null;

        Set<Id> winnerScheduleIds = new Set<Id>();
        List<String> memberKeys = new List<String>();
        for (String winnerType : winnerByType.keySet()) {
            Vehicle_Schedule_Assignment__c a = winnerByType.get(winnerType);
            winnerScheduleIds.add(a.Vehicle_Schedule__c);
            // C-C5 + C-C6: the vehicle's commercial type is threaded in and the
            // key is type-qualified WHENEVER that type is non-blank (C-C4/C-C6),
            // mirroring the member-row side; a blank type emits the five plain
            // keys exactly as before.
            memberKeys.addAll(buildMemberKeys(a.Vehicle_Schedule__c, makeName, modelName,
                vehicle.Commercial_Vehicle_Type__c, winnerType));
        }

        Map<Id, List<Vehicle_Schedule_Member__c>> membersBySchedule =
            groupMembersBySchedule(
                VehicleScheduleSelector.selectMembersByKeys(winnerScheduleIds, memberKeys));

        Boolean commercialUsage = isCommercialUsage(vehicle.Usage_Type__c);
        Boolean dieselFuel = 'Diesel'.equalsIgnoreCase(vehicle.Fuel_Type__c);

        // R2 winners are keyed by schedule type — process in deterministic type order.
        List<String> orderedTypes = new List<String>(winnerByType.keySet());
        orderedTypes.sort();

        for (String scheduleType : orderedTypes) {
            Vehicle_Schedule_Assignment__c assignment = winnerByType.get(scheduleType);
            Id scheduleId = assignment.Vehicle_Schedule__c;
            List<Vehicle_Schedule_Member__c> rows =
                membersBySchedule.containsKey(scheduleId) ? membersBySchedule.get(scheduleId) : null;

            // Schedule-family gates (design §6.4 / D2 P1 rule).
            if (TYPE_DIESEL_FEE.equals(scheduleType) && !dieselFuel) {
                continue;
            }
            if (TYPE_COMMERCIAL_SURCHARGE.equals(scheduleType) && !commercialUsage) {
                continue;
            }
            if (TYPE_TIRE_RIM_CATEGORY.equals(scheduleType) && commercialUsage) {
                result.blocks.add(BLOCK_TIRE_RIM_COMMERCIAL);
                continue;
            }

            // R3: first match wins (exclusion over inclusion, model over make,
            // catch-all last). No row at all => R4 no fee for this schedule.
            Vehicle_Schedule_Member__c winnerRow = pickWinningRow(rows);
            if (winnerRow == null) {
                continue;
            }

            ResolvedFeeLine line = buildLine(assignment, winnerRow);

            // R5: dealer override replaces the resolved PREMIUM fee amount.
            if (TYPE_PREMIUM_TIER.equals(scheduleType)
                && dealer != null
                && dealer.Charge_Premium_Vehicle_Fee__c == true
                && dealer.Premium_Fee_Override_Amount__c != null) {
                line.amount = dealer.Premium_Fee_Override_Amount__c;
                line.source = SOURCE_DEALER_OVERRIDE;
                line.dealerOverrideApplied = true;
                result.dealerOverrideApplied = true;
            }

            result.lines.add(line);
        }

        // R6: deterministic output order.
        result.lines.sort(new FeeLineComparator());
        return result;
    }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    /**
     * R2: among the effective/active candidate assignments, pick the winner per
     * schedule type by scope rank (dealer < package < plan type); ties by most
     * recent schedule Valid_From__c, then by assignment Id (deterministic).
     */
    private static Map<String, Vehicle_Schedule_Assignment__c> pickWinningAssignmentPerType(
        List<Vehicle_Schedule_Assignment__c> candidates) {

        Map<String, Vehicle_Schedule_Assignment__c> winners = new Map<String, Vehicle_Schedule_Assignment__c>();

        for (Vehicle_Schedule_Assignment__c a : candidates) {
            String type = a.Vehicle_Schedule__r != null ? a.Vehicle_Schedule__r.Type__c : null;
            if (String.isBlank(type)) {
                continue;
            }
            Integer rank = scopeRank(a);
            if (rank == null) {
                continue; // assignment without any scope — ignore
            }

            Vehicle_Schedule_Assignment__c current = winners.get(type);
            if (current == null || isBetterAssignment(a, rank, current)) {
                winners.put(type, a);
            }
        }
        return winners;
    }

    private static Integer scopeRank(Vehicle_Schedule_Assignment__c a) {
        if (a.Dealer__c != null) {
            return RANK_DEALER;
        }
        if (a.Package__c != null) {
            return RANK_PACKAGE;
        }
        if (a.Package_Group__c != null) {
            return RANK_PLAN_TYPE;
        }
        return null;
    }

    private static Boolean isBetterAssignment(
        Vehicle_Schedule_Assignment__c candidate,
        Integer candidateRank,
        Vehicle_Schedule_Assignment__c incumbent) {

        Integer incumbentRank = scopeRank(incumbent);
        if (candidateRank < incumbentRank) {
            return true;
        }
        if (candidateRank > incumbentRank) {
            return false;
        }
        // Same scope: most recent schedule Valid_From__c wins (R2 tie rule).
        Date cFrom = candidate.Vehicle_Schedule__r != null ? candidate.Vehicle_Schedule__r.Valid_From__c : null;
        Date iFrom = incumbent.Vehicle_Schedule__r != null ? incumbent.Vehicle_Schedule__r.Valid_From__c : null;
        if (cFrom != iFrom) {
            return cFrom != null && (iFrom == null || cFrom > iFrom);
        }
        // Full determinism (R6): assignment Id as final tie-break.
        return candidate.Id < incumbent.Id;
    }

    /**
     * R3: candidate member keys for one vehicle — ordered so a simple
     * first-match-wins scan over a query ordered by (Sort_Order, CreatedDate,
     * Id) yields the documented precedence. Exclusion rows are looked up with
     * the same keys as inclusion rows and win by position.
     */
    @TestVisible
    static List<String> buildMemberKeys(Id scheduleId, String makeName, String modelName) {
        String mk = String.isBlank(makeName) ? VehicleScheduleMemberKeyHandler.WILDCARD : makeName.trim();
        String mo = String.isBlank(modelName) ? VehicleScheduleMemberKeyHandler.WILDCARD : modelName.trim();
        String prefix = String.valueOf(scheduleId) + '|';
        return new List<String>{
            prefix + mk + '|' + mo + '|N|Y',  // model exclusion (rank 1)
            prefix + mk + '|' + mo + '|N|N',  // model inclusion (rank 2)
            prefix + mk + '|' + VehicleScheduleMemberKeyHandler.WILDCARD + '|Y|Y', // make exclusion (rank 3)
            prefix + mk + '|' + VehicleScheduleMemberKeyHandler.WILDCARD + '|Y|N', // make inclusion (rank 4)
            prefix + VehicleScheduleMemberKeyHandler.WILDCARD + '|' + VehicleScheduleMemberKeyHandler.WILDCARD + '|Y|N' // catch-all (rank 5)
        };
    }

    /**
     * C-C4 (Rev 7 commercial) + C-C6 (typed-key symmetry fix): type-qualified
     * variant of the five key shapes. A sixth pipe-segment
     * (`|<CommercialVehicleType>`) is appended whenever the vehicle's commercial
     * type is non-blank — for EVERY schedule family — mirroring
     * VehicleScheduleMemberKeyHandler.buildKey, which appends that segment
     * whenever the ROW's Commercial_Vehicle_Type__c is non-blank. Previously the
     * segment was emitted only for a Commercial_Surcharge schedule, so a typed
     * member row in any other family (e.g. Commercial_Eligibility) could never
     * match. For a blank type the five plain keys above are returned
     * => byte-identical to today. The plain keys are still emitted alongside
     * (harmless: a typed row never carries a plain key, and an untyped row never
     * carries a typed one).
     *
     * scheduleType is retained for call-site/API stability but no longer gates
     * the type segment — the row side was never family-aware.
     */
    @TestVisible
    static List<String> buildMemberKeys(Id scheduleId, String makeName, String modelName,
                                        String commercialVehicleType, String scheduleType) {
        List<String> keys = new List<String>(buildMemberKeys(scheduleId, makeName, modelName));
        if (String.isNotBlank(commercialVehicleType)) {
            String mk = String.isBlank(makeName) ? VehicleScheduleMemberKeyHandler.WILDCARD : makeName.trim();
            String mo = String.isBlank(modelName) ? VehicleScheduleMemberKeyHandler.WILDCARD : modelName.trim();
            String prefix = String.valueOf(scheduleId) + '|';
            String t = '|' + commercialVehicleType;
            keys.add(prefix + mk + '|' + mo + '|N|Y' + t);
            keys.add(prefix + mk + '|' + mo + '|N|N' + t);
            keys.add(prefix + mk + '|' + VehicleScheduleMemberKeyHandler.WILDCARD + '|Y|Y' + t);
            keys.add(prefix + mk + '|' + VehicleScheduleMemberKeyHandler.WILDCARD + '|Y|N' + t);
            keys.add(prefix + VehicleScheduleMemberKeyHandler.WILDCARD + '|' + VehicleScheduleMemberKeyHandler.WILDCARD + '|Y|N' + t);
        }
        return keys;
    }

    /**
     * C-3 (Rev 4 T&R / D-15): resolve a vehicle's Tire & Rim class —
     * schedule-authoritative with a native fallback. Returns the Class__c of the
     * matching row in an active, effective Tire_Rim_Category schedule; if none
     * matches (no schedule, vehicle not on the table, or a row without a class),
     * falls back to the vehicle's native Model class
     * (`Vehicle__r.Model_Lookup__r.Class__c`) — the value the portal already
     * uses — else null. Deterministic (schedules ordered by Id).
     */
    public static String resolveTireRimClass(Id vehicleId, Date asOf) {
        if (vehicleId == null) {
            return null;
        }
        Date at = asOf != null ? asOf : Date.today();
        Vehicle__c vehicle = VehicleScheduleSelector.selectVehicle(vehicleId);
        if (vehicle == null) {
            return null;
        }
        String nativeClass = vehicle.Model_Lookup__c != null
            ? vehicle.Model_Lookup__r.Class__c : null;

        List<Vehicle_Schedule__c> schedules =
            VehicleScheduleSelector.selectActiveSchedulesByType(TYPE_TIRE_RIM_CATEGORY, at);
        if (schedules.isEmpty()) {
            return nativeClass;
        }

        String makeName = vehicle.Make_Lookup__c != null ? vehicle.Make_Lookup__r.Name : null;
        String modelName = vehicle.Model_Lookup__c != null ? vehicle.Model_Lookup__r.Name : null;
        Set<Id> scheduleIds = new Set<Id>();
        List<String> keys = new List<String>();
        for (Vehicle_Schedule__c s : schedules) {
            scheduleIds.add(s.Id);
            keys.addAll(buildMemberKeys(s.Id, makeName, modelName));
        }
        Map<Id, List<Vehicle_Schedule_Member__c>> bySchedule = groupMembersBySchedule(
            VehicleScheduleSelector.selectMembersByKeys(scheduleIds, keys));

        for (Vehicle_Schedule__c s : schedules) {
            Vehicle_Schedule_Member__c row = pickWinningRow(bySchedule.get(s.Id));
            if (row != null && String.isNotBlank(row.Class__c)) {
                return row.Class__c;
            }
        }
        return nativeClass;
    }

    private static Map<Id, List<Vehicle_Schedule_Member__c>> groupMembersBySchedule(
        List<Vehicle_Schedule_Member__c> members) {

        Map<Id, List<Vehicle_Schedule_Member__c>> bySchedule = new Map<Id, List<Vehicle_Schedule_Member__c>>();
        for (Vehicle_Schedule_Member__c m : members) {
            if (!bySchedule.containsKey(m.Vehicle_Schedule__c)) {
                bySchedule.put(m.Vehicle_Schedule__c, new List<Vehicle_Schedule_Member__c>());
            }
            bySchedule.get(m.Vehicle_Schedule__c).add(m);
        }
        return bySchedule;
    }

    /**
     * First-match-wins over the query-ordered rows; because keys are generated in
     * precedence order and the query is deterministic, a model exclusion match is
     * always found before a model inclusion, etc. Any exclusion row in the bucket
     * => null (vehicle removed from this schedule, no fee).
     */
    private static Vehicle_Schedule_Member__c pickWinningRow(List<Vehicle_Schedule_Member__c> rows) {
        if (rows == null || rows.isEmpty()) {
            return null;
        }

        // Bucket by key shape: exclusion model rows, inclusion model rows,
        // exclusion make rows, inclusion make rows, catch-all rows.
        List<Vehicle_Schedule_Member__c> modelExclusions = new List<Vehicle_Schedule_Member__c>();
        List<Vehicle_Schedule_Member__c> modelInclusions = new List<Vehicle_Schedule_Member__c>();
        List<Vehicle_Schedule_Member__c> makeExclusions = new List<Vehicle_Schedule_Member__c>();
        List<Vehicle_Schedule_Member__c> makeInclusions = new List<Vehicle_Schedule_Member__c>();
        List<Vehicle_Schedule_Member__c> catchAllRows = new List<Vehicle_Schedule_Member__c>();

        for (Vehicle_Schedule_Member__c m : rows) {
            if (m.Make__c == null && m.Model__c == null) {
                catchAllRows.add(m);
            } else if (m.Make__c != null && m.Model__c != null) {
                if (m.Is_Exclusion__c == true) {
                    modelExclusions.add(m);
                } else {
                    modelInclusions.add(m);
                }
            } else if (m.Make__c != null) {
                if (m.Is_Exclusion__c == true) {
                    makeExclusions.add(m);
                } else {
                    makeInclusions.add(m);
                }
            }
        }

        // R3 order: model exclusion > model inclusion > make exclusion >
        // make inclusion > catch-all. First bucket that has any row wins; an
        // exclusion bucket means "removed from the schedule" => null.
        if (!modelExclusions.isEmpty()) {
            return null;
        }
        if (!modelInclusions.isEmpty()) {
            return modelInclusions[0];
        }
        if (!makeExclusions.isEmpty()) {
            return null;
        }
        if (!makeInclusions.isEmpty()) {
            return makeInclusions[0];
        }
        if (!catchAllRows.isEmpty()) {
            return catchAllRows[0];
        }
        return null;
    }

    private static ResolvedFeeLine buildLine(
        Vehicle_Schedule_Assignment__c assignment,
        Vehicle_Schedule_Member__c row) {

        ResolvedFeeLine line = new ResolvedFeeLine();
        line.scheduleId = assignment.Vehicle_Schedule__c;
        line.scheduleName = assignment.Vehicle_Schedule__r != null
            ? assignment.Vehicle_Schedule__r.Name : null;
        line.scheduleType = assignment.Vehicle_Schedule__r != null
            ? assignment.Vehicle_Schedule__r.Type__c : null;
        line.memberId = row.Id;
        line.tier = row.Tier__c;
        line.classification = row.Tier__c; // P-2: surface the classification group
        line.category = row.Class__c;      // C-2: surface the matched row's class (T&R)
        line.amountType = String.isNotBlank(row.Amount_Type__c) ? row.Amount_Type__c : AMOUNT_TYPE_FLAT;
        line.amount = row.Premium_Model_Fee__c;
        line.multiplier = row.Multiplier__c;
        return line;
    }

    private static Boolean isCommercialUsage(String usageType) {
        return String.isNotBlank(usageType)
            && usageType.equalsIgnoreCase('Commercial/Business Use');
    }

    /** Explicit comparator for R6 deterministic output ordering. */
    private class FeeLineComparator implements Comparator<ResolvedFeeLine> {
        public Integer compare(ResolvedFeeLine a, ResolvedFeeLine b) {
            Integer byType = safeCompare(a.scheduleType, b.scheduleType);
            if (byType != 0) {
                return byType;
            }
            Integer byName = safeCompare(a.scheduleName, b.scheduleName);
            if (byName != 0) {
                return byName;
            }
            if (a.memberId != b.memberId) {
                return a.memberId < b.memberId ? -1 : 1;
            }
            return 0;
        }

        private Integer safeCompare(String x, String y) {
            if (x == y) {
                return 0;
            }
            if (x == null) {
                return -1;
            }
            if (y == null) {
                return 1;
            }
            return x.compareTo(y);
        }
    }
}