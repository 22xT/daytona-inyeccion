USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   20 — Busqueda con precio sugerido + correccion de MarcaFabricante
   ================================================================= */

/* -----------------------------------------------------------------
   1. SP_ProveedorRepuesto_Buscar con precio de venta sugerido

   Ver el costo no alcanza para decidir si incorporar un articulo:
   lo que importa es a cuanto se va a vender. Se calcula aca, con el
   mismo criterio que el resto del sistema: margen del rubro, o el
   general si el rubro no tiene uno propio, mas IVA.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_ProveedorRepuesto_Buscar', 'P') IS NOT NULL
    DROP PROCEDURE SP_ProveedorRepuesto_Buscar;
GO

CREATE PROCEDURE SP_ProveedorRepuesto_Buscar
    @IdProveedor    INT = NULL,
    @Texto          VARCHAR(100) = NULL,
    @SoloSinEnlazar BIT = 1,
    @Tope           INT = 100
AS
BEGIN
    SET NOCOUNT ON;

    IF @Tope IS NULL OR @Tope <= 0 SET @Tope = 100;
    IF @Tope > 500 SET @Tope = 500;

    DECLARE @MargenGeneral DECIMAL(6,2) =
        ISNULL(TRY_CAST((SELECT Valor FROM ParametroSistema WHERE Clave = 'MargenGeneral')
                        AS DECIMAL(6,2)), 50);

    DECLARE @IvaDefecto DECIMAL(5,2) =
        ISNULL((SELECT TOP 1 Porcentaje FROM AlicuotaIva WHERE Porcentaje = 21 AND Activo = 1), 21);

    SELECT TOP (@Tope)
        pr.Id,
        pr.IdProveedor,
        p.RazonSocial       AS Proveedor,
        pr.CodigoProveedor,
        pr.Articulo,
        pr.Descripcion,
        pr.RubroTexto,
        pr.MarcaTexto,
        pr.IdRubro,
        r.Nombre            AS Rubro,
        pr.PrecioLista,
        pr.DescuentoRubro,
        pr.DescuentoGeneral,
        pr.PrecioCompra,

        -- Margen que le corresponde por su rubro
        ISNULL(r.MargenPorcentaje, @MargenGeneral) AS MargenAplicado,

        CAST(pr.PrecioCompra * (1 + ISNULL(r.MargenPorcentaje, @MargenGeneral) / 100.0)
             AS DECIMAL(12,2)) AS NetoSugerido,

        CAST(pr.PrecioCompra * (1 + ISNULL(r.MargenPorcentaje, @MargenGeneral) / 100.0)
             * (1 + @IvaDefecto / 100.0)
             AS DECIMAL(12,2)) AS FinalSugerido,

        pr.IdRepuesto,
        CASE WHEN pr.IdRepuesto IS NULL THEN 0 ELSE 1 END AS YaEnCatalogo,
        rep.Codigo      AS CodigoPropio,
        rep.Descripcion AS DescripcionPropia,
        ISNULL(st.Cantidad, 0) AS StockPropio

    FROM ProveedorRepuesto pr
    INNER JOIN Proveedor p ON p.Id = pr.IdProveedor
    LEFT JOIN Rubro r      ON r.Id = pr.IdRubro
    LEFT JOIN Repuesto rep ON rep.Id = pr.IdRepuesto
    LEFT JOIN Stock st     ON st.IdRepuesto = pr.IdRepuesto
    WHERE pr.Activo = 1
      AND pr.PrecioCompra > 0          -- sin costo no se puede incorporar
      AND (@IdProveedor IS NULL OR pr.IdProveedor = @IdProveedor)
      AND (@SoloSinEnlazar = 0 OR pr.IdRepuesto IS NULL)
      AND (@Texto IS NULL OR @Texto = ''
           OR pr.Descripcion LIKE '%' + @Texto + '%'
           OR pr.CodigoProveedor LIKE @Texto + '%'
           OR pr.Articulo LIKE @Texto + '%')
    ORDER BY pr.Descripcion;
END
GO


/* -----------------------------------------------------------------
   2. Corregir MarcaFabricante

   PROBLEMA: al incorporar un repuesto se estaba guardando en
   MarcaFabricante la columna Marca de la lista, que es la marca del
   VEHICULO ("VARIOS", "FIAT", "VOLKSWAGEN - SEAT"), no la del
   fabricante de la pieza.

   El fabricante viene dentro del texto del rubro, entre comillas:
       ABRAZADERAS "PERFECTO"   -> PERFECTO
       AMORTIGUADORES "NAKATA"  -> NAKATA
       BOMBAS DE AGUA "VMG"     -> VMG

   Los rubros sin comillas (HERRAMIENTAS, BOMBAS DE FRENO) no
   declaran fabricante: quedan en NULL, que es lo correcto.
   ----------------------------------------------------------------- */

