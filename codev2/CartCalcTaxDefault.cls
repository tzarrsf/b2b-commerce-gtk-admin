/**
 * @description       : Example Cart Calculator for Taxation aspects. This class is part of the "Get to Know B2B Commerce for Administrators"
 *                      curriculum in the Salesforce Partner Learning Camp (PLC). This class is loosely based on the example provided at this URL:
 *                      https://github.com/forcedotcom/commerce-extensibility/blob/releases/248/commerce/domain/tax/cart/calculator/classes/TaxCartCalculatorSample.cls
 *
 *                      Original Comments in the referenced code:
 *                      -----------------------------------------
 *                      This tax calculator extension class makes a call to an external service to retrieve tax
 *                      information for a cart item and its adjustments and saves it to a cart data transfer object
 *                      (DTO). For a tax calculator extension to be processed by the checkout flow, you must implement the
 *                      CartExtension.TaxCartCalculator class.
 *
 *                      Notable modifications made to original example code to better suit this course and improve understanding:
 *                      ---------------------------------------------------------------------------------------------------------
 *                      1. Screaming constants (static final variables)
 *                      2. Many additional System.debug entries
 *                      3. Reformatting for legibility
 *                      4. Additional comments
 *                      5. Refactoring to remove cognitive complexity warning
 *
 * @author            : Tom Zarr
 * @group             : Salesforce Commerce Partner Delivery Success (2024)
 * @last modified on  : 09-17-2024
 * @last modified by  : Tom Zarr
**/
public class CartCalcTaxDefault extends CartExtension.TaxCartCalculator
{

    /*
    You MUST change this to be your service or you must launch your own Third Party Service
    and add the host in Setup => Security => Remote site settings.
    */
    private static final String EXTERNAL_TAX_HOST = 'https://example.com';

    /*
    You MUST change the USE_EXTERNAL_SERVICE to True if you want to use the Third Party Service
    */
    private static final Boolean USE_EXTERNAL_SERVICE = false;

    /*
    States in the United states that purportedly don't have a sales tax
    */
    private static final String [] US_STATES_WITHOUT_SALES_TAX = new String [] {'AK', 'DE', 'MT', 'NH', 'OR'};

    private static final Decimal ZERO_DECIMAL = 0.0;

    /**
     * Run the loop against the cartValidationOutputCollection in reverse accounting for size to avoid
     * one-off errors since the collection size is modified by removing items which are of type TAXES
     * with the results passed back by reference.
     */
    private void removeTaxElementsFromCartValidationOutputCollection(CartExtension.CartValidationOutputList cartValidationOutputCollection)
    {
        System.debug('### removeTaxElementsFromCartValidationOutputCollection started with size: "' + cartValidationOutputCollection.size() + '"...');

        for (Integer i = (cartValidationOutputCollection.size() - 1); i >= 0; i--)
        {
            CartExtension.CartValidationOutput cvo = cartValidationOutputCollection.get(i);

            if (cvo.getType() == CartExtension.CartValidationOutputTypeEnum.TAXES)
            {
                System.debug('### Removing the hit on a cvo with Type: "' + cvo.getType() + '" and Level: "' + cvo.getLevel() + '".');
                cartValidationOutputCollection.remove(cvo);
            }
        }

        System.debug('### removeTaxElementsFromCartValidationOutputCollection complete with size: "' + cartValidationOutputCollection.size() + '".');
    }

    private void mapProductAndShippingCartItems(CartExtension.CartItemList cartItemCollection, Map<String, CartExtension.CartItem> cartItemById, Map<String, CartExtension.CartItem> shippingItemById)
    {
        String message = '### mapProductAndShippingCartItems started with ';
        message += 'cartItemCollection size: "' + cartItemCollection.size() + '" ';
        message += 'cartItemById size: "' + cartItemById.size() + '" ';
        message += 'shippingItemById: "' + shippingItemById.size() + '".';
        System.debug(message);

        for (Integer i = (cartItemCollection.size() - 1); i >= 0; i--)
        {
            if (cartItemCollection.get(i).getType() == CartExtension.SalesItemTypeEnum.PRODUCT)
            {
                cartItemById.put(cartItemCollection.get(i).getId(), cartItemCollection.get(i));
            }
            else if (cartItemCollection.get(i).getType() == CartExtension.SalesItemTypeEnum.CHARGE)
            {
                // Shipping cart items are uniquely identified using delivery group id.
                CartExtension.CartDeliveryGroup deliveryGroup = cartItemCollection.get(i).getCartDeliveryGroup();
                shippingItemById.put(deliveryGroup.getId(), cartItemCollection.get(i));
            }
        }
    }

