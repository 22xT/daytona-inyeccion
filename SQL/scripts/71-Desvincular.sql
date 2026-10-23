USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   71 — DESVINCULAR UN ARTICULO DE PROVEEDOR

   Vincular se podia; deshacerlo no. Si se vinculo por error un
   articulo que no es el mismo (otra marca, otro kit), quedaba
   comparando precios y sumando a pedidos como si lo fuera.

   Desvincular solo corta el enlace: el articulo vuelve a ser una
   oferta suelta de la lista del proveedor y tu repuesto sigue igual
   (stock, precio y ventas no se tocan). Los pedidos ya hechos no
   cambian.
   ================================================================= */

IF OBJECT_ID('SP_ProveedorRepuesto_Desvincular', 'P') IS NOT NULL DROP PROCEDURE SP_ProveedorRepuesto_Desvincular;
GO
CREATE PROCEDURE SP_ProveedorRepuesto_Desvincular
    @IdListaProveedor INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM ProveedorRepuesto WHERE Id = @IdListaProveedor)
        THROW 50130, 'El articulo de la lista no existe.', 1;

    IF EXISTS (SELECT 1 FROM ProveedorRepuesto WHERE Id = @IdListaProveedor AND IdRepuesto IS NULL)
        THROW 50131, 'Ese articulo no esta vinculado a ningun repuesto.', 1;

    UPDATE ProveedorRepuesto SET IdRepuesto = NULL WHERE Id = @IdListaProveedor;

    SELECT @IdListaProveedor AS Id;
END
GO
