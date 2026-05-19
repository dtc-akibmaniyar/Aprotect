public without sharing class DealerPortalMonerisIntegrationServices {
    /**
     * Moneris integration service for Dealer Portal.
     * Ensures every Moneris attempt is recorded in Payment__c regardless of success or failure.
     * Sensitive card data is never persisted; payloads are sanitized.
     *
     * Payment Flow (Architecture):
     * ─────────────────────────────────────────────────────────────────────────────
     * 1. Remittance Form is created (Dealer or Allocation type).
     * 2. Junction records (Remittance_Line_Item_Junction__c) are created at that time
     *    with Payment_Status__c = 'Planned' and Payment__c = null.
     * 3. Dealer/Backend makes a payment via one of the four payment methods below.
     * 4. A Payment__c record is inserted (card, cheque, e-transfer, or dealer credit).
     *    - Flow: Update_Remittance_Line_Item_Junction (on Payment__c Create)
     *      → sets Junction.Payment__c = this Payment Id (links the junction records)
     *      → for Card/Dealer Credit payments with status SUCCEEDED, also sets
     *        Payment_Confirmation_Status__c = 'Transaction Completed'.
     * 5a. Card/Dealer Credit (immediate): The status is set to 'Transaction Completed'
     *     by the Create flow above → triggers Makr_Remittance_Line_Items_Junction_Records_Paid
     *     flow → calls PaymentStatusInvocable → marks junctions, invoice line items,
     *     invoices, applications, and application packages as Paid.
     * 5b. Cheque/ETransfer (deferred): Payment stays 'Deposit Pending'. When a finance
     *     user confirms the deposit and sets Payment_Confirmation_Status__c =
     *     'Deposit Completed', Makr_Remittance_Line_Items_Junction_Records_Paid fires
     *     → calls PaymentStatusInvocable → marks everything as Paid.
     * ─────────────────────────────────────────────────────────────────────────────
     */

    // Class-level Moneris configuration
    private static final Moneris_API_Config__mdt monerisConfig = Moneris_API_Config__mdt.getInstance('Moneris_SB');

    // ─────────────────────────────────────────────────────────────────────────────
    // Helpers: Sanitization and Logging
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Masks a card number showing only first 4 and last 4 digits.
     * Used before persisting any card reference to Payment__c.
     */
    private static String maskCardNumber(String cardNumber) {
        if (String.isBlank(cardNumber) || cardNumber.length() < 8) {
            return null;
        }
        String first4 = cardNumber.substring(0, 4);
        String last4 = cardNumber.substring(cardNumber.length() - 4, cardNumber.length());
        Integer maskLen = cardNumber.length() - 8;
        String mask = '';
        for (Integer i = 0; i < maskLen; i++) {
            mask += '*';
        }
        return first4 + mask + last4;
    }

    /**
     * Sanitizes the raw JSON request body before storing it in the Payment__c log.
     * Masks the card number and removes the CVV entirely so sensitive data is never persisted.
     */
    private static String sanitizeRequest(String json) {
        if (String.isBlank(json)) return null;
        try {
            // Use System.JSON explicitly to avoid any naming collisions
            Map<String, Object> m = (Map<String, Object>) System.JSON.deserializeUntyped(json);
            if (m != null && m.containsKey('paymentMethod')) {
                Map<String, Object> pm = (Map<String, Object>) m.get('paymentMethod');
                if (pm != null && pm.containsKey('card')) {
                    Map<String, Object> card = (Map<String, Object>) pm.get('card');
                    if (card != null) {
                        Object pan = card.get('cardNumber');
                        if (pan != null) {
                            String s = String.valueOf(pan);
                            if (!String.isBlank(s)) {
                                Integer maskLen = (s.length() > 4) ? s.length() - 4 : 4;
                                String mask = '';
                                for (Integer i = 0; i < maskLen; i++) { mask += '*'; }
                                String last4 = (s.length() >= 4) ? s.substring(s.length() - 4, s.length()) : s;
                                String masked = mask + last4;
                                card.put('cardNumber', masked);
                            } else {
                                card.put('cardNumber', '****');
                            }
                        }
                        // Never store CVV
                        if (card.containsKey('cardSecurityCode')) {
                            card.remove('cardSecurityCode');
                        }
                    }
                }
            }
            return System.JSON.serialize(m);
        } catch (Exception e) {
            return '[REDACTED]';
        }
    }

    /**
     * Creates a Payment__c record to log every Moneris attempt (success or failure).
     * Returns the Id of the inserted record so it can be linked to junction records.
     *
     * NOTE: For SUCCEEDED card payments, Payment_Confirmation_Status__c is intentionally
     * left null here. The Update_Remittance_Line_Item_Junction flow (on Payment__c Create)
     * first links the junction records and then sets 'Transaction Completed', ensuring the
     * downstream Makr_Remittance_Line_Items_Junction_Records_Paid flow fires only after
     * the Payment__c → Junction relationship is already established.
     */
    private static String logMonerisHistory(
        String status,
        String recordId,
        String requestJson,
        HttpResponse res,
        PaymentResponse parsed,
        String errorMsg,
        String paymentMethodType,
        String maskedCardNumber,
        String cardHolderName
    ) {
        // Return-early pattern: do not throw from logger to avoid masking the real error
        Payment__c h = new Payment__c();
        try {
            h.Payment_Status__c = status;
            h.Payment_Initiated_Date__c = DateTime.now();
            if (!String.isBlank(recordId))       h.Remittance_Form__c  = recordId;
            if (!String.isBlank(requestJson))    h.Payload__c          = sanitizeRequest(requestJson);
            if (!String.isBlank(maskedCardNumber)) h.Card_Number__c    = maskedCardNumber;
            if (!String.isBlank(cardHolderName)) h.Card_Holder_Name__c = cardHolderName;

            if (res != null) {
                h.Status_Code__c = String.valueOf(res.getStatusCode());
                h.Response__c    = res.getBody();
            } else if (!String.isBlank(errorMsg)) {
                h.Response__c = errorMsg;
            }

            if (parsed != null) {
                h.Order_ID__c = parsed.orderId;
                if (parsed.amount != null) {
                    h.Amount__c = parsed.amount.amount / 100; // convert cents back to dollars
                }
                if (!String.isBlank(parsed.transactionDateTime)) {
                    h.Date_Time__c = DateTime.valueOfGmt(parsed.transactionDateTime.replace('Z', '').replace('T', ' '));
                }
                if (parsed.transactionDetails != null) {
                    h.Transaction_Reference__c = parsed.transactionDetails.transactionUniqueId;
                }
                if (parsed.paymentMethod != null && parsed.paymentMethod.paymentMethodInformation != null
                    && parsed.paymentMethod.paymentMethodInformation.cardInformation != null) {
                    h.Card_Type__c = parsed.paymentMethod.paymentMethodInformation.cardInformation.cardBrand;
                }
            }

            // Set RecordType based on payment method
            if (paymentMethodType == 'Card') {
                h.RecordTypeId = Schema.SObjectType.Payment__c.getRecordTypeInfosByDeveloperName().get('Card_Payment').getRecordTypeId();
            }

            // Mark non-succeeded attempts immediately so the flow can identify failures
            if (!status.equalsIgnoreCase('SUCCEEDED')) {
                h.Payment_Confirmation_Status__c = 'Failed Payment';
            }
            // SUCCEEDED card payments: Payment_Confirmation_Status__c remains null here.
            // The Update_Remittance_Line_Item_Junction flow sets it to 'Transaction Completed'
            // after linking junction records, ensuring the paid cascade fires in the right order.

            insert(h);
            return h.Id;
        } catch (Exception ex) {
            // Swallow logging exceptions — never let logging break the payment flow
            System.debug('ERROR in logMonerisHistory: ' + ex.getMessage());
            return null;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Moneris Access Token
    // ─────────────────────────────────────────────────────────────────────────────

    public static String getAccessToken() {
        // Get Moneris credentials from class-level configuration
        if (monerisConfig == null) {
            logMonerisHistory('FAILED', null, null, null, null, 'Moneris_SB configuration not found', null, null, null);
            return null;
        }

        String clientId     = monerisConfig.Client_Id__c;
        String clientSecret = monerisConfig.Client_Secret__c;

        if (String.isEmpty(clientId) || String.isEmpty(clientSecret)) {
            logMonerisHistory('FAILED', null, null, null, null, 'Client ID or Client Secret not configured', null, null, null);
            return null;
        }

        // Prepare the body of the POST request
        String body = 'grant_type=client_credentials&client_id=' +
                      EncodingUtil.urlEncode(clientId, 'UTF-8') +
                      '&client_secret=' +
                      EncodingUtil.urlEncode(clientSecret, 'UTF-8');

        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Moneris_Access_Token_Named_Credentials/oauth2/token');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setBody(body);

        try {
            HttpResponse res = http.send(req);

            if (res.getStatusCode() != 200 && res.getStatusCode() != 201) {
                logMonerisHistory('FAILED', null, null, res, null, 'Failed to get access token', null, null, null);
                return null;
            }

            Map<String, Object> responseMap = (Map<String, Object>) System.JSON.deserializeUntyped(res.getBody());
            String accessToken = (String) responseMap.get('access_token');

            if (accessToken == null) {
                logMonerisHistory('FAILED', null, null, res, null, 'Access token not found in response', null, null, null);
                return null;
            }

            return accessToken;
        } catch (Exception e) {
            // Network / Named Credential errors
            logMonerisHistory('FAILED', null, null, null, null, 'Access token error: ' + e.getMessage(), null, null, null);
            return null;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Payment Method 1: Credit Card (via Moneris API)
    // Immediate confirmation — junction records are marked Paid in the same transaction.
    // ─────────────────────────────────────────────────────────────────────────────

    @AuraEnabled
    public static PaymentResponse processPayment(
        String  recordId,
        String  cardNumber,
        Integer expiryMonth,
        Integer expiryYear,
        String  cvv,
        Decimal paymentAmount,
        String  cardHolderName
    ) {
        // ── Input validation ──────────────────────────────────────────────────────
        if (recordId == null) {
            String msg = 'Record ID is required to process payment';
            logMonerisHistory('FAILED', null, null, null, null, msg, 'Card', null, null);
            PaymentResponse pr = new PaymentResponse();
            pr.success = false;
            pr.paymentStatus = 'FAILED';
            pr.errorMessage = msg;
            return pr;
        }

        if (String.isEmpty(cardNumber) || expiryMonth == null || expiryYear == null || String.isEmpty(cvv)) {
            String msg = 'All card details are required to process payment';
            String maskedCardNumber = maskCardNumber(cardNumber);
            logMonerisHistory('FAILED', recordId, null, null, null, msg, 'Card', maskedCardNumber, null);
            PaymentResponse pr = new PaymentResponse();
            pr.success = false;
            pr.paymentStatus = 'FAILED';
            pr.errorMessage = msg;
            return pr;
        }

        if (paymentAmount == null || paymentAmount <= 0) {
            String msg = 'Valid payment amount is required';
            logMonerisHistory('FAILED', recordId, null, null, null, msg, 'Card', null, null);
            PaymentResponse pr = new PaymentResponse();
            pr.success = false;
            pr.paymentStatus = 'FAILED';
            pr.errorMessage = msg;
            return pr;
        }

        Remittance_Form__c remittanceForm = [
            SELECT Id, Amount__c
            FROM Remittance_Form__c
            WHERE Id = :recordId
            LIMIT 1
        ];
        if (remittanceForm.Amount__c == null) {
            String msg = 'Amount is missing';
            logMonerisHistory('FAILED', recordId, null, null, null, msg, 'Card', null, null);
            PaymentResponse pr = new PaymentResponse();
            pr.success = false;
            pr.paymentStatus = 'FAILED';
            pr.errorMessage = msg;
            return pr;
        }

        String formattedRecordId = String.valueOf(recordId).substring(0, 15);
        String maskedCardNumber  = maskCardNumber(cardNumber);

        // Access token (log failures inside getAccessToken)
        String accessToken = getAccessToken();
        if (String.isBlank(accessToken)) {
            // Already logged in getAccessToken
            String msg = 'Failed to obtain access token';
            logMonerisHistory('FAILED', recordId, null, null, null, msg, 'Card', maskedCardNumber, null);
            PaymentResponse pr = new PaymentResponse();
            pr.success = false;
            pr.paymentStatus = 'FAILED';
            pr.errorMessage = msg;
            return pr;
        }

        // ── Build Moneris request DTOs ────────────────────────────────────────────

        // Create Amount DTO — Convert amount from dollars to cents for Moneris API
        Amount amountObj = new Amount();
        system.debug('Payment Amount: ' + paymentAmount);
        amountObj.amount = paymentAmount * 100;
        system.debug('Amount in cents: ' + amountObj.amount);
        amountObj.currencyCode = 'CAD';

        // Create Card DTO
        Card card = new Card();
        card.cardNumber      = cardNumber;
        card.expiryMonth     = expiryMonth;
        card.expiryYear      = expiryYear;
        card.cardSecurityCode = cvv;

        // Create PaymentMethod DTO
        PaymentMethod paymentMethod = new PaymentMethod();
        paymentMethod.paymentMethodSource = 'CARD';
        paymentMethod.card                = card;
        paymentMethod.storePaymentMethod  = 'DO_NOT_STORE';

        // Use formatted record ID for invoice number / merchant reference
        String invoiceNumber = formattedRecordId;

        // Create PaymentRequest DTO
        PaymentRequest request = new PaymentRequest();
        request.idempotencyKey      = UUID.randomUUID().toString();
        request.invoiceNumber       = invoiceNumber;
        request.amount              = amountObj;
        request.paymentMethod       = paymentMethod;
        request.automaticCapture    = true;
        request.ecommerceIndicator  = 'AUTHENTICATED_ECOMMERCE';

        // Serialize request to JSON
        String requestBody = JSON.serialize(request);
        // Replace currencyCode with currency in the JSON string to match API specification
        requestBody = requestBody.replace('"currencyCode"', '"currency"');

        // ── Call Moneris API ──────────────────────────────────────────────────────

        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Moneris_Access_Token_Named_Credentials/payments');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + accessToken);
        req.setHeader('Api-Version', monerisConfig.Api_Version__c);
        req.setHeader('X-Merchant-Id', monerisConfig.Merchant_Id__c);
        req.setBody(requestBody);
        req.setTimeout(60000);

        HttpResponse res;
        PaymentResponse response;
        String errorMessage   = '';
        String paymentRecordId = null;

        try {
            res = http.send(req);
            System.debug('Moneris Response: ' + res.getBody());

            if (res.getStatusCode() != 200 && res.getStatusCode() != 201) {
                // Try to extract a human-readable error detail from Moneris response
                try {
                    Map<String, Object> errorResponse = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                    String errorDetail = (String) errorResponse.get('detail');
                    if (String.isNotBlank(errorDetail)) {
                        errorMessage = errorDetail;
                    }
                } catch (Exception e) {
                    // ignore parse error
                }
                // Log failed attempt
                logMonerisHistory('FAILED', recordId, requestBody, res, null, errorMessage, 'Card', maskedCardNumber, cardHolderName);
                PaymentResponse pr = new PaymentResponse();
                pr.success      = false;
                pr.paymentStatus = 'FAILED';
                pr.errorMessage  = String.isNotBlank(errorMessage) ? errorMessage : 'Failed to process payment';
                return pr;
            }

            // Parse the JSON response
            response = (PaymentResponse) JSON.deserialize(res.getBody(), PaymentResponse.class);

            // Log success (or API-reported non-succeeded status)
            String statusToLog = (response != null && !String.isBlank(response.paymentStatus)) ? response.paymentStatus : 'UNKNOWN';
            paymentRecordId = logMonerisHistory(statusToLog, recordId, requestBody, res, response, null, 'Card', maskedCardNumber, cardHolderName);

            // ── Business updates on SUCCEEDED ─────────────────────────────────────
            if (response != null && response.paymentStatus != null && response.paymentStatus.equalsIgnoreCase('SUCCEEDED')) {
                response.success = true;
                // Junction linking and status cascade are handled automatically by flows:
                // 1. Update_Remittance_Line_Item_Junction (on Payment__c Create):
                //    Sets Junction.Payment__c = this Payment Id, then sets
                //    Payment_Confirmation_Status__c = 'Transaction Completed'.
                // 2. Makr_Remittance_Line_Items_Junction_Records_Paid (on Payment__c Update):
                //    Detects the status change and calls PaymentStatusInvocable to mark
                //    junctions, invoice line items, and invoices as Paid.
            } else {
                if (response == null) {
                    // Already logged as UNKNOWN; ensure outward response has the failure flag
                    response = new PaymentResponse();
                }
                response.success = false;
            }

            return response;

        } catch (Exception ex) {
            // Log exceptions not covered above (e.g., callout failure, JSON parse issues)
            if (res == null) {
                logMonerisHistory('FAILED', recordId, requestBody, null, null, 'Payment call error: ' + ex.getMessage(), 'Card', maskedCardNumber, cardHolderName);
            }
            PaymentResponse pr = new PaymentResponse();
            pr.success      = false;
            pr.paymentStatus = 'FAILED';
            pr.errorMessage  = ex != null ? ex.getMessage() : 'Unexpected error';
            return pr;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Payment Method 2: Cheque
    // Deferred confirmation — junction records are linked now but marked Paid only
    // when a finance user sets Payment_Confirmation_Status__c = 'Deposit Completed'.
    // ─────────────────────────────────────────────────────────────────────────────

    @AuraEnabled
    public static ChequePaymentResponse processChequePayment(
        String  recordId,
        String  chequeDate,
        String  chequeDeliveryMethod,
        String  chequeNumber,
        Decimal chequeAmount,
        String  notes
    ) {
        ChequePaymentResponse response = new ChequePaymentResponse();

        // ── Input validation ──────────────────────────────────────────────────────
        if (String.isBlank(recordId)) {
            response.success      = false;
            response.errorMessage = 'Record ID is required';
            return response;
        }

        if (String.isBlank(chequeNumber) || String.isBlank(chequeDate) ||
            String.isBlank(chequeDeliveryMethod) || chequeAmount == null || chequeAmount <= 0) {
            response.success      = false;
            response.errorMessage = 'All required cheque details must be provided';
            return response;
        }

        try {
            // Create cheque payment transaction record
            Payment__c chequeRecord = new Payment__c();
            chequeRecord.Remittance_Form__c         = recordId;
            chequeRecord.Payment_Initiated_Date__c  = DateTime.now();
            chequeRecord.Cheque_Number__c           = chequeNumber;
            chequeRecord.Cheque_Date__c             = Date.valueOf(chequeDate);
            chequeRecord.Cheque_Delivery_Mthod__c   = chequeDeliveryMethod;
            chequeRecord.Amount__c                  = chequeAmount;
            chequeRecord.Payment_Confirmation_Status__c = 'Deposit Pending'; // awaiting physical deposit
            chequeRecord.Notes__c                   = String.isBlank(notes) ? '' : notes;

            // Set RecordType to Cheque_Payment
            chequeRecord.RecordTypeId = Schema.SObjectType.Payment__c
                .getRecordTypeInfosByDeveloperName().get('Cheque_Payment').getRecordTypeId();

            insert chequeRecord;
            // Junction linking is handled automatically by Update_Remittance_Line_Item_Junction
            // flow (triggers on Payment__c Create). When finance later sets
            // Payment_Confirmation_Status__c = 'Deposit Completed', the
            // Makr_Remittance_Line_Items_Junction_Records_Paid flow calls PaymentStatusInvocable
            // to mark junctions, invoice line items, and invoices as Paid.

            response.success       = true;
            response.transactionId = chequeRecord.Id;
            response.message       = 'Cheque payment details saved successfully';

        } catch (Exception e) {
            response.success      = false;
            response.errorMessage = e.getMessage();
            // Log the failure even for cheque payments
            logMonerisHistory('FAILED', recordId, null, null, null, 'Cheque payment error: ' + e.getMessage(), null, null, null);
        }

        return response;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Payment Method 3: E-Transfer
    // Deferred confirmation — junction records are linked now but marked Paid only
    // when a finance user sets Payment_Confirmation_Status__c = 'Deposit Completed'.
    // ─────────────────────────────────────────────────────────────────────────────

    @AuraEnabled
    public static ETransferPaymentResponse processETransferPayment(
        String  recordId,
        String  transactionReferenceNumber,
        String  transactionDate,
        Decimal transactionAmount,
        String  notes,
        String  senderEmail
    ) {
        ETransferPaymentResponse response = new ETransferPaymentResponse();

        // ── Input validation ──────────────────────────────────────────────────────
        if (String.isBlank(recordId)) {
            response.success      = false;
            response.errorMessage = 'Record ID is required';
            return response;
        }

        if (String.isBlank(transactionReferenceNumber) || String.isBlank(transactionDate) ||
            transactionAmount == null || transactionAmount <= 0) {
            response.success      = false;
            response.errorMessage = 'All required E-Transfer details must be provided';
            return response;
        }

        try {
            // Create E-Transfer payment transaction record
            Payment__c eTransferRecord = new Payment__c();
            eTransferRecord.Remittance_Form__c          = recordId;
            eTransferRecord.Payment_Initiated_Date__c   = DateTime.now();
            eTransferRecord.Transaction_Reference__c    = transactionReferenceNumber;
            eTransferRecord.Date_Time__c                = DateTime.valueOfGmt(transactionDate + ' 00:00:00');
            eTransferRecord.Amount__c                   = transactionAmount;
            eTransferRecord.Payment_Confirmation_Status__c = 'Deposit Pending'; // awaiting confirmation
            eTransferRecord.Notes__c                    = String.isBlank(notes) ? '' : notes;
            eTransferRecord.Sender_Email__c             = String.isBlank(senderEmail) ? '' : senderEmail;

            // Set RecordType to ETransfer_Payment
            eTransferRecord.RecordTypeId = Schema.SObjectType.Payment__c
                .getRecordTypeInfosByDeveloperName().get('E_Transfer').getRecordTypeId();

            insert eTransferRecord;
            // Junction linking is handled automatically by Update_Remittance_Line_Item_Junction
            // flow (triggers on Payment__c Create). When finance later sets
            // Payment_Confirmation_Status__c = 'Deposit Completed', the
            // Makr_Remittance_Line_Items_Junction_Records_Paid flow calls PaymentStatusInvocable
            // to mark junctions, invoice line items, and invoices as Paid.

            response.success       = true;
            response.transactionId = eTransferRecord.Id;
            response.message       = 'E-Transfer payment details saved successfully';

        } catch (Exception e) {
            response.success      = false;
            response.errorMessage = e.getMessage();
            // Log the failure even for e-transfer payments
            logMonerisHistory('FAILED', recordId, null, null, null, 'E-Transfer payment error: ' + e.getMessage(), null, null, null);
        }

        return response;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Payment Method 4: Dealer Credit
    // Immediate confirmation — applies dealer's available credit to pay the
    // remittance form. Updates Account credit fields and creates a Payment__c
    // record with 'Transaction Completed' status for immediate cascade.
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Retrieves the available dealer credit for the account associated with
     * the given Remittance Form. Called by the LWC to display the credit balance.
     */
    @AuraEnabled(cacheable=true)
    public static Decimal getDealerAvailableCredit(String recordId) {
        if (String.isBlank(recordId)) {
            return 0;
        }

        try {
            Remittance_Form__c rf = [
                SELECT Id, Dealer_Name__c
                FROM Remittance_Form__c
                WHERE Id = :recordId
                LIMIT 1
            ];

            if (rf.Dealer_Name__c == null) {
                return 0;
            }

            Account dealer = [
                SELECT Id, Total_Available_Credit__c
                FROM Account
                WHERE Id = :rf.Dealer_Name__c
                LIMIT 1
            ];

            return dealer.Total_Available_Credit__c != null ? dealer.Total_Available_Credit__c : 0;
        } catch (Exception e) {
            System.debug('Error fetching dealer credit: ' + e.getMessage());
            return 0;
        }
    }

    @AuraEnabled
    public static DealerCreditPaymentResponse processDealerCreditPayment(
        String  recordId,
        Decimal paymentAmount,
        String  notes
    ) {
        DealerCreditPaymentResponse response = new DealerCreditPaymentResponse();

        // ── Input validation ──────────────────────────────────────────────────────
        if (String.isBlank(recordId)) {
            response.success      = false;
            response.errorMessage = 'Record ID is required';
            return response;
        }

        if (paymentAmount == null || paymentAmount <= 0) {
            response.success      = false;
            response.errorMessage = 'Valid payment amount is required';
            return response;
        }

        try {
            // Query the Remittance Form to get the Dealer Account
            Remittance_Form__c remittanceForm = [
                SELECT Id, Amount__c, Balance__c, Dealer_Name__c
                FROM Remittance_Form__c
                WHERE Id = :recordId
                LIMIT 1
            ];

            if (remittanceForm.Dealer_Name__c == null) {
                response.success      = false;
                response.errorMessage = 'No dealer account associated with this remittance form';
                return response;
            }

            // Query the Dealer Account for available credit
            Account dealerAccount = [
                SELECT Id, Total_Available_Credit__c, Applied_Credit__c
                FROM Account
                WHERE Id = :remittanceForm.Dealer_Name__c
                LIMIT 1
            ];

            Decimal availableCredit = dealerAccount.Total_Available_Credit__c != null
                ? dealerAccount.Total_Available_Credit__c : 0;

            // Validate sufficient credit (full payment only)
            if (availableCredit < paymentAmount) {
                response.success      = false;
                response.errorMessage = 'Insufficient dealer credit. Available: $' +
                    availableCredit.setScale(2) + ', Required: $' + paymentAmount.setScale(2);
                return response;
            }

            // ── Create Payment__c record ──────────────────────────────────────────
            Payment__c creditPayment = new Payment__c();
            creditPayment.Remittance_Form__c            = recordId;
            creditPayment.Payment_Initiated_Date__c     = DateTime.now();
            creditPayment.Date_Time__c                  = DateTime.now();
            creditPayment.Amount__c                     = paymentAmount;
            creditPayment.Payment_Confirmation_Status__c = 'Transaction Completed'; // immediate
            creditPayment.Notes__c                      = String.isBlank(notes) ? 'Dealer Credit Applied' : notes;
            creditPayment.Transaction_Reference__c      = 'DC-' + String.valueOf(recordId).substring(0, 15);

            // Set RecordType to Dealer_Credit
            // NOTE: You must create this Record Type on Payment__c first.
            // Developer Name: Dealer_Credit, Label: Dealer Credit
            creditPayment.RecordTypeId = Schema.SObjectType.Payment__c
                .getRecordTypeInfosByDeveloperName().get('Dealer_Credit').getRecordTypeId();

            insert creditPayment;

            // ── Update Account credit fields ──────────────────────────────────────
            Decimal currentApplied = dealerAccount.Applied_Credit__c != null
                ? dealerAccount.Applied_Credit__c : 0;
            dealerAccount.Applied_Credit__c = currentApplied + paymentAmount;
            update dealerAccount;

            // Junction linking and status cascade are handled automatically by flows:
            // 1. Update_Remittance_Line_Item_Junction (on Payment__c Create):
            //    Sets Junction.Payment__c = this Payment Id, then sets
            //    Payment_Confirmation_Status__c = 'Transaction Completed'.
            // 2. Makr_Remittance_Line_Items_Junction_Records_Paid (on Payment__c Update):
            //    Detects the status and calls PaymentStatusInvocable to mark
            //    junctions, invoice line items, and invoices as Paid.

            response.success        = true;
            response.transactionId  = creditPayment.Id;
            response.message        = 'Dealer credit applied successfully';
            response.remainingCredit = availableCredit - paymentAmount;

        } catch (Exception e) {
            response.success      = false;
            response.errorMessage = e.getMessage();
            // Log the failure
            logMonerisHistory('FAILED', recordId, null, null, null, 'Dealer credit payment error: ' + e.getMessage(), null, null, null);
        }

        return response;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // DTO Classes
    // ─────────────────────────────────────────────────────────────────────────────

    public class Amount {
        @AuraEnabled
        public Decimal amount { get; set; }
        @AuraEnabled
        public String currencyCode { get; set; }
    }

    public class Card {
        public String  cardNumber      { get; set; }
        public Integer expiryMonth     { get; set; }
        public Integer expiryYear      { get; set; }
        public String  cardSecurityCode { get; set; }
    }

    public class PaymentMethod {
        // Request fields
        public String paymentMethodSource { get; set; }
        public Card   card                { get; set; }
        public String storePaymentMethod  { get; set; }

        // Response fields
        @AuraEnabled public String          paymentMethodId         { get; set; }
        @AuraEnabled public String          merchantId              { get; set; }
        @AuraEnabled public PaymentMethodInfo paymentMethodInformation { get; set; }
        @AuraEnabled public String          createdAt               { get; set; }
        @AuraEnabled public String          modifiedAt              { get; set; }
    }

    public class PaymentRequest {
        public String        idempotencyKey     { get; set; }
        public String        invoiceNumber      { get; set; }
        public Amount        amount             { get; set; }
        public PaymentMethod paymentMethod      { get; set; }
        public Boolean       automaticCapture   { get; set; }
        public String        ecommerceIndicator { get; set; }
    }

    public class PaymentResponse {
        @AuraEnabled public String             paymentId          { get; set; }
        @AuraEnabled public String             merchantId         { get; set; }
        @AuraEnabled public String             orderId            { get; set; }
        @AuraEnabled public String             invoiceNumber      { get; set; }
        @AuraEnabled public String             transactionDateTime { get; set; }
        @AuraEnabled public String             createdAt          { get; set; }
        @AuraEnabled public String             modifiedAt         { get; set; }
        @AuraEnabled public Amount             amount             { get; set; }
        @AuraEnabled public Amount             authorizedAmount   { get; set; }
        @AuraEnabled public Amount             capturableAmount   { get; set; }
        @AuraEnabled public String             customerId         { get; set; }
        @AuraEnabled public String             customerReference  { get; set; }
        @AuraEnabled public PaymentMethod      paymentMethod      { get; set; }
        @AuraEnabled public String             paymentStatus      { get; set; }
        @AuraEnabled public TransactionDetails transactionDetails { get; set; }
        @AuraEnabled public VerificationDetails verificationDetails { get; set; }
        @AuraEnabled public Boolean            success            { get; set; }
        @AuraEnabled public String             errorMessage       { get; set; }

        public PaymentResponse() {}
    }

    public class TransactionDetails {
        @AuraEnabled public String transactionUniqueId  { get; set; }
        @AuraEnabled public String isoResponseCode      { get; set; }
        @AuraEnabled public String authorizationCode    { get; set; }
        @AuraEnabled public String responseCode         { get; set; }
        @AuraEnabled public String message              { get; set; }
        @AuraEnabled public String ecommerceIndicator   { get; set; }
    }

    public class VerificationDetails {
        @AuraEnabled public String addressVerificationServiceResultCode       { get; set; }
        @AuraEnabled public String cardSecurityCodeResultCode                 { get; set; }
        @AuraEnabled public String threeDSecureAuthenticationValueResultCode  { get; set; }
    }

    public class PaymentMethodInfo {
        @AuraEnabled public String          paymentMethodType   { get; set; }
        @AuraEnabled public CardInformation cardInformation      { get; set; }
        @AuraEnabled public String          storePaymentMethod  { get; set; }
        @AuraEnabled public String          paymentMethodSource { get; set; }
    }

    public class CardInformation {
        @AuraEnabled public String  bankIdentificationNumber { get; set; }
        @AuraEnabled public String  lastFour                 { get; set; }
        @AuraEnabled public Integer expiryMonth              { get; set; }
        @AuraEnabled public Integer expiryYear               { get; set; }
        @AuraEnabled public String  cardBrand                { get; set; }
        @AuraEnabled public String  cardType                 { get; set; }
    }

    public class ChequePaymentResponse {
        @AuraEnabled public Boolean success       { get; set; }
        @AuraEnabled public String  transactionId { get; set; }
        @AuraEnabled public String  message       { get; set; }
        @AuraEnabled public String  errorMessage  { get; set; }

        public ChequePaymentResponse() {
            this.success      = false;
            this.message      = '';
            this.errorMessage = '';
        }
    }

    public class ETransferPaymentResponse {
        @AuraEnabled public Boolean success       { get; set; }
        @AuraEnabled public String  transactionId { get; set; }
        @AuraEnabled public String  message       { get; set; }
        @AuraEnabled public String  errorMessage  { get; set; }

        public ETransferPaymentResponse() {
            this.success      = false;
            this.message      = '';
            this.errorMessage = '';
        }
    }

    public class DealerCreditPaymentResponse {
        @AuraEnabled public Boolean success         { get; set; }
        @AuraEnabled public String  transactionId   { get; set; }
        @AuraEnabled public String  message         { get; set; }
        @AuraEnabled public String  errorMessage    { get; set; }
        @AuraEnabled public Decimal remainingCredit { get; set; }

        public DealerCreditPaymentResponse() {
            this.success         = false;
            this.message         = '';
            this.errorMessage    = '';
            this.remainingCredit = 0;
        }
    }
}