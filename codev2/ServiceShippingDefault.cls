/**
 * @description       : This code extends the CartExtension.ShippingCartCalculator base class in order to calculate shipping charges in
 *                      conjunction with the cart orchestrator. This class is current with the Spring '24 release and a part of the
 *                      Salesforce Partner Learning Camp course "B2B Commerce: Developer Essentials" and specific to these activities:
 *                          1. Implement a Shipping Provider
 *                          2. Configure a Cart Orchestrator
 *
 *                      Main documentation source: https://developer.salesforce.com/docs/commerce/salesforce-commerce/guide/ShippingCartCalculator.html
 *
 * @author            : Tom Zarr
 * @group             : Salesforce Commerce Partner Delivery Success (2024)
 * @last modified on  : 11-20-2024
 * @last modified by  : Tom Zarr
**/
public class ServiceShippingDefault extends CartExtension.ShippingCartCalculator
{
    // You MUST change this to be your service or you must launch your own Third Party Service
    // and add the host in Setup | Security | Remote site settings.
    private static final String EXTERNAL_SHIPPING_SERVICE_HOST = 'https://example.com';

    // You MUST change this to be your service or your URL
    private static final String EXTERNAL_SHIPPING_URL = EXTERNAL_SHIPPING_SERVICE_HOST + '/calculate-shipping-rates';

    // You MUST change the useExternalService to True if you want to use the Third Party Service.
    private static Boolean USE_EXTERNAL_SERVICE = false;

    /**
     * The  moniker for the shipping Shipping Product Placeholder represented in ProductCode. In a real implementation you'd typically have
     * one product, but multiple order delivery groups that are different. Then the price is whatever is calculated in checkout (price from
     * the product isn't a factor).
     */
    public static final String SHIPPING_PRODUCT_MONIKER = 'Shipping Product Placeholder';

    /**
     * The product for shipping represented in ProductCode.
     */
    public static final String SHIPPING_PRODUCT_CODE = SHIPPING_PRODUCT_MONIKER;

    /**
     * The product for shipping represented in the SKU.
     */
    public static final String SHIPPING_PRODUCT_STOCK_KEEPING_UNIT = SHIPPING_PRODUCT_MONIKER;

    /**
     * The product for shipping represented in the Name.
     */
    public static final String SHIPPING_PRODUCT_NAME = SHIPPING_PRODUCT_MONIKER;

    // TODO: Refactor this to use the BaseRestUtility or one of its children - the naming also isn't fantastic here
    private static final Integer SUCCESSFUL_HTTP_REQUEST = 200;

