USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   83 — AUDITORIA GENERAL

   Quien cambio que, cuando, y que valor tenia antes.

   DOS FUENTES, UNA PANTALLA
   1. Lo que hoy se pisa sin dejar rastro se registra con disparadores
      en la tabla Auditoria: precio de venta y costo de los repuestos,
      margen propio, altas y bajas; stock minimo; margen de los rubros;
      parametros de Configuracion; usuarios, roles y contraseñas;
      mecanico y limite de credito de los clientes; costos fijos;
      comisiones de los medios de pago; condiciones de los proveedores.
   2. Lo que ya se guarda con usuario no se duplica, se lee de donde
      esta: ajustes de stock, ventas con descuento, anulaciones (ventas,
      recepciones, gastos, pagos a proveedores), notas de credito,
      encargos cancelados, excepciones de credito y diferencias de caja.
   La vista vw_Auditoria junta las dos.

   QUIEN LO HIZO
   La API abre cada conexion con el nombre de aplicacion
   "Daytona#u=<IdUsuario>" (Config.cs). Los disparadores lo leen con
   APP_NAME(). Un cambio hecho desde sqlcmd o el Management Studio
   queda sin usuario y con el programa de origen.

   CAMBIOS MASIVOS
   La importacion de listas puede cambiar el costo de cientos de
   repuestos de una vez. Mas de 50 repuestos en una misma operacion se
   registran en un solo renglon resumen, no uno por repuesto.

   Requiere los scripts 13, 43, 49, 57, 61, 80 y 82.
   ================================================================= */


/* -----------------------------------------------------------------
   1. Tabla
   ----------------------------------------------------------------- */
IF OBJECT_ID('Auditoria', 'U') IS NULL
BEGIN
    CREATE TABLE Auditoria (
        Id             BIGINT IDENTITY(1,1) PRIMARY KEY,
        Fecha          DATETIME       NOT NULL DEFAULT GETDATE(),
        IdUsuario      INT            NULL,
        Origen         NVARCHAR(128)  NULL,      -- programa, si no fue desde el sistema
        Entidad        VARCHAR(30)    NOT NULL,  -- Repuesto, Usuario, Parametro...
        IdRegistro     INT            NULL,
        Referencia     NVARCHAR(200)  NULL,      -- codigo y descripcion, nombre, clave
        Campo          NVARCHAR(60)   NOT NULL,
        ValorAnterior  NVARCHAR(250)  NULL,
        ValorNuevo     NVARCHAR(250)  NULL
    );
    CREATE INDEX IX_Auditoria_Fecha ON Auditoria (Fecha) INCLUDE (IdUsuario, Entidad);
    CREATE INDEX IX_Auditoria_Registro ON Auditoria (Entidad, IdRegistro);
END
GO


/* -----------------------------------------------------------------
   2. Quien esta conectado
   ----------------------------------------------------------------- */
IF OBJECT_ID('fn_AuditoriaUsuario', 'FN') IS NOT NULL DROP FUNCTION fn_AuditoriaUsuario;
GO
CREATE FUNCTION fn_AuditoriaUsuario ()
RETURNS INT
AS
BEGIN
    DECLARE @app NVARCHAR(128) = APP_NAME();
    IF @app LIKE N'Daytona#u=%'
        RETURN TRY_CAST(SUBSTRING(@app, 11, 20) AS INT);
    RETURN NULL;
END
GO

IF OBJECT_ID('fn_AuditoriaOrigen', 'FN') IS NOT NULL DROP FUNCTION fn_AuditoriaOrigen;
GO
CREATE FUNCTION fn_AuditoriaOrigen ()
RETURNS NVARCHAR(128)
AS
BEGIN
    DECLARE @app NVARCHAR(128) = APP_NAME();
    IF @app LIKE N'Daytona#u=%' RETURN NULL;
    RETURN LEFT(ISNULL(NULLIF(@app, N''), N'Desconocido') + N' (' + SUSER_SNAME() + N')', 128);
END
GO

