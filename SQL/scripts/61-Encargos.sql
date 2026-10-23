USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   61 — ENCARGOS CON SEÑA

   Un cliente pide un repuesto que no hay en stock. Se toma el encargo
   con su nombre y telefono (o el cliente registrado), opcionalmente
   deja una seña, se le avisa por WhatsApp cuando llega y se entrega con
   una venta normal en la que la seña ya cuenta como pagada.

   LA SEÑA ES DINERO, ASI QUE TIENE DOCUMENTO
   - Al recibirla, entra a la caja o a Mercado Pago con origen en el
     encargo (y su comision, si es electronica).
   - A la vez queda registrada como deuda con el cliente en la cuenta
     "Señas de clientes", que no es dinero disponible: su saldo negativo
     es lo que el negocio debe en señas.
   - Al entregar, la venta se cobra con el medio "Seña aplicada" (SEN)
     por el importe de la seña, mas lo que falte con medios normales.
     SEN no mueve dinero: solo cancela la deuda en "Señas de clientes".
   - Si se cancela, la seña se devuelve, queda a favor en la cuenta
     corriente del cliente o se retiene. Lo decide el vendedor.

   ESTADOS
   Se guardan PENDIENTE, AVISADO, ENTREGADO y CANCELADO. Si hay stock
   para entregarlo o si ya esta pedido al proveedor NO se guarda: se
   calcula en cada consulta mirando el stock y los pedidos pendientes.

   Requiere los scripts 37 a 49.
   ================================================================= */


/* -----------------------------------------------------------------
   1. Cuenta de señas y medio "Seña aplicada"
   ----------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM CuentaFinanciera WHERE Codigo = 'SENAS')
    INSERT INTO CuentaFinanciera (Codigo, Nombre, EsCaja, Activo, EsDisponible)
    VALUES ('SENAS', N'Señas de clientes', 0, 1, 0);
GO

IF NOT EXISTS (SELECT 1 FROM MedioPago WHERE Codigo = 'SEN')
    INSERT INTO MedioPago (Codigo, Nombre, ComisionPorc, IdCuentaFinanciera, Orden)
    SELECT 'SEN', N'Seña aplicada', 0, Id, 90 FROM CuentaFinanciera WHERE Codigo = 'SENAS';
GO

-- Los botones de cobro muestran solo medios que mueven dinero disponible:
-- "Seña aplicada" no aparece en la venta comun ni en la app
ALTER PROCEDURE SP_MedioPago_GetAll
AS
BEGIN
    SET NOCOUNT ON;
    SELECT m.Id, m.Codigo, m.Nombre, m.ComisionPorc, m.Orden, m.Activo,
           c.Id AS IdCuentaFinanciera, c.Nombre AS Cuenta, c.EsCaja
    FROM MedioPago m
    INNER JOIN CuentaFinanciera c ON c.Id = m.IdCuentaFinanciera
    WHERE m.Activo = 1 AND c.EsDisponible = 1
    ORDER BY m.Orden;
END
GO

-- El panel de cuentas de la caja muestra el dinero disponible; las señas
-- se ven en la pantalla de encargos
ALTER PROCEDURE SP_CuentaFinanciera_Resumen
    @Desde DATE = NULL,
    @Hasta DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @Desde IS NULL SET @Desde = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1);
    IF @Hasta IS NULL SET @Hasta = CAST(GETDATE() AS DATE);

    SELECT
        c.Id, c.Codigo, c.Nombre, c.EsCaja,
        ISNULL(SUM(CASE WHEN m.Tipo = 'Ingreso' AND CAST(m.Fecha AS DATE) BETWEEN @Desde AND @Hasta THEN m.Monto END), 0) AS Ingresos,
        ISNULL(SUM(CASE WHEN m.Tipo = 'Egreso'  AND CAST(m.Fecha AS DATE) BETWEEN @Desde AND @Hasta THEN m.Monto END), 0) AS Egresos,
        ISNULL(SUM(CASE WHEN m.Concepto LIKE 'Comisi%' AND CAST(m.Fecha AS DATE) BETWEEN @Desde AND @Hasta THEN m.Monto END), 0) AS Comisiones,
        ISNULL(SUM(CASE WHEN m.Tipo = 'Ingreso' THEN m.Monto ELSE -m.Monto END), 0) AS Saldo
    FROM CuentaFinanciera c
    LEFT JOIN MovimientoCuentaFinanciera m ON m.IdCuentaFinanciera = c.Id
    WHERE c.Activo = 1 AND c.EsCaja = 0 AND c.EsDisponible = 1
    GROUP BY c.Id, c.Codigo, c.Nombre, c.EsCaja
    ORDER BY c.Id;
END
GO


/* -----------------------------------------------------------------
   2. Tablas
   ----------------------------------------------------------------- */
IF OBJECT_ID('Encargo', 'U') IS NULL
BEGIN
    CREATE TABLE Encargo (
        Id                 INT IDENTITY(1,1) PRIMARY KEY,
        Fecha              DATETIME      NOT NULL DEFAULT GETDATE(),
        IdCliente          INT           NULL,          -- si esta registrado
        Nombre             NVARCHAR(80)  NOT NULL,
        Telefono           NVARCHAR(30)  NOT NULL,
        Observacion        NVARCHAR(250) NULL,
        Estado             VARCHAR(12)   NOT NULL DEFAULT 'PENDIENTE',
        FechaAviso         DATETIME      NULL,
        IdVenta            INT           NULL,
        FechaEntrega       DATETIME      NULL,
        FechaCancelacion   DATETIME      NULL,
        MotivoCancelacion  NVARCHAR(250) NULL,
        ResolucionSena     VARCHAR(10)   NULL,          -- DEVUELTA | A_FAVOR | RETENIDA
        IdUsuario          INT           NOT NULL,
        CONSTRAINT FK_Encargo_Cliente FOREIGN KEY (IdCliente) REFERENCES Cliente(Id),
        CONSTRAINT FK_Encargo_Venta   FOREIGN KEY (IdVenta)   REFERENCES Venta(Id),
        CONSTRAINT CK_Encargo_Estado  CHECK (Estado IN ('PENDIENTE', 'AVISADO', 'ENTREGADO', 'CANCELADO')),
        CONSTRAINT CK_Encargo_Resol   CHECK (ResolucionSena IS NULL OR ResolucionSena IN ('DEVUELTA', 'A_FAVOR', 'RETENIDA'))
    );
    CREATE INDEX IX_Encargo_Estado ON Encargo(Estado, Fecha);
END
GO

