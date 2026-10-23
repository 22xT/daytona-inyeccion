USE [DaytonaInyeccion];
GO

/* =================================================================
   LISTAS DE PRECIOS DE PROVEEDOR

   La lista del proveedor vive SEPARADA de tu catalogo. Son 53.188
   articulos de Autocor: no son tus repuestos, son lo que Autocor
   ofrece. Tu catalogo (Repuesto) sigue teniendo solo lo que
   realmente vendes, y se enlaza con la lista cuando corresponde.

   Cadena de precios confirmada contra el catalogo web de Autocor:

     Costo = Lista x (1 - DtoRubro) x (1 - DtoGeneral)
     Venta = Costo x (1 + Utilidad) x (1 + Impuestos) x (1 + IVA)

   Los descuentos se encadenan, NO se suman. 5% y 19% dan 22,95%
   de descuento efectivo, no 24%.
   ================================================================= */

/* -----------------------------------------------------------------
   1. El proveedor tiene que existir
   ----------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM Proveedor WHERE RazonSocial LIKE '%AUTOCOR%')
BEGIN
    RAISERROR('No existe un proveedor con AUTOCOR en la razon social. Cargalo desde el sistema y volve a correr esto.', 16, 1);
    RETURN;
END
GO

SELECT Id, RazonSocial FROM Proveedor WHERE RazonSocial LIKE '%AUTOCOR%';
GO


/* -----------------------------------------------------------------
   2. Descuento general del proveedor
   El de la lista es 19% y esta en las 53.188 filas. Se guarda
   igual en el proveedor porque hace falta para los pedidos
   manuales, donde no hay lista de por medio.
   ----------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('Proveedor') AND name = 'DescuentoGeneral')
    ALTER TABLE Proveedor ADD DescuentoGeneral DECIMAL(6,2) NOT NULL
        CONSTRAINT DF_Proveedor_DtoGral DEFAULT 0;
GO


/* -----------------------------------------------------------------
   3. Catalogo del proveedor
   ----------------------------------------------------------------- */
IF OBJECT_ID('ProveedorRepuesto', 'U') IS NULL
BEGIN
    CREATE TABLE ProveedorRepuesto (
        Id                INT IDENTITY(1,1) PRIMARY KEY,
        IdProveedor       INT           NOT NULL,

        CodigoProveedor   VARCHAR(30)   NOT NULL,   -- el "Codigo" de la lista
        Articulo          VARCHAR(40)   NULL,       -- codigo del fabricante
        RubroTexto        VARCHAR(80)   NULL,       -- como viene en la lista
        MarcaTexto        VARCHAR(40)   NULL,
        Descripcion       VARCHAR(250)  NOT NULL,

        PrecioLista       DECIMAL(12,2) NOT NULL,
        DescuentoRubro    DECIMAL(6,2)  NOT NULL DEFAULT 0,
        DescuentoGeneral  DECIMAL(6,2)  NOT NULL DEFAULT 0,
        PrecioCompra      DECIMAL(12,2) NOT NULL,   -- costo real, ya con descuentos

        IdRubro           INT           NULL,       -- rubro tuyo, si matcheo
        IdRepuesto        INT           NULL,       -- se llena al incorporarlo

        FechaLista        DATE          NOT NULL,
        Activo            BIT           NOT NULL DEFAULT 1,

        CONSTRAINT FK_ProvRep_Proveedor FOREIGN KEY (IdProveedor) REFERENCES Proveedor(Id),
        CONSTRAINT FK_ProvRep_Rubro     FOREIGN KEY (IdRubro)     REFERENCES Rubro(Id),
        CONSTRAINT FK_ProvRep_Repuesto  FOREIGN KEY (IdRepuesto)  REFERENCES Repuesto(Id),
        CONSTRAINT UQ_ProvRep UNIQUE (IdProveedor, CodigoProveedor)
    );

    CREATE INDEX IX_ProvRep_Repuesto   ON ProveedorRepuesto(IdRepuesto);
    CREATE INDEX IX_ProvRep_Rubro      ON ProveedorRepuesto(IdRubro);
    CREATE INDEX IX_ProvRep_Desc       ON ProveedorRepuesto(Descripcion);
END
GO


/* -----------------------------------------------------------------
   4. Tabla de paso: todo VARCHAR
   Si algo viene mal formado, el BULK INSERT no falla; se ve despues.
   ----------------------------------------------------------------- */
IF OBJECT_ID('StgListaProveedor', 'U') IS NOT NULL DROP TABLE StgListaProveedor;
GO

