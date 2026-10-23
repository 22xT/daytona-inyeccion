USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   23 — NORMALIZADOR Y TEXTO DE BUSQUEDA
   Tramo 1A del centralizador multiproveedor.

   EL PROBLEMA
   Cada proveedor escribe lo mismo distinto:
       Autocor:  BOMBA AGUA VW SURAN FOX GOL TREND
       Expoyer:  BBA.AGUA SURAN 1.6 EA111
   El vendedor escribe "bomba agua suran".
   Ninguna busqueda por texto va a hacer que BBA matchee BOMBA: son
   cadenas distintas.

   LA SOLUCION
   Una columna derivada TextoBusqueda con el texto normalizado y las
   abreviaturas expandidas. La descripcion original NO se toca: es lo
   que se muestra en pantalla y lo que se le dice al cliente.

   LA REGLA QUE NO SE PUEDE ROMPER
   Si un token tiene al menos un digito, no se toca. Las medidas son
   significativas y distinguen productos entre si:
       8-12 7mm     30-45 12mm     3SK 796     1.6
   Las abrazaderas se diferencian SOLO por la medida. Si la
   normalizacion se come los guiones, dejan de ser buscables.

   Esto se cumple solo: el diccionario reemplaza palabras completas
   rodeadas de espacios, y ninguna abreviatura de texto coincide con
   un token que tiene digitos.
   ================================================================= */


/* -----------------------------------------------------------------
   1. Diccionario de abreviaturas y sinonimos

   Se reemplaza PALABRA COMPLETA: el termino se busca rodeado de
   espacios. Asi "DEL" no rompe "DELANTERO" ni "DELCO".
   ----------------------------------------------------------------- */
IF OBJECT_ID('SinonimoBusqueda', 'U') IS NULL
BEGIN
    CREATE TABLE SinonimoBusqueda (
        Id        INT IDENTITY(1,1) PRIMARY KEY,
        Termino   VARCHAR(40) NOT NULL,   -- como viene en la lista
        Reemplazo VARCHAR(40) NOT NULL,   -- forma canonica
        Activo    BIT NOT NULL DEFAULT 1,
        CONSTRAINT UQ_Sinonimo UNIQUE (Termino)
    );
END
GO

-- Abreviaturas reales del rubro. Se carga una vez y crece con el uso.
MERGE SinonimoBusqueda AS destino
USING (VALUES
    -- Piezas
    ('BBA','BOMBA'), ('BBAS','BOMBA'), ('BOMB','BOMBA'),
    ('AMORT','AMORTIGUADOR'), ('AMORTIG','AMORTIGUADOR'), ('AMOR','AMORTIGUADOR'),
    ('ABRAZ','ABRAZADERA'), ('ABRAZAD','ABRAZADERA'),
    ('CIL','CILINDRO'), ('CILIN','CILINDRO'),
    ('RET','RETEN'), ('RETN','RETEN'),
    ('JGO','JUEGO'), ('JUEG','JUEGO'), ('KIT','JUEGO'),
    ('CJTO','CONJUNTO'), ('CONJ','CONJUNTO'),
    ('SOP','SOPORTE'), ('SOPT','SOPORTE'),
    ('TENS','TENSOR'), ('TENSR','TENSOR'),
    ('VALV','VALVULA'), ('VALVUL','VALVULA'),
    ('CORR','CORREA'),
    ('ROD','RODAMIENTO'), ('RODAM','RODAMIENTO'),
    ('EMBR','EMBRAGUE'),
    ('CRUC','CRUCETA'),
    ('HOMOC','HOMOCINETICA'),
    ('TERM','TERMOSTATO'),
    ('SENS','SENSOR'),
    ('ELECTROV','ELECTROVENTILADOR'), ('ELECTROVENT','ELECTROVENTILADOR'),

    -- Posicion
    ('DEL','DELANTERO'), ('DELANT','DELANTERO'), ('DELT','DELANTERO'),
    ('TRAS','TRASERO'), ('TRA','TRASERO'), ('TRAST','TRASERO'),
    ('IZQ','IZQUIERDO'), ('IZQUIER','IZQUIERDO'),
    ('DER','DERECHO'), ('DCHO','DERECHO'), ('DERECH','DERECHO'),
    ('SUP','SUPERIOR'), ('SUPER','SUPERIOR'),
    ('INF','INFERIOR'), ('INFER','INFERIOR'),
    ('CENT','CENTRAL'), ('CTRAL','CENTRAL'),
    ('INT','INTERIOR'), ('EXT','EXTERIOR'),

    -- Sistemas
    ('DIR','DIRECCION'), ('DIREC','DIRECCION'),
    ('SUSP','SUSPENSION'),
    ('DISTR','DISTRIBUCION'), ('DIST','DISTRIBUCION'),
    ('REFRIG','REFRIGERACION'), ('REFRI','REFRIGERACION'),
    ('ALIM','ALIMENTACION'),
    ('ESCAPE','ESCAPE'),
    ('MOT','MOTOR'),

    -- Marcas de vehiculo abreviadas
    ('VW','VOLKSWAGEN'), ('CHEV','CHEVROLET'), ('PEUG','PEUGEOT'),
    ('MBENZ','MERCEDES BENZ'), ('MB','MERCEDES BENZ'),
    ('REN','RENAULT'), ('FRD','FORD'), ('TOY','TOYOTA')
) AS origen (Termino, Reemplazo)
ON destino.Termino = origen.Termino
WHEN NOT MATCHED THEN
    INSERT (Termino, Reemplazo) VALUES (origen.Termino, origen.Reemplazo);
