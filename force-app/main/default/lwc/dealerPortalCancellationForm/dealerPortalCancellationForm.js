import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { CurrentPageReference } from 'lightning/navigation';
import getVehicleInfoForCancellation from '@salesforce/apex/ApplicationCancellationController.getVehicleInfoForCancellation';
import getPrivacyPolicies from '@salesforce/apex/ApplicationCancellationController.getPolicies';
import savePoliciesAndCancel from '@salesforce/apex/ApplicationCancellationController.savePoliciesAndCancel';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class DealerPortalCancellationForm extends NavigationMixin(LightningElement) {
    @track applicationId;
    @track quoteId;
    @track vehicleName = '';
    @track vehicleVIN = '';
    @track vehicleOdometer = '';
    @track vehiclePrice = '';

    @track policyAccepted = false;     // for cancellation policy (if you still use it)
    @track privacyAccepted = false;    // overall flag (all privacy policies accepted)
    @track privacyPolicies = [];       // list of privacy policies

    @track isLoading = true;
    @track error;

    @wire(CurrentPageReference)
    getPageReferenceParameters(currentPageReference) {
        if (currentPageReference) {
            const state = currentPageReference.state || {};
            this.applicationId = state.c__appId || state.appId;
            this.quoteId = state.c__quoteId || state.quoteId;

            if (this.applicationId || this.quoteId) {
                this.loadVehicleInfo(this.applicationId || this.quoteId);
            }
        }
    }

    connectedCallback() {
        // Load privacy policies
        this.loadPrivacyPolicies();

        // Parse URL params as fallback
        const urlParams = new URLSearchParams(window.location.search);
        if (!this.applicationId) {
            this.applicationId = urlParams.get('appId') || urlParams.get('c__appId');
        }
        if (!this.quoteId) {
            this.quoteId = urlParams.get('quoteId') || urlParams.get('c__quoteId');
        }

        if (this.applicationId || this.quoteId) {
            this.loadVehicleInfo(this.applicationId || this.quoteId);
        } else {
            this.isLoading = false;
            this.error = 'No application ID provided';
        }
    }

    async loadVehicleInfo(id) {
        // Accept either `applicationId` or `quoteId` as the application id parameter
        const applicationIdToUse = id || this.applicationId || this.quoteId;
        if (!applicationIdToUse) {
            this.error = 'No application ID provided';
            return;
        }

        try {
            this.isLoading = true;
            this.error = null;

            const result = await getVehicleInfoForCancellation({
                applicationId: applicationIdToUse
            });

            if (result) {
                this.vehicleName = result.vehicleName || '';
                this.vehicleVIN = result.vehicleVIN || '';
                this.vehicleOdometer = result.vehicleOdometer || '';
                this.vehiclePrice = result.vehiclePrice || '';
            }
        } catch (error) {
            this.error =
                error.body?.message ||
                error.message ||
                'Error loading vehicle information';
            // eslint-disable-next-line no-console
            console.error('Error loading vehicle info:', error);
        } finally {
            this.isLoading = false;
        }
    }

    async loadPrivacyPolicies() {
    try {
        const result = await getPrivacyPolicies();

        // Helpful debug to see what Apex is really returning
        // (Open browser DevTools > Console to see it)
        // eslint-disable-next-line no-console
        console.log('getPrivacyPolicies result: ', JSON.stringify(result));

        // Normalize to an array in case Apex ever returns a single object
        const policies = Array.isArray(result)
            ? result
            : result
            ? [result]
            : [];

        this.privacyPolicies = policies.map((policy, index) => {
            return {
                ...policy,
                checkboxDomId: `privacy-accept-${index}`, // unique id for label "for"
                accepted: false
            };
        });

        this.privacyAccepted =
            this.privacyPolicies.length > 0 &&
            this.privacyPolicies.every((p) => p.accepted);
    } catch (err) {
        // eslint-disable-next-line no-console
        console.error('Error loading privacy policies: ', err);
        this.error = 'Error loading privacy policy text';
    }
}

    handlePolicyCheck(event) {
        this.policyAccepted = event.target.checked;
    }

    handlePrivacyCheck(event) {
        const policyId = event.target.dataset.id;
        const checked = event.target.checked;

        // Update the single policy's accepted state
        this.privacyPolicies = this.privacyPolicies.map((policy) => {
            if (policy.Id === policyId) {
                return { ...policy, accepted: checked };
            }
            return policy;
        });

        // Update overall flag (all privacy policies accepted)
        this.privacyAccepted =
            this.privacyPolicies.length > 0 &&
            this.privacyPolicies.every((p) => p.accepted);
    }

    async handleCancelApplication() {
        // Save accepted policies and mark application as canceled
        try {
            this.isLoading = true;
            this.error = null;

            const payload = this.privacyPolicies.map((p) => ({
                Name: p.Name,
                policyText: p.Policy_Text__c,
                privacyTermsAccepted: !!p.accepted
            }));

            await savePoliciesAndCancel({ applicationId: this.applicationId || this.quoteId, policies: payload });

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Application cancelled and policy records saved.',
                    variant: 'success'
                })
            );

            // Navigate after successful cancellation: to Quotes page if quoteId present, otherwise Application list
            if (this.quoteId) {
                this[NavigationMixin.Navigate]({
                    type: 'comm__namedPage',
                    attributes: {
                        pageName: 'quotes'
                    }
                });
            } else {
                this[NavigationMixin.Navigate]({
                    type: 'standard__objectPage',
                    attributes: {
                        objectApiName: 'Application__c',
                        actionName: 'list'
                    }
                });
            }

            // Optionally you could navigate away or refresh the page here
        } catch (err) {
            // eslint-disable-next-line no-console
            console.error('Error saving policies/cancelling application:', err);
            const msg = err.body?.message || err.message || 'Unknown error';
            this.error = msg;
            this.dispatchEvent(
                new ShowToastEvent({ title: 'Error', message: msg, variant: 'error' })
            );
        } finally {
            this.isLoading = false;
        }
    }
    handlecancelCancellation(){
        // Navigate to Application__c list view on cancel
        if (this.quoteId) {
            this[NavigationMixin.Navigate]({
                type: 'comm__namedPage',
                attributes: {
                    pageName: 'quotes'
                }
            });
        } else {
            this[NavigationMixin.Navigate]({
                type: 'standard__objectPage',
                attributes: {
                    objectApiName: 'Application__c',
                    actionName: 'list'
                }
            });
        }
    }

    // Computed property used by the template to enable/disable the Save button.
    // Save is enabled only when there is at least one privacy policy and
    // all privacy policy checkboxes are checked.
    get disableSaveButton() {
        return !(
            this.privacyPolicies &&
            this.privacyPolicies.length > 0 &&
            this.privacyPolicies.every((p) => p.accepted)
        );
    }
}