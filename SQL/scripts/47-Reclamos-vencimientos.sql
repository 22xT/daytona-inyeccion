USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   47 — RECLAMOS, NOTAS DE CREDITO Y VENCIMIENTOS DE PROVEEDORES

   Segunda parte del circuito de compras:
     - Cada proveedor tiene su plazo de pago (30 dias por defecto).
       El vencimiento de cada factura se calcula, no se guarda.
     - Que factura sigue impaga se deriva: los pagos y notas de credito
       cancelan primero las facturas mas viejas.
     - Visita del viajante: lo roto se le entrega y deja un recibo. Las
       incidencias pasan a EN_RECLAMO con ese numero.
     - La nota de credito llega despues y cierra los reclamos que cubre.
     - Otras salidas de un reclamo: llego despues, llego la factura, se
       devolvio, se acepto, o el proveedor lo rechazo.

   Requiere el script 46.
   ================================================================= */


/* -----------------------------------------------------------------
   1. Plazo de pago por proveedor
   ----------------------------------------------------------------- */
IF COL_LENGTH('Proveedor', 'DiasPago') IS NULL
    ALTER TABLE Proveedor ADD DiasPago INT NOT NULL CONSTRAINT DF_Proveedor_DiasPago DEFAULT 30
        CONSTRAINT CK_Proveedor_DiasPago CHECK (DiasPago BETWEEN 0 AND 180);
GO

IF OBJECT_ID('SP_Proveedor_SetDiasPago', 'P') IS NOT NULL DROP PROCEDURE SP_Proveedor_SetDiasPago;
GO
CREATE PROCEDURE SP_Proveedor_SetDiasPago @IdProveedor INT, @DiasPago INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @DiasPago IS NULL OR @DiasPago < 0 OR @DiasPago > 180
            RAISERROR('El plazo tiene que estar entre 0 y 180 días.', 16, 1);
        UPDATE Proveedor SET DiasPago = @DiasPago WHERE Id = @IdProveedor;
    END TRY
    BEGIN CATCH THROW; END CATCH
END
GO


/* -----------------------------------------------------------------
   2. Notas de credito del proveedor
   ----------------------------------------------------------------- */
IF OBJECT_ID('NotaCreditoProveedor', 'U') IS NULL
BEGIN
    CREATE TABLE NotaCreditoProveedor (
        Id          INT IDENTITY(1,1) PRIMARY KEY,
        IdProveedor INT           NOT NULL,
        Numero      VARCHAR(40)   NOT NULL,
        Fecha       DATE          NOT NULL,
        Importe     DECIMAL(12,2) NOT NULL,
        IdAdjunto   INT           NULL,
        FechaAlta   DATETIME      NOT NULL DEFAULT GETDATE(),
        IdUsuario   INT           NOT NULL,
        CONSTRAINT FK_NCP_Proveedor FOREIGN KEY (IdProveedor) REFERENCES Proveedor(Id),
        CONSTRAINT FK_NCP_Adjunto   FOREIGN KEY (IdAdjunto)   REFERENCES Adjunto(Id),
        CONSTRAINT CK_NCP_Importe   CHECK (Importe > 0)
    );
END
GO

IF COL_LENGTH('IncidenciaRecepcion', 'IdNotaCredito') IS NULL
    ALTER TABLE IncidenciaRecepcion ADD IdNotaCredito INT NULL CONSTRAINT FK_Inc_NC REFERENCES NotaCreditoProveedor(Id);
GO
IF COL_LENGTH('MovimientoCtaCteProveedor', 'IdNotaCredito') IS NULL
    ALTER TABLE MovimientoCtaCteProveedor ADD IdNotaCredito INT NULL CONSTRAINT FK_CCP_NC REFERENCES NotaCreditoProveedor(Id);
GO

-- Lista de Ids para operar sobre varias incidencias a la vez
IF TYPE_ID('IdListType') IS NULL
    CREATE TYPE IdListType AS TABLE (Id INT NOT NULL PRIMARY KEY);
GO


