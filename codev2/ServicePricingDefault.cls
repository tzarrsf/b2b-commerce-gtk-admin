/**
 * @description       : Example Service for Pricing aspects. This class is part of the "Get to Know B2B Commerce for Administrators"
 *                      curriculum in the Salesforce Partner Learning Camp (PLC) and loosely based on the example provided at this URL:
 *                      https://github.com/forcedotcom/commerce-extensibility/blob/releases/248/commerce/domain/pricing/service/classes/PricingServiceSample.cls
 *
 *                      Original Comments in the referenced code:
 *                      -----------------------------------------
 *                      This sample is for the situation when the pricing behavior needs to be extended or overriden via
 *                      the extension point for Salesorce Internal Pricing Api. For Salesforce Internal Price
 *                      calculation, please see the corresponding documentation.
 *                      Your custom apex class must be linked to the pricing extension point and then the integration
 *                      must be linked to the webstore via appropriate setup. For more information related to that,
 *                      please see the corresponding documentation.
 *
 *                      Notable modifications made to original example code to better suit this course and improve understanding:
 *                      ---------------------------------------------------------------------------------------------------------
 *                      1. Screaming constants (static final variables) for legibility / consistency
 *                      2. Many additional System.debug entries
 *                      3. Reformatting and alignment for legibility
 *                      4. Superfluous constructor removed in favor of a constant USE_EXTERNAL_SERVICE
 *                      5. Added PRICE_NOT_FOUND_DEFAULT_VALUE for fallback when price isn't found
 *                      6. Added BUBBLE_EXCEPTIONS for configurability
 *                      7. Added LOG_CART_DETAIL_ACTIVE and LOG_CART_ITEM_DETAIL_ACTIVE with methods for additional diagnostics
 *                      8. Introduced the Capricorn sample product price map for local calls (when USE_EXTERNAL_SERVICE is false)
 *                      9. WIP - Added a productCode property to PricingDataStructure structure so we can perform a lookup
 *                      10. WIP - Added a REST call for WebStore pricing data to drive the point home
 *                      11. Added more comments
 *                      12. Some refactoring to remove complexity
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : Salesforce Commerce Partner Delivery Success (2024)
 * @last modified on  : 09-18-2024
 * @last modified by  : Tom Zarr
**/

/*
This must implement the commercestorepricing.ServicePricingDefault class in order to be processed by the pricing flow.
*/
public class ServicePricingDefault extends commercestorepricing.PricingService
{
    // The name of the WebStore as it appears in the Commerce app UI - used to resolve the Webstore Id
    private static final string WEBSTORE_NAME = 'Alpine B2B LWR Store';

    // Removes the magic strings
    private static final Decimal ZERO_DECIMAL = 0.0;

    // Query parameters used with the Connect API for pricing in the constructor
    private static final Id[] PRODUCT_OVERVIEW_QUERY_PRODUCT_ID_LIST = new Id[]{};
    private static final String[] PRODUCT_OVERVIEW_QUERY_FIELDS = new String[] {'Id','ProductCode','StockKeepingUnit'};
    private static final Boolean PRODUCT_OVERVIEW_QUERY_EXCLUDE_MEDIA = true;

    // Set this to true to see a a networked call take place against your org - for demonstration purposes only
    private static final Boolean USE_EXTERNAL_SERVICE = false;

    // Supports a default value for pricing when the pricing is not found - for demostration purposes only
    private static final Decimal PRICE_NOT_FOUND_DEFAULT_VALUE = 50.00;

    // Set this to true to leave the last Capricorn sample out of the mapping to demonstrate how a missing pricing is handled
    private static Boolean DEMO_MISSING_PRICE_ITEM = true;

    // Set this to true to demonstrate the branch of code which will override unit price and list price by a fixed amount
    private static final Boolean DEMO_OVERRIDE_UNIT_PRICE_AND_LIST_PRICE_BY_FIXED_AMOUNT = false;

    /*
    Set this to the value you'd like to use for a fixed amount in price overrides. Take note that this variable
    does nothing until DEMO_OVERRIDE_UNIT_PRICE_AND_LIST_PRICE_BY_FIXED_AMOUNT is set to true
    */
    private static final Decimal DEMO_OVERRIDE_UNIT_PRICE_AND_LIST_PRICE_FIXED_AMOUNT = 10.00;

