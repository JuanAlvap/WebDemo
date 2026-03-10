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
    SET DATEFIRST 1;

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

-- Para calcular la semana actual
    DECLARE @Hoy DATE = CAST(SYSDATETIME() AS DATE);
    DECLARE @InicioSemana DATE = DATEADD(DAY, 1 - DATEPART(WEEKDAY, @Hoy), @Hoy);
    DECLARE @FinSemana DATE = DATEADD(DAY, 7, @InicioSemana);

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
WHERE o.Fecha >= @InicioSemana
    AND o.Fecha < @FinSemana
GROUP BY DATEPART(WEEKDAY, o.Fecha), d.ProductoID;

-- Limpiar el resumen OLAP
TRUNCATE TABLE dbo.ReporteTopProductoDiaSemana;

-- Insertar solo 1 producto TOP por día
-- Si hay empate en unidades, gana el ProductoID menor (regla fija y simple)
INSERT INTO dbo.ReporteTopProductoDiaSemana (DiaSemana, ProductoID, Nombre, Unidades, UltimaActualizacion)
SELECT
    x.DiaSemana,
    x.ProductoID,
    p.Nombre,
    x.Unidades,
    SYSDATETIME()
FROM (
    SELECT
        v.DiaSemana,
        v.ProductoID,
        v.Unidades,
        ROW_NUMBER() OVER (
            PARTITION BY v.DiaSemana
            ORDER BY v.Unidades DESC, v.ProductoID ASC
        ) AS rn
    FROM #VentasDiaProducto v
) x
JOIN dbo.Productos p
    ON p.ProductoID = x.ProductoID
WHERE x.rn = 1;

END
GO


select * from dbo.Usuarios;

select * from dbo.Productos;

Select * from dbo.Ordenes;

select * from dbo.DetalleOrden;

select * from ReporteTopProductoDiaSemana;

update dbo.Productos set Stock = 100 where ProductoID > 0;