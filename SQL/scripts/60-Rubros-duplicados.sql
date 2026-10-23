USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   60 — RUBROS DUPLICADOS

   Hay rubros que son el mismo escrito distinto: DIVAIO / DIVIAO,
   SEMI EJES / SEMIEJES, THOMPSON / THOMSON. Los repuestos quedan
   repartidos entre los dos, el margen por rubro se aplica a medias y
   los reportes por rubro muestran dos filas para lo mismo.

   EN DOS PASOS, PARA NO UNIR NADA POR ERROR
   1. Diagnostico (este script): lista los pares sospechosos y arma la
      linea para unir cada uno. NO MODIFICA NADA.
   2. Unificacion: se copian y corren solo las lineas de los pares que
      una persona confirmo que son el mismo rubro.

   Al unir, el rubro que queda es el que tiene mas repuestos. Todos los
   repuestos y articulos de proveedor del otro pasan a este, y el otro
   se desactiva (no se borra).
   ================================================================= */


/* -----------------------------------------------------------------
   1. Distancia entre dos textos (cuantas letras hay que cambiar,
      agregar o quitar para pasar de uno al otro)
   ----------------------------------------------------------------- */
IF OBJECT_ID('fn_Levenshtein', 'FN') IS NOT NULL DROP FUNCTION fn_Levenshtein;
GO
CREATE FUNCTION fn_Levenshtein (@a NVARCHAR(100), @b NVARCHAR(100))
RETURNS INT
AS
BEGIN
    DECLARE @la INT = LEN(@a), @lb INT = LEN(@b);
    IF @la = 0 RETURN @lb;
    IF @lb = 0 RETURN @la;

    -- Una fila de la matriz, guardada como texto de numeros de 3 cifras
    DECLARE @prev NVARCHAR(400) = N'', @cur NVARCHAR(400), @j INT = 0, @i INT;
    WHILE @j <= @lb BEGIN SET @prev += RIGHT(N'000' + CAST(@j AS NVARCHAR(3)), 3); SET @j += 1; END

    SET @i = 1;
    WHILE @i <= @la
    BEGIN
        SET @cur = RIGHT(N'000' + CAST(@i AS NVARCHAR(3)), 3);
        SET @j = 1;
        WHILE @j <= @lb
        BEGIN
            DECLARE @costo INT = CASE WHEN SUBSTRING(@a, @i, 1) = SUBSTRING(@b, @j, 1) THEN 0 ELSE 1 END;
            DECLARE @arriba INT = CAST(SUBSTRING(@prev, @j * 3 + 1, 3) AS INT) + 1;
            DECLARE @izq    INT = CAST(SUBSTRING(@cur, (@j - 1) * 3 + 1, 3) AS INT) + 1;
            DECLARE @diag   INT = CAST(SUBSTRING(@prev, (@j - 1) * 3 + 1, 3) AS INT) + @costo;
            DECLARE @m INT = @arriba;
            IF @izq < @m SET @m = @izq;
            IF @diag < @m SET @m = @diag;
            SET @cur += RIGHT(N'000' + CAST(@m AS NVARCHAR(3)), 3);
            SET @j += 1;
        END
        SET @prev = @cur;
        SET @i += 1;
    END
    RETURN CAST(SUBSTRING(@prev, @lb * 3 + 1, 3) AS INT);
END
GO


