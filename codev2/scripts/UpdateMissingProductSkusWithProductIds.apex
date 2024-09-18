/**
 * @description       : This code is a simple script to populate products missing SKUs with their Id 
 * @author            : Tom Zarr
 * @group             : Salesforce Commerce Partner Delivery Success (2024)
 * @last modified on  : 09-16-2024
 * @last modified by  : Tom Zarr
**/

List<Product2> productsSansSkus = [SELECT Id, Name, IsActive, StockKeepingUnit FROM Product2 where StockKeepingUnit = null];

for(Product2 product : productsSansSkus)
{
    System.debug('Setting StockKeepingUnit for Name: "' + product.Name + '" and Id: "' + product.Id + '" to: "' + product.Id + '"');
    product.StockKeepingUnit = product.Id;
}

update productsSansSkus;