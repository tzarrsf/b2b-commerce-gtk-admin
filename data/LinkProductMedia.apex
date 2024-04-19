List<ElectronicMediaGroup> mediaGroups = [
    SELECT Id, DeveloperName
    FROM ElectronicMediaGroup
    WHERE DeveloperName IN ('productDetailImage', 'productListImage')
    ORDER BY DeveloperName ASC
];

Set<Id> productsWithImages = new Set<Id>();
for (AggregateResult res : [SELECT ProductId FROM ProductMedia GROUP BY ProductId]) {
    productsWithImages.add((Id) res.get('ProductId')); // avoid matching products that already have images
}

List<Product2> products = [SELECT Id, Name 
    FROM Product2 
    WHERE StockKeepingUnit != NULL 
    AND Id NOT IN :productsWithImages
    LIMIT 10000];

Set<String> imageNames = new Set<String>();
for (Product2 p : products) {  
        
    imageNames.add(p.Name);
}

Map<String, Id> mediaRecordIdsByName = new Map<String, Id>();
for (ManagedContentVariant mcv : [
    SELECT ManagedContentId, ManagedContent.Name
    FROM ManagedContentVariant
    WHERE ManagedContent.Name IN :imageNames AND IsPublished = TRUE]) {

    mediaRecordIdsByName.put(mcv.ManagedContent.Name, mcv.ManagedContentId);
}

List<ProductMedia> productMediaToBeCreated = new List<ProductMedia>();
for (Product2 p : products) {
    Id mediaContentId = mediaRecordIdsByName.get(p.Name);
    if (mediaContentId != null) {
        productMediaToBeCreated.add(
            new ProductMedia(
                ElectronicMediaGroupId = mediaGroups[0].Id, // product detail image
                ElectronicMediaId = mediaContentId,
                ProductId = p.Id
            )
        );
        productMediaToBeCreated.add(
            new ProductMedia(
                ElectronicMediaGroupId = mediaGroups[1].Id, // product list image
                ElectronicMediaId = mediaContentId,
                ProductId = p.Id
            )
        );
    }
}

Database.insert(productMediaToBeCreated, false);