/* =================================================================
   94 - CAJA TIPO SUPERMERCADO (Administracion, fase 3)

   Sobre la sesion de caja del script 42:

   - ARQUEO CIEGO: quien cierra cuenta sin ver lo que espera el
     sistema. El cierre se registra con lo contado; recien despues se
     muestra la diferencia. El motivo se puede cargar al cerrar o
     despues, pero el conteo ya no cambia.
   - ARQUEO POR MEDIO: ademas del efectivo, se declara lo cobrado en
     el turno con cada medio electronico (transferencia, QR, debito,
     credito, prepaga), mirando la app de Mercado Pago. El sistema lo
     compara con las ventas y señas cobradas con ese medio en el turno.
     Un medio que no se declara no se controla.
   - APROBACION: si hay diferencia (en efectivo o en algun medio), el
     cierre queda PENDIENTE de revision hasta que un supervisor, un
     administrador o el dueño lo aprueba con un comentario.
   - RESUMEN DEL TURNO: ventas, comprobantes emitidos, movimientos de
     efectivo por concepto, arqueo por medio y diferencias.

   Requiere los scripts 37, 42, 61 y 92. Hora argentina como el 90.
   Se puede correr mas de una vez. Correr en local y en Azure.
   ================================================================= */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO


/* -----------------------------------------------------------------
   1. Revision de las diferencias
   ----------------------------------------------------------------- */
IF COL_LENGTH('SesionCaja', 'EstadoRevision') IS NULL
    ALTER TABLE SesionCaja ADD
        EstadoRevision     VARCHAR(10)   NULL,   -- NULL: sin diferencia (o anterior a este script)
        DiferenciaMedios   DECIMAL(12,2) NULL,   -- suma de las diferencias de los medios declarados
        IdUsuarioRevision  INT           NULL,
        FechaRevision      DATETIME      NULL,
        ComentarioRevision NVARCHAR(250) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_SesionCaja_Revision')
    ALTER TABLE SesionCaja ADD CONSTRAINT CK_SesionCaja_Revision
        CHECK (EstadoRevision IS NULL OR EstadoRevision IN ('PENDIENTE', 'APROBADA'));
GO


/* -----------------------------------------------------------------
   2. Arqueo por medio de pago
   ----------------------------------------------------------------- */
IF OBJECT_ID('SesionCajaMedio', 'U') IS NULL
BEGIN
    CREATE TABLE SesionCajaMedio (
        IdSesionCaja INT           NOT NULL,
        IdMedioPago  INT           NOT NULL,
        Teorico      DECIMAL(12,2) NOT NULL,   -- cobrado segun el sistema en el turno
        Declarado    DECIMAL(12,2) NULL,       -- lo que se informo al cerrar (NULL: no se controlo)
        Diferencia   DECIMAL(12,2) NULL,       -- declarado - teorico
        CONSTRAINT PK_SesionCajaMedio PRIMARY KEY (IdSesionCaja, IdMedioPago),
        CONSTRAINT FK_SesCajaMedio_Sesion FOREIGN KEY (IdSesionCaja) REFERENCES SesionCaja(Id),
        CONSTRAINT FK_SesCajaMedio_Medio  FOREIGN KEY (IdMedioPago)  REFERENCES MedioPago(Id),
        CONSTRAINT CK_SesCajaMedio_Decl   CHECK (Declarado IS NULL OR Declarado >= 0)
    );
END
GO

IF TYPE_ID('ArqueoMedioType') IS NULL
    CREATE TYPE ArqueoMedioType AS TABLE (
        IdMedioPago INT           NOT NULL,
        Declarado   DECIMAL(12,2) NOT NULL
    );
GO