    // Set this to true to demonstrate the branch of code which will override currency based on a mapping
    private static final Boolean DEMO_OVERRIDE_CURRENCY_USING_CUSTOM_MAPPING = false;

    /*
    The first currency value (the key) will be overriden with the second value on each line (the value) when
    currency is overridden (DEMO_OVERRIDE_CURRENCY_USING_CUSTOM_MAPPING is set to true). When pricing is not
    found you should get a semi-appropriate dialect response for that currency. Take note that this variable
    does nothing until DEMO_OVERRIDE_CURRENCY_USING_CUSTOM_MAPPING is set to true and that the currency presented
    will be switched a few times on subsequent requests eventually landing back on USD for United States dollar.
    This is for educational purposes.
    */
    private static final Map<String, String> DEMO_OVERRIDE_CURRENCY_MAP_IN_REQUEST = new Map<String, String> {'USD' => 'EUR'};

        // When true logs the details of the cart
    //private static final Boolean LOG_CART_DETAIL_ACTIVE = true;

    // When true logs the details of the cart item(s)
    //private static final Boolean LOG_CART_ITEM_DETAIL_ACTIVE = true;

    // Supports the Capricorn Sample Product Pricing by Product Code or SKU - for demonstration purposes only
    private Map<String, PricingDataStructure> capricornSamplesStaticPricing;

    // Supports the Capricorn Sample Product Pricing by Product Id - for demonstration purposes only
    private Map<String, Id> capricornSamplesProductCodeToIdMap;
    private Map<Id, String> capricornSamplesProductIdToCodeMap;

    private WebStore webstore;
    private Id webStoreId = '0ZEbn000002qasfGAA';
    private Account effectiveAccount;
    private User userEntity;

    // TODO: Remove this?
    // You MUST change this to be your service or you must launch your own Third Party Service
    // and add the host in Setup | Security | Remote site settings.
    private static String externalPricingServiceHost = 'https://example.com';

    /* Base URI for on-platform REST calls - This is not something you'd normally do but it provides a working example without Heroku  */
    private  static final String ORG_BASE_URI = URL.getOrgDomainUrl().toExternalForm();

    public ServicePricingDefault()
    {
        super();

        // Set up static mapping for the Capricorn Sample products potentially leaving one out
        capricornSamplesStaticPricing = new Map<String, PricingDataStructure>();
        capricornSamplesStaticPricing.put('PS-EL', new PricingDataStructure('PS-EL', 549.99, 599.99));
        capricornSamplesStaticPricing.put('TR-COFMAC-001', new PricingDataStructure('TR-COFMAC-001', 449.99, 499.99));
        capricornSamplesStaticPricing.put('ID-PEM', new PricingDataStructure('ID-PEM', 249.99, 259.99));
        capricornSamplesStaticPricing.put('B-C-COFMAC-001', new PricingDataStructure('B-C-COFMAC-001', 484.99, 549.99));
        capricornSamplesStaticPricing.put('CR-DEC', new PricingDataStructure('CR-DEC', 15.99, 22.49));
        capricornSamplesStaticPricing.put('ESP-IOT-1', new PricingDataStructure('ESP-IOT-1', 649.99, 679.99));
        capricornSamplesStaticPricing.put('MRC-1', new PricingDataStructure('MRC-1', 17.99, 24.99));
        capricornSamplesStaticPricing.put('PS-INF', new PricingDataStructure('PS-INF', 429.99, 484.99));

        // Logic to leave a product out to demonstrate behavior when prices are missing
        if(!DEMO_MISSING_PRICE_ITEM)
        {
            capricornSamplesStaticPricing.put('DRW-1', new PricingDataStructure('DRW-1', 14.99, 19.99));
        }

        // Set up Effective Account based on user - This likely won't work with Account switching
        userEntity = [
            SELECT
                AccountId
            FROM
                User
            WHERE
                Id =: UserInfo.getUserId()
            WITH
                SECURITY_ENFORCED
        ];

        effectiveAccount = [
            SELECT
                Id, Name, OwnerId
            FROM
                Account
            WHERE
                Id = :userEntity.AccountId
            WITH
                SECURITY_ENFORCED
        ];

        // Get some product fields via Connect API so we can map by product Id to other fields like ProductCode or StockKeepingUnit (SKU)
        //List<WebStoreNetwork> webStoreNetworks = [SELECT Id, WebStoreId, Name FROM WebStoreNetwork WHERE Name = :WEBSTORE_NAME];
        //System.assertEquals(1, webStoreNetworks.size(), '### WebStore issue - Only 1 record should be returned. Hint: Check the WEBSTORE_NAME value.');
        //webStoreId = webStoreNetworks[0].WebStoreId;

        // Make the query to the Connect API to get some additional fields for our statically mapped capricorn examples
        // Signature: getProducts(String webStoreId, String effectiveAccountId, List<String> ids, List<String> skus, List<String> fields, Boolean excludeMedia)
        ConnectApi.ProductOverviewCollection productOverview = ConnectApi.CommerceCatalog.getProducts(
            //(String)webstore.Id,
            webStoreId,
            (String)effectiveAccount.Id,
            PRODUCT_OVERVIEW_QUERY_PRODUCT_ID_LIST,
            new List<String>(capricornSamplesStaticPricing.keySet()),
            PRODUCT_OVERVIEW_QUERY_FIELDS,
            PRODUCT_OVERVIEW_QUERY_EXCLUDE_MEDIA
        );

        // Create a map to easily translate the product Id to a product code
        capricornSamplesProductCodeToIdMap = new Map<String, Id>();
        capricornSamplesProductIdToCodeMap = new Map<Id, String>();

        for(ConnectApi.ProductOverview product : productOverview.products)
        {
            System.debug('### Mapping product Id: "' + product.Id + '" => ProductCode: "' + product.fields.get('ProductCode') + '"');
            capricornSamplesProductCodeToIdMap.put(product.fields.get('ProductCode'), product.Id);
            capricornSamplesProductIdToCodeMap.put(product.Id, product.fields.get('ProductCode'));
        }
    }

