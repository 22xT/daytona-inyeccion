USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   35 — REPORTES DE LA CATEDRA
   Tres procedimientos que responden a las devoluciones del profesor:
     1. Pronostico de ventas (en vez de "tendencia")
     2. Punto de equilibrio
     3. Comparacion de periodos para el dashboard
   ================================================================= */


/* -----------------------------------------------------------------
   1. PRONOSTICO DE VENTAS

   Regresion lineal simple sobre las ventas mensuales: se ajusta una
   recta a los ultimos N meses y se proyectan los M siguientes.

   POR QUE REGRESION Y NO ALGO MAS SOFISTICADO
   Con menos de un año de datos no hay estacionalidad detectable ni
   volumen para un modelo mejor. Una recta es honesta: muestra hacia
   donde va la serie y cuanto confiar en eso (R²). Cuando haya dos
   años de historia se puede revisar.

   Devuelve la serie historica y la proyectada en la misma tabla, con
   una columna que las distingue, y el R² para que la pantalla pueda
   avisar cuando la proyeccion es debil.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Reporte_Pronostico', 'P') IS NOT NULL DROP PROCEDURE SP_Reporte_Pronostico;
GO

CREATE PROCEDURE SP_Reporte_Pronostico
    @MesesHistoria  INT = 6,    -- cuantos meses atras se miran
    @MesesProyectar INT = 3     -- cuantos hacia adelante
AS
BEGIN
    SET NOCOUNT ON;

    IF @MesesHistoria < 3 SET @MesesHistoria = 3;
    IF @MesesProyectar < 1 SET @MesesProyectar = 1;
    IF @MesesProyectar > 12 SET @MesesProyectar = 12;

    -- Primer dia del mes actual, y desde donde arranca la historia
    DECLARE @mesActual DATE = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1);
    DECLARE @desde DATE = DATEADD(MONTH, -(@MesesHistoria - 1), @mesActual);

    /* Serie mensual completa: incluye meses sin ventas como cero,
       porque un mes vacio es informacion (no vendimos), no un hueco. */
    ;WITH Meses AS (
        SELECT @desde AS Mes, 1 AS N
        UNION ALL
        SELECT DATEADD(MONTH, 1, Mes), N + 1 FROM Meses WHERE N < @MesesHistoria
    ),
    Ventas AS (
        SELECT DATEFROMPARTS(YEAR(v.Fecha), MONTH(v.Fecha), 1) AS Mes,
               SUM(v.Total) AS Total, COUNT(*) AS Cantidad
        FROM Venta v
        WHERE v.IdEstadoVenta = 1 AND v.Fecha >= @desde
        GROUP BY DATEFROMPARTS(YEAR(v.Fecha), MONTH(v.Fecha), 1)
    ),
    Serie AS (
        SELECT m.N AS X, m.Mes, ISNULL(vt.Total, 0) AS Y, ISNULL(vt.Cantidad, 0) AS Cantidad
        FROM Meses m LEFT JOIN Ventas vt ON vt.Mes = m.Mes
    ),
    /* Minimos cuadrados: pendiente y ordenada al origen */
    Stats AS (
        SELECT
            COUNT(*)              AS n,
            SUM(X)                AS sx,
            SUM(Y)                AS sy,
            SUM(X * X)            AS sxx,
            SUM(X * Y)            AS sxy,
            SUM(Y * Y)            AS syy
        FROM Serie
    ),
    Coef AS (
        SELECT
            CASE WHEN n * sxx - sx * sx = 0 THEN 0
                 ELSE (n * sxy - sx * sy) / (n * sxx - sx * sx) END AS Pendiente,
            CASE WHEN n = 0 THEN 0
                 ELSE (sy - (CASE WHEN n * sxx - sx * sx = 0 THEN 0
                                  ELSE (n * sxy - sx * sy) / (n * sxx - sx * sx) END) * sx) / n END AS Ordenada,
            -- R²: cuanto de la variacion explica la recta. 1 = perfecto, 0 = nada.
            CASE WHEN (n * sxx - sx * sx) * (n * syy - sy * sy) = 0 THEN 0
                 ELSE POWER(n * sxy - sx * sy, 2) / ((n * sxx - sx * sx) * (n * syy - sy * sy)) END AS R2,
            n AS MesesConDatos
        FROM Stats
    ),
    Proyeccion AS (
        SELECT @MesesHistoria + 1 AS X, DATEADD(MONTH, @MesesHistoria, @desde) AS Mes
        UNION ALL
        SELECT X + 1, DATEADD(MONTH, 1, Mes) FROM Proyeccion WHERE X < @MesesHistoria + @MesesProyectar
    )
    SELECT
        s.Mes,
        FORMAT(s.Mes, 'MMM yy', 'es-AR') AS Etiqueta,
        CAST(s.Y AS DECIMAL(12,2))       AS Total,
        s.Cantidad,
        'Historico'                       AS Tipo,
        CAST(c.Pendiente AS DECIMAL(12,2)) AS Pendiente,
        CAST(c.R2 AS DECIMAL(5,3))        AS R2,
        c.MesesConDatos
    FROM Serie s CROSS JOIN Coef c

    UNION ALL

    SELECT
        p.Mes,
        FORMAT(p.Mes, 'MMM yy', 'es-AR'),
        -- Una proyeccion negativa no tiene sentido: se corta en cero
        CAST(CASE WHEN c.Ordenada + c.Pendiente * p.X < 0 THEN 0
                  ELSE c.Ordenada + c.Pendiente * p.X END AS DECIMAL(12,2)),
        NULL,
        'Pronostico',
        CAST(c.Pendiente AS DECIMAL(12,2)),
        CAST(c.R2 AS DECIMAL(5,3)),
        c.MesesConDatos
    FROM Proyeccion p CROSS JOIN Coef c
    ORDER BY Mes
    OPTION (MAXRECURSION 24);
