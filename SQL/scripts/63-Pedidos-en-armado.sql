USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   63 — PEDIDOS EN ARMADO Y COMPRAS DESDE EL BUSCADOR

   PROCESO REAL
   Durante el dia se van juntando cosas para pedirle a cada proveedor:
   un encargo de un cliente, algo que se vio en el buscador y conviene
   tener, lo que sugiere la reposicion. Cuando se decide, se carga todo
   en la web del proveedor y llega al dia habil siguiente. Puede haber
   un pedido a la mañana y otro a la tarde al mismo proveedor.

   COMO QUEDA
   - Un pedido sin FechaEnvio esta EN ARMADO. Hay uno por proveedor a
     la vez: todo lo que se pide va sumando renglones a ese.
   - "Enviar" le pone FechaEnvio (= ya se cargo en la web). Lo proximo
     que se pida arranca otro pedido en armado.
   - Los pedidos existentes se dan por enviados en su fecha.
   - La llegada estimada es el dia habil siguiente al envio (o los dias
     que tenga cargado el proveedor en DiasEntrega).
   - Un encargo tomado desde el buscador suma su renglon al pedido en
     armado de ese proveedor y queda vinculado a ese renglon.
   - La reposicion sugerida tambien suma a los pedidos en armado.
   - Al recibir, el sistema lista los encargos que ya se pueden
     separar y avisar.

   Requiere los scripts 59, 61 y 62.
   ================================================================= */


/* -----------------------------------------------------------------
   1. Columnas nuevas
   ----------------------------------------------------------------- */
IF COL_LENGTH('Pedido', 'FechaEnvio') IS NULL
BEGIN
    ALTER TABLE Pedido ADD FechaEnvio DATETIME NULL;
    -- Lo que ya existia se considera enviado en su fecha. Solo al crear
    -- la columna: si el script se corre de nuevo, no toca los en armado.
    EXEC ('UPDATE Pedido SET FechaEnvio = Fecha');
END
GO

IF COL_LENGTH('Proveedor', 'DiasEntrega') IS NULL
    ALTER TABLE Proveedor ADD DiasEntrega INT NOT NULL CONSTRAINT DF_Proveedor_DiasEntrega DEFAULT 1;
GO

IF COL_LENGTH('EncargoDetalle', 'IdDetallePedido') IS NULL
    ALTER TABLE EncargoDetalle ADD IdDetallePedido INT NULL CONSTRAINT FK_EncDet_DetPed REFERENCES DetallePedido(Id);
GO


/* -----------------------------------------------------------------
   2. Llegada estimada: N dias habiles despues (sin sabados ni domingos)
   ----------------------------------------------------------------- */
IF OBJECT_ID('fn_LlegadaEstimada', 'FN') IS NOT NULL DROP FUNCTION fn_LlegadaEstimada;
GO
CREATE FUNCTION fn_LlegadaEstimada (@Desde DATETIME, @Dias INT)
RETURNS DATE
AS
BEGIN
    DECLARE @d DATE = CAST(@Desde AS DATE), @n INT = 0;
    IF @Dias IS NULL OR @Dias < 1 SET @Dias = 1;
    WHILE @n < @Dias
    BEGIN
        SET @d = DATEADD(DAY, 1, @d);
        -- 01/01/1900 fue lunes: 0..4 = lunes a viernes, 5 y 6 = fin de semana
        IF DATEDIFF(DAY, '19000101', @d) % 7 < 5 SET @n = @n + 1;
    END
    RETURN @d;
END
GO


