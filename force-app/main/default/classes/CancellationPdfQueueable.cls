/**
 * CancellationPdfQueueable
 *
 * Fallback path for CancellationPdfService. The synchronous call runs inside the
 * dealer's Lightning/Experience Cloud transaction, where Visualforce-to-PDF
 * rendering can be refused; this retries the same work in an asynchronous
 * transaction, where the renderer is never attached to a Lightning request.
 *
 * Failure is swallowed on purpose: the request already exists and must survive a
 * missing document.
 */
public class CancellationPdfQueueable implements Queueable {

    private final Id requestId;

    public CancellationPdfQueueable(Id requestId) {
        this.requestId = requestId;
    }

    public void execute(QueueableContext context) {
        try {
            CancellationPdfService.PdfResult result = CancellationPdfService.generateAndAttach(requestId);
            if (!result.getSucceeded()) {
                System.debug(LoggingLevel.WARN, 'Cancellation PDF not stored for ' + requestId + ': ' + result.error);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Cancellation PDF queueable failed for ' + requestId + ': ' + e.getMessage());
        }
    }
}