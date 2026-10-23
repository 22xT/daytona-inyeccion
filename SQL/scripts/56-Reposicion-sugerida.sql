USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   56 — REPOSICION SUGERIDA CALCULADA EN LA BASE

   ANTES: la pantalla bajaba todos los repuestos y las ~60.000 filas de
   las listas de proveedores para calcular en el navegador. Ademas
   sugeria de nuevo lo que ya estaba pedido.

   AHORA:
     Sugerido = Minimo - Stock - EnCamino   (nunca negativo)
   EnCamino es lo pendiente de pedidos abiertos: lo pedido menos lo
   recibido y lo cerrado. Si ya esta pedido, no se vuelve a sugerir.

   Devuelve tres resultados:
     1. Los repuestos a reponer, con su urgencia
     2. Las opciones de compra de cada uno (proveedor y costo), de la
        mas barata a la mas cara
     3. Cuantos estan bajo minimo pero cubiertos por pedidos en camino
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
               ISNULL(s.Cantidad, 0) AS Stock, ISNULL(s.StockMinimo, 0) AS Minimo,
               ISNULL(ec.Cant, 0) AS EnCamino
        FROM Repuesto r
        LEFT JOIN Stock s ON s.IdRepuesto = r.Id
        LEFT JOIN EnCamino ec ON ec.IdRepuesto = r.Id
        WHERE r.Activo = 1 AND ISNULL(s.StockMinimo, 0) > 0 AND ISNULL(s.Cantidad, 0) <= ISNULL(s.StockMinimo, 0)
    )
    SELECT b.IdRepuesto, b.Codigo, b.Descripcion, b.Stock, b.Minimo, b.EnCamino,
           b.Minimo - b.Stock - b.EnCamino AS Sugerido,
           CASE WHEN b.Stock <= 0              THEN 'SIN_STOCK'
                WHEN b.Stock * 2 <= b.Minimo   THEN 'CRITICO'
                ELSE 'BAJO' END AS Urgencia
    INTO #Items
    FROM Base b
    WHERE b.Minimo - b.Stock - b.EnCamino > 0;

    -- 1. Repuestos a reponer: los mas urgentes primero
    SELECT * FROM #Items
    ORDER BY CASE Urgencia WHEN 'SIN_STOCK' THEN 0 WHEN 'CRITICO' THEN 1 ELSE 2 END, Descripcion;

    -- 2. Opciones de compra, solo de esos repuestos
    SELECT pr.IdRepuesto, pr.IdProveedor, p.RazonSocial AS Proveedor, pr.PrecioCompra AS Precio,
           p.CondicionIva, pr.CodigoProveedor
    FROM ProveedorRepuesto pr
    INNER JOIN #Items i ON i.IdRepuesto = pr.IdRepuesto
    INNER JOIN Proveedor p ON p.Id = pr.IdProveedor AND p.Activo = 1
    WHERE pr.Activo = 1 AND pr.PrecioCompra > 0
    ORDER BY pr.IdRepuesto, pr.PrecioCompra;

    -- 3. Bajo minimo pero ya pedidos
    ;WITH EnCamino AS (
        SELECT dp.IdRepuesto, SUM(dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada) AS Cant
        FROM DetallePedido dp INNER JOIN Pedido p ON p.Id = dp.IdPedido
        WHERE p.IdEstado = 1 GROUP BY dp.IdRepuesto
    )
    SELECT COUNT(*) AS CubiertosEnCamino
    FROM Repuesto r
    INNER JOIN Stock s ON s.IdRepuesto = r.Id
    INNER JOIN EnCamino ec ON ec.IdRepuesto = r.Id
    WHERE r.Activo = 1 AND s.StockMinimo > 0 AND s.Cantidad <= s.StockMinimo
      AND s.StockMinimo - s.Cantidad - ec.Cant <= 0;
END
GO

EXEC SP_Reposicion_Sugerida;
GO
