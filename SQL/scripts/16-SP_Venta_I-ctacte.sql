USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   SP_Venta_I — descuento, forma de pago y cuenta corriente

   Cambios respecto de la version anterior:

   1. DESCUENTO. Recibe el porcentaje y guarda tambien el importe.
      Se guardan los dos para que reimprimir un comprobante viejo
      de exactamente lo mismo, sin depender de redondeos.

   2. FORMA DE PAGO. Una venta a credito NO ingresa a caja.
      Antes toda venta registraba un ingreso automatico por el total;
      en una venta fiada eso informaba plata que no entro y el arqueo
      nunca cerraba.

   3. ENTREGA PARCIAL. El caso "te dejo veinte mil y el resto
      anotalo" no necesita un concepto nuevo: es una venta a cuenta
      corriente mas un pago inmediato. La entrega si entra a caja.

   4. COSTO HISTORICO. Guarda en DetalleVenta.CostoUnitario el costo
      vigente al momento de la venta. Sin eso, la rentabilidad de una
      venta vieja se calcularia con el costo de hoy, que ya cambio.

   5. NETO E IVA discriminados, calculados por renglon segun la
      alicuota de cada repuesto.

   6. NOMBRE Y TELEFONO sueltos, para ventas de mostrador sin cliente
      registrado.

   COMPATIBILIDAD: todos los parametros nuevos tienen default. Una
   llamada con los tres parametros originales se comporta igual que
   antes: contado, sin descuento.
   ================================================================= */

