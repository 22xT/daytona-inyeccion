USE [DaytonaInyeccion];
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   CUENTA CORRIENTE — libro de movimientos

   El saldo NO se almacena: se deriva sumando los movimientos.
   Un campo de saldo actualizado por disparadores se desincroniza, y
   cuando eso pasa no hay forma de saber cual de los dos valores es
   el correcto. El libro es reproducible y se le puede mostrar al
   cliente movimiento por movimiento.

   Convencion de signo:
     Monto POSITIVO  = DEBE  (aumenta la deuda del cliente)
     Monto NEGATIVO  = HABER (la reduce)
     Saldo = SUM(Monto)

   Saldo positivo  -> el cliente debe
   Saldo negativo  -> el cliente tiene credito a favor

   El saldo a favor no necesita tratamiento especial: si paga de mas,
   el saldo queda negativo y se descuenta solo de la compra siguiente.
   ================================================================= */

/* -----------------------------------------------------------------
   1. Habilitacion de cuenta corriente en el cliente
   ----------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('Cliente') AND name = 'CuentaCorriente')
    ALTER TABLE Cliente ADD CuentaCorriente BIT NOT NULL
        CONSTRAINT DF_Cliente_CtaCte DEFAULT 0;
GO

-- Los mecanicos registrados trabajan con cuenta corriente por defecto
UPDATE Cliente SET CuentaCorriente = 1
WHERE EsMecanico = 1 AND Dni NOT IN ('00000000', '00000001');
GO


/* -----------------------------------------------------------------
   2. Libro de movimientos
   ----------------------------------------------------------------- */
IF OBJECT_ID('MovimientoCuentaCorriente', 'U') IS NULL
BEGIN
    CREATE TABLE MovimientoCuentaCorriente (
        Id            INT IDENTITY(1,1) PRIMARY KEY,
        IdCliente     INT           NOT NULL,
        Fecha         DATETIME      NOT NULL DEFAULT GETDATE(),

        -- 'Venta' | 'Pago' | 'NotaCredito' | 'Ajuste'
        Tipo          VARCHAR(20)   NOT NULL,
        Concepto      VARCHAR(120)  NOT NULL,

        -- Positivo = debe, negativo = haber
        Monto         DECIMAL(12,2) NOT NULL,

        IdVenta       INT           NULL,   -- si nace de una venta
        IdUsuario     INT           NOT NULL,
        Observaciones VARCHAR(300)  NULL,

        CONSTRAINT FK_MovCC_Cliente FOREIGN KEY (IdCliente) REFERENCES Cliente(Id),
        CONSTRAINT FK_MovCC_Venta   FOREIGN KEY (IdVenta)   REFERENCES Venta(Id),
        CONSTRAINT FK_MovCC_Usuario FOREIGN KEY (IdUsuario) REFERENCES Usuario(Id),
        CONSTRAINT CK_MovCC_Tipo CHECK (Tipo IN ('Venta','Pago','NotaCredito','Ajuste')),
        CONSTRAINT CK_MovCC_Monto CHECK (Monto <> 0)
    );

    CREATE INDEX IX_MovCC_Cliente ON MovimientoCuentaCorriente(IdCliente, Fecha);
    CREATE INDEX IX_MovCC_Venta   ON MovimientoCuentaCorriente(IdVenta);
END
GO


