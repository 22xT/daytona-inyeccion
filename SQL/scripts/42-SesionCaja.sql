USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   42 — ETAPA 2 DE CAJA Y FINANZAS: SESION DE CAJA

   La caja fisica se abre y se cierra. Entre medio, todo movimiento
   en efectivo queda asociado a la sesion abierta.

     ABRIR   Se informa el efectivo con que arranca el cajon. El sistema
             sugiere el que se conto en el ultimo cierre. Si difiere,
             motivo obligatorio y un ajuste por la diferencia.
     CERRAR  Se cuenta el efectivo. Saldo teorico = lo que dice el
             sistema. Si el contado difiere, motivo obligatorio y un
             ajuste por la diferencia: el sistema queda igual al cajon.

   Regla nueva: sin caja abierta no se registra ningun movimiento en
   efectivo. Una venta en efectivo con la caja cerrada se rechaza con
   un mensaje que dice que hay que abrirla.

   Banco y Mercado Pago no se arquean: no tienen sesion.
   Requiere los scripts 37 a 41.
   ================================================================= */


/* -----------------------------------------------------------------
   1. Tabla de sesiones
   SaldoTeorico y Diferencia se guardan: son la foto del momento del
   cierre, no un saldo vivo. Si despues alguien pregunta por que hubo
   $1.000 de diferencia el 14/10, la respuesta esta aca.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SesionCaja', 'U') IS NULL
BEGIN
    CREATE TABLE SesionCaja (
        Id                  INT IDENTITY(1,1) PRIMARY KEY,
        IdCuentaFinanciera  INT           NOT NULL,
        Estado              VARCHAR(8)    NOT NULL DEFAULT 'ABIERTA',
        -- Apertura
        FechaApertura       DATETIME      NOT NULL DEFAULT GETDATE(),
        IdUsuarioApertura   INT           NOT NULL,
        SaldoSugerido       DECIMAL(12,2) NOT NULL,   -- lo que decia el sistema
        SaldoInicial        DECIMAL(12,2) NOT NULL,   -- lo que se conto al abrir
        MotivoApertura      NVARCHAR(250) NULL,       -- obligatorio si difieren
        -- Cierre
        FechaCierre         DATETIME      NULL,
        IdUsuarioCierre     INT           NULL,
        SaldoTeorico        DECIMAL(12,2) NULL,
        EfectivoContado     DECIMAL(12,2) NULL,
        Diferencia          DECIMAL(12,2) NULL,       -- contado - teorico
        MotivoDiferencia    NVARCHAR(250) NULL,
        CONSTRAINT FK_SesionCaja_Cuenta FOREIGN KEY (IdCuentaFinanciera) REFERENCES CuentaFinanciera(Id),
        CONSTRAINT CK_SesionCaja_Estado CHECK (Estado IN ('ABIERTA', 'CERRADA')),
        CONSTRAINT CK_SesionCaja_Montos CHECK (SaldoInicial >= 0 AND (EfectivoContado IS NULL OR EfectivoContado >= 0)),
        -- Una sesion cerrada tiene todos los datos del cierre
        CONSTRAINT CK_SesionCaja_Cierre CHECK (
            (Estado = 'ABIERTA' AND FechaCierre IS NULL) OR
            (Estado = 'CERRADA' AND FechaCierre IS NOT NULL AND IdUsuarioCierre IS NOT NULL
                                AND SaldoTeorico IS NOT NULL AND EfectivoContado IS NOT NULL)
        )
    );

    -- Una sola sesion abierta por caja. La base lo garantiza, no el codigo.
    CREATE UNIQUE INDEX UX_SesionCaja_UnaAbierta ON SesionCaja(IdCuentaFinanciera) WHERE Estado = 'ABIERTA';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('MovimientoCaja') AND name = 'IdSesionCaja')
    ALTER TABLE MovimientoCaja ADD IdSesionCaja INT NULL CONSTRAINT FK_MovCaja_Sesion REFERENCES SesionCaja(Id);
GO


/* -----------------------------------------------------------------
   2. Todo movimiento en efectivo exige una sesion abierta
   Se agrega a SP_MovimientoCaja_RegistrarInterno, que es el unico
   punto por el que entra o sale efectivo: ventas, anulaciones,
   gastos, movimientos especiales, pedidos. Una sola validacion los
   cubre a todos.
   ----------------------------------------------------------------- */
