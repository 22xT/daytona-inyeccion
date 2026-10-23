USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   49 — DEVOLUCIONES Y NOTAS DE CREDITO Y DEBITO A CLIENTES

   ANULAR vs NOTA DE CREDITO
   La anulacion corrige un error de carga: solo la venta del dia y con
   la caja de esa venta todavia abierta. Despues, una devolucion es un
   hecho nuevo con su fecha: nota de credito. La venta original queda
   intacta.

   NOTA DE CREDITO
   - Con devolucion: se eligen repuestos y cantidades de una venta. El
     importe es lo cobrado (precio con el descuento de esa venta). Lo
     que vuelve en buen estado reingresa al stock; lo fallado no.
   - Sin devolucion: bonificacion o error de precio. Importe y motivo.
   - Que pasa con la plata:
       CUENTA     cliente con cuenta corriente: queda a su favor
       REINTEGRO  se le devuelve el dinero desde una cuenta
     Un consumidor final no tiene cuenta donde guardar un saldo: para
     el, siempre reintegro.

   NOTA DE DEBITO
   Suma deuda a un cliente con cuenta corriente: interes, flete,
   diferencia de precio. No mueve dinero.

   Requiere los scripts 38 a 43.
   ================================================================= */


/* -----------------------------------------------------------------
   1. Notas
   ----------------------------------------------------------------- */
IF OBJECT_ID('NotaCliente', 'U') IS NULL
BEGIN
    CREATE TABLE NotaCliente (
        Id               INT IDENTITY(1,1) PRIMARY KEY,
        Tipo             CHAR(2)       NOT NULL,      -- NC | ND
        IdCliente        INT           NOT NULL,
        IdVenta          INT           NULL,          -- de que venta sale la devolucion
        Fecha            DATETIME      NOT NULL DEFAULT GETDATE(),
        Motivo           NVARCHAR(250) NOT NULL,
        Importe          DECIMAL(12,2) NOT NULL,
        Resolucion       VARCHAR(10)   NULL,          -- NC: CUENTA | REINTEGRO
        IdCuentaReintegro INT          NULL,
        IdUsuario        INT           NOT NULL,
        CONSTRAINT FK_NotaCli_Cliente FOREIGN KEY (IdCliente) REFERENCES Cliente(Id),
        CONSTRAINT FK_NotaCli_Venta   FOREIGN KEY (IdVenta)   REFERENCES Venta(Id),
        CONSTRAINT FK_NotaCli_Cuenta  FOREIGN KEY (IdCuentaReintegro) REFERENCES CuentaFinanciera(Id),
        CONSTRAINT CK_NotaCli_Tipo    CHECK (Tipo IN ('NC', 'ND')),
        CONSTRAINT CK_NotaCli_Importe CHECK (Importe > 0),
        CONSTRAINT CK_NotaCli_Res     CHECK (
            (Tipo = 'ND' AND Resolucion IS NULL) OR
            (Tipo = 'NC' AND Resolucion = 'CUENTA' AND IdCuentaReintegro IS NULL) OR
            (Tipo = 'NC' AND Resolucion = 'REINTEGRO' AND IdCuentaReintegro IS NOT NULL))
    );
    CREATE INDEX IX_NotaCli_Venta ON NotaCliente(IdVenta);
END
GO

IF OBJECT_ID('NotaClienteDetalle', 'U') IS NULL
BEGIN
    CREATE TABLE NotaClienteDetalle (
        Id             INT IDENTITY(1,1) PRIMARY KEY,
        IdNota         INT           NOT NULL,
        IdRepuesto     INT           NOT NULL,
        Cantidad       INT           NOT NULL,
        PrecioUnitario DECIMAL(12,2) NOT NULL,   -- lo cobrado por unidad, con el descuento de la venta
        Subtotal       DECIMAL(12,2) NOT NULL,
        ReingresaStock BIT           NOT NULL,   -- 0: vino fallado, no vuelve a la venta
        CONSTRAINT FK_NotaCliDet_Nota     FOREIGN KEY (IdNota)     REFERENCES NotaCliente(Id),
        CONSTRAINT FK_NotaCliDet_Repuesto FOREIGN KEY (IdRepuesto) REFERENCES Repuesto(Id),
        CONSTRAINT CK_NotaCliDet_Cant     CHECK (Cantidad > 0)
    );
