public with sharing class MasterPackageAdminService {
private static final String DASH = '\u2014';
@TestVisible
private static Boolean simulateFieldAccessDenied = false;
public class PackageRow {
@AuraEnabled public Id id;
@AuraEnabled public String name;
@AuraEnabled public String perClaimLimitLabel;
@AuraEnabled public String deductibleLabel;
@AuraEnabled public String eligibilityLabel;
@AuraEnabled public String packageTypeLabel;
@AuraEnabled public String categoryLabel;
@AuraEnabled public String classLabel;
@AuraEnabled public Boolean isActive;
@AuraEnabled public String statusLabel;
@AuraEnabled public String statusTone;
@AuraEnabled public Integer tierCount;
@AuraEnabled public Integer termCount;
}
public class TermRow {
@AuraEnabled public Id id;
@AuraEnabled public String name;
@AuraEnabled public Decimal price;
@AuraEnabled public String priceLabel;
@AuraEnabled public String tierId;
@AuraEnabled public String durationType;
@AuraEnabled public Decimal odometerKm;
@AuraEnabled public String restrictionType;
@AuraEnabled public String classValue;
@AuraEnabled public Decimal byYear;
@AuraEnabled public Decimal perClaimLimit;
@AuraEnabled public Boolean allowDeferral;
}
public class TierBlock {
@AuraEnabled public String groupKey;
@AuraEnabled public String tierId;
@AuraEnabled public String tierName;
@AuraEnabled public String bandLabel;
@AuraEnabled public Boolean hasTier;
@AuraEnabled public Decimal startMileage;
@AuraEnabled public Decimal endMileage;
@AuraEnabled public String mileageUnit;
@AuraEnabled public List<TermRow> terms;
public TierBlock() { hasTier = false; terms = new List<TermRow>(); }
}
public class AddOnRow {
@AuraEnabled public Id id;
@AuraEnabled public String label;
@AuraEnabled public String priceLabel;
@AuraEnabled public String termId;
@AuraEnabled public String addOnType;
@AuraEnabled public Decimal price;
}
public class BenefitCapRow {
@AuraEnabled public Id id;
@AuraEnabled public String label;
@AuraEnabled public String capLabel;
@AuraEnabled public String termId;
@AuraEnabled public String benefitType;
@AuraEnabled public Decimal capAmount;
}
public class OptionRow {
@AuraEnabled public Id id;
@AuraEnabled public String label;
@AuraEnabled public String selectionLabel;
@AuraEnabled public String categoryLabel;
@AuraEnabled public String priceLabel;
@AuraEnabled public String optionId;
@AuraEnabled public String packageId;
@AuraEnabled public String termId;
@AuraEnabled public Decimal price;
@AuraEnabled public String selectionType;
@AuraEnabled public String category;
@AuraEnabled public String inclusionText;
@AuraEnabled public String exclusionText;
@AuraEnabled public String inclusionLabel;
@AuraEnabled public String exclusionLabel;
}
public class PackageDetail {
@AuraEnabled public Id id;
@AuraEnabled public String name;
@AuraEnabled public String groupName;
@AuraEnabled public String groupId;
@AuraEnabled public String releaseName;
@AuraEnabled public String releaseStatus;
@AuraEnabled public String perClaimLimitLabel;
@AuraEnabled public String deductibleLabel;
@AuraEnabled public String eligibilityYearLabel;
@AuraEnabled public String odometerCapLabel;
@AuraEnabled public String packageTypeLabel;
@AuraEnabled public String categoryLabel;
@AuraEnabled public String classLabel;
@AuraEnabled public String recordTypeLabel;
@AuraEnabled public String descriptionLabel;
@AuraEnabled public Boolean isActive;
@AuraEnabled public String statusLabel;
@AuraEnabled public Boolean hasTiers;
@AuraEnabled public Integer termCount;
@AuraEnabled public Integer tierCount;
@AuraEnabled public Integer optionCount;
@AuraEnabled public Integer addOnCount;
@AuraEnabled public Integer benefitCapCount;
@AuraEnabled public Decimal coveragePerClaim;
@AuraEnabled public Decimal deductible;
@AuraEnabled public String modelYearRestriction;
@AuraEnabled public Decimal mileage;
@AuraEnabled public String mileageUnit;
@AuraEnabled public String packageType;
@AuraEnabled public String category;
@AuraEnabled public String classValue;
@AuraEnabled public List<TierBlock> tierBlocks;
@AuraEnabled public List<OptionRow> options;
@AuraEnabled public List<AddOnRow> addOns;
@AuraEnabled public List<BenefitCapRow> benefitCaps;
public PackageDetail() {
hasTiers = false;
termCount = 0; tierCount = 0; optionCount = 0; addOnCount = 0; benefitCapCount = 0;
tierBlocks = new List<TierBlock>();
options = new List<OptionRow>();
addOns = new List<AddOnRow>();
benefitCaps = new List<BenefitCapRow>();
}
}
public class SaveResult {
@AuraEnabled public Boolean success;
@AuraEnabled public String message;
@AuraEnabled public Id recordId;
public SaveResult(Boolean success, String message, Id recordId) {
this.success = success; this.message = message; this.recordId = recordId;
}
}
public class Choice {
@AuraEnabled public String value;
@AuraEnabled public String label;
public Choice(String value, String label) { this.value = value; this.label = label; }
}
public class FormOptions {
@AuraEnabled public List<Choice> packageTypeOptions = new List<Choice>();
@AuraEnabled public List<Choice> categoryOptions = new List<Choice>();
@AuraEnabled public List<Choice> classOptions = new List<Choice>();
@AuraEnabled public List<Choice> mileageUnitOptions = new List<Choice>();
@AuraEnabled public List<Choice> termDurationTypeOptions = new List<Choice>();
@AuraEnabled public List<Choice> termRestrictionTypeOptions = new List<Choice>();
@AuraEnabled public List<Choice> termClassOptions = new List<Choice>();
@AuraEnabled public List<Choice> selectionTypeOptions = new List<Choice>();
@AuraEnabled public List<Choice> optionCategoryOptions = new List<Choice>();
@AuraEnabled public List<Choice> addOnTypeOptions = new List<Choice>();
@AuraEnabled public List<Choice> benefitTypeOptions = new List<Choice>();
@AuraEnabled public List<Choice> optionChoices = new List<Choice>();
@AuraEnabled public List<Choice> groupChoices = new List<Choice>();
public FormOptions() {}
}
public class PackageForm {
@AuraEnabled public String recordId { get; set; }
@AuraEnabled public String name { get; set; }
@AuraEnabled public String groupId { get; set; }
@AuraEnabled public Decimal coveragePerClaim { get; set; }
@AuraEnabled public Decimal deductible { get; set; }
@AuraEnabled public String modelYearRestriction { get; set; }
@AuraEnabled public Decimal mileage { get; set; }
@AuraEnabled public String mileageUnit { get; set; }
@AuraEnabled public String packageType { get; set; }
@AuraEnabled public String category { get; set; }
@AuraEnabled public String classValue { get; set; }
@AuraEnabled public Boolean isActive { get; set; }
public PackageForm() {}
}
public class TierForm {
@AuraEnabled public String recordId { get; set; }
@AuraEnabled public String packageId { get; set; }
@AuraEnabled public String name { get; set; }
@AuraEnabled public Decimal startMileage { get; set; }
@AuraEnabled public Decimal endMileage { get; set; }
@AuraEnabled public String mileageUnit { get; set; }
public TierForm() {}
}
public class TermForm {
@AuraEnabled public String recordId { get; set; }
@AuraEnabled public String packageId { get; set; }
@AuraEnabled public String tierId { get; set; }
@AuraEnabled public String name { get; set; }
@AuraEnabled public Decimal price { get; set; }
@AuraEnabled public String durationType { get; set; }
@AuraEnabled public Decimal odometerKm { get; set; }
@AuraEnabled public String restrictionType { get; set; }
@AuraEnabled public String classValue { get; set; }
@AuraEnabled public Decimal byYear { get; set; }
@AuraEnabled public Decimal perClaimLimit { get; set; }
@AuraEnabled public Boolean allowDeferral { get; set; }
public TermForm() {}
}
public class OptionForm {
@AuraEnabled public String recordId { get; set; }
@AuraEnabled public String packageId { get; set; }
@AuraEnabled public String termId { get; set; }
@AuraEnabled public String optionId { get; set; }
@AuraEnabled public Decimal price { get; set; }
@AuraEnabled public String selectionType { get; set; }
@AuraEnabled public String category { get; set; }
@AuraEnabled public String inclusionText { get; set; }
@AuraEnabled public String exclusionText { get; set; }
public OptionForm() {}
}
public class AddOnForm {
@AuraEnabled public String recordId { get; set; }
@AuraEnabled public String termId { get; set; }
@AuraEnabled public String addOnType { get; set; }
@AuraEnabled public Decimal price { get; set; }
public AddOnForm() {}
}
public class BenefitCapForm {
@AuraEnabled public String recordId { get; set; }
@AuraEnabled public String termId { get; set; }
@AuraEnabled public String benefitType { get; set; }
@AuraEnabled public Decimal capAmount { get; set; }
public BenefitCapForm() {}
}
@AuraEnabled(cacheable=true)
public static List<PackageRow> getPackages(Id groupId) {
List<PackageRow> rows = new List<PackageRow>();
if (groupId == null) { return rows; }
for (Package__c p : [
SELECT Id, Name, Coverage_per_claim__c, Deductible__c, Model_Year_Restriction__c,
Mileage_Restriction__c, Mileage_Unit__c, Package_Type__c, Category__c, Class__c,
Is_Active__c,
(SELECT Id FROM PackageItem__r),
(SELECT Id FROM Package_Term_Tiers__r)
FROM Package__c
WHERE Package_Group__c = :groupId
ORDER BY Name
]) {
rows.add(toPackageRow(p));
}
return rows;
}
@AuraEnabled(cacheable=true)
public static PackageDetail getPackageDetail(Id packageId) {
PackageDetail dto = new PackageDetail();
if (packageId == null) { return dto; }
List<Package__c> packages = [
SELECT Id, Name, Coverage_per_claim__c, Deductible__c, Model_Year_Restriction__c,
Mileage_Restriction__c, Mileage_Unit__c, Package_Type__c, Category__c, Class__c,
Is_Active__c, Package_Group__c, Description__c, RecordType.Name,
Package_Group__r.Name,
Package_Group__r.Catalogue_Release__r.Name,
Package_Group__r.Catalogue_Release__r.Status__c
FROM Package__c WHERE Id = :packageId LIMIT 1
];
if (packages.isEmpty()) { return dto; }
Package__c p = packages[0];
dto.id = p.Id;
dto.name = p.Name;
dto.groupName = p.Package_Group__r != null ? p.Package_Group__r.Name : '';
dto.groupId = p.Package_Group__c == null ? null : String.valueOf(p.Package_Group__c);
dto.releaseName = releaseNameOf(p);
dto.releaseStatus = releaseStatusOf(p);
dto.perClaimLimitLabel = perClaimLabel(p.Coverage_per_claim__c);
dto.deductibleLabel = deductibleLabel(p.Deductible__c);
dto.eligibilityYearLabel = valueOrDash(p.Model_Year_Restriction__c);
dto.odometerCapLabel = mileageLabel(p.Mileage_Restriction__c, p.Mileage_Unit__c);
dto.packageTypeLabel = valueOrDash(p.Package_Type__c);
dto.categoryLabel = valueOrDash(p.Category__c);
dto.classLabel = valueOrDash(p.Class__c);
dto.recordTypeLabel = p.RecordType == null ? DASH : valueOrDash(p.RecordType.Name);
dto.descriptionLabel = valueOrDash(p.Description__c);
dto.isActive = p.Is_Active__c == true;
dto.statusLabel = dto.isActive ? 'Active' : 'Inactive';
dto.coveragePerClaim = p.Coverage_per_claim__c;
dto.deductible = p.Deductible__c;
dto.modelYearRestriction = p.Model_Year_Restriction__c;
dto.mileage = p.Mileage_Restriction__c;
dto.mileageUnit = p.Mileage_Unit__c;
dto.packageType = p.Package_Type__c;
dto.category = p.Category__c;
dto.classValue = p.Class__c;
List<Package_Tier__c> tiers = [
SELECT Id, Name, Mileage_Restriction_Start__c, Mileage_Restriction_End__c, Mileage_Unit__c
FROM Package_Tier__c WHERE Package__c = :packageId
ORDER BY Mileage_Restriction_Start__c NULLS LAST, Name
];
dto.hasTiers = !tiers.isEmpty();
dto.tierCount = tiers.size();
List<Package_Term__c> terms = [
SELECT Id, Name, Price__c, Package_Tier__c, Duration_Type__c, Odometer_KM__c,
Restriction_Type__c, Class__c, ByYear__c, Per_Claim_Limit__c, Allow_Deferral__c
FROM Package_Term__c WHERE Package__c = :packageId ORDER BY Name
];
dto.termCount = terms.size();
Map<Id, List<Package_Term__c>> termsByTier = new Map<Id, List<Package_Term__c>>();
List<Package_Term__c> tierless = new List<Package_Term__c>();
for (Package_Term__c t : terms) {
if (t.Package_Tier__c == null) { tierless.add(t); continue; }
if (!termsByTier.containsKey(t.Package_Tier__c)) {
termsByTier.put(t.Package_Tier__c, new List<Package_Term__c>());
}
termsByTier.get(t.Package_Tier__c).add(t);
}
for (Package_Tier__c tier : tiers) {
TierBlock block = new TierBlock();
block.groupKey = 'tier-' + String.valueOf(tier.Id);
block.tierId = String.valueOf(tier.Id);
block.tierName = tier.Name;
block.bandLabel = bandLabel(tier);
block.hasTier = true;
block.startMileage = tier.Mileage_Restriction_Start__c;
block.endMileage = tier.Mileage_Restriction_End__c;
block.mileageUnit = tier.Mileage_Unit__c;
List<Package_Term__c> tierTerms = termsByTier.get(tier.Id);
if (tierTerms != null) {
for (Package_Term__c t : tierTerms) { block.terms.add(toTermRow(t)); }
}
dto.tierBlocks.add(block);
}
if (!tierless.isEmpty()) {
TierBlock block = new TierBlock();
block.groupKey = 'no-tier';
block.tierName = '';
block.bandLabel = 'All terms';
block.hasTier = false;
for (Package_Term__c t : tierless) { block.terms.add(toTermRow(t)); }
dto.tierBlocks.add(block);
}
for (Package_Option__c o : [
SELECT Id, Option__c, Option__r.Name, Name, Selection_Type__c, Category__c, Price__c,
Package__c, Package_Term__c, Inclusion_Text__c, Exclusion_Text__c
FROM Package_Option__c WHERE Package__c = :packageId
ORDER BY Option__r.Name NULLS LAST, Name
]) {
OptionRow row = new OptionRow();
row.id = o.Id;
String optionName = o.Option__r != null ? o.Option__r.Name : null;
row.label = !String.isBlank(optionName) ? optionName
: (String.isNotBlank(o.Name) ? o.Name : 'Add-on');
row.selectionLabel = valueOrDash(o.Selection_Type__c);
row.categoryLabel = valueOrDash(o.Category__c);
row.priceLabel = moneyOrDash(o.Price__c);
row.optionId = o.Option__c == null ? null : String.valueOf(o.Option__c);
row.packageId = o.Package__c == null ? null : String.valueOf(o.Package__c);
row.termId = o.Package_Term__c == null ? null : String.valueOf(o.Package_Term__c);
row.price = o.Price__c;
row.selectionType = o.Selection_Type__c;
row.category = o.Category__c;
row.inclusionText = o.Inclusion_Text__c;
row.exclusionText = o.Exclusion_Text__c;
row.inclusionLabel = valueOrDash(o.Inclusion_Text__c);
row.exclusionLabel = valueOrDash(o.Exclusion_Text__c);
dto.options.add(row);
}
dto.optionCount = dto.options.size();
for (Package_Add_On__c a : [
SELECT Id, Add_On_Type__c, Price__c, Package_Term__c
FROM Package_Add_On__c WHERE Package_Term__r.Package__c = :packageId ORDER BY Add_On_Type__c
]) {
AddOnRow row = new AddOnRow();
row.id = a.Id;
row.label = valueOrDash(a.Add_On_Type__c);
row.priceLabel = moneyOrDash(a.Price__c);
row.termId = a.Package_Term__c == null ? null : String.valueOf(a.Package_Term__c);
row.addOnType = a.Add_On_Type__c;
row.price = a.Price__c;
dto.addOns.add(row);
}
dto.addOnCount = dto.addOns.size();
for (Package_Benefit_Cap__c b : [
SELECT Id, Benefit_Type__c, Cap_Amount__c, Package_Term__c
FROM Package_Benefit_Cap__c WHERE Package_Term__r.Package__c = :packageId ORDER BY Benefit_Type__c
]) {
BenefitCapRow row = new BenefitCapRow();
row.id = b.Id;
row.label = valueOrDash(b.Benefit_Type__c);
row.capLabel = moneyOrDash(b.Cap_Amount__c);
row.termId = b.Package_Term__c == null ? null : String.valueOf(b.Package_Term__c);
row.benefitType = b.Benefit_Type__c;
row.capAmount = b.Cap_Amount__c;
dto.benefitCaps.add(row);
}
dto.benefitCapCount = dto.benefitCaps.size();
return dto;
}
@AuraEnabled(cacheable=true)
public static FormOptions getFormOptions() {
FormOptions options = new FormOptions();
options.packageTypeOptions = picklistChoices(Package__c.Package_Type__c);
options.categoryOptions = picklistChoices(Package__c.Category__c);
options.classOptions = picklistChoices(Package__c.Class__c);
options.mileageUnitOptions = picklistChoices(Package__c.Mileage_Unit__c);
options.termDurationTypeOptions = picklistChoices(Package_Term__c.Duration_Type__c);
options.termRestrictionTypeOptions = picklistChoices(Package_Term__c.Restriction_Type__c);
options.termClassOptions = picklistChoices(Package_Term__c.Class__c);
options.selectionTypeOptions = picklistChoices(Package_Option__c.Selection_Type__c);
options.optionCategoryOptions = picklistChoices(Package_Option__c.Category__c);
options.addOnTypeOptions = picklistChoices(Package_Add_On__c.Add_On_Type__c);
options.benefitTypeOptions = picklistChoices(Package_Benefit_Cap__c.Benefit_Type__c);
for (Option__c opt : [SELECT Id, Name FROM Option__c ORDER BY Name]) {
options.optionChoices.add(new Choice(String.valueOf(opt.Id), opt.Name));
}
for (Package_Group__c grp : [SELECT Id, Name FROM Package_Group__c ORDER BY Name]) {
options.groupChoices.add(new Choice(String.valueOf(grp.Id), grp.Name));
}
return options;
}
@AuraEnabled
public static SaveResult createBlankPackage(Id groupId) {
try {
if (groupId == null) { return fail('Choose the package group the new package belongs to.'); }
if (!groupExists(groupId)) { return fail('That package group no longer exists.'); }
String guard = guardCreate(new List<SObjectField>{
Package__c.Name, Package__c.Package_Group__c, Package__c.Is_Active__c });
if (guard != null) { return fail(guard); }
Package__c pkg = new Package__c(
Name = 'New Master Package',
Package_Group__c = groupId,
Is_Active__c = true,
Commercial_Business_Use__c = false
);
insert pkg;
return ok('Blank package created. Fill in its details and save.', pkg.Id);
} catch (Exception e) {
return fail('Could not create the package: ' + e.getMessage());
}
}
@AuraEnabled
public static SaveResult updatePackage(PackageForm form) {
try {
if (form == null || String.isBlank(form.recordId)) { return fail('No package was identified.'); }
List<Package__c> found = [
SELECT Id FROM Package__c WHERE Id = :form.recordId LIMIT 1
];
if (found.isEmpty()) { return fail('That master package no longer exists.'); }
if (String.isBlank(form.name)) { return fail('Package Name is required.'); }
if (String.isNotBlank(form.groupId) && !groupExists(form.groupId)) {
return fail('That package group no longer exists.');
}
if (form.coveragePerClaim != null && form.coveragePerClaim < 0) {
return fail('Per Claim Limit cannot be negative.');
}
if (form.deductible != null && form.deductible < 0) { return fail('Deductible cannot be negative.'); }
if (form.mileage != null && form.mileage < 0) { return fail('Mileage cannot be negative.'); }
String guard = picklistGuard(Package__c.Package_Type__c, form.packageType);
if (guard == null) { guard = picklistGuard(Package__c.Category__c, form.category); }
if (guard == null) { guard = picklistGuard(Package__c.Class__c, form.classValue); }
if (guard == null) { guard = picklistGuard(Package__c.Mileage_Unit__c, form.mileageUnit); }
if (guard == null) { guard = guardEdit(new List<SObjectField>{
Package__c.Name, Package__c.Coverage_per_claim__c, Package__c.Deductible__c,
Package__c.Model_Year_Restriction__c, Package__c.Mileage_Restriction__c,
Package__c.Mileage_Unit__c, Package__c.Package_Type__c, Package__c.Category__c,
Package__c.Class__c, Package__c.Is_Active__c }); }
if (guard == null && String.isNotBlank(form.groupId)) { guard = guardEdit(new List<SObjectField>{ Package__c.Package_Group__c }); }
if (guard != null) { return fail(guard); }
Package__c save = new Package__c(Id = found[0].Id);
save.Name = form.name.trim();
if (String.isNotBlank(form.groupId)) { save.Package_Group__c = form.groupId; }
save.Coverage_per_claim__c = form.coveragePerClaim;
save.Deductible__c = form.deductible;
save.Model_Year_Restriction__c = form.modelYearRestriction;
save.Mileage_Restriction__c = form.mileage;
save.Mileage_Unit__c = form.mileageUnit;
save.Package_Type__c = form.packageType;
save.Category__c = form.category;
save.Class__c = form.classValue;
if (form.isActive != null) { save.Is_Active__c = form.isActive; }
update save;
return ok('Package saved.', save.Id);
} catch (Exception e) {
return fail('Could not save the package: ' + e.getMessage());
}
}
@AuraEnabled
public static SaveResult setPackageActive(Id packageId, Boolean active) {
try {
if (packageId == null) { return fail('No package was identified.'); }
if (active == null) { return fail('Choose whether the package should be active.'); }
String guard = guardEdit(new List<SObjectField>{ Package__c.Is_Active__c });
if (guard != null) { return fail(guard); }
List<Package__c> found = [SELECT Id FROM Package__c WHERE Id = :packageId LIMIT 1];
if (found.isEmpty()) { return fail('That master package no longer exists.'); }
update new Package__c(Id = found[0].Id, Is_Active__c = active);
return ok(active ? 'Package activated.' : 'Package deactivated (kept, not deleted).', found[0].Id);
} catch (Exception e) {
return fail('Could not update the package status: ' + e.getMessage());
}
}
@AuraEnabled
public static SaveResult saveTier(TierForm form) {
try {
if (form == null) { return fail('No band details were provided.'); }
Boolean isNew = String.isBlank(form.recordId);
Id packageId;
if (isNew) {
if (String.isBlank(form.packageId)) { return fail('No package was identified for the new band.'); }
packageId = form.packageId;
if (!packageExists(packageId)) { return fail('That master package no longer exists.'); }
} else {
List<Package_Tier__c> found = [SELECT Id, Package__c FROM Package_Tier__c WHERE Id = :form.recordId LIMIT 1];
if (found.isEmpty()) { return fail('That odometer band no longer exists.'); }
packageId = found[0].Package__c;
}
if (String.isBlank(form.name)) { return fail('Band Name is required.'); }
if (form.startMileage != null && form.startMileage < 0) { return fail('Band minimum cannot be negative.'); }
if (form.endMileage != null && form.endMileage < 0) { return fail('Band maximum cannot be negative.'); }
if (form.startMileage != null && form.endMileage != null && form.startMileage > form.endMileage) {
return fail('Band minimum cannot be greater than its maximum.');
}
String guard = picklistGuard(Package_Tier__c.Mileage_Unit__c, form.mileageUnit);
if (guard == null) {
List<SObjectField> fields = new List<SObjectField>{
Package_Tier__c.Name, Package_Tier__c.Package__c,
Package_Tier__c.Mileage_Restriction_Start__c,
Package_Tier__c.Mileage_Restriction_End__c, Package_Tier__c.Mileage_Unit__c };
guard = isNew ? guardCreate(fields) : guardEdit(fields);
}
if (guard != null) { return fail(guard); }
Package_Tier__c save = isNew ? new Package_Tier__c(Package__c = packageId) : new Package_Tier__c(Id = form.recordId);
save.Name = form.name.trim();
save.Mileage_Restriction_Start__c = form.startMileage;
save.Mileage_Restriction_End__c = form.endMileage;
save.Mileage_Unit__c = form.mileageUnit;
if (isNew) { insert save; } else { update save; }
return ok('Odometer band saved.', save.Id);
} catch (Exception e) {
return fail('Could not save the odometer band: ' + e.getMessage());
}
}
@AuraEnabled
public static SaveResult deleteTier(Id tierId) {
try {
if (tierId == null) { return fail('No band was identified.'); }
List<Package_Tier__c> found = [SELECT Id FROM Package_Tier__c WHERE Id = :tierId LIMIT 1];
if (found.isEmpty()) { return fail('That odometer band no longer exists.'); }
Integer linked = [SELECT COUNT() FROM Package_Term__c WHERE Package_Tier__c = :tierId];
if (linked > 0) {
return fail('This band still has ' + linked + ' term'
+ (linked == 1 ? '' : 's') + ' under it. Move or remove those terms first.');
}
delete found[0];
return ok('Odometer band removed.', null);
} catch (Exception e) {
return fail('Could not remove the odometer band: ' + e.getMessage());
}
}
@AuraEnabled
public static SaveResult saveTerm(TermForm form) {
try {
if (form == null) { return fail('No term details were provided.'); }
Boolean isNew = String.isBlank(form.recordId);
Id packageId;
if (isNew) {
if (String.isBlank(form.packageId)) { return fail('No package was identified for the new term.'); }
packageId = form.packageId;
if (!packageExists(packageId)) { return fail('That master package no longer exists.'); }
} else {
List<Package_Term__c> found = [SELECT Id, Package__c FROM Package_Term__c WHERE Id = :form.recordId LIMIT 1];
if (found.isEmpty()) { return fail('That package term no longer exists.'); }
packageId = found[0].Package__c;
}
if (String.isBlank(form.name)) { return fail('Term Name is required.'); }
if (form.price == null) { return fail('Price is required — the term is the price anchor.'); }
if (form.price < 0) { return fail('Price cannot be negative.'); }
if (form.perClaimLimit != null && form.perClaimLimit < 0) { return fail('Per Claim Limit cannot be negative.'); }
if (form.odometerKm != null && form.odometerKm < 0) { return fail('Odometer cannot be negative.'); }
if (form.byYear != null && form.byYear < 0) { return fail('Max. Vehicle Age cannot be negative.'); }
if (String.isNotBlank(form.tierId)) {
String tierCheck = tierBelongsToPackage(form.tierId, packageId);
if (tierCheck != null) { return fail(tierCheck); }
}
String guard = picklistGuard(Package_Term__c.Duration_Type__c, form.durationType);
if (guard == null) { guard = picklistGuard(Package_Term__c.Restriction_Type__c, form.restrictionType); }
if (guard == null) { guard = picklistGuard(Package_Term__c.Class__c, form.classValue); }
if (guard == null) {
List<SObjectField> fields = new List<SObjectField>{
Package_Term__c.Name, Package_Term__c.Package__c, Package_Term__c.Price__c,
Package_Term__c.Package_Tier__c, Package_Term__c.Duration_Type__c,
Package_Term__c.Odometer_KM__c, Package_Term__c.Restriction_Type__c,
Package_Term__c.Class__c, Package_Term__c.ByYear__c,
Package_Term__c.Per_Claim_Limit__c, Package_Term__c.Allow_Deferral__c };
guard = isNew ? guardCreate(fields) : guardEdit(fields);
}
if (guard != null) { return fail(guard); }
Package_Term__c save = isNew ? new Package_Term__c(Package__c = packageId) : new Package_Term__c(Id = form.recordId);
save.Name = form.name.trim();
save.Price__c = form.price;
if (String.isNotBlank(form.tierId)) {
save.Package_Tier__c = form.tierId;
} else if (isNew) {
save.Package_Tier__c = null;
}
save.Duration_Type__c = form.durationType;
save.Odometer_KM__c = form.odometerKm;
save.Restriction_Type__c = form.restrictionType;
save.Class__c = form.classValue;
if (form.byYear != null) { save.ByYear__c = form.byYear; }
save.Per_Claim_Limit__c = form.perClaimLimit;
if (form.allowDeferral != null) { save.Allow_Deferral__c = form.allowDeferral; }
if (isNew) { insert save; } else { update save; }
return ok('Term saved.', save.Id);
} catch (Exception e) {
return fail('Could not save the term: ' + e.getMessage());
}
}
@AuraEnabled
public static SaveResult deleteTerm(Id termId) {
try {
if (termId == null) { return fail('No term was identified.'); }
List<Package_Term__c> found = [SELECT Id FROM Package_Term__c WHERE Id = :termId LIMIT 1];
if (found.isEmpty()) { return fail('That package term no longer exists.'); }
Integer linked = [SELECT COUNT() FROM Package_Add_On__c WHERE Package_Term__c = :termId]
+ [SELECT COUNT() FROM Package_Benefit_Cap__c WHERE Package_Term__c = :termId]
+ [SELECT COUNT() FROM Package_Option__c WHERE Package_Term__c = :termId];
if (linked > 0) {
return fail('This term still has ' + linked + ' linked row'
+ (linked == 1 ? '' : 's') + ' (add-ons, capped benefits or options). Remove those first.');
}
delete found[0];
return ok('Term removed from the master book. Any synced dealer copy is not removed by this action.', null);
} catch (Exception e) {
return fail('Could not remove the term: ' + e.getMessage());
}
}
@AuraEnabled
public static SaveResult saveOption(OptionForm form) {
try {
if (form == null) { return fail('No option details were provided.'); }
Boolean isNew = String.isBlank(form.recordId);
Id packageId = form.packageId;
if (!isNew) {
List<Package_Option__c> found = [SELECT Id, Package__c FROM Package_Option__c WHERE Id = :form.recordId LIMIT 1];
if (found.isEmpty()) { return fail('That option row no longer exists.'); }
packageId = found[0].Package__c;
}
if (String.isBlank(packageId)) { return fail('No package was identified for the option.'); }
if (!packageExists(packageId)) { return fail('That master package no longer exists.'); }
if (String.isBlank(form.optionId)) { return fail('Choose the option this row is for.'); }
if (!optionExists(form.optionId)) { return fail('That option no longer exists in the option catalogue.'); }
String selection = form.selectionType;
if (String.isBlank(selection)) { return fail('Selection Type is required (Included or Optional).'); }
String guard = picklistGuard(Package_Option__c.Selection_Type__c, selection);
if (guard == null) { guard = picklistGuard(Package_Option__c.Category__c, form.category); }
if (guard != null) { return fail(guard); }
Boolean isOptional = 'Optional'.equalsIgnoreCase(selection);
if (isOptional) {
if (form.price == null || form.price < 0) {
return fail('Price must be greater than or equal to 0 for an Optional row.');
}
} else if (form.price != null && form.price != 0) {
return fail('An Included row cannot carry a price.');
}
if (String.isNotBlank(form.termId)) {
String termCheck = termBelongsToPackage(form.termId, packageId);
if (termCheck != null) { return fail(termCheck); }
}
List<SObjectField> fields = new List<SObjectField>{
Package_Option__c.Option__c, Package_Option__c.Package__c, Package_Option__c.Package_Term__c,
Package_Option__c.Selection_Type__c, Package_Option__c.Price__c, Package_Option__c.Category__c,
Package_Option__c.Inclusion_Text__c, Package_Option__c.Exclusion_Text__c };
guard = isNew ? guardCreate(fields) : guardEdit(fields);
if (guard != null) { return fail(guard); }
Package_Option__c save = isNew
? new Package_Option__c(Package__c = packageId, Option__c = form.optionId)
: new Package_Option__c(Id = form.recordId);
save.Option__c = form.optionId;
save.Selection_Type__c = selection;
save.Price__c = isOptional ? form.price : null;
save.Category__c = form.category;
save.Inclusion_Text__c = form.inclusionText;
save.Exclusion_Text__c = form.exclusionText;
if (isNew) {
save.Package_Term__c = String.isNotBlank(form.termId) ? form.termId : null;
} else if (String.isNotBlank(form.termId)) {
save.Package_Term__c = form.termId;
}
if (isNew) { insert save; } else { update save; }
return ok('Option saved.', save.Id);
} catch (Exception e) {
return fail('Could not save the option: ' + e.getMessage());
}
}
@AuraEnabled
public static SaveResult deleteOptionRow(Id optionRowId) {
try {
if (optionRowId == null) { return fail('No option row was identified.'); }
List<Package_Option__c> found = [SELECT Id FROM Package_Option__c WHERE Id = :optionRowId LIMIT 1];
if (found.isEmpty()) { return fail('That option row no longer exists.'); }
delete found[0];
return ok('Option removed.', null);
} catch (Exception e) {
return fail('Could not remove the option: ' + e.getMessage());
}
}
@AuraEnabled
public static SaveResult saveAddOn(AddOnForm form) {
try {
if (form == null) { return fail('No add-on details were provided.'); }
Boolean isNew = String.isBlank(form.recordId);
if (isNew) {
if (String.isBlank(form.termId)) { return fail('Choose the term this add-on belongs to.'); }
if (!termExists(form.termId)) { return fail('That package term no longer exists.'); }
} else {
List<Package_Add_On__c> found = [SELECT Id FROM Package_Add_On__c WHERE Id = :form.recordId LIMIT 1];
if (found.isEmpty()) { return fail('That add-on no longer exists.'); }
}
if (String.isBlank(form.addOnType)) { return fail('Add-On Type is required.'); }
if (form.price != null && form.price < 0) { return fail('Price cannot be negative.'); }
String guard = picklistGuard(Package_Add_On__c.Add_On_Type__c, form.addOnType);
if (guard == null) {
List<SObjectField> fields = new List<SObjectField>{
Package_Add_On__c.Add_On_Type__c, Package_Add_On__c.Price__c };
if (isNew) { fields.add(Package_Add_On__c.Package_Term__c); }
guard = isNew ? guardCreate(fields) : guardEdit(fields);
}
if (guard != null) { return fail(guard); }
Package_Add_On__c save = isNew
? new Package_Add_On__c(Package_Term__c = form.termId)
: new Package_Add_On__c(Id = form.recordId);
save.Add_On_Type__c = form.addOnType;
save.Price__c = form.price;
if (isNew) { insert save; } else { update save; }
return ok('Add-on saved.', save.Id);
} catch (Exception e) {
return fail('Could not save the add-on: ' + e.getMessage());
}
}
@AuraEnabled
public static SaveResult deleteAddOn(Id addOnId) {
try {
if (addOnId == null) { return fail('No add-on was identified.'); }
List<Package_Add_On__c> found = [SELECT Id FROM Package_Add_On__c WHERE Id = :addOnId LIMIT 1];
if (found.isEmpty()) { return fail('That add-on no longer exists.'); }
delete found[0];
return ok('Add-on removed.', null);
} catch (Exception e) {
return fail('Could not remove the add-on: ' + e.getMessage());
}
}
@AuraEnabled
public static SaveResult saveBenefitCap(BenefitCapForm form) {
try {
if (form == null) { return fail('No capped-benefit details were provided.'); }
Boolean isNew = String.isBlank(form.recordId);
if (isNew) {
if (String.isBlank(form.termId)) { return fail('Choose the term this capped benefit belongs to.'); }
if (!termExists(form.termId)) { return fail('That package term no longer exists.'); }
} else {
List<Package_Benefit_Cap__c> found = [SELECT Id FROM Package_Benefit_Cap__c WHERE Id = :form.recordId LIMIT 1];
if (found.isEmpty()) { return fail('That capped benefit no longer exists.'); }
}
if (String.isBlank(form.benefitType)) { return fail('Benefit Type is required.'); }
if (form.capAmount == null) { return fail('Cap Amount is required.'); }
if (form.capAmount < 0) { return fail('Cap Amount cannot be negative.'); }
String guard = picklistGuard(Package_Benefit_Cap__c.Benefit_Type__c, form.benefitType);
if (guard == null) {
List<SObjectField> fields = new List<SObjectField>{
Package_Benefit_Cap__c.Benefit_Type__c, Package_Benefit_Cap__c.Cap_Amount__c };
if (isNew) { fields.add(Package_Benefit_Cap__c.Package_Term__c); }
guard = isNew ? guardCreate(fields) : guardEdit(fields);
}
if (guard != null) { return fail(guard); }
Package_Benefit_Cap__c save = isNew
? new Package_Benefit_Cap__c(Package_Term__c = form.termId)
: new Package_Benefit_Cap__c(Id = form.recordId);
save.Benefit_Type__c = form.benefitType;
save.Cap_Amount__c = form.capAmount;
if (isNew) { insert save; } else { update save; }
return ok('Capped benefit saved.', save.Id);
} catch (Exception e) {
return fail('Could not save the capped benefit: ' + e.getMessage());
}
}
@AuraEnabled
public static SaveResult deleteBenefitCap(Id benefitCapId) {
try {
if (benefitCapId == null) { return fail('No capped benefit was identified.'); }
List<Package_Benefit_Cap__c> found = [SELECT Id FROM Package_Benefit_Cap__c WHERE Id = :benefitCapId LIMIT 1];
if (found.isEmpty()) { return fail('That capped benefit no longer exists.'); }
delete found[0];
return ok('Capped benefit removed.', null);
} catch (Exception e) {
return fail('Could not remove the capped benefit: ' + e.getMessage());
}
}
private static SaveResult fail(String message) { return new SaveResult(false, message, null); }
private static SaveResult ok(String message, Id recordId) { return new SaveResult(true, message, recordId); }
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
private static Boolean groupExists(Id groupId) {
return groupId != null && [SELECT COUNT() FROM Package_Group__c WHERE Id = :groupId] > 0;
}
private static Boolean packageExists(Id packageId) {
return packageId != null && [SELECT COUNT() FROM Package__c WHERE Id = :packageId] > 0;
}
private static Boolean termExists(Id termId) {
return termId != null && [SELECT COUNT() FROM Package_Term__c WHERE Id = :termId] > 0;
}
private static Boolean optionExists(Id optionId) {
return optionId != null && [SELECT COUNT() FROM Option__c WHERE Id = :optionId] > 0;
}
private static String tierBelongsToPackage(Id tierId, Id packageId) {
List<Package_Tier__c> found = [SELECT Id, Package__c FROM Package_Tier__c WHERE Id = :tierId LIMIT 1];
if (found.isEmpty()) { return 'That odometer band no longer exists.'; }
if (found[0].Package__c != packageId) { return 'The selected odometer band belongs to a different package.'; }
return null;
}
private static String termBelongsToPackage(Id termId, Id packageId) {
List<Package_Term__c> found = [SELECT Id, Package__c FROM Package_Term__c WHERE Id = :termId LIMIT 1];
if (found.isEmpty()) { return 'That package term no longer exists.'; }
if (found[0].Package__c != packageId) { return 'The selected term belongs to a different package.'; }
return null;
}
private static PackageRow toPackageRow(Package__c p) {
PackageRow row = new PackageRow();
row.id = p.Id;
row.name = p.Name;
row.perClaimLimitLabel = perClaimLabel(p.Coverage_per_claim__c);
row.deductibleLabel = deductibleLabel(p.Deductible__c);
row.eligibilityLabel = eligibilityLabel(p);
row.packageTypeLabel = valueOrDash(p.Package_Type__c);
row.categoryLabel = valueOrDash(p.Category__c);
row.classLabel = valueOrDash(p.Class__c);
row.isActive = p.Is_Active__c == true;
row.statusLabel = row.isActive ? 'Active' : 'Inactive';
row.statusTone = row.isActive ? 'ok' : 'muted';
row.tierCount = p.Package_Term_Tiers__r == null ? 0 : p.Package_Term_Tiers__r.size();
row.termCount = p.PackageItem__r == null ? 0 : p.PackageItem__r.size();
return row;
}
private static TermRow toTermRow(Package_Term__c t) {
TermRow row = new TermRow();
row.id = t.Id;
row.name = t.Name;
row.price = t.Price__c;
row.priceLabel = moneyOrDash(t.Price__c);
row.tierId = t.Package_Tier__c == null ? null : String.valueOf(t.Package_Tier__c);
row.durationType = t.Duration_Type__c;
row.odometerKm = t.Odometer_KM__c;
row.restrictionType = t.Restriction_Type__c;
row.classValue = t.Class__c;
row.byYear = t.ByYear__c;
row.perClaimLimit = t.Per_Claim_Limit__c;
row.allowDeferral = t.Allow_Deferral__c;
return row;
}
private static String eligibilityLabel(Package__c p) {
List<String> parts = new List<String>();
if (String.isNotBlank(p.Model_Year_Restriction__c)) { parts.add(p.Model_Year_Restriction__c); }
if (p.Mileage_Restriction__c != null) { parts.add(mileageLabel(p.Mileage_Restriction__c, p.Mileage_Unit__c)); }
return parts.isEmpty() ? DASH : String.join(parts, ' \u00b7 ');
}
private static String bandLabel(Package_Tier__c tier) {
if (tier.Mileage_Restriction_Start__c == null && tier.Mileage_Restriction_End__c == null) {
return valueOrDash(tier.Name);
}
String unit = String.isBlank(tier.Mileage_Unit__c) ? 'km' : tier.Mileage_Unit__c.toLowerCase();
String start = tier.Mileage_Restriction_Start__c == null ? '0' : formatNumber(tier.Mileage_Restriction_Start__c);
if (tier.Mileage_Restriction_End__c == null) { return 'Over ' + start + ' ' + unit; }
return start + '\u2013' + formatNumber(tier.Mileage_Restriction_End__c) + ' ' + unit;
}
private static String mileageLabel(Decimal v, String unit) {
if (v == null) { return DASH; }
String u = String.isBlank(unit) ? 'km' : unit.toLowerCase();
return formatNumber(v) + ' ' + u;
}
private static String releaseNameOf(Package__c p) {
return (p.Package_Group__r != null && p.Package_Group__r.Catalogue_Release__r != null)
? p.Package_Group__r.Catalogue_Release__r.Name : '';
}
private static String releaseStatusOf(Package__c p) {
return (p.Package_Group__r != null && p.Package_Group__r.Catalogue_Release__r != null)
? p.Package_Group__r.Catalogue_Release__r.Status__c : '';
}
private static String valueOrDash(String s) { return String.isBlank(s) ? DASH : s; }
private static String perClaimLabel(Decimal v) { return v == null ? DASH : amountText(v) + ' Per Claim'; }
private static String deductibleLabel(Decimal v) {
if (v == null) { return DASH; }
return v == 0 ? 'No Deductible' : amountText(v) + ' Deductible';
}
private static String moneyOrDash(Decimal v) { return v == null ? DASH : amountText(v); }
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