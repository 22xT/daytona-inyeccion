/* =================================================================
   00 — BASE DE DESARROLLO PARA LA MIGRACION

   Crea DaytonaInyeccion_Dev como copia de la base real, para probar
   la API nueva sin tocar produccion.

   QUE HACE CON LA BASE REAL: solo la lee.
   El backup es COPY_ONLY: no corta la cadena de los backups
   automaticos (script 33b) ni cambia nada de DaytonaInyeccion.

   Se puede correr las veces que haga falta: si la base de desarrollo
   ya existe, la pisa con una copia fresca. Nunca pisa DaytonaInyeccion.

   Correr con F5 en SSMS, conectado como administrador.
   ================================================================= */
USE [master];
GO

DECLARE @Origen  SYSNAME = N'DaytonaInyeccion';
DECLARE @Destino SYSNAME = N'DaytonaInyeccion_Dev';
DECLARE @Archivo NVARCHAR(400) = N'C:\Backups\Daytona\Copia_para_dev.bak';

/* Freno de seguridad: el destino no puede ser la base real */
IF @Destino = @Origen OR @Destino NOT LIKE N'%[_]Dev'
BEGIN
    RAISERROR('El destino tiene que terminar en _Dev y no puede ser la base real.', 16, 1);
    SET NOEXEC ON;
END

EXEC master.dbo.xp_create_subdir N'C:\Backups\Daytona';

/* 1. Copia de la base real (no la modifica) */
BACKUP DATABASE @Origen TO DISK = @Archivo WITH COPY_ONLY, INIT, CHECKSUM, STATS = 25;

/* 2. Nombres logicos y carpeta de datos, para no chocar con los archivos de la base real */
DECLARE @LogicoDatos SYSNAME = (SELECT name FROM sys.master_files WHERE database_id = DB_ID(@Origen) AND type = 0);
DECLARE @LogicoLog   SYSNAME = (SELECT name FROM sys.master_files WHERE database_id = DB_ID(@Origen) AND type = 1);
DECLARE @Carpeta     NVARCHAR(260) = CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS NVARCHAR(260));
DECLARE @FisicoDatos NVARCHAR(400) = @Carpeta + @Destino + N'.mdf';
DECLARE @FisicoLog   NVARCHAR(400) = @Carpeta + @Destino + N'_log.ldf';

/* 3. Si ya existe la de desarrollo, se cierra y se reemplaza */
IF DB_ID(@Destino) IS NOT NULL
BEGIN
    DECLARE @sql NVARCHAR(400) = N'ALTER DATABASE ' + QUOTENAME(@Destino) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;';
    EXEC (@sql);
END

RESTORE DATABASE @Destino FROM DISK = @Archivo
WITH MOVE @LogicoDatos TO @FisicoDatos,
     MOVE @LogicoLog   TO @FisicoLog,
     REPLACE, RECOVERY, STATS = 25;

DECLARE @sql2 NVARCHAR(400) = N'ALTER DATABASE ' + QUOTENAME(@Destino) + N' SET MULTI_USER; ALTER DATABASE ' + QUOTENAME(@Destino) + N' SET RECOVERY SIMPLE;';
EXEC (@sql2);
GO

/* 4. Control: tiene que decir DaytonaInyeccion_Dev y los mismos numeros que la real */
USE [DaytonaInyeccion_Dev];
GO
SELECT DB_NAME() AS Base,
       (SELECT COUNT(*) FROM Venta)    AS Ventas,
       (SELECT COUNT(*) FROM Repuesto) AS Repuestos;
GO

SET NOEXEC OFF;
GO
