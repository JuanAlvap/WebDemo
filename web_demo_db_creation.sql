-- 1) Base de datos
IF DB_ID('MiniEcommerce') IS NULL
    CREATE DATABASE MiniEcommerce;
GO
USE MiniEcommerce;
GO

-- 2) Tablas simples: Usuarios, Productos, Ordenes, Detalle
CREATE TABLE dbo.Usuarios (
    UsuarioID INT IDENTITY(1,1) PRIMARY KEY,
    Nombre    NVARCHAR(80) NOT NULL,
    Email     NVARCHAR(120) NOT NULL UNIQUE,
    Pass      NVARCHAR(120) NOT NULL,
    Rol       NVARCHAR(10) NOT NULL CHECK (Rol IN ('user','admin'))
);

CREATE TABLE dbo.Productos (
    ProductoID INT IDENTITY(1,1) PRIMARY KEY,
    Nombre     NVARCHAR(100) NOT NULL,
    Precio     DECIMAL(12,2) NOT NULL,
    Stock      INT NOT NULL CHECK (Stock >= 0)
);

CREATE TABLE dbo.Ordenes (
    OrdenID   INT IDENTITY(1,1) PRIMARY KEY,
    UsuarioID INT NOT NULL,
    Fecha     DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    Total     DECIMAL(12,2) NOT NULL DEFAULT 0,
    FOREIGN KEY (UsuarioID) REFERENCES dbo.Usuarios(UsuarioID)
);

CREATE TABLE dbo.DetalleOrden (
    DetalleID  INT IDENTITY(1,1) PRIMARY KEY,
    OrdenID    INT NOT NULL,
    ProductoID INT NOT NULL,
    Cantidad   INT NOT NULL CHECK (Cantidad > 0),
    PrecioUnit DECIMAL(12,2) NOT NULL,
    FOREIGN KEY (OrdenID) REFERENCES dbo.Ordenes(OrdenID),
    FOREIGN KEY (ProductoID) REFERENCES dbo.Productos(ProductoID)
);
GO

-- 3) Datos iniciales: admin + algunos productos
INSERT INTO dbo.Usuarios (Nombre, Email, Pass, Rol)
VALUES ('Admin', 'admin@demo.com', 'admin123', 'admin');

INSERT INTO dbo.Productos (Nombre, Precio, Stock)
VALUES
('Teclado Mecánico', 220000, 10),
('Mouse Gamer', 120000, 8),
('SSD 1TB', 350000, 3);
GO


USE MiniEcommerce;
GO

-- Tabla resumen para OLAP (batch)
IF OBJECT_ID('dbo.ReporteVentasProducto') IS NOT NULL
    DROP TABLE dbo.ReporteVentasProducto;
GO

CREATE TABLE dbo.ReporteVentasProducto (
    ProductoID   INT PRIMARY KEY,
    Nombre       NVARCHAR(100) NOT NULL,
    Unidades     INT NOT NULL,
    IngresoTotal DECIMAL(12,2) NOT NULL,
    UltimaActualizacion DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);
GO

-- "ETL" básico: recalcula el resumen desde OLTP
CREATE OR ALTER PROCEDURE dbo.sp_ActualizarReporteVentasProducto
AS
BEGIN
    SET NOCOUNT ON;

    -- Recalcular completo (simple para clase)
    TRUNCATE TABLE dbo.ReporteVentasProducto;

    INSERT INTO dbo.ReporteVentasProducto (ProductoID, Nombre, Unidades, IngresoTotal, UltimaActualizacion)
    SELECT
        p.ProductoID,
        p.Nombre,
        COALESCE(SUM(d.Cantidad), 0) AS Unidades,
        COALESCE(SUM(d.Cantidad * d.PrecioUnit), 0) AS IngresoTotal,
        SYSDATETIME()
    FROM dbo.Productos p
    LEFT JOIN dbo.DetalleOrden d ON d.ProductoID = p.ProductoID
    LEFT JOIN dbo.Ordenes o ON o.OrdenID = d.OrdenID
    GROUP BY p.ProductoID, p.Nombre;
END
GO


select * from dbo.Usuarios;

select * from dbo.Productos;
