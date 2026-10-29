public with sharing class ZZ_SigProbe_ChainCtl {
    public String sigName { get; set; }
    public String appRef { get; set; }
    public String dealerName { get; set; }
    public String signedOn { get; set; }

    public ZZ_SigProbe_ChainCtl() {
        Map<String, String> p = ApexPages.currentPage() == null
            ? new Map<String, String>()
            : ApexPages.currentPage().getParameters();
        sigName = p.get('sig');
        appRef = p.get('app');
        dealerName = p.get('dealer');
        signedOn = p.get('on');
    }
}