/* =================================================================
   90 — LA HORA DE ARGENTINA TAMBIEN EN AZURE (28/10)

   EL PROBLEMA (prueba C4 de Sofi)
   En Azure SQL, GETDATE() devuelve la hora de Londres (UTC). Un pedido
   hecho a las 22:35 quedaba a la 01:35 del dia siguiente. Pasa con
   ventas, caja, pedidos, encargos, auditoria... todo lo que se fecha
   con GETDATE(). En la PC no se nota porque el servidor esta en hora
   argentina.

   LA SOLUCION
   Donde decia GETDATE() pasa a decir DATEADD(HOUR, -3, GETUTCDATE()):
   la hora argentina en cualquier servidor (Argentina no tiene horario
   de verano). Da lo mismo en la PC y en Azure.
     1. Procedimientos, funciones, triggers y vistas: se reescriben
        solos (ALTER) a partir de su definicion actual.
     2. Valores por defecto de las tablas (Fecha DEFAULT GETDATE()):
        se reemplazan.
   Todo o nada: si algo falla, se deshace y dice que objeto fue.
   No toca los datos ya guardados. Se puede correr mas de una vez.
   ================================================================= */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

DECLARE @nueva NVARCHAR(60) = N'DATEADD(HOUR, -3, GETUTCDATE())';

-- Lo que hay que cambiar (se arma antes de tocar nada)
IF OBJECT_ID('tempdb..#modulos') IS NOT NULL DROP TABLE #modulos;
SELECT o.object_id, QUOTENAME(SCHEMA_NAME(o.schema_id)) + '.' + QUOTENAME(o.name) AS Nombre,
       o.type_desc AS Tipo, m.definition AS Definicion
INTO #modulos
FROM sys.sql_modules m
INNER JOIN sys.objects o ON o.object_id = m.object_id
WHERE o.is_ms_shipped = 0
  AND o.type IN ('P', 'FN', 'IF', 'TF', 'TR', 'V')
  AND m.definition LIKE '%GETDATE()%';

IF OBJECT_ID('tempdb..#defaults') IS NOT NULL DROP TABLE #defaults;
SELECT QUOTENAME(SCHEMA_NAME(t.schema_id)) + '.' + QUOTENAME(t.name) AS Tabla,
       dc.name AS Restriccion, c.name AS Columna, dc.definition AS Definicion
INTO #defaults
FROM sys.default_constraints dc
INNER JOIN sys.tables t  ON t.object_id = dc.parent_object_id
INNER JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
WHERE dc.definition LIKE '%getdate()%';

DECLARE @n_mod INT = (SELECT COUNT(*) FROM #modulos), @n_def INT = (SELECT COUNT(*) FROM #defaults);
PRINT 'A cambiar: ' + CAST(@n_mod AS VARCHAR(10)) + ' procedimientos/funciones/triggers/vistas y ' +
      CAST(@n_def AS VARCHAR(10)) + ' valores por defecto.';

DECLARE @actual NVARCHAR(400) = N'', @sql NVARCHAR(MAX), @def NVARCHAR(MAX), @pos INT, @p INT;
DECLARE @nombre NVARCHAR(300), @tabla NVARCHAR(300), @restr SYSNAME, @col SYSNAME, @ddef NVARCHAR(MAX);

BEGIN TRY
    BEGIN TRAN;

    /* 1. Modulos: CREATE -> ALTER y GETDATE() -> hora argentina */
    DECLARE cm CURSOR LOCAL FAST_FORWARD FOR SELECT Nombre, Definicion FROM #modulos;
    OPEN cm;
    FETCH NEXT FROM cm INTO @nombre, @def;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @actual = @nombre;
        -- Donde empieza la sentencia CREATE (la primera de estas que aparezca)
        SET @pos = 0;
        SET @p = CHARINDEX('CREATE PROCEDURE', @def); IF @p > 0 AND (@pos = 0 OR @p < @pos) SET @pos = @p;
        SET @p = CHARINDEX('CREATE PROC ',     @def); IF @p > 0 AND (@pos = 0 OR @p < @pos) SET @pos = @p;
        SET @p = CHARINDEX('CREATE FUNCTION',  @def); IF @p > 0 AND (@pos = 0 OR @p < @pos) SET @pos = @p;
        SET @p = CHARINDEX('CREATE TRIGGER',   @def); IF @p > 0 AND (@pos = 0 OR @p < @pos) SET @pos = @p;
        SET @p = CHARINDEX('CREATE VIEW',      @def); IF @p > 0 AND (@pos = 0 OR @p < @pos) SET @pos = @p;
        IF @pos = 0
            RAISERROR('No encontre el CREATE de %s', 16, 1, @nombre);

        SET @sql = STUFF(@def, @pos, 6, 'ALTER');
        SET @sql = REPLACE(@sql, 'GETDATE()', @nueva);
        EXEC sp_executesql @sql;
        FETCH NEXT FROM cm INTO @nombre, @def;
    END
    CLOSE cm; DEALLOCATE cm;

    /* 2. Valores por defecto de las tablas */
    DECLARE cd CURSOR LOCAL FAST_FORWARD FOR SELECT Tabla, Restriccion, Columna, Definicion FROM #defaults;
    OPEN cd;
    FETCH NEXT FROM cd INTO @tabla, @restr, @col, @ddef;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @actual = @tabla + N'.' + @col;
        SET @sql = N'ALTER TABLE ' + @tabla + N' DROP CONSTRAINT ' + QUOTENAME(@restr) + N'; ' +
                   N'ALTER TABLE ' + @tabla + N' ADD CONSTRAINT ' + QUOTENAME(@restr) +
                   -- Se respeta el resto de la expresion (ej. CONVERT(date, getdate()))
                   N' DEFAULT ' + REPLACE(@ddef, 'getdate()', @nueva) + N' FOR ' + QUOTENAME(@col) + N';';
        EXEC sp_executesql @sql;
        FETCH NEXT FROM cd INTO @tabla, @restr, @col, @ddef;
    END
    CLOSE cd; DEALLOCATE cd;

    COMMIT;
    PRINT 'Listo: ' + CAST(@n_mod AS VARCHAR(10)) + ' objetos y ' + CAST(@n_def AS VARCHAR(10)) + ' valores por defecto en hora argentina.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    PRINT 'NO SE CAMBIO NADA. Fallo en: ' + @actual;
    PRINT ERROR_MESSAGE();
END CATCH
GO

/* Control: tiene que dar 0 y 0, y la hora de ahora en Argentina */
SELECT
    (SELECT COUNT(*) FROM sys.sql_modules m INNER JOIN sys.objects o ON o.object_id = m.object_id
      WHERE o.is_ms_shipped = 0 AND m.definition LIKE '%GETDATE()%')           AS ObjetosConGetdate,
    (SELECT COUNT(*) FROM sys.default_constraints WHERE definition LIKE '%getdate()%') AS DefaultsConGetdate,
    DATEADD(HOUR, -3, GETUTCDATE())                                             AS HoraArgentina;
GO
