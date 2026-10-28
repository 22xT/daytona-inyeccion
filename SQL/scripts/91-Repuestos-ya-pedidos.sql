/* =================================================================
   91 — AVISAR SI UN REPUESTO YA ESTA PEDIDO (28/10)

   Prueba C3 de Sofi: despues de confirmar el carrito, si se buscaba el
   mismo repuesto y se tocaba "Pedir", no avisaba que ya estaba en un
   pedido. Se podia pedir dos veces lo mismo.

   SP_Compras_EnCamino: todo lo que esta pedido y todavia no llego,
   renglon por renglon: en que pedido, a quien, cuanto falta recibir,
   si el pedido sigue en armado o ya se envio, y cuando llega.
   Lo usan el Buscador, el Carrito y el Pedido manual para avisar
   "Ya hay 2 en el pedido N° 14 de Autocor (en armado)".
   No toca datos.
   ================================================================= */
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID('SP_Compras_EnCamino', 'P') IS NOT NULL DROP PROCEDURE SP_Compras_EnCamino;
GO
CREATE PROCEDURE SP_Compras_EnCamino
AS
BEGIN
    SET NOCOUNT ON;

    SELECT dp.IdRepuesto, p.Id AS IdPedido, pv.RazonSocial AS Proveedor,
           SUM(dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada) AS Cantidad,
           CASE WHEN p.FechaEnvio IS NULL THEN 1 ELSE 0 END AS EnArmado,
           p.FechaEnvio,
           CASE WHEN p.FechaEnvio IS NULL THEN NULL
                ELSE dbo.fn_LlegadaEstimada(p.FechaEnvio, pv.DiasEntrega) END AS LlegadaEstimada
    FROM DetallePedido dp
    INNER JOIN Pedido p     ON p.Id = dp.IdPedido
    INNER JOIN Proveedor pv ON pv.Id = p.IdProveedor
    WHERE p.IdEstado = 1
      AND dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada > 0
    GROUP BY dp.IdRepuesto, p.Id, pv.RazonSocial, p.FechaEnvio, pv.DiasEntrega
    ORDER BY dp.IdRepuesto, p.Id;
END
GO

-- Prueba: lo que hoy esta pedido y sin recibir
EXEC SP_Compras_EnCamino;
GO