GO

SELECT COUNT(*) AS SinonimosCargados FROM SinonimoBusqueda WHERE Activo = 1;
GO


/* -----------------------------------------------------------------
   2. Columna derivada

   Aparte de Descripcion, no en lugar de ella. Si mañana mejora el
   diccionario, se reprocesa esta columna sin tocar el dato original.
   ----------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('ProveedorRepuesto') AND name = 'TextoBusqueda')
    ALTER TABLE ProveedorRepuesto ADD TextoBusqueda VARCHAR(400) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID('ProveedorRepuesto') AND name = 'IX_ProvRep_TextoBusqueda')
    CREATE INDEX IX_ProvRep_TextoBusqueda ON ProveedorRepuesto(TextoBusqueda);
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('Repuesto') AND name = 'TextoBusqueda')
    ALTER TABLE Repuesto ADD TextoBusqueda VARCHAR(400) NULL;
GO


/* -----------------------------------------------------------------
   3. Limpieza base

   Mayusculas, sin acentos, sin puntuacion que separe palabras,
   espacios colapsados. Los guiones y puntos DENTRO de un token con
   digitos se conservan: 8-12 sigue siendo 8-12, 1.6 sigue siendo 1.6.

   La coma, la barra y el punto y coma se convierten en espacio
   porque son separadores de aplicacion: "128/147/Duna" son tres
   modelos distintos y hay que poder buscar cualquiera.
   ----------------------------------------------------------------- */
IF OBJECT_ID('fn_LimpiarTexto', 'FN') IS NOT NULL DROP FUNCTION fn_LimpiarTexto;
GO

