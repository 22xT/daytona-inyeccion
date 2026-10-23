USE [DaytonaInyeccion];
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   SPs de ProveedorRepuesto

   Faltaban: el script 09 creo la tabla y los SPs de sugerencia y
   enlace, pero no el de consulta que necesita el frontend.
   ================================================================= */

/* -----------------------------------------------------------------
   1. Articulos ENLAZADOS a un repuesto del catalogo propio

   Es lo que consume PedidoNuevo.html. El campo PrecioCompra es el
   costo real, ya con los descuentos del proveedor aplicados: la
   comparacion entre proveedores se hace sobre costos, no sobre
   precios de lista, que no dicen nada.

   Los nombres de columna coinciden con lo que espera el frontend:
   IdRepuesto, IdProveedor, PrecioCompra y Proveedor.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_ProveedorRepuesto_GetEnlazados', 'P') IS NOT NULL
    DROP PROCEDURE SP_ProveedorRepuesto_GetEnlazados;
GO

CREATE PROCEDURE SP_ProveedorRepuesto_GetEnlazados
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        pr.Id,
        pr.IdRepuesto,
        pr.IdProveedor,
        p.RazonSocial       AS Proveedor,
        pr.CodigoProveedor,
        pr.Articulo,
        pr.Descripcion,
        pr.PrecioLista,
        pr.DescuentoRubro,
        pr.DescuentoGeneral,
        pr.PrecioCompra,
        pr.FechaLista
    FROM ProveedorRepuesto pr
    INNER JOIN Proveedor p ON p.Id = pr.IdProveedor
    WHERE pr.IdRepuesto IS NOT NULL
      AND pr.Activo = 1
      AND pr.PrecioCompra > 0
    ORDER BY pr.IdRepuesto, pr.PrecioCompra;   -- el mas barato primero
END
GO


/* -----------------------------------------------------------------
   2. Busqueda dentro de la lista de un proveedor

   Con tope: son 53.188 articulos y devolverlos todos colgaria el
   navegador. El tope por defecto es 100.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_ProveedorRepuesto_Buscar', 'P') IS NOT NULL
    DROP PROCEDURE SP_ProveedorRepuesto_Buscar;
GO

CREATE PROCEDURE SP_ProveedorRepuesto_Buscar
    @IdProveedor    INT = NULL,
    @Texto          VARCHAR(100) = NULL,
    @SoloSinEnlazar BIT = 1,
    @Tope           INT = 100
AS
BEGIN
    SET NOCOUNT ON;

    IF @Tope IS NULL OR @Tope <= 0 SET @Tope = 100;
    IF @Tope > 500 SET @Tope = 500;

    SELECT TOP (@Tope)
        pr.Id,
        pr.IdProveedor,
        p.RazonSocial   AS Proveedor,
        pr.CodigoProveedor,
        pr.Articulo,
        pr.Descripcion,
        pr.RubroTexto,
        pr.MarcaTexto,
        pr.IdRubro,
        r.Nombre        AS Rubro,
        pr.PrecioLista,
        pr.DescuentoRubro,
        pr.DescuentoGeneral,
        pr.PrecioCompra,
        pr.IdRepuesto,
        CASE WHEN pr.IdRepuesto IS NULL THEN 0 ELSE 1 END AS YaEnCatalogo
    FROM ProveedorRepuesto pr
    INNER JOIN Proveedor p ON p.Id = pr.IdProveedor
    LEFT JOIN Rubro r ON r.Id = pr.IdRubro
    WHERE pr.Activo = 1
      AND (@IdProveedor IS NULL OR pr.IdProveedor = @IdProveedor)
      AND (@SoloSinEnlazar = 0 OR pr.IdRepuesto IS NULL)
      AND (@Texto IS NULL OR @Texto = ''
           OR pr.Descripcion LIKE '%' + @Texto + '%'
           OR pr.CodigoProveedor LIKE @Texto + '%'
           OR pr.Articulo LIKE @Texto + '%')
    ORDER BY pr.Descripcion;
END
GO


/* -----------------------------------------------------------------
   3. VERIFICACION
   ----------------------------------------------------------------- */
SELECT name AS Procedimiento FROM sys.procedures
WHERE name LIKE 'SP_ProveedorRepuesto%' OR name LIKE 'SP_Proveedor_%'
ORDER BY name;

-- Debe devolver la abrazadera incorporada, con su costo
EXEC SP_ProveedorRepuesto_GetEnlazados;

-- Prueba de busqueda
EXEC SP_ProveedorRepuesto_Buscar @Texto = 'abrazadera', @Tope = 5;
GO