/* -----------------------------------------------------------------
   3. Cobrado por medio entre dos momentos
      Ventas no anuladas y señas de encargos, con medios electronicos.
      El efectivo se arquea aparte (cajon) y la seña aplicada no es un
      cobro nuevo.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_SesionCaja_MediosTeoricos', 'P') IS NOT NULL DROP PROCEDURE SP_SesionCaja_MediosTeoricos;
GO
CREATE PROCEDURE SP_SesionCaja_MediosTeoricos @Desde DATETIME, @Hasta DATETIME
AS
BEGIN
    SET NOCOUNT ON;
    SELECT mp.Id AS IdMedioPago, mp.Codigo, mp.Nombre, mp.Orden, ISNULL(t.Teorico, 0) AS Teorico, ISNULL(t.Operaciones, 0) AS Operaciones
    FROM MedioPago mp
    INNER JOIN CuentaFinanciera cf ON cf.Id = mp.IdCuentaFinanciera
    LEFT JOIN (
        SELECT IdMedioPago, SUM(Monto) AS Teorico, COUNT(*) AS Operaciones
        FROM (SELECT vp.IdMedioPago, vp.Monto
              FROM VentaPago vp INNER JOIN Venta v ON v.Id = vp.IdVenta
              WHERE v.IdEstadoVenta <> 2 AND vp.Fecha >= @Desde AND vp.Fecha <= @Hasta
              UNION ALL
              SELECT es.IdMedioPago, es.Monto
              FROM EncargoSena es
              WHERE es.Fecha >= @Desde AND es.Fecha <= @Hasta) x
        GROUP BY IdMedioPago
    ) t ON t.IdMedioPago = mp.Id
    WHERE cf.EsCaja = 0 AND mp.Codigo <> 'SEN' AND (mp.Activo = 1 OR t.Teorico IS NOT NULL)
    ORDER BY mp.Orden, mp.Id;
END
GO

-- Medios que se declaran al cerrar (para armar la pantalla, sin importes)
IF OBJECT_ID('SP_SesionCaja_MediosArqueo', 'P') IS NOT NULL DROP PROCEDURE SP_SesionCaja_MediosArqueo;
GO
CREATE PROCEDURE SP_SesionCaja_MediosArqueo
AS
BEGIN
    SET NOCOUNT ON;
    SELECT mp.Id AS IdMedioPago, mp.Codigo, mp.Nombre
    FROM MedioPago mp INNER JOIN CuentaFinanciera cf ON cf.Id = mp.IdCuentaFinanciera
    WHERE cf.EsCaja = 0 AND mp.Codigo <> 'SEN' AND mp.Activo = 1
    ORDER BY mp.Orden, mp.Id;
END
GO


/* -----------------------------------------------------------------
   4. Estado actual. @VerTeorico = 0 para quien cierra a ciegas:
      no ve lo que deberia haber ni lo que entro y salio.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_SesionCaja_Actual', 'P') IS NOT NULL DROP PROCEDURE SP_SesionCaja_Actual;
GO
CREATE PROCEDURE SP_SesionCaja_Actual @VerTeorico BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @IdSesion INT;
    SELECT @IdSesion = s.Id FROM SesionCaja s INNER JOIN CuentaFinanciera c ON c.Id = s.IdCuentaFinanciera
    WHERE s.Estado = 'ABIERTA' AND c.EsCaja = 1;

    IF @IdSesion IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Abierta, dbo.fn_SaldoCaja() AS SaldoSugerido,
               (SELECT TOP 1 FechaCierre FROM SesionCaja WHERE Estado = 'CERRADA' ORDER BY Id DESC) AS UltimoCierre,
               (SELECT COUNT(*) FROM SesionCaja WHERE EstadoRevision = 'PENDIENTE') AS CierresPendientes;
        RETURN;
    END

    SELECT
        CAST(1 AS BIT) AS Abierta, @VerTeorico AS VeTeorico,
        s.Id AS IdSesion, s.FechaApertura, u.Nombre AS UsuarioApertura, s.SaldoInicial,
        CASE WHEN @VerTeorico = 1 THEN ISNULL(SUM(CASE WHEN m.Tipo = 'Ingreso' AND m.Concepto <> 'Diferencia de apertura' THEN m.Monto END), 0) END AS Ingresos,
        CASE WHEN @VerTeorico = 1 THEN ISNULL(SUM(CASE WHEN m.Tipo = 'Egreso'  AND m.Concepto <> 'Diferencia de apertura' THEN m.Monto END), 0) END AS Egresos,
        COUNT(m.Id) AS Movimientos,
        CASE WHEN @VerTeorico = 1 THEN dbo.fn_SaldoCaja() END AS SaldoTeorico,
        -- Una sesion que viene de otro dia: alguien se olvido de cerrar
        CASE WHEN CAST(s.FechaApertura AS DATE) < CAST(DATEADD(HOUR, -3, GETUTCDATE()) AS DATE) THEN 1 ELSE 0 END AS DeOtroDia,
        (SELECT COUNT(*) FROM SesionCaja WHERE EstadoRevision = 'PENDIENTE') AS CierresPendientes
    FROM SesionCaja s
    LEFT JOIN Usuario u ON u.Id = s.IdUsuarioApertura
    LEFT JOIN MovimientoCaja m ON m.IdSesionCaja = s.Id
    WHERE s.Id = @IdSesion
    GROUP BY s.Id, s.FechaApertura, u.Nombre, s.SaldoInicial;
END
GO


/* -----------------------------------------------------------------
   5. Cerrar con arqueo ciego
      Se cierra SIEMPRE con lo contado. Si hay diferencia y no vino el
      motivo, queda pendiente de explicar; en cualquier caso queda
      pendiente de aprobacion.
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_SesionCaja_Cerrar', 'P') IS NOT NULL DROP PROCEDURE SP_SesionCaja_Cerrar;
GO
CREATE PROCEDURE SP_SesionCaja_Cerrar
    @EfectivoContado DECIMAL(12,2),
    @Motivo          NVARCHAR(250) = NULL,
    @IdUsuario       INT,
    @Medios          ArqueoMedioType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF @EfectivoContado IS NULL OR @EfectivoContado < 0
            RAISERROR('El efectivo contado no puede ser negativo.', 16, 1);
        IF EXISTS (SELECT 1 FROM @Medios WHERE Declarado < 0)
            RAISERROR('Lo declarado por medio de pago no puede ser negativo.', 16, 1);

        SET @Motivo = NULLIF(LTRIM(RTRIM(ISNULL(@Motivo, N''))), N'');
        IF @Motivo IS NOT NULL AND LEN(@Motivo) < 10
            RAISERROR('El motivo tiene que tener al menos 10 caracteres.', 16, 1);

        BEGIN TRANSACTION;

        DECLARE @IdSesion INT, @Apertura DATETIME;
        SELECT @IdSesion = s.Id, @Apertura = s.FechaApertura
        FROM SesionCaja s WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN CuentaFinanciera c ON c.Id = s.IdCuentaFinanciera
        WHERE s.Estado = 'ABIERTA' AND c.EsCaja = 1;

        IF @IdSesion IS NULL
            RAISERROR('La caja no esta abierta.', 16, 1);

        DECLARE @Ahora DATETIME = DATEADD(HOUR, -3, GETUTCDATE());

        -- Teorico del efectivo. Se bloquea: una venta que entre en este
        -- instante espera a que termine el cierre.
        DECLARE @Teorico DECIMAL(12,2);
        SELECT TOP 1 @Teorico = SaldoResultante FROM MovimientoCaja WITH (UPDLOCK, HOLDLOCK) ORDER BY Id DESC;
        SET @Teorico = ISNULL(@Teorico, 0);
        DECLARE @Dif DECIMAL(12,2) = @EfectivoContado - @Teorico;

        -- El sistema queda igual al cajon: la diferencia es un movimiento de la sesion
        IF @Dif <> 0
        BEGIN
            DECLARE @TipoAj NVARCHAR(10) = CASE WHEN @Dif > 0 THEN 'Ingreso' ELSE 'Egreso' END;
            DECLARE @MontoAj DECIMAL(12,2) = ABS(@Dif);
            DECLARE @DescAj NVARCHAR(250) = ISNULL(@Motivo, N'Diferencia de arqueo de la sesión #' + CAST(@IdSesion AS NVARCHAR(10)) + N' (motivo a cargar)');
            EXEC SP_MovimientoCaja_RegistrarInterno
                 @Tipo = @TipoAj,
                 @Concepto = 'Diferencia de arqueo',
                 @Monto = @MontoAj,
                 @Descripcion = @DescAj,
                 @IdUsuario = @IdUsuario;
        END

        -- Arqueo de los medios electronicos
        CREATE TABLE #Teo (IdMedioPago INT, Codigo VARCHAR(10), Nombre NVARCHAR(40), Orden INT, Teorico DECIMAL(12,2), Operaciones INT);
        INSERT INTO #Teo EXEC SP_SesionCaja_MediosTeoricos @Apertura, @Ahora;

        INSERT INTO SesionCajaMedio (IdSesionCaja, IdMedioPago, Teorico, Declarado, Diferencia)
        SELECT @IdSesion, t.IdMedioPago, t.Teorico, d.Declarado, d.Declarado - t.Teorico
        FROM #Teo t
        LEFT JOIN @Medios d ON d.IdMedioPago = t.IdMedioPago
        WHERE t.Teorico <> 0 OR d.IdMedioPago IS NOT NULL;

        DECLARE @DifMedios DECIMAL(12,2) = (SELECT SUM(Diferencia) FROM SesionCajaMedio WHERE IdSesionCaja = @IdSesion);
        DECLARE @HayDifMedios BIT = CASE WHEN EXISTS (SELECT 1 FROM SesionCajaMedio
                                                     WHERE IdSesionCaja = @IdSesion AND Diferencia <> 0) THEN 1 ELSE 0 END;

        UPDATE SesionCaja
        SET Estado = 'CERRADA', FechaCierre = @Ahora, IdUsuarioCierre = @IdUsuario,
            SaldoTeorico = @Teorico, EfectivoContado = @EfectivoContado, Diferencia = @Dif,
            MotivoDiferencia = CASE WHEN @Dif <> 0 OR @HayDifMedios = 1 THEN @Motivo END,
            DiferenciaMedios = @DifMedios,
            EstadoRevision = CASE WHEN @Dif <> 0 OR @HayDifMedios = 1 THEN 'PENDIENTE' END
        WHERE Id = @IdSesion;

        COMMIT;

        SELECT s.Id AS IdSesion, s.SaldoTeorico, s.EfectivoContado, s.Diferencia, s.DiferenciaMedios,
               s.EstadoRevision, s.MotivoDiferencia
        FROM SesionCaja s WHERE s.Id = @IdSesion;

        SELECT m.IdMedioPago, mp.Nombre, m.Teorico, m.Declarado, m.Diferencia
        FROM SesionCajaMedio m INNER JOIN MedioPago mp ON mp.Id = m.IdMedioPago
        WHERE m.IdSesionCaja = @IdSesion ORDER BY mp.Orden, mp.Id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO


/* -----------------------------------------------------------------
   6. Explicar y aprobar una diferencia
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_SesionCaja_Explicar', 'P') IS NOT NULL DROP PROCEDURE SP_SesionCaja_Explicar;
GO
CREATE PROCEDURE SP_SesionCaja_Explicar @IdSesion INT, @Motivo NVARCHAR(250), @IdUsuario INT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Motivo = LTRIM(RTRIM(ISNULL(@Motivo, N'')));
    IF LEN(@Motivo) < 10
    BEGIN
        RAISERROR('Explicá la diferencia con al menos 10 caracteres.', 16, 1);
        RETURN;
    END
    UPDATE SesionCaja SET MotivoDiferencia = @Motivo
    WHERE Id = @IdSesion AND Estado = 'CERRADA' AND EstadoRevision = 'PENDIENTE';
    IF @@ROWCOUNT = 0
        RAISERROR('Ese cierre no tiene una diferencia pendiente.', 16, 1);
END
GO

IF OBJECT_ID('SP_SesionCaja_Aprobar', 'P') IS NOT NULL DROP PROCEDURE SP_SesionCaja_Aprobar;
GO
CREATE PROCEDURE SP_SesionCaja_Aprobar @IdSesion INT, @Comentario NVARCHAR(250), @IdUsuario INT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Comentario = LTRIM(RTRIM(ISNULL(@Comentario, N'')));
    IF LEN(@Comentario) < 5
    BEGIN
        RAISERROR('Dejá un comentario de la revisión (mínimo 5 caracteres).', 16, 1);
        RETURN;
    END
    IF EXISTS (SELECT 1 FROM SesionCaja WHERE Id = @IdSesion AND EstadoRevision = 'PENDIENTE' AND MotivoDiferencia IS NULL)
    BEGIN
        RAISERROR('Primero quien cerró la caja tiene que explicar la diferencia.', 16, 1);
        RETURN;
    END
    UPDATE SesionCaja
    SET EstadoRevision = 'APROBADA', IdUsuarioRevision = @IdUsuario,
        FechaRevision = DATEADD(HOUR, -3, GETUTCDATE()), ComentarioRevision = @Comentario
    WHERE Id = @IdSesion AND EstadoRevision = 'PENDIENTE';
    IF @@ROWCOUNT = 0
        RAISERROR('Ese cierre no tiene una diferencia pendiente de aprobar.', 16, 1);
END
GO


/* -----------------------------------------------------------------
   7. Historial con el estado de la revision
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_SesionCaja_Historial', 'P') IS NOT NULL DROP PROCEDURE SP_SesionCaja_Historial;
GO
CREATE PROCEDURE SP_SesionCaja_Historial
    @Desde DATE = NULL,
    @Hasta DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @hoy DATE = CAST(DATEADD(HOUR, -3, GETUTCDATE()) AS DATE);
    IF @Desde IS NULL SET @Desde = DATEADD(DAY, -30, @hoy);
    IF @Hasta IS NULL SET @Hasta = @hoy;

    SELECT s.Id, s.Estado, s.FechaApertura, ua.Nombre AS UsuarioApertura, s.SaldoInicial,
           s.SaldoSugerido, s.MotivoApertura,
           s.FechaCierre, uc.Nombre AS UsuarioCierre, s.SaldoTeorico, s.EfectivoContado,
           s.Diferencia, s.MotivoDiferencia, s.DiferenciaMedios,
           s.EstadoRevision, ur.Nombre AS UsuarioRevision, s.FechaRevision, s.ComentarioRevision,
           (SELECT COUNT(*) FROM MovimientoCaja m WHERE m.IdSesionCaja = s.Id) AS Movimientos
    FROM SesionCaja s
    LEFT JOIN Usuario ua ON ua.Id = s.IdUsuarioApertura
    LEFT JOIN Usuario uc ON uc.Id = s.IdUsuarioCierre
    LEFT JOIN Usuario ur ON ur.Id = s.IdUsuarioRevision
    WHERE CAST(s.FechaApertura AS DATE) BETWEEN @Desde AND @Hasta
       OR s.EstadoRevision = 'PENDIENTE'          -- un pendiente viejo no se pierde de vista
    ORDER BY s.Id DESC;
END
GO


/* -----------------------------------------------------------------
   8. Resumen del turno (solo de un cierre ya hecho)
   ----------------------------------------------------------------- */
