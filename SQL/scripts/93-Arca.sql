/* =================================================================
   93 - ARCA (Administracion, fase 2): pedir el CAE

   - ArcaToken: el ticket de acceso de WSAA dura 12 horas y ARCA no
     da otro mientras el anterior siga vigente. Se guarda en la base
     para no perderlo si la aplicacion se reinicia.
   - ArcaSolicitud: cada pedido a ARCA con su respuesta, para auditar
     y reintentar. Nunca guarda el token ni la firma.
   - Punto de venta de pruebas (homologacion) y datos del emisor.
   - Reservar numero, autorizar y rechazar un comprobante.

   Circuito: BORRADOR o RECHAZADO -> PENDIENTE (con numero reservado)
             -> AUTORIZADO (CAE) | RECHAZADO (sin numero, con motivo)
   Si ARCA no responde, queda PENDIENTE: al reintentar primero se
   consulta si ese numero ya quedo autorizado.

   Se puede correr mas de una vez. Correr en local y en Azure.
   ================================================================= */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO


/* -----------------------------------------------------------------
   1. Ticket de acceso y registro de pedidos
   ----------------------------------------------------------------- */
IF OBJECT_ID('ArcaToken', 'U') IS NULL
BEGIN
    CREATE TABLE ArcaToken (
        Servicio  VARCHAR(20)   NOT NULL,
        Entorno   VARCHAR(13)   NOT NULL,
        Token     NVARCHAR(MAX) NOT NULL,
        Sign      NVARCHAR(MAX) NOT NULL,
        ExpiraUtc DATETIME      NOT NULL,
        CONSTRAINT PK_ArcaToken PRIMARY KEY (Servicio, Entorno)
    );
END
GO

IF OBJECT_ID('ArcaSolicitud', 'U') IS NULL
BEGIN
    CREATE TABLE ArcaSolicitud (
        Id            INT IDENTITY(1,1) PRIMARY KEY,
        Fecha         DATETIME       NOT NULL,
        Entorno       VARCHAR(13)    NOT NULL,
        Servicio      VARCHAR(20)    NOT NULL,      -- WSAA | WSFE
        Metodo        VARCHAR(40)    NOT NULL,
        IdComprobante INT            NULL,
        Resultado     VARCHAR(10)    NOT NULL,      -- OK | A | R | P | ERROR
        Mensaje       NVARCHAR(2000) NULL,
        Enviado       NVARCHAR(MAX)  NULL,
        Recibido      NVARCHAR(MAX)  NULL,
        DuracionMs    INT            NULL,
        IdUsuario     INT            NULL,
        CONSTRAINT FK_ArcaSol_Comp FOREIGN KEY (IdComprobante) REFERENCES Comprobante(Id)
    );
    CREATE INDEX IX_ArcaSol_Comp  ON ArcaSolicitud(IdComprobante);
    CREATE INDEX IX_ArcaSol_Fecha ON ArcaSolicitud(Fecha);
END
GO


