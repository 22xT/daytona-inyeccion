USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   SP_Repuesto_U — neto y final siempre coherentes

   Problema del SP viejo: escribia PrecioDeVenta directo. Al editar,
   el precio final cambiaba y PrecioNetoVenta quedaba con el valor
   anterior. Desde ese momento el margen que muestra el sistema es
   falso, porque se calcula sobre un neto que ya no corresponde.

   Ahora el final SIEMPRE se recalcula desde el neto.

   COMPATIBILIDAD: los parametros nuevos tienen default y
   @PrecioDeVenta sigue funcionando como antes. El controller y el
   formulario actuales no necesitan cambios.
   ================================================================= */

ALTER PROCEDURE [dbo].[SP_Repuesto_U]
    @Id               INT,
    @Descripcion      NVARCHAR(100),
    @PrecioDeVenta    DECIMAL(10,2) = NULL,   -- final con IVA (compatibilidad)
    @IdModelo         INT = NULL,
    @IdRubro          INT,
    -- nuevos
    @Codigo           VARCHAR(40)   = NULL,
    @CodigoFabricante VARCHAR(40)   = NULL,
    @MarcaFabricante  VARCHAR(60)   = NULL,
    @PrecioCompra     DECIMAL(12,2) = NULL,
    @PrecioNetoVenta  DECIMAL(12,2) = NULL,
    @IdAlicuotaIva    INT           = NULL,
    -- true = los NULL borran el valor; false = los NULL dejan lo que habia
    @PisarNulos       BIT           = 0
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM Repuesto WHERE Id = @Id)
            RAISERROR('El repuesto indicado no existe.', 16, 1);

        IF @Descripcion IS NULL OR LTRIM(RTRIM(@Descripcion)) = ''
            RAISERROR('La descripcion es obligatoria.', 16, 1);

        IF NOT EXISTS (SELECT 1 FROM Rubro WHERE Id = @IdRubro)
            RAISERROR('El rubro indicado no existe.', 16, 1);

        -- Duplicados: otro repuesto con misma descripcion + rubro + modelo
        IF EXISTS (
            SELECT 1 FROM Repuesto
            WHERE Activo = 1
              AND Id <> @Id
              AND LTRIM(RTRIM(Descripcion)) = LTRIM(RTRIM(@Descripcion))
              AND IdRubro = @IdRubro
              AND ((@IdModelo IS NULL AND IdModelo IS NULL) OR (IdModelo = @IdModelo))
        )
            RAISERROR('Ya existe otro repuesto con esa descripcion en el mismo rubro.', 16, 1);

        -- Codigo repetido en OTRO repuesto
        IF @Codigo IS NOT NULL AND LTRIM(RTRIM(@Codigo)) <> ''
           AND EXISTS (SELECT 1 FROM Repuesto WHERE Codigo = LTRIM(RTRIM(@Codigo)) AND Id <> @Id)
            RAISERROR('Ya existe otro repuesto con ese codigo.', 16, 1);

        /* Se toma lo que habia como punto de partida. Asi una pantalla
           que solo manda descripcion y precio no borra el costo ni el
           codigo de fabricante que cargo otra pantalla. */
        DECLARE @actCodigo VARCHAR(40), @actCodFab VARCHAR(40), @actMarcaFab VARCHAR(60),
                @actCompra DECIMAL(12,2), @actNeto DECIMAL(12,2), @actAlic INT;

        SELECT @actCodigo    = Codigo,
               @actCodFab    = CodigoFabricante,
               @actMarcaFab  = MarcaFabricante,
               @actCompra    = PrecioCompra,
               @actNeto      = PrecioNetoVenta,
               @actAlic      = IdAlicuotaIva
        FROM Repuesto WHERE Id = @Id;

        IF @PisarNulos = 0
        BEGIN
            SET @Codigo           = COALESCE(NULLIF(LTRIM(RTRIM(@Codigo)), ''), @actCodigo);
            SET @CodigoFabricante = COALESCE(NULLIF(LTRIM(RTRIM(@CodigoFabricante)), ''), @actCodFab);
            SET @MarcaFabricante  = COALESCE(NULLIF(LTRIM(RTRIM(@MarcaFabricante)), ''), @actMarcaFab);
            SET @PrecioCompra     = COALESCE(@PrecioCompra, @actCompra);
            SET @IdAlicuotaIva    = COALESCE(@IdAlicuotaIva, @actAlic);
        END

        -- Alicuota: la que venga, la que tenia, o 21%
        IF @IdAlicuotaIva IS NULL
            SELECT TOP 1 @IdAlicuotaIva = Id FROM AlicuotaIva WHERE Porcentaje = 21 AND Activo = 1;

        DECLARE @alic DECIMAL(5,2);
        SELECT @alic = Porcentaje FROM AlicuotaIva WHERE Id = @IdAlicuotaIva;
        SET @alic = ISNULL(@alic, 21);

        /* Precio, en orden:
           1. si vino el neto, se usa
           2. si vino el final (modo viejo), se despeja el neto
           3. si no vino ninguno, queda el que tenia */
        IF @PrecioNetoVenta IS NULL AND @PrecioDeVenta IS NOT NULL AND @PrecioDeVenta > 0
            SET @PrecioNetoVenta = CAST(@PrecioDeVenta / (1 + @alic / 100.0) AS DECIMAL(12,2));

        IF @PrecioNetoVenta IS NULL
            SET @PrecioNetoVenta = @actNeto;

        -- El final NUNCA se guarda como vino: se recalcula
        DECLARE @final DECIMAL(10,2) = NULL;
        IF @PrecioNetoVenta IS NOT NULL
            SET @final = CAST(@PrecioNetoVenta * (1 + @alic / 100.0) AS DECIMAL(10,2));

        UPDATE Repuesto
        SET Descripcion       = @Descripcion,
            IdModelo          = @IdModelo,
            IdRubro           = @IdRubro,
            Codigo            = NULLIF(LTRIM(RTRIM(@Codigo)), ''),
            CodigoFabricante  = NULLIF(LTRIM(RTRIM(@CodigoFabricante)), ''),
            MarcaFabricante   = NULLIF(LTRIM(RTRIM(@MarcaFabricante)), ''),
            PrecioCompra      = @PrecioCompra,
            PrecioNetoVenta   = @PrecioNetoVenta,
            PrecioDeVenta     = @final,
            IdAlicuotaIva     = @IdAlicuotaIva,
            -- Si cambio el costo, queda registrado cuando
            FechaUltimaCompra = CASE WHEN @PrecioCompra IS NOT NULL
                                      AND ISNULL(@actCompra, -1) <> @PrecioCompra
                                     THEN GETDATE() ELSE FechaUltimaCompra END
        WHERE Id = @Id;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   PRUEBA: editar sin mandar los campos nuevos no debe borrar nada
   ----------------------------------------------------------------- */
/*
-- Estado antes
SELECT Id, Codigo, Descripcion, CodigoFabricante, PrecioCompra,
       PrecioNetoVenta, PrecioDeVenta
FROM Repuesto WHERE Id = 1;

-- Llamada al estilo viejo, solo con los 5 parametros originales
EXEC SP_Repuesto_U @Id = 1, @Descripcion = 'Prueba edicion',
                   @PrecioDeVenta = 2000, @IdModelo = NULL, @IdRubro = 1;

-- CodigoFabricante y PrecioCompra tienen que seguir ahi,
-- y PrecioNetoVenta tiene que dar 2000 / 1,21 = 1652,89
SELECT Id, Codigo, Descripcion, CodigoFabricante, PrecioCompra,
       PrecioNetoVenta, PrecioDeVenta
FROM Repuesto WHERE Id = 1;
*/
GO