    public virtual override void calculate(CartExtension.CartCalculateCalculatorRequest request)
    {
        System.debug('### calculate started with request data: "' + JSON.serializePretty(request) + '"...');

        try
        {
            CartExtension.Cart cart = request.getCart();
            System.debug('### cart retrieved with data: "' + JSON.serializePretty(cart) + '"...');

            /*
            Clean up CVO based on tax. When new tax calculator request comes, we need to clean up
            previous CVOs as they have been previously handled by the Cart Calculate API.
            */
            CartExtension.CartValidationOutputList cartValidationOutputCollection = cart.getCartValidationOutputs();
            removeTaxElementsFromCartValidationOutputCollection(cartValidationOutputCollection);

            /*
            There's an assumption here that split shipping is not in use, i.e. that there should
            be only a single delivery group per cart.
            */
            CartExtension.CartDeliveryGroupList cartDeliveryGroups = cart.getCartDeliveryGroups();
            System.assert(cartDeliveryGroups.size() == 1, '### NOTE: This example does not support multiple Cart Delivery Groups');
            CartExtension.CartDeliveryGroup cartDeliveryGroup = cartDeliveryGroups.get(0);

            /*
            Get a clean reference to the cart items which will contain both products and shipping
            items at the cart level.
            */
            CartExtension.CartItemList cartItemCollection = cart.getCartItems();
            System.debug('### cartItemCollection data: "' + JSON.serializePretty(cartItemCollection) + '"...');

            // Map cart ID to cart item with type Product.
            // The cartItemCollection contains both products and shipping cart items.
            Map<String, CartExtension.CartItem> cartItemById = new Map<String, CartExtension.CartItem>();
            Map<String, CartExtension.CartItem> shippingItemById = new Map<String, CartExtension.CartItem>();

            mapProductAndShippingCartItems(cartItemCollection, cartItemById, shippingItemById);

            System.debug('### mapProductAndShippingCartItems cartItemCollection data: "' + JSON.serializePretty(cartItemCollection) + '".');
            System.debug('### mapProductAndShippingCartItems cartItemById data: "' + JSON.serializePretty(cartItemById) + '".');
            System.debug('### mapProductAndShippingCartItems shippingItemById data: "' + JSON.serializePretty(shippingItemById) + '".');

            /*
            Get the tax rates and tax amounts for all given products and their adjustments via one of two means:
                1. An external service - NOTE: USE_EXTERNAL_SERVICE must be set to true and any external URLs needed such as the value in
                EXTERNAL_TAX_HOST must be allowed in Setup => Security => Remote site settings for this branch
                of code to work
                2. A static response - essentially a mock with no external callout being made.
            */
            Map<String, TaxDataFromExternalService> cartItemTaxCallData = null;
            Map<String, TaxDataFromExternalService> shippingItemTaxCallData = null;
            String deliveryState = CartDeliveryGroup.getDeliverToAddress().getState();
            String deliveryCountry = CartDeliveryGroup.getDeliverToAddress().getCountry();
            CartExtension.TaxLocaleTypeEnum cartTaxType = cart.getTaxType();

            if(USE_EXTERNAL_SERVICE)
            {
                System.debug('### Starting getTaxesFromExternalService...');
                cartItemTaxCallData = getTaxesFromExternalService(cartItemById, deliveryState, deliveryCountry,cartTaxType);
                shippingItemTaxCallData = getTaxesFromExternalService(shippingItemById, deliveryState, deliveryCountry, cartTaxType);
                System.debug('### getTaxesFromExternalService complete!');
            }
            else
            {
                System.debug('### Starting getTaxesFromStaticResponse...');
                cartItemTaxCallData = getTaxesFromStaticResponse(cartItemById, deliveryState, deliveryCountry, cartTaxType);
                shippingItemTaxCallData = getTaxesFromStaticResponse(shippingItemById, deliveryState, deliveryCountry, cartTaxType);
                System.debug('### getTaxesFromStaticResponse complete!');
            }

            // If no tax details are returned for any cart item, add a cart validation output entry. If
            // any invalid scenario found then return.
            boolean isCvoPresent = false;

            for (String cartItemId : cartItemById.keySet())
            {
                System.debug('### Seeking taxes on cartItemId: "' + cartItemId + '" state: "' + deliveryState  + '" country: "' + deliveryCountry  + '"...');

                TaxDataFromExternalService taxDetails = cartItemTaxCallData.get(cartItemId);
                System.debug('### taxDetails data: "' + JSON.serializePretty(taxDetails) + '".');

                if (taxDetails == null)
                {
                    System.debug('### No tax rates configured for this location whe looking for cartItemId: "' + cartItemId + '".');

                    // add CartValidationOutputs with message about rates not found
                    CartExtension.CartValidationOutput cvo = new CartExtension.CartValidationOutput(
                        CartExtension.CartValidationOutputTypeEnum.TAXES,
                        CartExtension.CartValidationOutputLevelEnum.INFO
                    );
                    cvo.setMessage('No tax rates configured for this location.');
                    cartValidationOutputCollection.add(cvo);
                    isCvoPresent = true;
                }

                System.debug('### Looking for taxes on cartItemId: "' + cartItemId + '" complete.');
            }

            if (isCvoPresent)
            {
                return;
            }

            for (String cartItemId : cartItemTaxCallData.keySet())
            {
                TaxDataFromExternalService taxDetailsToCartId = cartItemTaxCallData.get(cartItemId);
                CartExtension.CartItem cartItem = cartItemById.get(cartItemId);

                // NOTE: DELETED items get filtered out in the DtoCollection and if there is no tax setup
                // against any cart item, then that's considered an invalid scenario and added to CVO. If
                // cart tax numbers are changed that indicates the cart item was MODIFIED, then:
                // 1. Delete existing and create new cart tax entries in cart item and cart item
                // adjustments.
                // 2. Update cart item tax information. Currently, we do not support taxes on tier
                // adjustment in an extension.
                boolean isCartItemModified = false;

                if ((cartItem.getNetUnitPrice() != null && cartItem.getNetUnitPrice() != taxDetailsToCartId.getNetUnitPrice()) || !verifyAdjustmentUpdate(cartItem, taxDetailsToCartId))
                {
                    if (cartItem.getCartTaxes().size() > 0)
                    {
                        cartItem.getCartTaxes().remove(cartItem.getCartTaxes().get(0));
                    }

                    for (Integer i = (cartItem.getCartItemPriceAdjustments().size() - 1); i >= 0; i--)
                    {
                        CartExtension.CartTaxList cipaTaxes = cartItem.getCartItemPriceAdjustments().get(i).getCartTaxes();

                        if (cipaTaxes.size() > 0)
                        {
                            cipaTaxes.remove(cipaTaxes.get(0));
                        }
                    }

                    isCartItemModified = true;
                }

                // If there are no existing cart tax entries in the cart item that indicates cart item was
                // newly CREATED in the cart then:
                // 1. Create new cart tax entries
                // 2. Update cart item tax information
                if (cartItem.getCartTaxes() == null || cartItem.getCartTaxes().isEmpty() || isCartItemModified == true)
                {
                    cartItem.setNetUnitPrice(taxDetailsToCartId.getNetUnitPrice());
                    cartItem.setGrossUnitPrice(taxDetailsToCartId.getGrossUnitPrice());
                    cartItem.setAdjustmentTaxAmount(taxDetailsToCartId.getAdjustmentTaxAmount());
                    CartExtension.CartTaxList cartTaxCollection = cartItem.getCartTaxes();
                    CartExtension.CartTax cartTax = new CartExtension.CartTax(CartExtension.TaxTypeEnum.ESTIMATED,
                        taxDetailsToCartId.getAmount(), taxDetailsToCartId.getTaxName());
                    cartTax.setTaxRate(String.valueOf(taxDetailsToCartId.getRate()));
                    cartTaxCollection.add(cartTax);

                    // Add adjustment taxes to cartItemAdjustments of cartItem and create CartTaxDto entries
                    // for all promotion adjustments.
                    if (taxDetailsToCartId.getItemizedPromotionTaxAmounts() != null && !(taxDetailsToCartId.getItemizedPromotionTaxAmounts().isEmpty()))
                    {
                        for (CartAdjustment cipaTax : taxDetailsToCartId.getItemizedPromotionTaxAmounts())
                        {
                            CartExtension.CartTax promoTax = new CartExtension.CartTax(CartExtension.TaxTypeEnum.ESTIMATED,
                                cipaTax.getAmount(), taxDetailsToCartId.getTaxName()
                            );
                            promoTax.setTaxRate(String.valueOf(taxDetailsToCartId.getRate()));
                            CartExtension.cartItemPriceAdjustment adj = getAdjustmentById(cartItem.getCartItemPriceAdjustments(),
                                cipaTax.getId());

                            if (adj != null)
                            {
                                adj.getCartTaxes().add(promoTax);
                            }
                        }
                    }
                }
            }

            // If there are shipping items, add tax for them as well
            for (String cartItemId : shippingItemTaxCallData.keySet())
            {
                TaxDataFromExternalService taxDetailsToCartId = shippingItemTaxCallData.get(cartItemId);
                CartExtension.CartItem cartItem = shippingItemById.get(cartItemId);
                boolean isCartItemModified = false;

                // If there is any modification in unit price, delete existing and create new cart tax entries in cart item.
                if (cartItem.getNetUnitPrice() != null && cartItem.getNetUnitPrice() != taxDetailsToCartId.getNetUnitPrice())
                {
                    cartItem.getCartTaxes().remove(cartItem.getCartTaxes().get(0));
                    isCartItemModified = true;
                }

                if (cartItem.getCartTaxes() == null || cartItem.getCartTaxes().isEmpty() || isCartItemModified == true)
                {
                    cartItem.setNetUnitPrice(taxDetailsToCartId.getNetUnitPrice());
                    cartItem.setGrossUnitPrice(taxDetailsToCartId.getGrossUnitPrice());
                    CartExtension.CartTaxList cartTaxCollection = cartItem.getCartTaxes();
                    CartExtension.CartTax cartTax = new CartExtension.CartTax(CartExtension.TaxTypeEnum.ESTIMATED,
                        taxDetailsToCartId.getAmount(), taxDetailsToCartId.getTaxName());
                    cartTax.setTaxRate(String.valueOf(taxDetailsToCartId.getRate()));
                    cartTaxCollection.add(cartTax);
                }
            }
        }
        catch (Exception e)
        {
            // For testing purposes, this example treats exceptions as user errors, which means they are
            // displayed to the buyer user. In production, you probably want exceptions to be admin-type
            // errors. In that case, throw the exception here and make sure that a notification system is
            // in place to let the admin know that the error occurred. See the README section about error
            // handling for details about how to create that notification.
            System.debug('### Trapped error in calculate method of TaxCartCalculator');
            throw new CalloutException('There was a problem with the request.');
        }
    }

