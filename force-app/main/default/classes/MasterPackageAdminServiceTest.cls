/**
 * MasterPackageAdminServiceTest
 *
 * Unit tests for the master-side package service.
 *   • Phase 1 (read): hierarchy read, price-from-term, list rollups, typed
 *     empty results, tier-less packages, group scoping.
 *   • Phase 2 (write): blank-package create, package edit, activate/deactivate,
 *     tier/term/option/add-on/benefit-cap create + edit, every validation guard,
 *     the guarded deletes, the FLS fail-closed path, and the PackageTermTrigger
 *     side effect (a blank new term takes its package's Max Vehicle Age Limit).
 *
 * Fixtures build a small master book directly:
 *   Catalogue_Release__c → Package_Group__c → Package__c
 *       ├ Package_Tier__c (odometer band)
 *       ├ Package_Term__c (the price anchor)
 *       │     ├ Package_Add_On__c
 *       │     └ Package_Benefit_Cap__c
 *       └ Package_Option__c → Option__c
 */
@IsTest
private class MasterPackageAdminServiceTest {

    // ── Fixtures ─────────────────────────────────────────────────────────────

    private static Catalogue_Release__c makeRelease() {
        Catalogue_Release__c rel = new Catalogue_Release__c(
            Name = 'V99', Release_Number__c = 'V99', Status__c = 'Draft',
            Effective_Date__c = Date.newInstance(2027, 1, 1));
        insert rel;
        return rel;
    }

    private static Package_Group__c makeGroup(Id releaseId, String name) {
        Package_Group__c g = new Package_Group__c(
            Name = name, Active__c = true, Catalogue_Release__c = releaseId);
        insert g;
        return g;
    }

    private static Package__c makePackage(Id groupId, String name, Decimal perClaim, Decimal deductible) {
        Package__c p = new Package__c(
            Name = name,
            Package_Group__c = groupId,
            Coverage_per_claim__c = perClaim,
            Deductible__c = deductible,
            Is_Active__c = true,
            Commercial_Business_Use__c = false);
        insert p;
        return p;
    }

    private static Option__c makeOption(String name) {
        Option__c o = new Option__c(Name = name);
        insert o;
        return o;
    }

    // ── PHASE 1 — hierarchical read + price-from-term ────────────────────────