CREATE TABLE StgListaProveedor (
    Codigo       VARCHAR(50),
    Articulo     VARCHAR(60),
    Rubro        VARCHAR(120),
    Marca        VARCHAR(60),
    Descripcion  VARCHAR(300),
    Precio       VARCHAR(30),
    Descuento    VARCHAR(20),
    DescExtra    VARCHAR(20),
    PrecioNeto   VARCHAR(30)
);
GO


/* -----------------------------------------------------------------
   5. BULK INSERT

   CAMBIAR LA RUTA. Tiene que ser una carpeta que pueda leer el
   SERVICIO de SQL Server, no tu usuario de Windows. Si SQL corre
   en la misma maquina, C:\Temp\ anda bien.

   Si da error de terminador de fila, probar con
   ROWTERMINATOR = '0x0a00' en vez de '\n'.
   ----------------------------------------------------------------- */
BULK INSERT StgListaProveedor
FROM 'C:\Temp\lista_proveedor.txt'
WITH (
    DATAFILETYPE    = 'widechar',   -- UTF-16: SQL 2014 no soporta UTF-8 aca
    FIELDTERMINATOR = '|',
    ROWTERMINATOR   = '\n',
    TABLOCK
);
GO

SELECT COUNT(*) AS FilasImportadas FROM StgListaProveedor;
SELECT TOP 5 * FROM StgListaProveedor;
GO


/* -----------------------------------------------------------------
   6. Volcado a la tabla definitiva

   El matcheo de rubro normaliza espacios: la lista trae
   'BULBO  ELECTROVENTILADOR "MD"' con dos espacios y tu base tiene
   uno solo. Sin normalizar, no matchea ninguno de esos.
   ----------------------------------------------------------------- */
DECLARE @IdProveedor INT, @FechaLista DATE = '2026-09-01';
SELECT TOP 1 @IdProveedor = Id FROM Proveedor WHERE RazonSocial LIKE '%AUTOCOR%';

-- Se reemplaza la lista anterior de este proveedor.
-- Los que ya estan enlazados a un repuesto NO se borran: se actualizan,
-- para no perder el vinculo con tu catalogo.
UPDATE pr
SET pr.PrecioLista      = TRY_CAST(s.Precio AS DECIMAL(12,2)),
    pr.DescuentoRubro   = TRY_CAST(s.Descuento AS DECIMAL(6,2)),
    pr.DescuentoGeneral = TRY_CAST(s.DescExtra AS DECIMAL(6,2)),
    pr.PrecioCompra     = TRY_CAST(s.PrecioNeto AS DECIMAL(12,2)),
    pr.Descripcion      = s.Descripcion,
    pr.FechaLista       = @FechaLista,
    pr.Activo           = 1
FROM ProveedorRepuesto pr
INNER JOIN StgListaProveedor s ON s.Codigo = pr.CodigoProveedor
WHERE pr.IdProveedor = @IdProveedor;

-- Los que ya no vienen en la lista quedan inactivos, no se borran:
-- puede haber ventas historicas apuntando a ellos.
UPDATE ProveedorRepuesto
SET Activo = 0
WHERE IdProveedor = @IdProveedor
  AND CodigoProveedor NOT IN (SELECT Codigo FROM StgListaProveedor);

-- Altas
INSERT INTO ProveedorRepuesto
    (IdProveedor, CodigoProveedor, Articulo, RubroTexto, MarcaTexto, Descripcion,
     PrecioLista, DescuentoRubro, DescuentoGeneral, PrecioCompra, IdRubro, FechaLista)
SELECT
    @IdProveedor,
    s.Codigo,
    s.Articulo,
    s.Rubro,
    s.Marca,
    s.Descripcion,
    TRY_CAST(s.Precio     AS DECIMAL(12,2)),
    TRY_CAST(s.Descuento  AS DECIMAL(6,2)),
    TRY_CAST(s.DescExtra  AS DECIMAL(6,2)),
    TRY_CAST(s.PrecioNeto AS DECIMAL(12,2)),
    r.Id,
    @FechaLista
FROM StgListaProveedor s
LEFT JOIN Rubro r
    ON UPPER(LTRIM(RTRIM(
         REPLACE(REPLACE(REPLACE(r.Nombre, '   ', ' '), '  ', ' '), '  ', ' ')
       )))
     = UPPER(LTRIM(RTRIM(
         REPLACE(REPLACE(REPLACE(s.Rubro,  '   ', ' '), '  ', ' '), '  ', ' ')
       )))
