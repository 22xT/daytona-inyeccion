USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   86 — MATCHER (ENTREGABLE 1): ETIQUETADO DEL BENCHMARK

   Para medir si los embeddings encuentran el mismo repuesto entre
   proveedores, primero hace falta un conjunto de pares confirmados
   por una persona. Este script arma ese conjunto.

   Relaciones (decision del 27/10):
     IGUAL        misma pieza: misma referencia de la misma marca
     EQUIVALENTE  sirve para lo mismo en el mismo vehiculo, otra marca
                  (pastilla Litton / Remsa / Bosch para el mismo auto)
     DISTINTO     no es lo mismo (sirve para medir errores)

   Dos fuentes de pares:
     CODIGO  los 50 pares Autocor-Expoyer con el mismo codigo de
             fabrica. 4 de cada 12 resultaron piezas distintas: se
             revisan uno por uno, nada entra solo.
     MANUAL  se elige un articulo "ancla" de Autocor y se marcan sus
             iguales y equivalentes entre los resultados del buscador.

   El ancla sale de Autocor porque es el unico proveedor que trae el
   tipo de pieza en el rubro ("PASTILLAS DE FRENO "LITTON""). Los
   candidatos salen de todas las listas, tambien de Autocor mismo.

   Criterio GO / NO GO (se fija ANTES de ver resultados):
     EQUIVALENTE: en el 85% de las anclas de prueba, al menos uno de
                  sus equivalentes aparece entre los 5 primeros.
     IGUAL:       el 95% de los pares iguales aparece entre los 5
                  primeros.

   No toca datos del negocio: solo crea tablas nuevas.
   ================================================================= */


/* -----------------------------------------------------------------
   1. Tablas
   ----------------------------------------------------------------- */
IF OBJECT_ID('MatcherAncla', 'U') IS NULL
CREATE TABLE MatcherAncla (
    IdProveedorRepuesto INT          NOT NULL PRIMARY KEY,
    Tipo                VARCHAR(120) NOT NULL,
    Estado              VARCHAR(12)  NOT NULL,
    Conjunto            VARCHAR(5)   NULL,      -- DEV / TEST, se asigna al separar
    Nota                NVARCHAR(200) NULL,
    IdUsuario           INT          NULL,
    Fecha               DATETIME     NOT NULL CONSTRAINT DF_MatcherAncla_Fecha DEFAULT GETDATE(),
    CONSTRAINT FK_MatcherAncla_PR FOREIGN KEY (IdProveedorRepuesto) REFERENCES ProveedorRepuesto(Id),
    CONSTRAINT CK_MatcherAncla_Estado CHECK (Estado IN ('ETIQUETADA', 'SALTEADA')),
    CONSTRAINT CK_MatcherAncla_Conjunto CHECK (Conjunto IS NULL OR Conjunto IN ('DEV', 'TEST'))
);
GO

IF OBJECT_ID('MatcherPar', 'U') IS NULL
CREATE TABLE MatcherPar (
    Id          INT IDENTITY(1,1) PRIMARY KEY,
    IdAncla     INT          NOT NULL,
    IdCandidato INT          NOT NULL,
    Relacion    VARCHAR(12)  NOT NULL,
    Origen      VARCHAR(8)   NOT NULL,
    IdUsuario   INT          NULL,
    Fecha       DATETIME     NOT NULL CONSTRAINT DF_MatcherPar_Fecha DEFAULT GETDATE(),
    CONSTRAINT FK_MatcherPar_Ancla FOREIGN KEY (IdAncla) REFERENCES ProveedorRepuesto(Id),
    CONSTRAINT FK_MatcherPar_Cand  FOREIGN KEY (IdCandidato) REFERENCES ProveedorRepuesto(Id),
    CONSTRAINT UQ_MatcherPar UNIQUE (IdAncla, IdCandidato),
    CONSTRAINT CK_MatcherPar_Distintos CHECK (IdAncla <> IdCandidato),
    CONSTRAINT CK_MatcherPar_Relacion CHECK (Relacion IN ('PENDIENTE', 'IGUAL', 'EQUIVALENTE', 'DISTINTO')),
    CONSTRAINT CK_MatcherPar_Origen CHECK (Origen IN ('CODIGO', 'MANUAL'))
);
GO

