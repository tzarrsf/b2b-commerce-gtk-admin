/**
 * @description       : This code is an execute anonymous script that populates inventory levels for products in a store.
 * 						using some randomization. It allows you specify which products should have a level of 0 and specify
 * 						minimum and maximum amounts for products by Code or SKU.
 * @author            : Tom Zarr
 * @group             : Salesforce Commerce Partner Delivery Success (2024)
 * @last modified on  : 07-22-2025
 * @last modified by  : Tom Zarr
**/

// -------- Start user settings -------- //

String storeName = 'B2B Store'; // The store name with products needing inventory levels
String priceBookName = storeName + ' Price Book'; // The store's oprice book name
String locationId = 'B2BStore_Warehouse'; // The locationId in OCI for the inventory levels
Integer maxLevelForAny = 250; // Max level anything can be set at for onhand, future1 or future2 if not mapped

// Products by SKU that should have on hand set to 0
List<String> zeroLevelStockKeepingUnits = new List<String>{'123456', '654321'};
// Products by CODE that should have on hand set to 0
List<String> zeroLevelProductCodes = new List<String>{'123456', '654321'};

// If a product sku is mapped here by SKU its entry supercedes maxLevelForAny
List<Map<String, Integer>> maxLevelsByStockKeepingUnitList = new List<Map<String, Integer>>{
    new Map<String, Integer>{'123456' => 5},
    new Map<String, Integer>{'654321' => 5}
};
Map<String, Integer> maxLevelsByStockKeepingUnit = new Map<String, Integer>();
for (Map<String, Integer> entry : maxLevelsByStockKeepingUnitList) {
    for (String key : entry.keySet()) {
        maxLevelsByStockKeepingUnit.put(key, entry.get(key));
    }
}

// If a product code is mapped here by CODE its entry supercedes maxLevelForAny
List<Map<String, Integer>> maxLevelsByProductCodeList = new List<Map<String, Integer>>{
    new Map<String, Integer>{'123456' => 5},
    new Map<String, Integer>{'654321' => 5}
};
Map<String, Integer> maxLevelsByProductCode = new Map<String, Integer>();
for (Map<String, Integer> entry : maxLevelsByProductCodeList) {
    for (String key : entry.keySet()) {
        maxLevelsByProductCode.put(key, entry.get(key));
    }
}

Integer safetyStockMinPercentage = 5; // Min percentage of on hand to set as safety stock
Integer safetyStockMaxPercentage = 12; // Max percentage of on hand to set as safety stock
Integer effectiveDaysBeforeNowMin = 1; // Min days BEFORE now to use for effectiveDate
Integer effectiveDaysBeforeNowMax = 8; // Max days BEFORE now to use for effectiveDate
Integer future1daysMin = 7; // Min days AFTER today to use for future1Date
Integer future1daysMax = 15; // Max days AFTER today to use for future1Date
Integer future2daysFromFuture1 = 7; // Min days AFTER today + future1 to use for future2Date
Integer future2daysFromFuture1Max = 21; // Max days AFTER today + future1 to use for future2Date

// -------- End user settings -------- //

DateTime now = System.now();
Integer minLevelForAny = 1;
String groupEligibilityExclusion = '';

// Fetch Product2 records for the store
List<Product2> products = [
    SELECT Id, Name, StockKeepingUnit, ProductCode
    FROM Product2
    WHERE Id IN (
        SELECT Product2Id
        FROM PricebookEntry
        WHERE Pricebook2.Name = :priceBookName
    )
    AND (NOT StockKeepingUnit = '9999999')
    AND (NOT StockKeepingUnit LIKE 'OMS%')
];

// Prepare CSV string
String csvData = 'Location ID,SKU,Quantity On Hand,Safety Stock,Effective Date,Future Date 1,Future Quantity 1,Future Date 2,Future Quantity 2,Group Eligibility Exclusion\n';

System.debug('### products count: ' + products.size());

