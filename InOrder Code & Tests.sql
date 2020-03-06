#---------------------------------------------------------------------------------------------------------------------------------------------
#Part1: Create Database and tables.

#################################### Create Database ########################################
DROP DATABASE IF EXISTS InOrderSystem;
CREATE DATABASE InOrderSystem;
USE InOrderSystem;

#################################### Create tables ########################################

# Drop tables if exist
DROP TABLE IF EXISTS InventoryRecord;
DROP TABLE IF EXISTS PriceHistory;
DROP TABLE IF EXISTS OrderRecord;
DROP TABLE IF EXISTS Promotion;
DROP TABLE IF EXISTS Product;
DROP TABLE IF EXISTS Orders;
DROP TABLE IF EXISTS Customer;
DROP TABLE IF EXISTS NorthAmericaStates;

# Create Product table
CREATE TABLE Product(
    Name VARCHAR(100) NOT NULL CHECK (Name != ''),
    Description VARCHAR(2000),
    Listed BOOLEAN NOT NULL DEFAULT FALSE,
    SKU VARCHAR(12) NOT NULL CHECK(SKU REGEXP '[A-Z]{2}-[0-9]{6}-[0-9A-Z]{2}'),
    PRIMARY KEY(SKU));

# Create InventoryRecord table
CREATE TABLE InventoryRecord(
    Units INT  NOT NULL CHECK (Units >= 0),
    Price DOUBLE(40,2)  NOT NULL CHECK (Price >= 0),
    Discount DOUBLE(3,2) default 1, CHECK(Discount >= 0 and Discount <= 1),
    SKU VARCHAR(12) NOT NULL CHECK(SKU REGEXP '[A-Z]{2}-[0-9]{6}-[0-9A-Z]{2}'),
    PreOrderUnit INT NOT NULL DEFAULT 0 CHECK (PreOrderUnit >= 0),
    PreOrderUnitSold INT NOT NULL DEFAULT 0 CHECK (PreOrderUnitSold >= 0),
    PRIMARY KEY (SKU),
    FOREIGN KEY (SKU) REFERENCES Product(SKU) ON DELETE CASCADE);

# Create PriceHistory table
CREATE TABLE PriceHistory(
    SKU VARCHAR(12) NOT NULL CHECK(SKU REGEXP '[A-Z]{2}-[0-9]{6}-[0-9A-Z]{2}'),
    DateTime DATETIME NOT NULL,
    FinalPrice DOUBLE(40,2) NOT NULL CHECK (FinalPrice >= 0),
    PRIMARY KEY(SKU, DateTime),
    FOREIGN KEY (SKU) REFERENCES Product(SKU) ON DELETE CASCADE);

# Create Customer table
CREATE TABLE Customer(
    CustomerID INT NOT NULL,
    Name VARCHAR(20) NOT NULL,
    Address VARCHAR(100) NOT NULL,
    City VARCHAR(20) NOT NULL,
    State VARCHAR(20) NOT NULL,
    Country VARCHAR(20) NOT NULL,
    PostalCode VARCHAR(10) NOT NULL,
    PRIMARY KEY (CustomerID));

# Create Orders table
CREATE TABLE Orders(
    CustomerID INT NOT NULL,
    OrderID VARCHAR(40) NOT NULL,
    OrderDate DATETIME NOT NULL,
    ShipmentDate DATETIME,
    isCancelled BOOLEAN DEFAULT FALSE,
    TotalPrice DOUBLE(40,2) CHECK (TotalPrice >= 0),
    PRIMARY KEY(OrderID),
    FOREIGN KEY(CustomerID) REFERENCES Customer(CustomerID) ON DELETE CASCADE);


# Create OrderRecord Table
CREATE TABLE OrderRecord(
    OrderID VARCHAR(40) NOT NULL,
    Units INT NOT NULL CHECK (Units >= 0),
    Price DOUBLE(40,2) NOT NULL CHECK (Price >= 0),
    SKU VARCHAR(12) NOT NULL CHECK(SKU REGEXP '[A-Z]{2}-[0-9]{6}-[0-9A-Z]{2}'),
    PRIMARY KEY (OrderID, SKU),
    FOREIGN KEY (SKU) REFERENCES Product(SKU) ON DELETE CASCADE,
    FOREIGN KEY (OrderID) REFERENCES Orders(OrderID) ON DELETE CASCADE);

# Create table Promotion with fields orderID and amount
CREATE TABLE Promotion(
    orderID VARCHAR(40) NOT NULL,
    amount DOUBLE(40,2) CHECK (amount >= 0),
    PRIMARY KEY(orderID),
    FOREIGN KEY(orderID) REFERENCES Orders(orderID) ON DELETE CASCADE);

# Create table NorthAmericaStates with US and Canada states for checking valid customer info
CREATE TABLE NorthAmericaStates(
    Country VARCHAR(40) NOT NULL,
    State VARCHAR(40) NOT NULL,
    taxRate  DOUBLE(8,5) NOT NULL DEFAULT 0 CHECK(taxRate >= 0 and taxRate <= 1),
    PRIMARY KEY(Country, State));

#################################### Create triggers ########################################

# Promotion trigger: get $50 off when spending $300+
DROP TRIGGER IF EXISTS applyPromotion;
CREATE TRIGGER applyPromotion AFTER UPDATE ON Orders
   FOR EACH ROW
   BEGIN
       IF NEW.TotalPrice >= 300 THEN
           INSERT INTO Promotion VALUES (NEW.OrderID, '50');
       END IF;
   END;

# Unlist a product if unit and preOrderUnit both become zero
DROP TRIGGER IF EXISTS unlistProductIfNotAvailable;
CREATE TRIGGER unlistProductIfNotAvailable AFTER UPDATE ON InventoryRecord
   FOR EACH ROW
   BEGIN
       IF NEW.Units = 0 AND NEW.PreOrderUnit = 0 THEN
           UPDATE Product SET Listed = false
           WHERE SKU = NEW.SKU;
       END IF;
   END;

#---------------------------------------------------------------------------------------------------------------------------------------------
#Part2: Create 27 stored procedures and 2 triggers.
#################################### Create procedures ########################################

#1 createCustomer
#  Create a new customer with given customerID, name, address, city, state, country and postal code.
#  Throw an error message if encounters duplicate primary key or invalid input country or state.
#  Throw a SQLException if any other error occurs.
DROP PROCEDURE IF EXISTS createCustomer;
CREATE PROCEDURE createCustomer(
  inputCustomerID int,
  inputName VARCHAR(20),
  inputAddress VARCHAR(100),
  inputCity VARCHAR(20),
  inputState VARCHAR(20),
  inputCountry VARCHAR(20),
  inputPostalCode VARCHAR(10))
BEGIN
   DECLARE DuplicatePrimaryKey CONDITION FOR 1062;
  DECLARE EXIT HANDLER FOR DuplicatePrimaryKey SELECT 'SQLException: Duplicate Primary Key' Message;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION SELECT 'SQLException encountered' Message;
  IF (inputCountry in (SELECT Country FROM NorthAmericaStates)
          AND inputState in(SELECT STATE FROM NorthAmericaStates WHERE NorthAmericaStates.Country = inputCountry)) THEN
          INSERT INTO Customer(customerID, name, address, city, state, country, postalCode)
          VALUES (inputCustomerID, inputName, inputAddress, inputCity, inputState, inputCountry, inputPostalCode);
  ELSE
      SELECT('Error creating customer, Invalid country or state.') Message;
  END IF;
END;

#2 createProduct
#  Create a new product with given name, description and SKU.
#  Throw an error message if encounters duplicate primary key, invalid SKU or empty name.
#  Throw a SQLException if any other error occurs.
DROP PROCEDURE IF EXISTS createProduct;
CREATE PROCEDURE createProduct(
certainName VARCHAR(100),
certainDescription VARCHAR(2000),
certainSKU VARCHAR(12))
BEGIN
   DECLARE DuplicatePrimaryKey CONDITION FOR 1062;
  DECLARE EXIT HANDLER FOR DuplicatePrimaryKey SELECT 'SQLException: Duplicate Primary Key' Message;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION SELECT 'SQLException encountered' Message;
 IF(certainSKU REGEXP '[A-Z]{2}-[0-9]{6}-[0-9A-Z]{2}' AND certainName != '') THEN
     INSERT INTO Product (name, description, SKU )
     VALUES (certainName, certainDescription, certainSKU);
     INSERT INTO InventoryRecord(SKU, units, price)
     VALUES(certainSKU, 0, 0);
 ELSEIF NOT(certainSKU REGEXP '[A-Z]{2}-[0-9]{6}-[0-9A-Z]{2}') THEN
     SELECT 'SQLException: Invalid SKU.' Message;
 ELSE SELECT 'SQLException: Name cannot be empty string.' Message;
 END IF;
