USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   37 — FORMAS DE PAGO

   ANTES
   La venta distinguia solo Contado y CuentaCorriente, y todo lo
   cobrado entraba a la caja fisica. Una venta con tarjeta sumaba al
   arqueo dinero que nunca estuvo en el cajon.

   AHORA
   - MedioPago: efectivo, transferencia, QR, debito, credito. Cada uno
     con su comision y la cuenta a la que va la plata.
   - CuentaFinanciera: caja fisica, banco, Mercado Pago.
   - VentaPago: los pagos de cada venta. Uno o varios (pago mixto).
   - MovimientoCuentaFinanciera: los movimientos de banco y MP.

   LA CAJA FISICA NO SE TOCA. MovimientoCaja sigue siendo solo
   efectivo, que es lo que se cuenta en el arqueo.

   LA COMISION SE REGISTRA COMO EGRESO, no se esconde en el neto.
   Queda visible cuanto se llevan las tarjetas.

   COMPATIBILIDAD: SP_Venta_I sigue aceptando @FormaPago y @Entrega.
   Si no vienen pagos, se comporta como antes. La app mobile no se
   rompe.
   ================================================================= */


/* -----------------------------------------------------------------
   1. Cuentas financieras
   ----------------------------------------------------------------- */
IF OBJECT_ID('CuentaFinanciera', 'U') IS NULL
BEGIN
    CREATE TABLE CuentaFinanciera (
        Id      INT IDENTITY(1,1) PRIMARY KEY,
        Codigo  VARCHAR(10)  NOT NULL UNIQUE,
        Nombre  NVARCHAR(60) NOT NULL,
        EsCaja  BIT NOT NULL DEFAULT 0,   -- 1 = efectivo fisico, va a MovimientoCaja
        Activo  BIT NOT NULL DEFAULT 1
    );

    INSERT INTO CuentaFinanciera (Codigo, Nombre, EsCaja) VALUES
        ('CAJA',  N'Caja física',      1),
        ('BANCO', N'Cuenta bancaria',  0),
        ('MP',    N'Mercado Pago',     0);
END
GO


/* -----------------------------------------------------------------
   2. Medios de pago

   La comision es un dato, no esta en el codigo. El negocio informo
   ~5% para tarjetas; se puede ajustar por medio desde la tabla.
   ----------------------------------------------------------------- */
IF OBJECT_ID('MedioPago', 'U') IS NULL
BEGIN
    CREATE TABLE MedioPago (
        Id                 INT IDENTITY(1,1) PRIMARY KEY,
        Codigo             VARCHAR(10)  NOT NULL UNIQUE,
        Nombre             NVARCHAR(40) NOT NULL,
        ComisionPorc       DECIMAL(5,2) NOT NULL DEFAULT 0,
        IdCuentaFinanciera INT NOT NULL,
        Orden              TINYINT NOT NULL DEFAULT 99,
        Activo             BIT NOT NULL DEFAULT 1,
        CONSTRAINT FK_MedioPago_Cuenta FOREIGN KEY (IdCuentaFinanciera) REFERENCES CuentaFinanciera(Id)
    );

    INSERT INTO MedioPago (Codigo, Nombre, ComisionPorc, IdCuentaFinanciera, Orden)
    SELECT 'EFE', N'Efectivo',      0,    Id, 1 FROM CuentaFinanciera WHERE Codigo = 'CAJA'
    UNION ALL
    SELECT 'TRF', N'Transferencia', 0,    Id, 2 FROM CuentaFinanciera WHERE Codigo = 'BANCO'
    UNION ALL
    SELECT 'QR',  N'QR Mercado Pago', 5,  Id, 3 FROM CuentaFinanciera WHERE Codigo = 'MP'
    UNION ALL
    SELECT 'DEB', N'Débito',        5,    Id, 4 FROM CuentaFinanciera WHERE Codigo = 'BANCO'
    UNION ALL
    SELECT 'CRE', N'Crédito',       5,    Id, 5 FROM CuentaFinanciera WHERE Codigo = 'BANCO';
END
GO


/* -----------------------------------------------------------------
   3. Pagos de cada venta
   ----------------------------------------------------------------- */
