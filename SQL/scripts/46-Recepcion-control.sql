USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   46 — RECEPCION EN DOS TIEMPOS, CON CONTROL E INCIDENCIAS

   El proceso real del local:
     1. Llega el repartidor. Se saca la foto de la factura (o se sube
        el PDF del mail). La recepcion queda EN_CONTROL: no hay stock
        ni deuda todavia. La mercaderia espera hasta que haya tiempo.
     2. Control: por cada renglon, cuanto se FACTURO, cuanto se
        RECIBIO y cuanto vino en MAL ESTADO.
     3. Confirmar: sube al stock solo lo que esta en buen estado, la
        deuda es el total de la factura, y cada diferencia queda como
        INCIDENCIA abierta para resolver con el viajante.

   Por que la deuda es el total de la factura y no lo que llego: si el
   proveedor facturo 10 y llegaron 8, le debemos 10 hasta que mande la
   nota de credito. Bajarla solos seria inventar un documento.

   Lo que llega roto queda apartado: esta en el local pero no entra al
   stock vendible. Es la incidencia DANADO abierta, la lista de lo que
   hay que devolverle al viajante.

   El viajante no resuelve el reclamo en la visita: deja un recibo y la
   empresa revisa. La nota de credito llega despues. Por eso una
   incidencia pasa por ABIERTA -> EN_RECLAMO -> RESUELTA o RECHAZADA.

   Los reclamos NO se descuentan del pago: se paga cada factura a su
   vencimiento (unos 30 dias) y la nota de credito se toma cuando llega.

   Requiere los scripts 43 y 45.
   ================================================================= */


/* -----------------------------------------------------------------
   1. Recepcion: estado y vinculo con la lectura
   ----------------------------------------------------------------- */
IF COL_LENGTH('RecepcionPedido', 'Estado') IS NULL
BEGIN
    ALTER TABLE RecepcionPedido ADD
        Estado                VARCHAR(12) NOT NULL CONSTRAINT DF_Recep_Estado DEFAULT 'CONFIRMADA',
        FechaConfirmacion     DATETIME NULL,
        IdUsuarioConfirmacion INT NULL,
        IdLecturaFactura      INT NULL CONSTRAINT FK_Recep_Lectura REFERENCES LecturaFactura(Id);
END
GO
-- Las recepciones anteriores ya estaban confirmadas
UPDATE RecepcionPedido SET FechaConfirmacion = Fecha, IdUsuarioConfirmacion = IdUsuario
WHERE Estado = 'CONFIRMADA' AND FechaConfirmacion IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Recep_Estado')
    ALTER TABLE RecepcionPedido ADD CONSTRAINT CK_Recep_Estado CHECK (Estado IN ('EN_CONTROL', 'CONFIRMADA'));
GO


/* -----------------------------------------------------------------
   2. Renglones: tres cantidades
     CantidadFacturada  lo que dice la factura
     CantidadRecibida   lo que se conto (NULL hasta el control)
     CantidadDanada     lo que vino roto
     Cantidad           lo que entra al stock = recibida - danada
     CantidadImputada   lo que se descuenta de lo pendiente del pedido
   Un renglon puede no estar identificado (IdRepuesto NULL): es algo
   facturado que no esta en nuestro catalogo.
   ----------------------------------------------------------------- */
IF COL_LENGTH('DetalleRecepcion', 'CantidadFacturada') IS NULL
BEGIN
    ALTER TABLE DetalleRecepcion ADD
        CodigoFactura      NVARCHAR(60)  NULL,
        DescripcionFactura NVARCHAR(250) NULL,
        CantidadFacturada  INT NOT NULL CONSTRAINT DF_DetRecep_Fact DEFAULT 0,
        CantidadRecibida   INT NULL,
        CantidadDanada     INT NOT NULL CONSTRAINT DF_DetRecep_Dan DEFAULT 0,
        CantidadImputada   INT NOT NULL CONSTRAINT DF_DetRecep_Imp DEFAULT 0,
        Observacion        NVARCHAR(200) NULL;
