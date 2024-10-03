/**
 * @description       : Example Cart Calculator for Pricing aspects. This class is part of the "Get to Know B2B Commerce for Administrators"
 *                      curriculum in the Salesforce Partner Learning Camp (PLC) and loosely based on the example provided at this URL:
 *                      https://github.com/forcedotcom/commerce-extensibility/blob/releases/248/commerce/domain/pricing/cart/PricingBasicCalculator/PricingCalculatorSample.cls
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
 *                      1. Screaming constants (static final variables) for legibility / consistency
 *                      2. Many additional System.debug entries
 *                      3. Reformatting and alignment for legibility
 *                      4. Superfluous constructor removed in favor of a constant DEMO_USE_EXTERNAL_SERVICE
 *                      5. Added PRICE_NOT_FOUND_DEFAULT_VALUE for fallback when price isn't found
 *                      6. Added BUBBLE_EXCEPTIONS for configurability
 *                      7. Added LOG_CART_DETAIL_ACTIVE and LOG_CART_ITEM_DETAIL_ACTIVE with methods for additional diagnostics
 *                      8. Introduced the Capricorn sample product price map for local calls (when DEMO_USE_EXTERNAL_SERVICE is false)
 *                      9. WIP - Added a productCode property to PricingDataStructure structure so we can perform a lookup
 *                      10. WIP - Added a REST call for WebStore pricing data to drive the point home
 *                      11. Added more comments
 *                      12. Some refactoring to remove complexity
 *
 * @author            : Tom Zarr
 * @group             : Salesforce Commerce Partner Delivery Success (2024)
 * @last modified on  : 10-02-2024
 * @last modified by  : Tom Zarr
**/

public class CartCalcPricingDefault extends CartExtension.PricingCartCalculator
{
    // ======== Start Demonstration and Behavioral Settings ======== //

    /*  For demostration purposes only: Set this to true to see a networked call take place against your org,
    false to pull static data from the Capricorn sample products */
    private static final Boolean DEMO_USE_EXTERNAL_SERVICE = false;

    /*  For demostration purposes only: Set this to true to leave the last Capricorn sample out of the mapping
    to demonstrate how a missing pricing is handled. */
    private static final Boolean DEMO_MISSING_PRICE_ITEM = true;

    // Set this to true to rethrow the error in the catch block
    private static final Boolean BUBBLE_EXCEPTIONS = true;

    // Supports a default value for pricing when the pricing is not found - for demostration purposes only
    private static final Decimal PRICE_NOT_FOUND_DEFAULT_VALUE = 50.00;

    // When true logs the details of the cart
    private static final Boolean LOG_CART_DETAIL_ACTIVE = true;

    // When true logs the details of the cart item(s)
    private static final Boolean LOG_CART_ITEM_DETAIL_ACTIVE = true;

    // ======== End Behavioral and Demonstration Settings ======== //

    private static final Decimal ZERO_DECIMAL = 0.0;

    // Supports the Capricorn Sample Product Pricing - for demonstration purposes only
    private Map<String, PricingDataStructure> capricornSamplesStaticPricing;

