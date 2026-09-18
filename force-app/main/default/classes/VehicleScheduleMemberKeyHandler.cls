/**
 * VehicleScheduleMemberKeyHandler
 *
 * Maintains Vehicle_Schedule_Member__c.Member_Key__c on insert/update so the
 * resolver can use an indexed text-key lookup (change-plan §04.1).
 *
 * Key grammar (pipe-separated, uppercase-normalised source names):
 *   <MakeName|'*'>|<ModelName|'*'>|<IncludeAll Y|N>|<IsExclusion Y|N>
 *
 *   - Make + Model populated          => exact model row        e.g. Porsche|911 GT3|N|N
 *   - Make populated, IncludeAll TRUE => make row               e.g. Porsche|*|Y|N
 *   - Exclusion flag TRUE             => exclusion row          e.g. Ford|Mustang Shelby GT350|N|Y
 *   - Make/Model blank + IncludeAll   => catch-all row          e.g. *|*|Y|N  (diesel fee schedule)
 *
 * The resolver builds the same keys from the vehicle's make/model records, so the
 * two sides stay in lock-step as long as both read the same Make__c/Model__c Names.
 */
public inherited sharing class VehicleScheduleMemberKeyHandler {

    public static final String WILDCARD = '*';

    private VehicleScheduleMemberKeyHandler() {}

    /**
     * Derive and assign Member_Key__c for a batch of members (before-insert/update).
     * Queries the referenced Make__c/Model__c records once for the whole batch.
     */
    public static void deriveMemberKeys(List<Vehicle_Schedule_Member__c> members) {
        if (members == null || members.isEmpty()) {
            return;
        }

        Set<Id> makeIds = new Set<Id>();
        Set<Id> modelIds = new Set<Id>();
        for (Vehicle_Schedule_Member__c m : members) {
            if (m.Make__c != null) {
                makeIds.add(m.Make__c);
            }
            if (m.Model__c != null) {
                modelIds.add(m.Model__c);
            }
        }

        Map<Id, Make__c> makes = new Map<Id, Make__c>();
        if (!makeIds.isEmpty()) {
            makes = new Map<Id, Make__c>([SELECT Id, Name FROM Make__c WHERE Id IN :makeIds]);
        }
        Map<Id, Model__c> models = new Map<Id, Model__c>();
        if (!modelIds.isEmpty()) {
            models = new Map<Id, Model__c>([SELECT Id, Name FROM Model__c WHERE Id IN :modelIds]);
        }

        for (Vehicle_Schedule_Member__c m : members) {
            String makeName = m.Make__c != null && makes.containsKey(m.Make__c)
                ? makes.get(m.Make__c).Name
                : null;
            String modelName = m.Model__c != null && models.containsKey(m.Model__c)
                ? models.get(m.Model__c).Name
                : null;
            m.Member_Key__c = buildKey(
                m.Vehicle_Schedule__c,
                makeName,
                modelName,
                m.Include_All_Models__c == true,
                m.Is_Exclusion__c == true,
                m.Commercial_Vehicle_Type__c
            );
        }
    }

    /**
     * Build the canonical key. Null/blank names become the '*' wildcard so a
     * make row (no model) and a catch-all row (no make/model) still get keys.
     *
     * NOTE ON SCOPE: the org defines Member_Key__c as UNIQUE + External ID
     * (verified baseline), while the P1 key grammar (Make|Model|IncludeAll|
     * IsExclusion) is per-schedule in nature — the same make row legitimately
     * appears in many schedules (design §6.1: one schedule per plan family
     * sharing member structure). To satisfy the unique constraint the key is
     * prefixed with the owning schedule id:
     *   <ScheduleId>|<MakeName|'*'>|<ModelName|'*'>|<IncludeAll>|<IsExclusion>
     * The resolver already scopes every member query by schedule, so the
     * prefix is free — it only keeps rows of DIFFERENT schedules distinct.
     * (Schema drift vs plan §04.1 grammar — recorded for the P1 report.)
     */
    public static String buildKey(Id scheduleId, String makeName, String modelName, Boolean includeAll, Boolean isExclusion) {
        return buildKey(scheduleId, makeName, modelName, includeAll, isExclusion, null);
    }

    /**
     * C-C1 (Rev 7): type-qualified key. A sixth `|<CommercialVehicleType>`
     * segment is appended ONLY when the member's Commercial_Vehicle_Type__c is
     * non-blank — so every premium / T&R / diesel / powersports row (and any
     * commercial row without a type) derives the SAME five-segment key as
     * before. The resolver emits the matching typed key only for a
     * Commercial_Surcharge schedule (C-C4).
     */
    public static String buildKey(Id scheduleId, String makeName, String modelName,
                                  Boolean includeAll, Boolean isExclusion, String commercialVehicleType) {
        String mk = String.isBlank(makeName) ? WILDCARD : makeName.trim();
        String mo = String.isBlank(modelName) ? WILDCARD : modelName.trim();
        String key = String.valueOf(scheduleId) + '|' + mk + '|' + mo + '|'
            + (includeAll ? 'Y' : 'N') + '|' + (isExclusion ? 'Y' : 'N');
        if (String.isNotBlank(commercialVehicleType)) {
            key += '|' + commercialVehicleType;
        }
        return key;
    }
}