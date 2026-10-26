USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   82 — LIMITE DE CREDITO EN CUENTA CORRIENTE

   Reglas (definidas con el negocio):
   - SOLO LOS MECANICOS tienen cuenta corriente. El resto de los
     clientes paga en el momento. Marcar a alguien como mecanico le
     habilita la cuenta; desmarcarlo se la quita (si no debe nada).
   - El limite es OPCIONAL por mecanico. Vacio = sin limite. Los
     mecanicos arrancan sin limite; se les pone solo si se quiere.
   - Ademas del monto, se frena a quien tiene deuda vieja: si la deuda
     mas antigua sin cubrir tiene mas de N dias (parametro
     DiasMaximoDeudaCtaCte; 0 = no se controla).
   - Si una venta a cuenta corriente pasaria el limite o el cliente
     esta atrasado, el vendedor no puede seguir. El Dueño o un
     Administrador si, y queda registrado quien lo autorizo.

   Deuda mas antigua: los pagos (y notas de credito) cubren primero
   lo mas viejo. La primera compra que no llega a estar cubierta es
   desde cuando debe. No se guarda: se calcula.

   Tambien: el alta de un mecanico le habilita cuenta corriente (era la
   regla del script 15, pero solo se aplico a los que ya existian).

   Requiere los scripts 15, 19, 62.
   ================================================================= */


/* -----------------------------------------------------------------
   1. Limite en la ficha del cliente
   ----------------------------------------------------------------- */
IF COL_LENGTH('Cliente', 'LimiteCredito') IS NULL
    ALTER TABLE Cliente ADD LimiteCredito DECIMAL(12,2) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Cliente_LimiteCredito')
    ALTER TABLE Cliente ADD CONSTRAINT CK_Cliente_LimiteCredito CHECK (LimiteCredito IS NULL OR LimiteCredito >= 0);
GO


-- Cuenta corriente = mecanico (sin tocar a quien no es mecanico y debe)
UPDATE Cliente SET CuentaCorriente = 1
WHERE EsMecanico = 1 AND ISNULL(Dni, '') NOT IN ('00000000', '00000001') AND CuentaCorriente = 0;
UPDATE c SET CuentaCorriente = 0, LimiteCredito = NULL
FROM Cliente c
WHERE c.EsMecanico = 0 AND c.CuentaCorriente = 1
  AND ISNULL((SELECT SUM(m.Monto) FROM MovimientoCuentaCorriente m WHERE m.IdCliente = c.Id), 0) <= 0.009;
GO


/* -----------------------------------------------------------------
   2. Dias maximos de deuda sin pagar (editable en Configuracion)
   ----------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM ParametroSistema WHERE Clave = 'DiasMaximoDeudaCtaCte')
    INSERT INTO ParametroSistema (Clave, Valor, Descripcion, Tipo, Editable)
    VALUES ('DiasMaximoDeudaCtaCte', '60',
            'Dias que puede tener la deuda mas vieja de un cliente antes de frenar nuevas ventas a cuenta corriente (0 = no se controla)',
            'entero', 1);
GO


/* -----------------------------------------------------------------
   3. Registro de autorizaciones
   ----------------------------------------------------------------- */
IF OBJECT_ID('AutorizacionCredito', 'U') IS NULL
BEGIN
    CREATE TABLE AutorizacionCredito (
        Id             INT IDENTITY(1,1) PRIMARY KEY,
        Fecha          DATETIME      NOT NULL DEFAULT GETDATE(),
        IdVenta        INT           NOT NULL REFERENCES Venta(Id),
        IdCliente      INT           NOT NULL REFERENCES Cliente(Id),
        IdUsuario      INT           NOT NULL REFERENCES Usuario(Id),
        SaldoAnterior  DECIMAL(12,2) NOT NULL,   -- lo que debia antes de la venta
        Importe        DECIMAL(12,2) NOT NULL,   -- lo que la venta sumo a la cuenta
        Limite         DECIMAL(12,2) NULL,
        DiasAtraso     INT           NOT NULL,
        DiasMaximo     INT           NOT NULL,
        Motivo         VARCHAR(20)   NOT NULL,
        CONSTRAINT CK_AutCred_Motivo CHECK (Motivo IN ('LIMITE', 'ATRASO', 'LIMITE_Y_ATRASO'))
    );
    CREATE INDEX IX_AutCred_Cliente ON AutorizacionCredito (IdCliente, Fecha);
END
GO


/* -----------------------------------------------------------------
   4. Situacion de credito de un cliente
   ----------------------------------------------------------------- */
