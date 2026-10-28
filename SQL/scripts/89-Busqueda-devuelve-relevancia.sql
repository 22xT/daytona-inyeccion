/* =================================================================
   89 — LA BUSQUEDA DEVUELVE LA RELEVANCIA (28/10)

   El script 88 ordena por relevancia; este hace que la API ademas
   la DEVUELVA (columna Relevancia) en las dos tablas del buscador:
     0 coincide por codigo
     1 es la pieza buscada (la descripcion empieza con la palabra o
       el rubro la nombra)
     2 las palabras aparecen juntas (accesorios: "ORING BOMBA AGUA")
     3 las nombra de pasada
   Con eso la pantalla separa "lo que buscas" de "relacionados" y el
   resumen dice "desde $X" con el precio de la pieza, no del accesorio.

   Requiere el script 88 (fn_BusquedaRelevancia). No toca datos.
   ================================================================= */
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID('SP_Busqueda_Universal', 'P') IS NOT NULL DROP PROCEDURE SP_Busqueda_Universal;
GO
CREATE PROCEDURE SP_Busqueda_Universal
    @Texto        VARCHAR(200),
    @IdProveedor  INT = NULL,
    @SoloConStock BIT = 0,
    @Tope         INT = 60
AS
BEGIN
    SET NOCOUNT ON;

    IF @Tope IS NULL OR @Tope <= 0 SET @Tope = 60;
    IF @Tope > 200 SET @Tope = 200;

    DECLARE @busca VARCHAR(400) = dbo.fn_NormalizarBusqueda(@Texto);

    IF @busca IS NULL OR LEN(@busca) < 3
    BEGIN
        SELECT TOP 0 CAST(NULL AS INT) AS Id;
        SELECT TOP 0 CAST(NULL AS INT) AS Id;
        RETURN;
    END

    /* Hasta cuatro palabras. Se exige que TODAS aparezcan: buscar
       "bomba agua suran" no debe traer todas las bombas. */
    DECLARE @p1 VARCHAR(60), @p2 VARCHAR(60), @p3 VARCHAR(60), @p4 VARCHAR(60);
    DECLARE @resto VARCHAR(400) = @busca + ' ';

    SET @p1 = NULLIF(LEFT(@resto, CHARINDEX(' ', @resto) - 1), '');
    SET @resto = LTRIM(SUBSTRING(@resto, CHARINDEX(' ', @resto) + 1, 400));
    IF LEN(@resto) > 0 SET @p2 = NULLIF(LEFT(@resto + ' ', CHARINDEX(' ', @resto + ' ') - 1), '');
    SET @resto = LTRIM(SUBSTRING(@resto, CHARINDEX(' ', @resto + ' ') + 1, 400));
    IF LEN(@resto) > 0 SET @p3 = NULLIF(LEFT(@resto + ' ', CHARINDEX(' ', @resto + ' ') - 1), '');
    SET @resto = LTRIM(SUBSTRING(@resto, CHARINDEX(' ', @resto + ' ') + 1, 400));
    IF LEN(@resto) > 0 SET @p4 = NULLIF(LEFT(@resto + ' ', CHARINDEX(' ', @resto + ' ') - 1), '');

    -- Version sin separadores de cada palabra, para buscar en codigos
    DECLARE @c1 VARCHAR(60) = dbo.fn_LimpiarCodigo(ISNULL(@p1, ''));
    DECLARE @c2 VARCHAR(60) = dbo.fn_LimpiarCodigo(ISNULL(@p2, ''));
    DECLARE @c3 VARCHAR(60) = dbo.fn_LimpiarCodigo(ISNULL(@p3, ''));
    DECLARE @c4 VARCHAR(60) = dbo.fn_LimpiarCodigo(ISNULL(@p4, ''));

    -- Solo se busca en codigos si la palabra tiene algun digito
    DECLARE @n1 BIT = CASE WHEN @c1 LIKE '%[0-9]%' THEN 1 ELSE 0 END;
    DECLARE @n2 BIT = CASE WHEN @c2 LIKE '%[0-9]%' THEN 1 ELSE 0 END;
    DECLARE @n3 BIT = CASE WHEN @c3 LIKE '%[0-9]%' THEN 1 ELSE 0 END;
    DECLARE @n4 BIT = CASE WHEN @c4 LIKE '%[0-9]%' THEN 1 ELSE 0 END;

    /* El texto entero como un solo codigo: "ktb 341", "KTB-341" y
       "KTB341" son lo mismo. Si tiene algun numero y al menos 4
       caracteres, alcanza con que coincida el codigo. */
    DECLARE @todo VARCHAR(200) = dbo.fn_LimpiarCodigo(@Texto);
    DECLARE @esCod BIT = CASE WHEN @todo LIKE '%[0-9]%' AND LEN(@todo) >= 4 THEN 1 ELSE 0 END;


    /* =============== 1. LO QUE TENGO =============== */

    SELECT TOP (@Tope)
        r.Id, r.Codigo, r.Descripcion, r.CodigoFabricante, r.MarcaFabricante,
        r.AplicacionTexto,
        ISNULL(ru.Nombre, '-')      AS Rubro,
        ISNULL(s.Cantidad, 0)       AS Stock,
        ISNULL(s.StockMinimo, 0)    AS StockMinimo,
        r.PrecioCompra, r.PrecioDeVenta,
        CASE WHEN ISNULL(s.Cantidad, 0) <= 0                        THEN 'SinStock'
             WHEN ISNULL(s.Cantidad, 0) <= ISNULL(s.StockMinimo, 0) THEN 'Critico'
             ELSE 'OK' END          AS EstadoStock,
        (SELECT COUNT(*) FROM ProveedorRepuesto pr
         WHERE pr.IdRepuesto = r.Id AND pr.Activo = 1 AND pr.PrecioCompra > 0)
                                    AS ProveedoresDisponibles,
        (SELECT MIN(pr.PrecioCompra) FROM ProveedorRepuesto pr
         WHERE pr.IdRepuesto = r.Id AND pr.Activo = 1 AND pr.PrecioCompra > 0)
                                    AS MejorCosto,
        (SELECT TOP 1 p.RazonSocial FROM ProveedorRepuesto pr
         INNER JOIN Proveedor p ON p.Id = pr.IdProveedor
         WHERE pr.IdRepuesto = r.Id AND pr.Activo = 1 AND pr.PrecioCompra > 0
         ORDER BY pr.PrecioCompra)  AS MejorProveedor,
        /* Lo trabaja el local: tiene stock, un minimo, ventas, compras o
           encargos. Si no, es solo una ficha armada al vincular listas de
           proveedores (un "matcheo" a mano): no se muestra como del local. */
        CASE WHEN ISNULL(s.Cantidad, 0) > 0 OR ISNULL(s.StockMinimo, 0) > 0
               OR EXISTS (SELECT 1 FROM DetalleVenta dv WHERE dv.IdRepuesto = r.Id)
               OR EXISTS (SELECT 1 FROM DetallePedido dp INNER JOIN Pedido pe ON pe.Id = dp.IdPedido
                          WHERE dp.IdRepuesto = r.Id AND (dp.CantidadRecibida > 0 OR pe.IdEstado = 1))
               OR EXISTS (SELECT 1 FROM vw_StockReservado rv WHERE rv.IdRepuesto = r.Id)
             THEN 1 ELSE 0 END      AS EnLocal,
        /* 0 coincide por codigo · 1 es la pieza buscada · 2 palabras
           juntas · 3 las nombra de pasada (script 88/89) */
        CASE WHEN @esCod = 1 AND r.CodigosBusqueda LIKE '%' + @todo + '%' THEN 0
             ELSE dbo.fn_BusquedaRelevancia(r.TextoBusqueda, ru.Nombre, @p1, @p2, @p3, @p4)
        END                         AS Relevancia
    FROM Repuesto r
    LEFT JOIN Rubro ru ON ru.Id = r.IdRubro
    LEFT JOIN Stock s  ON s.IdRepuesto = r.Id
    WHERE r.Activo = 1
      AND (@SoloConStock = 0 OR ISNULL(s.Cantidad, 0) > 0)
      AND (
            ( (@esCod = 1 AND r.CodigosBusqueda LIKE '%' + @todo + '%')
       OR ( (@p1 IS NULL OR r.TextoBusqueda LIKE '%' + @p1 + '%'
           OR (@n1 = 1 AND r.CodigosBusqueda LIKE '%' + @c1 + '%'))
      AND (@p2 IS NULL OR r.TextoBusqueda LIKE '%' + @p2 + '%'
           OR (@n2 = 1 AND r.CodigosBusqueda LIKE '%' + @c2 + '%'))
      AND (@p3 IS NULL OR r.TextoBusqueda LIKE '%' + @p3 + '%'
           OR (@n3 = 1 AND r.CodigosBusqueda LIKE '%' + @c3 + '%'))
      AND (@p4 IS NULL OR r.TextoBusqueda LIKE '%' + @p4 + '%'
           OR (@n4 = 1 AND r.CodigosBusqueda LIKE '%' + @c4 + '%')) ) )
         -- O un articulo de proveedor VINCULADO a este repuesto coincide con
         -- la busqueda: si el proveedor lo encuentra, tu repuesto tambien
         OR EXISTS (SELECT 1 FROM ProveedorRepuesto px
                    WHERE px.IdRepuesto = r.Id AND px.Activo = 1
                  AND ( (@esCod = 1 AND px.CodigosBusqueda LIKE '%' + @todo + '%')
       OR ( (@p1 IS NULL OR px.TextoBusqueda LIKE '%' + @p1 + '%'
           OR (@n1 = 1 AND px.CodigosBusqueda LIKE '%' + @c1 + '%'))
      AND (@p2 IS NULL OR px.TextoBusqueda LIKE '%' + @p2 + '%'
           OR (@n2 = 1 AND px.CodigosBusqueda LIKE '%' + @c2 + '%'))
      AND (@p3 IS NULL OR px.TextoBusqueda LIKE '%' + @p3 + '%'
           OR (@n3 = 1 AND px.CodigosBusqueda LIKE '%' + @c3 + '%'))
      AND (@p4 IS NULL OR px.TextoBusqueda LIKE '%' + @p4 + '%'
           OR (@n4 = 1 AND px.CodigosBusqueda LIKE '%' + @c4 + '%')) ) )
)
          )
    ORDER BY
        Relevancia,
        CASE WHEN ISNULL(s.Cantidad, 0) > 0 THEN 0 ELSE 1 END,
        r.Descripcion;


    /* =============== 2. LO QUE PUEDO CONSEGUIR =============== */

    DECLARE @MargenGeneral DECIMAL(6,2) =
        ISNULL(TRY_CAST((SELECT Valor FROM ParametroSistema WHERE Clave = 'MargenGeneral')
                        AS DECIMAL(6,2)), 50);

    SELECT TOP (@Tope)
        pr.Id, pr.IdProveedor, p.RazonSocial AS Proveedor,
        pr.CodigoProveedor, pr.Articulo, pr.Descripcion, pr.RubroTexto,
        ISNULL(ru.Nombre, pr.RubroTexto) AS Rubro,
        pr.PrecioCompra,
        -- Proveedor que factura con IVA: costo + margen, y el IVA arriba.
        -- Proveedor que no (TAC): costo + margen ya es el precio final.
        CAST(pr.PrecioCompra * (1 + ISNULL(ru.MargenPorcentaje, @MargenGeneral) / 100.0)
             * CASE WHEN p.CondicionIva = 'Responsable Inscripto' THEN 1.21 ELSE 1 END
             AS DECIMAL(12,2)) AS PrecioSugerido,
        CASE WHEN p.CondicionIva = 'Responsable Inscripto' THEN 0 ELSE 1 END AS IvaIncluido,
        pr.IdRepuesto,
        rep.Codigo              AS CodigoPropio,
        ISNULL(st.Cantidad, 0)  AS StockPropio,
        CASE WHEN pr.IdRepuesto IS NOT NULL THEN 1 ELSE 0 END AS Comparable,
        CASE WHEN pr.IdRepuesto IS NULL THEN NULL
             ELSE RANK() OVER (PARTITION BY pr.IdRepuesto ORDER BY pr.PrecioCompra)
        END AS RankingCosto,
        CASE WHEN @esCod = 1 AND pr.CodigosBusqueda LIKE '%' + @todo + '%' THEN 0
             ELSE dbo.fn_BusquedaRelevancia(pr.TextoBusqueda, ISNULL(pr.RubroTexto, '') + ' ' + ISNULL(ru.Nombre, ''), @p1, @p2, @p3, @p4)
        END AS Relevancia
    FROM ProveedorRepuesto pr
    INNER JOIN Proveedor p ON p.Id = pr.IdProveedor
    LEFT JOIN Rubro ru     ON ru.Id = pr.IdRubro
    LEFT JOIN Repuesto rep ON rep.Id = pr.IdRepuesto
    LEFT JOIN Stock st     ON st.IdRepuesto = pr.IdRepuesto
    WHERE pr.Activo = 1
      AND pr.PrecioCompra > 0
      AND (@IdProveedor IS NULL OR pr.IdProveedor = @IdProveedor)
      AND ( (@esCod = 1 AND pr.CodigosBusqueda LIKE '%' + @todo + '%')
       OR ( (@p1 IS NULL OR pr.TextoBusqueda LIKE '%' + @p1 + '%'
           OR (@n1 = 1 AND pr.CodigosBusqueda LIKE '%' + @c1 + '%'))
      AND (@p2 IS NULL OR pr.TextoBusqueda LIKE '%' + @p2 + '%'
           OR (@n2 = 1 AND pr.CodigosBusqueda LIKE '%' + @c2 + '%'))
      AND (@p3 IS NULL OR pr.TextoBusqueda LIKE '%' + @p3 + '%'
           OR (@n3 = 1 AND pr.CodigosBusqueda LIKE '%' + @c3 + '%'))
      AND (@p4 IS NULL OR pr.TextoBusqueda LIKE '%' + @p4 + '%'
           OR (@n4 = 1 AND pr.CodigosBusqueda LIKE '%' + @c4 + '%')) ) )
    ORDER BY
        Relevancia,
        CASE WHEN pr.IdRepuesto IS NOT NULL THEN 0 ELSE 1 END,
        pr.PrecioCompra;
END
GO

-- Prueba: la ultima columna (Relevancia) tiene que dar 1 en las bombas y 2 en el oring y la correa
EXEC SP_Busqueda_Universal @Texto = 'bomba de agua suran', @Tope = 20;
GO