CREATE FUNCTION fn_LimpiarTexto(@texto VARCHAR(400))
RETURNS VARCHAR(400)
AS
BEGIN
    IF @texto IS NULL RETURN NULL;

    DECLARE @t VARCHAR(400) = UPPER(LTRIM(RTRIM(@texto)));

    -- Acentos
    SET @t = REPLACE(@t, 'Á', 'A');
    SET @t = REPLACE(@t, 'É', 'E');
    SET @t = REPLACE(@t, 'Í', 'I');
    SET @t = REPLACE(@t, 'Ó', 'O');
    SET @t = REPLACE(@t, 'Ú', 'U');
    SET @t = REPLACE(@t, 'Ü', 'U');
    SET @t = REPLACE(@t, 'Ñ', 'N');

    -- Separadores de aplicacion y puntuacion suelta
    SET @t = REPLACE(@t, '/',  ' ');
    SET @t = REPLACE(@t, '\',  ' ');
    SET @t = REPLACE(@t, ',',  ' ');
    SET @t = REPLACE(@t, ';',  ' ');
    SET @t = REPLACE(@t, '"',  ' ');
    SET @t = REPLACE(@t, '''', ' ');
    SET @t = REPLACE(@t, '(',  ' ');
    SET @t = REPLACE(@t, ')',  ' ');
    SET @t = REPLACE(@t, '+',  ' ');

    -- El punto solo separa cuando NO esta entre digitos.
    -- "BBA.AGUA" -> "BBA AGUA", pero "1.6" queda intacto.
    -- Se resuelve marcando los decimales, reemplazando, y devolviendolos.
    SET @t = REPLACE(@t, '0.', '0~');  SET @t = REPLACE(@t, '1.', '1~');
    SET @t = REPLACE(@t, '2.', '2~');  SET @t = REPLACE(@t, '3.', '3~');
    SET @t = REPLACE(@t, '4.', '4~');  SET @t = REPLACE(@t, '5.', '5~');
    SET @t = REPLACE(@t, '6.', '6~');  SET @t = REPLACE(@t, '7.', '7~');
    SET @t = REPLACE(@t, '8.', '8~');  SET @t = REPLACE(@t, '9.', '9~');
    SET @t = REPLACE(@t, '.', ' ');
    SET @t = REPLACE(@t, '~', '.');

    -- Espacios multiples
    WHILE CHARINDEX('  ', @t) > 0
        SET @t = REPLACE(@t, '  ', ' ');

    RETURN LTRIM(RTRIM(@t));
END
GO


/* -----------------------------------------------------------------
   4. Reprocesar TextoBusqueda

   El diccionario se aplica con REPLACE de palabra completa: el
   termino va rodeado de espacios, asi que 'DEL' no toca 'DELANTERO'
   ni 'DELCO'. Y como ningun sinonimo tiene digitos, las medidas
   quedan intactas por construccion.

   Se arma una cadena dinamica de REPLACE en vez de recorrer fila por
   fila: con 53.188 filas y 60 sinonimos, la diferencia es de minutos
   a segundos.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Busqueda_Reprocesar', 'P') IS NOT NULL DROP PROCEDURE SP_Busqueda_Reprocesar;
GO

CREATE PROCEDURE SP_Busqueda_Reprocesar
    @SoloNuevos BIT = 0    -- 1 = solo los que tienen TextoBusqueda NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Cadena de REPLACE anidados, uno por sinonimo
    DECLARE @expr NVARCHAR(MAX) = N'@base';

    SELECT @expr = N'REPLACE(' + @expr + N', '' ' + Termino + N' '', '' ' + Reemplazo + N' '')'
    FROM SinonimoBusqueda
    WHERE Activo = 1
    ORDER BY LEN(Termino) DESC;   -- primero los largos, para no romperlos

    DECLARE @sql NVARCHAR(MAX);

    /* --- Catalogo de proveedores --- */
    SET @sql = N'
        UPDATE ProveedorRepuesto
        SET TextoBusqueda = LTRIM(RTRIM(' +
            REPLACE(@expr, N'@base',
                N''' '' + dbo.fn_LimpiarTexto(Descripcion + '' '' + ISNULL(RubroTexto, '''') + '' '' + ISNULL(MarcaTexto, '''')) + '' ''')
        + N'))
        WHERE Activo = 1 ' +
        CASE WHEN @SoloNuevos = 1 THEN N'AND TextoBusqueda IS NULL' ELSE N'' END + N';';

    EXEC sp_executesql @sql;
    PRINT 'ProveedorRepuesto actualizado: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' filas.';

    /* --- Catalogo propio --- */
    SET @sql = N'
        UPDATE Repuesto
        SET TextoBusqueda = LTRIM(RTRIM(' +
            REPLACE(@expr, N'@base',
                N''' '' + dbo.fn_LimpiarTexto(Descripcion + '' '' + ISNULL(AplicacionTexto, '''') + '' '' + ISNULL(MarcaFabricante, '''')) + '' ''')
        + N'))
        WHERE Activo = 1 ' +
        CASE WHEN @SoloNuevos = 1 THEN N'AND TextoBusqueda IS NULL' ELSE N'' END + N';';

    EXEC sp_executesql @sql;
    PRINT 'Repuesto actualizado: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' filas.';
END
GO


/* -----------------------------------------------------------------
   5. Normalizar tambien lo que escribe el usuario

   La busqueda tiene que pasar por el mismo molde que los datos, o no
   matchea. Si el vendedor escribe "bba agua", se convierte en
   "BOMBA AGUA" antes de buscar.
   ----------------------------------------------------------------- */
IF OBJECT_ID('fn_NormalizarBusqueda', 'FN') IS NOT NULL DROP FUNCTION fn_NormalizarBusqueda;
GO

CREATE FUNCTION fn_NormalizarBusqueda(@texto VARCHAR(200))
RETURNS VARCHAR(400)
AS
BEGIN
    IF @texto IS NULL RETURN NULL;

    DECLARE @t VARCHAR(400) = ' ' + dbo.fn_LimpiarTexto(@texto) + ' ';

    -- Aca si conviene recorrer: son pocas palabras, no 53.000 filas
    SELECT @t = REPLACE(@t, ' ' + Termino + ' ', ' ' + Reemplazo + ' ')
    FROM SinonimoBusqueda
    WHERE Activo = 1;

    RETURN LTRIM(RTRIM(@t));
END
GO


/* -----------------------------------------------------------------
   6. EJECUCION Y VERIFICACION
   ----------------------------------------------------------------- */
EXEC SP_Busqueda_Reprocesar @SoloNuevos = 0;
GO

-- Las medidas tienen que haber sobrevivido intactas
SELECT TOP 10 CodigoProveedor, Descripcion, TextoBusqueda
FROM ProveedorRepuesto
WHERE Descripcion LIKE '%8-12%' OR Descripcion LIKE '%30-45%' OR Descripcion LIKE '%1.6%';
GO

-- Prueba del normalizador de consulta
SELECT
    'bba agua suran'          AS Escribio, dbo.fn_NormalizarBusqueda('bba agua suran')          AS Busca
UNION ALL SELECT 'amort del izq',        dbo.fn_NormalizarBusqueda('amort del izq')
UNION ALL SELECT 'abraz 8-12 7mm',       dbo.fn_NormalizarBusqueda('abraz 8-12 7mm')
UNION ALL SELECT 'bomba agua vw 1.6',    dbo.fn_NormalizarBusqueda('bomba agua vw 1.6')
UNION ALL SELECT 'sop mot der',          dbo.fn_NormalizarBusqueda('sop mot der');
GO

-- Cuantas filas quedaron sin normalizar (deberia dar 0)
SELECT COUNT(*) AS SinNormalizar
FROM ProveedorRepuesto WHERE Activo = 1 AND TextoBusqueda IS NULL;
GO
