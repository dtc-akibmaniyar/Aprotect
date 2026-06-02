import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { updateRecord } from 'lightning/uiRecordApi';

// Base application summary (customer + vehicle)
import getApplicationSummaryData from '@salesforce/apex/ApplicationSummaryController.getApplicationSummaryData';
// Application Package data from ApplicationPDFExtension
import getApplicationPackageData from '@salesforce/apex/ApplicationSummaryController.getApplicationPackageData';
// Keep existing PDF flow: attach file via ApplicationSummaryController
import generateAndAttachPDF from '@salesforce/apex/ApplicationSummaryController.generateAndAttachPDF';
import generatePDFForPackageRecordType from '@salesforce/apex/ApplicationSummaryController.generatePDFForPackageRecordType';
// Create invoice on application submit
import createInvoiceOnApplicationSubmit from '@salesforce/apex/ApplicationSummaryController.createInvoiceOnApplicationSubmit';
// Update application status
import updateApplicationStatus from '@salesforce/apex/DealerPortalController.updateApplicationStatus';
import getInvoiceForApplication from '@salesforce/apex/ApplicationSummaryController.getInvoiceForApplication';

export default class DealerPortalSummary extends NavigationMixin(LightningElement) {
    @api recordId;
    @api applicationId = '';
    @api isLocked = false;
    
    @track loading = false;
    @track isBusy = false;
    @track generatingPdfRecordType = null;

    // Initialize summaryData with all nested objects to prevent undefined errors
    @track summaryData = {
        application: {},
        salesPersonName: '',
        customerAddress: {},
        customerLessee: {},
        customerCoLessee: {},
        company: {},
        dealershipInfo: {},
        lienHolderInfo: {},
        financedVehicleLoans: {},
        vehicle: {
            specifications: {},
            warranty: {}
        },
        applicationPackages: []
    };
    @track packageData = { recordTypeWrappers: [] };
    @track loading = true;
    @track error;
    
    @track vehicleData = {};
    @track customerData = {};
    @track warrantyData = {};
    @track moreProductsData = {};
    @track gapData = {};
    @track applicationData = {};
    
    @track hasVehicleData = false;
    @track hasCustomerData = false;
    @track hasWarrantyData = false;
    @track hasMoreProductsData = false;
    @track hasGapData = false;
    
    @track totalPrice = 0;
    @track taxAmount = 0;
    @track contractPremium = 0;
    
    @track invoiceId = null;
    @track invoiceName = null;

    @track saveAsQuoteButtonLabel = 'Save as Quote';
    @track saveAsQuoteButtonDisabled = false;

    @track packageHasFiles = false;
    @track packageFileCount = 0;
    
    connectedCallback() {
        console.log('🎯 DealerPortalSummary connected');
        this.loadData();
        this.calculateTotal();
    }
    
    @api
    async onTabActivated() {
        console.log('🎯 DealerPortalSummary tab activated - START');
        this.loading = true; // Ensure loading spinner is shown immediately
        await this.loadData();
        this.calculateTotal();
        console.log('🎯 DealerPortalSummary tab activated - END');
    }
    
    get effectiveApplicationId() {
        return this.applicationId || this.recordId || null;
    }
    
    get applicationIdList() {
        const appId = this.effectiveApplicationId;
        return appId ? [appId] : [];
    }
    
