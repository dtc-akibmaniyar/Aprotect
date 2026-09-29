import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPartOrdersForClaim from '@salesforce/apex/ClaimEstimateService.getPartOrdersForClaim';
import getOrderableParts from '@salesforce/apex/ClaimEstimateService.getOrderableParts';
import orderSuggestedPart from '@salesforce/apex/ClaimEstimateService.orderSuggestedPart';
import saveOrderedPartStatuses from '@salesforce/apex/ClaimEstimateService.saveOrderedPartStatuses';
import savePartOrderEdits from '@salesforce/apex/ClaimEstimateService.savePartOrderEdits';

const STATUS_OPTIONS = [
    { label: 'Ordered', value: 'Ordered' },
    { label: 'Backordered', value: 'Backordered' },
    { label: 'Received', value: 'Received' },
    { label: 'Cancelled', value: 'Cancelled' }
];
const BRAND_OPTIONS = ['OEM (Original Equipment Manufacturer)', 'Aftermarket', 'Remanufactured OEM']
    .map((v) => ({ label: v, value: v }));
const CONDITION_OPTIONS = [
    'New', 'Used', 'Refurbished', 'Rebuilt/Remanufactured', 'Salvage/LKQ', 'Take-off', 'Repair Shop Supplied'
].map((v) => ({ label: v, value: v }));

/**
 * Order The Parts tab (Sep 25 redesign): the claim's Part__c records
 * (populated by ClaimEstimateService.syncEstimateChildren from the
 * winning estimate's own scalar fields) are suggested for one-click
 * ordering instead of typed in by hand - "Order This Part" creates one
 * Part_Order__c + one Ordered_Part__c in a single click and links the
 * work order's own Part line to it. Replaces the old manual "+ New Part
 * Order" / "+ Add Part" forms entirely (Osama's explicit call - no
 * free-text fallback). Existing Part Orders and their lines are still
 * shown below, with inline Status editing on each line always available,
 * plus an Edit/Save/Cancel toggle per card (Sep 25) for PO Number,
 * Expected Delivery, and each line's Description/Brand/Condition.
 */
export default class PartOrderManager extends NavigationMixin(LightningElement) {
    @api recordId; // the Claim__c Id

    statusOptions = STATUS_OPTIONS;
    brandOptions = BRAND_OPTIONS;
    conditionOptions = CONDITION_OPTIONS;
    partOrders = [];
    suggestions = [];
    isLoading = true;
    orderingPartId = null;

    connectedCallback() {
        this.loadSuggestions();
        this.loadPartOrders();
    }

    async loadSuggestions() {
        try {
            this.suggestions = await getOrderableParts({ claimId: this.recordId });
        } catch (error) {
            this.showError('Could Not Load Suggested Parts', error);
        }
    }

    async loadPartOrders() {
        this.isLoading = true;
        try {
            const groups = await getPartOrdersForClaim({ claimId: this.recordId });
            this.partOrders = groups.map((g) => ({ ...g, isEditing: false, draft: null, lines: g.lines.map((l) => ({ ...l })) }));
        } catch (error) {
            this.showError('Could Not Load Part Orders', error);
        } finally {
            this.isLoading = false;
        }
    }

    get hasPartOrders() {
        return this.partOrders.length > 0;
    }

    get hasSuggestions() {
        return this.suggestions.length > 0;
    }

    // ───────────────── One-click ordering ─────────────────

    async handleOrderPart(event) {
        const partId = event.currentTarget.dataset.partId;
        this.orderingPartId = partId;
        try {
            await orderSuggestedPart({ claimId: this.recordId, partId });
            this.dispatchEvent(new ShowToastEvent({ title: 'Part Ordered', variant: 'success' }));
            await Promise.all([this.loadSuggestions(), this.loadPartOrders()]);
        } catch (error) {
            this.showError('Could Not Order This Part', error, 'sticky');
        } finally {
            this.orderingPartId = null;
        }
    }

    // ───────────────── Inline status edit ─────────────────