END;

#3 listProduct
#  List a product on the website to make it available for customers, and add current price information into the PriceHistory table.
#  Throw an error message if the product has already been listed, the product cannot be found or the price has not been set.
DROP PROCEDURE IF EXISTS listProduct;
CREATE PROCEDURE listProduct(certainSKU VARCHAR(12))
BEGIN
  IF ((SELECT Listed FROM Product WHERE SKU = certainSKU) = FALSE AND
      (SELECT Price FROM InventoryRecord WHERE SKU = certainSKU) > 0) THEN
      UPDATE InOrderSystem.Product SET listed = TRUE WHERE SKU = certainSKU;
      set @a1 := (SELECT Price FROM InOrderSystem.InventoryRecord WHERE SKU = certainSKU);
      INSERT INTO PriceHistory(SKU, DATETIME, FinalPrice)
      VALUES(certainSKU, NOW(), @a1);
  ELSEIF ((SELECT Listed FROM Product WHERE SKU = certainSKU) = TRUE) THEN
      SELECT('This product has already been listed.') Message;
  ELSE
      SELECT('Cannot list product as the product cannot be found or the price has not been set!') Message;
  END IF;
END;

#4 unlistProduct
#  Unlist a product from the website.
#  Throw an error message if the product has already been unlisted or the product cannot be found.
DROP PROCEDURE IF EXISTS unListProduct;
CREATE PROCEDURE unListProduct(certainSKU VARCHAR(12))
BEGIN
   IF ((SELECT Listed FROM Product WHERE SKU = certainSKU) = TRUE) THEN
       UPDATE InOrderSystem.Product SET listed = FALSE WHERE SKU = certainSKU;
   ELSEIF ((SELECT Listed FROM Product WHERE SKU = certainSKU) = FALSE) THEN
       SELECT('This product has already been unlisted.') Message;
   ELSE
       SELECT('Cannot found the product.') Message;
   END IF;
END;

#5 readListedProducts
#  Display all the listed product names, descriptions, prices, discounts and sale prices to customers.
#  Throw a "Not Found" message if the query output is null.
DROP PROCEDURE IF EXISTS readListedProducts;
CREATE PROCEDURE readListedProducts()
BEGIN
   IF EXISTS(SELECT 1 FROM Product
   WHERE Product.Listed = TRUE) THEN
         SELECT Product.Name,
                Product.Description,
                InventoryRecord.Price,
                InventoryRecord.Discount,
                InventoryRecord.Price * InventoryRecord.Discount AS SalePrice
         FROM Product,
              InventoryRecord
         WHERE Product.SKU = InventoryRecord.SKU
           AND Product.listed = TRUE;
   ELSE
         SELECT ('No such product exists') Message;
   END IF;
END;


#6 searchProductName
#  Search listed products that contains the input string in their names, and display relevant product information.
#  Throw a "Not Found" message if the query output is null.
DROP PROCEDURE IF EXISTS searchProductName;
CREATE PROCEDURE searchProductName(search varchar(100))
BEGIN
   IF EXISTS(SELECT 1 FROM Product
   WHERE Product.Listed = TRUE AND Product.Name LIKE CONCAT('%', search, '%') COLLATE utf8mb4_GENERAL_CI) THEN
         SELECT Product.Name, Product.Description, InventoryRecord.Price, InventoryRecord.Discount,
                InventoryRecord.Price * InventoryRecord.Discount AS SalePrice
         FROM Product, InventoryRecord
         WHERE Product.SKU = InventoryRecord.SKU AND Product.listed = TRUE
           AND Product.Name LIKE CONCAT('%', search, '%') COLLATE utf8mb4_GENERAL_CI;
   ELSE
       SELECT ('No such product exists') Message;
   END IF;
END;


#7 readProductInventory
#  Display all the listed/unlisted product information in table Product and InventoryRecord.
DROP PROCEDURE IF EXISTS readProductInventory;
CREATE PROCEDURE readProductInventory(l boolean)
BEGIN
  SELECT * FROM Product, InventoryRecord WHERE Product.SKU = InventoryRecord.SKU and listed = l;
END;


#8 readAllProductInventory
#  Display all the product information in table Product and InventoryRecord
DROP PROCEDURE IF EXISTS readAllProductInventory;
CREATE PROCEDURE readAllProductInventory()
BEGIN
  SELECT * FROM Product, InventoryRecord WHERE Product.SKU = InventoryRecord.SKU;
END;


#9 readInventorySpecifyingUnit
#  Display all the product information in table Product and InventoryRecord for a specific units range.
#  Throw an error message if beginUnit is larger than endUnit.
#  Throw a "Not Found" message if the query output is null.
DROP PROCEDURE IF EXISTS readInventorySpecifyingUnit;
CREATE PROCEDURE readInventorySpecifyingUnit(beginUnit int, endUnit int)
BEGIN
   IF beginUnit > endUnit THEN
       SELECT ('Invalid unit range') Message;
   ELSE
       IF EXISTS(SELECT 1 FROM InventoryRecord
       WHERE InventoryRecord.Units >= beginUnit AND InventoryRecord.Units <= endUnit) THEN
           SELECT * FROM Product, InventoryRecord WHERE Product.SKU = InventoryRecord.SKU
           AND InventoryRecord.Units >= beginUnit AND InventoryRecord.Units <= endUnit;
       ELSE
           SELECT ('No such product exists') Message;
       END IF;
   END IF;
END;


#10 changeInvertoryUnits
#   Change inventory units of a product.
#   Throw an error message if the inventory units after change is less than 0 or the product cannot been found.
DROP PROCEDURE IF EXISTS changeInventoryUnits;
create procedure changeInventoryUnits( certainSKU VARCHAR(12), inputUnits INT)
BEGIN
 DECLARE t_error INTEGER DEFAULT 0;
 DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET t_error=1;
 START TRANSACTION ;
     IF NOT EXISTS(SELECT 1 FROM Product WHERE certainSKU = Product.SKU) THEN
         SELECT 'Cannot find the input SKU' Message;
     ELSE
         update InventoryRecord set Units = Units + inputUnits where SKU = certainSKU;
     END IF;
     IF t_error = 1 THEN
         ROLLBACK;
         SELECT 'SQLException: invalid input.' Message;
     ELSE
         COMMIT;
     END IF;
END;


#11 changeDiscount
#   Change discount of a product and add the new sale price into PriceHistory table.
#   Throw an error message if the discount after change is not between 0 and 1 or the product cannot be found.
DROP PROCEDURE IF EXISTS changeDiscount;
CREATE PROCEDURE changeDiscount(S VARCHAR(12), d DOUBLE(40,2))
BEGIN
   IF NOT EXISTS(SELECT 1 FROM Product WHERE S = Product.SKU) THEN
         SELECT('Cannot find the input SKU') Message;
  ELSEIF(d < 0 OR d > 1)THEN
      SELECT('SQLException: Discount cannot be negative or greater than 1') Message;
  ELSE
      update InventoryRecord
      set discount = d
      where SKU = S;
      IF ((SELECT Listed FROM Product WHERE SKU = S)) THEN
          SET @a1 := (SELECT d * (SELECT Price FROM InventoryRecord WHERE SKU = S));
          INSERT INTO PriceHistory(SKU, Datetime, FinalPrice) VALUES(S, NOW(),  ROUND(@a1, 2));
      END IF;
          END IF;
END;


