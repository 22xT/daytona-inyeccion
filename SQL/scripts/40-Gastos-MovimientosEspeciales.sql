USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   40 — ETAPA 1 DE CAJA Y FINANZAS: GASTOS Y MOVIMIENTOS ESPECIALES

   Resuelve la observacion de la profesora: ya no se puede cargar un
   ingreso o egreso libre. Lo que antes era "Egreso: Servicios $X" pasa
   a ser un GASTO con tipo, comprobante y adjunto, que mueve dinero
   recien cuando se paga. Lo que era "Retiro de socio" pasa a ser un
   MOVIMIENTO ESPECIAL de una lista cerrada, con motivo obligatorio.

   Mientras no exista la tabla unica MovimientoFinanciero (etapa 3),
   el dinero se sigue registrando en MovimientoCaja (efectivo) y en
   MovimientoCuentaFinanciera (banco, Mercado Pago). A las dos se les
   agrega de donde vino cada movimiento: IdGasto o IdMovimientoEspecial.

   Requiere los scripts 37 a 39.
   ================================================================= */


/* -----------------------------------------------------------------
   1. Cuenta financiera: disponible o no
   La cartera de cheques (etapa 2) no es dinero disponible. Se marca
   desde ahora para que nadie pueda pagar un gasto "con la cartera".
   ----------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('CuentaFinanciera') AND name = 'EsDisponible')
    ALTER TABLE CuentaFinanciera ADD EsDisponible BIT NOT NULL CONSTRAINT DF_CuentaFin_Disp DEFAULT 1;
GO


/* -----------------------------------------------------------------
   2. Adjuntos: foto o PDF del comprobante
   Se guardan en la base: viajan con el backup y con Azure sin hacer
   nada extra. Limite de 2 MB por archivo, validado aca y en la API.
   ----------------------------------------------------------------- */
IF OBJECT_ID('Adjunto', 'U') IS NULL
BEGIN
    CREATE TABLE Adjunto (
        Id            INT IDENTITY(1,1) PRIMARY KEY,
        NombreArchivo NVARCHAR(200) NOT NULL,
        TipoMime      VARCHAR(60)   NOT NULL,
        Tamano        INT           NOT NULL,
        Contenido     VARBINARY(MAX) NOT NULL,
        Fecha         DATETIME      NOT NULL DEFAULT GETDATE(),
        IdUsuario     INT           NOT NULL,
        CONSTRAINT CK_Adjunto_Tamano CHECK (Tamano > 0 AND Tamano <= 2097152),
        CONSTRAINT CK_Adjunto_Mime CHECK (TipoMime IN ('image/jpeg', 'image/png', 'image/webp', 'application/pdf'))
    );
END
GO


/* -----------------------------------------------------------------
   3. Tipos de gasto
   Categoria como columna: son cuatro valores fijos que solo agrupan.
   RequiereComprobante = 0 solo para gastos menores del local; esos
   exigen igual un motivo y solo los cargan Administrador o Dueño.
   ----------------------------------------------------------------- */
IF OBJECT_ID('TipoGasto', 'U') IS NULL
BEGIN
    CREATE TABLE TipoGasto (
        Id                  INT IDENTITY(1,1) PRIMARY KEY,
        Nombre              NVARCHAR(60) NOT NULL UNIQUE,
        Categoria           VARCHAR(20)  NOT NULL,
        RequiereComprobante BIT NOT NULL DEFAULT 1,
        Activo              BIT NOT NULL DEFAULT 1,
        CONSTRAINT CK_TipoGasto_Cat CHECK (Categoria IN ('Servicios', 'Operacion', 'Mantenimiento', 'Administracion', 'Personal'))
    );

    INSERT INTO TipoGasto (Nombre, Categoria, RequiereComprobante) VALUES
        (N'Energía eléctrica',        'Servicios',      1),
        (N'Gas',                      'Servicios',      1),
        (N'Agua',                     'Servicios',      1),
        (N'Internet',                 'Servicios',      1),
        (N'Teléfono',                 'Servicios',      1),
        (N'Alquiler',                 'Administracion', 1),
        (N'Contador',                 'Administracion', 1),
        (N'Abogado',                  'Administracion', 1),
        (N'Impuestos y tasas',        'Administracion', 1),
        (N'Mantenimiento de cuenta',  'Administracion', 1),
        (N'Fletes',                   'Operacion',      1),
        (N'Moto o Uber',              'Operacion',      1),
        (N'Combustible',              'Operacion',      1),
        (N'Limpieza',                 'Operacion',      1),
        (N'Librería',                 'Operacion',      1),
        (N'Reparaciones',             'Mantenimiento',  1),
        (N'Informática',              'Mantenimiento',  1),
        (N'Herramientas',             'Mantenimiento',  1),
        (N'Sueldos',                  'Personal',       1),
        (N'Gastos menores del local', 'Operacion',      0);