WHERE NOT EXISTS (
    SELECT 1 FROM ProveedorRepuesto pr
    WHERE pr.IdProveedor = @IdProveedor AND pr.CodigoProveedor = s.Codigo
);

-- El descuento general del proveedor sale de la propia lista
UPDATE Proveedor
SET DescuentoGeneral = (SELECT TOP 1 TRY_CAST(DescExtra AS DECIMAL(6,2))
                        FROM StgListaProveedor)
WHERE Id = @IdProveedor;
GO


/* -----------------------------------------------------------------
   7. VERIFICACION
   ----------------------------------------------------------------- */

-- Total y cuantos quedaron sin rubro tuyo
SELECT
    COUNT(*)                                    AS Total,
    SUM(CASE WHEN IdRubro IS NULL THEN 1 ELSE 0 END) AS SinRubroPropio,
    SUM(CASE WHEN PrecioLista = 0 THEN 1 ELSE 0 END) AS SinPrecio,
    SUM(CASE WHEN IdRepuesto IS NOT NULL THEN 1 ELSE 0 END) AS EnMiCatalogo
FROM ProveedorRepuesto;

-- Rubros de la lista que NO existen en tu base.
-- Son los candidatos a crear, o a corregir si es solo un tema de nombre.
SELECT TOP 60 RubroTexto, COUNT(*) AS Articulos
FROM ProveedorRepuesto
WHERE IdRubro IS NULL
GROUP BY RubroTexto
ORDER BY COUNT(*) DESC;

-- Control de la cadena: el costo tiene que dar lista x (1-d1) x (1-d2)
SELECT TOP 10
    CodigoProveedor, Descripcion, PrecioLista,
    DescuentoRubro, DescuentoGeneral, PrecioCompra,
    CAST(PrecioLista * (1 - DescuentoRubro/100.0) * (1 - DescuentoGeneral/100.0)
         AS DECIMAL(12,2)) AS CostoCalculado
FROM ProveedorRepuesto
WHERE ABS(PrecioCompra -
          CAST(PrecioLista * (1 - DescuentoRubro/100.0) * (1 - DescuentoGeneral/100.0)
               AS DECIMAL(12,2))) > 0.05;
-- Si esto no devuelve filas, la cadena cierra en las 53.188.

-- La abrazadera del catalogo web: tiene que dar 743,40 -> 602,15
SELECT CodigoProveedor, Descripcion, PrecioLista, DescuentoRubro,
       DescuentoGeneral, PrecioCompra
FROM ProveedorRepuesto
WHERE CodigoProveedor = '359V001';

-- Descuentos por rubro que trae la lista
SELECT RubroTexto, DescuentoRubro, COUNT(*) AS Articulos
FROM ProveedorRepuesto
WHERE DescuentoRubro > 0
GROUP BY RubroTexto, DescuentoRubro
ORDER BY DescuentoRubro DESC, COUNT(*) DESC;
GO


/* -----------------------------------------------------------------
   8. Enlazar la lista con tu catalogo actual

   Se enlaza por descripcion parecida, solo como SUGERENCIA.
   NO actualiza nada: mira el resultado y enlaza vos los que
   correspondan. El matcheo automatico por texto se equivoca, y un
   repuesto enlazado al articulo equivocado te trae el costo de otra
   cosa.
   ----------------------------------------------------------------- */
SELECT
    r.Id            AS IdRepuestoMio,
    r.Codigo        AS MiCodigo,
    r.Descripcion   AS MiDescripcion,
    r.PrecioCompra  AS MiCostoActual,
    pr.Id           AS IdListaProveedor,
    pr.CodigoProveedor,
    pr.Descripcion  AS DescripcionProveedor,
    pr.PrecioCompra AS CostoProveedor,
    CASE WHEN r.PrecioCompra > 0
         THEN CAST((pr.PrecioCompra - r.PrecioCompra) / r.PrecioCompra * 100 AS DECIMAL(6,2))
         ELSE NULL END AS DiferenciaPorc
FROM Repuesto r
INNER JOIN ProveedorRepuesto pr
    ON pr.Activo = 1
   AND pr.Descripcion LIKE '%' + LEFT(r.Descripcion, 15) + '%'
WHERE r.Activo = 1
ORDER BY r.Codigo;

-- Para enlazar uno a mano:
-- UPDATE ProveedorRepuesto SET IdRepuesto = <IdRepuestoMio> WHERE Id = <IdListaProveedor>;
GO
