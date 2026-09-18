------------------------------------------------------
-- BASE DE DATOS DAYTONA INYECCION
------------------------------------------------------
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'DaytonaInyeccion')
BEGIN
    EXEC('CREATE DATABASE DaytonaInyeccion');
END
GO

USE DaytonaInyeccion;
GO


------------------------------------------------------
-- TABLAS PRINCIPALES
------------------------------------------------------

-- MARCA--

IF OBJECT_ID('Marca', 'U') IS NULL
BEGIN
    CREATE TABLE Marca (
        Id INT PRIMARY KEY IDENTITY,
        Nombre NVARCHAR(50) NOT NULL
    );
END
GO

-- MODELO--

IF OBJECT_ID('Modelo', 'U') IS NULL
BEGIN
    CREATE TABLE Modelo (
        Id INT PRIMARY KEY IDENTITY,
        Nombre NVARCHAR(50) NOT NULL,
        IdMarca INT NOT NULL,
        FOREIGN KEY (IdMarca) REFERENCES Marca(Id)
    );
END
GO

-- RUBRO--

IF OBJECT_ID('Rubro', 'U') IS NULL
BEGIN
    CREATE TABLE Rubro (
        Id INT PRIMARY KEY IDENTITY,
        Nombre NVARCHAR(100)
    );
END
GO

IF OBJECT_ID('Proveedor', 'U') IS NOT NULL
    DROP TABLE Proveedor;
GO

CREATE TABLE Proveedor (
    Id INT PRIMARY KEY IDENTITY,
    Cuit NVARCHAR(11) NOT NULL UNIQUE,
    RazonSocial NVARCHAR(100) NOT NULL,
    CondicionIva NVARCHAR(50),
    Calle NVARCHAR(100),
    Barrio NVARCHAR(100),
    Localidad NVARCHAR(100),
    Provincia NVARCHAR(100),
    CodigoPostal NVARCHAR(10),
    Telefono NVARCHAR(50),
    Mail NVARCHAR(100),
    Observaciones NVARCHAR(200)
);
GO


-- REPUESTO
IF OBJECT_ID('Repuesto', 'U') IS NULL
BEGIN
    CREATE TABLE Repuesto (
        Id INT PRIMARY KEY IDENTITY,
        Descripcion NVARCHAR(100) NOT NULL,
        PrecioDeVenta DECIMAL(10,2) NOT NULL,
        IdModelo INT NOT NULL,
        IdRubro INT NOT NULL,
        FOREIGN KEY (IdModelo) REFERENCES Modelo(Id),
        FOREIGN KEY (IdRubro) REFERENCES Rubro(Id)
    );
END
GO

-- PROVEEDOR/REPUESTO (RELACIÓN)
IF OBJECT_ID('ProveedorRepuesto', 'U') IS NULL
BEGIN
    CREATE TABLE ProveedorRepuesto (
        IdProveedor INT NOT NULL,
        IdRepuesto INT NOT NULL,
        Precio DECIMAL(10,2) NOT NULL,
        Fecha DATETIME NOT NULL DEFAULT GETDATE(),
        PRIMARY KEY (IdProveedor, IdRepuesto),
        FOREIGN KEY (IdProveedor) REFERENCES Proveedor(Id),
        FOREIGN KEY (IdRepuesto) REFERENCES Repuesto(Id)
    );
END
GO

------------------------------------------------------
-- TABLA ESTADO PEDIDO
------------------------------------------------------
IF OBJECT_ID('EstadoPedido', 'U') IS NULL
BEGIN
    CREATE TABLE EstadoPedido (
        Id INT PRIMARY KEY IDENTITY,
        Nombre NVARCHAR(50) NOT NULL
    );

    INSERT INTO EstadoPedido (Nombre)
    VALUES ('Pendiente'), ('Recibido'), ('Cancelado');
END
GO
------------------------------------------------------
-- TABLA PEDIDO
------------------------------------------------------
CREATE TABLE Pedido (
    Id INT PRIMARY KEY IDENTITY,
    Fecha DATETIME DEFAULT GETDATE(),
    IdProveedor INT NOT NULL,
    IdEstado INT NOT NULL DEFAULT 1, -- 1 = Pendiente
    Total DECIMAL(10,2) DEFAULT 0,
    FOREIGN KEY (IdProveedor) REFERENCES Proveedor(Id),
    FOREIGN KEY (IdEstado) REFERENCES EstadoPedido(Id)
);
GO
------------------------------------------------------
-- TABLA DETALLE PEDIDO
------------------------------------------------------
CREATE TABLE DetallePedido (
    Id INT PRIMARY KEY IDENTITY,
    IdPedido INT NOT NULL,
    IdRepuesto INT NOT NULL,
    Cantidad INT NOT NULL,
    PrecioUnitario DECIMAL(10,2) NOT NULL,
    Subtotal AS (Cantidad * PrecioUnitario) PERSISTED,
    FOREIGN KEY (IdPedido) REFERENCES Pedido(Id),
    FOREIGN KEY (IdRepuesto) REFERENCES Repuesto(Id)
);
GO

-- CLIENTE
IF OBJECT_ID('Cliente', 'U') IS NULL
BEGIN
    CREATE TABLE Cliente (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        Dni NVARCHAR(8) NOT NULL,
        Nombre NVARCHAR(50) NOT NULL,
        Apellido NVARCHAR(50) NOT NULL,
        Telefono NVARCHAR(20),
        Mail NVARCHAR(50),
        Direccion NVARCHAR(100)
    );
END
GO


------------------------------------------------------
-- PROCEDIMIENTOS ALMACENADOS PRINCIPALES
------------------------------------------------------
------------------------------------------------------
-- PROVEEDOR
------------------------------------------------------

