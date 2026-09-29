import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import CreateClaimModal from 'c/createClaimModal';

/**
 * Thin quick-action launcher for "Create Claim" on Application__c. Exists
 * only because the quick-action dialog frame's own width can't be widened
 * from inside an LWC (that chrome lives outside the component's shadow
 * boundary) - opening the real content as a lightning/modal instead (same
 * pattern repairPriceScenarios uses via claimEstimatesList) is the only
 * reliable way to get a wide "large" dialog. This component shows nothing
 * of its own; it opens the modal immediately and closes the outer
 * quick-action dialog once the modal is dismissed either way.
 *
 * Same recordId-timing caveat as the original single-component build: a
 * quick-action screen doesn't reliably have @api recordId populated by the
 * time connectedCallback runs, so this uses a setter rather than reading
 * recordId directly in connectedCallback.
 *
 * Two things tried so far for the outer quick-action dialog's leftover dark
 * backdrop (Osama caught this - visible both before and after the fix
 * below, so it isn't purely a close-timing issue): closing after awaiting
 * the modal's close, and closing synchronously right after triggering
 * open() with no render at all (an empty template). Neither fully cleared
 * it. Current attempt: give this launcher a brief real render (a spinner)
 * instead of a wholly empty template, and let one microtask pass after
 * calling open() before closing, in case Salesforce's own panel manager
 * doesn't clean up its backdrop correctly when a completely empty
 * component is opened and closed in the same tick. Flag to Osama if this
 * still doesn't fully resolve it - this exact "quick action launcher opens
 * a lightning/modal" combination has no documented precedent found either
 * in this codebase or in Salesforce's own docs, so this remains somewhat
 * experimental.
 */
export default class CreateClaimAction extends LightningElement {
    _recordId;
    _opened = false;

    @api
    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.openModal();
        }
    }
    get recordId() {
        return this._recordId;
    }

    async openModal() {
        if (this._opened) return;
        this._opened = true;
        const openPromise = CreateClaimModal.open({
            size: 'large',
            label: 'Create Claim',
            applicationId: this.recordId
        });
        // Let the modal actually start rendering before tearing down the
        // outer quick-action dialog.
        await Promise.resolve();
        this.dispatchEvent(new CloseActionScreenEvent());
        await openPromise;
    }
}