END
GO


/* -----------------------------------------------------------------
   2. PUNTO DE EQUILIBRIO

   Cuanto hay que vender por mes para no perder plata.

     Contribucion marginal = Ventas - Costo de lo vendido
     Ratio de contribucion = Contribucion / Ventas
     Punto de equilibrio   = Costos fijos / Ratio de contribucion

   El costo de lo vendido sale del costo historico que se guarda en
   cada renglon (Sprint 10). Sin eso, se calcularia con el costo de
   hoy, que ya cambio.

   Los costos fijos mensuales (alquiler, sueldos, servicios) son un
   parametro del sistema: el negocio los conoce, el sistema no.
   ----------------------------------------------------------------- */

-- Parametro de costos fijos, si no existe
IF NOT EXISTS (SELECT 1 FROM ParametroSistema WHERE Clave = 'CostosFijosMensuales')
    INSERT INTO ParametroSistema (Clave, Valor, Descripcion)
    VALUES ('CostosFijosMensuales', '0',
            'Suma mensual de alquiler, sueldos, servicios e impuestos fijos. Para el punto de equilibrio.');
GO

IF OBJECT_ID('SP_Reporte_PuntoEquilibrio', 'P') IS NOT NULL DROP PROCEDURE SP_Reporte_PuntoEquilibrio;
GO