/* -----------------------------------------------------------------
   2. Unir dos rubros
   Mueve TODO lo que apunta al rubro de origen (repuestos, articulos
   de proveedor y cualquier otra tabla con clave foranea a Rubro) al de
   destino, y desactiva el de origen. Todo o nada.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Rubro_Unificar', 'P') IS NOT NULL DROP PROCEDURE SP_Rubro_Unificar;
GO
CREATE PROCEDURE SP_Rubro_Unificar
    @IdQueda INT,
    @IdSeVa  INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @IdQueda = @IdSeVa
        THROW 50110, 'Los dos rubros son el mismo.', 1;
    IF NOT EXISTS (SELECT 1 FROM Rubro WHERE Id = @IdQueda) OR NOT EXISTS (SELECT 1 FROM Rubro WHERE Id = @IdSeVa)
        THROW 50111, 'Uno de los rubros no existe.', 1;

    -- Si los dos tienen margen propio y son distintos, alguien tiene que decidir
    DECLARE @mQ DECIMAL(6,2), @mV DECIMAL(6,2);
    SELECT @mQ = MargenPorcentaje FROM Rubro WHERE Id = @IdQueda;
    SELECT @mV = MargenPorcentaje FROM Rubro WHERE Id = @IdSeVa;
    IF @mQ IS NOT NULL AND @mV IS NOT NULL AND @mQ <> @mV
        THROW 50112, 'Los dos rubros tienen un margen propio distinto. Igualalos en Beneficios y parametros antes de unirlos.', 1;

    -- Todas las columnas de otras tablas que apuntan a Rubro
    DECLARE @sql NVARCHAR(MAX) = N'';
    SELECT @sql += N'UPDATE ' + QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name) +
                   N' SET ' + QUOTENAME(c.name) + N' = @q WHERE ' + QUOTENAME(c.name) + N' = @v; '
    FROM sys.foreign_key_columns fkc
    INNER JOIN sys.tables  t ON t.object_id = fkc.parent_object_id
    INNER JOIN sys.columns c ON c.object_id = fkc.parent_object_id AND c.column_id = fkc.parent_column_id
    WHERE fkc.referenced_object_id = OBJECT_ID('Rubro');

    BEGIN TRY
        BEGIN TRANSACTION;

        EXEC sp_executesql @sql, N'@q INT, @v INT', @q = @IdQueda, @v = @IdSeVa;

        -- El margen del que se va se conserva si el que queda no tenia
        IF @mQ IS NULL AND @mV IS NOT NULL
            UPDATE Rubro SET MargenPorcentaje = @mV WHERE Id = @IdQueda;

        IF COL_LENGTH('Rubro', 'Activo') IS NOT NULL
            EXEC sp_executesql N'UPDATE Rubro SET Activo = 0 WHERE Id = @v', N'@v INT', @v = @IdSeVa;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    SELECT q.Id, q.Nombre AS Queda, v.Nombre AS SeUnio,
           (SELECT COUNT(*) FROM Repuesto r WHERE r.IdRubro = @IdQueda) AS RepuestosAhora
    FROM Rubro q CROSS JOIN Rubro v
    WHERE q.Id = @IdQueda AND v.Id = @IdSeVa;
END
GO


/* -----------------------------------------------------------------
   3. DIAGNOSTICO: pares sospechosos. No modifica nada.

   Se comparan los nombres sin espacios, guiones, puntos ni tildes.
   Es sospechoso si quedan iguales (SEMI EJES / SEMIEJES) o si difieren
   en una letra (THOMPSON / THOMSON), o en dos si el nombre es largo.
   ----------------------------------------------------------------- */
IF OBJECT_ID('tempdb..#R') IS NOT NULL DROP TABLE #R;

SELECT ru.Id, ru.Nombre,
       -- Sin tildes, sin espacios ni signos
       REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
           UPPER(LTRIM(RTRIM(ru.Nombre))) COLLATE Latin1_General_CI_AI,
           ' ', ''), '-', ''), '.', ''), '/', ''), '"', ''), '''', '') AS Clave,
       (SELECT COUNT(*) FROM Repuesto r WHERE r.IdRubro = ru.Id) AS Repuestos
INTO #R
FROM Rubro ru
WHERE COL_LENGTH('Rubro', 'Activo') IS NULL OR ru.Id IN (SELECT Id FROM Rubro WHERE 1 = 1);

-- Si existe la columna Activo, solo se comparan los activos
IF COL_LENGTH('Rubro', 'Activo') IS NOT NULL
    EXEC sp_executesql N'DELETE FROM #R WHERE Id IN (SELECT Id FROM Rubro WHERE Activo = 0)';

SELECT
    a.Nombre AS RubroA, a.Repuestos AS RepuestosA,
    b.Nombre AS RubroB, b.Repuestos AS RepuestosB,
    CASE WHEN a.Clave = b.Clave THEN 'Mismo texto'
         ELSE 'Difiere en ' + CAST(dbo.fn_Levenshtein(a.Clave, b.Clave) AS VARCHAR(2)) + ' letra(s)' END AS Motivo,
    -- Linea lista para copiar si se confirma: queda el que tiene mas repuestos
    'EXEC SP_Rubro_Unificar @IdQueda = ' +
        CAST(CASE WHEN a.Repuestos >= b.Repuestos THEN a.Id ELSE b.Id END AS VARCHAR(10)) +
        ', @IdSeVa = ' +
        CAST(CASE WHEN a.Repuestos >= b.Repuestos THEN b.Id ELSE a.Id END AS VARCHAR(10)) +
        ';  -- queda ' + CASE WHEN a.Repuestos >= b.Repuestos THEN a.Nombre ELSE b.Nombre END AS ParaUnir
FROM #R a
INNER JOIN #R b ON a.Id < b.Id
WHERE a.Clave = b.Clave
   OR (ABS(LEN(a.Clave) - LEN(b.Clave)) <= 2
       AND LEFT(a.Clave, 1) = LEFT(b.Clave, 1)          -- descarta rapido los que no se parecen
       AND dbo.fn_Levenshtein(a.Clave, b.Clave) <= CASE WHEN LEN(a.Clave) >= 8 THEN 2 ELSE 1 END)
ORDER BY a.Nombre;
GO


/* -----------------------------------------------------------------
   4. UNIFICACION — copiar aca SOLO las lineas confirmadas de la
      columna ParaUnir y correr este bloque seleccionado.
   ----------------------------------------------------------------- */
/*
EXEC SP_Rubro_Unificar @IdQueda = 0, @IdSeVa = 0;
*/