-- Formatos para que el valor se lea como en la pantalla
IF OBJECT_ID('fn_AudPesos', 'FN') IS NOT NULL DROP FUNCTION fn_AudPesos;
GO
CREATE FUNCTION fn_AudPesos (@v DECIMAL(14,2))
RETURNS NVARCHAR(40)
AS
BEGIN
    RETURN CASE WHEN @v IS NULL THEN NULL ELSE N'$ ' + FORMAT(@v, 'N2', 'es-AR') END;
END
GO
IF OBJECT_ID('fn_AudPorc', 'FN') IS NOT NULL DROP FUNCTION fn_AudPorc;
GO
CREATE FUNCTION fn_AudPorc (@v DECIMAL(9,2))
RETURNS NVARCHAR(40)
AS
BEGIN
    RETURN CASE WHEN @v IS NULL THEN NULL ELSE FORMAT(@v, '0.##', 'es-AR') + N'%' END;
END
GO
IF OBJECT_ID('fn_AudSiNo', 'FN') IS NOT NULL DROP FUNCTION fn_AudSiNo;
GO
CREATE FUNCTION fn_AudSiNo (@v BIT)
RETURNS NVARCHAR(10)
AS
BEGIN
    RETURN CASE WHEN @v IS NULL THEN NULL WHEN @v = 1 THEN N'Sí' ELSE N'No' END;
END
GO


/* -----------------------------------------------------------------
   3. Disparadores
   Patron: por cada campo vigilado, un renglon solo si cambio.
   ----------------------------------------------------------------- */

