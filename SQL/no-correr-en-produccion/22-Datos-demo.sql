USE [DaytonaInyeccion]
GO
SET NOCOUNT ON;
GO

/* =================================================================
   22 — DATOS DE DEMOSTRACION

   Genera clientes, repuestos, ventas, pagos y saldos para poder
   mostrar el sistema con contenido.

   IMPORTANTE: usa los procedimientos reales (SP_Repuesto_I,
   SP_Venta_I, SP_CuentaCorriente_RegistrarPago), no inserts
   directos. Asi el stock, la caja y la cuenta corriente quedan
   coherentes entre si, y de paso queda probado el circuito completo.

   La unica excepcion es la carga inicial de stock, que se hace por
   UPDATE. En el uso real eso va por Ajuste de Stock, que ademas
   registra el motivo y el usuario.

   Se puede correr varias veces: los clientes no se duplican y los
   repuestos se saltean si ya estan incorporados.
   ================================================================= */

DECLARE @IdUsuario INT;
SELECT TOP 1 @IdUsuario = Id FROM Usuario WHERE Activo = 1 ORDER BY Id;

IF @IdUsuario IS NULL
BEGIN
    RAISERROR('No hay usuarios activos. Cargá al menos uno antes de seguir.', 16, 1);
    RETURN;
END

PRINT '=== Usuario para la carga: ' + CAST(@IdUsuario AS VARCHAR(10)) + ' ===';


/* -----------------------------------------------------------------
   1. MECANICOS
   Sin DNI, con telefono, con cuenta corriente habilitada.
   ----------------------------------------------------------------- */
PRINT '';
PRINT '--- Mecanicos ---';

IF NOT EXISTS (SELECT 1 FROM Cliente WHERE Telefono = '3515501122')
    EXEC SP_Cliente_I @Dni = NULL, @Nombre = 'Carlos', @Apellido = 'Gimenez',
                      @Telefono = '3515501122', @Mail = NULL, @Calle = NULL,
                      @Numero = NULL, @EsMecanico = 1;

IF NOT EXISTS (SELECT 1 FROM Cliente WHERE Telefono = '3515503344')
    EXEC SP_Cliente_I @Dni = NULL, @Nombre = 'Marcelo', @Apellido = 'Ruiz',
                      @Telefono = '3515503344', @Mail = NULL, @Calle = NULL,
                      @Numero = NULL, @EsMecanico = 1;

IF NOT EXISTS (SELECT 1 FROM Cliente WHERE Telefono = '3515505566')
    EXEC SP_Cliente_I @Dni = NULL, @Nombre = 'Taller', @Apellido = 'San Martin',
                      @Telefono = '3515505566', @Mail = NULL, @Calle = NULL,
                      @Numero = NULL, @EsMecanico = 1;

-- SP_Cliente_I no habilita cuenta corriente por si solo
UPDATE Cliente SET CuentaCorriente = 1
WHERE EsMecanico = 1 AND Telefono IN ('3515501122','3515503344','3515505566');

DECLARE @Carlos INT, @Marcelo INT, @Taller INT;
SELECT @Carlos  = Id FROM Cliente WHERE Telefono = '3515501122';
SELECT @Marcelo = Id FROM Cliente WHERE Telefono = '3515503344';
SELECT @Taller  = Id FROM Cliente WHERE Telefono = '3515505566';

SELECT Id, Apellido, Nombre, Telefono, EsMecanico, CuentaCorriente
FROM Cliente WHERE Id IN (@Carlos, @Marcelo, @Taller);


/* -----------------------------------------------------------------
   2. REPUESTOS desde la lista del proveedor

   Se eligen artículos reales con costo cargado, de rubros variados,
   para que el catalogo se vea creible.
   ----------------------------------------------------------------- */
PRINT '';
PRINT '--- Incorporando repuestos desde la lista ---';

DECLARE @ids TABLE (Id INT IDENTITY(1,1), IdLista INT);