END
GO
-- Las anteriores: se facturo, llego y entro lo mismo
UPDATE DetalleRecepcion
SET CantidadFacturada = Cantidad, CantidadRecibida = Cantidad, CantidadImputada = Cantidad
WHERE CantidadRecibida IS NULL AND CantidadFacturada = 0;
GO

ALTER TABLE DetalleRecepcion ALTER COLUMN IdRepuesto INT NULL;
GO
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_DetRecep_Cant')
    ALTER TABLE DetalleRecepcion DROP CONSTRAINT CK_DetRecep_Cant;
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_DetRecep_Cantidades')
    ALTER TABLE DetalleRecepcion ADD CONSTRAINT CK_DetRecep_Cantidades CHECK (
        Cantidad >= 0 AND CantidadFacturada >= 0 AND CantidadDanada >= 0 AND CantidadImputada >= 0
        AND (CantidadRecibida IS NULL OR (CantidadRecibida >= 0 AND CantidadDanada <= CantidadRecibida))
    );
GO


/* -----------------------------------------------------------------
   3. Incidencias: lo que hay que resolver con el proveedor
   ----------------------------------------------------------------- */
IF OBJECT_ID('IncidenciaRecepcion', 'U') IS NULL
BEGIN
    CREATE TABLE IncidenciaRecepcion (
        Id                 INT IDENTITY(1,1) PRIMARY KEY,
        IdRecepcion        INT           NOT NULL,
        IdDetalle          INT           NOT NULL,
        IdProveedor        INT           NOT NULL,
        IdRepuesto         INT           NULL,
        Descripcion        NVARCHAR(250) NOT NULL,
        Tipo               VARCHAR(25)   NOT NULL,
        Cantidad           INT           NOT NULL,
        CostoUnitario      DECIMAL(12,2) NOT NULL,
        Importe            DECIMAL(12,2) NOT NULL,
        Estado             VARCHAR(12)   NOT NULL DEFAULT 'ABIERTA',
        Fecha              DATETIME      NOT NULL DEFAULT GETDATE(),
        IdUsuario          INT           NOT NULL,
        -- Cuando se le entrega al viajante: el recibo que deja es la constancia del reclamo
        NumeroConstancia   NVARCHAR(40)  NULL,
        FechaReclamo       DATETIME      NULL,
        IdUsuarioReclamo   INT           NULL,
        -- Cuando llega la nota de credito (o la rechazan)
        Resolucion         NVARCHAR(250) NULL,
        FechaResolucion    DATETIME      NULL,
        IdUsuarioResolucion INT          NULL,
        CONSTRAINT FK_Inc_Recep     FOREIGN KEY (IdRecepcion) REFERENCES RecepcionPedido(Id),
        CONSTRAINT FK_Inc_Detalle   FOREIGN KEY (IdDetalle)   REFERENCES DetalleRecepcion(Id),
        CONSTRAINT FK_Inc_Proveedor FOREIGN KEY (IdProveedor) REFERENCES Proveedor(Id),
        CONSTRAINT CK_Inc_Tipo CHECK (Tipo IN ('FACTURADO_NO_RECIBIDO', 'RECIBIDO_NO_FACTURADO', 'DANADO', 'NO_PEDIDO')),
        /* ABIERTA     se detecto al controlar; lo roto esta apartado en el local
           EN_RECLAMO  se entrego al viajante, que dejo un recibo; el proveedor revisa
           RESUELTA    llego la nota de credito (o la factura de lo no facturado)
           RECHAZADA   el proveedor no lo reconocio
           ANULADA     se anulo la recepcion */
        CONSTRAINT CK_Inc_Estado CHECK (Estado IN ('ABIERTA', 'EN_RECLAMO', 'RESUELTA', 'RECHAZADA', 'ANULADA')),
        CONSTRAINT CK_Inc_Cant CHECK (Cantidad > 0)
    );
    CREATE INDEX IX_Inc_Proveedor ON IncidenciaRecepcion(IdProveedor, Estado);
END
GO


/* -----------------------------------------------------------------
   4. Tipos de tabla
   ----------------------------------------------------------------- */
