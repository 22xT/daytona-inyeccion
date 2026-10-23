USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   65 — EQUIVALENCIAS Y VINCULACION ORDENADA

   Dos relaciones distintas que hasta ahora estaban mezcladas:

   VINCULAR (ya existia): "este articulo del proveedor B ES este
   repuesto". Misma marca, mismo codigo. Comparten stock, precio y
   pedido. Ej: SKF VKMA01107 de Autocor = SKF VKMA01107 de Expoyer.

   EQUIVALENTE (nuevo): "es la misma pieza de OTRA marca". Cada uno
   conserva su stock y su precio, pero quedan en el mismo grupo.
   Ej: Kit distribucion Suran -> SKF VKMA01107, Dayco KTB341, INA ...
   Sirve para ofrecer otra marca cuando una no hay, y para que no
   queden repuestos sueltos.

   Ademas la busqueda para vincular deja de ordenar alfabeticamente:
   ordena por parecido (codigo de fabrica, palabras en comun, misma
   marca, mismo rubro) y devuelve la marca de cada resultado.
   ================================================================= */


/* -----------------------------------------------------------------
   1. Grupos de equivalencia
   ----------------------------------------------------------------- */
IF OBJECT_ID('GrupoEquivalencia', 'U') IS NULL
    CREATE TABLE GrupoEquivalencia (
        Id        INT IDENTITY(1,1) PRIMARY KEY,
        Nombre    NVARCHAR(100) NOT NULL,
        FechaAlta DATETIME NOT NULL DEFAULT GETDATE()
    );
GO

IF COL_LENGTH('Repuesto', 'IdGrupoEquivalencia') IS NULL
    ALTER TABLE Repuesto ADD IdGrupoEquivalencia INT NULL
        CONSTRAINT FK_Repuesto_GrupoEquivalencia REFERENCES GrupoEquivalencia(Id);
GO