    async loadData() {
        this.loading = true; // Set loading to true at the start
        console.log('🔄 loadData - START');
        if (!this.effectiveApplicationId) {
            this.error = 'No record ID provided';
            this.loading = false;
            return;
        }

        try {
            // Load both sets of data in parallel
            const [summaryResult, packageResult] = await Promise.all([
                getApplicationSummaryData({ applicationId: this.effectiveApplicationId }),
                getApplicationPackageData({ applicationId: this.effectiveApplicationId })
            ]);
            
            // Merge summaryResult with default structure to ensure all properties exist
            this.summaryData = {
                application: summaryResult.application || {},
                salesPersonName: summaryResult.salesPersonName || '',
                customerAddress: summaryResult.customerAddress || {},
                customerLessee: summaryResult.customerLessee || {},
                customerCoLessee: summaryResult.customerCoLessee || {},
                company: summaryResult.company || {},
                dealershipInfo: summaryResult.dealershipInfo || {},
                lienHolderInfo: summaryResult.lienHolderInfo || {},
                financedVehicleLoans: summaryResult.financedVehicleLoans || {},
                vehicle: {
                    specifications: summaryResult.vehicle?.specifications || {},
                    warranty: summaryResult.vehicle?.warranty || {}
                },
                applicationPackages: summaryResult.applicationPackages || []
            };
            
            this.packageData = packageResult;
            console.log('🔄 loadData - packageResult received', packageResult);
            const clonedPackageData = { ...this.packageData }; // Shallow copy of packageData
            clonedPackageData.recordTypeWrappers = clonedPackageData.recordTypeWrappers.map(rtWrapper => {
                return {
                    ...rtWrapper,
                    packages: rtWrapper.packages.map(pkgWrapper => {
                        const clonedPkg = { ...pkgWrapper.pkg }; // Shallow copy of pkg
                        const packageTermName = clonedPkg.Package_Term__r && clonedPkg.Package_Term__r.Name ? clonedPkg.Package_Term__r.Name : '';
                        if(clonedPkg.Application_Status__c == 'Quote' || clonedPkg.Application_Status__c == 'Submitted'){
                            this.saveAsQuoteButtonDisabled = true;
                        }
                        else{
                            this.saveAsQuoteButtonDisabled = false;
                        }
                        return {
                            ...pkgWrapper,
                            pkg: clonedPkg,
                            packageTermName: packageTermName // Add the new property here
                        };
                    })
                };
            });
            this.packageData = clonedPackageData; // Assign the modified shallow copy back
            console.log('🔄 loadData - packageData processed', this.packageData);
            // Load invoice data
            try {
                const invoiceResult = await getInvoiceForApplication({ applicationId: this.effectiveApplicationId });
                if (invoiceResult) {
                    this.invoiceId = invoiceResult.invoiceId;
                    this.invoiceName = invoiceResult.invoiceName;
                } else {
                    this.invoiceId = null;
                    this.invoiceName = null;
                }
            } catch (invoiceError) {
                console.warn('Could not load invoice data:', invoiceError);
                this.invoiceId = null;
                this.invoiceName = null;
            }

            this.error = undefined;
            
        } catch (error) {
            console.error('Error loading data:', error);
            this.error = error.body ? error.body.message : error.message;
            // Keep the initialized structure even on error to prevent undefined errors
            this.summaryData = {
                application: {},
                salesPersonName: '',
                customerAddress: {},
                customerLessee: {},
                customerCoLessee: {},
                company: {},
                dealershipInfo: {},
                lienHolderInfo: {},
                financedVehicleLoans: {},
                vehicle: {
                    specifications: {},
                    warranty: {}
                },
                applicationPackages: []
            };
            this.packageData = { recordTypeWrappers: [] };
        } finally {
            this.loading = false;
            console.log('🔄 loadData - END, loading:', this.loading);
        }
    }

    // Getters for computed properties
    get customerName() {
        if (!this.summaryData || !this.summaryData.application) return '';
        const app = this.summaryData.application;
        return `${app.Customer_First_Name__c || ''} ${app.Customer_Last_Name__c || ''}`.trim();
    }