-- INSERTAR
IF OBJECT_ID('SP_Proveedor_I', 'P') IS NOT NULL DROP PROCEDURE SP_Proveedor_I;
GO
CREATE PROCEDURE SP_Proveedor_I
  @Cuit NVARCHAR(11),
  @RazonSocial NVARCHAR(100),
  @CondicionIva NVARCHAR(50),
  @Calle NVARCHAR(100),
  @Barrio NVARCHAR(100),
  @Localidad NVARCHAR(100),
  @Provincia NVARCHAR(100),
  @CodigoPostal NVARCHAR(10),
  @Telefono NVARCHAR(50),
  @Mail NVARCHAR(100),
  @Observaciones NVARCHAR(200)
AS
BEGIN
  INSERT INTO Proveedor (Cuit, RazonSocial, CondicionIva, Calle, Barrio, Localidad, Provincia, CodigoPostal, Telefono, Mail, Observaciones)
  VALUES (@Cuit, @RazonSocial, @CondicionIva, @Calle, @Barrio, @Localidad, @Provincia, @CodigoPostal, @Telefono, @Mail, @Observaciones);
END
GO

-- ACTUALIZAR
IF OBJECT_ID('SP_Proveedor_U', 'P') IS NOT NULL DROP PROCEDURE SP_Proveedor_U;
GO
CREATE PROCEDURE SP_Proveedor_U
  @Id INT,
  @Cuit NVARCHAR(11),
  @RazonSocial NVARCHAR(100),
  @CondicionIva NVARCHAR(50),
  @Calle NVARCHAR(100),
  @Barrio NVARCHAR(100),
  @Localidad NVARCHAR(100),
  @Provincia NVARCHAR(100),
  @CodigoPostal NVARCHAR(10),
  @Telefono NVARCHAR(50),
  @Mail NVARCHAR(100),
  @Observaciones NVARCHAR(200)
AS
BEGIN
  UPDATE Proveedor
  SET Cuit = @Cuit,
      RazonSocial = @RazonSocial,
      CondicionIva = @CondicionIva,
      Calle = @Calle,
      Barrio = @Barrio,
      Localidad = @Localidad,
      Provincia = @Provincia,
      CodigoPostal = @CodigoPostal,
      Telefono = @Telefono,
      Mail = @Mail,
      Observaciones = @Observaciones
  WHERE Id = @Id;
END
GO


-- ELIMINAR
IF OBJECT_ID('SP_Proveedor_D', 'P') IS NOT NULL DROP PROCEDURE SP_Proveedor_D;
GO
CREATE PROCEDURE SP_Proveedor_D
    @Id INT
AS
BEGIN
  DELETE FROM Proveedor WHERE Id = @Id;
END
GO


-- BUSCAR POR ID
IF OBJECT_ID('SP_Proveedor_GetId', 'P') IS NOT NULL DROP PROCEDURE SP_Proveedor_GetId;
GO
CREATE PROCEDURE SP_Proveedor_GetId
    @Id INT
AS
BEGIN
    SELECT * FROM Proveedor WHERE Id=@Id;
END
GO

-- BUSCAR TODOS

IF OBJECT_ID('SP_Proveedor_GetAll', 'P') IS NOT NULL DROP PROCEDURE SP_Proveedor_GetAll;
GO
CREATE PROCEDURE SP_Proveedor_GetAll AS
BEGIN
    SELECT * FROM Proveedor ORDER BY RazonSocial;
END
GO



------------------------------------------------------
-- REPUESTO
------------------------------------------------------

-- INSERTAR
IF OBJECT_ID('SP_Repuesto_I', 'P') IS NOT NULL DROP PROCEDURE SP_Repuesto_I;
GO
CREATE PROCEDURE SP_Repuesto_I
    @Descripcion NVARCHAR(100),
    @PrecioDeVenta DECIMAL(10,2),
    @IdModelo INT,
    @IdRubro INT
AS
BEGIN
    INSERT INTO Repuesto (Descripcion, PrecioDeVenta, IdModelo, IdRubro)
    VALUES (@Descripcion, @PrecioDeVenta, @IdModelo, @IdRubro);
END
GO

-- ACTUALIZAR
IF OBJECT_ID('SP_Repuesto_U', 'P') IS NOT NULL DROP PROCEDURE SP_Repuesto_U;
GO
CREATE PROCEDURE SP_Repuesto_U
    @Id INT,
    @Descripcion NVARCHAR(100),
    @PrecioDeVenta DECIMAL(10,2),
    @IdModelo INT,
    @IdRubro INT
AS
BEGIN
    UPDATE Repuesto
    SET Descripcion=@Descripcion, PrecioDeVenta=@PrecioDeVenta,
        IdModelo=@IdModelo, IdRubro=@IdRubro
    WHERE Id=@Id;
END
GO

-- ELIMINAR
IF OBJECT_ID('SP_Repuesto_D', 'P') IS NOT NULL DROP PROCEDURE SP_Repuesto_D;
GO
CREATE PROCEDURE SP_Repuesto_D
    @Id INT
AS
BEGIN
    DELETE FROM Repuesto WHERE Id=@Id;
END
GO

-- BUSCAR POR ID
IF OBJECT_ID('SP_Repuesto_GetId', 'P') IS NOT NULL DROP PROCEDURE SP_Repuesto_GetId;
GO
CREATE PROCEDURE SP_Repuesto_GetId
    @Id INT
AS
BEGIN
    SELECT * FROM Repuesto WHERE Id=@Id;
END
GO


------------------------------------------------------
-- PEDIDO
------------------------------------------------------

