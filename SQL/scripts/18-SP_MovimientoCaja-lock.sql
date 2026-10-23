USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   SP_MovimientoCaja_RegistrarInterno — bloqueo en la lectura

   PROBLEMA
   El saldo se calcula leyendo el SaldoResultante del ultimo
   movimiento. Esa lectura no tomaba ningun bloqueo, asi que dos
   operaciones simultaneas podian leer el mismo saldo de partida y
   calcular las dos sobre la misma base.

   Ejemplo: saldo 10.000. Una venta de 2.000 y un pago de 3.000 al
   mismo tiempo. Las dos leen 10.000, una escribe 12.000 y la otra
   13.000. El saldo final queda en 13.000 cuando deberia ser 15.000,
   y no hay forma de detectarlo despues.

   SOLUCION
   UPDLOCK + HOLDLOCK sobre la lectura del ultimo movimiento. La
   segunda operacion espera a que la primera termine, y cuando lee ya
   ve el saldo actualizado. Es el mismo mecanismo que se aplico al
   stock en SP_Venta_I.

   LO QUE NO CAMBIA
   Sigue sin validar saldo negativo, a proposito: los movimientos
   automaticos reflejan operaciones comerciales que ya ocurrieron.
   Impedir el registro no impide el hecho, solo lo esconde.

   Sigue sin abrir transaccion propia: corre dentro de la del SP que
   lo llama.
   ================================================================= */

ALTER PROCEDURE [dbo].[SP_MovimientoCaja_RegistrarInterno]
    @Tipo        NVARCHAR(10),
    @Concepto    NVARCHAR(60),
    @Monto       DECIMAL(12,2),
    @Descripcion NVARCHAR(250),
    @IdUsuario   INT,
    @IdVenta     INT = NULL,
    @IdPedido    INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Monto IS NULL OR @Monto <= 0
    BEGIN
        RAISERROR('El importe del movimiento de caja debe ser mayor a cero.', 16, 1);
        RETURN;
    END

    IF @Tipo NOT IN ('Ingreso', 'Egreso')
    BEGIN
        RAISERROR('El tipo de movimiento debe ser Ingreso o Egreso.', 16, 1);
        RETURN;
    END

    DECLARE @SaldoActual DECIMAL(12,2);

    -- UPDLOCK + HOLDLOCK: sin esto, dos movimientos simultaneos leen
    -- el mismo saldo de partida y uno de los dos se pierde.
    SELECT TOP 1 @SaldoActual = SaldoResultante
    FROM MovimientoCaja WITH (UPDLOCK, HOLDLOCK)
    ORDER BY Id DESC;

    IF @SaldoActual IS NULL SET @SaldoActual = 0;

    DECLARE @NuevoSaldo DECIMAL(12,2);

    IF @Tipo = 'Ingreso'
        SET @NuevoSaldo = @SaldoActual + @Monto;
    ELSE
        SET @NuevoSaldo = @SaldoActual - @Monto;   -- puede quedar negativo, es intencional

    INSERT INTO MovimientoCaja
        (Tipo, Concepto, Monto, Descripcion, SaldoResultante,
         IdUsuario, IdVenta, IdPedido, Automatico)
    VALUES
        (@Tipo, @Concepto, @Monto, @Descripcion, @NuevoSaldo,
         @IdUsuario, @IdVenta, @IdPedido, 1);
END
GO


/* -----------------------------------------------------------------
   CONTROL DE INTEGRIDAD DEL SALDO

   El SaldoResultante es un valor congelado en cada fila. Si alguna
   vez se corrige o borra un movimiento del medio, todos los saldos
   posteriores quedan desactualizados sin que nadie se entere.

   Esta consulta compara el saldo guardado contra el acumulado real.
   Si devuelve filas, hay movimientos con el saldo mal calculado.

   Conviene correrla cada tanto, sobre todo despues de tocar la caja
   a mano.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_MovimientoCaja_VerificarSaldos', 'P') IS NOT NULL
    DROP PROCEDURE SP_MovimientoCaja_VerificarSaldos;
GO

CREATE PROCEDURE SP_MovimientoCaja_VerificarSaldos
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Acumulado AS (
        SELECT
            Id, Fecha, Tipo, Concepto, Monto, SaldoResultante,
            SUM(CASE WHEN Tipo = 'Ingreso' THEN Monto ELSE -Monto END)
                OVER (ORDER BY Id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
                AS SaldoCalculado
        FROM MovimientoCaja
    )
    SELECT
        Id, Fecha, Tipo, Concepto, Monto,
        SaldoResultante AS SaldoGuardado,
        SaldoCalculado,
        SaldoResultante - SaldoCalculado AS Diferencia
    FROM Acumulado
    WHERE ABS(SaldoResultante - SaldoCalculado) > 0.01
    ORDER BY Id;
END
GO


/* -----------------------------------------------------------------
   VERIFICACION
   ----------------------------------------------------------------- */

-- Debe decir que tiene UPDLOCK
SELECT CASE WHEN OBJECT_DEFINITION(OBJECT_ID('SP_MovimientoCaja_RegistrarInterno'))
                 LIKE '%UPDLOCK%'
            THEN 'OK — bloqueo aplicado'
            ELSE 'FALTA' END AS Estado;

-- Si devuelve filas, hay saldos historicos mal calculados
EXEC SP_MovimientoCaja_VerificarSaldos;

-- Saldo actual segun el ultimo movimiento vs el acumulado real
SELECT
    (SELECT TOP 1 SaldoResultante FROM MovimientoCaja ORDER BY Id DESC) AS SaldoUltimoMovimiento,
    (SELECT ISNULL(SUM(CASE WHEN Tipo = 'Ingreso' THEN Monto ELSE -Monto END), 0)
     FROM MovimientoCaja) AS SaldoAcumuladoReal;
GO
