trigger ContentDocumentLinkTrigger on ContentDocumentLink (before insert) {
    Set<Id> accountIds = new Set<Id>();

    // Collect Account Ids where file is being uploaded
    for (ContentDocumentLink cdl : Trigger.new) {
        if (cdl.LinkedEntityId != null && cdl.LinkedEntityId.getSObjectType() == Account.sObjectType) {
            accountIds.add(cdl.LinkedEntityId);
        }
    }

    if (accountIds.isEmpty()) return;

    // Get Partner Users related to those Accounts
    List<User> partnerUsers = [
        SELECT Id, Contact.AccountId
        FROM User
        WHERE UserType = 'Partner Community Login User Custom'
        AND Contact.AccountId IN :accountIds
    ];

    Set<Id> partnerAccountIds = new Set<Id>();
    for (User u : partnerUsers) {
        partnerAccountIds.add(u.Contact.AccountId);
    }

    // Enforce sharing visibility before insert
    for (ContentDocumentLink cdl : Trigger.new) {
        if (partnerAccountIds.contains(cdl.LinkedEntityId)) {
            // Ensure file is visible to all partner users of that account
            cdl.ShareType = 'V';       // Viewer access
            cdl.Visibility = 'AllUsers'; // Make visible across the community
        }
    }
}