/**
 * @description       : Given a list of store names (for the WebStore entity), check if they are not enabled with both:
 *                          1. Cart Calculat API
 *                          2. Asynchronous Checkout Processing
 *                      and upgrade their configuration.
 *                      NOTE: This script assumes the TSO stores carried down for a particular partner workshop. Be sure to adjust the
 *                      "storeNames" variable appropriately.
 * @author            : Tom Zarr
 * @group             : Salesforce Commerce Partner Delivery Success (2024)
 * @last modified on  : 12-18-2024
 * @last modified by  : Tom Zarr
**/

// True = make upgrade changes | False = scan only
Boolean makeUpgrades = true;

// The list of store names for the WebStore entity to be upgraded to CCA & Async Processing
// List<String> storeNames = new List<String>(String[] {'B2B LWR Enhanced TSO Store','D2C Store from TSO'});
String[] storeNames = new String[]{
    'B2B LWR Enhanced Store from TSO',
    'D2C Store from TSO',
    'B2B LWR Store from TSO'
};

List<WebStore> webStoresForUpgrade = [
    SELECT
    	Id, Name, OptionsCartCalculateEnabled, OptionsCartAsyncProcessingEnabled
    FROM
    	WebStore
    WHERE
    	Name in :storeNames
    	AND (OptionsCartCalculateEnabled = false OR OptionsCartAsyncProcessingEnabled = false)
    ORDER BY
    	Name ASC
];

System.debug(webStoresForUpgrade.size() + ' candidate stores for upgrade found by name in provided list of ' + storeNames.size() + ' names.');

if(webStoresForUpgrade != null && webStoresForUpgrade.size() > 0 ) {
    System.debug('Scanning CCA and Async settings for WebStore(s)...');

    for(WebStore webStore : webStoresForUpgrade) {
        webStore.OptionsCartCalculateEnabled = true;
        webStore.OptionsCartAsyncProcessingEnabled = true;
    }

    if(makeUpgrades) {
        System.debug('Upgrading CCA and Async settings for WebStore(s)...');
        update webStoresForUpgrade;
    }
}

System.debug('Script complete!');