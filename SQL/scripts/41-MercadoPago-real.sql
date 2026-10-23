USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   41 — MERCADO PAGO CON DATOS REALES

   Fuente: reporte de liquidaciones de Mercado Pago del 01/09/2026 al
   17/09/2026 (419 cobros, $9.430.301,81). Comision efectiva total:
   1,88%. Todo se acredita al instante.

   Dato del negocio: TODO lo electronico entra a Mercado Pago (QR,
   transferencias, debito y credito por Point, rendimientos). No hay
   cuenta bancaria operativa.

   Tasas: la que se repite en cada medio (la mediana del reporte).
     Transferencia directa al CVU            0,00%   (53 cobros)
     QR con dinero en cuenta o transferencia 0,97%   (143 cobros)
     Point con debito                        2,40%   (42 cobros)
     Point con prepaga                       4,00%   (11 cobros)
     Point o QR con credito                  6,46%   (15 cobros)
   El QR pagado con debito cobra 1,71%, pero fueron 4 de 152: se deja
   el QR en 0,97% y, si el cliente paga el QR con credito, el vendedor
   elige Credito.
   ================================================================= */

DECLARE @MP INT = (SELECT Id FROM CuentaFinanciera WHERE Codigo = 'MP');
DECLARE @BANCO INT = (SELECT Id FROM CuentaFinanciera WHERE Codigo = 'BANCO');

/* 1. Tasas reales y cuenta correcta */
UPDATE MedioPago SET ComisionPorc = 0.00, IdCuentaFinanciera = @MP WHERE Codigo = 'TRF';
UPDATE MedioPago SET ComisionPorc = 0.97, IdCuentaFinanciera = @MP, Nombre = N'QR Mercado Pago' WHERE Codigo = 'QR';
UPDATE MedioPago SET ComisionPorc = 2.40, IdCuentaFinanciera = @MP WHERE Codigo = 'DEB';
UPDATE MedioPago SET ComisionPorc = 6.46, IdCuentaFinanciera = @MP WHERE Codigo = 'CRE';

/* 2. Prepaga: aparecio 11 veces en el reporte */
IF NOT EXISTS (SELECT 1 FROM MedioPago WHERE Codigo = 'PRE')
    INSERT INTO MedioPago (Codigo, Nombre, ComisionPorc, IdCuentaFinanciera, Orden)
    VALUES ('PRE', N'Prepaga', 4.00, @MP, 5);
UPDATE MedioPago SET Orden = 6 WHERE Codigo = 'CRE';

/* 3. Banco: no existe como cuenta operativa.
   No se borra: tiene claves foraneas y puede usarse en el futuro. Se
   desactiva, y lo registrado ahi pasa a Mercado Pago, que es donde el
   dinero entro de verdad. Es la correccion de un error de
   configuracion, no la reescritura de un hecho. */
UPDATE MovimientoCuentaFinanciera SET IdCuentaFinanciera = @MP WHERE IdCuentaFinanciera = @BANCO;
UPDATE CuentaFinanciera SET Activo = 0 WHERE Id = @BANCO;
GO


/* -----------------------------------------------------------------
   4. RENDIMIENTO como quinto movimiento especial
   Los intereses que paga Mercado Pago por el saldo son dinero real,
   con el reporte como respaldo. No son aporte (no los pone el dueño)
   ni ajuste (no corrigen un error). Tipo propio, solo destino.
   ----------------------------------------------------------------- */
ALTER TABLE MovimientoEspecial DROP CONSTRAINT CK_MovEsp_Tipo;
ALTER TABLE MovimientoEspecial ADD CONSTRAINT CK_MovEsp_Tipo
    CHECK (Tipo IN ('APORTE', 'RETIRO', 'TRANSFERENCIA', 'AJUSTE', 'RENDIMIENTO'));