#12 changePrice
#   Change price of a product and add the new sale price into PriceHistory table.
#   Throw an error message if the price after change is less than 0 or the product cannot be found.
DROP PROCEDURE IF EXISTS changePrice;
CREATE PROCEDURE changePrice(S VARCHAR(12), p DOUBLE(40,2))
BEGIN
  IF NOT EXISTS(SELECT 1 FROM Product WHERE S = Product.SKU) THEN
      SELECT('Cannot find the input SKU') Message;
  ELSEIF(p < 0)THEN
      SELECT('SQLException: Price cannot be negative');
  ELSE
      update InventoryRecord
      set Price = p
      where SKU = S;
      IF ((SELECT Listed FROM Product WHERE SKU = S)) THEN
          SET @a1 := (SELECT Discount FROM InventoryRecord WHERE SKU = S);
          INSERT INTO PriceHistory(SKU, DateTime, FinalPrice) VALUES(S, NOW(), P * @a1);
      END IF;
  END IF;
END;


#13 readPriceHistory
#   Display all the price history for a given product.
#   Throw a "Not Found" message if the query output is null.
DROP PROCEDURE IF EXISTS readPriceHistory;
CREATE PROCEDURE readPriceHistory(certainSKU VARCHAR(12))
BEGIN
   IF EXISTS(SELECT 1 FROM PriceHistory WHERE SKU = certainSKU) THEN
       SELECT * FROM PriceHistory WHERE SKU = certainSKU;
   ELSE
       SELECT ('No such product exists') Message;
   END IF;
END;


#14 readPriceHistorySpecifyingTime
#   Display all the price history for a given product and specified time range.
#   Throw an error message if startDate is later than endDate.
#   Throw a "Not Found" message if the query output is null.
DROP PROCEDURE IF EXISTS readPriceHistorySpecifyingTime;
CREATE PROCEDURE readPriceHistorySpecifyingTime(certainSKU VARCHAR(12), startTime DATETIME, endTime DATETIME)
BEGIN
   IF startTime > endTime THEN
       SELECT ('Invalid time range') Message;
   ELSE
       IF EXISTS(SELECT 1 FROM PriceHistory
       WHERE SKU = certainSKU) THEN
           SELECT * FROM PriceHistory WHERE SKU = certainSKU AND DateTime >= startTime AND DateTime <= endTime;
       ELSE
           SELECT ('No such product exists') Message;
       END IF;
   END IF;
END;


#15 createOrder
#   Create a new order with given customer ID, order ID and order date.
#   Throw an error message if encounters duplicate primary key or a foreign key constraint fails.
#   Throw a SQLException if any other error occurs.
DROP PROCEDURE IF EXISTS createOrder;
create procedure createOrder( cust INT, oID VARCHAR(40), da DATETIME)
BEGIN
   DECLARE DuplicatePrimaryKey CONDITION FOR 1062;
   DECLARE EXIT HANDLER FOR DuplicatePrimaryKey SELECT 'SQLException: Duplicate Primary Key' Message;
   DECLARE EXIT HANDLER FOR 1452 SELECT 'SQLException: a foreign key constraint fails' Message;
   DECLARE EXIT HANDLER FOR SQLEXCEPTION SELECT 'SQLException encountered' Message;
   IF (oID != '') THEN
       INSERT ignore into orders(customerID, orderID, orderDate) values(cust,oID, da);
   ELSE
       SELECT 'SQLException: OrderID cannot be empty string.' Message;
   END IF;
END;


#16 changePreOrderUnits
#   Change pre-order units of a product.
#   Throw an error message if the pre-order units after change is less than 0 or the product cannot be found.
DROP PROCEDURE IF EXISTS changePreOrderUnits;
create procedure changePreOrderUnits( certainSKU VARCHAR(12), inputPreOrderUnit INT)
BEGIN
DECLARE t_error INTEGER DEFAULT 0;
DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET t_error = 1;
START TRANSACTION;
   IF NOT EXISTS(SELECT 1 FROM Product WHERE certainSKU = Product.SKU) THEN
       SELECT 'Cannot find the input SKU' Message;
   ELSE
       UPDATE InventoryRecord SET preOrderUnit = preOrderUnit + inputPreOrderUnit WHERE SKU = certainSKU;
   END IF;
   IF t_error = 1 THEN
       ROLLBACK;
       SELECT 'SQLException: Invalid input units.' Message;
   ELSE
       COMMIT;
   END IF;
END;


#17 createOrderRecord
#   Create an order record for a certain product in an order.
#   When the order record is created, the price is calculated according to the price and discount in the InventoryRecord table
#   and inventory is automatically reduced. Since we have Units and preOrderUnits, Units is deducted first.
#   When Units becomes 0, preOrderUnits is used and PreOrderUnitsSold is recorded for future reference.
#   Throw an error message and rollback if certainUnits is negative, certainUnits exceeds inventory or any other error happens.
DROP PROCEDURE IF EXISTS createOrderRecord;
create procedure createOrderRecord( inputSKU VARCHAR(12), inputOrderID VARCHAR(40), orderUnits int)
BEGIN
DECLARE t_error INTEGER DEFAULT 0;
DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET t_error=1;
Set @errorType = 0;
start transaction;
    set @unit1 := (select Units from InventoryRecord where SKU = inputSKU);#Units, preOrderUnit
    set @unit2 := (select preOrderUnit from InventoryRecord where SKU = inputSKU);#Units, preOrderUnit
    set @unitPrice:= (select Price*Discount from InventoryRecord where SKU = inputSKU);
    If orderUnits>@unit1+@unit2 THEN
        set @errorType = 1;
    ELSEIF orderUnits<=0 THEN
        set @errorType = 2;
    ELSEIF orderUnits>@unit1 then
        update InventoryRecord set Units = 0 where SKU = inputSKU;
        update InventoryRecord set preOrderUnit = @unit2-(orderUnits-@unit1) where SKU = inputSKU;
        update InventoryRecord set PreOrderUnitSold = orderUnits-@unit1 where SKU = inputSKU;
        insert into OrderRecord(ORDERID, UNITS, PRICE, SKU) VALUES(inputOrderID,orderUnits,@unitPrice,inputSKU);
    ELSE
        update InventoryRecord set Units = @unit1-orderUnits where SKU = inputSKU;
        insert into OrderRecord(ORDERID, UNITS, PRICE, SKU) VALUES(inputOrderID,orderUnits,@unitPrice,inputSKU);
    END IF;
    IF t_error <> 0 or @errorType <> 0 THEN
        ROLLBACK;
        IF @errorType = 1 THEN SELECT 'SQLException: orderUnits can not exceed inventory.';
        ELSEIF @errorType = 2 THEN SELECT 'SQLException: orderUnits can not be negative.';
        ELSE SELECT 'SQLException: Invaild';
        END IF;
    ELSE
        COMMIT;
    END IF;
END;


#18 calculateOrderPrice
#   Calculate total price for a given order ID
#   Throw an error message if the order ID cannot be found.
DROP PROCEDURE  IF EXISTS calculateOrderPrice;
CREATE PROCEDURE calculateOrderPrice(inputOrderID VARCHAR(40))
BEGIN
   IF NOT EXISTS(SELECT 1 FROM Orders WHERE inputOrderID = Orders.OrderID) THEN
      SELECT('Cannot find the input order ID.') Message;
   ELSE
       UPDATE Orders
       SET TotalPrice = (SELECT SUM(PRICE * UNITS) FROM orderRecord WHERE orderID = inputOrderID)
       WHERE OrderID = inputOrderID;
   END IF;
END;


#19 FinalizeOrderPrice
#   Finalize total price for a given order ID after considering promotion amount and tax.
#   Throw an error message if the order ID cannot be found.
DROP PROCEDURE IF EXISTS FinalizeOrderPrice;
CREATE PROCEDURE FinalizeOrderPrice(inputOrderID VARCHAR(40))
BEGIN
   IF NOT EXISTS(SELECT 1 FROM Orders WHERE inputOrderID = Orders.OrderID) THEN
      SELECT('Cannot find the input order ID.') Message;
   ELSE
       SET @a1 := (SELECT customerID FROM Orders WHERE orderID = inputOrderID);
       SET @a2 := (SELECT Country FROM Customer WHERE CustomerID = @a1);
       SET @a3 := (SELECT State FROM Customer WHERE CustomerID = @a1);
       SET @a4 := (SELECT taxRate FROM NorthAmericaStates WHERE Country = @a2 and State = @a3);
       SET @a5 := (SELECT TOTALPRICE FROM Orders WHERE OrderID = inputOrderID);
       IF(inputOrderID in (SELECT OrderID FROM Promotion WHERE OrderID = inputOrderID) AND @a4 > 0) THEN
         SET @a6 := @a5 - (SELECT AMOUNT FROM Promotion WHERE OrderID = inputOrderID);
         SELECT ROUND (@a6 * (1 + @a4), 2) AS finalPrice;
       ELSEIF(@a4 > 0) THEN
         SELECT ROUND(@a5 * (1 + @a4), 2) AS finalPrice;
       ELSE
         SELECT TOTALPRICE FROM Orders AS finalPrice WHERE OrderID = inputOrderID;
       END IF;
   END IF;
