USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   80 — COSTOS FIJOS COMO LISTA

   Antes los costos fijos eran un solo numero (CostosFijosMensuales)
   escrito a mano. Ahora son una lista: alquiler, luz, sueldos,
   contador... con su monto mensual. El punto de equilibrio usa la
   suma de la lista.

   Cada costo se puede asociar a un tipo de gasto del modulo de
   Gastos. Asi la pantalla sugiere cuanto se pago en promedio los
   ultimos 3 meses, y propone agregar los gastos que se repiten y
   todavia no estan en la lista. El monto lo decide la persona.

   El valor unico anterior, si tenia algo, entra como primer renglon
   para no perderlo.
   ================================================================= */


/* -----------------------------------------------------------------
   1. Tabla
   ----------------------------------------------------------------- */
IF OBJECT_ID('CostoFijo', 'U') IS NULL
BEGIN
    CREATE TABLE CostoFijo (
        Id            INT IDENTITY(1,1) PRIMARY KEY,
        Concepto      NVARCHAR(80)  NOT NULL,
        IdTipoGasto   INT           NULL REFERENCES TipoGasto(Id),
        MontoMensual  DECIMAL(12,2) NOT NULL,
        Activo        BIT           NOT NULL DEFAULT 1,
        FechaAlta     DATETIME      NOT NULL DEFAULT GETDATE(),
        CONSTRAINT CK_CostoFijo_Monto CHECK (MontoMensual >= 0 AND MontoMensual <= 100000000)
    );

    DECLARE @anterior DECIMAL(12,2) =
        TRY_CAST((SELECT Valor FROM ParametroSistema WHERE Clave = 'CostosFijosMensuales') AS DECIMAL(12,2));
    IF ISNULL(@anterior, 0) > 0
        INSERT INTO CostoFijo (Concepto, MontoMensual) VALUES (N'Costos fijos (valor cargado antes)', @anterior);
END
GO