    @IsTest
    static void detailReadsHierarchyAndPricesComeFromTheTerm() {
        Catalogue_Release__c rel = makeRelease();
        Package_Group__c g = makeGroup(rel.Id, 'Powertrain Warranties');
        Package__c pkg = makePackage(g.Id, 'Powertrain Bronze', 750, 100);

        Package_Tier__c band = new Package_Tier__c(
            Name = 'Diamond Plus (0-60,000 km)', Package__c = pkg.Id,
            Mileage_Restriction_Start__c = 0, Mileage_Restriction_End__c = 60000,
            Mileage_Unit__c = 'KM');
        insert band;

        Package_Term__c tieredTerm = new Package_Term__c(
            Name = '12 Months/Unlimited km', Package__c = pkg.Id,
            Package_Tier__c = band.Id, Price__c = 819);
        Package_Term__c tierlessTerm = new Package_Term__c(
            Name = '3 Months/3000 km', Package__c = pkg.Id, Price__c = 59);
        insert new List<Package_Term__c>{ tieredTerm, tierlessTerm };

        insert new Package_Add_On__c(
            Package_Term__c = tieredTerm.Id, Add_On_Type__c = 'Car Rental', Price__c = 149);
        insert new Package_Benefit_Cap__c(
            Package_Term__c = tieredTerm.Id, Benefit_Type__c = 'Car Rental', Cap_Amount__c = 500);

        Option__c opt = makeOption('Zero Deductible');
        insert new Package_Option__c(
            Package__c = pkg.Id, Option__c = opt.Id,
            Selection_Type__c = 'Included', Price__c = 30);

        Test.startTest();
        MasterPackageAdminService.PackageDetail dto =
            MasterPackageAdminService.getPackageDetail(pkg.Id);
        Test.stopTest();

        Assert.areEqual('Powertrain Bronze', dto.name);
        Assert.areEqual('Powertrain Warranties', dto.groupName);
        Assert.areEqual(String.valueOf(g.Id), dto.groupId);
        Assert.areEqual('V99', dto.releaseName);
        Assert.areEqual('$750 Per Claim', dto.perClaimLimitLabel);
        Assert.areEqual('$100 Deductible', dto.deductibleLabel);
        Assert.areEqual(750, dto.coveragePerClaim);
        Assert.isTrue(dto.hasTiers, 'the package has a tier band');
        Assert.areEqual(1, dto.tierCount);
        Assert.areEqual(2, dto.termCount);
        Assert.areEqual(2, dto.tierBlocks.size(), 'one band block plus the tier-less block');

        MasterPackageAdminService.TierBlock bandBlock = dto.tierBlocks[0];
        Assert.isTrue(bandBlock.hasTier, 'first block is the odometer band');
        Assert.areEqual('0' + '\u2013' + '60,000 km', bandBlock.bandLabel,
            'tier band label is the odometer range');
        Assert.areEqual(1, bandBlock.terms.size());
        Assert.areEqual('12 Months/Unlimited km', bandBlock.terms[0].name);
        Assert.areEqual('$819', bandBlock.terms[0].priceLabel,
            'the price column must come from Package_Term__c.Price__c');

        MasterPackageAdminService.TierBlock flatBlock = dto.tierBlocks[1];
        Assert.isFalse(flatBlock.hasTier, 'second block collects the tier-less terms');
        Assert.areEqual(1, flatBlock.terms.size());
        Assert.areEqual('$59', flatBlock.terms[0].priceLabel);

        Assert.areEqual(1, dto.addOnCount);
        Assert.areEqual('Car Rental', dto.addOns[0].label);
        Assert.areEqual('$149', dto.addOns[0].priceLabel);
        Assert.areEqual(1, dto.benefitCapCount);
        Assert.areEqual('$500', dto.benefitCaps[0].capLabel);
        Assert.areEqual(1, dto.optionCount);
        Assert.areEqual('Zero Deductible', dto.options[0].label,
            'the option label is joined from Option__c');
    }

    @IsTest
    static void packageListRollsUpCountsAndLabels() {
        Catalogue_Release__c rel = makeRelease();
        Package_Group__c g = makeGroup(rel.Id, 'Essential');
        Package__c first = makePackage(g.Id, 'Essential $1,000', 1000, 100);
        makePackage(g.Id, 'Essential $1,500', 1500, 0);

        Package_Tier__c band = new Package_Tier__c(
            Name = 'Band A', Package__c = first.Id,
            Mileage_Restriction_Start__c = 0, Mileage_Restriction_End__c = 60000,
            Mileage_Unit__c = 'KM');
        insert band;
        insert new Package_Term__c(
            Name = '12 Months/20,000 km', Package__c = first.Id,
            Package_Tier__c = band.Id, Price__c = 219);

        Test.startTest();
        List<MasterPackageAdminService.PackageRow> rows =
            MasterPackageAdminService.getPackages(g.Id);
        Test.stopTest();

        Assert.areEqual(2, rows.size(), 'both packages of the group are returned');
        Assert.areEqual('Essential $1,000', rows[0].name, 'rows are name-ordered');
        Assert.areEqual('$1,000 Per Claim', rows[0].perClaimLimitLabel);
        Assert.areEqual('$100 Deductible', rows[0].deductibleLabel);
        Assert.areEqual(1, rows[0].tierCount, 'tier count sub-select');
        Assert.areEqual(1, rows[0].termCount, 'term count sub-select');
        Assert.isTrue(rows[0].isActive);
        Assert.areEqual('Active', rows[0].statusLabel);
        Assert.areEqual('No Deductible', rows[1].deductibleLabel,
            'a zero deductible reads as "No Deductible"');
    }