IF OBJECT_ID('SP_SesionCaja_Resumen', 'P') IS NOT NULL DROP PROCEDURE SP_SesionCaja_Resumen;
GO
CREATE PROCEDURE SP_SesionCaja_Resumen @IdSesion INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Desde DATETIME, @Hasta DATETIME, @Estado VARCHAR(8);
    SELECT @Desde = FechaApertura, @Hasta = FechaCierre, @Estado = Estado FROM SesionCaja WHERE Id = @IdSesion;
    IF @Estado IS NULL
    BEGIN
        RAISERROR('El turno no existe.', 16, 1);
        RETURN;
    END
    IF @Estado <> 'CERRADA'
    BEGIN
        RAISERROR('El resumen se ve cuando el turno está cerrado.', 16, 1);
        RETURN;
    END

    -- 1. Cabecera
    SELECT s.Id, s.FechaApertura, ua.Nombre AS UsuarioApertura, s.SaldoInicial, s.SaldoSugerido, s.MotivoApertura,
           s.FechaCierre, uc.Nombre AS UsuarioCierre, s.SaldoTeorico, s.EfectivoContado, s.Diferencia,
           s.MotivoDiferencia, s.DiferenciaMedios, s.EstadoRevision, ur.Nombre AS UsuarioRevision,
           s.FechaRevision, s.ComentarioRevision
    FROM SesionCaja s
    LEFT JOIN Usuario ua ON ua.Id = s.IdUsuarioApertura
    LEFT JOIN Usuario uc ON uc.Id = s.IdUsuarioCierre
    LEFT JOIN Usuario ur ON ur.Id = s.IdUsuarioRevision
    WHERE s.Id = @IdSesion;

    -- 2. Efectivo por concepto
    SELECT Tipo, Concepto, COUNT(*) AS Cantidad, SUM(Monto) AS Total
    FROM MovimientoCaja WHERE IdSesionCaja = @IdSesion
    GROUP BY Tipo, Concepto
    ORDER BY CASE Tipo WHEN 'Ingreso' THEN 0 ELSE 1 END, SUM(Monto) DESC;

    -- 3. Medios electronicos: teorico, declarado y diferencia
    SELECT mp.Nombre, m.Teorico, m.Declarado, m.Diferencia
    FROM SesionCajaMedio m INNER JOIN MedioPago mp ON mp.Id = m.IdMedioPago
    WHERE m.IdSesionCaja = @IdSesion ORDER BY mp.Orden, mp.Id;

    -- 4. Ventas del turno
    SELECT COUNT(CASE WHEN IdEstadoVenta <> 2 THEN 1 END) AS Ventas,
           ISNULL(SUM(CASE WHEN IdEstadoVenta <> 2 THEN Total END), 0) AS Total,
           COUNT(CASE WHEN IdEstadoVenta = 2 THEN 1 END) AS Anuladas
    FROM Venta WHERE Fecha >= @Desde AND Fecha <= @Hasta;

    -- 5. Cobrado por medio (efectivo y electronicos) en las ventas del turno
    SELECT mp.Nombre, COUNT(*) AS Operaciones, SUM(vp.Monto) AS Cobrado
    FROM VentaPago vp
    INNER JOIN Venta v ON v.Id = vp.IdVenta
    INNER JOIN MedioPago mp ON mp.Id = vp.IdMedioPago
    WHERE v.IdEstadoVenta <> 2 AND vp.Fecha >= @Desde AND vp.Fecha <= @Hasta
    GROUP BY mp.Nombre, mp.Orden
    ORDER BY mp.Orden;

    -- 6. Comprobantes emitidos en el turno
    SELECT t.Nombre AS Tipo, t.Clase, COUNT(*) AS Cantidad, SUM(c.ImporteTotal) AS Total,
           SUM(CASE WHEN c.Estado = 'AUTORIZADO' THEN 1 ELSE 0 END) AS Autorizados
    FROM Comprobante c INNER JOIN TipoComprobante t ON t.Id = c.IdTipoComprobante
    WHERE c.FechaCreacion >= @Desde AND c.FechaCreacion <= @Hasta AND c.Estado <> 'ANULADO'
    GROUP BY t.Nombre, t.Clase, t.Id
    ORDER BY t.Id;
END
GO


/* -----------------------------------------------------------------
   CONTROL
   ----------------------------------------------------------------- */
EXEC SP_SesionCaja_MediosArqueo;
SELECT COUNT(*) AS CierresPendientesDeRevision FROM SesionCaja WHERE EstadoRevision = 'PENDIENTE';
GO