ALTER PROCEDURE [dbo].[SP_MovimientoCaja_RegistrarInterno]
    @Tipo                 NVARCHAR(10),
    @Concepto             NVARCHAR(60),
    @Monto                DECIMAL(12,2),
    @Descripcion          NVARCHAR(250),
    @IdUsuario            INT,
    @IdVenta              INT = NULL,
    @IdPedido             INT = NULL,
    @IdGasto              INT = NULL,
    @IdMovimientoEspecial INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Monto IS NULL OR @Monto <= 0
        THROW 50020, 'El importe del movimiento de caja debe ser mayor a cero.', 1;
    IF @Tipo NOT IN ('Ingreso', 'Egreso')
        THROW 50021, 'El tipo de movimiento debe ser Ingreso o Egreso.', 1;

    DECLARE @IdSesion INT;
    SELECT @IdSesion = s.Id
    FROM SesionCaja s INNER JOIN CuentaFinanciera c ON c.Id = s.IdCuentaFinanciera
    WHERE s.Estado = 'ABIERTA' AND c.EsCaja = 1;

    IF @IdSesion IS NULL
        THROW 50022, 'La caja esta cerrada. Abri la caja desde el menu Caja para registrar movimientos en efectivo.', 1;

    DECLARE @SaldoActual DECIMAL(12,2);
    -- UPDLOCK + HOLDLOCK: sin esto, dos movimientos simultaneos leen
    -- el mismo saldo de partida y uno de los dos se pierde.
    SELECT TOP 1 @SaldoActual = SaldoResultante
    FROM MovimientoCaja WITH (UPDLOCK, HOLDLOCK)
    ORDER BY Id DESC;
    IF @SaldoActual IS NULL SET @SaldoActual = 0;

    DECLARE @NuevoSaldo DECIMAL(12,2) =
        CASE WHEN @Tipo = 'Ingreso' THEN @SaldoActual + @Monto ELSE @SaldoActual - @Monto END;

    INSERT INTO MovimientoCaja
        (Tipo, Concepto, Monto, Descripcion, SaldoResultante,
         IdUsuario, IdVenta, IdPedido, IdGasto, IdMovimientoEspecial, IdSesionCaja, Automatico)
    VALUES
        (@Tipo, @Concepto, @Monto, @Descripcion, @NuevoSaldo,
         @IdUsuario, @IdVenta, @IdPedido, @IdGasto, @IdMovimientoEspecial, @IdSesion, 1);
END
GO


/* -----------------------------------------------------------------
   3. Saldo actual del efectivo segun el sistema
   ----------------------------------------------------------------- */
IF OBJECT_ID('fn_SaldoCaja', 'FN') IS NOT NULL DROP FUNCTION fn_SaldoCaja;
GO
CREATE FUNCTION fn_SaldoCaja() RETURNS DECIMAL(12,2)
AS
BEGIN
    RETURN ISNULL((SELECT TOP 1 SaldoResultante FROM MovimientoCaja ORDER BY Id DESC), 0);
END
GO


