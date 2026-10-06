public with sharing class MasterPackageScheduleService {
private static final String DASH = '\u2014';
private static final Integer DEFAULT_PAGE = 25;
private static final Integer MAX_PAGE = 200;
@TestVisible
private static Boolean simulateFieldAccessDenied = false;
public class Choice {
@AuraEnabled public String value;
@AuraEnabled public String label;
public Choice(String value, String label) { this.value = value; this.label = label; }
}
public class SaveResult {
@AuraEnabled public Boolean success;
@AuraEnabled public String message;
@AuraEnabled public Id recordId;
@AuraEnabled public Boolean requiresConfirmation = false;
@AuraEnabled public List<String> warnings = new List<String>();
public SaveResult(Boolean success, String message, Id recordId) {
this.success = success; this.message = message; this.recordId = recordId;
}
}
public class ScheduleRow {
@AuraEnabled public Id id;
@AuraEnabled public String name;
@AuraEnabled public String type;
@AuraEnabled public String typeLabel;
@AuraEnabled public Boolean isActive;
@AuraEnabled public String statusLabel;
@AuraEnabled public String statusTone;
@AuraEnabled public String validFromLabel;
@AuraEnabled public String validToLabel;
@AuraEnabled public Integer memberCount;
@AuraEnabled public Integer assignmentCount;
@AuraEnabled public String summaryLabel;
}
public class SchedulePage {
@AuraEnabled public List<ScheduleRow> rows = new List<ScheduleRow>();
@AuraEnabled public Integer total = 0;
@AuraEnabled public Integer offset = 0;
@AuraEnabled public Boolean hasMore = false;
}
public class MemberRow {
@AuraEnabled public Id id;
@AuraEnabled public String name;
@AuraEnabled public String makeId;
@AuraEnabled public String makeLabel;
@AuraEnabled public String modelId;
@AuraEnabled public String modelLabel;
@AuraEnabled public String classValue;
@AuraEnabled public String tier;
@AuraEnabled public Decimal multiplier;
@AuraEnabled public String amountType;
@AuraEnabled public Decimal premiumModelFee;
@AuraEnabled public Boolean isExclusion;
@AuraEnabled public Boolean includeAllModels;
@AuraEnabled public String memberKey;
@AuraEnabled public String vehicleLabel;
@AuraEnabled public String effectLabel;
@AuraEnabled public String flagsLabel;
}
public class AssignmentRow {
@AuraEnabled public Id id;
@AuraEnabled public String scheduleId;
@AuraEnabled public String scheduleName;
@AuraEnabled public String scheduleTypeLabel;
@AuraEnabled public String targetType;
@AuraEnabled public String targetId;
@AuraEnabled public String targetName;
@AuraEnabled public String effectiveFrom;
@AuraEnabled public String effectiveTo;
@AuraEnabled public String effectiveFromLabel;
@AuraEnabled public String effectiveToLabel;
@AuraEnabled public String windowLabel;
}
public class ScheduleDetail {
@AuraEnabled public Id id;
@AuraEnabled public String name;
@AuraEnabled public String type;
@AuraEnabled public String typeLabel;
@AuraEnabled public Boolean isActive;
@AuraEnabled public String statusLabel;
@AuraEnabled public String validFrom;
@AuraEnabled public String validTo;
@AuraEnabled public String validFromLabel;
@AuraEnabled public String validToLabel;
@AuraEnabled public String description;
@AuraEnabled public Integer memberTotal;
@AuraEnabled public Integer assignmentTotal;
@AuraEnabled public Integer memberOffset;
@AuraEnabled public Boolean membersHaveMore;
@AuraEnabled public List<MemberRow> members = new List<MemberRow>();
@AuraEnabled public List<AssignmentRow> assignments = new List<AssignmentRow>();
public ScheduleDetail() {
memberTotal = 0; assignmentTotal = 0; memberOffset = 0; membersHaveMore = false;
}
}
public class ContextPanel {
@AuraEnabled public String contextType;
@AuraEnabled public String contextId;
@AuraEnabled public String contextName;
@AuraEnabled public Integer total = 0;
@AuraEnabled public List<AssignmentRow> assignments = new List<AssignmentRow>();
}
public class FormOptions {
@AuraEnabled public List<Choice> typeOptions = new List<Choice>();
@AuraEnabled public List<Choice> amountTypeOptions = new List<Choice>();
@AuraEnabled public List<Choice> tierOptions = new List<Choice>();
@AuraEnabled public List<Choice> memberClassOptions = new List<Choice>();
@AuraEnabled public List<Choice> scheduleChoices = new List<Choice>();
@AuraEnabled public List<Choice> packageChoices = new List<Choice>();
@AuraEnabled public List<Choice> groupChoices = new List<Choice>();
@AuraEnabled public List<Choice> makeChoices = new List<Choice>();
public FormOptions() {}
}
public class ScheduleForm {
@AuraEnabled public String recordId { get; set; }
@AuraEnabled public String name { get; set; }
@AuraEnabled public String type { get; set; }
@AuraEnabled public Boolean isActive { get; set; }
@AuraEnabled public String validFrom { get; set; }
@AuraEnabled public String validTo { get; set; }
@AuraEnabled public String description { get; set; }
@AuraEnabled public Boolean confirmedVersionedChange { get; set; }
public ScheduleForm() {}
}
public class MemberForm {
@AuraEnabled public String recordId { get; set; }
@AuraEnabled public String scheduleId { get; set; }
@AuraEnabled public String makeId { get; set; }
@AuraEnabled public String modelId { get; set; }
@AuraEnabled public String classValue { get; set; }
@AuraEnabled public String tier { get; set; }
@AuraEnabled public Decimal multiplier { get; set; }
@AuraEnabled public String amountType { get; set; }
@AuraEnabled public Decimal premiumModelFee { get; set; }
@AuraEnabled public Boolean isExclusion { get; set; }
@AuraEnabled public Boolean includeAllModels { get; set; }
public MemberForm() {}
}
public class AssignmentForm {
@AuraEnabled public String recordId { get; set; }
@AuraEnabled public String scheduleId { get; set; }
@AuraEnabled public String packageId { get; set; }
@AuraEnabled public String groupId { get; set; }
@AuraEnabled public String effectiveFrom { get; set; }
@AuraEnabled public String effectiveTo { get; set; }
public AssignmentForm() {}
}
@AuraEnabled(cacheable=true)
public static SchedulePage getSchedules(String searchKey, Integer offset, Integer limitSize) {
SchedulePage page = new SchedulePage();
Integer off = normalizeOffset(offset);
Integer lim = normalizeLimit(limitSize);
page.offset = off;
String likeKey = String.isBlank(searchKey) ? null : '%' + searchKey.trim() + '%';
if (likeKey == null) {
page.total = [SELECT COUNT() FROM Vehicle_Schedule__c];
} else {
page.total = [SELECT COUNT() FROM Vehicle_Schedule__c WHERE Name LIKE :likeKey];
}
List<Vehicle_Schedule__c> rows = likeKey == null
? [SELECT Id, Name, Type__c, Is_Active__c, Valid_From__c, Valid_To__c,
(SELECT Id FROM Vehicle_Schedule_Member__r),
(SELECT Id FROM Vehicle_Schedule__r)
FROM Vehicle_Schedule__c ORDER BY Name LIMIT :lim OFFSET :off]
: [SELECT Id, Name, Type__c, Is_Active__c, Valid_From__c, Valid_To__c,
(SELECT Id FROM Vehicle_Schedule_Member__r),
(SELECT Id FROM Vehicle_Schedule__r)
FROM Vehicle_Schedule__c WHERE Name LIKE :likeKey ORDER BY Name LIMIT :lim OFFSET :off];
for (Vehicle_Schedule__c s : rows) { page.rows.add(toScheduleRow(s)); }
page.hasMore = (off + page.rows.size()) < page.total;
return page;
}
@AuraEnabled(cacheable=true)
public static ScheduleDetail getScheduleDetail(Id scheduleId, Integer memberOffset, Integer memberLimit) {
ScheduleDetail d = new ScheduleDetail();
if (scheduleId == null) { return d; }
List<Vehicle_Schedule__c> found = [
SELECT Id, Name, Type__c, Is_Active__c, Valid_From__c, Valid_To__c, Description__c
FROM Vehicle_Schedule__c WHERE Id = :scheduleId LIMIT 1];
if (found.isEmpty()) { return d; }
Vehicle_Schedule__c s = found[0];
d.id = s.Id; d.name = s.Name; d.type = s.Type__c; d.typeLabel = valueOrDash(s.Type__c);
d.isActive = s.Is_Active__c == true;
d.statusLabel = d.isActive ? 'Active' : 'Inactive';
d.validFrom = s.Valid_From__c == null ? null : String.valueOf(s.Valid_From__c);
d.validTo = s.Valid_To__c == null ? null : String.valueOf(s.Valid_To__c);
d.validFromLabel = dateLabel(s.Valid_From__c);
d.validToLabel = dateLabel(s.Valid_To__c);
d.description = s.Description__c;
d.memberTotal = [SELECT COUNT() FROM Vehicle_Schedule_Member__c WHERE Vehicle_Schedule__c = :scheduleId];
d.assignmentTotal = [SELECT COUNT() FROM Vehicle_Schedule_Assignment__c WHERE Vehicle_Schedule__c = :scheduleId];
Integer off = normalizeOffset(memberOffset);
Integer lim = normalizeLimit(memberLimit);
d.memberOffset = off;
for (Vehicle_Schedule_Member__c m : [
SELECT Id, Name, Make__c, Make__r.Name, Model__c, Model__r.Name, Class__c, Tier__c,
Multiplier__c, Amount_Type__c, Premium_Model_Fee__c, Is_Exclusion__c,
Include_All_Models__c, Member_Key__c
FROM Vehicle_Schedule_Member__c WHERE Vehicle_Schedule__c = :scheduleId
ORDER BY Make__r.Name NULLS LAST, Model__r.Name NULLS LAST, Name
LIMIT :lim OFFSET :off]) {
d.members.add(toMemberRow(m));
}
d.membersHaveMore = (off + d.members.size()) < d.memberTotal;
d.assignments = assignmentRows([
SELECT Id, Vehicle_Schedule__c, Vehicle_Schedule__r.Name, Vehicle_Schedule__r.Type__c,
Package__c, Package__r.Name, Package_Group__c, Package_Group__r.Name,
Effective_From__c, Effective_To__c
FROM Vehicle_Schedule_Assignment__c WHERE Vehicle_Schedule__c = :scheduleId
ORDER BY Effective_From__c DESC NULLS LAST]);
return d;
}
@AuraEnabled(cacheable=true)
public static ContextPanel getContextAssignments(String contextType, Id contextId) {
ContextPanel p = new ContextPanel();
p.contextType = contextType;
p.contextId = contextId == null ? null : String.valueOf(contextId);
if (contextId == null || String.isBlank(contextType)) { return p; }
List<Vehicle_Schedule_Assignment__c> rows;
if ('group'.equalsIgnoreCase(contextType)) {
p.contextName = groupLabel(contextId);
rows = [
SELECT Id, Vehicle_Schedule__c, Vehicle_Schedule__r.Name, Vehicle_Schedule__r.Type__c,
Package__c, Package__r.Name, Package_Group__c, Package_Group__r.Name,
Effective_From__c, Effective_To__c
FROM Vehicle_Schedule_Assignment__c WHERE Package_Group__c = :contextId
ORDER BY Effective_From__c DESC NULLS LAST];
} else if ('package'.equalsIgnoreCase(contextType)) {
p.contextName = packageLabel(contextId);
rows = [
SELECT Id, Vehicle_Schedule__c, Vehicle_Schedule__r.Name, Vehicle_Schedule__r.Type__c,
Package__c, Package__r.Name, Package_Group__c, Package_Group__r.Name,
Effective_From__c, Effective_To__c
FROM Vehicle_Schedule_Assignment__c WHERE Package__c = :contextId
ORDER BY Effective_From__c DESC NULLS LAST];
} else {
return p;
}
p.assignments = assignmentRows(rows);
p.total = p.assignments.size();
return p;
}
@AuraEnabled(cacheable=true)
public static FormOptions getFormOptions() {
FormOptions o = new FormOptions();
o.typeOptions = picklistChoices(Vehicle_Schedule__c.Type__c);
o.amountTypeOptions = picklistChoices(Vehicle_Schedule_Member__c.Amount_Type__c);
o.tierOptions = picklistChoices(Vehicle_Schedule_Member__c.Tier__c);
o.memberClassOptions = picklistChoices(Vehicle_Schedule_Member__c.Class__c);
for (Vehicle_Schedule__c s : [
SELECT Id, Name, Type__c FROM Vehicle_Schedule__c ORDER BY Name LIMIT 500]) {
o.scheduleChoices.add(new Choice(String.valueOf(s.Id), s.Name));
}
for (Package__c p : [SELECT Id, Name FROM Package__c ORDER BY Name LIMIT 500]) {
o.packageChoices.add(new Choice(String.valueOf(p.Id), p.Name));
}
for (Package_Group__c g : [SELECT Id, Name FROM Package_Group__c ORDER BY Name LIMIT 500]) {
o.groupChoices.add(new Choice(String.valueOf(g.Id), g.Name));
}
for (Make__c mk : [SELECT Id, Name FROM Make__c ORDER BY Name LIMIT 500]) {
o.makeChoices.add(new Choice(String.valueOf(mk.Id), mk.Name));
}
return o;
}
@AuraEnabled(cacheable=true)
public static List<Choice> searchMakes(String term, Integer limitSize) {
Integer lim = normalizeLimit(limitSize);
String likeKey = String.isBlank(term) ? null : '%' + term.trim() + '%';
List<Choice> out = new List<Choice>();
List<Make__c> rows = likeKey == null
? [SELECT Id, Name FROM Make__c ORDER BY Name LIMIT :lim]
: [SELECT Id, Name FROM Make__c WHERE Name LIKE :likeKey ORDER BY Name LIMIT :lim];
for (Make__c m : rows) { out.add(new Choice(String.valueOf(m.Id), m.Name)); }
return out;
}
@AuraEnabled(cacheable=true)
public static List<Choice> searchModels(String makeId, String term, Integer limitSize) {
Integer lim = normalizeLimit(limitSize);
String likeKey = String.isBlank(term) ? null : '%' + term.trim() + '%';
List<Choice> out = new List<Choice>();
List<Model__c> rows;
if (String.isNotBlank(makeId)) {
rows = likeKey == null
? [SELECT Id, Name FROM Model__c WHERE Make__c = :makeId ORDER BY Name LIMIT :lim]
: [SELECT Id, Name FROM Model__c WHERE Make__c = :makeId AND Name LIKE :likeKey ORDER BY Name LIMIT :lim];
} else {
rows = likeKey == null
? [SELECT Id, Name FROM Model__c ORDER BY Name LIMIT :lim]
: [SELECT Id, Name FROM Model__c WHERE Name LIKE :likeKey ORDER BY Name LIMIT :lim];
}
for (Model__c m : rows) { out.add(new Choice(String.valueOf(m.Id), m.Name)); }
return out;
}
@AuraEnabled
public static SaveResult saveSchedule(ScheduleForm form) {
try {
if (form == null) { return fail('No schedule details were provided.'); }
Boolean isNew = String.isBlank(form.recordId);
Vehicle_Schedule__c existing;
if (!isNew) {
List<Vehicle_Schedule__c> found = [
SELECT Id, Name, Type__c, Is_Active__c, Valid_From__c, Valid_To__c, Description__c
FROM Vehicle_Schedule__c WHERE Id = :form.recordId LIMIT 1];
if (found.isEmpty()) { return fail('That vehicle schedule no longer exists.'); }
existing = found[0];
}
if (String.isBlank(form.name)) { return fail('Schedule Name is required.'); }
String dateErr = dateError('Valid From', form.validFrom);
if (dateErr == null) { dateErr = dateError('Valid To', form.validTo); }
if (dateErr != null) { return fail(dateErr); }
Date vFrom = toDate(form.validFrom);
Date vTo = toDate(form.validTo);
if (vFrom != null && vTo != null && vTo < vFrom) {
return fail('Valid To cannot be before Valid From.');
}
String guard = picklistGuard(Vehicle_Schedule__c.Type__c, form.type);
if (guard == null) { guard = guardCreateOrEdit(isNew, new List<SObjectField>{
Vehicle_Schedule__c.Name, Vehicle_Schedule__c.Type__c, Vehicle_Schedule__c.Is_Active__c,
Vehicle_Schedule__c.Valid_From__c, Vehicle_Schedule__c.Valid_To__c,
Vehicle_Schedule__c.Description__c }); }
if (guard != null) { return fail(guard); }
if (!isNew) {
Integer assignmentUse = [SELECT COUNT() FROM Vehicle_Schedule_Assignment__c
WHERE Vehicle_Schedule__c = :existing.Id];
Integer memberUse = [SELECT COUNT() FROM Vehicle_Schedule_Member__c
WHERE Vehicle_Schedule__c = :existing.Id];
Boolean movesVersion = existing.Valid_From__c != vFrom;
if ((assignmentUse > 0 || memberUse > 0) && movesVersion && form.confirmedVersionedChange != true) {
SaveResult flagged = new SaveResult(false,
'This schedule is already in use. Moving its Valid From date rewrites what is already '
+ 'effective, and schedules are date-versioned data. Confirm to change it, or create a new '
+ 'schedule (a new validity window) instead.', existing.Id);
flagged.requiresConfirmation = true;
flagged.warnings.add(assignmentUse + ' assignment(s) and ' + memberUse + ' member(s) ride on this schedule.');
return flagged;
}
}
Vehicle_Schedule__c save = isNew
? new Vehicle_Schedule__c() : new Vehicle_Schedule__c(Id = existing.Id);
save.Name = form.name.trim();
save.Type__c = form.type;
save.Valid_From__c = vFrom;
save.Valid_To__c = vTo;
save.Description__c = form.description;
if (isNew) {
save.Is_Active__c = form.isActive == null ? true : form.isActive;
} else if (form.isActive != null) {
save.Is_Active__c = form.isActive;
}
if (isNew) { insert save; } else { update save; }
SaveResult res = ok('Vehicle schedule saved.', save.Id);
if (!isNew && form.confirmedVersionedChange == true) {
res.warnings.add('Valid From changed on a schedule that is already in use.');
}
return res;
} catch (Exception e) {
return fail('Could not save the vehicle schedule: ' + e.getMessage());
}
}
@AuraEnabled
public static SaveResult setScheduleActive(Id scheduleId, Boolean active) {
try {
if (scheduleId == null) { return fail('No schedule was identified.'); }
if (active == null) { return fail('Choose whether the schedule should be active.'); }
String guard = guardEdit(new List<SObjectField>{ Vehicle_Schedule__c.Is_Active__c });
if (guard != null) { return fail(guard); }
List<Vehicle_Schedule__c> found = [SELECT Id FROM Vehicle_Schedule__c WHERE Id = :scheduleId LIMIT 1];
if (found.isEmpty()) { return fail('That vehicle schedule no longer exists.'); }
update new Vehicle_Schedule__c(Id = found[0].Id, Is_Active__c = active);
return ok(active ? 'Schedule activated.' : 'Schedule deactivated (kept, not deleted).', found[0].Id);
} catch (Exception e) {
return fail('Could not update the schedule status: ' + e.getMessage());
}
}
@AuraEnabled
public static SaveResult saveMember(MemberForm form) {
try {
if (form == null) { return fail('No member details were provided.'); }
Boolean isNew = String.isBlank(form.recordId);
Id scheduleId;
if (isNew) {
if (String.isBlank(form.scheduleId)) { return fail('No schedule was identified for the new member.'); }
scheduleId = form.scheduleId;
if (!scheduleExists(scheduleId)) { return fail('That vehicle schedule no longer exists.'); }
} else {
List<Vehicle_Schedule_Member__c> found = [
SELECT Id, Vehicle_Schedule__c FROM Vehicle_Schedule_Member__c WHERE Id = :form.recordId LIMIT 1];
if (found.isEmpty()) { return fail('That schedule member no longer exists.'); }
scheduleId = found[0].Vehicle_Schedule__c;
if (String.isNotBlank(form.scheduleId) && form.scheduleId != String.valueOf(scheduleId)) {
return fail('A member cannot be moved to another schedule — the schedule is a master-detail '
+ 'parent. Use "Move" on the target schedule to create it there instead.');
}
}
Boolean includeAll = form.includeAllModels == true;
Boolean isExcl = form.isExclusion == true;
if (String.isBlank(form.makeId) && String.isBlank(form.modelId) && !includeAll) {
return fail('Set a Make, a Model, or turn on Include All Models.');
}
if (String.isNotBlank(form.makeId) && !makeExists(form.makeId)) {
return fail('That make no longer exists.');
}
if (String.isNotBlank(form.modelId) && !modelExists(form.modelId)) {
return fail('That model no longer exists.');
}
if (String.isNotBlank(form.modelId) && String.isNotBlank(form.makeId)) {
List<Model__c> theModel = [SELECT Id, Make__c FROM Model__c WHERE Id = :form.modelId LIMIT 1];
if (!theModel.isEmpty() && theModel[0].Make__c != form.makeId) {
return fail('The selected model does not belong to the selected make.');
}
}
String guard = picklistGuard(Vehicle_Schedule_Member__c.Amount_Type__c, form.amountType);
if (guard == null) { guard = picklistGuard(Vehicle_Schedule_Member__c.Tier__c, form.tier); }
if (guard == null) { guard = picklistGuard(Vehicle_Schedule_Member__c.Class__c, form.classValue); }
if (guard != null) { return fail(guard); }
if (form.multiplier != null && form.multiplier < 0) { return fail('Multiplier cannot be negative.'); }
if (form.premiumModelFee != null && form.premiumModelFee < 0) { return fail('Premium Model Fee cannot be negative.'); }
if ('Multiplier'.equalsIgnoreCase(form.amountType) && form.multiplier == null) {
return fail('A Multiplier amount type needs a Multiplier value.');
}
List<SObjectField> memberFields = new List<SObjectField>{
Vehicle_Schedule_Member__c.Make__c, Vehicle_Schedule_Member__c.Model__c,
Vehicle_Schedule_Member__c.Class__c, Vehicle_Schedule_Member__c.Tier__c,
Vehicle_Schedule_Member__c.Multiplier__c, Vehicle_Schedule_Member__c.Amount_Type__c,
Vehicle_Schedule_Member__c.Premium_Model_Fee__c, Vehicle_Schedule_Member__c.Is_Exclusion__c,
Vehicle_Schedule_Member__c.Include_All_Models__c };
if (isNew) { memberFields.add(Vehicle_Schedule_Member__c.Vehicle_Schedule__c); }
String fieldGuard = isNew ? guardCreate(memberFields) : guardEdit(memberFields);
if (fieldGuard != null) { return fail(fieldGuard); }
Vehicle_Schedule_Member__c save = isNew
? new Vehicle_Schedule_Member__c(Vehicle_Schedule__c = scheduleId)
: new Vehicle_Schedule_Member__c(Id = form.recordId);
save.Make__c = String.isBlank(form.makeId) ? null : form.makeId;
save.Model__c = String.isBlank(form.modelId) ? null : form.modelId;
save.Class__c = String.isBlank(form.classValue) ? null : form.classValue;
save.Tier__c = String.isBlank(form.tier) ? null : form.tier;
save.Multiplier__c = form.multiplier;
save.Amount_Type__c = String.isBlank(form.amountType) ? null : form.amountType;
save.Premium_Model_Fee__c = form.premiumModelFee;
save.Is_Exclusion__c = isExcl;
save.Include_All_Models__c = includeAll;
if (isNew) { insert save; } else { update save; }
return ok('Schedule member saved.', save.Id);
} catch (Exception e) {
if (isDuplicateMemberKey(e)) {
return fail('This schedule already has a member with that make/model and exclusion combination.');
}
return fail('Could not save the schedule member: ' + e.getMessage());
}
}
@AuraEnabled
public static SaveResult deleteMember(Id memberId) {
try {
if (memberId == null) { return fail('No member was identified.'); }
List<Vehicle_Schedule_Member__c> found = [
SELECT Id FROM Vehicle_Schedule_Member__c WHERE Id = :memberId LIMIT 1];
if (found.isEmpty()) { return fail('That schedule member no longer exists.'); }
delete found[0];
return ok('Member removed from the schedule.', null);
} catch (Exception e) {
return fail('Could not remove the member: ' + e.getMessage());
}
}
@AuraEnabled
public static SaveResult moveMember(Id memberId, Id targetScheduleId) {
try {
if (memberId == null) { return fail('No member was identified.'); }
if (targetScheduleId == null) { return fail('Choose the schedule to move this member to.'); }
List<Vehicle_Schedule_Member__c> found = [
SELECT Id, Vehicle_Schedule__c, Make__c, Model__c, Class__c, Tier__c, Multiplier__c,
Amount_Type__c, Premium_Model_Fee__c, Is_Exclusion__c, Include_All_Models__c
FROM Vehicle_Schedule_Member__c WHERE Id = :memberId LIMIT 1];
if (found.isEmpty()) { return fail('That schedule member no longer exists.'); }
Vehicle_Schedule_Member__c src = found[0];
if (src.Vehicle_Schedule__c == targetScheduleId) { return fail('The member is already on that schedule.'); }
if (!scheduleExists(targetScheduleId)) { return fail('The target schedule no longer exists.'); }
String guard = guardCreate(new List<SObjectField>{
Vehicle_Schedule_Member__c.Vehicle_Schedule__c, Vehicle_Schedule_Member__c.Make__c,
Vehicle_Schedule_Member__c.Model__c, Vehicle_Schedule_Member__c.Class__c,
Vehicle_Schedule_Member__c.Tier__c, Vehicle_Schedule_Member__c.Multiplier__c,
Vehicle_Schedule_Member__c.Amount_Type__c, Vehicle_Schedule_Member__c.Premium_Model_Fee__c,
Vehicle_Schedule_Member__c.Is_Exclusion__c, Vehicle_Schedule_Member__c.Include_All_Models__c });
if (guard != null) { return fail(guard); }
Vehicle_Schedule_Member__c copy = new Vehicle_Schedule_Member__c(
Vehicle_Schedule__c = targetScheduleId, Make__c = src.Make__c, Model__c = src.Model__c,
Class__c = src.Class__c, Tier__c = src.Tier__c, Multiplier__c = src.Multiplier__c,
Amount_Type__c = src.Amount_Type__c, Premium_Model_Fee__c = src.Premium_Model_Fee__c,
Is_Exclusion__c = src.Is_Exclusion__c, Include_All_Models__c = src.Include_All_Models__c);
insert copy;
delete src;
return ok('Member moved — re-created on the target schedule (a master-detail member cannot be re-parented).', copy.Id);
} catch (Exception e) {
if (isDuplicateMemberKey(e)) {
return fail('The target schedule already has a member with that make/model and exclusion combination.');
}
return fail('Could not move the member: ' + e.getMessage());
}
}
@AuraEnabled
public static SaveResult saveAssignment(AssignmentForm form) {
try {
if (form == null) { return fail('No assignment details were provided.'); }
Boolean isNew = String.isBlank(form.recordId);
Id scheduleId = null;
if (String.isNotBlank(form.scheduleId)) { scheduleId = form.scheduleId; }
if (isNew) {
if (scheduleId == null) { return fail('Choose the vehicle schedule to assign.'); }
if (!scheduleExists(scheduleId)) { return fail('That vehicle schedule no longer exists.'); }
} else {
List<Vehicle_Schedule_Assignment__c> found = [
SELECT Id, Vehicle_Schedule__c FROM Vehicle_Schedule_Assignment__c
WHERE Id = :form.recordId LIMIT 1];
if (found.isEmpty()) { return fail('That assignment no longer exists.'); }
if (scheduleId == null) { scheduleId = found[0].Vehicle_Schedule__c; }
else if (!scheduleExists(scheduleId)) { return fail('That vehicle schedule no longer exists.'); }
}
Boolean hasPkg = String.isNotBlank(form.packageId);
Boolean hasGrp = String.isNotBlank(form.groupId);
if (hasPkg == hasGrp) {
return fail('Choose exactly one target — a package or a package group (not both, and not neither).');
}
if (hasPkg && !packageExists(form.packageId)) { return fail('That master package no longer exists.'); }
if (hasGrp && !groupExists(form.groupId)) { return fail('That package group no longer exists.'); }
String dateErr = dateError('Effective From', form.effectiveFrom);
if (dateErr == null) { dateErr = dateError('Effective To', form.effectiveTo); }
if (dateErr != null) { return fail(dateErr); }
Date ef = toDate(form.effectiveFrom);
Date et = toDate(form.effectiveTo);
if (ef != null && et != null && et < ef) {
return fail('Effective To cannot be before Effective From.');
}
String fieldGuard = guardCreateOrEdit(isNew, new List<SObjectField>{
Vehicle_Schedule_Assignment__c.Vehicle_Schedule__c, Vehicle_Schedule_Assignment__c.Package__c,
Vehicle_Schedule_Assignment__c.Package_Group__c, Vehicle_Schedule_Assignment__c.Effective_From__c,
Vehicle_Schedule_Assignment__c.Effective_To__c });
if (fieldGuard != null) { return fail(fieldGuard); }
List<Vehicle_Schedule_Assignment__c> dupes = hasPkg
? [SELECT Id FROM Vehicle_Schedule_Assignment__c
WHERE Vehicle_Schedule__c = :scheduleId AND Package__c = :form.packageId
AND Id != :form.recordId]
: [SELECT Id FROM Vehicle_Schedule_Assignment__c
WHERE Vehicle_Schedule__c = :scheduleId AND Package_Group__c = :form.groupId
AND Id != :form.recordId];
if (!dupes.isEmpty()) {
return fail('That schedule is already assigned to this target. Edit the existing assignment instead.');
}
Vehicle_Schedule_Assignment__c save = isNew
? new Vehicle_Schedule_Assignment__c() : new Vehicle_Schedule_Assignment__c(Id = form.recordId);
save.Vehicle_Schedule__c = scheduleId;
save.Package__c = hasPkg ? form.packageId : null;
save.Package_Group__c = hasGrp ? form.groupId : null;
save.Effective_From__c = ef;
save.Effective_To__c = et;
if (isNew) { insert save; } else { update save; }
return ok('Assignment saved.', save.Id);
} catch (Exception e) {
return fail('Could not save the assignment: ' + e.getMessage());
}
}
@AuraEnabled
public static SaveResult deleteAssignment(Id assignmentId) {
try {
if (assignmentId == null) { return fail('No assignment was identified.'); }
List<Vehicle_Schedule_Assignment__c> found = [
SELECT Id FROM Vehicle_Schedule_Assignment__c WHERE Id = :assignmentId LIMIT 1];
if (found.isEmpty()) { return fail('That assignment no longer exists.'); }
delete found[0];
return ok('Assignment removed. The schedule and its members are untouched.', null);
} catch (Exception e) {
return fail('Could not remove the assignment: ' + e.getMessage());
}
}
private static SaveResult fail(String message) { return new SaveResult(false, message, null); }
private static SaveResult ok(String message, Id recordId) { return new SaveResult(true, message, recordId); }
private static Integer normalizeOffset(Integer offset) {
return (offset == null || offset < 0) ? 0 : offset;
}
private static Integer normalizeLimit(Integer limitSize) {
if (limitSize == null || limitSize <= 0) { return DEFAULT_PAGE; }
return limitSize > MAX_PAGE ? MAX_PAGE : limitSize;
}
private static Boolean canCreate(SObjectField fld) {
return !simulateFieldAccessDenied && fld != null && fld.getDescribe().isCreateable();
}
private static Boolean canEdit(SObjectField fld) {
return !simulateFieldAccessDenied && fld != null && fld.getDescribe().isUpdateable();
}
private static String guardCreate(List<SObjectField> fields) {
for (SObjectField fld : fields) { if (!canCreate(fld)) { return permissionMessage(fld, 'set'); } }
return null;
}
private static String guardEdit(List<SObjectField> fields) {
for (SObjectField fld : fields) { if (!canEdit(fld)) { return permissionMessage(fld, 'change'); } }
return null;
}
private static String guardCreateOrEdit(Boolean isNew, List<SObjectField> fields) {
if (!isNew) { return guardEdit(fields); }
for (SObjectField fld : fields) {
if (canCreate(fld) || canEdit(fld)) { continue; }
return permissionMessage(fld, 'set');
}
return null;
}
private static String permissionMessage(SObjectField fld, String verb) {
if (fld == null) { return 'You do not have permission to make that change.'; }
Schema.DescribeFieldResult d = fld.getDescribe();
return 'You do not have permission to ' + verb + ' ' + d.getLabel()
+ ' on ' + d.getSObjectType().getDescribe().getLabel() + '.';
}
private static String picklistGuard(SObjectField fld, String value) {
if (String.isBlank(value)) { return null; }
Schema.DescribeFieldResult d = fld.getDescribe();
for (Schema.PicklistEntry entry : d.getPicklistValues()) {
if (entry.getValue() == value) { return null; }
}
return '"' + value + '" is not a valid ' + d.getLabel() + '.';
}
private static List<Choice> picklistChoices(SObjectField fld) {
List<Choice> choices = new List<Choice>();
for (Schema.PicklistEntry entry : fld.getDescribe().getPicklistValues()) {
choices.add(new Choice(entry.getValue(), entry.getLabel()));
}
return choices;
}
private static String dateError(String label, String iso) {
if (String.isBlank(iso)) { return null; }
try { Date.valueOf(iso); return null; }
catch (Exception e) { return label + ' is not a valid date.'; }
}
private static Date toDate(String iso) {
return String.isBlank(iso) ? null : Date.valueOf(iso);
}
private static Boolean scheduleExists(Id scheduleId) {
return scheduleId != null && [SELECT COUNT() FROM Vehicle_Schedule__c WHERE Id = :scheduleId] > 0;
}
private static Boolean packageExists(Id packageId) {
return packageId != null && [SELECT COUNT() FROM Package__c WHERE Id = :packageId] > 0;
}
private static Boolean groupExists(Id groupId) {
return groupId != null && [SELECT COUNT() FROM Package_Group__c WHERE Id = :groupId] > 0;
}
private static Boolean makeExists(Id makeId) {
return makeId != null && [SELECT COUNT() FROM Make__c WHERE Id = :makeId] > 0;
}
private static Boolean modelExists(Id modelId) {
return modelId != null && [SELECT COUNT() FROM Model__c WHERE Id = :modelId] > 0;
}
private static String packageLabel(Id packageId) {
List<Package__c> found = [SELECT Id, Name FROM Package__c WHERE Id = :packageId LIMIT 1];
return found.isEmpty() ? '' : found[0].Name;
}
private static String groupLabel(Id groupId) {
List<Package_Group__c> found = [SELECT Id, Name FROM Package_Group__c WHERE Id = :groupId LIMIT 1];
return found.isEmpty() ? '' : found[0].Name;
}
private static Boolean isDuplicateMemberKey(Exception e) {
String msg = e == null ? null : e.getMessage();
if (msg == null) { return false; }
Boolean mentionsKey = msg.containsIgnoreCase('Member_Key__c') || msg.containsIgnoreCase('Member Key');
Boolean dup = msg.containsIgnoreCase('duplicate') || msg.containsIgnoreCase('unique')
|| msg.containsIgnoreCase('DUPLICATE_VALUE');
return mentionsKey && dup;
}
private static ScheduleRow toScheduleRow(Vehicle_Schedule__c s) {
ScheduleRow row = new ScheduleRow();
row.id = s.Id;
row.name = s.Name;
row.type = s.Type__c;
row.typeLabel = valueOrDash(s.Type__c);
row.isActive = s.Is_Active__c == true;
row.statusLabel = row.isActive ? 'Active' : 'Inactive';
row.statusTone = row.isActive ? 'ok' : 'muted';
row.validFromLabel = dateLabel(s.Valid_From__c);
row.validToLabel = dateLabel(s.Valid_To__c);
row.memberCount = s.Vehicle_Schedule_Member__r == null ? 0 : s.Vehicle_Schedule_Member__r.size();
row.assignmentCount = s.Vehicle_Schedule__r == null ? 0 : s.Vehicle_Schedule__r.size();
row.summaryLabel = row.memberCount + (row.memberCount == 1 ? ' member' : ' members')
+ ' \u00b7 ' + row.assignmentCount + (row.assignmentCount == 1 ? ' assignment' : ' assignments');
return row;
}
private static MemberRow toMemberRow(Vehicle_Schedule_Member__c m) {
MemberRow row = new MemberRow();
row.id = m.Id;
row.name = m.Name;
row.makeId = m.Make__c == null ? null : String.valueOf(m.Make__c);
row.makeLabel = m.Make__r != null ? m.Make__r.Name : '';
row.modelId = m.Model__c == null ? null : String.valueOf(m.Model__c);
row.modelLabel = m.Model__r != null ? m.Model__r.Name : '';
row.classValue = m.Class__c;
row.tier = m.Tier__c;
row.multiplier = m.Multiplier__c;
row.amountType = m.Amount_Type__c;
row.premiumModelFee = m.Premium_Model_Fee__c;
row.isExclusion = m.Is_Exclusion__c == true;
row.includeAllModels = m.Include_All_Models__c == true;
row.memberKey = m.Member_Key__c;
row.vehicleLabel = vehicleLabel(m);
row.effectLabel = effectLabel(m);
row.flagsLabel = flagsLabel(m);
return row;
}
private static AssignmentRow toAssignmentRow(Vehicle_Schedule_Assignment__c a) {
AssignmentRow row = new AssignmentRow();
row.id = a.Id;
row.scheduleId = a.Vehicle_Schedule__c == null ? null : String.valueOf(a.Vehicle_Schedule__c);
row.scheduleName = a.Vehicle_Schedule__r != null ? a.Vehicle_Schedule__r.Name : '';
row.scheduleTypeLabel = a.Vehicle_Schedule__r != null ? valueOrDash(a.Vehicle_Schedule__r.Type__c) : DASH;
if (a.Package__c != null) {
row.targetType = 'Package';
row.targetId = String.valueOf(a.Package__c);
row.targetName = a.Package__r != null ? a.Package__r.Name : '';
} else if (a.Package_Group__c != null) {
row.targetType = 'Group';
row.targetId = String.valueOf(a.Package_Group__c);
row.targetName = a.Package_Group__r != null ? a.Package_Group__r.Name : '';
} else {
row.targetType = 'Unbound';
row.targetName = DASH;
}
row.effectiveFrom = a.Effective_From__c == null ? null : String.valueOf(a.Effective_From__c);
row.effectiveTo = a.Effective_To__c == null ? null : String.valueOf(a.Effective_To__c);
row.effectiveFromLabel = dateLabel(a.Effective_From__c);
row.effectiveToLabel = dateLabel(a.Effective_To__c);
row.windowLabel = windowLabel(a.Effective_From__c, a.Effective_To__c);
return row;
}
private static List<AssignmentRow> assignmentRows(List<Vehicle_Schedule_Assignment__c> records) {
List<AssignmentRow> out = new List<AssignmentRow>();
for (Vehicle_Schedule_Assignment__c a : records) { out.add(toAssignmentRow(a)); }
return out;
}
private static String vehicleLabel(Vehicle_Schedule_Member__c m) {
String make = m.Make__r != null ? m.Make__r.Name : null;
String model = m.Model__r != null ? m.Model__r.Name : null;
List<String> parts = new List<String>();
if (String.isNotBlank(make)) { parts.add(make); }
if (String.isNotBlank(model)) { parts.add(model); }
if (m.Include_All_Models__c == true) { parts.add('All models'); }
return parts.isEmpty() ? 'Any vehicle' : String.join(parts, ' ');
}
private static String effectLabel(Vehicle_Schedule_Member__c m) {
List<String> parts = new List<String>();
if (m.Is_Exclusion__c == true) { parts.add('Exclusion'); }
if (m.Amount_Type__c == 'Multiplier' && m.Multiplier__c != null) {
parts.add('\u00d7' + formatNumber(m.Multiplier__c));
} else if (m.Premium_Model_Fee__c != null) {
parts.add(amountText(m.Premium_Model_Fee__c));
} else if (String.isNotBlank(m.Amount_Type__c)) {
parts.add(m.Amount_Type__c);
}
return parts.isEmpty() ? DASH : String.join(parts, ' \u00b7 ');
}
private static String flagsLabel(Vehicle_Schedule_Member__c m) {
List<String> parts = new List<String>();
if (String.isNotBlank(m.Tier__c)) { parts.add(m.Tier__c); }
if (String.isNotBlank(m.Class__c)) { parts.add(m.Class__c); }
return parts.isEmpty() ? DASH : String.join(parts, ' \u00b7 ');
}
private static String windowLabel(Date fromDate, Date toDate) {
if (fromDate == null && toDate == null) { return 'Always effective'; }
String f = fromDate == null ? 'Open' : formatDate(fromDate);
String t = toDate == null ? 'Open' : formatDate(toDate);
return f + ' \u2192 ' + t;
}
private static String dateLabel(Date d) { return d == null ? DASH : formatDate(d); }
private static String valueOrDash(String s) { return String.isBlank(s) ? DASH : s; }
private static String formatDate(Date d) {
return d == null ? DASH : d.format();
}
private static String amountText(Decimal v) {
if (v == null) { return ''; }
Boolean whole = (v == v.setScale(0, System.RoundingMode.HALF_UP));
String raw = whole ? String.valueOf(v.setScale(0)) : String.valueOf(v.setScale(2));
Boolean neg = raw.startsWith('-');
if (neg) { raw = raw.substring(1); }
Integer dot = raw.indexOf('.');
String intPart = dot == -1 ? raw : raw.substring(0, dot);
String frac = dot == -1 ? '' : raw.substring(dot);
return (neg ? '-$' : '$') + groupThousands(intPart) + frac;
}
private static String formatNumber(Decimal v) {
if (v == null) { return ''; }
return groupThousands(String.valueOf(v.setScale(0, System.RoundingMode.HALF_UP)));
}
private static String groupThousands(String digits) {
if (String.isBlank(digits)) { return '0'; }
Boolean neg = digits.startsWith('-');
if (neg) { digits = digits.substring(1); }
String out = '';
Integer count = 0;
for (Integer i = digits.length() - 1; i >= 0; i--) {
out = digits.substring(i, i + 1) + out;
count++;
if (count == 3 && i > 0) { out = ',' + out; count = 0; }
}
return (neg ? '-' : '') + out;
}
}