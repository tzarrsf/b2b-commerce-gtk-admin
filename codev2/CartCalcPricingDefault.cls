/**
 * @description       : Example Cart Calculator for Taxation aspects. This class is part of the "Get to Know B2B Commerce for Administrators"
 *                      curriculum in the Salesforce Partner Learning Camp (PLC). This class is loosely based on the example provided at this URL:
 *                      https://github.com/forcedotcom/commerce-extensibility/blob/releases/248/commerce/domain/tax/cart/calculator/classes/TaxCartCalculatorSample.cls
 *
 *                      Original Comments in the referenced code:
 *                      -----------------------------------------
 *                      This Pricing calculator extension class makes a call to an external service or static to retrieve pricing
 *                      information for a cart item and saves it to a cart data transfer object (DTO).
 *                      For a pricing calculator extension to be processed by the checkout flow, you must implement the
 *                      CartExtension.PricingCartCalculator class. This is just a sample for Pricing calculator, you are expected
 *                      to refer this and write your own implementation.
 *
 *                      Notable modifications made to original example code to better suit this course and improve understanding:
 *                      ---------------------------------------------------------------------------------------------------------
 *                      1. Screaming constants (static final variables)
 *                      2. Many additional System.debug entries
 *                      3. Reformatting for legibility
 *                      4. Superfluous constructor removed in favor of constant
 *                      5. Added PRICE_NOT_FOUND_DEFAULT_VALUE for fallback
 *                      6. Added BUBBLE_EXCEPTIONS for configurability
 *                      7. Added LOG_CART_DETAIL_ACTIVE and LOG_CART_ITEM_DETAIL_ACTIVE with methods for diagnostic data
 *                      8. Introduced the Capricorn sample product price map for local call
 *                      9. Added a productCode property to PricingDataFromExternalService structure so we can perform a lookup
 *                      10. Added a REST call for WebStore pricing data to drive the point home
 *                      11. Added more comments
 *                      12. Refactored to remove some complexity
 *
 * @author            : Tom Zarr
 * @group             : Salesforce Commerce Partner Delivery Success (2024)
 * @last modified on  : 09-18-2024
 * @last modified by  : Tom Zarr
**/

public class CartCalcPricingDefault extends CartExtension.PricingCartCalculator
{
    private static final Decimal ZERO_DECIMAL = 0.0;

    // Set this to true to rethrow the error in the catch block
    private static final Boolean BUBBLE_EXCEPTIONS = true;

    // Set this to true to see a a networked call take place against your org - for demonstration purposes only
    private static final Boolean USE_EXTERNAL_SERVICE = false;

    // Supports a default value for pricing when the pricing is not found - for demostration purposes only
    private static final Decimal PRICE_NOT_FOUND_DEFAULT_VALUE = 50.00;

    // When true logs the details of the cart
    private static final Boolean LOG_CART_DETAIL_ACTIVE = true;

    // When true logs the details of the cart item(s)
    private static final Boolean LOG_CART_ITEM_DETAIL_ACTIVE = true;

    // Supports the Capricorn Sample Product Pricing - for demonstration purposes only
    private Map<String, PricingDataFromExternalService> capricornSamplesStaticPricing;

    /**
    * @description All classes extending CartExtension.AbstractCartCalculator must have a default constructor defined
    */
    public CartCalcPricingDefault()
    {
        super();
        capricornSamplesStaticPricing = new Map<String, PricingDataFromExternalService>();
        // Note on the ctor's parameter format: (productCode, unitPrice, listPrice, totalAdjustmentAmount, totalListPrice, totalPrice)
        capricornSamplesStaticPricing.put('PS-EL', new PricingDataFromExternalService('PS-EL', 549.99, 599.99, 549.99, 549.99, 549.99));
        capricornSamplesStaticPricing.put('TR-COFMAC-001', new PricingDataFromExternalService('TR-COFMAC-001', 449.99, 499.99, 449.99, 449.99, 449.99));
        capricornSamplesStaticPricing.put('ID-PEM', new PricingDataFromExternalService('ID-PEM', 249.99, 259.99, 249.99, 249.99, 249.99));
        capricornSamplesStaticPricing.put('B-C-COFMAC-001', new PricingDataFromExternalService('B-C-COFMAC-001', 484.99, 549.99, 484.99, 484.99, 484.99));
        capricornSamplesStaticPricing.put('CR-DEC', new PricingDataFromExternalService('CR-DEC', 15.99, 22.49, 15.99, 15.99, 15.99));
        capricornSamplesStaticPricing.put('ESP-IOT-1', new PricingDataFromExternalService('ESP-IOT-1', 649.99, 679.99, 649.99, 649.99, 649.99));
        capricornSamplesStaticPricing.put('MRC-1', new PricingDataFromExternalService('MRC-1', 17.99, 24.99, 17.99, 17.99, 17.99));
        capricornSamplesStaticPricing.put('PS-INF', new PricingDataFromExternalService('PS-INF', 429.99, 484.99, 429.99, 429.99, 429.99));
        // TODO: Uncomment this like to get Pricing in the cart for the 'DRW-1' item (Dark Roast Whole Bean)
        // capricornSamplesStaticPricing.put('DRW-1', new PricingDataFromExternalService('DRW-1', 14.99, 19.99, 14.99, 14.99, 14.99));
    }

