/* =================================================================
   87 — LA BUSQUEDA IGNORA "DE", "LA", "PARA"... (28/10)

   EL PROBLEMA
   La busqueda exige que aparezcan TODAS las palabras. Si el vendedor
   escribe "bomba de agua suran", el "de" tambien se exige. Expoyer
   escribe "BBA.AGUA SURAN 1.6" (sin "de") y quedaba afuera; Autocor
   aparecia solo porque su rubro dice "BOMBAS DE AGUA". Resultado:
   casi todo de un solo proveedor.

   LA SOLUCION
   fn_NormalizarBusqueda (lo que se hace con el texto que se escribe)
   saca las palabras que no distinguen un repuesto de otro:
   DE, LA, EL, LOS, LAS, PARA, CON, Y, EN, UN, UNA, AL.
   "DEL" NO se saca: es la abreviatura de DELANTERO.
   Si alguien escribe solo palabras vacias, se busca lo que escribio.

   Lo usan el Buscador, la Venta, el Catalogo de proveedores, la
   vinculacion y el registro de busquedas: se arregla en todos a la vez.
   No toca los datos ni la descripcion de ningun articulo.
   ================================================================= */
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER FUNCTION fn_NormalizarBusqueda(@texto VARCHAR(200))
RETURNS VARCHAR(400)
AS
BEGIN
    IF @texto IS NULL RETURN NULL;

    DECLARE @t VARCHAR(400) = ' ' + dbo.fn_LimpiarTexto(@texto) + ' ';

    -- Abreviaturas y sinonimos (script 23)
    SELECT @t = REPLACE(@t, ' ' + Termino + ' ', ' ' + Reemplazo + ' ')
    FROM SinonimoBusqueda
    WHERE Activo = 1;

    -- Palabras vacias (script 87). Dos pasadas: "DE LA DE" queda limpio.
    DECLARE @sin VARCHAR(400) = @t, @i INT = 0;
    WHILE @i < 2
    BEGIN
        SET @sin = REPLACE(@sin, ' DE ',   ' ');
        SET @sin = REPLACE(@sin, ' LA ',   ' ');
        SET @sin = REPLACE(@sin, ' EL ',   ' ');
        SET @sin = REPLACE(@sin, ' LOS ',  ' ');
        SET @sin = REPLACE(@sin, ' LAS ',  ' ');
        SET @sin = REPLACE(@sin, ' PARA ', ' ');
        SET @sin = REPLACE(@sin, ' CON ',  ' ');
        SET @sin = REPLACE(@sin, ' Y ',    ' ');
        SET @sin = REPLACE(@sin, ' EN ',   ' ');
        SET @sin = REPLACE(@sin, ' UN ',   ' ');
        SET @sin = REPLACE(@sin, ' UNA ',  ' ');
        SET @sin = REPLACE(@sin, ' AL ',   ' ');
        SET @i = @i + 1;
    END
    IF LEN(LTRIM(RTRIM(@sin))) > 0 SET @t = @sin;

    -- Espacios dobles que dejan los reemplazos
    WHILE CHARINDEX('  ', @t) > 0 SET @t = REPLACE(@t, '  ', ' ');

    RETURN LTRIM(RTRIM(@t));
END
GO

-- Prueba: tiene que dar BOMBA AGUA SURAN, JUEGO DISTRIBUCION GOL, DE
SELECT dbo.fn_NormalizarBusqueda('bomba de agua suran') AS Prueba1,
       dbo.fn_NormalizarBusqueda('kit de distribucion para gol') AS Prueba2,
       dbo.fn_NormalizarBusqueda('de') AS Prueba3;
GO
