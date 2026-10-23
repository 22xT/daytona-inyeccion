USE [DaytonaInyeccion]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
   34 — IDEMPOTENCIA EN LA VENTA

   EL PROBLEMA
   El vendedor toca "Registrar" dos veces, o la red se cuelga y el
   navegador reenvia. Se crean dos ventas iguales: doble descuento de
   stock, doble ingreso en caja. No se nota hasta el arqueo.

   LA SOLUCION
   El cliente genera un token unico (GUID) al armar el carrito y lo
   manda con la venta. El servidor lo reserva ANTES de registrar:
     - si el token es nuevo, registra y lo asocia a la venta
     - si ya existe con venta, devuelve esa venta sin crear otra
     - si ya existe sin venta, hay otra peticion en curso: rechaza

   La reserva es un INSERT con clave primaria: dos peticiones
   simultaneas con el mismo token no pueden entrar las dos. La base
   garantiza la exclusion, no el codigo.

   No se toca SP_Venta_I. Se envuelve.
   ================================================================= */

IF OBJECT_ID('VentaOperacion', 'U') IS NULL
BEGIN
    CREATE TABLE VentaOperacion (
        Token      UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
        IdVenta    INT NULL,                 -- NULL mientras esta en curso
        IdUsuario  INT NOT NULL,
        Fecha      DATETIME NOT NULL DEFAULT GETDATE(),
        CONSTRAINT FK_VentaOperacion_Venta FOREIGN KEY (IdVenta) REFERENCES Venta(Id)
    );
END
GO


/* Reservar el token. Devuelve:
     Estado = 'NUEVA'    -> seguir y registrar
     Estado = 'EXISTE'   -> ya se registro; IdVenta viene cargado
     Estado = 'EN_CURSO' -> otra peticion la esta registrando ahora */
IF OBJECT_ID('SP_VentaOperacion_Reservar', 'P') IS NOT NULL DROP PROCEDURE SP_VentaOperacion_Reservar;
GO

CREATE PROCEDURE SP_VentaOperacion_Reservar
    @Token     UNIQUEIDENTIFIER,
    @IdUsuario INT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        INSERT INTO VentaOperacion (Token, IdUsuario) VALUES (@Token, @IdUsuario);
        SELECT 'NUEVA' AS Estado, CAST(NULL AS INT) AS IdVenta;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 2627   -- violacion de clave primaria: ya estaba
        BEGIN
            DECLARE @idVenta INT;
            SELECT @idVenta = IdVenta FROM VentaOperacion WHERE Token = @Token;

            IF @idVenta IS NOT NULL
                SELECT 'EXISTE' AS Estado, @idVenta AS IdVenta;
            ELSE
                SELECT 'EN_CURSO' AS Estado, CAST(NULL AS INT) AS IdVenta;
        END
        ELSE
            THROW;
    END CATCH
END
GO


-- Asociar la venta al token, cuando SP_Venta_I termino bien
IF OBJECT_ID('SP_VentaOperacion_Completar', 'P') IS NOT NULL DROP PROCEDURE SP_VentaOperacion_Completar;
GO

CREATE PROCEDURE SP_VentaOperacion_Completar
    @Token   UNIQUEIDENTIFIER,
    @IdVenta INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE VentaOperacion SET IdVenta = @IdVenta WHERE Token = @Token;
END
GO


-- Liberar el token si la venta fallo, para que el cliente pueda reintentar
IF OBJECT_ID('SP_VentaOperacion_Liberar', 'P') IS NOT NULL DROP PROCEDURE SP_VentaOperacion_Liberar;
GO

CREATE PROCEDURE SP_VentaOperacion_Liberar
    @Token UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM VentaOperacion WHERE Token = @Token AND IdVenta IS NULL;
END
GO


/* -----------------------------------------------------------------
   Limpieza: los tokens que quedaron en curso hace mas de una hora
   son peticiones que murieron a mitad de camino. Se borran para no
   bloquear reintentos legitimos. Correr esporadicamente o desde el
   job de backup.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_VentaOperacion_Limpiar', 'P') IS NOT NULL DROP PROCEDURE SP_VentaOperacion_Limpiar;
GO

CREATE PROCEDURE SP_VentaOperacion_Limpiar
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM VentaOperacion
    WHERE IdVenta IS NULL AND Fecha < DATEADD(HOUR, -1, GETDATE());
    SELECT @@ROWCOUNT AS Liberados;
END
GO


/* -----------------------------------------------------------------
   PRUEBA: el mismo token dos veces
   ----------------------------------------------------------------- */
DECLARE @t UNIQUEIDENTIFIER = NEWID();

EXEC SP_VentaOperacion_Reservar @Token = @t, @IdUsuario = 1;   -- NUEVA
EXEC SP_VentaOperacion_Reservar @Token = @t, @IdUsuario = 1;   -- EN_CURSO
EXEC SP_VentaOperacion_Completar @Token = @t, @IdVenta = 1;    -- (usa una venta que exista)
EXEC SP_VentaOperacion_Reservar @Token = @t, @IdUsuario = 1;   -- EXISTE, IdVenta = 1

DELETE FROM VentaOperacion WHERE Token = @t;   -- limpiar la prueba
GO
