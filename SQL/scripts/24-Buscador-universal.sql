USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   24 — BUSCADOR UNIVERSAL
   Tramo 1A del centralizador.

   Responde la pregunta del mostrador: "¿lo tenemos, o podemos
   conseguirlo, de quien y a cuanto?".

   DOS RESULTADOS SEPARADOS, NO UNA LISTA MEZCLADA

   "Lo tengo" y "lo podria conseguir" son afirmaciones de naturaleza
   distinta. Mezclarlas en una sola lista ordenada obliga al vendedor
   a leer para distinguirlas, que es justo lo que no tiene tiempo de
   hacer con un cliente enfrente.

   Por eso el SP devuelve DOS tablas:
     1. Lo que hay en el catalogo propio, con su stock
     2. Lo que ofrecen los proveedores

   ADVERTENCIA SOBRE LA COMPARACION

   Solo se pueden comparar costos entre articulos que apuntan al
   mismo Repuesto. Dos filas de proveedores distintos que parecen la
   misma pieza pero no estan enlazadas NO son comparables: pueden ser
   marcas o calidades diferentes. El SP marca esa diferencia y la
   pantalla tiene que respetarla.
   ================================================================= */

IF OBJECT_ID('SP_Busqueda_Universal', 'P') IS NOT NULL DROP PROCEDURE SP_Busqueda_Universal;
GO

CREATE PROCEDURE SP_Busqueda_Universal
    @Texto        VARCHAR(200),
    @IdProveedor  INT = NULL,      -- NULL = todos
    @SoloConStock BIT = 0,
    @Tope         INT = 60