-- Al capturar: lo que dice la factura
IF TYPE_ID('RecepcionFacturaType') IS NULL
    CREATE TYPE RecepcionFacturaType AS TABLE (
        IdRepuesto        INT            NULL,
        Codigo            NVARCHAR(60)   NULL,
        Descripcion       NVARCHAR(250)  NULL,
        CantidadFacturada INT            NOT NULL,
        CostoUnitario     DECIMAL(12,2)  NOT NULL
    );
GO
-- Al controlar: lo que se conto. IdDetalle NULL = llego algo que no estaba facturado
IF TYPE_ID('RecepcionControlType') IS NULL
    CREATE TYPE RecepcionControlType AS TABLE (
        IdDetalle        INT            NULL,
        IdRepuesto       INT            NULL,
        CantidadRecibida INT            NOT NULL,
        CantidadDanada   INT            NOT NULL,
        CostoUnitario    DECIMAL(12,2)  NULL,
        Observacion      NVARCHAR(200)  NULL
    );
GO


/* -----------------------------------------------------------------
   5. Paso 1 — capturar la factura
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Recepcion_Iniciar', 'P') IS NOT NULL DROP PROCEDURE SP_Recepcion_Iniciar;
GO
CREATE PROCEDURE SP_Recepcion_Iniciar
    @IdPedido          INT,
    @Lineas            RecepcionFacturaType READONLY,
    @TipoComprobante   VARCHAR(20),
    @NumeroComprobante VARCHAR(40),
    @FechaComprobante  DATE,
    @TotalComprobante  DECIMAL(12,2),
    @IdAdjunto         INT = NULL,
    @IdLecturaFactura  INT = NULL,
    @Observacion       NVARCHAR(250) = NULL,
    @IdUsuario         INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM @Lineas WHERE CantidadFacturada > 0)
            RAISERROR('Cargá al menos un renglón facturado.', 16, 1);
        IF EXISTS (SELECT 1 FROM @Lineas WHERE CantidadFacturada < 0 OR CostoUnitario < 0)
            RAISERROR('Las cantidades y los costos no pueden ser negativos.', 16, 1);
        IF EXISTS (SELECT 1 FROM @Lineas WHERE IdRepuesto IS NULL AND ISNULL(LTRIM(RTRIM(Descripcion)), '') = '')
            RAISERROR('Los renglones sin repuesto identificado necesitan una descripción.', 16, 1);
        IF ISNULL(LTRIM(RTRIM(@TipoComprobante)), '') = '' OR ISNULL(LTRIM(RTRIM(@NumeroComprobante)), '') = ''
            RAISERROR('Indicá el tipo y el número del comprobante del proveedor.', 16, 1);
        IF @TotalComprobante IS NULL OR @TotalComprobante <= 0
            RAISERROR('Indicá el total del comprobante: es lo que se le debe al proveedor.', 16, 1);
        IF @FechaComprobante > CAST(GETDATE() AS DATE)
            RAISERROR('La fecha del comprobante no puede ser futura.', 16, 1);

        BEGIN TRANSACTION;

        DECLARE @IdProveedor INT, @Estado INT;
        SELECT @IdProveedor = IdProveedor, @Estado = IdEstado FROM Pedido WITH (UPDLOCK) WHERE Id = @IdPedido;
        IF @IdProveedor IS NULL RAISERROR('El pedido no existe.', 16, 1);
        IF @Estado = 3         RAISERROR('El pedido está cancelado.', 16, 1);

        IF EXISTS (SELECT 1 FROM RecepcionPedido WHERE IdPedido = @IdPedido AND Estado = 'EN_CONTROL' AND Anulada = 0)
            RAISERROR('Este pedido ya tiene una recepción en control. Terminá esa primero.', 16, 1);

        IF EXISTS (SELECT 1 FROM RecepcionPedido
                   WHERE IdProveedor = @IdProveedor AND Anulada = 0
                     AND TipoComprobante = @TipoComprobante AND NumeroComprobante = LTRIM(RTRIM(@NumeroComprobante)))
            RAISERROR('Ese comprobante del proveedor ya está registrado en otra recepción.', 16, 1);

        INSERT INTO RecepcionPedido (IdPedido, IdProveedor, IdUsuario, TipoComprobante, NumeroComprobante,
                                     FechaComprobante, TotalComprobante, IdAdjunto, Observacion, Estado, IdLecturaFactura)
        VALUES (@IdPedido, @IdProveedor, @IdUsuario, @TipoComprobante, LTRIM(RTRIM(@NumeroComprobante)),
                @FechaComprobante, @TotalComprobante, @IdAdjunto, NULLIF(LTRIM(RTRIM(@Observacion)), ''),
                'EN_CONTROL', @IdLecturaFactura);
        DECLARE @IdRecepcion INT = SCOPE_IDENTITY();

        INSERT INTO DetalleRecepcion (IdRecepcion, IdRepuesto, CodigoFactura, DescripcionFactura,
                                      CantidadFacturada, Cantidad, CostoUnitario)
        SELECT @IdRecepcion, l.IdRepuesto, NULLIF(LTRIM(RTRIM(l.Codigo)), ''),
               COALESCE(NULLIF(LTRIM(RTRIM(l.Descripcion)), ''), r.Descripcion),
               l.CantidadFacturada, 0, l.CostoUnitario
        FROM @Lineas l LEFT JOIN Repuesto r ON r.Id = l.IdRepuesto
        WHERE l.CantidadFacturada > 0;

        IF @IdLecturaFactura IS NOT NULL
            UPDATE LecturaFactura SET IdRecepcion = @IdRecepcion WHERE Id = @IdLecturaFactura AND IdRecepcion IS NULL;

        COMMIT;
        SELECT @IdRecepcion AS IdRecepcion;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   6. Paso 3 — confirmar lo controlado
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Recepcion_Confirmar', 'P') IS NOT NULL DROP PROCEDURE SP_Recepcion_Confirmar;
GO
CREATE PROCEDURE SP_Recepcion_Confirmar
    @IdRecepcion INT,
    @Lineas      RecepcionControlType READONLY,
    @IdUsuario   INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF EXISTS (SELECT 1 FROM @Lineas WHERE CantidadRecibida < 0 OR CantidadDanada < 0 OR CantidadDanada > CantidadRecibida)
            RAISERROR('Las cantidades no son válidas: lo que vino en mal estado no puede superar lo recibido.', 16, 1);

        BEGIN TRANSACTION;

        DECLARE @IdPedido INT, @IdProveedor INT, @Estado VARCHAR(12), @Anulada BIT, @Total DECIMAL(12,2), @Comp NVARCHAR(80);
        SELECT @IdPedido = IdPedido, @IdProveedor = IdProveedor, @Estado = Estado, @Anulada = Anulada,
               @Total = TotalComprobante, @Comp = TipoComprobante + ' ' + NumeroComprobante
        FROM RecepcionPedido WITH (UPDLOCK) WHERE Id = @IdRecepcion;

        IF @IdPedido IS NULL           RAISERROR('La recepción no existe.', 16, 1);
        IF @Anulada = 1                RAISERROR('La recepción está anulada.', 16, 1);
        IF @Estado <> 'EN_CONTROL'     RAISERROR('La recepción ya fue confirmada.', 16, 1);

        -- Cada renglon facturado tiene que estar controlado
        IF EXISTS (SELECT 1 FROM DetalleRecepcion d WHERE d.IdRecepcion = @IdRecepcion
                   AND NOT EXISTS (SELECT 1 FROM @Lineas l WHERE l.IdDetalle = d.Id))
            RAISERROR('Falta controlar algún renglón de la factura.', 16, 1);

        -- Lo que no esta identificado no puede entrar al stock
        IF EXISTS (SELECT 1 FROM @Lineas l INNER JOIN DetalleRecepcion d ON d.Id = l.IdDetalle
                   WHERE d.IdRepuesto IS NULL AND l.IdRepuesto IS NULL AND l.CantidadRecibida - l.CantidadDanada > 0)
            RAISERROR('Hay un renglón que llegó pero no está vinculado a ningún repuesto. Vinculalo o marcalo como no recibido.', 16, 1);
        IF EXISTS (SELECT 1 FROM @Lineas WHERE IdDetalle IS NULL AND (IdRepuesto IS NULL OR CantidadRecibida <= 0))
            RAISERROR('Lo que llegó sin facturar tiene que indicar el repuesto y la cantidad.', 16, 1);

        -- Renglones facturados: lo contado
        UPDATE d SET
            d.IdRepuesto       = COALESCE(d.IdRepuesto, l.IdRepuesto),
            d.CantidadRecibida = l.CantidadRecibida,
            d.CantidadDanada   = l.CantidadDanada,
            d.Cantidad         = l.CantidadRecibida - l.CantidadDanada,
            d.CostoUnitario    = COALESCE(l.CostoUnitario, d.CostoUnitario),
            d.Observacion      = NULLIF(LTRIM(RTRIM(l.Observacion)), '')
        FROM DetalleRecepcion d INNER JOIN @Lineas l ON l.IdDetalle = d.Id
        WHERE d.IdRecepcion = @IdRecepcion;

        -- Lo que llego sin estar facturado
        INSERT INTO DetalleRecepcion (IdRecepcion, IdRepuesto, DescripcionFactura, CantidadFacturada,
                                      CantidadRecibida, CantidadDanada, Cantidad, CostoUnitario, Observacion)
        SELECT @IdRecepcion, l.IdRepuesto, r.Descripcion, 0, l.CantidadRecibida, l.CantidadDanada,
               l.CantidadRecibida - l.CantidadDanada,
               COALESCE(l.CostoUnitario, dp.PrecioUnitario, 0), NULLIF(LTRIM(RTRIM(l.Observacion)), '')
        FROM @Lineas l
        INNER JOIN Repuesto r ON r.Id = l.IdRepuesto
        LEFT JOIN DetallePedido dp ON dp.IdPedido = @IdPedido AND dp.IdRepuesto = l.IdRepuesto
        WHERE l.IdDetalle IS NULL;

        -- Cuanto de lo aceptado descuenta lo pendiente del pedido (nunca mas de lo pendiente)
        UPDATE d SET d.CantidadImputada =
            CASE WHEN dp.IdRepuesto IS NULL THEN 0
                 WHEN d.Cantidad < dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada THEN d.Cantidad
                 ELSE dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada END
        FROM DetalleRecepcion d
        LEFT JOIN DetallePedido dp ON dp.IdPedido = @IdPedido AND dp.IdRepuesto = d.IdRepuesto
        WHERE d.IdRecepcion = @IdRecepcion;

        UPDATE dp SET dp.CantidadRecibida = dp.CantidadRecibida + x.Imputada
        FROM DetallePedido dp
        INNER JOIN (SELECT IdRepuesto, SUM(CantidadImputada) AS Imputada FROM DetalleRecepcion
                    WHERE IdRecepcion = @IdRecepcion AND IdRepuesto IS NOT NULL GROUP BY IdRepuesto) x
            ON x.IdRepuesto = dp.IdRepuesto
        WHERE dp.IdPedido = @IdPedido;

        -- Stock: solo lo que esta en buen estado
        INSERT INTO Stock (IdRepuesto, Cantidad, UltimaActualizacion)
        SELECT DISTINCT d.IdRepuesto, 0, GETDATE() FROM DetalleRecepcion d
        WHERE d.IdRecepcion = @IdRecepcion AND d.IdRepuesto IS NOT NULL AND d.Cantidad > 0
          AND NOT EXISTS (SELECT 1 FROM Stock s WHERE s.IdRepuesto = d.IdRepuesto);

        UPDATE s SET s.Cantidad = s.Cantidad + x.Cant, s.UltimaActualizacion = GETDATE()
        FROM Stock s
        INNER JOIN (SELECT IdRepuesto, SUM(Cantidad) AS Cant FROM DetalleRecepcion
                    WHERE IdRecepcion = @IdRecepcion AND IdRepuesto IS NOT NULL GROUP BY IdRepuesto) x
            ON x.IdRepuesto = s.IdRepuesto;

        -- Incidencias: una por cada diferencia
        INSERT INTO IncidenciaRecepcion (IdRecepcion, IdDetalle, IdProveedor, IdRepuesto, Descripcion, Tipo,
                                         Cantidad, CostoUnitario, Importe, IdUsuario)
        SELECT @IdRecepcion, d.Id, @IdProveedor, d.IdRepuesto, ISNULL(d.DescripcionFactura, '(sin descripción)'),
               t.Tipo, t.Cant, d.CostoUnitario, CAST(t.Cant * d.CostoUnitario AS DECIMAL(12,2)), @IdUsuario
        FROM DetalleRecepcion d
        CROSS APPLY (VALUES
            ('FACTURADO_NO_RECIBIDO', d.CantidadFacturada - d.CantidadRecibida),
            ('RECIBIDO_NO_FACTURADO', d.CantidadRecibida - d.CantidadFacturada),
            ('DANADO',                d.CantidadDanada),
            -- llego, se acepto, pero no estaba pedido o excede lo pendiente
            ('NO_PEDIDO',             d.Cantidad - d.CantidadImputada)
        ) t(Tipo, Cant)
        WHERE d.IdRecepcion = @IdRecepcion AND t.Cant > 0;

        -- Deuda: el total de la factura, tal cual
        DECLARE @Desc NVARCHAR(250) = @Comp + ' · recepción #' + CAST(@IdRecepcion AS NVARCHAR(10)) +
                                      ' del pedido #' + CAST(@IdPedido AS NVARCHAR(10));
        INSERT INTO MovimientoCtaCteProveedor (IdProveedor, Tipo, Monto, Descripcion, IdRecepcion, IdUsuario)
        VALUES (@IdProveedor, 'COMPRA', @Total, @Desc, @IdRecepcion, @IdUsuario);

        UPDATE RecepcionPedido
        SET Estado = 'CONFIRMADA', FechaConfirmacion = GETDATE(), IdUsuarioConfirmacion = @IdUsuario
        WHERE Id = @IdRecepcion;

        EXEC SP_Pedido_RecalcularEstado @IdPedido = @IdPedido;

        COMMIT;

        SELECT @IdRecepcion AS IdRecepcion,
               (SELECT IdEstado FROM Pedido WHERE Id = @IdPedido) AS IdEstadoPedido,
               (SELECT COUNT(*) FROM IncidenciaRecepcion WHERE IdRecepcion = @IdRecepcion) AS Incidencias,
               (SELECT ISNULL(SUM(Importe), 0) FROM IncidenciaRecepcion
                WHERE IdRecepcion = @IdRecepcion AND Tipo IN ('FACTURADO_NO_RECIBIDO', 'DANADO')) AS ImporteAReclamar;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   7. Anular: distinto segun este en control o confirmada
   ----------------------------------------------------------------- */
