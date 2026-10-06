@IsTest
private class MasterPackageDeactivationServiceTest {
private static final String PKG_RT = 'Extended_Limited_Warranty';
private static final String DP_RT = 'Extended_Limited_Warranty';
private static Package__c makeActiveMaster() {
Package__c pkg = TestDataFactory.createPackage(PKG_RT, true);
update new Package__c(Id = pkg.Id, Is_Active__c = true);
return pkg;
}
private static Account makeDealer(Integer n) {
Account a = new Account(
Name = 'Cascade Dealer ' + n + ' ' + Datetime.now().getTime(),
RecordTypeId = TestDataFactory.getRecordTypeId('Account', 'Dealer_Account'),
Phone = '4165550' + String.valueOf(300 + n),
BillingStreet = 'Cascade Street ' + n,
BillingCity = 'Toronto', BillingState = 'ON', BillingCountry = 'Canada',
BillingPostalCode = 'M5V 0B' + String.valueOf(n)
);
Database.DMLOptions opts = new Database.DMLOptions();
opts.DuplicateRuleHeader.allowSave = true;
opts.DuplicateRuleHeader.runAsCurrentUser = true;
Database.insert(a, opts);
return a;
}
private static Dealer_Package__c makeDealerPackage(Id packageId, Integer n, Boolean active) {
Dealer_Package__c dp = new Dealer_Package__c(
Name = 'Cascade Mirror ' + n + ' ' + Datetime.now().getTime(),
Dealer__c = makeDealer(n).Id,
Package__c = packageId,
RecordTypeId = TestDataFactory.getRecordTypeId('Dealer_Package__c', DP_RT),
Active__c = active
);
Database.DMLOptions opts = new Database.DMLOptions();
opts.DuplicateRuleHeader.allowSave = true;
opts.DuplicateRuleHeader.runAsCurrentUser = true;
Database.insert(dp, opts);
return dp;
}
private static Integer activeMirrorCount(Id packageId) {
return [SELECT COUNT() FROM Dealer_Package__c
WHERE Package__c = :packageId AND Active__c = true];
}
@IsTest
static void cascadeDeactivatesMasterAndEveryAssociatedDealerPackage() {
Package__c pkg = makeActiveMaster();
makeDealerPackage(pkg.Id, 1, true);
makeDealerPackage(pkg.Id, 2, true);
makeDealerPackage(pkg.Id, 3, true);
System.assertEquals(true,
[SELECT Is_Active__c FROM Package__c WHERE Id = :pkg.Id].Is_Active__c,
'the fixture master starts active');
Test.startTest();
MasterPackageDeactivationService.CascadeResult result =
MasterPackageDeactivationService.deactivatePackageCascade(pkg.Id);
Test.stopTest();
System.assertEquals(true, result.success, result.message);
System.assertEquals(3, result.dealerPackagesDeactivated, 'all three dealer copies are counted');
System.assertEquals(0, result.dealerPackagesFailed, 'no per-record failures');
System.assertEquals(0, result.errors.size(), 'no per-record errors');
System.assert(result.message.contains('3'), result.message);
System.assertEquals(false,
[SELECT Is_Active__c FROM Package__c WHERE Id = :pkg.Id].Is_Active__c,
'the master package is deactivated');
for (Dealer_Package__c dp : [
SELECT Id, Active__c FROM Dealer_Package__c WHERE Package__c = :pkg.Id
]) {
System.assertEquals(false, dp.Active__c,
'every associated dealer package is deactivated');
}
System.assertEquals(0, activeMirrorCount(pkg.Id));
}
@IsTest
static void countReflectsOnlyTheCopiesThatChanged() {
Package__c pkg = makeActiveMaster();
makeDealerPackage(pkg.Id, 1, true);
makeDealerPackage(pkg.Id, 2, false); // already inactive before the run
makeDealerPackage(pkg.Id, 3, true);
Test.startTest();
MasterPackageDeactivationService.CascadeResult result =
MasterPackageDeactivationService.deactivatePackageCascade(pkg.Id);
Test.stopTest();
System.assertEquals(true, result.success, result.message);
System.assertEquals(2, result.dealerPackagesDeactivated, 'only the active copies are counted');
System.assertEquals(1, result.dealerPackagesAlreadyInactive, 'the pre-inactive copy is reported');
System.assertEquals(0, activeMirrorCount(pkg.Id));
}
@IsTest
static void reRunningIsIdempotent() {
Package__c pkg = makeActiveMaster();
makeDealerPackage(pkg.Id, 1, true);
makeDealerPackage(pkg.Id, 2, true);
Test.startTest();
MasterPackageDeactivationService.CascadeResult first =
MasterPackageDeactivationService.deactivatePackageCascade(pkg.Id);
MasterPackageDeactivationService.CascadeResult second =
MasterPackageDeactivationService.deactivatePackageCascade(pkg.Id);
Test.stopTest();
System.assertEquals(true, first.success, first.message);
System.assertEquals(2, first.dealerPackagesDeactivated);
System.assertEquals(true, second.success, second.message);
System.assertEquals(0, second.dealerPackagesDeactivated, 'a re-run changes nothing');
System.assertEquals(2, second.dealerPackagesAlreadyInactive);
System.assert(second.message.containsIgnoreCase('already inactive'), second.message);
System.assertEquals(false,
[SELECT Is_Active__c FROM Package__c WHERE Id = :pkg.Id].Is_Active__c);
System.assertEquals(0, activeMirrorCount(pkg.Id));
}
@IsTest
static void alreadyInactiveMasterStillSwitchesOffStrandedCopies() {
Package__c pkg = makeActiveMaster();
makeDealerPackage(pkg.Id, 1, true);
update new Package__c(Id = pkg.Id, Is_Active__c = false); // master off, copy left on
Test.startTest();
MasterPackageDeactivationService.CascadeResult result =
MasterPackageDeactivationService.deactivatePackageCascade(pkg.Id);
Test.stopTest();
System.assertEquals(true, result.success, result.message);
System.assert(result.message.containsIgnoreCase('already inactive'), result.message);
System.assertEquals(1, result.dealerPackagesDeactivated, 'the stranded active copy is switched off');
System.assertEquals(0, activeMirrorCount(pkg.Id));
}
@IsTest
static void dealerFieldGuardFailsClosedWithoutDml() {
Package__c pkg = makeActiveMaster();
makeDealerPackage(pkg.Id, 1, true);
MasterPackageDeactivationService.simulateDealerCascadeAccessDenied = true;
Test.startTest();
MasterPackageDeactivationService.CascadeResult denied =
MasterPackageDeactivationService.deactivatePackageCascade(pkg.Id);
Test.stopTest();
MasterPackageDeactivationService.simulateDealerCascadeAccessDenied = false;
System.assertEquals(false, denied.success, 'a denied dealer field fails closed');
System.assert(denied.message.containsIgnoreCase('permission'), denied.message);
System.assertEquals(true,
[SELECT Is_Active__c FROM Package__c WHERE Id = :pkg.Id].Is_Active__c,
'the master is untouched when the guard fails closed');
System.assertEquals(1, activeMirrorCount(pkg.Id), 'the dealer copy is untouched');
}
@IsTest
static void masterFieldGuardFailsClosed() {
Package__c pkg = makeActiveMaster();
makeDealerPackage(pkg.Id, 1, true);
MasterPackageDeactivationService.simulateFieldAccessDenied = true;
Test.startTest();
MasterPackageDeactivationService.CascadeResult denied =
MasterPackageDeactivationService.deactivatePackageCascade(pkg.Id);
Test.stopTest();
MasterPackageDeactivationService.simulateFieldAccessDenied = false;
System.assertEquals(false, denied.success);
System.assert(denied.message.containsIgnoreCase('permission'), denied.message);
System.assertEquals(true,
[SELECT Is_Active__c FROM Package__c WHERE Id = :pkg.Id].Is_Active__c,
'the master is untouched when the guard fails closed');
System.assertEquals(1, activeMirrorCount(pkg.Id));
}
@IsTest
static void nullAndUnknownIdsAreRefused() {
String unknownId = Package__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000AAA';
Test.startTest();
MasterPackageDeactivationService.CascadeResult nullResult =
MasterPackageDeactivationService.deactivatePackageCascade(null);
MasterPackageDeactivationService.CascadeResult unknownResult =
MasterPackageDeactivationService.deactivatePackageCascade(unknownId);
Test.stopTest();
System.assertEquals(false, nullResult.success);
System.assert(nullResult.message.containsIgnoreCase('No package'), nullResult.message);
System.assertEquals(false, unknownResult.success);
System.assert(unknownResult.message.containsIgnoreCase('no longer exists'), unknownResult.message);
}
@IsTest
static void packageWithNoDealerCopiesStillDeactivatesTheMaster() {
Package__c pkg = makeActiveMaster();
Test.startTest();
MasterPackageDeactivationService.CascadeResult result =
MasterPackageDeactivationService.deactivatePackageCascade(pkg.Id);
Test.stopTest();
System.assertEquals(true, result.success, result.message);
System.assertEquals(0, result.dealerPackagesDeactivated);
System.assertEquals(false,
[SELECT Is_Active__c FROM Package__c WHERE Id = :pkg.Id].Is_Active__c);
}
}