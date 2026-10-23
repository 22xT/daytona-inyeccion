USE [DaytonaInyeccion];
GO

/* =================================================================
   MODELO DE PRECIOS — costo, IVA y margen

   Responsable inscripto: los precios se guardan NETOS y la pantalla
   muestra el final con IVA. Guardar el final y despejar el neto hacia
   atras funciona hasta que aparecen los redondeos; ahi los numeros
   dejan de cerrar contra el libro de IVA.

   El margen se calcula SIEMPRE sobre el neto. El IVA que cobras no es
   tuyo: calcular rentabilidad sobre precios finales la infla.

   ESTE SCRIPT NO BORRA DATOS. Solo agrega columnas y mueve el precio
   actual a la columna de costo, que es lo que realmente es.
   ================================================================= */

/* -----------------------------------------------------------------
   0. ANTES DE EMPEZAR: backup
   Cambiar la ruta por una que exista en el servidor.
   ----------------------------------------------------------------- */
-- BACKUP DATABASE DaytonaInyeccion
-- TO DISK = 'C:\Backups\DaytonaInyeccion_antes_precios.bak'
-- WITH INIT, NAME = 'Antes del modelo de precios';
-- GO

-- Foto del estado actual, para comparar despues
SELECT Id, Codigo, Descripcion, PrecioDeVenta AS PrecioActual_QueEsCosto
FROM Repuesto
ORDER BY Id;
GO


/* -----------------------------------------------------------------
   1. ALICUOTAS DE IVA
   Tabla chica en vez de constantes sueltas: si cambia una alicuota,
   se cambia en un lugar y queda registrado desde cuando.
   ----------------------------------------------------------------- */
IF OBJECT_ID('AlicuotaIva', 'U') IS NULL
BEGIN
    CREATE TABLE AlicuotaIva (
        Id          INT IDENTITY(1,1) PRIMARY KEY,
        Nombre      VARCHAR(30)   NOT NULL,
        Porcentaje  DECIMAL(5,2)  NOT NULL,
        Activo      BIT           NOT NULL DEFAULT 1,
        CONSTRAINT UQ_AlicuotaIva_Nombre UNIQUE (Nombre)
    );

    INSERT INTO AlicuotaIva (Nombre, Porcentaje) VALUES
        ('21%',      21.00),
        ('10,5%',    10.50),
        ('Exento',    0.00),
        ('No gravado', 0.00);
END
GO


/* -----------------------------------------------------------------
   2. REPUESTO — costo, precio neto y alicuota

   PrecioDeVenta se CONSERVA y pasa a ser el precio FINAL con IVA,
   calculado. No se borra: lo siguen leyendo pantallas que todavia
   no migramos, y asi nada se rompe mientras avanzamos.
   ----------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Repuesto') AND name = 'PrecioCompra')
    ALTER TABLE Repuesto ADD PrecioCompra DECIMAL(12,2) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Repuesto') AND name = 'PrecioNetoVenta')
    ALTER TABLE Repuesto ADD PrecioNetoVenta DECIMAL(12,2) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Repuesto') AND name = 'IdAlicuotaIva')
    ALTER TABLE Repuesto ADD IdAlicuotaIva INT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Repuesto') AND name = 'FechaUltimaCompra')
    ALTER TABLE Repuesto ADD FechaUltimaCompra DATETIME NULL;
GO

-- Margen propio del repuesto: pisa al del rubro cuando esta cargado.
-- Sirve para los casos puntuales sin tener que crear un rubro nuevo.
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Repuesto') AND name = 'MargenPropio')
    ALTER TABLE Repuesto ADD MargenPropio DECIMAL(6,2) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Repuesto_AlicuotaIva')
    ALTER TABLE Repuesto ADD CONSTRAINT FK_Repuesto_AlicuotaIva
        FOREIGN KEY (IdAlicuotaIva) REFERENCES AlicuotaIva(Id);
GO

-- El 80% va al 21%: se pone por defecto y despues se corrigen las excepciones
UPDATE Repuesto
SET IdAlicuotaIva = (SELECT Id FROM AlicuotaIva WHERE Nombre = '21%')
WHERE IdAlicuotaIva IS NULL;
GO


/* -----------------------------------------------------------------
   3. MIGRACION: el precio actual es un COSTO, no un precio de venta

   No se divide por 1,21. Lo cargado nunca fue un precio de venta:
   era el costo del proveedor puesto en la columna equivocada.
   Se mueve a PrecioCompra y el precio de venta queda NULL hasta que
   se calcule con el margen.
   ----------------------------------------------------------------- */
UPDATE Repuesto
SET PrecioCompra = PrecioDeVenta
WHERE PrecioCompra IS NULL AND PrecioDeVenta > 0;
GO


