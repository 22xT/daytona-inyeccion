USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   78 — REGISTRO DE BUSQUEDAS

   Cada busqueda del mostrador queda anotada: que se escribio, quien,
   y que encontro (en el local con stock, en el local sin stock, en
   proveedores, en ningun lado). Sirve para tres cosas:
   - Lo que piden y no tenemos: demanda que hoy se pierde.
   - Lo que no aparece en ningun lado: como lo escribe la gente
     (sinonimos que faltan, errores de tipeo).
   - Cuantas busquedas terminan en venta.

   Lo que se guarda es lo que no se puede reconstruir despues: el
   texto, los resultados de ESE momento (los ids que se mostraron) y
   los conteos. Si termino en venta NO se guarda: se calcula cruzando
   con las ventas del mismo usuario en los 30 minutos siguientes que
   incluyen alguno de esos repuestos.

   Mientras se escribe, el buscador busca varias veces ("bom",
   "bomba", "bomba agua"). Para no anotar cada letra, si el mismo
   usuario busca algo que empieza igual dentro de los 2 minutos, se
   actualiza la misma fila.
   ================================================================= */


/* -----------------------------------------------------------------
   1. Tabla
   ----------------------------------------------------------------- */
IF OBJECT_ID('RegistroBusqueda', 'U') IS NULL
BEGIN
    CREATE TABLE RegistroBusqueda (
        Id                  INT IDENTITY(1,1) PRIMARY KEY,
        Fecha               DATETIME      NOT NULL DEFAULT GETDATE(),
        FechaUltima         DATETIME      NOT NULL DEFAULT GETDATE(),
        IdUsuario           INT           NULL,
        Origen              VARCHAR(20)   NOT NULL DEFAULT 'BUSCADOR',
        Texto               VARCHAR(200)  NOT NULL,
        TextoNormalizado    VARCHAR(400)  NULL,
        ResultadosLocal     INT           NOT NULL DEFAULT 0,
        ConStock            INT           NOT NULL DEFAULT 0,
        ResultadosProveedor INT           NOT NULL DEFAULT 0,
        IdsMostrados        VARCHAR(800)  NULL      -- ' 12 45 78 ': repuestos del local que se vieron
    );
    CREATE INDEX IX_RegistroBusqueda_Fecha ON RegistroBusqueda (Fecha) INCLUDE (IdUsuario, TextoNormalizado);
    CREATE INDEX IX_RegistroBusqueda_Usuario ON RegistroBusqueda (IdUsuario, FechaUltima);
END
GO


