USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   58 — LOS REPORTES RESTAN LAS DEVOLUCIONES

   Hasta ahora, si un cliente devolvia algo, la venta seguia sumando
   completa en el pronostico, el punto de equilibrio y la comparacion
   de periodos. Desde aca:

     Ventas netas   = ventas - notas de credito + notas de debito
     Costo vendido  = costo de lo vendido - costo de lo que volvio al stock
     Unidades netas = unidades vendidas - unidades devueltas

   CRITERIOS
   - La nota cuenta en la FECHA DE LA NOTA, no en la de la venta. Igual
     que la caja: una devolucion de hoy no cambia lo que se informo el
     mes pasado.
   - Solo el repuesto que vuelve al stock descuenta costo. El que vino
     fallado (ReingresaStock = 0) se perdio: su costo sigue siendo costo,
     y por eso la devolucion baja la ganancia por el precio entero.
   - La nota de debito suma a las ventas y no tiene costo: es un cargo
     posterior (diferencia de precio, por ejemplo).

   Abarca pronostico, punto de equilibrio, comparacion de periodos,
   reporte de ventas (resumen y por dia) y panel principal.
   Las columnas que ya usaban las pantallas no cambian de nombre. Se
   agregan columnas nuevas con el detalle (bruto, NC, ND).

   Requiere el script 49 (notas a clientes).
   ================================================================= */


/* -----------------------------------------------------------------
   1. Lo que cada nota le hace a los reportes, una fila por nota
   ----------------------------------------------------------------- */
IF OBJECT_ID('vw_NotaClienteImpacto', 'V') IS NOT NULL DROP VIEW vw_NotaClienteImpacto;
GO
CREATE VIEW vw_NotaClienteImpacto
AS
SELECT
    n.Id,
    n.Tipo,
    CAST(n.Fecha AS DATE)                                   AS Fecha,
    n.Fecha                                                 AS FechaHora,
    CASE WHEN n.Tipo = 'NC' THEN n.Importe ELSE 0 END       AS NotaCredito,
    CASE WHEN n.Tipo = 'ND' THEN n.Importe ELSE 0 END       AS NotaDebito,
    -- Cuanto cambian las ventas: la NC resta, la ND suma
    CASE WHEN n.Tipo = 'NC' THEN -n.Importe ELSE n.Importe END AS AjusteVentas,
    -- Costo de lo que volvio al stock, al costo de la venta original
    ISNULL((SELECT SUM(d.Cantidad * ISNULL(c.Costo, 0))
            FROM NotaClienteDetalle d
            OUTER APPLY (SELECT AVG(dv.CostoUnitario) AS Costo
                         FROM DetalleVenta dv
                         WHERE dv.IdVenta = n.IdVenta AND dv.IdRepuesto = d.IdRepuesto) c
            WHERE d.IdNota = n.Id AND d.ReingresaStock = 1), 0) AS CostoDevuelto,
    ISNULL((SELECT SUM(d.Cantidad) FROM NotaClienteDetalle d WHERE d.IdNota = n.Id), 0) AS UnidadesDevueltas
FROM NotaCliente n;
GO


