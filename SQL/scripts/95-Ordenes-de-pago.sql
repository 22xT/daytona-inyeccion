/* =================================================================
   95 - PAGOS A PROVEEDORES (Administracion, fase 4)

   ORDEN DE PAGO
   Un pago deja de ser "un importe a cuenta": es un documento que dice
   QUE facturas cancela, que notas de credito aplica y con que medios
   se paga (puede ser mas de uno: parte transferencia, parte efectivo).
     total de facturas = notas de credito aplicadas + lo pagado
   Cada medio genera un PagoProveedor (el del script 43), asi el dinero
   sale de su cuenta y la deuda baja igual que antes. Anular la orden
   anula todos sus pagos.

   LO IMPAGO DE CADA FACTURA
   Antes los pagos cancelaban siempre las facturas mas viejas. Ahora:
     1. lo imputado por ordenes de pago va a la factura elegida;
     2. lo demas (pagos sueltos de antes, notas de credito no
        aplicadas, ajustes) sigue cancelando las mas viejas.
   El total impago sigue siendo exactamente el saldo de la cuenta.

   DATOS FISCALES DE LA FACTURA DE COMPRA
   Tipo (A, B, C), punto de venta, numero, CAE, neto e IVA por
   alicuota, percepciones y total. Son la base del Libro IVA compras
   (fase 5) y de la constatacion del CAE en ARCA.

   Requiere los scripts 43, 47, 55 y 92. Hora argentina como el 90.
   Se puede correr mas de una vez. Correr en local y en Azure.
   ================================================================= */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO


/* -----------------------------------------------------------------
   1. Orden de pago
   ----------------------------------------------------------------- */
IF OBJECT_ID('OrdenPago', 'U') IS NULL
BEGIN
    CREATE TABLE OrdenPago (
        Id                 INT IDENTITY(1,1) PRIMARY KEY,
        IdProveedor        INT           NOT NULL,
        Fecha              DATETIME      NOT NULL,
        TotalImputado      DECIMAL(12,2) NOT NULL,   -- facturas que cancela
        TotalNotasCredito  DECIMAL(12,2) NOT NULL,   -- notas de credito que aplica
        TotalPagado        DECIMAL(12,2) NOT NULL,   -- lo que sale de las cuentas
        Observacion        NVARCHAR(250) NULL,
        Estado             VARCHAR(8)    NOT NULL DEFAULT 'VIGENTE',
        IdUsuario          INT           NOT NULL,
        FechaAnulacion     DATETIME      NULL,
        IdUsuarioAnulacion INT           NULL,
        MotivoAnulacion    NVARCHAR(250) NULL,
        CONSTRAINT FK_OP_Proveedor FOREIGN KEY (IdProveedor) REFERENCES Proveedor(Id),
        CONSTRAINT CK_OP_Estado    CHECK (Estado IN ('VIGENTE', 'ANULADA')),
        CONSTRAINT CK_OP_Importes  CHECK (TotalImputado > 0 AND TotalNotasCredito >= 0 AND TotalPagado >= 0
                                          AND TotalImputado = TotalNotasCredito + TotalPagado)
    );
    CREATE INDEX IX_OP_Proveedor ON OrdenPago(IdProveedor, Fecha);
END
GO

IF OBJECT_ID('OrdenPagoImputacion', 'U') IS NULL
BEGIN
    CREATE TABLE OrdenPagoImputacion (
        IdOrdenPago  INT           NOT NULL,
        IdMovimiento INT           NOT NULL,     -- la factura (o ND, o saldo inicial) en la cuenta del proveedor
        Importe      DECIMAL(12,2) NOT NULL,
        CONSTRAINT PK_OPImp PRIMARY KEY (IdOrdenPago, IdMovimiento),
        CONSTRAINT FK_OPImp_OP  FOREIGN KEY (IdOrdenPago)  REFERENCES OrdenPago(Id),
        CONSTRAINT FK_OPImp_Mov FOREIGN KEY (IdMovimiento) REFERENCES MovimientoCtaCteProveedor(Id),
        CONSTRAINT CK_OPImp_Imp CHECK (Importe > 0)
    );
    CREATE INDEX IX_OPImp_Mov ON OrdenPagoImputacion(IdMovimiento);
END
GO

IF OBJECT_ID('OrdenPagoNotaCredito', 'U') IS NULL
BEGIN
    CREATE TABLE OrdenPagoNotaCredito (
        IdOrdenPago   INT           NOT NULL,
        IdNotaCredito INT           NOT NULL,
        Importe       DECIMAL(12,2) NOT NULL,
        CONSTRAINT PK_OPNC PRIMARY KEY (IdOrdenPago, IdNotaCredito),
        CONSTRAINT FK_OPNC_OP FOREIGN KEY (IdOrdenPago)   REFERENCES OrdenPago(Id),
        CONSTRAINT FK_OPNC_NC FOREIGN KEY (IdNotaCredito) REFERENCES NotaCreditoProveedor(Id),
        CONSTRAINT CK_OPNC_Imp CHECK (Importe > 0)
    );
END
GO

IF COL_LENGTH('PagoProveedor', 'IdOrdenPago') IS NULL
    ALTER TABLE PagoProveedor ADD IdOrdenPago INT NULL CONSTRAINT FK_PagoProv_OP REFERENCES OrdenPago(Id);
GO

IF TYPE_ID('OPImputacionType') IS NULL
    CREATE TYPE OPImputacionType AS TABLE (IdMovimiento INT NOT NULL PRIMARY KEY, Importe DECIMAL(12,2) NOT NULL);
GO
IF TYPE_ID('OPNotaCreditoType') IS NULL
    CREATE TYPE OPNotaCreditoType AS TABLE (IdNotaCredito INT NOT NULL PRIMARY KEY, Importe DECIMAL(12,2) NOT NULL);