/* -----------------------------------------------------------------
   3. Facturas impagas y vencimientos (derivado)

   Debitos: compras, notas de debito y ajustes positivos.
   Creditos: pagos, notas de credito, anulaciones y ajustes negativos.
   Los creditos cancelan primero los debitos mas viejos. Lo que queda
   es lo impago de cada factura.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_CtaCteProveedor_Facturas', 'P') IS NOT NULL DROP PROCEDURE SP_CtaCteProveedor_Facturas;
GO
CREATE PROCEDURE SP_CtaCteProveedor_Facturas @IdProveedor INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Debitos AS (
        -- Lo que genera deuda: facturas (no anuladas), notas de debito y ajustes positivos
        SELECT m.IdProveedor, m.Id, m.Monto,
               COALESCE(rp.FechaComprobante, CAST(m.Fecha AS DATE)) AS FechaDoc,
               COALESCE(rp.TipoComprobante + ' ' + rp.NumeroComprobante, m.Descripcion) AS Documento,
               rp.IdAdjunto, rp.IdPedido
        FROM MovimientoCtaCteProveedor m
        LEFT JOIN RecepcionPedido rp ON rp.Id = m.IdRecepcion
        WHERE (@IdProveedor IS NULL OR m.IdProveedor = @IdProveedor)
          AND (   (m.Tipo = 'COMPRA' AND ISNULL(rp.Anulada, 0) = 0)
               OR  m.Tipo = 'ND'
               OR (m.Tipo = 'AJUSTE' AND m.Monto > 0))
    ),
    /* Lo que ya se cancelo = lo facturado - el saldo. Asi cualquier
       anulacion (de una recepcion o de un pago) queda bien contada sin
       tener que clasificarla. */
    Creditos AS (
        SELECT d.IdProveedor,
               SUM(d.Monto) - ISNULL((SELECT SUM(m.Monto) FROM MovimientoCtaCteProveedor m
                                      WHERE m.IdProveedor = d.IdProveedor), 0) AS Total
        FROM Debitos d
        GROUP BY d.IdProveedor
    ),
    Acumulado AS (
        SELECT d.*, SUM(d.Monto) OVER (PARTITION BY d.IdProveedor ORDER BY d.FechaDoc, d.Id ROWS UNBOUNDED PRECEDING) AS Acum
        FROM Debitos d
    )
    SELECT a.IdProveedor, p.RazonSocial AS Proveedor, a.Id AS IdMovimiento, a.Documento, a.FechaDoc,
           DATEADD(DAY, p.DiasPago, a.FechaDoc) AS Vencimiento,
           a.Monto AS Importe,
           -- lo que queda de esta factura despues de aplicar los creditos a las anteriores
           CAST(CASE WHEN a.Acum - ISNULL(c.Total, 0) <= 0 THEN 0
                     WHEN a.Acum - ISNULL(c.Total, 0) >= a.Monto THEN a.Monto
                     ELSE a.Acum - ISNULL(c.Total, 0) END AS DECIMAL(12,2)) AS Pendiente,
           DATEDIFF(DAY, CAST(GETDATE() AS DATE), DATEADD(DAY, p.DiasPago, a.FechaDoc)) AS DiasParaVencer,
           a.IdAdjunto, a.IdPedido
    FROM Acumulado a
    INNER JOIN Proveedor p ON p.Id = a.IdProveedor
    LEFT JOIN Creditos c ON c.IdProveedor = a.IdProveedor
    WHERE a.Acum - ISNULL(c.Total, 0) > 0
    ORDER BY DATEADD(DAY, p.DiasPago, a.FechaDoc), p.RazonSocial;
END
GO


