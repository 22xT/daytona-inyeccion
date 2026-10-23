USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   SP_Repuesto_I — sin sigla, con costo y precio neto

   Cambios:
   1. Se va la generacion de SIGLA-NNNN. El codigo viene del
      proveedor por el que se incorpora el repuesto.
   2. Entran costo, precio neto, alicuota y datos del fabricante.
   3. Devuelve el Id y el Codigo generados. Antes no devolvia nada,
      y hace falta para dejar seleccionado el repuesto recien creado.

   COMPATIBILIDAD: todos los parametros nuevos tienen default, y
   @PrecioDeVenta sigue existiendo. El controller y el formulario
   actuales siguen andando sin tocar una linea.
   ================================================================= */

ALTER PROCEDURE [dbo].[SP_Repuesto_I]
    @Descripcion      NVARCHAR(100),
    @PrecioDeVenta    DECIMAL(10,2) = NULL,   -- precio FINAL con IVA (compatibilidad)
    @IdModelo         INT = NULL,
    @IdRubro          INT,
    -- nuevos
    @Codigo           VARCHAR(40)   = NULL,   -- codigo del proveedor
    @CodigoFabricante VARCHAR(40)   = NULL,   -- A0254, AC25085...
    @MarcaFabricante  VARCHAR(60)   = NULL,   -- Perfecto, Nakata...
    @PrecioCompra     DECIMAL(12,2) = NULL,
    @PrecioNetoVenta  DECIMAL(12,2) = NULL,   -- si no viene, se calcula
    @IdAlicuotaIva    INT           = NULL,
    @StockMinimo      INT           = 5
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF @Descripcion IS NULL OR LTRIM(RTRIM(@Descripcion)) = ''
            RAISERROR('La descripcion es obligatoria.', 16, 1);

        IF NOT EXISTS (SELECT 1 FROM Rubro WHERE Id = @IdRubro)
            RAISERROR('El rubro indicado no existe.', 16, 1);

        -- Duplicados: misma descripcion + rubro + modelo.
        -- Los universales (IdModelo NULL) comparan sin modelo.
        IF EXISTS (
            SELECT 1 FROM Repuesto
            WHERE Activo = 1
              AND LTRIM(RTRIM(Descripcion)) = LTRIM(RTRIM(@Descripcion))
              AND IdRubro = @IdRubro
              AND ((@IdModelo IS NULL AND IdModelo IS NULL) OR (IdModelo = @IdModelo))
        )
            RAISERROR('Ya existe un repuesto con esa descripcion en el mismo rubro.', 16, 1);

        -- Codigo repetido: mensaje claro en vez de violacion de indice
        IF @Codigo IS NOT NULL AND LTRIM(RTRIM(@Codigo)) <> ''
           AND EXISTS (SELECT 1 FROM Repuesto WHERE Codigo = LTRIM(RTRIM(@Codigo)))
            RAISERROR('Ya existe un repuesto con ese codigo.', 16, 1);

        IF @Codigo IS NOT NULL AND LTRIM(RTRIM(@Codigo)) = ''
            SET @Codigo = NULL;

        -- Alicuota: por defecto 21%
        IF @IdAlicuotaIva IS NULL
            SELECT TOP 1 @IdAlicuotaIva = Id FROM AlicuotaIva WHERE Porcentaje = 21 AND Activo = 1;

        DECLARE @alic DECIMAL(5,2);
        SELECT @alic = ISNULL(Porcentaje, 21) FROM AlicuotaIva WHERE Id = @IdAlicuotaIva;
        SET @alic = ISNULL(@alic, 21);

        /* Precio: se resuelve en este orden
           1. si vino el neto, se usa
           2. si vino el costo, se aplica el margen del rubro
           3. si vino el precio final (modo viejo), se despeja el neto */
        IF @PrecioNetoVenta IS NULL AND @PrecioCompra IS NOT NULL AND @PrecioCompra > 0
        BEGIN
            DECLARE @margen DECIMAL(6,2);
            SELECT @margen = COALESCE(
                r.MargenPorcentaje,
                TRY_CAST((SELECT Valor FROM ParametroSistema WHERE Clave = 'MargenGeneral') AS DECIMAL(6,2)),
                50.00)
            FROM Rubro r WHERE r.Id = @IdRubro;

            SET @PrecioNetoVenta = CAST(@PrecioCompra * (1 + ISNULL(@margen, 50) / 100.0) AS DECIMAL(12,2));
        END

        IF @PrecioNetoVenta IS NULL AND @PrecioDeVenta IS NOT NULL AND @PrecioDeVenta > 0
            SET @PrecioNetoVenta = CAST(@PrecioDeVenta / (1 + @alic / 100.0) AS DECIMAL(12,2));

        -- El final SIEMPRE se calcula: si se guardaran los dos por
        -- separado, tarde o temprano dejan de coincidir.
        DECLARE @final DECIMAL(10,2) = NULL;
        IF @PrecioNetoVenta IS NOT NULL
            SET @final = CAST(@PrecioNetoVenta * (1 + @alic / 100.0) AS DECIMAL(10,2));

        INSERT INTO Repuesto
            (Codigo, Descripcion, PrecioDeVenta, IdModelo, IdRubro,
             CodigoFabricante, MarcaFabricante, PrecioCompra, PrecioNetoVenta,
             IdAlicuotaIva, FechaUltimaCompra)
        VALUES
            (LTRIM(RTRIM(@Codigo)), @Descripcion, @final, @IdModelo, @IdRubro,
             NULLIF(LTRIM(RTRIM(@CodigoFabricante)), ''), NULLIF(LTRIM(RTRIM(@MarcaFabricante)), ''),
             @PrecioCompra, @PrecioNetoVenta,
             @IdAlicuotaIva,
             CASE WHEN @PrecioCompra IS NOT NULL THEN GETDATE() ELSE NULL END);

        DECLARE @IdNuevo INT = SCOPE_IDENTITY();

        -- Sin codigo del proveedor, uno propio para que sea identificable
        IF @Codigo IS NULL
        BEGIN
            SET @Codigo = 'R-' + RIGHT('000000' + CAST(@IdNuevo AS VARCHAR(6)), 6);
            UPDATE Repuesto SET Codigo = @Codigo WHERE Id = @IdNuevo;
        END

        INSERT INTO Stock (IdRepuesto, Cantidad, StockMinimo)
        VALUES (@IdNuevo, 0, ISNULL(@StockMinimo, 5));

        COMMIT TRANSACTION;

        SELECT @IdNuevo AS Id, @Codigo AS Codigo;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO


/* =================================================================
   SP_Repuesto_IncorporarDesdeLista

   Toma un articulo de la lista de un proveedor y lo da de alta en
   el catalogo propio, con el costo real y el precio sugerido.
   Ademas deja enlazada la fila de la lista con el repuesto nuevo.

   Este es el circuito completo: lista -> costo -> margen -> precio.
   ================================================================= */
IF OBJECT_ID('SP_Repuesto_IncorporarDesdeLista', 'P') IS NOT NULL
    DROP PROCEDURE SP_Repuesto_IncorporarDesdeLista;
GO

CREATE PROCEDURE SP_Repuesto_IncorporarDesdeLista
    @IdListaProveedor INT,
    @IdModelo         INT = NULL,
    @StockMinimo      INT = 5,
    @PrecioNetoVenta  DECIMAL(12,2) = NULL   -- si viene, pisa al sugerido
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @Codigo VARCHAR(40), @Articulo VARCHAR(40), @Marca VARCHAR(60),
                @Descripcion NVARCHAR(100), @Costo DECIMAL(12,2), @IdRubro INT,
                @IdRepuestoExistente INT;

        SELECT
            @Codigo      = pr.CodigoProveedor,
            @Articulo    = pr.Articulo,
            @Marca       = pr.MarcaTexto,
            @Descripcion = LEFT(pr.Descripcion, 100),
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
            RAISERROR('El articulo no tiene rubro propio asignado. Crea el rubro o asignaselo antes de incorporarlo.', 16, 1);
            RETURN;
        END

        IF @Costo IS NULL OR @Costo <= 0
        BEGIN
            RAISERROR('El articulo no tiene costo cargado en la lista.', 16, 1);
            RETURN;
        END

        -- Se reusa SP_Repuesto_I para no duplicar la logica de precios
        DECLARE @salida TABLE (Id INT, Codigo VARCHAR(40));

        INSERT INTO @salida
        EXEC SP_Repuesto_I
            @Descripcion      = @Descripcion,
            @PrecioDeVenta    = NULL,
            @IdModelo         = @IdModelo,
            @IdRubro          = @IdRubro,
            @Codigo           = @Codigo,
            @CodigoFabricante = @Articulo,
            @MarcaFabricante  = @Marca,
            @PrecioCompra     = @Costo,
            @PrecioNetoVenta  = @PrecioNetoVenta,
            @IdAlicuotaIva    = NULL,
            @StockMinimo      = @StockMinimo;

        DECLARE @IdNuevo INT;
        SELECT TOP 1 @IdNuevo = Id FROM @salida;

        -- Queda enlazado: de ahi en mas el sistema sabe a quien comprarlo
        UPDATE ProveedorRepuesto SET IdRepuesto = @IdNuevo WHERE Id = @IdListaProveedor;

        SELECT Id, Codigo FROM @salida;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   PRUEBA: incorporar la abrazadera del catalogo web
   Costo 602,15 + 50% = 903,23 neto + 21% = 1.092,91 final,
   que es exactamente el precio que muestra Autocor.
   ----------------------------------------------------------------- */
/*
DECLARE @id INT;
SELECT @id = Id FROM ProveedorRepuesto WHERE CodigoProveedor = '359V001';
EXEC SP_Repuesto_IncorporarDesdeLista @IdListaProveedor = @id;

SELECT Codigo, Descripcion, CodigoFabricante, MarcaFabricante,
       PrecioCompra, PrecioNetoVenta, PrecioDeVenta
FROM Repuesto WHERE Id = (SELECT MAX(Id) FROM Repuesto);
*/
GO
