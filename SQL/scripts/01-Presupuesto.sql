/* =================================================================
   DAYTONA INYECCIÓN — Módulo Presupuesto
   Correr una sola vez, en orden. Base: DaytonaInyeccion
   ================================================================= */

USE DaytonaInyeccion;
GO

/* -----------------------------------------------------------------
   1. TABLAS
   ----------------------------------------------------------------- */

IF OBJECT_ID('DetallePresupuesto', 'U') IS NOT NULL DROP TABLE DetallePresupuesto;
IF OBJECT_ID('Presupuesto', 'U') IS NOT NULL DROP TABLE Presupuesto;
GO

CREATE TABLE Presupuesto (
    Id                  INT IDENTITY(1,1) PRIMARY KEY,
    Numero              INT             NOT NULL,   -- correlativo visible, lo genera el SP
    Fecha               DATETIME        NOT NULL DEFAULT GETDATE(),
    FechaVencimiento    DATETIME        NOT NULL,

    -- Cliente: acá SÍ puede ser NULL. Es tabla nueva, ningún reporte existente
    -- hace JOIN contra ella, así que no hay nada que romper.
    IdCliente           INT             NULL,
    NombreOcasional     NVARCHAR(80)    NULL,
    TelefonoOcasional   NVARCHAR(30)    NULL,
    TipoCliente         NVARCHAR(20)    NOT NULL DEFAULT 'Publico',  -- 'Publico' | 'Mecanico'

    Total               DECIMAL(12,2)   NOT NULL DEFAULT 0,
    IdUsuario           INT             NOT NULL,

    -- Trazabilidad: si el presupuesto termina en venta, queda enlazado.
    IdVenta             INT             NULL,

    Activo              BIT             NOT NULL DEFAULT 1,  -- baja lógica = anulado
    Observaciones       NVARCHAR(300)   NULL,

    CONSTRAINT UQ_Presupuesto_Numero UNIQUE (Numero),
    CONSTRAINT FK_Presupuesto_Cliente FOREIGN KEY (IdCliente) REFERENCES Cliente(Id),
    CONSTRAINT FK_Presupuesto_Usuario FOREIGN KEY (IdUsuario) REFERENCES Usuario(Id),
    CONSTRAINT FK_Presupuesto_Venta   FOREIGN KEY (IdVenta)   REFERENCES Venta(Id),
    CONSTRAINT CK_Presupuesto_Tipo    CHECK (TipoCliente IN ('Publico', 'Mecanico'))
);
GO

CREATE TABLE DetallePresupuesto (
    Id              INT IDENTITY(1,1) PRIMARY KEY,
    IdPresupuesto   INT             NOT NULL,
    IdRepuesto      INT             NOT NULL,
    Cantidad        INT             NOT NULL,
    PrecioUnitario  DECIMAL(10,2)   NOT NULL,
    Subtotal        DECIMAL(12,2)   NOT NULL,

    CONSTRAINT FK_DetPresu_Presupuesto FOREIGN KEY (IdPresupuesto)
        REFERENCES Presupuesto(Id) ON DELETE CASCADE,
    CONSTRAINT FK_DetPresu_Repuesto FOREIGN KEY (IdRepuesto) REFERENCES Repuesto(Id),
    CONSTRAINT CK_DetPresu_Cantidad CHECK (Cantidad > 0),
    CONSTRAINT CK_DetPresu_Precio   CHECK (PrecioUnitario >= 0)
);
GO

CREATE INDEX IX_Presupuesto_Fecha   ON Presupuesto(Fecha DESC);
CREATE INDEX IX_Presupuesto_Cliente ON Presupuesto(IdCliente);
CREATE INDEX IX_DetPresu_Presupuesto ON DetallePresupuesto(IdPresupuesto);
GO


/* -----------------------------------------------------------------
   2. COLUMNAS NUEVAS EN VENTA
   Para guardar nombre y teléfono sueltos de una venta de mostrador
   sin obligar a registrar un cliente.
   ----------------------------------------------------------------- */

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('Venta') AND name = 'NombreOcasional')
    ALTER TABLE Venta ADD NombreOcasional NVARCHAR(80) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('Venta') AND name = 'TelefonoOcasional')
    ALTER TABLE Venta ADD TelefonoOcasional NVARCHAR(30) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('Venta') AND name = 'TipoCliente')
    ALTER TABLE Venta ADD TipoCliente NVARCHAR(20) NULL;
GO


/* -----------------------------------------------------------------
   3. SP: ALTA DE PRESUPUESTO
   Genera el correlativo adentro, igual que SP_Repuesto_I genera SIGLA-NNNN.
   Devuelve el Id y el Número asignados.
   ----------------------------------------------------------------- */