    /*
     * Verify if taxes from adjustments returned by external service and existing cart has changed. If
     * returned true then that indicates that there was an adjustment change.
     */
    private Boolean verifyAdjustmentUpdate(CartExtension.CartItem cartItemDto, TaxDataFromExternalService taxesFromExternalService)
    {
        System.debug('### verifyAdjustmentUpdate started...');

        List<CartAdjustment> ajustments = taxesFromExternalService.getItemizedPromotionTaxAmounts() == null
            ? new List<CartAdjustment>()
            : taxesFromExternalService.getItemizedPromotionTaxAmounts();

        // Reverse loop accounting for one-offs due to collection size changes
        for (Integer i = (cartItemDto.getCartItemPriceAdjustments().size() - 1); i >= 0; i--)
        {
            CartExtension.CartTaxList cartTaxes = cartItemDto.getCartItemPriceAdjustments()
                .get(i)
                .getCartTaxes();

            // Reverse loop accounting for one-offs due to collection size changes
            for (Integer j = (cartTaxes.size() - 1); j >= 0; j--)
            {
                Boolean changedAdjTax = false;

                // Reverse loop accounting for one-offs due to collection size changes
                for (Integer k = (ajustments.size() - 1); k >= 0; k--)
                {
                    if (cartTaxes.get(j).getAmount() == ajustments.get(k).getAmount())
                    {
                        changedAdjTax = true;
                    }
                }

                if (changedAdjTax == false)
                {
                    return false;
                }
            }
        }

        return true;
    }