/* -----------------------------------------------------------------
   4. Visita del viajante: entregar lo reclamado
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Incidencia_Reclamar', 'P') IS NOT NULL DROP PROCEDURE SP_Incidencia_Reclamar;
GO
CREATE PROCEDURE SP_Incidencia_Reclamar
    @Ids              IdListType READONLY,
    @NumeroConstancia NVARCHAR(40),
    @IdUsuario        INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF ISNULL(LTRIM(RTRIM(@NumeroConstancia)), '') = ''
            RAISERROR('Cargá el número del recibo que dejó el viajante.', 16, 1);
        IF EXISTS (SELECT 1 FROM @Ids x LEFT JOIN IncidenciaRecepcion i ON i.Id = x.Id
                   WHERE i.Id IS NULL OR i.Estado <> 'ABIERTA')
            RAISERROR('Solo se pueden entregar al viajante reclamos que estén abiertos.', 16, 1);
        IF (SELECT COUNT(DISTINCT i.IdProveedor) FROM IncidenciaRecepcion i INNER JOIN @Ids x ON x.Id = i.Id) > 1
            RAISERROR('Los reclamos tienen que ser de un mismo proveedor.', 16, 1);

        UPDATE i SET Estado = 'EN_RECLAMO', NumeroConstancia = LTRIM(RTRIM(@NumeroConstancia)),
                     FechaReclamo = GETDATE(), IdUsuarioReclamo = @IdUsuario
        FROM IncidenciaRecepcion i INNER JOIN @Ids x ON x.Id = i.Id;
    END TRY
    BEGIN CATCH THROW; END CATCH
END
GO


/* -----------------------------------------------------------------
   5. Llego la nota de credito
   Baja la deuda y cierra los reclamos que cubre. El importe puede no
   coincidir con lo reclamado: se registra lo que dice la nota.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_NotaCreditoProveedor_I', 'P') IS NOT NULL DROP PROCEDURE SP_NotaCreditoProveedor_I;
GO
CREATE PROCEDURE SP_NotaCreditoProveedor_I
    @IdProveedor INT,
    @Numero      VARCHAR(40),
    @Fecha       DATE,
    @Importe     DECIMAL(12,2),
    @IdAdjunto   INT = NULL,
    @Incidencias IdListType READONLY,
    @IdUsuario   INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF ISNULL(LTRIM(RTRIM(@Numero)), '') = ''   RAISERROR('Cargá el número de la nota de crédito.', 16, 1);
        IF @Importe IS NULL OR @Importe <= 0        RAISERROR('El importe tiene que ser mayor a cero.', 16, 1);
        IF @Fecha > CAST(GETDATE() AS DATE)         RAISERROR('La fecha no puede ser futura.', 16, 1);
        IF EXISTS (SELECT 1 FROM NotaCreditoProveedor WHERE IdProveedor = @IdProveedor AND Numero = LTRIM(RTRIM(@Numero)))
            RAISERROR('Esa nota de crédito ya está registrada.', 16, 1);
        IF EXISTS (SELECT 1 FROM @Incidencias x LEFT JOIN IncidenciaRecepcion i ON i.Id = x.Id
                   WHERE i.Id IS NULL OR i.IdProveedor <> @IdProveedor OR i.Estado NOT IN ('ABIERTA', 'EN_RECLAMO'))
            RAISERROR('Algún reclamo elegido no es de este proveedor o ya está cerrado.', 16, 1);

        BEGIN TRANSACTION;

        INSERT INTO NotaCreditoProveedor (IdProveedor, Numero, Fecha, Importe, IdAdjunto, IdUsuario)
        VALUES (@IdProveedor, LTRIM(RTRIM(@Numero)), @Fecha, @Importe, @IdAdjunto, @IdUsuario);
        DECLARE @IdNC INT = SCOPE_IDENTITY();

        INSERT INTO MovimientoCtaCteProveedor (IdProveedor, Tipo, Monto, Descripcion, IdUsuario, IdNotaCredito)
        VALUES (@IdProveedor, 'NC', -@Importe, 'Nota de crédito ' + LTRIM(RTRIM(@Numero)), @IdUsuario, @IdNC);

        UPDATE i SET Estado = 'RESUELTA', IdNotaCredito = @IdNC,
                     Resolucion = 'Nota de crédito ' + LTRIM(RTRIM(@Numero)),
                     FechaResolucion = GETDATE(), IdUsuarioResolucion = @IdUsuario
        FROM IncidenciaRecepcion i INNER JOIN @Incidencias x ON x.Id = i.Id;

        COMMIT;
        SELECT @IdNC AS IdNotaCredito;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   6. Otras formas de cerrar un reclamo

   LLEGO_DESPUES   lo facturado que faltaba, o el reemplazo de lo roto,
                   llego en otra entrega: sube al stock sin deuda nueva
   FACTURADO       lo que llego sin factura, se facturo: deuda nueva
   DEVUELTO        lo que llego sin factura o sin pedir, se devolvio:
                   sale del stock
   ACEPTADO        lo que llego sin pedir, nos lo quedamos
   RECHAZADO       el proveedor no reconocio el reclamo
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Incidencia_Resolver', 'P') IS NOT NULL DROP PROCEDURE SP_Incidencia_Resolver;
GO
CREATE PROCEDURE SP_Incidencia_Resolver
    @IdIncidencia INT,
    @Accion       VARCHAR(15),
    @Numero       VARCHAR(40) = NULL,     -- FACTURADO: numero de la factura
    @Importe      DECIMAL(12,2) = NULL,   -- FACTURADO: importe facturado
    @Motivo       NVARCHAR(250) = NULL,
    @IdUsuario    INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @Tipo VARCHAR(25), @Estado VARCHAR(12), @IdProv INT, @IdRep INT, @Cant INT, @IdRecep INT, @Desc NVARCHAR(250);
        SELECT @Tipo = Tipo, @Estado = Estado, @IdProv = IdProveedor, @IdRep = IdRepuesto,
               @Cant = Cantidad, @IdRecep = IdRecepcion, @Desc = Descripcion
        FROM IncidenciaRecepcion WITH (UPDLOCK) WHERE Id = @IdIncidencia;

        IF @Tipo IS NULL                            RAISERROR('El reclamo no existe.', 16, 1);
        IF @Estado NOT IN ('ABIERTA', 'EN_RECLAMO') RAISERROR('El reclamo ya está cerrado.', 16, 1);

        DECLARE @Res NVARCHAR(250);

        IF @Accion = 'LLEGO_DESPUES'
        BEGIN
            IF @Tipo NOT IN ('FACTURADO_NO_RECIBIDO', 'DANADO')
                RAISERROR('Solo lo facturado que faltaba o el reemplazo de lo roto pueden llegar después.', 16, 1);
            IF @IdRep IS NULL
                RAISERROR('El renglón no está vinculado a un repuesto: no se puede sumar al stock.', 16, 1);

            IF NOT EXISTS (SELECT 1 FROM Stock WHERE IdRepuesto = @IdRep)
                INSERT INTO Stock (IdRepuesto, Cantidad, UltimaActualizacion) VALUES (@IdRep, 0, GETDATE());
            UPDATE Stock SET Cantidad = Cantidad + @Cant, UltimaActualizacion = GETDATE() WHERE IdRepuesto = @IdRep;

            -- Descuenta lo pendiente del pedido, sin pasarse
            DECLARE @IdPedido INT = (SELECT IdPedido FROM RecepcionPedido WHERE Id = @IdRecep);
            UPDATE DetallePedido
            SET CantidadRecibida = CantidadRecibida +
                CASE WHEN @Cant < Cantidad - CantidadRecibida - CantidadCancelada THEN @Cant
                     ELSE Cantidad - CantidadRecibida - CantidadCancelada END
            WHERE IdPedido = @IdPedido AND IdRepuesto = @IdRep AND Cantidad - CantidadRecibida - CantidadCancelada > 0;
            EXEC SP_Pedido_RecalcularEstado @IdPedido = @IdPedido;

            SET @Res = CASE WHEN @Tipo = 'DANADO' THEN 'Llegó el reemplazo' ELSE 'Llegó en otra entrega' END;
        END
        ELSE IF @Accion = 'FACTURADO'
        BEGIN
            IF @Tipo NOT IN ('RECIBIDO_NO_FACTURADO', 'NO_PEDIDO')
                RAISERROR('Solo lo que llegó sin facturar puede facturarse después.', 16, 1);
            IF ISNULL(LTRIM(RTRIM(@Numero)), '') = '' OR @Importe IS NULL OR @Importe <= 0
                RAISERROR('Cargá el número y el importe de la factura.', 16, 1);
            INSERT INTO MovimientoCtaCteProveedor (IdProveedor, Tipo, Monto, Descripcion, IdUsuario)
            VALUES (@IdProv, 'ND', @Importe, 'Factura ' + LTRIM(RTRIM(@Numero)) + ' · ' + @Desc, @IdUsuario);
            SET @Res = 'Facturado: ' + LTRIM(RTRIM(@Numero));
        END
        ELSE IF @Accion = 'DEVUELTO'
        BEGIN
            IF @Tipo NOT IN ('RECIBIDO_NO_FACTURADO', 'NO_PEDIDO')
                RAISERROR('Solo lo que llegó sin facturar o sin pedir se devuelve con esta opción. Lo roto se entrega al viajante.', 16, 1);
            IF @IdRep IS NOT NULL
            BEGIN
                IF (SELECT Cantidad FROM Stock WITH (UPDLOCK) WHERE IdRepuesto = @IdRep) < @Cant
                    RAISERROR('No hay stock suficiente para devolverlo: parte ya se vendió.', 16, 1);
                UPDATE Stock SET Cantidad = Cantidad - @Cant, UltimaActualizacion = GETDATE() WHERE IdRepuesto = @IdRep;
            END
            SET @Res = 'Devuelto al proveedor';
        END
        ELSE IF @Accion = 'ACEPTADO'
        BEGIN
            IF @Tipo <> 'NO_PEDIDO'
                RAISERROR('Aceptar solo corresponde a lo que llegó sin estar pedido.', 16, 1);
            SET @Res = 'Aceptado: queda en stock';
        END
        ELSE IF @Accion = 'RECHAZADO'
        BEGIN
            IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 10
                RAISERROR('Explicá el rechazo con al menos 10 caracteres.', 16, 1);
            SET @Res = 'Rechazado por el proveedor: ' + LTRIM(RTRIM(@Motivo));
        END
        ELSE
            RAISERROR('Acción no válida.', 16, 1);

        UPDATE IncidenciaRecepcion
        SET Estado = CASE WHEN @Accion = 'RECHAZADO' THEN 'RECHAZADA' ELSE 'RESUELTA' END,
            Resolucion = LEFT(@Res, 250), FechaResolucion = GETDATE(), IdUsuarioResolucion = @IdUsuario
        WHERE Id = @IdIncidencia;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   7. Datos del proveedor en el resumen: plazo y vencidas
   ----------------------------------------------------------------- */