-- INSERTAR
IF OBJECT_ID('SP_Pedido_I', 'P') IS NOT NULL DROP PROCEDURE SP_Pedido_I;
GO
CREATE PROCEDURE SP_Pedido_I
    @IdProveedor INT,
    @Total DECIMAL(10,2)
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO Pedido (IdProveedor, Total, IdEstado)
    VALUES (@IdProveedor, @Total, 1);   
    SELECT MAX(Id) AS NuevoId FROM Pedido;
END
GO


-- ACTUALIZAR
IF OBJECT_ID('SP_Pedido_U', 'P') IS NOT NULL
    DROP PROCEDURE SP_Pedido_U;
GO

CREATE PROCEDURE SP_Pedido_U
    @Id INT,
    @IdEstado INT,
    @Total DECIMAL(10,2)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE Pedido
    SET 
        IdEstado = @IdEstado,
        Total = @Total
    WHERE Id = @Id;
END;
GO


-- ELIMINAR
IF OBJECT_ID('SP_Pedido_D', 'P') IS NOT NULL DROP PROCEDURE SP_Pedido_D;
GO
CREATE PROCEDURE SP_Pedido_D
    @Id INT
AS
BEGIN
    -- Primero borra los detalles (por FK)
    DELETE FROM DetallePedido WHERE IdPedido = @Id;
    DELETE FROM Pedido WHERE Id = @Id;
END
GO


-- BUSCAR TODOS
IF OBJECT_ID('SP_Pedido_GetAll', 'P') IS NOT NULL DROP PROCEDURE SP_Pedido_GetAll;
GO
CREATE PROCEDURE SP_Pedido_GetAll
AS
BEGIN
    SELECT 
        p.Id,
        p.Fecha,
        pr.RazonSocial AS Proveedor,
        p.Total,
        e.Nombre AS Estado
    FROM Pedido p
    INNER JOIN Proveedor pr ON p.IdProveedor = pr.Id
    INNER JOIN EstadoPedido e ON p.IdEstado = e.Id
    ORDER BY p.Fecha DESC;
END
GO


-- BUSCAR POR ID
IF OBJECT_ID('SP_Pedido_GetById', 'P') IS NOT NULL DROP PROCEDURE SP_Pedido_GetById;
GO
CREATE PROCEDURE SP_Pedido_GetById
    @Id INT
AS
BEGIN
    -- Cabecera
    SELECT 
        p.Id,
        p.Fecha,
        p.IdProveedor,  -- 🔹 agregado para permitir PUT con IdProveedor
        pr.RazonSocial AS Proveedor,
        p.Total,
        e.Nombre AS Estado
    FROM Pedido p
    INNER JOIN Proveedor pr ON p.IdProveedor = pr.Id
    INNER JOIN EstadoPedido e ON p.IdEstado = e.Id
    WHERE p.Id = @Id;

    -- Detalle
    SELECT 
        dp.Id,
        r.Descripcion AS Repuesto,
        dp.Cantidad,
        dp.PrecioUnitario,
        dp.Subtotal
    FROM DetallePedido dp
    INNER JOIN Repuesto r ON dp.IdRepuesto = r.Id
    WHERE dp.IdPedido = @Id;
END
GO


------------------------------------------------------
-- DETALLE PEDIDO
------------------------------------------------------

-- INSERTAR
IF OBJECT_ID('SP_DetallePedido_I', 'P') IS NOT NULL DROP PROCEDURE SP_DetallePedido_I;
GO
CREATE PROCEDURE SP_DetallePedido_I
    @IdPedido INT,
    @IdRepuesto INT,
    @Cantidad INT,
    @PrecioUnitario DECIMAL(10,2)
AS
BEGIN
    INSERT INTO DetallePedido (IdPedido, IdRepuesto, Cantidad, PrecioUnitario)
    VALUES (@IdPedido, @IdRepuesto, @Cantidad, @PrecioUnitario);
END
GO


-- ELIMINAR
IF OBJECT_ID('SP_DetallePedido_D', 'P') IS NOT NULL DROP PROCEDURE SP_DetallePedido_D;
GO
CREATE PROCEDURE SP_DetallePedido_D
    @Id INT
AS
BEGIN
    DELETE FROM DetallePedido WHERE Id = @Id;
END
GO



------------------------------------------------------
-- CLIENTE
------------------------------------------------------

-- ACTUALIZAR
IF OBJECT_ID('SP_Cliente_U', 'P') IS NOT NULL DROP PROCEDURE SP_Cliente_U;
GO
CREATE PROCEDURE SP_Cliente_U
    @Id INT,
    @Dni NVARCHAR(8),
    @Nombre NVARCHAR(50),
    @Apellido NVARCHAR(50),
    @Telefono NVARCHAR(20),
    @Mail NVARCHAR(50),
    @Direccion NVARCHAR(100)
AS
BEGIN
    UPDATE Cliente
    SET Dni=@Dni, Nombre=@Nombre, Apellido=@Apellido,
        Telefono=@Telefono, Mail=@Mail, Direccion=@Direccion
    WHERE Id=@Id;
END
GO

-- ELIMINAR
IF OBJECT_ID('SP_Cliente_D', 'P') IS NOT NULL DROP PROCEDURE SP_Cliente_D;
GO
CREATE PROCEDURE SP_Cliente_D
    @Id INT
AS
BEGIN
    DELETE FROM Cliente WHERE Id=@Id;
END
GO

-- BUSCAR POR ID
IF OBJECT_ID('SP_Cliente_GetById', 'P') IS NOT NULL DROP PROCEDURE SP_Cliente_GetById;
GO
CREATE PROCEDURE SP_Cliente_GetById
    @Id INT
AS
BEGIN
    SELECT * FROM Cliente WHERE Id=@Id;
END
GO

-- BUSCAR TODOS

