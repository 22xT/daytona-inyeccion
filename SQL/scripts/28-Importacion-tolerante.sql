USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   28 — FILAS INCOMPLETAS EN LA LISTA DEL PROVEEDOR

   PROBLEMA
   La lista de Expoyer trae 9 articulos de Renault SIN DESCRIPCION.
   No es un error de la conversion: vienen asi del proveedor.
   Con una sola de esas filas, el INSERT falla entero y no entra
   ninguna de las 103.109.

   DECISION
   Se saltean. Un articulo sin descripcion no se puede buscar ni
   identificar, asi que no aporta nada al catalogo.

   Pero NO en silencio: el SP informa cuantas filas descarto y por
   que. Un proceso que descarta datos sin decirlo es peor que uno
   que falla, porque el problema aparece meses despues cuando alguien
   busca algo que deberia estar.
   ================================================================= */

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

    DECLARE @eD1 VARCHAR(80) = CASE WHEN @cD1 IS NULL THEN CAST(@dFijo1 AS VARCHAR(20))
                                    ELSE 'ISNULL(TRY_CAST(s.Col' + CAST(@cD1 AS VARCHAR(2)) + ' AS DECIMAL(6,2)),0)' END;
    DECLARE @eD2 VARCHAR(80) = CASE WHEN @cD2 IS NULL THEN CAST(@dFijo2 AS VARCHAR(20))
                                    ELSE 'ISNULL(TRY_CAST(s.Col' + CAST(@cD2 AS VARCHAR(2)) + ' AS DECIMAL(6,2)),0)' END;

    DECLARE @eCosto NVARCHAR(500);
    IF @esquema = 'CostoEnColumna' AND @cCos IS NOT NULL
        SET @eCosto = N'TRY_CAST(s.Col' + CAST(@cCos AS VARCHAR(2)) + N' AS DECIMAL(12,2))';
    ELSE IF @esquema = 'CostoDirecto'
        SET @eCosto = N'TRY_CAST(' + @ePre + N' AS DECIMAL(12,2))';
    ELSE IF @esquema = 'UnDescuento'
        SET @eCosto = N'CAST(TRY_CAST(' + @ePre + N' AS DECIMAL(12,2)) * (1 - ' + @eD1 + N'/100.0) AS DECIMAL(12,2))';
    ELSE
        SET @eCosto = N'CAST(TRY_CAST(' + @ePre + N' AS DECIMAL(12,2)) * (1 - ' + @eD1 + N'/100.0) * (1 - ' + @eD2 + N'/100.0) AS DECIMAL(12,2))';

    /* Condiciones que una fila tiene que cumplir para entrar.
       Se aplican tanto en el conteo de descartes como en el INSERT,
       para que los numeros que se informan sean los reales. */
    DECLARE @valida NVARCHAR(MAX) =
        N' ' + @eCod + N' IS NOT NULL AND LTRIM(RTRIM(' + @eCod + N')) <> '''' ' +
        N' AND ' + @eDes + N' IS NOT NULL AND LTRIM(RTRIM(' + @eDes + N')) <> '''' ' +
        N' AND TRY_CAST(' + @ePre + N' AS DECIMAL(12,2)) IS NOT NULL ';

    DECLARE @filtroEnc VARCHAR(40) = ' AND s.Fila > ' + CAST(@enc AS VARCHAR(3));
    DECLARE @sql NVARCHAR(MAX);

    /* --- Vista previa --- */
    IF @SoloVistaPrevia = 1
    BEGIN
        SET @sql = N'
        SELECT
            COUNT(*) AS FilasEnArchivo,
            SUM(CASE WHEN ' + @eCod + N' IS NULL OR LTRIM(RTRIM(' + @eCod + N')) = '''' THEN 1 ELSE 0 END) AS SinCodigo,
            SUM(CASE WHEN ' + @eDes + N' IS NULL OR LTRIM(RTRIM(' + @eDes + N')) = '''' THEN 1 ELSE 0 END) AS SinDescripcion,
            SUM(CASE WHEN TRY_CAST(' + @ePre + N' AS DECIMAL(12,2)) IS NULL THEN 1 ELSE 0 END) AS PrecioNoNumerico,
            SUM(CASE WHEN ISNULL(' + @eCosto + N', 0) <= 0 THEN 1 ELSE 0 END) AS CostoCero,
            SUM(CASE WHEN ' + @valida + N' THEN 1 ELSE 0 END) AS FilasQueEntrarian
        FROM StgImportacion s WHERE 1=1 ' + @filtroEnc + N';

        SELECT TOP 10
            ' + @eCod + N' AS Codigo, ' + @eDes + N' AS Descripcion,
            TRY_CAST(' + @ePre + N' AS DECIMAL(12,2)) AS PrecioLista,
            ' + @eCosto + N' AS CostoCalculado
        FROM StgImportacion s WHERE ' + @valida + @filtroEnc + N';

        -- Las que se van a descartar, para poder mirarlas
        SELECT TOP 20
            ' + @eCod + N' AS Codigo, ' + @eDes + N' AS Descripcion,
            ' + @ePre + N' AS Precio,
            CASE WHEN ' + @eCod + N' IS NULL OR LTRIM(RTRIM(' + @eCod + N')) = '''' THEN ''Sin codigo''
                 WHEN ' + @eDes + N' IS NULL OR LTRIM(RTRIM(' + @eDes + N')) = '''' THEN ''Sin descripcion''
                 ELSE ''Precio no numerico'' END AS Motivo
        FROM StgImportacion s WHERE NOT (' + @valida + N') ' + @filtroEnc + N';';

        EXEC sp_executesql @sql;
        RETURN;
    END

    /* --- Cuantas se descartan --- */
    DECLARE @tablaConteo TABLE (Descartadas INT);
    SET @sql = N'SELECT COUNT(*) FROM StgImportacion s WHERE NOT (' + @valida + N') ' + @filtroEnc + N';';
    INSERT INTO @tablaConteo EXEC sp_executesql @sql;
    DECLARE @descartadas INT = (SELECT TOP 1 Descartadas FROM @tablaConteo);

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
    WHERE pr.IdProveedor = @p AND ' + @valida + @filtroEnc + N';';

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
    WHERE ' + @valida + @filtroEnc + N'
      AND NOT EXISTS (SELECT 1 FROM ProveedorRepuesto pr
                      WHERE pr.IdProveedor = @p AND pr.CodigoProveedor = ' + @eCod + N');';

    EXEC sp_executesql @sql, N'@p INT, @f DATE', @p = @IdProveedor, @f = @FechaLista;
    DECLARE @nuevos INT = @@ROWCOUNT;

    SELECT @actualizados AS Actualizados,
           @nuevos       AS Nuevos,
           @desactivados AS Desactivados,
           @descartadas  AS Descartadas;

    IF @descartadas > 0
        PRINT 'ATENCION: se descartaron ' + CAST(@descartadas AS VARCHAR(10)) +
              ' filas por venir incompletas. Correr con @SoloVistaPrevia = 1 para verlas.';

    PRINT 'Falta reprocesar el texto de busqueda:';
    PRINT '  EXEC SP_Busqueda_Reprocesar @SoloNuevos = 1;';
END
GO


/* =================================================================
   EJECUTAR AHORA
   ================================================================= */

-- 1. Vista previa: mirar SinDescripcion y FilasQueEntrarian
DECLARE @p1 INT;
SELECT TOP 1 @p1 = Id FROM Proveedor WHERE RazonSocial LIKE '%EXPOYER%';
EXEC SP_Importacion_Procesar @IdProveedor = @p1, @SoloVistaPrevia = 1;
GO

-- 2. Procesar. Esperado: 103.100 nuevos y 9 descartados.
DECLARE @p2 INT;
SELECT TOP 1 @p2 = Id FROM Proveedor WHERE RazonSocial LIKE '%EXPOYER%';
EXEC SP_Importacion_Procesar @IdProveedor = @p2, @FechaLista = '2026-09-08';
GO

-- 3. Texto de busqueda. Sobre 156.000 filas tarda varios minutos.
EXEC SP_Busqueda_Reprocesar @SoloNuevos = 1;
GO

-- 4. Estado final
SELECT p.RazonSocial, COUNT(*) AS Articulos,
       SUM(CASE WHEN pr.IdRepuesto IS NOT NULL THEN 1 ELSE 0 END) AS Enlazados
FROM ProveedorRepuesto pr
INNER JOIN Proveedor p ON p.Id = pr.IdProveedor
WHERE pr.Activo = 1
GROUP BY p.RazonSocial;
GO