ALTER PROCEDURE [dbo].[SP_Venta_I]
    @IdCliente           INT,
    @IdUsuario           INT,
    @Detalle             DetalleVentaType READONLY,
    -- nuevos
    @PorcentajeDescuento DECIMAL(6,2)  = 0,
    @FormaPago           VARCHAR(20)   = 'Contado',   -- 'Contado' | 'CuentaCorriente'
    @Entrega             DECIMAL(12,2) = NULL,        -- parte que paga en el momento
    @NombreOcasional     NVARCHAR(80)  = NULL,
    @TelefonoOcasional   NVARCHAR(30)  = NULL,
    @TipoCliente         NVARCHAR(20)  = NULL         -- 'Publico' | 'Mecanico'
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        /* ---------- Validaciones de cabecera ---------- */

        IF NOT EXISTS (SELECT 1 FROM @Detalle)
            RAISERROR('La venta debe tener al menos un repuesto.', 16, 1);

        IF EXISTS (SELECT IdRepuesto FROM @Detalle GROUP BY IdRepuesto HAVING COUNT(*) > 1)
            RAISERROR('Hay un repuesto repetido en el detalle de la venta.', 16, 1);

        IF @PorcentajeDescuento IS NULL SET @PorcentajeDescuento = 0;

        IF @PorcentajeDescuento < 0 OR @PorcentajeDescuento > 100
            RAISERROR('El descuento debe estar entre 0 y 100.', 16, 1);

        IF @FormaPago IS NULL OR @FormaPago = '' SET @FormaPago = 'Contado';

        IF @FormaPago NOT IN ('Contado', 'CuentaCorriente')
            RAISERROR('La forma de pago debe ser Contado o CuentaCorriente.', 16, 1);

        /* ---------- Stock ----------
           UPDLOCK + HOLDLOCK: sin eso, dos ventas simultaneas del
           ultimo ejemplar pasan ambas la validacion y el stock queda
           en negativo. */

        DECLARE @SinFilaStock NVARCHAR(200);
        SELECT TOP 1 @SinFilaStock = r.Descripcion
        FROM @Detalle d
        INNER JOIN Repuesto r ON r.Id = d.IdRepuesto
        LEFT JOIN Stock s WITH (UPDLOCK, HOLDLOCK) ON s.IdRepuesto = d.IdRepuesto
        WHERE s.IdRepuesto IS NULL;

        IF @SinFilaStock IS NOT NULL
            RAISERROR('El repuesto "%s" no tiene stock inicializado. Registralo con un ajuste de stock antes de venderlo.', 16, 1, @SinFilaStock);

        DECLARE @RepuestoSinStock NVARCHAR(200), @Disponible INT;
        SELECT TOP 1
            @RepuestoSinStock = r.Descripcion,
            @Disponible = s.Cantidad
        FROM @Detalle d
        INNER JOIN Repuesto r ON r.Id = d.IdRepuesto
        INNER JOIN Stock s WITH (UPDLOCK, HOLDLOCK) ON s.IdRepuesto = d.IdRepuesto
        WHERE s.Cantidad < d.Cantidad;

        IF @RepuestoSinStock IS NOT NULL
            RAISERROR('Stock insuficiente para "%s". Disponible: %d.', 16, 1, @RepuestoSinStock, @Disponible);

        /* ---------- Importes ---------- */

        DECLARE @Subtotal DECIMAL(12,2), @Descuento DECIMAL(12,2), @Total DECIMAL(12,2);

        SELECT @Subtotal = SUM(CAST(Cantidad AS DECIMAL(12,2)) * PrecioUnitario)
        FROM @Detalle;

        IF @Subtotal IS NULL OR @Subtotal <= 0
            RAISERROR('El total de la venta debe ser mayor a cero.', 16, 1);

        SET @Descuento = CAST(@Subtotal * @PorcentajeDescuento / 100.0 AS DECIMAL(12,2));
        SET @Total     = @Subtotal - @Descuento;

        IF @Total <= 0
            RAISERROR('El total de la venta despues del descuento debe ser mayor a cero.', 16, 1);

        /* Neto e IVA por renglon: cada repuesto puede tener su alicuota.
           El descuento se prorratea para que neto + IVA de exactamente
           el total. */
        DECLARE @Neto DECIMAL(12,2), @Iva DECIMAL(12,2);
        DECLARE @factorDesc DECIMAL(18,10) = CASE WHEN @Subtotal > 0
                                                  THEN @Total / @Subtotal ELSE 1 END;

        SELECT @Neto = SUM(
            CAST(d.Cantidad * d.PrecioUnitario * @factorDesc
                 / (1 + ISNULL(a.Porcentaje, 21) / 100.0) AS DECIMAL(12,2)))
        FROM @Detalle d
        INNER JOIN Repuesto r ON r.Id = d.IdRepuesto
        LEFT JOIN AlicuotaIva a ON a.Id = r.IdAlicuotaIva;

        SET @Neto = ISNULL(@Neto, 0);
        SET @Iva  = @Total - @Neto;

        /* ---------- Entrega y forma de pago ---------- */

        IF @Entrega IS NULL
            SET @Entrega = CASE WHEN @FormaPago = 'Contado' THEN @Total ELSE 0 END;

        IF @Entrega < 0
            RAISERROR('La entrega no puede ser negativa.', 16, 1);

        IF @Entrega > @Total
            RAISERROR('La entrega no puede superar el total de la venta.', 16, 1);

        IF @FormaPago = 'Contado' AND @Entrega <> @Total
            RAISERROR('En una venta de contado la entrega debe ser igual al total.', 16, 1);

        IF @FormaPago = 'CuentaCorriente'
        BEGIN
            -- Fiar a un cliente generico partiria la deuda de todos los
            -- mecanicos en una sola ficha: no se sabria quien debe que.
            IF NOT EXISTS (SELECT 1 FROM Cliente
                           WHERE Id = @IdCliente AND CuentaCorriente = 1 AND Activo = 1)
                RAISERROR('Ese cliente no tiene cuenta corriente habilitada. Para vender a credito hay que registrarlo.', 16, 1);
        END

        /* ---------- Cabecera ---------- */

        INSERT INTO Venta
            (Fecha, IdCliente, IdUsuario, IdEstadoVenta, Total,
             Neto, Iva, PorcentajeDescuento, Descuento,
             NombreOcasional, TelefonoOcasional, TipoCliente)
        VALUES
            (GETDATE(), @IdCliente, @IdUsuario, 1, @Total,
             @Neto, @Iva, @PorcentajeDescuento, @Descuento,
             NULLIF(LTRIM(RTRIM(@NombreOcasional)), ''),
             NULLIF(LTRIM(RTRIM(@TelefonoOcasional)), ''),
             @TipoCliente);

        DECLARE @IdVenta INT = SCOPE_IDENTITY();

        /* ---------- Detalle, con el costo del momento ---------- */

        INSERT INTO DetalleVenta
            (IdVenta, IdRepuesto, Cantidad, PrecioUnitario, Subtotal, CostoUnitario)
        SELECT
            @IdVenta, d.IdRepuesto, d.Cantidad, d.PrecioUnitario,
            (d.Cantidad * d.PrecioUnitario),
            r.PrecioCompra
        FROM @Detalle d
        INNER JOIN Repuesto r ON r.Id = d.IdRepuesto;

        /* ---------- Stock ---------- */

        UPDATE s
        SET s.Cantidad            = s.Cantidad - d.Cantidad,
            s.UltimaActualizacion = GETDATE()
        FROM Stock s
        INNER JOIN @Detalle d ON d.IdRepuesto = s.IdRepuesto;

        IF EXISTS (SELECT 1 FROM Stock s INNER JOIN @Detalle d ON d.IdRepuesto = s.IdRepuesto
                   WHERE s.Cantidad < 0)
            RAISERROR('La operacion habria dejado stock negativo. No se registro la venta.', 16, 1);

        /* ---------- Caja ----------
           Solo entra lo que efectivamente se cobro. En una venta
           fiada eso es cero, y no se registra movimiento. */

        IF @Entrega > 0
        BEGIN
            DECLARE @DescCaja NVARCHAR(250) =
                CASE WHEN @FormaPago = 'CuentaCorriente'
                     THEN 'Entrega sobre venta #' + CAST(@IdVenta AS NVARCHAR(10))
                     ELSE 'Ingreso automatico por venta #' + CAST(@IdVenta AS NVARCHAR(10)) END;

            EXEC SP_MovimientoCaja_RegistrarInterno
                @Tipo        = 'Ingreso',
                @Concepto    = 'Venta mostrador',
                @Monto       = @Entrega,
                @Descripcion = @DescCaja,
                @IdUsuario   = @IdUsuario,
                @IdVenta     = @IdVenta,
                @IdPedido    = NULL;
        END

        /* ---------- Cuenta corriente ----------
           La venta genera el DEBE por el total. Si hubo entrega, se
           registra ademas el HABER. El saldo sube por la diferencia. */

        IF @FormaPago = 'CuentaCorriente'
        BEGIN
            INSERT INTO MovimientoCuentaCorriente
                (IdCliente, Tipo, Concepto, Monto, IdVenta, IdUsuario)
            VALUES
                (@IdCliente, 'Venta',
                 'Venta #' + CAST(@IdVenta AS VARCHAR(10)),
                 @Total, @IdVenta, @IdUsuario);

            IF @Entrega > 0
                INSERT INTO MovimientoCuentaCorriente
                    (IdCliente, Tipo, Concepto, Monto, IdVenta, IdUsuario)
                VALUES
                    (@IdCliente, 'Pago',
                     'Entrega sobre venta #' + CAST(@IdVenta AS VARCHAR(10)),
                     -@Entrega, @IdVenta, @IdUsuario);
        END

        COMMIT TRANSACTION;

        SELECT @IdVenta AS IdVenta, @Total AS Total, @Descuento AS Descuento,
               @Entrega AS Entrega, (@Total - @Entrega) AS SaldoGenerado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   PRUEBAS

   Antes de correrlas hay que tener un repuesto con stock. Si el
   catalogo esta vacio, cargar stock con un ajuste.
   ----------------------------------------------------------------- */
