/* =================================================================
   92 - COMPROBANTES (Administracion, fase 1)

   Cada venta, nota de credito y nota de debito pasa a tener su
   comprobante: Factura, NC o ND, letra A o B segun la condicion
   frente al IVA del cliente, con el receptor, los renglones y el IVA
   por alicuota CONGELADOS en el momento de emitirlo.

   En esta fase todavia no se habla con ARCA: los comprobantes nacen
   en estado BORRADOR, en el punto de venta 0 (interno). En la fase 2
   se piden los CAE y pasan a AUTORIZADO con su numero.

   Estados: BORRADOR -> PENDIENTE (de CAE) -> AUTORIZADO
                                           -> RECHAZADO (con motivo)
            ANULADO: solo un borrador (por ejemplo, la venta del dia
            que se anula). Un autorizado nunca cambia: se corrige con
            nota de credito o de debito.

   Tambien:
   - Cliente: razon social y validacion del CUIT.
   - AlicuotaIva: codigo de ARCA de cada alicuota.

   No cambia SP_Venta_I ni SP_NotaCreditoCliente_I: la API genera el
   comprobante despues de registrar la venta o la nota. Si eso falla,
   la venta queda igual y aparece en "Pendientes de comprobante".

   Se puede correr mas de una vez. Hora argentina (UTC-3) como en el
   script 90. Correr en local y en Azure.
   ================================================================= */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;   -- los indices filtrados lo necesitan
GO


/* -----------------------------------------------------------------
   1. Alicuotas: codigo de ARCA
      1 No gravado · 2 Exento · 3 0% · 4 10,5% · 5 21% · 6 27%
   ----------------------------------------------------------------- */
IF COL_LENGTH('AlicuotaIva', 'IdArca') IS NULL
    ALTER TABLE AlicuotaIva ADD IdArca INT NULL;
GO
UPDATE AlicuotaIva
SET IdArca = CASE
        WHEN Nombre = 'No gravado' THEN 1
        WHEN Nombre = 'Exento'     THEN 2
        WHEN Porcentaje = 0        THEN 3
        WHEN Porcentaje = 10.5     THEN 4
        WHEN Porcentaje = 21       THEN 5
        WHEN Porcentaje = 27       THEN 6
        WHEN Porcentaje = 5        THEN 8
        WHEN Porcentaje = 2.5      THEN 9
    END
WHERE IdArca IS NULL;
GO


/* -----------------------------------------------------------------
   2. Condicion frente al IVA del receptor: codigo ARCA y letra
      Es una tabla y no un CASE para que, si el contador indica otra
      cosa (por ejemplo, la letra para monotributistas), se cambie un
      dato y no el codigo.
   ----------------------------------------------------------------- */
IF OBJECT_ID('CondicionIvaReceptor', 'U') IS NULL
BEGIN
    CREATE TABLE CondicionIvaReceptor (
        Nombre    VARCHAR(30) NOT NULL PRIMARY KEY,   -- igual que Cliente.CondicionIva
        IdArca    INT         NOT NULL,
        Letra     CHAR(1)     NOT NULL,
        ExigeCuit BIT         NOT NULL,
        CONSTRAINT CK_CondIvaRec_Letra CHECK (Letra IN ('A', 'B'))
    );
    INSERT INTO CondicionIvaReceptor (Nombre, IdArca, Letra, ExigeCuit) VALUES
        ('Responsable Inscripto', 1, 'A', 1),
        ('Monotributo',           6, 'A', 1),   -- RG 5003: a confirmar con el contador
        ('Exento',                4, 'B', 1),
        ('Consumidor Final',      5, 'B', 0);
END
GO


/* -----------------------------------------------------------------
   3. Tipos de comprobante (Id = codigo de ARCA)
   ----------------------------------------------------------------- */
IF OBJECT_ID('TipoComprobante', 'U') IS NULL
BEGIN
    CREATE TABLE TipoComprobante (
        Id     INT          NOT NULL PRIMARY KEY,
        Nombre NVARCHAR(40) NOT NULL,
        Letra  CHAR(1)      NOT NULL,
        Clase  CHAR(2)      NOT NULL,   -- FC | NC | ND
        CONSTRAINT CK_TipoComp_Clase CHECK (Clase IN ('FC', 'NC', 'ND')),
        CONSTRAINT UQ_TipoComp_LetraClase UNIQUE (Letra, Clase)
    );
    INSERT INTO TipoComprobante (Id, Nombre, Letra, Clase) VALUES
        (1, N'Factura A',          'A', 'FC'),
        (2, N'Nota de débito A',   'A', 'ND'),
        (3, N'Nota de crédito A',  'A', 'NC'),
        (6, N'Factura B',          'B', 'FC'),
        (7, N'Nota de débito B',   'B', 'ND'),
        (8, N'Nota de crédito B',  'B', 'NC');
END
GO


/* -----------------------------------------------------------------
   4. Puntos de venta
      El 0 es interno: lo que se emite ahi no tiene validez fiscal.
      En la fase 2 se agrega el de ARCA y pasa a ser el predeterminado.
   ----------------------------------------------------------------- */
IF OBJECT_ID('PuntoVenta', 'U') IS NULL
BEGIN
    CREATE TABLE PuntoVenta (
        Id               INT IDENTITY(1,1) PRIMARY KEY,
        Numero           INT          NOT NULL,
        Descripcion      NVARCHAR(80) NOT NULL,
        Entorno          VARCHAR(13)  NOT NULL,   -- INTERNO | HOMOLOGACION | PRODUCCION
        Activo           BIT          NOT NULL DEFAULT 1,
        EsPredeterminado BIT          NOT NULL DEFAULT 0,
        CONSTRAINT UQ_PuntoVenta_Numero UNIQUE (Numero),
        CONSTRAINT CK_PuntoVenta_Numero CHECK (Numero BETWEEN 0 AND 99998),
        CONSTRAINT CK_PuntoVenta_Entorno CHECK (Entorno IN ('INTERNO', 'HOMOLOGACION', 'PRODUCCION'))
    );
    CREATE UNIQUE INDEX UX_PuntoVenta_Predeterminado ON PuntoVenta(EsPredeterminado) WHERE EsPredeterminado = 1;

    INSERT INTO PuntoVenta (Numero, Descripcion, Entorno, Activo, EsPredeterminado)
    VALUES (0, N'Interno, sin ARCA (fase 1)', 'INTERNO', 1, 1);
END
GO


/* -----------------------------------------------------------------
   5. Comprobante, renglones e IVA por alicuota
   ----------------------------------------------------------------- */