    /**
     * You can override the processPrice method in order to change behavior of the pricing of a single product.
     *  Fields that can be overriden are:
     *       Header level: currency and error.
     *       Item level:  unit or negotiated price, list price, pricebook entry Id, product Id and product selling model Id.
     */
    public override commercestorepricing.PricingResponse processPrice(commercestorepricing.PricingRequest request)
    {
        System.debug('### processPrice in ServicePricingDefault started...');

        // Extract products in request
        Set<String> products = new Set<String>();

        commercestorepricing.PricingRequestItemCollection items = request.getPricingRequestItems();

        for(Integer i = 0; i < items.size(); i++)
        {
            commercestorepricing.PricingRequestItem item = items.get(i);
            products.add(item.getProductId());
        }

        // Get prices from an external service

        // OLD CODE:

        Map<String, PricingDataStructure> pricingDataReturned;

        if(USE_EXTERNAL_SERVICE)
        {
            pricingDataReturned = getPricesFromExternalService(products);
        }
        else
        {
            //pricingDataReturned = getPriceFromStaticResponse(products);
            pricingDataReturned = getPricingFromStaticResponse(products);
        }

        // NEW CODE:
        /*
        Map<String, PricingDataStructure> pricingDataReturned = (USE_EXTERNAL_SERVICE)
            ? getPricingFromExternalService(products) // OLD METHOD for reference: getPricesFromExternalService(skus)
            : getPricingFromStaticResponse(products); // OLD METHOD for reference: getPriceFromStaticResponse(skus)
        */

        // Create response using either the static data or the service response data in the current user's default currency
        commercestorepricing.PricingResponse response = new commercestorepricing.PricingResponse(UserInfo.getDefaultCurrency());

        for (Integer i = 0; i < items.size(); i++)
        {
            String productId = items.get(i).getProductId();
            System.debug('### processPrice for productId: "' + productId  + '" in ServicePricingDefault started...');

            if (pricingDataReturned == null || pricingDataReturned.get(productId) == null)
            {
                // Unsuccessful response item
                System.debug('### processPrice for productId: "' + productId  + '" => Unsuccessful response item.');

                commercestorepricing.PricingResponseItem responseItem = new commercestorepricing.PricingResponseItem(
                    productId,
                    null,
                    null,
                    null,
                    null
                );

                responseItem.setError(
                    this.getNoPricesFoundForThisItemForCurrency(response.getCurrencyIsoCode()),
                    this.getNoPricesFoundForThisItemForCurrency('EUR')
                );

                response.addPricingResponseItem(responseItem);
            }
            else
            {
                // Successful response item
                System.debug('### processPrice for productId: "' + productId  + '" => Successful response item.');
                PricingDataStructure pricingDataStructure = pricingDataReturned.get(productId);

                commercestorepricing.PricingResponseItem responseItem = new commercestorepricing.PricingResponseItem(
                    productId,
                    null,
                    null,
                    pricingDataStructure.getListPrice(),
                    pricingDataStructure.getUnitPrice()
                );

                response.addPricingResponseItem(responseItem);
            }
        }

        // Override currency using a custom mapping with each request ultimately repeating if the map is set to do it.
        if(DEMO_OVERRIDE_CURRENCY_USING_CUSTOM_MAPPING)
        {
            System.debug('### processPrice in ServicePricingDefault DEMO_OVERRIDE_CURRENCY_USING_CUSTOM_MAPPING is true');
            String responseCurrency = response.getCurrencyIsoCode();

            if (DEMO_OVERRIDE_CURRENCY_MAP_IN_REQUEST.containsKey(responseCurrency))
            {
                String newCurrency = DEMO_OVERRIDE_CURRENCY_MAP_IN_REQUEST.get(responseCurrency);
                response.setCurrencyIsoCode(newCurrency);
            }
        }

        /*
        Override unit price and list price by increasing them by a fixed amount (for successful responses)
        if the class is set up to do that per DEMO_OVERRIDE_UNIT_PRICE_AND_LIST_PRICE_BY_FIXED_AMOUNT = true
        */
        if(DEMO_OVERRIDE_UNIT_PRICE_AND_LIST_PRICE_BY_FIXED_AMOUNT)
        {
            System.debug('### processPrice in ServicePricingDefault DEMO_OVERRIDE_UNIT_PRICE_AND_LIST_PRICE_BY_FIXED_AMOUNT is true');
            commercestorepricing.PricingResponseItemCollection itemCollection = response.getPricingResponseItems();

            for (Integer i = 0; i < itemCollection.size(); i++)
            {
                commercestorepricing.PricingResponseItem item = itemCollection.get(i);

                if (item.isSuccess())
                {
                    item.setListPrice(item.getListPrice() + DEMO_OVERRIDE_UNIT_PRICE_AND_LIST_PRICE_FIXED_AMOUNT);
                    item.setNegotiatedPrice(item.getNegotiatedPrice() + DEMO_OVERRIDE_UNIT_PRICE_AND_LIST_PRICE_FIXED_AMOUNT);
                }
            }
        }

        System.debug('### processPrice in ServicePricingDefault complete.');
        return response;
    }