    // Get cartItemAdjustment based on its ID.
    private CartExtension.cartItemPriceAdjustment getAdjustmentById(CartExtension.cartItemPriceAdjustmentList cipaList, String id)
    {
        // Does this need to be a reverse loop accounting for one-offs? Probably not.
        for (Integer i = (cipaList.size() - 1); i >= 0; i--)
        {
            if (String.valueOf(cipaList.get(i).getId()) == id)
            {
                return cipaList.get(i);
            }
        }

        return null;
    }

    // This similartes a call to an external tax service. Change this function based on your external
    // service. Transform tax data returned from service into cart ID to TaxDataFromExternalService
    // map.
    private Map<String, TaxDataFromExternalService> getTaxesFromExternalService(Map<String, CartExtension.CartItem> cartItemById,
        String state, String country, CartExtension.TaxLocaleTypeEnum taxType)
    {
        String requestURL = EXTERNAL_TAX_HOST+'/get-tax-rates-with-adjustments-post';

        String requestBody =
        '{"state":"' +
        state +
        '", "country":"' +
        country +
        '", "taxType":"' +
        taxType +
        '", ' +
        '"amountsBySKU":' +
        JSON.serialize(cartItemById) +
        '}';

        Http http = new Http();
        HttpRequest request = new HttpRequest();
        request.setEndpoint(requestURL);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setBody(requestBody);
        HttpResponse response = http.send(request);

        // If the request is successful, parse the JSON response.
        if (response.getStatusCode() == 200)
        {
            Map<String, Object> resultsFromExternalService = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            return populateTax(resultsFromExternalService);
        }
        else
        {
            throw new CalloutException(
                'There was a problem with the request. Error: ' + response.getStatusCode()
            );
        }
    }