IF OBJECT_ID('SP_Cliente_GetAll', 'P') IS NOT NULL DROP PROCEDURE SP_Cliente_GetAll;
GO
CREATE PROCEDURE SP_Cliente_GetAll AS
BEGIN
    SELECT * FROM Cliente ORDER BY Apellido, Nombre;
END
GO
--INSERTAR

IF OBJECT_ID('SP_Cliente_I', 'P') IS NOT NULL DROP PROCEDURE SP_Cliente_I;
GO
CREATE PROCEDURE SP_Cliente_I
    @Dni NVARCHAR(8),
    @Nombre NVARCHAR(50),
    @Apellido NVARCHAR(50),
    @Telefono NVARCHAR(20),
    @Mail NVARCHAR(50),
    @Direccion NVARCHAR(100)
AS
BEGIN
    INSERT INTO Cliente (Dni, Nombre, Apellido, Telefono, Mail, Direccion)
    VALUES (@Dni, @Nombre, @Apellido, @Telefono, @Mail, @Direccion);
END
GO


------------------------------------------------------
-- MARCA
------------------------------------------------------
IF OBJECT_ID('SP_Marca_GetAll', 'P') IS NOT NULL DROP PROCEDURE SP_Marca_GetAll;
GO
CREATE PROCEDURE SP_Marca_GetAll AS
BEGIN
    SELECT * FROM Marca ORDER BY Nombre;
END
GO

IF OBJECT_ID('SP_Marca_I', 'P') IS NOT NULL DROP PROCEDURE SP_Marca_I;
GO
CREATE PROCEDURE SP_Marca_I @Nombre NVARCHAR(50)
AS
BEGIN
    INSERT INTO Marca (Nombre) VALUES (@Nombre);
END
GO

------------------------------------------------------
-- MODELO
------------------------------------------------------
IF OBJECT_ID('SP_Modelo_GetAll', 'P') IS NOT NULL DROP PROCEDURE SP_Modelo_GetAll;
GO
CREATE PROCEDURE SP_Modelo_GetAll AS
BEGIN
    SELECT mo.Id, mo.Nombre, mo.IdMarca, ma.Nombre AS Marca
    FROM Modelo mo
    INNER JOIN Marca ma ON mo.IdMarca = ma.Id
    ORDER BY mo.Nombre;
END
GO

IF OBJECT_ID('SP_Modelo_GetByMarca', 'P') IS NOT NULL DROP PROCEDURE SP_Modelo_GetByMarca;
GO
CREATE PROCEDURE SP_Modelo_GetByMarca @IdMarca INT AS
BEGIN
    SELECT * FROM Modelo WHERE IdMarca = @IdMarca ORDER BY Nombre;
END
GO


-- RUBRO
IF OBJECT_ID('SP_Rubro_GetAll', 'P') IS NOT NULL DROP PROCEDURE SP_Rubro_GetAll;
GO
CREATE PROCEDURE SP_Rubro_GetAll AS
BEGIN
    SELECT * FROM Rubro ORDER BY Nombre;
END
GO


-- REPUESTO
IF OBJECT_ID('SP_Repuesto_GetAll', 'P') IS NOT NULL DROP PROCEDURE SP_Repuesto_GetAll;
GO
CREATE PROCEDURE SP_Repuesto_GetAll AS
BEGIN
    SELECT r.Id, r.Descripcion, r.PrecioDeVenta,
           mo.Nombre AS Modelo, ma.Nombre AS Marca, ru.Nombre AS Rubro
    FROM Repuesto r
    INNER JOIN Modelo mo ON r.IdModelo = mo.Id
    INNER JOIN Marca ma ON mo.IdMarca = ma.Id
    INNER JOIN Rubro ru ON r.IdRubro = ru.Id
    ORDER BY ma.Nombre, mo.Nombre, r.Descripcion;
END
GO

IF OBJECT_ID('SP_Repuesto_Filtrar', 'P') IS NOT NULL DROP PROCEDURE SP_Repuesto_Filtrar;
GO
CREATE PROCEDURE SP_Repuesto_Filtrar
  @IdRubro INT,
  @IdMarca INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        r.Id,
        r.Descripcion,
        r.PrecioDeVenta,
        ru.Nombre AS Rubro,
        ma.Nombre AS Marca,
        mo.Nombre AS Modelo
    FROM Repuesto r
    INNER JOIN Rubro ru ON r.IdRubro = ru.Id
    INNER JOIN Modelo mo ON r.IdModelo = mo.Id
    INNER JOIN Marca ma ON mo.IdMarca = ma.Id
    WHERE r.IdRubro = @IdRubro
      AND ma.Id = @IdMarca
    ORDER BY r.Descripcion;
END
GO


------------------------------------------------------
-- PEDIDO
------------------------------------------------------

-- INSERTAR
IF OBJECT_ID('SP_Pedido_I', 'P') IS NOT NULL DROP PROCEDURE SP_Pedido_I;
GO
CREATE PROCEDURE SP_Pedido_I
    @IdProveedor INT,
    @Total DECIMAL(10,2)
AS
BEGIN
    SET NOCOUNT ON;

    -- Inserta un nuevo pedido con estado Pendiente (1)
    INSERT INTO Pedido (IdProveedor, Total, IdEstado)
    VALUES (@IdProveedor, @Total, 1);  -- 1 = Pendiente

    -- ✅ Devuelve el último Id sin usar SCOPE_IDENTITY()
    SELECT MAX(Id) AS NuevoId FROM Pedido;
END
GO


-- ACTUALIZAR
IF OBJECT_ID('SP_Pedido_U', 'P') IS NOT NULL DROP PROCEDURE SP_Pedido_U;
GO
CREATE PROCEDURE SP_Pedido_U
    @Id INT,
    @IdProveedor INT,
    @IdEstado INT,
    @Total DECIMAL(10,2)
