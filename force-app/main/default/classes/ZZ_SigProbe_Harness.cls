public with sharing class ZZ_SigProbe_Harness {
    public class ProbeException extends Exception {}

    static void out(Object o) {
        throw new ProbeException(JSON.serialize(o));
    }

    public static void tWho() {
        out(new Map<String, Object>{
            'user' => UserInfo.getUserName(),
            'profile' => [SELECT Name FROM Profile WHERE Id = :UserInfo.getProfileId()].Name,
            'type' => UserInfo.getUserType(),
            'meHttp' => ZZ_SigProbe_Nc.me().code,
            'me' => ZZ_SigProbe_Nc.me().body
        });
    }

    public static void tCreate(String name, String b64) {
        ZZ_SigProbe_Nc.R r = ZZ_SigProbe_Nc.create(name, b64);
        out(new Map<String, Object>{
            'code' => r.code, 'ms' => r.ms, 'id' => r.id, 'b64len' => b64.length(), 'body' => r.body
        });
    }

    public static void tCreateTwo(String n1, String n2, String b64) {
        Long t0 = System.now().getTime();
        ZZ_SigProbe_Nc.R a = ZZ_SigProbe_Nc.create(n1, b64);
        ZZ_SigProbe_Nc.R b = ZZ_SigProbe_Nc.create(n2, b64);
        out(new Map<String, Object>{
            'a' => new List<Object>{ a.code, a.ms, a.id },
            'b' => new List<Object>{ b.code, b.ms, b.id },
            'totalMs' => System.now().getTime() - t0
        });
    }

    public static void tDelete(String resourceId) {
        ZZ_SigProbe_Nc.R r = ZZ_SigProbe_Nc.del(resourceId);
        out(new Map<String, Object>{ 'code' => r.code, 'ms' => r.ms, 'body' => r.body });
    }

    public static void tFind(String name) {
        ZZ_SigProbe_Nc.R r = ZZ_SigProbe_Nc.find(name);
        out(new Map<String, Object>{ 'code' => r.code, 'ms' => r.ms, 'body' => r.body });
    }

    // DML then callout: expect BLOCKED
    public static void tDmlThenCallout() {
        insert new ZZ_SigProbe_Sig__c(AppRef__c = 'X', IdemKey__c = 'dmlco-' + System.now().getTime());
        Map<String, Object> m = new Map<String, Object>{ 'phase' => 'insert-then-callout' };
        try {
            ZZ_SigProbe_Nc.R r = ZZ_SigProbe_Nc.find('ZZ_SigProbe_SignatureWhite');
            m.put('result', 'ALLOWED');
            m.put('code', r.code);
        } catch (Exception e) {
            m.put('result', 'BLOCKED');
            m.put('error', e.getMessage());
        }
        out(m);
    }

    // callout then DML: expect ALLOWED
    public static void tCalloutThenDml() {
        Map<String, Object> m = new Map<String, Object>();
        ZZ_SigProbe_Nc.R r = ZZ_SigProbe_Nc.find('ZZ_SigProbe_SignatureWhite');
        m.put('calloutCode', r.code);
        try {
            insert new ZZ_SigProbe_Sig__c(AppRef__c = 'X', IdemKey__c = 'codml-' + System.now().getTime());
            m.put('dmlAfterCallout', 'ALLOWED');
        } catch (Exception e) {
            m.put('dmlAfterCallout', 'BLOCKED: ' + e.getMessage());
        }
        out(m);
    }

    // DML then getContentAsPDF: does the renderer count as a callout?
    public static void tDmlThenRender() {
        Map<String, Object> m = new Map<String, Object>();
        insert new ZZ_SigProbe_Sig__c(AppRef__c = 'X', IdemKey__c = 'dmlrender-' + System.now().getTime());
        try {
            Blob b = ZZ_SigProbe_Chain.render('ZZ_SigProbe_SignatureWhite', 'APP', 'DEALER');
            m.put('renderAfterDml', 'ALLOWED');
            m.put('bytes', b.size());
        } catch (Exception e) {
            m.put('renderAfterDml', 'BLOCKED');
            m.put('error', e.getMessage());
        }
        out(m);
    }

    public static void tLoop(Integer n, String prefix, String b64) {
        List<Object> rows = new List<Object>();
        for (Integer i = 0; i < n; i++) {
            String name = prefix + i + '_' + String.valueOf(Crypto.getRandomLong()).left(6).replace('-', '');
            ZZ_SigProbe_Nc.R r = ZZ_SigProbe_Nc.create(name, b64);
            rows.add(new List<Object>{ name, r.code, r.ms });
        }
        out(rows);
    }

    public static void tIssue(Id sigId) {
        out(ZZ_SigProbe_Chain.issue(sigId));
    }

    public static void tDrop(Id sigId) {
        out(new Map<String, Object>{ 'deleteCode' => ZZ_SigProbe_Chain.dropResource(sigId) });
    }

    public static void tCleanup(Integer ageMinutes) {
        out(new Map<String, Object>{ 'deleted' => ZZ_SigProbe_Cleanup.run(ageMinutes) });
    }

    public static void tRenderOnly(String name, Integer times) {
        List<Object> rows = new List<Object>();
        for (Integer i = 0; i < times; i++) {
            Long t0 = System.now().getTime();
            Blob b = ZZ_SigProbe_Chain.render(name, 'APP-1', 'ZZ Dealer');
            rows.add(new List<Object>{ System.now().getTime() - t0, b.size() });
        }
        out(rows);
    }
}