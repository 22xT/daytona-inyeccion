USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   62 — STOCK RESERVADO POR ENCARGOS

   Lo que llega para un encargo abierto queda apartado para ese
   cliente: no se le puede vender a otro desde la venta comun ni desde
   la app. Se entrega desde Encargos.

   Reservado = suma de lo encargado en encargos PENDIENTES o AVISADOS.
   Libre     = stock fisico - reservado.
   No se guarda en ningun lado: se calcula, igual que el saldo de una
   cuenta corriente. Cuando el encargo se entrega o se cancela, la
   reserva desaparece sola.

   Ademas, la reposicion sugerida suma lo encargado a lo que hay que
   tener: un encargo sin stock aparece para pedir aunque el repuesto
   no tenga minimo.

   Requiere el script 61.
   ================================================================= */


/* -----------------------------------------------------------------
   1. Cuanto hay reservado de cada repuesto
   ----------------------------------------------------------------- */
IF OBJECT_ID('vw_StockReservado', 'V') IS NOT NULL DROP VIEW vw_StockReservado;
GO
CREATE VIEW vw_StockReservado
AS
SELECT ed.IdRepuesto, SUM(ed.Cantidad) AS Reservado, COUNT(DISTINCT e.Id) AS Encargos
FROM EncargoDetalle ed
INNER JOIN Encargo e ON e.Id = ed.IdEncargo
WHERE e.Estado IN ('PENDIENTE', 'AVISADO')
GROUP BY ed.IdRepuesto;
GO

IF OBJECT_ID('SP_Stock_Reservas', 'P') IS NOT NULL DROP PROCEDURE SP_Stock_Reservas;
GO
CREATE PROCEDURE SP_Stock_Reservas
AS
BEGIN
    SET NOCOUNT ON;
    SELECT IdRepuesto, Reservado, Encargos FROM vw_StockReservado;
END
GO