/* -----------------------------------------------------------------
   4. Abrir
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_SesionCaja_Abrir', 'P') IS NOT NULL DROP PROCEDURE SP_SesionCaja_Abrir;
GO
CREATE PROCEDURE SP_SesionCaja_Abrir
    @SaldoInicial DECIMAL(12,2),
    @Motivo       NVARCHAR(250) = NULL,
    @IdUsuario    INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF @SaldoInicial IS NULL OR @SaldoInicial < 0
            RAISERROR('El efectivo inicial no puede ser negativo.', 16, 1);

        BEGIN TRANSACTION;

        DECLARE @Caja INT = (SELECT TOP 1 Id FROM CuentaFinanciera WHERE EsCaja = 1 AND Activo = 1);
        IF @Caja IS NULL
            RAISERROR('No hay una caja fisica configurada.', 16, 1);

        IF EXISTS (SELECT 1 FROM SesionCaja WITH (UPDLOCK, HOLDLOCK) WHERE IdCuentaFinanciera = @Caja AND Estado = 'ABIERTA')
            RAISERROR('La caja ya esta abierta.', 16, 1);

        -- Bloquea el saldo para que nada se mueva mientras se abre
        DECLARE @Sugerido DECIMAL(12,2);
        SELECT TOP 1 @Sugerido = SaldoResultante FROM MovimientoCaja WITH (UPDLOCK, HOLDLOCK) ORDER BY Id DESC;
        SET @Sugerido = ISNULL(@Sugerido, 0);

        DECLARE @Dif DECIMAL(12,2) = @SaldoInicial - @Sugerido;
        IF @Dif <> 0 AND LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 10
            RAISERROR('El efectivo no coincide con el del ultimo cierre: explica el motivo con al menos 10 caracteres.', 16, 1);

        INSERT INTO SesionCaja (IdCuentaFinanciera, IdUsuarioApertura, SaldoSugerido, SaldoInicial, MotivoApertura)
        VALUES (@Caja, @IdUsuario, @Sugerido, @SaldoInicial, CASE WHEN @Dif <> 0 THEN LTRIM(RTRIM(@Motivo)) END);

        DECLARE @IdSesion INT = SCOPE_IDENTITY();

        -- Si el cajon no tiene lo que dejo el ultimo cierre, el sistema se
        -- alinea con un ajuste explicado. Ya hay sesion abierta: el
        -- movimiento queda asociado a ella.
        IF @Dif <> 0
        BEGIN
            -- EXEC no acepta expresiones como parametros: van a variables
            DECLARE @TipoAj NVARCHAR(10) = CASE WHEN @Dif > 0 THEN 'Ingreso' ELSE 'Egreso' END;
            DECLARE @MontoAj DECIMAL(12,2) = ABS(@Dif);
            EXEC SP_MovimientoCaja_RegistrarInterno
                 @Tipo = @TipoAj,
                 @Concepto = 'Diferencia de apertura',
                 @Monto = @MontoAj,
                 @Descripcion = @Motivo,
                 @IdUsuario = @IdUsuario;
        END

        COMMIT;
        SELECT @IdSesion AS IdSesion, @Sugerido AS SaldoSugerido, @SaldoInicial AS SaldoInicial, @Dif AS Diferencia;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   5. Cerrar con arqueo
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_SesionCaja_Cerrar', 'P') IS NOT NULL DROP PROCEDURE SP_SesionCaja_Cerrar;
GO
CREATE PROCEDURE SP_SesionCaja_Cerrar
    @EfectivoContado DECIMAL(12,2),
    @Motivo          NVARCHAR(250) = NULL,
    @IdUsuario       INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF @EfectivoContado IS NULL OR @EfectivoContado < 0
            RAISERROR('El efectivo contado no puede ser negativo.', 16, 1);

        BEGIN TRANSACTION;

        DECLARE @IdSesion INT;
        SELECT @IdSesion = s.Id
        FROM SesionCaja s WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN CuentaFinanciera c ON c.Id = s.IdCuentaFinanciera
        WHERE s.Estado = 'ABIERTA' AND c.EsCaja = 1;

        IF @IdSesion IS NULL
            RAISERROR('La caja no esta abierta.', 16, 1);

        -- Teorico = lo que dice el sistema ahora. Se bloquea: una venta
        -- que entre en este instante espera a que termine el cierre.
        DECLARE @Teorico DECIMAL(12,2);
        SELECT TOP 1 @Teorico = SaldoResultante FROM MovimientoCaja WITH (UPDLOCK, HOLDLOCK) ORDER BY Id DESC;
        SET @Teorico = ISNULL(@Teorico, 0);

        DECLARE @Dif DECIMAL(12,2) = @EfectivoContado - @Teorico;
        IF @Dif <> 0 AND LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 10
            RAISERROR('El efectivo contado no coincide con el del sistema: explica la diferencia con al menos 10 caracteres.', 16, 1);

        -- La diferencia se registra como movimiento de la misma sesion:
        -- despues del cierre, el sistema dice lo mismo que el cajon.
        IF @Dif <> 0
        BEGIN
            -- EXEC no acepta expresiones como parametros: van a variables
            DECLARE @TipoAj NVARCHAR(10) = CASE WHEN @Dif > 0 THEN 'Ingreso' ELSE 'Egreso' END;
            DECLARE @MontoAj DECIMAL(12,2) = ABS(@Dif);
            EXEC SP_MovimientoCaja_RegistrarInterno
                 @Tipo = @TipoAj,
                 @Concepto = 'Diferencia de arqueo',
                 @Monto = @MontoAj,
                 @Descripcion = @Motivo,
                 @IdUsuario = @IdUsuario;
        END

        UPDATE SesionCaja
        SET Estado = 'CERRADA', FechaCierre = GETDATE(), IdUsuarioCierre = @IdUsuario,
            SaldoTeorico = @Teorico, EfectivoContado = @EfectivoContado, Diferencia = @Dif,
            MotivoDiferencia = CASE WHEN @Dif <> 0 THEN LTRIM(RTRIM(@Motivo)) END
        WHERE Id = @IdSesion;

        COMMIT;
        SELECT @IdSesion AS IdSesion, @Teorico AS SaldoTeorico, @EfectivoContado AS EfectivoContado, @Dif AS Diferencia;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   6. Consultas
   ----------------------------------------------------------------- */

