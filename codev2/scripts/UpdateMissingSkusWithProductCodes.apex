/**
 * @description       : This code is a simple script to populate products Codes with their SKUs
 * @author            : Tom Zarr
 * @group             : Salesforce Commerce Partner Delivery Success (2024)
 * @last modified on  : 07-21-2025
 * @last modified by  : Tom Zarr
**/

List<Product2> productsSansSkus = [SELECT Id, Name, ProductCode, IsActive, StockKeepingUnit FROM Product2 where StockKeepingUnit = null];

for(Product2 product : productsSansSkus)
{
    System.debug('Setting ProductCode for Name: "' + product.Name + '" and Id: "' + product.Id + '" to: "' + product.ProductCode + '"');
    product.ProductCode = product.StockKeepingUnit;
}

update productsSansSkus;