    @IsTest
    static void nullAndUnknownIdsReturnTypedEmptyResults() {
        String unknownId = Package__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000AAA';

        Test.startTest();
        List<MasterPackageAdminService.PackageRow> nullGroupRows =
            MasterPackageAdminService.getPackages(null);
        List<MasterPackageAdminService.PackageRow> unknownGroupRows =
            MasterPackageAdminService.getPackages(unknownId);
        MasterPackageAdminService.PackageDetail nullDetail =
            MasterPackageAdminService.getPackageDetail(null);
        MasterPackageAdminService.PackageDetail unknownDetail =
            MasterPackageAdminService.getPackageDetail(unknownId);
        Test.stopTest();

        Assert.isNotNull(nullGroupRows, 'null group returns an empty typed list');
        Assert.areEqual(0, nullGroupRows.size());
        Assert.isNotNull(unknownGroupRows, 'unknown group returns an empty typed list');
        Assert.areEqual(0, unknownGroupRows.size());

        Assert.isNotNull(nullDetail, 'null id returns an empty typed DTO');
        Assert.isNull(nullDetail.id);
        Assert.areEqual(0, nullDetail.tierBlocks.size());
        Assert.isNotNull(unknownDetail, 'unknown id returns an empty typed DTO, not an exception');
        Assert.isNull(unknownDetail.id);
        Assert.areEqual(0, unknownDetail.addOns.size());
        Assert.areEqual(0, unknownDetail.options.size());
    }

    @IsTest
    static void tierlessPackageFallsIntoASingleUnbandedBlock() {
        Catalogue_Release__c rel = makeRelease();
        Package_Group__c g = makeGroup(rel.Id, 'Premium Special');
        Package__c pkg = makePackage(g.Id, 'Premium Special $3,000', 3000, 100);
        insert new Package_Term__c(Name = '6 Months/Unlimited km', Package__c = pkg.Id, Price__c = 339);
        insert new Package_Term__c(Name = '12 Months/20,000 km', Package__c = pkg.Id, Price__c = 479);

        Test.startTest();
        MasterPackageAdminService.PackageDetail dto =
            MasterPackageAdminService.getPackageDetail(pkg.Id);
        Test.stopTest();

        Assert.isFalse(dto.hasTiers, 'a package with no tier rows has no bands');
        Assert.areEqual(0, dto.tierCount);
        Assert.areEqual(2, dto.termCount);
        Assert.areEqual(1, dto.tierBlocks.size(), 'all terms collect into one unbanded block');
        MasterPackageAdminService.TierBlock block = dto.tierBlocks[0];
        Assert.isFalse(block.hasTier);
        Assert.areEqual(2, block.terms.size());
        Boolean saw479 = false;
        Boolean saw339 = false;
        for (MasterPackageAdminService.TermRow tr : block.terms) {
            if ('$479'.equals(tr.priceLabel)) saw479 = true;
            if ('$339'.equals(tr.priceLabel)) saw339 = true;
        }
        Assert.isTrue(saw479, 'the 12-month term price is surfaced from the term');
        Assert.isTrue(saw339, 'the 6-month term price is surfaced from the term');
    }

    @IsTest
    static void packagesAreScopedToTheirGroup() {
        Catalogue_Release__c rel = makeRelease();
        Package_Group__c wanted = makeGroup(rel.Id, 'Wanted');
        Package_Group__c other = makeGroup(rel.Id, 'Other');
        makePackage(wanted.Id, 'In scope', 750, 100);
        makePackage(other.Id, 'Out of scope', 750, 100);

        Test.startTest();
        List<MasterPackageAdminService.PackageRow> rows =
            MasterPackageAdminService.getPackages(wanted.Id);
        Test.stopTest();

        Assert.areEqual(1, rows.size(), 'only the requested group\u2019s packages are returned');
        Assert.areEqual('In scope', rows[0].name);
    }