AS
BEGIN
    UPDATE Pedido
    SET 
        IdProveedor = @IdProveedor,
        IdEstado = @IdEstado,
        Total = @Total
    WHERE Id = @Id;
END
GO


-- ELIMINAR
IF OBJECT_ID('SP_Pedido_D', 'P') IS NOT NULL DROP PROCEDURE SP_Pedido_D;
GO
CREATE PROCEDURE SP_Pedido_D
    @Id INT
AS
BEGIN
    -- Primero borra los detalles (por FK)
    DELETE FROM DetallePedido WHERE IdPedido = @Id;
    DELETE FROM Pedido WHERE Id = @Id;
END
GO


-- BUSCAR TODOS
IF OBJECT_ID('SP_Pedido_GetAll', 'P') IS NOT NULL DROP PROCEDURE SP_Pedido_GetAll;
GO
CREATE PROCEDURE SP_Pedido_GetAll
AS
BEGIN
    SELECT 
        p.Id,
        p.Fecha,
        pr.RazonSocial AS Proveedor,
        p.Total,
        e.Nombre AS Estado
    FROM Pedido p
    INNER JOIN Proveedor pr ON p.IdProveedor = pr.Id
    INNER JOIN EstadoPedido e ON p.IdEstado = e.Id
    ORDER BY p.Fecha DESC;
END
GO


-- BUSCAR POR ID
IF OBJECT_ID('SP_Pedido_GetId', 'P') IS NOT NULL DROP PROCEDURE SP_Pedido_GetId;
GO
CREATE PROCEDURE SP_Pedido_GetId
    @Id INT
AS
BEGIN
    -- Cabecera
    SELECT 
        p.Id,
        p.Fecha,
        p.IdProveedor,  -- 🔹 agregado para permitir PUT con IdProveedor
        pr.RazonSocial AS Proveedor,
        p.Total,
        e.Nombre AS Estado
    FROM Pedido p
    INNER JOIN Proveedor pr ON p.IdProveedor = pr.Id
    INNER JOIN EstadoPedido e ON p.IdEstado = e.Id
    WHERE p.Id = @Id;

    -- Detalle
    SELECT 
        dp.Id,
        r.Descripcion AS Repuesto,
        dp.Cantidad,
        dp.PrecioUnitario,
        dp.Subtotal
    FROM DetallePedido dp
    INNER JOIN Repuesto r ON dp.IdRepuesto = r.Id
    WHERE dp.IdPedido = @Id;
END
GO


------------------------------------------------------
-- DETALLE PEDIDO
------------------------------------------------------

-- INSERTAR
IF OBJECT_ID('SP_DetallePedido_I', 'P') IS NOT NULL DROP PROCEDURE SP_DetallePedido_I;
GO
CREATE PROCEDURE SP_DetallePedido_I
    @IdPedido INT,
    @IdRepuesto INT,
    @Cantidad INT,
    @PrecioUnitario DECIMAL(10,2)
AS
BEGIN
    INSERT INTO DetallePedido (IdPedido, IdRepuesto, Cantidad, PrecioUnitario)
    VALUES (@IdPedido, @IdRepuesto, @Cantidad, @PrecioUnitario);
END
GO


-- ELIMINAR
IF OBJECT_ID('SP_DetallePedido_D', 'P') IS NOT NULL DROP PROCEDURE SP_DetallePedido_D;
GO
CREATE PROCEDURE SP_DetallePedido_D
    @Id INT
AS
BEGIN
    DELETE FROM DetallePedido WHERE Id = @Id;
END
GO


------------------------------------------------------
-- USUARIOS DEL SISTEMA
------------------------------------------------------

IF OBJECT_ID('Usuario', 'U') IS NULL
BEGIN
    CREATE TABLE Usuario (
        Id INT PRIMARY KEY IDENTITY(1,1),
        Nombre NVARCHAR(50) NOT NULL,
        Correo NVARCHAR(100) UNIQUE NOT NULL,
        Clave NVARCHAR(100) NOT NULL,
        Rol NVARCHAR(20) NOT NULL CHECK (Rol IN ('Administrador', 'Invitado')),
        Activo BIT DEFAULT 1
    );

    INSERT INTO Usuario (Nombre, Correo, Clave, Rol)
    VALUES ('Administrador General', 'admin@daytona.com', 'admin123', 'Administrador');
END
GO

-- LOGIN
IF OBJECT_ID('SP_Usuario_Login', 'P') IS NOT NULL DROP PROCEDURE SP_Usuario_Login;
GO
CREATE PROCEDURE SP_Usuario_Login
    @Correo NVARCHAR(100),
    @Clave NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Id, Nombre, Rol
    FROM Usuario
    WHERE Correo = @Correo AND Clave = @Clave AND Activo = 1;
END
GO

-- LISTAR
IF OBJECT_ID('SP_Usuario_GetAll', 'P') IS NOT NULL DROP PROCEDURE SP_Usuario_GetAll;
GO
CREATE PROCEDURE SP_Usuario_GetAll
AS
BEGIN
    SELECT Id, Nombre, Correo, Rol, Activo
    FROM Usuario
    ORDER BY Nombre;
END
GO

-- INSERTAR
IF OBJECT_ID('SP_Usuario_I', 'P') IS NOT NULL DROP PROCEDURE SP_Usuario_I;
GO
CREATE PROCEDURE SP_Usuario_I
    @Nombre NVARCHAR(50),
    @Correo NVARCHAR(100),
    @Clave NVARCHAR(100),
    @Rol NVARCHAR(20)
AS
BEGIN
    INSERT INTO Usuario (Nombre, Correo, Clave, Rol)
    VALUES (@Nombre, @Correo, @Clave, @Rol);
END
GO