IF OBJECT_ID('fn_CreditoCliente', 'IF') IS NOT NULL DROP FUNCTION fn_CreditoCliente;
GO
CREATE FUNCTION fn_CreditoCliente (@IdCliente INT)
RETURNS TABLE
AS
RETURN
WITH Mov AS (
    SELECT Id, Fecha, Monto FROM MovimientoCuentaCorriente WHERE IdCliente = @IdCliente
),
Tot AS (
    SELECT ISNULL(SUM(Monto), 0)                                  AS Saldo,
           ISNULL(-SUM(CASE WHEN Monto < 0 THEN Monto END), 0)    AS Haber,
           MAX(CASE WHEN Monto < 0 THEN Fecha END)                AS UltimoPago
    FROM Mov
),
Debe AS (
    SELECT Fecha, SUM(Monto) OVER (ORDER BY Fecha, Id ROWS UNBOUNDED PRECEDING) AS Acumulado
    FROM Mov WHERE Monto > 0
),
Par AS (
    SELECT ISNULL(TRY_CAST((SELECT Valor FROM ParametroSistema WHERE Clave = 'DiasMaximoDeudaCtaCte') AS INT), 0) AS DiasMaximo
)
SELECT
    c.Id AS IdCliente, c.CuentaCorriente, c.EsMecanico, c.LimiteCredito,
    t.Saldo,
    CAST(CASE WHEN c.LimiteCredito IS NULL THEN NULL ELSE c.LimiteCredito - t.Saldo END AS DECIMAL(12,2)) AS Disponible,
    CASE WHEN t.Saldo > 0.009 THEN d.DeudaDesde END AS DeudaDesde,
    CASE WHEN t.Saldo > 0.009 AND d.DeudaDesde IS NOT NULL
         THEN DATEDIFF(DAY, d.DeudaDesde, GETDATE()) ELSE 0 END AS DiasAtraso,
    p.DiasMaximo,
    t.UltimoPago
FROM Cliente c
CROSS JOIN Tot t
CROSS JOIN Par p
OUTER APPLY (SELECT MIN(x.Fecha) AS DeudaDesde FROM Debe x WHERE x.Acumulado > t.Haber + 0.009) d
WHERE c.Id = @IdCliente;
GO

IF OBJECT_ID('SP_Cliente_Credito', 'P') IS NOT NULL DROP PROCEDURE SP_Cliente_Credito;
GO
CREATE PROCEDURE SP_Cliente_Credito
    @IdCliente INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT f.*,
           CASE WHEN f.LimiteCredito IS NOT NULL AND f.Saldo > f.LimiteCredito + 0.01 THEN 1 ELSE 0 END AS PasaLimite,
           CASE WHEN f.DiasMaximo > 0 AND f.DiasAtraso > f.DiasMaximo THEN 1 ELSE 0 END AS Atrasado
    FROM dbo.fn_CreditoCliente(@IdCliente) f;

    SELECT TOP 10 a.Fecha, a.IdVenta, a.Importe, a.SaldoAnterior, a.Limite, a.DiasAtraso, a.Motivo, u.Nombre AS Usuario
    FROM AutorizacionCredito a
    INNER JOIN Usuario u ON u.Id = a.IdUsuario
    WHERE a.IdCliente = @IdCliente
    ORDER BY a.Fecha DESC;
END
GO


/* -----------------------------------------------------------------
   5. Alta y edicion del cliente: la cuenta corriente sale de la marca
   de mecanico. @CambiarCredito = 1 solo cuando el limite lo manda
   quien puede (Dueño o Administrador); si no, el limite no se toca.
   ----------------------------------------------------------------- */
