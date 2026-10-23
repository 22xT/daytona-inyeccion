USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   26 — SEGUNDO PROVEEDOR: EXPOYER

   Estructura de su archivo, muy distinta a la de Autocor:

     - 11 hojas separadas por marca de vehiculo (RN, VW, FI, PG, CH,
       FO, UN, CI, TY, JE, CD). El conversor las unifica.
     - 103.109 articulos
     - Columnas: CODIGO, DESCR, NROORI, PRECIO, DESCR2, CODPRO,
       ORIGEN, CANPED, FOTO, COEF, CODRUB, MARCA
     - FOTO y COEF vienen VACIAS en todas las filas
     - PRECIO es el precio de LISTA (verificado contra el catalogo web)
     - El archivo NO trae los descuentos: los informa el proveedor

   DESCUENTO CONFIRMADO POR EL PROVEEDOR: 61,08% y despues 15%

   Encadenados, no sumados:
       82.691,00 x (1-0,6108) x (1-0,15) = 27.355,84   -> coincide
       82.691,00 x (1-0,7608)            = 19.779,69   -> NO coincide

   Son $7.576 de diferencia en un solo articulo. Verificado al
   centavo contra dos articulos del catalogo web.
   ================================================================= */


/* -----------------------------------------------------------------
   1. Un segundo descuento fijo en el perfil

   Expoyer no manda los descuentos en el archivo, asi que hay que
   guardarlos en la configuracion. El perfil ya tenia DescuentoFijo
   para el primero; falta el segundo.
   ----------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('PerfilImportacion') AND name = 'DescuentoFijo2')
    ALTER TABLE PerfilImportacion ADD DescuentoFijo2 DECIMAL(6,2) NOT NULL
        CONSTRAINT DF_Perfil_DtoFijo2 DEFAULT 0;
GO


/* -----------------------------------------------------------------
   2. Alta del proveedor
   ----------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM Proveedor WHERE RazonSocial LIKE '%EXPOYER%')
BEGIN
    -- Ajustar las columnas si tu tabla Proveedor difiere
    INSERT INTO Proveedor (RazonSocial, Activo, DescuentoGeneral)
    VALUES ('Expoyer', 1, 61.08);
    PRINT 'Proveedor Expoyer creado.';
END
GO

SELECT Id, RazonSocial, DescuentoGeneral FROM Proveedor;
GO


/* -----------------------------------------------------------------
   3. Perfil de importacion

   El conversor unifica las 11 hojas y agrega la hoja como columna
   extra al final, para no perder la marca de vehiculo.

   Columnas del archivo generado:
     1 CODIGO   2 DESCR    3 NROORI   4 PRECIO   5 DESCR2
     6 CODPRO   7 ORIGEN   8 CANPED   9 FOTO    10 COEF
    11 CODRUB  12 MARCA   13 HOJA
   ----------------------------------------------------------------- */
DECLARE @idExpoyer INT;
SELECT TOP 1 @idExpoyer = Id FROM Proveedor WHERE RazonSocial LIKE '%EXPOYER%';

IF @idExpoyer IS NOT NULL AND NOT EXISTS (SELECT 1 FROM PerfilImportacion WHERE IdProveedor = @idExpoyer)
    INSERT INTO PerfilImportacion
        (IdProveedor, Nombre,
         ColCodigo, ColArticulo, ColRubro, ColMarca, ColDescripcion,
         ColPrecio, ColDescuento1, ColDescuento2, ColCosto,
         EsquemaCosto, DescuentoFijo, DescuentoFijo2, FilasEncabezado)
    VALUES
        (@idExpoyer, 'Expoyer — catalogo completo',
         1,     -- CODIGO
         3,     -- NROORI, el numero original de fabrica
         11,    -- CODRUB
         13,    -- HOJA, la marca de vehiculo
         2,     -- DESCR
         4,     -- PRECIO, que es el de LISTA
         NULL,  -- no manda descuentos: van fijos
         NULL,
         NULL,
         'DosDescuentos', 61.08, 15.00, 0);
