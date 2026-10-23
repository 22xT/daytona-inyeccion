USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   59 — GENERAR PEDIDOS TODO O NADA

   La reposicion sugerida creaba los pedidos con varios envios
   sucesivos: primero la cabecera, despues cada renglon. Si algo
   fallaba a mitad de camino (se corta la red, un renglon invalido),
   quedaba un pedido creado con la mitad de los renglones.

   Ahora la pantalla manda todos los renglones juntos y la base crea
   todos los pedidos, uno por proveedor, dentro de una transaccion.
   O se crean todos completos, o no se crea ninguno.

   De paso se corrige SP_Pedido_I (alta manual), que devolvia
   MAX(Id) en vez del Id que acababa de crear: con dos altas al mismo
   tiempo, una podia recibir el pedido de la otra.
   ================================================================= */


/* -----------------------------------------------------------------
   1. Renglones a pedir
   ----------------------------------------------------------------- */
IF TYPE_ID('PedidoLoteLineaType') IS NULL
    CREATE TYPE PedidoLoteLineaType AS TABLE (
        IdProveedor    INT           NOT NULL,
        IdRepuesto     INT           NOT NULL,
        Cantidad       INT           NOT NULL,
        PrecioUnitario DECIMAL(10,2) NOT NULL
    );
GO


/* -----------------------------------------------------------------
   2. Crear un pedido por proveedor, todo junto
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Pedido_GenerarLote', 'P') IS NOT NULL DROP PROCEDURE SP_Pedido_GenerarLote;
GO
CREATE PROCEDURE SP_Pedido_GenerarLote
    @Lineas PedidoLoteLineaType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /* Validaciones antes de tocar nada */
    IF NOT EXISTS (SELECT 1 FROM @Lineas)
        THROW 50100, 'No hay nada para pedir.', 1;

    IF EXISTS (SELECT 1 FROM @Lineas WHERE Cantidad <= 0 OR Cantidad > 500)
        THROW 50101, 'Cada cantidad tiene que estar entre 1 y 500.', 1;

    IF EXISTS (SELECT 1 FROM @Lineas WHERE PrecioUnitario < 0)
        THROW 50102, 'Hay un precio negativo.', 1;

    IF EXISTS (SELECT 1 FROM @Lineas l WHERE NOT EXISTS (SELECT 1 FROM Proveedor p WHERE p.Id = l.IdProveedor))
        THROW 50103, 'Uno de los proveedores no existe.', 1;

    IF EXISTS (SELECT 1 FROM @Lineas l WHERE NOT EXISTS (SELECT 1 FROM Repuesto r WHERE r.Id = l.IdRepuesto))
        THROW 50104, 'Uno de los repuestos no existe.', 1;

    -- El mismo repuesto dos veces para el mismo proveedor: se avisa en vez de sumar a escondidas
    IF EXISTS (SELECT IdProveedor, IdRepuesto FROM @Lineas GROUP BY IdProveedor, IdRepuesto HAVING COUNT(*) > 1)
        THROW 50105, 'Un repuesto aparece dos veces para el mismo proveedor.', 1;

    DECLARE @Creados TABLE (IdPedido INT NOT NULL, IdProveedor INT NOT NULL);

    BEGIN TRY
        BEGIN TRANSACTION;

        /* Una cabecera por proveedor. MERGE con una condicion que nunca se
           cumple es la forma de usar OUTPUT con columnas del origen
           (IdProveedor) y obtener el Id real de cada pedido creado. */
        MERGE Pedido AS destino
        USING (SELECT IdProveedor, SUM(Cantidad * PrecioUnitario) AS Total
               FROM @Lineas GROUP BY IdProveedor) AS origen
        ON 1 = 0
        WHEN NOT MATCHED THEN
            INSERT (IdProveedor, Total, IdEstado)
            VALUES (origen.IdProveedor, origen.Total, 1)
        OUTPUT inserted.Id, origen.IdProveedor INTO @Creados (IdPedido, IdProveedor);

        -- Renglones (el Subtotal es una columna calculada: no se inserta)
        INSERT INTO DetallePedido (IdPedido, IdRepuesto, Cantidad, PrecioUnitario)
        SELECT c.IdPedido, l.IdRepuesto, l.Cantidad, l.PrecioUnitario
        FROM @Lineas l
        INNER JOIN @Creados c ON c.IdProveedor = l.IdProveedor;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    -- Lo creado, para mostrarlo en pantalla
    SELECT c.IdPedido, c.IdProveedor, pr.RazonSocial AS Proveedor, p.Total,
           (SELECT COUNT(*) FROM DetallePedido d WHERE d.IdPedido = c.IdPedido) AS Renglones
    FROM @Creados c
    INNER JOIN Pedido p     ON p.Id = c.IdPedido
    INNER JOIN Proveedor pr ON pr.Id = c.IdProveedor
    ORDER BY pr.RazonSocial;
END
GO


/* -----------------------------------------------------------------
   3. Alta manual: devolver el Id propio, no el ultimo de la tabla
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Pedido_I', 'P') IS NOT NULL DROP PROCEDURE SP_Pedido_I;
GO
CREATE PROCEDURE SP_Pedido_I
    @IdProveedor INT,
    @Total DECIMAL(10,2)
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO Pedido (IdProveedor, Total, IdEstado)
    VALUES (@IdProveedor, @Total, 1);   -- 1 = Pendiente

    SELECT CAST(SCOPE_IDENTITY() AS INT) AS NuevoId;
END
GO


/* -----------------------------------------------------------------
   PRUEBA (no crea nada: todo dentro de una transaccion que se deshace)
   ----------------------------------------------------------------- */
BEGIN TRANSACTION;
    DECLARE @prueba PedidoLoteLineaType;
    INSERT INTO @prueba (IdProveedor, IdRepuesto, Cantidad, PrecioUnitario)
    SELECT TOP 2 (SELECT TOP 1 Id FROM Proveedor ORDER BY Id), r.Id, 1, 100
    FROM Repuesto r ORDER BY r.Id;

    EXEC SP_Pedido_GenerarLote @Lineas = @prueba;   -- tiene que mostrar 1 pedido con 2 renglones
ROLLBACK TRANSACTION;
GO
