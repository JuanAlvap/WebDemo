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

IF OBJECT_ID('dbo.ReporteTopProductoDiaSemana') IS NOT NULL
    DROP TABLE dbo.ReporteTopProductoDiaSemana;
GO

CREATE TABLE dbo.ReporteTopProductoDiaSemana (
    DiaSemana  INT NOT NULL,              -- 1=Lunes ... 7=Domingo (lo fijamos en el ETL)
    ProductoID INT NOT NULL,
    Nombre     NVARCHAR(100) NOT NULL,
    Unidades   INT NOT NULL,
    UltimaActualizacion DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT PK_ReporteTopProductoDiaSemana PRIMARY KEY (DiaSemana, ProductoID)
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

    -- ---------------------------------------------------------
-- NUEVO: Reporte TOP producto por día de la semana (OLAP)
-- ---------------------------------------------------------

-- Para que 1 = Lunes, 7 = Domingo (importante para la gráfica)
SET DATEFIRST 1;

-- Tabla temporal con ventas agregadas por (día, producto)
IF OBJECT_ID('tempdb..#VentasDiaProducto') IS NOT NULL
    DROP TABLE #VentasDiaProducto;

CREATE TABLE #VentasDiaProducto (
    DiaSemana INT,
    ProductoID INT,
    Unidades INT
);

INSERT INTO #VentasDiaProducto (DiaSemana, ProductoID, Unidades)
SELECT
    DATEPART(WEEKDAY, o.Fecha) AS DiaSemana,
    d.ProductoID,
    SUM(d.Cantidad) AS Unidades
FROM dbo.Ordenes o
JOIN dbo.DetalleOrden d ON d.OrdenID = o.OrdenID
GROUP BY DATEPART(WEEKDAY, o.Fecha), d.ProductoID;

-- Limpiar el resumen OLAP
TRUNCATE TABLE dbo.ReporteTopProductoDiaSemana;

-- Insertar el/los productos TOP por día (si hay empate, mete ambos)
INSERT INTO dbo.ReporteTopProductoDiaSemana (DiaSemana, ProductoID, Nombre, Unidades, UltimaActualizacion)
SELECT
    v.DiaSemana,
    v.ProductoID,
    p.Nombre,
    v.Unidades,
    SYSDATETIME()
FROM #VentasDiaProducto v
JOIN (
    SELECT DiaSemana, MAX(Unidades) AS MaxUnidades
    FROM #VentasDiaProducto
    GROUP BY DiaSemana
) mx
    ON mx.DiaSemana = v.DiaSemana AND mx.MaxUnidades = v.Unidades
JOIN dbo.Productos p
    ON p.ProductoID = v.ProductoID;

END
GO


select * from dbo.Usuarios;

select * from dbo.Productos;

Select * from dbo.Ordenes;

select * from dbo.DetalleOrden;

select * from ReporteTopProductoDiaSemana;
