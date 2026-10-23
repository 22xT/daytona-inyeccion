USE [DaytonaInyeccion]
GO

/* =================================================================
   44 — COMPATIBILIDAD CON AZURE: INDICE CLUSTER EN TODAS LAS TABLAS

   La exportacion a .bacpac fallo con SQL71564: StgImportacion y
   StgListaProveedor no tienen indice cluster. SQL Server local lo
   tolera; Azure SQL no deja insertar en tablas sin indice cluster.

   Se agrega un indice cluster NO unico sobre la primera columna de
   cada tabla que no tenga uno. No se agregan ni se cambian columnas:
   el BULK INSERT del importador sigue funcionando igual.

   Es generico a proposito: si en el futuro aparece otra tabla sin
   indice cluster, correr este mismo script la corrige.
   ================================================================= */

DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql = @sql +
    N'CREATE CLUSTERED INDEX ' + QUOTENAME('CIX_' + t.name) +
    N' ON ' + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name) +
    N' (' + QUOTENAME(c.name) + N');' + CHAR(13) + CHAR(10)
FROM sys.tables t
INNER JOIN sys.schemas s ON s.schema_id = t.schema_id
INNER JOIN sys.columns c ON c.object_id = t.object_id AND c.column_id = (
    SELECT MIN(c2.column_id) FROM sys.columns c2
    WHERE c2.object_id = t.object_id
      -- columnas que pueden ser clave de indice
      AND TYPE_NAME(c2.system_type_id) NOT IN ('text', 'ntext', 'image', 'xml')
      AND c2.max_length <> -1)
WHERE t.is_ms_shipped = 0
  AND NOT EXISTS (SELECT 1 FROM sys.indexes i WHERE i.object_id = t.object_id AND i.type = 1);

PRINT 'Se van a crear estos indices:';
PRINT @sql;

IF @sql <> N''
    EXEC sp_executesql @sql;
GO

-- Verificacion: tiene que dar cero filas
SELECT t.name AS TablaSinIndiceCluster
FROM sys.tables t
WHERE t.is_ms_shipped = 0
  AND NOT EXISTS (SELECT 1 FROM sys.indexes i WHERE i.object_id = t.object_id AND i.type = 1);
GO