-- Para el experimento (dias 6 a 8): que texto se vectorizo y que dio cada corrida
IF OBJECT_ID('MatcherEmbedding', 'U') IS NULL
CREATE TABLE MatcherEmbedding (
    IdProveedorRepuesto INT           NOT NULL PRIMARY KEY,
    Modelo              VARCHAR(60)   NOT NULL,
    Texto               NVARCHAR(600) NOT NULL,
    Hash                CHAR(64)      NOT NULL,
    Fecha               DATETIME      NOT NULL CONSTRAINT DF_MatcherEmb_Fecha DEFAULT GETDATE(),
    CONSTRAINT FK_MatcherEmb_PR FOREIGN KEY (IdProveedorRepuesto) REFERENCES ProveedorRepuesto(Id)
);
GO
IF OBJECT_ID('MatcherCorrida', 'U') IS NULL
CREATE TABLE MatcherCorrida (
    Id          INT IDENTITY(1,1) PRIMARY KEY,
    Fecha       DATETIME      NOT NULL CONSTRAINT DF_MatcherCorrida_Fecha DEFAULT GETDATE(),
    Modelo      VARCHAR(60)   NOT NULL,
    Dimensiones INT           NULL,
    Conjunto    VARCHAR(5)    NOT NULL,
    Descripcion NVARCHAR(200) NULL
);
GO
IF OBJECT_ID('MatcherResultado', 'U') IS NULL
CREATE TABLE MatcherResultado (
    IdCorrida  INT NOT NULL,
    IdPar      INT NOT NULL,
    Posicion   INT NULL,              -- 1 a 10; NULL = no aparecio entre los 10
    Similitud  DECIMAL(6,4) NULL,
    CONSTRAINT PK_MatcherResultado PRIMARY KEY (IdCorrida, IdPar),
    CONSTRAINT FK_MatcherRes_Corrida FOREIGN KEY (IdCorrida) REFERENCES MatcherCorrida(Id),
    CONSTRAINT FK_MatcherRes_Par FOREIGN KEY (IdPar) REFERENCES MatcherPar(Id)
);
GO


/* -----------------------------------------------------------------
   2. Tipo de pieza y marca a partir del rubro de Autocor
      'PASTILLAS DE FRENO "LITTON"' -> tipo PASTILLAS DE FRENO, marca LITTON
   ----------------------------------------------------------------- */
IF OBJECT_ID('fn_MatcherTipo', 'FN') IS NOT NULL DROP FUNCTION fn_MatcherTipo;
GO
CREATE FUNCTION fn_MatcherTipo (@Rubro VARCHAR(120))
RETURNS VARCHAR(120)
AS
BEGIN
    IF @Rubro IS NULL RETURN NULL;
    DECLARE @a INT = CHARINDEX('"', @Rubro);
    IF @a = 0 RETURN LTRIM(RTRIM(@Rubro));
    DECLARE @b INT = CHARINDEX('"', @Rubro, @a + 1);
    IF @b = 0 RETURN LTRIM(RTRIM(LEFT(@Rubro, @a - 1)));
    RETURN LTRIM(RTRIM(LEFT(@Rubro, @a - 1) + ' ' + SUBSTRING(@Rubro, @b + 1, 120)));
END
GO
IF OBJECT_ID('fn_MatcherMarca', 'FN') IS NOT NULL DROP FUNCTION fn_MatcherMarca;
GO
CREATE FUNCTION fn_MatcherMarca (@Rubro VARCHAR(120))
RETURNS VARCHAR(60)
AS
BEGIN
    DECLARE @a INT = CHARINDEX('"', ISNULL(@Rubro, ''));
    IF @a = 0 RETURN NULL;
    DECLARE @b INT = CHARINDEX('"', @Rubro, @a + 1);
    IF @b = 0 RETURN NULL;
    RETURN NULLIF(LTRIM(RTRIM(SUBSTRING(@Rubro, @a + 1, @b - @a - 1))), '');
