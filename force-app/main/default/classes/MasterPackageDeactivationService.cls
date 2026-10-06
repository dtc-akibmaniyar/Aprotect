public without sharing class MasterPackageDeactivationService {
private static final Integer CASCADE_BATCH_SIZE = 200;
@TestVisible
private static Boolean simulateDealerCascadeAccessDenied = false;
@TestVisible
private static Boolean simulateFieldAccessDenied = false;
public class CascadeResult {
@AuraEnabled public Boolean success;
@AuraEnabled public String message;
@AuraEnabled public Id recordId;
@AuraEnabled public Integer dealerPackagesDeactivated;
@AuraEnabled public Integer dealerPackagesAlreadyInactive;
@AuraEnabled public Integer dealerPackagesFailed;
@AuraEnabled public List<String> errors;
public CascadeResult() {
dealerPackagesDeactivated = 0;
dealerPackagesAlreadyInactive = 0;
dealerPackagesFailed = 0;
errors = new List<String>();
}
}
@AuraEnabled
public static CascadeResult deactivatePackageCascade(Id packageId) {
try {
if (packageId == null) {
return fail('No package was identified.');
}
List<Package__c> found = [
SELECT Id, Name, Is_Active__c FROM Package__c WHERE Id = :packageId LIMIT 1
];
if (found.isEmpty()) {
return fail('That master package no longer exists.');
}
String guard = guardMasterEdit();
if (guard == null) { guard = guardDealerCascadeEdit(); }
if (guard != null) { return fail(guard); }
Package__c master = found[0];
Boolean masterWasActive = master.Is_Active__c == true;
if (masterWasActive) {
update new Package__c(Id = master.Id, Is_Active__c = false);
}
List<Dealer_Package__c> toDeactivate = [
SELECT Id FROM Dealer_Package__c
WHERE Package__c = :packageId AND Active__c = true
];
Integer totalDealerPackages = [
SELECT COUNT() FROM Dealer_Package__c WHERE Package__c = :packageId
];
CascadeResult result = new CascadeResult();
result.dealerPackagesAlreadyInactive = totalDealerPackages - toDeactivate.size();
result.recordId = master.Id;
for (Integer start = 0; start < toDeactivate.size(); start += CASCADE_BATCH_SIZE) {
List<Dealer_Package__c> batch = new List<Dealer_Package__c>();
Integer stop = Math.min(start + CASCADE_BATCH_SIZE, toDeactivate.size());
for (Integer i = start; i < stop; i++) {
batch.add(new Dealer_Package__c(Id = toDeactivate[i].Id, Active__c = false));
}
for (Database.SaveResult sr : Database.update(batch, false)) {
if (sr.isSuccess()) {
result.dealerPackagesDeactivated++;
} else {
result.dealerPackagesFailed++;
for (Database.Error err : sr.getErrors()) {
result.errors.add(err.getMessage());
}
}
}
}
result.message = buildMessage(masterWasActive, result);
result.success = result.dealerPackagesFailed == 0;
return result;
} catch (Exception e) {
return fail('Could not deactivate the package: ' + e.getMessage());
}
}
private static String buildMessage(Boolean masterWasActive, CascadeResult result) {
String message = masterWasActive
? 'Package deactivated.'
: 'Package was already inactive.';
if (result.dealerPackagesDeactivated > 0) {
message += ' ' + result.dealerPackagesDeactivated + ' associated dealer package'
+ (result.dealerPackagesDeactivated == 1 ? ' was' : 's were')
+ ' also deactivated.';
} else {
message += ' No active dealer packages were found to deactivate.';
}
if (result.dealerPackagesFailed > 0) {
message += ' ' + result.dealerPackagesFailed + ' dealer package'
+ (result.dealerPackagesFailed == 1 ? '' : 's') + ' could not be updated.';
}
return message;
}
private static CascadeResult fail(String message) {
CascadeResult result = new CascadeResult();
result.success = false;
result.message = message;
return result;
}
private static String guardMasterEdit() {
if (simulateFieldAccessDenied || !Package__c.Is_Active__c.getDescribe().isUpdateable()) {
return 'You do not have permission to change Active on Package. '
+ 'Ask your admin to grant you edit access.';
}
return null;
}
private static String guardDealerCascadeEdit() {
if (simulateFieldAccessDenied || simulateDealerCascadeAccessDenied
|| !Dealer_Package__c.Active__c.getDescribe().isUpdateable()) {
return 'You do not have permission to change Active on Dealer Package, which is needed '
+ 'to deactivate the associated dealer packages. Ask your admin to grant you edit access.';
}
return null;
}
}