IF OBJECT_ID('EncargoDetalle', 'U') IS NULL
BEGIN
    CREATE TABLE EncargoDetalle (
        Id            INT IDENTITY(1,1) PRIMARY KEY,
        IdEncargo     INT           NOT NULL,
        IdRepuesto    INT           NOT NULL,
        Cantidad      INT           NOT NULL,
        PrecioPactado DECIMAL(12,2) NOT NULL,   -- el precio que se le dijo al cliente
        CONSTRAINT FK_EncDet_Encargo  FOREIGN KEY (IdEncargo)  REFERENCES Encargo(Id),
        CONSTRAINT FK_EncDet_Repuesto FOREIGN KEY (IdRepuesto) REFERENCES Repuesto(Id),
        CONSTRAINT CK_EncDet_Cant     CHECK (Cantidad > 0),
        CONSTRAINT CK_EncDet_Precio   CHECK (PrecioPactado >= 0)
    );
    CREATE INDEX IX_EncDet_Encargo ON EncargoDetalle(IdEncargo);
END
GO

IF OBJECT_ID('EncargoSena', 'U') IS NULL
BEGIN
    CREATE TABLE EncargoSena (
        Id           INT IDENTITY(1,1) PRIMARY KEY,
        IdEncargo    INT           NOT NULL,
        Fecha        DATETIME      NOT NULL DEFAULT GETDATE(),
        IdMedioPago  INT           NOT NULL,
        Monto        DECIMAL(12,2) NOT NULL,
        Comision     DECIMAL(12,2) NOT NULL DEFAULT 0,
        IdUsuario    INT           NOT NULL,
        CONSTRAINT FK_EncSena_Encargo FOREIGN KEY (IdEncargo)   REFERENCES Encargo(Id),
        CONSTRAINT FK_EncSena_Medio   FOREIGN KEY (IdMedioPago) REFERENCES MedioPago(Id),
        CONSTRAINT CK_EncSena_Monto   CHECK (Monto > 0)
    );
END
GO

IF TYPE_ID('EncargoLineaType') IS NULL
    CREATE TYPE EncargoLineaType AS TABLE (
        IdRepuesto    INT           NOT NULL,
        Cantidad      INT           NOT NULL,
        PrecioPactado DECIMAL(12,2) NOT NULL
    );
GO


/* -----------------------------------------------------------------
   3. Origen del dinero: los movimientos pueden apuntar al encargo
   ----------------------------------------------------------------- */
IF COL_LENGTH('MovimientoCaja', 'IdEncargo') IS NULL
    ALTER TABLE MovimientoCaja ADD IdEncargo INT NULL CONSTRAINT FK_MovCaja_Encargo REFERENCES Encargo(Id);
GO
IF COL_LENGTH('MovimientoCuentaFinanciera', 'IdEncargo') IS NULL
    ALTER TABLE MovimientoCuentaFinanciera ADD IdEncargo INT NULL CONSTRAINT FK_MovCF_Encargo REFERENCES Encargo(Id);
GO
IF COL_LENGTH('MovimientoCuentaCorriente', 'IdEncargo') IS NULL
    ALTER TABLE MovimientoCuentaCorriente ADD IdEncargo INT NULL CONSTRAINT FK_MovCC_Encargo REFERENCES Encargo(Id);
GO

/* -----------------------------------------------------------------
   4. Los registros de dinero aceptan el encargo como origen
   ----------------------------------------------------------------- */
ALTER PROCEDURE [dbo].[SP_MovimientoCaja_RegistrarInterno]
    @Tipo                 NVARCHAR(10),
    @Concepto             NVARCHAR(60),
    @Monto                DECIMAL(12,2),
    @Descripcion          NVARCHAR(250),
    @IdUsuario            INT,
    @IdVenta              INT = NULL,
    @IdPedido             INT = NULL,
    @IdGasto              INT = NULL,
    @IdMovimientoEspecial INT = NULL,
    @IdPagoProveedor      INT = NULL,
    @IdNotaCliente        INT = NULL,
    @IdEncargo            INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Monto IS NULL OR @Monto <= 0
        THROW 50020, 'El importe del movimiento de caja debe ser mayor a cero.', 1;
    IF @Tipo NOT IN ('Ingreso', 'Egreso')
        THROW 50021, 'El tipo de movimiento debe ser Ingreso o Egreso.', 1;

    DECLARE @IdSesion INT;
    SELECT @IdSesion = s.Id
    FROM SesionCaja s INNER JOIN CuentaFinanciera c ON c.Id = s.IdCuentaFinanciera
    WHERE s.Estado = 'ABIERTA' AND c.EsCaja = 1;

    IF @IdSesion IS NULL
        THROW 50022, 'La caja esta cerrada. Abri la caja desde el menu Caja para registrar movimientos en efectivo.', 1;

    DECLARE @SaldoActual DECIMAL(12,2);
    SELECT TOP 1 @SaldoActual = SaldoResultante
    FROM MovimientoCaja WITH (UPDLOCK, HOLDLOCK)
    ORDER BY Id DESC;
    IF @SaldoActual IS NULL SET @SaldoActual = 0;

    DECLARE @NuevoSaldo DECIMAL(12,2) =
        CASE WHEN @Tipo = 'Ingreso' THEN @SaldoActual + @Monto ELSE @SaldoActual - @Monto END;

    INSERT INTO MovimientoCaja
        (Tipo, Concepto, Monto, Descripcion, SaldoResultante, IdUsuario,
         IdVenta, IdPedido, IdGasto, IdMovimientoEspecial, IdPagoProveedor, IdNotaCliente, IdEncargo, IdSesionCaja, Automatico)
    VALUES
        (@Tipo, @Concepto, @Monto, @Descripcion, @NuevoSaldo, @IdUsuario,
         @IdVenta, @IdPedido, @IdGasto, @IdMovimientoEspecial, @IdPagoProveedor, @IdNotaCliente, @IdEncargo, @IdSesion, 1);
END
GO

