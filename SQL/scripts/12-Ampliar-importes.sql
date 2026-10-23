USE [DaytonaInyeccion];
GO

/* =================================================================
   AMPLIAR COLUMNAS DE IMPORTE

   Criterio: se amplian los importes que ACUMULAN, no los unitarios.

   - Un precio unitario de mas de $99.999.999 no existe: el repuesto
     mas caro de la lista de Autocor esta en $2.878.451. Quedan en
     DECIMAL(10,2).
   - Un TOTAL o un SUBTOTAL si puede crecer: es cantidad por precio,
     y ademas los saldos acumulan con el tiempo. Van a DECIMAL(12,2).
   - Los porcentajes (MargenPropio, PorcentajeDescuento) son
     DECIMAL(6,2) a proposito: 9999,99% de tope es mas que suficiente.
   ================================================================= */

/* -----------------------------------------------------------------
   1. Confirmar si Venta.Total ya se amplio
   ----------------------------------------------------------------- */
SELECT name AS Columna, precision, scale,
       CASE WHEN precision >= 12 THEN 'YA AMPLIADA' ELSE 'FALTA' END AS Estado
FROM sys.columns
WHERE object_id = OBJECT_ID('Venta') AND name = 'Total';
GO


/* -----------------------------------------------------------------
   2. Chequear que no haya indices ni constraints encima
   Si esto devuelve filas, avisar ANTES de correr los ALTER:
   hay que sacarlas primero y volver a crearlas despues.
   ----------------------------------------------------------------- */
SELECT OBJECT_NAME(i.object_id) AS Tabla, i.name AS Indice, c.name AS Columna
FROM sys.indexes i
JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns c ON c.object_id = i.object_id AND c.column_id = ic.column_id
WHERE c.name IN ('Total', 'Subtotal')
  AND OBJECT_NAME(i.object_id) IN ('Venta', 'Pedido', 'DetalleVenta', 'DetallePedido');

SELECT OBJECT_NAME(parent_object_id) AS Tabla, name AS Constraint_, definition
FROM sys.check_constraints
WHERE OBJECT_NAME(parent_object_id) IN ('Venta', 'Pedido', 'DetalleVenta', 'DetallePedido');
GO


/* -----------------------------------------------------------------
   3. Los ALTER
   Correr solo si el paso 2 no devolvio nada sobre esas columnas.
   ----------------------------------------------------------------- */

-- Solo si el paso 1 dijo FALTA
-- ALTER TABLE Venta ALTER COLUMN Total DECIMAL(12,2) NOT NULL;
-- GO

ALTER TABLE DetalleVenta ALTER COLUMN Subtotal DECIMAL(12,2) NOT NULL;
GO

ALTER TABLE Pedido ALTER COLUMN Total DECIMAL(12,2) NULL;
GO


/* -----------------------------------------------------------------
   4. El CAST del SP de precios tambien queda corto

   SP_Repuesto_AplicarPrecio castea a DECIMAL(10,2) al escribir
   PrecioDeVenta. Con precios normales no molesta, pero si algun dia
   se aplica un precio muy alto tira overflow en vez de un mensaje.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Repuesto_AplicarPrecio', 'P') IS NOT NULL
BEGIN
    EXEC('
    ALTER PROCEDURE SP_Repuesto_AplicarPrecio
        @IdRepuesto      INT,
        @PrecioNetoVenta DECIMAL(12,2)
    AS
    BEGIN
        SET NOCOUNT ON;

        IF NOT EXISTS (SELECT 1 FROM Repuesto WHERE Id = @IdRepuesto)
        BEGIN
            RAISERROR(''El repuesto indicado no existe.'', 16, 1);
            RETURN;
        END

        IF @PrecioNetoVenta IS NULL OR @PrecioNetoVenta <= 0
        BEGIN
            RAISERROR(''El precio neto debe ser mayor a cero.'', 16, 1);
            RETURN;
        END

        IF @PrecioNetoVenta > 99000000
        BEGIN
            RAISERROR(''El precio es demasiado alto.'', 16, 1);
            RETURN;
        END

        DECLARE @alicuota DECIMAL(5,2);
        SELECT @alicuota = ISNULL(a.Porcentaje, 21)
        FROM Repuesto r LEFT JOIN AlicuotaIva a ON a.Id = r.IdAlicuotaIva
        WHERE r.Id = @IdRepuesto;

        UPDATE Repuesto
        SET PrecioNetoVenta = @PrecioNetoVenta,
            PrecioDeVenta   = CAST(@PrecioNetoVenta * (1 + @alicuota / 100.0) AS DECIMAL(10,2))
        WHERE Id = @IdRepuesto;
    END');
    PRINT 'SP_Repuesto_AplicarPrecio actualizado.';
END
GO


/* -----------------------------------------------------------------
   5. VERIFICACION
   ----------------------------------------------------------------- */
SELECT OBJECT_NAME(c.object_id) AS Tabla, c.name AS Columna, c.precision, c.scale
FROM sys.columns c
JOIN sys.types t ON t.user_type_id = c.user_type_id
WHERE t.name = 'decimal'
  AND OBJECT_NAME(c.object_id) IN ('Venta','DetalleVenta','Pedido','DetallePedido','Repuesto')
  AND c.name IN ('Total','Subtotal','PrecioUnitario','PrecioDeVenta','PrecioCompra','PrecioNetoVenta')
ORDER BY Tabla, Columna;
GO