/* -----------------------------------------------------------------
   2. Lista, con lo pagado segun Gastos
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_CostoFijo_Listar', 'P') IS NOT NULL DROP PROCEDURE SP_CostoFijo_Listar;
GO
CREATE PROCEDURE SP_CostoFijo_Listar
AS
BEGIN
    SET NOCOUNT ON;

    -- Los ultimos 3 meses completos
    DECLARE @hasta DATE = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1);
    DECLARE @desde DATE = DATEADD(MONTH, -3, @hasta);

    ;WITH pagado AS (
        SELECT g.IdTipoGasto,
               CAST(SUM(g.Importe) / 3.0 AS DECIMAL(12,2)) AS PromedioMensual,
               MAX(g.Fecha) AS UltimaFecha
        FROM Gasto g
        WHERE g.Estado <> 'ANULADO' AND g.Fecha >= @desde AND g.Fecha < @hasta
        GROUP BY g.IdTipoGasto
    )
    SELECT c.Id, c.Concepto, c.IdTipoGasto, t.Nombre AS TipoGasto, c.MontoMensual,
           p.PromedioMensual, p.UltimaFecha
    FROM CostoFijo c
    LEFT JOIN TipoGasto t ON t.Id = c.IdTipoGasto
    LEFT JOIN pagado p    ON p.IdTipoGasto = c.IdTipoGasto
    WHERE c.Activo = 1
    ORDER BY c.MontoMensual DESC, c.Concepto;

    -- Gastos que se repiten (aparecen en 2 de los 3 meses) y no estan en la lista
    SELECT t.Id AS IdTipoGasto, t.Nombre AS TipoGasto,
           CAST(SUM(g.Importe) / 3.0 AS DECIMAL(12,2)) AS PromedioMensual,
           COUNT(DISTINCT DATEFROMPARTS(YEAR(g.Fecha), MONTH(g.Fecha), 1)) AS Meses
    FROM Gasto g
    INNER JOIN TipoGasto t ON t.Id = g.IdTipoGasto
    WHERE g.Estado <> 'ANULADO' AND g.Fecha >= @desde AND g.Fecha < @hasta
      AND NOT EXISTS (SELECT 1 FROM CostoFijo c WHERE c.Activo = 1 AND c.IdTipoGasto = t.Id)
    GROUP BY t.Id, t.Nombre
    HAVING COUNT(DISTINCT DATEFROMPARTS(YEAR(g.Fecha), MONTH(g.Fecha), 1)) >= 2
    ORDER BY SUM(g.Importe) DESC;
END
GO


/* -----------------------------------------------------------------
   3. Alta o cambio
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_CostoFijo_Guardar', 'P') IS NOT NULL DROP PROCEDURE SP_CostoFijo_Guardar;
GO
CREATE PROCEDURE SP_CostoFijo_Guardar
    @Id           INT = NULL,
    @Concepto     NVARCHAR(80),
    @IdTipoGasto  INT = NULL,
    @MontoMensual DECIMAL(12,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET @Concepto = LTRIM(RTRIM(ISNULL(@Concepto, '')));

    IF @Concepto = ''
        THROW 50301, 'Escribí el concepto (por ejemplo: Alquiler).', 1;
    IF @MontoMensual IS NULL OR @MontoMensual < 0 OR @MontoMensual > 100000000
        THROW 50302, 'El monto mensual no es válido.', 1;
    IF @IdTipoGasto IS NOT NULL AND NOT EXISTS (SELECT 1 FROM TipoGasto WHERE Id = @IdTipoGasto)
        THROW 50303, 'El tipo de gasto no existe.', 1;
    IF EXISTS (SELECT 1 FROM CostoFijo WHERE Activo = 1 AND Concepto = @Concepto AND Id <> ISNULL(@Id, 0))
        THROW 50304, 'Ya hay un costo fijo con ese concepto.', 1;

    IF @Id IS NULL
    BEGIN
        INSERT INTO CostoFijo (Concepto, IdTipoGasto, MontoMensual) VALUES (@Concepto, @IdTipoGasto, @MontoMensual);
        SET @Id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM CostoFijo WHERE Id = @Id AND Activo = 1)
            THROW 50305, 'El costo fijo no existe.', 1;
        UPDATE CostoFijo SET Concepto = @Concepto, IdTipoGasto = @IdTipoGasto, MontoMensual = @MontoMensual
        WHERE Id = @Id;
    END

    SELECT @Id AS Id;
END
GO


/* -----------------------------------------------------------------
   4. Quitar (baja logica)
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_CostoFijo_Quitar', 'P') IS NOT NULL DROP PROCEDURE SP_CostoFijo_Quitar;
GO
CREATE PROCEDURE SP_CostoFijo_Quitar
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE CostoFijo SET Activo = 0 WHERE Id = @Id;
END
GO


/* -----------------------------------------------------------------
   5. Nombres claros para los parametros (los muestra la pantalla)
   ----------------------------------------------------------------- */
UPDATE ParametroSistema SET Descripcion = N'Descuento fijo para clientes marcados como mecánico.' WHERE Clave = 'DescuentoMecanico';
UPDATE ParametroSistema SET Descripcion = N'Botones de descuento rápido en la venta al público.' WHERE Clave = 'DescuentosPublico';
UPDATE ParametroSistema SET Descripcion = N'Cuántos días vale un presupuesto.' WHERE Clave = 'DiasValidezPresupuesto';
-- El valor unico queda solo como respaldo: ahora manda la lista
UPDATE ParametroSistema SET Editable = 0 WHERE Clave = 'CostosFijosMensuales';
GO


/* -----------------------------------------------------------------
   6. Punto de equilibrio con la suma de la lista
      (misma definicion que el script 58, cambia de donde salen los
      costos fijos)
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

    -- Costos fijos: la suma de la lista de Configuracion (script 80).
    -- Si la lista esta vacia, se usa el valor unico que habia antes.
    DECLARE @CostosFijos DECIMAL(12,2) =
        CASE WHEN EXISTS (SELECT 1 FROM CostoFijo WHERE Activo = 1)
             THEN (SELECT SUM(MontoMensual) FROM CostoFijo WHERE Activo = 1)
             ELSE ISNULL(TRY_CAST((SELECT Valor FROM ParametroSistema WHERE Clave = 'CostosFijosMensuales')
                                  AS DECIMAL(12,2)), 0) END;

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


/* PRUEBA (no modifica nada) */
EXEC SP_CostoFijo_Listar;
EXEC SP_Reporte_PuntoEquilibrio;
GO