END;


#20 createOneOrderWithManyItems
#   An aggregate simulating procedure for placing an order. Assuming only three products can be purchased in one order.
DROP PROCEDURE IF EXISTS createOneOrderWithManyItems;
CREATE PROCEDURE createOneOrderWithManyItems(
    certainCustomerID int, certainOrderID varchar(40), certainOrderDate datetime,
    sku1 varchar(12), units1 int,
    sku2 varchar(12), units2 int,
    sku3 varchar(12), units3 int)
BEGIN
    DECLARE CONTINUE HANDLER FOR 1062 SELECT 'SQLException: Duplicate Primary Key' Message;
    DECLARE CONTINUE HANDLER FOR 1452 SELECT 'SQLException: a foreign key constraint fails' Message;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SELECT 'SQLException encountered' Message;
    CALL createOrder(certainCustomerID,certainOrderID,certainOrderDate);
    CALL createOrderRecord(sku1,certainOrderID,units1);
    CALL createOrderRecord(sku2,certainOrderID,units2);
    CALL createOrderRecord(sku3,certainOrderID,units3);
    CALL calculateOrderPrice(certainOrderID);
    CALL finalizeOrderPrice(certainOrderID);
END;


#21 updateShipmentDate
#   Update shipment date for an order.
#   Throw an error message if the input shipment date is earlier than order date or the order ID cannot be found.
DROP PROCEDURE IF EXISTS updateShipmentDate;
create procedure updateShipmentDate( inputOrderID VARCHAR(40), inputShipmentDate DATETIME)
BEGIN
 IF NOT EXISTS(SELECT 1 FROM Orders WHERE inputOrderID = Orders.OrderID) THEN
      SELECT('Cannot find the input order ID.') Message;
 ELSE
     SET SQL_SAFE_UPDATES = 0;
     SET @orderDate = (select OrderDate from Orders where orderID = inputOrderID);
     IF inputShipmentDate >= @orderDate THEN
         update Orders
         set Orders.shipmentDate = inputShipmentDate
         where orderID = inputOrderID;
     ELSE
         select 'SQLException: invalid ShipmentDate' Message;
     END IF;
 END IF;
END;


#22 cancelOrder
#   Cancel an order.
#   Throw an error message if the order ID cannot be found.
DROP PROCEDURE IF EXISTS cancelOrder;
CREATE PROCEDURE cancelOrder(inputOrderID VARCHAR(40))
BEGIN
   IF NOT EXISTS(SELECT 1 FROM Orders WHERE inputOrderID = Orders.OrderID) THEN
      SELECT('Cannot find the input order ID.') Message;
   ELSE
       If(ISNULL((select ShipmentDate from Orders where OrderID=inputOrderID)))THEN
              update Orders set isCancelled = 1 where orderID = inputOrderID;
          ELSE SELECT 'SQLException: Can not cancel a shipped order.';
       END IF;
   END IF;
END;


#23 calculateTotalRevenue in date range
#   Calculate total revenue for a given time range.
#   Throw an error message if startDate is later than endDate.
DROP PROCEDURE IF EXISTS calculateTotalRevenue;
CREATE PROCEDURE calculateTotalRevenue(startDate datetime, endDate datetime)
BEGIN
   IF (startDate <= endDate) THEN
       SELECT SUM(TotalPrice) as Revenue FROM Orders WHERE (startDate <= OrderDate AND endDate >= OrderDate);
   ELSE
       SELECT('Invalid time range input.') Message;
   END IF;
END;

#24 read customer orders
#   Display all the orders for a given customer ID.
#   Throw an error message if the customer ID cannot be found.
DROP PROCEDURE IF EXISTS readCustomerOrders;
CREATE PROCEDURE readCustomerOrders(certainCustomerID int)
BEGIN
   IF EXISTS(SELECT 1 FROM Orders WHERE CustomerID = certainCustomerID) THEN
            SELECT * FROM Orders WHERE CustomerID = certainCustomerID;
       ELSE
           SELECT ('No such customer exists') Message;
       END IF;
END;


#25 readCustomerOrdersSpecifyingTime
#   Display all the orders for a given customer ID and time range.
#   Throw an error message if startDate is later than endDate or the customer ID cannot be found.
DROP PROCEDURE IF EXISTS readCustomerOrdersSpecifyingTime;
CREATE PROCEDURE readCustomerOrdersSpecifyingTime(certainCustomerID int, startDate datetime, endDate datetime)
BEGIN
   IF startDate > endDate THEN
       SELECT ('Invalid time range') Message;
   ELSE
       IF EXISTS(SELECT 1 FROM Orders WHERE CustomerID = certainCustomerID) THEN
           SELECT * FROM Orders
           WHERE CustomerID = certainCustomerID AND OrderDate >= startDate AND OrderDate <= endDate;
       ELSE
           SELECT ('No such customer exists') Message;
       END IF;
   END IF;
END;


#26 read order detail
#   Display all the product names, prices and units bought for a given order ID.
#   Throw an error message if the order ID cannot be found.
DROP PROCEDURE IF EXISTS readOrderDetail;
CREATE PROCEDURE readOrderDetail(certainOrderID varchar(40))
BEGIN
   IF EXISTS(SELECT 1 FROM Orders WHERE certainOrderID = Orders.OrderID) THEN
        SELECT Product.Name, OrderRecord.Price, OrderRecord.Units FROM OrderRecord, Product, Orders
        WHERE certainOrderID = Orders.OrderID AND Orders.OrderID = OrderRecord.OrderID AND OrderRecord.SKU = Product.SKU;
   ELSE
       SELECT ('No such order exists') Message;
   END IF;
END;

#27 readSpecificProductInventory
#   Display inventory record for a specific product.
#   Throw a "Not Found" message if the query output is null.
DROP PROCEDURE IF EXISTS readSpecificProductInventory;
CREATE PROCEDURE readSpecificProductInventory(certainSKU varchar(12))
BEGIN
    IF EXISTS(SELECT 1 FROM InventoryRecord WHERE SKU = certainSKU)THEN
        SELECT * FROM InventoryRecord WHERE SKU = certainSKU;
    ELSE
        SELECT('Cannot find input SKU') Message;
    END IF;
END;

