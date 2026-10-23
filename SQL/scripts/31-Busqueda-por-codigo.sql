USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   31 — BUSQUEDA POR CODIGO Y NUMERO PARCIAL

   DOS PROBLEMAS DETECTADOS EN USO

   1. CODIGOS CON Y SIN GUION
      El sitio de Expoyer muestra 25320-2, pero el Excel que descarga
      trae 253202: el guion se pierde en la exportacion. Al reves
      pasa con Autocor, que escribe KTB341 donde Expoyer pone KTB-341.
      Buscar por codigo fallaba en los dos sentidos.

   2. NUMEROS PARCIALES
      Buscar "2206" no encontraba "VKMA 02206A". El termino se
      comparaba contra palabras completas, y en los codigos de
      fabricante lo normal es acordarse de una parte.

   SOLUCION
   Una columna adicional con todos los codigos del articulo sin
   separadores, y una regla en la busqueda: si el termino tiene
   digitos, se busca ademas como fragmento dentro de esa columna.

   LO QUE NO CAMBIA
   Las palabras siguen buscandose completas. "kit" no debe traer
   "kits" de otra cosa, y las medidas siguen intactas.
   ================================================================= */


/* -----------------------------------------------------------------
   1. Columna con los codigos sin separadores
   ----------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('ProveedorRepuesto') AND name = 'CodigosBusqueda')
    ALTER TABLE ProveedorRepuesto ADD CodigosBusqueda VARCHAR(200) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('Repuesto') AND name = 'CodigosBusqueda')
    ALTER TABLE Repuesto ADD CodigosBusqueda VARCHAR(200) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID('ProveedorRepuesto') AND name = 'IX_ProvRep_CodigosBusqueda')
    CREATE INDEX IX_ProvRep_CodigosBusqueda ON ProveedorRepuesto(CodigosBusqueda);
GO


/* -----------------------------------------------------------------
   2. Limpiar un codigo: mayusculas y sin separadores
   ----------------------------------------------------------------- */
IF OBJECT_ID('fn_LimpiarCodigo', 'FN') IS NOT NULL DROP FUNCTION fn_LimpiarCodigo;
GO

CREATE FUNCTION fn_LimpiarCodigo(@t VARCHAR(200))
RETURNS VARCHAR(200)
AS
BEGIN
    IF @t IS NULL RETURN '';
    RETURN REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
             UPPER(@t), '-', ''), ' ', ''), '.', ''), '/', ''), '_', '');
END
GO


/* -----------------------------------------------------------------
   3. Poblar la columna

   Junta el codigo del proveedor, el codigo de fabricante y los
   numeros que aparecen en la descripcion, todos sin separadores.
   ----------------------------------------------------------------- */
UPDATE ProveedorRepuesto
SET CodigosBusqueda =
    ' ' + dbo.fn_LimpiarCodigo(ISNULL(CodigoProveedor, '')) +
    ' ' + dbo.fn_LimpiarCodigo(ISNULL(Articulo, '')) + ' '
WHERE Activo = 1;
GO

UPDATE Repuesto
SET CodigosBusqueda =
    ' ' + dbo.fn_LimpiarCodigo(ISNULL(Codigo, '')) +
    ' ' + dbo.fn_LimpiarCodigo(ISNULL(CodigoFabricante, '')) + ' '
WHERE Activo = 1;
GO

SELECT COUNT(*) AS ConCodigosBusqueda
FROM ProveedorRepuesto WHERE Activo = 1 AND CodigosBusqueda IS NOT NULL;
GO


