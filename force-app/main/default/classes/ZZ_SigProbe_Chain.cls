public with sharing class ZZ_SigProbe_Chain {
    public static final String PREFIX = 'SIGTMP_';

    static String newName() {
        return PREFIX + String.valueOf(Crypto.getRandomLong()).replace('-', '').left(12);
    }

    // ---- T1: signature capture (pure DML, commits on its own) ----
    public static Id saveSignature(String idemKey, String appRef, String b64, String signedBy) {
        ZZ_SigProbe_Sig__c s = new ZZ_SigProbe_Sig__c(
            AppRef__c = appRef,
            PngB64__c = b64,
            PngBytes__c = (b64 == null ? 0 : b64.length()),
            SignedBy__c = signedBy,
            SignedAt__c = System.now(),
            Status__c = 'CAPTURED',
            IdemKey__c = idemKey
        );
        insert s;
        return s.Id;
    }

    // ---- render the probe contract page ----
    public static Blob render(String resourceName, String appRef, String dealer) {
        PageReference pr = Page.ZZ_SigProbe_ChainPage;
        pr.getParameters().put('sig', resourceName);
        pr.getParameters().put('app', appRef);
        pr.getParameters().put('dealer', dealer);
        pr.getParameters().put('on', String.valueOf(System.now()));
        return pr.getContentAsPDF();
    }

    // ---- T2: callout create -> render -> DML. Callout FIRST, no DML before it. ----
    public static Map<String, Object> issue(Id sigId) {
        Map<String, Object> out = new Map<String, Object>();
        Long t0 = System.now().getTime();
        ZZ_SigProbe_Sig__c s = [SELECT Id, PngB64__c, AppRef__c, SignedBy__c
                                FROM ZZ_SigProbe_Sig__c WHERE Id = :sigId];
        String name = newName();
        ZZ_SigProbe_Nc.R cr = ZZ_SigProbe_Nc.create(name, s.PngB64__c);
        out.put('createCode', cr.code);
        out.put('createMs', cr.ms);
        if (cr.code != 201) {
            out.put('createBody', cr.body);
            out.put('totalMs', System.now().getTime() - t0);
            out.put('ok', false);
            return out;
        }
        Long t1 = System.now().getTime();
        Blob pdf;
        try {
            pdf = render(name, s.AppRef__c, s.SignedBy__c);
        } catch (Exception e) {
            out.put('renderError', e.getMessage());
        }
        out.put('renderMs', System.now().getTime() - t1);

        s.ResourceName__c = name;
        s.ResourceId__c = cr.id;
        if (pdf == null) {
            s.Status__c = 'RENDER_FAILED';
            update s;
            out.put('pdfBytes', 0);
            out.put('totalMs', System.now().getTime() - t0);
            out.put('ok', false);
            return out;
        }
        s.Status__c = 'RENDERED';
        update s;
        ContentVersion cv = new ContentVersion(
            Title = 'ZZ_SigProbe_Rendered',
            PathOnClient = 'ZZ_SigProbe_Rendered_' + name + '.pdf',
            VersionData = pdf,
            FirstPublishLocationId = sigId
        );
        insert cv;
        out.put('pdfBytes', pdf.size());
        out.put('contentVersionId', cv.Id);
        out.put('resourceName', name);
        out.put('resourceId', cr.id);
        out.put('totalMs', System.now().getTime() - t0);
        out.put('ok', true);
        return out;
    }

    // ---- T3: delete the resource (callout), then clear the pointer (DML) ----
    public static Integer dropResource(Id sigId) {
        ZZ_SigProbe_Sig__c s = [SELECT Id, ResourceId__c FROM ZZ_SigProbe_Sig__c WHERE Id = :sigId];
        if (s.ResourceId__c == null) {
            return 0;
        }
        ZZ_SigProbe_Nc.R r = ZZ_SigProbe_Nc.del(s.ResourceId__c);
        if (r.code == 204 || r.code == 200 || r.code == 404) {
            s.ResourceId__c = null;
            s.Status__c = 'DONE';
            update s;
        }
        return r.code;
    }

    // ---- orphan check for one signature row ----
    public static Integer dropByName(String resourceName) {
        ZZ_SigProbe_Nc.R f = ZZ_SigProbe_Nc.find(resourceName);
        if (f.code != 200) {
            return -1;
        }
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(f.body);
        List<Object> recs = (List<Object>) body.get('records');
        if (recs.isEmpty()) {
            return -2;
        }
        ZZ_SigProbe_Nc.R d = ZZ_SigProbe_Nc.del((String) ((Map<String, Object>) recs[0]).get('Id'));
        return d.code;
    }
}