END
GO


/* -----------------------------------------------------------------
   4. Gastos
   El gasto es la obligacion. Existe antes de pagarse (PENDIENTE) y
   mueve dinero recien al pagarlo (PAGADO). Un gasto se paga completo,
   en un solo pago: los pagos parciales quedan fuera de esta version.
   ----------------------------------------------------------------- */
IF OBJECT_ID('Gasto', 'U') IS NULL
BEGIN
    CREATE TABLE Gasto (
        Id                 INT IDENTITY(1,1) PRIMARY KEY,
        IdTipoGasto        INT           NOT NULL,
        IdProveedor        INT           NULL,        -- EPEC, el contador... si esta cargado
        Emisor             NVARCHAR(100) NULL,        -- si el emisor no es un proveedor del sistema
        Fecha              DATE          NOT NULL,    -- fecha del comprobante
        Descripcion        NVARCHAR(250) NOT NULL,
        Importe            DECIMAL(12,2) NOT NULL,
        TipoComprobante    VARCHAR(20)   NULL,        -- Factura A, Factura B, Factura C, Ticket, Recibo
        NumeroComprobante  VARCHAR(40)   NULL,
        IdAdjunto          INT           NULL,
        Estado             VARCHAR(10)   NOT NULL DEFAULT 'PENDIENTE',
        FechaAlta          DATETIME      NOT NULL DEFAULT GETDATE(),
        IdUsuario          INT           NOT NULL,
        -- Pago
        FechaPago          DATETIME      NULL,
        IdCuentaPago       INT           NULL,
        IdUsuarioPago      INT           NULL,
        -- Anulacion
        FechaAnulacion     DATETIME      NULL,
        IdUsuarioAnulacion INT           NULL,
        MotivoAnulacion    NVARCHAR(250) NULL,
        CONSTRAINT FK_Gasto_Tipo      FOREIGN KEY (IdTipoGasto)  REFERENCES TipoGasto(Id),
        CONSTRAINT FK_Gasto_Proveedor FOREIGN KEY (IdProveedor)  REFERENCES Proveedor(Id),
        CONSTRAINT FK_Gasto_Adjunto   FOREIGN KEY (IdAdjunto)    REFERENCES Adjunto(Id),
        CONSTRAINT FK_Gasto_Cuenta    FOREIGN KEY (IdCuentaPago) REFERENCES CuentaFinanciera(Id),
        CONSTRAINT CK_Gasto_Estado  CHECK (Estado IN ('PENDIENTE', 'PAGADO', 'ANULADO')),
        CONSTRAINT CK_Gasto_Importe CHECK (Importe > 0)
    );
    CREATE INDEX IX_Gasto_Fecha ON Gasto(Fecha);
    CREATE INDEX IX_Gasto_Estado ON Gasto(Estado);
END
GO


/* -----------------------------------------------------------------
   5. Movimientos especiales: lista cerrada de cuatro
   No existe "otro": esa opcion era la puerta que se queria cerrar.
     APORTE        el dueño pone dinero       solo destino
     RETIRO        el dueño saca dinero       solo origen
     TRANSFERENCIA de una cuenta a otra       origen y destino
     AJUSTE        correccion con motivo      origen (salida) o destino (entrada)
   ----------------------------------------------------------------- */
IF OBJECT_ID('MovimientoEspecial', 'U') IS NULL
BEGIN
    CREATE TABLE MovimientoEspecial (
        Id                 INT IDENTITY(1,1) PRIMARY KEY,
        Tipo               VARCHAR(15)   NOT NULL,
        IdCuentaOrigen     INT           NULL,
        IdCuentaDestino    INT           NULL,
        Importe            DECIMAL(12,2) NOT NULL,
        Motivo             NVARCHAR(250) NOT NULL,
        IdAdjunto          INT           NULL,
        Fecha              DATETIME      NOT NULL DEFAULT GETDATE(),
        IdUsuario          INT           NOT NULL,
        Estado             VARCHAR(12)   NOT NULL DEFAULT 'CONFIRMADO',
        FechaAnulacion     DATETIME      NULL,
        IdUsuarioAnulacion INT           NULL,
        MotivoAnulacion    NVARCHAR(250) NULL,
        CONSTRAINT FK_MovEsp_Origen  FOREIGN KEY (IdCuentaOrigen)  REFERENCES CuentaFinanciera(Id),
        CONSTRAINT FK_MovEsp_Destino FOREIGN KEY (IdCuentaDestino) REFERENCES CuentaFinanciera(Id),
        CONSTRAINT FK_MovEsp_Adjunto FOREIGN KEY (IdAdjunto)       REFERENCES Adjunto(Id),
        CONSTRAINT CK_MovEsp_Tipo    CHECK (Tipo IN ('APORTE', 'RETIRO', 'TRANSFERENCIA', 'AJUSTE')),
        CONSTRAINT CK_MovEsp_Estado  CHECK (Estado IN ('CONFIRMADO', 'ANULADO')),
        CONSTRAINT CK_MovEsp_Importe CHECK (Importe > 0),
        -- Cada tipo con exactamente las cuentas que le corresponden
        CONSTRAINT CK_MovEsp_Cuentas CHECK (
            (Tipo = 'APORTE'        AND IdCuentaOrigen IS NULL     AND IdCuentaDestino IS NOT NULL) OR
            (Tipo = 'RETIRO'        AND IdCuentaOrigen IS NOT NULL AND IdCuentaDestino IS NULL) OR
            (Tipo = 'TRANSFERENCIA' AND IdCuentaOrigen IS NOT NULL AND IdCuentaDestino IS NOT NULL
                                    AND IdCuentaOrigen <> IdCuentaDestino) OR
            (Tipo = 'AJUSTE'        AND ((IdCuentaOrigen IS NULL AND IdCuentaDestino IS NOT NULL) OR
                                         (IdCuentaOrigen IS NOT NULL AND IdCuentaDestino IS NULL)))
        )
    );
