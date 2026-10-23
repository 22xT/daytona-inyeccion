USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   77 — LA MARCA DE LA PIEZA, NO LA DEL AUTO

   Al vincular, los articulos de Autocor salian como "otra marca":
   Autocor usa su columna Marca para la marca del VEHICULO
   ("VOLKSWAGEN - SEAT"), y la marca de la pieza la pone en el rubro
   entre comillas: CORREAS POLI-V "HUTCHINSON".

   fn_MarcaPieza decide la marca de la pieza de un articulo de lista:
     1. la que esta entre comillas en el rubro, si hay
     2. si no, la columna marca, salvo que sea una marca de auto
        o "VARIOS" (en ese caso queda sin dato)
   No se borra nada de lo cargado: la marca del vehiculo sigue en
   MarcaTexto y sirve para buscar.

   Se usa en SP_Repuesto_Vinculacion (misma definicion que el 65,
   solo cambia de donde sale la marca).
   ================================================================= */


/* -----------------------------------------------------------------
   1. Marca de la pieza
   ----------------------------------------------------------------- */
IF OBJECT_ID('fn_MarcaPieza', 'FN') IS NOT NULL DROP FUNCTION fn_MarcaPieza;
GO
CREATE FUNCTION fn_MarcaPieza
(
    @RubroTexto VARCHAR(120),
    @MarcaTexto VARCHAR(60)
)
RETURNS VARCHAR(60)
AS
BEGIN
    DECLARE @i INT = CHARINDEX('"', ISNULL(@RubroTexto, ''));
    DECLARE @j INT = CASE WHEN @i > 0 THEN CHARINDEX('"', @RubroTexto, @i + 1) ELSE 0 END;

    IF @j > @i + 1
        RETURN LTRIM(RTRIM(SUBSTRING(@RubroTexto, @i + 1, @j - @i - 1)));

    DECLARE @m VARCHAR(60) = UPPER(LTRIM(RTRIM(ISNULL(@MarcaTexto, ''))));
    IF @m = '' RETURN NULL;

    -- Primera palabra ("VOLKSWAGEN - SEAT" -> VOLKSWAGEN)
    DECLARE @p VARCHAR(60) = CASE WHEN CHARINDEX(' ', @m) > 0 THEN LEFT(@m, CHARINDEX(' ', @m) - 1) ELSE @m END;

    IF @p IN ('VARIOS', 'VARIAS', 'UNIVERSAL', 'GENERICO', 'GENERAL',
              'VOLKSWAGEN', 'VW', 'FORD', 'FIAT', 'CHEVROLET', 'GM', 'RENAULT', 'PEUGEOT', 'CITROEN',
              'TOYOTA', 'HONDA', 'NISSAN', 'SEAT', 'AUDI', 'BMW', 'MERCEDES', 'MERCEDES-BENZ', 'JEEP',
              'DODGE', 'CHRYSLER', 'RAM', 'KIA', 'HYUNDAI', 'SUZUKI', 'MITSUBISHI', 'IVECO', 'SCANIA',
              'VOLVO', 'SUBARU', 'MAZDA', 'ALFA', 'LAND', 'MINI', 'SKODA', 'CHERY', 'GEELY', 'LIFAN',
              'JAC', 'BAIC', 'DFSK', 'HAVAL', 'GREAT', 'ISUZU', 'DAEWOO', 'SSANGYONG', 'SMART', 'DS',
              'PORSCHE', 'LANCIA', 'RENAULT/NISSAN', 'VW/AUDI', 'FIAT/IVECO', 'AGRALE')
        RETURN NULL;

    RETURN LTRIM(RTRIM(@MarcaTexto));
END
GO


