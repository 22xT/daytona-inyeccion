USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   69 — REPOSICION SUGERIDA MAS CLARA

   La pantalla mostraba el codigo y la descripcion tal como venian de
   la lista del proveedor, sin marca ni codigo de fabrica, y un
   "+1 en camino" que no decia en que pedido estaba ni si ya se habia
   mandado.

   Mismo calculo que el script 62 (minimo + encargado - stock - en
   camino), con dos agregados:
   - Marca, codigo de fabrica y rubro de cada repuesto.
   - Un cuarto resultado con el detalle de lo que ya esta pedido:
     numero de pedido, proveedor, cantidad, si esta en armado o
     enviado, y cuando llega.
   ================================================================= */

IF OBJECT_ID('SP_Reposicion_Sugerida', 'P') IS NOT NULL DROP PROCEDURE SP_Reposicion_Sugerida;
GO
CREATE PROCEDURE SP_Reposicion_Sugerida
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH EnCamino AS (
        SELECT dp.IdRepuesto, SUM(dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada) AS Cant
        FROM DetallePedido dp INNER JOIN Pedido p ON p.Id = dp.IdPedido
        WHERE p.IdEstado = 1 AND dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada > 0
        GROUP BY dp.IdRepuesto
    ),
    Base AS (
        SELECT r.Id AS IdRepuesto, r.Codigo, r.Descripcion,
               r.MarcaFabricante, r.CodigoFabricante, ru.Nombre AS Rubro,
               ISNULL(s.Cantidad, 0) AS Stock, ISNULL(s.StockMinimo, 0) AS Minimo,
               ISNULL(ec.Cant, 0) AS EnCamino,
               ISNULL(rv.Reservado, 0) AS Encargado
        FROM Repuesto r
        LEFT JOIN Rubro ru ON ru.Id = r.IdRubro
        LEFT JOIN Stock s ON s.IdRepuesto = r.Id
        LEFT JOIN EnCamino ec ON ec.IdRepuesto = r.Id
        LEFT JOIN vw_StockReservado rv ON rv.IdRepuesto = r.Id
        WHERE r.Activo = 1
          AND (   (ISNULL(s.StockMinimo, 0) > 0 AND ISNULL(s.Cantidad, 0) <= ISNULL(s.StockMinimo, 0))
               OR ISNULL(rv.Reservado, 0) > 0)
    )
    SELECT b.IdRepuesto, b.Codigo, b.Descripcion, b.MarcaFabricante, b.CodigoFabricante, b.Rubro,
           b.Stock, b.Minimo, b.EnCamino, b.Encargado,
           b.Minimo + b.Encargado - b.Stock - b.EnCamino AS Sugerido,
           CASE WHEN b.Stock - b.Encargado <= 0  THEN 'SIN_STOCK'
                WHEN (b.Stock - b.Encargado) * 2 <= b.Minimo THEN 'CRITICO'
                ELSE 'BAJO' END AS Urgencia
    INTO #Items
    FROM Base b
    WHERE b.Minimo + b.Encargado - b.Stock - b.EnCamino > 0;

    -- 1. Repuestos a reponer: los mas urgentes primero
    SELECT * FROM #Items
    ORDER BY CASE Urgencia WHEN 'SIN_STOCK' THEN 0 WHEN 'CRITICO' THEN 1 ELSE 2 END,
             CASE WHEN Encargado > 0 THEN 0 ELSE 1 END, Descripcion;

    -- 2. Opciones de compra, solo de esos repuestos
    SELECT pr.IdRepuesto, pr.IdProveedor, p.RazonSocial AS Proveedor, pr.PrecioCompra AS Precio,
           p.CondicionIva, pr.CodigoProveedor
    FROM ProveedorRepuesto pr
    INNER JOIN #Items i ON i.IdRepuesto = pr.IdRepuesto
    INNER JOIN Proveedor p ON p.Id = pr.IdProveedor AND p.Activo = 1
    WHERE pr.Activo = 1 AND pr.PrecioCompra > 0
    ORDER BY pr.IdRepuesto, pr.PrecioCompra;

    -- 3. Bajo minimo pero ya pedidos del todo (no aparecen en la lista)
    ;WITH EnCamino AS (
        SELECT dp.IdRepuesto, SUM(dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada) AS Cant
        FROM DetallePedido dp INNER JOIN Pedido p ON p.Id = dp.IdPedido
        WHERE p.IdEstado = 1 GROUP BY dp.IdRepuesto
    )
    SELECT COUNT(*) AS CubiertosEnCamino
    FROM Repuesto r
    INNER JOIN Stock s ON s.IdRepuesto = r.Id
    INNER JOIN EnCamino ec ON ec.IdRepuesto = r.Id
    LEFT JOIN vw_StockReservado rv ON rv.IdRepuesto = r.Id
    WHERE r.Activo = 1 AND (s.StockMinimo > 0 OR ISNULL(rv.Reservado, 0) > 0)
      AND s.Cantidad <= s.StockMinimo + ISNULL(rv.Reservado, 0)
      AND s.StockMinimo + ISNULL(rv.Reservado, 0) - s.Cantidad - ec.Cant <= 0;

    -- 4. Lo que ya esta pedido de cada repuesto de la lista: en que pedido y cuando llega
    SELECT dp.IdRepuesto, p.Id AS IdPedido, pv.RazonSocial AS Proveedor,
           SUM(dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada) AS Cantidad,
           CASE WHEN p.FechaEnvio IS NULL THEN 1 ELSE 0 END AS EnArmado,
           p.FechaEnvio,
           CASE WHEN p.FechaEnvio IS NULL THEN NULL
                ELSE dbo.fn_LlegadaEstimada(p.FechaEnvio, pv.DiasEntrega) END AS LlegadaEstimada
    FROM DetallePedido dp
    INNER JOIN Pedido p     ON p.Id = dp.IdPedido
    INNER JOIN Proveedor pv ON pv.Id = p.IdProveedor
    INNER JOIN #Items i     ON i.IdRepuesto = dp.IdRepuesto
    WHERE p.IdEstado = 1 AND dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada > 0
    GROUP BY dp.IdRepuesto, p.Id, pv.RazonSocial, p.FechaEnvio, pv.DiasEntrega
    ORDER BY dp.IdRepuesto, p.Id;
END
GO

EXEC SP_Reposicion_Sugerida;
GO