END
GO

-- Proveedor de donde salen las anclas
IF OBJECT_ID('fn_MatcherProveedorAnclas', 'FN') IS NOT NULL DROP FUNCTION fn_MatcherProveedorAnclas;
GO
CREATE FUNCTION fn_MatcherProveedorAnclas ()
RETURNS INT
AS
BEGIN
    RETURN (SELECT TOP 1 Id FROM Proveedor WHERE UPPER(LTRIM(RTRIM(RazonSocial))) LIKE 'AUTOCOR%' ORDER BY Id);
END
GO


/* -----------------------------------------------------------------
   3. Pares por codigo: se cargan como PENDIENTE para revisarlos
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Matcher_CargarParesCodigo', 'P') IS NOT NULL DROP PROCEDURE SP_Matcher_CargarParesCodigo;
GO
CREATE PROCEDURE SP_Matcher_CargarParesCodigo
AS
BEGIN
    SET NOCOUNT ON;
    ;WITH u AS (
        SELECT IdProveedor, dbo.fn_LimpiarCodigo(Articulo) AS Cod, MIN(Id) AS IdPr
        FROM ProveedorRepuesto
        WHERE Activo = 1 AND Articulo IS NOT NULL AND LEN(dbo.fn_LimpiarCodigo(Articulo)) >= 5
        GROUP BY IdProveedor, dbo.fn_LimpiarCodigo(Articulo)
        HAVING COUNT(*) = 1)
    INSERT INTO MatcherPar (IdAncla, IdCandidato, Relacion, Origen)
    SELECT ua.IdPr, ub.IdPr, 'PENDIENTE', 'CODIGO'
    FROM u ua
    INNER JOIN u ub ON ub.Cod = ua.Cod AND ub.IdProveedor > ua.IdProveedor
    WHERE NOT EXISTS (SELECT 1 FROM MatcherPar m
                      WHERE (m.IdAncla = ua.IdPr AND m.IdCandidato = ub.IdPr)
                         OR (m.IdAncla = ub.IdPr AND m.IdCandidato = ua.IdPr));
    SELECT @@ROWCOUNT AS ParesNuevos,
           (SELECT COUNT(*) FROM MatcherPar WHERE Origen = 'CODIGO') AS ParesPorCodigo;
END
GO

IF OBJECT_ID('SP_Matcher_ParesCodigo', 'P') IS NOT NULL DROP PROCEDURE SP_Matcher_ParesCodigo;
GO
CREATE PROCEDURE SP_Matcher_ParesCodigo
AS
BEGIN
    SET NOCOUNT ON;
    SELECT m.Id, m.Relacion,
           a.Articulo AS Codigo,
           pa.RazonSocial AS ProveedorA, a.CodigoProveedor AS CodigoA, a.RubroTexto AS RubroA, a.MarcaTexto AS MarcaA, a.Descripcion AS DescripcionA,
           pb.RazonSocial AS ProveedorB, b.CodigoProveedor AS CodigoB, b.RubroTexto AS RubroB, b.MarcaTexto AS MarcaB, b.Descripcion AS DescripcionB
    FROM MatcherPar m
    INNER JOIN ProveedorRepuesto a ON a.Id = m.IdAncla
    INNER JOIN ProveedorRepuesto b ON b.Id = m.IdCandidato
    INNER JOIN Proveedor pa ON pa.Id = a.IdProveedor
    INNER JOIN Proveedor pb ON pb.Id = b.IdProveedor
    WHERE m.Origen = 'CODIGO'
    ORDER BY CASE WHEN m.Relacion = 'PENDIENTE' THEN 0 ELSE 1 END, m.Id;
END
GO

IF OBJECT_ID('SP_Matcher_RevisarCodigo', 'P') IS NOT NULL DROP PROCEDURE SP_Matcher_RevisarCodigo;
GO
CREATE PROCEDURE SP_Matcher_RevisarCodigo
    @IdPar     INT,
    @Relacion  VARCHAR(12),
    @IdUsuario INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @Relacion NOT IN ('PENDIENTE', 'IGUAL', 'EQUIVALENTE', 'DISTINTO')
        THROW 50701, 'Relacion no valida.', 1;
    UPDATE MatcherPar SET Relacion = @Relacion, IdUsuario = @IdUsuario, Fecha = GETDATE()
    WHERE Id = @IdPar AND Origen = 'CODIGO';
    IF @@ROWCOUNT = 0 THROW 50702, 'No existe ese par por codigo.', 1;
END
GO


/* -----------------------------------------------------------------
   4. Etiquetado manual
   ----------------------------------------------------------------- */

