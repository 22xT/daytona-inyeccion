USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   52 — PRECIO FINAL CON IVA INCLUIDO PARA PROVEEDORES QUE NO FACTURAN IVA

   Regla del negocio: el precio de venta es el costo + 50%.
     - Proveedor RESPONSABLE INSCRIPTO: ese 50% da el NETO y el IVA se
       suma arriba (como hasta ahora).
     - Proveedor que NO factura IVA (TAC: consumidor final; tambien
       monotributista o exento): ese 50% da el PRECIO FINAL. Si se le
       sumara el IVA arriba, quedaria 21% mas caro que la competencia.

   Daytona es responsable inscripto: el precio final igual lleva el
   IVA adentro. El neto se despeja del final (final / 1,21), y es lo
   que va a ir a la factura y al libro de IVA cuando se facture con
   ARCA. Por eso el margen real de esos articulos es menor al 50%:
   la bujia ZKR7B-10 de TAC (costo $7.786,90) se vende a $11.680,35
   final, con un neto de $9.653,18: un 24% sobre el costo.

   La condicion de IVA del proveedor ya estaba en su ficha pero no
   intervenia en ningun calculo. Ahora decide esto.
   ================================================================= */


/* -----------------------------------------------------------------
   1. De que proveedor sale el costo de un repuesto propio
   Un repuesto puede estar vinculado a varios proveedores: se toma el
   activo mas barato, que es al que se le compraria.
   ----------------------------------------------------------------- */
IF OBJECT_ID('fn_RepuestoIvaIncluido', 'FN') IS NOT NULL DROP FUNCTION fn_RepuestoIvaIncluido;
GO
CREATE FUNCTION fn_RepuestoIvaIncluido(@IdRepuesto INT) RETURNS BIT
AS
BEGIN
    DECLARE @cond VARCHAR(30);
    SELECT TOP 1 @cond = p.CondicionIva
    FROM ProveedorRepuesto pr INNER JOIN Proveedor p ON p.Id = pr.IdProveedor
    WHERE pr.IdRepuesto = @IdRepuesto AND pr.Activo = 1 AND pr.PrecioCompra > 0
    ORDER BY pr.PrecioCompra;
    -- Sin proveedor vinculado: como siempre, IVA arriba
    RETURN CASE WHEN @cond IS NULL OR @cond = 'Responsable Inscripto' THEN 0 ELSE 1 END;
END
GO


/* -----------------------------------------------------------------
   2. Precio sugerido del catalogo propio (el que se confirma)
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Repuesto_PrecioSugerido', 'P') IS NOT NULL DROP PROCEDURE SP_Repuesto_PrecioSugerido;
GO
CREATE PROCEDURE SP_Repuesto_PrecioSugerido
    @IdRepuesto INT = NULL   -- NULL = todos los que tengan costo cargado
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Base AS (
        SELECT r.Id, r.Codigo, r.Descripcion, ISNULL(ru.Nombre, '-') AS Rubro, r.PrecioCompra,
               dbo.fn_MargenDeRepuesto(r.Id) AS MargenAplicado, a.Porcentaje AS AlicuotaIva,
               dbo.fn_RepuestoIvaIncluido(r.Id) AS IvaIncluido,
               r.PrecioNetoVenta, r.PrecioDeVenta
        FROM Repuesto r
        LEFT JOIN Rubro ru ON ru.Id = r.IdRubro
        LEFT JOIN AlicuotaIva a ON a.Id = r.IdAlicuotaIva
        WHERE r.Activo = 1 AND r.PrecioCompra IS NOT NULL
          AND (@IdRepuesto IS NULL OR r.Id = @IdRepuesto)
    ),
    Calc AS (
        SELECT b.*,
               -- Final sugerido: con IVA arriba, o costo + margen si el proveedor no factura IVA
               CAST(CASE WHEN b.IvaIncluido = 1
                         THEN b.PrecioCompra * (1 + b.MargenAplicado / 100.0)
                         ELSE b.PrecioCompra * (1 + b.MargenAplicado / 100.0) * (1 + b.AlicuotaIva / 100.0) END
                    AS DECIMAL(12,2)) AS FinalSugerido
        FROM Base b
    )
    SELECT
        c.Id, c.Codigo, c.Descripcion, c.Rubro, c.PrecioCompra, c.MargenAplicado, c.AlicuotaIva,
        c.IvaIncluido,
        -- El neto siempre se despeja del final: es lo que va al libro de IVA
        CAST(c.FinalSugerido / (1 + c.AlicuotaIva / 100.0) AS DECIMAL(12,2)) AS NetoSugerido,
        c.FinalSugerido,
        c.PrecioNetoVenta AS NetoActual,
        c.PrecioDeVenta   AS FinalActual,

        -- Margen real sobre el costo: con IVA incluido es menor que el margen objetivo
        CASE WHEN c.PrecioCompra > 0 AND c.PrecioNetoVenta IS NOT NULL
             THEN CAST((c.PrecioNetoVenta - c.PrecioCompra) / c.PrecioCompra * 100 AS DECIMAL(6,2))
             ELSE NULL END AS MargenActual,

        CASE WHEN c.PrecioNetoVenta IS NULL          THEN 'Sin precio de venta'
             WHEN c.PrecioNetoVenta < c.PrecioCompra THEN 'POR DEBAJO DEL COSTO'
             WHEN c.PrecioDeVenta < c.FinalSugerido * 0.9
                                                     THEN 'Margen por debajo del objetivo'
             ELSE 'OK' END AS Estado
    FROM Calc c
    ORDER BY c.Codigo;
END
GO


/* -----------------------------------------------------------------
   3. Precio sugerido en el buscador, para articulos de proveedores
   Version vigente del script 31, con un solo cambio: el 1,21.
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
   4. Verificacion con la bujia de la pagina de TAC
   Tiene que dar 11680.35, igual que la web del proveedor.
   ----------------------------------------------------------------- */
SELECT p.RazonSocial, p.CondicionIva, pr.CodigoProveedor, pr.PrecioLista, pr.DescuentoRubro, pr.PrecioCompra,
       CAST(pr.PrecioCompra * 1.5 * CASE WHEN p.CondicionIva = 'Responsable Inscripto' THEN 1.21 ELSE 1 END
            AS DECIMAL(12,2)) AS PrecioFinal
FROM ProveedorRepuesto pr INNER JOIN Proveedor p ON p.Id = pr.IdProveedor
WHERE pr.CodigoProveedor IN ('ZKR7B-10', 'ZKR7BI-10');
GO