-- ACTUALIZAR
IF OBJECT_ID('SP_Usuario_U', 'P') IS NOT NULL DROP PROCEDURE SP_Usuario_U;
GO
CREATE PROCEDURE SP_Usuario_U
    @Id INT,
    @Nombre NVARCHAR(50),
    @Correo NVARCHAR(100),
    @Rol NVARCHAR(20),
    @Activo BIT
AS
BEGIN
    UPDATE Usuario
    SET Nombre=@Nombre, Correo=@Correo, Rol=@Rol, Activo=@Activo
    WHERE Id=@Id;
END
GO

-- ELIMINAR
IF OBJECT_ID('SP_Usuario_D', 'P') IS NOT NULL DROP PROCEDURE SP_Usuario_D;
GO
CREATE PROCEDURE SP_Usuario_D
    @Id INT
AS
BEGIN
    DELETE FROM Usuario WHERE Id=@Id;
END
GO



------------------------------------------------------
-- 🚗 MARCAS BASE
------------------------------------------------------
INSERT INTO Marca (Nombre) VALUES 
('Chevrolet'),('Citroen'),('Fiat'),('Ford'),('Importados'),
('Jeep'),('Mercedes Benz'),('Nissan'),('Peugeot'),
('Rastrojero'),('Renault'),('Toyota'),('Universales'),('Volkswagen');
GO

