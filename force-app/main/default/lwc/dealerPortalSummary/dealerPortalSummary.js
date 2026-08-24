import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { updateRecord, getRecord, getFieldValue } from 'lightning/uiRecordApi';
import DUE_DATE_FIELD from '@salesforce/schema/Invoice__c.Invoice_Due_Date__c';

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
    @api applicationStatus;
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
    @track showInvoicePromptModal = false;
    @track invoicePromptLoading = false;

    @track showSubmissionSuccess = false;
    @track submittedInvoiceId = null;
    @track _rawDueDate = null;

    @wire(getRecord, { recordId: '$submittedInvoiceId', fields: [DUE_DATE_FIELD] })
    wiredInvoiceRecord({ data, error }) {
        if (data) {
            const raw = getFieldValue(data, DUE_DATE_FIELD);
            this._rawDueDate = raw;
        } else if (error) {
            this._rawDueDate = null;
        }
    }
    
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

    get isQuote() {
        return this.applicationStatus === 'Quote';
    }

    get summaryHeaderTitle() {
        return this.isQuote ? 'QUOTE SUMMARY' : 'APPLICATION SUMMARY';
    }

    get summaryHeaderSubtitle() {
        return this.isQuote
            ? 'Please review the details of the quote below.'
            : 'Please review the details of the application below. Please note once the application is submitted and payment has been remitted, all cancellations must be requested through A-Protect.';
    }

    get applicationIdLabel() {
        return this.isQuote ? 'QUOTE ID' : 'APPLICATION ID # (AP#)';
    }

    get applicationInfoHeader() {
        return this.isQuote ? 'QUOTE INFORMATION' : 'APPLICATION INFORMATION';
    }

    get submitButtonLabel() {
        return this.isQuote ? 'CONVERT TO APPLICATION' : 'SUBMIT';
    }
    
    get applicationIdList() {
        const appId = this.effectiveApplicationId;
        return appId ? [appId] : [];
    }

    get formattedPaymentDueDate() {
        if (!this._rawDueDate) return 'To be determined';
        return new Date(this._rawDueDate).toLocaleDateString('en-US', {
            year: 'numeric', month: 'long', day: 'numeric', timeZone: 'UTC'
        });
    }

    // Fix 2 — Powersports getter
    get isPowersports() {
        return this.summaryData?.vehicle?.specifications?.vehicleCategory === 'Powersports';
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
            
            // Post-process applicationPackages to remove Premium Vehicle Fee from customer-facing totals
            this._recalculateCustomerTotals();
            console.log('🔄 loadData - packageResult received', packageResult);
            const clonedPackageData = { ...this.packageData }; // Shallow copy of packageData
            clonedPackageData.recordTypeWrappers = clonedPackageData.recordTypeWrappers.map(rtWrapper => {
                return {
                    ...rtWrapper,
                    packages: rtWrapper.packages.map(pkgWrapper => {
                        const clonedPkg = { ...pkgWrapper.pkg }; // Shallow copy of pkg
                        // Display name: prefer the dealer-selected term, fall back to the master term
                        const packageTermName = (clonedPkg.Dealer_Package_Term__r && clonedPkg.Dealer_Package_Term__r.Name)
                            ? clonedPkg.Dealer_Package_Term__r.Name
                            : (clonedPkg.Package_Term__r && clonedPkg.Package_Term__r.Name ? clonedPkg.Package_Term__r.Name : '');
                        console.log('Package Term for package: ', clonedPkg.Package_Term__c);
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

            // Enrich summary packages with optionalOptionsList from packageData
            this._enrichPackageOptions();
            
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

    get showCreateInvoiceButton() {
        // Visible only when submitted + no invoice yet
        return this.isApplicationSubmitted && !this.hasInvoice && !this.isBusy;
    }

    /**
     * Cross-reference packageData (which has the clean included/optional split)
     * into summaryData packages so the HTML can render two distinct sections.
     * summaryData.additionalOptionsPurchased = Included option names (cost in package price).
     * packageData.optionalOptions = user-selected add-ons with their own price.
     */
    _enrichPackageOptions() {
        if (!this.summaryData.applicationPackages || !this.packageData.recordTypeWrappers) return;
        const pkgDataMap = new Map();
        for (const rtw of this.packageData.recordTypeWrappers) {
            for (const pw of (rtw.packages || [])) {
                if (pw.pkg && pw.pkg.Id) {
                    pkgDataMap.set(pw.pkg.Id, pw);
                }
            }
        }
        const fmt = v => v != null
            ? new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(v)
            : '';
        for (const rtw of this.summaryData.applicationPackages) {
            for (const pw of (rtw.packages || [])) {
                const pkgId = pw.pkg && pw.pkg.Id ? pw.pkg.Id : null;
                const matched = pkgId ? pkgDataMap.get(pkgId) : null;
                const opts = matched && matched.optionalOptions ? matched.optionalOptions : [];
                pw.optionalOptionsList = opts.map(opt => ({
                    label: opt.Option__c
                        || (opt.Package_Option__r && opt.Package_Option__r.Name)
                        || 'Unknown',
                    price: opt.Package_Option__r && opt.Package_Option__r.Price__c != null
                        ? fmt(opt.Package_Option__r.Price__c)
                        : ''
                }));
            }
        }
    }

    /**
     * Recalculate customer-facing totals on each applicationPackage.
     * For Powersports: total = retailCost + premiumModelFee + ((retailCost + premiumModelFee) * taxRate)
     * For non-Powersports: total = retailCost + (retailCost * taxRate)
     * Tax is recalculated on base retail cost only (non-Powersports) or retail+surcharge (Powersports).
     */
    _recalculateCustomerTotals() {
        if (!this.summaryData.applicationPackages) return;
        const isPowersports = this.isPowersports;
        this.summaryData.applicationPackages.forEach(rtWrapper => {
            if (rtWrapper.packages) {
                rtWrapper.packages.forEach(pkgWrapper => {
                    const retailCost = this._parseCurrency(pkgWrapper.formattedRetailCost);
                    const taxRate = parseFloat((pkgWrapper.formattedTaxRate || '0').replace('%', '')) / 100;
                    let taxBase = retailCost;
                    if (isPowersports && pkgWrapper.premiumModelFee) {
                        taxBase = retailCost + (pkgWrapper.premiumModelFee || 0);
                    }
                    const customerTax = taxBase * taxRate;
                    const customerTotal = taxBase + customerTax;
                    pkgWrapper.customerFormattedTax = this._formatCurrency(customerTax);
                    pkgWrapper.customerFormattedTotal = this._formatCurrency(customerTotal);
                });
            }
        });
    }

    _parseCurrency(str) {
        if (!str) return 0;
        return parseFloat(str.replace(/[^0-9.\-]/g, '')) || 0;
    }

    _formatCurrency(value) {
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD'
        }).format(value);
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
        console.log('📁 Files hasFiles:', this.packageHasFiles);
        console.log('📁 Files fileCount:', this.packageFileCount);
    }

    // --- Modal scroll helpers (Phase B) ---
    lockBodyScroll() {
        // Phase C: idempotent lock - remember the previous overflow value so we
        // restore it exactly, and never double-lock or clobber another
        // component's lock. A modal that fails to open can never leave the page
        // locked, because unlock restores the saved value on every close path.
        if (!this._bodyScrollLocked) {
            this._bodyScrollLocked = true;
            this._bodyScrollPrevOverflow = document.body.style.overflow;
            document.body.style.overflow = 'hidden';
        }
    }

    unlockBodyScroll() {
        // Phase C: idempotent unlock - only restore when this component owns
        // the lock; never lets the page stay locked after a modal closes.
        if (this._bodyScrollLocked) {
            this._bodyScrollLocked = false;
            document.body.style.overflow = this._bodyScrollPrevOverflow || '';
        }
    }

    scrollToTop() {
        // Verified: this app's content flows in normal document layout (container
        // .tab-content is overflow:visible), so the viewport/document is the
        // scroller — the standard Experience Cloud (Aura) shell behavior.
        window.scrollTo(0, 0);
        const scroller = document.scrollingElement || document.documentElement;
        if (scroller) {
            scroller.scrollTop = 0;
        }
        if (document.body) {
            document.body.scrollTop = 0;
        }
    }

    async handleSaveAsQuote() {
        console.log('💾 Save as Quote requested from summary');
        this.scrollToTop();
        this.dispatchEvent(new CustomEvent('saveasquote', {
            detail: {
                applicationId: this.effectiveApplicationId
            },
            bubbles: true,
            composed: true
        }));
    }

    async handleSubmitApplication() {
        // If Quote, trigger convert to application instead of submit
        if (this.isQuote) {
            this.handleConvertToApplication();
            return;
        }
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
            
            console.log('📨 Calling updateApplicationStatus for:', appId);

            // Step 1: Update status only (no PDF, no invoice yet)
            const statusResponse = await updateApplicationStatus({
                applicationId: appId,
                status: 'Submitted'
            });

            console.log('📨 Status response:', statusResponse);

            if (!statusResponse?.success) {
                throw new Error(statusResponse?.message || 'Application submission failed');
            }

            console.log('✅ Application submitted successfully');

            // Update local state
            this.applicationData = {
                ...this.applicationData,
                status: 'Submitted'
            };

            // Dispatch event to parent container to update application status
            console.log('📡 Dispatching applicationstatuschanged event to parent');
            this.dispatchEvent(new CustomEvent('applicationstatuschanged', {
                detail: { newStatus: 'Submitted' },
                bubbles: true,
                composed: true
            }));

            // Step 2: Create invoice and show success screen
            try {
                const invoiceResponse = await createInvoiceOnApplicationSubmit({ applicationId: appId });
                if (invoiceResponse && (invoiceResponse.success) && (invoiceResponse.id || invoiceResponse.invoiceId)) {
                    this.invoiceId = invoiceResponse.id || invoiceResponse.invoiceId;
                    this.submittedInvoiceId = this.invoiceId;
                } else if (invoiceResponse && invoiceResponse.invoiceId) {
                    this.invoiceId = invoiceResponse.invoiceId;
                    this.submittedInvoiceId = this.invoiceId;
                }
            } catch (invoiceError) {
                console.warn('Invoice creation failed, continuing to success screen:', invoiceError);
            }
            this.showSubmissionSuccess = true;
            this.lockBodyScroll();
            this.scrollToTop();
            if (this.invoiceId) {
                this.submittedInvoiceId = this.invoiceId;
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

    async handleInvoicePromptYes() {
        const appId = this.effectiveApplicationId;
        if (!appId) return;
        this.invoicePromptLoading = true;
        try {
            const invoiceResponse = await createInvoiceOnApplicationSubmit({ applicationId: appId });
            if (invoiceResponse?.success && invoiceResponse?.invoiceId) {
                this.invoiceId = invoiceResponse.invoiceId;
                this.showInvoicePromptModal = false;
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: invoiceResponse.invoiceId,
                        objectApiName: 'Invoice__c',
                        actionName: 'view'
                    }
                });
            } else {
                this.showToast('Warning', invoiceResponse?.message || 'Invoice creation failed.', 'warning');
                this.showInvoicePromptModal = false;
                await this.loadData();
                await this.calculateTotal();
            }
        } catch (error) {
            const msg = error?.body?.message || error?.message || 'Failed to create invoice';
            this.showToast('Error', msg, 'error');
            this.showInvoicePromptModal = false;
        } finally {
            this.invoicePromptLoading = false;
        }
    }

    async handleInvoicePromptNo() {
        this.showInvoicePromptModal = false;
        await this.loadData();
        await this.calculateTotal();
    }

    async handleCreateInvoice() {
        const appId = this.effectiveApplicationId;
        if (!appId) return;
        this.isBusy = true;
        try {
            const invoiceResponse = await createInvoiceOnApplicationSubmit({ applicationId: appId });
            if (invoiceResponse && invoiceResponse.success && invoiceResponse.invoiceId) {
                this.invoiceId = invoiceResponse.invoiceId;
                this.showToast('Success', 'Invoice created successfully!', 'success');
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: invoiceResponse.invoiceId,
                        objectApiName: 'Invoice__c',
                        actionName: 'view'
                    }
                });
            } else {
                this.showToast('Warning', (invoiceResponse && invoiceResponse.message) || 'Invoice creation failed.', 'warning');
            }
        } catch (error) {
            const msg = (error && error.body && error.body.message) || (error && error.message) || 'Failed to create invoice';
            this.showToast('Error', msg, 'error');
        } finally {
            this.isBusy = false;
        }
    }

    handleConvertToApplication() {
        console.log('🔄 Convert to Application requested from summary');
        this.dispatchEvent(new CustomEvent('convertapplication', {
            bubbles: true,
            composed: true
        }));
    }

    handleGenerateQuotePDF() {
        console.log('📄 Generate Quote PDF - dispatching to container');
        this.scrollToTop();
        this.dispatchEvent(new CustomEvent('generatequotepdf'));
    }

    handlePreviewQuotePDF() {
        console.log('👁️ Preview Quote PDF requested from summary');
        this.scrollToTop();
        this.dispatchEvent(new CustomEvent('previewpdf', {
            bubbles: true,
            composed: true
        }));
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

    handleViewInvoiceFromSuccess() {
        this.unlockBodyScroll();
        if (this.invoiceId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.invoiceId,
                    actionName: 'view'
                }
            });
        }
    }

    handleCreateAnotherApplication() {
        this.unlockBodyScroll();
        this.dispatchEvent(new CustomEvent('createanotherapplication'));
    }

    handleViewApplications() {
        this.unlockBodyScroll();
        this.dispatchEvent(new CustomEvent('viewapplications'));
    }

    handleReturnToHome() {
        this.unlockBodyScroll();
        this.dispatchEvent(new CustomEvent('returntohome'));
    }

    handlePackagePdfFromSuccess(event) {
        const recordTypeId = event.currentTarget.dataset.recordTypeId;
        const rtWrapper = this.packageData.recordTypeWrappers
            ? this.packageData.recordTypeWrappers.find(w => w.recordTypeId === recordTypeId)
            : null;
        if (rtWrapper && rtWrapper.packages && rtWrapper.packages.length > 0) {
            const pkg = rtWrapper.packages[0].pkg;
            if (pkg && pkg.Id) {
                this.handlePackagePdf({
                    currentTarget: {
                        dataset: {
                            packageId: pkg.Id,
                            recordTypeName: rtWrapper.recordTypeName
                        }
                    }
                });
            }
        }
    }
}