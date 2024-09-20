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
 *                      1. Screaming constants (static final variables) for legibility / consistency / removing magic numbers
 *                      2. Many. many additional System.debug entries for tracing purposes
 *                      3. Reformatting and alignment for legibility
 *                      4. Superfluous constructor removed in favor of a constant DEMO_USE_EXTERNAL_SERVICE
 *                      5. Added PRICE_NOT_FOUND_DEFAULT_VALUE for fallback when price isn't found
 *                      6. Introduced the Capricorn sample product price map for local calls (when DEMO_USE_EXTERNAL_SERVICE is false)
 *                      7. Added clear "DEMO_" Booleans and supporting constants examples like pricing and currency overrides can be isolated
 *                      8. WIP - Added a REST call for WebStore pricing data to drive the point home along with ORG_BASE_URI and
 *                      API_VERSION to support flexibility and reuse.
 *                      9. Added many more comments
 *                      10. Refactoring to remove complexity
 * @author            : Tom Zarr
 * @group             : Salesforce Commerce Partner Delivery Success (2024)
 * @last modified on  : 09-20-2024
 * @last modified by  : Tom Zarr
**/

/**
 *  This must implement the commercestorepricing.ServicePricingDefault class in order to be processed by the
 *  pricing flow. Services like this are mostly for estimated or custom pricing on the product list and detail
 *  pages. For custom cart calculations see the example class CartCalcPricingDefault.
 */
public class ServicePricingDefault extends commercestorepricing.PricingService
{
    // ======== Start Demonstration and Behavioral Settings ======== //

    /*  For demonstration purposes only: Set this to true to see a networked call take place against your org,
    false to pull static data from the Capricorn sample products */
    private static final Boolean DEMO_USE_EXTERNAL_SERVICE = false;

    /*  For demonstration purposes only: Set this to true to leave the last Capricorn sample out of the mapping
    to demonstrate how a missing pricing is handled. */
    private static final Boolean DEMO_MISSING_PRICE_ITEM = true;

    /*  For demonstration purposes only: Supports a default value for pricing when the pricing is not found */
    private static final Decimal PRICE_NOT_FOUND_DEFAULT_VALUE = 50.00;

    /*  For demonstration purposes only: Set this to true to demonstrate the branch of code which will override
    unit price and list price by a fixed amount */
    private static final Boolean DEMO_OVERRIDE_UNIT_PRICE_AND_LIST_PRICE_BY_FIXED_AMOUNT = false;

    /*  For demonstration purposes only: Set this to the value you'd like to use for a fixed amount in price
    overrides. This variable does nothing until DEMO_OVERRIDE_UNIT_PRICE_AND_LIST_PRICE_BY_FIXED_AMOUNT is set to true */
    private static final Decimal DEMO_OVERRIDE_UNIT_PRICE_AND_LIST_PRICE_FIXED_AMOUNT = 10.00;

    /*  For demonstration purposes only: Set this to true to demonstrate the branch of code which will override
    currency based on a mapping */
    private static final Boolean DEMO_OVERRIDE_CURRENCY_USING_CUSTOM_MAPPING = false;

    /*  For demonstration purposes only: The first currency value (i.e. the key in the map) will be overriden with the
    second value (i.e. the map entry's value) when DEMO_OVERRIDE_CURRENCY_USING_CUSTOM_MAPPING is set to true. */
    private static final Map<String, String> DEMO_OVERRIDE_CURRENCY_MAP_IN_REQUEST = new Map<String, String> {'USD' => 'EUR'};

    // ======== End Behavioral and Demonstration Settings ======== //

    // ======== Start API Settings ======== //

