/**
 * Estimate lifecycle (Add / Edit / Remove Scenario in the HTML calculator)
 * and the Create Work Order transaction.
 *
 * Remove deletes the Part__c / Service__c / Shop_Supply__c children
 * explicitly: their lookups to Estimate__c are SetNull, so deleting the
 * estimate alone would orphan them, not remove them.
 *
 * Create Work Order, in one transaction:
 *   1. Work_Order__c with its existing Estimate__c lookup set (source of
 *      truth for "which estimate won").
 *   2. Estimate__c.Is_Selected__c = true on the chosen estimate, false on
 *      its siblings, kept in step with the lookup above.
 *   3. One Claim_Line_Item__c per charge (Part / Labour / Supplies) from the
 *      estimate's children. Amount__c is what A-Protect owes the vendor.
 *   4. Work_Order_Line_Item__c rows generated FROM those Claim Line Items.
 *      Price__c is populated because Work_Order__c.Total_Line_Items_Cost__c
 *      rolls it up.
 *
 * FLS/CRUD hardening (Sep 22, Osama's explicit request after asking whether
 * this LWC-facing service enforces profile-based security): "with sharing"
 * only enforces record-level sharing, never field-level security or object
 * CRUD by itself, so every SOQL query here runs WITH USER_MODE and every
 * insert/update/delete goes through Database.<op>(records, AccessLevel.
 * USER_MODE) rather than a bare DML statement - the platform throws
 * (System.NoAccessException, wrapped below as AuraHandledException) instead
 * of silently writing/reading past a missing grant. (First attempt used
 * WITH SECURITY_ENFORCED / Security.stripInaccessible - this org's API
 * version rejects SECURITY_ENFORCED as deprecated in favor of USER_MODE,
 * which - bonus - also works on queries with subqueries, unlike
 * SECURITY_ENFORCED, so nothing here is exempted the way an earlier pass
 * assumed.)
 */
