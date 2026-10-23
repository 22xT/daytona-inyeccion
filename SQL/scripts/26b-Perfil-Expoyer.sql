USE [DaytonaInyeccion]
GO

-- =====================================================
-- PERFIL DE IMPORTACION DE EXPOYER
-- Ejecutar TODO el archivo con F5, sin seleccionar nada.
-- Requiere que el proveedor Expoyer ya exista.
-- =====================================================

-- Columna para el segundo descuento fijo
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('PerfilImportacion') AND name = 'DescuentoFijo2')
    ALTER TABLE PerfilImportacion ADD DescuentoFijo2 DECIMAL(6,2) NOT NULL
        CONSTRAINT DF_Perfil_DtoFijo2 DEFAULT 0;
GO

-- El proveedor tiene que existir
IF NOT EXISTS (SELECT 1 FROM Proveedor WHERE RazonSocial LIKE '%EXPOYER%')
BEGIN
    RAISERROR('No existe el proveedor Expoyer. Cargalo desde la pantalla de Proveedores y volve a correr esto.', 16, 1);
    RETURN;
END
GO

-- Descuento del proveedor: 61,08 y despues 15, encadenados
UPDATE Proveedor SET DescuentoGeneral = 61.08 WHERE RazonSocial LIKE '%EXPOYER%';
GO

/*
   Columnas del archivo expoyer.txt:
     1 CODIGO   2 DESCR    3 NROORI   4 PRECIO   5 DESCR2
     6 CODPRO   7 ORIGEN   8 CANPED   9 FOTO    10 COEF
    11 CODRUB  12 MARCA   13 HOJA (marca de vehiculo)

   PRECIO es el precio de LISTA. El costo se calcula con los dos
   descuentos, que el archivo no trae y van fijos en el perfil.
*/
DECLARE @idExpoyer INT;
SELECT TOP 1 @idExpoyer = Id FROM Proveedor WHERE RazonSocial LIKE '%EXPOYER%';

IF NOT EXISTS (SELECT 1 FROM PerfilImportacion WHERE IdProveedor = @idExpoyer)
BEGIN
    INSERT INTO PerfilImportacion
        (IdProveedor, Nombre,
         ColCodigo, ColArticulo, ColRubro, ColMarca, ColDescripcion,
         ColPrecio, ColDescuento1, ColDescuento2, ColCosto,
         EsquemaCosto, DescuentoFijo, DescuentoFijo2, FilasEncabezado)
    VALUES
        (@idExpoyer, 'Expoyer - catalogo completo',
         1, 3, 11, 13, 2, 4, NULL, NULL, NULL,
         'DosDescuentos', 61.08, 15.00, 0);
END
ELSE
BEGIN
    UPDATE PerfilImportacion
    SET ColCodigo = 1, ColArticulo = 3, ColRubro = 11, ColMarca = 13,
        ColDescripcion = 2, ColPrecio = 4,
        ColDescuento1 = NULL, ColDescuento2 = NULL, ColCosto = NULL,
        EsquemaCosto = 'DosDescuentos',
        DescuentoFijo = 61.08, DescuentoFijo2 = 15.00, FilasEncabezado = 0
    WHERE IdProveedor = @idExpoyer;
END
GO

-- Verificacion
SELECT pv.Id AS IdProveedor, pv.RazonSocial, pv.Cuit,
       p.Nombre AS Perfil, p.EsquemaCosto,
       p.DescuentoFijo AS Dto1, p.DescuentoFijo2 AS Dto2,
       p.ColCodigo, p.ColDescripcion, p.ColPrecio, p.ColArticulo, p.ColMarca
FROM Proveedor pv
LEFT JOIN PerfilImportacion p ON p.IdProveedor = pv.Id
ORDER BY pv.Id;
GO