    @IsTest
    static void formOptionsExposePicklistsAndLookups() {
        Option__c opt = makeOption('Roadside Assist');
        Catalogue_Release__c rel = makeRelease();
        makeGroup(rel.Id, 'Options Group');

        Test.startTest();
        MasterPackageAdminService.FormOptions options =
            MasterPackageAdminService.getFormOptions();
        Test.stopTest();

        Assert.isTrue(options.packageTypeOptions.size() > 0, 'package-type picklist is surfaced');
        Assert.isTrue(options.selectionTypeOptions.size() > 0, 'selection-type picklist is surfaced');
        Assert.isTrue(options.addOnTypeOptions.size() > 0, 'add-on-type picklist is surfaced');
        Assert.isTrue(options.benefitTypeOptions.size() > 0, 'benefit-type picklist is surfaced');
        Assert.isTrue(options.mileageUnitOptions.size() > 0, 'mileage-unit picklist is surfaced');
        Boolean sawOption = false;
        for (MasterPackageAdminService.Choice c : options.optionChoices) {
            if (c.value == String.valueOf(opt.Id)) { sawOption = true; }
        }
        Assert.isTrue(sawOption, 'the option catalogue is offered as choices');
        Assert.isTrue(options.groupChoices.size() > 0, 'package groups are offered as choices');
    }

    // ── PHASE 2 — Package__c create / edit / activate ────────────────────────

    @IsTest
    static void blankPackageCreateEditAndToggle() {
        Catalogue_Release__c rel = makeRelease();
        Package_Group__c g = makeGroup(rel.Id, 'Blank Test');
        Package_Group__c other = makeGroup(rel.Id, 'Reparent Target');

        Test.startTest();
        MasterPackageAdminService.SaveResult created =
            MasterPackageAdminService.createBlankPackage(g.Id);
        Test.stopTest();

        Assert.isTrue(created.success, created.message);
        Assert.isNotNull(created.recordId);

        Package__c blank = [
            SELECT Name, Package_Group__c, Is_Active__c FROM Package__c WHERE Id = :created.recordId
        ];
        Assert.areEqual('New Master Package', blank.Name);
        Assert.areEqual(g.Id, blank.Package_Group__c);
        Assert.isTrue(blank.Is_Active__c, 'a blank package starts active');

        MasterPackageAdminService.PackageForm form = new MasterPackageAdminService.PackageForm();
        form.recordId = String.valueOf(created.recordId);
        form.name = 'Essential Gold';
        form.groupId = String.valueOf(other.Id);
        form.coveragePerClaim = 1500;
        form.deductible = 0;
        form.modelYearRestriction = '9 Years or Newer';
        form.mileage = 160000;
        form.mileageUnit = 'KM';
        form.packageType = 'Warranty';
        form.category = 'Gold';
        form.classValue = 'Class 2';
        form.isActive = true;

        MasterPackageAdminService.SaveResult saved =
            MasterPackageAdminService.updatePackage(form);

        Assert.isTrue(saved.success, saved.message);
        Package__c edited = [
            SELECT Name, Package_Group__c, Coverage_per_claim__c, Deductible__c,
                   Model_Year_Restriction__c, Mileage_Restriction__c, Mileage_Unit__c,
                   Package_Type__c, Category__c, Class__c
            FROM Package__c WHERE Id = :created.recordId
        ];
        Assert.areEqual('Essential Gold', edited.Name);
        Assert.areEqual(other.Id, edited.Package_Group__c, 'the package is reparented');
        Assert.isTrue(edited.Coverage_per_claim__c == 1500, 'the per-claim limit was saved');
        Assert.areEqual('Gold', edited.Category__c);

        MasterPackageAdminService.SaveResult deactivatedByAdmin =
            MasterPackageAdminService.setPackageActive(created.recordId, false);
        Assert.isTrue(deactivatedByAdmin.success);
        Assert.isFalse([SELECT Is_Active__c FROM Package__c WHERE Id = :created.recordId].Is_Active__c);

        MasterPackageAdminService.SaveResult reactivatedByAdmin =
            MasterPackageAdminService.setPackageActive(created.recordId, true);
        Assert.isTrue(reactivatedByAdmin.success);
        Assert.isTrue([SELECT Is_Active__c FROM Package__c WHERE Id = :created.recordId].Is_Active__c);
    }

