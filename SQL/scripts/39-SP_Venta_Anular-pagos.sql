USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   39 — SP_Venta_Anular CON FORMAS DE PAGO

   Ademas de stock, caja y cuenta corriente, revierte los movimientos
   de banco y Mercado Pago que la venta genero. Se registra el inverso
   por el neto de cada cuenta; nada se borra.

   Requiere los scripts 37 y 38.
   ================================================================= */

ALTER PROCEDURE [dbo].[SP_Venta_Anular]
    @Id        INT,
    @IdUsuario INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @EstadoActual INT, @IdCliente INT, @Total DECIMAL(12,2);

        SELECT @EstadoActual = IdEstadoVenta,
               @IdCliente    = IdCliente,
               @Total        = Total
        FROM Venta WHERE Id = @Id;

        IF @EstadoActual IS NULL
            RAISERROR('La venta no existe.', 16, 1);

        IF @EstadoActual = 2
            RAISERROR('La venta ya estaba anulada.', 16, 1);

        IF NOT EXISTS (SELECT 1 FROM Usuario WHERE Id = @IdUsuario)
            RAISERROR('El usuario indicado no existe.', 16, 1);

        /* ---------- 1. Stock ---------- */

        UPDATE s
        SET s.Cantidad            = s.Cantidad + dv.Cantidad,
            s.UltimaActualizacion = GETDATE()
        FROM Stock s
        INNER JOIN DetalleVenta dv ON dv.IdRepuesto = s.IdRepuesto
        WHERE dv.IdVenta = @Id;

        /* ---------- 2. Caja ----------
           Se devuelve lo que efectivamente entro por esta venta, que
           no siempre es el total: en una venta fiada con entrega
           parcial entro solo la entrega, y en una fiada sin entrega
           no entro nada. */

        DECLARE @IngresadoCaja DECIMAL(12,2);

        SELECT @IngresadoCaja = ISNULL(SUM(
                    CASE WHEN Tipo = 'Ingreso' THEN Monto ELSE -Monto END), 0)
        FROM MovimientoCaja
        WHERE IdVenta = @Id;

        IF @IngresadoCaja > 0
        BEGIN
            DECLARE @DescCaja NVARCHAR(250) =
                'Devolucion por anulacion de venta #' + CAST(@Id AS NVARCHAR(10));

            EXEC SP_MovimientoCaja_RegistrarInterno
                @Tipo        = 'Egreso',
                @Concepto    = 'Anulacion de venta',
                @Monto       = @IngresadoCaja,
                @Descripcion = @DescCaja,
                @IdUsuario   = @IdUsuario,
                @IdVenta     = @Id,
                @IdPedido    = NULL;
        END

        /* ---------- 2b. Banco y Mercado Pago ----------
           Cada cuenta se revierte por su neto: lo que entro menos la
           comision que ya se registro como egreso. Igual que la caja,
           se registra el inverso, no se borra. */

        DECLARE @cta INT, @netoCta DECIMAL(12,2);
        DECLARE curCta CURSOR LOCAL FAST_FORWARD FOR
            SELECT IdCuentaFinanciera,
                   SUM(CASE WHEN Tipo = 'Ingreso' THEN Monto ELSE -Monto END)
            FROM MovimientoCuentaFinanciera
            WHERE IdVenta = @Id
            GROUP BY IdCuentaFinanciera
            HAVING SUM(CASE WHEN Tipo = 'Ingreso' THEN Monto ELSE -Monto END) <> 0;

        OPEN curCta;
        FETCH NEXT FROM curCta INTO @cta, @netoCta;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            INSERT INTO MovimientoCuentaFinanciera
                (IdCuentaFinanciera, Tipo, Concepto, Monto, Descripcion, IdUsuario, IdVenta)
            VALUES
                (@cta,
                 CASE WHEN @netoCta > 0 THEN 'Egreso' ELSE 'Ingreso' END,
                 'Anulacion de venta',
                 ABS(@netoCta),
                 'Devolucion por anulacion de venta #' + CAST(@Id AS NVARCHAR(10)),
                 @IdUsuario, @Id);
            FETCH NEXT FROM curCta INTO @cta, @netoCta;
        END
        CLOSE curCta; DEALLOCATE curCta;

        /* ---------- 3. Cuenta corriente ----------
           Se suma lo que esta venta dejo en el libro y se registra el
           inverso como nota de credito. En una venta fiada de $9.000
           con entrega de $1.000 el neto fue $8.000: se acredita eso.

           Los movimientos originales NO se borran. El libro tiene que
           poder explicar que paso: hubo una venta, hubo una entrega y
           despues se anulo. Borrarlos dejaria un saldo correcto con
           una historia incompleta. */

        DECLARE @NetoCtaCte DECIMAL(12,2);

        SELECT @NetoCtaCte = ISNULL(SUM(Monto), 0)
        FROM MovimientoCuentaCorriente
        WHERE IdVenta = @Id;

        IF @NetoCtaCte <> 0
            INSERT INTO MovimientoCuentaCorriente
                (IdCliente, Tipo, Concepto, Monto, IdVenta, IdUsuario, Observaciones)
            VALUES
                (@IdCliente, 'NotaCredito',
                 'Anulacion de venta #' + CAST(@Id AS VARCHAR(10)),
                 -@NetoCtaCte, @Id, @IdUsuario,
                 'Reversion automatica por anulacion');

        /* ---------- 4. Cabecera ---------- */

        UPDATE Venta
        SET IdEstadoVenta      = 2,
            IdUsuarioAnulacion = @IdUsuario,
            FechaAnulacion     = GETDATE()
        WHERE Id = @Id;

        COMMIT TRANSACTION;

        SELECT @Id            AS IdVenta,
               @Total         AS TotalAnulado,
               @IngresadoCaja AS DevueltoDeCaja,
               @NetoCtaCte    AS SaldoCancelado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