    private Map<String, TaxDataFromExternalService> populateTax(Map<String, Object> resultsFromExternalService)
    {
        Map<String, TaxDataFromExternalService> taxDetailsFromExternalService = new Map<String, TaxDataFromExternalService>();

        for (String cartItemId : resultsFromExternalService.keySet())
        {
            Map<String, Object> rateAndAmountFromExternalService = (Map<String, Object>) resultsFromExternalService.get(cartItemId);
            List<Object> cipaList = (List<Object>) rateAndAmountFromExternalService.get('itemizedPromotionTaxAmounts');
            List<CartAdjustment> cipaObj = new List<CartAdjustment>();

            for (Object cipa : cipaList)
            {
                CartAdjustment newCartAdjustment = new CartAdjustment((String) ((Map<String, Object>) cipa).get('id'),(Decimal) ((Map<String, Object>) cipa).get('taxAmount'));
                cipaObj.add(newCartAdjustment);
            }

            taxDetailsFromExternalService.put(
                cartItemId,
                new TaxDataFromExternalService(
                    (Decimal) rateAndAmountFromExternalService.get('rate'),
                    (Decimal) rateAndAmountFromExternalService.get('amount'),
                    (String) rateAndAmountFromExternalService.get('taxName'),
                    (Decimal) rateAndAmountFromExternalService.get('adjustmentTaxAmount'),
                    (Decimal) rateAndAmountFromExternalService.get('totalItemizedPromotionTaxAmount'),
                    cipaObj,
                    (Decimal) rateAndAmountFromExternalService.get('grossUnitPrice'),
                    (Decimal) rateAndAmountFromExternalService.get('netUnitPrice')
                )
            );
        }

        return taxDetailsFromExternalService;
    }

