USE [DaytonaInyeccion]
GO

/* =================================================================
   27 — CARGA DE EXPOYER

   PROBLEMA: StgImportacion tiene una columna Fila con IDENTITY, y
   BULK INSERT mapea los campos del archivo en orden contra TODAS las
   columnas de la tabla. El primer campo del archivo iba a parar a
   Fila, que es un int autonumerico, y fallaba la conversion.

   SOLUCION: cargar a traves de una vista que expone solo Col1..Col20.
   BULK INSERT respeta las columnas de la vista y la identity se
   genera sola.
   ================================================================= */

IF OBJECT_ID('vw_StgImportacion', 'V') IS NOT NULL DROP VIEW vw_StgImportacion;
GO

CREATE VIEW vw_StgImportacion AS
SELECT Col1, Col2, Col3, Col4, Col5, Col6, Col7, Col8, Col9, Col10,
       Col11, Col12, Col13, Col14, Col15, Col16, Col17, Col18, Col19, Col20
FROM StgImportacion;
GO


-- =====================================================
-- CARGA
-- =====================================================
TRUNCATE TABLE StgImportacion;
GO

BULK INSERT vw_StgImportacion
FROM 'C:\Temp\expoyer.txt'
WITH (
    DATAFILETYPE    = 'widechar',
    FIELDTERMINATOR = '|',
    ROWTERMINATOR   = '0x0a00',
    TABLOCK
);
GO

SELECT COUNT(*) AS FilasImportadas FROM StgImportacion;   -- 103109
GO


-- =====================================================
-- CONTROL antes de procesar
-- Tiene que dar: Col4 = 82691,00 y CostoEsperado = 27355,84
-- =====================================================
SELECT Col1 AS Codigo, Col2 AS Descripcion, Col3 AS NroOriginal,
       Col4 AS PrecioLista, Col11 AS CodRubro, Col13 AS Hoja,
       CAST(TRY_CAST(Col4 AS DECIMAL(12,2)) * (1 - 61.08/100.0) * (1 - 15.0/100.0)
            AS DECIMAL(12,2)) AS CostoEsperado
FROM StgImportacion
WHERE Col1 = 'CD1025572';
GO

-- Muestra general
SELECT TOP 5 Col1, Col2, Col4, Col13 FROM StgImportacion;
GO


-- =====================================================
-- VISTA PREVIA (no escribe nada)
-- =====================================================
DECLARE @p INT;
SELECT TOP 1 @p = Id FROM Proveedor WHERE RazonSocial LIKE '%EXPOYER%';
EXEC SP_Importacion_Procesar @IdProveedor = @p, @SoloVistaPrevia = 1;
GO


-- =====================================================
-- PROCESAR — recien cuando el control de arriba coincida
-- =====================================================
/*
DECLARE @p INT;
SELECT TOP 1 @p = Id FROM Proveedor WHERE RazonSocial LIKE '%EXPOYER%';
EXEC SP_Importacion_Procesar @IdProveedor = @p, @FechaLista = '2026-09-08';
GO

-- Reprocesar el texto de busqueda de los articulos nuevos.
-- Con 103.109 filas mas puede tardar varios minutos.
EXEC SP_Busqueda_Reprocesar @SoloNuevos = 1;
GO

-- Estado final
SELECT p.RazonSocial, COUNT(*) AS Articulos,
       SUM(CASE WHEN pr.IdRepuesto IS NOT NULL THEN 1 ELSE 0 END) AS Enlazados
FROM ProveedorRepuesto pr
INNER JOIN Proveedor p ON p.Id = pr.IdProveedor
WHERE pr.Activo = 1
GROUP BY p.RazonSocial;
GO

-- La primera comparacion real entre dos proveedores
EXEC SP_Busqueda_Universal @Texto = 'kit distribucion suran';
GO
*/
