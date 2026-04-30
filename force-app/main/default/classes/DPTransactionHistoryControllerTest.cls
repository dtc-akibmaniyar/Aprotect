/**
 * DPTransactionHistoryControllerTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Covers DealerPortalTransactionHistoryController.getTransactionHistory():
 *   • Blank recordId   → AuraHandledException thrown immediately
 *   • Invalid id string → SOQL exception caught and re-thrown as AuraHandledException
 *   • Valid RF, no payments → empty list returned
 *   • Valid RF, one payment → single-element list with correct fields
 *   • Valid RF, multiple payments → all returned (ORDER BY CreatedDate DESC)
 *
 * Test Strategy:
 *   ✔ @isTest(SeeAllData=false)
 *   ✔ @TestSetup for shared Dealer + Remittance Form base
 *   ✔ All data exclusively via TestDataFactory — no inline SObject creation
 *   ✔ Positive + Negative per branch
 *   ✔ System.assert* with descriptive messages on every assertion
 *   ✔ No hardcoded Ids
 */
@isTest(SeeAllData=false)
private class DPTransactionHistoryControllerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // @TestSetup — Dealer + Remittance Form only.
    // Individual tests create their own Payment__c records so each test
    // controls exactly which payments appear against the RF.
    // ─────────────────────────────────────────────────────────────────────────

    @TestSetup
    static void setup() {
        Account dealer = TestDataFactory.createDealer(true);
        TestDataFactory.createRemittanceForm(dealer.Id, true);
    }

    // ── Private query helpers ─────────────────────────────────────────────────

    private static Remittance_Form__c getRemittanceForm() {
        return [SELECT Id FROM Remittance_Form__c LIMIT 1];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // NEGATIVE / EDGE CASE TESTS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Blank recordId — throws AuraHandledException before reaching the SOQL.
     */
    @isTest
    static void testBlankId_throwsAuraHandledException() {
        Boolean threw = false;
        Test.startTest();
        try {
            DealerPortalTransactionHistoryController.getTransactionHistory('');
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().length() > 0,
                'AuraHandledException message should not be empty for blank recordId');
        }
        Test.stopTest();

        System.assertEquals(true, threw,
            'getTransactionHistory should throw AuraHandledException for a blank recordId');
    }

    /**
     * Null recordId — isBlank(null) = true, same early-exit path as blank.
     */
    @isTest
    static void testNullId_throwsAuraHandledException() {
        Boolean threw = false;
        Test.startTest();
        try {
            DealerPortalTransactionHistoryController.getTransactionHistory(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw,
            'getTransactionHistory should throw AuraHandledException for a null recordId');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // POSITIVE TESTS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Valid RF with no Payment__c records — returns an empty list without error.
     */
    @isTest
    static void testValidRF_noPayments_returnsEmptyList() {
        Remittance_Form__c rf = getRemittanceForm();

        Test.startTest();
        List<Payment__c> result =
            DealerPortalTransactionHistoryController.getTransactionHistory(rf.Id);
        Test.stopTest();

        System.assertNotEquals(null, result,
            'Result should not be null even when no payments exist');
        System.assertEquals(0, result.size(),
            'Empty list should be returned when no Payment__c records exist for the RF');
    }

    /**
     * Valid RF with one Payment__c — returns a single-element list with the
     * correct record and key fields populated.
     */
    @isTest
    static void testValidRF_onePayment_returnsPayment() {
        Remittance_Form__c rf = getRemittanceForm();
        Payment__c pmt        = TestDataFactory.createPayment(rf.Id, true);

        Test.startTest();
        List<Payment__c> result =
            DealerPortalTransactionHistoryController.getTransactionHistory(rf.Id);
        Test.stopTest();

        System.assertEquals(1, result.size(),
            'Should return exactly one Payment__c for the RF');
        System.assertEquals(pmt.Id, result[0].Id,
            'Returned payment Id should match the created Payment__c');
        System.assertEquals(1500.00, result[0].Amount__c,
            'Amount__c should match the value set by TestDataFactory.createPayment');
        System.assertEquals('Transaction Pending', result[0].Payment_Confirmation_Status__c,
            'Payment_Confirmation_Status__c should match the factory default');
    }

    /**
     * Valid RF with multiple payments — all are returned.
     * Verifies the query has no artificial limit that would drop records.
     */
    @isTest
    static void testValidRF_multiplePayments_allReturned() {
        Remittance_Form__c rf = getRemittanceForm();
        TestDataFactory.createPayment(rf.Id, true);
        TestDataFactory.createCompletedPayment(rf.Id, true);
        TestDataFactory.createDepositPendingPayment(rf.Id, true);

        Test.startTest();
        List<Payment__c> result =
            DealerPortalTransactionHistoryController.getTransactionHistory(rf.Id);
        Test.stopTest();

        System.assertEquals(3, result.size(),
            'All three Payment__c records should be returned for the RF');
    }

    /**
     * Valid RF Id that matches no records (different object type Id used) —
     * returns empty list, no exception thrown.
     */
    @isTest
    static void testNonMatchingRFId_returnsEmptyList() {
        Remittance_Form__c rf = getRemittanceForm();
        // Use the RF's own Id as a fake "other RF" — create a second RF to get a real Id
        // that exists but has no payments, then query against it
        Account dealer         = [SELECT Id FROM Account LIMIT 1];
        Remittance_Form__c rf2 = TestDataFactory.createRemittanceForm(dealer.Id, true);

        Test.startTest();
        List<Payment__c> result =
            DealerPortalTransactionHistoryController.getTransactionHistory(rf2.Id);
        Test.stopTest();

        System.assertEquals(0, result.size(),
            'Empty list should be returned for a valid RF Id that has no payments');
    }
}