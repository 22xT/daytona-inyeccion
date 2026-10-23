USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   55 — CAMBIAR O QUITAR LA FOTO DE UNA FACTURA

   Si se subio la foto equivocada, se reemplaza o se quita. La foto
   anterior NO se borra: queda guardada y desvinculada, con quien la
   cambio y cuando. Es el respaldo de una deuda con el proveedor.
   ================================================================= */

IF OBJECT_ID('AdjuntoCambio', 'U') IS NULL
BEGIN
    CREATE TABLE AdjuntoCambio (
        Id                 INT IDENTITY(1,1) PRIMARY KEY,
        IdRecepcion        INT           NOT NULL,
        IdAdjuntoAnterior  INT           NULL,
        IdAdjuntoNuevo     INT           NULL,      -- NULL: se quito la foto
        Fecha              DATETIME      NOT NULL DEFAULT GETDATE(),
        IdUsuario          INT           NOT NULL,
        CONSTRAINT FK_AdjCambio_Recep    FOREIGN KEY (IdRecepcion)       REFERENCES RecepcionPedido(Id),
        CONSTRAINT FK_AdjCambio_Anterior FOREIGN KEY (IdAdjuntoAnterior) REFERENCES Adjunto(Id),
        CONSTRAINT FK_AdjCambio_Nuevo    FOREIGN KEY (IdAdjuntoNuevo)    REFERENCES Adjunto(Id)
    );
END
GO

IF OBJECT_ID('SP_Recepcion_CambiarAdjunto', 'P') IS NOT NULL DROP PROCEDURE SP_Recepcion_CambiarAdjunto;
GO
CREATE PROCEDURE SP_Recepcion_CambiarAdjunto
    @IdRecepcion INT,
    @IdAdjunto   INT = NULL,     -- NULL = quitar la foto
    @IdUsuario   INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @Anterior INT, @Existe BIT = 0;
        SELECT @Anterior = IdAdjunto, @Existe = 1 FROM RecepcionPedido WITH (UPDLOCK) WHERE Id = @IdRecepcion;

        IF @Existe = 0
            RAISERROR('La recepción no existe.', 16, 1);
        IF @IdAdjunto IS NULL AND @Anterior IS NULL
            RAISERROR('Esa factura no tiene foto.', 16, 1);
        IF @IdAdjunto IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Adjunto WHERE Id = @IdAdjunto)
            RAISERROR('El archivo nuevo no existe.', 16, 1);

        UPDATE RecepcionPedido SET IdAdjunto = @IdAdjunto WHERE Id = @IdRecepcion;

        INSERT INTO AdjuntoCambio (IdRecepcion, IdAdjuntoAnterior, IdAdjuntoNuevo, IdUsuario)
        VALUES (@IdRecepcion, @Anterior, @IdAdjunto, @IdUsuario);
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

-- La lista de facturas devuelve la recepcion, para poder cambiar su foto
ALTER PROCEDURE SP_CtaCteProveedor_Facturas @IdProveedor INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

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
           a.IdAdjunto, a.IdPedido, a.IdRecepcion
    FROM Acumulado a
    INNER JOIN Proveedor p ON p.Id = a.IdProveedor
    LEFT JOIN Creditos c ON c.IdProveedor = a.IdProveedor
    WHERE a.Acum - ISNULL(c.Total, 0) > 0
    ORDER BY DATEADD(DAY, p.DiasPago, a.FechaDoc), p.RazonSocial;
END
GO

ALTER PROCEDURE SP_CtaCteProveedor_Saldos
AS
BEGIN
    SET NOCOUNT ON;

    CREATE TABLE #Fact (IdProveedor INT, Proveedor NVARCHAR(200), IdMovimiento INT, Documento NVARCHAR(300),
                        FechaDoc DATE, Vencimiento DATE, Importe DECIMAL(12,2), Pendiente DECIMAL(12,2),
                        DiasParaVencer INT, IdAdjunto INT, IdPedido INT, IdRecepcion INT);
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