/* -----------------------------------------------------------------
   2. Pronostico: la serie mensual pasa a ser neta
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Reporte_Pronostico', 'P') IS NOT NULL DROP PROCEDURE SP_Reporte_Pronostico;
GO
CREATE PROCEDURE SP_Reporte_Pronostico
    @MesesHistoria  INT = 6,
    @MesesProyectar INT = 3
AS
BEGIN
    SET NOCOUNT ON;

    IF @MesesHistoria < 3 SET @MesesHistoria = 3;
    IF @MesesProyectar < 1 SET @MesesProyectar = 1;
    IF @MesesProyectar > 12 SET @MesesProyectar = 12;

    DECLARE @mesActual DATE = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1);
    DECLARE @desde DATE = DATEADD(MONTH, -(@MesesHistoria - 1), @mesActual);

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
    Notas AS (
        SELECT DATEFROMPARTS(YEAR(n.Fecha), MONTH(n.Fecha), 1) AS Mes,
               SUM(n.AjusteVentas) AS Ajuste
        FROM vw_NotaClienteImpacto n
        WHERE n.Fecha >= @desde
        GROUP BY DATEFROMPARTS(YEAR(n.Fecha), MONTH(n.Fecha), 1)
    ),
    Serie AS (
        SELECT m.N AS X, m.Mes,
               CAST(ISNULL(vt.Total, 0) + ISNULL(nt.Ajuste, 0) AS FLOAT) AS Y,
               ISNULL(vt.Cantidad, 0) AS Cantidad
        FROM Meses m
        LEFT JOIN Ventas vt ON vt.Mes = m.Mes
        LEFT JOIN Notas  nt ON nt.Mes = m.Mes
    ),
    Stats AS (
        SELECT COUNT(*) AS n, SUM(CAST(X AS FLOAT)) AS sx, SUM(Y) AS sy,
               SUM(CAST(X * X AS FLOAT)) AS sxx, SUM(X * Y) AS sxy, SUM(Y * Y) AS syy
        FROM Serie
    ),
    Coef AS (
        SELECT
            CASE WHEN n * sxx - sx * sx = 0 THEN 0
                 ELSE (n * sxy - sx * sy) / (n * sxx - sx * sx) END AS Pendiente,
            CASE WHEN n = 0 THEN 0
                 ELSE (sy - (CASE WHEN n * sxx - sx * sx = 0 THEN 0
                                  ELSE (n * sxy - sx * sy) / (n * sxx - sx * sx) END) * sx) / n END AS Ordenada,
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
        FORMAT(s.Mes, 'MMM yy', 'es-AR')   AS Etiqueta,
        CAST(s.Y AS DECIMAL(12,2))         AS Total,
        s.Cantidad,
        'Historico'                        AS Tipo,
        CAST(c.Pendiente AS DECIMAL(12,2)) AS Pendiente,
        CAST(c.R2 AS DECIMAL(5,3))         AS R2,
        c.MesesConDatos
    FROM Serie s CROSS JOIN Coef c

    UNION ALL

    SELECT
        p.Mes,
        FORMAT(p.Mes, 'MMM yy', 'es-AR'),
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
   3. Punto de equilibrio con ventas y costo netos
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Reporte_PuntoEquilibrio', 'P') IS NOT NULL DROP PROCEDURE SP_Reporte_PuntoEquilibrio;
GO
CREATE PROCEDURE SP_Reporte_PuntoEquilibrio
    @Desde DATE = NULL,
    @Hasta DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Desde IS NULL SET @Desde = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1);
    IF @Hasta IS NULL SET @Hasta = CAST(GETDATE() AS DATE);

    DECLARE @CostosFijos DECIMAL(12,2) =
        ISNULL(TRY_CAST((SELECT Valor FROM ParametroSistema WHERE Clave = 'CostosFijosMensuales')
                        AS DECIMAL(12,2)), 0);

    DECLARE @Meses DECIMAL(6,2) = DATEDIFF(DAY, @Desde, @Hasta) / 30.0;
    IF @Meses < 0.1 SET @Meses = 0.1;
    DECLARE @CostosFijosPeriodo DECIMAL(12,2) = @CostosFijos * @Meses;

    DECLARE @VentasBrutas DECIMAL(12,2), @CostoBruto DECIMAL(12,2), @UnidadesBrutas INT;

    SELECT
        @VentasBrutas   = ISNULL(SUM(dv.Cantidad * dv.PrecioUnitario * (1 - ISNULL(v.PorcentajeDescuento, 0) / 100.0)), 0),
        @CostoBruto     = ISNULL(SUM(dv.Cantidad * ISNULL(dv.CostoUnitario, 0)), 0),
        @UnidadesBrutas = ISNULL(SUM(dv.Cantidad), 0)
    FROM DetalleVenta dv
    INNER JOIN Venta v ON v.Id = dv.IdVenta
    WHERE v.IdEstadoVenta = 1
      AND CAST(v.Fecha AS DATE) BETWEEN @Desde AND @Hasta;

    DECLARE @NC DECIMAL(12,2), @ND DECIMAL(12,2), @CostoDevuelto DECIMAL(12,2), @UnidadesDevueltas INT;
    SELECT @NC = ISNULL(SUM(NotaCredito), 0), @ND = ISNULL(SUM(NotaDebito), 0),
           @CostoDevuelto = ISNULL(SUM(CostoDevuelto), 0), @UnidadesDevueltas = ISNULL(SUM(UnidadesDevueltas), 0)
    FROM vw_NotaClienteImpacto
    WHERE Fecha BETWEEN @Desde AND @Hasta;

    DECLARE @Ventas DECIMAL(12,2)       = @VentasBrutas - @NC + @ND;
    DECLARE @CostoVendido DECIMAL(12,2) = @CostoBruto - @CostoDevuelto;
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
        CASE WHEN @PuntoEquilibrio IS NULL OR @Ventas >= @PuntoEquilibrio THEN 0
             ELSE (@PuntoEquilibrio - @Ventas) /
                  NULLIF(DATEDIFF(DAY, @Hasta, EOMONTH(@Hasta)), 0) END AS FaltaPorDia,
        @UnidadesBrutas - @UnidadesDevueltas AS UnidadesVendidas,
        CASE WHEN @CostosFijos = 0 THEN 1 ELSE 0 END AS FaltaConfigurarCostosFijos,
        -- Detalle nuevo
        @VentasBrutas                AS VentasBrutas,
        @NC                          AS NotasCredito,
        @ND                          AS NotasDebito,
        @CostoDevuelto               AS CostoDevuelto;
END
GO


/* -----------------------------------------------------------------
   4. Comparacion de periodos del panel, neta
   Ademas: la ganancia ahora respeta el descuento de la venta, igual
   que el punto de equilibrio. Antes se calculaba sobre el precio de
   lista del renglon y daba de mas en las ventas con descuento.
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

    DECLARE @dias INT = DATEDIFF(DAY, @Desde, @Hasta) + 1;
    DECLARE @antDesde DATE = DATEADD(DAY, -@dias, @Desde);
    DECLARE @antHasta DATE = DATEADD(DAY, -1, @Desde);

    ;WITH Periodos AS (
        SELECT 'A' AS P, @Desde AS D, @Hasta AS H
        UNION ALL
        SELECT 'B', @antDesde, @antHasta
    ),
    Calc AS (
        SELECT
            p.P,
            -- Ventas brutas y cantidad de operaciones
            (SELECT ISNULL(SUM(v.Total), 0) FROM Venta v
             WHERE v.IdEstadoVenta = 1 AND CAST(v.Fecha AS DATE) BETWEEN p.D AND p.H) AS VentasBrutas,
            (SELECT COUNT(*) FROM Venta v
             WHERE v.IdEstadoVenta = 1 AND CAST(v.Fecha AS DATE) BETWEEN p.D AND p.H) AS Operaciones,
            (SELECT ISNULL(SUM(dv.Cantidad), 0) FROM DetalleVenta dv
             INNER JOIN Venta v ON v.Id = dv.IdVenta
             WHERE v.IdEstadoVenta = 1 AND CAST(v.Fecha AS DATE) BETWEEN p.D AND p.H) AS UnidadesBrutas,
            (SELECT ISNULL(SUM(dv.Cantidad * (dv.PrecioUnitario * (1 - ISNULL(v.PorcentajeDescuento, 0) / 100.0)
                                              - ISNULL(dv.CostoUnitario, 0))), 0)
             FROM DetalleVenta dv INNER JOIN Venta v ON v.Id = dv.IdVenta
             WHERE v.IdEstadoVenta = 1 AND CAST(v.Fecha AS DATE) BETWEEN p.D AND p.H) AS GananciaBruta,
            -- Notas del periodo
            (SELECT ISNULL(SUM(n.NotaCredito), 0) FROM vw_NotaClienteImpacto n WHERE n.Fecha BETWEEN p.D AND p.H) AS NC,
            (SELECT ISNULL(SUM(n.NotaDebito), 0)  FROM vw_NotaClienteImpacto n WHERE n.Fecha BETWEEN p.D AND p.H) AS ND,
            (SELECT ISNULL(SUM(n.CostoDevuelto), 0) FROM vw_NotaClienteImpacto n WHERE n.Fecha BETWEEN p.D AND p.H) AS CostoDevuelto,
            (SELECT ISNULL(SUM(n.UnidadesDevueltas), 0) FROM vw_NotaClienteImpacto n WHERE n.Fecha BETWEEN p.D AND p.H) AS UnidadesDevueltas
        FROM Periodos p
    ),
    Neto AS (
        SELECT
            P,
            VentasBrutas - NC + ND                              AS Ventas,
            Operaciones,
            CASE WHEN Operaciones = 0 THEN 0
                 ELSE (VentasBrutas - NC + ND) / Operaciones END AS TicketPromedio,
            UnidadesBrutas - UnidadesDevueltas                  AS Unidades,
            -- La NC resta lo cobrado y devuelve el costo de lo que volvio al stock
            GananciaBruta - NC + CostoDevuelto + ND             AS Ganancia,
            NC, ND
        FROM Calc
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
        CASE WHEN an.Ganancia = 0 THEN NULL ELSE CAST((a.Ganancia - an.Ganancia) / an.Ganancia * 100 AS DECIMAL(6,1)) END AS GananciaVariacion,

        -- Detalle nuevo
        a.NC AS NotasCredito, a.ND AS NotasDebito
    FROM Neto a CROSS JOIN Neto an
    WHERE a.P = 'A' AND an.P = 'B';
END
GO


/* -----------------------------------------------------------------
   5. Reporte de ventas: resumen
   TotalFacturado pasa a ser neto (la nota de credito tambien es un
   comprobante que baja lo facturado). Se agregan las columnas con el
   detalle para mostrarlo debajo.
   ----------------------------------------------------------------- */