    get formattedPurchasePrice() {
        if (!this.summaryData || !this.summaryData.application || !this.summaryData.application.Vehicle_Purchase_Price__c) {
            return '';
        }
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD'
        }).format(this.summaryData.application.Vehicle_Purchase_Price__c);
    }

    get formattedPurchaseDate() {
        if (!this.summaryData || !this.summaryData.application || !this.summaryData.application.LastModifiedDate) {
            return '';
        }
        return new Date(this.summaryData.application.LastModifiedDate).toLocaleString();
    }

    get formattedCustomerAddress() {
        if (!this.summaryData || !this.summaryData.customerAddress) {
            return '';
        }
        const addr = this.summaryData.customerAddress;
        const parts = [];
        
        if (addr.city) parts.push(addr.city);
        if (addr.state) parts.push(addr.state);
        if (addr.postalCode) parts.push(addr.postalCode);
        if (addr.country) parts.push(addr.country);
        
        return parts.join(', ');
    }

    get isApplicationSubmitted() {
        // Check if application exists and has Application_Status__c = 'Submitted'
        return this.summaryData && 
               this.summaryData.application && 
               this.summaryData.application.Application_Status__c === 'Submitted';
    }

    get isApplicationOrActive() {
        // Check if application exists and has Application_Status__c = 'Submitted' or 'Active'
        return ((this.summaryData && 
               this.summaryData.application && 
               this.summaryData.application.Application_Status__c === 'Submitted')
            ||

            (this.summaryData && 
               this.summaryData.application && 
               this.summaryData.application.Application_Status__c === 'Active')
            );
    }
    
    get isSubmitButtonDisabled() {
        // Disable submit button if busy or already submitted
        return this.isBusy || this.isApplicationSubmitted;
    }
    
    get hasInvoice() {
        return !!this.invoiceId;
    }

    calculateTotal() {
        this.totalPrice = 0;
        this.taxAmount = 0;
        this.contractPremium = 0; // Reset total price before recalculating
        console.log('📊 calculateTotal - START', 'Current totalPrice:', this.totalPrice);
        if (!this.packageData || !this.packageData.recordTypeWrappers) {
            console.log('📊 calculateTotal - No packageData or recordTypeWrappers available');
            return; // Exit if packageData is not ready
        }
        this.packageData.recordTypeWrappers.forEach(rtWrapper => {
            console.log('📊 Processing recordTypeWrapper:', rtWrapper.recordTypeName);
            if (rtWrapper.packages) {
                rtWrapper.packages.forEach(pkg1 => {
                    console.log('📊 Processing package:', pkg1.pkg.Name);
                    let pack = pkg1.pkg;
                    const totalPrice = parseFloat(pack.Contract_Cost_Price__c || 0);
                    const tax = parseFloat(pack.Tax_Amount_Cost__c || 0);
                    const retailCost = parseFloat(pack.Contract_Cost_Price_Without_Tax__c|| 0);
                    console.log(pack.Contract_Cost_Price_Without_Tax__c);
                    console.log(pack.Tax_Amount_Cost__c);
                    this.totalPrice += totalPrice;
                    this.taxAmount += tax;
                    this.contractPremium += retailCost;
                });
            }
        });
        console.log('📊 calculateTotal - Raw totalPrice:', this.totalPrice);
        this.totalPrice = this.totalPrice.toFixed(2);
        this.taxAmount = this.taxAmount.toFixed(2);
        this.contractPremium = this.contractPremium.toFixed(2);
        console.log('📊 calculateTotal - Formatted totalPrice:', this.totalPrice);
        console.log('📊 calculateTotal - Formatted taxAmount:', this.taxAmount);
        console.log('📊 calculateTotal - Formatted contractPremium:', this.contractPremium);
    }
    /*calculateTotal() {
        const warrantyPrice = parseFloat(this.warrantyData?.price || 0);
        const moreProductsPrice = parseFloat(this.moreProductsData?.totalPrice || 0);
        const gapPrice = parseFloat(this.gapData?.gapPrice || 0);
        
        console.log('💰 Calculating total:');
        console.log('💰 Warranty:', warrantyPrice);
        console.log('💰 More Products:', moreProductsPrice);
        console.log('💰 GAP:', gapPrice);
        
        this.totalPrice = (warrantyPrice + moreProductsPrice + gapPrice).toFixed(2);
        console.log('💰 Grand Total:', this.totalPrice);
    }
    */
    async handleClick() {
        console.log('📄 PDF generation and download requested');
        this.isBusy = true;
        const appId = this.effectiveApplicationId;
        
        try {
            if (!appId) {
                throw new Error('No Application ID available');
            }
            if(!this.packageData || !this.packageData.recordTypeWrappers || this.packageData.recordTypeWrappers.length === 0){
                this.showToast('Error', 'Cannot generate PDF without services. Please add at least one service to continue.', 'error');
                this.isBusy = false;
                return;
            }
            
            console.log('📄 Calling generateAndAttachPDF for:', appId);
            const response = await generateAndAttachPDF({ applicationId: appId });
            console.log('📄 PDF response:', response);
            
            if (!response?.success) {
                throw new Error(response?.message || 'PDF generation failed');
            }
            
            // Success! PDF was generated and attached
            this.showToast('Success', 'PDF Generated Successfully', 'success');
            
        } catch (error) {
            console.error('❌ PDF generation error:', error);
            const errorMessage = error?.body?.message || error?.message || 'PDF generation failed';
            this.showToast('Error', errorMessage, 'error');
        } finally {
            this.isBusy = false;
        }
    }

    handleCreatePdf() {
        return this.handleClick();
    }

    async handlePackagePdf(event) {
        const recordTypeName = event.currentTarget.dataset.recordtype || '';
        const appId = this.effectiveApplicationId;
        console.log('📄 Package PDF requested for recordType:', recordTypeName);

        if (!appId) {
            this.showToast('Error', 'No Application ID available', 'error');
            return;
        }

        this.isBusy = true;
        this.generatingPdfRecordType = recordTypeName;
        try {
            const response = await generatePDFForPackageRecordType({
                applicationId: appId,
                recordTypeName: recordTypeName
            });
            console.log('📄 Package PDF response:', response);

            if (!response?.success) {
                throw new Error(response?.message || 'PDF generation failed');
            }

            this.showToast('Success', response.message || 'PDF Generated Successfully', 'success');

            // Navigate to the generated PDF view
            if (response.attachmentId) {
                const baseUrl = 'https://' + location.host;
                const fileUrl = baseUrl + '/dealerportal/sfc/servlet.shepherd/document/download/' + response.attachmentId + '?operationContext=S1';
                window.open(fileUrl, '_blank');
            }
        } catch (error) {
            console.error('❌ Package PDF error:', error);
            const errorMessage = error?.body?.message || error?.message || 'PDF generation failed';
            this.showToast('Error', errorMessage, 'error');
        } finally {
            this.isBusy = false;
            this.generatingPdfRecordType = null;
        }
    }

    handlePreviewPdf() {
        console.log('👁️ Preview PDF requested');
        const appId = this.effectiveApplicationId;
        
        if (!appId) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'No Application ID available',
                variant: 'error'
            }));
            return;
        }
        
        // Construct the URL to the related files page
        const baseUrl = 'https://' + location.host;
        const previewUrl = baseUrl + '/dealerportal/s/contentdocument/related/' + appId + '/AttachedContentDocuments';
        
        // Navigate to the URL
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: previewUrl
            }
        }, false);
    }

    handleFilesLoaded(event) {
        const fileDetails = event.detail;
        this.packageHasFiles = fileDetails.hasFiles;
        this.packageFileCount = fileDetails.fileCount;
        console.log('📁 Files loaded:', fileDetails);
        console.log('📁 Files hasFiles:', packageHasFiles);
        console.log('📁 Files fileCount:', packageFileCount);
    }

    async handleSaveAsQuote() {
        console.log('💾 Save as Quote requested');
        this.isBusy = true;
        const appId = this.effectiveApplicationId;
        
        try {
            if (!appId) {
                throw new Error('No Application ID available');
            }
            
            console.log('💾 Updating Application Status to Quote for:', appId);
            const fields = {
                Id: appId,
                Application_Status__c: 'Quote'
            };
            
            await updateRecord({ fields });
            
            // Success! Application status updated to Quote
            console.log('✅ Application status updated to Quote successfully');
            
            // Update local application data to reflect the new status
            this.applicationData = {
                ...this.applicationData,
                status: 'Quote'
            };
            
            // Show success toast
            this.showToast('Success', 
                'Application status updated to Quote successfully!', 
                'success'
            );
            
            // Dispatch event to parent container to update application status imperatively
            // This bypasses wire adapter caching and ensures immediate UI update
            console.log('📡 Dispatching applicationstatuschanged event to parent');
            this.dispatchEvent(new CustomEvent('applicationstatuschanged', {
                detail: {
                    newStatus: 'Quote'
                },
                bubbles: true,
                composed: true
            }));
            
            // Navigate back to vehicle tab
            console.log('🔄 Navigating back to vehicle tab');
            this.dispatchEvent(new CustomEvent('navigate', {
                detail: {
                    tab: 'vehicle'
                },
                bubbles: true,
                composed: true
            }));
            
            // Reload data to reflect the changes
            await this.loadData();
            
        } catch (error) {
            console.error('❌ Save as Quote error:', error);
            const errorMessage = error?.body?.message || error?.message || 'Failed to save as quote';
            this.showToast('Error', errorMessage, 'error');
        } finally {
            this.isBusy = false;
        }
    }

    async handleSubmitApplication() {
        console.log('📨 Submit Application requested');
        this.isBusy = true;
        const appId = this.effectiveApplicationId;
        
        try {
            if (!appId) {
                throw new Error('No Application ID available');
            }
            if(!this.packageData || !this.packageData.recordTypeWrappers || this.packageData.recordTypeWrappers.length === 0){
                this.showToast('Error', 'Cannot submit application without services. Please add at least one service to proceed.', 'error');
                this.isBusy = false;
                return;
            }
            
            console.log('📨 Calling updateApplicationStatus, createInvoice, and generatePDF in parallel for:', appId);
            
            // Execute all three methods in parallel using Promise.all
            const [statusResponse, invoiceResponse, pdfResponse] = await Promise.all([
                updateApplicationStatus({ 
                    applicationId: appId, 
                    status: 'Submitted' 
                }),
                createInvoiceOnApplicationSubmit({ 
                    applicationId: appId 
                }),
                generateAndAttachPDF({ 
                    applicationId: appId 
                })
            ]);
            
            console.log('📨 Status response:', statusResponse);
            console.log('📋 Invoice response:', invoiceResponse);
            console.log('📄 PDF response:', pdfResponse);
            
            if (!statusResponse?.success) {
                throw new Error(statusResponse?.message || 'Application submission failed');
            }
            
            // Success! Application submitted
            console.log('✅ Application submitted successfully');
            
            // Check invoice creation result
            if (!invoiceResponse?.success) {
                console.warn('⚠️ Invoice creation failed:', invoiceResponse?.message);
            } else {
                console.log('✅ Invoice created successfully:', invoiceResponse?.invoiceId);
                this.invoiceId = invoiceResponse.invoiceId;
            }
            
            // Check PDF generation result
            if (!pdfResponse?.success) {
                console.warn('⚠️ PDF generation completed but with issues:', pdfResponse?.message);
            } else {
                console.log('✅ PDF generated successfully');
            }
            
            // Update local application data to reflect the new status
            this.applicationData = {
                ...this.applicationData,
                status: 'Submitted'
            };
            
            // Show success toast
            this.showToast('Success',
                'Application submitted successfully, invoice created, and PDF generated!',
                'success'
            );

            // Dispatch event to parent container to update application status imperatively
            // This bypasses wire adapter caching and ensures immediate UI update
            console.log('📡 Dispatching applicationstatuschanged event to parent');
            this.dispatchEvent(new CustomEvent('applicationstatuschanged', {
                detail: {
                    newStatus: 'Submitted'
                },
                bubbles: true,
                composed: true
            }));

            // Reload data to reflect the changes
            await this.loadData();

            // Navigate to the created invoice
            if (invoiceResponse?.success && invoiceResponse?.invoiceId) {
                console.log('🧾 Navigating to invoice:', invoiceResponse.invoiceId);
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: invoiceResponse.invoiceId,
                        objectApiName: 'Invoice__c',
                        actionName: 'view'
                    }
                });
            }
            
        } catch (error) {
            console.error('❌ Submit Application error:', error);
            const errorMessage = error?.body?.message || error?.message || 'Failed to submit application';
            this.showToast('Error', errorMessage, 'error');
        } finally {
            this.isBusy = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        }));
    }

    handleViewInvoice() {
        if (!this.invoiceId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.invoiceId,
                objectApiName: 'Invoice__c',
                actionName: 'view'
            }
        });
    }

    handleBack() {
        console.log('🔙 Back button clicked from summary component');
        const backEvent = new CustomEvent('back', {
            detail: {},
            bubbles: true
        });
        this.dispatchEvent(backEvent);
    }

    handleEditSection(event) {
        event.stopPropagation();
        let tab = event.currentTarget.dataset.tab;
        if (!tab) {
            const recordType = (event.currentTarget.dataset.recordtype || '').toLowerCase();
            if (recordType.includes('tire') || recordType.includes('rim')) {
                tab = 'moreProducts';
            } else if (recordType.includes('gap') || recordType.includes('total loss')) {
                tab = 'gap';
            } else {
                tab = 'warranty';
            }
        }
        console.log('✏️ Edit section clicked - navigating to tab:', tab);
        this.dispatchEvent(new CustomEvent('navigate', {
            detail: { tab },
            bubbles: true,
            composed: true
        }));
    }
}