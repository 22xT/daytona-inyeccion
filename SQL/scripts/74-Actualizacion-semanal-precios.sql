USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   74 — ACTUALIZACION SEMANAL DE PRECIOS (viernes)

   Hasta ahora importar una lista pisaba los precios y no quedaba
   registro de cuanto valian antes. Para ver "como cambiaron los
   precios" hace falta:

   1. Historial: cada vez que cambia el precio de un articulo de un
      proveedor, se guarda el anterior y el nuevo (trigger). Vale para
      cualquier forma de importar.
   2. Comparar ANTES de importar: se carga el archivo en la tabla de
      paso y SP_Importacion_Comparar informa que sube, que baja, que
      es raro y que repuestos tuyos cambian de costo, sin escribir nada.
   3. Recien despues, si esta todo bien, se importa como siempre.

   Los precios de venta NO se tocan solos: el informe muestra cuanto
   quedaria cada uno y lo decide una persona.
   ================================================================= */


/* -----------------------------------------------------------------
   1. Historial de precios de proveedor
   ----------------------------------------------------------------- */
IF OBJECT_ID('HistorialPrecioProveedor', 'U') IS NULL
    CREATE TABLE HistorialPrecioProveedor (
        Id                   INT IDENTITY(1,1) PRIMARY KEY,
        IdProveedorRepuesto  INT NOT NULL REFERENCES ProveedorRepuesto(Id),
        Fecha                DATETIME NOT NULL DEFAULT GETDATE(),
        PrecioListaAnterior  DECIMAL(12,2) NULL,
        PrecioListaNuevo     DECIMAL(12,2) NULL,
        CostoAnterior        DECIMAL(12,2) NULL,
        CostoNuevo           DECIMAL(12,2) NULL
    );
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_HistorialPrecio_Articulo')
    CREATE INDEX IX_HistorialPrecio_Articulo ON HistorialPrecioProveedor(IdProveedorRepuesto, Fecha);
GO

IF OBJECT_ID('TR_ProveedorRepuesto_HistorialPrecio', 'TR') IS NOT NULL
    DROP TRIGGER TR_ProveedorRepuesto_HistorialPrecio;
GO
CREATE TRIGGER TR_ProveedorRepuesto_HistorialPrecio ON ProveedorRepuesto
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT (UPDATE(PrecioLista) OR UPDATE(PrecioCompra)) RETURN;

    INSERT INTO HistorialPrecioProveedor
        (IdProveedorRepuesto, PrecioListaAnterior, PrecioListaNuevo, CostoAnterior, CostoNuevo)
    SELECT i.Id, d.PrecioLista, i.PrecioLista, d.PrecioCompra, i.PrecioCompra
    FROM inserted i
    INNER JOIN deleted d ON d.Id = i.Id
    WHERE ISNULL(d.PrecioLista, -1) <> ISNULL(i.PrecioLista, -1)
       OR ISNULL(d.PrecioCompra, -1) <> ISNULL(i.PrecioCompra, -1);
END
GO


/* -----------------------------------------------------------------
   2. Comparar la lista nueva contra la cargada (no escribe nada en
      ProveedorRepuesto)
   ----------------------------------------------------------------- */
IF OBJECT_ID('StgComparacion', 'U') IS NOT NULL DROP TABLE StgComparacion;
GO
CREATE TABLE StgComparacion (
    Codigo       VARCHAR(60)   NOT NULL,
    Articulo     VARCHAR(60)   NULL,
    Rubro        VARCHAR(150)  NULL,
    Descripcion  VARCHAR(300)  NULL,
    PrecioLista  DECIMAL(12,2) NULL,
    Costo        DECIMAL(12,2) NULL
);
GO
CREATE INDEX IX_StgComparacion_Codigo ON StgComparacion(Codigo);
GO