GO
IF TYPE_ID('OPMedioType') IS NULL
    CREATE TYPE OPMedioType AS TABLE (IdCuentaFinanciera INT NOT NULL, Importe DECIMAL(12,2) NOT NULL, Referencia NVARCHAR(100) NULL);
GO


/* -----------------------------------------------------------------
   2. Lo impago de cada factura (mismas columnas que antes: la usan
      el resumen de cuentas y la pantalla)
   ----------------------------------------------------------------- */
ALTER PROCEDURE SP_CtaCteProveedor_Facturas @IdProveedor INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @hoy DATE = CAST(DATEADD(HOUR, -3, GETUTCDATE()) AS DATE);

    ;WITH Debitos AS (
        -- Lo que genera deuda: facturas (no anuladas), notas de debito y ajustes positivos
        SELECT m.IdProveedor, m.Id, m.Monto,
               COALESCE(rp.FechaComprobante, CAST(m.Fecha AS DATE)) AS FechaDoc,
               COALESCE(rp.TipoComprobante + ' ' + rp.NumeroComprobante, m.Descripcion) AS Documento,
               rp.IdAdjunto, rp.IdPedido, m.IdRecepcion
        FROM MovimientoCtaCteProveedor m
        LEFT JOIN RecepcionPedido rp ON rp.Id = m.IdRecepcion
        WHERE (@IdProveedor IS NULL OR m.IdProveedor = @IdProveedor)
          AND (   (m.Tipo = 'COMPRA' AND ISNULL(rp.Anulada, 0) = 0)
               OR  m.Tipo = 'ND'
               OR (m.Tipo = 'AJUSTE' AND m.Monto > 0))
    ),
    -- Lo que cada factura ya tiene cancelado por ordenes de pago vigentes
    Imputado AS (
        SELECT i.IdMovimiento, SUM(i.Importe) AS Importe
        FROM OrdenPagoImputacion i INNER JOIN OrdenPago o ON o.Id = i.IdOrdenPago AND o.Estado = 'VIGENTE'
        GROUP BY i.IdMovimiento
    ),
    /* Creditos sin destino = lo cancelado en total (facturado - saldo)
       menos lo que las ordenes de pago ya imputaron. Esos van a las
       facturas mas viejas, como antes. */
    Libres AS (
        SELECT d.IdProveedor,
               SUM(d.Monto)
               - ISNULL((SELECT SUM(m.Monto) FROM MovimientoCtaCteProveedor m WHERE m.IdProveedor = d.IdProveedor), 0)
               - ISNULL((SELECT SUM(i.Importe) FROM OrdenPagoImputacion i
                         INNER JOIN OrdenPago o ON o.Id = i.IdOrdenPago AND o.Estado = 'VIGENTE'
                         WHERE o.IdProveedor = d.IdProveedor), 0) AS Total
        FROM Debitos d
        GROUP BY d.IdProveedor
    ),
    Resto AS (
        SELECT d.*, CASE WHEN d.Monto - ISNULL(im.Importe, 0) > 0 THEN d.Monto - ISNULL(im.Importe, 0) ELSE 0 END AS Resto
        FROM Debitos d LEFT JOIN Imputado im ON im.IdMovimiento = d.Id
    ),
    Acumulado AS (
        SELECT r.*, SUM(r.Resto) OVER (PARTITION BY r.IdProveedor ORDER BY r.FechaDoc, r.Id ROWS UNBOUNDED PRECEDING) AS Acum
        FROM Resto r
    ),
    Calculo AS (
        SELECT a.*,
               CAST(CASE WHEN a.Acum - ISNULL(l.Total, 0) <= 0 THEN 0
                         WHEN a.Acum - ISNULL(l.Total, 0) >= a.Resto THEN a.Resto
                         ELSE a.Acum - ISNULL(l.Total, 0) END AS DECIMAL(12,2)) AS Pendiente
        FROM Acumulado a LEFT JOIN Libres l ON l.IdProveedor = a.IdProveedor
    )
    SELECT c.IdProveedor, p.RazonSocial AS Proveedor, c.Id AS IdMovimiento, c.Documento, c.FechaDoc,
           DATEADD(DAY, p.DiasPago, c.FechaDoc) AS Vencimiento,
           c.Monto AS Importe,
           c.Pendiente,
           DATEDIFF(DAY, @hoy, DATEADD(DAY, p.DiasPago, c.FechaDoc)) AS DiasParaVencer,
           c.IdAdjunto, c.IdPedido, c.IdRecepcion
    FROM Calculo c
    INNER JOIN Proveedor p ON p.Id = c.IdProveedor
    WHERE c.Pendiente > 0
    ORDER BY DATEADD(DAY, p.DiasPago, c.FechaDoc), p.RazonSocial;
END
GO


