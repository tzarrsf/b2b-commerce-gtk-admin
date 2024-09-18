/**
* @description This is a sample orchestrator that calls the pricing and tax calculators only.
* This class must extend CartExtension.CartCalculate and must be linked to the orchestrator extension point (Commerce_Domain_Cart_Calculate).
* Calculates pricing and promotions for operations: Add product to cart, remove product from cart, edit cart item quantity.
* Calculates taxes for select delivery method operation.
*/
global class CartOrchestrator extends CartExtension.CartCalculate
{

    /**
     * @description All classes extending CartExtension.CartCalculate must have a default constructor defined
     */
    global CartOrchestrator()
    {
        System.debug('CartOrchestrator ctor');
    }

    /**
     * @description Constructor used by unit tests only. See <<CartCalculateSampleUnitTest>>.
     * @param apexExecutor Executor which executes various calculators. Can be used to stub calculation results or delegate calculations to actual Calculator. See <<CartCalculateExecutorMock>>.
     */
    global CartOrchestrator(final CartExtension.CartCalculateExecutorMock apexExecutor)
    {
        // Must call super constructor in order for provided Executor to be used for calculations
        super(apexExecutor);
    }

    // Each orchestrator must override this calculate method.
    global virtual override void calculate(CartExtension.CartCalculateOrchestratorRequest request)
    {
        CartExtension.Cart cart = request.getCart();

        // Use BuyerActions to decide which calculators to invoke
        CartExtension.BuyerActions buyerActions = request.getBuyerActions();
        boolean runPricing = buyerActions.isCheckoutStarted() || buyerActions.isCartItemChanged();
        boolean runTaxes = buyerActions.isDeliveryGroupChanged() || buyerActions.isDeliveryMethodSelected();

        // OptionalBuyerActionDetails can be used to optimize the various calculators that are invoked
        CartExtension.CartCalculateCalculatorRequest calculatorRequest = new CartExtension.CartCalculateCalculatorRequest(cart, request.getOptionalBuyerActionDetails());

        if (runPricing)
        {
            System.debug('### runPricing');
            prices(calculatorRequest);

            if (hasErrorLevelCartValidationOutput(cart.getCartValidationOutputs(), CartExtension.CartValidationOutputTypeEnum.PRICING))
            {
                return;
            }
        }

        if (runTaxes)
        {
            System.debug('### runTaxes');
            taxes(calculatorRequest);
        }
    }

    // This function evaluates whether there are errors in the CVO of a specific calculator type.
    private Boolean hasErrorLevelCartValidationOutput(CartExtension.CartValidationOutputList cartValidationOutputs,
        CartExtension.CartValidationOutputTypeEnum cartValidationOutputType)
    {
        Iterator<CartExtension.CartValidationOutput> iterator = cartValidationOutputs.iterator();

        while (iterator.hasNext())
        {
            CartExtension.CartValidationOutput cvo = iterator.next();

            Boolean cvoContainsCalculatorError = cvo.getType() == cartValidationOutputType
                && cvo.getLevel() == CartExtension.CartValidationOutputLevelEnum.ERROR;

            if (cvoContainsCalculatorError)
            {
                return true;
            }
        }

        return false;
    }
}