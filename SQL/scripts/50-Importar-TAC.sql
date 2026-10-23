USE [DaytonaInyeccion]
GO

/* =================================================================
   50 — LISTA DE PRECIOS DE TAC

   El archivo original (ListaDePrecios.xls) no se puede importar tal
   cual: 2.065 descripciones tienen saltos de linea dentro de la celda,
   463 superan los 250 caracteres y 20 articulos tienen precio cero.
   tac.txt ya viene limpio, en el formato del importador:
     UTF-16, campos separados por |, 20 columnas, sin encabezado.
     1 Codigo · 2 Descripcion · 3 Precio de lista · 4 Marca (detectada)

   ANTES DE CORRER
   1. TAC tiene que estar dado de alta como proveedor.
   2. Copiar tac.txt a C:\Temp\
   3. Revisar @Descuento de la seccion 1.
   ================================================================= */


/* -----------------------------------------------------------------
   1. Perfil de TAC
   Si TAC te hace un descuento sobre la lista, ponelo en @Descuento:
   el costo se calcula como precio de lista x (1 - descuento).
   Si la lista ya es tu costo, dejalo en 0.
   ----------------------------------------------------------------- */
DECLARE @Descuento DECIMAL(6,2) = 0;     -- <<< revisar

DECLARE @IdTac INT = (SELECT TOP 1 Id FROM Proveedor WHERE UPPER(LTRIM(RTRIM(RazonSocial))) LIKE 'TAC%' ORDER BY Id);
IF @IdTac IS NULL
BEGIN
    RAISERROR('No encuentro a TAC entre los proveedores. Dalo de alta primero.', 16, 1);
    SET NOEXEC ON;
END

IF NOT EXISTS (SELECT 1 FROM PerfilImportacion WHERE IdProveedor = @IdTac)
    INSERT INTO PerfilImportacion
        (IdProveedor, Nombre, ColCodigo, ColArticulo, ColRubro, ColMarca, ColDescripcion, ColPrecio,
         ColDescuento1, ColDescuento2, ColCosto, EsquemaCosto, DescuentoFijo, FilasEncabezado)
    VALUES
        (@IdTac, 'TAC — lista de precios', 1, NULL, NULL, 4, 2, 3,
         NULL, NULL, NULL, CASE WHEN @Descuento > 0 THEN 'UnDescuento' ELSE 'CostoDirecto' END, @Descuento, 0);
ELSE
    UPDATE PerfilImportacion
    SET EsquemaCosto = CASE WHEN @Descuento > 0 THEN 'UnDescuento' ELSE 'CostoDirecto' END,
        DescuentoFijo = @Descuento
    WHERE IdProveedor = @IdTac;

SELECT pr.RazonSocial, p.Nombre, p.EsquemaCosto, p.DescuentoFijo FROM PerfilImportacion p
INNER JOIN Proveedor pr ON pr.Id = p.IdProveedor WHERE p.IdProveedor = @IdTac;
GO


/* -----------------------------------------------------------------
   2. Carga del archivo
   ----------------------------------------------------------------- */
TRUNCATE TABLE StgImportacion;
GO

BULK INSERT vw_StgImportacion
FROM 'C:\Temp\tac.txt'
WITH (
    DATAFILETYPE    = 'widechar',
    FIELDTERMINATOR = '|',
    ROWTERMINATOR   = '0x0a00',
    TABLOCK
);
GO

SELECT COUNT(*) AS FilasImportadas FROM StgImportacion;   -- tiene que dar 5742
GO


/* -----------------------------------------------------------------
   3. Vista previa: no escribe nada
   SinCodigo, PrecioNoNumerico y SinCosto tienen que dar 0.
   ----------------------------------------------------------------- */
DECLARE @IdTac INT = (SELECT TOP 1 Id FROM Proveedor WHERE UPPER(LTRIM(RTRIM(RazonSocial))) LIKE 'TAC%' ORDER BY Id);
EXEC SP_Importacion_Procesar @IdProveedor = @IdTac, @SoloVistaPrevia = 1;
GO


/* -----------------------------------------------------------------
   4. IMPORTAR — descomentar cuando la vista previa este bien
   ----------------------------------------------------------------- */
/*
DECLARE @IdTac INT = (SELECT TOP 1 Id FROM Proveedor WHERE UPPER(LTRIM(RTRIM(RazonSocial))) LIKE 'TAC%' ORDER BY Id);
EXEC SP_Importacion_Procesar @IdProveedor = @IdTac;      -- tiene que dar Nuevos = 5742

-- Texto de busqueda y codigos sin guiones, para que el buscador los encuentre
EXEC SP_Busqueda_Reprocesar @SoloNuevos = 1;

UPDATE ProveedorRepuesto
SET CodigosBusqueda = ' ' + dbo.fn_LimpiarCodigo(ISNULL(CodigoProveedor, '')) +
                      ' ' + dbo.fn_LimpiarCodigo(ISNULL(Articulo, '')) + ' '
WHERE IdProveedor = @IdTac AND CodigosBusqueda IS NULL;

SELECT COUNT(*) AS ArticulosTAC, MIN(PrecioCompra) AS CostoMin, MAX(PrecioCompra) AS CostoMax
FROM ProveedorRepuesto WHERE IdProveedor = @IdTac AND Activo = 1;
*/
GO

SET NOEXEC OFF;
GO