    /*  The version of the API to use for local REST oAPI calls in the format: "v##" - mostly for demonstration purposes */
    public static final String API_VERSION = 'v61.0';
    /*  The Base URI for on-platform REST calls - used for fill-in REST API calls in implementation and demostrating a
    working remote call even if that means pointing back to the org to get pricing data */
    public static final String ORG_BASE_URI = URL.getOrgDomainUrl().toExternalForm();
    /*  The "API Home" or calculated URL for REST calls of various flavors. This is meant to have a suffix appended to it.
        Here are a few examples:
            /query/?q=SELECT+Id,+Name+FROM+WebStore+WHERE+Name+=+'{{webStoreName}}'
            /commerce/oci/availability/availability-records/actions/get-availability
    */
    public static final String API_HOST = ORG_BASE_URI + '/services/data/' + API_VERSION + '/';
    /* HTTP POST Method */
    public static final String METHOD_POST = 'POST';
    /* HTTP GET Method */
    public static final String METHOD_GET = 'GET';
    /* Header key to set the Content Type for REST + JSON */
    public static final String CONTENT_TYPE_HEADER_KEY = 'Content-Type';
    /* Header value to set the Content Type for REST + JSON */
    public static final String CONTENT_TYPE_HEADER_VALUE = 'application/json;  charset=utf-8';
    /* Lowest possible value for a valid REST call */
    public static final Integer HTTP_STATUS_OK_LOW = 200;
    /* Highest possible value for a valid REST call  */
    public static final Integer HTTP_STATUS_OK_HIGH = 204;

    // ======== End API Settings ======== //

    // ======== Start Product Overview Query Settings (for Connect API) ======== //

    // Query parameters used with the Connect API for product details in the constructor
    private static final Id[] PRODUCT_OVERVIEW_QUERY_PRODUCT_ID_LIST = new Id[]{};
    private static final String[] PRODUCT_OVERVIEW_QUERY_FIELDS = new String[] {'Id','ProductCode','StockKeepingUnit'};
    private static final Boolean PRODUCT_OVERVIEW_QUERY_EXCLUDE_MEDIA = true;

    // ======== End Product Overview Query Settings (for Connect API) ======== //

    /*  Avoid magic strings */
    private static final Decimal ZERO_DECIMAL = 0.0;
    /*  For demonstration purposes only: Supports the Capricorn Sample Product Pricing by Product Code or SKU */
    private Map<String, PricingDataStructure> capricornSamplesStaticPricing;
    /*  For demonstration purposes only: Supports the Capricorn Sample Product Pricing by mapping Product Code to Product Id */
    private Map<String, Id> capricornSamplesProductCodeToIdMap;
    /* For demonstration purposes only: Supports the Capricorn Sample Product Pricing by mapping Product Id to Product Code */
    private Map<Id, String> capricornSamplesProductIdToCodeMap;

    private WebCart webCart;
    private Id webStoreId;
    private Id effectiveAccountId;
    private User userEntity;

