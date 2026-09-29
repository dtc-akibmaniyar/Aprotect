import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRepairProgressForClaim from '@salesforce/apex/ClaimEstimateService.getRepairProgressForClaim';
import saveRepairProgress from '@salesforce/apex/ClaimEstimateService.saveRepairProgress';

const MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

const STAGES = [
    { key: 'Vehicle Received at Shop', label: 'Vehicle received at shop', dateField: 'vehicleReceivedDate', apiField: 'Vehicle_Received_Date__c' },
    { key: 'Repair In Progress', label: 'Repair in progress', dateField: 'repairStartedDate', apiField: 'Repair_Started_Date__c' },
    { key: 'Quality Check', label: 'Quality check', dateField: 'qualityCheckDate', apiField: 'Quality_Check_Date__c' },
    { key: 'Ready for Customer Pickup', label: 'Ready for customer pickup', dateField: 'readyForPickupDate', apiField: 'Ready_For_Pickup_Date__c' }
];

const MILESTONE_OPTIONS = STAGES.map((s) => ({ label: s.label, value: s.key }));

function formatDate(isoDate) {
    if (!isoDate) {
        return null;
    }
    const [year, month, day] = isoDate.split('-').map(Number);
    return `${MONTH_NAMES[month - 1]} ${day}, ${year}`;
}

/**
 * A claim has only one active work order, so its milestone is shown directly
 * as a timeline (Vehicle Received -> Repair In Progress -> Quality Check ->
 * Ready for Pickup), not as a filtered related list. Each stage's date field
 * (e.g. Repair_Started_Date__c) records when that stage was reached, not a
 * future target, so the in-progress stage's subtext reads "Started <date>".
 */
export default class RepairProgressTimeline extends NavigationMixin(LightningElement) {
    @api recordId; // the Claim__c Id

    milestoneOptions = MILESTONE_OPTIONS;
    isLoading = true;
    isEditing = false;
    isSaving = false;
    progress = null;
    stages = [];
    draftMilestone = null;
    draftDates = {};

    connectedCallback() {
        this.loadProgress();
    }

    async loadProgress() {
        this.isLoading = true;
        try {
            this.progress = await getRepairProgressForClaim({ claimId: this.recordId });
            this.buildStages();
        } catch (error) {
            this.progress = null;
            this.stages = [];
            this.showError('Could Not Load Repair Progress', error);
        } finally {
            this.isLoading = false;
        }
    }

    buildStages() {
        if (!this.progress) {
            this.stages = [];
            return;
        }
        const currentIndex = STAGES.findIndex((s) => s.key === this.progress.currentMilestone);
        this.stages = STAGES.map((stage, index) => {
            const dateValue = this.progress[stage.dateField];
            let state;
            let subtext;
            if (currentIndex === -1) {
                state = 'not-started';
                subtext = 'Not started';
            } else if (index < currentIndex) {
                state = 'done';
                subtext = formatDate(dateValue) || 'Completed';
            } else if (index === currentIndex) {
                state = 'current';
                subtext = dateValue ? `Started ${formatDate(dateValue)}` : 'In Progress';
            } else {
                state = 'not-started';
                subtext = 'Not started';
            }
            return {
                key: stage.key,
                label: stage.label,
                subtext,
                dotClass: `tl-dot tl-dot_${state}`,
                itemClass: `tl-item tl-item_${state}`
            };
        });
    }

    get hasActiveWorkOrder() {
        return !!this.progress;
    }

    get editableStages() {
        return STAGES.map((stage) => ({
            key: stage.key,
            label: stage.label,
            apiField: stage.apiField,
            value: this.draftDates[stage.apiField]
        }));
    }

    // ───────────────── Edit / Save / Cancel ─────────────────

    handleEdit() {
        this.draftMilestone = this.progress.currentMilestone;
        this.draftDates = STAGES.reduce((acc, stage) => {
            acc[stage.apiField] = this.progress[stage.dateField];
            return acc;
        }, {});
        this.isEditing = true;
    }

    handleCancelEdit() {
        this.isEditing = false;
    }

    handleMilestoneChange(event) {
        this.draftMilestone = event.detail.value;
    }

    handleDateChange(event) {
        const field = event.currentTarget.dataset.field;
        this.draftDates = { ...this.draftDates, [field]: event.target.value || null };
    }

    async handleSaveEdit() {
        this.isSaving = true;
        try {
            await saveRepairProgress({
                progressUpdate: {
                    Id: this.progress.workOrderId,
                    Repair_Milestone__c: this.draftMilestone,
                    ...this.draftDates
                }
            });
            this.isEditing = false;
            this.dispatchEvent(new ShowToastEvent({ title: 'Repair Progress Saved', variant: 'success' }));
            await this.loadProgress();
        } catch (error) {
            this.showError('Could Not Save Repair Progress', error, 'sticky');
        } finally {
            this.isSaving = false;
        }
    }

    // ───────────────── Work Order link ─────────────────

    handleWorkOrderClick(event) {
        event.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.progress.workOrderId,
                objectApiName: 'Work_Order__c',
                actionName: 'view'
            }
        });
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