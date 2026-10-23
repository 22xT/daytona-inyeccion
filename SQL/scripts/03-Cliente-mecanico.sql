USE [DaytonaInyeccion];
GO

/* =================================================================
   Cliente — DNI opcional + marca de mecánico

   Por qué un índice filtrado y no dejar el UNIQUE existente:
   en SQL Server un UNIQUE clásico permite UN SOLO NULL. Con el DNI
   nullable, el primer mecánico sin documento entra y el segundo
   revienta con violación de constraint. El índice filtrado
   (WHERE Dni IS NOT NULL) sigue impidiendo DNI repetidos pero
   ignora los NULL, así que podés tener todos los mecánicos que
   quieras sin documento.
   ================================================================= */

/* -----------------------------------------------------------------
   0. Ver qué columna cubre el UNIQUE actual, antes de tocarlo
   ----------------------------------------------------------------- */
SELECT i.name AS Indice, c.name AS Columna, i.is_unique, i.is_primary_key
FROM sys.indexes i
JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns c ON c.object_id = i.object_id AND c.column_id = ic.column_id
WHERE i.object_id = OBJECT_ID('Cliente') AND i.is_unique = 1;
GO
-- Si el UNIQUE NO es sobre Dni, PARÁ ACÁ y avisá antes de seguir.


/* -----------------------------------------------------------------
   1. Sacar el UNIQUE de Dni
   El nombre tiene sufijo autogenerado, así que se busca dinámicamente.
   ----------------------------------------------------------------- */
DECLARE @nombreUQ SYSNAME, @sql NVARCHAR(500);

SELECT TOP 1 @nombreUQ = i.name
FROM sys.indexes i
JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns c ON c.object_id = i.object_id AND c.column_id = ic.column_id
WHERE i.object_id = OBJECT_ID('Cliente')
  AND i.is_unique = 1
  AND i.is_primary_key = 0
  AND c.name = 'Dni';

IF @nombreUQ IS NOT NULL
BEGIN
    -- Puede estar como constraint o como índice, según cómo se creó
    IF EXISTS (SELECT 1 FROM sys.key_constraints
               WHERE parent_object_id = OBJECT_ID('Cliente') AND name = @nombreUQ)
        SET @sql = 'ALTER TABLE Cliente DROP CONSTRAINT [' + @nombreUQ + ']';
    ELSE
        SET @sql = 'DROP INDEX [' + @nombreUQ + '] ON Cliente';

    EXEC sp_executesql @sql;
    PRINT 'Constraint removida: ' + @nombreUQ;
END
ELSE
    PRINT 'No se encontró UNIQUE sobre Dni. Revisar el paso 0.';
GO


/* -----------------------------------------------------------------
   2. DNI pasa a opcional
   ----------------------------------------------------------------- */
ALTER TABLE Cliente ALTER COLUMN Dni VARCHAR(8) NULL;
GO

-- Los que quedaron con string vacío pasan a NULL: '' y '' son iguales
-- entre sí y volverían a chocar contra el índice único.
UPDATE Cliente SET Dni = NULL WHERE LTRIM(RTRIM(Dni)) = '';
GO


/* -----------------------------------------------------------------
   3. Índice único filtrado: único entre los que tienen DNI
   ----------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID('Cliente') AND name = 'UX_Cliente_Dni')
    CREATE UNIQUE NONCLUSTERED INDEX UX_Cliente_Dni
        ON Cliente(Dni)
        WHERE Dni IS NOT NULL;
GO


/* -----------------------------------------------------------------
   4. Marca de mecánico
   El descuento NO se guarda por cliente: si es mecánico es 10%.
   Guardarlo abriría la puerta a que cada mecánico tenga el suyo,
   que no es como trabajás.
   ----------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('Cliente') AND name = 'EsMecanico')
    ALTER TABLE Cliente ADD EsMecanico BIT NOT NULL DEFAULT 0;
GO


/* -----------------------------------------------------------------
   5. Un mecánico sin teléfono no sirve
   Si el DNI deja de ser obligatorio, el teléfono es lo único con lo
   que lo encontrás en la lista y lo único para reclamarle.
   ----------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE parent_object_id = OBJECT_ID('Cliente') AND name = 'CK_Cliente_MecanicoTelefono')
    ALTER TABLE Cliente ADD CONSTRAINT CK_Cliente_MecanicoTelefono
        CHECK (EsMecanico = 0 OR (Telefono IS NOT NULL AND LTRIM(RTRIM(Telefono)) <> ''));
GO


/* -----------------------------------------------------------------
   6. VERIFICACIÓN
   ----------------------------------------------------------------- */
SELECT c.name AS Columna, t.name AS Tipo, c.max_length, c.is_nullable
FROM sys.columns c
JOIN sys.types t ON t.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID('Cliente')
ORDER BY c.column_id;

SELECT name AS Indice, is_unique, filter_definition
FROM sys.indexes
WHERE object_id = OBJECT_ID('Cliente');

-- Prueba: dos clientes sin DNI deben poder convivir.
-- Si esto falla, el índice filtrado no quedó bien.
/*
INSERT INTO Cliente (Dni, Nombre, Apellido, Telefono, Activo, EsMecanico)
VALUES (NULL, 'Prueba', 'Uno', '3510000001', 1, 1),
       (NULL, 'Prueba', 'Dos', '3510000002', 1, 1);

SELECT Id, Nombre, Apellido, Dni, EsMecanico FROM Cliente WHERE Nombre = 'Prueba';
DELETE FROM Cliente WHERE Nombre = 'Prueba';
*/
GO