    public ServicePricingDefault()
    {
        super();

        /*  Set up static mapping for the Capricorn Sample products potentially leaving one out depending on
        how DEMO_MISSING_PRICE_ITEM is set */
        capricornSamplesStaticPricing = new Map<String, PricingDataStructure>();
        capricornSamplesStaticPricing.put('PS-EL', new PricingDataStructure('PS-EL', 549.99, 599.99));
        capricornSamplesStaticPricing.put('TR-COFMAC-001', new PricingDataStructure('TR-COFMAC-001', 449.99, 499.99));
        capricornSamplesStaticPricing.put('ID-PEM', new PricingDataStructure('ID-PEM', 249.99, 259.99));
        capricornSamplesStaticPricing.put('B-C-COFMAC-001', new PricingDataStructure('B-C-COFMAC-001', 484.99, 549.99));
        capricornSamplesStaticPricing.put('CR-DEC', new PricingDataStructure('CR-DEC', 15.99, 22.49));
        capricornSamplesStaticPricing.put('ESP-IOT-1', new PricingDataStructure('ESP-IOT-1', 649.99, 679.99));
        capricornSamplesStaticPricing.put('MRC-1', new PricingDataStructure('MRC-1', 17.99, 24.99));
        capricornSamplesStaticPricing.put('PS-INF', new PricingDataStructure('PS-INF', 429.99, 484.99));

        // The logic to leave a product out to demonstrate error handling or behaviors when prices are missing
        if(!DEMO_MISSING_PRICE_ITEM)
        {
            capricornSamplesStaticPricing.put('DRW-1', new PricingDataStructure('DRW-1', 14.99, 19.99));
        }

        /*  Get the UserEntity for the current user and set up Effective Account based on user. Note: This
        likely won't work with Account switching and may not work qith guest access. */
        userEntity = [
            SELECT
                Id,
                AccountId
            FROM
                User
            WHERE
                Id =: UserInfo.getUserId()
            WITH
                SECURITY_ENFORCED
        ];

        effectiveAccountId = userEntity.AccountId;

        // Get the newest WebCart for the current user via the REST "Query" API and pull the WebStoreId from it
        String webCartSoql = 'SELECT Id, WebStoreId, OwnerId, Name FROM WebCart WHERE OwnerId = \'' + userEntity.Id + '\' ORDER BY LastModifiedDate desc LIMIT 1';
        String webCartSoqlEncoded = EncodingUtil.urlEncode(webCartSoql, 'UTF-8');
        String webCartJson = this.handleLocalHttpGetRequest('query/?q=' + webCartSoqlEncoded);
        Map<String, Object> jsonMap = (Map<String, Object>)JSON.deserializeUntyped(webCartJson);
        // System.assert(jsonMap.get('totalSize') == 1, 'There should be only 1 record returned for Webstore');
        // System.assert(jsonMap.get('done') == true, 'The fetch should be complete');
        List<Object> records = (List<Object>)jsonMap.get('records');

        /*  Not all the variables below are used but they were left in for educational purposes because working
        with the JSON parser can be tricky and slow-going. We really just want to assign webStoreId and move on.
        We already asserted that there's only 1 record above so the single iteration for loop is again for better
        visualization of how to work with JSON results for those Administrators wanting to learn more Apex. */

        for(Object record : records)
        {
            Map<String, Object> recordDetail = (Map<String, Object>)record;
            Id id = (Id)recordDetail.get('Id');
            webStoreId = (Id)recordDetail.get('WebStoreId');
            Id ownerId = (Id)recordDetail.get('OwnerId');
            String name = (String)recordDetail.get('Name');
        }

        // System.assert(String.isNotEmpty(webStoreId) && String.isNotBlank((String)webStoreId), 'webStoreId should not be null or blank');

        /*  Make a query to the Connect API to get some additional fields for our statically mapped capricorn examples
        since this class needs Product Ids and those are unique from org to org (shoudl be fetched dynamically) */
        ConnectApi.ProductOverviewCollection productOverview = ConnectApi.CommerceCatalog.getProducts(
            webStoreId,
            effectiveAccountId,
            PRODUCT_OVERVIEW_QUERY_PRODUCT_ID_LIST,
            new List<String>(capricornSamplesStaticPricing.keySet()),
            PRODUCT_OVERVIEW_QUERY_FIELDS,
            PRODUCT_OVERVIEW_QUERY_EXCLUDE_MEDIA
        );

        // TODO: Fix this as it's wonky! - Create a map to easily translate the product Id to a product code
        capricornSamplesProductCodeToIdMap = new Map<String, Id>();
        capricornSamplesProductIdToCodeMap = new Map<Id, String>();

        for(ConnectApi.ProductOverview product : productOverview.products)
        {
            System.debug('### Mapping product Id: "' + product.Id + '" => ProductCode: "' + product.fields.get('ProductCode') + '"');
            capricornSamplesProductCodeToIdMap.put(product.fields.get('ProductCode'), product.Id);
            capricornSamplesProductIdToCodeMap.put(product.Id, product.fields.get('ProductCode'));
        }
    }

