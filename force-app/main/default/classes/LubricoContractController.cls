/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : LubricoContractController
 * Author          : Akib Maniyar
 * Created Date    : Aug 7, 2026
 * Last Modified By: Akib Maniyar
 * Last Modified On: Aug 7, 2026
 * Description     : This class implements for supporting LubricoContract VF Page which is created to test the compatibilty to application pdf as copy of lubrico contract
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Aug 7, 2026  │ Akib Maniyar   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public class LubricoContractController {
	// ── Public properties ──────────────────────────────────────────────
    public String  termsAndConditionRecord  { get; private set; }
    public String  fileName         { get; private set; }
    public String  fileExtension    { get; private set; }
    public String  fileSizeLabel    { get; private set; }
    public String  fileType         { get; private set; }  // pdf | image | text | html | unsupported
    public String  embedDataUri     { get; private set; }  // data URI for pdf / image
    public String  textContent      { get; private set; }  // rendered text / html body
    public Boolean fileFound        { get; private set; }
    public Boolean tooLarge         { get; private set; }
    public Boolean isUnsupported    { get; private set; }
    public String  unsupportedMsg   { get; private set; }
    public String  downloadUrl      { get; private set; }  // fallback for all types

    // ── File type sets ─────────────────────────────────────────────────
    private static final Set<String> PDF_EXTS = new Set<String>{
        'pdf'
    };
    private static final Set<String> IMAGE_EXTS = new Set<String>{
        'jpg', 'jpeg', 'png', 'gif', 'bmp', 'svg', 'webp', 'tiff', 'tif'
    };
    private static final Set<String> TEXT_EXTS = new Set<String>{
        'txt', 'csv', 'log', 'xml', 'json', 'yaml', 'yml', 'md'
    };
    private static final Set<String> HTML_EXTS = new Set<String>{
        'html', 'htm'
    };
    // Recognised but not renderable inline
    private static final Set<String> BINARY_EXTS = new Set<String>{
        'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
        'zip', 'rar', '7z', 'tar', 'gz',
        'mp4', 'mov', 'avi', 'mp3', 'wav',
        'exe', 'dmg', 'pkg'
    };
    private static final Map<String, String> BINARY_LABELS = new Map<String, String>{
        'doc'  => 'Word Document',  'docx' => 'Word Document',
        'xls'  => 'Excel Spreadsheet', 'xlsx' => 'Excel Spreadsheet',
        'ppt'  => 'PowerPoint',     'pptx' => 'PowerPoint',
        'zip'  => 'ZIP Archive',    'rar'  => 'RAR Archive',
        '7z'   => '7-Zip Archive',  'tar'  => 'TAR Archive',
        'gz'   => 'GZip Archive',
        'mp4'  => 'Video File',     'mov'  => 'Video File',
        'avi'  => 'Video File',     'mp3'  => 'Audio File',
        'wav'  => 'Audio File',     'exe'  => 'Executable',
        'dmg'  => 'Disk Image',     'pkg'  => 'Package'
    };

    // ── Heap limits ────────────────────────────────────────────────────
    // Synchronous Apex heap: 6 MB total. We read the blob + base64 encode
    // it (adds ~33% overhead). Safe ceiling = 4 MB raw file size.
    private static final Integer MAX_BYTES_EMBED  = 4 * 1024 * 1024;   // 4 MB
    // Text files: much smaller — 500 KB is plenty for a CSV / log
    private static final Integer MAX_BYTES_TEXT   = 512 * 1024;         // 512 KB

    // ──────────────────────────────────────────────────────────────────
    public LubricoContractController() {
        fileFound    = false;
        tooLarge     = false;
        isUnsupported = false;

        String termsAndConditionId = 'a33G1000000eXmrIAE';

        if (String.isBlank(termsAndConditionId)) {
            return;
        }

        // ── Load Terms & Condition Record ──
        try {
            //termsAndConditionRecord = [SELECT Id, Name FROM Terms_and_Conditions__c WHERE Id = :termsAndConditionId LIMIT 1];
        } catch (QueryException e) {
			System.debug('Exception at retrieving terms and condition record : ' + e.getMessage());
            return;
        }

        // ── Get all linked ContentDocuments ──
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM   ContentDocumentLink
            WHERE  LinkedEntityId = :termsAndConditionId
            ORDER  BY SystemModstamp DESC
        ];

        if (links.isEmpty()) {
            return;
        }

        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink cdl : links) {
            docIds.add(cdl.ContentDocumentId);
        }

		List<ContentVersion> versions;
		
		versions = [
			SELECT Id, Title, FileExtension, ContentSize, VersionData
			FROM   ContentVersion
			WHERE  ContentDocumentId IN :docIds
			AND    IsLatest = true
			ORDER  BY CreatedDate DESC
			LIMIT  1
		];

        if (versions.isEmpty()) {
            return;
        }

        ContentVersion cv = versions[0];
        fileName      = cv.Title;
        fileExtension = String.isNotBlank(cv.FileExtension)
                        ? cv.FileExtension.toLowerCase().trim()
                        : '';
        fileSizeLabel = formatSize(cv.ContentSize);
        downloadUrl   = '/sfc/servlet.shepherd/version/download/'
                      + cv.Id + '?operationContext=S1';

        // ── Route by file type ──────────────────────────────────────
        if (PDF_EXTS.contains(fileExtension)) {
            handlePDF(cv);

        } else if (IMAGE_EXTS.contains(fileExtension)) {
            handleImage(cv);

        } else if (TEXT_EXTS.contains(fileExtension)) {
            handleText(cv);

        } else if (HTML_EXTS.contains(fileExtension)) {
            handleHTML(cv);

        } else if (BINARY_EXTS.contains(fileExtension)) {
            // Recognised binary — cannot render, but give a useful message
            String typeLabel = BINARY_LABELS.containsKey(fileExtension)
                               ? BINARY_LABELS.get(fileExtension)
                               : fileExtension.toUpperCase() + ' File';
            markUnsupported(typeLabel + ' files cannot be rendered inline. '
                + 'Use the Download button to open this file.');

        } else {
            // Completely unknown extension
            markUnsupported(
                'Unknown file type ".' + fileExtension + '". '
                + 'Cannot render inline — use the Download button.');
        }
    }

    // ── PDF handler ────────────────────────────────────────────────────
    private void handlePDF(ContentVersion cv) {
        fileType = 'pdf';
        if (cv.ContentSize > MAX_BYTES_EMBED) {
            tooLarge = true;
            return;
        }
        embedDataUri = 'data:application/pdf;base64,'
                     + EncodingUtil.base64Encode(cv.VersionData);
        fileFound = true;
    }

    // ── Image handler ──────────────────────────────────────────────────
    private void handleImage(ContentVersion cv) {
        fileType = 'image';
        if (cv.ContentSize > MAX_BYTES_EMBED) {
            tooLarge = true;
            return;
        }
        String mime = mimeForImage(fileExtension);
        embedDataUri = 'data:' + mime + ';base64,'
                     + EncodingUtil.base64Encode(cv.VersionData);
        fileFound = true;
    }

    // ── Plain text handler ─────────────────────────────────────────────
    private void handleText(ContentVersion cv) {
        fileType = 'text';
        if (cv.ContentSize > MAX_BYTES_TEXT) {
            tooLarge = true;
            return;
        }
        // Escape and wrap in <pre> — safe for escape="false" on the page
        textContent = '<pre style="white-space:pre-wrap;word-break:break-word;'
                    + 'font-family:\'Courier New\',Courier,monospace;font-size:9pt;">'
                    + cv.VersionData.toString().escapeHtml4()
                    + '</pre>';
        fileFound = true;
    }

    // ── HTML handler ───────────────────────────────────────────────────
    private void handleHTML(ContentVersion cv) {
        fileType = 'html';
        if (cv.ContentSize > MAX_BYTES_TEXT) {
            tooLarge = true;
            return;
        }
        // Raw HTML — rendered as-is inside the page
        // ⚠️ Only do this for internally generated / trusted HTML files
        textContent = cv.VersionData.toString();
        fileFound = true;
    }

    // ── Helpers ────────────────────────────────────────────────────────
    private void markUnsupported(String msg) {
        fileType      = 'unsupported';
        isUnsupported = true;
        unsupportedMsg = msg;
    }

    private void addError(String msg) {
        ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, msg));
    }

    private void addWarning(String msg) {
        ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.WARNING, msg));
    }

    private String heapWarning(String title, Integer size, Integer heapLimit) {
        return '"' + title + '" is ' + formatSize(size)
             + ' — exceeds the ' + formatSize(heapLimit)
             + ' inline embed limit. Use the Download button instead.';
    }

    private String formatSize(Integer bytes) {
        if (bytes == null) return '0 B';
        if (bytes >= 1024 * 1024)
            return (bytes / (1024 * 1024)) + '.' +
                   ((Math.mod(bytes, 1024 * 1024) * 10) / (1024 * 1024)) + ' MB';
        if (bytes >= 1024)
            return (bytes / 1024) + ' KB';
        return bytes + ' B';
    }

    private String mimeForImage(String ext) {
        Map<String, String> mimes = new Map<String, String>{
            'jpg'  => 'image/jpeg',
            'jpeg' => 'image/jpeg',
            'png'  => 'image/png',
            'gif'  => 'image/gif',
            'bmp'  => 'image/bmp',
            'svg'  => 'image/svg+xml',
            'webp' => 'image/webp',
            'tiff' => 'image/tiff',
            'tif'  => 'image/tiff'
        };
        return mimes.containsKey(ext) ? mimes.get(ext) : 'image/' + ext;
    }
}