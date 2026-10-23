USE [DaytonaInyeccion];
GO

-- ==================================================
-- RESET DE DATOS DE PRUEBA  (version final)
-- Ejecutar TODO el archivo con F5, sin seleccionar.
--
-- Orden armado desde el mapa real de claves foraneas.
-- Los DBCC solo corren si el borrado funciono: si fallan
-- los DELETE y los contadores se reinician igual, quedan
-- apuntando a Ids que todavia existen.
-- ==================================================

BEGIN TRY
    BEGIN TRANSACTION;

    -- Sueltan las referencias a Repuesto sin borrar la lista del proveedor
    IF OBJECT_ID('ProveedorRepuesto', 'U') IS NOT NULL
        UPDATE ProveedorRepuesto SET IdRepuesto = NULL WHERE IdRepuesto IS NOT NULL;

    -- Presupuestos antes que ventas: Presupuesto.IdVenta apunta a Venta
    IF OBJECT_ID('DetallePresupuesto', 'U') IS NOT NULL DELETE FROM DetallePresupuesto;
    IF OBJECT_ID('Presupuesto', 'U')        IS NOT NULL DELETE FROM Presupuesto;

    -- Movimientos antes que sus origenes
    IF OBJECT_ID('MovimientoCaja', 'U')  IS NOT NULL DELETE FROM MovimientoCaja;
    IF OBJECT_ID('MovimientoStock', 'U') IS NOT NULL DELETE FROM MovimientoStock;

    DELETE FROM DetalleVenta;
    DELETE FROM Venta;

    DELETE FROM DetallePedido;
    DELETE FROM Pedido;

    DELETE FROM Stock;
    DELETE FROM Repuesto;

    COMMIT TRANSACTION;
    PRINT 'Reset completo.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'ERROR: no se borro nada. Detalle abajo.';
    THROW;
END CATCH
GO


-- Contadores: solo si el borrado funciono.
-- Stock no lleva identity, su clave es IdRepuesto.
IF (SELECT COUNT(*) FROM Repuesto) = 0 AND (SELECT COUNT(*) FROM Venta) = 0
BEGIN
    DBCC CHECKIDENT ('Repuesto',           RESEED, 0);
    DBCC CHECKIDENT ('Venta',              RESEED, 0);
    DBCC CHECKIDENT ('DetalleVenta',       RESEED, 0);
    DBCC CHECKIDENT ('Pedido',             RESEED, 0);
    DBCC CHECKIDENT ('DetallePedido',      RESEED, 0);
    DBCC CHECKIDENT ('Presupuesto',        RESEED, 0);
    DBCC CHECKIDENT ('DetallePresupuesto', RESEED, 0);
    DBCC CHECKIDENT ('MovimientoCaja',     RESEED, 0);
    PRINT 'Contadores reiniciados.';
END
ELSE
    PRINT 'Contadores NO reiniciados: todavia quedan datos.';
GO


-- Proveedores de prueba. Ya no hay pedidos que los referencien.
IF (SELECT COUNT(*) FROM Pedido) = 0
BEGIN
    IF OBJECT_ID('ProveedorRepuesto', 'U') IS NOT NULL
        DELETE FROM ProveedorRepuesto WHERE IdProveedor IN (4, 7, 8);

    DELETE FROM Proveedor WHERE Id IN (4, 7, 8);
    PRINT 'Proveedores de prueba eliminados.';
END
GO


-- ============ VERIFICACION ============
SELECT 'Repuesto' AS Tabla, COUNT(*) AS Filas FROM Repuesto
UNION ALL SELECT 'Stock',                  COUNT(*) FROM Stock
UNION ALL SELECT 'Venta',                  COUNT(*) FROM Venta
UNION ALL SELECT 'DetalleVenta',           COUNT(*) FROM DetalleVenta
UNION ALL SELECT 'Pedido',                 COUNT(*) FROM Pedido
UNION ALL SELECT 'DetallePedido',          COUNT(*) FROM DetallePedido
UNION ALL SELECT 'Presupuesto',            COUNT(*) FROM Presupuesto
UNION ALL SELECT 'MovimientoCaja',         COUNT(*) FROM MovimientoCaja
UNION ALL SELECT 'Rubro (conservado)',     COUNT(*) FROM Rubro
UNION ALL SELECT 'Marca (conservado)',     COUNT(*) FROM Marca
UNION ALL SELECT 'Modelo (conservado)',    COUNT(*) FROM Modelo
UNION ALL SELECT 'Proveedor (conservado)', COUNT(*) FROM Proveedor
UNION ALL SELECT 'Cliente (conservado)',   COUNT(*) FROM Cliente
UNION ALL SELECT 'Usuario (conservado)',   COUNT(*) FROM Usuario;

SELECT Id, RazonSocial FROM Proveedor;
GO
