USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   38 — SP_Venta_I CON FORMAS DE PAGO

   Acepta una lista de pagos (@Pagos). Efectivo va a la caja fisica,
   lo demas a su cuenta financiera con la comision como egreso.
   Si @Pagos viene vacia, se comporta como antes con @FormaPago y
   @Entrega: la app mobile y cualquier cliente viejo siguen andando.

   Requiere el script 37.
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
    @TipoCliente         NVARCHAR(20)  = NULL,        -- 'Publico' | 'Mecanico'
    -- formas de pago: lista de (medio, monto). Si viene vacia, se usan
    -- @FormaPago y @Entrega como antes (compatibilidad con clientes viejos)
    @Pagos               VentaPagoType READONLY
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

        /* ---------- Pagos ----------
           Dos caminos:
             a) Lista de pagos (clientes nuevos): uno o varios medios.
                Lo pagado es la suma; si no llega al total, el resto
                va a cuenta corriente.
             b) Sin lista (clientes viejos): @FormaPago y @Entrega se
                convierten en un unico pago en efectivo. */

        DECLARE @PagosNorm TABLE (IdMedioPago INT, Monto DECIMAL(12,2), Orden INT IDENTITY(1,1));
        DECLARE @Pagado DECIMAL(12,2) = 0;

        IF EXISTS (SELECT 1 FROM @Pagos)
        BEGIN
            IF EXISTS (SELECT 1 FROM @Pagos WHERE Monto <= 0)
                RAISERROR('Cada pago debe tener un importe mayor a cero.', 16, 1);

            IF EXISTS (SELECT 1 FROM @Pagos p LEFT JOIN MedioPago m ON m.Id = p.IdMedioPago AND m.Activo = 1
                       WHERE m.Id IS NULL)
                RAISERROR('Uno de los medios de pago no existe o esta inactivo.', 16, 1);

            INSERT INTO @PagosNorm (IdMedioPago, Monto)
            SELECT IdMedioPago, Monto FROM @Pagos;

            SELECT @Pagado = SUM(Monto) FROM @PagosNorm;

            -- Lo que no se pago va a cuenta corriente
            SET @FormaPago = CASE WHEN @Pagado < @Total THEN 'CuentaCorriente' ELSE 'Contado' END;
            SET @Entrega = @Pagado;
        END
        ELSE
        BEGIN
            -- Camino viejo
            IF @Entrega IS NULL
                SET @Entrega = CASE WHEN @FormaPago = 'Contado' THEN @Total ELSE 0 END;

            IF @FormaPago = 'Contado' AND @Entrega <> @Total
                RAISERROR('En una venta de contado la entrega debe ser igual al total.', 16, 1);

            IF @Entrega > 0
                INSERT INTO @PagosNorm (IdMedioPago, Monto)
                SELECT Id, @Entrega FROM MedioPago WHERE Codigo = 'EFE';

            SET @Pagado = @Entrega;
        END

        IF @Pagado < 0
            RAISERROR('Lo pagado no puede ser negativo.', 16, 1);

        -- Tolerancia de un centavo por redondeos de pago mixto
        IF @Pagado > @Total + 0.01
            RAISERROR('Lo pagado supera el total de la venta.', 16, 1);

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

        /* ---------- Registro de cada pago ----------
           Efectivo -> MovimientoCaja (arqueo).
           Lo demas -> MovimientoCuentaFinanciera, con la comision como
           egreso separado. Queda visible cuanto se llevan las tarjetas. */

        DECLARE @ComisionTotal DECIMAL(12,2) = 0;
        DECLARE @i INT = 1, @n INT = (SELECT COUNT(*) FROM @PagosNorm);
        DECLARE @pMedio INT, @pMonto DECIMAL(12,2), @pComPorc DECIMAL(5,2), @pCom DECIMAL(12,2),
                @pCuenta INT, @pEsCaja BIT, @pNombre NVARCHAR(40), @pIdPago INT;

        WHILE @i <= @n
        BEGIN
            SELECT @pMedio = pn.IdMedioPago, @pMonto = pn.Monto,
                   @pComPorc = m.ComisionPorc, @pCuenta = m.IdCuentaFinanciera,
                   @pEsCaja = c.EsCaja, @pNombre = m.Nombre
            FROM @PagosNorm pn
            INNER JOIN MedioPago m ON m.Id = pn.IdMedioPago
            INNER JOIN CuentaFinanciera c ON c.Id = m.IdCuentaFinanciera
            WHERE pn.Orden = @i;

            SET @pCom = CAST(@pMonto * @pComPorc / 100.0 AS DECIMAL(12,2));
            SET @ComisionTotal = @ComisionTotal + @pCom;

            INSERT INTO VentaPago (IdVenta, IdMedioPago, Monto, ComisionPorc, Comision, Neto)
            VALUES (@IdVenta, @pMedio, @pMonto, @pComPorc, @pCom, @pMonto - @pCom);
            SET @pIdPago = SCOPE_IDENTITY();

            IF @pEsCaja = 1
            BEGIN
                DECLARE @DescCaja NVARCHAR(250) =
                    CASE WHEN @FormaPago = 'CuentaCorriente'
                         THEN 'Entrega sobre venta #' + CAST(@IdVenta AS NVARCHAR(10))
                         ELSE 'Ingreso automatico por venta #' + CAST(@IdVenta AS NVARCHAR(10)) END;

                EXEC SP_MovimientoCaja_RegistrarInterno
                    @Tipo = 'Ingreso', @Concepto = 'Venta mostrador', @Monto = @pMonto,
                    @Descripcion = @DescCaja, @IdUsuario = @IdUsuario,
                    @IdVenta = @IdVenta, @IdPedido = NULL;
            END
            ELSE
            BEGIN
                INSERT INTO MovimientoCuentaFinanciera
                    (IdCuentaFinanciera, Tipo, Concepto, Monto, Descripcion, IdUsuario, IdVenta, IdVentaPago)
                VALUES
                    (@pCuenta, 'Ingreso', 'Venta ' + @pNombre, @pMonto,
                     'Venta #' + CAST(@IdVenta AS NVARCHAR(10)), @IdUsuario, @IdVenta, @pIdPago);

                IF @pCom > 0
                    INSERT INTO MovimientoCuentaFinanciera
                        (IdCuentaFinanciera, Tipo, Concepto, Monto, Descripcion, IdUsuario, IdVenta, IdVentaPago)
                    VALUES
                        (@pCuenta, 'Egreso', 'Comision ' + @pNombre, @pCom,
                         CAST(@pComPorc AS NVARCHAR(10)) + '% sobre venta #' + CAST(@IdVenta AS NVARCHAR(10)),
                         @IdUsuario, @IdVenta, @pIdPago);
            END

            SET @i = @i + 1;
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
               @Pagado AS Entrega, @Pagado AS Pagado,
               (@Total - @Pagado) AS SaldoGenerado, @ComisionTotal AS Comision;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   PRUEBAS (ajustar los Ids a los de tu base)
   ----------------------------------------------------------------- */