AS
BEGIN
    SET NOCOUNT ON;

    IF @Tope IS NULL OR @Tope <= 0 SET @Tope = 60;
    IF @Tope > 200 SET @Tope = 200;

    -- La consulta pasa por el mismo molde que los datos, o no matchea
    DECLARE @busca VARCHAR(400) = dbo.fn_NormalizarBusqueda(@Texto);

    IF @busca IS NULL OR LEN(@busca) < 3
    BEGIN
        SELECT TOP 0 CAST(NULL AS INT) AS Id;   -- resultado vacio, dos tablas
        SELECT TOP 0 CAST(NULL AS INT) AS Id;
        RETURN;
    END

    /* Se parte la consulta en palabras y se exige que TODAS aparezcan.
       "bomba agua suran" no debe traer todas las bombas ni todos los
       Suran: solo lo que tiene las tres. */
    DECLARE @p1 VARCHAR(60), @p2 VARCHAR(60), @p3 VARCHAR(60), @p4 VARCHAR(60);
    DECLARE @resto VARCHAR(400) = @busca + ' ';

    SET @p1 = NULLIF(LEFT(@resto, CHARINDEX(' ', @resto) - 1), '');
    SET @resto = LTRIM(SUBSTRING(@resto, CHARINDEX(' ', @resto) + 1, 400));
    IF LEN(@resto) > 0 SET @p2 = NULLIF(LEFT(@resto + ' ', CHARINDEX(' ', @resto + ' ') - 1), '');
    SET @resto = LTRIM(SUBSTRING(@resto, CHARINDEX(' ', @resto + ' ') + 1, 400));
    IF LEN(@resto) > 0 SET @p3 = NULLIF(LEFT(@resto + ' ', CHARINDEX(' ', @resto + ' ') - 1), '');
    SET @resto = LTRIM(SUBSTRING(@resto, CHARINDEX(' ', @resto + ' ') + 1, 400));
    IF LEN(@resto) > 0 SET @p4 = NULLIF(LEFT(@resto + ' ', CHARINDEX(' ', @resto + ' ') - 1), '');


    /* =============== 1. LO QUE TENGO =============== */

    SELECT TOP (@Tope)
        r.Id,
        r.Codigo,
        r.Descripcion,
        r.CodigoFabricante,
        r.MarcaFabricante,
        r.AplicacionTexto,
        ISNULL(ru.Nombre, '-')      AS Rubro,
        ISNULL(s.Cantidad, 0)       AS Stock,
        ISNULL(s.StockMinimo, 0)    AS StockMinimo,
        r.PrecioCompra,
        r.PrecioDeVenta,

        CASE WHEN ISNULL(s.Cantidad, 0) <= 0                    THEN 'SinStock'
             WHEN ISNULL(s.Cantidad, 0) <= ISNULL(s.StockMinimo, 0) THEN 'Critico'
             ELSE 'OK' END          AS EstadoStock,

        -- Cuantos proveedores lo ofrecen hoy
        (SELECT COUNT(*) FROM ProveedorRepuesto pr
         WHERE pr.IdRepuesto = r.Id AND pr.Activo = 1 AND pr.PrecioCompra > 0)
                                    AS ProveedoresDisponibles,

        -- El costo mas barato entre los que SI son el mismo repuesto
        (SELECT MIN(pr.PrecioCompra) FROM ProveedorRepuesto pr
         WHERE pr.IdRepuesto = r.Id AND pr.Activo = 1 AND pr.PrecioCompra > 0)
                                    AS MejorCosto,

        (SELECT TOP 1 p.RazonSocial
         FROM ProveedorRepuesto pr
         INNER JOIN Proveedor p ON p.Id = pr.IdProveedor
         WHERE pr.IdRepuesto = r.Id AND pr.Activo = 1 AND pr.PrecioCompra > 0
         ORDER BY pr.PrecioCompra)  AS MejorProveedor

    FROM Repuesto r
    LEFT JOIN Rubro ru ON ru.Id = r.IdRubro
    LEFT JOIN Stock s  ON s.IdRepuesto = r.Id
    WHERE r.Activo = 1
      AND (@SoloConStock = 0 OR ISNULL(s.Cantidad, 0) > 0)
      AND (@p1 IS NULL OR r.TextoBusqueda LIKE '%' + @p1 + '%')
      AND (@p2 IS NULL OR r.TextoBusqueda LIKE '%' + @p2 + '%')
      AND (@p3 IS NULL OR r.TextoBusqueda LIKE '%' + @p3 + '%')
      AND (@p4 IS NULL OR r.TextoBusqueda LIKE '%' + @p4 + '%')
    ORDER BY
        -- Primero lo que se puede vender ahora mismo
        CASE WHEN ISNULL(s.Cantidad, 0) > 0 THEN 0 ELSE 1 END,
        r.Descripcion;


    /* =============== 2. LO QUE PUEDO CONSEGUIR =============== */

    DECLARE @MargenGeneral DECIMAL(6,2) =
        ISNULL(TRY_CAST((SELECT Valor FROM ParametroSistema WHERE Clave = 'MargenGeneral')
                        AS DECIMAL(6,2)), 50);

    SELECT TOP (@Tope)
        pr.Id,
        pr.IdProveedor,
        p.RazonSocial           AS Proveedor,
        pr.CodigoProveedor,
        pr.Articulo,
        pr.Descripcion,
        pr.RubroTexto,
        ISNULL(ru.Nombre, pr.RubroTexto) AS Rubro,
        pr.PrecioCompra,

        CAST(pr.PrecioCompra * (1 + ISNULL(ru.MargenPorcentaje, @MargenGeneral) / 100.0)
             * 1.21 AS DECIMAL(12,2)) AS PrecioSugerido,

        pr.IdRepuesto,
        rep.Codigo              AS CodigoPropio,
        ISNULL(st.Cantidad, 0)  AS StockPropio,

        /* Enlazado: se sabe con certeza que es el mismo repuesto, asi
           que su costo ES comparable con el de otros proveedores.
           Sin enlazar: aparece porque el texto coincide, pero podria
           ser otra marca u otra calidad. */
        CASE WHEN pr.IdRepuesto IS NOT NULL THEN 1 ELSE 0 END AS Comparable,

        -- Ranking de costo, solo entre los enlazados al mismo repuesto
        CASE WHEN pr.IdRepuesto IS NULL THEN NULL
             ELSE RANK() OVER (PARTITION BY pr.IdRepuesto ORDER BY pr.PrecioCompra)
        END AS RankingCosto

    FROM ProveedorRepuesto pr
    INNER JOIN Proveedor p ON p.Id = pr.IdProveedor
    LEFT JOIN Rubro ru     ON ru.Id = pr.IdRubro
    LEFT JOIN Repuesto rep ON rep.Id = pr.IdRepuesto
    LEFT JOIN Stock st     ON st.IdRepuesto = pr.IdRepuesto
    WHERE pr.Activo = 1
      AND pr.PrecioCompra > 0
      AND (@IdProveedor IS NULL OR pr.IdProveedor = @IdProveedor)
      AND (@p1 IS NULL OR pr.TextoBusqueda LIKE '%' + @p1 + '%')
      AND (@p2 IS NULL OR pr.TextoBusqueda LIKE '%' + @p2 + '%')
      AND (@p3 IS NULL OR pr.TextoBusqueda LIKE '%' + @p3 + '%')
      AND (@p4 IS NULL OR pr.TextoBusqueda LIKE '%' + @p4 + '%')
    ORDER BY
        -- Los que ya son parte del catalogo primero: de esos se sabe todo
        CASE WHEN pr.IdRepuesto IS NOT NULL THEN 0 ELSE 1 END,
        pr.PrecioCompra;