/* -----------------------------------------------------------------
   2. Reposicion sugerida con los encargos
     Necesita = Minimo + Encargado - Stock - EnCamino
   El stock cubre primero a los encargos y despues al minimo.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Reposicion_Sugerida', 'P') IS NOT NULL DROP PROCEDURE SP_Reposicion_Sugerida;
GO
CREATE PROCEDURE SP_Reposicion_Sugerida
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH EnCamino AS (
        SELECT dp.IdRepuesto, SUM(dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada) AS Cant
        FROM DetallePedido dp INNER JOIN Pedido p ON p.Id = dp.IdPedido
        WHERE p.IdEstado = 1 AND dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada > 0
        GROUP BY dp.IdRepuesto
    ),
    Base AS (
        SELECT r.Id AS IdRepuesto, r.Codigo, r.Descripcion,
               ISNULL(s.Cantidad, 0) AS Stock, ISNULL(s.StockMinimo, 0) AS Minimo,
               ISNULL(ec.Cant, 0) AS EnCamino,
               ISNULL(rv.Reservado, 0) AS Encargado
        FROM Repuesto r
        LEFT JOIN Stock s ON s.IdRepuesto = r.Id
        LEFT JOIN EnCamino ec ON ec.IdRepuesto = r.Id
        LEFT JOIN vw_StockReservado rv ON rv.IdRepuesto = r.Id
        WHERE r.Activo = 1
          AND (   (ISNULL(s.StockMinimo, 0) > 0 AND ISNULL(s.Cantidad, 0) <= ISNULL(s.StockMinimo, 0))
               OR ISNULL(rv.Reservado, 0) > 0)
    )
    SELECT b.IdRepuesto, b.Codigo, b.Descripcion, b.Stock, b.Minimo, b.EnCamino, b.Encargado,
           b.Minimo + b.Encargado - b.Stock - b.EnCamino AS Sugerido,
           -- Un encargo sin cubrir es un cliente esperando: va primero
           CASE WHEN b.Stock - b.Encargado <= 0  THEN 'SIN_STOCK'
                WHEN (b.Stock - b.Encargado) * 2 <= b.Minimo THEN 'CRITICO'
                ELSE 'BAJO' END AS Urgencia
    INTO #Items
    FROM Base b
    WHERE b.Minimo + b.Encargado - b.Stock - b.EnCamino > 0;

    -- 1. Repuestos a reponer: los mas urgentes primero
    SELECT * FROM #Items
    ORDER BY CASE Urgencia WHEN 'SIN_STOCK' THEN 0 WHEN 'CRITICO' THEN 1 ELSE 2 END,
             CASE WHEN Encargado > 0 THEN 0 ELSE 1 END, Descripcion;

    -- 2. Opciones de compra, solo de esos repuestos
    SELECT pr.IdRepuesto, pr.IdProveedor, p.RazonSocial AS Proveedor, pr.PrecioCompra AS Precio,
           p.CondicionIva, pr.CodigoProveedor
    FROM ProveedorRepuesto pr
    INNER JOIN #Items i ON i.IdRepuesto = pr.IdRepuesto
    INNER JOIN Proveedor p ON p.Id = pr.IdProveedor AND p.Activo = 1
    WHERE pr.Activo = 1 AND pr.PrecioCompra > 0
    ORDER BY pr.IdRepuesto, pr.PrecioCompra;

    -- 3. Bajo minimo pero ya pedidos
    ;WITH EnCamino AS (
        SELECT dp.IdRepuesto, SUM(dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada) AS Cant
        FROM DetallePedido dp INNER JOIN Pedido p ON p.Id = dp.IdPedido
        WHERE p.IdEstado = 1 GROUP BY dp.IdRepuesto
    )
    SELECT COUNT(*) AS CubiertosEnCamino
    FROM Repuesto r
    INNER JOIN Stock s ON s.IdRepuesto = r.Id
    INNER JOIN EnCamino ec ON ec.IdRepuesto = r.Id
    LEFT JOIN vw_StockReservado rv ON rv.IdRepuesto = r.Id
    WHERE r.Activo = 1 AND (s.StockMinimo > 0 OR ISNULL(rv.Reservado, 0) > 0)
      AND s.Cantidad <= s.StockMinimo + ISNULL(rv.Reservado, 0)
      AND s.StockMinimo + ISNULL(rv.Reservado, 0) - s.Cantidad - ec.Cant <= 0;
END
GO


/* -----------------------------------------------------------------
   3. La venta no toca lo reservado (salvo que entregue ese encargo)
   ----------------------------------------------------------------- */
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
    @Pagos               VentaPagoType READONLY,
    -- Entrega de un encargo: la sena ya cobrada se aplica con el medio SEN
    @IdEncargo           INT = NULL
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

        /* Stock reservado: lo que llego para un encargo abierto no se le
           vende a otro cliente. Si esta venta ES la entrega de un encargo,
           lo reservado para ese encargo no cuenta. */
        DECLARE @RepuestoReservado NVARCHAR(200), @Libre INT, @Reservado INT;
        SELECT TOP 1
            @RepuestoReservado = r.Descripcion,
            @Libre = s.Cantidad - rv.Reservado,
            @Reservado = rv.Reservado
        FROM @Detalle d
        INNER JOIN Repuesto r ON r.Id = d.IdRepuesto
        INNER JOIN Stock s ON s.IdRepuesto = d.IdRepuesto
        CROSS APPLY (SELECT ISNULL(SUM(ed.Cantidad), 0) AS Reservado
                     FROM EncargoDetalle ed INNER JOIN Encargo e ON e.Id = ed.IdEncargo
                     WHERE ed.IdRepuesto = d.IdRepuesto AND e.Estado IN ('PENDIENTE', 'AVISADO')
                       AND (@IdEncargo IS NULL OR e.Id <> @IdEncargo)) rv
        WHERE rv.Reservado > 0 AND s.Cantidad - rv.Reservado < d.Cantidad;

        IF @RepuestoReservado IS NOT NULL
        BEGIN
            IF @Libre < 0 SET @Libre = 0;
            RAISERROR('"%s": hay %d libre(s) y %d reservado(s) para encargos. Entregalo desde Encargos o cancelá el encargo.',
                      16, 1, @RepuestoReservado, @Libre, @Reservado);
        END

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

        /* ---------- Sena de un encargo ----------
           El medio SEN no mueve dinero: la sena entro a la caja o a
           Mercado Pago cuando se tomo el encargo. Aca solo se aplica, y
           tiene que coincidir con lo que el cliente dejo. */
        DECLARE @SenaAplicada DECIMAL(12,2) = ISNULL((SELECT SUM(pn.Monto) FROM @PagosNorm pn
                                                       INNER JOIN MedioPago m ON m.Id = pn.IdMedioPago
                                                       WHERE m.Codigo = 'SEN'), 0);
        IF @IdEncargo IS NULL AND @SenaAplicada > 0
            RAISERROR('La seña solo se aplica al entregar un encargo.', 16, 1);

        IF @IdEncargo IS NOT NULL
        BEGIN
            DECLARE @EstadoEncargo VARCHAR(12), @SenaEncargo DECIMAL(12,2);
            SELECT @EstadoEncargo = Estado FROM Encargo WITH (UPDLOCK, HOLDLOCK) WHERE Id = @IdEncargo;
            IF @EstadoEncargo IS NULL
                RAISERROR('El encargo no existe.', 16, 1);
            IF @EstadoEncargo IN ('ENTREGADO', 'CANCELADO')
                RAISERROR('Ese encargo ya fue entregado o cancelado.', 16, 1);
            SET @SenaEncargo = ISNULL((SELECT SUM(Monto) FROM EncargoSena WHERE IdEncargo = @IdEncargo), 0);
            IF ABS(@SenaAplicada - @SenaEncargo) > 0.01
                RAISERROR('La seña aplicada no coincide con la que dejó el cliente.', 16, 1);
        END

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

        /* ---------- Encargo entregado ---------- */
        IF @IdEncargo IS NOT NULL
            UPDATE Encargo SET Estado = 'ENTREGADO', IdVenta = @IdVenta, FechaEntrega = GETDATE()
            WHERE Id = @IdEncargo;

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
   PRUEBA
   ----------------------------------------------------------------- */
SELECT TOP 20 r.Codigo, r.Descripcion, s.Cantidad AS Stock, rv.Reservado, s.Cantidad - rv.Reservado AS Libre
FROM vw_StockReservado rv
INNER JOIN Repuesto r ON r.Id = rv.IdRepuesto
LEFT JOIN Stock s ON s.IdRepuesto = rv.IdRepuesto;
EXEC SP_Reposicion_Sugerida;
GO