-- Para articulos de lista que todavia no estan en el catalogo propio.
-- Cuando un articulo esta vinculado a un repuesto, manda el grupo del repuesto.
IF COL_LENGTH('ProveedorRepuesto', 'IdGrupoEquivalencia') IS NULL
    ALTER TABLE ProveedorRepuesto ADD IdGrupoEquivalencia INT NULL
        CONSTRAINT FK_ProvRep_GrupoEquivalencia REFERENCES GrupoEquivalencia(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Repuesto_Grupo')
    CREATE INDEX IX_Repuesto_Grupo ON Repuesto(IdGrupoEquivalencia) WHERE IdGrupoEquivalencia IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ProvRep_Grupo')
    CREATE INDEX IX_ProvRep_Grupo ON ProveedorRepuesto(IdGrupoEquivalencia) WHERE IdGrupoEquivalencia IS NOT NULL;
GO


/* -----------------------------------------------------------------
   2. Unir dos grupos (uso interno)
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Equivalencia_Unir', 'P') IS NOT NULL DROP PROCEDURE SP_Equivalencia_Unir;
GO
CREATE PROCEDURE SP_Equivalencia_Unir
    @Queda INT,
    @SeVa  INT
AS
BEGIN
    SET NOCOUNT ON;
    IF @Queda IS NULL OR @SeVa IS NULL OR @Queda = @SeVa RETURN;

    UPDATE Repuesto          SET IdGrupoEquivalencia = @Queda WHERE IdGrupoEquivalencia = @SeVa;
    UPDATE ProveedorRepuesto SET IdGrupoEquivalencia = @Queda WHERE IdGrupoEquivalencia = @SeVa;
    DELETE FROM GrupoEquivalencia WHERE Id = @SeVa;
END
GO


/* -----------------------------------------------------------------
   3. Agregar un articulo de lista como equivalente de un repuesto
      Si el articulo ya es un repuesto del catalogo, se agrupa ese
      repuesto. Si cada uno ya tenia grupo, los grupos se unen.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Equivalencia_Agregar', 'P') IS NOT NULL DROP PROCEDURE SP_Equivalencia_Agregar;
GO
CREATE PROCEDURE SP_Equivalencia_Agregar
    @IdRepuesto          INT,
    @IdProveedorRepuesto INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM Repuesto WHERE Id = @IdRepuesto)
        THROW 50120, 'El repuesto no existe.', 1;
    IF NOT EXISTS (SELECT 1 FROM ProveedorRepuesto WHERE Id = @IdProveedorRepuesto)
        THROW 50121, 'El articulo de la lista no existe.', 1;

    DECLARE @otroRep INT, @gR INT, @gO INT, @nombre NVARCHAR(100);

    SELECT @otroRep = IdRepuesto FROM ProveedorRepuesto WHERE Id = @IdProveedorRepuesto;

    IF @otroRep = @IdRepuesto
        THROW 50122, 'Ese articulo ya esta vinculado a este repuesto: es el mismo, no un equivalente.', 1;

    SELECT @gR = IdGrupoEquivalencia, @nombre = Descripcion FROM Repuesto WHERE Id = @IdRepuesto;

    IF @otroRep IS NOT NULL
        SELECT @gO = IdGrupoEquivalencia FROM Repuesto WHERE Id = @otroRep;
    ELSE
        SELECT @gO = IdGrupoEquivalencia FROM ProveedorRepuesto WHERE Id = @IdProveedorRepuesto;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @gR IS NULL AND @gO IS NULL
        BEGIN
            INSERT INTO GrupoEquivalencia (Nombre) VALUES (@nombre);
            SET @gR = CAST(SCOPE_IDENTITY() AS INT);
        END
        ELSE IF @gR IS NULL
            SET @gR = @gO;
        ELSE IF @gO IS NOT NULL AND @gO <> @gR
            EXEC SP_Equivalencia_Unir @Queda = @gR, @SeVa = @gO;

        UPDATE Repuesto SET IdGrupoEquivalencia = @gR WHERE Id = @IdRepuesto;

        IF @otroRep IS NOT NULL
            UPDATE Repuesto SET IdGrupoEquivalencia = @gR WHERE Id = @otroRep;
        ELSE
            UPDATE ProveedorRepuesto SET IdGrupoEquivalencia = @gR WHERE Id = @IdProveedorRepuesto;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    SELECT @gR AS IdGrupo;
END
GO


/* -----------------------------------------------------------------
   4. Sacar algo de su grupo
      Se indica el repuesto O el articulo de lista. Si el grupo queda
      con un solo integrante, deja de existir.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Equivalencia_Quitar', 'P') IS NOT NULL DROP PROCEDURE SP_Equivalencia_Quitar;
GO
CREATE PROCEDURE SP_Equivalencia_Quitar
    @IdRepuesto          INT = NULL,
    @IdProveedorRepuesto INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @g INT;

    IF @IdRepuesto IS NOT NULL
        SELECT @g = IdGrupoEquivalencia FROM Repuesto WHERE Id = @IdRepuesto;
    ELSE IF @IdProveedorRepuesto IS NOT NULL
        SELECT @g = IdGrupoEquivalencia FROM ProveedorRepuesto WHERE Id = @IdProveedorRepuesto;
    ELSE
        THROW 50123, 'Hay que indicar que se saca del grupo.', 1;

    IF @g IS NULL RETURN;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @IdRepuesto IS NOT NULL
            UPDATE Repuesto SET IdGrupoEquivalencia = NULL WHERE Id = @IdRepuesto;
        ELSE
            UPDATE ProveedorRepuesto SET IdGrupoEquivalencia = NULL WHERE Id = @IdProveedorRepuesto;

        DECLARE @quedan INT =
            (SELECT COUNT(*) FROM Repuesto WHERE IdGrupoEquivalencia = @g) +
            (SELECT COUNT(*) FROM ProveedorRepuesto WHERE IdGrupoEquivalencia = @g AND IdRepuesto IS NULL);

        IF @quedan < 2
        BEGIN
            UPDATE Repuesto          SET IdGrupoEquivalencia = NULL WHERE IdGrupoEquivalencia = @g;
            UPDATE ProveedorRepuesto SET IdGrupoEquivalencia = NULL WHERE IdGrupoEquivalencia = @g;
            DELETE FROM GrupoEquivalencia WHERE Id = @g;
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   5. Cuando un articulo de lista agrupado entra al catalogo (se
      incorpora o se vincula), su grupo pasa al repuesto.
   ----------------------------------------------------------------- */
IF OBJECT_ID('TR_ProveedorRepuesto_Equivalencia', 'TR') IS NOT NULL
    DROP TRIGGER TR_ProveedorRepuesto_Equivalencia;
GO
CREATE TRIGGER TR_ProveedorRepuesto_Equivalencia ON ProveedorRepuesto
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(IdRepuesto) RETURN;

    DECLARE @idPR INT, @idRep INT, @gPR INT, @gRep INT;
    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT i.Id, i.IdRepuesto, i.IdGrupoEquivalencia
        FROM inserted i
        WHERE i.IdRepuesto IS NOT NULL AND i.IdGrupoEquivalencia IS NOT NULL;

    OPEN cur;
    FETCH NEXT FROM cur INTO @idPR, @idRep, @gPR;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SELECT @gRep = IdGrupoEquivalencia FROM Repuesto WHERE Id = @idRep;

        IF @gRep IS NULL
            UPDATE Repuesto SET IdGrupoEquivalencia = @gPR WHERE Id = @idRep;
        ELSE IF @gRep <> @gPR
            EXEC SP_Equivalencia_Unir @Queda = @gRep, @SeVa = @gPR;

        -- Vinculado: manda el grupo del repuesto
        UPDATE ProveedorRepuesto SET IdGrupoEquivalencia = NULL WHERE Id = @idPR;

        FETCH NEXT FROM cur INTO @idPR, @idRep, @gPR;
    END
    CLOSE cur; DEALLOCATE cur;
END
GO


/* -----------------------------------------------------------------
   6. Equivalentes de un repuesto (los demas integrantes del grupo)
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Repuesto_Equivalentes', 'P') IS NOT NULL DROP PROCEDURE SP_Repuesto_Equivalentes;
GO
CREATE PROCEDURE SP_Repuesto_Equivalentes
    @IdRepuesto INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @g INT = (SELECT IdGrupoEquivalencia FROM Repuesto WHERE Id = @IdRepuesto);

    SELECT 'CATALOGO'                    AS Tipo,
           r.Id                          AS IdRepuesto,
           CAST(NULL AS INT)             AS IdProveedorRepuesto,
           CAST(r.Codigo AS VARCHAR(40)) AS Codigo,
           CAST(r.Descripcion AS NVARCHAR(250)) AS Descripcion,
           CAST(r.MarcaFabricante AS VARCHAR(60)) AS Marca,
           ISNULL(s.Cantidad, 0)         AS Stock,
           CAST(r.PrecioDeVenta AS DECIMAL(12,2)) AS Precio,   -- precio de venta
           CAST(NULL AS VARCHAR(200))    AS Proveedor
    FROM Repuesto r
    LEFT JOIN Stock s ON s.IdRepuesto = r.Id
    WHERE @g IS NOT NULL AND r.IdGrupoEquivalencia = @g AND r.Id <> @IdRepuesto AND r.Activo = 1

    UNION ALL

    SELECT 'LISTA', NULL, pr.Id,
           CAST(pr.CodigoProveedor AS VARCHAR(40)),
           CAST(pr.Descripcion AS NVARCHAR(250)),
           CAST(pr.MarcaTexto AS VARCHAR(60)),
           0,
           CAST(pr.PrecioCompra AS DECIMAL(12,2)),               -- costo
           CAST(p.RazonSocial AS VARCHAR(200))
    FROM ProveedorRepuesto pr
    INNER JOIN Proveedor p ON p.Id = pr.IdProveedor
    WHERE @g IS NOT NULL AND pr.IdGrupoEquivalencia = @g AND pr.IdRepuesto IS NULL AND pr.Activo = 1

    ORDER BY Tipo, Stock DESC, Descripcion;
END
GO


/* -----------------------------------------------------------------
   7. Pantalla de vinculacion: tres resultados en una sola llamada
      1) el repuesto  2) candidatos ordenados por parecido
      3) sus equivalentes actuales

      @Texto NULL = se arma solo con la descripcion del repuesto,
      sin la marca ni el codigo (para que aparezcan otras marcas).
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Repuesto_Vinculacion', 'P') IS NOT NULL DROP PROCEDURE SP_Repuesto_Vinculacion;
GO
CREATE PROCEDURE SP_Repuesto_Vinculacion
    @IdRepuesto INT,
    @Texto      VARCHAR(100) = NULL,
    @Tope       INT = 40
AS
BEGIN
    SET NOCOUNT ON;

    IF @Tope IS NULL OR @Tope <= 0 OR @Tope > 100 SET @Tope = 40;

    DECLARE @desc NVARCHAR(100), @marca VARCHAR(60), @codFab VARCHAR(40), @cod VARCHAR(40),
            @idRubro INT, @costo DECIMAL(12,2), @grupo INT;

    SELECT @desc = Descripcion, @marca = MarcaFabricante, @codFab = CodigoFabricante,
           @cod = Codigo, @idRubro = IdRubro, @costo = PrecioCompra, @grupo = IdGrupoEquivalencia
    FROM Repuesto WHERE Id = @IdRepuesto;

    IF @desc IS NULL
        THROW 50124, 'El repuesto no existe.', 1;

    DECLARE @auto BIT = CASE WHEN NULLIF(LTRIM(RTRIM(@Texto)), '') IS NULL THEN 1 ELSE 0 END;
    DECLARE @codFabL VARCHAR(60) = dbo.fn_LimpiarCodigo(ISNULL(@codFab, ''));
    DECLARE @codL    VARCHAR(60) = dbo.fn_LimpiarCodigo(ISNULL(@cod, ''));
    DECLARE @marcaL  VARCHAR(60) = dbo.fn_LimpiarCodigo(ISNULL(@marca, ''));
    DECLARE @marcaN  VARCHAR(100) = ISNULL(dbo.fn_NormalizarBusqueda(@marca), '');

    /* Palabras a buscar (hasta 8), normalizadas igual que TextoBusqueda */
    DECLARE @Palabras TABLE (Orden INT IDENTITY(1,1), W VARCHAR(60), Cod VARCHAR(60));
    DECLARE @t VARCHAR(400) = ISNULL(dbo.fn_NormalizarBusqueda(CASE WHEN @auto = 1 THEN @desc ELSE @Texto END), '') + ' ';
    DECLARE @pos INT, @w VARCHAR(60);

    WHILE LEN(@t) > 0 AND (SELECT COUNT(*) FROM @Palabras) < 8
    BEGIN
        IF CHARINDEX(' ', @t) = 0 SET @t = @t + ' ';
        SET @pos = CHARINDEX(' ', @t);
        SET @w = LEFT(@t, @pos - 1);
        SET @t = LTRIM(SUBSTRING(@t, @pos + 1, 400));

        IF LEN(@w) >= 2
           AND @w NOT IN ('DE','LA','EL','LOS','LAS','CON','SIN','PARA','POR','Y','EN','AL','DEL')
           AND NOT EXISTS (SELECT 1 FROM @Palabras WHERE W = @w)
           -- En automatico se saca la marca y los codigos propios:
           -- asi aparecen tambien las otras marcas de la misma pieza
           AND NOT (@auto = 1 AND (
                    (@marcaN <> '' AND ' ' + @marcaN + ' ' LIKE '% ' + @w + ' %')
                 OR (dbo.fn_LimpiarCodigo(@w) IN (@codFabL, @codL) AND LEN(dbo.fn_LimpiarCodigo(@w)) >= 4)))
            INSERT INTO @Palabras (W, Cod)
            VALUES (@w, CASE WHEN @w LIKE '%[0-9]%' AND LEN(dbo.fn_LimpiarCodigo(@w)) >= 4
                             THEN dbo.fn_LimpiarCodigo(@w) END);
    END

    DECLARE @n INT = (SELECT COUNT(*) FROM @Palabras);
    DECLARE @req INT = CASE WHEN @n <= 2 THEN @n WHEN @n = 3 THEN 2 ELSE CEILING(@n * 0.6) END;

    DECLARE @textoUsado VARCHAR(400) =
        CASE WHEN @auto = 1
             THEN ISNULL((SELECT ' ' + W FROM @Palabras ORDER BY Orden FOR XML PATH(''), TYPE).value('.', 'VARCHAR(400)'), '')
             ELSE @Texto END;

    /* 1) El repuesto */
    SELECT r.Id, r.Codigo, r.Descripcion, r.MarcaFabricante, r.CodigoFabricante,
           r.IdGrupoEquivalencia, r.PrecioCompra, ISNULL(s.Cantidad, 0) AS Stock,
           LTRIM(@textoUsado) AS TextoUsado
    FROM Repuesto r
    LEFT JOIN Stock s ON s.IdRepuesto = r.Id
    WHERE r.Id = @IdRepuesto;

    /* 2) Candidatos */
    ;WITH base AS (
        SELECT pr.Id, pr.IdProveedor, p.RazonSocial AS Proveedor, pr.CodigoProveedor,
               pr.Articulo, pr.Descripcion, pr.MarcaTexto, pr.PrecioCompra, pr.IdRubro,
               pr.IdRepuesto AS IdRepuestoEnlazado,
               re.Codigo AS CodigoEnlazado, re.Descripcion AS DescripcionEnlazado,
               (SELECT COUNT(*) FROM @Palabras w
                WHERE pr.TextoBusqueda LIKE '% ' + w.W + '%'
                   OR (w.Cod IS NOT NULL AND pr.CodigosBusqueda LIKE '%' + w.Cod + '%')) AS Coincidencias,
               -- Mismo codigo de fabrica: en su columna, o escrito en la
               -- descripcion (Expoyer pone "KIT ... KTBWP3411 FOX/SURAN")
               CASE WHEN LEN(@codFabL) >= 5
                     AND (REPLACE(REPLACE(REPLACE(REPLACE(UPPER(ISNULL(pr.Articulo, '')), '-', ''), ' ', ''), '.', ''), '/', '') = @codFabL
                          OR REPLACE(pr.TextoBusqueda, '-', '') LIKE '% ' + @codFabL + ' %')
                    THEN 1 ELSE 0 END AS MismoCodigo,
               REPLACE(REPLACE(REPLACE(REPLACE(UPPER(ISNULL(pr.MarcaTexto, '')), '-', ''), ' ', ''), '.', ''), '/', '') AS mL,
               pr.TextoBusqueda,
               CASE WHEN EXISTS (SELECT 1 FROM ProveedorRepuesto x
                                 WHERE x.IdRepuesto = @IdRepuesto AND x.IdProveedor = pr.IdProveedor)
                    THEN 1 ELSE 0 END AS ProveedorYaVinculado
        FROM ProveedorRepuesto pr
        INNER JOIN Proveedor p ON p.Id = pr.IdProveedor
        LEFT JOIN Repuesto re  ON re.Id = pr.IdRepuesto
        WHERE pr.Activo = 1
          AND pr.PrecioCompra > 0
          AND ISNULL(pr.IdRepuesto, 0) <> @IdRepuesto
          -- Lo que ya es equivalente se muestra aparte
          AND NOT (@grupo IS NOT NULL AND (pr.IdGrupoEquivalencia = @grupo OR re.IdGrupoEquivalencia = @grupo))
    ),
    filtrado AS (
        SELECT b.*,
               CASE
                   WHEN @marcaL = '' THEN 'SIN_DATO'
                   WHEN b.mL = '' THEN
                        CASE WHEN @marcaN <> '' AND b.TextoBusqueda LIKE '% ' + @marcaN + ' %'
                             THEN 'MISMA' ELSE 'SIN_DATO' END
                   WHEN b.mL = @marcaL THEN 'MISMA'
                   WHEN LEN(@marcaL) >= 3 AND LEN(b.mL) >= 3
                        AND (CHARINDEX(@marcaL, b.mL) > 0 OR CHARINDEX(b.mL, @marcaL) > 0) THEN 'MISMA'
                   ELSE 'OTRA'
               END AS Marca
        FROM base b
        WHERE b.MismoCodigo = 1 OR (@n > 0 AND b.Coincidencias >= @req)
    )
    SELECT TOP (@Tope)
        f.Id, f.IdProveedor, f.Proveedor, f.CodigoProveedor, f.Articulo, f.Descripcion,
        f.MarcaTexto, f.Marca, f.PrecioCompra,
        CASE WHEN @costo > 0 THEN CAST((f.PrecioCompra - @costo) / @costo * 100 AS DECIMAL(8,1)) END AS DiferenciaPorc,
        f.MismoCodigo, f.Coincidencias, @n AS Palabras,
        f.IdRepuestoEnlazado, f.CodigoEnlazado, f.DescripcionEnlazado, f.ProveedorYaVinculado,
        f.MismoCodigo * 100 + f.Coincidencias * 10
          + CASE WHEN f.Marca = 'MISMA' THEN 15 ELSE 0 END
          + CASE WHEN f.IdRubro = @idRubro THEN 5 ELSE 0 END AS Puntaje,
        -- Solo se pre-marca lo seguro; el resto lo decide la persona
        CASE WHEN f.MismoCodigo = 1 AND f.Marca <> 'OTRA'
                  AND f.IdRepuestoEnlazado IS NULL AND f.ProveedorYaVinculado = 0
             THEN 'MISMO' ELSE '' END AS Sugerido
    FROM filtrado f
    ORDER BY Puntaje DESC, f.PrecioCompra;

    /* 3) Equivalentes actuales */
    EXEC SP_Repuesto_Equivalentes @IdRepuesto = @IdRepuesto;
END
GO


/* -----------------------------------------------------------------
   PRUEBA (no modifica nada): el repuesto con mas proveedores
   ----------------------------------------------------------------- */
DECLARE @id INT = (SELECT TOP 1 IdRepuesto FROM ProveedorRepuesto
                   WHERE IdRepuesto IS NOT NULL GROUP BY IdRepuesto ORDER BY COUNT(*) DESC);
EXEC SP_Repuesto_Vinculacion @IdRepuesto = @id;
GO