-- Tipos de pieza de Autocor: los que tienen mas marcas primero
-- (ahi es donde mas equivalentes hay que encontrar)
IF OBJECT_ID('SP_Matcher_Tipos', 'P') IS NOT NULL DROP PROCEDURE SP_Matcher_Tipos;
GO
CREATE PROCEDURE SP_Matcher_Tipos
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Aut INT = dbo.fn_MatcherProveedorAnclas();
    SELECT t.Tipo, COUNT(*) AS Articulos, COUNT(DISTINCT t.Marca) AS Marcas,
           ISNULL(MAX(e.Etiquetadas), 0) AS Etiquetadas,
           ISNULL(MAX(e.ConRelacionados), 0) AS ConRelacionados
    FROM (SELECT dbo.fn_MatcherTipo(RubroTexto) AS Tipo, dbo.fn_MatcherMarca(RubroTexto) AS Marca
          FROM ProveedorRepuesto
          WHERE IdProveedor = @Aut AND Activo = 1 AND RubroTexto IS NOT NULL) t
    LEFT JOIN (SELECT a.Tipo, COUNT(*) AS Etiquetadas,
                      SUM(CASE WHEN r.IdAncla IS NOT NULL THEN 1 ELSE 0 END) AS ConRelacionados
               FROM MatcherAncla a
               LEFT JOIN (SELECT DISTINCT IdAncla FROM MatcherPar
                          WHERE Origen = 'MANUAL' AND Relacion IN ('IGUAL', 'EQUIVALENTE')) r ON r.IdAncla = a.IdProveedorRepuesto
               WHERE a.Estado = 'ETIQUETADA' GROUP BY a.Tipo) e ON e.Tipo = t.Tipo
    WHERE t.Tipo <> ''
    GROUP BY t.Tipo
    HAVING COUNT(*) >= 10
    ORDER BY COUNT(DISTINCT t.Marca) DESC, COUNT(*) DESC;
END
GO

-- Proxima ancla de un tipo: primero las que ya estan vinculadas a un
-- repuesto del local (lo que se trabaja), despues al azar.
IF OBJECT_ID('SP_Matcher_Ancla', 'P') IS NOT NULL DROP PROCEDURE SP_Matcher_Ancla;
GO
CREATE PROCEDURE SP_Matcher_Ancla
    @Tipo    VARCHAR(120) = NULL,
    @IdAncla INT = NULL           -- para volver a abrir una ya etiquetada
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Aut INT = dbo.fn_MatcherProveedorAnclas();

    IF @IdAncla IS NULL
        SELECT TOP 1 @IdAncla = pr.Id
        FROM ProveedorRepuesto pr
        WHERE pr.IdProveedor = @Aut AND pr.Activo = 1
          AND pr.RubroTexto LIKE @Tipo + '%'
          AND dbo.fn_MatcherTipo(pr.RubroTexto) = @Tipo
          AND NOT EXISTS (SELECT 1 FROM MatcherAncla a WHERE a.IdProveedorRepuesto = pr.Id)
        ORDER BY CASE WHEN pr.IdRepuesto IS NOT NULL THEN 0 ELSE 1 END, NEWID();

    SELECT pr.Id, p.RazonSocial AS Proveedor, pr.CodigoProveedor, pr.Articulo,
           dbo.fn_MatcherTipo(pr.RubroTexto) AS Tipo, dbo.fn_MatcherMarca(pr.RubroTexto) AS MarcaPieza,
           pr.MarcaTexto, pr.Descripcion, pr.PrecioCompra,
           a.Estado, a.Nota
    FROM ProveedorRepuesto pr
    INNER JOIN Proveedor p ON p.Id = pr.IdProveedor
    LEFT JOIN MatcherAncla a ON a.IdProveedorRepuesto = pr.Id
    WHERE pr.Id = @IdAncla;

    -- Lo que ya se marco para esa ancla
    SELECT m.IdCandidato AS Id, m.Relacion, p.RazonSocial AS Proveedor, c.CodigoProveedor, c.Articulo,
           c.RubroTexto, c.MarcaTexto, c.Descripcion, c.PrecioCompra
    FROM MatcherPar m
    INNER JOIN ProveedorRepuesto c ON c.Id = m.IdCandidato
    INNER JOIN Proveedor p ON p.Id = c.IdProveedor
    WHERE m.IdAncla = @IdAncla AND m.Origen = 'MANUAL';
