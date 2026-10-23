USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   66 — EQUIVALENTES CON STOCK

   Cuando un repuesto no tiene stock, el Buscador y la Venta muestran
   las otras marcas del mismo grupo que si tienen ("No hay SKF, hay
   Dayco: 3").

   Devuelve solo los repuestos que estan en algun grupo (son pocos),
   con su stock disponible: fisico menos lo apartado para encargos.
   Las pantallas lo cargan una vez y lo cruzan en el navegador.
   ================================================================= */

IF OBJECT_ID('SP_Equivalencia_Mapa', 'P') IS NOT NULL DROP PROCEDURE SP_Equivalencia_Mapa;
GO
CREATE PROCEDURE SP_Equivalencia_Mapa
AS
BEGIN
    SET NOCOUNT ON;

    SELECT r.Id AS IdRepuesto,
           r.IdGrupoEquivalencia AS IdGrupo,
           r.Codigo,
           r.Descripcion,
           r.MarcaFabricante AS Marca,
           r.PrecioDeVenta,
           ISNULL(s.Cantidad, 0) AS StockFisico,
           ISNULL(vr.Reservado, 0) AS Reservado,
           CASE WHEN ISNULL(s.Cantidad, 0) - ISNULL(vr.Reservado, 0) > 0
                THEN ISNULL(s.Cantidad, 0) - ISNULL(vr.Reservado, 0) ELSE 0 END AS StockDisponible
    FROM Repuesto r
    LEFT JOIN Stock s             ON s.IdRepuesto = r.Id
    LEFT JOIN vw_StockReservado vr ON vr.IdRepuesto = r.Id
    WHERE r.IdGrupoEquivalencia IS NOT NULL
      AND r.Activo = 1
    ORDER BY r.IdGrupoEquivalencia, StockDisponible DESC;
END
GO

EXEC SP_Equivalencia_Mapa;   -- vacio hasta que agrupes los primeros
GO