    /*
     * See https://developer.salesforce.com/docs/commerce/salesforce-commerce/references/comm-apex-reference/Cart.html
     * for additional property setters and getters. 
     */
    private void logCartDetail(CartExtension.Cart cart)
    {
        if(!LOG_CART_DETAIL_ACTIVE)
        {
            return;
        }

        String cartDetail = '### cart data in CartCalcPricingDefault started...\r\n';
        cartDetail += '     Name: "' + cart.getName() + '"\r\n';
        cartDetail += '     WebStoreId: "' + cart.getWebStoreId() + '"\r\n';
        cartDetail += '     AccountId: "' + cart.getAccountId() + '"\r\n';
        cartDetail += '     OwnerId: "' + cart.getOwnerId() + '"\r\n';
        cartDetail += '     Status: "' + cart.getStatus() + '"\r\n';
        cartDetail += '     CurrencyIsoCode: "' + cart.getCurrencyIsoCode() + '"\r\n';
        cartDetail += '     TotalListAmount: "' + cart.getTotalListAmount() + '"\r\n';
        cartDetail += '     TotalProductAmount: "' + cart.getTotalProductAmount() + '"\r\n';
        cartDetail += '     TotalChargeAmount: "' + cart.getTotalChargeAmount() + '"\r\n';
        cartDetail += '     TotalCartLevelAdjAmount: "' + cart.getTotalCartLevelAdjAmount() + '"\r\n';
        cartDetail += '     TotalProductItemAdjAmount: "' + cart.getTotalProductItemAdjAmount() + '"\r\n';
        cartDetail += '     OrderReferenceNumber: "' + cart.getOrderReferenceNumber() + '"\r\n';
        cartDetail += '     GuestEmailAddress: "' + cart.getGuestEmailAddress() + '"\r\n';
        cartDetail += '     GuestPhoneNumber: "' + cart.getGuestPhoneNumber() + '"\r\n';
        cartDetail += '     PoNumber: "' + cart.getPoNumber() + '"\r\n';
        cartDetail += '     PaymentMethodId: "' + cart.getPaymentMethodId() + '"\r\n';
        cartDetail += '     TotalProductCount: "' + cart.getTotalProductCount() + '"\r\n';
        cartDetail += '     TotalTaxAmount: "' + cart.getTotalTaxAmount() + '"\r\n';
        cartDetail += '     TaxType: "' + cart.getTaxType() + '"\r\n';
        cartDetail += '### cart data in CartCalcPricingDefault complete.\r\n';
        System.debug(cartDetail);
    }

    /*
    See https://developer.salesforce.com/docs/commerce/salesforce-commerce/references/comm-apex-reference/CartItem.html
    for additional property setters and getters.
    */
    private void logCartItemDetail(CartExtension.CartItem cartItem)
    {
        if(!LOG_CART_ITEM_DETAIL_ACTIVE)
        {
            return;
        }

        String cartItemDetail = '### cartItem data in CartCalcPricingDefault started...\r\n';
        cartItemDetail += '     Name: "' + cartItem.getName() + '"\r\n';
        cartItemDetail += '     SalesItemType: "' + cartItem.getType().toString() + '"\r\n';
        cartItemDetail += '     CartDeliveryGroup: "' + cartItem.getCartDeliveryGroup() + '"\r\n';
        cartItemDetail += '### cartItem data in CartCalcPricingDefault complete.\r\n';
        System.debug(cartItemDetail);
    }