IF OBJECT_ID('Comprobante', 'U') IS NULL
BEGIN
    CREATE TABLE Comprobante (
        Id                    INT IDENTITY(1,1) PRIMARY KEY,
        IdPuntoVenta          INT           NOT NULL,
        IdTipoComprobante     INT           NOT NULL,
        Numero                INT           NULL,       -- lo asigna ARCA al autorizar
        Fecha                 DATE          NOT NULL,
        FechaCreacion         DATETIME      NOT NULL,
        Estado                VARCHAR(10)   NOT NULL DEFAULT 'BORRADOR',
        IdCliente             INT           NOT NULL,
        IdVenta               INT           NULL,
        IdNotaCliente         INT           NULL,
        IdComprobanteAsociado INT           NULL,       -- la factura que corrige una NC o ND
        -- Receptor, congelado: si despues cambia la ficha del cliente, el comprobante no cambia
        ReceptorDocTipo       INT           NOT NULL,   -- 80 CUIT · 96 DNI · 99 sin identificar
        ReceptorDocNumero     VARCHAR(11)   NOT NULL,
        ReceptorCondicionIva  INT           NOT NULL,   -- codigo ARCA
        ReceptorNombre        NVARCHAR(120) NOT NULL,
        ReceptorDomicilio     NVARCHAR(150) NULL,
        -- Importes
        ImporteNeto           DECIMAL(12,2) NOT NULL,   -- neto gravado
        ImporteNoGravado      DECIMAL(12,2) NOT NULL DEFAULT 0,
        ImporteExento         DECIMAL(12,2) NOT NULL DEFAULT 0,
        ImporteIva            DECIMAL(12,2) NOT NULL,
        ImporteTributos       DECIMAL(12,2) NOT NULL DEFAULT 0,
        ImporteTotal          DECIMAL(12,2) NOT NULL,
        -- ARCA (fase 2)
        Cae                   CHAR(14)      NULL,
        CaeVencimiento        DATE          NULL,
        FechaAutorizacion     DATETIME      NULL,
        MotivoRechazo         NVARCHAR(500) NULL,
        MotivoAnulacion       NVARCHAR(250) NULL,
        IdUsuario             INT           NOT NULL,
        CONSTRAINT FK_Comp_PuntoVenta FOREIGN KEY (IdPuntoVenta)          REFERENCES PuntoVenta(Id),
        CONSTRAINT FK_Comp_Tipo       FOREIGN KEY (IdTipoComprobante)     REFERENCES TipoComprobante(Id),
        CONSTRAINT FK_Comp_Cliente    FOREIGN KEY (IdCliente)             REFERENCES Cliente(Id),
        CONSTRAINT FK_Comp_Venta      FOREIGN KEY (IdVenta)               REFERENCES Venta(Id),
        CONSTRAINT FK_Comp_Nota       FOREIGN KEY (IdNotaCliente)         REFERENCES NotaCliente(Id),
        CONSTRAINT FK_Comp_Asociado   FOREIGN KEY (IdComprobanteAsociado) REFERENCES Comprobante(Id),
        CONSTRAINT CK_Comp_Estado     CHECK (Estado IN ('BORRADOR', 'PENDIENTE', 'AUTORIZADO', 'RECHAZADO', 'ANULADO')),
        CONSTRAINT CK_Comp_DocTipo    CHECK (ReceptorDocTipo IN (80, 86, 96, 99)),
        CONSTRAINT CK_Comp_Origen     CHECK (IdVenta IS NOT NULL OR IdNotaCliente IS NOT NULL),
        CONSTRAINT CK_Comp_Positivo   CHECK (ImporteTotal > 0 AND ImporteNeto >= 0 AND ImporteIva >= 0
                                             AND ImporteNoGravado >= 0 AND ImporteExento >= 0 AND ImporteTributos >= 0),
        CONSTRAINT CK_Comp_Total      CHECK (ImporteTotal = ImporteNeto + ImporteNoGravado + ImporteExento + ImporteIva + ImporteTributos),
        CONSTRAINT CK_Comp_Autorizado CHECK (Estado <> 'AUTORIZADO'
                                             OR (Cae IS NOT NULL AND Numero IS NOT NULL AND CaeVencimiento IS NOT NULL)),
        CONSTRAINT CK_Comp_Anulado    CHECK (Estado <> 'ANULADO' OR Cae IS NULL)
    );

    -- Un numero por punto de venta y tipo (cuando ya lo tiene)
    CREATE UNIQUE INDEX UX_Comp_Numero  ON Comprobante(IdPuntoVenta, IdTipoComprobante, Numero) WHERE Numero IS NOT NULL;
    -- Una sola factura vigente por venta y un solo comprobante vigente por nota
    CREATE UNIQUE INDEX UX_Comp_Factura ON Comprobante(IdVenta)       WHERE IdNotaCliente IS NULL AND Estado <> 'ANULADO';
    CREATE UNIQUE INDEX UX_Comp_Nota    ON Comprobante(IdNotaCliente) WHERE IdNotaCliente IS NOT NULL AND Estado <> 'ANULADO';
    CREATE INDEX IX_Comp_Fecha    ON Comprobante(Fecha);
    CREATE INDEX IX_Comp_Asociado ON Comprobante(IdComprobanteAsociado);
END
GO

IF OBJECT_ID('ComprobanteRenglon', 'U') IS NULL
BEGIN
    CREATE TABLE ComprobanteRenglon (
        Id            INT IDENTITY(1,1) PRIMARY KEY,
        IdComprobante INT           NOT NULL,
        Orden         INT           NOT NULL,
        IdRepuesto    INT           NULL,          -- NULL: renglon de ajuste (bonificacion, recargo)
        Codigo        NVARCHAR(40)  NULL,
        Descripcion   NVARCHAR(200) NOT NULL,
        Cantidad      DECIMAL(12,2) NOT NULL,
        IdAlicuotaIva INT           NOT NULL,
        IdArcaIva     INT           NOT NULL,
        PorcentajeIva DECIMAL(5,2)  NOT NULL,
        ImporteNeto   DECIMAL(12,2) NOT NULL,
        ImporteIva    DECIMAL(12,2) NOT NULL,
        ImporteTotal  DECIMAL(12,2) NOT NULL,      -- con IVA y con el descuento de la venta
        CONSTRAINT FK_CompRen_Comp     FOREIGN KEY (IdComprobante) REFERENCES Comprobante(Id),
        CONSTRAINT FK_CompRen_Repuesto FOREIGN KEY (IdRepuesto)    REFERENCES Repuesto(Id),
        CONSTRAINT FK_CompRen_Alicuota FOREIGN KEY (IdAlicuotaIva) REFERENCES AlicuotaIva(Id),
        CONSTRAINT CK_CompRen_Cantidad CHECK (Cantidad > 0),
        CONSTRAINT CK_CompRen_Total    CHECK (ImporteTotal = ImporteNeto + ImporteIva)
    );
    CREATE INDEX IX_CompRen_Comp ON ComprobanteRenglon(IdComprobante);