    @IsTest
    static void packageWriteValidationGuards() {
        Catalogue_Release__c rel = makeRelease();
        Package_Group__c g = makeGroup(rel.Id, 'Guards');
        Package__c pkg = makePackage(g.Id, 'Guarded', 750, 100);
        String unknownGroupId = Package_Group__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000AAA';

        Assert.isFalse(MasterPackageAdminService.createBlankPackage(null).success,
            'a null group is refused');
        Assert.isFalse(MasterPackageAdminService.createBlankPackage(unknownGroupId).success,
            'an unknown group is refused');

        MasterPackageAdminService.PackageForm form = new MasterPackageAdminService.PackageForm();
        form.recordId = String.valueOf(pkg.Id);
        form.name = 'Valid';
        form.coveragePerClaim = -1;
        MasterPackageAdminService.SaveResult neg =
            MasterPackageAdminService.updatePackage(form);
        Assert.isFalse(neg.success, 'a negative per-claim limit is refused');
        Assert.isTrue(neg.message.contains('negative'), neg.message);

        form.coveragePerClaim = 500;
        form.name = '   ';
        Assert.isFalse(MasterPackageAdminService.updatePackage(form).success,
            'a blank package name is refused');

        form.name = 'Valid';
        form.packageType = 'Not A Real Type';
        Assert.isFalse(MasterPackageAdminService.updatePackage(form).success,
            'an invalid picklist value is refused');

        form.packageType = 'Warranty';
        form.groupId = unknownGroupId;
        Assert.isFalse(MasterPackageAdminService.updatePackage(form).success,
            'an unknown parent group is refused');

        MasterPackageAdminService.SaveResult missing =
            MasterPackageAdminService.updatePackage(new MasterPackageAdminService.PackageForm());
        Assert.isFalse(missing.success, 'a missing record id is refused');
        Assert.isFalse(MasterPackageAdminService.setPackageActive(null, true).success,
            'a null package id is refused');
    }

    // ── PHASE 2 — Package_Tier__c ────────────────────────────────────────────

    @IsTest
    static void tierCreateEditAndBandOrderingGuard() {
        Catalogue_Release__c rel = makeRelease();
        Package_Group__c g = makeGroup(rel.Id, 'Bands');
        Package__c pkg = makePackage(g.Id, 'Banded', 750, 100);

        MasterPackageAdminService.TierForm form = new MasterPackageAdminService.TierForm();
        form.packageId = String.valueOf(pkg.Id);
        form.name = '0-60k';
        form.startMileage = 0;
        form.endMileage = 60000;
        form.mileageUnit = 'KM';

        Test.startTest();
        MasterPackageAdminService.SaveResult created = MasterPackageAdminService.saveTier(form);
        Test.stopTest();
        Assert.isTrue(created.success, created.message);

        form.recordId = String.valueOf(created.recordId);
        form.endMileage = 80000;
        Assert.isTrue(MasterPackageAdminService.saveTier(form).success, 'band edits save');

        form.recordId = null;
        form.startMileage = 90000;
        form.endMileage = 10000;
        MasterPackageAdminService.SaveResult bad = MasterPackageAdminService.saveTier(form);
        Assert.isFalse(bad.success, 'a start greater than the end is refused');
        Assert.isTrue(bad.message.contains('greater'), bad.message);

        form.startMileage = 0;
        form.endMileage = 5000;
        form.name = ' ';
        Assert.isFalse(MasterPackageAdminService.saveTier(form).success,
            'a blank band name is refused');
    }

    // ── PHASE 2 — Package_Term__c (price anchor) ─────────────────────────────