END
GO

IF TYPE_ID('DevolucionLineaType') IS NULL
    CREATE TYPE DevolucionLineaType AS TABLE (
        IdRepuesto     INT NOT NULL,
        Cantidad       INT NOT NULL,
        ReingresaStock BIT NOT NULL
    );
GO


/* -----------------------------------------------------------------
   2. Cuenta corriente: nota de debito y origen
   ----------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_MovCC_Tipo')
    ALTER TABLE MovimientoCuentaCorriente DROP CONSTRAINT CK_MovCC_Tipo;
GO
ALTER TABLE MovimientoCuentaCorriente ADD CONSTRAINT CK_MovCC_Tipo
    CHECK (Tipo IN ('Venta', 'Pago', 'NotaCredito', 'NotaDebito', 'Ajuste'));
GO
IF COL_LENGTH('MovimientoCuentaCorriente', 'IdNotaCliente') IS NULL
    ALTER TABLE MovimientoCuentaCorriente ADD IdNotaCliente INT NULL CONSTRAINT FK_MovCC_Nota REFERENCES NotaCliente(Id);
GO


/* -----------------------------------------------------------------
   3. El reintegro mueve dinero: origen en las tablas de movimientos
   ----------------------------------------------------------------- */
IF COL_LENGTH('MovimientoCaja', 'IdNotaCliente') IS NULL
    ALTER TABLE MovimientoCaja ADD IdNotaCliente INT NULL CONSTRAINT FK_MovCaja_NotaCli REFERENCES NotaCliente(Id);
GO
IF COL_LENGTH('MovimientoCuentaFinanciera', 'IdNotaCliente') IS NULL
    ALTER TABLE MovimientoCuentaFinanciera ADD IdNotaCliente INT NULL CONSTRAINT FK_MovCF_NotaCli REFERENCES NotaCliente(Id);
GO

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
    @IdNotaCliente        INT = NULL
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
         IdVenta, IdPedido, IdGasto, IdMovimientoEspecial, IdPagoProveedor, IdNotaCliente, IdSesionCaja, Automatico)
    VALUES
        (@Tipo, @Concepto, @Monto, @Descripcion, @NuevoSaldo, @IdUsuario,
         @IdVenta, @IdPedido, @IdGasto, @IdMovimientoEspecial, @IdPagoProveedor, @IdNotaCliente, @IdSesion, 1);
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
    @IdNotaCliente        INT = NULL
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
             @IdPagoProveedor = @IdPagoProveedor, @IdNotaCliente = @IdNotaCliente;
    ELSE
        INSERT INTO MovimientoCuentaFinanciera
            (IdCuentaFinanciera, Tipo, Concepto, Monto, Descripcion, IdUsuario,
             IdGasto, IdMovimientoEspecial, IdPagoProveedor, IdNotaCliente, Automatico)
        VALUES
            (@IdCuentaFinanciera, @Tipo, @Concepto, @Monto, @Descripcion, @IdUsuario,
             @IdGasto, @IdMovimientoEspecial, @IdPagoProveedor, @IdNotaCliente, 1);
END
GO