-- 3.1 Repuesto: precio, costo, margen propio, activo, rubro
IF OBJECT_ID('TR_Repuesto_Auditoria', 'TR') IS NOT NULL DROP TRIGGER TR_Repuesto_Auditoria;
GO
CREATE TRIGGER TR_Repuesto_Auditoria ON Repuesto
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

    DECLARE @u INT = dbo.fn_AuditoriaUsuario(), @o NVARCHAR(128) = dbo.fn_AuditoriaOrigen();

    -- Altas (solo si se carga de a uno; la incorporacion masiva no)
    IF NOT EXISTS (SELECT 1 FROM deleted)
    BEGIN
        IF (SELECT COUNT(*) FROM inserted) <= 50
            INSERT INTO Auditoria (IdUsuario, Origen, Entidad, IdRegistro, Referencia, Campo, ValorAnterior, ValorNuevo)
            SELECT @u, @o, 'Repuesto', i.Id, LEFT(ISNULL(i.Codigo + N' · ', N'') + i.Descripcion, 200),
                   N'Alta', NULL, N'Precio ' + dbo.fn_AudPesos(i.PrecioDeVenta)
            FROM inserted i;
        RETURN;
    END

    ;WITH C AS (
        SELECT i.Id, LEFT(ISNULL(i.Codigo + N' · ', N'') + i.Descripcion, 200) AS Ref, v.Campo, v.Ant, v.Nue
        FROM inserted i
        INNER JOIN deleted d ON d.Id = i.Id
        CROSS APPLY (VALUES
            (N'Precio de venta', dbo.fn_AudPesos(d.PrecioDeVenta), dbo.fn_AudPesos(i.PrecioDeVenta)),
            (N'Costo',           dbo.fn_AudPesos(d.PrecioCompra),  dbo.fn_AudPesos(i.PrecioCompra)),
            (N'Margen propio',   dbo.fn_AudPorc(d.MargenPropio),   dbo.fn_AudPorc(i.MargenPropio)),
            (N'Activo',          dbo.fn_AudSiNo(d.Activo),         dbo.fn_AudSiNo(i.Activo)),
            (N'Rubro',           CAST(d.IdRubro AS NVARCHAR(20)),  CAST(i.IdRubro AS NVARCHAR(20)))
        ) v(Campo, Ant, Nue)
        WHERE ISNULL(v.Ant, N'~') <> ISNULL(v.Nue, N'~')
    )
    SELECT * INTO #C FROM C;

    IF (SELECT COUNT(DISTINCT Id) FROM #C) > 50
        -- Cambio masivo: un renglon por campo
        INSERT INTO Auditoria (IdUsuario, Origen, Entidad, IdRegistro, Referencia, Campo, ValorAnterior, ValorNuevo)
        SELECT @u, @o, 'Repuesto', NULL,
               CAST(COUNT(DISTINCT Id) AS NVARCHAR(10)) + N' repuestos', Campo, NULL, N'Cambio masivo'
        FROM #C GROUP BY Campo;
    ELSE
        INSERT INTO Auditoria (IdUsuario, Origen, Entidad, IdRegistro, Referencia, Campo, ValorAnterior, ValorNuevo)
        SELECT @u, @o, 'Repuesto', c.Id, c.Ref, c.Campo,
               CASE WHEN c.Campo = N'Rubro' THEN (SELECT Nombre FROM Rubro WHERE Id = TRY_CAST(c.Ant AS INT)) ELSE c.Ant END,
               CASE WHEN c.Campo = N'Rubro' THEN (SELECT Nombre FROM Rubro WHERE Id = TRY_CAST(c.Nue AS INT)) ELSE c.Nue END
        FROM #C c;
END
GO

-- 3.2 Stock: solo el minimo (la cantidad la registran ventas, compras y ajustes)
IF OBJECT_ID('TR_Stock_Auditoria', 'TR') IS NOT NULL DROP TRIGGER TR_Stock_Auditoria;
GO
CREATE TRIGGER TR_Stock_Auditoria ON Stock
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(StockMinimo) RETURN;
    INSERT INTO Auditoria (IdUsuario, Origen, Entidad, IdRegistro, Referencia, Campo, ValorAnterior, ValorNuevo)
    SELECT dbo.fn_AuditoriaUsuario(), dbo.fn_AuditoriaOrigen(), 'Stock', i.IdRepuesto,
           LEFT(ISNULL(r.Codigo + N' · ', N'') + r.Descripcion, 200), N'Stock mínimo',
           CAST(d.StockMinimo AS NVARCHAR(20)), CAST(i.StockMinimo AS NVARCHAR(20))
    FROM inserted i
    INNER JOIN deleted d ON d.IdRepuesto = i.IdRepuesto
    INNER JOIN Repuesto r ON r.Id = i.IdRepuesto
    WHERE i.StockMinimo <> d.StockMinimo;
END
GO

-- 3.3 Rubro: margen, nombre, activo
IF OBJECT_ID('TR_Rubro_Auditoria', 'TR') IS NOT NULL DROP TRIGGER TR_Rubro_Auditoria;
GO
CREATE TRIGGER TR_Rubro_Auditoria ON Rubro
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO Auditoria (IdUsuario, Origen, Entidad, IdRegistro, Referencia, Campo, ValorAnterior, ValorNuevo)
    SELECT dbo.fn_AuditoriaUsuario(), dbo.fn_AuditoriaOrigen(), 'Rubro', i.Id, i.Nombre, v.Campo, v.Ant, v.Nue
    FROM inserted i
    INNER JOIN deleted d ON d.Id = i.Id
    CROSS APPLY (VALUES
        (N'Margen del rubro', ISNULL(dbo.fn_AudPorc(d.MargenPorcentaje), N'General'), ISNULL(dbo.fn_AudPorc(i.MargenPorcentaje), N'General')),
        (N'Nombre',           d.Nombre, i.Nombre),
        (N'Activo',           dbo.fn_AudSiNo(d.Activo), dbo.fn_AudSiNo(i.Activo))
    ) v(Campo, Ant, Nue)
    WHERE ISNULL(v.Ant, N'~') <> ISNULL(v.Nue, N'~');
END
GO

-- 3.4 Parametros de Configuracion
IF OBJECT_ID('TR_ParametroSistema_Auditoria', 'TR') IS NOT NULL DROP TRIGGER TR_ParametroSistema_Auditoria;
GO
CREATE TRIGGER TR_ParametroSistema_Auditoria ON ParametroSistema
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO Auditoria (IdUsuario, Origen, Entidad, IdRegistro, Referencia, Campo, ValorAnterior, ValorNuevo)
    SELECT dbo.fn_AuditoriaUsuario(), dbo.fn_AuditoriaOrigen(), 'Parametro', NULL,
           LEFT(ISNULL(i.Descripcion, i.Clave), 200), i.Clave, d.Valor, i.Valor
    FROM inserted i
    LEFT JOIN deleted d ON d.Clave = i.Clave
    WHERE ISNULL(d.Valor, N'~') <> ISNULL(i.Valor, N'~');
END
GO

-- 3.5 Usuarios: rol, activo, correo, nombre, contraseña (sin el valor)
IF OBJECT_ID('TR_Usuario_Auditoria', 'TR') IS NOT NULL DROP TRIGGER TR_Usuario_Auditoria;
GO
CREATE TRIGGER TR_Usuario_Auditoria ON Usuario
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @u INT = dbo.fn_AuditoriaUsuario(), @o NVARCHAR(128) = dbo.fn_AuditoriaOrigen();

    -- Alta
    INSERT INTO Auditoria (IdUsuario, Origen, Entidad, IdRegistro, Referencia, Campo, ValorAnterior, ValorNuevo)
    SELECT @u, @o, 'Usuario', i.Id, i.Nombre + N' (' + i.Correo + N')', N'Alta de usuario', NULL, r.Nombre
    FROM inserted i
    LEFT JOIN deleted d ON d.Id = i.Id
    LEFT JOIN Rol r ON r.Id = i.IdRol
    WHERE d.Id IS NULL;

    -- Baja fisica
    INSERT INTO Auditoria (IdUsuario, Origen, Entidad, IdRegistro, Referencia, Campo, ValorAnterior, ValorNuevo)
    SELECT @u, @o, 'Usuario', d.Id, d.Nombre + N' (' + d.Correo + N')', N'Usuario eliminado', r.Nombre, NULL
    FROM deleted d
    LEFT JOIN inserted i ON i.Id = d.Id
    LEFT JOIN Rol r ON r.Id = d.IdRol
    WHERE i.Id IS NULL;

    -- Cambios
    INSERT INTO Auditoria (IdUsuario, Origen, Entidad, IdRegistro, Referencia, Campo, ValorAnterior, ValorNuevo)
    SELECT @u, @o, 'Usuario', i.Id, i.Nombre + N' (' + i.Correo + N')', v.Campo, v.Ant, v.Nue
    FROM inserted i
    INNER JOIN deleted d ON d.Id = i.Id
    LEFT JOIN Rol ra ON ra.Id = d.IdRol
    LEFT JOIN Rol rn ON rn.Id = i.IdRol
    CROSS APPLY (VALUES
        (N'Rol',         ra.Nombre, rn.Nombre),
        (N'Activo',      dbo.fn_AudSiNo(d.Activo), dbo.fn_AudSiNo(i.Activo)),
        (N'Correo',      d.Correo, i.Correo),
        (N'Nombre',      d.Nombre, i.Nombre),
        (N'Contraseña',  CASE WHEN d.ClaveHash <> i.ClaveHash THEN N'(anterior)' END,
                         CASE WHEN d.ClaveHash <> i.ClaveHash THEN N'(cambiada)' END)
    ) v(Campo, Ant, Nue)
    WHERE ISNULL(v.Ant, N'~') <> ISNULL(v.Nue, N'~');
END
GO

-- 3.6 Clientes: mecanico, limite de credito, activo
IF OBJECT_ID('TR_Cliente_Auditoria', 'TR') IS NOT NULL DROP TRIGGER TR_Cliente_Auditoria;
GO
CREATE TRIGGER TR_Cliente_Auditoria ON Cliente
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO Auditoria (IdUsuario, Origen, Entidad, IdRegistro, Referencia, Campo, ValorAnterior, ValorNuevo)
    SELECT dbo.fn_AuditoriaUsuario(), dbo.fn_AuditoriaOrigen(), 'Cliente', i.Id, i.Apellido + N', ' + i.Nombre, v.Campo, v.Ant, v.Nue
    FROM inserted i
    INNER JOIN deleted d ON d.Id = i.Id
    CROSS APPLY (VALUES
        (N'Mecánico',            dbo.fn_AudSiNo(d.EsMecanico), dbo.fn_AudSiNo(i.EsMecanico)),
        (N'Límite de crédito',   CASE WHEN d.CuentaCorriente = 0 THEN N'Sin cuenta' ELSE ISNULL(dbo.fn_AudPesos(d.LimiteCredito), N'Sin límite') END,
                                 CASE WHEN i.CuentaCorriente = 0 THEN N'Sin cuenta' ELSE ISNULL(dbo.fn_AudPesos(i.LimiteCredito), N'Sin límite') END),
        (N'Activo',              dbo.fn_AudSiNo(d.Activo), dbo.fn_AudSiNo(i.Activo))
    ) v(Campo, Ant, Nue)
    WHERE ISNULL(v.Ant, N'~') <> ISNULL(v.Nue, N'~');
END
GO

-- 3.7 Costos fijos
IF OBJECT_ID('TR_CostoFijo_Auditoria', 'TR') IS NOT NULL DROP TRIGGER TR_CostoFijo_Auditoria;
GO
CREATE TRIGGER TR_CostoFijo_Auditoria ON CostoFijo
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO Auditoria (IdUsuario, Origen, Entidad, IdRegistro, Referencia, Campo, ValorAnterior, ValorNuevo)
    SELECT dbo.fn_AuditoriaUsuario(), dbo.fn_AuditoriaOrigen(), 'CostoFijo', i.Id, i.Concepto, v.Campo, v.Ant, v.Nue
    FROM inserted i
    LEFT JOIN deleted d ON d.Id = i.Id
    CROSS APPLY (VALUES
        (N'Monto por mes', dbo.fn_AudPesos(d.MontoMensual), dbo.fn_AudPesos(i.MontoMensual)),
        (N'Activo',        dbo.fn_AudSiNo(d.Activo), dbo.fn_AudSiNo(i.Activo)),
        (N'Concepto',      d.Concepto, i.Concepto)
    ) v(Campo, Ant, Nue)
    WHERE ISNULL(v.Ant, N'~') <> ISNULL(v.Nue, N'~')
      AND NOT (d.Id IS NULL AND v.Campo <> N'Monto por mes');   -- el alta: un solo renglon
END
GO

-- 3.8 Medios de pago: comision y activo
IF OBJECT_ID('TR_MedioPago_Auditoria', 'TR') IS NOT NULL DROP TRIGGER TR_MedioPago_Auditoria;
GO
CREATE TRIGGER TR_MedioPago_Auditoria ON MedioPago
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO Auditoria (IdUsuario, Origen, Entidad, IdRegistro, Referencia, Campo, ValorAnterior, ValorNuevo)
    SELECT dbo.fn_AuditoriaUsuario(), dbo.fn_AuditoriaOrigen(), 'MedioPago', i.Id, i.Nombre, v.Campo, v.Ant, v.Nue
    FROM inserted i
    INNER JOIN deleted d ON d.Id = i.Id
    CROSS APPLY (VALUES
        (N'Comisión', dbo.fn_AudPorc(d.ComisionPorc), dbo.fn_AudPorc(i.ComisionPorc)),
        (N'Activo',   dbo.fn_AudSiNo(d.Activo), dbo.fn_AudSiNo(i.Activo))
    ) v(Campo, Ant, Nue)
    WHERE ISNULL(v.Ant, N'~') <> ISNULL(v.Nue, N'~');
END
GO

-- 3.9 Proveedores: descuento, plazos, activo
IF OBJECT_ID('TR_Proveedor_Auditoria', 'TR') IS NOT NULL DROP TRIGGER TR_Proveedor_Auditoria;
GO
CREATE TRIGGER TR_Proveedor_Auditoria ON Proveedor
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO Auditoria (IdUsuario, Origen, Entidad, IdRegistro, Referencia, Campo, ValorAnterior, ValorNuevo)
    SELECT dbo.fn_AuditoriaUsuario(), dbo.fn_AuditoriaOrigen(), 'Proveedor', i.Id, i.RazonSocial, v.Campo, v.Ant, v.Nue
    FROM inserted i
    INNER JOIN deleted d ON d.Id = i.Id
    CROSS APPLY (VALUES
        (N'Descuento general', dbo.fn_AudPorc(d.DescuentoGeneral), dbo.fn_AudPorc(i.DescuentoGeneral)),
        (N'Días de pago',      CAST(d.DiasPago AS NVARCHAR(10)), CAST(i.DiasPago AS NVARCHAR(10))),
        (N'Días de entrega',   CAST(d.DiasEntrega AS NVARCHAR(10)), CAST(i.DiasEntrega AS NVARCHAR(10))),
        (N'Condición IVA',     d.CondicionIva, i.CondicionIva),
        (N'Activo',            dbo.fn_AudSiNo(d.Activo), dbo.fn_AudSiNo(i.Activo))
    ) v(Campo, Ant, Nue)
    WHERE ISNULL(v.Ant, N'~') <> ISNULL(v.Nue, N'~');
END
GO


/* -----------------------------------------------------------------
   4. Todo junto
   Tipo agrupa para filtrar: Precios, Stock, Descuentos, Anulaciones,
   Permisos, Crédito, Caja, Configuración, Clientes, Proveedores.
   ----------------------------------------------------------------- */
IF OBJECT_ID('vw_Auditoria', 'V') IS NOT NULL DROP VIEW vw_Auditoria;
GO
CREATE VIEW vw_Auditoria
AS
-- Cambios registrados por los disparadores
SELECT
    a.Fecha, a.IdUsuario, a.Origen,
    CASE a.Entidad
        WHEN 'Repuesto'   THEN CASE WHEN a.Campo IN (N'Precio de venta', N'Costo', N'Margen propio') THEN 'Precios' ELSE 'Catálogo' END
        WHEN 'Stock'      THEN 'Stock'
        WHEN 'Usuario'    THEN 'Permisos'
        WHEN 'Cliente'    THEN CASE WHEN a.Campo = N'Límite de crédito' THEN 'Crédito' ELSE 'Clientes' END
        WHEN 'Proveedor'  THEN 'Proveedores'
        ELSE 'Configuración'
    END AS Tipo,
    a.Entidad, a.IdRegistro, a.Referencia, a.Campo, a.ValorAnterior, a.ValorNuevo,
    CAST(NULL AS NVARCHAR(250)) AS Detalle
FROM Auditoria a

UNION ALL
-- Ajustes de stock (manuales e inventario)
SELECT m.Fecha, m.IdUsuario, NULL, 'Stock', 'Repuesto', m.IdRepuesto,
       LEFT(ISNULL(r.Codigo + N' · ', N'') + r.Descripcion, 200), N'Cantidad',
       CAST(m.CantidadAnterior AS NVARCHAR(20)), CAST(m.CantidadNueva AS NVARCHAR(20)),
       LEFT(m.Tipo + N': ' + m.Motivo, 250)
FROM MovimientoStock m
INNER JOIN Repuesto r ON r.Id = m.IdRepuesto

UNION ALL
-- Ventas con descuento
SELECT v.Fecha, v.IdUsuario, NULL, 'Descuentos', 'Venta', v.Id,
       N'Venta #' + RIGHT('00000000' + CAST(v.Id AS VARCHAR(10)), 8), N'Descuento',
       dbo.fn_AudPesos(v.Total + v.Descuento),
       dbo.fn_AudPesos(v.Total),
       dbo.fn_AudPorc(v.PorcentajeDescuento) + N' (' + dbo.fn_AudPesos(v.Descuento) + N')' +
       CASE WHEN v.TipoCliente = N'Mecanico' THEN N' · mecánico' ELSE N'' END
FROM Venta v
WHERE v.PorcentajeDescuento > 0

UNION ALL
-- Ventas anuladas
SELECT v.FechaAnulacion, v.IdUsuarioAnulacion, NULL, 'Anulaciones', 'Venta', v.Id,
       N'Venta #' + RIGHT('00000000' + CAST(v.Id AS VARCHAR(10)), 8), N'Estado', N'Vigente', N'Anulada',
       N'Total ' + dbo.fn_AudPesos(v.Total) + N' · vendida el ' + CONVERT(NVARCHAR(10), v.Fecha, 103)
FROM Venta v
WHERE v.FechaAnulacion IS NOT NULL

UNION ALL
-- Recepciones anuladas o facturas descartadas
SELECT r.FechaAnulacion, r.IdUsuarioAnulacion, NULL, 'Anulaciones', 'Recepcion', r.Id,
       LEFT(p.RazonSocial + N' · ' + r.TipoComprobante + N' ' + r.NumeroComprobante, 200), N'Recepción',
       CASE WHEN r.Estado = 'EN_CONTROL' THEN N'En control' ELSE N'Confirmada' END, N'Anulada',
       LEFT(N'Total ' + dbo.fn_AudPesos(r.TotalComprobante) + ISNULL(N' · ' + r.MotivoAnulacion, N''), 250)
FROM RecepcionPedido r
INNER JOIN Proveedor p ON p.Id = r.IdProveedor
WHERE r.Anulada = 1 AND r.FechaAnulacion IS NOT NULL

UNION ALL
-- Gastos anulados
SELECT g.FechaAnulacion, g.IdUsuarioAnulacion, NULL, 'Anulaciones', 'Gasto', g.Id,
       LEFT(g.Descripcion, 200), N'Gasto', dbo.fn_AudPesos(g.Importe), N'Anulado',
       LEFT(g.MotivoAnulacion, 250)
FROM Gasto g
WHERE g.Estado = 'ANULADO' AND g.FechaAnulacion IS NOT NULL

UNION ALL
-- Pagos a proveedores anulados
SELECT pp.FechaAnulacion, pp.IdUsuarioAnulacion, NULL, 'Anulaciones', 'PagoProveedor', pp.Id,
       p.RazonSocial, N'Pago', dbo.fn_AudPesos(pp.Importe), N'Anulado', LEFT(pp.MotivoAnulacion, 250)
FROM PagoProveedor pp
INNER JOIN Proveedor p ON p.Id = pp.IdProveedor
WHERE pp.Estado = 'ANULADO' AND pp.FechaAnulacion IS NOT NULL

UNION ALL
-- Notas de credito a clientes (devoluciones y descuentos posteriores)
SELECT n.Fecha, n.IdUsuario, NULL, 'Anulaciones', 'NotaCliente', n.Id,
       LEFT(c.Apellido + N', ' + c.Nombre + ISNULL(N' · venta #' + CAST(n.IdVenta AS NVARCHAR(10)), N''), 200),
       N'Nota de crédito', NULL, dbo.fn_AudPesos(n.Importe), LEFT(n.Motivo, 250)
FROM NotaCliente n
INNER JOIN Cliente c ON c.Id = n.IdCliente
WHERE n.Tipo = 'NC'

UNION ALL
-- Encargos cancelados (el sistema no guarda quien cancelo: queda el que lo tomo)
SELECT e.FechaCancelacion, NULL, NULL, 'Anulaciones', 'Encargo', e.Id,
       LEFT(N'Encargo #' + CAST(e.Id AS NVARCHAR(10)) + N' · ' + e.Nombre, 200), N'Encargo', N'Abierto', N'Cancelado',
       LEFT(ISNULL(e.MotivoCancelacion, N'') +
            CASE e.ResolucionSena WHEN 'DEVUELTA' THEN N' · seña devuelta' WHEN 'A_FAVOR' THEN N' · seña a favor'
                                  WHEN 'RETENIDA' THEN N' · seña retenida' ELSE N'' END, 250)
FROM Encargo e
WHERE e.Estado = 'CANCELADO' AND e.FechaCancelacion IS NOT NULL

UNION ALL
-- Excepciones de credito autorizadas
SELECT a.Fecha, a.IdUsuario, NULL, 'Crédito', 'Venta', a.IdVenta,
       LEFT(c.Apellido + N', ' + c.Nombre + N' · venta #' + CAST(a.IdVenta AS NVARCHAR(10)), 200),
       CASE a.Motivo WHEN 'LIMITE' THEN N'Pasó el límite' WHEN 'ATRASO' THEN N'Fió con deuda atrasada' ELSE N'Límite y deuda atrasada' END,
       dbo.fn_AudPesos(a.SaldoAnterior), dbo.fn_AudPesos(a.SaldoAnterior + a.Importe),
       LEFT(ISNULL(N'Límite ' + dbo.fn_AudPesos(a.Limite), N'Sin límite') +
            CASE WHEN a.DiasAtraso > 0 THEN N' · deuda de ' + CAST(a.DiasAtraso AS NVARCHAR(10)) + N' días' ELSE N'' END, 250)
FROM AutorizacionCredito a
INNER JOIN Cliente c ON c.Id = a.IdCliente

UNION ALL
-- Cierres de caja con diferencia
SELECT s.FechaCierre, s.IdUsuarioCierre, NULL, 'Caja', 'SesionCaja', s.Id,
       N'Cierre de caja #' + CAST(s.Id AS NVARCHAR(10)), N'Efectivo',
       dbo.fn_AudPesos(s.SaldoTeorico), dbo.fn_AudPesos(s.EfectivoContado),
       LEFT(N'Diferencia ' + dbo.fn_AudPesos(s.Diferencia) + ISNULL(N' · ' + s.MotivoDiferencia, N''), 250)
FROM SesionCaja s
WHERE s.FechaCierre IS NOT NULL AND ISNULL(s.Diferencia, 0) <> 0;
GO


/* -----------------------------------------------------------------
   5. Listado para la pantalla
   RS1 Renglones (los mas nuevos primero, hasta @Max)
   RS2 Cuantos por tipo      RS3 Cuantos por usuario
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Auditoria_Listar', 'P') IS NOT NULL DROP PROCEDURE SP_Auditoria_Listar;
GO
CREATE PROCEDURE SP_Auditoria_Listar
    @Desde     DATE,
    @Hasta     DATE,
    @IdUsuario INT           = NULL,   -- -1 = sin usuario (scripts)
    @Tipo      VARCHAR(20)   = NULL,
    @Texto     NVARCHAR(100) = NULL,
    @Max       INT           = 500
AS
BEGIN
    SET NOCOUNT ON;
    IF @Max IS NULL OR @Max < 1 OR @Max > 5000 SET @Max = 500;
    SET @Texto = NULLIF(LTRIM(RTRIM(@Texto)), N'');

    SELECT a.Fecha, a.IdUsuario, a.Origen, a.Tipo, a.Entidad, a.IdRegistro, a.Referencia, a.Campo,
           a.ValorAnterior, a.ValorNuevo, a.Detalle
    INTO #A
    FROM vw_Auditoria a
    WHERE a.Fecha >= @Desde AND a.Fecha < DATEADD(DAY, 1, @Hasta)
      AND (@IdUsuario IS NULL OR (@IdUsuario = -1 AND a.IdUsuario IS NULL) OR a.IdUsuario = @IdUsuario)
      AND (@Texto IS NULL OR a.Referencia LIKE N'%' + @Texto + N'%' OR a.Campo LIKE N'%' + @Texto + N'%'
           OR a.Detalle LIKE N'%' + @Texto + N'%' OR a.ValorNuevo LIKE N'%' + @Texto + N'%');

    SELECT TOP (@Max) a.Fecha, a.Tipo, a.Entidad, a.IdRegistro, a.Referencia, a.Campo,
           a.ValorAnterior, a.ValorNuevo, a.Detalle, a.IdUsuario,
           ISNULL(u.Nombre, ISNULL(a.Origen, N'Sin registro')) AS Usuario,
           CASE WHEN a.IdUsuario IS NULL THEN 1 ELSE 0 END AS SinUsuario
    FROM #A a
    LEFT JOIN Usuario u ON u.Id = a.IdUsuario
    WHERE @Tipo IS NULL OR a.Tipo = @Tipo
    ORDER BY a.Fecha DESC;

    SELECT Tipo, COUNT(*) AS Cantidad FROM #A GROUP BY Tipo ORDER BY Cantidad DESC;

    SELECT a.IdUsuario, ISNULL(u.Nombre, N'Sin usuario (scripts)') AS Usuario, COUNT(*) AS Cantidad
    FROM #A a LEFT JOIN Usuario u ON u.Id = a.IdUsuario
    WHERE @Tipo IS NULL OR a.Tipo = @Tipo
    GROUP BY a.IdUsuario, u.Nombre
    ORDER BY Cantidad DESC;

    DROP TABLE #A;
END
GO


/* -----------------------------------------------------------------
   PRUEBAS
   Un cambio desde aca queda sin usuario, con el programa de origen.
   ----------------------------------------------------------------- */
DECLARE @d DATE = DATEADD(DAY, -30, CAST(GETDATE() AS DATE)), @h DATE = CAST(GETDATE() AS DATE);
EXEC SP_Auditoria_Listar @Desde = @d, @Hasta = @h, @Max = 20;
GO
