USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   29 — INCORPORAR ELIGIENDO EL RUBRO + VINCULAR AL SEGUNDO PROVEEDOR

   POR QUE
   Los rubros de Expoyer son codigos numericos (58, 55, 220) que
   agrupan cosas distintas a las de Autocor: el 58 junta tapones de
   caja, bulones de tapa de cilindros y kits de distribucion.
   Traducirlos no sirve, porque no hay equivalencia real.

   La solucion es que el rubro se elija AL INCORPORAR, que es cuando
   una persona sabe donde va esa pieza en su propio negocio. Es lo
   mismo que se hace al cargar un repuesto a mano.

   Y ADEMAS
   Al incorporar un articulo, se buscan sus equivalentes en los otros
   proveedores por codigo de fabricante. Ese es el momento en que el
   enlace es mas barato: ya se esta mirando esa pieza.
   ================================================================= */


/* -----------------------------------------------------------------
   1. Incorporar con rubro explicito
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Repuesto_IncorporarDesdeLista', 'P') IS NOT NULL
    DROP PROCEDURE SP_Repuesto_IncorporarDesdeLista;
GO

CREATE PROCEDURE SP_Repuesto_IncorporarDesdeLista
    @IdListaProveedor INT,
    @IdRubro          INT = NULL,   -- si no viene, se usa el del articulo
    @IdModelo         INT = NULL,
    @StockMinimo      INT = 5,
    @PrecioNetoVenta  DECIMAL(12,2) = NULL,
    @Descripcion      NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @Codigo VARCHAR(40), @Articulo VARCHAR(40), @RubroTexto VARCHAR(120),
                @DescProv NVARCHAR(250), @Costo DECIMAL(12,2), @IdRubroLista INT,
                @IdRepuestoExistente INT, @Fabricante VARCHAR(60), @IdProv INT;

        SELECT @Codigo = pr.CodigoProveedor, @Articulo = pr.Articulo,
               @RubroTexto = pr.RubroTexto, @DescProv = pr.Descripcion,
               @Costo = pr.PrecioCompra, @IdRubroLista = pr.IdRubro,
               @IdRepuestoExistente = pr.IdRepuesto, @IdProv = pr.IdProveedor
        FROM ProveedorRepuesto pr WHERE pr.Id = @IdListaProveedor;

        IF @Codigo IS NULL
        BEGIN
            RAISERROR('El articulo de la lista no existe.', 16, 1);
            RETURN;
        END

        IF @IdRepuestoExistente IS NOT NULL
        BEGIN
            RAISERROR('Ese articulo ya esta enlazado a un repuesto de tu catalogo.', 16, 1);
            RETURN;
        END

        -- El rubro elegido manda sobre el del proveedor
        IF @IdRubro IS NULL SET @IdRubro = @IdRubroLista;

        IF @IdRubro IS NULL
        BEGIN
            RAISERROR('Elegi un rubro: el proveedor no manda uno que se pueda usar.', 16, 1);
            RETURN;
        END

        IF NOT EXISTS (SELECT 1 FROM Rubro WHERE Id = @IdRubro)
        BEGIN
            RAISERROR('El rubro indicado no existe.', 16, 1);
            RETURN;
        END

        IF @Costo IS NULL OR @Costo <= 0
        BEGIN
            RAISERROR('El articulo no tiene costo cargado en la lista.', 16, 1);
            RETURN;
        END

        IF @Descripcion IS NULL OR LTRIM(RTRIM(@Descripcion)) = ''
            SET @Descripcion = LEFT(@DescProv, 100);

        -- El fabricante viene entre comillas en el rubro, cuando lo declara
        SET @Fabricante =
            CASE WHEN CHARINDEX('"', ISNULL(@RubroTexto, '')) > 0
                 THEN LTRIM(RTRIM(SUBSTRING(@RubroTexto,
                        CHARINDEX('"', @RubroTexto) + 1,
                        CHARINDEX('"', @RubroTexto, CHARINDEX('"', @RubroTexto) + 1)
                            - CHARINDEX('"', @RubroTexto) - 1)))
                 ELSE NULL END;

        DECLARE @salida TABLE (Id INT, Codigo VARCHAR(40));

        INSERT INTO @salida
        EXEC SP_Repuesto_I
            @Descripcion = @Descripcion, @PrecioDeVenta = NULL,
            @IdModelo = @IdModelo, @IdRubro = @IdRubro, @Codigo = @Codigo,
            @CodigoFabricante = @Articulo, @MarcaFabricante = @Fabricante,
            @PrecioCompra = @Costo, @PrecioNetoVenta = @PrecioNetoVenta,
            @IdAlicuotaIva = NULL, @StockMinimo = @StockMinimo;

        DECLARE @IdNuevo INT;
        SELECT TOP 1 @IdNuevo = Id FROM @salida;

        UPDATE Repuesto SET AplicacionTexto = @DescProv WHERE Id = @IdNuevo;
        UPDATE ProveedorRepuesto SET IdRepuesto = @IdNuevo WHERE Id = @IdListaProveedor;
        UPDATE Repuesto SET TextoBusqueda = NULL WHERE Id = @IdNuevo;

        SELECT @IdNuevo AS Id, (SELECT TOP 1 Codigo FROM @salida) AS Codigo,
               @IdProv AS IdProveedorOrigen, @Articulo AS CodigoFabricante;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   2. Buscar el mismo repuesto en los otros proveedores

   El codigo de fabricante es la mejor señal, pero no es una clave:
   hay 7.934 repetidos y valores basura. Por eso se SUGIERE con un
   nivel de confianza y lo confirma una persona.

   Se normalizan guiones y espacios: Autocor escribe KTB341 y
   Expoyer KTB-341 para el mismo kit Dayco.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Repuesto_BuscarEnOtrosProveedores', 'P') IS NOT NULL
    DROP PROCEDURE SP_Repuesto_BuscarEnOtrosProveedores;
GO

CREATE PROCEDURE SP_Repuesto_BuscarEnOtrosProveedores
    @IdRepuesto INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @codFab VARCHAR(40), @desc NVARCHAR(100), @costo DECIMAL(12,2);
    SELECT @codFab = CodigoFabricante, @desc = Descripcion, @costo = PrecioCompra
    FROM Repuesto WHERE Id = @IdRepuesto;

    -- Sin guiones ni espacios, para que KTB341 y KTB-341 se encuentren
    DECLARE @codLimpio VARCHAR(40) =
        REPLACE(REPLACE(REPLACE(UPPER(ISNULL(@codFab, '')), '-', ''), ' ', ''), '.', '');

    SELECT
        pr.Id,
        pr.IdProveedor,
        p.RazonSocial       AS Proveedor,
        pr.CodigoProveedor,
        pr.Articulo,
        pr.Descripcion,
        pr.PrecioCompra,
        @costo              AS MiCostoActual,
        CAST(pr.PrecioCompra - @costo AS DECIMAL(12,2)) AS Diferencia,
        CASE WHEN @costo > 0
             THEN CAST((pr.PrecioCompra - @costo) / @costo * 100 AS DECIMAL(6,2))
             ELSE NULL END  AS DiferenciaPorc,

        /* Alta: mismo codigo de fabricante, ignorando guiones.
           Media: la descripcion arranca igual.
           Es una sugerencia: la confirma una persona. */
        CASE WHEN @codLimpio <> ''
              AND REPLACE(REPLACE(REPLACE(UPPER(ISNULL(pr.Articulo, '')), '-', ''), ' ', ''), '.', '')
                  = @codLimpio
             THEN 'Alta' ELSE 'Media' END AS Confianza

    FROM ProveedorRepuesto pr
    INNER JOIN Proveedor p ON p.Id = pr.IdProveedor
    WHERE pr.Activo = 1
      AND pr.PrecioCompra > 0
      AND pr.IdRepuesto IS NULL          -- todavia sin enlazar
      AND (
            (@codLimpio <> ''
             AND REPLACE(REPLACE(REPLACE(UPPER(ISNULL(pr.Articulo, '')), '-', ''), ' ', ''), '.', '')
                 = @codLimpio)
            OR pr.Descripcion LIKE LEFT(@desc, 18) + '%'
          )
    ORDER BY
        CASE WHEN @codLimpio <> ''
              AND REPLACE(REPLACE(REPLACE(UPPER(ISNULL(pr.Articulo, '')), '-', ''), ' ', ''), '.', '')
                  = @codLimpio
             THEN 0 ELSE 1 END,
        pr.PrecioCompra;
END
GO


/* -----------------------------------------------------------------
   3. PRUEBA con el caso real detectado

   Autocor 452G006  = kit Dayco KTB341   a $36.131,51
   Expoyer WWW109119F-Z = kit KTB-341    a $38.605,16

   Es el mismo kit. Autocor lo tiene $2.473 mas barato.
   ----------------------------------------------------------------- */
SELECT pr.Id, p.RazonSocial, pr.CodigoProveedor, pr.Articulo,
       pr.Descripcion, pr.PrecioCompra
FROM ProveedorRepuesto pr
INNER JOIN Proveedor p ON p.Id = pr.IdProveedor
WHERE pr.Activo = 1
  AND REPLACE(REPLACE(UPPER(ISNULL(pr.Articulo, '')), '-', ''), ' ', '') LIKE '%KTB341%'
ORDER BY pr.PrecioCompra;
GO