GO

SELECT p.Nombre, pv.RazonSocial, p.EsquemaCosto,
       p.DescuentoFijo AS Dto1, p.DescuentoFijo2 AS Dto2,
       p.ColCodigo, p.ColDescripcion, p.ColPrecio, p.ColArticulo
FROM PerfilImportacion p
INNER JOIN Proveedor pv ON pv.Id = p.IdProveedor;
GO


/* -----------------------------------------------------------------
   4. El motor tiene que contemplar el segundo descuento fijo

   Antes, si ColDescuento2 era NULL se asumia 0. Ahora usa
   DescuentoFijo2 cuando la columna no viene.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Importacion_Procesar', 'P') IS NOT NULL DROP PROCEDURE SP_Importacion_Procesar;
GO

CREATE PROCEDURE SP_Importacion_Procesar
    @IdProveedor INT,
    @FechaLista  DATE = NULL,
    @SoloVistaPrevia BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @FechaLista IS NULL SET @FechaLista = CAST(GETDATE() AS DATE);

    DECLARE @cCod TINYINT, @cArt TINYINT, @cRub TINYINT, @cMar TINYINT,
            @cDes TINYINT, @cPre TINYINT, @cD1 TINYINT, @cD2 TINYINT,
            @cCos TINYINT, @esquema VARCHAR(20),
            @dFijo1 DECIMAL(6,2), @dFijo2 DECIMAL(6,2), @enc TINYINT;

    SELECT @cCod = ColCodigo, @cArt = ColArticulo, @cRub = ColRubro, @cMar = ColMarca,
           @cDes = ColDescripcion, @cPre = ColPrecio, @cD1 = ColDescuento1,
           @cD2 = ColDescuento2, @cCos = ColCosto, @esquema = EsquemaCosto,
           @dFijo1 = DescuentoFijo, @dFijo2 = DescuentoFijo2, @enc = FilasEncabezado
    FROM PerfilImportacion
    WHERE IdProveedor = @IdProveedor AND Activo = 1;

    IF @cCod IS NULL
    BEGIN
        RAISERROR('Ese proveedor no tiene perfil de importacion configurado.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM StgImportacion)
    BEGIN
        RAISERROR('La tabla de paso esta vacia. Corre primero el BULK INSERT.', 16, 1);
        RETURN;
    END

    DECLARE @eCod VARCHAR(30) = 's.Col' + CAST(@cCod AS VARCHAR(2));
    DECLARE @eArt VARCHAR(30) = CASE WHEN @cArt IS NULL THEN 'NULL' ELSE 's.Col' + CAST(@cArt AS VARCHAR(2)) END;
    DECLARE @eRub VARCHAR(30) = CASE WHEN @cRub IS NULL THEN 'NULL' ELSE 's.Col' + CAST(@cRub AS VARCHAR(2)) END;
    DECLARE @eMar VARCHAR(30) = CASE WHEN @cMar IS NULL THEN 'NULL' ELSE 's.Col' + CAST(@cMar AS VARCHAR(2)) END;
    DECLARE @eDes VARCHAR(30) = 's.Col' + CAST(@cDes AS VARCHAR(2));
    DECLARE @ePre VARCHAR(30) = 's.Col' + CAST(@cPre AS VARCHAR(2));

    -- Si el proveedor no manda el descuento, se usa el fijo del perfil
    DECLARE @eD1 VARCHAR(80) = CASE WHEN @cD1 IS NULL
                                    THEN CAST(@dFijo1 AS VARCHAR(20))
                                    ELSE 'ISNULL(TRY_CAST(s.Col' + CAST(@cD1 AS VARCHAR(2)) + ' AS DECIMAL(6,2)),0)' END;
    DECLARE @eD2 VARCHAR(80) = CASE WHEN @cD2 IS NULL
                                    THEN CAST(@dFijo2 AS VARCHAR(20))
                                    ELSE 'ISNULL(TRY_CAST(s.Col' + CAST(@cD2 AS VARCHAR(2)) + ' AS DECIMAL(6,2)),0)' END;

    DECLARE @eCosto NVARCHAR(500);

    IF @esquema = 'CostoEnColumna' AND @cCos IS NOT NULL
        SET @eCosto = N'TRY_CAST(s.Col' + CAST(@cCos AS VARCHAR(2)) + N' AS DECIMAL(12,2))';
    ELSE IF @esquema = 'CostoDirecto'
        SET @eCosto = N'TRY_CAST(' + @ePre + N' AS DECIMAL(12,2))';
    ELSE IF @esquema = 'UnDescuento'
        SET @eCosto = N'CAST(TRY_CAST(' + @ePre + N' AS DECIMAL(12,2)) * (1 - ' + @eD1 + N'/100.0) AS DECIMAL(12,2))';
    ELSE  -- DosDescuentos: encadenados, NUNCA sumados
        SET @eCosto = N'CAST(TRY_CAST(' + @ePre + N' AS DECIMAL(12,2)) * (1 - ' + @eD1 + N'/100.0) * (1 - ' + @eD2 + N'/100.0) AS DECIMAL(12,2))';

    DECLARE @sql NVARCHAR(MAX);
    DECLARE @filtroEnc VARCHAR(40) = ' AND s.Fila > ' + CAST(@enc AS VARCHAR(3));

    /* --- Vista previa --- */
    IF @SoloVistaPrevia = 1
    BEGIN
        SET @sql = N'
        SELECT
            COUNT(*) AS FilasEnArchivo,
            SUM(CASE WHEN ' + @eCod + N' IS NULL OR LTRIM(RTRIM(' + @eCod + N')) = '''' THEN 1 ELSE 0 END) AS SinCodigo,
            SUM(CASE WHEN TRY_CAST(' + @ePre + N' AS DECIMAL(12,2)) IS NULL THEN 1 ELSE 0 END) AS PrecioNoNumerico,
            SUM(CASE WHEN ISNULL(' + @eCosto + N', 0) <= 0 THEN 1 ELSE 0 END) AS SinCosto,
            COUNT(DISTINCT ' + @eCod + N') AS CodigosDistintos
        FROM StgImportacion s WHERE 1=1 ' + @filtroEnc + N';

        SELECT TOP 10
            ' + @eCod + N' AS Codigo, ' + @eDes + N' AS Descripcion,
            TRY_CAST(' + @ePre + N' AS DECIMAL(12,2)) AS PrecioLista,
            ' + @eCosto + N' AS CostoCalculado
        FROM StgImportacion s WHERE 1=1 ' + @filtroEnc + N';';

        EXEC sp_executesql @sql;
        RETURN;
    END

    /* --- Actualizar existentes --- */
    SET @sql = N'
    UPDATE pr
    SET pr.PrecioLista      = TRY_CAST(' + @ePre + N' AS DECIMAL(12,2)),
        pr.DescuentoRubro   = ' + @eD1 + N',
        pr.DescuentoGeneral = ' + @eD2 + N',
        pr.PrecioCompra     = ' + @eCosto + N',
        pr.Descripcion      = LEFT(' + @eDes + N', 250),
        pr.FechaLista       = @f,
        pr.Activo           = 1,
        pr.TextoBusqueda    = NULL
    FROM ProveedorRepuesto pr
    INNER JOIN StgImportacion s ON ' + @eCod + N' = pr.CodigoProveedor
    WHERE pr.IdProveedor = @p ' + @filtroEnc + N';';

    EXEC sp_executesql @sql, N'@p INT, @f DATE', @p = @IdProveedor, @f = @FechaLista;
    DECLARE @actualizados INT = @@ROWCOUNT;

    /* --- Baja logica de lo que ya no viene --- */
    SET @sql = N'
    UPDATE ProveedorRepuesto
    SET Activo = 0
    WHERE IdProveedor = @p
      AND CodigoProveedor NOT IN
          (SELECT ' + @eCod + N' FROM StgImportacion s
           WHERE ' + @eCod + N' IS NOT NULL ' + @filtroEnc + N');';

    EXEC sp_executesql @sql, N'@p INT', @p = @IdProveedor;
    DECLARE @desactivados INT = @@ROWCOUNT;

    /* --- Altas --- */
    SET @sql = N'
    INSERT INTO ProveedorRepuesto
        (IdProveedor, CodigoProveedor, Articulo, RubroTexto, MarcaTexto, Descripcion,
         PrecioLista, DescuentoRubro, DescuentoGeneral, PrecioCompra, IdRubro, FechaLista)
    SELECT
        @p, ' + @eCod + N', LEFT(' + @eArt + N', 40), LEFT(' + @eRub + N', 120),
        LEFT(' + @eMar + N', 60), LEFT(' + @eDes + N', 250),
        TRY_CAST(' + @ePre + N' AS DECIMAL(12,2)),
        ' + @eD1 + N', ' + @eD2 + N', ' + @eCosto + N',
        r.Id, @f
    FROM StgImportacion s
    LEFT JOIN Rubro r
        ON UPPER(LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(r.Nombre, ''   '', '' ''), ''  '', '' ''), ''  '', '' ''))))
         = UPPER(LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(' + @eRub + N', ''   '', '' ''), ''  '', '' ''), ''  '', '' ''))))
    WHERE ' + @eCod + N' IS NOT NULL
      AND LTRIM(RTRIM(' + @eCod + N')) <> ''''
      AND TRY_CAST(' + @ePre + N' AS DECIMAL(12,2)) IS NOT NULL
      ' + @filtroEnc + N'
      AND NOT EXISTS (SELECT 1 FROM ProveedorRepuesto pr
                      WHERE pr.IdProveedor = @p AND pr.CodigoProveedor = ' + @eCod + N');';

    EXEC sp_executesql @sql, N'@p INT, @f DATE', @p = @IdProveedor, @f = @FechaLista;
    DECLARE @nuevos INT = @@ROWCOUNT;

    SELECT @actualizados AS Actualizados, @nuevos AS Nuevos, @desactivados AS Desactivados;

    PRINT 'Falta reprocesar el texto de busqueda:';
    PRINT '  EXEC SP_Busqueda_Reprocesar @SoloNuevos = 1;';
END
GO


/* -----------------------------------------------------------------
   5. PASOS PARA CARGAR EXPOYER
   ----------------------------------------------------------------- */
/*
-- a) Generar el archivo unificando las 11 hojas:
--    python preparar_lista.py "ARTICULOS.XLSX" --unir-hojas --salida expoyer.txt
-- b) Copiarlo a C:\Temp\

TRUNCATE TABLE StgImportacion;

BULK INSERT StgImportacion
FROM 'C:\Temp\expoyer.txt'
WITH (DATAFILETYPE = 'widechar', FIELDTERMINATOR = '|',
      ROWTERMINATOR = '0x0a00', TABLOCK);

SELECT COUNT(*) FROM StgImportacion;   -- 103109

-- c) Vista previa ANTES de escribir
DECLARE @p INT; SELECT TOP 1 @p = Id FROM Proveedor WHERE RazonSocial LIKE '%EXPOYER%';
EXEC SP_Importacion_Procesar @IdProveedor = @p, @SoloVistaPrevia = 1;

-- CONTROL: buscar el articulo CD1025572 en la muestra.
-- PrecioLista debe dar 82691,00 y CostoCalculado 27355,84.
-- Si no coincide, PARAR: el perfil esta mal configurado.

-- d) Procesar
DECLARE @p2 INT; SELECT TOP 1 @p2 = Id FROM Proveedor WHERE RazonSocial LIKE '%EXPOYER%';
EXEC SP_Importacion_Procesar @IdProveedor = @p2;

EXEC SP_Busqueda_Reprocesar @SoloNuevos = 1;

-- e) Ahora si: la primera comparacion real entre dos proveedores
EXEC SP_Busqueda_Universal @Texto = 'kit distribucion suran';
EXEC SP_Ahorro_Oportunidades;
*/
GO