IF OBJECT_ID('VentaPago', 'U') IS NULL
BEGIN
    CREATE TABLE VentaPago (
        Id            INT IDENTITY(1,1) PRIMARY KEY,
        IdVenta       INT NOT NULL,
        IdMedioPago   INT NOT NULL,
        Monto         DECIMAL(12,2) NOT NULL,   -- lo que pago el cliente
        ComisionPorc  DECIMAL(5,2)  NOT NULL,   -- congelada al momento
        Comision      DECIMAL(12,2) NOT NULL,   -- Monto * ComisionPorc / 100
        Neto          DECIMAL(12,2) NOT NULL,   -- Monto - Comision
        Fecha         DATETIME NOT NULL DEFAULT GETDATE(),
        CONSTRAINT FK_VentaPago_Venta FOREIGN KEY (IdVenta) REFERENCES Venta(Id),
        CONSTRAINT FK_VentaPago_Medio FOREIGN KEY (IdMedioPago) REFERENCES MedioPago(Id),
        CONSTRAINT CK_VentaPago_Monto CHECK (Monto > 0)
    );
    CREATE INDEX IX_VentaPago_Venta ON VentaPago(IdVenta);
END
GO


/* -----------------------------------------------------------------
   4. Movimientos de banco y Mercado Pago

   Espejo de MovimientoCaja pero para las cuentas que no son efectivo.
   Sin SaldoResultante congelado: el saldo se deriva con SUM, como en
   cuenta corriente. Banco y MP no se arquean a mano.
   ----------------------------------------------------------------- */
IF OBJECT_ID('MovimientoCuentaFinanciera', 'U') IS NULL
BEGIN
    CREATE TABLE MovimientoCuentaFinanciera (
        Id                 INT IDENTITY(1,1) PRIMARY KEY,
        IdCuentaFinanciera INT NOT NULL,
        Fecha              DATETIME NOT NULL DEFAULT GETDATE(),
        Tipo               VARCHAR(10) NOT NULL,      -- 'Ingreso' | 'Egreso'
        Concepto           NVARCHAR(60) NOT NULL,
        Monto              DECIMAL(12,2) NOT NULL,
        Descripcion        NVARCHAR(250) NULL,
        IdUsuario          INT NOT NULL,
        IdVenta            INT NULL,
        IdVentaPago        INT NULL,
        Automatico         BIT NOT NULL DEFAULT 1,
        CONSTRAINT FK_MovCF_Cuenta FOREIGN KEY (IdCuentaFinanciera) REFERENCES CuentaFinanciera(Id),
        CONSTRAINT FK_MovCF_Venta  FOREIGN KEY (IdVenta) REFERENCES Venta(Id),
        CONSTRAINT CK_MovCF_Tipo CHECK (Tipo IN ('Ingreso', 'Egreso'))
    );
    CREATE INDEX IX_MovCF_Cuenta ON MovimientoCuentaFinanciera(IdCuentaFinanciera, Fecha);
    CREATE INDEX IX_MovCF_Venta  ON MovimientoCuentaFinanciera(IdVenta);
END
GO