END
GO


/* -----------------------------------------------------------------
   6. Origen del dinero en las tablas de movimientos actuales
   Cada movimiento que genere un gasto o un movimiento especial queda
   apuntando a su documento. Es la regla 1: ningun dinero sin origen.
   ----------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('MovimientoCaja') AND name = 'IdGasto')
    ALTER TABLE MovimientoCaja ADD IdGasto INT NULL CONSTRAINT FK_MovCaja_Gasto REFERENCES Gasto(Id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('MovimientoCaja') AND name = 'IdMovimientoEspecial')
    ALTER TABLE MovimientoCaja ADD IdMovimientoEspecial INT NULL CONSTRAINT FK_MovCaja_MovEsp REFERENCES MovimientoEspecial(Id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('MovimientoCuentaFinanciera') AND name = 'IdGasto')
    ALTER TABLE MovimientoCuentaFinanciera ADD IdGasto INT NULL CONSTRAINT FK_MovCF_Gasto REFERENCES Gasto(Id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('MovimientoCuentaFinanciera') AND name = 'IdMovimientoEspecial')
    ALTER TABLE MovimientoCuentaFinanciera ADD IdMovimientoEspecial INT NULL CONSTRAINT FK_MovCF_MovEsp REFERENCES MovimientoEspecial(Id);
GO


/* -----------------------------------------------------------------
   7. SP_MovimientoCaja_RegistrarInterno con los dos origenes nuevos
   Parametros opcionales al final: las ventas y pedidos lo siguen
   llamando igual que antes.
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

    DECLARE @NuevoSaldo DECIMAL(12,2) =
        CASE WHEN @Tipo = 'Ingreso' THEN @SaldoActual + @Monto ELSE @SaldoActual - @Monto END;

    INSERT INTO MovimientoCaja
        (Tipo, Concepto, Monto, Descripcion, SaldoResultante,
         IdUsuario, IdVenta, IdPedido, IdGasto, IdMovimientoEspecial, Automatico)
    VALUES
        (@Tipo, @Concepto, @Monto, @Descripcion, @NuevoSaldo,
         @IdUsuario, @IdVenta, @IdPedido, @IdGasto, @IdMovimientoEspecial, 1);
END
GO


/* -----------------------------------------------------------------
   8. Registrar un movimiento en cualquier cuenta
   Un solo punto de entrada: si la cuenta es la caja fisica va a
   MovimientoCaja, si no a MovimientoCuentaFinanciera. Los gastos y
   los movimientos especiales no necesitan saber cual es cual.
   No abre transaccion: corre dentro de la del SP que lo llama.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Cuenta_RegistrarMovimiento', 'P') IS NOT NULL DROP PROCEDURE SP_Cuenta_RegistrarMovimiento;
GO
CREATE PROCEDURE SP_Cuenta_RegistrarMovimiento
    @IdCuentaFinanciera   INT,
    @Tipo                 VARCHAR(10),     -- 'Ingreso' | 'Egreso'
    @Concepto             NVARCHAR(60),
    @Monto                DECIMAL(12,2),
    @Descripcion          NVARCHAR(250),
    @IdUsuario            INT,
    @IdGasto              INT = NULL,
    @IdMovimientoEspecial INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @EsCaja BIT, @EsDisponible BIT, @Activo BIT;
    SELECT @EsCaja = EsCaja, @EsDisponible = EsDisponible, @Activo = Activo
    FROM CuentaFinanciera WHERE Id = @IdCuentaFinanciera;

    -- THROW corta siempre, este dentro de un TRY del llamador o no
    IF @EsCaja IS NULL
        THROW 50001, 'La cuenta financiera no existe.', 1;
    IF @Activo = 0
        THROW 50002, 'La cuenta financiera esta inactiva.', 1;
    IF @EsDisponible = 0
        THROW 50003, 'Esa cuenta no es dinero disponible: no se pueden registrar pagos ni movimientos sobre ella.', 1;

    IF @EsCaja = 1
        EXEC SP_MovimientoCaja_RegistrarInterno
             @Tipo = @Tipo, @Concepto = @Concepto, @Monto = @Monto, @Descripcion = @Descripcion,
             @IdUsuario = @IdUsuario, @IdGasto = @IdGasto, @IdMovimientoEspecial = @IdMovimientoEspecial;
    ELSE
        INSERT INTO MovimientoCuentaFinanciera
            (IdCuentaFinanciera, Tipo, Concepto, Monto, Descripcion, IdUsuario, IdGasto, IdMovimientoEspecial, Automatico)
        VALUES
            (@IdCuentaFinanciera, @Tipo, @Concepto, @Monto, @Descripcion, @IdUsuario, @IdGasto, @IdMovimientoEspecial, 1);
END
GO

IF OBJECT_ID('SP_CuentaFinanciera_GetAll', 'P') IS NOT NULL DROP PROCEDURE SP_CuentaFinanciera_GetAll;
GO
CREATE PROCEDURE SP_CuentaFinanciera_GetAll
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Id, Codigo, Nombre, EsCaja, EsDisponible
    FROM CuentaFinanciera
    WHERE Activo = 1 AND EsDisponible = 1
    ORDER BY EsCaja DESC, Id;
END
GO


/* -----------------------------------------------------------------
   9. Adjuntos
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Adjunto_I', 'P') IS NOT NULL DROP PROCEDURE SP_Adjunto_I;
GO
CREATE PROCEDURE SP_Adjunto_I
    @NombreArchivo NVARCHAR(200),
    @TipoMime      VARCHAR(60),
    @Contenido     VARBINARY(MAX),
    @IdUsuario     INT
AS
BEGIN
    SET NOCOUNT ON;
    -- RAISERROR fuera de un TRY no corta la ejecucion: se envuelve para
    -- que cualquier validacion fallida detenga el SP.
    BEGIN TRY
        DECLARE @tam INT = DATALENGTH(@Contenido);
        IF @tam IS NULL OR @tam = 0
            RAISERROR('El archivo esta vacio.', 16, 1);
        IF @tam > 2097152
            RAISERROR('El archivo supera los 2 MB. Sacale una foto con menos resolucion o comprimi el PDF.', 16, 1);
        IF @TipoMime NOT IN ('image/jpeg', 'image/png', 'image/webp', 'application/pdf')
            RAISERROR('Solo se aceptan fotos (JPG, PNG, WEBP) o PDF.', 16, 1);

        INSERT INTO Adjunto (NombreArchivo, TipoMime, Tamano, Contenido, IdUsuario)
        VALUES (@NombreArchivo, @TipoMime, @tam, @Contenido, @IdUsuario);

        SELECT CAST(SCOPE_IDENTITY() AS INT) AS Id;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

IF OBJECT_ID('SP_Adjunto_Get', 'P') IS NOT NULL DROP PROCEDURE SP_Adjunto_Get;
GO
CREATE PROCEDURE SP_Adjunto_Get @Id INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Id, NombreArchivo, TipoMime, Tamano, Contenido FROM Adjunto WHERE Id = @Id;
END
GO


/* -----------------------------------------------------------------
   10. Gastos: alta, pago, anulacion, consulta
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_TipoGasto_GetAll', 'P') IS NOT NULL DROP PROCEDURE SP_TipoGasto_GetAll;
GO
CREATE PROCEDURE SP_TipoGasto_GetAll
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Id, Nombre, Categoria, RequiereComprobante
    FROM TipoGasto WHERE Activo = 1
    ORDER BY Categoria, Nombre;
END
GO

IF OBJECT_ID('SP_Gasto_Pagar', 'P') IS NOT NULL DROP PROCEDURE SP_Gasto_Pagar;
GO
CREATE PROCEDURE SP_Gasto_Pagar
    @IdGasto            INT,
    @IdCuentaFinanciera INT,
    @IdUsuario          INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    -- Puede llamarse suelto o desde SP_Gasto_I (registrar y pagar juntos).
    -- Solo abre transaccion si no hay una abierta: anidarlas esconde el
    -- mensaje de error real detras de uno de conteo de transacciones.
    DECLARE @propia BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    BEGIN TRY
        IF @propia = 1 BEGIN TRANSACTION;

        DECLARE @Estado VARCHAR(10), @Importe DECIMAL(12,2), @Desc NVARCHAR(250), @Tipo NVARCHAR(60);
        SELECT @Estado = g.Estado, @Importe = g.Importe, @Desc = g.Descripcion, @Tipo = t.Nombre
        FROM Gasto g WITH (UPDLOCK) INNER JOIN TipoGasto t ON t.Id = g.IdTipoGasto
        WHERE g.Id = @IdGasto;

        IF @Estado IS NULL      RAISERROR('El gasto no existe.', 16, 1);
        IF @Estado = 'PAGADO'   RAISERROR('Ese gasto ya esta pagado.', 16, 1);
        IF @Estado = 'ANULADO'  RAISERROR('No se puede pagar un gasto anulado.', 16, 1);

        DECLARE @DescMov NVARCHAR(250) = LEFT('Gasto #' + CAST(@IdGasto AS NVARCHAR(10)) + ' · ' + @Tipo + ' · ' + @Desc, 250);

        EXEC SP_Cuenta_RegistrarMovimiento
             @IdCuentaFinanciera = @IdCuentaFinanciera, @Tipo = 'Egreso', @Concepto = 'Pago de gasto',
             @Monto = @Importe, @Descripcion = @DescMov, @IdUsuario = @IdUsuario, @IdGasto = @IdGasto;

        UPDATE Gasto
        SET Estado = 'PAGADO', FechaPago = GETDATE(), IdCuentaPago = @IdCuentaFinanciera, IdUsuarioPago = @IdUsuario
        WHERE Id = @IdGasto;

        IF @propia = 1 COMMIT;
    END TRY
    BEGIN CATCH
        IF @propia = 1 AND @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

IF OBJECT_ID('SP_Gasto_I', 'P') IS NOT NULL DROP PROCEDURE SP_Gasto_I;
GO
CREATE PROCEDURE SP_Gasto_I
    @IdTipoGasto        INT,
    @IdProveedor        INT = NULL,
    @Emisor             NVARCHAR(100) = NULL,
    @Fecha              DATE,
    @Descripcion        NVARCHAR(250),
    @Importe            DECIMAL(12,2),
    @TipoComprobante    VARCHAR(20) = NULL,
    @NumeroComprobante  VARCHAR(40) = NULL,
    @IdAdjunto          INT = NULL,
    @IdUsuario          INT,
    -- Para registrar y pagar en el mismo acto, el caso mas comun
    @IdCuentaPago       INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @Requiere BIT, @Activo BIT;
        SELECT @Requiere = RequiereComprobante, @Activo = Activo FROM TipoGasto WHERE Id = @IdTipoGasto;

        IF @Requiere IS NULL OR @Activo = 0
            RAISERROR('El tipo de gasto no existe o esta inactivo.', 16, 1);
        IF @Importe IS NULL OR @Importe <= 0
            RAISERROR('El importe debe ser mayor a cero.', 16, 1);
        IF @Fecha > CAST(GETDATE() AS DATE)
            RAISERROR('La fecha del comprobante no puede ser futura.', 16, 1);

        IF @Requiere = 1
        BEGIN
            -- El centro de la observacion de la profesora: sin respaldo no hay gasto
            IF ISNULL(LTRIM(RTRIM(@TipoComprobante)), '') = '' OR ISNULL(LTRIM(RTRIM(@NumeroComprobante)), '') = ''
                RAISERROR('Este tipo de gasto exige el tipo y el numero del comprobante.', 16, 1);
            IF @IdAdjunto IS NULL
                RAISERROR('Este tipo de gasto exige adjuntar la foto o el PDF del comprobante.', 16, 1);
            IF @IdProveedor IS NULL AND ISNULL(LTRIM(RTRIM(@Emisor)), '') = ''
                RAISERROR('Indica quien emitio el comprobante: un proveedor o el nombre del emisor.', 16, 1);
        END

        IF LEN(LTRIM(RTRIM(ISNULL(@Descripcion, '')))) < 10
            RAISERROR('Describi el gasto con al menos 10 caracteres.', 16, 1);

        -- El mismo comprobante del mismo emisor no se carga dos veces
        IF @NumeroComprobante IS NOT NULL AND EXISTS (
            SELECT 1 FROM Gasto
            WHERE Estado <> 'ANULADO'
              AND NumeroComprobante = @NumeroComprobante
              AND ISNULL(TipoComprobante, '') = ISNULL(@TipoComprobante, '')
              AND ((@IdProveedor IS NOT NULL AND IdProveedor = @IdProveedor) OR
                   (@IdProveedor IS NULL AND ISNULL(Emisor, '') = ISNULL(@Emisor, ''))))
            RAISERROR('Ese comprobante ya esta cargado como gasto.', 16, 1);

        BEGIN TRANSACTION;

        INSERT INTO Gasto (IdTipoGasto, IdProveedor, Emisor, Fecha, Descripcion, Importe,
                           TipoComprobante, NumeroComprobante, IdAdjunto, IdUsuario)
        VALUES (@IdTipoGasto, @IdProveedor, NULLIF(LTRIM(RTRIM(@Emisor)), ''), @Fecha, LTRIM(RTRIM(@Descripcion)), @Importe,
                NULLIF(@TipoComprobante, ''), NULLIF(@NumeroComprobante, ''), @IdAdjunto, @IdUsuario);

        DECLARE @IdGasto INT = SCOPE_IDENTITY();

        IF @IdCuentaPago IS NOT NULL
            EXEC SP_Gasto_Pagar @IdGasto = @IdGasto, @IdCuentaFinanciera = @IdCuentaPago, @IdUsuario = @IdUsuario;

        COMMIT;

        SELECT @IdGasto AS IdGasto, (SELECT Estado FROM Gasto WHERE Id = @IdGasto) AS Estado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

-- Revierte el pago: el gasto vuelve a PENDIENTE. El movimiento original
-- se conserva y se registra su inverso.
IF OBJECT_ID('SP_Gasto_AnularPago', 'P') IS NOT NULL DROP PROCEDURE SP_Gasto_AnularPago;
GO
CREATE PROCEDURE SP_Gasto_AnularPago
    @IdGasto   INT,
    @Motivo    NVARCHAR(250),
    @IdUsuario INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 10
            RAISERROR('El motivo de la anulacion debe tener al menos 10 caracteres.', 16, 1);

        BEGIN TRANSACTION;

        DECLARE @Estado VARCHAR(10), @Importe DECIMAL(12,2), @Cuenta INT;
        SELECT @Estado = Estado, @Importe = Importe, @Cuenta = IdCuentaPago
        FROM Gasto WITH (UPDLOCK) WHERE Id = @IdGasto;

        IF @Estado IS NULL      RAISERROR('El gasto no existe.', 16, 1);
        IF @Estado <> 'PAGADO'  RAISERROR('Solo se puede anular el pago de un gasto pagado.', 16, 1);

        DECLARE @Desc NVARCHAR(250) = LEFT('Anulacion del pago del gasto #' + CAST(@IdGasto AS NVARCHAR(10)) + ': ' + @Motivo, 250);

        EXEC SP_Cuenta_RegistrarMovimiento
             @IdCuentaFinanciera = @Cuenta, @Tipo = 'Ingreso', @Concepto = 'Anulacion de pago de gasto',
             @Monto = @Importe, @Descripcion = @Desc, @IdUsuario = @IdUsuario, @IdGasto = @IdGasto;

        UPDATE Gasto SET Estado = 'PENDIENTE', FechaPago = NULL, IdCuentaPago = NULL, IdUsuarioPago = NULL
        WHERE Id = @IdGasto;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

-- Anula un gasto pendiente. Si esta pagado, primero se anula el pago.
IF OBJECT_ID('SP_Gasto_Anular', 'P') IS NOT NULL DROP PROCEDURE SP_Gasto_Anular;
GO
CREATE PROCEDURE SP_Gasto_Anular
    @IdGasto   INT,
    @Motivo    NVARCHAR(250),
    @IdUsuario INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 10
            RAISERROR('El motivo de la anulacion debe tener al menos 10 caracteres.', 16, 1);

        DECLARE @Estado VARCHAR(10) = (SELECT Estado FROM Gasto WHERE Id = @IdGasto);
        IF @Estado IS NULL      RAISERROR('El gasto no existe.', 16, 1);
        IF @Estado = 'PAGADO'   RAISERROR('El gasto esta pagado: primero anula el pago.', 16, 1);
        IF @Estado = 'ANULADO'  RAISERROR('El gasto ya esta anulado.', 16, 1);

        UPDATE Gasto
        SET Estado = 'ANULADO', FechaAnulacion = GETDATE(), IdUsuarioAnulacion = @IdUsuario, MotivoAnulacion = @Motivo
        WHERE Id = @IdGasto;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

IF OBJECT_ID('SP_Gasto_GetAll', 'P') IS NOT NULL DROP PROCEDURE SP_Gasto_GetAll;
GO
CREATE PROCEDURE SP_Gasto_GetAll
    @Desde  DATE = NULL,
    @Hasta  DATE = NULL,
    @Estado VARCHAR(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @Desde IS NULL SET @Desde = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1);
    IF @Hasta IS NULL SET @Hasta = CAST(GETDATE() AS DATE);

    SELECT
        g.Id, g.Fecha, g.Descripcion, g.Importe, g.Estado,
        g.IdTipoGasto, t.Nombre AS TipoGasto, t.Categoria,
        COALESCE(p.RazonSocial, g.Emisor, '—') AS Emisor,
        g.TipoComprobante, g.NumeroComprobante,
        g.IdAdjunto, CASE WHEN g.IdAdjunto IS NULL THEN 0 ELSE 1 END AS TieneAdjunto,
        g.FechaPago, c.Nombre AS CuentaPago,
        g.MotivoAnulacion,
        u.Nombre AS Usuario
    FROM Gasto g
    INNER JOIN TipoGasto t      ON t.Id = g.IdTipoGasto
    LEFT  JOIN Proveedor p      ON p.Id = g.IdProveedor
    LEFT  JOIN CuentaFinanciera c ON c.Id = g.IdCuentaPago
    LEFT  JOIN Usuario u        ON u.Id = g.IdUsuario
    WHERE (g.Fecha BETWEEN @Desde AND @Hasta OR g.Estado = 'PENDIENTE')   -- los pendientes siempre se ven
      AND (@Estado IS NULL OR g.Estado = @Estado)
    ORDER BY CASE g.Estado WHEN 'PENDIENTE' THEN 0 WHEN 'PAGADO' THEN 1 ELSE 2 END, g.Fecha DESC, g.Id DESC;
END
GO

-- Totales por categoria del periodo, para el resumen de la pantalla
IF OBJECT_ID('SP_Gasto_Resumen', 'P') IS NOT NULL DROP PROCEDURE SP_Gasto_Resumen;
GO
CREATE PROCEDURE SP_Gasto_Resumen
    @Desde DATE = NULL,
    @Hasta DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @Desde IS NULL SET @Desde = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1);
    IF @Hasta IS NULL SET @Hasta = CAST(GETDATE() AS DATE);

    SELECT t.Categoria,
           SUM(CASE WHEN g.Estado = 'PAGADO'    THEN g.Importe ELSE 0 END) AS Pagado,
           SUM(CASE WHEN g.Estado = 'PENDIENTE' THEN g.Importe ELSE 0 END) AS Pendiente,
           COUNT(*) AS Cantidad
    FROM Gasto g INNER JOIN TipoGasto t ON t.Id = g.IdTipoGasto
    WHERE g.Estado <> 'ANULADO' AND g.Fecha BETWEEN @Desde AND @Hasta
    GROUP BY t.Categoria
    ORDER BY SUM(g.Importe) DESC;
END
GO


/* -----------------------------------------------------------------
   11. Movimientos especiales
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_MovimientoEspecial_I', 'P') IS NOT NULL DROP PROCEDURE SP_MovimientoEspecial_I;
GO
CREATE PROCEDURE SP_MovimientoEspecial_I
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
        IF @Tipo NOT IN ('APORTE', 'RETIRO', 'TRANSFERENCIA', 'AJUSTE')
            RAISERROR('Tipo de movimiento no permitido. Solo aporte, retiro, transferencia o ajuste.', 16, 1);
        IF @Importe IS NULL OR @Importe <= 0
            RAISERROR('El importe debe ser mayor a cero.', 16, 1);
        IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 10
            RAISERROR('El motivo es obligatorio y debe tener al menos 10 caracteres.', 16, 1);

        BEGIN TRANSACTION;

        -- El CHECK de la tabla valida que cada tipo tenga sus cuentas
        INSERT INTO MovimientoEspecial (Tipo, IdCuentaOrigen, IdCuentaDestino, Importe, Motivo, IdAdjunto, IdUsuario)
        VALUES (@Tipo, @IdCuentaOrigen, @IdCuentaDestino, @Importe, LTRIM(RTRIM(@Motivo)), @IdAdjunto, @IdUsuario);

        DECLARE @Id INT = SCOPE_IDENTITY();
        DECLARE @Concepto NVARCHAR(60) =
            CASE @Tipo WHEN 'APORTE' THEN 'Aporte del propietario'
                       WHEN 'RETIRO' THEN 'Retiro del propietario'
                       WHEN 'TRANSFERENCIA' THEN 'Transferencia entre cuentas'
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

-- Anula registrando el inverso de cada movimiento que genero
IF OBJECT_ID('SP_MovimientoEspecial_Anular', 'P') IS NOT NULL DROP PROCEDURE SP_MovimientoEspecial_Anular;
GO
CREATE PROCEDURE SP_MovimientoEspecial_Anular
    @Id        INT,
    @Motivo    NVARCHAR(250),
    @IdUsuario INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 10
            RAISERROR('El motivo de la anulacion debe tener al menos 10 caracteres.', 16, 1);

        BEGIN TRANSACTION;

        DECLARE @Estado VARCHAR(12), @Importe DECIMAL(12,2), @Orig INT, @Dest INT;
        SELECT @Estado = Estado, @Importe = Importe, @Orig = IdCuentaOrigen, @Dest = IdCuentaDestino
        FROM MovimientoEspecial WITH (UPDLOCK) WHERE Id = @Id;

        IF @Estado IS NULL        RAISERROR('El movimiento no existe.', 16, 1);
        IF @Estado = 'ANULADO'    RAISERROR('El movimiento ya esta anulado.', 16, 1);

        DECLARE @Desc NVARCHAR(250) = LEFT('Anulacion del mov. especial #' + CAST(@Id AS NVARCHAR(10)) + ': ' + @Motivo, 250);

        -- Inverso: lo que salio vuelve a entrar y viceversa
        IF @Orig IS NOT NULL
            EXEC SP_Cuenta_RegistrarMovimiento
                 @IdCuentaFinanciera = @Orig, @Tipo = 'Ingreso', @Concepto = 'Anulacion de movimiento especial',
                 @Monto = @Importe, @Descripcion = @Desc, @IdUsuario = @IdUsuario, @IdMovimientoEspecial = @Id;
        IF @Dest IS NOT NULL
            EXEC SP_Cuenta_RegistrarMovimiento
                 @IdCuentaFinanciera = @Dest, @Tipo = 'Egreso', @Concepto = 'Anulacion de movimiento especial',
                 @Monto = @Importe, @Descripcion = @Desc, @IdUsuario = @IdUsuario, @IdMovimientoEspecial = @Id;

        UPDATE MovimientoEspecial
        SET Estado = 'ANULADO', FechaAnulacion = GETDATE(), IdUsuarioAnulacion = @IdUsuario, MotivoAnulacion = @Motivo
        WHERE Id = @Id;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

IF OBJECT_ID('SP_MovimientoEspecial_GetAll', 'P') IS NOT NULL DROP PROCEDURE SP_MovimientoEspecial_GetAll;
GO
CREATE PROCEDURE SP_MovimientoEspecial_GetAll
    @Desde DATE = NULL,
    @Hasta DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @Desde IS NULL SET @Desde = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1);
    IF @Hasta IS NULL SET @Hasta = CAST(GETDATE() AS DATE);

    SELECT m.Id, m.Tipo, m.Importe, m.Motivo, m.Fecha, m.Estado, m.MotivoAnulacion,
           co.Nombre AS CuentaOrigen, cd.Nombre AS CuentaDestino,
           m.IdAdjunto, u.Nombre AS Usuario
    FROM MovimientoEspecial m
    LEFT JOIN CuentaFinanciera co ON co.Id = m.IdCuentaOrigen
    LEFT JOIN CuentaFinanciera cd ON cd.Id = m.IdCuentaDestino
    LEFT JOIN Usuario u ON u.Id = m.IdUsuario
    WHERE CAST(m.Fecha AS DATE) BETWEEN @Desde AND @Hasta
    ORDER BY m.Id DESC;
END
GO


/* -----------------------------------------------------------------
   12. PRUEBAS (descomentar, ajustar Ids)
   ----------------------------------------------------------------- */