ALTER PROCEDURE [dbo].[SP_Reporte_VentasResumen]
    @Desde DATE,
    @Hasta DATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Bruto DECIMAL(12,2), @Cantidad INT;
    SELECT @Bruto = ISNULL(SUM(v.Total), 0), @Cantidad = COUNT(*)
    FROM Venta v
    WHERE v.IdEstadoVenta = 1 AND CAST(v.Fecha AS DATE) BETWEEN @Desde AND @Hasta;

    DECLARE @NC DECIMAL(12,2), @ND DECIMAL(12,2), @CantNC INT;
    SELECT @NC = ISNULL(SUM(NotaCredito), 0), @ND = ISNULL(SUM(NotaDebito), 0),
           @CantNC = ISNULL(SUM(CASE WHEN Tipo = 'NC' THEN 1 ELSE 0 END), 0)
    FROM vw_NotaClienteImpacto
    WHERE Fecha BETWEEN @Desde AND @Hasta;

    SELECT
        @Bruto - @NC + @ND                                          AS TotalFacturado,
        @Cantidad                                                   AS CantidadVentas,
        CASE WHEN @Cantidad = 0 THEN 0
             ELSE CAST((@Bruto - @NC + @ND) / @Cantidad AS DECIMAL(12,2)) END AS TicketPromedio,
        (SELECT COUNT(*) FROM Venta a
         WHERE a.IdEstadoVenta = 2
           AND CAST(a.FechaAnulacion AS DATE) BETWEEN @Desde AND @Hasta) AS VentasAnuladas,
        @Bruto                                                      AS VentasBrutas,
        @NC                                                         AS NotasCredito,
        @ND                                                         AS NotasDebito,
        @CantNC                                                     AS CantidadNotasCredito;