ALTER PROCEDURE SP_CtaCteProveedor_Saldos
AS
BEGIN
    SET NOCOUNT ON;

    CREATE TABLE #Fact (IdProveedor INT, Proveedor NVARCHAR(200), IdMovimiento INT, Documento NVARCHAR(300),
                        FechaDoc DATE, Vencimiento DATE, Importe DECIMAL(12,2), Pendiente DECIMAL(12,2),
                        DiasParaVencer INT, IdAdjunto INT, IdPedido INT);
    INSERT INTO #Fact EXEC SP_CtaCteProveedor_Facturas;

    SELECT p.Id, p.RazonSocial, p.DiasPago,
           ISNULL((SELECT SUM(m.Monto) FROM MovimientoCtaCteProveedor m WHERE m.IdProveedor = p.Id), 0) AS Saldo,
           (SELECT MAX(m.Fecha) FROM MovimientoCtaCteProveedor m WHERE m.IdProveedor = p.Id) AS UltimoMovimiento,
           (SELECT COUNT(*) FROM Pedido pe WHERE pe.IdProveedor = p.Id AND pe.IdEstado = 1) AS PedidosPendientes,
           (SELECT COUNT(*) FROM IncidenciaRecepcion i WHERE i.IdProveedor = p.Id AND i.Estado IN ('ABIERTA', 'EN_RECLAMO')) AS Incidencias,
           ISNULL((SELECT SUM(i.Importe) FROM IncidenciaRecepcion i
                   WHERE i.IdProveedor = p.Id AND i.Estado IN ('ABIERTA', 'EN_RECLAMO')
                     AND i.Tipo IN ('FACTURADO_NO_RECIBIDO', 'DANADO')), 0) AS ImporteAReclamar,
           ISNULL((SELECT SUM(f.Pendiente) FROM #Fact f WHERE f.IdProveedor = p.Id AND f.DiasParaVencer < 0), 0) AS Vencido,
           ISNULL((SELECT SUM(f.Pendiente) FROM #Fact f WHERE f.IdProveedor = p.Id AND f.DiasParaVencer BETWEEN 0 AND 7), 0) AS VenceEstaSemana,
           (SELECT MIN(f.Vencimiento) FROM #Fact f WHERE f.IdProveedor = p.Id) AS ProximoVencimiento
    FROM Proveedor p
    WHERE p.Activo = 1
    ORDER BY ISNULL((SELECT SUM(m.Monto) FROM MovimientoCtaCteProveedor m WHERE m.IdProveedor = p.Id), 0) DESC, p.RazonSocial;
END
GO
