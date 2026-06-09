import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { updateRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getApplicationsList from '@salesforce/apex/QuotesListViewController.getQuotesList';
import createNewQuote from '@salesforce/apex/QuotesListViewController.createNewQuote';
import convertQuoteToApplication from '@salesforce/apex/DealerPortalController.convertQuoteToApplication';
import generateQuotePDF from '@salesforce/apex/QuotePDFGeneratorService.generateQuotePDF';
import communityBasePath from '@salesforce/community/basePath';

export default class QuotesListView extends NavigationMixin(LightningElement) {
    @track isLoading = true;
    @track search = '';
    @track page = 1;
    @track pageSize = 10;
    @track totalPages = 1;
    @track totalCount = 0;
    @track applications = [];
    @track showCancellationModal = false;
    @track cancellationApplicationId = null;
    @track cancellationVehicleName = '';
    @track cancellationVIN = '';
    @track showNewQuoteModal = false;
    @track isCreating = false;
    @track showConvertModal = false;
    @track convertApplicationId = null;
    @track convertVehicleName = '';
    @track convertVIN = '';
    @track isConverting = false;
    @track generatingPDFId = null;

    // Cache management
    pageCache = new Map(); // Map<pageNumber, array of records>
    countFetched = 0; // Total records fetched so far
    initialLoadDone = false;
    INITIAL_FETCH_LIMIT = 25000; // Fetch up to 49000 records on first call
    // Holds transformed records from the initial bulk fetch (if any)
    allFetchedRecords = [];

    connectedCallback() {
        this.loadInitial();
    }

    /**
     * Load first page and get total count, fetching up to 49000 records
     */
    async loadInitial() {
        this.isLoading = true;
        try {
            // Determine how many pages to fetch initially
            // With 49000 limit and pageSize of 10, we need max 4900 pages
            // But we fetch in increments, so calculate initial fetch size
            const initialPageSize = this.INITIAL_FETCH_LIMIT;
            
            const resp = await getApplicationsList({ 
                pageNumber: 1, 
                pageSize: initialPageSize,
                searchTerm: this.search
            });
            console.log('Initial load resp:: ' + JSON.stringify(resp));
            
            if (resp && resp.success && Array.isArray(resp.data)) {
                this.totalCount = resp.totalCount || 0;
                // Compute client-side totalPages based on current pageSize
                this.totalPages = Math.max(1, Math.ceil((this.totalCount || 0) / this.pageSize));
                this.page = 1;
                
                // Transform and cache all fetched records
                const transformedData = this.transformData(resp.data);
                this.countFetched = resp.data.length;
                
                // Store fetched records in a temporary storage for pagination
                this.allFetchedRecords = transformedData;
                
                // Cache pages based on pageSize from initial fetch
                this.cachePagesFromFetchedData(transformedData);
                
                this.updateCurrentPage();
                this.initialLoadDone = true;
            } else {
                this.totalCount = 0;
                this.totalPages = 1;
                this.applications = [];
            }
        } catch (e) {
            console.error('Error loading quotes', e);
            this.applications = [];
            this.totalCount = 0;
            this.totalPages = 1;
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Transform raw data from Apex into UI format
     */
    transformData(data) {
        return data.map((row) => {
            const created = row.createdDate ? new Date(row.createdDate) : new Date();
            const dateFmt = this.formatDate(created);
            const vehicle = row.vehicleName || '—';
            const services = Array.isArray(row.services) ? row.services.map(label => ({ label })) : [];
            // Determine badge status based on paymentStatus field
            let statusBadge = 'Due';
            if (row.paymentStatus && row.paymentStatus.toLowerCase() === 'paid') {
                statusBadge = 'Paid';
            }
            // Use the quoteName from the formula field (QuoteName__c)
            const quoteName = row.quoteName;
            return {
                id: row.id,
                appNumber: quoteName,
                date: dateFmt,
                customer: {
                    name: row.customerName || '',
                    address1: row.billingStreet || '',
                    address2: this.formatCityLine(row.billingCity, row.billingState, row.billingPostalCode),
                    phone: '',
                    email: ''
                },
                vehicle: {
                    name: vehicle,
                    vin: row.vehicleVin,
                    price: row.purchasePrice,
                    odometer: row.odometer,
                    odometerUnit: row.oddometerUnit ||''
                },
                services,
                statusBadge: statusBadge,
                disabledCancel: statusBadge && statusBadge.toLowerCase() === 'paid' ? true : false,
                hasFiles: !!row.hasFiles
            };
        });
    }

    /**
     * Cache pages from fetched data based on current pageSize
     */
    cachePagesFromFetchedData(data) {
        const pageCount = Math.ceil(data.length / this.pageSize);
        for (let i = 0; i < pageCount; i++) {
            const start = i * this.pageSize;
            const end = start + this.pageSize;
            const pageData = data.slice(start, end);
            this.pageCache.set(i + 1, pageData);
        }
    }

    /**
     * Update displayed page from cache or fetch if needed
     */
    async updateCurrentPage() {
        // Check if page is already cached
        if (this.pageCache.has(this.page)) {
            const cached = this.pageCache.get(this.page) || [];
            // If cached page is partial (fewer than pageSize) and we know there are more records
            // available beyond what we've fetched, fetch the needed chunk to complete the page.
            if (cached.length < this.pageSize && this.totalCount > this.countFetched) {
                // fall through to chunk fetching below
            } else {
                this.applications = cached;
                return;
            }
        }

        // Check if we need to fetch more data beyond the initial 49000
        const lastRecordNeeded = this.page * this.pageSize;
        if (this.allFetchedRecords) {
            const start = (this.page - 1) * this.pageSize;
            const end = start + this.pageSize;
            // If we have the full page cached, serve it
            if (lastRecordNeeded <= this.countFetched && this.allFetchedRecords.length >= lastRecordNeeded) {
                const pageData = this.allFetchedRecords.slice(start, end);
                this.pageCache.set(this.page, pageData);
                this.applications = pageData;
                return;
            }
            // If we have some records for this page but fewer than pageSize, fetch the next chunk to complete the page
            if (this.allFetchedRecords.length > start && this.allFetchedRecords.length < end && this.totalCount > this.countFetched) {
                const chunkIndexNeeded = Math.floor((end - 1) / this.INITIAL_FETCH_LIMIT) + 1;
                await this.fetchChunk(chunkIndexNeeded);
                if (this.pageCache.has(this.page)) {
                    this.applications = this.pageCache.get(this.page);
                    return;
                }
            }
        }

        // If we reach here, we don't have enough cached records to render the page.
        // Determine which chunk (block) we need. Each chunk is INITIAL_FETCH_LIMIT in size.
        const chunkIndexNeeded = Math.floor((lastRecordNeeded - 1) / this.INITIAL_FETCH_LIMIT) + 1;
        const currentChunksFetched = Math.ceil(this.countFetched / this.INITIAL_FETCH_LIMIT);

        // If the chunk we need hasn't been fetched yet, fetch the whole chunk (not single page)
        if (chunkIndexNeeded > currentChunksFetched && this.totalCount > this.countFetched) {
            await this.fetchChunk(chunkIndexNeeded);
            // after fetching chunk, try to serve from allFetchedRecords
            if (this.pageCache.has(this.page)) {
                this.applications = this.pageCache.get(this.page);
                return;
            }
        }

        // Fallback to fetching a single page if something unexpected happened
        await this.fetchPage(this.page);
    }

    /**
     * Fetch a chunk (block) of records of size INITIAL_FETCH_LIMIT from Apex.
     * chunkIndex is 1-based: chunkIndex=1 => offset 0..INITIAL_FETCH_LIMIT-1
     */
    async fetchChunk(chunkIndex) {
        this.isLoading = true;
        try {
            const resp = await getApplicationsList({
                pageNumber: chunkIndex,
                pageSize: this.INITIAL_FETCH_LIMIT,
                searchTerm: this.search
            });
            console.log('Fetch chunk ' + chunkIndex + ' resp:: ' + JSON.stringify(resp));
            if (resp && resp.success && Array.isArray(resp.data)) {
                // Update totalCount and totalPages
                this.totalCount = resp.totalCount || this.totalCount || 0;
                this.totalPages = Math.max(1, Math.ceil((this.totalCount || 0) / this.pageSize));

                const transformed = this.transformData(resp.data);
                // Calculate where to place this chunk in allFetchedRecords
                const expectedStart = (chunkIndex - 1) * this.INITIAL_FETCH_LIMIT;
                // Ensure allFetchedRecords length and then insert/append at expected position
                if (!this.allFetchedRecords) this.allFetchedRecords = [];
                // If the array is shorter than expectedStart, fill gaps with nulls
                while (this.allFetchedRecords.length < expectedStart) {
                    this.allFetchedRecords.push(...Array(Math.min(expectedStart - this.allFetchedRecords.length, 1000)).fill(null));
                }
                // Overwrite or append the chunk
                for (let i = 0; i < transformed.length; i++) {
                    this.allFetchedRecords[expectedStart + i] = transformed[i];
                }

                // Update countFetched to actual known records (trim nulls)
                this.countFetched = this.allFetchedRecords.filter(r => r != null).length;

                // Rebuild page cache from allFetchedRecords
                this.cachePagesFromFetchedData(this.allFetchedRecords.filter(r => r != null));

                // If the requested page falls within this new chunk, set applications
                if (this.pageCache.has(this.page)) {
                    this.applications = this.pageCache.get(this.page);
                }
            } else {
                // nothing returned
            }
        } catch (e) {
            console.error('Error fetching chunk ' + chunkIndex, e);
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Fetch a specific page from Apex
     */
    async fetchPage(pageNumber) {
        this.isLoading = true;
        try {
            const resp = await getApplicationsList({ 
                pageNumber, 
                pageSize: this.pageSize,
                searchTerm: this.search
            });
            console.log('Fetch page ' + pageNumber + ' resp:: ' + JSON.stringify(resp));
            
            if (resp && resp.success && Array.isArray(resp.data)) {
                // Update totalCount if provided and recompute totalPages for client paging
                this.totalCount = resp.totalCount || this.totalCount || 0;
                this.totalPages = Math.max(1, Math.ceil((this.totalCount || 0) / this.pageSize));
                
                const transformed = this.transformData(resp.data);
                this.pageCache.set(pageNumber, transformed);
                
                // Update count fetched
                const recordsUpToThisPage = pageNumber * this.pageSize;
                if (recordsUpToThisPage > this.countFetched) {
                    this.countFetched = recordsUpToThisPage;
                }
                
                this.applications = transformed;
            } else {
                this.applications = [];
            }
        } catch (e) {
            console.error('Error fetching page ' + pageNumber, e);
            this.applications = [];
        } finally {
            this.isLoading = false;
        }
    }

    handleSearchChange(event) {
        this.search = event.target.value || '';
        // Reset cache and reload
        this.pageCache.clear();
        this.countFetched = 0;
        this.page = 1;
        this.loadInitial();
    }

    // Pagination helpers
    async handlePagePrev() {
        if (this.page > 1) {
            this.page -= 1;
            await this.updateCurrentPage();
        }
    }

    async handlePageNext() {
        if (this.page < this.totalPages) {
            this.page += 1;
            await this.updateCurrentPage();
        }
    }

    async handlePageSizeChange(event) {
        const val = parseInt(event.target.value, 10);
        if (!isNaN(val) && val > 0) {
            this.pageSize = val;
            // Reset cache when page size changes
            this.pageCache.clear();
            this.countFetched = 0;
            this.page = 1;
            await this.loadInitial();
        }
    }

    get isFirstPage() {
        return this.page <= 1;
    }

    get isLastPage() {
        return this.page >= this.totalPages;
    }

    get paged() {
        return this.applications;
    }

    get filtered() {
        // Return data for the total count display
        return Array(this.totalCount).fill(null);
    }

    clickPrint(event) {
        event.stopPropagation();
    }

    clickDollar(event) {
        event.stopPropagation();
    }

    clickDelete(event) {
        event.stopPropagation();
        const applicationId = event.currentTarget.closest('.dp-row')?.querySelector('.record-link')?.dataset?.id;
        if (!applicationId) return;
        
        // Find the application data
        const app = this.applications.find(a => a.id === applicationId);
        if (!app) return;
        
        // Set modal data and show
        this.cancellationApplicationId = applicationId;
        this.cancellationVehicleName = app.vehicle.name;
        this.cancellationVIN = app.vehicle.vin;
        this.showCancellationModal = true;
    }

    clickConvert(event) {
        event.stopPropagation();
        const applicationId = event.currentTarget.closest('.dp-row')?.querySelector('.record-link')?.dataset?.id;
        if (!applicationId) return;
        
        const app = this.applications.find(a => a.id === applicationId);
        if (!app) return;
        
        this.convertApplicationId = applicationId;
        this.convertVehicleName = app.vehicle.name;
        this.convertVIN = app.vehicle.vin;
        this.showConvertModal = true;
    }

    handleCloseConvertModal() {
        this.showConvertModal = false;
        this.convertApplicationId = null;
        this.convertVehicleName = '';
        this.convertVIN = '';
    }

    async handleContinueToConvert() {
        if (!this.convertApplicationId) return;
        this.isConverting = true;
        try {
            const result = await convertQuoteToApplication({ applicationId: this.convertApplicationId });
            if (result.success) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Success',
                    message: 'Quote converted to application successfully',
                    variant: 'success'
                }));
                this.handleCloseConvertModal();
                // Navigate to the application detail page
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: result.recordId,
                        objectApiName: 'Application__c',
                        actionName: 'view'
                    }
                });
            } else {
                throw new Error(result.message || 'Failed to convert quote');
            }
        } catch (err) {
            const msg = (err && err.body && err.body.message) || err.message || JSON.stringify(err);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error converting quote',
                message: msg,
                variant: 'error'
            }));
            console.error('Error converting quote', err);
        } finally {
            this.isConverting = false;
        }
    }

    handleCreateNewQuote() {
        // Show the new quote confirmation modal
        this.showNewQuoteModal = true;
    }

    handleCloseNewQuoteModal() {
        this.showNewQuoteModal = false;
    }

    async handleContinueToCreateQuote() {
        // Create a new quote using Apex
        this.isCreating = true;
        try {
            const result = await createNewQuote();
            
            if (result.success && result.recordId) {
                // Navigate to the new record in view mode
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: result.recordId,
                        objectApiName: 'Application__c',
                        actionName: 'view'
                    }
                });
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Created',
                    message: 'New quote created',
                    variant: 'success'
                }));
                this.handleCloseNewQuoteModal();
            } else {
                throw new Error(result.message || 'Failed to create record');
            }
        } catch (err) {
            // Show toast with error information
            const msg = (err && err.body && err.body.message) || err.message || JSON.stringify(err);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error creating quote',
                message: msg,
                variant: 'error'
            }));
            console.error('Error creating quote', err);
        } finally {
            this.isCreating = false;
        }
    }

    handleCloseCancellationModal() {
        this.showCancellationModal = false;
        this.cancellationApplicationId = null;
        this.cancellationVehicleName = '';
        this.cancellationVIN = '';
    }

	handleContinueToCancellation() {
		// Update the application status to 'Deleted'
		if (this.cancellationApplicationId) {
			const fields = {
				Id: this.cancellationApplicationId,
				Application_Status__c: 'Deleted'
			};

			updateRecord({ fields })
				.then(() => {
					this.dispatchEvent(
						new ShowToastEvent({
							title: 'Success',
							message: 'Quote deleted successfully',
							variant: 'success'
						})
					);
					this.handleCloseCancellationModal();
					// Refresh the list by reloading
					setTimeout(() => {
						this.loadInitial();
					}, 500);
				})
				.catch((error) => {
					this.dispatchEvent(
						new ShowToastEvent({
							title: 'Error',
							message: error.body?.message || 'Failed to delete quote',
							variant: 'error'
						})
					);
				});
		}
	}

    async clickGeneratePDF(event) {
        event.stopPropagation();
        const applicationId = event.currentTarget.closest('.dp-row')?.querySelector('.record-link')?.dataset?.id;
        if (!applicationId || this.generatingPDFId) return;
        this.generatingPDFId = applicationId;
        try {
            const result = await generateQuotePDF({ applicationId });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Quote PDF generated successfully',
                variant: 'success'
            }));
            // Open the generated PDF in a new browser tab (community-safe URL)
            const cvId = result && result.contentVersionId;
            if (cvId) {
                let basePath = communityBasePath || '';
                // Remove trailing /s from community base path — servlet URLs don't use it
                basePath = basePath.replace(/\/s$/, '');
                const downloadUrl = basePath + '/sfc/servlet.shepherd/version/download/' + cvId;
                window.open(downloadUrl, '_blank');
            }
            // Update hasFiles flag for this row so View PDF button appears
            if (this.allFetchedRecords && this.allFetchedRecords.length > 0) {
                this.allFetchedRecords = this.allFetchedRecords.map(row => {
                    if (row && row.id === applicationId) {
                        return Object.assign({}, row, { hasFiles: true });
                    }
                    return row;
                });
                // Rebuild page cache and refresh current page
                this.pageCache.clear();
                this.cachePagesFromFetchedData(this.allFetchedRecords.filter(r => r != null));
                this.updateCurrentPage();
            }
        } catch (err) {
            const msg = (err && err.body && err.body.message) || err.message || JSON.stringify(err);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error generating PDF',
                message: msg,
                variant: 'error'
            }));
        } finally {
            this.generatingPDFId = null;
        }
    }

    clickViewPDF(event) {
        event.stopPropagation();
        const applicationId = event.currentTarget.closest('.dp-row')?.querySelector('.record-link')?.dataset?.id;
        if (!applicationId) return;
        const basePath = communityBasePath || '';
        const filesUrl = basePath + '/contentdocument/related/' + applicationId + '/AttachedContentDocuments';
        window.open(filesUrl, '_blank');
    }

    handleOpenRecord(event) {
        event.preventDefault();
        const recordId = event.currentTarget?.dataset?.id;
        if (!recordId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName: 'Application__c',
                actionName: 'view'
            }
        });
    }

    formatDate(d) {
        const months = [
            'JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEPT','OCT','NOV','DEC'
        ];
        const dd = String(d.getDate()).padStart(2, '0');
        const m = months[d.getMonth()];
        const yyyy = d.getFullYear();
        return `${dd}-${m}-${yyyy}`;
    }

    formatCityLine(city, state, postal) {
        const parts = [];
        if (city) parts.push(city);
        if (state) parts.push(state);
        const left = parts.join(', ');
        return [left, postal].filter(Boolean).join(' ');
    }
}