// Loop through products
for (Product2 p : products) {
    String sku = p.StockKeepingUnit;
    String productCode = p.ProductCode;

    // Integer quantityOnHand = Integer.MIN_VALUE;
	Integer quantityOnHand = -1;
    Integer safetyStock = 0;

    if (zeroLevelStockKeepingUnits.contains(sku) || zeroLevelProductCodes.contains(productCode)) {
        quantityOnHand = 0;
    } else {
        quantityOnHand = Math.round(Math.random() * (maxLevelForAny - minLevelForAny)) + minLevelForAny;
        Integer percent = Math.round(Math.random() * (safetyStockMaxPercentage - safetyStockMinPercentage)) + safetyStockMinPercentage;
        safetyStock = Math.floor((Decimal.valueOf(quantityOnHand) * percent) / 100).intValue();
    }

    Integer randomEffectiveDaysBefore = Math.round(Math.random() * (effectiveDaysBeforeNowMax - effectiveDaysBeforeNowMin)) + effectiveDaysBeforeNowMin;
    DateTime effectiveDate = now.addDays(-randomEffectiveDaysBefore);

    Integer randomFuture1days = Math.round(Math.random() * (future1daysMax - future1daysMin)) + future1daysMin;
    DateTime futureDate1 = now.addDays(randomFuture1days);

    Integer randomFuture2daysFromFuture1 = Math.round(Math.random() * (future2daysFromFuture1Max - future2daysFromFuture1)) + future2daysFromFuture1;
    Integer future2daysTotal = randomFuture1days + randomFuture2daysFromFuture1;
    DateTime futureDate2 = now.addDays(future2daysTotal);

    Integer futureQuantity1 = Math.round(Math.random() * (maxLevelForAny - minLevelForAny)) + minLevelForAny;
    Integer futureQuantity2 = futureQuantity1;

    if (maxLevelsByStockKeepingUnit.containsKey(sku)) {
        futureQuantity1 = Math.round(Math.random() * (maxLevelsByStockKeepingUnit.get(sku) - minLevelForAny)) + minLevelForAny;
        futureQuantity2 = Math.round(Math.random() * (maxLevelsByStockKeepingUnit.get(sku) - minLevelForAny)) + minLevelForAny;
    }
    if (maxLevelsByProductCode.containsKey(productCode)) {
        futureQuantity1 = Math.round(Math.random() * (maxLevelsByProductCode.get(productCode) - minLevelForAny)) + minLevelForAny;
        futureQuantity2 = Math.round(Math.random() * (maxLevelsByProductCode.get(productCode) - minLevelForAny)) + minLevelForAny;
    }

    TimeZone tz = UserInfo.getTimeZone();
	Integer offsetMins = tz.getOffset(now) / (1000 * 60);
	String offsetSign = offsetMins >= 0 ? '+' : '-';
	Integer absOffsetMins = Math.abs(offsetMins);

	Integer offsetHours = absOffsetMins / 60;
	Integer offsetMinutes = Math.mod(absOffsetMins, 60);

	// Manual zero-padding
	String offsetHH = (offsetHours < 10 ? '0' : '') + String.valueOf(offsetHours);
	String offsetMM = (offsetMinutes < 10 ? '0' : '') + String.valueOf(offsetMinutes);
	String offsetFormatted = offsetSign + offsetHH + ':' + offsetMM;

	// Format dates with fake microseconds and time zone
	String effectiveDateStr = effectiveDate.format('yyyy-MM-dd\'T\'HH:mm:ss.SSS') + '000' + offsetFormatted;
	String futureDate1Str = futureDate1.format('yyyy-MM-dd\'T\'HH:mm:ss.SSS') + '000' + offsetFormatted;
	String futureDate2Str = futureDate2.format('yyyy-MM-dd\'T\'HH:mm:ss.SSS') + '000' + offsetFormatted;

	// Now build the row
	String row = String.join(new List<String>{
		locationId,
		sku,
		String.valueOf(quantityOnHand),
		String.valueOf(safetyStock),
		effectiveDateStr,
		futureDate1Str,
		String.valueOf(futureQuantity1),
		futureDate2Str,
		String.valueOf(futureQuantity2),
		groupEligibilityExclusion
	}, ',');

    csvData += row + '\n';
}

// Create ContentVersion to store CSV
ContentVersion cv = new ContentVersion();
cv.PathOnClient = 'product_stock_data.csv';
cv.Title = 'Product Stock Data';
cv.VersionData = Blob.valueOf(csvData);
insert cv;

// Query ContentVersion Id to get ContentDocumentId
cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

// Generate downloadable link
String baseUrl = URL.getOrgDomainUrl().toExternalForm();
String downloadLink = baseUrl + '/sfc/servlet.shepherd/document/download/' + cv.ContentDocumentId;
//String downloadLink = baseUrl + '/' + cv.ContentDocumentId;
System.debug('Download your CSV file here: ' + downloadLink);