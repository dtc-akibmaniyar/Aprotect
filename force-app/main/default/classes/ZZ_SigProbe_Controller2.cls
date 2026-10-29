public class ZZ_SigProbe_Controller2 {
    // TEMP PROBE ARTIFACT - delete after signature feasibility probe
    public String dataUriWhite { get; private set; }
    public String cvId { get; private set; }
    public String instanceUrl { get; private set; }
    public List<PItem> payloads { get; private set; }

    public class PItem {
        public String label { get; set; }
        public String uri { get; set; }
    }

    public ZZ_SigProbe_Controller2() {
        payloads = new List<PItem>();
        Blob w = null;
        for (StaticResource r : [
            SELECT Name, Body FROM StaticResource
            WHERE Name IN ('ZZ_SigProbe_SignatureWhite', 'ZZ_SigProbe_Signature')
        ]) {
            if (r.Name == 'ZZ_SigProbe_SignatureWhite') w = r.Body;
        }
        if (w != null) {
            dataUriWhite = 'data:image/png;base64,' + EncodingUtil.base64Encode(w);
        }
        Map<String, String> p = ApexPages.currentPage().getParameters();
        cvId = p.get('cvId');
        instanceUrl = URL.getOrgDomainUrl().toExternalForm();

        String pads = p.get('pads');
        if (String.isNotBlank(pads) && w != null) {
            for (String s : pads.split(',')) {
                Integer n = Integer.valueOf(s.trim());
                Blob padded = appendZeroBytes(w, n);
                String b64 = EncodingUtil.base64Encode(padded);
                PItem it = new PItem();
                it.label = 'pad ' + n + ' bytes -> blob ' + padded.size()
                         + ' B, base64 ' + b64.length() + ' chars';
                it.uri = 'data:image/png;base64,' + b64;
                payloads.add(it);
            }
        }
    }

    private static Blob appendZeroBytes(Blob src, Integer n) {
        List<String> parts = new List<String>();
        parts.add(EncodingUtil.convertToHex(src));
        String block = '00'.repeat(4000);
        Integer remaining = n;
        while (remaining > 0) {
            Integer take = Math.min(remaining, 4000);
            parts.add(block.substring(0, take * 2));
            remaining -= take;
        }
        return EncodingUtil.convertFromHex(String.join(parts, ''));
    }
}