------------------------------------------------------
-- 🧩 RUBROS COMPLETOS
------------------------------------------------------
INSERT INTO Rubro (Nombre) VALUES
('ZAPATAS DE FRENO'),
('VALVULAS EGR "FISPA"'),
('VALVULAS EGR "LUCAS"'),
('VALVULAS EVR "FISPA"'),
('VALVULAS EVR "LUCAS"'),
('VALVULAS LIMITAD. FRENOS'),
('VALVULAS SOLENOIDES VVT "FISPA"'),
('ZAPATAS DE FRENOS "ARMETAL"'),
('VALVULAS CONTROL PRESION DE TURBO "FISPA"'),
('TENSORES DE CORREA "HUTCHINSON"'),
('TERMOSTATOS "MD" / THOMPSON'),
('TRICETAS "ETMA"'),
('TRICETAS "NAKATA"'),
('TUERCAS DE SEGURIDAD "TOP SAFE"'),
('VALVULA PCV "FISPA"'),
('VALVULA REGULADORA DE PRESION COMMON RAIL "FISPA"'),
('VALVULAS CANISTER "FISPA"'),
('SONDAS LAMBDA "LUCAS"'),
('TAZAS GRASERAS'),
('TEMPORIZADORES DE PRECALENTAMIENTO "FISPA"'),
('TENSORES DE CORREA "KUGELLAGER"'),
('TENSORES DE CORREA "DAYCO"'),
('TENSORES DE CORREA "GESPANNT"'),
('TENSORES DE CORREA "GMB"'),
('SENSORES MAP "MD"'),
('SENSORES MARIPOSA - TPS - "FISPA"'),
('SENSORES MARIPOSA - TPS - "LUCAS"'),
('SENSORES MARIPOSA - TPS - "MD"'),
('SENSORES ROTACION RPM Y DE FASE CMP "FISPA"'),
('SENSORES ROTACION RPM Y DE FASE CMP "LUCAS"'),
('SONDAS LAMBDA "MTE-THOMSON"'),
('SONDAS LAMBDA "FISPA"'),
('SENSORES DE DESGASTE "LITTON"'),
('SENSORES DE DETONACION "FISPA"'),
('SENSORES DE VELOCIDAD "ESEVEN"'),
('SENSORES DE VELOCIDAD "FISPA"'),
('SENSORES DE VELOCIDAD "LUCAS"'),
('SENSORES MAP "FISPA"'),
('SENSORES MAP "LUCAS"'),
('SENSOR DE NIVEL DE ACEITE "FISPA"'),
('SENSOR DE NIVEL DEL LIQUIDO REFRIGERANTE "MD"'),
('SENSOR DE PRESION DE COMBUSTIBLE "FISPA"'),
('SENSOR DE VACIO "MD"'),
('SENSOR EGTS "MD"'),
('SENSOR TEMP. GASES DE ESCAPE "MD"'),
('SENSORES ABS "FISPA"'),
('SENSORES ABS "MTE-THOMSON"'),
('RESISTORES "FISPA"'),
('RESORTES DE SUSPENSION "CAR"'),
('RETENES GUIA DE CAJA'),
('RULEMANES DE RUEDA'),
('RULEMANES DE RUEDA "DAYCO"'),
('RULEMANES DE RUEDA "GMB"'),
('SEMI EJES "NAKATA"'),
('POLEAS DE BOMBAS DE AGUA'),
('POLEAS DE CIGÜEÑAL'),
('PREFILTROS "FISPA"'),
('PRESOSTATOS "FISPA"'),
('RADIADORES DE AGUA Y CALEFACCION'),
('REGULADORES DE PRESION "FISPA"'),
('RELAY "FISPA"'),
('RESISTENCIAS Y MAZOS P/ELECTROVENTILADORES'),
('PARTES DE EMBRAGUE'),
('PASTILLAS DE FRENO "DURBLOC"'),
('PASTILLAS DE FRENO "FRAS-LE"'),
('PASTILLAS DE FRENO "LITTON"'),
('PASTILLAS DE FRENO "REMSA"'),
('POLEAS DE ALTERNADOR "HUTCHINSON"'),
('POLEAS DE ALTERNADOR Y DH'),
('MOTORES DE ARRANQUE Y ALTERNADORES "LUCAS"'),
('MOTORES PASO A PASO "FISPA"'),
('MOTORES PASO A PASO "LUCAS"'),
('MULTIPLES DE GOMA "YACO"'),
('PALETAS DE VENTILADOR "OMER"'),
('PARRILLAS Y BRAZOS DE SUSPENSION'),
('PARRILLAS Y BRAZOS DE SUSPENSION "NAKATA"'),
('PARRILLAS Y BRAZOS DE SUSPENSION "THOMPSON"'),
('MANGUERAS "YACO"'),
('MAZAS DE RUEDA'),
('MAZAS DE RUEDA "DAYCO"'),
('MAZAS DE RUEDA "NAKATA"'),
('MODULO DE CONTROL DE BOMBA "FISPA"'),
('MODULOS DE IGNICION "FISPA"'),
('MODULOS DE IGNICION "LUCAS"'),
('KIT FILTROS Y O RINGS'),
('LAMPARAS "KOBO"'),
('LIQUIDO PARA FRENOS "TENSA"'),
('LIQUIDOS REFRIGERANTES "ARMETAL"'),
('LIQUIDOS REFRIGERANTES "VMG"'),
('LLAVES CONMUTADORAS "VUARAM"'),
('LLAVES TECLAS "VUARAM"'),
('MANGUERAS "FREPLAST" DE PVC'),
('KIT CABLE/BUJIA "LUCAS"'),
('KIT DE CADENA DE DISTRIBUCION'),
('KIT DE CADENA DE DISTRIBUCION "DAYCO"'),
('KIT DE DISTRIBUCION "DAYCO"'),
('KIT DE DISTRIBUCION "HUTCHINSON"'),
('KIT DE DISTRIBUCION "VMG"'),
('KIT DE FRENOS "FREMAX - FRASLE"'),
('JUNTA DE CARTER "MEYRO"'),
('JUNTA MULTIPLE DE ADMISION "MEYRO"'),
('JUNTA MULTIPLE DE ESCAPE "MEYRO"'),
('JUNTA SALIDA DE ESCAPE "MEYRO"'),
('JUNTA TAPA DE CILINDRO "MEYRO"'),
('JUNTA TAPA DE VALVULAS "MEYRO"'),
('JUNTAS HOMOCINETICAS "NAKATA"'),
('JUNTAS HOMOCINETICAS "SPICER"'),
('INSTRUMENTAL "MD"'),
('INTERRUPTORES DE IGNICION "VUARAM"'),
('INYECTORES "FISPA"'),
('INYECTORES "LUCAS"'),
('JUEGOS DESCARBONIZACION "MEYRO"'),
('JUEGOS JUNTAS P/INYECCION ELECTRONICA "FISPA"'),
('JUEGOS REPAR. BOMBAS AGUA'),
('FLOTANTES Y TAPAS DE COMBUSTIBLE'),
('FUELLES DE DIRECCION "SERRAT"'),
('FUELLES DE SUSPENSION "SERRAT"'),
('FUELLES DE TRANSMISION "SERRAT"'),
('FUELLES KIT DIRECCION "SERRAT"'),
('FUELLES KIT TRANSMISION "SERRAT"'),
('GARGANTAS AGUA/ANTECUERPOS'),
('HERRAMIENTAS'),
('EXTREMOS DE DIR/ROT/BARRA "TIPER"'),
('EXTREMOS DE DIR/ROT/BARRA "NAKATA"'),
('FICHAS DE INYECCION "FISPA"'),
('FILTROS DE COMBUSTIBLE DIESEL "FISPA"'),
('FILTROS DE COMBUSTIBLE DIESEL "LUCAS"'),
('FILTROS P/COMBUSTIBLE DE INYECCION "FISPA"'),
('FLEXIBLES HIDRAULICOS'),
('ELECTROV P/ BOMB INYECT "FISPA"'),
('ELECTROV P/ BOMB INYECT "MD"'),
('ELECTROVENTILADORES "OMER"'),
('EMBRAGUES "PHC-VALEO"'),
('EMBRAGUES "WOBRON"'),
('ENFRIADORES DE ACEITE'),
('ESCOBILLAS "EKTION"'),
('CUERPOS MARIPOSA "LUCAS"'),
('DISCOS DE FRENO "FREMAX"'),
('DISCOS DE FRENO "LITTON"'),
('DISCOS DE FRENO "RAYBESTOS"'),
('EJES PARRILLA SUSPENSION "DUPLA"'),
('EJES SECTORES Y SINFINES "BR"'),
('ELECTROV P/ BOMB INYECT "ELIFEL"'),
('BUJIAS PRE-POST CALENTAMIENTO "LUCAS"'),
('BULBO ELECTROVENTILADOR "FISPA"'),
('BULBO ELECTROVENTILADOR "GENY"'),
('BULBO ELECTROVENTILADOR "MD"'),
('BULBO INTERR LUZ PUERTA'),
('BULBO INTERR LUZ PUERTA "GENY"'),
('BULBO INTERR RETROMARCHA "GENY"'),
('BOMBAS DEPRESORAS "RM"'),
('BOMBAS ELECTRICAS DE COMBUSTIBLE "FISPA"'),
('BOMBAS ELECTRICAS DE COMBUSTIBLE "LUCAS"'),
('BOMBAS UREA "FISPA"'),
('BUJES "CAPEMI"'),
('BUJES SILENTBLOCK'),
('BUJES DE IGNICION "LUCAS"'),
('BOMBAS DE ALTA PRESION "FISPA"'),
('BOMBAS DE COMBUSTIBLE "ELIFEL"'),
('BOMBAS DE DIRECCION HIDRAULICA'),
('BOMBAS DE EMBRAGUE'),
('BOMBAS DE EMBRAGUE "TENSA"'),
('BOMBAS DE FRENO'),
('BOMBAS DE FRENO "TENSA"'),
('BOBINAS DE IGNICION "FISPA"'),
('BOBINAS DE IGNICION "LUCAS"'),
('BOCINAS "DIVIAO"'),
('BOMBAS DE ACEITE'),
('BOMBAS DE AGUA "GMB"'),
('BOMBAS DE AGUA "LUCAS"'),
('BOMBAS DE AGUA "VMG"'),
('BOMBAS DE AGUA "VMG" LINEA MIL'),
('BARRAS CARDANICAS "DINES"'),
('BARRAS CARDANICAS "LEO"'),
('BARRAS TENSORAS "DUPLA"'),
('BIDON RECUPERADOR DE AGUA/TAPAS PLASTICAS'),
('BIELETAS DE DIRECCION Y SUSPENSION'),
('BIELETAS DE DIRECCION Y SUSPENSION "NAKATA"'),
('BIELETAS DE DIRECCION Y SUSPENSION "THOMPSON"'),
('AMORTIGUADORES "NAKATA"'),
('ANILLOS DE SINCRONIZADOS'),
('ANTIVIBRANTES "HUTCHINSON"'),
('ARTICULO DE GOMA "REY GOMA"'),
('ARTICULOS DE GOMA'),
('AXIALES / PRECAPS "NAKATA"'),
('AXIALES / PRECAPS "THOMPSON"'),
('AXIALES / PRECAPS "TIPER"'),
('ABRAZADERAS "PERFECTO"'),
('ACCESORIOS DE BOMBAS/TUBOS COMB."FISPA"'),
('ACEITES Y LUBRICANTES "TOTAL"'),
('ACOPLES VISCOSOS'),
('ACTUADORES HIDRAULICOS'),
('ADHESIVOS/SELLADORES/LUBRICANTES/OTROS'),
('AMORTIGUADOR DE COMPUERTA "NAKATA"');


