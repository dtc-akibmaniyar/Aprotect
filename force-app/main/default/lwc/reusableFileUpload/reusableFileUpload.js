import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

// Import file handling methods
import getPackageFiles from '@salesforce/apex/DealerPortalFileHandler.getPackageFiles';
import saveFilesToPackage from '@salesforce/apex/DealerPortalFileHandler.saveFilesToPackage';
import getPDFContent from '@salesforce/apex/DealerPortalFileHandler.getPDFContent';
import removeFileFromPackage from '@salesforce/apex/DealerPortalFileHandler.removeFileFromPackage';

/**
 * Reusable File Upload Component
 * Can be integrated with any parent LWC component
 * FEATURES: Upload, View, Download, and Remove files
 */
export default class ReusableFileUpload extends NavigationMixin(LightningElement) {
    
    // ===============================
    // PUBLIC PROPERTIES (CONFIGURABLE)
    // ===============================
    
    isConnected = false;
    _recordId;
    @api title = 'File Manager';
    @api uploadLabel = 'Upload Files';
    @api acceptedFileTypes = '.pdf';
    @api allowMultipleFiles = false;
    @api autoLoadFiles = false;
    @api allowRemove;
    
    // ===============================
    // INTERNAL PROPERTIES
    // ===============================
    
    @track existingFiles = [];
    @track isLoading = false;
    @track uploadInProgress = false;
    @track pdfViewLoading = false;
    @track removingFileId = null;
    
    // Private flag to prevent multiple loads
    _hasLoadedFiles = false;
    
