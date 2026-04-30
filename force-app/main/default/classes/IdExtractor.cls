public class IdExtractor {
    
    @InvocableMethod(label='Extract Claim and Repair Shop IDs' description='Extracts Claim ID and Repair Shop ID from a combined string')
    public static List<IdResult> extractIds(List<String> inputStrings) {
        List<IdResult> results = new List<IdResult>();
        
        for (String inputString : inputStrings) {
            IdResult result = new IdResult();
            
            if (String.isNotBlank(inputString)) {
                // Split by 'AND' to get the two parts
                List<String> parts = inputString.split('AND');
                
                if (parts.size() >= 2) {
                    // First part is the claim ID
                    result.claimId = parts[0];
                    
                    // Second part is the repair shop ID
                    result.repairShopId = parts[1];
                }
            }
            
            results.add(result);
        }
        
        return results;
    }
    
    public class IdResult {
        @InvocableVariable(label='Claim ID' description='The extracted Claim ID')
        public String claimId;
        
        @InvocableVariable(label='Repair Shop ID' description='The extracted Repair Shop ID')
        public String repairShopId;
    }
}