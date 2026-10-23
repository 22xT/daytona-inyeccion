USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   Exponer CuentaCorriente en las consultas de Cliente

   La pantalla de venta necesita saber si el cliente elegido tiene
   cuenta corriente habilitada: si no la tiene, la opcion de vender
   fiado no debe ni ofrecerse. El SP de venta la rechaza igual, pero
   ofrecer algo que va a fallar es peor que no ofrecerlo.

   La columna va al FINAL, para no correr de lugar a las demas.
   ================================================================= */

ALTER PROCEDURE [dbo].[SP_Cliente_GetAll]
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Id, Dni, Nombre, Apellido, Telefono, Mail, Calle, Numero, Activo,
           EsMecanico, CuentaCorriente
    FROM Cliente
    ORDER BY Apellido, Nombre;
END
GO


ALTER PROCEDURE [dbo].[SP_Cliente_GetById]
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Id, Dni, Nombre, Apellido, Telefono, Mail, Calle, Numero, Activo,
           EsMecanico, CuentaCorriente
    FROM Cliente
    WHERE Id = @Id;
END
GO


/* -----------------------------------------------------------------
   VERIFICACION
   ----------------------------------------------------------------- */
SELECT OBJECT_NAME(object_id) AS SP,
       CASE WHEN OBJECT_DEFINITION(object_id) LIKE '%CuentaCorriente%'
            THEN 'OK' ELSE 'FALTA' END AS Estado
FROM sys.procedures
WHERE name IN ('SP_Cliente_GetAll', 'SP_Cliente_GetById');

SELECT Id, Apellido, Nombre, EsMecanico, CuentaCorriente
FROM Cliente WHERE Activo = 1;
GO