/* -----------------------------------------------------------------
   4. La venta, lista para devolver
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Venta_ParaDevolucion', 'P') IS NOT NULL DROP PROCEDURE SP_Venta_ParaDevolucion;
GO
CREATE PROCEDURE SP_Venta_ParaDevolucion @IdVenta INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT v.Id, v.Fecha, v.Total, ISNULL(v.PorcentajeDescuento, 0) AS PorcentajeDescuento, v.IdEstadoVenta,
           v.IdCliente, c.Apellido + ', ' + c.Nombre AS Cliente, c.Dni, c.CuentaCorriente,
           CASE WHEN c.Dni IN ('00000000', '00000001') THEN 1 ELSE 0 END AS EsGenerico,
           ISNULL((SELECT SUM(n.Importe) FROM NotaCliente n WHERE n.IdVenta = v.Id AND n.Tipo = 'NC'), 0) AS YaAcreditado
    FROM Venta v INNER JOIN Cliente c ON c.Id = v.IdCliente
    WHERE v.Id = @IdVenta;

    -- Cuanto se puede devolver de cada renglon: lo vendido menos lo ya devuelto
    SELECT dv.IdRepuesto, r.Codigo, r.Descripcion, dv.Cantidad AS Vendido,
           ISNULL(dev.Devuelto, 0) AS Devuelto,
           dv.Cantidad - ISNULL(dev.Devuelto, 0) AS Disponible,
           CAST(dv.PrecioUnitario * (1 - ISNULL(v.PorcentajeDescuento, 0) / 100.0) AS DECIMAL(12,2)) AS PrecioCobrado
    FROM DetalleVenta dv
    INNER JOIN Venta v ON v.Id = dv.IdVenta
    INNER JOIN Repuesto r ON r.Id = dv.IdRepuesto
    LEFT JOIN (SELECT d.IdRepuesto, SUM(d.Cantidad) AS Devuelto
               FROM NotaClienteDetalle d INNER JOIN NotaCliente n ON n.Id = d.IdNota
               WHERE n.IdVenta = @IdVenta GROUP BY d.IdRepuesto) dev ON dev.IdRepuesto = dv.IdRepuesto
    WHERE dv.IdVenta = @IdVenta
    ORDER BY r.Descripcion;

    -- Notas anteriores de esta venta
    SELECT n.Id, n.Tipo, n.Fecha, n.Motivo, n.Importe, n.Resolucion, cf.Nombre AS CuentaReintegro, u.Nombre AS Usuario
    FROM NotaCliente n
    LEFT JOIN CuentaFinanciera cf ON cf.Id = n.IdCuentaReintegro
    LEFT JOIN Usuario u ON u.Id = n.IdUsuario
    WHERE n.IdVenta = @IdVenta
    ORDER BY n.Id;
END
GO


/* -----------------------------------------------------------------
   5. Nota de credito
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_NotaCreditoCliente_I', 'P') IS NOT NULL DROP PROCEDURE SP_NotaCreditoCliente_I;
GO
CREATE PROCEDURE SP_NotaCreditoCliente_I
    @IdVenta          INT = NULL,
    @IdCliente        INT = NULL,               -- si no viene venta
    @Lineas           DevolucionLineaType READONLY,
    @ImporteSinDevolucion DECIMAL(12,2) = NULL, -- bonificacion, error de precio
    @Motivo           NVARCHAR(250),
    @Resolucion       VARCHAR(10),              -- CUENTA | REINTEGRO
    @IdCuentaReintegro INT = NULL,
    @IdUsuario        INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 10
            RAISERROR('El motivo es obligatorio, con al menos 10 caracteres.', 16, 1);
        IF @Resolucion NOT IN ('CUENTA', 'REINTEGRO')
            RAISERROR('Indicá si queda a favor en la cuenta o se reintegra el dinero.', 16, 1);
        IF @Resolucion = 'REINTEGRO' AND @IdCuentaReintegro IS NULL
            RAISERROR('Indicá desde qué cuenta se devuelve el dinero.', 16, 1);

        DECLARE @hayLineas BIT = CASE WHEN EXISTS (SELECT 1 FROM @Lineas) THEN 1 ELSE 0 END;
        IF @hayLineas = 0 AND (@ImporteSinDevolucion IS NULL OR @ImporteSinDevolucion <= 0)
            RAISERROR('Indicá qué se devuelve o el importe a acreditar.', 16, 1);
        IF @hayLineas = 1 AND @IdVenta IS NULL
            RAISERROR('Una devolución de mercadería tiene que salir de una venta.', 16, 1);
        IF EXISTS (SELECT 1 FROM @Lineas WHERE Cantidad <= 0)
            RAISERROR('Las cantidades a devolver tienen que ser mayores a cero.', 16, 1);

        BEGIN TRANSACTION;

        IF @IdVenta IS NOT NULL
        BEGIN
            DECLARE @EstadoVenta INT;
            SELECT @IdCliente = IdCliente, @EstadoVenta = IdEstadoVenta FROM Venta WITH (UPDLOCK) WHERE Id = @IdVenta;
            IF @IdCliente IS NULL   RAISERROR('La venta no existe.', 16, 1);
            IF @EstadoVenta = 2     RAISERROR('La venta está anulada.', 16, 1);
        END

        DECLARE @TieneCuenta BIT, @EsGenerico BIT;
        SELECT @TieneCuenta = CuentaCorriente,
               @EsGenerico = CASE WHEN Dni IN ('00000000', '00000001') THEN 1 ELSE 0 END
        FROM Cliente WHERE Id = @IdCliente;
        IF @TieneCuenta IS NULL RAISERROR('El cliente no existe.', 16, 1);

        -- Un consumidor final no tiene donde guardar un saldo a favor
        IF @Resolucion = 'CUENTA' AND (@TieneCuenta = 0 OR @EsGenerico = 1)
            RAISERROR('Este cliente no tiene cuenta corriente: el dinero se le reintegra en el momento.', 16, 1);

        -- Si la venta fue a cuenta corriente, reintegrar efectivo seria pagarle
        -- algo que todavia puede deber: la nota va a su cuenta
        IF @Resolucion = 'REINTEGRO' AND @IdVenta IS NOT NULL
           AND EXISTS (SELECT 1 FROM MovimientoCuentaCorriente WHERE IdVenta = @IdVenta AND Tipo = 'Venta')
            RAISERROR('Esa venta fue a cuenta corriente: la nota de crédito se acredita en la cuenta del cliente.', 16, 1);

        -- No se devuelve mas de lo que quedo por devolver
        IF @hayLineas = 1
        BEGIN
            DECLARE @excede NVARCHAR(200);
            SELECT TOP 1 @excede = r.Descripcion
            FROM @Lineas l
            INNER JOIN Repuesto r ON r.Id = l.IdRepuesto
            LEFT JOIN (SELECT IdRepuesto, SUM(Cantidad) AS Vendido FROM DetalleVenta WHERE IdVenta = @IdVenta GROUP BY IdRepuesto) dv
                   ON dv.IdRepuesto = l.IdRepuesto
            LEFT JOIN (SELECT d.IdRepuesto, SUM(d.Cantidad) AS Devuelto
                       FROM NotaClienteDetalle d INNER JOIN NotaCliente n ON n.Id = d.IdNota
                       WHERE n.IdVenta = @IdVenta GROUP BY d.IdRepuesto) dev ON dev.IdRepuesto = l.IdRepuesto
            WHERE dv.IdRepuesto IS NULL OR l.Cantidad > dv.Vendido - ISNULL(dev.Devuelto, 0);
            IF @excede IS NOT NULL
            BEGIN
                DECLARE @msg NVARCHAR(300) = 'Se intenta devolver más de lo vendido (o ya devuelto) de: ' + @excede;
                RAISERROR(@msg, 16, 1);
            END
        END

        -- Importe: lo cobrado por cada unidad, con el descuento de la venta
        DECLARE @Desc DECIMAL(6,2) = ISNULL((SELECT PorcentajeDescuento FROM Venta WHERE Id = @IdVenta), 0);
        DECLARE @Importe DECIMAL(12,2);
        IF @hayLineas = 1
            SELECT @Importe = SUM(CAST(x.Precio * l.Cantidad AS DECIMAL(12,2)))
            FROM @Lineas l
            CROSS APPLY (SELECT TOP 1 CAST(dv.PrecioUnitario * (1 - @Desc / 100.0) AS DECIMAL(12,2)) AS Precio
                         FROM DetalleVenta dv WHERE dv.IdVenta = @IdVenta AND dv.IdRepuesto = l.IdRepuesto) x;
        ELSE
            SET @Importe = @ImporteSinDevolucion;

        -- Con venta: no se acredita mas de lo que se cobro
        IF @IdVenta IS NOT NULL AND @Importe + ISNULL((SELECT SUM(Importe) FROM NotaCliente WHERE IdVenta = @IdVenta AND Tipo = 'NC'), 0)
                                  > (SELECT Total FROM Venta WHERE Id = @IdVenta) + 0.01
            RAISERROR('Lo acreditado superaría el total de la venta.', 16, 1);

        INSERT INTO NotaCliente (Tipo, IdCliente, IdVenta, Motivo, Importe, Resolucion, IdCuentaReintegro, IdUsuario)
        VALUES ('NC', @IdCliente, @IdVenta, LTRIM(RTRIM(@Motivo)), @Importe, @Resolucion,
                CASE WHEN @Resolucion = 'REINTEGRO' THEN @IdCuentaReintegro END, @IdUsuario);
        DECLARE @IdNota INT = SCOPE_IDENTITY();

        IF @hayLineas = 1
        BEGIN
            INSERT INTO NotaClienteDetalle (IdNota, IdRepuesto, Cantidad, PrecioUnitario, Subtotal, ReingresaStock)
            SELECT @IdNota, l.IdRepuesto, l.Cantidad, x.Precio, CAST(x.Precio * l.Cantidad AS DECIMAL(12,2)), l.ReingresaStock
            FROM @Lineas l
            CROSS APPLY (SELECT TOP 1 CAST(dv.PrecioUnitario * (1 - @Desc / 100.0) AS DECIMAL(12,2)) AS Precio
                         FROM DetalleVenta dv WHERE dv.IdVenta = @IdVenta AND dv.IdRepuesto = l.IdRepuesto) x;

            -- Lo que vuelve en buen estado, vuelve al stock
            UPDATE s SET s.Cantidad = s.Cantidad + l.Cantidad, s.UltimaActualizacion = GETDATE()
            FROM Stock s INNER JOIN @Lineas l ON l.IdRepuesto = s.IdRepuesto
            WHERE l.ReingresaStock = 1;
        END

        DECLARE @Txt NVARCHAR(250) = LEFT('Nota de crédito #' + CAST(@IdNota AS NVARCHAR(10)) +
                                     ISNULL(' · venta #' + CAST(@IdVenta AS NVARCHAR(10)), '') + ': ' + @Motivo, 250);

        IF @Resolucion = 'CUENTA'
            INSERT INTO MovimientoCuentaCorriente (IdCliente, Tipo, Concepto, Monto, IdVenta, IdUsuario, IdNotaCliente)
            VALUES (@IdCliente, 'NotaCredito', LEFT(@Txt, 120), -@Importe, @IdVenta, @IdUsuario, @IdNota);
        ELSE
            -- El dinero sale de la cuenta elegida (efectivo exige caja abierta)
            EXEC SP_Cuenta_RegistrarMovimiento
                 @IdCuentaFinanciera = @IdCuentaReintegro, @Tipo = 'Egreso', @Concepto = 'Reintegro a cliente',
                 @Monto = @Importe, @Descripcion = @Txt, @IdUsuario = @IdUsuario, @IdNotaCliente = @IdNota;

        COMMIT;
        SELECT @IdNota AS IdNota, @Importe AS Importe;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   6. Nota de debito
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_NotaDebitoCliente_I', 'P') IS NOT NULL DROP PROCEDURE SP_NotaDebitoCliente_I;
GO
CREATE PROCEDURE SP_NotaDebitoCliente_I
    @IdCliente INT,
    @Importe   DECIMAL(12,2),
    @Motivo    NVARCHAR(250),
    @IdUsuario INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF @Importe IS NULL OR @Importe <= 0
            RAISERROR('El importe tiene que ser mayor a cero.', 16, 1);
        IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 10
            RAISERROR('El motivo es obligatorio, con al menos 10 caracteres.', 16, 1);
        IF NOT EXISTS (SELECT 1 FROM Cliente WHERE Id = @IdCliente AND CuentaCorriente = 1
                       AND Dni NOT IN ('00000000', '00000001'))
            RAISERROR('La nota de débito es para clientes con cuenta corriente.', 16, 1);

        BEGIN TRANSACTION;
        INSERT INTO NotaCliente (Tipo, IdCliente, Motivo, Importe, IdUsuario)
        VALUES ('ND', @IdCliente, LTRIM(RTRIM(@Motivo)), @Importe, @IdUsuario);
        DECLARE @IdNota INT = SCOPE_IDENTITY();

        INSERT INTO MovimientoCuentaCorriente (IdCliente, Tipo, Concepto, Monto, IdUsuario, IdNotaCliente)
        VALUES (@IdCliente, 'NotaDebito', LEFT('Nota de débito #' + CAST(@IdNota AS NVARCHAR(10)) + ': ' + @Motivo, 120),
                @Importe, @IdUsuario, @IdNota);
        COMMIT;
        SELECT @IdNota AS IdNota;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   7. Anular solo lo del dia, con la caja todavia abierta
   Se llama antes de SP_Venta_Anular. Si la venta ya cerro su dia,
   la devolucion se hace con nota de credito.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Venta_ValidarAnulacion', 'P') IS NOT NULL DROP PROCEDURE SP_Venta_ValidarAnulacion;
GO
CREATE PROCEDURE SP_Venta_ValidarAnulacion @IdVenta INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @Fecha DATETIME = (SELECT Fecha FROM Venta WHERE Id = @IdVenta);
        IF @Fecha IS NULL
            RAISERROR('La venta no existe.', 16, 1);
        IF CAST(@Fecha AS DATE) < CAST(GETDATE() AS DATE)
            RAISERROR('Solo se anulan las ventas del día. Para una devolución, hacé una nota de crédito.', 16, 1);
        IF EXISTS (SELECT 1 FROM MovimientoCaja m INNER JOIN SesionCaja s ON s.Id = m.IdSesionCaja
                   WHERE m.IdVenta = @IdVenta AND s.Estado = 'CERRADA')
            RAISERROR('La caja de esa venta ya se cerró. Para una devolución, hacé una nota de crédito.', 16, 1);
        IF EXISTS (SELECT 1 FROM NotaCliente WHERE IdVenta = @IdVenta)
            RAISERROR('La venta ya tiene una nota de crédito: no se puede anular.', 16, 1);
    END TRY
    BEGIN CATCH THROW; END CATCH
END
GO


/* -----------------------------------------------------------------
   8. Listado de notas
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_NotaCliente_GetAll', 'P') IS NOT NULL DROP PROCEDURE SP_NotaCliente_GetAll;
GO
CREATE PROCEDURE SP_NotaCliente_GetAll @Desde DATE = NULL, @Hasta DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @Desde IS NULL SET @Desde = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1);
    IF @Hasta IS NULL SET @Hasta = CAST(GETDATE() AS DATE);
    SELECT n.Id, n.Tipo, n.Fecha, c.Apellido + ', ' + c.Nombre AS Cliente, n.IdVenta, n.Motivo, n.Importe,
           n.Resolucion, cf.Nombre AS CuentaReintegro, u.Nombre AS Usuario,
           (SELECT SUM(d.Cantidad) FROM NotaClienteDetalle d WHERE d.IdNota = n.Id) AS Unidades
    FROM NotaCliente n
    INNER JOIN Cliente c ON c.Id = n.IdCliente
    LEFT JOIN CuentaFinanciera cf ON cf.Id = n.IdCuentaReintegro
    LEFT JOIN Usuario u ON u.Id = n.IdUsuario
    WHERE CAST(n.Fecha AS DATE) BETWEEN @Desde AND @Hasta
    ORDER BY n.Id DESC;
END
GO