/* -----------------------------------------------------------------
   3. Notas de credito con saldo para aplicar en una orden de pago
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_NotaCreditoProveedor_Disponibles', 'P') IS NOT NULL DROP PROCEDURE SP_NotaCreditoProveedor_Disponibles;
GO
CREATE PROCEDURE SP_NotaCreditoProveedor_Disponibles @IdProveedor INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT n.Id, n.Numero, n.Fecha, n.Importe,
           n.Importe - ISNULL(a.Aplicado, 0) AS Disponible
    FROM NotaCreditoProveedor n
    OUTER APPLY (SELECT SUM(x.Importe) AS Aplicado
                 FROM OrdenPagoNotaCredito x INNER JOIN OrdenPago o ON o.Id = x.IdOrdenPago AND o.Estado = 'VIGENTE'
                 WHERE x.IdNotaCredito = n.Id) a
    WHERE n.IdProveedor = @IdProveedor AND n.Importe - ISNULL(a.Aplicado, 0) > 0
    ORDER BY n.Fecha, n.Id;
END
GO


/* -----------------------------------------------------------------
   4. Registrar la orden de pago
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_OrdenPago_I', 'P') IS NOT NULL DROP PROCEDURE SP_OrdenPago_I;
GO
CREATE PROCEDURE SP_OrdenPago_I
    @IdProveedor   INT,
    @Imputaciones  OPImputacionType READONLY,
    @NotasCredito  OPNotaCreditoType READONLY,
    @Medios        OPMedioType READONLY,
    @Observacion   NVARCHAR(250) = NULL,
    @IdUsuario     INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM @Imputaciones)
            RAISERROR('Elegí qué facturas se pagan.', 16, 1);
        IF EXISTS (SELECT 1 FROM @Imputaciones WHERE Importe <= 0)
           OR EXISTS (SELECT 1 FROM @NotasCredito WHERE Importe <= 0)
           OR EXISTS (SELECT 1 FROM @Medios WHERE Importe <= 0)
            RAISERROR('Todos los importes tienen que ser mayores a cero.', 16, 1);

        DECLARE @TotImp DECIMAL(12,2) = (SELECT SUM(Importe) FROM @Imputaciones),
                @TotNC  DECIMAL(12,2) = ISNULL((SELECT SUM(Importe) FROM @NotasCredito), 0),
                @TotPag DECIMAL(12,2) = ISNULL((SELECT SUM(Importe) FROM @Medios), 0);
        IF @TotNC + @TotPag <> @TotImp
        BEGIN
            DECLARE @mt NVARCHAR(300) = N'No cierra: las facturas suman ' + FORMAT(@TotImp, 'N2', 'es-AR') +
                N' y las notas de crédito más lo pagado suman ' + FORMAT(@TotNC + @TotPag, 'N2', 'es-AR') + N'.';
            RAISERROR(@mt, 16, 1);
        END
        IF EXISTS (SELECT 1 FROM @Medios m LEFT JOIN CuentaFinanciera c ON c.Id = m.IdCuentaFinanciera
                   WHERE c.Id IS NULL OR c.Activo = 0)
            RAISERROR('Alguna cuenta elegida no existe o está inactiva.', 16, 1);

        BEGIN TRANSACTION;

        -- Una orden por proveedor a la vez: lo impago se calcula y se usa sin que cambie en el medio
        DECLARE @Prov NVARCHAR(150);
        SELECT @Prov = RazonSocial FROM Proveedor WITH (UPDLOCK, HOLDLOCK) WHERE Id = @IdProveedor;
        IF @Prov IS NULL RAISERROR('El proveedor no existe.', 16, 1);

        CREATE TABLE #F (IdProveedor INT, Proveedor NVARCHAR(200), IdMovimiento INT, Documento NVARCHAR(300),
                         FechaDoc DATE, Vencimiento DATE, Importe DECIMAL(12,2), Pendiente DECIMAL(12,2),
                         DiasParaVencer INT, IdAdjunto INT, IdPedido INT, IdRecepcion INT);
        INSERT INTO #F EXEC SP_CtaCteProveedor_Facturas @IdProveedor;

        DECLARE @mal NVARCHAR(300);
        SELECT TOP 1 @mal = ISNULL(f.Documento, N'una factura que ya no tiene saldo')
        FROM @Imputaciones i LEFT JOIN #F f ON f.IdMovimiento = i.IdMovimiento
        WHERE f.IdMovimiento IS NULL OR i.Importe > f.Pendiente;
        IF @mal IS NOT NULL
        BEGIN
            DECLARE @mi NVARCHAR(400) = N'Se intenta pagar más de lo que falta de ' + @mal + N'. Actualizá la pantalla y revisá.';
            RAISERROR(@mi, 16, 1);
        END

        CREATE TABLE #NC (Id INT, Numero VARCHAR(40), Fecha DATE, Importe DECIMAL(12,2), Disponible DECIMAL(12,2));
        INSERT INTO #NC EXEC SP_NotaCreditoProveedor_Disponibles @IdProveedor;
        IF EXISTS (SELECT 1 FROM @NotasCredito x LEFT JOIN #NC n ON n.Id = x.IdNotaCredito
                   WHERE n.Id IS NULL OR x.Importe > n.Disponible)
            RAISERROR('Alguna nota de crédito no es de este proveedor o no tiene tanto saldo para aplicar.', 16, 1);

        DECLARE @Ahora DATETIME = DATEADD(HOUR, -3, GETUTCDATE());
        INSERT INTO OrdenPago (IdProveedor, Fecha, TotalImputado, TotalNotasCredito, TotalPagado, Observacion, IdUsuario)
        VALUES (@IdProveedor, @Ahora, @TotImp, @TotNC, @TotPag, NULLIF(LTRIM(RTRIM(ISNULL(@Observacion, N''))), N''), @IdUsuario);
        DECLARE @IdOP INT = SCOPE_IDENTITY();

        INSERT INTO OrdenPagoImputacion (IdOrdenPago, IdMovimiento, Importe)
        SELECT @IdOP, IdMovimiento, Importe FROM @Imputaciones;
        INSERT INTO OrdenPagoNotaCredito (IdOrdenPago, IdNotaCredito, Importe)
        SELECT @IdOP, IdNotaCredito, Importe FROM @NotasCredito;

        -- Cada medio es un pago: sale de su cuenta (caja exige sesion abierta) y baja la deuda
        DECLARE @M TABLE (n INT IDENTITY(1,1), IdCuenta INT, Importe DECIMAL(12,2), Referencia NVARCHAR(100));
        INSERT INTO @M (IdCuenta, Importe, Referencia)
        SELECT IdCuentaFinanciera, Importe, NULLIF(LTRIM(RTRIM(ISNULL(Referencia, N''))), N'') FROM @Medios;

        DECLARE @i INT = 1, @n INT = (SELECT COUNT(*) FROM @M), @Cta INT, @Imp DECIMAL(12,2), @Ref NVARCHAR(100), @IdPago INT, @Desc NVARCHAR(250);
        WHILE @i <= @n
        BEGIN
            SELECT @Cta = IdCuenta, @Imp = Importe, @Ref = Referencia FROM @M WHERE n = @i;

            INSERT INTO PagoProveedor (IdProveedor, Fecha, Importe, IdCuentaFinanciera, Referencia, IdUsuario, IdOrdenPago)
            VALUES (@IdProveedor, @Ahora, @Imp, @Cta, @Ref, @IdUsuario, @IdOP);
            SET @IdPago = SCOPE_IDENTITY();

            SET @Desc = LEFT(N'Orden de pago #' + CAST(@IdOP AS NVARCHAR(10)) + N' a ' + @Prov + ISNULL(N' · ' + @Ref, N''), 250);
            EXEC SP_Cuenta_RegistrarMovimiento
                 @IdCuentaFinanciera = @Cta, @Tipo = 'Egreso', @Concepto = 'Pago a proveedor',
                 @Monto = @Imp, @Descripcion = @Desc, @IdUsuario = @IdUsuario, @IdPagoProveedor = @IdPago;

            INSERT INTO MovimientoCtaCteProveedor (IdProveedor, Fecha, Tipo, Monto, Descripcion, IdPagoProveedor, IdUsuario)
            VALUES (@IdProveedor, @Ahora, 'PAGO', -@Imp, @Desc, @IdPago, @IdUsuario);

            SET @i += 1;
        END

        COMMIT;
        SELECT @IdOP AS IdOrdenPago,
               (SELECT ISNULL(SUM(Monto), 0) FROM MovimientoCtaCteProveedor WHERE IdProveedor = @IdProveedor) AS SaldoNuevo;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   5. Anular un pago (el del script 43) y anular una orden de pago
      Un pago que es parte de una orden se anula anulando la orden.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_PagoProveedor_Anular', 'P') IS NOT NULL DROP PROCEDURE SP_PagoProveedor_Anular;
GO
CREATE PROCEDURE SP_PagoProveedor_Anular
    @IdPago      INT,
    @Motivo      NVARCHAR(250),
    @IdUsuario   INT,
    @DesdeOrden  BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 10
            RAISERROR('El motivo de la anulacion debe tener al menos 10 caracteres.', 16, 1);

        BEGIN TRANSACTION;

        DECLARE @Prov INT, @Importe DECIMAL(12,2), @Cuenta INT, @Estado VARCHAR(12), @IdOP INT;
        SELECT @Prov = IdProveedor, @Importe = Importe, @Cuenta = IdCuentaFinanciera, @Estado = Estado, @IdOP = IdOrdenPago
        FROM PagoProveedor WITH (UPDLOCK) WHERE Id = @IdPago;

        IF @Prov IS NULL         RAISERROR('El pago no existe.', 16, 1);
        IF @Estado = 'ANULADO'   RAISERROR('El pago ya esta anulado.', 16, 1);
        IF @IdOP IS NOT NULL AND @DesdeOrden = 0
        BEGIN
            DECLARE @mo NVARCHAR(200) = N'Este pago es parte de la orden de pago #' + CAST(@IdOP AS NVARCHAR(10)) + N': se anula la orden entera.';
            RAISERROR(@mo, 16, 1);
        END

        DECLARE @Desc NVARCHAR(250) = LEFT('Anulacion del pago #' + CAST(@IdPago AS NVARCHAR(10)) + ': ' + @Motivo, 250);

        EXEC SP_Cuenta_RegistrarMovimiento
             @IdCuentaFinanciera = @Cuenta, @Tipo = 'Ingreso', @Concepto = 'Anulacion de pago a proveedor',
             @Monto = @Importe, @Descripcion = @Desc, @IdUsuario = @IdUsuario, @IdPagoProveedor = @IdPago;

        INSERT INTO MovimientoCtaCteProveedor (IdProveedor, Fecha, Tipo, Monto, Descripcion, IdPagoProveedor, IdUsuario)
        VALUES (@Prov, DATEADD(HOUR, -3, GETUTCDATE()), 'ANULACION', @Importe, @Desc, @IdPago, @IdUsuario);

        UPDATE PagoProveedor
        SET Estado = 'ANULADO', FechaAnulacion = DATEADD(HOUR, -3, GETUTCDATE()), IdUsuarioAnulacion = @IdUsuario, MotivoAnulacion = @Motivo
        WHERE Id = @IdPago;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

IF OBJECT_ID('SP_OrdenPago_Anular', 'P') IS NOT NULL DROP PROCEDURE SP_OrdenPago_Anular;
GO
CREATE PROCEDURE SP_OrdenPago_Anular
    @IdOrdenPago INT,
    @Motivo      NVARCHAR(250),
    @IdUsuario   INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        SET @Motivo = LTRIM(RTRIM(ISNULL(@Motivo, N'')));
        IF LEN(@Motivo) < 10
            RAISERROR('El motivo de la anulacion debe tener al menos 10 caracteres.', 16, 1);

        BEGIN TRANSACTION;

        DECLARE @Estado VARCHAR(8);
        SELECT @Estado = Estado FROM OrdenPago WITH (UPDLOCK, HOLDLOCK) WHERE Id = @IdOrdenPago;
        IF @Estado IS NULL       RAISERROR('La orden de pago no existe.', 16, 1);
        IF @Estado = 'ANULADA'   RAISERROR('La orden de pago ya está anulada.', 16, 1);

        DECLARE @P TABLE (n INT IDENTITY(1,1), IdPago INT);
        INSERT INTO @P (IdPago) SELECT Id FROM PagoProveedor WHERE IdOrdenPago = @IdOrdenPago AND Estado = 'CONFIRMADO' ORDER BY Id;
        DECLARE @i INT = 1, @n INT = (SELECT COUNT(*) FROM @P), @IdPago INT;
        DECLARE @MotivoPago NVARCHAR(250) = LEFT(N'Orden de pago #' + CAST(@IdOrdenPago AS NVARCHAR(10)) + N' anulada: ' + @Motivo, 250);
        WHILE @i <= @n
        BEGIN
            SELECT @IdPago = IdPago FROM @P WHERE n = @i;
            EXEC SP_PagoProveedor_Anular @IdPago = @IdPago, @Motivo = @MotivoPago, @IdUsuario = @IdUsuario, @DesdeOrden = 1;
            SET @i += 1;
        END

        UPDATE OrdenPago
        SET Estado = 'ANULADA', FechaAnulacion = DATEADD(HOUR, -3, GETUTCDATE()), IdUsuarioAnulacion = @IdUsuario, MotivoAnulacion = @Motivo
        WHERE Id = @IdOrdenPago;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   6. Consultas de ordenes de pago
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_OrdenPago_GetAll', 'P') IS NOT NULL DROP PROCEDURE SP_OrdenPago_GetAll;
GO
CREATE PROCEDURE SP_OrdenPago_GetAll @IdProveedor INT = NULL, @Desde DATE = NULL, @Hasta DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @hoy DATE = CAST(DATEADD(HOUR, -3, GETUTCDATE()) AS DATE);
    SET @Hasta = ISNULL(@Hasta, @hoy);
    SET @Desde = ISNULL(@Desde, DATEADD(MONTH, -6, @Hasta));

    SELECT o.Id, o.Fecha, o.IdProveedor, p.RazonSocial AS Proveedor, o.TotalImputado, o.TotalNotasCredito,
           o.TotalPagado, o.Estado, o.Observacion, u.Nombre AS Usuario,
           (SELECT COUNT(*) FROM OrdenPagoImputacion i WHERE i.IdOrdenPago = o.Id) AS Facturas
    FROM OrdenPago o
    INNER JOIN Proveedor p ON p.Id = o.IdProveedor
    LEFT JOIN Usuario u ON u.Id = o.IdUsuario
    WHERE (@IdProveedor IS NULL OR o.IdProveedor = @IdProveedor)
      AND CAST(o.Fecha AS DATE) BETWEEN @Desde AND @Hasta
    ORDER BY o.Id DESC;
END
GO

IF OBJECT_ID('SP_OrdenPago_GetId', 'P') IS NOT NULL DROP PROCEDURE SP_OrdenPago_GetId;
GO
CREATE PROCEDURE SP_OrdenPago_GetId @Id INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT o.*, p.RazonSocial AS Proveedor, p.Cuit AS CuitProveedor, u.Nombre AS Usuario, ua.Nombre AS UsuarioAnulacion
    FROM OrdenPago o
    INNER JOIN Proveedor p ON p.Id = o.IdProveedor
    LEFT JOIN Usuario u ON u.Id = o.IdUsuario
    LEFT JOIN Usuario ua ON ua.Id = o.IdUsuarioAnulacion
    WHERE o.Id = @Id;

    -- Facturas que cancela
    SELECT i.IdMovimiento, COALESCE(rp.TipoComprobante + ' ' + rp.NumeroComprobante, m.Descripcion) AS Documento,
           COALESCE(rp.FechaComprobante, CAST(m.Fecha AS DATE)) AS FechaDoc, m.Monto AS ImporteFactura, i.Importe
    FROM OrdenPagoImputacion i
    INNER JOIN MovimientoCtaCteProveedor m ON m.Id = i.IdMovimiento
    LEFT JOIN RecepcionPedido rp ON rp.Id = m.IdRecepcion
    WHERE i.IdOrdenPago = @Id
    ORDER BY COALESCE(rp.FechaComprobante, CAST(m.Fecha AS DATE)), i.IdMovimiento;

    -- Notas de credito aplicadas
    SELECT n.Id, n.Numero, n.Fecha, x.Importe
    FROM OrdenPagoNotaCredito x INNER JOIN NotaCreditoProveedor n ON n.Id = x.IdNotaCredito
    WHERE x.IdOrdenPago = @Id ORDER BY n.Fecha;

    -- Medios de pago
    SELECT pp.Id AS IdPago, c.Nombre AS Cuenta, pp.Importe, pp.Referencia, pp.Estado
    FROM PagoProveedor pp INNER JOIN CuentaFinanciera c ON c.Id = pp.IdCuentaFinanciera
    WHERE pp.IdOrdenPago = @Id ORDER BY pp.Id;
END
GO


/* -----------------------------------------------------------------
   7. Datos fiscales de la factura de compra
      Van pegados al movimiento de la cuenta del proveedor (factura,
      nota de debito o nota de credito).
   ----------------------------------------------------------------- */