    /**
     * You can override the processTransactionalPrice method in order to change behavior of the pricing
     * of multiple products within a transaction.
     * Fields that can be overriden are: Header level - currency, error, total list price, total product
     * amount, total adjustment amount and total amount. Item level - line id, product id, unit price,
     * list price, unit pricebook entry id, unit adjustment amount, total line amount, total adjustment
     * amount, total price, and total list price.
     */
    public override commercestorepricing.TransactionalPricingResponse processTransactionalPrice(commercestorepricing.TransactionalPricingRequest request2)
    {
        // Customers can easily overide the request fields. Here we increase the quantity of the first item by 1.
        commercestorepricing.TransactionalPricingRequestItem reqItem = request2.getTxnPricingRequestItems().get(0);
        reqItem.setQuantity(reqItem.getQuantity() + 1);

        // Call the default internal pricing implemenation with either original request or modified request
        commercestorepricing.TransactionalPricingResponse txnResponse = super.processTransactionalPrice(request2);

        // Override all string fields by appending a prefix to them in case customers use a different
        // naming convention than salesforce IDs Also increase the adjustments by a fixed amount in case
        // customer is giving a promotion for some time
        String prefix = 'XYZ_';
        Decimal fixedAdjustmentAmount = 5;
        commercestorepricing.TxnPricingResponseItemCollection txnItemCollection = txnResponse.getTxnPricingResponseItems();

        for (Integer j = 0; j < txnItemCollection.size(); j++)
        {
            commercestorepricing.TransactionalPricingResponseItem txnItem = txnItemCollection.get(j);
            txnItem.setLineId(appendField(prefix, txnItem.getLineId()));
            txnItem.setProductId(appendField(prefix, txnItem.getProductId()));
            txnItem.setUnitPricePriceBookEntryId(appendField(prefix, txnItem.getUnitPricePriceBookEntryId()));
            txnItem.setTotalAdjustmentAmount(txnItem.getTotalAdjustmentAmount() - fixedAdjustmentAmount);
            txnItem.setTotalPrice(txnItem.getTotalPrice() - fixedAdjustmentAmount);
        }

        // Update the total adjustment and amount at header level accordingly
        txnResponse.setTotalAdjustmentAmount(txnResponse.getTotalAdjustmentAmount() - (fixedAdjustmentAmount * txnItemCollection.size()));
        txnResponse.setTotalAmount(txnResponse.getTotalProductAmount() + txnResponse.getTotalAdjustmentAmount());

        if (!txnItemCollection.isEmpty())
        {
            // Override success/failure of a product easily by adding an error message to the product. Here
            // we are failing the first product in the response.
            String customErrorMessage = 'We no longer sell this particular product.';
            String localizedErrorMessage = 'Wir verkaufen dieses spezielle Produkt nicht mehr.';
            txnItemCollection.get(0).setError(customErrorMessage, localizedErrorMessage);
        }

        return txnResponse;
    }

