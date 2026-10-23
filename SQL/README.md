# Scripts SQL de Daytona

Historial de cambios a la base desde el estado inicial (BaseDeDatos.sql, noviembre 2025) hasta hoy. Cada script se corrió una vez, en orden, sobre la base real.

## Carpetas

- `scripts/` — los cambios en orden (01 a 57). Sirven para saber qué se hizo y cuándo; no hace falta volver a correrlos sobre una base que ya los tiene.
- `no-correr-en-produccion/` — el reset de datos de prueba (08c) y la carga de datos de demostración (22). Borran o inventan datos. Nunca sobre DaytonaInyeccion.
- `00-Crear-base-dev.sql` — arma DaytonaInyeccion_Dev como copia de la real para trabajar la migración. A la real solo la lee (backup COPY_ONLY).

## Cuidado

Casi todos los scripts empiezan con `USE [DaytonaInyeccion]`, o sea, apuntan a la base real aunque SSMS esté parado en otra. Para probar uno contra la base de desarrollo hay que cambiar esa línea por `USE [DaytonaInyeccion_Dev]` antes de correrlo.

## Estado actual

BaseDeDatos.sql quedó viejo: no tiene nada de caja, compras, proveedores ni notas. Para tener el esquema completo de hoy, la fuente es un backup o un .bacpac de la base real, no ese archivo.
