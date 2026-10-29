public with sharing class ZZ_SigProbe_Nc {
    public class R {
        public Integer code;
        public String body;
        public Long ms;
        public String id;
    }

    static final String BASE = 'callout:ZZ_SigProbe_Self';

    static HttpRequest req(String path, String method) {
        HttpRequest r = new HttpRequest();
        r.setEndpoint(BASE + path);
        r.setMethod(method);
        r.setHeader('Content-Type', 'application/json');
        r.setTimeout(120000);
        return r;
    }

    static R send(HttpRequest r) {
        R out = new R();
        Long t0 = System.now().getTime();
        HttpResponse res = new Http().send(r);
        out.ms = System.now().getTime() - t0;
        out.code = res.getStatusCode();
        out.body = res.getBody();
        if (out.body != null && out.body.length() > 700) {
            out.body = out.body.substring(0, 700);
        }
        return out;
    }

    public static R create(String name, String b64) {
        HttpRequest r = req('/services/data/v67.0/tooling/sobjects/StaticResource', 'POST');
        r.setBody(JSON.serialize(new Map<String, Object>{
            'Name' => name,
            'ContentType' => 'image/png',
            'CacheControl' => 'Public',
            'Body' => b64
        }));
        R out = send(r);
        if (out.code == 201 && out.body != null) {
            Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(out.body);
            out.id = (String) m.get('id');
        }
        return out;
    }

    public static R del(String resourceId) {
        return send(req('/services/data/v67.0/tooling/sobjects/StaticResource/' + resourceId, 'DELETE'));
    }

    public static R find(String name) {
        return findBySoql('SELECT Id, Name FROM StaticResource WHERE Name = \'' +
            String.escapeSingleQuotes(name) + '\'');
    }

    public static R findBySoql(String soql) {
        return send(req('/services/data/v67.0/tooling/query?q=' + EncodingUtil.urlEncode(soql, 'UTF-8'), 'GET'));
    }

    public static R me() {
        return send(req('/services/data/v67.0/chatter/users/me', 'GET'));
    }
}