------------------------------------------------------------
-- 🚘 CHEVROLET
------------------------------------------------------------
INSERT INTO Modelo (Nombre, IdMarca) VALUES 
('Onix', 1),
('Prisma', 1),
('Cruze', 1),
('S10', 1),
('Tracker', 1),
('Spin', 1);

------------------------------------------------------------
-- 🚗 CITROËN
------------------------------------------------------------
INSERT INTO Modelo (Nombre, IdMarca) VALUES 
('C3', 2),
('C4 Lounge', 2),
('Berlingo', 2),
('C-Elysée', 2),
('Jumper', 2);

------------------------------------------------------------
-- 🚙 FIAT
------------------------------------------------------------
INSERT INTO Modelo (Nombre, IdMarca) VALUES 
('Palio', 3),
('Uno', 3),
('Cronos', 3),
('Strada', 3),
('Toro', 3),
('Fiorino', 3);

------------------------------------------------------------
-- 🚘 FORD
------------------------------------------------------------
INSERT INTO Modelo (Nombre, IdMarca) VALUES 
('Fiesta', 4),
('Focus', 4),
('Ecosport', 4),
('Ka', 4),
('Ranger', 4),
('Transit', 4);

------------------------------------------------------------
-- 🌍 IMPORTADOS
------------------------------------------------------------
INSERT INTO Modelo (Nombre, IdMarca) VALUES 
('A3', 5),
('Q5', 5),
('Serie 3', 5),
('Clase C', 5),
('A4', 5);

------------------------------------------------------------
-- 🚙 JEEP
------------------------------------------------------------
INSERT INTO Modelo (Nombre, IdMarca) VALUES 
('Renegade', 6),
('Compass', 6),
('Cherokee', 6),
('Grand Cherokee', 6);

------------------------------------------------------------
-- 🚗 MERCEDES BENZ
------------------------------------------------------------
INSERT INTO Modelo (Nombre, IdMarca) VALUES 
('Clase A', 7),
('Clase B', 7),
('Sprinter', 7),
('Vito', 7),
('Actros', 7);

------------------------------------------------------------
-- 🚙 NISSAN
------------------------------------------------------------
INSERT INTO Modelo (Nombre, IdMarca) VALUES 
('March', 8),
('Versa', 8),
('Frontier', 8),
('Kicks', 8),
('Sentra', 8);

------------------------------------------------------------
-- 🚗 PEUGEOT
------------------------------------------------------------
INSERT INTO Modelo (Nombre, IdMarca) VALUES 
('208', 9),
('2008', 9),
('308', 9),
('Partner', 9),
('Expert', 9),
('408', 9);

------------------------------------------------------------
-- 🚜 RASTROJERO
------------------------------------------------------------
INSERT INTO Modelo (Nombre, IdMarca) VALUES 
('Diesel', 10),
('Pick-Up', 10),
('F-70', 10);

------------------------------------------------------------
-- 🚗 RENAULT
------------------------------------------------------------
INSERT INTO Modelo (Nombre, IdMarca) VALUES 
('Kangoo', 11),
('Sandero', 11),
('Stepway', 11),
('Logan', 11),
('Duster', 11),
('Alaskan', 11);

------------------------------------------------------------
-- 🚙 TOYOTA
------------------------------------------------------------
INSERT INTO Modelo (Nombre, IdMarca) VALUES 
('Corolla', 12),
('Hilux', 12),
('Etios', 12),
('SW4', 12),
('Yaris', 12),
('RAV4', 12);

------------------------------------------------------------
-- 🧩 UNIVERSALES
------------------------------------------------------------
INSERT INTO Modelo (Nombre, IdMarca) VALUES 
('Universal 1', 13),
('Universal 2', 13),
('Universal 3', 13);

------------------------------------------------------------
-- 🚘 VOLKSWAGEN
------------------------------------------------------------
INSERT INTO Modelo (Nombre, IdMarca) VALUES 
('Gol', 14),
('Voyage', 14),
('Polo', 14),
('Amarok', 14),
('Saveiro', 14),
('T-Cross', 14);
GO