    private Map<String, TaxDataFromExternalService> getTaxesFromStaticResponse(Map<String, CartExtension.CartItem> cartItemsMap,
        String state, String country, CartExtension.TaxLocaleTypeEnum taxType)
    {

        Double taxRate = 0.15;
        String responseJson = '{';

        for (String key : cartItemsMap.keySet())
        {
            CartExtension.CartItem cartItem = cartItemsMap.get(key);
            ID cartItemId = cartItem.getId();
            Double amount = cartItem.getTotalAmount()==null ? 0.00 : cartItem.getTotalAmount();
            Double tierAdjustment = cartItem.getAdjustmentAmount()==null ? 0.00 : cartItem.getAdjustmentAmount();
            Double quantity = cartItem.getQuantity()==null ? 0.00 : cartItem.getQuantity();

            if(country == 'US')
            {
                taxRate = 0.08;

                if (US_STATES_WITHOUT_SALES_TAX.contains(state))
                {
                    taxRate = 0.00;
                }
            }

            Double itemizedPromotionTax = 0.00;
            Double [] itemizedPromotionTaxArr = new Double [] {};
            Double netUnitPrice = 0.00;
            Double grossUnitPrice = 0.00;
            Double multiplier = 0.00;

            if(taxType == CartExtension.TaxLocaleTypeEnum.GROSS)
            {
                multiplier = taxRate / (1 + taxRate);
            }
            else
            {
                multiplier = taxRate;
            }

            Double cartItemTax = amount * multiplier;
            Double tierAdjustmentTax = (tierAdjustment!=null ? tierAdjustment : 0.00) * multiplier;
            CartExtension.CartItemPriceAdjustmentList itemizedPromotions = cartItem.getCartItemPriceAdjustments();

            String itemizedPromotionTaxResp = '[';

            for(Integer i = 0; i < itemizedPromotions.size(); i++)
            {
                CartExtension.CartItemPriceAdjustment itemAdj = itemizedPromotions.get(i);
                Double itemTaxAmount = (itemAdj.getTotalAmount()!=null ? itemAdj.getTotalAmount() : 0.00) * multiplier;
                itemizedPromotionTaxResp = itemizedPromotionTaxResp + '{';
                itemizedPromotionTaxResp = itemizedPromotionTaxResp + '"id": "' + itemAdj.getId() + '",';
                itemizedPromotionTaxResp = itemizedPromotionTaxResp + '"taxAmount": ' + itemTaxAmount;
                itemizedPromotionTaxResp = itemizedPromotionTaxResp + '},';
                itemizedPromotionTax = itemizedPromotionTax + itemTaxAmount;
            }

            itemizedPromotionTaxResp = itemizedPromotionTaxResp.removeEnd(',') + ']';

            if(taxType == CartExtension.TaxLocaleTypeEnum.GROSS)
            {
                System.debug('Calculating for Gross taxation');
                grossUnitPrice = amount / quantity;
                netUnitPrice = (amount - cartItemTax) / quantity;
            }
            else
            {
                System.debug('Calculating for Net taxation');
                grossUnitPrice = (amount + cartItemTax) / quantity;
                netUnitPrice = amount / quantity;
            }

            responseJson = responseJson + '"'+ key +'":';
            responseJson = responseJson + '{';
            responseJson = responseJson + '"cartItemId": "' + cartItemId + '",';
            responseJson = responseJson + '"amount": ' + cartItemTax + ',';
            responseJson = responseJson + '"adjustmentTaxAmount": ' + tierAdjustmentTax + ',';
            responseJson = responseJson + '"itemizedPromotionTaxAmounts": ';
            responseJson = responseJson + itemizedPromotionTaxResp;
            responseJson = responseJson + ',';
            responseJson = responseJson + '"totalItemizedPromotionTaxAmount": ' + itemizedPromotionTax + ',';
            responseJson = responseJson + '"grossUnitPrice": ' + grossUnitPrice + ',';
            responseJson = responseJson + '"netUnitPrice": ' + netUnitPrice + ',';
            responseJson = responseJson + '"rate": ' + taxRate + ',';
            responseJson = responseJson + '"taxName": "GST"';
            responseJson = responseJson + '},';
        }

        responseJson = responseJson.removeEnd(',') + '}';
        Map<String, Object> resultsFromStaticResponse =  (Map<String, Object>) JSON.deserializeUntyped(responseJson);
        return populateTax(resultsFromStaticResponse);
    }