/* -----------------------------------------------------------------
   2. Punto de venta de pruebas y datos del emisor
      El punto de venta de produccion se da de alta en ARCA cuando el
      contador de el OK; aca se agrega despues con su numero real.
   ----------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM PuntoVenta WHERE Entorno = 'HOMOLOGACION')
   AND NOT EXISTS (SELECT 1 FROM PuntoVenta WHERE Numero = 1)
    INSERT INTO PuntoVenta (Numero, Descripcion, Entorno, Activo, EsPredeterminado)
    VALUES (1, N'Pruebas ARCA (homologación, sin validez fiscal)', 'HOMOLOGACION', 1, 0);
GO

-- Con que punto de venta se piden los CAE (Id de PuntoVenta)
IF NOT EXISTS (SELECT 1 FROM ParametroSistema WHERE Clave = 'ArcaPuntoVenta')
    INSERT INTO ParametroSistema (Clave, Valor, Descripcion)
    SELECT 'ArcaPuntoVenta', CAST(Id AS VARCHAR(10)), 'Id del punto de venta con el que se piden los CAE'
    FROM PuntoVenta WHERE Entorno = 'HOMOLOGACION' AND Numero = 1;
GO

-- Datos del emisor: van impresos en el comprobante y en el QR.
-- Se completan con los datos reales (CUIT obligatorio para ARCA).
IF NOT EXISTS (SELECT 1 FROM ParametroSistema WHERE Clave = 'EmisorCuit')
    INSERT INTO ParametroSistema (Clave, Valor, Descripcion) VALUES
        ('EmisorCuit',              '', 'CUIT del emisor, 11 numeros sin guiones'),
        ('EmisorRazonSocial',       'Daytona Repuestos Automotor', 'Nombre o razon social del emisor'),
        ('EmisorDomicilio',         '', 'Domicilio comercial'),
        ('EmisorIngresosBrutos',    '', 'Numero de Ingresos Brutos'),
        ('EmisorInicioActividades', '', 'Fecha de inicio de actividades (DD/MM/AAAA)'),
        ('EmisorCondicionIva',      'Responsable Inscripto', 'Condicion del emisor frente al IVA');
GO


/* -----------------------------------------------------------------
   3. Ticket de acceso
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_ArcaToken_Get', 'P') IS NOT NULL DROP PROCEDURE SP_ArcaToken_Get;
GO
CREATE PROCEDURE SP_ArcaToken_Get @Servicio VARCHAR(20), @Entorno VARCHAR(13)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Token, Sign, ExpiraUtc FROM ArcaToken WHERE Servicio = @Servicio AND Entorno = @Entorno;
END
GO

IF OBJECT_ID('SP_ArcaToken_Set', 'P') IS NOT NULL DROP PROCEDURE SP_ArcaToken_Set;
GO
CREATE PROCEDURE SP_ArcaToken_Set
    @Servicio VARCHAR(20), @Entorno VARCHAR(13), @Token NVARCHAR(MAX), @Sign NVARCHAR(MAX), @ExpiraUtc DATETIME
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE ArcaToken SET Token = @Token, Sign = @Sign, ExpiraUtc = @ExpiraUtc
    WHERE Servicio = @Servicio AND Entorno = @Entorno;
    IF @@ROWCOUNT = 0
        INSERT INTO ArcaToken (Servicio, Entorno, Token, Sign, ExpiraUtc)
        VALUES (@Servicio, @Entorno, @Token, @Sign, @ExpiraUtc);
END
GO


/* -----------------------------------------------------------------
   4. Registro de cada pedido
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_ArcaSolicitud_I', 'P') IS NOT NULL DROP PROCEDURE SP_ArcaSolicitud_I;
GO
CREATE PROCEDURE SP_ArcaSolicitud_I
    @Entorno VARCHAR(13), @Servicio VARCHAR(20), @Metodo VARCHAR(40), @IdComprobante INT = NULL,
    @Resultado VARCHAR(10), @Mensaje NVARCHAR(2000) = NULL, @Enviado NVARCHAR(MAX) = NULL,
    @Recibido NVARCHAR(MAX) = NULL, @DuracionMs INT = NULL, @IdUsuario INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO ArcaSolicitud (Fecha, Entorno, Servicio, Metodo, IdComprobante, Resultado, Mensaje,
                               Enviado, Recibido, DuracionMs, IdUsuario)
    VALUES (DATEADD(HOUR, -3, GETUTCDATE()), @Entorno, @Servicio, @Metodo, @IdComprobante, @Resultado,
            LEFT(@Mensaje, 2000), @Enviado, @Recibido, @DuracionMs, @IdUsuario);
END
GO


/* -----------------------------------------------------------------
   5. Configuracion para ARCA: punto de venta y emisor
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Arca_Configuracion', 'P') IS NOT NULL DROP PROCEDURE SP_Arca_Configuracion;
GO
CREATE PROCEDURE SP_Arca_Configuracion
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IdPV INT = TRY_CAST((SELECT Valor FROM ParametroSistema WHERE Clave = 'ArcaPuntoVenta') AS INT);

    SELECT pv.Id AS IdPuntoVenta, pv.Numero AS PuntoVenta, pv.Entorno, pv.Activo,
           (SELECT Valor FROM ParametroSistema WHERE Clave = 'EmisorCuit') AS EmisorCuit,
           (SELECT Valor FROM ParametroSistema WHERE Clave = 'EmisorRazonSocial') AS EmisorRazonSocial
    FROM (SELECT 1 AS x) d
    LEFT JOIN PuntoVenta pv ON pv.Id = @IdPV;
END
GO


/* -----------------------------------------------------------------
   6. Lo que se le manda a ARCA de un comprobante
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Arca_Comprobante', 'P') IS NOT NULL DROP PROCEDURE SP_Arca_Comprobante;
GO
CREATE PROCEDURE SP_Arca_Comprobante @Id INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT c.Id, c.Estado, c.IdTipoComprobante, t.Clase, t.Letra, c.IdPuntoVenta, pv.Numero AS PuntoVenta,
           pv.Entorno, c.Numero, c.Fecha, c.ReceptorDocTipo, c.ReceptorDocNumero, c.ReceptorCondicionIva,
           c.ImporteNeto, c.ImporteNoGravado, c.ImporteExento, c.ImporteIva, c.ImporteTributos, c.ImporteTotal,
           c.IdComprobanteAsociado,
           a.Estado AS EstadoAsociado, a.IdTipoComprobante AS TipoAsociado, pva.Numero AS PuntoVentaAsociado,
           a.Numero AS NumeroAsociado, a.Fecha AS FechaAsociado
    FROM Comprobante c
    INNER JOIN TipoComprobante t ON t.Id = c.IdTipoComprobante
    INNER JOIN PuntoVenta pv ON pv.Id = c.IdPuntoVenta
    LEFT JOIN Comprobante a ON a.Id = c.IdComprobanteAsociado
    LEFT JOIN PuntoVenta pva ON pva.Id = a.IdPuntoVenta
    WHERE c.Id = @Id;

    SELECT IdArcaIva, BaseImponible, Importe FROM ComprobanteIva WHERE IdComprobante = @Id ORDER BY IdArcaIva;
END
GO


/* -----------------------------------------------------------------
   7. Reservar el numero antes de mandarlo
      Pasa a PENDIENTE con el punto de venta, el numero y la fecha con
      que se envia. Si ARCA no contesta queda asi, y el reintento
      consulta ese numero antes de pedir otro.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Arca_Reservar', 'P') IS NOT NULL DROP PROCEDURE SP_Arca_Reservar;
GO
CREATE PROCEDURE SP_Arca_Reservar
    @Id INT, @IdPuntoVenta INT, @Numero INT, @Fecha DATE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @Estado VARCHAR(10), @Tipo INT;
        SELECT @Estado = Estado, @Tipo = IdTipoComprobante FROM Comprobante WITH (UPDLOCK, HOLDLOCK) WHERE Id = @Id;
        IF @Estado IS NULL RAISERROR('El comprobante no existe.', 16, 1);
        IF @Estado NOT IN ('BORRADOR', 'RECHAZADO')
        BEGIN
            DECLARE @m1 NVARCHAR(200) = N'El comprobante está ' + LOWER(@Estado) + N': no se puede volver a enviar.';
            RAISERROR(@m1, 16, 1);
        END
        -- ARCA numera en orden: si otro del mismo tipo quedo esperando respuesta, va primero ese
        IF EXISTS (SELECT 1 FROM Comprobante WITH (UPDLOCK, HOLDLOCK)
                   WHERE IdPuntoVenta = @IdPuntoVenta AND IdTipoComprobante = @Tipo AND Estado = 'PENDIENTE' AND Id <> @Id)
            RAISERROR('Hay otro comprobante del mismo tipo esperando respuesta de ARCA: reintentá ese primero.', 16, 1);

        UPDATE Comprobante
        SET Estado = 'PENDIENTE', IdPuntoVenta = @IdPuntoVenta, Numero = @Numero, Fecha = @Fecha, MotivoRechazo = NULL
        WHERE Id = @Id;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

IF OBJECT_ID('SP_Arca_Autorizar', 'P') IS NOT NULL DROP PROCEDURE SP_Arca_Autorizar;
GO
CREATE PROCEDURE SP_Arca_Autorizar
    @Id INT, @Cae CHAR(14), @CaeVencimiento DATE, @Observaciones NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Comprobante
    SET Estado = 'AUTORIZADO', Cae = @Cae, CaeVencimiento = @CaeVencimiento,
        FechaAutorizacion = DATEADD(HOUR, -3, GETUTCDATE()), MotivoRechazo = NULLIF(@Observaciones, N'')
    WHERE Id = @Id AND Estado = 'PENDIENTE' AND Numero IS NOT NULL;
    IF @@ROWCOUNT = 0
        RAISERROR('El comprobante no estaba esperando el CAE.', 16, 1);
END
GO

-- Rechazado: ARCA no uso el numero, se libera
IF OBJECT_ID('SP_Arca_Rechazar', 'P') IS NOT NULL DROP PROCEDURE SP_Arca_Rechazar;
GO
CREATE PROCEDURE SP_Arca_Rechazar @Id INT, @Motivo NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Comprobante
    SET Estado = 'RECHAZADO', Numero = NULL, MotivoRechazo = LEFT(@Motivo, 500)
    WHERE Id = @Id AND Estado = 'PENDIENTE';
END
GO


/* -----------------------------------------------------------------
   8. Rehacer un borrador o un rechazado
      El receptor queda congelado al emitir: si ARCA lo rechazo por un
      dato del cliente (por ejemplo, el CUIT), se corrige la ficha y se
      rehace. El anterior queda anulado y se genera uno nuevo.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Comprobante_Rehacer', 'P') IS NOT NULL DROP PROCEDURE SP_Comprobante_Rehacer;
GO
CREATE PROCEDURE SP_Comprobante_Rehacer @Id INT, @IdUsuario INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @Estado VARCHAR(10), @IdVenta INT, @IdNota INT;
        SELECT @Estado = Estado, @IdVenta = IdVenta, @IdNota = IdNotaCliente
        FROM Comprobante WITH (UPDLOCK, HOLDLOCK) WHERE Id = @Id;
        IF @Estado IS NULL RAISERROR('El comprobante no existe.', 16, 1);
        IF @Estado NOT IN ('BORRADOR', 'RECHAZADO')
            RAISERROR('Solo se rehace un borrador o un rechazado.', 16, 1);
        IF EXISTS (SELECT 1 FROM Comprobante WHERE IdComprobanteAsociado = @Id AND Estado <> 'ANULADO')
            RAISERROR('Tiene notas de crédito o débito asociadas: no se puede rehacer.', 16, 1);

        UPDATE Comprobante
        SET Estado = 'ANULADO', Numero = NULL,
            MotivoAnulacion = N'Rehecho por el usuario #' + CAST(@IdUsuario AS NVARCHAR(10))
        WHERE Id = @Id;

        IF @IdNota IS NOT NULL
            EXEC SP_Comprobante_DesdeNota @IdNota, @IdUsuario;
        ELSE
            EXEC SP_Comprobante_DesdeVenta @IdVenta, @IdUsuario;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO


IF OBJECT_ID('SP_Emisor_Get', 'P') IS NOT NULL DROP PROCEDURE SP_Emisor_Get;
GO
CREATE PROCEDURE SP_Emisor_Get
AS
BEGIN
    SET NOCOUNT ON;
    SELECT MAX(CASE WHEN Clave = 'EmisorCuit'              THEN Valor END) AS Cuit,
           MAX(CASE WHEN Clave = 'EmisorRazonSocial'       THEN Valor END) AS RazonSocial,
           MAX(CASE WHEN Clave = 'EmisorDomicilio'         THEN Valor END) AS Domicilio,
           MAX(CASE WHEN Clave = 'EmisorIngresosBrutos'    THEN Valor END) AS IngresosBrutos,
           MAX(CASE WHEN Clave = 'EmisorInicioActividades' THEN Valor END) AS InicioActividades,
           MAX(CASE WHEN Clave = 'EmisorCondicionIva'      THEN Valor END) AS CondicionIva
    FROM ParametroSistema WHERE Clave LIKE 'Emisor%';
END
GO


/* -----------------------------------------------------------------
   9. Historial de pedidos de un comprobante (sin token ni firma)
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_ArcaSolicitud_GetByComprobante', 'P') IS NOT NULL DROP PROCEDURE SP_ArcaSolicitud_GetByComprobante;
GO
CREATE PROCEDURE SP_ArcaSolicitud_GetByComprobante @IdComprobante INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Id, Fecha, Entorno, Metodo, Resultado, Mensaje, DuracionMs
    FROM ArcaSolicitud WHERE IdComprobante = @IdComprobante ORDER BY Id DESC;
END
GO


/* -----------------------------------------------------------------
   CONTROL
   ----------------------------------------------------------------- */
SELECT pv.Numero, pv.Descripcion, pv.Entorno, pv.EsPredeterminado,
       CASE WHEN CAST(pv.Id AS VARCHAR(10)) = (SELECT Valor FROM ParametroSistema WHERE Clave = 'ArcaPuntoVenta')
            THEN 'SI' ELSE '' END AS ParaCae
FROM PuntoVenta pv ORDER BY pv.Numero;
SELECT Clave, Valor FROM ParametroSistema WHERE Clave LIKE 'Emisor%' OR Clave = 'ArcaPuntoVenta' ORDER BY Clave;
GO