-- Ver que se va a extraer, antes de tocar nada
SELECT DISTINCT TOP 30
    pr.RubroTexto,
    CASE WHEN CHARINDEX('"', pr.RubroTexto) > 0
         THEN LTRIM(RTRIM(SUBSTRING(
                pr.RubroTexto,
                CHARINDEX('"', pr.RubroTexto) + 1,
                CHARINDEX('"', pr.RubroTexto, CHARINDEX('"', pr.RubroTexto) + 1)
                    - CHARINDEX('"', pr.RubroTexto) - 1)))
         ELSE NULL END AS FabricanteExtraido
FROM ProveedorRepuesto pr
WHERE CHARINDEX('"', pr.RubroTexto) > 0
ORDER BY pr.RubroTexto;
GO

-- Corregir los repuestos ya incorporados
UPDATE rep
SET rep.MarcaFabricante =
    CASE WHEN CHARINDEX('"', pr.RubroTexto) > 0
         THEN LTRIM(RTRIM(SUBSTRING(
                pr.RubroTexto,
                CHARINDEX('"', pr.RubroTexto) + 1,
                CHARINDEX('"', pr.RubroTexto, CHARINDEX('"', pr.RubroTexto) + 1)
                    - CHARINDEX('"', pr.RubroTexto) - 1)))
         ELSE NULL END
FROM Repuesto rep
INNER JOIN ProveedorRepuesto pr ON pr.IdRepuesto = rep.Id
WHERE pr.Activo = 1;
GO

SELECT Id, Codigo, Descripcion, CodigoFabricante, MarcaFabricante
FROM Repuesto ORDER BY Id;
GO


/* -----------------------------------------------------------------
   3. SP_Repuesto_IncorporarDesdeLista: tomar el fabricante del rubro
      y arrastrar la aplicacion vehicular
   ----------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('Repuesto') AND name = 'AplicacionTexto')
    ALTER TABLE Repuesto ADD AplicacionTexto VARCHAR(250) NULL;
GO

IF OBJECT_ID('SP_Repuesto_IncorporarDesdeLista', 'P') IS NOT NULL
    DROP PROCEDURE SP_Repuesto_IncorporarDesdeLista;
GO

CREATE PROCEDURE SP_Repuesto_IncorporarDesdeLista
    @IdListaProveedor INT,
    @IdModelo         INT = NULL,
    @StockMinimo      INT = 5,
    @PrecioNetoVenta  DECIMAL(12,2) = NULL,   -- si viene, pisa al sugerido
    @Descripcion      NVARCHAR(100) = NULL    -- si viene, pisa a la del proveedor
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @Codigo VARCHAR(40), @Articulo VARCHAR(40), @RubroTexto VARCHAR(120),
                @DescProv NVARCHAR(250), @Costo DECIMAL(12,2), @IdRubro INT,
                @IdRepuestoExistente INT, @Fabricante VARCHAR(60);

        SELECT
            @Codigo      = pr.CodigoProveedor,
            @Articulo    = pr.Articulo,
            @RubroTexto  = pr.RubroTexto,
            @DescProv    = pr.Descripcion,
            @Costo       = pr.PrecioCompra,
            @IdRubro     = pr.IdRubro,
            @IdRepuestoExistente = pr.IdRepuesto
        FROM ProveedorRepuesto pr
        WHERE pr.Id = @IdListaProveedor;

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

        IF @IdRubro IS NULL
        BEGIN
            RAISERROR('El articulo no tiene rubro propio asignado.', 16, 1);
            RETURN;
        END

        IF @Costo IS NULL OR @Costo <= 0
        BEGIN
            RAISERROR('El articulo no tiene costo cargado en la lista.', 16, 1);
            RETURN;
        END

        -- El fabricante sale del rubro, entre comillas. La columna Marca
        -- de la lista es la marca del VEHICULO y no sirve para esto.
        SET @Fabricante =
            CASE WHEN CHARINDEX('"', @RubroTexto) > 0
                 THEN LTRIM(RTRIM(SUBSTRING(
                        @RubroTexto,
                        CHARINDEX('"', @RubroTexto) + 1,
                        CHARINDEX('"', @RubroTexto, CHARINDEX('"', @RubroTexto) + 1)
                            - CHARINDEX('"', @RubroTexto) - 1)))
                 ELSE NULL END;

        DECLARE @salida TABLE (Id INT, Codigo VARCHAR(40));

        INSERT INTO @salida
        EXEC SP_Repuesto_I
            @Descripcion      = @Descripcion,
            @PrecioDeVenta    = NULL,
            @IdModelo         = @IdModelo,
            @IdRubro          = @IdRubro,
            @Codigo           = @Codigo,
            @CodigoFabricante = @Articulo,
            @MarcaFabricante  = @Fabricante,
            @PrecioCompra     = @Costo,
            @PrecioNetoVenta  = @PrecioNetoVenta,
            @IdAlicuotaIva    = NULL,
            @StockMinimo      = @StockMinimo;

        DECLARE @IdNuevo INT;
        SELECT TOP 1 @IdNuevo = Id FROM @salida;

        -- La aplicacion vehicular viene dentro de la descripcion del
        -- proveedor. Se copia tal cual y queda editable: es la unica
        -- fuente realista de ese dato.
        UPDATE Repuesto SET AplicacionTexto = @DescProv WHERE Id = @IdNuevo;

        UPDATE ProveedorRepuesto SET IdRepuesto = @IdNuevo WHERE Id = @IdListaProveedor;

        SELECT Id, Codigo FROM @salida;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   4. Fix: SP_Repuesto_I con @Descripcion NULL
   IncorporarDesdeLista puede no recibir descripcion propia. En ese
   caso hay que usar la del proveedor.
   ----------------------------------------------------------------- */
