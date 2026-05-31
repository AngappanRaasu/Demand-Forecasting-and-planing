-- Run this script in SQL Server Management Studio (SSMS) or Azure Data Studio
-- It creates a sample source database with the required tables and sample data

USE master;
GO

-- Create the Database
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'SampleSourceDB')
BEGIN
    CREATE DATABASE SampleSourceDB;
END
GO

USE SampleSourceDB;
GO

-- 1. Create Tables
CREATE TABLE Industries (
    Id INT PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL
);

CREATE TABLE Companies (
    Id INT PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    IndustryId INT NOT NULL FOREIGN KEY REFERENCES Industries(Id)
);

CREATE TABLE Categories (
    Id INT PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    CompanyId INT NOT NULL FOREIGN KEY REFERENCES Companies(Id)
);

CREATE TABLE Items (
    Id INT PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    CategoryId INT NOT NULL FOREIGN KEY REFERENCES Categories(Id)
);

CREATE TABLE SalesHistories (
    Id INT PRIMARY KEY IDENTITY(1,1),
    ItemId INT NOT NULL FOREIGN KEY REFERENCES Items(Id),
    Date DATETIME2 NOT NULL,
    Quantity FLOAT NOT NULL
);
GO

-- 2. Insert Sample Data
INSERT INTO Industries (Id, Name) VALUES 
(1, 'Retail'), 
(2, 'Manufacturing');

INSERT INTO Companies (Id, Name, IndustryId) VALUES 
(1, 'TechGadgets Inc', 1),
(2, 'AutoParts Co', 2);

INSERT INTO Categories (Id, Name, CompanyId) VALUES 
(1, 'Smartphones', 1),
(2, 'Laptops', 1),
(3, 'Engine Components', 2);

INSERT INTO Items (Id, Name, CategoryId) VALUES 
(1, 'Phone X 128GB', 1),
(2, 'Phone X 256GB', 1),
(3, 'Laptop Pro 15"', 2),
(4, 'V6 Engine Block', 3);

-- Generate sample sales history data (past 24 months)
DECLARE @ItemId INT = 1;
DECLARE @Month INT = 1;

WHILE @ItemId <= 4
BEGIN
    SET @Month = 1;
    WHILE @Month <= 24
    BEGIN
        INSERT INTO SalesHistories (ItemId, Date, Quantity)
        VALUES (
            @ItemId, 
            DATEADD(MONTH, -@Month, GETDATE()), 
            -- Random quantity between 100 and 500
            ABS(CHECKSUM(NEWID()) % 400) + 100 
        );
        SET @Month = @Month + 1;
    END
    SET @ItemId = @ItemId + 1;
END
GO

PRINT 'Sample database created successfully!';
