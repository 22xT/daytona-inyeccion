USE [DaytonaInyeccion];
GO

/* =================================================================
   09b — CORRECCION DEL CATALOGO MAESTRO

   Dos problemas del script 09 original:

   1. El ALTER COLUMN sobre Repuesto.Codigo corria ANTES de que se
      quitara el indice unico que dependia de esa columna. El indice
      ya se elimino, asi que ahora el ALTER pasa.

   2. ProveedorRepuesto YA EXISTIA en la base con una estructura
      minima (IdProveedor, IdRepuesto, Precio, Fecha), seguramente
      como esqueleto de la integracion con proveedores que nunca se
      completo. El script la salteaba por el IF OBJECT_ID IS NULL y
      todos los SPs fallaban contra columnas inexistentes.

      La tabla esta VACIA, por lo que se reemplaza sin perdida de
      datos. La version minima no servia: sin CodigoProveedor no
      puede almacenar el catalogo de un mayorista, solo la relacion
      con repuestos ya existentes.
   ================================================================= */

/* -----------------------------------------------------------------
   1. Confirmar que esta vacia antes de reemplazarla
   ----------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM ProveedorRepuesto)
BEGIN
    RAISERROR('ProveedorRepuesto tiene datos. Frenar y revisar antes de continuar.', 16, 1);
    RETURN;
END
GO

PRINT 'ProveedorRepuesto esta vacia. Se reemplaza.';
GO


/* -----------------------------------------------------------------
   2. Repuesto.Codigo: ahora si, sin el indice viejo encima
   ----------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM sys.columns
           WHERE object_id = OBJECT_ID('Repuesto') AND name = 'Codigo' AND is_nullable = 0)
    ALTER TABLE Repuesto ALTER COLUMN Codigo VARCHAR(40) NULL;
GO

UPDATE Repuesto SET Codigo = NULL WHERE LTRIM(RTRIM(ISNULL(Codigo, ''))) = '';
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID('Repuesto') AND name = 'UX_Repuesto_Codigo')
    CREATE UNIQUE NONCLUSTERED INDEX UX_Repuesto_Codigo
        ON Repuesto(Codigo) WHERE Codigo IS NOT NULL;
GO


/* -----------------------------------------------------------------
   3. Reemplazar ProveedorRepuesto
   ----------------------------------------------------------------- */
IF OBJECT_ID('ProveedorRepuesto', 'U') IS NOT NULL DROP TABLE ProveedorRepuesto;
GO

CREATE TABLE ProveedorRepuesto (
    Id                INT IDENTITY(1,1) PRIMARY KEY,
    IdProveedor       INT           NOT NULL,

    CodigoProveedor   VARCHAR(30)   NOT NULL,   -- codigo interno del mayorista
    Articulo          VARCHAR(40)   NULL,       -- codigo del fabricante
    RubroTexto        VARCHAR(120)  NULL,
    MarcaTexto        VARCHAR(60)   NULL,
    Descripcion       VARCHAR(250)  NOT NULL,

    PrecioLista       DECIMAL(12,2) NOT NULL,
    DescuentoRubro    DECIMAL(6,2)  NOT NULL DEFAULT 0,
    DescuentoGeneral  DECIMAL(6,2)  NOT NULL DEFAULT 0,
    PrecioCompra      DECIMAL(12,2) NOT NULL,   -- costo real con descuentos aplicados

    IdRubro           INT           NULL,       -- rubro propio, si matcheo
    IdRepuesto        INT           NULL,       -- se completa al incorporarlo

    FechaLista        DATE          NOT NULL,
    Activo            BIT           NOT NULL DEFAULT 1,

    CONSTRAINT FK_ProvRep_Proveedor FOREIGN KEY (IdProveedor) REFERENCES Proveedor(Id),
    CONSTRAINT FK_ProvRep_Rubro     FOREIGN KEY (IdRubro)     REFERENCES Rubro(Id),
    CONSTRAINT FK_ProvRep_Repuesto  FOREIGN KEY (IdRepuesto)  REFERENCES Repuesto(Id),
    CONSTRAINT UQ_ProvRep UNIQUE (IdProveedor, CodigoProveedor)
);
GO

CREATE INDEX IX_ProvRep_Repuesto ON ProveedorRepuesto(IdRepuesto);
CREATE INDEX IX_ProvRep_Rubro    ON ProveedorRepuesto(IdRubro);
CREATE INDEX IX_ProvRep_Articulo ON ProveedorRepuesto(Articulo);
GO


