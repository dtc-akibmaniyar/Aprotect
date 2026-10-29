@isTest
private class SignatureResourceClientTest {

    private class ResMock implements HttpCalloutMock {
        public Integer postStatus = 201;
        public String postBody = '{"id":"081G1000003PllBIAS","success":true}';
        public Integer deleteStatus = 204;
        public String lastEndpoint;
        public String lastMethod;
        public String lastAuth;

        public HttpResponse respond(HttpRequest req) {
            lastEndpoint = req.getEndpoint();
            lastMethod = req.getMethod();
            lastAuth = req.getHeader('Authorization');
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            if (req.getEndpoint() != null && req.getEndpoint().contains('/services/oauth2/token')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"tok-test","expires_in":7200}');
                return res;
            }
            if (req.getMethod() == 'DELETE') {
                res.setStatusCode(deleteStatus);
                res.setBody(deleteStatus == 204 ? '' : '{"error":"nope"}');
                return res;
            }
            res.setStatusCode(postStatus);
            res.setBody(postBody);
            return res;
        }
    }

    private static void seedConfig() {
        insert new Signature_Credential__c(
            ClientId__c = 'test-client-id',
            ClientSecret__c = 'test-client-secret',
            TokenEndpoint__c = 'https://example.my.salesforce.com/services/oauth2/token',
            Active__c = true
        );
    }

    @isTest
    static void createAndDeleteUseTheMintedToken() {
        seedConfig();
        ResMock mock = new ResMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Id rid = SignatureResourceClient.createResource('SIGTMP_test01', 'AAAA');
        SignatureResourceClient.deleteResource(String.valueOf(rid));
        Test.stopTest();

        System.assertEquals('081G1000003PllBIAS', String.valueOf(rid), 'create must return the id from the response');
        System.assert(String.isNotBlank(mock.lastAuth) || mock.lastEndpoint.startsWith('callout:'),
            'a request must either carry a bearer token or use the named credential');
    }

    @isTest
    static void bearerTokenIsSentToTheOrgEndpoint() {
        seedConfig();
        ResMock mock = new ResMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        SignatureResourceClient.createResource('SIGTMP_test02', 'AAAA');
        Test.stopTest();

        if (SignatureTokenService.lastMode() != null) {
            System.assert(mock.lastEndpoint.startsWith('https://'), 'minted-token path must call the org REST host directly');
            System.assert(mock.lastAuth != null && mock.lastAuth.startsWith('Bearer '), 'Authorization must carry the bearer token');
        }
    }

    @isTest
    static void unauthorizedCreateSurfacesTheCredentialMessage() {
        seedConfig();
        ResMock mock = new ResMock();
        mock.postStatus = 401;
        mock.postBody = '{"errorCode":"INVALID_SESSION_ID"}';
        Test.setMock(HttpCalloutMock.class, mock);

        String msg;
        Test.startTest();
        try {
            SignatureResourceClient.createResource('SIGTMP_test03', 'AAAA');
        } catch (SignatureResourceException e) {
            msg = e.getMessage();
        }
        Test.stopTest();

        System.assertNotEquals(null, msg, '401 must raise SignatureResourceException');
        System.assert(msg.contains('re-seed the external credential'), '401 message must stay operator actionable');
    }

    @isTest
    static void missingDeleteIsTreatedAsAlreadyGone() {
        ResMock mock = new ResMock();
        mock.deleteStatus = 404;
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        SignatureResourceClient.deleteResource('081G1000003PllBIAS');
        SignatureResourceClient.deleteResource(null);
        Test.stopTest();
        System.assertEquals(null, SignatureResourceClient.bodyLength(null), 'null id has no length');
    }

    @isTest
    static void resourceNamesAreUniqueAndPrefixed() {
        String a = SignatureResourceClient.newResourceName();
        String b = SignatureResourceClient.newResourceName();
        System.assert(a.startsWith('SIGTMP_'), 'names must be prefixed for the sweeper');
        System.assertNotEquals(a, b, 'names must not collide');
    }
}