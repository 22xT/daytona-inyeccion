USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   21 — Indicador de reposicion e imagen del repuesto
   ================================================================= */

/* -----------------------------------------------------------------
   1. Campo de imagen

   Las miniaturas ya estan maquetadas en CargarVenta y en PedidoNuevo:
   leen Imagen, UrlImagen o Foto, y mientras no exista muestran un
   recuadro con icono. Con la columna creada empiezan a funcionar sin
   tocar el frontend.

   Se guarda la RUTA o la URL, no la imagen. Meter archivos binarios
   en la base la infla y complica los backups; para un catalogo de
   repuestos alcanza con apuntar al archivo.
   ----------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('Repuesto') AND name = 'Imagen')
    ALTER TABLE Repuesto ADD Imagen VARCHAR(255) NULL;
GO


/* -----------------------------------------------------------------
   2. Resumen para el indicador del menu

   Devuelve una sola fila con los contadores que se muestran como
   globo en la barra superior. Es una consulta liviana porque se
   ejecuta en cada carga de pantalla.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Indicadores_Menu', 'P') IS NOT NULL
    DROP PROCEDURE SP_Indicadores_Menu;
GO

CREATE PROCEDURE SP_Indicadores_Menu
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        -- Repuestos que hay que reponer
        (SELECT COUNT(*)
         FROM Repuesto r
         INNER JOIN Stock s ON s.IdRepuesto = r.Id
         WHERE r.Activo = 1
           AND s.Cantidad <= s.StockMinimo
           AND s.StockMinimo > 0)                       AS Reposicion,

        -- De esos, los que ya se quedaron sin nada
        (SELECT COUNT(*)
         FROM Repuesto r
         INNER JOIN Stock s ON s.IdRepuesto = r.Id
         WHERE r.Activo = 1 AND s.Cantidad <= 0)        AS SinStock,

        -- Pedidos que siguen esperando (estado 1 = Pendiente)
        (SELECT COUNT(*) FROM Pedido WHERE IdEstado = 1) AS PedidosPendientes,

        -- Clientes que deben plata
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
         ) q)                                            AS TotalACobrar;
END
GO


/* -----------------------------------------------------------------
   3. VERIFICACION
   ----------------------------------------------------------------- */
EXEC SP_Indicadores_Menu;

SELECT name AS ColumnaImagen FROM sys.columns
WHERE object_id = OBJECT_ID('Repuesto') AND name = 'Imagen';
GO