IF OBJECT_ID('SP_Importacion_Comparar', 'P') IS NOT NULL DROP PROCEDURE SP_Importacion_Comparar;
GO
CREATE PROCEDURE SP_Importacion_Comparar
    @IdProveedor INT,
    @UmbralRaro  DECIMAL(6,2) = 30     -- % de cambio que se considera raro
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @cCod TINYINT, @cArt TINYINT, @cRub TINYINT, @cDes TINYINT, @cPre TINYINT,
            @cD1 TINYINT, @cD2 TINYINT, @cCos TINYINT, @esquema VARCHAR(20), @dFijo DECIMAL(6,2), @enc TINYINT;

    SELECT @cCod = ColCodigo, @cArt = ColArticulo, @cRub = ColRubro, @cDes = ColDescripcion,
           @cPre = ColPrecio, @cD1 = ColDescuento1, @cD2 = ColDescuento2, @cCos = ColCosto,
           @esquema = EsquemaCosto, @dFijo = DescuentoFijo, @enc = FilasEncabezado
    FROM PerfilImportacion WHERE IdProveedor = @IdProveedor AND Activo = 1;

    IF @cCod IS NULL
        THROW 50150, 'Ese proveedor no tiene perfil de importacion configurado.', 1;
    IF NOT EXISTS (SELECT 1 FROM StgImportacion)
        THROW 50151, 'La tabla de paso esta vacia: primero el BULK INSERT del archivo.', 1;

    /* Las mismas cuentas que SP_Importacion_Procesar */
    DECLARE @eArt VARCHAR(20) = CASE WHEN @cArt IS NULL THEN 'NULL' ELSE 'Col' + CAST(@cArt AS VARCHAR(2)) END;
    DECLARE @eRub VARCHAR(20) = CASE WHEN @cRub IS NULL THEN 'NULL' ELSE 'Col' + CAST(@cRub AS VARCHAR(2)) END;
    DECLARE @ePre VARCHAR(20) = 'Col' + CAST(@cPre AS VARCHAR(2));
    DECLARE @eD1  VARCHAR(60) = CASE WHEN @cD1 IS NULL THEN CAST(@dFijo AS VARCHAR(20))
                                     ELSE 'TRY_CAST(Col' + CAST(@cD1 AS VARCHAR(2)) + ' AS DECIMAL(6,2))' END;
    DECLARE @eD2  VARCHAR(60) = CASE WHEN @cD2 IS NULL THEN '0'
                                     ELSE 'TRY_CAST(Col' + CAST(@cD2 AS VARCHAR(2)) + ' AS DECIMAL(6,2))' END;
    DECLARE @eCosto NVARCHAR(500);
    IF @esquema = 'CostoEnColumna' AND @cCos IS NOT NULL
        SET @eCosto = N'TRY_CAST(Col' + CAST(@cCos AS VARCHAR(2)) + N' AS DECIMAL(12,2))';
    ELSE IF @esquema = 'CostoDirecto'
        SET @eCosto = N'TRY_CAST(' + @ePre + N' AS DECIMAL(12,2))';
    ELSE IF @esquema = 'UnDescuento'
        SET @eCosto = N'CAST(TRY_CAST(' + @ePre + N' AS DECIMAL(12,2)) * (1 - ISNULL(' + @eD1 + N',0)/100.0) AS DECIMAL(12,2))';
    ELSE
        SET @eCosto = N'CAST(TRY_CAST(' + @ePre + N' AS DECIMAL(12,2)) * (1 - ISNULL(' + @eD1 + N',0)/100.0) * (1 - ISNULL(' + @eD2 + N',0)/100.0) AS DECIMAL(12,2))';

    TRUNCATE TABLE StgComparacion;
    DECLARE @sql NVARCHAR(MAX) = N'
    INSERT INTO StgComparacion (Codigo, Articulo, Rubro, Descripcion, PrecioLista, Costo)
    SELECT LTRIM(RTRIM(Col' + CAST(@cCod AS VARCHAR(2)) + N')), LEFT(' + @eArt + N', 60), LEFT(' + @eRub + N', 150),
           LEFT(Col' + CAST(@cDes AS VARCHAR(2)) + N', 300),
           TRY_CAST(' + @ePre + N' AS DECIMAL(12,2)), ' + @eCosto + N'
    FROM StgImportacion
    WHERE Fila > ' + CAST(ISNULL(@enc, 0) AS VARCHAR(3)) + N'
      AND Col' + CAST(@cCod AS VARCHAR(2)) + N' IS NOT NULL
      AND LTRIM(RTRIM(Col' + CAST(@cCod AS VARCHAR(2)) + N')) <> '''';';
    EXEC sp_executesql @sql;

    DECLARE @MargenGeneral DECIMAL(6,2) =
        ISNULL(TRY_CAST((SELECT Valor FROM ParametroSistema WHERE Clave = 'MargenGeneral') AS DECIMAL(6,2)), 50);
    DECLARE @RI BIT = CASE WHEN (SELECT CondicionIva FROM Proveedor WHERE Id = @IdProveedor) = 'Responsable Inscripto' THEN 1 ELSE 0 END;

    /* Cruce: lo nuevo contra lo cargado */
    SELECT n.Codigo, n.Rubro, n.Descripcion, pr.Id AS IdPR, pr.IdRepuesto,
           pr.PrecioCompra AS CostoAntes, n.Costo AS CostoAhora,
           CASE WHEN pr.Id IS NULL THEN 'NUEVO'
                WHEN ISNULL(n.Costo, 0) <= 0 AND pr.PrecioCompra > 0 THEN 'SIN_PRECIO'
                WHEN ISNULL(pr.PrecioCompra, 0) <= 0 AND n.Costo > 0 THEN 'VUELVE'
                WHEN n.Costo > pr.PrecioCompra THEN 'SUBE'
                WHEN n.Costo < pr.PrecioCompra THEN 'BAJA'
                ELSE 'IGUAL' END AS Cambio,
           CASE WHEN pr.PrecioCompra > 0 AND n.Costo > 0
                THEN CAST((n.Costo - pr.PrecioCompra) / pr.PrecioCompra * 100 AS DECIMAL(8,2)) END AS VariacionPorc
    INTO #Cruce
    FROM StgComparacion n
    LEFT JOIN ProveedorRepuesto pr ON pr.IdProveedor = @IdProveedor AND pr.CodigoProveedor = n.Codigo;

    -- 1) Resumen
    SELECT
        (SELECT COUNT(*) FROM StgComparacion)                                   AS ArticulosEnArchivo,
        SUM(CASE WHEN Cambio = 'SUBE' THEN 1 ELSE 0 END)                        AS Suben,
        SUM(CASE WHEN Cambio = 'BAJA' THEN 1 ELSE 0 END)                        AS Bajan,
        SUM(CASE WHEN Cambio = 'IGUAL' THEN 1 ELSE 0 END)                       AS Iguales,
        SUM(CASE WHEN Cambio = 'NUEVO' THEN 1 ELSE 0 END)                       AS Nuevos,
        SUM(CASE WHEN Cambio = 'SIN_PRECIO' THEN 1 ELSE 0 END)                  AS QuedanSinPrecio,
        SUM(CASE WHEN Cambio = 'VUELVE' THEN 1 ELSE 0 END)                      AS VuelvenATenerPrecio,
        (SELECT COUNT(*) FROM ProveedorRepuesto pr
         WHERE pr.IdProveedor = @IdProveedor AND pr.Activo = 1
           AND NOT EXISTS (SELECT 1 FROM StgComparacion n WHERE n.Codigo = pr.CodigoProveedor)) AS DesaparecenDeLaLista,
        CAST(AVG(CASE WHEN Cambio IN ('SUBE','BAJA','IGUAL') THEN VariacionPorc END) AS DECIMAL(8,2)) AS VariacionPromedioPorc,
        CAST(AVG(CASE WHEN Cambio = 'SUBE' THEN VariacionPorc END) AS DECIMAL(8,2))                 AS AumentoPromedioDeLosQueSuben
    FROM #Cruce;

    -- 2) Por rubro (los que mas cambiaron primero)
    SELECT Rubro,
           COUNT(*) AS Articulos,
           SUM(CASE WHEN Cambio = 'SUBE' THEN 1 ELSE 0 END) AS Suben,
           SUM(CASE WHEN Cambio = 'BAJA' THEN 1 ELSE 0 END) AS Bajan,
           CAST(AVG(VariacionPorc) AS DECIMAL(8,2)) AS VariacionPromedioPorc,
           MIN(VariacionPorc) AS MinPorc, MAX(VariacionPorc) AS MaxPorc
    FROM #Cruce
    WHERE Cambio IN ('SUBE', 'BAJA', 'IGUAL')
    GROUP BY Rubro
    ORDER BY ABS(AVG(VariacionPorc)) DESC, COUNT(*) DESC;

    -- 3) Raros: cambios grandes o que se quedan sin precio. Revisar antes de importar.
    SELECT TOP 300 Codigo, Rubro, Descripcion, CostoAntes, CostoAhora, VariacionPorc, Cambio,
           CASE WHEN IdRepuesto IS NOT NULL THEN 'Si' ELSE '' END AS EsDeTuCatalogo
    FROM #Cruce
    WHERE (Cambio IN ('SUBE','BAJA') AND ABS(VariacionPorc) >= @UmbralRaro)
       OR (Cambio = 'SIN_PRECIO' AND IdRepuesto IS NOT NULL)
    ORDER BY CASE WHEN IdRepuesto IS NOT NULL THEN 0 ELSE 1 END, ABS(ISNULL(VariacionPorc, 100)) DESC;

    -- 4) Tus repuestos: cuanto cambia el costo y cuanto quedaria el precio de venta
    SELECT r.Codigo AS TuCodigo, r.Descripcion, r.MarcaFabricante AS Marca,
           ISNULL(s.Cantidad, 0) AS Stock,
           c.CostoAntes, c.CostoAhora, c.VariacionPorc, c.Cambio,
           r.PrecioDeVenta AS PrecioVentaActual,
           CAST(c.CostoAhora * (1 + ISNULL(r.MargenPropio, ISNULL(ru.MargenPorcentaje, @MargenGeneral)) / 100.0)
                * CASE WHEN @RI = 1 THEN 1.21 ELSE 1 END AS DECIMAL(12,2)) AS PrecioVentaSugerido,
           -- ¿Este proveedor sigue siendo el mas barato para ese repuesto?
           CASE WHEN c.CostoAhora > 0 AND c.CostoAhora <= ISNULL((SELECT MIN(x.PrecioCompra) FROM ProveedorRepuesto x
                                                    WHERE x.IdRepuesto = r.Id AND x.IdProveedor <> @IdProveedor
                                                      AND x.Activo = 1 AND x.PrecioCompra > 0), 999999999)
                THEN 'Si' ELSE 'No' END AS SigueSiendoElMasBarato
    FROM #Cruce c
    INNER JOIN Repuesto r ON r.Id = c.IdRepuesto
    LEFT JOIN Rubro ru    ON ru.Id = r.IdRubro
    LEFT JOIN Stock s     ON s.IdRepuesto = r.Id
    WHERE r.Activo = 1
    ORDER BY CASE c.Cambio WHEN 'SIN_PRECIO' THEN 0 WHEN 'SUBE' THEN 1 WHEN 'BAJA' THEN 2 ELSE 3 END,
             ABS(ISNULL(c.VariacionPorc, 0)) DESC;
END
GO


/* =================================================================
   EL VIERNES, PASO A PASO (Autocor del 14/10)

   El archivo ya convertido esta en
   C:\DaytonaProject\Tesis Daytona\Importaciones\autocor_2026-10-14.txt
   Seleccionar cada bloque y F5.
   ================================================================= */

/* PASO 1 — cargar el archivo en la tabla de paso
   (si da "Acceso denegado", SQL Server no puede leer esa carpeta:
    copiá el .txt a C:\Temp\ y cambiá la ruta, como en las importaciones anteriores)
TRUNCATE TABLE StgImportacion;

BULK INSERT StgImportacion
FROM 'C:\DaytonaProject\Tesis Daytona\Importaciones\autocor_2026-10-14.txt'
WITH (DATAFILETYPE = 'widechar', FIELDTERMINATOR = '|', ROWTERMINATOR = '0x0a00', TABLOCK);

SELECT COUNT(*) AS FilasCargadas FROM StgImportacion;   -- 53316
*/

/* PASO 2 — comparar (no cambia nada). Mirar los 4 resultados.
DECLARE @p INT = (SELECT TOP 1 Id FROM Proveedor WHERE RazonSocial LIKE '%AUTOCOR%');
EXEC SP_Importacion_Comparar @IdProveedor = @p;
*/

/* PASO 3 — si esta bien, importar. Queda el historial de cada cambio.
DECLARE @p INT = (SELECT TOP 1 Id FROM Proveedor WHERE RazonSocial LIKE '%AUTOCOR%');
EXEC SP_Importacion_Procesar @IdProveedor = @p, @FechaLista = '2026-10-14';
EXEC SP_Busqueda_Reprocesar @SoloNuevos = 1;

SELECT COUNT(*) AS CambiosRegistrados FROM HistorialPrecioProveedor
WHERE Fecha >= CAST(GETDATE() AS DATE);
*/