/* -----------------------------------------------------------------
   3. Sumar un renglon al pedido en armado del proveedor
   Si no hay pedido en armado, lo crea. Si el repuesto ya esta en el
   pedido, suma la cantidad. Sirve suelto o dentro de una transaccion
   de quien lo llama.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Pedido_AgregarRenglon', 'P') IS NOT NULL DROP PROCEDURE SP_Pedido_AgregarRenglon;
GO
CREATE PROCEDURE SP_Pedido_AgregarRenglon
    @IdProveedor    INT,
    @IdRepuesto     INT,
    @Cantidad       INT,
    @PrecioUnitario DECIMAL(10,2) = NULL,   -- si no viene, el costo de la lista del proveedor
    @IdPedido       INT OUTPUT,
    @IdDetalle      INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Cantidad IS NULL OR @Cantidad <= 0 OR @Cantidad > 500
        THROW 50170, 'La cantidad tiene que estar entre 1 y 500.', 1;
    IF NOT EXISTS (SELECT 1 FROM Proveedor WHERE Id = @IdProveedor AND Activo = 1)
        THROW 50171, 'El proveedor no existe o está inactivo.', 1;
    IF NOT EXISTS (SELECT 1 FROM Repuesto WHERE Id = @IdRepuesto)
        THROW 50172, 'El repuesto no existe.', 1;

    IF @PrecioUnitario IS NULL
        SELECT TOP 1 @PrecioUnitario = PrecioCompra FROM ProveedorRepuesto
        WHERE IdProveedor = @IdProveedor AND IdRepuesto = @IdRepuesto AND Activo = 1
        ORDER BY PrecioCompra;
    IF @PrecioUnitario IS NULL SET @PrecioUnitario = 0;

    DECLARE @propia BIT = 0;
    IF @@TRANCOUNT = 0 BEGIN BEGIN TRANSACTION; SET @propia = 1; END

    BEGIN TRY
        SET @IdPedido = NULL; SET @IdDetalle = NULL;

        SELECT TOP 1 @IdPedido = Id FROM Pedido WITH (UPDLOCK, HOLDLOCK)
        WHERE IdProveedor = @IdProveedor AND IdEstado = 1 AND FechaEnvio IS NULL
        ORDER BY Id DESC;

        IF @IdPedido IS NULL
        BEGIN
            INSERT INTO Pedido (IdProveedor, Total, IdEstado) VALUES (@IdProveedor, 0, 1);
            SET @IdPedido = CAST(SCOPE_IDENTITY() AS INT);
        END

        SELECT TOP 1 @IdDetalle = Id FROM DetallePedido WITH (UPDLOCK)
        WHERE IdPedido = @IdPedido AND IdRepuesto = @IdRepuesto;

        IF @IdDetalle IS NULL
        BEGIN
            INSERT INTO DetallePedido (IdPedido, IdRepuesto, Cantidad, PrecioUnitario)
            VALUES (@IdPedido, @IdRepuesto, @Cantidad, @PrecioUnitario);
            SET @IdDetalle = CAST(SCOPE_IDENTITY() AS INT);
        END
        ELSE
            UPDATE DetallePedido SET Cantidad = Cantidad + @Cantidad WHERE Id = @IdDetalle;

        UPDATE Pedido
        SET Total = (SELECT SUM(Cantidad * PrecioUnitario) FROM DetallePedido WHERE IdPedido = @IdPedido)
        WHERE Id = @IdPedido;

        IF @propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   4. "Pedir" desde el buscador
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Pedido_Pedir', 'P') IS NOT NULL DROP PROCEDURE SP_Pedido_Pedir;
GO
CREATE PROCEDURE SP_Pedido_Pedir
    @IdProveedor INT,
    @IdRepuesto  INT,
    @Cantidad    INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IdPedido INT, @IdDetalle INT;
    EXEC SP_Pedido_AgregarRenglon @IdProveedor = @IdProveedor, @IdRepuesto = @IdRepuesto, @Cantidad = @Cantidad,
         @IdPedido = @IdPedido OUTPUT, @IdDetalle = @IdDetalle OUTPUT;

    SELECT p.Id AS IdPedido, pr.RazonSocial AS Proveedor, p.Total,
           (SELECT COUNT(*) FROM DetallePedido d WHERE d.IdPedido = p.Id) AS Renglones
    FROM Pedido p INNER JOIN Proveedor pr ON pr.Id = p.IdProveedor
    WHERE p.Id = @IdPedido;
END
GO


/* -----------------------------------------------------------------
   5. Reposicion sugerida: ahora suma a los pedidos en armado
   (todo o nada, como en el script 59)
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Pedido_GenerarLote', 'P') IS NOT NULL DROP PROCEDURE SP_Pedido_GenerarLote;
GO
CREATE PROCEDURE SP_Pedido_GenerarLote
    @Lineas PedidoLoteLineaType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM @Lineas)
        THROW 50100, 'No hay nada para pedir.', 1;
    IF EXISTS (SELECT 1 FROM @Lineas WHERE Cantidad <= 0 OR Cantidad > 500)
        THROW 50101, 'Cada cantidad tiene que estar entre 1 y 500.', 1;
    IF EXISTS (SELECT 1 FROM @Lineas WHERE PrecioUnitario < 0)
        THROW 50102, 'Hay un precio negativo.', 1;
    IF EXISTS (SELECT IdProveedor, IdRepuesto FROM @Lineas GROUP BY IdProveedor, IdRepuesto HAVING COUNT(*) > 1)
        THROW 50105, 'Un repuesto aparece dos veces para el mismo proveedor.', 1;

    DECLARE @Tocados TABLE (IdPedido INT PRIMARY KEY);
    DECLARE @prov INT, @rep INT, @cant INT, @precio DECIMAL(10,2), @ped INT, @det INT;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE c CURSOR LOCAL FAST_FORWARD FOR
            SELECT IdProveedor, IdRepuesto, Cantidad, PrecioUnitario FROM @Lineas ORDER BY IdProveedor;
        OPEN c;
        FETCH NEXT FROM c INTO @prov, @rep, @cant, @precio;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC SP_Pedido_AgregarRenglon @IdProveedor = @prov, @IdRepuesto = @rep, @Cantidad = @cant,
                 @PrecioUnitario = @precio, @IdPedido = @ped OUTPUT, @IdDetalle = @det OUTPUT;
            IF NOT EXISTS (SELECT 1 FROM @Tocados WHERE IdPedido = @ped) INSERT INTO @Tocados VALUES (@ped);
            FETCH NEXT FROM c INTO @prov, @rep, @cant, @precio;
        END
        CLOSE c; DEALLOCATE c;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    SELECT p.Id AS IdPedido, p.IdProveedor, pr.RazonSocial AS Proveedor, p.Total,
           (SELECT COUNT(*) FROM DetallePedido d WHERE d.IdPedido = p.Id) AS Renglones
    FROM @Tocados t
    INNER JOIN Pedido p     ON p.Id = t.IdPedido
    INNER JOIN Proveedor pr ON pr.Id = p.IdProveedor
    ORDER BY pr.RazonSocial;
END
GO


/* -----------------------------------------------------------------
   6. Enviar: ya se cargo en la web del proveedor
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Pedido_Enviar', 'P') IS NOT NULL DROP PROCEDURE SP_Pedido_Enviar;
GO
CREATE PROCEDURE SP_Pedido_Enviar @Id INT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM DetallePedido WHERE IdPedido = @Id)
        THROW 50180, 'El pedido no tiene renglones.', 1;

    UPDATE Pedido SET FechaEnvio = GETDATE()
    WHERE Id = @Id AND IdEstado = 1 AND FechaEnvio IS NULL;
    IF @@ROWCOUNT = 0
        THROW 50181, 'Ese pedido ya fue enviado o está cerrado.', 1;

    SELECT p.Id, p.FechaEnvio, dbo.fn_LlegadaEstimada(p.FechaEnvio, pr.DiasEntrega) AS LlegadaEstimada
    FROM Pedido p INNER JOIN Proveedor pr ON pr.Id = p.IdProveedor
    WHERE p.Id = @Id;
END
GO

-- Si llega mercaderia de un pedido que nadie marco como enviado, se da por enviado
IF OBJECT_ID('TR_RecepcionPedido_MarcarEnviado', 'TR') IS NOT NULL DROP TRIGGER TR_RecepcionPedido_MarcarEnviado;
GO
CREATE TRIGGER TR_RecepcionPedido_MarcarEnviado ON RecepcionPedido
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE p SET FechaEnvio = GETDATE()
    FROM Pedido p INNER JOIN inserted i ON i.IdPedido = p.Id
    WHERE p.FechaEnvio IS NULL;
END
GO


/* -----------------------------------------------------------------
   7. Lista para cargar en la web del proveedor
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Pedido_ListaWeb', 'P') IS NOT NULL DROP PROCEDURE SP_Pedido_ListaWeb;
GO
CREATE PROCEDURE SP_Pedido_ListaWeb @Id INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT d.Id AS IdDetalle,
           ISNULL((SELECT TOP 1 pr.CodigoProveedor FROM ProveedorRepuesto pr
                   WHERE pr.IdRepuesto = d.IdRepuesto AND pr.IdProveedor = p.IdProveedor AND pr.Activo = 1), r.Codigo) AS Codigo,
           r.Descripcion, d.Cantidad, d.PrecioUnitario,
           -- Para quien es: si sale de un encargo, el nombre del cliente
           (SELECT TOP 1 e.Nombre FROM EncargoDetalle ed INNER JOIN Encargo e ON e.Id = ed.IdEncargo
            WHERE ed.IdDetallePedido = d.Id) AS ParaCliente
    FROM DetallePedido d
    INNER JOIN Pedido p   ON p.Id = d.IdPedido
    INNER JOIN Repuesto r ON r.Id = d.IdRepuesto
    WHERE d.IdPedido = @Id
    ORDER BY r.Descripcion;
END
GO


/* -----------------------------------------------------------------
   8. Listado de pedidos con el estado de envio
   (mismas columnas que antes, mas las nuevas al final)
   ----------------------------------------------------------------- */
