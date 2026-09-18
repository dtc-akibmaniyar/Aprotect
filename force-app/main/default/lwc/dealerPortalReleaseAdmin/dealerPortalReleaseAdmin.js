import { LightningElement, track } from 'lwc';

import getReleases from '@salesforce/apex/CatalogueReleaseService.getReleases';
import getLinkedGroups from '@salesforce/apex/CatalogueReleaseService.getLinkedGroups';
import createDraft from '@salesforce/apex/CatalogueReleaseService.createDraft';
import updateDraft from '@salesforce/apex/CatalogueReleaseService.updateDraft';
import deleteDraft from '@salesforce/apex/CatalogueReleaseService.deleteDraft';
import publishRelease from '@salesforce/apex/CatalogueReleaseService.publish';
import unpublishRelease from '@salesforce/apex/CatalogueReleaseService.unpublish';
import supersedeRelease from '@salesforce/apex/CatalogueReleaseService.supersede';

/**
 * dealerPortalReleaseAdmin
 *
 * Consolidated catalogue-release admin (change-plan §09.2 / §11 Phase 5 [L]).
 * Built over the CatalogueReleaseService surface (P5-A) — pure data lifecycle:
 * list Draft/Published/Superseded releases, author Drafts, publish on the
 * effective date, supersede/unpublish, and inspect the plan-type families
 * (Package_Group__c) linked to each release.
 *
 * Deletion policy note (plan §09.3): the legacy near-identical admin LWCs
 * (dealerPortalAdminMarkup, dealerPortalAdminUnifiedMarkup, etc.) are NOT
 * deleted in this phase — that happens after admin UAT. This component is the
 * "releases" concern of the one-LWC-per-concern consolidation.
 */
export default class DealerPortalReleaseAdmin extends LightningElement {
    @track releases = [];
    @track groupsByRelease = {};
    @track expandedId;
    @track isLoading = true;
    @track isSaving = false;
    @track error;

    // New/edit Draft form state
    @track showForm = false;
    @track editingId;
    @track form = { name: '', releaseNumber: '', effectiveDate: '', notes: '' };

    connectedCallback() {
        this.loadReleases();
    }

    async loadReleases() {
        this.isLoading = true;
        this.error = undefined;
        try {
            const releases = await getReleases();
            releases.forEach((r) => {
                r.groupLabel = r.groupCount + ' plan type(s)';
            });
            this.releases = releases;
            this.refreshRowFlags();
        } catch (e) {
            this.error = this.extractError(e);
        } finally {
            this.isLoading = false;
        }
    }

    // ── Row action dispatch ────────────────────────────────────────────────

    handleAction(event) {
        const action = event.currentTarget.dataset.action;
        const id = event.currentTarget.dataset.id;
        const rel = this.releases.find((r) => r.id === id);
        if (!rel) {
            return;
        }
        if (action === 'edit') {
            this.openEditDraft(rel);
        } else if (action === 'publish') {
            this.publish(rel);
        } else if (action === 'delete') {
            this.removeDraft(rel);
        } else if (action === 'unpublish') {
            this.unpublish(rel);
        } else if (action === 'supersede') {
            this.supersede(rel);
        } else if (action === 'groups') {
            this.toggleGroups(rel);
        }
    }

    // ── Draft authoring ────────────────────────────────────────────────────

    openNewDraft() {
        this.editingId = undefined;
        this.form = { name: '', releaseNumber: '', effectiveDate: '', notes: '' };
        this.showForm = true;
    }

    openEditDraft(rel) {
        this.editingId = rel.id;
        this.form = {
            name: rel.name || '',
            releaseNumber: rel.releaseNumber || '',
            effectiveDate: rel.effectiveDate || '',
            notes: rel.notes || ''
        };
        this.showForm = true;
    }

    closeForm() {
        this.showForm = false;
        this.editingId = undefined;
    }

    handleInput(event) {
        const field = event.target.dataset.field;
        this.form[field] = event.target.value;
    }

    async saveDraft() {
        this.isSaving = true;
        this.error = undefined;
        try {
            if (this.editingId) {
                await updateDraft({
                    releaseId: this.editingId,
                    name: this.form.name,
                    releaseNumber: this.form.releaseNumber,
                    effectiveDate: this.form.effectiveDate,
                    notes: this.form.notes
                });
            } else {
                await createDraft({
                    name: this.form.name,
                    releaseNumber: this.form.releaseNumber,
                    effectiveDate: this.form.effectiveDate,
                    notes: this.form.notes
                });
            }
            this.showForm = false;
            this.editingId = undefined;
            await this.loadReleases();
        } catch (e) {
            this.error = this.extractError(e);
        } finally {
            this.isSaving = false;
        }
    }

    async removeDraft(rel) {
        this.error = undefined;
        try {
            await deleteDraft({ releaseId: rel.id });
            await this.loadReleases();
        } catch (e) {
            this.error = this.extractError(e);
        }
    }

    // ── Lifecycle transitions ──────────────────────────────────────────────

    async publish(rel) {
        this.error = undefined;
        try {
            await publishRelease({ releaseId: rel.id });
            await this.loadReleases();
        } catch (e) {
            this.error = this.extractError(e);
        }
    }

    async unpublish(rel) {
        this.error = undefined;
        try {
            await unpublishRelease({ releaseId: rel.id });
            await this.loadReleases();
        } catch (e) {
            this.error = this.extractError(e);
        }
    }

    async supersede(rel) {
        this.error = undefined;
        try {
            await supersedeRelease({ releaseId: rel.id });
            await this.loadReleases();
        } catch (e) {
            this.error = this.extractError(e);
        }
    }

    // ── Linked plan types ──────────────────────────────────────────────────

    async toggleGroups(rel) {
        if (this.expandedId === rel.id) {
            this.expandedId = undefined;
        } else {
            this.expandedId = rel.id;
        }
        this.refreshRowFlags();
        if (!this.groupsByRelease[rel.id]) {
            try {
                const rows = await getLinkedGroups({ releaseId: rel.id });
                rows.forEach((g) => {
                    g.activeLabel = g.active ? 'active' : 'inactive';
                });
                this.groupsByRelease[rel.id] = rows;
            } catch (e) {
                this.error = this.extractError(e);
            }
        }
    }

    refreshRowFlags() {
        this.releases.forEach((r) => {
            r.isDraft = r.status === 'Draft';
            r.isPublished = r.status === 'Published';
            r.isExpanded = r.id === this.expandedId;
        });
    }

    get expandButtonLabel() {
        return this.expandedId ? 'Hide plan types' : 'Plan types';
    }

    get expandIconName() {
        return this.expandedId ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get groupRows() {
        const rows = this.groupsByRelease[this.expandedId];
        return rows && rows.length ? rows : [];
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    get hasReleases() {
        return this.releases.length > 0;
    }

    extractError(e) {
        if (e && e.body && e.body.message) {
            return e.body.message;
        }
        if (e && e.message) {
            return e.message;
        }
        return 'An unexpected error occurred.';
    }
}