IF OBJECT_ID('CompraFiscal', 'U') IS NULL
BEGIN
    CREATE TABLE CompraFiscal (
        Id                INT IDENTITY(1,1) PRIMARY KEY,
        IdMovimiento      INT           NOT NULL,
        IdProveedor       INT           NOT NULL,
        TipoArca          INT           NOT NULL,   -- 1/2/3 A · 6/7/8 B · 11/12/13 C
        PuntoVenta        INT           NOT NULL,
        Numero            BIGINT        NOT NULL,
        Fecha             DATE          NOT NULL,
        Cae               VARCHAR(14)   NULL,
        CaeVencimiento    DATE          NULL,
        ImporteNeto       DECIMAL(12,2) NOT NULL,   -- neto gravado (suma de las bases)
        ImporteIva        DECIMAL(12,2) NOT NULL,
        ImporteNoGravado  DECIMAL(12,2) NOT NULL DEFAULT 0,   -- en la C: el importe sin IVA discriminado
        ImporteExento     DECIMAL(12,2) NOT NULL DEFAULT 0,
        PercepcionIva     DECIMAL(12,2) NOT NULL DEFAULT 0,
        PercepcionIibb    DECIMAL(12,2) NOT NULL DEFAULT 0,
        ImpuestosInternos DECIMAL(12,2) NOT NULL DEFAULT 0,
        OtrosTributos     DECIMAL(12,2) NOT NULL DEFAULT 0,
        ImporteTotal      DECIMAL(12,2) NOT NULL,
        Constatado        BIT           NULL,       -- WSCDC de ARCA: NULL sin constatar
        FechaConstatacion DATETIME      NULL,
        ResultadoConstatacion NVARCHAR(300) NULL,
        FechaCarga        DATETIME      NOT NULL,
        IdUsuario         INT           NOT NULL,
        CONSTRAINT FK_CompraFiscal_Mov  FOREIGN KEY (IdMovimiento) REFERENCES MovimientoCtaCteProveedor(Id),
        CONSTRAINT FK_CompraFiscal_Prov FOREIGN KEY (IdProveedor)  REFERENCES Proveedor(Id),
        CONSTRAINT UQ_CompraFiscal_Mov  UNIQUE (IdMovimiento),
        CONSTRAINT UQ_CompraFiscal_Nro  UNIQUE (IdProveedor, TipoArca, PuntoVenta, Numero),
        CONSTRAINT CK_CompraFiscal_Tipo CHECK (TipoArca IN (1, 2, 3, 6, 7, 8, 11, 12, 13)),
        CONSTRAINT CK_CompraFiscal_Nros CHECK (PuntoVenta BETWEEN 1 AND 99999 AND Numero BETWEEN 1 AND 99999999),
        CONSTRAINT CK_CompraFiscal_Total CHECK (ImporteTotal = ImporteNeto + ImporteIva + ImporteNoGravado + ImporteExento
                                                + PercepcionIva + PercepcionIibb + ImpuestosInternos + OtrosTributos)
    );