ALTER PROCEDURE SP_Pedido_GetAll
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        p.Id,
        p.Fecha,
        pr.RazonSocial AS Proveedor,
        p.Total,
        e.Nombre AS Estado,
        p.IdProveedor,
        p.IdEstado,
        p.FechaEnvio,
        CASE WHEN p.IdEstado = 1 AND p.FechaEnvio IS NULL THEN 1 ELSE 0 END AS EnArmado,
        CASE WHEN p.FechaEnvio IS NULL THEN NULL
             ELSE dbo.fn_LlegadaEstimada(p.FechaEnvio, pr.DiasEntrega) END AS LlegadaEstimada,
        (SELECT COUNT(DISTINCT ed.IdEncargo) FROM EncargoDetalle ed
         INNER JOIN DetallePedido d ON d.Id = ed.IdDetallePedido
         WHERE d.IdPedido = p.Id) AS Encargos
    FROM Pedido p
    INNER JOIN Proveedor pr ON p.IdProveedor = pr.Id
    INNER JOIN EstadoPedido e ON p.IdEstado = e.Id
    ORDER BY CASE WHEN p.IdEstado = 1 AND p.FechaEnvio IS NULL THEN 0 ELSE 1 END, p.Fecha DESC;
END
GO


/* -----------------------------------------------------------------
   9. A quien se le puede comprar un repuesto (para "Pedir" y
      "Encargar" sobre un repuesto propio)
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Repuesto_OpcionesCompra', 'P') IS NOT NULL DROP PROCEDURE SP_Repuesto_OpcionesCompra;
GO
CREATE PROCEDURE SP_Repuesto_OpcionesCompra @IdRepuesto INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT pr.IdProveedor, p.RazonSocial AS Proveedor, pr.CodigoProveedor, pr.PrecioCompra,
           p.DiasEntrega, dbo.fn_LlegadaEstimada(GETDATE(), p.DiasEntrega) AS LlegadaEstimada
    FROM ProveedorRepuesto pr
    INNER JOIN Proveedor p ON p.Id = pr.IdProveedor AND p.Activo = 1
    WHERE pr.IdRepuesto = @IdRepuesto AND pr.Activo = 1 AND pr.PrecioCompra > 0
    ORDER BY pr.PrecioCompra;
END
GO


/* -----------------------------------------------------------------
   10. Encargo: si se indica proveedor, se pide en el mismo momento
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Encargo_I', 'P') IS NOT NULL DROP PROCEDURE SP_Encargo_I;
GO
CREATE PROCEDURE SP_Encargo_I
    @IdCliente         INT = NULL,
    @Nombre            NVARCHAR(80),
    @Telefono          NVARCHAR(30),
    @Observacion       NVARCHAR(250) = NULL,
    @Lineas            EncargoLineaType READONLY,
    @IdMedioSena       INT = NULL,
    @MontoSena         DECIMAL(12,2) = NULL,
    @IdUsuario         INT,
    @IdProveedorPedido INT = NULL       -- si viene, se suma al pedido en armado de ese proveedor
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Nombre = LTRIM(RTRIM(ISNULL(@Nombre, '')));
    SET @Telefono = LTRIM(RTRIM(ISNULL(@Telefono, '')));

    IF @IdCliente IS NOT NULL
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM Cliente WHERE Id = @IdCliente)
            THROW 50120, 'El cliente no existe.', 1;
        IF @Nombre = '' SELECT @Nombre = LTRIM(RTRIM(ISNULL(Apellido, '') + ', ' + ISNULL(Nombre, ''))) FROM Cliente WHERE Id = @IdCliente;
        IF @Telefono = '' SELECT @Telefono = ISNULL(Telefono, '') FROM Cliente WHERE Id = @IdCliente;
    END

    IF LEN(@Nombre) < 2
        THROW 50121, 'Falta el nombre del cliente.', 1;
    IF LEN(@Telefono) < 6
        THROW 50122, 'Falta el teléfono: es para avisarle cuando llegue.', 1;
    IF NOT EXISTS (SELECT 1 FROM @Lineas)
        THROW 50123, 'Indicá qué repuesto encarga.', 1;
    IF EXISTS (SELECT 1 FROM @Lineas WHERE Cantidad <= 0 OR PrecioPactado < 0)
        THROW 50124, 'Revisá cantidades y precios.', 1;
    IF EXISTS (SELECT IdRepuesto FROM @Lineas GROUP BY IdRepuesto HAVING COUNT(*) > 1)
        THROW 50125, 'Un repuesto aparece dos veces.', 1;
    IF EXISTS (SELECT 1 FROM @Lineas l WHERE NOT EXISTS (SELECT 1 FROM Repuesto r WHERE r.Id = l.IdRepuesto))
        THROW 50126, 'Uno de los repuestos no existe.', 1;
    IF @IdProveedorPedido IS NOT NULL AND EXISTS (
        SELECT 1 FROM @Lineas l WHERE NOT EXISTS (SELECT 1 FROM ProveedorRepuesto pr
            WHERE pr.IdRepuesto = l.IdRepuesto AND pr.IdProveedor = @IdProveedorPedido AND pr.Activo = 1))
        THROW 50129, 'Ese proveedor no tiene el repuesto en su lista.', 1;

    DECLARE @Total DECIMAL(12,2) = (SELECT SUM(Cantidad * PrecioPactado) FROM @Lineas);
    IF ISNULL(@MontoSena, 0) > 0 AND @MontoSena > @Total
        THROW 50127, 'La seña no puede superar el total del encargo.', 1;
    IF ISNULL(@MontoSena, 0) > 0 AND @IdMedioSena IS NULL
        THROW 50128, 'Elegí con qué medio paga la seña.', 1;

    DECLARE @IdPedido INT = NULL;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO Encargo (IdCliente, Nombre, Telefono, Observacion, IdUsuario)
        VALUES (@IdCliente, @Nombre, @Telefono, NULLIF(LTRIM(RTRIM(@Observacion)), ''), @IdUsuario);
        DECLARE @Id INT = SCOPE_IDENTITY();

        INSERT INTO EncargoDetalle (IdEncargo, IdRepuesto, Cantidad, PrecioPactado)
        SELECT @Id, IdRepuesto, Cantidad, PrecioPactado FROM @Lineas;

        IF @IdProveedorPedido IS NOT NULL
        BEGIN
            DECLARE @dId INT, @dRep INT, @dCant INT, @det INT;
            DECLARE cEnc CURSOR LOCAL FAST_FORWARD FOR
                SELECT Id, IdRepuesto, Cantidad FROM EncargoDetalle WHERE IdEncargo = @Id;
            OPEN cEnc;
            FETCH NEXT FROM cEnc INTO @dId, @dRep, @dCant;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                EXEC SP_Pedido_AgregarRenglon @IdProveedor = @IdProveedorPedido, @IdRepuesto = @dRep, @Cantidad = @dCant,
                     @IdPedido = @IdPedido OUTPUT, @IdDetalle = @det OUTPUT;
                UPDATE EncargoDetalle SET IdDetallePedido = @det WHERE Id = @dId;
                FETCH NEXT FROM cEnc INTO @dId, @dRep, @dCant;
            END
            CLOSE cEnc; DEALLOCATE cEnc;
        END

        IF ISNULL(@MontoSena, 0) > 0
            EXEC SP_Encargo_RegistrarSena @IdEncargo = @Id, @IdMedioPago = @IdMedioSena, @Monto = @MontoSena, @IdUsuario = @IdUsuario;

        COMMIT TRANSACTION;

        SELECT @Id AS IdEncargo, @IdPedido AS IdPedido,
               CASE WHEN @IdProveedorPedido IS NULL THEN NULL
                    ELSE dbo.fn_LlegadaEstimada(GETDATE(), (SELECT DiasEntrega FROM Proveedor WHERE Id = @IdProveedorPedido)) END AS LlegadaEstimada;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   11. Situacion de cada encargo, renglon por renglon
     EN_STOCK : hay stock para todo                 -> avisar y entregar
     PEDIDO   : lo que falta esta en un pedido enviado
     EN_ARMADO: lo que falta esta en un pedido todavia sin enviar
     SIN_PEDIR: falta algo que nadie pidio
   Atrasado: paso la llegada estimada y todavia no hay stock.
   ----------------------------------------------------------------- */
