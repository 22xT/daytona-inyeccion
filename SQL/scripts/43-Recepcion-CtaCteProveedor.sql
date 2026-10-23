USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   43 — RECEPCION DE MERCADERIA Y CUENTA CORRIENTE DE PROVEEDORES

   ANTES
   "Recibir" era cambiar el estado del pedido a Recibido. Eso sumaba al
   stock TODO lo pedido y registraba un egreso de caja por el total
   que mandaba el navegador. Tres problemas:
     - Asumia que toda compra se paga en efectivo al recibirla.
     - Con la sesion de caja (script 42), falla si la caja esta cerrada.
     - Si el pedido volvia atras, se revertia el stock pero NO la caja.

   AHORA
   La recepcion es un documento: que llego, con que factura, quien lo
   recibio. Puede haber varias por pedido (recepcion parcial). Genera:
     - stock por lo que llego de verdad, no por lo pedido
     - DEUDA en la cuenta corriente del proveedor, no egreso de caja
   El dinero sale recien con un PAGO A PROVEEDOR, desde la cuenta que
   corresponda.

   El estado del pedido se deriva de sus renglones:
     nada recibido            -> Pendiente
     todo recibido o cerrado  -> Recibido
   Los faltantes siguen esperando hasta que alguien los cierra.

   Requiere los scripts 40 a 42.
   ================================================================= */

-- Si el modelo no es el esperado, NOEXEC frena todos los lotes que siguen
IF COL_LENGTH('Pedido', 'IdProveedor') IS NULL OR COL_LENGTH('DetallePedido', 'PrecioUnitario') IS NULL
BEGIN
    RAISERROR('Pedido o DetallePedido no tienen las columnas esperadas: no se ejecuta nada.', 16, 1);
    SET NOEXEC ON;
END
GO


/* -----------------------------------------------------------------
   1. Renglones del pedido: cuanto llego y cuanto se dio por perdido
   ----------------------------------------------------------------- */
IF COL_LENGTH('DetallePedido', 'CantidadRecibida') IS NULL
    ALTER TABLE DetallePedido ADD CantidadRecibida INT NOT NULL CONSTRAINT DF_DetPed_Recibida DEFAULT 0;
GO
IF COL_LENGTH('DetallePedido', 'CantidadCancelada') IS NULL
    ALTER TABLE DetallePedido ADD CantidadCancelada INT NOT NULL CONSTRAINT DF_DetPed_Cancelada DEFAULT 0;
GO

-- Los pedidos ya recibidos con el sistema viejo recibieron todo
UPDATE dp SET CantidadRecibida = dp.Cantidad
FROM DetallePedido dp INNER JOIN Pedido p ON p.Id = dp.IdPedido
WHERE p.IdEstado = 2 AND dp.CantidadRecibida = 0;
GO

IF COL_LENGTH('Pedido', 'MotivoCierreFaltantes') IS NULL
    ALTER TABLE Pedido ADD MotivoCierreFaltantes NVARCHAR(250) NULL,
                           FechaCierreFaltantes  DATETIME NULL,
                           IdUsuarioCierreFaltantes INT NULL;
GO


/* -----------------------------------------------------------------
   2. Recepcion: el documento de llegada
   ----------------------------------------------------------------- */
IF OBJECT_ID('RecepcionPedido', 'U') IS NULL
BEGIN
    CREATE TABLE RecepcionPedido (
        Id                 INT IDENTITY(1,1) PRIMARY KEY,
        IdPedido           INT           NOT NULL,
        IdProveedor        INT           NOT NULL,
        Fecha              DATETIME      NOT NULL DEFAULT GETDATE(),
        IdUsuario          INT           NOT NULL,
        TipoComprobante    VARCHAR(20)   NOT NULL,     -- Factura A, Factura B, Remito...
        NumeroComprobante  VARCHAR(40)   NOT NULL,
        FechaComprobante   DATE          NOT NULL,
        TotalComprobante   DECIMAL(12,2) NOT NULL,     -- lo que dice la factura: es la deuda
        IdAdjunto          INT           NULL,         -- foto o PDF de la factura
        Observacion        NVARCHAR(250) NULL,
        Anulada            BIT           NOT NULL DEFAULT 0,
        FechaAnulacion     DATETIME      NULL,
        IdUsuarioAnulacion INT           NULL,
        MotivoAnulacion    NVARCHAR(250) NULL,
        CONSTRAINT FK_Recep_Pedido    FOREIGN KEY (IdPedido)    REFERENCES Pedido(Id),
        CONSTRAINT FK_Recep_Proveedor FOREIGN KEY (IdProveedor) REFERENCES Proveedor(Id),
        CONSTRAINT FK_Recep_Adjunto   FOREIGN KEY (IdAdjunto)   REFERENCES Adjunto(Id),
        CONSTRAINT CK_Recep_Total     CHECK (TotalComprobante > 0)
    );
    CREATE INDEX IX_Recep_Pedido ON RecepcionPedido(IdPedido);
