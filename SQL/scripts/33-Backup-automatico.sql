USE [master]
GO

/* =================================================================
   33 — BACKUP AUTOMATICO

   Sin esto el sistema no se puede usar en un negocio: un disco que
   falla o un UPDATE sin WHERE borra meses de ventas y cuentas
   corrientes.

   ESTRATEGIA (realista para una PyME, sin herramientas pagas)
     - Backup completo todas las noches a las 23:30
     - Se conservan los ultimos 14 dias; los mas viejos se borran solos
     - Van a C:\Backups\Daytona\ (cambiar por un segundo disco si hay)
     - Una copia manual semanal a un pendrive o a la nube es tarea de
       la persona, no del sistema: el script la recuerda al final

   Requiere SQL Server Agent corriendo (no viene en Express: ver nota
   al final si es el caso).
   ================================================================= */


/* -----------------------------------------------------------------
   1. Carpeta de destino
   ----------------------------------------------------------------- */
EXEC master.dbo.xp_create_subdir 'C:\Backups\Daytona';
GO


/* -----------------------------------------------------------------
   2. Procedimiento que hace el backup y limpia los viejos
   ----------------------------------------------------------------- */
IF OBJECT_ID('dbo.SP_Daytona_Backup', 'P') IS NOT NULL DROP PROCEDURE dbo.SP_Daytona_Backup;
GO

CREATE PROCEDURE dbo.SP_Daytona_Backup
    @Carpeta   NVARCHAR(260) = N'C:\Backups\Daytona\',
    @DiasRetener INT = 14
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @fecha NVARCHAR(20) = CONVERT(NVARCHAR(8), GETDATE(), 112) + '_' +
                                  REPLACE(CONVERT(NVARCHAR(8), GETDATE(), 108), ':', '');
    DECLARE @archivo NVARCHAR(400) = @Carpeta + N'DaytonaInyeccion_' + @fecha + N'.bak';

    -- Backup completo, comprimido, con verificacion
    BACKUP DATABASE [DaytonaInyeccion]
    TO DISK = @archivo
    WITH COMPRESSION, CHECKSUM, INIT,
         NAME = N'Daytona backup diario',
         DESCRIPTION = N'Backup automatico completo';

    RESTORE VERIFYONLY FROM DISK = @archivo WITH CHECKSUM;

    -- Borrar los que superen la retencion
    DECLARE @limite DATETIME = DATEADD(DAY, -@DiasRetener, GETDATE());
    EXEC master.dbo.xp_delete_file 0, @Carpeta, N'bak', @limite, 0;

    PRINT N'Backup OK: ' + @archivo;
END
GO


/* -----------------------------------------------------------------
   3. Job del Agente: todas las noches a las 23:30
   ----------------------------------------------------------------- */
USE [msdb]
GO

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'Daytona - Backup diario')
    EXEC msdb.dbo.sp_delete_job @job_name = N'Daytona - Backup diario';
GO

EXEC msdb.dbo.sp_add_job
    @job_name = N'Daytona - Backup diario',
    @description = N'Backup completo nocturno de DaytonaInyeccion con retencion de 14 dias.',
    @enabled = 1;

EXEC msdb.dbo.sp_add_jobstep
    @job_name = N'Daytona - Backup diario',
    @step_name = N'Ejecutar backup',
    @subsystem = N'TSQL',
    @database_name = N'master',
    @command = N'EXEC dbo.SP_Daytona_Backup;';

EXEC msdb.dbo.sp_add_schedule
    @schedule_name = N'Todas las noches 23:30',
    @freq_type = 4,            -- diario
    @freq_interval = 1,
    @active_start_time = 233000;

EXEC msdb.dbo.sp_attach_schedule
    @job_name = N'Daytona - Backup diario',
    @schedule_name = N'Todas las noches 23:30';

EXEC msdb.dbo.sp_add_jobserver
    @job_name = N'Daytona - Backup diario';
GO


/* -----------------------------------------------------------------
   4. Probar ahora mismo
   ----------------------------------------------------------------- */
EXEC master.dbo.SP_Daytona_Backup;
GO

-- Ver el historial de backups de la base
SELECT TOP 5
    backup_start_date AS Fecha,
    CAST(backup_size / 1024 / 1024 AS DECIMAL(10,1)) AS TamanoMB,
    CAST(compressed_backup_size / 1024 / 1024 AS DECIMAL(10,1)) AS ComprimidoMB,
    physical_device_name AS Archivo
FROM msdb.dbo.backupset bs
INNER JOIN msdb.dbo.backupmediafamily bmf ON bmf.media_set_id = bs.media_set_id
WHERE database_name = 'DaytonaInyeccion'
ORDER BY backup_start_date DESC;
GO


/* =================================================================
   PROCEDIMIENTO DE RESTAURACION (para probar una vez al mes)

   Un backup que nunca se restauro no se sabe si sirve. Una vez al mes,
   restaurar el ultimo en una base aparte y abrir una pantalla:

   RESTORE DATABASE [DaytonaInyeccion_Prueba]
   FROM DISK = N'C:\Backups\Daytona\<archivo mas reciente>.bak'
   WITH MOVE 'DaytonaInyeccion' TO 'C:\Backups\Daytona\prueba.mdf',
        MOVE 'DaytonaInyeccion_log' TO 'C:\Backups\Daytona\prueba.ldf',
        REPLACE;

   Si los nombres logicos difieren, verlos con:
   RESTORE FILELISTONLY FROM DISK = N'C:\Backups\Daytona\<archivo>.bak';

   Despues: DROP DATABASE [DaytonaInyeccion_Prueba];


   SI EL AGENTE NO ESTA DISPONIBLE (SQL Server Express)
   Express no trae Agente. Alternativa: Programador de tareas de
   Windows ejecutando cada noche:

   sqlcmd -S CAT1913\NATIONALSOFT -E -Q "EXEC master.dbo.SP_Daytona_Backup"

   COPIA FUERA DE LA MAQUINA
   El backup en el mismo disco protege contra errores, no contra un
   disco roto ni un robo. Una vez por semana, copiar la carpeta
   C:\Backups\Daytona a un pendrive o a OneDrive. Es tarea de la
   persona: anotarla en el calendario.
   ================================================================= */
