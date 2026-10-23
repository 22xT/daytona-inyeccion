USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   79 — INVENTARIO FISICO (conteo ciego)

   Mismo criterio que el arqueo de caja: quien cuenta NO ve cuanto
   dice el sistema. Recien al revisar aparecen las diferencias, y se
   ajusta con motivo.

   Un conteo puede ser de un rubro o de todo el local (los repuestos
   que se trabajan: con stock, con minimo o que alguna vez se
   vendieron; no las 150.000 fichas de las listas). Se puede sumar un
   repuesto que aparece en la estanteria y no estaba en la lista.

   Ventas durante el conteo: al anotar cada cantidad se guarda el
   stock que habia EN ESE MOMENTO (sin mostrarlo). La diferencia es
   contado - stock al contar, y al cerrar se aplica esa diferencia
   sobre el stock actual. Si se vendio algo despues de contarlo, el
   ajuste sigue siendo correcto.

   El ajuste usa SP_MovimientoStock_Ajustar (el mismo de la pantalla
   de ajuste), asi queda en el historial de movimientos con usuario,
   fecha y motivo. Todo el cierre es una sola transaccion.

   Un conteo abierto a la vez.
   ================================================================= */


/* -----------------------------------------------------------------
   1. Tablas
   ----------------------------------------------------------------- */
IF OBJECT_ID('InventarioConteo', 'U') IS NULL
BEGIN
    CREATE TABLE InventarioConteo (
        Id              INT IDENTITY(1,1) PRIMARY KEY,
        FechaInicio     DATETIME      NOT NULL DEFAULT GETDATE(),
        IdUsuario       INT           NOT NULL,
        IdRubro         INT           NULL,          -- NULL = todo el local
        Estado          VARCHAR(10)   NOT NULL DEFAULT 'ABIERTO',   -- ABIERTO / CERRADO / ANULADO
        FechaCierre     DATETIME      NULL,
        IdUsuarioCierre INT           NULL,
        Observacion     NVARCHAR(250) NULL,
        CONSTRAINT CK_InventarioConteo_Estado CHECK (Estado IN ('ABIERTO', 'CERRADO', 'ANULADO'))
    );
END
GO

IF OBJECT_ID('InventarioRenglon', 'U') IS NULL
BEGIN
    CREATE TABLE InventarioRenglon (
        Id              INT IDENTITY(1,1) PRIMARY KEY,
        IdConteo        INT           NOT NULL REFERENCES InventarioConteo(Id),
        IdRepuesto      INT           NOT NULL REFERENCES Repuesto(Id),
        Agregado        BIT           NOT NULL DEFAULT 0,   -- no estaba en la lista: aparecio en la estanteria
        Contado         INT           NULL,                 -- NULL = todavia no se conto
        StockAlContar   INT           NULL,                 -- lo que decia el sistema al anotar (no se muestra)
        FechaConteo     DATETIME      NULL,
        IdUsuarioConteo INT           NULL,
        Motivo          NVARCHAR(200) NULL,                 -- de la diferencia, si se aclara una por una
        StockAntesAjuste INT          NULL,                 -- al cerrar
        StockDespues    INT           NULL,
        CONSTRAINT UQ_InventarioRenglon UNIQUE (IdConteo, IdRepuesto),
        CONSTRAINT CK_InventarioRenglon_Contado CHECK (Contado IS NULL OR Contado BETWEEN 0 AND 100000)
    );
END
GO


