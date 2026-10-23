USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   53 — LA CONDICION DE IVA DEFINE COMO SE TRABAJA CON EL PROVEEDOR

     Condicion              Comprobante        Precio de venta              CUIT
     Responsable Inscripto  Factura A          costo + margen + IVA         obligatorio
     Monotributista         Factura C          costo + margen = final       obligatorio
     Exento                 Factura C          costo + margen = final       obligatorio
     Consumidor Final       Presupuesto        costo + margen = final       opcional
   En todos los casos tambien Remito: la mercaderia puede llegar antes
   que el comprobante.

   El precio de venta ya lo resuelve el script 52. Este agrega:
     - CUIT opcional para quien no factura
     - la recepcion acepta solo el comprobante que corresponde
   ================================================================= */


/* -----------------------------------------------------------------
   1. Que comprobantes corresponden a cada condicion
   ----------------------------------------------------------------- */
IF OBJECT_ID('fn_ComprobanteValido', 'FN') IS NOT NULL DROP FUNCTION fn_ComprobanteValido;
GO
CREATE FUNCTION fn_ComprobanteValido(@Condicion VARCHAR(30), @Tipo VARCHAR(20)) RETURNS BIT
AS
BEGIN
    IF @Tipo = 'Remito' RETURN 1;
    RETURN CASE
        WHEN @Condicion = 'Responsable Inscripto' AND @Tipo = 'Factura A'                        THEN 1
        WHEN @Condicion IN ('Monotributista', 'Exento') AND @Tipo = 'Factura C'                  THEN 1
        WHEN @Condicion = 'Consumidor Final' AND @Tipo = 'Presupuesto'                           THEN 1
        WHEN @Condicion IS NULL                                                                  THEN 1  -- proveedor sin condicion cargada: no se bloquea
        ELSE 0 END;
END
GO

IF OBJECT_ID('fn_ComprobantesPermitidos', 'FN') IS NOT NULL DROP FUNCTION fn_ComprobantesPermitidos;
GO
CREATE FUNCTION fn_ComprobantesPermitidos(@Condicion VARCHAR(30)) RETURNS VARCHAR(60)
AS
BEGIN
    RETURN CASE
        WHEN @Condicion = 'Responsable Inscripto'          THEN 'Factura A,Remito'
        WHEN @Condicion IN ('Monotributista', 'Exento')    THEN 'Factura C,Remito'
        WHEN @Condicion = 'Consumidor Final'               THEN 'Presupuesto,Remito'
        ELSE 'Factura A,Factura B,Factura C,Presupuesto,Remito' END;
END
GO


/* -----------------------------------------------------------------
   2. CUIT opcional para quien no factura
   Se quitan los indices unicos que haya sobre el CUIT, se permite NULL
   y se recrea la unicidad solo para los CUIT cargados.
   ----------------------------------------------------------------- */
DECLARE @sql NVARCHAR(MAX) = N'';

-- Restricciones UNIQUE sobre Cuit
SELECT @sql = @sql + N'ALTER TABLE Proveedor DROP CONSTRAINT ' + QUOTENAME(kc.name) + N';'
FROM sys.key_constraints kc
INNER JOIN sys.index_columns ic ON ic.object_id = kc.parent_object_id AND ic.index_id = kc.unique_index_id
INNER JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE kc.parent_object_id = OBJECT_ID('Proveedor') AND kc.type = 'UQ' AND c.name = 'Cuit';

-- Indices sueltos sobre Cuit
SELECT @sql = @sql + N'DROP INDEX ' + QUOTENAME(i.name) + N' ON Proveedor;'
FROM sys.indexes i
INNER JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
INNER JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE i.object_id = OBJECT_ID('Proveedor') AND c.name = 'Cuit'
  AND i.is_primary_key = 0 AND i.is_unique_constraint = 0;

-- La columna admite NULL, con su mismo tipo
SELECT @sql = @sql + N'ALTER TABLE Proveedor ALTER COLUMN Cuit ' + TYPE_NAME(c.user_type_id) +
       CASE WHEN TYPE_NAME(c.user_type_id) IN ('varchar', 'char') THEN '(' + CAST(c.max_length AS VARCHAR(5)) + ')'
            WHEN TYPE_NAME(c.user_type_id) IN ('nvarchar', 'nchar') THEN '(' + CAST(c.max_length / 2 AS VARCHAR(5)) + ')'
            ELSE '' END + N' NULL;'
FROM sys.columns c WHERE c.object_id = OBJECT_ID('Proveedor') AND c.name = 'Cuit' AND c.is_nullable = 0;

