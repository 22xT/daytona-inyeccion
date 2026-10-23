USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   SP_Cliente_I / SP_Cliente_U — agregar EsMecanico

   @EsMecanico va con DEFAULT 0 para que cualquier llamada vieja que
   no lo mande siga funcionando igual que antes.

   SP_Cliente_I ahora devuelve el Id generado. Hace falta para dar de
   alta un mecanico desde el mostrador y dejarlo seleccionado en la
   venta sin ir a buscarlo a la lista. Los llamadores que usan
   ExecuteNonQuery lo ignoran sin romperse.
   ================================================================= */

ALTER PROCEDURE [dbo].[SP_Cliente_I]
    @Dni        VARCHAR(8),
    @Nombre     VARCHAR(50),
    @Apellido   VARCHAR(50),
    @Telefono   VARCHAR(30),
    @Mail       VARCHAR(100),
    @Calle      VARCHAR(100),
    @Numero     VARCHAR(15),
    @EsMecanico BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    -- El teléfono es lo único con lo que se ubica a un mecánico sin DNI
    IF @EsMecanico = 1 AND (@Telefono IS NULL OR LTRIM(RTRIM(@Telefono)) = '')
    BEGIN
        RAISERROR('El teléfono es obligatorio para un mecánico.', 16, 1);
        RETURN;
    END

    -- '' no es NULL: dos cadenas vacías chocarían contra UX_Cliente_Dni
    IF @Dni IS NOT NULL AND LTRIM(RTRIM(@Dni)) = ''
        SET @Dni = NULL;

    INSERT INTO Cliente (Dni, Nombre, Apellido, Telefono, Mail, Calle, Numero, EsMecanico)
    VALUES (@Dni, @Nombre, @Apellido, @Telefono, @Mail, @Calle, @Numero, @EsMecanico);

    SELECT CAST(SCOPE_IDENTITY() AS INT) AS Id;
END
GO


ALTER PROCEDURE [dbo].[SP_Cliente_U]
    @Id         INT,
    @Dni        VARCHAR(8),
    @Nombre     VARCHAR(50),
    @Apellido   VARCHAR(50),
    @Telefono   VARCHAR(30),
    @Mail       VARCHAR(100),
    @Calle      VARCHAR(100),
    @Numero     VARCHAR(15),
    @EsMecanico BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @EsMecanico = 1 AND (@Telefono IS NULL OR LTRIM(RTRIM(@Telefono)) = '')
    BEGIN
        RAISERROR('El teléfono es obligatorio para un mecánico.', 16, 1);
        RETURN;
    END

    IF @Dni IS NOT NULL AND LTRIM(RTRIM(@Dni)) = ''
        SET @Dni = NULL;

    UPDATE Cliente
    SET Dni        = @Dni,
        Nombre     = @Nombre,
        Apellido   = @Apellido,
        Telefono   = @Telefono,
        Mail       = @Mail,
        Calle      = @Calle,
        Numero     = @Numero,
        EsMecanico = @EsMecanico
    WHERE Id = @Id;
END
GO


/* -----------------------------------------------------------------
   VERIFICACIÓN: que SP_Cliente_GetAll y SP_Cliente_GetById
   devuelvan EsMecanico.

   Si usan SELECT * ya lo traen solo. Si listan las columnas a mano,
   hay que agregar EsMecanico o el checkbox del formulario nunca se
   va a ver tildado al editar.
   ----------------------------------------------------------------- */
SELECT OBJECT_NAME(object_id) AS Procedimiento,
       CASE WHEN OBJECT_DEFINITION(object_id) LIKE '%EsMecanico%' THEN 'OK'
            WHEN OBJECT_DEFINITION(object_id) LIKE '%SELECT%*%'   THEN 'Usa SELECT *, deberia traerlo'
            ELSE 'FALTA: agregar EsMecanico al SELECT' END AS Estado
FROM sys.procedures
WHERE name IN ('SP_Cliente_GetAll', 'SP_Cliente_GetById');
GO