ALTER PROCEDURE SP_RecepcionPedido_Anular
    @IdRecepcion INT,
    @Motivo      NVARCHAR(250),
    @IdUsuario   INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 10
            RAISERROR('El motivo de la anulación debe tener al menos 10 caracteres.', 16, 1);

        BEGIN TRANSACTION;

        DECLARE @IdPedido INT, @IdProveedor INT, @Total DECIMAL(12,2), @Anulada BIT, @Estado VARCHAR(12), @Comp NVARCHAR(80);
        SELECT @IdPedido = IdPedido, @IdProveedor = IdProveedor, @Total = TotalComprobante, @Anulada = Anulada,
               @Estado = Estado, @Comp = TipoComprobante + ' ' + NumeroComprobante
        FROM RecepcionPedido WITH (UPDLOCK) WHERE Id = @IdRecepcion;

        IF @IdPedido IS NULL RAISERROR('La recepción no existe.', 16, 1);
        IF @Anulada = 1      RAISERROR('La recepción ya está anulada.', 16, 1);

        IF @Estado = 'CONFIRMADA'
        BEGIN
            -- No se puede si alguna incidencia ya se resolvio con el proveedor
            IF EXISTS (SELECT 1 FROM IncidenciaRecepcion WHERE IdRecepcion = @IdRecepcion
                       AND Estado IN ('EN_RECLAMO', 'RESUELTA', 'RECHAZADA'))
                RAISERROR('Esta recepción tiene reclamos ya iniciados con el proveedor: no se puede anular.', 16, 1);

            DECLARE @sinStock NVARCHAR(200);
            SELECT TOP 1 @sinStock = r.Descripcion
            FROM (SELECT IdRepuesto, SUM(Cantidad) AS Cant FROM DetalleRecepcion
                  WHERE IdRecepcion = @IdRecepcion AND IdRepuesto IS NOT NULL GROUP BY IdRepuesto) d
            INNER JOIN Stock s WITH (UPDLOCK) ON s.IdRepuesto = d.IdRepuesto
            INNER JOIN Repuesto r ON r.Id = d.IdRepuesto
            WHERE s.Cantidad < d.Cant;
            IF @sinStock IS NOT NULL
            BEGIN
                DECLARE @msg NVARCHAR(300) = 'No se puede anular: parte de lo recibido ya se vendió (' + @sinStock + ').';
                RAISERROR(@msg, 16, 1);
            END

            UPDATE s SET s.Cantidad = s.Cantidad - d.Cant, s.UltimaActualizacion = GETDATE()
            FROM Stock s
            INNER JOIN (SELECT IdRepuesto, SUM(Cantidad) AS Cant FROM DetalleRecepcion
                        WHERE IdRecepcion = @IdRecepcion AND IdRepuesto IS NOT NULL GROUP BY IdRepuesto) d
                ON d.IdRepuesto = s.IdRepuesto;

            UPDATE dp SET dp.CantidadRecibida = dp.CantidadRecibida - d.Imp
            FROM DetallePedido dp
            INNER JOIN (SELECT IdRepuesto, SUM(CantidadImputada) AS Imp FROM DetalleRecepcion
                        WHERE IdRecepcion = @IdRecepcion AND IdRepuesto IS NOT NULL GROUP BY IdRepuesto) d
                ON d.IdRepuesto = dp.IdRepuesto
            WHERE dp.IdPedido = @IdPedido;

            DECLARE @Desc NVARCHAR(250) = LEFT('Anulación de ' + @Comp + ' (recepción #' + CAST(@IdRecepcion AS NVARCHAR(10)) + '): ' + @Motivo, 250);
            INSERT INTO MovimientoCtaCteProveedor (IdProveedor, Tipo, Monto, Descripcion, IdRecepcion, IdUsuario)
            VALUES (@IdProveedor, 'ANULACION', -@Total, @Desc, @IdRecepcion, @IdUsuario);

            UPDATE IncidenciaRecepcion
            SET Estado = 'ANULADA', Resolucion = 'Recepción anulada', FechaResolucion = GETDATE(), IdUsuarioResolucion = @IdUsuario
            WHERE IdRecepcion = @IdRecepcion AND Estado = 'ABIERTA';
        END
        -- En control: no hubo stock ni deuda, solo se marca anulada

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
   8. Consultas para la pantalla
   ----------------------------------------------------------------- */