ALTER PROCEDURE SP_Cuenta_RegistrarMovimiento
    @IdCuentaFinanciera   INT,
    @Tipo                 VARCHAR(10),
    @Concepto             NVARCHAR(60),
    @Monto                DECIMAL(12,2),
    @Descripcion          NVARCHAR(250),
    @IdUsuario            INT,
    @IdGasto              INT = NULL,
    @IdMovimientoEspecial INT = NULL,
    @IdPagoProveedor      INT = NULL,
    @IdNotaCliente        INT = NULL,
    @IdEncargo            INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @EsCaja BIT, @EsDisponible BIT, @Activo BIT;
    SELECT @EsCaja = EsCaja, @EsDisponible = EsDisponible, @Activo = Activo
    FROM CuentaFinanciera WHERE Id = @IdCuentaFinanciera;

    IF @EsCaja IS NULL
        THROW 50001, 'La cuenta financiera no existe.', 1;
    IF @Activo = 0
        THROW 50002, 'La cuenta financiera esta inactiva.', 1;
    IF @EsDisponible = 0
        THROW 50003, 'Esa cuenta no es dinero disponible: no se pueden registrar pagos ni movimientos sobre ella.', 1;

    IF @EsCaja = 1
        EXEC SP_MovimientoCaja_RegistrarInterno
             @Tipo = @Tipo, @Concepto = @Concepto, @Monto = @Monto, @Descripcion = @Descripcion,
             @IdUsuario = @IdUsuario, @IdGasto = @IdGasto, @IdMovimientoEspecial = @IdMovimientoEspecial,
             @IdPagoProveedor = @IdPagoProveedor, @IdNotaCliente = @IdNotaCliente, @IdEncargo = @IdEncargo;
    ELSE
        INSERT INTO MovimientoCuentaFinanciera
            (IdCuentaFinanciera, Tipo, Concepto, Monto, Descripcion, IdUsuario,
             IdGasto, IdMovimientoEspecial, IdPagoProveedor, IdNotaCliente, IdEncargo, Automatico)
        VALUES
            (@IdCuentaFinanciera, @Tipo, @Concepto, @Monto, @Descripcion, @IdUsuario,
             @IdGasto, @IdMovimientoEspecial, @IdPagoProveedor, @IdNotaCliente, @IdEncargo, 1);
END
GO