ALTER PROCEDURE [dbo].[SP_Cliente_I]
    @Dni            VARCHAR(8),
    @Nombre         VARCHAR(50),
    @Apellido       VARCHAR(50),
    @Telefono       VARCHAR(30),
    @Mail           VARCHAR(100),
    @Calle          VARCHAR(100),
    @Numero         VARCHAR(15),
    @EsMecanico     BIT = 0,
    @LimiteCredito  DECIMAL(12,2) = NULL,
    @CambiarCredito BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @EsMecanico = 1 AND (@Telefono IS NULL OR LTRIM(RTRIM(@Telefono)) = '')
    BEGIN
        RAISERROR('El teléfono es obligatorio para un mecánico.', 16, 1);
        RETURN;
    END
    IF @LimiteCredito IS NOT NULL AND @LimiteCredito < 0
    BEGIN
        RAISERROR('El límite de crédito no puede ser negativo.', 16, 1);
        RETURN;
    END

    IF @Dni IS NOT NULL AND LTRIM(RTRIM(@Dni)) = ''
        SET @Dni = NULL;

    -- Cuenta corriente solo para mecanicos. Los clientes genericos del
    -- mostrador nunca fian: mezclarian la deuda de todos.
    DECLARE @cc BIT = CASE WHEN @EsMecanico = 1 AND ISNULL(@Dni, '') NOT IN ('00000000', '00000001') THEN 1 ELSE 0 END;

    INSERT INTO Cliente (Dni, Nombre, Apellido, Telefono, Mail, Calle, Numero, EsMecanico, CuentaCorriente, LimiteCredito)
    VALUES (@Dni, @Nombre, @Apellido, @Telefono, @Mail, @Calle, @Numero, @EsMecanico, @cc,
            CASE WHEN @CambiarCredito = 1 AND @cc = 1 THEN @LimiteCredito END);

    SELECT CAST(SCOPE_IDENTITY() AS INT) AS Id;
END
GO

ALTER PROCEDURE [dbo].[SP_Cliente_U]
    @Id             INT,
    @Dni            VARCHAR(8),
    @Nombre         VARCHAR(50),
    @Apellido       VARCHAR(50),
    @Telefono       VARCHAR(30),
    @Mail           VARCHAR(100),
    @Calle          VARCHAR(100),
    @Numero         VARCHAR(15),
    @EsMecanico     BIT = 0,
    @LimiteCredito  DECIMAL(12,2) = NULL,
    @CambiarCredito BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @EsMecanico = 1 AND (@Telefono IS NULL OR LTRIM(RTRIM(@Telefono)) = '')
    BEGIN
        RAISERROR('El teléfono es obligatorio para un mecánico.', 16, 1);
        RETURN;
    END
    IF @LimiteCredito IS NOT NULL AND @LimiteCredito < 0
    BEGIN
        RAISERROR('El límite de crédito no puede ser negativo.', 16, 1);
        RETURN;
    END
    -- Sacarle la marca de mecanico le cierra la cuenta corriente: no si debe
    IF @EsMecanico = 0
       AND ISNULL((SELECT SUM(Monto) FROM MovimientoCuentaCorriente WHERE IdCliente = @Id), 0) > 0.009
    BEGIN
        RAISERROR('No se le puede quitar la marca de mecánico: tiene deuda en cuenta corriente. Primero tiene que pagarla.', 16, 1);
        RETURN;
    END

    DECLARE @cc BIT = CASE WHEN @EsMecanico = 1 AND ISNULL(@Dni, '') NOT IN ('00000000', '00000001') THEN 1 ELSE 0 END;

    IF @Dni IS NOT NULL AND LTRIM(RTRIM(@Dni)) = ''
        SET @Dni = NULL;

    UPDATE Cliente
    SET Dni        = @Dni,
        Nombre     = @Nombre,
        Apellido   = @Apellido,
        Telefono   = @Telefono,
        Mail       = @Mail,
        Calle      = @Calle,
        Numero     = @Numero,
        EsMecanico = @EsMecanico,
        CuentaCorriente = @cc,
        LimiteCredito   = CASE WHEN @cc = 0 THEN NULL
                               WHEN @CambiarCredito = 1 THEN @LimiteCredito
                               ELSE LimiteCredito END
    WHERE Id = @Id;
END
GO

ALTER PROCEDURE [dbo].[SP_Cliente_GetAll]
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Id, Dni, Nombre, Apellido, Telefono, Mail, Calle, Numero, Activo,
           EsMecanico, CuentaCorriente, LimiteCredito
    FROM Cliente
    ORDER BY Apellido, Nombre;
END
GO

ALTER PROCEDURE [dbo].[SP_Cliente_GetById]
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Id, Dni, Nombre, Apellido, Telefono, Mail, Calle, Numero, Activo,
           EsMecanico, CuentaCorriente, LimiteCredito
    FROM Cliente
    WHERE Id = @Id;
END
GO


/* -----------------------------------------------------------------
   6. La venta controla el limite y la deuda atrasada
   (es el SP_Venta_I del script 62 con el control agregado)
   ----------------------------------------------------------------- */
