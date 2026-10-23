USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   SP_Venta_Anular — reversion completa

   Antes solo devolvia el stock. La plata quedaba mal registrada:

   - El ingreso de caja seguia ahi, asi que la caja informaba dinero
     que ya no correspondia a ninguna venta valida.
   - En una venta fiada, la deuda del cliente quedaba viva despues de
     anulada la operacion.

   CRITERIO: no se recalcula nada. Se REVIERTE exactamente lo que la
   venta genero, consultandolo. Si la venta fue de contado, se
   devuelve lo que entro; si fue fiada con entrega parcial, se
   devuelve solo la entrega y se cancela el saldo que habia generado.

   Recalcular a partir del total daria mal en las ventas con entrega
   parcial y en cualquier caso donde los importes hayan cambiado.
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


/* -----------------------------------------------------------------
   VERIFICACION IMPORTANTE ANTES DE USAR

   SP_MovimientoCaja_RegistrarInterno puede estar validando saldo
   suficiente antes de registrar un egreso. Si es asi, anular una
   venta cuando la caja no tiene fondos va a fallar.

   Ver si el SP tiene esa validacion:
   ----------------------------------------------------------------- */
SELECT OBJECT_DEFINITION(OBJECT_ID('SP_MovimientoCaja_RegistrarInterno')) AS Definicion;
GO

/* Si valida saldo, hay que decidir:
     a) permitir que la devolucion deje la caja en negativo, porque
        la anulacion refleja un hecho que ya ocurrio;
     b) exigir que haya fondos, y que el usuario haga primero un
        ingreso manual.
   La opcion (a) es la habitual: el sistema registra la realidad,
   no la impide. */


/* -----------------------------------------------------------------
   PRUEBAS
   ----------------------------------------------------------------- */
/*
-- Estado antes
SELECT Id, Total, IdEstadoVenta FROM Venta WHERE Id = <IdVenta>;
SELECT Tipo, Concepto, Monto FROM MovimientoCaja WHERE IdVenta = <IdVenta>;
SELECT Tipo, Concepto, Monto FROM MovimientoCuentaCorriente WHERE IdVenta = <IdVenta>;

EXEC SP_Venta_Anular @Id = <IdVenta>, @IdUsuario = 1;

-- Despues: el stock volvio, hay un egreso por lo que habia entrado,
-- y una nota de credito que cancela el saldo generado.
SELECT Tipo, Concepto, Monto FROM MovimientoCaja WHERE IdVenta = <IdVenta>;
SELECT Tipo, Concepto, Monto FROM MovimientoCuentaCorriente WHERE IdVenta = <IdVenta>;

-- El saldo del cliente tiene que quedar como antes de la venta
EXEC SP_CuentaCorriente_GetSaldo @IdCliente = <IdCliente>;
*/
GO