INSERT INTO @ids (IdLista)
SELECT TOP 12 pr.Id
FROM ProveedorRepuesto pr
INNER JOIN Rubro r ON r.Id = pr.IdRubro
WHERE pr.Activo = 1
  AND pr.IdRepuesto IS NULL
  AND pr.PrecioCompra BETWEEN 3000 AND 90000
  AND (pr.RubroTexto LIKE '%BOMBA%'
    OR pr.RubroTexto LIKE '%AMORTIGUADOR%'
    OR pr.RubroTexto LIKE '%ABRAZADERA%'
    OR pr.RubroTexto LIKE '%FILTRO%'
    OR pr.RubroTexto LIKE '%CORREA%'
    OR pr.RubroTexto LIKE '%SENSOR%')
ORDER BY NEWID();

DECLARE @i INT = 1, @tot INT = (SELECT COUNT(*) FROM @ids), @idLista INT;

WHILE @i <= @tot
BEGIN
    SELECT @idLista = IdLista FROM @ids WHERE Id = @i;

    BEGIN TRY
        EXEC SP_Repuesto_IncorporarDesdeLista
             @IdListaProveedor = @idLista, @StockMinimo = 3;
    END TRY
    BEGIN CATCH
        -- Si ya estaba o la descripcion choca, se saltea y sigue
        PRINT '  (salteado: ' + ERROR_MESSAGE() + ')';
    END CATCH

    SET @i = @i + 1;
END

SELECT Id, Codigo, Descripcion, MarcaFabricante,
       PrecioCompra, PrecioNetoVenta, PrecioDeVenta
FROM Repuesto WHERE Activo = 1 ORDER BY Id;


/* -----------------------------------------------------------------
   3. STOCK INICIAL

   Carga directa. En el uso real esto va por Ajuste de Stock, que
   ademas guarda motivo y usuario.
   ----------------------------------------------------------------- */
PRINT '';
PRINT '--- Stock inicial ---';

UPDATE s
SET s.Cantidad = 4 + (r.Id % 9),          -- entre 4 y 12, variado
    s.UltimaActualizacion = GETDATE()
FROM Stock s
INNER JOIN Repuesto r ON r.Id = s.IdRepuesto
WHERE r.Activo = 1 AND s.Cantidad = 0;

-- Dos quedan en stock critico, para que la reposicion sugerida tenga
-- algo que mostrar
UPDATE s SET s.Cantidad = 1
FROM Stock s
WHERE s.IdRepuesto IN (SELECT TOP 2 Id FROM Repuesto WHERE Activo = 1 ORDER BY Id DESC);

SELECT r.Codigo, r.Descripcion, s.Cantidad, s.StockMinimo
FROM Repuesto r INNER JOIN Stock s ON s.IdRepuesto = r.Id
WHERE r.Activo = 1 ORDER BY r.Id;
GO


/* -----------------------------------------------------------------
   4. VENTAS

   Tres situaciones distintas para que la demostracion cubra los
   casos que importan.
   ----------------------------------------------------------------- */
PRINT '';
PRINT '--- Ventas ---';

DECLARE @IdUsuario INT, @Carlos INT, @Marcelo INT, @Taller INT, @ConsFinal INT;
SELECT TOP 1 @IdUsuario = Id FROM Usuario WHERE Activo = 1 ORDER BY Id;
SELECT @Carlos    = Id FROM Cliente WHERE Telefono = '3515501122';
SELECT @Marcelo   = Id FROM Cliente WHERE Telefono = '3515503344';
SELECT @Taller    = Id FROM Cliente WHERE Telefono = '3515505566';
SELECT @ConsFinal = Id FROM Cliente WHERE Dni = '00000000';

