USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   48 — SALDO INICIAL DE PROVEEDORES, COMPROBANTE POR COMPROBANTE

   Lo que ya se le debia a cada proveedor antes de usar el sistema se
   carga con el resumen de cuenta que manda el proveedor: un renglon
   por comprobante pendiente, con su fecha. Asi cada uno vence cuando
   corresponde. Un solo ajuste por el total haria vencer todo junto.

   Se carga lo PENDIENTE de cada comprobante (lo que el proveedor ya
   desconto por pagos parciales no se vuelve a cargar). Las notas de
   credito van con importe negativo.

   Tambien: algunos proveedores (TAC) no facturan, entregan
   presupuestos. Se agrega Presupuesto como tipo de comprobante.
   ================================================================= */

IF TYPE_ID('SaldoInicialType') IS NULL
    CREATE TYPE SaldoInicialType AS TABLE (
        Fecha       DATE           NOT NULL,
        Comprobante NVARCHAR(80)   NOT NULL,
        Importe     DECIMAL(12,2)  NOT NULL   -- positivo: deuda; negativo: nota de credito
    );
GO

IF OBJECT_ID('SP_CtaCteProveedor_SaldoInicial', 'P') IS NOT NULL DROP PROCEDURE SP_CtaCteProveedor_SaldoInicial;
GO
CREATE PROCEDURE SP_CtaCteProveedor_SaldoInicial
    @IdProveedor INT,
    @Lineas      SaldoInicialType READONLY,
    @IdUsuario   INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM @Lineas)
            RAISERROR('No hay comprobantes para cargar.', 16, 1);
        IF EXISTS (SELECT 1 FROM @Lineas WHERE Importe = 0)
            RAISERROR('Hay comprobantes con importe cero.', 16, 1);
        IF EXISTS (SELECT 1 FROM @Lineas WHERE Fecha > CAST(GETDATE() AS DATE))
            RAISERROR('Hay comprobantes con fecha futura.', 16, 1);
        IF NOT EXISTS (SELECT 1 FROM Proveedor WHERE Id = @IdProveedor)
            RAISERROR('El proveedor no existe.', 16, 1);

        -- Un mismo comprobante no se carga dos veces como saldo inicial
        IF EXISTS (SELECT 1 FROM @Lineas l INNER JOIN MovimientoCtaCteProveedor m
                     ON m.IdProveedor = @IdProveedor AND m.Tipo = 'AJUSTE'
                    AND m.Descripcion = 'Saldo inicial · ' + LTRIM(RTRIM(l.Comprobante)))
            RAISERROR('Alguno de esos comprobantes ya está cargado como saldo inicial.', 16, 1);

        BEGIN TRANSACTION;

        -- La fecha del movimiento es la del comprobante: de ahi sale el vencimiento
        INSERT INTO MovimientoCtaCteProveedor (IdProveedor, Fecha, Tipo, Monto, Descripcion, IdUsuario)
        SELECT @IdProveedor, CAST(l.Fecha AS DATETIME), 'AJUSTE', l.Importe,
               'Saldo inicial · ' + LTRIM(RTRIM(l.Comprobante)), @IdUsuario
        FROM @Lineas l
        ORDER BY l.Fecha;

        COMMIT;
        SELECT COUNT(*) AS Cargados, SUM(Importe) AS Total FROM @Lineas;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO
