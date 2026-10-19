public without sharing class InvoiceDetailPDFController {

public Invoice__c      invoice      { get; set; }
public Application__c  application  { get; set; }
public String          dealerName   { get; set; }
public String          billTo       { get; set; }
public List<PackageRow>   packages  { get; set; }
public Decimal         grandTotal   { get; set; }

public String  invoiceDate       { get; set; }
public String  dueDate           { get; set; }
public String  statusStyle       { get; set; }
public String  applicationId     { get; set; }
public String  customerFullName  { get; set; }
public String  vehicleInfo       { get; set; }
public String  vin               { get; set; }
public String  odometerUnit      { get; set; }
public Boolean hasDealerName     { get; set; }
public Boolean hasBillTo         { get; set; }
public Decimal subTotal          { get; set; }
public Decimal taxTotal          { get; set; }
public Decimal blendedTaxRate    { get; set; }
public Decimal balanceAmount     { get; set; }

private static Decimal getDisplayPrice(Application_Package__c pkg) {
return pkg.Contract_Cost_Price__c != null ? pkg.Contract_Cost_Price__c : 0;
}

private static String resolvePackageName(Application_Package__c pkg) {
if (pkg.Package__r != null && String.isNotBlank(pkg.Package__r.Name)) {
return pkg.Package__r.Name;
}
if (pkg.Dealer_Package__r != null && pkg.Dealer_Package__r.Package__r != null
&& String.isNotBlank(pkg.Dealer_Package__r.Package__r.Name)) {
return pkg.Dealer_Package__r.Package__r.Name;
}
if (pkg.Dealer_Package__r != null && String.isNotBlank(pkg.Dealer_Package__r.Name)) {
return pkg.Dealer_Package__r.Name;
}
return '';
}

private static String resolveTermName(Application_Package__c pkg) {
if (pkg.Package_Term__r != null && String.isNotBlank(pkg.Package_Term__r.Name)) {
return pkg.Package_Term__r.Name;
}
if (pkg.Dealer_Package_Term__r != null && pkg.Dealer_Package_Term__r.Package_Term__r != null
&& String.isNotBlank(pkg.Dealer_Package_Term__r.Package_Term__r.Name)) {
return pkg.Dealer_Package_Term__r.Package_Term__r.Name;
}
if (pkg.Dealer_Package_Term__r != null && String.isNotBlank(pkg.Dealer_Package_Term__r.Name)) {
return pkg.Dealer_Package_Term__r.Name;
}
return '';
}

private static String buildStatusStyle(String status) {
if (status == 'Paid')         return 'color:#5cb85c; font-weight:700;';
if (status == 'Partial Paid') return 'color:#f0ad4e; font-weight:700;';
if (status == 'Due')          return 'color:#d9534f; font-weight:700;';
if (status == 'Planned')      return 'color:#5bc0de; font-weight:700;';
if (status == 'Cancelled')    return 'color:#999; font-weight:700; text-decoration:line-through;';
return 'color:#999; font-weight:700;';
}

private static String buildBillToFromAccount(Account dlr) {
List<String> addrParts = new List<String>();
if (String.isNotBlank(dlr.BillingStreet))     addrParts.add(dlr.BillingStreet);
String cityLine = '';
if (String.isNotBlank(dlr.BillingCity))       cityLine += dlr.BillingCity;
if (String.isNotBlank(dlr.BillingState))      cityLine += (String.isNotBlank(cityLine) ? ' ' : '') + dlr.BillingState;
if (String.isNotBlank(dlr.BillingPostalCode)) cityLine += (String.isNotBlank(cityLine) ? ' ' : '') + dlr.BillingPostalCode;
if (String.isNotBlank(cityLine))               addrParts.add(cityLine);
if (String.isNotBlank(dlr.BillingCountry))    addrParts.add(dlr.BillingCountry);
if (String.isNotBlank(dlr.Phone))              addrParts.add('Tel: ' + dlr.Phone);
if (String.isNotBlank(dlr.Email__c))           addrParts.add('E-mail: ' + dlr.Email__c);
return addrParts.isEmpty() ? null : String.join(addrParts, '<br/>');
}

private static PackageRow buildStandaloneRow(Invoice_Line_Item__c li, Decimal amount) {
PackageRow row          = new PackageRow();
row.pkg                 = new Application_Package__c();
row.packageName         = String.isNotBlank(li.Description__c) ? li.Description__c : 'Option';
row.categoryLabel       = 'Options';
row.lineItems           = new List<LineItemWrapper>();
row.options             = new List<OptionWrapper>();
row.packageTotal        = amount;
row.baseCostPrice       = 0;
row.addOnsTotal         = 0;
row.lineTotal           = amount;
row.packageCostWithFees = amount;
row.basePriceWithoutTax = amount;
row.taxPercentage       = 0;
row.taxAmount           = 0;
row.hasTax              = false;
row.premiumModelFee     = 0;
row.hasPremiumModelFee  = false;
row.extraFeeTotal       = 0;
row.termDisplay         = '';

row.isOptionRow         = true;
return row;
}

private static String stripOptionalSuffix(String value) {
if (value == null) {
return '';
}
String trimmed = value.trim();
if (trimmed.endsWith(InvoiceOptionLineService.OPTIONAL_SUFFIX)) {
return trimmed.substring(0,
trimmed.length() - InvoiceOptionLineService.OPTIONAL_SUFFIX.length());
}
return trimmed;
}

public InvoiceDetailPDFController() {
packages   = new List<PackageRow>();
grandTotal = 0;
subTotal   = 0;
taxTotal   = 0;
hasDealerName = false;
hasBillTo     = false;

String invoiceId = ApexPages.currentPage().getParameters().get('id');
if (String.isBlank(invoiceId)) return;

List<Invoice__c> invoices = [
SELECT Id, Name, Status__c, CreatedDate,
Invoice_Due_Date__c, Total_Balance_Amount__c,
Application__c,
Application__r.Name,
Application__r.Dealer_Name__c,
Application__r.Customer_First_Name__c,
Application__r.Customer_Last_Name__c,
Application__r.Customer_Address__c,
Application__r.Vehicle_VIN__c,
Application__r.Vehicle_Year__c,
Application__r.Vehicle_Make__c,
Application__r.Vehicle_Model__c,
Application__r.Odometer__c,
Application__r.Odometer_Unit__c,
Remittance_Form__r.Bill_To__c,
Remittance_Form__r.Dealer_Name__c,
Remittance_Form__r.Dealer_Name__r.Name,
Application__r.Dealer_Name__r.Name,
Application__r.Dealer_Name__r.BillingStreet,
Application__r.Dealer_Name__r.BillingCity,
Application__r.Dealer_Name__r.BillingState,
Application__r.Dealer_Name__r.BillingPostalCode,
Application__r.Dealer_Name__r.BillingCountry,
Application__r.Dealer_Name__r.Phone,
Application__r.Dealer_Name__r.Email__c
FROM Invoice__c
WHERE Id = :invoiceId
LIMIT 1
];
if (invoices.isEmpty()) return;

invoice     = invoices[0];
application = invoice.Application__r;

invoiceDate = invoice.CreatedDate != null
? invoice.CreatedDate.format('MMM dd, yyyy')
: null;
dueDate     = invoice.Invoice_Due_Date__c != null
? String.valueOf(invoice.Invoice_Due_Date__c)
: null;
statusStyle = buildStatusStyle(invoice.Status__c);

if (invoice.Application__c != null && invoice.Application__r != null) {
applicationId = invoice.Application__r.Name;
String fn = invoice.Application__r.Customer_First_Name__c != null
? invoice.Application__r.Customer_First_Name__c : '';
String ln = invoice.Application__r.Customer_Last_Name__c != null
? invoice.Application__r.Customer_Last_Name__c : '';
customerFullName = (fn + ' ' + ln).trim();
vin = invoice.Application__r.Vehicle_VIN__c;

List<String> vParts = new List<String>();
if (invoice.Application__r.Vehicle_Year__c  != null)            vParts.add(String.valueOf(invoice.Application__r.Vehicle_Year__c));
if (String.isNotBlank(invoice.Application__r.Vehicle_Make__c))  vParts.add(invoice.Application__r.Vehicle_Make__c);
if (String.isNotBlank(invoice.Application__r.Vehicle_Model__c)) vParts.add(invoice.Application__r.Vehicle_Model__c);
vehicleInfo = String.join(vParts, '/');

odometerUnit = invoice.Application__r.Odometer_Unit__c != null
? invoice.Application__r.Odometer_Unit__c : 'KM';
}

if (invoice.Remittance_Form__c != null && invoice.Remittance_Form__r != null
&& invoice.Remittance_Form__r.Dealer_Name__c != null
&& invoice.Remittance_Form__r.Dealer_Name__r != null) {
dealerName = invoice.Remittance_Form__r.Dealer_Name__r.Name;
}
if (dealerName == null && invoice.Application__c != null && invoice.Application__r != null
&& invoice.Application__r.Dealer_Name__c != null
&& invoice.Application__r.Dealer_Name__r != null) {
dealerName = invoice.Application__r.Dealer_Name__r.Name;
}
hasDealerName = String.isNotBlank(dealerName);

if (invoice.Remittance_Form__c != null && invoice.Remittance_Form__r != null
&& invoice.Remittance_Form__r.Bill_To__c != null) {
billTo = invoice.Remittance_Form__r.Bill_To__c;
}
if (billTo == null && invoice.Application__c != null && invoice.Application__r != null
&& invoice.Application__r.Dealer_Name__c != null
&& invoice.Application__r.Dealer_Name__r != null) {
billTo = buildBillToFromAccount(invoice.Application__r.Dealer_Name__r);
}
hasBillTo = String.isNotBlank(billTo);

List<Invoice_Line_Item__c> lineItems = [
SELECT Id, Application_Package__c, Contract_Cost_Price__c,
Tax_Amount__c, Status__c, Amount__c, Description__c
FROM Invoice_Line_Item__c
WHERE Invoice__c = :invoiceId
ORDER BY Application_Package_Name__c ASC
LIMIT 1000
];

Map<Id, List<Invoice_Line_Item__c>> pkgMap = new Map<Id, List<Invoice_Line_Item__c>>();
Set<Id> packageIds = new Set<Id>();
for (Invoice_Line_Item__c li : lineItems) {
if (li.Application_Package__c != null) {
packageIds.add(li.Application_Package__c);
if (!pkgMap.containsKey(li.Application_Package__c))
pkgMap.put(li.Application_Package__c, new List<Invoice_Line_Item__c>());
pkgMap.get(li.Application_Package__c).add(li);
}
}

Set<String> billedOptionKeys = new Set<String>();
for (Invoice_Line_Item__c li : lineItems) {
if (li.Application_Package__c == null && li.Amount__c != null && li.Amount__c != 0) {
billedOptionKeys.add(
InvoiceOptionLineService.normalize(stripOptionalSuffix(li.Description__c)));
}
}

Map<Id, List<OptionWrapper>> pkgToOptions = new Map<Id, List<OptionWrapper>>();
try {
if (!packageIds.isEmpty()) {
Map<Id, Id> dealerPkgByPkg = new Map<Id, Id>();
for (Application_Package__c p : [
SELECT Id, Dealer_Package__c, Dealer_Package_Term__r.Dealer_Package__c
FROM Application_Package__c WHERE Id IN :packageIds
]) {
Id dpId = (p.Dealer_Package_Term__r != null && p.Dealer_Package_Term__r.Dealer_Package__c != null)
? p.Dealer_Package_Term__r.Dealer_Package__c : p.Dealer_Package__c;
if (dpId != null) {
dealerPkgByPkg.put(p.Id, dpId);
}
}
Map<Id, Dealer_Package_Option__c> mirrorByMaster = new Map<Id, Dealer_Package_Option__c>();
Set<Id> dealerPkgIds = new Set<Id>(dealerPkgByPkg.values());
if (!dealerPkgIds.isEmpty()) {
for (Dealer_Package_Option__c dpo : [
SELECT Id, Package_Option__c, Net_Cost__c
FROM Dealer_Package_Option__c
WHERE Dealer_Package__c IN :dealerPkgIds
AND Package_Option__c != null
AND Net_Cost__c != null AND Net_Cost__c != 0
]) {
if (!mirrorByMaster.containsKey(dpo.Package_Option__c)) {
mirrorByMaster.put(dpo.Package_Option__c, dpo);
}
}
}
for (Application_Package_Line_Item__c line : (List<Application_Package_Line_Item__c>) Database.queryWithBinds(
'SELECT Application_Package__c, Description__c, Amount__c, Package_Option__c' +
' FROM Application_Package_Line_Item__c' +
' WHERE Application_Package__c IN :packageIds' +
' AND Line_Type__c = \'Option\'' +
' ORDER BY Package_Option__c, Id',
new Map<String, Object>{ 'packageIds' => packageIds },
System.AccessLevel.SYSTEM_MODE)) {
if (line.Application_Package__c == null) {
continue;
}
if (billedOptionKeys.contains(
InvoiceOptionLineService.normalize(line.Description__c))) {
continue;
}
List<OptionWrapper> rows = pkgToOptions.get(line.Application_Package__c);
if (rows == null) {
rows = new List<OptionWrapper>();
pkgToOptions.put(line.Application_Package__c, rows);
}
OptionWrapper ow = new OptionWrapper();
Dealer_Package_Option__c mirror = line.Package_Option__c != null
? mirrorByMaster.get(line.Package_Option__c) : null;
ow.optionName    = String.isNotBlank(line.Description__c)
? line.Description__c : 'Additional Option';
ow.costPrice     = mirror != null && mirror.Net_Cost__c != null
? mirror.Net_Cost__c : (line.Amount__c != null ? line.Amount__c : 0);
ow.selectionType = 'Optional';
rows.add(ow);
}
}
} catch (Exception e) {

System.debug(LoggingLevel.WARN, 'PDF: Failed to query option lines: ' + e.getMessage());
}

Map<String, Id> optionNameToPkg   = new Map<String, Id>();
Set<String>     ambiguousOption   = new Set<String>();
Map<Id, List<OptionWrapper>> billedOptionsByPkg = new Map<Id, List<OptionWrapper>>();
Set<Id>         nestedOptionLineIds = new Set<Id>();
try {
if (!packageIds.isEmpty()) {
for (Application_Package_Line_Item__c line : (List<Application_Package_Line_Item__c>) Database.queryWithBinds(
'SELECT Id, Name, Application_Package__c' +
' FROM Application_Package_Line_Item__c' +
' WHERE Application_Package__c IN :packageIds',
new Map<String, Object>{ 'packageIds' => packageIds },
System.AccessLevel.SYSTEM_MODE)) {
if (line.Application_Package__c == null || String.isBlank(line.Name)) {
continue;
}
String key = InvoiceOptionLineService.normalize(line.Name);
if (String.isBlank(key)) {
continue;
}
if (!optionNameToPkg.containsKey(key)) {
optionNameToPkg.put(key, line.Application_Package__c);
} else if (optionNameToPkg.get(key) != line.Application_Package__c) {
ambiguousOption.add(key);
}
}
}
for (Invoice_Line_Item__c li : lineItems) {
if (li.Application_Package__c != null || li.Amount__c == null || li.Amount__c == 0) {
continue;
}
if (!(li.Description__c != null
&& li.Description__c.trim().endsWith(InvoiceOptionLineService.OPTIONAL_SUFFIX))) {
continue;
}
String stem = InvoiceOptionLineService.normalize(stripOptionalSuffix(li.Description__c));
if (String.isBlank(stem) || ambiguousOption.contains(stem)) {
continue;
}
Id ownerPkg = optionNameToPkg.get(stem);
if (ownerPkg == null) {
continue;
}
OptionWrapper ow  = new OptionWrapper();
ow.optionName     = stripOptionalSuffix(li.Description__c);
ow.costPrice      = li.Amount__c;
ow.selectionType  = 'Optional';
ow.isBilledOption = true;
List<OptionWrapper> rows = billedOptionsByPkg.get(ownerPkg);
if (rows == null) {
rows = new List<OptionWrapper>();
billedOptionsByPkg.put(ownerPkg, rows);
}
rows.add(ow);
nestedOptionLineIds.add(li.Id);
}
} catch (Exception e) {

System.debug(LoggingLevel.WARN, 'PDF: option->package mapping unavailable: ' + e.getMessage());
billedOptionsByPkg.clear();
nestedOptionLineIds.clear();
}

Map<Id, FeeSet> feeByPkg = loadFeeLinesByPackage(packageIds);
Map<Id, Decimal> pkgDisplayPrice = new Map<Id, Decimal>();
if (!packageIds.isEmpty()) {
List<Application_Package__c> appPkgs = [
SELECT Id, Package__r.Name, Package_Term__r.Name,
Dealer_Package__c, Dealer_Package__r.Name,
Dealer_Package__r.Package__r.Name,
Dealer_Package_Term__c, Dealer_Package_Term__r.Name,
Dealer_Package_Term__r.Package_Term__r.Name,
Odometer_Start__c, Odometer_End__c,
Contract_Start_Date__c, Contract_End_Date__c,
RecordType.Name,
Contract_Cost_Price__c,
Contract_Cost_Price_Without_Tax__c,
Contract_Premium_Price__c,
Contract_Premium_Price_Without_Tax__c,
Tax_Amount__c,
Dealer_Price_Override__c,
Tax_Percentage__c,
Dealer_Package_Price__c,
Add_Ons_Price__c,
Premium_Model_Fee__c
FROM Application_Package__c
WHERE Id IN :packageIds
LIMIT 1000
];

for (Application_Package__c pkg : appPkgs) {
FeeSet fs = feeByPkg.get(pkg.Id);
Decimal extraWithTax = 0;
if (fs != null && fs.extraFee > 0) {
Decimal rate = pkg.Tax_Percentage__c != null ? pkg.Tax_Percentage__c : 0;
extraWithTax = (fs.extraFee + (fs.extraFee * rate / 100))
.setScale(2, System.RoundingMode.HALF_UP);
}
pkgDisplayPrice.put(pkg.Id, getDisplayPrice(pkg) + extraWithTax);
}

for (Application_Package__c pkg : appPkgs) {
PackageRow row    = new PackageRow();
row.pkg           = pkg;
row.packageName   = resolvePackageName(pkg);
row.lineItems     = new List<LineItemWrapper>();
row.packageTotal  = 0;
row.baseCostPrice = pkg.Dealer_Package_Price__c != null ? pkg.Dealer_Package_Price__c : 0;
row.addOnsTotal   = pkg.Add_Ons_Price__c != null ? pkg.Add_Ons_Price__c : 0;
row.hasBreakdown  = row.addOnsTotal > 0;

List<OptionWrapper> pkgOptionRows = pkgToOptions.containsKey(pkg.Id)
? new List<OptionWrapper>(pkgToOptions.get(pkg.Id))
: new List<OptionWrapper>();
if (billedOptionsByPkg.containsKey(pkg.Id)) {
pkgOptionRows.addAll(billedOptionsByPkg.get(pkg.Id));
}
row.options       = pkgOptionRows;

row.premiumModelFee    = pkg.Premium_Model_Fee__c != null ? pkg.Premium_Model_Fee__c : 0;
row.hasPremiumModelFee = row.premiumModelFee > 0;

FeeSet fs = feeByPkg.get(pkg.Id);
row.dieselFee         = fs != null ? fs.dieselFee : 0;
row.commercialFee     = fs != null ? fs.commercialFee : 0;
row.powersportsFee    = fs != null ? fs.powersportsFee : 0;
row.hasDieselFee      = row.dieselFee > 0;
row.hasCommercialFee  = row.commercialFee > 0;
row.hasPowersportsFee = row.powersportsFee > 0;
row.extraFeeTotal     = fs != null ? fs.extraFee : 0;

Decimal billedOptionTotal = 0;
if (billedOptionsByPkg.containsKey(pkg.Id)) {
for (OptionWrapper billedOpt : billedOptionsByPkg.get(pkg.Id)) {
billedOptionTotal += billedOpt.costPrice != null ? billedOpt.costPrice : 0;
}
}
row.lineTotal          = row.baseCostPrice + row.addOnsTotal + row.premiumModelFee + row.extraFeeTotal + billedOptionTotal;

row.packageCostWithFees = row.baseCostPrice + row.premiumModelFee + row.extraFeeTotal;
row.termDisplay        = resolveTermName(pkg).replaceAll('\\bnull\\b', '0');
row.isOptionRow        = false;

row.basePriceWithoutTax = (pkg.Contract_Cost_Price_Without_Tax__c != null ? pkg.Contract_Cost_Price_Without_Tax__c : 0)
+ row.extraFeeTotal;
row.taxPercentage = pkg.Tax_Percentage__c != null ? pkg.Tax_Percentage__c : 0;
Decimal costWithTax = pkg.Contract_Cost_Price__c != null ? pkg.Contract_Cost_Price__c : 0;
row.taxAmount = costWithTax - (row.basePriceWithoutTax - row.extraFeeTotal);
row.hasTax = row.taxPercentage > 0 || row.taxAmount > 0 || row.extraFeeTotal > 0;

if (pkgMap.containsKey(pkg.Id)) {
Decimal displayPrice = pkgDisplayPrice.get(pkg.Id);
for (Invoice_Line_Item__c li : pkgMap.get(pkg.Id)) {
LineItemWrapper liw = new LineItemWrapper();
liw.lineItem = li;
liw.displayPrice = displayPrice;
row.lineItems.add(liw);
row.packageTotal += displayPrice;
}
}
grandTotal += row.packageTotal;
packages.add(row);

subTotal += row.basePriceWithoutTax;
if (row.hasTax && row.taxPercentage != null && row.basePriceWithoutTax != null) {
taxTotal += row.basePriceWithoutTax * (row.taxPercentage / 100);
}
}
}

for (Invoice_Line_Item__c li : lineItems) {
if (li.Application_Package__c != null) {
continue;
}
Decimal standaloneAmt = li.Amount__c != null ? li.Amount__c : 0;
grandTotal += standaloneAmt;
subTotal   += standaloneAmt;

if (standaloneAmt != 0 && !nestedOptionLineIds.contains(li.Id)) {
packages.add(buildStandaloneRow(li, standaloneAmt));
}
}

blendedTaxRate = (subTotal != null && taxTotal != null && subTotal > 0)
? (taxTotal / subTotal * 100).setScale(2)
: null;
balanceAmount = invoice.Total_Balance_Amount__c != null
? invoice.Total_Balance_Amount__c
: grandTotal;
}

public class PackageRow {
public Application_Package__c      pkg          { get; set; }
public String                      packageName  { get; set; }
public String                      categoryLabel { get; set; }
public List<LineItemWrapper>        lineItems    { get; set; }
public Decimal                     packageTotal { get; set; }
public Decimal                     baseCostPrice { get; set; }
public Decimal                     addOnsTotal   { get; set; }
public Boolean                     hasBreakdown  { get; set; }
public List<OptionWrapper>         options       { get; set; }

public Decimal                     basePriceWithoutTax { get; set; }
public Decimal                     taxPercentage       { get; set; }
public Decimal                     taxAmount           { get; set; }
public Boolean                     hasTax              { get; set; }

public Decimal                     premiumModelFee     { get; set; }
public Boolean                     hasPremiumModelFee  { get; set; }
public Decimal                     lineTotal           { get; set; }

public Decimal                     packageCostWithFees { get; set; }
public String                      termDisplay         { get; set; }

public Boolean                     isOptionRow         { get; set; }

public Decimal                     dieselFee           { get; set; }
public Decimal                     commercialFee       { get; set; }
public Decimal                     powersportsFee      { get; set; }
public Boolean                     hasDieselFee        { get; set; }
public Boolean                     hasCommercialFee    { get; set; }
public Boolean                     hasPowersportsFee   { get; set; }
public Decimal                     extraFeeTotal       { get; set; }
}

public class FeeSet {
public Boolean hasLines       = false;
public Decimal premiumFee     = 0;
public Decimal dieselFee      = 0;
public Decimal commercialFee  = 0;
public Decimal powersportsFee = 0;
public Decimal extraFee       = 0;
}

@TestVisible
private static Map<Id, FeeSet> loadFeeLinesByPackage(Set<Id> pkgIds) {
Map<Id, FeeSet> byPkg = new Map<Id, FeeSet>();
if (pkgIds == null || pkgIds.isEmpty()) {
return byPkg;
}
try {
for (Application_Package_Line_Item__c line : (List<Application_Package_Line_Item__c>) Database.queryWithBinds(
'SELECT Application_Package__c, Line_Type__c, Amount__c' +
' FROM Application_Package_Line_Item__c' +
' WHERE Application_Package__c IN :pkgIds' +
' ORDER BY Application_Package__c, Sort_Order__c, Id',
new Map<String, Object>{ 'pkgIds' => pkgIds },
System.AccessLevel.SYSTEM_MODE)) {
if (line.Application_Package__c == null) {
continue;
}
FeeSet fs = byPkg.get(line.Application_Package__c);
if (fs == null) {
fs = new FeeSet();
byPkg.put(line.Application_Package__c, fs);
}
fs.hasLines = true;
Decimal amt = line.Amount__c != null ? line.Amount__c : 0;
if ('Premium_Fee'.equals(line.Line_Type__c)) {
fs.premiumFee += amt;
} else if ('Diesel_Fee'.equals(line.Line_Type__c)) {
fs.dieselFee += amt;
} else if ('Commercial_Surcharge'.equals(line.Line_Type__c)) {
fs.commercialFee += amt;
} else if ('Powersports_Adjustment'.equals(line.Line_Type__c)) {
fs.powersportsFee += amt;
}
}
for (FeeSet fs : byPkg.values()) {
fs.extraFee = fs.dieselFee + fs.commercialFee + fs.powersportsFee;
}
} catch (Exception e) {
System.debug(LoggingLevel.WARN,
'InvoiceDetailPDFController: fee line read unavailable: ' + e.getMessage());
byPkg.clear();
}
return byPkg;
}

public class LineItemWrapper {
public Invoice_Line_Item__c lineItem     { get; set; }
public Decimal              displayPrice { get; set; }
}

public class OptionWrapper {
public String  optionName    { get; set; }
public Decimal costPrice     { get; set; }
public String  selectionType { get; set; }

public Boolean isBilledOption { get; set; }
}
}