/*
-- Gasto sin comprobante de un tipo que lo exige: tiene que fallar
EXEC SP_Gasto_I @IdTipoGasto = 1, @Fecha = '2026-09-30', @Descripcion = 'Factura de luz septiembre',
                @Importe = 120000, @IdUsuario = 1;

-- Gasto menor sin comprobante: pasa, con motivo
DECLARE @tm INT = (SELECT Id FROM TipoGasto WHERE Nombre = 'Gastos menores del local');
DECLARE @caja INT = (SELECT Id FROM CuentaFinanciera WHERE Codigo = 'CAJA');
EXEC SP_Gasto_I @IdTipoGasto = @tm, @Fecha = '2026-09-30', @Descripcion = 'Cafe y azucar para el mostrador',
                @Importe = 4500, @IdUsuario = 1, @IdCuentaPago = @caja;

-- Retiro del dueño desde la caja
EXEC SP_MovimientoEspecial_I @Tipo = 'RETIRO', @IdCuentaOrigen = @caja, @Importe = 20000,
                             @Motivo = 'Retiro personal del propietario', @IdUsuario = 1;

-- Un tipo que no existe: el CHECK lo rechaza
EXEC SP_MovimientoEspecial_I @Tipo = 'OTRO', @IdCuentaDestino = @caja, @Importe = 5000,
                             @Motivo = 'Esto no deberia poder cargarse', @IdUsuario = 1;

SELECT * FROM Gasto ORDER BY Id DESC;
SELECT * FROM MovimientoEspecial ORDER BY Id DESC;
SELECT TOP 5 Tipo, Concepto, Monto, Descripcion, IdGasto, IdMovimientoEspecial FROM MovimientoCaja ORDER BY Id DESC;
*/

SELECT 'TipoGasto' AS Tabla, COUNT(*) AS Filas FROM TipoGasto
UNION ALL SELECT 'CuentaFinanciera', COUNT(*) FROM CuentaFinanciera;
GO
