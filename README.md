# Daytona Inyección — Sistema de Gestión

Sistema web de gestión para un negocio de repuestos automotores.
Proyecto de Práctica Profesionalizante — Tecnicatura en Análisis de Sistemas.

## Tecnologías

- ASP.NET Web API sobre .NET Framework 4.5
- SQL Server 2014, con ADO.NET y procedimientos almacenados
- HTML, JavaScript y Bootstrap 5 en el frontend
- Autenticación con JWT

## Módulos

Catálogo de repuestos, stock, ventas, presupuestos, pedidos a proveedor,
caja, cuenta corriente de clientes y buscador multiproveedor sobre las
listas de precios.

## Puesta en marcha

El repositorio **no incluye los archivos de configuración**, porque
contienen la cadena de conexión y la clave de firma de los tokens.

1. Copiar `DaytonaInyeccionTesis/WebApi/Web.config.ejemplo` como
   `Web.config` y completar la cadena de conexión y la clave JWT.
2. Copiar `Pages/config.ejemplo.js` como `config.js` y ajustar la
   dirección del backend.
3. Restaurar la base de datos desde `BaseDeDatos.sql`.
4. Compilar y ejecutar.

Sin los pasos 1 y 2 la aplicación no arranca.