public with sharing class ClaimEstimateService {

    public class WorkOrderResult {
        @AuraEnabled public Id workOrderId          { get; set; }
        @AuraEnabled public Integer claimLineItems  { get; set; }
        @AuraEnabled public Integer workOrderLines  { get; set; }
    }

    // ───────────────────────── Estimate lifecycle ─────────────────────────

    /**
     * Backs the Estimates tab's custom related list (claimEstimatesList LWC).
     * Deliberately NOT cacheable (Sep 22 fix): this list must show the
     * result of a just-completed Manage Estimates save immediately, and an
     * imperative call to a cacheable method can still be served the
     * framework's cached response with no refreshApex equivalent to bust
     * it - claimEstimatesList calls this directly (not via @wire) precisely
     * so every call is guaranteed fresh.
     */
    @AuraEnabled
    public static List<Estimate__c> getEstimatesForClaim(Id claimId) {
        return [
            // Osama, 2026-10-09: Source dropped from the Estimates related list
            // and Customer Pays (+tax) added after Retail Total. The figure is
            // READ from Customer_Pays_With_Tax__c, the calc() custTax output the
            // pricing service stamps, not recomputed here.
            SELECT Id, Name, Estimate_Name__c, Repair_Shop__c, Repair_Shop__r.Name,
                   Retail_Total__c, Customer_Pays_With_Tax__c, Is_Selected__c
            FROM Estimate__c
            WHERE Claim__c = :claimId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
        ];
    }

    /**
     * Full editable detail for every estimate on a claim - backs the Repair
     * Price Scenarios grid loading existing estimates for editing (Sep 22),
     * not just the summary columns getEstimatesForClaim returns for the
     * related list. Deliberately NOT cacheable, same reason as
     * getEstimatesForClaim above - reopening this screen after a save must
     * show the just-saved values, not a stale cached response.
     */
    @AuraEnabled
    public static List<Estimate__c> getEstimateDetailsForClaim(Id claimId) {
        return [
            SELECT Id, Estimate_Name__c, Repair_Shop__c, Repair_Shop__r.Tax_Percentage__c, Source__c,
                   Part_Component__c, Job_Type__c,
                   Parts_Supplier__c, Part_Code__c, Stock_Number__c, Condition__c, KMs__c,
                   Insurance_Source__c, Insurance_Amount__c, Parts_Cost__c, Labour_Hours__c, Labour_Rate__c,
                   Shop_Supplies__c, Shop_Supplies_Retail__c, Retail_Price__c, Deductable__c, Is_Selected__c
            FROM Estimate__c
            WHERE Claim__c = :claimId
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ];
    }

    @AuraEnabled
    public static Estimate__c createEstimate(Id claimId, Id repairShopId, String estimateName) {
        Estimate__c e = new Estimate__c(
            Claim__c        = claimId,
            Repair_Shop__c  = repairShopId,
            Estimate_Name__c = estimateName
        );
        if (repairShopId != null) {
            Repair_Shop__c shop = [
                SELECT Labour_Rate_On_File__c FROM Repair_Shop__c
                WHERE Id = :repairShopId
                WITH USER_MODE
            ];
            e.Labour_Rate__c = shop.Labour_Rate_On_File__c;
        }
        insertSecured(new List<Estimate__c>{ e });
        syncEstimateChildren(new List<Estimate__c>{ e });
        return e;
    }

    /** Saves the edited inputs, then re-stamps the totals so they never drift. */
    @AuraEnabled
    public static ClaimPricingService.PricingResult updateEstimate(Estimate__c estimate, Decimal cap) {
        updateSecured(new List<Estimate__c>{ estimate });
        ClaimPricingService.PricingResult r = ClaimPricingService.recalculateAndStamp(estimate.Id, cap);
        syncEstimateChildren(new List<Estimate__c>{ estimate });
        return r;
    }

    /**
     * Marks one estimate selected and clears the flag on every sibling on the
     * same claim. Called directly from the Repair Price Scenarios grid's USE
     * radio at save time (Sep 22 decision) - a preview of the eventual
     * winner, ahead of Create Work Order. createWorkOrder calls the same
     * shared helper, so whichever estimate actually becomes the work order
     * always wins the flag in the end, regardless of what was marked here.
     */
    @AuraEnabled
    public static void selectEstimate(Id estimateId) {
        Estimate__c est = [
            SELECT Id, Claim__c FROM Estimate__c
            WHERE Id = :estimateId
            WITH USER_MODE
        ];
        markSelected(est.Id, est.Claim__c);
    }

    private static void markSelected(Id estimateId, Id claimId) {
        List<Estimate__c> siblings = [
            SELECT Id, Is_Selected__c FROM Estimate__c
            WHERE Claim__c = :claimId
            WITH USER_MODE
        ];
        for (Estimate__c s : siblings) s.Is_Selected__c = (s.Id == estimateId);
        updateSecured(siblings);
    }

    @AuraEnabled
    public static void deleteEstimate(Id estimateId) {
        Savepoint sp = Database.setSavepoint();
        try {
            deleteSecured([SELECT Id FROM Part__c        WHERE Estimate__c = :estimateId WITH USER_MODE]);
            deleteSecured([SELECT Id FROM Service__c     WHERE Estimate__c = :estimateId WITH USER_MODE]);
            deleteSecured([SELECT Id FROM Shop_Supply__c WHERE Estimate__c = :estimateId WITH USER_MODE]);
            deleteSecured([SELECT Id FROM Estimate__c    WHERE Id = :estimateId          WITH USER_MODE]);
        } catch (Exception ex) {
            Database.rollback(sp);
            throw new AuraHandledException('Could not remove estimate: ' + ex.getMessage());
        }
    }

    /**
     * Bulk equivalent of createEstimate + updateEstimate + deleteEstimate +
     * selectEstimate combined - saves every row of the Repair Price
     * Scenarios grid in ONE Apex call instead of one call per row (Sep 22
     * fix: Save All Estimates was taking 6-7 seconds with several rows,
     * because the LWC previously awaited a separate round trip per row in
     * a for loop - each @AuraEnabled call has real fixed network/platform
     * overhead on top of its own work, so N rows meant N+ sequential round
     * trips. This collapses the whole save into a handful of bulk SOQL/DML
     * statements in one transaction, so total time barely grows with row
     * count.
     *
     * estimates: one entry per row currently in the grid, Id populated for
     * an existing row (update) or blank for a new one (insert); the row
     * with Is_Selected__c = true (at most one) becomes the claim's selected
     * estimate, same meaning as selectEstimate/createWorkOrder's flag.
     * deleteIds: estimates removed from the grid since it was opened -
     * deleted along with their Part__c/Service__c/Shop_Supply__c children,
     * batched across every removed estimate rather than one delete per id.
     */
    @AuraEnabled
    public static void saveEstimates(Id claimId, List<Estimate__c> estimates, List<Id> deleteIds) {
        Savepoint sp = Database.setSavepoint();
        try {
            if (deleteIds != null && !deleteIds.isEmpty()) {
                deleteSecured([SELECT Id FROM Part__c        WHERE Estimate__c IN :deleteIds WITH USER_MODE]);
                deleteSecured([SELECT Id FROM Service__c     WHERE Estimate__c IN :deleteIds WITH USER_MODE]);
                deleteSecured([SELECT Id FROM Shop_Supply__c WHERE Estimate__c IN :deleteIds WITH USER_MODE]);
                deleteSecured([SELECT Id FROM Estimate__c    WHERE Id IN :deleteIds          WITH USER_MODE]);
            }
            if (estimates == null || estimates.isEmpty()) return;

            List<Estimate__c> toInsert = new List<Estimate__c>();
            List<Estimate__c> toUpdate = new List<Estimate__c>();
            Set<Id> shopIds = new Set<Id>();
            for (Estimate__c e : estimates) {
                if (e.Repair_Shop__c != null) shopIds.add(e.Repair_Shop__c);
                if (e.Id == null) { e.Claim__c = claimId; toInsert.add(e); }
                else toUpdate.add(e);
            }

            // One query for every shop referenced across every row, instead
            // of one per row - same bulk principle as the round-trip fix.
            Map<Id, Repair_Shop__c> shopsById = new Map<Id, Repair_Shop__c>([
                SELECT Id, Labour_Rate_On_File__c, Tax_Percentage__c
                FROM Repair_Shop__c WHERE Id IN :shopIds
                WITH USER_MODE
            ]);
            for (Estimate__c e : toInsert) {
                if (e.Labour_Rate__c == null && e.Repair_Shop__c != null) {
                    Repair_Shop__c shop = shopsById.get(e.Repair_Shop__c);
                    if (shop != null) e.Labour_Rate__c = shop.Labour_Rate_On_File__c;
                }
            }

            insertSecured(toInsert);  // populates Id on toInsert's records, same objects referenced in estimates
            updateSecured(toUpdate);

            // Recompute + stamp totals for every row from the already-known
            // shop data and one shared claim-level cap/deductible lookup -
            // no per-row query, matching the same bulk principle throughout.
            Claim__c claim = [
                SELECT Application_Package__r.Per_Claim_Limit__c, Application_Package__r.Deductible__c
                FROM Claim__c WHERE Id = :claimId
                WITH USER_MODE
            ];
            Decimal claimCap = claim.Application_Package__r?.Per_Claim_Limit__c;
            Decimal claimDed = claim.Application_Package__r?.Deductible__c;

            List<Estimate__c> toStamp = new List<Estimate__c>();
            for (Estimate__c e : estimates) {
                Repair_Shop__c shop = e.Repair_Shop__c != null ? shopsById.get(e.Repair_Shop__c) : null;
                ClaimPricingService.PricingInput i = new ClaimPricingService.PricingInput();
                i.parts      = e.Parts_Cost__c;
                i.hrs        = e.Labour_Hours__c;
                i.rate       = e.Labour_Rate__c != null ? e.Labour_Rate__c : shop?.Labour_Rate_On_File__c;
                i.ins        = e.Insurance_Amount__c;
                i.supC       = e.Shop_Supplies__c;
                i.supR       = e.Shop_Supplies_Retail__c;
                i.retail     = e.Retail_Price__c;
                i.ded        = e.Deductable__c != null ? e.Deductable__c : claimDed;
                i.taxPercent = shop?.Tax_Percentage__c;
                i.cap        = claimCap;
                ClaimPricingService.PricingResult r = ClaimPricingService.calculate(i);
                toStamp.add(new Estimate__c(
                    Id                        = e.Id,
                    Labour_Cost__c            = r.labour,
                    Wholesale_Cost__c         = r.wsTotal,
                    Coverage_Applied__c       = r.coverage,
                    Customer_Pays__c          = r.custPre,
                    Customer_Pays_With_Tax__c = r.custTax,
                    Profit_Loss__c            = r.pl,
                    Retail_Total__c           = r.retailTotal,
                    // Sep 22 (Osama): write back the deductible actually
                    // used - the estimate's own override if one was set,
                    // otherwise the claim's - so the record shows the real
                    // number instead of staying blank whenever no override
                    // was ever entered. Never changes the math (i.ded is
                    // already what calculate() used above), purely visibility.
                    Deductable__c             = i.ded
                ));
            }
            updateSecured(toStamp);

            // Selection: whichever row came in with Is_Selected__c = true
            // wins, and every other estimate on the claim (including ones
            // not part of this save) is cleared to match - same guarantee
            // selectEstimate/createWorkOrder already give, just reached
            // without an extra round trip.
            Id selectedId = null;
            for (Estimate__c e : estimates) if (e.Is_Selected__c == true) selectedId = e.Id;
            if (selectedId != null) markSelected(selectedId, claimId);

            syncEstimateChildren(estimates);
        } catch (Exception ex) {
            Database.rollback(sp);
            throw new AuraHandledException('Could not save estimates: ' + ex.getMessage());
        }
    }

    /**
     * Keeps Part__c/Service__c/Shop_Supply__c in sync with their parent
     * Estimate__c's own scalar fields (Sep 25 - closes the gap Osama
     * flagged: the Repair Price Scenarios grid has only ever written
     * scalar fields onto Estimate__c since the Sep 16 architecture
     * decision, never actually creating the real Part/Service/Shop_Supply
     * children those scalars represent). One child of each type per
     * Estimate__c - mirrors buildClaimLineItems' own "3 lines max, one per
     * type, only when non-zero" pattern exactly, since there is no
     * per-estimate multi-part itemization in this model. Upserts by the
     * existing Estimate__c lookup (never duplicates on re-save); deletes
     * (not just blanks) a child whose triggering amount goes to zero, so
     * an estimate edited down to $0 doesn't leave a stray zero-dollar
     * child behind.
     *
     * Resolves Claim__c itself via a fresh query rather than trusting
     * estimate.Claim__c to be populated on the incoming objects - the grid's
     * save payload only sets Claim__c for brand-new (toInsert) rows, never
     * for edits to existing ones, so reading it off the caller's object
     * would silently null out Part__c.Claim__c on every edit-only save.
     *
     * HARD RULE: Export_to_Work_Order__c is never set true here (stays at
     * its schema default, false). Setting it true would let the dormant
     * legacy WorkOrderCreatorController.createWorkOrders() pick these
     * records up and generate a second, conflicting Work_Order__c - that
     * legacy path's own filter (Export_to_Work_Order__c = true AND
     * Repair_Shop__c != null) is the only thing keeping it inert, and this
     * rule keeps it that way.
     *
     * Bulk-safe: one query per child type plus one Claim__c-resolution
     * query across the whole batch, one insert list + one update list per
     * child type - 7 DML statements total regardless of how many estimates
     * are being saved.
     */
    private static void syncEstimateChildren(List<Estimate__c> estimates) {
        Set<Id> estimateIds = new Set<Id>();
        for (Estimate__c e : estimates) if (e.Id != null) estimateIds.add(e.Id);
        if (estimateIds.isEmpty()) return;

        // Re-query every field fresh by Id rather than trusting the caller's
        // objects to carry them - createEstimate/saveEstimates' payloads
        // always do, but updateEstimate's single-record callers (including
        // this class's own tests) can pass a partially-selected SOQL result,
        // and Apex throws reading an unqueried field even for one this
        // method never changes (e.g. Repair_Shop__c). Self-sufficient here
        // means this never breaks regardless of what the caller populated.
        Map<Id, Estimate__c> freshById = new Map<Id, Estimate__c>([
            SELECT Id, Claim__c, Repair_Shop__c, Part_Component__c, Part_Code__c, Condition__c,
                   KMs__c, Parts_Supplier__c, Parts_Cost__c, Retail_Price__c, Job_Type__c,
                   Labour_Hours__c, Labour_Rate__c, Shop_Supplies__c, Shop_Supplies_Retail__c
            FROM Estimate__c WHERE Id IN :estimateIds
            WITH USER_MODE
        ]);

        Map<Id, Part__c> partByEstimate = new Map<Id, Part__c>();
        for (Part__c p : [SELECT Id, Estimate__c FROM Part__c WHERE Estimate__c IN :estimateIds WITH USER_MODE]) {
            partByEstimate.put(p.Estimate__c, p);
        }
        Map<Id, Service__c> serviceByEstimate = new Map<Id, Service__c>();
        for (Service__c s : [SELECT Id, Estimate__c FROM Service__c WHERE Estimate__c IN :estimateIds WITH USER_MODE]) {
            serviceByEstimate.put(s.Estimate__c, s);
        }
        Map<Id, Shop_Supply__c> supplyByEstimate = new Map<Id, Shop_Supply__c>();
        for (Shop_Supply__c sp : [SELECT Id, Estimate__c FROM Shop_Supply__c WHERE Estimate__c IN :estimateIds WITH USER_MODE]) {
            supplyByEstimate.put(sp.Estimate__c, sp);
        }

        List<Part__c> partsToInsert = new List<Part__c>();
        List<Part__c> partsToUpdate = new List<Part__c>();
        List<Service__c> servicesToInsert = new List<Service__c>();
        List<Service__c> servicesToUpdate = new List<Service__c>();
        List<Shop_Supply__c> suppliesToInsert = new List<Shop_Supply__c>();
        List<Shop_Supply__c> suppliesToUpdate = new List<Shop_Supply__c>();
        List<SObject> toDelete = new List<SObject>();

        for (Estimate__c e : freshById.values()) {
            Id claimId = e.Claim__c;

            // Same proportional split buildClaimLineItems already uses, so
            // Part__c/Service__c's retail figures agree with the eventual
            // Claim_Line_Item__c/Work_Order_Line_Item__c retail split.
            Decimal partsWholesale  = nz(e.Parts_Cost__c);
            Decimal labourWholesale = nz(e.Labour_Hours__c) * nz(e.Labour_Rate__c);
            Decimal repairWholesale = partsWholesale + labourWholesale;
            Decimal jobRetail       = nz(e.Retail_Price__c);
            Decimal partsShare = repairWholesale > 0
                ? (partsWholesale / repairWholesale).setScale(10, RoundingMode.HALF_UP)
                : 0;
            Decimal partsRetail  = (jobRetail * partsShare).setScale(2, RoundingMode.HALF_UP);
            Decimal labourRetail = jobRetail - partsRetail;

            // Part__c
            Part__c existingPart = partByEstimate.get(e.Id);
            if (partsWholesale != 0) {
                Part__c p = existingPart != null ? new Part__c(Id = existingPart.Id) : new Part__c();
                p.Estimate__c    = e.Id;
                p.Claim__c       = claimId;
                p.Repair_Shop__c = e.Repair_Shop__c;
                p.Part_Name__c   = e.Part_Component__c;
                p.Part_Code__c   = e.Part_Code__c;
                p.Part_Type__c   = e.Condition__c;
                p.Part_Cost__c   = partsWholesale;
                p.Price__c       = partsRetail;
                p.KMS__c         = e.KMs__c;
                p.Supplier__c    = e.Parts_Supplier__c;
                if (existingPart == null) { p.Quantity__c = 1; partsToInsert.add(p); }
                else partsToUpdate.add(p);
            } else if (existingPart != null) {
                toDelete.add(existingPart);
            }

            // Service__c
            Service__c existingService = serviceByEstimate.get(e.Id);
            if (labourWholesale != 0) {
                Service__c s = existingService != null ? new Service__c(Id = existingService.Id) : new Service__c();
                s.Estimate__c    = e.Id;
                s.Repair_Shop__c = e.Repair_Shop__c;
                s.Job_Type__c    = e.Job_Type__c;
                s.Time__c        = e.Labour_Hours__c != null ? String.valueOf(e.Labour_Hours__c) : null;
                s.Repair_Time_Adj__c = e.Labour_Hours__c != null
                    ? e.Labour_Hours__c.setScale(0, RoundingMode.HALF_UP) : null;
                s.Wholesale_Labour_Rate_HR__c = e.Labour_Rate__c;
                s.Wholesale__c   = labourWholesale;
                s.Retail__c      = labourRetail;
                if (existingService == null) servicesToInsert.add(s);
                else servicesToUpdate.add(s);
            } else if (existingService != null) {
                toDelete.add(existingService);
            }

            // Shop_Supply__c
            Shop_Supply__c existingSupply = supplyByEstimate.get(e.Id);
            Decimal suppliesWholesale = nz(e.Shop_Supplies__c);
            Decimal suppliesRetail    = nz(e.Shop_Supplies_Retail__c);
            if (suppliesWholesale != 0 || suppliesRetail != 0) {
                Shop_Supply__c sup = existingSupply != null ? new Shop_Supply__c(Id = existingSupply.Id) : new Shop_Supply__c();
                sup.Estimate__c    = e.Id;
                sup.Repair_Shop__c = e.Repair_Shop__c;
                sup.Cost__c        = suppliesWholesale;
                sup.Price__c       = suppliesRetail;
                if (existingSupply == null) { sup.Item_Name__c = 'Shop Supplies'; suppliesToInsert.add(sup); }
                else suppliesToUpdate.add(sup);
            } else if (existingSupply != null) {
                toDelete.add(existingSupply);
            }
        }

        insertSecured(partsToInsert);
        updateSecured(partsToUpdate);
        insertSecured(servicesToInsert);
        updateSecured(servicesToUpdate);
        insertSecured(suppliesToInsert);
        updateSecured(suppliesToUpdate);
        if (!toDelete.isEmpty()) deleteSecured(toDelete);
    }

    // ═══════════════════ Manage Estimates (TASK-047) ══════════════════════
    //
    // Noelle's Repair Price Scenarios Feedback 1.0. The architectural change
    // here is that Part__c / Service__c / Shop_Supply__c become the SOURCE OF
    // TRUTH, many of each per Estimate__c, where syncEstimateChildren above
    // treated them as derived copies of the Estimate's own scalars and
    // allowed exactly one of each.
    //
    // The Estimate__c scalars do not go away. recalculateRollups below
    // recomputes every one of them from the children on each save, so
    // ClaimPricingService.calculate's consumers, the nine Work_Order__c
    // formula fields, claimsWorksheet and both screen flows keep reading the
    // field names they have always read (Osama's decision 1). Native roll-up
    // summary fields are not an option: the three children are Lookup to
    // Estimate__c, not master-detail.
    //
    // Pricing runs through ClaimPricingService.calculateScenario, which
    // replaces the older calculate() coverage and tax sequence: the cap is
    // now tested against the TAX-INCLUSIVE repair, and approved ancillary
    // benefits are subtracted from the customer's bill (Osama's decision 8).
    // Historical records are not restated (decision 10).

    public class ManageEstimatesData {
        @AuraEnabled public String claimNumber;
        @AuraEnabled public String vehicle;
        /** Read-only, from the purchased contract. Decision 4: not an input. */
        @AuraEnabled public Decimal cap;
        @AuraEnabled public Decimal deductible;
        @AuraEnabled public List<BenefitBalanceRow> benefits;
        @AuraEnabled public List<ScenarioRow> scenarios;
        @AuraEnabled public List<ShopOption> shops;
        @AuraEnabled public List<NamedOption> suppliers;
        /**
         * TASK-050. The work order header, read from the claim rather than
         * typed into the preview by hand as it was before. Every one of these
         * is an existing field: no value here is derived in Apex, per Osama's
         * rule of 2026-10-08.
         */
        @AuraEnabled public String applicationNumber;
        @AuraEnabled public String customerName;
        @AuraEnabled public String customerAddress;
        @AuraEnabled public String customerPhone;
        @AuraEnabled public String customerEmail;
        @AuraEnabled public String vin;
        @AuraEnabled public Decimal odometer;
        @AuraEnabled public String odometerUnit;
        /**
         * TASK-051. Options for Estimate__c.Reimbursement_Payment_Method__c,
         * read from the field so the picklist stays the one definition.
         */
        @AuraEnabled public List<ValueOption> paymentMethodOptions;
        /**
         * How many payload rows saveManageEstimates refused because they
         * carried no content. Always 0 on a plain read. The screen reports a
         * non-zero count rather than claiming a successful save, because
         * skipping silently is what made the original problem so hard to see:
         * the agent clicked Save, nothing persisted, and nothing said why.
         */
        @AuraEnabled public Integer skippedEmptyScenarios = 0;
    }

    public class ShopOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        /** Composed from the structured parts, falling back to the legacy single-line Address__c. */
        @AuraEnabled public String address;
        @AuraEnabled public String city;
        /** The design calls this "Area": the metro the shop is worked as part of, which can differ from city. */
        @AuraEnabled public String region;
        @AuraEnabled public String phone;
        @AuraEnabled public Decimal postedRate;
        @AuraEnabled public Decimal taxPercent;
        /** "Pays by", already expanded from the multi-select into a readable list. */
        @AuraEnabled public String paysBy;
    }

    public class NamedOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
    }

    /** A picklist value in the shape lightning-combobox takes. */
    public class ValueOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
    }

    public class ScenarioRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Id repairShopId;
        @AuraEnabled public String repairShopName;
        @AuraEnabled public String network;
        @AuraEnabled public String claimType;
        @AuraEnabled public Decimal taxPercent;
        @AuraEnabled public Decimal deductible;
        @AuraEnabled public Boolean isSelected;
        /** TASK-051. Reimbursement Only only; saved as null on a Repair scenario. */
        @AuraEnabled public String paymentMethod;
        @AuraEnabled public Date expectedPaymentDate;
        @AuraEnabled public List<PartRow> parts;
        @AuraEnabled public List<LabourRow> labour;
        @AuraEnabled public List<SupplyRow> supplies;
        @AuraEnabled public List<ReimbursementRow> reimbursements;
    }

    public class PartRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String partNumber;
        @AuraEnabled public String category;
        @AuraEnabled public String condition;
        @AuraEnabled public Id supplierId;
        @AuraEnabled public String supplierName;
        @AuraEnabled public String stockNumber;
        @AuraEnabled public Decimal kms;
        @AuraEnabled public Decimal qty;
        @AuraEnabled public Decimal unitWholesale;
        @AuraEnabled public String markupType;
        @AuraEnabled public Decimal markupValue;
        @AuraEnabled public Decimal unitRetail;
        @AuraEnabled public Decimal coreCharge;
        @AuraEnabled public String warrantySource;
        @AuraEnabled public Boolean includedWarranty;
        @AuraEnabled public String includedWarrantyCovers;
        @AuraEnabled public Decimal includedWarrantyMonths;
        @AuraEnabled public Decimal includedWarrantyKm;
        @AuraEnabled public Boolean extendedWarranty;
        @AuraEnabled public Decimal extendedWarrantyMonths;
        @AuraEnabled public Decimal extendedWarrantyKm;
        @AuraEnabled public Decimal extendedWarrantyCost;
        @AuraEnabled public String extendedWarrantyMarkupType;
        @AuraEnabled public Decimal extendedWarrantyMarkupValue;
        @AuraEnabled public Decimal extendedWarrantyRetail;
        @AuraEnabled public String warrantyNotes;
    }

    public class LabourRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String description;
        @AuraEnabled public Decimal wholesaleHours;
        @AuraEnabled public Decimal wholesaleRate;
        @AuraEnabled public Decimal wholesaleTotal;
        @AuraEnabled public Decimal retailHours;
        @AuraEnabled public Decimal retailRate;
        @AuraEnabled public Decimal retailTotal;
        @AuraEnabled public Decimal guideMitchell;
        @AuraEnabled public Decimal guideAllData;
    }

    public class SupplyRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String description;
        @AuraEnabled public Decimal wholesaleCost;
        @AuraEnabled public String markupType;
        @AuraEnabled public Decimal markupValue;
        @AuraEnabled public Decimal retailPrice;
    }

    public class ReimbursementRow {
        @AuraEnabled public Id id;            // Benefit_Usage__c
        @AuraEnabled public Id benefitBalanceId;
        @AuraEnabled public String benefitType;
        @AuraEnabled public Decimal receiptAmount;
        /**
         * TASK-051. How much of this saved line Benefit_Balance__c.Remaining__c
         * already has subtracted: the amount when the line counts toward the
         * balance (its scenario is marked Use), otherwise 0. The LWC adds it
         * back to find the room this scenario really has, exactly as
         * getApprovedReimbursements does.
         */
        @AuraEnabled public Decimal countedAmount;
    }

    /**
     * TASK-051. One saved reimbursement receipt and what A-Protect approves
     * for it, in the columns of the Feedback 1.0 reimbursement notice.
     */
    public class ApprovedReimbursement {
        public Id usageId;
        public Id estimateId;
        public Id balanceId;
        public String benefitType;
        public Decimal receipts;
        public Decimal approved;
        public Decimal leftOnTerm;
        public Decimal over;
    }

    /**
     * TASK-051. THE approval rule for reimbursement receipts, in one place:
     * a receipt is approved only up to the room left on its benefit for the
     * term, and Left on term is that room less the approval.
     *
     * Room is Benefit_Balance__c.Remaining__c PLUS this estimate's own draws
     * on the same balance that are already counted in it (a scenario marked
     * Use writes its receipts with Counts_Toward_Balance__c = true, so the
     * roll-up has subtracted them). Without the add-back a selected scenario
     * would be capped against itself and its receipts subtracted twice. The
     * claim-level ancillary draw (Estimate__c blank) is NOT added back: it is
     * a real, separate use of the term (Osama, 2026-10-13).
     *
     * Each line is capped independently, the same as the live mirror in
     * repairPriceScenarios.approvedReceipt. Readers: recalculateRollups
     * (Reimbursement_Total__c), recalculateClaimTotalProfit, createWorkOrder
     * (the Reimbursement claim line items) and WorkOrderPDFController.
     */
    public static Map<Id, List<ApprovedReimbursement>> getApprovedReimbursements(Set<Id> estimateIds) {
        Map<Id, List<ApprovedReimbursement>> out = new Map<Id, List<ApprovedReimbursement>>();
        if (estimateIds == null || estimateIds.isEmpty()) return out;

        List<Benefit_Usage__c> usages = [
            SELECT Id, Estimate__c, Benefit_Balance__c, Benefit_Balance__r.Benefit_Type__c,
                   Benefit_Balance__r.Remaining__c, Amount_Used__c, Counts_Toward_Balance__c
            FROM Benefit_Usage__c
            WHERE Estimate__c IN :estimateIds
            WITH USER_MODE
            ORDER BY CreatedDate ASC, Id ASC
        ];

        Map<String, Decimal> ownCounted = new Map<String, Decimal>();
        for (Benefit_Usage__c u : usages) {
            if (u.Counts_Toward_Balance__c != true) continue;
            String key = u.Estimate__c + '|' + u.Benefit_Balance__c;
            ownCounted.put(key, nz(ownCounted.get(key)) + nz(u.Amount_Used__c));
        }

        for (Benefit_Usage__c u : usages) {
            String key = u.Estimate__c + '|' + u.Benefit_Balance__c;
            Decimal room = Math.max(0, nz(u.Benefit_Balance__r?.Remaining__c) + nz(ownCounted.get(key)));
            ApprovedReimbursement a = new ApprovedReimbursement();
            a.usageId     = u.Id;
            a.estimateId  = u.Estimate__c;
            a.balanceId   = u.Benefit_Balance__c;
            a.benefitType = u.Benefit_Balance__r?.Benefit_Type__c;
            a.receipts    = nz(u.Amount_Used__c);
            a.approved    = Math.max(0, Math.min(a.receipts, room));
            a.leftOnTerm  = Math.max(0, room - a.approved);
            a.over        = a.receipts - a.approved;
            if (!out.containsKey(u.Estimate__c)) out.put(u.Estimate__c, new List<ApprovedReimbursement>());
            out.get(u.Estimate__c).add(a);
        }
        return out;
    }

    private static Decimal approvedTotal(List<ApprovedReimbursement> lines) {
        Decimal total = 0;
        if (lines != null) for (ApprovedReimbursement a : lines) total += a.approved;
        return total;
    }

    /**
     * Everything the Manage Estimates page needs, in ONE call: the claim bar,
     * the claim-level ancillary benefits, and every scenario with its full
     * Part / Labour / Shop Supply / reimbursement child list.
     *
     * Deliberately NOT cacheable, same reason as getEstimatesForClaim: the
     * page must show the result of its own just-completed save.
     */
    @AuraEnabled
    public static ManageEstimatesData getManageEstimatesData(Id claimId) {
        ManageEstimatesData d = new ManageEstimatesData();

        Claim__c claim = [
            SELECT Id, Name, Vehicle_Description__c,
                   Application__r.Name, Customer_Name__c, Customer_Address__c,
                   Customer_Phone__c, Customer_Email__c,
                   Vehicle_Identification_Number_VIN__c,
                   Current_Odometer__c, Current_Odometer_Unit__c,
                   Application_Package__r.Per_Claim_Limit__c,
                   Application_Package__r.Deductible__c
            FROM Claim__c WHERE Id = :claimId
            WITH USER_MODE
        ];
        d.claimNumber = claim.Name;
        // Vehicle_Description__c is a formula field composing year, make, model
        // and trim. It replaced a String.join of year, make and model here,
        // which also silently dropped the trim even though the preview was
        // labelled Year/Make/Model/Trim. One definition, editable in
        // configuration: Osama's rule, 2026-10-08.
        d.vehicle    = claim.Vehicle_Description__c;

        // TASK-050. The work order header, read rather than typed.
        d.applicationNumber = claim.Application__r?.Name;
        d.customerName      = claim.Customer_Name__c;
        d.customerAddress   = claim.Customer_Address__c;
        d.customerPhone     = claim.Customer_Phone__c;
        d.customerEmail     = claim.Customer_Email__c;
        d.vin               = claim.Vehicle_Identification_Number_VIN__c;
        d.odometer          = claim.Current_Odometer__c;
        d.odometerUnit      = claim.Current_Odometer_Unit__c;
        d.cap        = claim.Application_Package__r?.Per_Claim_Limit__c;
        d.deductible = claim.Application_Package__r?.Deductible__c;
        d.benefits   = getBenefitBalancesForClaim(claimId);

        d.paymentMethodOptions = new List<ValueOption>();
        for (Schema.PicklistEntry p : Estimate__c.Reimbursement_Payment_Method__c.getDescribe().getPicklistValues()) {
            if (!p.isActive()) continue;
            ValueOption o = new ValueOption();
            o.value = p.getValue(); o.label = p.getLabel();
            d.paymentMethodOptions.add(o);
        }

        d.shops = new List<ShopOption>();
        for (Repair_Shop__c s : [
            SELECT Id, Name, Address__c, Street__c, City__c, State_Province__c, Postal_Code__c,
                   Country__c, Region__c, Payment_Method__c, Phone__c,
                   Labour_Rate_On_File__c, Tax_Percentage__c
            FROM Repair_Shop__c
            WHERE Unauthorized__c = false
            WITH USER_MODE
            ORDER BY Name
        ]) {
            ShopOption o = new ShopOption();
            o.id = s.Id; o.name = s.Name; o.phone = s.Phone__c;
            o.city = s.City__c; o.region = s.Region__c;
            o.address = composeAddress(s);
            o.postedRate = s.Labour_Rate_On_File__c; o.taxPercent = s.Tax_Percentage__c;
            o.paysBy = s.Payment_Method__c == null ? null : s.Payment_Method__c.replace(';', ', ');
            d.shops.add(o);
        }

        d.suppliers = new List<NamedOption>();
        for (Account a : getSupplierAccounts()) {
            NamedOption o = new NamedOption();
            o.id = a.Id; o.name = a.Name;
            d.suppliers.add(o);
        }

        List<Estimate__c> estimates = [
            SELECT Id, Estimate_Name__c, Repair_Shop__c, Repair_Shop__r.Name,
                   Network__c, Claim_Type__c, Tax_Percentage__c, Deductable__c, Is_Selected__c,
                   Reimbursement_Payment_Method__c, Reimbursement_Expected_Payment_Date__c
            FROM Estimate__c
            WHERE Claim__c = :claimId
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ];
        d.scenarios = new List<ScenarioRow>();
        if (estimates.isEmpty()) return d;

        Set<Id> estimateIds = new Map<Id, Estimate__c>(estimates).keySet();
        Map<Id, List<PartRow>> partsByEstimate     = new Map<Id, List<PartRow>>();
        Map<Id, List<LabourRow>> labourByEstimate  = new Map<Id, List<LabourRow>>();
        Map<Id, List<SupplyRow>> suppliesByEstimate= new Map<Id, List<SupplyRow>>();
        Map<Id, List<ReimbursementRow>> reimbByEstimate = new Map<Id, List<ReimbursementRow>>();
        for (Id eid : estimateIds) {
            partsByEstimate.put(eid, new List<PartRow>());
            labourByEstimate.put(eid, new List<LabourRow>());
            suppliesByEstimate.put(eid, new List<SupplyRow>());
            reimbByEstimate.put(eid, new List<ReimbursementRow>());
        }

        for (Part__c p : [
            SELECT Id, Estimate__c, Part_Name__c, Part_Code__c, Part_Category__c, Part_Type__c,
                   Supplier__c, Supplier__r.Name, Stock_Number__c, KMS__c, Quantity__c,
                   Part_Cost_Wholesale__c, Markup_Type__c, Markup_Value__c, Price__c, Core_Charge__c,
                   Warranty_Source__c, Included_Warranty__c, Included_Warranty_Covers__c,
                   Included_Warranty_Months__c, Included_Warranty_Km__c,
                   Extended_Warranty__c, Extended_Warranty_Months__c, Extended_Warranty_Km__c,
                   Extended_Warranty_Cost__c, Extended_Warranty_Markup_Type__c,
                   Extended_Warranty_Markup_Value__c, Extended_Warranty_Retail__c, Warranty_Notes__c
            FROM Part__c WHERE Estimate__c IN :estimateIds
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ]) {
            PartRow r = new PartRow();
            r.id = p.Id; r.name = p.Part_Name__c; r.partNumber = p.Part_Code__c;
            r.category = p.Part_Category__c; r.condition = p.Part_Type__c;
            r.supplierId = p.Supplier__c; r.supplierName = p.Supplier__r?.Name;
            r.stockNumber = p.Stock_Number__c; r.kms = p.KMS__c; r.qty = p.Quantity__c;
            r.unitWholesale = p.Part_Cost_Wholesale__c;
            r.markupType = p.Markup_Type__c; r.markupValue = p.Markup_Value__c;
            r.unitRetail = p.Price__c; r.coreCharge = p.Core_Charge__c;
            r.warrantySource = p.Warranty_Source__c;
            r.includedWarranty = p.Included_Warranty__c;
            r.includedWarrantyCovers = p.Included_Warranty_Covers__c;
            r.includedWarrantyMonths = p.Included_Warranty_Months__c;
            r.includedWarrantyKm = p.Included_Warranty_Km__c;
            r.extendedWarranty = p.Extended_Warranty__c;
            r.extendedWarrantyMonths = p.Extended_Warranty_Months__c;
            r.extendedWarrantyKm = p.Extended_Warranty_Km__c;
            r.extendedWarrantyCost = p.Extended_Warranty_Cost__c;
            r.extendedWarrantyMarkupType = p.Extended_Warranty_Markup_Type__c;
            r.extendedWarrantyMarkupValue = p.Extended_Warranty_Markup_Value__c;
            r.extendedWarrantyRetail = p.Extended_Warranty_Retail__c;
            r.warrantyNotes = p.Warranty_Notes__c;
            partsByEstimate.get(p.Estimate__c).add(r);
        }

        for (Service__c s : [
            SELECT Id, Estimate__c, Item_Desription__c, Repair_Time_EST__c, Wholesale_Labour_Rate_HR__c,
                   Wholesale__c, Repair_Time_Adj__c, Retail_Labour_Rate__c, Retail__c,
                   Labour_Guide_Time_Mitchell__c, Labour_Guide_Time_All_Data__c
            FROM Service__c WHERE Estimate__c IN :estimateIds
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ]) {
            LabourRow r = new LabourRow();
            r.id = s.Id; r.description = s.Item_Desription__c;
            r.wholesaleHours = s.Repair_Time_EST__c; r.wholesaleRate = s.Wholesale_Labour_Rate_HR__c;
            r.wholesaleTotal = s.Wholesale__c;
            r.retailHours = s.Repair_Time_Adj__c; r.retailRate = s.Retail_Labour_Rate__c;
            r.retailTotal = s.Retail__c;
            r.guideMitchell = s.Labour_Guide_Time_Mitchell__c;
            r.guideAllData = s.Labour_Guide_Time_All_Data__c;
            labourByEstimate.get(s.Estimate__c).add(r);
        }

        for (Shop_Supply__c x : [
            SELECT Id, Estimate__c, Item_Description__c, Cost__c, Markup_Type__c, Markup_Value__c, Price__c
            FROM Shop_Supply__c WHERE Estimate__c IN :estimateIds
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ]) {
            SupplyRow r = new SupplyRow();
            r.id = x.Id; r.description = x.Item_Description__c; r.wholesaleCost = x.Cost__c;
            r.markupType = x.Markup_Type__c; r.markupValue = x.Markup_Value__c; r.retailPrice = x.Price__c;
            suppliesByEstimate.get(x.Estimate__c).add(r);
        }

        for (Benefit_Usage__c u : [
            SELECT Id, Estimate__c, Benefit_Balance__c, Benefit_Balance__r.Benefit_Type__c, Amount_Used__c,
                   Counts_Toward_Balance__c
            FROM Benefit_Usage__c WHERE Estimate__c IN :estimateIds
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ]) {
            ReimbursementRow r = new ReimbursementRow();
            r.id = u.Id; r.benefitBalanceId = u.Benefit_Balance__c;
            r.benefitType = u.Benefit_Balance__r?.Benefit_Type__c;
            r.receiptAmount = u.Amount_Used__c;
            r.countedAmount = u.Counts_Toward_Balance__c == true ? u.Amount_Used__c : 0;
            reimbByEstimate.get(u.Estimate__c).add(r);
        }

        for (Estimate__c e : estimates) {
            ScenarioRow r = new ScenarioRow();
            r.id = e.Id; r.name = e.Estimate_Name__c;
            r.repairShopId = e.Repair_Shop__c; r.repairShopName = e.Repair_Shop__r?.Name;
            r.network = e.Network__c; r.claimType = e.Claim_Type__c;
            r.taxPercent = e.Tax_Percentage__c; r.deductible = e.Deductable__c;
            r.isSelected = e.Is_Selected__c;
            r.paymentMethod = e.Reimbursement_Payment_Method__c;
            r.expectedPaymentDate = e.Reimbursement_Expected_Payment_Date__c;
            r.parts = partsByEstimate.get(e.Id);
            r.labour = labourByEstimate.get(e.Id);
            r.supplies = suppliesByEstimate.get(e.Id);
            r.reimbursements = reimbByEstimate.get(e.Id);
            d.scenarios.add(r);
        }
        return d;
    }

    /**
     * Saves every scenario on the claim, children and all, in one transaction.
     *
     * Deliberately NOT a call to saveEstimates above: that method's whole
     * model is "scalars on the Estimate drive one child of each type," which
     * is exactly the assumption TASK-047 removes. saveEstimates stays in place
     * untouched for the older grid and its tests.
     *
     * deletedChildIds carries ids removed in the UI since the page loaded,
     * across all three child types plus reimbursement lines, so a part the
     * agent removed is actually deleted rather than silently left behind.
     */
    @AuraEnabled
    public static ManageEstimatesData saveManageEstimates(
            Id claimId, List<ScenarioRow> scenarios, List<Id> deletedEstimateIds, List<Id> deletedChildIds) {
        Savepoint sp = Database.setSavepoint();
        try {
            if (deletedEstimateIds != null && !deletedEstimateIds.isEmpty()) {
                deleteSecured([SELECT Id FROM Benefit_Usage__c WHERE Estimate__c IN :deletedEstimateIds WITH USER_MODE]);
                deleteSecured([SELECT Id FROM Part__c          WHERE Estimate__c IN :deletedEstimateIds WITH USER_MODE]);
                deleteSecured([SELECT Id FROM Service__c       WHERE Estimate__c IN :deletedEstimateIds WITH USER_MODE]);
                deleteSecured([SELECT Id FROM Shop_Supply__c   WHERE Estimate__c IN :deletedEstimateIds WITH USER_MODE]);
                deleteSecured([SELECT Id FROM Estimate__c      WHERE Id IN :deletedEstimateIds          WITH USER_MODE]);
            }
            if (deletedChildIds != null && !deletedChildIds.isEmpty()) {
                deleteSecured([SELECT Id FROM Part__c        WHERE Id IN :deletedChildIds WITH USER_MODE]);
                deleteSecured([SELECT Id FROM Service__c     WHERE Id IN :deletedChildIds WITH USER_MODE]);
                deleteSecured([SELECT Id FROM Shop_Supply__c WHERE Id IN :deletedChildIds WITH USER_MODE]);
                deleteSecured([SELECT Id FROM Benefit_Usage__c WHERE Id IN :deletedChildIds WITH USER_MODE]);
            }
            if (scenarios == null || scenarios.isEmpty()) return getManageEstimatesData(claimId);

            // ---- 1. the Estimate__c rows themselves ----
            Set<Id> shopIds = new Set<Id>();
            for (ScenarioRow s : scenarios) if (s.repairShopId != null) shopIds.add(s.repairShopId);
            Map<Id, Repair_Shop__c> shopsById = new Map<Id, Repair_Shop__c>([
                SELECT Id, Labour_Rate_On_File__c, Tax_Percentage__c
                FROM Repair_Shop__c WHERE Id IN :shopIds
                WITH USER_MODE
            ]);

            List<Estimate__c> toInsert = new List<Estimate__c>();
            List<Estimate__c> toUpdate = new List<Estimate__c>();
            List<ScenarioRow> newRows = new List<ScenarioRow>();
            Integer skippedEmpty = 0;
            for (ScenarioRow s : scenarios) {
                Decimal taxPct = s.taxPercent != null
                    ? s.taxPercent
                    : (s.repairShopId != null ? shopsById.get(s.repairShopId)?.Tax_Percentage__c : null);
                // TASK-051. Payment details only mean something on a
                // reimbursement, so a card switched back to Repair drops them
                // rather than carrying hidden values.
                Boolean isReimb = s.claimType == 'Reimbursement Only';
                String payMethod = isReimb ? s.paymentMethod : null;
                Date payDate = isReimb ? s.expectedPaymentDate : null;
                if (s.id == null) {
                    // Osama, 2026-10-07: a scenario the agent never filled in
                    // must not become an Estimate__c. Three blank estimates
                    // (E-0053, E-0056, E-0057) were inserted on CL ID - 00054
                    // exactly this way: every scalar null and no child rows.
                    // recalculateRollups then stamped a deductible and a
                    // negative customer-pays onto them, so they looked like
                    // real estimates in the related list. Refusing the insert
                    // here is authoritative - it holds for a stale browser
                    // bundle and for any future caller, not just this LWC.
                    if (isEmptyScenario(s)) { skippedEmpty++; continue; }
                    toInsert.add(new Estimate__c(
                        Claim__c         = claimId,
                        Estimate_Name__c = s.name,
                        Repair_Shop__c   = s.repairShopId,
                        Network__c       = s.network,
                        Claim_Type__c    = s.claimType,
                        Tax_Percentage__c= taxPct,
                        Deductable__c    = s.deductible,
                        Reimbursement_Payment_Method__c        = payMethod,
                        Reimbursement_Expected_Payment_Date__c = payDate
                    ));
                    newRows.add(s);
                } else {
                    // Claim__c is a non-reparentable master-detail. Never resend
                    // it on an update, even unchanged: USER_MODE refuses the
                    // whole DML as an edit to a structurally uneditable field.
                    toUpdate.add(new Estimate__c(
                        Id               = s.id,
                        Estimate_Name__c = s.name,
                        Repair_Shop__c   = s.repairShopId,
                        Network__c       = s.network,
                        Claim_Type__c    = s.claimType,
                        Tax_Percentage__c= taxPct,
                        Deductable__c    = s.deductible,
                        Reimbursement_Payment_Method__c        = payMethod,
                        Reimbursement_Expected_Payment_Date__c = payDate
                    ));
                }
            }
            insertSecured(toInsert);
            updateSecured(toUpdate);
            // insertSecured populates Id in order, so the new rows can now be
            // matched back to their payload for the child save below.
            for (Integer i = 0; i < toInsert.size(); i++) newRows[i].id = toInsert[i].Id;

            // ---- 2. the children ----
            saveScenarioChildren(claimId, scenarios);

            // ---- 3. rollups and pricing ----
            Set<Id> estimateIds = new Set<Id>();
            for (ScenarioRow s : scenarios) if (s.id != null) estimateIds.add(s.id);
            recalculateRollups(claimId, estimateIds);

            // ---- 4. selection ----
            Id selectedId = null;
            for (ScenarioRow s : scenarios) if (s.isSelected == true) selectedId = s.id;
            if (selectedId != null) markSelected(selectedId, claimId);

            recalculateClaimTotalProfit(claimId);
            ManageEstimatesData out = getManageEstimatesData(claimId);
            out.skippedEmptyScenarios = skippedEmpty;
            return out;
        } catch (Exception ex) {
            Database.rollback(sp);
            // AuraHandledException.getMessage() returns the useless
            // "Script-thrown exception" unless setMessage is called explicitly,
            // which hides the real cause from the LWC and from test output
            // alike. saveBenefitUsage already does this correctly; this does
            // now too. Type and line number are included because a failed save
            // here is almost always a field-level or DML problem worth naming.
            String detail = 'Could not save estimates: ' + ex.getTypeName()
                + ': ' + ex.getMessage() + ' (line ' + ex.getLineNumber() + ')';
            System.debug(LoggingLevel.ERROR, detail + '\n' + ex.getStackTraceString());
            AuraHandledException wrapped = new AuraHandledException(detail);
            wrapped.setMessage(detail);
            throw wrapped;
        }
    }

    /**
     * JSON entry point for the Manage Estimates screen, and the one the LWC
     * actually calls.
     *
     * Why this exists. Osama, 2026-10-08: the screen sent a filled-in scenario
     * and Apex received a ScenarioRow with every field null and no child rows
     * at all. Proven both ways in one run: the LWC's own isEmptyScenarioRow
     * judged the card NOT empty and sent it, while isEmptyScenario here judged
     * the very same row empty. The debug log confirmed it, showing
     * `scenarios|[{}]` and not one PartRow or LabourRow constructed during
     * deserialization. The data was being lost by the Aura layer that maps
     * LWC objects onto a custom Apex type, which does not reliably enumerate
     * objects originating from an LWC reactive proxy (`@track`). It fails
     * silently, which is why the browser console looked correct: JSON.stringify
     * reads through the proxy traps and is unaffected.
     *
     * Passing the payload as a JSON string removes that layer from the path
     * entirely, which is the fix. One thing it does NOT give us, contrary to
     * what this comment first claimed: JSON.deserialize silently IGNORES
     * properties with no matching Apex field, it does not throw on them. So
     * this is no defence against the LWC payload and these wrapper classes
     * drifting apart. A renamed property would simply arrive null again. What
     * guards that is saveFromJsonRoundTripsTheScreenPayload, which pins the
     * exact payload shape, plus isEmptyScenario refusing a contentless row.
     * It does throw on malformed JSON and on a value that cannot convert to
     * the field's type, and the catch below names those.
     *
     * The typed saveManageEstimates below is unchanged and still carries all
     * the behaviour and every test.
     */
    @AuraEnabled
    public static ManageEstimatesData saveManageEstimatesFromJson(
            Id claimId, String scenariosJson, List<Id> deletedEstimateIds, List<Id> deletedChildIds) {
        List<ScenarioRow> rows;
        try {
            rows = String.isBlank(scenariosJson)
                ? new List<ScenarioRow>()
                : (List<ScenarioRow>) JSON.deserialize(scenariosJson, List<ScenarioRow>.class);
        } catch (Exception ex) {
            // Never fail silently here. A shape mismatch between the LWC
            // payload and these wrapper classes is a developer error, and it
            // must name itself rather than reappear as an empty estimate.
            String detail = 'Manage Estimates could not read the data the screen sent: '
                + ex.getTypeName() + ': ' + ex.getMessage();
            System.debug(LoggingLevel.ERROR, detail + '\nPayload was: ' + scenariosJson);
            AuraHandledException wrapped = new AuraHandledException(detail);
            wrapped.setMessage(detail);
            throw wrapped;
        }
        return saveManageEstimates(claimId, rows, deletedEstimateIds, deletedChildIds);
    }

    /**
     * True when a payload row carries nothing worth saving.
     *
     * Network__c and Claim_Type__c are deliberately NOT consulted. The LWC
     * seeds both with a default the moment a card is added ('In-Network' and
     * 'Repair'), so counting them would make every row look filled in and
     * defeat the guard entirely. Same reasoning for the estimate name when it
     * still holds the generated "Repair Shop 1 - Option A" placeholder: that
     * is a suggestion, not content, so a row carrying only the placeholder and
     * nothing else is still empty.
     *
     * The LWC also always seeds one blank labour row, so an untouched scenario
     * arrives with labour.size() == 1 and every field on it null. That counts
     * as empty, which is why labour is inspected field by field rather than by
     * list size the way parts and supplies are.
     */
    private static Boolean isEmptyScenario(ScenarioRow s) {
        if (String.isNotBlank(s.name) && !isPlaceholderName(s.name)) return false;
        if (s.repairShopId != null || s.taxPercent != null || s.deductible != null) return false;
        if (s.parts != null && !s.parts.isEmpty()) return false;
        if (s.supplies != null && !s.supplies.isEmpty()) return false;
        if (s.reimbursements != null && !s.reimbursements.isEmpty()) return false;
        if (s.labour != null) {
            for (LabourRow l : s.labour) {
                if (String.isNotBlank(l.description)
                        || l.wholesaleHours != null || l.wholesaleRate != null
                        || l.retailHours != null   || l.retailRate != null) {
                    return false;
                }
            }
        }
        return true;
    }

    /** Matches the name handleAddScenario generates: "Repair Shop 2 - Option B". */
    private static Boolean isPlaceholderName(String name) {
        return Pattern.matches('(?i)^repair shop \\d+ - option [a-z]$', name.trim());
    }

    /**
     * Upserts every Part__c / Service__c / Shop_Supply__c / reimbursement row
     * the page sent, many per Estimate. Retail figures are computed here with
     * ClaimPricingService.applyMarkup rather than trusted from the browser, so
     * a tampered or stale payload can never write a price the markup rule does
     * not produce.
     *
     * Bulk-safe: two DML statements per child type regardless of how many
     * scenarios or lines are being saved.
     */
    private static void saveScenarioChildren(Id claimId, List<ScenarioRow> scenarios) {
        List<Part__c> partIns = new List<Part__c>(), partUpd = new List<Part__c>();
        List<Service__c> svcIns = new List<Service__c>(), svcUpd = new List<Service__c>();
        List<Shop_Supply__c> supIns = new List<Shop_Supply__c>(), supUpd = new List<Shop_Supply__c>();
        List<Benefit_Usage__c> benIns = new List<Benefit_Usage__c>(), benUpd = new List<Benefit_Usage__c>();

        for (ScenarioRow s : scenarios) {
            if (s.id == null) continue;
            Boolean isReimb = s.claimType == 'Reimbursement Only';

            for (PartRow p : safeParts(s)) {
                Decimal unitRetail = ClaimPricingService.applyMarkup(p.unitWholesale, p.markupType, p.markupValue);
                Decimal qty = nz(p.qty) == 0 ? 1 : p.qty;
                Decimal extRetail = p.extendedWarranty == true
                    ? ClaimPricingService.applyMarkup(p.extendedWarrantyCost, p.extendedWarrantyMarkupType, p.extendedWarrantyMarkupValue)
                    : 0;
                Part__c rec = new Part__c(
                    Part_Name__c                      = p.name,
                    Part_Code__c                      = p.partNumber,
                    Part_Category__c                  = p.category,
                    Part_Type__c                      = p.condition,
                    Supplier__c                       = p.supplierId,
                    Stock_Number__c                   = p.stockNumber,
                    KMS__c                            = p.kms,
                    Quantity__c                       = qty,
                    Part_Cost_Wholesale__c            = p.unitWholesale,
                    Markup_Type__c                    = p.markupType,
                    Markup_Value__c                   = p.markupValue,
                    Price__c                          = unitRetail,
                    Part_Cost__c                      = qty * nz(p.unitWholesale),
                    Core_Charge__c                    = p.coreCharge,
                    Warranty_Source__c                = p.warrantySource,
                    Included_Warranty__c              = p.includedWarranty == true,
                    Included_Warranty_Covers__c       = p.includedWarrantyCovers,
                    Included_Warranty_Months__c       = p.includedWarrantyMonths,
                    Included_Warranty_Km__c           = p.includedWarrantyKm,
                    Extended_Warranty__c              = p.extendedWarranty == true,
                    Extended_Warranty_Months__c       = p.extendedWarrantyMonths,
                    Extended_Warranty_Km__c           = p.extendedWarrantyKm,
                    Extended_Warranty_Cost__c         = p.extendedWarrantyCost,
                    Extended_Warranty_Markup_Type__c  = p.extendedWarrantyMarkupType,
                    Extended_Warranty_Markup_Value__c = p.extendedWarrantyMarkupValue,
                    Extended_Warranty_Retail__c       = extRetail
                );
                rec.Warranty_Notes__c = p.warrantyNotes;
                if (p.id == null) {
                    rec.Estimate__c = s.id;
                    rec.Claim__c = claimId;
                    rec.Repair_Shop__c = s.repairShopId;
                    // HARD RULE, carried over from syncEstimateChildren:
                    // Export_to_Work_Order__c is never set true here. Setting it
                    // would let the dormant legacy WorkOrderCreatorController
                    // pick these up and build a second, conflicting Work_Order__c.
                    partIns.add(rec);
                } else {
                    rec.Id = p.id;
                    partUpd.add(rec);
                }
            }

            for (LabourRow l : safeLabour(s)) {
                Service__c rec = new Service__c(
                    Item_Desription__c           = l.description,
                    Repair_Time_EST__c           = l.wholesaleHours,
                    Wholesale_Labour_Rate_HR__c  = l.wholesaleRate,
                    Wholesale__c                 = nz(l.wholesaleHours) * nz(l.wholesaleRate),
                    Repair_Time_Adj__c           = l.retailHours,
                    Retail_Labour_Rate__c        = l.retailRate,
                    Retail__c                    = nz(l.retailHours) * nz(l.retailRate),
                    Labour_Guide_Time_Mitchell__c= l.guideMitchell,
                    Labour_Guide_Time_All_Data__c= l.guideAllData
                );
                if (l.id == null) {
                    rec.Estimate__c = s.id;
                    rec.Repair_Shop__c = s.repairShopId;
                    svcIns.add(rec);
                } else {
                    rec.Id = l.id;
                    svcUpd.add(rec);
                }
            }

            for (SupplyRow x : safeSupplies(s)) {
                // Item_Name__c is REQUIRED on Shop_Supply__c (the only required
                // field across the three children), so it can never be left
                // blank. The design only gives the agent one supply text box,
                // which maps to Item_Description__c, so the name is derived
                // from it and falls back to the same literal the older
                // syncEstimateChildren uses. Truncated to the field's 255,
                // because Item_Description__c is a TextArea and can be longer.
                String supplyName = 'Shop Supplies';
                if (String.isNotBlank(x.description)) {
                    supplyName = x.description.length() > 255
                        ? x.description.substring(0, 255)
                        : x.description;
                }
                Shop_Supply__c rec = new Shop_Supply__c(
                    Item_Name__c        = supplyName,
                    Item_Description__c = x.description,
                    Cost__c             = x.wholesaleCost,
                    Markup_Type__c      = x.markupType,
                    Markup_Value__c     = x.markupValue,
                    Price__c            = ClaimPricingService.applyMarkup(x.wholesaleCost, x.markupType, x.markupValue)
                );
                if (x.id == null) {
                    rec.Estimate__c = s.id;
                    rec.Repair_Shop__c = s.repairShopId;
                    supIns.add(rec);
                } else {
                    rec.Id = x.id;
                    supUpd.add(rec);
                }
            }

            // Reimbursement lines belong to ONE scenario, so they carry
            // Estimate__c. Claim-level ancillary benefits leave it blank and
            // are saved by saveBenefitUsage instead. Only a Reimbursement Only
            // scenario keeps them, so flipping a scenario back to Repair drops
            // them rather than quietly reimbursing on a repair claim.
            //
            // Counts_Toward_Balance__c is the scenario's own Use flag.
            // Benefit_Balance__c.Used_To_Date__c filters its roll-up on it, so
            // a receipt typed into a competing scenario is recorded but does
            // NOT eat the customer's remaining benefit for the term. Because
            // every scenario is rewritten on every save, a scenario losing Use
            // automatically flips its own lines back off.
            if (isReimb) {
                Boolean counts = s.isSelected == true;
                for (ReimbursementRow r : safeReimbursements(s)) {
                    if (r.benefitBalanceId == null) continue;
                    if (r.id == null) {
                        benIns.add(new Benefit_Usage__c(
                            Benefit_Balance__c       = r.benefitBalanceId,
                            Claim__c                 = claimId,
                            Estimate__c              = s.id,
                            Amount_Used__c           = r.receiptAmount,
                            Counts_Toward_Balance__c = counts,
                            Date__c                  = Date.today()
                        ));
                    } else {
                        // Benefit_Balance__c is non-reparentable master-detail:
                        // same rule as saveBenefitUsage, never resend it.
                        benUpd.add(new Benefit_Usage__c(
                            Id                       = r.id,
                            Amount_Used__c           = r.receiptAmount,
                            Claim__c                 = claimId,
                            Estimate__c              = s.id,
                            Counts_Toward_Balance__c = counts
                        ));
                    }
                }
            }
        }

        insertSecured(partIns);  updateSecured(partUpd);
        insertSecured(svcIns);   updateSecured(svcUpd);
        insertSecured(supIns);   updateSecured(supUpd);
        insertSecured(benIns);   updateSecured(benUpd);
    }

    /**
     * One display address from the structured parts, falling back to the
     * legacy single-line Address__c when none of them are populated.
     *
     * The fallback matters: Address__c is the only address the org holds
     * today and it still backs RepairShopIntakeFormController, the customer
     * e-mail flow and Claim__c.Repair_Shop_Address__c, so it cannot be
     * dropped. Shops keep showing their address correctly whether or not
     * anyone has filled the structured fields in yet.
     */
    private static String composeAddress(Repair_Shop__c s) {
        List<String> bits = new List<String>();
        if (String.isNotBlank(s.Street__c))         bits.add(s.Street__c.trim());
        if (String.isNotBlank(s.City__c))           bits.add(s.City__c.trim());
        if (String.isNotBlank(s.State_Province__c)) bits.add(s.State_Province__c.trim());
        if (String.isNotBlank(s.Postal_Code__c))    bits.add(s.Postal_Code__c.trim());
        if (String.isNotBlank(s.Country__c))        bits.add(s.Country__c.trim());
        return bits.isEmpty() ? s.Address__c : String.join(bits, ', ');
    }

    private static List<PartRow> safeParts(ScenarioRow s) {
        return s.parts == null ? new List<PartRow>() : s.parts;
    }
    private static List<LabourRow> safeLabour(ScenarioRow s) {
        return s.labour == null ? new List<LabourRow>() : s.labour;
    }
    private static List<SupplyRow> safeSupplies(ScenarioRow s) {
        return s.supplies == null ? new List<SupplyRow>() : s.supplies;
    }
    private static List<ReimbursementRow> safeReimbursements(ScenarioRow s) {
        return s.reimbursements == null ? new List<ReimbursementRow>() : s.reimbursements;
    }

    /**
     * Rolls every child back up onto the Estimate__c scalars and stamps the
     * TASK-047 scenario figures beside them.
     *
     * This is what keeps decision 1 true: Parts_Cost__c, Labour_Cost__c,
     * Shop_Supplies__c, Retail_Price__c, Wholesale_Cost__c, Coverage_Applied__c,
     * Customer_Pays__c, Profit_Loss__c and the rest all keep existing and keep
     * meaning what they have always meant, so the nine Work_Order__c formula
     * fields, claimsWorksheet, buildClaimLineItems and both screen flows carry
     * on working untouched. What changes is HOW the numbers are reached: from
     * the children, through calculateScenario, instead of from the Estimate's
     * own scalars through calculate().
     *
     * Re-queries the children rather than trusting the caller's payload, for
     * the same reason syncEstimateChildren does: Apex throws reading ANY
     * unqueried field off a partial SOQL result, not just the one you assumed
     * would be missing.
     */
    private static void recalculateRollups(Id claimId, Set<Id> estimateIds) {
        if (estimateIds == null || estimateIds.isEmpty()) return;

        Claim__c claim = [
            SELECT Application_Package__r.Per_Claim_Limit__c,
                   Application_Package__r.Deductible__c
            FROM Claim__c WHERE Id = :claimId
            WITH USER_MODE
        ];
        Decimal claimCap = claim.Application_Package__r?.Per_Claim_Limit__c;
        Decimal claimDed = claim.Application_Package__r?.Deductible__c;

        // Claim-level approved ancillary benefits, shared by every scenario,
        // exactly as the design intends ("set benefits once"). Reimbursement
        // lines are excluded here because they are scenario-specific.
        Decimal benefitsApproved = 0;
        for (Benefit_Usage__c u : [
            SELECT Amount_Used__c FROM Benefit_Usage__c
            WHERE Claim__c = :claimId AND Estimate__c = null
            WITH USER_MODE
        ]) {
            benefitsApproved += nz(u.Amount_Used__c);
        }

        Map<Id, Estimate__c> estimates = new Map<Id, Estimate__c>([
            SELECT Id, Claim_Type__c, Tax_Percentage__c, Deductable__c, Repair_Shop__r.Tax_Percentage__c
            FROM Estimate__c WHERE Id IN :estimateIds
            WITH USER_MODE
        ]);

        Map<Id, Decimal[]> agg = new Map<Id, Decimal[]>();
        // [0] parts wholesale, [1] parts retail, [2] warranty wholesale,
        // [3] warranty retail, [4] labour wholesale, [5] labour retail,
        // [6] supplies wholesale, [7] supplies retail, [8] core, [9] reimbursement
        for (Id eid : estimates.keySet()) {
            agg.put(eid, new List<Decimal>{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 });
        }

        for (Part__c p : [
            SELECT Estimate__c, Quantity__c, Part_Cost_Wholesale__c, Price__c, Core_Charge__c,
                   Extended_Warranty__c, Extended_Warranty_Cost__c, Extended_Warranty_Retail__c
            FROM Part__c WHERE Estimate__c IN :estimateIds
            WITH USER_MODE
        ]) {
            Decimal[] a = agg.get(p.Estimate__c);
            Decimal q = nz(p.Quantity__c) == 0 ? 1 : p.Quantity__c;
            a[0] += q * nz(p.Part_Cost_Wholesale__c);
            a[1] += q * nz(p.Price__c);
            a[8] += q * nz(p.Core_Charge__c);
            if (p.Extended_Warranty__c == true) {
                a[2] += nz(p.Extended_Warranty_Cost__c);
                a[3] += nz(p.Extended_Warranty_Retail__c);
            }
        }
        for (Service__c s : [
            SELECT Estimate__c, Wholesale__c, Retail__c
            FROM Service__c WHERE Estimate__c IN :estimateIds
            WITH USER_MODE
        ]) {
            Decimal[] a = agg.get(s.Estimate__c);
            a[4] += nz(s.Wholesale__c);
            a[5] += nz(s.Retail__c);
        }
        for (Shop_Supply__c x : [
            SELECT Estimate__c, Cost__c, Price__c
            FROM Shop_Supply__c WHERE Estimate__c IN :estimateIds
            WITH USER_MODE
        ]) {
            Decimal[] a = agg.get(x.Estimate__c);
            a[6] += nz(x.Cost__c);
            a[7] += nz(x.Price__c);
        }
        // TASK-051: the APPROVED amount, not the raw receipt. This used to sum
        // Amount_Used__c, so a receipt over what was left on the term was
        // saved in full while the Manage Estimates preview showed it capped.
        Map<Id, List<ApprovedReimbursement>> approvedByEstimate = getApprovedReimbursements(estimates.keySet());
        for (Id eid : approvedByEstimate.keySet()) {
            if (agg.containsKey(eid)) agg.get(eid)[9] = approvedTotal(approvedByEstimate.get(eid));
        }

        List<Estimate__c> toStamp = new List<Estimate__c>();
        for (Id eid : estimates.keySet()) {
            Estimate__c e = estimates.get(eid);
            Decimal[] a = agg.get(eid);
            Boolean isReimb = e.Claim_Type__c == 'Reimbursement Only';

            ClaimPricingService.ScenarioInput i = new ClaimPricingService.ScenarioInput();
            i.partsWholesale    = a[0]; i.partsRetail       = a[1];
            i.warrantyWholesale = a[2]; i.warrantyRetail    = a[3];
            i.labourWholesale   = a[4]; i.labourRetail      = a[5];
            i.suppliesWholesale = a[6]; i.suppliesRetail    = a[7];
            i.coreTotal         = a[8];
            i.cap               = claimCap;
            i.deductible        = e.Deductable__c != null ? e.Deductable__c : claimDed;
            i.taxPercent        = e.Tax_Percentage__c != null
                                      ? e.Tax_Percentage__c
                                      : e.Repair_Shop__r?.Tax_Percentage__c;
            i.benefitsApproved  = benefitsApproved;
            i.isReimbursement   = isReimb;
            i.reimbursementTotal= a[9];

            ClaimPricingService.ScenarioResult r = ClaimPricingService.calculateScenario(i);

            // Fresh minimal record: the query above pulled Repair_Shop__r,
            // and the master-detail Claim__c must never be resent on update.
            toStamp.add(new Estimate__c(
                Id                            = eid,
                // existing scalars, same meaning as always
                Parts_Cost__c                 = r.partsWholesale,
                Labour_Cost__c                = r.labourWholesale,
                Shop_Supplies__c              = r.suppliesWholesale,
                Shop_Supplies_Retail__c       = r.suppliesRetail,
                Core_Charge__c                = r.coreTotal,
                Retail_Price__c               = r.retailRepair,
                Retail_Total__c               = r.subtotalRetail,
                Wholesale_Cost__c             = r.claimCost,
                // Tax_Amount__c is NOT stamped: it has been a formula since
                // Sep 22, Customer_Pays_With_Tax__c - Customer_Pays__c, so the
                // platform derives it from the two fields below. Removing the
                // assignment is also right on meaning: this field has always
                // meant the tax sitting inside what the customer pays, which is
                // calculateScenario's customerTaxAmount, not the taxTotal
                // charged across repair and supplies that was being written here.
                Coverage_Applied__c           = r.coverageApplied,
                Customer_Pays__c              = r.customerPaysPreTax,
                Customer_Pays_With_Tax__c     = r.customerPays,
                Profit_Loss__c                = r.profitLossRepairOnly,
                Deductable__c                 = i.deductible,
                // TASK-048: Parts_Retail__c, Labour_Retail__c,
                // Extended_Warranty_Cost__c and Extended_Warranty_Retail__c are
                // NOT stamped here any more. They became native roll-up
                // summaries once the children moved to master-detail, and Apex
                // cannot write to a Summary field. The platform maintains them
                // from Part__c.Line_Retail__c, Service__c.Labour_Retail_Calc__c
                // and the two Extended_Warranty fields filtered on
                // Extended_Warranty__c. calculateScenario still computes the
                // same figures, and the LWC still uses them live; they simply
                // no longer need persisting by hand.
                // TASK-047 additions
                Ancillary_Benefits_Paid__c    = r.benefitsApproved,
                A_Protect_P_L_Incl_Benefits__c= r.profitLossInclBenefits,
                Profit_Loss_Incl_Tax__c       = r.profitLossInclTax,
                Reimbursement_Total__c        = isReimb ? a[9] : 0
            ));
        }
        updateSecured(toStamp);
    }

    // ───────────────────────── Create Work Order ──────────────────────────

    /**
     * Called from the createWorkOrderAction LWC button on the Work Order tab
     * (Sep 22 - Osama caught that the plan originally had this fire
     * automatically on the Claim_Status__c change to "Work Order," which was
     * wrong: the agent needs a deliberate moment to log Ancillary Benefits
     * on that same tab first, and the HTML reference itself has a real
     * button, not automatic behavior). Resolves the claim's currently
     * selected estimate and delegates to createWorkOrder, which already has
     * every guard rail (one active work order per claim, no duplicate per
     * estimate).
     */
    /**
     * TASK-050 item 5 (Osama, 2026-10-09): the Work Order tab tells the agent
     * to pick an estimate before creating a work order, and disables the
     * button until one is. createWorkOrderForSelectedEstimate already refuses
     * with a clear message, but only AFTER the click; this lets the screen say
     * so beforehand. The server check stays exactly as it is and remains the
     * authoritative one.
     *
     * Widened 2026-10-09 from a Boolean hasSelectedEstimate to return the
     * estimate itself, because the tab now NAMES the selected estimate above
     * the button so the agent can see what they are about to commit to. One
     * round trip either way; a Boolean could not carry the name. Returns null
     * when nothing is selected, which is the disabled case.
     */
    @AuraEnabled(cacheable=false)
    public static Estimate__c getSelectedEstimateForClaim(Id claimId) {
        List<Estimate__c> selected = [
            SELECT Id, Name, Estimate_Name__c, Repair_Shop__r.Name,
                   Retail_Total__c, Customer_Pays_With_Tax__c
            FROM Estimate__c
            WHERE Claim__c = :claimId AND Is_Selected__c = true
            WITH USER_MODE
            LIMIT 1
        ];
        return selected.isEmpty() ? null : selected[0];
    }

    @AuraEnabled
    public static WorkOrderResult createWorkOrderForSelectedEstimate(Id claimId) {
        List<Estimate__c> selected = [
            SELECT Id FROM Estimate__c
            WHERE Claim__c = :claimId AND Is_Selected__c = true
            WITH USER_MODE
            LIMIT 1
        ];
        if (selected.isEmpty()) {
            // AuraHandledException.getMessage() only returns the constructor
            // text after setMessage() is also called - a documented Apex
            // quirk, not a typo.
            AuraHandledException ex = new AuraHandledException('Mark an estimate as USE in Manage Estimates before creating a work order.');
            ex.setMessage('Mark an estimate as USE in Manage Estimates before creating a work order.');
            throw ex;
        }
        return createWorkOrder(selected[0].Id);
    }

    @AuraEnabled
    public static WorkOrderResult createWorkOrder(Id estimateId) {
        Estimate__c est = [
            SELECT Id, Claim__c, Repair_Shop__c,
                   Repair_Shop__r.Tax_Region__c, Repair_Shop__r.Tax_Region__r.Total_Tax_Rate__c,
                   Repair_Shop__r.Tax_Percentage__c,
                   Part_Component__c, Job_Type__c, Part_Code__c, Parts_Supplier__c,
                   Parts_Cost__c, Labour_Hours__c, Labour_Rate__c,
                   Shop_Supplies__c, Shop_Supplies_Retail__c, Retail_Price__c, Coverage_Applied__c,
                   // Claim_Type__c tells the coverage split which tax basis
                   // Coverage_Applied__c is on: only the TASK-047 scenario
                   // model writes it, and only that model stamps a
                   // tax-inclusive coverage figure.
                   Claim_Type__c,
                   // TASK-051: How you will be paid, snapshotted below.
                   Reimbursement_Payment_Method__c, Reimbursement_Expected_Payment_Date__c,
                   // TASK-050: the application, customer and vehicle data the
                   // work order snapshots below. All of these are FORMULA
                   // fields on Claim__c reaching through to Application__r and
                   // Vehicle__r, so reading them here never touches those
                   // Application/Package-team objects directly.
                   Claim__r.Application__r.Name,
                   Claim__r.Customer_Name__c, Claim__r.Customer_Address__c,
                   Claim__r.Customer_Email__c, Claim__r.Customer_Phone__c,
                   Claim__r.Vehicle_Identification_Number_VIN__c,
                   Claim__r.Vehicle_Year__c, Claim__r.Vehicle_Make__c,
                   Claim__r.Vehicle_Model__c, Claim__r.Vehicle_Trim__c,
                   Claim__r.Current_Odometer__c, Claim__r.Current_Odometer_Unit__c,
                   (SELECT Id FROM Work_Orders__r LIMIT 1)
            FROM Estimate__c WHERE Id = :estimateId
            WITH USER_MODE
        ];
        if (!est.Work_Orders__r.isEmpty()) {
            throw new AuraHandledException('A work order already exists for this estimate.');
        }

        // Only one active work order per claim (any Status__c other than
        // Voided counts as active), even across different estimates on the
        // same claim - the per-estimate check above only catches re-running
        // Create Work Order on the same winning estimate, not a second,
        // different estimate on a claim that already has one.
        List<Work_Order__c> activeOnClaim = [
            SELECT Id FROM Work_Order__c
            WHERE Claim__c = :est.Claim__c AND Status__c != 'Voided'
            WITH USER_MODE
            LIMIT 1
        ];
        if (!activeOnClaim.isEmpty()) {
            throw new AuraHandledException('This claim already has an active work order.');
        }

        Savepoint sp = Database.setSavepoint();
        try {
            // 1. Work order header. Its totals are formulas over the line items
            //    (Total_Line_Items_Cost__c rolls up Price__c, Tax_13__c and
            //    Total_Repair_Cost__c derive from that) and its coverage /
            //    deductible come from Estimate__r.Claim__r.Package__r, so only
            //    the relationships are set here.
            //    Tax mirrors the Application_Package__c pattern: the region is
            //    stamped from the shop, and the percentage is a writeable snapshot
            //    of that region's rate at authorization time (region rate, else the
            //    shop's synced percentage, else 13), so a later rate change never
            //    rewrites an authorized work order.
            Decimal taxRate = est.Repair_Shop__r?.Tax_Region__r?.Total_Tax_Rate__c;
            if (taxRate == null) taxRate = est.Repair_Shop__r?.Tax_Percentage__c;
            if (taxRate == null) taxRate = 13;
            Work_Order__c wo = new Work_Order__c(
                Claim__c         = est.Claim__c,
                Estimate__c      = est.Id,
                Repair_Shop__c   = est.Repair_Shop__c,
                Tax_Region__c    = est.Repair_Shop__r?.Tax_Region__c,
                Tax_Percentage__c = taxRate,

                // TASK-050. Snapshot, same reasoning as Tax_Percentage__c just
                // above: a work order goes out to the customer and the repair
                // shop for authorization, so it has to say what was true when
                // it was issued. Every Claim__c field read here is itself a
                // formula over Application__r or Vehicle__r, so a live
                // reference would let the other team's edits silently rewrite
                // a document that had already been sent.
                Application_Number__c = est.Claim__r?.Application__r?.Name,
                Customer_Name__c      = est.Claim__r?.Customer_Name__c,
                Customer_Address__c   = est.Claim__r?.Customer_Address__c,
                // The home-then-business precedence lives in the
                // Claim__c.Customer_Phone__c formula, not here, so it has one
                // definition that stays editable in configuration. Osama's
                // rule, 2026-10-08.
                Customer_Phone__c     = est.Claim__r?.Customer_Phone__c,
                Customer_Email__c     = est.Claim__r?.Customer_Email__c,
                VIN__c                = est.Claim__r?.Vehicle_Identification_Number_VIN__c,
                Vehicle_Year__c       = est.Claim__r?.Vehicle_Year__c,
                Vehicle_Make__c       = est.Claim__r?.Vehicle_Make__c,
                Vehicle_Model__c      = est.Claim__r?.Vehicle_Model__c,
                Vehicle_Trim__c       = est.Claim__r?.Vehicle_Trim__c,
                Odometer_In__c        = est.Claim__r?.Current_Odometer__c,
                Odometer_In_Unit__c   = est.Claim__r?.Current_Odometer_Unit__c
            );
            // TASK-051. Snapshot for the same reason as the header above: the
            // payment method and date a reimbursement notice promised must not
            // change after it was sent. Reimbursement Only work orders only.
            Boolean isReimbursement = est.Claim_Type__c == 'Reimbursement Only';
            if (isReimbursement) {
                wo.Reimbursement_Payment_Method__c        = est.Reimbursement_Payment_Method__c;
                wo.Reimbursement_Expected_Payment_Date__c = est.Reimbursement_Expected_Payment_Date__c;
            }
            insertSecured(new List<Work_Order__c>{ wo });

            // 2. Selection flag: exactly one per claim.
            markSelected(est.Id, est.Claim__c);

            // 2b. Benefits-inclusive final P&L onto the claim (repair-only
            //     stays on the Estimate/Work Order - see recalculateClaimTotalProfit).
            recalculateClaimTotalProfit(est.Claim__c);

            // 3. Claim line items, ONE PER CHILD RECORD (TASK-049), plus a
            //    separate line for each optional extended warranty purchased.
            //    Queried here rather than inside buildClaimLineItems so that
            //    method stays pure and unit-testable, and so this stays one
            //    query per child type regardless of how many lines result.
            List<Part__c> estParts = [
                SELECT Id, Part_Name__c, Part_Code__c, Stock_Number__c, Supplier__c, Quantity__c,
                       Part_Cost_Wholesale__c, Price__c,
                       Extended_Warranty__c, Extended_Warranty_Cost__c, Extended_Warranty_Retail__c,
                       Extended_Warranty_Months__c, Extended_Warranty_Km__c
                FROM Part__c WHERE Estimate__c = :est.Id
                WITH USER_MODE
                ORDER BY CreatedDate ASC
            ];
            List<Service__c> estServices = [
                // TASK-050: the retail rate, the retail hours and both guide
                // times were missing from this query, so they could not reach
                // the work order line even though Work_Order_Line_Item__c has
                // a field for each of them.
                SELECT Id, Item_Desription__c, Repair_Time_EST__c, Wholesale_Labour_Rate_HR__c,
                       Wholesale__c, Repair_Time_Adj__c, Retail_Labour_Rate__c, Retail__c,
                       Labour_Guide_Time_Mitchell__c, Labour_Guide_Time_All_Data__c
                FROM Service__c WHERE Estimate__c = :est.Id
                WITH USER_MODE
                ORDER BY CreatedDate ASC
            ];
            List<Shop_Supply__c> estSupplies = [
                SELECT Id, Item_Name__c, Cost__c, Price__c
                FROM Shop_Supply__c WHERE Estimate__c = :est.Id
                WITH USER_MODE
                ORDER BY CreatedDate ASC
            ];
            ClaimLineBuild build =
                buildClaimLineItems(est, estParts, estServices, estSupplies);
            List<Claim_Line_Item__c> lines = build.lines;
            insertSecured(lines);

            // 4. Work order line items generated from the claim line items.
            //    Price__c carries RETAIL because Work_Order__c.Total_Line_Items_Cost__c
            //    rolls it up and the work order is the customer-facing document; the
            //    vendor cost sits in Wholesale__c. Falls back to wholesale only when a
            //    child had no retail figure at all.
            //    Covered_Amount__c/Customer_Pay_Amount__c (Sep 24, "Work Order - Approved
            //    Repairs" table): the Estimate's Coverage_Applied__c is split proportionally
            //    across the non-Supplies lines by their own retail share of Retail_Price__c
            //    (same technique already used to split retail between Part/Labour above) -
            //    the LAST non-Supplies line absorbs the rounding remainder so the lines
            //    always sum back to exactly Coverage_Applied__c. Supplies is never covered,
            //    matching the pricing formula (shop supplies retail is added AFTER coverage).
            // TASK-049 fix for a bug TASK-047 introduced and this surfaced.
            // Decision 8 made Coverage_Applied__c TAX-INCLUSIVE (the cap is now
            // tested against the tax-inclusive repair), but these line items
            // carry PRE-TAX retail. Spreading a tax-inclusive coverage figure
            // across pre-tax retail hands a line more coverage than it is
            // worth: Option C would have produced Part -71.43 and Labour -28.57
            // as NEGATIVE customer-pay amounts on a fully covered claim.
            // Converting coverage to its pre-tax equivalent first reconciles
            // exactly: for Option C the lines then total 233.63 pre-tax, which
            // x 1.13 is 264.00, precisely repairInc less coverage.
            // Coverage_Applied__c is TAX-INCLUSIVE under the TASK-047 scenario
            // model (decision 8: the cap now covers tax), but these line items
            // carry PRE-TAX retail, so it has to be converted before it can be
            // spread across them. Without this, a fully covered claim writes
            // NEGATIVE customer-pay amounts: Option C produced Part -71.43 and
            // Labour -28.57. Converted, the lines total 233.63 pre-tax, which
            // x 1.13 is exactly 264.00, the repair less coverage.
            //
            // This assumes the scenario model priced the estimate, which is
            // true for everything the UI can now produce: no LWC calls
            // saveEstimates, updateEstimate or recalculateAndStamp any more,
            // and those legacy entry points survive only for their own tests.
            // Two attempts to detect the basis instead both failed and are
            // recorded so nobody retries them: comparing coverage against the
            // pre-tax line total is wrong on an over-cap claim (Option A has
            // coverage 2900 below a 4447.50 line total yet still needs
            // converting), and Claim_Type__c is useless as a discriminator
            // because 'Repair' is its picklist DEFAULT, so every estimate has
            // it. Retiring the legacy pricing path would delete this comment
            // and the conversion along with it.
            Decimal taxFactor = 1 + (nz(taxRate) / 100);
            Decimal coverageApplied = taxFactor > 0
                ? nz(est.Coverage_Applied__c).divide(taxFactor, 2, RoundingMode.HALF_UP)
                : nz(est.Coverage_Applied__c);

            // Denominator from the lines themselves rather than the stamped
            // Retail_Price__c, so the shares always sum to exactly 1 even if
            // that scalar is stale relative to the children.
            Decimal jobRetail = 0;
            Integer nonSuppliesCount = 0;
            for (Claim_Line_Item__c cli : lines) {
                if (cli.Line_Type__c != 'Supplies') {
                    nonSuppliesCount++;
                    jobRetail += cli.Retail_Amount__c != null ? cli.Retail_Amount__c : nz(cli.Amount__c);
                }
            }
            // Coverage can never exceed what the covered lines are actually worth.
            if (coverageApplied > jobRetail) coverageApplied = jobRetail;

            List<Work_Order_Line_Item__c> woLines = new List<Work_Order_Line_Item__c>();
            Integer nonSuppliesSeen  = 0;
            Decimal coverageAssigned = 0;
            for (Integer i = 0; i < lines.size(); i++) {
                Claim_Line_Item__c cli = lines[i];
                SObject source = build.sources[i];
                Decimal retail = cli.Retail_Amount__c != null ? cli.Retail_Amount__c : cli.Amount__c;

                Decimal covered = 0;
                if (cli.Line_Type__c != 'Supplies' && jobRetail > 0) {
                    nonSuppliesSeen++;
                    if (nonSuppliesSeen == nonSuppliesCount) {
                        covered = coverageApplied - coverageAssigned;
                    } else {
                        Decimal share = (retail / jobRetail).setScale(10, RoundingMode.HALF_UP);
                        covered = (coverageApplied * share).setScale(2, RoundingMode.HALF_UP);
                    }
                    coverageAssigned += covered;
                }
                Decimal customerPay = retail - covered;

                Work_Order_Line_Item__c wl = new Work_Order_Line_Item__c(
                    Customer_Work_Order__c        = wo.Id,
                    Claim_Line_Item__c            = cli.Id,
                    Service_Repair_Description__c = cli.Description__c,
                    Description__c                = cli.Description__c,
                    Repair_Shop__c                = cli.Repair_Shop__c,
                    Price__c                      = retail,
                    Retail__c                     = retail,
                    Wholesale__c                  = cli.Amount__c,
                    Covered_Amount__c             = covered,
                    Customer_Pay_Amount__c        = customerPay
                );
                // TASK-050. Labour detail comes from the Service__c itself, not
                // from the claim line item in between. That record has a single
                // Hours__c and Rate__c, so routing labour through it could only
                // ever carry the wholesale pair: the retail rate, the retail
                // hours and both guide times were dropped, and the WHOLESALE
                // hours were being written into Repair_Time_Adj__c, which means
                // the ADJUSTED (retail) time on both objects. That mislabelling
                // was invisible whenever the two hour figures happened to be
                // equal, which is why it survived.
                if (source instanceof Service__c) {
                    Service__c s = (Service__c) source;
                    wl.Repair_Time_EST__c            = s.Repair_Time_EST__c;
                    wl.Wholesale_Labour_Rate_HR__c   = s.Wholesale_Labour_Rate_HR__c;
                    wl.Repair_Time_Adj__c            = s.Repair_Time_Adj__c;
                    wl.Retail_Labour_Rate__c         = s.Retail_Labour_Rate__c;
                    wl.Labour_Guide_Time_Mitchell__c = s.Labour_Guide_Time_Mitchell__c;
                    wl.Labour_Guide_Time_All_Data__c = s.Labour_Guide_Time_All_Data__c;
                } else if (cli.Line_Type__c == 'Labour') {
                    // Legacy estimates with no children, where the only hours
                    // available are the old Estimate__c.Labour_Hours__c. Those
                    // are wholesale hours, so they belong in Repair_Time_EST__c
                    // rather than in the adjusted field they used to land in.
                    wl.Wholesale_Labour_Rate_HR__c = cli.Rate__c;
                    wl.Repair_Time_EST__c = cli.Hours__c == null
                        ? null : cli.Hours__c.setScale(0, RoundingMode.HALF_UP);
                }
                woLines.add(wl);
            }
            insertSecured(woLines);

            // 5. TASK-051 (Osama, 2026-10-13). A reimbursement pays the
            //    CUSTOMER, so it belongs in the payables ledger like any other
            //    line A-Protect pays out: one Claim_Line_Item__c per approved
            //    receipt, Role Customer. Before this the payout was recorded
            //    nowhere. Deliberately NOT turned into Work_Order_Line_Item__c
            //    rows: those are repair work the customer is charged for, and
            //    Wrap Up builds the customer invoice from them.
            List<Claim_Line_Item__c> reimbLines = new List<Claim_Line_Item__c>();
            if (isReimbursement) {
                List<ApprovedReimbursement> approved =
                    getApprovedReimbursements(new Set<Id>{ est.Id }).get(est.Id);
                if (approved != null) {
                    for (ApprovedReimbursement a : approved) {
                        if (a.approved <= 0) continue;
                        reimbLines.add(new Claim_Line_Item__c(
                            Claim__c       = est.Claim__c,
                            Estimate__c    = est.Id,
                            Line_Type__c   = 'Reimbursement',
                            Role__c        = 'Customer',
                            Description__c = a.benefitType + ' reimbursement',
                            Amount__c      = a.approved
                        ));
                    }
                }
                insertSecured(reimbLines);
            }

            WorkOrderResult r = new WorkOrderResult();
            r.workOrderId    = wo.Id;
            r.claimLineItems = lines.size() + reimbLines.size();
            r.workOrderLines = woLines.size();
            return r;
        } catch (Exception ex) {
            Database.rollback(sp);
            // AuraHandledException.getMessage() returns the useless
            // "Script-thrown exception" unless setMessage is called, which hid
            // the real cause from the screen AND from test output. Seven tests
            // failed with nothing but that string on 2026-10-08 while this was
            // the only thing standing between me and the actual error.
            // saveManageEstimates and saveBenefitUsage already do this.
            String detail = 'Could not create work order: ' + ex.getTypeName()
                + ': ' + ex.getMessage() + ' (line ' + ex.getLineNumber() + ')';
            System.debug(LoggingLevel.ERROR, detail + '\n' + ex.getStackTraceString());
            AuraHandledException wrapped = new AuraHandledException(detail);
            wrapped.setMessage(detail);
            throw wrapped;
        }
    }

    /**
     * TASK-049 (requirement 9): ONE claim line item per real child record,
     * plus a SEPARATE line for each optional extended warranty actually
     * purchased, which the brief called out explicitly:
     *
     *   "If the customer purchased the Optional Extended Warranty, a separate
     *    Work Order Line Item must be created for it. Make sure this is
     *    represented separately and does not get incorrectly merged into
     *    another line item."
     *
     * Before this, the work order always had exactly 3 hardcoded lines
     * (Part/Labour/Supplies) no matter what the estimate contained, so an
     * estimate with three parts produced one line labelled after the first
     * part with all three lumped into it, and an extended warranty never
     * appeared at all even though the customer was charged for it.
     *
     * The proportional retail split that used to live here is GONE. It only
     * existed because the old Estimate had a single combined Retail_Price__c
     * with no per-line retail; every child now carries its own honest figure.
     *
     * Falls back to the old scalar-driven behaviour when an estimate has no
     * children, so work orders can still be created from estimates that
     * predate TASK-047. Osama's decision 10 stands: nothing historical is
     * restated or broken.
     *
     * Line_Type__c distinguishes Part / Labour / Supplies / Extended
     * Warranty, which the Vendor Payables and Claim Detail reports rely on.
     *
     * OPEN QUESTION, deliberately left as-is (flagged 2026-10-06): whether an
     * extended warranty should be covered by A-Protect or paid entirely by
     * the customer. Noelle's design puts it INSIDE the retail repair that the
     * cap is tested against (Formulas card 7: "retail repair = parts + ext.
     * warranty + labour (supplies excluded)"), and the work order preview
     * labels only Shop Supplies as "(Customer Responsibility)". That design
     * is what is implemented here, so an Extended Warranty line takes a
     * proportional share of coverage exactly like Part and Labour. On an
     * over-cap claim this is identical to the customer paying in full, since
     * coverage is pinned at the cap; the two readings only differ on a fully
     * covered claim. Do not change this without Noelle and the client.
     */
    /**
     * The claim line items, each paired with the child record it came from.
     *
     * TASK-050: the pairing is the point. Claim_Line_Item__c has one Hours__c
     * and one Rate__c, so a labour line could only ever carry the WHOLESALE
     * pair through it; the retail rate, the retail hours and both guide times
     * had nowhere to go and were silently dropped, even though
     * Work_Order_Line_Item__c has a purpose-built field for every one of them.
     * Keeping the source alongside each line lets the work order line be
     * populated from Service__c directly, rather than from the lossy middle
     * record. Index-aligned: sources[i] is where lines[i] came from, and it is
     * null for the legacy no-children fallback.
     */
    private class ClaimLineBuild {
        List<Claim_Line_Item__c> lines = new List<Claim_Line_Item__c>();
        List<SObject> sources = new List<SObject>();

        void add(Claim_Line_Item__c line, SObject source) {
            lines.add(line);
            sources.add(source);
        }
    }

    private static ClaimLineBuild buildClaimLineItems(
            Estimate__c est,
            List<Part__c> parts,
            List<Service__c> services,
            List<Shop_Supply__c> supplies) {

        Boolean hasChildren = !parts.isEmpty() || !services.isEmpty() || !supplies.isEmpty();
        if (!hasChildren) {
            ClaimLineBuild legacy = new ClaimLineBuild();
            for (Claim_Line_Item__c cli : buildClaimLineItemsFromScalars(est)) {
                legacy.add(cli, null);
            }
            return legacy;
        }

        ClaimLineBuild out = new ClaimLineBuild();

        for (Part__c p : parts) {
            Decimal qty       = nz(p.Quantity__c) == 0 ? 1 : p.Quantity__c;
            Decimal wholesale = qty * nz(p.Part_Cost_Wholesale__c);
            Decimal retail    = qty * nz(p.Price__c);
            if (wholesale != 0 || retail != 0) {
                out.add(new Claim_Line_Item__c(
                    Claim__c          = est.Claim__c,
                    // TASK-050 primary rule: every downstream line must be
                    // traceable back to the Estimate AND to the child it came
                    // from. Work Order Line Item and Invoice Line Item already
                    // chain; this was the broken hop.
                    Estimate__c       = est.Id,
                    Part__c           = p.Id,
                    Line_Type__c      = 'Part',
                    Role__c           = 'Parts Supplier',
                    Description__c    = String.isNotBlank(p.Part_Name__c) ? p.Part_Name__c : 'Part',
                    Part_Code__c      = p.Part_Code__c,
                    Stock_Number__c   = p.Stock_Number__c,
                    Parts_Supplier__c = p.Supplier__c,
                    Repair_Shop__c    = est.Repair_Shop__c,
                    Amount__c         = wholesale,
                    Retail_Amount__c  = retail
                ), p);
            }

            // Its own line, never merged into the part it belongs to.
            if (p.Extended_Warranty__c == true && nz(p.Extended_Warranty_Cost__c) != 0) {
                out.add(new Claim_Line_Item__c(
                    Claim__c         = est.Claim__c,
                    Estimate__c      = est.Id,
                    // The warranty is sold against a part, so it traces to the
                    // same Part__c as the part line beside it.
                    Part__c          = p.Id,
                    Line_Type__c     = 'Extended Warranty',
                    Role__c          = 'Parts Supplier',
                    Description__c   = extendedWarrantyLabel(p),
                    Repair_Shop__c   = est.Repair_Shop__c,
                    Amount__c        = nz(p.Extended_Warranty_Cost__c),
                    Retail_Amount__c = nz(p.Extended_Warranty_Retail__c)
                ), p);
            }
        }

        for (Service__c s : services) {
            Decimal wholesale = nz(s.Wholesale__c);
            Decimal retail    = nz(s.Retail__c);
            if (wholesale != 0 || retail != 0) {
                out.add(new Claim_Line_Item__c(
                    Claim__c         = est.Claim__c,
                    Estimate__c      = est.Id,
                    Service__c       = s.Id,
                    Line_Type__c     = 'Labour',
                    Role__c          = 'Repair Shop',
                    Description__c   = String.isNotBlank(s.Item_Desription__c) ? s.Item_Desription__c : 'Labour',
                    Hours__c         = s.Repair_Time_EST__c,
                    Rate__c          = s.Wholesale_Labour_Rate_HR__c,
                    Repair_Shop__c   = est.Repair_Shop__c,
                    Amount__c        = wholesale,
                    Retail_Amount__c = retail
                ), s);
            }
        }

        for (Shop_Supply__c x : supplies) {
            Decimal wholesale = nz(x.Cost__c);
            Decimal retail    = nz(x.Price__c);
            if (wholesale != 0 || retail != 0) {
                out.add(new Claim_Line_Item__c(
                    Claim__c         = est.Claim__c,
                    Estimate__c      = est.Id,
                    Shop_Supply__c   = x.Id,
                    Line_Type__c     = 'Supplies',
                    Role__c          = 'Repair Shop',
                    Description__c   = String.isNotBlank(x.Item_Name__c) ? x.Item_Name__c : 'Shop Supplies',
                    Repair_Shop__c   = est.Repair_Shop__c,
                    Amount__c        = wholesale,
                    Retail_Amount__c = retail
                ), x);
            }
        }
        return out;
    }

    /** "Extended Warranty: Engine (12 mo / 20,000 km)", matching the design's own wording. */
    private static String extendedWarrantyLabel(Part__c p) {
        List<String> term = new List<String>();
        if (nz(p.Extended_Warranty_Months__c) > 0) {
            term.add(String.valueOf(p.Extended_Warranty_Months__c.setScale(0, RoundingMode.HALF_UP)) + ' mo');
        }
        if (nz(p.Extended_Warranty_Km__c) > 0) {
            term.add(String.valueOf(p.Extended_Warranty_Km__c.setScale(0, RoundingMode.HALF_UP)) + ' km');
        }
        String name = String.isNotBlank(p.Part_Name__c) ? p.Part_Name__c : 'part';
        return 'Extended Warranty: ' + name + (term.isEmpty() ? '' : ' (' + String.join(term, ' / ') + ')');
    }

    /**
     * The pre-TASK-049 behaviour, kept ONLY as a fallback for estimates with
     * no children (anything created before TASK-047). Three lines at most,
     * with the retail allocation that the child-driven path above no longer
     * needs: the old Estimate had one combined Retail_Price__c for parts and
     * labour together, split here proportionally by wholesale share so the
     * lines still sum back to exactly Retail_Total__c.
     */
    private static List<Claim_Line_Item__c> buildClaimLineItemsFromScalars(Estimate__c est) {
        List<Claim_Line_Item__c> out = new List<Claim_Line_Item__c>();

        Decimal partsWholesale  = nz(est.Parts_Cost__c);
        Decimal labourWholesale = nz(est.Labour_Hours__c) * nz(est.Labour_Rate__c);
        Decimal repairWholesale = partsWholesale + labourWholesale;
        Decimal jobRetail       = nz(est.Retail_Price__c);
        // setScale(2) before dividing back out - an un-rounded division here
        // (e.g. 1300/1900) can produce a long repeating decimal that throws
        // the retail split off by a fraction of a cent.
        Decimal partsShare   = repairWholesale > 0
            ? (partsWholesale / repairWholesale).setScale(10, RoundingMode.HALF_UP)
            : 0;
        Decimal partsRetail  = (jobRetail * partsShare).setScale(2, RoundingMode.HALF_UP);
        Decimal labourRetail = jobRetail - partsRetail;

        if (partsWholesale != 0) {
            out.add(new Claim_Line_Item__c(
                Claim__c          = est.Claim__c,
                Line_Type__c      = 'Part',
                Role__c           = 'Parts Supplier',
                Description__c    = String.isNotBlank(est.Part_Component__c) ? est.Part_Component__c : 'Part',
                Part_Code__c      = est.Part_Code__c,
                Parts_Supplier__c = est.Parts_Supplier__c,
                Repair_Shop__c    = est.Repair_Shop__c,
                Amount__c         = partsWholesale,
                Retail_Amount__c  = partsRetail
            ));
        }

        if (labourWholesale != 0) {
            out.add(new Claim_Line_Item__c(
                Claim__c         = est.Claim__c,
                Line_Type__c     = 'Labour',
                Role__c          = 'Repair Shop',
                Description__c   = String.isNotBlank(est.Job_Type__c) ? est.Job_Type__c + ' Labour' : 'Labour',
                Hours__c         = est.Labour_Hours__c,
                Rate__c          = est.Labour_Rate__c,
                Repair_Shop__c   = est.Repair_Shop__c,
                Amount__c        = labourWholesale,
                Retail_Amount__c = labourRetail
            ));
        }

        Decimal suppliesWholesale = nz(est.Shop_Supplies__c);
        Decimal suppliesRetail    = nz(est.Shop_Supplies_Retail__c);
        if (suppliesWholesale != 0 || suppliesRetail != 0) {
            out.add(new Claim_Line_Item__c(
                Claim__c         = est.Claim__c,
                Line_Type__c     = 'Supplies',
                Role__c          = 'Repair Shop',
                Description__c   = 'Shop Supplies',
                Repair_Shop__c   = est.Repair_Shop__c,
                Amount__c        = suppliesWholesale,
                Retail_Amount__c = suppliesRetail
            ));
        }

        return out;
    }

    private static Decimal nz(Decimal d) { return d == null ? 0 : d; }

    // ──────────────── Ancillary Benefits (Work Order tab) ────────────────
    // Backs the ancillaryBenefits LWC (Pass 2). Benefits are claim-level,
    // shared across every competing Estimate on the claim, not tied to any
    // one of them - Benefit_Balance__c is keyed off the claim's purchased
    // Application_Package__c, not an Estimate__c.

    public class BenefitBalanceRow {
        @AuraEnabled public Id balanceId;
        @AuraEnabled public String benefitType;
        @AuraEnabled public Decimal capAmount;
        @AuraEnabled public Decimal usedToDate;
        @AuraEnabled public Decimal remaining;     // Benefit_Balance__c.Remaining__c as-is
        @AuraEnabled public Id usageId;            // this claim's own Benefit_Usage__c, if it already has one
        @AuraEnabled public Decimal usageAmount;   // that draw's Amount_Used__c, if any
        // Ceiling for editing THIS claim's own draw: Remaining__c already has
        // this claim's existing usage subtracted out (it's counted in
        // Used_To_Date__c), so saving a changed amount REPLACES that draw
        // rather than adding to it - add it back to get the true room to type into.
        @AuraEnabled public Decimal availableToUse;
    }

    /**
     * Every Benefit_Balance__c under the claim's purchased Application_Package__c,
     * each paired with this claim's own existing Benefit_Usage__c draw (if
     * any) so the LWC edits that draw in place on Save instead of inserting
     * a second, duplicate one every time the screen is saved.
     */
    @AuraEnabled
    public static List<BenefitBalanceRow> getBenefitBalancesForClaim(Id claimId) {
        Claim__c claim = [
            SELECT Id, Application_Package__c
            FROM Claim__c WHERE Id = :claimId
            WITH USER_MODE
        ];
        List<BenefitBalanceRow> rows = new List<BenefitBalanceRow>();
        if (claim.Application_Package__c == null) return rows;

        List<Benefit_Balance__c> balances = [
            SELECT Id, Benefit_Type__c, Cap_Amount__c, Used_To_Date__c, Remaining__c
            FROM Benefit_Balance__c
            WHERE Application_Package__c = :claim.Application_Package__c
            WITH USER_MODE
            ORDER BY Benefit_Type__c
        ];
        if (balances.isEmpty()) return rows;

        Map<Id, Benefit_Usage__c> usageByBalance = new Map<Id, Benefit_Usage__c>();
        for (Benefit_Usage__c u : [
            SELECT Id, Benefit_Balance__c, Amount_Used__c
            FROM Benefit_Usage__c
            WHERE Claim__c = :claimId AND Benefit_Balance__c IN :balances
              // TASK-047: a draw carrying an Estimate__c belongs to one
              // Reimbursement Only scenario, not to the claim as a whole.
              // Without this filter a reimbursement line would surface here
              // as the claim's own ancillary draw and be double counted.
              AND Estimate__c = null
            WITH USER_MODE
        ]) {
            usageByBalance.put(u.Benefit_Balance__c, u);
        }

        for (Benefit_Balance__c b : balances) {
            Benefit_Usage__c existing = usageByBalance.get(b.Id);
            BenefitBalanceRow row = new BenefitBalanceRow();
            row.balanceId      = b.Id;
            row.benefitType    = b.Benefit_Type__c;
            row.capAmount      = b.Cap_Amount__c;
            row.usedToDate     = b.Used_To_Date__c;
            row.remaining      = b.Remaining__c;
            row.usageId        = existing?.Id;
            row.usageAmount    = existing?.Amount_Used__c;
            row.availableToUse = nz(b.Remaining__c) + nz(existing?.Amount_Used__c);
            rows.add(row);
        }
        return rows;
    }

    /**
     * Bulk save for the Ancillary Benefits editor: one Benefit_Usage__c per
     * included benefit, Id populated to update this claim's already-existing
     * draw (never a second, duplicate draw on re-save) or blank to insert a
     * new one. Amount_Used__c over its balance's availableToUse is refused -
     * the LWC already blocks this live, this is the server-side backstop.
     */
    @AuraEnabled
    public static void saveBenefitUsage(Id claimId, List<Benefit_Usage__c> usages,
            List<Id> removedUsageIds) {
        // Osama, 2026-10-08: unchecking a benefit and saving left it still
        // showing as drawn. The editor sends only the CHECKED rows, so an
        // unchecked benefit was simply absent from the payload and its
        // Benefit_Usage__c row survived untouched. That is a money bug, not a
        // display one: the draw kept consuming Benefit_Balance__c.Used_To_Date__c
        // and kept crediting the customer through Ancillary_Benefits_Paid__c.
        // Deleting here is what makes unchecking mean anything.
        if (removedUsageIds != null && !removedUsageIds.isEmpty()) {
            deleteSecured([
                SELECT Id FROM Benefit_Usage__c
                WHERE Id IN :removedUsageIds AND Claim__c = :claimId
                WITH USER_MODE
            ]);
        }

        // Deliberately AFTER the delete, and it still recalculates: clearing
        // the last benefit on a claim is a real change and the claim's total
        // profit has to follow it. Returning early here was the same trap as
        // in saveManageEstimates, where an early return would have swallowed
        // pending deletions.
        if (usages == null || usages.isEmpty()) {
            recalculateClaimTotalProfit(claimId);
            return;
        }

        Set<Id> balanceIds = new Set<Id>();
        Set<Id> usageIds = new Set<Id>();
        for (Benefit_Usage__c u : usages) {
            balanceIds.add(u.Benefit_Balance__c);
            if (u.Id != null) usageIds.add(u.Id);
        }
        Map<Id, Benefit_Balance__c> balancesById = new Map<Id, Benefit_Balance__c>([
            SELECT Id, Remaining__c FROM Benefit_Balance__c WHERE Id IN :balanceIds WITH USER_MODE
        ]);
        Map<Id, Decimal> existingAmountByUsageId = new Map<Id, Decimal>();
        if (!usageIds.isEmpty()) {
            for (Benefit_Usage__c existing : [
                SELECT Id, Amount_Used__c FROM Benefit_Usage__c WHERE Id IN :usageIds WITH USER_MODE
            ]) {
                existingAmountByUsageId.put(existing.Id, existing.Amount_Used__c);
            }
        }

        List<Benefit_Usage__c> toInsert = new List<Benefit_Usage__c>();
        List<Benefit_Usage__c> toUpdate = new List<Benefit_Usage__c>();
        for (Benefit_Usage__c u : usages) {
            Benefit_Balance__c bal = balancesById.get(u.Benefit_Balance__c);
            Decimal available = bal == null ? 0 : nz(bal.Remaining__c) + nz(existingAmountByUsageId.get(u.Id));
            if (nz(u.Amount_Used__c) > available) {
                AuraHandledException ex = new AuraHandledException('Use This Claim amount exceeds the benefit\'s remaining balance.');
                ex.setMessage('Use This Claim amount exceeds the benefit\'s remaining balance.');
                throw ex;
            }
            if (u.Id == null) {
                u.Claim__c = claimId;
                if (u.Date__c == null) u.Date__c = Date.today();
                // TASK-047: a claim-level ancillary draw always consumes the
                // balance. Only an estimate-scoped reimbursement line on an
                // unchosen scenario does not, and those are written by
                // saveScenarioChildren, never here.
                u.Counts_Toward_Balance__c = true;
                toInsert.add(u);
            } else {
                // Benefit_Balance__c is a non-reparentable master-detail -
                // never resend it on an update, even unchanged: USER_MODE
                // treats that as an edit to a field that structurally can
                // never be edited and refuses the whole DML.
                toUpdate.add(new Benefit_Usage__c(
                    Id                       = u.Id,
                    Amount_Used__c           = u.Amount_Used__c,
                    Date__c                  = u.Date__c != null ? u.Date__c : Date.today(),
                    Claim__c                 = claimId,
                    Counts_Toward_Balance__c = true
                ));
            }
        }
        insertSecured(toInsert);
        updateSecured(toUpdate);
        recalculateClaimTotalProfit(claimId);
    }

    /**
     * Stamps the benefits-inclusive final P&L onto Claim__c.Total_Profit__c -
     * the number the Estimate__c/Work_Order__c "A-Protect P&L" fields
     * deliberately do NOT show (those stay repair-only, per the Sep 22
     * decision, so competing estimates stay comparable). Formula: the
     * claim's selected Estimate's own repair-only Profit_Loss__c, minus
     * every ancillary benefit drawn against this claim so far. No-ops if
     * no estimate is selected yet - there's nothing meaningful to compute.
     * Called after every Ancillary Benefits save AND after Create Work
     * Order, so the number never goes stale regardless of which happens
     * first or is edited again later (Osama's choice, Sep 22).
     */
    private static void recalculateClaimTotalProfit(Id claimId) {
        List<Estimate__c> selected = [
            SELECT Id, Profit_Loss__c, Claim_Type__c
            FROM Estimate__c
            WHERE Claim__c = :claimId AND Is_Selected__c = true
            WITH USER_MODE
            LIMIT 1
        ];
        if (selected.isEmpty()) return;

        // TASK-051 (Osama, 2026-10-13): when the chosen scenario is
        // Reimbursement Only, the customer is paid its approved receipts and
        // nothing else, exactly as calculateScenario prices it. The
        // claim-level ancillary draws apply to repair scenarios only. This
        // total feeds Work_Order__c.Benefits_Used__c, which showed 305 on
        // CWO-0044 (a 100 claim-level draw plus 205 of receipts) while the
        // customer was being reimbursed 205.
        if (selected[0].Claim_Type__c == 'Reimbursement Only') {
            Decimal reimbursed = approvedTotal(
                getApprovedReimbursements(new Set<Id>{ selected[0].Id }).get(selected[0].Id));
            updateSecured(new List<Claim__c>{
                new Claim__c(
                    Id = claimId,
                    Total_Profit__c = nz(selected[0].Profit_Loss__c) - reimbursed,
                    Total_Benefits_Used__c = reimbursed
                )
            });
            return;
        }

        // TASK-047: a Benefit_Usage__c carrying an Estimate__c is a
        // reimbursement line belonging to ONE scenario. Only the scenario
        // actually marked Use may affect the claim's P&L, otherwise a
        // reimbursement typed into a competing scenario the agent never chose
        // would still be subtracted here. Claim-level draws (Estimate__c
        // blank) always count, because they apply to every scenario.
        Id selectedId = selected[0].Id;
        AggregateResult[] agg = [
            SELECT SUM(Amount_Used__c) total
            FROM Benefit_Usage__c
            WHERE Claim__c = :claimId
              AND (Estimate__c = null OR Estimate__c = :selectedId)
            WITH USER_MODE
        ];
        Decimal benefitsUsed = agg.isEmpty() ? 0 : (Decimal) agg[0].get('total');

        updateSecured(new List<Claim__c>{
            new Claim__c(
                Id = claimId,
                Total_Profit__c = nz(selected[0].Profit_Loss__c) - nz(benefitsUsed),
                Total_Benefits_Used__c = nz(benefitsUsed)
            )
        });
    }

    // ──────────────── Work Order detail (Work Order tab) ────────────────
    // Backs createWorkOrderAction's detail view, shown once the claim has an
    // active work order instead of the Create Work Order button.

    public class WorkOrderDetail {
        @AuraEnabled public Id workOrderId;
        @AuraEnabled public String workOrderName;
        @AuraEnabled public Decimal deductible;        // Deductable__c
        @AuraEnabled public Decimal balanceAmountDue;  // Total_Amount_Due__c
        @AuraEnabled public List<WorkOrderLineRow> lines;

        // Selected Scenario breakdown (warranty_claims_dashboard (2).html),
        // added Sep 24. Descriptive fields read straight through Estimate__r
        // (display-only, not worth mirroring onto Work_Order__c as their own
        // fields); dollar figures read from Work_Order__c's own mirrored
        // formula fields, so this LWC and the record page always agree.
        @AuraEnabled public String partComponent;
        @AuraEnabled public String jobType;
        @AuraEnabled public String condition;
        @AuraEnabled public Decimal kms;
        @AuraEnabled public String partsSupplierName;
        @AuraEnabled public String partCode;
        @AuraEnabled public String stockNumber;
        @AuraEnabled public String repairShopName;
        @AuraEnabled public Decimal labourHours;
        @AuraEnabled public Decimal labourRate;
        @AuraEnabled public String insuranceSource;
        @AuraEnabled public Decimal capAmount; // Claim__r.Application_Package__r.Per_Claim_Limit__c, display only

        @AuraEnabled public Decimal retailPrice;           // Retail_Price__c
        @AuraEnabled public Decimal coverageApplied;       // Coverage_Applied__c
        @AuraEnabled public Decimal customerRepairPortion; // Customer_Repair_Portion__c
        @AuraEnabled public Decimal shopSuppliesRetail;    // Shop_Supplies_Retail__c
        @AuraEnabled public Decimal customerPaysPreTax;    // Customer_Pays__c
        @AuraEnabled public Decimal taxAmount;             // Tax_Amount__c
        @AuraEnabled public Decimal customerPaysWithTax;   // Total_Amount_Due__c (same field as balanceAmountDue)

        @AuraEnabled public Decimal partsCost;        // Parts_Cost__c
        @AuraEnabled public Decimal labourCost;       // Labour_Cost__c
        @AuraEnabled public Decimal shopSuppliesCost; // Shop_Supplies__c
        @AuraEnabled public Decimal insuranceAmount;  // Insurance_Amount__c
        @AuraEnabled public Decimal wholesaleCost;    // Wholesale_Cost__c
        @AuraEnabled public Decimal benefitsUsed;     // Benefits_Used__c
        @AuraEnabled public Decimal totalClaimCost;   // Total_Claim_Cost__c
        @AuraEnabled public Decimal finalProfitLoss;  // Final_Profit_Loss__c
    }

    public class WorkOrderLineRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String description; // Service_Repair_Description__c
        @AuraEnabled public Decimal price;       // Price__c
        // TASK-050 item 4: the Approved Repairs table shows Retail alongside
        // Covered and Customer Pay. Retail__c is the existing field and the
        // one the document uses; no new figure is introduced here.
        @AuraEnabled public Decimal retail;      // Retail__c
        @AuraEnabled public Decimal covered;     // Covered_Amount__c
        @AuraEnabled public Decimal customerPay; // Customer_Pay_Amount__c
        @AuraEnabled public String orderedPartStatus; // Ordered_Part_Status__c
    }

    /**
     * The claim's one active (non-Voided) work order and its line items, or
     * null if none exists yet - same "one active work order per claim" rule
     * already enforced in createWorkOrder.
     */
    @AuraEnabled
    public static WorkOrderDetail getActiveWorkOrderDetailsForClaim(Id claimId) {
        List<Work_Order__c> active = [
            SELECT Id, Name, Deductable__c, Total_Amount_Due__c,
                   Retail_Price__c, Coverage_Applied__c, Customer_Repair_Portion__c, Shop_Supplies_Retail__c,
                   Customer_Pays__c, Tax_Amount__c,
                   Parts_Cost__c, Labour_Cost__c, Shop_Supplies__c, Insurance_Amount__c, Wholesale_Cost__c,
                   Benefits_Used__c, Total_Claim_Cost__c, Final_Profit_Loss__c,
                   Estimate__r.Part_Component__c, Estimate__r.Job_Type__c, Estimate__r.Condition__c,
                   Estimate__r.KMs__c, Estimate__r.Parts_Supplier__r.Name, Estimate__r.Part_Code__c,
                   Estimate__r.Stock_Number__c, Estimate__r.Repair_Shop__r.Name,
                   Estimate__r.Labour_Hours__c, Estimate__r.Labour_Rate__c, Estimate__r.Insurance_Source__c,
                   Claim__r.Application_Package__r.Per_Claim_Limit__c,
                   (SELECT Id, Name, Service_Repair_Description__c, Description__c,
                           Claim_Line_Item__r.Description__c,
                           Price__c, Retail__c, Covered_Amount__c, Customer_Pay_Amount__c,
                           Ordered_Part_Status__c
                    FROM Customer_Work_Order_Line_Items__r)
            FROM Work_Order__c
            WHERE Claim__c = :claimId AND Status__c != 'Voided'
            WITH USER_MODE
            LIMIT 1
        ];
        if (active.isEmpty()) return null;

        Work_Order__c wo = active[0];
        WorkOrderDetail detail = new WorkOrderDetail();
        detail.workOrderId      = wo.Id;
        detail.workOrderName    = wo.Name;
        detail.deductible       = wo.Deductable__c;
        detail.balanceAmountDue = wo.Total_Amount_Due__c;
        detail.lines            = new List<WorkOrderLineRow>();
        for (Work_Order_Line_Item__c wl : wo.Customer_Work_Order_Line_Items__r) {
            WorkOrderLineRow row = new WorkOrderLineRow();
            row.id          = wl.Id;
            row.name        = wl.Name;
            row.description = lineDescription(wl);
            row.price        = wl.Price__c;
            row.retail       = wl.Retail__c;
            row.covered      = wl.Covered_Amount__c;
            row.customerPay  = wl.Customer_Pay_Amount__c;
            row.orderedPartStatus = wl.Ordered_Part_Status__c;
            detail.lines.add(row);
        }

        detail.partComponent    = wo.Estimate__r.Part_Component__c;
        detail.jobType          = wo.Estimate__r.Job_Type__c;
        detail.condition        = wo.Estimate__r.Condition__c;
        detail.kms              = wo.Estimate__r.KMs__c;
        detail.partsSupplierName = wo.Estimate__r.Parts_Supplier__r?.Name;
        detail.partCode          = wo.Estimate__r.Part_Code__c;
        detail.stockNumber       = wo.Estimate__r.Stock_Number__c;
        detail.repairShopName    = wo.Estimate__r.Repair_Shop__r?.Name;
        detail.labourHours       = wo.Estimate__r.Labour_Hours__c;
        detail.labourRate        = wo.Estimate__r.Labour_Rate__c;
        detail.insuranceSource   = wo.Estimate__r.Insurance_Source__c;
        detail.capAmount         = wo.Claim__r.Application_Package__r?.Per_Claim_Limit__c;

        detail.retailPrice           = wo.Retail_Price__c;
        detail.coverageApplied       = wo.Coverage_Applied__c;
        detail.customerRepairPortion = wo.Customer_Repair_Portion__c;
        detail.shopSuppliesRetail    = wo.Shop_Supplies_Retail__c;
        detail.customerPaysPreTax    = wo.Customer_Pays__c;
        detail.taxAmount             = wo.Tax_Amount__c;
        detail.customerPaysWithTax   = wo.Total_Amount_Due__c;

        detail.partsCost        = wo.Parts_Cost__c;
        detail.labourCost       = wo.Labour_Cost__c;
        detail.shopSuppliesCost = wo.Shop_Supplies__c;
        detail.insuranceAmount  = wo.Insurance_Amount__c;
        detail.wholesaleCost    = wo.Wholesale_Cost__c;
        detail.benefitsUsed     = wo.Benefits_Used__c;
        detail.totalClaimCost   = wo.Total_Claim_Cost__c;
        detail.finalProfitLoss  = wo.Final_Profit_Loss__c;

        return detail;
    }

    // ──────────────── Repair Progress (Repairs In Progress tab) ────────────────
    // Backs repairProgressTimeline - a claim has only one active work order, so
    // this shows that single record's milestone timeline directly, not a list.

    public class RepairProgress {
        @AuraEnabled public Id workOrderId;
        @AuraEnabled public String workOrderName;
        @AuraEnabled public String currentMilestone;    // Repair_Milestone__c
        @AuraEnabled public Date vehicleReceivedDate;
        @AuraEnabled public Date repairStartedDate;
        @AuraEnabled public Date qualityCheckDate;
        @AuraEnabled public Date readyForPickupDate;
    }

    /**
     * The claim's one active (non-Voided) work order's repair milestone and
     * per-stage dates, or null if none exists yet.
     */
    @AuraEnabled
    public static RepairProgress getRepairProgressForClaim(Id claimId) {
        List<Work_Order__c> active = [
            SELECT Id, Name, Repair_Milestone__c, Vehicle_Received_Date__c,
                   Repair_Started_Date__c, Quality_Check_Date__c, Ready_For_Pickup_Date__c
            FROM Work_Order__c
            WHERE Claim__c = :claimId AND Status__c != 'Voided'
            WITH USER_MODE
            LIMIT 1
        ];
        if (active.isEmpty()) return null;

        Work_Order__c wo = active[0];
        RepairProgress rp = new RepairProgress();
        rp.workOrderId         = wo.Id;
        rp.workOrderName       = wo.Name;
        rp.currentMilestone    = wo.Repair_Milestone__c;
        rp.vehicleReceivedDate = wo.Vehicle_Received_Date__c;
        rp.repairStartedDate   = wo.Repair_Started_Date__c;
        rp.qualityCheckDate    = wo.Quality_Check_Date__c;
        rp.readyForPickupDate  = wo.Ready_For_Pickup_Date__c;
        return rp;
    }

    /**
     * Saves the Repair Milestone and/or its per-stage dates from the
     * Repairs In Progress tab - the caller passes only the Work_Order__c
     * fields it wants changed, keyed by the same Id returned by
     * getRepairProgressForClaim.
     */
    @AuraEnabled
    public static void saveRepairProgress(Work_Order__c progressUpdate) {
        updateSecured(new List<Work_Order__c>{ progressUpdate });
    }

    // ──────────────── Part Orders (Order The Parts tab) ────────────────
    // Backs the partOrderManager LWC. A claim can have more than one
    // Part_Order__c; each carries its own Ordered_Part__c lines.

    public class PartOrderGroup {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;          // PORD-#### autonumber
        @AuraEnabled public String poNumber;
        @AuraEnabled public Date expectedDelivery;
        @AuraEnabled public Id supplierId;
        @AuraEnabled public String supplierName;
        @AuraEnabled public List<OrderedPartRow> lines;
    }

    public class OrderedPartRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String partName;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public String status;
        @AuraEnabled public String description; // Part_Description__c
        @AuraEnabled public String brand;        // Brand__c
        @AuraEnabled public String condition;    // Condition__c
    }

    /** Every Part_Order__c on the claim, each with its own lines - one query, no N+1. */
    @AuraEnabled
    public static List<PartOrderGroup> getPartOrdersForClaim(Id claimId) {
        List<PartOrderGroup> groups = new List<PartOrderGroup>();
        for (Part_Order__c po : [
            SELECT Id, Name, PO_Number__c, Expected_Delivery__c, Supplier__c, Supplier__r.Name,
                   (SELECT Id, Name, Part_Name__c, Quantity__c, Status__c,
                           Part_Description__c, Brand__c, Condition__c
                    FROM Ordered_Parts__r ORDER BY CreatedDate ASC)
            FROM Part_Order__c
            WHERE Claim__c = :claimId
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ]) {
            PartOrderGroup grp = new PartOrderGroup();
            grp.id               = po.Id;
            grp.name             = po.Name;
            grp.poNumber         = po.PO_Number__c;
            grp.expectedDelivery = po.Expected_Delivery__c;
            grp.supplierId       = po.Supplier__c;
            grp.supplierName     = po.Supplier__r?.Name;
            grp.lines            = new List<OrderedPartRow>();
            for (Ordered_Part__c op : po.Ordered_Parts__r) {
                OrderedPartRow row = new OrderedPartRow();
                row.id          = op.Id;
                row.name        = op.Name;
                row.partName    = op.Part_Name__c;
                row.quantity    = op.Quantity__c;
                row.status      = op.Status__c;
                row.description = op.Part_Description__c;
                row.brand       = op.Brand__c;
                row.condition   = op.Condition__c;
                grp.lines.add(row);
            }
            groups.add(grp);
        }
        return groups;
    }

    @AuraEnabled
    public static Id createPartOrder(Id claimId, Part_Order__c partOrder) {
        partOrder.Claim__c = claimId;
        insertSecured(new List<Part_Order__c>{ partOrder });
        return partOrder.Id;
    }

    /** Claim__c is a direct shortcut alongside Part_Order__c, matching the field's own built-in intent. */
    @AuraEnabled
    public static void addOrderedPart(Id partOrderId, Id claimId, Ordered_Part__c part) {
        part.Part_Order__c = partOrderId;
        part.Claim__c       = claimId;
        insertSecured(new List<Ordered_Part__c>{ part });
    }

    @AuraEnabled
    public static void saveOrderedPartStatuses(List<Ordered_Part__c> statusUpdates) {
        updateSecured(statusUpdates);
    }

    /**
     * Commits the Edit-mode Save on one Part Order card in partOrderManager:
     * the card's own PO_Number__c/Expected_Delivery__c plus every line's
     * Part_Description__c/Brand__c/Condition__c, in one call and one
     * transaction - same "single call for the whole unit" principle as
     * saveEstimates. Callers must pass only Id plus the field(s) actually
     * edited on each record.
     */
    @AuraEnabled
    public static void savePartOrderEdits(Part_Order__c poUpdate, List<Ordered_Part__c> lineUpdates) {
        Savepoint sp = Database.setSavepoint();
        try {
            updateSecured(new List<Part_Order__c>{ poUpdate });
            if (lineUpdates != null && !lineUpdates.isEmpty()) updateSecured(lineUpdates);
        } catch (Exception ex) {
            Database.rollback(sp);
            if (ex instanceof AuraHandledException) throw ex;
            throw new AuraHandledException('Could not save part order changes: ' + ex.getMessage());
        }
    }

    /** Feeds the Supplier dropdown - Account's own lookup filter on Part_Order__c.Supplier__c is UI-only, so this enforces it server-side instead. */
    @AuraEnabled
    public static List<Account> getSupplierAccounts() {
        return [
            SELECT Id, Name
            FROM Account
            WHERE RecordType.DeveloperName = 'Supplier_Account'
            WITH USER_MODE
            ORDER BY Name
        ];
    }

    // ───────────────── One-click part ordering (Sep 25) ─────────────────
    // Now that syncEstimateChildren keeps a real Part__c under every
    // estimate with a non-zero Parts_Cost__c, the Order The Parts tab can
    // suggest ordering that exact part instead of the agent typing
    // everything by hand. Replaces the old "+ New Part Order"/"+ Add Part"
    // manual forms entirely (Osama's explicit call).

    public class OrderableSuggestion {
        @AuraEnabled public Id partId;
        @AuraEnabled public String partName;      // Part_Name__c
        @AuraEnabled public String partType;      // Part_Type__c
        @AuraEnabled public Decimal quantity;     // Quantity__c
        @AuraEnabled public Decimal partCost;     // Part_Cost__c, display only
        @AuraEnabled public Id supplierId;        // Supplier__c
        @AuraEnabled public String supplierName;
        @AuraEnabled public String estimateName;  // Estimate__r.Estimate_Name__c, for context
    }

    /**
     * Part__c records on this claim's SELECTED estimate (Is_Selected__c)
     * not yet linked to any NON-cancelled Ordered_Part__c - the suggestion
     * queue for the Order The Parts tab's one-click flow. Every estimate on
     * the claim gets its own synced Part__c (see syncEstimateChildren), but
     * only the winning scenario's part should ever be orderable, so
     * non-selected estimates' parts are excluded here. A cancelled order
     * frees its source part back up for re-ordering (a cancelled order
     * didn't happen), but any other status (Ordered/Backordered/Received)
     * keeps it off this list.
     */
    @AuraEnabled
    public static List<OrderableSuggestion> getOrderableParts(Id claimId) {
        Set<Id> alreadyOrderedPartIds = new Set<Id>();
        for (Ordered_Part__c op : [
            SELECT Part__c FROM Ordered_Part__c
            WHERE Claim__c = :claimId AND Part__c != null AND Status__c != 'Cancelled'
            WITH USER_MODE
        ]) alreadyOrderedPartIds.add(op.Part__c);

        List<OrderableSuggestion> out = new List<OrderableSuggestion>();
        for (Part__c p : [
            SELECT Id, Part_Name__c, Part_Type__c, Quantity__c, Part_Cost__c,
                   Supplier__c, Supplier__r.Name, Estimate__r.Estimate_Name__c
            FROM Part__c
            WHERE Estimate__r.Claim__c = :claimId
              AND Estimate__r.Is_Selected__c = true
            WITH USER_MODE
        ]) {
            if (alreadyOrderedPartIds.contains(p.Id)) continue;
            OrderableSuggestion s = new OrderableSuggestion();
            s.partId       = p.Id;
            s.partName     = p.Part_Name__c;
            s.partType     = p.Part_Type__c;
            s.quantity     = p.Quantity__c;
            s.partCost     = p.Part_Cost__c;
            s.supplierId   = p.Supplier__c;
            s.supplierName = p.Supplier__r?.Name;
            s.estimateName = p.Estimate__r?.Estimate_Name__c;
            out.add(s);
        }
        return out;
    }

    /**
     * One-click "order this part": in one transaction, creates a
     * Part_Order__c (Supplier__c defaulted from the Part's own Supplier__c;
     * PO_Number__c/Expected_Delivery__c left blank, filled in later), one
     * Ordered_Part__c linked back to the source Part__c (Brand__c/
     * Condition__c deliberately left blank - Part__c.Part_Type__c's
     * NEW/USED/AFTERMARKET doesn't map cleanly onto Ordered_Part__c's
     * different value sets, and guessing wrong on a real purchase order is
     * worse than leaving it for the agent to set), and - closing the loop
     * back to the work order - points the claim's active work order's
     * "Part" line (Work_Order_Line_Item__c via Claim_Line_Item__r.Line_Type__c
     * = 'Part') at the new Ordered_Part__c so Ordered_Part_Status__c shows
     * live. A no-op, not an error, if no Part line exists yet (e.g. the
     * winning estimate had $0 Parts_Cost__c).
     */
    @AuraEnabled
    public static Id orderSuggestedPart(Id claimId, Id partId) {
        Part__c part = [
            SELECT Id, Part_Name__c, Quantity__c, Supplier__c
            FROM Part__c WHERE Id = :partId
            WITH USER_MODE
        ];

        Savepoint sp = Database.setSavepoint();
        try {
            Part_Order__c po = new Part_Order__c(
                Claim__c    = claimId,
                Supplier__c = part.Supplier__c
            );
            insertSecured(new List<Part_Order__c>{ po });

            Ordered_Part__c op = new Ordered_Part__c(
                Part_Order__c = po.Id,
                Claim__c      = claimId,
                Part__c       = part.Id,
                Part_Name__c  = part.Part_Name__c,
                Quantity__c   = part.Quantity__c != null ? part.Quantity__c : 1,
                Status__c     = 'Ordered'
            );
            insertSecured(new List<Ordered_Part__c>{ op });

            List<Work_Order_Line_Item__c> partLines = [
                SELECT Id
                FROM Work_Order_Line_Item__c
                WHERE Customer_Work_Order__r.Claim__c = :claimId
                  AND Customer_Work_Order__r.Status__c != 'Voided'
                  AND Claim_Line_Item__r.Line_Type__c = 'Part'
                WITH USER_MODE
                LIMIT 1
            ];
            if (!partLines.isEmpty()) {
                updateSecured(new List<Work_Order_Line_Item__c>{
                    new Work_Order_Line_Item__c(Id = partLines[0].Id, Ordered_Part__c = op.Id)
                });
            }
            return op.Id;
        } catch (Exception ex) {
            Database.rollback(sp);
            throw new AuraHandledException('Could not order this part: ' + ex.getMessage());
        }
    }

    // ───────────────── FLS/CRUD-secured DML helpers ─────────────────
    // AccessLevel.USER_MODE makes the DML itself respect the running user's
    // object and field permissions, the write-side counterpart to WITH
    // USER_MODE on the SOQL above - the platform throws System.NoAccessException
    // rather than silently writing a value the user isn't permitted to set,
    // which is caught here and rethrown as a clear AuraHandledException.

    private static void insertSecured(List<SObject> records) {
        if (records.isEmpty()) return;
        try {
            Database.insert(records, AccessLevel.USER_MODE);
        } catch (System.NoAccessException ex) {
            throw new AuraHandledException('You do not have permission to create this type of record. Contact your administrator.');
        }
    }

    private static void updateSecured(List<SObject> records) {
        if (records.isEmpty()) return;
        try {
            Database.update(records, AccessLevel.USER_MODE);
        } catch (System.NoAccessException ex) {
            throw new AuraHandledException('You do not have permission to update one or more fields on this record. Contact your administrator.');
        }
    }

    private static void deleteSecured(List<SObject> records) {
        if (records.isEmpty()) return;
        try {
            Database.delete(records, AccessLevel.USER_MODE);
        } catch (System.NoAccessException ex) {
            throw new AuraHandledException('You do not have permission to delete this type of record. Contact your administrator.');
        }
    }

    // ──────────────── Invoice And Wrap Up: generate the invoice ───────────────

    /**
     * Called from ClaimWrapUpInvoiceTrigger when a claim's Claim_Status__c
     * changes to "Invoice And Wrap Up". Reuses the Application/Package
     * team's Invoice__c / Invoice_Line_Item__c objects (Osama's Sep 21
     * decision), bridged by the Work_Order__c and Work_Order_Line_Item__c
     * lookups added directly in Setup. Also stamps Invoice__c.Application__c
     * from Claim__r.Application__c (Osama, Sep 21) - Invoice__c's own
     * pre-existing Application_Id__c formula reads Application__r.Name, so
     * setting this one lookup populates both. Mirrors the claim's one
     * active work order (Status__c != 'Voided', matching the "only one
     * active work order per claim" rule) and its lines one-for-one, so the
     * invoice and work order agree by construction rather than needing a
     * manual fix.
     * Idempotent: a claim that re-enters this status (e.g. a status typo
     * corrected and re-saved) does not get a second invoice for the same
     * work order. Silently no-ops for a claim with no active work order
     * yet, or one that already has its invoice - this is a side effect of
     * the status save, not something that should ever block it.
     *
     * Line items ARE itemized, one per Work_Order_Line_Item__c, carrying
     * the same (gross retail) amount as its work order counterpart
     * (Osama, Sep 21). Invoice__c.Amount__c is left alone - a pre-existing,
     * active DLRS real-time rollup sums the line items onto it
     * automatically (so it naturally lands on the gross total, same
     * meaning as Work_Order__c.Total_Line_Items_Cost__c). What the
     * customer actually owes lives on the new Invoice__c.Net_Amount_Due__c,
     * a simple formula reading Work_Order__r.Total_Amount_Due__c directly -
     * mirroring how the work order itself keeps its gross total
     * (Total_Line_Items_Cost__c) and its net amount due
     * (Total_Amount_Due__c) as two separate fields, not one trying to be
     * both. No line-item math, no rollup filter, no negative line needed.
     *
     * Not @AuraEnabled - only reachable via the trigger, not this LWC - but
     * its query and DML are still secured for consistency, running as
     * whichever user saved the claim status change.
     */
    public static void generateInvoicesForWrapUp(List<Id> claimIds) {
        Map<Id, Work_Order__c> activeWorkOrderByClaim = new Map<Id, Work_Order__c>();
        for (Work_Order__c wo : [
            SELECT Id, Name, Claim__c, Claim__r.Application__c, Total_Amount_Due__c,
                   (SELECT Id FROM Invoice__r LIMIT 1),
                   (SELECT Id, Description__c, Service_Repair_Description__c, Price__c,
                           Claim_Line_Item__r.Line_Type__c, Claim_Line_Item__r.Description__c
                    FROM Customer_Work_Order_Line_Items__r)
            FROM Work_Order__c
            WHERE Claim__c IN :claimIds AND Status__c != 'Voided'
            WITH USER_MODE
        ]) {
            activeWorkOrderByClaim.put(wo.Claim__c, wo);
        }

        List<Invoice__c> invoicesToInsert = new List<Invoice__c>();
        for (Id claimId : claimIds) {
            Work_Order__c wo = activeWorkOrderByClaim.get(claimId);
            if (wo == null) continue;              // nothing to invoice yet
            if (!wo.Invoice__r.isEmpty()) continue; // already generated
            // A Reimbursement Only work order is invoiced too, deliberately.
            // It has no work order line items, so its invoice has no lines and
            // Net_Amount_Due__c is 0; the payout itself is the Reimbursement
            // claim line items. TASK-051 briefly skipped it, and Osama asked
            // for the empty $0 invoice back as the middle ground (2026-10-13).

            invoicesToInsert.add(new Invoice__c(
                Name          = 'INV-' + wo.Name,
                Claim__c      = claimId,
                Work_Order__c = wo.Id,
                Application__c = wo.Claim__r.Application__c,
                Status__c     = 'Due'
            ));
        }
        if (invoicesToInsert.isEmpty()) return;
        insertSecured(invoicesToInsert);

        List<Invoice_Line_Item__c> linesToInsert = new List<Invoice_Line_Item__c>();
        for (Invoice__c inv : invoicesToInsert) {
            Work_Order__c wo = activeWorkOrderByClaim.get(inv.Claim__c);
            for (Work_Order_Line_Item__c wl : wo.Customer_Work_Order_Line_Items__r) {
                linesToInsert.add(new Invoice_Line_Item__c(
                    Invoice__c              = inv.Id,
                    Work_Order_Line_Item__c = wl.Id,
                    // Osama, 2026-10-09: Name was never set here. It is a TEXT
                    // name field, not an auto number, so every invoice line
                    // this trigger created showed its record id instead of a
                    // business name. It takes the same value Description__c
                    // takes, from the same source, so the two stay consistent
                    // by construction: "Engine", "Labour", "Shop supplies".
                    Name                    = invoiceLineName(wl),
                    // Plain text, not the rich text field: that one stores
                    // "Oil &amp; fluids" for a supply named "Oil & fluids".
                    Description__c          = lineDescription(wl),
                    Repair_Charge_Amount__c = wl.Price__c
                ));
            }
        }
        if (!linesToInsert.isEmpty()) insertSecured(linesToInsert);
    }

    /**
     * The plain-text description of a work order line, for anything a person
     * reads: the Approved Repairs table, the work order PDF, and the invoice
     * line's Name and Description.
     *
     * Work_Order_Line_Item__c.Description__c is type Html, a RICH TEXT field.
     * Salesforce HTML-encodes plain text written into one, so a shop supply
     * named "Oil & fluids" is stored there as "Oil &amp; fluids" and renders
     * with the entity visible (Osama, 2026-10-09). Service_Repair_Description__c
     * is a plain TextArea that createWorkOrder sets from the SAME source in the
     * same statement, so it carries the identical text without the encoding.
     *
     * Reading the plain field is therefore strictly better, and this exists in
     * one place so the four readers cannot disagree again. The Html field is
     * still written exactly as before; nothing about the data model changed.
     *
     * The preference order keeps the behaviour the earlier tests pinned, that
     * a line's OWN label beats its claim line item's more generic one. Only
     * the source of that own label changed, from the rich text field to its
     * plain twin.
     */
    public static String lineDescription(Work_Order_Line_Item__c wl) {
        if (wl == null) return null;
        // 1. The plain twin. Present on every record createWorkOrder makes.
        if (String.isNotBlank(wl.Service_Repair_Description__c)) {
            return wl.Service_Repair_Description__c.trim();
        }
        // 2. Records that predate that field still carry their own label in
        //    the rich text one, so decode it rather than skipping it.
        String ownLabel = htmlToPlainText(wl.Description__c);
        if (String.isNotBlank(ownLabel)) return ownLabel;
        // 3. Last resort, the claim line item's description.
        return String.isBlank(wl.Claim_Line_Item__r?.Description__c)
            ? null
            : wl.Claim_Line_Item__r.Description__c.trim();
    }

    /**
     * Turns the stored markup of a rich text field back into the text a person
     * typed. Line breaks become newlines before tags are dropped, so two
     * paragraphs do not run together into one word, and entities are decoded
     * LAST, after tag removal, so that a literal "&lt;" in the content cannot
     * become a tag the stripper then eats.
     */
    private static String htmlToPlainText(String html) {
        if (String.isBlank(html)) return null;
        String plain = html
            .replaceAll('(?i)<br\\s*/?>', '\n')
            .replaceAll('(?i)</(p|div|li)\\s*>', '\n')
            .replaceAll('<[^>]*>', '')
            .unescapeHtml4()
            .trim();
        return String.isBlank(plain) ? null : plain;
    }

    /**
     * The business-facing name for an invoice line, derived from the work
     * order line it was generated from.
     *
     * Deliberately the SAME source Description__c uses, so the two can never
     * say different things about one line, which is what Osama asked for on
     * 2026-10-09. The work order line's own description already carries the
     * specific child record's name ("Engine" rather than "Part"), because
     * TASK-049 names each line after its real child, so there is no mapping
     * table to invent here: the specificity is already in the data.
     *
     * The fallbacks exist only so a line can never go back to showing a record
     * id. Line_Type__c is the generic type, and a blank name is never written.
     * Name is a Text field capped at 80 characters, so a long part description
     * is truncated rather than failing the whole invoice.
     */
    private static String invoiceLineName(Work_Order_Line_Item__c wl) {
        String name = lineDescription(wl);
        if (String.isBlank(name)) name = wl.Claim_Line_Item__r?.Line_Type__c;
        if (String.isBlank(name)) name = 'Invoice Line Item';
        name = name.trim();
        return name.length() > 80 ? name.left(80) : name;
    }
}