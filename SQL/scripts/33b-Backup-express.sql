USE [master]
GO

/* =================================================================
   33b — BACKUP AUTOMATICO PARA SQL SERVER EXPRESS

   Express no tiene compresion ni Agente. Se usa backup sin comprimir
   y el Programador de tareas de Windows para ejecutarlo cada noche.

   Y esta vez el mensaje de exito solo sale si el backup se hizo.
   ================================================================= */

EXEC master.dbo.xp_create_subdir 'C:\Backups\Daytona';
GO

IF OBJECT_ID('dbo.SP_Daytona_Backup', 'P') IS NOT NULL DROP PROCEDURE dbo.SP_Daytona_Backup;
GO

CREATE PROCEDURE dbo.SP_Daytona_Backup
    @Carpeta     NVARCHAR(260) = N'C:\Backups\Daytona\',
    @DiasRetener INT = 14
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @fecha NVARCHAR(20) = CONVERT(NVARCHAR(8), GETDATE(), 112) + '_' +
                                  REPLACE(CONVERT(NVARCHAR(8), GETDATE(), 108), ':', '');
    DECLARE @archivo NVARCHAR(400) = @Carpeta + N'DaytonaInyeccion_' + @fecha + N'.bak';

    BEGIN TRY
        -- Sin COMPRESSION: Express no lo soporta
        BACKUP DATABASE [DaytonaInyeccion]
        TO DISK = @archivo
        WITH CHECKSUM, INIT,
             NAME = N'Daytona backup diario';

        RESTORE VERIFYONLY FROM DISK = @archivo WITH CHECKSUM;

        DECLARE @limite DATETIME = DATEADD(DAY, -@DiasRetener, GETDATE());
        EXEC master.dbo.xp_delete_file 0, @Carpeta, N'bak', @limite, 0;

        PRINT N'Backup OK: ' + @archivo;
    END TRY
    BEGIN CATCH
        -- Que falle ruidosamente: un backup que falla en silencio es peor
        -- que no tener backup, porque uno cree que lo tiene.
        PRINT N'BACKUP FALLO: ' + ERROR_MESSAGE();
        THROW;
    END CATCH
END
GO

-- Probar
EXEC master.dbo.SP_Daytona_Backup;
GO

SELECT TOP 3
    backup_start_date AS Fecha,
    CAST(backup_size / 1024 / 1024 AS DECIMAL(10,1)) AS TamanoMB,
    physical_device_name AS Archivo
FROM msdb.dbo.backupset bs
INNER JOIN msdb.dbo.backupmediafamily bmf ON bmf.media_set_id = bs.media_set_id
WHERE database_name = 'DaytonaInyeccion'
ORDER BY backup_start_date DESC;
GO
