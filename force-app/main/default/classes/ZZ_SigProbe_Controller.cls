public class ZZ_SigProbe_Controller {
    // TEMP PROBE ARTIFACT - delete after signature feasibility probe
    public String dataUriTransparent { get; private set; }
    public String dataUriWhite { get; private set; }
    public String payloadUri { get; private set; }
    public String payloadInfo { get; private set; }
    public String fileId { get; private set; }
    public String instanceUrl { get; private set; }
    public String b64Len { get; private set; }

    public ZZ_SigProbe_Controller() {
        Map<String, Blob> bodies = new Map<String, Blob>();
        for (StaticResource r : [
            SELECT Name, Body FROM StaticResource
            WHERE Name IN ('ZZ_SigProbe_Signature', 'ZZ_SigProbe_SignatureWhite')
        ]) {
            bodies.put(r.Name, r.Body);
        }
        Blob t = bodies.get('ZZ_SigProbe_Signature');
        Blob w = bodies.get('ZZ_SigProbe_SignatureWhite');
        if (t != null) {
            String b = EncodingUtil.base64Encode(t);
            dataUriTransparent = 'data:image/png;base64,' + b;
            b64Len = String.valueOf(b.length());
        }
        if (w != null) {
            dataUriWhite = 'data:image/png;base64,' + EncodingUtil.base64Encode(w);
        }

        Map<String, String> p = ApexPages.currentPage().getParameters();
        fileId = p.get('fileId');
        instanceUrl = URL.getOrgDomainUrl().toExternalForm();

        String padStr = p.get('pad');
        if (String.isNotBlank(padStr) && t != null) {
            Integer pad = Integer.valueOf(padStr);
            Blob padded = appendZeroBytes(t, pad);
            String b = EncodingUtil.base64Encode(padded);
            payloadUri = 'data:image/png;base64,' + b;
            payloadInfo = 'padded ' + pad + ' bytes -> blob ' + padded.size()
                        + ' B, base64 ' + b.length() + ' chars';
        }
    }

    // appends N zero bytes to the end of a blob (after the PNG IEND chunk)
    private static Blob appendZeroBytes(Blob src, Integer n) {
        List<String> parts = new List<String>();
        parts.add(EncodingUtil.convertToHex(src));
        String block = '00'.repeat(4000); // 8,000 hex chars = 4,000 zero bytes
        Integer remaining = n;
        while (remaining > 0) {
            Integer take = Math.min(remaining, 4000);
            parts.add(block.substring(0, take * 2));
            remaining -= take;
        }
        return EncodingUtil.convertFromHex(String.join(parts, ''));
    }
}