    public virtual override void calculate(CartExtension.CartCalculateCalculatorRequest request)
    {
        System.debug('### calculate in CartCalcPricingDefault started...');

        try
        {
            // Documentation for the type below: https://developer.salesforce.com/docs/commerce/salesforce-commerce/references/comm-apex-reference/Cart.html
            CartExtension.Cart cart = request.getCart();
            this.logCartDetail(cart);

            Iterator<CartExtension.CartItem> cartItemsIterator = clearErrorsAndGetCartItemsIterator(cart, request.getOptionalBuyerActionDetails());

            // Get the SKU from each cart item that needs a price calculation
            Set<String> skus = new Set<String>();
            List<CartExtension.CartItem> cartItems = new List<CartExtension.CartItem>();

            while (cartItemsIterator.hasNext())
            {
                // Documentation for the type below: https://developer.salesforce.com/docs/commerce/salesforce-commerce/references/comm-apex-reference/CartItem.html
                CartExtension.CartItem cartItem = cartItemsIterator.next();
                this.logCartItemDetail(cartItem);

                // Pricing service is expected to calculate prices for only products (not things like shipping charges)
                if(cartItem.getType() == CartExtension.SalesItemTypeEnum.PRODUCT)
                {
                    skus.add(cartItem.getSku());
                    cartItems.add(cartItem);
                }
            }

            Map<String, PricingDataFromExternalService> pricingDataMap = retrievePriceData(skus);

            if(pricingDataMap == null)
            {
                // No data returned means there is an issue with underlying 3rd party service. Populate generic error message for the Buyer.
                CartExtension.CartValidationOutput cvo = new CartExtension.CartValidationOutput(
                CartExtension.CartValidationOutputTypeEnum.PRICING,
                CartExtension.CartValidationOutputLevelEnum.ERROR);
                cvo.setMessage('We are not able to process your cart. Please contact support.');
                cart.getCartValidationOutputs().add(cvo);
                System.debug('### calculate in CartCalcPricingDefault did not receive data');
                return;
            }

            applyPricesToCartItems(cart, cartItems.iterator(), pricingDataMap);
        }
        catch (Exception e)
        {
            /*
            This is an example of throwing special type of Exception (CartCalculateRuntimeException).
            Throwing this exception causes the rollback of all previously applied changes to the cart (in scope of given request)
            and may not always be the best choice.
            */
            System.debug('### Error trapped: calculate in CartCalcPricingDefault. Message: "' + e.getMessage() + '" Stack Trace: "' + e.getStackTraceString() + '" Exception: "' + e.toString() + '"');

            // Rethrow only when configured for it
            if(BUBBLE_EXCEPTIONS)
            {
                throw new CartExtension.CartCalculateRuntimeException('An integration error occurred in COMPUTE_PRICES. Contact your admin', e);
            }
        }

        System.debug('### calculate in CartCalcPricingDefault complete.');
    }

    /**
    * @description Returns an iterator instance for Cart Items that need price calculations.
    *
    * @param cart In memory representation of the Cart
    * @param optionalBuyerActionDetails The latest set of changes applied to the Cart by the Buyer
    *
    * @return <<Iterator<CartExtension.CartItem>>>
    */
    private Iterator<CartExtension.CartItem> clearErrorsAndGetCartItemsIterator(CartExtension.Cart cart,
        CartExtension.OptionalBuyerActionDetails optionalBuyerActionDetails)
    {

        System.debug('### clearErrorsAndGetCartItemsIterator in CartCalcPricingDefault started...');

        CartExtension.CartValidationOutputList cartValidationOutputs = cart.getCartValidationOutputs();

        if (!optionalBuyerActionDetails.isPresent() || optionalBuyerActionDetails.get().isCheckoutStarted())
        {
            // Remove all CVOs of PRICING type since we are going to reprice all cart items.
            removeAllCVOsOfType(cart, CartExtension.CartValidationOutputTypeEnum.PRICING);
            return cart.getCartItems().iterator();
        }

        // Get the list of changed cart items from BuyerActionDetails
        List<CartExtension.CartItem> cartItemsToCalculatePrice = new List<CartExtension.CartItem>();
        List<CartExtension.CartItemChange> cartItemChanges = optionalBuyerActionDetails.get().getCartItemChanges();

        for (CartExtension.CartItemChange cartItemChange : cartItemChanges)
        {
            CartExtension.OptionalCartItem optionalCartItem = cartItemChange.getChangedItem();

            if (optionalCartItem.isPresent())
            {
                CartExtension.CartItem cartItem = optionalCartItem.get();
                cartItemsToCalculatePrice.add(cartItem);
                // Remove CVOs related to the changed cart item, but leave other PRICING related CVOs.
                removeCVOsOfTypeRelatedTo(cart, CartExtension.CartValidationOutputTypeEnum.PRICING, cartItem);
            }
        }

        System.debug('### clearErrorsAndGetCartItemsIterator in CartCalcPricingDefault complete.');
        return cartItemsToCalculatePrice.iterator();
    }