    @IsTest
    static void termCreateEditAndPriceAnchorGuard() {
        Catalogue_Release__c rel = makeRelease();
        Package_Group__c g = makeGroup(rel.Id, 'Terms');
        Package__c pkg = makePackage(g.Id, 'Termed', 750, 100);
        Package_Tier__c band = new Package_Tier__c(
            Name = 'Band', Package__c = pkg.Id,
            Mileage_Restriction_Start__c = 0, Mileage_Restriction_End__c = 60000,
            Mileage_Unit__c = 'KM');
        insert band;

        MasterPackageAdminService.TermForm form = new MasterPackageAdminService.TermForm();
        form.packageId = String.valueOf(pkg.Id);
        form.tierId = String.valueOf(band.Id);
        form.name = '12 Months/20,000 km';
        form.price = 819;
        form.durationType = 'Months';
        form.restrictionType = 'Fixed Odometer';

        Test.startTest();
        MasterPackageAdminService.SaveResult created = MasterPackageAdminService.saveTerm(form);
        Test.stopTest();
        Assert.isTrue(created.success, created.message);
        Assert.areEqual(819,
            [SELECT Price__c FROM Package_Term__c WHERE Id = :created.recordId].Price__c);

        form.recordId = String.valueOf(created.recordId);
        form.price = 899;
        Assert.isTrue(MasterPackageAdminService.saveTerm(form).success, 'term edits save');

        form.recordId = null;
        form.price = null;
        MasterPackageAdminService.SaveResult noPrice = MasterPackageAdminService.saveTerm(form);
        Assert.isFalse(noPrice.success, 'price is required on a term');
        Assert.isTrue(noPrice.message.contains('Price'), noPrice.message);

        form.price = -5;
        Assert.isFalse(MasterPackageAdminService.saveTerm(form).success,
            'a negative price is refused');

        form.price = 100;
        form.name = ' ';
        Assert.isFalse(MasterPackageAdminService.saveTerm(form).success,
            'a blank term name is refused');
    }

    @IsTest
    static void blankTermTakesPackageAgeLimit() {
        // PackageTermTrigger side effect: a blank new term inherits the package's
        // Max. Vehicle Age Limit. The service must not fight it.
        Catalogue_Release__c rel = makeRelease();
        Package_Group__c g = makeGroup(rel.Id, 'Age Limit');
        Package__c pkg = makePackage(g.Id, 'Age Limited', 750, 100);
        pkg.Max_Vehicle_Age_Limit_In_Years__c = 9;
        update pkg;

        MasterPackageAdminService.TermForm form = new MasterPackageAdminService.TermForm();
        form.packageId = String.valueOf(pkg.Id);
        form.name = 'Blank ByYear Term';
        form.price = 500;

        Test.startTest();
        MasterPackageAdminService.SaveResult created = MasterPackageAdminService.saveTerm(form);
        Test.stopTest();
        Assert.isTrue(created.success, created.message);

        Decimal byYear = [
            SELECT ByYear__c FROM Package_Term__c WHERE Id = :created.recordId
        ].ByYear__c;
        Assert.areEqual(9, byYear, 'the blank term took the package age limit via the trigger');
    }

    // ── PHASE 2 — Package_Option__c ──────────────────────────────────────────

    @IsTest
    static void optionCreateEditAndGuards() {
        Catalogue_Release__c rel = makeRelease();
        Package_Group__c g = makeGroup(rel.Id, 'Options');
        Package__c pkg = makePackage(g.Id, 'Optioned', 750, 100);
        Option__c opt = makeOption('Zero Deductible');

        MasterPackageAdminService.OptionForm form = new MasterPackageAdminService.OptionForm();
        form.packageId = String.valueOf(pkg.Id);
        form.optionId = String.valueOf(opt.Id);
        form.selectionType = 'Optional';
        form.price = 30;
        form.inclusionText = 'Covers this';
        form.exclusionText = 'Not that';

        Test.startTest();
        MasterPackageAdminService.SaveResult created = MasterPackageAdminService.saveOption(form);
        Test.stopTest();
        Assert.isTrue(created.success, created.message);

        form.recordId = String.valueOf(created.recordId);
        form.price = 45;
        Assert.isTrue(MasterPackageAdminService.saveOption(form).success, 'option edits save');

        form.recordId = null;
        form.optionId = null;
        Assert.isFalse(MasterPackageAdminService.saveOption(form).success,
            'an option is required');
        form.optionId = String.valueOf(opt.Id);
        form.selectionType = 'Optional';
        form.price = null;
        Assert.isFalse(MasterPackageAdminService.saveOption(form).success,
            'an Optional row needs a price');
        form.selectionType = 'Included';
        form.price = 10;
        Assert.isFalse(MasterPackageAdminService.saveOption(form).success,
            'an Included row cannot carry a price');
        form.price = null;
        Assert.isTrue(MasterPackageAdminService.saveOption(form).success,
            'an Included row with no price saves');
    }