ALTER TABLE MovimientoEspecial DROP CONSTRAINT CK_MovEsp_Cuentas;
ALTER TABLE MovimientoEspecial ADD CONSTRAINT CK_MovEsp_Cuentas CHECK (
    (Tipo IN ('APORTE', 'RENDIMIENTO') AND IdCuentaOrigen IS NULL     AND IdCuentaDestino IS NOT NULL) OR
    (Tipo = 'RETIRO'                   AND IdCuentaOrigen IS NOT NULL AND IdCuentaDestino IS NULL) OR
    (Tipo = 'TRANSFERENCIA'            AND IdCuentaOrigen IS NOT NULL AND IdCuentaDestino IS NOT NULL
                                       AND IdCuentaOrigen <> IdCuentaDestino) OR
    (Tipo = 'AJUSTE'                   AND ((IdCuentaOrigen IS NULL AND IdCuentaDestino IS NOT NULL) OR
                                            (IdCuentaOrigen IS NOT NULL AND IdCuentaDestino IS NULL)))
);
GO

ALTER PROCEDURE SP_MovimientoEspecial_I
    @Tipo            VARCHAR(15),
    @IdCuentaOrigen  INT = NULL,
    @IdCuentaDestino INT = NULL,
    @Importe         DECIMAL(12,2),
    @Motivo          NVARCHAR(250),
    @IdAdjunto       INT = NULL,
    @IdUsuario       INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF @Tipo NOT IN ('APORTE', 'RETIRO', 'TRANSFERENCIA', 'AJUSTE', 'RENDIMIENTO')
            RAISERROR('Tipo de movimiento no permitido. Solo aporte, retiro, transferencia, ajuste o rendimiento.', 16, 1);
        IF @Importe IS NULL OR @Importe <= 0
            RAISERROR('El importe debe ser mayor a cero.', 16, 1);
        IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 10
            RAISERROR('El motivo es obligatorio y debe tener al menos 10 caracteres.', 16, 1);

        BEGIN TRANSACTION;

        INSERT INTO MovimientoEspecial (Tipo, IdCuentaOrigen, IdCuentaDestino, Importe, Motivo, IdAdjunto, IdUsuario)
        VALUES (@Tipo, @IdCuentaOrigen, @IdCuentaDestino, @Importe, LTRIM(RTRIM(@Motivo)), @IdAdjunto, @IdUsuario);

        DECLARE @Id INT = SCOPE_IDENTITY();
        DECLARE @Concepto NVARCHAR(60) =
            CASE @Tipo WHEN 'APORTE'        THEN 'Aporte del propietario'
                       WHEN 'RETIRO'        THEN 'Retiro del propietario'
                       WHEN 'TRANSFERENCIA' THEN 'Transferencia entre cuentas'
                       WHEN 'RENDIMIENTO'   THEN 'Rendimiento de cuenta'
                       ELSE 'Ajuste' END;
        DECLARE @Desc NVARCHAR(250) = LEFT('Mov. especial #' + CAST(@Id AS NVARCHAR(10)) + ': ' + @Motivo, 250);

        IF @IdCuentaOrigen IS NOT NULL
            EXEC SP_Cuenta_RegistrarMovimiento
                 @IdCuentaFinanciera = @IdCuentaOrigen, @Tipo = 'Egreso', @Concepto = @Concepto,
                 @Monto = @Importe, @Descripcion = @Desc, @IdUsuario = @IdUsuario, @IdMovimientoEspecial = @Id;

        IF @IdCuentaDestino IS NOT NULL
            EXEC SP_Cuenta_RegistrarMovimiento
                 @IdCuentaFinanciera = @IdCuentaDestino, @Tipo = 'Ingreso', @Concepto = @Concepto,
                 @Monto = @Importe, @Descripcion = @Desc, @IdUsuario = @IdUsuario, @IdMovimientoEspecial = @Id;

        COMMIT;
        SELECT @Id AS Id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   VERIFICACION
   ----------------------------------------------------------------- */
SELECT m.Codigo, m.Nombre, m.ComisionPorc AS [Comision %], c.Nombre AS Cuenta, m.Orden
FROM MedioPago m INNER JOIN CuentaFinanciera c ON c.Id = m.IdCuentaFinanciera
WHERE m.Activo = 1 ORDER BY m.Orden;

SELECT Codigo, Nombre, Activo FROM CuentaFinanciera;

-- Debe dar 0: nada quedo en la cuenta desactivada
SELECT COUNT(*) AS MovimientosEnBanco
FROM MovimientoCuentaFinanciera mcf INNER JOIN CuentaFinanciera c ON c.Id = mcf.IdCuentaFinanciera
WHERE c.Codigo = 'BANCO';
GO
