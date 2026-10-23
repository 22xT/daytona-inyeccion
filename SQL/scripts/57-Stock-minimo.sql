USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   57 — CAMBIAR EL STOCK MINIMO
   No habia ninguna pantalla para hacerlo: quedaba en 5 al crear el
   repuesto. La reposicion sugerida depende entera de este numero.
   ================================================================= */
IF OBJECT_ID('SP_Stock_SetMinimo', 'P') IS NOT NULL DROP PROCEDURE SP_Stock_SetMinimo;
GO
CREATE PROCEDURE SP_Stock_SetMinimo @IdRepuesto INT, @StockMinimo INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @StockMinimo IS NULL OR @StockMinimo < 0 OR @StockMinimo > 9999
            RAISERROR('El stock mínimo tiene que estar entre 0 y 9999.', 16, 1);
        IF NOT EXISTS (SELECT 1 FROM Repuesto WHERE Id = @IdRepuesto)
            RAISERROR('El repuesto no existe.', 16, 1);

        IF EXISTS (SELECT 1 FROM Stock WHERE IdRepuesto = @IdRepuesto)
            UPDATE Stock SET StockMinimo = @StockMinimo, UltimaActualizacion = GETDATE() WHERE IdRepuesto = @IdRepuesto;
        ELSE
            INSERT INTO Stock (IdRepuesto, Cantidad, StockMinimo, UltimaActualizacion) VALUES (@IdRepuesto, 0, @StockMinimo, GETDATE());
    END TRY
    BEGIN CATCH THROW; END CATCH
END
GO
