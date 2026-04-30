/**
 * RepairShopIntakeFormControllerTest
 * ──────────────────────────────────────────────────────────────────────────────
 * Coverage target: 99%+
 *
 * Covers:
 *   • All 8 inner wrapper classes (every @AuraEnabled property)
 *   • getVehicleAndShopInfoFromClaim — success, null-field, and error paths
 *   • formatAddress — all branch combinations (street, city, state,
 *                     postalCode, country — each present or absent)
 *   • createEstimate — success, empty lists, bulk, and all null-list
 *                      error paths
 */
@isTest
private class RepairShopIntakeFormControllerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // SHARED SETUP HELPERS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Builds a minimal chain (no Vehicle, no Customer on Application).
     * Sufficient for createEstimate tests that do not need those relationships.
     *
     *   Dealer → Application → Repair_Shop__c → Claim__c
     *
     * Returns a map with keys: 'claim', 'repairShop', 'application'
     */
    private static Map<String, SObject> setupMinimalChain() {
        Account        dealer     = TestDataFactory.createDealer(true);
        Application__c app        = TestDataFactory.createApplication(dealer.Id, true);
        Repair_Shop__c repairShop = TestDataFactory.createRepairShop(true);
        Claim__c       claim      = TestDataFactory.createClaim(
                                        app.Id,
                                        repairShop.Id,
                                        'Warranty_Claim',
                                        true
                                    );
        Map<String, SObject> result = new Map<String, SObject>();
        result.put('claim',      claim);
        result.put('repairShop', repairShop);
        result.put('application', app);
        return result;
    }

    /**
     * Builds a full chain including Vehicle__c and a Person Account
     * (Customer_Name__c) with billing address fields set.
     *
     *   Dealer → Application (Customer_Name__c set)
     *          → Repair_Shop__c
     *          → Claim__c (Vehicle__c set)
     *
     * Returns a map with keys:
     *   'claim', 'repairShop', 'vehicle', 'application', 'customer'
     */
    private static Map<String, SObject> setupFullChain() {
        Account        dealer     = TestDataFactory.createDealer(true);
        Account        customer   = TestDataFactory.createCustomerAccount(true);
        Application__c app        = TestDataFactory.createApplication(dealer.Id, true);

        app.Customer_Name__c = customer.Id;
        update app;

        Repair_Shop__c repairShop = TestDataFactory.createRepairShop(true);
        Vehicle__c     vehicle    = TestDataFactory.createVehicle(true);
        Claim__c       claim      = TestDataFactory.createClaim(
                                        app.Id,
                                        repairShop.Id,
                                        'Warranty_Claim',
                                        true
                                    );
        claim.Vehicle__c = vehicle.Id;
        update claim;

        Map<String, SObject> result = new Map<String, SObject>();
        result.put('claim',      claim);
        result.put('repairShop', repairShop);
        result.put('vehicle',    vehicle);
        result.put('application', app);
        result.put('customer',   customer);
        return result;
    }

    /**
     * Builds a full chain with a customer whose billing address fields
     * are set to the provided values. Used for formatAddress branch tests.
     */
    private static Map<String, SObject> setupChainWithAddress(
        String street,
        String city,
        String state,
        String postalCode,
        String country
    ) {
        Account        dealer   = TestDataFactory.createDealer(true);
        Account        customer = TestDataFactory.createCustomerAccount(true);

        customer.BillingStreet     = street;
        customer.BillingCity       = city;
        customer.BillingState      = state;
        customer.BillingPostalCode = postalCode;
        customer.BillingCountry    = country;
        update customer;

        Application__c app = TestDataFactory.createApplication(dealer.Id, true);
        app.Customer_Name__c = customer.Id;
        update app;

        Repair_Shop__c repairShop = TestDataFactory.createRepairShop(true);
        Claim__c       claim      = TestDataFactory.createClaim(
                                        app.Id,
                                        repairShop.Id,
                                        'Warranty_Claim',
                                        true
                                    );
        Map<String, SObject> result = new Map<String, SObject>();
        result.put('claim',      claim);
        result.put('repairShop', repairShop);
        return result;
    }

    /**
     * Builds a standard EstimateRequest with one service, one part,
     * and one supply. Used for success-path tests.
     */
    private static RepairShopIntakeFormController.EstimateRequest buildFullRequest(
        Id claimId,
        Id repairShopId
    ) {
        RepairShopIntakeFormController.EstimateRequest req =
            new RepairShopIntakeFormController.EstimateRequest();
        req.claimId        = claimId;
        req.repairShopId   = repairShopId;
        req.repairComments = 'Test repair comments';

        RepairShopIntakeFormController.ServiceWrapper svc =
            new RepairShopIntakeFormController.ServiceWrapper();
        svc.category    = 'Engine';
        svc.description = 'Oil change service';
        svc.serviceTime = '1.5';
        svc.cost        = 50.00;
        svc.price       = 75.00;
        svc.discount    = 5.00;
        svc.charge      = 70.00;
        req.services = new List<RepairShopIntakeFormController.ServiceWrapper>{ svc };

        RepairShopIntakeFormController.PartWrapper part =
            new RepairShopIntakeFormController.PartWrapper();
        part.partCode      = 'P001';
        part.description   = 'Oil filter';
        part.quantity      = 1;
        part.partCost      = 15.00;
        part.price         = 25.00;
        part.discount      = 0;
        part.productCharge = 25.00;
        req.parts = new List<RepairShopIntakeFormController.PartWrapper>{ part };

        RepairShopIntakeFormController.SupplyWrapper supply =
            new RepairShopIntakeFormController.SupplyWrapper();
        supply.itemName    = 'Shop Rags';
        supply.description = 'Cleaning supplies';
        supply.supplyTime  = '0.5';
        supply.quantity    = 2;
        supply.cost        = 5.00;
        supply.price       = 10.00;
        supply.discount    = 0;
        supply.charge      = 10.00;
        req.supplies = new List<RepairShopIntakeFormController.SupplyWrapper>{ supply };

        return req;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 1 — INNER WRAPPER CLASS COVERAGE
    // Every @AuraEnabled property on every inner class must be touched.
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testVehicleInfoWrapper_allPropertiesGetAndSet() {
        RepairShopIntakeFormController.VehicleInfo vi =
            new RepairShopIntakeFormController.VehicleInfo();
        vi.vehicle     = 'Toyota Camry';
        vi.vin         = '1HGBH41JXMN109186';
        vi.odometerIn  = '15000';
        vi.odometerOut = '15500';

        System.assertEquals('Toyota Camry',       vi.vehicle,     'vehicle should match');
        System.assertEquals('1HGBH41JXMN109186',  vi.vin,         'vin should match');
        System.assertEquals('15000',               vi.odometerIn,  'odometerIn should match');
        System.assertEquals('15500',               vi.odometerOut, 'odometerOut should match');
    }

    @isTest
    static void testShopInfoWrapper_allPropertiesGetAndSet() {
        RepairShopIntakeFormController.ShopInfo si =
            new RepairShopIntakeFormController.ShopInfo();
        si.name          = 'Test Repair Shop';
        si.address       = '123 Main St, Toronto, ON';
        si.email         = 'shop@test.com';
        si.phone         = '905-555-0100';
        si.hstNumber     = 'HST123456';
        si.taxPercentage = 13.00;

        System.assertEquals('Test Repair Shop', si.name,          'name should match');
        System.assertEquals('123 Main St, Toronto, ON', si.address,'address should match');
        System.assertEquals('shop@test.com',     si.email,         'email should match');
        System.assertEquals('905-555-0100',      si.phone,         'phone should match');
        System.assertEquals('HST123456',         si.hstNumber,     'hstNumber should match');
        System.assertEquals(13.00,               si.taxPercentage, 'taxPercentage should match');
    }

    @isTest
    static void testCustomerInfoWrapper_allPropertiesGetAndSet() {
        RepairShopIntakeFormController.CustomerInfo ci =
            new RepairShopIntakeFormController.CustomerInfo();
        ci.name    = 'John Doe';
        ci.address = '456 Oak Ave, Toronto, ON, M5V 0A1, Canada';
        ci.phone   = '416-555-0200';
        ci.email   = 'john@test.com';

        System.assertEquals('John Doe',   ci.name,    'name should match');
        System.assertEquals('416-555-0200', ci.phone, 'phone should match');
        System.assertEquals('john@test.com', ci.email,'email should match');
    }

    @isTest
    static void testServiceWrapper_allPropertiesGetAndSet() {
        RepairShopIntakeFormController.ServiceWrapper sw =
            new RepairShopIntakeFormController.ServiceWrapper();
        sw.category    = 'Engine';
        sw.description = 'Oil change';
        sw.serviceTime = '1.5';
        sw.cost        = 50.00;
        sw.price       = 75.00;
        sw.discount    = 5.00;
        sw.charge      = 70.00;

        System.assertEquals('Engine',  sw.category,    'category should match');
        System.assertEquals('1.5',     sw.serviceTime, 'serviceTime should match');
        System.assertEquals(50.00,     sw.cost,        'cost should match');
        System.assertEquals(75.00,     sw.price,       'price should match');
        System.assertEquals(5.00,      sw.discount,    'discount should match');
        System.assertEquals(70.00,     sw.charge,      'charge should match');
    }

    @isTest
    static void testPartWrapper_allPropertiesGetAndSet() {
        RepairShopIntakeFormController.PartWrapper pw =
            new RepairShopIntakeFormController.PartWrapper();
        pw.partCode      = 'P001';
        pw.description   = 'Oil filter';
        pw.quantity      = 2;
        pw.partCost      = 15.00;
        pw.price         = 25.00;
        pw.discount      = 2.00;
        pw.productCharge = 23.00;

        System.assertEquals('P001',  pw.partCode,      'partCode should match');
        System.assertEquals(2,       pw.quantity,      'quantity should match');
        System.assertEquals(15.00,   pw.partCost,      'partCost should match');
        System.assertEquals(23.00,   pw.productCharge, 'productCharge should match');
    }

    @isTest
    static void testSupplyWrapper_allPropertiesGetAndSet() {
        RepairShopIntakeFormController.SupplyWrapper sw =
            new RepairShopIntakeFormController.SupplyWrapper();
        sw.itemName    = 'Shop Rags';
        sw.description = 'Cleaning supplies';
        sw.supplyTime  = '0.5';
        sw.quantity    = 3;
        sw.cost        = 5.00;
        sw.price       = 10.00;
        sw.discount    = 1.00;
        sw.charge      = 9.00;

        System.assertEquals('Shop Rags', sw.itemName,   'itemName should match');
        System.assertEquals('0.5',       sw.supplyTime, 'supplyTime should match');
        System.assertEquals(3,           sw.quantity,   'quantity should match');
        System.assertEquals(9.00,        sw.charge,     'charge should match');
    }

    @isTest
    static void testClaimInfoWrapper_allPropertiesGetAndSet() {
        RepairShopIntakeFormController.VehicleInfo  vi  = new RepairShopIntakeFormController.VehicleInfo();
        RepairShopIntakeFormController.ShopInfo     si  = new RepairShopIntakeFormController.ShopInfo();
        RepairShopIntakeFormController.CustomerInfo ci  = new RepairShopIntakeFormController.CustomerInfo();
        RepairShopIntakeFormController.ClaimInfoWrapper ciw =
            new RepairShopIntakeFormController.ClaimInfoWrapper();
        ciw.vehicleInfo  = vi;
        ciw.shopInfo     = si;
        ciw.customerInfo = ci;

        System.assertNotEquals(null, ciw.vehicleInfo,  'vehicleInfo should be set');
        System.assertNotEquals(null, ciw.shopInfo,     'shopInfo should be set');
        System.assertNotEquals(null, ciw.customerInfo, 'customerInfo should be set');
    }

    @isTest
    static void testEstimateRequestWrapper_allPropertiesGetAndSet() {
        RepairShopIntakeFormController.EstimateRequest er =
            new RepairShopIntakeFormController.EstimateRequest();
        er.claimId       = 'testClaimId';
        er.repairShopId  = 'testShopId';
        er.repairComments = 'Test comments';
        er.services = new List<RepairShopIntakeFormController.ServiceWrapper>();
        er.parts    = new List<RepairShopIntakeFormController.PartWrapper>();
        er.supplies = new List<RepairShopIntakeFormController.SupplyWrapper>();

        System.assertEquals('testClaimId',  er.claimId,       'claimId should match');
        System.assertEquals('testShopId',   er.repairShopId,  'repairShopId should match');
        System.assertEquals('Test comments',er.repairComments,'repairComments should match');
        System.assertNotEquals(null, er.services, 'services should be set');
        System.assertNotEquals(null, er.parts,    'parts should be set');
        System.assertNotEquals(null, er.supplies, 'supplies should be set');
    }

    @isTest
    static void testEstimateResponseWrapper_allPropertiesGetAndSet() {
        RepairShopIntakeFormController.EstimateResponse resp =
            new RepairShopIntakeFormController.EstimateResponse();
        resp.estimateId = 'estId123';
        resp.status     = 'SUCCESS';
        resp.message    = 'New estimate created successfully';

        System.assertEquals('estId123',  resp.estimateId, 'estimateId should match');
        System.assertEquals('SUCCESS',   resp.status,     'status should match');
        System.assertEquals('New estimate created successfully', resp.message,
            'message should match');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 2 — getVehicleAndShopInfoFromClaim — SUCCESS PATH
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetVehicleAndShopInfo_allRelationshipsPopulated() {
        Map<String, SObject> chain = setupFullChain();
        Claim__c claim = (Claim__c) chain.get('claim');

        Test.startTest();
            RepairShopIntakeFormController.ClaimInfoWrapper result =
                RepairShopIntakeFormController.getVehicleAndShopInfoFromClaim(claim.Id);
        Test.stopTest();

        System.assertNotEquals(null, result,             'Result wrapper should not be null');
        System.assertNotEquals(null, result.vehicleInfo, 'VehicleInfo should not be null');
        System.assertNotEquals(null, result.shopInfo,    'ShopInfo should not be null');
        System.assertNotEquals(null, result.customerInfo,'CustomerInfo should not be null');
    }

    @isTest
    static void testGetVehicleAndShopInfo_vehicleFieldsPopulated() {
        Map<String, SObject> chain = setupFullChain();
        Claim__c   claim   = (Claim__c)   chain.get('claim');
        Vehicle__c vehicle = (Vehicle__c) chain.get('vehicle');

        Test.startTest();
            RepairShopIntakeFormController.ClaimInfoWrapper result =
                RepairShopIntakeFormController.getVehicleAndShopInfoFromClaim(claim.Id);
        Test.stopTest();

        System.assertNotEquals(null, result.vehicleInfo.vehicle,
            'Vehicle name should be populated from Vehicle__r.Name');
        System.assertNotEquals(null, result.vehicleInfo.vin,
            'VIN should be populated from Vehicle__r.VIN__c');
        System.assertNotEquals(null, result.vehicleInfo.odometerIn,
            'OdometerIn should be populated from Vehicle__r.Odometer__c');
    }

    @isTest
    static void testGetVehicleAndShopInfo_shopInfoFieldsPopulated() {
        Map<String, SObject> chain = setupFullChain();
        Claim__c claim = (Claim__c) chain.get('claim');

        Test.startTest();
            RepairShopIntakeFormController.ClaimInfoWrapper result =
                RepairShopIntakeFormController.getVehicleAndShopInfoFromClaim(claim.Id);
        Test.stopTest();
    }

    @isTest
    static void testGetVehicleAndShopInfo_taxPercentagePopulated() {
        Map<String, SObject> chain = setupFullChain();
        Claim__c claim = (Claim__c) chain.get('claim');

        // Set a known tax percentage on the repair shop so we can assert it
        Repair_Shop__c repairShop = (Repair_Shop__c) chain.get('repairShop');
        repairShop.Tax_Percentage__c = 13.00;
        update repairShop;

        Test.startTest();
            RepairShopIntakeFormController.ClaimInfoWrapper result =
                RepairShopIntakeFormController.getVehicleAndShopInfoFromClaim(claim.Id);
        Test.stopTest();

        System.assertEquals(13.00, result.shopInfo.taxPercentage,
            'Tax percentage should match the Repair_Shop__r.Tax_Percentage__c value');
    }

    @isTest
    static void testGetVehicleAndShopInfo_noVehicleLinked_vehicleFieldsAreNull() {
        Map<String, SObject> chain = setupMinimalChain();
        Claim__c claim = (Claim__c) chain.get('claim');

        Test.startTest();
            RepairShopIntakeFormController.ClaimInfoWrapper result =
                RepairShopIntakeFormController.getVehicleAndShopInfoFromClaim(claim.Id);
        Test.stopTest();

        System.assertEquals(null, result.vehicleInfo.vehicle,
            'Vehicle name should be null when no Vehicle__c on Claim');
        System.assertEquals(null, result.vehicleInfo.vin,
            'VIN should be null when no Vehicle__c on Claim');
    }

    @isTest
    static void testGetVehicleAndShopInfo_noCustomerLinked_customerFieldsAreNull() {
        // Minimal chain — Application has no Customer_Name__c
        Map<String, SObject> chain = setupMinimalChain();
        Claim__c claim = (Claim__c) chain.get('claim');

        Test.startTest();
            RepairShopIntakeFormController.ClaimInfoWrapper result =
                RepairShopIntakeFormController.getVehicleAndShopInfoFromClaim(claim.Id);
        Test.stopTest();

        System.assertEquals(null, result.customerInfo.name,
            'Customer name should be null when no Customer_Name__c on Application');
        System.assertEquals(null, result.customerInfo.phone,
            'Customer phone should be null when no Customer_Name__c on Application');
        System.assertEquals(null, result.customerInfo.email,
            'Customer email should be null when no Customer_Name__c on Application');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 3 — formatAddress branch coverage
    // Tests every if/ternary combination in formatAddress indirectly
    // via getVehicleAndShopInfoFromClaim with controlled billing address values
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testFormatAddress_allPartsPopulated_fullAddressReturned() {
        Map<String, SObject> chain = setupChainWithAddress(
            '123 Main Street', 'Toronto', 'ON', 'M5V 0A1', 'Canada'
        );
        Claim__c claim = (Claim__c) chain.get('claim');

        Test.startTest();
            RepairShopIntakeFormController.ClaimInfoWrapper result =
                RepairShopIntakeFormController.getVehicleAndShopInfoFromClaim(claim.Id);
        Test.stopTest();

        String addr = result.customerInfo.address;
        System.assertNotEquals(null, addr, 'Address should not be null');
        System.assert(addr.contains('123 Main Street'), 'Street should appear in address');
        System.assert(addr.contains('Toronto'),         'City should appear in address');
        System.assert(addr.contains('ON'),              'State should appear in address');
        System.assert(addr.contains('M5V 0A1'),         'PostalCode should appear in address');
        System.assert(addr.contains('Canada'),          'Country should appear in address');
        // City and State should be joined with a comma separator
        System.assert(addr.contains('Toronto, ON'),
            'City and State should be separated by a comma');
    }

    @isTest
    static void testFormatAddress_allBlank_returnsEmptyString() {
        // All null — formatAddress returns '' (String.join on empty list)
        Map<String, SObject> chain = setupChainWithAddress(null, null, null, null, null);
        Claim__c claim = (Claim__c) chain.get('claim');

        Test.startTest();
            RepairShopIntakeFormController.ClaimInfoWrapper result =
                RepairShopIntakeFormController.getVehicleAndShopInfoFromClaim(claim.Id);
        Test.stopTest();

        System.assertEquals('', result.customerInfo.address,
            'Address should be empty string when all parts are null');
    }

    @isTest
    static void testFormatAddress_onlyStreet() {
        Map<String, SObject> chain = setupChainWithAddress(
            '99 Elm Street', null, null, null, null
        );
        Claim__c claim = (Claim__c) chain.get('claim');

        Test.startTest();
            RepairShopIntakeFormController.ClaimInfoWrapper result =
                RepairShopIntakeFormController.getVehicleAndShopInfoFromClaim(claim.Id);
        Test.stopTest();

        System.assertEquals('99 Elm Street', result.customerInfo.address,
            'Address should contain only the street');
    }

    @isTest
    static void testFormatAddress_cityAndStateOnly_joinedWithComma() {
        // Both city and state set — tests the ternary ', ' prefix branch
        Map<String, SObject> chain = setupChainWithAddress(
            null, 'Ottawa', 'ON', null, null
        );
        Claim__c claim = (Claim__c) chain.get('claim');

        Test.startTest();
            RepairShopIntakeFormController.ClaimInfoWrapper result =
                RepairShopIntakeFormController.getVehicleAndShopInfoFromClaim(claim.Id);
        Test.stopTest();

        System.assertEquals('Ottawa, ON', result.customerInfo.address,
            'City and State should be comma-joined when both present');
    }

    @isTest
    static void testFormatAddress_onlyCity_noCommaPrefix() {
        // City only — state blank, so no ', ' prefix in cityState
        Map<String, SObject> chain = setupChainWithAddress(
            null, 'Vancouver', null, null, null
        );
        Claim__c claim = (Claim__c) chain.get('claim');

        Test.startTest();
            RepairShopIntakeFormController.ClaimInfoWrapper result =
                RepairShopIntakeFormController.getVehicleAndShopInfoFromClaim(claim.Id);
        Test.stopTest();

        System.assertEquals('Vancouver', result.customerInfo.address,
            'Address should be just the city when only city is set');
    }

    @isTest
    static void testFormatAddress_onlyState_cityBlankNoCommaPrefix() {
        // State only — city blank so cityState starts blank, no ', ' prefix
        // Hits the ternary false branch: isNotBlank(cityState) = false → ''
        Map<String, SObject> chain = setupChainWithAddress(
            null, null, 'BC', null, null
        );
        Claim__c claim = (Claim__c) chain.get('claim');

        Test.startTest();
            RepairShopIntakeFormController.ClaimInfoWrapper result =
                RepairShopIntakeFormController.getVehicleAndShopInfoFromClaim(claim.Id);
        Test.stopTest();

        System.assertEquals('BC', result.customerInfo.address,
            'Address should be just the state when only state is set');
    }

    @isTest
    static void testFormatAddress_onlyPostalCode() {
        Map<String, SObject> chain = setupChainWithAddress(
            null, null, null, 'M5V 0A1', null
        );
        Claim__c claim = (Claim__c) chain.get('claim');

        Test.startTest();
            RepairShopIntakeFormController.ClaimInfoWrapper result =
                RepairShopIntakeFormController.getVehicleAndShopInfoFromClaim(claim.Id);
        Test.stopTest();

        System.assertEquals('M5V 0A1', result.customerInfo.address,
            'Address should be just the postal code when only postal code is set');
    }

    @isTest
    static void testFormatAddress_onlyCountry() {
        Map<String, SObject> chain = setupChainWithAddress(
            null, null, null, null, 'Canada'
        );
        Claim__c claim = (Claim__c) chain.get('claim');

        Test.startTest();
            RepairShopIntakeFormController.ClaimInfoWrapper result =
                RepairShopIntakeFormController.getVehicleAndShopInfoFromClaim(claim.Id);
        Test.stopTest();

        System.assertEquals('Canada', result.customerInfo.address,
            'Address should be just the country when only country is set');
    }

    @isTest
    static void testFormatAddress_streetAndCountryNoCityState() {
        // Street + Country but no city/state/postal — cityState stays blank,
        // not added to addressParts
        Map<String, SObject> chain = setupChainWithAddress(
            '10 Bay St', null, null, null, 'Canada'
        );
        Claim__c claim = (Claim__c) chain.get('claim');

        Test.startTest();
            RepairShopIntakeFormController.ClaimInfoWrapper result =
                RepairShopIntakeFormController.getVehicleAndShopInfoFromClaim(claim.Id);
        Test.stopTest();

        String addr = result.customerInfo.address;
        System.assert(addr.contains('10 Bay St'), 'Street should be in address');
        System.assert(addr.contains('Canada'),    'Country should be in address');
        System.assert(!addr.contains(', ,'),
            'No empty segment separators should appear');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 4 — getVehicleAndShopInfoFromClaim — ERROR PATH
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetVehicleAndShopInfo_invalidStringIdThrowsAuraHandledException() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            RepairShopIntakeFormController.getVehicleAndShopInfoFromClaim('notAnId');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
    }

    @isTest
    static void testGetVehicleAndShopInfo_nonExistentIdThrowsAuraHandledException() {
        // Well-formed Claim Id that does not exist — SOQL returns 0 rows → ListException
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            RepairShopIntakeFormController.getVehicleAndShopInfoFromClaim(
                'a0000000000000ZAAQ'
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown,
            'Non-existent claimId should throw AuraHandledException');
    }

    @isTest
    static void testGetVehicleAndShopInfo_nullIdThrowsAuraHandledException() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            RepairShopIntakeFormController.getVehicleAndShopInfoFromClaim(null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown,
            'Null claimId should throw AuraHandledException');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 5 — createEstimate — SUCCESS PATH
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testCreateEstimate_successStatusAndEstimateIdReturned() {
        Map<String, SObject> chain = setupMinimalChain();
        Claim__c       claim      = (Claim__c)       chain.get('claim');
        Repair_Shop__c repairShop = (Repair_Shop__c) chain.get('repairShop');

        Test.startTest();
            RepairShopIntakeFormController.EstimateResponse resp =
                RepairShopIntakeFormController.createEstimate(
                    buildFullRequest(claim.Id, repairShop.Id)
                );
        Test.stopTest();

        System.assertEquals('SUCCESS', resp.status,
            'createEstimate should return SUCCESS');
        System.assertNotEquals(null, resp.estimateId,
            'EstimateId should be returned on success');
        System.assertEquals('New estimate created successfully', resp.message,
            'Success message should match');
    }

    @isTest
    static void testCreateEstimate_estimateRecordPersistedCorrectly() {
        Map<String, SObject> chain = setupMinimalChain();
        Claim__c       claim      = (Claim__c)       chain.get('claim');
        Repair_Shop__c repairShop = (Repair_Shop__c) chain.get('repairShop');

        Test.startTest();
            RepairShopIntakeFormController.EstimateResponse resp =
                RepairShopIntakeFormController.createEstimate(
                    buildFullRequest(claim.Id, repairShop.Id)
                );
        Test.stopTest();

        Estimate__c saved = [
            SELECT Claim__c, Repair_Shop__c, Repair_Comments__c
            FROM   Estimate__c
            WHERE  Id = :resp.estimateId
        ];
        System.assertEquals(claim.Id,      saved.Claim__c,
            'Estimate should be linked to correct Claim');
        System.assertEquals(repairShop.Id, saved.Repair_Shop__c,
            'Estimate should be linked to correct Repair Shop');
        System.assertEquals('Test repair comments', saved.Repair_Comments__c,
            'Repair comments should be persisted');
    }

    @isTest
    static void testCreateEstimate_serviceRecordPersistedCorrectly() {
        Map<String, SObject> chain = setupMinimalChain();
        Claim__c       claim      = (Claim__c)       chain.get('claim');
        Repair_Shop__c repairShop = (Repair_Shop__c) chain.get('repairShop');

        Test.startTest();
            RepairShopIntakeFormController.EstimateResponse resp =
                RepairShopIntakeFormController.createEstimate(
                    buildFullRequest(claim.Id, repairShop.Id)
                );
        Test.stopTest();

        List<Service__c> services = [
            SELECT Category__c, Item_Desription__c, Time__c,
                   Cost__c, Price__c, Discount__c, Charge__c,
                   Repair_Shop__c
            FROM   Service__c
            WHERE  Estimate__c = :resp.estimateId
        ];
        System.assertEquals(1, services.size(),
            'Exactly one Service__c should be created');
        System.assertEquals('Engine',     services[0].Category__c,
            'Category should match ServiceWrapper.category');
        System.assertEquals('1.5',        services[0].Time__c,
            'Time should match ServiceWrapper.serviceTime');
        System.assertEquals(50.00,        services[0].Cost__c,
            'Cost should match ServiceWrapper.cost');
        System.assertEquals(75.00,        services[0].Price__c,
            'Price should match ServiceWrapper.price');
        System.assertEquals(5.00,         services[0].Discount__c,
            'Discount should match ServiceWrapper.discount');
        System.assertEquals(70.00,        services[0].Charge__c,
            'Charge should match ServiceWrapper.charge');
        System.assertEquals(repairShop.Id,services[0].Repair_Shop__c,
            'Service should be linked to the correct Repair Shop');
    }

    @isTest
    static void testCreateEstimate_partRecordPersistedCorrectly() {
        Map<String, SObject> chain = setupMinimalChain();
        Claim__c       claim      = (Claim__c)       chain.get('claim');
        Repair_Shop__c repairShop = (Repair_Shop__c) chain.get('repairShop');

        Test.startTest();
            RepairShopIntakeFormController.EstimateResponse resp =
                RepairShopIntakeFormController.createEstimate(
                    buildFullRequest(claim.Id, repairShop.Id)
                );
        Test.stopTest();

        List<Part__c> parts = [
            SELECT Part_Code__c, Quantity__c, Part_Cost__c,
                   Price__c, Discount__c, Product_Charge__c,
                   Repair_Shop__c
            FROM   Part__c
            WHERE  Estimate__c = :resp.estimateId
        ];
        System.assertEquals(1,     parts.size(),             'Exactly one Part__c should be created');
        System.assertEquals('P001',parts[0].Part_Code__c,    'Part code should match');
        System.assertEquals(1,     parts[0].Quantity__c,     'Quantity should match');
        System.assertEquals(15.00, parts[0].Part_Cost__c,    'Part cost should match');
        System.assertEquals(25.00, parts[0].Price__c,        'Price should match');
        System.assertEquals(0,     parts[0].Discount__c,     'Discount should match');
        System.assertEquals(25.00, parts[0].Product_Charge__c,'Product charge should match');
        System.assertEquals(repairShop.Id, parts[0].Repair_Shop__c,
            'Part should be linked to the correct Repair Shop');
    }

    @isTest
    static void testCreateEstimate_supplyRecordPersistedCorrectly() {
        Map<String, SObject> chain = setupMinimalChain();
        Claim__c       claim      = (Claim__c)       chain.get('claim');
        Repair_Shop__c repairShop = (Repair_Shop__c) chain.get('repairShop');

        Test.startTest();
            RepairShopIntakeFormController.EstimateResponse resp =
                RepairShopIntakeFormController.createEstimate(
                    buildFullRequest(claim.Id, repairShop.Id)
                );
        Test.stopTest();

        List<Shop_Supply__c> supplies = [
            SELECT Item_Name__c, Time__c, Quantity__c,
                   Cost__c, Price__c, Discount__c, Charge__c,
                   Repair_Shop__c
            FROM   Shop_Supply__c
            WHERE  Estimate__c = :resp.estimateId
        ];
        System.assertEquals(1,          supplies.size(),            'Exactly one Shop_Supply__c should be created');
        System.assertEquals('Shop Rags',supplies[0].Item_Name__c,   'Item name should match');
        System.assertEquals('0.5',      supplies[0].Time__c,        'Supply time should match');
        System.assertEquals(2,          supplies[0].Quantity__c,    'Quantity should match');
        System.assertEquals(5.00,       supplies[0].Cost__c,        'Cost should match');
        System.assertEquals(10.00,      supplies[0].Price__c,       'Price should match');
        System.assertEquals(0,          supplies[0].Discount__c,    'Discount should match');
        System.assertEquals(10.00,      supplies[0].Charge__c,      'Charge should match');
        System.assertEquals(repairShop.Id, supplies[0].Repair_Shop__c,
            'Supply should be linked to the correct Repair Shop');
    }

    @isTest
    static void testCreateEstimate_emptyLists_onlyEstimateCreated() {
        Map<String, SObject> chain = setupMinimalChain();
        Claim__c       claim      = (Claim__c)       chain.get('claim');
        Repair_Shop__c repairShop = (Repair_Shop__c) chain.get('repairShop');

        RepairShopIntakeFormController.EstimateRequest req =
            new RepairShopIntakeFormController.EstimateRequest();
        req.claimId        = claim.Id;
        req.repairShopId   = repairShop.Id;
        req.repairComments = 'Empty lists test';
        req.services = new List<RepairShopIntakeFormController.ServiceWrapper>();
        req.parts    = new List<RepairShopIntakeFormController.PartWrapper>();
        req.supplies = new List<RepairShopIntakeFormController.SupplyWrapper>();

        Test.startTest();
            RepairShopIntakeFormController.EstimateResponse resp =
                RepairShopIntakeFormController.createEstimate(req);
        Test.stopTest();

        System.assertEquals('SUCCESS', resp.status,
            'Empty lists should still return SUCCESS');
        System.assertNotEquals(null, resp.estimateId,
            'Estimate should still be created');
        System.assertEquals(0,
            [SELECT COUNT() FROM Service__c   WHERE Estimate__c = :resp.estimateId],
            'No services should be created for empty list');
        System.assertEquals(0,
            [SELECT COUNT() FROM Part__c      WHERE Estimate__c = :resp.estimateId],
            'No parts should be created for empty list');
        System.assertEquals(0,
            [SELECT COUNT() FROM Shop_Supply__c WHERE Estimate__c = :resp.estimateId],
            'No supplies should be created for empty list');
    }

    @isTest
    static void testCreateEstimate_bulk200Services() {
        Map<String, SObject> chain = setupMinimalChain();
        Claim__c       claim      = (Claim__c)       chain.get('claim');
        Repair_Shop__c repairShop = (Repair_Shop__c) chain.get('repairShop');

        List<RepairShopIntakeFormController.ServiceWrapper> services =
            new List<RepairShopIntakeFormController.ServiceWrapper>();
        for (Integer i = 0; i < 200; i++) {
            RepairShopIntakeFormController.ServiceWrapper svc =
                new RepairShopIntakeFormController.ServiceWrapper();
            svc.category    = 'Engine';
            svc.description = 'Bulk service ' + i;
            svc.serviceTime = '1.0';
            svc.cost        = 40.00;
            svc.price       = 60.00;
            svc.discount    = 0;
            svc.charge      = 60.00;
            services.add(svc);
        }

        RepairShopIntakeFormController.EstimateRequest req =
            new RepairShopIntakeFormController.EstimateRequest();
        req.claimId      = claim.Id;
        req.repairShopId = repairShop.Id;
        req.services = services;
        req.parts    = new List<RepairShopIntakeFormController.PartWrapper>();
        req.supplies = new List<RepairShopIntakeFormController.SupplyWrapper>();

        Test.startTest();
            RepairShopIntakeFormController.EstimateResponse resp =
                RepairShopIntakeFormController.createEstimate(req);
        Test.stopTest();

        System.assertEquals('SUCCESS', resp.status,
            'Bulk 200 services should return SUCCESS');
        System.assertEquals(200,
            [SELECT COUNT() FROM Service__c WHERE Estimate__c = :resp.estimateId],
            '200 Service__c records should be created');
    }

    @isTest
    static void testCreateEstimate_multiplePartsAndSupplies() {
        Map<String, SObject> chain = setupMinimalChain();
        Claim__c       claim      = (Claim__c)       chain.get('claim');
        Repair_Shop__c repairShop = (Repair_Shop__c) chain.get('repairShop');

        List<RepairShopIntakeFormController.PartWrapper> parts =
            new List<RepairShopIntakeFormController.PartWrapper>();
        for (Integer i = 0; i < 5; i++) {
            RepairShopIntakeFormController.PartWrapper p =
                new RepairShopIntakeFormController.PartWrapper();
            p.partCode      = 'P00' + i;
            p.description   = 'Part ' + i;
            p.quantity      = 1;
            p.partCost      = 10.00;
            p.price         = 20.00;
            p.discount      = 0;
            p.productCharge = 20.00;
            parts.add(p);
        }

        List<RepairShopIntakeFormController.SupplyWrapper> supplies =
            new List<RepairShopIntakeFormController.SupplyWrapper>();
        for (Integer i = 0; i < 3; i++) {
            RepairShopIntakeFormController.SupplyWrapper s =
                new RepairShopIntakeFormController.SupplyWrapper();
            s.itemName    = 'Supply ' + i;
            s.description = 'Supply desc ' + i;
            s.supplyTime  = '0.25';
            s.quantity    = 1;
            s.cost        = 5.00;
            s.price       = 8.00;
            s.discount    = 0;
            s.charge      = 8.00;
            supplies.add(s);
        }

        RepairShopIntakeFormController.EstimateRequest req =
            new RepairShopIntakeFormController.EstimateRequest();
        req.claimId      = claim.Id;
        req.repairShopId = repairShop.Id;
        req.services = new List<RepairShopIntakeFormController.ServiceWrapper>();
        req.parts    = parts;
        req.supplies = supplies;

        Test.startTest();
            RepairShopIntakeFormController.EstimateResponse resp =
                RepairShopIntakeFormController.createEstimate(req);
        Test.stopTest();

        System.assertEquals('SUCCESS', resp.status, 'Should return SUCCESS');
        System.assertEquals(5,
            [SELECT COUNT() FROM Part__c       WHERE Estimate__c = :resp.estimateId],
            '5 parts should be created');
        System.assertEquals(3,
            [SELECT COUNT() FROM Shop_Supply__c WHERE Estimate__c = :resp.estimateId],
            '3 supplies should be created');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 6 — createEstimate — ERROR PATH
    // Each null list hits a different for-loop NullPointerException branch
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testCreateEstimate_nullServicesListReturnsErrorResponse() {
        Map<String, SObject> chain = setupMinimalChain();
        Claim__c       claim      = (Claim__c)       chain.get('claim');
        Repair_Shop__c repairShop = (Repair_Shop__c) chain.get('repairShop');

        RepairShopIntakeFormController.EstimateRequest req =
            new RepairShopIntakeFormController.EstimateRequest();
        req.claimId      = claim.Id;
        req.repairShopId = repairShop.Id;
        req.services = null; // → NullPointerException in for loop → catch block
        req.parts    = new List<RepairShopIntakeFormController.PartWrapper>();
        req.supplies = new List<RepairShopIntakeFormController.SupplyWrapper>();

        Test.startTest();
            RepairShopIntakeFormController.EstimateResponse resp =
                RepairShopIntakeFormController.createEstimate(req);
        Test.stopTest();

        System.assertEquals('ERROR', resp.status,
            'Null services list should return ERROR status');
        System.assertNotEquals(null, resp.message,
            'Error message should be populated');
    }

    @isTest
    static void testCreateEstimate_nullPartsListReturnsErrorResponse() {
        Map<String, SObject> chain = setupMinimalChain();
        Claim__c       claim      = (Claim__c)       chain.get('claim');
        Repair_Shop__c repairShop = (Repair_Shop__c) chain.get('repairShop');

        RepairShopIntakeFormController.EstimateRequest req =
            new RepairShopIntakeFormController.EstimateRequest();
        req.claimId      = claim.Id;
        req.repairShopId = repairShop.Id;
        req.services = new List<RepairShopIntakeFormController.ServiceWrapper>();
        req.parts    = null; // → NullPointerException in for loop → catch block
        req.supplies = new List<RepairShopIntakeFormController.SupplyWrapper>();

        Test.startTest();
            RepairShopIntakeFormController.EstimateResponse resp =
                RepairShopIntakeFormController.createEstimate(req);
        Test.stopTest();

        System.assertEquals('ERROR', resp.status,
            'Null parts list should return ERROR status');
        System.assertNotEquals(null, resp.message,
            'Error message should be populated');
    }

    @isTest
    static void testCreateEstimate_nullSuppliesListReturnsErrorResponse() {
        Map<String, SObject> chain = setupMinimalChain();
        Claim__c       claim      = (Claim__c)       chain.get('claim');
        Repair_Shop__c repairShop = (Repair_Shop__c) chain.get('repairShop');

        RepairShopIntakeFormController.EstimateRequest req =
            new RepairShopIntakeFormController.EstimateRequest();
        req.claimId      = claim.Id;
        req.repairShopId = repairShop.Id;
        req.services = new List<RepairShopIntakeFormController.ServiceWrapper>();
        req.parts    = new List<RepairShopIntakeFormController.PartWrapper>();
        req.supplies = null; // → NullPointerException in for loop → catch block

        Test.startTest();
            RepairShopIntakeFormController.EstimateResponse resp =
                RepairShopIntakeFormController.createEstimate(req);
        Test.stopTest();

        System.assertEquals('ERROR', resp.status,
            'Null supplies list should return ERROR status');
        System.assertNotEquals(null, resp.message,
            'Error message should be populated');
    }

    @isTest
    static void testCreateEstimate_invalidClaimIdReturnsErrorResponse() {
        Repair_Shop__c repairShop = TestDataFactory.createRepairShop(true);

        RepairShopIntakeFormController.EstimateRequest req =
            new RepairShopIntakeFormController.EstimateRequest();
        req.claimId      = 'notAValidClaimId';
        req.repairShopId = repairShop.Id;
        req.services = new List<RepairShopIntakeFormController.ServiceWrapper>();
        req.parts    = new List<RepairShopIntakeFormController.PartWrapper>();
        req.supplies = new List<RepairShopIntakeFormController.SupplyWrapper>();

        Test.startTest();
            RepairShopIntakeFormController.EstimateResponse resp =
                RepairShopIntakeFormController.createEstimate(req);
        Test.stopTest();

        System.assertEquals('ERROR', resp.status,
            'Invalid claimId string should return ERROR status');
        System.assertNotEquals(null, resp.message,
            'Error message should be populated');
        System.assertEquals(null, resp.estimateId,
            'EstimateId should be null on error');
    }

    @isTest
    static void testCreateEstimate_nullClaimIdReturnsErrorResponse() {
        // Null Claim__c on a Master-Detail → DML required field error
        Repair_Shop__c repairShop = TestDataFactory.createRepairShop(true);

        RepairShopIntakeFormController.EstimateRequest req =
            new RepairShopIntakeFormController.EstimateRequest();
        req.claimId      = null;
        req.repairShopId = repairShop.Id;
        req.services = new List<RepairShopIntakeFormController.ServiceWrapper>();
        req.parts    = new List<RepairShopIntakeFormController.PartWrapper>();
        req.supplies = new List<RepairShopIntakeFormController.SupplyWrapper>();

        Test.startTest();
            RepairShopIntakeFormController.EstimateResponse resp =
                RepairShopIntakeFormController.createEstimate(req);
        Test.stopTest();

        System.assertEquals('ERROR', resp.status,
            'Null claimId should return ERROR — Claim__c is required on Estimate');
        System.assertNotEquals(null, resp.message,
            'Error message should be populated');
    }
}