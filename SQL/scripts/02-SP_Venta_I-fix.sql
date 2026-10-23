USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   SP_Venta_I — correcciones

   1. La lectura de Stock ahora toma UPDLOCK + HOLDLOCK.
      Sin eso, dos ventas simultaneas del ultimo repuesto pasan las dos
      la validacion y el stock queda en negativo. El lock hace que la
      segunda transaccion espere a que la primera termine, y cuando
      lee ya ve el stock actualizado.

   2. El chequeo de stock pasa de INNER JOIN a LEFT JOIN.
      Con INNER JOIN, un repuesto sin fila en Stock desaparecia del
      resultado y por lo tanto nunca se detectaba como faltante.

   3. Se separan los dos casos para que el mensaje diga que pasa:
      "sin fila de stock" no es lo mismo que "no alcanza".
   ================================================================= */

ALTER PROCEDURE [dbo].[SP_Venta_I]
    @IdCliente INT,
    @IdUsuario INT,
    @Detalle DetalleVentaType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        -- Validar que haya detalle
        IF NOT EXISTS (SELECT 1 FROM @Detalle)
        BEGIN
            RAISERROR('La venta debe tener al menos un repuesto.', 16, 1);
        END

        -- Un mismo repuesto no puede venir dos veces: descontaria stock doble
        IF EXISTS (SELECT IdRepuesto FROM @Detalle GROUP BY IdRepuesto HAVING COUNT(*) > 1)
        BEGIN
            RAISERROR('Hay un repuesto repetido en el detalle de la venta.', 16, 1);
        END

        -- Repuestos sin fila en Stock: no se puede vender lo que no esta inventariado
        DECLARE @SinFilaStock NVARCHAR(200);
        SELECT TOP 1 @SinFilaStock = r.Descripcion
        FROM @Detalle d
        INNER JOIN Repuesto r ON r.Id = d.IdRepuesto
        LEFT JOIN Stock s WITH (UPDLOCK, HOLDLOCK) ON s.IdRepuesto = d.IdRepuesto
        WHERE s.IdRepuesto IS NULL;

        IF @SinFilaStock IS NOT NULL
        BEGIN
            RAISERROR('El repuesto "%s" no tiene stock inicializado. Registralo con un ajuste de stock antes de venderlo.', 16, 1, @SinFilaStock);
        END

        -- Stock suficiente. El UPDLOCK de arriba ya dejo las filas tomadas,
        -- asi que este SELECT ve el valor real y nadie lo puede cambiar
        -- hasta que esta transaccion termine.
        DECLARE @RepuestoSinStock NVARCHAR(200);
        DECLARE @Disponible INT;

        SELECT TOP 1
            @RepuestoSinStock = r.Descripcion,
            @Disponible = s.Cantidad
        FROM @Detalle d
        INNER JOIN Repuesto r ON r.Id = d.IdRepuesto
        INNER JOIN Stock s WITH (UPDLOCK, HOLDLOCK) ON s.IdRepuesto = d.IdRepuesto
        WHERE s.Cantidad < d.Cantidad;

        IF @RepuestoSinStock IS NOT NULL
        BEGIN
            RAISERROR('Stock insuficiente para "%s". Disponible: %d.', 16, 1, @RepuestoSinStock, @Disponible);
        END

        -- Calcular total. DECIMAL(12,2) para no desbordar con ventas grandes:
        -- DECIMAL(10,2) tope en 99.999.999,99
        DECLARE @Total DECIMAL(12,2);
        SELECT @Total = SUM(CAST(Cantidad AS DECIMAL(12,2)) * PrecioUnitario) FROM @Detalle;

        IF @Total IS NULL OR @Total <= 0
        BEGIN
            RAISERROR('El total de la venta debe ser mayor a cero.', 16, 1);
        END

        -- Insertar cabecera (estado 1 = Confirmada)
        INSERT INTO Venta (Fecha, IdCliente, IdUsuario, IdEstadoVenta, Total)
        VALUES (GETDATE(), @IdCliente, @IdUsuario, 1, @Total);

        DECLARE @IdVenta INT = SCOPE_IDENTITY();

        -- Insertar detalle
        INSERT INTO DetalleVenta (IdVenta, IdRepuesto, Cantidad, PrecioUnitario, Subtotal)
        SELECT @IdVenta, IdRepuesto, Cantidad, PrecioUnitario, (Cantidad * PrecioUnitario)
        FROM @Detalle;

        -- Descontar stock
        UPDATE s
        SET s.Cantidad            = s.Cantidad - d.Cantidad,
            s.UltimaActualizacion = GETDATE()
        FROM Stock s
        INNER JOIN @Detalle d ON d.IdRepuesto = s.IdRepuesto;

        -- Red de seguridad: si algo se escapo, no dejamos stock negativo
        IF EXISTS (SELECT 1 FROM Stock s INNER JOIN @Detalle d ON d.IdRepuesto = s.IdRepuesto
                   WHERE s.Cantidad < 0)
        BEGIN
            RAISERROR('La operacion habria dejado stock negativo. No se registro la venta.', 16, 1);
        END

        -- Ingreso automatico en caja
        DECLARE @DescCaja NVARCHAR(250) = 'Ingreso automatico por venta #' + CAST(@IdVenta AS NVARCHAR(10));
        EXEC SP_MovimientoCaja_RegistrarInterno
            @Tipo        = 'Ingreso',
            @Concepto    = 'Venta mostrador',
            @Monto       = @Total,
            @Descripcion = @DescCaja,
            @IdUsuario   = @IdUsuario,
            @IdVenta     = @IdVenta,
            @IdPedido    = NULL;

        COMMIT TRANSACTION;

        SELECT @IdVenta AS IdVenta;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   OPCIONAL: ampliar Venta.Total a DECIMAL(12,2)
   Solo si hoy es DECIMAL(10,2). Queda consistente con Presupuesto.Total.
   Verificar primero:
   ----------------------------------------------------------------- */

SELECT name AS Columna, TYPE_NAME(system_type_id) AS Tipo, precision, scale
FROM sys.columns
WHERE object_id = OBJECT_ID('Venta') AND name = 'Total';
GO

-- Si da precision 10, descomentar:
-- ALTER TABLE Venta ALTER COLUMN Total DECIMAL(12,2) NOT NULL;
-- GO


/* -----------------------------------------------------------------
   VERIFICACION: repuestos activos sin fila en Stock
   Si esta consulta devuelve filas, esos repuestos hoy no se pueden
   vender (antes se vendian sin descontar nada).
   ----------------------------------------------------------------- */

SELECT r.Id, r.Codigo, r.Descripcion
FROM Repuesto r
LEFT JOIN Stock s ON s.IdRepuesto = r.Id
WHERE s.IdRepuesto IS NULL AND r.Activo = 1;
GO