END
GO

IF OBJECT_ID('CompraFiscalIva', 'U') IS NULL
BEGIN
    CREATE TABLE CompraFiscalIva (
        IdCompraFiscal INT           NOT NULL,
        IdArcaIva      INT           NOT NULL,
        BaseImponible  DECIMAL(12,2) NOT NULL,
        Importe        DECIMAL(12,2) NOT NULL,
        CONSTRAINT PK_CompraFiscalIva PRIMARY KEY (IdCompraFiscal, IdArcaIva),
        CONSTRAINT FK_CompraFiscalIva FOREIGN KEY (IdCompraFiscal) REFERENCES CompraFiscal(Id),
        CONSTRAINT CK_CompraFiscalIva CHECK (IdArcaIva IN (3, 4, 5, 6, 8, 9) AND BaseImponible >= 0 AND Importe >= 0)
    );
END
GO

IF TYPE_ID('CompraIvaType') IS NULL
    CREATE TYPE CompraIvaType AS TABLE (IdArcaIva INT NOT NULL PRIMARY KEY, BaseImponible DECIMAL(12,2) NOT NULL, Importe DECIMAL(12,2) NOT NULL);
GO

-- Lo que hay cargado y lo que se propone desde la recepcion
IF OBJECT_ID('SP_CompraFiscal_Get', 'P') IS NOT NULL DROP PROCEDURE SP_CompraFiscal_Get;
GO
CREATE PROCEDURE SP_CompraFiscal_Get @IdMovimiento INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT m.Id AS IdMovimiento, m.IdProveedor, m.Tipo AS TipoMovimiento, ABS(m.Monto) AS ImporteCuenta,
           p.RazonSocial AS Proveedor, p.Cuit AS CuitProveedor, p.CondicionIva AS CondicionProveedor,
           rp.TipoComprobante, rp.NumeroComprobante, rp.FechaComprobante, rp.IdAdjunto,
           nc.Numero AS NumeroNC, nc.Fecha AS FechaNC, nc.IdAdjunto AS IdAdjuntoNC,
           cf.Id AS IdCompraFiscal, cf.TipoArca, cf.PuntoVenta, cf.Numero, cf.Fecha, cf.Cae, cf.CaeVencimiento,
           cf.ImporteNeto, cf.ImporteIva, cf.ImporteNoGravado, cf.ImporteExento, cf.PercepcionIva, cf.PercepcionIibb,
           cf.ImpuestosInternos, cf.OtrosTributos, cf.ImporteTotal, cf.Constatado, cf.ResultadoConstatacion
    FROM MovimientoCtaCteProveedor m
    INNER JOIN Proveedor p ON p.Id = m.IdProveedor
    LEFT JOIN RecepcionPedido rp ON rp.Id = m.IdRecepcion
    LEFT JOIN NotaCreditoProveedor nc ON nc.Id = m.IdNotaCredito
    LEFT JOIN CompraFiscal cf ON cf.IdMovimiento = m.Id
    WHERE m.Id = @IdMovimiento;

    SELECT i.IdArcaIva, i.BaseImponible, i.Importe
    FROM CompraFiscalIva i INNER JOIN CompraFiscal cf ON cf.Id = i.IdCompraFiscal
    WHERE cf.IdMovimiento = @IdMovimiento ORDER BY i.IdArcaIva;