IF OBJECT_ID('SP_Presupuesto_I', 'P') IS NOT NULL DROP PROCEDURE SP_Presupuesto_I;
GO

CREATE PROCEDURE SP_Presupuesto_I
    @IdCliente          INT = NULL,
    @NombreOcasional    NVARCHAR(80) = NULL,
    @TelefonoOcasional  NVARCHAR(30) = NULL,
    @TipoCliente        NVARCHAR(20) = 'Publico',
    @IdUsuario          INT,
    @DiasValidez        INT = 7,
    @Observaciones      NVARCHAR(300) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM Usuario WHERE Id = @IdUsuario)
    BEGIN
        RAISERROR('El usuario indicado no existe.', 16, 1);
        RETURN;
    END

    IF @IdCliente IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Cliente WHERE Id = @IdCliente)
    BEGIN
        RAISERROR('El cliente indicado no existe.', 16, 1);
        RETURN;
    END

    IF @TipoCliente NOT IN ('Publico', 'Mecanico')
        SET @TipoCliente = 'Publico';

    DECLARE @Numero INT;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- UPDLOCK + HOLDLOCK evita que dos altas simultáneas saquen el mismo número
        SELECT @Numero = ISNULL(MAX(Numero), 0) + 1
        FROM Presupuesto WITH (UPDLOCK, HOLDLOCK);

        INSERT INTO Presupuesto
            (Numero, Fecha, FechaVencimiento, IdCliente, NombreOcasional,
             TelefonoOcasional, TipoCliente, Total, IdUsuario, Activo, Observaciones)
        VALUES
            (@Numero, GETDATE(), DATEADD(DAY, @DiasValidez, GETDATE()), @IdCliente,
             @NombreOcasional, @TelefonoOcasional, @TipoCliente, 0, @IdUsuario, 1, @Observaciones);

        DECLARE @Id INT = SCOPE_IDENTITY();

        COMMIT TRANSACTION;

        SELECT @Id AS Id, @Numero AS Numero;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @msg NVARCHAR(2000) = ERROR_MESSAGE();
        RAISERROR(@msg, 16, 1);
    END CATCH
END
GO


/* -----------------------------------------------------------------
   4. SP: ALTA DE DETALLE
   Recalcula el Total del presupuesto en la misma operación.
   ----------------------------------------------------------------- */

IF OBJECT_ID('SP_DetallePresupuesto_I', 'P') IS NOT NULL DROP PROCEDURE SP_DetallePresupuesto_I;
GO