#  testData
#  this procedure initialize every table with test data for testing purpose.
#  !NOTICE: when trying to run this procedure,
#  a message may pops up right above the Output window asking about deleting all the data in tables
#  please just select 'Excute ALL' or 'Execute'
DROP PROCEDURE IF EXISTS testData;
CREATE PROCEDURE testData()
BEGIN
    DELETE FROM Customer;
    DELETE FROM PriceHistory;
    DELETE FROM InventoryRecord;
    DELETE FROM OrderRecord;
    DELETE FROM Orders;
    DELETE FROM Product;
    DELETE FROM Promotion;
    DELETE FROM NorthAmericaStates;

    INSERT INTO NorthAmericaStates(Country, State, taxRate) VALUES('United States', 'Alaska', 0),
                                                        ('United States', 'Alabama', 0.04),
                                                        ('United States', 'American Samoa', 0),
                                                        ('United States', 'Arizona', 0.056),
                                                        ('United States', 'Arkansas', 0.065),
                                                        ('United States', 'California', 0.0725),
                                                        ('United States', 'Colorado', 0.029),
                                                        ('United States', 'Connecticut', 0.0635),
                                                        ('United States', 'Delaware', 0),
                                                        ('United States', 'District of Columbia', 0.06),
                                                        ('United States', 'Florida', 0.06),
                                                        ('United States', 'Georgia', 0.04),
                                                        ('United States', 'Guam', 0),
                                                        ('United States', 'Hawaii', 0.04),
                                                        ('United States', 'Idaho', 0.06),
                                                        ('United States', 'Illinois', 0.0625),
                                                        ('United States', 'Indiana', 0.07),
                                                        ('United States', 'Iowa', 0.06),
                                                        ('United States', 'Kansas', 0.065),
                                                        ('United States', 'Kentucky', 0.06),
                                                        ('United States', 'Louisiana', 0.0445),
                                                        ('United States', 'Maine', 0.055),
                                                        ('United States', 'Maryland', 0.06),
                                                        ('United States', 'Massachusetts', 0.0625),
                                                        ('United States', 'Michigan', 0.06),
                                                        ('United States', 'Minnesota', 0.06875),
                                                        ('United States', 'Mississippi', 0.07),
                                                        ('United States', 'Missouri', 0.04225),
                                                        ('United States', 'Montana', 0),
                                                        ('United States', 'Nebraska', 0.055),
                                                        ('United States', 'Nevada', 0.0685),
                                                        ('United States', 'New Hampshire', 0),
                                                        ('United States', 'New Jersey', 0.06625),
                                                        ('United States', 'New Mexico', 0.05125),
                                                        ('United States', 'New York', 0.04),
                                                        ('United States', 'North Carolina', 0.0475),
                                                        ('United States', 'North Dakota', 0.05),
                                                        ('United States', 'Northern Mariana Islands', 0),
                                                        ('United States', 'Ohio', 0.0575),
                                                        ('United States', 'Oklahoma', 0.045),
                                                        ('United States', 'Oregon', 0),
                                                        ('United States', 'Palau', 0),
                                                        ('United States', 'Pennsylvania', 0.06),
                                                        ('United States', 'Puerto Rico', 0.115),
                                                        ('United States', 'Rhode Island', 0.07),
                                                        ('United States', 'South Carolina', 0.06),
                                                        ('United States', 'South Dakota', 0.045),
                                                        ('United States', 'Tennessee', 0.07),
                                                        ('United States', 'Texas', 0.0625),
                                                        ('United States', 'Utah', 0.0485),
                                                        ('United States', 'Vermont', 0.06),
                                                        ('United States', 'Virgin Islands', 0),
                                                        ('United States', 'Virginia', 0.043),
                                                        ('United States', 'Washington', 0.065),
                                                        ('United States', 'West Virginia', 0.06),
                                                        ('United States', 'Wisconsin', 0.05),
                                                        ('United States', 'Wyoming', 0.04);
    INSERT INTO NorthAmericaStates(Country, State, taxRate) VALUES('Canada', 'Alberta', 0),
                                                        ('Canada', 'British Columbia', 0.07),
                                                        ('Canada', 'Manitoba', 0.07),
                                                        ('Canada', 'New Brunswick', 0.1),
                                                        ('Canada', 'Newfoundland and Labrador', 0.1),
                                                        ('Canada', 'Northwest Territories', 0),
                                                        ('Canada', 'Nova Scotia', 0.1),
                                                        ('Canada', 'Nunavut', 0),
                                                        ('Canada', 'Ontario', 0.08),
                                                        ('Canada', 'Prince Edward Island', 0.1),
                                                        ('Canada', 'Québec', 0.09975),
                                                        ('Canada', 'Saskatchewan', 0.06),
                                                        ('Canada', 'Yukon Territory', 0);

    INSERT INTO NorthAmericaStates(Country, State, taxRate) VALUES('Mexico', 'Aguascalientes', 0.03),
                                                        ('Mexico', 'Baja California Norte', 0.045),
                                                        ('Mexico', 'Baja California Sur', 0.075),
                                                        ('Mexico', 'Campeche', 0.015),
                                                        ('Mexico', 'Chiapas', 0.025),
                                                        ('Mexico', 'Mexico City', 0.04),
                                                        ('Mexico', 'Chihuahua', 0.0345),
                                                        ('Mexico', 'Coahuila', 0.0285),
                                                        ('Mexico', 'Colima', 0.05),
                                                        ('Mexico', 'Durango', 0.04),
                                                        ('Mexico', 'Guanajuato', 0.07),
                                                        ('Mexico', 'Guerrero', 0.065),
                                                        ('Mexico', 'Hidalgo', 0.045),
                                                        ('Mexico', 'Jalisco', 0.055),
                                                        ('Mexico', 'México', 0.025),
                                                        ('Mexico', 'Michoacán', 0),
                                                        ('Mexico', 'Morelos', 0),
                                                        ('Mexico', 'Nayarit', 0.03),
                                                        ('Mexico', 'Nuevo León', 0),
                                                        ('Mexico', 'Oaxaca', 0.05),
                                                        ('Mexico', 'Puebla', 0.02),
                                                        ('Mexico', 'Querétaro', 0.1),
                                                        ('Mexico', 'Quintana Roo', 0),
                                                        ('Mexico', 'San Luis Potosí', 0.0435),
                                                        ('Mexico', 'Sinaloa', 0.0625),
                                                        ('Mexico', 'Sonora', 0.0355),
                                                        ('Mexico', 'Tabasco', 0),
                                                        ('Mexico', 'Tamaulipas', 0.045),
                                                        ('Mexico', 'Tlaxcala', 0),
                                                        ('Mexico', 'Veracruz', 0.1),
                                                        ('Mexico', 'Yucatán', 0.03),
                                                        ('Mexico', 'Zacatecas', 0.06);


    Insert into Customer(CustomerID, Name, Address, City, State, Country, PostalCode)
        VALUES(577435,'Later983','46 Louis Street', 'Santa Clara', 'California', 'United States', '95190');
    Insert into Customer(customerID, Name, address, city, state, country, postalCode )
        VALUES ( 123456, 'Lisa312', '99 Maple Street', 'Charlottetown', 'Prince Edward Island', 'Canada', 'C1A 0A1');
    Insert into Customer(customerID, Name, address, city, state, country, postalCode )
        VALUES ( 123457, 'María001', '378 Sunset Avenue', 'Mexico City', 'Mexico City', 'Mexico', '00810');
    #Jeans
    Insert into Product(Name, Description, SKU, Listed) VALUES('Levis Jeans 501','Original fit jeans','LE-420422-JE', 1);
    Insert into InventoryRecord(SKU,Units, Price) VALUES ('LE-420422-JE', 100, 180);
    Insert into Product(Name, Description, SKU, Listed) VALUES('Levis Jeans Wedgie','High-rise straight jeans','LE-420423-JE', 1);
    Insert into InventoryRecord(SKU,Units, Price) VALUES ('LE-420423-JE',60, 110);

    #Pants
    Insert into Product(Name, Description, SKU, Listed) VALUES('Levis Pants 710','Super skinny pants','LE-497892-PA', 1);
    Insert into InventoryRecord(SKU,Units, Price) VALUES ('LE-497892-PA', 200, 180);
    Insert into Product(Name, Description, SKU, Listed) VALUES('Levis Pants 286','Corduroy pants','LE-497893-PA', 0);
    Insert into InventoryRecord(SKU,Units, Price) VALUES ('LE-497893-PA', 300, 120);

    #SweatShirts
    Insert into Product(Name, Description, SKU, Listed) VALUES('Levis SweatShirt 292','Comfortable 100% cotton sweatshirt','LE-420492-SW', 1);
    Insert into InventoryRecord(SKU,Units, Price) VALUES ('LE-420492-SW', 160, 80);
    Insert into Product(Name, Description, SKU, Listed) VALUES('Levis SweatShirt 293','Comfortable long-sleeve sweatshirt','LE-420493-SW', 0);
    Insert into InventoryRecord(SKU,Units, Price) VALUES ('LE-420493-SW',100, 90);

    #Shirt
    Insert into Product(Name, Description, SKU, Listed) VALUES('Levis Shirt 867','Comfortable 100% cotton shirt','LE-594092-SH', 1);
    Insert into InventoryRecord(SKU,Units, Price) VALUES ('LE-594092-SH', 150, 70);

    #Hat
    Insert into Product(Name, Description, SKU, Listed) VALUES('Levis Hat 834','One size fit hat','LE-594382-HA', 1);
    Insert into InventoryRecord(SKU,Units, Price) VALUES ('LE-594382-HA', 80, 50);

    # history within a week
    Insert into PriceHistory(SKU, DateTime, FinalPrice) VALUES('LE-420422-JE','2019-12-07 20:45:25' ,160);
    Insert into PriceHistory(SKU, DateTime, FinalPrice) VALUES('LE-420422-JE','2019-12-05 11:48:27' ,150);

    # history within a month
    Insert into PriceHistory(SKU, DateTime, FinalPrice) VALUES('LE-420422-JE','2019-11-26 23:24:40' ,170);
    Insert into PriceHistory(SKU, DateTime, FinalPrice) VALUES('LE-420422-JE','2019-11-23 12:35:05' ,200);

    # history within a season
    Insert into PriceHistory(SKU, DateTime, FinalPrice) VALUES('LE-420422-JE','2019-10-23 17:17:37' ,210);
    Insert into PriceHistory(SKU, DateTime, FinalPrice) VALUES('LE-420422-JE','2019-10-16 22:16:10' ,230);

    # history within a year
    Insert into PriceHistory(SKU, DateTime, FinalPrice) VALUES('LE-420422-JE','2019-01-18 06:10:55' ,300);
    Insert into PriceHistory(SKU, DateTime, FinalPrice) VALUES('LE-420422-JE','2019-01-07 09:09:33' ,360);

    #some prouduts with one price change
    Insert into PriceHistory(SKU, DateTime, FinalPrice) VALUES('LE-497892-PA','2019-11-23 13:38:42' ,260);
    Insert into PriceHistory(SKU, DateTime, FinalPrice) VALUES('LE-420492-SW','2019-11-26 11:18:45' ,250);
    Insert into PriceHistory(SKU, DateTime, FinalPrice) VALUES('LE-594382-HA','2019-12-10 02:23:19' ,200);
    Insert into PriceHistory(SKU, DateTime, FinalPrice) VALUES('LE-420493-SW','2019-05-23 14:42:50' ,100);


    #Orders
    #customerID: Later983
    #orderID: 256354501 cancelled order from Later983 within one year
    Insert into Orders(customerID, OrderID, orderdate, isCancelled) VALUES (577435, 256354501, '2019-01-10', 1);
    Insert into OrderRecord(orderID, units, price, sku) VALUES (256354501, 3, 90, 'LE-420493-SW');
    Insert into OrderRecord(orderID, units, price, sku) VALUES (256354501, 1, 110, 'LE-420423-JE');

    #orderID: 256354690 from later983 within one year
    Insert into Orders(customerID, OrderID, orderdate, isCancelled) VALUES (577435, 256354690, '2019-06-13', 0);
    Insert into OrderRecord(orderID, units, price, sku) VALUES (256354690, 10, 90, 'LE-420493-SW');
    Insert into OrderRecord(orderID, units, price, sku) VALUES (256354690, 1, 110, 'LE-420423-JE');

    #orderID: 197354610 from later983 within one season
    Insert into Orders(customerID, OrderID, orderdate, isCancelled) VALUES (577435, 197354610, '2019-10-13', 0);
    Insert into OrderRecord(orderID, units, price, sku) VALUES (197354610, 2, 90, 'LE-420493-SW');
    Insert into OrderRecord(orderID, units, price, sku) VALUES (197354610, 10, 110, 'LE-420423-JE');

    #orderID: 197359093 from later983 within one season
    Insert into Orders(customerID, OrderID, orderdate, isCancelled) VALUES (577435, 197359093, '2019-09-21', 0);
    Insert into OrderRecord(orderID, units, price, sku) VALUES (197359093, 2, 90, 'LE-420493-SW');
    Insert into OrderRecord(orderID, units, price, sku) VALUES (197359093, 2, 110, 'LE-420423-JE');

    #orderID: 478633255 from later983 within one month
    Insert into Orders(customerID, OrderID, orderdate, isCancelled) VALUES (577435, 478633255, '2019-11-13', 0);
    Insert into OrderRecord(orderID, units, price, sku) VALUES (478633255, 2, 110, 'LE-420423-JE');

    #orderID: 687312546 from later983 within one month
    Insert into Orders(customerID, OrderID, orderdate, isCancelled) VALUES (577435, 687312546, '2019-11-30', 0);
    Insert into OrderRecord(orderID, units, price, sku) VALUES (687312546, 5, 90, 'LE-420493-SW');
    Insert into OrderRecord(orderID, units, price, sku) VALUES (687312546, 2, 110, 'LE-420423-JE');

    #orderID: 906743588 from later983 within one week
    Insert into Orders(customerID, OrderID, orderdate, isCancelled) VALUES (577435, 906743588, '2019-12-06', 0);
    Insert into OrderRecord(orderID, units, price, sku) VALUES (906743588, 4, 90, 'LE-420493-SW');

    #orderID: 906743541 from later983 within one week
    Insert into Orders(customerID, OrderID, orderdate, isCancelled) VALUES (577435, 906743541, '2019-12-09', 0);
    Insert into OrderRecord(orderID, units, price, sku) VALUES (906743541, 4, 90, 'LE-420493-SW');
    Insert into OrderRecord(orderID, units, price, sku) VALUES (906743541, 7, 110, 'LE-420423-JE');

    #customerID: Lisa312
    #orderID: 345543099 from  Lisa312 within one week
    Insert into Orders(customerID, OrderID, orderdate, isCancelled) VALUES (123456, 345543099, '2019-12-07', 0);
    Insert into OrderRecord(orderID, units, price, sku) VALUES (345543099, 1, 90,'LE-420493-SW');
    Insert into OrderRecord(orderID, units, price, sku) VALUES (345543099, 1, 110, 'LE-420423-JE');

    #orderID: 325354322 from Lisa312 within one month
    Insert into Orders(customerID, OrderID, orderdate, isCancelled) VALUES (123457, 325354322, '2019-11-29',0);
    Insert into OrderRecord(orderID, units, price, sku) VALUES (325354322, 5, 90,'LE-420493-SW');
    Insert into OrderRecord(orderID, units, price, sku) VALUES (325354322, 1, 110,'LE-420423-JE');

    #customerID: María001
    #empty order 325354974 from María001 created right now
    Insert into Orders(customerID, OrderID, orderdate, isCancelled) VALUES (123457,325354974, NOW(), 0);

    #orderID: 325354379 from María001 within one month
    Insert into Orders(customerID, OrderID, orderdate, isCancelled) VALUES (123457, 325354379, '2019-09-17',0);
    Insert into OrderRecord(orderID, units, price, sku) VALUES (325354379, 6, 90,'LE-420493-SW');
    Insert into OrderRecord(orderID, units, price, sku) VALUES (325354379, 1, 110,'LE-420423-JE');
