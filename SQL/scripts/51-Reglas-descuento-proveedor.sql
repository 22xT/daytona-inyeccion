USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   51 — DESCUENTOS DEL PROVEEDOR POR TIPO DE PRODUCTO

   Algunos proveedores (TAC) hacen descuentos por linea de producto y
   no mandan una columna de rubro. El descuento sale de reglas sobre la
   descripcion: "si dice BUJIA ... NGK, 7%".

   El descuento se guarda en DescuentoRubro, la misma columna que usan
   los proveedores que si mandan rubros. El costo sigue siendo:
       PrecioLista x (1 - DescuentoRubro) x (1 - DescuentoGeneral)

   Un trigger aplica las reglas cada vez que entra o cambia un articulo,
   asi que una lista nueva de TAC ya llega con los descuentos.
   Si se cambian las reglas: EXEC SP_Proveedor_AplicarReglas @IdProveedor
   ================================================================= */

IF OBJECT_ID('ReglaDescuentoProveedor', 'U') IS NULL
BEGIN
    CREATE TABLE ReglaDescuentoProveedor (
        Id          INT IDENTITY(1,1) PRIMARY KEY,
        IdProveedor INT           NOT NULL,
        Nombre      NVARCHAR(80)  NOT NULL,
        -- Patrones LIKE sobre la descripcion en mayusculas. Tienen que
        -- cumplirse los dos Incluye y ninguno de los Excluye.
        Incluye     NVARCHAR(100) NOT NULL,
        Incluye2    NVARCHAR(100) NULL,
        Excluye     NVARCHAR(100) NULL,
        Excluye2    NVARCHAR(100) NULL,
        Porcentaje  DECIMAL(5,2)  NOT NULL,
        Prioridad   INT           NOT NULL DEFAULT 100,   -- si dos reglas coinciden, gana la menor
        Activo      BIT           NOT NULL DEFAULT 1,
        CONSTRAINT FK_ReglaDesc_Proveedor FOREIGN KEY (IdProveedor) REFERENCES Proveedor(Id),
        CONSTRAINT CK_ReglaDesc_Porc CHECK (Porcentaje > 0 AND Porcentaje < 100)
    );
END
GO


/* -----------------------------------------------------------------
   Aplicar las reglas a un conjunto de articulos.
   Solo toca proveedores que tienen reglas, y solo si su perfil no trae
   el descuento de rubro desde el archivo (no pisa a Autocor).
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Proveedor_AplicarReglas', 'P') IS NOT NULL DROP PROCEDURE SP_Proveedor_AplicarReglas;
GO
CREATE PROCEDURE SP_Proveedor_AplicarReglas @IdProveedor INT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM PerfilImportacion WHERE IdProveedor = @IdProveedor AND ColDescuento1 IS NOT NULL)
    BEGIN
        RAISERROR('Este proveedor trae el descuento de rubro en su lista: las reglas no se aplican.', 16, 1);
        RETURN;
    END

    UPDATE pr SET
        DescuentoRubro = ISNULL(r.Porcentaje, 0),
        PrecioCompra   = CAST(pr.PrecioLista * (1 - ISNULL(r.Porcentaje, 0) / 100.0)
                                             * (1 - ISNULL(pr.DescuentoGeneral, 0) / 100.0) AS DECIMAL(12,2))
    FROM ProveedorRepuesto pr
    OUTER APPLY (SELECT TOP 1 x.Porcentaje FROM ReglaDescuentoProveedor x
                 WHERE x.IdProveedor = pr.IdProveedor AND x.Activo = 1
                   AND UPPER(pr.Descripcion) LIKE x.Incluye
                   AND (x.Incluye2 IS NULL OR UPPER(pr.Descripcion) LIKE x.Incluye2)
                   AND (x.Excluye  IS NULL OR UPPER(pr.Descripcion) NOT LIKE x.Excluye)
                   AND (x.Excluye2 IS NULL OR UPPER(pr.Descripcion) NOT LIKE x.Excluye2)
                 ORDER BY x.Prioridad, x.Id) r
    WHERE pr.IdProveedor = @IdProveedor AND pr.PrecioLista IS NOT NULL;

    SELECT @@ROWCOUNT AS ArticulosRecalculados;
END
GO


/* -----------------------------------------------------------------
   Trigger: una lista nueva ya entra con los descuentos aplicados
   ----------------------------------------------------------------- */
