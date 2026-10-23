USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   25 — MOTOR DE IMPORTACION CONFIGURABLE

   EL PROBLEMA
   El importador actual esta escrito contra las nueve columnas
   exactas de Autocor. El segundo proveedor va a traer otra cantidad
   de columnas, otros nombres, otro orden, y probablemente otro
   esquema de descuentos: puede venir el costo directo sin descuentos
   que aplicar, o un descuento unico en vez de dos encadenados.

   LA SOLUCION
   Una tabla de paso generica de 20 columnas de texto, y un PERFIL
   por proveedor que dice que columna es cada cosa. El perfil se
   define una vez y se reutiliza todos los meses.

   IMPORTANTE: el proveedor 1 se migra a este motor ANTES de cargar
   el segundo. Si el motor no puede reproducir la importacion que ya
   funciona, entonces no abstrae de verdad.
   ================================================================= */


/* -----------------------------------------------------------------
   1. Perfil de importacion por proveedor
   ----------------------------------------------------------------- */
IF OBJECT_ID('PerfilImportacion', 'U') IS NULL
BEGIN
    CREATE TABLE PerfilImportacion (
        Id            INT IDENTITY(1,1) PRIMARY KEY,
        IdProveedor   INT           NOT NULL,
        Nombre        VARCHAR(80)   NOT NULL,

        -- Que numero de columna del archivo es cada campo.
        -- NULL = ese proveedor no lo manda.
        ColCodigo      TINYINT NOT NULL,   -- codigo interno del proveedor
        ColArticulo    TINYINT NULL,       -- codigo del fabricante
        ColRubro       TINYINT NULL,
        ColMarca       TINYINT NULL,
        ColDescripcion TINYINT NOT NULL,
        ColPrecio      TINYINT NOT NULL,   -- lista o costo, segun el esquema
        ColDescuento1  TINYINT NULL,
        ColDescuento2  TINYINT NULL,
        ColCosto       TINYINT NULL,       -- si el proveedor ya lo calcula
        ColStock       TINYINT NULL,       -- algunos informan disponibilidad

        /* Como se llega al costo:
             'DosDescuentos'  costo = precio x (1-d1) x (1-d2)
             'UnDescuento'    costo = precio x (1-d1)
             'CostoDirecto'   el precio YA es el costo
             'CostoEnColumna' el costo viene en ColCosto */
        EsquemaCosto  VARCHAR(20)   NOT NULL DEFAULT 'DosDescuentos',

        -- Si el proveedor no manda descuentos pero se le hace uno fijo
        DescuentoFijo DECIMAL(6,2)  NOT NULL DEFAULT 0,

        FilasEncabezado TINYINT     NOT NULL DEFAULT 0,
        Activo        BIT           NOT NULL DEFAULT 1,

        CONSTRAINT FK_Perfil_Proveedor FOREIGN KEY (IdProveedor) REFERENCES Proveedor(Id),
        CONSTRAINT UQ_Perfil_Proveedor UNIQUE (IdProveedor),
        CONSTRAINT CK_Perfil_Esquema CHECK (EsquemaCosto IN
            ('DosDescuentos','UnDescuento','CostoDirecto','CostoEnColumna'))
    );
END
GO


/* -----------------------------------------------------------------
   2. Tabla de paso generica

   Veinte columnas de texto. Todo entra como VARCHAR: si un dato
   viene mal, el BULK INSERT no falla y el problema se ve despues,
   en la validacion, con el detalle de que fila y por que.
   ----------------------------------------------------------------- */
IF OBJECT_ID('StgImportacion', 'U') IS NOT NULL DROP TABLE StgImportacion;
GO

CREATE TABLE StgImportacion (
    Fila  INT IDENTITY(1,1),
    Col1  VARCHAR(300), Col2  VARCHAR(300), Col3  VARCHAR(300), Col4  VARCHAR(300),
    Col5  VARCHAR(300), Col6  VARCHAR(300), Col7  VARCHAR(300), Col8  VARCHAR(300),
    Col9  VARCHAR(300), Col10 VARCHAR(300), Col11 VARCHAR(300), Col12 VARCHAR(300),
    Col13 VARCHAR(300), Col14 VARCHAR(300), Col15 VARCHAR(300), Col16 VARCHAR(300),
    Col17 VARCHAR(300), Col18 VARCHAR(300), Col19 VARCHAR(300), Col20 VARCHAR(300)
);
GO


