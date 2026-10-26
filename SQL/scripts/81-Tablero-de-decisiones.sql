USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   81 — TABLERO DE DECISIONES

   Cada cosa que se hace en el sistema deja un dato. Este script los
   junta para responder preguntas del negocio:
     - Ventas:       que mes se vendio mas, que dias y a que hora,
                     con que se paga, quien vende, cuanto se descuenta.
     - Productos:    lo mas vendido, lo que mas ganancia deja, la
                     temporada de cada rubro, lo que se vende cada vez
                     menos, cuantos productos hacen el 80% de la venta.
     - Proveedores:  cuanto tarda cada uno en entregar, que dia y a que
                     hora suele llegar, cada cuanto, si manda completo,
                     cuanto llega roto o mal facturado, cuanto aumento.
     - Clientes:     los mejores, los que dejaron de venir, quien debe,
                     como terminan los encargos.
     - Stock:        lo que se vende y no hay, la plata parada en el
                     estante, cuantos dias alcanza cada repuesto.
     - Rentabilidad: ganancia menos gastos mes a mes, en que se gasta.

   CRITERIOS (los mismos de los reportes del script 58)
   - Venta valida: IdEstadoVenta = 1.
   - Importe de un renglon: cantidad x precio x (1 - descuento de la venta).
   - Ganancia: importe - cantidad x costo del renglon (CostoUnitario).
   - Las devoluciones (NC) restan en la fecha de la nota. El repuesto
     que vuelve al stock devuelve su costo; el fallado no.
   - No se guarda nada nuevo: todo sale de lo que el sistema ya registra.

   Requiere los scripts 43, 46, 49, 58, 61, 62, 63, 74 y 80.
   ================================================================= */


/* -----------------------------------------------------------------
   1. Renglones vendidos, netos de devoluciones
   Una fila por renglon de venta valida y una fila NEGATIVA por cada
   repuesto devuelto con nota de credito.
   ----------------------------------------------------------------- */
IF OBJECT_ID('vw_VentaLinea', 'V') IS NOT NULL DROP VIEW vw_VentaLinea;
GO
CREATE VIEW vw_VentaLinea
AS
SELECT
    'VENTA'                                   AS Origen,
    v.Id                                      AS IdVenta,
    v.Fecha                                   AS Fecha,
    CAST(v.Fecha AS DATE)                     AS Dia,
    v.IdCliente                               AS IdCliente,
    v.IdUsuario                               AS IdUsuario,
    dv.IdRepuesto                             AS IdRepuesto,
    dv.Cantidad                               AS Unidades,
    CAST(dv.Cantidad * dv.PrecioUnitario * (1 - ISNULL(v.PorcentajeDescuento, 0) / 100.0) AS DECIMAL(14,2)) AS Importe,
    CAST(dv.Cantidad * ISNULL(dv.CostoUnitario, 0) AS DECIMAL(14,2)) AS Costo,
    CASE WHEN dv.CostoUnitario IS NULL THEN 1 ELSE 0 END AS SinCosto
FROM DetalleVenta dv
INNER JOIN Venta v ON v.Id = dv.IdVenta
WHERE v.IdEstadoVenta = 1

UNION ALL

SELECT
    'DEVOLUCION',
    n.IdVenta,
    n.Fecha,
    CAST(n.Fecha AS DATE),
    n.IdCliente,
    n.IdUsuario,
    d.IdRepuesto,
    -d.Cantidad,
    CAST(-d.Subtotal AS DECIMAL(14,2)),
    CAST(-(CASE WHEN d.ReingresaStock = 1 THEN d.Cantidad * ISNULL(c.Costo, 0) ELSE 0 END) AS DECIMAL(14,2)),
    0
FROM NotaClienteDetalle d
INNER JOIN NotaCliente n ON n.Id = d.IdNota
OUTER APPLY (SELECT AVG(dv.CostoUnitario) AS Costo
             FROM DetalleVenta dv
             WHERE dv.IdVenta = n.IdVenta AND dv.IdRepuesto = d.IdRepuesto) c
WHERE n.Tipo = 'NC';
GO


/* -----------------------------------------------------------------
   2. Numeros de un periodo (mismo calculo que SP_Dashboard_Periodo)
   ----------------------------------------------------------------- */
IF OBJECT_ID('fn_TableroPeriodo', 'IF') IS NOT NULL DROP FUNCTION fn_TableroPeriodo;
GO
CREATE FUNCTION fn_TableroPeriodo (@Desde DATE, @Hasta DATE)
RETURNS TABLE
AS
RETURN
WITH V AS (
    SELECT ISNULL(SUM(v.Total), 0) AS Bruto, COUNT(*) AS Operaciones
    FROM Venta v
    WHERE v.IdEstadoVenta = 1 AND v.Fecha >= @Desde AND v.Fecha < DATEADD(DAY, 1, @Hasta)
),
L AS (
    SELECT ISNULL(SUM(dv.Cantidad), 0) AS Unidades,
           ISNULL(SUM(dv.Cantidad * dv.PrecioUnitario * (1 - ISNULL(v.PorcentajeDescuento, 0) / 100.0)), 0) AS ImporteLineas,
           ISNULL(SUM(dv.Cantidad * ISNULL(dv.CostoUnitario, 0)), 0) AS Costo,
           ISNULL(SUM(dv.Cantidad * dv.PrecioUnitario * ISNULL(v.PorcentajeDescuento, 0) / 100.0), 0) AS Descuentos
    FROM DetalleVenta dv
    INNER JOIN Venta v ON v.Id = dv.IdVenta
    WHERE v.IdEstadoVenta = 1 AND v.Fecha >= @Desde AND v.Fecha < DATEADD(DAY, 1, @Hasta)
),
N AS (
    SELECT ISNULL(SUM(NotaCredito), 0) AS NC, ISNULL(SUM(NotaDebito), 0) AS ND,
           ISNULL(SUM(CostoDevuelto), 0) AS CostoDevuelto, ISNULL(SUM(UnidadesDevueltas), 0) AS UnidadesDevueltas
    FROM vw_NotaClienteImpacto
    WHERE Fecha BETWEEN @Desde AND @Hasta
),
G AS (
    SELECT ISNULL(SUM(g.Importe), 0) AS Gastos
    FROM Gasto g
    WHERE g.Estado <> 'ANULADO' AND g.Fecha BETWEEN @Desde AND @Hasta
),
C AS (
    SELECT ISNULL(SUM(vp.Comision), 0) AS Comisiones
    FROM VentaPago vp
    INNER JOIN Venta v ON v.Id = vp.IdVenta
    WHERE v.IdEstadoVenta = 1 AND v.Fecha >= @Desde AND v.Fecha < DATEADD(DAY, 1, @Hasta)
)
SELECT
    CAST(V.Bruto - N.NC + N.ND AS DECIMAL(14,2))                                    AS Ventas,
    V.Operaciones                                                                   AS Operaciones,
    L.Unidades - N.UnidadesDevueltas                                                AS Unidades,
    CAST(L.Costo - N.CostoDevuelto AS DECIMAL(14,2))                                AS CostoVendido,
    CAST((L.ImporteLineas - L.Costo) - N.NC + N.CostoDevuelto + N.ND AS DECIMAL(14,2)) AS Ganancia,
    CAST(N.NC AS DECIMAL(14,2))                                                     AS NotasCredito,
    CAST(L.Descuentos AS DECIMAL(14,2))                                             AS Descuentos,
    CAST(G.Gastos AS DECIMAL(14,2))                                                 AS Gastos,
    CAST(C.Comisiones AS DECIMAL(14,2))                                             AS Comisiones
FROM V CROSS JOIN L CROSS JOIN N CROSS JOIN G CROSS JOIN C;
GO


/* -----------------------------------------------------------------
   3. Los ultimos N meses (el actual incluido), del mas viejo al actual
   ----------------------------------------------------------------- */
IF OBJECT_ID('fn_TableroMeses', 'IF') IS NOT NULL DROP FUNCTION fn_TableroMeses;
GO
CREATE FUNCTION fn_TableroMeses (@Meses INT)
RETURNS TABLE
AS
RETURN
WITH M AS (
    SELECT 0 AS N
    UNION ALL
    SELECT N + 1 FROM M WHERE N + 1 < @Meses
)
SELECT DATEADD(MONTH, -N, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1)) AS Mes
FROM M;
GO


/* -----------------------------------------------------------------
   4. Costos fijos del mes (lista del script 80; si esta vacia, el
   parametro viejo)
   ----------------------------------------------------------------- */
IF OBJECT_ID('fn_CostosFijosMensuales', 'FN') IS NOT NULL DROP FUNCTION fn_CostosFijosMensuales;
GO
CREATE FUNCTION fn_CostosFijosMensuales ()
RETURNS DECIMAL(14,2)
AS
BEGIN
    DECLARE @cf DECIMAL(14,2) = (SELECT SUM(MontoMensual) FROM CostoFijo WHERE Activo = 1);
    IF @cf IS NULL OR @cf = 0
        SET @cf = ISNULL(TRY_CAST((SELECT Valor FROM ParametroSistema WHERE Clave = 'CostosFijosMensuales') AS DECIMAL(14,2)), 0);
    RETURN @cf;
END
GO


/* -----------------------------------------------------------------
   5. Dias habiles entre dos momentos (sin sabados ni domingos), para
   comparar la demora real con los DiasEntrega del proveedor.
   01/01/1900 fue lunes: dia % 7 -> 0 lunes ... 5 sabado, 6 domingo.
   ----------------------------------------------------------------- */