    private void removeAllCVOsOfType(CartExtension.Cart cart, CartExtension.CartValidationOutputTypeEnum type)
    {
        System.debug('### removeAllCVOsOfType in CartCalcPricingDefault started...');

        CartExtension.CartValidationOutputList cartValidationOutputList = cart.getCartValidationOutputs();

        for (Integer i = (cartValidationOutputList.size() - 1); i >= 0; i--)
        {
            CartExtension.CartValidationOutput cvo = cartValidationOutputList.get(i);

            if (cvo.getType() == type)
            {
                cartValidationOutputList.remove(cvo);
            }
        }

        System.debug('### removeAllCVOsOfType in CartCalcPricingDefault complete.');

    }

    private void removeCVOsOfTypeRelatedTo(CartExtension.Cart cart, CartExtension.CartValidationOutputTypeEnum type, CartExtension.CartItem cartItem)
    {
        System.debug('### removeCVOsOfTypeRelatedTo in CartCalcPricingDefault started...');

        if (cartItem.getId() == null)
        {
            System.debug('### removeCVOsOfTypeRelatedTo in CartCalcPricingDefault complete (cartItem.getId() == null).');
            return;
        }

        CartExtension.CartValidationOutputList cartValidationOutputList = cart.getCartValidationOutputs();

        // Reverse loop accounting for one-offs due to collection size changes
        for (Integer i = (cartValidationOutputList.size() - 1); i >= 0; i--)
        {
            CartExtension.CartValidationOutput cvo = cartValidationOutputList.get(i);

            if (cvo.getRelatedEntityId() == null)
            {
                continue;
            }

            if (cvo.getType() == type && cvo.getRelatedEntityId() == cartItem.getId())
            {
                cartValidationOutputList.remove(cvo);
            }
        }

        System.debug('### removeCVOsOfTypeRelatedTo in CartCalcPricingDefault complete.');
    }

    /**
     * In the real world you would very likely NOT use a SKU, but instead use a Product Code which is more universal. SKUs are
     * Stock Keeping Units which are more a function of inventory, usually where the item is located, not necessarily the item's
     * definition in the domain.
     */
    private Map<String, PricingDataFromExternalService> retrievePriceData(Set<String> skus)
    {
        System.debug('### retrievePriceData in CartCalcPricingDefault started...');
        Map<String, PricingDataFromExternalService> pricingDataReturned = (USE_EXTERNAL_SERVICE)
            ? getPricingFromExternalService(skus)
            : getPricingFromStaticResponse(skus);
        System.debug('### retrievePriceData in CartCalcPricingDefault complete.');
        return pricingDataReturned;
    }

    /**
    * Handles pricing data response by external or static response and sets it to cart items.
    */
    private void applyPricesToCartItems(CartExtension.Cart cart, Iterator<CartExtension.CartItem> cartItemsIterator, Map<String, PricingDataFromExternalService> lineItemIdToPricingDetailsMap)
    {
        System.debug('applyPricesToCartItems in CartCalcPricingDefault started...');

        while (cartItemsIterator.hasNext())
        {
            CartExtension.CartItem cartItem = cartItemsIterator.next();

            if(lineItemIdToPricingDetailsMap.get(cartItem.getSku()) == null)
            {
                // No price available for the SKU in the Cart. Populate error message for the Buyer.
                CartExtension.CartValidationOutput cvo = new CartExtension.CartValidationOutput(CartExtension.CartValidationOutputTypeEnum.PRICING,
                    CartExtension.CartValidationOutputLevelEnum.ERROR, cartItem);
                cvo.setMessage('### No price available for the SKU in the Cart.');
                cart.getCartValidationOutputs().add(cvo);
                System.debug('### No price available for the SKU: ' + cartItem.getSku());
                continue;
            }

            setPricingFieldsOnCart(cartItem, lineItemIdToPricingDetailsMap.get(cartItem.getSku()));
        }

        System.debug('applyPricesToCartItems in CartCalcPricingDefault complete.');
    }