-- Estado actual: si hay sesion abierta, su resumen; si no, lo que se
-- sugeriria para abrir.
IF OBJECT_ID('SP_SesionCaja_Actual', 'P') IS NOT NULL DROP PROCEDURE SP_SesionCaja_Actual;
GO
CREATE PROCEDURE SP_SesionCaja_Actual
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @IdSesion INT;
    SELECT @IdSesion = s.Id FROM SesionCaja s INNER JOIN CuentaFinanciera c ON c.Id = s.IdCuentaFinanciera
    WHERE s.Estado = 'ABIERTA' AND c.EsCaja = 1;

    IF @IdSesion IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Abierta, dbo.fn_SaldoCaja() AS SaldoSugerido,
               (SELECT TOP 1 FechaCierre FROM SesionCaja WHERE Estado = 'CERRADA' ORDER BY Id DESC) AS UltimoCierre;
        RETURN;
    END

    SELECT
        CAST(1 AS BIT) AS Abierta,
        s.Id AS IdSesion, s.FechaApertura, u.Nombre AS UsuarioApertura, s.SaldoInicial,
        ISNULL(SUM(CASE WHEN m.Tipo = 'Ingreso' AND m.Concepto <> 'Diferencia de apertura' THEN m.Monto END), 0) AS Ingresos,
        ISNULL(SUM(CASE WHEN m.Tipo = 'Egreso'  AND m.Concepto <> 'Diferencia de apertura' THEN m.Monto END), 0) AS Egresos,
        COUNT(m.Id) AS Movimientos,
        dbo.fn_SaldoCaja() AS SaldoTeorico,
        -- Una sesion que viene de otro dia: alguien se olvido de cerrar
        CASE WHEN CAST(s.FechaApertura AS DATE) < CAST(GETDATE() AS DATE) THEN 1 ELSE 0 END AS DeOtroDia
    FROM SesionCaja s
    LEFT JOIN Usuario u ON u.Id = s.IdUsuarioApertura
    LEFT JOIN MovimientoCaja m ON m.IdSesionCaja = s.Id
    WHERE s.Id = @IdSesion
    GROUP BY s.Id, s.FechaApertura, u.Nombre, s.SaldoInicial;
