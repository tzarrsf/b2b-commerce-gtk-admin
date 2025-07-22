/**
 * @description       : This code is a simple script to populate products missing ProductCode with their StockKeepingUnit.
 * @author            : Tom Zarr
 * @group             : Salesforce Commerce Partner Delivery Success (2024)
 * @last modified on  : 07-21-2025
 * @last modified by  : Tom Zarr
**/

List<Product2> productsSansCodes = [SELECT Id, Name, IsActive, ProductCode, StockKeepingUnit FROM Product2 where ProductCode = null and StockKeepingUnit <> '9999999'];

for(Product2 product : productsSansCodes)
{
    System.debug('Setting ProductCode for Name: "' + product.Name + '" and Id: "' + product.Id + '" to: "' + product.StockKeepingUnit + '"');
    product.ProductCode = product.StockKeepingUnit;
}

update productsSansCodes;