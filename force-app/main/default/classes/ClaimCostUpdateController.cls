public without sharing class ClaimCostUpdateController {
    public Decimal estimatedRepairCost { get; set; }
    public Decimal laborCost { get; set; }
    public Decimal shopSupplies { get; set; }
    public Decimal wholesalePrice { get; set; }
    private String claimId;
    
    public ClaimCostUpdateController() {
        claimId = ApexPages.currentPage().getParameters().get('id');
    }
    
    public PageReference submitClaim() {
        try {
            Claim__c newClaim = new Claim__c(
                Id = claimId,
                Estimated_Repair_Cost__c = estimatedRepairCost,
                Labor_Cost__c = laborCost,
                Shop_Supplies__c = shopSupplies,
                Wholesale_Price__c = wholesalePrice
            );
            
            update newClaim;
            
            PageReference redirectPage = new PageReference('https://a-protectwarranty.com/');
            redirectPage.setRedirect(true);
            return redirectPage;
            
        } catch(Exception e) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                'Error submitting claim: ' + e.getMessage()
            ));
            return null;
        }
    }
}