END
GO

/* Guarda una ancla con lo que se marco. @Pares: "123:IGUAL,456:EQUIVALENTE"
   Reemplaza lo marcado antes para esa ancla. Todo o nada. */
IF OBJECT_ID('SP_Matcher_Etiquetar', 'P') IS NOT NULL DROP PROCEDURE SP_Matcher_Etiquetar;
GO
CREATE PROCEDURE SP_Matcher_Etiquetar
    @IdAncla   INT,
    @Estado    VARCHAR(12),
    @Pares     VARCHAR(MAX) = NULL,
    @Nota      NVARCHAR(200) = NULL,
    @IdUsuario INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Estado NOT IN ('ETIQUETADA', 'SALTEADA') THROW 50703, 'Estado no valido.', 1;
    DECLARE @Tipo VARCHAR(120) = (SELECT dbo.fn_MatcherTipo(RubroTexto) FROM ProveedorRepuesto WHERE Id = @IdAncla);
    IF @Tipo IS NULL THROW 50704, 'El ancla no existe o no tiene tipo de pieza.', 1;

    DECLARE @p TABLE (IdCandidato INT PRIMARY KEY, Relacion VARCHAR(12));
    DECLARE @resto VARCHAR(MAX) = ISNULL(@Pares, '') + ',', @item VARCHAR(60), @pos INT, @dp INT;
    WHILE LEN(@resto) > 1
    BEGIN
        SET @pos = CHARINDEX(',', @resto);
        SET @item = LTRIM(RTRIM(LEFT(@resto, @pos - 1)));
        SET @resto = SUBSTRING(@resto, @pos + 1, LEN(@resto));
        SET @dp = CHARINDEX(':', @item);
        IF @dp > 1
            INSERT INTO @p (IdCandidato, Relacion)
            SELECT TRY_CAST(LEFT(@item, @dp - 1) AS INT), UPPER(SUBSTRING(@item, @dp + 1, 12))
            WHERE TRY_CAST(LEFT(@item, @dp - 1) AS INT) IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM @p WHERE IdCandidato = TRY_CAST(LEFT(@item, @dp - 1) AS INT));
    END

    IF EXISTS (SELECT 1 FROM @p WHERE Relacion NOT IN ('IGUAL', 'EQUIVALENTE', 'DISTINTO'))
        THROW 50705, 'Hay una relacion no valida.', 1;
    IF EXISTS (SELECT 1 FROM @p x WHERE x.IdCandidato = @IdAncla OR NOT EXISTS (SELECT 1 FROM ProveedorRepuesto c WHERE c.Id = x.IdCandidato))
        THROW 50706, 'Hay un candidato que no existe.', 1;

    BEGIN TRAN;
        IF EXISTS (SELECT 1 FROM MatcherAncla WHERE IdProveedorRepuesto = @IdAncla)
            UPDATE MatcherAncla SET Estado = @Estado, Nota = @Nota, IdUsuario = @IdUsuario, Fecha = GETDATE()
            WHERE IdProveedorRepuesto = @IdAncla;
        ELSE
            INSERT INTO MatcherAncla (IdProveedorRepuesto, Tipo, Estado, Nota, IdUsuario)
            VALUES (@IdAncla, @Tipo, @Estado, @Nota, @IdUsuario);

        DELETE FROM MatcherPar WHERE IdAncla = @IdAncla AND Origen = 'MANUAL';

        INSERT INTO MatcherPar (IdAncla, IdCandidato, Relacion, Origen, IdUsuario)
        SELECT @IdAncla, x.IdCandidato, x.Relacion, 'MANUAL', @IdUsuario
        FROM @p x
        WHERE @Estado = 'ETIQUETADA'
          AND NOT EXISTS (SELECT 1 FROM MatcherPar m WHERE m.IdAncla = @IdAncla AND m.IdCandidato = x.IdCandidato);
    COMMIT;

    SELECT (SELECT COUNT(*) FROM MatcherPar WHERE IdAncla = @IdAncla AND Origen = 'MANUAL') AS ParesGuardados;