    // ── PHASE 2 — Package_Add_On__c ──────────────────────────────────────────

    @IsTest
    static void addOnCreateEditAndGuards() {
        Catalogue_Release__c rel = makeRelease();
        Package_Group__c g = makeGroup(rel.Id, 'Add-Ons');
        Package__c pkg = makePackage(g.Id, 'Add-Oned', 750, 100);
        Package_Term__c term = new Package_Term__c(
            Name = '12 Months', Package__c = pkg.Id, Price__c = 499);
        insert term;

        MasterPackageAdminService.AddOnForm form = new MasterPackageAdminService.AddOnForm();
        form.termId = String.valueOf(term.Id);
        form.addOnType = 'Car Rental';
        form.price = 149;

        Test.startTest();
        MasterPackageAdminService.SaveResult created = MasterPackageAdminService.saveAddOn(form);
        Test.stopTest();
        Assert.isTrue(created.success, created.message);

        form.recordId = String.valueOf(created.recordId);
        form.price = 199;
        Assert.isTrue(MasterPackageAdminService.saveAddOn(form).success, 'add-on edits save');

        form.recordId = null;
        form.termId = null;
        Assert.isFalse(MasterPackageAdminService.saveAddOn(form).success,
            'a term is required for an add-on');
        form.termId = String.valueOf(term.Id);
        form.addOnType = null;
        Assert.isFalse(MasterPackageAdminService.saveAddOn(form).success,
            'an add-on type is required');
    }

    // ── PHASE 2 — Package_Benefit_Cap__c ─────────────────────────────────────

    @IsTest
    static void benefitCapCreateEditAndGuards() {
        Catalogue_Release__c rel = makeRelease();
        Package_Group__c g = makeGroup(rel.Id, 'Caps');
        Package__c pkg = makePackage(g.Id, 'Capped', 750, 100);
        Package_Term__c term = new Package_Term__c(
            Name = '12 Months', Package__c = pkg.Id, Price__c = 499);
        insert term;

        MasterPackageAdminService.BenefitCapForm form = new MasterPackageAdminService.BenefitCapForm();
        form.termId = String.valueOf(term.Id);
        form.benefitType = 'Car Rental';
        form.capAmount = 500;

        Test.startTest();
        MasterPackageAdminService.SaveResult created =
            MasterPackageAdminService.saveBenefitCap(form);
        Test.stopTest();
        Assert.isTrue(created.success, created.message);

        form.recordId = String.valueOf(created.recordId);
        form.capAmount = 750;
        Assert.isTrue(MasterPackageAdminService.saveBenefitCap(form).success, 'cap edits save');

        form.recordId = null;
        form.capAmount = null;
        Assert.isFalse(MasterPackageAdminService.saveBenefitCap(form).success,
            'a cap amount is required');
        form.capAmount = 100;
        form.benefitType = null;
        Assert.isFalse(MasterPackageAdminService.saveBenefitCap(form).success,
            'a benefit type is required');
    }

    // ── PHASE 2 — guarded deletes ────────────────────────────────────────────

