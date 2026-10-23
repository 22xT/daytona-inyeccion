USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   76 — CARRITO DE COMPRAS

   Devolucion: la pantalla de reposicion hacia demasiado a la vez
   (sugerir, elegir proveedor, comparar precios y generar pedidos).
   Se separa en dos pasos:

   1. REPOSICION SUGERIDA: que falta. Cada repuesto tiene "Sumar al
      carrito" con la cantidad. No se elige proveedor.
   2. CARRITO: todo lo que hay que pedir, venga de la reposicion o del
      Buscador. Aca se define el proveedor de cada uno (el mas barato
      viene elegido) y se confirma: se suma a los pedidos en armado.

   Lo que esta en el carrito ya no se vuelve a sugerir.
   ================================================================= */


/* -----------------------------------------------------------------
   1. Tabla: un renglon por repuesto
   ----------------------------------------------------------------- */
IF OBJECT_ID('CarritoCompra', 'U') IS NULL
    CREATE TABLE CarritoCompra (
        Id          INT IDENTITY(1,1) PRIMARY KEY,
        IdRepuesto  INT NOT NULL REFERENCES Repuesto(Id),
        Cantidad    INT NOT NULL CHECK (Cantidad > 0 AND Cantidad <= 500),
        IdProveedor INT NULL REFERENCES Proveedor(Id),   -- NULL = el mas barato
        Origen      VARCHAR(20) NOT NULL DEFAULT 'REPOSICION',
        Fecha       DATETIME NOT NULL DEFAULT GETDATE(),
        CONSTRAINT UQ_Carrito_Repuesto UNIQUE (IdRepuesto)
    );
GO