    /** Helper method for handling generic HTTP GET requests and getting the raw response within the org.
     *  I also have a Postman collection here if you'd like to learn more about the APIs:
     *  https://github.com/tzarrsf/b2b-commerce-postman-setup-with-example-files*/
    private String handleLocalHttpGetRequest(String endpoint)
    {
        System.debug('### handleLocalHttpGetRequest called with endpoint: \'' + endpoint + '\'');
        String calloutUrl = API_HOST + endpoint;

        System.debug('### handleLocalHttpGetRequest calling with calloutUrl: \'' + calloutUrl + '\'');
        String response;
        HttpRequest httpRequest = new HttpRequest();
        httpRequest.setMethod(METHOD_GET);
        httpRequest.setHeader(CONTENT_TYPE_HEADER_KEY, CONTENT_TYPE_HEADER_VALUE);
        String sessionId = UserInfo.getSessionId();
        // This is fine as we're not really leaving the org - ignore any IDE warnings about Named Credentials
        httpRequest.setHeader('Authorization', 'Bearer ' + sessionId);
        httpRequest.setEndpoint(calloutUrl);

        try
        {
            Http http = new Http();
            HttpResponse httpResponse = http.send(httpRequest);
            Integer statusCode = httpResponse.getStatusCode();

            if (statusCode >= HTTP_STATUS_OK_LOW && statusCode <= HTTP_STATUS_OK_HIGH)
            {
                    response = httpResponse.getBody();
            }
            else
            {
                    throw new CalloutException(httpResponse.getBody());
            }
        }
        catch (Exception e)
        {
            System.debug('### handleLocalHttpGetRequest caught an exception with endpoint: "' + endpoint + '" and calloutUrl: "' + calloutUrl + '" User: "' + UserInfo.getUserName()  + '"');
            String msg = e.getMessage();
            System.debug(msg);
            return msg;
        }

        System.debug(' ### handleLocalHttpGetRequest called with endpoint: "' + endpoint  + '" and calloutUrl: "' + calloutUrl + '" returning json:\r\n"' + response + '"\r\n');
        return response;
    }