ALTER PROCEDURE SP_Pedido_ParaRecepcion @IdPedido INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT p.Id, p.Fecha, p.IdEstado, p.IdProveedor, pr.RazonSocial AS Proveedor, p.MotivoCierreFaltantes
    FROM Pedido p INNER JOIN Proveedor pr ON pr.Id = p.IdProveedor
    WHERE p.Id = @IdPedido;

    SELECT dp.IdRepuesto, r.Codigo, r.Descripcion,
           dp.Cantidad, dp.CantidadRecibida, dp.CantidadCancelada,
           dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada AS Pendiente,
           dp.PrecioUnitario
    FROM DetallePedido dp INNER JOIN Repuesto r ON r.Id = dp.IdRepuesto
    WHERE dp.IdPedido = @IdPedido
    ORDER BY r.Descripcion;

    SELECT rp.Id, rp.Fecha, rp.Estado, rp.TipoComprobante, rp.NumeroComprobante, rp.TotalComprobante,
           rp.IdAdjunto, rp.Anulada, rp.MotivoAnulacion, u.Nombre AS Usuario,
           (SELECT SUM(Cantidad) FROM DetalleRecepcion d WHERE d.IdRecepcion = rp.Id) AS Unidades,
           (SELECT COUNT(*) FROM IncidenciaRecepcion i WHERE i.IdRecepcion = rp.Id AND i.Estado IN ('ABIERTA', 'EN_RECLAMO')) AS IncidenciasAbiertas
    FROM RecepcionPedido rp LEFT JOIN Usuario u ON u.Id = rp.IdUsuario
    WHERE rp.IdPedido = @IdPedido
    ORDER BY rp.Id;

    -- Renglones de la recepcion en control, si hay una
    SELECT d.Id AS IdDetalle, d.IdRecepcion, d.IdRepuesto, r.Codigo, d.CodigoFactura,
           COALESCE(r.Descripcion, d.DescripcionFactura) AS Descripcion,
           d.CantidadFacturada, d.CostoUnitario,
           dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada AS PendientePedido
    FROM DetalleRecepcion d
    INNER JOIN RecepcionPedido rp ON rp.Id = d.IdRecepcion AND rp.Estado = 'EN_CONTROL' AND rp.Anulada = 0
    LEFT JOIN Repuesto r       ON r.Id = d.IdRepuesto
    LEFT JOIN DetallePedido dp ON dp.IdPedido = rp.IdPedido AND dp.IdRepuesto = d.IdRepuesto
    WHERE rp.IdPedido = @IdPedido
    ORDER BY d.Id;