    /**
     * Structure to store the tax data retrieved from external service. This class simplifies our
     * ability to access the data when storing it in Salesforce's CartTaxDto.
     */
    class TaxDataFromExternalService
    {
        private Decimal rate;
        private Decimal amount;
        private String taxName;
        private Decimal adjustmentTaxAmount;
        private Decimal totalItemizedPromotionTaxAmount;
        private List<CartAdjustment> itemizedPromotionTaxAmounts;
        private Decimal grossUnitPrice;
        private Decimal netUnitPrice;
        //private static final Decimal ZERO_DECIMAL = ZERO_DECIMAL;

        public TaxDataFromExternalService() {
            rate = CartCalcTaxDefault.ZERO_DECIMAL;
            amount = CartCalcTaxDefault.ZERO_DECIMAL;
            taxName = '';
            adjustmentTaxAmount = CartCalcTaxDefault.ZERO_DECIMAL;
            totalItemizedPromotionTaxAmount = CartCalcTaxDefault.ZERO_DECIMAL;
            itemizedPromotionTaxAmounts = null;
            grossUnitPrice = CartCalcTaxDefault.ZERO_DECIMAL;
            netUnitPrice = CartCalcTaxDefault.ZERO_DECIMAL;
        }

        public TaxDataFromExternalService(Decimal rateObj, Decimal amountObj, String taxNameObj, Decimal adjustmentTaxAmountObj,
            Decimal totalItemizedPromotionTaxAmountObj, List<CartAdjustment> itemizedPromotionTaxAmountsObj, Decimal grossUnitPriceObj,
            Decimal netUnitPriceObj)
        {
            rate = rateObj;
            amount = amountObj;
            taxName = taxNameObj;
            adjustmentTaxAmount = adjustmentTaxAmountObj;
            totalItemizedPromotionTaxAmount = totalItemizedPromotionTaxAmountObj;
            itemizedPromotionTaxAmounts = itemizedPromotionTaxAmountsObj;
            grossUnitPrice = grossUnitPriceObj;
            netUnitPrice = netUnitPriceObj;
        }

        public Decimal getRate() {
            return rate;
        }

        public Decimal getAmount() {
            return amount;
        }

        public String getTaxName() {
            return taxName;
        }

        public Decimal getAdjustmentTaxAmount() {
            return adjustmentTaxAmount;
        }

        public Decimal getTotalItemizedPromotionTaxAmount() {
            return totalItemizedPromotionTaxAmount;
        }

        public List<CartAdjustment> getItemizedPromotionTaxAmounts() {
            return itemizedPromotionTaxAmounts;
        }

        public Decimal getGrossUnitPrice() {
            return grossUnitPrice;
        }

        public Decimal getNetUnitPrice() {
            return netUnitPrice;
        }
    }

    /**
     * Structure to store the Cart Adjustment data. Useful for things like itemized promotion tax amounts.
     */
    class CartAdjustment
    {
        private String id;
        private Decimal amount;

        public CartAdjustment() {
            id = '';
            amount = CartCalcTaxDefault.ZERO_DECIMAL;
        }

        public CartAdjustment(String idObj, Decimal taxAmountObj) {
            id = idObj;
            amount = taxAmountObj;
        }

        public String getId() {
            return id;
        }

        public Decimal getAmount() {
            return amount;
        }
    }
}
