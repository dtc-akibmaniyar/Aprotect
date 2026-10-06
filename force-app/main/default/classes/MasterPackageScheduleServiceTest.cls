@IsTest
private class MasterPackageScheduleServiceTest {
private static Catalogue_Release__c makeRelease() {
Catalogue_Release__c rel = new Catalogue_Release__c(
Name = 'V99S', Release_Number__c = 'V99S', Status__c = 'Draft',
Effective_Date__c = Date.newInstance(2027, 1, 1));
insert rel;
return rel;
}
private static Package_Group__c makeGroup(Id releaseId, String name) {
Package_Group__c g = new Package_Group__c(Name = name, Active__c = true, Catalogue_Release__c = releaseId);
insert g;
return g;
}
private static Package__c makePackage(Id groupId, String name) {
Package__c p = new Package__c(Name = name, Package_Group__c = groupId, Is_Active__c = true,
Commercial_Business_Use__c = false);
insert p;
return p;
}
private static Vehicle_Schedule__c makeSchedule(String name, String type, Boolean active) {
Vehicle_Schedule__c s = new Vehicle_Schedule__c(
Name = name, Type__c = type, Is_Active__c = active, Valid_From__c = Date.newInstance(2027, 1, 1));
insert s;
return s;
}
private static Make__c makeMake(String name) {
Make__c mk = new Make__c(Name = name);
insert mk;
return mk;
}
private static Model__c makeModel(String name, Id makeId) {
Model__c mo = new Model__c(Name = name, Make__c = makeId);
insert mo;
return mo;
}
private static Vehicle_Schedule_Member__c makeMember(Id scheduleId, Id makeId, Id modelId, Boolean excl) {
Vehicle_Schedule_Member__c m = new Vehicle_Schedule_Member__c(
Vehicle_Schedule__c = scheduleId, Make__c = makeId, Model__c = modelId,
Is_Exclusion__c = excl == true, Include_All_Models__c = false);
insert m;
return m;
}
@IsTest
static void scheduleCreateEditAndToggle() {
Test.startTest();
MasterPackageScheduleService.ScheduleForm form = new MasterPackageScheduleService.ScheduleForm();
form.name = 'Premium Tier - Test Book';
form.type = 'Premium_Tier';
form.validFrom = '2027-01-01';
form.validTo = '2027-12-31';
form.isActive = true;
MasterPackageScheduleService.SaveResult created = MasterPackageScheduleService.saveSchedule(form);
Test.stopTest();
Assert.isTrue(created.success, created.message);
Assert.isNotNull(created.recordId);
Vehicle_Schedule__c s = [SELECT Name, Type__c, Is_Active__c, Valid_From__c, Valid_To__c
FROM Vehicle_Schedule__c WHERE Id = :created.recordId];
Assert.areEqual('Premium Tier - Test Book', s.Name);
Assert.areEqual('Premium_Tier', s.Type__c);
Assert.isTrue(s.Is_Active__c);
Assert.areEqual(Date.newInstance(2027, 12, 31), s.Valid_To__c);
form.recordId = String.valueOf(created.recordId);
form.name = 'Premium Tier - Test Book (rev)';
form.type = 'Diesel_Fee';
form.validTo = null;
MasterPackageScheduleService.SaveResult edited = MasterPackageScheduleService.saveSchedule(form);
Assert.isTrue(edited.success, edited.message);
Vehicle_Schedule__c e = [SELECT Name, Type__c, Valid_To__c FROM Vehicle_Schedule__c WHERE Id = :created.recordId];
Assert.areEqual('Premium Tier - Test Book (rev)', e.Name);
Assert.areEqual('Diesel_Fee', e.Type__c);
Assert.isNull(e.Valid_To__c);
Assert.isTrue(MasterPackageScheduleService.setScheduleActive(created.recordId, false).success);
Assert.isFalse([SELECT Is_Active__c FROM Vehicle_Schedule__c WHERE Id = :created.recordId].Is_Active__c);
Assert.isTrue(MasterPackageScheduleService.setScheduleActive(created.recordId, true).success);
}
@IsTest
static void scheduleValidationGuards() {
String unknownId = Vehicle_Schedule__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000AAA';
MasterPackageScheduleService.ScheduleForm form = new MasterPackageScheduleService.ScheduleForm();
form.name = '   ';
Assert.isFalse(MasterPackageScheduleService.saveSchedule(form).success, 'a blank name is refused');
form.name = 'Guarded';
form.type = 'Not_A_Real_Type';
Assert.isFalse(MasterPackageScheduleService.saveSchedule(form).success, 'an invalid type is refused');
form.type = 'Premium_Tier';
form.validFrom = '2027-06-01';
form.validTo = '2027-01-01';
MasterPackageScheduleService.SaveResult bad = MasterPackageScheduleService.saveSchedule(form);
Assert.isFalse(bad.success, 'Valid To before Valid From is refused');
Assert.isTrue(bad.message.contains('before'), bad.message);
form.validTo = '2027-12-01';
form.validFrom = 'not-a-date';
Assert.isFalse(MasterPackageScheduleService.saveSchedule(form).success, 'a malformed date is refused');
MasterPackageScheduleService.ScheduleForm edit = new MasterPackageScheduleService.ScheduleForm();
edit.recordId = unknownId;
edit.name = 'Nope';
edit.type = 'Premium_Tier';
Assert.isFalse(MasterPackageScheduleService.saveSchedule(edit).success, 'an unknown schedule id is refused');
Assert.isFalse(MasterPackageScheduleService.saveSchedule(null).success, 'a null form is refused');
Assert.isFalse(MasterPackageScheduleService.setScheduleActive(null, true).success, 'a null id is refused');
Assert.isFalse(MasterPackageScheduleService.setScheduleActive(unknownId, true).success, 'an unknown id is refused');
}
@IsTest
static void versionedScheduleEditRequiresConfirmation() {
Vehicle_Schedule__c s = makeSchedule('Versioned', 'Premium_Tier', true);
insert new Vehicle_Schedule_Member__c(Vehicle_Schedule__c = s.Id, Include_All_Models__c = true);
MasterPackageScheduleService.ScheduleForm form = new MasterPackageScheduleService.ScheduleForm();
form.recordId = String.valueOf(s.Id);
form.name = 'Versioned';
form.type = 'Premium_Tier';
form.validFrom = '2026-01-01'; // moves the version window on a schedule already in use
MasterPackageScheduleService.SaveResult flagged = MasterPackageScheduleService.saveSchedule(form);
Assert.isFalse(flagged.success, 'a version move on an in-use schedule must be flagged, not silently applied');
Assert.isTrue(flagged.requiresConfirmation, 'the result asks for confirmation');
Assert.areEqual(Date.newInstance(2027, 1, 1),
[SELECT Valid_From__c FROM Vehicle_Schedule__c WHERE Id = :s.Id].Valid_From__c,
'nothing was written while unconfirmed');
form.confirmedVersionedChange = true;
MasterPackageScheduleService.SaveResult applied = MasterPackageScheduleService.saveSchedule(form);
Assert.isTrue(applied.success, applied.message);
Assert.areEqual(Date.newInstance(2026, 1, 1),
[SELECT Valid_From__c FROM Vehicle_Schedule__c WHERE Id = :s.Id].Valid_From__c);
Assert.isTrue(applied.warnings.size() > 0, 'the versioned change is flagged in the result');
}
@IsTest
static void memberCreateEditAndTriggerDerivesKey() {
Vehicle_Schedule__c s = makeSchedule('Members', 'Premium_Tier', true);
Make__c mk = makeMake('Porsche');
Model__c mo = makeModel('911 GT3', mk.Id);
MasterPackageScheduleService.MemberForm form = new MasterPackageScheduleService.MemberForm();
form.scheduleId = String.valueOf(s.Id);
form.makeId = String.valueOf(mk.Id);
form.modelId = String.valueOf(mo.Id);
form.amountType = 'Flat';
form.premiumModelFee = 199;
form.tier = 'Tier 1';
Test.startTest();
MasterPackageScheduleService.SaveResult created = MasterPackageScheduleService.saveMember(form);
Test.stopTest();
Assert.isTrue(created.success, created.message);
Vehicle_Schedule_Member__c m = [SELECT Make__c, Model__c, Member_Key__c, Premium_Model_Fee__c
FROM Vehicle_Schedule_Member__c WHERE Id = :created.recordId];
Assert.areEqual(mk.Id, m.Make__c);
Assert.isNotNull(m.Member_Key__c, 'the trigger derived the member key');
Assert.isTrue(m.Member_Key__c.startsWith(String.valueOf(s.Id) + '|'),
'the key is prefixed with the owning schedule: ' + m.Member_Key__c);
Assert.isTrue(m.Member_Key__c.contains('Porsche'), m.Member_Key__c);
form.recordId = String.valueOf(created.recordId);
form.premiumModelFee = 249;
MasterPackageScheduleService.SaveResult edited = MasterPackageScheduleService.saveMember(form);
Assert.isTrue(edited.success, edited.message);
Assert.areEqual(249,
[SELECT Premium_Model_Fee__c FROM Vehicle_Schedule_Member__c WHERE Id = :created.recordId].Premium_Model_Fee__c);
Assert.isNotNull([SELECT Member_Key__c FROM Vehicle_Schedule_Member__c WHERE Id = :created.recordId].Member_Key__c,
'the derived key survives an edit');
}
@IsTest
static void memberValidationGuards() {
Vehicle_Schedule__c s = makeSchedule('MemberGuards', 'Premium_Tier', true);
Make__c mk = makeMake('Ford');
Make__c other = makeMake('Holden');
Model__c mo = makeModel('Mustang', mk.Id);
MasterPackageScheduleService.MemberForm form = new MasterPackageScheduleService.MemberForm();
form.scheduleId = String.valueOf(s.Id);
Assert.isFalse(MasterPackageScheduleService.saveMember(form).success,
'a member with no make, model or include-all is refused');
form.includeAllModels = true;
form.amountType = 'Multiplier';
Assert.isFalse(MasterPackageScheduleService.saveMember(form).success,
'a Multiplier amount type without a value is refused');
form.multiplier = -1;
form.amountType = null;
Assert.isFalse(MasterPackageScheduleService.saveMember(form).success, 'a negative multiplier is refused');
form.multiplier = null;
form.includeAllModels = false;
form.makeId = String.valueOf(mk.Id);
form.modelId = String.valueOf(other.Id);
Assert.isFalse(MasterPackageScheduleService.saveMember(form).success,
'a model that does not belong to the make is refused');
form.modelId = null;
form.amountType = 'Not_A_Type';
Assert.isFalse(MasterPackageScheduleService.saveMember(form).success, 'an invalid amount type is refused');
form.amountType = null;
form.makeId = String.valueOf(mk.Id);
form.premiumModelFee = -5;
Assert.isFalse(MasterPackageScheduleService.saveMember(form).success, 'a negative premium fee is refused');
form.premiumModelFee = null;
MasterPackageScheduleService.SaveResult first = MasterPackageScheduleService.saveMember(form);
Assert.isTrue(first.success, first.message);
Vehicle_Schedule__c target = makeSchedule('ReparentTarget', 'Diesel_Fee', true);
form.recordId = String.valueOf(first.recordId);
form.scheduleId = String.valueOf(target.Id);
MasterPackageScheduleService.SaveResult reparent = MasterPackageScheduleService.saveMember(form);
Assert.isFalse(reparent.success, 're-parenting a member is refused');
Assert.isTrue(reparent.message.containsIgnoreCase('master-detail'), reparent.message);
Assert.isFalse(MasterPackageScheduleService.saveMember(null).success, 'a null form is refused');
}
@IsTest
static void duplicateMemberKeyIsTranslatedToPlainWords() {
Vehicle_Schedule__c s = makeSchedule('Dupe', 'Premium_Tier', true);
Make__c mk = makeMake('Toyota');
Model__c mo = makeModel('Hilux', mk.Id);
MasterPackageScheduleService.MemberForm form = new MasterPackageScheduleService.MemberForm();
form.scheduleId = String.valueOf(s.Id);
form.makeId = String.valueOf(mk.Id);
form.modelId = String.valueOf(mo.Id);
Assert.isTrue(MasterPackageScheduleService.saveMember(form).success, 'the first member saves');
MasterPackageScheduleService.SaveResult dupe = MasterPackageScheduleService.saveMember(form);
Assert.isFalse(dupe.success, 'an identical member in the same schedule is refused');
Assert.isFalse(dupe.message.containsIgnoreCase('Member_Key__c'),
'the raw unique-key error is not leaked: ' + dupe.message);
Assert.areEqual(1, [SELECT COUNT() FROM Vehicle_Schedule_Member__c WHERE Vehicle_Schedule__c = :s.Id]);
}
@IsTest
static void memberDeleteAndMove() {
Vehicle_Schedule__c source = makeSchedule('MoveSource', 'Premium_Tier', true);
Vehicle_Schedule__c target = makeSchedule('MoveTarget', 'Premium_Tier', true);
Make__c mk = makeMake('Mazda');
Model__c mo = makeModel('CX-5', mk.Id);
Vehicle_Schedule_Member__c m = makeMember(source.Id, mk.Id, mo.Id, false);
Assert.isFalse(MasterPackageScheduleService.deleteMember(null).success, 'a null id is refused');
Assert.isFalse(MasterPackageScheduleService.moveMember(null, target.Id).success, 'a null member id is refused');
Assert.isFalse(MasterPackageScheduleService.moveMember(m.Id, null).success, 'a null target is refused');
Assert.isFalse(MasterPackageScheduleService.moveMember(m.Id, source.Id).success,
'moving to the same schedule is refused');
MasterPackageScheduleService.SaveResult moved = MasterPackageScheduleService.moveMember(m.Id, target.Id);
Assert.isTrue(moved.success, moved.message);
Assert.areEqual(0, [SELECT COUNT() FROM Vehicle_Schedule_Member__c WHERE Id = :m.Id],
'the old row is gone');
Assert.areEqual(1, [SELECT COUNT() FROM Vehicle_Schedule_Member__c WHERE Vehicle_Schedule__c = :target.Id]);
Assert.isTrue([SELECT Member_Key__c FROM Vehicle_Schedule_Member__c WHERE Id = :moved.recordId].Member_Key__c
.startsWith(String.valueOf(target.Id) + '|'), 'the new row carries the target schedule key');
Assert.isTrue(MasterPackageScheduleService.deleteMember(moved.recordId).success, 'the moved member deletes');
}
@IsTest
static void assignmentCreateEditAndMutualExclusion() {
Catalogue_Release__c rel = makeRelease();
Package_Group__c g = makeGroup(rel.Id, 'Assign Group');
Package__c pkg = makePackage(g.Id, 'Assign Package');
Vehicle_Schedule__c s = makeSchedule('Assignable', 'Commercial_Surcharge', true);
Vehicle_Schedule__c other = makeSchedule('Assignable2', 'Diesel_Fee', true);
MasterPackageScheduleService.AssignmentForm form = new MasterPackageScheduleService.AssignmentForm();
form.scheduleId = String.valueOf(s.Id);
form.packageId = String.valueOf(pkg.Id);
form.effectiveFrom = '2027-01-01';
form.effectiveTo = '2027-12-31';
Test.startTest();
MasterPackageScheduleService.SaveResult created = MasterPackageScheduleService.saveAssignment(form);
Test.stopTest();
Assert.isTrue(created.success, created.message);
Vehicle_Schedule_Assignment__c a = [SELECT Package__c, Package_Group__c, Dealer__c, Effective_From__c
FROM Vehicle_Schedule_Assignment__c WHERE Id = :created.recordId];
Assert.areEqual(pkg.Id, a.Package__c);
Assert.isNull(a.Package_Group__c, 'the package target excludes a group target');
Assert.isNull(a.Dealer__c, 'MASTER ONLY — the dealer override is never set');
form.recordId = null;
form.scheduleId = String.valueOf(other.Id);
form.groupId = String.valueOf(g.Id);
MasterPackageScheduleService.SaveResult both = MasterPackageScheduleService.saveAssignment(form);
Assert.isFalse(both.success, 'a package AND a group target is refused');
form.packageId = null;
form.groupId = null;
MasterPackageScheduleService.SaveResult neither = MasterPackageScheduleService.saveAssignment(form);
Assert.isFalse(neither.success, 'neither target is refused');
form.groupId = String.valueOf(g.Id);
form.scheduleId = String.valueOf(other.Id);
MasterPackageScheduleService.SaveResult groupAssign = MasterPackageScheduleService.saveAssignment(form);
Assert.isTrue(groupAssign.success, groupAssign.message);
Assert.areEqual(g.Id,
[SELECT Package_Group__c FROM Vehicle_Schedule_Assignment__c WHERE Id = :groupAssign.recordId].Package_Group__c);
MasterPackageScheduleService.AssignmentForm edit = new MasterPackageScheduleService.AssignmentForm();
edit.recordId = String.valueOf(created.recordId);
edit.packageId = String.valueOf(pkg.Id);
edit.effectiveFrom = '2027-06-01';
edit.effectiveTo = '2027-01-01';
MasterPackageScheduleService.SaveResult badDate = MasterPackageScheduleService.saveAssignment(edit);
Assert.isFalse(badDate.success, 'Effective To before Effective From is refused');
edit.effectiveTo = '2027-08-01';
Assert.isTrue(MasterPackageScheduleService.saveAssignment(edit).success, 'the assignment edit saves');
MasterPackageScheduleService.AssignmentForm dupe = new MasterPackageScheduleService.AssignmentForm();
dupe.scheduleId = String.valueOf(s.Id);
dupe.packageId = String.valueOf(pkg.Id);
MasterPackageScheduleService.SaveResult duplicate = MasterPackageScheduleService.saveAssignment(dupe);
Assert.isFalse(duplicate.success, 'a duplicate schedule/target assignment is refused');
Assert.isTrue(duplicate.message.containsIgnoreCase('already assigned'), duplicate.message);
}
@IsTest
static void assignmentValidationAndGuards() {
String unknownId = Vehicle_Schedule__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000AAA';
Vehicle_Schedule__c s = makeSchedule('AssignGuards', 'Diesel_Fee', true);
MasterPackageScheduleService.AssignmentForm form = new MasterPackageScheduleService.AssignmentForm();
form.packageId = String.valueOf(Package__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000AAA');
Assert.isFalse(MasterPackageScheduleService.saveAssignment(form).success,
'a missing schedule is refused');
form.scheduleId = String.valueOf(s.Id);
Assert.isFalse(MasterPackageScheduleService.saveAssignment(form).success,
'an unknown package target is refused');
form.packageId = null;
form.groupId = String.valueOf(Package_Group__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000AAA');
Assert.isFalse(MasterPackageScheduleService.saveAssignment(form).success,
'an unknown group target is refused');
form.scheduleId = unknownId;
Assert.isFalse(MasterPackageScheduleService.saveAssignment(form).success, 'an unknown schedule is refused');
MasterPackageScheduleService.AssignmentForm edit = new MasterPackageScheduleService.AssignmentForm();
edit.recordId = unknownId;
edit.packageId = form.groupId;
Assert.isFalse(MasterPackageScheduleService.saveAssignment(edit).success, 'an unknown assignment id is refused');
Assert.isFalse(MasterPackageScheduleService.saveAssignment(null).success, 'a null form is refused');
Assert.isFalse(MasterPackageScheduleService.deleteAssignment(null).success, 'a null assignment id is refused');
Assert.isFalse(MasterPackageScheduleService.deleteAssignment(unknownId).success, 'an unknown id is refused');
}
@IsTest
static void assignmentDeleteLeavesScheduleAndMembers() {
Catalogue_Release__c rel = makeRelease();
Package_Group__c g = makeGroup(rel.Id, 'Del Group');
Package__c pkg = makePackage(g.Id, 'Del Package');
Vehicle_Schedule__c s = makeSchedule('Del Schedule', 'Premium_Tier', true);
insert new Vehicle_Schedule_Member__c(Vehicle_Schedule__c = s.Id, Include_All_Models__c = true);
Vehicle_Schedule_Assignment__c a = new Vehicle_Schedule_Assignment__c(
Vehicle_Schedule__c = s.Id, Package__c = pkg.Id, Effective_From__c = Date.newInstance(2027, 1, 1));
insert a;
MasterPackageScheduleService.SaveResult removed = MasterPackageScheduleService.deleteAssignment(a.Id);
Assert.isTrue(removed.success, removed.message);
Assert.areEqual(0, [SELECT COUNT() FROM Vehicle_Schedule_Assignment__c WHERE Id = :a.Id]);
Assert.areEqual(1, [SELECT COUNT() FROM Vehicle_Schedule__c WHERE Id = :s.Id], 'the schedule is kept');
Assert.areEqual(1, [SELECT COUNT() FROM Vehicle_Schedule_Member__c WHERE Vehicle_Schedule__c = :s.Id],
'the schedule members are kept');
}
@IsTest
static void scheduleBrowsePagingSearchAndDetail() {
Catalogue_Release__c rel = makeRelease();
Package_Group__c g = makeGroup(rel.Id, 'Browse Group');
Package__c pkg = makePackage(g.Id, 'Browse Package');
Vehicle_Schedule__c s = makeSchedule('Browse - Alpha', 'Premium_Tier', true);
makeSchedule('Browse - Beta', 'Diesel_Fee', false);
Make__c mk = makeMake('Subaru');
insert new Vehicle_Schedule_Member__c(Vehicle_Schedule__c = s.Id, Make__c = mk.Id, Include_All_Models__c = true);
insert new Vehicle_Schedule_Member__c(Vehicle_Schedule__c = s.Id, Include_All_Models__c = true, Is_Exclusion__c = true);
insert new Vehicle_Schedule_Assignment__c(
Vehicle_Schedule__c = s.Id, Package__c = pkg.Id, Effective_From__c = Date.newInstance(2027, 1, 1));
Test.startTest();
MasterPackageScheduleService.SchedulePage page =
MasterPackageScheduleService.getSchedules(null, 0, 1);
Test.stopTest();
Assert.areEqual(2, page.total, 'both schedules are counted');
Assert.areEqual(1, page.rows.size(), 'only one row is returned for a page size of 1');
Assert.isTrue(page.hasMore, 'more rows remain');
Assert.areEqual('Browse - Alpha', page.rows[0].name);
Assert.areEqual(2, page.rows[0].memberCount, 'member rollup');
Assert.areEqual(1, page.rows[0].assignmentCount, 'assignment rollup');
Assert.areEqual('Active', page.rows[0].statusLabel);
MasterPackageScheduleService.SchedulePage search =
MasterPackageScheduleService.getSchedules('Alpha', 0, 50);
Assert.areEqual(1, search.total, 'name search narrows the list');
MasterPackageScheduleService.ScheduleDetail detail =
MasterPackageScheduleService.getScheduleDetail(s.Id, 0, 1);
Assert.areEqual(s.Id, detail.id);
Assert.areEqual(2, detail.memberTotal, 'member total is reported');
Assert.areEqual(1, detail.members.size(), 'members are paged, never bulk-loaded');
Assert.isTrue(detail.membersHaveMore, 'a second member page remains');
Assert.areEqual(1, detail.assignments.size());
Assert.areEqual('Package', detail.assignments[0].targetType);
Assert.areEqual('Browse Package', detail.assignments[0].targetName);
MasterPackageScheduleService.ScheduleDetail secondPage =
MasterPackageScheduleService.getScheduleDetail(s.Id, 1, 1);
Assert.areEqual(1, secondPage.members.size());
Assert.isFalse(secondPage.membersHaveMore);
MasterPackageScheduleService.ScheduleDetail none =
MasterPackageScheduleService.getScheduleDetail(null, null, null);
Assert.isNull(none.id);
Assert.areEqual(0, none.members.size());
String unknown = Vehicle_Schedule__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000AAA';
Assert.isNull(MasterPackageScheduleService.getScheduleDetail(unknown, 0, 10).id);
}
@IsTest
static void contextAssignmentsForPackageAndGroup() {
Catalogue_Release__c rel = makeRelease();
Package_Group__c g = makeGroup(rel.Id, 'Ctx Group');
Package__c pkg = makePackage(g.Id, 'Ctx Package');
Vehicle_Schedule__c s = makeSchedule('Ctx Schedule', 'Powersports_Program', true);
insert new Vehicle_Schedule_Assignment__c(
Vehicle_Schedule__c = s.Id, Package__c = pkg.Id, Effective_From__c = Date.newInstance(2027, 1, 1));
insert new Vehicle_Schedule_Assignment__c(
Vehicle_Schedule__c = s.Id, Package_Group__c = g.Id, Effective_From__c = Date.newInstance(2027, 1, 1));
MasterPackageScheduleService.ContextPanel forPackage =
MasterPackageScheduleService.getContextAssignments('package', pkg.Id);
Assert.areEqual(1, forPackage.total, 'only the package assignment is returned');
Assert.areEqual('Package', forPackage.assignments[0].targetType);
Assert.areEqual('Ctx Schedule', forPackage.assignments[0].scheduleName);
MasterPackageScheduleService.ContextPanel forGroup =
MasterPackageScheduleService.getContextAssignments('group', g.Id);
Assert.areEqual(1, forGroup.total, 'only the group assignment is returned');
Assert.areEqual('Group', forGroup.assignments[0].targetType);
MasterPackageScheduleService.ContextPanel none =
MasterPackageScheduleService.getContextAssignments(null, null);
Assert.areEqual(0, none.total, 'null context returns a typed empty panel');
Assert.areEqual(0, MasterPackageScheduleService.getContextAssignments('nonsense', pkg.Id).total);
}
@IsTest
static void formOptionsAndLookups() {
Catalogue_Release__c rel = makeRelease();
Package_Group__c g = makeGroup(rel.Id, 'Options Group');
makePackage(g.Id, 'Options Package');
makeMake('Kia');
Make__c mk = makeMake('Volvo');
makeModel('XC90', mk.Id);
makeSchedule('Options Schedule', 'Tire_Rim_Category', true);
MasterPackageScheduleService.FormOptions o = MasterPackageScheduleService.getFormOptions();
Assert.isTrue(o.typeOptions.size() > 0, 'the schedule type picklist is surfaced');
Assert.isTrue(o.amountTypeOptions.size() > 0, 'the amount type picklist is surfaced');
Assert.isTrue(o.tierOptions.size() > 0, 'the tier picklist is surfaced');
Assert.isTrue(o.memberClassOptions.size() > 0, 'the member class picklist is surfaced');
Assert.isTrue(o.scheduleChoices.size() > 0, 'schedules are offered as choices');
Assert.isTrue(o.packageChoices.size() > 0, 'packages are offered as choices');
Assert.isTrue(o.groupChoices.size() > 0, 'groups are offered as choices');
Assert.isTrue(o.makeChoices.size() > 0, 'makes are offered as choices');
Assert.isTrue(MasterPackageScheduleService.searchMakes('Volvo', 10).size() >= 1, 'make search works');
Assert.isTrue(MasterPackageScheduleService.searchModels(String.valueOf(mk.Id), null, 10).size() >= 1,
'model search scoped to a make works');
}
@IsTest
static void fieldAccessGuardsFailClosed() {
Catalogue_Release__c rel = makeRelease();
Package_Group__c g = makeGroup(rel.Id, 'FLS Group');
Package__c pkg = makePackage(g.Id, 'FLS Package');
Vehicle_Schedule__c s = makeSchedule('FLS Schedule', 'Premium_Tier', true);
MasterPackageScheduleService.AssignmentForm a = new MasterPackageScheduleService.AssignmentForm();
a.scheduleId = String.valueOf(s.Id);
a.packageId = String.valueOf(pkg.Id);
MasterPackageScheduleService.MemberForm m = new MasterPackageScheduleService.MemberForm();
m.scheduleId = String.valueOf(s.Id);
m.includeAllModels = true;
MasterPackageScheduleService.simulateFieldAccessDenied = true;
Test.startTest();
MasterPackageScheduleService.SaveResult blockedAssign = MasterPackageScheduleService.saveAssignment(a);
MasterPackageScheduleService.SaveResult blockedMember = MasterPackageScheduleService.saveMember(m);
Test.stopTest();
MasterPackageScheduleService.simulateFieldAccessDenied = false;
Assert.isFalse(blockedAssign.success, 'a denied field fails closed');
Assert.isTrue(blockedAssign.message.containsIgnoreCase('permission'), blockedAssign.message);
Assert.isFalse(blockedMember.success, 'member create is blocked when a field cannot be set');
Assert.areEqual(0, [SELECT COUNT() FROM Vehicle_Schedule_Member__c WHERE Vehicle_Schedule__c = :s.Id],
'no DML happened under the FLS guard');
}
@IsTest
static void nullFormsAndNullIdsAreRefusedGracefully() {
Test.startTest();
Assert.isFalse(MasterPackageScheduleService.saveSchedule(null).success);
Assert.isFalse(MasterPackageScheduleService.saveMember(null).success);
Assert.isFalse(MasterPackageScheduleService.saveAssignment(null).success);
Assert.isFalse(MasterPackageScheduleService.deleteMember(null).success);
Assert.isFalse(MasterPackageScheduleService.deleteAssignment(null).success);
Assert.isFalse(MasterPackageScheduleService.setScheduleActive(null, null).success);
Assert.isFalse(MasterPackageScheduleService.moveMember(null, null).success);
Test.stopTest();
}
}