END
GO

-- Incidencias abiertas: por proveedor o todas
IF OBJECT_ID('SP_Incidencia_Abiertas', 'P') IS NOT NULL DROP PROCEDURE SP_Incidencia_Abiertas;
GO
CREATE PROCEDURE SP_Incidencia_Abiertas @IdProveedor INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT i.Id, i.IdRecepcion, i.IdProveedor, pr.RazonSocial AS Proveedor, i.IdRepuesto, r.Codigo,
           i.Descripcion, i.Tipo, i.Estado, i.Cantidad, i.CostoUnitario, i.Importe, i.Fecha,
           i.NumeroConstancia, i.FechaReclamo,
           rp.TipoComprobante + ' ' + rp.NumeroComprobante AS Comprobante, rp.IdPedido, rp.IdAdjunto
    FROM IncidenciaRecepcion i
    INNER JOIN Proveedor pr ON pr.Id = i.IdProveedor
    INNER JOIN RecepcionPedido rp ON rp.Id = i.IdRecepcion
    LEFT JOIN Repuesto r ON r.Id = i.IdRepuesto
    WHERE i.Estado IN ('ABIERTA', 'EN_RECLAMO') AND (@IdProveedor IS NULL OR i.IdProveedor = @IdProveedor)
    ORDER BY pr.RazonSocial, i.Estado, i.Fecha;