IF OBJECT_ID('fn_DiasHabiles', 'FN') IS NOT NULL DROP FUNCTION fn_DiasHabiles;
GO
CREATE FUNCTION fn_DiasHabiles (@Desde DATETIME, @Hasta DATETIME)
RETURNS INT
AS
BEGIN
    DECLARE @d DATE = CAST(@Desde AS DATE), @h DATE = CAST(@Hasta AS DATE);
    IF @h <= @d RETURN 0;
    DECLARE @dias INT = DATEDIFF(DAY, @d, @h);
    DECLARE @semanas INT = @dias / 7;
    DECLARE @resto INT = @dias % 7;
    DECLARE @n INT = @semanas * 5, @i INT = 1;
    WHILE @i <= @resto
    BEGIN
        IF DATEDIFF(DAY, '19000101', DATEADD(DAY, @i, @d)) % 7 < 5 SET @n = @n + 1;
        SET @i = @i + 1;
    END
    RETURN @n;
END
GO


/* =================================================================
   6. RESUMEN: lo que se ve al entrar al Dashboard
   RS1 Numeros del periodo y del anterior de igual duracion
   RS2 Un titular por area (para las tarjetas)
   RS3 Alertas: cosas para decidir, de la mas urgente a la menos
   ================================================================= */
IF OBJECT_ID('SP_Tablero_Resumen', 'P') IS NOT NULL DROP PROCEDURE SP_Tablero_Resumen;
GO
CREATE PROCEDURE SP_Tablero_Resumen
    @Desde DATE = NULL,
    @Hasta DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @hoy DATE = CAST(GETDATE() AS DATE);
    IF @Desde IS NULL SET @Desde = DATEFROMPARTS(YEAR(@hoy), MONTH(@hoy), 1);
    IF @Hasta IS NULL SET @Hasta = @hoy;
    IF @Hasta < @Desde SET @Hasta = @Desde;

    DECLARE @dias INT = DATEDIFF(DAY, @Desde, @Hasta) + 1;
    DECLARE @antDesde DATE = DATEADD(DAY, -@dias, @Desde);
    DECLARE @antHasta DATE = DATEADD(DAY, -1, @Desde);

    DECLARE @cfMes DECIMAL(14,2) = dbo.fn_CostosFijosMensuales();
    DECLARE @meses DECIMAL(8,3) = @dias / 30.0;

    /* ---------- RS1: numeros ---------- */
    SELECT
        @Desde AS Desde, @Hasta AS Hasta, @antDesde AS AnteriorDesde, @antHasta AS AnteriorHasta,
        a.Ventas, a.Operaciones, a.Unidades, a.Ganancia, a.CostoVendido, a.Gastos, a.Comisiones, a.Descuentos, a.NotasCredito,
        CAST(CASE WHEN a.Operaciones = 0 THEN 0 ELSE a.Ventas / a.Operaciones END AS DECIMAL(14,2)) AS TicketPromedio,
        CAST(CASE WHEN a.Ventas = 0 THEN 0 ELSE a.Ganancia * 100.0 / a.Ventas END AS DECIMAL(6,1))    AS MargenPorc,
        CAST(a.Ganancia - a.Gastos - a.Comisiones AS DECIMAL(14,2))                                   AS Resultado,
        b.Ventas AS VentasAnterior, b.Operaciones AS OperacionesAnterior, b.Ganancia AS GananciaAnterior,
        CAST(CASE WHEN b.Operaciones = 0 THEN 0 ELSE b.Ventas / b.Operaciones END AS DECIMAL(14,2)) AS TicketAnterior,
        CAST(b.Ganancia - b.Gastos - b.Comisiones AS DECIMAL(14,2))                                   AS ResultadoAnterior,
        @cfMes                                                       AS CostosFijosMensuales,
        CAST(@cfMes * @meses AS DECIMAL(14,2))                       AS CostosFijosPeriodo,
        CAST(CASE WHEN a.Ventas > 0 AND a.Ganancia > 0 AND @cfMes > 0
                  THEN @cfMes * @meses / (a.Ganancia / a.Ventas) END AS DECIMAL(14,2)) AS PuntoEquilibrio,
        ISNULL(dbo.fn_SaldoCaja(), 0)                                AS SaldoCaja
    FROM dbo.fn_TableroPeriodo(@Desde, @Hasta) a
    CROSS JOIN dbo.fn_TableroPeriodo(@antDesde, @antHasta) b;

    /* ---------- RS2: un titular por area ---------- */
    DECLARE @MejorMes DATE, @MejorMesVentas DECIMAL(14,2);
    SELECT TOP 1 @MejorMes = m.Mes, @MejorMesVentas = p.Ventas
    FROM dbo.fn_TableroMeses(12) m
    CROSS APPLY dbo.fn_TableroPeriodo(m.Mes, EOMONTH(m.Mes)) p
    WHERE p.Ventas > 0
    ORDER BY p.Ventas DESC;

    DECLARE @TopUnid NVARCHAR(200), @TopUnidCant INT, @TopGan NVARCHAR(200), @TopGanImp DECIMAL(14,2);
    SELECT TOP 1 @TopUnid = r.Descripcion, @TopUnidCant = SUM(l.Unidades)
    FROM vw_VentaLinea l INNER JOIN Repuesto r ON r.Id = l.IdRepuesto
    WHERE l.Dia BETWEEN @Desde AND @Hasta
    GROUP BY r.Id, r.Descripcion
    HAVING SUM(l.Unidades) > 0
    ORDER BY SUM(l.Unidades) DESC;

    SELECT TOP 1 @TopGan = r.Descripcion, @TopGanImp = SUM(l.Importe - l.Costo)
    FROM vw_VentaLinea l INNER JOIN Repuesto r ON r.Id = l.IdRepuesto
    WHERE l.Dia BETWEEN @Desde AND @Hasta
    GROUP BY r.Id, r.Descripcion
    HAVING SUM(l.Importe - l.Costo) > 0
    ORDER BY SUM(l.Importe - l.Costo) DESC;

    -- Proveedores: demora de los ultimos 6 meses
    DECLARE @Demora DECIMAL(6,1), @ProvRapido NVARCHAR(100), @ProvRapidoDias DECIMAL(6,1);
    ;WITH Lleg AS (
        SELECT p.Id, p.IdProveedor, p.FechaEnvio, MIN(r.Fecha) AS Llegada
        FROM Pedido p
        INNER JOIN RecepcionPedido r ON r.IdPedido = p.Id AND r.Anulada = 0
        WHERE p.FechaEnvio IS NOT NULL AND p.FechaEnvio >= DATEADD(MONTH, -6, @hoy)
        GROUP BY p.Id, p.IdProveedor, p.FechaEnvio
    )
    SELECT @Demora = CAST(AVG(CAST(dbo.fn_DiasHabiles(FechaEnvio, Llegada) AS DECIMAL(8,2))) AS DECIMAL(6,1)) FROM Lleg;

    ;WITH Lleg AS (
        SELECT p.Id, p.IdProveedor, p.FechaEnvio, MIN(r.Fecha) AS Llegada
        FROM Pedido p
        INNER JOIN RecepcionPedido r ON r.IdPedido = p.Id AND r.Anulada = 0
        WHERE p.FechaEnvio IS NOT NULL AND p.FechaEnvio >= DATEADD(MONTH, -6, @hoy)
        GROUP BY p.Id, p.IdProveedor, p.FechaEnvio
    )
    SELECT TOP 1 @ProvRapido = pr.RazonSocial,
                 @ProvRapidoDias = CAST(AVG(CAST(dbo.fn_DiasHabiles(l.FechaEnvio, l.Llegada) AS DECIMAL(8,2))) AS DECIMAL(6,1))
    FROM Lleg l INNER JOIN Proveedor pr ON pr.Id = l.IdProveedor
    GROUP BY pr.Id, pr.RazonSocial
    HAVING COUNT(*) >= 2
    ORDER BY AVG(CAST(dbo.fn_DiasHabiles(l.FechaEnvio, l.Llegada) AS DECIMAL(8,2))), COUNT(*) DESC;

    DECLARE @Reclamos DECIMAL(14,2) = ISNULL((SELECT SUM(Importe) FROM IncidenciaRecepcion WHERE Estado IN ('ABIERTA', 'EN_RECLAMO')), 0);
    DECLARE @DeudaProv DECIMAL(14,2) = ISNULL((SELECT SUM(Monto) FROM MovimientoCtaCteProveedor), 0);

    -- Clientes con nombre (no Consumidor Final ni Mecanico Mostrador)
    DECLARE @ClientesActivos INT, @MejorCliente NVARCHAR(120), @MejorClienteImp DECIMAL(14,2), @Perdidos INT;
    SELECT @ClientesActivos = COUNT(DISTINCT v.IdCliente)
    FROM Venta v INNER JOIN Cliente c ON c.Id = v.IdCliente
    WHERE v.IdEstadoVenta = 1 AND v.Fecha >= @Desde AND v.Fecha < DATEADD(DAY, 1, @Hasta)
      AND c.Dni NOT IN ('00000000', '00000001');

    SELECT TOP 1 @MejorCliente = c.Nombre + ' ' + c.Apellido, @MejorClienteImp = SUM(l.Importe)
    FROM vw_VentaLinea l INNER JOIN Cliente c ON c.Id = l.IdCliente
    WHERE l.Dia BETWEEN @Desde AND @Hasta AND c.Dni NOT IN ('00000000', '00000001')
    GROUP BY c.Id, c.Nombre, c.Apellido
    ORDER BY SUM(l.Importe) DESC;

    SELECT @Perdidos = COUNT(*)
    FROM (
        SELECT v.IdCliente
        FROM Venta v INNER JOIN Cliente c ON c.Id = v.IdCliente
        WHERE v.IdEstadoVenta = 1 AND c.Dni NOT IN ('00000000', '00000001')
          AND v.Fecha >= DATEADD(DAY, -365, @hoy)
        GROUP BY v.IdCliente
        HAVING SUM(CASE WHEN v.Fecha < DATEADD(DAY, -60, @hoy) THEN 1 ELSE 0 END) >= 3
           AND MAX(v.Fecha) < DATEADD(DAY, -60, @hoy)
    ) x;

    -- Stock
    DECLARE @V TABLE (IdRepuesto INT PRIMARY KEY, U90 INT, UltimaVenta DATETIME);
    INSERT INTO @V
    SELECT IdRepuesto,
           SUM(CASE WHEN Dia >= DATEADD(DAY, -90, @hoy) THEN Unidades ELSE 0 END),
           MAX(CASE WHEN Origen = 'VENTA' THEN Fecha END)
    FROM vw_VentaLinea
    GROUP BY IdRepuesto;

    DECLARE @ValorStock DECIMAL(14,2), @Inmov DECIMAL(14,2), @InmovArt INT, @Quiebres INT;
    ;WITH S AS (
        SELECT r.Id, ISNULL(st.Cantidad, 0) AS Stock, ISNULL(rs.Reservado, 0) AS Reservado, ISNULL(r.PrecioCompra, 0) AS Costo
        FROM Repuesto r
        LEFT JOIN (SELECT IdRepuesto, SUM(Cantidad) AS Cantidad FROM Stock GROUP BY IdRepuesto) st ON st.IdRepuesto = r.Id
        LEFT JOIN vw_StockReservado rs ON rs.IdRepuesto = r.Id
        WHERE r.Activo = 1
    )
    SELECT
        @ValorStock = SUM(CASE WHEN s.Stock > 0 THEN s.Stock * s.Costo ELSE 0 END),
        @Inmov      = SUM(CASE WHEN s.Stock > 0 AND (v.UltimaVenta IS NULL OR v.UltimaVenta < DATEADD(DAY, -180, @hoy)) THEN s.Stock * s.Costo ELSE 0 END),
        @InmovArt   = SUM(CASE WHEN s.Stock > 0 AND (v.UltimaVenta IS NULL OR v.UltimaVenta < DATEADD(DAY, -180, @hoy)) THEN 1 ELSE 0 END),
        @Quiebres   = SUM(CASE WHEN s.Stock - s.Reservado <= 0 AND ISNULL(v.U90, 0) >= 2 THEN 1 ELSE 0 END)
    FROM S s LEFT JOIN @V v ON v.IdRepuesto = s.Id;

    SELECT
        @MejorMes AS MejorMes, @MejorMesVentas AS MejorMesVentas,
        @TopUnid AS ProductoMasVendido, @TopUnidCant AS ProductoMasVendidoUnidades,
        @TopGan AS ProductoMasGanancia, @TopGanImp AS ProductoMasGananciaImporte,
        @Demora AS DemoraPromedioDias, @ProvRapido AS ProveedorMasRapido, @ProvRapidoDias AS ProveedorMasRapidoDias,
        @Reclamos AS ReclamosAbiertos, @DeudaProv AS DeudaProveedores,
        @ClientesActivos AS ClientesActivos, @MejorCliente AS MejorCliente, @MejorClienteImp AS MejorClienteImporte,
        @Perdidos AS ClientesPerdidos,
        ISNULL(@ValorStock, 0) AS ValorStock, ISNULL(@Inmov, 0) AS StockInmovilizado, ISNULL(@InmovArt, 0) AS ArticulosInmovilizados,
        ISNULL(@Quiebres, 0) AS Quiebres;

    /* ---------- RS3: alertas para decidir ---------- */
    DECLARE @A TABLE (Prioridad INT, Area VARCHAR(20), Titulo NVARCHAR(200), Detalle NVARCHAR(400), Destino VARCHAR(100));

    IF ISNULL(@Quiebres, 0) > 0
        INSERT INTO @A VALUES (1, 'stock',
            CASE WHEN @Quiebres = 1 THEN N'1 repuesto que se vende está sin stock' ELSE CAST(@Quiebres AS NVARCHAR(10)) + N' repuestos que se venden están sin stock' END,
            N'Vendiste al menos 2 en los últimos 90 días y hoy no queda ninguno disponible. Cada día sin stock es una venta que se va.',
            'Tablero.html#stock');

    DECLARE @NoTenemos INT = (
        SELECT COUNT(*) FROM (
            SELECT TextoNormalizado
            FROM RegistroBusqueda
            WHERE Fecha >= DATEADD(DAY, -30, @hoy) AND ResultadosLocal = 0 AND Origen <> 'REVISION'
              AND TextoNormalizado IS NOT NULL
            GROUP BY TextoNormalizado
            HAVING COUNT(*) >= 3) x);
    IF @NoTenemos > 0
        INSERT INTO @A VALUES (1, 'productos',
            CASE WHEN @NoTenemos = 1 THEN N'1 cosa que te piden y no tenés' ELSE CAST(@NoTenemos AS NVARCHAR(10)) + N' cosas que te piden y no tenés' END,
            N'Se buscaron 3 veces o más en el último mes sin resultados en el local. Puede convenir incorporarlas.',
            'ReporteBusquedas.html');

    DECLARE @BajoCosto INT = (
        SELECT COUNT(DISTINCT IdVenta) FROM vw_VentaLinea
        WHERE Origen = 'VENTA' AND SinCosto = 0 AND Unidades > 0 AND Importe < Costo
          AND Dia BETWEEN @Desde AND @Hasta);
    IF @BajoCosto > 0
        INSERT INTO @A VALUES (1, 'productos',
            CASE WHEN @BajoCosto = 1 THEN N'1 venta con algún repuesto por debajo del costo' ELSE CAST(@BajoCosto AS NVARCHAR(10)) + N' ventas con algún repuesto por debajo del costo' END,
            N'El precio cobrado (con el descuento) no cubrió lo que costó. Revisá precios desactualizados o descuentos.',
            'Tablero.html#productos');

    DECLARE @RecViejos INT, @RecViejosImp DECIMAL(14,2);
    SELECT @RecViejos = COUNT(*), @RecViejosImp = ISNULL(SUM(Importe), 0)
    FROM IncidenciaRecepcion
    WHERE Estado IN ('ABIERTA', 'EN_RECLAMO') AND Fecha < DATEADD(DAY, -30, @hoy);
    IF @RecViejos > 0
        INSERT INTO @A VALUES (2, 'proveedores',
            CASE WHEN @RecViejos = 1 THEN N'1 reclamo a proveedores con más de 30 días' ELSE CAST(@RecViejos AS NVARCHAR(10)) + N' reclamos a proveedores con más de 30 días' END,
            CASE WHEN @RecViejos = 1 THEN N'Son ' ELSE N'Suman ' END + FORMAT(@RecViejosImp, 'C0', 'es-AR') + N' que todavía no volvieron como nota de crédito.',
            'Tablero.html#proveedores');

    DECLARE @Deudores INT, @DeudaCli DECIMAL(14,2);
    SELECT @Deudores = COUNT(*), @DeudaCli = ISNULL(SUM(Saldo), 0)
    FROM (
        SELECT m.IdCliente, SUM(m.Monto) AS Saldo,
               MAX(CASE WHEN m.Tipo = 'Pago' THEN m.Fecha END) AS UltimoPago,
               MIN(m.Fecha) AS Primero
        FROM MovimientoCuentaCorriente m
        GROUP BY m.IdCliente
        HAVING SUM(m.Monto) > 0
    ) x
    WHERE ISNULL(x.UltimoPago, x.Primero) < DATEADD(DAY, -30, @hoy);
    IF @Deudores > 0
        INSERT INTO @A VALUES (2, 'clientes',
            CASE WHEN @Deudores = 1 THEN N'1 cliente debe y no paga hace más de 30 días' ELSE CAST(@Deudores AS NVARCHAR(10)) + N' clientes deben y no pagan hace más de 30 días' END,
            N'Deuda total en cuenta corriente: ' + FORMAT(@DeudaCli, 'C0', 'es-AR') + N'.',
            'Tablero.html#clientes');

    IF ISNULL(@Perdidos, 0) > 0
        INSERT INTO @A VALUES (2, 'clientes',
            CASE WHEN @Perdidos = 1 THEN N'1 cliente habitual dejó de venir' ELSE CAST(@Perdidos AS NVARCHAR(10)) + N' clientes habituales dejaron de venir' END,
            N'Compraron 3 veces o más en el año y no vuelven hace más de 60 días. Un llamado puede recuperarlos.',
            'Tablero.html#clientes');

    DECLARE @Avisados INT = (
        SELECT COUNT(*) FROM Encargo
        WHERE Estado = 'AVISADO' AND FechaAviso < DATEADD(DAY, -7, @hoy));
    IF @Avisados > 0
        INSERT INTO @A VALUES (2, 'clientes',
            CASE WHEN @Avisados = 1 THEN N'1 encargo avisado hace más de una semana sin retirar' ELSE CAST(@Avisados AS NVARCHAR(10)) + N' encargos avisados hace más de una semana sin retirar' END,
            N'El repuesto está apartado y no se puede vender a otro. Conviene volver a llamar.',
            'Encargos.html');

    DECLARE @Aumentos INT, @AumProm DECIMAL(6,1);
    SELECT @Aumentos = COUNT(DISTINCT pr.IdProveedor),
           @AumProm = CAST(AVG((h.CostoNuevo - h.CostoAnterior) * 100.0 / h.CostoAnterior) AS DECIMAL(6,1))
    FROM HistorialPrecioProveedor h
    INNER JOIN ProveedorRepuesto pr ON pr.Id = h.IdProveedorRepuesto
    WHERE h.Fecha >= DATEADD(DAY, -30, @hoy) AND h.CostoAnterior > 0 AND h.CostoNuevo IS NOT NULL
      AND h.CostoNuevo > h.CostoAnterior;
    IF ISNULL(@Aumentos, 0) > 0
        INSERT INTO @A VALUES (3, 'proveedores',
            CASE WHEN @Aumentos = 1 THEN N'1 proveedor aumentó precios este mes' ELSE CAST(@Aumentos AS NVARCHAR(10)) + N' proveedores aumentaron precios este mes' END,
            N'Aumento promedio de lo que subió: ' + REPLACE(CAST(@AumProm AS NVARCHAR(10)), '.', ',') + N'%. Revisá si tus precios de venta acompañan.',
            'Tablero.html#proveedores');

    IF ISNULL(@Inmov, 0) > 0
        INSERT INTO @A VALUES (3, 'stock',
            FORMAT(@Inmov, 'C0', 'es-AR') + N' de mercadería sin venderse hace 6 meses',
            CASE WHEN @InmovArt = 1 THEN N'1 repuesto con stock y sin ventas en 180 días.' ELSE CAST(@InmovArt AS NVARCHAR(10)) + N' repuestos con stock y sin ventas en 180 días.' END + N' Es plata parada: se puede liquidar o devolver.',
            'Tablero.html#stock');

    IF @cfMes = 0
        INSERT INTO @A VALUES (3, 'rentabilidad',
            N'Faltan cargar los costos fijos',
            N'Sin alquiler, sueldos y servicios no se puede saber cuánto hay que vender para no perder.',
            'Configuracion.html');

    SELECT Prioridad, Area, Titulo, Detalle, Destino FROM @A ORDER BY Prioridad, Area;