IF OBJECT_ID('vw_EncargoSituacion', 'V') IS NOT NULL DROP VIEW vw_EncargoSituacion;
GO
CREATE VIEW vw_EncargoSituacion
AS
WITH Pend AS (
    SELECT dp.IdRepuesto,
           SUM(CASE WHEN p.FechaEnvio IS NOT NULL THEN dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada ELSE 0 END) AS Enviado,
           SUM(CASE WHEN p.FechaEnvio IS NULL     THEN dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada ELSE 0 END) AS EnArmado
    FROM DetallePedido dp INNER JOIN Pedido p ON p.Id = dp.IdPedido
    WHERE p.IdEstado = 1
    GROUP BY dp.IdRepuesto
),
Lin AS (
    SELECT d.IdEncargo,
           CASE WHEN ISNULL(s.Cantidad, 0) >= d.Cantidad THEN 0
                WHEN ISNULL(s.Cantidad, 0) + ISNULL(pd.Enviado, 0) >= d.Cantidad THEN 1
                WHEN ISNULL(s.Cantidad, 0) + ISNULL(pd.Enviado, 0) + ISNULL(pd.EnArmado, 0) >= d.Cantidad THEN 2
                ELSE 3 END AS Nivel,
           -- Llegada estimada del renglon, si esta vinculado a un pedido
           CASE WHEN d.IdDetallePedido IS NULL THEN NULL
                ELSE dbo.fn_LlegadaEstimada(ISNULL(pp.FechaEnvio, GETDATE()), prv.DiasEntrega) END AS Llegada
    FROM EncargoDetalle d
    LEFT JOIN Stock s ON s.IdRepuesto = d.IdRepuesto
    LEFT JOIN Pend pd ON pd.IdRepuesto = d.IdRepuesto
    LEFT JOIN DetallePedido dpp ON dpp.Id = d.IdDetallePedido
    LEFT JOIN Pedido pp ON pp.Id = dpp.IdPedido
    LEFT JOIN Proveedor prv ON prv.Id = pp.IdProveedor
)
SELECT IdEncargo,
       CASE MAX(Nivel) WHEN 0 THEN 'EN_STOCK' WHEN 1 THEN 'PEDIDO' WHEN 2 THEN 'EN_ARMADO' ELSE 'SIN_PEDIR' END AS Disponibilidad,
       MAX(Llegada) AS LlegadaEstimada
