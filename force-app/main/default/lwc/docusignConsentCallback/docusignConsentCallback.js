import { LightningElement, track } from 'lwc';
import sendEnvelopeWithTabs from
    '@salesforce/apex/DocusignApplicationService.sendEnvelopeWithTabs';

export default class DocusignConsentCallback extends LightningElement {
    @track loading = true;
    @track message = 'Finalizing authorization...';

    connectedCallback() {
        const params = new URLSearchParams(window.location.search);
        const status = params.get('dfsle__status');
        const state = params.get('state');

        if (status !== 'Success' || !state) {
            this.message = 'Authorization failed.';
            this.loading = false;
            return;
        }

        // 🔁 Decode original transaction
        const decodedState = JSON.parse(
            decodeURIComponent(state)
        );

        // 🔄 Resume original transaction
        sendEnvelopeWithTabs({
            applicationId: decodedState.applicationId,
            contentVersionIds: decodedState.contentVersionIds
        })
        .then(() => {
            this.message =
                'Documents sent successfully. Redirecting...';

            setTimeout(() => {
                window.location.assign(
                    `/s/detail/${decodedState.applicationId}`
                );
            }, 1500);
        })
        .catch(() => {
            this.message =
                'Authorization completed, but sending failed.';
        })
        .finally(() => {
            this.loading = false;
        });
    }
}