/* -----------------------------------------------------------------
   3. SP: saldo de un cliente
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_CuentaCorriente_GetSaldo', 'P') IS NOT NULL
    DROP PROCEDURE SP_CuentaCorriente_GetSaldo;
GO

CREATE PROCEDURE SP_CuentaCorriente_GetSaldo
    @IdCliente INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        c.Id                AS IdCliente,
        c.Apellido + ', ' + c.Nombre AS Cliente,
        c.Telefono,
        c.EsMecanico,
        c.CuentaCorriente,
        ISNULL(SUM(m.Monto), 0)                                  AS Saldo,
        ISNULL(SUM(CASE WHEN m.Monto > 0 THEN m.Monto END), 0)   AS TotalDebe,
        ISNULL(-SUM(CASE WHEN m.Monto < 0 THEN m.Monto END), 0)  AS TotalHaber,
        COUNT(m.Id)                                              AS Movimientos,
        MAX(CASE WHEN m.Tipo = 'Pago'  THEN m.Fecha END)         AS UltimoPago,
        MAX(CASE WHEN m.Tipo = 'Venta' THEN m.Fecha END)         AS UltimaCompra,
        CASE
            WHEN ISNULL(SUM(m.Monto), 0) > 0  THEN 'Debe'
            WHEN ISNULL(SUM(m.Monto), 0) < 0  THEN 'A favor'
            ELSE 'Al dia'
        END AS Estado
    FROM Cliente c
    LEFT JOIN MovimientoCuentaCorriente m ON m.IdCliente = c.Id
    WHERE c.Id = @IdCliente
    GROUP BY c.Id, c.Apellido, c.Nombre, c.Telefono, c.EsMecanico, c.CuentaCorriente;
END
GO


/* -----------------------------------------------------------------
   4. SP: movimientos con saldo acumulado
   El saldo corrido se calcula al vuelo, no se guarda.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_CuentaCorriente_GetMovimientos', 'P') IS NOT NULL
    DROP PROCEDURE SP_CuentaCorriente_GetMovimientos;
GO

CREATE PROCEDURE SP_CuentaCorriente_GetMovimientos
    @IdCliente  INT,
    @FechaDesde DATETIME = NULL,
    @FechaHasta DATETIME = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- SQL Server 2014 soporta SUM() OVER con marco de filas
    SELECT
        m.Id,
        m.Fecha,
        m.Tipo,
        m.Concepto,
        m.Monto,
        CASE WHEN m.Monto > 0 THEN m.Monto ELSE NULL END  AS Debe,
        CASE WHEN m.Monto < 0 THEN -m.Monto ELSE NULL END AS Haber,
        SUM(m.Monto) OVER (ORDER BY m.Fecha, m.Id
                           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS SaldoAcumulado,
        m.IdVenta,
        u.Nombre AS Usuario,
        m.Observaciones
    FROM MovimientoCuentaCorriente m
    INNER JOIN Usuario u ON u.Id = m.IdUsuario
    WHERE m.IdCliente = @IdCliente
      AND (@FechaDesde IS NULL OR m.Fecha >= @FechaDesde)
      AND (@FechaHasta IS NULL OR m.Fecha < DATEADD(DAY, 1, @FechaHasta))
    ORDER BY m.Fecha, m.Id;
END
GO


/* -----------------------------------------------------------------
   5. SP: listado de clientes con saldo
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_CuentaCorriente_GetAll', 'P') IS NOT NULL
    DROP PROCEDURE SP_CuentaCorriente_GetAll;
GO

CREATE PROCEDURE SP_CuentaCorriente_GetAll
    @SoloConSaldo BIT = 1,
    @Texto        VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT * FROM (
        SELECT
            c.Id                AS IdCliente,
            c.Apellido + ', ' + c.Nombre AS Cliente,
            c.Telefono,
            c.EsMecanico,
            ISNULL(SUM(m.Monto), 0) AS Saldo,
            MAX(CASE WHEN m.Tipo = 'Pago'  THEN m.Fecha END) AS UltimoPago,
            MAX(CASE WHEN m.Tipo = 'Venta' THEN m.Fecha END) AS UltimaCompra,
            DATEDIFF(DAY, MAX(CASE WHEN m.Tipo = 'Pago' THEN m.Fecha END), GETDATE()) AS DiasSinPagar
        FROM Cliente c
        LEFT JOIN MovimientoCuentaCorriente m ON m.IdCliente = c.Id
        WHERE c.Activo = 1
          AND c.CuentaCorriente = 1
          AND (@Texto IS NULL OR @Texto = ''
               OR c.Apellido LIKE '%' + @Texto + '%'
               OR c.Nombre   LIKE '%' + @Texto + '%'
               OR c.Telefono LIKE '%' + @Texto + '%')
        GROUP BY c.Id, c.Apellido, c.Nombre, c.Telefono, c.EsMecanico
    ) q
    WHERE (@SoloConSaldo = 0 OR q.Saldo <> 0)
    ORDER BY q.Saldo DESC;
END
GO


/* -----------------------------------------------------------------
   6. SP: registrar un cobro

   El pago hace DOS cosas: reduce el saldo e ingresa a caja.
   Son eventos distintos y se registran en tablas distintas, dentro
   de la misma transaccion.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_CuentaCorriente_RegistrarPago', 'P') IS NOT NULL
    DROP PROCEDURE SP_CuentaCorriente_RegistrarPago;
GO

CREATE PROCEDURE SP_CuentaCorriente_RegistrarPago
    @IdCliente     INT,
    @Monto         DECIMAL(12,2),
    @IdUsuario     INT,
    @Observaciones VARCHAR(300) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM Cliente WHERE Id = @IdCliente AND Activo = 1)
            RAISERROR('El cliente indicado no existe o esta dado de baja.', 16, 1);

        IF @Monto IS NULL OR @Monto <= 0
            RAISERROR('El importe del pago debe ser mayor a cero.', 16, 1);

        IF @Monto > 99999999
            RAISERROR('El importe del pago es demasiado alto.', 16, 1);

        DECLARE @nombre VARCHAR(120);
        SELECT @nombre = Apellido + ', ' + Nombre FROM Cliente WHERE Id = @IdCliente;

        -- Haber: reduce la deuda
        INSERT INTO MovimientoCuentaCorriente
            (IdCliente, Tipo, Concepto, Monto, IdUsuario, Observaciones)
        VALUES
            (@IdCliente, 'Pago', 'Pago a cuenta', -@Monto, @IdUsuario, @Observaciones);

        -- Y recien ahora entra la plata a la caja
        EXEC SP_MovimientoCaja_RegistrarInterno
            @Tipo        = 'Ingreso',
            @Concepto    = 'Cobro cuenta corriente',
            @Monto       = @Monto,
            @Descripcion = @nombre,
            @IdUsuario   = @IdUsuario,
            @IdVenta     = NULL,
            @IdPedido    = NULL;

        COMMIT TRANSACTION;

        EXEC SP_CuentaCorriente_GetSaldo @IdCliente = @IdCliente;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   7. SP: ajuste manual
   Para corregir errores. Queda registrado como tal, no se disfraza
   de venta ni de pago.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_CuentaCorriente_Ajuste', 'P') IS NOT NULL
    DROP PROCEDURE SP_CuentaCorriente_Ajuste;
GO

CREATE PROCEDURE SP_CuentaCorriente_Ajuste
    @IdCliente     INT,
    @Monto         DECIMAL(12,2),   -- positivo suma deuda, negativo la reduce
    @Concepto      VARCHAR(120),
    @IdUsuario     INT,
    @Observaciones VARCHAR(300) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM Cliente WHERE Id = @IdCliente)
    BEGIN
        RAISERROR('El cliente indicado no existe.', 16, 1);
        RETURN;
    END

    IF @Monto IS NULL OR @Monto = 0
    BEGIN
        RAISERROR('El importe del ajuste no puede ser cero.', 16, 1);
        RETURN;
    END

    IF @Concepto IS NULL OR LTRIM(RTRIM(@Concepto)) = ''
    BEGIN
        RAISERROR('El ajuste necesita un concepto que lo explique.', 16, 1);
        RETURN;
    END

    -- Un ajuste NO toca la caja: corrige el registro, no mueve dinero
    INSERT INTO MovimientoCuentaCorriente
        (IdCliente, Tipo, Concepto, Monto, IdUsuario, Observaciones)
    VALUES
        (@IdCliente, 'Ajuste', @Concepto, @Monto, @IdUsuario, @Observaciones);
END
GO


/* -----------------------------------------------------------------
   8. VERIFICACION
   ----------------------------------------------------------------- */
SELECT name AS Procedimiento FROM sys.procedures
WHERE name LIKE 'SP_CuentaCorriente%' ORDER BY name;

SELECT name AS Tabla FROM sys.tables WHERE name = 'MovimientoCuentaCorriente';

SELECT Id, Apellido, Nombre, EsMecanico, CuentaCorriente
FROM Cliente WHERE Activo = 1;
GO
