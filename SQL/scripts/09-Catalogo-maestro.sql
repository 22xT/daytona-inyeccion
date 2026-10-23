USE [DaytonaInyeccion];
GO

/* =================================================================
   CATALOGO MAESTRO

   Un Repuesto = una pieza fisica. Un solo stock.
   Los codigos de cada proveedor viven en ProveedorRepuesto.

   El codigo del FABRICANTE (A0254 de Perfecto, AC25085 de Nakata)
   es lo mas parecido a una identidad real que existe: si Sudimar
   vende la misma abrazadera Perfecto, la lista con el mismo A0254.
   El codigo del distribuidor (359V001) es interno de Autocor y no
   sirve fuera de ahi.

   OJO: el codigo de fabricante NO es una clave. En la lista de
   Autocor hay 7.934 articulos repetidos, y algunos son basura
   (el articulo "5" aparece en cuatro piezas distintas). Por eso
   el enlace se SUGIERE y lo confirma una persona. Un duplicado se
   arregla despues; una fusion equivocada corrompe el stock.
   ================================================================= */

/* -----------------------------------------------------------------
   1. REPUESTO — identidad del fabricante

   MarcaFabricante es un campo NUEVO, no se reusa IdMarca:
   en este sistema Marca es la marca del AUTO (Fiat, Peugeot).
   El fabricante del repuesto es otra cosa (Perfecto, Nakata).
   ----------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('Repuesto') AND name = 'CodigoFabricante')
    ALTER TABLE Repuesto ADD CodigoFabricante VARCHAR(40) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('Repuesto') AND name = 'MarcaFabricante')
    ALTER TABLE Repuesto ADD MarcaFabricante VARCHAR(60) NULL;
GO

CREATE INDEX IX_Repuesto_CodigoFabricante ON Repuesto(CodigoFabricante);
GO


/* -----------------------------------------------------------------
   2. El Codigo deja de ser SIGLA-NNNN

   Pasa a ser texto libre: se llena con el codigo del proveedor por
   el que se incorporo el repuesto. Sigue siendo unico entre los que
   tienen codigo, con indice filtrado para permitir NULL.
   ----------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM sys.columns
           WHERE object_id = OBJECT_ID('Repuesto') AND name = 'Codigo' AND is_nullable = 0)
    ALTER TABLE Repuesto ALTER COLUMN Codigo VARCHAR(40) NULL;
GO

UPDATE Repuesto SET Codigo = NULL WHERE LTRIM(RTRIM(ISNULL(Codigo, ''))) = '';
GO

-- Se saca cualquier unique viejo sobre Codigo y se pone uno filtrado
DECLARE @uq SYSNAME, @sql NVARCHAR(500);

SELECT TOP 1 @uq = i.name
FROM sys.indexes i
JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns c ON c.object_id = i.object_id AND c.column_id = ic.column_id
WHERE i.object_id = OBJECT_ID('Repuesto')
  AND i.is_unique = 1 AND i.is_primary_key = 0
  AND c.name = 'Codigo'
  AND i.has_filter = 0;

IF @uq IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM sys.key_constraints
               WHERE parent_object_id = OBJECT_ID('Repuesto') AND name = @uq)
        SET @sql = 'ALTER TABLE Repuesto DROP CONSTRAINT [' + @uq + ']';
    ELSE
        SET @sql = 'DROP INDEX [' + @uq + '] ON Repuesto';
    EXEC sp_executesql @sql;
    PRINT 'Se quito el unique viejo sobre Codigo: ' + @uq;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID('Repuesto') AND name = 'UX_Repuesto_Codigo')
    CREATE UNIQUE NONCLUSTERED INDEX UX_Repuesto_Codigo
        ON Repuesto(Codigo) WHERE Codigo IS NOT NULL;
GO


/* -----------------------------------------------------------------
   3. RUBROS QUE FALTAN

   Se crean desde la tabla de paso, comparando con normalizacion de
   espacios: la lista trae 'BULBO  ELECTROVENTILADOR "MD"' con dos
   espacios y la base tiene uno solo.

   CORRER ESTO DESPUES DEL BULK INSERT Y ANTES DEL VOLCADO
   (entre las secciones 5 y 6 del script 07). Si el volcado corre
   primero, los articulos de esos rubros quedan con IdRubro NULL.
   ----------------------------------------------------------------- */
IF OBJECT_ID('StgListaProveedor', 'U') IS NULL
BEGIN
    PRINT 'No existe StgListaProveedor. Corre primero el BULK INSERT del script 07.';
    RETURN;
END
GO

-- Rubros de la lista que no estan en la base
IF OBJECT_ID('tempdb..#RubrosNuevos') IS NOT NULL DROP TABLE #RubrosNuevos;