/* -----------------------------------------------------------------
   2. Vinculacion con la marca de la pieza
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Repuesto_Vinculacion', 'P') IS NOT NULL DROP PROCEDURE SP_Repuesto_Vinculacion;
GO
CREATE PROCEDURE SP_Repuesto_Vinculacion
    @IdRepuesto INT,
    @Texto      VARCHAR(100) = NULL,
    @Tope       INT = 40
AS
BEGIN
    SET NOCOUNT ON;

    IF @Tope IS NULL OR @Tope <= 0 OR @Tope > 100 SET @Tope = 40;

    DECLARE @desc NVARCHAR(100), @marca VARCHAR(60), @codFab VARCHAR(40), @cod VARCHAR(40),
            @idRubro INT, @costo DECIMAL(12,2), @grupo INT;

    SELECT @desc = Descripcion, @marca = MarcaFabricante, @codFab = CodigoFabricante,
           @cod = Codigo, @idRubro = IdRubro, @costo = PrecioCompra, @grupo = IdGrupoEquivalencia
    FROM Repuesto WHERE Id = @IdRepuesto;

    IF @desc IS NULL
        THROW 50124, 'El repuesto no existe.', 1;

    DECLARE @auto BIT = CASE WHEN NULLIF(LTRIM(RTRIM(@Texto)), '') IS NULL THEN 1 ELSE 0 END;
    DECLARE @codFabL VARCHAR(60) = dbo.fn_LimpiarCodigo(ISNULL(@codFab, ''));
    DECLARE @codL    VARCHAR(60) = dbo.fn_LimpiarCodigo(ISNULL(@cod, ''));
    DECLARE @marcaL  VARCHAR(60) = dbo.fn_LimpiarCodigo(ISNULL(@marca, ''));
    DECLARE @marcaN  VARCHAR(100) = ISNULL(dbo.fn_NormalizarBusqueda(@marca), '');

    /* Palabras a buscar (hasta 8), normalizadas igual que TextoBusqueda */
    DECLARE @Palabras TABLE (Orden INT IDENTITY(1,1), W VARCHAR(60), Cod VARCHAR(60));
    DECLARE @t VARCHAR(400) = ISNULL(dbo.fn_NormalizarBusqueda(CASE WHEN @auto = 1 THEN @desc ELSE @Texto END), '') + ' ';
    DECLARE @pos INT, @w VARCHAR(60);

    WHILE LEN(@t) > 0 AND (SELECT COUNT(*) FROM @Palabras) < 8
    BEGIN
        IF CHARINDEX(' ', @t) = 0 SET @t = @t + ' ';
        SET @pos = CHARINDEX(' ', @t);
        SET @w = LEFT(@t, @pos - 1);
        SET @t = LTRIM(SUBSTRING(@t, @pos + 1, 400));

        IF LEN(@w) >= 2
           AND @w NOT IN ('DE','LA','EL','LOS','LAS','CON','SIN','PARA','POR','Y','EN','AL','DEL')
           AND NOT EXISTS (SELECT 1 FROM @Palabras WHERE W = @w)
           -- En automatico se saca la marca y los codigos propios:
           -- asi aparecen tambien las otras marcas de la misma pieza
           AND NOT (@auto = 1 AND (
                    (@marcaN <> '' AND ' ' + @marcaN + ' ' LIKE '% ' + @w + ' %')
                 OR (dbo.fn_LimpiarCodigo(@w) IN (@codFabL, @codL) AND LEN(dbo.fn_LimpiarCodigo(@w)) >= 4)))
            INSERT INTO @Palabras (W, Cod)
            VALUES (@w, CASE WHEN @w LIKE '%[0-9]%' AND LEN(dbo.fn_LimpiarCodigo(@w)) >= 4
                             THEN dbo.fn_LimpiarCodigo(@w) END);
    END

    DECLARE @n INT = (SELECT COUNT(*) FROM @Palabras);
    DECLARE @req INT = CASE WHEN @n <= 2 THEN @n WHEN @n = 3 THEN 2 ELSE CEILING(@n * 0.6) END;

    DECLARE @textoUsado VARCHAR(400) =
        CASE WHEN @auto = 1
             THEN ISNULL((SELECT ' ' + W FROM @Palabras ORDER BY Orden FOR XML PATH(''), TYPE).value('.', 'VARCHAR(400)'), '')
             ELSE @Texto END;

    /* 1) El repuesto */
    SELECT r.Id, r.Codigo, r.Descripcion, r.MarcaFabricante, r.CodigoFabricante,
           r.IdGrupoEquivalencia, r.PrecioCompra, ISNULL(s.Cantidad, 0) AS Stock,
           LTRIM(@textoUsado) AS TextoUsado
    FROM Repuesto r
    LEFT JOIN Stock s ON s.IdRepuesto = r.Id
    WHERE r.Id = @IdRepuesto;

    /* 2) Candidatos */
    ;WITH base AS (
        SELECT pr.Id, pr.IdProveedor, p.RazonSocial AS Proveedor, pr.CodigoProveedor,
               pr.Articulo, pr.Descripcion,
               pr.RubroTexto, pr.MarcaTexto AS MarcaLista,
               pr.PrecioCompra, pr.IdRubro,
               pr.IdRepuesto AS IdRepuestoEnlazado,
               re.Codigo AS CodigoEnlazado, re.Descripcion AS DescripcionEnlazado,
               (SELECT COUNT(*) FROM @Palabras w
                WHERE pr.TextoBusqueda LIKE '% ' + w.W + '%'
                   OR (w.Cod IS NOT NULL AND pr.CodigosBusqueda LIKE '%' + w.Cod + '%')) AS Coincidencias,
               -- Mismo codigo de fabrica: en su columna, o escrito en la
               -- descripcion (Expoyer pone "KIT ... KTBWP3411 FOX/SURAN")
               CASE WHEN LEN(@codFabL) >= 5
                     AND (REPLACE(REPLACE(REPLACE(REPLACE(UPPER(ISNULL(pr.Articulo, '')), '-', ''), ' ', ''), '.', ''), '/', '') = @codFabL
                          OR REPLACE(pr.TextoBusqueda, '-', '') LIKE '% ' + @codFabL + ' %')
                    THEN 1 ELSE 0 END AS MismoCodigo,
               pr.TextoBusqueda,
               CASE WHEN EXISTS (SELECT 1 FROM ProveedorRepuesto x
                                 WHERE x.IdRepuesto = @IdRepuesto AND x.IdProveedor = pr.IdProveedor)
                    THEN 1 ELSE 0 END AS ProveedorYaVinculado
        FROM ProveedorRepuesto pr
        INNER JOIN Proveedor p ON p.Id = pr.IdProveedor
        LEFT JOIN Repuesto re  ON re.Id = pr.IdRepuesto
        WHERE pr.Activo = 1
          AND pr.PrecioCompra > 0
          AND ISNULL(pr.IdRepuesto, 0) <> @IdRepuesto
          -- Lo que ya es equivalente se muestra aparte
          AND NOT (@grupo IS NOT NULL AND (pr.IdGrupoEquivalencia = @grupo OR re.IdGrupoEquivalencia = @grupo))
    ),
    -- Primero se filtra; la marca se calcula solo para los candidatos
    candidatos AS (
        SELECT b.*,
               -- La marca de la PIEZA: Autocor pone en su columna Marca la del
               -- vehiculo; la de la pieza viene en el rubro entre comillas
               dbo.fn_MarcaPieza(b.RubroTexto, b.MarcaLista) AS MarcaTexto
        FROM base b
        WHERE b.MismoCodigo = 1 OR (@n > 0 AND b.Coincidencias >= @req)
    ),
    conMarca AS (
        SELECT c.*, dbo.fn_LimpiarCodigo(ISNULL(c.MarcaTexto, '')) AS mL
        FROM candidatos c
    ),
    filtrado AS (
        SELECT b.*,
               CASE
                   WHEN @marcaL = '' THEN 'SIN_DATO'
                   WHEN b.mL = '' THEN
                        CASE WHEN @marcaN <> '' AND b.TextoBusqueda LIKE '% ' + @marcaN + ' %'
                             THEN 'MISMA' ELSE 'SIN_DATO' END
                   WHEN b.mL = @marcaL THEN 'MISMA'
                   WHEN LEN(@marcaL) >= 3 AND LEN(b.mL) >= 3
                        AND (CHARINDEX(@marcaL, b.mL) > 0 OR CHARINDEX(b.mL, @marcaL) > 0) THEN 'MISMA'
                   ELSE 'OTRA'
               END AS Marca
        FROM conMarca b
    )
    SELECT TOP (@Tope)
        f.Id, f.IdProveedor, f.Proveedor, f.CodigoProveedor, f.Articulo, f.Descripcion,
        f.MarcaTexto, f.Marca, f.PrecioCompra,
        CASE WHEN @costo > 0 THEN CAST((f.PrecioCompra - @costo) / @costo * 100 AS DECIMAL(8,1)) END AS DiferenciaPorc,
        f.MismoCodigo, f.Coincidencias, @n AS Palabras,
        f.IdRepuestoEnlazado, f.CodigoEnlazado, f.DescripcionEnlazado, f.ProveedorYaVinculado,
        f.MismoCodigo * 100 + f.Coincidencias * 10
          + CASE WHEN f.Marca = 'MISMA' THEN 15 ELSE 0 END
          + CASE WHEN f.IdRubro = @idRubro THEN 5 ELSE 0 END AS Puntaje,
        -- Solo se pre-marca lo seguro; el resto lo decide la persona
        CASE WHEN f.MismoCodigo = 1 AND f.Marca <> 'OTRA'
                  AND f.IdRepuestoEnlazado IS NULL AND f.ProveedorYaVinculado = 0
             THEN 'MISMO' ELSE '' END AS Sugerido
    FROM filtrado f
    ORDER BY Puntaje DESC, f.PrecioCompra;

    /* 3) Equivalentes actuales */
    EXEC SP_Repuesto_Equivalentes @IdRepuesto = @IdRepuesto;
END
GO

/* -----------------------------------------------------------------
   PRUEBA (no modifica nada): que marca sale para cada proveedor
   ----------------------------------------------------------------- */
SELECT TOP 20 p.RazonSocial, pr.RubroTexto, pr.MarcaTexto AS MarcaDeLaLista,
       dbo.fn_MarcaPieza(pr.RubroTexto, pr.MarcaTexto) AS MarcaDeLaPieza, pr.Descripcion
FROM ProveedorRepuesto pr
INNER JOIN Proveedor p ON p.Id = pr.IdProveedor
WHERE pr.Activo = 1 AND pr.Descripcion LIKE '%3SK%';
GO