/* -----------------------------------------------------------------
   2. Anotar una busqueda (lo llama la API despues de buscar)
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Busqueda_Registrar', 'P') IS NOT NULL DROP PROCEDURE SP_Busqueda_Registrar;
GO
CREATE PROCEDURE SP_Busqueda_Registrar
    @IdUsuario           INT = NULL,
    @Texto               VARCHAR(200),
    @Origen              VARCHAR(20) = 'BUSCADOR',
    @ResultadosLocal     INT = 0,
    @ConStock            INT = 0,
    @ResultadosProveedor INT = 0,
    @IdsMostrados        VARCHAR(800) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @Texto = LTRIM(RTRIM(ISNULL(@Texto, '')));
    IF LEN(@Texto) < 3 RETURN;

    DECLARE @norm VARCHAR(400) = dbo.fn_NormalizarBusqueda(@Texto);
    IF @norm IS NULL OR LEN(@norm) < 3 RETURN;

    -- La misma busqueda que se sigue escribiendo (o corrigiendo)
    DECLARE @id INT;
    SELECT TOP 1 @id = Id
    FROM RegistroBusqueda
    WHERE ISNULL(IdUsuario, 0) = ISNULL(@IdUsuario, 0)
      AND Origen = ISNULL(@Origen, 'BUSCADOR')
      AND FechaUltima >= DATEADD(SECOND, -120, GETDATE())
      AND (@norm LIKE TextoNormalizado + '%' OR TextoNormalizado LIKE @norm + '%')
    ORDER BY FechaUltima DESC;

    IF @id IS NOT NULL
        UPDATE RegistroBusqueda
        SET Texto = @Texto, TextoNormalizado = @norm, FechaUltima = GETDATE(),
            ResultadosLocal = ISNULL(@ResultadosLocal, 0), ConStock = ISNULL(@ConStock, 0),
            ResultadosProveedor = ISNULL(@ResultadosProveedor, 0), IdsMostrados = @IdsMostrados
        WHERE Id = @id;
    ELSE
        INSERT INTO RegistroBusqueda
            (IdUsuario, Origen, Texto, TextoNormalizado, ResultadosLocal, ConStock, ResultadosProveedor, IdsMostrados)
        VALUES
            (@IdUsuario, ISNULL(@Origen, 'BUSCADOR'), @Texto, @norm, ISNULL(@ResultadosLocal, 0),
             ISNULL(@ConStock, 0), ISNULL(@ResultadosProveedor, 0), @IdsMostrados);
END
GO


/* -----------------------------------------------------------------
   3. Reporte
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Busqueda_Reporte', 'P') IS NOT NULL DROP PROCEDURE SP_Busqueda_Reporte;
GO
CREATE PROCEDURE SP_Busqueda_Reporte
    @Dias INT = 30
AS
BEGIN
    SET NOCOUNT ON;
    IF @Dias IS NULL OR @Dias <= 0 OR @Dias > 365 SET @Dias = 30;
    DECLARE @desde DATETIME = DATEADD(DAY, -@Dias, CAST(GETDATE() AS DATE));

    -- Cada busqueda del periodo, con su resultado y si termino en venta
    SELECT b.Id, b.Fecha, b.IdUsuario, b.Texto, b.TextoNormalizado,
           b.ResultadosLocal, b.ConStock, b.ResultadosProveedor,
           CASE WHEN b.ConStock > 0                   THEN 'CON_STOCK'
                WHEN b.ResultadosProveedor > 0        THEN 'EN_PROVEEDOR'
                WHEN b.ResultadosLocal > 0            THEN 'SIN_STOCK'
                ELSE 'NADA' END AS Resultado,
           CASE WHEN b.IdsMostrados IS NOT NULL AND EXISTS (
                    SELECT 1 FROM Venta v
                    INNER JOIN DetalleVenta dv ON dv.IdVenta = v.Id
                    WHERE v.IdEstadoVenta = 1
                      AND v.IdUsuario = b.IdUsuario
                      AND v.Fecha BETWEEN b.Fecha AND DATEADD(MINUTE, 30, b.FechaUltima)
                      AND b.IdsMostrados LIKE '% ' + CAST(dv.IdRepuesto AS VARCHAR(12)) + ' %')
                THEN 1 ELSE 0 END AS TerminoEnVenta
    INTO #b
    FROM RegistroBusqueda b
    WHERE b.Fecha >= @desde
      AND b.Origen <> 'REVISION';   -- lo que se busca desde este reporte no cuenta

    -- 1) Resumen
    SELECT COUNT(*) AS Busquedas,
           COUNT(DISTINCT IdUsuario) AS Usuarios,
           SUM(CASE WHEN Resultado = 'CON_STOCK' THEN 1 ELSE 0 END)    AS ConStock,
           SUM(CASE WHEN Resultado = 'EN_PROVEEDOR' THEN 1 ELSE 0 END) AS SoloEnProveedor,
           SUM(CASE WHEN Resultado = 'SIN_STOCK' THEN 1 ELSE 0 END)    AS SinStockNiProveedor,
           SUM(CASE WHEN Resultado = 'NADA' THEN 1 ELSE 0 END)         AS SinResultados,
           SUM(TerminoEnVenta)                                          AS TerminaronEnVenta,
           @Dias AS Dias
    FROM #b;

    -- 2) Lo que piden y no tenemos en stock
    SELECT TOP 50
           TextoNormalizado,
           MAX(Texto)                    AS ComoLoEscribieron,
           COUNT(*)                      AS Veces,
           MAX(Fecha)                    AS Ultima,
           MAX(ResultadosProveedor)      AS EnProveedores,
           MAX(ResultadosLocal)          AS EnCatalogo,
           SUM(TerminoEnVenta)           AS TerminaronEnVenta
    FROM #b
    WHERE ConStock = 0
    GROUP BY TextoNormalizado
    ORDER BY COUNT(*) DESC, MAX(Fecha) DESC;

    -- 3) Lo mas buscado
    SELECT TOP 30
           TextoNormalizado,
           MAX(Texto)                    AS ComoLoEscribieron,
           COUNT(*)                      AS Veces,
           SUM(TerminoEnVenta)           AS TerminaronEnVenta,
           SUM(CASE WHEN ConStock > 0 THEN 1 ELSE 0 END) AS ConStock
    FROM #b
    GROUP BY TextoNormalizado
    ORDER BY COUNT(*) DESC, MAX(Fecha) DESC;

    -- 4) Sin resultados en ningun lado: sinonimos que faltan o errores
    SELECT TOP 50
           TextoNormalizado,
           MAX(Texto)                    AS ComoLoEscribieron,
           COUNT(*)                      AS Veces,
           MAX(Fecha)                    AS Ultima
    FROM #b
    WHERE Resultado = 'NADA'
    GROUP BY TextoNormalizado
    ORDER BY COUNT(*) DESC, MAX(Fecha) DESC;

    -- 5) Por dia (para el grafico)
    SELECT CAST(Fecha AS DATE) AS Dia, COUNT(*) AS Busquedas,
           SUM(CASE WHEN ConStock = 0 THEN 1 ELSE 0 END) AS SinStock,
           SUM(TerminoEnVenta) AS TerminaronEnVenta
    FROM #b
    GROUP BY CAST(Fecha AS DATE)
    ORDER BY Dia;
END
GO


/* -----------------------------------------------------------------
   PRUEBA (no modifica nada)
   ----------------------------------------------------------------- */
EXEC SP_Busqueda_Reporte @Dias = 30;
GO
