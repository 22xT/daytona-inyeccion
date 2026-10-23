USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   64 — SEGUIMIENTO DE ENCARGOS Y CONTADORES DEL MENU

   - "No retiró": se le avisó hace mas de N dias (parametro
     DiasRetiroEncargo, 7 por defecto) y no vino a buscarlo.
   - "Atrasado": paso la llegada estimada y todavia no hay stock
     (ya calculado en el script 63).
   - El menu suma: encargos para avisar, atrasados, no retiraron y
     pedidos en armado sin enviar.

   Nada de esto se guarda: se calcula en cada consulta.
   Requiere el script 63.
   ================================================================= */

IF NOT EXISTS (SELECT 1 FROM ParametroSistema WHERE Clave = 'DiasRetiroEncargo')
    INSERT INTO ParametroSistema (Clave, Valor, Descripcion)
    VALUES ('DiasRetiroEncargo', '7', 'Días desde el aviso para marcar un encargo como "no retiró".');
GO


/* -----------------------------------------------------------------
   1. Listado de encargos con "no retiró"
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Encargo_GetAll', 'P') IS NOT NULL DROP PROCEDURE SP_Encargo_GetAll;
GO
CREATE PROCEDURE SP_Encargo_GetAll
    @Abiertos BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @DiasRetiro INT = ISNULL(TRY_CAST((SELECT Valor FROM ParametroSistema WHERE Clave = 'DiasRetiroEncargo') AS INT), 7);

    SELECT e.Id, e.Fecha, e.Nombre, e.Telefono, e.IdCliente, e.Observacion, e.Estado,
           e.FechaAviso, e.IdVenta, e.FechaEntrega, e.FechaCancelacion, e.ResolucionSena,
           l.Total, l.Renglones, l.Primero,
           ISNULL((SELECT SUM(Monto) FROM EncargoSena es WHERE es.IdEncargo = e.Id), 0) AS Sena,
           CASE WHEN e.Estado IN ('ENTREGADO', 'CANCELADO') THEN NULL ELSE si.Disponibilidad END AS Disponibilidad,
           si.LlegadaEstimada,
           CASE WHEN e.Estado IN ('PENDIENTE', 'AVISADO') AND si.Disponibilidad <> 'EN_STOCK'
                     AND si.LlegadaEstimada < CAST(GETDATE() AS DATE) THEN 1 ELSE 0 END AS Atrasado,
           -- Se le aviso, esta en stock y no vino a buscarlo
           CASE WHEN e.Estado = 'AVISADO' AND si.Disponibilidad = 'EN_STOCK'
                     AND e.FechaAviso < DATEADD(DAY, -@DiasRetiro, GETDATE()) THEN 1 ELSE 0 END AS NoRetiro,
           DATEDIFF(DAY, e.Fecha, GETDATE()) AS Dias
    FROM Encargo e
    INNER JOIN (SELECT d.IdEncargo, SUM(d.Cantidad * d.PrecioPactado) AS Total, COUNT(*) AS Renglones,
                       MIN(r.Descripcion) AS Primero
                FROM EncargoDetalle d INNER JOIN Repuesto r ON r.Id = d.IdRepuesto
                GROUP BY d.IdEncargo) l ON l.IdEncargo = e.Id
    LEFT JOIN vw_EncargoSituacion si ON si.IdEncargo = e.Id
    WHERE (@Abiertos = 1 AND e.Estado IN ('PENDIENTE', 'AVISADO'))
       OR (@Abiertos = 0 AND e.Fecha >= DATEADD(DAY, -90, GETDATE()))
    ORDER BY CASE e.Estado WHEN 'PENDIENTE' THEN 1 WHEN 'AVISADO' THEN 2 ELSE 3 END, e.Fecha;

    SELECT ISNULL(-SUM(CASE WHEN m.Tipo = 'Ingreso' THEN m.Monto ELSE -m.Monto END), 0) AS SenasPendientes
    FROM MovimientoCuentaFinanciera m
    INNER JOIN CuentaFinanciera c ON c.Id = m.IdCuentaFinanciera
    WHERE c.Codigo = 'SENAS';
END
GO



/* -----------------------------------------------------------------
   2. Contadores del menu (mismas columnas que antes, mas las nuevas)
   ----------------------------------------------------------------- */
ALTER PROCEDURE SP_Indicadores_Menu
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @DiasRetiro INT = ISNULL(TRY_CAST((SELECT Valor FROM ParametroSistema WHERE Clave = 'DiasRetiroEncargo') AS INT), 7);

    SELECT
        (SELECT COUNT(*)
         FROM Repuesto r
         INNER JOIN Stock s ON s.IdRepuesto = r.Id
         WHERE r.Activo = 1
           AND s.Cantidad <= s.StockMinimo
           AND s.StockMinimo > 0)                       AS Reposicion,

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
EXEC SP_Encargo_GetAll;
GO