    async handleStatusChange(event) {
        const lineId = event.target.dataset.lineId;
        const poId = event.target.dataset.poId;
        const newStatus = event.target.value;

        // optimistic local update - no full re-fetch needed for a single-field flip
        this.partOrders = this.partOrders.map((g) =>
            g.id !== poId
                ? g
                : { ...g, lines: g.lines.map((l) => (l.id === lineId ? { ...l, status: newStatus } : l)) }
        );

        try {
            await saveOrderedPartStatuses({ statusUpdates: [{ Id: lineId, Status__c: newStatus }] });
            // A cancellation frees the source part back up for re-ordering.
            if (newStatus === 'Cancelled') await this.loadSuggestions();
        } catch (error) {
            this.showError('Could Not Update Status', error, 'sticky');
            await this.loadPartOrders(); // revert to server truth on failure
        }
    }

    // ───────────────── Part Order card inline edit ─────────────────

    handleEditPartOrder(event) {
        const poId = event.currentTarget.dataset.poId;
        this.partOrders = this.partOrders.map((g) =>
            g.id !== poId
                ? g
                : {
                      ...g,
                      isEditing: true,
                      draft: {
                          poNumber: g.poNumber,
                          expectedDelivery: g.expectedDelivery,
                          lines: g.lines.map((l) => ({ ...l }))
                      }
                  }
        );
    }

    handleCancelEdit(event) {
        const poId = event.currentTarget.dataset.poId;
        this.partOrders = this.partOrders.map((g) =>
            g.id !== poId
                ? g
                : {
                      ...g,
                      isEditing: false,
                      poNumber: g.draft.poNumber,
                      expectedDelivery: g.draft.expectedDelivery,
                      lines: g.draft.lines,
                      draft: null
                  }
        );
    }

    handlePoFieldChange(event) {
        const poId = event.currentTarget.dataset.poId;
        const field = event.currentTarget.dataset.field;
        const value = event.target.value;
        this.partOrders = this.partOrders.map((g) => (g.id !== poId ? g : { ...g, [field]: value }));
    }

    handleLineFieldChange(event) {
        const poId = event.currentTarget.dataset.poId;
        const lineId = event.currentTarget.dataset.lineId;
        const field = event.currentTarget.dataset.field;
        const value = event.detail ? event.detail.value : event.target.value;
        this.partOrders = this.partOrders.map((g) =>
            g.id !== poId
                ? g
                : { ...g, lines: g.lines.map((l) => (l.id !== lineId ? l : { ...l, [field]: value })) }
        );
    }

    async handleSaveEdit(event) {
        const poId = event.currentTarget.dataset.poId;
        const group = this.partOrders.find((g) => g.id === poId);
        if (!group) return;
        try {
            await savePartOrderEdits({
                poUpdate: {
                    Id: poId,
                    PO_Number__c: group.poNumber || null,
                    Expected_Delivery__c: group.expectedDelivery || null
                },
                lineUpdates: group.lines.map((l) => ({
                    Id: l.id,
                    Part_Description__c: l.description || null,
                    Brand__c: l.brand || null,
                    Condition__c: l.condition || null
                }))
            });
            this.partOrders = this.partOrders.map((g) => (g.id !== poId ? g : { ...g, isEditing: false, draft: null }));
            this.dispatchEvent(new ShowToastEvent({ title: 'Part Order Saved', variant: 'success' }));
        } catch (error) {
            this.showError('Could Not Save Part Order', error, 'sticky');
        }
    }

    navigateToRecord(event, objectApiName) {
        event.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: event.currentTarget.dataset.id,
                objectApiName,
                actionName: 'view'
            }
        });
    }

    handlePartOrderClick(event) {
        this.navigateToRecord(event, 'Part_Order__c');
    }

    handlePartClick(event) {
        this.navigateToRecord(event, 'Ordered_Part__c');
    }

    showError(title, error, mode) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message: (error && error.body && error.body.message) || 'An unexpected error occurred.',
                variant: 'error',
                mode: mode || 'dismissable'
            })
        );
    }
}