END
GO

-- Que facturas de un proveedor ya tienen sus datos fiscales
IF OBJECT_ID('SP_CompraFiscal_Estado', 'P') IS NOT NULL DROP PROCEDURE SP_CompraFiscal_Estado;
GO
CREATE PROCEDURE SP_CompraFiscal_Estado @IdProveedor INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT IdMovimiento, TipoArca, PuntoVenta, Numero, Constatado FROM CompraFiscal WHERE IdProveedor = @IdProveedor;
END
GO

IF OBJECT_ID('SP_CompraFiscal_Guardar', 'P') IS NOT NULL DROP PROCEDURE SP_CompraFiscal_Guardar;
GO
CREATE PROCEDURE SP_CompraFiscal_Guardar
    @IdMovimiento      INT,
    @TipoArca          INT,
    @PuntoVenta        INT,
    @Numero            BIGINT,
    @Fecha             DATE,
    @Cae               VARCHAR(14) = NULL,
    @CaeVencimiento    DATE = NULL,
    @ImporteNoGravado  DECIMAL(12,2) = 0,
    @ImporteExento     DECIMAL(12,2) = 0,
    @PercepcionIva     DECIMAL(12,2) = 0,
    @PercepcionIibb    DECIMAL(12,2) = 0,
    @ImpuestosInternos DECIMAL(12,2) = 0,
    @OtrosTributos     DECIMAL(12,2) = 0,
    @ImporteTotal      DECIMAL(12,2),
    @Iva               CompraIvaType READONLY,
    @IdUsuario         INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @IdProv INT, @TipoMov VARCHAR(12), @ImporteCuenta DECIMAL(12,2);
        SELECT @IdProv = IdProveedor, @TipoMov = Tipo, @ImporteCuenta = ABS(Monto)
        FROM MovimientoCtaCteProveedor WHERE Id = @IdMovimiento;
        IF @IdProv IS NULL RAISERROR('El comprobante no existe en la cuenta del proveedor.', 16, 1);
        IF @TipoMov NOT IN ('COMPRA', 'ND', 'NC')
            RAISERROR('Solo las facturas y las notas de crédito o débito llevan datos fiscales.', 16, 1);

        -- La clase del tipo tiene que corresponder al movimiento
        DECLARE @Clase CHAR(2) = CASE WHEN @TipoArca IN (1, 6, 11) THEN 'FC' WHEN @TipoArca IN (2, 7, 12) THEN 'ND'
                                      WHEN @TipoArca IN (3, 8, 13) THEN 'NC' END;
        IF @Clase IS NULL RAISERROR('El tipo de comprobante no es válido.', 16, 1);
        IF (@TipoMov = 'COMPRA' AND @Clase NOT IN ('FC', 'ND')) OR (@TipoMov = 'NC' AND @Clase <> 'NC') OR (@TipoMov = 'ND' AND @Clase <> 'ND')
            RAISERROR('El tipo de comprobante no coincide con lo que es en la cuenta (factura o nota).', 16, 1);

        IF @PuntoVenta IS NULL OR @PuntoVenta NOT BETWEEN 1 AND 99999 RAISERROR('El punto de venta va de 1 a 99999.', 16, 1);
        IF @Numero IS NULL OR @Numero NOT BETWEEN 1 AND 99999999     RAISERROR('El número va de 1 a 99999999.', 16, 1);
        IF @Fecha IS NULL OR @Fecha > CAST(DATEADD(HOUR, -3, GETUTCDATE()) AS DATE)
            RAISERROR('La fecha del comprobante no puede ser futura.', 16, 1);
        SET @Cae = NULLIF(LTRIM(RTRIM(ISNULL(@Cae, ''))), '');
        IF @Cae IS NOT NULL AND (LEN(@Cae) <> 14 OR @Cae LIKE '%[^0-9]%')
            RAISERROR('El CAE tiene 14 números.', 16, 1);

        DECLARE @EsC BIT = CASE WHEN @TipoArca IN (11, 12, 13) THEN 1 ELSE 0 END;
        IF @EsC = 1 AND EXISTS (SELECT 1 FROM @Iva)
            RAISERROR('La factura C no discrimina IVA: el importe va como no gravado.', 16, 1);
        IF @EsC = 0 AND NOT EXISTS (SELECT 1 FROM @Iva) AND @ImporteExento = 0 AND @ImporteNoGravado = 0
            RAISERROR('Cargá el neto y el IVA por alícuota.', 16, 1);
        IF EXISTS (SELECT 1 FROM @Iva WHERE IdArcaIva NOT IN (3, 4, 5, 6, 8, 9) OR BaseImponible < 0 OR Importe < 0)
            RAISERROR('Alguna alícuota de IVA no es válida.', 16, 1);
        -- El IVA de cada alicuota tiene que corresponder a su base (tolerancia de $1 por redondeos por renglón)
        IF EXISTS (SELECT 1 FROM @Iva
                   WHERE ABS(Importe - BaseImponible * CASE IdArcaIva WHEN 3 THEN 0 WHEN 4 THEN 0.105 WHEN 5 THEN 0.21
                                                                      WHEN 6 THEN 0.27 WHEN 8 THEN 0.05 WHEN 9 THEN 0.025 END) > 1)
            RAISERROR('El IVA de alguna alícuota no corresponde a su base: revisá los importes.', 16, 1);
        IF @ImporteNoGravado < 0 OR @ImporteExento < 0 OR @PercepcionIva < 0 OR @PercepcionIibb < 0
           OR @ImpuestosInternos < 0 OR @OtrosTributos < 0
            RAISERROR('Los importes no pueden ser negativos.', 16, 1);

        DECLARE @Neto DECIMAL(12,2) = ISNULL((SELECT SUM(BaseImponible) FROM @Iva), 0),
                @ImpIva DECIMAL(12,2) = ISNULL((SELECT SUM(Importe) FROM @Iva), 0);
        DECLARE @Suma DECIMAL(12,2) = @Neto + @ImpIva + @ImporteNoGravado + @ImporteExento + @PercepcionIva
                                      + @PercepcionIibb + @ImpuestosInternos + @OtrosTributos;
        IF @Suma <> @ImporteTotal
        BEGIN
            DECLARE @ms NVARCHAR(300) = N'Las partes suman ' + FORMAT(@Suma, 'N2', 'es-AR') + N' y el total es ' + FORMAT(@ImporteTotal, 'N2', 'es-AR') + N'.';
            RAISERROR(@ms, 16, 1);
        END
        IF ABS(@ImporteTotal - @ImporteCuenta) > 0.01
        BEGIN
            DECLARE @mc NVARCHAR(300) = N'El total (' + FORMAT(@ImporteTotal, 'N2', 'es-AR') + N') no coincide con lo cargado en la cuenta del proveedor (' +
                                        FORMAT(@ImporteCuenta, 'N2', 'es-AR') + N').';
            RAISERROR(@mc, 16, 1);
        END
        IF EXISTS (SELECT 1 FROM CompraFiscal WHERE IdProveedor = @IdProv AND TipoArca = @TipoArca
                   AND PuntoVenta = @PuntoVenta AND Numero = @Numero AND IdMovimiento <> @IdMovimiento)
            RAISERROR('Ese comprobante ya está cargado en otra factura de este proveedor.', 16, 1);

        BEGIN TRANSACTION;
        DECLARE @Id INT = (SELECT Id FROM CompraFiscal WITH (UPDLOCK, HOLDLOCK) WHERE IdMovimiento = @IdMovimiento);
        IF @Id IS NULL
        BEGIN
            INSERT INTO CompraFiscal (IdMovimiento, IdProveedor, TipoArca, PuntoVenta, Numero, Fecha, Cae, CaeVencimiento,
                                      ImporteNeto, ImporteIva, ImporteNoGravado, ImporteExento, PercepcionIva, PercepcionIibb,
                                      ImpuestosInternos, OtrosTributos, ImporteTotal, FechaCarga, IdUsuario)
            VALUES (@IdMovimiento, @IdProv, @TipoArca, @PuntoVenta, @Numero, @Fecha, @Cae, @CaeVencimiento,
                    @Neto, @ImpIva, @ImporteNoGravado, @ImporteExento, @PercepcionIva, @PercepcionIibb,
                    @ImpuestosInternos, @OtrosTributos, @ImporteTotal, DATEADD(HOUR, -3, GETUTCDATE()), @IdUsuario);
            SET @Id = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            DELETE FROM CompraFiscalIva WHERE IdCompraFiscal = @Id;
            UPDATE CompraFiscal
            SET TipoArca = @TipoArca, PuntoVenta = @PuntoVenta, Numero = @Numero, Fecha = @Fecha, Cae = @Cae,
                CaeVencimiento = @CaeVencimiento, ImporteNeto = @Neto, ImporteIva = @ImpIva,
                ImporteNoGravado = @ImporteNoGravado, ImporteExento = @ImporteExento, PercepcionIva = @PercepcionIva,
                PercepcionIibb = @PercepcionIibb, ImpuestosInternos = @ImpuestosInternos, OtrosTributos = @OtrosTributos,
                ImporteTotal = @ImporteTotal, FechaCarga = DATEADD(HOUR, -3, GETUTCDATE()), IdUsuario = @IdUsuario,
                Constatado = NULL, FechaConstatacion = NULL, ResultadoConstatacion = NULL   -- cambiaron los datos
            WHERE Id = @Id;
        END
        INSERT INTO CompraFiscalIva (IdCompraFiscal, IdArcaIva, BaseImponible, Importe)
        SELECT @Id, IdArcaIva, BaseImponible, Importe FROM @Iva WHERE BaseImponible > 0 OR Importe > 0;
        COMMIT;
        SELECT @Id AS IdCompraFiscal;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   CONTROL
   ----------------------------------------------------------------- */