END
GO

-- Las incidencias abiertas, resumidas, para la cuenta de proveedores
ALTER PROCEDURE SP_CtaCteProveedor_Saldos
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.Id, p.RazonSocial,
           ISNULL((SELECT SUM(m.Monto) FROM MovimientoCtaCteProveedor m WHERE m.IdProveedor = p.Id), 0) AS Saldo,
           (SELECT MAX(m.Fecha) FROM MovimientoCtaCteProveedor m WHERE m.IdProveedor = p.Id) AS UltimoMovimiento,
           (SELECT COUNT(*) FROM Pedido pe WHERE pe.IdProveedor = p.Id AND pe.IdEstado = 1) AS PedidosPendientes,
           (SELECT COUNT(*) FROM IncidenciaRecepcion i WHERE i.IdProveedor = p.Id AND i.Estado IN ('ABIERTA', 'EN_RECLAMO')) AS Incidencias,
           -- Lo que el proveedor tiene que acreditar: informativo, no se descuenta del pago
           ISNULL((SELECT SUM(i.Importe) FROM IncidenciaRecepcion i
                   WHERE i.IdProveedor = p.Id AND i.Estado IN ('ABIERTA', 'EN_RECLAMO')
                     AND i.Tipo IN ('FACTURADO_NO_RECIBIDO', 'DANADO')), 0) AS ImporteAReclamar
    FROM Proveedor p
    WHERE p.Activo = 1
    ORDER BY ISNULL((SELECT SUM(m.Monto) FROM MovimientoCtaCteProveedor m WHERE m.IdProveedor = p.Id), 0) DESC, p.RazonSocial;
END
GO