FROM Lin
GROUP BY IdEncargo;
GO

IF OBJECT_ID('SP_Encargo_GetAll', 'P') IS NOT NULL DROP PROCEDURE SP_Encargo_GetAll;
GO
CREATE PROCEDURE SP_Encargo_GetAll
    @Abiertos BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    SELECT e.Id, e.Fecha, e.Nombre, e.Telefono, e.IdCliente, e.Observacion, e.Estado,
           e.FechaAviso, e.IdVenta, e.FechaEntrega, e.FechaCancelacion, e.ResolucionSena,
           l.Total, l.Renglones, l.Primero,
           ISNULL((SELECT SUM(Monto) FROM EncargoSena es WHERE es.IdEncargo = e.Id), 0) AS Sena,
           CASE WHEN e.Estado IN ('ENTREGADO', 'CANCELADO') THEN NULL ELSE si.Disponibilidad END AS Disponibilidad,
           si.LlegadaEstimada,
           CASE WHEN e.Estado IN ('PENDIENTE', 'AVISADO') AND si.Disponibilidad <> 'EN_STOCK'
                     AND si.LlegadaEstimada < CAST(GETDATE() AS DATE) THEN 1 ELSE 0 END AS Atrasado,
           DATEDIFF(DAY, e.Fecha, GETDATE()) AS Dias
    FROM Encargo e
    INNER JOIN (SELECT d.IdEncargo, SUM(d.Cantidad * d.PrecioPactado) AS Total, COUNT(*) AS Renglones,
                       MIN(r.Descripcion) AS Primero
                FROM EncargoDetalle d INNER JOIN Repuesto r ON r.Id = d.IdRepuesto
                GROUP BY d.IdEncargo) l ON l.IdEncargo = e.Id
    LEFT JOIN vw_EncargoSituacion si ON si.IdEncargo = e.Id
    WHERE (@Abiertos = 1 AND e.Estado IN ('PENDIENTE', 'AVISADO'))
       OR (@Abiertos = 0 AND e.Fecha >= DATEADD(DAY, -90, GETDATE()))
    ORDER BY CASE e.Estado WHEN 'PENDIENTE' THEN 1 WHEN 'AVISADO' THEN 2 ELSE 3 END, e.Fecha;

    SELECT ISNULL(-SUM(CASE WHEN m.Tipo = 'Ingreso' THEN m.Monto ELSE -m.Monto END), 0) AS SenasPendientes
    FROM MovimientoCuentaFinanciera m
    INNER JOIN CuentaFinanciera c ON c.Id = m.IdCuentaFinanciera
    WHERE c.Codigo = 'SENAS';