END
GO


/* -----------------------------------------------------------------
   6. Reporte de ventas: detalle por dia
   Un dia con devoluciones y sin ventas tambien aparece.
   ----------------------------------------------------------------- */
ALTER PROCEDURE [dbo].[SP_Reporte_VentasPeriodo]
    @Desde DATE,
    @Hasta DATE
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Ventas AS (
        SELECT CAST(v.Fecha AS DATE) AS Dia, COUNT(*) AS Cantidad, SUM(v.Total) AS Total
        FROM Venta v
        WHERE v.IdEstadoVenta = 1 AND CAST(v.Fecha AS DATE) BETWEEN @Desde AND @Hasta
        GROUP BY CAST(v.Fecha AS DATE)
    ),
    Notas AS (
        SELECT Fecha AS Dia, SUM(NotaCredito) AS NC, SUM(NotaDebito) AS ND
        FROM vw_NotaClienteImpacto
        WHERE Fecha BETWEEN @Desde AND @Hasta
        GROUP BY Fecha
    )
    SELECT
        ISNULL(v.Dia, n.Dia)                                  AS Dia,
        ISNULL(v.Cantidad, 0)                                 AS CantidadVentas,
        ISNULL(v.Total, 0) - ISNULL(n.NC, 0) + ISNULL(n.ND, 0) AS TotalDia,
        ISNULL(v.Total, 0)                                    AS VentasBrutas,
        ISNULL(n.NC, 0)                                       AS NotasCredito,
        ISNULL(n.ND, 0)                                       AS NotasDebito
    FROM Ventas v
    FULL OUTER JOIN Notas n ON n.Dia = v.Dia
    ORDER BY Dia;