SELECT DISTINCT
    LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(s.Rubro, '   ', ' '), '  ', ' '), '  ', ' '))) AS Nombre
INTO #RubrosNuevos
FROM StgListaProveedor s
WHERE NOT EXISTS (
    SELECT 1 FROM Rubro r
    WHERE UPPER(LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(r.Nombre, '   ', ' '), '  ', ' '), '  ', ' '))))
        = UPPER(LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(s.Rubro, '   ', ' '), '  ', ' '), '  ', ' ')))));

SELECT COUNT(*) AS RubrosACrear FROM #RubrosNuevos;
SELECT Nombre FROM #RubrosNuevos ORDER BY Nombre;
GO

-- El alta contempla que Rubro pueda tener columnas obligatorias
-- distintas segun como este armada la tabla. Se resuelve en tiempo
-- de ejecucion en vez de asumir una estructura.
DECLARE @tieneSigla BIT = 0, @tieneActivo BIT = 0, @sqlIns NVARCHAR(MAX);

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Rubro') AND name = 'Sigla')
    SET @tieneSigla = 1;
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Rubro') AND name = 'Activo')
    SET @tieneActivo = 1;

IF @tieneSigla = 1
BEGIN
    -- Sigla = tres primeras letras del nombre. Si ya existe, se le
    -- agrega un numero, que es la convencion que ya usa el sistema
    -- (BOM15, SEN12, ART2, BUJ2).
    SET @sqlIns = N'
    WITH Base AS (
        SELECT Nombre,
               UPPER(LEFT(REPLACE(REPLACE(Nombre, '' '', ''''), ''"'', ''''), 3)) AS SiglaBase
        FROM #RubrosNuevos
    ),
    Numerada AS (
        SELECT Nombre, SiglaBase,
               ROW_NUMBER() OVER (PARTITION BY SiglaBase ORDER BY Nombre) AS rn
        FROM Base
    )
    INSERT INTO Rubro (Nombre, Sigla' + CASE WHEN @tieneActivo = 1 THEN N', Activo' ELSE N'' END + N')
    SELECT n.Nombre,
           CASE WHEN EXISTS (SELECT 1 FROM Rubro r WHERE r.Sigla = n.SiglaBase) OR n.rn > 1
                THEN n.SiglaBase + CAST(n.rn + (SELECT COUNT(*) FROM Rubro r2 WHERE r2.Sigla LIKE n.SiglaBase + ''%'') AS VARCHAR(5))
                ELSE n.SiglaBase END
           ' + CASE WHEN @tieneActivo = 1 THEN N', 1' ELSE N'' END + N'
    FROM Numerada n;';
END
ELSE
BEGIN
    SET @sqlIns = N'INSERT INTO Rubro (Nombre' + CASE WHEN @tieneActivo = 1 THEN N', Activo' ELSE N'' END + N')
                    SELECT Nombre' + CASE WHEN @tieneActivo = 1 THEN N', 1' ELSE N'' END + N'
                    FROM #RubrosNuevos;';
END

PRINT 'Rubro tiene Sigla: ' + CAST(@tieneSigla AS VARCHAR(1));
EXEC sp_executesql @sqlIns;
PRINT 'Rubros creados: ' + CAST(@@ROWCOUNT AS VARCHAR(10));
GO

SELECT COUNT(*) AS TotalRubrosAhora FROM Rubro;
GO


/* -----------------------------------------------------------------
   4. SP: sugerir enlaces entre la lista y tu catalogo

   NO enlaza nada. Devuelve candidatos con su nivel de confianza
   para que una persona confirme.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Proveedor_SugerirEnlaces', 'P') IS NOT NULL
    DROP PROCEDURE SP_Proveedor_SugerirEnlaces;
GO

CREATE PROCEDURE SP_Proveedor_SugerirEnlaces
    @IdProveedor INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        r.Id                AS IdRepuesto,
        r.Codigo            AS MiCodigo,
        r.Descripcion       AS MiDescripcion,
        r.CodigoFabricante  AS MiCodigoFabricante,
        r.PrecioCompra      AS MiCostoActual,

        pr.Id               AS IdListaProveedor,
        pr.CodigoProveedor,
        pr.Articulo         AS CodigoFabricanteProveedor,
        pr.Descripcion      AS DescripcionProveedor,
        pr.PrecioCompra     AS CostoProveedor,

        CASE WHEN r.PrecioCompra > 0
             THEN CAST((pr.PrecioCompra - r.PrecioCompra) / r.PrecioCompra * 100 AS DECIMAL(6,2))
             ELSE NULL END  AS DiferenciaPorc,

        -- Alta: mismo codigo de fabricante Y mismo rubro.
        -- Se exige el rubro porque hay codigos de fabricante basura
        -- repetidos en piezas que no tienen nada que ver.
        CASE
            WHEN r.CodigoFabricante IS NOT NULL
             AND pr.Articulo = r.CodigoFabricante
             AND pr.IdRubro = r.IdRubro          THEN 'Alta'
            WHEN r.CodigoFabricante IS NOT NULL
             AND pr.Articulo = r.CodigoFabricante THEN 'Media'
            WHEN UPPER(LTRIM(RTRIM(pr.Descripcion))) = UPPER(LTRIM(RTRIM(r.Descripcion)))
                                                  THEN 'Media'
            ELSE 'Baja'
        END AS Confianza

    FROM Repuesto r
    INNER JOIN ProveedorRepuesto pr
        ON pr.IdProveedor = @IdProveedor
       AND pr.Activo = 1
       AND pr.IdRepuesto IS NULL      -- solo los que todavia no estan enlazados
       AND (
             (r.CodigoFabricante IS NOT NULL AND pr.Articulo = r.CodigoFabricante)
             OR pr.Descripcion LIKE '%' + LEFT(r.Descripcion, 15) + '%'
           )
    WHERE r.Activo = 1
    ORDER BY
        CASE WHEN r.CodigoFabricante IS NOT NULL AND pr.Articulo = r.CodigoFabricante
                  AND pr.IdRubro = r.IdRubro THEN 1
             WHEN r.CodigoFabricante IS NOT NULL AND pr.Articulo = r.CodigoFabricante THEN 2
             ELSE 3 END,
        r.Descripcion;
END
GO


/* -----------------------------------------------------------------
   5. SP: confirmar un enlace
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Proveedor_EnlazarRepuesto', 'P') IS NOT NULL
    DROP PROCEDURE SP_Proveedor_EnlazarRepuesto;
GO

CREATE PROCEDURE SP_Proveedor_EnlazarRepuesto
    @IdListaProveedor INT,
    @IdRepuesto       INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM ProveedorRepuesto WHERE Id = @IdListaProveedor)
    BEGIN
        RAISERROR('El articulo de la lista no existe.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM Repuesto WHERE Id = @IdRepuesto)
    BEGIN
        RAISERROR('El repuesto indicado no existe.', 16, 1);
        RETURN;
    END

    -- Un proveedor no puede tener dos articulos apuntando al mismo
    -- repuesto: seria el mismo producto cotizado dos veces.
    IF EXISTS (SELECT 1 FROM ProveedorRepuesto pr
               INNER JOIN ProveedorRepuesto nuevo ON nuevo.Id = @IdListaProveedor
               WHERE pr.IdProveedor = nuevo.IdProveedor
                 AND pr.IdRepuesto = @IdRepuesto
                 AND pr.Id <> @IdListaProveedor)
    BEGIN
        RAISERROR('Ese proveedor ya tiene otro articulo enlazado a este repuesto.', 16, 1);
        RETURN;
    END

    UPDATE ProveedorRepuesto SET IdRepuesto = @IdRepuesto WHERE Id = @IdListaProveedor;
END
GO


/* -----------------------------------------------------------------
   6. VISTA: todos los proveedores de cada repuesto, ordenados por costo
   Es lo que alimenta la comparacion en Reposicion sugerida.
   ----------------------------------------------------------------- */
IF OBJECT_ID('vw_RepuestoProveedores', 'V') IS NOT NULL DROP VIEW vw_RepuestoProveedores;
GO

CREATE VIEW vw_RepuestoProveedores AS
SELECT
    pr.IdRepuesto,
    pr.IdProveedor,
    p.RazonSocial       AS Proveedor,
    pr.CodigoProveedor,
    pr.Articulo,
    pr.PrecioLista,
    pr.DescuentoRubro,
    pr.DescuentoGeneral,
    pr.PrecioCompra,
    pr.FechaLista,
    ROW_NUMBER() OVER (PARTITION BY pr.IdRepuesto ORDER BY pr.PrecioCompra) AS Ranking
FROM ProveedorRepuesto pr
INNER JOIN Proveedor p ON p.Id = pr.IdProveedor
WHERE pr.IdRepuesto IS NOT NULL
  AND pr.Activo = 1
  AND pr.PrecioCompra > 0;
GO


/* -----------------------------------------------------------------
   7. VERIFICACION
   ----------------------------------------------------------------- */
SELECT c.name AS ColumnaNuevaEnRepuesto
FROM sys.columns c
WHERE c.object_id = OBJECT_ID('Repuesto')
  AND c.name IN ('CodigoFabricante', 'MarcaFabricante', 'PrecioCompra', 'PrecioNetoVenta');

SELECT name AS Indice, is_unique, filter_definition
FROM sys.indexes WHERE object_id = OBJECT_ID('Repuesto');

SELECT COUNT(*) AS TotalRubros FROM Rubro;
GO
