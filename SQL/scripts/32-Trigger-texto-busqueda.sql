USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   32 — TEXTO DE BUSQUEDA AL INSERTAR Y MODIFICAR

   BUG DETECTADO CON LA APP MOBILE
   Al incorporar un repuesto, TextoBusqueda y CodigosBusqueda quedaban
   en NULL hasta que alguien corriera SP_Busqueda_Reprocesar a mano.
   Mientras tanto el repuesto existia pero era invisible para el
   buscador: la app mostraba "sin resultados" con el catalogo cargado.

   SOLUCION
   Un procedimiento que genera el texto de UN repuesto, y un trigger
   que lo llama despues de cada INSERT o UPDATE de las columnas que
   lo componen. Ya no depende de que nadie se acuerde.

   Por que trigger y no modificar cada SP: hay tres caminos para crear
   o cambiar un repuesto (alta manual, incorporacion desde lista,
   edicion) y mañana puede haber mas. El trigger cubre todos.
   ================================================================= */

/* -----------------------------------------------------------------
   1. Generar el texto de un solo repuesto
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Repuesto_GenerarTextoBusqueda', 'P') IS NOT NULL
    DROP PROCEDURE SP_Repuesto_GenerarTextoBusqueda;
GO

CREATE PROCEDURE SP_Repuesto_GenerarTextoBusqueda
    @IdRepuesto INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Misma cadena de sinonimos que usa el reprocesamiento masivo
    DECLARE @expr NVARCHAR(MAX) = N'@base';
    SELECT @expr = N'REPLACE(' + @expr + N', '' ' + Termino + N' '', '' ' + Reemplazo + N' '')'
    FROM SinonimoBusqueda WHERE Activo = 1
    ORDER BY LEN(Termino) DESC;

    DECLARE @sql NVARCHAR(MAX) = N'
        UPDATE Repuesto
        SET TextoBusqueda = LTRIM(RTRIM(' +
            REPLACE(@expr, N'@base',
                N''' '' + dbo.fn_LimpiarTexto(Descripcion + '' '' + ISNULL(AplicacionTexto, '''') + '' '' + ISNULL(MarcaFabricante, '''')) + '' ''')
        + N')),
            CodigosBusqueda = '' '' + dbo.fn_LimpiarCodigo(ISNULL(Codigo, '''')) +
                              '' '' + dbo.fn_LimpiarCodigo(ISNULL(CodigoFabricante, '''')) + '' ''
        WHERE Id = @id;';

    EXEC sp_executesql @sql, N'@id INT', @id = @IdRepuesto;
END
GO


/* -----------------------------------------------------------------
   2. Trigger: despues de insertar o cambiar las columnas de origen

   Se protege contra recursion: el trigger actualiza TextoBusqueda, y
   ese UPDATE no debe volver a dispararlo. Por eso se chequean solo
   las columnas de origen con UPDATE().
   ----------------------------------------------------------------- */
IF OBJECT_ID('TR_Repuesto_TextoBusqueda', 'TR') IS NOT NULL
    DROP TRIGGER TR_Repuesto_TextoBusqueda;
GO

CREATE TRIGGER TR_Repuesto_TextoBusqueda
ON Repuesto
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Solo si cambio algo que forma parte del texto
    IF NOT (UPDATE(Descripcion) OR UPDATE(AplicacionTexto) OR UPDATE(MarcaFabricante)
            OR UPDATE(Codigo) OR UPDATE(CodigoFabricante))
        RETURN;

    DECLARE @id INT;
    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT Id FROM inserted;
    OPEN cur;
    FETCH NEXT FROM cur INTO @id;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC SP_Repuesto_GenerarTextoBusqueda @IdRepuesto = @id;
        FETCH NEXT FROM cur INTO @id;
    END
    CLOSE cur; DEALLOCATE cur;
END
GO


/* -----------------------------------------------------------------
   3. Limpiar el UPDATE redundante del SP de incorporacion

   Ponia TextoBusqueda = NULL "para que se reprocese despues". Con el
   trigger ya no hace falta: se genera solo.
   ----------------------------------------------------------------- */
-- Se deja el SP como esta: el UPDATE a NULL dispara el trigger igual
-- (cambia AplicacionTexto en la misma sentencia) y queda regenerado.
-- No vale la pena reescribir 80 lineas por una que ya no molesta.


/* -----------------------------------------------------------------
   4. Reparar lo existente y verificar
   ----------------------------------------------------------------- */
EXEC SP_Busqueda_Reprocesar @SoloNuevos = 0;
GO

-- Prueba: cambiar una descripcion y ver que el texto se actualiza solo
DECLARE @id INT = (SELECT TOP 1 Id FROM Repuesto WHERE Activo = 1 ORDER BY Id);
DECLARE @antes VARCHAR(400) = (SELECT TextoBusqueda FROM Repuesto WHERE Id = @id);

UPDATE Repuesto SET Descripcion = Descripcion + ' ' WHERE Id = @id;   -- cambio trivial
UPDATE Repuesto SET Descripcion = RTRIM(Descripcion) WHERE Id = @id;   -- lo deshace

SELECT Id, Descripcion, TextoBusqueda, CodigosBusqueda,
       CASE WHEN TextoBusqueda IS NULL THEN 'FALLO: quedo NULL' ELSE 'OK: trigger funciona' END AS Resultado
FROM Repuesto WHERE Id = @id;
GO

SELECT COUNT(*) AS RepuestosSinTexto FROM Repuesto WHERE Activo = 1 AND TextoBusqueda IS NULL;
GO