END
GO

IF OBJECT_ID('SP_SesionCaja_Historial', 'P') IS NOT NULL DROP PROCEDURE SP_SesionCaja_Historial;
GO
CREATE PROCEDURE SP_SesionCaja_Historial
    @Desde DATE = NULL,
    @Hasta DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @Desde IS NULL SET @Desde = DATEADD(DAY, -30, CAST(GETDATE() AS DATE));
    IF @Hasta IS NULL SET @Hasta = CAST(GETDATE() AS DATE);

    SELECT s.Id, s.Estado, s.FechaApertura, ua.Nombre AS UsuarioApertura, s.SaldoInicial,
           s.SaldoSugerido, s.MotivoApertura,
           s.FechaCierre, uc.Nombre AS UsuarioCierre, s.SaldoTeorico, s.EfectivoContado,
           s.Diferencia, s.MotivoDiferencia,
           (SELECT COUNT(*) FROM MovimientoCaja m WHERE m.IdSesionCaja = s.Id) AS Movimientos
    FROM SesionCaja s
    LEFT JOIN Usuario ua ON ua.Id = s.IdUsuarioApertura
    LEFT JOIN Usuario uc ON uc.Id = s.IdUsuarioCierre
    WHERE CAST(s.FechaApertura AS DATE) BETWEEN @Desde AND @Hasta
    ORDER BY s.Id DESC;
END
GO

-- Diferencias acumuladas: si se repiten, hay un problema que investigar
IF OBJECT_ID('SP_SesionCaja_ResumenDiferencias', 'P') IS NOT NULL DROP PROCEDURE SP_SesionCaja_ResumenDiferencias;
GO
CREATE PROCEDURE SP_SesionCaja_ResumenDiferencias
    @Desde DATE = NULL,
    @Hasta DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @Desde IS NULL SET @Desde = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1);
    IF @Hasta IS NULL SET @Hasta = CAST(GETDATE() AS DATE);

    SELECT COUNT(*) AS Cierres,
           SUM(CASE WHEN Diferencia <> 0 THEN 1 ELSE 0 END) AS ConDiferencia,
           ISNULL(SUM(CASE WHEN Diferencia > 0 THEN Diferencia END), 0) AS Sobrantes,
           ISNULL(SUM(CASE WHEN Diferencia < 0 THEN -Diferencia END), 0) AS Faltantes,
           ISNULL(SUM(Diferencia), 0) AS Neto
    FROM SesionCaja
    WHERE Estado = 'CERRADA' AND CAST(FechaCierre AS DATE) BETWEEN @Desde AND @Hasta;
END
GO


/* -----------------------------------------------------------------
   PRUEBA (descomentar)
   ----------------------------------------------------------------- */
/*
EXEC SP_SesionCaja_Actual;                                   -- cerrada, sugiere el saldo actual

-- Una venta en efectivo ahora tiene que fallar con "La caja esta cerrada"

DECLARE @s DECIMAL(12,2) = dbo.fn_SaldoCaja();
EXEC SP_SesionCaja_Abrir @SaldoInicial = @s, @IdUsuario = 1;   -- abre sin diferencia
EXEC SP_SesionCaja_Actual;                                     -- abierta

-- ... registrar una venta en efectivo ...

DECLARE @t DECIMAL(12,2) = dbo.fn_SaldoCaja();
SET @t = @t - 1000;                                            -- faltan $1.000
EXEC SP_SesionCaja_Cerrar @EfectivoContado = @t, @IdUsuario = 1;   -- falla: falta motivo
EXEC SP_SesionCaja_Cerrar @EfectivoContado = @t, @Motivo = 'Vuelto mal dado a un cliente', @IdUsuario = 1;
EXEC SP_SesionCaja_Historial;
*/
GO