/* -----------------------------------------------------------------
   4. Descuento general del proveedor, por si el script 07 no llego
   ----------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('Proveedor') AND name = 'DescuentoGeneral')
    ALTER TABLE Proveedor ADD DescuentoGeneral DECIMAL(6,2) NOT NULL
        CONSTRAINT DF_Proveedor_DtoGral DEFAULT 0;
GO


/* -----------------------------------------------------------------
   4. SP: sugerir enlaces entre la lista y tu catalogo

   NO enlaza nada. Devuelve candidatos con su nivel de confianza
   para que una persona confirme.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Proveedor_SugerirEnlaces', 'P') IS NOT NULL
    DROP PROCEDURE SP_Proveedor_SugerirEnlaces;
GO

CREATE PROCEDURE SP_Proveedor_SugerirEnlaces
    @IdProveedor INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        r.Id                AS IdRepuesto,
        r.Codigo            AS MiCodigo,
        r.Descripcion       AS MiDescripcion,
        r.CodigoFabricante  AS MiCodigoFabricante,
        r.PrecioCompra      AS MiCostoActual,

        pr.Id               AS IdListaProveedor,
        pr.CodigoProveedor,
        pr.Articulo         AS CodigoFabricanteProveedor,
        pr.Descripcion      AS DescripcionProveedor,
        pr.PrecioCompra     AS CostoProveedor,

        CASE WHEN r.PrecioCompra > 0
             THEN CAST((pr.PrecioCompra - r.PrecioCompra) / r.PrecioCompra * 100 AS DECIMAL(6,2))
             ELSE NULL END  AS DiferenciaPorc,

        -- Alta: mismo codigo de fabricante Y mismo rubro.
        -- Se exige el rubro porque hay codigos de fabricante basura
        -- repetidos en piezas que no tienen nada que ver.
        CASE
            WHEN r.CodigoFabricante IS NOT NULL
             AND pr.Articulo = r.CodigoFabricante
             AND pr.IdRubro = r.IdRubro          THEN 'Alta'
            WHEN r.CodigoFabricante IS NOT NULL
             AND pr.Articulo = r.CodigoFabricante THEN 'Media'
            WHEN UPPER(LTRIM(RTRIM(pr.Descripcion))) = UPPER(LTRIM(RTRIM(r.Descripcion)))
                                                  THEN 'Media'
            ELSE 'Baja'
        END AS Confianza

    FROM Repuesto r
    INNER JOIN ProveedorRepuesto pr
        ON pr.IdProveedor = @IdProveedor
       AND pr.Activo = 1
       AND pr.IdRepuesto IS NULL      -- solo los que todavia no estan enlazados
       AND (
             (r.CodigoFabricante IS NOT NULL AND pr.Articulo = r.CodigoFabricante)
             OR pr.Descripcion LIKE '%' + LEFT(r.Descripcion, 15) + '%'
           )
    WHERE r.Activo = 1
    ORDER BY
        CASE WHEN r.CodigoFabricante IS NOT NULL AND pr.Articulo = r.CodigoFabricante
                  AND pr.IdRubro = r.IdRubro THEN 1
             WHEN r.CodigoFabricante IS NOT NULL AND pr.Articulo = r.CodigoFabricante THEN 2
             ELSE 3 END,
        r.Descripcion;
END
GO


/* -----------------------------------------------------------------
   5. SP: confirmar un enlace
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Proveedor_EnlazarRepuesto', 'P') IS NOT NULL
    DROP PROCEDURE SP_Proveedor_EnlazarRepuesto;
GO

CREATE PROCEDURE SP_Proveedor_EnlazarRepuesto
    @IdListaProveedor INT,
    @IdRepuesto       INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM ProveedorRepuesto WHERE Id = @IdListaProveedor)
    BEGIN
        RAISERROR('El articulo de la lista no existe.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM Repuesto WHERE Id = @IdRepuesto)
    BEGIN
        RAISERROR('El repuesto indicado no existe.', 16, 1);
        RETURN;
    END

    -- Un proveedor no puede tener dos articulos apuntando al mismo
    -- repuesto: seria el mismo producto cotizado dos veces.
    IF EXISTS (SELECT 1 FROM ProveedorRepuesto pr
               INNER JOIN ProveedorRepuesto nuevo ON nuevo.Id = @IdListaProveedor
               WHERE pr.IdProveedor = nuevo.IdProveedor
                 AND pr.IdRepuesto = @IdRepuesto
                 AND pr.Id <> @IdListaProveedor)
    BEGIN
        RAISERROR('Ese proveedor ya tiene otro articulo enlazado a este repuesto.', 16, 1);
        RETURN;
    END

    UPDATE ProveedorRepuesto SET IdRepuesto = @IdRepuesto WHERE Id = @IdListaProveedor;
END
GO


/* -----------------------------------------------------------------
   6. VISTA: todos los proveedores de cada repuesto, ordenados por costo
   Es lo que alimenta la comparacion en Reposicion sugerida.
   ----------------------------------------------------------------- */
IF OBJECT_ID('vw_RepuestoProveedores', 'V') IS NOT NULL DROP VIEW vw_RepuestoProveedores;
GO

CREATE VIEW vw_RepuestoProveedores AS
SELECT
    pr.IdRepuesto,
    pr.IdProveedor,
    p.RazonSocial       AS Proveedor,
    pr.CodigoProveedor,
    pr.Articulo,
    pr.PrecioLista,
    pr.DescuentoRubro,
    pr.DescuentoGeneral,
    pr.PrecioCompra,
    pr.FechaLista,
    ROW_NUMBER() OVER (PARTITION BY pr.IdRepuesto ORDER BY pr.PrecioCompra) AS Ranking
FROM ProveedorRepuesto pr
INNER JOIN Proveedor p ON p.Id = pr.IdProveedor
WHERE pr.IdRepuesto IS NOT NULL
  AND pr.Activo = 1
  AND pr.PrecioCompra > 0;
GO



/* -----------------------------------------------------------------
   VERIFICACION
   ----------------------------------------------------------------- */
SELECT c.name AS ColumnaProveedorRepuesto, t.name AS Tipo
FROM sys.columns c JOIN sys.types t ON t.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID('ProveedorRepuesto')
ORDER BY c.column_id;

SELECT name AS ObjetoCreado FROM sys.procedures
WHERE name IN ('SP_Proveedor_SugerirEnlaces', 'SP_Proveedor_EnlazarRepuesto')
UNION ALL
SELECT name FROM sys.views WHERE name = 'vw_RepuestoProveedores';

SELECT name AS IndiceRepuesto, is_unique, filter_definition
FROM sys.indexes WHERE object_id = OBJECT_ID('Repuesto');

SELECT COUNT(*) AS TotalRubros FROM Rubro;

SELECT c.name AS ColumnaNuevaEnRepuesto
FROM sys.columns c WHERE c.object_id = OBJECT_ID('Repuesto')
  AND c.name IN ('CodigoFabricante','MarcaFabricante','PrecioCompra','PrecioNetoVenta');
GO