PRINT @sql;
IF @sql <> N'' EXEC sp_executesql @sql;
GO

-- Un CUIT cargado no se repite; los vacios no cuentan
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Proveedor_Cuit')
    CREATE UNIQUE INDEX UX_Proveedor_Cuit ON Proveedor(Cuit) WHERE Cuit IS NOT NULL AND Cuit <> '';
GO

-- La base exige el CUIT a todos menos a consumidor final
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Proveedor_Cuit')
    ALTER TABLE Proveedor WITH NOCHECK ADD CONSTRAINT CK_Proveedor_Cuit
        CHECK (CondicionIva = 'Consumidor Final' OR (Cuit IS NOT NULL AND LEN(Cuit) = 11));
GO


/* -----------------------------------------------------------------
   3. La recepcion valida el comprobante y la pantalla sabe cuales ofrecer
   ----------------------------------------------------------------- */
ALTER PROCEDURE SP_Recepcion_Iniciar
    @IdPedido          INT,
    @Lineas            RecepcionFacturaType READONLY,
    @TipoComprobante   VARCHAR(20),
    @NumeroComprobante VARCHAR(40),
    @FechaComprobante  DATE,
    @TotalComprobante  DECIMAL(12,2),
    @IdAdjunto         INT = NULL,
    @IdLecturaFactura  INT = NULL,
    @Observacion       NVARCHAR(250) = NULL,
    @IdUsuario         INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM @Lineas WHERE CantidadFacturada > 0)
            RAISERROR('Cargá al menos un renglón facturado.', 16, 1);
        IF EXISTS (SELECT 1 FROM @Lineas WHERE CantidadFacturada < 0 OR CostoUnitario < 0)
            RAISERROR('Las cantidades y los costos no pueden ser negativos.', 16, 1);
        IF EXISTS (SELECT 1 FROM @Lineas WHERE IdRepuesto IS NULL AND ISNULL(LTRIM(RTRIM(Descripcion)), '') = '')
            RAISERROR('Los renglones sin repuesto identificado necesitan una descripción.', 16, 1);
        IF ISNULL(LTRIM(RTRIM(@TipoComprobante)), '') = '' OR ISNULL(LTRIM(RTRIM(@NumeroComprobante)), '') = ''
            RAISERROR('Indicá el tipo y el número del comprobante del proveedor.', 16, 1);
        IF @TotalComprobante IS NULL OR @TotalComprobante <= 0
            RAISERROR('Indicá el total del comprobante: es lo que se le debe al proveedor.', 16, 1);
        IF @FechaComprobante > CAST(GETDATE() AS DATE)
            RAISERROR('La fecha del comprobante no puede ser futura.', 16, 1);

        BEGIN TRANSACTION;

        DECLARE @IdProveedor INT, @Estado INT;
        SELECT @IdProveedor = IdProveedor, @Estado = IdEstado FROM Pedido WITH (UPDLOCK) WHERE Id = @IdPedido;
        IF @IdProveedor IS NULL RAISERROR('El pedido no existe.', 16, 1);
        IF @Estado = 3         RAISERROR('El pedido está cancelado.', 16, 1);

        -- El comprobante tiene que corresponder a la condicion del proveedor
        DECLARE @Cond VARCHAR(30) = (SELECT CondicionIva FROM Proveedor WHERE Id = @IdProveedor);
        IF dbo.fn_ComprobanteValido(@Cond, @TipoComprobante) = 0
        BEGIN
            DECLARE @msgComp NVARCHAR(300) = 'Un proveedor ' + ISNULL(@Cond, 'sin condición de IVA') +
                ' no entrega ' + @TipoComprobante + '. Corresponde: ' + dbo.fn_ComprobantesPermitidos(@Cond) + '.';
            RAISERROR(@msgComp, 16, 1);
        END

        IF EXISTS (SELECT 1 FROM RecepcionPedido WHERE IdPedido = @IdPedido AND Estado = 'EN_CONTROL' AND Anulada = 0)
            RAISERROR('Este pedido ya tiene una recepción en control. Terminá esa primero.', 16, 1);

        IF EXISTS (SELECT 1 FROM RecepcionPedido
                   WHERE IdProveedor = @IdProveedor AND Anulada = 0
                     AND TipoComprobante = @TipoComprobante AND NumeroComprobante = LTRIM(RTRIM(@NumeroComprobante)))
            RAISERROR('Ese comprobante del proveedor ya está registrado en otra recepción.', 16, 1);

        INSERT INTO RecepcionPedido (IdPedido, IdProveedor, IdUsuario, TipoComprobante, NumeroComprobante,
                                     FechaComprobante, TotalComprobante, IdAdjunto, Observacion, Estado, IdLecturaFactura)
        VALUES (@IdPedido, @IdProveedor, @IdUsuario, @TipoComprobante, LTRIM(RTRIM(@NumeroComprobante)),
                @FechaComprobante, @TotalComprobante, @IdAdjunto, NULLIF(LTRIM(RTRIM(@Observacion)), ''),
                'EN_CONTROL', @IdLecturaFactura);
        DECLARE @IdRecepcion INT = SCOPE_IDENTITY();

        INSERT INTO DetalleRecepcion (IdRecepcion, IdRepuesto, CodigoFactura, DescripcionFactura,
                                      CantidadFacturada, Cantidad, CostoUnitario)
        SELECT @IdRecepcion, l.IdRepuesto, NULLIF(LTRIM(RTRIM(l.Codigo)), ''),
               COALESCE(NULLIF(LTRIM(RTRIM(l.Descripcion)), ''), r.Descripcion),
               l.CantidadFacturada, 0, l.CostoUnitario
        FROM @Lineas l LEFT JOIN Repuesto r ON r.Id = l.IdRepuesto
        WHERE l.CantidadFacturada > 0;

        IF @IdLecturaFactura IS NOT NULL
            UPDATE LecturaFactura SET IdRecepcion = @IdRecepcion WHERE Id = @IdLecturaFactura AND IdRecepcion IS NULL;

        COMMIT;
        SELECT @IdRecepcion AS IdRecepcion;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

