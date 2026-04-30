import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getApplicationSummaryData from '@salesforce/apex/ApplicationSummaryController.getApplicationSummaryData';
import generateAndAttachPDF from '@salesforce/apex/ApplicationSummaryController.generateAndAttachPDF';

// Define fields to retrieve
const FIELDS = [
    'Application__c.Package_Plan_Type__r.Name',
    'Application__c.Package__r.Name',
    'Application__c.Package_Tier__r.Name',
    'Application__c.Package_Term__r.Name'
];

export default class ApplicationSummaryLWC extends LightningElement {
    @api recordId;
    @track applicationData;
    @track includedOptions = [];
    @track optionalOptions = [];
    @track isLoading = false;
    @track error;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    application;

    // Get complete application data when component loads
    connectedCallback() {
        this.loadApplicationData();
    }

    async loadApplicationData() {
        this.isLoading = true;
        try {
            const result = await getApplicationSummaryData({ applicationId: this.recordId });
            this.applicationData = result.application;
            this.includedOptions = result.includedOptions || [];
            this.optionalOptions = result.optionalOptions || [];
            this.error = undefined;
        } catch (error) {
            this.error = error;
            this.applicationData = null;
            console.error('Error loading application data:', error);
        } finally {
            this.isLoading = false;
        }
    }

    // Generate PDF and attach to application record
    async handleGeneratePDF() {
        this.isLoading = true;
        try {
            const contentVersionId = await generateAndAttachPDF({ applicationId: this.recordId });
            
            this.showToast(
                'Success',
                'PDF generated and attached successfully!',
                'success'
            );
            
            // Refresh the page to show the new file
            window.location.reload();
            
        } catch (error) {
            this.showToast(
                'Error',
                'Failed to generate PDF: ' + error.body.message,
                'error'
            );
            console.error('PDF generation error:', error);
        } finally {
            this.isLoading = false;
        }
    }

    // Show toast notification
    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(evt);
    }

    // Getter methods for field values (backwards compatibility)
    get packagePlanType() {
        return this.applicationData?.Package_Plan_Type__r?.Name || 
               getFieldValue(this.application.data, 'Application__c.Package_Plan_Type__r.Name');
    }

    get package() {
        return this.applicationData?.Package__r?.Name || 
               getFieldValue(this.application.data, 'Application__c.Package__r.Name');
    }

    get packageTier() {
        return this.applicationData?.Package_Tier__r?.Name || 
               getFieldValue(this.application.data, 'Application__c.Package_Tier__r.Name');
    }

    get packageTerm() {
        return this.applicationData?.Package_Term__r?.Name || 
               getFieldValue(this.application.data, 'Application__c.Package_Term__r.Name');
    }

    // Enhanced getter methods with application data
    get applicationName() {
        return this.applicationData?.Name || 'Loading...';
    }

    get applicationStatus() {
        return this.applicationData?.Application_Status__c || 'Unknown';
    }

    get customerName() {
        const firstName = this.applicationData?.Customer_First_Name__c || '';
        const lastName = this.applicationData?.Customer_Last_Name__c || '';
        return `${firstName} ${lastName}`.trim() || 'N/A';
    }

    get customerEmail() {
        return this.applicationData?.Customer_Email__c || 'N/A';
    }

    get customerPhone() {
        return this.applicationData?.Customer_Home_Phone__c || 'N/A';
    }

    get vehicleInfo() {
        if (!this.applicationData) return 'Loading...';
        const year = this.applicationData.Vehicle_Year__c || '';
        const make = this.applicationData.Vehicle_Make__c || '';
        const model = this.applicationData.Vehicle_Model__c || '';
        return `${year} ${make} ${model}`.trim() || 'N/A';
    }

    get vehicleVIN() {
        return this.applicationData?.Vehicle_VIN__c || 'N/A';
    }

    get vehiclePrice() {
        const price = this.applicationData?.Vehicle_Purchase_Price__c;
        return price ? `$${price.toLocaleString()}` : 'N/A';
    }

    get hasIncludedOptions() {
        return this.includedOptions && this.includedOptions.length > 0;
    }

    get hasOptionalOptions() {
        return this.optionalOptions && this.optionalOptions.length > 0;
    }

    get isDataLoaded() {
        return this.applicationData && !this.isLoading;
    }
}