/* -----------------------------------------------------------------
   5. Tipo de tabla para los pagos
   ----------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.types WHERE name = 'VentaPagoType')
    CREATE TYPE VentaPagoType AS TABLE (
        IdMedioPago INT NOT NULL,
        Monto       DECIMAL(12,2) NOT NULL
    );
GO


/* -----------------------------------------------------------------
   6. Consultas
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_MedioPago_GetAll', 'P') IS NOT NULL DROP PROCEDURE SP_MedioPago_GetAll;
GO
CREATE PROCEDURE SP_MedioPago_GetAll
AS
BEGIN
    SET NOCOUNT ON;
    SELECT m.Id, m.Codigo, m.Nombre, m.ComisionPorc, m.Orden, m.Activo,
           c.Id AS IdCuentaFinanciera, c.Nombre AS Cuenta, c.EsCaja
    FROM MedioPago m
    INNER JOIN CuentaFinanciera c ON c.Id = m.IdCuentaFinanciera
    WHERE m.Activo = 1
    ORDER BY m.Orden;
END
GO

IF OBJECT_ID('SP_VentaPago_GetByVenta', 'P') IS NOT NULL DROP PROCEDURE SP_VentaPago_GetByVenta;
GO
CREATE PROCEDURE SP_VentaPago_GetByVenta @IdVenta INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT vp.Id, vp.IdMedioPago, m.Nombre AS Medio, m.Codigo,
           vp.Monto, vp.ComisionPorc, vp.Comision, vp.Neto, vp.Fecha
    FROM VentaPago vp
    INNER JOIN MedioPago m ON m.Id = vp.IdMedioPago
    WHERE vp.IdVenta = @IdVenta
    ORDER BY vp.Id;
END
GO

-- Saldo y movimientos de banco / MP
IF OBJECT_ID('SP_CuentaFinanciera_Resumen', 'P') IS NOT NULL DROP PROCEDURE SP_CuentaFinanciera_Resumen;
GO
CREATE PROCEDURE SP_CuentaFinanciera_Resumen
    @Desde DATE = NULL,
    @Hasta DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @Desde IS NULL SET @Desde = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1);
    IF @Hasta IS NULL SET @Hasta = CAST(GETDATE() AS DATE);

    SELECT
        c.Id, c.Codigo, c.Nombre, c.EsCaja,
        -- Del periodo
        ISNULL(SUM(CASE WHEN m.Tipo = 'Ingreso' AND CAST(m.Fecha AS DATE) BETWEEN @Desde AND @Hasta THEN m.Monto END), 0) AS Ingresos,
        ISNULL(SUM(CASE WHEN m.Tipo = 'Egreso'  AND CAST(m.Fecha AS DATE) BETWEEN @Desde AND @Hasta THEN m.Monto END), 0) AS Egresos,
        ISNULL(SUM(CASE WHEN m.Concepto LIKE 'Comisi%' AND CAST(m.Fecha AS DATE) BETWEEN @Desde AND @Hasta THEN m.Monto END), 0) AS Comisiones,
        -- Acumulado total
        ISNULL(SUM(CASE WHEN m.Tipo = 'Ingreso' THEN m.Monto ELSE -m.Monto END), 0) AS Saldo
    FROM CuentaFinanciera c
    LEFT JOIN MovimientoCuentaFinanciera m ON m.IdCuentaFinanciera = c.Id
    WHERE c.Activo = 1 AND c.EsCaja = 0
    GROUP BY c.Id, c.Codigo, c.Nombre, c.EsCaja
    ORDER BY c.Id;
END
GO

-- Cuanto se cobro por cada medio en un periodo
IF OBJECT_ID('SP_Venta_PorMedioPago', 'P') IS NOT NULL DROP PROCEDURE SP_Venta_PorMedioPago;
GO
CREATE PROCEDURE SP_Venta_PorMedioPago
    @Desde DATE = NULL,
    @Hasta DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @Desde IS NULL SET @Desde = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1);
    IF @Hasta IS NULL SET @Hasta = CAST(GETDATE() AS DATE);

    SELECT m.Nombre AS Medio, m.Codigo,
           COUNT(vp.Id)     AS Operaciones,
           SUM(vp.Monto)    AS Cobrado,
           SUM(vp.Comision) AS Comisiones,
           SUM(vp.Neto)     AS Neto
    FROM VentaPago vp
    INNER JOIN MedioPago m ON m.Id = vp.IdMedioPago
    INNER JOIN Venta v ON v.Id = vp.IdVenta
    WHERE v.IdEstadoVenta = 1
      AND CAST(v.Fecha AS DATE) BETWEEN @Desde AND @Hasta
    GROUP BY m.Nombre, m.Codigo, m.Orden
    ORDER BY m.Orden;
END
GO

SELECT * FROM CuentaFinanciera;
SELECT m.Codigo, m.Nombre, m.ComisionPorc, c.Nombre AS Cuenta FROM MedioPago m
INNER JOIN CuentaFinanciera c ON c.Id = m.IdCuentaFinanciera ORDER BY m.Orden;
GO