/* -----------------------------------------------------------------
   4. Buscador universal con la regla nueva

   Para cada palabra del termino:
     - si tiene digitos: se busca como fragmento en los codigos
       Y TAMBIEN en el texto. Asi "2206" encuentra "VKMA 02206A" y
       "25320-2" encuentra el codigo 253202.
     - si es solo letras: se busca en el texto, como antes.
   ----------------------------------------------------------------- */
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
         ORDER BY pr.PrecioCompra)  AS MejorProveedor
    FROM Repuesto r
    LEFT JOIN Rubro ru ON ru.Id = r.IdRubro
    LEFT JOIN Stock s  ON s.IdRepuesto = r.Id
    WHERE r.Activo = 1
      AND (@SoloConStock = 0 OR ISNULL(s.Cantidad, 0) > 0)
      AND (@p1 IS NULL OR r.TextoBusqueda LIKE '%' + @p1 + '%'
           OR (@n1 = 1 AND r.CodigosBusqueda LIKE '%' + @c1 + '%'))
      AND (@p2 IS NULL OR r.TextoBusqueda LIKE '%' + @p2 + '%'
           OR (@n2 = 1 AND r.CodigosBusqueda LIKE '%' + @c2 + '%'))
      AND (@p3 IS NULL OR r.TextoBusqueda LIKE '%' + @p3 + '%'
           OR (@n3 = 1 AND r.CodigosBusqueda LIKE '%' + @c3 + '%'))
      AND (@p4 IS NULL OR r.TextoBusqueda LIKE '%' + @p4 + '%'
           OR (@n4 = 1 AND r.CodigosBusqueda LIKE '%' + @c4 + '%'))
    ORDER BY
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
        CAST(pr.PrecioCompra * (1 + ISNULL(ru.MargenPorcentaje, @MargenGeneral) / 100.0)
             * 1.21 AS DECIMAL(12,2)) AS PrecioSugerido,
        pr.IdRepuesto,
        rep.Codigo              AS CodigoPropio,
        ISNULL(st.Cantidad, 0)  AS StockPropio,
        CASE WHEN pr.IdRepuesto IS NOT NULL THEN 1 ELSE 0 END AS Comparable,
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
      AND (@p1 IS NULL OR pr.TextoBusqueda LIKE '%' + @p1 + '%'
           OR (@n1 = 1 AND pr.CodigosBusqueda LIKE '%' + @c1 + '%'))
      AND (@p2 IS NULL OR pr.TextoBusqueda LIKE '%' + @p2 + '%'
           OR (@n2 = 1 AND pr.CodigosBusqueda LIKE '%' + @c2 + '%'))
      AND (@p3 IS NULL OR pr.TextoBusqueda LIKE '%' + @p3 + '%'
           OR (@n3 = 1 AND pr.CodigosBusqueda LIKE '%' + @c3 + '%'))
      AND (@p4 IS NULL OR pr.TextoBusqueda LIKE '%' + @p4 + '%'
           OR (@n4 = 1 AND pr.CodigosBusqueda LIKE '%' + @c4 + '%'))
    ORDER BY
        CASE WHEN pr.IdRepuesto IS NOT NULL THEN 0 ELSE 1 END,
        pr.PrecioCompra;
END
GO


/* -----------------------------------------------------------------
   5. Lo mismo para el buscador de incorporacion y vinculacion
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_ProveedorRepuesto_Buscar', 'P') IS NOT NULL
    DROP PROCEDURE SP_ProveedorRepuesto_Buscar;
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
        CAST(pr.PrecioCompra * (1 + ISNULL(r.MargenPorcentaje, @MargenGeneral) / 100.0)
             AS DECIMAL(12,2)) AS NetoSugerido,
        CAST(pr.PrecioCompra * (1 + ISNULL(r.MargenPorcentaje, @MargenGeneral) / 100.0)
             * (1 + @IvaDefecto / 100.0) AS DECIMAL(12,2)) AS FinalSugerido,
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


/* -----------------------------------------------------------------
   6. PRUEBAS con los casos que fallaron
   ----------------------------------------------------------------- */

-- "KIT 2206" tiene que encontrar el VKMA 02206A
EXEC SP_ProveedorRepuesto_Buscar @Texto = 'KIT 2206', @Tope = 10, @SoloSinEnlazar = 0;
GO

-- El codigo con guion, aunque el archivo lo traiga sin el
EXEC SP_ProveedorRepuesto_Buscar @Texto = '25320-2', @Tope = 10, @SoloSinEnlazar = 0;
GO

-- Y al reves: KTB341 tiene que encontrar tambien KTB-341
EXEC SP_ProveedorRepuesto_Buscar @Texto = 'ktb341', @Tope = 10, @SoloSinEnlazar = 0;
GO

-- Control: las medidas siguen funcionando
EXEC SP_ProveedorRepuesto_Buscar @Texto = 'abrazadera 8-12', @Tope = 5, @SoloSinEnlazar = 0;
GO
