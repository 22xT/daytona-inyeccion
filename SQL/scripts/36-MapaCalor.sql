USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   36 — MAPA DE CALOR: DIA DE LA SEMANA x HORA DEL DIA

   El mapa anterior cruzaba dia de la semana por mes: con pocos meses
   quedaba vacio y no respondia nada util.

   Este cruza dia por hora y cuenta OPERACIONES, no importe. Responde
   "cuando se llena el mostrador", que sirve para decidir horarios y
   personal. Se llena con pocas semanas de datos.

   El importe va como dato secundario, para el tooltip.
   ================================================================= */

IF OBJECT_ID('SP_Dashboard_MapaCalor', 'P') IS NOT NULL DROP PROCEDURE SP_Dashboard_MapaCalor;
GO

CREATE PROCEDURE SP_Dashboard_MapaCalor
    @Desde DATE = NULL,
    @Hasta DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Por defecto, las ultimas 8 semanas: suficiente para que el patron
    -- semanal se vea y reciente para que sea vigente
    IF @Hasta IS NULL SET @Hasta = CAST(GETDATE() AS DATE);
    IF @Desde IS NULL SET @Desde = DATEADD(WEEK, -8, @Hasta);

    SELECT
        -- 1 = lunes ... 7 = domingo, independiente de la configuracion del servidor
        ((DATEPART(WEEKDAY, v.Fecha) + @@DATEFIRST - 2) % 7) + 1 AS DiaSemana,
        DATEPART(HOUR, v.Fecha)  AS Hora,
        COUNT(*)                 AS Operaciones,
        SUM(v.Total)             AS Total
    FROM Venta v
    WHERE v.IdEstadoVenta = 1
      AND CAST(v.Fecha AS DATE) BETWEEN @Desde AND @Hasta
    GROUP BY ((DATEPART(WEEKDAY, v.Fecha) + @@DATEFIRST - 2) % 7) + 1,
             DATEPART(HOUR, v.Fecha)
    ORDER BY DiaSemana, Hora;
END
GO

EXEC SP_Dashboard_MapaCalor;
GO