CREATE PROCEDURE SP_DetallePresupuesto_I
    @IdPresupuesto  INT,
    @IdRepuesto     INT,
    @Cantidad       INT,
    @PrecioUnitario DECIMAL(10,2)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM Presupuesto WHERE Id = @IdPresupuesto)
    BEGIN
        RAISERROR('El presupuesto indicado no existe.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM Repuesto WHERE Id = @IdRepuesto)
    BEGIN
        RAISERROR('El repuesto indicado no existe.', 16, 1);
        RETURN;
    END

    IF @Cantidad <= 0
    BEGIN
        RAISERROR('La cantidad debe ser mayor a cero.', 16, 1);
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Si el repuesto ya está, se suma la cantidad en vez de duplicar la fila
        IF EXISTS (SELECT 1 FROM DetallePresupuesto
                   WHERE IdPresupuesto = @IdPresupuesto AND IdRepuesto = @IdRepuesto)
        BEGIN
            UPDATE DetallePresupuesto
            SET Cantidad = Cantidad + @Cantidad,
                PrecioUnitario = @PrecioUnitario,
                Subtotal = (Cantidad + @Cantidad) * @PrecioUnitario
            WHERE IdPresupuesto = @IdPresupuesto AND IdRepuesto = @IdRepuesto;
        END
        ELSE
        BEGIN
            INSERT INTO DetallePresupuesto (IdPresupuesto, IdRepuesto, Cantidad, PrecioUnitario, Subtotal)
            VALUES (@IdPresupuesto, @IdRepuesto, @Cantidad, @PrecioUnitario, @Cantidad * @PrecioUnitario);
        END

        UPDATE Presupuesto
        SET Total = (SELECT ISNULL(SUM(Subtotal), 0) FROM DetallePresupuesto
                     WHERE IdPresupuesto = @IdPresupuesto)
        WHERE Id = @IdPresupuesto;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @msg NVARCHAR(2000) = ERROR_MESSAGE();
        RAISERROR(@msg, 16, 1);
    END CATCH
END
GO


/* -----------------------------------------------------------------
   5. SP: LISTADO
   El Estado no se guarda: se deriva. Evita una tabla EstadoPresupuesto
   y evita que un presupuesto quede "Vigente" en la base después de vencido.
   ----------------------------------------------------------------- */

IF OBJECT_ID('SP_Presupuesto_GetAll', 'P') IS NOT NULL DROP PROCEDURE SP_Presupuesto_GetAll;
GO

CREATE PROCEDURE SP_Presupuesto_GetAll
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.Id,
        p.Numero,
        p.Fecha,
        p.FechaVencimiento,
        p.IdCliente,
        p.NombreOcasional,
        p.TelefonoOcasional,
        p.TipoCliente,
        p.Total,
        p.IdUsuario,
        p.IdVenta,
        p.Activo,
        p.Observaciones,
        -- LEFT JOIN: el cliente puede no existir
        ISNULL(c.Apellido + ', ' + c.Nombre,
               ISNULL(NULLIF(p.NombreOcasional, ''), 'Consumidor final')) AS Cliente,
        u.Nombre AS Usuario,
        (SELECT COUNT(*) FROM DetallePresupuesto d WHERE d.IdPresupuesto = p.Id) AS CantidadItems,
        CASE
            WHEN p.Activo = 0                       THEN 'Anulado'
            WHEN p.IdVenta IS NOT NULL              THEN 'Convertido'
            WHEN p.FechaVencimiento < GETDATE()     THEN 'Vencido'
            ELSE 'Vigente'
        END AS Estado
    FROM Presupuesto p
    LEFT JOIN Cliente c ON c.Id = p.IdCliente
    INNER JOIN Usuario u ON u.Id = p.IdUsuario
    ORDER BY p.Fecha DESC;
END
GO


/* -----------------------------------------------------------------
   6. SP: UNO SOLO, CON SU DETALLE (dos result sets)
   ----------------------------------------------------------------- */

IF OBJECT_ID('SP_Presupuesto_GetId', 'P') IS NOT NULL DROP PROCEDURE SP_Presupuesto_GetId;
GO

CREATE PROCEDURE SP_Presupuesto_GetId
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.Id, p.Numero, p.Fecha, p.FechaVencimiento, p.IdCliente,
        p.NombreOcasional, p.TelefonoOcasional, p.TipoCliente,
        p.Total, p.IdUsuario, p.IdVenta, p.Activo, p.Observaciones,
        ISNULL(c.Apellido + ', ' + c.Nombre,
               ISNULL(NULLIF(p.NombreOcasional, ''), 'Consumidor final')) AS Cliente,
        c.Telefono AS TelefonoCliente,
        u.Nombre AS Usuario,
        CASE
            WHEN p.Activo = 0                   THEN 'Anulado'
            WHEN p.IdVenta IS NOT NULL          THEN 'Convertido'
            WHEN p.FechaVencimiento < GETDATE() THEN 'Vencido'
            ELSE 'Vigente'
        END AS Estado
    FROM Presupuesto p
    LEFT JOIN Cliente c ON c.Id = p.IdCliente
    INNER JOIN Usuario u ON u.Id = p.IdUsuario
    WHERE p.Id = @Id;

    SELECT
        d.Id, d.IdPresupuesto, d.IdRepuesto, d.Cantidad, d.PrecioUnitario, d.Subtotal,
        r.Codigo, r.Descripcion,
        ISNULL(ru.Nombre, '-') AS Rubro,
        -- El precio actual sirve para avisar si cambió desde que se presupuestó
        r.PrecioDeVenta AS PrecioActual,
        ISNULL(s.Cantidad, 0) AS StockActual
    FROM DetallePresupuesto d
    INNER JOIN Repuesto r ON r.Id = d.IdRepuesto
    LEFT JOIN Rubro ru ON ru.Id = r.IdRubro
    LEFT JOIN Stock s ON s.IdRepuesto = r.Id
    WHERE d.IdPresupuesto = @Id
    ORDER BY d.Id;
END
GO


/* -----------------------------------------------------------------
   7. SP: FILTRAR
   @Estado: 'Vigente' | 'Vencido' | 'Convertido' | 'Anulado' | NULL = todos
   ----------------------------------------------------------------- */

IF OBJECT_ID('SP_Presupuesto_Filtrar', 'P') IS NOT NULL DROP PROCEDURE SP_Presupuesto_Filtrar;
GO

CREATE PROCEDURE SP_Presupuesto_Filtrar
    @FechaDesde DATETIME = NULL,
    @FechaHasta DATETIME = NULL,
    @IdCliente  INT = NULL,
    @Estado     NVARCHAR(20) = NULL,
    @Texto      NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT * FROM (
        SELECT
            p.Id, p.Numero, p.Fecha, p.FechaVencimiento, p.IdCliente,
            p.NombreOcasional, p.TelefonoOcasional, p.TipoCliente,
            p.Total, p.IdUsuario, p.IdVenta, p.Activo,
            ISNULL(c.Apellido + ', ' + c.Nombre,
                   ISNULL(NULLIF(p.NombreOcasional, ''), 'Consumidor final')) AS Cliente,
            u.Nombre AS Usuario,
            (SELECT COUNT(*) FROM DetallePresupuesto d WHERE d.IdPresupuesto = p.Id) AS CantidadItems,
            CASE
                WHEN p.Activo = 0                   THEN 'Anulado'
                WHEN p.IdVenta IS NOT NULL          THEN 'Convertido'
                WHEN p.FechaVencimiento < GETDATE() THEN 'Vencido'
                ELSE 'Vigente'
            END AS Estado
        FROM Presupuesto p
        LEFT JOIN Cliente c ON c.Id = p.IdCliente
        INNER JOIN Usuario u ON u.Id = p.IdUsuario
        WHERE (@FechaDesde IS NULL OR p.Fecha >= @FechaDesde)
          AND (@FechaHasta IS NULL OR p.Fecha < DATEADD(DAY, 1, @FechaHasta))
          AND (@IdCliente IS NULL OR @IdCliente = 0 OR p.IdCliente = @IdCliente)
          AND (@Texto IS NULL OR @Texto = ''
               OR CAST(p.Numero AS NVARCHAR(20)) LIKE '%' + @Texto + '%'
               OR p.NombreOcasional LIKE '%' + @Texto + '%'
               OR c.Apellido LIKE '%' + @Texto + '%'
               OR c.Nombre LIKE '%' + @Texto + '%')
    ) AS q
    WHERE (@Estado IS NULL OR @Estado = '' OR q.Estado = @Estado)
    ORDER BY q.Fecha DESC;
END
GO


/* -----------------------------------------------------------------
   8. SP: ANULAR (baja lógica, igual que el resto del sistema)
   ----------------------------------------------------------------- */

IF OBJECT_ID('SP_Presupuesto_Anular', 'P') IS NOT NULL DROP PROCEDURE SP_Presupuesto_Anular;
GO

CREATE PROCEDURE SP_Presupuesto_Anular
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM Presupuesto WHERE Id = @Id)
    BEGIN
        RAISERROR('El presupuesto indicado no existe.', 16, 1);
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM Presupuesto WHERE Id = @Id AND IdVenta IS NOT NULL)
    BEGIN
        RAISERROR('No se puede anular: el presupuesto ya se convirtió en venta.', 16, 1);
        RETURN;
    END

    UPDATE Presupuesto SET Activo = 0 WHERE Id = @Id;
