import { api, LightningElement, track, wire } from 'lwc';
import getRecord from '@salesforce/apex/ContentManagerService.getRecord';
import getContentDetails from '@salesforce/apex/ContentManagerService.getContentDetails';
import sendForRemoteSigning from '@salesforce/apex/DocusignApplicationService.sendForRemoteSigning';
import sendForEmbeddedSigning from '@salesforce/apex/DocusignApplicationService.sendForEmbeddedSigning';
import sendMultiplePdfsForRemoteSigning from '@salesforce/apex/DocusignApplicationService.sendMultiplePdfsForRemoteSigning';
import sendMultiplePdfsForEmbeddedSigning from '@salesforce/apex/DocusignApplicationService.sendMultiplePdfsForEmbeddedSigning';
import sendEnvelopeWithTabs from '@salesforce/apex/DocusignApplicationService.sendEnvelopeWithTabs';
import getPdfContentBase64 from '@salesforce/apex/DocusignApplicationService.getPdfContentBase64';
import generateUniqueClientUserId from '@salesforce/apex/DocusignApplicationService.generateUniqueClientUserId';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const columns = [
    { label: 'Title',       fieldName: 'Title', wrapText : true,
        cellAttributes: { 
            iconName: { fieldName: 'icon' }, iconPosition: 'left' 
        }
    },
    { label: 'Created By',  fieldName: 'CREATED_BY',
        cellAttributes: { 
            iconName: 'standard:user', iconPosition: 'left' 
        }
    },
    { label: 'File Size',   fieldName: 'Size' } 
];

export default class DealerPortalPDFPreview extends LightningElement {

    title ='Documents';
    showDetails = true;
    @api recordId;
    usedInCommunity = true;

    @track dataList;
    @track columnsList = columns;
    @track showDocuSignModal = false;
    @track signerEmail = '';
    @track signerName = '';
    @track selectedSigningType = 'remote';
    @track returnUrl = '';
    @track selectedRows = [];
    @track useEnvelopeWithTabs = false;
    
    isLoading = false;
    wiredFilesResult;

    signingTypeOptions = [
        { label: 'Remote Signing (Email Link)', value: 'remote' },
        { label: 'Embedded Signing (Sign in Portal)', value: 'embedded' }
    ];

    connectedCallback() {
        // Extract recordId from URL if not passed as property
        if (!this.recordId) {
            const pathArray = window.location.pathname.split('/');
            const contentdocIndex = pathArray.indexOf('contentdocument');
            if (contentdocIndex !== -1 && pathArray[contentdocIndex + 2]) {
                this.recordId = pathArray[contentdocIndex + 2];
            }
        }
        this.handleSync();
        this.loadApplicationRecord();
    }

    async loadApplicationRecord() {
        try {
            debugger;
            const result = await getRecord({
                recordId: this.recordId
            });
            if (result) {
                const record = JSON.parse(result);
                // Populate signer fields from application record
                if (record.Customer_Name__r) {
                    this.signerName = record.Customer_Name__r.Name || '';
                    this.signerEmail = record.Customer_Name__r.PersonEmail || '';
                    // this.signerEmail = 'ghulam.mohayyudin@dtcforce.com';
                }
            }
        } catch (error) {
            console.error('Error loading application record:', error);
        }
    }

    getBaseUrl(){
        let baseUrl = 'https://'+location.host+'/';
        return baseUrl;
    }

    handleSendEmail(){
        // Open DocuSign modal
        this.showDocuSignModal = true;
    }

    handleCloseModal(){
        this.showDocuSignModal = false;
        this.resetModalFields();
    }

    handleSignerEmailChange(event){
        this.signerEmail = event.target.value;
    }

    handleSignerNameChange(event){
        this.signerName = event.target.value;
    }

    handleSigningTypeChange(event){
        this.selectedSigningType = event.detail.value;
    }

    handleReturnUrlChange(event){
        this.returnUrl = event.target.value;
    }

    get isEmbeddedSigning(){
        return this.selectedSigningType === 'embedded';
    }

    handleUseEnvelopeWithTabsChange(event){
        this.useEnvelopeWithTabs = event.target.checked;
    }