    // TODO: Remove this?
    private String getNoPricesFoundForThisItemForCurrency(String currencyIsoCode)
    {
        Map<String, String> responseDialect = new Map<String, String>
        {
            'USD' => 'No prices available for this product.',
            'EUR' => 'Für dieses Produkt sind keine Preise verfügbar.',
            'AUD' => 'G\'Day Mate! The prices for this product seem to be gone walkabout.'
        };

        return responseDialect.get(currencyIsoCode);
    }

    /**
    * Returns a static pricing data map for all products defined in the capricornSamplesStaticPricing variable, falling back to PRICE_NOT_FOUND_DEFAULT_VALUE
    * if a price can't be located. This is done for educational purposes.
    */
    private Map<String, PricingDataStructure> getPricingFromStaticResponse(Set<String> productIdList)
    {
        System.debug('### productIdList has ' + productIdList.size() + ' items.');

        Map<String, PricingDataStructure> pricingDataResult = new Map<String, PricingDataStructure>();

        for(String productId: productIdList)
        {
            System.debug('### productId: "' + productId + '"');
            String productCode = capricornSamplesProductIdToCodeMap.get(productId);
            System.debug('### productCode: "' + productCode + '"');
            PricingDataStructure pricingData = capricornSamplesStaticPricing.get(productCode);
            System.debug('### pricingData: "' + JSON.serializePretty(pricingData) + '"');

            // This code is for demonstrative purposes
            if(pricingData == null)
            {
                System.debug('### Pricing data not found in getPricingFromStaticResponse with productId value: "' + productId + '". Resorting to default value: "' + PRICE_NOT_FOUND_DEFAULT_VALUE + '"');
                pricingData = new PricingDataStructure(productId, PRICE_NOT_FOUND_DEFAULT_VALUE, PRICE_NOT_FOUND_DEFAULT_VALUE);
            }

            // Use the capricornSamplesStaticPricing but map it to the product Id
            pricingDataResult.put(productId, pricingData);
        }

        System.debug('### getPricingFromStaticResponse in CartCalcPricingDefault complete.');
        return pricingDataResult;
    }

    /** This is akin to the method of the same name in the CartCalcPricingDefault class but is using JSON formatting */
    /*
    private Map<String, PricingDataStructure> getPriceFromStaticResponse(Set<String> productIds)
    {
        String responseJson = '{';

        for(String productID : productIds)
        {
            Double price = 10.00;
            Double listPrice = 10.00;
            Double unitPrice = 10.00;
            responseJson = responseJson + '"'+productID+'"';
            responseJson = responseJson + ':';
            responseJson = responseJson + '{';
            responseJson = responseJson + '"listPrice"';
            responseJson = responseJson + ':';
            responseJson = responseJson + price;
            responseJson = responseJson + ',';
            responseJson = responseJson + '"unitPrice"';
            responseJson = responseJson + ':';
            responseJson = responseJson + price;
            responseJson = responseJson + '}';
            responseJson = responseJson + ',';
        }

        responseJson = responseJson.removeEnd(',') + '}';
        Map<String, Object> resultsFromExternalServiceBySKU =  (Map<String, Object>) JSON.deserializeUntyped(responseJson);
        return populatePrice(resultsFromExternalServiceBySKU);
    }
    */