END
GO

IF OBJECT_ID('ComprobanteIva', 'U') IS NULL
BEGIN
    CREATE TABLE ComprobanteIva (
        IdComprobante INT           NOT NULL,
        IdArcaIva     INT           NOT NULL,      -- 3 a 9: alicuotas gravadas
        Porcentaje    DECIMAL(5,2)  NOT NULL,
        BaseImponible DECIMAL(12,2) NOT NULL,
        Importe       DECIMAL(12,2) NOT NULL,
        CONSTRAINT PK_ComprobanteIva PRIMARY KEY (IdComprobante, IdArcaIva),
        CONSTRAINT FK_CompIva_Comp FOREIGN KEY (IdComprobante) REFERENCES Comprobante(Id)
    );
END
GO


/* -----------------------------------------------------------------
   6. Desde cuando se emiten comprobantes
      Las ventas anteriores no se facturan hacia atras.
   ----------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM ParametroSistema WHERE Clave = 'ComprobantesDesde')
    INSERT INTO ParametroSistema (Clave, Valor, Descripcion)
    VALUES ('ComprobantesDesde', CONVERT(VARCHAR(10), CAST(DATEADD(HOUR, -3, GETUTCDATE()) AS DATE), 23),
            'Fecha desde la que cada venta y nota lleva comprobante (AAAA-MM-DD)');
GO


/* -----------------------------------------------------------------
   7. Cliente: razon social y CUIT valido
   ----------------------------------------------------------------- */
IF COL_LENGTH('Cliente', 'RazonSocial') IS NULL
    ALTER TABLE Cliente ADD RazonSocial NVARCHAR(120) NULL;
GO

-- CUIT: 11 digitos y digito verificador (modulo 11). Acepta guiones,
-- puntos y espacios; devuelve los 11 digitos o NULL si no es valido.
IF OBJECT_ID('fn_CuitNormalizado', 'FN') IS NOT NULL DROP FUNCTION fn_CuitNormalizado;
GO
CREATE FUNCTION fn_CuitNormalizado (@Cuit VARCHAR(20))
RETURNS CHAR(11)
AS
BEGIN
    DECLARE @c VARCHAR(20) = REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(ISNULL(@Cuit, ''))), '-', ''), '.', ''), ' ', '');
    IF LEN(@c) <> 11 OR @c LIKE '%[^0-9]%' RETURN NULL;

    DECLARE @pesos CHAR(10) = '5432765432', @i INT = 1, @suma INT = 0;
    WHILE @i <= 10
    BEGIN
        SET @suma += CAST(SUBSTRING(@c, @i, 1) AS INT) * CAST(SUBSTRING(@pesos, @i, 1) AS INT);
        SET @i += 1;
    END
    DECLARE @dv INT = 11 - (@suma % 11);
    IF @dv = 11 SET @dv = 0;
    IF @dv = 10 OR @dv <> CAST(RIGHT(@c, 1) AS INT) RETURN NULL;
    RETURN @c;
END
GO


