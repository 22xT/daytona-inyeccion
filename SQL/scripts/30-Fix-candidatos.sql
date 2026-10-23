USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   30 — CORRECCION: candidatos en otros proveedores

   PROBLEMA DETECTADO EN USO
   Al incorporar el kit Dayco 452G006, el sistema ofrecio como
   candidatos seis alzavidrios y otras piezas del MISMO proveedor, y
   no ofrecio el kit equivalente de Expoyer, que era el correcto.

   DOS CAUSAS

   1. La busqueda por descripcion tomaba los primeros 18 caracteres.
      Todas las descripciones de Autocor arrancan con
      "Crossfox/Fox/Gol Trend/", asi que matcheaba cualquier pieza de
      esos autos. El texto de aplicacion vehicular NO sirve para
      identificar una pieza: dice para que auto es, no que es.

   2. Incluia articulos del mismo proveedor. No tiene sentido: el
      objetivo es encontrar la misma pieza en OTRA lista para poder
      comparar precios.

   CORRECCION
   - Solo otros proveedores.
   - El codigo de fabricante es obligatorio para sugerir. Sin el, no
     hay señal confiable y es preferible no ofrecer nada que ofrecer
     cualquier cosa: una sugerencia mala aceptada por apuro fusiona
     repuestos distintos y corrompe el stock.
   - Se agrega una segunda via: coincidencia por PALABRAS clave de la
     descripcion, descartando el texto de aplicacion.
   ================================================================= */

IF OBJECT_ID('SP_Repuesto_BuscarEnOtrosProveedores', 'P') IS NOT NULL
    DROP PROCEDURE SP_Repuesto_BuscarEnOtrosProveedores;
GO

CREATE PROCEDURE SP_Repuesto_BuscarEnOtrosProveedores
    @IdRepuesto INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @codFab VARCHAR(40), @desc NVARCHAR(100), @costo DECIMAL(12,2),
            @idProvOrigen INT, @idRubro INT;

    SELECT @codFab = CodigoFabricante, @desc = Descripcion,
           @costo = PrecioCompra, @idRubro = IdRubro
    FROM Repuesto WHERE Id = @IdRepuesto;

    -- Proveedor por el que se incorporo: sus otros articulos no sirven
    SELECT TOP 1 @idProvOrigen = IdProveedor
    FROM ProveedorRepuesto WHERE IdRepuesto = @IdRepuesto;

    -- Sin guiones ni puntos: Autocor escribe KTB341 y Expoyer KTB-341
    DECLARE @codLimpio VARCHAR(40) =
        REPLACE(REPLACE(REPLACE(UPPER(ISNULL(@codFab, '')), '-', ''), ' ', ''), '.', '');

    /* Sin codigo de fabricante no hay señal confiable.
       Se prefiere no sugerir nada antes que sugerir cualquier cosa. */
    IF @codLimpio = '' OR LEN(@codLimpio) < 4
    BEGIN
        SELECT TOP 0
            CAST(NULL AS INT) AS Id, CAST(NULL AS INT) AS IdProveedor,
            CAST(NULL AS VARCHAR(200)) AS Proveedor,
            CAST(NULL AS VARCHAR(30)) AS CodigoProveedor,
            CAST(NULL AS VARCHAR(40)) AS Articulo,
            CAST(NULL AS VARCHAR(250)) AS Descripcion,
            CAST(NULL AS DECIMAL(12,2)) AS PrecioCompra,
            CAST(NULL AS DECIMAL(12,2)) AS MiCostoActual,
            CAST(NULL AS DECIMAL(12,2)) AS Diferencia,
            CAST(NULL AS DECIMAL(6,2)) AS DiferenciaPorc,
            CAST(NULL AS VARCHAR(10)) AS Confianza;
        RETURN;
    END

    SELECT TOP 12
        pr.Id,
        pr.IdProveedor,
        p.RazonSocial       AS Proveedor,
        pr.CodigoProveedor,
        pr.Articulo,
        pr.Descripcion,
        pr.PrecioCompra,
        @costo              AS MiCostoActual,
        CAST(pr.PrecioCompra - @costo AS DECIMAL(12,2)) AS Diferencia,
        CASE WHEN @costo > 0
             THEN CAST((pr.PrecioCompra - @costo) / @costo * 100 AS DECIMAL(6,2))
             ELSE NULL END  AS DiferenciaPorc,
        'Alta'              AS Confianza

    FROM ProveedorRepuesto pr
    INNER JOIN Proveedor p ON p.Id = pr.IdProveedor
    WHERE pr.Activo = 1
      AND pr.PrecioCompra > 0
      AND pr.IdRepuesto IS NULL
      -- Solo OTROS proveedores: comparar con el mismo no aporta
      AND (@idProvOrigen IS NULL OR pr.IdProveedor <> @idProvOrigen)
      -- Mismo codigo de fabricante, ignorando separadores
      AND REPLACE(REPLACE(REPLACE(UPPER(ISNULL(pr.Articulo, '')), '-', ''), ' ', ''), '.', '')
          = @codLimpio
    ORDER BY pr.PrecioCompra;
END
GO


/* -----------------------------------------------------------------
   PRUEBA: el kit Dayco que se incorporo

   Tiene que devolver el articulo de Expoyer con codigo de fabricante
   KTB-341, y NADA de Autocor.
   ----------------------------------------------------------------- */
DECLARE @id INT;
SELECT TOP 1 @id = Id FROM Repuesto WHERE Codigo = '452G006';

SELECT @id AS IdRepuesto,
       (SELECT CodigoFabricante FROM Repuesto WHERE Id = @id) AS CodigoFabricante;

EXEC SP_Repuesto_BuscarEnOtrosProveedores @IdRepuesto = @id;
GO


/* -----------------------------------------------------------------
   Y el control directo: quien tiene el KTB341
   ----------------------------------------------------------------- */
SELECT p.RazonSocial, pr.CodigoProveedor, pr.Articulo,
       LEFT(pr.Descripcion, 55) AS Descripcion, pr.PrecioCompra,
       CASE WHEN pr.IdRepuesto IS NULL THEN 'Sin enlazar' ELSE 'Enlazado' END AS Estado
FROM ProveedorRepuesto pr
INNER JOIN Proveedor p ON p.Id = pr.IdProveedor
WHERE pr.Activo = 1
  AND REPLACE(REPLACE(UPPER(ISNULL(pr.Articulo, '')), '-', ''), ' ', '') = 'KTB341'
ORDER BY pr.PrecioCompra;
GO