END
GO

IF OBJECT_ID('DetalleRecepcion', 'U') IS NULL
BEGIN
    CREATE TABLE DetalleRecepcion (
        Id             INT IDENTITY(1,1) PRIMARY KEY,
        IdRecepcion    INT           NOT NULL,
        IdRepuesto     INT           NOT NULL,
        Cantidad       INT           NOT NULL,
        CostoUnitario  DECIMAL(12,2) NOT NULL,   -- el de la factura
        CONSTRAINT FK_DetRecep_Recep    FOREIGN KEY (IdRecepcion) REFERENCES RecepcionPedido(Id),
        CONSTRAINT FK_DetRecep_Repuesto FOREIGN KEY (IdRepuesto)  REFERENCES Repuesto(Id),
        CONSTRAINT CK_DetRecep_Cant     CHECK (Cantidad > 0),
        CONSTRAINT CK_DetRecep_Costo    CHECK (CostoUnitario >= 0)
    );
END
GO

-- Tipo de tabla para los renglones que llegan
IF TYPE_ID('RecepcionLineaType') IS NULL
    CREATE TYPE RecepcionLineaType AS TABLE (
        IdRepuesto    INT           NOT NULL,
        Cantidad      INT           NOT NULL,
        CostoUnitario DECIMAL(12,2) NOT NULL
    );
GO


/* -----------------------------------------------------------------
   3. Cuenta corriente de proveedores
   Misma forma que la de clientes: positivo aumenta lo que le debemos,
   negativo lo reduce. El saldo es la suma, nunca se guarda.
   ----------------------------------------------------------------- */
IF OBJECT_ID('MovimientoCtaCteProveedor', 'U') IS NULL
BEGIN
    CREATE TABLE MovimientoCtaCteProveedor (
        Id               INT IDENTITY(1,1) PRIMARY KEY,
        IdProveedor      INT           NOT NULL,
        Fecha            DATETIME      NOT NULL DEFAULT GETDATE(),
        Tipo             VARCHAR(12)   NOT NULL,
        Monto            DECIMAL(12,2) NOT NULL,   -- con signo
        Descripcion      NVARCHAR(250) NOT NULL,
        IdRecepcion      INT           NULL,
        IdPagoProveedor  INT           NULL,
        IdUsuario        INT           NOT NULL,
        CONSTRAINT FK_CCP_Proveedor FOREIGN KEY (IdProveedor) REFERENCES Proveedor(Id),
        CONSTRAINT FK_CCP_Recep     FOREIGN KEY (IdRecepcion) REFERENCES RecepcionPedido(Id),
        CONSTRAINT CK_CCP_Tipo      CHECK (Tipo IN ('COMPRA', 'PAGO', 'NC', 'ND', 'AJUSTE', 'ANULACION')),
        CONSTRAINT CK_CCP_Monto     CHECK (Monto <> 0)
    );
    CREATE INDEX IX_CCP_Proveedor ON MovimientoCtaCteProveedor(IdProveedor, Fecha);
END
GO


/* -----------------------------------------------------------------
   4. Pago a proveedor
   ----------------------------------------------------------------- */