end;


#---------------------------------------------------------------------------------------------------------------------------------------------
#Part3: test 26 stored procedures and 2 triggers.

## Part3-1: test for Procedure createCustomer.
#(1)Base situation:
CALL testData();
SELECT * from customer; # We have 3 customer rows in the Customer table
#(2)Valid case
# add 2 customer
CALL createCustomer(489325, '4Sally', '231 Maple St.', 'Stockton', 'California','United States','95201');
CALL createCustomer(365903, 'Stowed012', '221B Baker Street', 'Vancouver', 'British Columbia','Canada','98607');
SELECT * from customer; # we have 5 customers in the customer table.
#(3)Invalid cases
#duplicate primary key
CALL createCustomer(123456, 'STEVE1', '11 Park Rd.', 'New Haven', 'Connecticut','United States','46593');
# Invalid country name
CALL createCustomer(657848, 'Jenny22', '102 rainbow Dr.', 'Chihuahua', 'Sichuan', 'SABCD','365342');
# Invalid state name
CALL createCustomer(489324, 'Echo_1', '2209 Poughkeepsie Rd.', 'New Haven', 'Yukon Territory','United States','C1A 0A9');
SELECT * from customer;# customers not added, we have 5 customers in the customer table.

## Part3-2: test for Procedure createProduct
#(1)Base Situation:
CALL testData();
SELECT * from Product; # We have 8 products in Product table
#(2)Valid cases
# add 2 products
CALL createProduct('Levis Hat 075','One size fit comfy hat', 'LE-000002-HA');
CALL createProduct('Levis Shirt 1178', 'Comfortable 100% cotton shirt', 'LE-238843-SH');
SELECT * from Product; # we have 10 products in Product table
#(3)Invalid cases
#duplicate primary key
CALL createProduct('Levis Shirt 034', 'Comfortable 100% cotton shirt', 'LE-594092-SH');
#name cannot be empty string
CALL createProduct('', 'Comfortable 100% cotton shirt', 'LE-865421-SH');
#inputSKU does not match regex
CALL createProduct('Levis Hat 075','One size fit comfy hat', 'LE-000002');
CALL createProduct('Levis Hat 075','One size fit comfy hat', '34-564567-12');
SELECT * from Product; # Product not added, we have 10 products in Product table