END
GO


/* =================================================================
   7. VENTAS
   RS1 Mensual (24 meses)           RS5 Mecanicos y publico
   RS2 Por dia de la semana          RS6 Vendedores
   RS3 Por hora                      RS7 Mismo periodo del anio anterior
   RS4 Medios de pago
   ================================================================= */
IF OBJECT_ID('SP_Tablero_Ventas', 'P') IS NOT NULL DROP PROCEDURE SP_Tablero_Ventas;
GO
CREATE PROCEDURE SP_Tablero_Ventas
    @Desde DATE,
    @Hasta DATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @HastaExcl DATETIME = DATEADD(DAY, 1, @Hasta);

    -- RS1
    SELECT m.Mes, p.Ventas, p.Operaciones, p.Ganancia, p.Unidades,
           CAST(CASE WHEN p.Operaciones = 0 THEN 0 ELSE p.Ventas / p.Operaciones END AS DECIMAL(14,2)) AS Ticket
    FROM dbo.fn_TableroMeses(24) m
    CROSS APPLY dbo.fn_TableroPeriodo(m.Mes, EOMONTH(m.Mes)) p
    ORDER BY m.Mes;

    -- RS2 (0 = lunes ... 6 = domingo)
    SELECT DATEDIFF(DAY, '19000101', v.Fecha) % 7 AS Dia,
           COUNT(*) AS Operaciones, SUM(v.Total) AS Ventas,
           COUNT(DISTINCT CAST(v.Fecha AS DATE)) AS DiasConVenta
    FROM Venta v
    WHERE v.IdEstadoVenta = 1 AND v.Fecha >= @Desde AND v.Fecha < @HastaExcl
    GROUP BY DATEDIFF(DAY, '19000101', v.Fecha) % 7
    ORDER BY Dia;

    -- RS3
    SELECT DATEPART(HOUR, v.Fecha) AS Hora, COUNT(*) AS Operaciones, SUM(v.Total) AS Ventas
    FROM Venta v
    WHERE v.IdEstadoVenta = 1 AND v.Fecha >= @Desde AND v.Fecha < @HastaExcl
    GROUP BY DATEPART(HOUR, v.Fecha)
    ORDER BY Hora;

    -- RS4: lo cobrado por cada medio; las ventas sin cobro son de cuenta corriente
    SELECT m.Nombre AS Medio, COUNT(DISTINCT vp.IdVenta) AS Operaciones,
           SUM(vp.Monto) AS Monto, SUM(vp.Comision) AS Comision
    FROM VentaPago vp
    INNER JOIN Venta v ON v.Id = vp.IdVenta
    INNER JOIN MedioPago m ON m.Id = vp.IdMedioPago
    WHERE v.IdEstadoVenta = 1 AND v.Fecha >= @Desde AND v.Fecha < @HastaExcl
    GROUP BY m.Nombre
    UNION ALL
    -- Sin cobro registrado: cuenta corriente si genero deuda; si no, son
    -- ventas anteriores a los medios de pago (script 37)
    SELECT x.Medio, COUNT(*), SUM(x.Total), 0
    FROM (
        SELECT CASE WHEN EXISTS (SELECT 1 FROM MovimientoCuentaCorriente m WHERE m.IdVenta = v.Id)
                    THEN N'Cuenta corriente' ELSE N'Sin medio registrado' END AS Medio,
               v.Total
        FROM Venta v
        WHERE v.IdEstadoVenta = 1 AND v.Fecha >= @Desde AND v.Fecha < @HastaExcl
          AND NOT EXISTS (SELECT 1 FROM VentaPago vp WHERE vp.IdVenta = v.Id)
    ) x
    GROUP BY x.Medio
    ORDER BY Monto DESC;

    -- RS5
    SELECT CASE WHEN c.EsMecanico = 1 THEN N'Mecánicos' ELSE N'Público' END AS Tipo,
           COUNT(DISTINCT CASE WHEN l.Origen = 'VENTA' THEN l.IdVenta END) AS Operaciones,
           SUM(l.Importe) AS Ventas, SUM(l.Importe - l.Costo) AS Ganancia
    FROM vw_VentaLinea l
    LEFT JOIN Cliente c ON c.Id = l.IdCliente
    WHERE l.Dia BETWEEN @Desde AND @Hasta
    GROUP BY CASE WHEN c.EsMecanico = 1 THEN N'Mecánicos' ELSE N'Público' END;

    -- RS6
    SELECT ISNULL(u.Nombre, N'Sin usuario') AS Vendedor,
           COUNT(DISTINCT l.IdVenta) AS Operaciones,
           SUM(l.Importe) AS Ventas, SUM(l.Importe - l.Costo) AS Ganancia
    FROM vw_VentaLinea l
    LEFT JOIN Usuario u ON u.Id = l.IdUsuario
    WHERE l.Origen = 'VENTA' AND l.Dia BETWEEN @Desde AND @Hasta
    GROUP BY u.Nombre
    ORDER BY Ventas DESC;

    -- RS7
    SELECT 'ACTUAL' AS Periodo, @Desde AS Desde, @Hasta AS Hasta, a.*
    FROM dbo.fn_TableroPeriodo(@Desde, @Hasta) a
    UNION ALL
    SELECT 'ANIO_ANTERIOR', DATEADD(YEAR, -1, @Desde), DATEADD(YEAR, -1, @Hasta), b.*
    FROM dbo.fn_TableroPeriodo(DATEADD(YEAR, -1, @Desde), DATEADD(YEAR, -1, @Hasta)) b;