ALTER PROCEDURE SP_Pedido_ParaRecepcion @IdPedido INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT p.Id, p.Fecha, p.IdEstado, p.IdProveedor, pr.RazonSocial AS Proveedor, p.MotivoCierreFaltantes,
           pr.CondicionIva, dbo.fn_ComprobantesPermitidos(pr.CondicionIva) AS ComprobantesPermitidos
    FROM Pedido p INNER JOIN Proveedor pr ON pr.Id = p.IdProveedor
    WHERE p.Id = @IdPedido;

    SELECT dp.IdRepuesto, r.Codigo, r.Descripcion,
           dp.Cantidad, dp.CantidadRecibida, dp.CantidadCancelada,
           dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada AS Pendiente,
           dp.PrecioUnitario
    FROM DetallePedido dp INNER JOIN Repuesto r ON r.Id = dp.IdRepuesto
    WHERE dp.IdPedido = @IdPedido
    ORDER BY r.Descripcion;

    SELECT rp.Id, rp.Fecha, rp.Estado, rp.TipoComprobante, rp.NumeroComprobante, rp.TotalComprobante,
           rp.IdAdjunto, rp.Anulada, rp.MotivoAnulacion, u.Nombre AS Usuario,
           (SELECT SUM(Cantidad) FROM DetalleRecepcion d WHERE d.IdRecepcion = rp.Id) AS Unidades,
           (SELECT COUNT(*) FROM IncidenciaRecepcion i WHERE i.IdRecepcion = rp.Id AND i.Estado IN ('ABIERTA', 'EN_RECLAMO')) AS IncidenciasAbiertas
    FROM RecepcionPedido rp LEFT JOIN Usuario u ON u.Id = rp.IdUsuario
    WHERE rp.IdPedido = @IdPedido
    ORDER BY rp.Id;

    -- Renglones de la recepcion en control, si hay una
    SELECT d.Id AS IdDetalle, d.IdRecepcion, d.IdRepuesto, r.Codigo, d.CodigoFactura,
           COALESCE(r.Descripcion, d.DescripcionFactura) AS Descripcion,
           d.CantidadFacturada, d.CostoUnitario,
           dp.Cantidad - dp.CantidadRecibida - dp.CantidadCancelada AS PendientePedido
    FROM DetalleRecepcion d
    INNER JOIN RecepcionPedido rp ON rp.Id = d.IdRecepcion AND rp.Estado = 'EN_CONTROL' AND rp.Anulada = 0
    LEFT JOIN Repuesto r       ON r.Id = d.IdRepuesto
    LEFT JOIN DetallePedido dp ON dp.IdPedido = rp.IdPedido AND dp.IdRepuesto = d.IdRepuesto
    WHERE rp.IdPedido = @IdPedido
    ORDER BY d.Id;
END
GO


/* -----------------------------------------------------------------
   VERIFICACION
   ----------------------------------------------------------------- */
SELECT RazonSocial, CondicionIva, Cuit, dbo.fn_ComprobantesPermitidos(CondicionIva) AS Comprobantes
FROM Proveedor WHERE Activo = 1 ORDER BY RazonSocial;
GO
