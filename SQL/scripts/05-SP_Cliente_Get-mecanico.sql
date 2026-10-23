USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   SP_Cliente_GetAll / SP_Cliente_GetById — exponer EsMecanico

   La columna va al FINAL de la lista, no en el medio: si alguna
   pantalla leyera por posición en vez de por nombre, agregarla al
   final no corre nada de lugar.
   ================================================================= */

ALTER PROCEDURE [dbo].[SP_Cliente_GetAll]
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Id, Dni, Nombre, Apellido, Telefono, Mail, Calle, Numero, Activo, EsMecanico
    FROM Cliente
    ORDER BY Apellido, Nombre;
END
GO


ALTER PROCEDURE [dbo].[SP_Cliente_GetById]
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Id, Dni, Nombre, Apellido, Telefono, Mail, Calle, Numero, Activo, EsMecanico
    FROM Cliente
    WHERE Id = @Id;
END
GO


/* -----------------------------------------------------------------
   VERIFICACIÓN — los dos tienen que decir OK
   ----------------------------------------------------------------- */
SELECT OBJECT_NAME(object_id) AS Procedimiento,
       CASE WHEN OBJECT_DEFINITION(object_id) LIKE '%EsMecanico%'
            THEN 'OK' ELSE 'FALTA' END AS Estado
FROM sys.procedures
WHERE name IN ('SP_Cliente_GetAll', 'SP_Cliente_GetById');
GO

-- Y que la columna llegue con datos
SELECT TOP 5 Id, Apellido, Nombre, Dni, Telefono, EsMecanico FROM Cliente ORDER BY Id DESC;
GO