/* -----------------------------------------------------------------
   3. Perfil del proveedor 1 (Autocor)

   Estructura real de su archivo:
     1 Codigo · 2 Articulo · 3 Rubro · 4 Marca · 5 Descripcion
     6 Precio(lista) · 7 Descuento(rubro) · 8 Desc.Extra(general)
     9 Precio Neto(costo, sirve de control)
   ----------------------------------------------------------------- */
DECLARE @idAutocor INT;
SELECT TOP 1 @idAutocor = Id FROM Proveedor WHERE RazonSocial LIKE '%AUTOCOR%';

IF @idAutocor IS NOT NULL AND NOT EXISTS (SELECT 1 FROM PerfilImportacion WHERE IdProveedor = @idAutocor)
    INSERT INTO PerfilImportacion
        (IdProveedor, Nombre, ColCodigo, ColArticulo, ColRubro, ColMarca,
         ColDescripcion, ColPrecio, ColDescuento1, ColDescuento2, ColCosto,
         EsquemaCosto, FilasEncabezado)
    VALUES
        (@idAutocor, 'Autocor — lista mensual', 1, 2, 3, 4, 5, 6, 7, 8, 9,
         'DosDescuentos', 0);
GO

SELECT p.Nombre, pr.RazonSocial, p.EsquemaCosto,
       p.ColCodigo, p.ColDescripcion, p.ColPrecio, p.ColDescuento1, p.ColDescuento2
FROM PerfilImportacion p
INNER JOIN Proveedor pr ON pr.Id = p.IdProveedor;
GO


