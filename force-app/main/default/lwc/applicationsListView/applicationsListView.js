import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { updateRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getApplicationsList from '@salesforce/apex/ApplicationsListViewController.getApplicationsList';
import createNewApplication from '@salesforce/apex/ApplicationsListViewController.createNewApplication';
import getUnpaidApplications from '@salesforce/apex/DealerActionBoardController.getUnpaidApplications';
import createRemittanceForm from '@salesforce/apex/DealerPortalRemittanceHandler.createRemittanceForm';

export default class ApplicationsListView extends NavigationMixin(LightningElement) {
	@track isLoading = true;
	@track search = '';
	@track fromDate = '';
	@track toDate = '';
	@track showDateFilter = false;
	@track isDateFilterApplied = false;
	@track page = 1;
	@track pageSize = 10;
	@track totalPages = 1;
	@track totalCount = 0;
	@track applications = [];
	@track showCancellationModal = false;
	@track cancellationApplicationId = null;
	@track cancellationVehicleName = '';
	@track cancellationVIN = '';
	@track cancellationApplicationStatus = '';
	@track showNewApplicationModal = false;
	@track statusFilter = 'Pending';
	@track paymentDueDateFilter = 'All';
	@track showMakePaymentModal = false;
	@track unpaidApplications = [];
	@track isLoadingApplications = false;

	// Payment due date filter options
	get paymentDueDateOptions() {
		return [
			{ label: 'All', value: 'All' },
			{ label: '30 Days', value: '30' },
			{ label: '60 Days', value: '60' },
			{ label: '90 Days', value: '90' }
		];
	}

	get isPaymentDueAll() { return this.paymentDueDateFilter === 'All'; }
	get isPaymentDue30() { return this.paymentDueDateFilter === '30'; }
	get isPaymentDue60() { return this.paymentDueDateFilter === '60'; }
	get isPaymentDue90() { return this.paymentDueDateFilter === '90'; }

	// Wire CurrentPageReference to handle navigation state
	@wire(CurrentPageReference)
	pageStateChange(currentPageReference) {
		if (currentPageReference && currentPageReference.state && currentPageReference.state.statusFilter) {
			this.statusFilter = currentPageReference.state.statusFilter;
		}
	}

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

	renderedCallback() {
		const select = this.template.querySelector('.dp-status-select');
		if (select && select.value !== this.statusFilter) {
			select.value = this.statusFilter;
		}
		const dueDateSelect = this.template.querySelector('.dp-due-date-select');
		if (dueDateSelect && dueDateSelect.value !== this.paymentDueDateFilter) {
			dueDateSelect.value = this.paymentDueDateFilter;
		}
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
				searchTerm: this.search,
				statusFilter: this.statusFilter,
				fromDate: this.fromDate,
				toDate: this.toDate
			});
			console.log('Initial load resp:: ' + JSON.stringify(resp));
			
			if (resp && resp.success && Array.isArray(resp.data)) {
				// Transform and cache all fetched records
				const transformedData = this.transformData(resp.data);
				this.countFetched = resp.data.length;
				
				// Store fetched records in a temporary storage for pagination
				this.allFetchedRecords = transformedData;

				// Apply payment due date filter client-side
				const filteredData = this.applyPaymentDueDateFilter(transformedData);
				
				this.totalCount = filteredData.length;
				// Compute client-side totalPages based on current pageSize
				this.totalPages = Math.max(1, Math.ceil((this.totalCount || 0) / this.pageSize));
				this.page = 1;
				
				// Cache pages based on pageSize from filtered data
				this.cachePagesFromFetchedData(filteredData);
				
				this.updateCurrentPage();
				this.initialLoadDone = true;
			} else {
				this.totalCount = 0;
				this.totalPages = 1;
				this.applications = [];
			}
		} catch (e) {
			console.error('Error loading applications', e);
			this.applications = [];
			this.totalCount = 0;
			this.totalPages = 1;
		} finally {
			this.isLoading = false;
		}
	}

	/**
	 * Apply payment due date filter on client-side
	 */
	applyPaymentDueDateFilter(data) {
		if (this.paymentDueDateFilter === 'All') {
			return data;
		}
		const days = parseInt(this.paymentDueDateFilter, 10);
		if (isNaN(days)) return data;

		const today = new Date();
		today.setHours(0, 0, 0, 0);
		const cutoffDate = new Date(today);
		cutoffDate.setDate(cutoffDate.getDate() + days);

		return data.filter(app => {
			if (!app.paymentDueDate) return false;
			const dueDate = new Date(app.paymentDueDate);
			dueDate.setHours(0, 0, 0, 0);
			return dueDate >= today && dueDate <= cutoffDate;
		});
	}

	/**
	 * Handle payment due date filter change
	 */
	handlePaymentDueDateFilterChange(event) {
		this.paymentDueDateFilter = event.target.value;
		// Re-apply filter from cached data
		this.pageCache.clear();
		this.page = 1;

		const filteredData = this.applyPaymentDueDateFilter(this.allFetchedRecords);
		this.totalCount = filteredData.length;
		this.totalPages = Math.max(1, Math.ceil(this.totalCount / this.pageSize));
		this.cachePagesFromFetchedData(filteredData);
		this.updateCurrentPage();
	}

	/**
	 * Transform raw data from Apex into UI format
	 */
	transformData(data) {
		return data.map((row) => {
			const created = row.createdDate ? new Date(row.createdDate) : new Date();
			const dateFmt = this.formatDate(created);
			const vehicle = row.vehicleName || '—';
			const services = Array.isArray(row.services) ? row.services.map((item) => {
				// Format prices if they exist
				const costPriceWithTax = item.costPriceWithTax ? `$${item.costPriceWithTax}` : '';
				const costPriceWithoutTax = item.costPriceWithoutTax ? `$${item.costPriceWithoutTax}` : '';
				return {
					label: item.label,
					costPriceWithTax: costPriceWithTax,
					costPriceWithoutTax: costPriceWithoutTax
				};
			}) : [];
			// Use actual payment status from the record
			let statusBadge = row.paymentStatus || 'Due';
			return {
				id: row.id,
				appNumber: row.appNumber,
				date: dateFmt,
				paymentDueDate: row.paymentDueDate || null,
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
				applicationStatus: row.applicationStatus || '',
				invoiceId: row.invoiceId || null,
				disabledCancel: (statusBadge && statusBadge.toLowerCase() !== 'due') || 
					['cancelled', 'deleted'].includes((row.applicationStatus || '').toLowerCase()) ||
					(row.cancellationStatus && ['pending sales review', 'pending accounting review', 'approved', 'cancelled'].includes(row.cancellationStatus.toLowerCase())),
				cancellationBadge: (row.cancellationStatus && ['Pending Sales Review', 'Pending Accounting Review'].includes(row.cancellationStatus)) ? 'Pending-Cancellation' : '',
				cancellationBadgeLabel: (row.cancellationStatus && ['Pending Sales Review', 'Pending Accounting Review'].includes(row.cancellationStatus)) ? 'Cancellation Requested' : '',
				showCancellationBadge: !!(row.cancellationStatus && ['Pending Sales Review', 'Pending Accounting Review'].includes(row.cancellationStatus)),
			remittanceDisabled: row.applicationStatus === 'Active'
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
				searchTerm: this.search,
				statusFilter: this.statusFilter,
				fromDate: this.fromDate,
				toDate: this.toDate
			});
			console.log('Fetch chunk ' + chunkIndex + ' resp:: ' + JSON.stringify(resp));
			if (resp && resp.success && Array.isArray(resp.data)) {
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

				// Apply payment due date filter and rebuild pages
				const filteredData = this.applyPaymentDueDateFilter(this.allFetchedRecords.filter(r => r != null));
				this.totalCount = filteredData.length;
				this.totalPages = Math.max(1, Math.ceil(this.totalCount / this.pageSize));
				this.cachePagesFromFetchedData(filteredData);

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
				searchTerm: this.search,
				statusFilter: this.statusFilter,
				fromDate: this.fromDate,
				toDate: this.toDate
			});
			
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

	handleFromDateChange(event) {
		this.fromDate = event.target.value || '';
	}

	handleToDateChange(event) {
		this.toDate = event.target.value || '';
	}

	handleFilterIconClick() {
		this.showDateFilter = !this.showDateFilter;
	}

	handleDateSearch() {
		this.showDateFilter = false;
		this.isDateFilterApplied = true;
		this.pageCache.clear();
		this.countFetched = 0;
		this.page = 1;
		this.loadInitial();
	}

	handleDateReset() {
		this.fromDate = '';
		this.toDate = '';
		this.showDateFilter = false;
		this.isDateFilterApplied = false;
		this.pageCache.clear();
		this.countFetched = 0;
		this.page = 1;
		this.loadInitial();
	}

	get isDateSearchDisabled() {
		return !this.fromDate || !this.toDate;
	}

	get filterIconClass() {
		if (this.isDateFilterApplied) return 'dp-date-icon-btn dp-date-icon-btn--applied';
		if (this.showDateFilter) return 'dp-date-icon-btn dp-date-icon-btn--active';
		return 'dp-date-icon-btn';
	}


	handleFilterSubmittedChange(event) {
		this.statusFilter = event.target.value;
		// Reset pagination and reload when filter changes
		this.pageCache.clear();
		this.countFetched = 0;
		this.page = 1;
		this.loadInitial();
	}

	handleStatusFilterChange(event) {
		this.statusFilter = event.target.value;
		// Reset pagination and reload when filter changes
		this.pageCache.clear();
		this.countFetched = 0;
		this.page = 1;
		this.loadInitial();
	}

	handleFilterPendingChange(event) {
		this.statusFilter = event.target.value;
		// Reset pagination and reload when filter changes
		this.pageCache.clear();
		this.countFetched = 0;
		this.page = 1;
		this.loadInitial();
	}

	get hasDueSubmittedApplications() {
		const records = this.allFetchedRecords || [];
		return records.some(app =>
			app && app.applicationStatus === 'Submitted' && app.statusBadge !== 'Paid'
		);
	}

	async clickNewApplication() {
		// Show the new application confirmation modal
		this.showNewApplicationModal = true;
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

	get isSubmittedStatus() {
		return this.cancellationApplicationStatus && this.cancellationApplicationStatus.toLowerCase() === 'submitted';
	}

	get isPendingSelected() {
		return this.statusFilter === 'Draft';
	}

	get isSubmittedSelected() {
		return this.statusFilter === 'Submitted';
	}

	get isCancelledSelected() {
		return this.statusFilter === 'Cancelled';
	}

	get isPendingCancellationSelected() {
		return this.statusFilter === 'Pending Cancellation';
	}

	get isAllSelected() {
		return this.statusFilter === 'All';
	}

	clickPrint(event) {
		event.stopPropagation();
		// Get the application ID from the row
		const appId = event.currentTarget.closest('.dp-row')?.querySelector('.record-link')?.dataset?.id;
		if (!appId) return;
		
		// Construct the URL to the related files page
		const baseUrl = 'https://' + location.host;
		const previewUrl = baseUrl + '/dealerportal/s/contentdocument/related/' + appId + '/AttachedContentDocuments';
		
		const pageRef = {
			type: 'standard__webPage',
			attributes: {
				url: previewUrl
			}
		};
		
		this[NavigationMixin.GenerateUrl](pageRef).then(url => {
			window.open(url, '_blank');
		});
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
		this.cancellationApplicationStatus = app.applicationStatus;
		this.showCancellationModal = true;
	}

	handleCloseCancellationModal() {
		// Close the cancellation modal and reload the list to reflect any changes
		this.showCancellationModal = false;
		this.cancellationApplicationId = null;
		this.cancellationVehicleName = '';
		this.cancellationVIN = '';
		this.cancellationApplicationStatus = '';
		// Reload list to pick up status changes from cancellation flow
		this.loadInitial();
	}

	handleCloseNewApplicationModal() {
		this.showNewApplicationModal = false;
	}

	async handleContinueToCreateApplication() {
		// Create a new Application using Apex with 'Application' record type
		this.isLoading = true;
		try {
			const result = await createNewApplication();
			
			if (result.success && result.recordId) {
				// Navigate to the new record in view mode so the user can fill details
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
					message: 'New application created',
					variant: 'success'
				}));
				this.handleCloseNewApplicationModal();
			} else {
				throw new Error(result.message || 'Failed to create record');
			}
		} catch (err) {
			// Show toast with error information
			const msg = (err && err.body && err.body.message) || err.message || JSON.stringify(err);
			this.dispatchEvent(new ShowToastEvent({
				title: 'Error creating application',
				message: msg,
				variant: 'error'
			}));
			console.error('Error creating application', err);
		} finally {
			this.isLoading = false;
		}
	}

	async handleOpenMakePaymentModal() {
		this.showMakePaymentModal = true;
		this.unpaidApplications = [];
		this.isLoadingApplications = true;
		try {
			const apps = await getUnpaidApplications();
			this.unpaidApplications = apps || [];
		} catch (err) {
			const msg = (err && err.body && err.body.message) || err.message || JSON.stringify(err);
			this.dispatchEvent(new ShowToastEvent({
				title: 'Error loading applications',
				message: msg,
				variant: 'error'
			}));
		} finally {
			this.isLoadingApplications = false;
		}
	}

	handleCloseMakePaymentModal() {
		this.showMakePaymentModal = false;
		this.unpaidApplications = [];
	}

	async handleCreateRemittanceFromModal(event) {
		const { applicationIds } = event.detail;
		try {
			const result = await createRemittanceForm({ applicationIds });
			if (result.success && result.remittanceFormId) {
				this.handleCloseMakePaymentModal();
				this[NavigationMixin.Navigate]({
					type: 'standard__recordPage',
					attributes: {
						recordId: result.remittanceFormId,
						objectApiName: 'Remittance_Form__c',
						actionName: 'view'
					}
				});
				this.dispatchEvent(new ShowToastEvent({
					title: 'Success',
					message: 'Remittance form created successfully',
					variant: 'success'
				}));
			} else {
				throw new Error(result.message || 'Failed to create remittance form');
			}
		} catch (err) {
			const msg = (err && err.body && err.body.message) || err.message || JSON.stringify(err);
			this.dispatchEvent(new ShowToastEvent({
				title: 'Error',
				message: msg,
				variant: 'error'
			}));
		}
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

	clickViewInvoice(event) {
		event.preventDefault();
		const invoiceId = event.currentTarget?.dataset?.id;
		if (!invoiceId) return;
		
		const pageRef = {
			type: 'standard__recordPage',
			attributes: {
				recordId: invoiceId,
				objectApiName: 'Invoice__c',
				actionName: 'view'
			}
		};
		
		this[NavigationMixin.GenerateUrl](pageRef).then(url => {
			window.open(url, '_blank');
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