/*
-- 1. Venta de contado: entra todo a caja, sin movimiento de cuenta corriente
DECLARE @d DetalleVentaType;
INSERT INTO @d VALUES (1, 1, 1092.91);
EXEC SP_Venta_I @IdCliente = 1, @IdUsuario = 1, @Detalle = @d;

-- 2. Venta fiada a un mecanico: no entra nada a caja, sube el saldo
DECLARE @d2 DetalleVentaType;
INSERT INTO @d2 VALUES (1, 1, 1092.91);
EXEC SP_Venta_I @IdCliente = <IdMecanico>, @IdUsuario = 1, @Detalle = @d2,
                @PorcentajeDescuento = 10, @FormaPago = 'CuentaCorriente';

-- 3. Venta fiada con entrega parcial
DECLARE @d3 DetalleVentaType;
INSERT INTO @d3 VALUES (1, 2, 1092.91);
EXEC SP_Venta_I @IdCliente = <IdMecanico>, @IdUsuario = 1, @Detalle = @d3,
                @PorcentajeDescuento = 10, @FormaPago = 'CuentaCorriente',
                @Entrega = 1000;

-- 4. Saldo y movimientos
EXEC SP_CuentaCorriente_GetSaldo @IdCliente = <IdMecanico>;
EXEC SP_CuentaCorriente_GetMovimientos @IdCliente = <IdMecanico>;

-- 5. Cobro
EXEC SP_CuentaCorriente_RegistrarPago @IdCliente = <IdMecanico>,
                                      @Monto = 2000, @IdUsuario = 1;

-- 6. Verificar que la caja solo tenga lo efectivamente cobrado
SELECT Tipo, Concepto, Monto, Descripcion FROM MovimientoCaja ORDER BY Id DESC;
*/
GO