/*
DECLARE @d DetalleVentaType; INSERT INTO @d VALUES (1, 1, 1000);
DECLARE @p VentaPagoType;

-- 1) Contado en efectivo, camino viejo (sin @Pagos): igual que siempre
EXEC SP_Venta_I @IdCliente = 1, @IdUsuario = 1, @Detalle = @d;

-- 2) Todo con debito: entra a BANCO menos 5% de comision, caja no se mueve
INSERT INTO @p SELECT Id, 1000 FROM MedioPago WHERE Codigo = 'DEB';
EXEC SP_Venta_I @IdCliente = 1, @IdUsuario = 1, @Detalle = @d, @Pagos = @p;
DELETE FROM @p;

-- 3) Mixto: 600 efectivo + 400 QR
INSERT INTO @p SELECT Id, 600 FROM MedioPago WHERE Codigo = 'EFE';
INSERT INTO @p SELECT Id, 400 FROM MedioPago WHERE Codigo = 'QR';
EXEC SP_Venta_I @IdCliente = 1, @IdUsuario = 1, @Detalle = @d, @Pagos = @p;
DELETE FROM @p;

-- 4) Mecanico con cuenta corriente: paga 300 por transferencia, debe 700
INSERT INTO @p SELECT Id, 300 FROM MedioPago WHERE Codigo = 'TRF';
EXEC SP_Venta_I @IdCliente = <IdMecanico>, @IdUsuario = 1, @Detalle = @d, @Pagos = @p, @TipoCliente = 'Mecanico';

-- Verificar
SELECT * FROM VentaPago ORDER BY Id DESC;
SELECT * FROM MovimientoCuentaFinanciera ORDER BY Id DESC;
SELECT Tipo, Concepto, Monto FROM MovimientoCaja ORDER BY Id DESC;
EXEC SP_CuentaFinanciera_Resumen;
EXEC SP_Venta_PorMedioPago;
*/