/* -----------------------------------------------------------------
   5. Registrar una seña (interno: lo usan el alta y "agregar seña")
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Encargo_RegistrarSena', 'P') IS NOT NULL DROP PROCEDURE SP_Encargo_RegistrarSena;
GO
CREATE PROCEDURE SP_Encargo_RegistrarSena
    @IdEncargo   INT,
    @IdMedioPago INT,
    @Monto       DECIMAL(12,2),
    @IdUsuario   INT
AS
BEGIN
    SET NOCOUNT ON;
    -- Se llama siempre dentro de una transaccion abierta por quien la usa

    IF @Monto IS NULL OR @Monto <= 0
        THROW 50130, 'La seña tiene que ser mayor a cero.', 1;

    DECLARE @Codigo VARCHAR(10), @ComPorc DECIMAL(5,2), @IdCuenta INT, @EsCaja BIT, @EsDisp BIT, @Nombre NVARCHAR(40);
    SELECT @Codigo = m.Codigo, @ComPorc = m.ComisionPorc, @IdCuenta = c.Id, @EsCaja = c.EsCaja,
           @EsDisp = c.EsDisponible, @Nombre = m.Nombre
    FROM MedioPago m INNER JOIN CuentaFinanciera c ON c.Id = m.IdCuentaFinanciera
    WHERE m.Id = @IdMedioPago AND m.Activo = 1 AND c.Activo = 1;

    IF @Codigo IS NULL OR @EsDisp = 0
        THROW 50131, 'Elegí con qué medio paga la seña.', 1;

    DECLARE @Comision DECIMAL(12,2) = CAST(@Monto * @ComPorc / 100.0 AS DECIMAL(12,2));
    DECLARE @Txt NVARCHAR(250) = N'Seña de encargo #' + CAST(@IdEncargo AS NVARCHAR(10));

    INSERT INTO EncargoSena (IdEncargo, IdMedioPago, Monto, Comision, IdUsuario)
    VALUES (@IdEncargo, @IdMedioPago, @Monto, @Comision, @IdUsuario);

    -- 1) El dinero entra (efectivo exige caja abierta)
    IF @EsCaja = 1
        EXEC SP_MovimientoCaja_RegistrarInterno
             @Tipo = 'Ingreso', @Concepto = N'Seña de encargo', @Monto = @Monto,
             @Descripcion = @Txt, @IdUsuario = @IdUsuario, @IdEncargo = @IdEncargo;
    ELSE
    BEGIN
        INSERT INTO MovimientoCuentaFinanciera (IdCuentaFinanciera, Tipo, Concepto, Monto, Descripcion, IdUsuario, IdEncargo)
        VALUES (@IdCuenta, 'Ingreso', LEFT(N'Seña ' + @Nombre, 60), @Monto, @Txt, @IdUsuario, @IdEncargo);
        IF @Comision > 0
            INSERT INTO MovimientoCuentaFinanciera (IdCuentaFinanciera, Tipo, Concepto, Monto, Descripcion, IdUsuario, IdEncargo)
            VALUES (@IdCuenta, 'Egreso', LEFT(N'Comision ' + @Nombre, 60), @Comision,
                    CAST(@ComPorc AS NVARCHAR(10)) + N'% sobre seña de encargo #' + CAST(@IdEncargo AS NVARCHAR(10)),
                    @IdUsuario, @IdEncargo);
    END

    -- 2) Queda la deuda con el cliente en "Señas de clientes"
    INSERT INTO MovimientoCuentaFinanciera (IdCuentaFinanciera, Tipo, Concepto, Monto, Descripcion, IdUsuario, IdEncargo)
    SELECT Id, 'Egreso', N'Seña recibida', @Monto, @Txt, @IdUsuario, @IdEncargo
    FROM CuentaFinanciera WHERE Codigo = 'SENAS';
END
GO


/* -----------------------------------------------------------------
   6. Tomar un encargo
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Encargo_I', 'P') IS NOT NULL DROP PROCEDURE SP_Encargo_I;
GO
CREATE PROCEDURE SP_Encargo_I
    @IdCliente   INT = NULL,
    @Nombre      NVARCHAR(80),
    @Telefono    NVARCHAR(30),
    @Observacion NVARCHAR(250) = NULL,
    @Lineas      EncargoLineaType READONLY,
    @IdMedioSena INT = NULL,
    @MontoSena   DECIMAL(12,2) = NULL,
    @IdUsuario   INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Nombre = LTRIM(RTRIM(ISNULL(@Nombre, '')));
    SET @Telefono = LTRIM(RTRIM(ISNULL(@Telefono, '')));

    IF @IdCliente IS NOT NULL
    BEGIN
        -- Un cliente registrado completa los datos que falten
        IF NOT EXISTS (SELECT 1 FROM Cliente WHERE Id = @IdCliente)
            THROW 50120, 'El cliente no existe.', 1;
        IF @Nombre = '' SELECT @Nombre = LTRIM(RTRIM(ISNULL(Apellido, '') + ', ' + ISNULL(Nombre, ''))) FROM Cliente WHERE Id = @IdCliente;
        IF @Telefono = '' SELECT @Telefono = ISNULL(Telefono, '') FROM Cliente WHERE Id = @IdCliente;
    END

    IF LEN(@Nombre) < 2
        THROW 50121, 'Falta el nombre del cliente.', 1;
    IF LEN(@Telefono) < 6
        THROW 50122, 'Falta el teléfono: es para avisarle cuando llegue.', 1;
    IF NOT EXISTS (SELECT 1 FROM @Lineas)
        THROW 50123, 'Indicá qué repuesto encarga.', 1;
    IF EXISTS (SELECT 1 FROM @Lineas WHERE Cantidad <= 0 OR PrecioPactado < 0)
        THROW 50124, 'Revisá cantidades y precios.', 1;
    IF EXISTS (SELECT IdRepuesto FROM @Lineas GROUP BY IdRepuesto HAVING COUNT(*) > 1)
        THROW 50125, 'Un repuesto aparece dos veces.', 1;
    IF EXISTS (SELECT 1 FROM @Lineas l WHERE NOT EXISTS (SELECT 1 FROM Repuesto r WHERE r.Id = l.IdRepuesto))
        THROW 50126, 'Uno de los repuestos no existe.', 1;

    DECLARE @Total DECIMAL(12,2) = (SELECT SUM(Cantidad * PrecioPactado) FROM @Lineas);
    IF ISNULL(@MontoSena, 0) > 0 AND @MontoSena > @Total
        THROW 50127, 'La seña no puede superar el total del encargo.', 1;
    IF ISNULL(@MontoSena, 0) > 0 AND @IdMedioSena IS NULL
        THROW 50128, 'Elegí con qué medio paga la seña.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO Encargo (IdCliente, Nombre, Telefono, Observacion, IdUsuario)
        VALUES (@IdCliente, @Nombre, @Telefono, NULLIF(LTRIM(RTRIM(@Observacion)), ''), @IdUsuario);
        DECLARE @Id INT = SCOPE_IDENTITY();

        INSERT INTO EncargoDetalle (IdEncargo, IdRepuesto, Cantidad, PrecioPactado)
        SELECT @Id, IdRepuesto, Cantidad, PrecioPactado FROM @Lineas;

        IF ISNULL(@MontoSena, 0) > 0
            EXEC SP_Encargo_RegistrarSena @IdEncargo = @Id, @IdMedioPago = @IdMedioSena, @Monto = @MontoSena, @IdUsuario = @IdUsuario;

        COMMIT TRANSACTION;
        SELECT @Id AS IdEncargo;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   7. Agregar seña a un encargo ya tomado
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Encargo_AgregarSena', 'P') IS NOT NULL DROP PROCEDURE SP_Encargo_AgregarSena;
GO
CREATE PROCEDURE SP_Encargo_AgregarSena
    @IdEncargo   INT,
    @IdMedioPago INT,
    @Monto       DECIMAL(12,2),
    @IdUsuario   INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @Estado VARCHAR(12);
        SELECT @Estado = Estado FROM Encargo WITH (UPDLOCK, HOLDLOCK) WHERE Id = @IdEncargo;
        IF @Estado IS NULL THROW 50140, 'El encargo no existe.', 1;
        IF @Estado IN ('ENTREGADO', 'CANCELADO') THROW 50141, 'El encargo ya está cerrado.', 1;

        DECLARE @Total DECIMAL(12,2) = (SELECT SUM(Cantidad * PrecioPactado) FROM EncargoDetalle WHERE IdEncargo = @IdEncargo);
        DECLARE @Sena  DECIMAL(12,2) = ISNULL((SELECT SUM(Monto) FROM EncargoSena WHERE IdEncargo = @IdEncargo), 0);
        IF @Sena + @Monto > @Total + 0.01
            THROW 50142, 'Con esta seña se superaría el total del encargo.', 1;

        EXEC SP_Encargo_RegistrarSena @IdEncargo = @IdEncargo, @IdMedioPago = @IdMedioPago, @Monto = @Monto, @IdUsuario = @IdUsuario;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   8. Listado, con la disponibilidad calculada
     EN_STOCK : hay stock para todo lo encargado -> se puede avisar
     PEDIDO   : falta stock, pero esta en un pedido pendiente
     SIN_PEDIR: falta stock y nadie lo pidio todavia
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Encargo_GetAll', 'P') IS NOT NULL DROP PROCEDURE SP_Encargo_GetAll;
GO
CREATE PROCEDURE SP_Encargo_GetAll
    @Abiertos BIT = 1      -- 1: pendientes y avisados; 0: todos los de los ultimos 90 dias
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH EnCamino AS (
        SELECT dp.IdRepuesto, SUM(dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada) AS Cant
        FROM DetallePedido dp INNER JOIN Pedido p ON p.Id = dp.IdPedido
        WHERE p.IdEstado = 1
        GROUP BY dp.IdRepuesto
    ),
    Lineas AS (
        SELECT d.IdEncargo,
               SUM(d.Cantidad * d.PrecioPactado) AS Total,
               COUNT(*) AS Renglones,
               SUM(CASE WHEN ISNULL(s.Cantidad, 0) >= d.Cantidad THEN 0 ELSE 1 END) AS SinStock,
               SUM(CASE WHEN ISNULL(s.Cantidad, 0) < d.Cantidad AND ISNULL(ec.Cant, 0) <= 0 THEN 1 ELSE 0 END) AS SinPedir,
               MIN(r.Descripcion) AS Primero
        FROM EncargoDetalle d
        INNER JOIN Repuesto r ON r.Id = d.IdRepuesto
        LEFT JOIN Stock s ON s.IdRepuesto = d.IdRepuesto
        LEFT JOIN EnCamino ec ON ec.IdRepuesto = d.IdRepuesto
        GROUP BY d.IdEncargo
    )
    SELECT e.Id, e.Fecha, e.Nombre, e.Telefono, e.IdCliente, e.Observacion, e.Estado,
           e.FechaAviso, e.IdVenta, e.FechaEntrega, e.FechaCancelacion, e.ResolucionSena,
           l.Total, l.Renglones, l.Primero,
           ISNULL((SELECT SUM(Monto) FROM EncargoSena es WHERE es.IdEncargo = e.Id), 0) AS Sena,
           CASE WHEN e.Estado IN ('ENTREGADO', 'CANCELADO') THEN NULL
                WHEN l.SinStock = 0 THEN 'EN_STOCK'
                WHEN l.SinPedir = 0 THEN 'PEDIDO'
                ELSE 'SIN_PEDIR' END AS Disponibilidad,
           DATEDIFF(DAY, e.Fecha, GETDATE()) AS Dias
    FROM Encargo e
    INNER JOIN Lineas l ON l.IdEncargo = e.Id
    WHERE (@Abiertos = 1 AND e.Estado IN ('PENDIENTE', 'AVISADO'))
       OR (@Abiertos = 0 AND e.Fecha >= DATEADD(DAY, -90, GETDATE()))
    ORDER BY CASE e.Estado WHEN 'PENDIENTE' THEN 1 WHEN 'AVISADO' THEN 2 ELSE 3 END, e.Fecha;

    -- Total de señas que el negocio tiene en su poder por encargos abiertos
    SELECT ISNULL(-SUM(CASE WHEN m.Tipo = 'Ingreso' THEN m.Monto ELSE -m.Monto END), 0) AS SenasPendientes
    FROM MovimientoCuentaFinanciera m
    INNER JOIN CuentaFinanciera c ON c.Id = m.IdCuentaFinanciera
    WHERE c.Codigo = 'SENAS';
END
GO


/* -----------------------------------------------------------------
   9. Un encargo con sus renglones (para la ficha y para la venta)
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Encargo_Get', 'P') IS NOT NULL DROP PROCEDURE SP_Encargo_Get;
GO
CREATE PROCEDURE SP_Encargo_Get @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT e.*, u.Nombre AS Usuario,
           ISNULL((SELECT SUM(Monto) FROM EncargoSena es WHERE es.IdEncargo = e.Id), 0) AS Sena,
           (SELECT SUM(Cantidad * PrecioPactado) FROM EncargoDetalle d WHERE d.IdEncargo = e.Id) AS Total,
           c.CuentaCorriente AS ClienteConCuenta,
           CASE WHEN c.Dni IN ('00000000', '00000001') THEN 1 ELSE 0 END AS ClienteGenerico,
           (SELECT Id FROM MedioPago WHERE Codigo = 'SEN') AS IdMedioSen
    FROM Encargo e
    LEFT JOIN Usuario u ON u.Id = e.IdUsuario
    LEFT JOIN Cliente c ON c.Id = e.IdCliente
    WHERE e.Id = @Id;

    SELECT d.Id, d.IdRepuesto, r.Codigo, r.Descripcion, d.Cantidad, d.PrecioPactado,
           CAST(d.Cantidad * d.PrecioPactado AS DECIMAL(12,2)) AS Subtotal,
           ISNULL(s.Cantidad, 0) AS Stock,
           ISNULL((SELECT SUM(dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada)
                   FROM DetallePedido dp INNER JOIN Pedido p ON p.Id = dp.IdPedido
                   WHERE p.IdEstado = 1 AND dp.IdRepuesto = d.IdRepuesto), 0) AS EnCamino
    FROM EncargoDetalle d
    INNER JOIN Repuesto r ON r.Id = d.IdRepuesto
    LEFT JOIN Stock s ON s.IdRepuesto = d.IdRepuesto
    WHERE d.IdEncargo = @Id
    ORDER BY r.Descripcion;

    SELECT es.Id, es.Fecha, m.Nombre AS Medio, m.Codigo, es.Monto, es.Comision
    FROM EncargoSena es INNER JOIN MedioPago m ON m.Id = es.IdMedioPago
    WHERE es.IdEncargo = @Id
    ORDER BY es.Id;
END
GO


/* -----------------------------------------------------------------
   10. Marcar que se le aviso al cliente
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Encargo_MarcarAvisado', 'P') IS NOT NULL DROP PROCEDURE SP_Encargo_MarcarAvisado;
GO
CREATE PROCEDURE SP_Encargo_MarcarAvisado @Id INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Encargo SET Estado = 'AVISADO', FechaAviso = GETDATE()
    WHERE Id = @Id AND Estado IN ('PENDIENTE', 'AVISADO');
    IF @@ROWCOUNT = 0
        THROW 50150, 'El encargo no existe o ya está cerrado.', 1;
END
GO


/* -----------------------------------------------------------------
   11. Cancelar, decidiendo que pasa con la seña
     DEVUELTA : sale el dinero de la cuenta elegida (efectivo: caja abierta)
     A_FAVOR  : queda como saldo a favor en la cuenta corriente del cliente
     RETENIDA : el cliente la pierde; el dinero ya estaba en el negocio
   En los tres casos se cancela la deuda en "Señas de clientes".
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Encargo_Cancelar', 'P') IS NOT NULL DROP PROCEDURE SP_Encargo_Cancelar;
GO
CREATE PROCEDURE SP_Encargo_Cancelar
    @Id                 INT,
    @Motivo             NVARCHAR(250),
    @Resolucion         VARCHAR(10) = NULL,
    @IdCuentaDevolucion INT = NULL,
    @IdUsuario          INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 5
            THROW 50160, 'Indicá el motivo de la cancelación.', 1;

        BEGIN TRANSACTION;

        DECLARE @Estado VARCHAR(12), @IdCliente INT;
        SELECT @Estado = Estado, @IdCliente = IdCliente FROM Encargo WITH (UPDLOCK, HOLDLOCK) WHERE Id = @Id;
        IF @Estado IS NULL THROW 50161, 'El encargo no existe.', 1;
        IF @Estado IN ('ENTREGADO', 'CANCELADO') THROW 50162, 'El encargo ya está cerrado.', 1;

        DECLARE @Sena DECIMAL(12,2) = ISNULL((SELECT SUM(Monto) FROM EncargoSena WHERE IdEncargo = @Id), 0);
        DECLARE @Txt NVARCHAR(250) = LEFT(N'Encargo #' + CAST(@Id AS NVARCHAR(10)) + N' cancelado: ' + LTRIM(RTRIM(@Motivo)), 250);

        IF @Sena > 0
        BEGIN
            IF @Resolucion NOT IN ('DEVUELTA', 'A_FAVOR', 'RETENIDA') OR @Resolucion IS NULL
                THROW 50163, 'Indicá qué pasa con la seña: se devuelve, queda a favor o se retiene.', 1;

            IF @Resolucion = 'DEVUELTA'
            BEGIN
                IF @IdCuentaDevolucion IS NULL
                    THROW 50164, 'Indicá desde qué cuenta se devuelve la seña.', 1;
                EXEC SP_Cuenta_RegistrarMovimiento
                     @IdCuentaFinanciera = @IdCuentaDevolucion, @Tipo = 'Egreso', @Concepto = N'Devolución de seña',
                     @Monto = @Sena, @Descripcion = @Txt, @IdUsuario = @IdUsuario, @IdEncargo = @Id;
            END

            IF @Resolucion = 'A_FAVOR'
            BEGIN
                IF @IdCliente IS NULL OR NOT EXISTS (SELECT 1 FROM Cliente WHERE Id = @IdCliente AND CuentaCorriente = 1
                                                     AND Dni NOT IN ('00000000', '00000001'))
                    THROW 50165, 'Para dejar la seña a favor, el cliente tiene que estar registrado con cuenta corriente.', 1;
                INSERT INTO MovimientoCuentaCorriente (IdCliente, Tipo, Concepto, Monto, IdUsuario, IdEncargo)
                VALUES (@IdCliente, 'Pago', LEFT('Seña a favor · encargo #' + CAST(@Id AS VARCHAR(10)) + ' cancelado', 120),
                        -@Sena, @IdUsuario, @Id);
            END

            -- La deuda en señas se cancela siempre
            INSERT INTO MovimientoCuentaFinanciera (IdCuentaFinanciera, Tipo, Concepto, Monto, Descripcion, IdUsuario, IdEncargo)
            SELECT Id, 'Ingreso',
                   CASE @Resolucion WHEN 'DEVUELTA' THEN N'Seña devuelta'
                                    WHEN 'A_FAVOR'  THEN N'Seña a cuenta corriente'
                                    ELSE N'Seña retenida' END,
                   @Sena, @Txt, @IdUsuario, @Id
            FROM CuentaFinanciera WHERE Codigo = 'SENAS';
        END

        UPDATE Encargo
        SET Estado = 'CANCELADO', FechaCancelacion = GETDATE(), MotivoCancelacion = LTRIM(RTRIM(@Motivo)),
            ResolucionSena = CASE WHEN @Sena > 0 THEN @Resolucion END
        WHERE Id = @Id;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   12. Venta: aplica la seña y cierra el encargo
   ----------------------------------------------------------------- */