DECLARE @r1 INT, @r2 INT, @r3 INT, @r4 INT;
SELECT @r1 = MIN(Id) FROM Repuesto WHERE Activo = 1;
SELECT @r2 = MIN(Id) FROM Repuesto WHERE Activo = 1 AND Id > @r1;
SELECT @r3 = MIN(Id) FROM Repuesto WHERE Activo = 1 AND Id > @r2;
SELECT @r4 = MIN(Id) FROM Repuesto WHERE Activo = 1 AND Id > @r3;

DECLARE @p1 DECIMAL(12,2), @p2 DECIMAL(12,2), @p3 DECIMAL(12,2), @p4 DECIMAL(12,2);
SELECT @p1 = PrecioDeVenta FROM Repuesto WHERE Id = @r1;
SELECT @p2 = PrecioDeVenta FROM Repuesto WHERE Id = @r2;
SELECT @p3 = PrecioDeVenta FROM Repuesto WHERE Id = @r3;
SELECT @p4 = PrecioDeVenta FROM Repuesto WHERE Id = @r4;

/* --- Venta 1: contado a consumidor final, sin descuento --- */
BEGIN TRY
    DECLARE @d1 DetalleVentaType;
    INSERT INTO @d1 VALUES (@r1, 1, @p1), (@r2, 2, @p2);
    EXEC SP_Venta_I @IdCliente = @ConsFinal, @IdUsuario = @IdUsuario, @Detalle = @d1;
    PRINT '  Venta contado: OK';
END TRY
BEGIN CATCH PRINT '  Venta contado: ' + ERROR_MESSAGE(); END CATCH

/* --- Venta 2: mecanico, 10% de descuento, fiada completa --- */
BEGIN TRY
    DECLARE @d2 DetalleVentaType;
    INSERT INTO @d2 VALUES (@r3, 1, @p3);
    EXEC SP_Venta_I @IdCliente = @Carlos, @IdUsuario = @IdUsuario, @Detalle = @d2,
                    @PorcentajeDescuento = 10, @FormaPago = 'CuentaCorriente',
                    @TipoCliente = 'Mecanico';
    PRINT '  Venta fiada a Gimenez: OK';
END TRY
BEGIN CATCH PRINT '  Venta fiada Gimenez: ' + ERROR_MESSAGE(); END CATCH

/* --- Venta 3: mecanico, fiada con entrega parcial --- */
BEGIN TRY
    DECLARE @d3 DetalleVentaType, @totalM DECIMAL(12,2);
    INSERT INTO @d3 VALUES (@r4, 2, @p4);
    SET @totalM = CAST(@p4 * 2 * 0.9 AS DECIMAL(12,2));

    EXEC SP_Venta_I @IdCliente = @Marcelo, @IdUsuario = @IdUsuario, @Detalle = @d3,
                    @PorcentajeDescuento = 10, @FormaPago = 'CuentaCorriente',
                    @Entrega = 5000, @TipoCliente = 'Mecanico';
    PRINT '  Venta fiada con entrega a Ruiz: OK';
END TRY
BEGIN CATCH PRINT '  Venta con entrega Ruiz: ' + ERROR_MESSAGE(); END CATCH

/* --- Venta 4: taller, fiada --- */
BEGIN TRY
    DECLARE @d4 DetalleVentaType;
    INSERT INTO @d4 VALUES (@r1, 1, @p1), (@r3, 1, @p3);
    EXEC SP_Venta_I @IdCliente = @Taller, @IdUsuario = @IdUsuario, @Detalle = @d4,
                    @PorcentajeDescuento = 10, @FormaPago = 'CuentaCorriente',
                    @TipoCliente = 'Mecanico';
    PRINT '  Venta fiada a Taller San Martin: OK';
END TRY
BEGIN CATCH PRINT '  Venta Taller: ' + ERROR_MESSAGE(); END CATCH
GO


/* -----------------------------------------------------------------
   5. COBROS

   Uno paga parcial, otro paga de mas para que quede un saldo a favor.
   Ese caso es el que muestra que el modelo lo resuelve sin logica
   especial: el saldo simplemente queda negativo.
   ----------------------------------------------------------------- */
