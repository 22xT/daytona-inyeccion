USE [DaytonaInyeccion];
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   CONFIGURACION — parametros y margenes editables desde el sistema

   Hasta ahora el margen general y el descuento de mecanico se
   cambiaban con un UPDATE a mano. Son decisiones comerciales, no
   tecnicas: tienen que poder cambiarse desde la pantalla.
   ================================================================= */

/* -----------------------------------------------------------------
   1. Descripcion y tipo de cada parametro
   El tipo permite que la pantalla valide antes de guardar.
   ----------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('ParametroSistema') AND name = 'Tipo')
    ALTER TABLE ParametroSistema ADD Tipo VARCHAR(20) NOT NULL
        CONSTRAINT DF_Parametro_Tipo DEFAULT 'texto';
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('ParametroSistema') AND name = 'Editable')
    ALTER TABLE ParametroSistema ADD Editable BIT NOT NULL
        CONSTRAINT DF_Parametro_Editable DEFAULT 1;
GO

UPDATE ParametroSistema SET Tipo = 'porcentaje'
WHERE Clave IN ('MargenGeneral', 'DescuentoMecanico');
GO

-- Parametros de descuento a publico general: los tres escalones
IF NOT EXISTS (SELECT 1 FROM ParametroSistema WHERE Clave = 'DescuentosPublico')
    INSERT INTO ParametroSistema (Clave, Valor, Descripcion, Tipo)
    VALUES ('DescuentosPublico', '5,7,10',
            'Descuentos que se ofrecen al publico general, separados por coma', 'lista');
GO

IF NOT EXISTS (SELECT 1 FROM ParametroSistema WHERE Clave = 'DiasValidezPresupuesto')
    INSERT INTO ParametroSistema (Clave, Valor, Descripcion, Tipo)
    VALUES ('DiasValidezPresupuesto', '7',
            'Dias que vale un presupuesto desde que se emite', 'entero');
GO


/* -----------------------------------------------------------------
   2. SP: listar parametros
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Parametro_GetAll', 'P') IS NOT NULL DROP PROCEDURE SP_Parametro_GetAll;
GO

CREATE PROCEDURE SP_Parametro_GetAll
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Clave, Valor, Descripcion, Tipo, Editable
    FROM ParametroSistema
    ORDER BY Clave;
END
GO


/* -----------------------------------------------------------------
   3. SP: modificar un parametro
   Valida segun el tipo. Un margen de 5000% o negativo no entra.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Parametro_U', 'P') IS NOT NULL DROP PROCEDURE SP_Parametro_U;
GO

CREATE PROCEDURE SP_Parametro_U
    @Clave VARCHAR(50),
    @Valor VARCHAR(200)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @tipo VARCHAR(20), @editable BIT;
    SELECT @tipo = Tipo, @editable = Editable
    FROM ParametroSistema WHERE Clave = @Clave;

    IF @tipo IS NULL
    BEGIN
        RAISERROR('El parametro indicado no existe.', 16, 1);
        RETURN;
    END

    IF @editable = 0
    BEGIN
        RAISERROR('Ese parametro no se puede modificar desde el sistema.', 16, 1);
        RETURN;
    END

    SET @Valor = LTRIM(RTRIM(ISNULL(@Valor, '')));

    IF @tipo = 'porcentaje'
    BEGIN
        DECLARE @n DECIMAL(10,2) = TRY_CAST(@Valor AS DECIMAL(10,2));
        IF @n IS NULL
        BEGIN
            RAISERROR('El valor tiene que ser un numero.', 16, 1);
            RETURN;
        END
        IF @n < 0 OR @n > 500
        BEGIN
            RAISERROR('El porcentaje tiene que estar entre 0 y 500.', 16, 1);
            RETURN;
        END
    END

    IF @tipo = 'entero'
    BEGIN
        IF TRY_CAST(@Valor AS INT) IS NULL
        BEGIN
            RAISERROR('El valor tiene que ser un numero entero.', 16, 1);
            RETURN;
        END
    END

    IF @tipo = 'lista'
    BEGIN
        IF @Valor LIKE '%[^0-9,. ]%'
        BEGIN
            RAISERROR('La lista solo puede tener numeros separados por coma.', 16, 1);
            RETURN;
        END
    END

    UPDATE ParametroSistema SET Valor = @Valor WHERE Clave = @Clave;
END
GO


/* -----------------------------------------------------------------
   4. SP: rubros con margen propio
   Devuelve solo las EXCEPCIONES, que en la practica son pocas.
   Los que no estan usan el general.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Rubro_GetMargenes', 'P') IS NOT NULL DROP PROCEDURE SP_Rubro_GetMargenes;
GO

CREATE PROCEDURE SP_Rubro_GetMargenes
    @SoloConMargen BIT = 1,
    @Texto         VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT r.Id, r.Nombre, r.MargenPorcentaje,
           (SELECT COUNT(*) FROM Repuesto rp WHERE rp.IdRubro = r.Id AND rp.Activo = 1) AS Repuestos
    FROM Rubro r
    WHERE (@SoloConMargen = 0 OR r.MargenPorcentaje IS NOT NULL)
      AND (@Texto IS NULL OR @Texto = '' OR r.Nombre LIKE '%' + @Texto + '%')
    ORDER BY
        CASE WHEN r.MargenPorcentaje IS NULL THEN 1 ELSE 0 END,
        r.Nombre;
END
GO


/* -----------------------------------------------------------------
   5. SP: fijar o quitar el margen de un rubro
   @Margen NULL borra la excepcion y el rubro vuelve al general.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Rubro_SetMargen', 'P') IS NOT NULL DROP PROCEDURE SP_Rubro_SetMargen;
GO

CREATE PROCEDURE SP_Rubro_SetMargen
    @IdRubro INT,
    @Margen  DECIMAL(6,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM Rubro WHERE Id = @IdRubro)
    BEGIN
        RAISERROR('El rubro indicado no existe.', 16, 1);
        RETURN;
    END

    IF @Margen IS NOT NULL AND (@Margen < 0 OR @Margen > 500)
    BEGIN
        RAISERROR('El margen tiene que estar entre 0 y 500.', 16, 1);
        RETURN;
    END

    UPDATE Rubro SET MargenPorcentaje = @Margen WHERE Id = @IdRubro;
END
GO


/* -----------------------------------------------------------------
   6. Aplicar lo que ya sabemos del negocio
   ----------------------------------------------------------------- */
EXEC SP_Parametro_U @Clave = 'MargenGeneral', @Valor = '50';
GO

-- Amortiguadores Nakata al 35%, si el rubro existe
DECLARE @idNakata INT;
SELECT TOP 1 @idNakata = Id FROM Rubro WHERE Nombre LIKE '%AMORTIGUADORES%NAKATA%';
IF @idNakata IS NOT NULL
    EXEC SP_Rubro_SetMargen @IdRubro = @idNakata, @Margen = 35;
GO


/* -----------------------------------------------------------------
   7. VERIFICACION
   ----------------------------------------------------------------- */
EXEC SP_Parametro_GetAll;
EXEC SP_Rubro_GetMargenes @SoloConMargen = 1;
GO