END
GO


/* -----------------------------------------------------------------
   7. Panel principal
   - Ventas, ticket y ventas por dia: netos de notas.
   - Ventas por rubro y top 5: restan lo devuelto de cada repuesto.
   - Repuestos criticos: por DEBAJO del minimo (antes contaba tambien
     los que estaban justo en el minimo, que estan bien).
   El resto queda igual.
   ----------------------------------------------------------------- */
ALTER PROCEDURE [dbo].[SP_Dashboard_General]
    @Desde DATE,
    @Hasta DATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Bruto DECIMAL(12,2), @Cantidad INT;
    SELECT @Bruto = ISNULL(SUM(Total), 0), @Cantidad = COUNT(*)
    FROM Venta WHERE IdEstadoVenta = 1 AND CAST(Fecha AS DATE) BETWEEN @Desde AND @Hasta;

    DECLARE @Ajuste DECIMAL(12,2) =
        ISNULL((SELECT SUM(AjusteVentas) FROM vw_NotaClienteImpacto WHERE Fecha BETWEEN @Desde AND @Hasta), 0);

    -- Lo devuelto en el periodo, por repuesto
    DECLARE @Devuelto TABLE (IdRepuesto INT PRIMARY KEY, Cantidad INT, Importe DECIMAL(12,2));
    INSERT INTO @Devuelto
    SELECT d.IdRepuesto, SUM(d.Cantidad), SUM(d.Subtotal)
    FROM NotaClienteDetalle d INNER JOIN NotaCliente n ON n.Id = d.IdNota
    WHERE n.Tipo = 'NC' AND CAST(n.Fecha AS DATE) BETWEEN @Desde AND @Hasta
    GROUP BY d.IdRepuesto;

    -- ===== RESULT SET 1: KPIs principales =====
    SELECT
        @Bruto + @Ajuste AS VentasPeriodo,
        @Cantidad        AS CantidadVentas,
        CASE WHEN @Cantidad = 0 THEN 0 ELSE CAST((@Bruto + @Ajuste) / @Cantidad AS DECIMAL(12,2)) END AS TicketPromedio,
        ISNULL((SELECT SUM(CASE WHEN Tipo = 'Ingreso' THEN Monto ELSE -Monto END) FROM MovimientoCaja), 0) AS SaldoCaja,
        ISNULL((SELECT COUNT(*) FROM Stock s INNER JOIN Repuesto r ON r.Id = s.IdRepuesto
                WHERE r.Activo = 1 AND s.Cantidad < s.StockMinimo), 0) AS RepuestosCriticos,
        ISNULL((SELECT COUNT(*) FROM Venta
                WHERE IdEstadoVenta = 2 AND CAST(FechaAnulacion AS DATE) BETWEEN @Desde AND @Hasta), 0) AS VentasAnuladas;

    -- ===== RESULT SET 2: Ventas por dia, netas =====
    ;WITH Ventas AS (
        SELECT CAST(Fecha AS DATE) AS Dia, SUM(Total) AS Total
        FROM Venta WHERE IdEstadoVenta = 1 AND CAST(Fecha AS DATE) BETWEEN @Desde AND @Hasta
        GROUP BY CAST(Fecha AS DATE)
    ),
    Notas AS (
        SELECT Fecha AS Dia, SUM(AjusteVentas) AS Ajuste
        FROM vw_NotaClienteImpacto WHERE Fecha BETWEEN @Desde AND @Hasta
        GROUP BY Fecha
    )
    SELECT ISNULL(v.Dia, n.Dia) AS Dia, ISNULL(v.Total, 0) + ISNULL(n.Ajuste, 0) AS Total
    FROM Ventas v FULL OUTER JOIN Notas n ON n.Dia = v.Dia
    ORDER BY Dia;

    -- ===== RESULT SET 3: Ventas por rubro, menos lo devuelto =====
    ;WITH Vendido AS (
        SELECT dv.IdRepuesto, SUM(dv.Subtotal) AS Importe
        FROM DetalleVenta dv
        INNER JOIN Venta v ON v.Id = dv.IdVenta AND v.IdEstadoVenta = 1
        WHERE CAST(v.Fecha AS DATE) BETWEEN @Desde AND @Hasta
        GROUP BY dv.IdRepuesto
    ),
    PorRepuesto AS (
        SELECT ISNULL(v.IdRepuesto, d.IdRepuesto) AS IdRepuesto,
               ISNULL(v.Importe, 0) - ISNULL(d.Importe, 0) AS Importe
        FROM Vendido v FULL OUTER JOIN @Devuelto d ON d.IdRepuesto = v.IdRepuesto
    )
    SELECT ISNULL(ru.Nombre, 'Sin rubro') AS Rubro, SUM(p.Importe) AS Total
    FROM PorRepuesto p
    INNER JOIN Repuesto r ON r.Id = p.IdRepuesto
    LEFT JOIN Rubro ru    ON ru.Id = r.IdRubro
    GROUP BY ru.Nombre
    HAVING SUM(p.Importe) > 0
    ORDER BY Total DESC;

    -- ===== RESULT SET 4: Top 5 productos mas vendidos, neto de devoluciones =====
    ;WITH Vendido AS (
        SELECT dv.IdRepuesto, SUM(dv.Cantidad) AS Cantidad, SUM(dv.Subtotal) AS Importe
        FROM DetalleVenta dv
        INNER JOIN Venta v ON v.Id = dv.IdVenta AND v.IdEstadoVenta = 1
        WHERE CAST(v.Fecha AS DATE) BETWEEN @Desde AND @Hasta
        GROUP BY dv.IdRepuesto
    )
    SELECT TOP 5
        r.Descripcion,
        SUM(v.Cantidad - ISNULL(d.Cantidad, 0)) AS CantidadVendida,
        SUM(v.Importe  - ISNULL(d.Importe, 0))  AS ImporteTotal
    FROM Vendido v
    LEFT JOIN @Devuelto d ON d.IdRepuesto = v.IdRepuesto
    INNER JOIN Repuesto r ON r.Id = v.IdRepuesto
    GROUP BY r.Descripcion
    HAVING SUM(v.Cantidad - ISNULL(d.Cantidad, 0)) > 0
    ORDER BY CantidadVendida DESC;

    -- ===== RESULT SET 5: Ingresos vs egresos de caja por mes (sin cambios) =====
    SELECT
        FORMAT(Fecha, 'yyyy-MM') AS Mes,
        SUM(CASE WHEN Tipo = 'Ingreso' THEN Monto ELSE 0 END) AS Ingresos,
        SUM(CASE WHEN Tipo = 'Egreso'  THEN Monto ELSE 0 END) AS Egresos
    FROM MovimientoCaja
    WHERE CAST(Fecha AS DATE) BETWEEN @Desde AND @Hasta
    GROUP BY FORMAT(Fecha, 'yyyy-MM')
    ORDER BY Mes;

    -- ===== RESULT SET 6: Ventas por dia de semana y mes (sin cambios) =====
    SELECT
        DATENAME(WEEKDAY, Fecha) AS DiaSemana,
        DATEPART(WEEKDAY, Fecha)  AS NumDia,
        FORMAT(Fecha, 'yyyy-MM')  AS Mes,
        SUM(Total)                AS Total
    FROM Venta
    WHERE IdEstadoVenta = 1 AND CAST(Fecha AS DATE) BETWEEN @Desde AND @Hasta
    GROUP BY DATENAME(WEEKDAY, Fecha), DATEPART(WEEKDAY, Fecha), FORMAT(Fecha, 'yyyy-MM')
    ORDER BY Mes, NumDia;
END
GO


/* -----------------------------------------------------------------
   PRUEBAS
   Comparar Ventas contra VentasBrutas - NotasCredito + NotasDebito.
   ----------------------------------------------------------------- */
SELECT TOP 10 * FROM vw_NotaClienteImpacto ORDER BY Id DESC;
EXEC SP_Reporte_PuntoEquilibrio;
EXEC SP_Dashboard_Periodo;
EXEC SP_Reporte_Pronostico @MesesHistoria = 6, @MesesProyectar = 3;
DECLARE @d DATE = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1), @h DATE = CAST(GETDATE() AS DATE);
EXEC SP_Reporte_VentasResumen @Desde = @d, @Hasta = @h;
EXEC SP_Reporte_VentasPeriodo @Desde = @d, @Hasta = @h;
EXEC SP_Dashboard_General @Desde = @d, @Hasta = @h;
GO
