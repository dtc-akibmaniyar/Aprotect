public with sharing class SIGPdfProbe {
    public static String runProbe() {
        String uuid = EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 12);
        String name = 'SIGTMP_' + uuid;
        String b64 = 'iVBORw0KGgoAAAANSUhEUgAAAu4AAAD6CAIAAABxp1U5AAADlElEQVR42u3WMQ0AAAzDsPIn3cKYJtkQciUFAHgrEgAAVgYAwMoAAFgZAMDKAABYGQAAKwMAYGUAACsDAGBlAACsDABgZQAArAwAgJUBALAyAICVAQCwMgAAVgYAwMoAAFYGAMDKAABYGQDAygAAWBkA' +
        'ACsDAGBlAAArAwBgZQAArAwAgJUBAKwMAICVAQCwMgCAlQEAsDIAAFYGAMDKAABWBgDAygAAWBkAwMoAAFgZAAArAwBgZQAAKwMAYGUAAKwMAICVAQCsDACAlQEAsDIAgJUBALAyAABWBgDAygAAVgYAwMoAAFgZAAArAwBYGQAAKwMAYGUAACsDAGBlAACsDACAlQEA' +
        'rAwAgJUBALAyAABWBgCwMgAAVgYAwMoAAFYGAMDKAABYGQAAKwMAWBkAACsDAGBlAAArAwBgZQAArAwAgJUBAKwMAICVAQCwMgAAVgYAsDIAAFYGAMDKAABWBgDAygAAWBkAACsDAFgZAAArAwBgZQAArAwAYGUAAKwMAICVAQCsDACAlQEAsDIAAFYGALAyAABWBgDA' +
        'ygAAWBkAwMoAAFgZAAArAwBYGQAAKwMAYGUAAKwMAGBlAACsDACAlQEArAwAgJUBALAyAABWBgCwMgAAVgYAwMoAAFgZAMDKAABYGQAAKwMAWBkAACsDAGBlAACsDABgZQAArAwAgJUBALAyAICVAQCwMgAAVgYAsDIAAFYGAMDKAABYGQDAygAAWBkAACsDAFgZAAAr' +
        'AwBgZQAArAwAYGUAAKwMAICVAQCwMgCAlQEAsDIAAFYGALAyAABWBgDAygAAWBkAwMoAAFgZAAArAwBgZQAAKwMAYGUAAKwMAGBlAACsDACAlQEAsDIAgJUBALAyAABWBgDAygAAVgYAwMoAAFgZAMDKAABYGQAAKwMAYGUAACsDAGBlAACsDABgZQAArAwAgJUBALAy' +
        'AICVAQCwMgAAVgYAwMoAAFYGAMDKAABYGQDAygAAWBkAACsDAGBlAAArAwBgZQAArAwAgJUBAKwMAICVAQCwMgCAlQEAsDIAAFYGAMDKAABWBgDAygAAWBkAACsDAFgZAAArAwBgZQAAKwMAYGUAAKwMAICVAQCsDACAlQEAsDIAgJUBALAyAABWBgDAygAAVgYAwMoA' +
        'AFgZAAArAwBYGQAAKwMAYGUAACsDAGBlAACsDACAlQEArAwAgJUBALAyAABWBgCwMgAAdwbP5S8As1JnAwAAAABJRU5ErkJggg==';
        String payload = '{"Name":"' + name + '","ContentType":"image/png","CacheControl":"Public","Body":"' + b64 + '"}';
        String base = 'callout:SIG_Portal_PDF_Org/services/data/v67.0/tooling/sobjects/StaticResource';
        Long t1 = System.now().getTime();
        HttpResponse r1 = send('POST', base, payload);
        Long d1 = System.now().getTime() - t1;
        String out = 'CREATE ' + r1.getStatusCode() + ' ' + d1 + 'ms ' + r1.getBody().left(120);
        if (r1.getStatusCode() != 201) return out;
        String id = (String) ((Map<String,Object>) JSON.deserializeUntyped(r1.getBody())).get('id');
        Long t2 = System.now().getTime();
        HttpResponse r2 = send('GET', base + '/' + id, null);
        Long d2 = System.now().getTime() - t2;
        out += ' | READ ' + r2.getStatusCode() + ' ' + d2 + 'ms len=' + r2.getBody().length();
        Long t3 = System.now().getTime();
        HttpResponse r3 = send('DELETE', base + '/' + id, null);
        Long d3 = System.now().getTime() - t3;
        out += ' | DELETE ' + r3.getStatusCode() + ' ' + d3 + 'ms';
        return out + ' | NAME ' + name;
    }

    public static String diag() {
        String out = '';
        HttpResponse a = send('GET', 'callout:SIG_Portal_PDF_Org/services/data/v67.0/', null);
        out += 'VERSIONS ' + a.getStatusCode() + ' len=' + a.getBody().length();
        HttpResponse b = send('GET', 'callout:SIG_Portal_PDF_Org/services/data/v67.0/tooling/sobjects/StaticResource/describe', null);
        out += ' | DESCRIBE ' + b.getStatusCode() + ' ' + b.getBody().left(80);
        HttpResponse c = send('GET', 'callout:SIG_Portal_PDF_Org/services/data/v67.0/sobjects/StaticResource/describe', null);
        out += ' | STD_DESCRIBE ' + c.getStatusCode() + ' ' + c.getBody().left(80);
        return out;
    }

    static HttpResponse send(String m, String url, String body) {
        HttpRequest r = new HttpRequest();
        r.setEndpoint(url);
        r.setMethod(m);
        r.setHeader('Content-Type', 'application/json');
        if (body != null) r.setBody(body);
        r.setTimeout(120000);
        return new Http().send(r);
    }
}