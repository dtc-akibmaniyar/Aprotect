/**
 * SignatureResourceException
 * Thrown by SignatureResourceClient for any transport / HTTP / credential failure
 * on the StaticResource endpoint. Carries the raw response body (truncated) so the
 * caller can persist a diagnosis in Application_Signature__c.Render_Error__c.
 */
public class SignatureResourceException extends Exception {
}