END
GO


/* =================================================================
   8. PRODUCTOS
   RS1 Ranking (unidades, importe, ganancia, margen)
   RS2 Rubros    RS3 Marcas
   RS4 Temporada: unidades por mes del anio, por rubro (ultimos 36 meses)
   RS5 Historia disponible y renglones sin costo
   RS6 Curva ABC (cuantos productos hacen el 80% de la venta)
   RS7 Tendencia: ultimos 90 dias contra los 90 anteriores
   ================================================================= */
IF OBJECT_ID('SP_Tablero_Productos', 'P') IS NOT NULL DROP PROCEDURE SP_Tablero_Productos;
GO
CREATE PROCEDURE SP_Tablero_Productos
    @Desde DATE,
    @Hasta DATE
AS
BEGIN
    SET NOCOUNT ON;

    SELECT IdRepuesto, Origen, IdVenta, Unidades, Importe, Costo, SinCosto
    INTO #L
    FROM vw_VentaLinea
    WHERE Dia BETWEEN @Desde AND @Hasta;

    -- RS1
    SELECT TOP 300
        r.Id, r.Codigo, r.Descripcion,
        ISNULL(NULLIF(LTRIM(RTRIM(r.MarcaFabricante)), ''), N'Sin marca') AS Marca,
        ISNULL(ru.Nombre, N'Sin rubro') AS Rubro,
        SUM(l.Unidades) AS Unidades,
        SUM(l.Importe) AS Importe,
        SUM(l.Importe - l.Costo) AS Ganancia,
        CAST(CASE WHEN SUM(l.Importe) > 0 THEN SUM(l.Importe - l.Costo) * 100.0 / SUM(l.Importe) END AS DECIMAL(6,1)) AS MargenPorc,
        COUNT(DISTINCT CASE WHEN l.Origen = 'VENTA' THEN l.IdVenta END) AS Operaciones,
        MAX(l.SinCosto) AS SinCosto,
        ISNULL(st.Cantidad, 0) AS Stock
    FROM #L l
    INNER JOIN Repuesto r ON r.Id = l.IdRepuesto
    LEFT JOIN Rubro ru ON ru.Id = r.IdRubro
    LEFT JOIN (SELECT IdRepuesto, SUM(Cantidad) AS Cantidad FROM Stock GROUP BY IdRepuesto) st ON st.IdRepuesto = r.Id
    GROUP BY r.Id, r.Codigo, r.Descripcion, r.MarcaFabricante, ru.Nombre, st.Cantidad
    HAVING SUM(l.Unidades) > 0
    ORDER BY SUM(l.Importe) DESC;

    -- RS2
    SELECT ISNULL(ru.Nombre, N'Sin rubro') AS Rubro,
           SUM(l.Unidades) AS Unidades, SUM(l.Importe) AS Importe, SUM(l.Importe - l.Costo) AS Ganancia,
           COUNT(DISTINCT l.IdRepuesto) AS Productos
    FROM #L l
    INNER JOIN Repuesto r ON r.Id = l.IdRepuesto
    LEFT JOIN Rubro ru ON ru.Id = r.IdRubro
    GROUP BY ru.Nombre
    HAVING SUM(l.Importe) > 0
    ORDER BY Importe DESC;

    -- RS3
    SELECT TOP 30 ISNULL(NULLIF(LTRIM(RTRIM(r.MarcaFabricante)), ''), N'Sin marca') AS Marca,
           SUM(l.Unidades) AS Unidades, SUM(l.Importe) AS Importe, SUM(l.Importe - l.Costo) AS Ganancia,
           COUNT(DISTINCT l.IdRepuesto) AS Productos
    FROM #L l
    INNER JOIN Repuesto r ON r.Id = l.IdRepuesto
    GROUP BY ISNULL(NULLIF(LTRIM(RTRIM(r.MarcaFabricante)), ''), N'Sin marca')
    HAVING SUM(l.Importe) > 0
    ORDER BY Importe DESC;

    -- RS4: temporada, 12 rubros que mas venden
    DECLARE @desde36 DATE = DATEADD(MONTH, -35, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1));
    ;WITH T AS (
        SELECT ISNULL(ru.Nombre, N'Sin rubro') AS Rubro, MONTH(l.Dia) AS Mes, l.Unidades, l.Importe
        FROM vw_VentaLinea l
        INNER JOIN Repuesto r ON r.Id = l.IdRepuesto
        LEFT JOIN Rubro ru ON ru.Id = r.IdRubro
        WHERE l.Dia >= @desde36
    ),
    Top12 AS (
        SELECT TOP 12 Rubro FROM T GROUP BY Rubro HAVING SUM(Importe) > 0 ORDER BY SUM(Importe) DESC
    )
    SELECT t.Rubro, t.Mes, SUM(t.Unidades) AS Unidades, SUM(t.Importe) AS Importe
    FROM T t INNER JOIN Top12 x ON x.Rubro = t.Rubro
    GROUP BY t.Rubro, t.Mes
    ORDER BY t.Rubro, t.Mes;

    -- RS5
    SELECT
        (SELECT MIN(Fecha) FROM Venta WHERE IdEstadoVenta = 1) AS PrimeraVenta,
        (SELECT COUNT(DISTINCT DATEFROMPARTS(YEAR(Fecha), MONTH(Fecha), 1)) FROM Venta WHERE IdEstadoVenta = 1) AS MesesConVentas,
        ISNULL((SELECT SUM(Importe) FROM #L WHERE SinCosto = 1), 0) AS ImporteSinCosto,
        ISNULL((SELECT SUM(Importe) FROM #L WHERE Origen = 'VENTA'), 0) AS ImporteTotal;

    -- RS6: curva ABC por importe
    ;WITH P AS (
        SELECT IdRepuesto, SUM(Importe) AS Importe FROM #L GROUP BY IdRepuesto HAVING SUM(Importe) > 0
    ),
    Acum AS (
        SELECT Importe,
               SUM(Importe) OVER (ORDER BY Importe DESC, IdRepuesto ROWS UNBOUNDED PRECEDING) - Importe AS Antes,
               SUM(Importe) OVER () AS Total
        FROM P
    )
    SELECT CASE WHEN Antes < Total * 0.80 THEN 'A' WHEN Antes < Total * 0.95 THEN 'B' ELSE 'C' END AS Clase,
           COUNT(*) AS Productos, SUM(Importe) AS Importe
    FROM Acum
    GROUP BY CASE WHEN Antes < Total * 0.80 THEN 'A' WHEN Antes < Total * 0.95 THEN 'B' ELSE 'C' END
    ORDER BY Clase;

    -- RS7: tendencia (respecto del ultimo dia elegido)
    ;WITH T AS (
        SELECT l.IdRepuesto,
               SUM(CASE WHEN l.Dia >  DATEADD(DAY, -90, @Hasta) AND l.Dia <= @Hasta THEN l.Unidades ELSE 0 END) AS Ultimos90,
               SUM(CASE WHEN l.Dia >  DATEADD(DAY, -180, @Hasta) AND l.Dia <= DATEADD(DAY, -90, @Hasta) THEN l.Unidades ELSE 0 END) AS Anteriores90
        FROM vw_VentaLinea l
        WHERE l.Dia > DATEADD(DAY, -180, @Hasta) AND l.Dia <= @Hasta
        GROUP BY l.IdRepuesto
    )
    SELECT TOP 60 r.Id, r.Codigo, r.Descripcion, t.Ultimos90, t.Anteriores90,
           CAST(CASE WHEN t.Anteriores90 > 0 THEN (t.Ultimos90 - t.Anteriores90) * 100.0 / t.Anteriores90 END AS DECIMAL(8,1)) AS VariacionPorc
    FROM T t INNER JOIN Repuesto r ON r.Id = t.IdRepuesto
    WHERE (t.Ultimos90 >= 4 OR t.Anteriores90 >= 4)
      AND ABS(t.Ultimos90 - t.Anteriores90) * 2 >= CASE WHEN t.Anteriores90 > 0 THEN t.Anteriores90 ELSE 1 END
    ORDER BY ABS(t.Ultimos90 - t.Anteriores90) DESC;

    DROP TABLE #L;
END
GO


/* =================================================================
   9. FICHA DE UN PRODUCTO (al tocarlo en el ranking)
   RS1 Ficha   RS2 Mensual (24 meses)   RS3 Ultimas compras
   ================================================================= */
IF OBJECT_ID('SP_Tablero_Producto', 'P') IS NOT NULL DROP PROCEDURE SP_Tablero_Producto;
GO
CREATE PROCEDURE SP_Tablero_Producto
    @IdRepuesto INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @hoy DATE = CAST(GETDATE() AS DATE);

    -- RS1
    SELECT r.Id, r.Codigo, r.Descripcion,
           ISNULL(NULLIF(LTRIM(RTRIM(r.MarcaFabricante)), ''), N'Sin marca') AS Marca,
           ISNULL(ru.Nombre, N'Sin rubro') AS Rubro,
           r.PrecioDeVenta, r.PrecioCompra, r.FechaUltimaCompra,
           ISNULL((SELECT SUM(Cantidad) FROM Stock WHERE IdRepuesto = r.Id), 0) AS Stock,
           ISNULL((SELECT MAX(StockMinimo) FROM Stock WHERE IdRepuesto = r.Id), 0) AS StockMinimo,
           ISNULL((SELECT Reservado FROM vw_StockReservado WHERE IdRepuesto = r.Id), 0) AS Reservado,
           (SELECT MAX(Fecha) FROM vw_VentaLinea WHERE IdRepuesto = r.Id AND Origen = 'VENTA') AS UltimaVenta,
           ISNULL((SELECT SUM(Unidades) FROM vw_VentaLinea WHERE IdRepuesto = r.Id AND Dia > DATEADD(DAY, -365, @hoy)), 0) AS Unidades365,
           ISNULL((SELECT SUM(Importe) FROM vw_VentaLinea WHERE IdRepuesto = r.Id AND Dia > DATEADD(DAY, -365, @hoy)), 0) AS Importe365,
           ISNULL((SELECT SUM(Importe - Costo) FROM vw_VentaLinea WHERE IdRepuesto = r.Id AND Dia > DATEADD(DAY, -365, @hoy)), 0) AS Ganancia365
    FROM Repuesto r
    LEFT JOIN Rubro ru ON ru.Id = r.IdRubro
    WHERE r.Id = @IdRepuesto;

    -- RS2
    SELECT m.Mes,
           ISNULL(SUM(l.Unidades), 0) AS Unidades,
           ISNULL(SUM(l.Importe), 0) AS Importe,
           ISNULL(SUM(l.Importe - l.Costo), 0) AS Ganancia
    FROM dbo.fn_TableroMeses(24) m
    LEFT JOIN vw_VentaLinea l ON l.IdRepuesto = @IdRepuesto AND l.Dia >= m.Mes AND l.Dia <= EOMONTH(m.Mes)
    GROUP BY m.Mes
    ORDER BY m.Mes;

    -- RS3
    SELECT TOP 10 r.Fecha, p.RazonSocial AS Proveedor, d.Cantidad, d.CostoUnitario, r.TipoComprobante + ' ' + r.NumeroComprobante AS Comprobante
    FROM DetalleRecepcion d
    INNER JOIN RecepcionPedido r ON r.Id = d.IdRecepcion
    INNER JOIN Proveedor p ON p.Id = r.IdProveedor
    WHERE d.IdRepuesto = @IdRepuesto AND r.Anulada = 0 AND r.Estado = 'CONFIRMADA'
    ORDER BY r.Fecha DESC;
END
GO


/* =================================================================
   10. PROVEEDORES
   RS1 Un renglon por proveedor: demora, cumplimiento, problemas, deuda
   RS2 Llegadas por dia de la semana y hora (para "cuando suele venir")
   RS3 Cambios de precio de sus listas
   RS4 Problemas en la recepcion, por tipo
   RS5 Compras contra costo de lo vendido, mes a mes
   La demora es desde que se envio el pedido hasta que llego la
   primera factura (paso 1 de la recepcion), en dias habiles.
   ================================================================= */
IF OBJECT_ID('SP_Tablero_Proveedores', 'P') IS NOT NULL DROP PROCEDURE SP_Tablero_Proveedores;
GO
CREATE PROCEDURE SP_Tablero_Proveedores
    @Desde DATE,
    @Hasta DATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @HastaExcl DATETIME = DATEADD(DAY, 1, @Hasta);

    -- Pedidos enviados en el periodo y su primera llegada
    SELECT p.Id, p.IdProveedor, p.FechaEnvio,
           (SELECT MIN(r.Fecha) FROM RecepcionPedido r WHERE r.IdPedido = p.Id AND r.Anulada = 0) AS Llegada,
           (SELECT SUM(dp.Cantidad) FROM DetallePedido dp WHERE dp.IdPedido = p.Id) AS Pedidas,
           (SELECT SUM(d.CantidadImputada) FROM DetalleRecepcion d
              INNER JOIN RecepcionPedido r ON r.Id = d.IdRecepcion
              WHERE r.IdPedido = p.Id AND r.Anulada = 0 AND r.Estado = 'CONFIRMADA') AS Llegadas
    INTO #Ped
    FROM Pedido p
    WHERE p.FechaEnvio >= @Desde AND p.FechaEnvio < @HastaExcl AND p.IdEstado <> 3;

    -- Recepciones del periodo
    SELECT r.Id, r.IdProveedor, r.Fecha, r.Estado, r.TotalComprobante
    INTO #Rec
    FROM RecepcionPedido r
    WHERE r.Anulada = 0 AND r.Fecha >= @Desde AND r.Fecha < @HastaExcl;

    ;WITH Ped AS (
        SELECT IdProveedor, COUNT(*) AS Pedidos,
               SUM(CASE WHEN Llegada IS NOT NULL THEN 1 ELSE 0 END) AS PedidosLlegados,
               AVG(CASE WHEN Llegada IS NOT NULL THEN CAST(dbo.fn_DiasHabiles(FechaEnvio, Llegada) AS DECIMAL(8,2)) END) AS DemoraDias,
               MAX(CASE WHEN Llegada IS NOT NULL THEN dbo.fn_DiasHabiles(FechaEnvio, Llegada) END) AS DemoraMax,
               AVG(CASE WHEN Llegada IS NOT NULL THEN DATEDIFF(MINUTE, FechaEnvio, Llegada) / 60.0 END) AS DemoraHoras,
               SUM(ISNULL(Pedidas, 0)) AS UnidadesPedidas,
               SUM(CASE WHEN Llegada IS NOT NULL THEN ISNULL(Pedidas, 0) ELSE 0 END) AS UnidadesPedidasLlegadas,
               SUM(ISNULL(Llegadas, 0)) AS UnidadesLlegadas
        FROM #Ped GROUP BY IdProveedor
    ),
    ATiempo AS (
        SELECT pe.IdProveedor,
               SUM(CASE WHEN dbo.fn_DiasHabiles(pe.FechaEnvio, pe.Llegada) <= pr.DiasEntrega THEN 1 ELSE 0 END) AS ATiempo
        FROM #Ped pe INNER JOIN Proveedor pr ON pr.Id = pe.IdProveedor
        WHERE pe.Llegada IS NOT NULL
        GROUP BY pe.IdProveedor
    ),
    Rec AS (
        SELECT IdProveedor, COUNT(*) AS Entregas,
               SUM(CASE WHEN Estado = 'CONFIRMADA' THEN TotalComprobante ELSE 0 END) AS Compras,
               CAST(CASE WHEN COUNT(*) > 1 THEN DATEDIFF(HOUR, MIN(Fecha), MAX(Fecha)) / 24.0 / (COUNT(*) - 1) END AS DECIMAL(8,1)) AS CadaCuantosDias
        FROM #Rec GROUP BY IdProveedor
    ),
    Fact AS (
        SELECT r.IdProveedor, SUM(d.CantidadFacturada) AS UnidadesFacturadas
        FROM DetalleRecepcion d INNER JOIN #Rec r ON r.Id = d.IdRecepcion
        WHERE r.Estado = 'CONFIRMADA'
        GROUP BY r.IdProveedor
    ),
    Inc AS (
        SELECT i.IdProveedor,
               SUM(i.Cantidad) AS UnidadesConProblema,
               SUM(CASE WHEN i.Tipo = 'DANADO' THEN i.Cantidad ELSE 0 END) AS Rotos,
               COUNT(DISTINCT i.IdRecepcion) AS EntregasConProblema
        FROM IncidenciaRecepcion i INNER JOIN #Rec r ON r.Id = i.IdRecepcion
        WHERE i.Estado <> 'ANULADA'
        GROUP BY i.IdProveedor
    ),
    Abiertos AS (
        SELECT IdProveedor, SUM(Importe) AS ReclamosAbiertos
        FROM IncidenciaRecepcion WHERE Estado IN ('ABIERTA', 'EN_RECLAMO') GROUP BY IdProveedor
    ),
    Deuda AS (
        SELECT IdProveedor, SUM(Monto) AS Deuda FROM MovimientoCtaCteProveedor GROUP BY IdProveedor
    )
    SELECT pr.Id AS IdProveedor, pr.RazonSocial AS Proveedor, pr.DiasEntrega AS DiasPrometidos, pr.DiasPago,
           ISNULL(pe.Pedidos, 0) AS Pedidos, ISNULL(pe.PedidosLlegados, 0) AS PedidosLlegados,
           CAST(pe.DemoraDias AS DECIMAL(6,1)) AS DemoraDias, pe.DemoraMax,
           CAST(pe.DemoraHoras AS DECIMAL(8,1)) AS DemoraHoras,
           CAST(CASE WHEN pe.PedidosLlegados > 0 THEN t.ATiempo * 100.0 / pe.PedidosLlegados END AS DECIMAL(5,1)) AS ATiempoPorc,
           CAST(CASE WHEN pe.UnidadesPedidasLlegadas > 0 THEN pe.UnidadesLlegadas * 100.0 / pe.UnidadesPedidasLlegadas END AS DECIMAL(5,1)) AS CompletoPorc,
           ISNULL(re.Entregas, 0) AS Entregas, ISNULL(re.Compras, 0) AS Compras, re.CadaCuantosDias,
           ISNULL(f.UnidadesFacturadas, 0) AS UnidadesFacturadas,
           ISNULL(i.UnidadesConProblema, 0) AS UnidadesConProblema, ISNULL(i.Rotos, 0) AS Rotos,
           ISNULL(i.EntregasConProblema, 0) AS EntregasConProblema,
           ISNULL(a.ReclamosAbiertos, 0) AS ReclamosAbiertos,
           ISNULL(dd.Deuda, 0) AS Deuda
    FROM Proveedor pr
    LEFT JOIN Ped pe     ON pe.IdProveedor = pr.Id
    LEFT JOIN ATiempo t  ON t.IdProveedor = pr.Id
    LEFT JOIN Rec re     ON re.IdProveedor = pr.Id
    LEFT JOIN Fact f     ON f.IdProveedor = pr.Id
    LEFT JOIN Inc i      ON i.IdProveedor = pr.Id
    LEFT JOIN Abiertos a ON a.IdProveedor = pr.Id
    LEFT JOIN Deuda dd   ON dd.IdProveedor = pr.Id
    WHERE pe.IdProveedor IS NOT NULL OR re.IdProveedor IS NOT NULL
       OR ISNULL(a.ReclamosAbiertos, 0) <> 0 OR ISNULL(dd.Deuda, 0) <> 0
    ORDER BY ISNULL(re.Compras, 0) DESC, pr.RazonSocial;

    -- RS2 (0 = lunes ... 6 = domingo)
    SELECT IdProveedor, DATEDIFF(DAY, '19000101', Fecha) % 7 AS Dia, DATEPART(HOUR, Fecha) AS Hora, COUNT(*) AS Cantidad
    FROM #Rec
    GROUP BY IdProveedor, DATEDIFF(DAY, '19000101', Fecha) % 7, DATEPART(HOUR, Fecha);

    -- RS3
    SELECT pr.IdProveedor, p.RazonSocial AS Proveedor,
           COUNT(DISTINCT h.IdProveedorRepuesto) AS Articulos,
           SUM(CASE WHEN h.CostoNuevo > h.CostoAnterior THEN 1 ELSE 0 END) AS Suben,
           SUM(CASE WHEN h.CostoNuevo < h.CostoAnterior THEN 1 ELSE 0 END) AS Bajan,
           CAST(AVG((h.CostoNuevo - h.CostoAnterior) * 100.0 / h.CostoAnterior) AS DECIMAL(6,1)) AS VariacionPromedio,
           MAX(h.Fecha) AS Ultima
    FROM HistorialPrecioProveedor h
    INNER JOIN ProveedorRepuesto pr ON pr.Id = h.IdProveedorRepuesto
    INNER JOIN Proveedor p ON p.Id = pr.IdProveedor
    WHERE h.Fecha >= @Desde AND h.Fecha < @HastaExcl
      AND h.CostoAnterior > 0 AND h.CostoNuevo IS NOT NULL AND h.CostoNuevo <> h.CostoAnterior
    GROUP BY pr.IdProveedor, p.RazonSocial
    ORDER BY VariacionPromedio DESC;

    -- RS4
    SELECT p.RazonSocial AS Proveedor, i.Tipo, COUNT(*) AS Casos, SUM(i.Cantidad) AS Unidades, SUM(i.Importe) AS Importe
    FROM IncidenciaRecepcion i
    INNER JOIN Proveedor p ON p.Id = i.IdProveedor
    WHERE i.Estado <> 'ANULADA' AND i.Fecha >= @Desde AND i.Fecha < @HastaExcl
    GROUP BY p.RazonSocial, i.Tipo
    ORDER BY Importe DESC;

    -- RS5
    SELECT m.Mes,
           ISNULL((SELECT SUM(r.TotalComprobante) FROM RecepcionPedido r
                   WHERE r.Anulada = 0 AND r.Estado = 'CONFIRMADA'
                     AND r.Fecha >= m.Mes AND r.Fecha < DATEADD(MONTH, 1, m.Mes)), 0) AS Compras,
           p.CostoVendido
    FROM dbo.fn_TableroMeses(12) m
    CROSS APPLY dbo.fn_TableroPeriodo(m.Mes, EOMONTH(m.Mes)) p
    ORDER BY m.Mes;

    DROP TABLE #Ped;
    DROP TABLE #Rec;
END
GO


/* =================================================================
   11. CLIENTES (con nombre: no Consumidor Final ni Mecanico Mostrador)
   RS1 Resumen   RS2 Mejores   RS3 Dejaron de venir
   RS4 Deben en cuenta corriente   RS5 Encargos   RS6 Frecuencia
   ================================================================= */
IF OBJECT_ID('SP_Tablero_Clientes', 'P') IS NOT NULL DROP PROCEDURE SP_Tablero_Clientes;
GO
CREATE PROCEDURE SP_Tablero_Clientes
    @Desde DATE,
    @Hasta DATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @HastaExcl DATETIME = DATEADD(DAY, 1, @Hasta);
    DECLARE @hoy DATE = CAST(GETDATE() AS DATE);

    SELECT v.Id, v.IdCliente, v.Fecha, v.Total,
           CASE WHEN c.Id IS NOT NULL AND c.Dni NOT IN ('00000000', '00000001') THEN 1 ELSE 0 END AS ConNombre
    INTO #V
    FROM Venta v
    LEFT JOIN Cliente c ON c.Id = v.IdCliente
    WHERE v.IdEstadoVenta = 1 AND v.Fecha >= @Desde AND v.Fecha < @HastaExcl;

    -- RS1
    SELECT
        (SELECT COUNT(*) FROM #V) AS Operaciones,
        (SELECT COUNT(*) FROM #V WHERE ConNombre = 1) AS OperacionesConNombre,
        (SELECT ISNULL(SUM(Total), 0) FROM #V WHERE ConNombre = 1) AS VentasConNombre,
        (SELECT ISNULL(SUM(Total), 0) FROM #V) AS VentasTotal,
        (SELECT COUNT(DISTINCT IdCliente) FROM #V WHERE ConNombre = 1) AS Clientes,
        (SELECT COUNT(*) FROM (SELECT IdCliente FROM #V WHERE ConNombre = 1 GROUP BY IdCliente HAVING COUNT(*) >= 2) x) AS Recurrentes,
        (SELECT COUNT(*) FROM (
            SELECT x.IdCliente FROM #V x WHERE x.ConNombre = 1 GROUP BY x.IdCliente
            HAVING NOT EXISTS (SELECT 1 FROM Venta a WHERE a.IdCliente = x.IdCliente AND a.IdEstadoVenta = 1 AND a.Fecha < @Desde)
        ) n) AS Nuevos;

    -- RS2
    SELECT TOP 50 c.Id, c.Nombre + ' ' + c.Apellido AS Cliente, c.Telefono, c.EsMecanico,
           COUNT(DISTINCT CASE WHEN l.Origen = 'VENTA' THEN l.IdVenta END) AS Operaciones,
           SUM(l.Importe) AS Importe, SUM(l.Importe - l.Costo) AS Ganancia,
           (SELECT MAX(a.Fecha) FROM Venta a WHERE a.IdCliente = c.Id AND a.IdEstadoVenta = 1) AS UltimaCompra,
           ISNULL((SELECT SUM(m.Monto) FROM MovimientoCuentaCorriente m WHERE m.IdCliente = c.Id), 0) AS Saldo
    FROM vw_VentaLinea l
    INNER JOIN Cliente c ON c.Id = l.IdCliente
    WHERE l.Dia BETWEEN @Desde AND @Hasta AND c.Dni NOT IN ('00000000', '00000001')
    GROUP BY c.Id, c.Nombre, c.Apellido, c.Telefono, c.EsMecanico
    HAVING SUM(l.Importe) > 0
    ORDER BY Importe DESC;

    -- RS3: 3 compras o mas en el anio y ninguna en 60 dias
    SELECT TOP 40 c.Id, c.Nombre + ' ' + c.Apellido AS Cliente, c.Telefono, c.EsMecanico,
           COUNT(*) AS ComprasEnElAnio, SUM(v.Total) AS ImporteEnElAnio,
           MAX(v.Fecha) AS UltimaCompra, DATEDIFF(DAY, MAX(v.Fecha), @hoy) AS DiasSinVenir
    FROM Venta v
    INNER JOIN Cliente c ON c.Id = v.IdCliente
    WHERE v.IdEstadoVenta = 1 AND c.Dni NOT IN ('00000000', '00000001')
      AND v.Fecha >= DATEADD(DAY, -365, @hoy)
    GROUP BY c.Id, c.Nombre, c.Apellido, c.Telefono, c.EsMecanico
    HAVING COUNT(*) >= 3 AND MAX(v.Fecha) < DATEADD(DAY, -60, @hoy)
    ORDER BY SUM(v.Total) DESC;

    -- RS4
    SELECT c.Id, c.Nombre + ' ' + c.Apellido AS Cliente, c.Telefono,
           SUM(m.Monto) AS Saldo,
           MAX(CASE WHEN m.Tipo = 'Pago' THEN m.Fecha END) AS UltimoPago,
           MAX(CASE WHEN m.Tipo = 'Venta' THEN m.Fecha END) AS UltimaCompra,
           DATEDIFF(DAY, ISNULL(MAX(CASE WHEN m.Tipo = 'Pago' THEN m.Fecha END), MIN(m.Fecha)), @hoy) AS DiasSinPagar
    FROM MovimientoCuentaCorriente m
    INNER JOIN Cliente c ON c.Id = m.IdCliente
    GROUP BY c.Id, c.Nombre, c.Apellido, c.Telefono
    HAVING SUM(m.Monto) > 0
    ORDER BY Saldo DESC;

    -- RS5
    SELECT
        COUNT(*) AS Creados,
        ISNULL(SUM(CASE WHEN e.Estado = 'ENTREGADO' THEN 1 ELSE 0 END), 0) AS Entregados,
        ISNULL(SUM(CASE WHEN e.Estado = 'CANCELADO' THEN 1 ELSE 0 END), 0) AS Cancelados,
        ISNULL(SUM(CASE WHEN e.Estado IN ('PENDIENTE', 'AVISADO') THEN 1 ELSE 0 END), 0) AS Abiertos,
        CAST(AVG(CASE WHEN e.Estado = 'ENTREGADO' THEN DATEDIFF(HOUR, e.Fecha, e.FechaEntrega) / 24.0 END) AS DECIMAL(6,1)) AS DiasHastaEntrega,
        ISNULL(SUM(s.Senas), 0) AS Senas,
        ISNULL(SUM(CASE WHEN e.ResolucionSena = 'RETENIDA' THEN s.Senas ELSE 0 END), 0) AS SenasRetenidas
    FROM Encargo e
    LEFT JOIN (SELECT IdEncargo, SUM(Monto) AS Senas FROM EncargoSena GROUP BY IdEncargo) s ON s.IdEncargo = e.Id
    WHERE e.Fecha >= @Desde AND e.Fecha < @HastaExcl;

    -- RS6
    SELECT CASE WHEN n = 1 THEN '1 vez' WHEN n <= 3 THEN '2 a 3 veces' WHEN n <= 9 THEN '4 a 9 veces' ELSE '10 o más' END AS Frecuencia,
           MIN(n) AS Orden, COUNT(*) AS Clientes, SUM(Importe) AS Importe
    FROM (SELECT IdCliente, COUNT(*) AS n, SUM(Total) AS Importe FROM #V WHERE ConNombre = 1 GROUP BY IdCliente) x
    GROUP BY CASE WHEN n = 1 THEN '1 vez' WHEN n <= 3 THEN '2 a 3 veces' WHEN n <= 9 THEN '4 a 9 veces' ELSE '10 o más' END
    ORDER BY Orden;

    DROP TABLE #V;
END
GO


/* =================================================================
   12. STOCK (foto de hoy; ventas de los ultimos 90 y 365 dias)
   RS1 Resumen   RS2 Se vende y no hay   RS3 Plata parada
   RS4 Dias que alcanza   RS5 Rotacion por rubro
   ================================================================= */
IF OBJECT_ID('SP_Tablero_Stock', 'P') IS NOT NULL DROP PROCEDURE SP_Tablero_Stock;
GO
CREATE PROCEDURE SP_Tablero_Stock
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @hoy DATE = CAST(GETDATE() AS DATE);

    SELECT IdRepuesto,
           SUM(CASE WHEN Dia > DATEADD(DAY, -90, @hoy) THEN Unidades ELSE 0 END) AS U90,
           SUM(CASE WHEN Dia > DATEADD(DAY, -365, @hoy) THEN Costo ELSE 0 END) AS Costo365,
           MAX(CASE WHEN Origen = 'VENTA' THEN Fecha END) AS UltimaVenta
    INTO #Vt
    FROM vw_VentaLinea
    GROUP BY IdRepuesto;

    SELECT r.Id, r.Codigo, r.Descripcion, ISNULL(ru.Nombre, N'Sin rubro') AS Rubro,
           ISNULL(st.Cantidad, 0) AS Stock, ISNULL(st.Minimo, 0) AS StockMinimo,
           ISNULL(rs.Reservado, 0) AS Reservado, ISNULL(rs.Encargos, 0) AS Encargos,
           ISNULL(r.PrecioCompra, 0) AS Costo, r.FechaUltimaCompra,
           ISNULL(v.U90, 0) AS U90, ISNULL(v.Costo365, 0) AS Costo365, v.UltimaVenta
    INTO #S
    FROM Repuesto r
    LEFT JOIN Rubro ru ON ru.Id = r.IdRubro
    LEFT JOIN (SELECT IdRepuesto, SUM(Cantidad) AS Cantidad, MAX(StockMinimo) AS Minimo FROM Stock GROUP BY IdRepuesto) st ON st.IdRepuesto = r.Id
    LEFT JOIN vw_StockReservado rs ON rs.IdRepuesto = r.Id
    LEFT JOIN #Vt v ON v.IdRepuesto = r.Id
    WHERE r.Activo = 1;

    -- RS1
    SELECT
        SUM(CASE WHEN Stock > 0 THEN 1 ELSE 0 END) AS ArticulosConStock,
        SUM(CASE WHEN Stock > 0 THEN Stock * Costo ELSE 0 END) AS ValorStock,
        SUM(CASE WHEN Stock > 0 AND Costo = 0 THEN 1 ELSE 0 END) AS ArticulosSinCosto,
        SUM(CASE WHEN Stock > 0 AND (UltimaVenta IS NULL OR UltimaVenta < DATEADD(DAY, -180, @hoy)) THEN Stock * Costo ELSE 0 END) AS ValorInmovilizado,
        SUM(CASE WHEN Stock > 0 AND (UltimaVenta IS NULL OR UltimaVenta < DATEADD(DAY, -180, @hoy)) THEN 1 ELSE 0 END) AS ArticulosInmovilizados,
        SUM(CASE WHEN Stock - Reservado <= 0 AND U90 >= 1 THEN 1 ELSE 0 END) AS Quiebres,
        SUM(CASE WHEN StockMinimo > 0 AND Stock < StockMinimo THEN 1 ELSE 0 END) AS BajoMinimo,
        SUM(CASE WHEN U90 > 0 AND Stock - Reservado > 0 AND (Stock - Reservado) / (U90 / 90.0) > 180
                 THEN (Stock - Reservado - CEILING(U90 * 2.0)) * Costo ELSE 0 END) AS ValorExceso
    FROM #S;

    -- RS2
    SELECT TOP 100 Id, Codigo, Descripcion, Rubro, Stock, Reservado, Encargos, U90, UltimaVenta, Costo
    FROM #S
    WHERE Stock - Reservado <= 0 AND U90 >= 1
    ORDER BY U90 DESC, Encargos DESC;

    -- RS3
    SELECT TOP 150 Id, Codigo, Descripcion, Rubro, Stock, Costo, CAST(Stock * Costo AS DECIMAL(14,2)) AS Valor,
           UltimaVenta, FechaUltimaCompra
    FROM #S
    WHERE Stock > 0 AND (UltimaVenta IS NULL OR UltimaVenta < DATEADD(DAY, -180, @hoy))
    ORDER BY Stock * Costo DESC;

    -- RS4
    SELECT TOP 400 Id, Codigo, Descripcion, Rubro, Stock, Reservado, U90,
           CAST(CASE WHEN Stock - Reservado <= 0 THEN 0 ELSE (Stock - Reservado) / (U90 / 90.0) END AS DECIMAL(8,1)) AS DiasQueAlcanza,
           Costo
    FROM #S
    WHERE U90 > 0
    ORDER BY U90 DESC;

    -- RS5
    SELECT Rubro,
           SUM(CASE WHEN Stock > 0 THEN Stock * Costo ELSE 0 END) AS ValorStock,
           SUM(Costo365) AS CostoVendidoAnio,
           CAST(CASE WHEN SUM(CASE WHEN Stock > 0 THEN Stock * Costo ELSE 0 END) > 0
                     THEN SUM(Costo365) / SUM(CASE WHEN Stock > 0 THEN Stock * Costo ELSE 0 END) END AS DECIMAL(8,2)) AS VueltasPorAnio
    FROM #S
    GROUP BY Rubro
    HAVING SUM(CASE WHEN Stock > 0 THEN Stock * Costo ELSE 0 END) > 0 OR SUM(Costo365) > 0
    ORDER BY ValorStock DESC;

    DROP TABLE #S;
    DROP TABLE #Vt;
END
GO


/* =================================================================
   13. RENTABILIDAD
   RS1 Mes a mes (12 meses): ventas, ganancia, gastos, comisiones, resultado
   RS2 Gastos por tipo, contra el periodo anterior
   RS3 Totales del periodo y del anterior
   ================================================================= */
IF OBJECT_ID('SP_Tablero_Rentabilidad', 'P') IS NOT NULL DROP PROCEDURE SP_Tablero_Rentabilidad;
GO
CREATE PROCEDURE SP_Tablero_Rentabilidad
    @Desde DATE,
    @Hasta DATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @dias INT = DATEDIFF(DAY, @Desde, @Hasta) + 1;
    DECLARE @antDesde DATE = DATEADD(DAY, -@dias, @Desde);
    DECLARE @antHasta DATE = DATEADD(DAY, -1, @Desde);

    -- RS1
    SELECT m.Mes, p.Ventas, p.CostoVendido, p.Ganancia, p.Gastos, p.Comisiones,
           CAST(p.Ganancia - p.Gastos - p.Comisiones AS DECIMAL(14,2)) AS Resultado
    FROM dbo.fn_TableroMeses(12) m
    CROSS APPLY dbo.fn_TableroPeriodo(m.Mes, EOMONTH(m.Mes)) p
    ORDER BY m.Mes;

    -- RS2
    SELECT t.Nombre AS Tipo, t.Categoria,
           SUM(CASE WHEN g.Fecha BETWEEN @Desde AND @Hasta THEN g.Importe ELSE 0 END) AS Importe,
           SUM(CASE WHEN g.Fecha BETWEEN @antDesde AND @antHasta THEN g.Importe ELSE 0 END) AS ImporteAnterior
    FROM Gasto g
    INNER JOIN TipoGasto t ON t.Id = g.IdTipoGasto
    WHERE g.Estado <> 'ANULADO' AND g.Fecha BETWEEN @antDesde AND @Hasta
    GROUP BY t.Nombre, t.Categoria
    ORDER BY Importe DESC;

    -- RS3
    SELECT 'ACTUAL' AS Periodo, @Desde AS Desde, @Hasta AS Hasta, a.*,
           dbo.fn_CostosFijosMensuales() AS CostosFijosMensuales
    FROM dbo.fn_TableroPeriodo(@Desde, @Hasta) a
    UNION ALL
    SELECT 'ANTERIOR', @antDesde, @antHasta, b.*, dbo.fn_CostosFijosMensuales()
    FROM dbo.fn_TableroPeriodo(@antDesde, @antHasta) b;
END
GO


/* -----------------------------------------------------------------
   PRUEBAS (solo lectura)
   ----------------------------------------------------------------- */
DECLARE @d DATE = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1), @h DATE = CAST(GETDATE() AS DATE);
DECLARE @d12 DATE = DATEADD(MONTH, -11, @d);
EXEC SP_Tablero_Resumen @Desde = @d, @Hasta = @h;
EXEC SP_Tablero_Ventas @Desde = @d12, @Hasta = @h;
EXEC SP_Tablero_Productos @Desde = @d12, @Hasta = @h;
EXEC SP_Tablero_Proveedores @Desde = @d12, @Hasta = @h;
EXEC SP_Tablero_Clientes @Desde = @d12, @Hasta = @h;
EXEC SP_Tablero_Stock;
EXEC SP_Tablero_Rentabilidad @Desde = @d, @Hasta = @h;
GO
