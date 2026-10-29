/**
 * SignatureTokenService (v2)
 *
 * Mints an OAuth 2.0 client-credentials access token for the signature
 * StaticResource callout, so nothing has to be re-seeded by hand.
 *
 * Configuration: custom setting Signature_Credential__c
 *   ClientId__c, ClientSecret__c, TokenEndpoint__c, Active__c
 *
 * The setting is read in system context (this class is `without sharing`).
 * The client secret and the minted token are never logged and never placed in
 * an exception message.
 *
 * Platform Cache note: this org has no cache partition allocated, so the token
 * is memoised for the life of the transaction only.
 */
public without sharing class SignatureTokenService {

    /** Typed failure with an operator-readable message (no secrets inside). */
    public class TokenException extends Exception {}

    public static final Integer TIMEOUT_MS = 10000;

    private static String memoToken;
    private static String memoMode;

    /** Returns a token for this transaction, minting one when needed. */
    public static String accessToken() {
        if (String.isNotBlank(memoToken)) { memoMode = 'MEMO'; return memoToken; }
        mint();
        return memoToken;
    }

    /** 'MINTED' | 'MEMO' - how the last accessToken() call resolved. */
    public static String lastMode() { return memoMode; }

    /** Drops the in-transaction copy (used by tests to force a fresh mint). */
    public static void clearCache() { memoToken = null; memoMode = null; }

    /** Platform Cache is not available in this org. */
    public static Boolean cacheReady() { return false; }

    private static void mint() {
        Signature_Credential__c cfg = loadConfig();
        String endpoint = cfg.TokenEndpoint__c == null ? '' : cfg.TokenEndpoint__c.trim();
        if (!endpoint.toLowerCase().startsWith('https://')) {
            throw new TokenException('Signature token endpoint is missing or not HTTPS. Set TokenEndpoint__c on Signature_Credential__c.');
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setHeader('Accept', 'application/json');
        req.setBody('grant_type=client_credentials'
            + '&client_id=' + EncodingUtil.urlEncode(cfg.ClientId__c.trim(), 'UTF-8')
            + '&client_secret=' + EncodingUtil.urlEncode(cfg.ClientSecret__c.trim(), 'UTF-8'));
        req.setTimeout(TIMEOUT_MS);

        HttpResponse res;
        try { res = new Http().send(req); }
        catch (Exception e) {
            throw new TokenException('Signature token request could not reach the token endpoint: ' + e.getMessage());
        }

        Integer sc = res.getStatusCode();
        if (sc < 200 || sc > 299) {
            throw new TokenException('Signature token request was rejected (HTTP ' + sc + '). Check Client Id and Client Secret on Signature_Credential__c' + errorHint(res) + '.');
        }

        String token;
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            token = parsed.get('access_token') == null ? null : String.valueOf(parsed.get('access_token'));
        } catch (Exception e) { token = null; }

        if (String.isBlank(token)) {
            throw new TokenException('Signature token endpoint returned no access_token. Check the Connected App client-credentials flow.');
        }
        memoToken = token;
        memoMode = 'MINTED';
    }

    /** Reads the setting in system context. */
    private static Signature_Credential__c loadConfig() {
        List<Signature_Credential__c> rows = [SELECT ClientId__c, ClientSecret__c, TokenEndpoint__c, Active__c FROM Signature_Credential__c LIMIT 1];
        if (rows.isEmpty()) {
            throw new TokenException('Signature_Credential__c is not configured. Set Client Id, Client Secret, Token Endpoint and Active on its org default.');
        }
        Signature_Credential__c cfg = rows[0];
        if (cfg.Active__c != true) {
            throw new TokenException('Signature_Credential__c is not active. Tick Active on its org default once the Client Id and Secret are entered.');
        }
        if (String.isBlank(cfg.ClientId__c) || String.isBlank(cfg.ClientSecret__c)) {
            throw new TokenException('Signature_Credential__c is missing the Client Id or Client Secret. Enter both on its org default.');
        }
        return cfg;
    }

    /** Short, secret-free hint from an OAuth error body. */
    private static String errorHint(HttpResponse res) {
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            if (parsed.get('error') == null) { return ''; }
            String detail = String.valueOf(parsed.get('error'));
            if (parsed.get('error_description') != null) { detail += ': ' + String.valueOf(parsed.get('error_description')); }
            return ' [' + detail.left(160) + ']';
        } catch (Exception e) { return ''; }
    }
}