/* -----------------------------------------------------------------
   4. MARGEN POR RUBRO + MARGEN GENERAL

   Prioridad al calcular: MargenPropio del repuesto, si no el del
   rubro, si no el general. Tres niveles, del mas especifico al mas
   amplio.
   ----------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Rubro') AND name = 'MargenPorcentaje')
    ALTER TABLE Rubro ADD MargenPorcentaje DECIMAL(6,2) NULL;
GO

IF OBJECT_ID('ParametroSistema', 'U') IS NULL
BEGIN
    CREATE TABLE ParametroSistema (
        Clave       VARCHAR(50)   NOT NULL PRIMARY KEY,
        Valor       VARCHAR(200)  NOT NULL,
        Descripcion VARCHAR(300)  NULL
    );

    INSERT INTO ParametroSistema (Clave, Valor, Descripcion) VALUES
        ('MargenGeneral', '40', 'Margen por defecto cuando el rubro no tiene uno propio'),
        ('DescuentoMecanico', '10', 'Descuento fijo para clientes marcados como mecanico');
END
GO


/* -----------------------------------------------------------------
   5. FUNCION: margen que corresponde a un repuesto
   ----------------------------------------------------------------- */
IF OBJECT_ID('fn_MargenDeRepuesto', 'FN') IS NOT NULL DROP FUNCTION fn_MargenDeRepuesto;
GO

CREATE FUNCTION fn_MargenDeRepuesto(@IdRepuesto INT)
RETURNS DECIMAL(6,2)
AS
BEGIN
    DECLARE @margen DECIMAL(6,2);

    SELECT @margen = COALESCE(
        r.MargenPropio,
        ru.MargenPorcentaje,
        TRY_CAST((SELECT Valor FROM ParametroSistema WHERE Clave = 'MargenGeneral') AS DECIMAL(6,2)),
        40.00
    )
    FROM Repuesto r
    LEFT JOIN Rubro ru ON ru.Id = r.IdRubro
    WHERE r.Id = @IdRepuesto;

    RETURN ISNULL(@margen, 40.00);
END
GO


