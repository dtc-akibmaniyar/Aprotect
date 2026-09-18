/**
 * VehicleScheduleSelector
 *
 * SOQL path for the Vehicle Schedule resolver (change-plan §04.1, P1). No business
 * logic — pure queries. `without sharing` so the engine can read the schedule
 * tables (OWD private) on behalf of portal users without granting them FLS.
 *
 * P7-g (2026-09-10): every query is pinned to WITH SYSTEM_MODE. API v67 runs
 * plain Apex SOQL in USER mode by default (Summer '26); the portal profile has
 * no FLS/object access to these private schedule tables (D7), so a user-mode
 * read fails for portal users exactly like the engine's own selectors did.
 *
 * Resolution input context (R1-R6) is: dealer Account, Vehicle, Package, as-of date.
 */
public without sharing class VehicleScheduleSelector {

    private VehicleScheduleSelector() {}

    /**
     * Candidate assignments for one resolve context, honouring R1 at query level:
     * the schedule must be active and its Valid_From/To window plus the
     * assignment's Effective_From/To window must contain the as-of date.
     * Scope OR: dealer-scoped (R2 rank 0), package-scoped (rank 1), plan-type /
     * Package_Group-scoped (rank 2).
     */
    public static List<Vehicle_Schedule_Assignment__c> selectAssignmentCandidates(
        Id dealerId, Id packageId, Id packageGroupId, Date asOf) {

        return [
            SELECT Id, Dealer__c, Package__c, Package_Group__c,
                   Effective_From__c, Effective_To__c,
                   Vehicle_Schedule__c,
                   Vehicle_Schedule__r.Name,
                   Vehicle_Schedule__r.Type__c,
                   Vehicle_Schedule__r.Valid_From__c,
                   Vehicle_Schedule__r.Valid_To__c
            FROM Vehicle_Schedule_Assignment__c
            WHERE Vehicle_Schedule__r.Is_Active__c = TRUE
              AND (Dealer__c = :dealerId OR Package__c = :packageId OR Package_Group__c = :packageGroupId)
              AND (Effective_From__c = NULL OR Effective_From__c <= :asOf)
              AND (Effective_To__c = NULL OR Effective_To__c >= :asOf)
              AND (Vehicle_Schedule__r.Valid_From__c = NULL OR Vehicle_Schedule__r.Valid_From__c <= :asOf)
              AND (Vehicle_Schedule__r.Valid_To__c = NULL OR Vehicle_Schedule__r.Valid_To__c >= :asOf)
            WITH SYSTEM_MODE
            ORDER BY Vehicle_Schedule__r.Type__c
        ];
    }

    /**
     * Member rows of the candidate schedules matching any of the vehicle's
     * generated member keys (model/make/catch-all x inclusion/exclusion).
     * Ordered deterministically (Sort_Order then CreatedDate then Id) — final
     * row precedence is applied in the resolver (R3/R6).
     */
    public static List<Vehicle_Schedule_Member__c> selectMembersByKeys(
        Set<Id> scheduleIds, List<String> memberKeys) {

        return [
            SELECT Id, Name, Vehicle_Schedule__c,
                   Make__c, Make__r.Name, Model__c, Model__r.Name,
                   Include_All_Models__c, Is_Exclusion__c,
                   Class__c, Tier__c, Amount_Type__c, Multiplier__c,
                   Premium_Model_Fee__c, Sort_Order__c, Member_Key__c
            FROM Vehicle_Schedule_Member__c
            WHERE Vehicle_Schedule__c IN :scheduleIds
              AND Member_Key__c IN :memberKeys
            WITH SYSTEM_MODE
            ORDER BY Sort_Order__c ASC NULLS LAST, CreatedDate ASC, Id ASC
        ];
    }

    /** Vehicle context: canonical make/model lookups + eligibility inputs (D2/D4 reads). */
    public static Vehicle__c selectVehicle(Id vehicleId) {
        List<Vehicle__c> rows = [
            SELECT Id, Name, Year__c,
                   Make_Lookup__c, Make_Lookup__r.Name,
                   Model_Lookup__c, Model_Lookup__r.Name, Model_Lookup__r.Class__c,
                   Fuel_Type__c, Usage_Type__c, Vehicle_Category__c, GVWR__c,
                   Commercial_Vehicle_Type__c
            FROM Vehicle__c
            WHERE Id = :vehicleId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * Active + effective schedules of one type, with no scope filter (C-3 T&R
     * class resolution: the class table is not scope-dependent). Deterministic
     * ordering by Id so the resolved class is stable (R6).
     */
    public static List<Vehicle_Schedule__c> selectActiveSchedulesByType(String type, Date asOf) {
        return [
            SELECT Id, Name, Type__c, Is_Active__c, Valid_From__c, Valid_To__c
            FROM Vehicle_Schedule__c
            WHERE Type__c = :type
              AND Is_Active__c = TRUE
              AND (Valid_From__c = NULL OR Valid_From__c <= :asOf)
              AND (Valid_To__c = NULL OR Valid_To__c >= :asOf)
            WITH SYSTEM_MODE
            ORDER BY Id
        ];
    }

    /** Package context: plan-type group for group-scoped assignment matching (R2). */
    public static Package__c selectPackage(Id packageId) {
        List<Package__c> rows = [
            SELECT Id, Name, Package_Group__c, Package_Group__r.Name
            FROM Package__c
            WHERE Id = :packageId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    /** Dealer context: R5 override gate fields. */
    public static Account selectDealerAccount(Id dealerId) {
        List<Account> rows = [
            SELECT Id, Name, Charge_Premium_Vehicle_Fee__c, Premium_Fee_Override_Amount__c
            FROM Account
            WHERE Id = :dealerId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }
}