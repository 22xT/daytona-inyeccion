USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   70 — EL GLOBO DE COMPRAS CUENTA LO MISMO QUE LA PANTALLA

   El numero rojo de Compras contaba todo repuesto con stock menor o
   IGUAL al minimo, aunque ya estuviera pedido. La reposicion sugerida,
   en cambio, solo muestra lo que falta pedir. Resultado: un 4 en el
   menu y la pantalla vacia.

   Ahora el globo usa la misma cuenta que la pantalla. Los pedidos en
   armado sin enviar se siguen sumando (hay que cargarlos en la web
   del proveedor), y se ven aparte en Compras > Pedidos.
   ================================================================= */

IF OBJECT_ID('SP_Indicadores_Menu', 'P') IS NOT NULL DROP PROCEDURE SP_Indicadores_Menu;
GO
CREATE PROCEDURE SP_Indicadores_Menu
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @DiasRetiro INT = ISNULL(TRY_CAST((SELECT Valor FROM ParametroSistema WHERE Clave = 'DiasRetiroEncargo') AS INT), 7);

    SELECT
        -- Mismo calculo que la pantalla de reposicion: minimo + encargado
        -- - stock - lo que ya esta pedido. Estar EN el minimo esta bien, y
        -- lo que ya se pidio no se vuelve a contar.
        (SELECT COUNT(*)
         FROM Repuesto r
         LEFT JOIN Stock s ON s.IdRepuesto = r.Id
         LEFT JOIN vw_StockReservado rv ON rv.IdRepuesto = r.Id
         OUTER APPLY (SELECT SUM(dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada) AS Cant
                      FROM DetallePedido dp INNER JOIN Pedido p ON p.Id = dp.IdPedido
                      WHERE p.IdEstado = 1 AND dp.IdRepuesto = r.Id
                        AND dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada > 0) ec
         WHERE r.Activo = 1
           AND ISNULL(s.StockMinimo, 0) + ISNULL(rv.Reservado, 0)
               - ISNULL(s.Cantidad, 0) - ISNULL(ec.Cant, 0) > 0) AS Reposicion,

        (SELECT COUNT(*)
         FROM Repuesto r
         INNER JOIN Stock s ON s.IdRepuesto = r.Id
         WHERE r.Activo = 1 AND s.Cantidad <= 0)        AS SinStock,

        (SELECT COUNT(*) FROM Pedido WHERE IdEstado = 1) AS PedidosPendientes,

        (SELECT COUNT(*) FROM (
            SELECT m.IdCliente
            FROM MovimientoCuentaCorriente m
            GROUP BY m.IdCliente
            HAVING SUM(m.Monto) > 0
         ) q)                                            AS ClientesConDeuda,

        (SELECT ISNULL(SUM(q.Saldo), 0) FROM (
            SELECT SUM(m.Monto) AS Saldo
            FROM MovimientoCuentaCorriente m
            GROUP BY m.IdCliente
            HAVING SUM(m.Monto) > 0
         ) q)                                            AS TotalACobrar,

        -- Nuevos
        (SELECT COUNT(*) FROM Pedido WHERE IdEstado = 1 AND FechaEnvio IS NULL) AS PedidosEnArmado,

        (SELECT COUNT(*) FROM Encargo e INNER JOIN vw_EncargoSituacion si ON si.IdEncargo = e.Id
         WHERE e.Estado = 'PENDIENTE' AND si.Disponibilidad = 'EN_STOCK')          AS EncargosParaAvisar,

        (SELECT COUNT(*) FROM Encargo e INNER JOIN vw_EncargoSituacion si ON si.IdEncargo = e.Id
         WHERE e.Estado IN ('PENDIENTE', 'AVISADO') AND si.Disponibilidad <> 'EN_STOCK'
           AND si.LlegadaEstimada < CAST(GETDATE() AS DATE))                       AS EncargosAtrasados,

        (SELECT COUNT(*) FROM Encargo e INNER JOIN vw_EncargoSituacion si ON si.IdEncargo = e.Id
         WHERE e.Estado = 'AVISADO' AND si.Disponibilidad = 'EN_STOCK'
           AND e.FechaAviso < DATEADD(DAY, -@DiasRetiro, GETDATE()))              AS EncargosNoRetiro;
END
GO

EXEC SP_Indicadores_Menu;
GO