    async handleSendDocuSign(){
        // Validate inputs
        if (!this.signerEmail || !this.signerName) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Validation Error',
                message: 'Please enter signer email and name',
                variant: 'error'
            }));
            return;
        }

        // Validate email format
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailRegex.test(this.signerEmail)) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Validation Error',
                message: 'Please enter a valid email address',
                variant: 'error'
            }));
            return;
        }

        // Check if any files are selected
        if (this.selectedRows.length === 0) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Validation Error',
                message: 'Please select at least one PDF to send',
                variant: 'error'
            }));
            return;
        }

        this.isLoading = true;

        try {
            // Get ContentVersion IDs from selected rows
            const contentVersionIds = this.selectedRows.map(row => row.Id);
            
            // Use the new sendEnvelopeWithTabs method if enabled
            if (this.useEnvelopeWithTabs) {
                await sendEnvelopeWithTabs({
                    applicationId: this.recordId,
                    contentVersionIds: contentVersionIds
                });

                this.dispatchEvent(new ShowToastEvent({
                    title: 'Success',
                    message: `${this.selectedRows.length} PDF(s) sent via sendEnvelopeWithTabs method with signature and date tabs!`,
                    variant: 'success'
                }));
                this.resetModalFields();
                this.handleCloseModal();
                return;
            }
            
            // Fetch base64-encoded PDF content
            const pdfContents = await getPdfContentBase64({ contentVersionIds: contentVersionIds });
            const pdfNames = pdfContents.map(pdf => pdf.title);
            const pdfBase64Contents = pdfContents.map(pdf => pdf.base64);

            if (this.selectedSigningType === 'remote') {
                // Remote signing with multiple PDFs
                const result = await sendMultiplePdfsForRemoteSigning({
                    applicationId: this.recordId,
                    signerEmail: this.signerEmail.trim(),
                    signerName: this.signerName.trim(),
                    pdfNames: pdfNames,
                    pdfBase64Contents: pdfBase64Contents
                });

                if (result.success) {
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Success',
                        message: `${this.selectedRows.length} PDF(s) sent successfully.`,
                        variant: 'success'
                    }));
                    this.resetModalFields();
                    this.handleCloseModal();
                } else {
                    throw new Error(result.errorMessage);
                }
            } else {
                // Embedded signing with multiple PDFs
                const clientUserId = await generateUniqueClientUserId({ prefix: 'client' });
                const safeReturnUrl = this.returnUrl.trim() || `${window.location.origin}/lightning/page/home`;

                const result = await sendMultiplePdfsForEmbeddedSigning({
                    applicationId: this.recordId,
                    signerEmail: this.signerEmail.trim(),
                    signerName: this.signerName.trim(),
                    clientUserId: clientUserId,
                    returnUrl: safeReturnUrl,
                    pdfNames: pdfNames,
                    pdfBase64Contents: pdfBase64Contents
                });

                if (result.success) {
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Success',
                        message: `${this.selectedRows.length} PDF(s) ready for embedded signing. Opening portal...`,
                        variant: 'success'
                    }));
                    
                    // Redirect to signing URL
                    if (result.signingUrl) {
                        window.open(result.signingUrl, '_blank');
                    }
                    this.resetModalFields();
                    this.handleCloseModal();
                } else {
                    throw new Error(result.errorMessage);
                }
            }
        } catch (error) {
            console.error('DocuSign Error:', error);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error Sending Documents',
                message: error.body ? error.body.message : error.message,
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }

    resetModalFields(){
        this.loadApplicationRecord();
        this.selectedSigningType = 'remote';
        this.returnUrl = '';
        this.selectedRows = [];
        this.useEnvelopeWithTabs = false;
    }

    handleRowSelection(event) {
        this.selectedRows = event.detail.selectedRows;
    }

    handleSync(){

        let imageExtensions = ['png','jpg','gif'];
        let supportedIconExtensions = ['ai','attachment','audio','box_notes','csv','eps','excel','exe',
                        'flash','folder','gdoc','gdocs','gform','gpres','gsheet','html','image','keynote','library_folder',
                        'link','mp4','overlay','pack','pages','pdf','ppt','psd','quip_doc','quip_sheet','quip_slide',
                        'rtf','slide','stypi','txt','unknown','video','visio','webex','word','xml','zip'];

        this.isLoading = true;
        getContentDetails({
            recordId : this.recordId
        })
        .then(result => {
            let parsedData = JSON.parse(result);
            let stringifiedData = JSON.stringify(parsedData);
            let finalData = JSON.parse(stringifiedData);
            let baseUrl = this.getBaseUrl();
            let tempRecs = [];
            finalData.forEach(file => {
                let tempRec = Object.assign({}, file);
                tempRec.downloadUrl = baseUrl+'/sfsites/c/sfc/servlet.shepherd/document/download/'+tempRec.ContentDocumentId;
                tempRec.fileUrl     = baseUrl+'/sfc/servlet.shepherd/version/renditionDownload?rendition=PDF&versionId='+tempRec.Id;
                tempRec.titleUrl    = baseUrl + '/s/contentdocument/' + tempRec.ContentDocumentId;
                tempRec.CREATED_BY  = tempRec.ContentDocument.CreatedBy.Name;
                tempRec.Size        = this.formatBytes(tempRec.ContentDocument.ContentSize, 2);

                let fileType = tempRec.ContentDocument.FileType.toLowerCase();
                if(imageExtensions.includes(fileType)){
                    tempRec.icon = 'doctype:image';
                }else{
                    if(supportedIconExtensions.includes(fileType)){
                        tempRec.icon = 'doctype:' + fileType;
                    }
                }
                tempRecs.push(tempRec);
            });
            this.dataList = tempRecs;
        })
        .catch(error => {
            console.error('**** error **** \n ',error)
        })
        .finally(()=>{
            this.isLoading = false;
        });
    }

    formatBytes(bytes,decimals) {
        if(bytes == 0) return '0 Bytes';
        var k = 1024,
            dm = decimals || 2,
            sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'],
            i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
    }

}