    // ===============================
    // COMPUTED PROPERTIES
    // ===============================

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        if (this._recordId !== value) {
            this._recordId = value;

            // Reset state for new record
            this._hasLoadedFiles = false;
            this.existingFiles = [];
            this.removingFileId = null;

            // If we're already connected, load immediately
            if (this._isConnected && this._recordId) {
                this.loadExistingFiles();
            }
        }
    }
    
    get showSection() {
        return !!this.recordId;
    }
    
    get hasExistingFiles() {
        return this.existingFiles && this.existingFiles.length > 0;
    }
    
    get showUpload() {
        return !!this.recordId && !this.isLoading;
    }
    
    get showEmptyState() {
        return !this.hasExistingFiles && !this.showUpload && !this.isLoading && !!this.recordId;
    }
    
    // Check if remove functionality is enabled
    get isRemoveEnabled() {
        return this.allowRemove !== false; // Default to true unless explicitly set to false
    }
    
    // Helper to check if a specific file is being removed
    isFileBeingRemoved(fileId) {
        return this.removingFileId === fileId;
    }
    
    // ===============================
    // LIFECYCLE METHODS
    // ===============================
    
    connectedCallback() {
        console.log('🎯 reusableFileUpload connected with recordId:', this.recordId);
        this._isConnected = true;
        // if record id was set before connect, load now
        if (this._recordId && !this._hasLoadedFiles && !this.isLoading) {
            this._hasLoadedFiles = true;
            this.loadExistingFiles();
        }
    }
    
    renderedCallback() {
        console.log('in renderedCallback');
        console.log(this.recordId);
        console.log(this._hasLoadedFiles);
        console.log(this.isLoading);
        // Auto-load files when recordId is available (only once)
        if (this._recordId && !this._hasLoadedFiles && !this.isLoading) {
            this._hasLoadedFiles = true;
            this.loadExistingFiles();
        }
    }
    
    // ===============================
    // PUBLIC METHODS (API)
    // ===============================
    
    @api
    refreshFiles() {
        this._hasLoadedFiles = true;
        return this.loadExistingFiles();
    }
    
    @api
    getFileCount() {
        return this.existingFiles ? this.existingFiles.length : 0;
    }
    
    @api
    getFiles() {
        return this.existingFiles ? [...this.existingFiles] : [];
    }
    
    // ===============================
    // EVENT HANDLERS
    // ===============================
    
    // *** SIMPLIFIED: File upload handler with simple success message ***
    async handleFileUpload(event) {
        try {
            this.uploadInProgress = true;
            const uploadedFiles = event.detail.files;
            console.log('📁 Files uploaded:', uploadedFiles.length);
            
            if (!uploadedFiles || uploadedFiles.length === 0) {
                this.showToast('Warning', 'No files were uploaded', 'warning');
                return;
            }
            
            // Extract ContentDocument IDs
            const contentDocumentIds = uploadedFiles.map(file => file.documentId);
            console.log('📋 ContentDocument IDs:', contentDocumentIds);
            
            // Save files using the file handler
            const result = await saveFilesToPackage({ 
                packageId: this.recordId, 
                contentDocumentIds: contentDocumentIds 
            });
            
            console.log('💾 Save result:', result);
            
            if (result && result.success) {
                // *** SIMPLIFIED: Always show simple success message ***
                this.showToast('Success', 'File uploaded successfully', 'success');
                
                // Refresh file list
                await this.loadExistingFiles();
                
                // Emit upload success event
                this.dispatchEvent(new CustomEvent('filesuploaded', {
                    detail: {
                        uploadedFiles: uploadedFiles,
                        totalFiles: this.existingFiles ? this.existingFiles.length : 0,
                        recordId: this.recordId,
                        newFiles: result.fileCount || 0
                    }
                }));
            } else {
                // Handle errors
                const errorMessage = result ? result.message : 'Unknown error occurred';
                console.error('❌ Upload failed:', errorMessage);
                
                // Check for specific error types
                if (errorMessage.includes('already linked')) {
                    this.showToast('Info', 'File is already associated with this package.', 'info');
                } else {
                    this.showToast('Error', 'Upload failed: ' + errorMessage, 'error');
                }
            }
            
        } catch (error) {
            console.error('💥 File upload error:', error);
            
            // Better error classification
            let errorMessage = 'File upload failed';
            
            if (error.body && error.body.message) {
                errorMessage = error.body.message;
                
                // Handle specific database errors
                if (errorMessage.includes('already linked')) {
                    this.showToast('Info', 'File is already associated with this package.', 'info');
                    // Still refresh to show current state
                    await this.loadExistingFiles();
                    return;
                }
            } else if (error.message) {
                errorMessage = error.message;
            }
            
            this.showToast('Error', errorMessage, 'error');
        } finally {
            this.uploadInProgress = false;
        }
    }
    
    // File removal handler
    async handleFileRemove(event) {
        event.preventDefault();
        event.stopPropagation();
        
        const contentDocumentId = event.currentTarget.dataset.documentId;
        const fileName = event.currentTarget.dataset.fileName;
        
        if (!contentDocumentId) {
            this.showToast('Error', 'Invalid file selected for removal', 'error');
            return;
        }
        
        // Show confirmation dialog
        const confirmed = await this.showConfirmDialog(
            'Remove File', 
            `Are you sure you want to remove "${fileName}" from this package?\n\nNote: This will only remove the file association, not delete the file permanently.`
        );
        
        if (!confirmed) {
            return; // User cancelled
        }
        
        console.log('🗑️ Removing file:', fileName, contentDocumentId);
        
        try {
            this.removingFileId = contentDocumentId;
            
            // Call Apex method to remove file
            const result = await removeFileFromPackage({ 
                packageId: this.recordId, 
                contentDocumentId: contentDocumentId 
            });
            
            if (result && result.success) {
                console.log('✅ File removed successfully');
                this.showToast('Success', result.message, 'success');
                
                // Refresh file list
                await this.loadExistingFiles();
                
                // Emit file removed event
                this.dispatchEvent(new CustomEvent('fileremoved', {
                    detail: {
                        removedFileId: contentDocumentId,
                        fileName: fileName,
                        totalFiles: this.existingFiles ? this.existingFiles.length : 0,
                        recordId: this.recordId
                    }
                }));
            } else {
                const errorMessage = result ? result.message : 'Unknown error occurred';
                console.error('❌ File removal failed:', errorMessage);
                this.showToast('Error', 'Failed to remove file: ' + errorMessage, 'error');
            }
            
        } catch (error) {
            console.error('💥 File removal error:', error);
            
            let errorMessage = 'Failed to remove file';
            if (error.body && error.body.message) {
                errorMessage = error.body.message;
            } else if (error.message) {
                errorMessage = error.message;
            }
            
            this.showToast('Error', errorMessage, 'error');
        } finally {
            this.removingFileId = null;
        }
    }
    
    // Show confirmation dialog
    async showConfirmDialog(title, message) {
        return new Promise((resolve) => {
            const confirmed = confirm(message);
            resolve(confirmed);
        });
    }
    
    // PDF viewing handler
    async handleFileView(event) {
        event.preventDefault();
        event.stopPropagation();
        console.log(event.currentTarget.dataset.downloadUrl);
        console.log(event.currentTarget.dataset.contentDocumentId);
        const fileId = event.currentTarget.dataset.downloadUrl;
        const downloadUrl = event.currentTarget.dataset.downloadUrl; // Get downloadUrl from dataset
        const fileName = event.currentTarget.dataset.fileName;
        
        if (!downloadUrl) {
            this.showToast('Error', 'Invalid file selected for view', 'error');
            return;
        }
        // this[NavigationMixin.Navigate]({
        //     type: 'standard__recordPage',
        //     attributes: {
        //         recordId: fileId,
        //         objectApiName: 'ContentDocument',
        //         actionName: 'view'
        //     }
        // });
        //const basePath = getBasePath(); // e.g., "/s/"
        
        // Construct a safe, relative URL to the record page
        const url = `/dealerportal/s/contentdocument/${downloadUrl}`;
        console.log(downloadUrl);
        window.open(url, '_blank');
        console.log('👁️ Opening PDF in new tab:', fileName, downloadUrl);
        
        // try {
        //     // Previous code using Base64 and Blob URLs (commented out)
            
        //     this.pdfViewLoading = true;
        //     const contentDocumentId = event.currentTarget.dataset.documentId;
        //     const result = await getPDFContent({ contentDocumentId: contentDocumentId });
            
        //     if (!result || !result.success) {
        //         throw new Error(result?.error || 'Failed to retrieve PDF content');
        //     }
        //     console.log('✅ PDF content retrieved successfully');
        //     this.openPDFInNewTab(result.base64Data, result.fileName || fileName);
            
            
        //     // Use NavigationMixin to open the URL in a new tab
        //     // this[NavigationMixin.Navigate]({
        //     //     type: 'standard__webPage',
        //     //     attributes: {
        //     //         url: downloadUrl
        //     //     }
        //     // }, false); // Set to false to open in a new tab/window
            
        //     console.log('✅ PDF opened in new tab successfully');
            
        // } catch (error) {
        //     console.error('❌ PDF view error:', error);
        //     this.showToast('Error', 'Failed to open PDF: ' + error.message, 'error');
        // } finally {
        //     // this.pdfViewLoading = false; // Only relevant for the commented-out code
        // }
    }
    
    // Open PDF in new browser tab (commented out as it's no longer used directly)
    
    openPDFInNewTab(base64Data, fileName) {
        try {
            console.log('📄 Opening PDF in new tab:', fileName);
            const byteCharacters = atob(base64Data);
            const byteNumbers = new Array(byteCharacters.length);
            for (let i = 0; i < byteCharacters.length; i++) {
                byteNumbers[i] = byteCharacters.charCodeAt(i);
            }
            const byteArray = new Uint8Array(byteNumbers);
            const blob = new Blob([byteArray], { type: 'application/pdf' });
            const url = URL.createObjectURL(blob);
            const newWindow = window.open(url, '_blank');
            
            if (!newWindow) {
                this.showToast('Info', 'Popup blocked. Please allow popups for this site to view PDFs.', 'info');
                const link = document.createElement('a');
                link.href = url;
                link.download = fileName;
                link.style.display = 'none';
                document.body.appendChild(link);
                link.click();
                document.body.removeChild(link);
            } else {
                setTimeout(() => {
                    try {
                        newWindow.document.title = fileName;
                    } catch (e) {
                    }
                }, 100);
            }
            setTimeout(() => {
                URL.revokeObjectURL(url);
            }, 30000); 
            console.log('✅ PDF opened in new tab successfully');
        } catch (error) {
            console.error('❌ Error opening PDF in new tab:', error);
            throw new Error('Failed to open PDF in new tab: ' + error.message);
        }
    }
    
    
    // File download handler
    handleFileDownload(event) {
        event.preventDefault();
        const downloadUrl = event.currentTarget.dataset.downloadUrl;
        const fileName = event.currentTarget.dataset.fileName;
        
        if (downloadUrl) {
            console.log('⬇️ Downloading file:', fileName);
            // Use the original download URL for direct download
            window.open(downloadUrl, '_blank');
        }
    }
    
    // ===============================
    // PRIVATE METHODS
    // ===============================
    
    async loadExistingFiles() {
        try {
            this.isLoading = true;
            console.log('🗂️ Loading files for recordId:', this.recordId);
            
            const result = await getPackageFiles({ packageId: this.recordId });
            
            if (result && result.success) {
                this.existingFiles = result.data || [];
                console.log('✅ Loaded', this.existingFiles.length, 'existing files');
                
                // Emit file loaded event
                this.dispatchEvent(new CustomEvent('filesloaded', {
                    detail: {
                        files: this.existingFiles,
                        fileCount: this.existingFiles.length,
                        recordId: this.recordId
                    }
                }));
            } else {
                console.warn('⚠️ Failed to load files:', result ? result.message : 'Unknown error');
                this.existingFiles = [];
            }
            
        } catch (error) {
            console.error('❌ Error loading existing files:', error);
            this.existingFiles = [];
            this.showToast('Error', 'Failed to load existing files: ' + error.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    // Improved toast messaging
    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            mode: 'dismissible',
            duration: this.getToastDuration(variant)
        });
        this.dispatchEvent(evt);
    }
    
    // Helper to determine toast duration based on importance
    getToastDuration(variant) {
        switch (variant) {
            case 'error':
                return 8000; // 8 seconds for errors
            case 'warning':
                return 5000; // 5 seconds for warnings
            case 'info':
                return 4000; // 4 seconds for info
            case 'success':
            default:
                return 3000; // 3 seconds for success
        }
    }
    
    // Helper method to format file name for display
    formatFileName(fileName, maxLength = 50) {
        if (!fileName) return 'Unnamed File';
        if (fileName.length <= maxLength) return fileName;
        
        const extension = fileName.split('.').pop();
        const name = fileName.substring(0, fileName.lastIndexOf('.'));
        const truncated = name.substring(0, maxLength - extension.length - 4) + '...';
        return truncated + '.' + extension;
    }
}