    public virtual override void calculate(CartExtension.CartCalculateCalculatorRequest request)
    {
        try
        {
            System.debug('## INVOCATION: ServiceShippingDefault.calculate called.');

            CartExtension.Cart cart = request.getCart();
            /***
             * Clean up CartValidationOutputList based on SHIPPING. When new shipping calculator request comes, we need to clean up
             * previous CVOs as they have been previously handled by the Cart Calculate API.
             */
            CartExtension.CartValidationOutputList cartValidationOutputCollection = cart.getCartValidationOutputs();
            Iterator<CartExtension.CartValidationOutput> cartValidationOutputCollectionIterator = cartValidationOutputCollection.iterator();

            while (cartValidationOutputCollectionIterator.hasNext())
            {
                CartExtension.CartValidationOutput cvo = cartValidationOutputCollectionIterator.next();

                if (cvo.getType() == CartExtension.CartValidationOutputTypeEnum.SHIPPING) {
                    cartValidationOutputCollection.remove(cvo);
                }
            }

            // To create the Cart delivery group methods, we need to get the ID of the cart delivery group.
            CartExtension.CartDeliveryGroupList cartDeliveryGroups = cart.getCartDeliveryGroups();
            if (cartDeliveryGroups.size() == 0)
            {
                CartExtension.CartValidationOutput cvo = new CartExtension.CartValidationOutput(CartExtension.CartValidationOutputTypeEnum.SHIPPING,
                    CartExtension.CartValidationOutputLevelEnum.ERROR);
                cvo.setMessage('No Cart Delivery Groups have been defined');
                cartValidationOutputCollection.add(cvo);
            }
            else
            {
                CartExtension.CartItemList cartItems = cart.getCartItems();
                Integer numberOfUniqueItems = cartItems.size();

                for (Integer i = (cartDeliveryGroups.size() - 1); i >= 0; i--)
                {
                    CartExtension.CartDeliveryGroup cartDeliveryGroup = cartDeliveryGroups.get(i);
                    CartExtension.CartDeliveryGroupMethodList cartDeliveryGroupMethods = cartDeliveryGroup.getCartDeliveryGroupMethods();

                    // Clean up the CartDeliveryGroupMethods
                    for (Integer j = (cartDeliveryGroupMethods.size() - 1); j >= 0; j--)
                    {
                        CartExtension.CartDeliveryGroupMethod method = cartDeliveryGroupMethods.get(j);
                        cartDeliveryGroupMethods.remove(method);
                    }

                    // To clear selected Cart Delivery Group Method
                    cartDeliveryGroup.setSelectedCartDeliveryGroupMethod(null);

                    // Get the Shipping Product
                    List<Product2> shippingProducts = [
                        SELECT
                            Id, Name, StockKeepingUnit, ProductCode
                        FROM
                            Product2
                        WHERE
                            ProductClass != 'VariationParent'
                            AND Name = :SHIPPING_PRODUCT_NAME
                            AND StockKeepingUnit = :SHIPPING_PRODUCT_STOCK_KEEPING_UNIT
                            AND ProductCode = :SHIPPING_PRODUCT_CODE LIMIT 1
                    ];

                    if(shippingProducts.size() == 0)
                    {
                        CartExtension.CartValidationOutput cvo = new CartExtension.CartValidationOutput(CartExtension.CartValidationOutputTypeEnum.SHIPPING,
                                CartExtension.CartValidationOutputLevelEnum.ERROR );
                        cvo.setMessage('No Shipping Products have been defined');
                        cartValidationOutputCollection.add(cvo);
                    }
                    else
                    {
                        String shippingProduct = Id.valueOf(shippingProducts[0].Id);
                        // Create a CartDeliveryGroupMethod record for every shipping option returned from the external service
                        if(USE_EXTERNAL_SERVICE) {
                            // Get shipping options, including aspects like rates and carriers, from the external service.
                            ShippingOptionsAndRatesFromExternalService[] shippingOptionsAndRatesFromExternalService = getShippingOptionsAndRatesFromExternalService(
                            numberOfUniqueItems, cartValidationOutputCollection
                            );

                            // Create a CartDeliveryGroupMethod record for every shipping option returned from the external
                            // service and every Order Delivery Method that matches
                            if(shippingOptionsAndRatesFromExternalService != null)
                            {
                                populateCartDeliveryGroupMethodWithShippingOptions(
                                    shippingOptionsAndRatesFromExternalService,
                                    cartDeliveryGroupMethods,shippingProduct,
                                    cartValidationOutputCollection
                                );
                            }
                        }
                        else
                        {
                            // TODO: Put this into a method like getShippingOptionsAndRatesFromOrg
                            System.debug('## INVOCATION: ServiceShippingDefault.calculate using org-based values.');

                            // 1. Ground delivery = 10.99 fee
                            CartExtension.CartDeliveryGroupMethod cartDeliveryGroupMethod01 = new CartExtension.CartDeliveryGroupMethod('Ground Shipping', 10.99, shippingProduct);
                            cartDeliveryGroupMethod01.setCarrier('USPS');
                            cartDeliveryGroupMethod01.setClassOfService('Ground Shipping');

                            // 2. Nest Day Air delivery = 15.99 fee
                            CartExtension.CartDeliveryGroupMethod cartDeliveryGroupMethod02 = new CartExtension.CartDeliveryGroupMethod('Next Day Air', 15.99, shippingProduct);
                            cartDeliveryGroupMethod02.setCarrier('UPS');
                            cartDeliveryGroupMethod02.setClassOfService('Next Day Air');
                            cartDeliveryGroupMethods.add(cartDeliveryGroupMethod01);
                            cartDeliveryGroupMethods.add(cartDeliveryGroupMethod02);
                        }
                    }
                }
            }

            System.debug('## SUCCESS: ServiceShippingDefault.calculate');
        }
        catch (Exception e)
        {
            /***
             * For testing purposes, this example treats exceptions as user errors, which means they are
             * displayed to the buyer user. In production, you probably want exceptions to be admin-type
             * errors. In that case, throw the exception here and make sure that a notification system is
             * in place to let the admin know that the error occurred.
             */
            System.debug('## EXCEPTION THROWN: ServiceShippingDefault.calculate: ' + e.getMessage());
        }
    }

    private static String generateRandomString(Integer stringLength)
    {
        final String chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz';
        String randStr = '';

        while (randStr.length() < stringLength)
        {
            Integer idx = Math.mod(Math.abs(Crypto.getRandomInteger()), chars.length());
            randStr += chars.substring(idx, idx+1);
        }

        return randStr;
    }