/* -----------------------------------------------------------------
   2. Empezar un conteo
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Inventario_Iniciar', 'P') IS NOT NULL DROP PROCEDURE SP_Inventario_Iniciar;
GO
CREATE PROCEDURE SP_Inventario_Iniciar
    @IdRubro     INT = NULL,
    @IdUsuario   INT,
    @Observacion NVARCHAR(250) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM InventarioConteo WHERE Estado = 'ABIERTO')
        THROW 50201, 'Ya hay un conteo abierto. Terminalo o anulalo antes de empezar otro.', 1;

    IF @IdRubro IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Rubro WHERE Id = @IdRubro)
        THROW 50202, 'El rubro no existe.', 1;

    BEGIN TRAN;
        INSERT INTO InventarioConteo (IdUsuario, IdRubro, Observacion)
        VALUES (@IdUsuario, @IdRubro, NULLIF(LTRIM(RTRIM(@Observacion)), ''));

        DECLARE @Id INT = SCOPE_IDENTITY();

        -- Lo que se trabaja en el local, no las fichas armadas al vincular
        INSERT INTO InventarioRenglon (IdConteo, IdRepuesto)
        SELECT @Id, r.Id
        FROM Repuesto r
        LEFT JOIN Stock s ON s.IdRepuesto = r.Id
        WHERE r.Activo = 1
          AND (@IdRubro IS NULL OR r.IdRubro = @IdRubro)
          AND (ISNULL(s.Cantidad, 0) <> 0 OR ISNULL(s.StockMinimo, 0) > 0
               OR EXISTS (SELECT 1 FROM DetalleVenta dv WHERE dv.IdRepuesto = r.Id));

        IF NOT EXISTS (SELECT 1 FROM InventarioRenglon WHERE IdConteo = @Id)
            THROW 50203, 'No hay repuestos para contar en ese rubro.', 1;
    COMMIT;

    SELECT @Id AS Id, (SELECT COUNT(*) FROM InventarioRenglon WHERE IdConteo = @Id) AS Repuestos;
END
GO


/* -----------------------------------------------------------------
   3. Ver un conteo. Mientras esta abierto NO devuelve el stock del
      sistema (conteo ciego); cerrado, devuelve todo.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Inventario_Get', 'P') IS NOT NULL DROP PROCEDURE SP_Inventario_Get;
GO
CREATE PROCEDURE SP_Inventario_Get
    @Id INT = NULL      -- NULL = el abierto, si hay
AS
BEGIN
    SET NOCOUNT ON;
    IF @Id IS NULL SELECT TOP 1 @Id = Id FROM InventarioConteo WHERE Estado = 'ABIERTO' ORDER BY Id DESC;

    DECLARE @estado VARCHAR(10) = (SELECT Estado FROM InventarioConteo WHERE Id = @Id);

    SELECT c.Id, c.FechaInicio, c.Estado, c.IdRubro, ISNULL(ru.Nombre, 'Todo el local') AS Alcance,
           c.Observacion, c.FechaCierre, u.Nombre AS Usuario,
           (SELECT COUNT(*) FROM InventarioRenglon x WHERE x.IdConteo = c.Id) AS Repuestos,
           (SELECT COUNT(*) FROM InventarioRenglon x WHERE x.IdConteo = c.Id AND x.Contado IS NOT NULL) AS Contados
    FROM InventarioConteo c
    LEFT JOIN Rubro ru  ON ru.Id = c.IdRubro
    LEFT JOIN Usuario u ON u.Id = c.IdUsuario
    WHERE c.Id = @Id;

    SELECT ir.Id AS IdRenglon, r.Id AS IdRepuesto, r.Codigo, r.Descripcion, r.MarcaFabricante AS Marca,
           r.CodigoFabricante, ISNULL(ru.Nombre, '') AS Rubro, ir.Agregado,
           ir.Contado, ir.FechaConteo, ir.Motivo,
           CASE WHEN @estado = 'ABIERTO' THEN NULL ELSE ir.StockAlContar END AS StockAlContar,
           CASE WHEN @estado = 'ABIERTO' THEN NULL ELSE ir.Contado - ir.StockAlContar END AS Diferencia,
           CASE WHEN @estado = 'ABIERTO' THEN NULL ELSE ir.StockAntesAjuste END AS StockAntesAjuste,
           CASE WHEN @estado = 'ABIERTO' THEN NULL ELSE ir.StockDespues END AS StockDespues,
           r.PrecioCompra AS Costo
    FROM InventarioRenglon ir
    INNER JOIN Repuesto r ON r.Id = ir.IdRepuesto
    LEFT JOIN Rubro ru    ON ru.Id = r.IdRubro
    WHERE ir.IdConteo = @Id
    ORDER BY ru.Nombre, r.Descripcion;
END
GO


/* -----------------------------------------------------------------
   4. Anotar lo contado de un repuesto (o borrarlo con NULL)
      Si el repuesto no estaba en la lista, se agrega.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Inventario_Contar', 'P') IS NOT NULL DROP PROCEDURE SP_Inventario_Contar;
GO
CREATE PROCEDURE SP_Inventario_Contar
    @IdConteo   INT,
    @IdRepuesto INT,
    @Contado    INT = NULL,
    @IdUsuario  INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM InventarioConteo WHERE Id = @IdConteo AND Estado = 'ABIERTO')
        THROW 50204, 'El conteo no esta abierto.', 1;
    IF @Contado IS NOT NULL AND (@Contado < 0 OR @Contado > 100000)
        THROW 50205, 'La cantidad contada no es valida.', 1;
    IF NOT EXISTS (SELECT 1 FROM Repuesto WHERE Id = @IdRepuesto AND Activo = 1)
        THROW 50206, 'El repuesto no existe.', 1;

    DECLARE @stock INT = ISNULL((SELECT Cantidad FROM Stock WHERE IdRepuesto = @IdRepuesto), 0);

    IF NOT EXISTS (SELECT 1 FROM InventarioRenglon WHERE IdConteo = @IdConteo AND IdRepuesto = @IdRepuesto)
        INSERT INTO InventarioRenglon (IdConteo, IdRepuesto, Agregado) VALUES (@IdConteo, @IdRepuesto, 1);

    UPDATE InventarioRenglon
    SET Contado = @Contado,
        StockAlContar = CASE WHEN @Contado IS NULL THEN NULL ELSE @stock END,
        FechaConteo = CASE WHEN @Contado IS NULL THEN NULL ELSE GETDATE() END,
        IdUsuarioConteo = CASE WHEN @Contado IS NULL THEN NULL ELSE @IdUsuario END,
        Motivo = CASE WHEN @Contado IS NULL THEN NULL ELSE Motivo END
    WHERE IdConteo = @IdConteo AND IdRepuesto = @IdRepuesto;

    SELECT (SELECT COUNT(*) FROM InventarioRenglon WHERE IdConteo = @IdConteo AND Contado IS NOT NULL) AS Contados,
           (SELECT COUNT(*) FROM InventarioRenglon WHERE IdConteo = @IdConteo) AS Repuestos;
END
GO


/* -----------------------------------------------------------------
   5. Revisar: recien aca aparecen las diferencias
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Inventario_Diferencias', 'P') IS NOT NULL DROP PROCEDURE SP_Inventario_Diferencias;
GO
CREATE PROCEDURE SP_Inventario_Diferencias
    @IdConteo INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT COUNT(*) AS Repuestos,
           SUM(CASE WHEN Contado IS NOT NULL THEN 1 ELSE 0 END) AS Contados,
           SUM(CASE WHEN Contado IS NOT NULL AND Contado = StockAlContar THEN 1 ELSE 0 END) AS Coinciden,
           SUM(CASE WHEN Contado > StockAlContar THEN 1 ELSE 0 END) AS Sobran,
           SUM(CASE WHEN Contado < StockAlContar THEN 1 ELSE 0 END) AS Faltan,
           CAST(SUM(CASE WHEN Contado < StockAlContar THEN (StockAlContar - Contado) * ISNULL(r.PrecioCompra, 0) ELSE 0 END) AS DECIMAL(14,2)) AS ValorFaltante,
           CAST(SUM(CASE WHEN Contado > StockAlContar THEN (Contado - StockAlContar) * ISNULL(r.PrecioCompra, 0) ELSE 0 END) AS DECIMAL(14,2)) AS ValorSobrante
    FROM InventarioRenglon ir
    INNER JOIN Repuesto r ON r.Id = ir.IdRepuesto
    WHERE ir.IdConteo = @IdConteo;

    SELECT ir.Id AS IdRenglon, r.Id AS IdRepuesto, r.Codigo, r.Descripcion, r.MarcaFabricante AS Marca,
           ISNULL(ru.Nombre, '') AS Rubro, ir.Contado, ir.StockAlContar,
           ir.Contado - ir.StockAlContar AS Diferencia,
           CAST((ir.Contado - ir.StockAlContar) * ISNULL(r.PrecioCompra, 0) AS DECIMAL(14,2)) AS Valor,
           ir.Motivo, ir.Agregado
    FROM InventarioRenglon ir
    INNER JOIN Repuesto r ON r.Id = ir.IdRepuesto
    LEFT JOIN Rubro ru    ON ru.Id = r.IdRubro
    WHERE ir.IdConteo = @IdConteo
      AND ir.Contado IS NOT NULL AND ir.Contado <> ir.StockAlContar
    ORDER BY ABS((ir.Contado - ir.StockAlContar) * ISNULL(r.PrecioCompra, 0)) DESC;
END
GO


/* -----------------------------------------------------------------
   6. Motivo de una diferencia en particular
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Inventario_Motivo', 'P') IS NOT NULL DROP PROCEDURE SP_Inventario_Motivo;
GO
CREATE PROCEDURE SP_Inventario_Motivo
    @IdRenglon INT,
    @Motivo    NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM InventarioRenglon ir INNER JOIN InventarioConteo c ON c.Id = ir.IdConteo
                   WHERE ir.Id = @IdRenglon AND c.Estado = 'ABIERTO')
        THROW 50204, 'El conteo no esta abierto.', 1;
    UPDATE InventarioRenglon SET Motivo = NULLIF(LTRIM(RTRIM(@Motivo)), '') WHERE Id = @IdRenglon;
END
GO


/* -----------------------------------------------------------------
   7. Cerrar: ajustar las diferencias (todo o nada)
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Inventario_Cerrar', 'P') IS NOT NULL DROP PROCEDURE SP_Inventario_Cerrar;
GO
CREATE PROCEDURE SP_Inventario_Cerrar
    @IdConteo      INT,
    @IdUsuario     INT,
    @MotivoGeneral NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM InventarioConteo WHERE Id = @IdConteo AND Estado = 'ABIERTO')
        THROW 50204, 'El conteo no esta abierto.', 1;

    IF NOT EXISTS (SELECT 1 FROM InventarioRenglon WHERE IdConteo = @IdConteo AND Contado IS NOT NULL)
        THROW 50207, 'No se conto ningun repuesto.', 1;

    SET @MotivoGeneral = NULLIF(LTRIM(RTRIM(@MotivoGeneral)), '');
    IF @MotivoGeneral IS NULL AND EXISTS (
            SELECT 1 FROM InventarioRenglon
            WHERE IdConteo = @IdConteo AND Contado IS NOT NULL AND Contado <> StockAlContar AND Motivo IS NULL)
        THROW 50208, 'Hay diferencias sin motivo. Escribí un motivo general o uno en cada diferencia.', 1;

    DECLARE @ajustes TABLE (IdRenglon INT, IdRepuesto INT, Dif INT, Motivo NVARCHAR(250));
    INSERT INTO @ajustes
    SELECT Id, IdRepuesto, Contado - StockAlContar,
           LEFT('Inventario #' + CAST(@IdConteo AS VARCHAR(10)) + ': ' + ISNULL(Motivo, @MotivoGeneral), 250)
    FROM InventarioRenglon
    WHERE IdConteo = @IdConteo AND Contado IS NOT NULL AND Contado <> StockAlContar;

    BEGIN TRY
        BEGIN TRAN;

        DECLARE @idR INT, @idRep INT, @dif INT, @mot NVARCHAR(250), @actual INT, @nuevo INT;
        DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT IdRenglon, IdRepuesto, Dif, Motivo FROM @ajustes;
        OPEN cur;
        FETCH NEXT FROM cur INTO @idR, @idRep, @dif, @mot;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- La diferencia se aplica sobre el stock de AHORA (si se vendio
            -- algo despues de contarlo, el ajuste sigue siendo correcto)
            SET @actual = ISNULL((SELECT Cantidad FROM Stock WITH (UPDLOCK) WHERE IdRepuesto = @idRep), 0);
            SET @nuevo = @actual + @dif;
            IF @nuevo < 0 SET @nuevo = 0;

            IF @nuevo <> @actual
                EXEC SP_MovimientoStock_Ajustar @IdRepuesto = @idRep, @CantidadNueva = @nuevo,
                     @Tipo = N'Inventario físico', @Motivo = @mot, @IdUsuario = @IdUsuario;

            UPDATE InventarioRenglon SET StockAntesAjuste = @actual, StockDespues = @nuevo WHERE Id = @idR;
            FETCH NEXT FROM cur INTO @idR, @idRep, @dif, @mot;
        END
        CLOSE cur; DEALLOCATE cur;

        UPDATE InventarioConteo
        SET Estado = 'CERRADO', FechaCierre = GETDATE(), IdUsuarioCierre = @IdUsuario,
            Observacion = ISNULL(Observacion, @MotivoGeneral)
        WHERE Id = @IdConteo;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH

    SELECT COUNT(*) AS Ajustados FROM @ajustes;
END
GO


/* -----------------------------------------------------------------
   8. Anular un conteo abierto (no toca el stock)
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Inventario_Anular', 'P') IS NOT NULL DROP PROCEDURE SP_Inventario_Anular;
GO
CREATE PROCEDURE SP_Inventario_Anular
    @IdConteo  INT,
    @IdUsuario INT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM InventarioConteo WHERE Id = @IdConteo AND Estado = 'ABIERTO')
        THROW 50204, 'El conteo no esta abierto.', 1;
    UPDATE InventarioConteo SET Estado = 'ANULADO', FechaCierre = GETDATE(), IdUsuarioCierre = @IdUsuario
    WHERE Id = @IdConteo;
END
GO


/* -----------------------------------------------------------------
   9. Historial de conteos
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Inventario_Lista', 'P') IS NOT NULL DROP PROCEDURE SP_Inventario_Lista;
GO
CREATE PROCEDURE SP_Inventario_Lista
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP 50 c.Id, c.FechaInicio, c.FechaCierre, c.Estado,
           ISNULL(ru.Nombre, 'Todo el local') AS Alcance, u.Nombre AS Usuario,
           COUNT(ir.Id) AS Repuestos,
           SUM(CASE WHEN ir.Contado IS NOT NULL THEN 1 ELSE 0 END) AS Contados,
           SUM(CASE WHEN ir.Contado IS NOT NULL AND ir.Contado <> ir.StockAlContar THEN 1 ELSE 0 END) AS ConDiferencia,
           CAST(SUM(CASE WHEN ir.Contado IS NOT NULL THEN (ir.Contado - ir.StockAlContar) * ISNULL(r.PrecioCompra, 0) ELSE 0 END) AS DECIMAL(14,2)) AS ValorDiferencia
    FROM InventarioConteo c
    LEFT JOIN Rubro ru  ON ru.Id = c.IdRubro
    LEFT JOIN Usuario u ON u.Id = c.IdUsuario
    LEFT JOIN InventarioRenglon ir ON ir.IdConteo = c.Id
    LEFT JOIN Repuesto r ON r.Id = ir.IdRepuesto
    GROUP BY c.Id, c.FechaInicio, c.FechaCierre, c.Estado, ru.Nombre, u.Nombre
    ORDER BY c.Id DESC;
END
GO


/* PRUEBA (no modifica nada) */
EXEC SP_Inventario_Lista;
GO