/* -----------------------------------------------------------------
   4. Procesar la tabla de paso segun el perfil

   Arma dinamicamente el SELECT que mapea las columnas genericas a
   los campos reales, y calcula el costo segun el esquema.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Importacion_Procesar', 'P') IS NOT NULL DROP PROCEDURE SP_Importacion_Procesar;
GO

CREATE PROCEDURE SP_Importacion_Procesar
    @IdProveedor INT,
    @FechaLista  DATE = NULL,
    @SoloVistaPrevia BIT = 0     -- 1 = informa sin escribir nada
AS
BEGIN
    SET NOCOUNT ON;

    IF @FechaLista IS NULL SET @FechaLista = CAST(GETDATE() AS DATE);

    DECLARE @cCod TINYINT, @cArt TINYINT, @cRub TINYINT, @cMar TINYINT,
            @cDes TINYINT, @cPre TINYINT, @cD1 TINYINT, @cD2 TINYINT,
            @cCos TINYINT, @esquema VARCHAR(20), @dFijo DECIMAL(6,2), @enc TINYINT;

    SELECT @cCod = ColCodigo, @cArt = ColArticulo, @cRub = ColRubro, @cMar = ColMarca,
           @cDes = ColDescripcion, @cPre = ColPrecio, @cD1 = ColDescuento1,
           @cD2 = ColDescuento2, @cCos = ColCosto, @esquema = EsquemaCosto,
           @dFijo = DescuentoFijo, @enc = FilasEncabezado
    FROM PerfilImportacion
    WHERE IdProveedor = @IdProveedor AND Activo = 1;

    IF @cCod IS NULL
    BEGIN
        RAISERROR('Ese proveedor no tiene perfil de importacion configurado.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM StgImportacion)
    BEGIN
        RAISERROR('La tabla de paso esta vacia. Corre primero el BULK INSERT.', 16, 1);
        RETURN;
    END

    /* --- Expresiones de columna --- */
    DECLARE @eCod VARCHAR(20) = 'Col' + CAST(@cCod AS VARCHAR(2));
    DECLARE @eArt VARCHAR(20) = CASE WHEN @cArt IS NULL THEN 'NULL' ELSE 'Col' + CAST(@cArt AS VARCHAR(2)) END;
    DECLARE @eRub VARCHAR(20) = CASE WHEN @cRub IS NULL THEN 'NULL' ELSE 'Col' + CAST(@cRub AS VARCHAR(2)) END;
    DECLARE @eMar VARCHAR(20) = CASE WHEN @cMar IS NULL THEN 'NULL' ELSE 'Col' + CAST(@cMar AS VARCHAR(2)) END;
    DECLARE @eDes VARCHAR(20) = 'Col' + CAST(@cDes AS VARCHAR(2));
    DECLARE @ePre VARCHAR(20) = 'Col' + CAST(@cPre AS VARCHAR(2));
    DECLARE @eD1  VARCHAR(60) = CASE WHEN @cD1 IS NULL THEN CAST(@dFijo AS VARCHAR(20))
                                     ELSE 'TRY_CAST(Col' + CAST(@cD1 AS VARCHAR(2)) + ' AS DECIMAL(6,2))' END;
    DECLARE @eD2  VARCHAR(60) = CASE WHEN @cD2 IS NULL THEN '0'
                                     ELSE 'TRY_CAST(Col' + CAST(@cD2 AS VARCHAR(2)) + ' AS DECIMAL(6,2))' END;

    /* --- Como se calcula el costo --- */
    DECLARE @eCosto NVARCHAR(500);

    IF @esquema = 'CostoEnColumna' AND @cCos IS NOT NULL
        SET @eCosto = N'TRY_CAST(Col' + CAST(@cCos AS VARCHAR(2)) + N' AS DECIMAL(12,2))';
    ELSE IF @esquema = 'CostoDirecto'
        SET @eCosto = N'TRY_CAST(' + @ePre + N' AS DECIMAL(12,2))';
    ELSE IF @esquema = 'UnDescuento'
        SET @eCosto = N'CAST(TRY_CAST(' + @ePre + N' AS DECIMAL(12,2)) * (1 - ISNULL(' + @eD1 + N',0)/100.0) AS DECIMAL(12,2))';
    ELSE  -- DosDescuentos, encadenados y NO sumados
        SET @eCosto = N'CAST(TRY_CAST(' + @ePre + N' AS DECIMAL(12,2)) * (1 - ISNULL(' + @eD1 + N',0)/100.0) * (1 - ISNULL(' + @eD2 + N',0)/100.0) AS DECIMAL(12,2))';

    /* --- Vista previa: informa sin tocar nada --- */
    DECLARE @sql NVARCHAR(MAX);

    IF @SoloVistaPrevia = 1
    BEGIN
        SET @sql = N'
        SELECT
            COUNT(*) AS FilasEnArchivo,
            SUM(CASE WHEN ' + @eCod + N' IS NULL OR LTRIM(RTRIM(' + @eCod + N')) = '''' THEN 1 ELSE 0 END) AS SinCodigo,
            SUM(CASE WHEN TRY_CAST(' + @ePre + N' AS DECIMAL(12,2)) IS NULL THEN 1 ELSE 0 END) AS PrecioNoNumerico,
            SUM(CASE WHEN ISNULL(' + @eCosto + N', 0) <= 0 THEN 1 ELSE 0 END) AS SinCosto,
            (SELECT COUNT(*) FROM ProveedorRepuesto WHERE IdProveedor = @p AND Activo = 1) AS YaCargados
        FROM StgImportacion
        WHERE Fila > ' + CAST(@enc AS VARCHAR(3)) + N';

        SELECT TOP 10
            ' + @eCod + N' AS Codigo, ' + @eDes + N' AS Descripcion,
            TRY_CAST(' + @ePre + N' AS DECIMAL(12,2)) AS PrecioLista,
            ' + @eCosto + N' AS CostoCalculado
        FROM StgImportacion
        WHERE Fila > ' + CAST(@enc AS VARCHAR(3)) + N';';

        EXEC sp_executesql @sql, N'@p INT', @p = @IdProveedor;
        RETURN;
    END

    /* --- Actualizar lo que ya existe --- */
    SET @sql = N'
    UPDATE pr
    SET pr.PrecioLista      = TRY_CAST(s.' + @ePre + N' AS DECIMAL(12,2)),
        pr.DescuentoRubro   = ISNULL(' + REPLACE(@eD1, 'Col', 's.Col') + N', 0),
        pr.DescuentoGeneral = ISNULL(' + REPLACE(@eD2, 'Col', 's.Col') + N', 0),
        pr.PrecioCompra     = ' + REPLACE(@eCosto, 'Col', 's.Col') + N',
        pr.Descripcion      = LEFT(s.' + @eDes + N', 250),
        pr.FechaLista       = @f,
        pr.Activo           = 1,
        pr.TextoBusqueda    = NULL
    FROM ProveedorRepuesto pr
    INNER JOIN StgImportacion s ON s.' + @eCod + N' = pr.CodigoProveedor
    WHERE pr.IdProveedor = @p AND s.Fila > ' + CAST(@enc AS VARCHAR(3)) + N';';

    EXEC sp_executesql @sql, N'@p INT, @f DATE', @p = @IdProveedor, @f = @FechaLista;
    DECLARE @actualizados INT = @@ROWCOUNT;

    /* --- Dar de baja lo que ya no viene ---
       No se borra: puede haber ventas historicas apuntando ahi. */
    SET @sql = N'
    UPDATE ProveedorRepuesto
    SET Activo = 0
    WHERE IdProveedor = @p
      AND CodigoProveedor NOT IN
          (SELECT ' + @eCod + N' FROM StgImportacion
           WHERE Fila > ' + CAST(@enc AS VARCHAR(3)) + N'
             AND ' + @eCod + N' IS NOT NULL);';

    EXEC sp_executesql @sql, N'@p INT', @p = @IdProveedor;
    DECLARE @desactivados INT = @@ROWCOUNT;

    /* --- Altas --- */
    SET @sql = N'
    INSERT INTO ProveedorRepuesto
        (IdProveedor, CodigoProveedor, Articulo, RubroTexto, MarcaTexto, Descripcion,
         PrecioLista, DescuentoRubro, DescuentoGeneral, PrecioCompra, IdRubro, FechaLista)
    SELECT
        @p,
        s.' + @eCod + N',
        LEFT(s.' + @eArt + N', 40),
        LEFT(s.' + @eRub + N', 120),
        LEFT(s.' + @eMar + N', 60),
        LEFT(s.' + @eDes + N', 250),
        TRY_CAST(s.' + @ePre + N' AS DECIMAL(12,2)),
        ISNULL(' + REPLACE(@eD1, 'Col', 's.Col') + N', 0),
        ISNULL(' + REPLACE(@eD2, 'Col', 's.Col') + N', 0),
        ' + REPLACE(@eCosto, 'Col', 's.Col') + N',
        r.Id,
        @f
    FROM StgImportacion s
    LEFT JOIN Rubro r
        ON UPPER(LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(r.Nombre, ''   '', '' ''), ''  '', '' ''), ''  '', '' ''))))
         = UPPER(LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(s.' + @eRub + N', ''   '', '' ''), ''  '', '' ''), ''  '', '' ''))))
    WHERE s.Fila > ' + CAST(@enc AS VARCHAR(3)) + N'
      AND s.' + @eCod + N' IS NOT NULL
      AND LTRIM(RTRIM(s.' + @eCod + N')) <> ''''
      AND TRY_CAST(s.' + @ePre + N' AS DECIMAL(12,2)) IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM ProveedorRepuesto pr
                      WHERE pr.IdProveedor = @p AND pr.CodigoProveedor = s.' + @eCod + N');';

    EXEC sp_executesql @sql, N'@p INT, @f DATE', @p = @IdProveedor, @f = @FechaLista;
    DECLARE @nuevos INT = @@ROWCOUNT;

    -- El descuento general del proveedor se toma de la propia lista
    IF @cD2 IS NOT NULL
    BEGIN
        SET @sql = N'
        UPDATE Proveedor
        SET DescuentoGeneral = (SELECT TOP 1 ISNULL(' + REPLACE(@eD2, 'Col', 's.Col') + N', 0)
                                FROM StgImportacion s
                                WHERE s.Fila > ' + CAST(@enc AS VARCHAR(3)) + N')
        WHERE Id = @p;';
        EXEC sp_executesql @sql, N'@p INT', @p = @IdProveedor;
    END

    SELECT @actualizados AS Actualizados, @nuevos AS Nuevos, @desactivados AS Desactivados;

    PRINT 'Importacion terminada. Falta reprocesar el texto de busqueda:';
    PRINT '  EXEC SP_Busqueda_Reprocesar @SoloNuevos = 1;';