END
GO

-- Avance y ultimas anclas
IF OBJECT_ID('SP_Matcher_Resumen', 'P') IS NOT NULL DROP PROCEDURE SP_Matcher_Resumen;
GO
CREATE PROCEDURE SP_Matcher_Resumen
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        (SELECT COUNT(*) FROM MatcherAncla WHERE Estado = 'ETIQUETADA') AS Anclas,
        (SELECT COUNT(*) FROM MatcherAncla WHERE Estado = 'SALTEADA') AS Salteadas,
        (SELECT COUNT(DISTINCT IdAncla) FROM MatcherPar WHERE Origen = 'MANUAL' AND Relacion = 'IGUAL') AS AnclasConIgual,
        (SELECT COUNT(DISTINCT IdAncla) FROM MatcherPar WHERE Origen = 'MANUAL' AND Relacion = 'EQUIVALENTE') AS AnclasConEquivalente,
        (SELECT COUNT(*) FROM MatcherPar WHERE Origen = 'MANUAL' AND Relacion = 'IGUAL') AS ParesIgual,
        (SELECT COUNT(*) FROM MatcherPar WHERE Origen = 'MANUAL' AND Relacion = 'EQUIVALENTE') AS ParesEquivalente,
        (SELECT COUNT(*) FROM MatcherPar WHERE Origen = 'CODIGO') AS CodigoTotal,
        (SELECT COUNT(*) FROM MatcherPar WHERE Origen = 'CODIGO' AND Relacion = 'PENDIENTE') AS CodigoPendientes,
        (SELECT COUNT(*) FROM MatcherPar WHERE Origen = 'CODIGO' AND Relacion IN ('IGUAL', 'EQUIVALENTE')) AS CodigoConfirmados,
        (SELECT COUNT(*) FROM MatcherPar WHERE Origen = 'CODIGO' AND Relacion = 'DISTINTO') AS CodigoDistintos;

    SELECT TOP 20 a.IdProveedorRepuesto AS Id, a.Tipo, a.Estado, a.Fecha, pr.Descripcion,
           dbo.fn_MatcherMarca(pr.RubroTexto) AS MarcaPieza,
           (SELECT COUNT(*) FROM MatcherPar m WHERE m.IdAncla = a.IdProveedorRepuesto AND m.Origen = 'MANUAL' AND m.Relacion = 'IGUAL') AS Iguales,
           (SELECT COUNT(*) FROM MatcherPar m WHERE m.IdAncla = a.IdProveedorRepuesto AND m.Origen = 'MANUAL' AND m.Relacion = 'EQUIVALENTE') AS Equivalentes
    FROM MatcherAncla a
    INNER JOIN ProveedorRepuesto pr ON pr.Id = a.IdProveedorRepuesto
    ORDER BY a.Fecha DESC;
END
GO


/* -----------------------------------------------------------------
   5. Cargar los pares por codigo y mostrar como quedo
   ----------------------------------------------------------------- */
EXEC SP_Matcher_CargarParesCodigo;
GO
EXEC SP_Matcher_Resumen;
GO