/* -----------------------------------------------------------------
   6. CLIENTE — condicion frente al IVA
   Define si le corresponde factura A o B. Se apoya en EsMecanico
   pero no es lo mismo: hay mecanicos consumidor final.
   ----------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Cliente') AND name = 'CondicionIva')
    ALTER TABLE Cliente ADD CondicionIva VARCHAR(30) NOT NULL
        CONSTRAINT DF_Cliente_CondicionIva DEFAULT 'Consumidor Final';
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Cliente_CondicionIva')
    ALTER TABLE Cliente ADD CONSTRAINT CK_Cliente_CondicionIva
        CHECK (CondicionIva IN ('Consumidor Final', 'Responsable Inscripto', 'Monotributo', 'Exento'));
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Cliente') AND name = 'Cuit')
    ALTER TABLE Cliente ADD Cuit VARCHAR(13) NULL;
GO


/* -----------------------------------------------------------------
   7. VENTA — totales discriminados

   Total se CONSERVA como el importe final. Se agregan las partes
   que hoy no existen y que hacen falta para el libro de IVA y para
   calcular rentabilidad de verdad.
   ----------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Venta') AND name = 'Neto')
    ALTER TABLE Venta ADD Neto DECIMAL(12,2) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Venta') AND name = 'Iva')
    ALTER TABLE Venta ADD Iva DECIMAL(12,2) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Venta') AND name = 'PorcentajeDescuento')
    ALTER TABLE Venta ADD PorcentajeDescuento DECIMAL(6,2) NOT NULL
        CONSTRAINT DF_Venta_PorcDesc DEFAULT 0;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Venta') AND name = 'Descuento')
    ALTER TABLE Venta ADD Descuento DECIMAL(12,2) NOT NULL
        CONSTRAINT DF_Venta_Desc DEFAULT 0;
GO

-- Costo al momento de la venta: sin esto no hay margen real.
-- Se guarda EN LA VENTA porque el costo del repuesto cambia con el
-- tiempo, y la rentabilidad de una venta vieja se calcula con el
-- costo que tenia ese dia, no con el de hoy.
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('DetalleVenta') AND name = 'CostoUnitario')
    ALTER TABLE DetalleVenta ADD CostoUnitario DECIMAL(12,2) NULL;
GO


/* -----------------------------------------------------------------
   8. PRESUPUESTO — mismos campos, para que el papel coincida
   ----------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Presupuesto') AND name = 'Neto')
    ALTER TABLE Presupuesto ADD Neto DECIMAL(12,2) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Presupuesto') AND name = 'Iva')
    ALTER TABLE Presupuesto ADD Iva DECIMAL(12,2) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Presupuesto') AND name = 'PorcentajeDescuento')
    ALTER TABLE Presupuesto ADD PorcentajeDescuento DECIMAL(6,2) NOT NULL
        CONSTRAINT DF_Presu_PorcDesc DEFAULT 0;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Presupuesto') AND name = 'Descuento')
    ALTER TABLE Presupuesto ADD Descuento DECIMAL(12,2) NOT NULL
        CONSTRAINT DF_Presu_Desc DEFAULT 0;
GO


/* -----------------------------------------------------------------
   9. SP: precio de venta SUGERIDO
   No actualiza nada. Devuelve la propuesta para que el usuario
   confirme. Una factura mal cargada no puede mover 50 precios sola.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Repuesto_PrecioSugerido', 'P') IS NOT NULL DROP PROCEDURE SP_Repuesto_PrecioSugerido;
GO

CREATE PROCEDURE SP_Repuesto_PrecioSugerido
    @IdRepuesto INT = NULL   -- NULL = todos los que tengan costo cargado
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        r.Id,
        r.Codigo,
        r.Descripcion,
        ISNULL(ru.Nombre, '-')          AS Rubro,
        r.PrecioCompra,
        dbo.fn_MargenDeRepuesto(r.Id)   AS MargenAplicado,
        a.Porcentaje                    AS AlicuotaIva,

        -- Neto sugerido = costo + margen
        CAST(r.PrecioCompra * (1 + dbo.fn_MargenDeRepuesto(r.Id) / 100.0)
             AS DECIMAL(12,2))          AS NetoSugerido,

        -- Final sugerido = neto + IVA (es lo que se ve en el mostrador)
        CAST(r.PrecioCompra * (1 + dbo.fn_MargenDeRepuesto(r.Id) / 100.0)
             * (1 + a.Porcentaje / 100.0)
             AS DECIMAL(12,2))          AS FinalSugerido,

        r.PrecioNetoVenta               AS NetoActual,
        r.PrecioDeVenta                 AS FinalActual,

        -- Margen que se esta ganando HOY sobre el precio cargado
        CASE WHEN r.PrecioCompra > 0 AND r.PrecioNetoVenta IS NOT NULL
             THEN CAST((r.PrecioNetoVenta - r.PrecioCompra) / r.PrecioCompra * 100 AS DECIMAL(6,2))
             ELSE NULL END              AS MargenActual,

        -- Alerta: vender por debajo del costo es el error que mas plata cuesta
        CASE WHEN r.PrecioNetoVenta IS NULL          THEN 'Sin precio de venta'
             WHEN r.PrecioNetoVenta < r.PrecioCompra THEN 'POR DEBAJO DEL COSTO'
             WHEN r.PrecioNetoVenta < r.PrecioCompra * (1 + dbo.fn_MargenDeRepuesto(r.Id) / 100.0) * 0.9
                                                     THEN 'Margen por debajo del objetivo'
             ELSE 'OK' END              AS Estado

    FROM Repuesto r
    LEFT JOIN Rubro ru ON ru.Id = r.IdRubro
    LEFT JOIN AlicuotaIva a ON a.Id = r.IdAlicuotaIva
    WHERE r.Activo = 1
      AND r.PrecioCompra IS NOT NULL
      AND (@IdRepuesto IS NULL OR r.Id = @IdRepuesto)
    ORDER BY r.Codigo;
END
GO


/* -----------------------------------------------------------------
   10. SP: aplicar el precio confirmado
   Recibe el NETO. El final se calcula, nunca se manda desde afuera:
   si se mandaran los dos, tarde o temprano dejan de coincidir.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_Repuesto_AplicarPrecio', 'P') IS NOT NULL DROP PROCEDURE SP_Repuesto_AplicarPrecio;
GO

CREATE PROCEDURE SP_Repuesto_AplicarPrecio
    @IdRepuesto      INT,
    @PrecioNetoVenta DECIMAL(12,2)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM Repuesto WHERE Id = @IdRepuesto)
    BEGIN
        RAISERROR('El repuesto indicado no existe.', 16, 1);
        RETURN;
    END

    IF @PrecioNetoVenta IS NULL OR @PrecioNetoVenta <= 0
    BEGIN
        RAISERROR('El precio neto debe ser mayor a cero.', 16, 1);
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
END
GO


/* -----------------------------------------------------------------
   11. VERIFICACION
   ----------------------------------------------------------------- */
SELECT Nombre, Porcentaje FROM AlicuotaIva ORDER BY Porcentaje DESC;
SELECT Clave, Valor, Descripcion FROM ParametroSistema;

-- Cada rubro con su margen. Los que salen NULL usan el general.
SELECT Id, Nombre, MargenPorcentaje FROM Rubro ORDER BY Nombre;

-- La propuesta de precios para los 18 repuestos actuales.
-- Ojo: sus costos son de cuando se cargaron. Si tienen meses,
-- conviene contrastarlos con una factura reciente antes de aplicar.
EXEC SP_Repuesto_PrecioSugerido;
GO