END
GO

IF OBJECT_ID('SP_Encargo_Get', 'P') IS NOT NULL DROP PROCEDURE SP_Encargo_Get;
GO
CREATE PROCEDURE SP_Encargo_Get @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT e.*, u.Nombre AS Usuario,
           ISNULL((SELECT SUM(Monto) FROM EncargoSena es WHERE es.IdEncargo = e.Id), 0) AS Sena,
           (SELECT SUM(Cantidad * PrecioPactado) FROM EncargoDetalle d WHERE d.IdEncargo = e.Id) AS Total,
           c.CuentaCorriente AS ClienteConCuenta,
           CASE WHEN c.Dni IN ('00000000', '00000001') THEN 1 ELSE 0 END AS ClienteGenerico,
           (SELECT Id FROM MedioPago WHERE Codigo = 'SEN') AS IdMedioSen,
           si.Disponibilidad, si.LlegadaEstimada
    FROM Encargo e
    LEFT JOIN Usuario u ON u.Id = e.IdUsuario
    LEFT JOIN Cliente c ON c.Id = e.IdCliente
    LEFT JOIN vw_EncargoSituacion si ON si.IdEncargo = e.Id
    WHERE e.Id = @Id;

    SELECT d.Id, d.IdRepuesto, r.Codigo, r.Descripcion, d.Cantidad, d.PrecioPactado,
           CAST(d.Cantidad * d.PrecioPactado AS DECIMAL(12,2)) AS Subtotal,
           ISNULL(s.Cantidad, 0) AS Stock,
           ISNULL((SELECT SUM(dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada)
                   FROM DetallePedido dp INNER JOIN Pedido p ON p.Id = dp.IdPedido
                   WHERE p.IdEstado = 1 AND dp.IdRepuesto = d.IdRepuesto), 0) AS EnCamino,
           dpp.IdPedido, pp.FechaEnvio, prv.RazonSocial AS ProveedorPedido
    FROM EncargoDetalle d
    INNER JOIN Repuesto r ON r.Id = d.IdRepuesto
    LEFT JOIN Stock s ON s.IdRepuesto = d.IdRepuesto
    LEFT JOIN DetallePedido dpp ON dpp.Id = d.IdDetallePedido
    LEFT JOIN Pedido pp ON pp.Id = dpp.IdPedido
    LEFT JOIN Proveedor prv ON prv.Id = pp.IdProveedor
    WHERE d.IdEncargo = @Id
    ORDER BY r.Descripcion;

    SELECT es.Id, es.Fecha, m.Nombre AS Medio, m.Codigo, es.Monto, es.Comision
    FROM EncargoSena es INNER JOIN MedioPago m ON m.Id = es.IdMedioPago
    WHERE es.IdEncargo = @Id
    ORDER BY es.Id;
