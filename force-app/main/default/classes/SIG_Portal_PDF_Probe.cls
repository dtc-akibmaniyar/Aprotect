public class SIG_Portal_PDF_Probe {
    public static String mint(String key, String sec) {
        HttpRequest r = new HttpRequest();
        r.setEndpoint('https://business-platform-7607--dtcsandbox.sandbox.my.salesforce.com/services/oauth2/token');
        r.setMethod('POST');
        r.setHeader('Content-Type','application/x-www-form-urlencoded');
        r.setBody('grant_type=client_credentials&client_id=' + EncodingUtil.urlEncode(key,'UTF-8') + '&client_secret=' + EncodingUtil.urlEncode(sec,'UTF-8'));
        r.setTimeout(20000);
        try {
            HttpResponse res = new Http().send(r);
            String b = res.getBody();
            if (res.getStatusCode() == 200) { return 'OK 200 len=' + b.length() + ' hasToken=' + b.contains('access_token'); }
            return 'HTTP ' + res.getStatusCode() + ' :: ' + b.left(300);
        } catch (Exception e) {
            return 'EX ' + e.getTypeName() + ' :: ' + e.getMessage();
        }
    }
}