PRINT '';
PRINT '--- Cobros ---';

DECLARE @IdUsuario INT, @Carlos INT, @Marcelo INT;
SELECT TOP 1 @IdUsuario = Id FROM Usuario WHERE Activo = 1 ORDER BY Id;
SELECT @Carlos  = Id FROM Cliente WHERE Telefono = '3515501122';
SELECT @Marcelo = Id FROM Cliente WHERE Telefono = '3515503344';

-- Gimenez paga una parte
DECLARE @saldoCarlos DECIMAL(12,2);
SELECT @saldoCarlos = ISNULL(SUM(Monto), 0)
FROM MovimientoCuentaCorriente WHERE IdCliente = @Carlos;

IF @saldoCarlos > 1000
BEGIN
    DECLARE @pagoCarlos DECIMAL(12,2) = CAST(@saldoCarlos * 0.4 AS DECIMAL(12,2));
    EXEC SP_CuentaCorriente_RegistrarPago
         @IdCliente = @Carlos, @Monto = @pagoCarlos, @IdUsuario = @IdUsuario,
         @Observaciones = 'Pago parcial en efectivo';
    PRINT '  Gimenez pago parcial: OK';
END

-- Ruiz paga de mas: queda saldo a favor
DECLARE @saldoMarcelo DECIMAL(12,2);
SELECT @saldoMarcelo = ISNULL(SUM(Monto), 0)
FROM MovimientoCuentaCorriente WHERE IdCliente = @Marcelo;

IF @saldoMarcelo > 0
BEGIN
    DECLARE @pagoMarcelo DECIMAL(12,2) = @saldoMarcelo + 3500;
    EXEC SP_CuentaCorriente_RegistrarPago
         @IdCliente = @Marcelo, @Monto = @pagoMarcelo, @IdUsuario = @IdUsuario,
         @Observaciones = 'Pago con saldo a favor para la proxima';
    PRINT '  Ruiz pago de mas, queda a favor: OK';
END
GO


/* -----------------------------------------------------------------
   6. VERIFICACION FINAL

   Lo que hay que mirar:
   - Los tres mecanicos con saldos distintos: uno debe, otro tiene a
     favor, otro debe todo.
   - La caja tiene SOLO el contado y los cobros. Las ventas fiadas no
     aparecen como ingreso.
   ----------------------------------------------------------------- */
PRINT '';
PRINT '=== RESUMEN ===';

EXEC SP_CuentaCorriente_GetAll @SoloConSaldo = 0;

SELECT 'Ventas'    AS Tabla, COUNT(*) AS Cantidad FROM Venta
UNION ALL SELECT 'Repuestos',      COUNT(*) FROM Repuesto WHERE Activo = 1
UNION ALL SELECT 'Mov. cta cte',   COUNT(*) FROM MovimientoCuentaCorriente
UNION ALL SELECT 'Mov. caja',      COUNT(*) FROM MovimientoCaja;

-- El control que importa: a la caja entra solo lo cobrado
SELECT Tipo, Concepto, Monto, Descripcion, SaldoResultante
FROM MovimientoCaja ORDER BY Id;

SELECT
    (SELECT ISNULL(SUM(Total), 0) FROM Venta WHERE IdEstadoVenta = 1) AS TotalVendido,
    (SELECT ISNULL(SUM(CASE WHEN Tipo = 'Ingreso' THEN Monto ELSE -Monto END), 0)
     FROM MovimientoCaja)                                             AS EnCaja,
    (SELECT ISNULL(SUM(Monto), 0) FROM MovimientoCuentaCorriente)     AS PorCobrar;
-- TotalVendido = EnCaja + PorCobrar. Si eso cierra, el circuito esta bien.
GO

-- Reposicion sugerida e indicadores del menu
EXEC SP_Indicadores_Menu;
GO