    /**
    * Sets pricing data returned by external service to Salesforce's CartItem
    */
    private void setPricingFieldsOnCart(CartExtension.CartItem item, PricingDataFromExternalService pricingLineItem)
    {

        System.debug('setPricingFieldsOnCart in CartCalcPricingDefault started...');

        if (pricingLineItem != null)
        {
            item.setSalesPrice(pricingLineItem.getUnitPrice());
            item.setListPrice(pricingLineItem.getListPrice());
            item.setAdjustmentAmount(pricingLineItem.getTotalAdjustmentAmount());
            item.setTotalListPrice(pricingLineItem.getTotalListPrice());
            item.setTotalPrice(pricingLineItem.getTotalPrice());
        }

        System.debug('setPricingFieldsOnCart in CartCalcPricingDefault complete.');
    }

    /**
    * @description This doesn't actually make an HTTP call, but it mocks the JSON response of an external Pricing
    * Service.
    *
    * @param skus A set of SKUs to get pricing data
    *
    * @return Map containing PricingData for each SKU passed into this method
    */
    private Map<String, PricingDataFromExternalService> getPricingFromExternalService(Set<String> skus)
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
        return (Map<String, PricingDataFromExternalService>) JSON.deserialize(r.getBody(), Map<String, PricingDataFromExternalService>.class);
    }

    /**
    * Returns a static pricing data map for all products.
    */
    private Map<String, PricingDataFromExternalService> getPricingFromStaticResponse(Set<String> skus)
    {
        System.debug('### getPricingFromStaticResponse in CartCalcPricingDefault started...');
        Map<String, PricingDataFromExternalService> dataFromExternalService = new Map<String, PricingDataFromExternalService>();

        for(String sku: skus)
        {
            //PricingDataFromExternalService pricingData = new PricingDataFromExternalService(10, 10, 9, 20, 20);
            PricingDataFromExternalService pricingData = null;

            //try
            //{
                pricingData = capricornSamplesStaticPricing.get(sku);

                if(pricingData == null)
                {
                    System.debug('### PRICING DATA NOT FOUND!');
                }

            //}
            //catch(HandledException handledException)
            //{
            //    System.debug('### HandledException caught in getPricingFromStaticResponse. The sku value was: ' + sku + '". Error: "' + handledException + '"');
            //    pricingData = new PricingDataFromExternalService('FALLBACK', PRICE_NOT_FOUND_DEFAULT_VALUE,
            //        PRICE_NOT_FOUND_DEFAULT_VALUE, PRICE_NOT_FOUND_DEFAULT_VALUE, PRICE_NOT_FOUND_DEFAULT_VALUE, PRICE_NOT_FOUND_DEFAULT_VALUE);
            //}

            dataFromExternalService.put(sku, pricingData);
        }

        System.debug('### getPricingFromStaticResponse in CartCalcPricingDefault complete.');
        return dataFromExternalService;
    }

    /**
    * Structure to store pricing data retrieved from external service. This class simplifies our
    * ability to access the data when storing it in Salesforce's CartItem.
    */
    class PricingDataFromExternalService
    {
        private String productCode;
        private Decimal unitPrice;
        private Decimal listPrice;
        private Decimal totalAdjustmentAmount;
        private Decimal totalListPrice;
        private Decimal totalPrice;

        public PricingDataFromExternalService()
        {
            productCode = '';
            unitPrice = CartCalcPricingDefault.ZERO_DECIMAL;
            listPrice = CartCalcPricingDefault.ZERO_DECIMAL;
            totalAdjustmentAmount = CartCalcPricingDefault.ZERO_DECIMAL;
            totalListPrice = CartCalcPricingDefault.ZERO_DECIMAL;
            totalPrice = CartCalcPricingDefault.ZERO_DECIMAL;
        }

        public PricingDataFromExternalService(String productCode, Decimal unitPrice, Decimal listPrice, Decimal totalAdjustmentAmount,
            Decimal totalListPrice, Decimal totalPrice)
        {
            this.productCode = productCode;
            this.unitPrice = unitPrice;
            this.listPrice = listPrice;
            this.totalAdjustmentAmount = totalAdjustmentAmount;
            this.totalListPrice = totalListPrice;
            this.totalPrice = totalPrice;
        }

        public Decimal getUnitPrice()
        {
            return this.unitPrice;
        }

        public Decimal getListPrice()
        {
            return this.listPrice;
        }

        public Decimal getTotalAdjustmentAmount()
        {
            return this.totalAdjustmentAmount;
        }

        public Decimal getTotalListPrice()
        {
            return this.totalListPrice;
        }

        public Decimal getTotalPrice()
        {
            return this.totalPrice;
        }
    }
}