IF OBJECT_ID('PagoProveedor', 'U') IS NULL
BEGIN
    CREATE TABLE PagoProveedor (
        Id                 INT IDENTITY(1,1) PRIMARY KEY,
        IdProveedor        INT           NOT NULL,
        Fecha              DATETIME      NOT NULL DEFAULT GETDATE(),
        Importe            DECIMAL(12,2) NOT NULL,
        IdCuentaFinanciera INT           NOT NULL,
        Referencia         NVARCHAR(100) NULL,      -- n° de transferencia, recibo del proveedor
        IdUsuario          INT           NOT NULL,
        Estado             VARCHAR(12)   NOT NULL DEFAULT 'CONFIRMADO',
        FechaAnulacion     DATETIME      NULL,
        IdUsuarioAnulacion INT           NULL,
        MotivoAnulacion    NVARCHAR(250) NULL,
        CONSTRAINT FK_PagoProv_Proveedor FOREIGN KEY (IdProveedor) REFERENCES Proveedor(Id),
        CONSTRAINT FK_PagoProv_Cuenta    FOREIGN KEY (IdCuentaFinanciera) REFERENCES CuentaFinanciera(Id),
        CONSTRAINT CK_PagoProv_Importe   CHECK (Importe > 0),
        CONSTRAINT CK_PagoProv_Estado    CHECK (Estado IN ('CONFIRMADO', 'ANULADO'))
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_CCP_Pago')
    ALTER TABLE MovimientoCtaCteProveedor ADD CONSTRAINT FK_CCP_Pago FOREIGN KEY (IdPagoProveedor) REFERENCES PagoProveedor(Id);
GO

IF COL_LENGTH('MovimientoCaja', 'IdPagoProveedor') IS NULL
    ALTER TABLE MovimientoCaja ADD IdPagoProveedor INT NULL CONSTRAINT FK_MovCaja_PagoProv REFERENCES PagoProveedor(Id);
GO
IF COL_LENGTH('MovimientoCuentaFinanciera', 'IdPagoProveedor') IS NULL
    ALTER TABLE MovimientoCuentaFinanciera ADD IdPagoProveedor INT NULL CONSTRAINT FK_MovCF_PagoProv REFERENCES PagoProveedor(Id);
GO


/* -----------------------------------------------------------------
   5. Los dos registradores de dinero aceptan el pago como origen
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
    @IdPagoProveedor      INT = NULL
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
         IdVenta, IdPedido, IdGasto, IdMovimientoEspecial, IdPagoProveedor, IdSesionCaja, Automatico)
    VALUES
        (@Tipo, @Concepto, @Monto, @Descripcion, @NuevoSaldo, @IdUsuario,
         @IdVenta, @IdPedido, @IdGasto, @IdMovimientoEspecial, @IdPagoProveedor, @IdSesion, 1);
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
    @IdPagoProveedor      INT = NULL
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
             @IdPagoProveedor = @IdPagoProveedor;
    ELSE
        INSERT INTO MovimientoCuentaFinanciera
            (IdCuentaFinanciera, Tipo, Concepto, Monto, Descripcion, IdUsuario,
             IdGasto, IdMovimientoEspecial, IdPagoProveedor, Automatico)
        VALUES
            (@IdCuentaFinanciera, @Tipo, @Concepto, @Monto, @Descripcion, @IdUsuario,
             @IdGasto, @IdMovimientoEspecial, @IdPagoProveedor, 1);
END
GO


/* -----------------------------------------------------------------
   6. Estado del pedido derivado de sus renglones
   No abre transaccion: la llama quien recibe, cierra o anula.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Pedido_RecalcularEstado', 'P') IS NOT NULL DROP PROCEDURE SP_Pedido_RecalcularEstado;
GO
CREATE PROCEDURE SP_Pedido_RecalcularEstado @IdPedido INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pendiente INT, @recibido INT;
    SELECT @pendiente = SUM(Cantidad - CantidadRecibida - CantidadCancelada),
           @recibido  = SUM(CantidadRecibida)
    FROM DetallePedido WHERE IdPedido = @IdPedido;

    UPDATE Pedido
    SET IdEstado = CASE WHEN @pendiente > 0 THEN 1          -- falta algo: sigue pendiente
                        WHEN @recibido > 0  THEN 2          -- todo resuelto y algo llego
                        ELSE 3 END                          -- todo cerrado sin recibir nada
    WHERE Id = @IdPedido;
END
GO


/* -----------------------------------------------------------------
   7. Lo que hace falta para la pantalla de recepcion
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Pedido_ParaRecepcion', 'P') IS NOT NULL DROP PROCEDURE SP_Pedido_ParaRecepcion;
GO
CREATE PROCEDURE SP_Pedido_ParaRecepcion @IdPedido INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Cabecera
    SELECT p.Id, p.Fecha, p.IdEstado, p.IdProveedor, pr.RazonSocial AS Proveedor,
           p.MotivoCierreFaltantes
    FROM Pedido p INNER JOIN Proveedor pr ON pr.Id = p.IdProveedor
    WHERE p.Id = @IdPedido;

    -- Renglones con lo que falta
    SELECT dp.IdRepuesto, r.Codigo, r.Descripcion,
           dp.Cantidad, dp.CantidadRecibida, dp.CantidadCancelada,
           dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada AS Pendiente,
           dp.PrecioUnitario
    FROM DetallePedido dp INNER JOIN Repuesto r ON r.Id = dp.IdRepuesto
    WHERE dp.IdPedido = @IdPedido
    ORDER BY r.Descripcion;

    -- Recepciones anteriores
    SELECT rp.Id, rp.Fecha, rp.TipoComprobante, rp.NumeroComprobante, rp.TotalComprobante,
           rp.IdAdjunto, rp.Anulada, rp.MotivoAnulacion, u.Nombre AS Usuario,
           (SELECT SUM(Cantidad) FROM DetalleRecepcion d WHERE d.IdRecepcion = rp.Id) AS Unidades
    FROM RecepcionPedido rp LEFT JOIN Usuario u ON u.Id = rp.IdUsuario
    WHERE rp.IdPedido = @IdPedido
    ORDER BY rp.Id;
END
GO

-- Para el listado: cuanto de cada pedido ya llego
IF OBJECT_ID('SP_Pedido_ResumenRecepcion', 'P') IS NOT NULL DROP PROCEDURE SP_Pedido_ResumenRecepcion;
GO
CREATE PROCEDURE SP_Pedido_ResumenRecepcion
AS
BEGIN
    SET NOCOUNT ON;
    SELECT IdPedido,
           SUM(Cantidad) AS Pedidas,
           SUM(CantidadRecibida) AS Recibidas,
           SUM(CantidadCancelada) AS Cerradas
    FROM DetallePedido
    GROUP BY IdPedido;
END
GO


/* -----------------------------------------------------------------
   8. Recibir
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Pedido_Recibir', 'P') IS NOT NULL DROP PROCEDURE SP_Pedido_Recibir;
GO
CREATE PROCEDURE SP_Pedido_Recibir
    @IdPedido          INT,
    @Lineas            RecepcionLineaType READONLY,
    @TipoComprobante   VARCHAR(20),
    @NumeroComprobante VARCHAR(40),
    @FechaComprobante  DATE,
    @TotalComprobante  DECIMAL(12,2),
    @IdAdjunto         INT = NULL,
    @Observacion       NVARCHAR(250) = NULL,
    @IdUsuario         INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM @Lineas)
            RAISERROR('No hay renglones para recibir.', 16, 1);
        IF EXISTS (SELECT 1 FROM @Lineas WHERE Cantidad <= 0 OR CostoUnitario < 0)
            RAISERROR('Cada renglon debe tener cantidad mayor a cero y un costo valido.', 16, 1);
        IF ISNULL(LTRIM(RTRIM(@TipoComprobante)), '') = '' OR ISNULL(LTRIM(RTRIM(@NumeroComprobante)), '') = ''
            RAISERROR('Indica el tipo y el numero del comprobante del proveedor.', 16, 1);
        IF @TotalComprobante IS NULL OR @TotalComprobante <= 0
            RAISERROR('Indica el total del comprobante: es lo que se le debe al proveedor.', 16, 1);
        IF @FechaComprobante > CAST(GETDATE() AS DATE)
            RAISERROR('La fecha del comprobante no puede ser futura.', 16, 1);

        BEGIN TRANSACTION;

        DECLARE @IdProveedor INT, @Estado INT;
        SELECT @IdProveedor = IdProveedor, @Estado = IdEstado FROM Pedido WITH (UPDLOCK) WHERE Id = @IdPedido;
        IF @IdProveedor IS NULL RAISERROR('El pedido no existe.', 16, 1);
        IF @Estado = 3         RAISERROR('El pedido esta cancelado.', 16, 1);

        -- Cada renglon tiene que estar en el pedido y no superar lo pendiente
        IF EXISTS (SELECT 1 FROM @Lineas l
                   LEFT JOIN DetallePedido dp ON dp.IdPedido = @IdPedido AND dp.IdRepuesto = l.IdRepuesto
                   WHERE dp.IdRepuesto IS NULL)
            RAISERROR('Hay un repuesto que no esta en el pedido. Lo que llega de mas se registra con un pedido aparte.', 16, 1);

        DECLARE @excede NVARCHAR(200);
        SELECT TOP 1 @excede = r.Descripcion
        FROM @Lineas l
        INNER JOIN DetallePedido dp ON dp.IdPedido = @IdPedido AND dp.IdRepuesto = l.IdRepuesto
        INNER JOIN Repuesto r ON r.Id = l.IdRepuesto
        WHERE l.Cantidad > dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada;
        IF @excede IS NOT NULL
        BEGIN
            DECLARE @msg NVARCHAR(300) = 'Llega mas de lo que falta recibir de: ' + @excede;
            RAISERROR(@msg, 16, 1);
        END

        -- La misma factura no se carga dos veces
        IF EXISTS (SELECT 1 FROM RecepcionPedido
                   WHERE IdProveedor = @IdProveedor AND Anulada = 0
                     AND TipoComprobante = @TipoComprobante AND NumeroComprobante = LTRIM(RTRIM(@NumeroComprobante)))
            RAISERROR('Ese comprobante del proveedor ya esta registrado en otra recepcion.', 16, 1);

        INSERT INTO RecepcionPedido (IdPedido, IdProveedor, IdUsuario, TipoComprobante, NumeroComprobante,
                                     FechaComprobante, TotalComprobante, IdAdjunto, Observacion)
        VALUES (@IdPedido, @IdProveedor, @IdUsuario, @TipoComprobante, LTRIM(RTRIM(@NumeroComprobante)),
                @FechaComprobante, @TotalComprobante, @IdAdjunto, NULLIF(LTRIM(RTRIM(@Observacion)), ''));
        DECLARE @IdRecepcion INT = SCOPE_IDENTITY();

        INSERT INTO DetalleRecepcion (IdRecepcion, IdRepuesto, Cantidad, CostoUnitario)
        SELECT @IdRecepcion, IdRepuesto, Cantidad, CostoUnitario FROM @Lineas;

        -- Stock por lo que llego. Si un repuesto no tiene fila de stock, se crea.
        INSERT INTO Stock (IdRepuesto, Cantidad, UltimaActualizacion)
        SELECT l.IdRepuesto, 0, GETDATE() FROM @Lineas l
        WHERE NOT EXISTS (SELECT 1 FROM Stock s WHERE s.IdRepuesto = l.IdRepuesto);

        UPDATE s SET s.Cantidad = s.Cantidad + l.Cantidad, s.UltimaActualizacion = GETDATE()
        FROM Stock s INNER JOIN @Lineas l ON l.IdRepuesto = s.IdRepuesto;

        UPDATE dp SET dp.CantidadRecibida = dp.CantidadRecibida + l.Cantidad
        FROM DetallePedido dp INNER JOIN @Lineas l ON l.IdRepuesto = dp.IdRepuesto
        WHERE dp.IdPedido = @IdPedido;

        -- Deuda con el proveedor: el total de su comprobante
        DECLARE @Desc NVARCHAR(250) = @TipoComprobante + ' ' + LTRIM(RTRIM(@NumeroComprobante)) +
                                      ' · recepcion #' + CAST(@IdRecepcion AS NVARCHAR(10)) +
                                      ' del pedido #' + CAST(@IdPedido AS NVARCHAR(10));
        INSERT INTO MovimientoCtaCteProveedor (IdProveedor, Tipo, Monto, Descripcion, IdRecepcion, IdUsuario)
        VALUES (@IdProveedor, 'COMPRA', @TotalComprobante, @Desc, @IdRecepcion, @IdUsuario);

        EXEC SP_Pedido_RecalcularEstado @IdPedido = @IdPedido;

        COMMIT;
        SELECT @IdRecepcion AS IdRecepcion,
               (SELECT IdEstado FROM Pedido WHERE Id = @IdPedido) AS IdEstadoPedido;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   9. Anular una recepcion: el inverso de todo lo que hizo
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_RecepcionPedido_Anular', 'P') IS NOT NULL DROP PROCEDURE SP_RecepcionPedido_Anular;
GO
CREATE PROCEDURE SP_RecepcionPedido_Anular
    @IdRecepcion INT,
    @Motivo      NVARCHAR(250),
    @IdUsuario   INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 10
            RAISERROR('El motivo de la anulacion debe tener al menos 10 caracteres.', 16, 1);

        BEGIN TRANSACTION;

        DECLARE @IdPedido INT, @IdProveedor INT, @Total DECIMAL(12,2), @Anulada BIT, @Comp NVARCHAR(80);
        SELECT @IdPedido = IdPedido, @IdProveedor = IdProveedor, @Total = TotalComprobante, @Anulada = Anulada,
               @Comp = TipoComprobante + ' ' + NumeroComprobante
        FROM RecepcionPedido WITH (UPDLOCK) WHERE Id = @IdRecepcion;

        IF @IdPedido IS NULL RAISERROR('La recepcion no existe.', 16, 1);
        IF @Anulada = 1      RAISERROR('La recepcion ya esta anulada.', 16, 1);

        -- Si parte de lo recibido ya se vendio, el stock quedaria negativo
        DECLARE @sinStock NVARCHAR(200);
        SELECT TOP 1 @sinStock = r.Descripcion
        FROM DetalleRecepcion d
        INNER JOIN Stock s WITH (UPDLOCK) ON s.IdRepuesto = d.IdRepuesto
        INNER JOIN Repuesto r ON r.Id = d.IdRepuesto
        WHERE d.IdRecepcion = @IdRecepcion AND s.Cantidad < d.Cantidad;
        IF @sinStock IS NOT NULL
        BEGIN
            DECLARE @msg NVARCHAR(300) = 'No se puede anular: parte de lo recibido ya se vendio (' + @sinStock + '). Corregilo con una nota de credito o un ajuste de stock.';
            RAISERROR(@msg, 16, 1);
        END

        UPDATE s SET s.Cantidad = s.Cantidad - d.Cantidad, s.UltimaActualizacion = GETDATE()
        FROM Stock s INNER JOIN DetalleRecepcion d ON d.IdRepuesto = s.IdRepuesto
        WHERE d.IdRecepcion = @IdRecepcion;

        UPDATE dp SET dp.CantidadRecibida = dp.CantidadRecibida - d.Cantidad
        FROM DetallePedido dp INNER JOIN DetalleRecepcion d ON d.IdRepuesto = dp.IdRepuesto
        WHERE dp.IdPedido = @IdPedido AND d.IdRecepcion = @IdRecepcion;

        DECLARE @Desc NVARCHAR(250) = LEFT('Anulacion de ' + @Comp + ' (recepcion #' + CAST(@IdRecepcion AS NVARCHAR(10)) + '): ' + @Motivo, 250);
        INSERT INTO MovimientoCtaCteProveedor (IdProveedor, Tipo, Monto, Descripcion, IdRecepcion, IdUsuario)
        VALUES (@IdProveedor, 'ANULACION', -@Total, @Desc, @IdRecepcion, @IdUsuario);

        UPDATE RecepcionPedido
        SET Anulada = 1, FechaAnulacion = GETDATE(), IdUsuarioAnulacion = @IdUsuario, MotivoAnulacion = @Motivo
        WHERE Id = @IdRecepcion;

        EXEC SP_Pedido_RecalcularEstado @IdPedido = @IdPedido;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   10. Cerrar faltantes: lo que no va a llegar
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Pedido_CerrarFaltantes', 'P') IS NOT NULL DROP PROCEDURE SP_Pedido_CerrarFaltantes;
GO
CREATE PROCEDURE SP_Pedido_CerrarFaltantes
    @IdPedido  INT,
    @Motivo    NVARCHAR(250),
    @IdUsuario INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 10
            RAISERROR('Explica por que no van a llegar, con al menos 10 caracteres.', 16, 1);

        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM DetallePedido WITH (UPDLOCK)
                       WHERE IdPedido = @IdPedido AND Cantidad - CantidadRecibida - CantidadCancelada > 0)
            RAISERROR('El pedido no tiene faltantes.', 16, 1);

        UPDATE DetallePedido
        SET CantidadCancelada = Cantidad - CantidadRecibida
        WHERE IdPedido = @IdPedido AND Cantidad - CantidadRecibida - CantidadCancelada > 0;

        UPDATE Pedido
        SET MotivoCierreFaltantes = LTRIM(RTRIM(@Motivo)), FechaCierreFaltantes = GETDATE(),
            IdUsuarioCierreFaltantes = @IdUsuario
        WHERE Id = @IdPedido;

        EXEC SP_Pedido_RecalcularEstado @IdPedido = @IdPedido;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   11. SP_Pedido_U: ya no recibe
   Recibir es SP_Pedido_Recibir. Este solo cancela, y solo si no llego
   nada: si llego algo, lo que falta se cierra con CerrarFaltantes.
   El total ya no viene del navegador.
   ----------------------------------------------------------------- */
ALTER PROCEDURE [dbo].[SP_Pedido_U]
    @Id        INT,
    @IdEstado  INT,
    @Total     DECIMAL(10,2) = NULL,     -- se ignora: se conserva por compatibilidad
    @IdUsuario INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @EstadoActual INT;
        SELECT @EstadoActual = IdEstado FROM Pedido WHERE Id = @Id;

        IF @EstadoActual IS NULL
            RAISERROR('El pedido no existe.', 16, 1);
        IF @IdEstado = 2
            RAISERROR('La mercaderia se recibe desde "Recibir", con el comprobante del proveedor.', 16, 1);
        IF @EstadoActual = 2
            RAISERROR('Un pedido recibido no cambia de estado. Para corregirlo, anula la recepcion.', 16, 1);
        IF @IdEstado = 3 AND EXISTS (SELECT 1 FROM DetallePedido WHERE IdPedido = @Id AND CantidadRecibida > 0)
            RAISERROR('Ya llego parte del pedido: usa "Cerrar faltantes" para lo que no va a llegar.', 16, 1);

        BEGIN TRANSACTION;

        IF @IdEstado = 3 AND @EstadoActual <> 3
        BEGIN
            UPDATE DetallePedido SET CantidadCancelada = Cantidad WHERE IdPedido = @Id;
            UPDATE Pedido SET IdUsuarioCancelacion = @IdUsuario, FechaCancelacion = GETDATE() WHERE Id = @Id;
        END

        UPDATE Pedido SET IdEstado = @IdEstado WHERE Id = @Id;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   12. Cuenta corriente de proveedores: consultas y ajuste
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_CtaCteProveedor_Saldos', 'P') IS NOT NULL DROP PROCEDURE SP_CtaCteProveedor_Saldos;
GO
CREATE PROCEDURE SP_CtaCteProveedor_Saldos
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.Id, p.RazonSocial,
           ISNULL(SUM(m.Monto), 0) AS Saldo,
           MAX(m.Fecha) AS UltimoMovimiento,
           (SELECT COUNT(*) FROM Pedido pe WHERE pe.IdProveedor = p.Id AND pe.IdEstado = 1) AS PedidosPendientes
    FROM Proveedor p
    LEFT JOIN MovimientoCtaCteProveedor m ON m.IdProveedor = p.Id
    WHERE p.Activo = 1
    GROUP BY p.Id, p.RazonSocial
    ORDER BY ISNULL(SUM(m.Monto), 0) DESC, p.RazonSocial;
END
GO

IF OBJECT_ID('SP_CtaCteProveedor_Movimientos', 'P') IS NOT NULL DROP PROCEDURE SP_CtaCteProveedor_Movimientos;
GO
CREATE PROCEDURE SP_CtaCteProveedor_Movimientos @IdProveedor INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT m.Id, m.Fecha, m.Tipo, m.Monto, m.Descripcion, m.IdRecepcion, m.IdPagoProveedor,
           SUM(m.Monto) OVER (ORDER BY m.Fecha, m.Id ROWS UNBOUNDED PRECEDING) AS SaldoAcumulado,
           u.Nombre AS Usuario,
           rp.IdAdjunto
    FROM MovimientoCtaCteProveedor m
    LEFT JOIN Usuario u ON u.Id = m.IdUsuario
    LEFT JOIN RecepcionPedido rp ON rp.Id = m.IdRecepcion
    WHERE m.IdProveedor = @IdProveedor
    ORDER BY m.Fecha DESC, m.Id DESC;
END
GO

-- Saldo inicial: lo que ya se le debia antes de usar el sistema
IF OBJECT_ID('SP_CtaCteProveedor_Ajuste', 'P') IS NOT NULL DROP PROCEDURE SP_CtaCteProveedor_Ajuste;
GO
CREATE PROCEDURE SP_CtaCteProveedor_Ajuste
    @IdProveedor INT,
    @Monto       DECIMAL(12,2),     -- positivo: le debemos mas
    @Motivo      NVARCHAR(250),
    @IdUsuario   INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @Monto IS NULL OR @Monto = 0
            RAISERROR('El ajuste no puede ser cero.', 16, 1);
        IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 10
            RAISERROR('El motivo es obligatorio, con al menos 10 caracteres.', 16, 1);
        INSERT INTO MovimientoCtaCteProveedor (IdProveedor, Tipo, Monto, Descripcion, IdUsuario)
        VALUES (@IdProveedor, 'AJUSTE', @Monto, LTRIM(RTRIM(@Motivo)), @IdUsuario);
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   13. Pagar al proveedor y anular el pago
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_PagoProveedor_I', 'P') IS NOT NULL DROP PROCEDURE SP_PagoProveedor_I;
GO
CREATE PROCEDURE SP_PagoProveedor_I
    @IdProveedor        INT,
    @IdCuentaFinanciera INT,
    @Importe            DECIMAL(12,2),
    @Referencia         NVARCHAR(100) = NULL,
    @IdUsuario          INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF @Importe IS NULL OR @Importe <= 0
            RAISERROR('El importe debe ser mayor a cero.', 16, 1);
        IF NOT EXISTS (SELECT 1 FROM Proveedor WHERE Id = @IdProveedor)
            RAISERROR('El proveedor no existe.', 16, 1);

        BEGIN TRANSACTION;

        INSERT INTO PagoProveedor (IdProveedor, Importe, IdCuentaFinanciera, Referencia, IdUsuario)
        VALUES (@IdProveedor, @Importe, @IdCuentaFinanciera, NULLIF(LTRIM(RTRIM(@Referencia)), ''), @IdUsuario);
        DECLARE @IdPago INT = SCOPE_IDENTITY();

        DECLARE @Prov NVARCHAR(150) = (SELECT RazonSocial FROM Proveedor WHERE Id = @IdProveedor);
        DECLARE @Desc NVARCHAR(250) = LEFT('Pago #' + CAST(@IdPago AS NVARCHAR(10)) + ' a ' + @Prov +
                                      ISNULL(' · ' + NULLIF(LTRIM(RTRIM(@Referencia)), ''), ''), 250);

        -- El dinero sale de la cuenta elegida (caja exige sesion abierta)
        EXEC SP_Cuenta_RegistrarMovimiento
             @IdCuentaFinanciera = @IdCuentaFinanciera, @Tipo = 'Egreso', @Concepto = 'Pago a proveedor',
             @Monto = @Importe, @Descripcion = @Desc, @IdUsuario = @IdUsuario, @IdPagoProveedor = @IdPago;

        -- Y la deuda baja
        INSERT INTO MovimientoCtaCteProveedor (IdProveedor, Tipo, Monto, Descripcion, IdPagoProveedor, IdUsuario)
        VALUES (@IdProveedor, 'PAGO', -@Importe, @Desc, @IdPago, @IdUsuario);

        COMMIT;
        SELECT @IdPago AS IdPago,
               (SELECT ISNULL(SUM(Monto), 0) FROM MovimientoCtaCteProveedor WHERE IdProveedor = @IdProveedor) AS SaldoNuevo;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

IF OBJECT_ID('SP_PagoProveedor_Anular', 'P') IS NOT NULL DROP PROCEDURE SP_PagoProveedor_Anular;
GO
CREATE PROCEDURE SP_PagoProveedor_Anular
    @IdPago    INT,
    @Motivo    NVARCHAR(250),
    @IdUsuario INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 10
            RAISERROR('El motivo de la anulacion debe tener al menos 10 caracteres.', 16, 1);

        BEGIN TRANSACTION;

        DECLARE @Prov INT, @Importe DECIMAL(12,2), @Cuenta INT, @Estado VARCHAR(12);
        SELECT @Prov = IdProveedor, @Importe = Importe, @Cuenta = IdCuentaFinanciera, @Estado = Estado
        FROM PagoProveedor WITH (UPDLOCK) WHERE Id = @IdPago;

        IF @Prov IS NULL         RAISERROR('El pago no existe.', 16, 1);
        IF @Estado = 'ANULADO'   RAISERROR('El pago ya esta anulado.', 16, 1);

        DECLARE @Desc NVARCHAR(250) = LEFT('Anulacion del pago #' + CAST(@IdPago AS NVARCHAR(10)) + ': ' + @Motivo, 250);

        EXEC SP_Cuenta_RegistrarMovimiento
             @IdCuentaFinanciera = @Cuenta, @Tipo = 'Ingreso', @Concepto = 'Anulacion de pago a proveedor',
             @Monto = @Importe, @Descripcion = @Desc, @IdUsuario = @IdUsuario, @IdPagoProveedor = @IdPago;

        INSERT INTO MovimientoCtaCteProveedor (IdProveedor, Tipo, Monto, Descripcion, IdPagoProveedor, IdUsuario)
        VALUES (@Prov, 'ANULACION', @Importe, @Desc, @IdPago, @IdUsuario);

        UPDATE PagoProveedor
        SET Estado = 'ANULADO', FechaAnulacion = GETDATE(), IdUsuarioAnulacion = @IdUsuario, MotivoAnulacion = @Motivo
        WHERE Id = @IdPago;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   VERIFICACION
   ----------------------------------------------------------------- */
SELECT name FROM sys.procedures
WHERE name IN ('SP_Pedido_Recibir', 'SP_RecepcionPedido_Anular', 'SP_Pedido_CerrarFaltantes',
               'SP_Pedido_ParaRecepcion', 'SP_Pedido_ResumenRecepcion', 'SP_CtaCteProveedor_Saldos',
               'SP_CtaCteProveedor_Movimientos', 'SP_CtaCteProveedor_Ajuste',
               'SP_PagoProveedor_I', 'SP_PagoProveedor_Anular', 'SP_Pedido_RecalcularEstado')
ORDER BY name;   -- tienen que ser 11

SELECT TOP 5 p.Id, p.IdEstado, SUM(dp.Cantidad) AS Pedidas, SUM(dp.CantidadRecibida) AS Recibidas
FROM Pedido p INNER JOIN DetallePedido dp ON dp.IdPedido = p.Id
GROUP BY p.Id, p.IdEstado ORDER BY p.Id DESC;
GO

SET NOEXEC OFF;
GO
