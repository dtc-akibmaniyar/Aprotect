@IsTest
private class IdExtractorTest {
    
    @IsTest
    static void testExtractIds() {
        String inputString = 'a05DJ000003lT28ANDa02DJ000007IpCo';
        List<String> inputStrings = new List<String>{inputString};
        
        List<IdExtractor.IdResult> results = IdExtractor.extractIds(inputStrings);
        
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals('a05DJ000003lT28', results[0].claimId, 'Claim ID should be extracted correctly');
        System.assertEquals('a02DJ000007IpCo', results[0].repairShopId, 'Repair Shop ID should be extracted correctly');
    }
    
    @IsTest
    static void testEmptyInput() {
        List<String> inputStrings = new List<String>{''};
        
        List<IdExtractor.IdResult> results = IdExtractor.extractIds(inputStrings);
        
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(null, results[0].claimId, 'Claim ID should be null for empty input');
        System.assertEquals(null, results[0].repairShopId, 'Repair Shop ID should be null for empty input');
    }
    
    @IsTest
    static void testInvalidFormat() {
        List<String> inputStrings = new List<String>{'invalidformat'};
        
        List<IdExtractor.IdResult> results = IdExtractor.extractIds(inputStrings);
        
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(null, results[0].claimId, 'Claim ID should be null for invalid format');
        System.assertEquals(null, results[0].repairShopId, 'Repair Shop ID should be null for invalid format');
    }
    
    @IsTest
    static void testMultipleInputs() {
        List<String> inputStrings = new List<String>{
            'a05DJ000003lT28ANDa02DJ000007IpCo',
            'a05DJ000003lT29ANDa02DJ000007IpCp'
        };
        
        List<IdExtractor.IdResult> results = IdExtractor.extractIds(inputStrings);
        
        System.assertEquals(2, results.size(), 'Should return two results');
        System.assertEquals('a05DJ000003lT28', results[0].claimId, 'First Claim ID should be correct');
        System.assertEquals('a02DJ000007IpCo', results[0].repairShopId, 'First Repair Shop ID should be correct');
        System.assertEquals('a05DJ000003lT29', results[1].claimId, 'Second Claim ID should be correct');
        System.assertEquals('a02DJ000007IpCp', results[1].repairShopId, 'Second Repair Shop ID should be correct');
    }
}