ALTER PROCEDURE [dbo].[SP_Venta_I]
    @IdCliente           INT,
    @IdUsuario           INT,
    @Detalle             DetalleVentaType READONLY,
    -- nuevos
    @PorcentajeDescuento DECIMAL(6,2)  = 0,
    @FormaPago           VARCHAR(20)   = 'Contado',   -- 'Contado' | 'CuentaCorriente'
    @Entrega             DECIMAL(12,2) = NULL,        -- parte que paga en el momento
    @NombreOcasional     NVARCHAR(80)  = NULL,
    @TelefonoOcasional   NVARCHAR(30)  = NULL,
    @TipoCliente         NVARCHAR(20)  = NULL,        -- 'Publico' | 'Mecanico'
    -- formas de pago: lista de (medio, monto). Si viene vacia, se usan
    -- @FormaPago y @Entrega como antes (compatibilidad con clientes viejos)
    @Pagos               VentaPagoType READONLY,
    -- Entrega de un encargo: la sena ya cobrada se aplica con el medio SEN
    @IdEncargo           INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        /* ---------- Validaciones de cabecera ---------- */

        IF NOT EXISTS (SELECT 1 FROM @Detalle)
            RAISERROR('La venta debe tener al menos un repuesto.', 16, 1);

        IF EXISTS (SELECT IdRepuesto FROM @Detalle GROUP BY IdRepuesto HAVING COUNT(*) > 1)
            RAISERROR('Hay un repuesto repetido en el detalle de la venta.', 16, 1);

        IF @PorcentajeDescuento IS NULL SET @PorcentajeDescuento = 0;

        IF @PorcentajeDescuento < 0 OR @PorcentajeDescuento > 100
            RAISERROR('El descuento debe estar entre 0 y 100.', 16, 1);

        IF @FormaPago IS NULL OR @FormaPago = '' SET @FormaPago = 'Contado';

        IF @FormaPago NOT IN ('Contado', 'CuentaCorriente')
            RAISERROR('La forma de pago debe ser Contado o CuentaCorriente.', 16, 1);

        /* ---------- Stock ----------
           UPDLOCK + HOLDLOCK: sin eso, dos ventas simultaneas del
           ultimo ejemplar pasan ambas la validacion y el stock queda
           en negativo. */

        DECLARE @SinFilaStock NVARCHAR(200);
        SELECT TOP 1 @SinFilaStock = r.Descripcion
        FROM @Detalle d
        INNER JOIN Repuesto r ON r.Id = d.IdRepuesto
        LEFT JOIN Stock s WITH (UPDLOCK, HOLDLOCK) ON s.IdRepuesto = d.IdRepuesto
        WHERE s.IdRepuesto IS NULL;

        IF @SinFilaStock IS NOT NULL
            RAISERROR('El repuesto "%s" no tiene stock inicializado. Registralo con un ajuste de stock antes de venderlo.', 16, 1, @SinFilaStock);

        DECLARE @RepuestoSinStock NVARCHAR(200), @Disponible INT;
        SELECT TOP 1
            @RepuestoSinStock = r.Descripcion,
            @Disponible = s.Cantidad
        FROM @Detalle d
        INNER JOIN Repuesto r ON r.Id = d.IdRepuesto
        INNER JOIN Stock s WITH (UPDLOCK, HOLDLOCK) ON s.IdRepuesto = d.IdRepuesto
        WHERE s.Cantidad < d.Cantidad;

        IF @RepuestoSinStock IS NOT NULL
            RAISERROR('Stock insuficiente para "%s". Disponible: %d.', 16, 1, @RepuestoSinStock, @Disponible);

        /* ---------- Importes ---------- */

        DECLARE @Subtotal DECIMAL(12,2), @Descuento DECIMAL(12,2), @Total DECIMAL(12,2);

        SELECT @Subtotal = SUM(CAST(Cantidad AS DECIMAL(12,2)) * PrecioUnitario)
        FROM @Detalle;

        IF @Subtotal IS NULL OR @Subtotal <= 0
            RAISERROR('El total de la venta debe ser mayor a cero.', 16, 1);

        SET @Descuento = CAST(@Subtotal * @PorcentajeDescuento / 100.0 AS DECIMAL(12,2));
        SET @Total     = @Subtotal - @Descuento;

        IF @Total <= 0
            RAISERROR('El total de la venta despues del descuento debe ser mayor a cero.', 16, 1);

        /* Neto e IVA por renglon: cada repuesto puede tener su alicuota.
           El descuento se prorratea para que neto + IVA de exactamente
           el total. */
        DECLARE @Neto DECIMAL(12,2), @Iva DECIMAL(12,2);
        DECLARE @factorDesc DECIMAL(18,10) = CASE WHEN @Subtotal > 0
                                                  THEN @Total / @Subtotal ELSE 1 END;

        SELECT @Neto = SUM(
            CAST(d.Cantidad * d.PrecioUnitario * @factorDesc
                 / (1 + ISNULL(a.Porcentaje, 21) / 100.0) AS DECIMAL(12,2)))
        FROM @Detalle d
        INNER JOIN Repuesto r ON r.Id = d.IdRepuesto
        LEFT JOIN AlicuotaIva a ON a.Id = r.IdAlicuotaIva;

        SET @Neto = ISNULL(@Neto, 0);
        SET @Iva  = @Total - @Neto;

        /* ---------- Pagos ----------
           Dos caminos:
             a) Lista de pagos (clientes nuevos): uno o varios medios.
                Lo pagado es la suma; si no llega al total, el resto
                va a cuenta corriente.
             b) Sin lista (clientes viejos): @FormaPago y @Entrega se
                convierten en un unico pago en efectivo. */

        DECLARE @PagosNorm TABLE (IdMedioPago INT, Monto DECIMAL(12,2), Orden INT IDENTITY(1,1));
        DECLARE @Pagado DECIMAL(12,2) = 0;

        IF EXISTS (SELECT 1 FROM @Pagos)
        BEGIN
            IF EXISTS (SELECT 1 FROM @Pagos WHERE Monto <= 0)
                RAISERROR('Cada pago debe tener un importe mayor a cero.', 16, 1);

            IF EXISTS (SELECT 1 FROM @Pagos p LEFT JOIN MedioPago m ON m.Id = p.IdMedioPago AND m.Activo = 1
                       WHERE m.Id IS NULL)
                RAISERROR('Uno de los medios de pago no existe o esta inactivo.', 16, 1);

            INSERT INTO @PagosNorm (IdMedioPago, Monto)
            SELECT IdMedioPago, Monto FROM @Pagos;

            SELECT @Pagado = SUM(Monto) FROM @PagosNorm;

            -- Lo que no se pago va a cuenta corriente
            SET @FormaPago = CASE WHEN @Pagado < @Total THEN 'CuentaCorriente' ELSE 'Contado' END;
            SET @Entrega = @Pagado;
        END
        ELSE
        BEGIN
            -- Camino viejo
            IF @Entrega IS NULL
                SET @Entrega = CASE WHEN @FormaPago = 'Contado' THEN @Total ELSE 0 END;

            IF @FormaPago = 'Contado' AND @Entrega <> @Total
                RAISERROR('En una venta de contado la entrega debe ser igual al total.', 16, 1);

            IF @Entrega > 0
                INSERT INTO @PagosNorm (IdMedioPago, Monto)
                SELECT Id, @Entrega FROM MedioPago WHERE Codigo = 'EFE';

            SET @Pagado = @Entrega;
        END

        IF @Pagado < 0
            RAISERROR('Lo pagado no puede ser negativo.', 16, 1);

        -- Tolerancia de un centavo por redondeos de pago mixto
        IF @Pagado > @Total + 0.01
            RAISERROR('Lo pagado supera el total de la venta.', 16, 1);

        /* ---------- Sena de un encargo ----------
           El medio SEN no mueve dinero: la sena entro a la caja o a
           Mercado Pago cuando se tomo el encargo. Aca solo se aplica, y
           tiene que coincidir con lo que el cliente dejo. */
        DECLARE @SenaAplicada DECIMAL(12,2) = ISNULL((SELECT SUM(pn.Monto) FROM @PagosNorm pn
                                                       INNER JOIN MedioPago m ON m.Id = pn.IdMedioPago
                                                       WHERE m.Codigo = 'SEN'), 0);
        IF @IdEncargo IS NULL AND @SenaAplicada > 0
            RAISERROR('La seña solo se aplica al entregar un encargo.', 16, 1);

        IF @IdEncargo IS NOT NULL
        BEGIN
            DECLARE @EstadoEncargo VARCHAR(12), @SenaEncargo DECIMAL(12,2);
            SELECT @EstadoEncargo = Estado FROM Encargo WITH (UPDLOCK, HOLDLOCK) WHERE Id = @IdEncargo;
            IF @EstadoEncargo IS NULL
                RAISERROR('El encargo no existe.', 16, 1);
            IF @EstadoEncargo IN ('ENTREGADO', 'CANCELADO')
                RAISERROR('Ese encargo ya fue entregado o cancelado.', 16, 1);
            SET @SenaEncargo = ISNULL((SELECT SUM(Monto) FROM EncargoSena WHERE IdEncargo = @IdEncargo), 0);
            IF ABS(@SenaAplicada - @SenaEncargo) > 0.01
                RAISERROR('La seña aplicada no coincide con la que dejó el cliente.', 16, 1);
        END

        IF @FormaPago = 'CuentaCorriente'
        BEGIN
            -- Fiar a un cliente generico partiria la deuda de todos los
            -- mecanicos en una sola ficha: no se sabria quien debe que.
            IF NOT EXISTS (SELECT 1 FROM Cliente
                           WHERE Id = @IdCliente AND CuentaCorriente = 1 AND Activo = 1)
                RAISERROR('Ese cliente no tiene cuenta corriente habilitada. Para vender a credito hay que registrarlo.', 16, 1);
        END

        /* ---------- Cabecera ---------- */

        INSERT INTO Venta
            (Fecha, IdCliente, IdUsuario, IdEstadoVenta, Total,
             Neto, Iva, PorcentajeDescuento, Descuento,
             NombreOcasional, TelefonoOcasional, TipoCliente)
        VALUES
            (GETDATE(), @IdCliente, @IdUsuario, 1, @Total,
             @Neto, @Iva, @PorcentajeDescuento, @Descuento,
             NULLIF(LTRIM(RTRIM(@NombreOcasional)), ''),
             NULLIF(LTRIM(RTRIM(@TelefonoOcasional)), ''),
             @TipoCliente);

        DECLARE @IdVenta INT = SCOPE_IDENTITY();

        /* ---------- Detalle, con el costo del momento ---------- */

        INSERT INTO DetalleVenta
            (IdVenta, IdRepuesto, Cantidad, PrecioUnitario, Subtotal, CostoUnitario)
        SELECT
            @IdVenta, d.IdRepuesto, d.Cantidad, d.PrecioUnitario,
            (d.Cantidad * d.PrecioUnitario),
            r.PrecioCompra
        FROM @Detalle d
        INNER JOIN Repuesto r ON r.Id = d.IdRepuesto;

        /* ---------- Stock ---------- */

        UPDATE s
        SET s.Cantidad            = s.Cantidad - d.Cantidad,
            s.UltimaActualizacion = GETDATE()
        FROM Stock s
        INNER JOIN @Detalle d ON d.IdRepuesto = s.IdRepuesto;

        IF EXISTS (SELECT 1 FROM Stock s INNER JOIN @Detalle d ON d.IdRepuesto = s.IdRepuesto
                   WHERE s.Cantidad < 0)
            RAISERROR('La operacion habria dejado stock negativo. No se registro la venta.', 16, 1);

        /* ---------- Registro de cada pago ----------
           Efectivo -> MovimientoCaja (arqueo).
           Lo demas -> MovimientoCuentaFinanciera, con la comision como
           egreso separado. Queda visible cuanto se llevan las tarjetas. */

        DECLARE @ComisionTotal DECIMAL(12,2) = 0;
        DECLARE @i INT = 1, @n INT = (SELECT COUNT(*) FROM @PagosNorm);
        DECLARE @pMedio INT, @pMonto DECIMAL(12,2), @pComPorc DECIMAL(5,2), @pCom DECIMAL(12,2),
                @pCuenta INT, @pEsCaja BIT, @pNombre NVARCHAR(40), @pIdPago INT;

        WHILE @i <= @n
        BEGIN
            SELECT @pMedio = pn.IdMedioPago, @pMonto = pn.Monto,
                   @pComPorc = m.ComisionPorc, @pCuenta = m.IdCuentaFinanciera,
                   @pEsCaja = c.EsCaja, @pNombre = m.Nombre
            FROM @PagosNorm pn
            INNER JOIN MedioPago m ON m.Id = pn.IdMedioPago
            INNER JOIN CuentaFinanciera c ON c.Id = m.IdCuentaFinanciera
            WHERE pn.Orden = @i;

            SET @pCom = CAST(@pMonto * @pComPorc / 100.0 AS DECIMAL(12,2));
            SET @ComisionTotal = @ComisionTotal + @pCom;

            INSERT INTO VentaPago (IdVenta, IdMedioPago, Monto, ComisionPorc, Comision, Neto)
            VALUES (@IdVenta, @pMedio, @pMonto, @pComPorc, @pCom, @pMonto - @pCom);
            SET @pIdPago = SCOPE_IDENTITY();

            IF @pEsCaja = 1
            BEGIN
                DECLARE @DescCaja NVARCHAR(250) =
                    CASE WHEN @FormaPago = 'CuentaCorriente'
                         THEN 'Entrega sobre venta #' + CAST(@IdVenta AS NVARCHAR(10))
                         ELSE 'Ingreso automatico por venta #' + CAST(@IdVenta AS NVARCHAR(10)) END;

                EXEC SP_MovimientoCaja_RegistrarInterno
                    @Tipo = 'Ingreso', @Concepto = 'Venta mostrador', @Monto = @pMonto,
                    @Descripcion = @DescCaja, @IdUsuario = @IdUsuario,
                    @IdVenta = @IdVenta, @IdPedido = NULL;
            END
            ELSE
            BEGIN
                INSERT INTO MovimientoCuentaFinanciera
                    (IdCuentaFinanciera, Tipo, Concepto, Monto, Descripcion, IdUsuario, IdVenta, IdVentaPago)
                VALUES
                    (@pCuenta, 'Ingreso', 'Venta ' + @pNombre, @pMonto,
                     'Venta #' + CAST(@IdVenta AS NVARCHAR(10)), @IdUsuario, @IdVenta, @pIdPago);

                IF @pCom > 0
                    INSERT INTO MovimientoCuentaFinanciera
                        (IdCuentaFinanciera, Tipo, Concepto, Monto, Descripcion, IdUsuario, IdVenta, IdVentaPago)
                    VALUES
                        (@pCuenta, 'Egreso', 'Comision ' + @pNombre, @pCom,
                         CAST(@pComPorc AS NVARCHAR(10)) + '% sobre venta #' + CAST(@IdVenta AS NVARCHAR(10)),
                         @IdUsuario, @IdVenta, @pIdPago);
            END

            SET @i = @i + 1;
        END

        /* ---------- Cuenta corriente ----------
           La venta genera el DEBE por el total. Si hubo entrega, se
           registra ademas el HABER. El saldo sube por la diferencia. */

        IF @FormaPago = 'CuentaCorriente'
        BEGIN
            INSERT INTO MovimientoCuentaCorriente
                (IdCliente, Tipo, Concepto, Monto, IdVenta, IdUsuario)
            VALUES
                (@IdCliente, 'Venta',
                 'Venta #' + CAST(@IdVenta AS VARCHAR(10)),
                 @Total, @IdVenta, @IdUsuario);

            IF @Entrega > 0
                INSERT INTO MovimientoCuentaCorriente
                    (IdCliente, Tipo, Concepto, Monto, IdVenta, IdUsuario)
                VALUES
                    (@IdCliente, 'Pago',
                     'Entrega sobre venta #' + CAST(@IdVenta AS VARCHAR(10)),
                     -@Entrega, @IdVenta, @IdUsuario);
        END

        /* ---------- Encargo entregado ---------- */
        IF @IdEncargo IS NOT NULL
            UPDATE Encargo SET Estado = 'ENTREGADO', IdVenta = @IdVenta, FechaEntrega = GETDATE()
            WHERE Id = @IdEncargo;

        COMMIT TRANSACTION;

        SELECT @IdVenta AS IdVenta, @Total AS Total, @Descuento AS Descuento,
               @Pagado AS Entrega, @Pagado AS Pagado,
               (@Total - @Pagado) AS SaldoGenerado, @ComisionTotal AS Comision;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   13. Si se anula la venta que entrego un encargo, el encargo vuelve
       a estar abierto. La anulacion ya revierte el movimiento de SEN,
       asi que la seña vuelve a figurar como deuda con el cliente.
   ----------------------------------------------------------------- */