/* -----------------------------------------------------------------
   2. Sumar (si ya estaba, se suma la cantidad)
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Carrito_Agregar', 'P') IS NOT NULL DROP PROCEDURE SP_Carrito_Agregar;
GO
CREATE PROCEDURE SP_Carrito_Agregar
    @IdRepuesto  INT,
    @Cantidad    INT,
    @IdProveedor INT = NULL,
    @Origen      VARCHAR(20) = 'REPOSICION'
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM Repuesto WHERE Id = @IdRepuesto AND Activo = 1)
        THROW 50160, 'El repuesto no existe o esta dado de baja.', 1;
    IF @Cantidad IS NULL OR @Cantidad <= 0 OR @Cantidad > 500
        THROW 50161, 'La cantidad tiene que estar entre 1 y 500.', 1;
    IF @IdProveedor IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Proveedor WHERE Id = @IdProveedor)
        THROW 50162, 'El proveedor no existe.', 1;

    IF EXISTS (SELECT 1 FROM CarritoCompra WHERE IdRepuesto = @IdRepuesto)
    BEGIN
        IF (SELECT Cantidad FROM CarritoCompra WHERE IdRepuesto = @IdRepuesto) + @Cantidad > 500
            THROW 50161, 'En el carrito no puede haber mas de 500 de un mismo repuesto.', 1;
        UPDATE CarritoCompra
        SET Cantidad = Cantidad + @Cantidad,
            IdProveedor = ISNULL(@IdProveedor, IdProveedor)
        WHERE IdRepuesto = @IdRepuesto;
    END
    ELSE
        INSERT INTO CarritoCompra (IdRepuesto, Cantidad, IdProveedor, Origen)
        VALUES (@IdRepuesto, @Cantidad, @IdProveedor, ISNULL(@Origen, 'REPOSICION'));

    SELECT COUNT(*) AS Renglones, ISNULL(SUM(Cantidad), 0) AS Unidades FROM CarritoCompra;
END
GO


/* -----------------------------------------------------------------
   3. Cambiar cantidad o proveedor (cantidad 0 = sacarlo)
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Carrito_Cambiar', 'P') IS NOT NULL DROP PROCEDURE SP_Carrito_Cambiar;
GO
CREATE PROCEDURE SP_Carrito_Cambiar
    @IdRepuesto  INT,
    @Cantidad    INT,
    @IdProveedor INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @Cantidad IS NULL OR @Cantidad < 0 OR @Cantidad > 500
        THROW 50161, 'La cantidad tiene que estar entre 0 y 500.', 1;

    IF @Cantidad = 0
        DELETE FROM CarritoCompra WHERE IdRepuesto = @IdRepuesto;
    ELSE
        UPDATE CarritoCompra SET Cantidad = @Cantidad, IdProveedor = @IdProveedor
        WHERE IdRepuesto = @IdRepuesto;
END
GO


/* -----------------------------------------------------------------
   4. Ver el carrito: el renglon, y las opciones de compra de cada uno
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Carrito_Get', 'P') IS NOT NULL DROP PROCEDURE SP_Carrito_Get;
GO
CREATE PROCEDURE SP_Carrito_Get
AS
BEGIN
    SET NOCOUNT ON;

    SELECT c.IdRepuesto, c.Cantidad, c.IdProveedor AS IdProveedorElegido, c.Origen, c.Fecha,
           r.Codigo, r.Descripcion, r.MarcaFabricante, r.CodigoFabricante, ru.Nombre AS Rubro,
           ISNULL(s.Cantidad, 0) AS Stock, ISNULL(s.StockMinimo, 0) AS Minimo,
           ISNULL(rv.Reservado, 0) AS Encargado
    FROM CarritoCompra c
    INNER JOIN Repuesto r ON r.Id = c.IdRepuesto
    LEFT JOIN Rubro ru ON ru.Id = r.IdRubro
    LEFT JOIN Stock s ON s.IdRepuesto = r.Id
    LEFT JOIN vw_StockReservado rv ON rv.IdRepuesto = r.Id
    ORDER BY c.Fecha;

    SELECT pr.IdRepuesto, pr.IdProveedor, p.RazonSocial AS Proveedor, pr.PrecioCompra AS Precio,
           p.CondicionIva, pr.CodigoProveedor
    FROM ProveedorRepuesto pr
    INNER JOIN CarritoCompra c ON c.IdRepuesto = pr.IdRepuesto
    INNER JOIN Proveedor p ON p.Id = pr.IdProveedor AND p.Activo = 1
    WHERE pr.Activo = 1 AND pr.PrecioCompra > 0
    ORDER BY pr.IdRepuesto, pr.PrecioCompra;
END
GO


/* -----------------------------------------------------------------
   5. Confirmar: todo el carrito pasa a los pedidos en armado, un
      pedido por proveedor. Todo o nada.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Carrito_Confirmar', 'P') IS NOT NULL DROP PROCEDURE SP_Carrito_Confirmar;
GO
CREATE PROCEDURE SP_Carrito_Confirmar
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM CarritoCompra)
        THROW 50163, 'El carrito esta vacio.', 1;

    -- Proveedor de cada renglon: el elegido, o el mas barato
    DECLARE @L PedidoLoteLineaType;
    INSERT INTO @L (IdProveedor, IdRepuesto, Cantidad, PrecioUnitario)
    SELECT x.IdProveedor, c.IdRepuesto, c.Cantidad, x.PrecioCompra
    FROM CarritoCompra c
    CROSS APPLY (SELECT TOP 1 pr.IdProveedor, pr.PrecioCompra
                 FROM ProveedorRepuesto pr INNER JOIN Proveedor p ON p.Id = pr.IdProveedor AND p.Activo = 1
                 WHERE pr.IdRepuesto = c.IdRepuesto AND pr.Activo = 1 AND pr.PrecioCompra > 0
                   AND (c.IdProveedor IS NULL OR pr.IdProveedor = c.IdProveedor)
                 ORDER BY pr.PrecioCompra) x;

    IF (SELECT COUNT(*) FROM @L) < (SELECT COUNT(*) FROM CarritoCompra)
    BEGIN
        DECLARE @sin NVARCHAR(400) = STUFF((
            SELECT ', ' + ISNULL(r.Codigo, CAST(r.Id AS VARCHAR(10)))
            FROM CarritoCompra c INNER JOIN Repuesto r ON r.Id = c.IdRepuesto
            WHERE NOT EXISTS (SELECT 1 FROM @L l WHERE l.IdRepuesto = c.IdRepuesto)
            FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(400)'), 1, 2, '');
        DECLARE @msg NVARCHAR(500) = N'Sin proveedor con precio: ' + @sin + N'. Elegile uno o sacalo del carrito.';
        THROW 50164, @msg, 1;
    END

    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC SP_Pedido_GenerarLote @Lineas = @L;     -- se suma a los pedidos en armado
        DELETE FROM CarritoCompra;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   6. Reposicion: lo que ya esta en el carrito no se vuelve a sugerir
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
        SELECT r.Id AS IdRepuesto, ISNULL(cc.Cantidad, 0) AS EnCarrito, r.Codigo, r.Descripcion,
               r.MarcaFabricante, r.CodigoFabricante, ru.Nombre AS Rubro,
               ISNULL(s.Cantidad, 0) AS Stock, ISNULL(s.StockMinimo, 0) AS Minimo,
               ISNULL(ec.Cant, 0) AS EnCamino,
               ISNULL(rv.Reservado, 0) AS Encargado
        FROM Repuesto r
        LEFT JOIN Rubro ru ON ru.Id = r.IdRubro
        LEFT JOIN Stock s ON s.IdRepuesto = r.Id
        LEFT JOIN EnCamino ec ON ec.IdRepuesto = r.Id
        LEFT JOIN vw_StockReservado rv ON rv.IdRepuesto = r.Id
        LEFT JOIN CarritoCompra cc ON cc.IdRepuesto = r.Id
        WHERE r.Activo = 1
          AND (   (ISNULL(s.StockMinimo, 0) > 0 AND ISNULL(s.Cantidad, 0) <= ISNULL(s.StockMinimo, 0))
               OR ISNULL(rv.Reservado, 0) > 0)
    )
    SELECT b.IdRepuesto, b.Codigo, b.Descripcion, b.MarcaFabricante, b.CodigoFabricante, b.Rubro,
           b.Stock, b.Minimo, b.EnCamino, b.Encargado, b.EnCarrito,
           b.Minimo + b.Encargado - b.Stock - b.EnCamino - b.EnCarrito AS Sugerido,
           CASE WHEN b.Stock - b.Encargado <= 0  THEN 'SIN_STOCK'
                WHEN (b.Stock - b.Encargado) * 2 <= b.Minimo THEN 'CRITICO'
                ELSE 'BAJO' END AS Urgencia
    INTO #Items
    FROM Base b
    WHERE b.Minimo + b.Encargado - b.Stock - b.EnCamino - b.EnCarrito > 0;

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

    -- 3. Bajo minimo pero ya pedidos del todo (no aparecen en la lista)
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

    -- 4. Lo que ya esta pedido de cada repuesto de la lista: en que pedido y cuando llega
    SELECT dp.IdRepuesto, p.Id AS IdPedido, pv.RazonSocial AS Proveedor,
           SUM(dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada) AS Cantidad,
           CASE WHEN p.FechaEnvio IS NULL THEN 1 ELSE 0 END AS EnArmado,
           p.FechaEnvio,
           CASE WHEN p.FechaEnvio IS NULL THEN NULL
                ELSE dbo.fn_LlegadaEstimada(p.FechaEnvio, pv.DiasEntrega) END AS LlegadaEstimada
    FROM DetallePedido dp
    INNER JOIN Pedido p     ON p.Id = dp.IdPedido
    INNER JOIN Proveedor pv ON pv.Id = p.IdProveedor
    INNER JOIN #Items i     ON i.IdRepuesto = dp.IdRepuesto
    WHERE p.IdEstado = 1 AND dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada > 0
    GROUP BY dp.IdRepuesto, p.Id, pv.RazonSocial, p.FechaEnvio, pv.DiasEntrega
    ORDER BY dp.IdRepuesto, p.Id;
END
GO


/* -----------------------------------------------------------------
   7. Menu: el globo de Compras descuenta el carrito, y el carrito
      tiene su propio numero
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Indicadores_Menu', 'P') IS NOT NULL DROP PROCEDURE SP_Indicadores_Menu;
GO
CREATE PROCEDURE SP_Indicadores_Menu
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @DiasRetiro INT = ISNULL(TRY_CAST((SELECT Valor FROM ParametroSistema WHERE Clave = 'DiasRetiroEncargo') AS INT), 7);

    SELECT
        -- Mismo calculo que la pantalla de reposicion: minimo + encargado
        -- - stock - lo que ya esta pedido. Estar EN el minimo esta bien, y
        -- lo que ya se pidio no se vuelve a contar.
        (SELECT COUNT(*)
         FROM Repuesto r
         LEFT JOIN Stock s ON s.IdRepuesto = r.Id
         LEFT JOIN vw_StockReservado rv ON rv.IdRepuesto = r.Id
         OUTER APPLY (SELECT SUM(dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada) AS Cant
                      FROM DetallePedido dp INNER JOIN Pedido p ON p.Id = dp.IdPedido
                      WHERE p.IdEstado = 1 AND dp.IdRepuesto = r.Id
                        AND dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada > 0) ec
         WHERE r.Activo = 1
           AND ISNULL(s.StockMinimo, 0) + ISNULL(rv.Reservado, 0)
               - ISNULL(s.Cantidad, 0) - ISNULL(ec.Cant, 0)
               - ISNULL((SELECT cc.Cantidad FROM CarritoCompra cc WHERE cc.IdRepuesto = r.Id), 0) > 0) AS Reposicion,

        (SELECT COUNT(*) FROM CarritoCompra)              AS EnCarrito,

        (SELECT COUNT(*)
         FROM Repuesto r
         INNER JOIN Stock s ON s.IdRepuesto = r.Id
         WHERE r.Activo = 1 AND s.Cantidad <= 0)        AS SinStock,

        (SELECT COUNT(*) FROM Pedido WHERE IdEstado = 1) AS PedidosPendientes,

        (SELECT COUNT(*) FROM (
            SELECT m.IdCliente
            FROM MovimientoCuentaCorriente m
            GROUP BY m.IdCliente
            HAVING SUM(m.Monto) > 0
         ) q)                                            AS ClientesConDeuda,

        (SELECT ISNULL(SUM(q.Saldo), 0) FROM (
            SELECT SUM(m.Monto) AS Saldo
            FROM MovimientoCuentaCorriente m
            GROUP BY m.IdCliente
            HAVING SUM(m.Monto) > 0
         ) q)                                            AS TotalACobrar,

        -- Nuevos
        (SELECT COUNT(*) FROM Pedido WHERE IdEstado = 1 AND FechaEnvio IS NULL) AS PedidosEnArmado,

        (SELECT COUNT(*) FROM Encargo e INNER JOIN vw_EncargoSituacion si ON si.IdEncargo = e.Id
         WHERE e.Estado = 'PENDIENTE' AND si.Disponibilidad = 'EN_STOCK')          AS EncargosParaAvisar,

        (SELECT COUNT(*) FROM Encargo e INNER JOIN vw_EncargoSituacion si ON si.IdEncargo = e.Id
         WHERE e.Estado IN ('PENDIENTE', 'AVISADO') AND si.Disponibilidad <> 'EN_STOCK'
           AND si.LlegadaEstimada < CAST(GETDATE() AS DATE))                       AS EncargosAtrasados,

        (SELECT COUNT(*) FROM Encargo e INNER JOIN vw_EncargoSituacion si ON si.IdEncargo = e.Id
         WHERE e.Estado = 'AVISADO' AND si.Disponibilidad = 'EN_STOCK'
           AND e.FechaAviso < DATEADD(DAY, -@DiasRetiro, GETDATE()))              AS EncargosNoRetiro;
END
GO

EXEC SP_Carrito_Get;
GO