# Part3-3: test for Procedure listProduct
#(1)Base Situation:
CALL testData();
SELECT * from Product; # We have 2 unlisted products in Product table
#(2)Valid cases
#list 32 products
CALL listProduct('LE-420493-SW');
CALL listProduct('LE-497893-PA');
SELECT * from Product; # all products are listed

#(3)Invalid cases
# list an already listed product
CALL listProduct('LE-420422-JE');
CALL listProduct('LE-420423-JE');
#create 2 unlisted products
CALL createProduct('Levis shirt 1105', 'Comfortable 100% cotton shirt', 'LE-456885-SH');
CALL createProduct('Levis shirt 4365', 'Comfortable 100% cotton shirt', 'LE-897643-SH');
#can not be listed since price has not been set yet
CALL listProduct('LE-456885-SH');
CALL listProduct('LE-897643-SH');
SELECT * from Product; # we have 2 unlisted newly created productS in Product table

# Part3-4: test for Procedure unlistProuduct
#(1)Base Situation:
CALL testData();
SELECT * from Product; # we have 2 unlisted products in Product table
#(2)Valid cases
#unlist 2 products
CALL unListProduct('LE-497892-PA');
CALL unListProduct('LE-594092-SH');
SELECT * from Product; #we have 4 unlisted products in Product table

# Part3-5: test for Procedure readListProduct
#(1)Base Situation:
CALL testData();
SELECT * from Product; # show 8 products in Product table
#(2)Valid cases
CALL readListedProducts();
SELECT * from Product; # show 8 products in Product table
#unlist all products
CALL unListProduct('LE-420422-JE');
CALL unListProduct('LE-420423-JE');
CALL unListProduct('LE-420492-SW');
CALL unListProduct('LE-497892-PA');
CALL unListProduct('LE-594092-SH');
CALL unListProduct('LE-594382-HA');
CALL readListedProducts();# no listed products found

# Part3-6: test for Procedure searchProductName
#(1)Base Situation:
CALL testData();
SElECT * FROM Product; # show 8 products in Product table
#(2)Valid cases
CALL searchProductName('jeans'); # 2 listed products contain jeans in name found
CALL searchProductName('shirt'); # 2 listed products contain shirt in name found
#(3)Invalid cases # SQLException:
# No such product exists
CALL searchProductName('FSAGAWRGFIJAG');
CALL searchProductName('fgirtugrtg');


# Part3-7: test for Procedure readProductInventory
#(1)Base Situation:
CALL testData();
SELECT * from Product; # show 8 products in Product table
#(2)Valid cases
CALL readProductInventory(TRUE); # show 6 listed products
CALL readProductInventory(FALSE); # show 2 unlisted products

# Part3-8: test for Procedure readAllProductInventory
#(1)Base Situation:
CALL testData();
SELECT * from Product; # show 8 products in Product table
#(2)Valid cases
CALL readAllProductInventory();
SELECT * from Product; # show all 8 products in Product table


# Part3-9: test for Procedure readInventorySpecifyingUnit
#(1)Base Situation:
CALL testData();
SELECT * from InventoryRecord; # show 8 products in table InventoryRecord
#(2)Valid cases
CALL readInventorySpecifyingUnit(50, 90); #2 products within unit range [50,90] found
CALL readInventorySpecifyingUnit(100, 150); #3 products within unit range [100,150] found
CALL readInventorySpecifyingUnit(1000, 2000); #no product between this range found
#(3)Invalid cases
#Invalid unit range, beginUnit must smaller than endUnit
CALL readInventorySpecifyingUnit(100, 80);
CALL readInventorySpecifyingUnit(200, 70);



# Part3-10: test for Procedure changeInventoryUnits
#(1)Base Situation:
CALL testData();
SELECT * FROM InventoryRecord; #show products in InventoryRecord table
#(2)Valid cases
CALL changeInventoryUnits('LE-420422-JE', 100); # first product 'LE-420422-JE' increse 100 units
CALL changeInventoryUnits('LE-420423-JE', -50); # second product 'LE-420423-JE' decrease 50 units
SELECT * FROM InventoryRecord; #show products in InventoryRecord table
## PLUS* TEST Trigger unlistProductIfNotAvailable
SELECT * FROM Product; # 2 unlisted products in Product table
CALL changeInventoryUnits('LE-420423-JE', -10); # product 'LE-420423-JE' units becomes 0
SELECT * FROM Product; # we can see 3 unlisted products now
#(3)Invalid cases
#cannot find the inout SKU since the product does not exist
CALL changeInventoryUnits('LE-420499-SW', 10);
# SQLException: invalid input. decrease number larger than current units
CALL changeInventoryUnits('LE-420492-SW', -1000);
CALL changeInventoryUnits('LE-497892-PA', -500);
SELECT * FROM InventoryRecord; # units number of 2 products above unchanged



# Part3-11: test for Procedure changeDiscount
#(1)Base Situation:
CALL testData();
SELECT * FROM InventoryRecord;# show InventoryRecord table
#(2)Valid cases
CALL changeDiscount('LE-420422-JE', 0.6);
CALL changeDiscount('LE-420423-JE', 0.9);
SELECT * FROM InventoryRecord; #first 2 products discount changed in InventoryRecord table
#(3)Invalid cases
# Cannot find the input SKU, no such product exists
CALL changeDiscount('LE-387453-JE', 0.8);
# SQLException: Discount cannot be negative or greater than 1
CALL changeDiscount('LE-420422-JE', -0.1);
CALL changeDiscount('LE-420422-JE', 1.2);
SELECT * FROM InventoryRecord; # discount of 2 products above unchanged in InventoryRecord table


# Part3-12: test for Procedure changePrice
#(1)Base Situation:
CALL testData();
SELECT * FROM InventoryRecord; # show InventoryRecord table
#(2)Valid cases
CALL changePrice('LE-594092-SH', 120);
CALL changePrice('LE-420492-SW', 150);
SELECT * FROM InventoryRecord; # price of 2 products above changed
#(3)Invalid cases
# Cannot find the input SKU because such product does not exist
CALL changePrice('LE-765392-JE', 90);
# SQLException: Price cannot be negative
CALL changePrice('LE-594092-SH', -10);
CALL changePrice('LE-594092-SH', -100);
SELECT * FROM InventoryRecord; # price of product 'LE-594092-SH' unchanged in InventoryRecord table


# Part3-13: test for Procedure readPriceHistory
#(1)Base Situation:
CALL testData();
SELECT * FROM PriceHistory; #12 price history in priceHistory table
#(2)Valid cases
CALL readPriceHistory('LE-420422-JE'); # 8 price historys of product 'LE-420422-JE' found
CALL readPriceHistory('LE-420492-SW'); # 1 price history of product 'LE-420492-SW' found
SELECT * FROM PriceHistory; #12 price history in priceHistory table
CALL readPriceHistory('LE-438753-JE'); # No such product exists


# Part3-14: test for Procedure readPriceHistorySpecifyingTime
#(1)Base Situation:
CALL testData();
SELECT * FROM PriceHistory; #show 12 history records in priceHistory table
#(2)Valid cases
CALL readPriceHistorySpecifyingTime('LE-420422-JE', '2019-01-01', '2019-06-29'); # 2 history found
CALL readPriceHistorySpecifyingTime('LE-420422-JE', '2019-06-30', '2019-11-30'); # 4 history found
SELECT * FROM PriceHistory; # show priceHistory table
#(3)Invalid cases
#Invalid time range, start datetime cannot be later than end datetime
CALL readPriceHistorySpecifyingTime('LE-420422-JE', '2019-10-11', '2019-06-29');
# no such product exists
CALL readPriceHistorySpecifyingTime('LE-424865-LA','2019-01-01', '2019-09-29');