IF OBJECT_ID('TR_Venta_ReabrirEncargo', 'TR') IS NOT NULL DROP TRIGGER TR_Venta_ReabrirEncargo;
GO
CREATE TRIGGER TR_Venta_ReabrirEncargo ON Venta
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(IdEstadoVenta) RETURN;

    UPDATE e SET Estado = CASE WHEN e.FechaAviso IS NULL THEN 'PENDIENTE' ELSE 'AVISADO' END,
                 IdVenta = NULL, FechaEntrega = NULL
    FROM Encargo e
    INNER JOIN inserted i ON i.Id = e.IdVenta
    INNER JOIN deleted d  ON d.Id = i.Id
    WHERE i.IdEstadoVenta = 2 AND d.IdEstadoVenta <> 2;
END
GO


/* -----------------------------------------------------------------
   PRUEBA rapida (no deja nada: todo se deshace)
   ----------------------------------------------------------------- */
BEGIN TRANSACTION;
    DECLARE @l EncargoLineaType;
    INSERT INTO @l SELECT TOP 1 Id, 1, 1000 FROM Repuesto WHERE Activo = 1 ORDER BY Id;
    EXEC SP_Encargo_I @Nombre = N'Prueba', @Telefono = N'3515555555', @Lineas = @l,
                      @IdUsuario = 1;   -- tiene que devolver el IdEncargo
    EXEC SP_Encargo_GetAll;
ROLLBACK TRANSACTION;
GO
