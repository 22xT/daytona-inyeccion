USE [DaytonaInyeccion]
GO

/* =================================================================
   72 — REPUESTOS QUE ENTRARON CON MINIMO 5 SIN QUERERLO

   Al vincular, pedir o encargar desde el Buscador, el articulo se
   suma al catalogo. Se sumaba con stock minimo 5 (el valor por
   defecto), y entonces la reposicion sugerida lo pedia solo.
   Desde ahora entran con minimo 0.

   Este script NO cambia nada solo:
   1. Lista los repuestos con minimo 5 que nunca tuvieron stock ni
      ventas: son los candidatos a haber entrado asi.
   2. Revisá la lista. Si estan todos bien, corré el UPDATE de abajo
      (seleccionalo y F5). Los que si querés tener, cambiales el
      minimo desde Repuestos > Stock.
   ================================================================= */

SELECT r.Id, r.Codigo, r.Descripcion, r.MarcaFabricante, s.Cantidad AS Stock, s.StockMinimo
FROM Repuesto r
INNER JOIN Stock s ON s.IdRepuesto = r.Id
WHERE r.Activo = 1
  AND s.StockMinimo = 5
  AND s.Cantidad = 0
  AND NOT EXISTS (SELECT 1 FROM DetalleVenta dv WHERE dv.IdRepuesto = r.Id)
ORDER BY r.Id DESC;
GO

/*
UPDATE s SET s.StockMinimo = 0
FROM Stock s
INNER JOIN Repuesto r ON r.Id = s.IdRepuesto
WHERE r.Activo = 1
  AND s.StockMinimo = 5
  AND s.Cantidad = 0
  AND NOT EXISTS (SELECT 1 FROM DetalleVenta dv WHERE dv.IdRepuesto = r.Id);
*/
