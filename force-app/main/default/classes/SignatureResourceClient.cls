public with sharing class SignatureResourceClient {
    public static final String NAMED_CREDENTIAL = 'SIG_Portal_PDF_Org';
    public static final String RESOURCE_PATH = '/services/data/v67.0/sobjects/StaticResource';
    public static final Integer TIMEOUT_MS = 10000;
    public static final String NAME_PREFIX = 'SIGTMP_';

    public static Id createResource(String name, String b64) {
        if (String.isBlank(name)) { throw new SignatureResourceException('createResource: name is required'); }
        if (String.isBlank(b64)) { throw new SignatureResourceException('createResource: body is required'); }
        Map<String, Object> payload = new Map<String, Object>{
            'Name' => name, 'ContentType' => 'image/png', 'CacheControl' => 'Public', 'Body' => b64 };
        HttpRequest req = buildRequest('POST', RESOURCE_PATH);
        req.setBody(JSON.serialize(payload));
        HttpResponse res = send(req);
        Integer sc = res.getStatusCode();
        String body = res.getBody() == null ? '' : res.getBody();
        if (sc < 200 || sc > 299) { throw new SignatureResourceException(describeFailure('create', sc, body)); }
        String newId = extractId(body);
        if (String.isBlank(newId)) { throw new SignatureResourceException('create: HTTP ' + sc + ' but no id in response: ' + body.left(400)); }
        try { return (Id) newId.trim(); }
        catch (Exception e) { throw new SignatureResourceException('create: unparseable resource id'); }
    }

    public static void deleteResource(String resourceId) {
        if (String.isBlank(resourceId)) { return; }
        HttpRequest req = buildRequest('DELETE', RESOURCE_PATH + '/' + String.valueOf(resourceId).trim());
        HttpResponse res = send(req);
        Integer sc = res.getStatusCode();
        if (sc == 200 || sc == 204) { return; }
        if (sc == 404) { return; }
        throw new SignatureResourceException(describeFailure('delete', sc, res.getBody()));
    }

    public static Integer bodyLength(String resourceId) {
        if (String.isBlank(resourceId)) { return null; }
        try {
            List<StaticResource> rows = [SELECT Id, BodyLength FROM StaticResource WHERE Id = :resourceId LIMIT 1];
            return rows.isEmpty() ? null : rows[0].BodyLength;
        } catch (Exception e) { return null; }
    }

    public static String newResourceName() {
        String hexed = EncodingUtil.convertToHex(Crypto.generateAesKey(128));
        return NAME_PREFIX + hexed.substring(0, 12);
    }

    private static HttpRequest buildRequest(String method, String pathAndQuery) {
        HttpRequest req = new HttpRequest();
        req.setMethod(method);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(TIMEOUT_MS);
        String token = null;
        try { token = SignatureTokenService.accessToken(); } catch (Exception e) { token = null; }
        String baseUrl = token == null ? null : orgBaseUrl();
        if (String.isNotBlank(token) && String.isNotBlank(baseUrl)) {
            req.setEndpoint(baseUrl + pathAndQuery);
            req.setHeader('Authorization', 'Bearer ' + token);
        } else {
            req.setEndpoint('callout:' + NAMED_CREDENTIAL + pathAndQuery);
        }
        return req;
    }

    private static String orgBaseUrl() {
        try {
            String base = URL.getOrgDomainUrl().toExternalForm();
            if (base.endsWith('/')) { base = base.substring(0, base.length() - 1); }
            return base;
        } catch (Exception e) { return null; }
    }

    private static HttpResponse send(HttpRequest req) {
        try { return new Http().send(req); }
        catch (CalloutException e) { throw new SignatureResourceException('callout failed: ' + e.getMessage()); }
    }

    private static String extractId(String body) {
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
            return parsed.get('id') == null ? null : String.valueOf(parsed.get('id'));
        } catch (Exception e) { return null; }
    }

    private static String describeFailure(String op, Integer sc, String body) {
        String snippet = body == null ? '' : body.left(400);
        if (sc == 401) { return 'credential token expired — re-seed the external credential (HTTP 401). ' + snippet; }
        if (sc == 403) { return op + ' denied (HTTP 403) — check the SIG Integration User permission set. ' + snippet; }
        return op + ' failed (HTTP ' + sc + '): ' + snippet;
    }
}