    /** Helper method for handling generic HTTP POST requests and getting the raw response within the org.
     *  I also have a Postman collection here if you'd like to learn more about the APIs:
     *  https://github.com/tzarrsf/b2b-commerce-postman-setup-with-example-files*/
    private String handleLocalHttpPostRequest(String endpoint, String body)
    {
        System.debug('### handleLocalHttpPostRequest called with endpoint: \'' + endpoint + '\' and body: "' + body + '"...');
        String calloutUrl = API_HOST + endpoint;

        System.debug('### handleLocalHttpPostRequest attempting call with calloutUrl: \'' + calloutUrl + '\'');

        String response;
        HttpRequest httpRequest = new HttpRequest();
        httpRequest.setMethod(METHOD_POST);
        httpRequest.setHeader(CONTENT_TYPE_HEADER_KEY, CONTENT_TYPE_HEADER_VALUE);
        // This is fine as we're not really leaving the org - ignore any IDE warnings about Named Credentials
        httpRequest.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        httpRequest.setEndpoint(calloutUrl);
        httpRequest.setBody(body);

        try
        {
            Http http = new Http();
            HttpResponse httpResponse = http.send(httpRequest);
            Integer statusCode = httpResponse.getStatusCode();

            if (statusCode >= HTTP_STATUS_OK_LOW && statusCode <= HTTP_STATUS_OK_HIGH)
            {
                response = httpResponse.getBody();
            }
            else
            {
                throw new CalloutException(httpResponse.getBody());
            }
        }
        catch (Exception e)
        {
            System.debug('### handleLocalHttpPostRequest caught an exception with endpoint: "' + endpoint + '" and calloutUrl: "' + calloutUrl + '" User: "' + UserInfo.getUserName()  + '"');
            String msg = e.getMessage();
            System.debug(msg);
            return msg;
        }

        System.debug(' ### handleLocalHttpPostRequest called with endpoint: "' + endpoint  + '" and calloutUrl: "' + calloutUrl + '" returning json:\r\n"' + response + '"\r\n');
        return response;
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

        // Get prices from an external service or static mapping based on DEMO_USE_EXTERNAL_SERVICE
        Map<String, PricingDataStructure> pricingDataReturned = (DEMO_USE_EXTERNAL_SERVICE)
            ? getPricingFromExternalService(products) // OLD METHOD for reference: getPricesFromExternalService(skus)
            : getPricingFromStaticResponse(products);

        // Create a pricing response the current user's default currency
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

    /*  Uses the org's WebStore pricing service over the wire via REST API to drive the point home. This is something
     *  you wouldn't and shouldn't do in the real world until all other options have been exhausted first, but this
     *  functions as a working model so you can see how a real pricing request might work without depending on something
     *  like a Heroku service. I also have a Postman collection here if you'd like to learn more about these kind of APIs:
     *  https://github.com/tzarrsf/b2b-commerce-postman-setup-with-example-files
     */
    private Map<String, PricingDataStructure> getPricingFromExternalService(Set<String> productIdList)
    {
        /***
         *  Documentation for the endpoint:
         *  https://developer.salesforce.com/docs/atlas.en-us.chatterapi.meta/chatterapi/connect_resources_commerce_webstore_pricing_products.htm
         *  This is the only format I could get working with both a Pricing calculator and a Pricing Service mapped:
         *  /services/data/v61.0/commerce/webstores/0ZEbn000002qasfGAA/pricing/products?&effectiveAccountId=001bn000017bBQ6AAM
         */
        System.debug('### getPricingFromExternalService in CartCalcPricingDefault started...');
        String productIdsJoinedByComma = String.join(new List<String>(productIdList), ',');
        String pricingEndpoint = 'commerce/webstores/' + this.webStoreId;
        pricingEndpoint += '/pricing/products?';
        pricingEndpoint += 'effectiveAccountId=' + this.effectiveAccountId;

        System.debug('### pricingEndpoint calculated as: "' + pricingEndpoint + '"');

        /***
         *  This is the format of what needs to be sent over in the body of the post for a pricing call. While we could
         *  hack it in with strings, it's not wonderful example code so we'll build off some structures so those learning
         *  to code or improve their Apex code skills can see the serialization operations and thinking in action.
         */
        String exampleJson = '{';
        exampleJson += '"   pricingLineItems": [';
        exampleJson += '        {';
        exampleJson += '            "productId":"01txx000000000V"';
        exampleJson += '        },';
        exampleJson += '        {';
        exampleJson += '            "productId":"01txx000000000W"';
        exampleJson += '        },';
        exampleJson += '        {';
        exampleJson += '            "productId":"01txx000000000A"';
        exampleJson += '        }';
        exampleJson += '    ]';
        exampleJson += '}';

        // This is a practice of using 'proper' Apex objects on the SF side to serialize to JSON and then send on the wire
        List<PricingLineItem> pricingLineItemList = new List<PricingLineItem>();

        for(String productId : productIdList)
        {
            pricingLineItemList.add(new PricingLineItem(productId));
        }

        PricingRequestBody pricingRequestBody = new PricingRequestBody(pricingLineItemList);
        String body = JSON.serialize(pricingRequestBody);
        System.debug('### body JSON: "' + body + '"');

        // Send it over
        String pricingJson = this.handleLocalHttpPostRequest(pricingEndpoint, body);
        System.debug('### pricingJson from service: "' + pricingJson + '"');

        // TODO: Wrap this up and confirm comments are correct!
        // The response may include the negotiated as well as list price for each SKU. It looks something like this:
        // {"ProductID1":{"listPrice":10,"unitPrice":5}};

        System.debug('### getPricingFromExternalService in CartCalcPricingDefault complete.');
        return (Map<String, PricingDataStructure>) JSON.deserialize(pricingJson, Map<String, PricingDataStructure>.class);
    }

    // TODO: Go back to where this is demonstrated and break out the behavior with a DEMO_ variable
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

    /**
     *  Structure for a line item in a POST request for inventory levels
     */
    class PricingLineItem
    {
        private String productId;

        PricingLineItem(String productId)
        {
            this.productId = productId;
        }
    }

    /**
     *  Structure for a proper serialization to JSON for a POST request when requesting inventory levels. Could
     *  we have hacked this in with string concatenation, yes, but it's not great form and this is example code.
     */
    class PricingRequestBody
    {
        private List<PricingLineItem> pricingLineItems;

        PricingRequestBody(List<PricingLineItem> pricingLineItems)
        {
            this.pricingLineItems = pricingLineItems;
        }
    }
}