SELECT name FROM sys.procedures
WHERE name IN ('SP_CtaCteProveedor_Facturas', 'SP_NotaCreditoProveedor_Disponibles', 'SP_OrdenPago_I',
               'SP_PagoProveedor_Anular', 'SP_OrdenPago_Anular', 'SP_OrdenPago_GetAll', 'SP_OrdenPago_GetId',
               'SP_CompraFiscal_Get', 'SP_CompraFiscal_Estado', 'SP_CompraFiscal_Guardar')
ORDER BY name;   -- tienen que ser 10

-- Lo impago de cada proveedor tiene que seguir siendo igual a su saldo
CREATE TABLE #Control (IdProveedor INT, Proveedor NVARCHAR(200), IdMovimiento INT, Documento NVARCHAR(300),
                       FechaDoc DATE, Vencimiento DATE, Importe DECIMAL(12,2), Pendiente DECIMAL(12,2),
                       DiasParaVencer INT, IdAdjunto INT, IdPedido INT, IdRecepcion INT);
INSERT INTO #Control EXEC SP_CtaCteProveedor_Facturas;
SELECT p.RazonSocial, s.Saldo, ISNULL(c.Impago, 0) AS Impago
FROM Proveedor p
CROSS APPLY (SELECT ISNULL(SUM(Monto), 0) AS Saldo FROM MovimientoCtaCteProveedor WHERE IdProveedor = p.Id) s
LEFT JOIN (SELECT IdProveedor, SUM(Pendiente) AS Impago FROM #Control GROUP BY IdProveedor) c ON c.IdProveedor = p.Id
WHERE s.Saldo > 0 AND ABS(s.Saldo - ISNULL(c.Impago, 0)) > 0.01;   -- tiene que salir vacio
DROP TABLE #Control;
GO