    // Note: This sample method currently only takes in numberOfUniqueItems as an input parameter. For
    // real-world scenarios, expand the parameter list.
    private ShippingOptionsAndRatesFromExternalService[] getShippingOptionsAndRatesFromExternalService(
        Integer numberOfUniqueItems, CartExtension.CartValidationOutputList cartValidationOutputCollection) {
        System.debug('## INVOCATION: LwrCca_ShippinhDefault.getShippingOptionsAndRatesFromExternalService called.');

        // TODO: Refactor this to use the BaseRestUtility or one of its children
        ShippingOptionsAndRatesFromExternalService[] shippingOptions = new List<ShippingOptionsAndRatesFromExternalService>();
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        request.setEndpoint(EXTERNAL_SHIPPING_URL);
        request.setMethod('GET');
        HttpResponse response = http.send(request);

        /**
         * If the request is successful, parse the JSON response. Typical response looks like this:
         * [
         *  {
         *     "status": "calculated",
         *      "rate": {
         *       "name": "Delivery Method 1",
         *       "serviceName": "Test Carrier 1",
         *       "serviceCode": "SNC9600",
         *       "shipmentCost": 11.99,
         *       "otherCost": 5.99
         *     }
         *   },
         *   {
         *     "status": "calculated",
         *     "rate": {
         *       "name": "Delivery Method 2",
         *       "serviceName": "Test Carrier 2",
         *       "serviceCode": "SNC9600",
         *       "shipmentCost": 15.99,
         *       "otherCost": 6.99
         *     }
         *   }
         * ]
         */
        if (response.getStatusCode() == SUCCESSFUL_HTTP_REQUEST)
        {
            List<Object> results = (List<Object>) JSON.deserializeUntyped(response.getBody());

            for (Object result : results)
            {
                Map<String, Object> subresult = (Map<String, Object>) result;
                Map<String, Object> providerAndRate = (Map<String, Object>) subresult.get('rate');

                shippingOptions.add(
                    new ShippingOptionsAndRatesFromExternalService(
                        (String) providerAndRate.get('name'), (String) providerAndRate.get('serviceCode'), (Decimal) providerAndRate.get('shipmentCost'),
                        (Decimal) providerAndRate.get('otherCost'), (String) providerAndRate.get('serviceName'), (String) providerAndRate.get('serviceName'),
                        (String) providerAndRate.get('serviceCode'), generateRandomString(10), true
                    )
                );
            }

            return shippingOptions;
        }
        else
        {
            String errorMessage = 'We failed to calculate shipping options for your cart.';

            if(response.getStatusCode() == 404)
            {
                errorMessage = '404. You must create a sample application or add your own service which returns a valid response';
            }

            // Create a CVO with the Error
            CartExtension.CartValidationOutput cvo = new CartExtension.CartValidationOutput(CartExtension.CartValidationOutputTypeEnum.SHIPPING,
                CartExtension.CartValidationOutputLevelEnum.ERROR);
            cvo.setMessage(errorMessage);
            cartValidationOutputCollection.add(cvo);
            return null;
        }
    }

    // Structure to store the shipping options retrieved from external service.
    class ShippingOptionsAndRatesFromExternalService
    {
         private String name;
         private String provider;
         private Decimal rate;
         private Decimal otherCost;
         private String serviceName;
         private String carrier;
         private String classOfService;
         private String referenceNumber;
         private Boolean isActive;

         public ShippingOptionsAndRatesFromExternalService()
         {
             name = '';
             provider = '';
             rate = 0.0;
             serviceName = '';
             otherCost = 0.0;
             carrier = '';
             classOfService = '';
             referenceNumber = '';
             isActive = true;
         }

        public ShippingOptionsAndRatesFromExternalService(String someName, String someProvider, Decimal someRate, Decimal someOtherCost, String someServiceName,
                 String someCarrier, String someClassOfService, String someReferenceNumber, Boolean someIsActive)
        {
             name = someName;
             provider = someProvider;
             rate = someRate;
             otherCost = someOtherCost;
             serviceName = someServiceName;
             carrier = someCarrier;
             classOfService = someClassOfService;
             referenceNumber = someReferenceNumber;
             isActive = someIsActive;
         }

         // TODO: Move this to C#-style auto-properties?
         public String getProvider() { return provider; }
         public Decimal getRate() { return rate; }
         public Decimal getOtherCost() { return otherCost; }
         public String getServiceName() { return serviceName; }
         public String getName() { return name; }
         public String getCarrier() { return carrier; }
         public String getClassOfService() { return classOfService; }
         public String getReferenceNumber() { return referenceNumber; }
         public Boolean isActive() { return isActive; }
    }

    private void populateCartDeliveryGroupMethodWithShippingOptions(List<ServiceShippingDefault.ShippingOptionsAndRatesFromExternalService> shippingOptions,
        CartExtension.CartDeliveryGroupMethodList cartDeliveryGroupMethodCollection, String shippingProduct,
        CartExtension.CartValidationOutputList cartValidationOutputCollection)
    {
       for (ShippingOptionsAndRatesFromExternalService shippingOption : shippingOptions)
       {
            String carrier = shippingOption.serviceName;
            String classOfService = shippingOption.provider;

            // Create a CartDeliveryGroupMethod for every shipping option returned from the external service
            CartExtension.CartDeliveryGroupMethod cartDeliveryGroupMethod = new CartExtension.CartDeliveryGroupMethod(shippingOption.getName(),
                shippingOption.getRate(), shippingProduct);

            cartDeliveryGroupMethod.setExternalProvider(shippingOption.getProvider());
            cartDeliveryGroupMethod.setCarrier(shippingOption.getCarrier());
            cartDeliveryGroupMethod.setClassOfService(shippingOption.getClassOfService());
            cartDeliveryGroupMethod.setIsActive(shippingOption.isActive());
            cartDeliveryGroupMethod.setReferenceNumber(shippingOption.getReferenceNumber());
            cartDeliveryGroupMethodCollection.add(cartDeliveryGroupMethod);
         }
    }
 }