CREATE PROCEDURE SP_Reporte_PuntoEquilibrio
    @Desde DATE = NULL,
    @Hasta DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Por defecto, el mes actual
    IF @Desde IS NULL SET @Desde = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1);
    IF @Hasta IS NULL SET @Hasta = CAST(GETDATE() AS DATE);

    DECLARE @CostosFijos DECIMAL(12,2) =
        ISNULL(TRY_CAST((SELECT Valor FROM ParametroSistema WHERE Clave = 'CostosFijosMensuales')
                        AS DECIMAL(12,2)), 0);

    -- Cuantos meses abarca el periodo, para prorratear los costos fijos
    DECLARE @Meses DECIMAL(6,2) = DATEDIFF(DAY, @Desde, @Hasta) / 30.0;
    IF @Meses < 0.1 SET @Meses = 0.1;
    DECLARE @CostosFijosPeriodo DECIMAL(12,2) = @CostosFijos * @Meses;

    DECLARE @Ventas DECIMAL(12,2), @CostoVendido DECIMAL(12,2), @Unidades INT;

    SELECT
        @Ventas       = ISNULL(SUM(dv.Cantidad * dv.PrecioUnitario * (1 - ISNULL(v.PorcentajeDescuento, 0) / 100.0)), 0),
        @CostoVendido = ISNULL(SUM(dv.Cantidad * ISNULL(dv.CostoUnitario, 0)), 0),
        @Unidades     = ISNULL(SUM(dv.Cantidad), 0)
    FROM DetalleVenta dv
    INNER JOIN Venta v ON v.Id = dv.IdVenta
    WHERE v.IdEstadoVenta = 1
      AND CAST(v.Fecha AS DATE) BETWEEN @Desde AND @Hasta;

    DECLARE @Contribucion DECIMAL(12,2) = @Ventas - @CostoVendido;
    DECLARE @Ratio DECIMAL(8,4) = CASE WHEN @Ventas > 0 THEN @Contribucion / @Ventas ELSE 0 END;
    DECLARE @PuntoEquilibrio DECIMAL(12,2) = CASE WHEN @Ratio > 0 THEN @CostosFijosPeriodo / @Ratio ELSE NULL END;

    SELECT
        @Desde                       AS Desde,
        @Hasta                       AS Hasta,
        @Ventas                      AS Ventas,
        @CostoVendido                AS CostoVendido,
        @Contribucion                AS ContribucionMarginal,
        CAST(@Ratio * 100 AS DECIMAL(6,2)) AS RatioContribucionPorc,
        @CostosFijos                 AS CostosFijosMensuales,
        @CostosFijosPeriodo          AS CostosFijosPeriodo,
        @PuntoEquilibrio             AS PuntoEquilibrio,
        CASE WHEN @PuntoEquilibrio IS NULL THEN NULL
             ELSE @Ventas - @PuntoEquilibrio END AS MargenSobreEquilibrio,
        CASE WHEN @PuntoEquilibrio IS NULL THEN 'Sin datos'
             WHEN @Ventas >= @PuntoEquilibrio THEN 'Cubierto'
             ELSE 'No cubierto' END AS Estado,
        -- Cuanto falta vender por dia para llegar, si no se llego
        CASE WHEN @PuntoEquilibrio IS NULL OR @Ventas >= @PuntoEquilibrio THEN 0
             ELSE (@PuntoEquilibrio - @Ventas) /
                  NULLIF(DATEDIFF(DAY, @Hasta, EOMONTH(@Hasta)), 0) END AS FaltaPorDia,
        @Unidades                    AS UnidadesVendidas,
        -- Sin costos fijos cargados el reporte no dice nada util
        CASE WHEN @CostosFijos = 0 THEN 1 ELSE 0 END AS FaltaConfigurarCostosFijos;
END
GO


