import { LightningElement, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';
import ACCOUNT_ID from '@salesforce/schema/User.AccountId';
import ACCOUNT_NAME from '@salesforce/schema/Account.Name';
import DEALER_LOGO from '@salesforce/schema/Account.DealerLogo__c';

export default class DealerWelcomeCard extends LightningElement {
    userId = USER_ID;
    accountId;
    dealerName;
    dealerLogoUrl;
    isLoading = true;

    // Step 1: Get the current user's AccountId
    @wire(getRecord, { recordId: '$userId', fields: [ACCOUNT_ID] })
    wiredUser({ error, data }) {
        if (data) {
            this.accountId = getFieldValue(data, ACCOUNT_ID);
        } else if (error) {
            console.error('Error fetching user account:', error);
        }
    }

    // Step 2: Fetch Account details once accountId is known
    @wire(getRecord, { recordId: '$accountId', fields: [ACCOUNT_NAME, DEALER_LOGO] })
    wiredAccount({ error, data }) {
        if (data) {
            this.dealerName = getFieldValue(data, ACCOUNT_NAME);

            // DealerLogo__c is a Rich Text Area that stores an <img> tag using
            // the Salesforce ImageServer URL pattern:
            //   <img src="/servlet/servlet.ImageServer?id=<docId>&amp;oid=<orgId>">
            // Extract the src attribute value and decode the HTML entity &amp; → &
            const richTextLogo = getFieldValue(data, DEALER_LOGO);
            if (richTextLogo) {
                const srcMatch = richTextLogo.match(/src="([^"]+)"/);
                this.dealerLogoUrl = srcMatch
                    ? srcMatch[1].replace(/&amp;/g, '&')
                    : null;
            }

            this.isLoading = false;
        } else if (error) {
            console.error('Error fetching account details:', error);
            this.isLoading = false;
        }
    }
}