IF OBJECT_ID('TR_ProveedorRepuesto_ReglasDescuento', 'TR') IS NOT NULL DROP TRIGGER TR_ProveedorRepuesto_ReglasDescuento;
GO
CREATE TRIGGER TR_ProveedorRepuesto_ReglasDescuento ON ProveedorRepuesto
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT (UPDATE(PrecioLista) OR UPDATE(Descripcion)) RETURN;

    -- Solo proveedores con reglas activas y sin descuento de rubro en su archivo
    IF NOT EXISTS (SELECT 1 FROM inserted i
                   INNER JOIN ReglaDescuentoProveedor x ON x.IdProveedor = i.IdProveedor AND x.Activo = 1)
        RETURN;

    UPDATE pr SET
        DescuentoRubro = ISNULL(r.Porcentaje, 0),
        PrecioCompra   = CAST(pr.PrecioLista * (1 - ISNULL(r.Porcentaje, 0) / 100.0)
                                             * (1 - ISNULL(pr.DescuentoGeneral, 0) / 100.0) AS DECIMAL(12,2))
    FROM ProveedorRepuesto pr
    INNER JOIN inserted i ON i.Id = pr.Id
    OUTER APPLY (SELECT TOP 1 x.Porcentaje FROM ReglaDescuentoProveedor x
                 WHERE x.IdProveedor = pr.IdProveedor AND x.Activo = 1
                   AND UPPER(pr.Descripcion) LIKE x.Incluye
                   AND (x.Incluye2 IS NULL OR UPPER(pr.Descripcion) LIKE x.Incluye2)
                   AND (x.Excluye  IS NULL OR UPPER(pr.Descripcion) NOT LIKE x.Excluye)
                   AND (x.Excluye2 IS NULL OR UPPER(pr.Descripcion) NOT LIKE x.Excluye2)
                 ORDER BY x.Prioridad, x.Id) r
    WHERE pr.PrecioLista IS NOT NULL
      AND EXISTS (SELECT 1 FROM ReglaDescuentoProveedor x WHERE x.IdProveedor = pr.IdProveedor AND x.Activo = 1)
      AND NOT EXISTS (SELECT 1 FROM PerfilImportacion p WHERE p.IdProveedor = pr.IdProveedor AND p.ColDescuento1 IS NOT NULL);
END
GO


/* -----------------------------------------------------------------
   Reglas de TAC (acordadas con el proveedor)
   ----------------------------------------------------------------- */
DECLARE @IdTac INT = (SELECT TOP 1 Id FROM Proveedor WHERE UPPER(LTRIM(RTRIM(RazonSocial))) LIKE 'TAC%' ORDER BY Id);

IF NOT EXISTS (SELECT 1 FROM ReglaDescuentoProveedor WHERE IdProveedor = @IdTac)
    INSERT INTO ReglaDescuentoProveedor (IdProveedor, Nombre, Incluye, Incluye2, Excluye, Excluye2, Porcentaje, Prioridad) VALUES
        -- "BUJIA ENC.NGK BKR6E"; el _ acepta BUJIA y BUJÍA
        (@IdTac, N'Bujías NGK',                       N'BUJ_A%NGK%',           NULL,     N'%CABLE%', NULL,          7.00, 10),
        -- "CABLE BUJIA NGK SC-T59"; deja afuera los Genoud "tipo NGK"
        (@IdTac, N'Cables de bujía NGK',              N'%CABLE%BUJ_A NGK%',    NULL,     NULL,       NULL,          7.00, 10),
        -- Solo las que dicen Estrada: 4 plaquetas sin marca quedan sin descuento
        (@IdTac, N'Plaquetas rectificadoras Estrada', N'%PLAQUETA%RECTIFICAD%', N'%ESTRADA%', NULL,  NULL,          5.00, 20),
        -- Lamparas, juegos, kits y LEDs de señalizacion; no faros ni plafones
        (@IdTac, N'Lámparas CREE LED',                N'%CREE%',               N'%LED%', N'FARO%',   N'PLAFON%',    6.00, 30);

EXEC SP_Proveedor_AplicarReglas @IdProveedor = @IdTac;
GO


/* -----------------------------------------------------------------
   Verificacion: cuantos articulos tomo cada regla
   Esperado: Bujías 68 · Cables 30 · Plaquetas 36 · Lámparas 73
   ----------------------------------------------------------------- */
DECLARE @IdTac INT = (SELECT TOP 1 Id FROM Proveedor WHERE UPPER(LTRIM(RTRIM(RazonSocial))) LIKE 'TAC%' ORDER BY Id);

SELECT DescuentoRubro AS [Descuento %], COUNT(*) AS Articulos
FROM ProveedorRepuesto WHERE IdProveedor = @IdTac AND Activo = 1
GROUP BY DescuentoRubro ORDER BY DescuentoRubro;

SELECT TOP 12 CodigoProveedor, LEFT(Descripcion, 60) AS Descripcion, PrecioLista, DescuentoRubro, PrecioCompra
FROM ProveedorRepuesto
WHERE IdProveedor = @IdTac AND DescuentoRubro > 0
ORDER BY DescuentoRubro DESC, CodigoProveedor;
GO
