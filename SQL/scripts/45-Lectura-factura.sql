USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   45 — RECEPCION LEYENDO LA FOTO DE LA FACTURA

   La foto se manda a un modelo de vision (Claude) que devuelve los
   renglones. Este script resuelve lo que pasa DESPUES de leer:

     1. Guardar cada lectura: que leyo el modelo, cuanto tardo, si
        fallo. Con el tiempo muestra que tan bien lee cada proveedor.
     2. Cruzar cada renglon leido contra el catalogo del proveedor
        (por codigo, sin guiones) y contra lo pendiente del pedido.

   La lectura NUNCA toca stock, costo ni deuda: solo propone. La
   recepcion se confirma con SP_Pedido_Recibir, igual que a mano.

   Requiere el script 43.
   ================================================================= */


/* -----------------------------------------------------------------
   1. Registro de lecturas
   ----------------------------------------------------------------- */
IF OBJECT_ID('LecturaFactura', 'U') IS NULL
BEGIN
    CREATE TABLE LecturaFactura (
        Id           INT IDENTITY(1,1) PRIMARY KEY,
        IdAdjunto    INT            NOT NULL,
        IdPedido     INT            NOT NULL,
        Fecha        DATETIME       NOT NULL DEFAULT GETDATE(),
        Modelo       VARCHAR(60)    NOT NULL,
        Exito        BIT            NOT NULL,
        Respuesta    NVARCHAR(MAX)  NULL,      -- el JSON tal cual lo devolvio el modelo
        Error        NVARCHAR(500)  NULL,
        DuracionMs   INT            NULL,
        Renglones    INT            NULL,
        Identificados INT           NULL,
        IdUsuario    INT            NOT NULL,
        IdRecepcion  INT            NULL,      -- se completa si se confirma la recepcion
        CONSTRAINT FK_Lectura_Adjunto   FOREIGN KEY (IdAdjunto)   REFERENCES Adjunto(Id),
        CONSTRAINT FK_Lectura_Pedido    FOREIGN KEY (IdPedido)    REFERENCES Pedido(Id),
        CONSTRAINT FK_Lectura_Recepcion FOREIGN KEY (IdRecepcion) REFERENCES RecepcionPedido(Id)
    );
END
GO

IF OBJECT_ID('SP_LecturaFactura_I', 'P') IS NOT NULL DROP PROCEDURE SP_LecturaFactura_I;
GO
CREATE PROCEDURE SP_LecturaFactura_I
    @IdAdjunto     INT,
    @IdPedido      INT,
    @Modelo        VARCHAR(60),
    @Exito         BIT,
    @Respuesta     NVARCHAR(MAX) = NULL,
    @Error         NVARCHAR(500) = NULL,
    @DuracionMs    INT = NULL,
    @Renglones     INT = NULL,
    @Identificados INT = NULL,
    @IdUsuario     INT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO LecturaFactura (IdAdjunto, IdPedido, Modelo, Exito, Respuesta, Error, DuracionMs,
                                Renglones, Identificados, IdUsuario)
    VALUES (@IdAdjunto, @IdPedido, @Modelo, @Exito, @Respuesta, LEFT(@Error, 500), @DuracionMs,
            @Renglones, @Identificados, @IdUsuario);
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS IdLectura;
END
GO

-- Cuando se confirma la recepcion, la lectura queda asociada
IF OBJECT_ID('SP_LecturaFactura_Vincular', 'P') IS NOT NULL DROP PROCEDURE SP_LecturaFactura_Vincular;
GO
CREATE PROCEDURE SP_LecturaFactura_Vincular
    @IdLectura   INT,
    @IdRecepcion INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE LecturaFactura SET IdRecepcion = @IdRecepcion WHERE Id = @IdLectura AND IdRecepcion IS NULL;
END
GO


/* -----------------------------------------------------------------
   2. Renglones leidos
   ----------------------------------------------------------------- */
IF TYPE_ID('FacturaLineaType') IS NULL
    CREATE TYPE FacturaLineaType AS TABLE (
        Orden          INT            NOT NULL,
        Codigo         NVARCHAR(60)   NULL,
        Descripcion    NVARCHAR(250)  NULL,
        Cantidad       DECIMAL(12,2)  NULL,
        PrecioUnitario DECIMAL(12,2)  NULL
    );
GO


