USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   54 — CATALOGO DE PROVEEDORES CON IVA INCLUIDO PARA QUIEN NO FACTURA

   Tercer lugar que sumaba el IVA arriba sin mirar al proveedor (los
   otros dos los corrigio el script 52). Es el que alimenta el
   Catalogo de proveedores y, a traves de el, el precio con el que un
   articulo entra al catalogo propio al incorporarlo.

   Version vigente del script 31 con un solo cambio en el calculo.
   ================================================================= */
IF OBJECT_ID('SP_ProveedorRepuesto_Buscar', 'P') IS NOT NULL DROP PROCEDURE SP_ProveedorRepuesto_Buscar;
GO
CREATE PROCEDURE SP_ProveedorRepuesto_Buscar
    @IdProveedor    INT = NULL,
    @Texto          VARCHAR(100) = NULL,
    @SoloSinEnlazar BIT = 1,
    @Tope           INT = 100
AS
BEGIN
    SET NOCOUNT ON;

    IF @Tope IS NULL OR @Tope <= 0 SET @Tope = 100;
    IF @Tope > 500 SET @Tope = 500;

    DECLARE @MargenGeneral DECIMAL(6,2) =
        ISNULL(TRY_CAST((SELECT Valor FROM ParametroSistema WHERE Clave = 'MargenGeneral')
                        AS DECIMAL(6,2)), 50);
    DECLARE @IvaDefecto DECIMAL(5,2) =
        ISNULL((SELECT TOP 1 Porcentaje FROM AlicuotaIva WHERE Porcentaje = 21 AND Activo = 1), 21);

    DECLARE @busca VARCHAR(400) = dbo.fn_NormalizarBusqueda(@Texto);
    DECLARE @cod   VARCHAR(200) = dbo.fn_LimpiarCodigo(ISNULL(@Texto, ''));
    DECLARE @esCod BIT = CASE WHEN @cod LIKE '%[0-9]%' AND LEN(@cod) >= 3 THEN 1 ELSE 0 END;

    -- Se parte en palabras igual que el buscador universal
    DECLARE @p1 VARCHAR(60), @p2 VARCHAR(60), @p3 VARCHAR(60);
    DECLARE @resto VARCHAR(400) = ISNULL(@busca, '') + ' ';

    SET @p1 = NULLIF(LEFT(@resto, CHARINDEX(' ', @resto) - 1), '');
    SET @resto = LTRIM(SUBSTRING(@resto, CHARINDEX(' ', @resto) + 1, 400));
    IF LEN(@resto) > 0 SET @p2 = NULLIF(LEFT(@resto + ' ', CHARINDEX(' ', @resto + ' ') - 1), '');
    SET @resto = LTRIM(SUBSTRING(@resto, CHARINDEX(' ', @resto + ' ') + 1, 400));
    IF LEN(@resto) > 0 SET @p3 = NULLIF(LEFT(@resto + ' ', CHARINDEX(' ', @resto + ' ') - 1), '');

    DECLARE @c1 VARCHAR(60) = dbo.fn_LimpiarCodigo(ISNULL(@p1, ''));
    DECLARE @c2 VARCHAR(60) = dbo.fn_LimpiarCodigo(ISNULL(@p2, ''));
    DECLARE @c3 VARCHAR(60) = dbo.fn_LimpiarCodigo(ISNULL(@p3, ''));
    DECLARE @n1 BIT = CASE WHEN @c1 LIKE '%[0-9]%' THEN 1 ELSE 0 END;
    DECLARE @n2 BIT = CASE WHEN @c2 LIKE '%[0-9]%' THEN 1 ELSE 0 END;
    DECLARE @n3 BIT = CASE WHEN @c3 LIKE '%[0-9]%' THEN 1 ELSE 0 END;

    SELECT TOP (@Tope)
        pr.Id, pr.IdProveedor, p.RazonSocial AS Proveedor,
        pr.CodigoProveedor, pr.Articulo, pr.Descripcion,
        pr.RubroTexto, pr.MarcaTexto, pr.IdRubro,
        r.Nombre AS Rubro,
        pr.PrecioLista, pr.DescuentoRubro, pr.DescuentoGeneral, pr.PrecioCompra,
        ISNULL(r.MargenPorcentaje, @MargenGeneral) AS MargenAplicado,
        -- Proveedor que factura con IVA: costo + margen da el neto y el IVA va arriba.
        -- Proveedor que no (TAC): costo + margen ya es el final y el neto se despeja.
        CAST(CASE WHEN p.CondicionIva = 'Responsable Inscripto'
                  THEN pr.PrecioCompra * (1 + ISNULL(r.MargenPorcentaje, @MargenGeneral) / 100.0)
                  ELSE pr.PrecioCompra * (1 + ISNULL(r.MargenPorcentaje, @MargenGeneral) / 100.0) / (1 + @IvaDefecto / 100.0) END
             AS DECIMAL(12,2)) AS NetoSugerido,
        CAST(pr.PrecioCompra * (1 + ISNULL(r.MargenPorcentaje, @MargenGeneral) / 100.0)
             * CASE WHEN p.CondicionIva = 'Responsable Inscripto' THEN 1 + @IvaDefecto / 100.0 ELSE 1 END
             AS DECIMAL(12,2)) AS FinalSugerido,
        CASE WHEN p.CondicionIva = 'Responsable Inscripto' THEN 0 ELSE 1 END AS IvaIncluido,
        pr.IdRepuesto,
        CASE WHEN pr.IdRepuesto IS NULL THEN 0 ELSE 1 END AS YaEnCatalogo,
        rep.Codigo      AS CodigoPropio,
        rep.Descripcion AS DescripcionPropia,
        ISNULL(st.Cantidad, 0) AS StockPropio
    FROM ProveedorRepuesto pr
    INNER JOIN Proveedor p ON p.Id = pr.IdProveedor
    LEFT JOIN Rubro r      ON r.Id = pr.IdRubro
    LEFT JOIN Repuesto rep ON rep.Id = pr.IdRepuesto
    LEFT JOIN Stock st     ON st.IdRepuesto = pr.IdRepuesto
    WHERE pr.Activo = 1
      AND pr.PrecioCompra > 0
      AND (@IdProveedor IS NULL OR pr.IdProveedor = @IdProveedor)
      AND (@SoloSinEnlazar = 0 OR pr.IdRepuesto IS NULL)
      AND (
            -- El texto entero como codigo: "25320-2" encuentra 253202
            (@esCod = 1 AND pr.CodigosBusqueda LIKE '%' + @cod + '%')
            OR (
              (@p1 IS NULL OR pr.TextoBusqueda LIKE '%' + @p1 + '%'
               OR (@n1 = 1 AND pr.CodigosBusqueda LIKE '%' + @c1 + '%'))
              AND (@p2 IS NULL OR pr.TextoBusqueda LIKE '%' + @p2 + '%'
               OR (@n2 = 1 AND pr.CodigosBusqueda LIKE '%' + @c2 + '%'))
              AND (@p3 IS NULL OR pr.TextoBusqueda LIKE '%' + @p3 + '%'
               OR (@n3 = 1 AND pr.CodigosBusqueda LIKE '%' + @c3 + '%'))
            )
          )
    ORDER BY pr.Descripcion;
END
GO

-- Verificacion: la bujia de TAC tiene que dar final 11680.35 y neto 9653.18
DECLARE @IdTac INT = (SELECT TOP 1 Id FROM Proveedor WHERE RazonSocial LIKE 'TAC%');
SELECT pr.CodigoProveedor, pr.PrecioCompra,
       CAST(pr.PrecioCompra * 1.5 AS DECIMAL(12,2)) AS FinalEsperado,
       CAST(pr.PrecioCompra * 1.5 / 1.21 AS DECIMAL(12,2)) AS NetoEsperado
FROM ProveedorRepuesto pr WHERE pr.IdProveedor = @IdTac AND pr.CodigoProveedor = 'ZKR7B-10';
GO