ALTER PROCEDURE [dbo].[SP_Venta_I]
    @IdCliente           INT,
    @IdUsuario           INT,
    @Detalle             DetalleVentaType READONLY,
    -- nuevos
    @PorcentajeDescuento DECIMAL(6,2)  = 0,
    @FormaPago           VARCHAR(20)   = 'Contado',   -- 'Contado' | 'CuentaCorriente'
    @Entrega             DECIMAL(12,2) = NULL,        -- parte que paga en el momento
    @NombreOcasional     NVARCHAR(80)  = NULL,
    @TelefonoOcasional   NVARCHAR(30)  = NULL,
    @TipoCliente         NVARCHAR(20)  = NULL,        -- 'Publico' | 'Mecanico'
    -- formas de pago: lista de (medio, monto). Si viene vacia, se usan
    -- @FormaPago y @Entrega como antes (compatibilidad con clientes viejos)
    @Pagos               VentaPagoType READONLY,
    -- Entrega de un encargo: la sena ya cobrada se aplica con el medio SEN
    @IdEncargo           INT = NULL,
    -- Limite de credito (script 82): el Dueño o un Administrador autoriza pasarlo
    @AutorizarCredito    BIT = 0,
    -- Rol de quien vende: lo pone la API desde el token (no viene de la pantalla)
    @RolUsuario          NVARCHAR(30) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        /* ---------- Validaciones de cabecera ---------- */

        IF NOT EXISTS (SELECT 1 FROM @Detalle)
            RAISERROR('La venta debe tener al menos un repuesto.', 16, 1);

        IF EXISTS (SELECT IdRepuesto FROM @Detalle GROUP BY IdRepuesto HAVING COUNT(*) > 1)
            RAISERROR('Hay un repuesto repetido en el detalle de la venta.', 16, 1);

        IF @PorcentajeDescuento IS NULL SET @PorcentajeDescuento = 0;

        IF @PorcentajeDescuento < 0 OR @PorcentajeDescuento > 100
            RAISERROR('El descuento debe estar entre 0 y 100.', 16, 1);

        IF @FormaPago IS NULL OR @FormaPago = '' SET @FormaPago = 'Contado';

        IF @FormaPago NOT IN ('Contado', 'CuentaCorriente')
            RAISERROR('La forma de pago debe ser Contado o CuentaCorriente.', 16, 1);

        /* ---------- Stock ----------
           UPDLOCK + HOLDLOCK: sin eso, dos ventas simultaneas del
           ultimo ejemplar pasan ambas la validacion y el stock queda
           en negativo. */

        DECLARE @SinFilaStock NVARCHAR(200);
        SELECT TOP 1 @SinFilaStock = r.Descripcion
        FROM @Detalle d
        INNER JOIN Repuesto r ON r.Id = d.IdRepuesto
        LEFT JOIN Stock s WITH (UPDLOCK, HOLDLOCK) ON s.IdRepuesto = d.IdRepuesto
        WHERE s.IdRepuesto IS NULL;

        IF @SinFilaStock IS NOT NULL
            RAISERROR('El repuesto "%s" no tiene stock inicializado. Registralo con un ajuste de stock antes de venderlo.', 16, 1, @SinFilaStock);

        DECLARE @RepuestoSinStock NVARCHAR(200), @Disponible INT;
        SELECT TOP 1
            @RepuestoSinStock = r.Descripcion,
            @Disponible = s.Cantidad
        FROM @Detalle d
        INNER JOIN Repuesto r ON r.Id = d.IdRepuesto
        INNER JOIN Stock s WITH (UPDLOCK, HOLDLOCK) ON s.IdRepuesto = d.IdRepuesto
        WHERE s.Cantidad < d.Cantidad;

        IF @RepuestoSinStock IS NOT NULL
            RAISERROR('Stock insuficiente para "%s". Disponible: %d.', 16, 1, @RepuestoSinStock, @Disponible);

        /* Stock reservado: lo que llego para un encargo abierto no se le
           vende a otro cliente. Si esta venta ES la entrega de un encargo,
           lo reservado para ese encargo no cuenta. */
        DECLARE @RepuestoReservado NVARCHAR(200), @Libre INT, @Reservado INT;
        SELECT TOP 1
            @RepuestoReservado = r.Descripcion,
            @Libre = s.Cantidad - rv.Reservado,
            @Reservado = rv.Reservado
        FROM @Detalle d
        INNER JOIN Repuesto r ON r.Id = d.IdRepuesto
        INNER JOIN Stock s ON s.IdRepuesto = d.IdRepuesto
        CROSS APPLY (SELECT ISNULL(SUM(ed.Cantidad), 0) AS Reservado
                     FROM EncargoDetalle ed INNER JOIN Encargo e ON e.Id = ed.IdEncargo
                     WHERE ed.IdRepuesto = d.IdRepuesto AND e.Estado IN ('PENDIENTE', 'AVISADO')
                       AND (@IdEncargo IS NULL OR e.Id <> @IdEncargo)) rv
        WHERE rv.Reservado > 0 AND s.Cantidad - rv.Reservado < d.Cantidad;

        IF @RepuestoReservado IS NOT NULL
        BEGIN
            IF @Libre < 0 SET @Libre = 0;
            RAISERROR('"%s": hay %d libre(s) y %d reservado(s) para encargos. Entregalo desde Encargos o cancelá el encargo.',
                      16, 1, @RepuestoReservado, @Libre, @Reservado);
        END

        /* ---------- Importes ---------- */

        DECLARE @Subtotal DECIMAL(12,2), @Descuento DECIMAL(12,2), @Total DECIMAL(12,2);

        SELECT @Subtotal = SUM(CAST(Cantidad AS DECIMAL(12,2)) * PrecioUnitario)
        FROM @Detalle;

        IF @Subtotal IS NULL OR @Subtotal <= 0
            RAISERROR('El total de la venta debe ser mayor a cero.', 16, 1);

        SET @Descuento = CAST(@Subtotal * @PorcentajeDescuento / 100.0 AS DECIMAL(12,2));
        SET @Total     = @Subtotal - @Descuento;

        IF @Total <= 0
            RAISERROR('El total de la venta despues del descuento debe ser mayor a cero.', 16, 1);

        /* Neto e IVA por renglon: cada repuesto puede tener su alicuota.
           El descuento se prorratea para que neto + IVA de exactamente
           el total. */
        DECLARE @Neto DECIMAL(12,2), @Iva DECIMAL(12,2);
        DECLARE @factorDesc DECIMAL(18,10) = CASE WHEN @Subtotal > 0
                                                  THEN @Total / @Subtotal ELSE 1 END;

        SELECT @Neto = SUM(
            CAST(d.Cantidad * d.PrecioUnitario * @factorDesc
                 / (1 + ISNULL(a.Porcentaje, 21) / 100.0) AS DECIMAL(12,2)))
        FROM @Detalle d
        INNER JOIN Repuesto r ON r.Id = d.IdRepuesto
        LEFT JOIN AlicuotaIva a ON a.Id = r.IdAlicuotaIva;

        SET @Neto = ISNULL(@Neto, 0);
        SET @Iva  = @Total - @Neto;

        /* ---------- Pagos ----------
           Dos caminos:
             a) Lista de pagos (clientes nuevos): uno o varios medios.
                Lo pagado es la suma; si no llega al total, el resto
                va a cuenta corriente.
             b) Sin lista (clientes viejos): @FormaPago y @Entrega se
                convierten en un unico pago en efectivo. */

        DECLARE @PagosNorm TABLE (IdMedioPago INT, Monto DECIMAL(12,2), Orden INT IDENTITY(1,1));
        DECLARE @Pagado DECIMAL(12,2) = 0;

        IF EXISTS (SELECT 1 FROM @Pagos)
        BEGIN
            IF EXISTS (SELECT 1 FROM @Pagos WHERE Monto <= 0)
                RAISERROR('Cada pago debe tener un importe mayor a cero.', 16, 1);

            IF EXISTS (SELECT 1 FROM @Pagos p LEFT JOIN MedioPago m ON m.Id = p.IdMedioPago AND m.Activo = 1
                       WHERE m.Id IS NULL)
                RAISERROR('Uno de los medios de pago no existe o esta inactivo.', 16, 1);

            INSERT INTO @PagosNorm (IdMedioPago, Monto)
            SELECT IdMedioPago, Monto FROM @Pagos;

            SELECT @Pagado = SUM(Monto) FROM @PagosNorm;

            -- Lo que no se pago va a cuenta corriente
            SET @FormaPago = CASE WHEN @Pagado < @Total THEN 'CuentaCorriente' ELSE 'Contado' END;
            SET @Entrega = @Pagado;
        END
        ELSE
        BEGIN
            -- Camino viejo
            IF @Entrega IS NULL
                SET @Entrega = CASE WHEN @FormaPago = 'Contado' THEN @Total ELSE 0 END;

            IF @FormaPago = 'Contado' AND @Entrega <> @Total
                RAISERROR('En una venta de contado la entrega debe ser igual al total.', 16, 1);

            IF @Entrega > 0
                INSERT INTO @PagosNorm (IdMedioPago, Monto)
                SELECT Id, @Entrega FROM MedioPago WHERE Codigo = 'EFE';

            SET @Pagado = @Entrega;
        END

        IF @Pagado < 0
            RAISERROR('Lo pagado no puede ser negativo.', 16, 1);

        -- Tolerancia de un centavo por redondeos de pago mixto
        IF @Pagado > @Total + 0.01
            RAISERROR('Lo pagado supera el total de la venta.', 16, 1);

        /* ---------- Sena de un encargo ----------
           El medio SEN no mueve dinero: la sena entro a la caja o a
           Mercado Pago cuando se tomo el encargo. Aca solo se aplica, y
           tiene que coincidir con lo que el cliente dejo. */
        DECLARE @SenaAplicada DECIMAL(12,2) = ISNULL((SELECT SUM(pn.Monto) FROM @PagosNorm pn
                                                       INNER JOIN MedioPago m ON m.Id = pn.IdMedioPago
                                                       WHERE m.Codigo = 'SEN'), 0);
        IF @IdEncargo IS NULL AND @SenaAplicada > 0
            RAISERROR('La seña solo se aplica al entregar un encargo.', 16, 1);

        IF @IdEncargo IS NOT NULL
        BEGIN
            DECLARE @EstadoEncargo VARCHAR(12), @SenaEncargo DECIMAL(12,2);
            SELECT @EstadoEncargo = Estado FROM Encargo WITH (UPDLOCK, HOLDLOCK) WHERE Id = @IdEncargo;
            IF @EstadoEncargo IS NULL
                RAISERROR('El encargo no existe.', 16, 1);
            IF @EstadoEncargo IN ('ENTREGADO', 'CANCELADO')
                RAISERROR('Ese encargo ya fue entregado o cancelado.', 16, 1);
            SET @SenaEncargo = ISNULL((SELECT SUM(Monto) FROM EncargoSena WHERE IdEncargo = @IdEncargo), 0);
            IF ABS(@SenaAplicada - @SenaEncargo) > 0.01
                RAISERROR('La seña aplicada no coincide con la que dejó el cliente.', 16, 1);
        END

        DECLARE @RegistrarAutorizacion BIT = 0;

        IF @FormaPago = 'CuentaCorriente'
        BEGIN
            -- Fiar a un cliente generico partiria la deuda de todos los
            -- mecanicos en una sola ficha: no se sabria quien debe que.
            IF NOT EXISTS (SELECT 1 FROM Cliente
                           WHERE Id = @IdCliente AND CuentaCorriente = 1 AND Activo = 1)
                RAISERROR('Ese cliente no tiene cuenta corriente habilitada. Para vender a credito hay que registrarlo.', 16, 1);

            /* Limite de credito y deuda atrasada (script 82).
               La ficha del cliente se bloquea: dos ventas al mismo
               tiempo no pueden pasar el limite entre las dos. */
            DECLARE @cSaldo DECIMAL(12,2), @cLimite DECIMAL(12,2), @cDiasAtraso INT, @cDiasMax INT;
            SELECT @cLimite = LimiteCredito FROM Cliente WITH (UPDLOCK, HOLDLOCK) WHERE Id = @IdCliente;
            SELECT @cSaldo = Saldo, @cDiasAtraso = DiasAtraso, @cDiasMax = DiasMaximo
            FROM dbo.fn_CreditoCliente(@IdCliente);

            DECLARE @cNuevo DECIMAL(12,2) = @Total - @Pagado;
            DECLARE @cPasaLimite BIT = CASE WHEN @cLimite IS NOT NULL AND @cSaldo + @cNuevo > @cLimite + 0.01 THEN 1 ELSE 0 END;
            DECLARE @cAtrasado BIT = CASE WHEN @cDiasMax > 0 AND @cDiasAtraso > @cDiasMax THEN 1 ELSE 0 END;

            IF @cPasaLimite = 1 OR @cAtrasado = 1
            BEGIN
                DECLARE @cPuede BIT = CASE WHEN @RolUsuario IN (N'Dueño', N'Administrador') THEN 1 ELSE 0 END;
                IF @AutorizarCredito = 0 OR @cPuede = 0
                BEGIN
                    -- [CREDITO] le avisa a la pantalla que se puede autorizar
                    DECLARE @cMsg NVARCHAR(500) = N'[CREDITO] ' +
                        CASE WHEN @cPasaLimite = 1
                             THEN N'Con esta venta debería ' + FORMAT(@cSaldo + @cNuevo, 'C0', 'es-AR') +
                                  N' y su límite es ' + FORMAT(@cLimite, 'C0', 'es-AR') + N'.'
                             ELSE N'' END +
                        CASE WHEN @cAtrasado = 1
                             THEN CASE WHEN @cPasaLimite = 1 THEN N' ' ELSE N'' END +
                                  N'Tiene deuda sin pagar hace ' + CAST(@cDiasAtraso AS NVARCHAR(10)) +
                                  N' días (el máximo es ' + CAST(@cDiasMax AS NVARCHAR(10)) + N').'
                             ELSE N'' END +
                        CASE WHEN @cPuede = 1 THEN N''
                             ELSE N' Para seguir lo tiene que autorizar el dueño o un administrador.' END;
                    THROW 50410, @cMsg, 1;
                END
                SET @RegistrarAutorizacion = 1;
            END
        END

        /* ---------- Cabecera ---------- */

        INSERT INTO Venta
            (Fecha, IdCliente, IdUsuario, IdEstadoVenta, Total,
             Neto, Iva, PorcentajeDescuento, Descuento,
             NombreOcasional, TelefonoOcasional, TipoCliente)
        VALUES
            (GETDATE(), @IdCliente, @IdUsuario, 1, @Total,
             @Neto, @Iva, @PorcentajeDescuento, @Descuento,
             NULLIF(LTRIM(RTRIM(@NombreOcasional)), ''),
             NULLIF(LTRIM(RTRIM(@TelefonoOcasional)), ''),
             @TipoCliente);

        DECLARE @IdVenta INT = SCOPE_IDENTITY();

        -- Quien autorizo pasar el limite o fiar con deuda atrasada
        IF @RegistrarAutorizacion = 1
            INSERT INTO AutorizacionCredito
                (IdVenta, IdCliente, IdUsuario, SaldoAnterior, Importe, Limite, DiasAtraso, DiasMaximo, Motivo)
            VALUES
                (@IdVenta, @IdCliente, @IdUsuario, @cSaldo, @cNuevo, @cLimite, @cDiasAtraso, @cDiasMax,
                 CASE WHEN @cPasaLimite = 1 AND @cAtrasado = 1 THEN 'LIMITE_Y_ATRASO'
                      WHEN @cPasaLimite = 1 THEN 'LIMITE' ELSE 'ATRASO' END);

        /* ---------- Detalle, con el costo del momento ---------- */

        INSERT INTO DetalleVenta
            (IdVenta, IdRepuesto, Cantidad, PrecioUnitario, Subtotal, CostoUnitario)
        SELECT
            @IdVenta, d.IdRepuesto, d.Cantidad, d.PrecioUnitario,
            (d.Cantidad * d.PrecioUnitario),
            r.PrecioCompra
        FROM @Detalle d
        INNER JOIN Repuesto r ON r.Id = d.IdRepuesto;

        /* ---------- Stock ---------- */

        UPDATE s
        SET s.Cantidad            = s.Cantidad - d.Cantidad,
            s.UltimaActualizacion = GETDATE()
        FROM Stock s
        INNER JOIN @Detalle d ON d.IdRepuesto = s.IdRepuesto;

        IF EXISTS (SELECT 1 FROM Stock s INNER JOIN @Detalle d ON d.IdRepuesto = s.IdRepuesto
                   WHERE s.Cantidad < 0)
            RAISERROR('La operacion habria dejado stock negativo. No se registro la venta.', 16, 1);

        /* ---------- Registro de cada pago ----------
           Efectivo -> MovimientoCaja (arqueo).
           Lo demas -> MovimientoCuentaFinanciera, con la comision como
           egreso separado. Queda visible cuanto se llevan las tarjetas. */

        DECLARE @ComisionTotal DECIMAL(12,2) = 0;
        DECLARE @i INT = 1, @n INT = (SELECT COUNT(*) FROM @PagosNorm);
        DECLARE @pMedio INT, @pMonto DECIMAL(12,2), @pComPorc DECIMAL(5,2), @pCom DECIMAL(12,2),
                @pCuenta INT, @pEsCaja BIT, @pNombre NVARCHAR(40), @pIdPago INT;

        WHILE @i <= @n
        BEGIN
            SELECT @pMedio = pn.IdMedioPago, @pMonto = pn.Monto,
                   @pComPorc = m.ComisionPorc, @pCuenta = m.IdCuentaFinanciera,
                   @pEsCaja = c.EsCaja, @pNombre = m.Nombre
            FROM @PagosNorm pn
            INNER JOIN MedioPago m ON m.Id = pn.IdMedioPago
            INNER JOIN CuentaFinanciera c ON c.Id = m.IdCuentaFinanciera
            WHERE pn.Orden = @i;

            SET @pCom = CAST(@pMonto * @pComPorc / 100.0 AS DECIMAL(12,2));
            SET @ComisionTotal = @ComisionTotal + @pCom;

            INSERT INTO VentaPago (IdVenta, IdMedioPago, Monto, ComisionPorc, Comision, Neto)
            VALUES (@IdVenta, @pMedio, @pMonto, @pComPorc, @pCom, @pMonto - @pCom);
            SET @pIdPago = SCOPE_IDENTITY();

            IF @pEsCaja = 1
            BEGIN
                DECLARE @DescCaja NVARCHAR(250) =
                    CASE WHEN @FormaPago = 'CuentaCorriente'
                         THEN 'Entrega sobre venta #' + CAST(@IdVenta AS NVARCHAR(10))
                         ELSE 'Ingreso automatico por venta #' + CAST(@IdVenta AS NVARCHAR(10)) END;

                EXEC SP_MovimientoCaja_RegistrarInterno
                    @Tipo = 'Ingreso', @Concepto = 'Venta mostrador', @Monto = @pMonto,
                    @Descripcion = @DescCaja, @IdUsuario = @IdUsuario,
                    @IdVenta = @IdVenta, @IdPedido = NULL;
            END
            ELSE
            BEGIN
                INSERT INTO MovimientoCuentaFinanciera
                    (IdCuentaFinanciera, Tipo, Concepto, Monto, Descripcion, IdUsuario, IdVenta, IdVentaPago)
                VALUES
                    (@pCuenta, 'Ingreso', 'Venta ' + @pNombre, @pMonto,
                     'Venta #' + CAST(@IdVenta AS NVARCHAR(10)), @IdUsuario, @IdVenta, @pIdPago);

                IF @pCom > 0
                    INSERT INTO MovimientoCuentaFinanciera
                        (IdCuentaFinanciera, Tipo, Concepto, Monto, Descripcion, IdUsuario, IdVenta, IdVentaPago)
                    VALUES
                        (@pCuenta, 'Egreso', 'Comision ' + @pNombre, @pCom,
                         CAST(@pComPorc AS NVARCHAR(10)) + '% sobre venta #' + CAST(@IdVenta AS NVARCHAR(10)),
                         @IdUsuario, @IdVenta, @pIdPago);
            END

            SET @i = @i + 1;
        END

        /* ---------- Cuenta corriente ----------
           La venta genera el DEBE por el total. Si hubo entrega, se
           registra ademas el HABER. El saldo sube por la diferencia. */

        IF @FormaPago = 'CuentaCorriente'
        BEGIN
            INSERT INTO MovimientoCuentaCorriente
                (IdCliente, Tipo, Concepto, Monto, IdVenta, IdUsuario)
            VALUES
                (@IdCliente, 'Venta',
                 'Venta #' + CAST(@IdVenta AS VARCHAR(10)),
                 @Total, @IdVenta, @IdUsuario);

            IF @Entrega > 0
                INSERT INTO MovimientoCuentaCorriente
                    (IdCliente, Tipo, Concepto, Monto, IdVenta, IdUsuario)
                VALUES
                    (@IdCliente, 'Pago',
                     'Entrega sobre venta #' + CAST(@IdVenta AS VARCHAR(10)),
                     -@Entrega, @IdVenta, @IdUsuario);
        END

        /* ---------- Encargo entregado ---------- */
        IF @IdEncargo IS NOT NULL
            UPDATE Encargo SET Estado = 'ENTREGADO', IdVenta = @IdVenta, FechaEntrega = GETDATE()
            WHERE Id = @IdEncargo;

        COMMIT TRANSACTION;

        SELECT @IdVenta AS IdVenta, @Total AS Total, @Descuento AS Descuento,
               @Pagado AS Entrega, @Pagado AS Pagado,
               (@Total - @Pagado) AS SaldoGenerado, @ComisionTotal AS Comision;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   PRUEBAS (solo lectura)
   ----------------------------------------------------------------- */
SELECT TOP 10 c.Id, c.Apellido, c.Nombre, c.EsMecanico, f.Saldo, f.LimiteCredito, f.Disponible, f.DeudaDesde, f.DiasAtraso, f.DiasMaximo
FROM Cliente c
CROSS APPLY dbo.fn_CreditoCliente(c.Id) f
WHERE c.CuentaCorriente = 1
ORDER BY f.Saldo DESC;
GO