END
GO


/* -----------------------------------------------------------------
   12. Al recibir: encargos que ya se pueden separar y avisar
   Los abiertos que tienen algun repuesto de este pedido y para los que
   ahora alcanza el stock.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Encargo_ParaSeparar', 'P') IS NOT NULL DROP PROCEDURE SP_Encargo_ParaSeparar;
GO
CREATE PROCEDURE SP_Encargo_ParaSeparar @IdPedido INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT e.Id, e.Nombre, e.Telefono, e.Estado,
           (SELECT SUM(Cantidad * PrecioPactado) FROM EncargoDetalle d WHERE d.IdEncargo = e.Id) AS Total,
           ISNULL((SELECT SUM(Monto) FROM EncargoSena es WHERE es.IdEncargo = e.Id), 0) AS Sena,
           STUFF((SELECT ', ' + CAST(d.Cantidad AS VARCHAR(10)) + N' × ' + r.Descripcion
                  FROM EncargoDetalle d INNER JOIN Repuesto r ON r.Id = d.IdRepuesto
                  WHERE d.IdEncargo = e.Id
                  FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, '') AS Items
    FROM Encargo e
    INNER JOIN vw_EncargoSituacion si ON si.IdEncargo = e.Id
    WHERE e.Estado IN ('PENDIENTE', 'AVISADO')
      AND si.Disponibilidad = 'EN_STOCK'
      AND EXISTS (SELECT 1 FROM EncargoDetalle d
                  INNER JOIN DetallePedido dp ON dp.IdRepuesto = d.IdRepuesto AND dp.IdPedido = @IdPedido
                  WHERE d.IdEncargo = e.Id)
    ORDER BY e.Fecha;
END
GO


/* -----------------------------------------------------------------
   PRUEBA
   ----------------------------------------------------------------- */
SELECT dbo.fn_LlegadaEstimada('20261016', 1) AS ViernesMasUno;   -- tiene que dar lunes 19/10
EXEC SP_Pedido_GetAll;
EXEC SP_Encargo_GetAll;
GO
