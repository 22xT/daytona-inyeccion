USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   73 — SACAR UN RENGLON DE UN PEDIDO EN ARMADO

   Mientras el pedido esta en armado (todavia no se cargo en la web
   del proveedor) se puede sacar lo que no corresponde. Una vez
   enviado, no: lo que no llegue se cierra como faltante desde la
   recepcion.

   - No se saca un renglon que es de un encargo: hay un cliente
     esperando. Primero se cancela el encargo.
   - El total del pedido se recalcula.
   - Si el pedido queda vacio, se borra (estaba en armado, no se
     mando a nadie).
   ================================================================= */

IF OBJECT_ID('SP_Pedido_QuitarRenglon', 'P') IS NOT NULL DROP PROCEDURE SP_Pedido_QuitarRenglon;
GO
CREATE PROCEDURE SP_Pedido_QuitarRenglon
    @IdDetalle INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @IdPedido INT, @FechaEnvio DATETIME, @IdEstado INT, @Recibido INT;

    SELECT @IdPedido = p.Id, @FechaEnvio = p.FechaEnvio, @IdEstado = p.IdEstado,
           @Recibido = dp.CantidadRecibida
    FROM DetallePedido dp INNER JOIN Pedido p ON p.Id = dp.IdPedido
    WHERE dp.Id = @IdDetalle;

    IF @IdPedido IS NULL
        THROW 50140, 'Ese renglon no existe.', 1;
    IF @IdEstado <> 1 OR @FechaEnvio IS NOT NULL
        THROW 50141, 'El pedido ya se envio al proveedor: lo que no llegue se cierra como faltante al recibir.', 1;
    IF ISNULL(@Recibido, 0) > 0
        THROW 50142, 'De ese renglon ya se recibio mercaderia.', 1;
    IF EXISTS (SELECT 1 FROM EncargoDetalle ed INNER JOIN Encargo e ON e.Id = ed.IdEncargo
               WHERE ed.IdDetallePedido = @IdDetalle AND e.Estado IN ('PENDIENTE', 'AVISADO'))
        THROW 50143, 'Ese renglon es de un encargo de un cliente. Si ya no lo quiere, cancela el encargo desde Ventas > Encargos.', 1;

    DECLARE @Quedan INT;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Encargos ya cerrados que apuntaban a este renglon: se suelta la referencia
        UPDATE EncargoDetalle SET IdDetallePedido = NULL WHERE IdDetallePedido = @IdDetalle;

        DELETE FROM DetallePedido WHERE Id = @IdDetalle;

        SET @Quedan = (SELECT COUNT(*) FROM DetallePedido WHERE IdPedido = @IdPedido);

        IF @Quedan = 0
            DELETE FROM Pedido WHERE Id = @IdPedido;
        ELSE
            UPDATE Pedido
            SET Total = (SELECT SUM(Cantidad * PrecioUnitario) FROM DetallePedido WHERE IdPedido = @IdPedido)
            WHERE Id = @IdPedido;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    SELECT @IdPedido AS IdPedido, @Quedan AS RenglonesQuedan;
END
GO
