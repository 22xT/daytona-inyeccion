USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   84 — COMPARAR LISTAS RESPETANDO LOS DESCUENTOS POR LINEA

   Al comparar una lista nueva de TAC, el costo no tenia en cuenta los
   descuentos por linea (bujias y cables NGK 7%, plaquetas Estrada 5%,
   lamparas CREE 6%). Esos ~210 articulos aparecian como "suben" y el
   precio sugerido para tus repuestos salia mas caro de lo que es.

   Solo cambia SP_Importacion_Comparar (la vista previa). No toca datos.
   Correr en la base local y en Azure.
   ================================================================= */

IF OBJECT_ID('SP_Importacion_Comparar', 'P') IS NOT NULL DROP PROCEDURE SP_Importacion_Comparar;
GO
CREATE PROCEDURE SP_Importacion_Comparar
    @IdProveedor INT,
    @UmbralRaro  DECIMAL(6,2) = 30     -- % de cambio que se considera raro
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @cCod TINYINT, @cArt TINYINT, @cRub TINYINT, @cDes TINYINT, @cPre TINYINT,
            @cD1 TINYINT, @cD2 TINYINT, @cCos TINYINT, @esquema VARCHAR(20), @dFijo DECIMAL(6,2), @enc TINYINT;

    SELECT @cCod = ColCodigo, @cArt = ColArticulo, @cRub = ColRubro, @cDes = ColDescripcion,
           @cPre = ColPrecio, @cD1 = ColDescuento1, @cD2 = ColDescuento2, @cCos = ColCosto,
           @esquema = EsquemaCosto, @dFijo = DescuentoFijo, @enc = FilasEncabezado
    FROM PerfilImportacion WHERE IdProveedor = @IdProveedor AND Activo = 1;

    IF @cCod IS NULL
        THROW 50150, 'Ese proveedor no tiene perfil de importacion configurado.', 1;
    IF NOT EXISTS (SELECT 1 FROM StgImportacion)
        THROW 50151, 'La tabla de paso esta vacia: primero el BULK INSERT del archivo.', 1;

    /* Las mismas cuentas que SP_Importacion_Procesar */
    DECLARE @eArt VARCHAR(20) = CASE WHEN @cArt IS NULL THEN 'NULL' ELSE 'Col' + CAST(@cArt AS VARCHAR(2)) END;
    DECLARE @eRub VARCHAR(20) = CASE WHEN @cRub IS NULL THEN 'NULL' ELSE 'Col' + CAST(@cRub AS VARCHAR(2)) END;
    DECLARE @ePre VARCHAR(20) = 'Col' + CAST(@cPre AS VARCHAR(2));
    DECLARE @eD1  VARCHAR(60) = CASE WHEN @cD1 IS NULL THEN CAST(@dFijo AS VARCHAR(20))
                                     ELSE 'TRY_CAST(Col' + CAST(@cD1 AS VARCHAR(2)) + ' AS DECIMAL(6,2))' END;
    DECLARE @eD2  VARCHAR(60) = CASE WHEN @cD2 IS NULL THEN '0'
                                     ELSE 'TRY_CAST(Col' + CAST(@cD2 AS VARCHAR(2)) + ' AS DECIMAL(6,2))' END;
    DECLARE @eCosto NVARCHAR(500);
    IF @esquema = 'CostoEnColumna' AND @cCos IS NOT NULL
        SET @eCosto = N'TRY_CAST(Col' + CAST(@cCos AS VARCHAR(2)) + N' AS DECIMAL(12,2))';
    ELSE IF @esquema = 'CostoDirecto'
        SET @eCosto = N'TRY_CAST(' + @ePre + N' AS DECIMAL(12,2))';
    ELSE IF @esquema = 'UnDescuento'
        SET @eCosto = N'CAST(TRY_CAST(' + @ePre + N' AS DECIMAL(12,2)) * (1 - ISNULL(' + @eD1 + N',0)/100.0) AS DECIMAL(12,2))';
    ELSE
        SET @eCosto = N'CAST(TRY_CAST(' + @ePre + N' AS DECIMAL(12,2)) * (1 - ISNULL(' + @eD1 + N',0)/100.0) * (1 - ISNULL(' + @eD2 + N',0)/100.0) AS DECIMAL(12,2))';

    TRUNCATE TABLE StgComparacion;
    DECLARE @sql NVARCHAR(MAX) = N'
    INSERT INTO StgComparacion (Codigo, Articulo, Rubro, Descripcion, PrecioLista, Costo)
    SELECT LTRIM(RTRIM(Col' + CAST(@cCod AS VARCHAR(2)) + N')), LEFT(' + @eArt + N', 60), LEFT(' + @eRub + N', 150),
           LEFT(Col' + CAST(@cDes AS VARCHAR(2)) + N', 300),
           TRY_CAST(' + @ePre + N' AS DECIMAL(12,2)), ' + @eCosto + N'
    FROM StgImportacion
    WHERE Fila > ' + CAST(ISNULL(@enc, 0) AS VARCHAR(3)) + N'
      AND Col' + CAST(@cCod AS VARCHAR(2)) + N' IS NOT NULL
      AND LTRIM(RTRIM(Col' + CAST(@cCod AS VARCHAR(2)) + N')) <> '''';';
    EXEC sp_executesql @sql;

    /* Descuentos por linea de producto (script 51, TAC): si el proveedor
       tiene reglas y su lista no trae el descuento de rubro, el costo se
       calcula igual que lo deja el trigger despues de importar.
       Sin esto las bujias NGK aparecian subiendo un 7,5% y el precio de
       venta sugerido salia un 7% mas caro. */
    IF NOT EXISTS (SELECT 1 FROM PerfilImportacion WHERE IdProveedor = @IdProveedor AND Activo = 1 AND ColDescuento1 IS NOT NULL)
       AND EXISTS (SELECT 1 FROM ReglaDescuentoProveedor WHERE IdProveedor = @IdProveedor AND Activo = 1)
    BEGIN
        DECLARE @dGen DECIMAL(6,2) = ISNULL((SELECT TOP 1 CASE WHEN ColDescuento2 IS NULL THEN DescuentoFijo2 END
                                             FROM PerfilImportacion WHERE IdProveedor = @IdProveedor AND Activo = 1), 0);
        UPDATE n SET Costo = CAST(n.PrecioLista * (1 - r.Porcentaje / 100.0) * (1 - @dGen / 100.0) AS DECIMAL(12,2))
        FROM StgComparacion n
        CROSS APPLY (SELECT TOP 1 x.Porcentaje FROM ReglaDescuentoProveedor x
                     WHERE x.IdProveedor = @IdProveedor AND x.Activo = 1
                       AND UPPER(LEFT(n.Descripcion, 250)) LIKE x.Incluye
                       AND (x.Incluye2 IS NULL OR UPPER(LEFT(n.Descripcion, 250)) LIKE x.Incluye2)
                       AND (x.Excluye  IS NULL OR UPPER(LEFT(n.Descripcion, 250)) NOT LIKE x.Excluye)
                       AND (x.Excluye2 IS NULL OR UPPER(LEFT(n.Descripcion, 250)) NOT LIKE x.Excluye2)
                     ORDER BY x.Prioridad, x.Id) r
        WHERE n.PrecioLista > 0;
    END

    DECLARE @MargenGeneral DECIMAL(6,2) =
        ISNULL(TRY_CAST((SELECT Valor FROM ParametroSistema WHERE Clave = 'MargenGeneral') AS DECIMAL(6,2)), 50);
    DECLARE @RI BIT = CASE WHEN (SELECT CondicionIva FROM Proveedor WHERE Id = @IdProveedor) = 'Responsable Inscripto' THEN 1 ELSE 0 END;

    /* Cruce: lo nuevo contra lo cargado */
    SELECT n.Codigo, n.Rubro, n.Descripcion, pr.Id AS IdPR, pr.IdRepuesto,
           pr.PrecioCompra AS CostoAntes, n.Costo AS CostoAhora,
           CASE WHEN pr.Id IS NULL THEN 'NUEVO'
                WHEN ISNULL(n.Costo, 0) <= 0 AND pr.PrecioCompra > 0 THEN 'SIN_PRECIO'
                WHEN ISNULL(pr.PrecioCompra, 0) <= 0 AND n.Costo > 0 THEN 'VUELVE'
                WHEN n.Costo > pr.PrecioCompra THEN 'SUBE'
                WHEN n.Costo < pr.PrecioCompra THEN 'BAJA'
                ELSE 'IGUAL' END AS Cambio,
           CASE WHEN pr.PrecioCompra > 0 AND n.Costo > 0
                THEN CAST((n.Costo - pr.PrecioCompra) / pr.PrecioCompra * 100 AS DECIMAL(8,2)) END AS VariacionPorc
    INTO #Cruce
    FROM StgComparacion n
    LEFT JOIN ProveedorRepuesto pr ON pr.IdProveedor = @IdProveedor AND pr.CodigoProveedor = n.Codigo;

    -- 1) Resumen
    SELECT
        (SELECT COUNT(*) FROM StgComparacion)                                   AS ArticulosEnArchivo,
        SUM(CASE WHEN Cambio = 'SUBE' THEN 1 ELSE 0 END)                        AS Suben,
        SUM(CASE WHEN Cambio = 'BAJA' THEN 1 ELSE 0 END)                        AS Bajan,
        SUM(CASE WHEN Cambio = 'IGUAL' THEN 1 ELSE 0 END)                       AS Iguales,
        SUM(CASE WHEN Cambio = 'NUEVO' THEN 1 ELSE 0 END)                       AS Nuevos,
        SUM(CASE WHEN Cambio = 'SIN_PRECIO' THEN 1 ELSE 0 END)                  AS QuedanSinPrecio,
        SUM(CASE WHEN Cambio = 'VUELVE' THEN 1 ELSE 0 END)                      AS VuelvenATenerPrecio,
        (SELECT COUNT(*) FROM ProveedorRepuesto pr
         WHERE pr.IdProveedor = @IdProveedor AND pr.Activo = 1
           AND NOT EXISTS (SELECT 1 FROM StgComparacion n WHERE n.Codigo = pr.CodigoProveedor)) AS DesaparecenDeLaLista,
        CAST(AVG(CASE WHEN Cambio IN ('SUBE','BAJA','IGUAL') THEN VariacionPorc END) AS DECIMAL(8,2)) AS VariacionPromedioPorc,
        CAST(AVG(CASE WHEN Cambio = 'SUBE' THEN VariacionPorc END) AS DECIMAL(8,2))                 AS AumentoPromedioDeLosQueSuben
    FROM #Cruce;

    -- 2) Por rubro (los que mas cambiaron primero)
    SELECT Rubro,
           COUNT(*) AS Articulos,
           SUM(CASE WHEN Cambio = 'SUBE' THEN 1 ELSE 0 END) AS Suben,
           SUM(CASE WHEN Cambio = 'BAJA' THEN 1 ELSE 0 END) AS Bajan,
           CAST(AVG(VariacionPorc) AS DECIMAL(8,2)) AS VariacionPromedioPorc,
           MIN(VariacionPorc) AS MinPorc, MAX(VariacionPorc) AS MaxPorc
    FROM #Cruce
    WHERE Cambio IN ('SUBE', 'BAJA', 'IGUAL')
    GROUP BY Rubro
    ORDER BY ABS(AVG(VariacionPorc)) DESC, COUNT(*) DESC;

    -- 3) Raros: cambios grandes o que se quedan sin precio. Revisar antes de importar.
    SELECT TOP 300 Codigo, Rubro, Descripcion, CostoAntes, CostoAhora, VariacionPorc, Cambio,
           CASE WHEN IdRepuesto IS NOT NULL THEN 'Si' ELSE '' END AS EsDeTuCatalogo
    FROM #Cruce
    WHERE (Cambio IN ('SUBE','BAJA') AND ABS(VariacionPorc) >= @UmbralRaro)
       OR (Cambio = 'SIN_PRECIO' AND IdRepuesto IS NOT NULL)
    ORDER BY CASE WHEN IdRepuesto IS NOT NULL THEN 0 ELSE 1 END, ABS(ISNULL(VariacionPorc, 100)) DESC;

    -- 4) Tus repuestos: cuanto cambia el costo y cuanto quedaria el precio de venta
    SELECT r.Id AS IdRepuesto, r.Codigo AS TuCodigo, r.Descripcion, r.MarcaFabricante AS Marca,
           ISNULL(s.Cantidad, 0) AS Stock,
           c.CostoAntes, c.CostoAhora, c.VariacionPorc, c.Cambio,
           r.PrecioDeVenta AS PrecioVentaActual,
           CAST(c.CostoAhora * (1 + ISNULL(r.MargenPropio, ISNULL(ru.MargenPorcentaje, @MargenGeneral)) / 100.0)
                * CASE WHEN @RI = 1 THEN 1.21 ELSE 1 END AS DECIMAL(12,2)) AS PrecioVentaSugerido,
           -- Neto (sin IVA), que es lo que guarda SP_Repuesto_AplicarPrecio
           CAST(c.CostoAhora * (1 + ISNULL(r.MargenPropio, ISNULL(ru.MargenPorcentaje, @MargenGeneral)) / 100.0)
                / CASE WHEN @RI = 1 THEN 1 ELSE 1.21 END AS DECIMAL(12,2)) AS NetoSugerido,
           -- ¿Este proveedor sigue siendo el mas barato para ese repuesto?
           CASE WHEN c.CostoAhora > 0 AND c.CostoAhora <= ISNULL((SELECT MIN(x.PrecioCompra) FROM ProveedorRepuesto x
                                                    WHERE x.IdRepuesto = r.Id AND x.IdProveedor <> @IdProveedor
                                                      AND x.Activo = 1 AND x.PrecioCompra > 0), 999999999)
                THEN 'Si' ELSE 'No' END AS SigueSiendoElMasBarato
    FROM #Cruce c
    INNER JOIN Repuesto r ON r.Id = c.IdRepuesto
    LEFT JOIN Rubro ru    ON ru.Id = r.IdRubro
    LEFT JOIN Stock s     ON s.IdRepuesto = r.Id
    WHERE r.Activo = 1
    ORDER BY CASE c.Cambio WHEN 'SIN_PRECIO' THEN 0 WHEN 'SUBE' THEN 1 WHEN 'BAJA' THEN 2 ELSE 3 END,
             ABS(ISNULL(c.VariacionPorc, 0)) DESC;
END
GO