END
GO


/* -----------------------------------------------------------------
   5. Control de variaciones anormales de precio

   Un salto muy grande respecto del mes anterior suele ser un error
   de carga o un cambio de esquema de descuentos del proveedor. No se
   bloquea la importacion: se informa para que alguien lo mire.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Importacion_Alertas', 'P') IS NOT NULL DROP PROCEDURE SP_Importacion_Alertas;
GO

CREATE PROCEDURE SP_Importacion_Alertas
    @IdProveedor    INT,
    @VariacionMax   DECIMAL(6,2) = 60      -- % de cambio que enciende la alerta
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        pr.CodigoProveedor,
        pr.Descripcion,
        pr.PrecioCompra   AS CostoNuevo,
        r.PrecioCompra    AS CostoAnterior,
        CAST((pr.PrecioCompra - r.PrecioCompra) / NULLIF(r.PrecioCompra, 0) * 100
             AS DECIMAL(8,2)) AS VariacionPorc,
        CASE WHEN pr.PrecioCompra > r.PrecioCompra THEN 'Aumento' ELSE 'Baja' END AS Sentido
    FROM ProveedorRepuesto pr
    INNER JOIN Repuesto r ON r.Id = pr.IdRepuesto
    WHERE pr.IdProveedor = @IdProveedor
      AND pr.Activo = 1
      AND r.PrecioCompra > 0
      AND ABS((pr.PrecioCompra - r.PrecioCompra) / r.PrecioCompra * 100) >= @VariacionMax
    ORDER BY ABS((pr.PrecioCompra - r.PrecioCompra) / r.PrecioCompra) DESC;
END
GO


/* -----------------------------------------------------------------
   6. VERIFICACION
   ----------------------------------------------------------------- */