/* -----------------------------------------------------------------
   3. Cruce: cada renglon leido contra catalogo y pedido

   Identificacion, en este orden:
     a) codigo del proveedor o del fabricante, en el catalogo de ESE
        proveedor, sin guiones ni espacios (CodigosBusqueda)
     b) codigo propio o de fabricante en nuestro catalogo

   Resultado de cada renglon:
     COINCIDE           esta pedido y la cantidad es la pendiente
     CANTIDAD_DISTINTA  esta pedido pero llega otra cantidad
     NO_PEDIDO          lo identificamos, pero no esta pendiente en este pedido
     SIN_INCORPORAR     esta en la lista del proveedor pero no en nuestro catalogo
     NO_IDENTIFICADO    no aparece por ningun codigo
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Factura_Cruzar', 'P') IS NOT NULL DROP PROCEDURE SP_Factura_Cruzar;
GO
CREATE PROCEDURE SP_Factura_Cruzar
    @IdPedido INT,
    @Lineas   FacturaLineaType READONLY
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @IdProveedor INT = (SELECT IdProveedor FROM Pedido WHERE Id = @IdPedido);

    ;WITH Leidas AS (
        SELECT l.*, dbo.fn_LimpiarCodigo(ISNULL(l.Codigo, '')) AS CodLimpio
        FROM @Lineas l
    ),
    -- a) en la lista de este proveedor
    EnLista AS (
        SELECT le.Orden,
               MIN(pr.IdRepuesto) AS IdRepuesto,          -- vinculado a nuestro catalogo
               MIN(pr.Id)         AS IdProveedorRepuesto,
               MIN(pr.Descripcion) AS DescripcionLista
        FROM Leidas le
        INNER JOIN ProveedorRepuesto pr
            ON pr.IdProveedor = @IdProveedor AND pr.Activo = 1
           AND LEN(le.CodLimpio) >= 3                       -- codigos de 1 o 2 caracteres no identifican nada
           AND pr.CodigosBusqueda LIKE '% ' + le.CodLimpio + ' %'
        GROUP BY le.Orden
    ),
    -- b) por codigo propio
    Propio AS (
        SELECT le.Orden, MIN(r.Id) AS IdRepuesto
        FROM Leidas le
        INNER JOIN Repuesto r ON r.Activo = 1 AND LEN(le.CodLimpio) >= 3
           AND r.CodigosBusqueda LIKE '% ' + le.CodLimpio + ' %'    -- codigo propio o de fabricante
        GROUP BY le.Orden
    ),
    Resuelto AS (
        SELECT le.Orden, le.Codigo, le.Descripcion, le.Cantidad, le.PrecioUnitario,
               COALESCE(el.IdRepuesto, p.IdRepuesto) AS IdRepuesto,
               el.IdProveedorRepuesto, el.DescripcionLista
        FROM Leidas le
        LEFT JOIN EnLista el ON el.Orden = le.Orden
        LEFT JOIN Propio p   ON p.Orden = le.Orden
    )
    SELECT
        x.Orden,
        x.Codigo          AS CodigoLeido,
        x.Descripcion     AS DescripcionLeida,
        x.Cantidad        AS CantidadLeida,
        x.PrecioUnitario  AS PrecioLeido,
        x.IdRepuesto,
        r.Codigo          AS CodigoPropio,
        r.Descripcion     AS DescripcionPropia,
        x.DescripcionLista,
        dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada AS Pendiente,
        dp.PrecioUnitario AS PrecioPedido,
        CASE
            WHEN x.IdRepuesto IS NULL AND x.IdProveedorRepuesto IS NOT NULL THEN 'SIN_INCORPORAR'
            WHEN x.IdRepuesto IS NULL THEN 'NO_IDENTIFICADO'
            WHEN dp.IdRepuesto IS NULL
              OR dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada <= 0 THEN 'NO_PEDIDO'
            WHEN x.Cantidad = dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada THEN 'COINCIDE'
            ELSE 'CANTIDAD_DISTINTA'
        END AS Resultado
    FROM Resuelto x
    LEFT JOIN Repuesto r       ON r.Id = x.IdRepuesto
    LEFT JOIN DetallePedido dp ON dp.IdPedido = @IdPedido AND dp.IdRepuesto = x.IdRepuesto
    ORDER BY x.Orden;
END
GO


/* -----------------------------------------------------------------
   PRUEBA del cruce sin modelo (cambiar el pedido y los codigos)
   ----------------------------------------------------------------- */
/*
DECLARE @l FacturaLineaType;
INSERT INTO @l VALUES (1, 'KTB-341', 'KIT DISTRIBUCION DAYCO', 2, 36131.51),
                      (2, 'XYZ999', 'ALGO QUE NO EXISTE', 1, 1000);
EXEC SP_Factura_Cruzar @IdPedido = <IdPedido>, @Lineas = @l;
*/
GO