# Part3-15: test for Procedure createOrder
#(1)Base Situation:
CALL testData();
SELECT * FROM Orders; #show 12 records in Orders table
#(2)Valid cases
CALL createOrder('123456', '387457674',NOW());
CALL createOrder('123456', '475686901',NOW());
#show unmodified Orders table
SELECT * FROM Orders; #show 14 records in Orders table
#(3)Invalid cases
#SQLException: Duplicate Primary Key
CALL createOrder('123457','197354610', NOW());
#SQLException: a foreign key constraint fails because customer '234223' does not exists
CALL createOrder('234223', '435421456', NOW());
# SQLException: OrderID cannot be empty string.
CALL createOrder('123457','', NOW());
SELECT * FROM Orders; #show 14 records in Orders table



# Part3-16: test for Procedure changePreOrderUnits
#(1)Base Situation
CALL testData();
SELECT * FROM InventoryRecord;
#(2)Valid cases
CALL changePreOrderUnits('LE-420422-JE',  100);
CALL changePreOrderUnits('LE-420492-SW', 200);
CALL changePreOrderUnits('LE-420492-SW', -20);
SELECT * FROM InventoryRecord;
#(3)Invalid cases
# Cannot find the input SKU
CALL changePreOrderUnits('LE-857342-AS', 10);
# SQLException: Invalid input units
CALL changePreOrderUnits('LE-420422-JE',  -500);
CALL changePreOrderUnits('LE-420492-SW', -800);



# Part3-17: test for Procedure createOrderRecord
#(1)Base Situation
CALL testData();
SELECT * FROM InventoryRecord;
#(2)Valid cases
CALL createOrderRecord('LE-420422-JE','197359093', 10);
CALL createOrderRecord('LE-420422-JE','906743588', 5);
SELECT * FROM OrderRecord;
#(3)Invalid cases
#orderUnits can not be negative
CALL createOrderRecord('LE-594382-HA', '197359093', -10);
#orderUnits can not exceed inventory
CALL createOrderRecord('LE-594382-HA', '197359093', 1000);
#product does not exist SQLException
CALL createOrderRecord('LE-594382-45', '197359093', 5);


# Part3-18: test for Procedure calculateOrderPrice
#(1)Base Situation
CALL testData();
SELECT * FROM Orders;
#(2)Valid cases
CALL calculateOrderPrice('197359093'); #order total price 400, promotions applicable
CALL calculateOrderPrice('197354610'); #order total price 1280, promotions applicable
CALL calculateOrderPrice('345543099'); #order total price 200, promotions not applicable
SELECT * FROM Orders;
## PLUS* Trigger applyPromotion works for the 3 orders above, 2 orders exceeds $300 can apply promotion
SELECT * FROM Promotion;
# Cannot find the input order ID.
CALL calculateOrderPrice('435254123'); #enter an orderID that does not exist




# Part3-19: test for Procedure FinalizeOrderPrice
#(1)Base Situation
CALL testData();
SELECT * FROM OrderRecord;
#(2)Valid cases
CALL calculateOrderPrice('256354690');
CALL calculateOrderPrice('345543099');
# this order is from customer 'Later983' from California, tax rate 7.25%, order exceeds $300, got $50 off from promotion. We get 1029.6.
CALL FinalizeOrderPrice('256354690');
#this order is from customer 'Lisa312' from PEI, Canada, tax rate 10%, order less than $300, no promotion, we get 220.
CALL FinalizeOrderPrice('345543099');
#(3)Invalid cases
#cannot find the input order ID.
CALL FinalizeOrderPrice('764783289');# inout an order ID that does not exists



# Part3-20: test for Procedure createOneOrderWithManyItems
#(1)base situation
CALL testData();
SELECT * FROM Orders;#show 12 orders in Orders table
SELECT * FROM OrderRecord; #show 20 order records in OrderRecord table

#(2)valid case
CALL createOneOrderWithManyItems(577435, '826493587', '2019-10-19',
'LE-420422-JE', 5, 'LE-420492-SW', 30, 'LE-497892-PA', 70);
SELECT * FROM Orders; #show 13 orders in Orders table
SELECT * FROM OrderRecord; #show 23 order records in OrderRecord table

# Part3-21: test for Procedure updateShipmentDate
#(1)Base Situation
CALL testData();
SELECT * FROM Orders;
#(2)Valid cases
CALL updateShipmentDate('197359093','2019-11-10 17:02:55');# Valid shipment date.
CALL updateShipmentDate('256354690', NOW());
SELECT * FROM Orders;
#(3)Invalid cases
CALL updateShipmentDate('197354610','2015-12-07 00:00:00');# Invalid shipment date, precedes order date
#Cannot find the input order ID.
CALL updateShipmentDate('236435075', '2019-10-10 00:00:00');# input a nonexistent orderID



# Part3-22: test for Procedure cancelOrder
#(1)Base Situation
CALL testData();
SELECT * FROM Orders;
#(2)Valid cases
CALL cancelOrder('197354610');
CALL cancelOrder('197359093');
SELECT * FROM Orders;
#(3)Invalid cases
# SQLException: Can not cancel a shipped order
update Orders set ShipmentDate = '2019-12-03' where OrderID = 256354690;
CALL cancelOrder('256354690');
# Cannot find the input order ID.
CALL cancelOrder('468679123'); # input a nonexistent orderID


# Part3-23: test for Procedure calculateTotalRevenue
#(1)Base Situation
CALL testData();
CALL calculateOrderPrice(197354610);
CALL FinalizeOrderPrice(197354610);
CALL calculateOrderPrice(197359093);
CALL FinalizeOrderPrice(197359093);
CALL calculateOrderPrice(256354501);
CALL FinalizeOrderPrice(256354501);
SELECT * FROM Orders;
#(2)Valid cases
# Only one order, total revenue = 1280.
CALL calculateTotalRevenue('2019-10-10','2019-12-20');
# Three orders, total revenue = 2060.
CALL calculateTotalRevenue('2019-01-10','2019-12-20');
#Invalid time range input.
CALL calculateTotalRevenue('2019-10-18', '2019-04-27'); #end time precedes start time


# Part3-24: test for Procedure readCustomerOrders
#(1)Base Situation
CALL testData();
SELECT * FROM Orders;
#(2)Valid cases
# Find eight customerOrders.
CALL readCustomerOrders(577435);
# Find three customerOrders.
CALL readCustomerOrders(123457);
#(3)Invalid cases
#No such customer exists
CALL readCustomerOrders(546235); # input a nonexistent customer ID



# Part3-25: test for Procedure readCustomerOrdersSpecifyingTime
#(1)Base Situation
CALL testData();
SELECT * FROM Orders;
#(2)Valid cases
# Find five customerOrders.
CALL readCustomerOrdersSpecifyingTime(577435, '2019-10-01', '2019-12-11');
# Find one customerOrder.
CALL readCustomerOrdersSpecifyingTime(123457, '2019-09-01', '2019-10-01');
# No order during this time.
CALL readCustomerOrdersSpecifyingTime(123457, '2015-09-01', '2015-10-01');
#(3)Invalid cases
#No such customer exists
CALL readCustomerOrdersSpecifyingTime(546235, '2019-01-01', '2019-03-03'); # input a nonexistent customer ID


# Part3-26: test for Procedure readOrderDetail
#(1)Base Situation
CALL testData();
SELECT * FROM OrderRecord;
#(2)Valid cases
# Find two items for orderID 197354610.
CALL readOrderDetail(197354610);
# Find two items for orderID 687312546.
CALL readOrderDetail(687312546);
#(3)Invalid cases
# No such orderId as 451000000.
CALL readOrderDetail(451000000); # input a nonexistent order ID

# Part3-27: test for Procedure readSpecificProductInventory
#(1)Base Situation
CALL testData();
SELECT * FROM InventoryRecord;
#(2)Valid cases
CALL readSpecificProductInventory('LE-420422-JE');
CALL readSpecificProductInventory('LE-420423-JE');
#(3)Invalid cases
CALL readSpecificProductInventory('LE-432658-LE'); #cannot find input SKU
CALL readSpecificProductInventory('LE-432659-JD'); #cannot find input SKU
