@isTest
private class ZZ_SigProbe_Tests {
    class Mock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setHeader('Content-Type', 'application/json');
            if (req.getMethod() == 'POST') {
                res.setStatusCode(201);
                res.setBody('{"id":"081000000000001","success":true,"errors":[]}');
            } else if (req.getMethod() == 'DELETE') {
                res.setStatusCode(204);
                res.setBody('');
            } else {
                res.setStatusCode(200);
                res.setBody('{"totalSize":1,"done":true,"records":[{"Id":"081000000000001","Name":"SIGTMP_x",' +
                            '"CreatedDate":"2020-01-01T00:00:00.000+0000"}]}');
            }
            return res;
        }
    }

    @isTest
    static void calloutLayer() {
        Test.setMock(HttpCalloutMock.class, new Mock());
        ZZ_SigProbe_Nc.R c = ZZ_SigProbe_Nc.create('SIGTMP_a', 'AAAA');
        System.assertEquals(201, c.code);
        System.assertEquals('081000000000001', c.id);
        System.assertEquals(200, ZZ_SigProbe_Nc.find('SIGTMP_a').code);
        System.assertEquals(200, ZZ_SigProbe_Nc.me().code);
        System.assertEquals(204, ZZ_SigProbe_Nc.del(c.id).code);
        System.assertEquals(1, ZZ_SigProbe_Cleanup.run(0));
        System.assertEquals(0, ZZ_SigProbe_Cleanup.run(600));
    }

    @isTest
    static void signatureCapture() {
        Id id = ZZ_SigProbe_Chain.saveSignature('idem-1', 'APP-1', 'AAAA', 'Tester');
        System.assertNotEquals(null, id);
        ZZ_SigProbe_Sig__c s = [SELECT Id, Status__c, PngBytes__c FROM ZZ_SigProbe_Sig__c WHERE Id = :id];
        System.assertEquals('CAPTURED', s.Status__c);
        System.assertEquals(4, s.PngBytes__c);
    }

    @isTest
    static void controllerBindsParams() {
        Test.setCurrentPage(Page.ZZ_SigProbe_ChainPage);
        ApexPages.currentPage().getParameters().put('sig', 'SIGTMP_x');
        ApexPages.currentPage().getParameters().put('app', 'APP-9');
        ZZ_SigProbe_ChainCtl c = new ZZ_SigProbe_ChainCtl();
        System.assertEquals('SIGTMP_x', c.sigName);
        System.assertEquals('APP-9', c.appRef);
    }
}