END
GO


/* -----------------------------------------------------------------
   OPORTUNIDADES DE AHORRO

   El objetivo economico del modulo: descubrir que un repuesto que se
   compra habitualmente a un proveedor esta mas barato en otro.

   No se almacena nada: se deriva de las listas vigentes.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Ahorro_Oportunidades', 'P') IS NOT NULL DROP PROCEDURE SP_Ahorro_Oportunidades;
GO

CREATE PROCEDURE SP_Ahorro_Oportunidades
    @DiferenciaMinima DECIMAL(6,2) = 5    -- % a partir del cual vale la pena
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Costos AS (
        SELECT
            pr.IdRepuesto,
            pr.IdProveedor,
            p.RazonSocial,
            pr.PrecioCompra,
            RANK() OVER (PARTITION BY pr.IdRepuesto ORDER BY pr.PrecioCompra) AS rk
        FROM ProveedorRepuesto pr
        INNER JOIN Proveedor p ON p.Id = pr.IdProveedor
        WHERE pr.IdRepuesto IS NOT NULL
          AND pr.Activo = 1
          AND pr.PrecioCompra > 0
    )
    SELECT
        r.Id            AS IdRepuesto,
        r.Codigo,
        r.Descripcion,
        r.PrecioCompra  AS CostoActual,
        barato.RazonSocial AS ProveedorMasBarato,
        barato.PrecioCompra AS MejorCosto,
        r.PrecioCompra - barato.PrecioCompra AS DiferenciaUnitaria,
        CAST((r.PrecioCompra - barato.PrecioCompra) / NULLIF(r.PrecioCompra, 0) * 100
             AS DECIMAL(6,2)) AS DiferenciaPorc,

        -- Cuanto se dejo de ganar en lo que ya se vendio
        (SELECT ISNULL(SUM(dv.Cantidad), 0)
         FROM DetalleVenta dv
         INNER JOIN Venta v ON v.Id = dv.IdVenta AND v.IdEstadoVenta = 1
         WHERE dv.IdRepuesto = r.Id
           AND v.Fecha >= DATEADD(DAY, -120, GETDATE())) AS VendidasUltimos120,

        CAST((r.PrecioCompra - barato.PrecioCompra) *
             (SELECT ISNULL(SUM(dv.Cantidad), 0)
              FROM DetalleVenta dv
              INNER JOIN Venta v ON v.Id = dv.IdVenta AND v.IdEstadoVenta = 1
              WHERE dv.IdRepuesto = r.Id
                AND v.Fecha >= DATEADD(DAY, -120, GETDATE()))
             AS DECIMAL(12,2)) AS AhorroPotencial

    FROM Repuesto r
    INNER JOIN Costos barato ON barato.IdRepuesto = r.Id AND barato.rk = 1
    WHERE r.Activo = 1
      AND r.PrecioCompra > 0
      AND barato.PrecioCompra < r.PrecioCompra
      AND (r.PrecioCompra - barato.PrecioCompra) / r.PrecioCompra * 100 >= @DiferenciaMinima
    ORDER BY AhorroPotencial DESC, DiferenciaPorc DESC;
END
GO


/* -----------------------------------------------------------------
   COBERTURA DEL CENTRALIZADOR

   La metrica que dice si el modulo sirve. No se mide sobre el
   catalogo total sino sobre lo que realmente se vende: si con el 35%
   de los repuestos se cubre el 70% de las lineas de venta, ya aporta.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Centralizador_Cobertura', 'P') IS NOT NULL
    DROP PROCEDURE SP_Centralizador_Cobertura;
GO

CREATE PROCEDURE SP_Centralizador_Cobertura
    @Dias INT = 120
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @desde DATETIME = DATEADD(DAY, -@Dias, GETDATE());

    ;WITH Activos AS (
        SELECT DISTINCT dv.IdRepuesto
        FROM DetalleVenta dv
        INNER JOIN Venta v ON v.Id = dv.IdVenta AND v.IdEstadoVenta = 1
        WHERE v.Fecha >= @desde
    ),
    Lineas AS (
        SELECT dv.IdRepuesto, COUNT(*) AS Cant
        FROM DetalleVenta dv
        INNER JOIN Venta v ON v.Id = dv.IdVenta AND v.IdEstadoVenta = 1
        WHERE v.Fecha >= @desde
        GROUP BY dv.IdRepuesto
    )
    SELECT
        (SELECT COUNT(*) FROM Repuesto WHERE Activo = 1)          AS CatalogoTotal,
        (SELECT COUNT(*) FROM Activos)                            AS CatalogoActivo,

        (SELECT COUNT(DISTINCT a.IdRepuesto) FROM Activos a
         WHERE EXISTS (SELECT 1 FROM ProveedorRepuesto pr
                       WHERE pr.IdRepuesto = a.IdRepuesto AND pr.Activo = 1))
                                                                  AS ActivosVinculados,

        CAST(100.0 * (SELECT COUNT(DISTINCT a.IdRepuesto) FROM Activos a
                      WHERE EXISTS (SELECT 1 FROM ProveedorRepuesto pr
                                    WHERE pr.IdRepuesto = a.IdRepuesto AND pr.Activo = 1))
             / NULLIF((SELECT COUNT(*) FROM Activos), 0) AS DECIMAL(6,2))
                                                                  AS PorcSKUCubierto,

        -- La metrica que importa: porcentaje de LINEAS de venta cubiertas
        CAST(100.0 * (SELECT ISNULL(SUM(l.Cant), 0) FROM Lineas l
                      WHERE EXISTS (SELECT 1 FROM ProveedorRepuesto pr
                                    WHERE pr.IdRepuesto = l.IdRepuesto AND pr.Activo = 1))
             / NULLIF((SELECT SUM(Cant) FROM Lineas), 0) AS DECIMAL(6,2))
                                                                  AS PorcLineasCubierto;
END
GO


/* -----------------------------------------------------------------
   PRUEBAS
   ----------------------------------------------------------------- */
EXEC SP_Busqueda_Universal @Texto = 'bomba agua';
GO
EXEC SP_Busqueda_Universal @Texto = 'abraz 8-12';
GO
EXEC SP_Ahorro_Oportunidades;
GO
EXEC SP_Centralizador_Cobertura;
GO