-- Se resuelve en el SP de incorporacion: si no vino descripcion, se
-- usa la del proveedor recortada a 100 caracteres.
IF OBJECT_ID('SP_Repuesto_IncorporarDesdeLista', 'P') IS NOT NULL
    EXEC('
    ALTER PROCEDURE SP_Repuesto_IncorporarDesdeLista
        @IdListaProveedor INT,
        @IdModelo         INT = NULL,
        @StockMinimo      INT = 5,
        @PrecioNetoVenta  DECIMAL(12,2) = NULL,
        @Descripcion      NVARCHAR(100) = NULL
    AS
    BEGIN
        SET NOCOUNT ON;
        BEGIN TRY
            DECLARE @Codigo VARCHAR(40), @Articulo VARCHAR(40), @RubroTexto VARCHAR(120),
                    @DescProv NVARCHAR(250), @Costo DECIMAL(12,2), @IdRubro INT,
                    @IdRepuestoExistente INT, @Fabricante VARCHAR(60);

            SELECT @Codigo = pr.CodigoProveedor, @Articulo = pr.Articulo,
                   @RubroTexto = pr.RubroTexto, @DescProv = pr.Descripcion,
                   @Costo = pr.PrecioCompra, @IdRubro = pr.IdRubro,
                   @IdRepuestoExistente = pr.IdRepuesto
            FROM ProveedorRepuesto pr WHERE pr.Id = @IdListaProveedor;

            IF @Codigo IS NULL BEGIN RAISERROR(''El articulo de la lista no existe.'', 16, 1); RETURN; END
            IF @IdRepuestoExistente IS NOT NULL BEGIN RAISERROR(''Ese articulo ya esta enlazado a un repuesto de tu catalogo.'', 16, 1); RETURN; END
            IF @IdRubro IS NULL BEGIN RAISERROR(''El articulo no tiene rubro propio asignado.'', 16, 1); RETURN; END
            IF @Costo IS NULL OR @Costo <= 0 BEGIN RAISERROR(''El articulo no tiene costo cargado en la lista.'', 16, 1); RETURN; END

            IF @Descripcion IS NULL OR LTRIM(RTRIM(@Descripcion)) = ''''
                SET @Descripcion = LEFT(@DescProv, 100);

            SET @Fabricante =
                CASE WHEN CHARINDEX(''"'', @RubroTexto) > 0
                     THEN LTRIM(RTRIM(SUBSTRING(@RubroTexto,
                            CHARINDEX(''"'', @RubroTexto) + 1,
                            CHARINDEX(''"'', @RubroTexto, CHARINDEX(''"'', @RubroTexto) + 1)
                                - CHARINDEX(''"'', @RubroTexto) - 1)))
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

            SELECT Id, Codigo FROM @salida;
        END TRY
        BEGIN CATCH
            THROW;
        END CATCH
    END');
GO


/* -----------------------------------------------------------------
   5. VERIFICACION
   ----------------------------------------------------------------- */
EXEC SP_ProveedorRepuesto_Buscar @Texto = 'abrazadera', @Tope = 5, @SoloSinEnlazar = 0;

SELECT Id, Codigo, Descripcion, MarcaFabricante, AplicacionTexto,
       PrecioCompra, PrecioNetoVenta, PrecioDeVenta
FROM Repuesto ORDER BY Id;
GO