/* -----------------------------------------------------------------
   8. Alta, edicion y lectura del cliente con sus datos fiscales
      (los del script 82 + condicion IVA, CUIT y razon social)
      En la edicion, @CondicionIva NULL = no tocar los datos fiscales:
      asi una pantalla vieja que no los manda no los borra.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Cliente_ValidarFiscal', 'P') IS NOT NULL DROP PROCEDURE SP_Cliente_ValidarFiscal;
GO
CREATE PROCEDURE SP_Cliente_ValidarFiscal
    @Dni          VARCHAR(8),
    @CondicionIva VARCHAR(30),
    @Cuit         VARCHAR(20),
    @CuitOk       CHAR(11) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @CuitOk = NULL;

    DECLARE @exige BIT = (SELECT ExigeCuit FROM CondicionIvaReceptor WHERE Nombre = @CondicionIva);
    IF @exige IS NULL
    BEGIN
        RAISERROR('La condición frente al IVA no es válida.', 16, 1);
        RETURN 1;
    END
    IF ISNULL(@Dni, '') IN ('00000000', '00000001') AND @CondicionIva <> 'Consumidor Final'
    BEGIN
        RAISERROR('El cliente genérico del mostrador es consumidor final.', 16, 1);
        RETURN 1;
    END
    IF LTRIM(RTRIM(ISNULL(@Cuit, ''))) <> ''
    BEGIN
        SET @CuitOk = dbo.fn_CuitNormalizado(@Cuit);
        IF @CuitOk IS NULL
        BEGIN
            RAISERROR('El CUIT no es válido: revisá los 11 números.', 16, 1);
            RETURN 1;
        END
    END
    IF @exige = 1 AND @CuitOk IS NULL
    BEGIN
        DECLARE @m NVARCHAR(200) = N'Para un cliente ' + @CondicionIva + N' el CUIT es obligatorio.';
        RAISERROR(@m, 16, 1);
        RETURN 1;
    END
    RETURN 0;
END
GO

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
    @CambiarCredito BIT = 0,
    @CondicionIva   VARCHAR(30) = NULL,
    @Cuit           VARCHAR(20) = NULL,
    @RazonSocial    NVARCHAR(120) = NULL
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

    SET @CondicionIva = ISNULL(NULLIF(LTRIM(RTRIM(@CondicionIva)), ''), 'Consumidor Final');
    DECLARE @CuitOk CHAR(11), @r INT;
    EXEC @r = SP_Cliente_ValidarFiscal @Dni, @CondicionIva, @Cuit, @CuitOk OUTPUT;
    IF @r <> 0 RETURN;

    -- Cuenta corriente solo para mecanicos. Los clientes genericos del
    -- mostrador nunca fian: mezclarian la deuda de todos.
    DECLARE @cc BIT = CASE WHEN @EsMecanico = 1 AND ISNULL(@Dni, '') NOT IN ('00000000', '00000001') THEN 1 ELSE 0 END;

    INSERT INTO Cliente (Dni, Nombre, Apellido, Telefono, Mail, Calle, Numero, EsMecanico, CuentaCorriente, LimiteCredito,
                         CondicionIva, Cuit, RazonSocial)
    VALUES (@Dni, @Nombre, @Apellido, @Telefono, @Mail, @Calle, @Numero, @EsMecanico, @cc,
            CASE WHEN @CambiarCredito = 1 AND @cc = 1 THEN @LimiteCredito END,
            @CondicionIva, @CuitOk, NULLIF(LTRIM(RTRIM(@RazonSocial)), N''));

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
    @CambiarCredito BIT = 0,
    @CondicionIva   VARCHAR(30) = NULL,
    @Cuit           VARCHAR(20) = NULL,
    @RazonSocial    NVARCHAR(120) = NULL
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

    IF @Dni IS NOT NULL AND LTRIM(RTRIM(@Dni)) = ''
        SET @Dni = NULL;

    DECLARE @tocaFiscal BIT = CASE WHEN NULLIF(LTRIM(RTRIM(@CondicionIva)), '') IS NULL THEN 0 ELSE 1 END;
    DECLARE @CuitOk CHAR(11), @r INT;
    IF @tocaFiscal = 1
    BEGIN
        EXEC @r = SP_Cliente_ValidarFiscal @Dni, @CondicionIva, @Cuit, @CuitOk OUTPUT;
        IF @r <> 0 RETURN;
    END

    DECLARE @cc BIT = CASE WHEN @EsMecanico = 1 AND ISNULL(@Dni, '') NOT IN ('00000000', '00000001') THEN 1 ELSE 0 END;

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
                               ELSE LimiteCredito END,
        CondicionIva = CASE WHEN @tocaFiscal = 1 THEN @CondicionIva ELSE CondicionIva END,
        Cuit         = CASE WHEN @tocaFiscal = 1 THEN @CuitOk ELSE Cuit END,
        RazonSocial  = CASE WHEN @tocaFiscal = 1 THEN NULLIF(LTRIM(RTRIM(@RazonSocial)), N'') ELSE RazonSocial END
    WHERE Id = @Id;
END
GO

ALTER PROCEDURE [dbo].[SP_Cliente_GetAll]
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Id, Dni, Nombre, Apellido, Telefono, Mail, Calle, Numero, Activo,
           EsMecanico, CuentaCorriente, LimiteCredito,
           CondicionIva, Cuit, RazonSocial
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
           EsMecanico, CuentaCorriente, LimiteCredito,
           CondicionIva, Cuit, RazonSocial
    FROM Cliente
    WHERE Id = @Id;
END
GO


/* -----------------------------------------------------------------
   9. Receptor: a quien va el comprobante y con que letra
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Comprobante_Receptor', 'P') IS NOT NULL DROP PROCEDURE SP_Comprobante_Receptor;
GO
CREATE PROCEDURE SP_Comprobante_Receptor
    @IdCliente       INT,
    @NombreOcasional NVARCHAR(80) = NULL,
    @Letra           CHAR(1)       OUTPUT,
    @DocTipo         INT           OUTPUT,
    @DocNumero       VARCHAR(11)   OUTPUT,
    @CondicionArca   INT           OUTPUT,
    @Nombre          NVARCHAR(120) OUTPUT,
    @Domicilio       NVARCHAR(150) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Dni VARCHAR(8), @Cond VARCHAR(30), @Cuit CHAR(11), @Generico BIT;

    SELECT @Dni = c.Dni,
           @Cond = c.CondicionIva,
           @Cuit = dbo.fn_CuitNormalizado(c.Cuit),
           @Generico = CASE WHEN c.Dni IN ('00000000', '00000001') THEN 1 ELSE 0 END,
           @Nombre = COALESCE(NULLIF(LTRIM(RTRIM(c.RazonSocial)), N''),
                              NULLIF(LTRIM(RTRIM(ISNULL(c.Apellido, N'') + N' ' + ISNULL(c.Nombre, N''))), N'')),
           @Domicilio = NULLIF(LTRIM(RTRIM(ISNULL(c.Calle, N'') + N' ' + ISNULL(c.Numero, N''))), N'')
    FROM Cliente c
    WHERE c.Id = @IdCliente;

    IF @Cond IS NULL
    BEGIN
        RAISERROR('El cliente no existe.', 16, 1);
        RETURN 1;
    END

    -- El cliente generico del mostrador: consumidor final sin identificar
    IF @Generico = 1
    BEGIN
        SELECT @Letra = 'B', @DocTipo = 99, @DocNumero = '0',
               @CondicionArca = (SELECT IdArca FROM CondicionIvaReceptor WHERE Nombre = 'Consumidor Final'),
               @Nombre = COALESCE(NULLIF(LTRIM(RTRIM(@NombreOcasional)), N''), N'Consumidor final'),
               @Domicilio = NULL;
        RETURN 0;
    END

    DECLARE @Exige BIT;
    SELECT @Letra = Letra, @CondicionArca = IdArca, @Exige = ExigeCuit
    FROM CondicionIvaReceptor WHERE Nombre = @Cond;

    IF @Letra IS NULL
    BEGIN
        RAISERROR('La condición frente al IVA del cliente no es válida.', 16, 1);
        RETURN 1;
    END
    IF @Exige = 1 AND @Cuit IS NULL
    BEGIN
        DECLARE @m NVARCHAR(300) = N'El cliente es ' + @Cond +
            N' y no tiene un CUIT válido cargado. Completalo en la ficha del cliente y generá el comprobante desde Administración > Comprobantes.';
        RAISERROR(@m, 16, 1);
        RETURN 1;
    END

    IF @Cuit IS NOT NULL
        SELECT @DocTipo = 80, @DocNumero = @Cuit;
    ELSE IF @Dni IS NOT NULL AND LEN(@Dni) BETWEEN 7 AND 8 AND @Dni NOT LIKE '%[^0-9]%'
        SELECT @DocTipo = 96, @DocNumero = @Dni;
    ELSE
        SELECT @DocTipo = 99, @DocNumero = '0';

    SET @Nombre = ISNULL(@Nombre, N'Consumidor final');
    RETURN 0;
END
GO


/* -----------------------------------------------------------------
   10. Alta interna de un comprobante
       Lee los renglones de #CompLineas (la crea quien llama) y arma
       cabecera, renglones e IVA por alicuota. El IVA se calcula por
       alicuota sobre el total de cada una, como lo valida ARCA, y los
       totales cierran al centavo con lo cobrado.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Comprobante_Crear', 'P') IS NOT NULL DROP PROCEDURE SP_Comprobante_Crear;
GO
CREATE PROCEDURE SP_Comprobante_Crear
    @IdTipoComprobante     INT,
    @Fecha                 DATE,
    @IdCliente             INT,
    @IdVenta               INT = NULL,
    @IdNotaCliente         INT = NULL,
    @IdComprobanteAsociado INT = NULL,
    @DocTipo               INT,
    @DocNumero             VARCHAR(11),
    @CondicionArca         INT,
    @Nombre                NVARCHAR(120),
    @Domicilio             NVARCHAR(150),
    @IdUsuario             INT,
    @IdComprobante         INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @IdPV INT = (SELECT TOP 1 Id FROM PuntoVenta WHERE Activo = 1 AND EsPredeterminado = 1);
    IF @IdPV IS NULL
    BEGIN
        RAISERROR('No hay un punto de venta predeterminado activo.', 16, 1);
        RETURN 1;
    END
    IF NOT EXISTS (SELECT 1 FROM #CompLineas)
    BEGIN
        RAISERROR('El comprobante no tiene renglones.', 16, 1);
        RETURN 1;
    END
    IF EXISTS (SELECT 1 FROM #CompLineas WHERE IdArca IS NULL)
    BEGIN
        RAISERROR('Hay un repuesto con una alícuota de IVA sin código de ARCA.', 16, 1);
        RETURN 1;
    END

    -- Por alicuota: base e IVA sobre el total de cada una
    DECLARE @G TABLE (IdArca INT PRIMARY KEY, Porc DECIMAL(5,2), Final DECIMAL(12,2), Base DECIMAL(12,2), Iva DECIMAL(12,2));
    INSERT INTO @G (IdArca, Porc, Final, Base, Iva)
    SELECT IdArca, MAX(Porc), SUM(Final), 0, 0 FROM #CompLineas GROUP BY IdArca;
    UPDATE @G SET Base = CASE WHEN IdArca IN (1, 2, 3) THEN Final ELSE CAST(ROUND(Final / (1 + Porc / 100.0), 2) AS DECIMAL(12,2)) END;
    UPDATE @G SET Iva = Final - Base;

    DECLARE @Neto DECIMAL(12,2) = ISNULL((SELECT SUM(Base) FROM @G WHERE IdArca NOT IN (1, 2)), 0),
            @NoGr DECIMAL(12,2) = ISNULL((SELECT SUM(Base) FROM @G WHERE IdArca = 1), 0),
            @Exen DECIMAL(12,2) = ISNULL((SELECT SUM(Base) FROM @G WHERE IdArca = 2), 0),
            @Iva  DECIMAL(12,2) = ISNULL((SELECT SUM(Iva)  FROM @G WHERE IdArca NOT IN (1, 2)), 0),
            @Tot  DECIMAL(12,2) = (SELECT SUM(Final) FROM @G);

    INSERT INTO Comprobante
        (IdPuntoVenta, IdTipoComprobante, Fecha, FechaCreacion, Estado, IdCliente, IdVenta, IdNotaCliente,
         IdComprobanteAsociado, ReceptorDocTipo, ReceptorDocNumero, ReceptorCondicionIva, ReceptorNombre,
         ReceptorDomicilio, ImporteNeto, ImporteNoGravado, ImporteExento, ImporteIva, ImporteTributos,
         ImporteTotal, IdUsuario)
    VALUES
        (@IdPV, @IdTipoComprobante, @Fecha, DATEADD(HOUR, -3, GETUTCDATE()), 'BORRADOR', @IdCliente, @IdVenta, @IdNotaCliente,
         @IdComprobanteAsociado, @DocTipo, @DocNumero, @CondicionArca, LEFT(@Nombre, 120),
         @Domicilio, @Neto, @NoGr, @Exen, @Iva, 0,
         @Tot, @IdUsuario);
    SET @IdComprobante = SCOPE_IDENTITY();

    -- Renglones: neto e IVA de cada uno, informativos
    INSERT INTO ComprobanteRenglon
        (IdComprobante, Orden, IdRepuesto, Codigo, Descripcion, Cantidad, IdAlicuotaIva, IdArcaIva,
         PorcentajeIva, ImporteNeto, ImporteIva, ImporteTotal)
    SELECT @IdComprobante, l.Orden, l.IdRepuesto, l.Codigo, LEFT(l.Descripcion, 200), l.Cantidad, l.IdAlicuota, l.IdArca,
           l.Porc, x.Neto, l.Final - x.Neto, l.Final
    FROM #CompLineas l
    CROSS APPLY (SELECT CASE WHEN l.IdArca IN (1, 2, 3) THEN l.Final
                             ELSE CAST(ROUND(l.Final / (1 + l.Porc / 100.0), 2) AS DECIMAL(12,2)) END AS Neto) x;

    INSERT INTO ComprobanteIva (IdComprobante, IdArcaIva, Porcentaje, BaseImponible, Importe)
    SELECT @IdComprobante, IdArca, Porc, Base, Iva FROM @G WHERE IdArca NOT IN (1, 2);

    RETURN 0;
END
GO


/* -----------------------------------------------------------------
   11. Factura de una venta
       Si ya la tiene, devuelve la misma (se puede llamar dos veces).
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Comprobante_DesdeVenta', 'P') IS NOT NULL DROP PROCEDURE SP_Comprobante_DesdeVenta;
GO
CREATE PROCEDURE SP_Comprobante_DesdeVenta
    @IdVenta   INT,
    @IdUsuario INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @IdCliente INT, @EstadoVenta INT, @Total DECIMAL(12,2), @FechaVenta DATETIME, @NombreOc NVARCHAR(80);
        SELECT @IdCliente = IdCliente, @EstadoVenta = IdEstadoVenta, @Total = Total,
               @FechaVenta = Fecha, @NombreOc = NombreOcasional
        FROM Venta WITH (UPDLOCK, HOLDLOCK) WHERE Id = @IdVenta;

        IF @IdCliente IS NULL RAISERROR('La venta no existe.', 16, 1);
        IF @EstadoVenta = 2   RAISERROR('La venta está anulada: no lleva comprobante.', 16, 1);

        DECLARE @Existente INT = (SELECT Id FROM Comprobante
                                  WHERE IdVenta = @IdVenta AND IdNotaCliente IS NULL AND Estado <> 'ANULADO');
        IF @Existente IS NOT NULL
        BEGIN
            COMMIT;
            SELECT c.Id AS IdComprobante, t.Nombre AS Tipo, t.Letra, c.Estado, c.ImporteTotal, CAST(0 AS BIT) AS Nuevo
            FROM Comprobante c INNER JOIN TipoComprobante t ON t.Id = c.IdTipoComprobante WHERE c.Id = @Existente;
            RETURN;
        END

        DECLARE @Letra CHAR(1), @DocTipo INT, @DocNro VARCHAR(11), @Cond INT, @Nombre NVARCHAR(120), @Dom NVARCHAR(150), @r INT;
        EXEC @r = SP_Comprobante_Receptor @IdCliente, @NombreOc, @Letra OUTPUT, @DocTipo OUTPUT, @DocNro OUTPUT,
                                          @Cond OUTPUT, @Nombre OUTPUT, @Dom OUTPUT;
        IF @r <> 0 RAISERROR('No se pudo determinar el receptor del comprobante.', 16, 1);

        -- Renglones con el descuento de la venta prorrateado
        DECLARE @Subtotal DECIMAL(12,2) = (SELECT SUM(Subtotal) FROM DetalleVenta WHERE IdVenta = @IdVenta);
        IF ISNULL(@Subtotal, 0) <= 0 RAISERROR('La venta no tiene renglones.', 16, 1);
        DECLARE @factor DECIMAL(18,10) = @Total / @Subtotal;
        DECLARE @Alic21 INT = (SELECT TOP 1 Id FROM AlicuotaIva WHERE IdArca = 5 ORDER BY Id);

        CREATE TABLE #CompLineas (
            Orden INT IDENTITY(1,1), IdRepuesto INT NULL, Codigo NVARCHAR(40) NULL, Descripcion NVARCHAR(200) NOT NULL,
            Cantidad DECIMAL(12,2) NOT NULL, Final DECIMAL(12,2) NOT NULL,
            IdAlicuota INT NOT NULL, IdArca INT NULL, Porc DECIMAL(5,2) NOT NULL);

        INSERT INTO #CompLineas (IdRepuesto, Codigo, Descripcion, Cantidad, Final, IdAlicuota, IdArca, Porc)
        SELECT dv.IdRepuesto, LEFT(r.Codigo, 40), r.Descripcion, dv.Cantidad,
               CAST(ROUND(dv.Subtotal * @factor, 2) AS DECIMAL(12,2)),
               a.Id, a.IdArca, a.Porcentaje
        FROM DetalleVenta dv
        INNER JOIN Repuesto r ON r.Id = dv.IdRepuesto
        INNER JOIN AlicuotaIva a ON a.Id = ISNULL(r.IdAlicuotaIva, @Alic21)
        WHERE dv.IdVenta = @IdVenta
        ORDER BY dv.Id;

        -- Los centavos del redondeo van al renglon mas grande
        DECLARE @dif DECIMAL(12,2) = @Total - (SELECT SUM(Final) FROM #CompLineas);
        IF @dif <> 0
            UPDATE #CompLineas SET Final = Final + @dif
            WHERE Orden = (SELECT TOP 1 Orden FROM #CompLineas ORDER BY Final DESC, Orden);

        DECLARE @IdTipo INT = (SELECT Id FROM TipoComprobante WHERE Letra = @Letra AND Clase = 'FC');
        DECLARE @IdComp INT;
        DECLARE @Hoy DATE = CAST(@FechaVenta AS DATE);
        EXEC @r = SP_Comprobante_Crear @IdTipo, @Hoy, @IdCliente, @IdVenta, NULL, NULL,
                                       @DocTipo, @DocNro, @Cond, @Nombre, @Dom, @IdUsuario, @IdComp OUTPUT;
        IF @r <> 0 RAISERROR('No se pudo crear el comprobante.', 16, 1);

        COMMIT;
        SELECT c.Id AS IdComprobante, t.Nombre AS Tipo, t.Letra, c.Estado, c.ImporteTotal, CAST(1 AS BIT) AS Nuevo
        FROM Comprobante c INNER JOIN TipoComprobante t ON t.Id = c.IdTipoComprobante WHERE c.Id = @IdComp;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   12. Nota de credito o de debito de una NotaCliente
       - Asociada a la factura de la venta, con su misma letra y receptor.
       - Devolucion de mercaderia: un renglon por repuesto devuelto, con
         la alicuota con que se facturo.
       - Bonificacion o recargo por importe: se reparte entre las
         alicuotas de la factura en la misma proporcion; sin factura,
         al 21%.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Comprobante_DesdeNota', 'P') IS NOT NULL DROP PROCEDURE SP_Comprobante_DesdeNota;
GO
CREATE PROCEDURE SP_Comprobante_DesdeNota
    @IdNota    INT,
    @IdUsuario INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @Clase CHAR(2), @IdCliente INT, @IdVenta INT, @Importe DECIMAL(12,2), @Motivo NVARCHAR(250), @FechaNota DATETIME;
        SELECT @Clase = Tipo, @IdCliente = IdCliente, @IdVenta = IdVenta, @Importe = Importe,
               @Motivo = Motivo, @FechaNota = Fecha
        FROM NotaCliente WITH (UPDLOCK, HOLDLOCK) WHERE Id = @IdNota;
        IF @Clase IS NULL RAISERROR('La nota no existe.', 16, 1);

        DECLARE @Existente INT = (SELECT Id FROM Comprobante WHERE IdNotaCliente = @IdNota AND Estado <> 'ANULADO');
        IF @Existente IS NOT NULL
        BEGIN
            COMMIT;
            SELECT c.Id AS IdComprobante, t.Nombre AS Tipo, t.Letra, c.Estado, c.ImporteTotal, CAST(0 AS BIT) AS Nuevo
            FROM Comprobante c INNER JOIN TipoComprobante t ON t.Id = c.IdTipoComprobante WHERE c.Id = @Existente;
            RETURN;
        END

        -- La factura que corrige
        DECLARE @IdAsoc INT, @Letra CHAR(1), @DocTipo INT, @DocNro VARCHAR(11), @Cond INT,
                @Nombre NVARCHAR(120), @Dom NVARCHAR(150), @TotalAsoc DECIMAL(12,2), @r INT;
        IF @IdVenta IS NOT NULL
            SELECT @IdAsoc = c.Id, @Letra = t.Letra, @DocTipo = c.ReceptorDocTipo, @DocNro = c.ReceptorDocNumero,
                   @Cond = c.ReceptorCondicionIva, @Nombre = c.ReceptorNombre, @Dom = c.ReceptorDomicilio,
                   @TotalAsoc = c.ImporteTotal
            FROM Comprobante c INNER JOIN TipoComprobante t ON t.Id = c.IdTipoComprobante
            WHERE c.IdVenta = @IdVenta AND c.IdNotaCliente IS NULL AND c.Estado <> 'ANULADO';

        -- Venta posterior al arranque de los comprobantes y sin factura: primero la factura
        DECLARE @Desde DATE = TRY_CAST((SELECT Valor FROM ParametroSistema WHERE Clave = 'ComprobantesDesde') AS DATE);
        IF @IdVenta IS NOT NULL AND @IdAsoc IS NULL
           AND (SELECT CAST(Fecha AS DATE) FROM Venta WHERE Id = @IdVenta) >= ISNULL(@Desde, '19000101')
        BEGIN
            DECLARE @mv NVARCHAR(200) = N'La venta #' + CAST(@IdVenta AS NVARCHAR(10)) +
                                        N' todavía no tiene factura: generala primero desde Comprobantes.';
            RAISERROR(@mv, 16, 1);
        END

        IF @IdAsoc IS NULL
        BEGIN
            DECLARE @NombreOc NVARCHAR(80) = (SELECT NombreOcasional FROM Venta WHERE Id = @IdVenta);
            EXEC @r = SP_Comprobante_Receptor @IdCliente, @NombreOc, @Letra OUTPUT, @DocTipo OUTPUT, @DocNro OUTPUT,
                                              @Cond OUTPUT, @Nombre OUTPUT, @Dom OUTPUT;
            IF @r <> 0 RAISERROR('No se pudo determinar el receptor del comprobante.', 16, 1);
        END

        CREATE TABLE #CompLineas (
            Orden INT IDENTITY(1,1), IdRepuesto INT NULL, Codigo NVARCHAR(40) NULL, Descripcion NVARCHAR(200) NOT NULL,
            Cantidad DECIMAL(12,2) NOT NULL, Final DECIMAL(12,2) NOT NULL,
            IdAlicuota INT NOT NULL, IdArca INT NULL, Porc DECIMAL(5,2) NOT NULL);

        DECLARE @Alic21 INT = (SELECT TOP 1 Id FROM AlicuotaIva WHERE IdArca = 5 ORDER BY Id);

        IF EXISTS (SELECT 1 FROM NotaClienteDetalle WHERE IdNota = @IdNota)
        BEGIN
            -- Devolucion: la alicuota con que se facturo cada repuesto
            INSERT INTO #CompLineas (IdRepuesto, Codigo, Descripcion, Cantidad, Final, IdAlicuota, IdArca, Porc)
            SELECT d.IdRepuesto, LEFT(r.Codigo, 40), LEFT(N'Devolución: ' + r.Descripcion, 200), d.Cantidad, d.Subtotal,
                   a.Id, a.IdArca, a.Porcentaje
            FROM NotaClienteDetalle d
            INNER JOIN Repuesto r ON r.Id = d.IdRepuesto
            OUTER APPLY (SELECT TOP 1 cr.IdAlicuotaIva FROM ComprobanteRenglon cr
                         WHERE cr.IdComprobante = @IdAsoc AND cr.IdRepuesto = d.IdRepuesto) f
            INNER JOIN AlicuotaIva a ON a.Id = COALESCE(f.IdAlicuotaIva, r.IdAlicuotaIva, @Alic21)
            WHERE d.IdNota = @IdNota
            ORDER BY d.Id;
        END
        ELSE IF @IdAsoc IS NOT NULL
        BEGIN
            -- Por importe: proporcional a las alicuotas de la factura
            INSERT INTO #CompLineas (IdRepuesto, Codigo, Descripcion, Cantidad, Final, IdAlicuota, IdArca, Porc)
            SELECT NULL, NULL,
                   LEFT(CASE WHEN @Clase = 'NC' THEN N'Bonificación: ' ELSE N'Recargo: ' END + @Motivo, 200),
                   1, CAST(ROUND(@Importe * g.Final / @TotalAsoc, 2) AS DECIMAL(12,2)),
                   a.Id, g.IdArcaIva, g.Porc
            FROM (SELECT IdArcaIva, MAX(PorcentajeIva) AS Porc, SUM(ImporteTotal) AS Final
                  FROM ComprobanteRenglon WHERE IdComprobante = @IdAsoc GROUP BY IdArcaIva) g
            CROSS APPLY (SELECT TOP 1 Id FROM AlicuotaIva WHERE IdArca = g.IdArcaIva ORDER BY Id) a
            ORDER BY g.Final DESC;
            DELETE FROM #CompLineas WHERE Final <= 0;
        END
        ELSE
            INSERT INTO #CompLineas (IdRepuesto, Codigo, Descripcion, Cantidad, Final, IdAlicuota, IdArca, Porc)
            SELECT NULL, NULL,
                   LEFT(CASE WHEN @Clase = 'NC' THEN N'Bonificación: ' ELSE N'Recargo: ' END + @Motivo, 200),
                   1, @Importe, a.Id, a.IdArca, a.Porcentaje
            FROM AlicuotaIva a WHERE a.Id = @Alic21;

        -- Cierra al centavo con el importe de la nota
        DECLARE @dif DECIMAL(12,2) = @Importe - ISNULL((SELECT SUM(Final) FROM #CompLineas), 0);
        IF @dif <> 0
            UPDATE #CompLineas SET Final = Final + @dif
            WHERE Orden = (SELECT TOP 1 Orden FROM #CompLineas ORDER BY Final DESC, Orden);

        DECLARE @IdTipo INT = (SELECT Id FROM TipoComprobante WHERE Letra = @Letra AND Clase = @Clase);
        DECLARE @IdComp INT, @Fecha DATE = CAST(@FechaNota AS DATE);
        EXEC @r = SP_Comprobante_Crear @IdTipo, @Fecha, @IdCliente, @IdVenta, @IdNota, @IdAsoc,
                                       @DocTipo, @DocNro, @Cond, @Nombre, @Dom, @IdUsuario, @IdComp OUTPUT;
        IF @r <> 0 RAISERROR('No se pudo crear el comprobante.', 16, 1);

        COMMIT;
        SELECT c.Id AS IdComprobante, t.Nombre AS Tipo, t.Letra, c.Estado, c.ImporteTotal, CAST(1 AS BIT) AS Nuevo
        FROM Comprobante c INNER JOIN TipoComprobante t ON t.Id = c.IdTipoComprobante WHERE c.Id = @IdComp;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   13. Anular la venta del dia: su factura en borrador se anula.
       Si ya fue a ARCA (pendiente o autorizada), la venta no se anula:
       se corrige con nota de credito.
       @SoloValidar = 1 se llama ANTES de anular la venta.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Comprobante_AnularDeVenta', 'P') IS NOT NULL DROP PROCEDURE SP_Comprobante_AnularDeVenta;
GO
CREATE PROCEDURE SP_Comprobante_AnularDeVenta
    @IdVenta     INT,
    @IdUsuario   INT,
    @SoloValidar BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM Comprobante WHERE IdVenta = @IdVenta AND Estado IN ('PENDIENTE', 'AUTORIZADO'))
    BEGIN
        RAISERROR('La venta ya tiene comprobante enviado a ARCA: no se puede anular, se corrige con una nota de crédito.', 16, 1);
        RETURN;
    END
    IF @SoloValidar = 1 RETURN;

    UPDATE Comprobante
    SET Estado = 'ANULADO', MotivoAnulacion = N'Venta anulada por el usuario #' + CAST(@IdUsuario AS NVARCHAR(10))
    WHERE IdVenta = @IdVenta AND Estado IN ('BORRADOR', 'RECHAZADO');
END
GO


/* -----------------------------------------------------------------
   14. Consultas
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Comprobante_GetAll', 'P') IS NOT NULL DROP PROCEDURE SP_Comprobante_GetAll;
GO
CREATE PROCEDURE SP_Comprobante_GetAll
    @Desde  DATE = NULL,
    @Hasta  DATE = NULL,
    @Estado VARCHAR(10) = NULL,
    @Clase  CHAR(2) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @hoy DATE = CAST(DATEADD(HOUR, -3, GETUTCDATE()) AS DATE);
    SET @Hasta = ISNULL(@Hasta, @hoy);
    SET @Desde = ISNULL(@Desde, DATEADD(DAY, -30, @Hasta));

    SELECT c.Id, c.Fecha, c.Estado, t.Id AS CodigoTipo, t.Nombre AS Tipo, t.Letra, t.Clase,
           pv.Numero AS PuntoVenta, c.Numero,
           c.ReceptorNombre, c.ReceptorDocTipo, c.ReceptorDocNumero,
           c.ImporteNeto, c.ImporteNoGravado, c.ImporteExento, c.ImporteIva, c.ImporteTotal,
           c.IdVenta, c.IdNotaCliente, c.IdComprobanteAsociado, c.Cae, c.MotivoRechazo
    FROM Comprobante c
    INNER JOIN TipoComprobante t ON t.Id = c.IdTipoComprobante
    INNER JOIN PuntoVenta pv ON pv.Id = c.IdPuntoVenta
    WHERE c.Fecha BETWEEN @Desde AND @Hasta
      AND (@Estado IS NULL OR c.Estado = @Estado)
      AND (@Clase IS NULL OR t.Clase = @Clase)
    ORDER BY c.Fecha DESC, c.Id DESC;
END
GO

IF OBJECT_ID('SP_Comprobante_GetId', 'P') IS NOT NULL DROP PROCEDURE SP_Comprobante_GetId;
GO
CREATE PROCEDURE SP_Comprobante_GetId @Id INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT c.*, t.Nombre AS Tipo, t.Letra, t.Clase, pv.Numero AS PuntoVenta, pv.Entorno,
           ci.Nombre AS ReceptorCondicionNombre,
           ta.Nombre AS TipoAsociado, pva.Numero AS PuntoVentaAsociado, a.Numero AS NumeroAsociado, a.Fecha AS FechaAsociado,
           u.Nombre AS Usuario
    FROM Comprobante c
    INNER JOIN TipoComprobante t ON t.Id = c.IdTipoComprobante
    INNER JOIN PuntoVenta pv ON pv.Id = c.IdPuntoVenta
    LEFT JOIN CondicionIvaReceptor ci ON ci.IdArca = c.ReceptorCondicionIva
    LEFT JOIN Comprobante a ON a.Id = c.IdComprobanteAsociado
    LEFT JOIN TipoComprobante ta ON ta.Id = a.IdTipoComprobante
    LEFT JOIN PuntoVenta pva ON pva.Id = a.IdPuntoVenta
    LEFT JOIN Usuario u ON u.Id = c.IdUsuario
    WHERE c.Id = @Id;

    SELECT Orden, IdRepuesto, Codigo, Descripcion, Cantidad, PorcentajeIva, ImporteNeto, ImporteIva, ImporteTotal
    FROM ComprobanteRenglon WHERE IdComprobante = @Id ORDER BY Orden;

    SELECT IdArcaIva, Porcentaje, BaseImponible, Importe
    FROM ComprobanteIva WHERE IdComprobante = @Id ORDER BY Porcentaje DESC;

    -- Las notas que la corrigen
    SELECT n.Id, t.Nombre AS Tipo, n.Fecha, n.Estado, n.ImporteTotal
    FROM Comprobante n INNER JOIN TipoComprobante t ON t.Id = n.IdTipoComprobante
    WHERE n.IdComprobanteAsociado = @Id ORDER BY n.Id;
END
GO

-- Ventas y notas desde el arranque que no tienen comprobante vigente
IF OBJECT_ID('SP_Comprobante_Pendientes', 'P') IS NOT NULL DROP PROCEDURE SP_Comprobante_Pendientes;
GO
CREATE PROCEDURE SP_Comprobante_Pendientes
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Desde DATE = ISNULL(TRY_CAST((SELECT Valor FROM ParametroSistema WHERE Clave = 'ComprobantesDesde') AS DATE),
                                 CAST(DATEADD(HOUR, -3, GETUTCDATE()) AS DATE));

    SELECT 'VENTA' AS Origen, v.Id, v.Fecha, v.Total AS Importe,
           COALESCE(NULLIF(LTRIM(RTRIM(cl.RazonSocial)), N''), cl.Apellido + N' ' + cl.Nombre) AS Cliente,
           cl.CondicionIva, v.IdCliente
    FROM Venta v
    INNER JOIN Cliente cl ON cl.Id = v.IdCliente
    WHERE CAST(v.Fecha AS DATE) >= @Desde AND v.IdEstadoVenta <> 2
      AND NOT EXISTS (SELECT 1 FROM Comprobante c
                      WHERE c.IdVenta = v.Id AND c.IdNotaCliente IS NULL AND c.Estado <> 'ANULADO')
    UNION ALL
    SELECT CASE n.Tipo WHEN 'NC' THEN 'NC' ELSE 'ND' END, n.Id, n.Fecha, n.Importe,
           COALESCE(NULLIF(LTRIM(RTRIM(cl.RazonSocial)), N''), cl.Apellido + N' ' + cl.Nombre),
           cl.CondicionIva, n.IdCliente
    FROM NotaCliente n
    INNER JOIN Cliente cl ON cl.Id = n.IdCliente
    WHERE CAST(n.Fecha AS DATE) >= @Desde
      AND NOT EXISTS (SELECT 1 FROM Comprobante c WHERE c.IdNotaCliente = n.Id AND c.Estado <> 'ANULADO')
    ORDER BY 3;
END
GO


/* -----------------------------------------------------------------
   CONTROL
   ----------------------------------------------------------------- */
SELECT 'TipoComprobante' AS Tabla, COUNT(*) AS Filas FROM TipoComprobante
UNION ALL SELECT 'PuntoVenta', COUNT(*) FROM PuntoVenta
UNION ALL SELECT 'CondicionIvaReceptor', COUNT(*) FROM CondicionIvaReceptor
UNION ALL SELECT 'Alicuotas sin codigo ARCA', COUNT(*) FROM AlicuotaIva WHERE IdArca IS NULL
UNION ALL SELECT 'Clientes A sin CUIT valido', COUNT(*) FROM Cliente c
          INNER JOIN CondicionIvaReceptor ci ON ci.Nombre = c.CondicionIva
          WHERE ci.ExigeCuit = 1 AND dbo.fn_CuitNormalizado(c.Cuit) IS NULL;
SELECT Clave, Valor FROM ParametroSistema WHERE Clave = 'ComprobantesDesde';
GO
