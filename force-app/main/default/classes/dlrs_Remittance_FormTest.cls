/**
 * Auto Generated and Deployed by the Declarative Lookup Rollup Summaries Tool package (dlrs)
 **/
@IsTest
private class dlrs_Remittance_FormTest
{
    @IsTest
    private static void testTrigger()
    {
        // Force the dlrs_Remittance_FormTrigger to be invoked, fails the test if org config or other Apex code prevents this.
        dlrs.RollupService.testHandler(new Remittance_Form__c());
    }
}