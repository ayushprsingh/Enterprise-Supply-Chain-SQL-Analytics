
-- 1. SCHEMA CREATION & CONSTRAINTS
-- Setting up 8 normalized tables with integrity constraints to prevent invalid data
CREATE TABLE Warehouses (
    WarehouseID INT PRIMARY KEY,
    WarehouseName VARCHAR(100) NOT NULL,
    Location VARCHAR(100) NOT NULL,
    Capacity_SqFt INT CHECK (Capacity_SqFt > 0)
);

CREATE TABLE Suppliers (
    SupplierID INT PRIMARY KEY,
    SupplierName VARCHAR(100) NOT NULL,
    ContactEmail VARCHAR(100) UNIQUE NOT NULL,
    Rating DECIMAL(2, 1) CHECK (Rating BETWEEN 1.0 AND 5.0)
);

CREATE TABLE Inventory_Items (
    ItemID INT PRIMARY KEY,
    ItemName VARCHAR(100) NOT NULL,
    SupplierID INT,
    UnitCost DECIMAL(10, 2) CHECK (UnitCost > 0),
    ReorderLevel INT CHECK (ReorderLevel >= 0),
    FOREIGN KEY (SupplierID) REFERENCES Suppliers(SupplierID)
);

CREATE TABLE Warehouse_Stock (
    StockID INT PRIMARY KEY,
    WarehouseID INT,
    ItemID INT,
    QuantityInHand INT CHECK (QuantityInHand >= 0),
    FOREIGN KEY (WarehouseID) REFERENCES Warehouses(WarehouseID),
    FOREIGN KEY (ItemID) REFERENCES Inventory_Items(ItemID)
);

CREATE TABLE Logistics_Carriers (
    CarrierID INT PRIMARY KEY,
    CarrierName VARCHAR(100) NOT NULL,
    ServiceTier VARCHAR(30) CHECK (ServiceTier IN ('Standard', 'Express', 'Freight'))
);

CREATE TABLE Client_Orders (
    OrderID INT PRIMARY KEY,
    CustomerName VARCHAR(100) NOT NULL,
    OrderDate DATE NOT NULL,
    OrderStatus VARCHAR(30) CHECK (OrderStatus IN ('Placed', 'In-Transit', 'Delivered', 'Cancelled')),
    TotalAmount DECIMAL(12, 2) CHECK (TotalAmount >= 0)
);

CREATE TABLE Order_Line_Items (
    LineID INT PRIMARY KEY,
    OrderID INT,
    ItemID INT,
    Quantity INT CHECK (Quantity > 0),
    PricePerUnit DECIMAL(10, 2),
    FOREIGN KEY (OrderID) REFERENCES Client_Orders(OrderID),
    FOREIGN KEY (ItemID) REFERENCES Inventory_Items(ItemID)
);

CREATE TABLE Shipments (
    ShipmentID INT PRIMARY KEY,
    OrderID INT UNIQUE,
    CarrierID INT,
    WarehouseID INT,
    DispatchDate DATE,
    EstimatedDelivery DATE,
    ActualDelivery DATE,
    FOREIGN KEY (OrderID) REFERENCES Client_Orders(OrderID),
    FOREIGN KEY (CarrierID) REFERENCES Logistics_Carriers(CarrierID),
    FOREIGN KEY (WarehouseID) REFERENCES Warehouses(WarehouseID)
);

-- 2. INSERT SAMPLE DATA
-- Mock data representing hubs, suppliers, inventory levels, and shipments

INSERT INTO Warehouses VALUES 
(1, 'North Hub', 'Delhi-NCR', 50000), 
(2, 'South Hub', 'Bengaluru', 75000);

INSERT INTO Suppliers VALUES 
(10, 'TechSupply Corp', 'contact@techsupply.com', 4.8), 
(20, 'Global Logistics Ltd', 'sales@globallogistics.com', 4.2);

INSERT INTO Inventory_Items VALUES 
(101, 'Industrial Sensor Unit', 10, 150.00, 20),
(102, 'Microcontroller Kit', 10, 45.00, 50),
(103, 'Fiber Optic Cable (100m)', 20, 80.00, 15);

