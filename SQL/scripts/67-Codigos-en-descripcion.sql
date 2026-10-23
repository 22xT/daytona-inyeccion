USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   67 — CODIGOS ESCRITOS EN LA DESCRIPCION

   Buscar KTB341 no traia el de Expoyer, que lo escribe KTB-341 y
   solo dentro de la descripcion ("KIT DISTRIBUCION KTB-341 FOX/SURAN").
   La columna de codigos (CodigosBusqueda, sin guiones ni puntos) solo
   tenia el codigo del proveedor y el de fabrica; los codigos que
   vienen en la descripcion quedaban afuera.

   Ahora tambien entran los codigos de la descripcion: toda palabra
   con algun numero y al menos 4 caracteres, sin separadores.
   KTB-341 -> KTB341, 6PK-1070 -> 6PK1070. "1.6" o "16V" no entran
   (son medidas, no codigos).

   Se mantiene solo con un trigger: las proximas importaciones ya
   llegan con la columna completa.

   Puede tardar un par de minutos (son mas de 160.000 articulos).
   ================================================================= */


/* -----------------------------------------------------------------
   1. Armar la columna de codigos de un articulo
   ----------------------------------------------------------------- */
IF OBJECT_ID('fn_CodigosBusqueda', 'FN') IS NOT NULL DROP FUNCTION fn_CodigosBusqueda;
GO
CREATE FUNCTION fn_CodigosBusqueda
(
    @CodigoProveedor VARCHAR(60),
    @Articulo        VARCHAR(60),
    @Descripcion     VARCHAR(400)
)
RETURNS VARCHAR(200)
AS
BEGIN
    DECLARE @r VARCHAR(200) = ' ' + dbo.fn_LimpiarCodigo(ISNULL(@CodigoProveedor, '')) +
                              ' ' + dbo.fn_LimpiarCodigo(ISNULL(@Articulo, '')) + ' ';

    DECLARE @t VARCHAR(400) = ISNULL(dbo.fn_LimpiarTexto(@Descripcion), '') + ' ';
    DECLARE @pos INT, @pal VARCHAR(100), @cod VARCHAR(100);

    WHILE LEN(@t) > 0
    BEGIN
        SET @pos = CHARINDEX(' ', @t);
        IF @pos = 0 BEGIN SET @t = @t + ' '; SET @pos = CHARINDEX(' ', @t); END
        SET @pal = LEFT(@t, @pos - 1);
        SET @t = LTRIM(SUBSTRING(@t, @pos + 1, 400));

        SET @cod = dbo.fn_LimpiarCodigo(@pal);
        IF @cod LIKE '%[0-9]%' AND LEN(@cod) >= 4
           AND CHARINDEX(' ' + @cod + ' ', @r) = 0
           AND LEN(@r) + LEN(@cod) + 1 <= 199
            SET @r = @r + @cod + ' ';
    END

    RETURN @r;
END
GO


/* -----------------------------------------------------------------
   2. Trigger: altas y cambios de la lista
   ----------------------------------------------------------------- */
IF OBJECT_ID('TR_ProveedorRepuesto_Codigos', 'TR') IS NOT NULL
    DROP TRIGGER TR_ProveedorRepuesto_Codigos;
GO
CREATE TRIGGER TR_ProveedorRepuesto_Codigos ON ProveedorRepuesto
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT (UPDATE(Descripcion) OR UPDATE(Articulo) OR UPDATE(CodigoProveedor)) RETURN;

    UPDATE pr
    SET CodigosBusqueda = dbo.fn_CodigosBusqueda(pr.CodigoProveedor, pr.Articulo, pr.Descripcion)
    FROM ProveedorRepuesto pr
    INNER JOIN inserted i ON i.Id = pr.Id;
END
GO


/* -----------------------------------------------------------------
   3. Reprocesar lo que ya esta cargado
   ----------------------------------------------------------------- */
UPDATE ProveedorRepuesto
SET CodigosBusqueda = dbo.fn_CodigosBusqueda(CodigoProveedor, Articulo, Descripcion);
GO


/* -----------------------------------------------------------------
   PRUEBA: tienen que aparecer los dos (Autocor y Expoyer)
   ----------------------------------------------------------------- */
SELECT p.RazonSocial AS Proveedor, pr.CodigoProveedor, pr.Articulo, pr.Descripcion, pr.CodigosBusqueda
FROM ProveedorRepuesto pr
INNER JOIN Proveedor p ON p.Id = pr.IdProveedor
WHERE pr.CodigosBusqueda LIKE '%KTB341%';
GO
