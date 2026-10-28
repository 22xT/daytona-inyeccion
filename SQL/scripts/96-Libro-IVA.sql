/* =================================================================
   96 - LIBRO IVA VENTAS Y COMPRAS (Administracion, fase 5)

   Sale solo de lo que ya registra el sistema:
     VENTAS  : comprobantes AUTORIZADOS por ARCA (scripts 92 y 93).
               Los borradores no tienen validez fiscal y no entran.
               @IncluirPruebas = 1 suma los de homologacion, solo para
               probar la pantalla: nunca para presentar.
     COMPRAS : datos fiscales de las facturas y notas de proveedores
               (script 95).
   Se agrupa por la fecha del comprobante.

   La posicion de IVA del periodo (debito - credito - percepciones)
   es una estimacion para charlar con el contador: no incluye
   retenciones sufridas ni saldos a favor de periodos anteriores.

   Los archivos para importar en Libro IVA Digital de ARCA los arma la
   API con estos mismos datos.

   Requiere los scripts 92, 93 y 95. Se puede correr mas de una vez.
   Correr en local y en Azure.
   ================================================================= */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO


/* -----------------------------------------------------------------
   1. Ventas: comprobantes autorizados y su IVA por alicuota
      Signo: las notas de credito restan en los totales.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_LibroIva_Ventas', 'P') IS NOT NULL DROP PROCEDURE SP_LibroIva_Ventas;
GO
CREATE PROCEDURE SP_LibroIva_Ventas @Desde DATE, @Hasta DATE, @IncluirPruebas BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SELECT c.Id, c.Fecha, c.IdTipoComprobante AS TipoArca, t.Nombre AS Tipo, t.Clase,
           CASE WHEN t.Clase = 'NC' THEN -1 ELSE 1 END AS Signo,
           pv.Numero AS PuntoVenta, c.Numero,
           c.ReceptorDocTipo, c.ReceptorDocNumero, c.ReceptorNombre, c.ReceptorCondicionIva,
           c.ImporteNeto, c.ImporteNoGravado, c.ImporteExento, c.ImporteIva, c.ImporteTributos, c.ImporteTotal,
           c.Cae
    FROM Comprobante c
    INNER JOIN TipoComprobante t ON t.Id = c.IdTipoComprobante
    INNER JOIN PuntoVenta pv ON pv.Id = c.IdPuntoVenta
    WHERE c.Estado = 'AUTORIZADO' AND (pv.Entorno = 'PRODUCCION' OR (@IncluirPruebas = 1 AND pv.Entorno = 'HOMOLOGACION'))
      AND c.Fecha BETWEEN @Desde AND @Hasta
    ORDER BY c.Fecha, c.IdTipoComprobante, pv.Numero, c.Numero;

    SELECT i.IdComprobante, i.IdArcaIva, i.Porcentaje, i.BaseImponible, i.Importe
    FROM ComprobanteIva i
    INNER JOIN Comprobante c ON c.Id = i.IdComprobante
    INNER JOIN PuntoVenta pv ON pv.Id = c.IdPuntoVenta
    WHERE c.Estado = 'AUTORIZADO' AND (pv.Entorno = 'PRODUCCION' OR (@IncluirPruebas = 1 AND pv.Entorno = 'HOMOLOGACION'))
      AND c.Fecha BETWEEN @Desde AND @Hasta
    ORDER BY i.IdComprobante, i.IdArcaIva;
END
GO


/* -----------------------------------------------------------------
   2. Compras: comprobantes con datos fiscales y su IVA por alicuota
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_LibroIva_Compras', 'P') IS NOT NULL DROP PROCEDURE SP_LibroIva_Compras;
GO
CREATE PROCEDURE SP_LibroIva_Compras @Desde DATE, @Hasta DATE
AS
BEGIN
    SET NOCOUNT ON;
    SELECT cf.Id, cf.IdMovimiento, cf.Fecha, cf.TipoArca,
           CASE WHEN cf.TipoArca IN (3, 8, 13) THEN 'NC' WHEN cf.TipoArca IN (2, 7, 12) THEN 'ND' ELSE 'FC' END AS Clase,
           CASE WHEN cf.TipoArca IN (3, 8, 13) THEN -1 ELSE 1 END AS Signo,
           CASE WHEN cf.TipoArca IN (1, 2, 3) THEN 'A' WHEN cf.TipoArca IN (6, 7, 8) THEN 'B' ELSE 'C' END AS Letra,
           cf.PuntoVenta, cf.Numero, cf.IdProveedor, p.RazonSocial AS Proveedor, p.Cuit AS CuitProveedor,
           cf.ImporteNeto, cf.ImporteIva, cf.ImporteNoGravado, cf.ImporteExento, cf.PercepcionIva, cf.PercepcionIibb,
           cf.ImpuestosInternos, cf.OtrosTributos, cf.ImporteTotal, cf.Cae, cf.Constatado,
           -- Solo la A da credito fiscal
           CASE WHEN cf.TipoArca IN (1, 2, 3) THEN cf.ImporteIva ELSE 0 END AS CreditoFiscal
    FROM CompraFiscal cf
    INNER JOIN Proveedor p ON p.Id = cf.IdProveedor
    WHERE cf.Fecha BETWEEN @Desde AND @Hasta
    ORDER BY cf.Fecha, p.RazonSocial, cf.PuntoVenta, cf.Numero;

    SELECT i.IdCompraFiscal, i.IdArcaIva, i.BaseImponible, i.Importe
    FROM CompraFiscalIva i
    INNER JOIN CompraFiscal cf ON cf.Id = i.IdCompraFiscal
    WHERE cf.Fecha BETWEEN @Desde AND @Hasta
    ORDER BY i.IdCompraFiscal, i.IdArcaIva;
END
GO


/* -----------------------------------------------------------------
   3. Lo que falta para que el libro este completo
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_LibroIva_Faltantes', 'P') IS NOT NULL DROP PROCEDURE SP_LibroIva_Faltantes;
GO
CREATE PROCEDURE SP_LibroIva_Faltantes @Desde DATE, @Hasta DATE, @IncluirPruebas BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    -- Ventas: comprobantes del periodo que no estan autorizados en produccion
    SELECT c.Id, c.Fecha, t.Nombre AS Tipo, c.Estado, pv.Entorno, c.ReceptorNombre, c.ImporteTotal
    FROM Comprobante c
    INNER JOIN TipoComprobante t ON t.Id = c.IdTipoComprobante
    INNER JOIN PuntoVenta pv ON pv.Id = c.IdPuntoVenta
    WHERE c.Fecha BETWEEN @Desde AND @Hasta
      AND c.Estado <> 'ANULADO'
      AND NOT (c.Estado = 'AUTORIZADO' AND (pv.Entorno = 'PRODUCCION' OR (@IncluirPruebas = 1 AND pv.Entorno = 'HOMOLOGACION')))
    ORDER BY c.Fecha, c.Id;

    -- Compras: facturas y notas del periodo sin datos fiscales
    -- (los presupuestos y remitos no son comprobantes fiscales)
    SELECT m.Id AS IdMovimiento, m.IdProveedor, p.RazonSocial AS Proveedor, m.Tipo,
           COALESCE(rp.TipoComprobante + ' ' + rp.NumeroComprobante, m.Descripcion) AS Documento,
           COALESCE(rp.FechaComprobante, nc.Fecha, CAST(m.Fecha AS DATE)) AS FechaDoc, ABS(m.Monto) AS Importe
    FROM MovimientoCtaCteProveedor m
    INNER JOIN Proveedor p ON p.Id = m.IdProveedor
    LEFT JOIN RecepcionPedido rp ON rp.Id = m.IdRecepcion
    LEFT JOIN NotaCreditoProveedor nc ON nc.Id = m.IdNotaCredito
    LEFT JOIN CompraFiscal cf ON cf.IdMovimiento = m.Id
    WHERE cf.Id IS NULL
      AND m.Tipo IN ('COMPRA', 'ND', 'NC')
      AND ISNULL(rp.Anulada, 0) = 0
      AND ISNULL(rp.TipoComprobante, 'Factura') NOT IN ('Presupuesto', 'Remito')
      AND ISNULL(p.CondicionIva, '') <> 'Consumidor Final'
      AND COALESCE(rp.FechaComprobante, nc.Fecha, CAST(m.Fecha AS DATE)) BETWEEN @Desde AND @Hasta
    ORDER BY p.RazonSocial, FechaDoc;
END
GO


/* -----------------------------------------------------------------
   CONTROL
   ----------------------------------------------------------------- */
SELECT name FROM sys.procedures
WHERE name IN ('SP_LibroIva_Ventas', 'SP_LibroIva_Compras', 'SP_LibroIva_Faltantes')
ORDER BY name;   -- tienen que ser 3
GO