    private Map<String, PricingDataStructure> populatePrice(Map<String, Object> resultsFromExternalServiceBySKU)
    {
        Map<String, PricingDataStructure> pricingDataFromExternalServiceBySKU = new Map<String, PricingDataStructure>();

        for (String sku : resultsFromExternalServiceBySKU.keySet())
        {
            Map<String, Object> pricesFromExternalService = (Map<String, Object>) resultsFromExternalServiceBySKU.get(sku);

            pricingDataFromExternalServiceBySKU.put(
                sku,
                new PricingDataStructure(
                    sku,
                    (Decimal) pricesFromExternalService.get('listPrice'),
                    (Decimal) pricesFromExternalService.get('unitPrice')
                )
            );
        }

        return pricingDataFromExternalServiceBySKU;
    }

    /**
    * @description This doesn't actually make an HTTP call, but it mocks the JSON response of an external Pricing
    * Service.
    *
    * @param skus A set of SKUs to get pricing data
    * @return Map containing PricingData for each SKU passed into this method
    */
    private Map<String, PricingDataStructure> getPricingFromExternalService(Set<String> skus)
    {
        System.debug('### getPricingFromExternalService in CartCalcPricingDefault started...');

        Http http = new Http();
        HttpRequest request = new HttpRequest();
        Set<String> encodedSkus = new Set<String>();

        for (String sku : skus)
        {
            encodedSkus.add(EncodingUtil.urlEncode(sku, 'UTF-8'));
        }

        // To access the service below you may need to add endpoint = https://example.com in Setup | Security | Remote site settings.
        request.setEndpoint('https://example.com/get-sales-prices?skus=' + JSON.serialize(encodedSkus));
        request.setMethod('GET');
        HttpResponse r = http.send(request);

        if (r.getStatusCode() != 200)
        {
            // return null in case of not successful response from 3rd party service
            System.debug('### Did not receive pricing data. Call to external service was not successful.');
            return null;
        }

        System.debug('### getPricingFromExternalService in CartCalcPricingDefault complete.');
        return (Map<String, PricingDataStructure>) JSON.deserialize(r.getBody(), Map<String, PricingDataStructure>.class);
    }


    // TODO: Make this use the REST API for WebStore Pricing
    // This is simply a mocking of an external service call. Customers will have to change this logic to
    // call their respective services.
    private Map<String, PricingDataStructure> getPricesFromExternalService(Set<String> productIds)
    {
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        Integer SuccessfulHttpRequest = 200;

        // Encode the product IDs to avoid any invalid characters in the URL.
        Set<String> encodedProductIDs = new Set<String>();

        for (String productID : productIds)
        {
            encodedProductIDs.add(EncodingUtil.urlEncode(productID, 'UTF-8'));
        }

        // To access the service below, you may need to add endpoint =
        // httpHost in Setup > Security > Remote site settings.
        String requestURL =
        externalPricingServiceHost+'/get-prices?skus=' +  JSON.serialize(encodedProductIDs);
        request.setEndpoint(requestURL);
        request.setMethod('GET');
        HttpResponse response = http.send(request);

        // If the request is successful, parse the JSON response; The response includes the negotiated
        // as well as list price for each SKU. It looks something like this: response =
        // {"ProductID1":{"listPrice":10,"unitPrice":5}};
        if (response.getStatusCode() == SuccessfulHttpRequest)
        {
            Map<String, Object> resultsFromExternalServiceBySKU = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            return populatePrice(resultsFromExternalServiceBySKU);
        }
        else
        {
            throw new CalloutException('There was a problem with the request. Error: ' + response.getStatusCode());
        }
    }

    // TODO: Why is this code even here? Do we really need to write a method for the '+' operator
    @TestVisible
    private String appendField(String prefix, String field)
    {
        // Customers can easily change the string IDs returned by Salesforce Internal Pricing API
        return prefix + field;
    }

    /**
    * Structure to store pricing data retrieved from an external service or static example.
    */
    class PricingDataStructure
    {
        private String productId;
        private Decimal listPrice;
        private Decimal unitPrice;

        public PricingDataStructure()
        {
            this.productId = '';
            this.listPrice = ServicePricingDefault.ZERO_DECIMAL;
            this.unitPrice = ServicePricingDefault.ZERO_DECIMAL;
        }

        public PricingDataStructure(String productId, Decimal listPrice, Decimal unitPrice)
        {
            this.productId = productId;
            this.listPrice = listPrice;
            this.unitPrice = unitPrice;
        }

        public String getProductId()
        {
            return this.productId;
        }

        public Decimal getListPrice()
        {
            return this.listPrice;
        }

        public Decimal getUnitPrice()
        {
            return this.unitPrice;
        }
    }
}