    @IsTest
    static void deletesAreGuardedAndSafe() {
        Catalogue_Release__c rel = makeRelease();
        Package_Group__c g = makeGroup(rel.Id, 'Deletes');
        Package__c pkg = makePackage(g.Id, 'Deletable', 750, 100);

        Package_Tier__c busyBand = new Package_Tier__c(
            Name = 'Busy', Package__c = pkg.Id, Mileage_Unit__c = 'KM');
        Package_Tier__c freeBand = new Package_Tier__c(
            Name = 'Free', Package__c = pkg.Id, Mileage_Unit__c = 'KM');
        insert new List<Package_Tier__c>{ busyBand, freeBand };

        Package_Term__c term = new Package_Term__c(
            Name = '12 Months', Package__c = pkg.Id, Package_Tier__c = busyBand.Id, Price__c = 499);
        insert term;

        // A band with a term under it cannot be deleted…
        Assert.isFalse(MasterPackageAdminService.deleteTier(busyBand.Id).success,
            'a band with terms is protected');
        // …an empty band can.
        Assert.isTrue(MasterPackageAdminService.deleteTier(freeBand.Id).success);

        // A term with a linked add-on cannot be deleted until the add-on goes.
        Package_Add_On__c addOn = new Package_Add_On__c(
            Package_Term__c = term.Id, Add_On_Type__c = 'Car Rental', Price__c = 149);
        insert addOn;
        Assert.isFalse(MasterPackageAdminService.deleteTerm(term.Id).success,
            'a term with linked rows is protected');
        Assert.isTrue(MasterPackageAdminService.deleteAddOn(addOn.Id).success, 'the leaf add-on deletes');
        Assert.isTrue(MasterPackageAdminService.deleteTerm(term.Id).success,
            'the term deletes once nothing rides on it');

        // Leaf option + benefit-cap deletes.
        Option__c opt = makeOption('Roadside');
        Package_Option__c optionRow = new Package_Option__c(
            Package__c = pkg.Id, Option__c = opt.Id, Selection_Type__c = 'Included');
        insert optionRow;
        Assert.isTrue(MasterPackageAdminService.deleteOptionRow(optionRow.Id).success);

        Package_Term__c term2 = new Package_Term__c(Name = '6 Months', Package__c = pkg.Id, Price__c = 299);
        insert term2;
        Package_Benefit_Cap__c cap = new Package_Benefit_Cap__c(
            Package_Term__c = term2.Id, Benefit_Type__c = 'Car Rental', Cap_Amount__c = 500);
        insert cap;
        Assert.isTrue(MasterPackageAdminService.deleteBenefitCap(cap.Id).success);

        // Unknown ids are refused, never silently ignored.
        Assert.isFalse(MasterPackageAdminService.deleteTier(null).success);
        Assert.isFalse(MasterPackageAdminService.deleteTerm(null).success);
    }

    // ── PHASE 2 — FLS fail-closed + null-id writes ───────────────────────────

    @IsTest
    static void fieldAccessGuardsFailClosed() {
        Catalogue_Release__c rel = makeRelease();
        Package_Group__c g = makeGroup(rel.Id, 'FLS');
        Package__c pkg = makePackage(g.Id, 'Guarded FLS', 750, 100);

        MasterPackageAdminService.PackageForm form = new MasterPackageAdminService.PackageForm();
        form.recordId = String.valueOf(pkg.Id);
        form.name = 'Attempted';

        MasterPackageAdminService.simulateFieldAccessDenied = true;
        Test.startTest();
        MasterPackageAdminService.SaveResult blocked =
            MasterPackageAdminService.updatePackage(form);
        MasterPackageAdminService.SaveResult blankBlocked =
            MasterPackageAdminService.createBlankPackage(g.Id);
        Test.stopTest();
        MasterPackageAdminService.simulateFieldAccessDenied = false;

        Assert.isFalse(blocked.success, 'a denied field fails closed');
        Assert.isTrue(blocked.message.containsIgnoreCase('permission'), blocked.message);
        Assert.isFalse(blankBlocked.success, 'create is blocked when the field cannot be set');
        // The guard performs no DML: the package is unchanged.
        Assert.areEqual('Guarded FLS',
            [SELECT Name FROM Package__c WHERE Id = :pkg.Id].Name);
    }

    @IsTest
    static void nullFormsAreRefusedGracefully() {
        Test.startTest();
        Assert.isFalse(MasterPackageAdminService.updatePackage(null).success);
        Assert.isFalse(MasterPackageAdminService.saveTier(null).success);
        Assert.isFalse(MasterPackageAdminService.saveTerm(null).success);
        Assert.isFalse(MasterPackageAdminService.saveOption(null).success);
        Assert.isFalse(MasterPackageAdminService.saveAddOn(null).success);
        Assert.isFalse(MasterPackageAdminService.saveBenefitCap(null).success);
        Assert.isFalse(MasterPackageAdminService.deleteOptionRow(null).success);
        Assert.isFalse(MasterPackageAdminService.deleteAddOn(null).success);
        Assert.isFalse(MasterPackageAdminService.deleteBenefitCap(null).success);
        Test.stopTest();
    }
}