    /**
    * @description All classes extending CartExtension.AbstractCartCalculator must have a default constructor defined
    */
    public CartCalcPricingDefault()
    {
        super();
        capricornSamplesStaticPricing = new Map<String, PricingDataStructure>();
        // Note on the PricingDataStructure ctor's parameters: (productCode, unitPrice, listPrice, totalAdjustmentAmount, totalListPrice, totalPrice)
        // (String quantity, String productCode, Decimal listPrice, Decimal lineTotalAmount)
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

        // Couldn't find documentation saying this is a performance hit like in Java or C# so I'm going with it for now
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

        // Couldn't find documentation saying this is a performance hit like in Java or C# so I'm going with it for now
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

            Map<String, PricingDataStructure> pricingDataMap = retrievePriceData(skus);

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
    private Map<String, PricingDataStructure> retrievePriceData(Set<String> skus)
    {
        System.debug('### retrievePriceData in CartCalcPricingDefault started...');
        Map<String, PricingDataStructure> pricingDataReturned = (DEMO_USE_EXTERNAL_SERVICE)
            ? getPricingFromExternalService(skus)
            : getPricingFromStaticResponse(skus);
        System.debug('### retrievePriceData in CartCalcPricingDefault complete.');
        return pricingDataReturned;
    }

    /**
    * Handles pricing data response by external or static response and sets it to cart items.
    */
    private void applyPricesToCartItems(CartExtension.Cart cart, Iterator<CartExtension.CartItem> cartItemsIterator, Map<String, PricingDataStructure> lineItemIdToPricingDetailsMap)
    {
        System.debug('applyPricesToCartItems in CartCalcPricingDefault started...');

        while (cartItemsIterator.hasNext())
        {
            CartExtension.CartItem cartItem = cartItemsIterator.next();
            String sku = cartItem.getSku();
            System.debug('### iterating on sku: "' + sku + '" for result: "' + lineItemIdToPricingDetailsMap.get(sku)  + '"');

            if(lineItemIdToPricingDetailsMap.get(sku) == null)
            {
                // No price available for the SKU in the Cart. Populate error message for the Buyer.
                CartExtension.CartValidationOutput cvo = new CartExtension.CartValidationOutput(CartExtension.CartValidationOutputTypeEnum.PRICING,
                    CartExtension.CartValidationOutputLevelEnum.ERROR, cartItem);
                cvo.setMessage('No price available for the SKU in the Cart.');
                cart.getCartValidationOutputs().add(cvo);
                System.debug('### No price available for the SKU: ' + sku);
                continue;
            }

            setPricingFieldsOnCart(cartItem, lineItemIdToPricingDetailsMap.get(cartItem.getSku()));
        }

        System.debug('applyPricesToCartItems in CartCalcPricingDefault complete.');
    }

    /**
    * Sets pricing data returned by external service to Salesforce's CartItem
    */
    private void setPricingFieldsOnCart(CartExtension.CartItem cartItem, PricingDataStructure pricingLineItem)
    {

        System.debug('setPricingFieldsOnCart in CartCalcPricingDefault started...');

        if (pricingLineItem != null)
        {
            /*
            Basic pricing 101 according to Tom Z:
            This is a very basic example, but it  may help to think of a phsycial tag where someone has crossed
            out the price along with a receipt printout.
            ----------------------------------------------------------------------------------------------------
            List Price: Make the buyer feel as if they're getting a deal by crossing a price out (aka striekthrough price)
            Sales Price = The sale price of the unit (actual charge & less than the list / strikethrough price)
            Total List Price = This is the list price multipled by the quantity
            Total Price = The Sales price multiplied by the quantity
            Unit Adjusted Price With Item Adjustment = The per unit price adjusted for a single item based on all discounts.
            This is the $17.99/item you would see in a stock cart at the line item level.
            */

            Double quantity = cartItem.getQuantity() == null ? 0.00 : cartItem.getQuantity();
            cartItem.setListPrice(pricingLineItem.getListPrice());
            cartItem.setTotalListPrice(pricingLineItem.getListPrice() * quantity);
            cartItem.setSalesPrice(pricingLineItem.getSalesPrice());
            cartItem.setTotalPrice(pricingLineItem.getSalesPrice() * quantity);
            cartItem.setUnitAdjustedPriceWithItemAdj(pricingLineItem.getSalesPrice());
        }

        System.debug('setPricingFieldsOnCart in CartCalcPricingDefault complete.');
    }

    /*
    * This doesn't actually make an HTTP call, but it mocks the JSON response of an external Pricing
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

    /**
     * Returns a static pricing data map for all products. For this example we rely on the capricornSamplesStaticPricing
     * with an option configured in the variable DEMO_MISSING_PRICE_ITEM to demonstrate missing price behavior during
     * cart calculations.
     */
    private Map<String, PricingDataStructure> getPricingFromStaticResponse(Set<String> skus)
    {
        System.debug('### getPricingFromStaticResponse in CartCalcPricingDefault started...');
        Map<String, PricingDataStructure> dataFromExternalService = new Map<String, PricingDataStructure>();

        for(String sku: skus)
        {
            System.debug('#### sku: ' + sku);

            PricingDataStructure pricingData = capricornSamplesStaticPricing.get(sku);

            /*  When there's no pricing data we can try to use a fallback price or let an error show later */
            if(pricingData == null)
            {
                System.debug('#### sku: ' + sku + ' in pricingData == null');

                /*  This code is for demonstrative purposes of a fallback price- not real world code. A better way to
                handle this situation would be to get the price from another source so it's a semi-accurate estimate
                and not an arbitrary value. This also indicates a potential problem with the implementation as you
                can't sell things that aren't priced. */
                if(DEMO_MISSING_PRICE_ITEM)
                {
                    System.debug('#### sku: ' + sku + ' in DEMO_MISSING_PRICE_ITEM');

                    System.debug('### Pricing data not found in getPricingFromStaticResponse with sku value: ' + sku + '". Resorting to default value: "' + PRICE_NOT_FOUND_DEFAULT_VALUE + '"');
                    pricingData = new PricingDataStructure(sku, PRICE_NOT_FOUND_DEFAULT_VALUE, PRICE_NOT_FOUND_DEFAULT_VALUE);
                }
                //else
                //{
                    /*  Push null on to the map - it's dealt with later in the display if a product with missing
                    pricing lives in the cart. Look in the applyPricesToCartItems method and you'll see something
                    like this: cvo.setMessage('No price available for the SKU in the Cart.'); */
                    //dataFromExternalService.put(sku, pricingData);
                //}
            }
            //else
            //{
                // We did get pricing for the SKU so put it in the map
            dataFromExternalService.put(sku, pricingData);
            //}
        }

        System.debug('### getPricingFromStaticResponse in CartCalcPricingDefault complete.');
        return dataFromExternalService;
    }

    /*  Structure to store pricing data retrieved from an external service or static example. This
     *  class simplifies our ability to access the data when storing it in Salesforce's CartItem. */
    class PricingDataStructure
    {
        private String productCode;
        private Decimal salesPrice;
        private Decimal listPrice;

        public PricingDataStructure()
        {
            this.productCode = '';
            this.salesPrice = CartCalcPricingDefault.ZERO_DECIMAL;
            this.listPrice = CartCalcPricingDefault.ZERO_DECIMAL;
        }

        public PricingDataStructure(String productCode, Decimal salesPrice, Decimal listPrice)
        {
            this.productCode = productCode;
            this.salesPrice = salesPrice;
            this.listPrice = listPrice;
        }

        public String getProductCode()
        {
            return this.productCode;
        }

        public Decimal getSalesPrice()
        {
            return this.salesPrice;
        }

        public Decimal getListPrice()
        {
            return this.listPrice;
        }
    }
}