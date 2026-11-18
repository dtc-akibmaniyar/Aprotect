/**
 * Regression coverage for the dealer portal cancellation submit, run as a REAL
 * PowerPartner user. The existing controller tests inject dealerAccountOverride
 * and therefore never exercise the path a portal user actually takes; that gap
 * is what let a portal-only failure ship while the suite stayed green.
 */
@isTest(SeeAllData=true)
public class CancellationPortalDealerProbeTest {

    private static final String PNG =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

    @isTest
    static void dealerSubmitCreatesRoutedRequestWithSlaAndServiceLine() {
        User dealer = [SELECT Id FROM User WHERE Username = 'qaseem.abbas+2@dtcforce.com' LIMIT 1];
        Id appId = 'a01G100000oIU9UIAW';

        Id requestId;
        Integer selectedCount = 0;
        Boolean routed = false;
        System.runAs(dealer) {
            CancellationFormController.FormContext ctx =
                CancellationFormController.getFormContext(appId);
            List<Id> pkgIds = new List<Id>();
            for (CancellationFormController.PackageLine line : ctx.packages) {
                pkgIds.add(line.packageId);
            }
            selectedCount = pkgIds.size();
            CancellationFormController.SubmitResult res =
                CancellationFormController.submitRequest(
                    appId, pkgIds, 'Customer Request', null, true,
                    ctx.termsVersion, PNG, ctx.repName, ctx.repTitle);
            requestId = res.requestId;
            routed = res.success;
        }

        System.assertNotEquals(null, requestId, 'Portal submit created no cancellation request.');
        App_Cancellation_Request__c saved = [
            SELECT Name, Status__c, SLA_Due_Date__c, Submitted_From_Portal__c
            FROM App_Cancellation_Request__c WHERE Id = :requestId
        ];
        System.assertEquals('Pending Sales Review', saved.Status__c, 'Status was not stamped.');
        System.assertNotEquals(null, saved.SLA_Due_Date__c, 'SLA due date was not set.');
        System.assertEquals(true, saved.Submitted_From_Portal__c, 'Not marked as a portal submission.');
        System.assertEquals(selectedCount, [
            SELECT COUNT() FROM Cancellation_Service__c
            WHERE App_Cancellation_Request__c = :requestId
        ], 'Service lines were not all created.');
        System.assertEquals(true, routed, 'Request was saved but never routed to approval.');
    }

    @isTest
    static void portalUserWithoutDealerContactIsRefusedWithAMessage() {
        User admin = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' AND IsActive = true LIMIT 1];
        String message;
        System.runAs(admin) {
            try {
                CancellationFormController.getFormContext('a01G100000oIU9UIAW');
                message = 'no-exception';
            } catch (Exception e) {
                message = e.getMessage();
            }
        }
        System.assertEquals('Your portal user is not linked to a dealership.', message,
            'A user with no dealer contact must be refused with an explicit message.');
    }
}