/* -----------------------------------------------------------------
   3. COMPARACION DE PERIODOS

   El dashboard muestra un periodo y lo compara con el anterior de la
   misma duracion. "Este mes vendiste $X, un 12% mas que el mes
   pasado" dice mas que "$X" solo.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Dashboard_Periodo', 'P') IS NOT NULL DROP PROCEDURE SP_Dashboard_Periodo;
GO

CREATE PROCEDURE SP_Dashboard_Periodo
    @Desde DATE = NULL,
    @Hasta DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Desde IS NULL SET @Desde = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1);
    IF @Hasta IS NULL SET @Hasta = CAST(GETDATE() AS DATE);

    -- Periodo anterior: misma cantidad de dias, terminando el dia antes
    DECLARE @dias INT = DATEDIFF(DAY, @Desde, @Hasta) + 1;
    DECLARE @antDesde DATE = DATEADD(DAY, -@dias, @Desde);
    DECLARE @antHasta DATE = DATEADD(DAY, -1, @Desde);

    ;WITH Actual AS (
        SELECT
            ISNULL(SUM(v.Total), 0) AS Ventas,
            COUNT(*) AS Operaciones,
            ISNULL(AVG(v.Total), 0) AS TicketPromedio,
            (SELECT ISNULL(SUM(dv.Cantidad), 0) FROM DetalleVenta dv
             INNER JOIN Venta v2 ON v2.Id = dv.IdVenta
             WHERE v2.IdEstadoVenta = 1 AND CAST(v2.Fecha AS DATE) BETWEEN @Desde AND @Hasta) AS Unidades,
            (SELECT ISNULL(SUM(dv.Cantidad * (dv.PrecioUnitario - ISNULL(dv.CostoUnitario, 0))), 0)
             FROM DetalleVenta dv INNER JOIN Venta v2 ON v2.Id = dv.IdVenta
             WHERE v2.IdEstadoVenta = 1 AND CAST(v2.Fecha AS DATE) BETWEEN @Desde AND @Hasta) AS Ganancia
        FROM Venta v
        WHERE v.IdEstadoVenta = 1 AND CAST(v.Fecha AS DATE) BETWEEN @Desde AND @Hasta
    ),
    Anterior AS (
        SELECT
            ISNULL(SUM(v.Total), 0) AS Ventas,
            COUNT(*) AS Operaciones,
            ISNULL(AVG(v.Total), 0) AS TicketPromedio,
            (SELECT ISNULL(SUM(dv.Cantidad), 0) FROM DetalleVenta dv
             INNER JOIN Venta v2 ON v2.Id = dv.IdVenta
             WHERE v2.IdEstadoVenta = 1 AND CAST(v2.Fecha AS DATE) BETWEEN @antDesde AND @antHasta) AS Unidades,
            (SELECT ISNULL(SUM(dv.Cantidad * (dv.PrecioUnitario - ISNULL(dv.CostoUnitario, 0))), 0)
             FROM DetalleVenta dv INNER JOIN Venta v2 ON v2.Id = dv.IdVenta
             WHERE v2.IdEstadoVenta = 1 AND CAST(v2.Fecha AS DATE) BETWEEN @antDesde AND @antHasta) AS Ganancia
        FROM Venta v
        WHERE v.IdEstadoVenta = 1 AND CAST(v.Fecha AS DATE) BETWEEN @antDesde AND @antHasta
    )
    SELECT
        @Desde AS Desde, @Hasta AS Hasta, @antDesde AS AnteriorDesde, @antHasta AS AnteriorHasta,

        a.Ventas, an.Ventas AS VentasAnterior,
        CASE WHEN an.Ventas = 0 THEN NULL ELSE CAST((a.Ventas - an.Ventas) / an.Ventas * 100 AS DECIMAL(6,1)) END AS VentasVariacion,

        a.Operaciones, an.Operaciones AS OperacionesAnterior,
        CASE WHEN an.Operaciones = 0 THEN NULL ELSE CAST((a.Operaciones - an.Operaciones) * 100.0 / an.Operaciones AS DECIMAL(6,1)) END AS OperacionesVariacion,

        CAST(a.TicketPromedio AS DECIMAL(12,2)) AS TicketPromedio,
        CAST(an.TicketPromedio AS DECIMAL(12,2)) AS TicketPromedioAnterior,
        CASE WHEN an.TicketPromedio = 0 THEN NULL ELSE CAST((a.TicketPromedio - an.TicketPromedio) / an.TicketPromedio * 100 AS DECIMAL(6,1)) END AS TicketVariacion,

        a.Unidades, an.Unidades AS UnidadesAnterior,
        CASE WHEN an.Unidades = 0 THEN NULL ELSE CAST((a.Unidades - an.Unidades) * 100.0 / an.Unidades AS DECIMAL(6,1)) END AS UnidadesVariacion,

        CAST(a.Ganancia AS DECIMAL(12,2)) AS Ganancia,
        CAST(an.Ganancia AS DECIMAL(12,2)) AS GananciaAnterior,
        CASE WHEN an.Ganancia = 0 THEN NULL ELSE CAST((a.Ganancia - an.Ganancia) / an.Ganancia * 100 AS DECIMAL(6,1)) END AS GananciaVariacion
    FROM Actual a CROSS JOIN Anterior an;
END
GO


/* -----------------------------------------------------------------
   PRUEBAS
   ----------------------------------------------------------------- */
EXEC SP_Reporte_Pronostico @MesesHistoria = 6, @MesesProyectar = 3;
GO
EXEC SP_Reporte_PuntoEquilibrio;
GO
EXEC SP_Dashboard_Periodo;
GO

-- Para que el punto de equilibrio diga algo, cargar los costos fijos reales:
-- UPDATE ParametroSistema SET Valor = '850000' WHERE Clave = 'CostosFijosMensuales';