SELECT name AS Tabla FROM sys.tables
WHERE name IN ('PerfilImportacion', 'StgImportacion');

SELECT name AS Procedimiento FROM sys.procedures
WHERE name LIKE 'SP_Importacion%';

SELECT * FROM PerfilImportacion;
GO

/* -----------------------------------------------------------------
   7. MIGRACION DEL PROVEEDOR 1 AL MOTOR GENERICO

   Antes de cargar el segundo proveedor hay que comprobar que el
   motor puede reproducir la importacion que ya funciona. Si no
   puede, no abstrae de verdad.

   PASO A: guardar el estado actual como punto de comparacion
   ----------------------------------------------------------------- */
SELECT
    COUNT(*)                    AS FilasActuales,
    SUM(PrecioCompra)           AS SumaCostos,
    (SELECT PrecioCompra FROM ProveedorRepuesto WHERE CodigoProveedor = '359V001')
                                AS CostoAbrazadera
FROM ProveedorRepuesto;
GO
-- Anotar estos tres numeros. Despues de la migracion tienen que dar igual.


/* -----------------------------------------------------------------
   PASO B: cargar el archivo generico

   Generar con:  python preparar_lista.py "AUTOCOR....xlsx"
   Copiar a C:\Temp\ y correr:
   ----------------------------------------------------------------- */
/*
TRUNCATE TABLE StgImportacion;

BULK INSERT StgImportacion
FROM 'C:\Temp\lista_proveedor.txt'
WITH (
    DATAFILETYPE    = 'widechar',
    FIELDTERMINATOR = '|',
    ROWTERMINATOR   = '0x0a00',
    TABLOCK
);

SELECT COUNT(*) AS FilasImportadas FROM StgImportacion;   -- 53188
*/


/* -----------------------------------------------------------------
   PASO C: vista previa, antes de escribir nada
   ----------------------------------------------------------------- */
/*
DECLARE @p INT;
SELECT TOP 1 @p = Id FROM Proveedor WHERE RazonSocial LIKE '%AUTOCOR%';
EXEC SP_Importacion_Procesar @IdProveedor = @p, @SoloVistaPrevia = 1;
*/
-- Mirar: SinCodigo y PrecioNoNumerico en 0, y que el CostoCalculado
-- de las 10 filas de muestra coincida con el Precio Neto del Excel.


/* -----------------------------------------------------------------
   PASO D: procesar de verdad
   ----------------------------------------------------------------- */
/*
DECLARE @p INT;
SELECT TOP 1 @p = Id FROM Proveedor WHERE RazonSocial LIKE '%AUTOCOR%';
EXEC SP_Importacion_Procesar @IdProveedor = @p, @FechaLista = '2026-09-01';

EXEC SP_Busqueda_Reprocesar @SoloNuevos = 1;
*/


/* -----------------------------------------------------------------
   PASO E: comparar contra el punto de partida

   Los tres numeros tienen que dar lo mismo que en el PASO A.
   Si dan igual, el motor generico reproduce el importador especifico
   y se puede cargar el segundo proveedor con confianza.
   ----------------------------------------------------------------- */
/*
SELECT
    COUNT(*)          AS FilasDespues,
    SUM(PrecioCompra) AS SumaCostosDespues,
    (SELECT PrecioCompra FROM ProveedorRepuesto WHERE CodigoProveedor = '359V001')
                      AS CostoAbrazaderaDespues
FROM ProveedorRepuesto;

-- Y que ningun enlace se haya perdido
SELECT COUNT(*) AS EnlacesConservados
FROM ProveedorRepuesto WHERE IdRepuesto IS NOT NULL;
*/