END
GO


/* -----------------------------------------------------------------
   9. SP: VINCULAR CON UNA VENTA
   Se llama después de confirmar una venta nacida de un presupuesto.
   ----------------------------------------------------------------- */

IF OBJECT_ID('SP_Presupuesto_VincularVenta', 'P') IS NOT NULL DROP PROCEDURE SP_Presupuesto_VincularVenta;
GO

CREATE PROCEDURE SP_Presupuesto_VincularVenta
    @IdPresupuesto INT,
    @IdVenta       INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM Presupuesto WHERE Id = @IdPresupuesto)
    BEGIN
        RAISERROR('El presupuesto indicado no existe.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM Venta WHERE Id = @IdVenta)
    BEGIN
        RAISERROR('La venta indicada no existe.', 16, 1);
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM Presupuesto WHERE Id = @IdPresupuesto AND IdVenta IS NOT NULL)
    BEGIN
        RAISERROR('El presupuesto ya está vinculado a una venta.', 16, 1);
        RETURN;
    END

    UPDATE Presupuesto SET IdVenta = @IdVenta WHERE Id = @IdPresupuesto;
END
GO


/* -----------------------------------------------------------------
   10. VERIFICACIÓN
   ----------------------------------------------------------------- */

SELECT name AS Tabla FROM sys.tables WHERE name IN ('Presupuesto', 'DetallePresupuesto');

SELECT name AS Procedimiento FROM sys.procedures
WHERE name LIKE 'SP_Presupuesto%' OR name LIKE 'SP_DetallePresupuesto%'
ORDER BY name;

SELECT name AS ColumnaNuevaEnVenta FROM sys.columns
WHERE object_id = OBJECT_ID('Venta')
  AND name IN ('NombreOcasional', 'TelefonoOcasional', 'TipoCliente');
GO