-- Inserting items where QuantityInHand is purposefully lower than ReorderLevel to test Query 1
INSERT INTO Warehouse_Stock VALUES 
(1001, 1, 101, 12), -- Deficit: 12 in stock vs 20 needed
(1002, 1, 102, 120),
(1003, 2, 103, 8);  -- Deficit: 8 in stock vs 15 needed

INSERT INTO Logistics_Carriers VALUES 
(1, 'FedEx Express', 'Express'), 
(2, 'BlueDart Logistics', 'Standard');

INSERT INTO Client_Orders VALUES 
(5001, 'Acme Automation Systems', '2026-07-01', 'Delivered', 1200.00),
(5002, 'OmniTech Solutions', '2026-07-10', 'Delivered', 3500.00);

INSERT INTO Order_Line_Items VALUES 
(1, 5001, 101, 5, 150.00),
(2, 5001, 102, 10, 45.00),
(3, 5002, 103, 20, 80.00);

INSERT INTO Shipments VALUES 
(9001, 5001, 1, 1, '2026-07-02', '2026-07-05', '2026-07-04'), -- Delivered early/on-time
(9002, 5002, 2, 2, '2026-07-11', '2026-07-14', '2026-07-17'); -- Delayed by 3 days

-- 3. PROBLEM-SOLVING ANALYTICAL QUERIES

-- PROBLEM 1: Prevent stockouts by identifying low inventory across warehouses.
-- SOLUTION: Join stock logs with thresholds and fetch supplier emails so restock orders can be sent immediately.
SELECT 
    w.WarehouseName,
    i.ItemName,
    ws.QuantityInHand,
    i.ReorderLevel,
    (i.ReorderLevel - ws.QuantityInHand) AS DeficitAmount, -- Amount needed to reach minimum stock
    s.SupplierName,
    s.ContactEmail
FROM Warehouse_Stock ws
JOIN Warehouses w ON ws.WarehouseID = w.WarehouseID
JOIN Inventory_Items i ON ws.ItemID = i.ItemID
JOIN Suppliers s ON i.SupplierID = s.SupplierID
WHERE ws.QuantityInHand < i.ReorderLevel; -- Trigger restock alert only if stock drops below threshold


-- PROBLEM 2: Carrier delays cause customer SLA breaches. Need to evaluate delivery performance per carrier.
-- SOLUTION: Use a CTE to calculate delay days and binary SLA flags, then aggregate to compute overall success rate.
WITH ShipmentSLASummary AS (
    SELECT 
        c.CarrierName,
        s.OrderID,
        -- Calculate difference between target delivery and actual delivery date
        DATEDIFF(day, s.EstimatedDelivery, s.ActualDelivery) AS DelayInDays,
        -- Set flag to 1 if delivered on or before schedule, else 0
        CASE 
            WHEN s.ActualDelivery <= s.EstimatedDelivery THEN 1 
            ELSE 0 
        END AS IsOnTime
    FROM Shipments s
    JOIN Logistics_Carriers c ON s.CarrierID = c.CarrierID
    WHERE s.ActualDelivery IS NOT NULL
)
SELECT 
    CarrierName,
    COUNT(OrderID) AS TotalShipments,
    SUM(IsOnTime) AS OnTimeDeliveries,
    -- Calculate overall SLA compliance percentage
    ROUND((SUM(IsOnTime) * 100.0 / COUNT(OrderID)), 2) AS OnTimeSLA_Percentage,
    -- Compute average delay only for late shipments
    AVG(CASE WHEN DelayInDays > 0 THEN DelayInDays ELSE 0 END) AS AvgDelayDays
FROM ShipmentSLASummary
GROUP BY CarrierName;


-- PROBLEM 3: Track customer purchase trends and lifetime account growth over time.
-- SOLUTION: Use window function SUM() OVER() partitioned by customer to compute cumulative spend without extra subqueries.
SELECT 
    co.CustomerID,
    co.CustomerName,
    co.OrderID,
    co.OrderDate,
    co.TotalAmount,
    -- Calculates running total spend per customer ordered chronologically
    SUM(co.TotalAmount) OVER (PARTITION BY co.CustomerName ORDER BY co.OrderDate) AS CumulativeSpend
FROM Client_Orders co
WHERE co.OrderStatus != 'Cancelled';
